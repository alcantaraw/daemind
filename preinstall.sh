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

# SRE OVERRIDE IMMUTABILITY GUARD: Preserva export do operador durante todo o ciclo
INITIAL_USER_OVERRIDES=()
for _v in $(compgen -v | grep -E '^(USE_|OVERRIDE_|EMPRESA|ROUTING_|STORAGE_|S3_|OPENAI_|ANTHROPIC_|GEMINI_|DEEPSEEK_|OPENROUTER_)'); do
    [ -n "${!_v:-}" ] && INITIAL_USER_OVERRIDES+=("$_v=${!_v}")
done

log_info()    { echo -e "${CLR_CYAN}➜ [INFO PREINSTALL]${CLR_RESET} $1"; }
log_success() { echo -e "${CLR_GREEN}✔ [SUCESSO PREINSTALL]${CLR_RESET} $1"; }
log_warn()    { echo -e "${CLR_YELLOW}⚠️  [ATENÇÃO PREINSTALL]${CLR_RESET} $1"; }
log_error()   { echo -e "${CLR_RED}🚨 [ERRO CRÍTICO PREINSTALL]${CLR_RESET} $1"; }
# Tratamento de interrupção graciosa do usuário (Ctrl+C / SIGINT)
interrupcao_usuario() {
    clear 2>/dev/null || true
    echo -e "${CLR_YELLOW}➜ Instalação cancelada pelo usuário.${CLR_RESET}"
    exit 130
}
trap interrupcao_usuario SIGINT SIGTERM

# =========================================================================
# ⚙️ DETECÇÃO DE MODO DE INTERFACE (DIALOG TUI VS MODO CLI CLÁSSICO)
# =========================================================================
USE_TUI="true"
for arg in "$@"; do
    if [ "$arg" = "--cli" ]; then
        USE_TUI="false"
        break
    fi
done

if [ "$DEBIAN_FRONTEND" = "noninteractive" ] || [ "$CI" = "true" ] || ! [ -c /dev/tty ] || [ ! -t 0 -a "$USE_TUI" != "true" ]; then
    if [ "$USE_TUI" = "true" ] && ! [ -c /dev/tty ]; then
        USE_TUI="false"
    fi
fi


# =========================================================================
# ⏱️ SINCRONIZAÇÃO SILENCIOSA DE DATA/HORA & BOOTSTRAP DO DIALOG
# =========================================================================
# Garante elevação do timeout do sudo para não pedir senha no meio das janelas
echo "Defaults timestamp_timeout=60" | sudo tee /etc/sudoers.d/custom_sudo_timeout > /dev/null 2>&1 || true
sudo chmod 0440 /etc/sudoers.d/custom_sudo_timeout 2>/dev/null || true

# Garante fuso horário America/Sao_Paulo silenciosamente
if [ ! -f /etc/timezone ]; then
    echo "America/Sao_Paulo" | sudo tee /etc/timezone > /dev/null 2>&1 || true
fi
sudo timedatectl set-timezone America/Sao_Paulo >/dev/null 2>&1 || true

# Sincroniza relógio via HTTP silenciosamente
HTTP_NOW=$(curl -sI --max-time 5 https://1.1.1.1 2>/dev/null | grep -i '^Date:' | sed 's/^[Dd]ate: //g' || true)
if [ -n "$HTTP_NOW" ]; then
    sudo date -s "$HTTP_NOW" >/dev/null 2>&1 || true
fi

# Instalação silenciosa de ferramentas essenciais de bootstrap (dialog e git) com timeout estrito de 60s
if ! command -v dialog &>/dev/null || ! command -v git &>/dev/null; then
    local_err_apt=0
    sudo apt-get update -qq -o Dpkg::Lock::Timeout=30 > /dev/null 2>&1 || local_err_apt=1
    sudo -E apt-get install -y -qq -o Dpkg::Lock::Timeout=30 -o Dpkg::Options::="--force-confold" dialog git > /dev/null 2>&1 || local_err_apt=1

    if [ "$local_err_apt" -eq 1 ] || ! command -v dialog &>/dev/null; then
        if [ "$USE_TUI" = "true" ]; then
            echo -e "${CLR_YELLOW}⚠️  [BOOTSTRAP WARN] Não foi possível instalar o pacote 'dialog' via apt (timeout/bloqueio de lock).${CLR_RESET}"
            echo -e "${CLR_YELLOW}  ↳ Alternando automaticamente para o Modo CLI Clássico...${CLR_RESET}"
            USE_TUI="false"
        fi
    fi
fi

# =========================================================================
# 📥 CLONAGEM / SINCRONIZAÇÃO SILENCIOSA IMEDIATA DO REPOSITÓRIO (/opt/daemind)
# =========================================================================
TARGET_DIR="${TARGET_DIR:-/opt/daemind}"
REPO_URL="https://github.com/alcantaraw/daemind.git"
CURRENT_GIT_BRANCH=""
if [ -d "${TARGET_DIR}/.git" ]; then
    CURRENT_GIT_BRANCH=$(cd "${TARGET_DIR}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
fi
REPO_BRANCH="${TARGET_BRANCH:-${CURRENT_GIT_BRANCH:-test}}"

if ! getent hosts github.com >/dev/null 2>&1; then
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null || true
    echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf >/dev/null || true
fi

sudo mkdir -p "${TARGET_DIR}"
if [ -d "${TARGET_DIR}/.git" ]; then
    (cd "${TARGET_DIR}" && sudo git fetch --all -q >/dev/null 2>&1 && sudo git checkout -f "${REPO_BRANCH}" >/dev/null 2>&1 || sudo git checkout -b "${REPO_BRANCH}" "origin/${REPO_BRANCH}" >/dev/null 2>&1 || true && sudo git reset --hard "origin/${REPO_BRANCH}" >/dev/null 2>&1)
elif [ -d "${TARGET_DIR}" ] && [ "$(ls -A "${TARGET_DIR}" 2>/dev/null)" ]; then
    TEMP_CLONE=$(mktemp -d)
    sudo git clone -b "${REPO_BRANCH}" -q "${REPO_URL}" "${TEMP_CLONE}" > /dev/null 2>&1 || true
    if [ -d "${TEMP_CLONE}/core" ]; then
        sudo cp -rf "${TEMP_CLONE}"/* "${TARGET_DIR}/" 2>/dev/null || true
        sudo cp -rf "${TEMP_CLONE}"/.git "${TARGET_DIR}/" 2>/dev/null || true
    fi
    sudo rm -rf "${TEMP_CLONE}"
else
    sudo git clone -b "${REPO_BRANCH}" -q "${REPO_URL}" "${TARGET_DIR}" > /dev/null 2>&1 || true
fi

# =========================================================================
# COBERTURA FORENSE TRANSVERSAL (DEBUG, TRAP & LOG)
# =========================================================================
if [[ "$0" =~ ^-?(bash|sh)$ ]]; then
    SCRIPT_NOME="preinstall"
else
    SCRIPT_NOME=$(basename "$0" .sh)
fi

LOG_FILE="/tmp/debug_${SCRIPT_NOME}.log"

# Se estiver em modo CLI, exibe o cabeçalho no terminal; se for TUI, não polui a tela antes do dialog
if [ "$USE_TUI" != "true" ]; then
    log_header "Wizard de Preparação do Host, Kernel Tuning & Coleta de Variáveis"
fi

# =========================================================================
# 🔒 SRE GUARDRAIL: TRAVA DE CONCORRÊNCIA INTELIGENTE (MUTEX LOCK COM AUTOREPAIR)
# =========================================================================
LOCK_FILE="/tmp/${SCRIPT_NOME}.lock"
exec 200>"$LOCK_FILE"

if ! flock -n 200; then
    # Verifica qual PID detém a trava
    LOCK_PID=$(fuser "$LOCK_FILE" 2>/dev/null | awk '{print $1}' || true)
    
    # Se o processo antigo morreu ou é órfão, remove e prossegue
    if [ -z "$LOCK_PID" ] || ! ps -p "$LOCK_PID" > /dev/null 2>&1; then
        echo "➜ [AUTOREPAIR] Trava residual órfã detectada. Liberando ${LOCK_FILE}..."
        rm -f "$LOCK_FILE" 2>/dev/null || true
        exec 200>"$LOCK_FILE"
        flock -n 200 || true
    else
        # Se estiver em modo TUI/interativo com TTY, pergunta se deseja matar a instância anterior
        if [ "$FORCE_NEW_INSTALL" = "s" ] || [ "$FORCE_NEW_INSTALL" = "true" ]; then
            echo "➜ [FORCE] Encerrando instância anterior (PID: ${LOCK_PID}) para novo deploy..."
            sudo kill -9 "$LOCK_PID" 2>/dev/null || true
            sleep 1
            exec 200>"$LOCK_FILE"
            flock -n 200 || true
        else
            echo "====================================================================="
            echo "⚠️  [ALERTA SRE PREINSTALL] Uma instância do ${SCRIPT_NOME}.sh já está em execução (PID: ${LOCK_PID})."
            echo "➜ Arquivo de Trava: ${LOCK_FILE}"
            echo "➜ Logs da execução ativa: tail -f ${LOG_FILE}"
            echo "➜ Para forçar a execução matando a anterior, execute:"
            echo "    sudo kill -9 ${LOCK_PID} && rm -f ${LOCK_FILE}"
            echo "    ou passe a variável: FORCE_NEW_INSTALL=s"
            echo "====================================================================="
            # Consome stdin restante para evitar erro de pipe quebrado no curl (curl 23)
            cat > /dev/null 2>&1 || true
            exit 0
        fi
    fi
fi

# =========================================================================
# 🎨 TEMA VISUAL DO DIALOG & TUI WRAPPERS (SRE THEME - AZUL & PRETO)
# =========================================================================
gerar_dialogrc() {
    cat << 'EOF' > /tmp/.daemind_dialogrc
# Estilização Oficial daemind. SRE Dialog (Azul & Preto)
use_shadow = OFF
use_colors = ON
screen_color = (CYAN,BLACK,ON)
dialog_color = (CYAN,BLACK,ON)
title_color = (YELLOW,BLACK,ON)
border_color = (BLUE,BLACK,ON)
button_active_color = (BLACK,CYAN,ON)
button_inactive_color = (CYAN,BLACK,OFF)
button_key_active_color = (YELLOW,CYAN,ON)
button_key_inactive_color = (YELLOW,BLACK,OFF)
button_label_active_color = (BLACK,CYAN,ON)
button_label_inactive_color = (WHITE,BLACK,OFF)
form_active_text_color = (BLACK,CYAN,ON)
form_text_color = (WHITE,BLUE,ON)
form_item_readonly_color = (CYAN,BLACK,OFF)
item_color = (WHITE,BLACK,OFF)
item_selected_color = (BLACK,CYAN,ON)
tag_color = (YELLOW,BLACK,ON)
tag_selected_color = (YELLOW,CYAN,ON)
tag_key_color = (YELLOW,BLACK,ON)
tag_key_selected_color = (WHITE,CYAN,ON)
check_color = (CYAN,BLACK,OFF)
check_selected_color = (BLACK,CYAN,ON)
uarrow_color = (GREEN,BLACK,ON)
darrow_color = (GREEN,BLACK,ON)
EOF
    export DIALOGRC="/tmp/.daemind_dialogrc"
}

tui_dialog() {
    [ ! -f "/tmp/.daemind_dialogrc" ] && gerar_dialogrc
    dialog --clear --ascii-lines --mouse --tab-correct --cr-wrap --no-collapse "$@" < /dev/tty
    return $?
}

tui_dialog_out() {
    [ ! -f "/tmp/.daemind_dialogrc" ] && gerar_dialogrc
    dialog --clear --ascii-lines --mouse --stdout "$@" < /dev/tty
}

# Wrapper Dialog com suporte a navegação [Avançar] e [Voltar]
tui_dialog_step() {
    [ ! -f "/tmp/.daemind_dialogrc" ] && gerar_dialogrc
    local extra_args=()
    local is_input_box=0
    for a in "$@"; do
        if [ "$a" = "--inputbox" ] || [ "$a" = "--passwordbox" ] || [ "$a" = "--editbox" ]; then
            is_input_box=1
            break
        fi
    done
    # Em checklists/radios/forms pré-preenchidos, direciona o default para OK, mas em caixas de texto deixa o foco no campo
    if [ "$is_input_box" -eq 0 ]; then
        for a in "$@"; do
            if [ -n "$a" ] && [ "$a" != "off" ] && [ "$a" != "0" ] && [ ${#a} -ge 4 ]; then
                extra_args+=(--default-button "ok")
                break
            fi
        done
    fi
    local out
    out=$(dialog --clear --ascii-lines --mouse --insecure --ok-label "Avançar" --cancel-label "Voltar" "${extra_args[@]}" --stdout "$@" < /dev/tty)
    local ret=$?
    echo "$out"
    return $ret
}

tui_dialog_editbox() {
    [ ! -f "/tmp/.daemind_dialogrc" ] && gerar_dialogrc
    local title="$1"
    local file_path="$2"
    local height="${3:-20}"
    local width="${4:-80}"
    set +e
    dialog --ascii-lines --mouse --ok-label "Avançar" --cancel-label "Voltar" --title "$title" --editbox "$file_path" "$height" "$width" 2> "${file_path}.out" < /dev/tty
    local ret=$?
    set -e
    return $ret
}

tui_dialog_password() {
    [ ! -f "/tmp/.daemind_dialogrc" ] && gerar_dialogrc
    local prompt="$1"
    local height="$2"
    local width="$3"
    set +e
    local out
    out=$(dialog --ascii-lines --mouse --ok-label "Avançar" --cancel-label "Voltar" --insecure --stdout --passwordbox "$prompt" "$height" "$width" < /dev/tty)
    local ret=$?
    set -e
    echo "$out"
    return $ret
}

# Resolução estrita da home do usuário operador (onde os caches com dados sensíveis residem)
USER_HOME="${HOME:-/root}"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER" 2>/dev/null || echo "/home/$SUDO_USER")
elif [ -d "/home/$USER" ]; then
    USER_HOME="/home/$USER"
fi

# SRE CACHE DISCOVERY: Resolução dinâmica e resiliente do arquivo de cache do wizard na home do usuário
TARGET_CACHE_NAME="${WIZARD_CACHE_NAME:-${CACHE_NAME:-}}"
for param in "$@"; do
    if [ "$param" = "--cli" ]; then
        continue
    fi
    if [ -z "$TARGET_CACHE_NAME" ]; then
        TARGET_CACHE_NAME=$(echo "$param" | sed 's/^--//')
        break
    fi
done


if [ -n "$TARGET_CACHE_NAME" ]; then
    CACHE_WIZARD_FILE="${USER_HOME}/.daemind_wizard_cache_${TARGET_CACHE_NAME}.env"
    [ ! -f "$CACHE_WIZARD_FILE" ] && [ -f "./.daemind_wizard_cache_${TARGET_CACHE_NAME}.env" ] && CACHE_WIZARD_FILE="./.daemind_wizard_cache_${TARGET_CACHE_NAME}.env"
else
    CACHE_WIZARD_FILE="${USER_HOME}/.daemind_wizard_cache.env"
    [ ! -f "$CACHE_WIZARD_FILE" ] && [ -f "./.daemind_wizard_cache.env" ] && CACHE_WIZARD_FILE="./.daemind_wizard_cache.env"
fi

# SRE FALLBACK DE ESTADO VIVO: Se não há cache de wizard, mas existe ambiente ativo em /opt/daemind/.env, carrega como baseline
TARGET_DIR="${TARGET_DIR:-/opt/daemind}"
PROD_ENV_FILE="${TARGET_DIR}/.env"
if [ ! -f "$CACHE_WIZARD_FILE" ] && [ -f "$PROD_ENV_FILE" ]; then
    echo -e "\e[32m✔ [DISCOVERY PREINSTALL] Nenhuma sessão temporária encontrada, mas detectamos ambiente ativo em ${PROD_ENV_FILE}.\e[0m"
    echo -e "\e[36m➜ [DISCOVERY PREINSTALL] Importando configurações vigentes para manutenção/reconfiguração...\e[0m"
    cp -f "$PROD_ENV_FILE" "$CACHE_WIZARD_FILE" 2>/dev/null || true
    chmod 600 "$CACHE_WIZARD_FILE" 2>/dev/null || true
    [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && chown "$SUDO_USER:$SUDO_USER" "$CACHE_WIZARD_FILE" 2>/dev/null || true
fi


save_wizard_cache() {
    local var="$1"
    local val="$2"
    if [ -n "$var" ]; then
        val=$(echo "$val" | tr -d '\r' | xargs 2>/dev/null || echo "$val")
        grep -v "^${var}=" "$CACHE_WIZARD_FILE" 2>/dev/null > "${CACHE_WIZARD_FILE}.tmp" || true
        mv "${CACHE_WIZARD_FILE}.tmp" "$CACHE_WIZARD_FILE" 2>/dev/null || true
        # Valor não-vazio → grava. Vazio → remove entrada anterior (comportamento de unset no cache)
        [ -n "$val" ] && echo "${var}=\"${val}\"" >> "$CACHE_WIZARD_FILE"
        sed -i 's/\r$//' "$CACHE_WIZARD_FILE" 2>/dev/null || true
        chmod 600 "$CACHE_WIZARD_FILE" 2>/dev/null || true
        [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && chown "$SUDO_USER:$SUDO_USER" "$CACHE_WIZARD_FILE" 2>/dev/null || true
    fi
}

# SRE FIX: Função dedicada a forçar validação estrita de respostas Sim/Não [s/n] e checar cache
coletar_sn() {
    local prompt="$1"
    local var_name="$2"
    local default_val="${3:-n}" # 's' ou 'n'
    local save_cache="${4:-true}"
    
    local current_val="${!var_name}"
    if [ -n "$current_val" ]; then
        current_val=$(echo "$current_val" | tr '[:upper:]' '[:lower:]')
        if [[ "$current_val" =~ ^(s|n)$ ]]; then
            eval "$var_name=\"$current_val\""
            echo -e "\e[32m✔ [CACHE PREINSTALL] $prompt: ${current_val}\e[0m"
            return 0
        fi
    fi

    pausar_cronometro 2>/dev/null || true
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
            echo -e "\e[31m[ERRO CRÍTICO PREINSTALL] Resposta inválida! Digite apenas 's' ou 'n' (ou pressione Enter para o padrão '$default_val').\e[0m"
        fi
    done
    retomar_cronometro 2>/dev/null || true
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
            echo -e "\e[32m✔ [CACHE PREINSTALL] $prompt: ********\e[0m"
        else
            echo -e "\e[32m✔ [CACHE PREINSTALL] $prompt: $cached_val\e[0m"
        fi
        return 0
    fi

    pausar_cronometro 2>/dev/null || true
    while true; do
        if [ "$is_secret" = "true" ]; then
            echo -ne "➜ $prompt: "
            input_val=""
            # [SRE DOC] Captura de Keystrokes (Blindagem SecOps):
            while IFS= read -r -s -n 1 char < /dev/tty; do
                if [[ -z "$char" ]] || [[ "$char" == $'\n' ]] || [[ "$char" == $'\r' ]]; then
                    echo ""
                    break
                fi
                if [[ "$char" == $'\177' ]] || [[ "$char" == $'\b' ]]; then
                    if [ ${#input_val} -gt 0 ]; then
                        input_val="${input_val%?}"
                        echo -ne "\b \b"
                    fi
                else
                    input_val+="$char"
                    echo -ne "*"
                fi
            done
        else
            read -p "➜ $prompt: " input_val < /dev/tty
        fi

        input_val=$(echo "$input_val" | tr -d '\r' | xargs 2>/dev/null || echo "$input_val")

        if [ -n "$input_val" ]; then
            if [ -n "$exact_length" ] && [ ${#input_val} -ne "$exact_length" ]; then
                echo -e "\e[31m[ERRO CRÍTICO PREINSTALL] Valor inválido. Deve ter exatamente ${exact_length} caracteres.\e[0m"
                continue
            fi
            if [ -n "$regex" ] && ! [[ "$input_val" =~ $regex ]]; then
                echo -e "\e[31m[ERRO CRÍTICO PREINSTALL] Formato inválido! Tente novamente.\e[0m"
                continue
            fi
            eval "$var_name=\"$input_val\""
            save_wizard_cache "$var_name" "$input_val"
            break
        elif [ "$is_optional" = "true" ]; then
            eval "$var_name=\"\""
            break
        else
            echo -e "\e[31m[ERRO CRÍTICO PREINSTALL] O campo '$prompt' é obrigatório.\e[0m"
        fi
    done
    retomar_cronometro 2>/dev/null || true
}

# =========================================================================
# FASE 1 (MODO CLI): HIGIENIZAÇÃO E PREPARAÇÃO DO SISTEMA OPERACIONAL
# =========================================================================
if [ "$USE_TUI" != "true" ]; then
    echo "=== [SRE PREINSTALL] Elevando temporariamente o timeout do sudo para 60 minutos ==="
    echo "Defaults timestamp_timeout=60" | sudo tee /etc/sudoers.d/custom_sudo_timeout > /dev/null
    sudo chmod 0440 /etc/sudoers.d/custom_sudo_timeout

    cleanup_sudo_timeout() {
        if [ "$EXECUTAR_INSTALL" != "s" ]; then
            mostrar_duracao
        fi
        if [ -f /etc/sudoers.d/custom_sudo_timeout ]; then
            echo "=== [SRE HARDENING PREINSTALL] Revogando timeout estendido do sudo... ==="
            sudo rm -f /etc/sudoers.d/custom_sudo_timeout 2>/dev/null || true
        fi
        rm -f "$LOCK_FILE" 2>/dev/null || true
    }
    trap cleanup_sudo_timeout EXIT

    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1

    echo "=== [SRE KERNEL TUNING PREINSTALL] Aplicando Otimizações Avançadas de SO & Network Stack ==="

    if [ ! -f /etc/sysctl.d/99-daemind-sre.conf ] || ! grep -q 'net.core.somaxconn = 65535' /etc/sysctl.d/99-daemind-sre.conf 2>/dev/null; then
        echo "➜ [CONFIGURANDO PREINSTALL] Aplicando matriz de Kernel Tuning em /etc/sysctl.d/99-daemind-sre.conf..."
        cat << 'EOF' | sudo tee /etc/sysctl.d/99-daemind-sre.conf > /dev/null
# --- MEMORY TUNING (REDIS & POSTGRES) ---
vm.overcommit_memory = 1
vm.swappiness = 10
vm.max_map_count = 262144

# --- NETWORK STACK TUNING (CADDY, PGBOUNCER, MINIO) ---
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# --- FILE DESCRIPTORS & INOTIFY (DOCKER & NODE.JS) ---
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
EOF
        sudo sysctl --system > /dev/null 2>&1 || sudo sysctl -p /etc/sysctl.d/99-daemind-sre.conf > /dev/null 2>&1 || true
        echo "➜ [SUCESSO PREINSTALL] Kernel Tuning SRE aplicado (Memory Overcommit, Network Backlog, Inotify & Limits)."
    else
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] Matriz de Kernel Tuning já configurada e ativa no sistema."
    fi

    if [ ! -f /etc/security/limits.d/99-daemind-limits.conf ] || ! grep -q 'soft nofile 1048576' /etc/security/limits.d/99-daemind-limits.conf 2>/dev/null; then
        cat << 'EOF' | sudo tee /etc/security/limits.d/99-daemind-limits.conf > /dev/null
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 524288
* hard nproc 524288
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 524288
root hard nproc 524288
EOF
    fi

    if [ ! -f /etc/timezone ]; then
        echo "America/Sao_Paulo" | sudo tee /etc/timezone > /dev/null
    fi

    sudo timedatectl set-timezone America/Sao_Paulo 2>/dev/null || true

    echo "=== [SRE PREINSTALL] Sincronização Atômica de Relógio ==="
    HTTP_NOW=$(curl -sI --max-time 5 https://1.1.1.1 2>/dev/null | grep -i '^Date:' | sed 's/^[Dd]ate: //g' || true)

    if [ -n "$HTTP_NOW" ]; then
        sudo date -s "$HTTP_NOW" >/dev/null
        INICIO_TS=$(date +%s)
        export PREINSTALL_START_TS="$INICIO_TS"
        echo "➜ [SUCESSO PREINSTALL] Relógio do Kernel recalibrado via HTTP: $(date)"
    else
        echo "⚠️ [AVISO PREINSTALL] Não foi possível obter o horário via HTTP."
    fi

    echo "=== [SRE PREINSTALL] Verificando se há locks ativos do APT/DPKG no sistema ==="
    TENTATIVAS_APT_LOCK=0
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        TENTATIVAS_APT_LOCK=$((TENTATIVAS_APT_LOCK + 1))
        echo "  ↳ O APT está ocupado com outro processo em segundo plano (Tentativa ${TENTATIVAS_APT_LOCK}/24). Aguardando 5s..."
        sleep 5
        if [ "$TENTATIVAS_APT_LOCK" -ge 24 ]; then
            echo "  ⚠️ [SRE AUTO-HEALING PREINSTALL] Lock do APT retido por mais de 120s. Finalizando processos zumbis do APT/unattended-upgrades..."
            sudo systemctl stop unattended-upgrades 2>/dev/null || true
            sudo killall -9 apt apt-get dpkg 2>/dev/null || true
            sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
            sudo dpkg --configure -a 2>/dev/null || true
            break
        fi
    done

    echo "=== [SRE PREINSTALL] Detectando e corrigindo dinamicamente pacotes corrompidos ==="
    PACOTES_QUEBRADOS=$(dpkg -l | awk '/^i[FHRU]/ {print $2}')
    if [ -n "$PACOTES_QUEBRADOS" ]; then 
        echo "  ↳ Removendo resíduos de Kernel/Pacotes quebrados silenciosamente..."
        echo "$PACOTES_QUEBRADOS" | sudo xargs -r env DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y -qq > /dev/null 2>&1 < /dev/null
    fi

    sudo chmod -x /etc/kernel/prerm.d/vboxadd /etc/kernel/postinst.d/vboxadd 2>/dev/null || true
    if ! grep -q 'GRUB_DISABLE_OS_PROBER=true' /etc/default/grub 2>/dev/null; then
        sudo sed -i '/GRUB_DISABLE_OS_PROBER/d' /etc/default/grub 2>/dev/null || true
        echo "GRUB_DISABLE_OS_PROBER=true" | sudo tee -a /etc/default/grub > /dev/null
    fi
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

    echo "=== [SRE PREINSTALL] Configurando chaves e repositórios oficiais do Docker ==="
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "=== [SRE PREINSTALL] Verificando atualizações dos índices do APT ==="
    JANELA_CORTE_SEGUNDOS=86400 # 24 horas
    ULTIMA_ATUALIZACAO=0
    NOSSO_STAMP="/var/log/sre_factory_apt_update.stamp"

    if [ -f "$NOSSO_STAMP" ]; then
        ULTIMA_ATUALIZACAO=$(stat -c %Y "$NOSSO_STAMP")
    elif [ -f /var/lib/apt/periodic/update-success-stamp ]; then
        ULTIMA_ATUALIZACAO=$(stat -c %Y /var/lib/apt/periodic/update-success-stamp)
    fi

    AGORA=$(date +%s)
    TEMPO_DECORRIDO=$((AGORA - ULTIMA_ATUALIZACAO))

    LISTAS_APT=$(ls /var/lib/apt/lists/ 2>/dev/null | grep -v '^partial$' | head -n 1 || true)

    if [ $TEMPO_DECORRIDO -gt $JANELA_CORTE_SEGUNDOS ] || [ -z "$LISTAS_APT" ]; then
        if ! sudo apt-get update -qq -o Dpkg::Lock::Timeout=120 2>/dev/null; then
            sudo killall -9 apt-get apt 2>/dev/null || true
            sudo rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend 2>/dev/null || true
            sudo apt-get update -qq -o Dpkg::Lock::Timeout=60 > /dev/null 2>&1 || true
        fi
        sudo touch "$NOSSO_STAMP"
    fi

    PACOTES_REQUERIDOS=(
        chrony wget iputils-ping curl openssl iptables ipset cron dnsmasq apt-transport-https
        ca-certificates gnupg tcpdump net-tools lsb-release jq git vim
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        bind9-utils sysstat htop dnsutils systemd-timesyncd
    )

    PACOTES_PARA_INSTALAR=()
    for pacote in "${PACOTES_REQUERIDOS[@]}"; do
        if ! dpkg -l "$pacote" &>/dev/null; then
            PACOTES_PARA_INSTALAR+=("$pacote")
        else
            VERSAO_INSTALADA=$(dpkg-query -W -f='${Version}' "$pacote" 2>/dev/null)
            VERSAO_CANDIDATA=$(apt-cache policy "$pacote" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
            
            if [ "$VERSAO_INSTALADA" != "$VERSAO_CANDIDATA" ] && [ -n "$VERSAO_CANDIDATA" ] && [ "$VERSAO_CANDIDATA" != "(none)" ]; then
                PACOTES_PARA_INSTALAR+=("$pacote")
            fi
        fi
    done

    if [ ${#PACOTES_PARA_INSTALAR[@]} -gt 0 ]; then
        echo "➜ [SRE PREINSTALL] Provisionando ${#PACOTES_PARA_INSTALAR[@]} pacote(s) do sistema..."
        sudo add-apt-repository universe -y > /dev/null 2>&1 || true
        sudo apt-get update -qq -o Dpkg::Lock::Timeout=120 > /dev/null 2>&1 || true
        sudo touch "$NOSSO_STAMP"

        sudo -E apt-get install -y -qq -o Dpkg::Lock::Timeout=120 -o Dpkg::Options::="--force-confold" "${PACOTES_PARA_INSTALAR[@]}" > /dev/null 2>&1 < /dev/null
        sudo apt-get clean > /dev/null 2>&1 || true
        sudo systemctl stop dnsmasq 2>/dev/null || true
        echo "✔ [SUCESSO PREINSTALL] Pacotes do sistema instalados com sucesso."
    else
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] Pacotes do sistema já estão instalados e atualizados."
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

    if ! getent hosts github.com >/dev/null 2>&1; then
        echo "⚠️ [SRE AUTO-HEALING PREINSTALL] Resolução de DNS oscilou pós-APT. Injetando resolvers de contingência..."
        echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null || true
        echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf >/dev/null || true
    fi

    echo "➜ [SRE PREINSTALL] Sincronizando repositório oficial da solução..."
    sudo mkdir -p "${TARGET_DIR}"

    if [ -d "${TARGET_DIR}/.git" ]; then
        (cd "${TARGET_DIR}" && sudo git fetch --all -q >/dev/null 2>&1 && sudo git checkout -f "${REPO_BRANCH}" >/dev/null 2>&1 || sudo git checkout -b "${REPO_BRANCH}" "origin/${REPO_BRANCH}" >/dev/null 2>&1 || true && sudo git reset --hard "origin/${REPO_BRANCH}" >/dev/null 2>&1)
    elif [ -d "${TARGET_DIR}" ] && [ "$(ls -A "${TARGET_DIR}" 2>/dev/null)" ]; then
        TEMP_CLONE=$(mktemp -d)
        sudo git clone -b "${REPO_BRANCH}" -q "${REPO_URL}" "${TEMP_CLONE}" > /dev/null 2>&1
        sudo cp -rf "${TEMP_CLONE}"/* "${TARGET_DIR}/" 2>/dev/null || true
        sudo cp -rf "${TEMP_CLONE}"/.git "${TARGET_DIR}/" 2>/dev/null || true
        sudo rm -rf "${TEMP_CLONE}"
    else
        sudo git clone -b "${REPO_BRANCH}" -q "${REPO_URL}" "${TARGET_DIR}" > /dev/null 2>&1
    fi
    echo "✔ [SUCESSO PREINSTALL] Repositório atualizado e pronto para uso."

    echo "=== [SRE PREINSTALL] Sanitizando ambiente de produção ==="
    sudo rm -rf "${TARGET_DIR}/docs" "${TARGET_DIR}/README.md" "${TARGET_DIR}/LICENSE" 2>/dev/null || true
    sudo mkdir -p "${TARGET_DIR}/core/config"

    echo "=== [SRE PREINSTALL] Configurando resolvedor de rede perimetral (dnsmasq) no Host ==="
    sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    sudo sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    sudo systemctl restart systemd-resolved 2>/dev/null || true

    sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
    cat << EOC | sudo tee /etc/dnsmasq.conf > /dev/null
listen-address=127.0.0.1,172.17.0.1
bind-dynamic
server=8.8.8.8
server=1.1.1.1
conf-dir=/etc/dnsmasq.d,*.conf

# IPSET ALLOWED DOMAINS (CORE TLS, CERTIFICADOS & REPOSITÓRIOS DO HOST)
ipset=/letsencrypt.org/ALLOWED_DOMAINS
ipset=/lencr.org/ALLOWED_DOMAINS
ipset=/zerossl.com/ALLOWED_DOMAINS
ipset=/github.com/ALLOWED_DOMAINS
ipset=/raw.githubusercontent.com/ALLOWED_DOMAINS

domain-needed
bogus-priv
EOC

    IF_DOCKER_ACTIVE=$(systemctl is-active docker 2>/dev/null || echo "inactive")
    if [ -f /etc/docker/daemon.json ] && grep -q "172.17.0.1" /etc/docker/daemon.json 2>/dev/null && [ "$IF_DOCKER_ACTIVE" = "active" ]; then
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] Docker Engine e dnsmasq já vinculados ao Gateway local. Preservando containers."
        sudo systemctl restart dnsmasq 2>/dev/null || true
    else
        echo "=== [SRE PREINSTALL] Vinculando Docker Engine ao Gateway local ==="
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
        echo "=== [SRE PREINSTALL] Reiniciando daemons de rede e virtualização do Host ==="
        sudo systemctl restart dnsmasq docker
    fi

    if [ -n "$SUDO_USER" ]; then
        sudo usermod -aG docker "$SUDO_USER"
    fi

    if [ -f /swapfile ] && grep -q '/swapfile' /etc/fstab 2>/dev/null; then
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] Memória Virtual Swap (4GB) já estruturada e ativa."
    else
        echo "=== [SRE PREINSTALL] Criando Memória Virtual de Amortecimento (Swap 4GB) ==="
        sudo swapoff -a 2>/dev/null || true
        sudo rm -f /swapfile /swap.img 2>/dev/null || true
        sudo sed -i '/swap/d' /etc/fstab 2>/dev/null || true

        sudo fallocate -l 4G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile >/dev/null 2>&1
        sudo swapon /swapfile >/dev/null 2>&1
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
        echo "➜ [SUCESSO PREINSTALL] Swap 4GB criado e registrado no fstab."
    fi

    echo "=== [SRE PREINSTALL] Limpeza final antes do install.sh ==="
    sudo apt-get clean
    sudo rm -rf /var/lib/apt/lists/*
    sudo rm -f "$NOSSO_STAMP"

    INTERFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n 1)

    if [ -z "$INTERFACE" ]; then
        INTERFACE=$(ip link show | grep -E '^[0-9]+: e' | cut -d: -f2 | tr -d ' ' | head -n 1)
        sudo ip link set "$INTERFACE" up || true
        sudo dhclient -v "$INTERFACE" 2>/dev/null || true
        sleep 3
    fi

    IP_CIDR=$(ip -4 addr show dev "$INTERFACE" 2>/dev/null | grep inet | awk '{print $2}' | head -n 1)
    GATEWAY=$(ip -4 route show default 2>/dev/null | awk '{print $3}' | head -n 1)
    MAC_ADDR=$(ip link show dev "$INTERFACE" 2>/dev/null | grep link/ether | awk '{print $2}' | head -n 1)

    if [ -z "$IP_CIDR" ]; then
        sudo dhclient -r "$INTERFACE" 2>/dev/null || true
        sudo dhclient "$INTERFACE" 2>/dev/null || true
        sleep 2
        IP_CIDR=$(ip -4 addr show dev "$INTERFACE" | grep inet | awk '{print $2}' | head -n 1)
        GATEWAY=$(ip -4 route show default | awk '{print $3}' | head -n 1)
    fi

    if [ -z "$IP_CIDR" ] || [ -z "$GATEWAY" ]; then
        echo "🚨 [ERRO CRÍTICO PREINSTALL] A interface $INTERFACE não recebeu IP via DHCP!"
        exit 1
    fi

    if [ -f /etc/netplan/99-static-sre.yaml ] && grep -q "$IP_CIDR" /etc/netplan/99-static-sre.yaml 2>/dev/null; then
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] IP de rede estático já configurado (${IP_CIDR}). Preservando netplan."
    else
        echo "➜ [SRE PREINSTALL] Fixando IP de rede estático para a aplicação (${IP_CIDR})..."
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
        sudo netplan apply 2>/dev/null || true
        echo "✔ [SUCESSO PREINSTALL] IP de rede estático fixado e protegido contra trocas."
    fi

    echo "=== [SRE PREINSTALL] Configurando mensagem customizada de boas-vindas no login ==="
    sudo chmod -x /etc/update-motd.d/* 2>/dev/null || true

    sudo cat << 'EOM' | sudo tee /etc/update-motd.d/99-sre-banner > /dev/null
#!/bin/bash
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

USUARIO_LOGADO="${PAM_USER:-$(logname 2>/dev/null || who am i | awk '{print $1}')}"
[ -z "$USUARIO_LOGADO" ] && USUARIO_LOGADO=$(whoami)

HOST_SHORT=$(hostname -s)
DOMAIN_NAME=$(dnsdomainname 2>/dev/null || domainname 2>/dev/null || echo "")
if [ -n "$DOMAIN_NAME" ] && [ "$DOMAIN_NAME" != "(none)" ]; then
    HOST_FQDN="${HOST_SHORT}.${DOMAIN_NAME}"
else
    HOST_FQDN=$(hostname -f 2>/dev/null)
    [ "$HOST_FQDN" = "$HOST_SHORT" ] && HOST_FQDN="${HOST_SHORT}.local"
fi

MAIN_IFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n 1)
[ -z "$MAIN_IFACE" ] && MAIN_IFACE="eth0"
ETH_IP=$(ip -4 addr show dev "$MAIN_IFACE" 2>/dev/null | grep inet | awk '{print $2}' || echo "Sem Link/Offline")

UBUNTU_VER=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
KERNEL_VER=$(uname -r)

CPU_MODEL=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//' | xargs)
[ -z "$CPU_MODEL" ] && CPU_MODEL="Virtual Processor"
CPU_CORES=$(nproc)

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

    echo "=== [SRE PREINSTALL] Limpando rastros da sessão ==="
    sudo bash -c "cat /dev/null > /root/.bash_history 2>/dev/null || true"
    if [ -n "$SUDO_USER" ]; then
        USER_HOME_REAL=$(eval echo "~$SUDO_USER")
        cat /dev/null > "$USER_HOME_REAL/.bash_history" 2>/dev/null || true
    fi
fi

# =========================================================================
# FASE 2: GERADOR DE AMBIENTE MULTI-CLIENTE (SRE FACTORY)
# =========================================================================
SCRIPTS_DIR="./core/scripts"
[ -d "${TARGET_DIR}/core/scripts" ] && SCRIPTS_DIR="${TARGET_DIR}/core/scripts"
[ ! -d "$SCRIPTS_DIR" ] && [ -d "/opt/daemind/core/scripts" ] && SCRIPTS_DIR="/opt/daemind/core/scripts"

# Inspeção desacoplada de hardware do Host
TOTAL_CPUS_HOST=4
TOTAL_RAM_GB_HOST=8
TOTAL_RAM_MB_HOST=8192
IS_MODEST_SERVER="false"

if [ -f "${SCRIPTS_DIR}/autotune.sh" ]; then
    source "${SCRIPTS_DIR}/autotune.sh" "${TARGET_DIR}/.env" get_hardware_info 2>/dev/null || true
    TOTAL_CPUS_HOST="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    TOTAL_RAM_GB_HOST="${SYSTEM_TOTAL_RAM_GB:-${TOTAL_RAM_GB:-8}}"
    TOTAL_RAM_MB_HOST="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"
    IS_MODEST_SERVER="${IS_MODEST_SERVER:-false}"
fi

if [ "$USE_TUI" = "true" ] && command -v dialog &>/dev/null; then
    # =====================================================================
    # 🖥️ DIALOG TUI ENGINE COM NAVEGAÇÃO MULTI-PASSO (AVANÇAR / VOLTAR)
    # =====================================================================
    gerar_dialogrc

    # 🖥️ Tela 0: Boas-vindas & Apresentação Oficial daemind.
    BANNER_TEXT=$(cat << 'EOF'
============================================================
                   d a e m i n d .
     Sistema Operacional Autônomo para Negócios Digitais
============================================================

• Arquitetura SRE Production-Ready
• Topologia Zero-Trust & Self-Hosted Soberana
• Isolamento Perimetral & Virtualização Otimizada

Bem-vindo ao Assistente de Deploy Automatizado do daemind.
Navegue usando [Tab], [Setas], [Barra de Espaço] ou [Mouse].
EOF
)
    tui_dialog --title "daemind. - Sistema Operacional Autônomo" --msgbox "$BANNER_TEXT" 15 66 || true

    # 🔄 Tela 1: Reutilização de Cache (se existir)
    if [ -f "$CACHE_WIZARD_FILE" ]; then
        # Salva em memória as variáveis passadas explicitamente pelo operador na sessão/CLI para não serem sobrescritas pelo cache antigo
        CLI_PASSED_VARS=()
        for v in $(compgen -v | grep -E '^(USE_|OVERRIDE_|EMPRESA|ROUTING_|STORAGE_|S3_|OPENAI_|ANTHROPIC_|GEMINI_|DEEPSEEK_|OPENROUTER_)'); do
            [ -n "${!v:-}" ] && CLI_PASSED_VARS+=("$v=${!v}")
        done

        if tui_dialog --title "Reuso de Configurações" --yesno "Detectamos configurações salvas de uma sessão anterior em:\n${CACHE_WIZARD_FILE}\n\nDeseja reutilizar as respostas salvas para acelerar o deploy?" 10 65; then
            RESP_REUSE="s"
            sed -i 's/\r$//' "$CACHE_WIZARD_FILE" 2>/dev/null || true
            set -a
            source "$CACHE_WIZARD_FILE" 2>/dev/null || true
            set +a

            # Precedência SRE: Restaura variáveis explícitas passadas no ambiente/CLI (Override)
            for item in "${CLI_PASSED_VARS[@]}"; do
                eval "$item"
            done
        else
            RESP_REUSE="n"
            for var in $(compgen -v | grep -E '^(EMPRESA|USE_|IP_|HOST_|CPU_|MEM_|RES_|S3_|ROUTING_|CLIENTE_|TS_|DB_|OPENAI_|ANTHROPIC_|GEMINI_|DEEPSEEK_|OPENROUTER_|REDE_|BASE_)'); do
                unset "$var" 2>/dev/null || true
            done
        fi
    fi

    # Descoberta Dinâmica de Módulos Desacoplados (varre install_*.sh excluindo prefixos numéricos como 0ts, 1ia)
    BASE_MODS_LIST=()
    _scan_dir="$SCRIPTS_DIR"
    [ ! -d "$_scan_dir" ] && _scan_dir="./core/scripts"
    [ ! -d "$_scan_dir" ] && _scan_dir="${TARGET_DIR}/core/scripts"
    [ ! -d "$_scan_dir" ] && _scan_dir="/opt/daemind/core/scripts"

    if [ -d "$_scan_dir" ]; then
        for s_file in "$_scan_dir"/install_*.sh; do
            [ ! -f "$s_file" ] && continue
            b_name=$(basename "$s_file" .sh | sed 's/^install_//')
            # Ignora módulos core com prefixo numérico (ex: 0ts, 1ia)
            [[ "$b_name" =~ ^[0-9] ]] && continue
            BASE_MODS_LIST+=("$b_name")
        done
    fi
    SORTED_MOD_FILES=($(printf "%s\n" "${BASE_MODS_LIST[@]}" | sort -u))

    # MÁQUINA DE ESTADOS DO WIZARD TUI (Etapas 2 a 7)
    W_STEP=2
    while [ "$W_STEP" -ge 2 ] && [ "$W_STEP" -le 7 ]; do
        set +e
        case "$W_STEP" in
            2)
                # 🛡️ SRE GUARDRAIL: Carrega estado de stack previamente provisionada em /opt/daemind/.env
                EXISTING_ENV="/opt/daemind/.env"
                PREV_EMPRESA=""
                PREV_NOME=""
                PREV_SOBRENOME=""
                PREV_EMAIL=""
                PREV_PASSWORD=""
                IS_PROVISIONED=0

                if [ -f "$EXISTING_ENV" ] || (command -v sudo >/dev/null 2>&1 && sudo test -f "$EXISTING_ENV" 2>/dev/null); then
                    local _env_content=""
                    if [ -r "$EXISTING_ENV" ]; then
                        _env_content=$(cat "$EXISTING_ENV" 2>/dev/null || true)
                    elif command -v sudo >/dev/null 2>&1; then
                        _env_content=$(sudo cat "$EXISTING_ENV" 2>/dev/null || true)
                    fi

                    if [ -n "$_env_content" ]; then
                        PREV_EMPRESA=$(echo "$_env_content" | grep -E '^(EMPRESA|PREFIXO_CONTAINER)=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
                        PREV_NOME=$(echo "$_env_content" | grep -E '^CLIENTE_NOME=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
                        PREV_SOBRENOME=$(echo "$_env_content" | grep -E '^CLIENTE_SOBRENOME=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
                        PREV_EMAIL=$(echo "$_env_content" | grep -E '^(CLIENTE_EMAIL|TS_EMAIL)=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
                        PREV_PASSWORD=$(echo "$_env_content" | grep -E '^DB_PASSWORD=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
                        [ -n "$PREV_EMPRESA" ] && IS_PROVISIONED=1
                    fi
                fi

                # 🏢 Tela 2: Identidade Corporativa, Administrador & Senha Mestra (com campos de senha mascarados)
                FORM_OUT=$(tui_dialog_step --title "Passo 1/6: Identidade da Empresa, Administrador & Senha Mestra" \
                    --mixedform "Preencha os dados corporativos e defina a Senha Mestra de segurança da stack.\n🔒 Regra da Senha: 8-12 chars, mín. 1 MAIÚSCULA, 1 NÚMERO e 1 ESPECIAL (- _ * ~ ^)" 20 90 0 \
                    "ID da Empresa (Max 12 chars):"          1 1 "${EMPRESA:-$PREV_EMPRESA}"           1 38 46 12 0 \
                    "Nome do Administrador:"                  2 1 "${CLIENTE_NOME:-$PREV_NOME}"      2 38 46 30 0 \
                    "Sobrenome do Administrador:"             3 1 "${CLIENTE_SOBRENOME:-$PREV_SOBRENOME}" 3 38 46 30 0 \
                    "E-mail Corporativo:"                     4 1 "${CLIENTE_EMAIL:-$PREV_EMAIL}"     4 38 46 60 0 \
                    "Senha Mestra (8-12 chars):"              6 1 "${DB_PASSWORD:-$PREV_PASSWORD}"       6 38 46 12 1 \
                    "Confirme a Senha Mestra:"                7 1 "${DB_PASSWORD2:-${DB_PASSWORD:-$PREV_PASSWORD}}"      7 38 46 12 1 \
                    )
                STATUS_FORM=$?
                if [ $STATUS_FORM -ne 0 ]; then
                    if tui_dialog --title "Cancelar Instalação" --yesno "Deseja realmente cancelar e sair do instalador?" 8 60; then
                        clear 2>/dev/null || true
                        echo "Instalação cancelada pelo usuário."
                        exit 0
                    else
                        continue
                    fi
                fi

                # Sanitização rigorosa de caracteres de escape e ANSI
                clean_tui_field() {
                    local raw="$1"
                    echo "$raw" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | xargs 2>/dev/null || echo "$raw"
                }

                EMPRESA=$(clean_tui_field "$(echo "$FORM_OUT" | sed -n '1p')")
                CLIENTE_NOME=$(clean_tui_field "$(echo "$FORM_OUT" | sed -n '2p')")
                CLIENTE_SOBRENOME=$(clean_tui_field "$(echo "$FORM_OUT" | sed -n '3p')")
                CLIENTE_EMAIL=$(clean_tui_field "$(echo "$FORM_OUT" | sed -n '4p')")
                DB_PASSWORD=$(clean_tui_field "$(echo "$FORM_OUT" | sed -n '5p')")
                DB_PASSWORD2=$(clean_tui_field "$(echo "$FORM_OUT" | sed -n '6p')")

                # 🛡️ SRE GUARDRAIL CASE 1: Mesma Empresa já provisionada -> Impede alteração de credenciais que causem divergência de banco/volumes
                if [ "$IS_PROVISIONED" -eq 1 ] && [ "$EMPRESA" = "$PREV_EMPRESA" ]; then
                    if [ -n "$PREV_EMAIL" ] && [ "$CLIENTE_EMAIL" != "$PREV_EMAIL" ] || \
                       [ -n "$PREV_PASSWORD" ] && [ "$DB_PASSWORD" != "$PREV_PASSWORD" ] || \
                       [ -n "$PREV_NOME" ] && [ "$CLIENTE_NOME" != "$PREV_NOME" ] || \
                       [ -n "$PREV_SOBRENOME" ] && [ "$CLIENTE_SOBRENOME" != "$PREV_SOBRENOME" ]; then
                        tui_dialog --title "⚠️ Bloqueio de Segurança SRE: Stack Já Provisionada" --msgbox "A stack '${EMPRESA}' já foi provisionada anteriormente com este ID.\n\nPara evitar quebra de autenticação transacional e corrupção de volumes no banco de dados, os dados cadastrais e a Senha Mestra estão travados para este ID de Empresa.\n\n➜ Se desejar redefinir totalmente a stack, altere o ID da Empresa para um novo identificador.\n➜ As credenciais salvas em /opt/daemind/.env serão mantidas." 14 74 || true
                        CLIENTE_NOME="$PREV_NOME"
                        CLIENTE_SOBRENOME="$PREV_SOBRENOME"
                        CLIENTE_EMAIL="$PREV_EMAIL"
                        DB_PASSWORD="$PREV_PASSWORD"
                        DB_PASSWORD2="$PREV_PASSWORD"
                    fi
                fi

                # 🛡️ SRE GUARDRAIL CASE 2: Troca de ID da Empresa em Host com Stack Existente -> Destruição e Reset Transacional
                if [ "$IS_PROVISIONED" -eq 1 ] && [ -n "$EMPRESA" ] && [ "$EMPRESA" != "$PREV_EMPRESA" ]; then
                    if ! tui_dialog --title "⚠️ ALERTA CRÍTICO SRE: MUDANÇA DE ID DE EMPRESA" --yesno "Atenção: Foi detectada uma stack ativa pertencente à empresa:\n➜ [ ${PREV_EMPRESA} ]\n\nVocê selecionou um NOVO ID de empresa:\n➜ [ ${EMPRESA} ]\n\nEsta operação é DESTRUTIVA e irá:\n1. Executar disable e desprovisionamento de todos os módulos da empresa antiga.\n2. Limpar todas as entradas no Caddyfile, DNS e cards do index.html.\n3. Parar e remover todos os contêineres e volumes da stack anterior.\n4. Recriar a nova infraestrutura isolada para '${EMPRESA}'.\n\nDeseja realmente DESTRUIR a stack anterior e criar a nova do zero?" 17 76; then
                        EMPRESA="$PREV_EMPRESA"
                        CLIENTE_NOME="$PREV_NOME"
                        CLIENTE_SOBRENOME="$PREV_SOBRENOME"
                        CLIENTE_EMAIL="$PREV_EMAIL"
                        DB_PASSWORD="$PREV_PASSWORD"
                        DB_PASSWORD2="$PREV_PASSWORD"
                        continue
                    fi

                    # Rotina de Destruição e Desprovisionamento Limpo da Stack Antiga
                    clear 2>/dev/null || true
                    echo "=== [SRE GUARDRAIL] Desprovisionando e limpando stack da empresa anterior: ${PREV_EMPRESA} ==="
                    if [ -d "$SCRIPTS_DIR" ]; then
                        for s_mod in "$SCRIPTS_DIR"/install_*.sh; do
                            [ ! -f "$s_mod" ] && continue
                            if grep -q "disable()" "$s_mod" 2>/dev/null; then
                                echo "➜ Executando disable do módulo: $(basename "$s_mod")"
                                PREFIXO_CONTAINER="$PREV_EMPRESA" bash "$s_mod" "${TARGET_DIR}" "disable" 2>/dev/null || true
                            fi
                        done
                    fi

                    # 🛡️ Tenta docker compose down para encerrar tudo de forma limpa
                    if [ -d "$TARGET_DIR" ]; then
                        echo "➜ Derrubando contêineres via docker compose..."
                        (cd "$TARGET_DIR" && sudo docker compose down -v --remove-orphans 2>/dev/null || true)
                    fi

                    # 🔫 Fallback cirúrgico: força remoção de QUALQUER container com o prefixo do tenant antigo
                    # (cobre containers core que o compose down pode ter perdido se o .yml foi modificado)
                    echo "➜ Verificando containers residuais com prefixo '${PREV_EMPRESA}_'..."
                    _residual_containers=$(sudo docker ps -a --filter "name=^${PREV_EMPRESA}_" --format "{{.Names}}" 2>/dev/null || true)
                    if [ -n "$_residual_containers" ]; then
                        echo "➜ Containers residuais encontrados — forçando remoção:"
                        echo "$_residual_containers" | while read -r _cname; do
                            echo "   ✗ Removendo: ${_cname}"
                            sudo docker stop "$_cname" 2>/dev/null || true
                            sudo docker rm -f "$_cname" 2>/dev/null || true
                        done
                    else
                        echo "✔ Nenhum container residual '${PREV_EMPRESA}_*' encontrado."
                    fi

                    # 🗑️ Remove volumes com prefixo do tenant antigo
                    echo "➜ Verificando volumes residuais com prefixo '${PREV_EMPRESA}_'..."
                    _residual_volumes=$(sudo docker volume ls --filter "name=^${PREV_EMPRESA}_" --format "{{.Name}}" 2>/dev/null || true)
                    if [ -n "$_residual_volumes" ]; then
                        echo "➜ Volumes residuais encontrados — expurgando:"
                        echo "$_residual_volumes" | while read -r _vname; do
                            echo "   ✗ Removendo volume: ${_vname}"
                            sudo docker volume rm -f "$_vname" 2>/dev/null || true
                        done
                    fi

                    # Remove diretório de volumes físicos e chave de backup privada antiga
                    sudo rm -rf "${TARGET_DIR}/volumes" 2>/dev/null || true
                    rm -f "${USER_REAL_HOME}/CHAVE_PRIVADA_BACKUP_${PREV_EMPRESA}.asc" "${TARGET_DIR}/CHAVE_PRIVADA_BACKUP_${PREV_EMPRESA}.asc" 2>/dev/null || true
                    echo "✔ [SUCESSO SRE] Stack anterior limpa com sucesso. Prosseguindo com o provisionamento de: ${EMPRESA}"
                    sleep 2
                fi

                ERR_MSG=""
                if [ -z "$EMPRESA" ] || [ -z "$CLIENTE_NOME" ] || [ -z "$CLIENTE_SOBRENOME" ] || [ -z "$CLIENTE_EMAIL" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DB_PASSWORD2" ]; then
                    ERR_MSG="Todos os campos são obrigatórios."
                elif [ ${#EMPRESA} -gt 12 ] || ! [[ "$EMPRESA" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    ERR_MSG="O ID da Empresa é obrigatório (máximo 12 caracteres alfanuméricos)."
                elif ! [[ "$CLIENTE_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
                    ERR_MSG="E-mail corporativo inválido."
                elif [ ${#DB_PASSWORD} -lt 8 ] || [ ${#DB_PASSWORD} -gt 12 ]; then
                    ERR_MSG="A Senha Mestra deve ter entre 8 e 12 caracteres."
                elif ! [[ "$DB_PASSWORD" =~ [A-Z] ]]; then
                    ERR_MSG="A Senha Mestra deve conter ao menos 1 letra MAIÚSCULA."
                elif ! [[ "$DB_PASSWORD" =~ [0-9] ]]; then
                    ERR_MSG="A Senha Mestra deve conter ao menos 1 NÚMERO."
                elif [[ "$DB_PASSWORD" =~ [@#\&/:\?=\|%] ]]; then
                    ERR_MSG="A Senha Mestra contém caracteres inválidos de URI (@#&/:?=|%). Use apenas: - _ * ~ ^"
                elif ! [[ "$DB_PASSWORD" =~ [-_*~^] ]]; then
                    ERR_MSG="A Senha Mestra deve conter ao menos 1 caractere especial seguro (- _ * ~ ^)."
                elif [ "$DB_PASSWORD" != "$DB_PASSWORD2" ]; then
                    ERR_MSG="As senhas digitadas não conferem."
                fi

                if [ -n "$ERR_MSG" ]; then
                    tui_dialog --title "Erro de Validação" --msgbox "$ERR_MSG" 9 65 || true
                    continue
                fi

                save_wizard_cache "EMPRESA" "$EMPRESA"
                save_wizard_cache "CLIENTE_NOME" "$CLIENTE_NOME"
                save_wizard_cache "CLIENTE_SOBRENOME" "$CLIENTE_SOBRENOME"
                save_wizard_cache "CLIENTE_EMAIL" "$CLIENTE_EMAIL"
                save_wizard_cache "DB_PASSWORD" "$DB_PASSWORD"
                save_wizard_cache "DB_PASSWORD2" "$DB_PASSWORD2"
                W_STEP=3
                ;;

            3)
                # 🌐 Tela 3: Topologia de Borda & Roteamento (Desacoplado via install_0ts.sh)
                if [ -f "${SCRIPTS_DIR}/install_0ts.sh" ]; then
                    source "${SCRIPTS_DIR}/install_0ts.sh" "${TARGET_DIR}" "load_only" 2>/dev/null || true
                    if ! collect_wizard_inputs_tui; then
                        W_STEP=2
                        continue
                    fi
                fi
                W_STEP=4
                ;;


            4)
                # 🧩 Tela 4: Seleção Dinâmica de Módulos (Stack Planner)
                CHECKLIST_OPTS=()
                for m_name in "${SORTED_MOD_FILES[@]}"; do
                    desc=""
                    mod_script=""
                    for cand_dir in "$SCRIPTS_DIR" "./core/scripts" "${TARGET_DIR}/core/scripts" "/opt/daemind/core/scripts"; do
                        if [ -f "${cand_dir}/install_${m_name}.sh" ]; then
                            mod_script="${cand_dir}/install_${m_name}.sh"
                            break
                        fi
                    done

                    var_use="USE_$(echo "$m_name" | tr '[:lower:]' '[:upper:]')"
                    val_cur="${!var_use:-}"

                    is_hw_ok=0
                    # Contrato Desacoplado: Consulta a função is_hardware_supported do próprio módulo se ela existir
                    # Blindagem SRE contra OOM: Oculta o módulo se não houver sizing, a menos que o operador tenha feito override explícito (USE_<MODULO>=s ou OVERRIDE_TOTAL_*)
                    if [ -n "$mod_script" ] && [ -f "$mod_script" ]; then
                        if grep -q "is_hardware_supported()" "$mod_script" 2>/dev/null; then
                            # Executa com as variáveis de ambiente atuais preservadas
                            if ! env "${INITIAL_USER_OVERRIDES[@]}" bash "$mod_script" "${TARGET_DIR}" "is_hardware_supported" 2>/dev/null; then
                                is_hw_ok=1
                                # Se o operador exportou explicitamente ou definiu USE_<MODULO>=s, exibe o módulo com badge
                                v_name="USE_$(echo "$m_name" | tr '[:lower:]' '[:upper:]')"
                                v_val="${!v_name:-${val_cur:-}}"
                                if ! [[ "$v_val" =~ ^(s|S|true|TRUE|1)$ ]]; then
                                    continue
                                fi
                            fi
                        fi
                        desc=$(sed -n '3p' "$mod_script" 2>/dev/null | sed -e 's/^#[[:space:]]*//' -e 's/\r//g' || true)
                    fi
                    [ -z "$desc" ] && desc="Módulo Extensível ${m_name}"
                    [ "$is_hw_ok" -eq 1 ] && desc="⚠️ [SUBDIMENSIONADO] ${desc}"
                    
                    if [ -n "$val_cur" ]; then
                        if [[ "$val_cur" =~ ^(n|N|false|FALSE|0)$ ]]; then
                            st_opt="off"
                        else
                            st_opt="on"
                        fi
                    else
                        # Padrão para primeira instalação: Módulos subdimensionados ou storage iniciam desmarcados (off)
                        if [ "$is_hw_ok" -eq 1 ] || [ "$m_name" = "s3minio" ]; then
                            st_opt="off"
                        else
                            st_opt="on"
                        fi
                    fi

                    CHECKLIST_OPTS+=("$m_name" "$desc" "$st_opt")
                done

                SEL_MODS=$(tui_dialog_step --title "Passo 3/6: Seleção de Microsserviços da Stack" \
                    --checklist "Marque com [Espaço] os módulos desejados.\n⚠️  ATENÇÃO: Desmarcar um item ativo irá PARAR o container, remover a rota no Caddy e ocultar o card do portal." 24 82 15 \
                    "${CHECKLIST_OPTS[@]}")
                ST_M=$?
                if [ "$ST_M" -ne 0 ]; then
                    W_STEP=3
                    continue
                fi

                for m_name in "${SORTED_MOD_FILES[@]}"; do
                    var_use="USE_$(echo "$m_name" | tr '[:lower:]' '[:upper:]')"
                    if echo " $SEL_MODS " | grep -q " $m_name "; then
                        eval "$var_use=\"s\""
                        save_wizard_cache "$var_use" "s"
                    else
                        eval "$var_use=\"n\""
                        save_wizard_cache "$var_use" "n"
                    fi
                done

                # Sub-seleção Dinâmica de Storage (Desacoplado via install_s3minio.sh)
                if [ -f "${SCRIPTS_DIR}/install_s3minio.sh" ]; then
                    source "${SCRIPTS_DIR}/install_s3minio.sh" "${TARGET_DIR}" "load_only" 2>/dev/null || true
                    if ! collect_wizard_inputs_tui; then
                        W_STEP=4
                        continue
                    fi
                fi
                W_STEP=5
                ;;

            5)
                # 🤖 Tela 5: Roteamento & Credenciais de IA (Desacoplado via install_1ia.sh)
                if [ -f "${SCRIPTS_DIR}/install_1ia.sh" ]; then
                    source "${SCRIPTS_DIR}/install_1ia.sh" "${TARGET_DIR}" "load_only" 2>/dev/null || true
                    if ! collect_wizard_inputs_tui; then
                        W_STEP=4
                        continue
                    fi
                    # SRE FIX: Recarrega as chaves e provedores exportados pelo wizard de IA
                    if [ -f "$CACHE_WIZARD_FILE" ]; then
                        set -a
                        source "$CACHE_WIZARD_FILE" 2>/dev/null || true
                        set +a
                    fi
                fi
                W_STEP=6
                ;;



            6)
                # 🔌 Tela 6: Mapeamento de Sub-rede Privada (Bridge CIDR)
                R1_ST="on"; R2_ST="off"; R3_ST="off"; R4_ST="off"
                [ "${REDE_CHOICE:-1}" = "2" ] && { R1_ST="off"; R2_ST="on"; }
                [ "${REDE_CHOICE:-1}" = "3" ] && { R1_ST="off"; R3_ST="on"; }
                [ "${REDE_CHOICE:-1}" = "4" ] && { R1_ST="off"; R4_ST="on"; }

                REDE_CHOICE=$(tui_dialog_step --title "Passo 5/6: Rede Privada dos Contêineres (Bridge)" \
                    --radiolist "Escolha o endereçamento IP interno da malha de microsserviços:" 13 70 4 \
                    1 "172.25.0.0/24 (Padrão SRE Isolado)" "$R1_ST" \
                    2 "10.50.0.0/24 (AWS VPC Peering Seguro)" "$R2_ST" \
                    3 "192.168.200.0/24 (On-Premise Seguro)" "$R3_ST" \
                    4 "Customizado (Digitar 3 primeiros octetos)" "$R4_ST" \
                    )
                ST_RC=$?
                if [ $ST_RC -ne 0 ]; then
                    W_STEP=5
                    continue
                fi
                [ -z "$REDE_CHOICE" ] && REDE_CHOICE="1"

                case "$REDE_CHOICE" in
                    1) BASE_IP="172.25.0" ;;
                    2) BASE_IP="10.50.0" ;;
                    3) BASE_IP="192.168.200" ;;
                    4)
                       BASE_IP=$(tui_dialog_step --title "Sub-rede Customizada" \
                           --inputbox "Digite os 3 primeiros octetos (Ex: 10.99.0):" 8 60 "${BASE_IP:-10.99.0}" \
                           )
                       if [ $? -ne 0 ]; then
                           W_STEP=6
                           continue
                       fi
                       [ -z "$BASE_IP" ] && BASE_IP="172.25.0"
                       ;;
                    *)
                       REDE_CHOICE="1"
                       BASE_IP="172.25.0"
                       ;;
                esac
                save_wizard_cache "REDE_CHOICE" "$REDE_CHOICE"
                save_wizard_cache "BASE_IP" "$BASE_IP"
                W_STEP=7
                ;;

            7)
                # 📊 Tela 7: Resumo Geral de Governança & Confirmação de Deploy
                active_mods_formatted=""
                current_line=""
                local_mod_count=0
                for m_name in "${SORTED_MOD_FILES[@]}"; do
                    var_use="USE_$(echo "$m_name" | tr '[:lower:]' '[:upper:]')"
                    if [[ "${!var_use}" =~ ^[Ss]$ ]]; then
                        local_mod_count=$((local_mod_count + 1))
                        # Alinhamento por preenchimento de espaços exato
                        pad="                   " # 19 chars
                        entry="[X] ${m_name}"
                        len=${#entry}
                        diff=$(( 22 - len ))
                        [ $diff -lt 1 ] && diff=1
                        item_fmt="${entry}${pad:0:$diff}"
                        
                        current_line="${current_line}${item_fmt}"
                        if [ $(( local_mod_count % 3 )) -eq 0 ]; then
                            if [ -z "$active_mods_formatted" ]; then
                                active_mods_formatted="  ${current_line}"
                            else
                                active_mods_formatted="${active_mods_formatted}
  ${current_line}"
                            fi
                            current_line=""
                        fi
                    fi
                done
                if [ -n "$current_line" ]; then
                    if [ -z "$active_mods_formatted" ]; then
                        active_mods_formatted="  ${current_line}"
                    else
                        active_mods_formatted="${active_mods_formatted}
  ${current_line}"
                    fi
                fi

                ai_list_formatted="  [X] OpenRouter (Obrigatório)"
                [ -n "${OPENAI_API_KEY:-}" ]    && ai_list_formatted="${ai_list_formatted}  [X] OpenAI"
                [ -n "${ANTHROPIC_API_KEY:-}" ] && ai_list_formatted="${ai_list_formatted}  [X] Anthropic Claude"
                if [ -n "${GEMINI_API_KEY:-}" ] || [ "${FREE_GEMINI:-0}" = "1" ] || [[ "${RESP_GEMINI_FREE:-}" =~ ^[Ss]$ ]]; then
                    [ "${FREE_GEMINI:-0}" = "1" ] && ai_list_formatted="${ai_list_formatted}  [X] Gemini (Free Flash/Gemma)" || ai_list_formatted="${ai_list_formatted}  [X] Gemini (Pro)"
                fi
                [ -n "${DEEPSEEK_API_KEY:-}" ]  && ai_list_formatted="${ai_list_formatted}  [X] DeepSeek"

                topologia_str="BYODNS (${CUSTOM_DOMAIN})"
                [ "$ROUTING_CHOICE" = "1" ] && topologia_str="Tailscale VPN Soberana"

                SUMMARY_MSG="• Identidade da Empresa:    ${EMPRESA}
• Administrador:            ${CLIENTE_NOME} ${CLIENTE_SOBRENOME}
• E-mail Corporativo:       ${CLIENTE_EMAIL}
• Topologia de Borda:       ${topologia_str}
• Modo de Storage:          ${STORAGE_MODE}
• Sub-rede Privada:         ${BASE_IP}.0/24

• Provedores de IA:
${ai_list_formatted}

• Módulos Ativos (${local_mod_count}):
${active_mods_formatted}

----------------------------------------------------------------------
Deseja confirmar e iniciar a instalação imediatamente?"

                if tui_dialog --no-collapse --title "Passo 6/6: Confirmação de Deploy da Stack" --yes-label "Sim" --no-label "Não" --yesno "$SUMMARY_MSG" 24 82; then
                    EXECUTAR_INSTALL="s"
                    break
                else
                    # Se escolher "Não" no resumo, permite voltar ao passo 6 para ajustar
                    if tui_dialog --title "Ajustar Configurações" --yes-label "Sim" --no-label "Não" --yesno "Deseja voltar e alterar alguma informação antes de iniciar?" 8 65; then
                        W_STEP=6
                        continue
                    else
                        clear 2>/dev/null || true
                        echo "Instalação cancelada pelo operador no resumo."
                        exit 0
                    fi
                fi
                ;;
        esac
    done

    # Limpa a tela completamente ao sair do Wizard e entrar na fase de logs/deploy
    clear 2>/dev/null || true
    set -e

else
    # =====================================================================
    # 📟 MODO CLI CLÁSSICO (--cli / SEM TTY / HEADLESS)
    # =====================================================================
    echo ""
    echo -e "\e[36m=====================================================================\e[0m"
    echo -e "\e[36m      [SRE FACTORY PREINSTALL] GERADOR DE AMBIENTE MULTI-CLIENTE     \e[0m"
    echo -e "\e[36m=====================================================================\e[0m"

    if [ -f "$CACHE_WIZARD_FILE" ]; then
        echo ""
        echo -e "\e[32m✔ [CACHE PREINSTALL] Respostas de sessão anterior encontradas em ${CACHE_WIZARD_FILE}\e[0m"
        
        RESP_REUSE="${AUTO_REUSE_CACHE:-${RESP_REUSE:-}}"
        if [ -n "$RESP_REUSE" ]; then
            echo -e "\e[32m✔ [AUTO-REUSE PREINSTALL] Reutilização de cache ativada (${RESP_REUSE}).\e[0m"
        else
            coletar_sn "Deseja reutilizar as respostas da sessão anterior?" RESP_REUSE "s" "false"
        fi

        if [ "$RESP_REUSE" = "n" ]; then
            rm -f "$CACHE_WIZARD_FILE" "${CACHE_WIZARD_FILE}.tmp" 2>/dev/null || true
            for var in $(compgen -v | grep -E '^(USE_|IP_|HOST_|CPU_|MEM_|RES_|S3_|ROUTING_|CLIENTE_|TS_|DB_|OPENAI_|ANTHROPIC_|GEMINI_|DEEPSEEK_|OPENROUTER_|REDE_|BASE_)'); do
                unset "$var" 2>/dev/null || true
            done
            echo -e "\e[33m➜ [CACHE PREINSTALL] Cache resetado. O wizard coletará todas as informações novamente.\e[0m"
        else
            echo -e "\e[32m➜ [CACHE PREINSTALL] Restaurando dados salvos da sessão anterior...\e[0m"
            sed -i 's/\r$//' "$CACHE_WIZARD_FILE" 2>/dev/null || true
            set -a
            source "$CACHE_WIZARD_FILE" 2>/dev/null || true
            set +a
        fi
    fi

    # 🛡️ SRE GUARDRAIL CLI: Carrega estado de stack previamente provisionada em /opt/daemind/.env
    EXISTING_ENV="/opt/daemind/.env"
    PREV_EMPRESA=""
    PREV_NOME=""
    PREV_SOBRENOME=""
    PREV_EMAIL=""
    PREV_PASSWORD=""
    IS_PROVISIONED=0

    if [ -f "$EXISTING_ENV" ] || (command -v sudo >/dev/null 2>&1 && sudo test -f "$EXISTING_ENV" 2>/dev/null); then
        local _cli_env_content=""
        if [ -r "$EXISTING_ENV" ]; then
            _cli_env_content=$(cat "$EXISTING_ENV" 2>/dev/null || true)
        elif command -v sudo >/dev/null 2>&1; then
            _cli_env_content=$(sudo cat "$EXISTING_ENV" 2>/dev/null || true)
        fi

        if [ -n "$_cli_env_content" ]; then
            PREV_EMPRESA=$(echo "$_cli_env_content" | grep -E '^(EMPRESA|PREFIXO_CONTAINER)=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
            PREV_NOME=$(echo "$_cli_env_content" | grep -E '^CLIENTE_NOME=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
            PREV_SOBRENOME=$(echo "$_cli_env_content" | grep -E '^CLIENTE_SOBRENOME=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
            PREV_EMAIL=$(echo "$_cli_env_content" | grep -E '^(CLIENTE_EMAIL|TS_EMAIL)=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
            PREV_PASSWORD=$(echo "$_cli_env_content" | grep -E '^DB_PASSWORD=' | head -n 1 | cut -d= -f2- | tr -d '"\r\n ')
            [ -n "$PREV_EMPRESA" ] && IS_PROVISIONED=1
        fi
    fi

    coletar_input "ID da Empresa Cliente (Max 12 chars, Ex: microsoft apple nvidia)" EMPRESA "false" "^.{1,12}$" ""

    # 🛡️ SRE GUARDRAIL CASE 2 (CLI): Troca de ID da Empresa em Host com Stack Existente -> Destruição e Reset Transacional
    if [ "$IS_PROVISIONED" -eq 1 ] && [ -n "$EMPRESA" ] && [ "$EMPRESA" != "$PREV_EMPRESA" ]; then
        echo ""
        echo -e "\e[31m=====================================================================\e[0m"
        echo -e "\e[31m   ⚠️  ALERTA CRÍTICO SRE: MUDANÇA DE ID DE EMPRESA DETECTADA        \e[0m"
        echo -e "\e[31m=====================================================================\e[0m"
        echo -e "Atenção: Foi detectada uma stack ativa da empresa: \e[33m[ ${PREV_EMPRESA} ]\e[0m"
        echo -e "Você selecionou um NOVO ID de empresa:            \e[32m[ ${EMPRESA} ]\e[0m"
        echo ""
        echo -e "\e[31mEsta operação é DESTRUTIVA e irá:\e[0m"
        echo -e " 1. Executar disable e desprovisionamento de todos os módulos anteriores."
        echo -e " 2. Limpar todas as entradas no Caddyfile, DNS e cards do index.html."
        echo -e " 3. Parar e remover todos os contêineres e volumes da stack anterior."
        echo -e " 4. Recriar a nova infraestrutura isolada para '${EMPRESA}'."
        echo "---------------------------------------------------------------------"
        
        CONFIRMAR_RESET=""
        coletar_sn "Deseja realmente DESTRUIR a stack anterior e criar a nova do zero?" CONFIRMAR_RESET "n" "false"
        if [ "$CONFIRMAR_RESET" != "s" ]; then
            echo -e "\e[33m➜ [SRE GUARDRAIL] Operação cancelada. Mantendo stack e ID da empresa anterior (${PREV_EMPRESA}).\e[0m"
            EMPRESA="$PREV_EMPRESA"
            CLIENTE_NOME="$PREV_NOME"
            CLIENTE_SOBRENOME="$PREV_SOBRENOME"
            CLIENTE_EMAIL="$PREV_EMAIL"
            DB_PASSWORD="$PREV_PASSWORD"
            DB_PASSWORD2="$PREV_PASSWORD"
        else
            echo "=== [SRE GUARDRAIL] Desprovisionando e limpando stack da empresa anterior: ${PREV_EMPRESA} ==="
            SCRIPTS_DIR="${TARGET_DIR}/core/scripts"
            [ ! -d "$SCRIPTS_DIR" ] && SCRIPTS_DIR="./core/scripts"
            if [ -d "$SCRIPTS_DIR" ]; then
                for s_mod in "$SCRIPTS_DIR"/install_*.sh; do
                    [ ! -f "$s_mod" ] && continue
                    if grep -q "disable()" "$s_mod" 2>/dev/null; then
                        echo "➜ Executando disable do módulo: $(basename "$s_mod")"
                        PREFIXO_CONTAINER="$PREV_EMPRESA" bash "$s_mod" "${TARGET_DIR}" "disable" 2>/dev/null || true
                    fi
                done
            fi
            # 🛡️ Tenta docker compose down para encerrar tudo de forma limpa
            if [ -d "$TARGET_DIR" ]; then
                echo "➜ Derrubando contêineres via docker compose..."
                (cd "$TARGET_DIR" && sudo docker compose down -v --remove-orphans 2>/dev/null || true)
            fi

            # 🔫 Fallback cirúrgico: força remoção de QUALQUER container com o prefixo do tenant antigo (incluindo core)
            echo "➜ Verificando containers residuais com prefixo '${PREV_EMPRESA}_'..."
            _residual_containers=$(sudo docker ps -a --filter "name=^${PREV_EMPRESA}_" --format "{{.Names}}" 2>/dev/null || true)
            if [ -n "$_residual_containers" ]; then
                echo "➜ Containers residuais encontrados — forçando remoção:"
                echo "$_residual_containers" | while read -r _cname; do
                    echo "   ✗ Removendo: ${_cname}"
                    sudo docker stop "$_cname" 2>/dev/null || true
                    sudo docker rm -f "$_cname" 2>/dev/null || true
                done
            else
                echo "✔ Nenhum container residual '${PREV_EMPRESA}_*' encontrado."
            fi

            # 🗑️ Remove volumes com prefixo do tenant antigo
            echo "➜ Verificando volumes residuais com prefixo '${PREV_EMPRESA}_'..."
            _residual_volumes=$(sudo docker volume ls --filter "name=^${PREV_EMPRESA}_" --format "{{.Name}}" 2>/dev/null || true)
            if [ -n "$_residual_volumes" ]; then
                echo "➜ Volumes residuais encontrados — expurgando:"
                echo "$_residual_volumes" | while read -r _vname; do
                    echo "   ✗ Removendo volume: ${_vname}"
                    sudo docker volume rm -f "$_vname" 2>/dev/null || true
                done
            fi

            # Remove diretório de volumes físicos e chave de backup privada antiga
            sudo rm -rf "${TARGET_DIR}/volumes" 2>/dev/null || true
            rm -f "${USER_REAL_HOME}/CHAVE_PRIVADA_BACKUP_${PREV_EMPRESA}.asc" "${TARGET_DIR}/CHAVE_PRIVADA_BACKUP_${PREV_EMPRESA}.asc" 2>/dev/null || true
            echo -e "\e[32m✔ [SUCESSO SRE] Stack anterior limpa com sucesso. Prosseguindo com o provisionamento de: ${EMPRESA}\e[0m"
            IS_PROVISIONED=0
        fi
    fi

    # 🛡️ SRE GUARDRAIL CASE 1 (CLI): Mesma Empresa já provisionada -> Trava edição de credenciais
    if [ "$IS_PROVISIONED" -eq 1 ] && [ "$EMPRESA" = "$PREV_EMPRESA" ]; then
        echo ""
        echo -e "\e[33m=====================================================================\e[0m"
        echo -e "\e[33m   🔒  BLOQUEIO SRE: STACK JÁ PROVISIONADA PARA: ${EMPRESA}          \e[0m"
        echo -e "\e[33m=====================================================================\e[0m"
        echo -e "Os dados cadastrais e a Senha Mestra estão travados para preservar a"
        echo -e "integridade dos volumes do banco de dados e autenticações ativas."
        echo -e "➜ Administrador: \e[32m${PREV_NOME} ${PREV_SOBRENOME}\e[0m"
        echo -e "➜ E-mail:        \e[32${PREV_EMAIL}\e[0m"
        echo -e "➜ Senha Mestra:  \e[32m[PRESERVADA]\e[0m"
        echo "---------------------------------------------------------------------"
        CLIENTE_NOME="$PREV_NOME"
        CLIENTE_SOBRENOME="$PREV_SOBRENOME"
        CLIENTE_EMAIL="$PREV_EMAIL"
        DB_PASSWORD="$PREV_PASSWORD"
        DB_PASSWORD2="$PREV_PASSWORD"
    else
        coletar_input "Nome do Cliente/Responsável (Ex: Joao)" CLIENTE_NOME "false" "" ""
        coletar_input "Sobrenome do Cliente/Responsável (Ex: Silva)" CLIENTE_SOBRENOME "false" "" ""
        coletar_input "Email Oficial do Cliente/Tailnet (Ex: contato@loja.com)" CLIENTE_EMAIL "false" "^[^@]+@[^@]+\.[^@]+$" ""

        while true; do
            echo ""
            echo -e "\e[33m=== [SRE PREINSTALL] Definição da Senha Mestra (URI-Safe) ===\e[0m"
            echo -e "\e[36mPara garantir a integridade da malha de containers (Connection Strings):\e[0m"
            echo -e "\e[36m ↳ Tamanho: \e[37mEntre 8 e 12 caracteres\e[0m"
            echo -e "\e[36m ↳ Requisitos: \e[37mPelo menos 1 Maiúscula e 1 Número\e[0m"
            echo -e "\e[36m ↳ Especiais PERMITIDOS: \e[32m- _ * ~ ^\e[0m"
            echo -e "\e[36m ↳ Especiais PROIBIDOS:  \e[31m@ # & / : ? = % |\e[0m"
            echo "---------------------------------------------------------------------"
            
            coletar_input "Digite a Senha Mestra do Cliente" DB_PASSWORD "true" "" ""

            if [[ ${#DB_PASSWORD} -lt 8 ]] || [[ ${#DB_PASSWORD} -gt 12 ]]; then
                echo -e "\e[31m[ERRO PREINSTALL] A senha possui ${#DB_PASSWORD} caracteres. Ela deve ter obrigatoriamente entre 8 e 12.\e[0m"
                continue
            fi

            if [[ ! "$DB_PASSWORD" =~ [A-Z] ]]; then
                echo -e "\e[31m[ERRO PREINSTALL] A senha deve conter pelo menos uma letra MAIÚSCULA.\e[0m"
                continue
            fi

            if [[ ! "$DB_PASSWORD" =~ [0-9] ]]; then
                echo -e "\e[31m[ERRO PREINSTALL] A senha deve conter pelo menos um NÚMERO.\e[0m"
                continue
            fi

            if [[ "$DB_PASSWORD" =~ [@#\&/:\?=\|%] ]]; then
                echo -e "\e[31m[ERRO CRÍTICO PREINSTALL] Você usou um caractere reservado de URL!\e[0m"
                echo -e "\e[31m➜ Isso corrompe as strings de conexão do Postgres. Use apenas: - _ * ~ ^\e[0m"
                continue
            fi

            if [[ ! "$DB_PASSWORD" =~ [-_*~^] ]]; then
                echo -e "\e[31m[ERRO PREINSTALL] A senha deve conter pelo menos um CARACTERE ESPECIAL SEGURO (Ex: - _ * ~ ^).\e[0m"
                continue
            fi

            coletar_input "Confirme a Senha Mestra" DB_PASSWORD2 "true" "" ""
            if [ "$DB_PASSWORD" = "$DB_PASSWORD2" ]; then 
                save_wizard_cache "DB_PASSWORD2" "$DB_PASSWORD2"
                break
            fi
            
            echo -e "\e[31m[ERRO CRÍTICO PREINSTALL] As senhas digitadas não conferem! Tente novamente.\e[0m"
        done
    fi

# MOMENTANEAMENTE DESATIVADO (LOJA INTEGRADA)
# coletar_input "Chave de API Loja Integrada (20 chars)" LOJA_API_KEY "true" "" "20"
# coletar_input "Chave de Aplicação Loja Integrada (36 chars - UUID)" LOJA_APP_KEY "true" "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$" "36"
LOJA_API_KEY=""
LOJA_APP_KEY=""

    echo ""
    echo -e "\e[33m=== [SRE FinOps PREINSTALL] Seleção & Configuração Dinâmica de Módulos ===\e[0m"
    SCRIPTS_DIR="${TARGET_DIR}/core/scripts"
    [ ! -d "$SCRIPTS_DIR" ] && SCRIPTS_DIR="./core/scripts"

    if [ -f "$CACHE_WIZARD_FILE" ]; then
        set -a
        source "$CACHE_WIZARD_FILE" 2>/dev/null || true
        set +a
    fi

    if [ -f "${SCRIPTS_DIR}/autotune.sh" ]; then
        source "${SCRIPTS_DIR}/autotune.sh" "${TARGET_DIR}/.env" get_hardware_info 2>/dev/null || true
    fi

    for script in "$SCRIPTS_DIR"/install_*.sh; do
        [ ! -f "$script" ] && continue
        # SRE FIX: usa bash (subshell) para que o ACTION router receba $2="collect_wizard_inputs" corretamente
        bash "$script" "$TARGET_DIR" collect_wizard_inputs 2>/dev/null || true
        # Re-exporta as variáveis USE_* que o subshell pode ter setado via save_wizard_cache
        if [ -f "$CACHE_WIZARD_FILE" ]; then
            set -a; source "$CACHE_WIZARD_FILE" 2>/dev/null || true; set +a
        fi
    done

    echo ""
    echo -e "\e[33m=== [SRE PREINSTALL] Topologia de Rede (Isolamento CIDR) ===\e[0m"
    echo "1) 172.25.0.x (Padrão / Container)"
    echo "2) 10.50.0.x  (AWS VPC Peering Seguro)"
    echo "3) 192.168.200.x (On-Premise Seguro)"
    echo "4) Customizado (Ex: 10.99.0)"
    if [ -n "${REDE_CHOICE:-}" ]; then
        echo -e "\e[32m✔ [CACHE PREINSTALL] Opção de sub-rede restaurada: ${REDE_CHOICE}\e[0m"
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
fi

# =========================================================================
# FASE 1 (MODO TUI): PREPARAÇÃO DO SISTEMA OPERACIONAL & GIT CLONE
# =========================================================================
if [ "$USE_TUI" = "true" ]; then
    echo "=== [SRE PREINSTALL] Elevando temporariamente o timeout do sudo para 60 minutos ==="
    echo "Defaults timestamp_timeout=60" | sudo tee /etc/sudoers.d/custom_sudo_timeout > /dev/null
    sudo chmod 0440 /etc/sudoers.d/custom_sudo_timeout

    cleanup_sudo_timeout() {
        if [ "$EXECUTAR_INSTALL" != "s" ]; then
            mostrar_duracao
        fi
        if [ -f /etc/sudoers.d/custom_sudo_timeout ]; then
            echo "=== [SRE HARDENING PREINSTALL] Revogando timeout estendido do sudo... ==="
            sudo rm -f /etc/sudoers.d/custom_sudo_timeout 2>/dev/null || true
        fi
        rm -f "$LOCK_FILE" 2>/dev/null || true
    }
    trap cleanup_sudo_timeout EXIT

    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1

    echo "=== [SRE KERNEL TUNING PREINSTALL] Aplicando Otimizações Avançadas de SO & Network Stack ==="

    if [ ! -f /etc/sysctl.d/99-daemind-sre.conf ] || ! grep -q 'net.core.somaxconn = 65535' /etc/sysctl.d/99-daemind-sre.conf 2>/dev/null; then
        echo "➜ [CONFIGURANDO PREINSTALL] Aplicando matriz de Kernel Tuning em /etc/sysctl.d/99-daemind-sre.conf..."
        cat << 'EOF' | sudo tee /etc/sysctl.d/99-daemind-sre.conf > /dev/null
# --- MEMORY TUNING (REDIS & POSTGRES) ---
vm.overcommit_memory = 1
vm.swappiness = 10
vm.max_map_count = 262144

# --- NETWORK STACK TUNING (CADDY, PGBOUNCER, MINIO) ---
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# --- FILE DESCRIPTORS & INOTIFY (DOCKER & NODE.JS) ---
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
EOF
        sudo sysctl --system > /dev/null 2>&1 || sudo sysctl -p /etc/sysctl.d/99-daemind-sre.conf > /dev/null 2>&1 || true
        echo "➜ [SUCESSO PREINSTALL] Kernel Tuning SRE aplicado (Memory Overcommit, Network Backlog, Inotify & Limits)."
    else
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] Matriz de Kernel Tuning já configurada e ativa no sistema."
    fi

    if [ ! -f /etc/security/limits.d/99-daemind-limits.conf ] || ! grep -q 'soft nofile 1048576' /etc/security/limits.d/99-daemind-limits.conf 2>/dev/null; then
        cat << 'EOF' | sudo tee /etc/security/limits.d/99-daemind-limits.conf > /dev/null
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 524288
* hard nproc 524288
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 524288
root hard nproc 524288
EOF
    fi

    echo "=== [SRE PREINSTALL] Verificando se há locks ativos do APT/DPKG no sistema ==="
    TENTATIVAS_APT_LOCK=0
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        TENTATIVAS_APT_LOCK=$((TENTATIVAS_APT_LOCK + 1))
        echo "  ↳ O APT está ocupado com outro processo em segundo plano (Tentativa ${TENTATIVAS_APT_LOCK}/24). Aguardando 5s..."
        sleep 5
        if [ "$TENTATIVAS_APT_LOCK" -ge 24 ]; then
            echo "  ⚠️ [SRE AUTO-HEALING PREINSTALL] Lock do APT retido por mais de 120s. Finalizando processos zumbis do APT/unattended-upgrades..."
            sudo systemctl stop unattended-upgrades 2>/dev/null || true
            sudo killall -9 apt apt-get dpkg 2>/dev/null || true
            sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
            sudo dpkg --configure -a 2>/dev/null || true
            break
        fi
    done

    echo "=== [SRE PREINSTALL] Detectando e corrigindo dinamicamente pacotes corrompidos ==="
    PACOTES_QUEBRADOS=$(dpkg -l | awk '/^i[FHRU]/ {print $2}')
    if [ -n "$PACOTES_QUEBRADOS" ]; then 
        echo "  ↳ Removendo resíduos de Kernel/Pacotes quebrados silenciosamente..."
        echo "$PACOTES_QUEBRADOS" | sudo xargs -r env DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y -qq > /dev/null 2>&1 < /dev/null
    fi

    sudo chmod -x /etc/kernel/prerm.d/vboxadd /etc/kernel/postinst.d/vboxadd 2>/dev/null || true
    if ! grep -q 'GRUB_DISABLE_OS_PROBER=true' /etc/default/grub 2>/dev/null; then
        sudo sed -i '/GRUB_DISABLE_OS_PROBER/d' /etc/default/grub 2>/dev/null || true
        echo "GRUB_DISABLE_OS_PROBER=true" | sudo tee -a /etc/default/grub > /dev/null
    fi
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

    echo "=== [SRE PREINSTALL] Configurando chaves e repositórios oficiais do Docker ==="
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "=== [SRE PREINSTALL] Verificando atualizações dos índices do APT ==="
    JANELA_CORTE_SEGUNDOS=86400 # 24 horas
    ULTIMA_ATUALIZACAO=0
    NOSSO_STAMP="/var/log/sre_factory_apt_update.stamp"

    if [ -f "$NOSSO_STAMP" ]; then
        ULTIMA_ATUALIZACAO=$(stat -c %Y "$NOSSO_STAMP")
    elif [ -f /var/lib/apt/periodic/update-success-stamp ]; then
        ULTIMA_ATUALIZACAO=$(stat -c %Y /var/lib/apt/periodic/update-success-stamp)
    fi

    AGORA=$(date +%s)
    TEMPO_DECORRIDO=$((AGORA - ULTIMA_ATUALIZACAO))

    LISTAS_APT=$(ls /var/lib/apt/lists/ 2>/dev/null | grep -v '^partial$' | head -n 1 || true)

    # SRE GUARDRAIL: Sanitiza pacotes com pós-instalação pendente e recupera dpkg
    sudo dpkg --configure -a >/dev/null 2>&1 || true

    if [ $TEMPO_DECORRIDO -gt $JANELA_CORTE_SEGUNDOS ] || [ -z "$LISTAS_APT" ]; then
        if ! sudo apt-get update -qq -o Dpkg::Lock::Timeout=120 2>/dev/null; then
            sudo killall -9 apt-get apt 2>/dev/null || true
            sudo rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend 2>/dev/null || true
            sudo apt-get update -qq -o Dpkg::Lock::Timeout=60 > /dev/null 2>&1 || true
        fi
        sudo touch "$NOSSO_STAMP"
    fi

    PACOTES_REQUERIDOS=(
        chrony wget iputils-ping curl openssl iptables ipset cron dnsmasq apt-transport-https
        ca-certificates gnupg tcpdump net-tools lsb-release jq git vim dialog
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        bind9-utils sysstat htop dnsutils systemd-timesyncd
    )

    PACOTES_PARA_INSTALAR=()
    for pacote in "${PACOTES_REQUERIDOS[@]}"; do
        if ! dpkg -l "$pacote" &>/dev/null; then
            PACOTES_PARA_INSTALAR+=("$pacote")
        else
            VERSAO_INSTALADA=$(dpkg-query -W -f='${Version}' "$pacote" 2>/dev/null)
            VERSAO_CANDIDATA=$(apt-cache policy "$pacote" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
            
            if [ "$VERSAO_INSTALADA" != "$VERSAO_CANDIDATA" ] && [ -n "$VERSAO_CANDIDATA" ] && [ "$VERSAO_CANDIDATA" != "(none)" ]; then
                PACOTES_PARA_INSTALAR+=("$pacote")
            fi
        fi
    done

    if [ ${#PACOTES_PARA_INSTALAR[@]} -gt 0 ]; then
        echo "➜ [SRE PREINSTALL] Provisionando ${#PACOTES_PARA_INSTALAR[@]} pacote(s) do sistema..."
        sudo add-apt-repository universe -y > /dev/null 2>&1 || true
        sudo apt-get update -qq -o Dpkg::Lock::Timeout=120 > /dev/null 2>&1 || true
        sudo touch "$NOSSO_STAMP"

        sudo -E apt-get install -y -qq -o Dpkg::Lock::Timeout=120 -o Dpkg::Options::="--force-confold" "${PACOTES_PARA_INSTALAR[@]}" > /dev/null 2>&1 < /dev/null
        sudo apt-get clean > /dev/null 2>&1 || true
        sudo systemctl stop dnsmasq 2>/dev/null || true
        echo "✔ [SUCESSO PREINSTALL] Pacotes do sistema instalados com sucesso."
    else
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] Pacotes do sistema já estão instalados e atualizados."
    fi

    # =========================================================================
    # 📥 REPOSITÓRIO OFICIAL (DISCO LOCAL /opt/daemind - Já sincronizado)
    # =========================================================================
    TARGET_DIR="${TARGET_DIR:-/opt/daemind}"
    sudo mkdir -p "${TARGET_DIR}"
    echo "✔ [SUCESSO PREINSTALL] Repositório atualizado e pronto para uso."

    echo "=== [SRE PREINSTALL] Sanitizando ambiente de produção ==="
    sudo rm -rf "${TARGET_DIR}/docs" "${TARGET_DIR}/README.md" "${TARGET_DIR}/LICENSE" 2>/dev/null || true
    sudo mkdir -p "${TARGET_DIR}/core/config"

    echo "=== [SRE PREINSTALL] Configurando resolvedor de rede perimetral (dnsmasq) no Host ==="
    sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    sudo sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    sudo systemctl restart systemd-resolved 2>/dev/null || true

    sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
    cat << EOC | sudo tee /etc/dnsmasq.conf > /dev/null
listen-address=127.0.0.1,172.17.0.1
bind-dynamic
server=8.8.8.8
server=1.1.1.1
conf-dir=/etc/dnsmasq.d,*.conf

# IPSET ALLOWED DOMAINS (CORE TLS, CERTIFICADOS & REPOSITÓRIOS DO HOST)
ipset=/letsencrypt.org/ALLOWED_DOMAINS
ipset=/lencr.org/ALLOWED_DOMAINS
ipset=/zerossl.com/ALLOWED_DOMAINS
ipset=/github.com/ALLOWED_DOMAINS
ipset=/raw.githubusercontent.com/ALLOWED_DOMAINS

domain-needed
bogus-priv
EOC

    IF_DOCKER_ACTIVE=$(systemctl is-active docker 2>/dev/null || echo "inactive")
    if [ -f /etc/docker/daemon.json ] && grep -q "172.17.0.1" /etc/docker/daemon.json 2>/dev/null && [ "$IF_DOCKER_ACTIVE" = "active" ]; then
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] Docker Engine e dnsmasq já vinculados ao Gateway local. Preservando containers."
        sudo systemctl restart dnsmasq 2>/dev/null || true
    else
        echo "=== [SRE PREINSTALL] Vinculando Docker Engine ao Gateway local ==="
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
        echo "=== [SRE PREINSTALL] Reiniciando daemons de rede e virtualização do Host ==="
        sudo systemctl restart dnsmasq docker
    fi

    if [ -n "$SUDO_USER" ]; then
        sudo usermod -aG docker "$SUDO_USER"
    fi

    if [ -f /swapfile ] && grep -q '/swapfile' /etc/fstab 2>/dev/null; then
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] Memória Virtual Swap (4GB) já estruturada e ativa."
    else
        echo "=== [SRE PREINSTALL] Criando Memória Virtual de Amortecimento (Swap 4GB) ==="
        sudo swapoff -a 2>/dev/null || true
        sudo rm -f /swapfile /swap.img 2>/dev/null || true
        sudo sed -i '/swap/d' /etc/fstab 2>/dev/null || true

        sudo fallocate -l 4G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile >/dev/null 2>&1
        sudo swapon /swapfile >/dev/null 2>&1
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
        echo "➜ [SUCESSO PREINSTALL] Swap 4GB criado e registrado no fstab."
    fi

    echo "=== [SRE PREINSTALL] Limpeza final antes do install.sh ==="
    sudo apt-get clean
    sudo rm -rf /var/lib/apt/lists/*
    sudo rm -f "$NOSSO_STAMP"

    INTERFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n 1)

    if [ -z "$INTERFACE" ]; then
        INTERFACE=$(ip link show | grep -E '^[0-9]+: e' | cut -d: -f2 | tr -d ' ' | head -n 1)
        sudo ip link set "$INTERFACE" up || true
        sudo dhclient -v "$INTERFACE" 2>/dev/null || true
        sleep 3
    fi

    IP_CIDR=$(ip -4 addr show dev "$INTERFACE" 2>/dev/null | grep inet | awk '{print $2}' | head -n 1)
    GATEWAY=$(ip -4 route show default 2>/dev/null | awk '{print $3}' | head -n 1)
    MAC_ADDR=$(ip link show dev "$INTERFACE" 2>/dev/null | grep link/ether | awk '{print $2}' | head -n 1)

    if [ -z "$IP_CIDR" ]; then
        sudo dhclient -r "$INTERFACE" 2>/dev/null || true
        sudo dhclient "$INTERFACE" 2>/dev/null || true
        sleep 2
        IP_CIDR=$(ip -4 addr show dev "$INTERFACE" | grep inet | awk '{print $2}' | head -n 1)
        GATEWAY=$(ip -4 route show default | awk '{print $3}' | head -n 1)
    fi

    if [ -z "$IP_CIDR" ] || [ -z "$GATEWAY" ]; then
        echo "🚨 [ERRO CRÍTICO PREINSTALL] A interface $INTERFACE não recebeu IP via DHCP!"
        exit 1
    fi

    if [ -f /etc/netplan/99-static-sre.yaml ] && grep -q "$IP_CIDR" /etc/netplan/99-static-sre.yaml 2>/dev/null; then
        echo "➜ [IDEMPOTÊNCIA PREINSTALL] IP de rede estático já configurado (${IP_CIDR}). Preservando netplan."
    else
        echo "➜ [SRE PREINSTALL] Fixando IP de rede estático para a aplicação (${IP_CIDR})..."
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
        sudo netplan apply 2>/dev/null || true
        echo "✔ [SUCESSO PREINSTALL] IP de rede estático fixado e protegido contra trocas."
    fi

    echo "=== [SRE PREINSTALL] Configurando mensagem customizada de boas-vindas no login ==="
    sudo chmod -x /etc/update-motd.d/* 2>/dev/null || true

    sudo cat << 'EOM' | sudo tee /etc/update-motd.d/99-sre-banner > /dev/null
#!/bin/bash
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

USUARIO_LOGADO="${PAM_USER:-$(logname 2>/dev/null || who am i | awk '{print $1}')}"
[ -z "$USUARIO_LOGADO" ] && USUARIO_LOGADO=$(whoami)

HOST_SHORT=$(hostname -s)
DOMAIN_NAME=$(dnsdomainname 2>/dev/null || domainname 2>/dev/null || echo "")
if [ -n "$DOMAIN_NAME" ] && [ "$DOMAIN_NAME" != "(none)" ]; then
    HOST_FQDN="${HOST_SHORT}.${DOMAIN_NAME}"
else
    HOST_FQDN=$(hostname -f 2>/dev/null)
    [ "$HOST_FQDN" = "$HOST_SHORT" ] && HOST_FQDN="${HOST_SHORT}.local"
fi

MAIN_IFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n 1)
[ -z "$MAIN_IFACE" ] && MAIN_IFACE="eth0"
ETH_IP=$(ip -4 addr show dev "$MAIN_IFACE" 2>/dev/null | grep inet | awk '{print $2}' || echo "Sem Link/Offline")

UBUNTU_VER=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
KERNEL_VER=$(uname -r)

CPU_MODEL=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//' | xargs)
[ -z "$CPU_MODEL" ] && CPU_MODEL="Virtual Processor"
CPU_CORES=$(nproc)

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

    echo "=== [SRE PREINSTALL] Limpando rastros da sessão ==="
    sudo bash -c "cat /dev/null > /root/.bash_history 2>/dev/null || true"
    if [ -n "$SUDO_USER" ]; then
        USER_HOME_REAL=$(eval echo "~$SUDO_USER")
        cat /dev/null > "$USER_HOME_REAL/.bash_history" 2>/dev/null || true
    fi
fi

# =========================================================================
# FASE 3: GERAÇÃO DO AMBIENTE, HARDENING E DISPARO DO DEPLOY (SSOT)
# =========================================================================
# Atualiza o diretório de scripts para apontar para a infraestrutura oficial clonada em /opt/daemind
SCRIPTS_DIR="${TARGET_DIR}/core/scripts"
[ ! -d "$SCRIPTS_DIR" ] && SCRIPTS_DIR="./core/scripts"


if [ "$ROUTING_CHOICE" = "1" ]; then
    if [ -f "${SCRIPTS_DIR}/install_0ts.sh" ]; then
        sudo bash "${SCRIPTS_DIR}/install_0ts.sh" "${TARGET_DIR}" install_binary
    fi
else
    echo -e "\e[36m➜ [SRE SKIP PREINSTALL] Modo BYODNS Selecionado. Omitindo dependências de VPN.\e[0m"
fi


IP_NETWORK_SUBNET="${BASE_IP}.0/24"
IP_NETWORK_GATEWAY="${BASE_IP}.1"
IP_POSTGRES="${BASE_IP}.2"
IP_PGBOUNCER="${BASE_IP}.3"
IP_REDIS="${BASE_IP}.4"
IP_CADDY="${BASE_IP}.5"
IP_LITELLM="${BASE_IP}.6"

# --- Descoberta Autônoma dos Módulos Desacoplados (Linha 2 de cada install_*.sh) ---
ALL_NODES=()
for script in "$SCRIPTS_DIR"/install_*.sh; do
    [ ! -f "$script" ] && continue
    nodes=$(sed -n '2p' "$script" 2>/dev/null | sed 's/^#[[:space:]]*//')
    for node in $nodes; do
        [ -n "$node" ] && ALL_NODES+=("$(echo "$node" | tr '[:lower:]' '[:upper:]')")
    done
done

# Ordena todos os nós coletados em ordem alfabética estrita
SORTED_NODES=($(printf "%s\n" "${ALL_NODES[@]}" | sort -u))

IP_OFFSET=7
MODULOS_NETWORK_VARS=()
for node in "${SORTED_NODES[@]}"; do
    VAR_NAME="IP_${node}"
    eval "${VAR_NAME}=\"\${BASE_IP}.\${IP_OFFSET}\""
    MODULOS_NETWORK_VARS+=("${VAR_NAME}")
    IP_OFFSET=$((IP_OFFSET + 1))
done

NOME_ARQUIVO="${EMPRESA}.env"

echo "  ↳ Ativando persistência de relógio no Hardware (NTP + RTC)..."
sudo bash -c 'cat << EOF > /etc/systemd/timesyncd.conf
[Time]
NTP=a.st1.ntp.br b.st1.ntp.br 1.1.1.1
FallbackNTP=ntp.ubuntu.com
EOF'
sudo systemctl enable --now systemd-timesyncd 2>/dev/null || true
sudo hwclock --systohc 2>/dev/null || true
echo "➜ [OK PREINSTALL] Hora oficial gravada na BIOS com sucesso."

echo -e "\e[33m=== [SRE PREINSTALL] Geração Autônoma da Chave Criptográfica (Backups) ===\e[0m"
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
    echo -e "\e[32m➜ [IDEMPOTÊNCIA PREINSTALL] Chave criptográfica OpenPGP já existente para: ${CLIENTE_EMAIL}. Preservando par de chaves.\e[0m"
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

    # SRE FIX: Importação automática e atômica da Chave PÚBLICA no Keyring do Host apenas se ainda não importada
    if ! sudo gpg --list-public-keys "$CLIENTE_EMAIL" > /dev/null 2>&1; then
        sudo gpg --batch --yes --import "$CHAVE_PUBLICA_PATH" > /dev/null 2>&1 || true
        echo -e "\e[32m➜ [SUCESSO PREINSTALL] Chave pública importada no keyring do sistema para: $CLIENTE_EMAIL\e[0m"
    fi
else
    echo -e "\e[31m[ERRO CRÍTICO PREINSTALL] O motor GPG falhou ao tentar forjar o par de chaves de segurança!\e[0m"
    exit 1
fi

# Recarrega e exporta expressamente o cache do Wizard para a memória da sessão atual
if [ -f "$CACHE_WIZARD_FILE" ]; then
    sed -i 's/\r$//' "$CACHE_WIZARD_FILE" 2>/dev/null || true
    set -a
    source "$CACHE_WIZARD_FILE" 2>/dev/null || true
    set +a
fi

cat << EOF > "$NOME_ARQUIVO"

PREINSTALL_START_TS="$PREINSTALL_START_TS"
PREINSTALL_PAUSE_SEC="$TEMPO_PAUSA_INTERATIVA"
PROJETO_DIR="/opt/daemind"
PREFIXO_CONTAINER="${EMPRESA}"
DB_USER="admin_db"
DB_PASSWORD="${DB_PASSWORD}"
DB_NAME="${EMPRESA}_db"
CLIENTE_NOME="${CLIENTE_NOME}"
CLIENTE_SOBRENOME="${CLIENTE_SOBRENOME}"
TS_EMAIL="${CLIENTE_EMAIL}"
CHAVE_PUBLICA_B64="${CHAVE_PUBLICA_B64}"
HASH_ESPERADO="${HASH_ESPERADO}"
HOST_CADDY_PORT="80"
LITELLM_MASTER_KEY="sk-admin-${DB_PASSWORD}"

# --- Mapeamento Estático de Rede (SSOT Core) ---
IP_NETWORK_SUBNET="$IP_NETWORK_SUBNET"
IP_NETWORK_GATEWAY="$IP_NETWORK_GATEWAY"
IP_POSTGRES="$IP_POSTGRES"
IP_PGBOUNCER="$IP_PGBOUNCER"
IP_REDIS="$IP_REDIS"
IP_CADDY="$IP_CADDY"
IP_LITELLM="$IP_LITELLM"
EOF

# Injeção Dinâmica dos IPs dos Módulos Desacoplados
for var_name in "${MODULOS_NETWORK_VARS[@]}"; do
    echo "${var_name}=\"${!var_name}\"" >> "$NOME_ARQUIVO"
done

# Garante que as métricas de hardware estejam disponíveis para os build_envs de cada módulo
if [ -f "$SCRIPTS_DIR/autotune.sh" ]; then
    source "$SCRIPTS_DIR/autotune.sh" "" "get_hardware_info" 2>/dev/null || true
fi

# Injeção Dinâmica das Variáveis de Ambiente de Todos os Módulos (Contrato Desacoplado)
# SRE FIX: usa bash (subshell) com export do ambiente para que ACTION router receba $2="build_envs" corretamente
for script in "$SCRIPTS_DIR"/install_*.sh; do
    [ ! -f "$script" ] && continue
    # Exporta as variáveis chave para o subshell (USE_*, OVERRIDE_*, NOME_ARQUIVO, SYSTEM_*)
    export USE_DOCLING USE_OLLAMA USE_N8N USE_CHATWOOT USE_EVOLUTION USE_METABASE USE_OPENWEBUI USE_NOCODB USE_POSTIZ USE_S3MINIO 2>/dev/null || true
    export OVERRIDE_TOTAL_CPUS OVERRIDE_TOTAL_RAM_GB OVERRIDE_TOTAL_RAM_MB SYSTEM_TOTAL_CPUS SYSTEM_TOTAL_RAM_MB SYSTEM_TOTAL_RAM_GB TOTAL_CPUS TOTAL_RAM_MB TOTAL_RAM_GB 2>/dev/null || true
    export NOME_ARQUIVO EMPRESA PREFIXO_CONTAINER TARGET_DIR 2>/dev/null || true
    bash "$script" "$TARGET_DIR" build_envs || true
done

# =========================================================================
# SRE STATE HARMONIZATION: Persistência Final dos Flags de Controle no SSOT
# Gravados APÓS os build_envs para ter prioridade máxima (last-write-wins).
# Garante que toda escolha feita no wizard (TUI Dialog ou CLI) seja refletida
# integralmente no SSOT e propagada para o install.sh e re-deploys futuros.
# =========================================================================
{
    printf '\n# --- Flags de Controle de Módulos (State Harmonization SSOT) ---\n'
    for _hs in "$SCRIPTS_DIR"/install_*.sh; do
        [ ! -f "$_hs" ] && continue
        _hbname=$(basename "$_hs" .sh | sed 's/^install_//')
        # Módulos internos com prefixo numérico (0ts, 1ia) não possuem flag USE_*
        [[ "$_hbname" =~ ^[0-9] ]] && continue
        _hvar="USE_$(echo "$_hbname" | tr '[:lower:]' '[:upper:]')"
        printf '%s="%s"\n' "$_hvar" "${!_hvar:-n}"
    done
    printf '\n# --- Controle de Storage e Topologia de Borda ---\n'
    printf 'STORAGE_MODE="%s"\n'   "${STORAGE_MODE:-local}"
    printf 'USE_S3MINIO="%s"\n'    "${USE_S3MINIO:-n}"
    printf 'USE_TAILSCALE="%s"\n'  "${USE_TAILSCALE:-false}"
    printf 'ROUTING_CHOICE="%s"\n' "${ROUTING_CHOICE:-1}"
    if [ "${ROUTING_CHOICE:-1}" != "1" ]; then
        printf 'CUSTOM_DOMAIN="%s"\n'     "${CUSTOM_DOMAIN:-}"
        printf 'CUSTOM_EVO_DOMAIN="%s"\n' "${CUSTOM_EVO_DOMAIN:-}"
        printf 'CADDY_PROTOCOL="%s"\n'    "${CADDY_PROTOCOL:-https}"
    fi
    printf '\n# --- Provedores de Inteligência Artificial (Wizard Selections) ---\n'
    printf 'FREE_GEMINI="%s"\n'      "${FREE_GEMINI:-0}"
    printf 'RESP_GEMINI_FREE="%s"\n' "${RESP_GEMINI_FREE:-n}"
    [ -n "${GEMINI_API_KEY:-}" ]     && printf 'GEMINI_API_KEY="%s"\n'     "$GEMINI_API_KEY"
    [ -n "${OPENAI_API_KEY:-}" ]     && printf 'OPENAI_API_KEY="%s"\n'     "$OPENAI_API_KEY"
    [ -n "${ANTHROPIC_API_KEY:-}" ]  && printf 'ANTHROPIC_API_KEY="%s"\n'  "$ANTHROPIC_API_KEY"
    [ -n "${DEEPSEEK_API_KEY:-}" ]   && printf 'DEEPSEEK_API_KEY="%s"\n'   "$DEEPSEEK_API_KEY"
    [ -n "${OPENROUTER_API_KEY:-}" ] && printf 'OPENROUTER_API_KEY="%s"\n' "$OPENROUTER_API_KEY"
} >> "$NOME_ARQUIVO"

chmod 600 "$NOME_ARQUIVO"

# =========================================================================
# 🔒 SRE NETWORK HARDENING (CORE PERIMETRAL)
# =========================================================================
echo "=== [SRE PREINSTALL] Aplicando Hardening Perimetral no Kernel (IPTables & IPSet) ==="
POLICY_ATUAL=$(sudo iptables -L OUTPUT -n | head -n 1 | grep -oE 'DROP|REJECT|ACCEPT' || echo "ACCEPT")
if [[ "$POLICY_ATUAL" == "DROP" || "$POLICY_ATUAL" == "REJECT" ]]; then
  sudo iptables -P OUTPUT ACCEPT
fi

sudo ipset create ALLOWED_DOMAINS hash:ip timeout 86400 --exist

# Valida idempotência: se o ipset existe e a regra mestre do DOCKER-USER já está configurada
if sudo ipset list ALLOWED_DOMAINS >/dev/null 2>&1 && sudo iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT >/dev/null 2>&1; then
    echo "➜ [IDEMPOTÊNCIA PREINSTALL] Firewall perimetral e regras DOCKER-USER já consolidados no Kernel."
else
    # SRE FIX: Garante que a chain DOCKER-USER existe antes de flushear, impedindo interrupção com set -e
    sudo iptables -N DOCKER-USER 2>/dev/null || true
    sudo iptables -F DOCKER-USER

    # Regras Core
    sudo iptables -A DOCKER-USER -j RETURN
    sudo iptables -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -I DOCKER-USER 2 -i lo -j ACCEPT

    # Regras de Egress Core (DNS + IPSet Domínios Autorizados)
    sudo iptables -I DOCKER-USER 3 -p udp --dport 53 -j ACCEPT
    sudo iptables -I DOCKER-USER 4 -p tcp --dport 53 -j ACCEPT
    sudo iptables -I DOCKER-USER 5 -m set --match-set ALLOWED_DOMAINS dst -p tcp -m multiport --dports 80,443 -j ACCEPT

    # Regras de Ingress Core (Caddy HTTP/HTTPS WAF Mestre)
    sudo iptables -I DOCKER-USER 6 -p tcp -m multiport --dports 80,443 -j ACCEPT

    # Isolamento Bridge
    INTERFACE_REAL="br-${EMPRESA}"
    sudo iptables -I DOCKER-USER 7 ! -o "$INTERFACE_REAL" -j LOG --log-prefix "CONTAINER_EGRESS_BLOCKED: " 2>/dev/null || true
    sudo iptables -I DOCKER-USER 8 ! -o "$INTERFACE_REAL" -j DROP 2>/dev/null || true

    echo "➜ [SUCESSO PREINSTALL] Firewall perimetral ativado e consolidado para a empresa: ${EMPRESA}"
fi

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
    # SRE CHECKPOINT HARMONIZATION: Invalida os passos de runtime para forçar absorção do novo .env no install.sh
    sudo sed -i -E '/^(ENV_GENERATION|DOCKER_INFRA)$/d' /tmp/.sre_install_state 2>/dev/null || true
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
echo -e "\e[32m  [SUCESSO PREINSTALL] Host preparado e repositório estruturado em ${TARGET_DIR}!\e[0m"
echo -e "\e[32m  --> Arquivo SSOT: ${TARGET_DIR}/.env\e[0m"
echo -e "\e[32m=====================================================================\e[0m"
echo ""

# Prompt Interativo de Execução
if [ -n "${EXECUTAR_INSTALL:-}" ]; then
    echo -e "\e[32m✔ [AUTO-EXECUTE PREINSTALL] Opção de execução do instalador lida do ambiente (${EXECUTAR_INSTALL}).\e[0m"
else
    if [ -t 0 ] || [ -c /dev/tty ]; then
        coletar_sn "🚀 Deseja iniciar a instalação do daemind. agora?" EXECUTAR_INSTALL "s" "false"
    else
        EXECUTAR_INSTALL="n"
    fi
fi

if [ "$EXECUTAR_INSTALL" = "s" ]; then
    echo "=== [SRE PREINSTALL] Inicializando deploy do daemind. em segundo plano... ==="
    cd "${TARGET_DIR}"
    CURRENT_ACTUAL_USER="${SUDO_USER:-$USER}"
    if [ -f "./core/scripts/install.sh" ]; then
        sudo true; nohup sudo bash -c "export SUDO_USER='${CURRENT_ACTUAL_USER}'; export PREINSTALL_START_TS='${INICIO_TS}'; export PREINSTALL_PAUSE_SEC='${TEMPO_PAUSA_INTERATIVA}'; cd ${TARGET_DIR} && bash ./core/scripts/install.sh" > /dev/null 2>&1 &
    else
        sudo true; nohup sudo bash -c "export SUDO_USER='${CURRENT_ACTUAL_USER}'; export PREINSTALL_START_TS='${INICIO_TS}'; export PREINSTALL_PAUSE_SEC='${TEMPO_PAUSA_INTERATIVA}'; cd ${TARGET_DIR} && bash ./install.sh" > /dev/null 2>&1 &
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
