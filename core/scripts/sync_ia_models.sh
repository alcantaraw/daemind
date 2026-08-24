#!/bin/bash
# Sincronização Diária: Catálogos Big 5 -> Banco de Dados LiteLLM
# set -e

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "${SCRIPT_DIR}/config/.env" ]; then
    set -a; source "${SCRIPT_DIR}/config/.env"; set +a
elif [ -f "${SCRIPT_DIR}/../.env" ]; then
    set -a; source "${SCRIPT_DIR}/../.env"; set +a
fi

LITELLM_URL="http://127.0.0.1:4000"
LOG_ERR="/tmp/sync_ia_errors.log"
> "$LOG_ERR"
chmod 777 $LOG_ERR

echo "=== [SRE COMPATIBILITY ENGINE] Iniciando Varredura e Matchmaking ==="

# ===============================================================================
# 1. EXTRAÇÃO ATÔMICA (Descoberta do modelo do Postiz/Chatwoot)
# ===============================================================================
POSTIZ_MODEL=""
if [ "$(docker inspect -f '{{.State.Running}}' ${PREFIXO_CONTAINER}_postiz 2>/dev/null)" = "true" ]; then
    POSTIZ_MODEL=$(docker exec -i ${PREFIXO_CONTAINER}_postiz grep -oE "model: *['\"]gpt-[0-9a-zA-Z.-]+['\"]" /app/libraries/nestjs-libraries/src/openai/openai.service.ts 2>/dev/null | head -n 1 | grep -oE "gpt-[0-9a-zA-Z.-]+" || true)
fi

[ -z "$POSTIZ_MODEL" ] && POSTIZ_MODEL="gpt-4.1"
echo "  ↳ Modelo Postiz detectado em runtime: $POSTIZ_MODEL"

if [ "$(docker inspect -f '{{.State.Health.Status}}' ${PREFIXO_CONTAINER}_chatwoot 2>/dev/null)" = "healthy" ]; then
    CW_MODEL_ATUAL=$(docker exec -i ${PREFIXO_CONTAINER}_chatwoot bundle exec rails runner "
      c = InstallationConfig.find_by(name: 'OPENAI_MODEL')
      print c.value if c
    " 2>/dev/null || true)

    if [ "$CW_MODEL_ATUAL" = "$POSTIZ_MODEL" ]; then
        echo "  ↳ [IDEMPOTÊNCIA] Modelo Chatwoot CRM já configurado ($POSTIZ_MODEL)."
    else
        echo "  ↳ [CONFIGURANDO] Atualizando modelo no Chatwoot CRM -> $POSTIZ_MODEL..."
        docker exec -i ${PREFIXO_CONTAINER}_chatwoot bundle exec rails runner "
          c = InstallationConfig.find_or_initialize_by(name: 'OPENAI_MODEL')
          c.value = '$POSTIZ_MODEL'
          c.save!
        " > /dev/null 2>&1 || true
    fi
fi

# ===============================================================================
# 2. INTEGRAÇÃO ATÔMICA DOS CATÁLOGOS (Busca os Modelos nas APIs)
# ===============================================================================
PAYLOADS_TOTAIS="[]"
PAYLOAD_OPENAI="[]"
PAYLOAD_ANTHROPIC="[]"
PAYLOAD_GOOGLE="[]"
PAYLOAD_DEEPSEEK="[]"

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
API_KEY_GOOGLE="${GEMINI_API_KEY:-$GOOGLE_API_KEY}"
if [ -n "$API_KEY_GOOGLE" ]; then
    PAYLOAD_GOOGLE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$API_KEY_GOOGLE" 2>>"$LOG_ERR" | jq -c --arg free_only "${FREE_GEMINI:-0}" '
    def clean_id: .name | sub("^models/"; "");
    def extract_version: clean_id | if test("[0-9]+\\.[0-9]+") then (capture("(?<v>[0-9]+\\.[0-9]+)").v | tonumber) elif test("-[0-9]+-") then (capture("-(?<v>[0-9]+)-").v | tonumber) elif test("-[0-9]+$") then (capture("-(?<v>[0-9]+)$").v | tonumber) else 1.0 end;
    def extract_tier: clean_id | sub("^(gemini|gemma)-[0-9]+(\\.[0-9]+)?-?"; "") | sub("-(preview|001|002|customtools).*$"; "") | if . == "" then "base" else . end;
    def canonical_key: clean_id | sub("-(preview|001|002)$"; "") | sub("-preview-.*$"; "");

    .models
    | map(select((.supportedGenerationMethods | contains(["generateContent"])) and (.name | test("embedding|lyria|robotics|aqa|computer-use|antigravity|deep-research|imagen|veo|tts|-latest$|nano-banana") | not)))

    # SRE GUARDRAIL: Filtro rigoroso de gratuidade se o operador optou por custo zero no Google
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
        Alias: true
    })' || echo "[]")
    append_payloads "$PAYLOAD_OPENROUTER"
fi

# 2.6 OLLAMA (Modelos Locais On-Premise)
PAYLOAD_OLLAMA="[]"
OLLAMA_URL="http://${PREFIXO_CONTAINER}_ollama:11434"
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

# ===============================================================================
# 3. SRE HEALTH PROBER & RANKING DE FALLBACK (Zero-Hardcode & Auto-Healing)
# ===============================================================================
echo "➜ [SRE HEALTH PROBER] Testando e ranqueando a saúde dos modelos candidatos em tempo real..."

TARGET_MODEL=""
HEALTHY_FALLBACKS=()

probe_openrouter_model() {
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

# Se temos chaves pagas prioritárias (Gemini, DeepSeek, Anthropic, OpenAI):
if [ -n "${GEMINI_API_KEY:-}" ] && [ "$PAYLOAD_GOOGLE" != "[]" ]; then
    EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r 'map(select(.ID | test("-flash$"))) | .[0].ID // empty')
    [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r '.[0].ID // empty')
    [ -n "$EXTRACTED" ] && TARGET_MODEL="gemini/${EXTRACTED}"

elif [ -n "${DEEPSEEK_API_KEY:-}" ] && [ "$PAYLOAD_DEEPSEEK" != "[]" ]; then
    EXTRACTED=$(echo "$PAYLOAD_DEEPSEEK" | jq -r '[.[] | select(.ID | test("flash"))] | sort_by(.Created) | last.ID // empty')
    [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_DEEPSEEK" | jq -r '.[0].ID // empty')
    [ -n "$EXTRACTED" ] && TARGET_MODEL="deepseek/${EXTRACTED}"

elif [ -n "${ANTHROPIC_API_KEY:-}" ] && [ "$PAYLOAD_ANTHROPIC" != "[]" ]; then
    EXTRACTED=$(echo "$PAYLOAD_ANTHROPIC" | jq -r '[.[] | select(.ID | test("sonnet"))] | sort_by(.Created) | last.ID // empty')
    [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_ANTHROPIC" | jq -r '.[0].ID // empty')
    [ -n "$EXTRACTED" ] && TARGET_MODEL="anthropic/${EXTRACTED}"

elif [ -n "${OPENAI_API_KEY:-}" ] && [ "$PAYLOAD_OPENAI" != "[]" ]; then
    EXTRACTED=$(echo "$PAYLOAD_OPENAI" | jq -r '[.[] | select(.ID | test("luna"))] | sort_by(.Created) | last.ID // empty')
    [ -z "$EXTRACTED" ] && EXTRACTED=$(echo "$PAYLOAD_OPENAI" | jq -r '.[0].ID // empty')
    [ -n "$EXTRACTED" ] && TARGET_MODEL="openai/${EXTRACTED}"

elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
    # Varre TODOS os modelos do OpenRouter em paralelo com medição de latência
    CANDIDATES=$(echo "$PAYLOADS_TOTAIS" | jq -r '[.[] | select(.Provider == "openrouter")] | .[].ID')
    TMP_PROBE_DIR=$(mktemp -d)

    for cand in $CANDIDATES; do
        (
            PROBE_ID="$cand"
            if [ "$cand" != "openrouter/free" ] && ! echo "$cand" | grep -q ":free"; then
                PROBE_ID="${cand}:free"
            fi
            START_TS=$(date +%s%N 2>/dev/null | cut -b1-13)
            [ -z "$START_TS" ] && START_TS=$(date +%s)
            RESP=$(curl -s -m 5 "https://openrouter.ai/api/v1/chat/completions" \
                -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
                -H "Content-Type: application/json" \
                -d "{\"model\": \"${PROBE_ID}\", \"messages\": [{\"role\": \"user\", \"content\": \"1\"}], \"max_tokens\": 1}" 2>/dev/null || echo "")
            END_TS=$(date +%s%N 2>/dev/null | cut -b1-13)
            [ -z "$END_TS" ] && END_TS=$(date +%s)
            LATENCY=$(( END_TS - START_TS ))
            [ "$LATENCY" -lt 0 ] && LATENCY=0

            if echo "$RESP" | grep -q '"choices"'; then
                printf "%06d:%s\n" "$LATENCY" "$cand" > "${TMP_PROBE_DIR}/${cand//\//_}.ok"
            fi
        ) &
    done
    wait

    # Classifica todos os modelos saudáveis por menor latência (ms)
    if ls "${TMP_PROBE_DIR}"/*.ok >/dev/null 2>&1; then
        while IFS=: read -r lat_raw c_name || [ -n "$lat_raw" ]; do
            [ -z "$c_name" ] && continue
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
        HEALTHY_IDS_JSON=$(printf '%s\n' "${HEALTHY_FALLBACKS[@]}" | jq -R . | jq -s .)
        PAYLOADS_TOTAIS=$(echo "$PAYLOADS_TOTAIS" | jq -c --argjson ok "$HEALTHY_IDS_JSON" '
            map(select((.Provider != "openrouter") or (.ID as $id | $ok | contains([$id]))))
        ')
    fi
fi

[ -z "$TARGET_MODEL" ] && TARGET_MODEL="openrouter/free"
echo "  ↳ Target Model eleito por auditoria de saúde: $TARGET_MODEL"
echo "  ↳ Fallback Ranking: ${HEALTHY_FALLBACKS[*]:-openrouter/free}"

# ===============================================================================
# 4. FORJA DO YAML (Gravação Definitiva no LiteLLM)
# ===============================================================================
TOTAL=$(echo "$PAYLOADS_TOTAIS" | jq length)

if [ "$TOTAL" -gt 0 ]; then
    mkdir -p ./volumes/litellm_data
    TMP_CONFIG=$(mktemp)

    # Resolve o target visual completo (incluindo (free) ou (local) se aplicável)
    TARGET_VISUAL=$(echo "$PAYLOADS_TOTAIS" | jq -r --arg tm "$TARGET_MODEL" '
        def litellm_provider: if .Provider == "google" then "gemini" else .Provider end;
        def full_id: (litellm_provider) as $lp | (if (.ID | startswith($lp + "/")) then .ID else "\($lp)/\(.ID)" end);
        [.[] | select(full_id == $tm or .ID == $tm)] | first | 
        if . == null then $tm else
          "\(.ID)\(if .Provider == "ollama" then " (local)" elif .Free then " (free)" else "" end)"
        end
    ' 2>/dev/null || echo "$TARGET_MODEL")

    [ -z "$TARGET_VISUAL" ] && TARGET_VISUAL="$TARGET_MODEL"

    # Constrói array JSON com o ranking de fallbacks saudáveis
    FALLBACK_JSON=$(printf '%s\n' "${HEALTHY_FALLBACKS[@]}" | jq -R . 2>/dev/null | jq -s --arg tm "$TARGET_VISUAL" '([$tm] + .) | unique | map(select(length > 0))' 2>/dev/null || echo "[\"$TARGET_VISUAL\"]")
    [ "$FALLBACK_JSON" = "[]" ] && FALLBACK_JSON="[\"$TARGET_VISUAL\"]"

    cat << EO_BASE > "$TMP_CONFIG"
general_settings:
  store_model_in_db: false

litellm_settings:
  drop_params: true
  turn_off_message_logging: true
  set_verbose: false
  webhook_url: "http://${PREFIXO_CONTAINER}_n8n:5678/webhook/litellm-falhas"
  failure_callback: ["webhook"]
  model_alias_map:
    "$POSTIZ_MODEL": "$TARGET_VISUAL"
    "gpt-4.1": "$TARGET_VISUAL"
    "gpt-4": "$TARGET_VISUAL"
    "gpt-4o": "$TARGET_VISUAL"
    "gpt-4o-mini": "$TARGET_VISUAL"
    "gpt-3.5-turbo": "$TARGET_VISUAL"
    "openrouter/free": "$TARGET_VISUAL"
 
router_settings:
  num_retries: 2
  timeout: 30
  model_alias_map:
    "$POSTIZ_MODEL": "$TARGET_VISUAL"
    "gpt-4.1": "$TARGET_VISUAL"
    "gpt-4": "$TARGET_VISUAL"
    "gpt-4o": "$TARGET_VISUAL"
    "gpt-4o-mini": "$TARGET_VISUAL"
    "gpt-3.5-turbo": "$TARGET_VISUAL"
    "openrouter/free": "$TARGET_VISUAL"
  fallbacks:
    - {"*": $FALLBACK_JSON}

model_list:
EO_BASE

    echo "$PAYLOADS_TOTAIS" | jq -r --arg target "$TARGET_MODEL" '
      unique_by(.ID) |
      def litellm_provider: if .Provider == "google" then "gemini" else .Provider end;
      def full_id: (litellm_provider) as $lp | (if (.ID | startswith($lp + "/")) then .ID else "\($lp)/\(.ID)" end);
      def provider_weight:
        if full_id == $target or .ID == $target then "0_target"
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

      "  - model_name: \(visual_name | tojson)\n    litellm_params:\n      model: \(full_id)\(api_base_entry)\n    model_info:\n      id: \(.ID)\n      name: \(visual_name | tojson)\n      mode: chat\n      description: \(.Description | tojson)\n      tags: \([(.Category | split(", ")), (if .Free then "grátis" else "pago" end)] | flatten | unique | tojson)"
    ' >> "$TMP_CONFIG"

    if cmp -s "$TMP_CONFIG" ./volumes/litellm_data/config.yaml 2>/dev/null; then
        echo "  ↳ [IDEMPOTÊNCIA] Catálogo LiteLLM e aliases já estão 100% atualizados. Nenhuma alteração detectada."
        rm -f "$TMP_CONFIG" 2>/dev/null || true
    else
        mv "$TMP_CONFIG" ./volumes/litellm_data/config.yaml
        chmod 644 ./volumes/litellm_data/config.yaml 2>/dev/null || true
        docker restart ${PREFIXO_CONTAINER}_litellm > /dev/null 2>&1 || true
        echo "  ↳ [CONFIGURANDO] Catálogo LiteLLM atualizado e serviço reiniciado."
    fi
fi
