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
| **Memlord** | MCP Vector & BM25 Memory Server | `memlord.spencer.lan` (:8000), `/mcp` | [Memlord Guide](memlord.md) |
| **pgvector** | Unified Vector & Relational Database | `:5432` (Internal `db` network) | [pgvector Guide](pgvector.md) |
| **Firecrawl Stack** | Web Scraper, Crawler & Search | `:3002` (Internal `ai` & `redis` networks) | [Firecrawl Guide](firecrawl.md) |
| **SearXNG** | Metasearch Engine | `:8080` (Internal `ai` & `redis` networks) | [SearXNG Guide](searxng.md) |
| **Valkey** | In-Memory Cache & Rate Limiter | `:6379` (Internal `redis` network) | [Valkey Guide](valkey.md) |
| **Authentik** | Centralized IAM, SSO, OIDC & Outposts | `sso.spencer.lan`, `login.spencer.lan` (:9000) | [Authentik Guide](authentik.md) |
| **Dozzle** | Real-Time Container Log Viewer & Streamer | `logs.spencer.lan`, `dozzle.spencer.lan` (:8080) | [Dozzle Guide](dozzle.md) |
| **ntfy** | Push Notification Gateway & System Alerts | `push.spencer.lan`, `ntfy.spencer.lan`, `:80` | [ntfy Guide](ntfy.md) |
| **Gitea** | Self-Hosted Git Platform & Issue Tracker | `git.spencer.lan`, `gitea.spencer.lan`, `:2222` (SSH) | [Gitea Guide](gitea.md) |
| **Homepage** | Unified Homelab Dashboard & Service Directory | `home.spencer.lan`, `homepage.spencer.lan` (:3000) | [Homepage Guide](homepage.md) |
| *Retired Services* | *Archived Services Stack* | *Retired (legacy chat, database, agent vault, infisical)* | [Legacy Stack](archive/open-webui-legacy-stack.md), [Agent Vault](archive/agent-vault.md), [Infisical](archive/infisical.md) |

---

## 🌐 Network Topologies

1. **`net1`**: Traefik edge network connecting reverse proxy to exposed web services (Hermes Gateway, Hermes Dashboard, Hindsight UI, Memlord Web UI, LiteLLM, Authentik Server, Dozzle, ntfy, Gitea, Homepage, Traefik API).
2. **`ai`**: Private high-speed network for inter-service communication (Hermes, Hindsight, Memlord MCP, Ollama, LiteLLM, SearXNG, Firecrawl, ntfy, Homepage).
3. **`db`**: Isolated database network hosting PostgreSQL instances (`pgvector`). Any service needing vector or relational database access connects to `db` (Hindsight, Memlord, LiteLLM, Authentik, Gitea).
4. **`redis`**: Dedicated caching network shared between Valkey, SearXNG, Firecrawl, and Authentik (sessions and task queue).
