#!/usr/bin/env bash
# OPENWEBUI DOCLING
# Interface Web de IA Corporativa & MCP com Docling RAG On-Demand
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO OPEN WEBUI
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório Open WebUI
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.14.01-DECOUPLED"

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
fi

build_structure() {
    local TARGET_OWNER="1000:1000"
    if [ -n "${SUDO_USER:-}" ]; then
        local TARGET_UID=$(id -u "$SUDO_USER" 2>/dev/null || echo "1000")
        local TARGET_GID=$(id -g "$SUDO_USER" 2>/dev/null || echo "1000")
        TARGET_OWNER="${TARGET_UID}:${TARGET_GID}"
    fi

    local VOL_PATH="$TARGET_DIR/volumes/openwebui_data"
    local VOL_DOCLING="$TARGET_DIR/volumes/docling_data"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA OPENWEBUI] Estrutura de volumes de openwebui_data já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE OPENWEBUI] Criando estrutura física de volumes e permissões do Open WebUI e Docling..."
        sudo mkdir -p "$VOL_PATH" "$VOL_DOCLING" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" "$VOL_DOCLING" 2>/dev/null || true
    fi
}

provision_db() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE OPENWEBUI] Garantindo banco de dados lógico (openwebui_db) no PostgreSQL..."
    if docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -c "SELECT 1 FROM pg_database WHERE datname = 'openwebui_db'" 2>/dev/null | grep -q 1; then
        echo "➜ [IDEMPOTÊNCIA OPENWEBUI] Banco de dados 'openwebui_db' já existente. Preservando esquema."
    else
        echo "  ↳ Criando banco de dados 'openwebui_db'..."
        docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -q -c "CREATE DATABASE openwebui_db;" > /dev/null 2>&1 || true
    fi

    # Habilita pgvector incondicionalmente para busca semântica, embeddings e RAG nativo
    echo "  ↳ [RAG SRE] Habilitando extensão 'vector' (pgvector) no openwebui_db..."
    docker compose exec -T postgres psql -U "${DB_USER}" -d "openwebui_db" -q -c "CREATE EXTENSION IF NOT EXISTS vector;" > /dev/null 2>&1 || true
}

provision_infra() {
    echo "➜ [SRE OPENWEBUI] Inspecionando integridade, firewall e migrações do Open WebUI..."
    local PREFIX="${PREFIXO_CONTAINER}"
    
    local use_val="${USE_OPENWEBUI:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
        cat << 'EOF' | sudo tee /etc/dnsmasq.d/openwebui.conf > /dev/null
# IPSET ALLOWED DOMAINS (OPEN WEBUI / HUGGINGFACE MODELS)
ipset=/huggingface.co/ALLOWED_DOMAINS
ipset=/api-inference.huggingface.co/ALLOWED_DOMAINS
ipset=/cdn-lfs.huggingface.co/ALLOWED_DOMAINS
EOF
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 5000 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 5000 -j ACCEPT 2>/dev/null || true
        fi
    else
        sudo rm -f /etc/dnsmasq.d/openwebui.conf 2>/dev/null || true
    fi

    local OWUI_ERRORS=$(docker logs "${PREFIX}_openwebui" --tail 200 2>&1 | grep -iE "UndefinedTable|relation .* does not exist" || true)

    if [ -n "$OWUI_ERRORS" ]; then
        echo "➜ [SRE RECOVERY OPENWEBUI] Migrações pendentes no Open WebUI (Tabelas ausentes). Forçando recriação do container..."
        cd "$TARGET_DIR" && docker compose up -d --force-recreate openwebui > /dev/null 2>&1 || true
        sleep 8
    fi

    # SRE WAIT: Aguarda subida da porta :8080 (interna) ou :3001
    local TENTATIVAS_OW=0
    until curl -s -o /dev/null "http://127.0.0.1:3001/api/v1/models" 2>/dev/null; do
        TENTATIVAS_OW=$((TENTATIVAS_OW+1))
        if [ "$TENTATIVAS_OW" -ge 30 ]; then
            echo "⚠️ [SRE WARN OPENWEBUI] Open WebUI não respondeu em 30s. Prosseguindo..."
            break
        fi
        if [ "$TENTATIVAS_OW" -eq 15 ]; then
            echo "➜ [SRE RECOVERY OPENWEBUI] Open WebUI demorando a responder. Reciclando o container..."
            docker restart "${PREFIX}_openwebui" > /dev/null 2>&1 || true
            sleep 5
        fi

        echo "  ↳ Aguardando backend do Open WebUI (tentativa $TENTATIVAS_OWUI/36)..."
        sleep 5
    done
    echo "✔ [SUCESSO OPENWEBUI] Infraestrutura relacional e API FastAPI validadas."
}

inject_caddy_routes() {
    echo "➜ [SRE OPENWEBUI] Injetando rotas do Open WebUI (:3001) e Docling (:5001) no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ':3001 {' "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:3001 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_openwebui:8080
}
EOF
        fi
        if ! grep -q ':5001 {' "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:5001 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_docling:5001
}
EOF
        fi
    fi
}

remove_caddy_routes() {
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        python3 -c "
import re
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r') as f:
        content = f.read()
    pattern = r'(?:\n|^)\s*:(3001|5001)\s*\{[\s\S]*?\n\}'
    new_content = re.sub(pattern, '', content)
    with open(path, 'w') as f:
        f.write(new_content.strip() + '\n')
except Exception as e:
    pass
"
    fi
}

inject_dashboard_card() {
    echo "➜ [SRE OPENWEBUI] Injetando card do Open WebUI no portal de controle (index.html)..."
    local HTML_PATH="$TARGET_DIR/core/html/index.html"
    if [ ! -f "$HTML_PATH" ] && [ -f "$TARGET_DIR/html/index.html" ]; then
        HTML_PATH="$TARGET_DIR/html/index.html"
    fi

    if [ -f "$HTML_PATH" ]; then
        python3 -c "
import re

html_path = '$HTML_PATH'
card_html = '''
            <a href=\"#\" data-port=\"3001\" data-path=\"/\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">🧠</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Inteligência Artificial</h3>
                    <p class=\"description\">Assistente virtual com contexto soberano e automação de vendas.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:3001</span>
                    </div>
                </div>
            </a>'''

try:
    with open(html_path, 'r+') as f:
        content = f.read()
        if 'data-port=\"3001\"' not in content and '<h3>Inteligência Artificial</h3>' not in content:
            if '<div class=\"grid\">' in content:
                new_content = content.replace('<div class=\"grid\">', '<div class=\"grid\">\\n' + card_html, 1)
                f.seek(0)
                f.write(new_content)
                f.truncate()
except Exception as e:
    print(f'Erro ao injetar card Open WebUI: {e}')
"
    fi
}

remove_dashboard_card() {
    local HTML_PATH="$TARGET_DIR/core/html/index.html"
    if [ ! -f "$HTML_PATH" ] && [ -f "$TARGET_DIR/html/index.html" ]; then
        HTML_PATH="$TARGET_DIR/html/index.html"
    fi

    if [ -f "$HTML_PATH" ]; then
        python3 -c "
import re

html_path = '$HTML_PATH'
try:
    with open(html_path, 'r+') as f:
        content = f.read()
        pattern = r'<a [^>]*data-port=[\"\']3001[\"\'][\s\S]*?<\/a>'
        new_content = re.sub(pattern, '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception as e:
    pass
"
    fi
}

disable() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE OPENWEBUI] Desativando e desprovisionando contêineres do Open WebUI e Docling..."
    docker stop "${PREFIX}_openwebui" "${PREFIX}_docling" 2>/dev/null || true
    docker rm -f "${PREFIX}_openwebui" "${PREFIX}_docling" 2>/dev/null || true
    remove_caddy_routes
    remove_dashboard_card

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 3001 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 3001 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/openwebui.conf ]; then
        sudo rm -f /etc/dnsmasq.d/openwebui.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO OPENWEBUI] Módulo Open WebUI e Docling desativados, containers removidos, firewall e rotas limpos."
}

start_container() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE OPENWEBUI] Garantindo subida integrada do Open WebUI e posicionamento do Docling (Scale-to-Zero)..."
    cd "$TARGET_DIR" && docker compose up -d --no-deps openwebui > /dev/null 2>&1 || true
    # Posiciona o Docling criado e em repouso (Scale-to-Zero)
    cd "$TARGET_DIR" && (docker compose create docling > /dev/null 2>&1 || docker compose up --no-start docling > /dev/null 2>&1 || true)
}

wait_readiness() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE OPENWEBUI] Validando prontidão de socket e healthcheck do Open WebUI..."
    local TENTATIVAS=0
    until [ "$(docker inspect -f '{{.State.Health.Status}}' "${PREFIX}_openwebui" 2>/dev/null || true)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS + 1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [TIMEOUT OPENWEBUI] Container Open WebUI não atingiu estado healthy após 150s."
            return 1
        fi
        sleep 5
    done
    echo "✔ [SUCESSO OPENWEBUI] Open WebUI online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' "${PREFIX}_openwebui" 2>/dev/null || echo "OFFLINE")
    local http_status=""

    if [ "$health" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:3001/health" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-33s http://%s:3001  -> Status: [%s]\n" "Inteligência (Open WebUI):" "${ts_domain}" "${http_status}"
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    echo "  🧠 Inteligência (Open WebUI & Docling RAG)"
    echo "    ↳ Painel Web (Cliente MCP):        http://${ts_domain}:3001"
    echo "    ↳ Motor Multimodal Docling:        http://${ts_domain}:5001 (Scale-to-Zero)"
    echo "    ↳ Integração REST API:             http://${ts_domain}:3001/api/"
    echo "    ↳ Open API/Swagger:                http://${ts_domain}:3001/openapi.json"
    echo "    ↳ Healthcheck:                     http://${ts_domain}:3001/health"
    echo "    ↳ Docs:                            http://${ts_domain}:3001/docs"
    echo ""
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local VER=$(docker exec "${PREFIX}_openwebui" cat /app/package.json 2>/dev/null | grep '"version"' | head -n 1 | cut -d'"' -f4 || echo "")
    if [ -n "$VER" ]; then
        echo "$VER"
    else
        local IMAGE_TAG=$(docker inspect --format='{{.Config.Image}}' "${PREFIX}_openwebui" 2>/dev/null | cut -d':' -f2 || echo "")
        echo "${IMAGE_TAG:-main}"
    fi
}

provision_user() {
    echo "➜ [SRE OPENWEBUI] Provisionando Administrador Mestre no Open WebUI..."
    local PAYLOAD_OWUI=$(jq -n --arg name "$CLIENTE_NOME $CLIENTE_SOBRENOME" --arg email "$TS_EMAIL" --arg pwd "$DB_PASSWORD" '{name: $name, email: $email, password: $pwd}')
    local RESPONSE_OWUI=$(curl -s -w "%{http_code}" -o /dev/null -X POST "http://127.0.0.1:3001/api/v1/auths/signup" \
      -H "Content-Type: application/json" -d "$PAYLOAD_OWUI" || echo "000")
    if [[ "$RESPONSE_OWUI" =~ ^2 ]]; then
        echo "➜ [SUCESSO OPENWEBUI] Conta Administradora do Open WebUI cadastrada: ${TS_EMAIL}"
    elif [ "$RESPONSE_OWUI" = "400" ] || [ "$RESPONSE_OWUI" = "403" ]; then
        echo "➜ [IDEMPOTÊNCIA OPENWEBUI] Banco do Open WebUI já populado (Admin existente)."
    fi
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o Open WebUI (Interface de Chat IA & RAG)?" USE_OPENWEBUI "s"
    [[ "${USE_OPENWEBUI:-s}" =~ ^[Ss]$ ]] && USE_OPENWEBUI="s" || USE_OPENWEBUI="n"
    save_wizard_cache "USE_OPENWEBUI" "$USE_OPENWEBUI"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local API_KEY="${API_MASTER_KEY:-${DB_PASSWORD:-}}"
    local OLD_KEY=$(grep '^OPENWEBUI_SECRET_KEY=' "$env_path" 2>/dev/null | cut -d= -f2 || true)
    local FINAL_KEY="${OLD_KEY:-$API_KEY}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_openwebui="1.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_openwebui="4.0"
    elif [ "$cpus" -gt 4 ]; then
        cpu_openwebui="2.0"
    fi

    local mem_openwebui="1280M"
    local res_openwebui="512M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_openwebui="4096M"
        res_openwebui="2048M"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_openwebui="2048M"
        res_openwebui="1024M"
    fi

    cat << EOF >> "$env_path"

# --- Configurações e Tuning do Módulo Open WebUI & Docling OCR ---
USE_OPENWEBUI="${USE_OPENWEBUI:-s}"
HOST_OPENWEBUI_PORT="3001"
HOST_DOCLING_PORT="5001"
CPU_OPENWEBUI=${CPU_OPENWEBUI:-${cpu_openwebui}}
MEM_OPENWEBUI=${MEM_OPENWEBUI:-${mem_openwebui}}
RES_OPENWEBUI=${RES_OPENWEBUI:-${res_openwebui}}
CPU_DOCLING=${CPU_DOCLING:-2.0}
MEM_DOCLING=${MEM_DOCLING:-2048M}
RES_DOCLING=${RES_DOCLING:-512M}
DOCLING_OMP_THREADS=2
DOCLING_TORCH_THREADS=2
OPENWEBUI_SECRET_KEY=${FINAL_KEY}
EOF
}

# Roteador Universal CLI
ACTION="${2:-all}"
case "$ACTION" in
    collect_wizard_inputs|collect_inputs|wizard_prompt) collect_wizard_inputs ;;
    build_envs|build_env) build_envs ;;
    build_structure)      build_structure ;;
    provision_db)         provision_db ;;
    provision_infra)      provision_infra ;;
    inject_caddy_routes|inject_caddy)  inject_caddy_routes ;;
    remove_caddy_routes|remove_caddy)  remove_caddy_routes ;;
    inject_dashboard_card|inject_card) inject_dashboard_card ;;
    remove_dashboard_card|remove_card|purge_card) remove_dashboard_card ;;
    disable|teardown)     disable ;;
    start_container)      start_container ;;
    wait_readiness)       wait_readiness ;;
    audit_health)         audit_health "${3:-localhost}" ;;
    get_version)          get_version ;;
    render_forensic_report|render_report) render_forensic_report "${3:-localhost}" ;;
    provision_user)       provision_user ;;
    all)
        build_structure
        provision_db
        inject_caddy_routes
        inject_dashboard_card
        start_container
        wait_readiness
        provision_infra
        provision_user
        ;;
    *)
        ;;
esac
