# ⚙️ Engenharia de Resiliência, Arquitetura SRE e Tunings de Performance — daemind.

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
  - [3.4. Sincronização de Relógio Atômica & Auto-Healing de DNS do Host](#34-sincronização-de-relógio-atômica--auto-healing-de-dns-do-host)
  - [3.5. Motor Autônomo & Desacoplado de Auto-Tuning de Hardware (`core/scripts/autotune.sh`)](#35-motor-autônomo--desacoplado-de-auto-tuning-de-hardware-corescriptsautotunesh)
  - [3.6. Cronômetro SRE de Latência com Pausa Interativa de Wizard](#36-cronômetro-sre-de-latência-com-pausa-interativa-de-wizard)
  - [3.7. Banner Executivo Dinâmico no Login SSH (`/etc/update-motd.d/99-sre-banner`)](#37-banner-executivo-dinâmico-no-login-ssh-etcupdate-motdd99-sre-banner)
  - [3.8. Fixação Determinística de IP Estático via Netplan (`/etc/netplan/99-static-sre.yaml`)](#38-fixação-determinística-de-ip-estático-via-netplan-etcnetplan99-static-sreyaml)
- [4. Arquitetura da Malha de Contêineres & Tunings por Serviço](#4-arquitetura-da-malha-de-contêineres--tunings-por-serviço)
  - [4.1. PostgreSQL 17 + PGVector + PgBouncer (Transaction Pooling)](#41-postgresql-17--pgvector--pgbouncer-transaction-pooling)
  - [4.2. Chatwoot Omnichannel & Compilação Ruby YJIT](#42-chatwoot-omnichannel--compilação-ruby-yjit)
  - [4.3. Motor de Automação n8n & Hardening de Memória](#43-motor-de-automação-n8n--hardening-de-memória)
  - [4.4. Malha de IA: LiteLLM Gateway & Open WebUI RAG Compaction](#44-malha-de-ia-litellm-gateway--open-webui-rag-compaction)
  - [4.5. Postiz Social Planner & Orquestrador Temporal](#45-postiz-social-planner--orquestrador-temporal)
  - [4.6. Desacoplamento Modular de Armazenamento (Local, MinIO S3 ou Cloud S3)](#46-desacoplamento-modular-de-armazenamento-local-minio-s3-ou-cloud-s3)
  - [4.7. Contrato de Interface Polimórfico dos Scripts Modulares (`install_<modulo>.sh`)](#47-contrato-de-interface-polimórfico-dos-scripts-modulares-install_modulosh)
  - [4.8. Gateway de Borda Caddy WAF & ACME Automático](#48-gateway-de-borda-caddy-waf--acme-automático)
  - [4.9. Paridade de Fuso Horário e Alocação Dinâmica de IPs na Rede Privada](#49-paridade-de-fuso-horário-e-alocação-dinâmica-de-ips-na-rede-privada)
  - [4.10. Matriz Dinâmica de Versões e Imagens Docker (SRE BOM)](#410-matriz-dinâmica-de-versões-e-imagens-docker-sre-bom)
- [5. Gestão de Segredos & Sanitização em Memória (Zero Leakage)](#5-gestão-de-segredos--sanitização-em-memória-zero-leakage)
- [6. Idempotência, Traps Forenses & Observabilidade SRE](#6-idempotência-traps-forenses--observabilidade-sre)
  - [6.1. Cobertura Forense Transversal (`set -eEo pipefail`)](#61-cobertura-forense-transversal-set--eeo-pipefail)
  - [6.2. Log Stream Redirection](#62-log-stream-redirection)
  - [6.3. Protocolo Autônomo de Inspeção de Logs no Host](#63-protocolo-autônomo-de-inspeção-de-logs-no-host)
  - [6.4. Motor de Sincronização Inteligente de Modelos de IA (`install_1ia.sh`)](#64-motor-de-sincronização-inteligente-de-modelos-de-ia-install_1iash)
  - [6.5. Disaster Recovery, Backup Criptografado & Restauração (`backup_diario.sh` e `restore_production.sh`)](#65-disaster-recovery-backup-criptografado--restauração-backup_diariosh-e-restore_productionsh)
  - [6.6. Atualização Remota Declarativa da Stack (`upgrade_stack.sh`)](#66-atualização-remota-declarativa-da-stack-upgrade_stacksh)
  - [6.7. Bateria de Testes de Fumaça & Recuperação Perimetral (`ci_smoke_test.sh` e `install_0ts.sh`)](#67-bateria-de-testes-de-fumaça--recuperação-perimetral-ci_smoke_testsh-e-install_0tssh)
- [7. Padrões Avançados de Arquitetura de Dados, LGPD & Integração Física](#7-padrões-avançados-de-arquitetura-de-dados-lgpd--integração-física)

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

### 🖥️ 2.2. Motor de Frontend Dialog TUI, Dual-Mode CLI & Motor SSOT Unificado
Para aliar ergonomia visual de nível industrial com robustez e determinismo em pipelines de automação, o instalador implementa uma **Máquina de Estados de Interface Dual** operando sobre um **Motor SSOT (*Single Source of Truth*) Unificado**:

1. **Modo Gráfico Dialog TUI (Padrão)**:
   - Baseado no utilitário de terminal `dialog` com tema corporativo SRE de alto contraste (Ciano, Azul e Preto).
   - Componentes enriquecidos: `--msgbox` (Apresentação), `--mixedform` (Identidade e Credenciais com máscaras de segurança), `--radiolist` (Topologia e Storage), `--checklist` (Seleção de Microsserviços e Provedores de IA) e botões de navegação bidirecional `<Avançar>` / `<Voltar>`.
   - Gerenciamento de foco inteligente (`--default-button "ok"` quando há reaproveitamento de cache) para permitir avanço ágil com `[Enter]`.
   - **Navegação Bidirecional Resiliente:** Máquina de estados interna nos scripts especialistas (`install_0ts.sh`, `install_s3minio.sh`, `install_1ia.sh`) com suporte integral a retorno de subtelas sem corrupção ou perda de dados preenchidos.

2. **Modo Terminal Clássico (CLI Headless via `--cli`)**:
   - Ativado automaticamente quando detectado ambiente não-interativo (`DEBIAN_FRONTEND=noninteractive` ou ausência de TTY) ou via parâmetro `--cli`.
   - Coleta sequencial assistida no terminal padrão com validação estrita por expressões regulares e captura segura de caracteres mascarados.

3. **Motor SSOT Unificado (Single Source of Truth Engine)**:
   - Ambas as interfaces (TUI e CLI) alimentam o mesmo arquivo temporário de cache em `~/.daemind_wizard_cache_<empresa>.env` (`save_wizard_cache`).
   - Na **Fase 3 do `preinstall.sh`**, o motor compila a base determinística de rede (`IP_NETWORK_SUBNET`, IPs sequenciais dos nós via Linha 2 dos scripts) e delega a injeção de variáveis para a função padronizada `build_envs()` de cada script desacoplado.
   - Aplica a rotina de **State Harmonization** no final do arquivo com prioridade máxima (*last-write-wins*), garantindo paridade absoluta no `${TARGET_DIR}/.env` oficial (`chmod 600`) para consumo do `install.sh`.

---

### 📋 2.2.1. Matriz Oficial de Variáveis de Ambiente, Parâmetros e Governança SSOT

A tabela a seguir padroniza integralmente as variáveis suportadas tanto na esteira Headless/CI quanto nas telas interativas do Wizard TUI:

#### 1. 🚀 Variáveis de Execução, Fluxo & Cache (Bootstrap)
| Variável | Opções / Formato | Descrição |
| :--- | :--- | :--- |
| `TARGET_BRANCH` | `main`, `test`, `dev` *(default: main)* | Branch do repositório Git a ser clonada/utilizada |
| `WIZARD_CACHE_NAME` | String simples *(ex: minio, s3_external, loja1)* | Sufixo customizado do arquivo de cache (`.daemind_wizard_cache_<nome>.env`) |
| `AUTO_REUSE_CACHE` | `s` / `n` *(default: s na CLI se existir cache)* | Se `s`, reutiliza respostas salvas sem perguntar interativamente |
| `FORCE_NEW_INSTALL` | `s` / `n` *(default: n)* | Força limpeza de containers/volumes antigos ignorando locks de proteção |
| `EXECUTAR_INSTALL` | `s` / `n` *(default: s)* | Determina se dispara o `install.sh` ao término do `preinstall.sh` |
| `OVERRIDE_TOTAL_CPUS` | Inteiro *(ex: 4, 8)* | Sobrescreve a detecção de hardware (CPUs) para dimensionamento de limites |
| `OVERRIDE_TOTAL_RAM_GB` | Inteiro *(ex: 8, 16)* | Sobrescreve a detecção de hardware (RAM em GB) para dimensionamento de limites |

#### 2. 👤 Identificação do Cliente, Instância & Senhas Base
| Variável | Opções / Formato | Descrição |
| :--- | :--- | :--- |
| `EMPRESA` | `loja1`, `acme` *(sem espaços/especiais, max 12 chars)* | Identificador único da empresa (prefixo de containers/redes/volumes) |
| `CLIENTE_NOME` | String *(ex: Well)* | Primeiro nome do administrador |
| `CLIENTE_SOBRENOME` | String *(ex: Alcantara)* | Sobrenome do administrador |
| `CLIENTE_EMAIL` | `email@dominio.com` | E-mail corporativo principal (usado em SSL, admin do Chatwoot/n8n/NocoDB) |
| `DB_PASSWORD` | String forte *(8-12 chars, 1 maiúsc., 1 núm., esp. seguros)* | Senha mestra do PostgreSQL, Redis e MinIO |
| `DB_PASSWORD2` | Mesma que `DB_PASSWORD` | Confirmação da senha mestra |

#### 3. 🌐 Rede, Borda, Roteamento & Acesso (Tailscale vs BYODNS)
| Variável | Opções / Formato | Descrição |
| :--- | :--- | :--- |
| `ROUTING_CHOICE` | `1` (Tailscale VPN) ou `2` (BYODNS / Domínio Próprio) | Modelo de exposição da infraestrutura |
| `USE_TAILSCALE` | `true` ou `false` | Se ativo, sobe container perimetral Tailscale |
| `TS_OAUTH_ID` | `kXXXXXXXXXX` | OAuth Client ID do Tailscale *(Obrigatório se ROUTING_CHOICE=1)* |
| `TS_OAUTH_SECRET` | `tskey-client-XXXXX` | OAuth Client Secret do Tailscale *(Obrigatório se ROUTING_CHOICE=1)* |
| `CUSTOM_DOMAIN` | `painel.suaempresa.com.br` | Domínio do Painel Mestre / Caddy *(Obrigatório se ROUTING_CHOICE=2)* |
| `CUSTOM_EVO_DOMAIN` | `api.suaempresa.com.br` | Domínio da API WhatsApp / Webhooks *(Obrigatório se ROUTING_CHOICE=2)* |
| `CADDY_PROTOCOL` | `https` *(default)* ou `http` | Protocolo para emissão de certificados ou proxy reverso |
| `TLS_CHOICE` | `1` (Offload / HTTP) ou `2` (Caddy SSL Nativo / HTTPS) | Tratamento TLS do Caddy (usado na CLI) |
| `REDE_CHOICE` | `1`, `2`, `3` ou `4` | Escolha do CIDR Docker Privado |
| `BASE_IP` | `172.25.0`, `10.50.0`, `192.168.200` ou custom | Faixa IP das pontes internas Docker |

#### 4. 🧩 Módulos e Aplicações Desacopladas (`USE_*`)
*Todas aceitam `s` (instalar/ativo) ou `n` (não instalar/desativar):*
| Variável | Opções / Formato | Descrição |
| :--- | :--- | :--- |
| `USE_CHATWOOT` | `s` / `n` | Chatwoot CRM (Atendimento Omnichannel Multiatendente) |
| `USE_EVOLUTION` | `s` / `n` | Evolution API (Gateway WhatsApp / Baileys Webhooks) |
| `USE_N8N` | `s` / `n` | n8n (Orquestrador & Automação de Workflows Ilimitados) |
| `USE_NOCODB` | `s` / `n` | NocoDB (Smart Database & Interface Relacional/ERP) |
| `USE_OPENWEBUI` | `s` / `n` | Open WebUI (Interface Web de IA Corporativa & MCP) |
| `USE_POSTIZ` | `s` / `n` | Postiz (Agendador & Publicador de Mídias Sociais) |
| `USE_METABASE` | `s` / `n` | Metabase (Painéis & Dashboards Analíticos em Tempo Real) |
| `USE_OLLAMA` | `s` / `n` *(Requer >4 vCPUs e >=16GB RAM)* | Ollama (Inferência Local de Modelos Soberanos / LLMs) |
| `USE_DOCLING` | `s` / `n` *(Requer >4 vCPUs e >=16GB RAM)* | Docling (OCR & Parser Avançado de Documentos/PDFs por IA) |
| `USE_S3MINIO` | `s` / `n` | Controlado dinamicamente pelo `STORAGE_MODE` |

#### 5. 💾 Armazenamento de Objetos (Storage: Local vs MinIO vs S3 Externo)
| Variável | Opções / Formato | Descrição |
| :--- | :--- | :--- |
| `OPT_STORAGE` | `1` (Local), `2` (MinIO On-Premise), `3` (S3 Externo) | Seletor numérico de storage |
| `STORAGE_MODE` | `local`, `s3minio` ou `s3_external` | Modo operacional de armazenamento |
| `S3_ENDPOINT_EXT` | `https://<account-id>.r2.cloudflarestorage.com` | Endpoint do provedor S3 *(se STORAGE_MODE=s3_external)* |
| `S3_REGION_EXT` | `us-east-1` *(default)*, `auto`, `sa-east-1`, etc. | Região do bucket S3 |
| `S3_ACCESS_KEY_EXT` | String | Access Key ID / Client ID do S3 |
| `S3_SECRET_KEY_EXT` | String | Secret Access Key do S3 |
| `S3_CHATWOOT_BUCKET_EXT` | String *(default: chatwoot)* | Nome do bucket para mídia do Chatwoot |
| `S3_POSTIZ_BUCKET_EXT` | String *(default: postiz)* | Nome do bucket para vídeos/fotos do Postiz |
| `S3_EVOLUTION_BUCKET_EXT` | String *(default: evolution)* | Nome do bucket para áudios/mídias do WhatsApp |
| `S3_NOCODB_BUCKET_EXT` | String *(default: nocodb)* | Nome do bucket para anexos do NocoDB |

#### 6. 🤖 Inteligência Artificial (LiteLLM & Gateways)
| Variável | Opções / Formato | Descrição |
| :--- | :--- | :--- |
| `OPENROUTER_API_KEY` | `sk-or-v1-...` | **Obrigatória:** Chave do OpenRouter (Gateway Universal de IA) |
| `FREE_GEMINI` | `1` ou `0` | `1` se usar Google Gemini Gratuito (Flash/Gemma) |
| `RESP_GEMINI_FREE` | `s` ou `n` | Flag auxiliar de sincronia para modo Free do Gemini |
| `GEMINI_API_KEY` | `AIzaSy...` ou `AQ...` | Chave do Google AI Studio / Gemini |
| `OPENAI_API_KEY` | `sk-proj-...` | Chave de API da OpenAI (ChatGPT / GPT-4o) |
| `ANTHROPIC_API_KEY` | `sk-ant-...` | Chave de API da Anthropic (Claude 3.5 Sonnet) |
| `DEEPSEEK_API_KEY` | `sk-...` | Chave de API da DeepSeek (DeepSeek V3 / R1) |
| `RESP_PAGA` | `s` / `n` | Flag CLI: Pergunta se deseja provedores pagos além do OpenRouter |

---

### ⌨️ 2.3. Captura Criptográfica de Keystrokes via Raw TTY (Modo CLI)
Para a captura de senhas sensíveis no modo CLI, o script **despreza o comando genérico `read -s`** (que não exibe nenhum feedback visual ao operador e pode vazar buffer). É utilizado um loop de interceptação de caracteres char-a-char via TTY nativo:


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

### 🌐 3.4. Sincronização de Relógio Atômica & Auto-Healing de DNS do Host
- **Auto-Healing de DNS (`systemd-resolved` & Resolvers de Contingência):** O `preinstall.sh` e o `install.sh` monitoram a resolução de nomes via `getent hosts github.com`. Caso o StubListener ou o daemon de DNS oscile durante o provisionamento, o sistema reativa o resolver local e injeta resolvers de contingência (`8.8.8.8` e `1.1.1.1`) provisoriamente em `/etc/resolv.conf`, prevenindo falhas de download do Git ou Docker Hub.
- **Persistência de Horário Oficial (NTP + Hardware Clock):** Sincronização de tempo com o pool oficial brasileiro (`a.st1.ntp.br`, `b.st1.ntp.br`) via `systemd-timesyncd` e gravação direta na BIOS do servidor através de `hwclock --systohc`.

---

### ⚙️ 3.5. Motor de Auto-Tuning de Hardware & Descentralização nos Módulos (`autotune.sh` & `build_envs`)
Para permitir o desacoplamento e o escalonamento autônomo dos microsserviços sem engessamento ou ponto único de falha:

1. **Extração Universal de Hardware (`core/scripts/autotune.sh`):** Módulo SRE focado na descoberta pura de hardware do Host (`SYSTEM_TOTAL_CPUS`, `SYSTEM_TOTAL_RAM_MB`, `SYSTEM_TOTAL_DISK_GB`, `IS_MODEST_SERVER`).
2. **Dimensionamento do Núcleo Core (`core/scripts/autotune.sh`):** Dimensiona exclusivamente a infraestrutura de dados base e borda obrigatória (Postgres 17, PgBouncer, Redis 8, Caddy WAF e LiteLLM Gateway), ajustando buffers (`shared_buffers`, `work_mem`), evicção de memória do Redis (`maxmemory`), workers do LiteLLM e limites de CPU/RAM do Core.
3. **Dimensionamento Descentralizado por Módulo (`install_<modulo>.sh -> build_envs`):** Cada script de módulo é soberano e dono do seu próprio dimensionamento. Na execução de `build_envs()`, a aplicação avalia as métricas de hardware exportadas e injeta suas próprias variáveis de limites (`CPU_*`, `MEM_*`, `RES_*`, concorrência web/sidekiq, JVM/Node Heaps) no arquivo `.env` de forma 100% autônoma.
4. **Consumo no Docker Compose:** Todos os manifestos consom as variáveis dinâmicas com fallbacks seguros `${VAR:-DEFAULT}`, garantindo idempotência e execução perfeita em instâncias modestas de 4GB até servidores dedicados de 64GB+.

---

### ⏱️ 3.6. Cronômetro SRE de Latência com Pausa Interativa de Wizard
Para gerar métricas de latência de deploy fiéis e auditáveis:
- O cronômetro congela o contador durante perguntas interativas que aguardam digitação do operador (`pausar_cronometro` / `retomar_cronometro`).
- Ao final, o relatório SRE discrimina a **duração líquida real de processamento** do **tempo total decorrido com pausas humanas**, permitindo benchmarks precisos de I/O de disco e velocidade de rede do provedor.

---

### 🖥️ 3.7. Banner Executivo Dinâmico no Login SSH (`/etc/update-motd.d/99-sre-banner`)
- Desativação de scripts verbosos padrão do Ubuntu em `/etc/update-motd.d/*`.
- Injeção de painel executivo dinâmico que renderiza em tempo real: Sistema Operacional, Kernel, usuário logado, FQDN canônico, IP da interface de rede, modelo da CPU, total de vCPUs, RAM total/usada, Swap e taxa de ocupação da partição raiz (`/`).

---

### 🔌 3.8. Fixação Determinística de IP Estático via Netplan (`/etc/netplan/99-static-sre.yaml`)
- Para evitar a perda de conexão em servidores onde a concessão de DHCP expira ou varia, o `preinstall.sh` descobre a interface física padrão, IP, Gateway e MAC Address atribuídos e gera uma configuração declarativa estática protegida com permissão `600` via `netplan` (`renderer: networkd`).

---

## 4. Arquitetura da Malha de Contêineres & Tunings por Serviço

### 🐘 4.1. PostgreSQL 17 + PGVector + PgBouncer (Transaction Pooling)
A camada transacional do banco de dados opera com multiplexação obrigatória:

```mermaid
graph TD
    ClientApps[Contêineres: n8n, Evolution, Chatwoot, NocoDB, LiteLLM, Open WebUI] -->|Conexões Concorrentes Port 6432| PgBouncer[PgBouncer Pooler - Transaction Mode]
    PgBouncer -->|Pool Controlado Max 250 Conexões Port 5432| Postgres[PostgreSQL 17 + PGVector]
```

- **PostgreSQL 17:**
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

### 🗄️ 4.6. Desacoplamento Modular de Armazenamento (Local, MinIO S3 ou Cloud S3)
A infraestrutura implementa a especificação de **Armazenamento Desacoplado Plugável (BYOS - Bring Your Own Storage)** com profilamento automático de hardware via motor `autotune.sh` para os módulos consumidores de mídias/anexos (**Chatwoot**, **Evolution API**, **NocoDB** e o volume local de mídia do **Postiz**):
- **Modo 1 - Armazenamento Local Direto (Custo/Recurso Otimizado):** Recomendado automaticamente para hosts modestos (< 4 Cores vCPU ou < 8GB RAM). Redireciona o armazenamento de anexos e mídias para volumes isolados no disco do servidor (`./volumes/storage_data/chatwoot`, `./volumes/storage_data/postiz`, `./volumes/evolution_instances` e `./volumes/nocodb_data`), reduzindo o consumo de memória RAM em ~1 GB ao desativar o contêiner do MinIO.
- **Modo 2 - MinIO S3 Soberano (`${PREFIXO_CONTAINER}_s3minio`):** Ativado em servidores de alta performance (>= 4 Cores e >= 8GB RAM). Executa o contêiner isolado do MinIO via *Compose Override* (`docker-compose.s3minio.yml`) gerenciado por `install_s3minio.sh` nas portas `9000` (S3 API) e `9001` (Console UI), fornecendo compressão de disco (`MINIO_COMPRESS=on`) e gerenciamento centralizado com buckets dedicados (`chatwoot`, `evolution` e `nocodb`). O Postiz opera de forma resiliente em seu volume local persistente (`/app/uploads`).
- **Modo 3 - Provedor S3 Cloud Remoto (BYOS):** Conecta a stack a provedores externos de S3 (AWS S3, Cloudflare R2, DigitalOcean Spaces) injetando as credenciais e endpoints remotos diretamente no barramento de variáveis dos serviços compatíveis.
- **Criação de Pastas e Buckets Otimizada:** As pastas físicas em disco são criadas de forma segura e idempotente para cada serviço ativo (`USE_CHATWOOT=s`, `USE_POSTIZ=s`, `USE_EVOLUTION=s`, `USE_NOCODB=s`). Em modo S3 Externo, o provisionamento de buckets remotos é executado automaticamente via AWS CLI.
- **Manipulador Dinâmico de Overlays YAML (`docker-compose.s3minio.yml`):** Os blocos de sobreposição dos módulos no MinIO ficam encapsulados em comentários delimitadores (`# --- INJEÇÃO DECLARATIVA NATIVA NO <MODULO> QUANDO S3MINIO ESTÁ ATIVO ---`). A função `build_structure()` ativa (descomenta) ou mantém desativado (comentado) cada bloco no YAML conforme `USE_<MODULO>`, impedindo a criação de dependências órfãs na stack final.

---

### 🧩 4.7. Contrato de Interface Polimórfico dos Scripts Modulares (`install_<modulo>.sh`)
Para garantir 100% de desacoplamento e iterabilidade genérica tanto no `preinstall.sh` quanto no `install.sh`, cada módulo desacoplado (`install_0ts.sh`, `install_1ia.sh`, `install_n8n.sh`, `install_openwebui.sh`, `install_s3minio.sh`, `install_evolution.sh`, `install_postiz.sh`, `install_chatwoot.sh`, `install_nocodb.sh`, `install_metabase.sh`, `install_ollama.sh`, `install_docling.sh`) expõe rigorosamente a mesma interface pública de 15 funções sem prefixos específicos:

| Nº | Função Padronizada | Descrição de Engenharia SRE |
| :---: | :--- | :--- |
| **1** | `collect_wizard_inputs` | Coleta interativa de perguntas no Wizard CLI do `preinstall.sh`, integrada à persistência no Wizard Cache. |
| **2** | `build_envs` | Injeção polimórfica de variáveis de ambiente e sizing no `.env` SSOT. |
| **3** | `build_structure` | Estrutura pré-boot de volumes físicos e permissões (`chown`/`chmod`/`stat`), além de manipuladores dinâmicos de overlays YAML. |
| **4** | `provision_db` | Criação idempotente de bancos lógicos e schemas relacionais no PostgreSQL antes da subida da malha. |
| **5** | `provision_infra` | Hardening e pós-boot: injeção de firewall de porta no `DOCKER-USER` (via `${IP_NETWORK_SUBNET}`), geração de regras de DNS/IPSet em `/etc/dnsmasq.d/<modulo>.conf` e DDLs. |
| **6** | `inject_caddy_routes` | Injeção das portas do serviço no `Caddyfile`. |
| **7** | `remove_caddy_routes` | Purga cirúrgica das rotas do `Caddyfile`. |
| **8** | `inject_dashboard_card` | Injeção de Card visual no `index.html` em modo `r+` preservando Inode. |
| **9** | `remove_dashboard_card` | Remoção do Card visual do `index.html`. |
| **10** | `disable` | Teardown atômico (destrói container, remove rotas Caddy, purga cards e remove `/etc/dnsmasq.d/<modulo>.conf`). |
| **11** | `start_container` | Subida atômica do container via Docker Compose. |
| **12** | `wait_readiness` | Probe de prontidão com **Graceful Degradation** (não bloqueia a esteira caso um módulo secundário demore para responder). |
| **13** | `audit_health` | Validação de saúde HTTP/TCP e handshake da aplicação. |
| **14** | `get_version` | Inspeção de versão do container em tempo de execução. |
| **15** | `provision_user` | Automação e cadastro do usuário administrador mestre. |
| *(Aux)* | `render_forensic_report` | Impressão do bloco de credenciais/endpoints no console. |

---

### 🔒 4.8. Gateway de Borda Caddy WAF & ACME Automático
- **Caddy (`caddy`):** Atua como Reverse Proxy, Firewall WAF e emissor automático de certificados SSL/TLS via Let's Encrypt (modo BYODNS) ou suporte a VPN Tailscale.
- Serve páginas estáticas e favicons nativamente da memória com regras de cache agressivas.

---

### 🌍 4.9. Paridade de Fuso Horário e Alocação Dinâmica de IPs na Rede Privada
- **Fuso Horário Unificado:** Todos os contêineres realizam montagem de volume somente-leitura do relógio do host:
  ```yaml
  volumes:
    - '/etc/timezone:/etc/timezone:ro'
    - '/etc/localtime:/etc/localtime:ro'
  ```
- **Topologia de Rede Privada com Descoberta Autônoma (Zero Hardcode):** Toda a comunicação entre microsserviços utiliza endereçamento IPv4 fixo na rede bridge interna (`instancia_net`), eliminando overhead e latência de resolução DNS. A esteira aplica um algoritmo determinístico de alocação:
  1. **Faixa Fixa do Núcleo Core (`.1` a `.6`):**
     - Gateway (`.1`), Postgres (`.2`), PgBouncer (`.3`), Redis (`.4`), Caddy (`.5`), LiteLLM (`.6`).
  2. **Faixa Dinâmica dos Módulos Desacoplados (`.7+`):**
     - O provisionador escaneia os scripts `core/scripts/install_<modulo>.sh` em ordem alfabética e lê a **Linha 2** de cada arquivo (onde os nós são declarados como metadados, ex: `# CHATWOOT` ou `# POSTIZ TEMPORAL`).
     - Cada nó recebe sequencialmente um IP parametrizado (`${IP_CHATWOOT}="172.25.0.7"`, `${IP_EVOLUTION}="172.25.0.8"`, etc.), garantindo que novos módulos sejam adicionados sem alteração manual no orquestrador principal.

---

### 📦 4.10. Matriz Dinâmica de Versões e Imagens Docker (SRE BOM)
A infraestrutura do **daemind.** opera com a matriz de imagens e versões auditadas em tempo de execução pelo pipeline de SRE (**SRE BOM - Bill of Materials**). As versões internas são extraídas dinamicamente via `docker inspect` e runtime do sistema (sendo `${PREFIXO_CONTAINER}` o prefixo dinâmico escolhido no wizard pelo usuário):

| Container | Imagem Docker | Tag no Compose | Versão Interna Auditada | Função na Stack |
| :--- | :--- | :--- | :--- | :--- |
| `${PREFIXO_CONTAINER}_postgres` | `pgvector/pgvector` | `pg17` | **17.11** | Banco de Dados Relacional & Vetorial |
| `${PREFIXO_CONTAINER}_pgbouncer` | `edoburu/pgbouncer` | `v1.25.2-p0` | **1.25.2-p0** | Multiplexador de Conexões Postgres |
| `${PREFIXO_CONTAINER}_caddy` | `caddy` | `2.11.4-alpine` | **2.11.4** | Reverse Proxy & WAF com SSL Automático |
| `${PREFIXO_CONTAINER}_redis` | `redis` | `8.10-alpine` | **8.10.0** | Cache & Fila de Automações em Memória |
| `${PREFIXO_CONTAINER}_litellm` | `ghcr.io/berriai/litellm` | `main-latest` *(dinâmica)* | **1.98.0** | Gateway & Roteador de Modelos de IA |
| `${PREFIXO_CONTAINER}_s3minio` | `alpine/minio` | `latest-release` *(dinâmica)* | **2025-10-25** | Armazenamento S3 Soberano *(Módulo Opcional Desacoplado)* |
| `${PREFIXO_CONTAINER}_metabase` | `metabase/metabase` | `latest` *(dinâmica)* | **0.63.13** | Painéis e Dashboards de BI *(Módulo Opcional Desacoplado)* |
| `${PREFIXO_CONTAINER}_n8n` | `n8nio/n8n` | `2.34.6` | **2.34.6** | Motor de Automação de Processos *(Módulo Opcional Desacoplado)* |
| `${PREFIXO_CONTAINER}_temporal` | `temporalio/auto-setup` | `1.29.7` | **1.29.7** | Orquestrador de Workflows (Postiz) |
| `${PREFIXO_CONTAINER}_postiz` | `ghcr.io/gitroomhq/postiz-app` | `v2.23.0` | **2.23.0** | Agendador de Redes Sociais *(Módulo Opcional Desacoplado)* |
| `${PREFIXO_CONTAINER}_chatwoot` | `chatwoot/chatwoot` | `v4.16.2` | **4.16.2** | Inbox Omnichannel & Atendimento *(Módulo Opcional Desacoplado)* |
| `${PREFIXO_CONTAINER}_evolution` | `evoapicloud/evolution-api` | `v2.3.7` | **2.3.7** | API de Conexão WhatsApp *(Módulo Opcional Desacoplado)* |
| `${PREFIXO_CONTAINER}_nocodb` | `nocodb/nocodb` | `2026.08.0` | **2026.08.0** | CRM e Planilhas Inteligentes *(Módulo Opcional Desacoplado)* |
| `${PREFIXO_CONTAINER}_openwebui` | `ghcr.io/open-webui/open-webui` | `main` *(dinâmica)* | **0.11.0** | Interface Gráfica de IA *(Módulo Opcional Desacoplado)* |

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

O arquivo final `.env` em `/opt/daemind/.env` é gravado com permissão estrita `600` (`chmod 600`), acessível exclusivamente pelo usuário root.

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

### 🧠 6.4. Motor de Sincronização Inteligente de Modelos de IA (`install_1ia.sh`)
- **Varredura Atômica Multiprovedor (Big 5):** Consulta dinâmica das APIs oficiais (OpenAI, Anthropic, Google Gemini, DeepSeek e OpenRouter).
- **Matchmaking & Limpeza de Modelos Legados:** Algoritmo em `jq` que agrupa modelos por família canônica, identifica a versão mais recente em runtime, purga tags legadas ou descontinuadas e atualiza o banco de dados do LiteLLM via API interna (`/model/new`).
- **Sincronização Inter-Serviços (Postiz & Chatwoot):** Injeta o modelo atualizado no Chatwoot CRM via `rails runner` e no Postiz, mantendo paridade absoluta em toda a malha.

---

### 🛡️ 6.5. Disaster Recovery, Backup Criptografado & Restauração (`backup_diario.sh`, `install_0ts.sh` e `restore_production.sh`)
- **`backup_diario.sh` (Agendado via Cron às 23:00):**
  - **Sanity Check Prévio:** Executa dump com validação de saída.
  - **Backup de Identidade Perimetral Tailscale:** Empacota autonomamente a chave do nó e os certificados TLS Let's Encrypt em `~/tailscale_state_${PREFIXO_CONTAINER}_backup.tar.gz` (salvo exclusivamente na Home do usuário real com permissões `644`).
  - **Cifragem Assimétrica OpenPGP:** Criptografa o dump consolidado de todos os bancos (`${PREFIXO_CONTAINER}_db`, `chatwoot_db`, `postiz_db`, `temporal`, `nocodb_schema`, `litellm_db`, `openwebui_db`) usando a chave pública RSA 3072-bit do cliente.
  - **Rotação & Retenção:** Mantém os últimos 7 dias de backups criptografados em disco com purga automática de arquivos antigos.
- **Restauração Autônoma de Identidade Tailscale (`install_0ts.sh restore_identity`):**
  - Durante reinstalações ou migrações de host, o `install_0ts.sh` busca estritamente o arquivo `~/tailscale_state_${PREFIX}_backup.tar.gz`. Se encontrado, descompacta em `/var/lib/tailscale` e re-estabiliza o nó sem gerar novos dispositivos órfãos na Tailnet nem requerer novas chaves OAuth temporárias.
- **`restore_production.sh` (Restauração Assistida de Desastre):**
  - Solicitação interativa da Senha Mestra para descriptografia GPG via TTY.
  - Desmonte e reconstrução atômica dos esquemas e bancos de dados lógicos.
  - Restauração de mídias e volume persistente do Tailscale (`tailscale_state_*.tar.gz`), recuperando FQDN, certificados TLS e histórico de conversas em minutos.

---

### 🚀 6.6. Atualização Remota Declarativa da Stack (`upgrade_stack.sh`)
- Permite atualizar toda a infraestrutura sem perda de dados:
  - Sincronização atômica do repositório Git oficial.
  - Preservação estrita do arquivo `.env` (SSOT).
  - Execução de `docker compose pull` com retentativas automáticas e re-execução de migrações DDL pendentes.

---

### 🧪 6.7. Bateria de Testes de Fumaça & Recuperação Perimetral (`ci_smoke_test.sh` e `install_0ts.sh`)
- **`ci_smoke_test.sh`:** Suíte automatizada de validação pós-deploy que executa probes HTTP/HTTPS em todos os endpoints, testa portas internas (Postgres 5432, PgBouncer 6432, Redis 6379) e emite relatório com status de cada microsserviço.
- **`install_0ts.sh recovery`:** Utilitário de resgate perimetral que desliga túneis órfãos do Funnel, reseta o daemon `tailscaled`, reaplica a Auth Key do cliente e restabelece a exposição externa sem necessidade de reboot do host.

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
