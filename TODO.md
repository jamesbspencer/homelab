# 📋 Spencer's Homelab Roadmap & Todo

This file tracks upcoming features, architectural improvements, and exploration initiatives for the homelab.

---

## 🎯 Active Initiatives & Roadmap

### 1. 🛡️ Deep Agent Vault Integration & Secret Brokering
- [ ] **Wire Hermes Agent to Agent Vault MITM Proxy**: Mount `./agent-vault/data/ca.pem` into the `hermes` container and configure proxy environment variables (`HTTP_PROXY`, `HTTPS_PROXY` pointing to `http://<token>@agent-vault:14322`) alongside CA trust bundles (`REQUESTS_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE`, `CURL_CA_BUNDLE`).
- [ ] **Define Placeholder Credential Schemas**: Replace direct cloud API keys (e.g., Anthropic, OpenAI, GitHub, Telegram) with placeholder tokens (e.g., `__anthropic_api_key__`, `__github_token__`) to ensure zero raw credentials exist in Hermes prompt contexts or container environments.
- [ ] **End-to-End Validation**: Verify outbound requests through the MITM proxy successfully substitute secrets and validate that audit logs in Agent Vault record brokered traffic.

---

### 2. 💾 Automated Backup & Disaster Recovery Pipeline
- [ ] **Automated `pgvector` Backups**: Implement a lightweight backup sidecar or scheduled maintenance script executing transactional dumps (`pg_dumpall` or per-database `pg_dump`: `hindsight`, `litellm`, `authentik`, `agentvault`) with retention rotation (e.g., 7 daily, 4 weekly).
- [ ] **Encrypted State Archiving**: Snapshot critical runtime volumes (`./agent-vault/data`, `./authentik/media`, `./traefik/certs`, `./hermes/hindsight`) using encrypted backup utilities (e.g., Restic or Borg).
- [ ] **Local NAS Replication**: Configure automated synchronization of encrypted snapshots and database dumps to the local NAS (via NFS/SMB mount or SSH/rsync) with retention cleanup.
- [ ] **Restore & Recovery Runbook**: Document step-by-step restoration procedures in `docs/` and verify point-in-time recovery for database and certificate state.
