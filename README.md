# Spencer's Homelab Reverse Proxy, LLM Runtime & AI Agent Stack

A production-grade, privacy-first local homelab environment orchestrating edge routing, local LLM inference, autonomous agents, metasearch, headless browser rendering, and web scraping with **Docker Compose**.

---

## 🧭 In-Depth Documentation Directory

Detailed architectural designs, configuration options, environment variables, and troubleshooting guides for each individual service are located in the [`docs/`](docs/README.md) directory:

| Service | Role | Ingress & Internal Endpoints | Detailed Guide |
|---|---|---|---|
| **Traefik** | Reverse proxy, SSL, Geoblock (US Only) & edge router | `:80`, `:443` (`https://traefik.spencer.lan`) | [Traefik Guide](docs/traefik.md) |
| **CrowdSec** | Intrusion detection & Traefik Bouncer plugin | `:8080` (Internal `net1` network) | [CrowdSec Guide](docs/crowdsec.md) |
| **LiteLLM Proxy** | LLM routing gateway, spend manager & fallback router | `https://llm.spencer.lan` (:4000) | [LiteLLM Guide](docs/litellm.md) |
| **Ollama** | Local LLM inference engine with GPU acceleration | `http://ollama:11434` (Internal `ai` network) | [Ollama Guide](docs/ollama.md) |
| **Hermes Agent** | Autonomous AI agent runtime, dashboard & MCP server | `https://hermes.spencer.lan` / `https://ai.spencer.lan` / `https://mcp.spencer.lan` | [Hermes Guide](docs/hermes.md) |
| **Hindsight** | Long-term contextual memory engine for agents | `https://hindsight.spencer.lan` (:9999) / `:8888` | [Hindsight Guide](docs/hindsight.md) |
| **pgvector** | Unified vector & relational DB for Hindsight & LiteLLM | `pgvector:5432` (Internal `db` network) | [pgvector Guide](docs/pgvector.md) |
| **Firecrawl Stack** | Web scraper, crawler, and search backend | `http://firecrawl:3002` (Internal `ai` network) | [Firecrawl Guide](docs/firecrawl.md) |
| **SearXNG** | Privacy-respecting metasearch engine | `http://searxng:8080` (Internal `ai` network) | [SearXNG Guide](docs/searxng.md) |
| **Valkey** | High-performance in-memory cache & rate limiter | `valkey:6379` (Internal `redis` network) | [Valkey Guide](docs/valkey.md) |
| **Authentik** | Centralized IAM, SSO, OIDC & Proxy Outposts | `https://sso.spencer.lan` / `https://login.spencer.lan` (:9000) | [Authentik Guide](docs/authentik.md) |
| *Open WebUI Legacy Stack* | *Archived / Retired (Open WebUI, Postgres db, Open Terminal, Browserless)* | *Reclaimed ~1.02 GB RAM* | [Legacy Stack Archive](docs/archive/open-webui-legacy-stack.md) |

---

## 🏗️ Architecture Overview

```mermaid
flowchart TB
    %% External Ingress & Security
    subgraph Edge ["🌐 Edge Ingress & Security"]
        Client([External & LAN Clients]) -->|HTTPS :443| Traefik[Traefik Reverse Proxy]
        Traefik <--> GeoPlugin[Geoblock Plugin\nUS Only & RFC1918]
        Traefik <--> BouncerPlugin[CrowdSec Bouncer\nStream Mode]
        Traefik -.->|Access Logs| CrowdSec[CrowdSec Security Engine]
        Traefik <-->|ForwardAuth| Authentik[Authentik Server\nIAM & Outpost :9000]
    end

    %% Exposed Ingress Routes (net1)
    subgraph Ingress ["🚪 Proxied Endpoints (net1)"]
        Traefik -->|sso / login| Authentik
        Traefik -->|hermes / ai| HermesDash["Dashboard :9119"]
        Traefik -->|hermes-api| HermesAPI["API :8642"]
        Traefik -->|mcp| HermesMCP["MCP :8765"]
        Traefik -->|llm| LiteLLMUI["LiteLLM :4000"]
        Traefik -->|hindsight| HindsightUI["Hindsight :9999"]
        Traefik -->|traefik| TraefikDash["Traefik :internal"]
    end

    %% AI Agent & Inference Layer
    subgraph AICore ["🧠 AI Agent & Inference Layer (ai)"]
        Hermes["Nous Hermes Agent Runtime\n(Supervised Gateway & Background Review)"]
        LiteLLM["LiteLLM Proxy\n(Unified Router & Fallbacks)"]
        Ollama["Ollama (GPU Accelerated)\nqwen2.5:14b | nomic-embed"]
        Hindsight["Hindsight Memory Engine\n(Long-Term Memory & Graphs)"]
        Sandbox["Docker Sandbox\n(Ephemeral Container Runtime)"]
        
        HermesDash -.- Hermes
        HermesAPI -.- Hermes
        HermesMCP -.- Hermes

        Hermes -->|LLM Requests| LiteLLM
        Hermes -->|Memory Retain / Recall| Hindsight
        Hermes -->|Code & Process Exec| Sandbox
        LiteLLM -->|GPU Inference| Ollama
        LiteLLM -.->|Optional Cloud| CloudLLM[OpenRouter / Groq]
        Hindsight -->|Fact Extraction| Ollama
    end

    %% Tools, Search & Scraping Cluster
    subgraph Tools ["🛠️ Tools, Search & Scraping Cluster"]
        SearXNG["SearXNG Metasearch\n:8080 (ai / redis)"]
        
        subgraph FirecrawlStack ["Firecrawl Scraping Cluster (:3002)"]
            Firecrawl["Firecrawl Engine"]
            Playwright["Playwright Service\n:3000"]
            RabbitMQ["RabbitMQ Broker\n:5672"]
            NuqPG[("NuQ-Postgres\n:5432")]
            Firecrawl --> Playwright
            Firecrawl --> RabbitMQ
            Firecrawl --> NuqPG
        end

        Hermes -->|Web Search| SearXNG
        Hermes -->|Web Scraping & Crawling| Firecrawl
        Firecrawl -->|Direct Search Backend| SearXNG
    end

    %% Data Plane & Storage
    subgraph DataPlane ["💾 Data & Caching Plane"]
        subgraph DBNet ["db Network"]
            PGVector[("pgvector Database\n(hindsight & litellm)")]
        end
        subgraph CacheNet ["redis Network"]
            Valkey[("Valkey In-Memory Cache\n(Search Cache & Rate Limiting)")]
        end
    end

    Hindsight -->|Vectors & Relations| PGVector
    LiteLLM -->|Keys & Spend Audit| PGVector
    SearXNG -->|Result Cache| Valkey
    Firecrawl -->|Rate Limiting| Valkey
```

---

## 📁 Repository Structure

```text
/data/homelab/
├── docker-compose.yaml      # Master multi-container Compose manifest
├── README.md                # Main system summary and quickstart
├── CHANGELOG.md             # Date-based record of environment changes
├── TODO.md                  # Homelab roadmap and upcoming initiatives
├── AGENTS.md                # Workspace operational guidelines for AI agents
├── .env                     # Local environment secrets and configuration
├── .env.example             # Template file with documentation of all variables
├── crowdsec/                # CrowdSec intrusion detection configs & databases
│   ├── config/              # CrowdSec engine & log acquisition rules (acquis.d/)
│   └── data/                # SQLite event database and local intelligence store
├── docs/                    # Detailed service documentation
│   ├── README.md            # Documentation directory index
│   ├── browserless.md       # Browserless headless Chrome automation
│   ├── crowdsec.md          # CrowdSec security engine & Traefik bouncer guide
│   ├── firecrawl.md         # Firecrawl architecture, queues & scraping
│   ├── hermes.md            # Hermes Agent runtime, dashboard, sandbox & MCP
│   ├── hindsight.md         # Hindsight long-term agent memory engine
│   ├── litellm.md           # LiteLLM Proxy model router & spend tracker
│   ├── ollama.md            # Ollama setup & GPU acceleration guide
│   ├── open-terminal.md     # Sandboxed workspace execution setup
│   ├── open-webui.md        # Open WebUI features & connections
│   ├── pgvector.md          # Dedicated pgvector database for Hindsight & LiteLLM
│   ├── postgres.md          # PostgreSQL schema management for Open WebUI
│   ├── searxng.md           # SearXNG configuration & JSON engine setup
│   ├── traefik.md           # Traefik reverse proxy, SSL & bouncer plugin
│   └── valkey.md            # Valkey caching & healthcheck operations
├── hermes/                  # Hermes Agent persistent state, skills, MCP scripts
│   ├── config.yaml          # Hermes model providers, tools & memory configs
│   ├── hindsight/           # Profile memory configuration (config.json)
│   ├── init/                # Container s6 boot supervisor scripts (MCP server)
│   └── scripts/             # Hermes MCP server implementation (SSE & stdio)
├── litellm/                 # LiteLLM Proxy configuration (config.yaml)
├── nuq-postgres/            # NuQ PostgreSQL persistent crawl state database
├── ollama/                  # Cached LLM model weights
├── open-terminal/           # Sandboxed user home directory
├── open-webui/              # Open WebUI data and cache files
├── pgvector/                # Dedicated pgvector database data & init scripts
├── postgres/                # PostgreSQL pgvector data directory (Open WebUI)
├── searxng/                 # SearXNG configuration and cache directories
├── traefik/                 # Traefik static, dynamic, and TLS cert configurations
│   ├── certs/               # Wildcard SSL certificates (*.spencer.lan)
│   ├── dynamic.yml          # Dynamic routers, TLS & bouncer middleware
│   ├── logs/                # Traefik JSON access log (read by CrowdSec)
│   ├── traefik.yml          # Static entrypoints, plugins & log declarations
│   └── crowdsec_bouncer_key # Protected secret key file for bouncer plugin
└── valkey/                  # Valkey snapshot persistence directory
```

---

## 🚀 Quick Start

### 1. Prerequisites
* **Docker & Docker Compose**: Compose v2 installed.
* **NVIDIA Container Toolkit**: Required for hardware GPU acceleration on Ollama.
* **Local DNS**: `*.spencer.lan` pointed to your host IP address.
* **TLS Certificates**: Wildcard certificates in `traefik/certs/cert.pem` and `traefik/certs/key.pem`.

### 2. Environment Setup
Copy the template and adjust passwords or API keys as needed:
```bash
cp .env.example .env
```

### 3. Start the Stack
```bash
docker compose up -d
```

### 4. Verify Service Health
```bash
docker compose ps
```

---

## 🧪 Operational Commands & Health Checks

### Check Traefik Routing
Navigate to `https://traefik.spencer.lan` or check logs:
```bash
docker compose logs -f traefik
```

### Test Ollama GPU Inference
```bash
curl http://localhost:11434/api/tags
docker compose exec ollama nvidia-smi
```

### Test Internal Scraping (Firecrawl)
```bash
docker compose exec hermes curl -s -X POST http://firecrawl:3002/v1/scrape \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'
```

### Test Internal Search (SearXNG)
```bash
docker compose exec open-webui curl "http://searxng:8080/search?q=docker&format=json"
```

### Test Database Readiness
```bash
docker compose exec db pg_isready -U openwebui -d openwebui
```
