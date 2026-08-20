# Manual de Engenharia SRE: Desacoplamento Modular & Integração de Novos Módulos

Este documento estabelece o **gabarito técnico, contrato de interfaces e plano de execução padronizado** para o desacoplamento de microsserviços opcionais e para a **integração de novas aplicações à stack daemind.**, preservando o **Núcleo Core Único e Imutável** (PostgreSQL 17, PgBouncer, Redis, Caddy WAF e LiteLLM).

---

## 🎯 1. Princípios Fundamentais de Desacoplamento

1. **SSOT (Single Source of Truth)**: O arquivo `${TARGET_DIR}/.env` centraliza 100% das chaves e estados de ativação (`USE_<MODULO>="s/n"`).
2. **Pureza & Invariância dos Manifestos**: Os arquivos `docker-compose.<modulo>.yml` são autônomos e declarativos.
3. **Âncora Agnóstica de Injeção de Cards**: A injeção de Cards no `index.html` ancora diretamente antes da tag de fechamento do grid (`</div>\n\n        <div class="footer-note">`), sem depender da existência de outros módulos.
4. **Escrita In-Place de Inode Preservado (`r+`)**: A abertura do arquivo utiliza `open(path, 'r+')` com `seek(0)` e `truncate()` para preservar o Inode do Linux no bind mount do Docker.
5. **Cabeçalho Anti-Cache HTTP no WAF Caddy**: O Caddy injeta `header Cache-Control "no-cache, no-store, must-revalidate"` no portal estático, garantindo a exibição instantânea dos novos cards no navegador sem necessidade de limpar o cache manual.
6. **Restart Único e Atômico do Caddy no `install.sh`**: Disparado ao final da fase de montagem visual no `install.sh`.
8. **Purga Final de Artefatos Desativados**: Ao concluir o `install.sh` com sucesso, os scripts auxiliares e overlays YAML de módulos não ativados são expurgados do disco de produção para manter o ambiente 100% enxuto.
9. **Idempotência Estrita de I/O em Volumes**: Validação prévia de propriedades (`stat -c '%u:%g'`) antes de disparar `chown -R`, evitando tempestades de I/O em diretórios com grande volume de dados/mídias.
10. **Mutação Guardada de Arquivos de Configuração**: Inclusão de trava prévia (`grep -q`) antes de acionar comandos como `sed -i`, impedindo alterações desnecessárias do timestamp de modificação (`mtime`) em arquivos de sistema como o `Caddyfile`.
11. **Idempotência em Chamadas de API de Containers**: Verificação prévia de estado/políticas via API/CLI antes de aplicar mutações (ex: `mc alias list` e `mc anonymous get`), evitando requisições HTTP redundantes e poluição de logs.
12. **Injeção Dinâmica de Sobreposições YAML (Overlays)**: Em manifestos de infraestrutura compartilhada (ex: `docker-compose.s3minio.yml`), os blocos de integração com microsserviços opcionais (Chatwoot, Postiz, Evolution API, NocoDB) utilizam marcadores de comentário como delimitadores (`# --- INJEÇÃO DECLARATIVA NATIVA NO <MODULO> QUANDO S3MINIO ESTÁ ATIVO ---`). A função `build_structure` ativa (descomenta) ou desativa (comenta) dinamicamente cada bloco no manifesto conforme `USE_<MODULO>="s/n"` antes do merge final (`docker compose config`).
13. **Mapeamento e Exposição Dinâmica de Portas no Caddy**: Para evitar a exposição de portas de rede de módulos inativos no Host OS (blindagem de segurança e redução da superfície de ataque), as portas de roteamento e console de cada acessório (ex: `:3000` para Chatwoot, `:5000` para Postiz, `:18080` para NocoDB, `:8081` para Evolution e `:9000/:9001` para S3MinIO) não são expostas no `docker-compose.yml` base. Em vez disso, cada manifesto modular `docker-compose.<modulo>.yml` estende declarativamente o serviço do Caddy (`caddy:`) contendo sua respectiva injeção no array `ports:`. O Docker Compose realiza a fusão nativa das arrays de portas em runtime apenas para as aplicações marcadas como ativas.
14. **Descoberta Autônoma & Alocação Dinâmica de IPs na Rede Privada (Zero Hardcode)**: A topologia de rede segue um modelo determinístico com zero hardcode. O Núcleo Core ocupa a faixa fixa (`.1` a `.6`), enquanto os módulos desacoplados recebem seus endereços IP sequencialmente a partir de `.7`. O `preinstall.sh` e o `install.sh` realizam a varredura da **Linha 2** de todos os scripts `install_<modulo>.sh` (ex: `# CHATWOOT` ou `# POSTIZ TEMPORAL`), agregam todos os nós em um array global, aplicam **ordenação alfabética estrita nos nomes dos nós** (`sort -u`) e distribuem os endereços IP sequencialmente `${IP_<NÓ>}` injetando as variáveis no `.env`.
15. **Auto-Tuning Descentralizado nos Módulos (`build_envs`)**: O `autotune.sh` atua estritamente como motor de descoberta de hardware do Host (`SYSTEM_TOTAL_CPUS`, `SYSTEM_TOTAL_RAM_MB`, `SYSTEM_TOTAL_DISK_GB`) e dimensionamento do Núcleo Core Imutável. Cada módulo desacoplado é soberano e DEVE implementar em seu próprio `build_envs()` a lógica de cálculo proporcional dos seus limites (`CPU_<MODULO>`, `MEM_<MODULO>`, `RES_<MODULO>`, concorrência de processos e Heaps), eliminando dependências ou edições manuais no `autotune.sh`.
16. **Padronização de Tags de Logging Contextuais por Script/Módulo**: Todas as mensagens de saída em terminal (`echo`, `printf`) DEVEM carregar o prefixo identificador explícito do script ou módulo que a originou (ex: `[SRE PREINSTALL]`, `[IDEMPOTÊNCIA PREINSTALL]`, `[SUCESSO PREINSTALL]`, `[SRE INSTALL]`, `[SRE EVOLUTION]`, `[SRE CHATWOOT]`, `[SRE BACKUP]`, `[SRE RESTORE]`, `[SRE UPGRADE]`, `[CI SMOKE TEST]`). Isso garante rastreabilidade forense inequívoca em logs agregados de CI/CD, esteiras em background e sessões multiplexadas.

---

## 📋 1.4. Padrões Obrigatórios para Criação de Manifestos (`docker-compose.<modulo>.yml`)

Ao criar ou desacoplar qualquer novo serviço da stack, o manifesto `core/config/docker-compose.<modulo>.yml` deve atender rigorosamente aos seguintes **10 Padrões Obrigatórios de Engenharia SRE**:

1. **Nomeação Padronizada com Prefixo Dinâmico (`container_name`)**:
   - O contêiner DEVE utilizar a variável `${PREFIXO_CONTAINER}_<servico>` (ex: `container_name: '${PREFIXO_CONTAINER}_chatwoot'`).
2. **Alocação Dinâmica na Rede Privada (`instancia_net`)**:
   - Deve ser vinculado à rede `instancia_net` utilizando a variável dinâmica `${IP_<NOME_DO_NO>}` (ex: `ipv4_address: ${IP_EVOLUTION}`).
   - O nome da variável corresponde diretamente ao nó declarado na Linha 2 do script do módulo (ex: se declarou `# MEUMODULO`, consome `${IP_MEUMODULO}`).
3. **Política de Reinicialização de Resiliência (`restart`)**:
   - Definir `restart: unless-stopped` ou `restart: always` para recuperação autônoma após falha ou reboot do host.
4. **Matriz de Dimensionamento de Hardware Dinâmico (`deploy.resources`)**:
   - O container DEVE consumir os limites calculados dinamicamente pelo seu próprio `build_envs()` com fallbacks seguros:
     ```yaml
     deploy:
       resources:
         limits:
           cpus: '${CPU_<MODULO>:-1.0}'
           memory: '${MEM_<MODULO>:-1024M}'
         reservations:
           memory: '${RES_<MODULO>:-256M}'
     ```
5. **Paridade de Fuso Horário e Hardening de Timezone**:
   - Injetar no `environment` a variável `TZ=America/Sao_Paulo` (ou `${TZ:-America/Sao_Paulo}`).
   - Montar obrigatoriamente os volumes em modo somente leitura:
     ```yaml
     volumes:
       - '/etc/timezone:/etc/timezone:ro'
       - '/etc/localtime:/etc/localtime:ro'
     ```
6. **Dimensionamento de Heap V8 para Serviços Node.js (`NODE_OPTIONS`)**:
   - Para aplicações em Node.js/Nest.js/Next.js (Postiz, Evolution, NocoDB), definir:
     `- NODE_OPTIONS=--max-old-space-size=${NODE_HEAP_DEFAULT:-768} --no-deprecation`
7. **Encapsulamento de Portas via Extensão do Caddy (Zero Exposure no Host)**:
   - O serviço da aplicação **NÃO DEVE** expor portas diretamente para o host (`ports:` no serviço principal é PROIBIDO).
   - A exposição da porta deve ser feita estendendo o serviço `caddy:` no próprio manifesto modular:
     ```yaml
     caddy:
       ports:
         - "${MODULO_PORT:-PORTA}:PORTA/tcp"
     ```
8. **Probes de Prontidão Nativas (`healthcheck`)**:
   - Todo contêiner DEVE declarar um `healthcheck` via `CMD-SHELL` com comando leve (`wget --spider`, `curl`, `redis-cli ping` ou probe TCP) com `interval`, `timeout` e `retries` definidos.
9. **Mapeamento de Dependências com `condition: service_healthy`**:
   - Serviços que dependem de banco ou cache DEVEM declarar `depends_on` exigindo prontidão saudável dos provedores:
     ```yaml
     depends_on:
       postgres:
         condition: service_healthy
       redis:
         condition: service_healthy
     ```
10. **Persistência em Volumes Relativos Isolados**:
    - Todo dado persistente deve ser montado em subpastas de `./volumes/` (ex: `./volumes/storage_data/<modulo>` ou `./volumes/<modulo>_data`), garantindo portabilidade e facilidade de backup/restore.

---

## 📐 1.5. Contrato de Interface Padronizado & Polimórfico (`install_<modulo>.sh`)

Cada script modular (`install_<modulo>.sh`) implementa rigorosamente a mesma interface pública de **16 funções padronizadas** sem prefixos específicos, garantindo polimorfismo total na invocação tanto pelo `preinstall.sh` (Wizard & Hardening) quanto pelo `install.sh` (Orquestrador de Topologia):

| Nº | Função Padronizada | Descrição de Engenharia SRE & Propósito |
| :---: | :--- | :--- |
| **1** | `collect_wizard_inputs` | Coleta interativa de perguntas no Wizard CLI do `preinstall.sh`, com validação estrita e persistência no Wizard Cache (`save_wizard_cache`). |
| **2** | `collect_wizard_inputs_tui` | *(Especialistas de Interface)* Interface gráfica interativa Dialog TUI para módulos com formulários e radiolists próprios (ex: `install_0ts.sh`, `install_s3minio.sh`, `install_1ia.sh`). |
| **3** | `is_hardware_supported` | *(Opcional)* Valida se o hardware do host (vCPUs/RAM via autotune) atende aos requisitos mínimos do módulo. Retorna `0` (suportado) ou `1` (insuficiente), permitindo que o `preinstall.sh` omita o módulo dinamicamente sem nenhum hardcode. |
| **4** | `build_envs` | Injeção desacoplada de variáveis de ambiente e segredos padrão no arquivo `.env` SSOT (`${NOME_ARQUIVO:-$TARGET_DIR/.env}`). |
| **5** | `build_structure` | Infraestrutura pré-boot (criação física de diretórios no Host OS, permissões via `stat`/`chown` e ativação/desativação dinâmica de blocos de overlay YAML). |
| **6** | `provision_db` | Criação idempotente dos bancos de dados lógicos no PostgreSQL (`CREATE DATABASE <modulo_db>`). |
| **7** | `provision_infra` | Infraestrutura e Hardening: injeção de regras de firewall de porta no `DOCKER-USER` (via `${IP_NETWORK_SUBNET}` ou `tailscale0`), geração de regras de DNS/IPSet em `/etc/dnsmasq.d/<modulo>.conf`, criação de esquemas DDL e namespaces Temporal. |
| **8** | `inject_caddy_routes` | Injeta portas e rotas de proxy reverso no `Caddyfile` com sanitização de formatação. |
| **9** | `remove_caddy_routes` | Purga cirúrgica das rotas de proxy reverso do `Caddyfile`. |
| **10** | `inject_dashboard_card` | Injeta card visual no `index.html` (modo `r+` com `truncate` preservando Inode do Linux no bind mount). |
| **11** | `remove_dashboard_card` | Remove card visual do `index.html`. |
| **12** | `disable` / `teardown` | Teardown atômico (remove container, limpa rotas do Caddy, purga cards visuais e remove `/etc/dnsmasq.d/<modulo>.conf`). |
| **13** | `start_container` | Subida integrada e atômica do container via Docker Compose. |
| **14** | `wait_readiness` | Probe de prontidão com **Graceful Degradation** (retorna 1 e emite aviso em caso de lentidão sem abortar a esteira com `exit 1`). |
| **15** | `audit_health` | Validação de saúde HTTP/TCP e handshake da aplicação. |
| **16** | `get_version` | Captura dinâmica da versão interna da imagem/aplicação em execução. |
| **17** | `provision_user` | Provisão e automação de conta do usuário administrador mestre via CLI/API/Rails runner. |
| *(Aux)* | `render_forensic_report` | Renderização do bloco de endpoints e credenciais no relatório visual do console. |

---

### 🏷️ 1.5.0. Padrão Estrutural de Cabeçalho dos Scripts Modulares:
Todo script modular `install_<modulo>.sh` DEVE conter no seu cabeçalho:
- **Linha 1:** Shebang `#!/usr/bin/env bash`.
- **Linha 2:** `# <NOME_DO_NO>` em caixa alta (ex: `# CHATWOOT`). Utilizado pelo motor para cálculo de IP estático determinístico (`IP_<NOME_DO_NO>`).
- **Linha 3:** `# <Nome Oficial>: <Descrição Funcional>` (ex: `# Chatwoot: Inbox Omnichannel Multiatendente`). Utilizado pelo `preinstall.sh` para popular dinamicamente a checklist do Dialog TUI sem nenhum hardcode.

---

## 🛡️ 1.5.1. Regras Estritas de Engenharia e Prevenção de Falhas nos Scripts (`install_<modulo>.sh`)

Para assegurar **Zero Bugs, Idempotência Absoluta e Resiliência em Produção**, qualquer script modular `install_<modulo>.sh` DEVE implementar obrigatoriamente as seguintes salvaguardas técnicas em cada uma de suas funções:

### 1. **Cabeçalho e Absorção Resiliente de Variáveis:**
   - Iniciar obrigatoriamente com `set -euo pipefail`.
   - Ler o `$TARGET_DIR` do primeiro argumento (`${1:-/opt/daemind}`) e absorver o `.env` de forma protegida:
     ```bash
     if [ -f "$ENV_FILE" ]; then
         set -a; source "$ENV_FILE"; set +a
     fi
     ```
   - Tratar internamente prefixos e fallbacks seguros (ex: `PREFIX="${PREFIXO_CONTAINER:-loja1}"`, `DB_USER="${DB_USER:-postgres}"`).

### 2. **Idempotência Estrita de I/O em Diretórios e Permissões (`build_structure`):**
   - **Criação Segura**: Usar `sudo mkdir -p "$TARGET_DIR/volumes/..." 2>/dev/null || true`.
   - **Guarda de Propriedade (`stat -c '%u:%g'`)**: NUNCA disparar `chown -R` cego. Inspecionar antes com `stat` para evitar I/O desnecessário em volumes com milhares de arquivos de mídia:
     ```bash
     local CURRENT_OWNER=$(stat -c '%u:%g' "$VOLUME_PATH" 2>/dev/null || echo "")
     if [ "$CURRENT_OWNER" != "$TARGET_OWNER" ]; then
         sudo chown -R "$TARGET_OWNER" "$VOLUME_PATH" 2>/dev/null || true
     fi
     ```
   - **Guarda de Modo de Armazenamento**: Se `STORAGE_MODE == s3_external`, suprimir a criação física de volumes locais não utilizados.

### 3. **Criação Segura e Idempotente de Bancos Lógicos (`provision_db`):**
   - Consultar `pg_database` antes de tentar criar o banco:
     ```bash
     if docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -c "SELECT 1 FROM pg_database WHERE datname = '<modulo_db>'" 2>/dev/null | grep -q 1; then
         echo "➜ [IDEMPOTÊNCIA] Banco de dados '<modulo_db>' já existente."
     else
         docker compose exec -T postgres psql -U "${DB_USER}" -d "${PREFIX}_db" -q -c "CREATE DATABASE <modulo_db>;" > /dev/null 2>&1 || true
     fi
     ```

### 4. **Manipulação Precisa de Rotas no `Caddyfile` (`inject_caddy_routes` / `remove_caddy_routes`):**
   - **Guarda de Injeção**: Inspecionar com `grep -q ":${PORTA}" "$CADDYFILE"` antes de modificar o arquivo.
   - **Injeção com Quebra de Linha Limpa**: Injetar blocos declarativos com `reverse_proxy` formatados sem quebrar indentação.
   - **Remoção Limpa e Sem Resíduos**: `remove_caddy_routes` deve limpar cirurgicamente o bloco da porta usando Python/Sed preservando o resto do Caddyfile.

### 5. **Manipulação de Cards no Portal Web (`inject_dashboard_card` / `remove_dashboard_card`):**
   - **Preservação de Inode do Linux**: Abertura em modo `r+` com `seek(0)` e `truncate()` via Python 3 inline. Proibido usar `sed -i` que altera o Inode e corrompe o bind mount do Docker.
   - **Âncora Agnóstica de Injeção**: Injetar imediatamente antes da tag `</div>\n\n        <div class="footer-note">`.
   - **Remoção sem Deformação**: Localizar o elemento `<div class="card" ...>` específico do módulo e expurgá-lo de forma atômica.

### 6. **Probes com Retry Limitado e Timeout (`wait_readiness` & `audit_health`):**
   - Executar loop de espera consultando `docker inspect -f '{{.State.Health.Status}}'` com contador máximo de tentativas (timeout de 60s a 120s) para não congelar o instalador.
   - Validação com fallbacks seguros em caso de lentidão temporária de inicialização.

### 7. **Roteamento Universal de Ações via CLI (`case "$ACTION"`):**
   - Todo script deve possuir no rodapé o roteador de comandos CLI suportando execução individual de qualquer uma das 15 funções, com aliases seguros (ex: `inject_card`, `teardown`, `inject_caddy`, `render_report`) e a execução do fluxo completo `all`.

### 8. **Consumo de Métricas de Hardware e GPU via `autotune.sh` (Zero Chamadas OS Diretas):**
   - Nenhum script modular deve executar comandos diretos de SO (`nproc`, `free -m`, `df -BG`, `nvidia-smi`, `lspci`) em `collect_wizard_inputs` ou em suas funções para obter dados de hardware ou aceleração gráfica.
   - O motor `core/scripts/autotune.sh` é o **Single Source of Truth (SSOT)** de inspeção física de hardware e aceleração por GPU dedicada (Desktop e Mobile/Notebook), exportando globalmente as métricas normalizadas:
     - `SYSTEM_TOTAL_CPUS` / `TOTAL_CPUS` (Quantidade de núcleos vCPU)
     - `SYSTEM_TOTAL_RAM_GB` / `TOTAL_RAM_GB` (Capacidade de memória RAM em GB)
     - `IS_MODEST_SERVER` (`true` se $\le$ 4 vCPUs ou $<$ 8 GB RAM)
     - `SYSTEM_HAS_DEDICATED_GPU` / `HAS_DEDICATED_GPU` (`true` se detectada GPU dedicada compatível)
     - `SYSTEM_GPU_VENDOR` / `GPU_VENDOR` (`NVIDIA`, `AMD`, `INTEL` ou `NONE`)
     - `SYSTEM_GPU_MODEL` / `GPU_MODEL` (Nome/descrição do modelo de GPU detectado)
     - `SYSTEM_GPU_VRAM_MB` / `GPU_VRAM_MB` (Quantidade de memória de vídeo VRAM em MB)
     - `SYSTEM_GPU_VRAM_GB` / `GPU_VRAM_GB` (Quantidade de memória de vídeo VRAM em GB)
   - Módulos que exigem validação de capacidade e aceleração gráfica (ex: `install_s3minio.sh`, `install_docling.sh`, `install_ollama.sh`) devem consumir estritamente essas variáveis do ambiente na função `is_hardware_supported()`. O Ollama requer vCPUs $> 4$, RAM $\ge 16\text{ GB}$ e GPU dedicada com VRAM $> 4\text{ GB}$ (NVIDIA RTX, Radeon RX 6000/7000/8000/9000 ou Intel Arc — Desktop ou Laptop/Mobile).

---

## 🏛️ 1.7. Esqueleto Canônico de Manifesto (`core/config/docker-compose.<modulo>.yml`)

Todo novo serviço desacoplado da infraestrutura deve utilizar rigorosamente a seguinte estrutura declarativa:

```yaml
services:
  <modulo>:
    image: '<fornecedor>/<modulo>:<versao_fixada>'
    container_name: '${PREFIXO_CONTAINER}_<modulo>'
    networks:
      instancia_net:
        ipv4_address: ${IP_<MODULO>}
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '${CPU_<MODULO>:-1.0}'
          memory: '${MEM_<MODULO>:-1024M}'
        reservations:
          memory: '${RES_<MODULO>:-256M}'
    environment:
      - TZ=America/Sao_Paulo
      - NODE_OPTIONS=--max-old-space-size=${NODE_HEAP_DEFAULT:-768} --no-deprecation
      - LOG_LEVEL=error
      - DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@pgbouncer:6432/<modulo>_db?pool=20
      - REDIS_URL=redis://${IP_REDIS}:6379/0
      # Demais variáveis específicas consumidas do .env SSOT
    volumes:
      - './volumes/<modulo>_data:/app/data'
      - '/etc/timezone:/etc/timezone:ro'
      - '/etc/localtime:/etc/localtime:ro'
    depends_on:
      pgbouncer:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://127.0.0.1:<PORTA_INTERNA>/healthz || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Injeção e Extensão declarativa da porta no Caddy WAF (Zero exposição direta no Host OS)
  caddy:
    ports:
      - "${<MODULO>_PORT:-<PORTA_EXTERNA>}:<PORTA_EXTERNA>/tcp"
```

---

## 🛠️ 1.8. Esqueleto Canônico de Script de Ciclo de Vida (`core/scripts/install_<modulo>.sh`)

Todo novo script desacoplado deve implementar a matriz completa de **funções padronizadas** com todas as salvaguardas de idempotência, prevenção de I/O, integração ao Motor SSOT e manipulação segura de Inode:

```bash
#!/usr/bin/env bash
# <NOME_DO_NO_EM_MAIUSCULO>
# <Nome Oficial>: <Descrição Funcional Completa para o Dialog TUI>
# ===============================================================================
# DAEMIND SRE MODULE - PROVISIONADOR DINÂMICO: <MODULO_NOME>
# Especificação: Módulo desacoplado de gerenciamento, banco, Caddy, cards e auditoria
# ===============================================================================

set -euo pipefail

MODULE_VERSION="v2026.08.18.01-DECOUPLED"

TARGET_DIR="${1:-/opt/daemind}"
ENV_FILE="${TARGET_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
fi

# 1. collect_wizard_inputs: Coleta interativa de perguntas no Wizard CLI do preinstall.sh
collect_wizard_inputs() {
    coletar_sn "Deseja instalar o <MODULO_TITULO> (<MODULO_DESCRICAO>)?" USE_<MODULO> "s"
    [[ "${USE_<MODULO>:-s}" =~ ^[Ss]$ ]] && USE_<MODULO>="s" || USE_<MODULO>="n"
    save_wizard_cache "USE_<MODULO>" "$USE_<MODULO>"
}

# 2. collect_wizard_inputs_tui: (Opcional) Interface Dialog TUI para módulos com telas dedicadas
collect_wizard_inputs_tui() {
    # Implemente apenas se o módulo requerer subtelas, radiolists ou credenciais próprias
    return 0
}

# 2. build_envs: Injeção de variáveis de ambiente e dimensionamento de hardware no SSOT .env
build_envs() {
    local env_path="${NOME_ARQUIVO:-${TARGET_DIR:-/opt/daemind}/.env}"

    # Leitura das métricas de hardware exportadas pelo autotune.sh
    local cpus="${SYSTEM_TOTAL_CPUS:-${TOTAL_CPUS:-4}}"
    local ram_mb="${SYSTEM_TOTAL_RAM_MB:-${TOTAL_RAM_MB:-8192}}"

    # Dimensionamento dinâmico de CPU (ex: Standard <=4 cores, Pro 5-8 cores, Enterprise >8 cores)
    local cpu_<modulo>="1.0"
    if [ "$cpus" -gt 8 ]; then
        cpu_<modulo>="4.0"
    elif [ "$cpus" -gt 4 ]; then
        cpu_<modulo>="2.0"
    fi

    # Dimensionamento dinâmico de RAM e Reservations
    local mem_<modulo>="1024M"
    local res_<modulo>="256M"

    if [ "$ram_mb" -gt 24576 ]; then
        mem_<modulo>="4096M"
        res_<modulo>="1024M"
    elif [ "$ram_mb" -gt 12288 ]; then
        mem_<modulo>="2048M"
        res_<modulo>="512M"
    fi

    cat << EOF >> "$env_path"

# --- <MODULO> Decoupled Env & Dynamic Tuning ---
USE_<MODULO>="${USE_<MODULO>:-s}"
HOST_<MODULO>_PORT="<PORTA_EXTERNA>"
CPU_<MODULO>=${CPU_<MODULO>:-${cpu_<modulo>}}
MEM_<MODULO>=${MEM_<MODULO>:-${mem_<modulo>}}
RES_<MODULO>=${RES_<MODULO>:-${res_<modulo>}}
EOF
}

# 3. build_structure: Infraestrutura física pré-boot e permissões
build_structure() {
    echo "➜ [SRE <MODULO>] Criando estrutura física de volumes e permissões..."
    sudo mkdir -p "$TARGET_DIR"/volumes/<modulo>_data 2>/dev/null || true
    
    local TARGET_OWNER="1000:1000"
    if [ -n "${SUDO_USER:-}" ]; then
        local TARGET_UID=$(id -u "$SUDO_USER" 2>/dev/null || echo "1000")
        local TARGET_GID=$(id -g "$SUDO_USER" 2>/dev/null || echo "1000")
        TARGET_OWNER="${TARGET_UID}:${TARGET_GID}"
    fi

    local CURRENT_OWNER=$(stat -c '%u:%g' "$TARGET_DIR/volumes/<modulo>_data" 2>/dev/null || echo "")
    if [ "$CURRENT_OWNER" != "$TARGET_OWNER" ]; then
        echo "  ↳ Ajustando permissões do volume (${CURRENT_OWNER:-desconhecido} -> ${TARGET_OWNER})..."
        sudo chown -R "$TARGET_OWNER" "$TARGET_DIR/volumes/<modulo>_data" 2>/dev/null || true
    else
        echo "➜ [IDEMPOTÊNCIA] Permissões de volumes já alinhadas (${TARGET_OWNER}). Preservando I/O."
    fi
}

# 4. provision_db: Criação atômica do banco de dados lógico
provision_db() {
    local PREFIX="${PREFIXO_CONTAINER:-loja1}"
    echo "➜ [SRE <MODULO>] Garantindo banco de dados lógico (<modulo>_db) no PostgreSQL..."
    if docker compose exec -T postgres psql -U "${DB_USER:-postgres}" -d "${PREFIX}_db" -c "SELECT 1 FROM pg_database WHERE datname = '<modulo>_db'" 2>/dev/null | grep -q 1; then
        echo "➜ [IDEMPOTÊNCIA] Banco de dados '<modulo>_db' já existente. Preservando esquema."
    else
        echo "  ↳ Criando banco de dados '<modulo>_db'..."
        docker compose exec -T postgres psql -U "${DB_USER:-postgres}" -d "${PREFIX}_db" -q -c "CREATE DATABASE <modulo>_db;" > /dev/null 2>&1 || true
    fi
}

# 5. provision_infra: Esquemas DDL, regras de firewall DOCKER-USER e dnsmasq.d/<modulo>.conf
provision_infra() {
    echo "➜ [SRE <MODULO>] Executando migrações DDL, firewall perimetral e DNS allowlist..."
    local use_val="${USE_<MODULO>:-s}"
    if [[ "$use_val" =~ ^[Ss]$ ]]; then
        # Injeção de domínios permitidos no DNSMasq modular
        sudo mkdir -p /etc/dnsmasq.d 2>/dev/null || true
        cat << 'EOF' | sudo tee /etc/dnsmasq.d/<modulo>.conf > /dev/null
# IPSET ALLOWED DOMAINS (<MODULO>)
ipset=/<dominio-externo.com>/ALLOWED_DOMAINS
EOF
        # Injeção de regra estrita de porta no DOCKER-USER do Kernel
        if [ "${USE_TAILSCALE:-false}" = "true" ]; then
            sudo iptables -I DOCKER-USER 7 -i tailscale0 -p tcp --dport <PORTA_EXTERNA> -j ACCEPT 2>/dev/null || true
        else
            sudo iptables -I DOCKER-USER 7 -s "${IP_NETWORK_SUBNET}" -p tcp --dport <PORTA_EXTERNA> -j ACCEPT 2>/dev/null || true
        fi
    else
        sudo rm -f /etc/dnsmasq.d/<modulo>.conf 2>/dev/null || true
    fi
}

# 6. inject_caddy_routes: Injeção declarativa de rota no Caddyfile
inject_caddy_routes() {
    local CADDYFILE="${TARGET_DIR}/core/config/Caddyfile"
    local PORTA="<PORTA_EXTERNA>"
    local IP_SRV="${IP_<MODULO>:-172.25.0.X}"
    
    if [ -f "$CADDYFILE" ]; then
        if grep -q ":${PORTA}" "$CADDYFILE" 2>/dev/null; then
            echo "➜ [IDEMPOTÊNCIA] Rota da porta :${PORTA} já configurada no Caddyfile."
        else
            echo "➜ [CONFIGURANDO] Injetando rota do <MODULO> (:${PORTA}) no Caddyfile..."
            cat << EOF >> "$CADDYFILE"

:${PORTA} {
    encode gzip zstd
    reverse_proxy ${IP_SRV}:<PORTA_INTERNA> {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF
        fi
    fi
}

# 7. remove_caddy_routes: Purga cirúrgica de rota do Caddyfile
remove_caddy_routes() {
    local CADDYFILE="${TARGET_DIR}/core/config/Caddyfile"
    local PORTA="<PORTA_EXTERNA>"
    if [ -f "$CADDYFILE" ] && grep -q ":${PORTA}" "$CADDYFILE" 2>/dev/null; then
        echo "➜ [SRE TEARDOWN] Removendo rota da porta :${PORTA} do Caddyfile..."
        python3 -c "
path = '$CADDYFILE'
porta = ':$PORTA'
try:
    with open(path, 'r') as f:
        lines = f.readlines()
    new_lines = []
    inside = False
    for line in lines:
        if porta in line and '{' in line:
            inside = True
            continue
        if inside and line.strip() == '}':
            inside = False
            continue
        if not inside:
            new_lines.append(line)
    with open(path, 'w') as f:
        f.writelines(new_lines)
except Exception as e:
    print(f'🚨 Erro ao purgar Caddyfile: {e}')
" 2>/dev/null || true
    fi
}

# 8. inject_dashboard_card: Injeção de Card no index.html (preservando Inode via r+)
inject_dashboard_card() {
    local HTML_PATH="${TARGET_DIR}/core/config/dashboard/index.html"
    if [ -f "$HTML_PATH" ]; then
        if grep -q "href=\"http://' + window.location.hostname + ':<PORTA_EXTERNA>\"" "$HTML_PATH" 2>/dev/null || grep -q '<h3><MODULO_TITULO></h3>' "$HTML_PATH" 2>/dev/null; then
            echo "➜ [IDEMPOTÊNCIA] Card visual do <MODULO> já injetado no dashboard."
        else
            echo "➜ [SRE UI] Injetando card visual do <MODULO> no dashboard (preservando Inode)..."
            python3 -c "
path = '$HTML_PATH'
card_html = '''
            <a href=\"#\" onclick=\"window.open('http://' + window.location.hostname + ':<PORTA_EXTERNA>', '_blank'); return false;\" class=\"card\">
                <div class=\"card-icon\"><MODULO_EMOJI></div>
                <div class=\"card-title\"><MODULO_TITULO></div>
                <div class=\"card-desc\"><MODULO_DESCRICAO></div>
                <div class=\"card-badge\">Porta :<PORTA_EXTERNA></div>
            </a>
'''
try:
    with open(path, 'r+') as f:
        content = f.read()
        anchor = '</div>\n\n        <div class=\"footer-note\">'
        if anchor in content:
            parts = content.split(anchor, 1)
            f.seek(0)
            f.write(parts[0] + card_html + '\n        ' + anchor + parts[1])
            f.truncate()
            print('✔ [SUCESSO] Card do <MODULO> injetado com sucesso.')
except Exception as e:
    print(f'🚨 Erro ao injetar card: {e}')
" 2>/dev/null || true
        fi
    fi
}

# 9. remove_dashboard_card: Purga cirúrgica do Card visual
remove_dashboard_card() {
    local HTML_PATH="${TARGET_DIR}/core/config/dashboard/index.html"
    if [ -f "$HTML_PATH" ] && (grep -q ':<PORTA_EXTERNA>' "$HTML_PATH" 2>/dev/null || grep -q '<h3><MODULO_TITULO></h3>' "$HTML_PATH" 2>/dev/null); then
        echo "➜ [SRE TEARDOWN] Purgando card do <MODULO> do dashboard..."
        python3 -c "
path = '$HTML_PATH'
try:
    with open(path, 'r+') as f:
        content = f.read()
        import re
        pattern = r'<a[^>]*:<PORTA_EXTERNA>[^>]*>.*?</a>'
        new_content = re.sub(pattern, '', content, flags=re.DOTALL)
        f.seek(0)
        f.write(new_content)
        f.truncate()
        print('✔ [SUCESSO] Card do <MODULO> purgado com sucesso.')
except Exception as e:
    print(f'🚨 Erro ao purgar card: {e}')
" 2>/dev/null || true
    fi
}

# 10. disable: Teardown atômico do módulo
disable() {
    echo "➜ [SRE TEARDOWN] Desativando módulo <MODULO>..."
    remove_dashboard_card
    remove_caddy_routes
    local PREFIX="${PREFIXO_CONTAINER:-loja1}"
    sudo docker rm -f "${PREFIX}_<modulo>" 2>/dev/null || true

    # Limpeza de Regras de Firewall Perimetral e DNS
    sudo iptables -D DOCKER-USER -i tailscale0 -p tcp --dport <PORTA_EXTERNA> -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -s "${IP_NETWORK_SUBNET}" -p tcp --dport <PORTA_EXTERNA> -j ACCEPT 2>/dev/null || true
    if [ -f /etc/dnsmasq.d/<modulo>.conf ]; then
        sudo rm -f /etc/dnsmasq.d/<modulo>.conf 2>/dev/null || true
        sudo systemctl restart dnsmasq 2>/dev/null || true
    fi
    echo "✔ [SUCESSO <MODULO>] Módulo desativado, container removido, firewall e rotas limpos."
}

# 11. start_container: Subida do serviço
start_container() {
    local PREFIX="${PREFIXO_CONTAINER:-loja1}"
    echo "➜ [SRE <MODULO>] Inicializando container ${PREFIX}_<modulo>..."
    (cd "$TARGET_DIR" && sudo docker compose -f core/config/docker-compose.<modulo>.yml up -d --no-deps <modulo>) 2>/dev/null || true
}

# 12. wait_readiness: Probe de prontidão com Graceful Degradation
wait_readiness() {
    local PREFIX="${PREFIXO_CONTAINER:-loja1}"
    echo "➜ [SRE <MODULO>] Aguardando prontidão saudável do container ${PREFIX}_<modulo>..."
    local TENTATIVAS=0
    until [ "$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unhealthy{{end}}' ${PREFIX}_<modulo> 2>/dev/null)" = "healthy" ]; do
        TENTATIVAS=$((TENTATIVAS+1))
        if [ "$TENTATIVAS" -ge 30 ]; then
            echo "⚠️ [SRE WARN <MODULO>] Container ${PREFIX}_<modulo> demorou a responder (>60s). Continuando em modo resiliente..."
            return 1 2>/dev/null || true
        fi
        sleep 2
    done
    echo "✔ [SUCESSO] Container ${PREFIX}_<modulo> está saudável (healthy)."
}

# 13. audit_health: Validação de handshake e resposta HTTP
audit_health() {
    local DOMAIN="${1:-localhost}"
    local STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${DOMAIN}:<PORTA_EXTERNA>/" || echo "000")
    if [ "$STATUS_CODE" -ge 200 ] && [ "$STATUS_CODE" -lt 400 ]; then
        echo "✔ [AUDITORIA] Handshake HTTP <MODULO> OK (Status: ${STATUS_CODE})"
    else
        echo "⚠️ [AUDITORIA] Oscilação no <MODULO> (Status: ${STATUS_CODE})"
    fi
}

# 14. get_version: Captura dinâmica da versão da aplicação
get_version() {
    local PREFIX="${PREFIXO_CONTAINER:-loja1}"
    local VER=$(sudo docker inspect --format='{{index .Config.Labels "org.opencontainers.image.version"}}' ${PREFIX}_<modulo> 2>/dev/null || echo "")
    [ -z "$VER" ] && VER=$(sudo docker inspect --format='{{.Config.Image}}' ${PREFIX}_<modulo> 2>/dev/null | cut -d: -f2 || echo "latest")
    echo "$VER"
}

# 15. provision_user: Automação do usuário administrador
provision_user() {
    echo "➜ [SRE <MODULO>] Configurando credenciais do administrador..."
    # Lógica CLI/API de provisionamento do admin
}

# (Aux) render_forensic_report: Relatório visual para console
render_forensic_report() {
    local DOMAIN="${1:-localhost}"
    echo "====================================================================="
    echo "📌 <MODULO_TITULO>: http://${DOMAIN}:<PORTA_EXTERNA>"
    echo "   ↳ Usuário: ${ADMIN_EMAIL:-admin@empresa.com}"
    echo "====================================================================="
}

# Roteador Universal de Chamadas CLI
ACTION="${2:-all}"
case "$ACTION" in
    collect_wizard_inputs|collect_inputs|wizard_prompt)
        collect_wizard_inputs
        ;;
    build_envs|build_env)
        build_envs
        ;;
    get_version|render_forensic_report|render_report|audit_health|inject_dashboard_card|inject_card|remove_dashboard_card|remove_card|purge_card|disable|teardown|inject_caddy_routes|inject_caddy|remove_caddy_routes|remove_caddy|start_container|wait_readiness|provision_infra|provision_db|provision_user|build_structure)
        case "$ACTION" in
            inject_caddy) inject_caddy_routes ;;
            remove_caddy) remove_caddy_routes ;;
            inject_card) inject_dashboard_card ;;
            remove_card|purge_card) remove_dashboard_card ;;
            teardown) disable ;;
            render_report) render_forensic_report "${3:-localhost}" ;;
            audit_health) audit_health "${3:-localhost}" ;;
            render_forensic_report) render_forensic_report "${3:-localhost}" ;;
            *) "$ACTION" "${3:-localhost}" ;;
        esac
        ;;
    all|*)
        build_structure
        provision_db
        provision_infra
        inject_caddy_routes
        inject_dashboard_card
        start_container
        wait_readiness
        provision_user
        ;;
esac
```

---

O orquestrador mestre `core/scripts/install.sh` e o preparador de host `preinstall.sh` não contêm acoplamento rígido de quais módulos existem no repositório. Em vez disso, utilizam o padrão **Dynamic Plugin Discovery**:
1. **`preinstall.sh` (Wizard & Hardening Unificado)**: Varre dinamicamente `core/scripts/install_*.sh`, coletando as respostas com `collect_wizard_inputs`, consolidando o `.env` com `build_envs` e aplicando as regras de firewall e DNS allowlists com `provision_infra`.
2. **`install.sh` (Orquestrador de Topologia & Prontidão)**: Varre dinamicamente `core/scripts/install_*.sh`, avalia a flag `USE_<MODULO>="s/n"` no `.env`, separando em `MODULOS_DESACOPLADOS_ATIVOS` e `MODULOS_DESACOPLADOS_INATIVOS`.
3. **Dispatch Polimórfico com Tolerância a Falhas**: O `install.sh` itera sobre os módulos ativos disparando sequencialmente as funções padronizadas (`build_structure`, `provision_db`, `start_container`, `wait_readiness`, `provision_infra`, etc.), permitindo plugar ou desplugar novos microsserviços sem alterar uma única linha dos scripts centrais e sem que falhas em módulos opcionais abortem a instalação.

---

## 🔍 2. Diagnóstico Forense do `index.html` Anexado

Analisando o arquivo `scratch/logs/index.html` extraído do servidor:
- **Estrutura HTML**: 100% válida. As tags `<a>`, `<div>` e a indentação estão perfeitamente sintáticas.
- **Card Presente no Físico**: O bloco do MinIO Console (`:9001`) **ESTÁ PRESENTE** no arquivo (Linhas 314-326).
- **Causa da Não Exibição no Navegador**: Cache de resposta HTTP do navegador (Browser Caching).
- **Solução Definitiva**: Injeção do cabeçalho HTTP `Cache-Control: no-cache, no-store, must-revalidate` na rota do portal no `Caddyfile`.

---

## 🔍 3. Os 14 Pontos Focais do `install.sh` (Mapeamento Completo de Ciclo de Vida)

| ID | Etapa do Ciclo de Vida | Comportamento Condicional (`if [[ "${USE_<MODULO>:-s}" =~ ^[Ss]$ ]]; then`) |
| :---: | :--- | :--- |
| **1** | **Hook de Pré-Voo (Pre-flight)** | Executa validações de dependência e sanitização de permissões antes do boot. |
| **2** | **Criação da Estrutura de Volumes** | Cria os diretórios de persistência em `./volumes/storage_data/{chatwoot,postiz}`. |
| **3** | **Injeção ou Purga Visual de Cards** | Executa `<modulo>_inject_dashboard_card` (se `s`) ou `<modulo>_remove_dashboard_card` (se `n`) via `install_<modulo>.sh`. |
| **4** | **Atribuição de Fallback de Variáveis** | Define o valor default no shell script: `USE_<MODULO>="${USE_<MODULO>:-s}"`. |
| **5** | **Invocação Pré-Boot / Disable** | Invoca as rotinas pré-boot (`install_<modulo>.sh build_structure`) se ativado, ou `disable` se desativado. |
| **6** | **Fusão Dinâmica de Compose** | Inclui `-f docker-compose.<modulo>.yml` na mesclagem `docker compose config` apenas se o módulo estiver ativo. |
| **7** | **Desativação e Remoção de Container** | Se desativado, o hook `disable` executa `docker rm -f ${PREFIX}_<modulo>` para liberar RAM e CPU. |
| **8** | **Purga Dinâmica de Rotas WAF Caddy** | Se desativado, purga os blocos `:porta` do `Caddyfile` e executa reload/recreate do Caddy. |
| **9** | **Contagem de Imagens e Serviços** | Inclui os containers do módulo na contagem total de imagens apenas se ativado. |
| **10** | **Probes Dinâmicas de Prontidão** | Adiciona os containers no array `AGUARDAR_SERVICOS` para esperar o estado `healthy`. |
| **11** | **Regras de Firewall IPTables/IPSet** | Adiciona as regras de libertação de portas em `DOCKER-USER` apenas se o serviço estiver ativo. |
| **12** | **Rotinas de Backup e Criptografia GPG** | Inclui os bancos (`chatwoot_db`, `postiz_db`, `evolution_db`, `nocodb_schema`, `openwebui_db`) e volumes no plano de backup diário (`backup_diario.sh`). |
| **13** | **Hook Pós-Boot de Inicialização de Banco** | Executa migrações de banco (ex: `rails db:chatwoot_prepare` ou `CREATE DATABASE`). |
| **14** | **Renderização do Relatório Final Visual** | Imprime o bloco de credenciais/URLs se ativado, ou `Status: Desativado pelo Operador`. |

---

## 🛑 4. Protocolo de Desativação e Teardown Atômico (`<modulo>_disable`)

Quando um paradigma de armazenamento ou microsserviço é alterado para desativado (`USE_<MODULO>="n"`), o módulo desacoplado executa as seguintes 4 rotinas de teardown:

```bash
<modulo>_disable() {
    echo "➜ [SRE TEARDOWN] Desativando módulo <MODULO>..."
    <modulo>_remove_dashboard_card  # 1. Purga o card visual do index.html
    <modulo>_remove_caddy_routes    # 2. Purga as rotas de proxy reverso do Caddyfile
    sudo docker rm -f "${PREFIX}_<modulo>" 2>/dev/null || true # 3. Remove container do Docker
    # 4. O preparar_compose_monolitico ignora docker-compose.<modulo>.yml no docker compose config
}
```

---

## 🧹 5. Purga Final de Artefatos no Encerramento com Sucesso

Ao final da execução do `install.sh`, somente após a confirmação de sucesso absoluto do provisionamento da stack, os scripts auxiliares e manifestos YAML dos módulos desativados são expurgados do disco:

```bash
# --- SRE PURGE DE ACESSÓRIOS NÃO UTILIZADOS ---
if [[ ! "${USE_<MODULO>:-s}" =~ ^[Ss]$ ]]; then
    echo "➜ [SRE PURGE] Removendo scripts e overlays de acessórios desativados..."
    rm -f "${TARGET_DIR}/core/scripts/install_<modulo>.sh" 2>/dev/null || true
    rm -f "${TARGET_DIR}/core/config/docker-compose.<modulo>.yml" 2>/dev/null || true
fi
```

---

## 💾 6. Matriz de Integração com Scripts Satélites e de Suporte SRE

Para que qualquer nova aplicação desacoplada funcione de forma transparente com o restante do ecossistema, o arquiteto/engenheiro deve obrigatoriamente garantir sua cobertura nos 5 scripts satélites da infraestrutura:

### 1. `backup_diario.sh` (Disaster Recovery & Cold Backup)
- **Dump Relacional Consolidado**: Utilizar `pg_dumpall --clean --if-exists` para incluir automaticamente novas bases lógicas (ex: `<modulo>_db`) ou schemas customizados.
- **Sanity Check Multi-Database**: A query de validação deve testar tanto o `${DB_NAME}` quanto `pg_tables` (`schemaname NOT IN ('pg_catalog', 'information_schema')`).
- **Persistência de Volumes**: Adicionar o empacotamento condicional do volume em `$TMP_BACKUP_DIR/uploads/<modulo>`:
  ```bash
  [[ "${USE_<MODULO>:-s}" =~ ^[Ss]$ ]] && [ -d "${SCRIPT_DIR}/volumes/<modulo>_data" ] && cp -r "${SCRIPT_DIR}/volumes/<modulo>_data" "$TMP_BACKUP_DIR/uploads/<modulo>" 2>/dev/null || true
  ```

### 2. `restore_production.sh` (Restauração Atômica)
- **Reidratação de Banco**: O dump relacional deve ser injetado conectando em `-d postgres` para recriação limpa de todas as bases.
- **Restauração de Volumes**: Adicionar a extração do tarball para o diretório de volumes do módulo:
  ```bash
  [ -d "$TMP_RESTORE_DIR/uploads/<modulo>" ] && cp -r "$TMP_RESTORE_DIR/uploads/<modulo>"/* "${SCRIPT_DIR}/volumes/<modulo>_data/" 2>/dev/null || true
  ```

### 3. `ci_smoke_test.sh` (Portão de Qualidade CI/CD)
- **Provisionamento Antecipado de Banco**: Invocar dinamicamente `provision_db` de todos os scripts antes de subir a malha completa:
  ```bash
  for script in "${SCRIPT_DIR}"/core/scripts/install_*.sh; do
      [ -f "$script" ] && bash "$script" "$SCRIPT_DIR" provision_db 2>/dev/null || true
  done
  ```
- **Probe Condicional no Array `ENDPOINTS`**: Adicionar a verificação HTTP do serviço respeitando a flag de ativação:
  ```bash
  [[ "${USE_<MODULO>:-s}" =~ ^[Ss]$ ]] && ENDPOINTS["<Modulo Nome>"]="http://127.0.0.1:<PORTA_EXTERNA>/healthz"
  ```

### 4. `install_1ia.sh` (Sincronização de IA & Gateway)
- **Core LiteLLM Autônomo**: A atualização do catálogo Big 5 e o restart do LiteLLM são soberanos e ocorrem sempre.
- **Matchmaking Condicional**: O envio de modelos para aplicações consumidoras (ex: Postiz, Chatwoot) deve ser protegido por probe de status (`docker inspect -f '{{.State.Running}}'`).

### 5. `upgrade_stack.sh` (Atualização Declarativa Contínua)
- **Graceful Shutdown Protegido**: Se a aplicação possuir filas em memória ou rotinas assíncronas (como n8n), executar `docker compose stop -t 60 <modulo>` condicionado a `USE_<MODULO>` e container rodando.
- **Migrações SQL no Core Postgres**: As chamadas DDL utilizam o container `${PREFIXO_CONTAINER}_postgres`.

### 6. `autotune.sh` (Motor Autônomo de Dimensionamento de Hardware)
- **Matriz de vCPU (`TOTAL_CPUS`)**: Adicionar as variáveis `CPU_<MODULO>` para os três perfis (`Standard: <= 4 cores`, `Pro: 5-8 cores`, `Enterprise: > 8 cores`).
- **Matriz de RAM (`TOTAL_RAM_MB`)**: Adicionar as variáveis de limites (`MEM_<MODULO>`) e reservas (`RES_<MODULO>`) nos perfis de memória (`Standard: <= 12GB`, `Pro: 13-24GB`, `Enterprise: > 24GB`).
- **Tunings Específicos**: Se a aplicação rodar em Node.js/V8, utilizar a variável `${NODE_HEAP_DEFAULT}` calculada pelo autotune.
- **Persistência Atômica**: Adicionar a chamada `update_env_var` para gravar `CPU_<MODULO>`, `MEM_<MODULO>` e `RES_<MODULO>` no `.env`.

### 7. `preinstall.sh` (Inversão de Controle & Auto-Descoberta Total)
- **Zero Alteração no `preinstall.sh`**: Graças ao padrão IoC (Inversion of Control), o `preinstall.sh` descobre e executa automaticamente as funções `collect_wizard_inputs` e `build_envs` de cada script `install_<modulo>.sh`.
- **Implementação Obrigatória no Script do Módulo**:
  - `collect_wizard_inputs`: Coleta a pergunta interativa (ex: `coletar_sn`), sanitiza a resposta e salva no cache (`save_wizard_cache`).
  - `build_envs`: Formata e grava as variáveis de ambiente (`USE_<MODULO>`, portas, tokens) no arquivo de ambiente de forma declarativa.

---

## 📌 Checklist de Homologação para Novas Aplicações Desacopladas

Ao integrar qualquer nova ferramenta ou microsserviço à stack **daemind.**, valide todos os seguintes itens:

- [x] **Manifesto Declarativo**: Criado `core/config/docker-compose.<modulo>.yml` com `caddy.ports:` (sem portas diretas no host).
- [x] **Script de Ciclo de Vida**: Criado `core/scripts/install_<modulo>.sh` com as **15 funções padronizadas** (incluindo `collect_wizard_inputs` e `build_envs`).
- [x] **Calibragem no Auto-Tuning**: Variáveis `CPU_<MODULO>`, `MEM_<MODULO>` e `RES_<MODULO>` mapeadas no `autotune.sh`.
- [x] **Invocação no Orquestrador**: Inclusão do módulo no array `MODULOS_DESACOPLADOS_TODOS` do `install.sh`.
- [x] **Desabilitação de Cache no Caddy**: `header Cache-Control "no-cache, no-store, must-revalidate"` ativo no portal.
- [x] **Preservação de Inode (`r+`)**: Manipulação do `index.html` via Python 3 `seek(0)` / `truncate()`.
- [x] **Cobertura em Disaster Recovery**: Volume adicionado no `backup_diario.sh` e `restore_production.sh`.
- [x] **Cobertura em Testes CI**: Endpoint adicionado no `ci_smoke_test.sh`.
- [x] **Purga de Artefatos no Encerramento**: Exclusão final de scripts/manifestos caso o módulo não seja instalado.
