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
        (.id | test("openrouter/free|content-safety|guardrail|lyria|embedding|moderation") | not)
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

# ===============================================================================
# 3. ROTEADOR INTELIGENTE (MATCHMAKING DINÂMICO & À PROVA DE FUTURO)
# ===============================================================================
TARGET_MODEL="openrouter/free"

if [ -n "${GEMINI_API_KEY:-}" ] && [ "$PAYLOAD_GOOGLE" != "[]" ]; then
    EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r 'map(select(.ID | test("-flash$"))) | .[0].ID // empty')
    if [ -z "$EXTRACTED" ]; then
        EXTRACTED=$(echo "$PAYLOAD_GOOGLE" | jq -r 'map(select(.ID | test("-flash-lite$"))) | .[0].ID // empty')
    fi
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
    TARGET_MODEL="openrouter/free"
fi

echo "  ↳ Target Model resolvido dinamicamente: $TARGET_MODEL"

# ===============================================================================
# 4. FORJA DO YAML (Gravação Definitiva no LiteLLM)
# ===============================================================================
TOTAL=$(echo "$PAYLOADS_TOTAIS" | jq length)

if [ "$TOTAL" -gt 0 ]; then
    mkdir -p ./volumes/litellm_data
    TMP_CONFIG=$(mktemp)

    cat << EO_BASE > "$TMP_CONFIG"
general_settings:
  store_model_in_db: false
  model_alias_map:
    "$POSTIZ_MODEL": "$TARGET_MODEL"

litellm_settings:
  drop_params: true
  turn_off_message_logging: true
  set_verbose: false
  webhook_url: "http://${PREFIXO_CONTAINER}_n8n:5678/webhook/litellm-falhas"
  failure_callback: ["webhook"]
 
router_settings:
  num_retries: 2
  timeout: 30
  fallbacks:
    - {"*": ["openrouter/free"]}

model_list:
EO_BASE

    echo "$PAYLOADS_TOTAIS" | jq -r --arg target "$TARGET_MODEL" '
      unique_by(.ID) |
      def litellm_provider: if .Provider == "google" then "gemini" else .Provider end;
      def full_id: (litellm_provider) as $lp | (if (.ID | startswith($lp + "/")) then .ID else "\($lp)/\(.ID)" end);
      def provider_weight:
        if full_id == $target then "0_target"
        elif .Provider == "anthropic" then "1_anthropic"
        elif .Provider == "deepseek" then "2_deepseek"
        elif .Provider == "google" or .Provider == "gemini" then "3_gemini"
        elif .Provider == "openai" then "4_openai"
        else "5_openrouter" end;
      sort_by(provider_weight, .ID) |
      .[] |
      def free_label: if .Free then " (free)" else "" end;
      def visual_name: "\(.ID)\(free_label)";

      "  - model_name: \(visual_name | tojson)\n    litellm_params:\n      model: \(litellm_provider)/\(.ID)\n    model_info:\n      id: \(.ID)\n      name: \(visual_name | tojson)\n      mode: chat\n      description: \(.Description | tojson)\n      tags: \([(.Category | split(", ")), (if .Free then "grátis" else "pago" end)] | flatten | unique | tojson)"
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
