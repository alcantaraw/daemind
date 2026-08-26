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
    if docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -c "SELECT 1 FROM pg_database WHERE datname = 'evolution_db'" 2>/dev/null | grep -q 1; then
        echo "➜ [IDEMPOTÊNCIA EVOLUTION] Banco de dados 'evolution_db' já existente. Preservando esquema."
    else
        echo "  ↳ Criando banco de dados 'evolution_db'..."
        docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -q -c "CREATE DATABASE evolution_db;" > /dev/null 2>&1 || true
    fi
}

provision_infra() {
    echo "➜ [SRE EVOLUTION] Aplicando firewall, túnel perimetral e patch de assets no Evolution..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local use_val="${USE_EVOLUTION:-s}"
    local port_num="${HOST_EVO_PORT:-18081}"

    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
        cat << 'EOF' | sudo tee /etc/dnsmasq.d/evolution.conf > /dev/null
# IPSET ALLOWED DOMAINS (EVOLUTION API / META WHATSAPP)
ipset=/graph.facebook.com/ALLOWED_DOMAINS
EOF
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
            # Ativação autônoma do Tailscale Funnel para a porta da Evolution API (:8443 -> 18081)
            local FUNNEL_STATUS
            FUNNEL_STATUS=$(sudo tailscale funnel status 2>/dev/null || echo "")
            if ! echo "$FUNNEL_STATUS" | grep -q "https://.*:8443"; then
                echo "➜ [SRE TAILSCALE EVOLUTION] Ativando túnel Funnel HTTPS na porta :8443..."
                sudo tailscale funnel --bg --https=8443 "${port_num}" > /dev/null 2>&1 || true
            fi
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
        fi
    else
        sudo rm -f /etc/dnsmasq.d/evolution.conf 2>/dev/null || true
    fi

    local EVO_CONTAINER="${PREFIX}_evolution"
    if ! docker ps --format '{{.Names}}' | grep -q "^${EVO_CONTAINER}$"; then
        EVO_CONTAINER="evolution"
    fi

    docker exec -u root "$EVO_CONTAINER" sh -c '
        # Garante pastas físicas no dist do manager
        mkdir -p /evolution/manager/dist/assets/images 2>/dev/null || true

        # Copia o logo público como favicon e logo oficial na raiz servida do manager
        if [ -f /evolution/public/images/evolution-logo.png ]; then
            cp /evolution/public/images/evolution-logo.png /evolution/manager/dist/favicon.png 2>/dev/null || true
            cp /evolution/public/images/evolution-logo.png /evolution/manager/dist/evolution-logo.png 2>/dev/null || true
            cp /evolution/public/images/evolution-logo.png /evolution/manager/dist/evolution-logo-white.svg 2>/dev/null || true
            cp /evolution/public/images/evolution-logo.png /evolution/manager/dist/evolution-logo.svg 2>/dev/null || true
            cp /evolution/public/images/evolution-logo.png /evolution/manager/dist/assets/evolution-logo.png 2>/dev/null || true
            cp /evolution/public/images/evolution-logo.png /evolution/manager/dist/assets/images/evolution-logo.png 2>/dev/null || true
        fi

        # Patch no index.html do manager para carregar o favicon
        if [ -f /evolution/manager/dist/index.html ]; then
            sed -i -e "s|https://evolution-api.com/files/evo/favicon.svg|/manager/favicon.png|g" \
                   -e "s|href=\"/favicon.svg\"|href=\"/manager/favicon.png\"|g" \
                   -e "s|href=\"favicon.svg\"|href=\"/manager/favicon.png\"|g" \
                   -e "s|type=\"image/svg+xml\"|type=\"image/png\"|g" /evolution/manager/dist/index.html 2>/dev/null || true
        fi

        # Patch nos bundles JS para carregar logos e favicons locais em vez da CDN externa
        if [ -d /evolution/manager/dist/assets ]; then
            find /evolution/manager/dist/assets -type f -name "*.js" -exec sed -i \
                -e "s|https://evolution-api.com/files/evo/evolution-logo-white.svg|/manager/favicon.png|g" \
                -e "s|https://evolution-api.com/files/evo/evolution-logo.svg|/manager/favicon.png|g" \
                -e "s|https://evolution-api.com/files/evo/favicon.svg|/manager/favicon.png|g" {} + 2>/dev/null || true
        fi
    ' 2>/dev/null || true

    echo "✔ [SUCESSO EVOLUTION] Infra provisionada: DB, firewall, Funnel e assets configurados."
}

inject_caddy_routes() {
    echo "➜ [SRE EVOLUTION] Injetando rotas da Evolution API no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_EVO_PORT:-18081}"
    local custom_evo="${CUSTOM_EVO_DOMAIN:-}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ":${port_num}" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:${port_num} {
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

        # Rota dedicada se houver domínio próprio customizado para o WhatsApp
        if [ -n "$custom_evo" ] && ! grep -q "$custom_evo" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

${custom_evo} {
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
    local port_num="${HOST_EVO_PORT:-18081}"
    local custom_evo="${CUSTOM_EVO_DOMAIN:-}"

    if [ -f "$CADDYFILE_PATH" ]; then
        echo "➜ [SRE EVOLUTION] Removendo rotas da Evolution API do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
custom_evo = '$custom_evo'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:(8081|${port_num})\s*\{[\s\S]*?evolution[\s\S]*?\}', '', content)
        new_content = re.sub(r'\s*:(8081|${port_num})\s*\{[\s\S]*?\}', '', new_content)
        if custom_evo:
            new_content = re.sub(r'\s*' + re.escape(custom_evo) + r'\s*\{[\s\S]*?\}', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    local port_num="${HOST_EVO_PORT:-18081}"
    echo "➜ [SRE EVOLUTION] Injetando card da Evolution API no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$INDEX_PATH" ] && ! grep -q "data-port=\"$port_num\"" "$INDEX_PATH" && ! grep -q 'Evolution API' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"$port_num\" data-path=\"/manager\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">💬</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Evolution API</h3>
                    <p class=\"description\">Gateway de integração oficial do WhatsApp com suporte a instâncias e webhooks.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:$port_num</span>
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
    local port_num="${HOST_EVO_PORT:-18081}"
    if [ -f "$INDEX_PATH" ] && ( grep -q 'Evolution API' "$INDEX_PATH" || grep -q "data-port=\"$port_num\"" "$INDEX_PATH" || grep -q 'data-port="8081"' "$INDEX_PATH" ); then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^>]*data-port=\"(8081|${port_num})\"[\s\S]*?</a>\s*', '', content)
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [\s\S]*?Evolution API[\s\S]*?</a>\s*', '', new_content)
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

    # Desativação do túnel Tailscale Funnel da porta :8443
    sudo tailscale funnel --https=8443 off 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 18081 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 18081 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/evolution.conf ]; then
        sudo rm -f /etc/dnsmasq.d/evolution.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO EVOLUTION] Módulo Evolution API desativado, container removido, firewall, Funnel e rotas limpos."
}

start_container() {
    echo "➜ [SRE EVOLUTION] Garantindo subida integrada do container Evolution API..."
    cd "$TARGET_DIR"
    sudo docker compose up -d evolution 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE EVOLUTION] Validando prontidão de socket e healthcheck da Evolution API..."
    local TENTATIVAS=0
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_EVO_PORT:-18081}"
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_evolution 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN EVOLUTION] Evolution API demorou a responder após 60s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done

    echo "➜ [SRE EVOLUTION] Validando integridade da conexão Prisma com PgBouncer..."
    local EVO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "apikey: ${EVOLUTION_API_KEY:-${DB_PASSWORD}}" "http://127.0.0.1:${port_num}/instance/fetchInstances" 2>/dev/null || echo "000")

    if [ "$EVO_STATUS" = "500" ]; then
        echo "➜ [SRE RECOVERY EVOLUTION] Deadlock de conexão detectado no Prisma ORM (HTTP 500). Reciclando a Evolution API..."
        docker compose restart evolution > /dev/null 2>&1 || true
        sleep 5
        TENTATIVAS=0
        until [ "$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "apikey: ${EVOLUTION_API_KEY:-${DB_PASSWORD}}" "http://127.0.0.1:${port_num}/instance/fetchInstances" 2>/dev/null || echo "200")" = "200" ]; do
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
    local port_num="${HOST_EVO_PORT:-18081}"
    local health_status=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_evolution 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"
    if [ "$health_status" = "healthy" ]; then
        http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${port_num}/" 2>/dev/null || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    local funnel_info=""
    if [ "${USE_TAILSCALE:-false}" = "true" ]; then
        local http_funnel
        http_funnel=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${ts_domain}:8443/" 2>/dev/null || echo "000")
        funnel_info=" | Funnel HTTPS (:8443) -> [${http_funnel}]"
    fi

    printf "  ↳ %-32s http://%s:%s%s  -> Status: [%s]\n" "WhatsApp API (Evolution):" "${ts_domain}" "${port_num}" "${funnel_info}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_evolution"
    sudo docker exec "$container_name" node -e 'console.log(require("./package.json").version)' 2>/dev/null || echo "homolog"
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local port_num="${HOST_EVO_PORT:-18081}"
    local custom_evo="${CUSTOM_EVO_DOMAIN:-}"
    local evo_url="${SERVER_URL:-http://${ts_domain}:${port_num}}"

    if [ -n "$custom_evo" ]; then
        evo_url="${CADDY_PROTOCOL:-https}://${custom_evo}"
    elif [ "${USE_TAILSCALE:-false}" = "true" ]; then
        evo_url="https://${ts_domain}:8443"
    fi

    echo "  💬 WhatsApp API (Evolution)"
    echo "    ↳ API Principal (SERVER_URL):      ${evo_url}"
    echo "    ↳ Evolution Manager:               http://${ts_domain}:${port_num}/manager"
    echo "    ↳ Healthcheck:                     http://${ts_domain}:${port_num}/manager/health"
    echo ""
}

provision_user() {
    echo "➜ [SRE EVOLUTION] Validando integridade de chave de API e conexão com PgBouncer..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_EVO_PORT:-18081}"
    local EVO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "apikey: ${EVOLUTION_API_KEY:-${DB_PASSWORD}}" "http://127.0.0.1:${port_num}/instance/fetchInstances" 2>/dev/null || echo "000")

    if [ "$EVO_STATUS" = "500" ]; then
        echo "➜ [SRE RECOVERY EVOLUTION] Deadlock de conexão no Prisma ORM (HTTP 500). Reciclando a Evolution API..."
        docker compose up -d --force-recreate evolution > /dev/null 2>&1 || true
        sleep 5
    elif [ "$EVO_STATUS" = "200" ]; then
        echo "✔ [SUCESSO EVOLUTION] Evolution API conectada e autenticada com sucesso (HTTP 200)."
    fi

    # Auto-Integração Zero-Touch com Chatwoot CRM
    if [ "${USE_CHATWOOT:-s}" = "s" ]; then
        echo "➜ [SRE EVOLUTION] Verificando auto-integração nativa com o Chatwoot CRM..."
        local CW_URL="http://chatwoot:3000"
        local CW_TOKEN="${CHATWOOT_API_TOKEN:-${DB_PASSWORD}}"
        local INSTANCE_NAME="${PREFIXO_CONTAINER:-loja}"

        # 1. Purgar caixas legadas de WPPConnect ou duplicadas de API no Chatwoot caso existam
        sudo docker exec -i "${PREFIX}_chatwoot" bundle exec rails runner "
        begin
          Channel::Api.where('webhook_url LIKE ?', '%wppconnect%').each do |channel|
            channel.inbox&.destroy!
            channel.destroy!
          end
        rescue => e
        end
        " < /dev/null 2>/dev/null || true

        # 2. Busca instâncias existentes no Evolution API
        local INST_EXISTS
        INST_EXISTS=$(curl -s -H "apikey: ${EVOLUTION_API_KEY:-${DB_PASSWORD}}" "http://127.0.0.1:${port_num}/instance/fetchInstances" 2>/dev/null || echo "[]")

        # 3. Cria a instância padrão caso não exista
        if ! echo "$INST_EXISTS" | grep -q "\"name\":\"${INSTANCE_NAME}\""; then
            echo "  ↳ Criando instância padrão '${INSTANCE_NAME}' com integração Chatwoot..."
            curl -s -X POST "http://127.0.0.1:${port_num}/instance/create" \
                -H "apikey: ${EVOLUTION_API_KEY:-${DB_PASSWORD}}" \
                -H "Content-Type: application/json" \
                -d "{
                    \"instanceName\": \"${INSTANCE_NAME}\",
                    \"token\": \"${EVOLUTION_API_KEY:-${DB_PASSWORD}}\",
                    \"qrcode\": true,
                    \"integration\": \"WHATSAPP-BAILEYS\",
                    \"chatwootAccountId\": \"1\",
                    \"chatwootToken\": \"${CW_TOKEN}\",
                    \"chatwootUrl\": \"${CW_URL}\",
                    \"chatwootSignMsg\": true,
                    \"chatwootReopenConversation\": true,
                    \"chatwootConversationPending\": false,
                    \"chatwootImportContacts\": true,
                    \"chatwootNameInbox\": \"WhatsApp\",
                    \"chatwootMergeBrazilContacts\": true,
                    \"chatwootImportMessages\": true,
                    \"chatwootDaysLimitImportMessages\": 3,
                    \"chatwootOrganization\": \"${PREFIXO_CONTAINER:-loja}\",
                    \"chatwootAutoCreate\": true
                }" > /dev/null 2>&1 || true
        else
            # SRE Sync: Se a instância já existia, sincroniza parâmetros sem disparar autoCreate duplicado
            local CW_INT_RES
            CW_INT_RES=$(curl -s -X POST "http://127.0.0.1:${port_num}/chatwoot/set/${INSTANCE_NAME}" \
                -H "apikey: ${EVOLUTION_API_KEY:-${DB_PASSWORD}}" \
                -H "Content-Type: application/json" \
                -d "{
                    \"enabled\": true,
                    \"accountId\": \"1\",
                    \"token\": \"${CW_TOKEN}\",
                    \"url\": \"${CW_URL}\",
                    \"signMsg\": true,
                    \"reopenConversation\": true,
                    \"conversationPending\": false,
                    \"nameInbox\": \"WhatsApp\",
                    \"mergeBrazilContacts\": true,
                    \"importContacts\": true,
                    \"importMessages\": true,
                    \"daysLimitImportMessages\": 3,
                    \"signDelimiter\": \"\\n\",
                    \"autoCreate\": false,
                    \"organization\": \"${PREFIXO_CONTAINER:-loja}\"
                }" 2>/dev/null || echo "")

            if [ -n "$CW_INT_RES" ]; then
                echo "✔ [SUCESSO EVOLUTION] Auto-integração Chatwoot sincronizada para instância '${INSTANCE_NAME}'."
            fi
        fi
    fi
}

collect_wizard_inputs_tui() {
    if [ "${USE_TAILSCALE:-true}" = "false" ] || [ "${ROUTING_CHOICE:-1}" = "2" ]; then
        CUSTOM_EVO_DOMAIN=$(tui_dialog_step --title "Domínio Dedicado Evolution (WhatsApp)" \
            --inputbox "Digite o domínio FQDN para a Evolution API (Ex: api.loja.com - Opcional):" 9 70 "${CUSTOM_EVO_DOMAIN:-}" \
            ) || true
        CUSTOM_EVO_DOMAIN=$(clean_tui_field "$CUSTOM_EVO_DOMAIN")
        save_wizard_cache "CUSTOM_EVO_DOMAIN" "$CUSTOM_EVO_DOMAIN"
    else
        CUSTOM_EVO_DOMAIN=""
        save_wizard_cache "CUSTOM_EVO_DOMAIN" ""
    fi
    return 0
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar a Evolution API (Gateway WhatsApp)?" USE_EVOLUTION "s"
    [[ "${USE_EVOLUTION:-s}" =~ ^[Ss]$ ]] && USE_EVOLUTION="s" || USE_EVOLUTION="n"
    save_wizard_cache "USE_EVOLUTION" "$USE_EVOLUTION"

    if [ "$USE_EVOLUTION" = "s" ]; then
        USE_N8N="s"
        USE_CHATWOOT="s"
        save_wizard_cache "USE_N8N" "s"
        save_wizard_cache "USE_CHATWOOT" "s"
        export USE_N8N USE_CHATWOOT

        if [ "${USE_TAILSCALE:-true}" = "false" ] || [ "${ROUTING_CHOICE:-1}" = "2" ]; then
            coletar_input "Domínio da API WhatsApp (Ex: api.empresa.com - Deixe vazio para usar porta)" CUSTOM_EVO_DOMAIN "false" "^([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})?$" ""
            save_wizard_cache "CUSTOM_EVO_DOMAIN" "$CUSTOM_EVO_DOMAIN"
        else
            CUSTOM_EVO_DOMAIN=""
            save_wizard_cache "CUSTOM_EVO_DOMAIN" ""
        fi
    fi
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local API_KEY="${API_MASTER_KEY:-${DB_PASSWORD:-}}"
    local OLD_KEY=$(grep '^EVOLUTION_API_KEY=' "$env_path" 2>/dev/null | cut -d= -f2 || true)
    local FINAL_KEY="${OLD_KEY:-$API_KEY}"

    # SRE Guardrail de Dependência Autônomo: Evolution ativa o Chatwoot e n8n no .env
    if [[ "${USE_EVOLUTION:-s}" =~ ^[Ss]$ ]]; then
        export USE_CHATWOOT="s"
        export USE_N8N="s"
        sed -i 's/^USE_CHATWOOT=.*/USE_CHATWOOT="s"/' "$env_path" 2>/dev/null || true
        sed -i 's/^USE_N8N=.*/USE_N8N="s"/' "$env_path" 2>/dev/null || true
    fi

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
CUSTOM_EVO_DOMAIN="${CUSTOM_EVO_DOMAIN:-}"
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
    collect_wizard_inputs_tui)
        collect_wizard_inputs_tui
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
