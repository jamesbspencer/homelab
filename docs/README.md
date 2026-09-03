# Spencer's Homelab - Service Documentation Index

This directory contains in-depth documentation, architecture designs, configuration references, and operational guides for all services deployed in the homelab stack.

---

## 📚 Service Documentation

| Service | Category | Ports & Access | Documentation |
|---|---|---|---|
| **Traefik** | Reverse Proxy & Ingress | `:80`, `:443` (Hosts `traefik.spencer.lan`) | [Traefik Guide](traefik.md) |
| **CrowdSec** | Intrusion Detection & Traefik Bouncer | `:8080` (Internal `net1` network) | [CrowdSec Guide](crowdsec.md) |
| **LiteLLM Proxy** | LLM Router & Spend Gateway | `llm.spencer.lan` (:4000) | [LiteLLM Guide](litellm.md) |
| **Ollama** | LLM Engine (GPU Accelerated) | `:11434` (Internal `ai` network) | [Ollama Guide](ollama.md) |
| **Open WebUI** | AI Chat & Workspace Interface | `ai.spencer.lan` via Traefik | [Open WebUI Guide](open-webui.md) |
| **Hermes Agent** | Autonomous Agent, Dashboard & Code Sandbox | `hermes.spencer.lan` & `hermes-api.spencer.lan` | [Hermes Guide](hermes.md) |
| **Hindsight** | Agent Long-Term Memory Engine | `:8888` (API), `hindsight.spencer.lan` (:9999) | [Hindsight Guide](hindsight.md) |
| **PostgreSQL / pgvector (Legacy)** | Relational & Vector Database (Open WebUI) | `:5432` (Internal `db` network) | [Postgres Guide](postgres.md) |
| **pgvector (Standalone)** | Dedicated Vector & DB (Hindsight & Services) | `:5432` (Internal `db` network) | [pgvector Guide](pgvector.md) |
| **Firecrawl Stack** | Web Scraper, Crawler & Search | `:3002` (Internal `ai` & `redis` networks) | [Firecrawl Guide](firecrawl.md) |
| **SearXNG** | Metasearch Engine | `:8080` (Internal `ai` & `redis` networks) | [SearXNG Guide](searxng.md) |
| **Valkey** | In-Memory Cache & Rate Limiter | `:6379` (Internal `redis` network) | [Valkey Guide](valkey.md) |
| **Browserless Chrome** | Headless Browser Automation | `:3000` (Internal `ai` network) | [Browserless Guide](browserless.md) |
| **Open Terminal** | Sandboxed Code Execution | `:8000` (Internal `ai` network) | [Open Terminal Guide](open-terminal.md) |

---

## 🌐 Network Topologies

1. **`net1`**: Traefik edge network connecting reverse proxy to exposed web services (Open WebUI, Hermes Gateway, Hermes Dashboard, Hindsight UI, Traefik API).
2. **`ai`**: Private high-speed network for inter-service communication (Hermes, Hindsight, Ollama, Open WebUI, SearXNG, Firecrawl, Browserless, Open Terminal).
3. **`db`**: Isolated database network hosting PostgreSQL instances (`db`, `pgvector`). Any service needing vector or relational database access connects to `db`.
4. **`redis`**: Dedicated caching network shared between Valkey, SearXNG, and Firecrawl.
