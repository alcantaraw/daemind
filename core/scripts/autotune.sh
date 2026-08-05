#!/usr/bin/env bash
# ===============================================================================
#  DAEMIND SRE CORE - AUTOTUNE MOTOR (MATRIZ DINÂMICA DE RECURSOS)
#  Especificação: Extrai métricas cruas (CPU, RAM, DISCO) do .env ou do Host
#  e gera os limites e tunings otimizados para a malha de microsserviços.
# ===============================================================================

set -euo pipefail

ENV_FILE="${1:-/opt/daemind/core/config/.env}"

if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️ [AUTOTUNE] Arquivo .env não encontrado em ${ENV_FILE}. Abortando tuning."
    exit 0
fi

# Higieniza CRLF
sed -i 's/\r$//' "$ENV_FILE" 2>/dev/null || true

# Carrega variáveis existentes
set +e
source "$ENV_FILE" 2>/dev/null
set -e

# SRE ENGINE: Mede métricas brutas de hardware diretamente do Host a cada execução
TOTAL_CPUS=$(nproc 2>/dev/null || echo 4)
TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)
TOTAL_DISK_GB=$(df -BG /opt 2>/dev/null | awk 'NR==2 {print $2}' | sed 's/G//' 2>/dev/null || echo 50)

TOTAL_RAM_GB=$(( (TOTAL_RAM_MB + 512) / 1024 ))

echo "=== [SRE AUTOTUNE ENGINE] Profiling de Hardware ==="
echo "  ↳ Hardware do Host: ${TOTAL_CPUS} Cores vCPU | ${TOTAL_RAM_GB} GB RAM (${TOTAL_RAM_MB} MB) | ${TOTAL_DISK_GB} GB Disco"

# --------------------------------------------------------------------------
# MATRIZ DE CPU (Calculada via nproc)
# --------------------------------------------------------------------------
if [ "$TOTAL_CPUS" -le 4 ]; then
    echo "  ↳ Perfil CPU: [STANDARD] (<= 4 Cores)"
    CPU_POSTIZ="2.0"
    CPU_CHATWOOT="1.0"
    CPU_LITELLM="1.0"
    CPU_OPENWEBUI="1.0"
    CPU_N8N="1.0"
    CPU_EVOLUTION="1.0"
    CPU_MINIO="1.0"
    CPU_DB="1.0"
    CPU_NOCODB="0.5"
    CPU_TEMPORAL="0.5"
    CPU_WAF="0.5"
    CPU_REDIS="0.5"
    CPU_POOLER="0.2"
elif [ "$TOTAL_CPUS" -le 8 ]; then
    echo "  ↳ Perfil CPU: [PRO / HIGH-PERFORMANCE] (5 a 8 Cores)"
    CPU_POSTIZ="3.0"
    CPU_CHATWOOT="2.0"
    CPU_LITELLM="2.0"
    CPU_OPENWEBUI="2.0"
    CPU_N8N="2.0"
    CPU_EVOLUTION="2.0"
    CPU_MINIO="1.5"
    CPU_DB="2.0"
    CPU_NOCODB="1.0"
    CPU_TEMPORAL="1.0"
    CPU_WAF="1.0"
    CPU_REDIS="0.5"
    CPU_POOLER="0.5"
else
    echo "  ↳ Perfil CPU: [ENTERPRISE MONSTER] (> 8 Cores)"
    CPU_POSTIZ="4.0"
    CPU_CHATWOOT="4.0"
    CPU_LITELLM="4.0"
    CPU_OPENWEBUI="4.0"
    CPU_N8N="4.0"
    CPU_EVOLUTION="3.0"
    CPU_MINIO="2.0"
    CPU_DB="4.0"
    CPU_NOCODB="2.0"
    CPU_TEMPORAL="2.0"
    CPU_WAF="2.0"
    CPU_REDIS="1.0"
    CPU_POOLER="1.0"
fi

# --------------------------------------------------------------------------
# MATRIZ DE RAM & RESERVATIONS (Calculada via free -m)
# --------------------------------------------------------------------------
if [ "$TOTAL_RAM_MB" -le 12288 ]; then
    echo "  ↳ Perfil RAM: [STANDARD] (Até 12 GB RAM)"
    MEM_POSTIZ="4096M"
    MEM_LITELLM="2048M"
    MEM_CHATWOOT="2048M"
    MEM_OPENWEBUI="1024M"
    MEM_N8N="1024M"
    MEM_EVOLUTION="1024M"
    MEM_DB="1024M"
    MEM_NOCODB="1024M"
    MEM_MINIO="1024M"
    MEM_TEMPORAL="768M"
    MEM_WAF="256M"
    MEM_REDIS="256M"
    MEM_POOLER="256M"

    RES_DB="512M"
    RES_CHATWOOT="512M"
    RES_OPENWEBUI="512M"
    RES_LITELLM="256M"
    RES_POSTIZ="1024M"
    RES_TEMPORAL="128M"
    RES_POOLER="64M"
    RES_N8N="0M"
    RES_EVOLUTION="0M"
    RES_NOCODB="0M"
    RES_MINIO="0M"
    RES_REDIS="64M"
    RES_WAF="64M"

    NODE_HEAP_DEFAULT="768"
    NODE_HEAP_POSTIZ="2048"
    POSTGRES_SHARED_BUFFERS="256MB"
    POSTGRES_WORK_MEM="8MB"
    POSTGRES_MAINTENANCE_WORK_MEM="64MB"
    POSTGRES_MAX_PARALLEL_WORKERS="2"
    REDIS_MAXMEMORY="200mb"
    LITELLM_NUM_WORKERS="1"
    CHATWOOT_WEB_CONCURRENCY="2"
    CHATWOOT_SIDEKIQ_CONCURRENCY="10"
    MINIO_API_REQUESTS_MAX="1500"

elif [ "$TOTAL_RAM_MB" -le 24576 ]; then
    echo "  ↳ Perfil RAM: [PRO / BUSINESS] (13 GB a 24 GB RAM)"
    MEM_POSTIZ="6144M"
    MEM_LITELLM="4096M"
    MEM_CHATWOOT="4096M"
    MEM_OPENWEBUI="2048M"
    MEM_N8N="2048M"
    MEM_EVOLUTION="2048M"
    MEM_DB="2048M"
    MEM_NOCODB="2048M"
    MEM_MINIO="2048M"
    MEM_TEMPORAL="1024M"
    MEM_WAF="512M"
    MEM_REDIS="512M"
    MEM_POOLER="512M"

    RES_DB="1024M"
    RES_CHATWOOT="1024M"
    RES_OPENWEBUI="1024M"
    RES_LITELLM="512M"
    RES_POSTIZ="2048M"
    RES_N8N="512M"
    RES_EVOLUTION="512M"
    RES_NOCODB="512M"
    RES_MINIO="512M"
    RES_TEMPORAL="256M"
    RES_POOLER="128M"
    RES_REDIS="128M"
    RES_WAF="128M"

    NODE_HEAP_DEFAULT="1536"
    NODE_HEAP_POSTIZ="4096"
    POSTGRES_SHARED_BUFFERS="1024MB"
    POSTGRES_WORK_MEM="32MB"
    POSTGRES_MAINTENANCE_WORK_MEM="256MB"
    POSTGRES_MAX_PARALLEL_WORKERS="4"
    REDIS_MAXMEMORY="450mb"
    LITELLM_NUM_WORKERS="4"
    CHATWOOT_WEB_CONCURRENCY="4"
    CHATWOOT_SIDEKIQ_CONCURRENCY="20"
    MINIO_API_REQUESTS_MAX="3000"

else
    echo "  ↳ Perfil RAM: [ENTERPRISE MONSTER] (> 24 GB RAM)"
    MEM_POSTIZ="8192M"
    MEM_LITELLM="8192M"
    MEM_CHATWOOT="8192M"
    MEM_OPENWEBUI="4096M"
    MEM_N8N="4096M"
    MEM_EVOLUTION="4096M"
    MEM_DB="4096M"
    MEM_NOCODB="4096M"
    MEM_MINIO="4096M"
    MEM_TEMPORAL="2048M"
    MEM_WAF="1024M"
    MEM_REDIS="1024M"
    MEM_POOLER="1024M"

    RES_DB="2048M"
    RES_CHATWOOT="2048M"
    RES_OPENWEBUI="2048M"
    RES_LITELLM="2048M"
    RES_POSTIZ="4096M"
    RES_N8N="1024M"
    RES_EVOLUTION="1024M"
    RES_NOCODB="1024M"
    RES_MINIO="1024M"
    RES_TEMPORAL="512M"
    RES_POOLER="256M"
    RES_REDIS="256M"
    RES_WAF="256M"

    NODE_HEAP_DEFAULT="3072"
    NODE_HEAP_POSTIZ="6144"
    POSTGRES_SHARED_BUFFERS="3072MB"
    POSTGRES_WORK_MEM="64MB"
    POSTGRES_MAINTENANCE_WORK_MEM="512MB"
    POSTGRES_MAX_PARALLEL_WORKERS="8"
    REDIS_MAXMEMORY="900mb"
    LITELLM_NUM_WORKERS="8"
    CHATWOOT_WEB_CONCURRENCY="8"
    CHATWOOT_SIDEKIQ_CONCURRENCY="30"
    MINIO_API_REQUESTS_MAX="6000"
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

# Atualização Atômica das Variáveis Otimizadas
update_env_var "SYSTEM_TOTAL_CPUS" "$TOTAL_CPUS"
update_env_var "SYSTEM_TOTAL_RAM_MB" "$TOTAL_RAM_MB"
update_env_var "SYSTEM_TOTAL_DISK_GB" "$TOTAL_DISK_GB"

update_env_var "CPU_POSTIZ" "$CPU_POSTIZ"
update_env_var "CPU_CHATWOOT" "$CPU_CHATWOOT"
update_env_var "CPU_LITELLM" "$CPU_LITELLM"
update_env_var "CPU_OPENWEBUI" "$CPU_OPENWEBUI"
update_env_var "CPU_N8N" "$CPU_N8N"
update_env_var "CPU_EVOLUTION" "$CPU_EVOLUTION"
update_env_var "CPU_MINIO" "$CPU_MINIO"
update_env_var "CPU_DB" "$CPU_DB"
update_env_var "CPU_NOCODB" "$CPU_NOCODB"
update_env_var "CPU_TEMPORAL" "$CPU_TEMPORAL"
update_env_var "CPU_WAF" "$CPU_WAF"
update_env_var "CPU_REDIS" "$CPU_REDIS"
update_env_var "CPU_POOLER" "$CPU_POOLER"

update_env_var "MEM_POSTIZ" "$MEM_POSTIZ"
update_env_var "MEM_LITELLM" "$MEM_LITELLM"
update_env_var "MEM_CHATWOOT" "$MEM_CHATWOOT"
update_env_var "MEM_OPENWEBUI" "$MEM_OPENWEBUI"
update_env_var "MEM_N8N" "$MEM_N8N"
update_env_var "MEM_EVOLUTION" "$MEM_EVOLUTION"
update_env_var "MEM_DB" "$MEM_DB"
update_env_var "MEM_NOCODB" "$MEM_NOCODB"
update_env_var "MEM_MINIO" "$MEM_MINIO"
update_env_var "MEM_TEMPORAL" "$MEM_TEMPORAL"
update_env_var "MEM_WAF" "$MEM_WAF"
update_env_var "MEM_REDIS" "$MEM_REDIS"
update_env_var "MEM_POOLER" "$MEM_POOLER"

update_env_var "RES_DB" "$RES_DB"
update_env_var "RES_CHATWOOT" "$RES_CHATWOOT"
update_env_var "RES_OPENWEBUI" "$RES_OPENWEBUI"
update_env_var "RES_LITELLM" "$RES_LITELLM"
update_env_var "RES_POSTIZ" "$RES_POSTIZ"
update_env_var "RES_N8N" "$RES_N8N"
update_env_var "RES_EVOLUTION" "$RES_EVOLUTION"
update_env_var "RES_NOCODB" "$RES_NOCODB"
update_env_var "RES_MINIO" "$RES_MINIO"
update_env_var "RES_TEMPORAL" "$RES_TEMPORAL"
update_env_var "RES_POOLER" "$RES_POOLER"
update_env_var "RES_REDIS" "$RES_REDIS"
update_env_var "RES_WAF" "$RES_WAF"

update_env_var "NODE_HEAP_DEFAULT" "$NODE_HEAP_DEFAULT"
update_env_var "NODE_HEAP_POSTIZ" "$NODE_HEAP_POSTIZ"
update_env_var "POSTGRES_SHARED_BUFFERS" "$POSTGRES_SHARED_BUFFERS"
update_env_var "POSTGRES_WORK_MEM" "$POSTGRES_WORK_MEM"
update_env_var "POSTGRES_MAINTENANCE_WORK_MEM" "$POSTGRES_MAINTENANCE_WORK_MEM"
update_env_var "POSTGRES_MAX_PARALLEL_WORKERS" "$POSTGRES_MAX_PARALLEL_WORKERS"
update_env_var "REDIS_MAXMEMORY" "$REDIS_MAXMEMORY"
update_env_var "LITELLM_NUM_WORKERS" "$LITELLM_NUM_WORKERS"
update_env_var "CHATWOOT_WEB_CONCURRENCY" "$CHATWOOT_WEB_CONCURRENCY"
update_env_var "CHATWOOT_SIDEKIQ_CONCURRENCY" "$CHATWOOT_SIDEKIQ_CONCURRENCY"
update_env_var "MINIO_API_REQUESTS_MAX" "$MINIO_API_REQUESTS_MAX"

# Auto-registro do CronJob SRE para rodar no boot/restart da máquina (@reboot)
CRON_FILE="/etc/cron.d/daemind-autotune"
if [ -w "/etc/cron.d" ] || [ "$(id -u)" -eq 0 ]; then
    echo "@reboot root /opt/daemind/core/scripts/autotune.sh /opt/daemind/core/config/.env >/dev/null 2>&1" | tee "$CRON_FILE" >/dev/null 2>&1 || true
    chmod 644 "$CRON_FILE" 2>/dev/null || true
fi

echo "➜ [AUTOTUNE SUCESSO] Matriz de hardware calculada e consolidada em ${ENV_FILE}"
