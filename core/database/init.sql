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