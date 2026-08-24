#!/usr/bin/env bash
#
# ===============================================================================
#  DAEMIND SRE MODULE - TAILSCALE MESH & PERIMETER ENGINE: install_0ts.sh
#  Especificação: Gestão completa de ciclo de vida do Tailscale VPN, OAuth,
#  Hardening, Limpeza de Nós Órfãos, Funnel Ingress, Recuperação, Wizard e Envs.
# ===============================================================================

[ "${2:-}" = "load_only" ] || set -eo pipefail

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="./.env"

if [ -f "$ENV_FILE" ] && [ "${2:-}" != "load_only" ]; then
    if [ -r "$ENV_FILE" ]; then
        set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
    elif command -v sudo &>/dev/null; then
        eval "$(sudo cat "$ENV_FILE" 2>/dev/null | grep -E '^[A-Za-z0-9_]+=' | sed 's/^/export /')" 2>/dev/null || true
    fi
fi

PREFIX="${PREFIXO_CONTAINER}"
EMAIL="${TS_EMAIL:-}"
CLIENT_ID="${TS_OAUTH_ID:-}"
CLIENT_SECRET="${TS_OAUTH_SECRET:-}"
CADDY_PORT="${HOST_CADDY_PORT:-80}"
EVO_PORT_EXT="${HOST_EVO_PORT:-18081}"

# ===============================================================================
# 0. collect_wizard_inputs (CLI) & collect_wizard_inputs_tui (TUI) & build_envs
# ===============================================================================
collect_wizard_inputs_tui() {
    local ts_substep=1

    while [ "$ts_substep" -ge 1 ] && [ "$ts_substep" -le 2 ]; do
        case "$ts_substep" in
            1)
                local ROUTING_VAL="${ROUTING_CHOICE:-1}"
                local ITEM1_ST="on"
                local ITEM2_ST="off"
                [ "$ROUTING_VAL" = "2" ] && { ITEM1_ST="off"; ITEM2_ST="on"; }

                local _rc_raw
                _rc_raw=$(tui_dialog_step --title "Passo 2/6: Topologia de Borda & Acesso Externo" \
                    --radiolist "Selecione o modelo de exposição de rede e certificados TLS:" 12 74 2 \
                    "1" "Tailscale Mesh VPN (Zero-Trust, TLS Automático Let's Encrypt)" "$ITEM1_ST" \
                    "2" "Domínio Próprio / BYODNS (Proxy Reverso / Cloudflare / IP Estático)" "$ITEM2_ST" \
                    )
                if [ $? -ne 0 ]; then
                    return 1
                fi
                ROUTING_CHOICE=$(echo "$_rc_raw" | tr -d '"\r\n\t ' || true)
                [ -z "$ROUTING_CHOICE" ] && ROUTING_CHOICE="1"

                save_wizard_cache "ROUTING_CHOICE" "$ROUTING_CHOICE"
                export ROUTING_CHOICE
                ts_substep=2
                ;;

            2)
                if [ "$ROUTING_CHOICE" = "1" ]; then
                    USE_TAILSCALE="true"
                    CUSTOM_DOMAIN=""
                    CUSTOM_EVO_DOMAIN=""
                    CADDY_PROTOCOL="https"
                    save_wizard_cache "USE_TAILSCALE" "true"
                    save_wizard_cache "CUSTOM_DOMAIN" ""
                    save_wizard_cache "CUSTOM_EVO_DOMAIN" ""
                    save_wizard_cache "CADDY_PROTOCOL" "https"

                    while true; do
                        TS_OAUTH_SECRET=$(tui_dialog_step --title "Tailscale OAuth Client Secret" \
                            --inputbox "Digite o Tailscale OAuth Client Secret (Ex: tskey-client-k1234567890abcdef-xxxxxxxxxxxx):" 9 76 "${TS_OAUTH_SECRET:-}" \
                            )
                        if [ $? -ne 0 ]; then
                            ts_substep=1
                            break
                        fi
                        TS_OAUTH_SECRET=$(clean_tui_field "$TS_OAUTH_SECRET")

                        if [[ "$TS_OAUTH_SECRET" =~ tskey-client-([A-Za-z0-9]{17})- ]]; then
                            TS_OAUTH_ID="${BASH_REMATCH[1]}"
                            save_wizard_cache "TS_OAUTH_ID" "$TS_OAUTH_ID"
                            save_wizard_cache "TS_OAUTH_SECRET" "$TS_OAUTH_SECRET"
                            export TS_OAUTH_ID TS_OAUTH_SECRET
                            return 0
                        else
                            tui_dialog --title "Erro no Tailscale Secret" --msgbox "O formato do Tailscale OAuth Client Secret é inválido! Ele deve começar com 'tskey-client-' seguido do ID de 17 caracteres." 8 70 || true
                        fi
                    done
                else
                    USE_TAILSCALE="false"
                    TS_OAUTH_SECRET=""
                    TS_OAUTH_ID=""
                    save_wizard_cache "USE_TAILSCALE"   "false"
                    save_wizard_cache "TS_OAUTH_SECRET" ""
                    save_wizard_cache "TS_OAUTH_ID"     ""
                    unset TS_OAUTH_ID TS_OAUTH_SECRET 2>/dev/null || true
                    export USE_TAILSCALE

                    local BYODNS_OUT
                    BYODNS_OUT=$(tui_dialog_step --title "Domínio Próprio (BYODNS)" \
                        --mixedform "Configure os domínios FQDN e o protocolo para a stack:" 17 88 0 \
                        "Domínio Painel Mestre (Ex: painel.loja.com):" 1 1 "${CUSTOM_DOMAIN:-}" 1 46 36 80 0 \
                        "Domínio API WhatsApp (Ex: api.loja.com):"     2 1 "${CUSTOM_EVO_DOMAIN:-}" 2 46 36 80 0 \
                        )
                    if [ $? -ne 0 ]; then
                        ts_substep=1
                        continue
                    fi
                    CUSTOM_DOMAIN=$(clean_tui_field "$(echo "$BYODNS_OUT" | sed -n '1p')")
                    CUSTOM_EVO_DOMAIN=$(clean_tui_field "$(echo "$BYODNS_OUT" | sed -n '2p')")
                    [ -z "$CUSTOM_DOMAIN" ] && CUSTOM_DOMAIN="localhost"
                    save_wizard_cache "CUSTOM_DOMAIN" "$CUSTOM_DOMAIN"
                    save_wizard_cache "CUSTOM_EVO_DOMAIN" "$CUSTOM_EVO_DOMAIN"

                    local TLS_OPT1="on"
                    local TLS_OPT2="off"
                    [ "${CADDY_PROTOCOL:-https}" = "http" ] && { TLS_OPT1="on"; TLS_OPT2="off"; } || { TLS_OPT1="off"; TLS_OPT2="on"; }
                    local TLS_CHOICE
                    TLS_CHOICE=$(tui_dialog_step --title "Tratamento de Certificado TLS (BYODNS)" \
                        --radiolist "Como o tráfego chegará no servidor local?" 12 72 2 \
                        "1" "Offload Externo (Cloudflare Proxy / NPM) -> HTTP porta 80" "$TLS_OPT1" \
                        "2" "Caddy SSL Nativo (Let's Encrypt direto) -> HTTPS portas 80/443" "$TLS_OPT2" \
                        )
                    if [ $? -ne 0 ]; then
                        ts_substep=1
                        continue
                    fi
                    [ "$TLS_CHOICE" = "1" ] && CADDY_PROTOCOL="http" || CADDY_PROTOCOL="https"
                    save_wizard_cache "CADDY_PROTOCOL" "$CADDY_PROTOCOL"
                    return 0
                fi
                ;;
        esac
    done
    return 1
}

collect_wizard_inputs() {
    echo ""
    echo -e "\e[33m=== [SRE TAILSCALE] Topologia de Borda & Roteamento ===\e[0m"
    echo "1) Tailscale Mesh & Funnel (Padrão SRE - Zero-Trust, Túneis Seguros)"
    echo "2) Bring Your Own DNS (BYODNS - Cloudflare Tunnels, NPM, IP Fixo)"
    if [ -n "$ROUTING_CHOICE" ]; then
        echo -e "\e[32m✔ [CACHE TAILSCALE] Modelo de exposição restaurado: ${ROUTING_CHOICE}\e[0m"
    else
        pausar_cronometro 2>/dev/null || true
        while true; do
            read -p "➜ Escolha o modelo de exposição (1 ou 2): " ROUTING_CHOICE < /dev/tty
            ROUTING_CHOICE=$(echo "${ROUTING_CHOICE:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
            case "$ROUTING_CHOICE" in
                1|2) 
                    save_wizard_cache "ROUTING_CHOICE" "$ROUTING_CHOICE"
                    break 
                    ;;
                *) echo -e "\e[31m[ERRO TAILSCALE] Opção inválida. Digite 1 ou 2.\e[0m" ;;
            esac
        done
        retomar_cronometro 2>/dev/null || true
    fi

    export ROUTING_CHOICE

    if [ "$ROUTING_CHOICE" = "1" ]; then
        USE_TAILSCALE="true"
        CUSTOM_DOMAIN=""
        CUSTOM_EVO_DOMAIN=""
        CADDY_PROTOCOL="https"
        while true; do
            coletar_input "Tailscale OAuth Client Secret (63 chars)" TS_OAUTH_SECRET "true" "" "63"
            if [[ "$TS_OAUTH_SECRET" =~ tskey-client-([A-Za-z0-9]{17})- ]]; then
                TS_OAUTH_ID="${BASH_REMATCH[1]}"
                save_wizard_cache "TS_OAUTH_ID" "$TS_OAUTH_ID"
                save_wizard_cache "TS_OAUTH_SECRET" "$TS_OAUTH_SECRET"
                break
            else
                echo -e "\e[31m[ERRO CRÍTICO TAILSCALE] O formato do Tailscale OAuth Client Secret é inválido!\e[0m"
            fi
        done
    else
        USE_TAILSCALE="false"
        TS_OAUTH_SECRET="bypass_sec"
        TS_OAUTH_ID="bypass_id"
        save_wizard_cache "TS_OAUTH_SECRET" "$TS_OAUTH_SECRET"
        save_wizard_cache "TS_OAUTH_ID" "$TS_OAUTH_ID"
        
        echo ""
        echo -e "\e[33m=== [SRE TAILSCALE] Configuração BYODNS (Traga seu próprio DNS) ===\e[0m"
        coletar_input "Domínio do Painel Mestre (Ex: painel.empresa.com)" CUSTOM_DOMAIN "false" "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" ""
        coletar_input "Domínio da API WhatsApp (Ex: api.empresa.com)" CUSTOM_EVO_DOMAIN "false" "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" ""
        
        echo -e "\e[36mComo o tráfego chegará no servidor local?\e[0m"
        echo "1) Offload Externo (Cloudflare Proxy / Nginx Proxy Manager) -> Caddy sobe em HTTP."
        echo "2) Caddy SSL Nativo (Let's Encrypt) -> Exige IP Fixo apontado diretamente para a VM."
        coletar_input "Escolha o tratamento TLS (1-2)" TLS_CHOICE "false" "^[1-2]$" ""
        [ "$TLS_CHOICE" = "1" ] && CADDY_PROTOCOL="http" || CADDY_PROTOCOL="https"
        save_wizard_cache "CADDY_PROTOCOL" "$CADDY_PROTOCOL"
    fi

    save_wizard_cache "ROUTING_CHOICE" "$ROUTING_CHOICE"
    save_wizard_cache "USE_TAILSCALE" "$USE_TAILSCALE"
    save_wizard_cache "CUSTOM_DOMAIN" "$CUSTOM_DOMAIN"
    save_wizard_cache "CUSTOM_EVO_DOMAIN" "$CUSTOM_EVO_DOMAIN"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    cat << EOF >> "$env_path"

# =========================================================================
# TOPOLOGIA DE BORDA (ROTEAMENTO SRE & DOMÍNIOS)
# =========================================================================
USE_TAILSCALE="${USE_TAILSCALE:-true}"
CUSTOM_DOMAIN="${CUSTOM_DOMAIN}"
CUSTOM_EVO_DOMAIN="${CUSTOM_EVO_DOMAIN}"
CADDY_PROTOCOL="${CADDY_PROTOCOL:-https}"

# =========================================================================
# REDE PRIVADA E PERÍMETRO (TAILSCALE OAUTH)
# =========================================================================
TS_OAUTH_ID="${TS_OAUTH_ID}"
TS_OAUTH_SECRET="${TS_OAUTH_SECRET}"
EOF
}

# ===============================================================================
# 1. install_binary: Instalação do binário oficial, serviço e Hardening
# ===============================================================================
install_binary() {
    echo "=== [SRE TAILSCALE] Instalação do Tailscale Nativo no Host ==="
    if ! command -v tailscale &>/dev/null; then
        echo "  ↳ Binário ausente. Baixando e instalando (Modo Seguro)..."
        sudo rm -f /etc/resolv.conf
        echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
        
        # SRE FIX: Injetado env NONINTERACTIVE=1 para execução não-interativa e blindada
        # Prevenção SRE contra triggers quebrados de dracut/initramfs de kernels órfãos
        sudo dpkg --configure -a >/dev/null 2>&1 || true

        local ts_install_ok=0
        if curl -fsSL --retry 3 --connect-timeout 15 https://tailscale.com/install.sh | sudo env NONINTERACTIVE=1 sh > /tmp/debug_tailscale.log 2>&1; then
            ts_install_ok=1
        fi

        # Se o script do Tailscale retornou erro apenas devido a triggers de terceiros (ex: dracut/initramfs),
        # mas o binário do Tailscale foi de fato instalado no sistema:
        if [ "$ts_install_ok" -eq 0 ]; then
            if command -v tailscale &>/dev/null; then
                echo "⚠️  [SRE WARN TAILSCALE] O apt retornou aviso de trigger no SO, mas o binário do Tailscale foi instalado com sucesso."
                ts_install_ok=1
            else
                echo "🚨 [ERRO CRÍTICO TAILSCALE] Falha ao instalar Tailscale. Verifique: tail -f /tmp/debug_tailscale.log"
                exit 1
            fi
        fi
        echo "✔ [SUCESSO TAILSCALE] Binário do Tailscale instalado com sucesso."
    else
        echo "➜ [IDEMPOTÊNCIA TAILSCALE] Tailscale já instalado no host."
    fi

    # Hardening de Privacidade (Zero Logs para Suporte)
    if [ -f /etc/default/tailscaled ] && grep -q 'TS_NO_LOGS_NO_SUPPORT="true"' /etc/default/tailscaled 2>/dev/null; then
        echo "➜ [IDEMPOTÊNCIA TAILSCALE] Hardening de privacidade do Tailscale já ativado."
    else
        echo "➜ [SRE TAILSCALE] Aplicando Hardening de Privacidade no Tailscale..."
        sudo touch /etc/default/tailscaled
        sudo sed -i '/TS_NO_LOGS_NO_SUPPORT/d' /etc/default/tailscaled 2>/dev/null || true
        echo 'TS_NO_LOGS_NO_SUPPORT="true"' | sudo tee -a /etc/default/tailscaled > /dev/null
        sudo systemctl enable --now tailscaled > /dev/null 2>&1 || true
        sudo systemctl restart tailscaled || true
        echo "✔ [SUCESSO TAILSCALE] Hardening de privacidade aplicado e tailscaled reiniciado."
    fi
}

# ===============================================================================
# 2. restore_identity: Restauração preventiva do estado do nó e certificados TLS
# ===============================================================================
restore_identity() {
    echo "➜ [SRE TAILSCALE] Verificando backups locais de identidade de nó..."
    local TS_STATUS
    TS_STATUS=$(tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null || echo "NoState")

    local USER_HOME_REAL=""
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        USER_HOME_REAL=$(eval echo "~$SUDO_USER")
    fi

    local BACKUP_TS_FONTE=""
    if [ -n "$USER_HOME_REAL" ] && [ -f "${USER_HOME_REAL}/tailscale_state_${PREFIX}_backup.tar.gz" ]; then
        BACKUP_TS_FONTE="${USER_HOME_REAL}/tailscale_state_${PREFIX}_backup.tar.gz"
    else
        # Varre diretórios /home/* reais por arquivos de backup de identidade
        for user_dir in /home/*; do
            if [ -d "$user_dir" ] && [ -f "${user_dir}/tailscale_state_${PREFIX}_backup.tar.gz" ]; then
                USER_HOME_REAL="$user_dir"
                BACKUP_TS_FONTE="${user_dir}/tailscale_state_${PREFIX}_backup.tar.gz"
                break
            fi
        done
    fi

    [ -z "$USER_HOME_REAL" ] && USER_HOME_REAL="$HOME"

    if [ -f "$BACKUP_TS_FONTE" ]; then
        if [ "$TS_STATUS" != "Running" ]; then
            echo "➜ [SRE TAILSCALE] Identidade estável do Tailscale localizada em ${BACKUP_TS_FONTE}. Restaurando estado..."
            sudo systemctl stop tailscaled
            sudo mkdir -p /var/lib/tailscale
            sudo tar -xzf "$BACKUP_TS_FONTE" -C /var/lib/tailscale/ 2>/dev/null || true
            sudo chmod 700 /var/lib/tailscale
            sudo systemctl start tailscaled
            sleep 3
            echo "✔ [SUCESSO TAILSCALE] Identidade do nó e certificados TLS restaurados."
        else
            echo "➜ [IDEMPOTÊNCIA TAILSCALE] Nó Tailscale já autenticado e operando em status Running."
        fi
    else
        echo "➜ [IDEMPOTÊNCIA TAILSCALE] Nenhum backup de identidade anterior aplicável localizado em ${USER_HOME_REAL}."
    fi
}

# ===============================================================================
# 3. get_oauth_token: Helper para geração de access_token via API OAuth
# ===============================================================================
get_oauth_token() {
    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" = "bypass_sec" ]; then
        echo ""
        return 0
    fi

    local TOKEN_JSON
    TOKEN_JSON=$(curl -s -d "client_id=${CLIENT_ID}" -d "client_secret=${CLIENT_SECRET}" "https://api.tailscale.com/api/v2/oauth/token" || echo "{}")
    local ACCESS_TOKEN
    ACCESS_TOKEN=$(echo "$TOKEN_JSON" | jq -r '.access_token // empty' 2>/dev/null || echo "")
    echo "$ACCESS_TOKEN"
}

# ===============================================================================
# 4. cleanup_orphans: Expurgo de nós inativos/órfãos com Guardrail Antisuicídio
# ===============================================================================
cleanup_orphans() {
    echo "=== [SRE TAILSCALE] Executando protocolo de limpeza de nós órfãos ==="
    local ACCESS_TOKEN
    ACCESS_TOKEN=$(get_oauth_token)

    if [ -z "$ACCESS_TOKEN" ]; then
        echo "⚠️ [SRE SKIP TAILSCALE] Token OAuth ausente ou inválido. Ignorando expurgo via API."
        return 0
    fi

    local MY_LOCAL_IP
    MY_LOCAL_IP=$(tailscale ip -4 2>/dev/null | tr -d '\r\n ' || echo "")

    local DEVICES_JSON
    DEVICES_JSON=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://api.tailscale.com/api/v2/tailnet/${EMAIL}/devices" || echo "{}")

    echo "$DEVICES_JSON" | jq -c '.devices[]? | select(.hostname | test("^'"${PREFIX}"'(-[0-9]+)?$"))' 2>/dev/null | while read -r device; do
        [ -z "$device" ] && continue
        local DEVICE_ID
        DEVICE_ID=$(echo "$device" | jq -r '.id')
        local DEVICE_NAME
        DEVICE_NAME=$(echo "$device" | jq -r '.name // .hostname')
        local DEVICE_IP
        DEVICE_IP=$(echo "$device" | jq -r '.addresses[0] // empty')
        local CONNECTED
        CONNECTED=$(echo "$device" | jq -r '.connectedToControl // false')

        # GUARDRAIL: Se o IP do dispositivo da API for igual ao IP da nossa máquina atual, IGNORA!
        if [ -n "$MY_LOCAL_IP" ] && [ "$DEVICE_IP" = "$MY_LOCAL_IP" ]; then
            echo "🛡️ [GUARDRAIL TAILSCALE] Protegendo o nó ativo atual: ${DEVICE_NAME} (${DEVICE_IP})"
            continue
        fi

        # Se estiver inativo (false ou null), expurga do painel
        if [ "$CONNECTED" = "false" ] || [ "$CONNECTED" = "null" ]; then
            echo "🚨 [PURGE TAILSCALE] Removendo nó órfão inativo: ${DEVICE_NAME} (ID: ${DEVICE_ID})"
            curl -s -X DELETE -u "${ACCESS_TOKEN}:" "https://api.tailscale.com/api/v2/device/${DEVICE_ID}" > /dev/null 2>&1 || true
        fi
    done
    echo "✔ [SUCESSO TAILSCALE] Varredura e purga de nós órfãos concluída."
}

# ===============================================================================
# 5. authenticate_node: Autenticação Idempotente na Tailnet
# ===============================================================================
authenticate_node() {
    if [ "${USE_TAILSCALE:-true}" = "false" ]; then
        echo "➜ [SRE SKIP TAILSCALE] Modo BYODNS Ativado. Omitindo autenticação Tailscale."
        return 0
    fi

    echo "➜ [SRE TAILSCALE] Garantindo inicialização e autenticação do agente..."
    sudo systemctl enable --now tailscaled > /dev/null 2>&1 || true

    restore_identity

    local TS_STATUS
    TS_STATUS=$(tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null || echo "NoState")

    if [ "$TS_STATUS" = "Running" ]; then
        echo "➜ [SRE TAILSCALE] Nó já autenticado na Tailnet. Reaplicando configurações (Preservando Identidade)..."
        sudo tailscale up --advertise-tags=tag:production --accept-dns=true --hostname="${PREFIX}"
    else
        echo "➜ [SRE TAILSCALE] Nó não autenticado. Solicitando Auth Key via API OAuth para: ${EMAIL}..."
        local ACCESS_TOKEN
        ACCESS_TOKEN=$(get_oauth_token)

        if [ -z "$ACCESS_TOKEN" ]; then
            echo "🚨 [ERRO CRÍTICO TAILSCALE] Falha ao obter access_token OAuth da API do Tailscale."
            exit 1
        fi

        # Executa limpeza prévia de órfãos antes de gerar a nova chave
        cleanup_orphans

        local KEY_JSON
        KEY_JSON=$(curl -s -X POST -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"capabilities\": {\"devices\": {\"create\": {\"reusable\": false, \"ephemeral\": false, \"tags\": [\"tag:production\"]}}}}" \
            "https://api.tailscale.com/api/v2/tailnet/${EMAIL}/keys" || echo "{}")
        
        local PERSISTENT_AUTH_KEY
        PERSISTENT_AUTH_KEY=$(echo "$KEY_JSON" | jq -r '.key // empty' 2>/dev/null || echo "")

        if [ -z "$PERSISTENT_AUTH_KEY" ]; then
            echo "🚨 [ERRO CRÍTICO TAILSCALE] Falha ao gerar chave de autenticação na API da Tailnet."
            exit 1
        fi

        echo "➜ [SRE TAILSCALE] Autenticando nó na Tailnet com Auth Key temporária..."
        sudo tailscale up --auth-key="${PERSISTENT_AUTH_KEY}" --advertise-tags=tag:production --accept-dns=true --hostname="${PREFIX}"
        echo "✔ [SUCESSO TAILSCALE] Nó autenticado com sucesso na Tailnet."
    fi

    configure_funnels
    get_domain
}

# ===============================================================================
# 6. configure_funnels: Ativação dos túneis de borda HTTPS (Tailscale Funnel)
# ===============================================================================
configure_funnels() {
    if [ "${USE_TAILSCALE:-true}" = "false" ]; then
        echo "➜ [SRE SKIP TAILSCALE] Modo BYODNS Ativado. Omitindo configuração do Funnel."
        return 0
    fi

    local FUNNEL_STATUS=$(sudo tailscale funnel status 2>/dev/null || echo "")
    if echo "$FUNNEL_STATUS" | grep -q "https://.*:443" && echo "$FUNNEL_STATUS" | grep -q "${CADDY_PORT}"; then
        if echo "$FUNNEL_STATUS" | grep -q "https://.*:8443" && echo "$FUNNEL_STATUS" | grep -q "${EVO_PORT_EXT}"; then
            echo "➜ [IDEMPOTÊNCIA TAILSCALE] Túneis Funnel já ativos e roteando (Porta 443 -> ${CADDY_PORT} e Porta 8443 -> ${EVO_PORT_EXT})."
            return 0
        fi
    fi

    echo "➜ [CONFIGURANDO TAILSCALE] Ativando túneis de borda do Tailscale Funnel (Portas ${CADDY_PORT} e ${EVO_PORT_EXT})..."
    sudo tailscale funnel --bg "${CADDY_PORT}" > /dev/null 2>&1 || true
    sudo tailscale funnel --bg --https=8443 "${EVO_PORT_EXT}" > /dev/null 2>&1 || true
    echo "✔ [SUCESSO TAILSCALE] Túneis Funnel ativados em background (Porta 443 -> ${CADDY_PORT} e Porta 8443 -> ${EVO_PORT_EXT})."
}

# ===============================================================================
# 7. get_domain: Captura e validação determinística do domínio canônico (FQDN)
# ===============================================================================
get_domain() {
    if [ "${USE_TAILSCALE:-true}" = "false" ]; then
        local CUSTOM_D="${CUSTOM_DOMAIN:-localhost}"
        echo "$CUSTOM_D"
        return 0
    fi

    local DOMAIN=""
    local TENTATIVAS_DNS=0

    while [ -z "$DOMAIN" ]; do
        # SRE Padrão Indestrutível: Captura o DNSName seguro dentro do bloco do nó atual (Self)
        DOMAIN=$(tailscale status --json 2>/dev/null | grep -A 10 '"Self":' | grep '"DNSName"' | head -n 1 | cut -d'"' -f4 | sed 's/\.$//' | tr -d '\r\n ' || true)
     
        if [ -z "$DOMAIN" ]; then
            TENTATIVAS_DNS=$((TENTATIVAS_DNS+1))
            if [ "$TENTATIVAS_DNS" -ge 20 ]; then
                echo "[AVISO DE BARRAMENTO TAILSCALE] Timeout aguardando DNS público da Tailnet. Usando IP de interface como Fallback." >&2
                DOMAIN=$(tailscale ip -4 2>/dev/null | tr -d '\r\n ' || echo "localhost")
                break
            fi
            sleep 3
        fi
    done

    # Atualiza no .env de forma atômica se o arquivo existir
    PREFIX="${PREFIXO_CONTAINER}"
    if [ -z "$PREFIX" ] && [ -f "$ENV_FILE" ]; then
        PREFIX=$(sudo grep '^PREFIXO_CONTAINER=' "$ENV_FILE" 2>/dev/null | head -n 1 | cut -d= -f2 | tr -d '"' | tr -d "'" | tr -d ' ' || echo "")
    fi
    if [ -f "$ENV_FILE" ] && [ -n "$DOMAIN" ]; then
        if grep -q '^TS_DOMAIN=' "$ENV_FILE" 2>/dev/null; then
            sudo sed -i "s|^TS_DOMAIN=.*|TS_DOMAIN=\"${DOMAIN}\"|" "$ENV_FILE" 2>/dev/null || true
            sudo sed -i "s|^DOMAIN=.*|DOMAIN=\"${DOMAIN}\"|" "$ENV_FILE" 2>/dev/null || true
            sudo sed -i "s|^DOMAIN_NAME=.*|DOMAIN_NAME=\"${DOMAIN}\"|" "$ENV_FILE" 2>/dev/null || true
        fi
    fi

    echo "$DOMAIN"
}

# ===============================================================================
# 8. recovery: Protocolo de recuperação, auto-cura e reautenticação perimetral
# ===============================================================================
recovery() {
    echo "=== [SRE RECOVERY TAILSCALE] Iniciando protocolo de reautenticação perimetral ==="

    # 1. Desliga instâncias fantasmas do Funnel
    echo "➜ Limpando escopo de túneis antigos..."
    sudo tailscale funnel --https=443 off 2>/dev/null || true
    sudo tailscale funnel --https=8443 off 2>/dev/null || true

    # 2. Força o handshake limpo no painel usando a chave mestre do cliente com o reset protetivo
    echo "➜ Reautenticando nó ativo na Tailnet de forma estrita..."
    if [ -n "$CLIENT_SECRET" ] && [ "$CLIENT_SECRET" != "bypass_sec" ]; then
        sudo tailscale up --reset --auth-key="${CLIENT_SECRET}" --advertise-tags=tag:production --accept-dns=true --force-reauth || {
            echo "  ↳ Reautenticação direta falhou. Tentando via token de API..."
            authenticate_node
        }
    else
        sudo tailscale up --reset --advertise-tags=tag:production --accept-dns=true --force-reauth
    fi

    # 3. Reseta o daemon do sistema operacional para limpar o cache de memória do Kernel
    echo "➜ Resetando barramento do sistema operacional (tailscaled)..."
    sudo systemctl restart tailscaled
    sleep 5

    # 4. Reconstrói os tunnels do Funnel apontando para os sockets locais
    configure_funnels

    # 5. Executa a validação dinâmica de handshakes externos
    audit_health
}

# ===============================================================================
# 9. audit_health: Validação de handshakes externos, Funnel e Rate Limits ACME
# ===============================================================================
audit_health() {
    echo "=== [SRE AUDIT TAILSCALE] Validando estabilidade externa e túneis Tailscale ==="
    local FQDN
    FQDN=$(get_domain)

    local HTTP_GATEWAY_FUNNEL
    HTTP_GATEWAY_FUNNEL=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${FQDN}/healthz" || echo "000")

    local HTTP_EVO_FUNNEL
    HTTP_EVO_FUNNEL=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${FQDN}:8443/" || echo "000")

    echo "====================================================================="
    echo "➜ FQDN Canônico:            https://${FQDN}"
    echo "➜ Portal Gateway (443):     Status [${HTTP_GATEWAY_FUNNEL}]"
    echo "➜ Evolution API (8443):     Status [${HTTP_EVO_FUNNEL}]"
    echo "====================================================================="

    # Inspeção de logs ACME/Let's Encrypt para detecção proativa de Rate Limits
    local TS_RATE_LIMIT_LOG
    TS_RATE_LIMIT_LOG=$(journalctl -u tailscaled --no-pager 2>/dev/null | grep -iE "retry after|too many certificates|acme: error: 429|rate limit" | tail -n 1 || true)

    if [ -n "$TS_RATE_LIMIT_LOG" ]; then
        if echo "$TS_RATE_LIMIT_LOG" | grep -qi "retry after"; then
            local RETRY_DATE
            RETRY_DATE=$(echo "$TS_RATE_LIMIT_LOG" | sed -n 's/.*retry after \([0-9-]* [0-9:]* UTC\).*/\1/p')
            local LOCAL_RETRY
            LOCAL_RETRY=$(date -d "$RETRY_DATE" +'%d/%m/%Y às %H:%M:%S' 2>/dev/null || echo "$RETRY_DATE (UTC)")
            echo "⏳ [AVISO FINOPS TAILSCALE] Let's Encrypt Rate Limit ativo! HTTPS liberado em: ${LOCAL_RETRY}"
        else
            local MOTIVO
            MOTIVO=$(echo "$TS_RATE_LIMIT_LOG" | grep -oE "too many.*|rate limit.*" | head -n 1 || echo "Bloqueio ACME 429")
            echo "⏳ [AVISO FINOPS TAILSCALE] Let's Encrypt Rate Limit ativo! Motivo: ${MOTIVO}"
        fi
    fi

    if [ "$HTTP_GATEWAY_FUNNEL" = "200" ]; then
        echo "✔ [SUCESSO ABSOLUTO TAILSCALE] Barramento perimetral Tailscale operando em 100%."
    else
        echo "⚠️ [ALERTA TAILSCALE] Ambiente ativo, mas com oscilação no handshake público do Funnel."
    fi
}

# ===============================================================================
# 10. disable / teardown: Desligamento dos túneis e desconexão
# ===============================================================================
disable() {
    echo "➜ [SRE TEARDOWN TAILSCALE] Desativando túneis Tailscale Funnel..."
    sudo tailscale funnel --https=443 off 2>/dev/null || true
    sudo tailscale funnel --https=8443 off 2>/dev/null || true
    echo "✔ [SUCESSO TAILSCALE] Túneis do Funnel encerrados."
}

provision_infra() {
    local target_dir="${1:-${TARGET_DIR:-/opt/daemind}}"
    mkdir -p "$target_dir/volumes/tailscale_data"
    if [ "${USE_TAILSCALE:-false}" = "true" ]; then
        sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
        cat << 'EOF' | sudo tee /etc/dnsmasq.d/0ts.conf > /dev/null
# IPSET ALLOWED DOMAINS (TAILSCALE VPN)
ipset=/tailscale.com/ALLOWED_DOMAINS
ipset=/tailscale.io/ALLOWED_DOMAINS
ipset=/ts.net/ALLOWED_DOMAINS
ipset=/controlplane.tailscale.com/ALLOWED_DOMAINS
EOF
    else
        sudo rm -f /etc/dnsmasq.d/0ts.conf 2>/dev/null || true
    fi
    echo "➜ [INFRA TAILSCALE] Estrutura, DNS e diretórios Tailscale provisionados com sucesso."
}

build_structure() { :; }
provision_db() { :; }
inject_caddy_routes() { :; }
remove_caddy_routes() { :; }
inject_dashboard_card() { :; }
remove_dashboard_card() { :; }
start_container() { :; }
wait_readiness() { :; }
provision_user() { :; }
render_forensic_report() { :; }
get_version() { echo "Nativo"; }

# ===============================================================================
# Roteador CLI de Ações
# ===============================================================================
ACTION="${2:-all}"
case "$ACTION" in
    collect_wizard_inputs|collect_inputs|wizard_prompt)
        collect_wizard_inputs
        ;;
    collect_wizard_inputs_tui|collect_inputs_tui|wizard_tui)
        collect_wizard_inputs_tui
        ;;
    build_envs|build_env)
        build_envs
        ;;
    provision_infra|provision_structure)
        provision_infra
        ;;
    install|install_binary)
        install_binary
        ;;
    restore|restore_identity)
        restore_identity
        ;;
    cleanup|cleanup_orphans)
        cleanup_orphans
        ;;
    auth|authenticate|authenticate_node)
        authenticate_node
        ;;
    funnel|configure_funnels)
        configure_funnels
        ;;
    get_domain|domain)
        get_domain
        ;;
    recovery|ts_recovery)
        recovery
        ;;
    audit|audit_health)
        audit_health
        ;;
    disable|teardown)
        disable
        ;;
    all)
        install_binary
        authenticate_node
        ;;
    *)
        ;;
esac
