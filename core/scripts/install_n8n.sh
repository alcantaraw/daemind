#!/usr/bin/env bash
# N8N N8N_SANDBOX SEARXNG
# Motor de Automações & Workflows Ilimitados
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO N8N AUTOMATION
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório n8n
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.14.01-DECOUPLED"

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

    local VOL_PATH="$TARGET_DIR/volumes/n8n_data"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA N8N] Estrutura de volumes de n8n_data já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE N8N] Criando estrutura física de volumes e permissões do n8n..."
        sudo mkdir -p "$VOL_PATH" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" 2>/dev/null || true
        sudo chmod -R 775 "$VOL_PATH" 2>/dev/null || true
    fi

    # Se N8N_DEV_AI_ASSISTANT estiver ativo, cria a estrutura do SearXNG e descomenta os serviços no compose
    if [[ "${N8N_DEV_AI_ASSISTANT:-n}" =~ ^[Ss]$ ]]; then
        local SEARX_DIR="$TARGET_DIR/volumes/searxng"
        sudo mkdir -p "$SEARX_DIR" 2>/dev/null || true
        # Se limiter.toml foi criado como diretório pelo docker, remove
        if [ -d "$SEARX_DIR/limiter.toml" ]; then
            sudo rm -rf "$SEARX_DIR/limiter.toml" 2>/dev/null || true
        fi
        if [ ! -f "$SEARX_DIR/limiter.toml" ]; then
            echo "➜ [SRE N8N DEV] Gerando limiter.toml para o SearXNG..."
            cat << 'EOF' | sudo tee "$SEARX_DIR/limiter.toml" > /dev/null
[botdetection]
ipv4_prefix = 32
ipv6_prefix = 48
trusted_proxies = [
  '127.0.0.0/8',
  '::1',
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16'
]

[botdetection.ip_limit]
filter_link_local = false
link_token = false

[botdetection.ip_lists]
pass_ip = [
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16'
]
pass_searxng_org = true
EOF
        fi

        if [ ! -f "$SEARX_DIR/settings.yml" ]; then
            echo "➜ [SRE N8N DEV] Gerando settings.yml canônico e expurgando engines instáveis para o SearXNG..."
            sudo docker pull -q searxng/searxng:latest >/dev/null 2>&1 || true
            sudo docker run --rm --entrypoint sh searxng/searxng:latest -c "
/usr/local/searxng/.venv/bin/python3 -c '
import yaml
with open(\"/usr/local/searxng/searx/settings.yml\") as f:
    cfg = yaml.safe_load(f)
cfg[\"server\"][\"secret_key\"] = \"${DB_PASSWORD:-daemind_searxng_secret}\"
cfg[\"server\"][\"limiter\"] = False
cfg[\"server\"][\"image_proxy\"] = False
cfg[\"search\"][\"formats\"] = [\"html\", \"json\"]
# Remover completamente as engines problemáticas da lista
cfg[\"engines\"] = [
    eng for eng in cfg.get(\"engines\", [])
    if not any(k in eng.get(\"name\", \"\").lower() or k in eng.get(\"engine\", \"\").lower()
               for k in [\"ahmia\", \"torch\", \"wikidata\", \"onion\"])
]
with open(\"/tmp/settings.yml\", \"w\") as f:
    yaml.dump(cfg, f)
' && cat /tmp/settings.yml
" 2>/dev/null | sudo tee "$SEARX_DIR/settings.yml" > /dev/null
        fi
        sudo chown -R "$TARGET_OWNER" "$SEARX_DIR" 2>/dev/null || true

        local CERTS_DIR="$TARGET_DIR/volumes/n8n_sandbox_certs"
        if [ ! -f "$CERTS_DIR/server.crt" ]; then
            echo "➜ [SRE N8N DEV] Gerando par mTLS para o Sandbox API do n8n..."
            sudo mkdir -p "$CERTS_DIR" 2>/dev/null || true
            sudo openssl req -x509 -newkey rsa:2048 -nodes \
                -keyout "$CERTS_DIR/server.key" \
                -out "$CERTS_DIR/server.crt" \
                -days 3650 -subj "/CN=n8n_sandbox" 2>/dev/null || true
            sudo cp "$CERTS_DIR/server.crt" "$CERTS_DIR/ca.crt" 2>/dev/null || true
            sudo chown -R "$TARGET_OWNER" "$CERTS_DIR" 2>/dev/null || true
            sudo chmod -R 777 "$CERTS_DIR" 2>/dev/null || true
        fi

        # Ativação prévia no compose antes da fusão monotélica da Fase 4
        local N8N_COMPOSE="$TARGET_DIR/core/config/docker-compose.n8n.yml"
        [ ! -f "$N8N_COMPOSE" ] && N8N_COMPOSE="$TARGET_DIR/docker-compose.n8n.yml"
        if [ -f "$N8N_COMPOSE" ]; then
            echo "➜ [SRE N8N DEV] Habilitando AI Assistant Avançado (Sandbox + SearXNG) no compose..."
            # 1. Descomenta todas as linhas marcadas com '# '
            sed -i 's/# //g' "$N8N_COMPOSE" 2>/dev/null || true
            # 2. Habilita o módulo instance-ai liberando a UI do assistente no n8n
            sed -i 's/- N8N_DISABLED_MODULES=.*/- N8N_DISABLED_MODULES=/g' "$N8N_COMPOSE" 2>/dev/null || true
        fi
    fi
}

provision_db() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE N8N] Garantindo banco e schema relacional (n8n_schema) no PostgreSQL..."
    # O n8n utiliza o banco principal ${PREFIX}_db com o schema n8n_schema
    if docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -c "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'n8n_schema'" 2>/dev/null | grep -q 1; then
        echo "➜ [IDEMPOTÊNCIA N8N] Schema 'n8n_schema' já existente no banco principal. Preservando."
    else
        echo "  ↳ Criando schema 'n8n_schema'..."
        docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -q -c "CREATE SCHEMA IF NOT EXISTS n8n_schema AUTHORIZATION ${DB_USER};" > /dev/null 2>&1 || true
        echo "✔ [SUCESSO N8N] Schema 'n8n_schema' provisionado com sucesso."
    fi
}

provision_infra() {
    echo "➜ [SRE N8N] Provisionando firewall, workflows e integrações nativas do n8n..."
    local PREFIX="${PREFIXO_CONTAINER}"
    
    local use_val="${USE_N8N:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
        cat << 'EOF' | sudo tee /etc/dnsmasq.d/n8n.conf > /dev/null
# IPSET ALLOWED DOMAINS (N8N ENGINE & NODE REPOSITORIES)
ipset=/n8n.io/ALLOWED_DOMAINS
ipset=/api.n8n.io/ALLOWED_DOMAINS
ipset=/npmjs.org/ALLOWED_DOMAINS
ipset=/registry.npmjs.org/ALLOWED_DOMAINS
ipset=/registry.yarnpkg.com/ALLOWED_DOMAINS
EOF
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 5678 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 5678 -j ACCEPT 2>/dev/null || true
        fi
    else
        sudo rm -f /etc/dnsmasq.d/n8n.conf 2>/dev/null || true
    fi

    # Injeção idempotente do Workflow de Faxina Reativa 404 de Modelos de IA
    local WF_ID=$(docker exec ${PREFIX}_postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -t -A -c "SELECT id FROM n8n_schema.workflow_entity WHERE name LIKE '%Faxina Reativa%' LIMIT 1;" 2>/dev/null || echo "")

    if [ -z "$WF_ID" ]; then
        echo "➜ [CONFIGURANDO N8N] Injetando Workflow de Faxina Reativa (404) no Orquestrador n8n..."

        if [ -f "$TARGET_DIR/core/config/litellm_purge_workflow.json" ]; then
            cp "$TARGET_DIR/core/config/litellm_purge_workflow.json" "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json" 2>/dev/null || true
        elif [ -f "./core/config/litellm_purge_workflow.json" ]; then
            cp "./core/config/litellm_purge_workflow.json" "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json" 2>/dev/null || true
        fi

        if [ -f "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json" ]; then
            sed -i "s|##LITELLM_HOST##|${PREFIX}_litellm|g" "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json"
            sed -i "s|##LITELLM_KEY##|${LITELLM_MASTER_KEY}|g" "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json"

            docker exec -u node ${PREFIX}_n8n n8n import:workflow --input=/home/node/.n8n/litellm_purge_workflow.json > /dev/null 2>&1 || true

            # Captura o ID diretamente do PostgreSQL e publica o workflow
            WF_ID=$(docker exec ${PREFIX}_postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -t -A -c "SELECT id FROM n8n_schema.workflow_entity WHERE name LIKE '%Faxina Reativa%' LIMIT 1;" 2>/dev/null || echo "")
            if [ -n "$WF_ID" ]; then
                docker exec -u node ${PREFIX}_n8n n8n publish:workflow --id="$WF_ID" > /dev/null 2>&1 || docker exec -u node ${PREFIX}_n8n n8n update:workflow --id="$WF_ID" --active=true > /dev/null 2>&1 || true
            fi
            rm -f "$TARGET_DIR/volumes/n8n_data/litellm_purge_workflow.json" 2>/dev/null || true
            echo "➜ [SUCESSO N8N] Workflow de Faxina Reativa implantado e publicado no n8n."
        fi
    else
        # Garante publicação caso o workflow já exista
        docker exec -u node ${PREFIX}_n8n n8n publish:workflow --id="$WF_ID" > /dev/null 2>&1 || docker exec -u node ${PREFIX}_n8n n8n update:workflow --id="$WF_ID" --active=true > /dev/null 2>&1 || true
        echo "➜ [IDEMPOTÊNCIA N8N] Workflow de Faxina Reativa de Modelos IA já presente e publicado no n8n."
    fi

    # Ativação dinâmica dos containers e variáveis do AI Assistant quando solicitado
    local N8N_COMPOSE="$TARGET_DIR/core/config/docker-compose.n8n.yml"
    [ ! -f "$N8N_COMPOSE" ] && N8N_COMPOSE="$TARGET_DIR/docker-compose.n8n.yml"
    if [ -f "$N8N_COMPOSE" ]; then
        if [[ "${N8N_DEV_AI_ASSISTANT:-n}" =~ ^[Ss]$ ]]; then
            echo "➜ [SRE N8N DEV] Habilitando AI Assistant Avançado (Sandbox + SearXNG) no compose..."
            sed -i 's/# - N8N_INSTANCE_AI_/- N8N_INSTANCE_AI_/g' "$N8N_COMPOSE" 2>/dev/null || true
            sed -i 's/#   image: ghcr.io\/n8n-io\/n8n-sandbox/  image: ghcr.io\/n8n-io\/n8n-sandbox/g' "$N8N_COMPOSE" 2>/dev/null || true
            sed -i 's/#   image: searxng\/searxng/  image: searxng\/searxng/g' "$N8N_COMPOSE" 2>/dev/null || true
            python3 -c "
path = '$N8N_COMPOSE'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        content = re.sub(r'#\s*(n8n_sandbox:|searxng:)', r'\1', content)
        content = re.sub(r'#\s*(\s{2,}[a-zA-Z0-9_\-\.\:\/]+)', r'\1', content)
        f.seek(0)
        f.write(content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
        fi
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE N8N] Injetando rotas do n8n (:5678) no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ':5678 {' "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:5678 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_n8n:5678
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
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        python3 -c "
import re
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r') as f:
        content = f.read()
    pattern = r'(?:\n|^)\s*:5678\s*\{[\s\S]*?\n\}'
    new_content = re.sub(pattern, '', content)
    with open(path, 'w') as f:
        f.write(new_content.strip() + '\n')
except Exception as e:
    pass
"
    fi
}

inject_dashboard_card() {
    echo "➜ [SRE N8N] Injetando card do n8n no portal de controle (index.html)..."
    local HTML_PATH="$TARGET_DIR/core/html/index.html"
    if [ ! -f "$HTML_PATH" ] && [ -f "$TARGET_DIR/html/index.html" ]; then
        HTML_PATH="$TARGET_DIR/html/index.html"
    fi

    if [ -f "$HTML_PATH" ]; then
        python3 -c "
import re

html_path = '$HTML_PATH'
card_html = '''
            <a href=\"#\" data-port=\"5678\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">⚡</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Automação (n8n)</h3>
                    <p class=\"description\">Orquestrador de fluxos de trabalho e integrações avançadas sem código.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:5678</span>
                    </div>
                </div>
            </a>'''

try:
    with open(html_path, 'r+') as f:
        content = f.read()
        if 'data-port=\"5678\"' not in content and '<h3>Automação (n8n)</h3>' not in content:
            if '<div class=\"grid\">' in content:
                new_content = content.replace('<div class=\"grid\">', '<div class=\"grid\">\\n' + card_html, 1)
                f.seek(0)
                f.write(new_content)
                f.truncate()
except Exception as e:
    print(f'Erro ao injetar card n8n: {e}')
"
    fi
}

remove_dashboard_card() {
    local HTML_PATH="$TARGET_DIR/core/html/index.html"
    if [ ! -f "$HTML_PATH" ] && [ -f "$TARGET_DIR/html/index.html" ]; then
        HTML_PATH="$TARGET_DIR/html/index.html"
    fi

    if [ -f "$HTML_PATH" ]; then
        python3 -c "
import re

html_path = '$HTML_PATH'
try:
    with open(html_path, 'r+') as f:
        content = f.read()
        pattern = r'<a [^>]*data-port=[\"\']5678[\"\'][\s\S]*?<\/a>'
        new_content = re.sub(pattern, '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception as e:
    pass
"
    fi
}

disable() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE N8N] Desativando e desprovisionando contêiner do n8n..."
    docker stop "${PREFIX}_n8n" 2>/dev/null || true
    docker rm -f "${PREFIX}_n8n" 2>/dev/null || true
    remove_caddy_routes
    remove_dashboard_card

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 5678 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 5678 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/n8n.conf ]; then
        sudo rm -f /etc/dnsmasq.d/n8n.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO N8N] Módulo n8n desativado, container removido, firewall e rotas limpos."
}

start_container() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE N8N] Garantindo subida integrada do container n8n..."
    cd "$TARGET_DIR" && docker compose up -d --no-deps n8n > /dev/null 2>&1 || true
}

wait_readiness() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE N8N] Validando prontidão de socket e healthcheck do n8n..."
    local TENTATIVAS=0
    until [ "$(docker inspect -f '{{.State.Health.Status}}' "${PREFIX}_n8n" 2>/dev/null || true)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS + 1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [TIMEOUT N8N] Container n8n não atingiu estado healthy após 150s."
            return 1
        fi
        sleep 5
    done
    echo "✔ [SUCESSO N8N] n8n Automation online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' "${PREFIX}_n8n" 2>/dev/null || echo "OFFLINE")
    local http_status=""

    if [ "$health" = "healthy" ]; then
        http_status=$(curl -s -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:5678/healthz" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:5678  -> Status: [%s]\n" "Orquestrador (n8n):" "${ts_domain}" "${http_status}"
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    echo "  ⚡ Orquestrador de IA (n8n)"
    echo "    ↳ Painel Web / Editor:             http://${ts_domain}:5678"
    echo "    ↳ Instance MCP Server:             http://${ts_domain}:5678/mcp/"
    echo "    ↳ Workflow MCP Trigger:            http://${ts_domain}:5678/mcp-test/"
    echo "    ↳ Healthcheck:                     http://${ts_domain}:5678/healthz"
    echo ""
}

get_version() {
    local svc="${1:-n8n}"
    local PREFIX="${PREFIXO_CONTAINER}"
    case "$svc" in
        searxng)
            local VER=$(docker inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "${PREFIX}_searxng" 2>/dev/null || echo "")
            [ -z "$VER" ] && VER=$(docker exec "${PREFIX}_searxng" python3 -c 'import searx.version; print(searx.version.VERSION_STRING)' 2>/dev/null || echo "")
            [ -z "$VER" ] && VER=$(docker inspect -f '{{slice .Created 0 10}}' "${PREFIX}_searxng" 2>/dev/null || echo "")
            echo "${VER:-latest}"
            ;;
        n8n_sandbox)
            local VER=$(docker inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "${PREFIX}_n8n_sandbox" 2>/dev/null || echo "")
            [ -z "$VER" ] && VER=$(docker inspect -f '{{index .Config.Labels "version"}}' "${PREFIX}_n8n_sandbox" 2>/dev/null || echo "")
            [ -z "$VER" ] && VER=$(docker inspect -f '{{slice .Created 0 10}}' "${PREFIX}_n8n_sandbox" 2>/dev/null || echo "")
            echo "${VER:-latest}"
            ;;
        *)
            local VER=$(docker exec "${PREFIX}_n8n" n8n --version 2>/dev/null || echo "")
            if [ -n "$VER" ]; then
                echo "$VER"
            else
                local IMAGE_TAG=$(docker inspect --format='{{.Config.Image}}' "${PREFIX}_n8n" 2>/dev/null | cut -d':' -f2 || echo "")
                echo "${IMAGE_TAG:-latest}"
            fi
            ;;
    esac
}

provision_user() {
    echo "➜ [SRE N8N] Provisionando proprietário administrativo no n8n..."
    local PAYLOAD_N8N=$(jq -n --arg email "$TS_EMAIL" --arg pwd "$DB_PASSWORD" --arg fname "$CLIENTE_NOME" --arg lname "$CLIENTE_SOBRENOME" '{email: $email, password: $pwd, firstName: $fname, lastName: $lname, skipImportingCredentials: true}')
    
    local RESPONSE_N8N=$(curl -s -w "%{http_code}" -o /dev/null -X POST "http://127.0.0.1:5678/rest/owner/setup" \
      -H "Content-Type: application/json" -d "$PAYLOAD_N8N" || echo "000")

    if [[ "$RESPONSE_N8N" =~ ^2 ]]; then
        echo "➜ [SUCESSO N8N] Proprietário do n8n provisionado: ${TS_EMAIL}"
    elif [ "$RESPONSE_N8N" = "400" ] || [ "$RESPONSE_N8N" = "409" ] || [ "$RESPONSE_N8N" = "500" ]; then
        local N8N_HEALTH=$(curl -s -w "%{http_code}" -o /dev/null "http://127.0.0.1:5678/healthz" || echo "000")
        if [ "$N8N_HEALTH" = "200" ]; then
            echo "➜ [IDEMPOTÊNCIA N8N] Proprietário do n8n já cadastrado e instância online e saudável (Healthz 200)."
        else
            echo "🚨 [ERRO CRÍTICO N8N] Falha de infraestrutura no n8n (Setup HTTP ${RESPONSE_N8N} | Healthz HTTP ${N8N_HEALTH})."
            return 1
        fi
    else
        echo "🚨 [ERRO CRÍTICO N8N] Falha ao provisionar proprietário no n8n (HTTP ${RESPONSE_N8N})."
        return 1
    fi
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o n8n (Orquestrador de Automações)?" USE_N8N "s"
    [[ "${USE_N8N:-s}" =~ ^[Ss]$ ]] && USE_N8N="s" || USE_N8N="n"
    save_wizard_cache "USE_N8N" "$USE_N8N"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local domain="${TS_DOMAIN:-localhost}"
    local proto="${BASE_WEBHOOK_PROTOCOL:-http}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_n8n="1.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_n8n="4.0"
    elif [ "$cpus" -gt 4 ]; then
        cpu_n8n="2.0"
    fi

    local mem_n8n="1024M"
    local res_n8n="0M"
    local node_heap_default="768"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_n8n="4096M"
        res_n8n="1024M"
        node_heap_default="3072"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_n8n="2048M"
        res_n8n="512M"
        node_heap_default="1536"
    fi

    local disabled_modules="instance-ai"
    if [[ "${N8N_DEV_AI_ASSISTANT:-n}" =~ ^[Ss]$ ]]; then
        disabled_modules=""
    fi

    cat << EOF >> "$env_path"

# --- Configurações e Tuning do Módulo n8n Automation ---
USE_N8N="${USE_N8N:-s}"
N8N_DEV_AI_ASSISTANT="${N8N_DEV_AI_ASSISTANT:-n}"
N8N_DISABLED_MODULES="${disabled_modules}"
HOST_N8N_PORT="5678"
CPU_N8N=${CPU_N8N:-${cpu_n8n}}
MEM_N8N=${MEM_N8N:-${mem_n8n}}
RES_N8N=${RES_N8N:-${res_n8n}}
NODE_HEAP_DEFAULT=${NODE_HEAP_DEFAULT:-${node_heap_default}}
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-${proto}://${domain}}"
EOF
}

# Roteador Universal CLI
ACTION="${2:-all}"
case "$ACTION" in
    collect_wizard_inputs|collect_inputs|wizard_prompt) collect_wizard_inputs ;;
    build_envs|build_env) build_envs ;;
    build_structure)      build_structure ;;
    provision_db)         provision_db ;;
    provision_infra)      provision_infra ;;
    inject_caddy_routes|inject_caddy)  inject_caddy_routes ;;
    remove_caddy_routes|remove_caddy)  remove_caddy_routes ;;
    inject_dashboard_card|inject_card) inject_dashboard_card ;;
    remove_dashboard_card|remove_card|purge_card) remove_dashboard_card ;;
    disable|teardown)     disable ;;
    start_container)      start_container ;;
    wait_readiness)       wait_readiness ;;
    audit_health)         audit_health "${3:-localhost}" ;;
    get_version)          get_version "$3" ;;
    render_forensic_report|render_report) render_forensic_report "${3:-localhost}" ;;
    provision_user)       provision_user ;;
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
