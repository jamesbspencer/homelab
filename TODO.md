# 📋 Spencer's Homelab Roadmap & Todo

This file tracks upcoming features, architectural improvements, and exploration initiatives for the homelab.

---

## 🎯 Active Initiatives & Roadmap

### 1. 🧠 Persistent Memory with Hindsight
- [x] Explore and integrate **Hindsight** / long-term memory engine with Hermes Agent (deployed `hindsight` container in `ai` and `db` networks).
- [x] Configure vector/relational storage backend (e.g. pgvector or dedicated service) for user memory embeddings (deployed dedicated `pgvector` container with `hindsight` database on `db` network).
- [x] Establish automated memory consolidation and profile-scoped long-term context recall (`local_external` integration via `hermes/config.yaml` and `hermes/hindsight/config.json`).
- [x] Document memory architecture, ingestion pipelines, and configuration options in `docs/` (`docs/hindsight.md`).

---

### 2. 📦 Sandboxed Execution Environment for Hermes
- [x] Connect Hermes Agent to a secure execution sandbox (deployed Docker execution backend via `/var/run/docker.sock` with `nikolaik/python-nodejs:python3.11-nodejs20`).
- [x] Configure toolset permissions and security policies for safe code execution (enabled `terminal`, `process`, and `execute_code` with `--cap-drop ALL`, `--security-opt no-new-privileges`, and in-memory tmpfs).
- [x] Enable Hermes to run, debug, and test code snippets inside the isolated runtime without exposing the host system.
- [x] Update `docker-compose.yaml` networks and environment variables to bridge Hermes to the sandbox backend (`TERMINAL_ENV=docker`, `TERMINAL_CONTAINER_PERSISTENT=false`).

---

### 3. 🔄 Explore Hermes Self-Learning & Adaptation
- [x] Investigate Hermes Agent recursive learning loops, skill synthesis, and autonomous feedback mechanisms (enabled `skills` toolset, `creation_nudge_interval`, and `auxiliary.background_review` in `hermes/config.yaml`).
- [x] Set up memory logging and feedback evaluation pipelines for continuous improvement across sessions (enriched `hermes/hindsight/config.json` with retain/reflect bank missions and multi-layer recall).
- [x] Experiment with auto-generated skills and tool calibration based on past task execution history (configured `curator.consolidate: true` for autonomous umbrella merging, pruned lifecycle tracking, and ledger auditing).
- [x] Document best practices, safety boundaries, and prompt steering techniques for self-learning agents (steered via `hermes/SOUL.md` and documented in `docs/hermes.md`).

---

### 4. 🔌 Expose Hermes MCP Server
- [x] Configure and expose the **Model Context Protocol (MCP)** server from Hermes Agent (`hermes/scripts/hermes_mcp_server.py`).
- [x] Enable external MCP clients (e.g. Claude Desktop, Cursor, Antigravity IDE, Open WebUI MCP connectors) to consume Hermes homelab tools (SearXNG search, Firecrawl scraping, Docker sandbox execution, workspace file management, vision, skills).
- [x] Define authentication (Bearer token via `HERMES_MCP_KEY`), TLS routing through Traefik (`https://mcp.spencer.lan/sse`), unauthenticated `/health` check, and s6-overlay boot auto-supervision (`hermes/init/03-mcp-server.sh`).
- [x] Add an MCP integration guide with ready-to-copy client configurations to `docs/hermes.md`.

---

### 5. 🔀 Self-Hosted Free LLM Router (LiteLLM Proxy / RouteLLM / Portkey)
- [x] Evaluate and select an open-source, self-hosted LLM router (deployed **LiteLLM Proxy** `ghcr.io/berriai/litellm:main-latest`).
- [x] Deploy the router container on `ai`, `net1`, and `db` networks with Traefik routing at `https://llm.spencer.lan` and Admin UI at `https://llm.spencer.lan/ui`.
- [x] Connect local Ollama models (`qwen2.5:14b`, `nomic-embed-text`) alongside optional external providers (OpenRouter, Groq, DeepSeek) under a unified OpenAI-compatible API endpoint.
- [x] Configure intelligent request routing, automated database persistence in `pgvector` (`litellm` database), key management, rate limiting, and cost/token tracking.
- [x] Document client integration guides in [`docs/litellm.md`](file:///data/homelab/docs/litellm.md) to connect Open WebUI, Hermes Agent, and Hindsight to LiteLLM.

### 6. 🔍 Evaluate Decommissioning & Removal of Open WebUI
- [ ] Assess feature parity between Open WebUI and the primary Hermes Dashboard / Desktop interfaces (e.g. chat, document management, prompt presets).
- [ ] Audit secondary services coupled to Open WebUI (`postgres`/`pgvector`, `browserless`, `open-terminal`) to identify candidates for resource reclamation.
- [ ] Determine if document ingestion/RAG can be fully delegated to Hermes Agent + Firecrawl or a lighter alternative.
- [ ] Prepare migration or archiving strategy for existing chat history and vector embeddings before container removal.

---

### 7. 🛡️ CrowdSec Security Engine & Traefik Bouncer
- [x] Deploy **CrowdSec** security engine (`crowdsecurity/crowdsec:latest`) on `net1` network.
- [x] Configure real-time log acquisition from Traefik access logs via `crowdsec/config/acquis.d/traefik.yaml` with `crowdsecurity/traefik`, `crowdsecurity/http-cve`, and `crowdsecurity/whitelist-good-actors` collections.
- [x] Integrate **Traefik Bouncer Plugin** (`github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin`) in `stream` mode using pre-seeded API key and local subnet whitelisting.
- [x] Enforce edge protection globally across the `websecure` entrypoint in [`traefik/traefik.yml`](file:///data/homelab/traefik/traefik.yml).
- [x] Document CLI administration commands and operational architecture in [`docs/crowdsec.md`](file:///data/homelab/docs/crowdsec.md).

---

### 8. 🌍 Inbound Geoblocking with Traefik
- [x] Integrate **Traefik Geoblock Plugin** (`github.com/PascalMinder/geoblock` `v0.3.8`) on `websecure` entrypoint.
- [x] Configure allowlist mode (`blackListMode: false`) restricting ingress to the United States (`US`) while allowing local RFC 1918 traffic (`allowLocalRequests: true`).
- [x] Order middleware pipeline with `geoblock@file` before `crowdsec-bouncer@file` to drop non-US traffic before threat list evaluation.
- [x] Configure in-memory LRU caching (`cacheSize: 1000`) and reverse proxy header evaluation (`xForwardedForReverseProxy: true`).
- [x] Update documentation in [`docs/traefik.md`](file:///data/homelab/docs/traefik.md) and [`README.md`](file:///data/homelab/README.md).





