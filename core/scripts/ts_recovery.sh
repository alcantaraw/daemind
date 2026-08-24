#!/bin/bash
set -e

# SRE Context: Absorve os segredos locais diretamente do .env protegido
cd /opt/daemind 2>/dev/null || true
ENV_FILE="/opt/daemind/core/config/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="/opt/daemind/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="./.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "[ERRO] Arquivo .env não localizado em $ENV_FILE."
    exit 1
fi
set -a; source "$ENV_FILE"; set +a

echo "=== [SRE RECOVERY] Iniciando protocolo de reautenticação perimetral ==="

# 1. Desliga instâncias fantasmas do Funnel
echo "➜ Limpando escopo de túneis antigos..."
sudo tailscale funnel --https=443 off 2>/dev/null || true

# 2. Força o handshake limpo no painel usando a chave mestre do cliente com o reset protetivo
echo "➜ Reautenticando nó ativo na Tailnet de forma estrita..."
sudo tailscale up --reset --auth-key="${TS_OAUTH_SECRET}" --advertise-tags=tag:production --accept-dns=true --force-reauth

# 3. Reseta o daemon do sistema operacional para limpar o cache de memória do Kernel
echo "➜ Resetando barramento do sistema operacional (tailscaled)..."
sudo systemctl restart tailscaled
sleep 5

# 4. Reconstrói o tunnel do Funnel apontando para o socket do Gateway
echo "➜ Ativando novo túnel do Funnel em background..."
sudo tailscale funnel --bg ${PROXY_PORT:-${HOST_CADDY_PORT:-80}}

# 5. Executa a validação dinâmica de handshake externo
echo "=== [SRE AUDIT] Validando estabilidade externa do Gateway ==="
sleep 5
TS_DOMAIN=$(tailscale status --json 2>/dev/null | grep -A 10 '"Self":' | grep '"DNSName"' | head -n 1 | cut -d'"' -f4 | sed 's/\.$//' | tr -d '\r\n ' || true)

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
