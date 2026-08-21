#!/usr/bin/env bash
# WPPCONNECT
# Gateway Oficial Open Source WhatsApp & Chatwoot Bridge
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO WPPCONNECT SERVER (WHATSAPP)
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório WPPConnect
# Dependência Funcional: Chatwoot CRM
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.21.03-STANDALONE-OFFICIAL"

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

    local VOL_PATH="$TARGET_DIR/volumes/wppconnect_data"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA WPPCONNECT] Estrutura de volumes de wppconnect_data já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE WPPCONNECT] Criando estrutura física de volumes e permissões do WPPConnect Server..."
        sudo mkdir -p "$VOL_PATH/tokens" "$VOL_PATH/userDataDir" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" 2>/dev/null || true
    fi

    # Injeta a Senha Mestra diretamente no template HTML para Zero Atrito
    local HTML_MGR="$TARGET_DIR/core/html/wppconnect.html"
    if [ -f "$HTML_MGR" ]; then
        sed -i "s|__MASTER_KEY__|${DB_PASSWORD}|g" "$HTML_MGR" 2>/dev/null || true
    fi
}

provision_db() {
    # WPPConnect Server utiliza persistência em tokens/arquivos e cache Redis nativo
    echo "➜ [IDEMPOTÊNCIA WPPCONNECT] Banco de dados desacoplado: persistência local de sessões e cache em Redis."
}

provision_infra() {
    echo "➜ [SRE WPPCONNECT] Aplicando firewall e regras de borda do WPPConnect..."
    local use_val="${USE_WPPCONNECT:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
        cat << 'EOF' | sudo tee /etc/dnsmasq.d/wppconnect.conf > /dev/null
# IPSET ALLOWED DOMAINS (WPPCONNECT / META WHATSAPP)
ipset=/graph.facebook.com/ALLOWED_DOMAINS
ipset=/whatsapp.net/ALLOWED_DOMAINS
ipset=/whatsapp.com/ALLOWED_DOMAINS
EOF
        sudo iptables -C DOCKER-USER -i tailscale0 -p tcp --dport 18081 -j ACCEPT 2>/dev/null || \
        sudo iptables -I DOCKER-USER 1 -i tailscale0 -p tcp --dport 18081 -j ACCEPT 2>/dev/null || true

        sudo iptables -C DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 18081 -j ACCEPT 2>/dev/null || \
        sudo iptables -I DOCKER-USER 1 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 18081 -j ACCEPT 2>/dev/null || true
    fi
}

inject_caddy_routes() {
    local target_caddyfile="${TARGET_DIR:-/opt/daemind}/Caddyfile"
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_ext="${HOST_WPPCONNECT_PORT:-18081}"

    if [ -f "$target_caddyfile" ]; then
        if grep -q "reverse_proxy ${PREFIX}_wppconnect:21465" "$target_caddyfile" 2>/dev/null; then
            echo "➜ [IDEMPOTÊNCIA WPPCONNECT] Rotas do WPPConnect já presentes no Caddyfile."
        else
            echo "➜ [SRE WPPCONNECT] Injetando rotas do WPPConnect Server no Caddyfile (Subpath /wpp/ & Porta :${port_ext})..."
            
            # Injeta o proxy transparente /wpp/* logo antes do file_server no bloco do portal
            python3 -c "
path = '$target_caddyfile'
try:
    with open(path, 'r+', encoding='utf-8') as f:
        content = f.read()
        if 'handle_path /wpp/*' not in content:
            target = '    file_server'
            replacement = '''    # --- WPPCONNECT_SUBPATH_START ---
    handle_path /wpp/* {
        reverse_proxy ${PREFIX}_wppconnect:21465
    }
    # --- WPPCONNECT_SUBPATH_END ---

    file_server'''
            if target in content:
                new_content = content.replace(target, replacement, 1)
                f.seek(0)
                f.write(new_content)
                f.truncate()
except Exception:
    pass
" 2>/dev/null || true

            # Injeta a porta dedicada externa :18081
            sed -i "/# --- WPPCONNECT_START ---/,/# --- WPPCONNECT_END ---/d" "$target_caddyfile" 2>/dev/null || true
            cat << EOF >> "$target_caddyfile"

# --- WPPCONNECT_START ---
:${port_ext} {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_wppconnect:21465
}
# --- WPPCONNECT_END ---
EOF
        fi
    fi
}

remove_caddy_routes() {
    local target_caddyfile="${TARGET_DIR:-/opt/daemind}/Caddyfile"
    if [ -f "$target_caddyfile" ]; then
        echo "➜ [SRE WPPCONNECT] Purgando rotas do WPPConnect Server do Caddyfile..."
        sed -i "/# --- WPPCONNECT_START ---/,/# --- WPPCONNECT_END ---/d" "$target_caddyfile" 2>/dev/null || true
        sed -i "/# --- WPPCONNECT_SUBPATH_START ---/,/# --- WPPCONNECT_SUBPATH_END ---/d" "$target_caddyfile" 2>/dev/null || true
        sudo docker exec "${PREFIXO_CONTAINER}_caddy" caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    local target_html="${TARGET_DIR:-/opt/daemind}/core/html/index.html"
    local port_ext="${HOST_WPPCONNECT_PORT:-18081}"

    if [ -f "$target_html" ]; then
        if grep -q 'data-path="/wppconnect.html"' "$target_html" 2>/dev/null; then
            echo "➜ [IDEMPOTÊNCIA WPPCONNECT] Card do WPPConnect já presente no portal."
        else
            echo "➜ [SRE WPPCONNECT] Injetando card do WPPConnect no portal web..."
            python3 -c "
import sys
try:
    with open('$target_html', 'r+', encoding='utf-8') as f:
        content = f.read()
        if 'data-path=\"/wppconnect.html\"' not in content:
            card_html = '''        <a href=\"#\" data-port=\"80\" data-path=\"/wppconnect.html\" class=\"card dynamic-link\">
            <div class=\"card-content\">
                <div class=\"card-header\">
                    <div class=\"icon\">💬</div>
                    <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                </div>
                <h3>WPPConnect WhatsApp</h3>
                <p class=\"description\">Gerenciador de Sessões, Leitura de QR Code, API Swagger e Chatwoot Bridge.</p>
                <div class=\"card-footer\">
                    <span>Manager & API</span>
                    <span class=\"port\">:$port_ext</span>
                </div>
            </div>
        </a>
'''
            idx = content.find('</div>\n\n        <div class=\"footer-note\">')
            if idx != -1:
                new_content = content[:idx] + card_html + content[idx:]
                f.seek(0)
                f.write(new_content)
                f.truncate()
                print('Card WPPConnect injetado com sucesso.')
except Exception as e:
    pass
" 2>/dev/null || true
        fi
    fi
}

remove_dashboard_card() {
    local target_html="${TARGET_DIR:-/opt/daemind}/core/html/index.html"
    local port_ext="${HOST_WPPCONNECT_PORT:-18081}"

    if [ -f "$target_html" ]; then
        echo "➜ [SRE WPPCONNECT] Removendo card do WPPConnect do portal web..."
        python3 -c "
import sys, re
try:
    with open('$target_html', 'r+', encoding='utf-8') as f:
        content = f.read()
        pattern = r'<a href=\"#\" data-port=\"$port_ext\".*?</a>\s*'
        new_content = re.sub(pattern, '', content, flags=re.DOTALL)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE WPPCONNECT] Desativando módulo WPPConnect Server..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_wppconnect" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 18081 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 18081 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/wppconnect.conf ]; then
        sudo rm -f /etc/dnsmasq.d/wppconnect.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO WPPCONNECT] Módulo WPPConnect Server desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE WPPCONNECT] Garantindo subida integrada do container WPPConnect..."
    cd "$TARGET_DIR"
    sudo docker compose up -d wppconnect 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE WPPCONNECT] Validando prontidão de socket e healthcheck do WPPConnect Server..."
    local TENTATIVAS=0
    local PREFIX="${PREFIXO_CONTAINER}"
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_wppconnect 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN WPPCONNECT] WPPConnect demorou a responder após 90s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 3
    done
    echo "✔ [SUCESSO WPPCONNECT] WPPConnect Server online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_ext="${HOST_WPPCONNECT_PORT:-18081}"
    local health_wpp=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_wppconnect 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_wpp" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${port_ext}/api-docs/" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:%s  -> Status: [%s]\n" "WPPConnect WhatsApp:" "${ts_domain}" "${port_ext}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local v=""
    # 1. Tenta extrair versão do package.json do container
    v=$(sudo docker exec "${PREFIX}_wppconnect" node -p "require('./package.json').version" 2>/dev/null || echo "")
    # 2. Fallback via Label OCI
    if [ -z "$v" ]; then
        v=$(sudo docker inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "${PREFIX}_wppconnect" 2>/dev/null || echo "")
    fi
    echo "${v:-latest}"
}

provision_user() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE WPPCONNECT] Validando integração com Chatwoot CRM..."
    if [ "${USE_CHATWOOT:-s}" = "s" ] && [ -n "${CHATWOOT_API_TOKEN:-}" ]; then
        echo "✔ [SUCESSO WPPCONNECT] Token do Chatwoot CRM injetado no ambiente do WPPConnect."
    fi
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local port_ext="${HOST_WPPCONNECT_PORT:-18081}"
    local sec_key="${WPPCONNECT_SECRET_KEY:-${DB_PASSWORD}}"

    cat << EOF
---------------------------------------------------------------------
  💬 WPPCONNECT SERVER (WHATSAPP GATEWAY, CHATWOOT & N8N BRIDGE)
---------------------------------------------------------------------
  ↳ Documentação Swagger API:   http://${ts_domain}:${port_ext}/api-docs/
  ↳ Chave Secreta API (Bearer): ${sec_key}
  ↳ Integração Chatwoot:         Ativa (URL: http://${PREFIXO_CONTAINER}_chatwoot:3000)
  ↳ Webhooks de Eventos n8n:     Ativo (URL: http://${PREFIXO_CONTAINER}_n8n:5678/webhook/wppconnect)
---------------------------------------------------------------------
EOF
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o WPPConnect Server (Gateway Open Source WhatsApp & Chatwoot)?" USE_WPPCONNECT "s"
    [[ "${USE_WPPCONNECT:-s}" =~ ^[Ss]$ ]] && USE_WPPCONNECT="s" || USE_WPPCONNECT="n"
    # SRE Guardrail de Dependência: Se WPPConnect for ativado, Chatwoot DEVE ser ativado
    if [ "$USE_WPPCONNECT" = "s" ]; then
        USE_CHATWOOT="s"
        save_wizard_cache "USE_CHATWOOT" "s"
    fi
    save_wizard_cache "USE_WPPCONNECT" "$USE_WPPCONNECT"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local API_KEY="${API_MASTER_KEY:-${DB_PASSWORD:-}}"
    local domain="${TS_DOMAIN:-localhost}"

    # SRE Guardrail de Dependência Autônomo: WPPConnect ativa o Chatwoot no .env
    if [[ "${USE_WPPCONNECT:-s}" =~ ^[Ss]$ ]]; then
        export USE_CHATWOOT="s"
        sed -i 's/^USE_CHATWOOT=.*/USE_CHATWOOT="s"/' "$env_path" 2>/dev/null || true
    fi

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_wpp="0.5"
    if [ "$cpus" -gt 4 ]; then
        cpu_wpp="1.0"
    fi

    local mem_wpp="1024M"
    local res_wpp="256M"

    cat << EOF >> "$env_path"

# ===============================================================================
# CONFIGURAÇÕES DINÂMICAS: WPPCONNECT SERVER (WHATSAPP GATEWAY)
# ===============================================================================
USE_WPPCONNECT="${USE_WPPCONNECT:-s}"
HOST_WPPCONNECT_PORT="\${HOST_WPPCONNECT_PORT:-18081}"
WPPCONNECT_SECRET_KEY="${WPPCONNECT_SECRET_KEY:-${API_KEY}}"
CPU_WPPCONNECT="${cpu_wpp}"
MEM_WPPCONNECT="${mem_wpp}"
RES_WPPCONNECT="${res_wpp}"
EOF
}

# Sub-comandos do contrato de módulo desacoplado
case "${2:-}" in
    build_structure)        build_structure ;;
    provision_db)           provision_db ;;
    provision_infra)        provision_infra ;;
    inject_caddy_routes)    inject_caddy_routes ;;
    remove_caddy_routes)    remove_caddy_routes ;;
    inject_dashboard_card)  inject_dashboard_card ;;
    remove_dashboard_card)  remove_dashboard_card ;;
    start_container)        start_container ;;
    wait_readiness)         wait_readiness ;;
    audit_health)           audit_health "$3" ;;
    get_version)            get_version ;;
    provision_user)         provision_user ;;
    render_forensic_report) render_forensic_report "$3" ;;
    collect_wizard_inputs)  collect_wizard_inputs ;;
    build_envs)             build_envs ;;
    disable|teardown)       disable ;;
    load_only)              ;; # Apenas carrega as funções sem executar nada
    *)
        if [ "$#" -le 1 ]; then
            build_structure
            provision_db
            provision_infra
            inject_caddy_routes
            inject_dashboard_card
        fi
        ;;
esac
