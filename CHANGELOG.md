# CHANGELOG

## [v1.1.0] — (Em Desenvolvimento — Branch `test`)

> Expansão modular da stack com novos microsserviços soberanos, motor de auto-recuperação de rede Docker, auditoria proativa de IP Drift e eliminação total de acoplamentos hardcoded.

---

### 🧩 Novas Aplicações & Módulos Desacoplados

- **[ADD] Shlink + Shlink Web Client (`install_shlink.sh` + `docker-compose.shlink.yml`):**
  - Motor de encurtador de links soberano, QR Codes, analytics de cliques e atribuição de tags UTM.
  - Interface web moderna (`shlinkio/shlink-web-client`) desacoplada com gateway em porta dedicada `:8082` e API em `:8081`.
  - Persistência 100% nativa no PostgreSQL (`shlink_db`) e Redis da stack.
- **[ADD] Listmonk (`install_listmonk.sh` + `docker-compose.listmonk.yml`):**
  - Plataforma de e-mail marketing, newsletters e disparo transacional soberano de alta performance.
  - Banco relacional dedicado `listmonk_db`, isolamento perimetral de WAF e porta de borda `:9005`.
- **[ADD] Umami Analytics (`install_umami.sh` + `docker-compose.umami.yml`):**
  - Web analytics soberano, leve e 100% em conformidade com a LGPD/GDPR (cookieless).
  - Banco lógico dedicado `umami_db` e proxy reverso Caddy em porta `:3008`.
- **[REPLACE] WPPConnect Server (`install_wppconnect.sh` + `docker-compose.wppconnect.yml`):**
  - Substituição integral do antigo Evolution API pelo **WPPConnect Server (`latest`)**, eliminando o risco de estagnação de repositório.
  - Integração nativa e bidirecional com o **Chatwoot CRM** e webhooks em tempo real no **n8n** (`/webhook/wppconnect`).
  - Documentação Swagger integrada em `:18081/api-docs/` e gerenciamento de sessões com persistência local e cache em Redis.

---

### 🛡️ Engenharia SRE, Resiliência de Rede & Auto-Healing

- **[ADD] Auditoria Proativa de IP Drift (Zero-Touch Self-Healing):**
  - O `install.sh` inspeciona o IP de cada container em execução e compara com o `.env`. Contêineres rodando em IPs desalinhados são desanexados da rede e recriados automaticamente sem intervenção manual.
- **[ADD] Mitigação de Race Conditions no Docker (`Address already in use`):**
  - Desconexão atômica de endpoints com `docker network disconnect -f` antes de remoções forçadas (`docker rm -f`), liberando imediatamente a interface `veth` no kernel.
- **[ADD] Inversão de Controle Dinâmica (IoC) para Matriz de Versões (SRE BOM):**
  - Eliminação de `elif` hardcoded no core. O `install.sh` descobre dinamicamente os scripts responsáveis através da Linha 2 de cada `install_*.sh` e delega a extração de versões de forma polimórfica.
  - Suporte universal a labels OCI (`org.opencontainers.image.version` e `version`).
- **[ADD] Diretiva Máxima Universal de Zero Hardcode:**
  - Proibição absoluta de números de versão, portas ou IPs estáticos fixados em código.

---

## [v1.0.0] — 2026-08-18 — (DESACOPLAMENTO COMPLETO)

> Refatoração completa da arquitetura de provisionamento. A stack passa de um instalador monolítico com todos os serviços em um único `docker-compose.yml` e `install.sh` para um ecossistema desacoplado orientado a contratos.

---

### ⚙️ Arquitetura

- **[BREAKING]** `install.sh` reescrito do zero: o monólito foi desmontado em um orquestrador leve que descobre e mescla módulos dinamicamente.
- **[ADD]** Padrão de Contrato Desacoplado: cada serviço agora tem seu próprio `install_<módulo>.sh` com funções padronizadas (`build_envs`, `collect_wizard_inputs`, `inject_caddy_routes`, `inject_dashboard_card`, `start_container`, `disable`, etc.).
- **[ADD]** Composição dinâmica do `docker-compose.yml` via fusão sequencial de overlays (`docker-compose.<módulo>.yml`). O core define só a rede, Postgres, Redis e PgBouncer.
- **[REMOVE]** `docker-compose.yml` monolítico (todos os serviços num único arquivo) — substituído por 10 arquivos de overlay individuais.
- **[ADD]** `resolver_modulos_desacoplados()`: função que varre os `install_*.sh` e classifica dinamicamente cada módulo como ativo ou inativo com base nas flags `USE_*` do `.env`.

---

### 🧩 Novos Módulos Desacoplados

Cada um com script próprio, overlay compose, rotas Caddy e card do portal:

| Módulo | Arquivo | Status |
|--------|---------|--------|
| Tailscale VPN | `install_0ts.sh` | Novo |
| LiteLLM + IA Sync | `install_1ia.sh` | Novo |
| Chatwoot CRM | `install_chatwoot.sh` | Desacoplado |
| Docling OCR | `install_docling.sh` | **Novo** |
| WPPConnect Server | `install_wppconnect.sh` | **Substituição (Evolution)** |
| Metabase BI | `install_metabase.sh` | Desacoplado |
| n8n Automações | `install_n8n.sh` | Desacoplado |
| NocoDB | `install_nocodb.sh` | Desacoplado |
| Ollama LLM | `install_ollama.sh` | **Novo** |
| OpenWebUI | `install_openwebui.sh` | Desacoplado |
| Postiz | `install_postiz.sh` | Desacoplado |
| MinIO S3 | `install_s3minio.sh` | Desacoplado |

---

### 🧙 Wizard de Provisionamento (`preinstall.sh`)

- **[BREAKING]** `preinstall.sh` adicionado Wizard TUI interativo + modo CLI não-interativo.
- **[ADD]** Modo **TUI Dialog** (`dialog`): wizard gráfico em terminal com 6 passos (empresa, senha, módulos, rede, IA, confirmação).
- **[ADD]** Modo **CLI** (`USE_TUI=false`): fluxo headless para automação e CI/CD via variáveis de ambiente.
- **[ADD]** Detecção automática do modo: se `dialog` estiver instalado e o terminal for interativo → TUI; caso contrário → CLI.
- **[ADD]** Cache de wizard (`/tmp/.sre_wizard_cache`): respostas salvas entre sessões para acelerar re-deploys.
- **[ADD]** Seleção de microsserviços por checklist: o operador marca quais módulos deseja ativar/desativar em cada deploy.
- **[ADD]** Descoberta dinâmica de módulos: `BASE_MODS_LIST` construída varrendo os `install_*.sh` existentes, sem lista estática hardcoded.
- **[ADD]** Suporte a `OVERRIDE_TOTAL_CPUS` e `OVERRIDE_TOTAL_RAM_GB` para simular capacidade de hardware em testes.
- **[ADD]** Restrições de hardware por módulo: `is_hardware_supported()` em cada script (ex: Docling e Ollama exigem > 4 vCPUs e ≥ 16 GB RAM).
- **[FIX]** `build_envs` e `collect_wizard_inputs` agora são chamados via `bash` (subshell), corrigindo bug onde `source script arg` não propagava `$2` corretamente ao ACTION router dos módulos desacoplados — causa raiz de Docling e Ollama nunca serem instalados mesmo quando selecionados.

---

### 🛡️ Guardrails SRE

- **[ADD]** Guardrail de troca de tenant: detecta mudança de `EMPRESA` comparando com o `.env` existente em `/opt/daemind/`. Exige confirmação explícita; ao confirmar, executa `disable()` de todos os módulos desacoplados, `docker compose down -v`, `docker stop/rm` forçado de containers com prefixo do tenant anterior e remoção de volumes residuais.
- **[ADD]** Guardrail de credencial: bloqueia alteração de senha para um tenant já provisionado sem reset explícito.
- **[ADD]** Fallback `sudo cat` para leitura do `.env` existente quando o usuário corrente não tem permissão de leitura direta.
- **[ADD]** Mutex lock (`flock`) no `preinstall.sh` com autorepair de lock órfão.
- **[REMOVE]** Bloco destrutivo de fim do `install.sh` que apagava `install_<módulo>.sh` e `docker-compose.<módulo>.yml` dos módulos inativos — impedia reativação de módulos em reinstalações futuras.

---

### ⚡ Autotune (`autotune.sh`)

- **[BREAKING]** `autotune.sh` reescrito: de motor com lógica interna misturada a um motor modular com função `get_host_hardware()` exportável.
- **[REMOVE]** Suporte a `sync_ia_models.sh` embutido no `autotune.sh` (main tinha chamada interna).
- **[ADD]** Ação `get_hardware_info` / `get_hardware`: retorna apenas as métricas ao caller sem processar o `.env`, para uso pelo `preinstall.sh` antes de montar o wizard.
- **[ADD]** Respeito a `OVERRIDE_TOTAL_CPUS`, `OVERRIDE_TOTAL_RAM_GB`, `OVERRIDE_TOTAL_RAM_MB`: quando definidos, o autotune pula a validação de idempotência e recalcula o sizing completo com os valores forçados.
- **[FIX]** Idempotência agora ignora corretamente o cache quando `OVERRIDE_*` está ativo.

---

### 🗂️ State Harmonization (SSOT)

- **[ADD]** Bloco de State Harmonization no `preinstall.sh`: grava `USE_<MÓDULO>` com regra *last-write-wins* no `.env` após todos os `build_envs`, garantindo que a escolha do wizard sempre prevaleça sobre defaults internos dos módulos.
- **[ADD]** Bloco de State Harmonization no `install.sh`: re-persiste os flags de ativo/inativo no `.env` de runtime após a fusão do compose, para idempotência em re-runs do `install.sh`.
- **[ADD]** Invalida fases de checkpoint (`ENV_GENERATION`, `DOCKER_INFRA`) ao regenerar o `.env`, forçando reabsorção na próxima execução do `install.sh`.

---

### 🗃️ Scripts Adicionados

| Script | Finalidade |
|--------|-----------|
| `ci_smoke_test.sh` | Teste de fumaça pós-deploy para CI |
| `upgrade_stack.sh` | Upgrade controlado da stack com pull das imagens |
| `backup_diario.sh` | Backup automático (atualizado) |
| `restore_production.sh` | Restore de produção (atualizado) |

---

### 🗃️ Scripts Removidos

| Script | Motivo |
|--------|--------|
| `sync_ia_models.sh` | Incorporado ao módulo desacoplado `install_1ia.sh` |
| `ts_cleanup.sh` | Incorporado ao `install_0ts.sh` (disable/teardown) |
| `ts_recovery.sh` | Incorporado ao `install_0ts.sh` |

---

### 🌐 Portal de Controle (`index.html`)

- **[CHANGE]** `index.html` simplificado: o portal estático agora é gerado dinamicamente pelos `inject_dashboard_card()` de cada módulo ativo, eliminando cards hardcoded.
- **[REMOVE]** Cards fixos de todos os serviços do `index.html` da main — substituídos por injeção dinâmica.

---

## [v0.5.0] — 2026-08-06 — (PROVA DE CONCEITO)

> Versão inaugural do daemind. Instalador funcional, stack operacional, mas arquitetura ainda monolítica. Serviu como prova de conceito e validação do ecossistema antes da refatoração que originou a v1.0.0.

---

### ⚙️ Arquitetura

- `docker-compose.yml` único e monolítico contendo todos os serviços (Chatwoot, Evolution, n8n, Metabase, NocoDB, Postiz, MinIO, OpenWebUI, LiteLLM, Postgres, Redis, PgBouncer, Caddy).
- `install.sh` único tratando provisionamento, configuração de banco, injeção de rotas e health checks de todos os serviços num só arquivo de ~2000 linhas.
- `preinstall.sh` com fluxo CLI simples, sem TUI interativo e sem seleção granular de módulos.

---

### 🧩 Módulos Presentes (Hardcoded)

Todos os serviços provisionados incondicionalmente, sem flags de ativação/desativação:

- Chatwoot, Evolution API, n8n, Metabase, NocoDB, Postiz, MinIO S3, OpenWebUI, LiteLLM

> Ollama e Docling ausentes nesta versão.

---

### 🔧 Scripts Operacionais

| Script | Finalidade |
|--------|-----------|
| `autotune.sh` | Sizing de recursos (sem suporte a `OVERRIDE_*`) |
| `backup_diario.sh` | Backup automático diário |
| `restore_production.sh` | Restore a partir de backup |
| `sync_ia_models.sh` | Sincronização de modelos IA (script standalone) |
| `ts_cleanup.sh` | Limpeza manual do estado Tailscale |
| `ts_recovery.sh` | Recuperação de conectividade Tailscale |

---

### ⚠️ Limitações Conhecidas (resolvidas na v1.0.0)

- Sem seleção de módulos: toda a stack subia ou nada subia.
- Reinstalação destruía arquivos de módulos inativos, impedindo reativação futura.
- `preinstall.sh` sem modo TUI nem cache de respostas; cada re-deploy exigia reinserir todas as configurações.
- `autotune.sh` sem suporte a `OVERRIDE_TOTAL_CPUS` / `OVERRIDE_TOTAL_RAM_GB`.
- Sem guardrails de troca de tenant ou proteção de credenciais.
- Portal `index.html` com todos os cards hardcoded, independente do que estava ativo.
