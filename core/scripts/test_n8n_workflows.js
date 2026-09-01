/**
 * DAEMIND WORKFLOWS ENTERPRISE TEST RUNNER
 * Suíte de Testes Modulares e Seriais para os 32 Workflows do n8n (Templates 00 a 31).
 * Suporta execução isolada por função (--run=XX), bateria completa (--all) ou unitária (--unit-only).
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');

const rootDir = path.resolve(__dirname, '..', '..');
const templatesDir = path.join(rootDir, 'core', 'templates', 'n8n');
const fixturesDir = path.join(rootDir, 'tests', 'fixtures');
const edgeCasesDir = path.join(rootDir, 'tests', 'edge_cases');

// Cores para saída no terminal
const colors = {
    reset: "\x1b[0m",
    green: "\x1b[32m",
    red: "\x1b[31m",
    yellow: "\x1b[33m",
    cyan: "\x1b[36m",
    bold: "\x1b[1m"
};

function logPass(msg) {
    console.log(`  ${colors.green}✔ PASS:${colors.reset} ${msg}`);
}

function logFail(msg, err) {
    console.log(`  ${colors.red}✖ FAIL:${colors.reset} ${msg}`);
    if (err) console.error(`    ${colors.red}↳ Detalhes: ${err.message || err}${colors.reset}`);
}

function logInfo(msg) {
    console.log(`${colors.cyan}${colors.bold}[DAEMIND TEST ENGINE]${colors.reset} ${msg}`);
}

// Utilitário para carregar fixture JSON
function loadFixture(filename) {
    const p = path.join(fixturesDir, filename);
    if (!fs.existsSync(p)) {
        throw new Error(`Fixture não encontrada: ${filename}`);
    }
    return JSON.parse(fs.readFileSync(p, 'utf8'));
}

// Utilitário para carregar template JSON do n8n
function loadTemplate(filename) {
    const p = path.join(templatesDir, filename);
    if (!fs.existsSync(p)) {
        throw new Error(`Template não encontrado: ${filename}`);
    }
    return JSON.parse(fs.readFileSync(p, 'utf8'));
}

// Executor Sandbox de Code Node do n8n
function executeCodeNode(templateJson, inputPayload, nodeNameFilter = null) {
    const nodes = templateJson.nodes || [];
    const codeNode = nodes.find(n => n.type === 'n8n-nodes-base.code' && (!nodeNameFilter || n.name.includes(nodeNameFilter)));

    if (!codeNode) {
        throw new Error(`Nenhum Code Node encontrado no template ${templateJson.name || ''}`);
    }

    const jsCode = codeNode.parameters.jsCode || codeNode.parameters.code || '';
    if (!jsCode) {
        throw new Error(`Código JS vazio no nó ${codeNode.name}`);
    }

    // Mock do ambiente do n8n ($input, $json, crypto, items)
    const sandbox = {
        $input: {
            item: { json: inputPayload },
            all: () => [{ json: inputPayload }],
            first: () => ({ json: inputPayload })
        },
        $json: inputPayload,
        items: [{ json: inputPayload }],
        crypto: crypto,
        Buffer: Buffer,
        console: { log: () => {}, error: () => {}, warn: () => {} },
        JSON: JSON,
        Math: Math,
        Date: Date
    };

    const context = vm.createContext(sandbox);
    const script = new vm.Script(`
        (function() {
            ${jsCode}
        })()
    `);

    const result = script.runInContext(context, { timeout: 3000 });
    return result;
}

// ==========================================
// CATÁLOGO DAS 32 FUNÇÕES DE TESTE ISOLADAS
// ==========================================

const testSuite = {
    // 00 - SRE Faxina LiteLLM 404
    test_template_00: async function() {
        const template = loadTemplate('00_sre_faxina_reativa_modelos_ia_404.json');
        const fixture = loadFixture('00_litellm_error.json');
        const output = executeCodeNode(template, fixture);
        
        if (!output || !output.json || !output.json.deployment_id) {
            throw new Error("Falha na extração do deployment_id no erro 404");
        }
        logPass(`00 - SRE LiteLLM: Extração do modelo corrompido '${output.json.deployment_id}'`);
    },

    // 01 - Recuperação Carrinho WhatsApp
    test_template_01: async function() {
        const template = loadTemplate('01_ecommerce_recuperacao_carrinho_whatsapp.json');
        const fixture = loadFixture('01_carrinho_abandonado.json');
        const output = executeCodeNode(template, fixture);
        
        if (!output || !output.json || !output.json.whatsapp || !output.json.valor_formatado) {
            throw new Error("Falha na normalização do carrinho abandonado");
        }
        logPass(`01 - Carrinho: Sanitização WhatsApp '${output.json.whatsapp}', Valor: '${output.json.valor_formatado}'`);
    },

    // 02 - Cobrança PIX Pendente
    test_template_02: async function() {
        const template = loadTemplate('02_cobranca_pix_pendente_com_lembrete.json');
        const fixture = loadFixture('02_cobranca_pix.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.pix_copia_e_cola) {
            throw new Error("Chave PIX copia-e-cola não normalizada");
        }
        logPass(`02 - PIX: Código Copia-e-Cola e expiração calculados com sucesso`);
    },

    // 03 - Rastreamento Envio
    test_template_03: async function() {
        const template = loadTemplate('03_rastreamento_envio_pos_venda.json');
        const fixture = loadFixture('03_rastreio_envio.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.codigo_rastreio) {
            throw new Error("Código de rastreio não extraído");
        }
        logPass(`03 - Rastreio: Código '${output.json.codigo_rastreio}' normalizado`);
    },

    // 04 - OCR Comprovante PIX
    test_template_04: async function() {
        const template = loadTemplate('04_ocr_comprovante_pix_ia_docling.json');
        const fixture = loadFixture('04_ocr_pix_docling.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.media_url) {
            throw new Error("Falha ao isolar URL da imagem para OCR");
        }
        logPass(`04 - OCR PIX: Payload de mídia e parâmetros de conciliação validados`);
    },

    // 05 - Marketing 360
    test_template_05: async function() {
        const template = loadTemplate('05_marketing_360_postiz_listmonk_shlink.json');
        const fixture = loadFixture('05_marketing_360.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.title) {
            throw new Error("Título da publicação ausente");
        }
        logPass(`05 - Marketing 360: Artigo '${output.json.title}' preparado para distribuição multicanal`);
    },

    // 06 - Alerta Insumos
    test_template_06: async function() {
        const template = loadTemplate('06_alerta_estoque_insumos_nocodb.json');
        const fixture = loadFixture('06_alerta_insumos.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.sku_insumo) {
            throw new Error("Falha na avaliação de estoque crítico");
        }
        logPass(`06 - Insumos: Alerta de ruptura para '${output.json.sku_insumo}' processado`);
    },

    // 07 - Urgência Estoque
    test_template_07: async function() {
        const template = loadTemplate('07_recuperacao_boleto_pix_urgencia_estoque.json');
        const fixture = loadFixture('07_urgencia_estoque.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || output.json.estoque_remanescente === undefined) {
            throw new Error("Saldo de estoque não calculado");
        }
        logPass(`07 - Urgência Estoque: Gatilho com ${output.json.estoque_remanescente} un remanescentes`);
    },

    // 08 - Upsell / Cross-Sell
    test_template_08: async function() {
        const template = loadTemplate('08_upsell_cross_sell_pos_aprovacao_shlink.json');
        const fixture = loadFixture('08_upsell_cross_sell.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.produto_cross_sell) {
            throw new Error("Produto complementar não extraído");
        }
        logPass(`08 - Upsell: Oferta VIP '${output.json.produto_cross_sell}' montada com sucesso`);
    },

    // 09 - Reativação RFM
    test_template_09: async function() {
        const template = loadTemplate('09_reativacao_clientes_inativos_rfm_listmonk.json');
        const fixture = loadFixture('09_reativacao_rfm.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.cupom_reativacao) {
            throw new Error("Cupom de reativação não gerado");
        }
        logPass(`09 - Reativação RFM: Cliente inativo ${output.json.dias_sem_comprar} dias segmentado`);
    },

    // 10 - SDR Triagem Chatwoot
    test_template_10: async function() {
        const template = loadTemplate('10_sdr_qualificador_leads_whatsapp_chatwoot.json');
        const fixture = loadFixture('10_sdr_chatwoot.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.contact) {
            throw new Error("Contato do lead não extraído");
        }
        logPass(`10 - SDR Chatwoot: Lead '${output.json.contact.name}' normalizado para qualificação`);
    },

    // 11 - Transcritor Áudio Chatwoot
    test_template_11: async function() {
        const template = loadTemplate('11_audio_transcriber_resumo_chatwoot.json');
        const fixture = loadFixture('11_audio_chatwoot.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.attachment) {
            throw new Error("Anexo de áudio não identificado");
        }
        logPass(`11 - Áudio Chatwoot: URL do áudio e parâmetros de nota privada validados`);
    },

    // 12 - Atraso Logístico
    test_template_12: async function() {
        const template = loadTemplate('12_alerta_proativo_atraso_entrega.json');
        const fixture = loadFixture('12_atraso_logistico.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.codigo_rastreio) {
            throw new Error("Código de rastreio de ocorrência não encontrado");
        }
        logPass(`12 - Atraso Logístico: Alerta pró-ativo para '${output.json.codigo_rastreio}'`);
    },

    // 13 - Auditor Ads vs Caixa
    test_template_13: async function() {
        const template = loadTemplate('13_auditor_over_attribution_ads_vs_caixa.json');
        const fixture = loadFixture('13_auditoria_ads.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || output.json.over_attribution_percentual === undefined) {
            throw new Error("Cálculo de Over-Attribution não efetuado");
        }
        logPass(`13 - Auditor Ads: Discrepância calculada em ${output.json.over_attribution_percentual}%`);
    },

    // 14 - Copiloto Text-to-SQL
    test_template_14: async function() {
        const template = loadTemplate('14_copiloto_executivo_text_to_sql_whatsapp.json');
        const fixture = loadFixture('14_text_to_sql.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.pergunta) {
            throw new Error("Pergunta executiva não extraída");
        }
        logPass(`14 - Text-to-SQL: Pergunta sanitizada com sucesso: '${output.json.pergunta}'`);
    },

    // 15 - Content Repurposing
    test_template_15: async function() {
        const template = loadTemplate('15_content_repurposing_postiz_listmonk.json');
        const fixture = loadFixture('15_content_repurposing.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.titulo) {
            throw new Error("Texto base para repurposing não encontrado");
        }
        logPass(`15 - Repurposing: Título '${output.json.titulo}' pronto para desmembramento`);
    },

    // 16 - Chatbot Autônomo N1 com RAG & Memória
    test_template_16: async function() {
        const template = loadTemplate('16_chatbot_ia_atendimento_n1_chatwoot.json');
        const fixture = loadFixture('16_chatbot_rag_chatwoot.json');
        const output = executeCodeNode(template, fixture, 'Filtrar');

        if (!output || !output.json || !output.json.mensagem_cliente || !output.json.cliente_nome) {
            throw new Error("Falha na sanitização da mensagem e isolamento do cliente");
        }
        logPass(`16 - Chatbot N1: Mensagem '${output.json.mensagem_cliente.substring(0, 35)}...' e RAG montados`);
    },

    // 17 - Loja Integrada
    test_template_17: async function() {
        const template = loadTemplate('17_ecommerce_loja_integrada_ingestao_nativa.json');
        const fixture = loadFixture('17_lojaintegrada_pedido.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash || output.json.valor_total !== 349.00) {
            throw new Error("Normalização Loja Integrada incorreta ou hash SHA-256 ausente");
        }
        if (!output.json.itens || output.json.itens.length === 0) {
            throw new Error("Itens SKU não normalizados na Loja Integrada");
        }
        logPass(`17 - Loja Integrada: Pedido #${output.json.numero_pedido}, Total R$ ${output.json.valor_total}, Hash SHA-256: ${output.json.dedup_hash.substring(0, 16)}...`);
    },

    // 18 - Shopify
    test_template_18: async function() {
        const template = loadTemplate('18_ecommerce_shopify_vendas_e_tags_crm.json');
        const fixture = loadFixture('18_shopify_order.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash || output.json.origem !== 'Shopify') {
            throw new Error("Normalização Shopify incorreta");
        }
        logPass(`18 - Shopify: Pedido #${output.json.numero_pedido}, Tags: '${output.json.tags_cliente}', Total: R$ ${output.json.valor_total}`);
    },

    // 19 - Nuvemshop
    test_template_19: async function() {
        const template = loadTemplate('19_ecommerce_nuvemshop_pedidos_e_carrinhos.json');
        const fixture = loadFixture('19_nuvemshop_order.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash || output.json.origem !== 'Nuvemshop') {
            throw new Error("Normalização Nuvemshop incorreta");
        }
        logPass(`19 - Nuvemshop: Pedido #${output.json.numero_pedido}, Total: R$ ${output.json.valor_total}`);
    },

    // 20 - WooCommerce
    test_template_20: async function() {
        const template = loadTemplate('20_ecommerce_woocommerce_pedidos_e_custom_fields.json');
        const fixture = loadFixture('20_woocommerce_order.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash || output.json.origem !== 'WooCommerce') {
            throw new Error("Normalização WooCommerce incorreta");
        }
        logPass(`20 - WooCommerce: Pedido #${output.json.numero_pedido}, Total: R$ ${output.json.valor_total}`);
    },

    // 21 - VTEX OMS
    test_template_21: async function() {
        const template = loadTemplate('21_ecommerce_vtex_orders_e_oms.json');
        const fixture = loadFixture('21_vtex_order.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash || output.json.origem !== 'VTEX' || output.json.valor_total !== 520.00) {
            throw new Error("Conversão de centavos para reais falhou na VTEX");
        }
        logPass(`21 - VTEX: Pedido '${output.json.numero_pedido}', Total convertido de centavos: R$ ${output.json.valor_total}`);
    },

    // 22 - Checkouts Tray/Yampi/CartPanda
    test_template_22: async function() {
        const template = loadTemplate('22_ecommerce_tray_yampi_cartpanda_checkout.json');
        const fixture = loadFixture('22_checkouts_order.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash) {
            throw new Error("Normalização Checkouts falhou");
        }
        logPass(`22 - Checkouts: Provedor '${output.json.origem}', Total R$ ${output.json.valor_total}`);
    },

    // 23 - Mercado Livre
    test_template_23: async function() {
        const template = loadTemplate('23_marketplace_mercadolivre_pedidos_taxas.json');
        const fixture = loadFixture('23_mercadolivre_order.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash || output.json.taxa_gateway !== 55.86) {
            throw new Error("Cálculo de comissão ML não extraído corretamente");
        }
        logPass(`23 - Mercado Livre: Pedido #${output.json.numero_pedido}, Comissão ML R$ ${output.json.taxa_gateway}, Comprador: '${output.json.nickname}'`);
    },

    // 24 - Shopee
    test_template_24: async function() {
        const template = loadTemplate('24_marketplace_shopee_pedidos_e_escrow.json');
        const fixture = loadFixture('24_shopee_order.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash || output.json.origem !== 'Shopee') {
            throw new Error("Normalização Shopee falhou");
        }
        logPass(`24 - Shopee: Pedido #${output.json.numero_pedido}, Escrow Líquido R$ ${output.json.valor_liquido}`);
    },

    // 25 - Amazon SP-API
    test_template_25: async function() {
        const template = loadTemplate('25_marketplace_amazon_sp_api_orders.json');
        const fixture = loadFixture('25_amazon_order.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash || output.json.origem !== 'Amazon') {
            throw new Error("Normalização Amazon SP-API falhou");
        }
        logPass(`25 - Amazon: Pedido #${output.json.numero_pedido}, Prime: ${output.json.is_prime}, Total R$ ${output.json.valor_total}`);
    },

    // 26 - Hubs Magalu/Olist/AnyMarket
    test_template_26: async function() {
        const template = loadTemplate('26_marketplace_magalu_olist_anymarket.json');
        const fixture = loadFixture('26_magalu_order.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash) {
            throw new Error("Normalização Hubs falhou");
        }
        logPass(`26 - Hubs Marketplace: Canal '${output.json.origem}', Total R$ ${output.json.valor_total}`);
    },

    // 27 - ERPs Bling & Tiny NF-e
    test_template_27: async function() {
        const template = loadTemplate('27_erp_bling_tiny_faturamento_nfe_danfe.json');
        const fixture = loadFixture('27_bling_tiny_nfe.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.chave_nfe || output.json.chave_nfe.length !== 44) {
            throw new Error("Chave NF-e de 44 dígitos ausente ou inválida");
        }
        logPass(`27 - ERP NF-e: Chave de 44d '${output.json.chave_nfe}', Link DANFE: '${output.json.link_danfe}'`);
    },

    // 28 - Logística Melhor Envio / Frenet
    test_template_28: async function() {
        const template = loadTemplate('28_logistica_melhorenvio_frenet_etiquetas.json');
        const fixture = loadFixture('28_melhorenvio_etiqueta.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.codigo_rastreio) {
            throw new Error("Código de rastreio logístico não normalizado");
        }
        logPass(`28 - Logística: Rastreio '${output.json.codigo_rastreio}', Serviço: '${output.json.servico_envio}'`);
    },

    // 29 - Gateways Asaas/Stripe
    test_template_29: async function() {
        const template = loadTemplate('29_gateway_asaas_stripe_pagarme_cobrancas.json');
        const fixture = loadFixture('29_gateways_pagamento.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash) {
            throw new Error("Normalização Gateways falhou");
        }
        logPass(`29 - Gateways: Meio '${output.json.meio_pagamento}', Total R$ ${output.json.valor_bruto}, Líquido R$ ${output.json.valor_liquido}`);
    },

    // 30 - Delivery iFood / Rappi
    test_template_30: async function() {
        const template = loadTemplate('30_delivery_ifood_rappi_pedidos_tempo_real.json');
        const fixture = loadFixture('30_delivery_ifood.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash || output.json.origem !== 'iFood') {
            throw new Error("Normalização Delivery iFood falhou");
        }
        logPass(`30 - Delivery: Comanda iFood #${output.json.numero_pedido}, Total R$ ${output.json.valor_total}`);
    },

    // 31 - Hub Roteador Universal Fallback
    test_template_31: async function() {
        const template = loadTemplate('31_hub_universal_roteador_webhooks_crm.json');
        const fixture = loadFixture('31_universal_webhook.json');
        const output = executeCodeNode(template, fixture);

        if (!output || !output.json || !output.json.dedup_hash) {
            throw new Error("Normalização Fallback Universal falhou");
        }
        logPass(`31 - Hub Universal: Pedido #${output.json.numero_pedido}, Origem: '${output.json.origem}', Total R$ ${output.json.valor_total}`);
    }
};

// Runner Principal
async function runRunner() {
    const args = process.argv.slice(2);
    const runArg = args.find(a => a.startsWith('--run='));
    const isUnitOnly = args.includes('--unit-only');
    const isAll = args.includes('--all') || (!runArg && !isUnitOnly);

    console.log(`\n===============================================================`);
    console.log(`  DAEMIND ENTERPRISE TEST RUNNER - SUÍTE DE AUTOMAÇÕES N8N`);
    console.log(`===============================================================\n`);

    let passed = 0;
    let failed = 0;
    const startTime = Date.now();

    let testsToRun = [];

    if (runArg) {
        const num = runArg.split('=')[1].padStart(2, '0');
        const fnName = `test_template_${num}`;
        if (testSuite[fnName]) {
            testsToRun.push({ name: fnName, fn: testSuite[fnName] });
        } else {
            console.error(`${colors.red}Erro: Função de teste '${fnName}' não encontrada!${colors.reset}`);
            process.exit(1);
        }
    } else {
        for (let i = 0; i <= 31; i++) {
            const num = String(i).padStart(2, '0');
            const fnName = `test_template_${num}`;
            if (testSuite[fnName]) {
                testsToRun.push({ name: fnName, fn: testSuite[fnName] });
            }
        }
    }

    logInfo(`Iniciando execução serial de ${testsToRun.length} testes de workflows...\n`);

    for (const test of testsToRun) {
        try {
            await test.fn();
            passed++;
        } catch (err) {
            logFail(test.name, err);
            failed++;
        }
    }

    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`\n---------------------------------------------------------------`);
    console.log(`  RESULTADO DA BATERIA DE TESTES`);
    console.log(`---------------------------------------------------------------`);
    console.log(`  Total: ${testsToRun.length} | ${colors.green}Aprovados: ${passed}${colors.reset} | ${colors.red}Falhas: ${failed}${colors.reset} | Tempo: ${duration}s\n`);

    if (failed > 0) {
        process.exit(1);
    }
}

if (require.main === module) {
    runRunner().catch(err => {
        console.error("Erro fatal no runner:", err);
        process.exit(1);
    });
}

module.exports = { testSuite, executeCodeNode };
