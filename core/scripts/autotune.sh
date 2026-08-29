#!/usr/bin/env bash
# ===============================================================================
#  DAEMIND SRE CORE - AUTOTUNE MOTOR (MATRIZ DINÂMICA DE RECURSOS)
#  Especificação: Extrai métricas cruas (CPU, RAM, DISCO) do Host
#  e dimensiona os limites e tunings otimizados do Núcleo Core Imutável.
# ===============================================================================

set -eo pipefail

# Função modular para extração pura de dados de hardware do Host
# Função modular para extração pura de dados de hardware do Host
get_host_hardware() {
    TOTAL_CPUS="${OVERRIDE_TOTAL_CPUS:-$(nproc 2>/dev/null || echo 4)}"
    TOTAL_RAM_MB="${OVERRIDE_TOTAL_RAM_MB:-$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)}"
    TOTAL_DISK_GB="${OVERRIDE_TOTAL_DISK_GB:-$(df -BG /opt 2>/dev/null | awk 'NR==2 {print $2}' | sed 's/G//' 2>/dev/null || echo 50)}"
    TOTAL_RAM_GB="${OVERRIDE_TOTAL_RAM_GB:-$(( (TOTAL_RAM_MB + 512) / 1024 ))}"
    
    IS_MODEST_SERVER="false"
    if [ "$TOTAL_CPUS" -le 4 ] || [ "$TOTAL_RAM_GB" -lt 8 ]; then
        IS_MODEST_SERVER="true"
    fi

    # Detecção Agnóstica de GPU Dedicada (NVIDIA, AMD RX 6000+, Intel Arc) >= 4GB VRAM
    local has_gpu="false"
    local vram_mb=0
    local gpu_model="none"
    local gpu_type="none"

    if [ -n "${OVERRIDE_GPU_VRAM_MB:-}" ]; then
        vram_mb="$OVERRIDE_GPU_VRAM_MB"
        [ "$vram_mb" -ge 4000 ] && has_gpu="true"
        gpu_model="Manual Override GPU"
        gpu_type="override"
    else
        # 1. NVIDIA (nvidia-smi)
        if command -v nvidia-smi >/dev/null 2>&1; then
            local nv_vram
            nv_vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d ' ' || echo "0")
            if [ "${nv_vram:-0}" -ge 4000 ] 2>/dev/null; then
                has_gpu="true"
                vram_mb="$nv_vram"
                gpu_model=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 | xargs || echo "NVIDIA GPU")
                gpu_type="nvidia"
            fi
        fi

        # 2. AMD Radeon (RX 6000+ / RDNA 2/3/3.5/4 / ROCm / Sysfs)
        if [ "$has_gpu" = "false" ] && lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -qi 'AMD\|Radeon'; then
            local amd_vram_bytes
            amd_vram_bytes=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -n 1 || echo "0")
            local amd_vram_mb=$(( amd_vram_bytes / 1024 / 1024 ))
            if [ "$amd_vram_mb" -ge 4000 ] 2>/dev/null; then
                if lspci 2>/dev/null | grep -iE 'AMD|Radeon' | grep -qiE 'Navi [2-4]|RX [6-9][0-9]{3}|Radeon Pro (W[6-9]|V[6-9])|[789][0-9]{2}M|Radeon 80[0-9]{2}|GFX1[0-2]'; then
                    has_gpu="true"
                    vram_mb="$amd_vram_mb"
                    gpu_model=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'AMD' | head -n 1 | sed 's/.*: //; s/(rev.*)//' | xargs || echo "AMD Radeon Series")
                    gpu_type="amd"
                fi
            fi
        fi

        # 3. Intel Arc (Alchemist / Battlemage / Celestial / Xe2)
        if [ "$has_gpu" = "false" ] && lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -qi 'Intel.*Arc\|DG2\|BMG\|Battlemage\|Alchemist\|Xe LPG\|Xe2'; then
            local intel_vram_bytes
            intel_vram_bytes=$(cat /sys/class/drm/card*/device/lmem_total_bytes 2>/dev/null | head -n 1 || echo "0")
            local intel_vram_mb=$(( intel_vram_bytes / 1024 / 1024 ))
            if [ "$intel_vram_mb" -ge 4000 ] 2>/dev/null; then
                has_gpu="true"
                vram_mb="$intel_vram_mb"
                gpu_model=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'Intel' | head -n 1 | sed 's/.*: //; s/(rev.*)//' | xargs || echo "Intel Arc Series")
                gpu_type="intel"
            fi
        fi
    fi

    GPU_VRAM_GB=$(( (vram_mb + 512) / 1024 ))
    HAS_DEDICATED_GPU="$has_gpu"
    GPU_VRAM_MB="$vram_mb"
    GPU_MODEL="$gpu_model"
    GPU_TYPE="$gpu_type"

    SYSTEM_TOTAL_CPUS="$TOTAL_CPUS"
    SYSTEM_TOTAL_RAM_MB="$TOTAL_RAM_MB"
    SYSTEM_TOTAL_RAM_GB="$TOTAL_RAM_GB"
    SYSTEM_TOTAL_DISK_GB="$TOTAL_DISK_GB"

    export TOTAL_CPUS TOTAL_RAM_MB TOTAL_RAM_GB TOTAL_DISK_GB IS_MODEST_SERVER
    export SYSTEM_TOTAL_CPUS SYSTEM_TOTAL_RAM_MB SYSTEM_TOTAL_RAM_GB SYSTEM_TOTAL_DISK_GB
    export HAS_DEDICATED_GPU GPU_VRAM_MB GPU_VRAM_GB GPU_MODEL GPU_TYPE
}

get_host_hardware

# Se a ação for apenas extrair métricas de hardware para o caller, finaliza aqui
if [ "${2:-}" = "get_hardware_info" ] || [ "${2:-}" = "get_hardware" ]; then
    return 0 2>/dev/null || exit 0
fi

ENV_FILE="${1:-/opt/daemind/.env}"

if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️ [AUTOTUNE] Arquivo .env não encontrado em ${ENV_FILE}. Abortando tuning de arquivo."
    exit 0
fi

# Higieniza CRLF
sed -i 's/\r$//' "$ENV_FILE" 2>/dev/null || true

# Carrega variáveis existentes
set +e
source "$ENV_FILE" 2>/dev/null
set -e

# Validação de Idempotência: se as métricas de hardware e sizing já estão consolidadas no .env e conferem com o hardware real (e não há override forçado)
if [ -z "${OVERRIDE_TOTAL_CPUS:-}" ] && [ -z "${OVERRIDE_TOTAL_RAM_GB:-}" ] && [ -z "${OVERRIDE_TOTAL_RAM_MB:-}" ]; then
    if [ -n "${CPU_DB:-}" ] && [ "${SYSTEM_TOTAL_CPUS:-}" = "$TOTAL_CPUS" ] && [ "${SYSTEM_TOTAL_RAM_MB:-}" = "$TOTAL_RAM_MB" ]; then
        echo "➜ [IDEMPOTÊNCIA AUTOTUNE] Limites e dimensionamento de hardware já consolidados no .env (${TOTAL_CPUS} vCPUs, ${TOTAL_RAM_MB}MB RAM)."
        exit 0 2>/dev/null || return 0 2>/dev/null || true
    fi
fi

echo "➜ [SRE AUTOTUNE] Analisando recursos de hardware (vCPU/RAM/Disco) para dimensionamento de limites..."

# --------------------------------------------------------------------------
# MATRIZ DE CPU (Núcleo Core Imutável)
# --------------------------------------------------------------------------
if [ "$TOTAL_CPUS" -le 4 ]; then
    CPU_LITELLM="1.0"
    CPU_DB="1.0"
    CPU_WAF="0.5"
    CPU_REDIS="0.5"
    CPU_POOLER="0.2"
elif [ "$TOTAL_CPUS" -le 8 ]; then
    CPU_LITELLM="2.0"
    CPU_DB="2.0"
    CPU_WAF="1.0"
    CPU_REDIS="0.5"
    CPU_POOLER="0.5"
else
    CPU_LITELLM="4.0"
    CPU_DB="4.0"
    CPU_WAF="2.0"
    CPU_REDIS="1.0"
    CPU_POOLER="1.0"
fi

# --------------------------------------------------------------------------
# MATRIZ DE RAM & RESERVATIONS (Núcleo Core Imutável)
# --------------------------------------------------------------------------
if [ "$TOTAL_RAM_MB" -le 12288 ]; then
    MEM_LITELLM="2048M"
    MEM_DB="1024M"
    MEM_WAF="256M"
    MEM_REDIS="256M"
    MEM_POOLER="256M"

    RES_DB="512M"
    RES_LITELLM="256M"
    RES_POOLER="64M"
    RES_REDIS="64M"
    RES_WAF="64M"

    POSTGRES_SHARED_BUFFERS="256MB"
    POSTGRES_WORK_MEM="8MB"
    POSTGRES_MAINTENANCE_WORK_MEM="64MB"
    POSTGRES_MAX_PARALLEL_WORKERS="2"
    REDIS_MAXMEMORY="200mb"
    LITELLM_NUM_WORKERS="1"

elif [ "$TOTAL_RAM_MB" -le 24576 ]; then
    echo "  ↳ Perfil RAM Core: [PRO / BUSINESS] (13 GB a 24 GB RAM)"
    MEM_LITELLM="4096M"
    MEM_DB="2048M"
    MEM_WAF="512M"
    MEM_REDIS="512M"
    MEM_POOLER="512M"

    RES_DB="1024M"
    RES_LITELLM="512M"
    RES_POOLER="128M"
    RES_REDIS="128M"
    RES_WAF="128M"

    POSTGRES_SHARED_BUFFERS="1024MB"
    POSTGRES_WORK_MEM="32MB"
    POSTGRES_MAINTENANCE_WORK_MEM="256MB"
    POSTGRES_MAX_PARALLEL_WORKERS="4"
    REDIS_MAXMEMORY="450mb"
    LITELLM_NUM_WORKERS="4"

else
    echo "  ↳ Perfil RAM Core: [ENTERPRISE MONSTER] (> 24 GB RAM)"
    MEM_LITELLM="8192M"
    MEM_DB="4096M"
    MEM_WAF="1024M"
    MEM_REDIS="1024M"
    MEM_POOLER="1024M"

    RES_DB="2048M"
    RES_LITELLM="2048M"
    RES_POOLER="256M"
    RES_REDIS="256M"
    RES_WAF="256M"

    POSTGRES_SHARED_BUFFERS="3072MB"
    POSTGRES_WORK_MEM="64MB"
    POSTGRES_MAINTENANCE_WORK_MEM="512MB"
    POSTGRES_MAX_PARALLEL_WORKERS="8"
    REDIS_MAXMEMORY="900mb"
    LITELLM_NUM_WORKERS="8"
fi

# Função auxiliar para gravar ou atualizar chave em .env de forma limpa e segura
update_env_var() {
    local key="$1"
    local val="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$ENV_FILE"
    else
        echo "${key}=\"${val}\"" >> "$ENV_FILE"
    fi
}

# Atualização Atômica das Variáveis Otimizadas do Core
update_env_var "SYSTEM_TOTAL_CPUS" "$TOTAL_CPUS"
update_env_var "SYSTEM_TOTAL_RAM_MB" "$TOTAL_RAM_MB"
update_env_var "SYSTEM_TOTAL_DISK_GB" "$TOTAL_DISK_GB"

update_env_var "CPU_LITELLM" "$CPU_LITELLM"
update_env_var "CPU_DB" "$CPU_DB"
update_env_var "CPU_WAF" "$CPU_WAF"
update_env_var "CPU_REDIS" "$CPU_REDIS"
update_env_var "CPU_POOLER" "$CPU_POOLER"

update_env_var "MEM_LITELLM" "$MEM_LITELLM"
update_env_var "MEM_DB" "$MEM_DB"
update_env_var "MEM_WAF" "$MEM_WAF"
update_env_var "MEM_REDIS" "$MEM_REDIS"
update_env_var "MEM_POOLER" "$MEM_POOLER"

update_env_var "RES_DB" "$RES_DB"
update_env_var "RES_LITELLM" "$RES_LITELLM"
update_env_var "RES_POOLER" "$RES_POOLER"
update_env_var "RES_REDIS" "$RES_REDIS"
update_env_var "RES_WAF" "$RES_WAF"

update_env_var "POSTGRES_SHARED_BUFFERS" "$POSTGRES_SHARED_BUFFERS"
update_env_var "POSTGRES_WORK_MEM" "$POSTGRES_WORK_MEM"
update_env_var "POSTGRES_MAINTENANCE_WORK_MEM" "$POSTGRES_MAINTENANCE_WORK_MEM"
update_env_var "POSTGRES_MAX_PARALLEL_WORKERS" "$POSTGRES_MAX_PARALLEL_WORKERS"
update_env_var "REDIS_MAXMEMORY" "$REDIS_MAXMEMORY"
update_env_var "LITELLM_NUM_WORKERS" "$LITELLM_NUM_WORKERS"

# Auto-registro do CronJob SRE para rodar no boot/restart da máquina (@reboot)
CRON_FILE="/etc/cron.d/daemind-autotune"
if [ -w "/etc/cron.d" ] || [ "$(id -u)" -eq 0 ]; then
    echo "@reboot root /opt/daemind/core/scripts/autotune.sh /opt/daemind/.env >/dev/null 2>&1" | tee "$CRON_FILE" >/dev/null 2>&1 || true
    chmod 644 "$CRON_FILE" 2>/dev/null || true
fi

echo "✔ [SUCESSO AUTOTUNE] Limites de hardware otimizados e consolidados com sucesso."
