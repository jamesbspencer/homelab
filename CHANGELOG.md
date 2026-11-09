# Changelog

All notable changes to Spencer's Homelab environment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to date-based versioning (`YYYY-MM-DD`).

---

## [2026-11-09]

### Added
- **Qwen 3 Coder 30B MoE & Multi-Model Llama Router**:
  - Downloaded `Qwen3-Coder-30B-A3B-Instruct-IQ4_XS.gguf` (16.3 GB, 48 hidden layers, 128 experts with 8 active per token) into `./llama/models`.
  - Converted `llama-server` to Router Mode using `--models-preset /presets.ini` with single-model memory constraint (`--models-max 1`) for safe GPU VRAM sharing.
  - Defined router model presets in `llama/presets.ini` with 64k unified KV cache and `--n-cpu-moe` offloading:
    - `qwen3.6-35b-a3b`: `--n-cpu-moe 20` (20 CPU layers / 20 GPU layers).
    - `qwen3-coder-30b-a3b`: `--n-cpu-moe 32` (32 CPU layers / 16 GPU layers, ~7.8 GiB VRAM footprint).
  - Provisioned clean raw workspace models in Open WebUI (`vscode-coder` and `vscode`) with no tools, no memories, no knowledge retrieval, and no web search for VS Code extensions (Continue, Cline, Roo Code, Aider).
  - Configured OmniRoute context window overrides for `qwen3-coder-30b-a3b` and `vscode-coder` (65,536 tokens).
  - Synchronized documentation in `docs/llama-cpp.md`, `docs/open-webui.md`, `docs/omniroute.md`, `README.md`, and `AGENTS.md`.

## [2026-11-08]

### Added
- **OpenWrt Router DNS Provisioning for Knowledge Search & Homelab Services**:
  - Connected to the OpenWrt router (`192.168.77.1`) via ubus JSON-RPC and provisioned static DNS domain records in `dnsmasq` under the local `.spencer.lan` zone targeting the homelab host (`192.168.77.40`).
  - Added DNS records for `knowledge.spencer.lan`, `rag.spencer.lan`, `chat.spencer.lan`, `glances.spencer.lan`, `stats.spencer.lan`, and `dozzle.spencer.lan`.
  - Applied UCI changes and reloaded `dnsmasq` via `rc.init`, verifying name resolution directly over UDP port 53.

- **pgvector Knowledge Search Web UI & Retrieval Substrate**:
  - Built and deployed `knowledge-search` container (`homelab/knowledge-search:latest`) on port `8000`, accessible via local ingress [`https://knowledge.spencer.lan`](https://knowledge.spencer.lan) and [`https://rag.spencer.lan`](https://rag.spencer.lan).
  - Implemented multi-mode retrieval engine supporting:
    - **Hybrid Search**: Reciprocal Rank Fusion (RRF) combining dense semantic vector cosine similarity with sparse full-text keyword rank.
    - **Dense Semantic Vector Search**: Direct cosine similarity (`1 - (vector <=> $1)`) against pgvector, offloading real-time query embeddings to companion `llama-embed` (`nomic-embed-text` with AVX-512 acceleration, zero-padded from 768 to 1536 dimensions).
    - **Sparse Keyword / Full-Text Search**: Leverages PostgreSQL GIN `to_tsvector('simple', text)` indexing with `ts_rank_cd` and substring `ILIKE` fallback for code and symbols.
    - **Nearest Neighbor Similarity Explorer**: One-click cosine similarity comparison across chunks and collections.
  - Developed responsive, modern dark-themed single-page web UI featuring real-time search, interactive Markdown chunk rendering, JSON metadata inspection, vector telemetry drawer, and collection partition directory.
  - Configured Traefik reverse proxy labels with wildcard TLS encryption on `net1`, `db`, and `ai` bridge networks with automated container healthcheck.
  - Added Knowledge Search service tile and health widget to Homepage under the **Search & Scrape** group ([`homepage/config/services.yaml`](file:///data/homelab/homepage/config/services.yaml)).
  - Authored dedicated service documentation in [`docs/knowledge-search.md`](file:///data/homelab/docs/knowledge-search.md) and synchronized [`docs/README.md`](file:///data/homelab/docs/README.md), [`README.md`](file:///data/homelab/README.md), and [`AGENTS.md`](file:///data/homelab/AGENTS.md).

- **64k Context Window & Open WebUI Full Tooling Integration**:
  - Expanded `llama-server` context size to **65,536 tokens** using unified KV cache (`--kv-unified --kv-unified-per-slot 65536 -np 2`), resolving 32k context boundary errors with zero VRAM overflow (resident at 11,689 MiB on RTX 3060).
  - Pre-configured `qwen3.6-35b-a3b` persistent model preset in Open WebUI with default Web Search, all tools (`openbao_client`, `ubuntu_ssh_client`, `openwrt_client`), client skills, and Open Terminal execution substrate.
  - Set global user interface default `webSearch: "always"` in Open WebUI user settings.
  - Synchronized [`docs/open-webui.md`](file:///data/homelab/docs/open-webui.md) and [`docs/omniroute.md`](file:///data/homelab/docs/omniroute.md) to reflect the decoupled inference architecture.
- **Llama.cpp Hybrid MoE Runtime & Zero-VRAM Embeddings (Replacing Ollama & MoMoE)**:
  - Deployed `llama-server` (`ghcr.io/ggml-org/llama.cpp:server-cuda`) running `Qwen3.6-35B-A3B` (IQ4_XS, 35.5B parameters, 32k context) with expert offloading (`--n-cpu-moe 20`), flash attention (`--flash-attn on`), and quantized KV cache (`--cache-type-k q8_0 --cache-type-v q8_0`).
  - Dedicated 100% of the NVIDIA GeForce RTX 3060 (12 GB VRAM) to non-expert layers, shared experts, and KV cache, while offloading inactive routed expert weights to system DDR4 RAM computed via Intel Xeon W-2145 AVX-512 extensions (`--threads 8`), achieving ~47–55 tokens/sec generation speed.
  - Deployed companion `llama-embed` container running `nomic-embed-text` on CPU (0 MB VRAM, ~250 MB RAM) to handle vector search and conversational memory embeddings without GPU memory contention.
  - Decoupled OmniRoute from Open WebUI's critical inference and embedding path: Open WebUI connects directly to `llama-server:8080/v1` for chat and `llama-embed:8081/v1` for RAG, unblocking startup dependencies while retaining OmniRoute as an independent standalone router.
  - Retired and removed `ollama` and `momoe` containers, reclaiming fragmented VRAM reserves.
  - Archived [`docs/ollama.md`](file:///data/homelab/docs/archive/ollama.md) and [`docs/momoe.md`](file:///data/homelab/docs/archive/momoe.md) into [`docs/archive/`](file:///data/homelab/docs/archive/); authored comprehensive architecture and tuning guide in [`docs/llama-cpp.md`](file:///data/homelab/docs/llama-cpp.md).
  - Updated Homepage service cards, `README.md`, `AGENTS.md`, and `TODO.md`.
- **GitHub & Gitea CLI Developer Tooling in Open Terminal**:
  - Installed official upstream GitHub CLI (`gh` v2.103.3) directly into `/usr/bin/gh` with system package bash completions.
  - Installed both modern Gitea CLI (`gt` v0.1.0) and classic Gitea CLI (`tea` v0.16.0) into `/usr/local/bin` along with compatibility symlink `/usr/local/bin/gitea-cli -> gt`.
  - Configured native auto-generated bash completion for `gt` and `tea` in `/usr/share/bash-completion/completions/`.
  - Configured system-wide environment variables `GITEA_INSTANCE_URL=http://gitea:3000` and `GITEA_SERVER_URL=http://gitea:3000` in [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml), `/etc/profile.d/homelab.sh`, and [`open-terminal/workspace/.bashrc`](file:///data/homelab/open-terminal/workspace/.bashrc) for zero-config CLI interaction with homelab Gitea over the internal `ai` Docker network.
  - Parameterized `GH_CLI_VERSION`, `GITEA_CLI_VERSION`, and `TEA_VERSION` in [`.env.example`](file:///data/homelab/.env.example).
  - Synchronized documentation across [`docs/open-terminal.md`](file:///data/homelab/docs/open-terminal.md), [`docs/gitea.md`](file:///data/homelab/docs/gitea.md), [`docs/README.md`](file:///data/homelab/docs/README.md), [`README.md`](file:///data/homelab/README.md), and [`AGENTS.md`](file:///data/homelab/AGENTS.md).

- **OpenBao CLI Integration in Open Terminal**:
  - Authored custom container image recipe in [`open-terminal/Dockerfile`](file:///data/homelab/open-terminal/Dockerfile) multi-staging the official `bao` CLI binary directly from `openbao/openbao:latest` (`v2.7.2`).
  - Configured compatibility symlinks for `/usr/local/bin/openbao` and `/usr/local/bin/vault` alongside `/usr/local/bin/bao`.
  - Configured `BAO_ADDR=http://openbao:8200` and `VAULT_ADDR=http://openbao:8200` in [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml) and [`open-terminal/workspace/.bashrc`](file:///data/homelab/open-terminal/workspace/.bashrc) for seamless zero-config API connectivity over the internal `ai` bridge network.
  - Enabled bash CLI autocompletion for `bao`, `openbao`, and `vault`.
  - Rebuilt and deployed `homelab/open-terminal:latest`, verified CLI binary execution and vault health status probes directly from user shell.
  - Synchronized documentation in [`docs/open-terminal.md`](file:///data/homelab/docs/open-terminal.md), [`docs/openbao.md`](file:///data/homelab/docs/openbao.md), [`README.md`](file:///data/homelab/README.md), and [`AGENTS.md`](file:///data/homelab/AGENTS.md).

- **NVIDIA GPU Performance Telemetry on Homepage via Glances**:
  - Deployed `glances` container (`nicolargo/glances:ubuntu-latest-full`) with full NVIDIA GPU device passthrough (`driver: nvidia`, `count: all`, `capabilities: [gpu]`) on the isolated `ai` and `net1` bridge networks.
  - Utilized the `ubuntu-latest-full` (glibc) image base to ensure compatibility with host NVML (`libnvidia-ml.so.1`) drivers, avoiding Alpine musl `dlvsym` library loading issues.
  - Exposed Glances REST API v4 on internal port `61208` and registered Traefik reverse proxy routes for `glances.spencer.lan` and `stats.spencer.lan`.
  - Added `NVIDIA RTX 3060` hardware telemetry widget to the **AI & Agents** category (`metric: gpu:nvidia0`) and `Host Performance` widget to the **Developer Tools & Ops** category (`metric: cpu`) in Homepage ([`homepage/config/services.yaml`](file:///data/homelab/homepage/config/services.yaml)).
  - Updated grid column layout to 4 columns for **Developer Tools & Ops** in [`homepage/config/settings.yaml`](file:///data/homelab/homepage/config/settings.yaml).
  - Authored dedicated service documentation in [`docs/glances.md`](file:///data/homelab/docs/glances.md) and updated [`README.md`](file:///data/homelab/README.md), [`AGENTS.md`](file:///data/homelab/AGENTS.md), and [`docs/homepage.md`](file:///data/homelab/docs/homepage.md).

- **Open WebUI Valve Encryption at Rest**:
  - Configured `ENABLE_VALVE_ENCRYPTION=True` in [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml) and parameterized in [`.env.example`](file:///data/homelab/.env.example) and `.env`.
  - Enables Fernet (AES-128) symmetric encryption for all Tool and Function plugin valves and user valves stored in PostgreSQL, deriving the encryption key deterministically from `OPENWEBUI_SECRET_KEY`.
  - Updated service architecture and security documentation in [`docs/open-webui.md`](file:///data/homelab/docs/open-webui.md) and [`AGENTS.md`](file:///data/homelab/AGENTS.md).

---

## [2026-11-07]

### Added
- **Dedicated External Knowledge Vector Database in pgvector for Open WebUI**:
  - Provisioned dedicated `openwebui_knowledge` database in the `pgvector` container with `vector` extension enabled and full role permissions for `openwebui`.
  - Configured `PGVECTOR_DB_URL=postgresql://${OPENWEBUI_POSTGRES_USER:-openwebui}:${OPENWEBUI_POSTGRES_PASSWORD}@pgvector:5432/${OPENWEBUI_KNOWLEDGE_POSTGRES_DB:-openwebui_knowledge}` in [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml) to separate vector embeddings and RAG document chunks from core relational state (`openwebui` database).
  - Migrated existing document chunks and vector indices with zero loss, preserving all user personalization memories and RAG embeddings.
  - Updated auto-provisioning bootstrap script in [`pgvector/init/01-init-databases.sh`](file:///data/homelab/pgvector/init/01-init-databases.sh) and updated environment templates in [`.env.example`](file:///data/homelab/.env.example).
  - Synchronized documentation in [`docs/open-webui.md`](file:///data/homelab/docs/open-webui.md) and [`docs/pgvector.md`](file:///data/homelab/docs/pgvector.md).

- **Open Terminal Remote Shell & Agent Execution Substrate for Open WebUI**:
  - Integrated `open-terminal` (`ghcr.io/open-webui/open-terminal:latest`) on the isolated `ai` bridge network as a companion sandbox for Open WebUI v0.13.0+.
  - Configured persistent host bind mount at `/data/homelab/open-terminal/workspace` mapped to `/home/user` inside the container with UID 1000 permissions.
  - Hardened security with bearer token API authentication (`OPEN_TERMINAL_API_KEY`), 2 GB container memory cap, and no host port or Docker socket exposure.
  - Enabled `ENABLE_TOOL_SERVERS=True` and updated `open-webui` dependency chain in [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml).
  - Authored comprehensive service guide in [`docs/open-terminal.md`](file:///data/homelab/docs/open-terminal.md) and synchronized architecture documentation across [`README.md`](file:///data/homelab/README.md), [`AGENTS.md`](file:///data/homelab/AGENTS.md), and [`docs/README.md`](file:///data/homelab/docs/README.md).

### Deprecated & Removed
- **LiteLLM Gateway Decommissioning & PostgreSQL Archival**:
  - Decommissioned `litellm` container (`ghcr.io/berriai/litellm:main-latest`), removing the service definition, host port bindings, and PostgreSQL connection from [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml).
  - Exported final compressed database backup of LiteLLM spend logs and user keys to [`pgvector/archives/litellm_final_backup.sql.gz`](file:///data/homelab/pgvector/archives/litellm_final_backup.sql.gz) (9.3 MB) and decoupled PostgreSQL maintenance routines in [`scripts/pgvector-maintenance.sh`](file:///data/homelab/scripts/pgvector-maintenance.sh).
  - Deprecated legacy LiteLLM environment keys in [`.env.example`](file:///data/homelab/.env.example).
  - Archived service documentation to [`docs/archive/litellm.md`](file:///data/homelab/docs/archive/litellm.md).
- **Hindsight Long-Term Memory & Memlord MCP Decommissioning**:
  - Decommissioned `hindsight` (`ghcr.io/vectorize-io/hindsight`) and `memlord` (`ghcr.io/myrikld/memlord`) containers, removing both service blocks and pgvector environment variables from [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml).
  - Exported full compressed SQL dumps of both databases ([`archives/hindsight-dump-20261107.sql.gz`](file:///data/homelab/archives/hindsight-dump-20261107.sql.gz) and [`archives/memlord-dump-20261107.sql.gz`](file:///data/homelab/archives/memlord-dump-20261107.sql.gz)) and safely dropped `hindsight` and `memlord` databases and user roles from `pgvector`.
  - Purged downloaded ONNX model weights (`memlord/onnx/model.onnx`, 450 MB) and container images (`ghcr.io/vectorize-io/hindsight:latest` and `ghcr.io/myrikld/memlord:latest`), reclaiming ~7 GB of host storage.
  - Released ports `8888`, `9999`, and `8000`, and unregistered Traefik reverse proxy routers for `hindsight.spencer.lan`, `memlord.spencer.lan`, and WAN endpoints.
  - Removed Hindsight Memory and Memlord MCP tiles from Homepage dashboard ([`homepage/config/services.yaml`](file:///data/homelab/homepage/config/services.yaml)).
  - Modernized [`scripts/pgvector-maintenance.sh`](file:///data/homelab/scripts/pgvector-maintenance.sh) to vacuum and size active databases (`litellm`, `openwebui`, `authentik`, and `gitea`).
  - Sanitized obsolete `HINDSIGHT_*` and `MEMLORD_*` configuration variables from `.env` and [`.env.example`](file:///data/homelab/.env.example).
  - Archived service guides to [`docs/archive/hindsight.md`](file:///data/homelab/docs/archive/hindsight.md) and [`docs/archive/memlord.md`](file:///data/homelab/docs/archive/memlord.md).
- **Memlord Workspace Archival & Tree Cleanup**:
  - Removed obsolete `memlord/` workspace runtime directory and `.agents/skills/memlord/` agent skill following migration of all persistent memories to Open WebUI.
  - Purged obsolete `memlord/onnx/*` ignore patterns from [`.gitignore`](file:///data/homelab/.gitignore).
  - Preserved standalone [`SKILL.md`](file:///data/homelab/archives/deprecated-services/memlord/SKILL.md), service guide, repository asset archive, and database dump under `archives/deprecated-services/memlord/`.
  - Maintained `.agents/skills/.gitkeep` placeholder for future agent skill definitions.
- **Nous Research Hermes Agent Decommissioning & Workload Migration**:
  - Decommissioned `hermes` container (`nousresearch/hermes-agent:latest`) and removed the service definition, port allocations (`9119`, `8642`, `8765`), and environment variables from [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml).
  - Hardened host security posture by removing the host Docker socket (`/var/run/docker.sock`) volume mount and purging local execution sandbox images (`hermes-terminal:latest`) and cached weights, reclaiming ~6 GB of container image storage.
  - Migrated automated weekly database maintenance ([`scripts/pgvector-maintenance.sh`](file:///data/homelab/scripts/pgvector-maintenance.sh)) from Hermes's internal cron scheduler to the host user crontab (`0 3 * * 0 /data/homelab/scripts/pgvector-maintenance.sh`), preserving spend log pruning, HNSW reindexing, vacuuming, and ntfy alerts.
  - Performed final memory synchronization from Hindsight into Memlord and verified historical memory integration in Open WebUI's pgvector store.
  - Removed Traefik reverse proxy routers for `hermes.jamesspencer.me`, `hermes-api.spencer.lan`, and `mcp.spencer.lan`.
  - Decommissioned Authentik OIDC application and provider for Hermes.
  - Removed Hermes Agent and Hermes API & MCP tiles from Homepage dashboard ([`homepage/config/services.yaml`](file:///data/homelab/homepage/config/services.yaml)).
  - Archived complete runtime state to compressed storage (`archives/hermes-backup-20261107.tar.gz`), purged 726 MB of untracked runtime artifacts and state databases, moved service documentation to [`docs/archive/hermes.md`](file:///data/homelab/docs/archive/hermes.md), and archived the execution sandbox build context to [`docs/archive/hermes-terminal-image/`](file:///data/homelab/docs/archive/hermes-terminal-image/README.md).
  - Sanitized obsolete `HERMES_*` configuration keys from `.env` and [`.env.example`](file:///data/homelab/.env.example).

### Added
- **OmniRoute AI Gateway Deployment & Model Routing Migration**:
  - Deployed [OmniRoute](https://github.com/diegosouzapw/omniroute) (`diegosouzapw/omniroute:latest`) on internal port `20128` as the centralized LLM gateway and routing proxy across `net1`, `ai`, and `redis` networks, replacing LiteLLM.
  - Configured embedded local-first SQLite transactional storage ([`omniroute/data/storage.sqlite`](file:///data/homelab/omniroute/data/storage.sqlite)) backed by WAL mode, eliminating PostgreSQL runtime dependencies for LLM routing and spend logging.
  - Connected local inference engines: Ollama (`http://ollama:11434/v1`) for dense LLMs (`gemma4:12b`, `qwen2.5:14b`) and embeddings (`nomic-embed-text`), and MoMoE (`http://momoe:8080/v1`) for 64k MoE inference (`ornith-1.5-35b`, `momoe`).
  - Configured zero-latency model aliases (`gemma4:12b`, `qwen2.5:14b`, `momoe`, `nomic-embed-text`) in `key_value` table enabling un-prefixed OpenAI-compatible routing for Open WebUI and external developer tools.
  - Tuned context window limits and token compression for MoMoE: overridden context length to 65,536 tokens in `model_context_overrides` and configured adaptive context budgeting (`replace-autotrigger` with 4096 output reserve) and auto-trigger stacked compression (`rtk` + `caveman` at 45k tokens) to eliminate 400 context overflow errors.
  - Integrated Valkey cache on `redis://valkey:6379` over the `redis` Docker network for semantic caching and request throttling.
  - Reconfigured Traefik ingress (`llm.spencer.lan`) with wildcard TLS termination and direct access to OmniRoute's native Web UI dashboard and Bearer token API.
  - Updated Open WebUI chat and RAG embedding offload to target `http://omniroute:20128/v1`, updating both environment definitions and Open WebUI's database config.
  - Updated Homepage dashboard tile under `AI & Agents` to monitor OmniRoute health on `llm.spencer.lan`.
  - Authored comprehensive service guide in [`docs/omniroute.md`](file:///data/homelab/docs/omniroute.md).
- **Open WebUI Restoration & Upstream Upgrade (v0.13.0+)**:
  - Restored [Open WebUI](https://github.com/open-webui/open-webui) (`ghcr.io/open-webui/open-webui:main`, v0.13.0+) into the homelab stack, replacing the legacy isolated architecture.
  - Exposed publicly on WAN at `https://ai.jamesspencer.me` via Traefik reverse proxy with automated Let's Encrypt TLS certificate provisioning and CrowdSec edge bouncer protection.
  - Connected directly to unified [`pgvector`](file:///data/homelab/docker-compose.yaml#L98) PostgreSQL 16 database on the `db` network (database & user: `openwebui`), eliminating redundant standalone PostgreSQL containers.
  - Offloaded RAG and user memory vector embeddings to LiteLLM Proxy (`RAG_EMBEDDING_ENGINE=openai`, model: `nomic-embed-text`), eliminating in-container PyTorch/SentenceTransformers memory footprint and saving ~1 GB of host container RAM.
  - Configured dual model routing targeting LiteLLM Gateway (`http://litellm:4000/v1`) for MoMoE 64k and Ollama models, as well as direct Ollama fallback (`http://ollama:11434`).
  - Integrated local Firecrawl cluster (`http://firecrawl:3002`) on the `ai` network for headless web search grounding (`/v2/search`) and full-content markdown web scraping (`/v2/scrape`), with fallback SearXNG support.
  - Configured Traefik reverse proxy routing with dual host rules (`chat.spencer.lan` primary, `ai.spencer.lan` alias, and WAN domain) with wildcard TLS termination and CrowdSec bouncer protection.
  - Registered Open WebUI in Homepage dashboard under `AI & Agents` (`homepage/config/services.yaml`).
  - Created automated migration script [`scripts/import-memories-to-openwebui.py`](file:///data/homelab/scripts/import-memories-to-openwebui.py) and imported 412 deduplicated memories from Memlord and Hindsight into Open WebUI's user memory store with pgvector embeddings.
  - Authored comprehensive service documentation in [`docs/open-webui.md`](file:///data/homelab/docs/open-webui.md).
- **OpenBao Secrets & Encryption Management Service Deployment**:
  - Deployed [OpenBao](https://github.com/openbao/openbao) (`openbao/openbao:latest`, v2.7.2) stewarded under the Linux Foundation as an open-source identity-based secrets and transit encryption engine.
  - Configured internal-only Traefik ingress routing (`vault.spencer.lan` and `openbao.spencer.lan`) under entrypoint `websecure` with local wildcard TLS termination and no external public router.
  - Configured persistent Raft integrated transactional storage backend (`storage "raft"`) with mount path `./openbao/data` mapped to `/openbao/file`.
  - Configured non-root execution posture where container entrypoint manages volume permissions and drops privileges via `su-exec` to unprivileged user `openbao`.
  - Bound OpenBao to both `net1` (reverse proxy edge) and `ai` (internal AI agent communication via `http://openbao:8200`).
  - Added OpenBao healthcheck query with uninitialized and sealed HTTP code tolerances (`?uninitcode=200&sealedcode=200`).
  - Integrated OpenBao Vault into Homepage dashboard under `Core Infrastructure` (`homepage/config/services.yaml`).
  - Authored comprehensive service documentation in [`docs/openbao.md`](file:///data/homelab/docs/openbao.md) with initialization, unsealing, snapshot, and operational commands.
  - Fixed conditional block syntax in `pgvector/init/01-init-databases.sh`.
- **MoMoE Hybrid Mixture-of-Experts Inference Engine Deployment**:
  - Deployed [MoMoE](https://github.com/aflin/momoe) (`homelab/momoe:latest`) built natively from `./momoe/src` for NVIDIA RTX 3060 (`sm_86`) and Intel Xeon W-2145 (AVX-512 with 61 GiB quad-channel DDR4 RAM).
  - Attached strictly to the isolated `ai` network with no external ports or Traefik ingress (`http://momoe:8080/v1`).
  - Configured 2.5 GiB VRAM reservation (`MOMOE_VRAM_RESERVE_MIB=2560`) ensuring Ollama embeddings (`nomic-embed-text`) run reliably without OOM collisions.
  - Activated 65,536 context (`MOMOE_CONTEXT=65536`) with automated KV cache streaming into host DDR4 memory and Multi-Token Prediction (MTP) drafting, achieving 112.5 tok/s live throughput with a 73% GPU expert cache hit rate.
  - Implemented container entrypoint [`momoe/docker-entrypoint.sh`](file:///data/homelab/momoe/docker-entrypoint.sh) supporting CLI diagnostics and dynamic `VRAM_RESERVE_MIB` overrides.
- **LiteLLM Model Catalog & Security Hardening**:
  - Registered `ornith-1.5-35b` and `momoe` aliases targeting `http://momoe:8080/v1` with dynamic API key forwarding (`os.environ/MOMOE_API_KEY`), `max_tokens: 65536`, `max_input_tokens: 57344`, and `mode: chat`.
  - Forwarded `MOMOE_API_KEY` into `litellm` container environment in `docker-compose.yaml` and documented template in `.env.example`.
- **Hermes Agent Scraping & Resource Alignment**:
  - Aligned Hermes's Firecrawl web extraction and deep reasoning tools with the 64k MoMoE engine, providing unified context headroom and eliminating VRAM contention with dense Ollama models.
- **Observability & Service Dashboard Integration**:
  - Registered `MoMoE Engine` container in Homepage dashboard (`homepage/config/services.yaml`) under `AI & Agents` for real-time status monitoring.
- **Workspace Agent Guidelines**:
  - Added documentation synchronization rule to [`AGENTS.md`](file:///data/homelab/AGENTS.md) instructing AI agents to maintain root markdown files (`README.md`, `CHANGELOG.md`, `TODO.md`, `AGENTS.md`) upon every service or architecture change.

---

## [2026-10-03]

### Added
- **Memlord MCP Memory Server Deployment**:
  - Deployed [Memlord](https://github.com/MyrikLD/memlord) (`ghcr.io/myrikld/memlord:latest`) as a self-hosted Model Context Protocol (MCP) memory server featuring hybrid BM25 full-text and `pgvector` KNN vector search fused with Reciprocal Rank Fusion (RRF).
  - Provisioned dedicated `memlord` role and database with the `vector` extension enabled on the isolated `db` network in `pgvector/init/01-init-databases.sh`.
  - Configured local ONNX embedding runtime with persistent volume storage (`./memlord/onnx`) for zero external API or GPU dependencies.
  - Implemented dual-router Traefik ingress (`memlord.spencer.lan` / `${MEMLORD_PUBLIC_DOMAIN}`): protected Web UI via Authentik ForwardAuth (`authentik@file`) with direct client bypass for the `/mcp` Streamable HTTP endpoint.
  - Registered Memlord under "AI & Agents" in Homepage dashboard (`homepage/config/services.yaml`).
  - Authored comprehensive architecture and operational guide in [`docs/archive/memlord.md`](file:///data/homelab/docs/archive/memlord.md) and updated [`docs/README.md`](file:///data/homelab/docs/README.md) and [`TODO.md`](file:///data/homelab/TODO.md).
- **Automated Database & Vector Maintenance Pipeline**:
  - Implemented [`scripts/pgvector-maintenance.sh`](file:///data/homelab/scripts/pgvector-maintenance.sh) to automate periodic health and storage optimization for the homelab's `pgvector` PostgreSQL cluster.
  - **HNSW Vector Index Rebuilds**: Executes non-blocking `REINDEX TABLE CONCURRENTLY` for vector tables (`memory_units`, `mental_models`) and GIN full-text search indexes in Hindsight to prevent index graph fragmentation and search latency degradation.
  - **Spend Log & Task State Rotation**: Automatically exports aged records to compressed gzip CSV archives under `./pgvector/archives/` before pruning `LiteLLM_SpendLogs` (> 30 days default) and completed/failed `hindsight.async_operations` (> 14 days default).
  - **Cluster Vacuuming**: Executes `VACUUM (ANALYZE)` across `hindsight`, `litellm`, `authentik`, and `gitea` to reclaim storage and refresh PostgreSQL optimizer statistics.
  - **ntfy Push Notifications**: Dispatches formatted completion summaries (reclaimed counts, sizes, durations) to user devices via [`scripts/notify.sh`](file:///data/homelab/scripts/notify.sh).
  - **Hermes Cron Automation**: Registered weekly scheduled job (`6ff939ca35e2`, `0 3 * * 0`) in Hermes Agent's background scheduler with `--no-agent` mode for zero LLM overhead.
  - **Hermes DevOps Skill**: Created the `database-maintenance` skill (`hermes/skills/devops/database-maintenance/SKILL.md`) for conversational inspection and on-demand maintenance runs.
- **Push Notification Loopback Resolve**:
  - Enhanced [`scripts/notify.sh`](file:///data/homelab/scripts/notify.sh) with automatic Traefik loopback resolve (`--resolve push.spencer.lan:443:127.0.0.1`), ensuring push notifications dispatch reliably from host scripts when local LAN DNS is not configured on the host machine.
- **Hermes Custom Init & Skills Hub Quarantine Fix**:
  - Renamed `hermes/init/03-mcp-server.sh` to `hermes/init/03-custom-init.sh` and updated S6 volume mounts in [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml), [`.gitignore`](file:///data/homelab/.gitignore), and [`docs/archive/hermes.md`](file:///data/homelab/docs/archive/hermes.md) to reflect its expanded role handling boot supervision, custom CA injection, OIDC cookie handling, and runtime patching.
  - Resolved `FileExistsError` during skills hub bundle quarantine when community ZIPs contain directory entries without trailing slashes.
  - Integrated runtime filtering into `03-custom-init.sh` for `skills_hub_clawhub.py` and `skills_hub_install.py` to strip directory-name entries before file writing and quarantine scanning.


---

## [2026-10-01]

### Added
- **Homepage Dashboard Deployment**:
  - Deployed [Homepage](https://github.com/gethomepage/homepage) (`ghcr.io/gethomepage/homepage`) as the primary dashboard for Spencer's Homelab.
  - Bound to `net1` and `ai` networks behind Traefik reverse proxy on internal port `3000` (`home.spencer.lan`, `homepage.spencer.lan`).
  - Integrated Authentik ForwardAuth SSO (`authentik@file`) for secure local LAN access and optional WAN routing.
  - Mounted read-only Docker daemon socket (`/var/run/docker.sock:ro`) with `docker.yaml` for live container telemetry (health, CPU, memory).
  - Created declarative YAML configs under [`homepage/config/`](file:///data/homelab/homepage/config): `settings.yaml` (dark slate theme, grid layouts), `services.yaml` (AI & Agents, Search & Scrape, Core Infrastructure, Developer Tools, Backend Storage), `widgets.yaml` (SearXNG search bar and system resource metrics), and `bookmarks.yaml` (documentation and repository references).
  - Added service documentation in [`docs/homepage.md`](file:///data/homelab/docs/homepage.md) and updated [`docs/README.md`](file:///data/homelab/docs/README.md), [`AGENTS.md`](file:///data/homelab/AGENTS.md), and [`TODO.md`](file:///data/homelab/TODO.md).

---

## [2026-09-29]

### Removed
- **Infisical Secret Manager & Agent Vault Retirement**:
  - Removed `infisical` and `agent-vault` service definitions and Traefik routing rules from [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml).
  - Reverted HTTP/HTTPS egress proxying (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`), custom root CA bundle mounts (`ca.pem`, `ca-bundle.crt`), and service dependencies across downstream containers: [`searxng`](file:///data/homelab/docker-compose.yaml), [`litellm`](file:///data/homelab/docker-compose.yaml), [`hermes`](file:///data/homelab/docker-compose.yaml), [`playwright-service`](file:///data/homelab/docker-compose.yaml), and [`firecrawl`](file:///data/homelab/docker-compose.yaml), fixing Playwright proxy authentication (HTTP 407) restart loops.
  - Removed conditional role and database creation routines for `agentvault` and `infisical` from [`pgvector/init/01-init-databases.sh`](file:///data/homelab/pgvector/init/01-init-databases.sh).
  - Stripped all `INFISICAL_*`, `AGENTVAULT_*`, `AGENT_VAULT_*`, and agent proxy token variables from [`.env.example`](file:///data/homelab/.env.example) and local [`.env`](file:///data/homelab/.env).
  - Cleaned up the `agent-vault/` volume directory, certificates, and `.gitignore` patterns.
  - Archived service documentation to [`docs/archive/infisical.md`](file:///data/homelab/docs/archive/infisical.md) and [`docs/archive/agent-vault.md`](file:///data/homelab/docs/archive/agent-vault.md).
  - Updated architecture indexes, service catalogs, and operational guides across [`README.md`](file:///data/homelab/README.md), [`AGENTS.md`](file:///data/homelab/AGENTS.md), [`TODO.md`](file:///data/homelab/TODO.md), and [`docs/`](file:///data/homelab/docs/README.md).

---

## [2026-09-04]

### Changed
- **Context Window Restoration (65,536 Tokens Everywhere)**:
  - Created [`ollama/Modelfile`](file:///data/homelab/ollama/Modelfile) with `PARAMETER num_ctx 65536` and rebuilt the `qwen2.5:14b` model manifest to prevent Ollama from defaulting to 2048/4096 tokens.
  - Added `OLLAMA_CONTEXT_LENGTH=65536` and enabled `OLLAMA_FLASH_ATTENTION=1` in [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml).
  - Configured `num_ctx: 65536`, `max_tokens: 65536`, and `max_input_tokens: 65536` under `model_list` in [`litellm/config.yaml`](file:///data/homelab/litellm/config.yaml).
  - Synchronized `context_length: 65536` and `ollama_num_ctx: 65536` in `hermes/config.yaml` and `hermes/context_length_cache.yaml`.
- **LiteLLM Spend Logs & Dynamic Model Storage**:
  - Enabled `store_model_in_db: true` and `store_prompts_in_spend_logs: true` in [`litellm/config.yaml`](file:///data/homelab/litellm/config.yaml) and `STORE_MODEL_IN_DB=True` in [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml).
  - Documented database persistence and spend log tracking in [`docs/archive/litellm.md`](file:///data/homelab/docs/archive/litellm.md).
- **Hermes Agent Configuration Sync**:
  - Updated `hermes/config.yaml` to Hermes Agent schema v39.
  - Configured `auxiliary` pipeline routing `curator` and `background_review` through `litellm` (`qwen2.5:14b`).
  - Synced discovered model registry mapping under `custom_providers` and configured skill curation retention intervals (`stale_days: 30`, `archive_days: 90`).

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
  - Implemented dual-transport MCP server in `hermes/scripts/hermes_mcp_server.py` wrapping Hermes `model_tools.handle_function_call`.
  - Exposes 13 homelab tools to external AI clients: `web_search` (SearXNG), `web_extract` (Firecrawl), `execute_code`, `terminal`, `process` (Docker sandbox), `read_file`, `write_file`, `patch`, `search_files` (workspace), `vision_analyze` (multimodal vision), `text_to_speech` (TTS), and `skills_list` / `skill_view` (Hermes skills).
  - Integrated into existing `hermes` container via s6-overlay boot script (`hermes/init/03-custom-init.sh`) for automatic process supervision, failure recovery, and unified resource footprint without running duplicate containers.
  - Added Traefik edge routing on `net1` for `https://mcp.spencer.lan/sse` and message ingress at `/messages/` (port `8765`).
  - Enforced Bearer token authentication via `HERMES_MCP_KEY` with unauthenticated `/health` endpoint for monitoring.
  - Added client configuration examples for Claude Desktop (SSE and direct Docker stdio), Cursor / IDE extensions, and external MCP clients to [`docs/archive/hermes.md`](file:///data/homelab/docs/archive/hermes.md).

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
  - Declared explicit 64K context window metadata (`max_tokens: 65536`) for `qwen2.5:14b` in [`litellm/config.yaml`](file:///data/homelab/litellm/config.yaml) and registered `custom_providers` entry in `hermes/config.yaml`.
  - Verified end-to-end inference routing with automated token tracking and persistence in `pgvector` (`LiteLLM_SpendLogs`).
- **Hermes Agent Docker Sandbox Execution Environment**:
  - Mounted `/var/run/docker.sock` into the `hermes` container with `TERMINAL_ENV=docker`, `TERMINAL_DOCKER_IMAGE=nikolaik/python-nodejs:python3.11-nodejs20`, and `TERMINAL_CONTAINER_PERSISTENT=false`.
  - Enabled `terminal`, `process`, and `execute_code` toolsets in `hermes/config.yaml` across CLI, API server, and Gateway platforms.
  - Hardened sandbox execution with dropped Linux capabilities (`--cap-drop ALL`), disabled privilege escalation (`--security-opt no-new-privileges`), PID limit ceilings, and in-memory tmpfs scratch filesystems (`/workspace`, `/home`, `/root`).
- **Hindsight Long-Term Memory Container (`hindsight`)**:
  - Deployed `ghcr.io/vectorize-io/hindsight:${HINDSIGHT_VERSION:-latest}` service dual-homed on `ai` and `db` networks.
  - Connected Hindsight to the dedicated `pgvector` instance on `db` network (`postgresql://hindsight:...@pgvector:5432/hindsight`) with `pgvector` vector extension.
  - Connected Hindsight to local Ollama (`qwen2.5:14b`) via `http://ollama:11434/v1` on `ai` network for entity extraction and memory reflection, with concurrency limited to 1.
  - Added Traefik edge routing on `net1` for Hindsight Control Plane Web UI at `https://hindsight.spencer.lan` (port `9999`).
  - Added container healthcheck targeting `http://localhost:8888/health`.
  - Created service documentation in [`docs/archive/hindsight.md`](file:///data/homelab/docs/archive/hindsight.md) and updated service index in [`docs/README.md`](file:///data/homelab/docs/README.md).
- **Hermes Agent Hindsight Integration**:
  - Configured `hermes` container with `HINDSIGHT_MODE=local_external`, `HINDSIGHT_API_URL=http://hindsight:8888`, and `HINDSIGHT_BANK_ID=hermes`.
  - Added `hindsight` to `depends_on` for `hermes` service in `docker-compose.yaml`.
  - Activated `hindsight` memory provider in `hermes/config.yaml`.
  - Provisioned profile memory config in `hermes/hindsight/config.json` with auto-recall and auto-retain enabled.
  - Updated [`docs/archive/hermes.md`](file:///data/homelab/docs/archive/hermes.md) with memory backend architecture diagram and tool descriptions.
- **Dedicated pgvector Instance (`pgvector`)**:
  - Added standalone `pgvector` container running `pgvector/pgvector:${PGVECTOR_VERSION:-pg16}` for Hindsight long-term memory engine and future homelab microservices, decoupled from legacy databases.
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
  - Added individual service guides: `traefik.md`, `ollama.md`, `hermes.md`, `firecrawl.md`, `searxng.md`, and `valkey.md`.
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
  - Configured Playwright web loader engine to use `ws://browserless:3000` for rendering JavaScript-heavy websites.
- **pgvector Database Backend**:
  - Added `pgvector/pgvector:pg16` database service on an isolated `db` network.
  - Migrated relational data and document embeddings to PostgreSQL with `pgvector`.
- **Initial Homelab Architecture**:
  - Deployed Traefik reverse proxy with local TLS certificate termination and dashboard at `https://traefik.spencer.lan`.
  - Deployed Ollama LLM runtime with NVIDIA GPU hardware acceleration passthrough.
  - Deployed initial chat interface at `https://ai.spencer.lan`.
  - Deployed sandboxed code interpreter environment.
  - Deployed SearXNG privacy metasearch engine with Valkey key-value caching backend.
