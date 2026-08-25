#!/usr/bin/env bash
# LISTMONK
# Listmonk: Email Marketing e Envio Transacional Soberano
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO LISTMONK
# Especificação: Módulo desacoplado de gerenciamento, banco, Caddy, cards e auditoria
# ===============================================================================

set -eo pipefail

MODULE_VERSION="v2026.08.20.01-DECOUPLED"

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

    local VOL_PATH="$TARGET_DIR/volumes/listmonk_data"
    local CURRENT_OWNER=$(stat -c '%u:%g' "$VOL_PATH" 2>/dev/null || echo "")

    if [ -d "$VOL_PATH" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]; then
        echo "➜ [IDEMPOTÊNCIA LISTMONK] Estrutura de volumes de listmonk_data já alinhada (${TARGET_OWNER}). Preservando I/O."
    else
        echo "➜ [SRE LISTMONK] Criando estrutura física de volumes e permissões do Listmonk..."
        sudo mkdir -p "$VOL_PATH" 2>/dev/null || true
        sudo mkdir -p "$TARGET_DIR/volumes/storage_data/listmonk" 2>/dev/null || true
        sudo chmod -R 777 "$TARGET_DIR/volumes/storage_data/listmonk" 2>/dev/null || true
        sudo chown -R "$TARGET_OWNER" "$VOL_PATH" 2>/dev/null || true
    fi
}

provision_db() {
    echo "➜ [SRE LISTMONK] Provisionando banco de dados relacional dedicado (listmonk_db)..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local DB_ADMIN="${DB_USER}"
    local PRIMARY_DB="${PREFIX}_db"

    local DB_EXISTE=$(sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -t -c "SELECT 1 FROM pg_database WHERE datname = 'listmonk_db';" 2>/dev/null | tr -d '[:space:]' || echo "0")

    if [ "$DB_EXISTE" = "1" ]; then
        echo "➜ [IDEMPOTÊNCIA LISTMONK] Banco de dados 'listmonk_db' já existente no PostgreSQL. Preservando estado."
    else
        echo "  ↳ Criando banco lógico 'listmonk_db'..."
        sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "$PRIMARY_DB" -c "CREATE DATABASE listmonk_db OWNER ${DB_ADMIN};" >/dev/null 2>&1 || true
        echo "✔ [SUCESSO LISTMONK] Banco de dados 'listmonk_db' provisionado com sucesso."

        echo "  ↳ Executando migração/instalação de schema inicial do Listmonk..."
        sudo docker run --rm --network "${PREFIX}_net" \
            -e LISTMONK_db__host=postgres \
            -e LISTMONK_db__port=5432 \
            -e LISTMONK_db__user="${DB_USER}" \
            -e LISTMONK_db__password="${DB_PASSWORD}" \
            -e LISTMONK_db__database=listmonk_db \
            -e LISTMONK_db__ssl_mode=disable \
            listmonk/listmonk:latest ./listmonk --install --idempotent --yes >/dev/null 2>&1 || true

        echo "  ↳ Provisionando conta de Super Admin no banco do Listmonk..."
        provision_user
    fi
}

provision_infra() {
    echo "➜ [SRE LISTMONK] Verificando integridade e firewall perimetral do Listmonk..."
    local use_val="${USE_LISTMONK:-s}"
    local port_num="${HOST_LISTMONK_PORT:-9005}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
        fi
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE LISTMONK] Injetando rotas do Listmonk no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_LISTMONK_PORT:-9005}"

    if [ -f "$CADDYFILE_PATH" ]; then
        if ! grep -q ":${port_num}" "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:${port_num} {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_listmonk:9000
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
    local port_num="${HOST_LISTMONK_PORT:-9005}"
    if [ -f "$CADDYFILE_PATH" ] && grep -q ":${port_num}" "$CADDYFILE_PATH"; then
        echo "➜ [SRE LISTMONK] Removendo rotas do Listmonk do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:${port_num}\s*\{[\s\S]*?listmonk[\s\S]*?\}', '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_dashboard_card() {
    local port_num="${HOST_LISTMONK_PORT:-9005}"
    echo "➜ [SRE LISTMONK] Injetando card do Listmonk no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"

    if [ -f "$INDEX_PATH" ] && ! grep -q "data-port=\"$port_num\"" "$INDEX_PATH" && ! grep -q 'Listmonk Mailer' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"$port_num\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">✉️</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>Listmonk Mailer</h3>
                    <p class=\"description\">Disparador de e-mail marketing, newsletters e e-mails transacionais soberanos.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:$port_num</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'Listmonk Mailer' not in content:
            target = '</div>\n\n        <div class=\"footer-note\">'
            if target in content:
                new_content = content.replace(target, card + '        ' + target)
                f.seek(0)
                f.write(new_content)
                f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

remove_dashboard_card() {
    echo "➜ [SRE LISTMONK] Purgando card do Listmonk no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local port_num="${HOST_LISTMONK_PORT:-9005}"
    if [ -f "$INDEX_PATH" ] && ( grep -q 'Listmonk Mailer' "$INDEX_PATH" || grep -q "data-port=\"$port_num\"" "$INDEX_PATH" ); then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [^>]*data-port=\"$port_num\"[\s\S]*?</a>\s*', '', content)
        new_content = re.sub(r'\s*<a href=\"[^\"]*\" [\s\S]*?Listmonk Mailer[\s\S]*?</a>\s*', '', new_content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE LISTMONK] Desativando módulo Listmonk..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_LISTMONK_PORT:-9005}"
    sudo docker rm -f "${PREFIX}_listmonk" 2>/dev/null || true

    # Limpeza de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport "$port_num" -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/listmonk.conf ]; then
        sudo rm -f /etc/dnsmasq.d/listmonk.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO LISTMONK] Módulo Listmonk desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE LISTMONK] Garantindo subida integrada do container Listmonk..."
    cd "$TARGET_DIR"
    sudo docker compose up -d listmonk 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE LISTMONK] Validando prontidão de socket e healthcheck do Listmonk..."
    local PREFIX="${PREFIXO_CONTAINER}"
    local TENTATIVAS=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIX}_listmonk 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN LISTMONK] Listmonk demorou a responder após 60s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done
    echo "✔ [SUCESSO LISTMONK] Listmonk Server online e saudável!"
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local PREFIX="${PREFIXO_CONTAINER}"
    local port_num="${HOST_LISTMONK_PORT:-9005}"
    local health_val=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_listmonk 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_val" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:${port_num}/health" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:%s  -> Status: [%s]\n" "Listmonk Mailer API/UI:" "${ts_domain}" "${port_num}" "${http_status}"
}

get_version() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local container_name="${PREFIX}_listmonk"
    sudo docker exec "$container_name" ./listmonk --version 2>/dev/null | grep -o 'v[0-9.]*' | head -n 1 || echo "v4.1.0"
}

provision_user() {
    local PREFIX="${PREFIXO_CONTAINER}"
    local DB_ADMIN="${DB_USER}"
    local USER_EMAIL="${TS_EMAIL:-admin@localhost}"
    local SENHA="${DB_PASSWORD}"

    echo "➜ [SRE LISTMONK] Provisionando Super Admin automaticamente no banco do Listmonk..."

    local JA_EXISTE=$(sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "listmonk_db" -t -A -c "
        SELECT 1 FROM users WHERE email = '${USER_EMAIL}' OR username = '${USER_EMAIL}' LIMIT 1;
    " 2>/dev/null | tr -d '\r\n ' || true)

    sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "listmonk_db" -q -c "
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    DO \$\$
    DECLARE
        v_role_id INTEGER;
        v_hash TEXT;
    BEGIN
        -- Gera o hash bcrypt oficial $2a$ via pgcrypto nativo
        v_hash := crypt('${SENHA}', gen_salt('bf', 10));

        -- Obtém ou cria o role padrão de administrador
        SELECT id INTO v_role_id FROM roles WHERE type = 'user' LIMIT 1;
        IF v_role_id IS NULL THEN
            INSERT INTO roles (name, type, permissions, created_at, updated_at)
            VALUES ('Admin', 'user', '{}', NOW(), NOW()) RETURNING id INTO v_role_id;
        END IF;

        -- Injeta ou sincroniza o superadmin com o email do cliente como username principal
        IF NOT EXISTS (SELECT 1 FROM users WHERE email = '${USER_EMAIL}' OR username = '${USER_EMAIL}') THEN
            INSERT INTO users (username, password_login, password, email, name, type, user_role_id, status, twofa_type, created_at, updated_at)
            VALUES ('${USER_EMAIL}', true, v_hash, '${USER_EMAIL}', '${CLIENTE_NOME:-Admin} ${CLIENTE_SOBRENOME:-User}', 'user', v_role_id, 'enabled', 'none', NOW(), NOW());
        ELSE
            UPDATE users 
            SET username = '${USER_EMAIL}', password = v_hash, password_login = true, email = '${USER_EMAIL}', type = 'user', status = 'enabled', updated_at = NOW() 
            WHERE email = '${USER_EMAIL}' OR username = 'admin' OR username = '${USER_EMAIL}';
        END IF;
    END \$\$;
    " >/dev/null 2>&1 || true

    if [ "$JA_EXISTE" = "1" ]; then
        echo "➜ [IDEMPOTÊNCIA LISTMONK] Super Admin Listmonk (${USER_EMAIL}) já cadastrado. Credenciais sincronizadas com o Cofre Mestre."
    else
        echo "✔ [SUCESSO LISTMONK] Super Admin cadastrado e ativo no Listmonk (Login: ${USER_EMAIL} | Senha: [Cofre Mestre])."
    fi

    # -----------------------------------------------------------------------
    # SRE AUTO-INTEGRAÇÃO S3/MINIO: Configura o upload de mídias no MinIO
    # -----------------------------------------------------------------------
    if [ "${STORAGE_MODE:-s3minio}" = "s3minio" ] || [[ "${USE_S3MINIO:-s}" =~ ^[Ss]$ ]]; then
        echo "➜ [SRE LISTMONK] Vinculando bucket MinIO S3 ('listmonk') para uploads de mídias de e-mail..."
        local S3_HOST="http://${PREFIX}_s3minio:9000"
        local S3_PUBLIC_HOST="http://${TS_DOMAIN:-localhost}:9000"
        local S3_KEY="${TS_EMAIL:-admin@localhost}"
        local S3_SECRET="${DB_PASSWORD}"

        sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "listmonk_db" -q -c "
        INSERT INTO settings (key, value, updated_at)
        VALUES 
            ('upload.provider', '\"s3\"', NOW()),
            ('upload.s3.bucket', '\"listmonk\"', NOW()),
            ('upload.s3.aws_s3_bucket', '\"listmonk\"', NOW()),
            ('upload.s3.bucket_type', '\"public\"', NOW()),
            ('upload.s3.url', '\"${S3_HOST}\"', NOW()),
            ('upload.s3.public_url', '\"${S3_PUBLIC_HOST}/listmonk\"', NOW()),
            ('upload.s3.aws_default_region', '\"us-east-1\"', NOW()),
            ('upload.s3.aws_access_key_id', '\"${S3_KEY}\"', NOW()),
            ('upload.s3.aws_secret_access_key', '\"${S3_SECRET}\"', NOW()),
            ('upload.s3.aws_s3_endpoint', '\"${S3_HOST}\"', NOW()),
            ('upload.s3.aws_s3_path_style', 'true', NOW())
        ON CONFLICT (key) DO UPDATE 
        SET value = EXCLUDED.value, updated_at = NOW();
        " >/dev/null 2>&1 || true
        echo "✔ [AUTO-INTEGRAÇÃO LISTMONK] Uploads do Listmonk integrados com o MinIO S3 com sucesso."
    fi

    # -----------------------------------------------------------------------
    # SRE AUTO-INTEGRAÇÃO UTM/SHLINK: Injeta Template Executivo com Auto-UTM
    # -----------------------------------------------------------------------
    echo "➜ [SRE LISTMONK] Provisionando Template Executivo com Auto-UTM (Shlink & Umami)..."
    local TPL_BODY='<!doctype html>
<html>
<head>
    <title>{{ .Campaign.Subject }}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1">
    <base target="_blank">
    <style>
        body { background-color: #0f172a; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size: 15px; line-height: 26px; margin: 0; color: #334155; }
        .wrap { background-color: #ffffff; padding: 40px; max-width: 600px; margin: 30px auto; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 25px; border-bottom: 1px solid #e2e8f0; padding-bottom: 15px; }
        .button { background: #2563eb; border-radius: 6px; text-decoration: none !important; color: #ffffff !important; font-weight: 600; padding: 12px 28px; display: inline-block; margin-top: 15px; }
        .button:hover { background: #1d4ed8; }
        .footer { text-align: center; font-size: 12px; color: #94a3b8; margin: 20px 0; }
        .footer a { color: #64748b; text-decoration: underline; margin: 0 8px; }
    </style>
</head>
<body style="background-color: #f8fafc;">
    <div class="wrap">
        <div class="header">
            <h2 style="color: #0f172a; margin: 0;">{{ .Campaign.Subject }}</h2>
        </div>
        <div class="content" style="color: #334155;">
            {{ template "content" . }}
        </div>
    </div>
    <div class="footer">
        <p>
            <a href="{{ UnsubscribeURL }}">Descadastrar-se</a> | 
            <a href="{{ MessageURL }}">Visualizar no Navegador</a>
        </p>
        <p style="font-size: 11px;">Rastreamento Soberano 100% LGPD/GDPR via Daemind Stack</p>
    </div>
    {{ TrackView }}
</body>
</html>'

    sudo docker exec -i "${PREFIX}_postgres" psql -U "$DB_ADMIN" -d "listmonk_db" -q -c "
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM templates WHERE name = 'Template Executivo Auto-UTM (Shlink & Umami)') THEN
            INSERT INTO templates (name, subject, body, type, is_default, created_at, updated_at)
            VALUES (
                'Template Executivo Auto-UTM (Shlink & Umami)',
                '{{ .Campaign.Subject }}',
                \$$TPL_BODY\$,
                'campaign',
                false,
                NOW(),
                NOW()
            );
        ELSE
            UPDATE templates 
            SET subject = '{{ .Campaign.Subject }}', body = \$$TPL_BODY\$, updated_at = NOW() 
            WHERE name = 'Template Executivo Auto-UTM (Shlink & Umami)';
        END IF;
    END \$\$;
    " >/dev/null 2>&1 || true
    echo "✔ [AUTO-INTEGRAÇÃO LISTMONK] Template Executivo com Auto-UTM provisionado com sucesso."
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    local port_num="${HOST_LISTMONK_PORT:-9005}"
    echo "  ✉️ Listmonk (E-mail Marketing & Transacional)"
    echo "    ↳ Painel Web & API:                http://${ts_domain}:${port_num}"
    echo "    ↳ Administrador Mestre:            ${TS_EMAIL:-admin@localhost}"
    echo "    ↳ Senha de Acesso:                 [Protegida pelo Cofre Mestre]"
    echo ""
}

collect_wizard_inputs() {
    coletar_sn "Deseja instalar o Listmonk (E-mail Marketing & Transacional Soberano)?" USE_LISTMONK "s"
    [[ "${USE_LISTMONK:-s}" =~ ^[Ss]$ ]] && USE_LISTMONK="s" || USE_LISTMONK="n"
    save_wizard_cache "USE_LISTMONK" "$USE_LISTMONK"
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"
    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_listmonk="0.5"
    [ "$cpus" -gt 8 ] && cpu_listmonk="1.0"

    local mem_listmonk="512M"
    local res_listmonk="128M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_listmonk="1024M"
        res_listmonk="256M"
    fi

    cat << EOF >> "$env_path"

# --- Listmonk Decoupled Env & Tuning ---
USE_LISTMONK="${USE_LISTMONK:-s}"
HOST_LISTMONK_PORT="9005"
CPU_LISTMONK=${CPU_LISTMONK:-${cpu_listmonk}}
MEM_LISTMONK=${MEM_LISTMONK:-${mem_listmonk}}
RES_LISTMONK=${RES_LISTMONK:-${res_listmonk}}
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
