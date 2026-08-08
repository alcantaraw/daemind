#!/bin/bash
set -e

CLIENT_ID="##TS_OAUTH_ID##"
CLIENT_SECRET="##TS_OAUTH_SECRET##"
TAILNET="##TS_EMAIL##"
# 1. DESCOBERTA DINÂMICA DO SEU PRÓPRIO CONTEXTO LOCAL
PREFIXO=$(hostname | sed 's/[-_][0-9]\+$//')
MY_LOCAL_IP=$(tailscale ip -4 | tr -d '\r\n ')

echo "➜ [SRE] Prefixo de Varredura: ${PREFIXO}"
echo "➜ [SRE] IP Local Protegido: ${MY_LOCAL_IP}"

# 2. Handshake OAuth
TOKEN_JSON=$(curl -s -d "client_id=${CLIENT_ID}" -d "client_secret=${CLIENT_SECRET}" "https://api.tailscale.com/api/v2/oauth/token")
ACCESS_TOKEN=$(echo "$TOKEN_JSON" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo "[ERRO TS] Falha no token. Abortando."
    exit 1
fi

DEVICES_JSON=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://api.tailscale.com/api/v2/tailnet/${TAILNET}/devices")

# 3. Loop de Limpeza com Guardrail Antisuicídio
echo "$DEVICES_JSON" | jq -c '.devices[] | select(.hostname | test("^'"$PREFIXO"'(-[0-9]+)?$"))' | while read -r device; do
    DEVICE_ID=$(echo "$device" | jq -r '.id')
    DEVICE_NAME=$(echo "$device" | jq -r '.name')
    DEVICE_IP=$(echo "$device" | jq -r '.addresses[0]')
    CONNECTED=$(echo "$device" | jq -r '.connectedToControl // false')

    # GUARDRAIL: Se o IP do dispositivo da API for igual ao IP da nossa máquina atual, IGNORA!
    if [ "$DEVICE_IP" = "$MY_LOCAL_IP" ]; then
        echo "🛡️ [GUARDRAIL] Protegendo o nó ativo atual: $DEVICE_NAME ($DEVICE_IP)"
        continue
    fi

    # Se estiver inativo (false ou null), expurga do painel
    if [ "$CONNECTED" = "false" ] || [ "$CONNECTED" = "null" ]; then
        echo "🚨 [PURGE] Removendo nó órfão inativo: $DEVICE_NAME (ID: $DEVICE_ID)"
        curl -s -X DELETE -u "$ACCESS_TOKEN:" "https://api.tailscale.com/api/v2/device/$DEVICE_ID" > /dev/null
    fi
done
