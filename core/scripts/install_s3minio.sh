#!/usr/bin/env bash
# S3MINIO
# Storage S3 (MinIO Soberano ou Cloud S3)
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO MINIO S3
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório MinIO
# ===============================================================================

[ "${2:-}" = "load_only" ] || set -eo pipefail

MODULE_VERSION="v2026.08.08.10-PROXY-ROUTE-SANALIZED"

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

        # SRE FIX & IDEMPOTÊNCIA: Valida proprietário e permissão octal (777) antes de disparar I/O recursivo no filesystem
        local CURRENT_OWNER=$(stat -c '%u:%g' "$TARGET_DIR/volumes/storage_data" 2>/dev/null || echo "")
        local CURRENT_PERM=$(stat -c '%a' "$TARGET_DIR/volumes/storage_data" 2>/dev/null || echo "")

        if [ -d "$TARGET_DIR/volumes/storage_data" ] && [ "$CURRENT_OWNER" = "$TARGET_OWNER" ] && [ "$CURRENT_PERM" = "777" ]; then
            echo "➜ [IDEMPOTÊNCIA S3MINIO] Permissões e estrutura de storage_data já alinhadas (${TARGET_OWNER}:777). Preservando I/O."
        else
            echo "➜ [SRE S3MINIO] Criando estrutura física de volumes e permissões do MinIO..."
            sudo mkdir -p "$TARGET_DIR"/volumes/storage_data 2>/dev/null || true
            if [[ "${USE_CHATWOOT:-s}" =~ ^[Ss]$ ]]; then
                sudo mkdir -p "$TARGET_DIR"/volumes/storage_data/chatwoot 2>/dev/null || true
            fi
            if [[ "${USE_POSTIZ:-s}" =~ ^[Ss]$ ]]; then
                sudo mkdir -p "$TARGET_DIR"/volumes/storage_data/postiz 2>/dev/null || true
            fi
            if [[ "${USE_EVOLUTION:-s}" =~ ^[Ss]$ ]]; then
                sudo mkdir -p "$TARGET_DIR"/volumes/storage_data/evolution 2>/dev/null || true
            fi
            if [[ "${USE_NOCODB:-s}" =~ ^[Ss]$ ]]; then
                sudo mkdir -p "$TARGET_DIR"/volumes/storage_data/nocodb 2>/dev/null || true
            fi
            sudo chmod -R 777 "$TARGET_DIR"/volumes/storage_data 2>/dev/null || true
            sudo chown -R "$TARGET_OWNER" "$TARGET_DIR"/volumes/storage_data 2>/dev/null || true
            echo "➜ [SRE S3MINIO] Permissões de I/O de storage_data alinhadas (Owner: ${TARGET_OWNER}, Mode: 777)."
        fi
    else
        echo "➜ [SRE S3MINIO] Modo S3 Cloud Externo ativo. Omitindo criação de pastas locais de mídia (FS)."
    fi

    # SRE HARMONIZATION: Comenta ou descomenta blocos de sobreposição com base na seleção de módulos
    local MINIO_COMPOSE_PATH="$TARGET_DIR/core/config/docker-compose.s3minio.yml"
    if [ -f "$MINIO_COMPOSE_PATH" ]; then
        python3 -c "
import re

path = '$MINIO_COMPOSE_PATH'
use_cw = '${USE_CHATWOOT:-s}'.lower() in ['s', 'true', '1']
use_pz = '${USE_POSTIZ:-s}'.lower() in ['s', 'true', '1']
use_evo = '${USE_EVOLUTION:-s}'.lower() in ['s', 'true', '1']
use_noco = '${USE_NOCODB:-s}'.lower() in ['s', 'true', '1']

try:
    with open(path, 'r+') as f:
        content = f.read()
        
        # Chatwoot overlay handler
        cw_tag = '# --- INJEÇÃO DECLARATIVA NATIVA NO CHATWOOT QUANDO S3MINIO ESTÁ ATIVO ---'
        cw_pattern = re.escape(cw_tag) + r'\n([\s\S]*?)\n\s*' + re.escape(cw_tag)
        m_cw = re.search(cw_pattern, content)
        if m_cw:
            block = m_cw.group(1)
            lines = block.splitlines()
            if use_cw:
                new_lines = []
                for line in lines:
                    if line.startswith('  # '):
                        new_lines.append('  ' + line[4:])
                    elif line.startswith('# '):
                        new_lines.append('  ' + line[2:])
                    else:
                        new_lines.append(line)
            else:
                new_lines = ['  # ' + line.lstrip(' #') if line.strip() else line for line in lines]
            content = content[:m_cw.start(1)] + '\n'.join(new_lines) + content[m_cw.end(1):]


        # Evolution overlay handler
        evo_tag = '# --- INJEÇÃO DECLARATIVA NATIVA NO EVOLUTION QUANDO S3MINIO ESTÁ ATIVO ---'
        evo_pattern = re.escape(evo_tag) + r'\n([\s\S]*?)\n\s*' + re.escape(evo_tag)
        m_evo = re.search(evo_pattern, content)
        if m_evo:
            block = m_evo.group(1)
            lines = block.splitlines()
            if use_evo:
                new_lines = []
                for line in lines:
                    if line.startswith('  # '):
                        new_lines.append('  ' + line[4:])
                    elif line.startswith('# '):
                        new_lines.append('  ' + line[2:])
                    else:
                        new_lines.append(line)
            else:
                new_lines = ['  # ' + line.lstrip(' #') if line.strip() else line for line in lines]
            content = content[:m_evo.start(1)] + '\n'.join(new_lines) + content[m_evo.end(1):]

        # NocoDB overlay handler
        noco_tag = '# --- INJEÇÃO DECLARATIVA NATIVA NO NOCODB QUANDO S3MINIO ESTÁ ATIVO ---'
        noco_pattern = re.escape(noco_tag) + r'\n([\s\S]*?)\n\s*' + re.escape(noco_tag)
        m_noco = re.search(noco_pattern, content)
        if m_noco:
            block = m_noco.group(1)
            lines = block.splitlines()
            if use_noco:
                new_lines = []
                for line in lines:
                    if line.startswith('  # '):
                        new_lines.append('  ' + line[4:])
                    elif line.startswith('# '):
                        new_lines.append('  ' + line[2:])
                    else:
                        new_lines.append(line)
            else:
                new_lines = ['  # ' + line.lstrip(' #') if line.strip() else line for line in lines]
            content = content[:m_noco.start(1)] + '\n'.join(new_lines) + content[m_noco.end(1):]

        f.seek(0)
        f.write(content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

inject_caddy_routes() {
    echo "➜ [SRE S3MINIO] Injetando portas do MinIO S3 (:9000/:9001) no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$CADDYFILE_PATH" ]; then
        # Sanitiza rotas corrompidas apenas se a string corrompida existir
        if grep -q '\$_minio' "$CADDYFILE_PATH" || grep -q '\$_s3minio' "$CADDYFILE_PATH"; then
            sudo sed -i "s/\$_minio/${PREFIX}_s3minio/g; s/\$_s3minio/${PREFIX}_s3minio/g" "$CADDYFILE_PATH" 2>/dev/null || true
        fi
        if grep -q '\${PREFIXO_CONTAINER}_minio' "$CADDYFILE_PATH" || grep -q '\${PREFIXO_CONTAINER}_s3minio' "$CADDYFILE_PATH"; then
            sudo sed -i "s/\${PREFIXO_CONTAINER}_minio/${PREFIX}_s3minio/g; s/\${PREFIXO_CONTAINER}_s3minio/${PREFIX}_s3minio/g" "$CADDYFILE_PATH" 2>/dev/null || true
        fi

        if ! grep -q ':9000 {' "$CADDYFILE_PATH"; then
            cat << EOF | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:9000 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_s3minio:9000
}
:9001 {
    log {
        level error
    }
    reverse_proxy ${PREFIX}_s3minio:9001
}
EOF
        fi
    fi
}

inject_dashboard_card() {
    echo "➜ [SRE S3MINIO] Injetando card do MinIO Console no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    local PREFIX="${PREFIXO_CONTAINER}"

    if [ -f "$INDEX_PATH" ] && ! grep -q 'data-port="9001"' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
card = '''            <a href=\"#\" data-port=\"9001\" data-path=\"\" class=\"card dynamic-link\">
                <div class=\"card-content\">
                    <div class=\"card-header\">
                        <div class=\"icon\">🗄️</div>
                        <div class=\"status-indicator\"><div class=\"status-dot\"></div> Online</div>
                    </div>
                    <h3>MinIO Console</h3>
                    <p class=\"description\">Armazenamento S3 soberano para gestão centralizada de mídias e arquivos.</p>
                    <div class=\"card-footer\">
                        <span>Gateway: HTTP</span>
                        <span class=\"port\">:9001</span>
                    </div>
                </div>
            </a>\n'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'data-port=\"9001\"' not in content:
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
    echo "➜ [SRE S3MINIO] Purgando card do MinIO Console no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    if [ -f "$INDEX_PATH" ] && grep -q 'data-port="9001"' "$INDEX_PATH"; then
        python3 -c "
path = '$INDEX_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        if 'data-port=\"9001\"' in content:
            import re
            new_content = re.sub(r'\s*<a href=\"[^\"]*\" data-port=\"9001\"[\s\S]*?</a>\s*', '', content)
            f.seek(0)
            f.write(new_content)
            f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

remove_caddy_routes() {
    local CADDYFILE_PATH="$TARGET_DIR/Caddyfile"
    if [ ! -f "$CADDYFILE_PATH" ] && [ -f "$TARGET_DIR/core/config/Caddyfile" ]; then
        CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    fi
    if [ -f "$CADDYFILE_PATH" ] && grep -q ':9000 {' "$CADDYFILE_PATH"; then
        echo "➜ [SRE S3MINIO] Removendo rotas do MinIO S3 (:9000/:9001) do Caddyfile..."
        python3 -c "
path = '$CADDYFILE_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        new_content = re.sub(r'\s*:9000\s*\{[\s\S]*?\}\s*:9001\s*\{[\s\S]*?\}', '', content)
        f.seek(0)
        f.write(new_content)
        f.truncate()
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable() {
    echo "➜ [SRE S3MINIO] Desativando módulo MinIO S3 (Mudança de Paradigma de Armazenamento)..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER}"
    sudo docker rm -f "${PREFIX}_s3minio" 2>/dev/null || true

    # Limpeza de Regras de Firewall e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp -m multiport --dports 9000,9001 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp -m multiport --dports 9000,9001 -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/s3minio.conf ]; then
        sudo rm -f /etc/dnsmasq.d/s3minio.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO S3MINIO] Módulo MinIO desativado, container removido, firewall e rotas limpos."
}

start_container() {
    echo "➜ [SRE S3MINIO] Garantindo subida integrada do container MinIO..."
    cd "$TARGET_DIR"
    sudo docker compose up -d s3minio 2>/dev/null || true
}

wait_readiness() {
    echo "➜ [SRE S3MINIO] Validando prontidão de socket e healthcheck do MinIO..."
    local TENTATIVAS_MINIO=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIXO_CONTAINER}_s3minio 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS_MINIO=$((TENTATIVAS_MINIO+1))
        if [ "$TENTATIVAS_MINIO" -ge 30 ]; then
            echo "⚠️ [SRE WARN S3MINIO] MinIO S3 demorou a responder após 60s. Continuando em modo degradado..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done
    echo "✔ [SUCESSO S3MINIO] MinIO S3 Server online e saudável!"
}

provision_db() {
    # MinIO S3 Object Storage não exige banco de dados relacional PostgreSQL
    :
}

provision_user() {
    # Credenciais root do MinIO são inicializadas via variáveis de ambiente no container
    :
}

provision_infra() {
    local CW_BUCKET="${S3_CHATWOOT_BUCKET_EXT:-${S3_CHATWOOT_BUCKET:-chatwoot}}"
    local PZ_BUCKET="${S3_POSTIZ_BUCKET_EXT:-${S3_POSTIZ_BUCKET:-postiz}}"
    local EVO_BUCKET="${S3_EVOLUTION_BUCKET_EXT:-${S3_EVOLUTION_BUCKET:-evolution}}"
    local NOCO_BUCKET="${S3_NOCODB_BUCKET_EXT:-${S3_NOCODB_BUCKET:-nocodb}}"

    if [[ "${USE_S3MINIO:-s}" =~ ^[Ss]$ ]]; then
        echo "➜ [SRE S3MINIO] Garantindo buckets condicionados aos módulos ativos no MinIO S3..."
        
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp -m multiport --dports 9000,9001 -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp -m multiport --dports 9000,9001 -j ACCEPT 2>/dev/null || true
        fi

        local MINIO_CTR="${PREFIXO_CONTAINER}_s3minio"
        sudo docker exec "$MINIO_CTR" mc alias set local http://localhost:9000 "${TS_EMAIL}" "${DB_PASSWORD}" >/dev/null 2>&1 || true

        # 1. Bucket e política do Chatwoot
        if [[ "${USE_CHATWOOT:-s}" =~ ^[Ss]$ ]]; then
            if ! sudo docker exec "$MINIO_CTR" mc ls "local/${CW_BUCKET}" >/dev/null 2>&1; then
                sudo docker exec "$MINIO_CTR" mc mb "local/${CW_BUCKET}" >/dev/null 2>&1 || true
                sudo docker exec "$MINIO_CTR" mc anonymous set download "local/${CW_BUCKET}" >/dev/null 2>&1 || true
            else
                local CW_POLICY=$(sudo docker exec "$MINIO_CTR" mc anonymous get "local/${CW_BUCKET}" 2>/dev/null || echo "")
                if ! echo "$CW_POLICY" | grep -qi "download"; then
                    sudo docker exec "$MINIO_CTR" mc anonymous set download "local/${CW_BUCKET}" >/dev/null 2>&1 || true
                fi
            fi
        fi

        # 2. Bucket e política do Postiz
        if [[ "${USE_POSTIZ:-s}" =~ ^[Ss]$ ]]; then
            if ! sudo docker exec "$MINIO_CTR" mc ls "local/${PZ_BUCKET}" >/dev/null 2>&1; then
                sudo docker exec "$MINIO_CTR" mc mb "local/${PZ_BUCKET}" >/dev/null 2>&1 || true
                sudo docker exec "$MINIO_CTR" mc anonymous set download "local/${PZ_BUCKET}" >/dev/null 2>&1 || true
            else
                local PZ_POLICY=$(sudo docker exec "$MINIO_CTR" mc anonymous get "local/${PZ_BUCKET}" 2>/dev/null || echo "")
                if ! echo "$PZ_POLICY" | grep -qi "download"; then
                    sudo docker exec "$MINIO_CTR" mc anonymous set download "local/${PZ_BUCKET}" >/dev/null 2>&1 || true
                fi
            fi
        fi

        # 3. Bucket e política da Evolution API
        if [[ "${USE_EVOLUTION:-s}" =~ ^[Ss]$ ]]; then
            if ! sudo docker exec "$MINIO_CTR" mc ls "local/${EVO_BUCKET}" >/dev/null 2>&1; then
                sudo docker exec "$MINIO_CTR" mc mb "local/${EVO_BUCKET}" >/dev/null 2>&1 || true
                sudo docker exec "$MINIO_CTR" mc anonymous set download "local/${EVO_BUCKET}" >/dev/null 2>&1 || true
            else
                local EVO_POLICY=$(sudo docker exec "$MINIO_CTR" mc anonymous get "local/${EVO_BUCKET}" 2>/dev/null || echo "")
                if ! echo "$EVO_POLICY" | grep -qi "download"; then
                    sudo docker exec "$MINIO_CTR" mc anonymous set download "local/${EVO_BUCKET}" >/dev/null 2>&1 || true
                fi
            fi
        fi

        # 4. Bucket e política do NocoDB
        if [[ "${USE_NOCODB:-s}" =~ ^[Ss]$ ]]; then
            if ! sudo docker exec "$MINIO_CTR" mc ls "local/${NOCO_BUCKET}" >/dev/null 2>&1; then
                sudo docker exec "$MINIO_CTR" mc mb "local/${NOCO_BUCKET}" >/dev/null 2>&1 || true
                sudo docker exec "$MINIO_CTR" mc anonymous set download "local/${NOCO_BUCKET}" >/dev/null 2>&1 || true
            else
                local NOCO_POLICY=$(sudo docker exec "$MINIO_CTR" mc anonymous get "local/${NOCO_BUCKET}" 2>/dev/null || echo "")
                if ! echo "$NOCO_POLICY" | grep -qi "download"; then
                    sudo docker exec "$MINIO_CTR" mc anonymous set download "local/${NOCO_BUCKET}" >/dev/null 2>&1 || true
                fi
            fi
        fi

        echo "✔ [SUCESSO S3MINIO] Buckets de módulos ativos verificados e políticas aplicadas."

    elif [ "${STORAGE_MODE:-}" = "s3_external" ]; then
        echo "➜ [SRE S3 EXTERNO] Garantindo existência de buckets remotos para módulos ativos..."
        if command -v aws >/dev/null 2>&1; then
            export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_EXT:-${S3_ACCESS_KEY_ID:-}}"
            export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY_EXT:-${S3_SECRET_ACCESS_KEY:-}}"
            export AWS_DEFAULT_REGION="${S3_REGION_EXT:-${S3_REGION:-us-east-1}}"
            local ENDPOINT_FLAG=""
            if [ -n "${S3_ENDPOINT_EXT:-${S3_ENDPOINT:-}}" ]; then
                ENDPOINT_FLAG="--endpoint-url ${S3_ENDPOINT_EXT:-${S3_ENDPOINT}}"
            fi

            if [[ "${USE_CHATWOOT:-s}" =~ ^[Ss]$ ]] && [ -n "$CW_BUCKET" ]; then
                echo "  ↳ Tentando provisionar bucket S3 externo para Chatwoot: ${CW_BUCKET}..."
                aws s3 mb "s3://${CW_BUCKET}" $ENDPOINT_FLAG 2>/dev/null || true
            fi

            if [[ "${USE_POSTIZ:-s}" =~ ^[Ss]$ ]] && [ -n "$PZ_BUCKET" ]; then
                echo "  ↳ Tentando provisionar bucket S3 externo para Postiz: ${PZ_BUCKET}..."
                aws s3 mb "s3://${PZ_BUCKET}" $ENDPOINT_FLAG 2>/dev/null || true
            fi

            if [[ "${USE_EVOLUTION:-s}" =~ ^[Ss]$ ]] && [ -n "$EVO_BUCKET" ]; then
                echo "  ↳ Tentando provisionar bucket S3 externo para Evolution API: ${EVO_BUCKET}..."
                aws s3 mb "s3://${EVO_BUCKET}" $ENDPOINT_FLAG 2>/dev/null || true
            fi

            if [[ "${USE_NOCODB:-s}" =~ ^[Ss]$ ]] && [ -n "$NOCO_BUCKET" ]; then
                echo "  ↳ Tentando provisionar bucket S3 externo para NocoDB: ${NOCO_BUCKET}..."
                aws s3 mb "s3://${NOCO_BUCKET}" $ENDPOINT_FLAG 2>/dev/null || true
            fi
        fi
    fi
}

audit_health() {
    local ts_domain="${1:-localhost}"
    local health_minio=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_s3minio 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_minio" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:9001/" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    printf "  ↳ %-32s http://%s:9001  -> Status: [%s]\n" "MinIO Storage Console:" "${ts_domain}" "${http_status}"
}

get_version() {
    local container_name="${PREFIXO_CONTAINER}_s3minio"
    local VER=$(sudo docker inspect -f 'RELEASE.{{index .Config.Labels "org.opencontainers.image.created"}}' "$container_name" 2>/dev/null | cut -dT -f1 || echo "")
    if [ -n "$VER" ] && [ "$VER" != "RELEASE." ] && [ "$VER" != "RELEASE.<no value>" ]; then
        echo "$VER"
    else
        sudo docker inspect -f '{{.Config.Image}}' "$container_name" 2>/dev/null | cut -d: -f2 || echo "latest-release"
    fi
}

render_forensic_report() {
    local ts_domain="${1:-localhost}"
    echo "  🗄️ Armazenamento de Arquivos e Mídia"
    if [ "${STORAGE_MODE:-}" = "s3_external" ] || [ -n "${S3_ENDPOINT_EXT:-}" ] || [ -n "${S3_ENDPOINT:-}" ]; then
        echo "    ↳ Modo:                            S3 Provedor Remoto Cloud (Externo)"
        echo "    ↳ Endpoint S3:                     ${S3_ENDPOINT_EXT:-${S3_ENDPOINT}}"
        echo "    ↳ Região S3:                       ${S3_REGION_EXT:-${S3_REGION}}"
        echo "    ↳ Bucket Chatwoot:                 ${S3_CHATWOOT_BUCKET_EXT:-${S3_CHATWOOT_BUCKET}}"
        echo "    ↳ Bucket Postiz:                   ${S3_POSTIZ_BUCKET_EXT:-${S3_POSTIZ_BUCKET}}"
        echo "    ↳ Access Key ID:                   ${S3_ACCESS_KEY_EXT:-${S3_ACCESS_KEY_ID}}"
        echo ""
    elif [ "${STORAGE_MODE:-}" = "local" ] || [[ "${USE_S3MINIO:-s}" =~ ^[Nn]$ ]]; then
        echo "    ↳ Modo:                            Armazenamento FS Local Direto"
        echo "    ↳ Caminho Físico (Host):           ${TARGET_DIR}/volumes/storage_data"
        echo "    ↳ Mídias Chatwoot:                 ${TARGET_DIR}/volumes/storage_data/chatwoot"
        echo "    ↳ Mídias Postiz:                   ${TARGET_DIR}/volumes/storage_data/postiz"
        echo ""
    else
        echo "    ↳ Modo:                            MinIO S3 Soberano Local"
        echo "    ↳ Console Web:                     http://${ts_domain}:9001/login"
        echo "    ↳ S3 API:                          http://${ts_domain}:9000"
        echo "    ↳ Caminho Físico (Host):           ${TARGET_DIR}/volumes/storage_data"
        echo "    ↳ Healthcheck (Live):              http://${ts_domain}:9000/minio/health/live"
        echo "    ↳ Healthcheck (Ready):             http://${ts_domain}:9000/minio/health/ready"
        echo ""
    fi
}

collect_wizard_inputs_tui() {
    # Se MinIO estiver ativo pelo checklist, configura MinIO On-Premise
    if [[ "${USE_S3MINIO:-s}" =~ ^[Ss]$ ]]; then
        STORAGE_MODE="s3minio"
        USE_S3MINIO="s"
        OPT_STORAGE="2"
        save_wizard_cache "STORAGE_MODE" "$STORAGE_MODE"
        save_wizard_cache "USE_S3MINIO"  "$USE_S3MINIO"
        save_wizard_cache "OPT_STORAGE"  "$OPT_STORAGE"
        return 0
    fi

    local s3_substep=1

    while [ "$s3_substep" -ge 1 ] && [ "$s3_substep" -le 2 ]; do
        case "$s3_substep" in
            1)
                # Se MinIO foi desmarcado no checklist, abre tela dinâmica
                local OPT_S1="on"
                local OPT_S3="off"
                if [ "${STORAGE_MODE:-}" = "s3_external" ] || [ "${OPT_STORAGE:-}" = "3" ]; then
                    OPT_S1="off"; OPT_S3="on"
                fi

                local STORAGE_CHOICE
                STORAGE_CHOICE=$(tui_dialog_step --title "Passo 3b/6: Alternativa de Armazenamento (Sem MinIO)" \
                    --radiolist "Você optou por não instalar o MinIO local.\nSelecione onde os arquivos/mídias serão armazenados:" 13 74 2 \
                    "1" "Armazenamento Local Direto (FS - Salva em disco, 0MB RAM extra)" "$OPT_S1" \
                    "3" "Provedor S3 Cloud Externo (AWS S3 / Cloudflare R2 / DigitalOcean Spaces)" "$OPT_S3" \
                    )
                if [ $? -ne 0 ]; then
                    return 1
                fi

                [ -z "$STORAGE_CHOICE" ] && STORAGE_CHOICE="1"

                case "$STORAGE_CHOICE" in
                    1)
                        STORAGE_MODE="local"
                        USE_S3MINIO="n"
                        OPT_STORAGE="1"
                        save_wizard_cache "STORAGE_MODE" "$STORAGE_MODE"
                        save_wizard_cache "USE_S3MINIO"  "$USE_S3MINIO"
                        save_wizard_cache "OPT_STORAGE"  "$OPT_STORAGE"
                        return 0
                        ;;
                    3)
                        STORAGE_MODE="s3_external"
                        USE_S3MINIO="n"
                        OPT_STORAGE="3"
                        save_wizard_cache "STORAGE_MODE" "$STORAGE_MODE"
                        save_wizard_cache "USE_S3MINIO"  "$USE_S3MINIO"
                        save_wizard_cache "OPT_STORAGE"  "$OPT_STORAGE"
                        s3_substep=2
                        ;;
                esac
                ;;

            2)
                while true; do
                    local S3_FORM_OUT
                    S3_FORM_OUT=$(tui_dialog_step \
                        --title "Passo 3c/6: Credenciais do Provedor S3 Externo" \
                        --mixedform "Configure o acesso ao bucket S3 (AWS S3 / Cloudflare R2 / DigitalOcean Spaces):" \
                        22 90 10 \
                        "Endpoint S3 (https://...):"            1 1 "${S3_ENDPOINT_EXT:-}"                   1 40 44 512 0 \
                        "Região S3 (us-east-1 / auto / ...):"   2 1 "${S3_REGION_EXT:-us-east-1}"            2 40 44 128 0 \
                        "Access Key ID:"                        3 1 "${S3_ACCESS_KEY_EXT:-}"                  3 40 44 512 0 \
                        "Secret Access Key:"                    4 1 "${S3_SECRET_KEY_EXT:-}"                  4 40 44 512 0 \
                        "Bucket Chatwoot:"                      5 1 "${S3_CHATWOOT_BUCKET_EXT:-chatwoot}"     5 40 44 128 0 \
                        "Bucket Postiz:"                        6 1 "${S3_POSTIZ_BUCKET_EXT:-postiz}"         6 40 44 128 0 \
                        "Bucket Evolution API:"                 7 1 "${S3_EVOLUTION_BUCKET_EXT:-evolution}"   7 40 44 128 0 \
                        "Bucket NocoDB:"                        8 1 "${S3_NOCODB_BUCKET_EXT:-nocodb}"         8 40 44 128 0 \
                        )
                    if [ $? -ne 0 ]; then
                        s3_substep=1
                        break
                    fi

                    S3_ENDPOINT_EXT=$(echo  "$S3_FORM_OUT" | sed -n '1p' | tr -d '\r\n')
                    S3_REGION_EXT=$(echo    "$S3_FORM_OUT" | sed -n '2p' | tr -d '\r\n ')
                    S3_ACCESS_KEY_EXT=$(echo "$S3_FORM_OUT" | sed -n '3p' | tr -d '\r\n')
                    S3_SECRET_KEY_EXT=$(echo "$S3_FORM_OUT" | sed -n '4p' | tr -d '\r\n')
                    S3_CHATWOOT_BUCKET_EXT=$(echo  "$S3_FORM_OUT" | sed -n '5p' | tr -d '\r\n ')
                    S3_POSTIZ_BUCKET_EXT=$(echo    "$S3_FORM_OUT" | sed -n '6p' | tr -d '\r\n ')
                    S3_EVOLUTION_BUCKET_EXT=$(echo "$S3_FORM_OUT" | sed -n '7p' | tr -d '\r\n ')
                    S3_NOCODB_BUCKET_EXT=$(echo    "$S3_FORM_OUT" | sed -n '8p' | tr -d '\r\n ')

                    if [ -z "$S3_ENDPOINT_EXT" ] || [ -z "$S3_ACCESS_KEY_EXT" ] || [ -z "$S3_SECRET_KEY_EXT" ]; then
                        tui_dialog --title "Campos Obrigatórios" \
                            --msgbox "Endpoint, Access Key e Secret Key são obrigatórios para o S3 externo." 7 60 || true
                        continue
                    fi
                    [ -z "$S3_REGION_EXT" ]          && S3_REGION_EXT="us-east-1"
                    [ -z "$S3_CHATWOOT_BUCKET_EXT" ]  && S3_CHATWOOT_BUCKET_EXT="chatwoot"
                    [ -z "$S3_POSTIZ_BUCKET_EXT" ]    && S3_POSTIZ_BUCKET_EXT="postiz"
                    [ -z "$S3_EVOLUTION_BUCKET_EXT" ] && S3_EVOLUTION_BUCKET_EXT="evolution"
                    [ -z "$S3_NOCODB_BUCKET_EXT" ]    && S3_NOCODB_BUCKET_EXT="nocodb"
                    save_wizard_cache "S3_ENDPOINT_EXT"       "$S3_ENDPOINT_EXT"
                    save_wizard_cache "S3_REGION_EXT"         "$S3_REGION_EXT"
                    save_wizard_cache "S3_ACCESS_KEY_EXT"     "$S3_ACCESS_KEY_EXT"
                    save_wizard_cache "S3_SECRET_KEY_EXT"     "$S3_SECRET_KEY_EXT"
                    save_wizard_cache "S3_CHATWOOT_BUCKET_EXT"  "$S3_CHATWOOT_BUCKET_EXT"
                    save_wizard_cache "S3_POSTIZ_BUCKET_EXT"    "$S3_POSTIZ_BUCKET_EXT"
                    save_wizard_cache "S3_EVOLUTION_BUCKET_EXT" "$S3_EVOLUTION_BUCKET_EXT"
                    save_wizard_cache "S3_NOCODB_BUCKET_EXT"    "$S3_NOCODB_BUCKET_EXT"
                    export STORAGE_MODE USE_S3MINIO OPT_STORAGE S3_ENDPOINT_EXT S3_REGION_EXT S3_ACCESS_KEY_EXT S3_SECRET_KEY_EXT S3_CHATWOOT_BUCKET_EXT S3_POSTIZ_BUCKET_EXT S3_EVOLUTION_BUCKET_EXT S3_NOCODB_BUCKET_EXT
                    return 0
                done
                ;;
        esac
    done
    return 1
}

collect_wizard_inputs() {
    echo ""
    echo -e "\e[33m=== [SRE FinOps S3MINIO] Arquitetura de Armazenamento de Mídias e Arquivos ===\e[0m"

    local TOTAL_CPUS_HOST="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local TOTAL_RAM_GB_HOST="${SYSTEM_TOTAL_RAM_GB:-${TOTAL_RAM_GB:-8}}"
    local IS_MODEST_SERVER="${IS_MODEST_SERVER:-false}"

    STORAGE_MODE="${AUTO_STORAGE_MODE:-${STORAGE_MODE:-}}"

    if [ -z "$STORAGE_MODE" ] && [ -n "${WIZARD_CACHE_NAME:-}" ]; then
        case "${WIZARD_CACHE_NAME}" in
            local|s3minio|minio|s3_external)
                [ "${WIZARD_CACHE_NAME}" = "minio" ] && STORAGE_MODE="s3minio" || STORAGE_MODE="${WIZARD_CACHE_NAME}"
                ;;
        esac
    fi

    if [ -z "$STORAGE_MODE" ]; then
        if [ -n "${AUTO_USE_S3MINIO:-}" ] || [ -n "${USE_S3MINIO:-}" ]; then
            local VAL_S3MINIO="${AUTO_USE_S3MINIO:-$USE_S3MINIO}"
            if [[ "$VAL_S3MINIO" =~ ^[Ss]$ ]]; then
                STORAGE_MODE="s3minio"
            else
                STORAGE_MODE="local"
            fi
        fi
    fi

    if [ -n "$STORAGE_MODE" ]; then
        [ "$STORAGE_MODE" = "minio" ] && STORAGE_MODE="s3minio"
        echo -e "\e[32m✔ [AUTO-STORAGE S3MINIO] Modo de Armazenamento lido do ambiente/cache (STORAGE_MODE=${STORAGE_MODE}).\e[0m"
    else
        local DEFAULT_OPTION="2"
        if [ "$IS_MODEST_SERVER" = "true" ]; then
            echo -e "\e[33m⚠️ [SRE ADVICE S3MINIO] Host Modesto Detectado: ${TOTAL_CPUS_HOST} Cores | ${TOTAL_RAM_GB_HOST} GB RAM.\e[0m"
            echo -e "\e[36m  ↳ Recomendação: Armazenamento Local Direto (Economiza 1GB RAM & CPU do S3MinIO).\e[0m"
            DEFAULT_OPTION="1"
        else
            echo -e "\e[32m✔ [SRE ADVICE S3MINIO] Host de Alta Performance: ${TOTAL_CPUS_HOST} Cores | ${TOTAL_RAM_GB_HOST} GB RAM.\e[0m"
            echo -e "\e[36m  ↳ Recomendação: MinIO S3 Soberano (Gerenciamento centralizado de mídias).\e[0m"
            DEFAULT_OPTION="2"
        fi

        echo ""
        echo -e "Escolha o modo de armazenamento desejado para a stack:"
        echo -e "  [1] Armazenamento Local Direto (Sem S3MinIO - Salva em disco ./volumes/*_data, 0MB RAM extra)"
        echo -e "  [2] MinIO S3 Soberano (Local - Provisiona container S3MinIO dedicado com S3 API)"
        echo -e "  [3] Provedor S3 Cloud Externo (AWS S3 / Cloudflare R2 / DigitalOcean Spaces)"
        
        local OPT_STORAGE
        coletar_input "Digite a opção desejada (1, 2 ou 3)" OPT_STORAGE "false" "^[123]$" "$DEFAULT_OPTION" "false"

        case "$OPT_STORAGE" in
            1)
                STORAGE_MODE="local"
                USE_S3MINIO="n"
                ;;
            2)
                STORAGE_MODE="s3minio"
                USE_S3MINIO="s"
                ;;
            3)
                STORAGE_MODE="s3_external"
                USE_S3MINIO="n"
                ;;
            *)
                STORAGE_MODE="local"
                USE_S3MINIO="n"
                ;;
        esac
    fi

    if [ "$STORAGE_MODE" = "s3minio" ] || [ "$STORAGE_MODE" = "minio" ]; then
        STORAGE_MODE="s3minio"
        USE_S3MINIO="s"
    else
        USE_S3MINIO="n"
    fi

    if [ "$STORAGE_MODE" = "s3_external" ]; then
        echo ""
        echo -e "\e[36m➜ Configuração do Provedor S3 Cloud Remoto (AWS / R2 / DigitalOcean):\e[0m"
        coletar_input "Endpoint do S3 (ex: https://<account-id>.r2.cloudflarestorage.com ou https://s3.us-east-1.amazonaws.com)" S3_ENDPOINT_EXT "true" "^https?://" "" "false"
        coletar_input "Região do S3 (ex: us-east-1 ou auto)" S3_REGION_EXT "false" "" "us-east-1" "false"
        coletar_input "Access Key ID do S3" S3_ACCESS_KEY_EXT "true" "" "" "false"
        coletar_input "Secret Access Key do S3" S3_SECRET_KEY_EXT "true" "" "" "true"
        coletar_input "Nome do Bucket do Chatwoot" S3_CHATWOOT_BUCKET_EXT "false" "" "chatwoot" "false"
        coletar_input "Nome do Bucket do Postiz" S3_POSTIZ_BUCKET_EXT "false" "" "postiz" "false"
        coletar_input "Nome do Bucket da Evolution API" S3_EVOLUTION_BUCKET_EXT "false" "" "evolution" "false"
        coletar_input "Nome do Bucket do NocoDB" S3_NOCODB_BUCKET_EXT "false" "" "nocodb" "false"
    fi

    save_wizard_cache "STORAGE_MODE" "$STORAGE_MODE"
    save_wizard_cache "USE_S3MINIO" "$USE_S3MINIO"
    if [ "$STORAGE_MODE" = "s3_external" ]; then
        save_wizard_cache "S3_ENDPOINT_EXT" "$S3_ENDPOINT_EXT"
        save_wizard_cache "S3_REGION_EXT" "$S3_REGION_EXT"
        save_wizard_cache "S3_ACCESS_KEY_EXT" "$S3_ACCESS_KEY_EXT"
        save_wizard_cache "S3_SECRET_KEY_EXT" "$S3_SECRET_KEY_EXT"
        save_wizard_cache "S3_CHATWOOT_BUCKET_EXT" "$S3_CHATWOOT_BUCKET_EXT"
        save_wizard_cache "S3_POSTIZ_BUCKET_EXT" "$S3_POSTIZ_BUCKET_EXT"
        save_wizard_cache "S3_EVOLUTION_BUCKET_EXT" "$S3_EVOLUTION_BUCKET_EXT"
        save_wizard_cache "S3_NOCODB_BUCKET_EXT" "$S3_NOCODB_BUCKET_EXT"
    fi
}

build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"

    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    local cpu_s3minio="1.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_s3minio="2.0"
    fi

    local mem_s3minio="1024M"
    local res_s3minio="0M"
    local s3_requests_max="1500"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_s3minio="4096M"
        res_s3minio="1024M"
        s3_requests_max="6000"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_s3minio="2048M"
        res_s3minio="512M"
        s3_requests_max="3000"
    fi

    local s3_endpoint_val="${S3_ENDPOINT_EXT}"
    local s3_region_val="${S3_REGION_EXT:-us-east-1}"
    local s3_access_val="${S3_ACCESS_KEY_EXT}"
    local s3_secret_val="${S3_SECRET_KEY_EXT}"
    local s3_cw_bucket="${S3_CHATWOOT_BUCKET_EXT:-chatwoot}"
    local s3_pz_bucket="${S3_POSTIZ_BUCKET_EXT:-postiz}"
    local s3_evo_bucket="${S3_EVOLUTION_BUCKET_EXT:-evolution}"
    local s3_noco_bucket="${S3_NOCODB_BUCKET_EXT:-nocodb}"

    local evo_s3_enabled="false"
    local noco_storage_type="local"
    local active_storage="local"
    local pz_storage="local"

    if [ "$STORAGE_MODE" = "s3minio" ] || [ "$STORAGE_MODE" = "minio" ]; then
        evo_s3_enabled="true"
        noco_storage_type="s3"
        active_storage="amazon"
        pz_storage="local"
        s3_endpoint_val="http://${PREFIXO_CONTAINER}_s3minio:9000"
        s3_access_val="${TS_EMAIL}"
        s3_secret_val="${DB_PASSWORD}"
    elif [ "$STORAGE_MODE" = "s3_external" ]; then
        evo_s3_enabled="true"
        noco_storage_type="s3"
        active_storage="amazon"
        pz_storage="local"
    fi

    cat << EOF >> "$env_path"

# =========================================================================
# PARADIGMA E CONFIGURAÇÕES DE ARMAZENAMENTO (STORAGE_MODE & S3)
# =========================================================================
STORAGE_MODE="${STORAGE_MODE:-local}"
USE_S3MINIO="${USE_S3MINIO:-s}"
HOST_S3MINIO_API_PORT="9000"
HOST_S3MINIO_CONSOLE_PORT="9001"
CPU_S3MINIO=${CPU_S3MINIO:-${cpu_s3minio}}
MEM_S3MINIO=${MEM_S3MINIO:-${mem_s3minio}}
RES_S3MINIO=${RES_S3MINIO:-${res_s3minio}}
S3MINIO_API_REQUESTS_MAX=${S3MINIO_API_REQUESTS_MAX:-${s3_requests_max}}
S3_ENDPOINT_EXT="${S3_ENDPOINT_EXT}"
S3_REGION_EXT="${S3_REGION_EXT:-us-east-1}"
S3_ACCESS_KEY_EXT="${S3_ACCESS_KEY_EXT}"
S3_SECRET_KEY_EXT="${S3_SECRET_KEY_EXT}"
S3_CHATWOOT_BUCKET_EXT="${s3_cw_bucket}"
S3_POSTIZ_BUCKET_EXT="${s3_pz_bucket}"
S3_EVOLUTION_BUCKET_EXT="${s3_evo_bucket}"
S3_NOCODB_BUCKET_EXT="${s3_noco_bucket}"
S3_ENDPOINT="${s3_endpoint_val}"
S3_ENDPOINT_HOST="${PREFIXO_CONTAINER}_s3minio"
S3_PORT="9000"
S3_USE_SSL="false"
S3_REGION="${s3_region_val}"
S3_ACCESS_KEY_ID="${s3_access_val}"
S3_SECRET_ACCESS_KEY="${s3_secret_val}"
S3_CHATWOOT_BUCKET="${s3_cw_bucket}"
S3_POSTIZ_BUCKET="${s3_pz_bucket}"
S3_EVOLUTION_BUCKET="${s3_evo_bucket}"
S3_NOCODB_BUCKET="${s3_noco_bucket}"
EVOLUTION_S3_ENABLED="${evo_s3_enabled}"
NOCODB_STORAGE_TYPE="${noco_storage_type}"
ACTIVE_STORAGE_SERVICE="${active_storage}"
POSTIZ_STORAGE_PROVIDER="${pz_storage}"
EOF
}

# Roteamento de funções via parâmetros CLI (Padrão de Contrato Desacoplado)
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
    get_version|render_forensic_report|render_report|audit_health|inject_dashboard_card|inject_card|remove_dashboard_card|remove_card|purge_card|disable|teardown|inject_caddy_routes|inject_caddy|remove_caddy_routes|remove_caddy|start_container|wait_readiness|provision_infra|provision_buckets|provision_user|build_structure|provision_db)
        case "$ACTION" in
            render_report) render_forensic_report "${3:-localhost}" ;;
            inject_card) inject_dashboard_card ;;
            remove_card|purge_card) remove_dashboard_card ;;
            teardown) disable ;;
            inject_caddy) inject_caddy_routes ;;
            remove_caddy) remove_caddy_routes ;;
            provision_buckets) provision_infra ;;
            provision_db) ;;
            *) "$ACTION" "${3:-localhost}" ;;
        esac
        ;;
    all)
        build_structure
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
