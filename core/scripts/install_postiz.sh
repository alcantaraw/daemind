#!/usr/bin/env bash
# POSTIZ TEMPORAL
# Planejador e Publicador de Mídias Sociais
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO POSTIZ PLANNER & TEMPORAL ENGINE
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório Postiz/Temporal
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

    local VOL_PATH="$TARGET_DIR/volumes/storage_data/postiz"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA POSTIZ] Estrutura de volumes de storage_data/postiz já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE POSTIZ] Criando estrutura física de volumes e permissões do Postiz..."
        sudo mkdir -p "$VOL_PATH" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" 2>/dev/null || true
    fi
}

provision_db() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE POSTIZ] Garantindo banco de dados lógico (postiz_db, temporal e temporal_visibility) no PostgreSQL..."
    for db in postiz_db temporal temporal_visibility; do
        if docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -c "SELECT 1 FROM pg_database WHERE datname = '$db'" 2>/dev/null | grep -q 1; then
            echo "➜ [IDEMPOTÊNCIA POSTIZ] Banco de dados '$db' já existente. Preservando esquema."
        else
            echo "  ↳ Criando banco de dados '$db'..."
            docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -q -c "CREATE DATABASE $db;" > /dev/null 2>&1 || true
        fi
    done
}

provision_infra() {
    echo "➜ [SRE POSTIZ] Garantindo firewall e bancos de dados lógicos no PostgreSQL..."
    local PREFIX="${PREFIXO_CONTAINER}"
    
    local use_val="${USE_POSTIZ:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp -m multiport --dports 3000,3001 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp -m multiport --dports 3000,3001 -j ACCEPT 2>/dev/null || true
        fi
    fi

    # 1. Valida e estrutura esquema SQL do Temporal Engine (namespaces)
    if ! docker compose exec -T postgres psql -U "${DB_USER}" -d temporal -c "SELECT 1 FROM namespaces LIMIT 1;" > /dev/null 2>&1 < /dev/null; then
        echo "➜ [SRE TEMPORAL POSTIZ] Inicializando tabelas e esquema SQL do Temporal Engine (namespaces)..."
        docker compose up -d --force-recreate temporal > /dev/null 2>&1 || true
        local TENTATIVAS=0
        until docker compose exec -T postgres psql -U "${DB_USER}" -d temporal -c "SELECT 1 FROM namespaces LIMIT 1;" > /dev/null 2>&1 < /dev/null; do
            TENTATIVAS=$((TENTATIVAS+1))
            [ "$TENTATIVAS" -ge 30 ] && break
            sleep 2
        done
    fi

    # 2. Higienização Idempotente de Search Attributes do Temporal
    echo "➜ [SRE TEMPORAL] Verificando integridade dos Search Attributes (Postiz)..."
    local CURRENT_ATTRS=$(sudo docker exec -i ${PREFIX}_temporal temporal operator search-attribute list --address 127.0.0.1:7233 2>/dev/null || echo "")

    if echo "$CURRENT_ATTRS" | grep -qi "CustomTextField"; then
        echo "  ↳ Expurgando atributos padrão conflitantes (CustomTextField/CustomStringField)..."
        sudo docker exec -i ${PREFIX}_temporal sh -c "echo y | temporal operator search-attribute remove --name CustomTextField --name CustomStringField --address 127.0.0.1:7233 --yes" > /dev/null 2>&1 || true
    fi

    if ! echo "$CURRENT_ATTRS" | grep -qi "organizationId"; then
        echo "  ↳ Criando atributo obrigatório: organizationId (Keyword)..."
        sudo docker exec -i ${PREFIX}_temporal sh -c "echo y | temporal operator search-attribute create --name organizationId --type Keyword --address 127.0.0.1:7233" > /dev/null 2>&1 || true
    fi

    if ! echo "$CURRENT_ATTRS" | grep -qi "postId"; then
        echo "  ↳ Criando atributo obrigatório: postId (Keyword)..."
        sudo docker exec -i ${PREFIX}_temporal sh -c "echo y | temporal operator search-attribute create --name postId --type Keyword --address 127.0.0.1:7233" > /dev/null 2>&1 || true
    fi

    # 3. Validação DDL do Postiz (Prisma db push)
    if ! docker compose exec -T postgres psql -U "${DB_USER}" -d postiz_db -c "SELECT 1 FROM \"User\" LIMIT 1;" > /dev/null 2>&1 < /dev/null; then
        echo "➜ [SRE POSTIZ] Tabelas ausentes no banco postiz_db. Executando Prisma db push..."
        sudo docker exec -i ${PREFIX}_postiz npx prisma db push --skip-generate > /dev/null 2>&1 || true
    else
        echo "➜ [IDEMPOTÊNCIA POSTIZ] Schema do Postiz Planner (Prisma) já estruturado no Postgres. Preservando tabelas."
    fi

    # 4. Sincronização do barramento do Postiz com o Temporal
    echo "➜ [CONFIGURANDO POSTIZ] Sincronizando barramento do Postiz com o Temporal..."
    docker compose up -d --force-recreate postiz > /dev/null 2>&1 || true
    sleep 3
}

inject_caddy_routes() {
    echo "➜ [SRE POSTIZ] Injetando rotas do Postiz Planner (:5000) no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ':5000 {' "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:5000 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_postiz:5000 {
        header_down Set-Cookie "Secure" ""
        header_down Set-Cookie "SameSite=None" "SameSite=Lax"
        header_down Set-Cookie "Domain=.ts.net" ""
    }
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
    if [ -f "$CADDYFILE_PATH" ] && grep -q ':5000 {' "$CADDYFILE_PATH"; then
        echo "➜ [SRE POSTIZ] Removendo rotas do Postiz Planner (:5000) do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:5000\s*\{[\s\S]*?\}', '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    echo "➜ [SRE POSTIZ] Injetando card do Postiz Planner no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$INDEX_PATH" ] && ! grep -q 'data-port="5000"' "$INDEX_PATH" && ! grep -q 'Postiz Planner' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"5000\" data-path=\"/auth/login\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">🚀</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Postiz Planner</h3>
                    <p class=\"description\">Plataforma de agendamento, planejamento e gestão de redes sociais omnichannel.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:5000</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'Postiz Planner' not in content:
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
    echo "➜ [SRE POSTIZ] Purgando card do Postiz Planner no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    if [ -f "$INDEX_PATH" ] && ( grep -q 'Postiz Planner' "$INDEX_PATH" || grep -q 'data-port="5000"' "$INDEX_PATH" ); then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^>]*data-port=\"5000\"[\s\S]*?</a>\s*', '', content)
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [\s\S]*?Postiz Planner[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE POSTIZ] Desativando módulos Postiz Planner e Temporal Engine..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_postiz" "${PREFIX}_temporal" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 5000 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 5000 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/postiz.conf ]; then
        sudo rm -f /etc/dnsmasq.d/postiz.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO POSTIZ] Módulo Postiz + Temporal desativado, containers removidos, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE POSTIZ] Garantindo subida integrada dos containers Temporal e Postiz..."
    cd "$TARGET_DIR"
    sudo docker compose up -d temporal postiz 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE POSTIZ] Validando prontidão de socket e healthcheck do Temporal e Postiz..."
    local TENTATIVAS=0
    local PREFIX="${PREFIXO_CONTAINER}"
    
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_temporal 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN TEMPORAL] Temporal Engine demorou a responder após 60s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done

    # -----------------------------------------------------------------------
    # SRE UNIFIED READINESS: Validação simultânea dos 3 processos internos:
    # 1. Nginx Gateway (:5000)
    # 2. Next.js Frontend (:4200)
    # 3. NestJS Backend / Temporal (:3000)
    # -----------------------------------------------------------------------
    echo "➜ [SRE POSTIZ] Validando prontidão das 3 portas internas (:5000 Nginx, :4200 NextJS, :3000 NestJS)..."
    local ALL_PORTS_READY=false

    for i in {1..25}; do
        local sockets_postiz=$(sudo docker exec "${PREFIX}_postiz" ss -tulpn 2>/dev/null || echo "")
        
        local has_5000=false
        local has_4200=false
        local has_3000=false

        echo "$sockets_postiz" | grep -q ':5000' && has_5000=true || true
        echo "$sockets_postiz" | grep -q ':4200' && has_4200=true || true
        echo "$sockets_postiz" | grep -q ':3000' && has_3000=true || true

        if [ "$has_5000" = "true" ] && [ "$has_4200" = "true" ] && [ "$has_3000" = "true" ]; then
            # Valida handshake HTTP final de ponta a ponta
            local HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "http://127.0.0.1:5000/auth" 2>/dev/null || echo "000")
            HTTP_CODE=$(echo "$HTTP_CODE" | tr -dc '0-9')
            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "307" ] || [ "$HTTP_CODE" = "302" ]; then
                echo "✔ [OK POSTIZ] As 3 portas (:5000, :4200, :3000) e o HTTP /auth estão 100% operantes!"
                ALL_PORTS_READY=true
                break
            fi
        fi

        if [ "$i" -eq 18 ] && [ "$ALL_PORTS_READY" = "false" ]; then
            echo "➜ [SRE RECOVERY POSTIZ] Inicialização atrasada. Forçando recriação atômica do container..."
            cd "$TARGET_DIR" && sudo docker compose up -d --force-recreate postiz > /dev/null 2>&1 || true
            sleep 4
        fi

        sleep 2
    done

    if [ "$ALL_PORTS_READY" = "false" ]; then
        echo "⚠️ [SRE WARN POSTIZ] Postiz ainda inicializando migrações internas. Continuando em modo resiliente..."
        return 0
    fi

    echo "✔ [SUCESSO POSTIZ] Postiz Planner e Temporal Engine online e saudáveis!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local health_postiz=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_postiz 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_postiz" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:5000/" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    local health_temporal=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_temporal 2>/dev/null || echo "OFFLINE")
    local status_temporal="OFFLINE"
    if [ "$health_temporal" = "healthy" ]; then
        status_temporal=$(sudo docker exec ${PREFIX}_temporal temporal operator cluster health --address $(sudo docker exec ${PREFIX}_temporal hostname -i 2>/dev/null | awk '{print $1}'):7233 >/dev/null 2>&1 && echo "Saudável" || echo "FALHOU")
    else
        status_temporal="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:5000  -> Status: [%s]\n" "Acesso Postiz Planner:" "${ts_domain}" "${http_status}"
    printf "  ↳ %-32s 7233/tcp -> [%s]\n" "Temporal Engine:" "${status_temporal}"
}

get_version() {
    local target_service="${1:-postiz}"
    local PREFIX="${PREFIXO_CONTAINER}"
    
    if [ "$target_service" = "temporal" ]; then
        local container_name="${PREFIX}_temporal"
        local imagem=$(docker inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null || echo "N/A")
        local tag_imagem="${imagem##*:}"
        if [ -n "$tag_imagem" ] && [ "$tag_imagem" != "$imagem" ]; then
            echo "$tag_imagem"
        fi
    else
        local container_name="${PREFIX}_postiz"
        sudo docker exec "$container_name" env 2>/dev/null | grep NEXT_PUBLIC_VERSION | cut -d'=' -f2 || echo ""
    fi
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    echo "  🚀 Planejador Social (Postiz)"
    echo "    ↳ Painel Web (Frontend):           http://${ts_domain}:5000"
    echo "    ↳ Backend API:                     http://${ts_domain}:5000/api/"
    echo "    ↳ Auth:                            http://${ts_domain}:5000/auth"
    echo ""
    echo "  ⚙️ Temporal Engine"
    echo "    ↳ Temporal Web UI (Interna):       http://${ts_domain}:8080"
    echo "    ↳ Temporal API:                    http://${ts_domain}:8080/api/v1"
    echo ""
}

provision_user() {
    echo "➜ [SRE POSTIZ] Provisionando proprietário administrativo no Postiz Planner..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local PAYLOAD_POSTIZ=$(jq -n \
      --arg email "${TS_EMAIL}" \
      --arg pwd "${DB_PASSWORD}" \
      --arg name "${CLIENTE_NOME} ${CLIENTE_SOBRENOME}" \
      --arg company "${PREFIX}" \
      '{email: $email, password: $pwd, name: $name, company: $company, provider: "LOCAL"}')

    local RESPONSE_POSTIZ="502"
    for attempt in {1..20}; do
        # 1. Aguarda ativamente o backend do Postiz responder com código válido
        local probe=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:5000/auth" 2>/dev/null || curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:5000/auth" 2>/dev/null || echo "000")
        probe=$(echo "$probe" | tr -dc '0-9')
        
        if [ "$probe" = "200" ] || [ "$probe" = "307" ] || [ "$probe" = "302" ] || [ "$probe" = "404" ]; then
            RESPONSE_POSTIZ=$(curl -s -w "%{http_code}" -o /dev/null --max-time 10 -X POST "http://127.0.0.1:5000/api/auth/register" \
              -H "Content-Type: application/json" \
              -d "$PAYLOAD_POSTIZ" 2>/dev/null || echo "000")
            
            RESPONSE_POSTIZ=$(echo "$RESPONSE_POSTIZ" | tr -dc '0-9')
            if [ "$RESPONSE_POSTIZ" = "502" ] || [ "$RESPONSE_POSTIZ" = "000" ]; then
                RESPONSE_POSTIZ=$(curl -s -w "%{http_code}" -o /dev/null --max-time 10 -X POST "http://localhost:5000/api/auth/register" \
                  -H "Content-Type: application/json" \
                  -d "$PAYLOAD_POSTIZ" 2>/dev/null || echo "000")
                RESPONSE_POSTIZ=$(echo "$RESPONSE_POSTIZ" | tr -dc '0-9')
            fi

            if [[ "$RESPONSE_POSTIZ" =~ ^(2|400|409) ]]; then
                break
            fi
        fi
        sleep 2
    done

    if [[ "$RESPONSE_POSTIZ" =~ ^2 ]]; then
        echo "➜ [SUCESSO POSTIZ] Proprietário do Postiz provisionado com sucesso."
    elif [[ "$RESPONSE_POSTIZ" =~ ^(400|409) ]]; then
        echo "➜ [IDEMPOTÊNCIA POSTIZ] Proprietário do Postiz já cadastrado (Email already exists). Preservando conta."
    else
        echo "🚨 [ERRO CRÍTICO POSTIZ] Falha ao provisionar proprietário no Postiz (HTTP ${RESPONSE_POSTIZ})."
        return 1
    fi
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o Postiz (Planejador de Redes Sociais)?" USE_POSTIZ "s"
    [[ "${USE_POSTIZ:-s}" =~ ^[Ss]$ ]] && USE_POSTIZ="s" || USE_POSTIZ="n"
    save_wizard_cache "USE_POSTIZ" "$USE_POSTIZ"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local API_KEY="${API_MASTER_KEY:-${DB_PASSWORD:-}}"
    local OLD_KEY=$(grep '^POSTIZ_JWT_SECRET=' "$env_path" 2>/dev/null | cut -d= -f2 || true)
    local FINAL_KEY="${OLD_KEY:-$API_KEY}"
    local domain="${TS_DOMAIN:-localhost}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_postiz="2.0"
    local cpu_temporal="0.5"
    if [ "$cpus" -gt 8 ]; then
        cpu_postiz="4.0"
        cpu_temporal="2.0"
    elif [ "$cpus" -gt 4 ]; then
        cpu_postiz="3.0"
        cpu_temporal="1.0"
    fi

    local mem_postiz="4096M"
    local res_postiz="1024M"
    local mem_temporal="768M"
    local res_temporal="128M"
    local node_heap_postiz="2048"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_postiz="8192M"
        res_postiz="4096M"
        mem_temporal="2048M"
        res_temporal="512M"
        node_heap_postiz="6144"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_postiz="6144M"
        res_postiz="2048M"
        mem_temporal="1024M"
        res_temporal="256M"
        node_heap_postiz="4096"
    fi

    cat << EOF >> "$env_path"

# --- Postiz & Temporal Decoupled Env & Tuning ---
USE_POSTIZ="${USE_POSTIZ:-s}"
HOST_POSTIZ_PORT="5000"
POSTIZ_JWT_SECRET=${FINAL_KEY}
POSTIZ_FRONTEND_URL="http://${domain}:5000"
FRONTEND_URL="http://${domain}:5000"
MAIN_URL="http://${domain}:5000"
NEXT_PUBLIC_BACKEND_URL="http://${domain}:5000"
BACKEND_URL="http://${domain}:5000"
BACKEND_INTERNAL_URL="http://localhost:3000"
CPU_POSTIZ=${CPU_POSTIZ:-${cpu_postiz}}
MEM_POSTIZ=${MEM_POSTIZ:-${mem_postiz}}
RES_POSTIZ=${RES_POSTIZ:-${res_postiz}}
CPU_TEMPORAL=${CPU_TEMPORAL:-${cpu_temporal}}
MEM_TEMPORAL=${MEM_TEMPORAL:-${mem_temporal}}
RES_TEMPORAL=${RES_TEMPORAL:-${res_temporal}}
NODE_HEAP_POSTIZ=${NODE_HEAP_POSTIZ:-${node_heap_postiz}}
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
    get_version|render_forensic_report|render_report|audit_health|inject_dashboard_card|inject_card|remove_dashboard_card|remove_card|purge_card|disable|teardown|inject_caddy_routes|inject_caddy|remove_caddy_routes|remove_caddy|start_container|wait_readiness|provision_infra|provision_user|build_structure|provision_db)
        case "$ACTION" in
            render_report) render_forensic_report "${3:-localhost}" ;;
            inject_card) inject_dashboard_card ;;
            remove_card|purge_card) remove_dashboard_card ;;
            teardown) disable ;;
            inject_caddy) inject_caddy_routes ;;
            remove_caddy) remove_caddy_routes ;;
            get_version) get_version "$3" ;;
            *) "$ACTION" "${3:-localhost}" ;;
        esac
        ;;
    all)
        build_structure
        provision_infra
        inject_caddy_routes
        inject_dashboard_card
        start_container
        wait_readiness
        provision_user
		provision_db
        ;;
    *)
        ;;
esac
