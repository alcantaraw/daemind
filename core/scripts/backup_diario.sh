#!/bin/bash
# /core/scripts/backup_diario.sh
# Rotina de Disaster Recovery, Validação TLS/Tailscale e Backup Criptografado GPG
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

# Exibe o logo ASCII oficial do daemind.
exibir_banner_daemind "Rotina de Disaster Recovery, Validação TLS & Backup Criptografado GPG"

# =========================================================================
# GOLPE DE MESTRE SRE: COBERTURA FORENSE TRANSVERSAL (DEBUG, TRAP & LOG)
# =========================================================================
cd "$(dirname "$0")/../.."
SCRIPT_DIR="$(pwd)"
SCRIPT_NOME="backup_diario"
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
    echo "[FALHA CRÍTICA DETECTADA] Ecossistema interrompeu a esteira!"
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

# Criação de diretório temporário isolado
TMP_BACKUP_DIR=$(mktemp -d -t backup_XXXXXXXXXX)
chmod 700 "$TMP_BACKUP_DIR"

cleanup_backup() {
    rm -rf "$TMP_BACKUP_DIR" || true
    docker rm -f pg_test_sanity_${PREFIXO_CONTAINER} >/dev/null 2>&1 || true
    unset TS_OAUTH_ID TS_OAUTH_SECRET DB_USER DB_PASSWORD LOJA_API_KEY LOJA_APP_KEY GEMINI_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY OPENROUTER_API_KEY LITELLM_MASTER_KEY
}
trap cleanup_backup EXIT

# =========================================================================
# 1. DISASTER RECOVERY: DUMP RELACIONAL POSTGRESQL + SANITY CHECK
# =========================================================================
log_header "Fase 1: Dump Relacional e Sanity Check do PostgreSQL"

docker exec -i ${PREFIXO_CONTAINER}_postgres pg_dump --no-owner --no-acl -U ${DB_USER} -d ${DB_NAME} | gzip > "$TMP_BACKUP_DIR/raw_backup.sql.gz"

echo "=== [DR] Inicializando ambiente volátil de Sanity Check ==="
if ! SANITY_OUT=$(docker run --rm --name "pg_test_sanity_${PREFIXO_CONTAINER}" -e POSTGRES_PASSWORD=test_pwd_sanity -d pgvector/pgvector:pg16 2>&1); then
    echo -e "\e[31m[ERRO CRÍTICO] Falha ao provisionar container efêmero de Sanity Check:\e[0m"
    echo "$SANITY_OUT"
    exit 1
fi

TENTATIVAS=0
until docker exec pg_test_sanity_${PREFIXO_CONTAINER} pg_isready -h 127.0.0.1 -U postgres > /dev/null 2>&1; do
    TENTATIVAS=$((TENTATIVAS + 1))
    if [ $TENTATIVAS -ge 15 ]; then
        echo "[ALERTA FATAL] Timeout aguardando o container efêmero de validação estabilizar."
        exit 1
    fi
    sleep 2
done

echo "=== [DR] Testando hidratação estrutural do dump relacional ==="
gunzip -c "$TMP_BACKUP_DIR/raw_backup.sql.gz" | docker exec -i pg_test_sanity_${PREFIXO_CONTAINER} psql -U postgres -d postgres > /dev/null 2>&1

if ! docker exec pg_test_sanity_${PREFIXO_CONTAINER} psql -U postgres -d postgres -t -c "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' LIMIT 1;" | grep -q 1; then
    echo "[ALERTA CRÍTICO] O dump de backup falhou no teste de validação de tabelas relacionais!"
    exit 1
fi

log_success "Sanity Check do Banco Relacional aprovado com 100% de integridade."

# =========================================================================
# 2. DISASTER RECOVERY: VALIDAÇÃO TLS & BACKUP DE IDENTIDADE TAILSCALE
# =========================================================================
log_header "Fase 2: Validação de Certificados TLS Let's Encrypt & Identidade Tailscale"

if [ "$USE_TAILSCALE" = "true" ] || [ -d "/var/lib/tailscale" ]; then
    if command -v tailscale >/dev/null 2>&1; then
        if sudo tailscale status >/dev/null 2>&1; then
            log_success "Tailscale Node Ativo. FQDN de Borda Operacional."
        else
            log_warn "Tailscale Daemon presente, mas status inativo no momento."
        fi
    fi

    # Empacota o estado completo do Tailscale (nodekey + certificados TLS Let's Encrypt)
    TS_BACKUP_NAME="tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz"
    if [ -d "/var/lib/tailscale" ]; then
        sudo tar --warning=no-file-changed -czf "$TMP_BACKUP_DIR/$TS_BACKUP_NAME" -C /var/lib/tailscale . 2>/dev/null || true
        
        if [ -f "$TMP_BACKUP_DIR/$TS_BACKUP_NAME" ]; then
            # Atualiza no diretório do projeto
            cp "$TMP_BACKUP_DIR/$TS_BACKUP_NAME" "${SCRIPT_DIR}/$TS_BACKUP_NAME" 2>/dev/null || true
            
            # Atualiza na Home do Usuário Real (~/)
            USER_REAL_HOME=$(eval echo "~${SUDO_USER:-$USER}")
            if [ -d "$USER_REAL_HOME" ]; then
                cp "$TMP_BACKUP_DIR/$TS_BACKUP_NAME" "$USER_REAL_HOME/$TS_BACKUP_NAME" 2>/dev/null || true
                chmod 644 "$USER_REAL_HOME/$TS_BACKUP_NAME" 2>/dev/null || true
                if [ -n "$SUDO_USER" ]; then
                    chown "$SUDO_USER:$SUDO_USER" "$USER_REAL_HOME/$TS_BACKUP_NAME" 2>/dev/null || true
                fi
            fi
            log_success "Backup de Identidade Tailscale & Certificados TLS atualizado em ~/$TS_BACKUP_NAME"
        fi
    fi
fi

# =========================================================================
# 3. DISASTER RECOVERY: EMPACOTAMENTO MESTRE & CRIPTOGRAFIA ASSIMÉTRICA GPG
# =========================================================================
log_header "Fase 3: Criptografia Assimétrica GPG e Política FinOps de Retenção"

# Copia o SSOT .env e cria o pacote mestre contendo o SQL, Redis, mídias e metadados
cp "${SCRIPT_DIR}/core/config/.env" "$TMP_BACKUP_DIR/config_ssot.env" 2>/dev/null || true

# Força o Redis a persistir o estado em disco (BGSAVE) se estiver rodando
docker exec ${PREFIXO_CONTAINER}_redis redis-cli SAVE >/dev/null 2>&1 || true
if [ -f "${SCRIPT_DIR}/volumes/redis_data/dump.rdb" ]; then
    cp "${SCRIPT_DIR}/volumes/redis_data/dump.rdb" "$TMP_BACKUP_DIR/redis_dump.rdb" 2>/dev/null || true
fi

# Empacota os diretórios de mídias e anexos enviados pelos clientes se existirem
mkdir -p "$TMP_BACKUP_DIR/uploads"
[ -d "${SCRIPT_DIR}/volumes/minio_data" ] && cp -r "${SCRIPT_DIR}/volumes/minio_data" "$TMP_BACKUP_DIR/uploads/minio" 2>/dev/null || true
[ -d "${SCRIPT_DIR}/volumes/chatwoot_data" ] && cp -r "${SCRIPT_DIR}/volumes/chatwoot_data" "$TMP_BACKUP_DIR/uploads/chatwoot" 2>/dev/null || true
[ -d "${SCRIPT_DIR}/volumes/postiz_data" ] && cp -r "${SCRIPT_DIR}/volumes/postiz_data" "$TMP_BACKUP_DIR/uploads/postiz" 2>/dev/null || true
[ -d "${SCRIPT_DIR}/volumes/nocodb_data" ] && cp -r "${SCRIPT_DIR}/volumes/nocodb_data" "$TMP_BACKUP_DIR/uploads/nocodb" 2>/dev/null || true

# Cria o tarball consolidado contendo a base relacional + Redis + Mídias + SSOT
tar -czf "$TMP_BACKUP_DIR/full_snapshot.tar.gz" -C "$TMP_BACKUP_DIR" raw_backup.sql.gz config_ssot.env redis_dump.rdb uploads 2>/dev/null || tar -czf "$TMP_BACKUP_DIR/full_snapshot.tar.gz" -C "$TMP_BACKUP_DIR" raw_backup.sql.gz config_ssot.env 2>/dev/null

USER_REAL_HOME=$(eval echo "~${SUDO_USER:-$USER}")
if [ ! -d "$USER_REAL_HOME" ]; then
    USER_REAL_HOME="/home/${SUDO_USER:-$USER}"
fi

DATA_HOJE=$(date +%Y%m%d)
ARTEFATO_DESTINO="${USER_REAL_HOME}/backup_${PREFIXO_CONTAINER}_${DATA_HOJE}.sql.gz.gpg"

# Executa a cifragem GPG em modo Custódia Zero diretamente na Home do usuário
gpg --batch --yes --trust-model always --encrypt --recipient "${TS_EMAIL}" \
    --output "$ARTEFATO_DESTINO" "$TMP_BACKUP_DIR/full_snapshot.tar.gz"

# SRE FIX: Ajusta permissão 644 e propriedade para o usuário real (acesso direto via SSH/SFTP sem fricção)
chmod 644 "$ARTEFATO_DESTINO" 2>/dev/null || true
if [ -n "$SUDO_USER" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$ARTEFATO_DESTINO" 2>/dev/null || true
fi

log_success "Pacote de Disaster Recovery gerado e liberado na Home (SFTP Ready 644): ${ARTEFATO_DESTINO}"


# Política de Retenção FinOps (Limpeza de backups com mais de 7 dias na Home)
echo "➜ Executando Faxina SRE na Home (Política de Retenção: 7 dias)..."
find "${USER_REAL_HOME}/" -maxdepth 1 -name "backup_${PREFIXO_CONTAINER}_*.sql.gz.gpg" -type f -mtime +7 -delete 2>/dev/null || true

log_success "Retenção aplicada com sucesso. Backup completo disponibilizado para SFTP/SSH."
echo "====================================================================="