#!/usr/bin/env bash
# EVOLUTION
# API de Conexão WhatsApp Webhooks
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO EVOLUTION API (WHATSAPP)
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório Evolution API
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.11.01-DECOUPLED"

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

    local VOL_PATH="$TARGET_DIR/volumes/evolution_instances"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA EVOLUTION] Estrutura de volumes de evolution_instances já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE EVOLUTION] Criando estrutura física de volumes e permissões da Evolution API..."
        sudo mkdir -p "$VOL_PATH" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" 2>/dev/null || true
    fi
}

provision_db() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE EVOLUTION] Garantindo banco de dados lógico (evolution_db) no PostgreSQL..."
    local PREFIX="${PREFIXO_CONTAINER}"
    if docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -c "SELECT 1 FROM pg_database WHERE datname = 'evolution_db'" 2>/dev/null | grep -q 1; then
        echo "➜ [IDEMPOTÊNCIA EVOLUTION] Banco de dados 'evolution_db' já existente. Preservando esquema."
    else
        echo "  ↳ Criando banco de dados 'evolution_db'..."
        docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -q -c "CREATE DATABASE evolution_db;" > /dev/null 2>&1 || true
    fi
}

provision_infra() {
    echo "➜ [SRE EVOLUTION] Aplicando firewall e patch de assets no Evolution Manager (v2.3.7)..."
    local use_val="${USE_EVOLUTION:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
        cat << 'EOF' | sudo tee /etc/dnsmasq.d/evolution.conf > /dev/null
# IPSET ALLOWED DOMAINS (EVOLUTION API / META WHATSAPP)
ipset=/graph.facebook.com/ALLOWED_DOMAINS
EOF
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 18081 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 18081 -j ACCEPT 2>/dev/null || true
        fi
    else
        sudo rm -f /etc/dnsmasq.d/evolution.conf 2>/dev/null || true
    fi
    docker compose exec -T -u root evolution sh -c '
        # Copia o logo público como favicon oficial na raiz servida do manager
        if [ -f /evolution/public/images/evolution-logo.png ]; then
            cp /evolution/public/images/evolution-logo.png /evolution/manager/dist/favicon.png 2>/dev/null || true
        fi

        # Patch no index.html do manager para carregar o favicon
        if [ -f /evolution/manager/dist/index.html ]; then
            sed -i -e "s|https://evolution-api.com/files/evo/favicon.svg|/manager/favicon.png|g" \
                   -e "s|href=\"/favicon.svg\"|href=\"/manager/favicon.png\"|g" \
                   -e "s|href=\"favicon.svg\"|href=\"/manager/favicon.png\"|g" \
                   -e "s|type=\"image/svg+xml\"|type=\"image/png\"|g" /evolution/manager/dist/index.html 2>/dev/null || true
        fi

        # Patch nos bundles JS para carregar logos e favicons locais em vez de CDN externa
        if [ -d /evolution/manager/dist/assets ]; then
            find /evolution/manager/dist/assets -type f -name "*.js" -exec sed -i \
                -e "s|https://evolution-api.com/files/evo/evolution-logo-white.svg|/assets/images/evolution-logo.png|g" \
                -e "s|https://evolution-api.com/files/evo/evolution-logo.svg|/assets/images/evolution-logo.png|g" \
                -e "s|https://evolution-api.com/files/evo/favicon.svg|/manager/favicon.png|g" {} + 2>/dev/null || true
        fi
    ' 2>/dev/null || true

    echo "✔ [SUCESSO EVOLUTION] Infra provisionada: DB + assets do manager configurados."
}

inject_caddy_routes() {
    echo "➜ [SRE EVOLUTION] Injetando rotas da Evolution API no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_evo="${HOST_EVO_PORT:-18081}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ":${port_evo} {" "$CADDYFILE_PATH" && ! grep -q 'reverse_proxy.*_evolution:8080' "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:${port_evo} {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_evolution:8080 {
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
        header_up X-Real-IP {remote_host}
    }
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
    local port_evo="${HOST_EVO_PORT:-18081}"
    if [ -f "$CADDYFILE_PATH" ] && { grep -q ":${port_evo} {" "$CADDYFILE_PATH" || grep -q ':8081 {' "$CADDYFILE_PATH"; }; then
        echo "➜ [SRE EVOLUTION] Removendo rotas da Evolution API do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:${port_evo}\s*\{[\s\S]*?\}', '', content)
        new_content = re.sub(r'\s*:8081\s*\{[\s\S]*?\}', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    echo "➜ [SRE EVOLUTION] Injetando card da Evolution API no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local PREFIX="${PREFIXO_CONTAINER}"
    local EVO_PORT="${HOST_EVO_PORT:-18081}"

    if [ -f "$INDEX_PATH" ] && ! grep -q "data-port=\"$EVO_PORT\"" "$INDEX_PATH" && ! grep -q 'Evolution API' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"$EVO_PORT\" data-path=\"/manager\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">💬</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Evolution API</h3>
                    <p class=\"description\">Gateway de integração oficial do WhatsApp com suporte a instâncias e webhooks.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:$EVO_PORT</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'Evolution API' not in content:
            target = '</div>\n\n        <div class=\"footer-note\">'
            if target in content:
                new_content = content.replace(target, card + '        ' + target)
                f.seek(0)
                f.write(new_content)
                f.truncate()
except Exception as e:
    pass
" 2>/dev/null || true
    fi
}


remove_dashboard_card() {
    echo "➜ [SRE EVOLUTION] Purgando card da Evolution API no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local EVO_PORT="${HOST_EVO_PORT:-18081}"
    if [ -f "$INDEX_PATH" ] && ( grep -q 'Evolution API' "$INDEX_PATH" || grep -q "data-port=\"$EVO_PORT\"" "$INDEX_PATH" || grep -q 'data-port="8081"' "$INDEX_PATH" ); then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^\>]*data-port=\"(8081|$EVO_PORT)\"[\s\S]*?</a>\s*', '', content)
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^\>]*Evolution API[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE EVOLUTION] Desativando módulo Evolution API..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_evolution" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    local port_evo="${HOST_EVO_PORT:-18081}"
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport "$port_evo" -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_evo" -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/evolution.conf ]; then
        sudo rm -f /etc/dnsmasq.d/evolution.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO EVOLUTION] Módulo Evolution API desativado, containers removidos, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE EVOLUTION] Subindo container da Evolution API..."
    cd "$TARGET_DIR"
    sudo docker compose up -d evolution 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE EVOLUTION] Validando prontidão de socket e healthcheck da Evolution API..."
    local TENTATIVAS=0
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_evo="${HOST_EVO_PORT:-18081}"

    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_evolution 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN EVOLUTION] Evolution API demorou a responder após 60s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done

    echo "➜ [SRE EVOLUTION] Validando integridade da conexão Prisma com PgBouncer..."
    local EVO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "apikey: ${EVOLUTION_API_KEY:-${DB_PASSWORD}}" "http://127.0.0.1:${port_evo}/instance/fetchInstances" 2>/dev/null || echo "000")

    if [ "$EVO_STATUS" = "500" ]; then
        echo "➜ [SRE RECOVERY EVOLUTION] Deadlock de conexão detectado no Prisma ORM (HTTP 500). Reciclando a Evolution API..."
        docker compose restart evolution > /dev/null 2>&1 || true
        sleep 5
        TENTATIVAS=0
        until [ "$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "apikey: ${EVOLUTION_API_KEY:-${DB_PASSWORD}}" "http://127.0.0.1:${port_evo}/instance/fetchInstances" 2>/dev/null || echo "200")" = "200" ]; do
            TENTATIVAS=$((TENTATIVAS+1))
            [ "$TENTATIVAS" -ge 20 ] && { echo "⚠️ [SRE WARN EVOLUTION] Evolution não estabilizou totalmente após restart SRE. Prosseguindo..."; return 1 2>/dev/null || true; }
            sleep 5
        done
        echo "➜ [SUCESSO EVOLUTION] Evolution API destravada e operando perfeitamente (HTTP 200)."
    fi
    echo "✔ [SUCESSO EVOLUTION] Evolution API online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_evo="${HOST_EVO_PORT:-18081}"
    local health_status=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_evolution 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"
    if [ "$health_status" = "healthy" ]; then
        http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${port_evo}/" 2>/dev/null || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:%s  -> Status: [%s]\n" "WhatsApp API (Evolution):" "${ts_domain}" "${port_evo}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_evolution"
    sudo docker exec "$container_name" node -e 'console.log(require("./package.json").version)' 2>/dev/null || echo "v2.3.7"
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local evo_url="${SERVER_URL:-http://${ts_domain}:${HOST_EVO_PORT:-8081}}"
    echo "  💬 WhatsApp API (Evolution)"
    echo "    ↳ API Principal (SERVER_URL):      ${evo_url}"
    echo "    ↳ Evolution Manager:               http://${ts_domain}:${HOST_EVO_PORT:-8081}/manager"
    echo "    ↳ Healthcheck:                     http://${ts_domain}:${HOST_EVO_PORT:-8081}/manager/health"
    echo ""
}

provision_user() {
    echo "➜ [SRE EVOLUTION] Validando integridade de chave de API e conexão com PgBouncer..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local EVO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "apikey: ${EVOLUTION_API_KEY:-${DB_PASSWORD}}" "http://127.0.0.1:8081/instance/fetchInstances" 2>/dev/null || echo "000")

    if [ "$EVO_STATUS" = "500" ]; then
        echo "➜ [SRE RECOVERY EVOLUTION] Deadlock de conexão no Prisma ORM (HTTP 500). Reciclando a Evolution API..."
        docker compose up -d --force-recreate evolution > /dev/null 2>&1 || true
        sleep 5
    elif [ "$EVO_STATUS" = "200" ]; then
        echo "➜ [IDEMPOTÊNCIA EVOLUTION] Evolution API conectada e autenticada com sucesso (HTTP 200)."
    fi
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar a Evolution API (Gateway WhatsApp)?" USE_EVOLUTION "s"
    [[ "${USE_EVOLUTION:-s}" =~ ^[Ss]$ ]] && USE_EVOLUTION="s" || USE_EVOLUTION="n"
    save_wizard_cache "USE_EVOLUTION" "$USE_EVOLUTION"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local API_KEY="${API_MASTER_KEY:-${DB_PASSWORD:-}}"
    local OLD_KEY=$(grep '^EVOLUTION_API_KEY=' "$env_path" 2>/dev/null | cut -d= -f2 || true)
    local FINAL_KEY="${OLD_KEY:-$API_KEY}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_evolution="1.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_evolution="3.0"
    elif [ "$cpus" -gt 4 ]; then
        cpu_evolution="2.0"
    fi

    local mem_evolution="1024M"
    local res_evolution="0M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_evolution="4096M"
        res_evolution="1024M"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_evolution="2048M"
        res_evolution="512M"
    fi

    cat << EOF >> "$env_path"

# --- Evolution API Decoupled Env & Tuning ---
USE_EVOLUTION="${USE_EVOLUTION:-s}"
EVO_PORT=${HOST_EVO_PORT:-18081}
HOST_EVO_PORT=${HOST_EVO_PORT:-18081}
EVOLUTION_API_KEY=${FINAL_KEY}
CPU_EVOLUTION=${CPU_EVOLUTION:-${cpu_evolution}}
MEM_EVOLUTION=${MEM_EVOLUTION:-${mem_evolution}}
RES_EVOLUTION=${RES_EVOLUTION:-${res_evolution}}
EOF
}

# Roteamento de funções via parâmetros CLI
ACTION="${2:-all}"
case "$ACTION" in
    collect_wizard_inputs|collect_inputs|wizard_prompt)
        collect_wizard_inputs
        ;;
    build_envs|build_env)
        build_envs
        ;;
    get_version|render_forensic_report|render_report|audit_health|inject_dashboard_card|inject_card|remove_dashboard_card|remove_card|purge_card|disable|teardown|inject_caddy_routes|inject_caddy|remove_caddy_routes|remove_caddy|start_container|wait_readiness|provision_infra|provision_user|build_structure|patch_assets|provision_db)
        case "$ACTION" in
            render_report) render_forensic_report "${3:-localhost}" ;;
            inject_card) inject_dashboard_card ;;
            remove_card|purge_card) remove_dashboard_card ;;
            teardown) disable ;;
            inject_caddy) inject_caddy_routes ;;
            remove_caddy) remove_caddy_routes ;;
            patch_assets) provision_infra ;;
            *) "$ACTION" "${3:-localhost}" ;;
        esac
        ;;
    all)
        build_structure
        inject_caddy_routes
        inject_dashboard_card
        start_container
        wait_readiness
        provision_infra
        provision_user
		provision_db
        ;;
    *)
        ;;
esac
