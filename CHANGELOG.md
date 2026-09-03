# Changelog

All notable changes to Spencer's Homelab environment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to date-based versioning (`YYYY-MM-DD`).

---

## [2026-09-03]

### Added
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
- **Hermes Agent Docker Sandbox Execution Environment**:
  - Mounted `/var/run/docker.sock` into the `hermes` container with `TERMINAL_ENV=docker`, `TERMINAL_DOCKER_IMAGE=nikolaik/python-nodejs:python3.11-nodejs20`, and `TERMINAL_CONTAINER_PERSISTENT=false`.
  - Enabled `terminal`, `process`, and `execute_code` toolsets in [`hermes/config.yaml`](file:///data/homelab/hermes/config.yaml) across CLI, API server, and Gateway platforms.
  - Hardened sandbox execution with dropped Linux capabilities (`--cap-drop ALL`), disabled privilege escalation (`--security-opt no-new-privileges`), PID limit ceilings, and in-memory tmpfs scratch filesystems (`/workspace`, `/home`, `/root`).
- **LiteLLM Proxy Deployment (`litellm`)**:
  - Deployed `ghcr.io/berriai/litellm:main-latest` container tri-homed on `ai`, `net1`, and `db` networks.
  - Connected LiteLLM to `pgvector` database backend (`litellm` DB) with automated Prisma migrations for key generation, user management, and spend tracking.
  - Aggregated local Ollama models (`qwen2.5:14b`, `nomic-embed-text`) alongside optional external fallback providers (Groq, OpenRouter, DeepSeek) in [`litellm/config.yaml`](file:///data/homelab/litellm/config.yaml).
  - Added Traefik TLS edge routing at `https://llm.spencer.lan` for OpenAI-compatible API (`/v1`) and web Admin UI (`/ui`).
  - Added service documentation in [`docs/litellm.md`](file:///data/homelab/docs/litellm.md) and updated service index in [`docs/README.md`](file:///data/homelab/docs/README.md).

### Fixed
- **LiteLLM UI Reverse Proxy Redirection**:
  - Configured `FORWARDED_ALLOW_IPS=*` in LiteLLM container environment so Uvicorn honors `X-Forwarded-Proto: https` from Traefik instead of issuing `http://` 307 redirects.
  - Configured global HTTP-to-HTTPS entrypoint redirection (`redirections.entryPoint.to: websecure`) in [`traefik/traefik.yml`](file:///data/homelab/traefik/traefik.yml) so all port 80 traffic seamlessly upgrades to TLS port 443 across all homelab services.

### Changed
- **System Context & Documentation**:
  - Updated [`AGENTS.md`](file:///data/homelab/AGENTS.md) guidelines and [`docs/README.md`](file:///data/homelab/docs/README.md) to document `hindsight`, `litellm`, and Hermes Docker execution sandbox.
  - Updated roadmap items in [`TODO.md`](file:///data/homelab/TODO.md) reflecting completion of persistent memory with Hindsight, Docker sandboxed execution for Hermes, and LiteLLM proxy deployment.
  - Updated [`.env.example`](file:///data/homelab/.env.example) with Hindsight, Hermes terminal sandbox, and LiteLLM settings.

---

## [2026-09-02]

### Added
- **Dedicated pgvector Instance (`pgvector`)**:
  - Added standalone `pgvector` container running `pgvector/pgvector:${PGVECTOR_VERSION:-pg16}` for Hindsight long-term memory engine and future homelab microservices, decoupled from Open WebUI.
  - Added initialization script (`pgvector/init/01-init-databases.sh`) mounted to `/docker-entrypoint-initdb.d/` to enable `vector` extension on the primary database and auto-provision the `hindsight` database, user role, and vector extension.
  - Created service documentation in [`docs/pgvector.md`](file:///data/homelab/docs/pgvector.md) detailing architecture, connection strings, vector indexing, and backup operations.
  - Registered `pgvector` in [`docs/README.md`](file:///data/homelab/docs/README.md).
- **Environment & Git Configuration**:
  - Added configuration keys and templates in `.env.example` and configured secure credentials in `.env`.
  - Added ignore rules for `./pgvector/data/*` in `.gitignore`.

### Changed
- **Network Architecture & Strict Isolation**:
  - Bound `pgvector` exclusively to the internal `db` network (no `ai` network interface and no host port exposure).
  - Codified network requirement in [`AGENTS.md`](file:///data/homelab/AGENTS.md) and [`docs/README.md`](file:///data/homelab/docs/README.md) requiring any service needing vector/relational database access to connect to `db`.
- **Host UID/GID Mapping (`1000:1000`)**:
  - Configured dynamic entrypoint mapping in `docker-compose.yaml` to ensure database files in `./pgvector/data` are owned by `suadmin:suadmin` (1000:1000) directly on the host without `sudo`.
- **Roadmap Tracking**:
  - Marked Hindsight vector/relational storage backend milestone as complete in [`TODO.md`](file:///data/homelab/TODO.md).

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
