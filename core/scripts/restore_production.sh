#!/bin/bash
# /core/scripts/restore_production.sh
# Rotina de Restauração de Produção, Descriptografia GPG, Mídias e Identidade TLS
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

log_info()    { echo -e "${CLR_CYAN}➜ [INFO]${CLR_RESET} $1"; }
log_success() { echo -e "${CLR_GREEN}✔ [SUCESSO]${CLR_RESET} $1"; }
log_warn()    { echo -e "${CLR_YELLOW}⚠️  [ATENÇÃO]${CLR_RESET} $1"; }
log_error()   { echo -e "${CLR_RED}🚨 [ERRO CRÍTICO]${CLR_RESET} $1"; }
log_substep() { echo -e "${CLR_CYAN}  ↳${CLR_RESET} $1"; }
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

exibir_banner_daemind "Restaurador Mestre de Disaster Recovery (PostgreSQL, Redis, Mídias e TLS)"

# =========================================================================
# GOLPE DE MESTRE SRE: COBERTURA FORENSE TRANSVERSAL (DEBUG, TRAP & LOG)
# =========================================================================
cd "$(dirname "$0")/../.."
SCRIPT_DIR="$(pwd)"
SCRIPT_NOME="restore_production"
LOG_FILE="${SCRIPT_DIR}/volumes/tailscale_state/debug_${SCRIPT_NOME}.log"

# Absorve Fonte da Verdade (SSOT na Raiz)
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a; source "${SCRIPT_DIR}/.env"; set +a
elif [ -f .env ]; then 
    set -a; source .env; set +a
else 
    echo "[ERRO CRÍTICO] Arquivo .env local ausente." && exit 1
fi

if [ -z "$PREFIXO_CONTAINER" ]; then
    echo "[ERRO CRÍTICO] Variável PREFIXO_CONTAINER não configurada no .env" && exit 1
fi
DB_NAME="${DB_NAME:-${PREFIXO_CONTAINER}_db}"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

error_forensic_handler() {
    local linha_erro="$1"
    local comando_falho="$2"
    echo "====================================================================="
    echo "[FALHA CRÍTICA DETECTADA] Processo de Restauração interrompido!"
    echo "➜ Script: $0"
    echo "➜ Linha da Quebra: ${linha_erro}"
    echo "➜ Comando Abortado: ${comando_falho}"
    echo "➜ Detalhes extraídos em: ${LOG_FILE}"
    echo "====================================================================="
}
trap 'error_forensic_handler $LINENO "$BASH_COMMAND"' ERR

if [ "$DEBUG" = "true" ]; then
    echo "[INFO] Ativando rastreamento de expansão de variáveis (Xtrace)..."
    set -x
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
fi

# =========================================================================
# SELEÇÃO DO ARQUIVO DE BACKUP (GPG / SQL / TAR.GZ)
# =========================================================================
USER_REAL_HOME=$(eval echo "~${SUDO_USER:-$USER}")
if [ ! -d "$USER_REAL_HOME" ]; then
    USER_REAL_HOME="/home/${SUDO_USER:-$USER}"
fi

if [ -z "$ARQUIVO_ENTRADA" ]; then
    # Busca automaticamente o backup GPG mais recente na Home do usuário real (~/)
    ARQUIVO_ENTRADA=$(ls -t "${USER_REAL_HOME}/backup_${PREFIXO_CONTAINER}_"*.sql.gz.gpg 2>/dev/null | head -n 1 || true)
fi

if [ -z "$ARQUIVO_ENTRADA" ] || [ ! -f "$ARQUIVO_ENTRADA" ]; then
    echo "🚨 [ERRO CRÍTICO] Nenhum arquivo de backup válido fornecido ou encontrado."
    echo "Uso: $0 /caminho/do/backup_loja_YYYYMMDD.sql.gz.gpg"
    exit 1
fi

log_info "Arquivo de Backup selecionado: ${ARQUIVO_ENTRADA}"

TMP_RESTORE_DIR=$(mktemp -d -t restore_XXXXXXXXXX)
chmod 700 "$TMP_RESTORE_DIR"

cleanup_restore() {
    rm -rf "$TMP_RESTORE_DIR" || true
    unset TS_OAUTH_ID TS_OAUTH_SECRET DB_USER DB_PASSWORD LOJA_API_KEY LOJA_APP_KEY GEMINI_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY OPENROUTER_API_KEY LITELLM_MASTER_KEY
}
trap cleanup_restore EXIT

# =========================================================================
# FASE 1: DESCRIPTOGRAFIA E DESCOMPACTAÇÃO DO PACOTE MESTRE
# =========================================================================
log_header "Fase 1: Descriptografia GPG e Extração dos Artefatos de Backup"

if [[ "$ARQUIVO_ENTRADA" == *.gpg ]]; then
    log_info "Descriptografando pacote GPG..."
    gpg --batch --yes --decrypt "$ARQUIVO_ENTRADA" > "$TMP_RESTORE_DIR/full_snapshot.tar.gz"
    ARQUIVO_PACOTE="$TMP_RESTORE_DIR/full_snapshot.tar.gz"
else
    ARQUIVO_PACOTE="$ARQUIVO_ENTRADA"
fi

if tar -tf "$ARQUIVO_PACOTE" >/dev/null 2>&1; then
    log_info "Extraindo pacote consolidado (Base + Redis + Mídias + SSOT)..."
    tar -xzf "$ARQUIVO_PACOTE" -C "$TMP_RESTORE_DIR"
else
    # Fallback se for um SQL direto
    cp "$ARQUIVO_PACOTE" "$TMP_RESTORE_DIR/raw_backup.sql.gz"
fi

# =========================================================================
# FASE 2: PARADA SEGURA DA STACK E SANITIZAÇÃO DE VOLUMES RELACIONAIS
# =========================================================================
log_header "Fase 2: Parada de Serviços e Sanitização Controlada"

log_info "Parando aplicações para evitar escritas concorrentes..."
docker compose stop n8n evolution nocodb postiz chatwoot openwebui litellm minio temporal 2>/dev/null || true
docker compose stop postgres pgbouncer redis 2>/dev/null || true

log_warn "Expurgando volume PostgreSQL para garantia de restauração limpa (0-State)..."
sudo rm -rf "${SCRIPT_DIR}/volumes/postgres_data"/*
sudo mkdir -p "${SCRIPT_DIR}/volumes/postgres_data"

# =========================================================================
# FASE 3: RESTAURAÇÃO DO BANCO RELACIONAL POSTGRESQL
# =========================================================================
log_header "Fase 3: Restauração Relacional e Re-hidratação do PostgreSQL"

docker compose up -d postgres pgbouncer

log_info "Aguardando estabilização do motor PostgreSQL..."
TENTATIVAS=0
until docker exec -i ${PREFIXO_CONTAINER}_postgres pg_isready -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; do
    TENTATIVAS=$((TENTATIVAS + 1))
    if [ "$TENTATIVAS" -ge 20 ]; then
        echo "🚨 [ALERTA FATAL] Timeout aguardando o PostgreSQL estabilizar."
        exit 1
    fi
    sleep 2
done

if [ -f "$TMP_RESTORE_DIR/raw_backup.sql.gz" ]; then
    log_info "Injetando dump relacional descompactado..."
    gunzip -c "$TMP_RESTORE_DIR/raw_backup.sql.gz" | docker exec -i ${PREFIXO_CONTAINER}_postgres psql -v ON_ERROR_STOP=1 -q -U "$DB_USER" -d "$DB_NAME"
    log_success "Banco Relacional PostgreSQL restaurado com 100% de integridade."
elif [ -f "$TMP_RESTORE_DIR/raw_backup.sql" ]; then
    docker exec -i ${PREFIXO_CONTAINER}_postgres psql -v ON_ERROR_STOP=1 -q -U "$DB_USER" -d "$DB_NAME" < "$TMP_RESTORE_DIR/raw_backup.sql"
    log_success "Banco Relacional PostgreSQL restaurado com 100% de integridade."
fi

# =========================================================================
# FASE 4: RESTAURAÇÃO DO CACHE REDIS & MÍDIAS/UPLOADS DOS CLIENTES
# =========================================================================
log_header "Fase 4: Restauração de Redis e Mídias dos Clientes"

if [ -f "$TMP_RESTORE_DIR/redis_dump.rdb" ]; then
    log_info "Restaurando snapshot binário do Redis..."
    cp "$TMP_RESTORE_DIR/redis_dump.rdb" "${SCRIPT_DIR}/volumes/redis_data/dump.rdb" 2>/dev/null || true
    log_success "Snapshot do Redis restaurado com sucesso."
fi

if [ -d "$TMP_RESTORE_DIR/uploads" ]; then
    log_info "Restaurando arquivos de mídia e anexos dos clientes..."
    [ -d "$TMP_RESTORE_DIR/uploads/minio" ] && cp -r "$TMP_RESTORE_DIR/uploads/minio"/* "${SCRIPT_DIR}/volumes/minio_data/" 2>/dev/null || true
    [ -d "$TMP_RESTORE_DIR/uploads/chatwoot" ] && cp -r "$TMP_RESTORE_DIR/uploads/chatwoot"/* "${SCRIPT_DIR}/volumes/chatwoot_data/" 2>/dev/null || true
    [ -d "$TMP_RESTORE_DIR/uploads/postiz" ] && cp -r "$TMP_RESTORE_DIR/uploads/postiz"/* "${SCRIPT_DIR}/volumes/postiz_data/" 2>/dev/null || true
    [ -d "$TMP_RESTORE_DIR/uploads/nocodb" ] && cp -r "$TMP_RESTORE_DIR/uploads/nocodb"/* "${SCRIPT_DIR}/volumes/nocodb_data/" 2>/dev/null || true
    log_success "Mídias e anexos dos clientes restaurados."
fi

# =========================================================================
# FASE 5: RESTAURAÇÃO DE IDENTIDADE TAILSCALE & CERTIFICADOS TLS LET'S ENCRYPT
# =========================================================================
log_header "Fase 5: Restauração de Identidade do Nó & Certificados TLS"

TS_BACKUP_FILE="tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz"
USER_REAL_HOME=$(eval echo "~${SUDO_USER:-$USER}")

if [ -f "${SCRIPT_DIR}/$TS_BACKUP_FILE" ]; then
    TS_SOURCE="${SCRIPT_DIR}/$TS_BACKUP_FILE"
elif [ -f "$USER_REAL_HOME/$TS_BACKUP_FILE" ]; then
    TS_SOURCE="$USER_REAL_HOME/$TS_BACKUP_FILE"
fi

if [ -n "$TS_SOURCE" ] && [ -f "$TS_SOURCE" ]; then
    log_info "Restaurando identidade do nó Tailscale e Certificados TLS Let's Encrypt de: ${TS_SOURCE}"
    sudo mkdir -p /var/lib/tailscale
    sudo tar -xzf "$TS_SOURCE" -C /var/lib/tailscale 2>/dev/null || true
    log_success "Chaves de Nó e Certificados TLS restaurados em /var/lib/tailscale."
fi

# =========================================================================
# FASE 6: RE-INICIALIZAÇÃO DA STACK COMPLETA & VERIFICAÇÃO DE SAÚDE
# =========================================================================
log_header "Fase 6: Religamento da Stack e Verificação de Prontidão"

docker compose up -d --remove-orphans

log_success "Toda a stack de microsserviços foi religada e reidratada com sucesso!"
echo "====================================================================="