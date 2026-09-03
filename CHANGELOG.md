# Changelog

All notable changes to Spencer's Homelab environment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to date-based versioning (`YYYY-MM-DD`).

---

## [2026-09-03]

### Changed
- **Hermes Ingress Route Restructuring**:
  - Reconfigured Hermes Web Dashboard / Desktop UI routing from `hermes-dashboard.spencer.lan` to primary domain `hermes.spencer.lan` (with aliases `hermes-desktop.spencer.lan` and `hermes-dashboard.spencer.lan` preserved).
  - Reconfigured Hermes Gateway API routing from `hermes.spencer.lan` to `hermes-api.spencer.lan` on port `8642`.

### Added
- **Let's Encrypt (ACME) & Dynamic Public Ingress Routing**:
  - Configured `certificatesResolvers.letsencrypt` in [`traefik/traefik.yml`](file:///data/homelab/traefik/traefik.yml) using HTTP-01 challenge on entrypoint `web` with storage in `traefik/acme.json`.
  - Added public routing for Hermes Dashboard in [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml) driven by environment variables (`HERMES_PUBLIC_DOMAIN`, `ACME_EMAIL`) stored securely in uncommitted `.env`.
- **Traefik Inbound Geoblocking Plugin**:
  - Registered `github.com/PascalMinder/geoblock` (`v0.3.8`) plugin in [`traefik/traefik.yml`](file:///data/homelab/traefik/traefik.yml) to restrict incoming edge connections geographically.
  - Configured allowlist mode (`blackListMode: false`) permitting only the United States (`US`) with automatic RFC 1918 private IP bypass (`allowLocalRequests: true`) in [`traefik/dynamic.yml`](file:///data/homelab/traefik/dynamic.yml).
  - Attached `geoblock@file` to entrypoint `websecure` positioned before `crowdsec-bouncer@file`, immediately discarding foreign traffic with HTTP 403 before executing threat intelligence evaluations.
  - Configured in-memory LRU caching (`cacheSize: 1000`) and reverse proxy header evaluation (`xForwardedForReverseProxy: true`).
- **CrowdSec Security Engine & Traefik Bouncer**:
  - Deployed `crowdsecurity/crowdsec:latest` container attached to `net1` network for local log ingestion and LAPI serving.
  - Configured real-time Traefik access log acquisition in [`crowdsec/config/acquis.d/traefik.yaml`](file:///data/homelab/crowdsec/config/acquis.d/traefik.yaml) with automatic hub installation of `crowdsecurity/traefik`, `crowdsecurity/http-cve`, and `crowdsecurity/whitelist-good-actors`.
  - Registered and loaded **Traefik Bouncer Plugin** (`github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin` `v1.4.1`) in [`traefik/traefik.yml`](file:///data/homelab/traefik/traefik.yml) operating in in-memory `stream` mode.
  - Enforced global protection on `websecure` entrypoint (`443`) with secure file-based key loading (`traefik/crowdsec_bouncer_key`) and private subnet whitelisting (`127.0.0.1/32`, `192.168.0.0/16`, `10.0.0.0/8`).
  - Added comprehensive operational guide to [`docs/crowdsec.md`](file:///data/homelab/docs/crowdsec.md) and updated [`docs/README.md`](file:///data/homelab/docs/README.md) and [`AGENTS.md`](file:///data/homelab/AGENTS.md).
- **Hermes Model Context Protocol (MCP) Server**:
  - Implemented dual-transport MCP server in [`hermes/scripts/hermes_mcp_server.py`](file:///data/homelab/hermes/scripts/hermes_mcp_server.py) wrapping Hermes `model_tools.handle_function_call`.
  - Exposes 13 homelab tools to external AI clients: `web_search` (SearXNG), `web_extract` (Firecrawl), `execute_code`, `terminal`, `process` (Docker sandbox), `read_file`, `write_file`, `patch`, `search_files` (workspace), `vision_analyze` (multimodal vision), `text_to_speech` (TTS), and `skills_list` / `skill_view` (Hermes skills).
  - Integrated into existing `hermes` container via s6-overlay boot script ([`hermes/init/03-mcp-server.sh`](file:///data/homelab/hermes/init/03-mcp-server.sh)) for automatic process supervision, failure recovery, and unified resource footprint without running duplicate containers.
  - Added Traefik edge routing on `net1` for `https://mcp.spencer.lan/sse` and message ingress at `/messages/` (port `8765`).
  - Enforced Bearer token authentication via `HERMES_MCP_KEY` with unauthenticated `/health` endpoint for monitoring.
  - Added client configuration examples for Claude Desktop (SSE and direct Docker stdio), Cursor / IDE extensions, and Open WebUI MCP connectors to [`docs/hermes.md`](file:///data/homelab/docs/hermes.md).

---

## [2026-09-02]

### Added
- **LiteLLM Proxy Deployment (`litellm`)**:
  - Deployed `ghcr.io/berriai/litellm:main-latest` container tri-homed on `ai`, `net1`, and `db` networks.
  - Connected LiteLLM to `pgvector` database backend (`litellm` DB) with automated Prisma migrations for key generation, user management, and spend tracking.
  - Aggregated local Ollama models (`qwen2.5:14b`, `nomic-embed-text`) alongside optional external fallback providers (Groq, OpenRouter, DeepSeek) in [`litellm/config.yaml`](file:///data/homelab/litellm/config.yaml).
  - Added Traefik TLS edge routing at `https://llm.spencer.lan` for OpenAI-compatible API (`/v1`) and web Admin UI (`/ui`).
- **Hermes Agent LiteLLM Proxy Integration**:
  - Connected Hermes Agent to LiteLLM router endpoint at `http://litellm:4000/v1` over internal `ai` network.
  - Configured `CUSTOM_API_KEY` and `OPENAI_API_KEY` with `${LITELLM_MASTER_KEY}` for seamless authentication.
  - Declared explicit 64K context window metadata (`max_tokens: 65536`) for `qwen2.5:14b` in [`litellm/config.yaml`](file:///data/homelab/litellm/config.yaml) and registered `custom_providers` entry in [`hermes/config.yaml`](file:///data/homelab/hermes/config.yaml).
  - Verified end-to-end inference routing with automated token tracking and persistence in `pgvector` (`LiteLLM_SpendLogs`).
- **Hermes Agent Docker Sandbox Execution Environment**:
  - Mounted `/var/run/docker.sock` into the `hermes` container with `TERMINAL_ENV=docker`, `TERMINAL_DOCKER_IMAGE=nikolaik/python-nodejs:python3.11-nodejs20`, and `TERMINAL_CONTAINER_PERSISTENT=false`.
  - Enabled `terminal`, `process`, and `execute_code` toolsets in [`hermes/config.yaml`](file:///data/homelab/hermes/config.yaml) across CLI, API server, and Gateway platforms.
  - Hardened sandbox execution with dropped Linux capabilities (`--cap-drop ALL`), disabled privilege escalation (`--security-opt no-new-privileges`), PID limit ceilings, and in-memory tmpfs scratch filesystems (`/workspace`, `/home`, `/root`).
- **Hindsight Long-Term Memory Container (`hindsight`)**:
  - Deployed `ghcr.io/vectorize-io/hindsight:${HINDSIGHT_VERSION:-latest}` service dual-homed on `ai` and `db` networks.
  - Connected Hindsight to the dedicated `pgvector` instance on `db` network (`postgresql://hindsight:...@pgvector:5432/hindsight`) with `pgvector` vector extension.
  - Connected Hindsight to local Ollama (`qwen2.5:14b`) via `http://ollama:11434/v1` on `ai` network for entity extraction and memory reflection, with concurrency limited to 1.
  - Added Traefik edge routing on `net1` for Hindsight Control Plane Web UI at `https://hindsight.spencer.lan` (port `9999`).
  - Added container healthcheck targeting `http://localhost:8888/health`.
  - Created service documentation in [`docs/hindsight.md`](file:///data/homelab/docs/hindsight.md) and updated service index in [`docs/README.md`](file:///data/homelab/docs/README.md).
- **Hermes Agent Hindsight Integration**:
  - Configured `hermes` container with `HINDSIGHT_MODE=local_external`, `HINDSIGHT_API_URL=http://hindsight:8888`, and `HINDSIGHT_BANK_ID=hermes`.
  - Added `hindsight` to `depends_on` for `hermes` service in `docker-compose.yaml`.
  - Activated `hindsight` memory provider in [`hermes/config.yaml`](file:///data/homelab/hermes/config.yaml).
  - Provisioned profile memory config in [`hermes/hindsight/config.json`](file:///data/homelab/hermes/hindsight/config.json) with auto-recall and auto-retain enabled.
  - Updated [`docs/hermes.md`](file:///data/homelab/docs/hermes.md) with memory backend architecture diagram and tool descriptions.
- **Dedicated pgvector Instance (`pgvector`)**:
  - Added standalone `pgvector` container running `pgvector/pgvector:${PGVECTOR_VERSION:-pg16}` for Hindsight long-term memory engine and future homelab microservices, decoupled from Open WebUI.
  - Added initialization script (`pgvector/init/01-init-databases.sh`) mounted to `/docker-entrypoint-initdb.d/` to enable `vector` extension on the primary database and auto-provision the `hindsight` database, user role, and vector extension.
  - Created service documentation in [`docs/pgvector.md`](file:///data/homelab/docs/pgvector.md) detailing architecture, connection strings, vector indexing, and backup operations.
  - Registered `pgvector` in [`docs/README.md`](file:///data/homelab/docs/README.md).
- **Environment & Git Configuration**:
  - Added configuration keys and templates in `.env.example` and configured secure credentials in `.env`.
  - Added ignore rules for `./pgvector/data/*` in `.gitignore`.

### Fixed
- **LiteLLM UI Reverse Proxy Redirection**:
  - Configured `FORWARDED_ALLOW_IPS=*` in LiteLLM container environment so Uvicorn honors `X-Forwarded-Proto: https` from Traefik instead of issuing `http://` 307 redirects.
  - Configured global HTTP-to-HTTPS entrypoint redirection (`redirections.entryPoint.to: websecure`) in [`traefik/traefik.yml`](file:///data/homelab/traefik/traefik.yml) so all port 80 traffic seamlessly upgrades to TLS port 443 across all homelab services.

### Changed
- **Network Architecture & Strict Isolation**:
  - Bound `pgvector` exclusively to the internal `db` network (no `ai` network interface and no host port exposure).
  - Codified network requirement in [`AGENTS.md`](file:///data/homelab/AGENTS.md) and [`docs/README.md`](file:///data/homelab/docs/README.md) requiring any service needing vector/relational database access to connect to `db`.
- **Host UID/GID Mapping (`1000:1000`)**:
  - Configured dynamic entrypoint mapping in `docker-compose.yaml` to ensure database files in `./pgvector/data` are owned by `suadmin:suadmin` (1000:1000) directly on the host without `sudo`.
- **System Context & Documentation**:
  - Updated [`AGENTS.md`](file:///data/homelab/AGENTS.md) guidelines and [`docs/README.md`](file:///data/homelab/docs/README.md) to document `hindsight`, `litellm`, and Hermes Docker execution sandbox.
  - Updated roadmap items in [`TODO.md`](file:///data/homelab/TODO.md) reflecting completion of persistent memory with Hindsight, Docker sandboxed execution for Hermes, and LiteLLM proxy deployment.
  - Updated [`.env.example`](file:///data/homelab/.env.example) with Hindsight, Hermes terminal sandbox, and LiteLLM settings.


---

## [2026-08-30]

### Added
- **Firecrawl Scraping & Crawling Engine**:
  - Deployed unified `firecrawl` container running API, worker, and extract-worker services concurrently on internal port `3002`.
  - Added `rabbitmq` (`rabbitmq:3-management`) container as the real-time AMQP message broker for NuQ queues.
  - Added `nuq-postgres` (`ghcr.io/firecrawl/nuq-postgres:latest`) for persistent crawl queue schemas and job history.
  - Added `playwright-service` (`ghcr.io/firecrawl/playwright-service:latest`) for headless Chromium page rendering.
- **SearXNG & Hermes Integration**:
  - Attached Firecrawl directly to SearXNG via `SEARXNG_ENDPOINT: http://searxng:8080` for standalone `/v1/search` queries.
  - Attached Firecrawl to Hermes Agent via `FIRECRAWL_API_URL: http://firecrawl:3002` and configured `hermes/config.yaml` with `extract_backend: firecrawl` and `search_backend: searxng`.
- **In-Depth Documentation Directory (`docs/`)**:
  - Created [`docs/README.md`](file:///data/homelab/docs/README.md) documentation index.
  - Added 10 individual service guides: `traefik.md`, `ollama.md`, `open-webui.md`, `postgres.md`, `hermes.md`, `firecrawl.md`, `searxng.md`, `valkey.md`, `browserless.md`, and `open-terminal.md`.
  - Updated root [`README.md`](file:///data/homelab/README.md) with an overview table, updated architecture diagram, and links to all service guides.

### Changed
- **Default LLM Migration to `qwen2.5:14b`**:
  - Switched default model in Ollama, Hermes, and environment files to `qwen2.5:14b`.
  - Configured client-level 64K context window (`ollama_num_ctx: 65536`) to satisfy Hermes Agent's operational context requirements.
  - Streamlined `hermes/config.yaml` platform toolsets to prevent context saturation and enable native OpenAI tool-calling loops for real-time web searches.


### Security
- Parameterized Firecrawl PostgreSQL credentials (`FIRECRAWL_POSTGRES_USER`, `FIRECRAWL_POSTGRES_PASSWORD`, `FIRECRAWL_POSTGRES_DB`) in `docker-compose.yaml`, `.env`, and `.env.example`.
- Confirmed zero hardcoded secrets/passwords across all services in `docker-compose.yaml`.
- Enforced internal-only network isolation for the Firecrawl cluster (`ai` and `redis` networks only; no open host ports or Traefik LAN exposure).

---

## [2026-08-28]

### Added
- **Nous Research Hermes Agent**:
  - Deployed `nousresearch/hermes-agent:latest` running gateway and web dashboard under `s6` process supervision.
  - Added Traefik edge routing for Gateway API (`https://hermes.spencer.lan`) and Web Dashboard (`https://hermes-dashboard.spencer.lan`).
  - Configured basic authentication for dashboard access and connected Hermes to local Ollama runtime (`http://ollama:11434/v1`).

---

## [2026-08-27]

### Added
- **Browserless Chrome Service**:
  - Added `browserless/chrome:latest` container on the `ai` network.
  - Configured Open WebUI Playwright web loader engine to use `ws://browserless:3000` for rendering JavaScript-heavy websites.
- **pgvector Database Backend**:
  - Added `pgvector/pgvector:pg16` database service on an isolated `db` network.
  - Migrated Open WebUI relational data and document embeddings to PostgreSQL with `pgvector`.
- **Initial Homelab Architecture**:
  - Deployed Traefik reverse proxy with local TLS certificate termination and dashboard at `https://traefik.spencer.lan`.
  - Deployed Ollama LLM runtime with NVIDIA GPU hardware acceleration passthrough.
  - Deployed Open WebUI interface at `https://ai.spencer.lan`.
  - Deployed Open Terminal sandboxed code interpreter environment.
  - Deployed SearXNG privacy metasearch engine with Valkey key-value caching backend.
