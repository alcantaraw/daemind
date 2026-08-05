#!/usr/bin/env bash
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO MINIO S3
# Especificação: Módulo desacoplado de gerenciamento, injeção Caddy, visual e relatório MinIO
# ===============================================================================

set -euo pipefail

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/core/config/.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE"; set +a
fi

minio_build_structure() {
    echo "➜ [SRE MINIO] Criando estrutura física de volumes e permissões do MinIO..."
    sudo mkdir -p "$TARGET_DIR"/volumes/minio_data/{postiz,chatwoot} 2>/dev/null || true
    if [ -n "${SUDO_USER:-}" ]; then
        sudo chown -R "$SUDO_USER:$SUDO_USER" "$TARGET_DIR/volumes/minio_data" 2>/dev/null || true
    else
        sudo chown -R 1000:1000 "$TARGET_DIR/volumes/minio_data" 2>/dev/null || true
    fi
}

minio_inject_caddy_routes() {
    echo "➜ [SRE MINIO] Injetando portas do MinIO S3 (:9000/:9001) no Caddyfile..."
    local CADDYFILE_PATH="$TARGET_DIR/core/config/Caddyfile"
    if [ -f "$CADDYFILE_PATH" ] && ! grep -q ':9000 {' "$CADDYFILE_PATH"; then
        cat << 'EOF' | sudo tee -a "$CADDYFILE_PATH" > /dev/null

:9000 {
    log {
        level error
    }
    reverse_proxy ${PREFIXO_CONTAINER}_minio:9000
}
:9001 {
    log {
        level error
    }
    reverse_proxy ${PREFIXO_CONTAINER}_minio:9001
}
EOF
    fi
}

minio_inject_dashboard_card() {
    echo "➜ [SRE MINIO] Injetando card do MinIO Console no portal de controle (index.html)..."
    local INDEX_PATH="$TARGET_DIR/core/html/index.html"
    if [ -f "$INDEX_PATH" ] && ! grep -q 'data-port="9001"' "$INDEX_PATH"; then
        sudo sed -i '/data-port="5000"/i \            <a href="#" data-port="9001" data-path="" class="card dynamic-link">\n                <div class="card-content">\n                    <div class="card-header">\n                        <div class="icon">🗄️</div>\n                        <div class="status-indicator"><div class="status-dot"></div> Online</div>\n                    </div>\n                    <h3>MinIO Console</h3>\n                    <p class="description">Armazenamento S3 soberano para gestão centralizada de mídias e arquivos.</p>\n                    <div class="card-footer">\n                        <span>Gateway: HTTP</span>\n                        <span class="port">:9001</span>\n                    </div>\n                </div>\n            </a>\n' "$INDEX_PATH" 2>/dev/null || true
    fi
}

minio_start_container() {
    echo "➜ [SRE MINIO] Subindo contêiner isolado via docker-compose.minio.yml..."
    cd "$TARGET_DIR"
    if [ -f "./core/config/docker-compose.minio.yml" ]; then
        sudo docker compose -f ./core/config/docker-compose.yml -f ./core/config/docker-compose.minio.yml up -d minio
    else
        sudo docker compose up -d minio 2>/dev/null || true
    fi
}

minio_wait_readiness() {
    echo "➜ [SRE MINIO] Validando prontidão de socket e healthcheck do MinIO..."
    local TENTATIVAS_MINIO=0
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' ${PREFIXO_CONTAINER}_minio 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS_MINIO=$((TENTATIVAS_MINIO+1))
        if [ "$TENTATIVAS_MINIO" -ge 30 ]; then
            echo "🚨 [ERRO FATAL MINIO] MinIO não atingiu estado saudável após 60s."
            exit 1
        fi
        sleep 2
    done
    echo "✔ [SUCESSO MINIO] MinIO S3 Server online e saudável!"
}

minio_provision_buckets() {
    echo "➜ [SRE MINIO] Garantindo buckets padrão (chatwoot e postiz) no MinIO S3..."
    sudo docker exec ${PREFIXO_CONTAINER}_minio mc alias set local http://localhost:9000 ${TS_EMAIL} ${DB_PASSWORD} >/dev/null 2>&1 || true
    sudo docker exec ${PREFIXO_CONTAINER}_minio mc ls local/chatwoot >/dev/null 2>&1 || sudo docker exec ${PREFIXO_CONTAINER}_minio mc mb local/chatwoot >/dev/null 2>&1 || true
    sudo docker exec ${PREFIXO_CONTAINER}_minio mc anonymous set download local/chatwoot >/dev/null 2>&1 || true
    sudo docker exec ${PREFIXO_CONTAINER}_minio mc ls local/postiz >/dev/null 2>&1 || sudo docker exec ${PREFIXO_CONTAINER}_minio mc mb local/postiz >/dev/null 2>&1 || true
    sudo docker exec ${PREFIXO_CONTAINER}_minio mc anonymous set download local/postiz >/dev/null 2>&1 || true
    echo "✔ [SUCESSO MINIO] Buckets criados e políticas de download público consolidadas."
}

minio_audit_health() {
    local ts_domain="${1:-localhost}"
    local health_minio=$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIXO_CONTAINER}_minio 2>/dev/null || echo "OFFLINE")
    local http_status="OFFLINE"

    if [ "$health_minio" = "healthy" ]; then
        http_status=$(curl -s -L -H "Host: ${ts_domain}" -o /dev/null -w "%{http_code}" --max-time 10 --retry 3 --retry-delay 2 "http://127.0.0.1:9001/" || echo "FALHOU")
    else
        http_status="CONTAINER_ERRO"
    fi

    echo "  ↳ Acesso MinIO Console:   http://${ts_domain}:9001  -> Status: [${http_status}]"
}

minio_get_version() {
    local container_name="${PREFIXO_CONTAINER}_minio"
    sudo docker exec "$container_name" minio --version 2>/dev/null | grep -o 'RELEASE\.[0-9T-]*' || echo ""
}

minio_render_forensic_report() {
    local ts_domain="${1:-localhost}"
    echo "  🗄️ Armazenamento S3 (MinIO)"
    echo "    ↳ Console Web:                     http://${ts_domain}:9001/login"
    echo "    ↳ S3 API:                          http://${ts_domain}:9000"
    echo "    ↳ Healthcheck (Live):              http://${ts_domain}:9000/minio/health/live"
    echo "    ↳ Healthcheck (Ready):             http://${ts_domain}:9000/minio/health/ready"
    echo "    ↳ MinIO CLI:                       mc ready local"
    echo ""
}

# Roteamento de funções via parâmetros CLI
case "${2:-all}" in
    get_version)
        minio_get_version
        ;;
    render_report)
        minio_render_forensic_report "${3:-localhost}"
        ;;
    audit_health)
        minio_audit_health "${3:-localhost}"
        ;;
    inject_card)
        minio_inject_dashboard_card
        ;;
    inject_caddy)
        minio_inject_caddy_routes
        ;;
    wait_readiness)
        minio_wait_readiness
        ;;
    provision_buckets)
        minio_provision_buckets
        ;;
    build_structure)
        minio_build_structure
        ;;
    all)
        minio_build_structure
        minio_inject_caddy_routes
        minio_inject_dashboard_card
        minio_start_container
        minio_wait_readiness
        minio_provision_buckets
        ;;
    *)
        minio_build_structure
        minio_inject_caddy_routes
        minio_inject_dashboard_card
        minio_start_container
        minio_wait_readiness
        minio_provision_buckets
        ;;
esac
