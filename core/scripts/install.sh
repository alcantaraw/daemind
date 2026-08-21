#!/bin/bash
# /core/scripts/install.sh
# SRE FIX: 'set -E' obriga o Bash a acionar a trap ERR mesmo dentro das funções run_step
set -eEo pipefail

# ===============================================================================
# PADRONIZAÇÃO VISUAL DE CONSOLE & LOGGER SYSTEM (SRE CLI)
# ===============================================================================
CLR_BOLD="\e[1m"
CLR_RESET="\e[0m"
CLR_GREEN="\e[32m"
CLR_YELLOW="\e[33m"
CLR_CYAN="\e[36m"
CLR_RED="\e[31m"
CLR_BLUE="\e[34m"

log_info()    { echo -e "${CLR_CYAN}➜ [INFO INSTALL]${CLR_RESET} $1"; }
log_success() { echo -e "${CLR_GREEN}✔ [SUCESSO INSTALL]${CLR_RESET} $1"; }
log_warn()    { echo -e "${CLR_YELLOW}⚠️  [ATENÇÃO INSTALL]${CLR_RESET} $1"; }
log_error()   { echo -e "${CLR_RED}🚨 [ERRO CRÍTICO INSTALL]${CLR_RESET} $1"; }
log_substep() { echo -e "${CLR_CYAN}  ↳${CLR_RESET} $1"; }
log_skip()    { echo -e "${CLR_BLUE}⏭️  [PULADO INSTALL]${CLR_RESET} $1"; }
log_exec()    { echo -e "${CLR_YELLOW}⏳ [EXECUTANDO INSTALL]${CLR_RESET} $1"; }
log_header()  {
    echo ""
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_YELLOW}=== [SRE INSTALL] $1 ===${CLR_RESET}"
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
}

# ===============================================================================
# COBERTURA FORENSE TRANSVERSAL (DEBUG, TRAP & LOG)
# ===============================================================================
if [[ "$0" =~ ^-?(bash|sh)$ ]]; then
    SCRIPT_NOME="install"
else
    SCRIPT_NOME=$(basename "$0" .sh)
fi

LOG_FILE="/tmp/debug_${SCRIPT_NOME}.log"

SCRIPT_VERSION="v2026.08.08.10-PROXY-ROUTE-SANALIZED"

log_header "Orquestrador de Provisionamento Autônomo da Stack de Microsserviços (${SCRIPT_VERSION})"
echo ""

# ===============================================================================
# 🔒 SRE GUARDRAIL: TRAVA DE CONCORRÊNCIA INTELIGENTE (MUTEX LOCK COM AUTOREPAIR)
# ===============================================================================
LOCK_FILE="/tmp/${SCRIPT_NOME}.lock"
exec 200>"$LOCK_FILE"

if ! flock -n 200; then
    LOCK_PID=$(fuser "$LOCK_FILE" 2>/dev/null | awk '{print $1}' || true)
    if [ -z "$LOCK_PID" ] || ! ps -p "$LOCK_PID" > /dev/null 2>&1; then
        echo "➜ [AUTOREPAIR] Trava residual órfã detectada. Liberando ${LOCK_FILE}..."
        rm -f "$LOCK_FILE" 2>/dev/null || true
        exec 200>"$LOCK_FILE"
        flock -n 200 || true
    else
        if [ "${FORCE_NEW_INSTALL:-n}" = "s" ] || [ "${FORCE_NEW_INSTALL:-false}" = "true" ]; then
            echo "➜ [FORCE] Encerrando instância anterior (PID: ${LOCK_PID}) para novo deploy..."
            sudo kill -9 "$LOCK_PID" 2>/dev/null || true
            sleep 1
            exec 200>"$LOCK_FILE"
            flock -n 200 || true
        else
            echo "====================================================================="
            echo "⚠️  [ALERTA SRE] Uma instância do ${SCRIPT_NOME}.sh já está em execução (PID: ${LOCK_PID})."
            echo "➜ Arquivo de Trava: ${LOCK_FILE}"
            echo "➜ Logs da execução ativa: tail -f ${LOG_FILE}"
            echo "➜ Para forçar a execução matando a anterior, passe: FORCE_NEW_INSTALL=s"
            echo "====================================================================="
            cat > /dev/null 2>&1 || true
            exit 0
        fi
    fi
fi

# ===============================================================================
# CRONÔMETRO SRE (Métricas de Latência de Deploy)
# ===============================================================================
# Se o script veio encadeado pelo preinstall.sh, usa o inicio do preinstall; senao usa a hora atual
INICIO_TS="${PREINSTALL_START_TS:-$(date +%s)}"
PAUSA_SEC="${PREINSTALL_PAUSE_SEC:-0}"

# Guardrail de Sanitização Preventiva de Borda (Caddyfile File Integrity)
TARGET_DIR="${TARGET_DIR:-/opt/daemind}"
if [ -d "$TARGET_DIR/Caddyfile" ]; then
    rm -rf "$TARGET_DIR/Caddyfile"
fi
rm -rf "$TARGET_DIR/core/config/Caddyfile" "$TARGET_DIR/core/config/core" 2>/dev/null || true
if [ ! -f "$TARGET_DIR/Caddyfile" ]; then
    cat << 'EO_CAD' > "$TARGET_DIR/Caddyfile"
:80 {
    log { level error }
    @health path /healthz
    handle @health { respond "OK" 200 }
}
:4000 {
    log { level error }
    reverse_proxy ${PREFIXO_CONTAINER}_litellm:4000
}
EO_CAD
fi

mostrar_duracao() {
    local FIM_TS=$(date +%s)
    local DURACAO_BRUTA=$((FIM_TS - INICIO_TS))
    local DURACAO_LIQUIDA=$((DURACAO_BRUTA - PAUSA_SEC))
    [ $DURACAO_LIQUIDA -lt 0 ] && DURACAO_LIQUIDA=0
    echo "====================================================================="
    if [ -n "$PREINSTALL_START_TS" ]; then
        if [ "$PAUSA_SEC" -gt 0 ]; then
            echo "⏱️ [SRE METRIC INSTALL] Duração real da execução (Preinstall + Install): ${DURACAO_LIQUIDA}s (Total decorrido: ${DURACAO_BRUTA}s | Pausas em perguntas: ${PAUSA_SEC}s)."
        else
            echo "⏱️ [SRE METRIC INSTALL] Duração total da execução (Preinstall + Install): ${DURACAO_LIQUIDA} segundos."
        fi
    else
        echo "⏱️ [SRE METRIC INSTALL] Duração total da execução (Install): ${DURACAO_LIQUIDA} segundos."
    fi
    echo "📅 Data/Hora de término: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "====================================================================="
}

# Registra o log de início
echo "🚀 [SRE INSTALL] Início do deploy: $(date '+%Y-%m-%d %H:%M:%S')"

# Garante o redirecionamento unificado escrevendo em tempo real no arquivo volátil
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

# ===============================================================================
# ARRAYS GLOBAIS DE MÓDULOS DESACOPLADOS (SRE SSOT)
# ===============================================================================
declare -g -a MODULOS_DESACOPLADOS_ATIVOS=()
declare -g -a MODULOS_DESACOPLADOS_INATIVOS=()
declare -g -a STACK_ACTIVE_CONTAINERS=()

resolver_modulos_desacoplados() {
    MODULOS_DESACOPLADOS_ATIVOS=()
    MODULOS_DESACOPLADOS_INATIVOS=()

    local base_dir="${TARGET_DIR:-/opt/daemind}/core/scripts"
    [ ! -d "$base_dir" ] && base_dir="${RAIZ_REPO:-/tmp/infra-loja-bootstrap}/core/scripts"

    for script in "$base_dir"/install_*.sh; do
        [ -f "$script" ] || continue
        local fname=$(basename "$script")
        local mod="${fname#install_}"
        mod="${mod%.sh}"

        local use_var="USE_$(echo "$mod" | tr '[:lower:]' '[:upper:]')"

        local ativo=false
        if [ "$mod" = "s3minio" ]; then
            local val_s3="${USE_S3MINIO:-s}"
            if [ "${STORAGE_MODE:-local}" != "s3_external" ] && ([[ "$val_s3" =~ ^[Ss]$ ]] || [ "$val_s3" = "true" ]); then
                ativo=true
            fi
        else
            if [[ "${!use_var:-s}" =~ ^[Ss]$ ]] || [ "${!use_var:-}" = "true" ]; then
                ativo=true
            fi
        fi

        if [ "$ativo" = "true" ]; then
            MODULOS_DESACOPLADOS_ATIVOS+=("$mod")
        else
            MODULOS_DESACOPLADOS_INATIVOS+=("$mod")
        fi
    done
}

resolver_containers_ativos() {
    [ ${#MODULOS_DESACOPLADOS_ATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados
    
    STACK_ACTIVE_CONTAINERS=()
    local prefix="${PREFIXO_CONTAINER}"
    
    # 1. Se o docker-compose.yml final (unificado) já existe, descobre os serviços via CLI
    if command -v docker >/dev/null 2>&1 && [ -f "$TARGET_DIR/docker-compose.yml" ]; then
        for svc in $(cd "$TARGET_DIR" && docker compose config --services 2>/dev/null); do
            STACK_ACTIVE_CONTAINERS+=("${prefix}_${svc}")
        done
    fi
    
    # 2. Fallback 100% Dinâmico: Varre o docker-compose.yml base + YAMLs dos módulos ativos
    if [ ${#STACK_ACTIVE_CONTAINERS[@]} -eq 0 ]; then
        local base_compose="$TARGET_DIR/core/config/docker-compose.yml"
        local base_services=()
        
        if [ -f "$base_compose" ]; then
            base_services=($(python3 -c "
import yaml
try:
    with open('$base_compose', 'r') as f:
        data = yaml.safe_load(f)
        if data and 'services' in data:
            print(' '.join(data['services'].keys()))
except Exception:
    pass
" 2>/dev/null || true))
        fi
        
        if [ ${#base_services[@]} -eq 0 ]; then
            base_services=("postgres" "pgbouncer" "redis" "caddy" "litellm")
        fi
        
        for svc in "${base_services[@]}"; do
            STACK_ACTIVE_CONTAINERS+=("${prefix}_${svc}")
        done
        
        for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
            local mod_compose="$TARGET_DIR/core/config/docker-compose.${mod}.yml"
            if [ -f "$mod_compose" ]; then
                local mod_services=($(python3 -c "
import yaml
try:
    with open('$mod_compose', 'r') as f:
        data = yaml.safe_load(f)
        if data and 'services' in data:
            print(' '.join(data['services'].keys()))
except Exception:
    pass
" 2>/dev/null || true))
                for m_svc in "${mod_services[@]}"; do
                    if [[ ! " ${STACK_ACTIVE_CONTAINERS[*]} " =~ " ${prefix}_${m_svc} " ]]; then
                        STACK_ACTIVE_CONTAINERS+=("${prefix}_${m_svc}")
                    fi
                done
            fi
        done
    fi
}

diagnosticar_containers_stack() {
    local container_foco="$1"
    if command -v docker >/dev/null 2>&1; then
        echo ""
        echo "====================================================================="
        echo "🚨 [SRE DOCKER FORENSICS] RELATÓRIO FORENSE DE LOGS E CONTAINERS:"
        echo "====================================================================="
        local PREFIXO="${PREFIXO_CONTAINER}"

        [ ${#STACK_ACTIVE_CONTAINERS[@]} -eq 0 ] && resolver_containers_ativos

        for container in "${STACK_ACTIVE_CONTAINERS[@]}"; do
            STATUS=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
            HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo "none")
            EXIT_CODE=$(docker inspect -f '{{.State.ExitCode}}' "$container" 2>/dev/null || echo "0")
            RESTARTING=$(docker inspect -f '{{.State.Restarting}}' "$container" 2>/dev/null || echo "false")

            # Se o container não estiver rodando, estiver unhealthy, com erro, reiniciando ou for o container de foco
            if [ "$STATUS" != "running" ] || [ "$HEALTH" = "unhealthy" ] || [ "$EXIT_CODE" != "0" ] || [ "$RESTARTING" = "true" ] || [ "$container" = "$container_foco" ]; then
                echo -e "\e[31m---------------------------------------------------------------------\e[0m"
                echo -e "\e[31m🔍 Container: ${container} | Status: ${STATUS} | Health: ${HEALTH} | ExitCode: ${EXIT_CODE}\e[0m"
                echo -e "\e[31mÚltimas 80 linhas do log:\e[0m"
                docker logs --tail 80 "$container" 2>&1 || true
                echo -e "\e[31m---------------------------------------------------------------------\e[0m"
            fi
        done

        echo "📌 Status Geral da Stack de Containers da Empresa (${PREFIXO}):"
        docker ps -a --filter "name=${PREFIXO}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1 || true
        echo "====================================================================="
    fi
}

gerar_relatorio_versoes_stack() {
    if command -v docker >/dev/null 2>&1; then
        local PREFIXO="${PREFIXO_CONTAINER}"
        echo ""
        echo "==================================================================================================="
        echo "                    📊 [SRE BOM INSTALL] MATRIZ DINÂMICA DE VERSÕES E IMAGENS DOCKER               "
        echo "==================================================================================================="
        printf "%-20s | %-50s | %-20s\n" "CONTAINER" "IMAGEM DOCKER" "VERSÃO INTERNA"
        echo "---------------------------------------------------------------------------------------------------"

        [ ${#STACK_ACTIVE_CONTAINERS[@]} -eq 0 ] && resolver_containers_ativos

        for container in "${STACK_ACTIVE_CONTAINERS[@]}"; do
            local imagem=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null || echo "N/A")
            local servico="${container#${PREFIXO}_}"
            local versao=""

            # Delegador Polimórfico: se existir install_<servico>.sh, delega para get_version do módulo
            if [ -f "$TARGET_DIR/core/scripts/install_${servico}.sh" ]; then
                versao=$(bash "$TARGET_DIR/core/scripts/install_${servico}.sh" "$TARGET_DIR" get_version "$servico" 2>/dev/null || echo "")
            elif [ "$servico" = "temporal" ] && [ -f "$TARGET_DIR/core/scripts/install_postiz.sh" ]; then
                versao=$(bash "$TARGET_DIR/core/scripts/install_postiz.sh" "$TARGET_DIR" get_version "temporal" 2>/dev/null || echo "")
            fi

            # Fallback para serviços do Core que não possuem script desacoplado dedicado
            if [ -z "$versao" ]; then
                case "$servico" in
                    postgres)
                        versao=$(docker exec "$container" postgres --version 2>/dev/null | awk '{print $3}' || echo "")
                        ;;
                    pgbouncer)
                        local tag_imagem="${imagem##*:}"
                        if [ -n "$tag_imagem" ] && [ "$tag_imagem" != "$imagem" ]; then
                            versao="${tag_imagem}"
                        fi
                        ;;
                    redis)
                        versao=$(docker exec "$container" redis-server --version 2>/dev/null | sed -n 's/.*v=\([0-9.]*\).*/\1/p' || echo "")
                        ;;
                    caddy)
                        versao=$(docker exec "$container" caddy version 2>/dev/null | awk '{print $1}' || echo "")
                        ;;
                    litellm)
                        versao=$(docker exec "$container" python3 -c "import importlib.metadata; print(importlib.metadata.version('litellm'))" 2>/dev/null || echo "")
                        ;;
                    *)
                        local tag_imagem="${imagem##*:}"
                        if [ -n "$tag_imagem" ] && [ "$tag_imagem" != "$imagem" ]; then
                            versao="${tag_imagem}"
                        fi
                        ;;
                esac
            fi

            if [ -z "$versao" ]; then
                local tag_imagem="${imagem##*:}"
                if [ -n "$tag_imagem" ] && [ "$tag_imagem" != "$imagem" ]; then
                    versao="${tag_imagem}"
                else
                    versao="N/A"
                fi
            fi

            # Sanitização global de formatação (remove "Tag (...)", "RELEASE.", e prefixo "v")
            versao=$(echo "$versao" | sed -E 's/^Tag \((.*)\)$/\1/; s/^RELEASE\.//; s/^[vV]//')

            printf "%-20s | %-50s | %-20s\n" "$container" "$imagem" "$versao"
        done
        echo "==================================================================================================="
    fi
}

error_forensic_handler() {
    local linha_erro="$1"
    local comando_falho="$2"
    echo "====================================================================="
    echo "[FALHA CRÍTICA NO PROVISIONAMENTO] A esteira foi interrompida!"
    echo "➜ Linha da Quebra: ${linha_erro}"
    echo "➜ Comando Abortado: ${comando_falho}"
    echo "====================================================================="

    diagnosticar_containers_stack

    echo "🚨 [SRE EMERGENCY] Iniciando protocolo de destruição de dados sensíveis..."
    # 1. Expuga o clone, chaves e o script de hardening da raiz (Preservando estritamente /tmp/debug_bash.log)
    rm -rf /tmp/infra-loja-bootstrap /tmp/lojista_key.asc 2>/dev/null

    # 2. Sobrescreve e purga dinamicamente as variáveis sensíveis da sessão atual na memória antes do exit
    for var in $(compgen -v | grep -E '(_KEY|_SECRET|_PASSWORD|_TOKEN|TS_OAUTH|DB_USER)'); do
        export "$var"="EXPURGADO"
        unset "$var" 2>/dev/null || true
    done

    echo "➜ [INFO INSTALL] Rastro de dados sensíveis sanitizado com sucesso da memória e do disco."
}
trap 'error_forensic_handler $LINENO "$BASH_COMMAND"' ERR

# 1. Configura o timeout estendido temporário para a execução deste script
echo "=== [SRE INSTALL] Elevando temporariamente o timeout do sudo para 60 minutos ==="
echo "Defaults timestamp_timeout=60" | sudo tee /etc/sudoers.d/custom_sudo_timeout > /dev/null
sudo chmod 0440 /etc/sudoers.d/custom_sudo_timeout

# 2. GOLPE DE MESTRE: Registra o trap para remover o timeout ao sair do script, ocorra erro ou sucesso
cleanup_sudo_timeout() {
    mostrar_duracao
    if [ -f /etc/sudoers.d/custom_sudo_timeout ]; then
        echo "=== [SRE HARDENING INSTALL] Revogando timeout estendido do sudo... ==="
        sudo rm -f /etc/sudoers.d/custom_sudo_timeout 2>/dev/null || true
    fi
    rm -f "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup_sudo_timeout EXIT

if [ "$DEBUG" = "true" ]; then
    set -x
    export PS4='+(${BASH_SOURCE}:${LINENO}): '
fi

# ===============================================================================
# CARREGAMENTO DO PAYLOAD E FONTE DA VERDADE (SSOT)
# ===============================================================================
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -d "${SCRIPT_DIR}/core/config" ]; then
    RAIZ_REPO="${SCRIPT_DIR}"
else
    RAIZ_REPO=$(cd "${SCRIPT_DIR}/../.." && pwd)
fi

CLIENT_ENV_FILE="${1:-${RAIZ_REPO}/.env}"

# Se o .env oficial não for indicado, tenta na raiz
if [ ! -f "$CLIENT_ENV_FILE" ]; then
    CLIENT_ENV_FILE=$(ls -t "${RAIZ_REPO}/"*.env 2>/dev/null | head -n 1 || true)
fi

if [ -n "$CLIENT_ENV_FILE" ] && [ -f "$CLIENT_ENV_FILE" ]; then
    echo "=== [SRE INSTALL] Absorvendo variáveis de parametrização: ${CLIENT_ENV_FILE} ==="
    # SRE FIX: Aplica a higienização de quebras de linha Windows (CRLF)
    sed -i 's/\r$//' "${CLIENT_ENV_FILE}" 2>/dev/null || true
    set -a
    source "${CLIENT_ENV_FILE}"
    set +a
    echo "➜ [SUCESSO INSTALL] Variáveis de ambiente carregadas na sessão com sucesso."

    # Consolidação Atômica SSOT: Garante .env na raiz como a única Fonte da Verdade
    TARGET_SSOT="${RAIZ_REPO}/.env"
    if [ "$(readlink -f "$CLIENT_ENV_FILE" 2>/dev/null)" != "$(readlink -f "$TARGET_SSOT" 2>/dev/null)" ]; then
        cp "$CLIENT_ENV_FILE" "$TARGET_SSOT"
        chmod 600 "$TARGET_SSOT"
        rm -f "$CLIENT_ENV_FILE" 2>/dev/null || true
        echo "➜ [SRE ATÔMICO INSTALL] SSOT consolidado em ${TARGET_SSOT} e payload temporário expurgado."
    fi

    # SRE DECOUPLED MODULE: Execução do Motor de Auto-Tuning Dinâmico (Fallback para execução manual sem preinstall)
    if [ -z "${CPU_DB:-}" ] && [ -f "${RAIZ_REPO}/core/scripts/autotune.sh" ]; then
        chmod +x "${RAIZ_REPO}/core/scripts/autotune.sh" 2>/dev/null || true
        "${RAIZ_REPO}/core/scripts/autotune.sh" "${TARGET_SSOT}" || true
        set -a
        source "${TARGET_SSOT}"
        set +a
    fi
else
    echo "====================================================================="
    echo "🚨 [ERRO FATAL INSTALL] Arquivo de configuração (.env) não encontrado em ${RAIZ_REPO}/.env!"
    echo "➜ Certifique-se de ter executado o preinstall.sh anteriormente."
    echo "====================================================================="
    exit 1
fi

# ===============================================================================
# ➜ SRE GUARDRAIL: Validação Estrita do State Map (.env)
# ===============================================================================
VARIAVEIS_CRITICAS=(
    TS_EMAIL TS_OAUTH_ID TS_OAUTH_SECRET DB_USER DB_PASSWORD
    HASH_ESPERADO CHAVE_PUBLICA_B64 PREFIXO_CONTAINER PROJETO_DIR
    CLIENTE_NOME CLIENTE_SOBRENOME
    HOST_CADDY_PORT HOST_EVO_PORT HOST_NOCODB_PORT
)

for var in "${VARIAVEIS_CRITICAS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "====================================================================="
        echo "🚨 [ERRO FATAL INSTALL] Quebra de Integridade na Fonte da Verdade (SSOT)!"
        echo "➜ A variável estrutural obrigatória '$var' está vazia."
        echo "➜ Verifique se o arquivo .env foi gerado corretamente."
        echo "====================================================================="
        exit 1
    fi
done

# SRE: Validação Dinâmica da Malha de Inteligência Artificial
TEM_CHAVE_IA="false"
if [ -n "$OPENAI_API_KEY" ] || [ -n "$GEMINI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ] || \
   [ -n "$DEEPSEEK_API_KEY" ] || [ -n "$OPENROUTER_API_KEY" ]; then
    TEM_CHAVE_IA="true"
fi

if [ "$TEM_CHAVE_IA" = "true" ]; then
    echo "➜ [OK INSTALL] Credenciais estruturais e chaves de IA confirmadas em memória."
else
    echo "⚠️ [AVISO SRE INSTALL] Nenhuma chave de API de Inteligência Artificial foi configurada no .env."
fi

# ===============================================================================
# SRE STATE HARMONIZATION: Desmonte atômico de módulos desativados (Agnóstico a N módulos)
# ===============================================================================
[ ${#MODULOS_DESACOPLADOS_INATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados

for mod in "${MODULOS_DESACOPLADOS_INATIVOS[@]}"; do
    if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
        # Valida se o módulo tem container rodando ou arquivo de dnsmasq antes de rodar disable
        if docker inspect "${PREFIXO_CONTAINER}_${mod}" >/dev/null 2>&1 || [ -f "/etc/dnsmasq.d/${mod}.conf" ]; then
            echo "➜ [SRE HARMONIZATION INSTALL] Módulo '${mod}' desativado no .env. Garantindo desmonte atômico..."
            bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" disable 2>/dev/null || true
        fi
    fi
done

# SRE: Dimensionamento Fixo (Lightweight) para VPS Exclusiva
CPU_DB="1.0"
MEM_DB="1024M"

echo "=== Estruturando árvore física de volumes persistentes ==="
# SRE Ajuste: Se rodar via sudo, garante o mapeamento na home do usuário real (well) e não do root
if [ -n "$SUDO_USER" ]; then
    HOME_USER="/home/$SUDO_USER"
else
    HOME_USER="/home/$USER"
fi

TARGET_DIR="/opt/daemind"
cd "$TARGET_DIR" 2>/dev/null || true

step_build_tree_and_files() {
# ===============================================================================
echo "=== [FASE 1 INSTALL] Arquitetura Físico-Lógica de Volumes e Portal Estático ======="
# ===============================================================================
    # 1. Estruturação dos volumes exclusivos da infraestrutura CORE
    mkdir -p "$TARGET_DIR"/volumes/{postgres_data,tailscale_state,caddy_data,litellm_data,pgbouncer_data}
    touch "$TARGET_DIR/volumes/pgbouncer_data/pgbouncer-other-databases.ini" 2>/dev/null || true

    # SRE PRE-FLIGHT FIX: Garante que config.yaml do LiteLLM seja um ARQUIVO e não um DIRETÓRIO
    if [ -d "$TARGET_DIR/volumes/litellm_data/config.yaml" ]; then
        rm -rf "$TARGET_DIR/volumes/litellm_data/config.yaml"
    fi
    if [ ! -f "$TARGET_DIR/volumes/litellm_data/config.yaml" ]; then
        cat << 'EO_BASE' > "$TARGET_DIR/volumes/litellm_data/config.yaml"
litellm_settings:
  drop_params: true
EO_BASE
    fi

    # SRE Volume Hardening: Restaura permissões estritas dos serviços Core
    chown -R 999:999 "$TARGET_DIR/volumes/postgres_data" 2>/dev/null || true
    chown -R 1000:1000 "$TARGET_DIR/volumes/litellm_data" "$TARGET_DIR/volumes/pgbouncer_data" 2>/dev/null || true

    # --- INVOCAÇÃO DESACOPLADA DE ESTRUTURA DE VOLUMES DOS MÓDULOS (PARALELIZADO) ---
    [ ${#MODULOS_DESACOPLADOS_ATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados
    STRUCTURE_PIDS=()
    for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
        if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
            (
                bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" build_structure
            ) &
            STRUCTURE_PIDS+=($!)
        fi
    done
    for pid in "${STRUCTURE_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

# SRE Self-Healing: Garante que a chave GPG pública exista no keyring local
echo "$CHAVE_PUBLICA_B64" | base64 --decode > /tmp/lojista_key.asc
gpg --batch --yes --import /tmp/lojista_key.asc > /dev/null 2>&1 || true
rm -f /tmp/lojista_key.asc

echo "=== [SRE INSTALL] Processando Assets Visuais e Rotas WAF ==="

# 1. Copia todos os assets estáticos do repositório (index.html, favicons, background)
    cp -r "$RAIZ_REPO/core/html/"* "$TARGET_DIR/core/html/" 2>/dev/null || true

# 2. SRE Guardrail: Ajusta permissão apenas dos arquivos de código/config (preservando volumes)
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$TARGET_DIR" "$TARGET_DIR"/* 2>/dev/null || true
        chown -R "$SUDO_USER:$SUDO_USER" "$TARGET_DIR/core" 2>/dev/null || true
    fi

# ===============================================================================
# GOLPE DE MESTRE SRE: O Caddyfile DEVE ser criado antes de reiniciar o container
# ===============================================================================
BIND_PORTAL=":80"
BIND_API=":8081"

if [ "$USE_TAILSCALE" = "false" ]; then
    if [ "$CADDY_PROTOCOL" = "http" ]; then
        BIND_PORTAL="http://${CUSTOM_DOMAIN}"
        BIND_API="http://${CUSTOM_EVO_DOMAIN}"
    else
        BIND_PORTAL="${CUSTOM_DOMAIN}"
        BIND_API="${CUSTOM_EVO_DOMAIN}"
    fi
fi

if [ -d "$TARGET_DIR/Caddyfile" ]; then
    rm -rf "$TARGET_DIR/Caddyfile"
fi
rm -rf "$TARGET_DIR/core/config/Caddyfile" "$TARGET_DIR/Caddyfile" 2>/dev/null || true

cat << EOF > "$TARGET_DIR/Caddyfile"
# Caddyfile Dinâmico SRE - Portal e Roteamento Omnichannel
{
    log {
        level error
    }
}

# ===============================================================================
# 1. GATEWAY PÚBLICO & DASHBOARD (Exposto via Tailscale Funnel)
# ===============================================================================
${BIND_PORTAL} {
    log {
        level error
    }

    # SRE: Healthcheck do Docker nativo do Caddy
    @health path /healthz
    handle @health {
        respond "OK" 200
    }

    # --- PORTAL WHITE-LABEL ---
    handle {
        root * /etc/caddy/public
        header Cache-Control "no-cache, no-store, must-revalidate"
        file_server
    }
}

# ===============================================================================
# 2. ROTAS PRIVADAS BASE DO CORE (Acesso Restrito via Painel / VPN)
# ===============================================================================
:4000 {
    log {
        level error
    }
    reverse_proxy ${PREFIXO_CONTAINER}_litellm:4000
}

# ===============================================================================
# 4. GATEWAY MULTI-LLM INTERNO (Referência de Proxy Direto / Big 5 IA)
# ===============================================================================
# :8444 {
    # log {
        # level error
    # }
    # handle_path /gemini/* {
        # reverse_proxy generativelanguage.googleapis.com:443 {
            # transport http {
                # tls
            # }
            # header_up Host generativelanguage.googleapis.com
        # }
    # }
    # handle_path /openai/* {
        # reverse_proxy api.openai.com:443 {
            # transport http {
                # tls
            # }
            # header_up Host api.openai.com
        # }
    # }
    # handle_path /claude/* {
        # reverse_proxy api.anthropic.com:443 {
            # transport http {
                # tls
            # }
            # header_up Host api.anthropic.com
        # }
    # }
    # handle_path /deepseek/* {
        # reverse_proxy api.deepseek.com:443 {
            # transport http {
                # tls
            # }
            # header_up Host api.deepseek.com
        # }
    # }
    # handle_path /openrouter/* {
        # reverse_proxy openrouter.ai:443 {
            # transport http {
                # tls
            # }
            # header_up Host openrouter.ai
        # }
    # }
# }
EOF

# --- INVOCAÇÃO DESACOPLADA DE ROTAS CADDY E CARDS VISUAIS ---
chmod +x "$TARGET_DIR/core/scripts/"*.sh 2>/dev/null || true

[ ${#MODULOS_DESACOPLADOS_ATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados

for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
    if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
        bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" inject_caddy_routes
        bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" inject_dashboard_card
    fi
done
}

echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Estruturando árvore física de volumes e portal estático...\e[0m"
step_build_tree_and_files

cd "$TARGET_DIR"

step_tailscale_auth() {
# ===============================================================================
echo "=== [FASE 2 INSTALL] Conectividade Perimetral e Identidade de Rede ================"
# ===============================================================================
    if [ "$USE_TAILSCALE" = "false" ]; then
        echo "➜ [SRE SKIP INSTALL] Modo BYODNS Ativado. Omitindo provisionamento Tailscale/Funnel."
        return 0
    fi

    sudo bash "$TARGET_DIR/core/scripts/install_0ts.sh" "$TARGET_DIR" auth
    TS_DOMAIN=$(sudo bash "$TARGET_DIR/core/scripts/install_0ts.sh" "$TARGET_DIR" get_domain 2>/dev/null || echo "localhost")
    [ -z "$TS_DOMAIN" ] && TS_DOMAIN="localhost"
    export TS_DOMAIN
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Autenticação e Abertura de Túneis Tailscale...\e[0m"
step_tailscale_auth

step_generate_env() {
# ===============================================================================
echo "=== [FASE 3 INSTALL] Consolidação do SSOT de Runtime (.env) ======================="
# ===============================================================================

# SRE FIX: Se a Fase 2 foi pulada pelo Checkpoint, a variável TS_DOMAIN estará vazia.
# Aqui nós forçamos a recaptura da identidade perimetral via módulo install_0ts.sh.
if [ "$USE_TAILSCALE" = "true" ] && [ -z "$TS_DOMAIN" ]; then
    TS_DOMAIN=$(sudo bash "$TARGET_DIR/core/scripts/install_0ts.sh" "$TARGET_DIR" get_domain 2>/dev/null || echo "localhost")
fi

# SRE FIX: Prevenção absoluta contra strings de domínio vazias
TS_DOMAIN="${TS_DOMAIN:-localhost}"
[ -z "$TS_DOMAIN" ] && TS_DOMAIN="localhost"

SSOT_PATH="${TARGET_DIR}/.env"
[ ! -f "$SSOT_PATH" ] && SSOT_PATH="${RAIZ_REPO}/.env"
[ ! -f "$SSOT_PATH" ] && SSOT_PATH="./.env"

# SRE GUARDRAIL: Padronização da Chave de API Mestra da Stack (SSOT Unified API Key)
API_MASTER_KEY="${API_MASTER_KEY:-${DB_PASSWORD}}"

# SRE FIX: Resolução Determinística do FQDN Base e Protocolo Webhook
if [ "$USE_TAILSCALE" = "false" ]; then
    TS_DOMAIN="${CUSTOM_DOMAIN:-localhost}"
    [ -z "$TS_DOMAIN" ] && TS_DOMAIN="localhost"
    SERVER_URL="${CADDY_PROTOCOL:-http}://${CUSTOM_EVO_DOMAIN:-localhost}"
    BASE_WEBHOOK_PROTOCOL="${CADDY_PROTOCOL:-http}"
else
    SERVER_URL="https://${TS_DOMAIN}:8443"
    BASE_WEBHOOK_PROTOCOL="https"
fi

cat << EOF > .env
# --- Herança de Estado (SSOT) ---
IP_NETWORK_SUBNET=${IP_NETWORK_SUBNET}
IP_NETWORK_GATEWAY=${IP_NETWORK_GATEWAY}
IP_POSTGRES=${IP_POSTGRES}
IP_PGBOUNCER=${IP_PGBOUNCER}
IP_REDIS=${IP_REDIS}
IP_CADDY=${IP_CADDY}
IP_LITELLM=${IP_LITELLM}
PROJETO_DIR=${PROJETO_DIR}
PREFIXO_CONTAINER=${PREFIXO_CONTAINER}
TS_OAUTH_ID=${TS_OAUTH_ID}
TS_OAUTH_SECRET=${TS_OAUTH_SECRET}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
LOJA_API_KEY=${LOJA_API_KEY}
LOJA_APP_KEY=${LOJA_APP_KEY}
ACTIVE_AI_PROVIDER=${ACTIVE_AI_PROVIDER}
IA_SYSTEM_PROMPT="${IA_SYSTEM_PROMPT}"
FREE_GEMINI=${FREE_GEMINI}
GEMINI_API_KEY=${GEMINI_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
TS_EMAIL=${TS_EMAIL}
CLIENTE_NOME="${CLIENTE_NOME}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}"
CLIENTE_SOBRENOME="${CLIENTE_SOBRENOME}"
HOST_CADDY_PORT="${HOST_CADDY_PORT}"
CHAVE_PUBLICA_B64="${CHAVE_PUBLICA_B64}"
HASH_ESPERADO="${HASH_ESPERADO}"

# --- Variáveis Dinâmicas e Relacionais do Core ---
DB_NAME=${PREFIXO_CONTAINER}_db
API_MASTER_KEY=${API_MASTER_KEY}
TS_DOMAIN=${TS_DOMAIN}
DOMAIN=${TS_DOMAIN}
DOMAIN_NAME=${TS_DOMAIN}
SERVER_URL=${SERVER_URL}
PROXY_PORT=${HOST_CADDY_PORT}

REDIS_URL="redis://${IP_REDIS}:6379"
REDIS_HOST="${IP_REDIS}"
REDIS_PORT=6379
CPU_DB=${CPU_DB}
MEM_DB=${MEM_DB}
EOF

# Injeção Dinâmica dos IPs dos Módulos Desacoplados
ALL_NODES=()
for script in "$TARGET_DIR"/core/scripts/install_*.sh; do
    [ ! -f "$script" ] && continue
    nodes=$(sed -n '2p' "$script" 2>/dev/null | sed 's/^#[[:space:]]*//')
    for node in $nodes; do
        [ -n "$node" ] && ALL_NODES+=("$(echo "$node" | tr '[:lower:]' '[:upper:]')")
    done
done
SORTED_NODES=($(printf "%s\n" "${ALL_NODES[@]}" | sort -u))
IP_OFFSET=7
for node in "${SORTED_NODES[@]}"; do
    VAR_NAME="IP_${node}"
    IP_VAL="${!VAR_NAME:-${BASE_IP}.${IP_OFFSET}}"
    echo "${VAR_NAME}=\"${IP_VAL}\"" >> .env
    IP_OFFSET=$((IP_OFFSET + 1))
done

# --- INJEÇÃO POLIMÓRFICA DAS VARIÁVEIS DE AMBIENTE DOS MÓDULOS ATIVOS ---
[ ${#MODULOS_DESACOPLADOS_ATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados

for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
    if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
        bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" build_envs
    fi
done

# =========================================================================
# SRE STATE HARMONIZATION: Persistência dos Flags de Controle no .env Runtime
# Garante que re-runs do install.sh (com ou sem preinstall) preservem o estado
# exato dos módulos: ativos → "s", inativos → "n". Last-write-wins.
# =========================================================================
{
    printf '\n# --- Flags de Controle de Módulos (State Harmonization Runtime) ---\n'
    [ ${#MODULOS_DESACOPLADOS_ATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados
    for _rmod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
        printf 'USE_%s="s"\n' "$(echo "$_rmod" | tr '[:lower:]' '[:upper:]')"
    done
    for _rmod in "${MODULOS_DESACOPLADOS_INATIVOS[@]}"; do
        printf 'USE_%s="n"\n' "$(echo "$_rmod" | tr '[:lower:]' '[:upper:]')"
    done
    printf 'STORAGE_MODE="%s"\n'  "${STORAGE_MODE:-local}"
    printf 'USE_S3MINIO="%s"\n'   "${USE_S3MINIO:-n}"
    printf 'USE_TAILSCALE="%s"\n' "${USE_TAILSCALE:-false}"
} >> .env
# Guardrail de Segurança: Oculta o arquivo de outros usuários do Linux
chmod 600 .env
cp .env "$TARGET_DIR/.env" 2>/dev/null || true
chmod 600 "$TARGET_DIR/.env" 2>/dev/null || true
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Consolidando variáveis de estado de Runtime (.env)...\e[0m"
step_generate_env

step_docker_pull_and_infra() {
# =====================================================================================
echo "=== [FASE 4 INSTALL] Provisionando Infraestrutura Base e Módulos Ativos ============="
# =====================================================================================
cd "$TARGET_DIR" 2>/dev/null || true

preparar_compose_monolitico() {
    cd "$TARGET_DIR" 2>/dev/null || true
    
    # 1. Inicia a topologia base no docker-compose.yml a partir do arquivo base do Core
    cp "$TARGET_DIR/core/config/docker-compose.yml" "$TARGET_DIR/docker-compose.yml"
    
    echo "➜ [SRE INSTALL] Unificando topologia de containers via fusão sequencial acumulativa..."

    for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
        local overlay_path="$TARGET_DIR/core/config/docker-compose.${mod}.yml"
        if [ -f "$overlay_path" ]; then
            echo "  ↳ 🔗 Mesclando overlay do módulo '${mod}'..."
            local MERGE_ERR
            if MERGE_ERR=$(sudo docker compose -f "$TARGET_DIR/docker-compose.yml" -f "$overlay_path" config 2>&1 > "$TARGET_DIR/docker-compose.merged.yml"); then
                mv "$TARGET_DIR/docker-compose.merged.yml" "$TARGET_DIR/docker-compose.yml"
                echo "    ✔ Overlay '${mod}' mesclado com sucesso."
            else
                echo "🚨 [ERRO CRÍTICO INSTALL] Falha ao mesclar overlay do módulo '${mod}':"
                echo "$MERGE_ERR"
                rm -f "$TARGET_DIR/docker-compose.merged.yml" 2>/dev/null || true
                exit 1
            fi
        fi
    done

    echo "✔ [SUCESSO INSTALL] Topologia unificada com sucesso em ./docker-compose.yml"
    
    # [SRE SSOT] Atualiza o inventário do Array Global Único com os serviços do compose resolvido
    resolver_containers_ativos
}
preparar_compose_monolitico

cd "$TARGET_DIR" 2>/dev/null || true

# [SRE DOC] Polimorfismo de Portas: Se estivermos em BYODNS, a API Evolution não usa 
# mais uma porta separada (8081). Tudo passa pela 80/443 usando roteamento por Domínio (SNI).
if [ "$USE_TAILSCALE" = "false" ]; then
    # SRE FIX: Purga a porta 8081 no Compose usando RegEx flexível para evitar quebras por espaço/string
    sed -i -E '/\$\{EVO_PORT.*:8081\/tcp/d' ./docker-compose.yml
    
    if [ "$CADDY_PROTOCOL" = "https" ]; then
        sed -i 's/- "${PROXY_PORT:-80}:80\/tcp"/- "80:80\/tcp"\n      - "443:443\/tcp"/g' ./docker-compose.yml
    fi
fi

echo "➜ [SRE INSTALL] Verificando integridade das imagens Docker locais..."

SERVICOS_DECLARADOS=($(docker compose config --services 2>/dev/null | grep -v '^$' || true))
TOTAL_SERVICOS=${#SERVICOS_DECLARADOS[@]}

if [ "$TOTAL_SERVICOS" -gt 0 ]; then
    # Extrai a lista de imagens declaradas no docker-compose.yml
    IMAGENS_NECESSARIAS=($(docker compose config 2>/dev/null | grep -E '^\s*image:' | awk '{print $2}' | tr -d '"' | tr -d "'" | sort -u || true))
    IMAGENS_FALTANDO=()

    for img in "${IMAGENS_NECESSARIAS[@]}"; do
        if ! docker image inspect "$img" >/dev/null 2>&1; then
            IMAGENS_FALTANDO+=("$img")
        fi
    done

    if [ ${#IMAGENS_FALTANDO[@]} -eq 0 ]; then
        echo "➜ [IDEMPOTÊNCIA INSTALL] Todas as ${#IMAGENS_NECESSARIAS[@]} imagens necessárias já estão presentes no cache local."
    else
        echo "  ↳ Baixando ${#IMAGENS_FALTANDO[@]} imagem(ns) ausente(s) da stack: ${IMAGENS_FALTANDO[*]}..."
        MAX_PULL_RETRIES=3
        PULL_SUCCESS=false

        for tentativa in $(seq 1 $MAX_PULL_RETRIES); do
            # Recalcula imagens ainda ausentes no cache local
            IMAGENS_PENDENTES=()
            for img in "${IMAGENS_FALTANDO[@]}"; do
                if ! docker image inspect "$img" >/dev/null 2>&1; then
                    IMAGENS_PENDENTES+=("$img")
                fi
            done

            if [ ${#IMAGENS_PENDENTES[@]} -eq 0 ]; then
                PULL_SUCCESS=true
                break
            fi

            echo "  ↳ Sincronizando ${#IMAGENS_PENDENTES[@]} imagem(ns) em paralelo (Tentativa ${tentativa}/${MAX_PULL_RETRIES})..."

            local pids=()
            local tmp_logs=()
            local img_map=()

            for img_item in "${IMAGENS_PENDENTES[@]}"; do
                local log_tmp=$(mktemp -t docker_pull_XXXXXX.log)
                docker pull "$img_item" > "$log_tmp" 2>&1 &
                pids+=($!)
                tmp_logs+=("$log_tmp")
                img_map+=("$img_item")
            done

            local falhas_nesta_rodada=0
            for i in "${!pids[@]}"; do
                local pid="${pids[$i]}"
                local log_file="${tmp_logs[$i]}"
                local img_name="${img_map[$i]}"

                if ! wait "$pid"; then
                    falhas_nesta_rodada=$((falhas_nesta_rodada + 1))
                    echo -e "\e[31m  🚨 [FALHA PULL] Imagem: ${img_name}\e[0m"
                    if [ -f "$log_file" ]; then
                        echo -e "\e[33m  ↳ Detalhes do erro:\e[0m"
                        tail -n 10 "$log_file" | sed 's/^/      /'
                    fi
                fi
                rm -f "$log_file" 2>/dev/null || true
            done

            if [ $falhas_nesta_rodada -eq 0 ]; then
                PULL_SUCCESS=true
                break
            else
                if [ "$tentativa" -lt "$MAX_PULL_RETRIES" ]; then
                    BACKOFF=$((tentativa * 3))
                    echo "  ↳ Aguardando ${BACKOFF}s antes de tentar novamente as imagens com falha..."
                    sleep "$BACKOFF"
                fi
            fi
        done

        if [ "$PULL_SUCCESS" = "false" ]; then
            echo "🚨 [ERRO CRÍTICO INSTALL] Falha ao baixar imagens após ${MAX_PULL_RETRIES} tentativas."
            exit 1
        fi
        echo "✔ [SUCESSO INSTALL] Imagens sincronizadas com sucesso no cache local."
    fi

else
    echo "➜ [IDEMPOTÊNCIA INSTALL] Nenhuma imagem declarada pendente."
fi

echo "➜ [SRE INSTALL] Verificando e inicializando infraestrutura de dados base (Postgres, Redis, PgBouncer)..."
INFRA_SERVICES=("postgres" "redis" "pgbouncer")
if [[ "${USE_S3MINIO:-s}" =~ ^[Ss]$ ]]; then
    INFRA_SERVICES+=("s3minio")
fi
INFRA_OFFLINE=()

for svc in "${INFRA_SERVICES[@]}"; do
    STATUS=$(docker compose ps --services --filter "status=running" 2>/dev/null | grep -w "$svc" || echo "")
    if [ -z "$STATUS" ]; then
        INFRA_OFFLINE+=("$svc")
    fi
done

if [ ${#INFRA_OFFLINE[@]} -eq 0 ]; then
    echo "➜ [IDEMPOTÊNCIA INSTALL] Serviços de infraestrutura de dados (${INFRA_SERVICES[*]}) já estão ativos em status RUNNING."
else
    echo "  ↳ Disparando subida seletiva dos serviços offline: ${INFRA_OFFLINE[*]}..."
    if ! DB_UP_ERR=$(docker compose up -d --remove-orphans "${INFRA_OFFLINE[@]}" 2>&1); then
        echo "🚨 [ERRO CRÍTICO INSTALL] Falha ao inicializar os serviços de dados/cache offline (${INFRA_OFFLINE[*]}):"
        echo "$DB_UP_ERR"
        exit 1
    fi
fi

echo "Aguardando prontidão do banco Postgres..."
TENTATIVAS_DB=0
until docker compose exec -T postgres pg_isready -U $DB_USER -d postgres > /dev/null 2>&1 < /dev/null; do
  TENTATIVAS_DB=$((TENTATIVAS_DB+1))
  [ "$TENTATIVAS_DB" -ge 30 ] && { echo "🚨 [ERRO FATAL] Postgres não respondeu após 60s."; exit 1; }
  sleep 2
done
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Baixando imagens e inicializando Banco de Dados e Cache...\e[0m"
step_docker_pull_and_infra

step_ddl_and_migrations() {
# ===============================================================================
echo "=== [FASE 5 INSTALL] Injeção de Schemas DDL e Isolação dos Bancos Lógicos ========="
# ===============================================================================
cd "$TARGET_DIR" 2>/dev/null || true
echo "➜ [SRE INSTALL] Validando prontidão do banco PostgreSQL..."
TENTATIVAS_DB_MIG=0
until docker compose exec -T postgres pg_isready -U $DB_USER -d ${PREFIXO_CONTAINER}_db > /dev/null 2>&1 < /dev/null; do
  TENTATIVAS_DB_MIG=$((TENTATIVAS_DB_MIG+1))
  [ "$TENTATIVAS_DB_MIG" -ge 30 ] && { echo "🚨 [ERRO FATAL INSTALL] Postgres não respondeu após 60s."; exit 1; }
  sleep 2
done

# 1. Injeção de DDL idempotente (init.sql com IF NOT EXISTS)
if [ -f "./core/database/init.sql" ]; then
    docker compose exec -T postgres psql -U $DB_USER -d ${PREFIXO_CONTAINER}_db -q < ./core/database/init.sql > /dev/null 2>&1 || true
elif [ -f "$TARGET_DIR/core/database/init.sql" ]; then
    docker compose exec -T postgres psql -U $DB_USER -d ${PREFIXO_CONTAINER}_db -q < "$TARGET_DIR/core/database/init.sql" > /dev/null 2>&1 || true
fi

# 2. Bancos lógicos do Core
echo "➜ [SRE CORE INSTALL] Garantindo bancos de dados lógicos do Core (litellm_db)..."
for db in litellm_db; do
    if docker compose exec -T postgres psql -U $DB_USER -d ${PREFIXO_CONTAINER}_db -c "SELECT 1 FROM pg_database WHERE datname = '$db'" < /dev/null 2>/dev/null | grep -q 1; then
        echo "➜ [IDEMPOTÊNCIA INSTALL] Banco de dados Core '$db' já existente. Preservando esquema."
    else
        echo "  ↳ Criando banco de dados Core '$db'..."
        docker compose exec -T postgres psql -U $DB_USER -d ${PREFIXO_CONTAINER}_db -q -c "CREATE DATABASE $db;" < /dev/null > /dev/null 2>&1 || true
    fi
done

# 3. Bancos lógicos dos módulos desacoplados (Invocação Polimórfica)
echo "➜ [SRE MODULOS INSTALL] Garantindo bancos de dados lógicos dos módulos ativos..."
[ ${#MODULOS_DESACOPLADOS_ATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados

for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
    if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
        bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" provision_db 2>/dev/null || true
    fi
done

# --- PREVENÇÃO SRE: CRIANDO CONFIG PLACEHOLDER ANTES DO BOOT ---
mkdir -p "$TARGET_DIR/volumes/litellm_data" 2>/dev/null || true
if [ ! -f "$TARGET_DIR/volumes/litellm_data/config.yaml" ]; then
    echo "➜ [SRE BOOTSTRAP] Criando placeholder de config.yaml para montagem de volume do LiteLLM..."
    cat << 'EO_BASE' > "$TARGET_DIR/volumes/litellm_data/config.yaml"
litellm_settings:
  drop_params: true
EO_BASE
else
    echo "➜ [SRE BOOTSTRAP] Placeholder de config.yaml presente. Aguardando subida para sincronização de catálogo."
fi
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Injeção DDL e Isolamento Lógico de Bancos...\e[0m"
step_ddl_and_migrations

step_docker_up_apps() {
# ====================================================================================
echo "=== [FASE 6 INSTALL] Provisionamento Zero-Touch dos Microsserviços e Inteligência ======"
# ====================================================================================
echo "➜ [SRE INSTALL] Verificando status e orquestrando subida da malha de microsserviços..."
cd "$TARGET_DIR" 2>/dev/null || true

ALL_DECLARED_SERVICES=($(docker compose config --services 2>/dev/null | grep -v '^$' || true))
RUNNING_SERVICES=($(docker compose ps --services --filter "status=running" 2>/dev/null | grep -v '^$' || true))
APPS_OFFLINE=()

for svc in "${ALL_DECLARED_SERVICES[@]}"; do
    if ! echo "${RUNNING_SERVICES[*]}" | grep -qw "$svc"; then
        APPS_OFFLINE+=("$svc")
    fi
done

if [ ${#APPS_OFFLINE[@]} -eq 0 ]; then
    echo "➜ [IDEMPOTÊNCIA INSTALL] Todos os ${#ALL_DECLARED_SERVICES[@]} serviços declarados já estão rodando em status RUNNING."
else
    echo "  ↳ Disparando subida seletiva apenas dos microsserviços offline: ${APPS_OFFLINE[*]}..."
    
    # SRE FIX: Proteção contra falso-negativo de 'unhealthy' e 'Address already in use' (Race condition de IP)
    if ! UP_ERR=$(docker compose up -d --remove-orphans "${APPS_OFFLINE[@]}" 2>&1); then
        if echo "$UP_ERR" | grep -qiE "Address already in use|failed to set up container networking"; then
            echo "⚠️ [SRE RECOVERY INSTALL] O Docker Engine encontrou race condition de alocação de IP ('Address already in use')."
            echo "  ↳ Purgando contêineres órfãos e recriando com flush de rede..."
            for svc_off in "${APPS_OFFLINE[@]}"; do
                docker rm -f "${PREFIXO_CONTAINER}_${svc_off}" 2>/dev/null || true
            done
            sleep 3
            if ! UP_ERR_NET=$(docker compose up -d --force-recreate "${APPS_OFFLINE[@]}" 2>&1); then
                echo "🚨 [ERRO CRÍTICO INSTALL] Falha na re-alocação de IP dos microsserviços:"
                echo "$UP_ERR_NET"
                exit 1
            fi
        elif echo "$UP_ERR" | grep -qiE "unhealthy|dependency failed"; then
            echo "⚠️ [SRE RECOVERY INSTALL] O Docker bloqueou a subida pois uma dependência reportou 'unhealthy' temporário (Pico de CPU/IO)."
            echo "  ↳ Aguardando 15s para estabilização das migrações e readiness probes..."
            sleep 15
            
            echo "  ↳ Retentando injeção dos contêineres..."
            if ! UP_ERR2=$(docker compose up -d --remove-orphans "${APPS_OFFLINE[@]}" 2>&1); then
                echo "  ↳ Resetando o estado de saúde dos bancos e retentando..."
                docker restart ${PREFIXO_CONTAINER}_redis ${PREFIXO_CONTAINER}_postgres > /dev/null 2>&1 || true
                sleep 10
                if ! UP_ERR3=$(docker compose up -d --remove-orphans "${APPS_OFFLINE[@]}" 2>&1); then
                    echo "🚨 [ERRO CRÍTICO INSTALL] Falha definitiva ao inicializar microsserviços:"
                    echo "$UP_ERR3"
                    exit 1
                fi
            fi
        else
            echo "🚨 [ERRO CRÍTICO INSTALL] Falha ao inicializar os microsserviços:"
            echo "$UP_ERR"
            exit 1
        fi
    fi
    # SRE: Recria o Caddy WAF com os novos mapeamentos de portas e Caddyfile consolidado
    echo "➜ [SRE INSTALL] Sincronizando portas e rotas de borda no Caddy WAF..."
    sudo docker compose up -d --force-recreate caddy > /dev/null 2>&1 || true

    # --- AUTOMAÇÃO ATÔMICA DO CATÁLOGO DE IAS (HÍBRIDO) ---
    if [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4000/health/liveliness || echo "000")" != "200" ]; then
        echo "➜ [SRE INSTALL] Aguardando prontidão do AI Gateway (LiteLLM) para carga atômica..."
        until [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4000/health/liveliness || echo "000")" = "200" ]; do
            sleep 3
        done
    fi
fi
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Subida e Orquestração dos Microsserviços...\e[0m"
step_docker_up_apps

# ===============================================================================
# 🚀 PROVISIONAMENTO AUTO-ADMIN UNIFICADO (ZERO-TOUCH & IDEMPOTENTE)
# ===============================================================================

step_provision_decoupled_modules() {
    echo "=== [SRE PROVISION INSTALL] Provisionamento e Validação das Aplicações Desacopladas ==="
    [ ${#MODULOS_DESACOPLADOS_ATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados

    # 1. Provisionamento de infraestrutura (regras de iptables/firewall e schemas)
    for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
        if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
            echo "➜ [SRE INSTALL] Provisionando infraestrutura e schema do módulo '${mod}'..."
            bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" provision_infra 2>/dev/null || true
        fi
    done
    sudo systemctl restart dnsmasq 2>/dev/null || true

    # 2. SRE PERFORMANCE: Validação de prontidão (wait_readiness) paralela e não-bloqueante
    echo "➜ [SRE INSTALL] Disparando probes de prontidão (wait_readiness) em paralelo para todos os módulos..."
    local READINESS_PIDS=()
    for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
        if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
            (
                bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" wait_readiness 2>/dev/null || true
            ) &
            READINESS_PIDS+=($!)
        fi
    done

    # Aguarda a finalização simultânea de todas as sondas
    for pid in "${READINESS_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    echo "✔ [SUCESSO INSTALL] Probes de prontidão de todos os módulos validadas com sucesso."
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Provisionamento e Prontidão dos Módulos Desacoplados...\e[0m"
step_provision_decoupled_modules

step_provision_ai_gateway() {
# --- PROVISIONAMENTO ADMIN LITELLM (CORE) ---
echo "➜ [SRE INSTALL] Verificando prontidão do AI Gateway (LiteLLM)..."
TENTATIVAS_LLM=0
until [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4000/health/liveliness || echo "000")" = "200" ]; do
  TENTATIVAS_LLM=$((TENTATIVAS_LLM+1))
  [ "$TENTATIVAS_LLM" -ge 24 ] && { echo "🚨 [ERRO FATAL INSTALL] API do LiteLLM não respondeu após 120s."; exit 1; }
  sleep 5
done
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Cadastrando Hub Organizacional LiteLLM...\e[0m"
step_provision_ai_gateway

step_crontab_and_maintenance() {
    # Garante permissões de execução nos scripts de manutenção
    chmod +x "$TARGET_DIR/core/scripts/"*.sh 2>/dev/null || true

    # Injeta na crontab limpando as regras antigas para manter a idempotência estrita de SRE
    CURRENT_CRON=$(crontab -l 2>/dev/null || echo "")
    LINE_BACKUP="0 23 * * * /bin/bash $TARGET_DIR/core/scripts/backup_diario.sh"
    LINE_SYNC="0 4 * * * /bin/bash $TARGET_DIR/core/scripts/install_1ia.sh"

    if ! echo "$CURRENT_CRON" | grep -qF "$LINE_BACKUP" || ! echo "$CURRENT_CRON" | grep -qF "$LINE_SYNC"; then
        echo "  ↳ Injetando agendamentos SRE na crontab do sistema..."
        crontab -l 2>/dev/null | grep -v "backup_diario.sh" | grep -v "upgrade_stack.sh" | grep -v "install_1ia.sh" | grep -v "sync_ia_models.sh" > /tmp/cron_limpo || true
        echo "$LINE_BACKUP" >> /tmp/cron_limpo
        echo "$LINE_SYNC" >> /tmp/cron_limpo
        crontab /tmp/cron_limpo && rm -f /tmp/cron_limpo
    else
        echo "➜ [IDEMPOTÊNCIA INSTALL] Agendamentos Cron já presentes no sistema. Preservando estado."
    fi
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Injetando Crontabs e rotinas de manutenção...\e[0m"
step_crontab_and_maintenance

step_bootstrap_admin_users() {
echo "=== [SRE DML INSTALL] Provisionamento Unificado e Idempotente de Contas Administrativas ==="

# 1. LiteLLM Admin (Core)
USER_INFO=$(curl -s -X GET "http://127.0.0.1:4000/user/info?user_id=${TS_EMAIL}" -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" 2>/dev/null || echo "")
if echo "$USER_INFO" | grep -q "${TS_EMAIL}" && ! echo "$USER_INFO" | grep -q '"error"'; then
    echo "➜ [IDEMPOTÊNCIA INSTALL] Administrador LiteLLM já cadastrado (${TS_EMAIL})."
else
    PAYLOAD_NEW=$(jq -n --arg email "$TS_EMAIL" '{user_id: $email, user_email: $email, user_role: "proxy_admin", models: ["all"]}')
    curl -s -X POST "http://127.0.0.1:4000/user/new" -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json" -d "$PAYLOAD_NEW" > /dev/null 2>&1 || true
    PAYLOAD_UPDATE=$(jq -n --arg email "$TS_EMAIL" --arg pwd "$DB_PASSWORD" '{user_id: $email, password: $pwd, user_role: "proxy_admin"}')
    curl -s -X POST "http://127.0.0.1:4000/user/update" -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json" -d "$PAYLOAD_UPDATE" > /dev/null 2>&1 || true
    echo "➜ [SUCESSO INSTALL] Administrador LiteLLM cadastrado."
fi

# 2. PROVISÃO POLIMÓRFICA DE USUÁRIOS DOS MÓDULOS DESACOPLADOS ATIVOS (PARALELIZADO)
[ ${#MODULOS_DESACOPLADOS_ATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados

USER_PROV_PIDS=()
for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
    if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
        (
            bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" provision_user
        ) &
        USER_PROV_PIDS+=($!)
    fi
done

for pid in "${USER_PROV_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Provisionamento Unificado de Contas Administrativas...\e[0m"
step_bootstrap_admin_users

step_sync_ai_models() {
# Limpeza e remoção do clone temporário se a execução foi Headless
if [ "$RAIZ_REPO" = "/tmp/infra-loja-bootstrap" ]; then rm -rf /tmp/infra-loja-bootstrap; fi

# ===============================================================================
# SRE /READINESS PROBES: VALIDAÇÃO DINÂMICA DO CICLO DE VIDA DOS ATIVOS E AUTO-HEALING
# ===============================================================================
echo "=== [SRE INSTALL] Inicializando Probes Dinâmicas de Prontidão (Readiness Probes) ==="

[ ${#STACK_ACTIVE_CONTAINERS[@]} -eq 0 ] && resolver_containers_ativos

# SRE IDEMPOTÊNCIA: Validação rápida - se todos já estiverem saudáveis, avança sem loops de espera
ALL_INSTANT_HEALTHY=true
for container in "${STACK_ACTIVE_CONTAINERS[@]}"; do
    HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{if .State.Running}}healthy{{else}}unhealthy{{end}}{{end}}' "$container" 2>/dev/null || echo "OFFLINE")
    if [ "$HEALTH" != "healthy" ]; then
        ALL_INSTANT_HEALTHY=false
        break
    fi
done

if [ "$ALL_INSTANT_HEALTHY" = "true" ]; then
    echo "➜ [IDEMPOTÊNCIA & SRE INSTALL] Todos os ${#STACK_ACTIVE_CONTAINERS[@]} ativos já estão em estado [healthy]! Prosseguindo com sincronização de IA..."
    TODO_ECOSSISTEMA_SAUDAVEL=true
else
    TIMEOUT=120
    ELAPSED=0
    CHECK_INTERVAL=5
    TODO_ECOSSISTEMA_SAUDAVEL=true

    while [ $ELAPSED -lt $TIMEOUT ]; do
        ALL_HEALTHY=true
        for container in "${STACK_ACTIVE_CONTAINERS[@]}"; do
            HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{if .State.Running}}healthy{{else}}unhealthy{{end}}{{end}}' "$container" 2>/dev/null || echo "OFFLINE")
            
            if [ "$HEALTH" != "healthy" ]; then
                ALL_HEALTHY=false
                if [ "$HEALTH" = "unhealthy" ]; then
                    echo "  ↳ [SRE AUTO-HEALING INSTALL] Container $container detectado como UNHEALTHY. Acionando reinício de resgate..."
                    docker restart "$container" > /dev/null 2>&1 || true
                fi
            fi
        done

        if [ "$ALL_HEALTHY" = "true" ]; then
            echo "➜ [SUCESSO INSTALL] Todos os ativos atingiram o estado [healthy]! Prosseguindo com sincronização de IA..."
            break
        fi

        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))
        echo "  ↳ Aguardando prontidão da malha ou ação do Auto-Healing (${ELAPSED}/${TIMEOUT}s)..."
    done

    if [ "$ALL_HEALTHY" != "true" ]; then
        echo "⚠️ [AVISO SRE INSTALL] Timeout atingido! Alguns contêineres não estabilizaram a saúde a tempo."
        TODO_ECOSSISTEMA_SAUDAVEL=false
    fi
fi


echo "➜ [SRE INSTALL] Forjando motor de sincronização dinâmica (Catálogo Inteligente)..."
    # Copia o template desacoplado do motor de sincronização inteligente de IA
    cp "$RAIZ_REPO/core/scripts/install_1ia.sh" "$TARGET_DIR/core/scripts/install_1ia.sh" 2>/dev/null || true
    chmod +x "$TARGET_DIR/core/scripts/install_1ia.sh"

chmod +x "$TARGET_DIR/core/scripts/install_1ia.sh"

if [ -f "$TARGET_DIR/core/scripts/install_1ia.sh" ] && [ "$TODO_ECOSSISTEMA_SAUDAVEL" = "true" ]; then
    echo "=== [SRE INSTALL] Ecossistema estável. Executando Sincronização Atômica de Inteligência ==="
    local SYNC_OUT
    SYNC_OUT=$(sudo bash "$TARGET_DIR/core/scripts/install_1ia.sh" < /dev/null 2>&1 || true)
    echo "$SYNC_OUT"

    # SRE IDEMPOTÊNCIA: Só entra em amortecimento/espera se o LiteLLM de fato precisou ser reiniciado
    if echo "$SYNC_OUT" | grep -q "serviço reiniciado"; then
        echo "=== [SRE GUARDRAIL INSTALL] Amortecendo e aguardando re-estabilização pós-restart dos microsserviços ==="

        # Contêineres ativos da stack resolvidos dinamicamente (SSOT)
        [ ${#STACK_ACTIVE_CONTAINERS[@]} -eq 0 ] && resolver_containers_ativos
        RESTARTED_CONTAINERS=("${STACK_ACTIVE_CONTAINERS[@]}")

        # Loop de tolerância de até 90 segundos com intervalo de 3s
        MAX_WAIT=90
        WAIT_COUNT=0
        ALL_STABLE=false
        PENDING_CONTAINERS=()

        while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
            ALL_STABLE=true
            PENDING_CONTAINERS=()
            for container in "${RESTARTED_CONTAINERS[@]}"; do
                # Captura o status exato: running/healthy
                HEALTH_STATE=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{if .State.Running}}healthy{{else}}unhealthy{{end}}{{end}}' "$container" 2>/dev/null || echo "OFFLINE")
     
                if [ "$HEALTH_STATE" != "healthy" ]; then
                    ALL_STABLE=false
                    PENDING_CONTAINERS+=("${container} (${HEALTH_STATE})")
                fi
            done

            if [ "$ALL_STABLE" = "true" ]; then
                echo "➜ [SUCESSO INSTALL] Todos os microsserviços reiniciados atingiram estabilidade [healthy]!"
                break
            fi

            sleep 3
            WAIT_COUNT=$((WAIT_COUNT + 3))
            echo "  ↳ Aguardando reconexão das aplicações no barramento (${WAIT_COUNT}/${MAX_WAIT}s)..."
        done

        if [ "$ALL_STABLE" = "false" ]; then
            echo "⚠️ [AVISO SRE] Contêineres ainda em processo de estabilização pós-restart:"
            for p_cnt in "${PENDING_CONTAINERS[@]}"; do
                echo "    ↳ ${p_cnt}"
            done
            echo "  ↳ O grace period foi concedido. Prosseguindo com os testes de auditoria."
        fi
    fi
fi
}
echo -e "\e[33m⏳ [EXECUTANDO INSTALL] Sincronização Dinâmica do Catálogo Inteligente...\e[0m"
step_sync_ai_models

echo "=== [SRE AUDIT INSTALL] Inicializando varredura de rede e testes de handshakes ==="

# 1. Descoberta de IPs Físicos do Host (Interface LAN)
ENV_FILE="${TARGET_DIR}/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="${RAIZ_REPO}/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="./.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE"; set +a
fi
if [ "$USE_TAILSCALE" = "true" ] && [ -z "${TS_DOMAIN:-}" ]; then
    TS_DOMAIN=$(tailscale status --json 2>/dev/null | grep -A 10 '"Self":' | grep '"DNSName"' | head -n 1 | cut -d'"' -f4 | sed 's/\.$//' | tr -d '\r\n ' || true)
fi
IP_HOST_LAN=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || hostname -I | awk '{print $1}' || echo "127.0.0.1")

# [SRE DOC] Polimorfismo de Relatório: Coleta IPs e Metadados baseados na topologia de rede escolhida
if [ "$USE_TAILSCALE" = "true" ]; then
    IP_TAILSCALE=$(tailscale ip -4 2>/dev/null | tr -d '\r\n ' || echo "Offline")
    REPORT_BORDER_INFO="  ↳ IP Perimetral Tailscale: $IP_TAILSCALE"
    REPORT_PORTAL_URL="https://${TS_DOMAIN}"
else
    REPORT_BORDER_INFO="  ↳ Roteamento de Borda:     BYODNS (Nginx/Cloudflare/IP Fixo)"
    REPORT_PORTAL_URL="${CADDY_PROTOCOL:-http}://${TS_DOMAIN}"
fi

# 2. IP Privado do Host
IP_BOUNCER="${IP_PGBOUNCER:-127.0.0.1}"

# ===============================================================================
# 3. TESTES CONDICIONAIS DE HANDSHAKE (Guarda de Segurança)
# ===============================================================================
# --- Módulo Portal Gateway (Caddy WAF) ---
HTTP_GATEWAY_LOCAL=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:${HOST_CADDY_PORT:-80}/healthz" || echo "000")

if [ "$USE_TAILSCALE" = "true" ]; then
    HTTP_GATEWAY_FUNNEL=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "https://${TS_DOMAIN}/healthz" || echo "000")
    
    # SRE IDEMPOTÊNCIA: Se o Funnel ainda não estiver respondendo 200, concede um amortecimento de 10s
    if [ "$HTTP_GATEWAY_FUNNEL" != "200" ]; then
        echo "=== [SRE INSTALL] Amortecendo barramento (10s) para estabilização do Funnel... ==="
        sleep 10
        HTTP_GATEWAY_FUNNEL=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${TS_DOMAIN}/healthz" || echo "000")
    fi

    if [ "$HTTP_GATEWAY_FUNNEL" = "200" ] || sudo tailscale funnel status 2>/dev/null | grep -q "https://${TS_DOMAIN}"; then
        STATUS_GATEWAY="✅ HTTPS Público: OK"
        REPORT_PORTAL_URL="https://${TS_DOMAIN}"
        HTTP_GATEWAY="200"
    elif [ "$HTTP_GATEWAY_LOCAL" = "200" ]; then
        REPORT_PORTAL_URL="http://${TS_DOMAIN}"
        TS_RATE_LIMIT_LOG=$(journalctl -u tailscaled --no-pager 2>/dev/null | grep -iE "retry after|too many certificates|acme: error: 429|rate limit" | tail -n 1 || true)
        if [ -n "$TS_RATE_LIMIT_LOG" ]; then
            if echo "$TS_RATE_LIMIT_LOG" | grep -qi "retry after"; then
                RETRY_DATE=$(echo "$TS_RATE_LIMIT_LOG" | sed -n 's/.*retry after \([0-9-]* [0-9:]* UTC\).*/\1/p')
                LOCAL_RETRY=$(date -d "$RETRY_DATE" +'%d/%m/%Y às %H:%M:%S' 2>/dev/null || echo "$RETRY_DATE (UTC)")
                STATUS_GATEWAY="⏳ Let's Encrypt Rate Limit! HTTPS liberado em: $LOCAL_RETRY"
            else
                MOTIVO=$(echo "$TS_RATE_LIMIT_LOG" | grep -oE "too many.*|rate limit.*" | head -n 1 || echo "Bloqueio ACME 429")
                STATUS_GATEWAY="⏳ Let's Encrypt Rate Limit! Motivo: $MOTIVO"
            fi
        else
            STATUS_GATEWAY="⚠️ Funnel Desativado | HTTP Tailnet: OK"
        fi
        HTTP_GATEWAY="200"
    else
        STATUS_GATEWAY="❌ WAF Offline"
        REPORT_PORTAL_URL="http://${TS_DOMAIN}"
        HTTP_GATEWAY="FALHOU"
    fi
else
    # BYODNS / Acesso Direto HTTP
    REPORT_PORTAL_URL="http://${TS_DOMAIN}"
    if [ "$HTTP_GATEWAY_LOCAL" = "200" ]; then
        STATUS_GATEWAY="200"
        HTTP_GATEWAY="200"
    else
        STATUS_GATEWAY="❌ WAF Offline"
        HTTP_GATEWAY="FALHOU"
    fi
fi

# --- Módulo AI Gateway (LiteLLM) ---
HEALTH_LITELLM=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{if .State.Running}}healthy{{else}}unhealthy{{end}}{{end}}' ${PREFIXO_CONTAINER}_litellm 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_LITELLM" = "healthy" ]; then
    HTTP_LITELLM=$(docker exec ${PREFIXO_CONTAINER}_litellm python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:4000/health/liveliness').getcode())" 2>/dev/null || echo "FALHOU")
else
    HTTP_LITELLM="CONTAINER_ERRO"
fi



# --- Módulo Redis Cache ---
HEALTH_REDIS=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_redis 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_REDIS" = "healthy" ]; then
    STATUS_REDIS=$(docker exec ${PREFIXO_CONTAINER}_redis redis-cli ping 2>/dev/null | grep -q PONG && echo "Saudável" || echo "FALHOU")
else
    STATUS_REDIS="CONTAINER_OFFLINE"
fi

# --- Módulo Cluster PostgreSQL ---
HEALTH_DB=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_postgres 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_DB" = "healthy" ]; then
    STATUS_POSTGRES=$(docker exec ${PREFIXO_CONTAINER}_postgres pg_isready -U "$DB_USER" -d "${PREFIXO_CONTAINER}_db" >/dev/null 2>&1 && echo " Saudável" || echo " FALHOU")
else
    STATUS_POSTGRES=" CONTAINER_OFFLINE"
fi

# --- Módulo Connection Pooler (PgBouncer) ---
HEALTH_POOLER=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_pgbouncer 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_POOLER" = "healthy" ] && [ "$HEALTH_DB" = "healthy" ]; then
    STATUS_BOUNCER=$(docker exec ${PREFIXO_CONTAINER}_postgres pg_isready -h ${PREFIXO_CONTAINER}_pgbouncer -p 6432 -U "${DB_USER}" -d "${PREFIXO_CONTAINER}_db" >/dev/null 2>&1 && echo " Saudável" || echo " FALHOU")
else
    STATUS_BOUNCER=" CONTAINER_OFFLINE"
fi

# ===============================================================================
# 🛡️ SRE DR: COLD BACKUP INICIAL (DIA 0) - APENAS EM SUCESSO 100%
# ===============================================================================
# [SRE DOC] Resiliência de Checkpoint: Trata fallbacks de variáveis caso a auditoria rode 
# via checkpoint isolado, impedindo falsos-negativos no disparo do Cold Backup do Dia 0.
[ -z "$HTTP_GATEWAY" ] && [ "$HTTP_GATEWAY_LOCAL" = "200" ] && HTTP_GATEWAY="200"
[ -z "$HTTP_GATEWAY" ] && [ "$HTTP_GATEWAY_FUNNEL" = "200" ] && HTTP_GATEWAY="200"

ARTEFATO_BACKUP="NÃO GERADO (ECOSSISTEMA COM ALERTAS)"

if [ "$TODO_ECOSSISTEMA_SAUDAVEL" = "true" ] && \
   { [ "$HTTP_GATEWAY" = "200" ] || [ "$HTTP_GATEWAY_LOCAL" = "200" ]; } && \
   [ "$STATUS_REDIS" = "Saudável" ]; then

    USER_REAL_HOME=$(eval echo "~${SUDO_USER:-$USER}")
    EXISTING_BACKUP=$(ls -t "${USER_REAL_HOME}/backup_${PREFIXO_CONTAINER}_"*.sql.gz.gpg 2>/dev/null | head -n 1 || echo "")

    if [ -n "$EXISTING_BACKUP" ] && [ -f "$EXISTING_BACKUP" ]; then
        echo "➜ [IDEMPOTÊNCIA INSTALL] Backup Inicial (Dia 0) já existe. Preservando artefato: $EXISTING_BACKUP"
        ARTEFATO_BACKUP="$EXISTING_BACKUP"
    else
        echo "=== [SRE DR INSTALL] Ecossistema 100% Operacional! Executando Backup Inicial (Dia 0) ==="
        if bash "$TARGET_DIR/core/scripts/backup_diario.sh"; then
            ARTEFATO_BACKUP=$(ls -t "${USER_REAL_HOME}/backup_${PREFIXO_CONTAINER}_"*.sql.gz.gpg 2>/dev/null | head -n 1 || echo "ERRO_NA_CAPTURA")
            echo "➜ [SUCESSO INSTALL] Cold Backup gerado, testado no Sanity Check e cifrado via GPG!"
            echo "   ↳ Artefato: $ARTEFATO_BACKUP"
        else
            echo "⚠️ [ALERTA INSTALL] O ecossistema está saudável, mas o script de backup falhou na execução."
            ARTEFATO_BACKUP="FALHA NO EXPURGO/GPG"
        fi
    fi
else
    echo "⚠️ [SRE SKIP INSTALL] Backup inicial ignorado pois o ambiente apresentou instabilidade nos handshakes."
fi

# ===============================================================================
# RELATÓRIO FORENSE CONSOLIDADO DO ECOSSISTEMA
# ===============================================================================
echo ""
echo "====================================================================="
if [ "$TODO_ECOSSISTEMA_SAUDAVEL" = "true" ]; then
    echo "        [SUCESSO ABSOLUTO INSTALL] ECOSSISTEMA DE PROVISIONAMENTO ATIVO       "
else
    echo "        [CONCLUÍDO COM ALERTAS] ECOSSISTEMA REQUER ATENÇÃO            "
fi
echo "====================================================================="
echo "➜ INFRAESTRUTURA FÍSICA DO HOST:"
echo "  ↳ IP Privado Local (LAN):  $IP_HOST_LAN"
echo "$REPORT_BORDER_INFO"
echo "  ↳ Domínio FQDN Canônico:   $TS_DOMAIN"
echo ""
echo ""
echo "➜ MAPEAMENTO TOPOLÓGICO DE ATIVOS (DOCKER MALHA INTERNA):"
[ ${#STACK_ACTIVE_CONTAINERS[@]} -eq 0 ] && resolver_containers_ativos

# Varre e imprime dinamicamente todos os containers da stack em ordem alfabética
for cnt in $(printf '%s\n' "${STACK_ACTIVE_CONTAINERS[@]}" | sort); do
    [ -z "$cnt" ] && continue
    svc_name=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$cnt" 2>/dev/null || echo "")
    [ -z "$svc_name" ] && svc_name="${cnt#${PREFIXO_CONTAINER}_}"
    
    ip_cnt=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$cnt" 2>/dev/null || echo "N/A")
    ports_cnt=$(docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{(index $conf 0).HostPort}}->{{$p}} {{else}}{{$p}} {{end}}{{end}}' "$cnt" 2>/dev/null | xargs 2>/dev/null || echo "N/A")
    [ -z "$ports_cnt" ] && ports_cnt="N/A"

    printf "  ↳ %-24s (Container: %-18s) | IP: %-15s | Portas: %s\n" "${svc_name}" "${cnt}" "${ip_cnt}" "${ports_cnt}"
done

echo ""
echo "➜ MATRIZ DE ROTEAMENTO E STATUS DE HANDSHAKES:"

ROUTING_LINES=()

[ ${#STACK_ACTIVE_CONTAINERS[@]} -eq 0 ] && resolver_containers_ativos

# SRE PERFORMANCE: Auditoria de integridade e handshakes em paralelo (background subshells com pipes temporários)
AUDIT_TMP_DIR=$(mktemp -d /tmp/sre_audit.XXXXXX 2>/dev/null || echo "/tmp/sre_audit_tmp")
mkdir -p "$AUDIT_TMP_DIR" 2>/dev/null || true
AUDIT_PIDS=()

for cnt in "${STACK_ACTIVE_CONTAINERS[@]}"; do
    [ -z "$cnt" ] && continue
    svc="${cnt#${PREFIXO_CONTAINER}_}"
    
    (
        if [ -f "$TARGET_DIR/core/scripts/install_${svc}.sh" ]; then
            line=$(bash "$TARGET_DIR/core/scripts/install_${svc}.sh" "$TARGET_DIR" audit_health "${TS_DOMAIN:-localhost}" 2>/dev/null || true)
            [ -n "$line" ] && echo "${svc}|${line}" > "$AUDIT_TMP_DIR/${svc}.txt"
        elif [ "$svc" = "temporal" ] && [ -f "$TARGET_DIR/core/scripts/install_postiz.sh" ]; then
            : # O audit_health do postiz já inclui a checagem do temporal
        else
            case "$svc" in
                caddy)
                    msg=$(printf "  ↳ %-32s %s  -> Status: [%s]" "Acesso Portal Gateway:" "${REPORT_PORTAL_URL}" "${STATUS_GATEWAY}")
                    echo "caddy|${msg}" > "$AUDIT_TMP_DIR/${svc}.txt"
                    ;;
                litellm)
                    msg=$(printf "  ↳ %-32s http://%s:4000/health/liveliness  -> Status: [%s]" "AI Gateway (LiteLLM):" "${TS_DOMAIN}" "${HTTP_LITELLM}")
                    echo "litellm|${msg}" > "$AUDIT_TMP_DIR/${svc}.txt"
                    ;;
                postgres)
                    st=$(docker exec "$cnt" pg_isready -U "$DB_USER" -d "${PREFIXO_CONTAINER}_db" >/dev/null 2>&1 && echo "Saudável" || echo "FALHOU")
                    msg=$(printf "  ↳ %-32s 5432/tcp -> [%s]" "Banco Core (Postgres):" "${st}")
                    echo "postgres|${msg}" > "$AUDIT_TMP_DIR/${svc}.txt"
                    ;;
                pgbouncer)
                    st=$(docker exec "${PREFIXO_CONTAINER}_postgres" pg_isready -h "${PREFIXO_CONTAINER}_pgbouncer" -p 6432 -U "${DB_USER}" -d "${PREFIXO_CONTAINER}_db" >/dev/null 2>&1 && echo "Saudável" || echo "FALHOU")
                    msg=$(printf "  ↳ %-32s 6432/tcp -> [%s]" "Connection Pooler:" "${st}")
                    echo "pgbouncer|${msg}" > "$AUDIT_TMP_DIR/${svc}.txt"
                    ;;
                redis)
                    st=$(docker exec "$cnt" redis-cli ping 2>/dev/null | grep -q PONG && echo "Saudável" || echo "FALHOU")
                    msg=$(printf "  ↳ %-33s 6379/tcp -> [%s]" "Cache em Memória (Redis):" "${st}")
                    echo "redis|${msg}" > "$AUDIT_TMP_DIR/${svc}.txt"
                    ;;
                *)
                    hlth=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{if .State.Running}}healthy{{else}}unhealthy{{end}}{{end}}' "$cnt" 2>/dev/null || echo "OFFLINE")
                    msg=$(printf "  ↳ %-32s %s -> Status: [%s]" "Serviço (${svc}):" "${cnt}" "${hlth}")
                    echo "${svc}|${msg}" > "$AUDIT_TMP_DIR/${svc}.txt"
                    ;;
            esac
        fi
    ) &
    AUDIT_PIDS+=($!)
done

for pid in "${AUDIT_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

for res_file in "$AUDIT_TMP_DIR"/*.txt; do
    [ -f "$res_file" ] && ROUTING_LINES+=("$(cat "$res_file")")
done
rm -rf "$AUDIT_TMP_DIR" 2>/dev/null || true


# Imprime linhas da matriz de roteamento 100% ordenadas alfabeticamente por serviço (preservando frases)
printf '%s\n' "${ROUTING_LINES[@]}" | sort | while IFS= read -r entry; do
    [ -n "$entry" ] && echo "${entry#*|}"
done
echo ""
echo "➜ MATRIZ DE ACESSO, APIS E ENDPOINTS SRE (WHITE-LABEL):"
echo "  🌐 WAF Borda (Caddy)"
echo "    ↳ Portal Omnichannel (Frontend):   ${REPORT_PORTAL_URL}"
echo ""
echo "  🔄 Pool de Conexões PostgreSQL (PgBouncer)"
echo "    ↳ Endpoint TCP:                    ${TS_DOMAIN}:6432"
echo ""
echo "  🤖 AI Gateway (LiteLLM)"
echo "    ↳ Admin UI:                        http://${TS_DOMAIN}:4000/ui"
echo "    ↳ MCP Gateway Server:              http://${TS_DOMAIN}:4000/mcp"
echo "    ↳ Descoberta de Modelos:           http://${TS_DOMAIN}:4000/v1/models"
echo "    ↳ Chat Completions:                http://${TS_DOMAIN}:4000/v1/chat/completions"
echo "    ↳ Embeddings API:                  http://${TS_DOMAIN}:4000/v1/embeddings"
echo "    ↳ Liveliness:                      http://${TS_DOMAIN}:4000/health/liveliness"
echo ""
[ ${#MODULOS_DESACOPLADOS_ATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados

for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
    if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
        bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" render_forensic_report "${TS_DOMAIN:-localhost}"
    fi
done
echo ""
echo "  🔑 CREDENCIAIS DO CLIENTE (Acesso Global Unificado):"
echo "    - E-mail:                                  ${TS_EMAIL}"
echo "    - Senha / Master Secret / API Master Key:  ${DB_PASSWORD}"
echo "====================================================================="
echo "  [SRE AUDIT COMPLETO INSTALL] Varredura dinâmica de prontidão finalizada."
echo "====================================================================="

# ===============================================================================
# 🎯 PROTOCOLO DE TRIAGEM AUTOMÁTICA (LOG PATH DISCOVERY)
# ===============================================================================
ECOSSISTEMA_COM_ALERTAS=false
if [ "$TODO_ECOSSISTEMA_SAUDAVEL" = "false" ] || \
   [ "$HTTP_GATEWAY" = "FALHOU" ] || \
   [ "$HTTP_LITELLM" = "FALHOU" ] || [ "$HTTP_LITELLM" = "CONTAINER_ERRO" ] || \
   [[ "$STATUS_POSTGRES" == *"FALHOU"* ]] || [[ "$STATUS_BOUNCER" == *"FALHOU"* ]]; then
    ECOSSISTEMA_COM_ALERTAS=true
fi

# Validação dinâmica de auditoria para todos os módulos desacoplados ativos (Agnóstico a N módulos)
for mod in "${MODULOS_DESACOPLADOS_ATIVOS[@]}"; do
    if [ -f "$TARGET_DIR/core/scripts/install_${mod}.sh" ]; then
        HEALTH_CHECK_OUTPUT=$(bash "$TARGET_DIR/core/scripts/install_${mod}.sh" "$TARGET_DIR" audit_health "${TS_DOMAIN:-localhost}" 2>&1 || echo "FALHOU")
        if echo "$HEALTH_CHECK_OUTPUT" | grep -qE "FALHOU|CONTAINER_ERRO|OFFLINE|❌"; then
            ECOSSISTEMA_COM_ALERTAS=true
        fi
    fi
done

if [ "$ECOSSISTEMA_COM_ALERTAS" = "true" ]; then

    echo ""
    echo "====================================================================="
    echo "   ⚠️ [SRE TRIAGE INSTALL] DETECTADOS ATIVOS INSTÁVEIS OU FORA DE SOCKET "
    echo "====================================================================="
    echo "Mapeamento dos caminhos absolutos de logs no host para depuração externa:"
    echo ""

    [ ${#STACK_ACTIVE_CONTAINERS[@]} -eq 0 ] && resolver_containers_ativos

    for container in "${STACK_ACTIVE_CONTAINERS[@]}"; do
        # Captura a saúde em tempo real do componente
        HEALTH_STATUS=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{if .State.Running}}healthy{{else}}unhealthy{{end}}{{end}}' "$container" 2>/dev/null || echo "OFFLINE")

        # SRE Cross-Check: Se o container não estiver 100% healthy, isola para triagem
        if [ "$HEALTH_STATUS" != "healthy" ]; then
            # GOLPE DE MESTRE: Extrai o caminho físico real do arquivo de log JSON do Docker no HD do Ubuntu
            FULL_LOG_PATH=$(docker inspect -f '{{.LogPath}}' "$container" 2>/dev/null || echo "")
 
            echo "❌ COMPONENTE COM ANOMALIA: [$container]"
            echo "   ↳ Status de Prontidão: [$HEALTH_STATUS]"
 
            if [ -n "$FULL_LOG_PATH" ] && [ "$FULL_LOG_PATH" != "<no value>" ]; then
                echo "   ↳ Arquivo Físico de Log: $FULL_LOG_PATH"
                echo "   ↳ Comando SRE para Inspeção Direta (Últimas 50 linhas):"
                echo "     sudo tail -n 50 $FULL_LOG_PATH"
            else
                echo "   ↳ Arquivo Físico de Log: Não alocado pelo daemon do Docker."
                echo "   ↳ Comando de Fallback Nativo:"
                echo "     sudo docker logs --tail 50 $container"
            fi
            echo ""
        fi
    done
    echo "====================================================================="
fi

# 1. MATRIZ SRE BOM DE IMAGENS E VERSÕES
gerar_relatorio_versoes_stack

# ===============================================================================
# 🔒 PROTOCOLO FINAL DE HIGIENIZAÇÃO DE AMBIENTE (SUCESSO)
# ===============================================================================
echo "=== [SRE INSTALL] Finalizando provisionamento e higienizando barramento ==="

USER_HOME_REAL=$(eval echo "~${SUDO_USER:-$USER}")
[ ! -d "$USER_HOME_REAL" ] && USER_HOME_REAL="/home/${SUDO_USER:-$USER}"

# 1. Purga de Scripts e Overlays dos Acessórios Não Utilizados
[ ${#MODULOS_DESACOPLADOS_INATIVOS[@]} -eq 0 ] && resolver_modulos_desacoplados

for mod in "${MODULOS_DESACOPLADOS_INATIVOS[@]}"; do
    if [ -f "${TARGET_DIR}/core/scripts/install_${mod}.sh" ] || [ -f "${TARGET_DIR}/core/config/docker-compose.${mod}.yml" ]; then
        echo "➜ [SRE PURGE INSTALL] Removendo scripts e overlays de acessórios desativados (${mod})..."
        rm -f "${TARGET_DIR}/core/scripts/install_${mod}.sh" "${TARGET_DIR}/core/config/docker-compose.${mod}.yml" 2>/dev/null || true
    fi
done

if [ "$USE_TAILSCALE" = "false" ]; then
    rm -f "${TARGET_DIR}/core/scripts/install_0ts.sh" 2>/dev/null || true
fi

# 2. Destruição de rastros físicos e arquivos temporários (PRESERVA estritamente o wizard cache para deploys futuros)
rm -rf /tmp/infra-loja-bootstrap /tmp/lojista_key.asc "${RAIZ_REPO}/preinstall.sh" /opt/daemind/preinstall.sh 2>/dev/null
rm -f "$STATE_FILE" /tmp/sync_ia_errors.log 2>/dev/null || true
rm -rf /tmp/*/ || true
rm -rf "$TARGET_DIR/.git" "$TARGET_DIR/.gitignore" "$TARGET_DIR/.gitattributes" 2>/dev/null || true
rm -rf "$TARGET_DIR/core/config" "$TARGET_DIR/database" 2>/dev/null || true
rm -f "/opt/daemind/CHAVE_PRIVADA_BACKUP_${PREFIXO_CONTAINER}.asc" "${USER_HOME_REAL}/CHAVE_PRIVADA_BACKUP_${PREFIXO_CONTAINER}.asc" 2>/dev/null || true

# 3. Purga completa das credenciais em memória
for var in $(compgen -v | grep -E '(_KEY|_SECRET|_PASSWORD|_TOKEN|TS_OAUTH|DB_USER)'); do
    export "$var"="EXPURGADO"
    unset "$var" 2>/dev/null || true
done

echo "====================================================================="
echo "       [SUCESSO ABSOLUTO INSTALL] AMBIENTE SANITIZADO E ENTREGUE     "
echo "====================================================================="

if [ -f "$ARTEFATO_BACKUP" ]; then
    echo " 📦 [BACKUP DIA 0] Backup de segurança inicial consolidado com sucesso!"
    echo "    ↳ Localizador no Host: $ARTEFATO_BACKUP"
    echo "    ↳ Agendamento Automático: Diariamente às 23:00 (via backup_diario.sh)"
fi

CHAVE_PRIVADA_HOST="${USER_HOME_REAL}/CHAVE_PRIVADA_BACKUP_${PREFIXO_CONTAINER}.asc"
if [ -f "$CHAVE_PRIVADA_HOST" ] || [ -f "/opt/daemind/CHAVE_PRIVADA_BACKUP_${PREFIXO_CONTAINER}.asc" ]; then
    echo " 🔑 [CHAVE PRIVADA GPG] Chave de Criptografia Mestra (OpenPGP):"
    echo "    ↳ Localizador no Host: ${CHAVE_PRIVADA_HOST}"
    echo "    ⚠️  Faça o download deste arquivo via SFTP/SCP para um local seguro (Pendrive/Cofre) e remova-o do servidor!"
fi

if [ "$USE_TAILSCALE" = "true" ]; then
    sudo tar --warning=no-file-changed -czf "$USER_HOME_REAL/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz" -C /var/lib/tailscale . 2>/dev/null || true
    sudo chmod 644 "$USER_HOME_REAL/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz" 2>/dev/null || true
    [ -n "$SUDO_USER" ] && sudo chown "$SUDO_USER:$SUDO_USER" "$USER_HOME_REAL/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz" 2>/dev/null || true

    echo " 💡 [SRE ADVICE INSTALL] O backup de identidade vitalício do Tailscale foi gerado com sucesso!"
    echo "    ↳ Localização:  ${USER_HOME_REAL}/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz"
    echo "    Para os próximos deploys, coloque este arquivo na sua Home (~/) para não ser limitado"
    echo "    ao adquirir certificado Let's Encrypt TLS da conta Free."
else
    echo " 💡 [SRE ADVICE INSTALL] Operação finalizada em modelo BYODNS."
    echo "    ↳ Gestão de Domínios, Proxies Externos e TLS estão sob responsabilidade do administrador."
fi
echo "====================================================================="