# Spencer's Homelab - Service Documentation Index

This directory contains in-depth documentation, architecture designs, configuration references, and operational guides for all services deployed in the homelab stack.

---

## 📚 Service Documentation

| Service | Category | Ports & Access | Documentation |
|---|---|---|---|
| **Traefik** | Reverse Proxy & Ingress | `:80`, `:443` (Hosts `traefik.spencer.lan`) | [Traefik Guide](file:///data/homelab/docs/traefik.md) |
| **Ollama** | LLM Engine (GPU Accelerated) | `:11434` (Internal `ai` network) | [Ollama Guide](file:///data/homelab/docs/ollama.md) |
| **Open WebUI** | AI Chat & Workspace Interface | `ai.spencer.lan` via Traefik | [Open WebUI Guide](file:///data/homelab/docs/open-webui.md) |
| **PostgreSQL / pgvector (Legacy)** | Relational & Vector Database (Open WebUI) | `:5432` (Internal `db` network) | [Postgres Guide](file:///data/homelab/docs/postgres.md) |
| **pgvector (Standalone)** | Dedicated Vector & DB (Hindsight & Services) | `:5432` (Internal `db` network) | [pgvector Guide](file:///data/homelab/docs/pgvector.md) |
| **Hermes Agent** | Autonomous Agent & Dashboard | `hermes.spencer.lan` & `hermes-dashboard.spencer.lan` | [Hermes Guide](file:///data/homelab/docs/hermes.md) |
| **Firecrawl Stack** | Web Scraper, Crawler & Search | `:3002` (Internal `ai` & `redis` networks) | [Firecrawl Guide](file:///data/homelab/docs/firecrawl.md) |
| **SearXNG** | Metasearch Engine | `:8080` (Internal `ai` & `redis` networks) | [SearXNG Guide](file:///data/homelab/docs/searxng.md) |
| **Valkey** | In-Memory Cache & Rate Limiter | `:6379` (Internal `redis` network) | [Valkey Guide](file:///data/homelab/docs/valkey.md) |
| **Browserless Chrome** | Headless Browser Automation | `:3000` (Internal `ai` network) | [Browserless Guide](file:///data/homelab/docs/browserless.md) |
| **Open Terminal** | Sandboxed Code Execution | `:8000` (Internal `ai` network) | [Open Terminal Guide](file:///data/homelab/docs/open-terminal.md) |

---

## 🌐 Network Topologies

1. **`net1`**: Traefik edge network connecting reverse proxy to exposed web services (Open WebUI, Hermes Gateway, Hermes Dashboard, Traefik API).
2. **`ai`**: Private high-speed network for inter-service communication (Hermes, Ollama, Open WebUI, SearXNG, Firecrawl, Browserless, Open Terminal).
3. **`db`**: Isolated database network hosting PostgreSQL instances (`db`, `pgvector`). Any service needing vector or relational database access connects to `db`.
4. **`redis`**: Dedicated caching network shared between Valkey, SearXNG, and Firecrawl.
