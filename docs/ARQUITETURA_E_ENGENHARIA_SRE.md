# ⚙️ Engenharia de Resiliência, Arquitetura SRE e Tunings de Performance — daemind. (v6.0)

Whitepaper e especificação de engenharia técnica exaustiva cobrindo a arquitetura de resiliência, padrões DevOps, segurança perimetral (Zero-Trust), gestão de segredos e tunings de Kernel/Container implementados no **daemind.**.

---

## 📌 Sumário

- [1. Filosofia de Engenharia & Princípios SRE](#1-filosofia-de-engenharia--princípios-sre)
- [2. Hardening Perimetral & Defesa em Profundidade (SecOps)](#2-hardening-perimetral--defesa-em-profundidade-secops)
  - [2.1. Trava de Concorrência Estrita (`flock` no Kernel)](#21-trava-de-concorrência-estrita-flock-no-kernel)
  - [2.2. Captura Criptográfica de Keystrokes via Raw TTY](#22-captura-criptográfica-de-keystrokes-via-raw-tty)
  - [2.3. Validação Estrita de Senha Mestra (URI-Safe)](#23-validação-estrita-de-senha-mestra-uri-safe)
  - [2.4. Firewall Dinâmico na Chain `DOCKER-USER` (IPTables + IPSet + Dnsmasq)](#24-firewall-dinâmico-na-chain-docker-user-iptables--ipset--dnsmasq)
  - [2.5. Elevação Temporária e Revogação Garantida do Sudo (`trap EXIT`)](#25-elevação-temporária-e-revogação-garantida-do-sudo-trap-exit)
  - [2.6. Par de Chaves OpenPGP/RSA 3072-bit Autônomo](#26-par-de-chaves-openpgprsa-3072-bit-autônomo)
- [3. Resiliência do Host & Tuning de Kernel Linux](#3-resiliência-do-host--tuning-de-kernel-linux)
  - [3.1. Kernel Memory Overcommit (`vm.overcommit_memory = 1`)](#31-kernel-memory-overcommit-vmovercommit_memory--1)
  - [3.2. Prevenção de Bloqueio em Deploy Headless (APT Non-Interactive)](#32-prevenção-de-bloqueio-em-deploy-headless-apt-non-interactive)
  - [3.3. Prevenção de Race Condition no Boot de Cloud (dpkg fuser wait)](#33-prevenção-de-race-condition-no-boot-de-cloud-dpkg-fuser-wait)
  - [3.4. Sincronização de Relógio Atômica (NTP + Hardware Clock + HTTP Header Parsing)](#34-sincronização-de-relógio-atômica-ntp--hardware-clock--http-header-parsing)
  - [3.5. Motor Autônomo & Desacoplado de Auto-Tuning de Hardware (`core/scripts/autotune.sh`)](#35-motor-autônomo--desacoplado-de-auto-tuning-de-hardware-corescriptsautotunesh)
- [4. Arquitetura da Malha de Contêineres & Tunings por Serviço](#4-arquitetura-da-malha-de-contêineres--tunings-por-serviço)
  - [4.1. PostgreSQL 16 + PGVector + PgBouncer (Transaction Pooling)](#41-postgresql-16--pgvector--pgbouncer-transaction-pooling)
  - [4.2. Chatwoot Omnichannel & Compilação Ruby YJIT](#42-chatwoot-omnichannel--compilação-ruby-yjit)
  - [4.3. Motor de Automação n8n & Hardening de Memória](#43-motor-de-automação-n8n--hardening-de-memória)
  - [4.4. Malha de IA: LiteLLM Gateway & Open WebUI RAG Compaction](#44-malha-de-ia-litellm-gateway--open-webui-rag-compaction)
  - [4.5. Postiz Social Planner & Orquestrador Temporal](#45-postiz-social-planner--orquestrador-temporal)
  - [4.6. Desacoplamento de Armazenamento S3 via MinIO Local](#46-desacoplamento-de-armazenamento-s3-via-minio-local)
  - [4.7. Gateway de Borda Caddy WAF & ACME Automático](#47-gateway-de-borda-caddy-waf--acme-automático)
  - [4.8. Paridade de Fuso Horário e Mapeamento Estático de IP](#48-paridade-de-fuso-horário-e-mapeamento-estático-de-ip)
- [5. Gestão de Segredos & Sanitização em Memória (Zero Leakage)](#5-gestão-de-segredos--sanitização-em-memória-zero-leakage)
- [6. Idempotência, Traps Forenses & Observabilidade SRE](#6-idempotência-traps-forenses--observabilidade-sre)

---

## 1. Filosofia de Engenharia & Princípios SRE

O **daemind.** é construído sob a disciplina técnica de **Site Reliability Engineering (SRE)** do Google. A premissa central é que o código de infraestrutura deve ser tão robusto, testável e tolerante a falhas quanto um sistema de software distribuído.

### 📐 Princípios de Design:
* **Autocura (Self-Healing):** Todo componente possui mecanismos de verificação de saúde (*healthchecks*) e políticas de reinício automático (*restart: unless-stopped* ou *always*).
* **Eficiência Extrema de Recursos (FinOps):** 13 microsserviços corporativos pesados são integrados para rodar com alta performance em um servidor modesto de **4 vCPUs e 8 GB de RAM**.
* **Zero-Touch Runtime & Low-Touch Setup:** Zero intervenção manual após a coleta rápida de variáveis no Wizard inicial.
* **Soberania Absoluta dos Dados:** Nenhum dado de cliente, lead ou faturamento trafega por nuvens de terceiros não autorizadas.

---

## 2. Hardening Perimetral & Defesa em Profundidade (SecOps)

### 🔒 2.1. Trava de Concorrência Estrita (`flock` no Kernel)
Para evitar corrupção de estado (*race condition*) por execuções duplicadas acidentais de scripts no servidor:
```bash
LOCK_FILE="/tmp/${SCRIPT_NOME}.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "⚠️ [ALERTA SRE] Uma instância do script JÁ ESTÁ EM EXECUÇÃO!"
    exit 1
fi
```
O manipulador de arquivo 200 é travado no Kernel Linux via chamada de sistema `flock`. Se o script for chamado novamente enquanto outra instância estiver rodando, o processo secundário é abortado instantaneamente.

---

### ⌨️ 2.2. Captura Criptográfica de Keystrokes via Raw TTY
Para a captura de senhas sensíveis no terminal, o script **despreza o comando genérico `read -s`** (que não exibe nenhum feedback visual ao operador e pode vazar buffer). É utilizado um loop de interceptação de caracteres char-a-char via TTY nativo:

```bash
while IFS= read -r -s -n 1 char; do
    if [[ -z "$char" ]]; then break; fi
    # Tratamento cross-platform de Backspace (Linux \177 vs Mac \b)
    if [[ "$char" == $'\177' || "$char" == $'\b' ]]; then
        if [ ${#input_val} -gt 0 ]; then
            input_val="${input_val%?}"
            echo -ne "\b \b"
        fi
    else
        input_val+="$char"
        echo -ne "*"
    fi
done
```
**Benefícios de Segurança:**
1. Mascara a senha com asteriscos `*` no console para confirmação visual de digitação.
2. Não grava as senhas no histórico do shell (`~/.bash_history`).
3. Impede a exposição de senhas na tabela de processos do sistema (`ps aux`).

---

### 🛡️ 2.3. Validação Estrita de Senha Mestra (URI-Safe)
A senha mestra é utilizada para autenticar o PostgreSQL, Redis, PgBouncer, NocoDB e MinIO. Para prevenir a quebra ou corrupção de strings de conexão de banco (Ex: `postgresql://user:pass@host:5432/db`), o script impõe validação via Expressões Regulares (Regex):

- **Tamanho:** Entre 8 e 12 caracteres.
- **Requisitos:** Mínimo 1 letra MAIÚSCULA e 1 NÚMERO.
- **Símbolos Permitidos:** Apenas caracteres seguros para URLs: `-` `_` `*` `~` `^`
- **Símbolos Proibidos:** `@` `#` `&` `/` `:` `?` `=` `%` `|` *(Caracteres reservados de sintaxe URI)*.

---

### 🧱 2.4. Firewall Dinâmico na Chain `DOCKER-USER` (IPTables + IPSet + Dnsmasq)
Por padrão, o daemon do Docker abre portas diretamente na tabela `FORWARD` do IPTables, ignorando regras padrão do `UFW` ou `iptables -A INPUT`.

O **daemind.** contorna essa vulnerabilidade injetando regras diretamente na chain `DOCKER-USER`:

```bash
# 1. Criação do IPSet para Domínios Permitidos
sudo ipset create ALLOWED_DOMAINS hash:net 2>/dev/null || true

# 2. Injeção de Bloqueio WAN na Chain DOCKER-USER
sudo iptables -I DOCKER-USER -i eth0 -p tcp --dport 5678 -j DROP # n8n
sudo iptables -I DOCKER-USER -i eth0 -p tcp --dport 3000 -j DROP # Chatwoot
sudo iptables -I DOCKER-USER -i eth0 -p tcp --dport 4000 -j DROP # LiteLLM
sudo iptables -I DOCKER-USER -i eth0 -p tcp --dport 3001 -j DROP # Open WebUI
sudo iptables -I DOCKER-USER -i eth0 -p tcp --dport 9000 -j DROP # MinIO API
```
- **Ingress:** Libera apenas `80` (HTTP), `443` (HTTPS) e `8081` (WhatsApp) para tráfego público WAN. Portas administrativas só respondem em interfaces privadas RFC 1918 (LAN) ou na VPN Tailscale.
- **Egress com Dnsmasq:** O `dnsmasq` roda na porta 53 capturando requisições DNS dos contêineres e alimentando a tabela `IPSet` dinamicamente para limitar conexões externas autorizadas.

---

### 🔐 2.5. Elevação Temporária e Revogação Garantida do Sudo (`trap EXIT`)
Para evitar travamentos interativos em execuções *headless* sem manter privilégios de root expostos indefinidamente:

```bash
echo "Defaults timestamp_timeout=60" | sudo tee /etc/sudoers.d/custom_sudo_timeout > /dev/null
sudo chmod 0440 /etc/sudoers.d/custom_sudo_timeout

cleanup_sudo_timeout() {
    sudo rm -f /etc/sudoers.d/custom_sudo_timeout
    sudo -k
}
trap cleanup_sudo_timeout EXIT
```
O cache do sudo é estendido temporariamente para a esteira e o gatilho `trap EXIT` do Bash garante a revogação imediata e a destruição do arquivo do sudoers ao encerrar a execução.

---

### 🔑 2.6. Par de Chaves OpenPGP/RSA 3072-bit Autônomo
Durante o `preinstall.sh`, o sistema gera autonomamente um par de chaves criptográficas OpenPGP RSA de 3072 bits usando um diretório temporário isolado (`mktemp -d -t sre_gnupg_XXXXXX` com permissão `700`):

1. **Chave Pública:** Exportada em formato ASCII-Armored, convertida para Base64 e injetada no arquivo `.env` para uso pelos scripts automatizados de backup criptografado (`backup_diario.sh`). Importada automaticamente no keyring local via `gpg --import`.
2. **Chave Privada:** Exportada protegida pela senha mestra para `CHAVE_PRIVADA_BACKUP_${EMPRESA}.asc` (permissão `600`) para download pelo operador e subsequente deleção no servidor.

---

## 3. Resiliência do Host & Tuning de Kernel Linux

### ⚡ 3.1. Kernel Memory Overcommit (`vm.overcommit_memory = 1`)
O Redis realiza snapshots assíncronos de banco de dados (`BGSAVE`) utilizando a chamada de sistema `fork()`. No modo padrão do Linux (`overcommit_memory = 0`), o Kernel recusa o fork se a memória RAM alocada estiver acima de 50%, derrubando as filas do n8n e da Evolution API.

- **Ajuste aplicado:** `vm.overcommit_memory = 1` no `/etc/sysctl.conf`, forçando o Kernel a conceder alocação virtual de memória necessária para o fork do Redis sem falhas.

---

### 🚫 3.2. Prevenção de Bloqueio em Deploy Headless (APT Non-Interactive)
Em instalações automatizadas em nuvem, atualizações de pacotes do sistema (libc, openssh, kernel) frequentemente abrem telas azuis interativas de diálogo (*ncurses*), travando o provisionamento.

**Hardening Aplicado:**
```bash
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
```
Injeção da opção `-o Dpkg::Options::="--force-confold"` em todas as chamadas de instalação do `apt-get` para manter arquivos de configuração existentes sem interrupções.

---

### ⌛ 3.3. Prevenção de Race Condition no Boot de Cloud (dpkg fuser wait)
Cloud VPS (AWS EC2, Hetzner, DigitalOcean) disparam a rotina de atualização automática `unattended-upgrades` no exato instante em que a VM é criada.

Para evitar erros de travamento de arquivo (`Could not get lock /var/lib/dpkg/lock-frontend`), o script executa um loop de checagem atômica de processos via `fuser`:

```bash
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "  ↳ Aguardando liberação das travas de instalação do sistema..."
    sleep 5
done
```

---

### ⚙️ 3.5. Motor Autônomo & Desacoplado de Auto-Tuning de Hardware (`core/scripts/autotune.sh`)
Para permitir o desacoplamento e o escalonamento autônomo dos microsserviços sem engessamento de código, a extração de métricas de hardware foi separada da calibragem:

1. **Extração de Métricas Cruas (`preinstall.sh`):** O script de preparação descobre o hardware do host (`SYSTEM_TOTAL_CPUS`, `SYSTEM_TOTAL_RAM_MB`, `SYSTEM_TOTAL_DISK_GB`) e grava esses valores no arquivo `.env`.
2. **Cálculo da Matriz de Performance (`core/scripts/autotune.sh`):** Módulo SRE desacoplado que lê as métricas do `.env` e calcula dinamicamente duas matrizes independentes:
   - **Matriz de CPU (baseada em `nproc`):** Aloca frações e cotas de vCPUs por serviço conforme o total de núcleos (`Standard: <=4 cores`, `Pro: 5-8 cores`, `Enterprise: >8 cores`).
   - **Matriz de RAM & Reservations (baseada em `free -m`):** Define limites estritos (`limits.memory`), reservas garantidas (`reservations.memory`), buffers do Postgres (`shared_buffers`, `work_mem`), evicção do Redis (`maxmemory`), limites de Heap V8 (`NODE_OPTIONS`), workers do LiteLLM e threads do Sidekiq.
3. **Consumo no Docker Compose:** O [`core/config/docker-compose.yml`](../core/config/docker-compose.yml) consome as variáveis dinâmicas com fallbacks seguros `${VAR:-DEFAULT}`, garantindo idempotência e execução perfeita em instâncias de 8GB até servidores corporativos de 64GB+.

---

## 4. Arquitetura da Malha de Contêineres & Tunings por Serviço

### 🐘 4.1. PostgreSQL 16 + PGVector + PgBouncer (Transaction Pooling)

```mermaid
graph TD
    ClientApps[Contêineres: n8n, Evolution, Chatwoot, NocoDB, LiteLLM, Open WebUI] -->|Conexões Concorrentes Port 6432| PgBouncer[PgBouncer Pooler - Transaction Mode]
    PgBouncer -->|Pool Controlado Max 250 Conexões Port 5432| Postgres[PostgreSQL 16 + PGVector]
```

- **PostgreSQL 16:**
  - `command: ["postgres", "-c", "max_connections=250", "-c", "shared_buffers=256MB", "-c", "work_mem=8MB", "-c", "log_connections=off", "-c", "log_disconnections=off", "-c", "log_min_messages=warning"]`
  - Suporte à extensão `pgvector` para busca por vetores de embedding em RAG de IA.
  - Otimização de busca vetorial RAG com `shared_buffers=256MB` e `work_mem=8MB`.
  - Logs debloquetados (sem poluição de I/O em conexões aceitas/encerradas).
- **PgBouncer Connection Pooler:**
  - `POOL_MODE=transaction`, `LISTEN_PORT=6432`, `MAX_CLIENT_CONN=200`, `DEFAULT_POOL_SIZE=20`, `AUTH_TYPE=scram-sha-256`.
  - Atua como um multiplexador. Centenas de requisições paralelas abertas pelos microsserviços reutilizam um pool controlado de conexões no Postgres, evitando consumo excessivo de memória RAM por processos de banco.
- **Redis Cache & Fila:**
  - `command: ["redis-server", "--loglevel", "warning", "--maxmemory", "200mb", "--maxmemory-policy", "volatile-lru"]`
  - Evicção automática por LRU (*Least Recently Used*) impedindo estouros no limite do container.

---

### 💬 4.2. Chatwoot Omnichannel & Compilação Ruby YJIT
- **Compilador Ruby YJIT Ativado (`RUBY_YJIT_ENABLE=1`):** Ativa o compilador Just-In-Time do Ruby 3 no Rails, reduzindo o tempo de latência de resposta HTTP em até 30% e o uso de CPU.
- **Armazenamento Desacoplado:** `ACTIVE_STORAGE_SERVICE=amazon`, `S3_FORCE_PATH_STYLE=true` redirecionando todo o armazenamento de imagens, áudios e documentos para o MinIO S3 local, mantendo o contêiner leve e efêmero.

---

### ⚡ 4.3. Motor de Automação n8n & Hardening de Memória
- **Tuning V8 Heap:** `NODE_OPTIONS=--max-old-space-size=768` forçando o Garbage Collector a rodar dentro da margem de 1GB antes de disparar o OOM Killer.
- **Servidor MCP Nativo:** `N8N_MCP_ACCESS_ENABLED=true` habilitado para integração nativa com protocolo de contexto de IA.
- **Desativação de Telemetria:** `N8N_PERSONALIZATION_ENABLED=false`, `N8N_DIAGNOSTICS_ENABLED=false`, `N8N_METRICS_ENABLED=false`.
- **Limpeza Automática de Execuções (Pruning):** `EXECUTIONS_DATA_PRUNE=true`, `EXECUTIONS_DATA_MAX_AGE=14` e limite máximo de 50.000 execuções salvas. Impede o inchaço do banco de dados ao longo dos meses.

---

### 🤖 4.4. Malha de IA: LiteLLM Gateway & Open WebUI RAG Compaction
- **LiteLLM Gateway (`litellm`):**
  - Dimensionado com `cpus: 1.0` e `memory: 2048M` rodando com worker único (`--num_workers 1`) para alta taxa de transferência de tokens sem atraso de roteamento.
  - Roteamento de menor custo conectando ao OpenRouter (modelos 100% gratuitos) com fallback transparente para Gemini, OpenAI, Claude ou DeepSeek.
- **Open WebUI (`openwebui`):**
  - `ENABLE_CONTEXT_COMPACTION=True`: Comprime automaticamente históricos de chats longos antes de enviar ao gateway, reduzindo consumo de tokens.
  - `ENABLE_IMAGE_GENERATION=False`, `ENABLE_COMMUNITY_SHARING=False`: Recursos desnecessários desligados para hardening e otimização de I/O.
  - `RAG_EMBEDDING_ENGINE=openai` apontando diretamente para o LiteLLM local na porta `4000`.

---

### 📅 4.5. Postiz Social Planner & Orquestrador Temporal
- **Postiz (`postiz`):** Gerenciador de agendamento de mídias sociais. Dimensionado para `cpus: 2.0` e `memory: 4096M` com `NODE_OPTIONS=--max-old-space-size=2048` para estabilizar os 3 processos PM2 simultâneos (backend, frontend Next.js e orchestrator) sem estouro de RAM no aquecimento.
- **Temporal Server (`temporal`):** Motor de workflow assíncrono (`temporalio/auto-setup:1.29.7`) dimensionado para `768M` encarregado da fila de postagens do Postiz com tolerância a falhas.

---

### 🗄️ 4.6. Desacoplamento de Armazenamento S3 via MinIO Local
- **MinIO (`minio`):** Servidor S3 Soberano rodando localmente na porta `9000` (API) e `9001` (Console UI).
- Recebe arquivos pesados do Chatwoot e Postiz com compressão ativada (`MINIO_COMPRESS=on` para JSON, CSV, JS, XML), otimizando I/O de disco.

---

### 🔒 4.7. Gateway de Borda Caddy WAF & ACME Automático
- **Caddy (`caddy`):** Atua como Reverse Proxy, Firewall WAF e emissor automático de certificados SSL/TLS via Let's Encrypt (modo BYODNS) ou suporte a VPN Tailscale.
- Serve páginas estáticas e favicons nativamente da memória com regras de cache agressivas.

---

### 🌍 4.8. Paridade de Fuso Horário e Mapeamento Estático de IP
- **Fuso Horário Unificado:** Todos os 13 contêineres realizam montagem de volume somente-leitura do relógio do host:
  ```yaml
  volumes:
    - '/etc/timezone:/etc/timezone:ro'
    - '/etc/localtime:/etc/localtime:ro'
  ```
- **Alocação Estática de IPs Privados:** Toda a comunicação entre microsserviços utiliza endereçamento IPv4 estático na rede bridge interna (Ex: Redis em `.2`, Postgres em `.9`, PgBouncer em `.10`, LiteLLM em `.13`), eliminando latência de resolução DNS entre os contêineres Docker.

---

## 5. Gestão de Segredos & Sanitização em Memória (Zero Leakage)

Em conformidade com os padrões de segurança DevSecOps, **nenhuma credencial permanece exposta em memória após a execução**:

### 🧼 Protocolo de Expurgo de Variáveis de Ambiente:
No manipulador de erro (`error_forensic_handler`) e ao encerrar normalmente a execução do `preinstall.sh` ou `install.sh`:

```bash
export GIT_TOKEN_BOOT="EXPURGADO" DB_PASSWORD="EXPURGADO" TS_OAUTH_SECRET="EXPURGADO" \
       LOJA_API_KEY="EXPURGADO" LOJA_APP_KEY="EXPURGADO" GEMINI_API_KEY="EXPURGADO" \
       OPENAI_API_KEY="EXPURGADO" ANTHROPIC_API_KEY="EXPURGADO" \
       DEEPSEEK_API_KEY="EXPURGADO" OPENROUTER_API_KEY="EXPURGADO"

unset GIT_TOKEN_BOOT DB_PASSWORD TS_OAUTH_SECRET LOJA_API_KEY LOJA_APP_KEY \
      GEMINI_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY OPENROUTER_API_KEY
```

O arquivo final `.env` em `/opt/daemind/core/config/.env` é gravado com permissão estrita `600` (`chmod 600`), acessível exclusivamente pelo usuário root.

---

## 6. Idempotência, Traps Forenses & Observabilidade SRE

### 🚨 6.1. Cobertura Forense Transversal (`set -eEo pipefail`)
Os scripts de automação ativam tratamento estrito de erro:

```bash
set -eEo pipefail

error_forensic_handler() {
    local linha_erro="$1"
    local comando_falho="$2"
    echo "====================================================================="
    echo "🚨 [FALHA CRÍTICA NO PROVISIONAMENTO] A esteira foi interrompida!"
    echo "➜ Linha da Quebra: ${linha_erro}"
    echo "➜ Comando Abortado: ${comando_falho}"
    echo "====================================================================="
    # Executa expurgo de segredos em memória
}
trap 'error_forensic_handler $LINENO "$BASH_COMMAND"' ERR
```

### 📊 6.2. Log Stream Redirection
Toda a saída do console é espelhada em tempo real para auditoria pós-instalação:
```bash
exec > >(tee -a "/tmp/debug_install.log") 2> >(tee -a "/tmp/debug_install.log" >&2)
```

### 🔍 6.3. Protocolo Autônomo de Inspeção de Logs no Host
Se um contêiner falhar nos testes de prontidão (*healthchecks*), o `install.sh` consulta dinamicamente o caminho físico do arquivo JSON de log gravado pelo daemon do Docker em `/var/lib/docker/containers/`:

```bash
LOG_PATH=$(sudo docker inspect --format='{{.LogPath}}' "$CONTAINER_NAME" 2>/dev/null)
echo "🚨 [DIAGNÓSTICO SRE] Inspecione os logs do contêiner com:"
echo "   sudo tail -n 50 $LOG_PATH"
```

---

## 7. Padrões Avançados de Arquitetura de Dados, LGPD & Integração Física

### ⚡ 7.1. Staging Area Soberana (Proteção contra Rate-Limits HTTP 429)
Para evitar que o motor de automação (n8n) ou a malha de IA (LiteLLM/Open WebUI) estoure os limites de requisições de APIs externas (ex: limite de 100 req/min da Loja Integrada, retornando erro HTTP 429 / Err 633), o **daemind.** adota o padrão de **Staging Area Soberana**:
- **Réplica Local no PostgreSQL:** As tabelas `catalogo`, `clientes`, `pedidos` e `insumos` funcionam como uma réplica local atualizada assincronamente por webhooks de entrada.
- **Consultas em Milissegundos:** A IA e os robôs de atendimento realizam pesquisas e consultas diretamente na réplica local no Postgres, reduzindo a latência a milissegundos e eliminando requisições síncronas para plataformas remotas durante chamadas no WhatsApp.

### 🧬 7.2. Isolamento Relacional vs. Base Vetorial (`pgvector`)
Para garantir tempos de resposta de consulta otimizados e evitar inchaço no banco de dados:
- **Tabelas Relacionais Tipadas (`catalogo`, `pedidos`):** Armazenam dados estruturados (SKU, preço, saldo de estoque, status de entrega).
- **Tabela de Conhecimento Vetorial (`base_conhecimento`):** Armazena embeddings vetoriais via `pgvector` destinados estritamente a pesquisas semânticas RAG.
- **Governança RAG:** Documentações técnicas de desenvolvimento ou chaves internas são marcadas com a tag `dev_reference` e completamente omitidas do contexto do agente conversacional de vendas do WhatsApp.

### 📜 7.3. Privacy-by-Design & Conformidade Nativa LGPD
- **Protocolo de Opt-Out Automático:** O n8n intercepta mensagens de recusa (`"Parar"`, `"Sair"`, `"Cancelar"`) enviadas por clientes no WhatsApp/Evolution API e executa uma rotina SQL de expurgo imediato dos dados pessoais sensíveis (PII) no PostgreSQL.
- **Higienização de Inatividade (Sanitização Gradual de Leads):** Leads inativos por mais de 30 dias sofrem um procedimento de `UPDATE` parcial que deleta colunas com PII de pessoas físicas (telefone direto, e-mail pessoal, mensagens brutas), preservando unicamente dados cadastrais públicos PJ (CNPJ, CNAE) para auditoria e inteligência comercial B2B.

### 📦 7.4. Interface Físico-Digital com Hardware HID (Leitor de Código de Barras USB)
- Para balcões de expedição e controle físico de estoque, o NocoDB fornece Views configuradas com `Autofocus` na célula de SKU.
- O leitor de código de barras USB (Hardware HID que emula digitação + `Enter`) digita o código lido instantaneamente no campo focado, permitindo baixa de estoque e acionamento de fluxos de separação no n8n sem toque no mouse ou teclado.

### 🔄 7.5. Deduplicação por Hash de Payload SHA-256 (n8n Webhook Fallback)
- **Mitigação de Retentativas Indevidas:** Quando a infraestrutura externa reenviar webhooks modificando metadados como `event_id`, a primeira etapa do workflow do n8n executa uma função JavaScript (*Code Node*) que gera o `dedup_hash` (SHA-256 do corpo do payload + `LOJA_APP_KEY`).
- **Validação com TTL de 5 Minutos:** O n8n registra o hash com expiração automática de 5 minutos. Se o mesmo hash colidir dentro dessa janela, o fluxo responde HTTP 200 e interrompe o processamento redundante.

---

### 💡 Resumo do Veredito SRE

A arquitetura do **daemind.** exemplifica uma abordagem industrial de **Infraestrutura como Código (IaC)** e **Engenharia de Confiabilidade de Sistemas (SRE)**. O ecossistema foi projetado não apenas para funcionar em condições ideais, mas para **isolar falhas, autocurar serviços, preservar recursos de hardware e garantir blindagem total de dados** em ambientes de produção.
