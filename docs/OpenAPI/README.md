# Catálogo e Governança de Especificações OpenAPI 3.0

> **Última Atualização:** 31 de Agosto de 2026  
> **Total de Plataformas:** 74 (14 Aplicações Locais + 60 Serviços Externos)  
> **Total de Endpoints Validados:** 24.577 endpoints

Este diretório centraliza o catálogo soberano de contratos de API no padrão **OpenAPI 3.0.3**, estruturado em conformidade com as diretrizes de governança e integração do projeto.

---

## 🏗️ Estrutura do Diretório

O catálogo está dividido em duas categorias principais:

```text
docs/OpenAPI/
├── README.md               # Este catálogo e documentação técnica
├── apps/                   # Contratos das aplicações locais (Self-Hosted / Stack Interna)
└── services/               # Contratos dos serviços externos, gateways, ERPs e marketplaces integrados
```

---

## ⚙️ Arquitetura de Geração e Consolidação Técnica

As especificações são geradas e sincronizadas através de um pipeline de engenharia de dados e compilação de contratos com os seguintes princípios:

### 1. Ingestão Híbrida e Extração Semântica
- **Detecção de Especificações Oficiais**: O pipeline identifica e desembrulha especificações nativas (`Swagger 2.0`, `OpenAPI 3.0.x`, `Postman Collections v2.1`).
- **Análise Semântica de Documentação**: O conteúdo textual (páginas técnicas, tabelas de recursos e payloads cURL) é analisado por expressões regulares lineares de alta precisão para identificar endpoints e parâmetros adicionais.
- **Merge Aditivo Não-Destrutivo**: A especificação nativa atua como esquema estrutural e é enriquecida aditivamente com rotas e exemplos identificados na documentação textual, garantindo que atualizações publicadas em páginas não sejam omitidas.

### 2. Governança e Injeção de Padrões OpenAPI 3.0
Independentemente da fonte original, todos os contratos passam por um processo de normalização que injeta:

- 🛡️ **Segurança Padronizada (`components.securitySchemes`)**:
  - `BearerAuth` (HTTP Bearer / JWT Token)
  - `ApiKeyAuth` (Header `Authorization` / API Key)
  - `OAuth2` (Fluxos de autorização para plataformas compatíveis)
- ⏱️ **Controle de Vazão e Limites (`x-ratelimit`)**:
  - Metadados formais de taxa de requisição (`requests_per_minute`, `burst_limit`) e cabeçalhos de resposta HTTP (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`).
- 🔁 **Políticas de Resiliência (`x-retry-policy`)**:
  - Política de retentativas automáticas (`max_retries: 3`), códigos de erro elegíveis (`429`, `500`, `502`, `503`, `504`), estratégia de backoff exponencial com jitter e suporte a chaves de idempotência (`Idempotency-Key` / `X-Idempotency-Key`).
- 🚨 **Tratamento de Erros RFC 7807/9457 (`components.schemas.ErrorResponse`)**:
  - Estrutura padronizada de resposta de erro contendo `type`, `title`, `status`, `detail`, `instance` e `errors[]`, aplicada às respostas HTTP padrão (`400`, `401`, `403`, `404`, `429`, `500`).
- 🔔 **Contratos de Eventos Assíncronos (`webhooks`)**:
  - Definição estruturada de payloads e notificações assíncronas enviadas pelas plataformas.

---

## 📦 1. Aplicações Locais da Stack (`docs/OpenAPI/apps/`)

Aplicações e serviços self-hosted que compõem a infraestrutura interna do ambiente.

| Aplicação / Módulo | Arquivo de Contrato | Título Oficial da API | Versão | Endpoints | Base URL Local |
| :--- | :--- | :--- | :---: | :---: | :--- |
| **Chatwoot** | [`openapi_chatwoot.json`](apps/openapi_chatwoot.json) | Chatwoot Omnichannel API v1 | `1.0.0` | 286 | `http://chatwoot:3000` |
| **Docling** | [`openapi_docling.json`](apps/openapi_docling.json) | Docling Document OCR & PDF Processing API | `1.0.0` | 35 | `http://docling:5001` |
| **Evolution API** | [`openapi_evolution.json`](apps/openapi_evolution.json) | Evolution WhatsApp API v2.3 | `1.0.0` | 913 | `http://evolution:8080` |
| **Listmonk** | [`openapi_listmonk.json`](apps/openapi_listmonk.json) | Listmonk Newsletter & Mailing API | `1.0.0` | 107 | `http://listmonk:9000` |
| **LiteLLM** | [`openapi_litellm.json`](apps/openapi_litellm.json) | LiteLLM AI Gateway & Router API | `0.1.0` | 579 | `http://litellm:4000` |
| **Metabase** | [`openapi_metabase.json`](apps/openapi_metabase.json) | Metabase Business Intelligence REST API | `1.0.0` | 654 | `http://metabase:3000` |
| **MinIO (S3)** | [`openapi_minio.json`](apps/openapi_minio.json) | MinIO S3 Compatible Object Storage REST API | `2006-03-01` | 914 | `http://s3minio:9000` |
| **n8n** | [`openapi_n8n.json`](apps/openapi_n8n.json) | n8n Workflow Automation Public REST API | `1.0.0` | 18 | `http://n8n:5678` |
| **NocoDB** | [`openapi_nocodb.json`](apps/openapi_nocodb.json) | NocoDB Smart Spreadsheet Database API v2 | `0.200.0` | 244 | `http://nocodb:8080` |
| **Ollama** | [`openapi_ollama.json`](apps/openapi_ollama.json) | Ollama Local LLM Runner API | `1.0.0` | 66 | `http://ollama:11434` |
| **Open WebUI** | [`openapi_openwebui.json`](apps/openapi_openwebui.json) | Open WebUI Platform REST API | `1.0.0` | 68 | `http://openwebui:8080` |
| **Postiz** | [`openapi_postiz.json`](apps/openapi_postiz.json) | Postiz Social Media Scheduling API | `1.0.0` | 102 | `http://postiz:3000` |
| **SearXNG** | [`openapi_searxng.json`](apps/openapi_searxng.json) | SearXNG Meta Search Engine REST API | `1.0.0` | 3 | `http://searxng:8080` |
| **Shlink** | [`openapi_shlink.json`](apps/openapi_shlink.json) | Shlink URL Shortener REST API v3 | `3.0.0` | 22 | `http://shlink:8080` |

---

## 🌐 2. Serviços Externos & Parceiros (`docs/OpenAPI/services/`)

Plataformas de E-Commerce, Marketplaces, Gateways de Pagamento, ERPs, Logística e Delivery integrados ao ecossistema.

### 🛒 E-Commerce, Plataformas de Loja & Hubs
| Plataforma | Arquivo de Contrato | Título Oficial da API | Endpoints | Endpoint / Base URL Oficial |
| :--- | :--- | :--- | :---: | :--- |
| **AnyMarket** | [`openapi_anymarket.json`](services/openapi_anymarket.json) | AnyMarket Hub Marketplace API | 1.286 | `https://api.anymarket.com.br/v2` |
| **Bagy / Dooca** | [`openapi_bagy_dooca.json`](services/openapi_bagy_dooca.json) | Bagy & Dooca E-Commerce REST API | 38 | `https://api.dooca.store` |
| **Bling ERP** | [`openapi_bling.json`](services/openapi_bling.json) | Bling ERP REST API v3 | 166 | `https://api.bling.com.br/v3` |
| **Loja Integrada** | [`openapi_lojaintegrada.json`](services/openapi_lojaintegrada.json) | Loja Integrada REST API v1 | 675 | `https://api.awsli.com.br` |
| **Nuvemshop** | [`openapi_nuvemshop.json`](services/openapi_nuvemshop.json) | Nuvemshop / Tiendanube REST API | 336 | `https://api.nuvemshop.com.br/v1` |
| **Olist** | [`openapi_olist.json`](services/openapi_olist.json) | Olist Pax & Marketplace API | 24 | `https://api.olist.com` |
| **Shopify** | [`openapi_shopify.json`](services/openapi_shopify.json) | Shopify Admin REST API | 8.976 | `https://myshopify.com/admin/api` |
| **Shoper** | [`openapi_shopper.json`](services/openapi_shopper.json) | Shopper Supermercado Online & Abastecimento API | 256 | `https://api.shopper.com.br/v1` |
| **Simplo7** | [`openapi_simplo7.json`](services/openapi_simplo7.json) | Simplo7 / Dloja Virtual REST API | 64 | `https://api.simplo7.com.br` |
| **SkyHub / Americanas** | [`openapi_skyhub.json`](services/openapi_skyhub.json) | Americanas / SkyHub Marketplace API | 26 | `https://api.skyhub.com.br` |
| **Tiny ERP** | [`openapi_tiny.json`](services/openapi_tiny.json) | Tiny ERP REST API v3 | 113 | `https://api.tiny.com.br/api2` |
| **Tray E-Commerce** | [`openapi_tray.json`](services/openapi_tray.json) | Tray E-Commerce Open API | 59 | `https://api.tray.com.br` |
| **Vnda** | [`openapi_vnda.json`](services/openapi_vnda.json) | Vnda E-Commerce Open API | 752 | `https://api.vnda.com.br/api/v2` |
| **VTEX** | [`openapi_vtex.json`](services/openapi_vtex.json) | VTEX E-Commerce Platform REST API | 1.136 | `https://vtex.com.br/api` |
| **WooCommerce** | [`openapi_woocommerce.json`](services/openapi_woocommerce.json) | WooCommerce REST API v3 | 957 | `https://seusite.com.br/wp-json/wc/v3` |
| **Yampi** | [`openapi_yampi.json`](services/openapi_yampi.json) | Yampi Checkout & E-Commerce API | 312 | `https://api.dooki.com.br/v2` |

### 🏬 Marketplaces & Varejo
| Plataforma | Arquivo de Contrato | Título Oficial da API | Endpoints | Endpoint / Base URL Oficial |
| :--- | :--- | :--- | :---: | :--- |
| **AliExpress** | [`openapi_aliexpress.json`](services/openapi_aliexpress.json) | AliExpress Open Platform API | 27 | `https://api-sg.aliexpress.com` |
| **Amazon SP-API** | [`openapi_amazon_sp.json`](services/openapi_amazon_sp.json) | Amazon Selling Partner (SP-API) REST API | 104 | `https://sellingpartnerapi-na.amazon.com` |
| **Dafiti / GFG** | [`openapi_dafiti.json`](services/openapi_dafiti.json) | Dafiti, Kanui & Tricae Marketplace API | 1 | `https://sellercenter-api.dafiti.com.br` |
| **KaBuM!** | [`openapi_kabum.json`](services/openapi_kabum.json) | KaBuM! Marketplace HubScore API | 31 | `https://api.kabum.com.br` |
| **Leroy Merlin** | [`openapi_leroymerlin.json`](services/openapi_leroymerlin.json) | Leroy Merlin Brasil Marketplace API | 3 | `https://api.leroymerlin.com.br` |
| **MadeiraMadeira** | [`openapi_madeiramadeira.json`](services/openapi_madeiramadeira.json) | MadeiraMadeira Marketplace & Móveis API | 66 | `https://api.madeiramadeira.com.br/v1` |
| **Magalu** | [`openapi_magalu.json`](services/openapi_magalu.json) | Magalu Marketplace Open API | 116 | `https://api.magalu.com` |
| **Mercado Livre** | [`openapi_mercadolivre.json`](services/openapi_mercadolivre.json) | Mercado Livre Marketplace API | 208 | `https://api.mercadolibre.com` |
| **Mobly** | [`openapi_mobly.json`](services/openapi_mobly.json) | Mobly Móveis & Decoração Open API | 32 | `https://api.mobly.com.br` |
| **Netshoes / Zattini** | [`openapi_netshoes.json`](services/openapi_netshoes.json) | Netshoes & Zattini (Magalu) API | 47 | `https://api.netshoes.com.br` |
| **OLX Brasil** | [`openapi_olx.json`](services/openapi_olx.json) | OLX Brasil Marketplace & Integradores API | 26 | `https://api.olx.com.br` |
| **SHEIN** | [`openapi_shein.json`](services/openapi_shein.json) | SHEIN Open Platform Marketplace API | 20 | `https://openapi.sheincorp.com` |
| **Shopee** | [`openapi_shopee.json`](services/openapi_shopee.json) | Shopee Open Platform API v2 | 5 | `https://partner.shopeemobile.com/api/v2` |
| **TikTok Shop** | [`openapi_tiktokshop.json`](services/openapi_tiktokshop.json) | TikTok Shop Open API | 8 | `https://open-api.tiktokglobalshop.com` |

### 💳 Gateways de Pagamento, Checkout & Open Finance
| Plataforma | Arquivo de Contrato | Título Oficial da API | Endpoints | Endpoint / Base URL Oficial |
| :--- | :--- | :--- | :---: | :--- |
| **Asaas** | [`openapi_asaas.json`](services/openapi_asaas.json) | Asaas Payment Gateway API v3 | 752 | `https://api.asaas.com/v3` |
| **Efí Bank (Gerencianet)** | [`openapi_efi.json`](services/openapi_efi.json) | Efí Bank PIX & Open Finance API | 297 | `https://pix.sejaefi.com.br` |
| **Mercado Pago** | [`openapi_mercadopago.json`](services/openapi_mercadopago.json) | Mercado Pago Payment Gateway API | 36 | `https://api.mercadopago.com` |
| **Pagar.me (Stone)** | [`openapi_pagarme.json`](services/openapi_pagarme.json) | Pagar.me Stone Payment Gateway API | 448 | `https://api.pagar.me/core/v5` |
| **PagBank (PagSeguro)** | [`openapi_pagbank.json`](services/openapi_pagbank.json) | PagBank Open Payment API v4 | 64 | `https://api.pagseguro.com` |
| **Stripe** | [`openapi_stripe.json`](services/openapi_stripe.json) | Stripe Global Payment Gateway API | 1.915 | `https://api.stripe.com/v1` |

### 🚚 Logística, Fretes & Rastreio
| Plataforma | Arquivo de Contrato | Título Oficial da API | Endpoints | Endpoint / Base URL Oficial |
| :--- | :--- | :--- | :---: | :--- |
| **Correios** | [`openapi_correios.json`](services/openapi_correios.json) | Correios Web Services (CWS) Oficial API | 5 | `https://api.correios.com.br` |
| **Frenet** | [`openapi_frenet.json`](services/openapi_frenet.json) | Frenet Shipping Gateway API | 6 | `https://api.frenet.com.br` |
| **Jadlog (DPDgroup)** | [`openapi_jadlog.json`](services/openapi_jadlog.json) | Jadlog DPDgroup Express Tracking & Shipping API | 11 | `https://www.jadlog.com.br/embarcador/api` |
| **Loggi** | [`openapi_loggi.json`](services/openapi_loggi.json) | Loggi Express & Entrega Urbana API | 40 | `https://api.loggi.com/v1` |
| **Melhor Envio** | [`openapi_melhorenvio.json`](services/openapi_melhorenvio.json) | Melhor Envio Shipping & Logistics API v2 | 121 | `https://melhorenvio.com.br/api/v2` |

### 🍔 Delivery, Restaurantes & Mercados
| Plataforma | Arquivo de Contrato | Título Oficial da API | Endpoints | Endpoint / Base URL Oficial |
| :--- | :--- | :--- | :---: | :--- |
| **99Food** | [`openapi_99food.json`](services/openapi_99food.json) | 99Food Merchant & Courier API | 76 | `https://api.99app.com/food` |
| **Anota AI** | [`openapi_anotaai.json`](services/openapi_anotaai.json) | Anota AI Atendente Virtual & Delivery API | 26 | `https://api.anota.ai/v1` |
| **Delivery Much** | [`openapi_deliverymuch.json`](services/openapi_deliverymuch.json) | Delivery Much Franquias API | 19 | `https://api.deliverymuch.com.br` |
| **Goomer** | [`openapi_goomer.json`](services/openapi_goomer.json) | Goomer Cardápio Digital & Totem API | 51 | `https://api.goomer.com.br/v1` |
| **iFood** | [`openapi_ifood.json`](services/openapi_ifood.json) | iFood Merchant & Delivery Open API | 155 | `https://merchant-api.ifood.com.br` |
| **KeeTa (Meituan)** | [`openapi_keeta.json`](services/openapi_keeta.json) | KeeTa (Meituan) Food Delivery Open API | 40 | `https://api.keeta.com` |
| **Rappi** | [`openapi_rappi.json`](services/openapi_rappi.json) | Rappi Partners & Delivery API | 116 | `https://api.rappi.com` |

### 🎓 Infoprodutos, Automotivo, Viagens & Utilitários
| Plataforma | Arquivo de Contrato | Título Oficial da API | Endpoints | Endpoint / Base URL Oficial |
| :--- | :--- | :--- | :---: | :--- |
| **BlaBlaCar** | [`openapi_blablacar.json`](services/openapi_blablacar.json) | BlaBlaCar Carpooling & Bus Open API | 2 | `https://public-api.blablacar.com` |
| **BrasilAPI** | [`openapi_brasilapi.json`](services/openapi_brasilapi.json) | BrasilAPI (CEP, CNPJ, Bancos, DDD, FIPE, Feriados) | 115 | `https://brasilapi.com.br/api` |
| **Hotmart** | [`openapi_hotmart.json`](services/openapi_hotmart.json) | Hotmart Developers & Webhooks API v1 | 275 | `https://developers.hotmart.com/payments/api/v1` |
| **iCarros (Itaú)** | [`openapi_icarros.json`](services/openapi_icarros.json) | iCarros (Itaú) Anúncios Automotivos API | 58 | `https://api.icarros.com.br` |
| **Kiwify** | [`openapi_kiwify.json`](services/openapi_kiwify.json) | Kiwify Infoprodutos & Checkout API | 63 | `https://api.kiwify.com.br` |
| **ViaCEP** | [`openapi_viacep.json`](services/openapi_viacep.json) | ViaCEP Consulta de CEP Pública REST API | 3 | `https://viacep.com.br/ws` |
| **Webmotors** | [`openapi_webmotors.json`](services/openapi_webmotors.json) | Webmotors Anúncios de Veículos & Carros API | 2 | `https://api.webmotors.com.br` |
