#!/usr/bin/env bash
# METABASE
# Painéis e Dashboards de BI em Tempo Real
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO METABASE BI & ANALYTICS
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório Metabase
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.15.01-DECOUPLED"

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

    local VOL_PATH="$TARGET_DIR/volumes/metabase_data"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA METABASE] Estrutura de volumes de metabase_data já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE METABASE] Criando estrutura física de volumes e permissões do Metabase..."
        sudo mkdir -p "$VOL_PATH" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" 2>/dev/null || true
    fi
}

provision_db() {
    echo "➜ [SRE METABASE] Provisionando banco de dados relacional dedicado (metabase_db)..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local DB_ADMIN="${DB_USER}"
    local PRIMARY_DB="${PREFIX}_db"

    local DB_EXISTE=$(sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -t -c "SELECT 1 FROM pg_database WHERE datname = 'metabase_db';" 2>/dev/null | tr -d '[:space:]' || echo "0")

    if [ "$DB_EXISTE" = "1" ]; then
        echo "➜ [IDEMPOTÊNCIA METABASE] Banco de dados 'metabase_db' já existente no PostgreSQL. Preservando estado."
    else
        echo "  ↳ Criando banco lógico 'metabase_db'..."
        sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -c "CREATE DATABASE metabase_db OWNER ${DB_ADMIN};" >/dev/null 2>&1 || true
        echo "✔ [SUCESSO METABASE] Banco de dados 'metabase_db' provisionado com sucesso."
    fi
}

provision_infra() {
    echo "➜ [SRE METABASE] Verificando integridade de esquemas e firewall perimetral do Metabase..."
    local use_val="${USE_METABASE:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 3030 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 3030 -j ACCEPT 2>/dev/null || true
        fi
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE METABASE] Injetando rotas do Metabase BI no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q "reverse_proxy.*_metabase:3000" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:3030 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_metabase:3000
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
    if [ -f "$CADDYFILE_PATH" ] && grep -q "reverse_proxy.*_metabase:3000" "$CADDYFILE_PATH"; then
        echo "➜ [SRE METABASE] Removendo rotas do Metabase BI do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:3030\s*\{[\s\S]*?metabase[\s\S]*?\}', '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    local MB_PORT="${HOST_METABASE_PORT:-3030}"
    echo "➜ [SRE METABASE] Injetando card do Metabase BI no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$INDEX_PATH" ] && ! grep -q 'data-port="3030"' "$INDEX_PATH" && ! grep -q "data-port=\"$MB_PORT\"" "$INDEX_PATH" && ! grep -q 'Metabase BI' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"$MB_PORT\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">📈</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Metabase BI</h3>
                    <p class=\"description\">Painéis analíticos, relatórios e inteligência de negócios para a operação.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:$MB_PORT</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'Metabase BI' not in content:
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
    echo "➜ [SRE METABASE] Purgando card do Metabase BI no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    if [ -f "$INDEX_PATH" ] && { grep -q 'Metabase BI' "$INDEX_PATH" || grep -q 'data-port="3030"' "$INDEX_PATH"; }; then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\"[^>]*data-port=\"(3030|${HOST_METABASE_PORT:-3030})\"[\s\S]*?</a>\s*', '', content)
        if 'Metabase BI' in new_content:
            new_content = re.sub(r'\s*<a href=\"[^\"]*\" class=\"card dynamic-link\">[\s\S]*?Metabase BI[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE METABASE] Desativando módulo Metabase BI..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_metabase" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 3030 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 3030 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/metabase.conf ]; then
        sudo rm -f /etc/dnsmasq.d/metabase.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO METABASE] Módulo Metabase desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE METABASE] Garantindo subida integrada do container Metabase..."
    cd "$TARGET_DIR"
    sudo docker compose up -d metabase 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE METABASE] Validando prontidão de socket e healthcheck do Metabase..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local TENTATIVAS=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_metabase 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 45 ]; then
            echo "⚠️ [SRE WARN METABASE] Metabase demorou a responder após 90s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done
    echo "✔ [SUCESSO METABASE] Metabase BI Server online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local health_mb=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_metabase 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_mb" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:3030/api/health" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:3030  -> Status: [%s]\n" "Metabase BI Console:" "${ts_domain}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_metabase"
    local MB_PORT="${HOST_METABASE_PORT:-3030}"
    local VER=$(curl -s "http://127.0.0.1:${MB_PORT}/api/session/properties" 2>/dev/null | jq -r '.version.tag // .["version-info"].tag // empty' 2>/dev/null || echo "")
    if [ -n "$VER" ]; then
        echo "$VER"
    else
        sudo docker inspect -f '{{.Config.Image}}' "$container_name" 2>/dev/null || echo "latest"
    fi
}

provision_user() {
    echo "➜ [SRE METABASE] Provisionando conta de Administrador (Zero-Touch)..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local MB_URL="http://127.0.0.1:3030"
    local ADMIN_EMAIL="${TS_EMAIL}"
    local ADMIN_PASS="${DB_PASSWORD}"
    local FIRST_NAME="${CLIENTE_NOME}"
    local LAST_NAME="${CLIENTE_SOBRENOME}"
    local SITE_NAME="Metabase BI (${CLIENTE_NOME})"

    # 1. Obtém o setup-token emitido pelo Metabase no primeiro boot
    local PROPERTIES=$(curl -s -m 8 "${MB_URL}/api/session/properties" 2>/dev/null || echo "")
    local SETUP_TOKEN=$(echo "$PROPERTIES" | jq -r '.["setup-token"] // empty' 2>/dev/null || echo "")

    if [ -z "$SETUP_TOKEN" ] || [ "$SETUP_TOKEN" = "null" ]; then
        # Se não há setup-token, o Metabase já foi provisionado anteriormente (Idempotente)
        echo "➜ [IDEMPOTÊNCIA METABASE] Metabase já inicializado e com conta administrativa configurada."
        return 0
    fi

    # 2. Executa a criação do administrador e parametrização inicial via REST API
    local PAYLOAD=$(jq -n \
        --arg token "$SETUP_TOKEN" \
        --arg email "$ADMIN_EMAIL" \
        --arg first "$FIRST_NAME" \
        --arg last "$LAST_NAME" \
        --arg pass "$ADMIN_PASS" \
        --arg site "$SITE_NAME" \
        '{
            token: $token,
            user: {
                email: $email,
                first_name: $first,
                last_name: $last,
                password: $pass
            },
            prefs: {
                site_name: $site,
                site_locale: "pt_BR",
                allow_tracking: false
            }
        }')

    local RESPONSE=$(curl -s -X POST "${MB_URL}/api/setup" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>/dev/null || echo "")

    if echo "$RESPONSE" | grep -qiE '"id"|"session_id"|"success"|true'; then
        echo "✔ [SUCESSO METABASE] Administrador provisionado com sucesso (${ADMIN_EMAIL})!"
    else
        echo "⚠️ [SRE METABASE] Resposta da API de Setup: $(echo "$RESPONSE" | cut -c1-120)"
    fi
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local MB_PORT="${HOST_METABASE_PORT:-3030}"
    echo "  📊 Metabase Business Intelligence"
    echo "    ↳ Painel Web:                      http://${ts_domain}:${MB_PORT}"
    echo "    ↳ Healthcheck:                     http://${ts_domain}:${MB_PORT}/api/health"
    echo "    ↳ Banco de Dados Interno:          metabase_db (via PgBouncer)"
    echo "    ↳ Caminho Físico (Host):           ${TARGET_DIR}/volumes/metabase_data"
    echo ""
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o Metabase BI (Painéis Analíticos & Dashboards)?" USE_METABASE "s"
    [[ "${USE_METABASE:-s}" =~ ^[Ss]$ ]] && USE_METABASE="s" || USE_METABASE="n"
    save_wizard_cache "USE_METABASE" "$USE_METABASE"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_metabase="1.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_metabase="2.0"
    fi

    local mem_metabase="1024M"
    local res_metabase="256M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_metabase="4096M"
        res_metabase="1024M"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_metabase="2048M"
        res_metabase="512M"
    fi

    cat << EOF >> "$env_path"

# --- Metabase Decoupled Env & Tuning ---
USE_METABASE="${USE_METABASE:-s}"
HOST_METABASE_PORT="3030"
CPU_METABASE=${CPU_METABASE:-${cpu_metabase}}
MEM_METABASE=${MEM_METABASE:-${mem_metabase}}
RES_METABASE=${RES_METABASE:-${res_metabase}}
EOF
}

# Roteamento de funções via parâmetros CLI (Padrão de Contrato Desacoplado)
ACTION="${2:-all}"
case "$ACTION" in
    collect_wizard_inputs|collect_inputs|wizard_prompt)
        collect_wizard_inputs
        ;;
    build_envs|build_env)
        build_envs
        ;;
    get_version|render_forensic_report|render_report|audit_health|inject_dashboard_card|inject_card|remove_dashboard_card|remove_card|purge_card|disable|teardown|inject_caddy_routes|inject_caddy|remove_caddy_routes|remove_caddy|start_container|wait_readiness|provision_infra|provision_db|provision_user|build_structure)
        case "$ACTION" in
            render_report) render_forensic_report "${3:-localhost}" ;;
            inject_card) inject_dashboard_card ;;
            remove_card|purge_card) remove_dashboard_card ;;
            teardown) disable ;;
            inject_caddy) inject_caddy_routes ;;
            remove_caddy) remove_caddy_routes ;;
            *) "$ACTION" "${3:-localhost}" ;;
        esac
        ;;
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
