# 📋 Spencer's Homelab Roadmap & Todo

This file tracks upcoming features, architectural improvements, and exploration initiatives for the homelab.

---

## 🎯 Active Initiatives & Roadmap

### 1. 💾 Automated Backup & Disaster Recovery Pipeline
- [ ] **Automated `pgvector` Backups**: Implement a lightweight backup sidecar or scheduled maintenance script executing transactional dumps (`pg_dumpall` or per-database `pg_dump`: `hindsight`, `litellm`, `authentik`) with retention rotation (e.g., 7 daily, 4 weekly).
- [ ] **Encrypted State Archiving**: Snapshot critical runtime volumes (`./authentik/media`, `./traefik/certs`, `./hermes/hindsight`) using encrypted backup utilities (e.g., Restic or Borg).
- [ ] **Local NAS Replication**: Configure automated synchronization of encrypted snapshots and database dumps to the local NAS (via NFS/SMB mount or SSH/rsync) with retention cleanup.
- [ ] **Restore & Recovery Runbook**: Document step-by-step restoration procedures in `docs/` and verify point-in-time recovery for database and certificate state.

---

### 2. 📲 Self-Hosted Push Notifications & System Alerts (ntfy / Gotify)
- [x] **Deploy Notification Gateway**: Run a lightweight notification server (`ntfy` or `gotify`) behind Traefik (`push.spencer.lan`) with Authentik ForwardAuth protecting the web interface.
- [ ] **Backup & Security Event Dispatch**: Configured CrowdSec IP ban alerts and Authentik security events to dispatch to ntfy; pending local NAS backup script wiring in Phase 2.
- [x] **Hermes Notification Webhook**: Provided Hermes Agent with the `push-notifications` skill, helper script (`/opt/data/scripts/notify.sh`), and `send_notification` MCP tool to dispatch alerts to `http://ntfy:80/hermes`.

---

### 3. 🔀 Intelligent Multi-Tier Model Routing & Fallback Chains (LiteLLM)
- [ ] **Automated Local-to-Cloud Fallback**: Configure LiteLLM fallback chains so if local Ollama (`qwen2.5:14b`) encounters high latency, GPU saturation, or errors, requests automatically failover to cloud providers (e.g., DeepSeek-V3 or Groq).
- [ ] **Model Tiering by Capability**: Dynamically dispatch fast classification, code execution, and complex reasoning tasks to optimal backends.
- [ ] **Budget & Token Rate Limiting**: Configure spend caps and TPM (tokens per minute) rate limits per virtual key in LiteLLM to prevent runaway agent loops.

---

### 4. ⏰ Hermes Proactive Schedules & Autonomous Briefings
- [ ] **Daily Briefing Routine**: Configure a scheduled cron task for Hermes to run at 7:00 AM daily, querying SearXNG and Firecrawl for top news/releases, auditing homelab container status, and dispatching a formatted digest.
- [ ] **Autonomous Workspace & Dependency Hygiene**: Set up recurring agent routines to inspect repository dependencies, review git history, and suggest maintenance tasks.
- [ ] **Homelab Webhook Trigger Gateway**: Expose an authenticated webhook endpoint allowing external events (e.g. GitHub releases, RSS feeds, server events) to trigger Hermes to investigate and synthesize an analysis.

---

### 5. 📈 NVIDIA GPU & System Telemetry (Prometheus + Grafana + DCGM)
- [ ] **NVIDIA GPU Exporter**: Deploy `dcgm-exporter` or `nvidia-gpu-exporter` with GPU pass-through to monitor vRAM allocation, tensor core utilization, temperatures, and power draw during Ollama inference.
- [ ] **Service Metrics Ingestion**: Scrape Prometheus metrics from Traefik (`:8080/metrics`), LiteLLM (`:4000/metrics`), and CrowdSec Local API.
- [ ] **Unified Homelab Grafana Dashboard**: Create a single-pane dashboard displaying real-time LLM tokens/sec throughput, cache hit ratios in Valkey, active Traefik connections, and agent memory usage.

---

### 6. 🎙️ Fully Offline Voice & Speech AI Stack (Piper & Faster-Whisper)
- [ ] **Local Text-to-Speech (Piper)**: Deploy a containerized Piper TTS server on the `ai` network for low-latency neural speech generation.
- [ ] **Local Speech-to-Text (Faster-Whisper)**: Deploy a GPU-accelerated Whisper endpoint on the `ai` network for local speech transcription.
- [ ] **Hermes Audio Tools Integration**: Route Hermes's voice and audio tools to local Piper and Whisper endpoints instead of cloud APIs.

---

### 7. 🔍 Periodic Database & Vector Maintenance Automation
- [x] **Automated Vector Index Optimization**: Implemented scheduled maintenance pipeline (`scripts/pgvector-maintenance.sh`) executing concurrent HNSW vector and GIN text index rebuilds (`memory_units`, `mental_models`) in Hindsight.
- [x] **Session & Spend Log Rotation**: Configured automated archival (gzip CSVs in `pgvector/archives/`) and pruning for aged `LiteLLM_SpendLogs` (> 30d) and Hindsight `async_operations` (> 14d) with cluster-wide `VACUUM ANALYZE`.
- [x] **Hermes Proactive Cron & Alerts**: Registered weekly background maintenance job (`6ff939ca35e2`) in Hermes scheduler with ntfy push completion notifications and provided Hermes with the `database-maintenance` skill.

---

### 8. 🧠 Agentic Memory & Reinforcement Learning MCP Server (memlord)
- [ ] **Evaluate Memlord Architecture**: Investigate [`memlord`](https://github.com/MyrikLD/memlord) (self-hosted MCP memory server with reinforcement learning, time decay, and self-correcting agent memory) as a specialized per-project memory layer or alternative alongside Hindsight.
- [ ] **MCP Server Deployment**: Deploy `memlord` as a container on the `ai` network and configure it as an MCP server for Hermes Agent.
- [ ] **Memory Decay & Weight Tuning**: Validate memory persistence, weight-based reinforcement adjustments, and time decay across Hermes agent sessions.

---

### 9. 🧭 Centralized Homelab Dashboard & Status Portal (Homepage)
- [x] **Deploy Homepage Service**: Containerized Homepage (`ghcr.io/gethomepage/homepage`) deployed on `net1` and `ai` networks behind Traefik (`home.spencer.lan`, `homepage.spencer.lan`) with Authentik ForwardAuth SSO.
- [x] **Service Grouping & Icons**: Declarative `services.yaml` cataloging AI & Agents, Core Infrastructure, Search & Intelligence, Developer Tools & Ops, and Backend Storage.
- [x] **Live Container & System Telemetry**: Read-only Docker socket binding (`/var/run/docker.sock:ro`) for live container states, CPU, memory, and SearXNG search widget.
- [x] **Authentik Outpost Proxy Registration**: Completed binding of `https://home.spencer.lan` in the Authentik Admin interface under Embedded Outpost.
