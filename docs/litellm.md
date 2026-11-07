# LiteLLM Proxy - Centralized Homelab LLM Router

LiteLLM Proxy provides a unified, OpenAI-compatible proxy gateway and router for all local and external large language models in Spencer's Homelab.

---

## 🎯 Overview & Architecture

* **Role**: Centralized LLM dispatch gateway, model router, and token/spend tracker.
* **Container Name**: `litellm`
* **Image**: `ghcr.io/berriai/litellm:main-latest`
* **Networks**:
  * `net1`: Traefik reverse proxy ingress (`llm.spencer.lan`).
  * `ai`: Internal communication with Ollama (`ollama:11434`), MoMoE (`momoe:8080`), and Open WebUI.
  * `db`: PostgreSQL connection to `pgvector` for key management, spend tracking, and audit logging.
* **External Ingress & Ports**:
  * API Endpoint: `https://llm.spencer.lan/v1`
  * Admin & Playground UI: `https://llm.spencer.lan/ui`
  * Internal Service Port: `http://litellm:4000/v1`

```mermaid
graph TD
    Traefik[Traefik Proxy] -->|llm.spencer.lan| LiteLLM[LiteLLM Proxy :4000]
    
    subgraph Clients
        OpenWebUI[Open WebUI] -->|http://litellm:4000/v1| LiteLLM
        LAN[LAN Clients / IDEs] -->|https://llm.spencer.lan/v1| LiteLLM
    end

    subgraph Backends & Storage
        LiteLLM -->|Local GPU Inference| Ollama[Ollama :11434]
        LiteLLM -->|Hybrid MoE Inference 64k| MoMoE[MoMoE :8080]
        LiteLLM -->|Keys, Spend & Audit DB| PgVector[(pgvector :5432)]
        LiteLLM -.->|Optional Cloud Fallbacks| Cloud[Groq / OpenRouter / DeepSeek]
    end
```

---

## ⚙️ Model Catalog & Routing

Defined in [`litellm/config.yaml`](file:///data/homelab/litellm/config.yaml):

| Model Name / Alias | Target Backend | Model Type | Capabilities |
|---|---|---|---|
| `gemma4:12b` | `ollama_chat/gemma4:12b` via `http://ollama:11434` | Chat / Reasoning | GPU-accelerated local instruction & tool calling (64k context) |
| `default` | `ollama_chat/gemma4:12b` via `http://ollama:11434` | Chat Alias | Default homelab fallback model |
| `qwen2.5:14b` | `ollama_chat/qwen2.5:14b` via `http://ollama:11434` | Chat / Reasoning | GPU-accelerated local instruction & tool calling (32k context) |
| `ornith-1.5-35b` / `momoe` | `openai/ornith-1.5-35b-a3b-iq4_xs` via `http://momoe:8080/v1` | Hybrid MoE (35B-A3B) | Agentic coding, deep reasoning & web research via MoMoE (64k KV streaming in RAM + MTP drafting) |
| `nomic-embed-text` | `ollama/nomic-embed-text` via `http://ollama:11434` | Embeddings | High-performance text vector embeddings |
| `groq/llama-3.3-70b-versatile` | Groq Cloud (`GROQ_API_KEY`) | Ultra-Fast Cloud | Fast cloud fallback when local GPU is saturated |
| `openrouter/auto` | OpenRouter (`OPENROUTER_API_KEY`) | Auto-Routed Cloud | Flexible fallback routing to leading foundation models |
| `deepseek/deepseek-chat` | DeepSeek (`DEEPSEEK_API_KEY`) | Cost-Efficient Cloud | Large-context coding and reasoning |

---

## 🔒 Security, Authentication & Admin UI

1. **Master Key**:
   The admin key configured in `.env` (`LITELLM_MASTER_KEY`) grants full access to the API and Admin UI at `https://llm.spencer.lan/ui`.
2. **Authentik OpenID Connect (OIDC) Single Sign-On**:
   LiteLLM is natively integrated with Authentik IAM via standard Generic OIDC:
   - **Provider Name**: `LiteLLM Proxy OIDC` (`client_id: litellm`)
   - **Authorization Endpoint**: `https://<sso-public-domain>/application/o/authorize/`
   - **Token Endpoint**: `https://<sso-public-domain>/application/o/token/`
   - **Userinfo Endpoint**: `https://<sso-public-domain>/application/o/userinfo/`
   - **Redirect URI**: `https://llm.spencer.lan/sso/callback`
   - **Login Initiation**: `https://llm.spencer.lan/sso/key/generate`
   - **Scopes**: `openid profile email`
   - **User ID Claim**: `preferred_username` (or `sub`)
   Users logging into `https://llm.spencer.lan/ui` authenticate through Authentik without exposing credentials directly to the proxy.
3. **Client API Keys**:
   You can create scoped, rate-limited, and budget-capped API keys for specific clients or users directly from the Web UI or via the `/key/generate` endpoint.
4. **Database Schema & Dynamic Management**:
   All user profiles, keys, dynamically managed models (`store_model_in_db: true`), and spend logs with full prompt storage (`store_prompts_in_spend_logs: true`) persist in the dedicated `litellm` database on `pgvector`.

---

## 🔌 Client Integration

### 1. Pointing Open WebUI to LiteLLM
Open WebUI routes all chat generations and embeddings through LiteLLM over the internal `ai` Docker network.
- **In `docker-compose.yaml`**:
  ```yaml
  environment:
    - OPENAI_API_BASE_URL=http://litellm:4000/v1
    - OPENAI_API_KEY=${LITELLM_MASTER_KEY}
    - RAG_EMBEDDING_OPENAI_API_BASE_URL=http://litellm:4000/v1
    - RAG_EMBEDDING_OPENAI_API_KEY=${LITELLM_MASTER_KEY}
    - RAG_EMBEDDING_MODEL=nomic-embed-text
  depends_on:
    litellm:
      condition: service_healthy
  ```

---

## 📁 Mounted Volumes & Configuration Files

| Host Path | Container Path | Purpose |
|---|---|---|
| `./litellm/config.yaml` | `/etc/litellm/config.yaml:ro` | Declarative model catalog, router rules, and settings |

