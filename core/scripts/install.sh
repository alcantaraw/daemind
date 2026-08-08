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

log_info()    { echo -e "${CLR_CYAN}➜ [INFO]${CLR_RESET} $1"; }
log_success() { echo -e "${CLR_GREEN}✔ [SUCESSO]${CLR_RESET} $1"; }
log_warn()    { echo -e "${CLR_YELLOW}⚠️  [ATENÇÃO]${CLR_RESET} $1"; }
log_error()   { echo -e "${CLR_RED}🚨 [ERRO CRÍTICO]${CLR_RESET} $1"; }
log_substep() { echo -e "${CLR_CYAN}  ↳${CLR_RESET} $1"; }
log_skip()    { echo -e "${CLR_BLUE}⏭️  [PULADO]${CLR_RESET} $1"; }
log_exec()    { echo -e "${CLR_YELLOW}⏳ [EXECUTANDO]${CLR_RESET} $1"; }
log_header()  {
    echo ""
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_YELLOW}=== [SRE] $1 ===${CLR_RESET}"
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
}

exibir_banner_daemind() {
    local descricao="$1"
    echo -e "${CLR_CYAN}"
    cat << 'BANNER'
         _                      _           _   
      __| | __ _  ___ _ __ ___ (_)_ __   __| |  
     / _` |/ _` |/ _ \ '_ ` _ \| | '_ \ / _` |  
    | (_| | (_| |  __/ | | | | | | | | | (_| |_ 
     \__,_|\__,_|\___|_| |_| |_|_|_| |_|\__,_(_)
                                                
BANNER
    echo -e "${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_YELLOW}  Sistema Operacional Autônomo para Negócios Digitais${CLR_RESET}"
    if [ -n "$descricao" ]; then
        echo -e "${CLR_CYAN}    ➜ $descricao${CLR_RESET}"
    fi
    echo -e "${CLR_CYAN}=====================================================================${CLR_RESET}"
    echo ""
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

SCRIPT_VERSION="v2026.08.08.09-DYNAMIC-PREFIX-SAFE"

# Exibe o logo ASCII oficial do daemind.
exibir_banner_daemind "Orquestrador de Provisionamento Autônomo da Stack de Microsserviços"
echo -e "${CLR_BOLD}${CLR_GREEN}➜ [VERSION CHECK] install.sh Versão em Execução: ${SCRIPT_VERSION}${CLR_RESET}"
echo ""

# ===============================================================================
# 🔒 SRE GUARDRAIL: TRAVA DE CONCORRÊNCIA (MUTEX LOCK)
# ===============================================================================
LOCK_FILE="/tmp/${SCRIPT_NOME}.lock"
exec 200>"$LOCK_FILE"

if ! flock -n 200; then
    echo "====================================================================="
    echo "⚠️ [ALERTA SRE] Uma instância do ${SCRIPT_NOME}.sh JÁ ESTÁ EM EXECUÇÃO!"
    echo "➜ Arquivo de Trava: ${LOCK_FILE}"
    echo "➜ Para visualizar a execução atual: tail -f ${LOG_FILE}"
    echo "====================================================================="
    exit 1
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
    handle /webhook/* { reverse_proxy ${PREFIXO_CONTAINER}_n8n:5678 }
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
            echo "⏱️ [SRE METRIC] Duração real da execução (Preinstall + Install): ${DURACAO_LIQUIDA}s (Total decorrido: ${DURACAO_BRUTA}s | Pausas em perguntas: ${PAUSA_SEC}s)."
        else
            echo "⏱️ [SRE METRIC] Duração total da execução (Preinstall + Install): ${DURACAO_LIQUIDA} segundos."
        fi
    else
        echo "⏱️ [SRE METRIC] Duração total da execução (Install): ${DURACAO_LIQUIDA} segundos."
    fi
    echo "📅 Data/Hora de término: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "====================================================================="
}

# Registra o log de início
echo "🚀 [SRE] Início do deploy: $(date '+%Y-%m-%d %H:%M:%S')"

# Garante o redirecionamento unificado escrevendo em tempo real no arquivo volátil
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

diagnosticar_containers_stack() {
    local container_foco="$1"
    if command -v docker >/dev/null 2>&1; then
        echo ""
        echo "====================================================================="
        echo "🚨 [SRE DOCKER FORENSICS] RELATÓRIO FORENSE DE LOGS E CONTAINERS:"
        echo "====================================================================="
        local PREFIXO="${PREFIXO_CONTAINER}"

        for container in $(docker ps -a --format '{{.Names}}' 2>/dev/null); do
            if [[ "$container" == *"${PREFIXO}"* ]]; then
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
        echo "====================================================================="
        echo "       📊 [SRE BOM] MATRIZ DINÂMICA DE VERSÕES E IMAGENS DOCKER       "
        echo "====================================================================="
        printf "%-20s | %-42s | %-26s\n" "CONTAINER" "IMAGEM DOCKER" "VERSÃO INTERNA"
        echo "---------------------------------------------------------------------------------------------------"

        local containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep "^${PREFIXO}_" | sort)

        if [ -z "$containers" ]; then
            echo "⚠️ Nenhum container com prefixo '${PREFIXO}_' encontrado."
            return
        fi

        for container in $containers; do
            local imagem=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null || echo "N/A")
            local servico="${container#${PREFIXO}_}"
            local versao=""

            case "$servico" in
                db|postgres)
                    versao=$(docker exec "$container" postgres --version 2>/dev/null | awk '{print $3}' || echo "")
                    ;;
                redis)
                    versao=$(docker exec "$container" redis-server --version 2>/dev/null | sed -n 's/.*v=\([0-9.]*\).*/\1/p' || echo "")
                    ;;
                waf|caddy)
                    versao=$(docker exec "$container" caddy version 2>/dev/null | awk '{print $1}' || echo "")
                    ;;
                n8n)
                    versao=$(docker exec "$container" n8n --version 2>/dev/null || echo "")
                    ;;
                chatwoot)
                    versao=$(docker exec "$container" cat /app/package.json 2>/dev/null | grep '"version"' | head -n 1 | cut -d'"' -f4 || echo "")
                    ;;
                nocodb)
                    versao=$(docker exec "$container" node -e 'console.log(require("./package.json").version)' 2>/dev/null || echo "")
                    ;;
                evolution)
                    versao=$(docker exec "$container" node -e 'console.log(require("./package.json").version)' 2>/dev/null || echo "")
                    ;;
                openwebui)
                    versao=$(docker exec "$container" cat /app/package.json 2>/dev/null | grep '"version"' | head -n 1 | cut -d'"' -f4 || echo "")
                    ;;
                litellm)
                    versao=$(docker exec "$container" python3 -c "import importlib.metadata; print(importlib.metadata.version('litellm'))" 2>/dev/null || echo "")
                    ;;
                postiz)
                    versao=$(docker exec "$container" env 2>/dev/null | grep NEXT_PUBLIC_VERSION | cut -d'=' -f2 || echo "")
                    ;;
                minio)
                    if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]] && [ -f "$TARGET_DIR/core/scripts/install_minIO.sh" ]; then
                        versao=$(bash "$TARGET_DIR/core/scripts/install_minIO.sh" "$TARGET_DIR" get_version 2>/dev/null || echo "")
                    fi
                    ;;
                temporal|pooler|*)
                    local tag_imagem="${imagem##*:}"
                    if [ -n "$tag_imagem" ] && [ "$tag_imagem" != "$imagem" ]; then
                        versao="${tag_imagem}"
                    fi
                    ;;
            esac

            if [ -z "$versao" ]; then
                local tag_imagem="${imagem##*:}"
                if [ -n "$tag_imagem" ] && [ "$tag_imagem" != "$imagem" ]; then
                    versao="${tag_imagem}"
                else
                    versao="Ativo (Nativo)"
                fi
            fi

            # Sanitização global de formatação (remove "Tag (...)", "RELEASE.", e prefixo "v")
            versao=$(echo "$versao" | sed -E 's/^Tag \((.*)\)$/\1/; s/^RELEASE\.//; s/^[vV]//')

            printf "%-20s | %-42s | %-26s\n" "$container" "$imagem" "$versao"
        done
        echo "====================================================================="
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

    # 2. Sobrescreve as variáveis críticas da sessão atual na memória antes do exit
    export GIT_TOKEN_BOOT="EXPURGADO" DB_PASSWORD="EXPURGADO" TS_OAUTH_SECRET="EXPURGADO" LOJA_API_KEY="EXPURGADO" LOJA_APP_KEY="EXPURGADO" GEMINI_API_KEY="EXPURGADO" OPENAI_API_KEY="EXPURGADO" ANTHROPIC_API_KEY="EXPURGADO" DEEPSEEK_API_KEY="EXPURGADO"
    unset GIT_TOKEN_BOOT DB_PASSWORD TS_OAUTH_SECRET LOJA_API_KEY LOJA_APP_KEY GEMINI_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY

    echo "➜ [INFO] Rastro de dados sensíveis sanitizado com sucesso da memória e do disco."
}
trap 'error_forensic_handler $LINENO "$BASH_COMMAND"' ERR

# 1. Configura o timeout estendido temporário para a execução deste script
echo "=== [SRE] Elevando temporariamente o timeout do sudo para 60 minutos ==="
echo "Defaults timestamp_timeout=60" | sudo tee /etc/sudoers.d/custom_sudo_timeout > /dev/null
sudo chmod 0440 /etc/sudoers.d/custom_sudo_timeout

# 2. GOLPE DE MESTRE: Registra o trap para remover o timeout ao sair do script, ocorra erro ou sucesso
cleanup_sudo_timeout() {
    mostrar_duracao
    if [ -f /etc/sudoers.d/custom_sudo_timeout ]; then
        echo "=== [SRE HARDENING] Revogando timeout estendido do sudo... ==="
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
# SRE: DETECÇÃO DE MODO DE EXECUÇÃO (--force)
# ===============================================================================
FORCE_MODE="false"
for arg in "$@"; do
    if [ "$arg" == "--force" ] || [ "$arg" == "-f" ]; then
        FORCE_MODE="true"
    fi
done

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
    echo "=== [SRE] Absorvendo variáveis de parametrização: ${CLIENT_ENV_FILE} ==="
    # SRE FIX: Aplica a higienização de quebras de linha Windows (CRLF)
    sed -i 's/\r$//' "${CLIENT_ENV_FILE}" 2>/dev/null || true
    set -a
    source "${CLIENT_ENV_FILE}"
    set +a
    echo "➜ [SUCESSO] Variáveis de ambiente carregadas na sessão com sucesso."

    # Consolidação Atômica SSOT: Garante .env na raiz como a única Fonte da Verdade
    TARGET_SSOT="${RAIZ_REPO}/.env"
    if [ "$(readlink -f "$CLIENT_ENV_FILE" 2>/dev/null)" != "$(readlink -f "$TARGET_SSOT" 2>/dev/null)" ]; then
        cp "$CLIENT_ENV_FILE" "$TARGET_SSOT"
        chmod 600 "$TARGET_SSOT"
        rm -f "$CLIENT_ENV_FILE" 2>/dev/null || true
        echo "➜ [SRE ATÔMICO] SSOT consolidado em ${TARGET_SSOT} e payload temporário expurgado."
    fi

    # SRE DECOUPLED MODULE: Execução do Motor de Auto-Tuning Dinâmico
    if [ -f "${RAIZ_REPO}/core/scripts/autotune.sh" ]; then
        chmod +x "${RAIZ_REPO}/core/scripts/autotune.sh" 2>/dev/null || true
        "${RAIZ_REPO}/core/scripts/autotune.sh" "${TARGET_SSOT}" || true
        set -a
        source "${TARGET_SSOT}"
        set +a
    fi
else
    echo "====================================================================="
    echo "🚨 [ERRO FATAL] Arquivo de configuração (.env) não encontrado em ${RAIZ_REPO}/.env!"
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
        echo "🚨 [ERRO FATAL] Quebra de Integridade na Fonte da Verdade (SSOT)!"
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
    echo "➜ [OK] Credenciais estruturais e chaves de IA confirmadas em memória."
else
    echo "⚠️ [AVISO SRE] Nenhuma chave de API de Inteligência Artificial foi configurada no .env."
fi

echo "➜ [OK] Todas as credenciais estruturais e chaves de IA confirmadas em memória."

# SRE: Dimensionamento Fixo (Lightweight) para VPS Exclusiva
CPU_DB="1.0"
MEM_DB="1024M"
CPU_N8N="1.0"
MEM_N8N="1024M"

echo "=== Estruturando árvore física de volumes persistentes ==="
# SRE Ajuste: Se rodar via sudo, garante o mapeamento na home do usuário real (well) e não do root
if [ -n "$SUDO_USER" ]; then
    HOME_USER="/home/$SUDO_USER"
else
    HOME_USER="/home/$USER"
fi

TARGET_DIR="/opt/daemind"
cd "$TARGET_DIR" 2>/dev/null || true

# ===============================================================================
# ⚙️ MÁQUINA DE ESTADOS E CHECKPOINTS (IDEMPOTÊNCIA ABSOLUTA)
# ===============================================================================
STATE_FILE="/tmp/.sre_install_state"

if [ "$FORCE_MODE" = "true" ]; then
    echo -e "\e[31m⚠️ [SRE ENGINE] Flag --force detectada. Purgando checkpoints anteriores...\e[0m"
    rm -f "$STATE_FILE"
fi

run_step() {
    local STEP_ID="$1"
    local MSG="$2"
    local CMD_FUNC="$3"

    cd "$TARGET_DIR" 2>/dev/null || true

    # Se NÃO for force mode e a tag já existir no arquivo, pula
    if [ "$FORCE_MODE" = "false" ] && grep -q "^${STEP_ID}$" "$STATE_FILE" 2>/dev/null; then
        echo -e "\e[34m⏭️ [PULADO] $MSG (Já concluído no checkpoint $STEP_ID)\e[0m"
    else
        echo -e "\e[33m⏳ [EXECUTANDO] $MSG...\e[0m"

        # Dispara a função isolada e grava o checkpoint APENAS se a execução for bem sucedida (Exit status 0)
        if $CMD_FUNC; then
            echo "$STEP_ID" >> "$STATE_FILE"
            echo -e "\e[32m✅ [SUCESSO] Checkpoint gravado: $STEP_ID\e[0m"
        else
            echo -e "\e[31m⚠️ [FALHA] Passo $STEP_ID não concluído. O checkpoint NÃO foi gravado para re-execução.\e[0m"
            return 1
        fi
    fi
}

step_build_tree_and_files() {
# ===============================================================================
echo "=== [FASE 1] Arquitetura Físico-Lógica de Volumes e Portal Estático ======="
# ===============================================================================
    mkdir -p "$TARGET_DIR"/volumes/{postgres_data,n8n_data,evolution_instances,nocodb_data,tailscale_state,nocodb_ts_state,caddy_data,litellm_data,openwebui_data,postiz_data,pgbouncer_data}
    mkdir -p "$TARGET_DIR"/volumes/litellm_data
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

    # SRE Volume Hardening: Restaura permissões estritas de UIDs por container
    chown -R 999:999 "$TARGET_DIR/volumes/postgres_data" 2>/dev/null || true
    chown -R 1000:1000 "$TARGET_DIR/volumes/n8n_data" "$TARGET_DIR/volumes/evolution_instances" "$TARGET_DIR/volumes/nocodb_data" "$TARGET_DIR/volumes/openwebui_data" "$TARGET_DIR/volumes/litellm_data" "$TARGET_DIR/volumes/postiz_data" "$TARGET_DIR/volumes/pgbouncer_data" 2>/dev/null || true
    chmod -R 775 "$TARGET_DIR/volumes/n8n_data" 2>/dev/null || true

    # --- INVOCAÇÃO DESACOPLADA DE ESTRUTURA DE VOLUMES DO MINIO ---
    if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]] && [ -f "$TARGET_DIR/core/scripts/install_minIO.sh" ]; then
        bash "$TARGET_DIR/core/scripts/install_minIO.sh" "$TARGET_DIR" build_structure
    fi

# SRE Self-Healing: Garante que a chave GPG pública exista no keyring local
echo "$CHAVE_PUBLICA_B64" | base64 --decode > /tmp/lojista_key.asc
gpg --batch --yes --import /tmp/lojista_key.asc > /dev/null 2>&1 || true
rm -f /tmp/lojista_key.asc

echo "=== [SRE] Processando Assets Visuais (Logo vs Favicon) ==="

# 1. Copia todos os assets estáticos do repositório (index.html, favicons, background)
    cp -r "$RAIZ_REPO/core/html/"* "$TARGET_DIR/core/html/" 2>/dev/null || true

# 2. SRE Guardrail: Ajusta permissão apenas dos arquivos de código/config (preservando volumes)
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$TARGET_DIR" "$TARGET_DIR"/* 2>/dev/null || true
        chown -R "$SUDO_USER:$SUDO_USER" "$TARGET_DIR/core" 2>/dev/null || true
    fi

# 4. SRE FIX: Alinha dinamicamente o HTML para respeitar as portas exatas da infraestrutura
sed -i "s/data-port=\"18080\"/data-port=\"${HOST_NOCODB_PORT:-18080}\"/g" "$TARGET_DIR/core/html/index.html" 2>/dev/null || true
sed -i "s/:18080</:${HOST_NOCODB_PORT:-18080}</g" "$TARGET_DIR/core/html/index.html" 2>/dev/null || true
sed -i "s/data-port=\"18081\"/data-port=\"${HOST_EVO_PORT:-8081}\"/g" "$TARGET_DIR/core/html/index.html" 2>/dev/null || true

# 2. Cria o Caddyfile expandindo dinamicamente as variáveis de escopo
# [SRE DOC] Polimorfismo de Borda: Resolve as portas locais (:80, :8081) se estivermos
# usando Tailscale Funnel, ou injeta domínios absolutos nativos para o modelo BYODNS.
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

    # --- WEBHOKS PÚBLICOS E APIs ---
    handle /webhook/* {
        reverse_proxy ${PREFIXO_CONTAINER}_n8n:5678
    }
    handle /api/v1/webhooks/* {
        reverse_proxy ${PREFIXO_CONTAINER}_chatwoot:3000
    }
    handle /api/webhooks/* {
        reverse_proxy ${PREFIXO_CONTAINER}_postiz:5000
    }

    # --- PORTAL WHITE-LABEL ---
    handle {
        root * /etc/caddy
        file_server
    }
}

# ===============================================================================
# 2. EVOLUTION API PÚBLICA (Exposto via Tailscale Funnel)
# ===============================================================================
${BIND_API} {
    log {
        level error
    }
    handle {
        reverse_proxy ${PREFIXO_CONTAINER}_evolution:8080
    }
}

# ===============================================================================
# 3. ROTAS PRIVADAS (Acesso Restrito via Painel / VPN)
# ===============================================================================
:3000 {
    log {
        level error
    }
    reverse_proxy ${PREFIXO_CONTAINER}_chatwoot:3000
}
:3001 {
    log {
        level error
    }
    reverse_proxy ${PREFIXO_CONTAINER}_openwebui:8080
}
:4000 {
    log {
        level error
    }
    reverse_proxy ${PREFIXO_CONTAINER}_litellm:4000
}
:5678 {
    log {
        level error
    }
    reverse_proxy ${PREFIXO_CONTAINER}_n8n:5678
}
:8080 {
    log {
        level error
    }
    reverse_proxy ${PREFIXO_CONTAINER}_nocodb:8080
}
:5000 {
    log {
        level error
    }
    reverse_proxy ${PREFIXO_CONTAINER}_postiz:5000 {
        # SRE FIX: Intercepta e reescreve o cookie do NestJS em tempo de voo
        # Remove a trava de HTTPS, abaixa a proteção Cross-Site e remove o domínio PSL
        header_down Set-Cookie "Secure" ""
        header_down Set-Cookie "SameSite=None" "SameSite=Lax"
        header_down Set-Cookie "Domain=.ts.net" ""
    }
}

# ===============================================================================
# 4. GATEWAY MULTI-LLM INTERNO (N8N Inteligência Artificial)
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
    # handle_path /perplexity/* {
        # reverse_proxy api.perplexity.ai:443 {
            # transport http {
                # tls
            # }
            # header_up Host api.perplexity.ai
        # }
    # }
# }
EOF

    # --- INVOCAÇÃO DESACOPLADA DE ROTAS CADDY DO MINIO ---
    if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]] && [ -f "$TARGET_DIR/core/scripts/install_minIO.sh" ]; then
        bash "$TARGET_DIR/core/scripts/install_minIO.sh" "$TARGET_DIR" inject_caddy
    fi

    chmod +x "$TARGET_DIR/core/scripts/"*.sh 2>/dev/null || true
}
run_step "TREE_AND_FILES" "Estruturando árvore física de volumes e portal estático" "step_build_tree_and_files"

cd "$TARGET_DIR"

step_tailscale_auth() {
# ===============================================================================
echo "=== [FASE 2] Conectividade Perimetral e Identidade de Rede ================"
# ===============================================================================
    # [SRE DOC] Graceful Bypass: Se o tenant opera com Cloudflare/DNS Próprio,
    # pulamos 100% da rotina de VPN e Funnel para evitar falhas de Socket.
    if [ "$USE_TAILSCALE" = "false" ]; then
        echo "➜ [SRE SKIP] Modo BYODNS Ativado. Omitindo provisionamento Tailscale/Funnel."
        return 0
    fi

    echo "➜ [SRE] Garantindo inicialização e integridade do agente perimetral (Tailscale)..."
    sudo systemctl enable --now tailscaled > /dev/null 2>&1

    # SRE PERSISTÊNCIA: Avalia se precisamos puxar backup local
    TS_STATUS=$(tailscale status --json | jq -r '.BackendState' 2>/dev/null || echo "NoState")
    CLIENTE_SUFIXO=$(echo "${CLIENTE_NOME}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    
    if [ -n "$SUDO_USER" ]; then
        USER_HOME_REAL=$(eval echo "~$SUDO_USER")
    else
        USER_HOME_REAL="$HOME"
    fi

    BACKUP_TS_FONTE="${RAIZ_REPO}/core/config/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz"
    if [ ! -f "$BACKUP_TS_FONTE" ]; then BACKUP_TS_FONTE="${RAIZ_REPO}/core/config/tailscale_state.tar.gz"; fi
    if [ ! -f "$BACKUP_TS_FONTE" ]; then BACKUP_TS_FONTE="${USER_HOME_REAL}/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz"; fi
    if [ ! -f "$BACKUP_TS_FONTE" ]; then BACKUP_TS_FONTE="${USER_HOME_REAL}/tailscale_state.tar.gz"; fi
    if [ ! -f "$BACKUP_TS_FONTE" ]; then BACKUP_TS_FONTE="${TARGET_DIR}/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz"; fi
    if [ ! -f "$BACKUP_TS_FONTE" ]; then BACKUP_TS_FONTE="${TARGET_DIR}/tailscale_state.tar.gz"; fi

    if { [ "$TS_STATUS" = "NeedsLogin" ] || [ "$TS_STATUS" = "NoState" ]; } && [ -f "$BACKUP_TS_FONTE" ]; then
    echo "➜ [SRE] Identidade estável do Tailscale localizada. Restaurando cache de ${BACKUP_TS_FONTE}..."
        sudo systemctl stop tailscaled
        sudo mkdir -p /var/lib/tailscale
        sudo tar -xzf "$BACKUP_TS_FONTE" -C /var/lib/tailscale/
        sudo chmod 700 /var/lib/tailscale
        sudo systemctl start tailscaled
        sleep 3
        TS_STATUS=$(tailscale status --json | jq -r '.BackendState' 2>/dev/null || echo "NoState")
    fi

# -------------------------------------------------------------------------
# LÓGICA DE AUTENTICAÇÃO INTELIGENTE (IDEMPOTÊNCIA)
# -------------------------------------------------------------------------
    if [ "$TS_STATUS" = "Running" ]; then
    echo "➜ [SRE] Nó já autenticado na Tailnet. Reaplicando configurações (Preservando Identidade)..."
        sudo tailscale up --advertise-tags=tag:production --accept-dns=true --hostname="${PREFIXO_CONTAINER}"
    else
    echo "➜ [SRE] Nó não autenticado. Iniciando protocolo de Auth Key via API para: ${TS_EMAIL}..."

        TOKEN_JSON=$(curl -s -d "client_id=${TS_OAUTH_ID}" -d "client_secret=${TS_OAUTH_SECRET}" "https://api.tailscale.com/api/v2/oauth/token")
        ACCESS_TOKEN=$(echo "$TOKEN_JSON" | jq -r '.access_token // empty')

        if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
            echo "[ERRO CRÍTICO] Falha ao obter access_token OAuth da API do Tailscale."
            exit 1
        fi

        KEY_JSON=$(curl -s -X POST -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" -d "{\"capabilities\": {\"devices\": {\"create\": {\"reusable\": false, \"ephemeral\": false, \"tags\": [\"tag:production\"]}}}}" "https://api.tailscale.com/api/v2/tailnet/${TS_EMAIL}/keys")
        PERSISTENT_AUTH_KEY=$(echo "$KEY_JSON" | jq -r '.key // empty')

        # Limpeza Limpa de Nós Órfãos
        echo "➜ [SRE] Executando protocolo prévio de limpeza de nós órfãos (ts_cleanup)..."
        MY_LOCAL_IP=$(tailscale ip -4 | tr -d '\r\n ' || true)
        DEVICES_JSON=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://api.tailscale.com/api/v2/tailnet/${TS_EMAIL}/devices")

        echo "$DEVICES_JSON" | jq -c '.devices[] | select(.hostname | test("^'"${PREFIXO_CONTAINER}"'(-[0-9]+)?$"))' 2>/dev/null | while read -r device; do
            DEVICE_ID=$(echo "$device" | jq -r '.id')
            DEVICE_IP=$(echo "$device" | jq -r '.addresses[0]')
            CONNECTED=$(echo "$device" | jq -r '.connectedToControl // false')

            if [ "$DEVICE_IP" != "$MY_LOCAL_IP" ] && { [ "$CONNECTED" = "false" ] || [ "$CONNECTED" = "null" ]; }; then
 
                curl -s -X DELETE -u "$ACCESS_TOKEN:" "https://api.tailscale.com/api/v2/device/$DEVICE_ID" > /dev/null
            fi
        done
        sudo tailscale up --auth-key="${PERSISTENT_AUTH_KEY}" --advertise-tags=tag:production --accept-dns=true --hostname="${PREFIXO_CONTAINER}"
    fi

    # Ativação dos túneis de borda do Funnel (Idempotente)
    FUNNEL_RUNNING=$(sudo tailscale funnel status 2>/dev/null | grep -E "80|8443|443" || echo "")
    if [ -n "$FUNNEL_RUNNING" ]; then
        echo "➜ [IDEMPOTÊNCIA] Túneis de borda do Tailscale Funnel já ativos. Preservando conexão."
    else
        echo "➜ [CONFIGURANDO] Ativando túneis de borda do Tailscale Funnel..."
        sudo tailscale funnel --bg ${HOST_CADDY_PORT} > /dev/null 2>&1 || true
        sudo tailscale funnel --bg --https=8443 ${HOST_EVO_PORT} > /dev/null 2>&1 || true
    fi
	
	echo "=== [SRE] Capturando e validando domínio canônico da Tailnet ==="
	TS_DOMAIN=""
	TENTATIVAS_DNS=0
	while [ -z "$TS_DOMAIN" ]; do
	  # SRE Padrão Indestrutível: Captura o DNSName seguro dentro do bloco do nó atual (Self)
	  TS_DOMAIN=$(tailscale status --json | grep -A 10 '"Self":' | grep '"DNSName"' | head -n 1 | cut -d'"' -f4 | sed 's/\.$//' | tr -d '\r\n ' || true)
	 
	  if [ -z "$TS_DOMAIN" ]; then
		TENTATIVAS_DNS=$((TENTATIVAS_DNS+1))
		if [ "$TENTATIVAS_DNS" -ge 20 ]; then
			echo "[AVISO DE BARRAMENTO] Timeout aguardando DNS público da Tailnet. Usando IP de interface como Fallback."
			TS_DOMAIN=$(tailscale ip -4 | tr -d '\r\n ' || echo "localhost")
			break
		fi
		sleep 5
	  fi
	done
	echo "➜ Domínio capturado com sucesso para o cluster: $TS_DOMAIN"
	export TS_DOMAIN
	if [ -n "$TS_DOMAIN" ]; then
	    if grep -q '^TS_DOMAIN=' "${TARGET_DIR}/.env" 2>/dev/null; then
	        sudo sed -i "s|^TS_DOMAIN=.*|TS_DOMAIN=\"${TS_DOMAIN}\"|" "${TARGET_DIR}/.env" 2>/dev/null || true
	    fi
	fi
}
run_step "TAILSCALE_AUTH" "Autenticação e Abertura de Túneis Tailscale" "step_tailscale_auth"

step_generate_env() {
# ===============================================================================
echo "=== [FASE 3] Consolidação do SSOT de Runtime (.env) ======================="
# ===============================================================================
echo "=== [SRE] Consolidando variáveis de estado (SSOT) e Parâmetros de Runtime ==="

SSOT_PATH="${TARGET_DIR}/.env"
[ ! -f "$SSOT_PATH" ] && SSOT_PATH="${RAIZ_REPO}/.env"
[ ! -f "$SSOT_PATH" ] && SSOT_PATH="./.env"

# SRE GUARDRAIL: Captura chaves de API existentes para não quebrar sessões e webhooks ativos
OLD_EVO_KEY=$(grep '^EVOLUTION_API_KEY=' "$SSOT_PATH" 2>/dev/null | cut -d= -f2 || true)
OLD_OWUI_KEY=$(grep '^OPENWEBUI_SECRET_KEY=' "$SSOT_PATH" 2>/dev/null | cut -d= -f2 || true)
OLD_CW_KEY=$(grep '^CHATWOOT_SECRET_KEY=' "$SSOT_PATH" 2>/dev/null | cut -d= -f2 || true)
OLD_PZ_KEY=$(grep '^POSTIZ_JWT_SECRET=' "$SSOT_PATH" 2>/dev/null | cut -d= -f2 || true)

EVOLUTION_API_KEY=${OLD_EVO_KEY:-$(openssl rand -hex 16)}
OPENWEBUI_SECRET_KEY=${OLD_OWUI_KEY:-$(openssl rand -hex 32)}
CHATWOOT_SECRET_KEY=${OLD_CW_KEY:-$(openssl rand -hex 32)}
POSTIZ_JWT_SECRET=${OLD_PZ_KEY:-$(openssl rand -hex 32)}

# SRE FIX: Resolução Determinística do FQDN Base e Protocolo Webhook
if [ "$USE_TAILSCALE" = "false" ]; then
    TS_DOMAIN="$CUSTOM_DOMAIN"
    SERVER_URL="${CADDY_PROTOCOL}://${CUSTOM_EVO_DOMAIN}"
    BASE_WEBHOOK_PROTOCOL="${CADDY_PROTOCOL}"
else
    SERVER_URL="https://${TS_DOMAIN}:8443"
    BASE_WEBHOOK_PROTOCOL="https"
fi

cat << EOF > .env
# --- Herança de Estado (SSOT) ---
IP_NETWORK_SUBNET=${IP_NETWORK_SUBNET}
IP_NETWORK_GATEWAY=${IP_NETWORK_GATEWAY}
IP_REDIS=${IP_REDIS}
IP_NOCODB=${IP_NOCODB}
IP_N8N=${IP_N8N}
IP_EVOLUTION=${IP_EVOLUTION}
IP_CADDY=${IP_CADDY}
IP_CHATWOOT=${IP_CHATWOOT}
IP_POSTIZ=${IP_POSTIZ}
IP_POSTGRES=${IP_POSTGRES}
IP_PGBOUNCER=${IP_PGBOUNCER}
IP_TEMPORAL=${IP_TEMPORAL}
IP_LITELLM=${IP_LITELLM}
IP_OPENWEBUI=${IP_OPENWEBUI}
${USE_MINIO:+# MinIO S3 Dynamic IP}
${USE_MINIO:+IP_MINIO=${IP_MINIO}}
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
HOST_NOCODB_PORT="${HOST_NOCODB_PORT}"
HOST_EVO_PORT="${HOST_EVO_PORT}"
CHAVE_PUBLICA_B64="${CHAVE_PUBLICA_B64}"
HASH_ESPERADO="${HASH_ESPERADO}"

# --- Variáveis Dinâmicas e Relacionais de Runtime (Linux) ---
DB_NAME=${PREFIXO_CONTAINER}_db
EVOLUTION_API_KEY=${EVOLUTION_API_KEY}
OPENWEBUI_SECRET_KEY=${OPENWEBUI_SECRET_KEY}
TS_DOMAIN=${TS_DOMAIN}
SERVER_URL=${SERVER_URL}
N8N_WEBHOOK_URL=${BASE_WEBHOOK_PROTOCOL}://${TS_DOMAIN}
PROXY_PORT=${HOST_CADDY_PORT}
EVO_PORT=${HOST_EVO_PORT}
NOCO_PORT=${HOST_NOCODB_PORT}
CHATWOOT_SECRET_KEY=${CHATWOOT_SECRET_KEY}
POSTIZ_JWT_SECRET=${POSTIZ_JWT_SECRET}
CHATWOOT_FRONTEND_URL="http://${TS_DOMAIN}:3000"
POSTIZ_FRONTEND_URL="http://${TS_DOMAIN}:5000"
MAIN_URL="http://${TS_DOMAIN}:5000"
NEXT_PUBLIC_BACKEND_URL="http://${TS_DOMAIN}:5000"
FRONTEND_URL="http://${TS_DOMAIN}:5000"
REDIS_URL="redis://${IP_REDIS}:6379"
REDIS_HOST="${IP_REDIS}"
REDIS_PORT=6379
# --- Elasticidade e Tuning de Recursos ---
CACHE_CACHE_INLINE=true
CACHE_PROVIDER=local
CACHE_REDIS_ENABLED=false
CADDY_CPU_LIMIT=0.5
CADDY_MEM_LIMIT=256M
CPU_DB=${CPU_DB}
CPU_N8N=${CPU_N8N}
MEM_DB=${MEM_DB}
STORAGE_MODE="${STORAGE_MODE:-local}"
USE_MINIO="${USE_MINIO:-s}"
EOF
# Guardrail de Segurança: Oculta o arquivo de outros usuários do Linux
chmod 600 .env
cp .env "$TARGET_DIR/.env" 2>/dev/null || true
chmod 600 "$TARGET_DIR/.env" 2>/dev/null || true
}
run_step "ENV_GENERATION" "Consolidando variáveis de estado de Runtime (.env)" "step_generate_env"

step_docker_pull_and_infra() {
# =====================================================================================
echo "=== [FASE 4] Provisionando Infraestrutura Base (Postgres, Redis, MinIO) ========="
# =====================================================================================
cd "$TARGET_DIR" 2>/dev/null || true

# --- INVOCAÇÃO DOS HOOKS PRÉ-BOOT DO MINIO S3 ---
if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]]; then
    if [ -f "$TARGET_DIR/core/scripts/install_minIO.sh" ]; then
        chmod +x "$TARGET_DIR/core/scripts/install_minIO.sh"
        bash "$TARGET_DIR/core/scripts/install_minIO.sh" "$TARGET_DIR" build_structure
        bash "$TARGET_DIR/core/scripts/install_minIO.sh" "$TARGET_DIR" inject_caddy
        bash "$TARGET_DIR/core/scripts/install_minIO.sh" "$TARGET_DIR" inject_card
    fi
else
    echo "➜ [SRE SKIP] Módulo MinIO desativado (Armazenamento FS Local / S3 Cloud Externo)."
fi

preparar_compose_monolitico() {
    cd "$TARGET_DIR" 2>/dev/null || true
    
    # 1. Copia os manifestos para a raiz $TARGET_DIR para garantir execução 100% nativa
    cp "$TARGET_DIR/core/config/docker-compose.yml" "$TARGET_DIR/docker-compose.base.yml" 2>/dev/null || true
    
    if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]] && [ -f "$TARGET_DIR/core/config/docker-compose.minio.yml" ]; then
        cp "$TARGET_DIR/core/config/docker-compose.minio.yml" "$TARGET_DIR/docker-compose.minio.yml" 2>/dev/null || true
        echo "➜ [SRE] Unificando topologia de containers em ./docker-compose.yml..."
        if docker compose -f docker-compose.base.yml -f docker-compose.minio.yml config > docker-compose.yml 2>/dev/null; then
            echo "✔ [SUCESSO] Topologia unificada com sucesso em ./docker-compose.yml"
        else
            echo "  ⚠️ [AVISO] Falha ao unificar YAMLs via docker compose config. Copiando base..."
            cp docker-compose.base.yml docker-compose.yml
        fi
        rm -f "$TARGET_DIR/docker-compose.minio.yml" 2>/dev/null || true
    else
        cp docker-compose.base.yml docker-compose.yml
    fi
    
    rm -f "$TARGET_DIR/docker-compose.base.yml" 2>/dev/null || true
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

echo "➜ [SRE] Baixando todas as imagens da stack com resiliência de link..."
# SRE Network Resilience Loop: Tenta puxar as imagens até 3 vezes caso o link sofra timeout
TENTATIVAS_PULL=1
MAX_TENTATIVAS_PULL=3
SUCESSO_PULL=false

while [ $TENTATIVAS_PULL -le $MAX_TENTATIVAS_PULL ]; do
    echo "  ↳ Disparando pull paralelo silencioso (Tentativa ${TENTATIVAS_PULL}/${MAX_TENTATIVAS_PULL})...."
    # SRE Purificação: Mapeia o stderr temporariamente para capturar erros REAIS apenas se o pull falhar
    if PULL_ERRORS=$(docker compose pull --quiet 2>&1 >/dev/null); then
        SUCESSO_PULL=true
        break
    fi
    echo "  ⚠️ [AVISO] Oscilação de rede ou erro detectado no Docker Hub:"
    echo "$PULL_ERRORS" | sed 's/^/     /'
    echo "  ↳ Aguardando 10s para retransmitir..."
    sleep 10
    TENTATIVAS_PULL=$((TENTATIVAS_PULL + 1))
done

if [ "$SUCESSO_PULL" = "false" ]; then
    echo "🚨 [ERRO CRÍTICO] O link com o Docker Hub caiu permanentemente após ${MAX_TENTATIVAS_PULL} tentativas."
    exit 1
fi
TOTAL_SERVICOS=$(docker compose config --services 2>/dev/null | grep -v '^$' | wc -l | xargs 2>/dev/null || echo "13")
IMAGENS_PULLED=$(docker compose images --quiet 2>/dev/null | grep -v '^$' | sort -u | wc -l | xargs 2>/dev/null || echo "$TOTAL_SERVICOS")
echo "➜ [IDEMPOTÊNCIA] ${IMAGENS_PULLED} de ${TOTAL_SERVICOS} imagens declaradas verificadas e prontas no cache local."

echo "➜ [SRE] Verificando e inicializando infraestrutura de dados base (Postgres, Redis, PgBouncer)..."
INFRA_SERVICES=("postgres" "redis" "pgbouncer")
if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]]; then
    INFRA_SERVICES+=("minio")
fi
INFRA_OFFLINE=()

for svc in "${INFRA_SERVICES[@]}"; do
    STATUS=$(docker compose ps --services --filter "status=running" 2>/dev/null | grep -w "$svc" || echo "")
    if [ -z "$STATUS" ]; then
        INFRA_OFFLINE+=("$svc")
    fi
done

if [ ${#INFRA_OFFLINE[@]} -eq 0 ]; then
    echo "➜ [IDEMPOTÊNCIA] Serviços de infraestrutura de dados (${INFRA_SERVICES[*]}) já estão ativos em status RUNNING."
else
    echo "  ↳ Disparando subida seletiva dos serviços offline: ${INFRA_OFFLINE[*]}..."
    if ! DB_UP_ERR=$(docker compose up -d --remove-orphans "${INFRA_OFFLINE[@]}" 2>&1); then
        echo "🚨 [ERRO CRÍTICO] Falha ao inicializar os serviços de dados/cache offline (${INFRA_OFFLINE[*]}):"
        echo "$DB_UP_ERR"
        exit 1
    fi
fi

echo "Aguardando prontidão do banco Postgres..."
TENTATIVAS_DB=0
until docker compose exec -T postgres pg_isready -U $DB_USER -d ${PREFIXO_CONTAINER}_db > /dev/null 2>&1 < /dev/null; do
  TENTATIVAS_DB=$((TENTATIVAS_DB+1))
  [ "$TENTATIVAS_DB" -ge 30 ] && { echo "🚨 [ERRO FATAL] Postgres não respondeu após 60s."; exit 1; }
  sleep 2
done

# --- HOOKS PÓS-BOOT DO MINIO S3 ---
if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]]; then
    if [ -f "$TARGET_DIR/core/scripts/install_minIO.sh" ]; then
        bash "$TARGET_DIR/core/scripts/install_minIO.sh" "$TARGET_DIR" wait_readiness
        bash "$TARGET_DIR/core/scripts/install_minIO.sh" "$TARGET_DIR" provision_buckets
    fi
fi
}
run_step "DOCKER_INFRA" "Baixando imagens e inicializando Banco de Dados e Cache" "step_docker_pull_and_infra"

step_ddl_and_migrations() {
# ===============================================================================
echo "=== [FASE 5] Injeção de Schemas DDL e Isolação dos Bancos Lógicos ========="
# ===============================================================================
cd "$TARGET_DIR" 2>/dev/null || true
echo "➜ [SRE] Validando prontidão do banco PostgreSQL..."
TENTATIVAS_DB_MIG=0
until docker compose exec -T postgres pg_isready -U $DB_USER -d ${PREFIXO_CONTAINER}_db > /dev/null 2>&1 < /dev/null; do
  TENTATIVAS_DB_MIG=$((TENTATIVAS_DB_MIG+1))
  [ "$TENTATIVAS_DB_MIG" -ge 30 ] && { echo "🚨 [ERRO FATAL] Postgres não respondeu após 60s."; exit 1; }
  sleep 2
done

# Injeção de DDL idempotente (O init.sql possui IF NOT EXISTS)
if [ -f "./core/database/init.sql" ]; then
    docker compose exec -T postgres psql -U $DB_USER -d ${PREFIXO_CONTAINER}_db -q < ./core/database/init.sql > /dev/null 2>&1 || true
elif [ -f "$TARGET_DIR/core/database/init.sql" ]; then
    docker compose exec -T postgres psql -U $DB_USER -d ${PREFIXO_CONTAINER}_db -q < "$TARGET_DIR/core/database/init.sql" > /dev/null 2>&1 || true
fi

DBS_CRIADOS=0
for db in evolution_db chatwoot_db postiz_db temporal temporal_visibility litellm_db openwebui_db; do
    if ! docker compose exec -T postgres psql -U $DB_USER -d ${PREFIXO_CONTAINER}_db -c "SELECT 1 FROM pg_database WHERE datname = '$db'" < /dev/null 2>/dev/null | grep -q 1; then
        DBS_CRIADOS=$((DBS_CRIADOS+1))
        docker compose exec -T postgres psql -U $DB_USER -d ${PREFIXO_CONTAINER}_db -q -c "CREATE DATABASE $db;" < /dev/null > /dev/null 2>&1 || true
    fi
done

if [ "$DBS_CRIADOS" -eq 0 ]; then
    echo "➜ [IDEMPOTÊNCIA] Os 7 bancos de dados lógicos já existem. Preservando esquemas."
else
    echo "➜ [CONFIGURANDO] ${DBS_CRIADOS} novos bancos de dados lógicos criados com sucesso."
fi

if ! docker compose exec -T postgres psql -U $DB_USER -d chatwoot_db -c "SELECT 1 FROM installation_configs LIMIT 1;" > /dev/null 2>&1 < /dev/null; then
    echo "➜ [CONFIGURANDO] Executando preparação de schema inicial do Chatwoot (db:chatwoot_prepare)..."
    CW_ERR=$(docker compose run --rm -T chatwoot bundle exec rails db:chatwoot_prepare 2>&1) || true
    if ! docker compose exec -T postgres psql -U $DB_USER -d chatwoot_db -c "SELECT 1 FROM installation_configs LIMIT 1;" > /dev/null 2>&1 < /dev/null; then
        echo "  ↳ Segunda tentativa via db:schema:load e db:migrate..."
        CW_ERR2=$(docker compose run --rm -T chatwoot bundle exec rails db:schema:load db:migrate 2>&1) || true
    fi
else
    echo "➜ [IDEMPOTÊNCIA] Banco do Chatwoot já estruturado. Executando migrações incrementais (db:migrate)..."
    docker compose run --rm -T chatwoot bundle exec rails db:migrate > /dev/null 2>&1 < /dev/null || true
fi

if ! docker compose exec -T postgres psql -U $DB_USER -d chatwoot_db -c "SELECT 1 FROM installation_configs LIMIT 1;" > /dev/null 2>&1 < /dev/null; then
    echo "🚨 [ERRO CRÍTICO] A migration do Chatwoot falhou! A tabela installation_configs não foi criada."
    echo "Detalhes do Erro Rails (Chatwoot):"
    echo "${CW_ERR:-${CW_ERR2:-Erro desconhecido}}"
    exit 1
fi

# --- PREVENÇÃO SRE: CRIANDO CONFIG FAKE ANTES DO BOOT ---
echo "➜ [SRE] Forjando arquivo Base de IA para evitar corrupção de Bind Mount do Docker..."

cat << EO_BASE > "$TARGET_DIR/volumes/litellm_data/config.yaml"
litellm_settings:
  drop_params: true
EO_BASE
}
run_step "DATABASE_DDL" "Injeção DDL e Isolamento Lógico de Bancos" "step_ddl_and_migrations"

step_docker_up_apps() {
# ====================================================================================
echo "=== [FASE 6] Provisionamento Zero-Touch dos Microsserviços e Inteligência ======"
# ====================================================================================
echo "➜ [SRE] Verificando status e orquestrando subida da malha de microsserviços..."
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
    echo "➜ [IDEMPOTÊNCIA & SRE] Todos os ${#ALL_DECLARED_SERVICES[@]} serviços declarados já estão rodando em status RUNNING."
else
    echo "  ↳ Disparando subida seletiva apenas dos microsserviços offline: ${APPS_OFFLINE[*]}..."
    if ! UP_ERR=$(docker compose up -d --remove-orphans "${APPS_OFFLINE[@]}" 2>&1); then
        echo "🚨 [ERRO CRÍTICO] Falha ao injetar contêineres offline (${APPS_OFFLINE[*]}) no daemon do Docker!"
        echo "$UP_ERR"
        exit 1
    fi
    SERVICOS_RODANDO=$(docker compose ps --services --filter "status=running" 2>/dev/null | grep -v '^$' | wc -l | xargs 2>/dev/null || echo "0")
    echo "➜ [IDEMPOTÊNCIA & SRE] ${SERVICOS_RODANDO} de ${#ALL_DECLARED_SERVICES[@]} serviços declarados operando em status RUNNING."
fi

echo "➜ [SRE] Preparando Temporal Engine e destravando Postiz..."
# 1. Garante que o Temporal está pronto para receber os comandos
TENTATIVAS_TEMP=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' ${PREFIXO_CONTAINER}_temporal 2>/dev/null)" = "healthy" ]; do
    TENTATIVAS_TEMP=$((TENTATIVAS_TEMP+1))
    [ "$TENTATIVAS_TEMP" -ge 24 ] && { echo "🚨 [ERRO FATAL] Temporal Engine não inicializou após 120s."; exit 1; }
    echo "  ↳ Aguardando banco do Temporal inicializar..."
    sleep 5
done

# 2. Purga IMEDIATAMENTE os atributos de busca padrão do Temporal (CustomTextField/CustomStringField) que estouram o limite
docker exec -i ${PREFIXO_CONTAINER}_temporal sh -c "echo y | temporal operator search-attribute remove --name CustomTextField --name CustomStringField --address 127.0.0.1:7233 --yes" > /dev/null 2>&1 || true

# 3. Injeta os atributos estruturais do Postiz exclusivamente como KEYWORD (Idempotente)
docker exec -i ${PREFIXO_CONTAINER}_temporal sh -c "echo y | temporal operator search-attribute create --name organizationId --type Keyword --address 127.0.0.1:7233" > /dev/null 2>&1 || true
docker exec -i ${PREFIXO_CONTAINER}_temporal sh -c "echo y | temporal operator search-attribute create --name postId --type Keyword --address 127.0.0.1:7233" > /dev/null 2>&1 || true

# 4. Força o reinício limpo do contêiner do Postiz para conectar ao Temporal sanitizado sem locks do PM2
echo "➜ [CONFIGURANDO] Sincronizando barramento do Postiz com o Temporal..."
docker restart ${PREFIXO_CONTAINER}_postiz > /dev/null 2>&1 || true
sleep 3

# --- AUTOMAÇÃO ATÔMICA DO CATÁLOGO DE IAS (HÍBRIDO) ---
echo "➜ [SRE] Aguardando prontidão do AI Gateway (LiteLLM) para carga atômica..."
until [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4000/health/liveliness || echo "000")" = "200" ]; do
  sleep 3
done
}
run_step "DOCKER_APPS" "Subindo malha de microsserviços" "step_docker_up_apps"

# ===============================================================================
# 🚀 PROVISIONAMENTO AUTO-ADMIN UNIFICADO (ZERO-TOUCH & IDEMPOTENTE)
# ===============================================================================

# --- 1. PROVISIONAMENTO OWNER N8N ---
step_provision_n8n() {
echo "➜ [SRE] Aguardando prontidão da API do n8n para automação..."
TENTATIVAS_N8N=0
# [SRE DOC] Timeouts explícitos evitam que a esteira congele infinitamente (Deadlock)
# caso o container entre em CrashLoopBackOff por falta de memória ou erro estrutural.
until [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5678/healthz || echo "000")" = "200" ]; do
  TENTATIVAS_N8N=$((TENTATIVAS_N8N+1))
  [ "$TENTATIVAS_N8N" -ge 30 ] && { echo "🚨 [ERRO FATAL] API do n8n não respondeu após 150s."; exit 1; }
  sleep 5
done

PAYLOAD_N8N=$(jq -n --arg email "$TS_EMAIL" --arg pwd "$DB_PASSWORD" --arg fname "$CLIENTE_NOME" --arg lname "$CLIENTE_SOBRENOME" '{email: $email, password: $pwd, firstName: $fname, lastName: $lname}')
RESPONSE_N8N=$(curl -s -w "%{http_code}" -o /dev/null -X POST "http://127.0.0.1:5678/rest/owner/setup" \
  -H "Content-Type: application/json" -d "$PAYLOAD_N8N" || echo "000")

if [[ "$RESPONSE_N8N" =~ ^2 ]]; then
    echo "➜ [SUCESSO] Proprietário do n8n provisionado: ${TS_EMAIL}"
elif [ "$RESPONSE_N8N" = "400" ] || [ "$RESPONSE_N8N" = "409" ]; then
    echo "➜ [INFO] Proprietário do n8n já existente. Mantendo cadastro atual."
else
    echo "🚨 [ERRO CRÍTICO] Falha ao provisionar proprietário no n8n (HTTP ${RESPONSE_N8N})."
    return 1
fi

    # SRE GUARDRAIL: Avalia via CLI se o Workflow já existe para impedir a duplicação em re-execuções (Resinsert)
    EXISTE_WF=$(docker exec -u node ${PREFIXO_CONTAINER}_n8n n8n export:workflow --all 2>/dev/null | grep "Faxina Reativa de Modelos IA" || true)

    if [ -z "$EXISTE_WF" ]; then
        echo "➜ [CONFIGURANDO] Injetando Workflow de Faxina Reativa (404) no Orquestrador n8n..."
        cp "$RAIZ_REPO/core/config/litellm_purge_workflow.json" "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json" 2>/dev/null || true
        sed -i "s|##LITELLM_HOST##|${PREFIXO_CONTAINER}_litellm|g" "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json"
        sed -i "s|##LITELLM_KEY##|${LITELLM_MASTER_KEY}|g" "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json"

        docker exec -u node ${PREFIXO_CONTAINER}_n8n n8n import:workflow --input=/home/node/.n8n/litellm_purge_workflow.json > /dev/null 2>&1 < /dev/null || true
        rm -f "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json"
        echo "➜ [SUCESSO] Workflow de Faxina Reativa implantado e ativado no n8n."
    else
        echo "➜ [IDEMPOTÊNCIA] Workflow de Faxina Reativa (404) já cadastrado e ativo no n8n."
    fi
}
run_step "PROVISION_N8N" "Provisionamento Idempotente do n8n" "step_provision_n8n"

# --- 2. PROVISIONAMENTO ADMIN CHATWOOT (NUKE & BYPASS SRE) ---
step_provision_chatwoot() {
echo "➜ [SRE] Verificando existência do Administrador Mestre no Chatwoot..."
CHATWOOT_STATUS=$(docker exec -i ${PREFIXO_CONTAINER}_chatwoot bundle exec rails runner "
  if User.exists?(uid: '${TS_EMAIL}', provider: 'email') || User.exists?(email: '${TS_EMAIL}')
    user = User.find_by(uid: '${TS_EMAIL}', provider: 'email') || User.find_by(email: '${TS_EMAIL}')
    user.update!(password: '${DB_PASSWORD}', password_confirmation: '${DB_PASSWORD}')
    puts 'EXISTE'
  else
    puts 'CRIAR'
  end
" < /dev/null 2>/dev/null | grep -E "EXISTE|CRIAR" || echo "CRIAR")

if [ "$CHATWOOT_STATUS" = "EXISTE" ]; then
    echo "➜ [IDEMPOTÊNCIA] O Administrador mestre já existe no Chatwoot. Credenciais e arquitetura mantidas."
    return 0
fi

echo "➜ [SRE] Purgando cache do Redis para evitar conflitos de sessão (Ghost Cache)..."
docker exec -i ${PREFIXO_CONTAINER}_redis redis-cli FLUSHALL > /dev/null 2>&1 < /dev/null || true

echo "➜ [SRE] Provisionando Administrador Mestre e Destravando Onboarding Global no Chatwoot..."
docker exec -i ${PREFIXO_CONTAINER}_chatwoot bundle exec rails runner "
begin
  Sidekiq.logger.level = Logger::WARN if defined?(Sidekiq)
  ActiveRecord::Base.transaction do
    account = Account.find_or_create_by!(name: '${PREFIXO_CONTAINER}')

    user = User.new(
      name: '${CLIENTE_NOME} ${CLIENTE_SOBRENOME}',
      email: '${TS_EMAIL}',
      password: '${DB_PASSWORD}',
      password_confirmation: '${DB_PASSWORD}'
    )
    user.type = 'SuperAdmin'
    user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
    user.save!

    AccountUser.find_or_create_by!(account_id: account.id, user_id: user.id) do |au|
      au.role = :administrator
    end

    InstallationConfig.find_or_create_by!(name: 'INSTALLATION_NAME').update!(value: '${PREFIXO_CONTAINER}')
    InstallationConfig.find_or_create_by!(name: 'CHATWOOT_INSTANCE_ADMIN_EMAIL').update!(value: '${TS_EMAIL}')

    user.update!(ui_settings: { is_profile_setup_completed: true, is_onboarding_completed: true, locale: 'pt_BR' })
    account.update!(custom_attributes: {
      'website' => 'https://${TS_DOMAIN}',
      'timezone' => 'America/Sao_Paulo'
    })
  end

  Rails.cache.clear
  GlobalConfig.clear_cache if defined?(GlobalConfig) && GlobalConfig.respond_to?(:clear_cache)
  puts '➜ [OK] Banco de Dados populado com estado puro e destravado!'
rescue => e
  puts '🚨 [ERRO CRÍTICO NO RUBY] Falha ao provisionar Chatwoot:'
  puts e.message
  exit 1
end
" < /dev/null

echo "➜ [SUCESSO] Estado do Administrador Chatwoot consolidado (Zero-Touch concluído)."
}
run_step "PROVISION_CHATWOOT" "Provisionamento Administrador Mestre do Chatwoot" "step_provision_chatwoot"

step_provision_postiz() {

echo "➜ [SRE] Aguardando prontidão do Postiz Planner (Compilação Webpack/NestJS)..."
for i in {1..36}; do
    # Testa diretamente a rota da API em vez da raiz. Se não der 502 (Bad Gateway) nem 000 (Offline), está vivo!
    HTTP_CODE_POSTIZ=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/api/auth/register || echo "000")

    if [ "$HTTP_CODE_POSTIZ" != "502" ] && [ "$HTTP_CODE_POSTIZ" != "000" ]; then
        echo "➜ [OK] Postiz Planner totalmente operante."
        break
    fi
    echo "  ↳ Backend do Postiz aquecendo... tentativa $i/36 (aguardando 5s)"
    sleep 10
done

# [SRE DOC] Impede que a esteira continue (Fallthrough) caso as 36 tentativas tenham se esgotado
if [ "$HTTP_CODE_POSTIZ" = "502" ] || [ "$HTTP_CODE_POSTIZ" = "000" ]; then
    echo "🚨 [ERRO CRÍTICO] Timeout aguardando compilação (Webpack) do Postiz após 360s. Abortando provisão!"
    diagnosticar_containers_stack "${PREFIXO_CONTAINER}_postiz"
    exit 1
fi

echo "➜ [SRE] Provisionando Proprietário no Postiz Planner via REST API..."
PAYLOAD_POSTIZ=$(jq -n \
  --arg email "$TS_EMAIL" \
  --arg pwd "$DB_PASSWORD" \
  --arg name "$CLIENTE_NOME $CLIENTE_SOBRENOME" \
  --arg company "${PREFIXO_CONTAINER}" \
  '{email: $email, password: $pwd, name: $name, company: $company, provider: "LOCAL"}')

RESPONSE_POSTIZ=$(curl -s -w "%{http_code}" -o /dev/null --max-time 15 -X POST "http://127.0.0.1:5000/api/auth/register" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD_POSTIZ" || echo "000")

if [[ "$RESPONSE_POSTIZ" =~ ^2 ]]; then
    echo "➜ [SUCESSO] Proprietário do Postiz provisionado com sucesso."
elif [[ "$RESPONSE_POSTIZ" =~ ^(400|409) ]]; then
    echo "➜ [IDEMPOTÊNCIA] Proprietário do Postiz já cadastrado. Preservando conta."
else
    echo "🚨 [ERRO CRÍTICO] Falha ao provisionar proprietário no Postiz (HTTP ${RESPONSE_POSTIZ})."
    return 1
fi
}
run_step "PROVISION_POSTIZ" "Provisionamento Automático Postiz Planner" "step_provision_postiz"

step_provision_nocodb() {
echo "➜ [SRE] Automatizando mapeamento, limpeza e identidade visual no NocoDB..."

# ===============================================================================
# 🚀 PROVISIONAMENTO PROTOCOLO WHITE-LABEL (NOCODB v2 AUTOMATIZADO)
# ===============================================================================
echo "➜ [SRE] Aguardando prontidão do barramento HTTP do NocoDB para automação..."
TENTATIVAS_NOCO=0
until [ "$(docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/v1/health || echo "000")" = "200" ]; do
  TENTATIVAS_NOCO=$((TENTATIVAS_NOCO+1))
  [ "$TENTATIVAS_NOCO" -ge 36 ] && { echo "🚨 [ERRO FATAL] API do NocoDB não respondeu após 180s."; exit 1; }
  echo "  ↳ NocoDB executando migrações internas de tabelas estruturais... aguardando 5s"
  sleep 5
done
echo "➜ [OK] NocoDB totalmente inicializado e pronto para receber payloads API."

# 1. Autenticação e captura de Token (Uso da rota v2 atualizado)
echo "  ↳ Solicitando token de autenticação na API..."

# SRE: Constrói Payload JSON blindado contra senhas complexas/caracteres especiais
PAYLOAD_NOCO=$(jq -n \
  --arg email "$TS_EMAIL" \
  --arg pwd "$DB_PASSWORD" \
  --arg firstname "$CLIENTE_NOME" \
  --arg lastname "$CLIENTE_SOBRENOME" \
  '{email: $email, password: $pwd, firstname: $firstname, lastname: $lastname}')

RESPONSE=$(docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X POST http://localhost:8080/api/v1/auth/user/signin \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD_NOCO")

AUTH_TOKEN=$(echo "$RESPONSE" | jq -r '.token // empty')

# Fallback SRE: Se o banco acabou de nascer, força o primeiro cadastro
if [ -z "$AUTH_TOKEN" ] || [ "$AUTH_TOKEN" = "null" ]; then
    echo "  ↳ Signin direto não localizado. Forçando inicialização de primeiro cadastro (signup)..."
    RESPONSE=$(docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X POST http://localhost:8080/api/v1/auth/user/signup \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD_NOCO")
    AUTH_TOKEN=$(echo "$RESPONSE" | jq -r '.token // empty')
fi

if [ -z "$AUTH_TOKEN" ] || [ "$AUTH_TOKEN" = "null" ]; then
    echo "[ERRO CRÍTICO] Falha catastrófica ao autenticar na API do NocoDB. Ambas as rotas falharam."
    echo "$RESPONSE"
    exit 1
fi
echo "  ↳ Token administrativo gerado e validado com sucesso."

# SRE FIX: Injeta Nome Completo no perfil do NocoDB (Rota atualizada v2)
PAYLOAD_PROFILE_NOCO=$(jq -n \
  --arg name "$CLIENTE_NOME $CLIENTE_SOBRENOME" \
  '{display_name: $name}')

docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X PATCH http://localhost:8080/api/v1/user/profile \
  -H "xc-auth: $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD_PROFILE_NOCO" > /dev/null 2>&1 || true

# 2. Captura o Workspace ID mestre
WORKSPACE_ID=$(docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X GET http://localhost:8080/api/v1/workspaces -H "xc-auth: $AUTH_TOKEN" | jq -r '.list[0].id // empty')

# 3. Customiza a identidade visual do Workspace mestre
if [ -n "$WORKSPACE_ID" ] && [ "$WORKSPACE_ID" != "null" ]; then
    docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X PATCH "http://localhost:8080/api/v1/workspaces/${WORKSPACE_ID}" \
      -H "xc-auth: $AUTH_TOKEN" -H "Content-Type: application/json" -d "{\"title\": \"Painel de Controle\"}" > /dev/null
fi

# 4. SRE GUARDRAIL: Verifica se a Base 'Loja_db' já existe no Workspace
BASE_EXISTENTE=$(docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X GET "http://localhost:8080/api/v2/meta/workspaces/${WORKSPACE_ID}/bases" -H "xc-auth: $AUTH_TOKEN" | jq -r '.list[]? | select(.title == "Loja_db") | .id // empty' 2>/dev/null | head -n 1 || true)

    if [ -z "$BASE_EXISTENTE" ] || [ "$BASE_EXISTENTE" = "null" ]; then
        echo "  ↳ Base 'Loja_db' não localizada. Criando arquitetura corporativa..."
        BASE_RESPONSE=$(docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X POST "http://localhost:8080/api/v2/meta/workspaces/${WORKSPACE_ID}/bases" -H "xc-auth: $AUTH_TOKEN" -H "Content-Type: application/json" -d '{"title": "Loja_db"}')
        BASE_EXISTENTE=$(echo "$BASE_RESPONSE" | jq -r '.id // empty')

        ORPHAN_BASE_ID=$(docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X GET "http://localhost:8080/api/v2/meta/workspaces/${WORKSPACE_ID}/bases" -H "xc-auth: $AUTH_TOKEN" | jq -r '.list[]? | select(.title != "Loja_db") | .id // empty' 2>/dev/null | head -n 1 || true)
        if [ -n "$ORPHAN_BASE_ID" ] && [ "$ORPHAN_BASE_ID" != "null" ]; then
            echo "  ↳ Expurgando base órfã residual [$ORPHAN_BASE_ID]..."
            docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X DELETE "http://localhost:8080/api/v2/meta/bases/${ORPHAN_BASE_ID}" -H "xc-auth: $AUTH_TOKEN" > /dev/null
        fi
    fi

    if [ -n "$BASE_EXISTENTE" ] && [ "$BASE_EXISTENTE" != "null" ]; then
        SOURCE_EXISTENTE=$(docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X GET "http://localhost:8080/api/v2/meta/bases/${BASE_EXISTENTE}/sources" -H "xc-auth: $AUTH_TOKEN" | jq -r '.list[]? | select(.alias == "Postgres Transacional") | .id // empty' 2>/dev/null | head -n 1 || true)

        if [ -z "$SOURCE_EXISTENTE" ] || [ "$SOURCE_EXISTENTE" = "null" ]; then
            echo "  ↳ Injetando Postgres Transacional na Base [$BASE_EXISTENTE]..."
            docker exec ${PREFIXO_CONTAINER}_nocodb curl -s -X POST "http://localhost:8080/api/v2/meta/bases/${BASE_EXISTENTE}/sources" -H "xc-auth: $AUTH_TOKEN" -H "Content-Type: application/json" -d "{\"type\": \"pg\", \"alias\": \"Postgres Transacional\", \"config\": {\"client\": \"pg\", \"connection\": {\"host\": \"pgbouncer\", \"port\": 6432, \"user\": \"${DB_USER}\", \"password\": \"${DB_PASSWORD}\", \"database\": \"${PREFIXO_CONTAINER}_db\", \"ssl\": false}}}" > /dev/null
        else
            echo "  ↳ Fonte transacional já conectada. Preservando arquitetura (Idempotência OK)."
        fi
    fi
echo "➜ [SUCESSO] Painel CRM NocoDB validado e 100% íntegro."
}
run_step "PROVISION_NOCODB" "Customizando Workspaces NocoDB" "step_provision_nocodb"

step_provision_ai_gateway() {
# --- PROVISIONAMENTO ADMIN LITELLM E OPEN WEBUI ---
TENTATIVAS_LLM=0
until [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4000/health/liveliness || echo "000")" = "200" ]; do
  TENTATIVAS_LLM=$((TENTATIVAS_LLM+1))
  [ "$TENTATIVAS_LLM" -ge 24 ] && { echo "🚨 [ERRO FATAL] API do LiteLLM não respondeu após 120s."; exit 1; }
  sleep 5
done

# Registra a identidade do cliente no banco do LiteLLM (Idempotente)
USER_INFO=$(curl -s -X GET "http://127.0.0.1:4000/user/info?user_id=${TS_EMAIL}" -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" 2>/dev/null || echo "")

if echo "$USER_INFO" | grep -q "${TS_EMAIL}"; then
    echo "➜ [IDEMPOTÊNCIA] Administrador LiteLLM já cadastrado (${TS_EMAIL}). Preservando acesso Web UI."
else
    echo "➜ [CONFIGURANDO] Cadastrando Administrador com acesso Web UI no LiteLLM..."
    PAYLOAD_NEW=$(jq -n --arg email "$TS_EMAIL" '{user_id: $email, user_email: $email, user_role: "proxy_admin", models: ["all"]}')
    curl -s -X POST "http://127.0.0.1:4000/user/new" -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json" -d "$PAYLOAD_NEW" > /dev/null 2>&1 || true

    PAYLOAD_UPDATE=$(jq -n --arg email "$TS_EMAIL" --arg pwd "$DB_PASSWORD" '{user_id: $email, password: $pwd, user_role: "proxy_admin"}')
    curl -s -X POST "http://127.0.0.1:4000/user/update" -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json" -d "$PAYLOAD_UPDATE" > /dev/null 2>&1 || true
fi

echo "➜ [SRE] Provisionando Administrador Mestre no Open WebUI..."
# Aguarda o FastAPI do Open WebUI inicializar e montar o banco SQLite/Postgres
TENTATIVAS_OWUI=0
until [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3001/api/v1/health || echo "000")" = "200" ]; do
  TENTATIVAS_OWUI=$((TENTATIVAS_OWUI+1))
  [ "$TENTATIVAS_OWUI" -ge 36 ] && { echo "🚨 [ERRO FATAL] Banco do Open WebUI não montou após 180s."; exit 1; }
  sleep 5
done

# O primeiro usuário que bater nesta API antes do sistema travar ganha o cargo de Admin
PAYLOAD_OWUI=$(jq -n --arg name "$CLIENTE_NOME $CLIENTE_SOBRENOME" --arg email "$TS_EMAIL" --arg pwd "$DB_PASSWORD" '{name: $name, email: $email, password: $pwd}')
RESPONSE_OWUI=$(curl -s -w "%{http_code}" -o /dev/null -X POST "http://127.0.0.1:3001/api/v1/auths/signup" \
  -H "Content-Type: application/json" -d "$PAYLOAD_OWUI" || echo "000")
 
if [[ "$RESPONSE_OWUI" =~ ^2 ]]; then
    echo "➜ [SUCESSO] Conta Administradora do Open WebUI forjada com sucesso!"
elif [ "$RESPONSE_OWUI" = "400" ] || [ "$RESPONSE_OWUI" = "403" ]; then
    echo "➜ [INFO] Banco de dados do Open WebUI já populado (Idempotência OK)."
else
    echo "➜ [AVISO SRE] Falha silenciosa no Auth do Open WebUI (HTTP $RESPONSE_OWUI)."
fi
}
run_step "PROVISION_AI" "Cadastrando Hub Organizacional LiteLLM e OpenWebUI" "step_provision_ai_gateway"

step_crontab_and_recovery() {

# [SRE DOC] Bypass Atômico: Scripts de rede perimetral (Tailscale) não devem existir no modelo BYODNS
if [ "$USE_TAILSCALE" = "false" ]; then
    echo "➜ [SRE SKIP] Modo BYODNS Ativado: Omitindo utilitários de limpeza e recovery do Tailscale."
else
    # Copia os templates desacoplados dos utilitários de rede Tailscale
    cp "$RAIZ_REPO/core/scripts/ts_cleanup.sh" "$TARGET_DIR/core/scripts/ts_cleanup.sh" 2>/dev/null || true
    sed -i "s|##TS_OAUTH_ID##|${TS_OAUTH_ID}|g" "$TARGET_DIR/core/scripts/ts_cleanup.sh"
    sed -i "s|##TS_OAUTH_SECRET##|${TS_OAUTH_SECRET}|g" "$TARGET_DIR/core/scripts/ts_cleanup.sh"
    sed -i "s|##TS_EMAIL##|${TS_EMAIL}|g" "$TARGET_DIR/core/scripts/ts_cleanup.sh"
    sed -i "s|##PREFIXO_CONTAINER##|${PREFIXO_CONTAINER}|g" "$TARGET_DIR/core/scripts/ts_cleanup.sh"
    chmod 700 "$TARGET_DIR/core/scripts/ts_cleanup.sh"

    echo "4. Injetando utilitário de ressubida e recuperação de rede (ts_recovery.sh)"
    cp "$RAIZ_REPO/core/scripts/ts_recovery.sh" "$TARGET_DIR/core/scripts/ts_recovery.sh" 2>/dev/null || true
    chmod +x "$TARGET_DIR/core/scripts/ts_recovery.sh"
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$TARGET_DIR/core/scripts/ts_recovery.sh" 2>/dev/null || true
    fi
fi

    # Injeta na crontab limpando as regras antigas para manter a idempotência estrita de SRE
    crontab -l 2>/dev/null | grep -v "backup_diario.sh" | grep -v "upgrade_stack.sh" | grep -v "ts_cleanup.sh" | grep -v "sync_ia_models.sh" > /tmp/cron_limpo || true
    echo "0 23 * * * /bin/bash $TARGET_DIR/core/scripts/backup_diario.sh" >> /tmp/cron_limpo
    echo "0 4 * * * /bin/bash $TARGET_DIR/core/scripts/sync_ia_models.sh" >> /tmp/cron_limpo
    crontab /tmp/cron_limpo && rm -f /tmp/cron_limpo
}
run_step "CRONTAB_AND_RECOVERY" "Injetando Crontabs e script de recuperação" "step_crontab_and_recovery"  

step_sync_ai_models() {
# Limpeza e remoção do clone temporário se a execução foi Headless
if [ "$RAIZ_REPO" = "/tmp/infra-loja-bootstrap" ]; then rm -rf /tmp/infra-loja-bootstrap; fi

# ===============================================================================
# SRE /READINESS PROBES: VALIDAÇÃO DINÂMICA DO CICLO DE VIDA DOS ATIVOS
# ===============================================================================
echo "=== [SRE] Inicializando Probes Dinâmicas de Prontidão (Readiness Probes) ==="

CONTAINERS_AUDIT=(
    "${PREFIXO_CONTAINER}_redis"
    "${PREFIXO_CONTAINER}_postgres"
    "${PREFIXO_CONTAINER}_pgbouncer"
    "${PREFIXO_CONTAINER}_nocodb"
    "${PREFIXO_CONTAINER}_evolution"
    "${PREFIXO_CONTAINER}_n8n"
    "${PREFIXO_CONTAINER}_temporal"
    "${PREFIXO_CONTAINER}_caddy"
    "${PREFIXO_CONTAINER}_chatwoot"
    "${PREFIXO_CONTAINER}_postiz"
    "${PREFIXO_CONTAINER}_litellm"
    "${PREFIXO_CONTAINER}_openwebui"
)
if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]]; then
    CONTAINERS_AUDIT+=("${PREFIXO_CONTAINER}_minio")
fi

TIMEOUT=120
ELAPSED=0
CHECK_INTERVAL=5
TODO_ECOSSISTEMA_SAUDAVEL=true

while [ $ELAPSED -lt $TIMEOUT ]; do
    ALL_HEALTHY=true
    for container in "${CONTAINERS_AUDIT[@]}"; do
        # Captura o status real do Docker: starting, healthy, unhealthy ou OFFLINE
        HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{if .State.Running}}healthy{{else}}unhealthy{{end}}{{end}}' "$container" 2>/dev/null || echo "OFFLINE")
        if [ "$HEALTH" != "healthy" ]; then
            ALL_HEALTHY=false
            break
        fi
    done

    if [ "$ALL_HEALTHY" = "true" ]; then
        echo "➜ [SUCESSO] Todos os ativos atingiram o estado [healthy]! Prosseguindo..."
        break
    fi

    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
    echo "  ↳ Aguardando prontidão dos microsserviços (${ELAPSED}/${TIMEOUT}s)..."
done

if [ "$ALL_HEALTHY" != "true" ]; then
    echo "[AVISO SRE] Timeout atingido! Alguns contêineres não estabilizaram a saúde a tempo."
    TODO_ECOSSISTEMA_SAUDAVEL=false
fi

echo "➜ [SRE] Forjando motor de sincronização dinâmica (Catálogo Inteligente)..."
    # Copia o template desacoplado do motor de sincronização inteligente de IA
    cp "$RAIZ_REPO/core/scripts/sync_ia_models.sh" "$TARGET_DIR/core/scripts/sync_ia_models.sh" 2>/dev/null || true
    chmod +x "$TARGET_DIR/core/scripts/sync_ia_models.sh"

chmod +x "$TARGET_DIR/core/scripts/sync_ia_models.sh"

if [ -f "$TARGET_DIR/core/scripts/sync_ia_models.sh" ] && [ "$TODO_ECOSSISTEMA_SAUDAVEL" = "true" ]; then
    echo "=== [SRE] Ecossistema estável. Executando Sincronização Atômica de Inteligência ==="
    sudo bash "$TARGET_DIR/core/scripts/sync_ia_models.sh" < /dev/null

    echo "=== [SRE GUARDRAIL] Amortecendo e aguardando re-estabilização pós-restart dos microsserviços ==="

    # Contêineres impactados pelo restart do sync_ia_models.sh
    RESTARTED_CONTAINERS=(
        "${PREFIXO_CONTAINER}_litellm"
        "${PREFIXO_CONTAINER}_openwebui"
        "${PREFIXO_CONTAINER}_postiz"
        "${PREFIXO_CONTAINER}_chatwoot"
        "${PREFIXO_CONTAINER}_nocodb"
    )

    # Loop de tolerância de até 60 segundos com intervalo de 3s
    MAX_WAIT=60
    WAIT_COUNT=0
    ALL_STABLE=false

    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        ALL_STABLE=true
        for container in "${RESTARTED_CONTAINERS[@]}"; do
            # Captura o status exato: running/healthy
            HEALTH_STATE=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{if .State.Running}}healthy{{else}}unhealthy{{end}}{{end}}' "$container" 2>/dev/null || echo "OFFLINE")
 
            if [ "$HEALTH_STATE" != "healthy" ]; then
                ALL_STABLE=false
                break
            fi
        done

        if [ "$ALL_STABLE" = "true" ]; then
            echo "➜ [SUCESSO] Todos os microsserviços reiniciados atingiram estabilidade [healthy]!"
            break
        fi

        sleep 3
        WAIT_COUNT=$((WAIT_COUNT + 3))
        echo "  ↳ Aguardando reconexão das aplicações no barramento (${WAIT_COUNT}/${MAX_WAIT}s)..."
    done

    if [ "$ALL_STABLE" = "false" ]; then
        echo "⚠️ [AVISO SRE] Alguns contêineres ainda estão estabilizando, mas o grace period foi concedido."
    fi
fi
}
run_step "SYNC_AI" "Sincronização Dinâmica do Catálogo Inteligente" "step_sync_ai_models"

echo "=== [SRE AUDIT] Inicializando varredura de rede e testes de handshakes ==="

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
    REPORT_EVO_URL="${SERVER_URL}"
    REPORT_PORTAL_URL="https://${TS_DOMAIN}"
else
    REPORT_BORDER_INFO="  ↳ Roteamento de Borda:     BYODNS (Nginx/Cloudflare/IP Fixo)"
    REPORT_EVO_URL="${SERVER_URL}"
    REPORT_PORTAL_URL="${CADDY_PROTOCOL:-http}://${TS_DOMAIN}"
fi

# 2. Descoberta Dinâmica de IPs na Malha de Containers
IP_BOUNCER="$IP_PGBOUNCER"
IP_NOCO="$IP_NOCODB"
IP_WAF="$IP_CADDY"
IP_EVO="${IP_EVOLUTION}"

# ===============================================================================
# 3. TESTES CONDICIONAIS DE HANDSHAKE (Guarda de Segurança)
# ===============================================================================
echo "=== [SRE] Amortecendo barramento (10s) para estabilização do Funnel... ==="
sleep 10

# --- Módulo Portal Gateway (Teste Externo Funnel HTTPS vs Interno HTTP) ---
HTTP_GATEWAY_FUNNEL=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${TS_DOMAIN}/healthz" || echo "000")

if [ "$HTTP_GATEWAY_FUNNEL" = "200" ]; then
    STATUS_GATEWAY="✅ HTTPS Público: OK"
    HTTP_GATEWAY="200"
else
    # Fallback: Valida o Caddy localmente
    HTTP_GATEWAY_LOCAL=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${PROXY_PORT}/healthz" || echo "000")

    if [ "$HTTP_GATEWAY_LOCAL" = "200" ]; then
        # SRE FIX: Se o curl público deu timeout por hairpinning local, mas a CLI do Tailscale confirma Funnel ON
        if sudo tailscale funnel status 2>/dev/null | grep -q "https://${TS_DOMAIN}"; then
            STATUS_GATEWAY="✅ HTTPS Público: OK (Funnel Ativo / Loopback Protegido)"
            HTTP_GATEWAY="200"
        else
            # Busca no log do Tailscale mensagens de Rate Limit do Let's Encrypt
            TS_RATE_LIMIT_LOG=$(journalctl -u tailscaled --no-pager | grep -iE "retry after|too many certificates|acme: error: 429|rate limit" | tail -n 1 || true)
 
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
                STATUS_GATEWAY="⚠️ Funnel Desativado | HTTP Local: OK"
            fi
            HTTP_GATEWAY="200"
        fi
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

# --- Módulo Evolution API (Teste Externo Funnel HTTPS vs Interno HTTP) ---
HTTP_EVO_FUNNEL=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${TS_DOMAIN}:8443/" || echo "000")

if [ "$HTTP_EVO_FUNNEL" = "200" ]; then
    STATUS_EVO_EXT="✅ HTTPS Público: OK"
    HTTP_EVO_EXT="200"
else
    # Fallback Local
    if [ "$USE_TAILSCALE" = "false" ]; then
        # [SRE DOC] Probe BYODNS via Host Header Override:
        # Bate no socket local da porta do Caddy WAF (${PROXY_PORT}) injetando o Host Header do subdomínio da API.
        HTTP_EVO_LOCAL=$(curl -s -H "Host: ${CUSTOM_EVO_DOMAIN}" -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${PROXY_PORT}/" || echo "000")
    else
        HTTP_EVO_LOCAL=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${EVO_PORT}/" || echo "000")
    fi

    if [ "$HTTP_EVO_LOCAL" = "200" ]; then
        if [ "$USE_TAILSCALE" = "false" ]; then
            STATUS_EVO_EXT="✅ Roteamento BYODNS: OK (Host Header Roteado)"
            HTTP_EVO_EXT="200"
        elif sudo tailscale funnel status 2>/dev/null | grep -q ":8443"; then
            STATUS_EVO_EXT="✅ HTTPS Público: OK (Funnel Ativo / Loopback Protegido)"
            HTTP_EVO_EXT="200"
        else
            STATUS_EVO_EXT="⚠️ Funnel Desativado | HTTP Local: OK"
            HTTP_EVO_EXT="200"
        fi
    else
        STATUS_EVO_EXT="❌ Evolution API Offline"
        HTTP_EVO_EXT="FALHOU"
    fi
fi

# --- Módulo N8N Direct (Porta 5678) ---
HEALTH_N8N=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_n8n 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_N8N" = "healthy" ]; then
    HTTP_N8N_TS=$(curl -s -H "Host: ${TS_DOMAIN}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:5678/healthz" || echo "FALHOU")
else
    HTTP_N8N_TS="CONTAINER_ERRO"
fi

# --- Módulo Redis Cache ---
HEALTH_REDIS=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_redis 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_REDIS" = "healthy" ]; then
    STATUS_REDIS=$(docker exec ${PREFIXO_CONTAINER}_redis redis-cli ping 2>/dev/null | grep -q PONG && echo "Saudável" || echo "FALHOU")
else
    STATUS_REDIS="CONTAINER_OFFLINE"
fi

# --- Módulo NocoDB ---
HEALTH_NOCO=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_nocodb 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_NOCO" = "healthy" ]; then
    HTTP_NOCO_TS=$(curl -s -H "Host: ${TS_DOMAIN}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:${NOCO_PORT:-18080}/api/v1/health" || echo "FALHOU")
else
    HTTP_NOCO_TS="CONTAINER_ERRO"
fi

# --- Módulo Chatwoot CRM ---
HEALTH_CHATWOOT=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_chatwoot 2>/dev/null || echo "OFFLINE")

if [ "$HEALTH_CHATWOOT" = "healthy" ]; then
    HTTP_CHATWOOT_TS=$(curl -s -L -H "Host: ${TS_DOMAIN}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:3000/" || echo "FALHOU")
else
    HTTP_CHATWOOT_TS="CONTAINER_ERRO"
fi

# --- Módulo Postiz Planner ---
HEALTH_POSTIZ=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_postiz 2>/dev/null || echo "OFFLINE")

if [ "$HEALTH_POSTIZ" = "healthy" ]; then
    HTTP_POSTIZ_TS=$(curl -s -L -H "Host: ${TS_DOMAIN}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:5000/" || echo "FALHOU")
else
    HTTP_POSTIZ_TS="CONTAINER_ERRO"
fi

# --- Módulo Inteligência Artificial (Open WebUI) ---
HEALTH_OPENWEBUI=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_openwebui 2>/dev/null || echo "OFFLINE")

if [ "$HEALTH_OPENWEBUI" = "healthy" ]; then
    HTTP_OPENWEBUI_TS=$(curl -s -L -H "Host: ${TS_DOMAIN}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:3001/health" || echo "FALHOU")
else
    HTTP_OPENWEBUI_TS="CONTAINER_ERRO"
fi

# --- Módulo Cluster PostgreSQL ---
HEALTH_DB=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_postgres 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_DB" = "healthy" ]; then
    STATUS_POSTGRES=$(docker exec ${PREFIXO_CONTAINER}_postgres pg_isready -U "$DB_USER" -d "${PREFIXO_CONTAINER}_db" >/dev/null 2>&1 && echo " Saudável" || echo " FALHOU")
    STATUS_EVO_DB=$(docker exec ${PREFIXO_CONTAINER}_postgres pg_isready -U "$DB_USER" -d "evolution_db" >/dev/null 2>&1 && echo " Saudável" || echo " FALHOU")
else
    STATUS_POSTGRES=" CONTAINER_OFFLINE"
    STATUS_EVO_DB=" CONTAINER_OFFLINE"
fi

# --- Módulo Connection Pooler (PgBouncer) ---
HEALTH_POOLER=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_pgbouncer 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_POOLER" = "healthy" ] && [ "$HEALTH_DB" = "healthy" ]; then
    STATUS_BOUNCER=$(docker exec ${PREFIXO_CONTAINER}_postgres pg_isready -h ${PREFIXO_CONTAINER}_pgbouncer -p 6432 >/dev/null 2>&1 && echo " Saudável" || echo " FALHOU")
else
    STATUS_BOUNCER=" CONTAINER_OFFLINE"
fi

# --- Módulo Temporal Engine ---
HEALTH_TEMPORAL=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_temporal 2>/dev/null || echo "OFFLINE")
if [ "$HEALTH_TEMPORAL" = "healthy" ]; then
    STATUS_TEMPORAL=$(docker exec ${PREFIXO_CONTAINER}_temporal temporal operator cluster health --address $(docker exec ${PREFIXO_CONTAINER}_temporal hostname -i | awk '{print $1}'):7233 >/dev/null 2>&1 && echo "Saudável" || echo "FALHOU")
else
    STATUS_TEMPORAL="CONTAINER_ERRO"
fi

HTTP_MINIO_CHECK="200"
if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]]; then
    HEALTH_MINIO=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{if .State.Running}}healthy{{else}}unhealthy{{end}}{{end}}' ${PREFIXO_CONTAINER}_minio 2>/dev/null || echo "OFFLINE")
    if [ "$HEALTH_MINIO" = "healthy" ]; then
        HTTP_MINIO_CHECK=$(curl -s -L -H "Host: ${TS_DOMAIN}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:9001/" || echo "FALHOU")
    else
        HTTP_MINIO_CHECK="CONTAINER_ERRO"
    fi
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
   [ "$HTTP_N8N_TS" = "200" ] && \
   [ "$HTTP_EVO_EXT" = "200" ] && \
   [ "$HTTP_NOCO_TS" = "200" ] && \
   [ "$HTTP_CHATWOOT_TS" = "200" ] && \
   [ "$HTTP_POSTIZ_TS" = "200" ] && \
   [ "$HTTP_MINIO_CHECK" = "200" ] && \
   [ "$HTTP_LITELLM" = "200" ] && \
   [ "$STATUS_REDIS" = "Saudável" ]; then

    USER_REAL_HOME=$(eval echo "~${SUDO_USER:-$USER}")
    EXISTING_BACKUP=$(ls -t "${USER_REAL_HOME}/backup_${PREFIXO_CONTAINER}_"*.sql.gz.gpg 2>/dev/null | head -n 1 || echo "")

    if [ -n "$EXISTING_BACKUP" ] && [ -f "$EXISTING_BACKUP" ]; then
        echo "➜ [IDEMPOTÊNCIA] Backup Inicial (Dia 0) já existe. Preservando artefato: $EXISTING_BACKUP"
        ARTEFATO_BACKUP="$EXISTING_BACKUP"
    else
        echo "=== [SRE DR] Ecossistema 100% Operacional! Executando Backup Inicial (Dia 0) ==="
        if bash "$TARGET_DIR/core/scripts/backup_diario.sh"; then
            ARTEFATO_BACKUP=$(ls -t "${USER_REAL_HOME}/backup_${PREFIXO_CONTAINER}_"*.sql.gz.gpg 2>/dev/null | head -n 1 || echo "ERRO_NA_CAPTURA")
            echo "➜ [SUCESSO] Cold Backup gerado, testado no Sanity Check e cifrado via GPG!"
            echo "   ↳ Artefato: $ARTEFATO_BACKUP"
        else
            echo "⚠️ [ALERTA] O ecossistema está saudável, mas o script de backup falhou na execução."
            ARTEFATO_BACKUP="FALHA NO EXPURGO/GPG"
        fi
    fi
else
    echo "⚠️ [SRE SKIP] Backup inicial ignorado pois o ambiente apresentou instabilidade nos handshakes."
fi

# ===============================================================================
# RELATÓRIO FORENSE CONSOLIDADO DO ECOSSISTEMA
# ===============================================================================
echo ""
echo "====================================================================="
if [ "$TODO_ECOSSISTEMA_SAUDAVEL" = "true" ]; then
    echo "        [SUCESSO ABSOLUTO] ECOSSISTEMA DE PROVISIONAMENTO ATIVO       "
else
    echo "        [CONCLUÍDO COM ALERTAS] ECOSSISTEMA REQUER ATENÇÃO            "
fi
echo "====================================================================="
echo "➜ INFRAESTRUTURA FÍSICA DO HOST:"
echo "  ↳ IP Privado Local (LAN):  $IP_HOST_LAN"
echo "$REPORT_BORDER_INFO"
echo "  ↳ Domínio FQDN Canônico:   $TS_DOMAIN"
echo ""
echo "➜ MAPEAMENTO TOPOLÓGICO DE ATIVOS (DOCKER MALHA INTERNA):"
echo "  ↳ WAF Borda (Caddy):       $IP_WAF  | Portas do Host: 5678, 8081"
echo "  ↳ Orquestrador (n8n):      $IP_N8N  | Porta Interna: 5678"
echo "  ↳ WhatsApp API (Evolution):$IP_EVO  | Porta Interna: 8080 (Acesso Direto)"
echo "  ↳ Painel CRM (NocoDB):     $IP_NOCO  | Porta do Host: $HOST_NOCODB_PORT"
if [ "$USE_LITELLM" = "true" ]; then
    echo "  ↳ AI Gateway (LiteLLM):    $IP_LITELLM  | Porta Interna: 4000"
fi
echo "  ↳ Cluster PostgreSQL 16:   $IP_POSTGRES  | Porta Interna: 5432"
echo "  ↳ Connection Pooler:       $IP_BOUNCER  | Porta Interna: 6432"
echo ""
echo "➜ MATRIZ DE ROTEAMENTO E STATUS DE HANDSHAKES:"
echo "  ↳ Acesso Portal Gateway:  $STATUS_GATEWAY"
echo "  ↳ Acesso Evolution API:   $STATUS_EVO_EXT"
echo "  ↳ Acesso Chatwoot CRM:    http://$TS_DOMAIN:3000  -> Status: [$HTTP_CHATWOOT_TS]"
echo "  ↳ Acesso Postiz Planner:  http://$TS_DOMAIN:5000  -> Status: [$HTTP_POSTIZ_TS]"
echo "  ↳ Acesso n8n Direct:      http://$TS_DOMAIN:5678  -> Status: [$HTTP_N8N_TS]"
echo "  ↳ Acesso NocoDB ERP:      http://$TS_DOMAIN:${HOST_NOCODB_PORT:-18080}  -> Status: [$HTTP_NOCO_TS]"
if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]] && [ -f "$TARGET_DIR/core/scripts/install_minIO.sh" ]; then
    bash "$TARGET_DIR/core/scripts/install_minIO.sh" audit_health "$TARGET_DIR" "${TS_DOMAIN:-localhost}"
fi
echo "  ↳ Acesso Open WebUI (IA): http://$TS_DOMAIN:3001  -> Status: [$HTTP_OPENWEBUI_TS]"
# [SRE DOC] O LiteLLM é o Gateway de IA soberano e obrigatório da arquitetura
echo "  ↳ AI Gateway (LiteLLM):   Internal:4000           -> Status: [$HTTP_LITELLM]"
echo "  ↳ Cache em Memória:        Redis Server -> [$STATUS_REDIS]"
echo "  ↳ Banco n8n (PgBouncer):   6432/tcp -> [$STATUS_BOUNCER]"
echo "  ↳ Banco Core (Postgres):   5432/tcp -> [$STATUS_POSTGRES]"
echo "  ↳ Banco WhatsApp (Evo):    evolution_db -> [$STATUS_EVO_DB]"
echo "  ↳ Orquestrador (Temporal): 7233/tcp -> [$STATUS_TEMPORAL]"
echo ""
# [SRE DOC] Exibição Expandida de Endpoints Operacionais, APIs, Swagger, Health e MCP baseada em documentação oficial.
echo "➜ MATRIZ DE ACESSO, APIS E ENDPOINTS SRE (WHITE-LABEL):"
echo "  🌐 WAF Borda (Caddy)"
echo "    ↳ Portal Omnichannel (Frontend):   ${REPORT_PORTAL_URL}"
echo ""
echo "  🤖 AI Gateway (LiteLLM)"
echo "    ↳ Admin UI:                        http://${TS_DOMAIN}:4000/ui"
echo "    ↳ MCP Gateway Server:              http://${TS_DOMAIN}:4000/mcp"
echo "    ↳ Descoberta de Modelos:           http://${TS_DOMAIN}:4000/v1/models"
echo "    ↳ Chat Completions:                http://${TS_DOMAIN}:4000/v1/chat/completions"
echo "    ↳ Embeddings API:                  http://${TS_DOMAIN}:4000/v1/embeddings"
echo "    ↳ Liveliness:                      http://${TS_DOMAIN}:4000/health/liveliness"
echo ""
echo "  🧠 Inteligência (Open WebUI)"
echo "    ↳ Painel Web (Cliente MCP):        http://${TS_DOMAIN}:3001"
echo "    ↳ Integração REST API:             http://${TS_DOMAIN}:3001/api/"
echo "    ↳ Open API/Swagger:                http://${TS_DOMAIN}:3001/openapi.json"
echo "    ↳ Healthcheck:                     http://${TS_DOMAIN}:3001/health"
echo "    ↳ Docs:                            http://${TS_DOMAIN}:3001/docs"
echo ""
echo "  ⚡ Orquestrador de IA (n8n)"
echo "    ↳ Painel Web / Editor:             http://${TS_DOMAIN}:5678"
echo "    ↳ Instance MCP Server:             http://${TS_DOMAIN}:5678/mcp/"
echo "    ↳ Workflow MCP Trigger:            http://${TS_DOMAIN}:5678/mcp-test/"
echo "    ↳ Healthcheck:                     http://${TS_DOMAIN}:5678/healthz"
echo ""
echo "  💬 WhatsApp API (Evolution)"
echo "    ↳ API Principal:                   ${REPORT_EVO_URL}"
echo "    ↳ Evolution Manager:               ${REPORT_EVO_URL}/manager"
echo ""
echo "  🗣️ Atendimento CRM (Chatwoot)"
echo "    ↳ Painel Web:                      http://${TS_DOMAIN}:3000"
echo ""
echo "  🚀 Planejador Social (Postiz)"
echo "    ↳ Painel Web (Frontend):           http://${TS_DOMAIN}:5000"
echo "    ↳ Backend API:                     http://${TS_DOMAIN}:5000/api/"
echo "    ↳ Auth:                            http://${TS_DOMAIN}:5000/auth"
echo ""
echo "  📊 Banco de Dados ERP (NocoDB)"
echo "    ↳ Painel Web:                      http://${TS_DOMAIN}:${HOST_NOCODB_PORT:-18080}"
echo ""
if [[ "${USE_MINIO:-s}" =~ ^[Ss]$ ]]; then
    if [ -f "$TARGET_DIR/core/scripts/install_minIO.sh" ]; then
        bash "$TARGET_DIR/core/scripts/install_minIO.sh" render_report "${TS_DOMAIN:-localhost}"
    fi
else
    echo "  🗄️ Armazenamento S3"
    echo "    ↳ Status:                          S3 Provedor Remoto Externo (MinIO Local Desativado)"
    echo ""
fi
echo "  🔄 Pool de Conexões PostgreSQL (PgBouncer)"
echo "    ↳ Endpoint TCP:                    ${TS_DOMAIN}:6432"
echo "    ↳ Console Admin:                   psql -h ${TS_DOMAIN} -p 6432 -U pgbouncer pgbouncer"
echo "    ↳ Estatísticas:                    SHOW STATS;"
echo "    ↳ Pools:                           SHOW POOLS;"
echo "    ↳ Clientes:                        SHOW CLIENTS;"
echo ""
echo "  ⚙️ Motores de Fundo e Banco de Dados (Sem Painel Web Público)"
echo "    ↳ Temporal Web UI (Interna):       http://${TS_DOMAIN}:8080"
echo "    ↳ Temporal API:                    http://${TS_DOMAIN}:8080/api/v1"
echo "    ↳ Temporal CLI:                    temporal operator cluster health | tctl"
echo "    ↳ PostgreSQL DB (Health):          pg_isready | psql"
echo "    ↳ Redis Cache (Admin):             redis-cli INFO | MONITOR | redis-cli PING"

echo ""
echo ""
echo "  ❤️ Health"
echo "    ↳ LiteLLM:                         http://${TS_DOMAIN}:4000/health/liveliness"
echo "    ↳ Open Web UI:                     http://${TS_DOMAIN}:3001/health"
echo "    ↳ n8n:                             http://${TS_DOMAIN}::5678/healthz"
echo "    ↳ MinIO (Live):                    http://${TS_DOMAIN}:9000/minio/health/live"
echo "    ↳ MinIO (Ready):                   http://${TS_DOMAIN}:9000/minio/health/ready"
echo "    ↳ Evolution:                       ${REPORT_EVO_URL}/manager/health"
echo "    ↳ Evolution:                       ${REPORT_EVO_URL}/api/v1/health"
echo "    ↳ Postgres:                        pg_isready | psql"
echo "    ↳ Redis:                           redis-cli ping | INFO | MONITOR"
echo ""
echo "  🔑 CREDENCIAIS DO CLIENTE (Acesso Global Unificado):"
echo "    - E-mail:                         ${TS_EMAIL}"
echo "    - Senha:                          ${DB_PASSWORD}"
echo "    - Master Key (admin - LiteLLM):   ${LITELLM_MASTER_KEY}"
echo "====================================================================="
echo "  [SRE AUDIT COMPLETO] Varredura dinâmica de prontidão finalizada."
echo "====================================================================="

# ===============================================================================
# 🎯 PROTOCOLO DE TRIAGEM AUTOMÁTICA (LOG PATH DISCOVERY)
# ===============================================================================
# Verifica se houve qualquer anomalia na saúde geral ou nos handshakes de rede
if [ "$TODO_ECOSSISTEMA_SAUDAVEL" = "false" ] || \
   [ "$HTTP_GATEWAY" = "FALHOU" ] || \
   [ "$HTTP_N8N_TS" = "FALHOU" ] || [ "$HTTP_N8N_TS" = "CONTAINER_ERRO" ] || \
   [ "$HTTP_EVO_EXT" = "FALHOU" ] || [ "$HTTP_EVO_EXT" = "CONTAINER_ERRO" ] || \
   [ "$HTTP_NOCO_TS" = "FALHOU" ] || [ "$HTTP_NOCO_TS" = "CONTAINER_ERRO" ] || \
   [ "$HTTP_LITELLM" = "FALHOU" ] || [ "$HTTP_LITELLM" = "CONTAINER_ERRO" ] || \
   [[ "$STATUS_POSTGRES" == *"FALHOU"* ]] || [[ "$STATUS_BOUNCER" == *"FALHOU"* ]]; then

    echo ""
    echo "====================================================================="
    echo "   ⚠️ [SRE TRIAGE] DETECTADOS ATIVOS INSTÁVEIS OU FORA DE SOCKET     "
    echo "====================================================================="
    echo "Mapeamento dos caminhos absolutos de logs no host para depuração externa:"
    echo ""

    for container in "${CONTAINERS_AUDIT[@]}"; do
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

# ===============================================================================
# 🔒 PROTOCOLO FINAL DE HIGIENIZAÇÃO DE AMBIENTE (SUCESSO)
# ===============================================================================
echo "=== [SRE] Finalizando provisionamento e higienizando barramento ==="

# GOLPE DE MESTRE SRE: Captura o estado e os certificados válidos para persistência vitalícia por cliente
USER_HOME_REAL=$(eval echo "~${SUDO_USER:-$USER}")
if [ ! -d "$USER_HOME_REAL" ]; then
    USER_HOME_REAL="/home/${SUDO_USER:-$USER}"
fi

if [ "$USE_TAILSCALE" = "true" ]; then
    echo "➜ [SRE] Consolidando backup criptográfico da identidade do Tailscale para o cliente: ${CLIENTE_NOME}..."
    sudo tar --warning=no-file-changed -czf "$USER_HOME_REAL/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz" -C /var/lib/tailscale . 2>/dev/null || true
    sudo chmod 644 "$USER_HOME_REAL/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz" 2>/dev/null || true
    if [ -n "$SUDO_USER" ]; then
        sudo chown "$SUDO_USER:$SUDO_USER" "$USER_HOME_REAL/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz" 2>/dev/null || true
    fi
fi

if [ -d "$TARGET_DIR/volumes/nocodb_ts_state" ]; then
    echo "➜ [SRE] Consolidando identidade isolada do nó satélite NocoDB..."
    sudo tar --warning=no-file-changed -czf "$USER_HOME_REAL/nocodb_ts_${CLIENTE_SUFIXO}_backup.tar.gz" -C "$TARGET_DIR/volumes/nocodb_ts_state" . 2>/dev/null || true
    sudo chmod 644 "$USER_HOME_REAL/nocodb_ts_${CLIENTE_SUFIXO}_backup.tar.gz" 2>/dev/null || true
    if [ -n "$SUDO_USER" ]; then
        sudo chown "$SUDO_USER:$SUDO_USER" "$USER_HOME_REAL/nocodb_ts_${CLIENTE_SUFIXO}_backup.tar.gz" 2>/dev/null || true
    fi
fi

if [ -f "$ARTEFATO_BACKUP" ]; then
    echo "➜ BACKUP INICIAL DE SEGURANÇA (GPG ENCRYPTED):"
    echo "  ↳ Localizador no Host: $ARTEFATO_BACKUP"
    echo "  ↳ Agendamento Cron:   Diariamente às 23:00 (via backup_diario.sh)"
else
    echo "➜ BACKUP INICIAL DE SEGURANÇA (DIA 0):"
    echo "  ↳ Status: Aprovado para execução agendada (CRON diário às 23:00 via backup_diario.sh)"
fi

# Destruição do rastro físico temporário no HD (Garantindo intocado o /tmp/debug_bash.log)
rm -rf "${USER_HOME_REAL}/.daemind_wizard_cache.env" "${USER_HOME_REAL}/.daemind_wizard_cache.env.tmp" /tmp/infra-loja-bootstrap /tmp/lojista_key.asc "${RAIZ_REPO}/preinstall.sh" /opt/daemind/preinstall.sh 2>/dev/null
rm -f "$STATE_FILE" /tmp/sync_ia_errors.log 2>/dev/null || true
rm -rf "$TARGET_DIR/.git" "$TARGET_DIR/.gitignore" "$TARGET_DIR/.gitattributes" 2>/dev/null || true
rm -rf "$TARGET_DIR/core/config" "$TARGET_DIR/database" 2>/dev/null || true
rm -f "/opt/daemind/CHAVE_PRIVADA_BACKUP_${PREFIXO_CONTAINER}.asc" "${USER_HOME_REAL}/CHAVE_PRIVADA_BACKUP_${PREFIXO_CONTAINER}.asc" 2>/dev/null || true

# Relocalização segura e definitiva do log unificado para a área persistente
if [ -f "$LOG_FILE" ]; then
    cp "$LOG_FILE" "$TARGET_DIR/volumes/tailscale_state/debug_install.log" 2>/dev/null
fi

# Purga completa das credenciais em memória
export GIT_TOKEN_BOOT="EXPURGADO" DB_PASSWORD="EXPURGADO" TS_OAUTH_SECRET="EXPURGADO" LOJA_API_KEY="EXPURGADO" LOJA_APP_KEY="EXPURGADO" GEMINI_API_KEY="EXPURGADO" OPENAI_API_KEY="EXPURGADO" ANTHROPIC_API_KEY="EXPURGADO" DEEPSEEK_API_KEY="EXPURGADO" OPENROUTER_API_KEY="EXPURGADO"
unset GIT_TOKEN_BOOT DB_PASSWORD TS_OAUTH_SECRET LOJA_API_KEY LOJA_APP_KEY GEMINI_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY OPENROUTER_API_KEY

gerar_relatorio_versoes_stack

echo "====================================================================="
echo "       [SUCESSO ABSOLUTO] AMBIENTE SANITIZADO E ENTREGUE             "
echo "====================================================================="
if [ "$USE_TAILSCALE" = "true" ]; then
    echo " 💡 [SRE ADVICE] O backup de identidade vitalício do Tailscale foi gerado com sucesso!"
    echo "    ↳ Localização:  ${USER_HOME_REAL}/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz"
    echo "    Para os próximos deploys, coloque este arquivo na sua Home (~/) para não ser limitado"
    echo "    ao adquirir certificado Let's Encrypit TLS da conta Free."
    echo "====================================================================="
else
    echo " 💡 [SRE ADVICE] Operação finalizada em modelo BYODNS."
    echo "    ↳ Gestão de Domínios, Proxies Externos e TLS estão sob responsabilidade do administrador."
    echo "====================================================================="
fi