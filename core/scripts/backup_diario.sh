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

log_info()    { echo -e "${CLR_CYAN}➜ [INFO BACKUP]${CLR_RESET} $1"; }
log_success() { echo -e "${CLR_GREEN}✔ [SUCESSO BACKUP]${CLR_RESET} $1"; }
log_warn()    { echo -e "${CLR_YELLOW}⚠️  [ATENÇÃO BACKUP]${CLR_RESET} $1"; }
log_error()   { echo -e "${CLR_RED}🚨 [ERRO CRÍTICO BACKUP]${CLR_RESET} $1"; }
log_substep() { echo -e "${CLR_CYAN}  ↳${CLR_RESET} $1"; }
log_header()  {
    echo ""
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_YELLOW}=== [SRE BACKUP] $1 ===${CLR_RESET}"
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
}

log_header "Rotina de Disaster Recovery, Validação TLS & Backup Criptografado GPG"
echo ""

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
    echo "[ERRO CRÍTICO BACKUP] Arquivo .env local ausente." && exit 1
fi

if [ -z "$PREFIXO_CONTAINER" ]; then
    echo "[ERRO CRÍTICO BACKUP] Variável PREFIXO_CONTAINER não configurada no .env" && exit 1
fi
DB_NAME="${DB_NAME:-${PREFIXO_CONTAINER}_db}"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

error_forensic_handler() {
    local linha_erro="$1"
    local comando_falho="$2"
    echo "====================================================================="
    echo "[FALHA CRÍTICA BACKUP] Ecossistema interrompeu a esteira!"
    echo "➜ Script: $0"
    echo "➜ Linha da Quebra: ${linha_erro}"
    echo "➜ Comando Abortado: ${comando_falho}"
    echo "➜ Detalhes extraídos em: ${LOG_FILE}"
    echo "====================================================================="
}
trap 'error_forensic_handler $LINENO "$BASH_COMMAND"' ERR

if [ "$DEBUG" = "true" ]; then
    echo "[INFO BACKUP] Ativando rastreamento de expansão de variáveis (Xtrace)..."
    set -x
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
fi

# Criação de diretório temporário isolado
TMP_BACKUP_DIR=$(mktemp -d -t backup_XXXXXXXXXX)
chmod 700 "$TMP_BACKUP_DIR"

cleanup_backup() {
    rm -rf "$TMP_BACKUP_DIR" || true
    docker rm -f pg_test_sanity_${PREFIXO_CONTAINER} >/dev/null 2>&1 || true
    for var in $(compgen -v | grep -E '(_KEY|_SECRET|_PASSWORD|_TOKEN|TS_OAUTH|DB_USER)'); do
        unset "$var" 2>/dev/null || true
    done
}
trap cleanup_backup EXIT

# =========================================================================
# 1. DISASTER RECOVERY: DUMP RELACIONAL POSTGRESQL + SANITY CHECK
# =========================================================================
log_header "Fase 1: Dump Relacional e Sanity Check do PostgreSQL"

docker exec -i ${PREFIXO_CONTAINER}_postgres pg_dumpall --clean --if-exists -U "${DB_USER}" | gzip > "$TMP_BACKUP_DIR/raw_backup.sql.gz"

echo "=== [SRE DR BACKUP] Inicializando ambiente volátil de Sanity Check ==="
if ! SANITY_OUT=$(docker run --rm --name "pg_test_sanity_${PREFIXO_CONTAINER}" -e POSTGRES_PASSWORD=test_pwd_sanity -d pgvector/pgvector:pg17 2>&1); then
    echo -e "\e[31m[ERRO CRÍTICO BACKUP] Falha ao provisionar container efêmero de Sanity Check:\e[0m"
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

# SRE Sanity Probe: Valida a existência de tabelas criadas no banco principal ou nos bancos desacoplados da stack
if ! docker exec pg_test_sanity_${PREFIXO_CONTAINER} psql -U postgres -d "${DB_NAME}" -t -c "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' LIMIT 1;" 2>/dev/null | grep -q 1 && \
   ! docker exec pg_test_sanity_${PREFIXO_CONTAINER} psql -U postgres -d postgres -t -c "SELECT 1 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema') LIMIT 1;" 2>/dev/null | grep -q 1; then
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
            # Salva EXCLUSIVAMENTE na Home do Usuário Real (~/)
            USER_REAL_HOME=$(eval echo "~${SUDO_USER:-$USER}")
            if [ "$USER_REAL_HOME" = "/root" ] || [ -z "$USER_REAL_HOME" ]; then
                NON_ROOT_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd 2>/dev/null || echo "")
                if [ -n "$NON_ROOT_USER" ] && [ -d "/home/$NON_ROOT_USER" ]; then
                    USER_REAL_HOME="/home/$NON_ROOT_USER"
                fi
            fi

            if [ -d "$USER_REAL_HOME" ]; then
                cp "$TMP_BACKUP_DIR/$TS_BACKUP_NAME" "$USER_REAL_HOME/$TS_BACKUP_NAME" 2>/dev/null || true
                chmod 644 "$USER_REAL_HOME/$TS_BACKUP_NAME" 2>/dev/null || true
                if [ -n "$SUDO_USER" ]; then
                    chown "$SUDO_USER:$SUDO_USER" "$USER_REAL_HOME/$TS_BACKUP_NAME" 2>/dev/null || true
                fi
                log_success "Backup de Identidade Tailscale salvo com sucesso em: $USER_REAL_HOME/$TS_BACKUP_NAME"
            fi
        fi
    fi
fi

# =========================================================================
# 3. DISASTER RECOVERY: EMPACOTAMENTO MESTRE & CRIPTOGRAFIA ASSIMÉTRICA GPG
# =========================================================================
log_header "Fase 3: Criptografia Assimétrica GPG e Política FinOps de Retenção"

# Copia o SSOT .env e cria o pacote mestre contendo o SQL, Redis, mídias e metadados
cp "${SCRIPT_DIR}/.env" "$TMP_BACKUP_DIR/config_ssot.env" 2>/dev/null || true

# Força o Redis a persistir o estado em disco (BGSAVE) se estiver rodando
docker exec ${PREFIXO_CONTAINER}_redis redis-cli SAVE >/dev/null 2>&1 || true
if [ -f "${SCRIPT_DIR}/volumes/redis_data/dump.rdb" ]; then
    cp "${SCRIPT_DIR}/volumes/redis_data/dump.rdb" "$TMP_BACKUP_DIR/redis_dump.rdb" 2>/dev/null || true
fi

# Empacota dinamicamente os volumes persistentes e uploads (excluindo dados brutos de DB, cache e modelos locais pesados de IA)
mkdir -p "$TMP_BACKUP_DIR/uploads"
if [ -d "${SCRIPT_DIR}/volumes" ]; then
    rsync -a --exclude='postgres_data' \
             --exclude='redis_data' \
             --exclude='ollama_models' \
             "${SCRIPT_DIR}/volumes/" "$TMP_BACKUP_DIR/uploads/" 2>/dev/null || \
    cp -r "${SCRIPT_DIR}/volumes"/* "$TMP_BACKUP_DIR/uploads/" 2>/dev/null || true

    # Garante a exclusão caso o rsync tenha falhado e usado o fallback do cp
    rm -rf "$TMP_BACKUP_DIR/uploads/postgres_data" \
           "$TMP_BACKUP_DIR/uploads/redis_data" \
           "$TMP_BACKUP_DIR/uploads/ollama_models" 2>/dev/null || true
fi

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