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

    if [ -z "$SETUP_TOKEN" ] || [ "$SETUP_TOKEN" = "null" ]; then
        # Se não há setup-token, o Metabase já foi provisionado anteriormente (Idempotente)
        echo "➜ [IDEMPOTÊNCIA METABASE] Metabase já inicializado e com conta administrativa configurada."
        return 0
    fi

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

    # 3. Auto-vinculação do Data Warehouse (loja_db via PgBouncer)
    local MB_SESSION=$(curl -s -X POST "${MB_URL}/api/session" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"${ADMIN_EMAIL}\", \"password\": \"${ADMIN_PASS}\"}" 2>/dev/null | jq -r '.id // empty' 2>/dev/null || echo "")

    if [ -n "$MB_SESSION" ]; then
        local HAS_DB=$(curl -s -X GET "${MB_URL}/api/database" -H "X-Metabase-Session: $MB_SESSION" 2>/dev/null | jq -r '.data[] | select(.name == "Data Warehouse Soberano") | .id' 2>/dev/null || echo "")
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
        echo "➜ [IDEMPOTÊNCIA METABASE] Dashboard 'Cockpit Executivo Omnichannel 360°' já provisionado (ID: ${DASH_ID}). Garantindo fixação na Tela Inicial..."
        local PIN_NOW=$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')
        curl -s -X PUT "${MB_URL}/api/dashboard/${DASH_ID}" \
            -H "X-Metabase-Session: $MB_SESSION" \
            -H "Content-Type: application/json" \
            -d "{\"pinned_at\": \"${PIN_NOW}\", \"collection_position\": 1}" >/dev/null 2>&1 || true
        return 0
    fi

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

    if [ -z "$DASH_ID" ] || [ "$DASH_ID" = "null" ]; then
        echo "⚠️ [SRE WARN METABASE] Não foi possível criar o Dashboard via API. Prosseguindo..."
        return 0
    fi

    # Garante que o dashboard fique fixado como item principal da tela de Início (Coleção Raiz)
    curl -s -X PUT "${MB_URL}/api/dashboard/${DASH_ID}" \
        -H "X-Metabase-Session: $MB_SESSION" \
        -H "Content-Type: application/json" \
        -d "{\"pinned_at\": \"${PIN_NOW}\", \"collection_position\": 1}" >/dev/null 2>&1 || true

    echo "  ↳ Injetando e fixando Cards Analíticos Nativos do Data Warehouse..."

    # Helper para criar Card, fixar na tela inicial e adicionar ao Dashboard
    local CARD_PIN_POS=2
    create_card_and_pin() {
        local NAME="$1"
        local DISPLAY="$2"
        local SQL_QUERY="$3"
        local ROW="$4"
        local COL="$5"
        local SIZE_X="$6"
        local SIZE_Y="$7"

        local CARD_PAYLOAD
        CARD_PAYLOAD=$(jq -n \
            --arg name "$NAME" \
            --arg display "$DISPLAY" \
            --arg query "$SQL_QUERY" \
            --argjson db "$DB_ID" \
            --arg pin "$PIN_NOW" \
            --argjson pos "$CARD_PIN_POS" \
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
                visualization_settings: {},
                collection_position: $pos,
                pinned_at: $pin
            }')

        CARD_PIN_POS=$((CARD_PIN_POS + 1))

        local CARD_RES
        CARD_RES=$(curl -s -X POST "${MB_URL}/api/card" \
            -H "X-Metabase-Session: $MB_SESSION" \
            -H "Content-Type: application/json" \
            -d "$CARD_PAYLOAD" 2>/dev/null || echo "")
        local CARD_ID
        CARD_ID=$(echo "$CARD_RES" | jq -r '.id // empty' 2>/dev/null || echo "")

        if [ -n "$CARD_ID" ] && [ "$CARD_ID" != "null" ]; then
            # Fixa o card também com PUT para garantir exibição na Home Page
            curl -s -X PUT "${MB_URL}/api/card/${CARD_ID}" \
                -H "X-Metabase-Session: $MB_SESSION" \
                -H "Content-Type: application/json" \
                -d "{\"pinned_at\": \"${PIN_NOW}\", \"collection_position\": ${CARD_PIN_POS}}" >/dev/null 2>&1 || true

            curl -s -X POST "${MB_URL}/api/dashboard/${DASH_ID}/cards" \
                -H "X-Metabase-Session: $MB_SESSION" \
                -H "Content-Type: application/json" \
                -d "{
                    \"cardId\": ${CARD_ID},
                    \"row\": ${ROW},
                    \"col\": ${COL},
                    \"size_x\": ${SIZE_X},
                    \"size_y\": ${SIZE_Y}
                }" >/dev/null 2>&1 || true
        fi
    }

    # 1. DRE & Lucro Líquido Real Diário
    create_card_and_pin \
        "📈 Faturamento vs. Lucro Líquido Real (DRE Diário)" \
        "line" \
        "SELECT data_referencia, faturamento_bruto, total_cmv, lucro_liquido_dia, margem_liquida_perc, roas_dia FROM public.vw_dre_diario_consolidado ORDER BY data_referencia DESC LIMIT 30;" \
        0 0 12 8

    # 2. Radar de Oportunidades Cross-Sell & Upsell
    create_card_and_pin \
        "🎯 Radar de Oportunidades Cross-Sell & Upsell 360°" \
        "table" \
        "SELECT cliente_nome, cliente_whatsapp, segmento_cliente, ltv_total_consolidado, total_pedidos_produtos, contratos_servicos_ativos, share_produtos_perc, share_servicos_perc, oportunidade_cross_sell FROM public.vw_cliente_visao_360_hibrida ORDER BY ltv_total_consolidado DESC LIMIT 50;" \
        8 0 12 8

    # 3. Alerta de Estoque Crítico & Ruptura de Insumos
    create_card_and_pin \
        "⚠️ Estoque Crítico & Ruptura de Insumos de Expedição" \
        "table" \
        "SELECT tipo_item, identificador, item_nome, saldo_atual, nivel_minimo, deficit_reposicao, status_alerta, setor_responsavel FROM public.vw_estoque_critico ORDER BY deficit_reposicao DESC;" \
        16 0 12 6

    # 4. Performance de Marketing & Auditoria de ROAS Real vs Pixel
    create_card_and_pin \
        "📊 Performance de Ads: ROAS Real Caixa vs ROAS Pixel" \
        "table" \
        "SELECT data_referencia, plataforma_ads, campanha_ou_utm, valor_investido_ads, faturamento_pixel, faturamento_real_banco, lucro_liquido_real_auditado, roas_pixel_estimado, roas_real_faturado, discrepancia_pixel_vs_real_perc FROM public.vw_correlacao_ads_vendas_reais ORDER BY data_referencia DESC LIMIT 30;" \
        22 0 12 8

    # 5. MRR, ARR & Churn de Serviços B2B e Contratos
    create_card_and_pin \
        "💼 Gestão de Serviços B2B: MRR, ARR & Churn Rate" \
        "table" \
        "SELECT mes_ano, novos_contratos_mes, novo_mrr_adicionado, contratos_cancelados_mes, mrr_perdido_churn, mrr_net_growth_mes, mrr_total_ativo_mes, arr_anualizado_estimado, churn_rate_mrr_perc FROM public.vw_kpi_servicos_mrr_arr ORDER BY mes_referencia DESC LIMIT 12;" \
        30 0 12 6

    # 6. Recuperação de Carrinhos & WhatsApp
    create_card_and_pin \
        "💬 Recuperação de Carrinhos Abandonados & Boletos" \
        "table" \
        "SELECT tipo_pendencia, status_recuperacao, total_ocorrencias, valor_total_em_risco, valor_total_recuperado, taxa_recuperacao_perc, media_tentativas_contato FROM public.vw_kpi_recuperacao_vendas;" \
        36 0 12 6

    # 7. Produtividade & Conversão de SDRs no Chatwoot
    create_card_and_pin \
        "🏆 Produtividade Comercial de Atendentes (Chatwoot + Vendas)" \
        "table" \
        "SELECT atendente_nome, atendente_email, total_conversas_atendidas, conversas_resolvidas, tempo_medio_primeira_resposta_minutos, tempo_medio_resolucao_minutos, nota_media_csat, vendas_convertidas, faturamento_gerado_atendente, taxa_conversao_atendimento_venda_perc FROM public.vw_performance_comercial_atendentes ORDER BY faturamento_gerado_atendente DESC;" \
        42 0 12 6

    echo "✔ [AUTO-PROVISIONAMENTO METABASE] Cockpit Executivo Omnichannel 360° fixado permanentemente na Tela de Início!"
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
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

    local mem_metabase="1536M"
    local res_metabase="256M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_metabase="4096M"
        res_metabase="1024M"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_metabase="2048M"
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
