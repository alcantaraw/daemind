#!/bin/bash
set -e

# SRE Context: Localiza o diretório raiz e .env
TARGET_DIR="/opt/daemind"
[ ! -d "$TARGET_DIR" ] && TARGET_DIR="$(pwd)"

ENV_FILE="${TARGET_DIR}/core/config/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="${TARGET_DIR}/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="./.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE"; set +a
fi

# Se o script unificado install_0ts.sh existir, delega para a ação recovery nativa
if [ -f "${TARGET_DIR}/core/scripts/install_0ts.sh" ]; then
    exec bash "${TARGET_DIR}/core/scripts/install_0ts.sh" "${TARGET_DIR}" recovery
fi

echo "=== [SRE RECOVERY] Iniciando protocolo de reautenticação perimetral ==="

# 1. Desliga instâncias fantasmas do Funnel
echo "➜ Limpando escopo de túneis antigos..."
sudo tailscale funnel --https=443 off 2>/dev/null || true

# 2. Força o handshake limpo usando a chave com ephemeral=false&preauthorized=true
echo "➜ Reautenticando nó ativo na Tailnet de forma estrita..."
AUTH_SECRET="${TS_OAUTH_SECRET:-${CLIENT_SECRET}}"
if [ -n "$AUTH_SECRET" ] && [ "$AUTH_SECRET" != "bypass_sec" ]; then
    sudo tailscale up --reset --auth-key="${AUTH_SECRET}?ephemeral=false&preauthorized=true" --advertise-tags=tag:production --accept-dns=true --force-reauth
else
    sudo tailscale up --reset --advertise-tags=tag:production --accept-dns=true --force-reauth
fi

# 3. Reseta o daemon do sistema operacional para limpar o cache de memória do Kernel
echo "➜ Resetando barramento do sistema operacional (tailscaled)..."
sudo systemctl restart tailscaled
sleep 5

# 4. Reconstrói os túneis do Funnel apontando para os sockets do Gateway e Evolution
echo "➜ Ativando novos túneis do Funnel..."
sudo tailscale funnel --https=443 --bg ${PROXY_PORT:-${HOST_CADDY_PORT:-80}} > /dev/null 2>&1 || true
if [ "${USE_EVOLUTION:-s}" = "s" ]; then
    sudo tailscale funnel --https=8443 --bg 18081 > /dev/null 2>&1 || true
fi

# 5. Executa a validação dinâmica de handshake externo
echo "=== [SRE AUDIT] Validando estabilidade externa do Gateway ==="
sleep 5
TS_DOMAIN=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName' 2>/dev/null | sed 's/\.$//' || true)
[ -z "$TS_DOMAIN" ] && TS_DOMAIN="${DOMAIN:-localhost}"

HTTP_GATEWAY=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${TS_DOMAIN}/healthz" || echo "000")

echo "====================================================================="
echo "➜ Portal Gateway (443):         [$HTTP_GATEWAY]"
echo "====================================================================="
if [ "$HTTP_GATEWAY" = "200" ]; then
    echo "       [SUCESSO ABSOLUTO] ECOSSISTEMA TOTALMENTE RESTABELECIDO       "
else
    echo "       [ALERTA] Ambiente ativo, mas com oscilação de barramento.     "
fi
echo "====================================================================="
