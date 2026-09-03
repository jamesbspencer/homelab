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
- [ ] Connect Hermes Agent to a secure execution sandbox (e.g. Open Terminal container or isolated Docker-in-Docker / microVM environment).
- [ ] Configure toolset permissions and security policies for safe code execution.
- [ ] Enable Hermes to run, debug, and test code snippets inside the isolated runtime without exposing the host system.
- [ ] Update `docker-compose.yaml` networks and environment variables to bridge Hermes to the sandbox backend.

---

### 3. 🔄 Explore Hermes Self-Learning & Adaptation
- [ ] Investigate Hermes Agent recursive learning loops, skill synthesis, and autonomous feedback mechanisms.
- [ ] Set up memory logging and feedback evaluation pipelines for continuous improvement across sessions.
- [ ] Experiment with auto-generated skills and tool calibration based on past task execution history.
- [ ] Document best practices, safety boundaries, and prompt steering techniques for self-learning agents.

---

### 4. 🔌 Expose Hermes MCP Server
- [ ] Configure and expose the **Model Context Protocol (MCP)** server from Hermes Agent (`hermes-tools` / `python -m agent.transports.hermes_tools_mcp_server`).
- [ ] Enable external MCP clients (e.g. Claude Desktop, IDE extensions, Open WebUI MCP connectors) to consume Hermes homelab tools (SearXNG search, Firecrawl scraping, file management).
- [ ] Define authentication, TLS routing through Traefik (`mcp.spencer.lan` or SSE/stdio bridge), and access control policies.
- [ ] Add an MCP integration guide to `docs/hermes.md`.

---

### 5. 🔀 Self-Hosted Free LLM Router (LiteLLM Proxy / RouteLLM / Portkey)
- [ ] Evaluate and select an open-source, self-hosted LLM router (e.g. **LiteLLM Proxy**, **RouteLLM**, or **Portkey AI Gateway**).
- [ ] Deploy the router container on the `ai` network with Traefik routing (`router.spencer.lan` / `llm.spencer.lan`).
- [ ] Connect local Ollama models (`qwen2.5:14b`, `nomic-embed-text`) alongside optional external providers (OpenRouter, Groq, DeepSeek, Anthropic) under a unified OpenAI-compatible API endpoint.
- [ ] Configure intelligent request routing, automatic model failover/fallbacks, load balancing, rate limiting, and cost/token tracking.
- [ ] Point Open WebUI and Hermes Agent to the router endpoint for centralized LLM dispatch and observability.

---

### 6. 🔍 Evaluate Decommissioning & Removal of Open WebUI
- [ ] Assess feature parity between Open WebUI and the primary Hermes Dashboard / Desktop interfaces (e.g. chat, document management, prompt presets).
- [ ] Audit secondary services coupled to Open WebUI (`postgres`/`pgvector`, `browserless`, `open-terminal`) to identify candidates for resource reclamation.
- [ ] Determine if document ingestion/RAG can be fully delegated to Hermes Agent + Firecrawl or a lighter alternative.
- [ ] Prepare migration or archiving strategy for existing chat history and vector embeddings before container removal.


