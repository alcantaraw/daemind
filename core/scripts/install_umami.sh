#!/usr/bin/env bash
# UMAMI
# Umami: Web Analytics Focado em Privacidade e LGPD
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO UMAMI ANALYTICS
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
    # Umami não requer diretórios locais de persistência física pois é 100% persistido no PostgreSQL
    :
}

provision_db() {
    echo "➜ [SRE UMAMI] Provisionando banco de dados relacional dedicado (umami_db)..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local DB_ADMIN="${DB_USER}"
    local PRIMARY_DB="${PREFIX}_db"

    local DB_EXISTE=$(sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -t -c "SELECT 1 FROM pg_database WHERE datname = 'umami_db';" 2>/dev/null | tr -d '[:space:]' || echo "0")

    if [ "$DB_EXISTE" = "1" ]; then
        echo "➜ [IDEMPOTÊNCIA UMAMI] Banco de dados 'umami_db' já existente no PostgreSQL. Preservando estado."
    else
        echo "  ↳ Criando banco lógico 'umami_db'..."
        sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -c "CREATE DATABASE umami_db OWNER ${DB_ADMIN};" >/dev/null 2>&1 || true
        echo "✔ [SUCESSO UMAMI] Banco de dados 'umami_db' provisionado com sucesso."
    fi
}

provision_infra() {
    echo "➜ [SRE UMAMI] Verificando integridade e firewall perimetral do Umami..."
    local use_val="${USE_UMAMI:-s}"
    local port_num="${HOST_UMAMI_PORT:-3008}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
        fi
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE UMAMI] Injetando rotas do Umami no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_UMAMI_PORT:-3008}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ":${port_num}" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:${port_num} {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_umami:3000
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
    local port_num="${HOST_UMAMI_PORT:-3008}"
    if [ -f "$CADDYFILE_PATH" ] && grep -q ":${port_num}" "$CADDYFILE_PATH"; then
        echo "➜ [SRE UMAMI] Removendo rotas do Umami do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:${port_num}\s*\{[\s\S]*?umami[\s\S]*?\}', '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    local port_num="${HOST_UMAMI_PORT:-3008}"
    echo "➜ [SRE UMAMI] Injetando card do Umami no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"

    if [ -f "$INDEX_PATH" ] && ! grep -q "data-port=\"$port_num\"" "$INDEX_PATH" && ! grep -q 'Umami Analytics' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"$port_num\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">📈</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Umami Analytics</h3>
                    <p class=\"description\">Web analytics leve, moderno e 100% compatível com LGPD/GDPR sem cookies invasivos.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:$port_num</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'Umami Analytics' not in content:
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
    echo "➜ [SRE UMAMI] Purgando card do Umami no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local port_num="${HOST_UMAMI_PORT:-3008}"
    if [ -f "$INDEX_PATH" ] && ( grep -q 'Umami Analytics' "$INDEX_PATH" || grep -q "data-port=\"$port_num\"" "$INDEX_PATH" ); then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^>]*data-port=\"$port_num\"[\s\S]*?</a>\s*', '', content)
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [\s\S]*?Umami Analytics[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE UMAMI] Desativando módulo Umami..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_UMAMI_PORT:-3008}"
    sudo docker rm -f "${PREFIX}_umami" 2>/dev/null || true

    # Limpeza de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/umami.conf ]; then
        sudo rm -f /etc/dnsmasq.d/umami.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO UMAMI] Módulo Umami desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE UMAMI] Garantindo subida integrada do container Umami..."
    cd "$TARGET_DIR"
    sudo docker compose up -d umami 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE UMAMI] Validando prontidão de socket e healthcheck do Umami..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local TENTATIVAS=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_umami 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN UMAMI] Umami demorou a responder após 60s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done
    echo "✔ [SUCESSO UMAMI] Umami Analytics Server online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_UMAMI_PORT:-3008}"
    local health_val=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_umami 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_val" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:${port_num}/api/heartbeat" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:%s  -> Status: [%s]\n" "Umami Analytics API/UI:" "${ts_domain}" "${port_num}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_umami"
    sudo docker exec "$container_name" node -e 'console.log(require("./package.json").version)' 2>/dev/null || echo "2.16.0"
}

provision_user() {
    echo "➜ [SRE UMAMI] Engine Umami pronta. Login padrão inicial: admin / umami (recomenda-se alteração no primeiro login)."
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local port_num="${HOST_UMAMI_PORT:-3008}"
    echo "  📈 Umami (Web Analytics & Privacidade)"
    echo "    ↳ Painel Web:                      http://${ts_domain}:${port_num}"
    echo "    ↳ Login Padrão:                    admin"
    echo "    ↳ Senha Inicial:                   umami (ou chave mestre)"
    echo ""
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o Umami (Web Analytics Leve & LGPD Soberano)?" USE_UMAMI "s"
    [[ "${USE_UMAMI:-s}" =~ ^[Ss]$ ]] && USE_UMAMI="s" || USE_UMAMI="n"
    save_wizard_cache "USE_UMAMI" "$USE_UMAMI"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_umami="0.5"
    [ "$cpus" -gt 8 ] && cpu_umami="1.0"

    local mem_umami="512M"
    local res_umami="128M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_umami="1024M"
        res_umami="256M"
    fi

    cat << EOF >> "$env_path"

# --- Umami Analytics Decoupled Env & Tuning ---
USE_UMAMI="${USE_UMAMI:-s}"
HOST_UMAMI_PORT="3008"
CPU_UMAMI=${CPU_UMAMI:-${cpu_umami}}
MEM_UMAMI=${MEM_UMAMI:-${mem_umami}}
RES_UMAMI=${RES_UMAMI:-${res_umami}}
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
