# Spencer's Homelab - Service Documentation Index

This directory contains in-depth documentation, architecture designs, configuration references, and operational guides for all services deployed in the homelab stack.

---

## 📚 Service Documentation

| Service | Category | Ports & Access | Documentation |
|---|---|---|---|
| **Traefik** | Reverse Proxy & Ingress | `:80`, `:443` (Hosts `traefik.spencer.lan`) | [Traefik Guide](traefik.md) |
| **CrowdSec** | Intrusion Detection & Traefik Bouncer | `:8080` (Internal `net1` network) | [CrowdSec Guide](crowdsec.md) |
| **OmniRoute Gateway** | Universal AI Gateway & LLM Router | `llm.spencer.lan` (:20128) | [OmniRoute Guide](omniroute.md) |
| **Open WebUI** | Multi-Model Generative AI Chat Interface | `chat.spencer.lan`, `ai.spencer.lan` (:8080) | [Open WebUI Guide](open-webui.md) |
| **Open Terminal** | Sandboxed Remote Shell & Agent Execution Substrate | `:8000` (Internal `ai` network) | [Open Terminal Guide](open-terminal.md) |
| **Ollama** | LLM Engine (GPU Accelerated) | `:11434` (Internal `ai` network) | [Ollama Guide](ollama.md) |
| **MoMoE** | Hybrid MoE Inference Engine (GPU + RAM) | `:8080` (Internal `ai` network) | [MoMoE Guide](momoe.md) |
| **pgvector** | Unified Vector & Relational Database | `:5432` (Internal `db` network) | [pgvector Guide](pgvector.md) |
| **Firecrawl Stack** | Web Scraper, Crawler & Search | `:3002` (Internal `ai` & `redis` networks) | [Firecrawl Guide](firecrawl.md) |
| **SearXNG** | Metasearch Engine | `:8080` (Internal `ai` & `redis` networks) | [SearXNG Guide](searxng.md) |
| **Valkey** | In-Memory Cache & Rate Limiter | `:6379` (Internal `redis` network) | [Valkey Guide](valkey.md) |
| **Authentik** | Centralized IAM, SSO, OIDC & Outposts | `sso.spencer.lan`, `login.spencer.lan` (:9000) | [Authentik Guide](authentik.md) |
| **Dozzle** | Real-Time Container Log Viewer & Streamer | `logs.spencer.lan`, `dozzle.spencer.lan` (:8080) | [Dozzle Guide](dozzle.md) |
| **ntfy** | Push Notification Gateway & System Alerts | `push.spencer.lan`, `ntfy.spencer.lan`, `:80` | [ntfy Guide](ntfy.md) |
| **OpenBao** | Secrets & Encryption Management Service | `vault.spencer.lan`, `openbao.spencer.lan` (:8200) | [OpenBao Guide](openbao.md) |
| **Gitea** | Self-Hosted Git Platform & Issue Tracker | `git.spencer.lan`, `gitea.spencer.lan`, `:2222` (SSH) | [Gitea Guide](gitea.md) |
| **Homepage** | Unified Homelab Dashboard & Service Directory | `home.spencer.lan`, `homepage.spencer.lan` (:3000) | [Homepage Guide](homepage.md) |
| *Retired Services* | *Archived Services Stack* | *Retired (litellm, hindsight, memlord, hermes, legacy chat, database, agent vault, infisical)* | [LiteLLM](archive/litellm.md), [Hindsight](archive/hindsight.md), [Memlord](archive/memlord.md), [Hermes Agent](archive/hermes.md), [Hermes Sandbox](archive/hermes-terminal-image/README.md), [Legacy Stack](archive/open-webui-legacy-stack.md), [Agent Vault](archive/agent-vault.md), [Infisical](archive/infisical.md) |

---

## 🌐 Network Topologies

1. **`net1`**: Traefik edge network connecting reverse proxy to exposed web services (Open WebUI, OmniRoute, Authentik Server, Dozzle, ntfy, OpenBao, Gitea, Homepage, Traefik API).
2. **`ai`**: Private high-speed network for inter-service communication (Open WebUI, Open Terminal, Ollama, MoMoE, OmniRoute, OpenBao, SearXNG, Firecrawl, ntfy, Homepage).
3. **`db`**: Isolated database network hosting PostgreSQL instances (`pgvector`). Any service needing vector or relational database access connects to `db` (Open WebUI, Authentik, Gitea).
4. **`redis`**: Dedicated caching network shared between Valkey, OmniRoute (cache & rate limiter), SearXNG, Firecrawl, Authentik (sessions and task queue), and Gitea (cache, session, and queue).
