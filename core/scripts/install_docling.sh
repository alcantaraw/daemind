#!/usr/bin/env bash
# DOCLING
# OCR & Parsing de Documentos por IA
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO DOCLING OCR & DOC PARSER
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório Docling
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.15.01-DECOUPLED"

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
fi

build_structure() {
    echo "➜ [SRE DOCLING] Criando estrutura física de volumes e permissões do Docling..."
    sudo mkdir -p "$TARGET_DIR"/volumes/docling_data 2>/dev/null || true
    
    local TARGET_OWNER="1000:1000"
    if [ -n "${SUDO_USER:-}" ]; then
        local TARGET_UID=$(id -u "$SUDO_USER" 2>/dev/null || echo "1000")
        local TARGET_GID=$(id -g "$SUDO_USER" 2>/dev/null || echo "1000")
        TARGET_OWNER="${TARGET_UID}:${TARGET_GID}"
    fi

    local CURRENT_OWNER=$(stat -c '%u:%g' "$TARGET_DIR/volumes/docling_data" 2>/dev/null || echo "")
    if [ "$CURRENT_OWNER" != "$TARGET_OWNER" ]; then
        echo "  ↳ Ajustando permissões do volume docling_data (${CURRENT_OWNER:-desconhecido} -> ${TARGET_OWNER})..."
        sudo chown -R "$TARGET_OWNER" "$TARGET_DIR/volumes/docling_data" 2>/dev/null || true
    else
        echo "➜ [IDEMPOTÊNCIA DOCLING] Permissões de docling_data já alinhadas (${TARGET_OWNER}). Preservando I/O."
    fi
}

provision_db() {
    echo "➜ [SRE DOCLING] O módulo Docling opera como microserviço REST stateless (banco relacional não requerido)."
}

provision_infra() {
    echo "➜ [SRE DOCLING] Verificando integridade da infraestrutura e firewall perimetral do Docling..."
    local use_val="${USE_DOCLING:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
        cat << 'EOF' | sudo tee /etc/dnsmasq.d/docling.conf > /dev/null
# IPSET ALLOWED DOMAINS (DOCLING OCR & MODEL DOWNLOADS)
ipset=/huggingface.co/ALLOWED_DOMAINS
ipset=/api-inference.huggingface.co/ALLOWED_DOMAINS
ipset=/cdn-lfs.huggingface.co/ALLOWED_DOMAINS
EOF
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 5001 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 5001 -j ACCEPT 2>/dev/null || true
        fi
    else
        sudo rm -f /etc/dnsmasq.d/docling.conf 2>/dev/null || true
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE DOCLING] Injetando rotas do Docling OCR no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER:-}"
    if [ -z "$PREFIX" ] && [ -f "$ENV_FILE" ]; then
        PREFIX=$(sudo grep '^PREFIXO_CONTAINER=' "$ENV_FILE" 2>/dev/null | head -n 1 | cut -d= -f2 | tr -d '"' | tr -d "'" | tr -d ' ' || echo "")
    fi
    [ -z "$PREFIX" ] && PREFIX="${EMPRESA:-}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q "reverse_proxy.*_docling:5001" "$CADDYFILE_PATH"; then
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
    if [ -f "$CADDYFILE_PATH" ] && grep -q "reverse_proxy.*_docling:5001" "$CADDYFILE_PATH"; then
        echo "➜ [SRE DOCLING] Removendo rotas do Docling OCR do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:5001\s*\{[\s\S]*?docling[\s\S]*?\}', '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    :
}

remove_dashboard_card() {
    :
}

disable() {
    echo "➜ [SRE DOCLING] Desativando módulo Docling OCR..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_docling" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 5001 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 5001 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/docling.conf ]; then
        sudo rm -f /etc/dnsmasq.d/docling.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO DOCLING] Módulo Docling desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE DOCLING] Garantindo subida integrada do container Docling..."
    cd "$TARGET_DIR"
    sudo docker compose up -d docling 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE DOCLING] Validando prontidão de socket e healthcheck do Docling..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local TENTATIVAS=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_docling 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN DOCLING] Docling OCR demorou a responder após 60s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done
    echo "✔ [SUCESSO DOCLING] Docling OCR Server online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local health_dc=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_docling 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_dc" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:5001/health" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:5001  -> Status: [%s]\n" "Docling OCR / Doc API:" "${ts_domain}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_docling"
    local VER=$(sudo docker exec "$container_name" python3 -c 'import docling; print(docling.__version__)' 2>/dev/null || echo "")
    if [ -n "$VER" ]; then
        echo "v${VER}"
    else
        sudo docker inspect -f '{{.Config.Image}}' "$container_name" 2>/dev/null || echo "latest"
    fi
}

provision_user() {
    echo "➜ [SRE DOCLING] Microserviço Docling pronto para processamento assíncrono."
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local DOCLING_PORT="${HOST_DOCLING_PORT:-5001}"
    echo "  📑 Docling OCR & Parsing de Documentos"
    echo "    ↳ API Endpoint:                    http://${ts_domain}:${DOCLING_PORT}"
    echo "    ↳ Healthcheck:                     http://${ts_domain}:${DOCLING_PORT}/health"
    echo "    ↳ Volume de Dados (Host):          ${TARGET_DIR}/volumes/docling_data"
    echo ""
}

is_hardware_supported() {
    local cpus="${OVERRIDE_TOTAL_CPUS:-${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-}}}"
    local ram_gb="${OVERRIDE_TOTAL_RAM_GB:-${SYSTEM_TOTAL_RAM_GB:-${TOTAL_RAM_GB:-}}}"
    if [ -z "$cpus" ] || [ -z "$ram_gb" ]; then
        cpus=$(nproc 2>/dev/null || echo 4)
        local ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)
        ram_gb=$(( (ram_mb + 512) / 1024 ))
    fi
    if [ "$cpus" -le 4 ] || [ "$ram_gb" -lt 16 ]; then
        return 1
    fi
    return 0
}

collect_wizard_inputs() {
    local cpus="${OVERRIDE_TOTAL_CPUS:-${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}}"
    local ram_gb="${OVERRIDE_TOTAL_RAM_GB:-${SYSTEM_TOTAL_RAM_GB:-${TOTAL_RAM_GB:-8}}}"

    if ! is_hardware_supported; then
        echo -e "\e[33m⚠️ [SRE FinOps DOCLING] Docling OCR desativado: requer host com > 4 vCPUs e >= 16 GB RAM (Detectado pelo autotune: ${cpus} Cores, ${ram_gb} GB RAM).\e[0m"
        USE_DOCLING="n"
    else
        coletar_sn "Deseja instalar o Docling OCR (Extração & Parsing Avançado de Documentos)?" USE_DOCLING "s"
        [[ "${USE_DOCLING:-s}" =~ ^[Ss]$ ]] && USE_DOCLING="s" || USE_DOCLING="n"
    fi
    save_wizard_cache "USE_DOCLING" "$USE_DOCLING"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_docling="4.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_docling="6.0"
    fi

    local mem_docling="6144M"
    local res_docling="1024M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_docling="8192M"
        res_docling="4096M"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_docling="6144M"
        res_docling="2048M"
    fi

    cat << EOF >> "$env_path"

# --- Docling Decoupled Env & Tuning ---
USE_DOCLING="${USE_DOCLING:-s}"
HOST_DOCLING_PORT="5001"
CPU_DOCLING=${CPU_DOCLING:-${cpu_docling}}
MEM_DOCLING=${MEM_DOCLING:-${mem_docling}}
RES_DOCLING=${RES_DOCLING:-${res_docling}}
EOF
}

# Roteamento de funções via parâmetros CLI (Padrão de Contrato Desacoplado)
ACTION="${2:-all}"
case "$ACTION" in
    is_hardware_supported)
        is_hardware_supported
        exit $?
        ;;
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
