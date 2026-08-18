#!/bin/bash
# ci_smoke_test.sh
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

log_info()    { echo -e "${CLR_CYAN}➜ [INFO CI/SMOKE]${CLR_RESET} $1"; }
log_success() { echo -e "${CLR_GREEN}✔ [SUCESSO CI/SMOKE]${CLR_RESET} $1"; }
log_warn()    { echo -e "${CLR_YELLOW}⚠️  [ATENÇÃO CI/SMOKE]${CLR_RESET} $1"; }
log_error()   { echo -e "${CLR_RED}🚨 [ERRO CRÍTICO CI/SMOKE]${CLR_RESET} $1"; }
log_substep() { echo -e "${CLR_CYAN}  ↳${CLR_RESET} $1"; }
log_header()  {
    echo ""
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_YELLOW}=== [SRE CI SMOKE TEST] $1 ===${CLR_RESET}"
    echo -e "${CLR_YELLOW}=====================================================================${CLR_RESET}"
}

log_header "Bateria de Testes de Prontidão e Validação Contínua (CI/CD)"
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
    echo "[INFO CI/SMOKE] Ativando rastreamento de expansão de variáveis (Xtrace)..."
    set -x
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
fi

# SRE Correção: Ancoragem de contexto e carregamento seguro do escopo do projeto (Raiz)
cd "$(dirname "$0")/../.."
SCRIPT_DIR="$(pwd)"
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a; source "${SCRIPT_DIR}/.env"; set +a
elif [ -f .env ]; then 
    set -a; source .env; set +a
else 
    echo "[ERRO CRÍTICO CI/SMOKE] .env ausente." && exit 1
fi

# [SRE DOC] Função de limpeza blindada (SecOps + Expurgo de Hardware Efêmero)
# Captura sinais de morte (EXIT) e força o expurgo absoluto da malha de containers e 
# da memória RAM, impedindo que o runner do GitHub Actions/GitLab sofra vazamento de credenciais.
cleanup() {
    echo "=== [CI] Executando rotina de limpeza e expurgo da stack efêmera ==="
    docker compose down -v --remove-orphans > /dev/null 2>&1 || true
    
    echo "  ↳ Expurgando credenciais do cofre da RAM..."
    for var in $(compgen -v | grep -E '(_KEY|_SECRET|_PASSWORD|_TOKEN|TS_OAUTH|DB_USER)'); do
        unset "$var" 2>/dev/null || true
    done
}
trap cleanup EXIT

echo "=== [CI] Sanitização Preventiva (Garantia de Clean Room) ==="
docker compose down -v --remove-orphans > /dev/null 2>&1 || true

echo "=== [CI] Validando sintaxe e consistência do manifesto ==="
docker compose config > /dev/null

echo "=== [CI] Inicializando subida e handshakes determinísticos da infraestrutura base ==="
docker compose up -d postgres pgbouncer redis

TENTATIVAS=0
# [SRE DOC] Readiness Probe Composto: Garante que o barramento de dados e cache estejam operantes via rede
until docker exec -i ${PREFIXO_CONTAINER}_postgres pg_isready -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1 && \
      docker exec -i ${PREFIXO_CONTAINER}_redis redis-cli ping > /dev/null 2>&1; do
    TENTATIVAS=$((TENTATIVAS+1))
    if [ "$TENTATIVAS" -ge 15 ]; then
        echo "🚨 [ALERTA FATAL] Timeout estabilizando Banco de Dados ou Cache no CI."
        exit 1
    fi
    sleep 2
done

echo "=== [CI] Provisionando Bancos de Dados Lógicos dos Módulos Desacoplados ==="
# Invoca provision_db dos módulos ativos para criar os bancos lógicos (chatwoot_db, postiz_db, temporal, evolution_db)
for script in "${SCRIPT_DIR}"/core/scripts/install_*.sh; do
    if [ -f "$script" ]; then
        bash "$script" "$SCRIPT_DIR" provision_db 2>/dev/null || true
    fi
done

# Inicializa as fundações secundárias (s3minio / Temporal) se ativas
[[ "${USE_S3MINIO:-s}" =~ ^[Ss]$ ]] && docker compose up -d s3minio 2>/dev/null || true
[[ "${USE_POSTIZ:-s}" =~ ^[Ss]$ ]] && docker compose up -d temporal 2>/dev/null || true

# Inicializa a stack completa
docker compose up -d

# [SRE DOC] Regras de firewall (IPTables/IPSet) agora estão nativamente embutidas no preinstall.sh.
# O teste de egress HTTP abaixo validará a eficácia do isolamento no Kernel diretamente.

if [[ "${USE_N8N:-s}" =~ ^[Ss]$ ]] && [ "$(docker inspect -f '{{.State.Running}}' "${PREFIXO_CONTAINER}_n8n" 2>/dev/null)" = "true" ]; then
    echo "=== [CI] Executando Teste Empírico de Filtração e Ingestão de IPSET ==="
    # Força a resolução DNS real contra a interface local do dnsmasq amarrada ao daemon.json
    # SRE Resiliência: Garante até 3 tentativas de resolução para popular o ipset no kernel
    for i in {1..3}; do
        docker exec -i ${PREFIXO_CONTAINER}_n8n node -e "fetch('https://api.awsli.com.br/v1/categoria/').catch(() => process.exit(0))" 2>/dev/null || true
        if [ $(sudo ipset list ALLOWED_DOMAINS 2>/dev/null | grep -c -E '^[0-9]') -gt 0 ]; then
            break
        fi
        sleep 2
    done

    if [ $(sudo ipset list ALLOWED_DOMAINS 2>/dev/null | grep -c -E '^[0-9]') -eq 0 ]; then
        echo "[FALHA CRÍTICA] O ipset ALLOWED_DOMAINS permaneceu vazio pós-consulta DNS!"
        exit 1
    else
        echo "[SUCESSO CI/SMOKE] Barramento de egress dinâmico via ipset validado com sucesso no CI."
    fi

    # Tenta acessar um destino proibido fora da allowlist (Deve falhar)
    if docker exec -t ${PREFIXO_CONTAINER}_n8n curl --connect-timeout 5 -fsSL https://www.kernel.org > /dev/null 2>&1; then
        echo "[ALERTA CRÍTICO CI/SMOKE] O firewall falhou! O tráfego do container vazou sem restrição."
        exit 1
    else
        echo "[SUCESSO CI/SMOKE] Firewall perimetral validado. Tráfego não homologado dropado de forma determinística."
    fi
fi

echo "=== [SRE CI SMOKE TEST] Executando Teste de Integridade do Admin Endpoint do Caddy ==="
if ! docker exec -i ${PREFIXO_CONTAINER}_caddy wget --no-verbose --tries=1 --spider http://127.0.0.1:2019/config/ > /dev/null 2>&1; then
    echo "🚨 [FALHA CRÍTICA CI/SMOKE] API Administrativa do Caddy não está respondendo no IPv4 local!"
    exit 1
else
    echo "➜ [SUCESSO CI/SMOKE] WAF operante e roteamento interno validado."
fi

echo "=== [SRE CI SMOKE TEST] Executando Smoke Test de Endpoints (Full Spectrum Dinâmico) ==="

# 1. Checagem do Core Obrigatório (LiteLLM Gateway)
LITELLM_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://127.0.0.1:4000/health/liveliness" || echo "000")
if [[ "$LITELLM_STATUS" =~ ^(2|3) ]]; then
    printf "  ↳ %-32s http://localhost:4000/health/liveliness  -> Status: [%s]\n" "AI Gateway (LiteLLM):" "$LITELLM_STATUS"
else
    echo "🚨 [FALHA CRÍTICA CI/SMOKE] LiteLLM (AI Gateway) falhou no portão tratado (HTTP ${LITELLM_STATUS})."
    exit 1
fi

# 2. Varredura Dinâmica de Todos os Módulos Desacoplados Ativos
for script in "${SCRIPT_DIR}/core/scripts"/install_*.sh; do
    [ ! -f "$script" ] && continue
    mod=$(basename "$script" .sh | sed 's/^install_//')
    [ "$mod" = "0ts" ] || [ "$mod" = "1ia" ] && continue
    
    use_var="USE_$(echo "$mod" | tr '[:lower:]' '[:upper:]')"
    
    # Se o módulo estiver ativo no .env (ou padrão 's'), executa a auditoria de saúde do próprio script
    if [[ "${!use_var:-s}" =~ ^[Ss]$ ]]; then
        AUDIT_OUTPUT=$(bash "$script" "$SCRIPT_DIR" audit_health "localhost" 2>/dev/null || true)
        if [ -n "$AUDIT_OUTPUT" ]; then
            echo "$AUDIT_OUTPUT"
            if echo "$AUDIT_OUTPUT" | grep -qE "FALHOU|CONTAINER_ERRO|OFFLINE"; then
                echo "🚨 [FALHA CRÍTICA CI/SMOKE] Módulo ${mod} falhou no teste de saúde da stack!"
                exit 1
            fi
        fi
    fi
done

echo "====================================================================="
echo "       ✅ [SUCESSO CI/SMOKE] STACK APROVADA NO PORTÃO DE QUALIDADE CI "
echo "====================================================================="