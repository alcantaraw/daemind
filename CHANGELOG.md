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

---

### 🔗 Integrações Inter-Serviços & Data Warehouse Unificado

- **[ADD] Data Warehouse Soberano & Business Intelligence (Metabase + NocoDB via PgBouncer):**
  - **Federação Nativa Completa via `postgres_fdw`:** O banco centralizador `loja_db` integra em tempo real as bases de todos os 6 microsserviços da stack (`chatwoot_db`, `shlink_db`, `listmonk_db`, `umami_db`, `evolution_db`, `postiz_db`) em schemas isolados (`fdw_*`) sem duplicação de dados nem consumo extra de disco.
  - **7 Views Analíticas Executivas:** Provisionadas diretamente no `init.sql`:
    - `vw_kpi_atendimento`: Tempo médio de 1ª resposta, tempo de resolução e CSAT por atendente/canal (Chatwoot).
    - `vw_kpi_marketing_links`: Volume de cliques reais (anti-bot), UTMs, referrers e geolocalização (Shlink).
    - `vw_kpi_email_marketing`: Taxas de abertura (Open Rate), cliques (CTR) e crescimento de base (Listmonk).
    - `vw_kpi_trafego_web`: Visitantes únicos, pageviews, UTMs de campanhas e dispositivos (Umami).
    - `vw_kpi_whatsapp_disparos`: Volume de mensagens enviadas/recebidas, status de entrega, lidas e instâncias ativas (Evolution API).
    - `vw_kpi_redes_sociais`: Publicações agendadas vs postadas por plataforma social (Instagram, LinkedIn, etc.) (Postiz).
    - `vw_funil_executivo_completo`: Cruzamento ponta a ponta (Tráfego Web/Links ➔ Redes Sociais ➔ WhatsApp ➔ Leads Chatwoot ➔ Clientes Loja ➔ Pedidos/Faturamento).
  - **Auto-Conexão Zero-Touch:** Provisionamento automático da fonte de dados `Data Warehouse Soberano` no Metabase (`install_metabase.sh`) e auto-sincronização de metadados de Views no NocoDB (`install_nocodb.sh`).

- **[ADD] Template Executivo Auto-UTM no Listmonk (Shlink & Umami Ready):**
  - **Injeção Nativa de Atribuição:** Provisionamento automático do `Template Executivo Auto-UTM (Shlink & Umami)` diretamente no `listmonk_db`.
  - **Rastreabilidade Soberana:** Garante que qualquer campanha criada por operadores já possua URLs com tags de UTM formatadas (`utm_source=listmonk`, `utm_medium=email`, `utm_campaign={{ .Campaign.Name }}`), 100% integradas com o Shlink e Umami Analytics.
  - **100% Editável via Web:** O template fica disponível na interface do Listmonk (Campanhas ➔ Modelos), podendo ser personalizado visualmente (cores, logos, fontes e botões) a qualquer momento.

- **[ADD] Integração Plena de IA Local: Ollama ➔ LiteLLM ➔ OpenWebUI:**
  - **Auto-Discovery Dinâmico:** Os motores `sync_ia_models.sh` e `install_1ia.sh` inspecionam a API local do Ollama (`/api/tags`) e catalogam automaticamente novos modelos baixados (`ollama pull`) com quantização GGUF, tamanho em bilhões de parâmetros e tags.
  - **Roteamento Híbrido:** O LiteLLM roteia modelos locais para o container do Ollama via rede interna (`:11434`), permitindo chat 100% offline e sem custos.
  - **Polimento Visual OpenWebUI:** Remoção de prefixos redundantes de provedores, garantindo renderização limpa no dropdown do OpenWebUI sem truncamento com reticências.

- **[ADD] Padronização Global de Aliases de Rede RFC 1123 (Zero Underscore Error):**
  - **Conformidade DNS Universal:** Injeção explícita da propriedade `aliases` em todos os 14 arquivos `docker-compose*.yml` da stack (`instancia_net`), provendo nomes DNS canônicos e limpos (`s3minio`, `litellm`, `docling`, `postgres`, `pgbouncer`, `redis`, `n8n`, etc.).
  - **Mitigação em SDKs Estritos:** Elimina 100% de exceções de validação de hostname disparadas por bibliotecas que seguem estritamente as normas RFC 1123/952, como **`botocore`** (AWS SDK Python / Open WebUI), **AWS SDK v3** (Node/Go/Ruby) e parsers HTTP de URLs em endpoints internos com underline.

- **[ADD] Integração Plena de Storage S3 (MinIO Object Storage & S3 Remoto):**
  - **Storage Centralizado & Desacoplado:** Padronização e auto-criação de buckets dedicados com políticas de download anônimo e isolamento seguro:
    - `chatwoot`: Gravações, anexos e mídias de chamados.
    - `evolution`: Áudios, vídeos, imagens e documentos trafegados via WhatsApp.
    - `listmonk`: Imagens, banners de templates e mídias de campanhas de e-mail marketing com URLs públicas rápidas.
    - `postiz`: Uploads de artes e vídeos para agendamento de posts em redes sociais.
    - `openwebui`: Documentos, uploads de usuários e bases de arquivos RAG.
    - `n8n`: Relatórios gerados, PDFs e artefatos de fluxos de automação.
    - `nocodb`: Anexos de tabelas e arquivos de bancos relacionais.
  - **Resiliência Local e Cloud:** Suporte transparente tanto para o MinIO local (`STORAGE_PROVIDER=local`) quanto para S3 externo/cloud (`AWS_S3`, `Wasabi`, `Cloudflare R2`) sem regressão de código.

- **[ADD] n8n AI Assistant Avançado sob Demanda (Code Sandbox & SearXNG Web Search):**
  - **Eficiência de Recursos por Padrão:** Por padrão, a stack roda de forma ultraleve e econômica (`N8N_DEV_AI_ASSISTANT=n`), conectando o AI Assistant do n8n diretamente ao LiteLLM soberano sem overhead de containers extras.
  - **Modo Desenvolvedor / Integrações (`N8N_DEV_AI_ASSISTANT=s`):** Quando ativado pelo desenvolvedor no `.env`, o instalador desacoplado provisiona automaticamente:
    - **`n8n-sandbox-api` (`ghcr.io/n8n-io/n8n-sandbox-service-api`):** Ambiente isolado para teste e validação de scripts gerados pela IA sem tocar no container principal.
    - **`SearXNG` (`searxng/searxng`):** Motor de busca headless auto-hospedado (com `formats: [html, json]`) para o assistente consultar schemas e documentações de APIs externas em tempo real.

- **[ADD] Pipeline Soberano de RAG & Docling OCR (IBM Research):**
  - **Validação Estrita de Consumidores & Hardware:** O Docling só é oferecido e ativado se houver consumidores de IA ativos (`USE_OPENWEBUI=s` ou `USE_N8N=s`), além de cumprir os requisitos de hardware (> 4 vCPUs e >= 16 GB RAM), evitando desperdício de recursos computacionais.
  - **Content Extraction Engine:** O OpenWebUI foi integrado diretamente ao microserviço do Docling (`loja_docling:5001`), permitindo extração de PDFs complexos, escaneamentos com OCR, planilhas e DOCX com reconstrução semântica de tabelas Markdown.
  - **Embeddings & pgvector:** Provisionamento condicional da extensão `pgvector` no `openwebui_db` (apenas quando o Docling estiver ativo) e roteamento de embeddings vetoriais via LiteLLM (`loja_litellm:4000/v1`).

- **[ADD] Integração Plena Evolution API ➔ Chatwoot:**
  - **WebSockets Globais & Handshake:** Configuração de `WEBSOCKET_ENABLED=true`, `WEBSOCKET_GLOBAL_EVENTS=true` e `WEBSOCKET_ALLOWED_HOSTS=*`, eliminando rejeições de conexão e garantindo status conectado no Evolution Manager.
  - **Sincronização de Banco:** Alinhamento das credenciais de importação de contatos e conversas apontando diretamente para o `chatwoot_db`.
  - **Auto-Ativação do Copiloto de IA (Zero-Touch):** No provisionamento de conta (`provision_user`), o hook nativo `Integrations::Hook` do app `openai` é automaticamente criado e habilitado com a `${LITELLM_MASTER_KEY}`, eliminando a necessidade de colar a API key manualmente na interface web.
  - **Hardening Chatwoot Community Edition:** Configuração de `DISABLE_ENTERPRISE=true`, `ENABLE_ENTERPRISE=false` e `RUBYOPT=-W0`, eliminando polling de licença empresarial e silenciando avisos de depreciação do Redis.

- **[ADD] Integração Plena de IA nas Aplicações (AI Mesh Soberana via LiteLLM):**
  - **SRE Health Prober em Paralelo:** O motor de sincronização (`sync_ia_models.sh` e `install_1ia.sh`) dispara testes ativos de saúde (micro-probes de 1 token) para todos os modelos candidatos em subshells assíncronos simultâneos, medindo a latência real em milissegundos e expurgando automaticamente endpoints instáveis ou sem créditos (ex: provedores com erro 502/402).
  - **Ranking de Fallback & Auto-Healing:** O modelo online mais rápido e estável é eleito como `TARGET_MODEL` (atendendo o padrão `gpt-4.1`), enquanto todos os demais modelos saudáveis formam uma esteira de fallback resiliente no `router_settings.fallbacks` do LiteLLM.
  - **Virtualização de Aliases sem Poluição Visual:** Os aliases universais (`gpt-4.1`, `gpt-4`, `gpt-4o`, `gpt-4o-mini`, `gpt-3.5-turbo`, `openrouter/free`) foram isolados no `router_settings.model_alias_map`, garantindo que Chatwoot, Postiz, n8n e Evolution operem silenciosamente com qualquer modelo padrão, enquanto a rota pública `/v1/models` no OpenWebUI permanece 100% limpa, exibindo apenas modelos reais e funcionais.
  - **Wildcard Fallback Universal (`*`):** Implementação de regra coringa `{"*": $FALLBACK_JSON}` no LiteLLM, tornando a infraestrutura imune a futuras atualizações de bibliotecas ou modelos internos das aplicações parceiras.
  - **Auditoria 360° com 100% de Sucesso:** Validação ponta a ponta com resposta `HTTP 200` direta a partir do interior de todos os 5 contêineres consumidores:
    1. **Chatwoot (`loja_chatwoot`):** Copiloto do Atendente e Resumos de Chamados via Rails Runner.
    2. **Postiz (`loja_postiz`):** Geração de Legendas, Posts e Hashtags para Redes Sociais.
    3. **Open WebUI (`loja_openwebui`):** Interface de Chat, RAG e Personas.
    4. **n8n (`loja_n8n`):** Nós de AI Agent, LangChain e Automações de Negócio.
    5. **Evolution API (`loja_evolution`):** Transcrição de Áudio e Bots de WhatsApp.

- **[ADD] Service Mesh de Variáveis de Ambiente no n8n:**
  - Injeção automática dos endpoints e credenciais de todos os microsserviços da stack (`DOCLING_API_URL`, `SHLINK_API_URL`, `EVOLUTION_API_URL`, `CHATWOOT_API_URL`, `MINIO_ENDPOINT`, `LISTMONK_API_URL`, `POSTIZ_API_URL`), permitindo que nós e Agentes de IA do n8n interoperem instantaneamente sem configuração manual de IPs ou tokens.

- **[ADD] Auto-Sincronização do Shlink Web Client:**
  - Alinhamento da rota pública (`:8081`) e sincronização da `SHLINK_API_KEY` ativa no provisionamento, garantindo que o painel web abra conectado e pronto para uso imediato.

---

### 🛡️ Engenharia SRE, Resiliência de Rede & Auto-Healing

- **[ADD] Auditoria Proativa de IP Drift (Zero-Touch Self-Healing):**
  - O `install.sh` inspeciona o IP de cada container em execução e compara com o `.env`. Contêineres rodando em IPs desalinhados são desanexados da rede e recriados automaticamente sem intervenção manual.
- **[ADD] Mitigação de Race Conditions no Docker (`Address already in use`):**
  - Desconexão atômica de endpoints com `docker network disconnect -f` antes de remoções forçadas (`docker rm -f`), liberando imediatamente a interface `veth` no kernel.
- **[ADD] Hardening & Supressão Global de Logs (Piso Mínimo WARN/ERROR & Debloat de I/O):**
  - **Debloat & Otimização de I/O em Disco:** Varredura e calibração fina em 100% dos 14 arquivos `docker-compose*.yml` e microsserviços para eliminar logs de DEBUG, INFO, transações rotineiras de sucesso, migrations silenciosas e banners ASCII.
  - **Metabase BI:** Criação do arquivo de configuração dedicado [core/config/log4j2.metabase.xml](file:///e:/Documenta%C3%A7%C3%A3o/seu-repositorio-git/infra-loja1/core/config/log4j2.metabase.xml) com supressão de logs de sincronização de esquemas (`metabase.sync`), Liquibase e desligamento total de geradores de prompts/Metabot (`level="OFF"`).
  - **Open WebUI:** Injeção de `GLOBAL_LOG_LEVEL=WARNING`, `WEBUI_LOG_LEVEL=WARNING`, `UVICORN_LOG_LEVEL=warning`, `ALEMBIC_LOG_LEVEL=WARNING` e `PYTHONWARNINGS=ignore` para silenciar migrações automáticas do Alembic e pings de rotas estáticas.
  - **LiteLLM & Ollama:** Injeção de `UVICORN_LOG_LEVEL=warning`, `LITELLM_BANNER=False`, `DISABLE_BANNER=true`, `GIN_MODE=release` e `OLLAMA_DEBUG_LOG_REQUESTS=false` para expurgar mensagens de healthcheck repetitivas e banners.
  - **Evolution API, Chatwoot, n8n, NocoDB, Listmonk, Postiz & Temporal:** Padronização com `LOG_LEVEL=error`/`warn`, `RUBYOPT=-W0`, `LOG_COLOR=false` e `NC_LOGGER_LEVEL=error`, focando a observabilidade exclusivamente em falhas reais e alertas operacionais críticos.
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
| Evolution API | `install_evolution.sh` | Desacoplado |
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
