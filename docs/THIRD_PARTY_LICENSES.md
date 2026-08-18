# Matriz de Conformidade Jurídica e Licenciamento (Third-Party Licenses)

> **Projeto:** daemind.  
> **Última Atualização:** Agosto / 2026  
> **Escopo:** Mapeamento de Licenças Open Source e Regulamentação Legal de Uso  

---

## ⚖️ Declaração de Conformidade & Modelo de Negócio

O **daemind.** é uma pilha de infraestrutura open source de orquestração distribuída sob a [Licença MIT](../LICENSE). O modelo de negócio do projeto é pautado na prestação de **serviços de implantação, consultoria, customização, integração e suporte técnico dedicado por cliente (1 cliente = 1 stack)**.

Para garantir **boa-fé, transparência e segurança jurídica (compliance)** para clientes, parceiros e contribuidores, este documento estabelece o mapeamento detalhado das licenças dos componentes terceiros orquestrados, suas restrições e as diretrizes operacionais adotadas.

---

## 📊 Matriz de Licenciamento dos Componentes

A tabela abaixo lista os softwares de terceiros orquestrados pelo **daemind.**, a versão de referência utilizada no deploy, sua respectiva licença e o nível de atenção requerido:

| Software / Componente | Imagem Docker Oficial | Versão Interna Auditada | Licença Oficial | Permite Uso Comercial em Serviços? | Nível de Atenção / Risco Jurídico |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **PostgreSQL (`pgvector`)** | `pgvector/pgvector:pg17` | `17.11` | PostgreSQL License | ✅ Sim | 🟢 Nenhum |
| **Temporal Engine** | `temporalio/auto-setup:1.29.7` | `1.29.7` | MIT | ✅ Sim | 🟢 Nenhum |
| **MinIO S3** | `minio/minio:latest` | `2025-09-07T16-13-09` | AGPLv3 | ⚠️ Sim (Sob Regras AGPL) | 🟡 Médio (Reciprocidade de código de core) |
| **Redis** | `redis:8.10-alpine` | `8.10.0` | RSALv2 / SSPLv1 / AGPLv3 | ⚠️ Sim (Para uso como cache/fila da stack) | 🟡 Médio (Atenção às versões e termos) |
| **Postiz Planner** | `ghcr.io/gitroomhq/postiz-app:v2.23.0` | `2.23.0` | AGPLv3 | ⚠️ Sim (Sob Regras AGPL) | 🟡 Médio (Reciprocidade de código de core) |
| **Caddy WAF** | `caddy:2.11.4-alpine` | `2.11.4` | Apache 2.0 | ✅ Sim | 🟢 Nenhum |
| **LiteLLM (AI Gateway)** | `ghcr.io/berriai/litellm:main-latest` | `1.98.0` | Apache 2.0 (OSS) | ✅ Sim | 🟢 Low (Recursos Enterprise são à parte) |
| **PgBouncer** | `edoburu/pgbouncer:v1.25.2-p0` | `1.25.2-p0` | ISC-like | ✅ Sim | 🟢 Nenhum |
| **NocoDB** | `nocodb/nocodb:2026.08.0` | `2026.08.0` | AGPLv3 | ⚠️ Sim (Sob Regras AGPL) | 🟡 Médio (Reciprocidade de código de core) |
| **Open WebUI** | `ghcr.io/open-webui/open-webui:main` | `0.11.0` | BSD-3-Clause | ✅ Sim | 🟢 Nenhum |
| **Chatwoot CE** | `chatwoot/chatwoot:v4.16.2` | `4.16.2` | MIT | ✅ Sim | 🟢 Nenhum |
| **Evolution API** | `evoapicloud/evolution-api:v2.3.7` | `2.3.7` | Apache 2.0 | ✅ Sim | 🟢 Nenhum |
| **n8n Community Edition** | `n8nio/n8n:2.34.6` | `2.34.6` | Sustainable Use License (SUL) | ⚠️ Sim (Prestação de Serviços / Auto-hospedagem) | 🔴 Alto (Proibido criar produto SaaS concorrente direto) |

---

## 🔍 Análise Detalhada dos Componentes Relevantes

### 1. n8n Community Edition (Sustainable Use License - SUL)
* **Status:** 🔴 **Principal Ponto de Atenção**
* **Compreensão Legal:** O n8n não utiliza uma licença Open Source tradicional (OSI-approved), mas sim a **Sustainable Use License (SUL)**.
* **O que é PERMITIDO no modelo daemind.:**
  * Instalar e configurar instâncias dedicadas do n8n para clientes (1 cliente = 1 ambiente).
  * Prestar consultoria, treinamento, suporte e desenvolvimento de workflows/nodes personalizados.
  * Auto-hospedar e gerenciar a infraestrutura em nome do cliente.
* **O que é PROIBIDO:**
  * Comercializar o n8n como um serviço SaaS multi-tenant comercial ou produto concorrente direto da plataforma oficial do n8n (ex: *"n8n Cloud do Wellington"*).
* **Diretriz de Compliance:** O **daemind.** apenas instala e provisiona o n8n em infraestrutura própria do cliente ou dedicada a ele, sem praticar concorrência direta de plataforma gerenciada.

### 2. Componentes AGPLv3 (MinIO, NocoDB, Postiz)
* **Status:** 🟡 **Atenção Intermediária (Copyleft Forte de Rede)**
* **Compreensão Legal:** A licença GNU AGPLv3 não impede a prestação de serviços cobrados ou uso comercial. Contudo, ela possui a chamada "cláusula de rede": se o código do próprio software for alterado e disponibilizado aos usuários via rede/HTTP, o código-fonte modificado deve ser aberto.
* **Diretriz de Compliance:**
  * O **daemind.** utiliza os contêineres originais do MinIO, NocoDB e Postiz sem alterar o código-fonte interno desses projetos.
  * Criação de scripts externos de orquestração (`install.sh`), workflows, tabelas ou chamadas via API REST/S3 não configuram modificação de código interno sob AGPL.
  * Caso qualquer modificação seja feita diretamente no código-fonte desses projetos, o **daemind.** se compromete a disponibilizar as alterações sob a mesma licença.

### 3. Redis (Licenciamento Dual / RSALv2 / SSPLv1 / AGPLv3)
* **Status:** 🟡 **Atenção a Versões Fixadas**
* **Compreensão Legal:** A partir do Redis 7.4/8.0, o licenciamento transicionou do tradicional BSD para licenças de fonte disponível (RSALv2, SSPLv1) e AGPLv3.
* **Diretriz de Compliance:** O Redis é empregado no **daemind.** exclusivamente como componente interno de infraestrutura para cache e controle de filas em memória do Postiz e da Evolution API. As versões estão explicitamente fixadas na matriz SRE BOM para evitar incertezas regulatórias.

### 4. Componentes Enterprise Proprietários (LiteLLM, Chatwoot, etc.)
* **Status:** 🟢 **Uso Estrito da Edição Open Source / Community**
* **Diretriz de Compliance:** O **daemind.** faz uso estrito das versões comunitárias/open source (LiteLLM Gateway OSS e Chatwoot Community Edition MIT). Recursos enterprise (como SSO SAML avançado, auditoria corporativa proprietária ou suporte pago do fabricante) são opcionais e devem ser contratados diretamente com os respectivos mantenedores, caso o cliente final necessite.

---

## 📌 Isenção de Responsabilidade Legal (Disclaimer)

> [!NOTE]
> Este documento possui caráter **técnico-informativo de engenharia e governança de software**. O **daemind.** não realiza transferência ou alteração de licenças de terceiros; cada software orquestrado permanece integralmente sob a licença do seu autor original. Recomendamos que usuários e clientes corporativos consultem seus respectivos departamentos jurídicos para validação dos termos específicos de seus modelos de negócio.
