#!/usr/bin/env bash
# OLLAMA
# Inferência Local de LLMs (Requer 16GB+ RAM)
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO OLLAMA LOCAL AI
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório Ollama
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.15.01-DECOUPLED"

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
fi

build_structure() {
    echo "➜ [SRE OLLAMA] Criando estrutura física de volumes e permissões do Ollama..."
    sudo mkdir -p "$TARGET_DIR"/volumes/ollama_models 2>/dev/null || true
    
    local TARGET_OWNER="1000:1000"
    if [ -n "${SUDO_USER:-}" ]; then
        local TARGET_UID=$(id -u "$SUDO_USER" 2>/dev/null || echo "1000")
        local TARGET_GID=$(id -g "$SUDO_USER" 2>/dev/null || echo "1000")
        TARGET_OWNER="${TARGET_UID}:${TARGET_GID}"
    fi

    local CURRENT_OWNER=$(stat -c '%u:%g' "$TARGET_DIR/volumes/ollama_models" 2>/dev/null || echo "")
    if [ "$CURRENT_OWNER" != "$TARGET_OWNER" ]; then
        echo "  ↳ Ajustando permissões do volume ollama_models (${CURRENT_OWNER:-desconhecido} -> ${TARGET_OWNER})..."
        sudo chown -R "$TARGET_OWNER" "$TARGET_DIR/volumes/ollama_models" 2>/dev/null || true
    else
        echo "➜ [IDEMPOTÊNCIA OLLAMA] Permissões de ollama_models já alinhadas (${TARGET_OWNER}). Preservando I/O."
    fi
}

provision_db() {
    echo "➜ [SRE OLLAMA] O módulo Ollama opera de forma autônoma (banco relacional não requerido)."
}

provision_infra() {
    echo "➜ [SRE OLLAMA] Verificando integridade e firewall perimetral do Ollama..."
    local use_val="${USE_OLLAMA:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 11434 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 11434 -j ACCEPT 2>/dev/null || true
        fi
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE OLLAMA] Injetando rotas do Ollama AI no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q "reverse_proxy.*_ollama:11434" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:11434 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_ollama:11434
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
    if [ -f "$CADDYFILE_PATH" ] && grep -q "reverse_proxy.*_ollama:11434" "$CADDYFILE_PATH"; then
        echo "➜ [SRE OLLAMA] Removendo rotas do Ollama AI do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:11434\s*\{[\s\S]*?ollama[\s\S]*?\}', '', content)
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
    echo "➜ [SRE OLLAMA] Desativando módulo Ollama AI..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_ollama" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 11434 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 11434 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/ollama.conf ]; then
        sudo rm -f /etc/dnsmasq.d/ollama.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO OLLAMA] Módulo Ollama desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE OLLAMA] Garantindo subida integrada do container Ollama..."
    cd "$TARGET_DIR"
    sudo docker compose up -d ollama 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE OLLAMA] Validando prontidão de socket e healthcheck do Ollama..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local TENTATIVAS=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_ollama 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN OLLAMA] Ollama Local AI Server demorou a responder após 60s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done
    echo "✔ [SUCESSO OLLAMA] Ollama Local AI Server online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local health_ol=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_ollama 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_ol" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:11434/" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:11434  -> Status: [%s]\n" "Ollama Local AI API:" "${ts_domain}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_ollama"
    sudo docker exec "$container_name" ollama --version 2>/dev/null | grep -o '[0-9.]*' | head -n 1 || echo "latest"
}

provision_user() {
    echo "➜ [SRE OLLAMA] Engine Ollama pronta para recebimento de modelos via 'ollama pull'."
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local OLLAMA_PORT="${HOST_OLLAMA_PORT:-11434}"
    echo "  🦙 Ollama Local AI (Inferência Soberana)"
    echo "    ↳ API Endpoint:                    http://${ts_domain}:${OLLAMA_PORT}"
    echo "    ↳ Healthcheck:                     http://${ts_domain}:${OLLAMA_PORT}/api/tags"
    echo "    ↳ Volume de Modelos (Host):        ${TARGET_DIR}/volumes/ollama_models"
    echo ""
}

is_hardware_supported() {
    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_gb="${SYSTEM_TOTAL_RAM_GB:-${TOTAL_RAM_GB:-8}}"
    local has_gpu="${HAS_DEDICATED_GPU:-false}"
    local vram_mb="${GPU_VRAM_MB:-0}"

    # Requisitos Estritos: >4 vCPUs, >=16GB RAM e GPU Dedicada com >=4000MB VRAM
    if [ "$cpus" -le 4 ] || [ "$ram_gb" -lt 16 ] || [ "$has_gpu" != "true" ] || [ "$vram_mb" -lt 4000 ]; then
        return 1
    fi
    return 0
}

collect_wizard_inputs() {
    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_gb="${SYSTEM_TOTAL_RAM_GB:-${TOTAL_RAM_GB:-8}}"
    local gpu_name="${GPU_MODEL:-Nenhuma GPU compatível}"
    local vram_gb="${GPU_VRAM_GB:-0}"

    if ! is_hardware_supported; then
        echo -e "\e[33m⚠️ [SRE FinOps OLLAMA] Ollama Local AI desativado: requer host com >4 vCPUs, >=16 GB RAM e GPU >=4GB VRAM (Detectado: ${cpus} Cores, ${ram_gb}GB RAM, GPU: ${gpu_name} [${vram_gb}GB VRAM]).\e[0m"
        USE_OLLAMA="n"
    else
        coletar_sn "Deseja instalar o Ollama (Detectada GPU: ${gpu_name} [${vram_gb}GB VRAM])?" USE_OLLAMA "s"
        [[ "${USE_OLLAMA:-s}" =~ ^[Ss]$ ]] && USE_OLLAMA="s" || USE_OLLAMA="n"
    fi
    save_wizard_cache "USE_OLLAMA" "$USE_OLLAMA"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_ollama="4.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_ollama="6.0"
    fi

    local mem_ollama="8192M"
    local res_ollama="2048M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_ollama="16384M"
        res_ollama="8192M"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_ollama="8192M"
        res_ollama="4096M"
    fi

    cat << EOF >> "$env_path"

# --- Ollama Decoupled Env & Tuning ---
USE_OLLAMA="${USE_OLLAMA:-s}"
HOST_OLLAMA_PORT="11434"
CPU_OLLAMA=${CPU_OLLAMA:-${cpu_ollama}}
MEM_OLLAMA=${MEM_OLLAMA:-${mem_ollama}}
RES_OLLAMA=${RES_OLLAMA:-${res_ollama}}
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
