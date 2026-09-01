#!/usr/bin/env bash
# ===============================================================================
# DAEMIND SRE - SINCRONIZADOR & ORQUESTRADOR DECLARATIVO DE TEMPLATES N8N
# Especificação: Injeção idempotente, validação de dependências USE_* e auto-ativação
# ===============================================================================

set -eo pipefail

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
elif [ -f "./.env" ]; then
    set -a; source "./.env" 2>/dev/null || true; set +a
fi

PREFIX="${PREFIXO_CONTAINER:-daemind}"
TEMPLATES_DIR="$TARGET_DIR/core/templates/n8n"
[ ! -d "$TEMPLATES_DIR" ] && TEMPLATES_DIR="./core/templates/n8n"

echo "====================================================================="
echo "➜ [SRE N8N SYNC] Sincronizador Declarativo de Templates de Automação"
echo "====================================================================="

# 1. Validação de pré-requisitos da stack
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PREFIX}_n8n$"; then
    echo "➜ [AVISO N8N] Contêiner '${PREFIX}_n8n' não está em execução. Pulando sincronização."
    exit 0
fi

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PREFIX}_postgres$"; then
    echo "➜ [AVISO N8N] Contêiner '${PREFIX}_postgres' não está em execução. Pulando sincronização."
    exit 0
fi

if [ ! -d "$TEMPLATES_DIR" ]; then
    echo "➜ [AVISO N8N] Diretório de templates não localizado em '$TEMPLATES_DIR'. Pulando."
    exit 0
fi

# 2. Helpers para checagem de flags USE_*
is_active() {
    local val="${1:-n}"
    [[ "$val" =~ ^[Ss1Tt]$ ]] || [ "$val" = "true" ]
}

check_dependencies() {
    local tpl_file="$1"
    local base_name=$(basename "$tpl_file")
    local missing=""

    case "$base_name" in
        "00_sre_faxina_reativa_modelos_ia_404.json")
            # LiteLLM faz parte do Core Imutável
            ;;
        "01_ecommerce_recuperacao_carrinho_whatsapp.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ! is_active "${USE_SHLINK:-n}" && missing="${missing}USE_SHLINK "
            ;;
        "02_cobranca_pix_pendente_com_lembrete.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ;;
        "03_rastreamento_envio_pos_venda.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ! is_active "${USE_SHLINK:-n}" && missing="${missing}USE_SHLINK "
            ;;
        "04_ocr_comprovante_pix_ia_docling.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ;;
        "05_marketing_360_postiz_listmonk_shlink.json")
            ! is_active "${USE_LISTMONK:-n}" && missing="${missing}USE_LISTMONK "
            ! is_active "${USE_SHLINK:-n}" && missing="${missing}USE_SHLINK "
            ;;
        "06_alerta_estoque_insumos_nocodb.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ;;
        "07_recuperacao_boleto_pix_urgencia_estoque.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ;;
        "08_upsell_cross_sell_pos_aprovacao_shlink.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ! is_active "${USE_SHLINK:-n}" && missing="${missing}USE_SHLINK "
            ;;
        "09_reativacao_clientes_inativos_rfm_listmonk.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ! is_active "${USE_SHLINK:-n}" && missing="${missing}USE_SHLINK "
            ;;
        "10_sdr_qualificador_leads_whatsapp_chatwoot.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ;;
        "11_audio_transcriber_resumo_chatwoot.json")
            ! is_active "${USE_CHATWOOT:-n}" && missing="${missing}USE_CHATWOOT "
            ;;
        "12_alerta_proativo_atraso_entrega.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ;;
        "13_auditor_over_attribution_ads_vs_caixa.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ;;
        "14_copiloto_executivo_text_to_sql_whatsapp.json")
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ;;
        "15_content_repurposing_postiz_listmonk.json")
            ! is_active "${USE_LISTMONK:-n}" && missing="${missing}USE_LISTMONK "
            ! is_active "${USE_SHLINK:-n}" && missing="${missing}USE_SHLINK "
            ! is_active "${USE_EVOLUTION:-n}" && missing="${missing}USE_EVOLUTION "
            ;;
        "16_chatbot_ia_atendimento_n1_chatwoot.json")
            ! is_active "${USE_CHATWOOT:-n}" && missing="${missing}USE_CHATWOOT "
            ;;
        "17_ecommerce_loja_integrada_ingestao_nativa.json")
            if [ -z "${LOJA_INTEGRADA_API_KEY:-}" ] && [ -z "${LOJAINTEGRADA_API_KEY:-}" ] && ! is_active "${USE_LOJA_INTEGRADA:-n}" && ! is_active "${USE_LOJAINTEGRADA:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}LOJA_INTEGRADA_API_KEY "
            fi
            ;;
        "18_ecommerce_shopify_vendas_e_tags_crm.json")
            if [ -z "${SHOPIFY_ACCESS_TOKEN:-}" ] && [ -z "${SHOPIFY_API_KEY:-}" ] && ! is_active "${USE_SHOPIFY:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}SHOPIFY_ACCESS_TOKEN "
            fi
            ;;
        "19_ecommerce_nuvemshop_pedidos_e_carrinhos.json")
            if [ -z "${NUVEMSHOP_ACCESS_TOKEN:-}" ] && [ -z "${NUVEMSHOP_API_KEY:-}" ] && ! is_active "${USE_NUVEMSHOP:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}NUVEMSHOP_ACCESS_TOKEN "
            fi
            ;;
        "20_ecommerce_woocommerce_pedidos_e_custom_fields.json")
            if [ -z "${WOOCOMMERCE_CONSUMER_KEY:-}" ] && ! is_active "${USE_WOOCOMMERCE:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}WOOCOMMERCE_CONSUMER_KEY "
            fi
            ;;
        "21_ecommerce_vtex_orders_e_oms.json")
            if [ -z "${VTEX_APP_KEY:-}" ] && ! is_active "${USE_VTEX:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}VTEX_APP_KEY "
            fi
            ;;
        "22_ecommerce_tray_yampi_cartpanda_checkout.json")
            if [ -z "${CHECKOUT_API_KEY:-}" ] && [ -z "${YAMPI_TOKEN:-}" ] && [ -z "${CARTPANDA_TOKEN:-}" ] && ! is_active "${USE_CHECKOUT:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}CHECKOUT_API_KEY "
            fi
            ;;
        "23_marketplace_mercadolivre_pedidos_taxas.json")
            if [ -z "${MERCADOLIVRE_ACCESS_TOKEN:-}" ] && [ -z "${MERCADOLIVRE_CLIENT_ID:-}" ] && ! is_active "${USE_MERCADOLIVRE:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}MERCADOLIVRE_ACCESS_TOKEN "
            fi
            ;;
        "24_marketplace_shopee_pedidos_e_escrow.json")
            if [ -z "${SHOPEE_PARTNER_KEY:-}" ] && ! is_active "${USE_SHOPEE:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}SHOPEE_PARTNER_KEY "
            fi
            ;;
        "25_marketplace_amazon_sp_api_orders.json")
            if [ -z "${AMAZON_REFRESH_TOKEN:-}" ] && ! is_active "${USE_AMAZON:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}AMAZON_REFRESH_TOKEN "
            fi
            ;;
        "26_marketplace_magalu_olist_anymarket.json")
            if [ -z "${ANYMARKET_TOKEN:-}" ] && [ -z "${OLIST_TOKEN:-}" ] && [ -z "${MAGALU_TOKEN:-}" ] && ! is_active "${USE_ANYMARKET:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}ANYMARKET_TOKEN "
            fi
            ;;
        "27_erp_bling_tiny_faturamento_nfe_danfe.json")
            if [ -z "${BLING_API_KEY:-}" ] && [ -z "${TINY_API_KEY:-}" ] && ! is_active "${USE_BLING:-n}" && ! is_active "${USE_TINY:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}BLING_API_KEY "
            fi
            ;;
        "28_logistica_melhorenvio_frenet_etiquetas.json")
            ! is_active "${USE_SHLINK:-n}" && missing="${missing}USE_SHLINK "
            if [ -z "${MELHORENVIO_TOKEN:-}" ] && [ -z "${FRENET_TOKEN:-}" ] && ! is_active "${USE_MELHORENVIO:-n}" && ! is_active "${USE_LOGISTICA:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}MELHORENVIO_TOKEN "
            fi
            ;;
        "29_gateway_asaas_stripe_pagarme_cobrancas.json")
            if [ -z "${ASAAS_API_KEY:-}" ] && [ -z "${STRIPE_SECRET_KEY:-}" ] && [ -z "${PAGARME_API_KEY:-}" ] && ! is_active "${USE_ASAAS:-n}" && ! is_active "${USE_GATEWAYS:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}ASAAS_API_KEY "
            fi
            ;;
        "30_delivery_ifood_rappi_pedidos_tempo_real.json")
            if [ -z "${IFOOD_CLIENT_ID:-}" ] && [ -z "${RAPPI_API_KEY:-}" ] && ! is_active "${USE_IFOOD:-n}" && ! is_active "${USE_DELIVERY:-n}" && ! is_active "${USE_ECOMMERCE_ALL:-s}" && ! is_active "${USE_EVOLUTION:-n}"; then
                missing="${missing}IFOOD_CLIENT_ID "
            fi
            ;;
        "31_hub_universal_roteador_webhooks_crm.json")
            ;;
        *)
            ;;
    esac

    echo "$missing"
}

# 3. Varredura e sincronização idempotente de cada template
local_vol_path="$TARGET_DIR/volumes/n8n_data"
[ ! -d "$local_vol_path" ] && local_vol_path="./volumes/n8n_data"

TOTAL_APTOS=0
TOTAL_IMPORTADOS=0
TOTAL_PULADOS=0

for tpl in "$TEMPLATES_DIR"/*.json; do
    [ ! -f "$tpl" ] && continue
    
    file_name=$(basename "$tpl")
    
    # Extrai o nome do workflow do JSON
    wf_name=$(python3 -c "import json; d=json.load(open('$tpl')); print(d.get('name', ''))" 2>/dev/null || grep -o '"name": *"[^"]*"' "$tpl" | head -n1 | cut -d'"' -f4 || echo "$file_name")
    
    missing_deps=$(check_dependencies "$tpl")
    
    if [ -n "$missing_deps" ]; then
        echo "➜ [SKIP N8N] $file_name"
        echo "   ↳ Motivo: Dependências inativas ($missing_deps)"
        TOTAL_PULADOS=$((TOTAL_PULADOS + 1))
        continue
    fi
    
    TOTAL_APTOS=$((TOTAL_APTOS + 1))
    
    # Checa existência no PostgreSQL
    wf_escaped_name=$(echo "$wf_name" | sed "s/'/''/g")
    WF_ID=$(docker exec ${PREFIX}_postgres psql -U "${DB_USER:-postgres}" -d "${PREFIX}_db" -t -A -c "SELECT id FROM n8n_schema.workflow_entity WHERE name = '$wf_escaped_name' LIMIT 1;" 2>/dev/null || echo "")
    
    if [ -n "$WF_ID" ]; then
        # Garante que o workflow existente esteja publicado e ativo
        docker exec -u node ${PREFIX}_n8n n8n publish:workflow --id="$WF_ID" > /dev/null 2>&1 || docker exec -u node ${PREFIX}_n8n n8n update:workflow --id="$WF_ID" --active=true > /dev/null 2>&1 || true
        echo "✔ [IDEMPOTÊNCIA N8N] '$wf_name' já cadastrado (ID: $WF_ID). Ativado."
    else
        echo "➜ [IMPORTANDO N8N] Injetando '$wf_name'..."
        
        tmp_target="$local_vol_path/tmp_sync_${file_name}"
        cp "$tpl" "$tmp_target" 2>/dev/null || true
        
        if [ -f "$tmp_target" ]; then
            # Substituição de placeholders se presentes
            sed -i "s|##LITELLM_HOST##|${PREFIX}_litellm|g" "$tmp_target" 2>/dev/null || true
            sed -i "s|##LITELLM_KEY##|${LITELLM_MASTER_KEY}|g" "$tmp_target" 2>/dev/null || true
            
            # Importa para o n8n
            docker exec -u node ${PREFIX}_n8n n8n import:workflow --input="/home/node/.n8n/tmp_sync_${file_name}" > /dev/null 2>&1 || true
            
            # Publica e ativa o workflow importado
            WF_ID=$(docker exec ${PREFIX}_postgres psql -U "${DB_USER:-postgres}" -d "${PREFIX}_db" -t -A -c "SELECT id FROM n8n_schema.workflow_entity WHERE name = '$wf_escaped_name' LIMIT 1;" 2>/dev/null || echo "")
            if [ -n "$WF_ID" ]; then
                docker exec -u node ${PREFIX}_n8n n8n publish:workflow --id="$WF_ID" > /dev/null 2>&1 || docker exec -u node ${PREFIX}_n8n n8n update:workflow --id="$WF_ID" --active=true > /dev/null 2>&1 || true
                echo "✔ [SUCESSO N8N] '$wf_name' importado e ativado com sucesso (ID: $WF_ID)."
                TOTAL_IMPORTADOS=$((TOTAL_IMPORTADOS + 1))
            fi
            
            rm -f "$tmp_target" 2>/dev/null || true
        fi
    fi
done

echo "====================================================================="
echo "✔ [SRE N8N SYNC CONCLUÍDO] Aptos: $TOTAL_APTOS | Novos: $TOTAL_IMPORTADOS | Pulados: $TOTAL_PULADOS"
echo "====================================================================="
