#!/usr/bin/env bash
# DUB
# Dub.co: Gestão de Links Inteligentes, UTMs e Atribuição de Cliques
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO DUB.CO
# Especificação: Módulo desacoplado de gerenciamento, banco, Caddy, cards e auditoria
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.20.01-DECOUPLED"

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

    local VOL_PATH="$TARGET_DIR/volumes/dub_data"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA DUB] Estrutura de volumes de dub_data já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE DUB] Criando estrutura física de volumes e permissões do Dub..."
        sudo mkdir -p "$VOL_PATH" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" 2>/dev/null || true
    fi
}

provision_db() {
    echo "➜ [SRE DUB] Provisionando banco de dados relacional dedicado (dub_db)..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local DB_ADMIN="${DB_USER}"
    local PRIMARY_DB="${PREFIX}_db"

    local DB_EXISTE=$(sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -t -c "SELECT 1 FROM pg_database WHERE datname = 'dub_db';" 2>/dev/null | tr -d '[:space:]' || echo "0")

    if [ "$DB_EXISTE" = "1" ]; then
        echo "➜ [IDEMPOTÊNCIA DUB] Banco de dados 'dub_db' já existente no PostgreSQL. Preservando estado."
    else
        echo "  ↳ Criando banco lógico 'dub_db'..."
        sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -c "CREATE DATABASE dub_db OWNER ${DB_ADMIN};" >/dev/null 2>&1 || true
        echo "✔ [SUCESSO DUB] Banco de dados 'dub_db' provisionado com sucesso."
    fi
}

provision_infra() {
    echo "➜ [SRE DUB] Verificando integridade e firewall perimetral do Dub..."
    local use_val="${USE_DUB:-s}"
    local port_num="${HOST_DUB_PORT:-3009}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
        fi
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE DUB] Injetando rotas do Dub no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_DUB_PORT:-3009}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ":${port_num}" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:${port_num} {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_dub:3000
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
    local port_num="${HOST_DUB_PORT:-3009}"
    if [ -f "$CADDYFILE_PATH" ] && grep -q ":${port_num}" "$CADDYFILE_PATH"; then
        echo "➜ [SRE DUB] Removendo rotas do Dub do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:${port_num}\s*\{[\s\S]*?dub[\s\S]*?\}', '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    local port_num="${HOST_DUB_PORT:-3009}"
    echo "➜ [SRE DUB] Injetando card do Dub no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"

    if [ -f "$INDEX_PATH" ] && ! grep -q "data-port=\"$port_num\"" "$INDEX_PATH" && ! grep -q 'Dub Links' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"$port_num\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">🔗</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Dub Links</h3>
                    <p class=\"description\">Gestão de links curtos, QR Codes, analytics de cliques e campanhas UTM.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:$port_num</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'Dub Links' not in content:
            target = '</div>\n\n        <div class=\"footer-note\">'
            if target in content:
                new_content = content.replace(target, card + '        ' + target)
                f.seek(0)
                f.write(new_content)
                f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

remove_dashboard_card() {
    echo "➜ [SRE DUB] Purgando card do Dub no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local port_num="${HOST_DUB_PORT:-3009}"
    if [ -f "$INDEX_PATH" ] && ( grep -q 'Dub Links' "$INDEX_PATH" || grep -q "data-port=\"$port_num\"" "$INDEX_PATH" ); then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^>]*data-port=\"$port_num\"[\s\S]*?</a>\s*', '', content)
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [\s\S]*?Dub Links[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE DUB] Desativando módulo Dub..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_DUB_PORT:-3009}"
    sudo docker rm -f "${PREFIX}_dub" 2>/dev/null || true

    # Limpeza de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/dub.conf ]; then
        sudo rm -f /etc/dnsmasq.d/dub.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO DUB] Módulo Dub desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE DUB] Garantindo subida integrada do container Dub..."
    cd "$TARGET_DIR"
    sudo docker compose up -d dub 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE DUB] Validando prontidão de socket e healthcheck do Dub..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local TENTATIVAS=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_dub 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 36 ]; then
            echo "⚠️ [SRE WARN DUB] Dub demorou a responder após 120s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 3
    done
    echo "✔ [SUCESSO DUB] Dub Links Server online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_DUB_PORT:-3009}"
    local health_val=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_dub 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_val" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:${port_num}/api/health" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:%s  -> Status: [%s]\n" "Dub Links API/UI:" "${ts_domain}" "${port_num}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_dub"
    sudo docker exec "$container_name" node -e 'console.log(require("./package.json").version)' 2>/dev/null || echo "latest"
}

provision_user() {
    echo "➜ [SRE DUB] Engine Dub pronta para provisionamento de workspaces e domínios encurtadores."
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local port_num="${HOST_DUB_PORT:-3009}"
    echo "  🔗 Dub.co (Links & Atribuição de Campanhas)"
    echo "    ↳ Painel Web:                      http://${ts_domain}:${port_num}"
    echo "    ↳ API Endpoint:                    http://${ts_domain}:${port_num}/api"
    echo ""
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o Dub.co (Encurtador de Links, UTMs & Atribuição)?" USE_DUB "s"
    [[ "${USE_DUB:-s}" =~ ^[Ss]$ ]] && USE_DUB="s" || USE_DUB="n"
    save_wizard_cache "USE_DUB" "$USE_DUB"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_dub="1.0"
    [ "$cpus" -gt 8 ] && cpu_dub="2.0"

    local mem_dub="1024M"
    local res_dub="256M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_dub="2048M"
        res_dub="512M"
    fi

    cat << EOF >> "$env_path"

# --- Dub.co Decoupled Env & Tuning ---
USE_DUB="${USE_DUB:-s}"
HOST_DUB_PORT="3009"
CPU_DUB=${CPU_DUB:-${cpu_dub}}
MEM_DUB=${MEM_DUB:-${mem_dub}}
RES_DUB=${RES_DUB:-${res_dub}}
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
        provision_infra
        inject_caddy_routes
        inject_dashboard_card
        start_container
        wait_readiness
        provision_user
        ;;
    *)
        ;;
esac
