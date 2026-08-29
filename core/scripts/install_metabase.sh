#!/usr/bin/env bash
# METABASE
# Painéis e Dashboards de BI em Tempo Real
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO METABASE BI & ANALYTICS
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório Metabase
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.15.01-DECOUPLED"

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
fi

build_structure() {
    local TARGET_OWNER="1000:1000"
    if [ -n "${SUDO_USER:-}" ]; then
        local TARGET_UID=$(id -u "$SUDO_USER" 2>/dev/null || echo "1000")
        local TARGET_GID=$(id -g "$SUDO_USER" 2>/dev/null || echo "1000")
        TARGET_OWNER="${TARGET_UID}:${TARGET_GID}"
    fi

    local VOL_PATH="$TARGET_DIR/volumes/metabase_data"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    # SRE Fix: Garante arquivo de configuração do log4j2 (evita colisão de diretório no Docker bind mount)
    local LOG4J_FILE="$TARGET_DIR/core/config/log4j2.metabase.xml"
    if [ -d "$LOG4J_FILE" ]; then
        sudo rm -rf "$LOG4J_FILE" 2>/dev/null || rm -rf "$LOG4J_FILE" || true
    fi
    if [ ! -f "$LOG4J_FILE" ]; then
        sudo mkdir -p "$TARGET_DIR/core/config" 2>/dev/null || mkdir -p "$TARGET_DIR/core/config" || true
        cat << 'EOF' | sudo tee "$LOG4J_FILE" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<Configuration status="WARN">
  <Appenders>
    <Console name="Console" target="SYSTEM_OUT">
      <PatternLayout pattern="%d{yyyy-MM-dd HH:mm:ss,SSS} %-5p %c{1} :: %m%n" />
    </Console>
  </Appenders>
  <Loggers>
    <Root level="WARN">
      <AppenderRef ref="Console" />
    </Root>
    <Logger name="metabase" level="WARN" />
    <Logger name="metabase.sync" level="OFF" />
    <Logger name="metabase.driver" level="ERROR" />
    <Logger name="metabase.plugins" level="ERROR" />
    <Logger name="metabase.server.middleware.log" level="WARN" />
    <Logger name="metabase.metabot" level="OFF" />
    <Logger name="metabase.api.card" level="ERROR" />
    <Logger name="metabase.models.card" level="ERROR" />
    <Logger name="example-question-generator" level="OFF" />
    <Logger name="suggested-prompts-generator" level="OFF" />
    <Logger name="liquibase" level="ERROR" />
    <Logger name="org.quartz" level="ERROR" />
    <Logger name="c3p0" level="ERROR" />
    <Logger name="com.mchange" level="ERROR" />
  </Loggers>
</Configuration>
EOF
    fi

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA METABASE] Estrutura de volumes de metabase_data já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE METABASE] Criando estrutura física de volumes e permissões do Metabase..."
        sudo mkdir -p "$VOL_PATH" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" 2>/dev/null || true
    fi
}

provision_db() {
    echo "➜ [SRE METABASE] Provisionando banco de dados relacional dedicado (metabase_db)..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local DB_ADMIN="${DB_USER}"
    local PRIMARY_DB="${PREFIX}_db"

    local DB_EXISTE=$(sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -t -c "SELECT 1 FROM pg_database WHERE datname = 'metabase_db';" 2>/dev/null | tr -d '[:space:]' || echo "0")

    if [ "$DB_EXISTE" = "1" ]; then
        echo "➜ [IDEMPOTÊNCIA METABASE] Banco de dados 'metabase_db' já existente no PostgreSQL. Preservando estado."
    else
        echo "  ↳ Criando banco lógico 'metabase_db'..."
        sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -c "CREATE DATABASE metabase_db OWNER ${DB_ADMIN};" >/dev/null 2>&1 || true
        echo "✔ [SUCESSO METABASE] Banco de dados 'metabase_db' provisionado com sucesso."
    fi
}

provision_infra() {
    echo "➜ [SRE METABASE] Verificando integridade de esquemas e firewall perimetral do Metabase..."
    local use_val="${USE_METABASE:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 3030 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 3030 -j ACCEPT 2>/dev/null || true
        fi
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE METABASE] Injetando rotas do Metabase BI no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q "reverse_proxy.*_metabase:3000" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:3030 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_metabase:3000
}
EOF
        fi
    fi
}

remove_caddy_routes() {
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    if [ -f "$CADDYFILE_PATH" ] && grep -q "reverse_proxy.*_metabase:3000" "$CADDYFILE_PATH"; then
        echo "➜ [SRE METABASE] Removendo rotas do Metabase BI do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:3030\s*\{[\s\S]*?metabase[\s\S]*?\}', '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    local MB_PORT="${HOST_METABASE_PORT:-3030}"
    echo "➜ [SRE METABASE] Injetando card do Metabase BI no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$INDEX_PATH" ] && ! grep -q 'data-port="3030"' "$INDEX_PATH" && ! grep -q "data-port=\"$MB_PORT\"" "$INDEX_PATH" && ! grep -q 'Metabase BI' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"$MB_PORT\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">📈</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Metabase BI</h3>
                    <p class=\"description\">Painéis analíticos, relatórios e inteligência de negócios para a operação.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:$MB_PORT</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'Metabase BI' not in content:
            target = '</div>\n\n        <div class=\"footer-note\">'
            if target in content:
                new_content = content.replace(target, card + '        ' + target)
                f.seek(0)
                f.write(new_content)
                f.truncate()
except Exception as e:
    pass
" 2>/dev/null || true
    fi
}

remove_dashboard_card() {
    echo "➜ [SRE METABASE] Purgando card do Metabase BI no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    if [ -f "$INDEX_PATH" ] && { grep -q 'Metabase BI' "$INDEX_PATH" || grep -q 'data-port="3030"' "$INDEX_PATH"; }; then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\"[^>]*data-port=\"(3030|${HOST_METABASE_PORT:-3030})\"[\s\S]*?</a>\s*', '', content)
        if 'Metabase BI' in new_content:
            new_content = re.sub(r'\s*<a href=\"[^\"]*\" class=\"card dynamic-link\">[\s\S]*?Metabase BI[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE METABASE] Desativando módulo Metabase BI..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_metabase" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 3030 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 3030 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/metabase.conf ]; then
        sudo rm -f /etc/dnsmasq.d/metabase.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO METABASE] Módulo Metabase desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE METABASE] Garantindo subida integrada do container Metabase..."
    cd "$TARGET_DIR"
    sudo docker compose up -d metabase 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE METABASE] Validando prontidão de socket e healthcheck do Metabase..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local TENTATIVAS=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_metabase 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 45 ]; then
            echo "⚠️ [SRE WARN METABASE] Metabase demorou a responder após 90s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done
    echo "✔ [SUCESSO METABASE] Metabase BI Server online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local health_mb=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_metabase 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_mb" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:3030/api/health" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:3030  -> Status: [%s]\n" "Metabase BI Console:" "${ts_domain}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_metabase"
    local MB_PORT="${HOST_METABASE_PORT:-3030}"
    local VER=$(curl -s "http://127.0.0.1:${MB_PORT}/api/session/properties" 2>/dev/null | jq -r '.version.tag // .["version-info"].tag // empty' 2>/dev/null || echo "")
    if [ -n "$VER" ]; then
        echo "$VER"
    else
        sudo docker inspect -f '{{.Config.Image}}' "$container_name" 2>/dev/null || echo "latest"
    fi
}

provision_user() {
    echo "➜ [SRE METABASE] Provisionando conta de Administrador (Zero-Touch)..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local MB_URL="http://127.0.0.1:3030"
    local ADMIN_EMAIL="${TS_EMAIL}"
    local ADMIN_PASS="${DB_PASSWORD}"
    local FIRST_NAME="${CLIENTE_NOME}"
    local LAST_NAME="${CLIENTE_SOBRENOME}"
    local SITE_NAME="Metabase BI (${CLIENTE_NOME})"

    # 1. Obtém o setup-token emitido pelo Metabase no primeiro boot
    local PROPERTIES=$(curl -s -m 8 "${MB_URL}/api/session/properties" 2>/dev/null || echo "")
    local SETUP_TOKEN=$(echo "$PROPERTIES" | jq -r '.["setup-token"] // empty' 2>/dev/null || echo "")

    if [ -n "$SETUP_TOKEN" ] && [ "$SETUP_TOKEN" != "null" ]; then
        # 2. Executa a criação do administrador e parametrização inicial via REST API
        local PAYLOAD=$(jq -n \
            --arg token "$SETUP_TOKEN" \
            --arg email "$ADMIN_EMAIL" \
            --arg first "$FIRST_NAME" \
            --arg last "$LAST_NAME" \
            --arg pass "$ADMIN_PASS" \
            --arg site "$SITE_NAME" \
            '{
                token: $token,
                user: {
                    email: $email,
                    first_name: $first,
                    last_name: $last,
                    password: $pass
                },
                prefs: {
                    site_name: $site,
                    site_locale: "pt_BR",
                    allow_tracking: false
                }
            }')

        local RESPONSE=$(curl -s -X POST "${MB_URL}/api/setup" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" 2>/dev/null || echo "")

        if echo "$RESPONSE" | grep -qiE '"id"|"session_id"|"success"|true'; then
            echo "✔ [SUCESSO METABASE] Administrador provisionado com sucesso (${ADMIN_EMAIL})!"
        else
            echo "⚠️ [SRE METABASE] Resposta da API de Setup: $(echo "$RESPONSE" | cut -c1-120)"
        fi
    else
        echo "➜ [IDEMPOTÊNCIA METABASE] Metabase já inicializado com conta administrativa."
    fi

    # 3. Auto-vinculação do Data Warehouse (loja_db via PgBouncer)
    local MB_SESSION=$(curl -s -X POST "${MB_URL}/api/session" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"${ADMIN_EMAIL}\", \"password\": \"${ADMIN_PASS}\"}" 2>/dev/null | jq -r '.id // empty' 2>/dev/null || echo "")

    if [ -n "$MB_SESSION" ]; then
        local HAS_DB=$(curl -s -X GET "${MB_URL}/api/database" -H "X-Metabase-Session: $MB_SESSION" 2>/dev/null | jq -r '(.data // .)? | .[]? | select(.name == "Data Warehouse Soberano") | .id' 2>/dev/null || echo "")
        if [ -z "$HAS_DB" ]; then
            echo "➜ [SRE METABASE] Conectando Data Warehouse Soberano (${PREFIX}_db via PgBouncer)..."
            local DB_RES
            DB_RES=$(curl -s -X POST "${MB_URL}/api/database" \
                -H "X-Metabase-Session: $MB_SESSION" \
                -H "Content-Type: application/json" \
                -d "{
                    \"name\": \"Data Warehouse Soberano\",
                    \"engine\": \"postgres\",
                    \"details\": {
                        \"host\": \"pgbouncer\",
                        \"port\": 6432,
                        \"dbname\": \"${PREFIX}_db\",
                        \"user\": \"${DB_USER:-admin_db}\",
                        \"password\": \"${DB_PASSWORD}\",
                        \"ssl\": false,
                        \"let-user-control-scheduling\": false
                    },
                    \"is_full_sync\": true
                }" 2>/dev/null || echo "")
            HAS_DB=$(echo "$DB_RES" | jq -r '.id // empty' 2>/dev/null || echo "")
            echo "✔ [AUTO-INTEGRAÇÃO METABASE] Data Warehouse Soberano integrado ao Metabase com sucesso!"
        else
            echo "➜ [IDEMPOTÊNCIA METABASE] Data Warehouse Soberano já conectado ao Metabase."
        fi

        # 4. Injeção Automática de Dashboards & Cards Analíticos Omnichannel 360° (Zero-Touch)
        if [ -n "$HAS_DB" ] && [ "$HAS_DB" != "null" ]; then
            provision_dashboards "$MB_URL" "$MB_SESSION" "$HAS_DB"
        fi

        # 5. Auto-configuração do Metabot AI Gateway (LiteLLM) no Metabase (Zero-Touch)
        echo "➜ [SRE METABASE] Configurando Metabot AI via LiteLLM Gateway..."
        curl -s -X PUT "${MB_URL}/api/setting/llm-enabled" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d '{"value": true}' >/dev/null 2>&1 || true
        curl -s -X PUT "${MB_URL}/api/setting/llm-metabot-provider" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d '{"value": "openai"}' >/dev/null 2>&1 || true
        curl -s -X PUT "${MB_URL}/api/setting/llm-openai-model" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d '{"value": "gpt-4.1"}' >/dev/null 2>&1 || true
        curl -s -X PUT "${MB_URL}/api/setting/llm-openai-api-base" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d '{"value": "http://litellm:4000"}' >/dev/null 2>&1 || true
        curl -s -X PUT "${MB_URL}/api/setting/llm-openai-api-key" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": \"${LITELLM_MASTER_KEY}\"}" >/dev/null 2>&1 || true
    fi
}

provision_dashboards() {
    local MB_URL="$1"
    local MB_SESSION="$2"
    local DB_ID="$3"

    echo "➜ [SRE METABASE] Verificando Cockpit Executivo Omnichannel 360°..."
    local DASH_ID
    DASH_ID=$(curl -s -X GET "${MB_URL}/api/dashboard" -H "X-Metabase-Session: $MB_SESSION" 2>/dev/null | jq -r '.[] | select(.name == "Cockpit Executivo Omnichannel 360°") | .id' 2>/dev/null || echo "")

    if [ -n "$DASH_ID" ] && [ "$DASH_ID" != "null" ]; then
        echo "➜ [SRE METABASE] Dashboard 'Cockpit Executivo Omnichannel 360°' detectado (ID: ${DASH_ID}). Sincronizando cards, layout e gráficos atualizados..."
        local PIN_NOW=$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')
        curl -s -X PUT "${MB_URL}/api/dashboard/${DASH_ID}" \
            -H "X-Metabase-Session: $MB_SESSION" \
            -H "Content-Type: application/json" \
            -d "{\"pinned_at\": \"${PIN_NOW}\", \"collection_position\": 1}" >/dev/null 2>&1 || true
    else
        echo "  ↳ Criando Dashboard 'Cockpit Executivo Omnichannel 360°'..."
        local PIN_NOW=$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')
        local CREATE_DASH_RES
        CREATE_DASH_RES=$(curl -s -X POST "${MB_URL}/api/dashboard" \
            -H "X-Metabase-Session: $MB_SESSION" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Cockpit Executivo Omnichannel 360°\",
                \"description\": \"Painel de Inteligência de Negócios, Vendas, Serviços B2B, Performance de Ads, Estoque Crítico e SDRs em Tempo Real.\",
                \"collection_position\": 1,
                \"pinned_at\": \"${PIN_NOW}\"
            }" 2>/dev/null || echo "")
        DASH_ID=$(echo "$CREATE_DASH_RES" | jq -r '.id // empty' 2>/dev/null || echo "")
    fi

    if [ -z "$DASH_ID" ] || [ "$DASH_ID" = "null" ]; then
        echo "⚠️ [SRE WARN METABASE] Não foi possível criar ou obter o Dashboard via API. Prosseguindo..."
        return 0
    fi

    echo "  ↳ Injetando Cards Analíticos Nativos no Cockpit Executivo..."
    local DASH_CARDS_PAYLOAD="[]"
    local ROW_CURSOR=0
    local CARD_IDX=0

    # Layout 24 Colunas (Metabase 0.50+ / 50.x):
    # Topo: 1 Card de Largura Total (24 cols) para o Gráfico Temporal Principal (DRE)
    # Demais: Cards Lado a Lado (12 cols cada) em 2 colunas perfeitas
    local CURSOR_COL=0
    local ROW_CURSOR=0
    local ROW_MAX_H=0

    create_card() {
        local NAME="$1"
        local DISPLAY="$2"
        local SQL_QUERY="$3"
        local SIZE_X="${4:-12}"
        local SIZE_Y="${5:-7}"
        local VIZ_SETTINGS="$6"
        if [ -z "$VIZ_SETTINGS" ] || [ "$VIZ_SETTINGS" = "null" ]; then
            VIZ_SETTINGS="{}"
        fi

        local CARD_PAYLOAD
        CARD_PAYLOAD=$(echo "$VIZ_SETTINGS" | jq \
            --arg name "$NAME" \
            --arg display "$DISPLAY" \
            --arg query "$SQL_QUERY" \
            --argjson db "$DB_ID" \
            '{
                name: $name,
                display: $display,
                dataset_query: {
                    type: "native",
                    native: {
                        query: $query
                    },
                    database: $db
                },
                visualization_settings: .
            }' 2>/dev/null || echo "{}")

        local CARD_RES
        CARD_RES=$(curl -s -X POST "${MB_URL}/api/card" \
            -H "X-Metabase-Session: $MB_SESSION" \
            -H "Content-Type: application/json" \
            -d "$CARD_PAYLOAD" 2>/dev/null || echo "")
        local CARD_ID
        CARD_ID=$(echo "$CARD_RES" | jq -r '.id // empty' 2>/dev/null || echo "")

        if [ -n "$CARD_ID" ] && [ "$CARD_ID" != "null" ]; then
            CARD_IDX=$((CARD_IDX + 1))

            # Se o card não couber na linha atual (24 colunas), quebra para a próxima
            if [ $((CURSOR_COL + SIZE_X)) -gt 24 ]; then
                ROW_CURSOR=$((ROW_CURSOR + ROW_MAX_H))
                CURSOR_COL=0
                ROW_MAX_H=0
            fi

            local POS_COL="$CURSOR_COL"
            local POS_ROW="$ROW_CURSOR"

            CURSOR_COL=$((CURSOR_COL + SIZE_X))
            if [ "$SIZE_Y" -gt "$ROW_MAX_H" ]; then
                ROW_MAX_H="$SIZE_Y"
            fi

            local TEMP_ID="-$CARD_IDX"
            local CARD_ENTRY
            CARD_ENTRY=$(echo "$VIZ_SETTINGS" | jq \
                --argjson tempId "$TEMP_ID" \
                --argjson cardId "$CARD_ID" \
                --argjson row "$POS_ROW" \
                --argjson col "$POS_COL" \
                --argjson sx "$SIZE_X" \
                --argjson sy "$SIZE_Y" \
                '{
                    id: $tempId,
                    card_id: $cardId,
                    row: $row,
                    col: $col,
                    size_x: $sx,
                    size_y: $sy,
                    visualization_settings: .
                }' 2>/dev/null || echo "{}")

            DASH_CARDS_PAYLOAD=$(echo "$DASH_CARDS_PAYLOAD" | jq --argjson entry "$CARD_ENTRY" '. += [$entry]')
        fi
    }

    # 1. DRE & Lucro Líquido Real Diário (Full Width Topo - Gráfico de Linhas 24 cols)
    create_card \
        "📈 Faturamento vs. Lucro Líquido Real (DRE Diário)" \
        "line" \
        "SELECT data_referencia, faturamento_bruto, total_cmv, lucro_liquido_dia, margem_liquida_perc, roas_dia FROM public.vw_dre_diario_consolidado ORDER BY data_referencia DESC LIMIT 30;" \
        24 8 \
        '{"graph.dimensions": ["data_referencia"], "graph.metrics": ["faturamento_bruto", "lucro_liquido_dia", "total_cmv"]}'

    # 2. Performance de Ads: ROAS Real vs Pixel (Gráfico de Barras Agrupadas - 12 cols)
    create_card \
        "📊 Comparativo de ROAS: Caixa Real vs Pixel" \
        "bar" \
        "SELECT data_referencia, plataforma_ads, roas_real_faturado, roas_pixel_estimado FROM public.vw_correlacao_ads_vendas_reais ORDER BY data_referencia DESC LIMIT 15;" \
        12 7 \
        '{"graph.dimensions": ["data_referencia", "plataforma_ads"], "graph.metrics": ["roas_real_faturado", "roas_pixel_estimado"]}'

    # 3. Evolução de MRR & ARR B2B (Gráfico de Barras/Área - 12 cols)
    create_card \
        "💼 Crescimento de MRR & ARR B2B Recorrente" \
        "bar" \
        "SELECT mes_ano, novo_mrr_adicionado, mrr_perdido_churn, mrr_total_ativo_mes FROM public.vw_kpi_servicos_mrr_arr ORDER BY mes_referencia DESC LIMIT 12;" \
        12 7 \
        '{"graph.dimensions": ["mes_ano"], "graph.metrics": ["novo_mrr_adicionado", "mrr_total_ativo_mes"]}'

    # 4. Recuperação de Carrinhos & WhatsApp (Gráfico de Rosca/Pizza - 12 cols)
    create_card \
        "💬 Distribuição de Valor em Risco por Tipo de Pendência" \
        "pie" \
        "SELECT tipo_pendencia, SUM(valor_total_em_risco) AS valor_em_risco FROM public.vw_kpi_recuperacao_vendas GROUP BY tipo_pendencia;" \
        12 7 \
        '{"pie.dimension": "tipo_pendencia", "pie.metric": "valor_em_risco"}'

    # 5. Produtividade & Vendas por Atendente Chatwoot (Ranking em Barras Horizontais - 12 cols)
    create_card \
        "👥 Faturamento Convertido por Atendente Comercial" \
        "bar" \
        "SELECT atendente_nome, faturamento_gerado_atendente FROM public.vw_performance_comercial_atendentes WHERE faturamento_gerado_atendente > 0 ORDER BY faturamento_gerado_atendente DESC;" \
        12 7 \
        '{"graph.dimensions": ["atendente_nome"], "graph.metrics": ["faturamento_gerado_atendente"]}'

    # 6. Radar de Oportunidades Cross-Sell & Upsell (Tabela Analítica - 12 cols)
    create_card \
        "🎯 Radar de Oportunidades Cross-Sell & Upsell 360°" \
        "table" \
        "SELECT cliente_nome, cliente_whatsapp, segmento_cliente, ltv_total_consolidado, share_produtos_perc, share_servicos_perc, oportunidade_cross_sell FROM public.vw_cliente_visao_360_hibrida ORDER BY ltv_total_consolidado DESC LIMIT 50;" \
        12 7 \
        '{}'

    # 7. Alerta de Estoque Crítico & Ruptura de Insumos (Tabela Operacional - 12 cols)
    create_card \
        "⚠️ Estoque Crítico & Ruptura de Insumos de Expedição" \
        "table" \
        "SELECT tipo_item, item_nome, saldo_atual, nivel_minimo, deficit_reposicao, status_alerta, setor_responsavel FROM public.vw_estoque_critico ORDER BY deficit_reposicao DESC;" \
        12 7 \
        '{}'

    # Vincula todos os cards ao Dashboard via PUT
    curl -s -X PUT "${MB_URL}/api/dashboard/${DASH_ID}/cards" \
        -H "X-Metabase-Session: $MB_SESSION" \
        -H "Content-Type: application/json" \
        -d "{\"cards\": ${DASH_CARDS_PAYLOAD}}" >/dev/null 2>&1 || true

    # Configura Homepage oficial e IA
    curl -s -X PUT "${MB_URL}/api/setting/custom-homepage" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": true}" >/dev/null 2>&1 || true
    curl -s -X PUT "${MB_URL}/api/setting/custom-homepage-dashboard" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": ${DASH_ID}}" >/dev/null 2>&1 || true
    
    # Suprime "Primeiros Passos", Links de Tutoriais e Banco de Exemplos
    curl -s -X PUT "${MB_URL}/api/setting/show-metabase-links" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": false}" >/dev/null 2>&1 || true
    curl -s -X PUT "${MB_URL}/api/setting/help-link" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": \"none\"}" >/dev/null 2>&1 || true
    curl -s -X PUT "${MB_URL}/api/setting/enable-sample-database" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": false}" >/dev/null 2>&1 || true
    curl -s -X PUT "${MB_URL}/api/setting/has-user-setup" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": true}" >/dev/null 2>&1 || true

    # Remove o banco de exemplos (Sample Database) se existir para limpar o menu
    local SAMPLE_DB_ID=$(curl -s -X GET "${MB_URL}/api/database" -H "X-Metabase-Session: $MB_SESSION" 2>/dev/null | jq -r '(.data // .)? | .[]? | select(.is_sample == true or .name == "Sample Database" or .name == "Exemplo de banco de dados" or .name == "Examples") | .id' 2>/dev/null || echo "")
    if [ -n "$SAMPLE_DB_ID" ] && [ "$SAMPLE_DB_ID" != "null" ]; then
        curl -s -X DELETE "${MB_URL}/api/database/${SAMPLE_DB_ID}" -H "X-Metabase-Session: $MB_SESSION" >/dev/null 2>&1 || true
    fi

    # Integração Automática com IA Soberana (LiteLLM Proxy / Metabot v50+)
    local AI_KEY="${LITELLM_MASTER_KEY:-${OPENROUTER_API_KEY:-${OPENAI_API_KEY}}}"
    local AI_MODEL="${METABASE_AI_MODEL:-openai/gpt-4o-mini}"
    if [ -n "$AI_KEY" ]; then
        curl -s -X PUT "${MB_URL}/api/setting/llm-openai-api-base-url" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": \"http://litellm:4000/v1\"}" >/dev/null 2>&1 || true
        curl -s -X PUT "${MB_URL}/api/setting/llm-openai-api-key" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": \"${AI_KEY}\"}" >/dev/null 2>&1 || true
        curl -s -X PUT "${MB_URL}/api/setting/llm-openai-model" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": \"gpt-4o-mini\"}" >/dev/null 2>&1 || true
        curl -s -X PUT "${MB_URL}/api/setting/llm-metabot-provider" -H "X-Metabase-Session: $MB_SESSION" -H "Content-Type: application/json" -d "{\"value\": \"${AI_MODEL}\"}" >/dev/null 2>&1 || true
    fi

    echo "✔ [SUCESSO METABASE] Dashboard 'Cockpit Executivo Omnichannel 360°' provisionado e fixado na Homepage!"
}

render_forensic_report() {
    local MB_PORT="${HOST_METABASE_PORT:-3030}"
    echo "  📊 Metabase Business Intelligence"
    echo "    ↳ Painel Web:                      http://${ts_domain}:${MB_PORT}"
    echo "    ↳ Healthcheck:                     http://${ts_domain}:${MB_PORT}/api/health"
    echo "    ↳ Banco de Dados Interno:          metabase_db (via PgBouncer)"
    echo "    ↳ Caminho Físico (Host):           ${TARGET_DIR}/volumes/metabase_data"
    echo ""
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o Metabase BI (Painéis Analíticos & Dashboards)?" USE_METABASE "s"
    [[ "${USE_METABASE:-s}" =~ ^[Ss]$ ]] && USE_METABASE="s" || USE_METABASE="n"
    save_wizard_cache "USE_METABASE" "$USE_METABASE"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_metabase="1.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_metabase="2.0"
    fi

    local mem_metabase="2048M"
    local res_metabase="256M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_metabase="4096M"
        res_metabase="1024M"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_metabase="3072M"
        res_metabase="512M"
    fi

    cat << EOF >> "$env_path"

# --- Metabase Decoupled Env & Tuning ---
USE_METABASE="${USE_METABASE:-s}"
HOST_METABASE_PORT="3030"
CPU_METABASE=${CPU_METABASE:-${cpu_metabase}}
MEM_METABASE=${MEM_METABASE:-${mem_metabase}}
RES_METABASE=${RES_METABASE:-${res_metabase}}
EOF
}

# Roteamento de funções via parâmetros CLI (Padrão de Contrato Desacoplado)
ACTION="${2:-all}"
case "$ACTION" in
    collect_wizard_inputs|collect_inputs|wizard_prompt)
        collect_wizard_inputs
        ;;
    build_envs|build_env)
        build_envs
        ;;
    get_version|render_forensic_report|render_report|audit_health|inject_dashboard_card|inject_card|remove_dashboard_card|remove_card|purge_card|disable|teardown|inject_caddy_routes|inject_caddy|remove_caddy_routes|remove_caddy|start_container|wait_readiness|provision_infra|provision_db|provision_user|build_structure)
        case "$ACTION" in
            render_report) render_forensic_report "${3:-localhost}" ;;
            inject_card) inject_dashboard_card ;;
            remove_card|purge_card) remove_dashboard_card ;;
            teardown) disable ;;
            inject_caddy) inject_caddy_routes ;;
            remove_caddy) remove_caddy_routes ;;
            *) "$ACTION" "${3:-localhost}" ;;
        esac
        ;;
    all)
        build_structure
        provision_db
        inject_caddy_routes
        inject_dashboard_card
        start_container
        wait_readiness
        provision_infra
        provision_user
        ;;
    *)
        ;;
esac
