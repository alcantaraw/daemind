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
- [📦 Matriz de Versões da Stack & Imagens Docker (SRE BOM)](#-matriz-de-versões-da-stack--imagens-docker-sre-bom)
- [🛡️ Engenharia de Resiliência & SRE (Destaques da Arquitetura)](#️-engenharia-de-resiliência--sre-destaques-da-arquitetura)
- [📌 Roadmap de Engenharia & Futuras Evoluções (TODO)](#-roadmap-de-engenharia--futuras-evoluções-todo)
- [⚖️ Aviso Legal & Isenção de Responsabilidade](#️-aviso-legal--isenção-de-responsabilidade-third-party-disclaimer)
- [📜 Conformidade Jurídica & Matriz de Licenciamento](#-conformidade-jurídica--matriz-de-licenciamento)
- [👨‍💻 Autor & Engenharia de Arquitetura](#-autor--engenharia-de-arquitetura)
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
| **Agendamento de Redes Sociais** | Hootsuite, Buffer, mLabs | R$ 200 – R$ 600/mês | **Incluso** *(Postiz Planner)* |
| **Gateway de IA & Chatbot Interno** | ChatGPT Team, Claude Pro, Poe | R$ 300 – R$ 1.200/mês | **Incluso** *(LiteLLM + Open WebUI)* |
| **Armazenamento de Arquivos e Mídia** | AWS S3, Google Drive, Dropbox | R$ 150 – R$ 500/mês | **Incluso** *(MinIO S3 Soberano, Disco Local ou S3 Cloud)* |
| **CUSTO TOTAL APROXIMADO** | — | **R$ 2.150 – R$ 7.600/mês** | **Apenas o custo do servidor (VPS)** |

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

### 🧠 4. Inteligência Artificial Corporativa & RAG Soberano
- **Roteamento Inteligente**: Roteie consultas entre os modelos mais avançados do mercado (Google Gemini, OpenAI ChatGPT, Anthropic Claude, DeepSeek) pelo menor custo disponível.
- **Cérebro da Empresa (RAG)**: Treine IAs com manuais de produtos, FAQs de atendimento e políticas da empresa para responder dúvidas de clientes e equipe com precisão cirúrgica.

### 🔒 5. Blindagem de Dados, Segurança Bancária e Autocura
- **Soberania Absoluta**: Seus leads, contatos e faturamento nunca saem do seu servidor privado.
- **Backup Diário Criptografado**: Cópia de segurança automática dos dados e bancos com criptografia militar.
- **Disponibilidade 24/7**: Sistema projetado com tecnologia de tolerância a falhas e autocura imediata caso haja oscilações de conexão.

---

## 🛠️ Como funciona a implementação?

> [!TIP]
> 📖 **Documentação Detalhada & Integrações:**
> - Para o passo a passo completo da coleta de variáveis no Wizard, rede e credenciais, consulte o [Manual de Implantação (docs/MANUAL_DE_IMPLANTACAO.md)](docs/MANUAL_DE_IMPLANTACAO.md).
> - Para as especificações técnicas de integração de e-commerce, consulte o [Manual Técnico da Loja Integrada (docs/MANUAL_TECNICO_INTEGRACAO_LOJA_INTEGRADA.md)](docs/MANUAL_TECNICO_INTEGRACAO_LOJA_INTEGRADA.md).

A infraestrutura é provisionada de forma **Low-Touch (Assistida)**. O script de preparação instala os pacotes básicos, ajusta o kernel, clona o repositório em `/opt/daemind` e guia o operador por um **Wizard CLI de 2 minutos no terminal** para coletar a identidade da empresa, senha mestra segura e chaves de IA.

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

O **daemind.** integra os melhores microsserviços de código aberto em uma única malha de alta performance:

- 🗣️ **Chatwoot & Evolution API**: Inbox Omnichannel de atendimento e API de conexão direta com WhatsApp.
- ⚡ **n8n & Temporal Engine**: Motor ilimitado de automações de vendas, webhooks e orquestração de rotinas.
- 📊 **NocoDB**: CRM e banco de dados relacional visual estilo planilha.
- 🚀 **Postiz Planner**: Agendamento automatizado de postagens para redes sociais.
- 🤖 **LiteLLM & Open WebUI**: Gateway soberano de Inteligência Artificial e interface gráfica para chatbots RAG.
- 🗄️ **MinIO S3 / Storage Flexível**: Gestão de mídias e arquivos (Soberano, Disco Local ou Cloud S3).
- 🛡️ **Caddy WAF, Postgres & Redis**: Firewall de borda, banco vetorial/relacional e cache em memória.

> [!NOTE]
> 📊 **Matriz de Versões Auditadas (SRE BOM):** Para a lista exaustiva de contêineres, tags e versões internas auditadas em tempo de execução, consulte o [Manual de Arquitetura & Engenharia SRE (docs/ARQUITETURA_E_ENGENHARIA_SRE.md)](docs/ARQUITETURA_E_ENGENHARIA_SRE.md#49-matriz-dinâmica-de-versões-e-imagens-docker-sre-bom).

---

## 🛡️ Engenharia de Resiliência & SRE (Destaques da Arquitetura)

> [!IMPORTANT]
> ⚙️ **Whitepaper Técnico Completo:** Para a especificação exaustiva de tunings de kernel, parâmetros por container e SecOps, consulte o [Manual de Arquitetura & Engenharia SRE (docs/ARQUITETURA_E_ENGENHARIA_SRE.md)](docs/ARQUITETURA_E_ENGENHARIA_SRE.md).

O **daemind.** não é apenas um conjunto de contêineres, mas uma infraestrutura de nível industrial projetada sob rígidos padrões de **DevOps & Site Reliability Engineering (SRE)**:

- 🔒 **Hardening Perimetral & Segurança Zero-Trust:** Regras estritas no Firewall IPTables, isolamento de rede privada e proteção contra acessos externos não autorizados.
- ⚡ **Auto-Tuning Dinâmico de Hardware:** Inspeção autônoma do servidor (CPU, RAM e Disco) com otimização profunda de memória, CPU e I/O de disco aplicada individualmente a cada microsserviço para garantir máxima performance sem estouros.
- 🐘 **Banco de Dados Escalável:** PostgreSQL 16 com extensão `pgvector` multiplexado via PgBouncer para buscas por IA e webhooks ilimitados.
- 🧼 **Sanitização de Segredos:** Expurgo automático de chaves e credenciais da memória após o boot para zero vazamento.

---

## 📌 Roadmap de Engenharia & Futuras Evoluções (TODO)

Visando a expansão contínua da capacidade computacional, governança de dados e soberania da infraestrutura, os seguintes módulos estão mapeados para integração nas próximas releases:

- 🧠 **IA Local Soberana & Parsing Avançado de Documentos (Open WebUI + Ollama + Docling)**
  - Implementação de detecção dinâmica de capacidade de hardware no `preinstall.sh` (inspeção de RAM, CPU Cores, VRAM e presença do *NVIDIA Container Toolkit*).
  - Alocação inteligente e automatizada dos serviços de inferência local (Ollama) e extração de documentos (Docling) em CPU ou GPU, garantindo alta performance em servidores com placas dedicadas e estabilidade sem travamentos em VPSs modestas.

- 📊 **Business Intelligence, Protocolo MCP & Ingestão Dinâmica OpenAPI (Metabase + Servidores MCP + n8n)**
  - Conexão nativa das bases de dados relacionais ao **Metabase** para visualização e dashboards analíticos.
  - Estabelecimento de servidores do protocolo **MCP (Model Context Protocol)** para que os agentes de IA operem de forma estruturada sobre a infraestrutura.
  - Implementação do pipeline de conversão **OpenAPI ➔ MCP**, com captura e ingestão automática de especificações técnicas de ferramentas e serviços diretamente nos workflows do **n8n**.

- 🔐 **Gestão Profissional de Credenciais (Cofre Infisical)**
  - Transição do modelo de variáveis de ambiente baseadas em arquivo de disco (`.env`) para a custódia centralizada e criptografada no cofre do **Infisical**.
  - Reestruturação do mecanismo de inicialização do Docker Compose com tratamento rigoroso do *"Secret Zero"* (`INFISICAL_TOKEN`), garantindo rotação segura de credenciais e injeção em tempo de execução.

- 🔌 **Framework Universal de Conectores & Resiliência de APIs (E-commerce Integrations)**
  - Expansão da malha de conectores nativos no **n8n** para e-commerces (Shopify, WooCommerce, Mercado Livre, Bling, Tiny) utilizando especificações OpenAPI padronizadas.
  - Implementação de algoritmo de **Rate Limit Throttling (Token Bucket / Circuit Breaker)** nas esteiras de automação para evitar estouros de cotas (HTTP 429) e bloqueios de IP/chaves nas plataformas parceiras.
  - Padrão unificado de **Deduplicação de Webhooks por Hash SHA-256** no Redis/Postgres com TTL configurável, prevenindo duplo processamento em retentativas assíncronas.

- 📑 **Mapeamento & Padronização de Especificações OpenAPI (Stack Interna & E-commerces)**
  - Varredura e extração sistemática do padrão **OpenAPI 3.0/3.1** para todos os microsserviços da pilha interna (Chatwoot, Evolution API, Postiz, MinIO, LiteLLM, NocoDB) e plataformas de e-commerce parceiras (Shopify, WooCommerce, Mercado Livre, Bling, Tiny, Nuvemshop).
  - Ingestão contínua dos schemas OpenAPI no **n8n** e no roteador **LiteLLM / MCP**, permitindo a geração autônoma de nós de automação e capacitando os agentes de IA a realizarem chamadas REST dinâmicas de forma padronizada.

- 🧩 **Arquitetura de Núcleo Único & Módulos Desacoplados (Core vs Plugins Selecionáveis)**
  - Reestruturação da esteira de deploy em uma arquitetura de **Core Único Minimalista e Agnosticista** (banco de dados, rede privada, orquestrador e proxy).
  - Todas as ferramentas superiores (CRM, Chatbot/WhatsApp, Mídias Sociais, RAG/IA, BI) se tornam **módulos plugáveis e 100% desacoplados**, permitindo que o usuário escolha dinamicamente no Wizard CLI quais serviços deseja provisionar, economizando recursos de hardware e ajustando a stack à necessidade exata de cada negócio.

- 🎯 **Foco Primário de Mercado & Versatilidade Multi-Setorial**
  - **Foco Atual:** O **daemind.** nasce com foco especialista em **Vendedores de Marketplaces, Lojas Virtual/E-commerce e Profissionais de Vendas & Marketing Digital**, resolvendo a dor de conversão de carrinhos abandonados, recuperação de Boletos/PIX, atendimento multi-canal e inteligência de catálogo.
  - **Expansão Futura (Versatilidade Vertical):** Graças à arquitetura desacoplada e agnosticista, o **daemind.** será facilmente expansível para novos nichos profissionais através de *módulos de domínio*, tais como:
    - 🩺 **Saúde & Clínicas (Médicos e Dentistas):** Agendamentos inteligentes via WhatsApp, confirmação de consultas, prontuário seguro e retenção de pacientes.
    - 👥 **Recursos Humanos & Departamento Pessoal:** Triagem automática de currículos por IA, onboarding de colaboradores e gestão de chamados internos.
    - ⚖️ **Jurídico & Consultorias:** Acompanhamento de prazos, triagem de casos, RAG para consulta de contratos e atendimento automatizado a clientes.

---

## ⚖️ Aviso Legal & Isenção de Responsabilidade (Third-Party Disclaimer)

O **daemind.** é uma solução de orquestração de infraestrutura, automação e integração que se conecta a múltiplos softwares de código aberto (*Open Source*) e plataformas/APIs de terceiros, incluindo:

- 📦 **Pilha de Software Interna:** NocoDB, n8n, Evolution API, Chatwoot, Postiz, MinIO, LiteLLM, Open WebUI, PostgreSQL, PgBouncer, Redis, Caddy, Tailscale, Ollama, Docling, Metabase, Infisical, entre outros.
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

