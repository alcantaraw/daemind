# 📘 Manual de Implantação e Operação de Infraestrutura — daemind.

Manual técnico e tático de engenharia de resiliência (SRE) para provisionamento, coleta de credenciais, hardening perimetral e disparo da esteira do **daemind.**.

---

## 📌 Sumário

- [1. Requisitos de Hardware e Sistema Operacional](#1-requisitos-de-hardware-e-sistema-operacional)
- [2. Modos de Conectividade Externa (DNS vs Tailscale)](#2-modos-de-conectividade-externa-dns-vs-tailscale)
- [3. Coleta de Chaves e Credenciais (IA & E-commerce)](#3-coleta-de-chaves-e-credenciais-ia--e-commerce)
- [4. Preparação e Sanitização do Host (`preinstall.sh`)](#4-preparação-e-sanitização-do-host-preinstallsh)
- [5. Disparo da Instalação da Stack (`install.sh`)](#5-disparo-da-instalação-da-stack-installsh)
- [6. Arquitetura dos Serviços & Matriz de Portas](#6-arquitetura-dos-serviços--matriz-de-portas)
- [7. Observabilidade e Comandos de Inspeção SRE](#7-observabilidade-e-comandos-de-inspeção-sre)

---

## 1. Requisitos de Hardware e Sistema Operacional

O **daemind.** é projetado para rodar de forma leve e otimizada sobre qualquer ambiente Linux moderno.

### 💻 Especificações Mínimas Recomendadas:
* **Processador:** 4 Cores (vCPUs)
* **Memória RAM:** 8 GB
* **Armazenamento:** 60 GB+ em SSD ou NVMe
* **Sistema Operacional:** Ubuntu Server (22.04 LTS, 24.04 LTS ou 26.04 LTS — *instalação mínima/headless*)

### 🧠 Requisitos para Módulos de IA Local & OCR Pesado (Ollama / Docling):
* **Processador:** > 4 Cores (vCPUs)
* **Memória RAM:** $\ge$ 16 GB
* **GPU Dedicada com VRAM > 4 GB (Desktop ou Notebook/Mobile):**
  * **NVIDIA:** Famílias GeForce RTX (20xx, 30xx, 40xx, 50xx — Desktop e Laptop/Mobile), Quadro RTX, RTX A-Series, Tesla/Ampere/Hopper/Blackwell.
  * **AMD:** Famílias Radeon RX 6000, 7000, 8000 e 9000 Séries (Desktop e Mobile RX 6000M/S, 7000M/S, 8000M, 9000M, Radeon PRO Mobile).
  * **Intel:** Famílias Intel Arc Série A (A350M, A370M, A380, A530M, A550M, A570M, A580, A730M, A750, A770, A770M, Arc Pro) e Série B (Battlemage: B570, B580) tanto Desktop quanto Mobile.

### 🏢 Ambientes Suportados:
- **Cloud VPS / Dedicado:** Hetzner, Contabo, DigitalOcean, Linode, AWS, Oracle Cloud.
- **Virtualizadores (On-Premises):** Proxmox VE, VMware ESXi, Hyper-V, KVM, VirtualBox.
- **Hardware Físico (Bare Metal):** Servidor dedicado em infraestrutura própria.

---

## 2. Modos de Conectividade Externa (DNS vs Tailscale)

O sistema suporta duas topologias de conectividade de rede:

### 🌐 Opção A: Modo BYODNS / IP Fixo (Padrão de Produção)
* **Para quem é:** Servidores com IP Público Estático (Cloud VPS ou IP Fixo de Datacenter/Provedor).
* **Como funciona:** O Gateway de Borda (Caddy WAF) assume as portas `80` e `443` e emite certificados SSL válidos automaticamente via Let's Encrypt para o seu domínio (ex: `app.suaempresa.com.br`).

### 🔒 Opção B: Modo Tailscale Mesh (VPN & CGNAT)
* **Para quem é:** Servidores locais sem IP Público direto, atrás de CGNAT ou redes residenciais/escritórios.
* **Como funciona:** Cria uma malha privada criptografada com certificados SSL automatizados pelo Tailscale Funnel.

---

## 3. Coleta de Chaves e Credenciais (IA & E-commerce)

Antes de rodar a esteira no servidor, prepare um bloco de notas com as credenciais que serão solicitadas:

### 🛍️ 3.1. Integração E-commerce (Loja Integrada)
- *(Desativado momentaneamente no Wizard)*.

### 🧠 3.2. Malha de Inteligência Artificial (Gateway LiteLLM + Open WebUI)
A infraestrutura utiliza o **OpenRouter** de forma obrigatória para consumo de **modelos 100% gratuitos**, garantindo inferência de IA sem custo adicional por token.

| Provedor de IA | Obrigatoriedade | Função na Stack & Modelos Suportados | Onde Gerar a Chave |
| :--- | :--- | :--- | :--- |
| **OpenRouter** | 🔴 **OBRIGATÓRIO** | Servir modelos **100% Gratuitos** sem custo por token | [openrouter.ai/keys](https://openrouter.ai/keys) |
| **Google Gemini** | 🟡 Opcional | Modelos Gemini (*Gemini 3.1 Pro, 3.6 Flash, 3.5 Flash Lite*) | [aistudio.google.com](https://aistudio.google.com) |
| **OpenAI (ChatGPT)** | 🟡 Opcional | Modelos GPT (*GPT-5.6 Sol, GPT-5.6 Terra, GPT-5.6 Luna*) | [platform.openai.com](https://platform.openai.com) |
| **Anthropic (Claude)** | 🟡 Opcional | Modelos Claude (*Claude Fable 5, Opus 5, Sonnet 5, Haiku 4.5*) | [console.anthropic.com](https://console.anthropic.com) |
| **DeepSeek** | 🟡 Opcional | Modelos DeepSeek (*DeepSeek V4 Pro, V4 Flash, R1*) | [platform.deepseek.com](https://platform.deepseek.com) |

> [!IMPORTANT]
> A chave do **OpenRouter** é **obrigatória** para garantir o funcionamento nativo dos assistentes e automações sem custo. As demais chaves são opcionais para quem deseja utilizar modelos proprietários pagos adicionais.

### 🌐 3.3. Tailscale OAuth & Configuração de ACL (Apenas se utilizar a Opção B)

Para utilizar o modo Tailscale, é necessário preparar o painel administrativo do Tailscale com as permissões de **Funnel / Serve** e gerar as credenciais OAuth corretas:

#### 📜 Step 1: Configuração do ACL JSON (Access Control)
No painel do Tailscale, acesse `Access Control > JSON editor` e certifique-se de que a política JSON contém a permissão de `funnel` e `serve` conforme o padrão abaixo:

```json
{
	"tagOwners": {"tag:production": ["autogroup:admin"]},

	"grants": [
		{
			"src": ["*"],
			"dst": ["*"],
			"ip":  ["*"],
		},

	],

	"ssh": [
		{
			"action": "check",
			"src":    ["autogroup:member"],
			"dst":    ["autogroup:self"],
			"users":  ["autogroup:nonroot", "root"],
		},
	],

	"nodeAttrs": [
		{
			"target": ["autogroup:member", "tag:production"],
			"attr":   ["funnel", "serve"],
		},
	],
}
```

#### 🔑 Step 2: Geração da Chave OAuth sem Expiração
1. Acesse a página de credenciais do Tailscale: [console.tailscale.com/admin/settings/trust-credentials](https://console.tailscale.com/admin/settings/trust-credentials) (ou em `Settings > Trust credentials`).
2. Clique em **+ Generate OAuth Client** (ou `+ Credential`).
3. **Validade da Chave:** Altere a expiração para **Não expirar (Never expire)**.
4. **Permissões (Scopes Obrigatórios):**
   - **Devices > Core:** Marcar 🟢 **Write**
   - **Auth Keys:** Marcar 🟢 **Write**
5. Guarde o `Client Secret` (chave de 63 caracteres no formato `tskey-client-...`). O `Client ID` será derivado automaticamente pelo script.

---

## 4. Preparação do Host e Wizard de Instalação (`preinstall.sh`)

O provisionamento do **daemind.** é **Low-Touch / Assistido**: em vez de exigir a criação manual de arquivos de configuração complexos, o script `preinstall.sh` prepara o sistema operacional e oferece **dois modos de execução**:

1. **🖥️ Modo Padrão: Wizard Gráfico no Terminal (Dialog TUI)**: Interface rica com janelas, caixas de diálogo, botões `<Avançar>` / `<Voltar>`, navegação por teclado (`Tab`, `Setas`, `Espaço`, `Enter`) ou mouse, formulários agrupados e campos de senha mascarados.
2. **📟 Modo Clássico: Linha de Comando (CLI Headless)**: Execução sequencial direta via terminal texto, ideal para automações, esteiras de CI/CD ou quando invocada explicitamente com a flag `--cli`.

---

### 🚀 Comandos de Inicialização

#### 1. Iniciar com a Interface Gráfica TUI (Recomendado):
- **Via link encurtado:**
  ```bash
  curl -fsSL http://bit.ly/daemind | bash
  ```
- **Via URL direta do GitHub:**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/alcantaraw/daemind/main/preinstall.sh | bash
  ```

#### 2. Iniciar no Modo Terminal Clássico (CLI):
- **Via link encurtado:**
  ```bash
  curl -fsSL http://bit.ly/daemind | bash -s -- --cli
  ```
- **Via URL direta do GitHub:**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/alcantaraw/daemind/main/preinstall.sh | bash -s -- --cli
  ```

#### 3. Iniciar consumindo um Perfil de Cache de Sessão Anterior:
- **Execução no modo Dialog TUI com cache (ex: perfil `minio`):**
  ```bash
  export WIZARD_CACHE_NAME=minio
  curl -fsSL http://bit.ly/daemind | bash
  # Ou via GitHub:
  # curl -fsSL https://raw.githubusercontent.com/alcantaraw/daemind/main/preinstall.sh | bash
  ```

- **Execução no modo CLI com cache (ex: perfil `minio`):**
  ```bash
  export WIZARD_CACHE_NAME=minio
  curl -fsSL http://bit.ly/daemind | bash -s -- --cli
  # Ou via GitHub:
  # curl -fsSL https://raw.githubusercontent.com/alcantaraw/daemind/main/preinstall.sh | bash -s -- --cli
  ```



> [!NOTE]
> **Segurança:** Você pode inspecionar o destino do link encurtado via [CheckShortURL](https://checkshorturl.com/) inserindo a URL `http://bit.ly/daemind`.

---

### 📋 Mapeamento Completo das Telas do Wizard Dialog TUI

```
+-------------------------------------------------------------------------+
|                  daemind. - Sistema Operacional Autônomo                 |
+-------------------------------------------------------------------------+
|  Passo 1/6: Identidade da Empresa, Administrador & Senha Mestra         |
|  Passo 2/6: Topologia de Acesso & Roteamento de Borda                   |
|  Passo 3/6: Seleção Dinâmica de Microsserviços da Stack                 |
|  Passo 4/6: Provedores & Malha de Inteligência Artificial (LiteLLM)     |
|  Passo 5/6: Topologia de Sub-rede Privada Docker (CIDR)                 |
|  Passo 6/6: Resumo Executivo & Confirmação de Deploy                    |
+-------------------------------------------------------------------------+
|                       [  Avançar  ]      [  Voltar  ]                   |
+-------------------------------------------------------------------------+
```

#### 0️⃣ Reutilização de Cache (`--yesno`)
- O instalador verifica a presença de `~/.daemind_wizard_cache*.env`. Se encontrado, pergunta se deseja restaurar os parâmetros. Se confirmado, preenche automaticamente os campos subsequentes e posiciona o foco no botão `<Avançar>`.

#### 1️⃣ Passo 1/6: Identidade Corporativa & Senha Mestra (`--mixedform`)
- **`ID da Empresa (PREFIXO_CONTAINER)`:** Máximo 12 caracteres (ex: `loja1`). Usado no Docker, bancos de dados e domínios.
- **`Nome & Sobrenome do Administrador`:** Identificação do operador.
- **`E-mail Corporativo`:** E-mail de administração oficial da Tailnet e do NocoDB.
- **`Senha Mestra & Confirmação`:** Campos com máscara de caracteres (`*`), validados com regras URI-Safe:
  - Tamanho: 8 a 12 caracteres.
  - Pelo menos 1 letra Maiúscula e 1 Número.
  - Símbolos permitidos: `- _ * ~ ^`.
  - Símbolos proibidos: `@ # & / : ? = % |`.

#### 2️⃣ Passo 2/6: Topologia de Borda & Roteamento (`--radiolist`)
- **`[1] Tailscale Mesh VPN Soberana`:** Solicita o **Tailscale OAuth Client Secret** (chave de 63 caracteres `tskey-client-...`).
- **`[2] Domínio Próprio (BYODNS)`:** Solicita os domínios FQDN do Painel e da API WhatsApp e o tratamento SSL (Let's Encrypt vs Proxy Reverso Cloudflare).

#### 3️⃣ Passo 3/6: Seleção Dinâmica de Microsserviços (`--checklist`)
- Permite marcar/desmarcar com a `Barra de Espaço` os módulos desacoplados:
  - `[X] n8n (Workflows & Automações)`
  - `[X] Chatwoot CRM (Inbox Omnichannel)`
  - `[X] Evolution API (WhatsApp Webhooks)`
  - `[X] Postiz (Social Planner)`
  - `[X] NocoDB (Smart Database & Planilhas)`
  - `[X] S3MinIO / Storage (MinIO ou S3 Cloud)`
  - `[X] Open WebUI (Portal de Chat IA & MCP)`
  - `[X] Metabase BI (Painéis Executivos)`
  - `[X] Listmonk (E-mail Marketing & Transacional)`
  - `[X] Umami (Web Analytics & Privacidade sem Cookies)`
  - `[X] Shlink + Web Client (Encurtador de Links Soberano & UTMs)`
  - `[ ] Ollama & Docling` *(Exibidos em hosts/notebooks com > 4 vCPUs, >= 16GB RAM e GPU dedicada compatível > 4GB VRAM: NVIDIA RTX, Radeon RX 6000-9000 ou Intel Arc)*.
- **Arquitetura de Storage (`--radiolist`):** Define armazenamento Local Direto (disco), MinIO S3 Soberano (local) ou Provedor S3 Cloud Externo (Cloudflare R2 / AWS S3).

#### 4️⃣ Passo 4/6: Malha de Inteligência Artificial (`--checklist` & `--mixedform`)
- Seleção dos provedores (`OpenRouter [Obrigatório]`, `Google Gemini`, `OpenAI`, `Anthropic`, `DeepSeek`) e inserção das respectivas chaves de API.

#### 5️⃣ Passo 5/6: Topologia de Rede Privada (`--radiolist`)
- Escolha da sub-rede de contêineres: `172.25.0.x` (Padrão), `10.50.0.x`, `192.168.200.x` ou Customizada.

#### 6️⃣ Passo 6/6: Resumo Executivo & Disparo (`--yesno`)
- Exibe o resumo consolidado de governança da empresa e dispara a esteira de deploy em segundo plano (`install.sh`), com acompanhamento dos logs em tempo real.


#### 2️⃣ Identidade do Cliente e Empresa
- **`ID da Empresa (PREFIXO_CONTAINER)`:** Identificador curto da empresa (max 12 caracteres, ex: `loja1`, `empresaA`). Usado para nomear contêineres, subredes e certificados.
- **`Nome do Responsável`:** Nome do administrador (ex: `Joao`).
- **`Sobrenome do Responsável`:** Sobrenome do administrador (ex: `Silva`).
- **`Email Oficial do Cliente`:** E-mail de administração (usado no NocoDB, Tailnet e geração do par de chaves OpenPGP).

#### 3️⃣ Definição da Senha Mestra (URI-Safe Master Password)
O wizard solicita e valida a **Senha Mestra do Sistema** (usada para bancos de dados, NocoDB, MinIO e acessos principais). Para prevenir corrupção nas strings de conexão das chamadas PostgreSQL/Redis, o script aplica **regras estritas de segurança URI-Safe**:
- **Tamanho:** Obrigatoriamente entre **8 e 12 caracteres**.
- **Requisitos:** Pelo menos **1 letra MAIÚSCULA** e **1 NÚMERO**.
- **Símbolos Permitidos:** Apenas caracteres seguros para URLs: `-` `_` `*` `~` `^`
- **Símbolos Proibidos:** `@` `#` `&` `/` `:` `?` `=` `%` `|` *(Evita quebra de sintaxe em URLs de conexão)*.
- **Mascaramento:** A digitação é ocultada com caracteres `*` capturados via TTY, sem gravar histórico no `~/.bash_history` nem expor a senha em `ps aux`.

#### 4️⃣ Wizard de Inteligência Artificial (Gateway Múltiplo LiteLLM)
- **Provedores Pagos (Opcional):** Pergunta se deseja cadastrar chaves da OpenAI, Anthropic, Gemini ou DeepSeek.
- **OpenRouter (MANDATÓRIO):** Solicita a chave do OpenRouter para o roteamento sem custo de **modelos 100% gratuitos** (Llama 3, Gemma 2, Qwen).
- **Dica FinOps:** Se o Gemini não tiver sido preenchido, o wizard oferece a inclusão rápida do Tier Gratuito do Google Gemini via Google AI Studio.

#### 5️⃣ Arquitetura de Armazenamento de Mídias e Arquivos (FinOps Profiling)
O sistema analisa automaticamente a capacidade de hardware do host e sugere a melhor opção de armazenamento:
- **`[1] Armazenamento Local Direto`:** Recomendado automaticamente para servidores modestos (< 4 Cores ou < 8GB RAM). Salva anexos em disco local (`./volumes/storage_data/*`), economizando ~1GB de RAM ao desativar o MinIO.
- **`[2] MinIO S3 Soberano`:** Recomendado para servidores de alta performance (>= 4 Cores e >= 8GB RAM). Sobe o container dedicado do MinIO com API S3 nas portas `9000` (API) e `9001` (Console UI).
- **`[3] Provedor S3 Cloud Externo (BYOS)`:** Conecta a stack a provedores em nuvem (AWS S3, Cloudflare R2, DigitalOcean Spaces). O wizard solicitará o Endpoint, Região, Access Key, Secret Key e os nomes dos buckets do Chatwoot e Postiz.

#### 6️⃣ Seleção de Módulos & Aplicações Opcionais (SRE FinOps)
O wizard consulta interativamente se o operador deseja instalar cada uma das aplicações opcionais desacopladas da stack:
- **`n8n (Automation Engine)`** [`[S/n]`]: Motor de automações e orquestrador de workflows (Padrão: `S`).
- **`Open WebUI (Chat IA & RAG)`** [`[S/n]`]: Interface gráfica de chat corporativo e MCP (Padrão: `S`).
- **`Evolution API (WhatsApp)`** [`[S/n]`]: API de conexão nativa com WhatsApp (Padrão: `S`).
- **`Postiz (Social Planner)`** [`[S/n]`]: Agendador e publicador de mídias sociais (Padrão: `S`).
- **`Chatwoot (CRM Omnichannel)`** [`[S/n]`]: Central de atendimento multiatendente (Padrão: `S`).
- **`NocoDB (Smart Databases)`** [`[S/n]`]: Interface de planilhas inteligentes e CRM de estoque (Padrão: `S`).
- **`Metabase (BI & Analytics)`** [`[S/n]`]: Painéis analíticos e dashboards executivos (Padrão: `S`).
- **`Ollama (Local AI Engine)`** [`[S/n]`]: Motor local de modelos de linguagem soberanos (Ativação condicionada a hosts/notebooks com **> 4 Cores, >= 16 GB RAM e GPU dedicada compatível > 4 GB VRAM**: NVIDIA RTX, Radeon RX 6000-9000 ou Intel Arc).
- **`Docling (Document Parsing)`** [`[S/n]`]: Extração e OCR avançado de documentos e PDFs (Ativação condicionada a hosts de alta performance: **> 4 Cores e >= 16 GB RAM**).

> [!TIP]
> **Normalização Estrita:** Todas as respostas são normalizadas automaticamente para `s` ou `n`. Caso o usuário desative um módulo (`N`), a esteira omitirá os containers, rotas de proxy WAF Caddy, cards no portal web e volume de dados do serviço, otimizando o consumo de RAM do servidor. O **Núcleo Core** (`PostgreSQL 17`, `PgBouncer`, `Redis`, `Caddy WAF` e `LiteLLM`) permanece sempre ativo e imutável.

#### 7️⃣ Topologia de Subrede Docker (Isolamento CIDR)
- Permite escolher a faixa de IP interna dos contêineres:
  - `1) 172.25.0.x` (Padrão)
  - `2) 10.50.0.x` (AWS VPC Peering)
  - `3) 192.168.200.x` (On-Premises)
  - `4) Customizada` (Três primeiros octetos)

#### 8️⃣ Geração Autônoma de Chaves OpenPGP (RSA 3072 bits)
- Forja o par de chaves de segurança sem intervenção. Injeta a Chave Pública no `/opt/daemind/.env` e exporta a Chave Privada em `CHAVE_PRIVADA_BACKUP_${EMPRESA}.asc` para download seguro.

#### 9️⃣ Disparo da Instalação
- Pergunta: `🚀 Deseja iniciar a instalação do daemind. agora? [S/n]`.
  - **S / Enter:** Dispara o `./core/scripts/install.sh` imediatamente em segundo plano.
  - **N:** Finaliza o wizard, estrutura a pasta `/opt/daemind` com o `/opt/daemind/.env` pronto e instrui como rodar `sudo ./core/scripts/install.sh` mais tarde.

---

## 5. Disparo da Instalação da Stack (`install.sh`)

Se você optou por disparar a instalação manualmente após o `preinstall.sh`:

```bash
cd /opt/daemind
sudo ./core/scripts/install.sh
```

### 🚀 Fluxo de Execução do `install.sh`:
- Valida o arquivo `.env` (Fonte da Verdade - SSOT).
- Executa a invocação desacoplada e polimórfica da matriz de 15 funções nos scripts `install_<modulo>.sh` (`install_s3minio.sh`, `install_evolution.sh`, `install_postiz.sh`, `install_chatwoot.sh`, `install_nocodb.sh`, etc.).
- Cria os diretórios físicos de volumes persistentes em `/opt/daemind/volumes/`.
- Levanta sequencialmente os contêineres e valida o status de prontidão (*healthchecks*).
- **Sanitização Final:** Purga o script `preinstall.sh` e payloads temporários do servidor.

---

## 6. Arquitetura dos Serviços, Matriz de Portas & Versões (SRE BOM)

O **daemind.** orquestra microsserviços organizados de forma desacoplada e autônoma (`install_<modulo>.sh`). A tabela abaixo detalha a função de cada componente, suas portas de escuta e as versões de imagem docker configuradas no `docker-compose.yml` cruzadas com a versão interna auditada em tempo de execução:

| Serviço | Nome do Container | Imagem Docker | Tag no Compose | Versão Interna | Porta do WAF (Caddy) | Status na Stack |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **PostgreSQL 17** | `${PREFIXO}_postgres` | `pgvector/pgvector` | `pg17` | **17.11** | Interna (5432) | Core Obrigatório |
| **PgBouncer** | `${PREFIXO}_pgbouncer` | `edoburu/pgbouncer` | `v1.25.2-p0` | **1.25.2-p0** | Interna (6432) / 5432 | Core Obrigatório |
| **Redis 8.10** | `${PREFIXO}_redis` | `redis` | `8.10-alpine` | **8.10.0** | Interna (6379) | Core Obrigatório |
| **n8n** | `${PREFIXO}_n8n` | `n8nio/n8n` | `latest` *(dinâmica)* | **latest** | `5678` | Core Obrigatório |
| **Evolution API** | `${PREFIXO}_evolution` | `evoapicloud/evolution-api` | `v2.3.7` | **2.3.7** | `8081` | Opcional Desacoplado |
| **Chatwoot** | `${PREFIXO}_chatwoot` | `chatwoot/chatwoot` | `v4.16.2` | **4.16.2** | `3000` | Opcional Desacoplado |
| **NocoDB** | `${PREFIXO}_nocodb` | `nocodb/nocodb` | `2026.08.0` | **2026.08.0** | `18080` (8080) | Opcional Desacoplado |
| **Postiz** | `${PREFIXO}_postiz` | `ghcr.io/gitroomhq/postiz-app` | `v2.23.0` | **2.23.0** | `5000` | Opcional Desacoplado |
| **Temporal** | `${PREFIXO}_temporal` | `temporalio/auto-setup` | `1.29.7` | **1.29.7** | Interna (7233) | Sub-módulo Postiz |
| **S3MinIO** | `${PREFIXO}_s3minio` | `alpine/minio` | `latest-release` *(dinâmica)* | **2025-10-25** | `9000` (API) / `9001` (UI) | Opcional Desacoplado |
| **Metabase BI** | `${PREFIXO}_metabase` | `metabase/metabase` | `latest` *(dinâmica)* | **0.50.0** | `3030` | Opcional Desacoplado |
| **Ollama AI** | `${PREFIXO}_ollama` | `ollama/ollama` | `latest` *(dinâmica)* | **0.5.0** | `11434` | Opcional Desacoplado |
| **Docling OCR** | `${PREFIXO}_docling` | `ds4sd/docling-serve` | `latest` *(dinâmica)* | **1.0.0** | `5001` | Opcional Desacoplado |
| **Listmonk Mailer** | `${PREFIXO}_listmonk` | `listmonk/listmonk` | `latest` *(dinâmica)* | **latest** | `9005` (9000) | Opcional Desacoplado |
| **Umami Analytics** | `${PREFIXO}_umami` | `ghcr.io/umami-software/umami` | `postgresql-latest` *(dinâmica)* | **latest** | `3008` (3000) | Opcional Desacoplado |
| **Dub Links** | `${PREFIXO}_dub` | `dubinc/dub` | `latest` *(dinâmica)* | **latest** | `3009` (3000) | Opcional Desacoplado |
| **LiteLLM Gateway** | `${PREFIXO}_litellm` | `ghcr.io/berriai/litellm` | `main-latest` *(dinâmica)* | **1.98.0** | `4000` | Core Obrigatório |
| **Open WebUI** | `${PREFIXO}_openwebui` | `ghcr.io/open-webui/open-webui` | `main` *(dinâmica)* | **0.11.0** | `3001` | Core Obrigatório |
| **Caddy WAF** | `${PREFIXO}_caddy` | `caddy` | `2.11.4-alpine` | **2.11.4** | `80` / `443` | Core Obrigatório |

> [!NOTE]
> As imagens que utilizam tags flutuantes ou dinâmicas no `docker-compose.yml` (`latest`, `main`, `main-latest`) são inspecionadas dinamicamente durante a inicialização, garantindo transparência completa da versão binária em execução no servidor.

---

## 7. Observabilidade, Automações e Toolkit Operacional SRE

### 📊 Log da Esteira de Instalação:
Acompanhe a subida dos serviços em tempo real rodando:

```bash
tail -f /tmp/debug_install.log
```

### 🛠️ Comandos do Toolkit de Operação & Manutenção SRE:

```bash
# 1. Execução de Backup Manual Criptografado (GPG)
sudo /bin/bash /opt/daemind/core/scripts/backup_diario.sh

# 2. Restauração de Produção e Disaster Recovery
sudo /bin/bash /opt/daemind/core/scripts/restore_production.sh

# 3. Atualização Declarativa da Stack (Git Pull + Compose Pull + Migrations)
sudo /bin/bash /opt/daemind/core/scripts/upgrade_stack.sh

# 4. Sincronização Inteligente do Catálogo de Modelos de IA
sudo /bin/bash /opt/daemind/core/scripts/install_1ia.sh

# 5. Suíte de Testes de Fumaça e Prontidão (CI/CD Smoke Test)
sudo /bin/bash /opt/daemind/core/scripts/ci_smoke_test.sh

# 6. Restabelecimento e Recuperação de Túneis VPN Tailscale
sudo /bin/bash /opt/daemind/core/scripts/install_0ts.sh /opt/daemind recovery
```

### 🔍 Comandos SRE para Leitura Direta de Logs dos Containers:

```bash
# PostgreSQL & PGVector
sudo docker logs --tail 50 ${PREFIXO}_postgres

# Connection Pooler (PgBouncer)
sudo docker logs --tail 50 ${PREFIXO}_pgbouncer

# Orquestrador n8n
sudo docker logs --tail 50 ${PREFIXO}_n8n

# WhatsApp (Evolution API)
sudo docker logs --tail 50 ${PREFIXO}_evolution

# Atendimento Omnichannel (Chatwoot)
sudo docker logs --tail 50 ${PREFIXO}_chatwoot

# CRM & Banco de Dados (NocoDB)
sudo docker logs --tail 50 ${PREFIXO}_nocodb

# Redes Sociais (Postiz)
sudo docker logs --tail 50 ${PREFIXO}_postiz

# Gateway de IA (LiteLLM)
sudo docker logs --tail 50 ${PREFIXO}_litellm

# Interface RAG / Chatbot (Open WebUI)
sudo docker logs --tail 50 ${PREFIXO}_openwebui

# Armazenamento S3 (MinIO)
sudo docker logs --tail 50 ${PREFIXO}_s3minio

# WAF & Reverse Proxy (Caddy)
sudo docker logs --tail 50 ${PREFIXO}_caddy

# Agente Daemon do Tailscale (Mesh VPN & Subdomínios)
sudo journalctl -u tailscaled --no-pager
```

> [!TIP]
> Para travar o console assistindo às linhas de log entrarem ao vivo (estilo *tail -f*), adicione a flag `-f`:
> ```bash
> sudo docker logs -f --tail 50 ${PREFIXO_CONTAINER}_n8n
> sudo journalctl -fu tailscaled
> ```

---

## 8. Casos de Uso Operacionais e Workflows Práticos

Abaixo estão descritos os principais fluxos de automação pré-configurados no ecossistema:

### 💬 8.1. Atendimento Omnichannel 24/7 com RAG
- **Entrada de Mensagens:** As mensagens de WhatsApp (via Evolution API), Instagram e Facebook chegam ao n8n.
- **Roteamento Inteligente:** O LiteLLM consulta a tabela local `base_conhecimento` via `pgvector` para responder dúvidas com base no catálogo e manuais da empresa.
- **Transbordo para Atendentes:** Casos complexos são encaminhados para o Chatwoot com múltiplos atendentes no mesmo número.

### 📦 8.2. CRM de Estoque & Controle de Insumos (Caixas, Fitagem e Embalagens)
- **Tabela `insumos`:** Monitora saldo de caixas, fitas e etiquetas.
- **Alerta de Estoque Mínimo:** Uma rotina no n8n roda toda segunda-feira às 08:00 inspecionando o saldo. Se o estoque estiver abaixo do mínimo, o n8n gera um relatório de fornecedores no NocoDB e dispara um alerta de compra via WhatsApp ao administrador.

### 🛒 8.3. Recuperação de Carrinhos Abandonados & Notificação de Rastreio
- **Webhooks de Venda:** Ao receber o webhook de pedido pendente (`Pix` ou `Boleto`), o n8n recupera o código Copia e Cola e envia uma mensagem amigável no WhatsApp do cliente para acelerar a conversão.
- **Rastreamento Automático:** Ao faturar e enviar o pedido, o n8n extrai o código de rastreamento e envia o link direto de acompanhamento no WhatsApp do comprador.

### 🏷️ 8.4. Expedição por Leitor Ótico USB (Hardware HID)
- O operador abre a View de Expedição no NocoDB (com `Autofocus` ativo).
- Ao bipar o código de barras da caixa com o leitor USB, a string é enviada instantaneamente com `Enter`, acionando a baixa atômica de estoque e gerando a guia de postagem sem uso de mouse ou teclado.
