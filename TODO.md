# 📋 Spencer's Homelab Roadmap & Todo

This file tracks upcoming features, architectural improvements, and exploration initiatives for the homelab.

---

## 🎯 Active Initiatives & Roadmap

### 1. 💾 Automated Backup & Disaster Recovery Pipeline
- [ ] **Automated `pgvector` Backups**: Implement a lightweight backup sidecar or scheduled maintenance script executing transactional dumps (`pg_dumpall` or per-database `pg_dump`: `openwebui`, `authentik`, `gitea`) with retention rotation (e.g., 7 daily, 4 weekly).
- [ ] **Encrypted State Archiving**: Snapshot critical runtime volumes (`./authentik/media`, `./traefik/certs`, `./pgvector/data`, `./omniroute/data`) using encrypted backup utilities (e.g., Restic or Borg).
- [ ] **Local NAS Replication**: Configure automated synchronization of encrypted snapshots and database dumps to the local NAS (via NFS/SMB mount or SSH/rsync) with retention cleanup.
- [ ] **Restore & Recovery Runbook**: Document step-by-step restoration procedures in `docs/` and verify point-in-time recovery for database and certificate state.

---

### 2. 📲 Self-Hosted Push Notifications & System Alerts (ntfy)
- [ ] **Backup Event Dispatch**: Wire automated backup and NAS replication events to dispatch alerts to ntfy upon pipeline deployment.

---

### 3. 🔀 OmniRoute AI Gateway & Intelligent Multi-Tier Model Routing
- [x] **OmniRoute Gateway Deployment**: Replaced LiteLLM with OmniRoute (`diegosouzapw/omniroute:latest`) on `https://llm.spencer.lan` (internal port `20128`) with SQLite transactional storage, eliminating PostgreSQL database coupling.
- [x] **Local Engine Integration & Model Aliases**: Connected Ollama (`http://ollama:11434/v1`) and MoMoE (`http://momoe:8080/v1`), mapping zero-prefix aliases for `gemma4:12b`, `qwen2.5:14b`, `ornith-1.5-35b`, `momoe`, and `nomic-embed-text`.
- [x] **Client Switchover & Verification**: Re-routed Open WebUI chat and RAG embeddings to `http://omniroute:20128/v1`, verified full test suite (14/14 passing).
- [x] **Cache & Database Maintenance**: Connected Valkey cache on `redis` network, archived final LiteLLM database backup (`archives/litellm_final_backup.sql.gz`), and updated `scripts/pgvector-maintenance.sh`.
- [ ] **Automated Local-to-Cloud Fallback**: Configure multi-provider fallback chains in OmniRoute so if local Ollama or MoMoE encounters high latency, GPU saturation, or errors, requests automatically failover to cloud providers (e.g., DeepSeek-V3 or Groq).
- [ ] **Model Tiering by Capability**: Dynamically dispatch fast classification, code execution, and complex reasoning tasks to optimal backends via custom OmniRoute routing rules.
- [ ] **Budget & Token Rate Limiting**: Configure spend caps and TPM (tokens per minute) rate limits per virtual key in OmniRoute to prevent runaway agent loops.

---

### 4. 🛑 Hermes Agent Decommissioning & Workload Migration
- [x] **Decommission Hermes Agent Container**: Stopped and removed `nousresearch/hermes-agent:latest` container from `docker-compose.yaml`, freeing host ports `9119`, `8642`, `8765`, and eliminating the `/var/run/docker.sock` privilege exposure.
- [x] **Cron & Task Migration**: Migrated `pgvector-maintenance.sh` from Hermes internal scheduler to host crontab (`0 3 * * 0 /data/homelab/scripts/pgvector-maintenance.sh`), verified dry-run and ntfy notifications.
- [x] **Data Archival & Storage Reclamation**: Created timestamped compressed archive `archives/hermes-backup-20261107.tar.gz`, pruned untracked runtime cruft (`state.db`, caches, lockfiles), and deleted local Docker execution sandbox images (`hermes-terminal:latest`).
- [x] **Ingress, SSO & Homepage Clean-up**: Unregistered Traefik routers (`hermes.jamesspencer.me`, `hermes-api.spencer.lan`, `mcp.spencer.lan`), decommissioned Authentik OIDC integration, and removed tiles from Homepage.
- [x] **Documentation & Architecture Synchronization**: Archived `docs/hermes.md` to `docs/archive/hermes.md`, moved `hermes-terminal-image/` to `docs/archive/hermes-terminal-image/`, and updated `README.md`, `AGENTS.md`, and service guides.

---

### 5. 📈 NVIDIA GPU & System Telemetry (Prometheus + Grafana + DCGM)
- [ ] **NVIDIA GPU Exporter**: Deploy `dcgm-exporter` or `nvidia-gpu-exporter` with GPU pass-through to monitor vRAM allocation, tensor core utilization, temperatures, and power draw during Ollama inference.
- [ ] **Service Metrics Ingestion**: Scrape Prometheus metrics from Traefik (`:8080/metrics`), LiteLLM (`:4000/metrics`), and CrowdSec Local API.
- [ ] **Unified Homelab Grafana Dashboard**: Create a single-pane dashboard displaying real-time LLM tokens/sec throughput, cache hit ratios in Valkey, active Traefik connections, and agent memory usage.

---

### 6. 🎙️ Fully Offline Voice & Speech AI Stack (Piper & Faster-Whisper)
- [ ] **Local Text-to-Speech (Piper)**: Deploy a containerized Piper TTS server on the `ai` network for low-latency neural speech generation.
- [ ] **Local Speech-to-Text (Faster-Whisper)**: Deploy a GPU-accelerated Whisper endpoint on the `ai` network for local speech transcription.
- [ ] **Open WebUI Voice Integration**: Route Open WebUI's voice and audio tools to local Piper and Whisper endpoints instead of cloud APIs.

---

### 7. 🛑 Memlord & Hindsight Decommissioning & Memory Consolidation
- [x] **Consolidate Memories into Open WebUI**: Imported 400+ procedural rules and conversational memory units from Memlord and Hindsight into Open WebUI's native PostgreSQL memory store (`openwebui` database on pgvector).
- [x] **Database Dumps & Archival**: Generated full compressed SQL dumps for both `hindsight` (1.1 MB) and `memlord` (686 KB) under `archives/` before dropping databases from pgvector.
- [x] **Decommission Containers & Purge Images**: Stopped and removed `hindsight` and `memlord` containers, removed Traefik routers (`hindsight.spencer.lan`, `memlord.spencer.lan`), deleted downloaded ONNX models (`model.onnx`, 450 MB), and purged container images, reclaiming ~7 GB of storage.
- [x] **Configuration & Maintenance Updates**: Removed `HINDSIGHT_*` and `MEMLORD_*` keys from `.env` and `.env.example`, updated `scripts/pgvector-maintenance.sh` to vacuum active databases (`openwebui`, `litellm`, `authentik`, `gitea`), and archived documentation to `docs/archive/`.

---

### 8. ⚡ Hybrid Mixture-of-Experts (MoE) Inference Engine (MoMoE)
- [x] **Architecture Research & Candidate Selection**: Explored Strata, aflin/momoe, KTransformers, and ik_llama.cpp for combining GPU VRAM and host quad-channel DDR4 memory.
- [x] **Container Deployment & Build Optimization**: Cloned `aflin/momoe` into `momoe/src`, compiled native CUDA 86 binary for RTX 3060 (`homelab/momoe:latest`), and deployed on the `ai` bridge with custom entrypoint and 2.5 GiB VRAM reservation for Ollama coexistence.
- [x] **LiteLLM Model Routing & 64k KV Streaming**: Integrated `ornith-1.5-35b` and `momoe` into LiteLLM Proxy with 65,536 context (`MOMOE_CONTEXT=65536`) utilizing RAM KV cache streaming, MTP speculative drafting (112.5 tok/s live throughput), and dynamic API key forwarding.
- [x] **Hermes Agent Scraping & Tool Alignment**: Aligned Hermes's Firecrawl web extraction and deep reasoning tools with the 64k MoMoE engine, eliminating VRAM contention with dense Ollama models.
- [x] **Multi-Agent Code Review & Documentation**: Conducted 4-agent security, systems, routing, and standards audit; updated `AGENTS.md`, `README.md`, `docs/momoe.md`, `docs/litellm.md`, `docs/ollama.md`, and Homepage dashboard.

---

### 9. 🔐 Centralized Secret & Encryption Management (OpenBao)
- [x] **Deploy OpenBao Vault**: Deployed Linux Foundation OpenBao (`openbao/openbao:latest`, v2.7.2) with persistent Raft integrated transactional storage.
- [x] **Internal Traefik Routing**: Configured secure internal-only routing under `https://vault.spencer.lan` and `https://openbao.spencer.lan` with wildcard TLS certificate and no public exposure.
- [x] **Isolated Networking & Privilege Posture**: Attached to `net1` for Traefik ingress and `ai` for internal agent/service access; configured drop-root initialization running as unprivileged `openbao` user.
- [x] **Observability & Health Monitoring**: Added custom healthcheck with uninitialized/sealed tolerance; integrated OpenBao into Homepage dashboard under `Core Infrastructure`.
- [x] **Documentation & Runbooks**: Authored comprehensive guide in [`docs/openbao.md`](file:///data/homelab/docs/openbao.md) with Web UI / CLI initialization, unsealing, snapshot backups, and operational commands.

---

### 10. 💬 Open WebUI Restoration & Cross-AI Memory Synchronization
- [x] **Upstream Release Deployment**: Deployed latest `ghcr.io/open-webui/open-webui:main` (v0.13.0+) on `net1`, `ai`, and `db` networks.
- [x] **Unified PostgreSQL & pgvector Integration**: Connected to shared `pgvector` container with dedicated `openwebui` database/user, eliminating standalone DB containers.
- [x] **Embedding Offload to LiteLLM**: Configured `RAG_EMBEDDING_ENGINE=openai` pointing to LiteLLM's `nomic-embed-text` endpoint, freeing ~1 GB of container RAM.
- [x] **Dual Model Providers & Grounding**: Integrated LiteLLM Proxy (exposing hybrid MoMoE 64k and local Ollama) plus SearXNG search grounding.
- [x] **Cross-AI Memory Import**: Migrated 400+ persistent procedural knowledge and conversational memory units from Memlord and Hindsight into Open WebUI.
- [x] **Traefik Ingress & Homepage**: Configured dual routing on `chat.spencer.lan` and `ai.spencer.lan` with CrowdSec bouncer, and registered under "AI & Agents" in Homepage.

---

### 11. 💻 Open Terminal Agent Execution Substrate (Open WebUI)
- [x] **Container Deployment & Network Integration**: Deployed `open-terminal` (`ghcr.io/open-webui/open-terminal:latest`) on the isolated `ai` network with 2 GB memory cap and healthchecks.
- [x] **Workspace Storage & Permission Architecture**: Created persistent bind mount `./open-terminal/workspace` to `/home/user` with UID:GID 1000 permissions and zero git leakage.
- [x] **Security Hardening**: Enforced bearer token authentication via `OPEN_TERMINAL_API_KEY` across `.env`, `.env.passwords`, and `.env.example`; eliminated host port exposure and Docker socket passthrough.
- [x] **Multi-Phase Function Testing**: Execute container health probe, inter-service API auth verification, filesystem persistence probe, and Open WebUI end-to-end tool-calling test.
- [x] **Documentation Synchronization**: Authored [`docs/open-terminal.md`](file:///data/homelab/docs/open-terminal.md), updated [`README.md`](file:///data/homelab/README.md), [`AGENTS.md`](file:///data/homelab/AGENTS.md), and [`docs/README.md`](file:///data/homelab/docs/README.md).
