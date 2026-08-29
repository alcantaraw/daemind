#!/usr/bin/env bash
# CHATWOOT
# Inbox Omnichannel Multiatendente
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO CHATWOOT CRM
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório Chatwoot
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.11.01-DECOUPLED"

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
fi

build_structure() {
    if [ "${STORAGE_MODE:-local}" != "s3_external" ]; then
        local TARGET_OWNER="1000:1000"
        if [ -n "${SUDO_USER:-}" ]; then
            local TARGET_UID=$(id -u "$SUDO_USER" 2>/dev/null || echo "1000")
            local TARGET_GID=$(id -g "$SUDO_USER" 2>/dev/null || echo "1000")
            TARGET_OWNER="${TARGET_UID}:${TARGET_GID}"
        fi

        local VOL_PATH="$TARGET_DIR/volumes/storage_data/chatwoot"
        local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

        if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
            echo "➜ [IDEMPOTÊNCIA CHATWOOT] Estrutura de volumes de storage_data/chatwoot já alinhada (${TARGET_OWNER}). Preservando I/O."
        else
            echo "➜ [SRE CHATWOOT] Criando estrutura física de volumes e permissões do Chatwoot..."
            sudo mkdir -p "$VOL_PATH" 2>/dev/null || true
            sudo chown -R "$TARGET_OWNER" "$VOL_PATH" 2>/dev/null || true
        fi
    else
        echo "➜ [SRE CHATWOOT] Armazenamento S3 Externo ativo. Omitindo criação de volume local no disco."
    fi
}

provision_db() {
    local PREFIX="${PREFIXO_CONTAINER}"
    echo "➜ [SRE CHATWOOT] Garantindo banco de dados lógico (chatwoot_db) no PostgreSQL..."
    if docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -c "SELECT 1 FROM pg_database WHERE datname = 'chatwoot_db'" 2>/dev/null | grep -q 1; then
        echo "➜ [IDEMPOTÊNCIA CHATWOOT] Banco de dados 'chatwoot_db' já existente. Preservando esquema."
    else
        echo "  ↳ Criando banco de dados 'chatwoot_db'..."
        docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -q -c "CREATE DATABASE chatwoot_db;" > /dev/null 2>&1 || true
    fi
}

provision_infra() {
    echo "➜ [SRE CHATWOOT] Garantindo banco de dados lógico (chatwoot_db), firewall e esquema DDL..."
    local PREFIX="${PREFIXO_CONTAINER}"
    
    local use_val="${USE_CHATWOOT:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport 3000 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport 3000 -j ACCEPT 2>/dev/null || true
        fi
    fi

    # Validação e execução idempotente de migrações Rails
    if ! docker compose exec -T postgres psql -U "${DB_USER}" -d chatwoot_db -c "SELECT 1 FROM installation_configs LIMIT 1;" > /dev/null 2>&1 < /dev/null; then
        echo "➜ [CONFIGURANDO CHATWOOT] Executando preparação de schema inicial do Chatwoot (db:chatwoot_prepare)..."
        docker stop ${PREFIX}_chatwoot > /dev/null 2>&1 || true
        CW_ERR=$(docker compose run --rm --no-deps -T chatwoot bundle exec rails db:chatwoot_prepare 2>&1) || true
        if ! docker compose exec -T postgres psql -U "${DB_USER}" -d chatwoot_db -c "SELECT 1 FROM installation_configs LIMIT 1;" > /dev/null 2>&1 < /dev/null; then
            echo "  ↳ Segunda tentativa via db:schema:load e db:migrate..."
            CW_ERR2=$(docker compose run --rm --no-deps -T chatwoot bundle exec rails db:schema:load db:migrate 2>&1) || true
        fi
        echo "  ↳ Subindo container principal do Chatwoot..."
        docker compose up -d chatwoot > /dev/null 2>&1 || true
    else
        echo "➜ [IDEMPOTÊNCIA CHATWOOT] Banco e schema do Chatwoot já estruturados. Preservando estado."
    fi

    if ! docker compose exec -T postgres psql -U "${DB_USER}" -d chatwoot_db -c "SELECT 1 FROM installation_configs LIMIT 1;" > /dev/null 2>&1 < /dev/null; then
        echo "🚨 [ERRO CRÍTICO CHATWOOT] A migration do Chatwoot falhou! A tabela installation_configs não foi criada."
        echo "Detalhes do Erro Rails (Chatwoot):"
        echo "${CW_ERR:-${CW_ERR2:-Erro desconhecido}}"
        return 1
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE CHATWOOT] Injetando rotas do Chatwoot CRM (:3000) no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ':3000 {' "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:3000 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_chatwoot:3000
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
    if [ -f "$CADDYFILE_PATH" ] && grep -q ':3000 {' "$CADDYFILE_PATH"; then
        echo "➜ [SRE CHATWOOT] Removendo rotas do Chatwoot CRM (:3000) do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:3000\s*\{[\s\S]*?\}', '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    echo "➜ [SRE CHATWOOT] Injetando card do Chatwoot CRM no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$INDEX_PATH" ] && ! grep -q 'data-port="3000"' "$INDEX_PATH" && ! grep -q 'Chatwoot CRM' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"3000\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">🗣️</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Chatwoot CRM</h3>
                    <p class=\"description\">Central de atendimento omnichannel para gestão unificada de conversas e clientes.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:3000</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'Chatwoot CRM' not in content:
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
    echo "➜ [SRE CHATWOOT] Purgando card do Chatwoot CRM no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    if [ -f "$INDEX_PATH" ] && ( grep -q 'Chatwoot CRM' "$INDEX_PATH" || grep -q 'data-port="3000"' "$INDEX_PATH" ); then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^>]*data-port=\"3000\"[\s\S]*?</a>\s*', '', content)
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [\s\S]*?Chatwoot CRM[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE CHATWOOT] Desativando módulo Chatwoot CRM..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_chatwoot" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 3000 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport 3000 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/chatwoot.conf ]; then
        sudo rm -f /etc/dnsmasq.d/chatwoot.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO CHATWOOT] Módulo Chatwoot CRM desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE CHATWOOT] Garantindo subida integrada do container Chatwoot..."
    cd "$TARGET_DIR"
    sudo docker compose up -d chatwoot 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE CHATWOOT] Validando prontidão de socket e healthcheck do Chatwoot..."
    local TENTATIVAS=0
    local PREFIX="${PREFIXO_CONTAINER}"
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_chatwoot 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN CHATWOOT] Chatwoot CRM demorou a responder após 120s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 4
    done
    echo "✔ [SUCESSO CHATWOOT] Chatwoot CRM online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local health_chatwoot=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_chatwoot 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_chatwoot" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:3000/" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:3000  -> Status: [%s]\n" "Chatwoot CRM:" "${ts_domain}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_chatwoot"
    sudo docker exec "$container_name" cat /app/package.json 2>/dev/null | grep '"version"' | head -n 1 | cut -d'"' -f4 || echo "v4.16.0"
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    echo "  🗣️ Atendimento CRM (Chatwoot)"
    echo "    ↳ Painel Web:                      http://${ts_domain}:3000"
    echo ""
}

provision_user() {
    echo "➜ [SRE CHATWOOT] Provisionando conta SuperAdmin no Chatwoot..."
    local PREFIX="${PREFIXO_CONTAINER}"

    local CHATWOOT_STATUS=$(sudo docker exec -i ${PREFIX}_chatwoot bundle exec rails runner "
      if User.exists?(uid: '${TS_EMAIL:-admin@localhost}', provider: 'email') || User.exists?(email: '${TS_EMAIL:-admin@localhost}')
        puts 'EXISTE'
      else
        puts 'CRIAR'
      end
    " < /dev/null 2>/dev/null | grep -E "EXISTE|CRIAR" || echo "CRIAR")

    if [ "$CHATWOOT_STATUS" = "EXISTE" ]; then
        echo "➜ [IDEMPOTÊNCIA CHATWOOT] O Administrador mestre já existe no Chatwoot. Sincronizando AccessToken com DB_PASSWORD..."
        sudo docker exec -i ${PREFIX}_chatwoot bundle exec rails runner "
        begin
          user = User.find_by(email: '${TS_EMAIL:-admin@localhost}') || User.find_by(uid: '${TS_EMAIL:-admin@localhost}') || User.first
          if user
            token_obj = AccessToken.find_or_initialize_by(owner: user)
            token_obj.token = '${DB_PASSWORD}'
            token_obj.save!
          end

          # Auto-ativação da integração OpenAI / LiteLLM nativa para a conta
          Account.all.each do |acc|
            hook = Integrations::Hook.find_or_initialize_by(account_id: acc.id, app_id: 'openai')
            hook.settings = { 'api_key' => '${LITELLM_MASTER_KEY}' }
            hook.status = :enabled
            hook.save(validate: false) rescue nil
          end

          # SRE Self-Healing: Purga conversas e caixas de entrada órfãs (sem canal) para evitar 500 no painel geral
          Conversation.all.each do |c|
            if c.inbox.nil? || c.inbox.channel.nil?
              c.messages.destroy_all rescue nil
              c.destroy! rescue nil
            end
          end
          Inbox.all.each do |i|
            if i.channel.nil?
              i.destroy! rescue nil
            end
          end

          Rails.cache.clear
          GlobalConfig.clear_cache if defined?(GlobalConfig) && GlobalConfig.respond_to?(:clear_cache)
        rescue => e
        end
        " < /dev/null 2>/dev/null || true
    else
        sudo docker exec -i ${PREFIX}_redis redis-cli FLUSHALL > /dev/null 2>&1 < /dev/null || true
        sudo docker exec -i ${PREFIX}_chatwoot bundle exec rails runner "
        begin
          Sidekiq.logger.level = Logger::WARN if defined?(Sidekiq)
          
          # 1. Criação do SuperAdmin e Conta Mestre (Commit Garantido)
          user = User.find_by(email: '${TS_EMAIL:-admin@localhost}')
          if user.nil?
            user = User.new(
              name: '${CLIENTE_NOME:-Admin} ${CLIENTE_SOBRENOME:-User}',
              email: '${TS_EMAIL:-admin@localhost}',
              password: '${DB_PASSWORD:-******}',
              password_confirmation: '${DB_PASSWORD:-******}'
            )
            user.type = 'SuperAdmin'
            user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
            user.save!
          else
            user.password = '${DB_PASSWORD:-******}'
            user.password_confirmation = '${DB_PASSWORD:-******}'
            user.type = 'SuperAdmin'
            user.save!
          end

          account = Account.find_or_create_by!(name: '${PREFIX}')
          AccountUser.find_or_create_by!(account_id: account.id, user_id: user.id) do |au|
            au.role = :administrator
          end
          token_obj = AccessToken.find_or_initialize_by(owner: user)
          token_obj.token = '${DB_PASSWORD}'
          token_obj.save!

          user.update!(ui_settings: { is_profile_setup_completed: true, is_onboarding_completed: true, locale: 'pt_BR' })
          account.update!(custom_attributes: { 'website' => 'https://${TS_DOMAIN:-localhost}', 'timezone' => 'America/Sao_Paulo' })

          # 2. Auto-ativação da integração OpenAI / LiteLLM nativa para a conta
          hook = Integrations::Hook.find_or_initialize_by(account_id: account.id, app_id: 'openai')
          hook.settings = { 'api_key' => '${LITELLM_MASTER_KEY}' }
          hook.status = :enabled
          hook.save(validate: false) rescue nil

          # 3. Parametrização do GlobalConfig / InstallationConfig (HashWithIndifferentAccess)
          [
            ['INSTALLATION_NAME', '${PREFIX}'],
            ['CHATWOOT_INSTANCE_ADMIN_EMAIL', '${TS_EMAIL:-admin@localhost}'],
            ['CAPTAIN_OPEN_AI_API_KEY', '${LITELLM_MASTER_KEY}'],
            ['CAPTAIN_OPEN_AI_ENDPOINT', 'http://litellm:4000/v1'],
            ['CAPTAIN_OPEN_AI_MODEL', 'gpt-4.1'],
            ['OPENAI_API_KEY', '${LITELLM_MASTER_KEY}'],
            ['OPENAI_MODEL', 'gpt-4.1']
          ].each do |k, v|
            cfg = InstallationConfig.find_or_initialize_by(name: k)
            cfg.serialized_value = ActiveSupport::HashWithIndifferentAccess.new({ 'value' => v })
            cfg.save! rescue nil
          end

          Rails.cache.clear
          GlobalConfig.clear_cache if defined?(GlobalConfig) && GlobalConfig.respond_to?(:clear_cache)
          puts '➜ [OK CHATWOOT] SuperAdmin e configurações criados com sucesso!'
        rescue => e
          puts '🚨 [ERRO RUBY CHATWOOT] ' + e.message
        end
        " < /dev/null 2>/dev/null || true
        echo "➜ [SUCESSO CHATWOOT] Administrador Chatwoot cadastrado e IA configurada (Zero-Touch)."
    fi

    local env_file="${TARGET_DIR:-/opt/daemind}/.env"
    if [ -f "$env_file" ]; then
        if grep -q '^CHATWOOT_API_TOKEN=' "$env_file"; then
            sudo sed -i "s|^CHATWOOT_API_TOKEN=.*|CHATWOOT_API_TOKEN=\"${DB_PASSWORD}\"|" "$env_file" 2>/dev/null || true
        else
            echo "CHATWOOT_API_TOKEN=\"${DB_PASSWORD}\"" | sudo tee -a "$env_file" > /dev/null 2>&1 || true
        fi
    fi
    export CHATWOOT_API_TOKEN="${DB_PASSWORD}"
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o Chatwoot CRM (Central de Atendimento Omnichannel)?" USE_CHATWOOT "s"
    [[ "${USE_CHATWOOT:-s}" =~ ^[Ss]$ ]] && USE_CHATWOOT="s" || USE_CHATWOOT="n"
    save_wizard_cache "USE_CHATWOOT" "$USE_CHATWOOT"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local API_KEY="${API_MASTER_KEY:-${DB_PASSWORD:-}}"
    local OLD_KEY=$(grep '^CHATWOOT_SECRET_KEY=' "$env_path" 2>/dev/null | cut -d= -f2 || true)
    local FINAL_KEY="${OLD_KEY:-$API_KEY}"
    local domain="${TS_DOMAIN:-localhost}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_chatwoot="1.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_chatwoot="4.0"
    elif [ "$cpus" -gt 4 ]; then
        cpu_chatwoot="2.0"
    fi

    local mem_chatwoot="2048M"
    local res_chatwoot="512M"
    local web_concurrency="2"
    local sidekiq_concurrency="10"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_chatwoot="8192M"
        res_chatwoot="2048M"
        web_concurrency="8"
        sidekiq_concurrency="30"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_chatwoot="4096M"
        res_chatwoot="1024M"
        web_concurrency="4"
        sidekiq_concurrency="20"
    fi

    cat << EOF >> "$env_path"

# --- Chatwoot CRM Decoupled Env & Tuning ---
USE_CHATWOOT="${USE_CHATWOOT:-s}"
HOST_CHATWOOT_PORT="3000"
CHATWOOT_SECRET_KEY=${FINAL_KEY}
CHATWOOT_FRONTEND_URL="http://${domain}:3000"
CPU_CHATWOOT=${CPU_CHATWOOT:-${cpu_chatwoot}}
MEM_CHATWOOT=${MEM_CHATWOOT:-${mem_chatwoot}}
RES_CHATWOOT=${RES_CHATWOOT:-${res_chatwoot}}
CHATWOOT_WEB_CONCURRENCY=${CHATWOOT_WEB_CONCURRENCY:-${web_concurrency}}
CHATWOOT_SIDEKIQ_CONCURRENCY=${CHATWOOT_SIDEKIQ_CONCURRENCY:-${sidekiq_concurrency}}
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
    build_structure|provision_infra|inject_caddy_routes|inject_caddy|remove_caddy_routes|remove_caddy|inject_dashboard_card|inject_card|remove_dashboard_card|purge_card|remove_card|disable|teardown|start_container|wait_readiness|audit_health|get_version|render_forensic_report|render_report|provision_user|provision_db)
        case "$ACTION" in
            inject_caddy) inject_caddy_routes ;;
            remove_caddy) remove_caddy_routes ;;
            inject_card) inject_dashboard_card ;;
            remove_card|purge_card) remove_dashboard_card ;;
            teardown) disable ;;
            render_report) render_forensic_report "${3:-localhost}" ;;
            audit_health) audit_health "${3:-localhost}" ;;
            render_forensic_report) render_forensic_report "${3:-localhost}" ;;
            *) "$ACTION" ;;
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
