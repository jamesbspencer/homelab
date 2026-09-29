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

### 3. 📲 Self-Hosted Push Notifications & System Alerts (ntfy / Gotify)
- [x] **Deploy Notification Gateway**: Run a lightweight notification server (`ntfy` or `gotify`) behind Traefik (`push.spencer.lan`) with Authentik ForwardAuth protecting the web interface.
- [ ] **Backup & Security Event Dispatch**: Configured CrowdSec IP ban alerts and Authentik security events to dispatch to ntfy; pending local NAS backup script wiring in Phase 2.
- [x] **Hermes Notification Webhook**: Provided Hermes Agent with the `push-notifications` skill, helper script (`/opt/data/scripts/notify.sh`), and `send_notification` MCP tool to dispatch alerts to `http://ntfy:80/hermes`.

---

### 4. 🔀 Intelligent Multi-Tier Model Routing & Fallback Chains (LiteLLM)
- [ ] **Automated Local-to-Cloud Fallback**: Configure LiteLLM fallback chains so if local Ollama (`qwen2.5:14b`) encounters high latency, GPU saturation, or errors, requests automatically failover to cloud providers (e.g., DeepSeek-V3 or Groq).
- [ ] **Model Tiering by Capability**: Dynamically dispatch fast classification, code execution, and complex reasoning tasks to optimal backends.
- [ ] **Budget & Token Rate Limiting**: Configure spend caps and TPM (tokens per minute) rate limits per virtual key in LiteLLM to prevent runaway agent loops.

---

### 5. ⏰ Hermes Proactive Schedules & Autonomous Briefings
- [ ] **Daily Briefing Routine**: Configure a scheduled cron task for Hermes to run at 7:00 AM daily, querying SearXNG and Firecrawl for top news/releases, auditing homelab container status, and dispatching a formatted digest.
- [ ] **Autonomous Workspace & Dependency Hygiene**: Set up recurring agent routines to inspect repository dependencies, review git history, and suggest maintenance tasks.
- [ ] **Homelab Webhook Trigger Gateway**: Expose an authenticated webhook endpoint allowing external events (e.g. GitHub releases, RSS feeds, server events) to trigger Hermes to investigate and synthesize an analysis.

---

### 6. 📈 NVIDIA GPU & System Telemetry (Prometheus + Grafana + DCGM)
- [ ] **NVIDIA GPU Exporter**: Deploy `dcgm-exporter` or `nvidia-gpu-exporter` with GPU pass-through to monitor vRAM allocation, tensor core utilization, temperatures, and power draw during Ollama inference.
- [ ] **Service Metrics Ingestion**: Scrape Prometheus metrics from Traefik (`:8080/metrics`), LiteLLM (`:4000/metrics`), and CrowdSec Local API.
- [ ] **Unified Homelab Grafana Dashboard**: Create a single-pane dashboard displaying real-time LLM tokens/sec throughput, cache hit ratios in Valkey, active Traefik connections, and agent memory usage.

---

### 7. 🎙️ Fully Offline Voice & Speech AI Stack (Piper & Faster-Whisper)
- [ ] **Local Text-to-Speech (Piper)**: Deploy a containerized Piper TTS server on the `ai` network for low-latency neural speech generation.
- [ ] **Local Speech-to-Text (Faster-Whisper)**: Deploy a GPU-accelerated Whisper endpoint on the `ai` network for local speech transcription.
- [ ] **Hermes Audio Tools Integration**: Route Hermes's voice and audio tools to local Piper and Whisper endpoints instead of cloud APIs.

---

### 8. 🔍 Periodic Database & Vector Maintenance Automation
- [ ] **Automated Vector Index Optimization**: Implement scheduled maintenance jobs to rebuild and optimize HNSW vector indexes as Hindsight memory entries grow.
- [ ] **Session & Spend Log Rotation**: Configure automated vacuuming, pruning, and archiving for aged LiteLLM spend logs and ephemeral task states in `pgvector`.
