# 📘 Manual de Implantação e Operação de Infraestrutura — daemind. (v6.0)

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

## 4. Preparação do Host e Wizard Interativo (`preinstall.sh`)

O provisionamento do **daemind.** é **Low-Touch / Assistido**: em vez de exigir a criação manual de arquivos de configuração complexos, o script `preinstall.sh` prepara o sistema operacional e apresenta um **Wizard Interativo no Terminal CLI** de 2 minutos para coletar os parâmetros essenciais.

Acesse o terminal do seu servidor Ubuntu recém-instalado como `root` ou usuário com privilégios `sudo` e execute:

```bash
curl -fsSL http://bit.ly/daemind | bash
```

*(Ou via URL completa do repositório: `curl -fsSL https://raw.githubusercontent.com/alcantaraw/daemind/main/preinstall.sh | bash`)*

> [!NOTE]
> **Segurança:** Você pode inspecionar o destino do link encurtado via [CheckShortURL](https://checkshorturl.com/) inserindo a URL `http://bit.ly/daemind`.

---

### 📋 Mapeamento Completo das Perguntas do Wizard (Passo a Passo)

Durante a execução do `preinstall.sh`, o terminal apresentará sequencialmente os seguintes blocos de perguntas:

#### 1️⃣ Topologia de Rede e Roteamento
- **Escolha da Conectividade:**
  - `1) Tailscale Mesh VPN`: Para servidores atrás de CGNAT ou redes locais. O wizard solicitará o **Tailscale OAuth Client Secret** (63 caracteres `tskey-client-...`).
  - `2) BYODNS (IP Fixo / Domínio Próprio)`: O wizard solicitará o **Domínio do Painel Mestre** (ex: `painel.empresa.com`) e o **Domínio da API WhatsApp** (ex: `api.empresa.com`), além da escolha do tratamento TLS Caddy (Let's Encrypt Nativo vs Cloudflare Proxy).

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

#### 5️⃣ Topologia de Subrede Docker (Isolamento CIDR)
- Permite escolher a faixa de IP interna dos contêineres:
  - `1) 172.25.0.x` (Padrão)
  - `2) 10.50.0.x` (AWS VPC Peering)
  - `3) 192.168.200.x` (On-Premises)
  - `4) Customizada` (Três primeiros octetos)

#### 6️⃣ Geração Autônoma de Chaves OpenPGP (RSA 3072 bits)
- Forja o par de chaves de segurança sem intervenção. Injeta a Chave Pública no `.env` e exporta a Chave Privada em `CHAVE_PRIVADA_BACKUP_${EMPRESA}.asc` para download seguro.

#### 7️⃣ Disparo da Instalação
- Pergunta: `🚀 Deseja iniciar a instalação do daemind. agora? [S/n]`.
  - **S / Enter:** Dispara o `./core/scripts/install.sh` imediatamente em segundo plano.
  - **N:** Finaliza o wizard, estrutura a pasta `/opt/daemind` com o `core/config/.env` pronto e instrui como rodar `sudo ./core/scripts/install.sh` mais tarde.

---

## 5. Disparo da Instalação da Stack (`install.sh`)

Se você optou por disparar a instalação manualmente após o `preinstall.sh`:

```bash
cd /opt/daemind
sudo ./core/scripts/install.sh
```

### 🚀 Fluxo de Execução do `install.sh`:
- Valida o arquivo `core/config/.env` (Fonte da Verdade - SSOT).
- Cria os diretórios físicos de volumes persistentes em `/opt/daemind/volumes/`.
- Levanta sequencialmente os contêineres e valida o status de prontidão (*healthchecks*).
- **Sanitização Final:** Purga o script `preinstall.sh` e payloads temporários do servidor.

---

## 6. Arquitetura dos Serviços, Matriz de Portas & Versões (SRE BOM)

O **daemind.** orquestra **13 serviços essenciais** trabalhando em malha privada. A tabela abaixo detalha a função de cada componente, suas portas de escuta e as versões de imagem docker configuradas no `docker-compose.yml` cruzadas com a versão interna auditada em tempo de execução:

| Serviço | Nome do Container | Imagem Docker | Tag no Compose | Versão Interna | Porta do WAF (Caddy) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **PostgreSQL 16** | `${PREFIXO}_db` | `pgvector/pgvector` | `pg16` | **16.14** | Interna (5432) |
| **PgBouncer** | `${PREFIXO}_pooler` | `edoburu/pgbouncer` | `v1.25.2-p0` | **1.25.2-p0** | Interna (6432) / 5432 |
| **Redis 7.4** | `${PREFIXO}_redis` | `redis` | `7.4-alpine` | **7.4.10** | Interna (6379) |
| **n8n** | `${PREFIXO}_n8n` | `n8nio/n8n` | `2.31.6` | **2.31.6** | `5678` |
| **Evolution API** | `${PREFIXO}_evolution` | `evoapicloud/evolution-api` | `v2.3.7` | **2.3.7** | `8081` |
| **Chatwoot** | `${PREFIXO}_chatwoot` | `chatwoot/chatwoot` | `v4.16.0` | **4.16.0** | `3000` |
| **NocoDB** | `${PREFIXO}_nocodb` | `nocodb/nocodb` | `2026.07.0` | **2026.07.0** | `18080` (8080) |
| **Postiz** | `${PREFIXO}_postiz` | `ghcr.io/gitroomhq/postiz-app` | `v2.21.10` | **2.21.10** | `5000` |
| **Temporal** | `${PREFIXO}_temporal` | `temporalio/auto-setup` | `1.29.7` | **1.29.7** | Interna (7233) |
| **MinIO S3** | `${PREFIXO}_minio` | `minio/minio` | `latest` *(dinâmica)* | **2025-09-07T16-13-09** | `9000` (API) / `9001` (UI) |
| **LiteLLM Gateway** | `${PREFIXO}_litellm` | `ghcr.io/berriai/litellm` | `main-latest` *(dinâmica)* | **1.96.0** | `4000` |
| **Open WebUI** | `${PREFIXO}_openwebui` | `ghcr.io/open-webui/open-webui` | `main` *(dinâmica)* | **0.11.0** | `3001` |
| **Caddy WAF** | `${PREFIXO}_waf` | `caddy` | `2.11.4-alpine` | **2.11.4** | `80` / `443` |

> [!NOTE]
> As imagens que utilizam tags flutuantes ou dinâmicas no `docker-compose.yml` (`latest`, `main`, `main-latest`) são inspecionadas dinamicamente durante a inicialização, garantindo transparência completa da versão binária em execução no servidor.

---

## 7. Observabilidade e Comandos de Inspeção SRE

### 📊 Log da Esteira de Instalação:
Acompanhe a subida dos serviços em tempo real rodando:

```bash
tail -f /tmp/debug_install.log
```

### 🔍 Comandos SRE para Leitura Direta de Logs dos Containers:

```bash
# PostgreSQL & PGVector
sudo docker logs --tail 50 ${PREFIXO}_db

# Connection Pooler (PgBouncer)
sudo docker logs --tail 50 ${PREFIXO}_pooler

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
sudo docker logs --tail 50 ${PREFIXO}_minio

# WAF & Reverse Proxy (Caddy)
sudo docker logs --tail 50 ${PREFIXO}_waf

# Agente Daemon do Tailscale (Mesh VPN & Subdomínios)
sudo journalctl -u tailscaled --no-pager
```

> [!TIP]
> Para travar o console assistindo às linhas de log entrarem ao vivo (estilo *tail -f*), adicione a flag `-f`:
> ```bash
> sudo docker logs -f --tail 50 loja_n8n
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
