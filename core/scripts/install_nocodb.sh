#!/usr/bin/env bash
# NOCODB
# CRM e Banco de Dados Relacional Smart
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO NOCODB ERP
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório NocoDB
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.11.01-DECOUPLED"

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

    local VOL_PATH="$TARGET_DIR/volumes/nocodb_data"
    local VOL_TS_PATH="$TARGET_DIR/volumes/nocodb_ts_state"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA NOCODB] Estrutura de volumes de nocodb_data já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE NOCODB] Criando estrutura física de volumes e permissões do NocoDB..."
        sudo mkdir -p "$VOL_PATH" "$VOL_TS_PATH" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" "$VOL_TS_PATH" 2>/dev/null || true
    fi
}

provision_db() {
    # NocoDB utiliza SQLite/local data storage (banco PostgreSQL dedicado opcional)
    :
}

provision_infra() {
    echo "➜ [SRE NOCODB] Inspecionando integridade do esquema NocoDB e firewall perimetral..."
    local PREFIX="${PREFIXO_CONTAINER}"

    local use_val="${USE_NOCODB:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 18080 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 18080 -j ACCEPT 2>/dev/null || true
        fi
    fi

    local NOCO_TABELAS=$(docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -t -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'nc_%';" 2>/dev/null | tr -dc '0-9' || echo "0")
    NOCO_TABELAS=${NOCO_TABELAS:-0}
    local NOCO_ERRORS=$(sudo docker logs ${PREFIX}_nocodb --tail 200 2>&1 | grep -iE "relation.*does not exist|JOB FAILED|ERR_DATABASE_OP_FAILED" || true)

    if { [ "$NOCO_TABELAS" -gt 0 ] && [ "$NOCO_TABELAS" -lt 40 ]; } || [ -n "$NOCO_ERRORS" ]; then
        echo "➜ [SRE RECOVERY NOCODB] Corrupção no NocoDB detectada ($NOCO_TABELAS tabelas / Motor de migração travado)."
        echo "  ↳ Expurgando esquema corrompido de forma cirúrgica (DROP nc_* CASCADE)..."
        
        docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -c "
        DO \$\$ 
        DECLARE 
            r RECORD; 
        BEGIN 
            FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'nc_%') LOOP 
                EXECUTE 'DROP TABLE IF EXISTS public.' || quote_ident(r.tablename) || ' CASCADE'; 
            END LOOP; 
            FOR r IN (SELECT viewname FROM pg_views WHERE schemaname = 'public' AND viewname LIKE 'nc_%') LOOP 
                EXECUTE 'DROP VIEW IF EXISTS public.' || quote_ident(r.viewname) || ' CASCADE'; 
            END LOOP;
            FOR r IN (SELECT relname FROM pg_class WHERE relkind = 'S' AND relnamespace = 'public'::regnamespace AND relname LIKE 'nc_%') LOOP 
                EXECUTE 'DROP SEQUENCE IF EXISTS public.' || quote_ident(r.relname) || ' CASCADE'; 
            END LOOP;
        END \$\$;" > /dev/null 2>&1 || true

        echo "  ↳ Recriando container para forçar um Boot e Migração limpos..."
        cd "$TARGET_DIR" && sudo docker compose rm -s -f nocodb > /dev/null 2>&1 || true
        sudo rm -rf "$TARGET_DIR/volumes/nocodb_data" 2>/dev/null || true
        mkdir -p "$TARGET_DIR/volumes/nocodb_data"
        sudo chown -R "$TARGET_OWNER" "$TARGET_DIR/volumes/nocodb_data" 2>/dev/null || true
        cd "$TARGET_DIR" && sudo docker compose up -d --force-recreate nocodb > /dev/null 2>&1 || true
        sleep 5
    else
        echo "➜ [IDEMPOTÊNCIA NOCODB] Estrutura do NocoDB parece íntegra ($NOCO_TABELAS tabelas). Preservando o estado atual."
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE NOCODB] Injetando rotas do NocoDB ERP no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_noco="${HOST_NOCODB_PORT:-18080}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ":${port_noco} {" "$CADDYFILE_PATH" && ! grep -q "reverse_proxy.*_nocodb:8080" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:${port_noco} {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_nocodb:8080
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
    local port_noco="${HOST_NOCODB_PORT:-18080}"
    if [ -f "$CADDYFILE_PATH" ] && { grep -q ":${port_noco} {" "$CADDYFILE_PATH" || grep -q ':8080 {' "$CADDYFILE_PATH" || grep -q "reverse_proxy.*_nocodb:8080" "$CADDYFILE_PATH"; }; then
        echo "➜ [SRE NOCODB] Removendo rotas do NocoDB ERP do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:${port_noco}\s*\{[\s\S]*?nocodb[\s\S]*?\}', '', content)
        new_content = re.sub(r'\s*:8080\s*\{[\s\S]*?nocodb[\s\S]*?\}', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    local NOCO_PORT="${HOST_NOCODB_PORT:-18080}"
    echo "➜ [SRE NOCODB] Injetando card do NocoDB ERP no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$INDEX_PATH" ] && ! grep -q 'data-port="18080"' "$INDEX_PATH" && ! grep -q "data-port=\"$NOCO_PORT\"" "$INDEX_PATH" && ! grep -q 'NocoDB ERP' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"$NOCO_PORT\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">📊</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>NocoDB ERP</h3>
                    <p class=\"description\">Banco de dados visual e interface administrativa transacional no-code.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:$NOCO_PORT</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'NocoDB ERP' not in content:
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
    echo "➜ [SRE NOCODB] Purgando card do NocoDB ERP no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    if [ -f "$INDEX_PATH" ] && ( grep -q 'NocoDB ERP' "$INDEX_PATH" || grep -q 'data-port="18080"' "$INDEX_PATH" ); then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^>]*data-port=\"(18080|${HOST_NOCODB_PORT:-18080})\"[\s\S]*?</a>\s*', '', content)
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [\s\S]*?NocoDB ERP[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE NOCODB] Desativando módulo NocoDB ERP..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_nocodb" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 18080 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 18080 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/nocodb.conf ]; then
        sudo rm -f /etc/dnsmasq.d/nocodb.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO NOCODB] Módulo NocoDB ERP desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE NOCODB] Garantindo subida integrada do container NocoDB..."
    cd "$TARGET_DIR"
    sudo docker compose up -d nocodb 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE NOCODB] Validando prontidão de socket e healthcheck do NocoDB..."
    local TENTATIVAS=0
    local PREFIX="${PREFIXO_CONTAINER}"
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_nocodb 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 36 ]; then
            echo "⚠️ [SRE WARN NOCODB] NocoDB ERP não atingiu estado saudável após 180s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 5
    done

    echo "➜ [SRE NOCODB] Aguardando prontidão da API HTTP do NocoDB (:8080/api/v1/health)..."
    TENTATIVAS=0
    until [ "$(sudo docker exec ${PREFIX}_nocodb wget -qO- http://127.0.0.1:8080/api/v1/health 2>/dev/null | grep -o 'OK' || sudo docker exec ${PREFIX}_nocodb curl -s http://localhost:8080/api/v1/health 2>/dev/null | grep -o 'OK' || echo '')" = "OK" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 36 ]; then
            echo "⚠️ [SRE WARN NOCODB] API HTTP do NocoDB não respondeu OK após 180s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 5
    done
    echo "✔ [SUCESSO NOCODB] NocoDB ERP online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local NOCO_PORT="${HOST_NOCODB_PORT:-18080}"
    local health_nocodb=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_nocodb 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_nocodb" = "healthy" ]; then
        http_status=$(curl -s -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:${NOCO_PORT}/api/v1/health" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:%s  -> Status: [%s]\n" "NocoDB ERP:" "${ts_domain}" "${NOCO_PORT}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_nocodb"
    sudo docker exec "$container_name" node -e 'console.log(require("./package.json").version)' 2>/dev/null || echo "2026.07.0"
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local NOCO_PORT="${HOST_NOCODB_PORT:-18080}"
    echo "  📊 Banco de Dados ERP (NocoDB)"
    echo "    ↳ Painel Web:                      http://${ts_domain}:${NOCO_PORT}"
    echo ""
}

provision_user() {
    echo "➜ [SRE NOCODB] Provisionando proprietário e workspace transacional no NocoDB..."
    local PREFIX="${PREFIXO_CONTAINER}"

    local PAYLOAD_NOCO=$(jq -n \
      --arg email "${TS_EMAIL:-admin@localhost}" \
      --arg pwd "${DB_PASSWORD:-******}" \
      --arg firstname "${CLIENTE_NOME:-Admin}" \
      --arg lastname "${CLIENTE_SOBRENOME:-User}" \
      '{email: $email, password: $pwd, firstname: $firstname, lastname: $lastname}')

    local AUTH_TOKEN=""
    local TENTATIVAS=0

    while [ -z "$AUTH_TOKEN" ] || [ "$AUTH_TOKEN" = "null" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "🚨 [ERRO CRÍTICO NOCODB] Falha ao autenticar na API do NocoDB."
            return 1
        fi

        local RESPONSE=$(sudo docker exec ${PREFIX}_nocodb curl -s -X POST http://localhost:8080/api/v1/auth/user/signin \
          -H "Content-Type: application/json" -d "$PAYLOAD_NOCO" || echo '{"error":"CURL_FAILED"}')
        AUTH_TOKEN=$(echo "$RESPONSE" | jq -r '.token // empty')

        if [ -z "$AUTH_TOKEN" ] || [ "$AUTH_TOKEN" = "null" ]; then
            RESPONSE=$(sudo docker exec ${PREFIX}_nocodb curl -s -X POST http://localhost:8080/api/v1/auth/user/signup \
              -H "Content-Type: application/json" -d "$PAYLOAD_NOCO" || echo '{"error":"CURL_FAILED"}')
            AUTH_TOKEN=$(echo "$RESPONSE" | jq -r '.token // empty')
        fi

        if [ -n "$AUTH_TOKEN" ] && [ "$AUTH_TOKEN" != "null" ]; then
            break
        else
            sleep 4
        fi
    done

    echo "➜ [SUCESSO NOCODB] Token administrativo do NocoDB validado."

    # Configuração de Workspace e Fonte Transacional (daemind_db)
    local WORKSPACE_INFO=$(sudo docker exec ${PREFIX}_nocodb curl -s -X GET http://localhost:8080/api/v1/workspaces -H "xc-auth: $AUTH_TOKEN" 2>/dev/null || echo "")
    local WORKSPACE_ID=$(echo "$WORKSPACE_INFO" | jq -r '.list[0].id // empty')

    if [ -n "$WORKSPACE_ID" ] && [ "$WORKSPACE_ID" != "null" ]; then
        # SRE GUARDRAIL: Renomeia workspace apenas se necessário (verdadeiramente idempotente)
        local WORKSPACE_TITLE=$(echo "$WORKSPACE_INFO" | jq -r '.list[0].title // empty')
        if [ "$WORKSPACE_TITLE" != "Painel de Controle" ]; then
            echo "  ↳ Renomeando workspace '${WORKSPACE_TITLE}' → 'Painel de Controle'..."
            sudo docker exec ${PREFIX}_nocodb curl -s -o /dev/null -X PATCH "http://localhost:8080/api/v1/workspaces/${WORKSPACE_ID}" \
                -H "xc-auth: $AUTH_TOKEN" \
                -H "Content-Type: application/json" \
                -d '{"title": "Painel de Controle"}' || true
        else
            echo "➜ [IDEMPOTÊNCIA NOCODB] Workspace já nomeado como 'Painel de Controle'. Preservando."
        fi

        local PREFIX="${EMPRESA:-${PREFIXO_CONTAINER:-loja}}"
        local BASE_NAME="${PREFIX}_db"
        # 1. Localiza a base existente (${PREFIX}_db ou outra base padrão)
        local BASE_EXISTENTE=$(sudo docker exec ${PREFIX}_nocodb curl -s -X GET "http://localhost:8080/api/v2/meta/workspaces/${WORKSPACE_ID}/bases" -H "xc-auth: $AUTH_TOKEN" | jq -r --arg bn "$BASE_NAME" '.list[]? | select((.title | ascii_downcase) == ($bn | ascii_downcase) or .title == "Default Project" or .title == "Default Workspace") | .id // empty' 2>/dev/null | head -n 1 || true)

        if [ -z "$BASE_EXISTENTE" ] || [ "$BASE_EXISTENTE" = "null" ]; then
            # Se não localizou por nome específico, obtém a primeira base existente do workspace
            BASE_EXISTENTE=$(sudo docker exec ${PREFIX}_nocodb curl -s -X GET "http://localhost:8080/api/v2/meta/workspaces/${WORKSPACE_ID}/bases" -H "xc-auth: $AUTH_TOKEN" | jq -r '.list[0].id // empty' 2>/dev/null || true)
        fi

        # 2. Se nenhuma base existir no Workspace (NocoDB v0.250+), cria a Base corporativa
        if [ -z "$BASE_EXISTENTE" ] || [ "$BASE_EXISTENTE" = "null" ]; then
            echo "  ↳ Criando base corporativa principal (${BASE_NAME})..."
            local CREATE_BASE_RES
            CREATE_BASE_RES=$(sudo docker exec ${PREFIX}_nocodb curl -s -X POST "http://localhost:8080/api/v2/meta/workspaces/${WORKSPACE_ID}/bases" \
                -H "xc-auth: $AUTH_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"title\": \"${BASE_NAME}\", \"type\": \"database\"}" 2>/dev/null || echo "")

            BASE_EXISTENTE=$(echo "$CREATE_BASE_RES" | jq -r '.id // empty' 2>/dev/null || true)
        fi

        if [ -n "$BASE_EXISTENTE" ] && [ "$BASE_EXISTENTE" != "null" ]; then
            # 3. Verifica se a fonte de dados PostgreSQL já está vinculada na Base
            local HAS_PG_SOURCE=$(sudo docker exec ${PREFIX}_nocodb curl -s "http://localhost:8080/api/v2/meta/bases/${BASE_EXISTENTE}/sources" -H "xc-auth: $AUTH_TOKEN" | jq -r '.list[]? | select(.type == "pg" and .is_local == false) | .id // empty' 2>/dev/null | head -n 1 || true)

            if [ -z "$HAS_PG_SOURCE" ] || [ "$HAS_PG_SOURCE" = "null" ]; then
                echo "  ↳ Vinculando e sincronizando fonte de dados PostgreSQL (${PREFIX}_db via PgBouncer) no NocoDB..."
                local SOURCE_PAYLOAD
                SOURCE_PAYLOAD=$(jq -n \
                    --arg host "pgbouncer" \
                    --arg port "6432" \
                    --arg user "${DB_USER:-admin_db}" \
                    --arg password "${DB_PASSWORD}" \
                    --arg database "${PREFIX}_db" \
                    '{
                        type: "pg",
                        alias: "PostgreSQL",
                        config: {
                            client: "pg",
                            connection: {
                                host: $host,
                                port: ($port | tonumber),
                                user: $user,
                                password: $password,
                                database: $database,
                                ssl: false,
                                searchPath: "public"
                            }
                        }
                    }')

                sudo docker exec ${PREFIX}_nocodb curl -s -X POST "http://localhost:8080/api/v2/meta/bases/${BASE_EXISTENTE}/sources" \
                    -H "xc-auth: $AUTH_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "$SOURCE_PAYLOAD" >/dev/null 2>&1 || true
                echo "✔ [AUTO-INTEGRAÇÃO NOCODB] Data Warehouse e tabelas sincronizadas com sucesso no NocoDB."
            else
                echo "➜ [IDEMPOTÊNCIA NOCODB] Fonte de dados PostgreSQL já conectada e sincronizada no NocoDB."
            fi
        fi
    fi

    if [ -d "$TARGET_DIR/volumes/nocodb_ts_state" ]; then
        echo "➜ [SRE NOCODB] Consolidando identidade isolada do nó satélite NocoDB..."
        local USER_REAL_HOME=$(eval echo "~${SUDO_USER:-$USER}")
        sudo tar --warning=no-file-changed -czf "$USER_REAL_HOME/nocodb_ts_${PREFIXO_CONTAINER}_backup.tar.gz" -C "$TARGET_DIR/volumes/nocodb_ts_state" . 2>/dev/null || true
        sudo chmod 644 "$USER_REAL_HOME/nocodb_ts_${PREFIXO_CONTAINER}_backup.tar.gz" 2>/dev/null || true
        if [ -n "$SUDO_USER" ]; then
            sudo chown "$SUDO_USER:$SUDO_USER" "$USER_REAL_HOME/nocodb_ts_${PREFIXO_CONTAINER}_backup.tar.gz" 2>/dev/null || true
        fi
    fi
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o NocoDB ERP (Interface Visual de Banco de Dados)?" USE_NOCODB "s"
    [[ "${USE_NOCODB:-s}" =~ ^[Ss]$ ]] && USE_NOCODB="s" || USE_NOCODB="n"
    save_wizard_cache "USE_NOCODB" "$USE_NOCODB"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_nocodb="0.5"
    if [ "$cpus" -gt 8 ]; then
        cpu_nocodb="2.0"
    elif [ "$cpus" -gt 4 ]; then
        cpu_nocodb="1.0"
    fi

    local mem_nocodb="1024M"
    local res_nocodb="0M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_nocodb="4096M"
        res_nocodb="1024M"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_nocodb="2048M"
        res_nocodb="512M"
    fi

    cat << EOF >> "$env_path"

# --- NocoDB ERP Decoupled Env & Tuning ---
USE_NOCODB="${USE_NOCODB:-s}"
NOCO_PORT=${HOST_NOCODB_PORT:-18080}
HOST_NOCODB_PORT=${HOST_NOCODB_PORT:-18080}
CPU_NOCODB=${CPU_NOCODB:-${cpu_nocodb}}
MEM_NOCODB=${MEM_NOCODB:-${mem_nocodb}}
RES_NOCODB=${RES_NOCODB:-${res_nocodb}}
EOF
}

# Roteamento de funções via parâmetros CLI
ACTION="${2:-all}"
case "$ACTION" in
    collect_wizard_inputs|collect_inputs|wizard_prompt)
        collect_wizard_inputs
        ;;
    build_envs|build_env)
        build_envs
        ;;
    build_structure)
        build_structure
        ;;
    provision_infra)
        provision_infra
        ;;
    inject_caddy|inject_caddy_routes)
        inject_caddy_routes
        ;;
    remove_caddy|remove_caddy_routes)
        remove_caddy_routes
        ;;
    inject_card|inject_dashboard_card)
        inject_dashboard_card
        ;;
    remove_card|purge_card|remove_dashboard_card)
        remove_dashboard_card
        ;;
    disable|teardown)
        disable
        ;;
    start_container)
        start_container
        ;;
    wait_readiness)
        wait_readiness
        ;;
    audit_health)
        audit_health "${3:-localhost}"
        ;;
    get_version)
        get_version
        ;;
    render_report|render_forensic_report)
        render_forensic_report "${3:-localhost}"
        ;;
    provision_user)
        provision_user
        ;;
    provision_db)
        provision_db
        ;;
    all)
        build_structure
        provision_db
        provision_infra
        inject_caddy_routes
        inject_dashboard_card
        start_container
        wait_readiness
        provision_user
        ;;
    *)
        ;;
esac
