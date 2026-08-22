<div align="center">

  <h1>
    <img src="core/html/favicon-daemind.png" alt="daemind logo" width="48" height="48" style="vertical-align: middle; margin-right: 10px;" />
    <font size="20"><strong>daemind.</strong></font>
  </h1>

  <p align="center">
    <strong>Sistema Operacional Autônomo para Negócios Digitais</strong>
  </p>

  <p align="center">
    <img src="https://img.shields.io/badge/Status-Production--Ready-brightgreen?style=for-the-badge" alt="Status">
    <img src="https://img.shields.io/badge/Architecture-Self--Hosted-blue?style=for-the-badge" alt="Self-Hosted">
    <img src="https://img.shields.io/badge/Deployment-Low--Touch-orange?style=for-the-badge" alt="Low-Touch">
    <img src="https://img.shields.io/badge/Infrastructure-Soberana-purple?style=for-the-badge" alt="Soberana">
  </p>

</div>

> [!IMPORTANT]
> **A alternativa soberana, self-hosted e de custo marginal zero para substituir dezenas de assinaturas SaaS.**

O **daemind.** é uma infraestrutura empresarial pronta para uso que centraliza atendimento via WhatsApp, automação de processos, CRM, gestão de mídias sociais e Inteligência Artificial corporativa em um único servidor privado.

---

## 📌 Sumário

- [💡 Como tudo começou (A Origem)](#-como-tudo-começou-a-origem)
- [💰 Por que o daemind.? (SaaS-Killer)](#-por-que-o-daemind-saas-killer)
- [⚙️ O que você ganha no seu negócio](#️-o-que-você-ganha-no-seu-negócio)
  - [💬 1. Atendimento Unificado \& WhatsApp sem Bloqueios](#-1-atendimento-unificado--whatsapp-sem-bloqueios)
  - [⚡ 2. Automação de Vendas sem Limites de Execução](#-2-automação-de-vendas-sem-limites-de-execução)
  - [📊 3. CRM, Gestão de Estoque e Insumos em Tempo Real](#-3-crm-gestão-de-estoque-e-insumos-em-tempo-real)
  - [🧠 4. Inteligência Artificial Corporativa \& RAG Soberano](#-4-inteligência-artificial-corporativa--rag-soberano)
  - [🔒 5. Blindagem de Dados, Segurança Bancária e Autocura](#-5-blindagem-de-dados-segurança-bancária-e-autocura)
- [🛠️ Como funciona a implementação?](#️-como-funciona-a-implementação)
- [📦 Matriz de Versões da Stack \& Imagens Docker (SRE BOM)](#-matriz-de-versões-da-stack--imagens-docker-sre-bom)
- [🛡️ Engenharia de Resiliência \& SRE (Destaques da Arquitetura)](#️-engenharia-de-resiliência--sre-destaques-da-arquitetura)
- [📌 Roadmap de Engenharia \& Futuras Evoluções (TODO)](#-roadmap-de-engenharia--futuras-evoluções-todo)
- [⚖️ Aviso Legal \& Isenção de Responsabilidade](#️-aviso-legal--isenção-de-responsabilidade-third-party-disclaimer)
- [📜 Conformidade Jurídica \& Matriz de Licenciamento](#-conformidade-jurídica--matriz-de-licenciamento)
- [📋 Changelog](#-changelog)
- [👨‍💻 Autor \& Engenharia de Arquitetura](#-autor--engenharia-de-arquitetura)
- [📄 Licença](#-licença)

---

## 💡 Como tudo começou (A Origem)

A ideia do **daemind.** não nasceu num laboratório corporativo distante, mas de um pedido real: **meu irmão**, um vendedor multiplataforma experiente, pediu ajuda para escalar suas vendas e organizar o marketing digital da sua empresa.

O negócio dele já vendia bem e rodava na prática, mas a operação dependia 100% da garra diária — o famoso método *"no suor e na raça"* (ou, em bom português: no modo *"vamo que vamo!"*). Faltavam processos automatizados, padronização e uma arquitetura clara.

Ao mergulhar nos bastidores das vendas e do marketing, o diagnóstico foi imediato:
- 💸 **Labirinto de SaaS:** Dezenas de ferramentas soltas cobrando em dólar por usuário ou por execução.
- 🗂️ **Dados Pulverizados:** Leads e faturamento espalhados em nuvens de terceiros, com 50 abas abertas no navegador.
- 🤯 **Muita Fricção:** Softwares complexos de TI atrapalhando a equipe cujo foco principal é apenas **vender**.

A pergunta que deu origem ao **daemind.** foi simples:  
> *"Dá para entregar uma infraestrutura empresarial robusta, ultra-integrada, sem exigir hardware de supercomputador e com **fricção zero** para usuários que não são de TI?"*

A resposta é este repositório: os melhores sistemas open-source do mundo, unificados e prontos para rodar no seu próprio servidor privado.

---

## 💰 Por que o daemind.? (SaaS-Killer)

Em vez de pagar centenas de dólares mensais por plataformas isoladas que cobram por usuário, por lead ou por execução de fluxo, você roda toda a operação no seu próprio servidor por uma fração do custo.

| Funcionalidade | Substitui Plataformas Como | Custo Típico SaaS | No **daemind.** |
| :--- | :--- | :--- | :--- |
| **Atendimento Omnichannel & WhatsApp** | Zendesk, ManyChat, Intercom | R$ 600 – R$ 1.500/mês | **Incluso** *(Chatwoot + Evolution API)* |
| **Automação de Processos** | Zapier, Make, ActiveCampaign | R$ 400 – R$ 2.000/mês | **Incluso** *(n8n ilimitado)* |
| **CRM e ERP Transacional** | Airtable, Salesforce, HubSpot | R$ 500 – R$ 1.800/mês | **Incluso** *(NocoDB)* |
| **Agendamento de Redes Sociais** | Hootsuite, Buffer, mLabs | R$ 200 – R$ 600/mês | **Incluso** *(Postiz Planner + Temporal)* |
| **E-mail Marketing & Transacional** | Mailchimp, SendGrid, RD Station | R$ 300 – R$ 1.500/mês | **Incluso** *(Listmonk Mailer)* |
| **Encurtador de Links & UTMs** | Bitly Pro, Dub.co, Rebrandly | R$ 150 – R$ 600/mês | **Incluso** *(Shlink + Web Client)* |
| **Web Analytics sem Cookies (LGPD)** | Google Analytics 4, Plausible | R$ 100 – R$ 400/mês | **Incluso** *(Umami Analytics)* |
| **Business Intelligence & Dashboards**| PowerBI Pro, Tableau, Looker | R$ 300 – R$ 1.200/mês | **Incluso** *(Metabase BI)* |
| **Gateway de IA & Chatbot Interno** | ChatGPT Team, Claude Pro, Poe | R$ 300 – R$ 1.200/mês | **Incluso** *(LiteLLM + Open WebUI)* |
| **Armazenamento de Arquivos e Mídia** | AWS S3, Google Drive, Dropbox | R$ 150 – R$ 500/mês | **Incluso** *(MinIO S3 Soberano, Disco Local ou S3 Cloud)* |
| **CUSTO TOTAL APROXIMADO** | — | **R$ 3.000 – R$ 11.300/mês** | **Apenas o custo do servidor (VPS)** |

---

## ⚙️ O que você ganha no seu negócio

### 💬 1. Atendimento Unificado & WhatsApp sem Bloqueios
- **Inbox Compartilhado**: Atenda clientes via WhatsApp e redes sociais com múltiplos operadores na mesma conta.
- **Disparo e Automação de Vendas**: Envie notificações de pedido, recuperação de carrinho abandonado, PIX e boletos automaticamente sem pagar taxas por mensagem.

### ⚡ 2. Automação de Vendas sem Limites de Execução
- **Integração Completa**: Integre sua loja virtual (Loja Integrada, Shopify, WooCommerce ou Marketplaces) com seu banco de dados, emissor de nota fiscal e inteligência artificial.
- **Execução Ilimitada**: Execute centenas de milhares de automações mensais sem surpresas na fatura no final do mês.

### 📊 3. CRM, Gestão de Estoque e Insumos em Tempo Real
- **Visão 360°**: Visualize pedidos, dados de clientes, funis de prospecção B2B e acompanhamento de embalagens/insumos em painéis simples estilo planilha.
- **Soberania dos Dados**: Mantenha seu histórico de clientes 100% sob seu controle, livre de exportações travadas por SaaS terceirizados.

### ✉️ 4. E-mail Marketing, Campanhas e Atribuição Soberana
- **Disparos em Massa & Transacionais**: Envie newsletters, fluxos de onboarding e e-mails de confirmação de compra sem pagar por volume de contatos via **Listmonk**.
- **Encurtador de Links & Tags UTM**: Crie links curtos personalizados com domínio próprio, QR Codes dinâmicos e rastreamento de cliques em campanhas via **Shlink**.
- **Privacidade & Analytics (LGPD)**: Acompanhe visitas e conversões em tempo real sem banners invasivos de cookies e sem enviar dados dos seus clientes para big techs via **Umami**.

### 🧠 5. Inteligência Artificial Corporativa & RAG Soberano
- **Roteamento Inteligente**: Roteie consultas entre os modelos mais avançados do mercado (Google Gemini, OpenAI ChatGPT, Anthropic Claude, DeepSeek) pelo menor custo disponível.
- **Cérebro da Empresa (RAG)**: Treine IAs com manuais de produtos, FAQs de atendimento e políticas da empresa para responder dúvidas de clientes e equipe com precisão cirúrgica.

### 🔒 6. Blindagem de Dados, Segurança Bancária e Autocura
- **Soberania Absoluta**: Seus leads, contatos e faturamento nunca saem do seu servidor privado.
- **Backup Diário Criptografado**: Cópia de segurança automática dos dados e bancos com criptografia militar.
- **Disponibilidade 24/7**: Sistema projetado com tecnologia de tolerância a falhas e autocura imediata caso haja oscilações de conexão.

---

## 🛠️ Como funciona a implementação?

> [!TIP]
> 📖 **Documentação Detalhada & Integrações:**
> - Para o passo a passo completo da coleta de variáveis no Wizard, rede e credenciais, consulte o [Manual de Implantação (docs/MANUAL_DE_IMPLANTACAO.md)](docs/MANUAL_DE_IMPLANTACAO.md).
> - Para as especificações técnicas de integração de e-commerce, consulte o [Manual Técnico da Loja Integrada (docs/MANUAL_TECNICO_INTEGRACAO_LOJA_INTEGRADA.md)](docs/MANUAL_TECNICO_INTEGRACAO_LOJA_INTEGRADA.md).

A infraestrutura é provisionada de forma **Low-Touch (Assistida)**. O script de preparação instala os pacotes básicos, ajusta o kernel, clona o repositório em `/opt/daemind` e guia o operador por um **Wizard CLI de 2 minutos no terminal** para coletar a identidade da empresa, seleção de módulos opcionais (Evolution API, Postiz, Chatwoot, NocoDB, Listmonk, Umami, Shlink, etc.), senha mestra segura e chaves de IA.

Com o ambiente pronto e o código clonado, o sistema gera os pares de chaves criptográficas e executa a instalação autônoma em segundo plano.

### 🚀 Instalação Rápida (Ubuntu Server)

No seu servidor Ubuntu recém-criado, execute o comando em linha única abaixo como `root` ou com privilégios `sudo`:

```bash
curl -fsSL http://bit.ly/daemind | bash
```

*(Ou via URL completa do repositório: `curl -fsSL https://raw.githubusercontent.com/alcantaraw/daemind/main/preinstall.sh | bash`)*

> [!NOTE]
> **Transparência e Segurança:** Caso queira inspecionar e validar o destino exato do link encurtado antes de executá-lo no seu servidor, você pode checar a URL através do [FindRedirect](https://findredirect.com/pt/expander) ou [CheckShortURL](https://checkshorturl.com/) inserindo a URL `http://bit.ly/daemind`.

Ao final da preparação, o script perguntará se você deseja rodar a instalação do **daemind.** imediatamente. Se optar por rodar manualmente mais tarde:

```bash
cd /opt/daemind
sudo ./core/scripts/install.sh
```

---

## 📦 Componentes & Arquitetura da Stack

O **daemind.** opera sob uma arquitetura de **Núcleo Core Único & Imutável** complementado por **Módulos Opcionais Desacoplados e Plugáveis**:

### 🏛️ Núcleo Core Único & Imutável (Fundação Obrigatória)
Consolidado em um manifesto de alta coesão e performance, o Core garante a base relacional, cache, segurança e inteligência do sistema:
- 🐘 **PostgreSQL 17 + PGVector**: Banco de dados relacional e vetorial de alta performance com multiplexação via **PgBouncer**.
- ⚡ **Redis 8**: Cache em memória ultra-rápido e fila assíncrona de baixa latência.
- 🛡️ **Caddy WAF**: Firewall de borda, proxy reverso e emissor automatizado de certificados SSL/TLS.
- 🤖 **LiteLLM Gateway**: Gateway soberano e roteador multi-LLM (OpenRouter, Gemini, OpenAI, Claude, DeepSeek).

### 🧩 Módulos Plugáveis & Opcionais (Seleção Dinâmica via Wizard)
Cada aplicação opera como um módulo 100% desacoplado (`docker-compose.<modulo>.yml` + `install_<modulo>.sh`), permitindo ativação sob demanda para economia extrema de memória:
- ⚡ **n8n (Automation)**: Motor de automações ilimitadas de vendas, webhooks e workflows.
- 🧠 **Open WebUI (Chat & RAG)**: Interface gráfica corporativa de Inteligência Artificial e MCP.
- 🗣️ **Chatwoot & WPPConnect Server**: Inbox Omnichannel de atendimento multiatendente e Gateway Open Source de WhatsApp.
- 📊 **NocoDB**: CRM e banco de dados relacional estilo planilha inteligente.
- 🚀 **Postiz Planner & Temporal Engine**: Agendador e publicador de mídias sociais.
- ✉️ **Listmonk Mailer**: Disparador de e-mail marketing, newsletters e transacionais soberanos.
- 🔗 **Shlink & Web Client**: Encurtador de links soberano, QR Codes e atribuição de campanhas UTM.
- 📈 **Umami Analytics**: Web analytics moderno, leve e 100% aderente à LGPD/GDPR sem cookies invasivos.
- 🗄️ **MinIO S3 / Storage Flexível**: Gestão de mídias e arquivos (Soberano, Disco Local ou Cloud S3).
- 📈 **Metabase BI**: Painéis analíticos, dashboards e relatórios executivos em tempo real.
- 🦙 **Ollama & Docling**: Motor local de modelos de linguagem soberanos e OCR/parsing avançado de documentos.

> [!NOTE]
> 📊 **Matriz de Versões Auditadas (SRE BOM):** Para a lista exaustiva de contêineres, tags e versões internas auditadas em tempo de execução, consulte o [Manual de Arquitetura & Engenharia SRE (docs/ARQUITETURA_E_ENGENHARIA_SRE.md)](docs/ARQUITETURA_E_ENGENHARIA_SRE.md#410-matriz-dinâmica-de-versões-e-imagens-docker-sre-bom).

---

## 🛡️ Engenharia de Resiliência & SRE (Destaques da Arquitetura)

> [!IMPORTANT]
> ⚙️ **Whitepaper Técnico Completo:** Para a especificação exaustiva de tunings de kernel, parâmetros por container e SecOps, consulte o [Manual de Arquitetura & Engenharia SRE (docs/ARQUITETURA_E_ENGENHARIA_SRE.md)](docs/ARQUITETURA_E_ENGENHARIA_SRE.md).

O **daemind.** não é apenas um conjunto de contêineres, mas uma infraestrutura de nível industrial projetada sob rígidos padrões de **DevOps & Site Reliability Engineering (SRE)**:

- 🔒 **Hardening Perimetral & Segurança Zero-Trust:** Regras estritas no Firewall IPTables, isolamento de rede privada e proteção contra acessos externos não autorizados.
- ⚡ **Auto-Tuning Dinâmico de Hardware:** Inspeção autônoma do servidor (CPU, RAM e Disco) com otimização profunda de memória, CPU e I/O de disco aplicada individualmente a cada microsserviço para garantir máxima performance sem estouros.
- 🐘 **Banco de Dados Escalável:** PostgreSQL 17 com extensão `pgvector` multiplexado via PgBouncer para buscas por IA e webhooks ilimitados.
- 🔑 **Identidade Global Unificada & SSOT de Credenciais:** Uma única conta universal (`$TS_EMAIL` + `$DB_PASSWORD`) autentica 100% dos painéis e integrações da stack com zero fricção de onboarding manual.
- 🧼 **Sanitização de Segredos:** Expurgo automático de chaves e credenciais da memória após o boot para zero vazamento.

---

## 📌 Roadmap de Engenharia & Futuras Evoluções (TODO)

- 🚀 **1. Integrações Transversais de Alto Impacto (Zero-Touch Inter-App Ecosystem)**
  - 📊 **BI & Analytics Unificados (Metabase Auto-Connect):**
    - Auto-provisionamento de conexões no **Metabase** para todas as fontes de dados ativas da stack (`listmonk_db`, `shlink_db`, `umami_db`, `chatwoot_production`) via API/bootstrap, disponibilizando dashboards analíticos pré-construídos de vendas, cliques, tráfego e atendimento com zero configuração manual.
  - 🔗 **Rastreamento de Campanhas em Tempo Real (Shlink + Umami):**
    - Configuração integrada do **Shlink** para padronização automática de tags e parâmetros UTM reconhecidos nativamente pelo **Umami Analytics**, unificando o funil de atribuição de tráfego.
  - ✉️ **Auto-Encurtamento & Rastreamento em Newsletters (Listmonk + Shlink):**
    - Integração de disparos do **Listmonk** consumindo a API do **Shlink** para auto-encurtamento de links de campanhas, analytics de taxa de clique e proteção de entregabilidade.
  - 🗃️ **NocoDB como Painel de Gestão Visual (Listmonk & Shlink):**
    - Vinculação declarativa das bases `listmonk_db` e `shlink_db` no **NocoDB**, permitindo visualização, segmentação e gestão de inscritos e links encurtados em formato de planilha visual (Airtable soberano).
  - 🗄️ **Armazenamento Desacoplado no NocoDB (MinIO S3 Attachments):**
    - Injeção das variáveis de S3 (`NC_S3_BUCKET`, `NC_S3_KEY`, `NC_S3_SECRET`) para que todos os uploads de anexos e mídias de tabelas do NocoDB sejam roteados diretamente ao bucket dedicado `nocodb` do MinIO.

- 🛒 **2. Templates de Automação Prontos para E-commerce & Marketplaces (n8n)**
  - Criação de templates de automação prontos para uso no **n8n** integrando lojas virtuais (**Shopify, WooCommerce, Nuvemshop, Loja Integrada**) e marketplaces (**Mercado Livre, Amazon, Shopee**).
  - Esteiras de **Recuperação de Carrinho Abandonado**, **Cobrança Ativa de Boletos/PIX pendentes** e **Notificações de Rastreamento de Envio** diretamente via WhatsApp (*WPPConnect / Chatwoot*).
  - Algoritmos de **Throttling e Rate Limiting** nas esteiras para proteger as contas e chaves de API contra bloqueios nas plataformas parceiras.

- 🤖 **3. Agentes de IA Especialistas & Protocolo MCP para Negócios**
  - Configuração de **Servidores MCP (Model Context Protocol)** para que os agentes de IA consultem produtos, estoques, status de pedidos e tabelas de frete em tempo real no PostgreSQL e NocoDB.
  - Criação de **Agentes SDR (Pré-vendas) e Suporte N1** treinados com RAG na base de dados da empresa para atender clientes no Chatwoot de forma autônoma e humanizada.

- 📈 **4. Painéis Executivos de BI & Gestão de Lucro Real (Metabase)**
  - Dashboards pré-configurados no **Metabase** cruzando vendas, custos de produtos (CMV), despesas de anúncios/marketing e taxas de gateways de pagamento.
  - Relatórios automatizados diários e semanais enviados direto no WhatsApp ou e-mail dos gestores com métricas-chave de faturamento e estoque crítico.

- 🎯 **5. Expansão Multi-Setorial (Módulos de Domínio Vertical)**
  - O **daemind.** nasce especialista em **Vendas Online & Marketing Digital**, mas sua esteira modular permite rápida expansão para outros setores:
    - 🩺 **Saúde & Clínicas:** Agendamentos inteligentes via WhatsApp, confirmação de consultas, triagem pré-atendimento e retenção de pacientes.
    - 👥 **Recursos Humanos & Departamento Pessoal:** Triagem automática de currículos por IA, onboarding de novos colaboradores e gestão de solicitações internas.
    - ⚖️ **Jurídico & Consultorias:** Acompanhamento de prazos, triagem de casos, RAG para consulta de contratos e atendimento automatizado a clientes.

- ~~❌ **[DESCONTINUADO / ABANDONADO] 🔐 Gestão de Credenciais via Cofre Externo (Infisical)**~~
  - ~~Substituição do `.env` por cofre Infisical descartada em favor do modelo **SSOT com Permissões Estritas (chmod 600)**, âncora `SRE HOME ANCHOR` e sanitização atômica de memória no boot, mantendo a arquitetura simples, independente de terceiros e com zero overhead computacional.~~

- ~~✅ **[CONCLUÍDO] 🧠 IA Local Soberana & Parsing Avançado de Documentos (Open WebUI + Ollama + Docling)**~~
  - ~~(Módulo Opcional de Alto Desempenho - Host com > 4 Cores e > 16GB RAM)~~
  - ~~Implementação de detecção dinâmica de capacidade de hardware desacoplada via `autotune.sh` no `preinstall.sh` (inspeção de RAM e CPU Cores).~~
  - ~~Alocação inteligente e automatizada de sizing pesado dos serviços de inferência local (Ollama) e extração de documentos (Docling), garantindo alta performance em servidores dedicados e estabilidade sem travamentos em VPSs modestas.~~

- ~~✅ **[CONCLUÍDO] 🔌 Desacoplamento da Rede Tailscale (`core/scripts/install_0ts.sh`) e Catálogo de IA (`core/scripts/install_1ia.sh`)**~~
  - ~~Isolamento da lógica de provisionamento, autenticação OAuth, criação de nós satélites, auto-cura/recovery e expurgo da rede VPN perimetral **Tailscale** no módulo padronizado `core/scripts/install_0ts.sh`.~~
  - ~~Desacoplamento do motor de sincronização inteligente de IA (matchmaking dinâmico multiprovedor Big 5) no módulo padronizado `core/scripts/install_1ia.sh`.~~

- ~~✅ **[CONCLUÍDO] 🧩 Arquitetura de Núcleo Core Único Imutável, Auto-Descoberta Total & Inversão de Controle (IoC)**~~
  - ~~Consolidação do **Núcleo Core Imutável** (PostgreSQL 17, PgBouncer, Redis, Caddy WAF e LiteLLM Gateway) em manifesto monolítico de alta coesão e performance.~~
  - ~~Desacoplamento integral de **todos os serviços superiores** (**n8n**, **Open WebUI**, **Chatwoot**, **Evolution API**, **Postiz**, **NocoDB**, **S3MinIO**, **Metabase**, **Ollama** e **Docling**) em manifestos `docker-compose.<modulo>.yml` e scripts de ciclo de vida com contrato universal de 15 funções (`install_<modulo>.sh`).~~
  - ~~Implementação do padrão **Inversion of Control (IoC)** no `preinstall.sh`: auto-descoberta total e dinâmica de perguntas (`collect_wizard_inputs`) e variáveis de ambiente (`build_envs`) com preservação estrita do **Wizard Cache** (`.daemind_wizard_cache.env`), eliminando para sempre edições manuais no `preinstall.sh` ao criar novos módulos.~~
  - ~~Consolidação do guia oficial de desenvolvimento de novas extensões em **[Manual de Engenharia SRE: Desacoplamento Modular & Integração de Novos Módulos (docs/MANUAL_DE_DESACOPLAMENTO_E_NOVOS_MODULOS.md)](docs/MANUAL_DE_DESACOPLAMENTO_E_NOVOS_MODULOS.md)**.~~

---

## ⚖️ Aviso Legal & Isenção de Responsabilidade (Third-Party Disclaimer)

O **daemind.** é uma solução de orquestração de infraestrutura, automação e integração que se conecta a múltiplos softwares de código aberto (*Open Source*) e plataformas/APIs de terceiros, incluindo:

- 📦 **Pilha de Software Interna:** NocoDB, n8n, Evolution API, Chatwoot, Postiz, S3MinIO, LiteLLM, Open WebUI, PostgreSQL, PgBouncer, Redis, Caddy, Tailscale, Ollama, Docling, Metabase, entre outros.
- 🛍️ **Plataformas de E-commerce & Marketplaces Integrados ou a Integrar:** Loja Integrada, Mercado Livre, Amazon, Magalu, Shopee, Shopify, WooCommerce, Nuvemshop, Bling, Tiny ERP, etc.

> [!NOTE]
> - **Propriedade Intelectual & Marcas:** Todos os direitos de marca registrada, logotipos, nomes comerciais, código-fonte e especificações técnicas de APIs pertencem exclusivamente às suas respectivas empresas mantenedoras e proprietárias. A menção a qualquer serviço ou plataforma neste repositório destina-se unicamente a fins de identificação de compatibilidade técnica e integração.
> - **Isenção de Afiliação:** O **daemind.** é um projeto independente e não possui vínculo comercial, endosso ou associação oficial direta com as marcas ou plataformas citadas, salvo quando formalmente indicado.
> - **Suporte & Instabilidades de Terceiros:** O **daemind.** apenas orquestra o deploy, rede, segurança e esteiras de automação de dados. Eventuais falhas, instabilidades, mudanças descontinuadas em APIs REST/GraphQL, limites de cota (*Rate Limits*) ou interrupções de serviço de plataformas parceiras ou softwares Open Source devem ser verificadas e tratadas diretamente junto aos canais e repositórios oficiais dos respectivos fornecedores.
> - **Licenciamento:** O uso de cada componente deve respeitar suas respectivas licenças de software (*MIT, AGPL, Apache 2.0, GPL, etc.*) e Termos de Uso (*ToS*) das APIs de terceiros.

---

## 📜 Conformidade Jurídica & Matriz de Licenciamento

O projeto **daemind.** opera como uma solução Open Source sob licença MIT focada na orquestração e prestação de serviços de infraestrutura dedicada (modelo **1 cliente = 1 stack**). 

Para assegurar **total transparência e compliance legal**, cada software orquestrado permanece sob sua própria licença original, sem redistribuição ou alteração de código-fonte de terceiros.

Para consultar a análise detalhada por componente, restrições da **Sustainable Use License (SUL)** do n8n, regras da **AGPLv3** (MinIO, NocoDB, Postiz) e adequações de versão do **Redis**, acesse o nosso documento oficial de governança:

📄 **[Matriz de Conformidade Jurídica e Licenciamento (docs/THIRD_PARTY_LICENSES.md)](docs/THIRD_PARTY_LICENSES.md)**

## 👨‍💻 Autor & Engenharia de Arquitetura

Concebido e desenvolvido por **Wellington Alcantara** — Especialista em Engenharia de Confiabilidade (SRE), Arquitetura de Sistemas, DevOps & Observabilidade.

Com mais de **25 anos de carreira na TI** (com forte atuação em ecossistemas críticos de Telecom e grandes corporações como Oi, TIM, V.tal e Accenture), combina visão estratégica e atuação *hands-on*:

- 🛠️ **Troubleshooting Avançado & GC/JVM Tuning:** Investigação profunda de causa raiz em nível de código, threads, memory leaks e otimização extrema de performance.
- ⚡ **Observabilidade & Auto-Healing:** Arquitetura de telemetria proativa com ELK Stack (Elasticsearch, Logstash, Kibana), Zabbix e Grafana para antecipação de incidentes.
- 🛡️ **DevSecOps & Automação:** Esteiras robustas de CI/CD, hardening perimetral, gestão de ambientes de alta fidelidade e orquestração de microsserviços.
- 🎓 **Formação:** Pós-Graduado em Computação em Nuvem (Arquiteto de Operações e Segurança) & Graduado em Análise e Desenvolvimento de Sistemas (UniCarioca).

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/alcantaraw/)
[![E-mail](https://img.shields.io/badge/E--mail-EA4335?style=for-the-badge&logo=gmail&logoColor=white)](mailto:alcantaraw@gmail.com)

---

## 📋 Changelog

Todas as mudanças relevantes entre versões estão documentadas em **[CHANGELOG.md](CHANGELOG.md)**.

| Versão | Data | Descrição |
|--------|------|-----------|
| [`v1.0.0`](CHANGELOG.md#v100--2026-08-18--desacoplamento-completo) | 2026-08-18 | Desacoplamento completo — wizard TUI/CLI, módulos independentes, guardrails SRE |
| [`v0.5.0`](CHANGELOG.md#v050--2026-08--main-prova-de-conceito) | 2026-08-06 | Prova de conceito — stack monolítica funcional, instalador CLI simples |

---

## 📄 Licença

Este projeto é um software livre distribuído sob a **[Licença MIT](LICENSE)**.

Você tem total liberdade para utilizar, modificar, adaptar e incorporar este código em seus próprios projetos (pessoais ou comerciais), desde que **mantenha o aviso de copyright e os créditos originais de autoria** ([Wellington Alcantara](https://www.linkedin.com/in/alcantaraw/)).

---

## 🤖 Nota de Transparência & Co-pilotagem por Inteligência Artificial

> [!NOTE]
> **Engenharia Aumentada por IA:**  
> Este repositório e sua arquitetura de automação contaram com a colaboração ativa de **Inteligência Artificial** como *pair programmer* avançado. 
> 
> A IA foi utilizada para busca e síntese acelerada de informações, geração de soluções para lógicas complexas de scripts, transformação de rascunhos técnicos em documentações elegantes, higienização, comentarios e indentação impecável do código, além de um "pequeno" auxílio para agilizar em **1.000.000x** 🚀 a velocidade da entrega! 🤖✨

---

<p align="center">
  <b>daemind.</b> — Sistema Operacional Autônomo para Negócios Digitais<br>
  <sub>Desenvolvido sob rigorosos padrões de Site Reliability Engineering (SRE) & SecOps.</sub>
</p>

