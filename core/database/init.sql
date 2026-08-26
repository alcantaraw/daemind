-- ===============================================================================
-- DAEMIND SRE - ESQUEMA DE BANCO DE DADOS & DATA WAREHOUSE SOBERANO
-- Arquivo: core/database/init.sql
-- Motor: PostgreSQL 17 + PGVector (768d HNSW) + postgres_fdw
-- Governança: Modelagem Relacional, Índices SRE, Tuning IOPS e Views Executivas
-- ===============================================================================
-- 📌 SUMÁRIO DE ARTEFATOS PROVISIONADOS:
-- 1. TABELAS TRANSACIONAIS (OLTP / STAGING SOBERANA):
--    - base_conhecimento    : Vetores RAG (768d) para IA (LiteLLM/Open WebUI/Ollama)
--    - clientes             : Base SSOT de Clientes OmniChannel com ID do Chatwoot
--    - pedidos              : Faturamento, CMV, Taxas de Gateways, Fretes e Deduções
--    - insumos              : Controle Preditivo de Embalagens e Expedição (Caixas/Fitas)
--    - leads                : Funil de Prospecção Ativa (PJ/B2B/B2C) com Chatwoot Conv ID
--    - catalogo             : Cache Espelho da Loja Integrada com Custos e Estoque Mínimo
--    - despesas_marketing   : Lançamentos de Ads (Meta, Google, TikTok) para DRE/ROAS
--    - campanhas_marketing  : Metas, Orçamentos e Parâmetros UTM das Campanhas
--    - carrinhos_abandonados: Esteira Ativa de Recuperação de Vendas via WhatsApp/E-mail
--    - fila_mensageria      : Outbox Transacional com Concorrência SKIP LOCKED
--    - schema_version       : Governança Antifalha de Migrações
--    - processed_events     : Tabela de Idempotência Global para Webhooks do n8n
--
-- 2. AUTOMAÇÃO NATIVA & BUSINESS LOGIC (TRIGGERS / FUNCTIONS / CONSTRAINTS):
--    - fn_sanitizar_dados_contato       : Higienização autônoma de WhatsApp (DDI 55), CPF/CNPJ e E-mails
--    - fn_processar_novo_pedido_autonomo: Auto-conversão de Leads, baixa de Carrinhos e consumo de Insumos
--    - fn_buscar_conhecimento_rag       : Stored Function de Busca Vetorial Semântica (Cosine Similarity)
--    - CHECK Constraints                : Blindagem de valores positivos e enums de funil/recuperação
--
-- 3. FEDERAÇÃO DATA WAREHOUSE (postgres_fdw):
--    - fdw_chatwoot         : Conversas, Atendentes, Contatos e Pesquisas CSAT
--    - fdw_shlink           : Links Curtos, Cliques, Dispositivos e Geolocalização
--    - fdw_listmonk         : Campanhas de E-mail, Inscritos, Visualizações e Cliques
--    - fdw_umami            : Sessões, Dispositivos, Visualizações de Página e Tags UTM
--    - fdw_evolution        : Disparos de WhatsApp, Mensagens e Status de Instâncias
--    - fdw_postiz           : Postagens Agendadas e Contas de Mídias Sociais
--
-- 4. VIEWS ANALÍTICAS & BI (METABASE / NOCODB):
--    - vw_kpi_atendimento                   : SLA de Resposta, Resolução e CSAT Chatwoot
--    - vw_kpi_marketing_links               : Performance de Links Curtos (Shlink)
--    - vw_kpi_email_marketing               : Taxa de Abertura e Cliques (Listmonk)
--    - vw_kpi_trafego_web                   : Visitas, Dispositivos e UTMs (Umami)
--    - vw_kpi_whatsapp_disparos             : Volumetria e Entrega WhatsApp (Evolution API)
--    - vw_kpi_redes_sociais                 : Status de Posts e Plataformas (Postiz)
--    - vw_funil_executivo_completo          : Cruzamento de Ponta a Ponta (Lead ➔ Venda)
--    - vw_gestao_lucro_real                 : DRE Unitário por Pedido (Venda - Custos = Lucro)
--    - vw_dre_diario_consolidado            : DRE Diário Consolidado + ROAS de Marketing
--    - vw_estoque_critico                   : Alerta Unificado de Ruptura (Produtos + Insumos)
--    - vw_calculadora_leads_metricas        : CPL, CAC, Taxa de Conversão e ROAS por Origem
--    - vw_ranking_leads_icp                 : Ranking de Leads, Score ICP (0-100), Tiers A/B/C e Fila
--    - vw_triagem_volume_leads              : Capacidade de Atendimento, Gargalos e Triagem de Volume
--    - vw_analise_descarte_leads            : Motivos de Descarte, Taxa de Rejeição e Ads Desperdiçado
--    - vw_performance_ads_gerenciadores     : Performance Oficial de Ads (Meta/Google/ChatGPT/TikTok) - CPC, CPM, CTR, CPA
--    - vw_correlacao_ads_vendas_reais       : Ads Reportado vs Pedidos Faturados no Banco (ROAS Real vs ROAS Pixel)
--    - vw_atribuicao_utm_360                : Atribuição de Tráfego e Vendas por UTM
--    - vw_matriz_rfm_clientes               : Segmentação Comportamental (VIP, Leais, Risco)
--    - vw_recompra_e_ciclo_de_vida          : Taxa de Recompra, LTV e Intervalo de Dias
--    - vw_kpi_recuperacao_vendas            : Taxa de Recuperação de Carrinhos e Boletos
--    - vw_social_media_engajamento_conversao: Correlação de Posts Postiz com Tráfego Umami
--    - vw_performance_comercial_atendentes  : Produtividade e Conversão de Vendedores SDR
--    - vw_relatorio_mensal_agencia          : Fechamento Mensal de Gestão de Tráfego & ROI
-- ===============================================================================

-- 1. Define o escopo padrão do restante deste script para o schema public
SET search_path TO public;

-- 2. Ativação da Extensão de Vetores para o RAG da Inteligência Artificial
CREATE EXTENSION IF NOT EXISTS vector;

-- 1.5 Criação da Tabela de Conhecimento RAG (Catálogo e Manuais)
CREATE TABLE IF NOT EXISTS base_conhecimento (
    id SERIAL PRIMARY KEY,
    titulo VARCHAR(255) NOT NULL,
    conteudo TEXT NOT NULL,
    categoria VARCHAR(100),
    -- Utilizando dimensão 768, que é o padrão de saída do modelo text-embedding do Gemini
    embedding VECTOR(768), 
    data_atualizacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Criação da Tabela de Clientes (Base unificada OmniChannel e CRM)
-- Nota de Arquitetura SRE: O campo 'id' utiliza BIGINT PRIMARY KEY sem SERIAL propositalmente
-- para suportar sincronização SSOT de identidades externas (ID único da Loja Integrada / ERP / Chatwoot Contact).
CREATE TABLE IF NOT EXISTS clientes (
    id BIGINT PRIMARY KEY,
    nome VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE,
    documento VARCHAR(14) UNIQUE, -- Suporta CPF (11) ou CNPJ (14)
    razao_social VARCHAR(255),
    whatsapp VARCHAR(20), -- Formato limpo: 5521999998888 (Nullable por restrição de API)
    grupo VARCHAR(100),
	-- 🚀 SRE OMNICHANNEL: Chaves de vinculação com sistemas de borda
    chatwoot_contact_id BIGINT UNIQUE, -- Rastreabilidade bidirecional com o CRM do Chatwoot
    data_cadastro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Criação da Tabela de Pedidos (Sincronização com Loja Integrada e Marketplaces)
CREATE TABLE IF NOT EXISTS pedidos (
    id BIGINT PRIMARY KEY,
    -- SRE Correção: Elevação do tipo para BIGINT para suportar sequenciais numéricos massivos 
    -- de rastreabilidade de e-commerce e marketplaces sem estourar as constraints do motor.
    numero_pedido BIGINT UNIQUE NOT NULL, 
    cliente_id BIGINT REFERENCES clientes(id) ON DELETE SET NULL,
    valor_total NUMERIC(10,2) NOT NULL, -- Faturamento Bruto
    valor_desconto NUMERIC(10,2) DEFAULT 0.00,
    valor_frete NUMERIC(10,2) DEFAULT 0.00,
    despesa_frete_real NUMERIC(10,2) DEFAULT 0.00, -- Custo real de frete pago à transportadora/Correios
    taxa_gateway NUMERIC(10,2) DEFAULT 0.00, -- Taxas retidas por meios de pagamento (Mercado Pago, Pagar.me, etc.)
    custo_produtos_cmv NUMERIC(10,2) DEFAULT 0.00, -- Custo de Mercadoria Vendida (CMV) consolidado do pedido
    despesa_marketing NUMERIC(10,2) DEFAULT 0.00, -- Custo atribuído de tráfego/anúncios
    status_operacional VARCHAR(100) NOT NULL, 
    envio_id VARCHAR(100),
    codigo_rastreio VARCHAR(100),
    chave_fiscal VARCHAR(44), 
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    insumos_consumidos BOOLEAN DEFAULT FALSE, -- Flag anti-duplicação de baixa de embalagens
    data_criacao TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Criação da Tabela de Controle Preditivo de Insumos de Embalagem/Expedição
CREATE TABLE IF NOT EXISTS insumos (
    id SERIAL PRIMARY KEY,
    item_nome VARCHAR(255) UNIQUE NOT NULL, -- Caixas, Fitas, Etiquetas
    tipo_insumo VARCHAR(50) DEFAULT 'OUTRO', -- CAIXA, ETIQUETA, FITA, OUTRO (Indexável)
    quantidade_atual INTEGER NOT NULL DEFAULT 0,
    estoque_minimo INTEGER NOT NULL DEFAULT 10,
    fornecedor_nome VARCHAR(255),
    fornecedor_contato VARCHAR(100),
    ultima_atualizacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. Criação da Tabela de Funil de Leads e Prospecção Ativa (PJ e Concorrentes)
CREATE TABLE IF NOT EXISTS leads (
    id SERIAL PRIMARY KEY,
    origem_captura VARCHAR(100) NOT NULL, -- Google Maps, Instagram, Concorrente, Form_Site, Google_Ads, Meta_Ads
    perfil_ou_link TEXT,
    documento_pj VARCHAR(14),
    contato_identificado VARCHAR(255),
    status_funil VARCHAR(50) DEFAULT 'Frio', -- Frio, Morno, Quente, Convertido, Perdido, Desqualificado
    payload_raw JSONB, -- Payload bruto capturado para auditoria
    -- 🚀 SRE LEAD SCORING & QUALIFICAÇÃO INTELIGENTE
    score_qualificacao INTEGER DEFAULT 0, -- Score calculado de 0 a 100
    classificacao_lead VARCHAR(20) DEFAULT 'Tier C', -- Tier A (VIP/Alta Prioridade), Tier B (Média), Tier C (Baixa), Desqualificado
    motivo_descarte VARCHAR(100), -- Telefone Invalido, Sem Contato, Fora do ICP, CNPJ Invalido, Concorrente, Sem Interesse
    data_qualificacao TIMESTAMP, -- Timestamp em que o lead atingiu score ou foi classificado
    data_descarte TIMESTAMP, -- Timestamp do descarte
    atendente_designado VARCHAR(100), -- SDR / Vendedor responsável pelo atendimento
    -- 🚀 SRE OMNICHANNEL: Contexto de Atendimento
    chatwoot_conversation_id BIGINT UNIQUE, -- ID da conversa aberta no Inbox do Chatwoot
    data_captura TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. Criação da Tabela de Catálogo Local (Cache Espelho da Loja Integrada)
CREATE TABLE IF NOT EXISTS catalogo (
    id_interno BIGINT PRIMARY KEY, -- ID numérico interno exigido pela API
    sku VARCHAR(100) UNIQUE NOT NULL, -- SKU alfanumérico bipado ou digitado
    nome VARCHAR(255) NOT NULL,
    preco_cheio NUMERIC(10,2),
    custo_unitario NUMERIC(10,2) DEFAULT 0.00, -- Custo de aquisição unitário (CMV base)
    quantidade_estoque INTEGER NOT NULL DEFAULT 0,
    estoque_minimo INTEGER NOT NULL DEFAULT 5, -- Nível mínimo para disparo de alerta de estoque
    data_sincronizacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6.5 Criação da Tabela de Despesas de Marketing e Tráfego Pago
CREATE TABLE IF NOT EXISTS despesas_marketing (
    id SERIAL PRIMARY KEY,
    canal VARCHAR(100) NOT NULL, -- Meta Ads, Google Ads, TikTok, Influenciador, etc.
    valor NUMERIC(10,2) NOT NULL,
    data_despesa DATE NOT NULL DEFAULT CURRENT_DATE,
    observacoes TEXT,
    data_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6.6 Tabela de Gestão de Campanhas de Tráfego, Metas e UTMs (Hub de Mídia Paga)
CREATE TABLE IF NOT EXISTS campanhas_marketing (
    id SERIAL PRIMARY KEY,
    nome_campanha VARCHAR(255) NOT NULL,
    canal VARCHAR(100) NOT NULL, -- Meta Ads, Google Ads, TikTok Ads, ChatGPT Ads, LinkedIn Ads, Influenciador, Afiliados
    conta_anuncio_id VARCHAR(100), -- ID da Conta no Gerenciador (ex: act_123456789, 123-456-7890)
    campanha_externa_id VARCHAR(100), -- ID nativo da campanha na API (ex: 120205847382910)
    orcamento_planejado NUMERIC(10,2) DEFAULT 0.00,
    orcamento_diario NUMERIC(10,2) DEFAULT 0.00,
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    utm_content VARCHAR(100),
    utm_term VARCHAR(100),
    data_inicio DATE,
    data_fim DATE,
    status VARCHAR(50) DEFAULT 'Ativa', -- Planejada, Ativa, Pausada, Concluída, Arquivada
    observacoes TEXT,
    data_cadastro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6.6.1 Tabela de Coleta Diária de Métricas de Ads (Ingestão via n8n / APIs Oficiais)
-- Suporta: Meta Ads (Facebook/Instagram), Google Ads, TikTok Ads, ChatGPT Ads, LinkedIn Ads, Bing/Microsoft Ads
CREATE TABLE IF NOT EXISTS metricas_ads_diarias (
    id SERIAL PRIMARY KEY,
    plataforma VARCHAR(50) NOT NULL, -- Meta Ads, Google Ads, TikTok Ads, ChatGPT Ads, LinkedIn Ads, Pinterest Ads, Outros
    conta_id VARCHAR(100) NOT NULL, -- ID da Conta de Anúncios
    campanha_id_externo VARCHAR(100) NOT NULL, -- ID da Campanha no Gerenciador
    campanha_nome VARCHAR(255) NOT NULL,
    conjunto_anuncio_id_externo VARCHAR(100), -- AdSet ID / Grupo de Anúncios ID
    conjunto_anuncio_nome VARCHAR(255),
    anuncio_id_externo VARCHAR(100), -- Ad ID / Criativo ID
    anuncio_nome VARCHAR(255),
    data_referencia DATE NOT NULL,
    
    -- Métricas de Entrega e Alcance
    impressoes BIGINT DEFAULT 0,
    alcance BIGINT DEFAULT 0,
    frequencia NUMERIC(5,2) DEFAULT 1.00,
    
    -- Métricas de Engajamento e Cliques
    cliques BIGINT DEFAULT 0,
    cliques_unicos BIGINT DEFAULT 0,
    ctr NUMERIC(5,2) DEFAULT 0.00, -- Click-Through Rate %
    cpc NUMERIC(10,2) DEFAULT 0.00, -- Custo por Clique
    cpm NUMERIC(10,2) DEFAULT 0.00, -- Custo por Mil Impressões
    
    -- Métricas Financeiras de Investimento
    valor_investido NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    
    -- Métricas de Conversão do Pixel / API de Conversões da Plataforma
    conversoes_pixel INTEGER DEFAULT 0,
    compras_pixel INTEGER DEFAULT 0,
    receita_pixel NUMERIC(10,2) DEFAULT 0.00,
    roas_pixel NUMERIC(10,2) DEFAULT 0.00,
    cpa_pixel NUMERIC(10,2) DEFAULT 0.00, -- Custo por Aquisição reportado pelo pixel
    
    -- Parâmetros UTM mapeados
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    
    -- Payload bruto em JSONB para auditoria técnica de telemetria
    payload_api_raw JSONB,
    
    data_coleta TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Chave de Idempotência: Garante que uma sincronização diária para o mesmo anúncio/campanha não duplique linhas
    CONSTRAINT unq_metricas_ads_diarias UNIQUE (plataforma, conta_id, campanha_id_externo, data_referencia, anuncio_id_externo)
);
ALTER TABLE metricas_ads_diarias SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_vacuum_threshold = 20);

-- 6.7 Tabela de Recuperação de Vendas, Boletos e Carrinhos Abandonados
CREATE TABLE IF NOT EXISTS carrinhos_abandonados (
    id SERIAL PRIMARY KEY,
    cliente_nome VARCHAR(255),
    whatsapp VARCHAR(20),
    email VARCHAR(255),
    valor_carrinho NUMERIC(10,2) NOT NULL,
    link_checkout_recuperacao TEXT,
    tipo_pendencia VARCHAR(50) DEFAULT 'Carrinho Abandonado', -- Carrinho Abandonado, PIX Pendente, Boleto Pendente
    status_recuperacao VARCHAR(50) DEFAULT 'Pendente', -- Pendente, Disparado_WhatsApp, Disparado_Email, Recuperado, Expirado
    tentativas_contato INTEGER DEFAULT 0,
    data_abandono TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_recuperacao TIMESTAMP,
    pedido_gerado_id BIGINT REFERENCES pedidos(id) ON DELETE SET NULL, -- Histórico preservado ao excluir pedido
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7. Tabela de Controle de Mensageria e Prospecção B2B (Fila Transacional Outbox)
CREATE TABLE IF NOT EXISTS fila_mensageria (
    id SERIAL PRIMARY KEY,
    documento_pj VARCHAR(14) NOT NULL,
    whatsapp VARCHAR(20) NOT NULL,
    status VARCHAR(50) DEFAULT 'pendente',
    tentativas INTEGER DEFAULT 0,
    data_agendamento TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Racional de Micro-Tuning PostgreSQL (SRE IOPS Optimization):
-- Força parâmetros agressivos de autovacuum nas tabelas de alta rotação transacional
-- (filas outbox, staging de catálogo, pedidos e carrinhos abandonados),
-- forçando o motor a limpar o espaço morto imediatamente após leituras/updates
-- e impedindo o esgotamento prematuro de IOPS do Mini PC / VPS por fragmentação de páginas.
ALTER TABLE fila_mensageria SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_vacuum_threshold = 20);
ALTER TABLE catalogo SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_vacuum_threshold = 20);
ALTER TABLE pedidos SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_vacuum_threshold = 20);
ALTER TABLE carrinhos_abandonados SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_vacuum_threshold = 20);

-- Racional de Engenharia de Concorrência: O SELECT transacional de consumo da fila 
-- passa a executar obrigatoriamente as diretivas "FOR UPDATE SKIP LOCKED".
-- Isso instrui o PostgreSQL a travar as linhas em processamento por um worker, 
-- fazendo com que instâncias simultâneas pulem os registros ocupados, 
-- mitigando a probabilidade matemática de deadlocks em cenários de alta carga.
-- Queries de atualização de inventário na tabela 'catalogo' passam a adotar 
-- bloqueio pessimista via 'SELECT FOR UPDATE' nas janelas de concorrência.

-- 7.5 Tabela de Controle de Versão de Esquema (Governança Antifalha de Migrations)
CREATE TABLE IF NOT EXISTS schema_version (
    versao VARCHAR(255) PRIMARY KEY,
    data_aplicacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7.8 Tabela de Controle de Idempotência (Garantia de Execução Unitária de Eventos)
CREATE TABLE IF NOT EXISTS processed_events (
    event_id VARCHAR(255) PRIMARY KEY,
    webhook_topic VARCHAR(100) NOT NULL,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Racional de Integração: Todo webhook inbound (pedido.criado / pedido.editado) processado 
-- pelo orquestrador n8n realiza uma verificação "INSERT INTO processed_events VALUES (id) ON CONFLICT DO NOTHING".
-- Se o id já constar na tabela, a esteira aborta imediatamente a execução com sucesso (HTTP 200),
-- blindando as tabelas transacionais contra duplicidades geradas pela infraestrutura externa.

-- 8. Índices de Otimização Relacional, Buscas Rápidas & Joins Analíticos (SRE Index Matrix)
-- Índices em Catálogo e Insumos
CREATE INDEX IF NOT EXISTS idx_catalogo_sku ON catalogo(sku);
CREATE INDEX IF NOT EXISTS idx_catalogo_estoque ON catalogo(quantidade_estoque);
CREATE INDEX IF NOT EXISTS idx_insumos_tipo ON insumos(tipo_insumo);

-- Índices em Clientes e Leads (Matching OmniChannel Ultra-Rápido & Scoring)
CREATE INDEX IF NOT EXISTS idx_clientes_whatsapp ON clientes(whatsapp);
CREATE INDEX IF NOT EXISTS idx_clientes_documento ON clientes(documento);
CREATE INDEX IF NOT EXISTS idx_leads_documento ON leads(documento_pj);
CREATE INDEX IF NOT EXISTS idx_leads_contato ON leads(contato_identificado);
CREATE INDEX IF NOT EXISTS idx_leads_origem_funil ON leads(origem_captura, status_funil);
CREATE INDEX IF NOT EXISTS idx_leads_data_captura ON leads(data_captura);
CREATE INDEX IF NOT EXISTS idx_leads_score ON leads(score_qualificacao DESC);
CREATE INDEX IF NOT EXISTS idx_leads_classificacao ON leads(classificacao_lead);
CREATE INDEX IF NOT EXISTS idx_leads_motivo_descarte ON leads(motivo_descarte);

-- Índices em Pedidos (Aceleração Brutal de DRE e Métricas Temporais)
CREATE INDEX IF NOT EXISTS idx_pedidos_cliente ON pedidos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_data_criacao ON pedidos(data_criacao);
CREATE INDEX IF NOT EXISTS idx_pedidos_status ON pedidos(status_operacional);
CREATE INDEX IF NOT EXISTS idx_pedidos_data_status ON pedidos(data_criacao, status_operacional);
CREATE INDEX IF NOT EXISTS idx_pedidos_utm ON pedidos(utm_campaign, utm_source, utm_medium);
CREATE INDEX IF NOT EXISTS idx_pedidos_insumos_consumidos ON pedidos(insumos_consumidos);

-- Índices em Fila de Mensageria e Carrinhos Abandonados (Filtros de Esteiras n8n)
CREATE INDEX IF NOT EXISTS idx_fila_status ON fila_mensageria(status);
CREATE INDEX IF NOT EXISTS idx_carrinhos_status ON carrinhos_abandonados(status_recuperacao);
CREATE INDEX IF NOT EXISTS idx_carrinhos_data ON carrinhos_abandonados(data_abandono);
CREATE INDEX IF NOT EXISTS idx_carrinhos_whatsapp ON carrinhos_abandonados(whatsapp);

-- Índices em Marketing, Campanhas, Métricas de Ads e Eventos Processados
CREATE INDEX IF NOT EXISTS idx_campanhas_utm ON campanhas_marketing(utm_campaign);
CREATE INDEX IF NOT EXISTS idx_campanhas_status_data ON campanhas_marketing(status, data_inicio, data_fim);
CREATE INDEX IF NOT EXISTS idx_campanhas_externa_id ON campanhas_marketing(campanha_externa_id);
CREATE INDEX IF NOT EXISTS idx_despesas_data_canal ON despesas_marketing(data_despesa, canal);
CREATE INDEX IF NOT EXISTS idx_metricas_ads_data_plat ON metricas_ads_diarias(data_referencia, plataforma);
CREATE INDEX IF NOT EXISTS idx_metricas_ads_campanha ON metricas_ads_diarias(campanha_id_externo, data_referencia);
CREATE INDEX IF NOT EXISTS idx_metricas_ads_utm ON metricas_ads_diarias(utm_campaign, utm_source, utm_medium);
CREATE INDEX IF NOT EXISTS idx_processed_events_age ON processed_events(processed_at);

-- GOLPE DE MESTRE SRE: Índice HNSW para buscas semânticas ultra-rápidas (RAG)
-- Utiliza 'vector_cosine_ops' para otimizar pesquisas baseadas no operador de distância '<=>'
CREATE INDEX IF NOT EXISTS idx_base_conhecimento_embedding 
ON base_conhecimento USING hnsw (embedding vector_cosine_ops);

-- 9. DML de Carga Inicial (Seed de Insumos Estratégicos para Teste de Alerta - White Label)
INSERT INTO insumos (item_nome, tipo_insumo, quantidade_atual, estoque_minimo, fornecedor_nome, fornecedor_contato)
VALUES 
('Caixa de Embalagem Padrão Tamanho P', 'CAIXA', 5, 25, 'Fornecedor Central Embalagens', '21988887777'),
('Fita Adesiva Acrílica Larga 50mm', 'FITA', 2, 10, 'Distribuidora de Fitas e Lacres', '21977776666'),
('Etiqueta Térmica de Expedição 100x150mm', 'ETIQUETA', 150, 500, 'Suprimentos de Automacao Ltda', '21966665555')
ON CONFLICT (item_nome) DO UPDATE 
SET tipo_insumo = EXCLUDED.tipo_insumo;

-- ===============================================================================
-- 9.5 AUTOMAÇÃO NATIVA DO BANCO (TRIGGERS, FUNCTIONS, RAG & CHECK CONSTRAINTS)
-- ===============================================================================

-- 0. Function & Trigger Global: Atualização Automática de Timestamp (updated_at)
CREATE OR REPLACE FUNCTION fn_atualizar_timestamp_modificacao()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Vinculação da Trigger de updated_at nas tabelas transacionais
DROP TRIGGER IF EXISTS trg_upd_clientes ON public.clientes;
CREATE TRIGGER trg_upd_clientes BEFORE UPDATE ON public.clientes FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();

DROP TRIGGER IF EXISTS trg_upd_pedidos ON public.pedidos;
CREATE TRIGGER trg_upd_pedidos BEFORE UPDATE ON public.pedidos FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();

DROP TRIGGER IF EXISTS trg_upd_insumos ON public.insumos;
CREATE TRIGGER trg_upd_insumos BEFORE UPDATE ON public.insumos FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();

DROP TRIGGER IF EXISTS trg_upd_leads ON public.leads;
CREATE TRIGGER trg_upd_leads BEFORE UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();

DROP TRIGGER IF EXISTS trg_upd_catalogo ON public.catalogo;
CREATE TRIGGER trg_upd_catalogo BEFORE UPDATE ON public.catalogo FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();

DROP TRIGGER IF EXISTS trg_upd_despesas ON public.despesas_marketing;
CREATE TRIGGER trg_upd_despesas BEFORE UPDATE ON public.despesas_marketing FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();

DROP TRIGGER IF EXISTS trg_upd_campanhas ON public.campanhas_marketing;
CREATE TRIGGER trg_upd_campanhas BEFORE UPDATE ON public.campanhas_marketing FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();

DROP TRIGGER IF EXISTS trg_upd_metricas_ads ON public.metricas_ads_diarias;
CREATE TRIGGER trg_upd_metricas_ads BEFORE UPDATE ON public.metricas_ads_diarias FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();

DROP TRIGGER IF EXISTS trg_upd_carrinhos ON public.carrinhos_abandonados;
CREATE TRIGGER trg_upd_carrinhos BEFORE UPDATE ON public.carrinhos_abandonados FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();

DROP TRIGGER IF EXISTS trg_upd_fila ON public.fila_mensageria;
CREATE TRIGGER trg_upd_fila BEFORE UPDATE ON public.fila_mensageria FOR EACH ROW EXECUTE FUNCTION fn_atualizar_timestamp_modificacao();


-- A) Functions & Triggers: Higienização Automática de Dados de Contato
-- SRE Fix: Funções DEDICADAS por tabela — elimina bifurcação por TG_TABLE_NAME e acesso
-- a colunas inexistentes no NEW (ex: NEW.email em 'leads' que não possui o campo causaria
-- erro runtime em PL/pgSQL). Cada função opera apenas nos campos que a tabela realmente tem.

-- A.1) Sanitização de Clientes: E-mail, CPF/CNPJ (documento) e WhatsApp com DDI 55
CREATE OR REPLACE FUNCTION fn_sanitizar_clientes()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.email IS NOT NULL THEN
        NEW.email := LOWER(TRIM(NEW.email));
    END IF;
    IF NEW.documento IS NOT NULL THEN
        NEW.documento := REGEXP_REPLACE(NEW.documento, '[^0-9]', '', 'g');
    END IF;
    IF NEW.whatsapp IS NOT NULL THEN
        NEW.whatsapp := REGEXP_REPLACE(NEW.whatsapp, '[^0-9]', '', 'g');
        IF LENGTH(NEW.whatsapp) IN (10, 11) THEN
            NEW.whatsapp := '55' || NEW.whatsapp;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- A.2) Sanitização e Scoring de Leads: CNPJ (documento_pj), Contato e Cálculo Preditivo de Score
CREATE OR REPLACE FUNCTION fn_sanitizar_e_qualificar_leads()
RETURNS TRIGGER AS $$
DECLARE
    v_clean_tel TEXT;
    v_calc_score INTEGER := 0;
BEGIN
    -- 1. Sanitização de Documento PJ (CNPJ)
    IF NEW.documento_pj IS NOT NULL THEN
        NEW.documento_pj := REGEXP_REPLACE(NEW.documento_pj, '[^0-9]', '', 'g');
    END IF;

    -- 2. Sanitização de Contato Identificado (Telefone com DDI 55)
    IF NEW.contato_identificado IS NOT NULL THEN
        IF NEW.contato_identificado ~ '^[0-9\(\)\-\+[:space:]]+$' THEN
            v_clean_tel := REGEXP_REPLACE(NEW.contato_identificado, '[^0-9]', '', 'g');
            IF LENGTH(v_clean_tel) IN (10, 11) THEN
                NEW.contato_identificado := '55' || v_clean_tel;
            ELSIF LENGTH(v_clean_tel) >= 12 THEN
                NEW.contato_identificado := v_clean_tel;
            END IF;
        END IF;
    END IF;

    -- 3. Motor de Lead Scoring Inteligente & Triagem (0 a 100 pontos)
    -- Pontos por CNPJ identificado e válido
    IF NEW.documento_pj IS NOT NULL AND LENGTH(NEW.documento_pj) = 14 THEN
        v_calc_score := v_calc_score + 30;
    ELSIF NEW.documento_pj IS NOT NULL AND LENGTH(NEW.documento_pj) = 11 THEN
        v_calc_score := v_calc_score + 20; -- CPF / MEI
    END IF;

    -- Pontos por Telefone/WhatsApp válido
    IF NEW.contato_identificado IS NOT NULL AND LENGTH(NEW.contato_identificado) >= 12 THEN
        v_calc_score := v_calc_score + 25;
    END IF;

    -- Pontos por Origem de Alta Intenção / Inbound
    IF LOWER(NEW.origem_captura) IN ('form_site', 'formulario', 'google_ads', 'site', 'indicacao', 'whatsapp_inbound') THEN
        v_calc_score := v_calc_score + 25;
    ELSIF LOWER(NEW.origem_captura) IN ('meta_ads', 'instagram_ads', 'facebook_ads', 'linkedin') THEN
        v_calc_score := v_calc_score + 15;
    ELSIF LOWER(NEW.origem_captura) IN ('google maps', 'maps', 'concorrente', 'scraping') THEN
        v_calc_score := v_calc_score + 10;
    END IF;

    -- Pontos por Perfil / Site / Link mapeado
    IF NEW.perfil_ou_link IS NOT NULL AND LENGTH(TRIM(NEW.perfil_ou_link)) > 5 THEN
        v_calc_score := v_calc_score + 10;
    END IF;

    -- Pontos por Conversa Ativa no Chatwoot
    IF NEW.chatwoot_conversation_id IS NOT NULL THEN
        v_calc_score := v_calc_score + 10;
    END IF;

    NEW.score_qualificacao := LEAST(100, v_calc_score);

    -- 4. Classificação em Tiers e Descarte Inteligente
    IF NEW.status_funil = 'Desqualificado' THEN
        NEW.classificacao_lead := 'Desqualificado';
        IF NEW.data_descarte IS NULL THEN
            NEW.data_descarte := CURRENT_TIMESTAMP;
        END IF;
    ELSIF (NEW.contato_identificado IS NULL OR LENGTH(TRIM(NEW.contato_identificado)) = 0)
       AND (NEW.documento_pj IS NULL OR LENGTH(TRIM(NEW.documento_pj)) = 0)
       AND (NEW.perfil_ou_link IS NULL OR LENGTH(TRIM(NEW.perfil_ou_link)) = 0) THEN
        -- Descarte automático por ausência total de dados de contato
        NEW.status_funil := 'Desqualificado';
        NEW.classificacao_lead := 'Desqualificado';
        NEW.motivo_descarte := COALESCE(NEW.motivo_descarte, 'Sem Dados de Contato');
        NEW.data_descarte := CURRENT_TIMESTAMP;
    ELSIF NEW.score_qualificacao >= 70 THEN
        NEW.classificacao_lead := 'Tier A';
        NEW.data_qualificacao := COALESCE(NEW.data_qualificacao, CURRENT_TIMESTAMP);
    ELSIF NEW.score_qualificacao >= 40 THEN
        NEW.classificacao_lead := 'Tier B';
        NEW.data_qualificacao := COALESCE(NEW.data_qualificacao, CURRENT_TIMESTAMP);
    ELSE
        NEW.classificacao_lead := 'Tier C';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- A.3) Sanitização de Carrinhos Abandonados: E-mail e WhatsApp com DDI 55
CREATE OR REPLACE FUNCTION fn_sanitizar_carrinhos()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.email IS NOT NULL THEN
        NEW.email := LOWER(TRIM(NEW.email));
    END IF;
    IF NEW.whatsapp IS NOT NULL THEN
        NEW.whatsapp := REGEXP_REPLACE(NEW.whatsapp, '[^0-9]', '', 'g');
        IF LENGTH(NEW.whatsapp) IN (10, 11) THEN
            NEW.whatsapp := '55' || NEW.whatsapp;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Remove função unificada legada — substituída pelas funções dedicadas
DROP FUNCTION IF EXISTS fn_sanitizar_dados_contato() CASCADE;
DROP FUNCTION IF EXISTS fn_sanitizar_leads() CASCADE;

-- A.4) Trigger de Normalização e Auto-Cálculo de Eficiência de Ads (CPC, CPM, CTR)
CREATE OR REPLACE FUNCTION fn_calcular_metricas_ads_diarias()
RETURNS TRIGGER AS $$
BEGIN
    -- Força consistência nas tags UTM e nomes
    IF NEW.utm_source IS NOT NULL THEN
        NEW.utm_source := LOWER(TRIM(NEW.utm_source));
    END IF;
    IF NEW.utm_medium IS NOT NULL THEN
        NEW.utm_medium := LOWER(TRIM(NEW.utm_medium));
    END IF;
    IF NEW.utm_campaign IS NOT NULL THEN
        NEW.utm_campaign := LOWER(TRIM(NEW.utm_campaign));
    END IF;

    -- Cálculo automático de CTR % se não fornecido
    IF NEW.impressoes > 0 AND (NEW.ctr IS NULL OR NEW.ctr = 0.00) THEN
        NEW.ctr := ROUND((NEW.cliques::numeric / NEW.impressoes) * 100.0, 2);
    END IF;

    -- Cálculo automático de CPC se não fornecido
    IF NEW.cliques > 0 AND (NEW.cpc IS NULL OR NEW.cpc = 0.00) THEN
        NEW.cpc := ROUND(NEW.valor_investido / NEW.cliques, 2);
    END IF;

    -- Cálculo automático de CPM se não fornecido
    IF NEW.impressoes > 0 AND (NEW.cpm IS NULL OR NEW.cpm = 0.00) THEN
        NEW.cpm := ROUND((NEW.valor_investido / NEW.impressoes) * 1000.0, 2);
    END IF;

    -- Cálculo automático de ROAS do Pixel
    IF NEW.valor_investido > 0 AND (NEW.roas_pixel IS NULL OR NEW.roas_pixel = 0.00) AND NEW.receita_pixel > 0 THEN
        NEW.roas_pixel := ROUND(NEW.receita_pixel / NEW.valor_investido, 2);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_calcular_metricas_ads ON public.metricas_ads_diarias;
CREATE TRIGGER trg_calcular_metricas_ads
    BEFORE INSERT OR UPDATE ON public.metricas_ads_diarias
    FOR EACH ROW EXECUTE FUNCTION fn_calcular_metricas_ads_diarias();
DROP TRIGGER IF EXISTS trg_sanitizar_clientes ON public.clientes;
CREATE TRIGGER trg_sanitizar_clientes
    BEFORE INSERT OR UPDATE ON public.clientes
    FOR EACH ROW EXECUTE FUNCTION fn_sanitizar_clientes();

DROP TRIGGER IF EXISTS trg_sanitizar_leads ON public.leads;
CREATE TRIGGER trg_sanitizar_leads
    BEFORE INSERT OR UPDATE ON public.leads
    FOR EACH ROW EXECUTE FUNCTION fn_sanitizar_e_qualificar_leads();

DROP TRIGGER IF EXISTS trg_sanitizar_carrinhos ON public.carrinhos_abandonados;
CREATE TRIGGER trg_sanitizar_carrinhos
    BEFORE INSERT OR UPDATE ON public.carrinhos_abandonados
    FOR EACH ROW EXECUTE FUNCTION fn_sanitizar_carrinhos();


-- B) Function & Trigger: Automação Reativa de Pedidos
-- 1. Promove Leads para 'Convertido' com isolamento estrito de dados
-- 2. Dá baixa em Carrinhos Abandonados vinculando o pedido recuperado
-- 3. Consome insumos de expedição de forma unitária (idempotente com SKIP LOCKED)
-- SRE Fix: BEFORE Trigger evita auto-UPDATE recursivo na tabela 'pedidos'
CREATE OR REPLACE FUNCTION fn_processar_novo_pedido_autonomo()
RETURNS TRIGGER AS $$
DECLARE
    v_cliente RECORD;
    v_status_valido BOOLEAN;
BEGIN
    -- Busca dados do cliente vinculado ao pedido
    IF NEW.cliente_id IS NOT NULL THEN
        SELECT documento, whatsapp, email INTO v_cliente 
        FROM public.clientes 
        WHERE id = NEW.cliente_id;

        IF FOUND THEN
            -- 1. Auto-conversão de Leads: SKIP LOCKED serializa workers concorrentes no mesmo registro
            UPDATE public.leads
            SET status_funil = 'Convertido'
            WHERE id IN (
                SELECT id FROM public.leads
                WHERE status_funil != 'Convertido'
                  AND (
                    (v_cliente.documento IS NOT NULL AND documento_pj IS NOT NULL AND documento_pj = v_cliente.documento)
                    OR (v_cliente.whatsapp IS NOT NULL AND contato_identificado IS NOT NULL AND contato_identificado = v_cliente.whatsapp)
                  )
                FOR UPDATE SKIP LOCKED
            );

            -- 2. Auto-baixa de Carrinhos Abandonados: SKIP LOCKED evita dupla marcação em concorrência
            UPDATE public.carrinhos_abandonados
            SET status_recuperacao = 'Recuperado',
                data_recuperacao = CURRENT_TIMESTAMP,
                pedido_gerado_id = NEW.id
            WHERE id IN (
                SELECT id FROM public.carrinhos_abandonados
                WHERE status_recuperacao != 'Recuperado'
                  AND (
                    (v_cliente.whatsapp IS NOT NULL AND whatsapp IS NOT NULL AND whatsapp = v_cliente.whatsapp)
                    OR (v_cliente.email IS NOT NULL AND email IS NOT NULL AND LOWER(email) = LOWER(v_cliente.email))
                  )
                FOR UPDATE SKIP LOCKED
            );
        END IF;
    END IF;

    -- 3. Baixa Preditiva Automática de Insumos de Embalagem e Expedição
    -- SRE Fix: Apenas tipo_insumo indexado — ILIKE removido (tipo_insumo obrigatório via seed/upsert)
    v_status_valido := LOWER(COALESCE(NEW.status_operacional, '')) IN ('pago', 'em_separacao', 'faturado', 'enviado', 'aprovado');
    
    IF v_status_valido AND (NEW.insumos_consumidos IS FALSE OR NEW.insumos_consumidos IS NULL) THEN
        -- Baixa indexada exclusivamente por tipo_insumo com FOR UPDATE SKIP LOCKED
        UPDATE public.insumos
        SET quantidade_atual = GREATEST(0, quantidade_atual - 1),
            ultima_atualizacao = CURRENT_TIMESTAMP
        WHERE id IN (
            SELECT id FROM public.insumos
            WHERE tipo_insumo IN ('CAIXA', 'ETIQUETA')
            FOR UPDATE SKIP LOCKED
        );

        -- Atribuição direta no registro NEW (Zero overhead, sem re-disparo de trigger)
        NEW.insumos_consumidos := TRUE;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Vinculação da Trigger de Processamento Autônomo de Pedidos (BEFORE INSERT OR UPDATE)
DROP TRIGGER IF EXISTS trg_processar_pedido_autonomo ON public.pedidos;
CREATE TRIGGER trg_processar_pedido_autonomo
    BEFORE INSERT OR UPDATE OF status_operacional, insumos_consumidos ON public.pedidos
    FOR EACH ROW EXECUTE FUNCTION fn_processar_novo_pedido_autonomo();


-- C) Stored Function: Consulta Semântica RAG para Inteligência Artificial
-- Permite que o LiteLLM / Open WebUI / Agentes consultem manuais com scoring de similaridade
CREATE OR REPLACE FUNCTION fn_buscar_conhecimento_rag(
    query_embedding VECTOR(768),
    match_threshold FLOAT DEFAULT 0.70,
    match_count INT DEFAULT 5
)
RETURNS TABLE (
    id INT,
    titulo VARCHAR(255),
    conteudo TEXT,
    categoria VARCHAR(100),
    similaridade FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        b.id,
        b.titulo,
        b.conteudo,
        b.categoria,
        ROUND((1 - (b.embedding <=> query_embedding))::numeric, 4)::FLOAT AS similaridade
    FROM public.base_conhecimento b
    WHERE b.embedding IS NOT NULL
      AND (1 - (b.embedding <=> query_embedding)) >= match_threshold
    ORDER BY b.embedding <=> query_embedding
    LIMIT match_count;
END;
$$ LANGUAGE plpgsql;


-- D) Governança de CHECK Constraints (Idempotência e Blindagem de Valores)
DO $$
BEGIN
    -- Validação de Valores Monetários Não-Negativos
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_pedidos_valor_total_positivo') THEN
        ALTER TABLE public.pedidos ADD CONSTRAINT chk_pedidos_valor_total_positivo CHECK (valor_total >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_catalogo_custo_positivo') THEN
        ALTER TABLE public.catalogo ADD CONSTRAINT chk_catalogo_custo_positivo CHECK (custo_unitario >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_despesas_valor_positivo') THEN
        ALTER TABLE public.despesas_marketing ADD CONSTRAINT chk_despesas_valor_positivo CHECK (valor >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_metricas_ads_valor_positivo') THEN
        ALTER TABLE public.metricas_ads_diarias ADD CONSTRAINT chk_metricas_ads_valor_positivo CHECK (valor_investido >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_carrinhos_valor_positivo') THEN
        ALTER TABLE public.carrinhos_abandonados ADD CONSTRAINT chk_carrinhos_valor_positivo CHECK (valor_carrinho >= 0);
    END IF;

    -- Migração Idempotente de Colunas de Lead Scoring na tabela leads (para bases existentes)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'leads' AND column_name = 'score_qualificacao') THEN
        ALTER TABLE public.leads ADD COLUMN score_qualificacao INTEGER DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'leads' AND column_name = 'classificacao_lead') THEN
        ALTER TABLE public.leads ADD COLUMN classificacao_lead VARCHAR(20) DEFAULT 'Tier C';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'leads' AND column_name = 'motivo_descarte') THEN
        ALTER TABLE public.leads ADD COLUMN motivo_descarte VARCHAR(100);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'leads' AND column_name = 'data_qualificacao') THEN
        ALTER TABLE public.leads ADD COLUMN data_qualificacao TIMESTAMP;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'leads' AND column_name = 'data_descarte') THEN
        ALTER TABLE public.leads ADD COLUMN data_descarte TIMESTAMP;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'leads' AND column_name = 'atendente_designado') THEN
        ALTER TABLE public.leads ADD COLUMN atendente_designado VARCHAR(100);
    END IF;

    -- Validação de Estados Válidos do Funil de Leads (inclui Desqualificado)
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_leads_status_funil_valido') THEN
        ALTER TABLE public.leads DROP CONSTRAINT chk_leads_status_funil_valido;
    END IF;
    ALTER TABLE public.leads ADD CONSTRAINT chk_leads_status_funil_valido 
        CHECK (status_funil IN ('Frio', 'Morno', 'Quente', 'Convertido', 'Perdido', 'Desqualificado'));

    -- Validação de Classificações Válidas de Leads
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_leads_classificacao_valida') THEN
        ALTER TABLE public.leads ADD CONSTRAINT chk_leads_classificacao_valida 
            CHECK (classificacao_lead IN ('Tier A', 'Tier B', 'Tier C', 'Desqualificado'));
    END IF;

    -- Validação de Estados de Recuperação de Carrinhos
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_carrinhos_status_valido') THEN
        ALTER TABLE public.carrinhos_abandonados ADD CONSTRAINT chk_carrinhos_status_valido 
            CHECK (status_recuperacao IN ('Pendente', 'Disparado_WhatsApp', 'Disparado_Email', 'Recuperado', 'Expirado'));
    END IF;

    -- Validação de Coerência de Datas em Campanhas de Marketing
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_campanhas_datas_coerentes') THEN
        ALTER TABLE public.campanhas_marketing ADD CONSTRAINT chk_campanhas_datas_coerentes 
            CHECK (data_fim IS NULL OR data_inicio IS NULL OR data_fim >= data_inicio);
    END IF;

    -- Migração FK Idempotente: Garante ON DELETE SET NULL em carrinhos_abandonados.pedido_gerado_id
    -- Cobre deployments existentes onde a FK foi criada sem SET NULL (confdeltype 'a'=NO ACTION, 'r'=RESTRICT)
    IF EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'carrinhos_abandonados_pedido_gerado_id_fkey'
          AND confdeltype != 'n'
    ) THEN
        ALTER TABLE public.carrinhos_abandonados 
            DROP CONSTRAINT carrinhos_abandonados_pedido_gerado_id_fkey;
        ALTER TABLE public.carrinhos_abandonados 
            ADD CONSTRAINT carrinhos_abandonados_pedido_gerado_id_fkey 
            FOREIGN KEY (pedido_gerado_id) REFERENCES public.pedidos(id) ON DELETE SET NULL;
    END IF;
END $$;

-- ===============================================================================
-- 10. DATA WAREHOUSE & ANALYTICS VIEWS (METABASE / NOCODB / SRE BI)
-- ===============================================================================
-- Integração dos bancos dos microsserviços via Foreign Data Wrapper (FDW)
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Servidores Estrangeiros (Mapeamento interno localhost)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'srv_chatwoot') THEN
        CREATE SERVER srv_chatwoot FOREIGN DATA WRAPPER postgres_fdw 
            OPTIONS (host 'localhost', port '5432', dbname 'chatwoot_db');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'srv_shlink') THEN
        CREATE SERVER srv_shlink FOREIGN DATA WRAPPER postgres_fdw 
            OPTIONS (host 'localhost', port '5432', dbname 'shlink_db');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'srv_listmonk') THEN
        CREATE SERVER srv_listmonk FOREIGN DATA WRAPPER postgres_fdw 
            OPTIONS (host 'localhost', port '5432', dbname 'listmonk_db');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'srv_umami') THEN
        CREATE SERVER srv_umami FOREIGN DATA WRAPPER postgres_fdw 
            OPTIONS (host 'localhost', port '5432', dbname 'umami_db');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'srv_evolution') THEN
        CREATE SERVER srv_evolution FOREIGN DATA WRAPPER postgres_fdw 
            OPTIONS (host 'localhost', port '5432', dbname 'evolution_db');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'srv_postiz') THEN
        CREATE SERVER srv_postiz FOREIGN DATA WRAPPER postgres_fdw 
            OPTIONS (host 'localhost', port '5432', dbname 'postiz_db');
    END IF;
END $$;

-- Criação dos Schemas FDW para isolamento
CREATE SCHEMA IF NOT EXISTS fdw_chatwoot;
CREATE SCHEMA IF NOT EXISTS fdw_shlink;
CREATE SCHEMA IF NOT EXISTS fdw_listmonk;
CREATE SCHEMA IF NOT EXISTS fdw_umami;
CREATE SCHEMA IF NOT EXISTS fdw_evolution;
CREATE SCHEMA IF NOT EXISTS fdw_postiz;

-- Foreign Tables do Chatwoot CRM
CREATE FOREIGN TABLE IF NOT EXISTS fdw_chatwoot.conversations (
    id integer,
    display_id integer,
    status integer,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    first_reply_created_at timestamp with time zone,
    assignee_id integer,
    contact_id integer
) SERVER srv_chatwoot OPTIONS (schema_name 'public', table_name 'conversations');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_chatwoot.users (
    id integer,
    name text,
    email text
) SERVER srv_chatwoot OPTIONS (schema_name 'public', table_name 'users');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_chatwoot.contacts (
    id integer,
    name text,
    phone_number text,
    email text
) SERVER srv_chatwoot OPTIONS (schema_name 'public', table_name 'contacts');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_chatwoot.csat_survey_responses (
    id integer,
    conversation_id integer,
    rating integer,
    feedback_message text
) SERVER srv_chatwoot OPTIONS (schema_name 'public', table_name 'csat_survey_responses');

-- Foreign Tables do Shlink (Encurtador de Links)
CREATE FOREIGN TABLE IF NOT EXISTS fdw_shlink.short_urls (
    id integer,
    short_code text,
    title text,
    original_url text,
    date_created timestamp with time zone
) SERVER srv_shlink OPTIONS (schema_name 'public', table_name 'short_urls');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_shlink.visits (
    id integer,
    short_url_id integer,
    visit_location_id integer,
    date timestamp with time zone,
    referer text,
    user_agent text,
    potential_bot boolean
) SERVER srv_shlink OPTIONS (schema_name 'public', table_name 'visits');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_shlink.visit_locations (
    id integer,
    country_name text,
    city_name text,
    region_name text
) SERVER srv_shlink OPTIONS (schema_name 'public', table_name 'visit_locations');

-- Foreign Tables do Umami (Analytics)
CREATE FOREIGN TABLE IF NOT EXISTS fdw_umami.website (
    website_id uuid,
    name text,
    domain text
) SERVER srv_umami OPTIONS (schema_name 'public', table_name 'website');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_umami.session (
    session_id uuid,
    website_id uuid,
    browser text,
    os text,
    device text,
    country text,
    city text
) SERVER srv_umami OPTIONS (schema_name 'public', table_name 'session');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_umami.website_event (
    event_id uuid,
    website_id uuid,
    session_id uuid,
    created_at timestamp with time zone,
    url_path text,
    referrer_domain text,
    page_title text,
    utm_source text,
    utm_medium text,
    utm_campaign text
) SERVER srv_umami OPTIONS (schema_name 'public', table_name 'website_event');

-- Foreign Tables do Listmonk com tipos universais
CREATE FOREIGN TABLE IF NOT EXISTS fdw_listmonk.campaigns (
    id integer,
    uuid uuid,
    name text,
    subject text,
    from_email text,
    body text,
    status text,
    type text,
    to_send integer,
    sent integer,
    started_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
) SERVER srv_listmonk OPTIONS (schema_name 'public', table_name 'campaigns');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_listmonk.subscribers (
    id integer,
    uuid uuid,
    email text,
    name text,
    attribs jsonb,
    status text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
) SERVER srv_listmonk OPTIONS (schema_name 'public', table_name 'subscribers');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_listmonk.campaign_views (
    campaign_id integer,
    subscriber_id integer,
    created_at timestamp with time zone
) SERVER srv_listmonk OPTIONS (schema_name 'public', table_name 'campaign_views');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_listmonk.link_clicks (
    campaign_id integer,
    subscriber_id integer,
    link_id integer,
    count integer,
    created_at timestamp with time zone
) SERVER srv_listmonk OPTIONS (schema_name 'public', table_name 'link_clicks');

-- Foreign Tables do Evolution API (WhatsApp)
CREATE FOREIGN TABLE IF NOT EXISTS fdw_evolution.messages (
    id text,
    key jsonb,
    "pushName" text,
    participant text,
    "messageType" text,
    message jsonb,
    source text,
    "messageTimestamp" integer,
    "chatwootMessageId" integer,
    "chatwootConversationId" integer,
    "chatwootIsRead" boolean,
    "instanceId" text,
    status text
) SERVER srv_evolution OPTIONS (schema_name 'public', table_name 'Message');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_evolution.instances (
    id text,
    name text,
    status text,
    "connectionStatus" text
) SERVER srv_evolution OPTIONS (schema_name 'public', table_name 'Instance');

-- Foreign Tables do Postiz (Social Media Planner)
CREATE FOREIGN TABLE IF NOT EXISTS fdw_postiz.posts (
    id text,
    state text,
    "publishDate" timestamp without time zone,
    "organizationId" text,
    "integrationId" text,
    content text,
    title text,
    "createdAt" timestamp without time zone,
    "updatedAt" timestamp without time zone
) SERVER srv_postiz OPTIONS (schema_name 'public', table_name 'Post');

CREATE FOREIGN TABLE IF NOT EXISTS fdw_postiz.integrations (
    id text,
    identifier text,
    name text,
    "providerIdentifier" text
) SERVER srv_postiz OPTIONS (schema_name 'public', table_name 'Integration');

-- VIEWS ANALÍTICAS UNIFICADAS PARA METABASE & NOCODB

-- A) Métricas Executivas de Atendimento & CSAT (Chatwoot)
CREATE OR REPLACE VIEW vw_kpi_atendimento AS
SELECT 
    c.id AS conversa_id,
    c.display_id,
    c.status AS status_codigo,
    CASE 
        WHEN c.status = 0 THEN 'Aberto'
        WHEN c.status = 1 THEN 'Resolvido'
        WHEN c.status = 2 THEN 'Pendente'
        WHEN c.status = 3 THEN 'Adiado'
        ELSE 'Outro'
    END AS status_descricao,
    c.created_at AS data_abertura,
    c.first_reply_created_at AS data_primeira_resposta,
    ROUND(EXTRACT(EPOCH FROM (c.first_reply_created_at - c.created_at)) / 60.0, 2) AS tempo_primeira_resposta_minutos,
    c.updated_at AS data_resolucao,
    ROUND(EXTRACT(EPOCH FROM (c.updated_at - c.created_at)) / 60.0, 2) AS tempo_resolucao_minutos,
    u.id AS atendente_id,
    u.name AS atendente_nome,
    u.email AS atendente_email,
    ct.id AS contato_id,
    ct.name AS contato_nome,
    ct.phone_number AS contato_telefone,
    csat.rating AS csat_nota,
    csat.feedback_message AS csat_comentario
FROM fdw_chatwoot.conversations c
LEFT JOIN fdw_chatwoot.users u ON c.assignee_id = u.id
LEFT JOIN fdw_chatwoot.contacts ct ON c.contact_id = ct.id
LEFT JOIN fdw_chatwoot.csat_survey_responses csat ON csat.conversation_id = c.id;

-- B) Métricas de Marketing & Tráfego de Links Curtos (Shlink)
CREATE OR REPLACE VIEW vw_kpi_marketing_links AS
SELECT 
    s.id AS link_id,
    s.short_code,
    s.title AS titulo_campanha,
    s.original_url AS url_destino,
    s.date_created AS data_criacao,
    v.id AS visita_id,
    v.date AS data_visita,
    v.referer AS origem_trafego,
    v.user_agent AS navegador_dispositivo,
    v.potential_bot AS e_robo,
    loc.country_name AS pais,
    loc.city_name AS cidade,
    loc.region_name AS estado
FROM fdw_shlink.short_urls s
LEFT JOIN fdw_shlink.visits v ON v.short_url_id = s.id
LEFT JOIN fdw_shlink.visit_locations loc ON v.visit_location_id = loc.id;

-- C) Métricas de E-mail Marketing & Campanhas (Listmonk)
CREATE OR REPLACE VIEW vw_kpi_email_marketing AS
SELECT 
    c.id AS campanha_id,
    c.name AS campanha_nome,
    c.subject AS assunto,
    c.status AS status,
    c.sent AS emails_enviados,
    c.to_send AS total_destinatarios,
    c.started_at AS data_inicio_envio,
    c.created_at AS data_criacao,
    COUNT(DISTINCT v.subscriber_id) AS total_aberturas_unicas,
    COUNT(DISTINCT cl.subscriber_id) AS total_cliques_unicos,
    ROUND((COUNT(DISTINCT v.subscriber_id)::numeric / NULLIF(c.sent, 0)) * 100, 2) AS taxa_abertura_perc,
    ROUND((COUNT(DISTINCT cl.subscriber_id)::numeric / NULLIF(c.sent, 0)) * 100, 2) AS taxa_clique_perc
FROM fdw_listmonk.campaigns c
LEFT JOIN fdw_listmonk.campaign_views v ON v.campaign_id = c.id
LEFT JOIN fdw_listmonk.link_clicks cl ON cl.campaign_id = c.id
GROUP BY c.id, c.name, c.subject, c.status, c.sent, c.to_send, c.started_at, c.created_at;

-- D) Métricas de Tráfego Web & UTMs (Umami)
CREATE OR REPLACE VIEW vw_kpi_trafego_web AS
SELECT 
    w.website_id AS site_id,
    w.name AS site_nome,
    w.domain AS site_dominio,
    e.event_id,
    e.created_at AS data_evento,
    e.url_path AS pagina_acessada,
    e.referrer_domain AS dominio_referencia,
    e.utm_source,
    e.utm_medium,
    e.utm_campaign,
    s.session_id,
    s.browser AS navegador,
    s.os AS sistema_operacional,
    s.device AS tipo_dispositivo,
    s.country AS pais,
    s.city AS cidade
FROM fdw_umami.website_event e
JOIN fdw_umami.website w ON e.website_id = w.website_id
JOIN fdw_umami.session s ON e.session_id = s.session_id;

-- E) Métricas de Mensageria & Disparos WhatsApp (Evolution API)
CREATE OR REPLACE VIEW vw_kpi_whatsapp_disparos AS
SELECT 
    m.id AS mensagem_id,
    m."pushName" AS contato_nome,
    m.participant AS numero_remetente,
    m."messageType" AS tipo_mensagem,
    m.source AS dispositivo_origem,
    to_timestamp(m."messageTimestamp") AS data_envio,
    m.status AS status_entrega,
    m."chatwootConversationId" AS chatwoot_conversa_id,
    m."chatwootIsRead" AS lida_no_chatwoot,
    i.name AS instancia_nome,
    i.status AS instancia_status
FROM fdw_evolution.messages m
LEFT JOIN fdw_evolution.instances i ON m."instanceId" = i.id;

-- F) Métricas de Redes Sociais & Publicações (Postiz)
CREATE OR REPLACE VIEW vw_kpi_redes_sociais AS
SELECT 
    p.id AS post_id,
    p.title AS titulo_post,
    p.content AS conteudo,
    p.state AS status_publicacao,
    p."publishDate" AS data_agendamento,
    p."createdAt" AS data_criacao,
    i.name AS conta_rede_social,
    i."providerIdentifier" AS plataforma_social
FROM fdw_postiz.posts p
LEFT JOIN fdw_postiz.integrations i ON p."integrationId" = i.id;

-- G) Cruzamento Completo do Funil de Conversão (OmniChannel)
CREATE OR REPLACE VIEW vw_funil_executivo_completo AS
SELECT 
    cl.id AS cliente_id,
    cl.nome AS cliente_nome,
    cl.email AS cliente_email,
    cl.whatsapp AS cliente_whatsapp,
    cl.grupo AS cliente_segmento,
    cl.data_cadastro,
    l.id AS lead_id,
    l.origem_captura,
    l.status_funil,
    l.data_captura,
    p.id AS pedido_id,
    p.numero_pedido,
    p.valor_total AS pedido_faturamento,
    p.status_operacional AS pedido_status,
    p.data_criacao AS data_pedido,
    cw.conversa_id,
    cw.atendente_nome,
    cw.csat_nota
FROM public.clientes cl
LEFT JOIN public.leads l ON (l.documento_pj = cl.documento OR l.contato_identificado = cl.whatsapp)
LEFT JOIN public.pedidos p ON p.cliente_id = cl.id
LEFT JOIN vw_kpi_atendimento cw ON cw.contato_id = cl.chatwoot_contact_id;

-- H) Gestão de Lucro Real e DRE Operacional por Pedido
CREATE OR REPLACE VIEW vw_gestao_lucro_real AS
SELECT 
    p.id AS pedido_id,
    p.numero_pedido,
    p.data_criacao,
    p.data_criacao::DATE AS data_pedido,
    cl.nome AS cliente_nome,
    cl.whatsapp AS cliente_whatsapp,
    p.status_operacional,
    
    -- 1. Faturamento Bruto e Deduções
    p.valor_total AS faturamento_bruto,
    COALESCE(p.valor_desconto, 0.00) AS valor_desconto,
    COALESCE(p.valor_frete, 0.00) AS frete_cobrado_cliente,
    
    -- 2. Custos Variáveis da Venda
    COALESCE(p.custo_produtos_cmv, 0.00) AS custo_produtos_cmv,
    COALESCE(p.taxa_gateway, 0.00) AS taxas_gateway,
    COALESCE(p.despesa_frete_real, 0.00) AS despesa_frete_real,
    COALESCE(p.despesa_marketing, 0.00) AS despesa_marketing_atribuida,
    
    -- 3. Total de Custos Variáveis
    (COALESCE(p.custo_produtos_cmv, 0.00) + 
     COALESCE(p.taxa_gateway, 0.00) + 
     COALESCE(p.despesa_frete_real, 0.00) + 
     COALESCE(p.despesa_marketing, 0.00)) AS total_custos_variaveis,
     
    -- 4. Lucro Líquido Real & Margem %
    (p.valor_total - 
     (COALESCE(p.custo_produtos_cmv, 0.00) + 
      COALESCE(p.taxa_gateway, 0.00) + 
      COALESCE(p.despesa_frete_real, 0.00) + 
      COALESCE(p.despesa_marketing, 0.00))) AS lucro_liquido_real,
      
    ROUND(
        CASE 
            WHEN p.valor_total > 0 THEN 
                ((p.valor_total - 
                  (COALESCE(p.custo_produtos_cmv, 0.00) + 
                   COALESCE(p.taxa_gateway, 0.00) + 
                   COALESCE(p.despesa_frete_real, 0.00) + 
                   COALESCE(p.despesa_marketing, 0.00))) / p.valor_total) * 100.0
            ELSE 0.00 
        END, 2
    ) AS margem_liquida_perc
FROM public.pedidos p
LEFT JOIN public.clientes cl ON p.cliente_id = cl.id;

-- I) DRE Diário Consolidado (Vendas + CMV + Taxas + Ads = Lucro Líquido & ROAS)
CREATE OR REPLACE VIEW vw_dre_diario_consolidado AS
WITH vendas_dia AS (
    SELECT 
        p.data_criacao::DATE AS data_referencia,
        COUNT(p.id) AS total_pedidos,
        SUM(p.valor_total) AS faturamento_bruto,
        SUM(COALESCE(p.custo_produtos_cmv, 0.00)) AS total_cmv,
        SUM(COALESCE(p.taxa_gateway, 0.00)) AS total_taxas_gateway,
        SUM(COALESCE(p.despesa_frete_real, 0.00)) AS total_frete_real
    FROM public.pedidos p
    WHERE LOWER(p.status_operacional) NOT IN ('cancelado', 'devolvido', 'estornado')
    GROUP BY p.data_criacao::DATE
),
marketing_dia AS (
    SELECT 
        dm.data_despesa AS data_referencia,
        SUM(dm.valor) AS total_investimento_marketing
    FROM public.despesas_marketing dm
    GROUP BY dm.data_despesa
)
SELECT 
    COALESCE(v.data_referencia, m.data_referencia) AS data_referencia,
    COALESCE(v.total_pedidos, 0) AS total_pedidos,
    COALESCE(v.faturamento_bruto, 0.00) AS faturamento_bruto,
    COALESCE(v.total_cmv, 0.00) AS total_cmv,
    COALESCE(v.total_taxas_gateway, 0.00) AS total_taxas_gateway,
    COALESCE(v.total_frete_real, 0.00) AS total_frete_real,
    COALESCE(m.total_investimento_marketing, 0.00) AS investimento_marketing,
    
    -- Lucro Líquido Real Operacional
    (COALESCE(v.faturamento_bruto, 0.00) - 
     (COALESCE(v.total_cmv, 0.00) + 
      COALESCE(v.total_taxas_gateway, 0.00) + 
      COALESCE(v.total_frete_real, 0.00) + 
      COALESCE(m.total_investimento_marketing, 0.00))) AS lucro_liquido_dia,
      
    -- Margem Líquida % do Dia
    ROUND(
        CASE 
            WHEN COALESCE(v.faturamento_bruto, 0.00) > 0 THEN 
                ((COALESCE(v.faturamento_bruto, 0.00) - 
                  (COALESCE(v.total_cmv, 0.00) + 
                   COALESCE(v.total_taxas_gateway, 0.00) + 
                   COALESCE(v.total_frete_real, 0.00) + 
                   COALESCE(m.total_investimento_marketing, 0.00))) / v.faturamento_bruto) * 100.0
            ELSE 0.00 
        END, 2
    ) AS margem_liquida_perc,
    
    -- ROAS (Retorno sobre Gasto em Anúncios: Faturamento / Ads)
    ROUND(
        CASE 
            WHEN COALESCE(m.total_investimento_marketing, 0.00) > 0 THEN 
                COALESCE(v.faturamento_bruto, 0.00) / m.total_investimento_marketing
            ELSE 0.00 
        END, 2
    ) AS roas_dia
FROM vendas_dia v
FULL OUTER JOIN marketing_dia m ON v.data_referencia = m.data_referencia;

-- J) Alerta Executivo de Estoque Crítico (Produtos & Insumos de Expedição)
CREATE OR REPLACE VIEW vw_estoque_critico AS
SELECT 
    'PRODUTO' AS tipo_item,
    c.id_interno AS item_id,
    c.sku AS identificador,
    c.nome AS item_nome,
    c.quantidade_estoque AS saldo_atual,
    c.estoque_minimo AS nivel_minimo,
    (c.estoque_minimo - c.quantidade_estoque) AS deficit_reposicao,
    CASE 
        WHEN c.quantidade_estoque <= 0 THEN 'RUPTURA_TOTAL'
        WHEN c.quantidade_estoque < (c.estoque_minimo * 0.5) THEN 'CRITICO_URGENTE'
        ELSE 'ABAIXO_DO_MINIMO'
    END AS status_alerta,
    c.custo_unitario AS custo_reposicao_unitario,
    'Estoque de Venda' AS setor_responsavel,
    c.data_sincronizacao AS ultima_atualizacao
FROM public.catalogo c
WHERE c.quantidade_estoque <= c.estoque_minimo

UNION ALL

SELECT 
    'INSUMO' AS tipo_item,
    i.id AS item_id,
    'INS-' || i.id AS identificador,
    i.item_nome || ' [' || COALESCE(i.tipo_insumo, 'OUTRO') || ']' AS item_nome,
    i.quantidade_atual AS saldo_atual,
    i.estoque_minimo AS nivel_minimo,
    (i.estoque_minimo - i.quantidade_atual) AS deficit_reposicao,
    CASE 
        WHEN i.quantidade_atual <= 0 THEN 'RUPTURA_TOTAL'
        WHEN i.quantidade_atual < (i.estoque_minimo * 0.5) THEN 'CRITICO_URGENTE'
        ELSE 'ABAIXO_DO_MINIMO'
    END AS status_alerta,
    0.00 AS custo_reposicao_unitario,
    COALESCE(i.fornecedor_nome, 'Expedição / Embalagens') AS setor_responsavel,
    i.ultima_atualizacao
FROM public.insumos i
WHERE i.quantidade_atual <= i.estoque_minimo;

-- K) Calculadora Executiva de Performance e Conversão de Leads (CPL, CAC & ROAS)
CREATE OR REPLACE VIEW vw_calculadora_leads_metricas AS
WITH metricas_base AS (
    SELECT 
        l.origem_captura,
        COUNT(DISTINCT l.id) AS total_leads_capturados,
        COUNT(DISTINCT CASE WHEN l.status_funil = 'Frio' THEN l.id END) AS leads_frios,
        COUNT(DISTINCT CASE WHEN l.status_funil = 'Morno' THEN l.id END) AS leads_mornos,
        COUNT(DISTINCT CASE WHEN l.status_funil = 'Quente' THEN l.id END) AS leads_quentes,
        COUNT(DISTINCT CASE WHEN l.status_funil = 'Convertido' OR p.id IS NOT NULL THEN l.id END) AS leads_convertidos,
        
        -- Financeiro gerado pelos pedidos convertidos
        COALESCE(SUM(p.valor_total), 0.00) AS faturamento_gerado_total,
        COALESCE(SUM(p.custo_produtos_cmv), 0.00) AS cmv_total_gerado,
        COALESCE(SUM(p.taxa_gateway), 0.00) AS taxas_gateway_total,
        
        -- Tempo Médio até a Primeira Compra (em dias)
        ROUND(AVG(EXTRACT(EPOCH FROM (p.data_criacao - l.data_captura)) / 86400.0)::numeric, 1) AS tempo_medio_conversao_dias
    FROM public.leads l
    LEFT JOIN public.clientes cl ON (cl.documento = l.documento_pj OR cl.whatsapp = l.contato_identificado)
    LEFT JOIN public.pedidos p ON p.cliente_id = cl.id AND LOWER(p.status_operacional) NOT IN ('cancelado', 'devolvido', 'estornado')
    GROUP BY l.origem_captura
),
despesas_canal AS (
    SELECT 
        dm.canal AS origem_captura,
        SUM(dm.valor) AS total_investido
    FROM public.despesas_marketing dm
    GROUP BY dm.canal
)
SELECT 
    b.origem_captura AS canal_ou_origem,
    b.total_leads_capturados,
    b.leads_frios,
    b.leads_mornos,
    b.leads_quentes,
    b.leads_convertidos,
    
    -- Taxa de Conversão Geral do Canal (%)
    ROUND(
        CASE 
            WHEN b.total_leads_capturados > 0 THEN 
                (b.leads_convertidos::numeric / b.total_leads_capturados) * 100.0 
            ELSE 0.00 
        END, 2
    ) AS taxa_conversao_perc,
    
    -- Investimento registrado em anúncios/marketing
    COALESCE(d.total_investido, 0.00) AS investimento_marketing,
    
    -- CPL (Custo por Lead)
    ROUND(
        CASE 
            WHEN b.total_leads_capturados > 0 AND COALESCE(d.total_investido, 0.00) > 0 THEN 
                d.total_investido / b.total_leads_capturados 
            ELSE 0.00 
        END, 2
    ) AS custo_por_lead_cpl,
    
    -- CAC (Custo de Aquisição por Cliente Convertido)
    ROUND(
        CASE 
            WHEN b.leads_convertidos > 0 AND COALESCE(d.total_investido, 0.00) > 0 THEN 
                d.total_investido / b.leads_convertidos 
            ELSE 0.00 
        END, 2
    ) AS cac_por_cliente,
    
    -- Retorno Financeiro
    b.faturamento_gerado_total,
    ROUND(
        CASE 
            WHEN b.leads_convertidos > 0 THEN 
                b.faturamento_gerado_total / b.leads_convertidos 
            ELSE 0.00 
        END, 2
    ) AS ticket_medio_por_conversao,
    
    -- Lucro Líquido Real atribuído a esta origem de leads
    (b.faturamento_gerado_total - 
     (b.cmv_total_gerado + b.taxas_gateway_total + COALESCE(d.total_investido, 0.00))) AS lucro_liquido_gerado,
     
    -- ROAS do Canal (Faturamento / Investimento)
    ROUND(
        CASE 
            WHEN COALESCE(d.total_investido, 0.00) > 0 THEN 
                b.faturamento_gerado_total / d.total_investido 
            ELSE 0.00 
        END, 2
    ) AS roas_canal,
    
    -- Velocidade de Conversão
    COALESCE(b.tempo_medio_conversao_dias, 0.0) AS tempo_medio_conversao_dias

FROM metricas_base b
LEFT JOIN despesas_canal d ON LOWER(TRIM(d.origem_captura)) = LOWER(TRIM(b.origem_captura));

-- L) Atribuição Multi-Canal & Tráfego UTM 360° (Umami + Shlink + Pedidos)
-- SRE Fix: Atribuição direta por UTMs nativas do pedido com fallback em campanhas
CREATE OR REPLACE VIEW vw_atribuicao_utm_360 AS
WITH eventos_utm AS (
    SELECT 
        COALESCE(NULLIF(e.utm_source, ''), '(direto/organico)') AS utm_source,
        COALESCE(NULLIF(e.utm_medium, ''), '(nenhum)') AS utm_medium,
        COALESCE(NULLIF(e.utm_campaign, ''), '(geral)') AS utm_campaign,
        COUNT(DISTINCT e.session_id) AS total_visitas_unicas,
        COUNT(e.event_id) AS total_eventos
    FROM fdw_umami.website_event e
    GROUP BY 
        COALESCE(NULLIF(e.utm_source, ''), '(direto/organico)'),
        COALESCE(NULLIF(e.utm_medium, ''), '(nenhum)'),
        COALESCE(NULLIF(e.utm_campaign, ''), '(geral)')
),
vendas_utm AS (
    SELECT 
        COALESCE(NULLIF(p.utm_source, ''), NULLIF(c.utm_source, ''), '(direto/organico)') AS utm_source,
        COALESCE(NULLIF(p.utm_medium, ''), NULLIF(c.utm_medium, ''), '(nenhum)') AS utm_medium,
        COALESCE(NULLIF(p.utm_campaign, ''), NULLIF(c.utm_campaign, ''), '(geral)') AS utm_campaign,
        COUNT(p.id) AS total_pedidos_atribuidos,
        SUM(p.valor_total) AS faturamento_atribuido,
        SUM(COALESCE(p.custo_produtos_cmv, 0.00)) AS cmv_atribuido,
        SUM(COALESCE(p.taxa_gateway, 0.00)) AS taxas_gateway_atribuidas
    FROM public.pedidos p
    LEFT JOIN public.campanhas_marketing c ON p.utm_campaign = c.utm_campaign
    WHERE LOWER(p.status_operacional) NOT IN ('cancelado', 'devolvido', 'estornado')
    GROUP BY 
        COALESCE(NULLIF(p.utm_source, ''), NULLIF(c.utm_source, ''), '(direto/organico)'),
        COALESCE(NULLIF(p.utm_medium, ''), NULLIF(c.utm_medium, ''), '(nenhum)'),
        COALESCE(NULLIF(p.utm_campaign, ''), NULLIF(c.utm_campaign, ''), '(geral)')
)
SELECT 
    COALESCE(u.utm_source, v.utm_source) AS utm_source,
    COALESCE(u.utm_medium, v.utm_medium) AS utm_medium,
    COALESCE(u.utm_campaign, v.utm_campaign) AS utm_campaign,
    COALESCE(u.total_visitas_unicas, 0) AS visitas_site,
    COALESCE(v.total_pedidos_atribuidos, 0) AS vendas_realizadas,
    COALESCE(v.faturamento_atribuido, 0.00) AS faturamento_bruto,
    COALESCE(v.cmv_atribuido, 0.00) AS total_cmv,
    COALESCE(v.taxas_gateway_atribuidas, 0.00) AS total_taxas,
    (COALESCE(v.faturamento_atribuido, 0.00) - (COALESCE(v.cmv_atribuido, 0.00) + COALESCE(v.taxas_gateway_atribuidas, 0.00))) AS lucro_bruto_atribuido,
    ROUND(
        CASE 
            WHEN COALESCE(u.total_visitas_unicas, 0) > 0 THEN 
                (COALESCE(v.total_pedidos_atribuidos, 0)::numeric / u.total_visitas_unicas) * 100.0 
            ELSE 0.00 
        END, 2
    ) AS taxa_conversao_visita_para_venda_perc,
    ROUND(
        CASE 
            WHEN COALESCE(v.total_pedidos_atribuidos, 0) > 0 THEN 
                COALESCE(v.faturamento_atribuido, 0.00) / v.total_pedidos_atribuidos 
            ELSE 0.00 
        END, 2
    ) AS ticket_medio
FROM eventos_utm u
FULL OUTER JOIN vendas_utm v ON v.utm_source = u.utm_source AND v.utm_medium = u.utm_medium AND v.utm_campaign = u.utm_campaign;

-- M) Matriz RFM e Segmentação Inteligente de Clientes (Recência, Frequência & LTV)
CREATE OR REPLACE VIEW vw_matriz_rfm_clientes AS
WITH stats_cliente AS (
    SELECT 
        cl.id AS cliente_id,
        cl.nome AS cliente_nome,
        cl.whatsapp AS cliente_whatsapp,
        cl.email AS cliente_email,
        cl.data_cadastro,
        COUNT(p.id) AS frequencia_pedidos,
        COALESCE(SUM(p.valor_total), 0.00) AS ltv_total_gasto,
        MAX(p.data_criacao) AS data_ultimo_pedido,
        ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(p.data_criacao))) / 86400.0) AS dias_sem_comprar
    FROM public.clientes cl
    LEFT JOIN public.pedidos p ON p.cliente_id = cl.id AND LOWER(p.status_operacional) NOT IN ('cancelado', 'devolvido', 'estornado')
    GROUP BY cl.id, cl.nome, cl.whatsapp, cl.email, cl.data_cadastro
)
SELECT 
    cliente_id,
    cliente_nome,
    cliente_whatsapp,
    cliente_email,
    frequencia_pedidos AS total_compras,
    ltv_total_gasto AS ltv_acumulado,
    data_ultimo_pedido,
    COALESCE(dias_sem_comprar, 999) AS dias_desde_ultima_compra,
    
    -- Score de Recência (1 a 5)
    CASE 
        WHEN dias_sem_comprar <= 30 THEN 5
        WHEN dias_sem_comprar <= 60 THEN 4
        WHEN dias_sem_comprar <= 120 THEN 3
        WHEN dias_sem_comprar <= 240 THEN 2
        ELSE 1
    END AS score_recencia,
    
    -- Score de Frequência (1 a 5)
    CASE 
        WHEN frequencia_pedidos >= 10 THEN 5
        WHEN frequencia_pedidos >= 5 THEN 4
        WHEN frequencia_pedidos >= 3 THEN 3
        WHEN frequencia_pedidos >= 2 THEN 2
        WHEN frequencia_pedidos = 1 THEN 1
        ELSE 0
    END AS score_frequencia,
    
    -- Score Monetário / LTV (1 a 5)
    CASE 
        WHEN ltv_total_gasto >= 3000 THEN 5
        WHEN ltv_total_gasto >= 1500 THEN 4
        WHEN ltv_total_gasto >= 800 THEN 3
        WHEN ltv_total_gasto >= 300 THEN 2
        WHEN ltv_total_gasto > 0 THEN 1
        ELSE 0
    END AS score_monetario,
    
    -- Segmentação Comportamental Automática
    CASE 
        WHEN frequencia_pedidos = 0 THEN '🐣 Lead Cadastrado (Nunca Comprou)'
        WHEN frequencia_pedidos >= 5 AND dias_sem_comprar <= 45 THEN '🏆 Campeões / VIP'
        WHEN frequencia_pedidos >= 2 AND dias_sem_comprar <= 60 THEN '💎 Clientes Leais'
        WHEN frequencia_pedidos = 1 AND dias_sem_comprar <= 30 THEN '🌱 Novos Compradores'
        WHEN frequencia_pedidos >= 2 AND dias_sem_comprar > 90 THEN '⚠️ Em Risco de Churn'
        WHEN dias_sem_comprar > 180 THEN '💤 Inativos / Precisam de Reativação'
        ELSE '🎯 Compradores Regulares'
    END AS segmento_cliente

FROM stats_cliente;

-- N) Métricas de Recompra, Ciclo de Vida e Retenção
-- SRE Fix: Otimização O(N) com Window Function LAG() substituindo Self-Join Cartesiano
CREATE OR REPLACE VIEW vw_recompra_e_ciclo_de_vida AS
WITH cliente_compras AS (
    SELECT 
        cl.id AS cliente_id,
        COUNT(p.id) AS total_pedidos,
        SUM(p.valor_total) AS total_gasto,
        MIN(p.data_criacao) AS primeira_compra,
        MAX(p.data_criacao) AS ultima_compra
    FROM public.clientes cl
    JOIN public.pedidos p ON p.cliente_id = cl.id AND LOWER(p.status_operacional) NOT IN ('cancelado', 'devolvido', 'estornado')
    GROUP BY cl.id
),
pedidos_ordenados AS (
    SELECT 
        cliente_id,
        data_criacao,
        LAG(data_criacao) OVER (PARTITION BY cliente_id ORDER BY data_criacao) AS data_pedido_anterior
    FROM public.pedidos
    WHERE LOWER(status_operacional) NOT IN ('cancelado', 'devolvido', 'estornado')
),
intervalos_pedidos AS (
    SELECT 
        cliente_id,
        ROUND(AVG(EXTRACT(EPOCH FROM (data_criacao - data_pedido_anterior)) / 86400.0)) AS dias_entre_pedidos
    FROM pedidos_ordenados
    WHERE data_pedido_anterior IS NOT NULL
    GROUP BY cliente_id
)
SELECT 
    COUNT(c.cliente_id) AS total_clientes_compradores,
    COUNT(CASE WHEN c.total_pedidos > 1 THEN c.cliente_id END) AS clientes_recorrentes,
    COUNT(CASE WHEN c.total_pedidos = 1 THEN c.cliente_id END) AS clientes_compra_unica,
    
    -- Taxa de Recompra (%)
    ROUND(
        (COUNT(CASE WHEN c.total_pedidos > 1 THEN c.cliente_id END)::numeric / NULLIF(COUNT(c.cliente_id), 0)) * 100.0, 2
    ) AS taxa_recompra_perc,
    
    -- LTV Médio Geral
    ROUND(AVG(c.total_gasto), 2) AS ltv_medio_cliente,
    
    -- Ticket Médio Geral
    ROUND(SUM(c.total_gasto) / NULLIF(SUM(c.total_pedidos), 0), 2) AS ticket_medio_geral,
    
    -- Intervalo Médio de Recompra (em dias)
    COALESCE(ROUND(AVG(i.dias_entre_pedidos)), 0) AS intervalo_medio_recompra_dias

FROM cliente_compras c
LEFT JOIN intervalos_pedidos i ON i.cliente_id = c.cliente_id;

-- O) KPI de Recuperação de Vendas, Boletos e Carrinho Abandonado
CREATE OR REPLACE VIEW vw_kpi_recuperacao_vendas AS
SELECT 
    tipo_pendencia,
    status_recuperacao,
    COUNT(id) AS total_ocorrencias,
    SUM(valor_carrinho) AS valor_total_em_risco,
    SUM(CASE WHEN status_recuperacao = 'Recuperado' THEN valor_carrinho ELSE 0.00 END) AS valor_total_recuperado,
    ROUND(
        (COUNT(CASE WHEN status_recuperacao = 'Recuperado' THEN id END)::numeric / NULLIF(COUNT(id), 0)) * 100.0, 2
    ) AS taxa_recuperacao_perc,
    AVG(tentativas_contato) AS media_tentativas_contato,
    MIN(data_abandono) AS primeiro_abandono,
    MAX(data_abandono) AS ultimo_abandono
FROM public.carrinhos_abandonados
GROUP BY tipo_pendencia, status_recuperacao;

-- P) Correlação de Social Media & Publicações com Tráfego Web (Postiz + Umami)
CREATE OR REPLACE VIEW vw_social_media_engajamento_conversao AS
WITH posts_dia AS (
    SELECT 
        p."publishDate"::DATE AS data_post,
        i."providerIdentifier" AS rede_social,
        COUNT(p.id) AS total_posts_publicados,
        STRING_AGG(SUBSTRING(p.title FROM 1 FOR 40), ' | ') AS titulos_posts
    FROM fdw_postiz.posts p
    JOIN fdw_postiz.integrations i ON p."integrationId" = i.id
    WHERE p.state IN ('SCHEDULED', 'PUBLISHED')
    GROUP BY p."publishDate"::DATE, i."providerIdentifier"
),
trafego_dia AS (
    SELECT 
        e.created_at::DATE AS data_evento,
        COUNT(DISTINCT e.session_id) AS visitantes_unicos,
        COUNT(e.event_id) AS total_visualizacoes
    FROM fdw_umami.website_event e
    GROUP BY e.created_at::DATE
)
SELECT 
    COALESCE(p.data_post, t.data_evento) AS data_referencia,
    COALESCE(p.rede_social, 'Geral/Orgânico') AS canal_social,
    COALESCE(p.total_posts_publicados, 0) AS posts_publicados,
    p.titulos_posts,
    COALESCE(t.visitantes_unicos, 0) AS visitantes_unicos_site,
    COALESCE(t.total_visualizacoes, 0) AS visualizacoes_paginas
FROM posts_dia p
FULL OUTER JOIN trafego_dia t ON p.data_post = t.data_evento;

-- Q) Performance Comercial & Produtividade de Atendentes SDR (Chatwoot + Vendas)
CREATE OR REPLACE VIEW vw_performance_comercial_atendentes AS
SELECT 
    u.id AS atendente_id,
    u.name AS atendente_nome,
    u.email AS atendente_email,
    COUNT(DISTINCT c.id) AS total_conversas_atendidas,
    COUNT(DISTINCT CASE WHEN c.status = 1 THEN c.id END) AS conversas_resolvidas,
    ROUND(AVG(EXTRACT(EPOCH FROM (c.first_reply_created_at - c.created_at)) / 60.0), 1) AS tempo_medio_primeira_resposta_minutos,
    ROUND(AVG(EXTRACT(EPOCH FROM (c.updated_at - c.created_at)) / 60.0), 1) AS tempo_medio_resolucao_minutos,
    ROUND(AVG(csat.rating), 2) AS nota_media_csat,
    COUNT(DISTINCT p.id) AS vendas_convertidas,
    COALESCE(SUM(p.valor_total), 0.00) AS faturamento_gerado_atendente,
    ROUND(
        CASE 
            WHEN COUNT(DISTINCT c.id) > 0 THEN 
                (COUNT(DISTINCT p.id)::numeric / COUNT(DISTINCT c.id)) * 100.0 
            ELSE 0.00 
        END, 2
    ) AS taxa_conversao_atendimento_venda_perc
FROM fdw_chatwoot.users u
LEFT JOIN fdw_chatwoot.conversations c ON c.assignee_id = u.id
LEFT JOIN fdw_chatwoot.csat_survey_responses csat ON csat.conversation_id = c.id
LEFT JOIN fdw_chatwoot.contacts ct ON c.contact_id = ct.id
-- SRE Fix: Sanitização do número do Chatwoot (remover '+', parênteses, etc.) para matching universal com clientes.whatsapp
LEFT JOIN public.clientes cl ON cl.chatwoot_contact_id = ct.id OR cl.whatsapp = REGEXP_REPLACE(COALESCE(ct.phone_number, ''), '[^0-9]', '', 'g')
LEFT JOIN public.pedidos p ON p.cliente_id = cl.id AND LOWER(p.status_operacional) NOT IN ('cancelado', 'devolvido', 'estornado')
GROUP BY u.id, u.name, u.email;

-- R) Relatório Mensal Executivo para Agências e Gestores (Fechamento do Mês)
-- SRE Fix: DATE_TRUNC no GROUP BY habilita range scan em idx_pedidos_data_criacao.
-- CTEs usam TIMESTAMP tipado para JOIN eficiente; TO_CHAR só na projeção final para exibição.
CREATE OR REPLACE VIEW vw_relatorio_mensal_agencia AS
WITH vendas_mes AS (
    SELECT 
        DATE_TRUNC('month', p.data_criacao) AS mes_ref,
        COUNT(p.id) AS total_pedidos,
        COALESCE(SUM(p.valor_total), 0.00) AS faturamento_bruto,
        COALESCE(SUM(p.custo_produtos_cmv), 0.00) AS total_cmv,
        COALESCE(SUM(p.taxa_gateway), 0.00) AS total_taxas_gateway,
        COALESCE(SUM(p.despesa_frete_real), 0.00) AS total_frete_real,
        COUNT(DISTINCT p.cliente_id) AS clientes_compradores
    FROM public.pedidos p
    WHERE LOWER(p.status_operacional) NOT IN ('cancelado', 'devolvido', 'estornado')
    GROUP BY DATE_TRUNC('month', p.data_criacao)
),
ads_mes AS (
    SELECT 
        DATE_TRUNC('month', dm.data_despesa::TIMESTAMP) AS mes_ref,
        COALESCE(SUM(dm.valor), 0.00) AS total_investido_ads
    FROM public.despesas_marketing dm
    GROUP BY DATE_TRUNC('month', dm.data_despesa::TIMESTAMP)
),
leads_mes AS (
    SELECT 
        DATE_TRUNC('month', l.data_captura) AS mes_ref,
        COUNT(l.id) AS total_novos_leads
    FROM public.leads l
    GROUP BY DATE_TRUNC('month', l.data_captura)
),
carrinhos_mes AS (
    SELECT 
        DATE_TRUNC('month', ca.data_recuperacao) AS mes_ref,
        COUNT(ca.id) AS carrinhos_recuperados,
        COALESCE(SUM(ca.valor_carrinho), 0.00) AS faturamento_carrinhos_recuperado
    FROM public.carrinhos_abandonados ca
    WHERE ca.status_recuperacao = 'Recuperado' AND ca.data_recuperacao IS NOT NULL
    GROUP BY DATE_TRUNC('month', ca.data_recuperacao)
)
SELECT 
    TO_CHAR(v.mes_ref, 'YYYY-MM') AS mes_ano,  -- Exibição legível para Metabase/NocoDB
    v.mes_ref AS mes_data_referencia,            -- Timestamp tipado para filtros de range no BI
    v.total_pedidos,
    v.clientes_compradores,
    COALESCE(l.total_novos_leads, 0) AS novos_leads_capturados,
    COALESCE(c.carrinhos_recuperados, 0) AS vendas_recuperadas_whatsapp,
    COALESCE(c.faturamento_carrinhos_recuperado, 0.00) AS faturamento_recuperado_reais,
    
    -- Financeiro Consolidado com Blindagem Total contra NULLs
    v.faturamento_bruto,
    COALESCE(a.total_investido_ads, 0.00) AS total_investido_ads,
    COALESCE(v.total_cmv, 0.00) AS total_cmv,
    COALESCE(v.total_taxas_gateway, 0.00) AS total_taxas_gateway,
    COALESCE(v.total_frete_real, 0.00) AS total_frete_real,
    
    -- Lucro Líquido Real do Mês (Zero risco de virar NULL)
    (COALESCE(v.faturamento_bruto, 0.00) - (
        COALESCE(v.total_cmv, 0.00) + 
        COALESCE(v.total_taxas_gateway, 0.00) + 
        COALESCE(v.total_frete_real, 0.00) + 
        COALESCE(a.total_investido_ads, 0.00)
    )) AS lucro_liquido_real_mes,
    
    -- Margem Líquida %
    ROUND(
        ((COALESCE(v.faturamento_bruto, 0.00) - (
            COALESCE(v.total_cmv, 0.00) + 
            COALESCE(v.total_taxas_gateway, 0.00) + 
            COALESCE(v.total_frete_real, 0.00) + 
            COALESCE(a.total_investido_ads, 0.00)
        )) / NULLIF(v.faturamento_bruto, 0)) * 100.0, 2
    ) AS margem_liquida_mes_perc,
    
    -- ROAS Consolidado do Mês
    ROUND(
        COALESCE(v.faturamento_bruto, 0.00) / NULLIF(a.total_investido_ads, 0), 2
    ) AS roas_mensal,
    
    -- CAC Médio do Mês
    ROUND(
        COALESCE(a.total_investido_ads, 0.00) / NULLIF(v.clientes_compradores, 0), 2
    ) AS cac_medio_mes

FROM vendas_mes v
LEFT JOIN ads_mes a ON a.mes_ref = v.mes_ref
LEFT JOIN leads_mes l ON l.mes_ref = v.mes_ref
LEFT JOIN carrinhos_mes c ON c.mes_ref = v.mes_ref
ORDER BY v.mes_ref DESC;

-- ===============================================================================
-- 11. NOVAS VIEWS ANALÍTICAS: RANKING, TRIAGEM E DESCARTE DE LEADS (SRE CRM / BI)
-- ===============================================================================

-- S) Ranking de Leads, Score ICP e Fila Prioritária de Atendimento (SDR / Vendas)
CREATE OR REPLACE VIEW vw_ranking_leads_icp AS
SELECT 
    l.id AS lead_id,
    DENSE_RANK() OVER (ORDER BY l.score_qualificacao DESC, l.data_captura ASC) AS posicao_ranking,
    l.score_qualificacao AS score_icp,
    l.classificacao_lead,
    CASE 
        WHEN l.classificacao_lead = 'Tier A' THEN '🔥 ALTA PRIORIDADE (Tier A - Hot ICP)'
        WHEN l.classificacao_lead = 'Tier B' THEN '⚡ MÉDIA PRIORIDADE (Tier B - Qualificado)'
        WHEN l.classificacao_lead = 'Tier C' THEN '🌱 BAIXA PRIORIDADE (Tier C - Cadência)'
        ELSE '🚫 DESQUALIFICADO'
    END AS prioridade_atendimento,
    l.status_funil,
    l.origem_captura,
    l.documento_pj,
    l.contato_identificado AS telefone_whatsapp,
    l.perfil_ou_link,
    COALESCE(l.atendente_designado, 'Fila Geral / Não Atribuído') AS atendente_designado,
    l.chatwoot_conversation_id,
    l.data_captura,
    ROUND(EXTRACT(EPOCH FROM (NOW() - l.data_captura)) / 3600.0, 1) AS horas_em_fila,
    CASE 
        WHEN l.status_funil IN ('Convertido', 'Desqualificado') THEN 'Finalizado'
        WHEN EXTRACT(EPOCH FROM (NOW() - l.data_captura)) / 3600.0 > 24.0 THEN '⚠️ SLA Estourado (>24h)'
        WHEN EXTRACT(EPOCH FROM (NOW() - l.data_captura)) / 3600.0 > 4.0 THEN '🟡 Em Alerta (4h-24h)'
        ELSE '🟢 No Prazo (<4h)'
    END AS status_sla_atendimento
FROM public.leads l
WHERE l.status_funil != 'Desqualificado'
ORDER BY l.score_qualificacao DESC, l.data_captura ASC;

-- T) Triagem de Volume, Capacidade e Gargalos da Esteira de Leads
CREATE OR REPLACE VIEW vw_triagem_volume_leads AS
WITH volume_diario AS (
    SELECT 
        DATE_TRUNC('day', l.data_captura) AS data_referencia,
        l.origem_captura,
        COUNT(l.id) AS total_capturados,
        COUNT(CASE WHEN l.classificacao_lead = 'Tier A' THEN l.id END) AS leads_tier_a,
        COUNT(CASE WHEN l.classificacao_lead = 'Tier B' THEN l.id END) AS leads_tier_b,
        COUNT(CASE WHEN l.classificacao_lead = 'Tier C' THEN l.id END) AS leads_tier_c,
        COUNT(CASE WHEN l.status_funil = 'Desqualificado' THEN l.id END) AS leads_desqualificados,
        COUNT(CASE WHEN l.status_funil = 'Convertido' THEN l.id END) AS leads_convertidos,
        COUNT(CASE WHEN l.atendente_designado IS NOT NULL THEN l.id END) AS leads_distribuidos,
        COUNT(CASE WHEN l.atendente_designado IS NULL AND l.status_funil NOT IN ('Convertido', 'Desqualificado') THEN l.id END) AS leads_aguardando_triagem,
        ROUND(AVG(l.score_qualificacao), 1) AS score_medio_qualidade
    FROM public.leads l
    GROUP BY DATE_TRUNC('day', l.data_captura), l.origem_captura
)
SELECT 
    TO_CHAR(v.data_referencia, 'YYYY-MM-DD') AS data_dia,
    v.data_referencia,
    v.origem_captura,
    v.total_capturados,
    v.leads_tier_a,
    v.leads_tier_b,
    v.leads_tier_c,
    v.leads_desqualificados,
    v.leads_convertidos,
    v.leads_distribuidos,
    v.leads_aguardando_triagem,
    v.score_medio_qualidade,
    ROUND((v.leads_tier_a::numeric / NULLIF(v.total_capturados, 0)) * 100.0, 2) AS perc_tier_a_qualificado,
    ROUND((v.leads_desqualificados::numeric / NULLIF(v.total_capturados, 0)) * 100.0, 2) AS taxa_descarte_perc
FROM volume_diario v
ORDER BY v.data_referencia DESC, v.total_capturados DESC;

-- U) Análise de Descarte de Leads, Motivos de Rejeição & Ads Desperdiçado
CREATE OR REPLACE VIEW vw_analise_descarte_leads AS
WITH descarte_canal AS (
    SELECT 
        l.origem_captura,
        COALESCE(NULLIF(l.motivo_descarte, ''), 'Não Especificado / Outro') AS motivo_descarte,
        COUNT(l.id) AS total_descartados,
        MIN(l.data_captura) AS primeiro_descarte,
        MAX(l.data_captura) AS ultimo_descarte
    FROM public.leads l
    WHERE l.status_funil = 'Desqualificado' OR l.motivo_descarte IS NOT NULL
    GROUP BY l.origem_captura, COALESCE(NULLIF(l.motivo_descarte, ''), 'Não Especificado / Outro')
),
totais_origem AS (
    SELECT 
        l.origem_captura,
        COUNT(l.id) AS total_leads_gerados
    FROM public.leads l
    GROUP BY l.origem_captura
),
despesas_origem AS (
    SELECT 
        dm.canal AS origem_captura,
        SUM(dm.valor) AS total_investido_marketing
    FROM public.despesas_marketing dm
    GROUP BY dm.canal
)
SELECT 
    d.origem_captura,
    d.motivo_descarte,
    d.total_descartados,
    t.total_leads_gerados,
    ROUND((d.total_descartados::numeric / NULLIF(t.total_leads_gerados, 0)) * 100.0, 2) AS taxa_rejeicao_motivo_perc,
    COALESCE(m.total_investido_marketing, 0.00) AS total_investido_canal,
    -- Estimativa de Dinheiro de Tráfego Desperdiçado com Leads Lixo neste motivo
    ROUND(
        CASE 
            WHEN t.total_leads_gerados > 0 AND COALESCE(m.total_investido_marketing, 0.00) > 0 THEN 
                (m.total_investido_marketing / t.total_leads_gerados) * d.total_descartados
            ELSE 0.00 
        END, 2
    ) AS verba_marketing_desperdicada_estimada,
    d.primeiro_descarte,
    d.ultimo_descarte
FROM descarte_canal d
JOIN totais_origem t ON t.origem_captura = d.origem_captura
LEFT JOIN despesas_origem m ON LOWER(TRIM(m.origem_captura)) = LOWER(TRIM(d.origem_captura))
ORDER BY d.total_descartados DESC;

-- ===============================================================================
-- 12. VIEWS EXECUTIVAS DE TRÁFEGO PAGO & AUDITORIA DE ADS (REPORTEI KILLER)
-- ===============================================================================

-- V) Performance Consolidada de Anúncios e Gerenciadores (Meta, Google, TikTok, ChatGPT, etc.)
CREATE OR REPLACE VIEW vw_performance_ads_gerenciadores AS
SELECT 
    m.plataforma,
    m.conta_id,
    m.campanha_id_externo,
    m.campanha_nome,
    m.data_referencia,
    DATE_TRUNC('month', m.data_referencia::TIMESTAMP) AS mes_referencia,
    
    -- Volumetria
    SUM(m.impressoes) AS total_impressoes,
    SUM(m.alcance) AS total_alcance,
    SUM(m.cliques) AS total_cliques,
    
    -- Financeiro Investido
    SUM(m.valor_investido) AS total_investido,
    
    -- Métricas de Custo Médio Ponderado
    ROUND(
        CASE 
            WHEN SUM(m.impressoes) > 0 THEN 
                (SUM(m.cliques)::numeric / SUM(m.impressoes)) * 100.0 
            ELSE 0.00 
        END, 2
    ) AS ctr_ponderado_perc,
    
    ROUND(
        CASE 
            WHEN SUM(m.cliques) > 0 THEN 
                SUM(m.valor_investido) / SUM(m.cliques) 
            ELSE 0.00 
        END, 2
    ) AS cpc_medio,
    
    ROUND(
        CASE 
            WHEN SUM(m.impressoes) > 0 THEN 
                (SUM(m.valor_investido) / SUM(m.impressoes)) * 1000.0 
            ELSE 0.00 
        END, 2
    ) AS cpm_medio,
    
    -- Conversões do Pixel da Plataforma
    SUM(m.conversoes_pixel) AS total_conversoes_pixel,
    SUM(m.compras_pixel) AS total_compras_pixel,
    SUM(m.receita_pixel) AS receita_reportada_pixel,
    
    -- ROAS do Pixel
    ROUND(
        CASE 
            WHEN SUM(m.valor_investido) > 0 THEN 
                SUM(m.receita_pixel) / SUM(m.valor_investido) 
            ELSE 0.00 
        END, 2
    ) AS roas_pixel_reportado,
    
    -- CPA do Pixel
    ROUND(
        CASE 
            WHEN SUM(m.compras_pixel) > 0 THEN 
                SUM(m.valor_investido) / SUM(m.compras_pixel) 
            ELSE 0.00 
        END, 2
    ) AS cpa_pixel_medio

FROM public.metricas_ads_diarias m
GROUP BY m.plataforma, m.conta_id, m.campanha_id_externo, m.campanha_nome, m.data_referencia;

-- W) Auditoria de ROI: Ads Reportado pela Plataforma vs Vendas Reais Pagas no Banco
-- Goleada SRE: Revela a discrepância entre a "receita do Pixel" e o dinheiro real no caixa
CREATE OR REPLACE VIEW vw_correlacao_ads_vendas_reais AS
WITH ads_agrupado AS (
    SELECT 
        m.data_referencia,
        COALESCE(NULLIF(m.utm_campaign, ''), m.campanha_nome) AS campanha_chave,
        m.plataforma,
        SUM(m.valor_investido) AS investimento_ads,
        SUM(m.cliques) AS cliques_ads,
        SUM(m.receita_pixel) AS receita_pixel,
        SUM(m.compras_pixel) AS compras_pixel
    FROM public.metricas_ads_diarias m
    GROUP BY m.data_referencia, COALESCE(NULLIF(m.utm_campaign, ''), m.campanha_nome), m.plataforma
),
vendas_agrupadas AS (
    SELECT 
        p.data_criacao::DATE AS data_referencia,
        COALESCE(NULLIF(p.utm_campaign, ''), '(geral/organico)') AS campanha_chave,
        COUNT(p.id) AS vendas_reais_pagas,
        SUM(p.valor_total) AS faturamento_real_bruto,
        SUM(p.custo_produtos_cmv) AS cmv_real,
        SUM(p.taxa_gateway) AS taxas_gateway_reais,
        SUM(p.despesa_frete_real) AS frete_real
    FROM public.pedidos p
    WHERE LOWER(p.status_operacional) NOT IN ('cancelado', 'devolvido', 'estornado')
    GROUP BY p.data_criacao::DATE, COALESCE(NULLIF(p.utm_campaign, ''), '(geral/organico)')
)
SELECT 
    COALESCE(a.data_referencia, v.data_referencia) AS data_referencia,
    COALESCE(a.campanha_chave, v.campanha_chave) AS campanha_ou_utm,
    COALESCE(a.plataforma, 'Venda Direta/Orgânica') AS plataforma_ads,
    
    -- Comparativo de Volume
    COALESCE(a.cliques_ads, 0) AS cliques_anuncios,
    COALESCE(a.compras_pixel, 0) AS compras_reportadas_pixel,
    COALESCE(v.vendas_reais_pagas, 0) AS vendas_reais_banco,
    
    -- Comparativo Financeiro
    COALESCE(a.investimento_ads, 0.00) AS valor_investido_ads,
    COALESCE(a.receita_pixel, 0.00) AS faturamento_pixel,
    COALESCE(v.faturamento_real_bruto, 0.00) AS faturamento_real_banco,
    
    -- Lucro Líquido Real Auditado no Caixa
    (COALESCE(v.faturamento_real_bruto, 0.00) - (
        COALESCE(v.cmv_real, 0.00) + 
        COALESCE(v.taxas_gateway_reais, 0.00) + 
        COALESCE(v.frete_real, 0.00) + 
        COALESCE(a.investimento_ads, 0.00)
    )) AS lucro_liquido_real_auditado,
    
    -- ROAS Fantasia (Pixel) vs ROAS Real (Banco)
    ROUND(
        CASE 
            WHEN COALESCE(a.investimento_ads, 0.00) > 0 THEN 
                COALESCE(a.receita_pixel, 0.00) / a.investimento_ads 
            ELSE 0.00 
        END, 2
    ) AS roas_pixel_estimado,
    
    ROUND(
        CASE 
            WHEN COALESCE(a.investimento_ads, 0.00) > 0 THEN 
                COALESCE(v.faturamento_real_bruto, 0.00) / a.investimento_ads 
            ELSE 0.00 
        END, 2
    ) AS roas_real_faturado,
    
    -- Discrepância de Atribuição (Over-attribution do Pixel %)
    ROUND(
        CASE 
            WHEN COALESCE(v.faturamento_real_bruto, 0.00) > 0 THEN 
                ((COALESCE(a.receita_pixel, 0.00) - v.faturamento_real_bruto) / v.faturamento_real_bruto) * 100.0
            ELSE 0.00 
        END, 2
    ) AS discrepancia_pixel_vs_real_perc

FROM ads_agrupado a
FULL OUTER JOIN vendas_agrupadas v ON a.data_referencia = v.data_referencia AND a.campanha_chave = v.campanha_chave
ORDER BY data_referencia DESC;