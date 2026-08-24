-- 1. Garante a criação dos schemas de sistema para isolamento total dos microsserviços
CREATE SCHEMA IF NOT EXISTS n8n_schema;
CREATE SCHEMA IF NOT EXISTS nocodb_schema;

-- 2. Define o escopo padrão do restante deste script para o schema public (sua solução)
SET search_path TO public;

-- 3. Ativação da Extensão de Vetores para o RAG da Inteligência Artificial
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
    data_cadastro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Criação da Tabela de Pedidos (Sincronização com Loja Integrada e Marketplaces)
CREATE TABLE IF NOT EXISTS pedidos (
    id BIGINT PRIMARY KEY,
    -- SRE Correção: Elevação do tipo para BIGINT para suportar sequenciais numéricos massivos 
    -- de rastreabilidade de e-commerce e marketplaces sem estourar as constraints do motor.
    numero_pedido BIGINT NOT NULL, 
    cliente_id BIGINT REFERENCES clientes(id),
    valor_total NUMERIC(10,2) NOT NULL,
    status_operacional VARCHAR(100) NOT NULL, 
    envio_id VARCHAR(100),
    codigo_rastreio VARCHAR(100),
    chave_fiscal VARCHAR(44), 
    data_criacao TIMESTAMP NOT NULL
);

-- 4. Criação da Tabela de Controle Preditivo de Insumos de Embalagem/Expedição
CREATE TABLE IF NOT EXISTS insumos (
    id SERIAL PRIMARY KEY,
    item_nome VARCHAR(255) UNIQUE NOT NULL, -- Caixas, Fitas, Etiquetas
    quantidade_atual INTEGER NOT NULL DEFAULT 0,
    estoque_minimo INTEGER NOT NULL DEFAULT 10,
    fornecedor_nome VARCHAR(255),
    fornecedor_contato VARCHAR(100),
    ultima_atualizacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. Criação da Tabela de Funil de Leads e Prospecção Ativa (PJ e Concorrentes)
CREATE TABLE IF NOT EXISTS leads (
    id SERIAL PRIMARY KEY,
    origem_captura VARCHAR(100) NOT NULL, -- Google Maps, Instagram, Concorrente
    perfil_ou_link TEXT,
    documento_pj VARCHAR(14),
    contato_identificado VARCHAR(255),
    status_funil VARCHAR(50) DEFAULT 'Frio', -- Frio, Morno, Quente, Convertido
    payload_raw JSONB, -- Payload bruto capturado para auditoria
    -- 🚀 SRE OMNICHANNEL: Contexto de Atendimento
    chatwoot_conversation_id BIGINT UNIQUE, -- ID da conversa aberta no Inbox do Chatwoot
    data_captura TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. Criação da Tabela de Catálogo Local (Cache Espelho da Loja Integrada)
CREATE TABLE IF NOT EXISTS catalogo (
    id_interno BIGINT PRIMARY KEY, -- ID numérico interno exigido pela API
    sku VARCHAR(100) UNIQUE NOT NULL, -- SKU alfanumérico bipado ou digitado
    nome VARCHAR(255) NOT NULL,
    preco_cheio NUMERIC(10,2),
    quantidade_estoque INTEGER NOT NULL DEFAULT 0,
    data_sincronizacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7. Tabela de Controle de Mensageria e Prospecção B2B (Fila Transacional Outbox)
CREATE TABLE IF NOT EXISTS fila_mensageria (
    id SERIAL PRIMARY KEY,
    documento_pj VARCHAR(14) NOT NULL,
    whatsapp VARCHAR(20) NOT NULL,
    status VARCHAR(50) DEFAULT 'pendente',
    tentativas INTEGER DEFAULT 0,
    data_agendamento TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Racional de Micro-Tuning PostgreSQL: Força parâmetros agressivos de autovacuum 
-- nas tabelas de alta rotação transacional (filas outbox, staging area e pedidos),
-- forçando o motor a limpar o espaço morto imediatamente após leituras/updates 
-- e impedindo o esgotamento prematuro de IOPS do Mini PC por fragmentação.
ALTER TABLE fila_mensageria SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_vacuum_threshold = 20);
ALTER TABLE catalogo SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_vacuum_threshold = 20);

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

-- 8. Índices de Otimização Relacional e Busca de Strings
CREATE INDEX IF NOT EXISTS idx_catalogo_sku ON catalogo(sku);
CREATE INDEX IF NOT EXISTS idx_leads_documento ON leads(documento_pj);
CREATE INDEX IF NOT EXISTS idx_pedidos_cliente ON pedidos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_fila_status ON fila_mensageria(status);

-- GOLPE DE MESTRE SRE: Índice HNSW para buscas semânticas ultra-rápidas (RAG)
-- Utiliza 'vector_cosine_ops' para otimizar pesquisas baseadas no operador de distância '<=>'
CREATE INDEX IF NOT EXISTS idx_base_conhecimento_embedding 
ON base_conhecimento USING hnsw (embedding vector_cosine_ops);

-- 9. DML de Carga Inicial (Seed de Insumos Estratégicos para Teste de Alerta - White Label)
INSERT INTO insumos (item_nome, quantidade_atual, estoque_minimo, fornecedor_nome, fornecedor_contato)
VALUES 
('Caixa de Embalagem Padrão Tamanho P', 5, 25, 'Fornecedor Central Embalagens', '21988887777'),
('Fita Adesiva Acrílica Larga 50mm', 2, 10, 'Distribuidora de Fitas e Lacres', '21977776666'),
('Etiqueta Térmica de Expedição 100x150mm', 150, 500, 'Suprimentos de Automacao Ltda', '21966665555')
ON CONFLICT (item_nome) DO NOTHING;

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
END $$;

-- Criação dos Schemas FDW para isolamento
CREATE SCHEMA IF NOT EXISTS fdw_chatwoot;
CREATE SCHEMA IF NOT EXISTS fdw_shlink;
CREATE SCHEMA IF NOT EXISTS fdw_listmonk;
CREATE SCHEMA IF NOT EXISTS fdw_umami;

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

-- E) Cruzamento Completo do Funil de Conversão (OmniChannel)
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