#!/usr/bin/env bash
#
# ===============================================================================
#  DAEMIND SRE MODULE - AI GATEWAY & SYNC ENGINE: install_1ia.sh
#  Especificação: Sincronização Inteligente de Modelos, Wizard de IA e Envs
# ===============================================================================

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="./.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
fi

PREFIXO_CONTAINER="${PREFIXO_CONTAINER:-${PREFIX_NAME:-${PREFIX:-${COMPOSE_PROJECT_NAME}}}}"
if [ -z "$PREFIXO_CONTAINER" ] && command -v docker >/dev/null 2>&1; then
    PREFIXO_CONTAINER=$(docker ps -a --filter "name=_litellm" --format '{{.Names}}' 2>/dev/null | head -n 1 | sed 's/_litellm$//' || true)
fi

# ===============================================================================
# 0. collect_wizard_inputs (CLI) & collect_wizard_inputs_tui (TUI) & build_envs
# ===============================================================================
collect_wizard_inputs_tui() {
    local ia_substep=1
    local AI_CHOICE=""
    local GEMINI_MODE="NONE"

    while [ "$ia_substep" -ge 1 ] && [ "$ia_substep" -le 3 ]; do
        case "$ia_substep" in
            1)
                # --- 1. Checklist Big 4 (OpenAI, Anthropic, Google Gemini, DeepSeek) ---
                local ST_OPENAI="off";    [ -n "${OPENAI_API_KEY:-}" ]    && ST_OPENAI="on"
                local ST_ANTHROPIC="off"; [ -n "${ANTHROPIC_API_KEY:-}" ] && ST_ANTHROPIC="on"
                local ST_GEMINI="off";    { [ "${FREE_GEMINI:-0}" = "1" ] || [ -n "${GEMINI_API_KEY:-}" ] || [[ "${RESP_GEMINI_FREE:-}" =~ ^[Ss]$ ]]; } && ST_GEMINI="on"
                local ST_DEEPSEEK="off";  [ -n "${DEEPSEEK_API_KEY:-}" ]  && ST_DEEPSEEK="on"

                AI_CHOICE=$(tui_dialog_step --title "Passo 4/6: Provedores de Inteligência Artificial (LiteLLM)" \
                    --checklist "OpenRouter é obrigatório (sempre ativo). Selecione provedores adicionais (Big 4):" 14 76 4 \
                    "OPENAI"    "OpenAI (ChatGPT / GPT-4o / GPT-4o-mini)" "$ST_OPENAI"    \
                    "ANTHROPIC" "Anthropic Claude (Claude 3.5 Sonnet)"    "$ST_ANTHROPIC" \
                    "GEMINI"    "Google Gemini (Modelos Flash, Gemma ou 2.0 Pro)" "$ST_GEMINI" \
                    "DEEPSEEK"  "DeepSeek (DeepSeek V3 / R1)"             "$ST_DEEPSEEK"  \
                    )
                if [ $? -ne 0 ]; then
                    return 1
                fi

                if echo "$AI_CHOICE" | grep -q "GEMINI"; then
                    ia_substep=2
                else
                    FREE_GEMINI="0"
                    RESP_GEMINI_FREE="n"
                    GEMINI_API_KEY=""
                    GEMINI_MODE="NONE"
                    ia_substep=3
                fi
                ;;

            2)
                # --- 2. Tela Condicional do Gemini (Se marcado no Big 4) ---
                local ST_G_FREE="on"
                local ST_G_PRO="off"
                [ "${FREE_GEMINI:-0}" = "0" ] && [ -n "${GEMINI_API_KEY:-}" ] && { ST_G_FREE="off"; ST_G_PRO="on"; }

                local GEMINI_SUB_CHOICE
                GEMINI_SUB_CHOICE=$(tui_dialog_step \
                    --title "Passo 4b/6: Modalidade Google Gemini" \
                    --radiolist "Você selecionou o Google Gemini. Escolha a modalidade de uso:" 11 74 2 \
                    "FREE" "Gemini Gratuito (Apenas modelos 100% Free Flash/Gemma via Google AI Studio)" "$ST_G_FREE" \
                    "PRO"  "Gemini Pago / Pro (Modelos Avançados Gemini 2.0 Pro / Thinking)"             "$ST_G_PRO"  \
                    )
                if [ $? -ne 0 ]; then
                    ia_substep=1
                    continue
                fi
                [ -z "$GEMINI_SUB_CHOICE" ] && GEMINI_SUB_CHOICE="FREE"
                GEMINI_MODE="$GEMINI_SUB_CHOICE"

                if [ "$GEMINI_MODE" = "FREE" ]; then
                    FREE_GEMINI="1"
                    RESP_GEMINI_FREE="s"
                else
                    FREE_GEMINI="0"
                    RESP_GEMINI_FREE="n"
                fi
                ia_substep=3
                ;;

            3)
                # --- 3. Formulário Unificado de Chaves de API Selecionadas ---
                local AI_FORM_FIELDS=()
                local ROW_IDX=1

                # OpenRouter (Obrigatório para a Stack - Sempre o Primeiro)
                AI_FORM_FIELDS+=("OpenRouter API Key (sk-or-v1-... - Obrigatório):" $ROW_IDX 1 "${OPENROUTER_API_KEY:-}" $((ROW_IDX + 1)) 1 82 512 0)
                ROW_IDX=$((ROW_IDX + 3))

                if echo "$AI_CHOICE" | grep -q "OPENAI"; then
                    AI_FORM_FIELDS+=("OpenAI API Key (sk-proj-...):" $ROW_IDX 1 "${OPENAI_API_KEY:-}" $((ROW_IDX + 1)) 1 82 512 0)
                    ROW_IDX=$((ROW_IDX + 3))
                fi

                if echo "$AI_CHOICE" | grep -q "ANTHROPIC"; then
                    AI_FORM_FIELDS+=("Anthropic Claude API Key (sk-ant-...):" $ROW_IDX 1 "${ANTHROPIC_API_KEY:-}" $((ROW_IDX + 1)) 1 82 512 0)
                    ROW_IDX=$((ROW_IDX + 3))
                fi

                if [ "$GEMINI_MODE" != "NONE" ]; then
                    local g_lbl="Google Gemini API Key (AIzaSy...):"
                    [ "$GEMINI_MODE" = "FREE" ] && g_lbl="Google Gemini Free API Key (AIzaSy...):"
                    AI_FORM_FIELDS+=("$g_lbl" $ROW_IDX 1 "${GEMINI_API_KEY:-}" $((ROW_IDX + 1)) 1 82 512 0)
                    ROW_IDX=$((ROW_IDX + 3))
                fi

                if echo "$AI_CHOICE" | grep -q "DEEPSEEK"; then
                    AI_FORM_FIELDS+=("DeepSeek API Key (sk-...):" $ROW_IDX 1 "${DEEPSEEK_API_KEY:-}" $((ROW_IDX + 1)) 1 82 512 0)
                    ROW_IDX=$((ROW_IDX + 3))
                fi

                local TOTAL_H=$((ROW_IDX + 5))
                [ $TOTAL_H -lt 14 ] && TOTAL_H=14
                local FORM_H=$((ROW_IDX))

                local AI_KEYS_OUT
                AI_KEYS_OUT=$(tui_dialog_step --title "Passo 4c/6: Chaves de API dos Provedores de IA" \
                    --mixedform "Preencha as chaves dos provedores de IA selecionados para a stack:" $TOTAL_H 90 $FORM_H \
                    "${AI_FORM_FIELDS[@]}")
                if [ $? -ne 0 ]; then
                    if echo "$AI_CHOICE" | grep -q "GEMINI"; then
                        ia_substep=2
                    else
                        ia_substep=1
                    fi
                    continue
                fi

                local CUR_L=1
                OPENROUTER_API_KEY=$(clean_tui_field "$(echo "$AI_KEYS_OUT" | sed -n "${CUR_L}p")")
                CUR_L=$((CUR_L + 1))

                if echo "$AI_CHOICE" | grep -q "OPENAI"; then
                    OPENAI_API_KEY=$(clean_tui_field "$(echo "$AI_KEYS_OUT" | sed -n "${CUR_L}p")")
                    CUR_L=$((CUR_L + 1))
                fi
                if echo "$AI_CHOICE" | grep -q "ANTHROPIC"; then
                    ANTHROPIC_API_KEY=$(clean_tui_field "$(echo "$AI_KEYS_OUT" | sed -n "${CUR_L}p")")
                    CUR_L=$((CUR_L + 1))
                fi
                if [ "$GEMINI_MODE" != "NONE" ]; then
                    GEMINI_API_KEY=$(clean_tui_field "$(echo "$AI_KEYS_OUT" | sed -n "${CUR_L}p")")
                    CUR_L=$((CUR_L + 1))
                fi
                if echo "$AI_CHOICE" | grep -q "DEEPSEEK"; then
                    DEEPSEEK_API_KEY=$(clean_tui_field "$(echo "$AI_KEYS_OUT" | sed -n "${CUR_L}p")")
                    CUR_L=$((CUR_L + 1))
                fi

                # Validação OpenRouter: obrigatória
                if [ -z "$OPENROUTER_API_KEY" ] || ! [[ "$OPENROUTER_API_KEY" =~ ^sk-or-v1- ]]; then
                    tui_dialog --title "Erro de Validação" \
                        --msgbox "A chave do OpenRouter é obrigatória e deve começar com 'sk-or-v1-'." 8 65 || true
                    continue
                fi

                # Persistir todo o estado de IA no cache
                save_wizard_cache "OPENROUTER_API_KEY" "$OPENROUTER_API_KEY"
                save_wizard_cache "FREE_GEMINI"        "$FREE_GEMINI"
                save_wizard_cache "RESP_GEMINI_FREE"   "$RESP_GEMINI_FREE"
                save_wizard_cache "GEMINI_API_KEY"     "$GEMINI_API_KEY"
                save_wizard_cache "OPENAI_API_KEY"     "$OPENAI_API_KEY"
                save_wizard_cache "ANTHROPIC_API_KEY"  "$ANTHROPIC_API_KEY"
                save_wizard_cache "DEEPSEEK_API_KEY"   "$DEEPSEEK_API_KEY"
                export FREE_GEMINI RESP_GEMINI_FREE OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY DEEPSEEK_API_KEY
                return 0
                ;;
        esac
    done
    return 1
}

collect_wizard_inputs() {
    echo ""
    echo -e "\e[33m=== [SRE AI GATEWAY] Wizard de Inteligência Artificial (Gateway Múltiplo) ===\e[0m"

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
    save_wizard_cache "OPENAI_API_KEY" "$OPENAI_API_KEY"
    save_wizard_cache "ANTHROPIC_API_KEY" "$ANTHROPIC_API_KEY"
    save_wizard_cache "GEMINI_API_KEY" "$GEMINI_API_KEY"
    save_wizard_cache "DEEPSEEK_API_KEY" "$DEEPSEEK_API_KEY"
    save_wizard_cache "OPENROUTER_API_KEY" "$OPENROUTER_API_KEY"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    cat << EOF >> "$env_path"

# =========================================================================
# APIS DE TERCEIROS E INTELIGÊNCIA ARTIFICIAL (GATEWAY MÚLTIPLO)
# =========================================================================
# Integrações de E-commerce (Desativado momentaneamente)
LOJA_API_KEY=""
LOJA_APP_KEY=""

# System Prompt Canônico
IA_SYSTEM_PROMPT="Voce eh um assistente de IA focado em recuperacao de vendas, conversao de boletos e pix para e-commerce."

# Provedor Ativo Resolvido Dinamicamente
ACTIVE_AI_PROVIDER="openrouter"

# Chaves de Provedores de IA (OpenRouter e Gemini Free)
FREE_GEMINI="${FREE_GEMINI:-0}"
GEMINI_API_KEY="${GEMINI_API_KEY}"
OPENAI_API_KEY="${OPENAI_API_KEY}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY}"
EOF
}

# ===============================================================================
# 1. sync_models: Sincronização Diária: Catálogos Big 5 -> Banco de Dados LiteLLM
# ===============================================================================
sync_models() {
    local LITELLM_URL="http://127.0.0.1:4000"
    local LOG_ERR="/tmp/sync_ia_errors.log"
    > "$LOG_ERR"
    chmod 777 $LOG_ERR 2>/dev/null || true

    echo "=== [SRE COMPATIBILITY ENGINE AI GATEWAY] Iniciando Varredura e Matchmaking ==="

    # 1. VARREDURA DINÂMICA DE MODELOS DAS APLICAÇÕES (Postiz, Chatwoot, Metabase, n8n, Evolution)
    declare -A DETECTED_ALIASES_MAP
    local APP_DETECTED_MODELS=()

    add_app_model() {
        local m="$1"
        m=$(echo "$m" | tr -d '"'\''\r\n ' || true)
        if [ -n "$m" ] && [ -z "${DETECTED_ALIASES_MAP[$m]:-}" ]; then
            DETECTED_ALIASES_MAP["$m"]=1
            APP_DETECTED_MODELS+=("$m")
        fi
    }

    echo "➜ [SRE AI DISCOVERY] Executando varredura dinâmica de modelos em uso pelas aplicações..."

    # 1.1 Varredura Postiz (Serviço NestJS + Agent Mastra AI)
    if [ "$(docker inspect -f '{{.State.Running}}' ${PREFIXO_CONTAINER}_postiz 2>/dev/null)" = "true" ]; then
        local POSTIZ_MODELS
        POSTIZ_MODELS=$(docker exec -i ${PREFIXO_CONTAINER}_postiz grep -roE "(model|modelId): *['\"][a-zA-Z0-9_./-]+['\"]|openai\(['\"][a-zA-Z0-9_./-]+['\"]\)" /app/libraries /app/node_modules/@ag-ui /app/node_modules/@mastra 2>/dev/null | grep -oE "['\"][a-zA-Z0-9_./-]+['\"]" | tr -d '"'\'' ' | grep -iE 'gpt-|claude-|gemini-|deepseek-|openrouter/' | sort -u || true)
        for pm in $POSTIZ_MODELS; do
            add_app_model "$pm"
        done
    fi

    # 1.2 Varredura Dinâmica Chatwoot CRM (Configurações de Banco e llm.yml / llm_constants.rb)
    if [ "$(docker inspect -f '{{.State.Running}}' ${PREFIXO_CONTAINER}_chatwoot 2>/dev/null)" = "true" ]; then
        local CW_DYNAMIC_MODELS
        # Consulta direta no banco PostgreSQL do Chatwoot (installation_configs)
        CW_DYNAMIC_MODELS=$(docker exec -i ${PREFIXO_CONTAINER}_postgres psql -U "${DB_USER:-admin_db}" -d "chatwoot_db" -t -A -c "
            SELECT serialized_value FROM installation_configs WHERE name ILIKE '%MODEL%' OR name ILIKE '%OPENAI%' OR name ILIKE '%CAPTAIN%';
        " 2>/dev/null | grep -oE "['\"][a-zA-Z0-9_./-]+['\"]" | tr -d '"'\'' ' | grep -iE 'gpt-|claude-|gemini-|deepseek-|openrouter/' || true)

        # Varredura direta no arquivo de catálogo nativo do Chatwoot (config/llm.yml e lib/llm_constants.rb)
        local CW_FILE_MODELS
        CW_FILE_MODELS=$(docker exec -i ${PREFIXO_CONTAINER}_chatwoot sh -c "cat /app/config/llm.yml /app/lib/llm_constants.rb 2>/dev/null" | grep -oE "[a-zA-Z0-9_.-]+:[0-9a-zA-Z_.-]*|DEFAULT_MODEL *= *['\"][a-zA-Z0-9_./-]+['\"]|models: *\[.*\]|default: *[a-zA-Z0-9_./-]+" | grep -oE "gpt-[a-zA-Z0-9_./-]+|claude-[a-zA-Z0-9_./-]+|gemini-[a-zA-Z0-9_./-]+" | sort -u || true)

        for cwm in $CW_DYNAMIC_MODELS $CW_FILE_MODELS; do
            [ -n "$cwm" ] && add_app_model "$cwm"
        done
    fi

    # 1.3 Varredura Metabase BI (Catálogo Nativo e Configurações Ativas)
    if [ "$(docker inspect -f '{{.State.Status}}' ${PREFIXO_CONTAINER}_metabase 2>/dev/null)" = "running" ] || [ "$(docker inspect -f '{{.State.Health.Status}}' ${PREFIXO_CONTAINER}_metabase 2>/dev/null)" = "healthy" ]; then
        local MB_DISCOVERED=""
        
        # 1.3.1 Extração dinâmica de todos os modelos homologados no schema de settings do Metabase
        local MB_SCHEMA_MODELS
        MB_SCHEMA_MODELS=$(curl -s "http://127.0.0.1:3030/api/setting" 2>/dev/null | grep -oE "['\"][a-zA-Z0-9_./-]+['\"]" | tr -d '"'\'' ' | grep -iE 'gpt-|claude-|gemini-|deepseek-|openrouter/' | sort -u || true)
        
        # 1.3.2 Leitura das variáveis de ambiente ativas do container Metabase
        local MB_ENV_MODELS
        MB_ENV_MODELS=$(docker exec -i "${PREFIXO_CONTAINER}_metabase" env 2>/dev/null | grep -iE 'MB_LLM_|MB_OPENAI_' | cut -d= -f2- | tr -d '"\r' | grep -iE 'gpt-|claude-|gemini-|deepseek-|openrouter/' || true)
        
        # 1.3.3 Leitura direta na tabela setting do PostgreSQL metabase_db
        local MB_DB_MODELS=""
        if [ "$(docker inspect -f '{{.State.Health.Status}}' ${PREFIXO_CONTAINER}_postgres 2>/dev/null)" = "healthy" ]; then
            MB_DB_MODELS=$(docker exec -i "${PREFIXO_CONTAINER}_postgres" psql -U "${DB_USER:-admin_db}" -d "metabase_db" -t -A -c "
                SELECT value FROM setting WHERE key LIKE '%llm%' OR key LIKE '%openai%' OR key LIKE '%metabot%';
            " 2>/dev/null | grep -oE "[a-zA-Z0-9_./-]+" | grep -iE 'gpt-|claude-|gemini-|deepseek-|openrouter/' | tr -d '"\r' || true)
        fi

        for mm in $MB_SCHEMA_MODELS $MB_ENV_MODELS $MB_DB_MODELS; do
            [ -z "$mm" ] && continue
            # Registra o modelo exato (ex: openai/gpt-5.4, claude-opus-4-5-20251101, gpt-4.1)
            add_app_model "$mm"
            # Registra a versão sem o prefixo do provedor (ex: openai/gpt-5.4 -> gpt-5.4)
            local mm_clean
            mm_clean=$(echo "$mm" | sed -E 's|^(openai|anthropic|azure|mistral|openrouter)/||')
            [ -n "$mm_clean" ] && add_app_model "$mm_clean"
        done
    fi

    # 1.4 Varredura n8n AI Assistant
    if [ "$(docker inspect -f '{{.State.Running}}' ${PREFIXO_CONTAINER}_n8n 2>/dev/null)" = "true" ]; then
        local N8N_AI_M
        N8N_AI_M=$(docker exec -i ${PREFIXO_CONTAINER}_n8n env 2>/dev/null | grep -E '^N8N_INSTANCE_AI_MODEL=' | cut -d= -f2- | tr -d '"\r' || true)
        [ -n "$N8N_AI_M" ] && add_app_model "$N8N_AI_M"
    fi

    # 1.5 Fallback universal garantido
    add_app_model "openrouter/free"

    echo "  ↳ Total de aliases de compatibilidade ativos: ${#APP_DETECTED_MODELS[@]} [ ${APP_DETECTED_MODELS[*]} ]"

    # 2. INTEGRAÇÃO ATÔMICA DOS CATÁLOGOS (Busca os Modelos nas APIs)
    local PAYLOADS_TOTAIS="[]"
    local PAYLOAD_OPENAI="[]"
    local PAYLOAD_ANTHROPIC="[]"
    local PAYLOAD_GOOGLE="[]"
    local PAYLOAD_DEEPSEEK="[]"
    local PAYLOAD_OPENROUTER="[]"

    append_payloads() {
        local novos="$1"
        if [ -n "$novos" ] && [ "$novos" != "[]" ] && [ "$novos" != "null" ]; then
            PAYLOADS_TOTAIS=$(jq -n --argjson a "$PAYLOADS_TOTAIS" --argjson b "$novos" '$a + $b')
        fi
    }

    # 2.1 OPENAI
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        PAYLOAD_OPENAI=$(curl -fsSL https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY" 2>>"$LOG_ERR" | jq -c '
        def canonical: .id | sub("-[0-9]{4}-[0-9]{2}-[0-9]{2}$"; "");
        def category: if (.id|test("embedding")) then "embedding" elif (.id|test("moderation")) then "moderation" elif (.id|test("tts|audio")) then "audio" elif (.id|test("transcribe|whisper")) then "transcription" elif (.id|test("realtime")) then "realtime" elif (.id|test("image|dall-e|sora")) then "media" elif (.id|test("search")) then "search" else "chat" end;

        .data
        | map(select((.owned_by != "openai-internal") and (.id | test("^(ra-|ft:|user-|system-)") | not) and (.id | test("gpt-3\\.5|babbage|davinci|instruct|codex") | not) and (.id | test("latest$") | not) and (category == "chat")))
        | map(. + {
            canonical: canonical,
            is_alias: (.id == canonical),
            root_line: (if (.id | test("^gpt")) then "gpt" elif (.id | test("^o[0-9]")) then "o" else (.id | split("-")[0]) end),
            version_prefix: (if (.id | test("^gpt-[0-9]")) then (.id | capture("^(?<v>gpt-[0-9]+(\\.[0-9]+)?)").v) elif (.id | test("^gpt-4o")) then "gpt-4o" elif (.id | test("^o[0-9]")) then (.id | capture("^(?<v>o[0-9]+)").v) else (canonical | split("-")[0]) end)
          })
        | group_by(.canonical)
        | map((map(select(.is_alias)) + map(select(.is_alias | not))) | first)
        | group_by(.root_line)
        | map((sort_by(.created) | last.version_prefix) as $latest_ver | map(select(.version_prefix == $latest_ver)))
        | flatten
        | sort_by(.created) | reverse
        | map({
            ID: .canonical,
            Family: .version_prefix,
            Provider: "openai",
            Category: (["chat", "tools"] + (if (.canonical | test("gpt-4|gpt-5")) then ["image", "vision"] else [] end) + (if (.canonical | test("^o[0-9]")) then ["reasoning"] else [] end)) | unique | join(", "),
            Description: "Modelo Oficial OpenAI: \(.canonical)",
            Free: false,
            Created: .created,
            Alias: .is_alias
        })' || echo "[]")
        append_payloads "$PAYLOAD_OPENAI"
    fi

    # 2.2 ANTHROPIC
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        PAYLOAD_ANTHROPIC=$(curl -s https://api.anthropic.com/v1/models -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" 2>>"$LOG_ERR" | jq -c '
        def canonical: .id | sub("(-[0-9]{8}|-[0-9]{4}-[0-9]{2}-[0-9]{2})$"; "");
        def tier: if (.id | test("^claude-[a-z]+")) then (.id | capture("^claude-(?<t>[a-z]+)").t) else "other" end;

        .data
        | map(select(.id | test("latest$") | not))
        | map(. + {
            canonical: canonical,
            tier: tier,
            is_alias: (.id == canonical),
            version_prefix: (if (canonical | test("^claude-[a-z]+-[0-9]+")) then (canonical | capture("^(?<v>claude-[a-z]+-[0-9]+([.-][0-9]+)?)").v) else canonical end)
          })
        | group_by(.canonical)
        | map((map(select(.is_alias)) + map(select(.is_alias | not))) | first)
        | group_by(.tier)
        | map((sort_by(.created_at) | last.version_prefix) as $latest_ver | map(select(.version_prefix == $latest_ver)))
        | flatten
        | sort_by(.created_at) | reverse
        | map({
            ID: .canonical,
            Family: .tier,
            Provider: "anthropic",
            Category: (["chat", "tools"] + (if .capabilities.image_input?.supported then ["image", "vision"] else [] end) + (if .capabilities.thinking?.supported then ["reasoning"] else [] end) + (if .capabilities.pdf_input?.supported then ["pdf_analysis"] else [] end)) | unique | join(", "),
            Description: (.display_name // "Modelo Anthropic \(.canonical)"),
            Free: false,
            Created: .created_at,
            Alias: .is_alias
        })' || echo "[]")
        append_payloads "$PAYLOAD_ANTHROPIC"
    fi

    # 2.3 GOOGLE GEMINI
    local API_KEY_GOOGLE="${GEMINI_API_KEY:-$GOOGLE_API_KEY}"
    if [ -n "$API_KEY_GOOGLE" ]; then
        PAYLOAD_GOOGLE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$API_KEY_GOOGLE" 2>>"$LOG_ERR" | jq -c --arg free_only "${FREE_GEMINI:-0}" '
        def clean_id: .name | sub("^models/"; "");
        def extract_version: clean_id | if test("[0-9]+\\.[0-9]+") then (capture("(?<v>[0-9]+\\.[0-9]+)").v | tonumber) elif test("-[0-9]+-") then (capture("-(?<v>[0-9]+)-").v | tonumber) elif test("-[0-9]+$") then (capture("-(?<v>[0-9]+)$").v | tonumber) else 1.0 end;
        def extract_tier: clean_id | sub("^(gemini|gemma)-[0-9]+(\\.[0-9]+)?-?"; "") | sub("-(preview|001|002|customtools).*$"; "") | if . == "" then "base" else . end;
        def canonical_key: clean_id | sub("-(preview|001|002)$"; "") | sub("-preview-.*$"; "");

        .models
        | map(select((.supportedGenerationMethods | contains(["generateContent"])) and (.name | test("embedding|lyria|robotics|aqa|computer-use|antigravity|deep-research|imagen|veo|tts|-latest$|nano-banana") | not)))
        | map(select(if $free_only == "1" then (.name | test("gemma|flash")) else true end))
        | map(. + {
            id: clean_id,
            version: extract_version,
            tier: extract_tier,
            canonical: canonical_key,
            is_stable: (clean_id | test("preview|001") | not)
          })
        | group_by(.canonical)
        | map((map(select(.is_stable)) + map(select(.is_stable | not))) | first)
        | group_by(.tier)
        | map((sort_by(.version) | last.version) as $max_ver | map(select(.version == $max_ver)))
        | flatten
        | sort_by(.version) | reverse
        | map({
            ID: .id,
            Family: (if (.id | test("^gemma")) then ("gemma-" + .tier) else ("gemini-" + .tier) end),
            Provider: "google",
            Category: (["chat", "tools"] + (if (.id | test("gemini")) then ["image", "vision", "audio", "video"] else [] end) + (if .thinking then ["reasoning"] else [] end)) | unique | join(", "),
            Description: (.description // "Modelo multimodal Google Gemini"),
            Free: (.id | test("gemma|flash")),
            Created: 0,
            Alias: .is_stable
        })' || echo "[]")
        append_payloads "$PAYLOAD_GOOGLE"
    fi

    # 2.4 DEEPSEEK
    if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
        PAYLOAD_DEEPSEEK=$(curl -s https://api.deepseek.com/v1/models -H "Authorization: Bearer $DEEPSEEK_API_KEY" 2>>"$LOG_ERR" | jq -c '
        def family: if (.id | test("^deepseek-v[0-9]+")) then (.id | capture("^(?<f>deepseek-v[0-9]+)").f) else "deepseek" end;

        .data
        | map(select((.id | test("latest$") | not) and (.id | test("embedding|moderation") | not)))
        | map(. + {
            family: family,
            created_val: (.created // 0)
          })
        | map({
            ID: .id,
            Family: .family,
            Provider: "deepseek",
            Category: "chat, tools, reasoning",
            Description: "Modelo Oficial DeepSeek \(.id) (Suporte a Raciocínio CoT e Function Calling)",
            Free: false,
            Created: .created_val,
            Alias: true
        })' || echo "[]")
        append_payloads "$PAYLOAD_DEEPSEEK"
    fi

    # 2.5 OPENROUTER
    if [ -n "${OPENROUTER_API_KEY:-}" ]; then
        PAYLOAD_OPENROUTER=$(curl -s "https://openrouter.ai/api/v1/models" 2>>"$LOG_ERR" | jq -c '
        .data
        | map(select(
            (.pricing.prompt == "0" and .pricing.completion == "0") and
            (.id | test("content-safety|guardrail|lyria|embedding|moderation") | not)
          ))
        | map(. + {
            clean_id: (.id | sub(":free$"; "")),
            family: (.id | sub(":free$"; "") | split("-")[0])
          })
        | sort_by(.created) | reverse
        | map({
            ID: .clean_id,
            Family: .family,
            Provider: "openrouter",
            Category: (["chat"] + (if (.architecture.input_modalities | type == "array") then .architecture.input_modalities else [] end) + (if (.supported_parameters | type == "array" and contains(["tools"])) then ["tools"] else [] end) + (if (.supported_parameters | type == "array" and contains(["reasoning"])) then ["reasoning"] else [] end)) | map(if . == "text" then empty else . end) | unique | join(", "),
            Description: (.description // "Modelo agregado via OpenRouter"),
            Free: (.pricing.prompt == "0" and .pricing.completion == "0"),
            Created: .created,
            Alias: true
        })' || echo "[]")
        append_payloads "$PAYLOAD_OPENROUTER"
    fi

    # 2.6 OLLAMA (Modelos Locais On-Premise)
    local PAYLOAD_OLLAMA="[]"
    local OLLAMA_URL="http://${PREFIXO_CONTAINER}_ollama:11434"
    if [[ "${USE_OLLAMA:-s}" =~ ^[Ss]$ ]] && [ "$(docker inspect -f '{{.State.Running}}' ${PREFIXO_CONTAINER}_ollama 2>/dev/null)" = "true" ]; then
        PAYLOAD_OLLAMA=$(curl -s --max-time 3 "${OLLAMA_URL}/api/tags" 2>>"$LOG_ERR" | jq -c --arg base "$OLLAMA_URL" '
        .models // []
        | map({
            ID: .name,
            Family: (.details.family // "ollama"),
            Provider: "ollama",
            Category: (["local", "chat"] + (if (.name | test("vision|llava|bakllava|moondream")) then ["vision", "image"] else [] end)) | unique | join(", "),
            Description: "Modelo Local Ollama \(.name) (\(.details.parameter_size // "Local") - \(.details.quantization_level // "GGUF"))",
            Free: true,
            Created: 0,
            Alias: true,
            ApiBase: $base
        })' 2>/dev/null || echo "[]")
        append_payloads "$PAYLOAD_OLLAMA"
    fi

    # 3. SRE HEALTH PROBER & RANKING DE FALLBACK (Zero-Hardcode & Auto-Healing)
    echo "➜ [SRE HEALTH PROBER] Testando e ranqueando a saúde dos modelos candidatos em tempo real..."
    local TARGET_MODEL=""
    local HEALTHY_FALLBACKS=()

    probe_openrouter_candidate() {
        local m_id="$1"
        local response
        response=$(curl -s -m 5 "https://openrouter.ai/api/v1/chat/completions" \
            -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"${m_id}\", \"messages\": [{\"role\": \"user\", \"content\": \"1\"}], \"max_tokens\": 1}" 2>/dev/null || echo "")
        
        if echo "$response" | grep -q '"choices"'; then
            return 0
        else
            return 1
        fi
    }

    if [ -n "${ANTHROPIC_API_KEY:-}" ] && [ "$PAYLOAD_ANTHROPIC" != "[]" ]; then
        local EXTRACTED
        EXTRACTED=$(echo "$PAYLOAD_ANTHROPIC" | jq -r '[.[] | select(.ID | test("sonnet"))] | sort_by(.Created) | last.ID // empty')
        [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_ANTHROPIC" | jq -r '.[0].ID // empty')
        [ -n "$EXTRACTED" ] && TARGET_MODEL="anthropic/${EXTRACTED}"

    elif [ -n "${OPENAI_API_KEY:-}" ] && [ "$PAYLOAD_OPENAI" != "[]" ]; then
        local EXTRACTED
        EXTRACTED=$(echo "$PAYLOAD_OPENAI" | jq -r '[.[] | select(.ID | test("luna"))] | sort_by(.Created) | last.ID // empty')
        [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_OPENAI" | jq -r '.[0].ID // empty')
        [ -n "$EXTRACTED" ] && TARGET_MODEL="openai/${EXTRACTED}"

    elif [ -n "${GEMINI_API_KEY:-}" ] && [ "${FREE_GEMINI:-1}" = "0" ] && [ "$PAYLOAD_GOOGLE" != "[]" ]; then
        local EXTRACTED
        EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r 'map(select(.ID | test("-flash$"))) | .[0].ID // empty')
        [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r 'map(select(.ID | test("-flash-lite$"))) | .[0].ID // empty')
        [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r '.[0].ID // empty')
        [ -n "$EXTRACTED" ] && TARGET_MODEL="gemini/${EXTRACTED}"

    elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
        local CANDIDATES
        CANDIDATES=$(echo "$PAYLOADS_TOTAIS" | jq -r '[.[] | select(.Provider == "openrouter")] | .[].ID')
        local TMP_PROBE_DIR
        TMP_PROBE_DIR=$(mktemp -d)

        for cand in $CANDIDATES; do
            (
                local PROBE_ID="$cand"
                if [ "$cand" != "openrouter/free" ] && ! echo "$cand" | grep -q ":free"; then
                    PROBE_ID="${cand}:free"
                fi
                local START_TS
                START_TS=$(date +%s%N 2>/dev/null | cut -b1-13)
                [ -z "$START_TS" ] && START_TS=$(date +%s)
                local RESP
                RESP=$(curl -s -m 5 "https://openrouter.ai/api/v1/chat/completions" \
                    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
                    -H "Content-Type: application/json" \
                    -d "{\"model\": \"${PROBE_ID}\", \"messages\": [{\"role\": \"user\", \"content\": \"1\"}], \"max_tokens\": 1}" 2>/dev/null || echo "")
                local END_TS
                END_TS=$(date +%s%N 2>/dev/null | cut -b1-13)
                [ -z "$END_TS" ] && END_TS=$(date +%s)
                local LATENCY=$(( END_TS - START_TS ))
                [ "$LATENCY" -lt 0 ] && LATENCY=0

                if echo "$RESP" | grep -q '"choices"'; then
                    printf "%06d:%s\n" "$LATENCY" "$cand" > "${TMP_PROBE_DIR}/${cand//\//_}.ok"
                fi
            ) &
        done
        wait

        if ls "${TMP_PROBE_DIR}"/*.ok >/dev/null 2>&1; then
            while IFS=: read -r lat_raw c_name || [ -n "$lat_raw" ]; do
                [ -z "$c_name" ] && continue
                local lat
                lat=$(echo "$lat_raw" | sed 's/^0*//')
                [ -z "$lat" ] && lat=0
                echo "  ↳ Modelo saudável verificado: $c_name (${lat}ms)"
                [ -z "$TARGET_MODEL" ] && TARGET_MODEL="$c_name"
                HEALTHY_FALLBACKS+=("$c_name")
            done < <(sort "${TMP_PROBE_DIR}"/*.ok 2>/dev/null)
        fi
        rm -rf "$TMP_PROBE_DIR"

        # SRE PURGE: Remove do catálogo global todos os modelos que não responderam ao probe
        if [ "${#HEALTHY_FALLBACKS[@]}" -gt 0 ]; then
            local HEALTHY_IDS_JSON
            HEALTHY_IDS_JSON=$(printf '%s\n' "${HEALTHY_FALLBACKS[@]}" | jq -R . | jq -s .)
            PAYLOADS_TOTAIS=$(echo "$PAYLOADS_TOTAIS" | jq -c --argjson ok "$HEALTHY_IDS_JSON" '
                map(select((.Provider != "openrouter") or (.ID as $id | $ok | contains([$id]))))
            ')
        fi

    elif [ -n "${GEMINI_API_KEY:-}" ] && [ "$PAYLOAD_GOOGLE" != "[]" ]; then
        local EXTRACTED
        EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r 'map(select(.ID | test("-flash$"))) | .[0].ID // empty')
        [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r 'map(select(.ID | test("-flash-lite$"))) | .[0].ID // empty')
        [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r '.[0].ID // empty')
        [ -n "$EXTRACTED" ] && TARGET_MODEL="gemini/${EXTRACTED}"

    elif [ -n "${DEEPSEEK_API_KEY:-}" ] && [ "$PAYLOAD_DEEPSEEK" != "[]" ]; then
        local EXTRACTED
        EXTRACTED=$(echo "$PAYLOAD_DEEPSEEK" | jq -r '[.[] | select(.ID | test("flash"))] | sort_by(.Created) | last.ID // empty')
        [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_DEEPSEEK" | jq -r '.[0].ID // empty')
        [ -n "$EXTRACTED" ] && TARGET_MODEL="deepseek/${EXTRACTED}"
    fi

    [ -z "$TARGET_MODEL" ] && TARGET_MODEL="openrouter/free"
    echo "  ↳ Target Model eleito por auditoria de saúde: $TARGET_MODEL"
    echo "  ↳ Fallback Ranking: ${HEALTHY_FALLBACKS[*]:-openrouter/free}"

    # Resolve o target visual completo (incluindo (free) ou (local) se aplicável)
    local TARGET_VISUAL
    TARGET_VISUAL=$(echo "$PAYLOADS_TOTAIS" | jq -r --arg tm "$TARGET_MODEL" '
        def litellm_provider: if .Provider == "google" then "gemini" else .Provider end;
        def full_id: (litellm_provider) as $lp | (if (.ID | startswith($lp + "/")) then .ID else "\($lp)/\(.ID)" end);
        [.[] | select(full_id == $tm or .ID == $tm)] | first | 
        if . == null then $tm else
          "\(.ID)\(if .Provider == "ollama" then " (local)" elif .Free then " (free)" else "" end)"
        end
    ' 2>/dev/null || echo "$TARGET_MODEL")

    [ -z "$TARGET_VISUAL" ] && TARGET_VISUAL="$TARGET_MODEL"

    # 4. FORJA DO YAML (Gravação Definitiva no LiteLLM)
    local TOTAL
    TOTAL=$(echo "$PAYLOADS_TOTAIS" | jq length)

    if [ "$TOTAL" -gt 0 ]; then
        local TARGET_DIR_LITE="${TARGET_DIR:-/opt/daemind}"
        mkdir -p "$TARGET_DIR_LITE/volumes/litellm_data"
        local TMP_CONFIG
        TMP_CONFIG=$(mktemp)

        # Constrói array JSON com o ranking de fallbacks saudáveis
        local FALLBACK_JSON
        FALLBACK_JSON=$(printf '%s\n' "${HEALTHY_FALLBACKS[@]}" | jq -R . 2>/dev/null | jq -s --arg tm "$TARGET_VISUAL" '([$tm] + .) | unique | map(select(length > 0))' 2>/dev/null || echo "[\"$TARGET_VISUAL\"]")
        [ "$FALLBACK_JSON" = "[]" ] && FALLBACK_JSON="[\"$TARGET_VISUAL\"]"

        # Gera as entradas do model_alias_map dinamicamente para cada modelo descoberto
        local MODEL_ALIASES_YAML=""
        for app_m in "${APP_DETECTED_MODELS[@]}"; do
            [ -z "$app_m" ] && continue
            MODEL_ALIASES_YAML="${MODEL_ALIASES_YAML}    \"${app_m}\": \"${TARGET_VISUAL}\"\n"
        done

        cat << EO_BASE > "$TMP_CONFIG"
general_settings:
  store_model_in_db: false

litellm_settings:
  drop_params: true
  turn_off_message_logging: true
  suppress_debug_info: true
  set_verbose: false
  default_max_tokens: 4096
  webhook_url: "http://${PREFIXO_CONTAINER}_n8n:5678/webhook/litellm-falhas"
  failure_callback: ["webhook"]
  model_alias_map:
$(printf "%b" "$MODEL_ALIASES_YAML")
router_settings:
  num_retries: 2
  timeout: 30
  model_alias_map:
$(printf "%b" "$MODEL_ALIASES_YAML")
  fallbacks:
    - {"*": $FALLBACK_JSON}

model_list:
EO_BASE

        echo "$PAYLOADS_TOTAIS" | jq -r --arg target "$TARGET_MODEL" '
          unique_by(.ID) |
          def litellm_provider: if .Provider == "google" then "gemini" else .Provider end;
          def full_id: (litellm_provider) as $lp | (if (.ID | startswith($lp + "/")) then .ID else "\($lp)/\(.ID)" end);
          def provider_weight:
            if full_id == $target then "0_target"
            elif .Provider == "ollama" then "1_ollama"
            elif .Provider == "anthropic" then "2_anthropic"
            elif .Provider == "deepseek" then "3_deepseek"
            elif .Provider == "google" or .Provider == "gemini" then "4_gemini"
            elif .Provider == "openai" then "5_openai"
            else "6_openrouter" end;
          sort_by(provider_weight, .ID) |
          .[] |
          def free_label: if .Provider == "ollama" then " (local)" elif .Free then " (free)" else "" end;
          def visual_name: "\(.ID)\(free_label)";
          def api_base_entry: if .Provider == "ollama" and .ApiBase then "\n      api_base: \(.ApiBase)" else "" end;
          def openrouter_capping: if .Provider == "openrouter" then "\n      max_tokens: 4096" else "" end;

          "  - model_name: \(visual_name | tojson)\n    litellm_params:\n      model: \(full_id)\(api_base_entry)\(openrouter_capping)\n    model_info:\n      id: \(.ID)\n      name: \(visual_name | tojson)\n      mode: chat\n      description: \(.Description | tojson)\n      tags: \([(.Category | split(", ")), (if .Free then "grátis" else "pago" end)] | flatten | unique | tojson)"
        ' >> "$TMP_CONFIG"
        
        if ! grep -q "^model_list:" "$TMP_CONFIG" || [ "$(grep -c "model_name:" "$TMP_CONFIG")" -eq 0 ]; then
            echo "  ↳ [ERRO CRÍTICO AI GATEWAY] Geração do model_list falhou (jq retornou vazio/erro). Abortando gravação para não corromper o config em produção." >&2
            rm -f "$TMP_CONFIG"
            return 1
        fi

        local DEST_CONFIG="$TARGET_DIR_LITE/volumes/litellm_data/config.yaml"
        if [ -f "$DEST_CONFIG" ] && cmp -s "$TMP_CONFIG" "$DEST_CONFIG" 2>/dev/null; then
            echo "  ↳ [IDEMPOTÊNCIA AI GATEWAY] Catálogo LiteLLM e aliases já estão 100% atualizados. Nenhuma alteração detectada."
            rm -f "$TMP_CONFIG" 2>/dev/null || true
        else
            mv "$TMP_CONFIG" "$DEST_CONFIG"
            chmod 644 "$DEST_CONFIG" 2>/dev/null || true
            docker restart ${PREFIXO_CONTAINER}_litellm > /dev/null 2>&1 || true
            echo "  ↳ [CONFIGURANDO AI GATEWAY] Catálogo LiteLLM atualizado e serviço reiniciado."
        fi

        # 5. SINCRONIZAÇÃO EM CASCATA: N8N AI ASSISTANT
        if [ "$(docker inspect -f '{{.State.Running}}' ${PREFIXO_CONTAINER}_n8n 2>/dev/null)" = "true" ]; then
            local N8N_MODEL_ATUAL
            N8N_MODEL_ATUAL=$(docker exec -i ${PREFIXO_CONTAINER}_n8n node -e "console.log(process.env.N8N_INSTANCE_AI_MODEL || '')" 2>/dev/null || true)
            local TARGET_N8N="${TARGET_MODEL:-gpt-4.1}"
            if [ "$N8N_MODEL_ATUAL" = "$TARGET_N8N" ] || [ "$N8N_MODEL_ATUAL" = "gpt-4.1" ]; then
                echo "  ↳ [IDEMPOTÊNCIA AI GATEWAY] Modelo n8n AI Assistant já pareado com a malha (${N8N_MODEL_ATUAL})."
            else
                echo "  ↳ [CONFIGURANDO AI GATEWAY] Pareando modelo no n8n AI Assistant -> ${TARGET_N8N}..."
                local local_env="${TARGET_DIR_LITE}/.env"
                if [ -f "$local_env" ]; then
                    if grep -q '^N8N_INSTANCE_AI_MODEL=' "$local_env"; then
                        sed -i "s/^N8N_INSTANCE_AI_MODEL=.*/N8N_INSTANCE_AI_MODEL=${TARGET_N8N}/" "$local_env" 2>/dev/null || true
                    fi
                fi
                echo "  ↳ Modelo n8n AI Assistant sincronizado com sucesso."
            fi
        fi
    fi
}

provision_infra() {
    local target_dir="${1:-${TARGET_DIR:-/opt/daemind}}"
    mkdir -p "$target_dir/volumes/litellm_data"
    sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
    cat << 'EOF' | sudo tee /etc/dnsmasq.d/1ia.conf > /dev/null
# IPSET ALLOWED DOMAINS (BIG 5 AI GATEWAY)
ipset=/api.openai.com/ALLOWED_DOMAINS
ipset=/openai.azure.com/ALLOWED_DOMAINS
ipset=/cognitiveservices.azure.com/ALLOWED_DOMAINS
ipset=/api.anthropic.com/ALLOWED_DOMAINS
ipset=/generativelanguage.googleapis.com/ALLOWED_DOMAINS
ipset=/aiplatform.googleapis.com/ALLOWED_DOMAINS
ipset=/www.googleapis.com/ALLOWED_DOMAINS
ipset=/api.deepseek.com/ALLOWED_DOMAINS
ipset=/openrouter.ai/ALLOWED_DOMAINS
EOF
    if [ "${USE_TAILSCALE:-false}" = "true" ]; then
        sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 4000 -j ACCEPT 2>/dev/null || true
    else
        sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 4000 -j ACCEPT 2>/dev/null || true
    fi
    echo "➜ [INFRA AI GATEWAY] Estrutura, DNS e firewall perimetral para LiteLLM Gateway validados."
}

build_structure() { :; }
provision_db() { :; }
inject_caddy_routes() { :; }
remove_caddy_routes() { :; }
inject_dashboard_card() { :; }
remove_dashboard_card() { :; }
disable() { :; }
start_container() { :; }
wait_readiness() { :; }
provision_user() { :; }
render_forensic_report() { :; }
audit_health() { :; }
get_version() { echo "Nativo"; }

# ===============================================================================
# Roteador CLI de Ações
# ===============================================================================
ACTION="${2:-all}"
case "$ACTION" in
    collect_wizard_inputs|collect_inputs|wizard_prompt)
        collect_wizard_inputs
        ;;
    collect_wizard_inputs_tui|collect_inputs_tui|wizard_tui)
        collect_wizard_inputs_tui
        ;;
    build_envs|build_env)
        build_envs
        ;;
    provision_infra|provision_structure)
        provision_infra
        ;;
    sync|sync_models)
        sync_models
        ;;
    all)
        sync_models
        ;;
    *)
        ;;
esac
