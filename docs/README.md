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
| **Hermes Agent** | Autonomous Agent, Dashboard & Code Sandbox | `hermes.spencer.lan`, `ai.spencer.lan`, `hermes-api.spencer.lan` | [Hermes Guide](hermes.md) |
| **Hindsight** | Agent Long-Term Memory Engine | `:8888` (API), `hindsight.spencer.lan` (:9999) | [Hindsight Guide](hindsight.md) |
| **pgvector** | Unified Vector & Relational Database | `:5432` (Internal `db` network) | [pgvector Guide](pgvector.md) |
| **Firecrawl Stack** | Web Scraper, Crawler & Search | `:3002` (Internal `ai` & `redis` networks) | [Firecrawl Guide](firecrawl.md) |
| **SearXNG** | Metasearch Engine | `:8080` (Internal `ai` & `redis` networks) | [SearXNG Guide](searxng.md) |
| **Valkey** | In-Memory Cache & Rate Limiter | `:6379` (Internal `redis` network) | [Valkey Guide](valkey.md) |
| **Authentik** | Centralized IAM, SSO, OIDC & Outposts | `sso.spencer.lan`, `login.spencer.lan` (:9000) | [Authentik Guide](authentik.md) |
| *Open WebUI Stack* | *Archived Legacy Stack* | *Retired (Open WebUI, postgres, open-terminal, browserless)* | [Legacy Stack Archive](archive/open-webui-legacy-stack.md) |

---

## 🌐 Network Topologies

1. **`net1`**: Traefik edge network connecting reverse proxy to exposed web services (Hermes Gateway, Hermes Dashboard, Hindsight UI, LiteLLM, Traefik API).
2. **`ai`**: Private high-speed network for inter-service communication (Hermes, Hindsight, Ollama, LiteLLM, SearXNG, Firecrawl).
3. **`db`**: Isolated database network hosting PostgreSQL instances (`pgvector`). Any service needing vector or relational database access connects to `db`.
4. **`redis`**: Dedicated caching network shared between Valkey, SearXNG, and Firecrawl.
