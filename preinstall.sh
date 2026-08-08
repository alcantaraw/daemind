#!/bin/bash
# =========================================================================
# SRE: SCRIPT UNIFICADO DE PREPARAÇÃO DO HOST E GERAÇÃO DE AMBIENTE
# =========================================================================
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

# =========================================================================
# COBERTURA FORENSE TRANSVERSAL (DEBUG, TRAP & LOG)
# =========================================================================
if [[ "$0" =~ ^-?(bash|sh)$ ]]; then
    SCRIPT_NOME="preinstall"
else
    SCRIPT_NOME=$(basename "$0" .sh)
fi

LOG_FILE="/tmp/debug_${SCRIPT_NOME}.log"

# Exibe o logo ASCII oficial do daemind.
exibir_banner_daemind "Wizard de Preparação do Host, Kernel Tuning & Coleta de Variáveis"

# =========================================================================
# 🔒 SRE GUARDRAIL: TRAVA DE CONCORRÊNCIA (MUTEX LOCK)
# =========================================================================
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



# =========================================================================
# CRONÔMETRO SRE (Métricas de Latência de Deploy)
# =========================================================================
INICIO_TS=$(date +%s)
export PREINSTALL_START_TS="$INICIO_TS"

TEMPO_PAUSA_INTERATIVA=0
PAUSA_PROFUNDIDADE=0
INICIO_PAUSA_TS=""

pausar_cronometro() {
    if [ "$PAUSA_PROFUNDIDADE" -eq 0 ]; then
        INICIO_PAUSA_TS=$(date +%s)
    fi
    PAUSA_PROFUNDIDADE=$((PAUSA_PROFUNDIDADE + 1))
}

retomar_cronometro() {
    if [ "$PAUSA_PROFUNDIDADE" -gt 0 ]; then
        PAUSA_PROFUNDIDADE=$((PAUSA_PROFUNDIDADE - 1))
        if [ "$PAUSA_PROFUNDIDADE" -eq 0 ] && [ -n "$INICIO_PAUSA_TS" ]; then
            local FIM_PAUSA_TS=$(date +%s)
            local DELTA=$((FIM_PAUSA_TS - INICIO_PAUSA_TS))
            TEMPO_PAUSA_INTERATIVA=$((TEMPO_PAUSA_INTERATIVA + DELTA))
            INICIO_PAUSA_TS=""
        fi
    fi
}

mostrar_duracao() {
    local FIM_TS=$(date +%s)
    local DURACAO_BRUTA=$((FIM_TS - INICIO_TS))
    local DURACAO_LIQUIDA=$((DURACAO_BRUTA - TEMPO_PAUSA_INTERATIVA))
    [ $DURACAO_LIQUIDA -lt 0 ] && DURACAO_LIQUIDA=0
    echo "====================================================================="
    if [ $TEMPO_PAUSA_INTERATIVA -gt 0 ]; then
        echo "⏱️ [SRE METRIC] Duração real da higienização: ${DURACAO_LIQUIDA}s (Total decorrido: ${DURACAO_BRUTA}s | Pausas em perguntas: ${TEMPO_PAUSA_INTERATIVA}s)."
    else
        echo "⏱️ [SRE METRIC] Duração total da higienização: ${DURACAO_LIQUIDA} segundos."
    fi
    echo "📅 Data/Hora de término: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "====================================================================="
}

# Registra o log de início
echo "🚀 [SRE] Início da higienização perimetral: $(date '+%Y-%m-%d %H:%M:%S')"

# SRE Fallback: O 'tee' pode quebrar interfaces interativas que usam /dev/tty.
# Como o Wizard usa 'read', nós ativamos a gravação APENAS para os erros via syslog,
# ou então confiamos na captura nativa do Bash via redirecionamento de quem chamou.
error_forensic_handler() {
    local linha_erro="$1"
    local comando_falho="$2"
    echo "====================================================================="
    echo "🚨 [FALHA CRÍTICA NO KERNEL/SO] A higienização foi interrompida!"
    echo "➜ Linha da Quebra: ${linha_erro}"
    echo "➜ Comando Abortado: ${comando_falho}"
    echo "====================================================================="
}
trap 'error_forensic_handler $LINENO "$BASH_COMMAND"' ERR

# =========================================================================
# ⚙️ DETECÇÃO DE MODO DE EXECUÇÃO (DEBUG)
# =========================================================================
if [ "$DEBUG" = "true" ]; then
    echo "⚠️ [SRE] Modo DEBUG ativado (Trace Detalhado habilitado)."
    set -x
    export PS4='+(${BASH_SOURCE}:${LINENO}): '
fi

# =========================================================================
# 🌐 SRE GUARDRAIL: AUTO-HEALING DE DNS DO HOST
# =========================================================================
# Se uma execução anterior interrompida desligou o StubListener do systemd-resolved,
# a porta 53 pode ter ficado inoperante. Este bloco recupera a resolução de nomes.
if ! getent hosts github.com >/dev/null 2>&1; then
    echo "⚠️ [SRE AUTO-HEALING] Resolução de DNS inoperante. Restaurando conectividade de nomes no Host..."
    sudo sed -i 's/DNSStubListener=no/#DNSStubListener=yes/' /etc/systemd/resolved.conf 2>/dev/null || true
    sudo systemctl restart systemd-resolved 2>/dev/null || true
    sleep 2

    if ! getent hosts github.com >/dev/null 2>&1; then
        echo "  ↳ Injetando resolvers públicos primários (8.8.8.8 e 1.1.1.1) provisoriamente..."
        echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null || true
        echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf >/dev/null || true
    fi

    if getent hosts github.com >/dev/null 2>&1; then
        echo "✔ [SUCESSO] Resolução de DNS do Host recuperada com sucesso!"
    fi
fi

# =========================================================================
# FASE 1: HIGIENIZAÇÃO E PREPARAÇÃO DO SISTEMA OPERACIONAL (HOST ENGINE)
# =========================================================================
echo "=== [SRE] Elevando temporariamente o timeout do sudo para 60 minutos ==="
# [SRE DOC] Por que fazemos isso? 
# O instalador roda no modelo "Ephemeral Bootstrap" (curl | bash). Nesse modelo, 
# o STDIN não interativo impossibilita digitar a senha do sudo no meio do processo. 
# Elevamos o tempo de cache da credencial para garantir que a esteira não congele 
# aguardando um input invisível durante o apt-get ou pull do Docker.
echo "Defaults timestamp_timeout=60" | sudo tee /etc/sudoers.d/custom_sudo_timeout > /dev/null
sudo chmod 0440 /etc/sudoers.d/custom_sudo_timeout

cleanup_sudo_timeout() {
    if [ "$EXECUTAR_INSTALL" != "s" ]; then
        mostrar_duracao
    fi
    if [ -f /etc/sudoers.d/custom_sudo_timeout ]; then
        echo "=== [SRE HARDENING] Revogando timeout estendido do sudo... ==="
        sudo rm -f /etc/sudoers.d/custom_sudo_timeout 2>/dev/null || true
    fi
    rm -f "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup_sudo_timeout EXIT

# [SRE DOC] Prevenção de Congelamento do APT (Headless Mode):
# Em distribuições modernas (Ubuntu 22.04+), atualizações de pacotes base (libc, ssl) 
# disparam uma tela interativa (ncurses) perguntando quais daemons reiniciar.
# As variáveis abaixo forçam o SO a tomar a decisão no modo automático, 
# impedindo que o script congele infinitamente aguardando um "Enter" invisível.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

echo "Memory Overcommit exigido pelo Redis"
# [SRE DOC] Por que overcommit = 1?
# O Redis realiza snapshots em disco (BGSAVE) fazendo um 'fork' do processo. 
# Se o SO estiver no modo estrito (0) e a RAM estiver 50% cheia, o Linux recusa 
# o fork achando que vai faltar memória, derrubando o banco de cache do n8n/Evolution.
if ! grep -q 'vm.overcommit_memory = 1' /etc/sysctl.conf 2>/dev/null; then
    echo "➜ [CONFIGURANDO] Ajustando vm.overcommit_memory = 1 em /etc/sysctl.conf..."
    sudo sed -i '/vm.overcommit_memory/d' /etc/sysctl.conf 2>/dev/null || true
    echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf > /dev/null
    sudo sysctl -p > /dev/null 2>&1 || true
else
    echo "➜ [IDEMPOTÊNCIA] vm.overcommit_memory = 1 já configurado em /etc/sysctl.conf."
fi

if [ ! -f /etc/timezone ]; then
    echo "America/Sao_Paulo" | sudo tee /etc/timezone > /dev/null
fi

# Garante fuso e instala o serviço de tempo leve nativo do Ubuntu
sudo timedatectl set-timezone America/Sao_Paulo 2>/dev/null || true

echo "=== [SRE] Sincronização Atômica de Relógio (Fase 1: Kernel) ==="
HTTP_NOW=$(curl -sI --max-time 5 https://1.1.1.1 2>/dev/null | grep -i '^Date:' | sed 's/^[Dd]ate: //g' || true)

if [ -n "$HTTP_NOW" ]; then
    sudo date -s "$HTTP_NOW" >/dev/null
    echo "➜ [SUCESSO] Relógio do Kernel recalibrado via HTTP: $(date)"
else
    echo "⚠️ [AVISO] Não foi possível obter o horário via HTTP."
fi

echo "=== [SRE] Verificando se há locks ativos do APT/DPKG no sistema ==="
# [SRE DOC] Prevenção de "Race Condition" e Lock do APT:
# Se o 'unattended-upgrades' ou um 'apt-get' anterior travou ou está rodando em background,
# o script aguarda até 120s e encerra processos zumbis do APT que prendem os arquivos de lock.
TENTATIVAS_APT_LOCK=0
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
      sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
      sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    TENTATIVAS_APT_LOCK=$((TENTATIVAS_APT_LOCK + 1))
    echo "  ↳ O APT está ocupado com outro processo em segundo plano (Tentativa ${TENTATIVAS_APT_LOCK}/24). Aguardando 5s..."
    sleep 5
    if [ "$TENTATIVAS_APT_LOCK" -ge 24 ]; then
        echo "  ⚠️ [SRE AUTO-HEALING] Lock do APT retido por mais de 120s. Finalizando processos zumbis do APT/unattended-upgrades..."
        sudo systemctl stop unattended-upgrades 2>/dev/null || true
        sudo killall -9 apt apt-get dpkg 2>/dev/null || true
        sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
        sudo dpkg --configure -a 2>/dev/null || true
        break
    fi
done

echo "=== [SRE] Detectando e corrigindo dinamicamente pacotes corrompidos ==="
PACOTES_QUEBRADOS=$(dpkg -l | awk '/^i[FHRU]/ {print $2}')
if [ -n "$PACOTES_QUEBRADOS" ]; then 
    echo "  ↳ Removendo resíduos de Kernel/Pacotes quebrados silenciosamente..."
    echo "$PACOTES_QUEBRADOS" | sudo xargs -r env DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y -qq > /dev/null 2>&1 < /dev/null
fi

sudo chmod -x /etc/kernel/prerm.d/vboxadd /etc/kernel/postinst.d/vboxadd 2>/dev/null || true
# SRE FIX: Idempotência na configuração do GRUB
if ! grep -q 'GRUB_DISABLE_OS_PROBER=true' /etc/default/grub 2>/dev/null; then
    sudo sed -i '/GRUB_DISABLE_OS_PROBER/d' /etc/default/grub 2>/dev/null || true
    echo "GRUB_DISABLE_OS_PROBER=true" | sudo tee -a /etc/default/grub > /dev/null
fi
# [SRE DOC] Resolução de Conflitos de Configuração (Conffile Prompt):
# Se o provedor de Cloud alterou um arquivo padrão (ex: grub, sshd_config), o apt-get 
# pausa a instalação perguntando: "Manter a versão local ou usar a do mantenedor (Y/I/N/O/D/Z)?".
# A flag '--force-confold' instrui o Kernel a SEMPRE manter o arquivo existente, 
# garantindo que a conexão SSH não caia e o deploy não trave.
sudo dpkg --configure -a --force-confold > /dev/null 2>&1 < /dev/null || true
sudo apt-get --fix-broken install -y -qq -o Dpkg::Options::="--force-confold" > /dev/null 2>&1 < /dev/null || true
sudo apt-get autoremove --purge -y -qq > /dev/null 2>&1 < /dev/null || true
sudo apt-get clean > /dev/null 2>&1 < /dev/null || true
ATIVO=$(uname -r)

for dir in /usr/lib/modules/*-generic; do
    if [ -d "$dir" ] && [ "$(basename "$dir")" != "$ATIVO" ]; then
        sudo rm -rf "$dir" 2>/dev/null || true
    fi
done

echo "=== [SRE] Configurando chaves e repositórios oficiais do Docker ==="
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 2. INTELIGÊNCIA PERIÓDICA: Verifica se os índices foram atualizados nas últimas 24 horas
echo "=== [SRE] Verificando recência dos índices do APT ==="
JANELA_CORTE_SEGUNDOS=86400 # 24 horas
ULTIMA_ATUALIZACAO=0
NOSSO_STAMP="/var/log/sre_factory_apt_update.stamp"

# SRE Fallback: Tenta ler o nosso próprio carimbo ou o nativo do sistema
if [ -f "$NOSSO_STAMP" ]; then
    ULTIMA_ATUALIZACAO=$(stat -c %Y "$NOSSO_STAMP")
elif [ -f /var/lib/apt/periodic/update-success-stamp ]; then
    # Margem de segurança caso o sistema nativo resolva criar
    ULTIMA_ATUALIZACAO=$(stat -c %Y /var/lib/apt/periodic/update-success-stamp)
fi

AGORA=$(date +%s)
TEMPO_DECORRIDO=$((AGORA - ULTIMA_ATUALIZACAO))

# Valida se o stamp é recente E se o diretório de listas do APT realmente possui dados
LISTAS_APT=$(ls /var/lib/apt/lists/ 2>/dev/null | grep -v '^partial$' | head -n 1 || true)

if [ $TEMPO_DECORRIDO -le $JANELA_CORTE_SEGUNDOS ] && [ -n "$LISTAS_APT" ]; then
    echo "  ↳ [PULADO] Índices atualizados há menos de 24 horas e presentes no disco."
else
    echo "  ↳ [EXECUÇÃO] Índices obsoletos, ausentes ou limpos. Atualizando barramento..."
    if ! sudo apt-get update -qq -o Dpkg::Lock::Timeout=120 2>/dev/null; then
        echo "  ⚠️ [SRE AUTO-HEALING] Detectado travamento residual de lock no APT update. Destravando e retransmitindo..."
        sudo killall -9 apt-get apt 2>/dev/null || true
        sudo rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend 2>/dev/null || true
        sudo apt-get update -qq -o Dpkg::Lock::Timeout=60
    fi
    sudo touch "$NOSSO_STAMP"
fi

echo "=== [SRE] Validando status e versões dos pacotes requeridos ==="
PACOTES_REQUERIDOS=(
    chrony wget iputils-ping curl openssl iptables ipset cron dnsmasq apt-transport-https
    ca-certificates gnupg tcpdump net-tools lsb-release jq git vim
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    bind9-utils sysstat htop dnsutils systemd-timesyncd
)

PACOTES_PARA_INSTALAR=()
for pacote in "${PACOTES_REQUERIDOS[@]}"; do
    if ! dpkg -l "$pacote" &>/dev/null; then
        echo "  ↳ [MISSING] $pacote não está instalado. Adicionado à fila."
        PACOTES_PARA_INSTALAR+=("$pacote")
    else
        VERSAO_INSTALADA=$(dpkg-query -W -f='${Version}' "$pacote" 2>/dev/null)
        VERSAO_CANDIDATA=$(apt-cache policy "$pacote" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
        
        # SRE FIX: Ignora os 'UP-TO-DATE' e filtra o falso-positivo '(none)' de pacotes virtuais
        if [ "$VERSAO_INSTALADA" != "$VERSAO_CANDIDATA" ] && [ -n "$VERSAO_CANDIDATA" ] && [ "$VERSAO_CANDIDATA" != "(none)" ]; then
            echo "  ↳ [UPDATE] $pacote possui atualização disponível ($VERSAO_INSTALADA -> $VERSAO_CANDIDATA). Adicionado à fila."
            PACOTES_PARA_INSTALAR+=("$pacote")
        fi
    fi
done

if [ ${#PACOTES_PARA_INSTALAR[@]} -gt 0 ]; then
    echo "➜ Habilitando repositório 'universe' e atualizando barramento de pacotes..."
    sudo add-apt-repository universe -y 2>/dev/null || true
    sudo apt-get update -qq -o Dpkg::Lock::Timeout=120
    sudo touch "$NOSSO_STAMP"

    echo "➜ Executando provisionamento silencioso de ${#PACOTES_PARA_INSTALAR[@]} pacote(s)..."
    # SRE FIX: O sudo -E herda as proteções do topo. > /dev/null 2>&1 mata 100% da poluição visual do Dpkg/Needrestart
    sudo -E apt-get install -y -qq -o Dpkg::Lock::Timeout=120 -o Dpkg::Options::="--force-confold" "${PACOTES_PARA_INSTALAR[@]}" > /dev/null 2>&1 < /dev/null
    sudo apt-get clean > /dev/null 2>&1 || true
    
    # SRE FIX: Desativa o dnsmasq caso o apt-get o tenha iniciado com config vazia no SO limpo
    sudo systemctl stop dnsmasq 2>/dev/null || true
else
    echo "➜ [INFO] Todos os pacotes já estão atualizados. Pulando etapa do apt-get."
fi

# =========================================================================
# 📥 CLONAGEM DO REPOSITÓRIO OFICIAL (DISCO LOCAL /opt/daemind)
# =========================================================================
TARGET_DIR="/opt/daemind"
REPO_URL="https://github.com/alcantaraw/daemind.git"
CURRENT_GIT_BRANCH=""
if [ -d "${TARGET_DIR}/.git" ]; then
    CURRENT_GIT_BRANCH=$(cd "${TARGET_DIR}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
fi
REPO_BRANCH="${TARGET_BRANCH:-${CURRENT_GIT_BRANCH:-test}}"

# SRE GUARDRAIL: Auto-Healing de DNS estrito antes do git clone
if ! getent hosts github.com >/dev/null 2>&1; then
    echo "⚠️ [SRE AUTO-HEALING] Resolução de DNS oscilou pós-APT. Injetando resolvers de contingência..."
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null || true
    echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf >/dev/null || true
fi

echo "=== [SRE] Clonando/Sincronizando repositório oficial (Branch: ${REPO_BRANCH}) em ${TARGET_DIR} ==="
sudo mkdir -p "${TARGET_DIR}"

if [ -d "${TARGET_DIR}/.git" ]; then
    echo "➜ Repositório local já existente em ${TARGET_DIR}. Forçando atualização para origin/${REPO_BRANCH} (git fetch + reset --hard)..."
    (cd "${TARGET_DIR}" && sudo git fetch --all -q && sudo git checkout "${REPO_BRANCH}" 2>/dev/null || sudo git checkout -b "${REPO_BRANCH}" "origin/${REPO_BRANCH}" 2>/dev/null || true && sudo git reset --hard "origin/${REPO_BRANCH}" -q)
elif [ -d "${TARGET_DIR}" ] && [ "$(ls -A "${TARGET_DIR}" 2>/dev/null)" ]; then
    echo "➜ Diretório ${TARGET_DIR} já existe. Forçando sobrescrita limpa com a branch '${REPO_BRANCH}'..."
    TEMP_CLONE=$(mktemp -d)
    sudo git clone -b "${REPO_BRANCH}" -q "${REPO_URL}" "${TEMP_CLONE}"
    sudo cp -rf "${TEMP_CLONE}"/* "${TARGET_DIR}/" 2>/dev/null || true
    sudo cp -rf "${TEMP_CLONE}"/.git "${TARGET_DIR}/" 2>/dev/null || true
    sudo rm -rf "${TEMP_CLONE}"
else
    echo "➜ Clonando branch '${REPO_BRANCH}' de ${REPO_URL} em ${TARGET_DIR}..."
    sudo git clone -b "${REPO_BRANCH}" -q "${REPO_URL}" "${TARGET_DIR}"
fi

# SRE HARDENING: Sanitização de Produção (Remove conteúdos não operacionais, preservando o .git)
echo "=== [SRE] Sanitizando ambiente de produção (removendo artefatos não-core) ==="
sudo rm -rf "${TARGET_DIR}/docs" "${TARGET_DIR}/README.md" "${TARGET_DIR}/LICENSE" 2>/dev/null || true

# Garante o diretório de configurações no repositório oficial
sudo mkdir -p "${TARGET_DIR}/core/config"


# Resolução dinâmica da home do usuário (se rodando via sudo, usa $SUDO_USER home)
USER_HOME="${HOME:-/root}"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER" 2>/dev/null || echo "/home/$SUDO_USER")
fi

# SRE CACHE DISCOVERY: Resolução dinâmica do arquivo de cache do wizard
if [ -n "${WIZARD_CACHE_FILE:-${CACHE_FILE:-}}" ] && [ -f "${WIZARD_CACHE_FILE:-${CACHE_FILE:-}}" ]; then
    CACHE_WIZARD_FILE="${WIZARD_CACHE_FILE:-${CACHE_FILE:-}}"
elif [ -n "${WIZARD_CACHE_NAME:-${CACHE_NAME:-}}" ] && [ -f "${USER_HOME}/.daemind_wizard_cache_${WIZARD_CACHE_NAME:-$CACHE_NAME}.env" ]; then
    CACHE_WIZARD_FILE="${USER_HOME}/.daemind_wizard_cache_${WIZARD_CACHE_NAME:-$CACHE_NAME}.env"
elif [ -f "${USER_HOME}/.daemind_wizard_cache.env" ]; then
    CACHE_WIZARD_FILE="${USER_HOME}/.daemind_wizard_cache.env"
else
    # Procura por qualquer arquivo de cache do padrão ~/.daemind_wizard_cache*.env (seleciona o mais recente)
    CACHE_WIZARD_FILE=$(ls -t "${USER_HOME}"/.daemind_wizard_cache*.env 2>/dev/null | grep -v '\.tmp$' | head -n 1 || echo "${USER_HOME}/.daemind_wizard_cache.env")
fi

save_wizard_cache() {
    local var="$1"
    local val="$2"
    if [ -n "$var" ] && [ -n "$val" ]; then
        val=$(echo "$val" | tr -d '\r' | xargs 2>/dev/null || echo "$val")
        grep -v "^${var}=" "$CACHE_WIZARD_FILE" 2>/dev/null > "${CACHE_WIZARD_FILE}.tmp" || true
        mv "${CACHE_WIZARD_FILE}.tmp" "$CACHE_WIZARD_FILE" 2>/dev/null || true
        echo "${var}=\"${val}\"" >> "$CACHE_WIZARD_FILE"
        sed -i 's/\r$//' "$CACHE_WIZARD_FILE" 2>/dev/null || true
        chmod 600 "$CACHE_WIZARD_FILE" 2>/dev/null || true
        [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && chown "$SUDO_USER:$SUDO_USER" "$CACHE_WIZARD_FILE" 2>/dev/null || true
    fi
}

coletar_sn() {
    local prompt_msg="$1"
    local var_name="$2"
    local default_val="${3:-s}"
    local is_mandatory="${4:-false}"
    local input=""

    pausar_cronometro 2>/dev/null || true
    while true; do
        if [ -t 0 ] || [ -c /dev/tty ]; then
            read -p "➜ ${prompt_msg} (s/n) [${default_val}]: " input < /dev/tty || input=""
        else
            input=""
        fi
        input=$(echo "$input" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)
        if [ -z "$input" ]; then
            input="$default_val"
        fi

        case "$input" in
            s|sim|S|SIM|y|yes|Y|YES)
                eval "${var_name}='s'"
                save_wizard_cache "$var_name" "s" 2>/dev/null || true
                break
                ;;
            n|nao|não|N|NAO|NÃO|no|NO)
                eval "${var_name}='n'"
                save_wizard_cache "$var_name" "n" 2>/dev/null || true
                break
                ;;
            *)
                echo -e "\e[31m[ERRO] Resposta inválida. Por favor, responda com 's' (sim) ou 'n' (não).\e[0m"
                ;;
        esac
    done
    retomar_cronometro 2>/dev/null || true
}

if [ -f "$CACHE_WIZARD_FILE" ]; then
    echo ""
    echo -e "\e[32m✔ [CACHE] Respostas de sessão anterior encontradas em ${CACHE_WIZARD_FILE}\e[0m"
    
    # SRE FIX: Carrega preliminarmente o cache para ler RESP_REUSE ou AUTO_REUSE_CACHE se salvas no arquivo/ambiente
    sed -i 's/\r$//' "$CACHE_WIZARD_FILE" 2>/dev/null || true
    set +e
    source "$CACHE_WIZARD_FILE" 2>/dev/null
    set -e

    RESP_REUSE="${AUTO_REUSE_CACHE:-${RESP_REUSE:-}}"
    if [ -n "$RESP_REUSE" ]; then
        echo -e "\e[32m✔ [AUTO-REUSE] Reutilização de cache ativada (${RESP_REUSE}).\e[0m"
    else
        coletar_sn "Deseja reutilizar as respostas da sessão anterior?" RESP_REUSE "s" "false"
    fi

    if [ "$RESP_REUSE" = "n" ]; then
        rm -f "$CACHE_WIZARD_FILE" "${CACHE_WIZARD_FILE}.tmp" 2>/dev/null || true
        unset ROUTING_CHOICE EMPRESA CLIENTE_NOME CLIENTE_SOBRENOME CLIENTE_EMAIL TS_OAUTH_SECRET TS_OAUTH_ID CUSTOM_DOMAIN CUSTOM_EVO_DOMAIN TLS_CHOICE CADDY_PROTOCOL DB_PASSWORD DB_PASSWORD2 OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY DEEPSEEK_API_KEY OPENROUTER_API_KEY RESP_PAGA RESP_GEMINI_FREE RESP_OPENAI RESP_CLAUDE RESP_GEMINI RESP_DEEPSEEK FREE_GEMINI REDE_CHOICE BASE_IP EXECUTAR_INSTALL RESP_REUSE USE_MINIO STORAGE_MODE OPT_STORAGE S3_ENDPOINT_EXT S3_REGION_EXT S3_ACCESS_KEY_EXT S3_SECRET_KEY_EXT S3_CHATWOOT_BUCKET_EXT S3_POSTIZ_BUCKET_EXT
        echo -e "\e[33m➜ Cache resetado. O wizard coletará todas as informações novamente.\e[0m"
    else
        echo -e "\e[32m➜ Restaurando dados salvos da sessão anterior...\e[0m"
        sed -i 's/\r$//' "$CACHE_WIZARD_FILE" 2>/dev/null || true
        set -a
        source "$CACHE_WIZARD_FILE" 2>/dev/null || true
        set +a
        # SRE FIX: Higieniza retorno de carro (\r) e espaços de todas as variáveis restauradas do cache
        ROUTING_CHOICE=$(echo "${ROUTING_CHOICE:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        EMPRESA=$(echo "${EMPRESA:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        CLIENTE_NOME=$(echo "${CLIENTE_NOME:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        CLIENTE_SOBRENOME=$(echo "${CLIENTE_SOBRENOME:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        CLIENTE_EMAIL=$(echo "${CLIENTE_EMAIL:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        TS_OAUTH_SECRET=$(echo "${TS_OAUTH_SECRET:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        TS_OAUTH_ID=$(echo "${TS_OAUTH_ID:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        DB_PASSWORD=$(echo "${DB_PASSWORD:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        DB_PASSWORD2=$(echo "${DB_PASSWORD2:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        OPENROUTER_API_KEY=$(echo "${OPENROUTER_API_KEY:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        GEMINI_API_KEY=$(echo "${GEMINI_API_KEY:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
    fi
fi

echo ""
echo "=== [SRE] Topologia de Borda & Roteamento ==="
echo "1) Tailscale Mesh & Funnel (Padrão SRE - Zero-Trust, Túneis Seguros)"
echo "2) Bring Your Own DNS (BYODNS - Cloudflare Tunnels, NPM, IP Fixo)"
if [ -n "$ROUTING_CHOICE" ]; then
    echo -e "\e[32m✔ [CACHE] Modelo de exposição restaurado: ${ROUTING_CHOICE}\e[0m"
else
    pausar_cronometro
    while true; do
        read -p "➜ Escolha o modelo de exposição (1 ou 2): " ROUTING_CHOICE < /dev/tty
        ROUTING_CHOICE=$(echo "${ROUTING_CHOICE:-}" | tr -d '\r' | xargs 2>/dev/null || echo "")
        case "$ROUTING_CHOICE" in
            1|2) 
                save_wizard_cache "ROUTING_CHOICE" "$ROUTING_CHOICE"
                break 
                ;;
            *) echo -e "\e[31m[ERRO] Opção inválida. Digite 1 ou 2.\e[0m" ;;
        esac
    done
    retomar_cronometro
fi

export ROUTING_CHOICE # Exporta estado da máquina

if [ "$ROUTING_CHOICE" = "1" ]; then
    USE_TAILSCALE="true"
else
    USE_TAILSCALE="false"
fi

echo "=== [SRE] Configurando resolvedor de rede perimetral (dnsmasq) no Host ==="
# SRE FIX: Libera a porta 53/UDP do systemd-resolved APENAS quando o dnsmasq for configurado
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
sudo sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
sudo systemctl restart systemd-resolved 2>/dev/null || true

# [SRE DOC] Polimorfismo de DNS: Apenas injetamos os domínios do Tailscale no IPSet 
# de Egress se o motor da VPN estiver ativo, mantendo o dnsmasq 100% estrito.
cat << EOC | sudo tee /etc/dnsmasq.conf > /dev/null
listen-address=127.0.0.1,172.17.0.1
bind-dynamic
server=8.8.8.8
server=1.1.1.1

# IPSET ALLOWED DOMAINS (BASE)
ipset=/n8n.io/ALLOWED_DOMAINS
ipset=/api.n8n.io/ALLOWED_DOMAINS
ipset=/api.awsli.com.br/ALLOWED_DOMAINS
ipset=/letsencrypt.org/ALLOWED_DOMAINS
ipset=/lencr.org/ALLOWED_DOMAINS
ipset=/zerossl.com/ALLOWED_DOMAINS
ipset=/graph.facebook.com/ALLOWED_DOMAINS
ipset=/licencas.fornecedor.com.br/ALLOWED_DOMAINS
ipset=/npmjs.org/ALLOWED_DOMAINS
ipset=/registry.npmjs.org/ALLOWED_DOMAINS
ipset=/registry.yarnpkg.com/ALLOWED_DOMAINS
ipset=/github.com/ALLOWED_DOMAINS
ipset=/raw.githubusercontent.com/ALLOWED_DOMAINS
ipset=/huggingface.co/ALLOWED_DOMAINS
ipset=/api-inference.huggingface.co/ALLOWED_DOMAINS
ipset=/cdn-lfs.huggingface.co/ALLOWED_DOMAINS
ipset=/api.openai.com/ALLOWED_DOMAINS
ipset=/openai.azure.com/ALLOWED_DOMAINS
ipset=/cognitiveservices.azure.com/ALLOWED_DOMAINS
ipset=/api.anthropic.com/ALLOWED_DOMAINS
ipset=/generativelanguage.googleapis.com/ALLOWED_DOMAINS
ipset=/aiplatform.googleapis.com/ALLOWED_DOMAINS
ipset=/www.googleapis.com/ALLOWED_DOMAINS
ipset=/api.deepseek.com/ALLOWED_DOMAINS
ipset=/openrouter.ai/ALLOWED_DOMAINS
EOC

if [ "$USE_TAILSCALE" = "true" ]; then
    if ! grep -q "ts.net" /etc/dnsmasq.conf 2>/dev/null; then
        cat << EOC_TS | sudo tee -a /etc/dnsmasq.conf > /dev/null
# IPSET ALLOWED DOMAINS (TAILSCALE)
ipset=/tailscale.com/ALLOWED_DOMAINS
ipset=/tailscale.io/ALLOWED_DOMAINS
ipset=/ts.net/ALLOWED_DOMAINS
ipset=/controlplane.tailscale.com/ALLOWED_DOMAINS
EOC_TS
    fi
fi

if ! grep -q "bogus-priv" /etc/dnsmasq.conf 2>/dev/null; then
    cat << EOC_END | sudo tee -a /etc/dnsmasq.conf > /dev/null

domain-needed
bogus-priv
EOC_END
fi

IF_DOCKER_ACTIVE=$(systemctl is-active docker 2>/dev/null || echo "inactive")
if [ -f /etc/docker/daemon.json ] && grep -q "172.17.0.1" /etc/docker/daemon.json 2>/dev/null && [ "$IF_DOCKER_ACTIVE" = "active" ]; then
    echo "➜ [IDEMPOTÊNCIA] Docker Engine e dnsmasq já vinculados ao Gateway local. Preservando containers."
    sudo systemctl restart dnsmasq 2>/dev/null || true
else
    echo "=== [SRE] Vinculando Docker Engine ao Gateway local ==="
    cat << EOD | sudo tee /etc/docker/daemon.json > /dev/null
{ 
  "dns": ["172.17.0.1", "1.1.1.1"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOD
    echo "=== [SRE] Reiniciando daemons de rede e virtualização do Host ==="
    sudo systemctl restart dnsmasq docker
fi

if [ -n "$SUDO_USER" ]; then
    sudo usermod -aG docker "$SUDO_USER"
fi

if [ "$ROUTING_CHOICE" = "1" ]; then
    echo  "=== [SRE] Instalação do Tailscale Nativo no Host ==="
    if ! command -v tailscale &>/dev/null; then
        echo "  ↳ Binário ausente. Baixando e instalando (Modo Seguro)..."
        sudo rm -f /etc/resolv.conf
        echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
        
        # SRE FIX: Remoção do silenciador destrutivo (< /dev/null) que causava o curl: (23) SIGPIPE.
        # Injetado env NONINTERACTIVE=1 para obrigar o script da Tailscale a não exigir TTY.
        if ! curl -fsSL --retry 3 --connect-timeout 15 https://tailscale.com/install.sh | sudo env NONINTERACTIVE=1 sh > /tmp/debug_tailscale.log 2>&1; then
            echo "🚨 [ERRO CRÍTICO] Falha ao instalar Tailscale. Verifique: tail -f /tmp/debug_tailscale.log"
            exit 1
        fi
    else
        echo "  ↳ [INFO] Tailscale já instalado no host."
    fi

    if grep -q 'TS_NO_LOGS_NO_SUPPORT="true"' /etc/default/tailscaled 2>/dev/null; then
        echo "➜ [IDEMPOTÊNCIA] Hardening de privacidade do Tailscale já ativado."
    else
        echo "➜ [SRE] Aplicando Hardening de Privacidade no Tailscale..."
        sudo touch /etc/default/tailscaled
        sudo sed -i '/TS_NO_LOGS_NO_SUPPORT/d' /etc/default/tailscaled 2>/dev/null || true
        echo 'TS_NO_LOGS_NO_SUPPORT="true"' | sudo tee -a /etc/default/tailscaled > /dev/null
        sudo systemctl enable --now tailscaled > /dev/null 2>&1 || true
        sudo systemctl restart tailscaled || true
    fi
    sleep 2
else
    echo -e "\e[36m➜ [SRE SKIP] Modo BYODNS Selecionado. Ignorando instalação de dependências VPN.\e[0m"
fi

if [ -f /swapfile ] && grep -q '/swapfile' /etc/fstab 2>/dev/null; then
    echo "➜ [IDEMPOTÊNCIA] Memória Virtual Swap (4GB) já estruturada e ativa."
else
    echo "=== [SRE] Criando Memória Virtual de Amortecimento (Swap 4GB) ==="
    sudo swapoff -a 2>/dev/null || true
    sudo rm -f /swapfile /swap.img 2>/dev/null || true
    sudo sed -i '/swap/d' /etc/fstab 2>/dev/null || true

    sudo fallocate -l 4G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile >/dev/null 2>&1
    sudo swapon /swapfile >/dev/null 2>&1
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
    echo "➜ [SUCESSO] Swap 4GB criado e registrado no fstab."
fi

echo "=== [SRE] Limpeza final antes do install.sh ==="
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo rm -f "$NOSSO_STAMP"

echo "=== [SRE] Gerenciamento Inteligente de Rede (DHCP -> Static Fix) ==="

# 1. Identifica a interface física principal de saída
INTERFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n 1)

# Guardrail: Se a interface estiver DOWN/NO-CARRIER, força o NetworkManager/systemd-networkd a acordar a placa
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip link show | grep -E '^[0-9]+: e' | cut -d: -f2 | tr -d ' ' | head -n 1)
    echo "  ↳ Interface em estado DOWN detectada ($INTERFACE). Forçando link UP via dhclient..."
    sudo ip link set "$INTERFACE" up || true
    sudo dhclient -v "$INTERFACE" 2>/dev/null || true
    sleep 3
fi

# 2. Captura o IP, Máscara e Gateway que o roteador/DHCP entregou
IP_CIDR=$(ip -4 addr show dev "$INTERFACE" 2>/dev/null | grep inet | awk '{print $2}' | head -n 1)
GATEWAY=$(ip -4 route show default 2>/dev/null | awk '{print $3}' | head -n 1)
MAC_ADDR=$(ip link show dev "$INTERFACE" 2>/dev/null | grep link/ether | awk '{print $2}' | head -n 1)

# SRE Fallback: Se mesmo assim não pegar IP, força solicitação DHCP temporária
if [ -z "$IP_CIDR" ]; then
    echo "  ↳ Solicitando renovação de lease DHCP na interface $INTERFACE..."
    sudo dhclient -r "$INTERFACE" 2>/dev/null || true
    sudo dhclient "$INTERFACE" 2>/dev/null || true
    sleep 2
    IP_CIDR=$(ip -4 addr show dev "$INTERFACE" | grep inet | awk '{print $2}' | head -n 1)
    GATEWAY=$(ip -4 route show default | awk '{print $3}' | head -n 1)
fi

echo "  ↳ Interface Identificada: $INTERFACE"
echo "  ↳ MAC Address Fixo:       $MAC_ADDR"
echo "  ↳ IP Válido Atribuído:    $IP_CIDR"
echo "  ↳ Gateway de Rede:       $GATEWAY"

if [ -z "$IP_CIDR" ] || [ -z "$GATEWAY" ]; then
    echo "[ERRO CRÍTICO] A interface $INTERFACE não recebeu IP via DHCP!"
    exit 1
fi

if [ -f /etc/netplan/99-static-sre.yaml ] && grep -q "$IP_CIDR" /etc/netplan/99-static-sre.yaml 2>/dev/null; then
    echo "➜ [IDEMPOTÊNCIA] Regras de rede estática amarradas ao MAC já aplicadas ($IP_CIDR)."
else
    sudo mkdir -p /etc/netplan/backup
    sudo mv /etc/netplan/*.yaml /etc/netplan/backup/ 2>/dev/null || true

    sudo cat << EON | sudo tee /etc/netplan/99-static-sre.yaml > /dev/null
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      match:
        macaddress: "$MAC_ADDR"
      set-name: "$INTERFACE"
      dhcp4: no
      addresses:
        - $IP_CIDR
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
EON

    sudo chmod 600 /etc/netplan/99-static-sre.yaml
    echo "➜ Aplicando regras estáticas de rede amarradas ao MAC..."
    sudo netplan apply 2>/dev/null || true
    echo "➜ [OK] IP $IP_CIDR fixado com sucesso e blindado contra trocas!"
fi

# =========================================================================
# === [SRE] Personalização do Banner MOTD de Boas-Vindas (Login) ===
# =========================================================================
echo "=== [SRE] Configurando mensagem customizada de boas-vindas no login ==="

# 1. Silencia TODOS os scripts nativos poluídos do Ubuntu (header, news, help, unminimize, etc)
sudo chmod -x /etc/update-motd.d/* 2>/dev/null || true

# 2. Cria o script dinâmico do MOTD SRE sem duplicar unidades e capturando usuário/FQDN reais
sudo cat << 'EOM' | sudo tee /etc/update-motd.d/99-sre-banner > /dev/null
#!/bin/bash

# Cores ANSI
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Captura do Usuário Real que fez Login (Trata o contexto do MOTD/PAM)
USUARIO_LOGADO="${PAM_USER:-$(logname 2>/dev/null || who am i | awk '{print $1}')}"
[ -z "$USUARIO_LOGADO" ] && USUARIO_LOGADO=$(whoami)

# Hostname e FQDN Inteligente
HOST_SHORT=$(hostname -s)
DOMAIN_NAME=$(dnsdomainname 2>/dev/null || domainname 2>/dev/null || echo "")
if [ -n "$DOMAIN_NAME" ] && [ "$DOMAIN_NAME" != "(none)" ]; then
    HOST_FQDN="${HOST_SHORT}.${DOMAIN_NAME}"
else
    HOST_FQDN=$(hostname -f 2>/dev/null)
    [ "$HOST_FQDN" = "$HOST_SHORT" ] && HOST_FQDN="${HOST_SHORT}.local"
fi

# Interface e IP Principal
MAIN_IFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n 1)
[ -z "$MAIN_IFACE" ] && MAIN_IFACE="eth0"
ETH_IP=$(ip -4 addr show dev "$MAIN_IFACE" 2>/dev/null | grep inet | awk '{print $2}' || echo "Sem Link/Offline")

# Versão do Sistema Operacional (Ubuntu) e Kernel
UBUNTU_VER=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
KERNEL_VER=$(uname -r)

# Hardware
CPU_MODEL=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//' | xargs)
[ -z "$CPU_MODEL" ] && CPU_MODEL="Virtual Processor"
CPU_CORES=$(nproc)

# Formatador de Unidades sem duplo reemplaço (Gi -> GB / Mi -> MB)
format_unit() {
    echo "$1" | sed -E 's/([0-9.]+)[Gg]i?/\1GB/g; s/([0-9.]+)[Mm]i?/\1MB/g'
}

MEM_TOTAL=$(format_unit "$(free -h | awk '/Mem:/ {print $2}')")
SWAP_TOTAL=$(format_unit "$(free -h | awk '/Swap:/ {print $2}')")

DISKO_TOTAL=$(format_unit "$(df -h / | awk 'NR==2 {print $2}')")
DISKO_DISP=$(format_unit "$(df -h / | awk 'NR==2 {print $4}')")
DISKO_USADO_PCT=$(df -h / | awk 'NR==2 {print $5}')

echo -e "${CYAN}=====================================================================${NC}"
echo -e "${WHITE}           🚀 BEM-VINDO AO AMBIENTE DE INFRAESTRUTURA SRE            ${NC}"
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${YELLOW} 🐧 Sistema Operacional: ${NC}${WHITE}${UBUNTU_VER} (${KERNEL_VER})${NC}"
echo -e "${YELLOW} 👤 Usuário Autenticado: ${NC}${WHITE}${USUARIO_LOGADO}${NC}"
echo -e "${YELLOW} 🖥️  Hostname / FQDN:    ${NC}${WHITE}${HOST_FQDN}${NC}"
echo -e "${YELLOW} 🌐 Endereço IP (${MAIN_IFACE}): ${NC}${GREEN}${ETH_IP}${NC}"
echo -e "${CYAN}---------------------------------------------------------------------${NC}"
echo -e "${YELLOW} 🧩 Processador (CPU):   ${NC}${WHITE}${CPU_MODEL}${NC}"
echo -e "${YELLOW} ⚡ Núcleos (Cores):      ${NC}${WHITE}${CPU_CORES} vCPUs${NC}"
echo -e "${YELLOW} 🧠 Memória RAM Total:    ${NC}${WHITE}${MEM_TOTAL}${NC}"
echo -e "${YELLOW} 🔄 Memória Swap:         ${NC}${WHITE}${SWAP_TOTAL}${NC}"
echo -e "${YELLOW} 💾 Partição Raiz (/):    ${NC}${WHITE}${DISKO_TOTAL}${NC} Total | ${GREEN}${DISKO_DISP}${NC} Livre (${DISKO_USADO_PCT} usado)"
echo -e "${CYAN}=====================================================================${NC}"
echo ""
EOM

sudo chmod +x /etc/update-motd.d/99-sre-banner

echo "=== [SRE] Limpando rastros da sessão ==="
# 1. Limpa o history do root (o contexto atual da execução)
sudo bash -c "cat /dev/null > /root/.bash_history 2>/dev/null || true"

# 2. SRE Discovery: Limpa o history do operador real que invocou o sudo
if [ -n "$SUDO_USER" ]; then
    USER_HOME_REAL=$(eval echo "~$SUDO_USER")
    cat /dev/null > "$USER_HOME_REAL/.bash_history" 2>/dev/null || true
fi

# 3. Limpa o buffer temporário de comandos na memória RAM da sessão atual
history -c 2>/dev/null || true

# =========================================================================
# FASE 2: GERADOR DE AMBIENTE MULTI-CLIENTE (SRE FACTORY)
# =========================================================================
echo ""
echo -e "\e[36m=====================================================================\e[0m"
echo -e "\e[36m          [SRE FACTORY] GERADOR DE AMBIENTE MULTI-CLIENTE            \e[0m"
echo -e "\e[36m=====================================================================\e[0m"

# SRE FIX: Função dedicada a forçar validação estrita de respostas Sim/Não [s/n]
coletar_sn() {
    local prompt="$1"
    local var_name="$2"
    local default_val="${3:-n}" # 's' ou 'n'
    local save_cache="${4:-true}"
    
    local current_val="${!var_name}"
    if [ -n "$current_val" ]; then
        echo -e "\e[32m✔ [CACHE] $prompt: ${current_val}\e[0m"
        return 0
    fi

    pausar_cronometro
    local prompt_suffix="[s/N]"
    [ "$default_val" = "s" ] && prompt_suffix="[S/n]"

    local input_val
    while true; do
        read -p "➜ $prompt $prompt_suffix: " input_val < /dev/tty || true
        input_val="${input_val:-$default_val}"
        
        local input_lc
        input_lc=$(echo "$input_val" | tr '[:upper:]' '[:lower:]')

        if [ "$input_lc" = "s" ] || [ "$input_lc" = "n" ]; then
            eval "$var_name=\"$input_lc\""
            if [ "$save_cache" = "true" ]; then
                save_wizard_cache "$var_name" "$input_lc"
            fi
            break
        else
            echo -e "\e[31m[ERRO CRÍTICO] Resposta inválida! Digite apenas 's' ou 'n' (ou pressione Enter para o padrão '$default_val').\e[0m"
        fi
    done
    retomar_cronometro
}

# SRE FIX: Todas as leituras de input usam < /dev/tty para funcionar em execuções de Stream (curl | bash)
coletar_input() {
    local prompt="$1"
    local var_name="$2"
    local is_secret="$3"
    local regex="$4"
    local exact_length="$5"
    local is_optional="$6" # "true" se o usuario puder pular o campo em caso de invalidez
    
    local cached_val="${!var_name}"
    if [ -n "$cached_val" ]; then
        if [ "$is_secret" = "true" ]; then
            echo -e "\e[32m✔ [CACHE] $prompt: ********\e[0m"
        else
            echo -e "\e[32m✔ [CACHE] $prompt: $cached_val\e[0m"
        fi
        return 0
    fi

    pausar_cronometro
    while true; do
        if [ "$is_secret" = "true" ]; then
            echo -ne "➜ $prompt: "
            input_val=""
            # [SRE DOC] Captura de Keystrokes (Blindagem SecOps):
            # Não usamos o comando genérico 'read -s' pois ele não exibe feedback na tela.
            # Este loop intercepta o teclado char-a-char no TTY. Ele mascara a senha com '*', 
            # não grava no ~/.bash_history e não expõe a credencial no comando 'ps aux'.
            while IFS= read -r -s -n 1 char < /dev/tty; do
                # Tratamento de final de linha (Enter)
                if [[ -z "$char" ]]; then
                    break
                fi
                # Tratamento cross-platform de Backspace (Linux \177 vs Mac \b)
                if [[ "$char" == $'\177' || "$char" == $'\b' ]]; then
                    if [ ${#input_val} -gt 0 ]; then
                        input_val="${input_val%?}"
                        echo -ne "\b \b"
                    fi
                else
                    input_val+="$char"
                    echo -ne "*"
                fi
            done
            echo ""
        else
            read -p "➜ $prompt: " input_val < /dev/tty
        fi

        if [ -z "$input_val" ]; then
            if [ "$is_optional" = "true" ]; then
                eval "$var_name=\"\""
                break
            fi
            echo -e "\e[31m[ERRO] Este campo é obrigatório!\e[0m"
            continue
        fi

        if [ -n "$exact_length" ] && [ "${#input_val}" -ne "$exact_length" ]; then
            echo -e "\e[31m[ERRO CRÍTICO] O campo exige EXATAMENTE $exact_length caracteres! Enviado: ${#input_val}\e[0m"
            if [ "$is_optional" = "true" ]; then
                local RESP_SKIP=""
                coletar_sn "  ↳ Deseja pular a configuração desta chave?" RESP_SKIP "n" "false"
                if [ "$RESP_SKIP" = "s" ]; then
                    eval "$var_name=\"\""
                    break
                fi
            fi
            continue
        fi

        if [ -n "$regex" ] && [[ ! "$input_val" =~ $regex ]]; then
            echo -e "\e[31m[ERRO CRÍTICO] O formato da chave digitada não atende ao padrão esperado!\e[0m"
            if [ "$is_optional" = "true" ]; then
                local RESP_SKIP=""
                coletar_sn "  ↳ Deseja pular a configuração desta chave?" RESP_SKIP "n" "false"
                if [ "$RESP_SKIP" = "s" ]; then
                    eval "$var_name=\"\""
                    break
                fi
            fi
            continue
        fi

        eval "$var_name=\"\$input_val\""
        save_wizard_cache "$var_name" "$input_val"
        break
    done
    retomar_cronometro
}

coletar_input "ID da Empresa Cliente (Max 12 chars, Ex: microsoft apple nvidia)" EMPRESA "false" "^.{1,12}$" ""
coletar_input "Nome do Cliente/Responsável (Ex: Joao)" CLIENTE_NOME "false" "" ""
coletar_input "Sobrenome do Cliente/Responsável (Ex: Silva)" CLIENTE_SOBRENOME "false" "" ""
coletar_input "Email Oficial do Cliente/Tailnet (Ex: contato@loja.com)" CLIENTE_EMAIL "false" "^[^@]+@[^@]+\.[^@]+$" ""

echo ""
echo -e "\e[33m>>> Processando automação perimetral para '$EMPRESA'...\e[0m"
echo "---------------------------------------------------------------------"

if [ "$ROUTING_CHOICE" = "1" ]; then
    USE_TAILSCALE="true"
    CUSTOM_DOMAIN=""
    CUSTOM_EVO_DOMAIN=""
    CADDY_PROTOCOL="https"
    while true; do
        coletar_input "Tailscale OAuth Client Secret (63 chars)" TS_OAUTH_SECRET "true" "" "63"
        if [[ "$TS_OAUTH_SECRET" =~ tskey-client-([A-Za-z0-9]{17})- ]]; then
            TS_OAUTH_ID="${BASH_REMATCH[1]}"
            save_wizard_cache "TS_OAUTH_ID" "$TS_OAUTH_ID"
            break
        else
            echo -e "\e[31m[ERRO CRÍTICO] O formato do Tailscale OAuth Client Secret é inválido!\e[0m"
        fi
    done
else
    USE_TAILSCALE="false"
    TS_OAUTH_SECRET="bypass_sec"
    TS_OAUTH_ID="bypass_id"
    save_wizard_cache "TS_OAUTH_SECRET" "$TS_OAUTH_SECRET"
    save_wizard_cache "TS_OAUTH_ID" "$TS_OAUTH_ID"
    
    echo ""
    echo -e "\e[33m=== [SRE] Configuração BYODNS (Traga seu próprio DNS) ===\e[0m"
    coletar_input "Domínio do Painel Mestre (Ex: painel.empresa.com)" CUSTOM_DOMAIN "false" "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" ""
    coletar_input "Domínio da API WhatsApp (Ex: api.empresa.com)" CUSTOM_EVO_DOMAIN "false" "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" ""
    
    echo -e "\e[36mComo o tráfego chegará no servidor local?\e[0m"
    echo "1) Offload Externo (Cloudflare Proxy / Nginx Proxy Manager) -> Caddy sobe em HTTP."
    echo "2) Caddy SSL Nativo (Let's Encrypt) -> Exige IP Fixo apontado diretamente para a VM."
    coletar_input "Escolha o tratamento TLS (1-2)" TLS_CHOICE "false" "^[1-2]$" ""
    [ "$TLS_CHOICE" = "1" ] && CADDY_PROTOCOL="http" || CADDY_PROTOCOL="https"
    save_wizard_cache "CADDY_PROTOCOL" "$CADDY_PROTOCOL"
fi

while true; do
    echo ""
    echo -e "\e[33m=== [SRE] Definição da Senha Mestra (URI-Safe) ===\e[0m"
    echo -e "\e[36mPara garantir a integridade da malha de containers (Connection Strings):\e[0m"
    echo -e "\e[36m ↳ Tamanho: \e[37mEntre 8 e 12 caracteres\e[0m"
    echo -e "\e[36m ↳ Requisitos: \e[37mPelo menos 1 Maiúscula e 1 Número\e[0m"
    echo -e "\e[36m ↳ Especiais PERMITIDOS: \e[32m- _ * ~ ^\e[0m"
    echo -e "\e[36m ↳ Especiais PROIBIDOS:  \e[31m@ # & / : ? = % |\e[0m"
    echo "---------------------------------------------------------------------"
    
    coletar_input "Digite a Senha Mestra do Cliente" DB_PASSWORD "true" "" ""

    # 1. Validação de Tamanho (8 a 12 caracteres)
    if [[ ${#DB_PASSWORD} -lt 8 ]] || [[ ${#DB_PASSWORD} -gt 12 ]]; then
        echo -e "\e[31m[ERRO] A senha possui ${#DB_PASSWORD} caracteres. Ela deve ter obrigatoriamente entre 8 e 12.\e[0m"
        continue
    fi

    # 2. Validação de Letra Maiúscula
    if [[ ! "$DB_PASSWORD" =~ [A-Z] ]]; then
        echo -e "\e[31m[ERRO] A senha deve conter pelo menos uma letra MAIÚSCULA.\e[0m"
        continue
    fi

    # 3. Validação de Número
    if [[ ! "$DB_PASSWORD" =~ [0-9] ]]; then
        echo -e "\e[31m[ERRO] A senha deve conter pelo menos um NÚMERO.\e[0m"
        continue
    fi

    # 4. SRE GUARDRAIL: Prevenção de Quebra de URI (Connection Strings)
    if [[ "$DB_PASSWORD" =~ [@#\&/:\?=\|%] ]]; then
        echo -e "\e[31m[ERRO CRÍTICO] Você usou um caractere reservado de URL!\e[0m"
        echo -e "\e[31m➜ Isso corrompe as strings de conexão do Postgres. Use apenas: - _ * ~ ^\e[0m"
        continue
    fi

    # 5. Validação de Caractere Especial Seguro
    if [[ ! "$DB_PASSWORD" =~ [-_*~^] ]]; then
        echo -e "\e[31m[ERRO] A senha deve conter pelo menos um CARACTERE ESPECIAL SEGURO (Ex: - _ * ~ ^).\e[0m"
        continue
    fi

    coletar_input "Confirme a Senha Mestra" DB_PASSWORD2 "true" "" ""
    if [ "$DB_PASSWORD" = "$DB_PASSWORD2" ]; then 
        save_wizard_cache "DB_PASSWORD2" "$DB_PASSWORD2"
        break
    fi
    
    echo -e "\e[31m[ERRO CRÍTICO] As senhas digitadas não conferem! Tente novamente.\e[0m"
done

# MOMENTANEAMENTE DESATIVADO (LOJA INTEGRADA)
# coletar_input "Chave de API Loja Integrada (20 chars)" LOJA_API_KEY "true" "" "20"
# coletar_input "Chave de Aplicação Loja Integrada (36 chars - UUID)" LOJA_APP_KEY "true" "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$" "36"
LOJA_API_KEY=""
LOJA_APP_KEY=""
# coletar_input "Chave Privada WireGuard Proton VPN (44 chars)" PROTON_WG_PRIV "true" "" "44"

echo ""
echo -e "\e[33m=== [SRE] Wizard de Inteligência Artificial (Gateway Múltiplo) ===\e[0m"

# 1. Inicialização de Estado (Preserva valores do cache se existirem)
: "${GEMINI_API_KEY:=""}"
: "${OPENAI_API_KEY:=""}"
: "${ANTHROPIC_API_KEY:=""}"
: "${DEEPSEEK_API_KEY:=""}"
: "${OPENROUTER_API_KEY:=""}"

# 2. Árvore de Decisão de Negócio
coletar_sn "Quer configurar Provedor de IA pago (OpenAI, Anthropic, Gemini, DeepSeek)?" RESP_PAGA "n"

if [[ "$RESP_PAGA" =~ ^[Ss]$ ]]; then
    echo -e "\e[36m  ↳ Responda [s/n] para os provedores que deseja ativar:\e[0m"
    
    coletar_sn "  - Configurar o ChatGPT (OpenAI)?" RESP_OPENAI "n"
    if [[ "$RESP_OPENAI" =~ ^[Ss]$ ]]; then coletar_input "Chave de API da OpenAI (sk-proj-...)" OPENAI_API_KEY "true" "^sk-proj-" "" "true"; fi

    coletar_sn "  - Configurar o Claude (Anthropic)?" RESP_CLAUDE "n"
    if [[ "$RESP_CLAUDE" =~ ^[Ss]$ ]]; then coletar_input "Chave de API da Anthropic (sk-ant-...)" ANTHROPIC_API_KEY "true" "^sk-ant-" "" "true"; fi

    coletar_sn "  - Configurar o Gemini (Google)?" RESP_GEMINI "n"
    if [[ "$RESP_GEMINI" =~ ^[Ss]$ ]]; then coletar_input "Chave de API do Gemini (AIzaSy... ou AQ...)" GEMINI_API_KEY "true" "^(AQ\.|AIzaSy)" "" "true"; fi

    coletar_sn "  - Configurar o DeepSeek?" RESP_DEEPSEEK "n"
    if [[ "$RESP_DEEPSEEK" =~ ^[Ss]$ ]]; then coletar_input "Chave de API do DeepSeek (sk-...)" DEEPSEEK_API_KEY "true" "^sk-" "" "true"; fi

    echo -e "\e[36m➜ Para garantir a resiliência (Fallback), o OpenRouter será configurado como segurança.\e[0m"
else
    echo -e "\e[36m➜ Operação Custo Zero ativada. O OpenRouter será a fundação exclusiva da arquitetura.\e[0m"
fi

# 3. Coleta Mandatória (Executada independentemente do caminho escolhido acima)
coletar_input "Chave de API do OpenRouter (MANDATÓRIO - sk-or-v1-...)" OPENROUTER_API_KEY "true" "^sk-or-v1-" "" "false"

# =========================================================================
# SRE FINOPS: ARQUITETURA INTELIGENTE DE ARMAZENAMENTO DE MÍDIAS (PROFILING)
# =========================================================================
echo ""
echo -e "\e[33m=== [SRE FinOps] Arquitetura de Armazenamento de Mídias e Arquivos ===\e[0m"

# Executa a suíte autotune.sh para profiling de hardware unificado no .env temporário/definitivo
AUTOTUNE_SCRIPT="${RAIZ_REPO}/core/scripts/autotune.sh"
[ ! -f "$AUTOTUNE_SCRIPT" ] && AUTOTUNE_SCRIPT="./core/scripts/autotune.sh"

if [ -f "$AUTOTUNE_SCRIPT" ]; then
    bash "$AUTOTUNE_SCRIPT" "$NOME_ARQUIVO" >/dev/null 2>&1 || true
    if [ -f "$NOME_ARQUIVO" ]; then
        set +e
        source "$NOME_ARQUIVO" 2>/dev/null
        set -e
    fi
fi

# Extrai métricas reais através do autotune.sh
TOTAL_CPUS_HOST="${SYSTEM_TOTAL_CPUS:-$(nproc 2>/dev/null || echo 4)}"
TOTAL_RAM_MB_HOST="${SYSTEM_TOTAL_RAM_MB:-$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)}"
TOTAL_RAM_GB_HOST=$(( (TOTAL_RAM_MB_HOST + 512) / 1024 ))

# SRE GUARDRAIL: Avalia se o hardware é modesto (< 4 cores OU < 8GB RAM)
IS_MODEST_SERVER=false
if [ "$TOTAL_CPUS_HOST" -lt 4 ] || [ "$TOTAL_RAM_GB_HOST" -lt 8 ]; then
    IS_MODEST_SERVER=true
fi

# SRE GUARDRAIL: Permite bypass manual via variável de ambiente (AUTO_STORAGE_MODE, STORAGE_MODE ou USE_MINIO)
STORAGE_MODE="${AUTO_STORAGE_MODE:-${STORAGE_MODE:-}}"

if [ -z "$STORAGE_MODE" ]; then
    if [ -n "${AUTO_USE_MINIO:-}" ] || [ -n "${USE_MINIO:-}" ]; then
        VAL_MINIO="${AUTO_USE_MINIO:-$USE_MINIO}"
        if [[ "$VAL_MINIO" =~ ^[Ss]$ ]]; then
            STORAGE_MODE="minio"
        else
            STORAGE_MODE="local"
        fi
    fi
fi

if [ -n "$STORAGE_MODE" ]; then
    echo -e "\e[32m✔ [AUTO-STORAGE] Modo de Armazenamento lido do ambiente/cache (STORAGE_MODE=${STORAGE_MODE}).\e[0m"
else
    if [ "$IS_MODEST_SERVER" = "true" ]; then
        echo -e "\e[33m⚠️ [SRE ADVICE] Host Modesto Detectado: ${TOTAL_CPUS_HOST} Cores | ${TOTAL_RAM_GB_HOST} GB RAM.\e[0m"
        echo -e "\e[36m  ↳ Recomendação: Armazenamento Local Direto (Economiza 1GB RAM & CPU do MinIO).\e[0m"
        DEFAULT_OPTION="1"
    else
        echo -e "\e[32m✔ [SRE ADVICE] Host de Alta Performance: ${TOTAL_CPUS_HOST} Cores | ${TOTAL_RAM_GB_HOST} GB RAM.\e[0m"
        echo -e "\e[36m  ↳ Recomendação: MinIO S3 Soberano (Gerenciamento centralizado de mídias).\e[0m"
        DEFAULT_OPTION="2"
    fi

    echo ""
    echo -e "Escolha o modo de armazenamento desejado para a stack:"
    echo -e "  [1] Armazenamento Local Direto (Sem MinIO - Salva em disco ./volumes/*_data, 0MB RAM extra)"
    echo -e "  [2] MinIO S3 Soberano (Local - Provisiona container MinIO dedicado com S3 API)"
    echo -e "  [3] Provedor S3 Cloud Externo (AWS S3 / Cloudflare R2 / DigitalOcean Spaces)"
    
    coletar_input "Digite a opção desejada (1, 2 ou 3)" OPT_STORAGE "false" "^[123]$" "$DEFAULT_OPTION" "false"

    case "$OPT_STORAGE" in
        1)
            STORAGE_MODE="local"
            USE_MINIO="n"
            ;;
        2)
            STORAGE_MODE="minio"
            USE_MINIO="s"
            ;;
        3)
            STORAGE_MODE="s3_external"
            USE_MINIO="n"
            ;;
        *)
            STORAGE_MODE="local"
            USE_MINIO="n"
            ;;
    esac
fi

# Mapeia USE_MINIO para retrocompatibilidade
if [ "$STORAGE_MODE" = "minio" ]; then
    USE_MINIO="s"
else
    USE_MINIO="n"
fi

if [ "$STORAGE_MODE" = "s3_external" ]; then
    echo ""
    echo -e "\e[36m➜ Configuração do Provedor S3 Cloud Remoto (AWS / R2 / DigitalOcean):\e[0m"
    coletar_input "Endpoint do S3 (ex: https://<account-id>.r2.cloudflarestorage.com ou https://s3.us-east-1.amazonaws.com)" S3_ENDPOINT_EXT "true" "^https?://" "" "false"
    coletar_input "Região do S3 (ex: us-east-1 ou auto)" S3_REGION_EXT "false" "" "us-east-1" "false"
    coletar_input "Access Key ID do S3" S3_ACCESS_KEY_EXT "true" "" "" "false"
    coletar_input "Secret Access Key do S3" S3_SECRET_KEY_EXT "true" "" "" "true"
    coletar_input "Nome do Bucket do Chatwoot" S3_CHATWOOT_BUCKET_EXT "false" "" "chatwoot" "false"
    coletar_input "Nome do Bucket do Postiz" S3_POSTIZ_BUCKET_EXT "false" "" "postiz" "false"
fi

save_wizard_cache "STORAGE_MODE" "$STORAGE_MODE"
save_wizard_cache "USE_MINIO" "$USE_MINIO"
if [ "$STORAGE_MODE" = "s3_external" ]; then
    save_wizard_cache "S3_ENDPOINT_EXT" "$S3_ENDPOINT_EXT"
    save_wizard_cache "S3_REGION_EXT" "$S3_REGION_EXT"
    save_wizard_cache "S3_ACCESS_KEY_EXT" "$S3_ACCESS_KEY_EXT"
    save_wizard_cache "S3_SECRET_KEY_EXT" "$S3_SECRET_KEY_EXT"
    save_wizard_cache "S3_CHATWOOT_BUCKET_EXT" "$S3_CHATWOOT_BUCKET_EXT"
    save_wizard_cache "S3_POSTIZ_BUCKET_EXT" "$S3_POSTIZ_BUCKET_EXT"
fi

# =========================================================================
# SRE: OFERTA ATIVA DE TIER GRATUITO (FinOps & UX)
# =========================================================================
if [ -z "$GEMINI_API_KEY" ]; then
    echo ""
    echo -e "\e[36m➜ DICA SRE: Os modelos Google Gemini Flash e Gemma são 100% gratuitos via Google AI Studio.\e[0m"
    coletar_sn "  ↳ Deseja configurar uma chave gratuita do Google Gemini agora para poupar custos?" RESP_GEMINI_FREE "n"
    
    if [[ "$RESP_GEMINI_FREE" =~ ^[Ss]$ ]]; then
        echo -e "\e[36m    (Crie a sua chave em 3 cliques aqui: https://aistudio.google.com/app/apikey)\e[0m"
        coletar_input "Cole a Chave de API do Google Gemini (AIzaSy... ou AQ...)" GEMINI_API_KEY "true" "^(AQ\.|AIzaSy)" "" "true"
        FREE_GEMINI="1"
        save_wizard_cache "FREE_GEMINI" "1"
    fi
fi

if [[ "$RESP_GEMINI_FREE" =~ ^[Ss]$ ]]; then
    FREE_GEMINI="1"
elif [[ "$RESP_GEMINI" =~ ^[Ss]$ ]]; then
    FREE_GEMINI="0"
else
    : "${FREE_GEMINI:="0"}"
fi
save_wizard_cache "FREE_GEMINI" "$FREE_GEMINI"

echo ""
echo -e "\e[33m=== [SRE] Topologia de Rede (Isolamento CIDR) ===\e[0m"
echo "1) 172.25.0.x (Padrão / Container)"
echo "2) 10.50.0.x  (AWS VPC Peering Seguro)"
echo "3) 192.168.200.x (On-Premise Seguro)"
echo "4) Customizado (Ex: 10.99.0)"
if [ -n "${REDE_CHOICE:-}" ]; then
    echo -e "\e[32m✔ [CACHE] Opção de sub-rede restaurada: ${REDE_CHOICE}\e[0m"
else
    coletar_input "Escolha a base da rede (1-4)" REDE_CHOICE "false" "^[1-4]$" ""
fi

case "$REDE_CHOICE" in
    1) BASE_IP="172.25.0" ;;
    2) BASE_IP="10.50.0" ;;
    3) BASE_IP="192.168.200" ;;
    4) 
       if [ -z "${BASE_IP:-}" ]; then
           coletar_input "Digite os 3 primeiros octetos (Ex: 10.99.0)" BASE_IP "false" "^([0-9]{1,3}\.){2}[0-9]{1,3}$" ""
       fi
       ;;
    *)
       REDE_CHOICE="1"
       BASE_IP="172.25.0"
       ;;
esac
save_wizard_cache "REDE_CHOICE" "$REDE_CHOICE"
save_wizard_cache "BASE_IP" "$BASE_IP"

IP_NETWORK_SUBNET="${BASE_IP}.0/24"
IP_NETWORK_GATEWAY="${BASE_IP}.1"
IP_REDIS="${BASE_IP}.2"
IP_NOCODB="${BASE_IP}.3"
IP_N8N="${BASE_IP}.4"
IP_EVOLUTION="${BASE_IP}.5"
IP_CADDY="${BASE_IP}.6"
IP_CHATWOOT="${BASE_IP}.7"
IP_POSTIZ="${BASE_IP}.8"
IP_POSTGRES="${BASE_IP}.9"
IP_PGBOUNCER="${BASE_IP}.10"
IP_TEMPORAL="${BASE_IP}.11"
IP_MINIO="${BASE_IP}.12"
IP_LITELLM="${BASE_IP}.13"
IP_OPENWEBUI="${BASE_IP}.14"

NOME_ARQUIVO="${EMPRESA}.env"

echo "  ↳ Ativando persistência de relógio no Hardware (NTP + RTC)..."
sudo bash -c 'cat << EOF > /etc/systemd/timesyncd.conf
[Time]
NTP=a.st1.ntp.br b.st1.ntp.br 1.1.1.1
FallbackNTP=ntp.ubuntu.com
EOF'
sudo systemctl enable --now systemd-timesyncd 2>/dev/null || true
sudo hwclock --systohc 2>/dev/null || true
echo "➜ [OK] Hora oficial gravada na BIOS da VM com sucesso."

echo -e "\e[33m=== [SRE] Geração Autônoma da Chave Criptográfica (Backups) ===\e[0m"
echo -e "\e[36m- Inicializando gerador criptográfico nativo...\e[0m"
GPG_TEMP_HOME=$(mktemp -d -t sre_gnupg_XXXXXX)
chmod 700 "$GPG_TEMP_HOME"
GPG_BATCH="$GPG_TEMP_HOME/gpg_batch.txt"
USER_REAL_HOME=$(eval echo "~${SUDO_USER:-$USER}")
if [ ! -d "$USER_REAL_HOME" ]; then
    USER_REAL_HOME="/home/${SUDO_USER:-$USER}"
fi

CHAVE_PUBLICA_PATH="$GPG_TEMP_HOME/chave_publica.asc"
CHAVE_PRIVADA_PATH="${USER_REAL_HOME}/CHAVE_PRIVADA_BACKUP_${EMPRESA}.asc"
CHAVE_PRIVADA_EXISTENTE="${TARGET_DIR}/CHAVE_PRIVADA_BACKUP_${EMPRESA}.asc"

if [ -f "$CHAVE_PRIVADA_EXISTENTE" ] || sudo gpg --list-public-keys "$CLIENTE_EMAIL" > /dev/null 2>&1; then
    echo -e "\e[32m➜ [IDEMPOTÊNCIA] Chave criptográfica OpenPGP já existente para: ${CLIENTE_EMAIL}. Preservando par de chaves.\e[0m"
    sudo gpg --armor --export "$CLIENTE_EMAIL" > "$CHAVE_PUBLICA_PATH" 2>/dev/null || true
fi

if [ ! -f "$CHAVE_PUBLICA_PATH" ] || [ ! -s "$CHAVE_PUBLICA_PATH" ]; then
    cat << EOF > "$GPG_BATCH"
%echo Generating SRE OpenPGP key
Key-Type: RSA
Key-Length: 3072
Name-Real: $CLIENTE_NOME $CLIENTE_SOBRENOME
Name-Email: $CLIENTE_EMAIL
Expire-Date: 0
Passphrase: $DB_PASSWORD
%commit
%echo done
EOF

    gpg --homedir "$GPG_TEMP_HOME" --batch --yes --gen-key "$GPG_BATCH" > /dev/null 2>&1
    gpg --homedir "$GPG_TEMP_HOME" --yes --armor --export "$CLIENTE_EMAIL" > "$CHAVE_PUBLICA_PATH" 2>/dev/null
    gpg --homedir "$GPG_TEMP_HOME" --yes --batch --pinentry-mode loopback --passphrase "$DB_PASSWORD" --armor --export-secret-keys "$CLIENTE_EMAIL" > "$CHAVE_PRIVADA_PATH" 2>/dev/null
    chmod 600 "$CHAVE_PRIVADA_PATH" 2>/dev/null || true
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$CHAVE_PRIVADA_PATH" 2>/dev/null || true
    fi
fi

if [ -f "$CHAVE_PUBLICA_PATH" ]; then
    HASH_ESPERADO=$(sha256sum "$CHAVE_PUBLICA_PATH" | awk '{print $1}' | tr '[:lower:]' '[:upper:]')
    CHAVE_PUBLICA_B64=$(base64 -w 0 "$CHAVE_PUBLICA_PATH")

    # SRE FIX: Importação automática e atômica da Chave PÚBLICA no Keyring do Host
    sudo gpg --batch --yes --import "$CHAVE_PUBLICA_PATH" > /dev/null 2>&1 || true
    echo -e "\e[32m➜ [SUCESSO] Chave pública importada no keyring do sistema para: $CLIENTE_EMAIL\e[0m"
else
    echo -e "\e[31m[ERRO CRÍTICO] O motor GPG falhou ao tentar forjar o par de chaves de segurança!\e[0m"
    exit 1
fi

gpgconf --homedir "$GPG_TEMP_HOME" --kill gpg-agent 2>/dev/null || true
rm -rf "$GPG_TEMP_HOME"

cat << EOF > "$NOME_ARQUIVO"
PREINSTALL_START_TS="$PREINSTALL_START_TS"
PREINSTALL_PAUSE_SEC="$TEMPO_PAUSA_INTERATIVA"
# --- Topologia de Borda (Roteamento SRE) ---
USE_TAILSCALE="$USE_TAILSCALE"
CUSTOM_DOMAIN="$CUSTOM_DOMAIN"
CUSTOM_EVO_DOMAIN="$CUSTOM_EVO_DOMAIN"
CADDY_PROTOCOL="$CADDY_PROTOCOL"
# --- Mapeamento Estático de Rede (SSOT) ---
IP_NETWORK_SUBNET="$IP_NETWORK_SUBNET"
IP_NETWORK_GATEWAY="$IP_NETWORK_GATEWAY"
IP_NOCODB="$IP_NOCODB"
IP_N8N="$IP_N8N"
IP_EVOLUTION="$IP_EVOLUTION"
IP_CADDY="$IP_CADDY"
IP_POSTGRES="$IP_POSTGRES"
IP_PGBOUNCER="$IP_PGBOUNCER"
IP_REDIS="$IP_REDIS"
IP_CHATWOOT="$IP_CHATWOOT"
IP_POSTIZ="$IP_POSTIZ"
IP_TEMPORAL="$IP_TEMPORAL"
IP_MINIO="$IP_MINIO"
IP_LITELLM="$IP_LITELLM"
IP_OPENWEBUI="$IP_OPENWEBUI"
# ------------------------------------------
PROJETO_DIR="/opt/daemind"
PREFIXO_CONTAINER="${EMPRESA}"
TS_OAUTH_ID="${TS_OAUTH_ID}"
TS_OAUTH_SECRET="${TS_OAUTH_SECRET}"
DB_USER="admin_db"
DB_PASSWORD="${DB_PASSWORD}"
DB_NAME="${EMPRESA}_db"
LOJA_API_KEY="${LOJA_API_KEY}"
LOJA_APP_KEY="${LOJA_APP_KEY}"
# --- Prompt injetado no n8n (Para o Open WebUI, crie a persona via 'Workspace Models' na interface) ---
IA_SYSTEM_PROMPT="Voce eh um assistente de IA focado em recuperacao de vendas, conversao de boletos e pix para e-commerce."
# --- Chaves de API de Inteligência Artificial ---
FREE_GEMINI="${FREE_GEMINI}"
GEMINI_API_KEY="${GEMINI_API_KEY}"
OPENAI_API_KEY="${OPENAI_API_KEY}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY}"
HOST_CADDY_PORT="80"
HOST_NOCODB_PORT="18080"
HOST_EVO_PORT="18081"
CHAVE_PUBLICA_B64="${CHAVE_PUBLICA_B64}"
HASH_ESPERADO="${HASH_ESPERADO}"
CLIENTE_NOME="${CLIENTE_NOME}"
CLIENTE_SOBRENOME="${CLIENTE_SOBRENOME}"
TS_EMAIL="${CLIENTE_EMAIL}"
STORAGE_MODE="${STORAGE_MODE:-local}"
USE_MINIO="${USE_MINIO:-s}"
${S3_ENDPOINT_EXT:+S3_ENDPOINT="${S3_ENDPOINT_EXT}"}
${S3_REGION_EXT:+S3_REGION="${S3_REGION_EXT}"}
${S3_ACCESS_KEY_EXT:+S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_EXT}"}
${S3_SECRET_KEY_EXT:+S3_SECRET_ACCESS_KEY="${S3_SECRET_KEY_EXT}"}
${S3_CHATWOOT_BUCKET_EXT:+S3_CHATWOOT_BUCKET="${S3_CHATWOOT_BUCKET_EXT}"}
${S3_POSTIZ_BUCKET_EXT:+S3_POSTIZ_BUCKET="${S3_POSTIZ_BUCKET_EXT}"}
LITELLM_MASTER_KEY="sk-admin-${DB_PASSWORD}"
EOF

chmod 600 "$NOME_ARQUIVO"

# =========================================================================
# 🔒 SRE NETWORK HARDENING (INTEGRADO AO PREINSTALL)
# =========================================================================
echo "=== [SRE] Aplicando Hardening Perimetral no Kernel (IPTables & IPSet) ==="
POLICY_ATUAL=$(sudo iptables -L OUTPUT -n | head -n 1 | grep -oE 'DROP|REJECT|ACCEPT' || echo "ACCEPT")
if [[ "$POLICY_ATUAL" == "DROP" || "$POLICY_ATUAL" == "REJECT" ]]; then
  sudo iptables -P OUTPUT ACCEPT
fi

sudo ipset create ALLOWED_DOMAINS hash:ip timeout 86400 --exist

# SRE FIX: Garante que a chain DOCKER-USER existe antes de flushear, impedindo interrupção com set -e
sudo iptables -N DOCKER-USER 2>/dev/null || true
sudo iptables -F DOCKER-USER

# Regras Core
sudo iptables -A DOCKER-USER -j RETURN
sudo iptables -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -I DOCKER-USER 2 -i lo -j ACCEPT

# Regras de Egress
sudo iptables -I DOCKER-USER 3 -p udp --dport 53 -j ACCEPT
sudo iptables -I DOCKER-USER 4 -p tcp --dport 53 -j ACCEPT
sudo iptables -I DOCKER-USER 5 -m set --match-set ALLOWED_DOMAINS dst -p tcp -m multiport --dports 80,443 -j ACCEPT
sudo iptables -I DOCKER-USER 6 -p tcp --dport 11434 -j ACCEPT

# Regras de Ingress
# SRE FIX: Liberação mandatória da porta 443 para Let's Encrypt nativo (Caddy WAF)
sudo iptables -I DOCKER-USER 7 -p tcp -m multiport --dports 80,443,18081 -j ACCEPT

if [ "$USE_TAILSCALE" = "true" ]; then
    # [SRE DOC] Malha Fechada: Libera portas vitais apenas para IPs validados dentro da VPN.
    sudo iptables -I DOCKER-USER 8 -i tailscale0 -p tcp -m multiport --dports 3000,3001,4000,5000,5678,18080,9000,9001 -j ACCEPT
else
    # [SRE DOC] BYODNS: Sem a VPN, garantimos que Proxies Locais (NPM) ou Túneis (Cloudflared)
    # acessem os apps. Bloqueia a WAN Pública, aceitando apenas da LAN (RFC 1918) e Loopback.
    sudo iptables -I DOCKER-USER 8 -s 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 -p tcp -m multiport --dports 3000,3001,4000,5000,5678,18080,9000,9001 -j ACCEPT
fi

# Isolamento Bridge
INTERFACE_REAL="br-${EMPRESA}"
sudo iptables -I DOCKER-USER 9 ! -o "$INTERFACE_REAL" -j LOG --log-prefix "CONTAINER_EGRESS_BLOCKED: "
sudo iptables -I DOCKER-USER 10 ! -o "$INTERFACE_REAL" -j DROP

echo "➜ [SUCESSO] Firewall perimetral ativado e consolidado para a empresa: ${EMPRESA}"

# =========================================================================
# 📥 ESTRUTURAÇÃO FINAL DO PAYLOAD E SSOT EM /opt/daemind
# =========================================================================
# Garante o diretório de configurações no repositório oficial
sudo mkdir -p "${TARGET_DIR}/core/config"

# Salva/Consolida o payload SSOT diretamente no arquivo .env definitivo (na raiz TARGET_DIR/.env)
if [ -f "$NOME_ARQUIVO" ]; then
    sudo cp "$NOME_ARQUIVO" "${TARGET_DIR}/.env"
    sudo chmod 600 "${TARGET_DIR}/.env" 2>/dev/null || true
    rm -f "$NOME_ARQUIVO" 2>/dev/null || true
fi

# SRE PRE-FLIGHT FIX: Remove diretório corrompido litellm config.yaml se existir
if [ -d "${TARGET_DIR}/volumes/litellm_data/config.yaml" ]; then
    sudo rm -rf "${TARGET_DIR}/volumes/litellm_data/config.yaml" 2>/dev/null || true
fi

# SRE DECOUPLED MODULE: Execução do Motor de Auto-Tuning Dinâmico
if [ -f "${TARGET_DIR}/core/scripts/autotune.sh" ]; then
    sudo chmod +x "${TARGET_DIR}/core/scripts/autotune.sh"
    sudo "${TARGET_DIR}/core/scripts/autotune.sh" "${TARGET_DIR}/.env" || true
fi

# --- SRE PURGE DE ACESSÓRIOS NÃO UTILIZADOS ---
if [[ ! "${USE_MINIO:-s}" =~ ^[Ss]$ ]]; then
    echo "➜ [SRE PURGE] Removendo scripts e overlays de acessórios desativados (MinIO S3)..."
    sudo rm -f "${TARGET_DIR}/core/scripts/install_minIO.sh" 2>/dev/null || true
    sudo rm -f "${TARGET_DIR}/core/config/docker-compose.minio.yml" 2>/dev/null || true
fi
# Preserva o cache de sessão do wizard (.daemind_wizard_cache.env).
# A sanitização/remoção ocorrerá no final da execução com sucesso do install.sh.
rm -f /tmp/debug_tailscale.log 2>/dev/null || true

# Move/Preserva a chave privada exportada para dentro do projeto
CHAVE_PRIVADA_NOME="CHAVE_PRIVADA_BACKUP_${EMPRESA}.asc"
if [ -f "$CHAVE_PRIVADA_NOME" ]; then
    sudo mv -f "$CHAVE_PRIVADA_NOME" "${TARGET_DIR}/${CHAVE_PRIVADA_NOME}" 2>/dev/null || true
    sudo chmod 600 "${TARGET_DIR}/${CHAVE_PRIVADA_NOME}" 2>/dev/null || true
    [ -n "$SUDO_USER" ] && sudo chown "$SUDO_USER:$SUDO_USER" "${TARGET_DIR}/${CHAVE_PRIVADA_NOME}" 2>/dev/null || true
fi

# Garante permissão de execução no instalador oficial
if [ -f "${TARGET_DIR}/core/scripts/install.sh" ]; then
    sudo chmod +x "${TARGET_DIR}/core/scripts/install.sh"
elif [ -f "${TARGET_DIR}/install.sh" ]; then
    sudo chmod +x "${TARGET_DIR}/install.sh"
fi

echo ""
echo -e "\e[32m=====================================================================\e[0m"
echo -e "\e[32m  [SUCESSO] Host preparado e repositório estruturado em ${TARGET_DIR}!\e[0m"
echo -e "\e[32m  --> Arquivo SSOT: ${TARGET_DIR}/.env\e[0m"
echo -e "\e[32m=====================================================================\e[0m"
echo ""

# Prompt Interativo de Execução
if [ -n "${EXECUTAR_INSTALL:-}" ]; then
    echo -e "\e[32m✔ [AUTO-EXECUTE] Opção de execução do instalador lida do ambiente (${EXECUTAR_INSTALL}).\e[0m"
else
    if [ -t 0 ] || [ -c /dev/tty ]; then
        coletar_sn "🚀 Deseja iniciar a instalação do daemind. agora?" EXECUTAR_INSTALL "s" "false"
    else
        EXECUTAR_INSTALL="n"
    fi
fi

if [ "$EXECUTAR_INSTALL" = "s" ]; then
    echo "=== [SRE] Inicializando deploy do daemind. em segundo plano... ==="
    cd "${TARGET_DIR}"
    if [ -f "./core/scripts/install.sh" ]; then
        sudo true; nohup sudo bash -c "export PREINSTALL_START_TS='${INICIO_TS}'; export PREINSTALL_PAUSE_SEC='${TEMPO_PAUSA_INTERATIVA}'; cd ${TARGET_DIR} && bash ./core/scripts/install.sh" > /dev/null 2>&1 &
    else
        sudo true; nohup sudo bash -c "export PREINSTALL_START_TS='${INICIO_TS}'; export PREINSTALL_PAUSE_SEC='${TEMPO_PAUSA_INTERATIVA}'; cd ${TARGET_DIR} && bash ./install.sh" > /dev/null 2>&1 &
    fi
    sleep 2
    echo -e "\e[32m➜ Deploy disparado com sucesso! Anexando aos logs em tempo real...\e[0m"
    echo -e "\e[36m➜ (Pressione Ctrl+C a qualquer momento para desacoplar a visualização sem interromper a instalação)\e[0m"
    echo "---------------------------------------------------------------------"
    tail -n 50 -f /tmp/debug_install.log
else
    echo "====================================================================="
    echo "📌 Preparação concluída. Instalação pausada pelo operador."
    echo ""
    echo "➜ Para executar a instalação manualmente a qualquer momento, rode:"
    echo "    cd ${TARGET_DIR}"
    echo "    sudo ./core/scripts/install.sh"
    echo ""
    echo "⚠️  [ATENÇÃO - DEFESA PERIMETRAL / BACKUP OBRIGATÓRIO]:"
    echo "    Chave Privada salva em: ~/CHAVE_PRIVADA_BACKUP_${EMPRESA}.asc"
    echo "    Faça o download do arquivo .asc via SFTP/SCP para um local seguro (ex: Pendrive)"
    echo "    e remova o arquivo .asc do servidor!"
    echo "====================================================================="
fi