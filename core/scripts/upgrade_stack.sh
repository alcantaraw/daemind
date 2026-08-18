#!/bin/bash
# upgrade_stack.sh
set -eo pipefail

# =========================================================================
# PADRONIZAÇÃO VISUAL DE CONSOLE & LOGGER SYSTEM (SRE CLI)
# =========================================================================
CLR_BOLD="\e[1m"
CLR_RESET="\e[0m"
CLR_GREEN="\e[32m"
CLR_YELLOW="\e[33m"
CLR_CYAN="\e[36m"
CLR_RED="\e[31m"
CLR_BLUE="\e[34m"

log_info()    { echo -e "${CLR_CYAN}➜ [INFO UPGRADE]${CLR_RESET} $1"; }
log_success() { echo -e "${CLR_GREEN}✔ [SUCESSO UPGRADE]${CLR_RESET} $1"; }
log_warn()    { echo -e "${CLR_YELLOW}⚠️  [ATENÇÃO UPGRADE]${CLR_RESET} $1"; }
log_error()   { echo -e "${CLR_RED}🚨 [ERRO CRÍTICO UPGRADE]${CLR_RESET} $1"; }
log_substep() { echo -e "${CLR_CYAN}  ↳${CLR_RESET} $1"; }
log_header()  {
    echo ""
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_YELLOW}=== [SRE UPGRADE] $1 ===${CLR_RESET}"
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
}

log_header "Atualização Remota Declarativa de Containers e Repositório Git"
echo ""

# =========================================================================
# GOLPE DE MESTRE SRE: COBERTURA FORENSE TRANSVERSAL (DEBUG, TRAP & LOG)
# =========================================================================

# 1. Determina o arquivo físico de log baseado no nome do script em execução
# Nota: Salva dentro da pasta física compartilhada mapeada na arquitetura
SCRIPT_NOME=$(basename "$0" .sh)
LOG_FILE="./volumes/tailscale_state/debug_${SCRIPT_NOME}.log"

# Cria a pasta de logs caso ela ainda não tenha sido montada pelo instalador mestre
mkdir -p "$(dirname "$LOG_FILE")"

# Redirecionamento unificado (Garante gravação síncrona de STDOUT e STDERR no arquivo)
exec > >(tee -a "$LOG_FILE") 2>&1

# 2. Mecanismo de TRAP: Intercepta o sinal de erro (ERR) antes do encerramento por 'set -e'
error_forensic_handler() {
    local linha_erro="$1"
    local comando_falho="$2"
    echo "====================================================================="
    echo "[FALHA CRÍTICA DETECTADA] Ecossistema interrompeu a esteira!"
    echo "➜ Script: $0"
    echo "➜ Linha da Quebra: ${linha_erro}"
    echo "➜ Comando Abortado: ${comando_falho}"
    echo "➜ Detalhes extraídos em: ${LOG_FILE}"
    echo "====================================================================="
}
trap 'error_forensic_handler $LINENO "$BASH_COMMAND"' ERR

# 3. Gatilho XTRACE Dinâmico (Ativado via chamada de terminal: DEBUG=true ./script.sh)
if [ "$DEBUG" = "true" ]; then
    echo "[INFO UPGRADE] Ativando rastreamento de expansão de variáveis (Xtrace)..."
    set -x
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
fi

# Ancoragem do diretório de contexto (Raiz do Projeto)
cd "$(dirname "$0")/../.."
SCRIPT_DIR="$(pwd)"

# 1. Carrega as variáveis de ambiente locais do cliente de forma isolada (SSOT na Raiz)
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a; source "${SCRIPT_DIR}/.env"; set +a
elif [ -f .env ]; then 
    set -a; source .env; set +a
else 
    echo "[ERRO CRÍTICO UPGRADE] .env local ausente." && exit 1
fi

# SRE SecOps: Purgar o cofre de credenciais ao sair do script
cleanup_upgrade() {
    for var in $(compgen -v | grep -E '(_KEY|_SECRET|_PASSWORD|_TOKEN|TS_OAUTH|DB_USER)'); do
        unset "$var" 2>/dev/null || true
    done
}
trap cleanup_upgrade EXIT

# 2. Uso do utilitário flock com a string de tenant devidamente populada e isolada
LOCK_FILE="/var/run/upgrade_stack_${PREFIXO_CONTAINER}.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "[AVISO DE GOVERNANÇA] upgrade_stack.sh já está em execução para o cliente ${PREFIXO_CONTAINER}. Abortando."
    exit 0
fi

# Garante a limpeza do arquivo de lock na saída
cleanup_lock() {
    rm -f "$LOCK_FILE" 2>/dev/null || true
    cleanup_upgrade
}
trap cleanup_lock EXIT

echo "=== [1/5] SRE GUARDRAIL: Backup Físico Pré-Upgrade ==="
# [SRE DOC] Arquitetura de Proteção de Estado (State Rollback):
# NUNCA atualizamos o ambiente (git pull / docker pull) sem antes garantir um snapshot imutável 
# do exato momento anterior. Se a nova versão corromper o banco, o restore_production.sh salva o dia.
bash ./backup_diario.sh || { echo "🚨 [ERRO FATAL] Backup pré-upgrade falhou! Abortando atualização para proteger a produção."; exit 1; }

echo "=== [2/5] Sincronizando Manifestos de Forma Segura ==="
git fetch origin main

# Sanity Check de migrações SQL pendentes na esteira antes de mover o ponteiro HEAD
PENDENT_MIGRATIONS=$(git diff --name-only HEAD origin/main | grep -E "migrations/.*_up.sql" || true)

# SRE Idempotência: Alinha o repositório estritamente com a remote, blindando contra alterações locais fantasmas
git reset --hard origin/main

echo "=== [3/5] Atualizando Imagens e Reconstruindo Componentes Locais ==="
docker compose pull

# [SRE DOC] Graceful Shutdown (Prevenção de Corrupção de Estado):
# O n8n gerencia workflows longos/assíncronos. Se estiver ativo, aguarda dreno seguro antes de desligar.
if [[ "${USE_N8N:-s}" =~ ^[Ss]$ ]] && [ "$(docker inspect -f '{{.State.Running}}' "${PREFIXO_CONTAINER}_n8n" 2>/dev/null)" = "true" ]; then
    docker compose stop -t 60 n8n 2>/dev/null || true
fi

# SRE FIX: Remoção da compilação hardcoded do 'worker-moviepy' (Legado ausente no docker-compose atual).
# Adicionado build genérico focado apenas em imagens locais, caso surjam na nova versão.
docker compose build --pull --quiet

echo "=== [4/5] Executando Processamento Segurado de Migrações SQL ==="
if [ ! -z "$PENDENT_MIGRATIONS" ]; then
    
    # [SRE DOC] Readiness Probe Deterministico para Migrations:
    # Garante que o Postgres esteja aceitando conexões TCP antes de tentar aplicar os DDLs,
    # prevenindo falsos-negativos de falha na migração caso o banco sofra um micro-corte.
    TENTATIVAS_UPG=0
    until docker exec -i ${PREFIXO_CONTAINER}_postgres pg_isready -h 127.0.0.1 -U $DB_USER -d $DB_NAME > /dev/null 2>&1; do
        TENTATIVAS_UPG=$((TENTATIVAS_UPG+1))
        [ "$TENTATIVAS_UPG" -ge 30 ] && { echo "🚨 [ERRO FATAL] Postgres não religou a tempo para a migração."; exit 1; }
        sleep 2
    done

    for migration in $(echo "$PENDENT_MIGRATIONS" | sort); do
        MIGRATION_NAME=$(basename "$migration")

        # Correção SRE: Remoção de escapes literais indesejados nas chamadas de execução do contêiner
        ALREADY_APPLIED=$(docker exec -i ${PREFIXO_CONTAINER}_postgres psql -U $DB_USER -d $DB_NAME -t -c "SELECT 1 FROM schema_version WHERE versao='$MIGRATION_NAME';" | tr -d '[:space:]' || true)

        if [ "$ALREADY_APPLIED" = "1" ]; then
            echo "Migração $MIGRATION_NAME já aplicada anteriormente neste cliente. Pulando..."
            continue
        fi

        echo "Aplicando migração progressiva: $migration"

        # Executa a migration encapsulada em transação implícita única via psql nativo
        if docker exec -i ${PREFIXO_CONTAINER}_postgres psql -U $DB_USER -d $DB_NAME -v "ON_ERROR_STOP=1" --single-transaction < "$migration"; then
            docker exec -i ${PREFIXO_CONTAINER}_postgres psql -U $DB_USER -d $DB_NAME -c "INSERT INTO schema_version (versao) VALUES ('$MIGRATION_NAME') ON CONFLICT DO NOTHING;"
        else
            echo "[ALERTA FATAL] Falha crônica na migração $migration. PostgreSQL aplicou rollback automático."
            exit 1
        fi
    done
else
    echo "Nenhuma alteração estrutural detectada no esquema do banco de dados."
fi

echo "=== [5/5] Recarregando a Malha de Microsserviços de Forma Segura ==="
# [SRE DOC] Recarregamento Atômico (--remove-orphans):
# A flag '--remove-orphans' é vitalícia aqui. Se removermos um serviço do 'docker-compose.yml' 
# na nova versão, esta diretiva garante a destruição física do contêiner obsoleto, 
# evitando vazamento de recursos RAM/CPU e portas em conflito no host.
docker compose up -d --remove-orphans
echo "➜ [SUCESSO UPGRADE] Ecossistema atualizado com zero downtime estrutural."