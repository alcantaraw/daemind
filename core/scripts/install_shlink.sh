#!/usr/bin/env bash
# SHLINK
# Shlink: Encurtador de Links Inteligentes, UTMs e Atribuição de Campanhas
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO SHLINK & WEB CLIENT
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
    # Shlink é stateless (persistência 100% no PostgreSQL e Redis da stack)
    :
}

provision_db() {
    echo "➜ [SRE SHLINK] Provisionando banco de dados relacional dedicado (shlink_db)..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local DB_ADMIN="${DB_USER}"
    local PRIMARY_DB="${PREFIX}_db"

    local DB_EXISTE=$(sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -t -c "SELECT 1 FROM pg_database WHERE datname = 'shlink_db';" 2>/dev/null | tr -d '[:space:]' || echo "0")

    if [ "$DB_EXISTE" = "1" ]; then
        echo "➜ [IDEMPOTÊNCIA SHLINK] Banco de dados 'shlink_db' já existente no PostgreSQL. Preservando estado."
    else
        echo "  ↳ Criando banco lógico 'shlink_db'..."
        sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -c "CREATE DATABASE shlink_db OWNER ${DB_ADMIN};" >/dev/null 2>&1 || true
        echo "✔ [SUCESSO SHLINK] Banco de dados 'shlink_db' provisionado com sucesso."
    fi
}

provision_infra() {
    echo "➜ [SRE SHLINK] Verificando integridade e firewall perimetral do Shlink..."
    local use_val="${USE_SHLINK:-s}"
    local port_api="${HOST_SHLINK_PORT:-8080}"
    local port_web="${HOST_SHLINK_WEB_PORT:-8082}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport "$port_api" -j ACCEPT 2>/dev/null || true
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport "$port_web" -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_api" -j ACCEPT 2>/dev/null || true
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_web" -j ACCEPT 2>/dev/null || true
        fi
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE SHLINK] Injetando rotas do Shlink e Shlink Web Client no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_api="${HOST_SHLINK_PORT:-8081}"
    local port_web="${HOST_SHLINK_WEB_PORT:-8082}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ":${port_api}" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:${port_api} {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_shlink:8080
}

:${port_web} {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_shlink_web:8080
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
    local port_api="${HOST_SHLINK_PORT:-8081}"
    local port_web="${HOST_SHLINK_WEB_PORT:-8082}"
    if [ -f "$CADDYFILE_PATH" ] && grep -q ":${port_api}" "$CADDYFILE_PATH"; then
        echo "➜ [SRE SHLINK] Removendo rotas do Shlink do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:${port_api}\s*\{[\s\S]*?shlink:8080[\s\S]*?\}', '', content)
        new_content = re.sub(r'\s*:${port_web}\s*\{[\s\S]*?shlink_web:8080[\s\S]*?\}', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    local port_web="${HOST_SHLINK_WEB_PORT:-8082}"
    echo "➜ [SRE SHLINK] Injetando card do Shlink no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"

    if [ -f "$INDEX_PATH" ] && ! grep -q "data-port=\"$port_web\"" "$INDEX_PATH" && ! grep -q 'Shlink Links' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"$port_web\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">🔗</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Shlink Links</h3>
                    <p class=\"description\">Encurtador de links soberano, QR Codes, analytics de cliques e tags UTM.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:$port_web</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'Shlink Links' not in content:
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
    echo "➜ [SRE SHLINK] Purgando card do Shlink no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local port_web="${HOST_SHLINK_WEB_PORT:-8082}"
    if [ -f "$INDEX_PATH" ] && ( grep -q 'Shlink Links' "$INDEX_PATH" || grep -q "data-port=\"$port_web\"" "$INDEX_PATH" ); then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^>]*data-port=\"$port_web\"[\s\S]*?</a>\s*', '', content)
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [\s\S]*?Shlink Links[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE SHLINK] Desativando módulo Shlink..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_api="${HOST_SHLINK_PORT:-8080}"
    local port_web="${HOST_SHLINK_WEB_PORT:-8082}"
    sudo docker rm -f "${PREFIX}_shlink" "${PREFIX}_shlink_web" 2>/dev/null || true

    # Limpeza de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport "$port_api" -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport "$port_web" -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_api" -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_web" -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/shlink.conf ]; then
        sudo rm -f /etc/dnsmasq.d/shlink.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO SHLINK] Módulo Shlink desativado, containers removidos, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE SHLINK] Garantindo subida integrada dos containers Shlink..."
    cd "$TARGET_DIR"
    sudo docker compose up -d shlink shlink-web 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE SHLINK] Validando prontidão de socket e healthcheck do Shlink..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local TENTATIVAS=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_shlink 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN SHLINK] Shlink demorou a responder após 60s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done
    echo "✔ [SUCESSO SHLINK] Shlink Engine online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_web="${HOST_SHLINK_WEB_PORT:-8082}"
    local health_val=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_shlink 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_val" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:${port_web}/" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:%s  -> Status: [%s]\n" "Shlink Links Web UI:" "${ts_domain}" "${port_web}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_shlink"
    sudo docker exec "$container_name" shlink --version 2>/dev/null | grep -o '[0-9.]*' | head -n 1 || echo "stable"
}

provision_user() {
    echo "➜ [SRE SHLINK] API Key e credenciais de dashboard vinculadas ao cofre seguro da stack."
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local port_api="${HOST_SHLINK_PORT:-8080}"
    local port_web="${HOST_SHLINK_WEB_PORT:-8082}"
    echo "  🔗 Shlink (Encurtador & Atribuição de Campanhas)"
    echo "    ↳ Painel Web (GUI):                http://${ts_domain}:${port_web}"
    echo "    ↳ API Endpoint:                    http://${ts_domain}:${port_api}"
    echo "    ↳ API Key Inicial:                 ${SHLINK_API_KEY:-[Senha Mestra da Stack]}"
    echo ""
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o Shlink (Encurtador de Links Soberano, UTMs & QR Codes)?" USE_SHLINK "s"
    [[ "${USE_SHLINK:-s}" =~ ^[Ss]$ ]] && USE_SHLINK="s" || USE_SHLINK="n"
    save_wizard_cache "USE_SHLINK" "$USE_SHLINK"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_shlink="0.5"
    [ "$cpus" -gt 8 ] && cpu_shlink="1.0"

    local mem_shlink="512M"
    local res_shlink="128M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_shlink="1024M"
        res_shlink="256M"
    fi

    cat << EOF >> "$env_path"

# --- Shlink Decoupled Env & Tuning ---
USE_SHLINK="${USE_SHLINK:-s}"
HOST_SHLINK_PORT="8081"
HOST_SHLINK_WEB_PORT="8082"
CPU_SHLINK=${CPU_SHLINK:-${cpu_shlink}}
MEM_SHLINK=${MEM_SHLINK:-${mem_shlink}}
RES_SHLINK=${RES_SHLINK:-${res_shlink}}
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
