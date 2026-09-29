# [ARCHIVED] Infisical Agent Vault - AI Agent Credential Proxy & Broker

> [!NOTE]
> **Status: Retired / Archived**
> Agent Vault has been removed from Spencer's Homelab stack. This documentation is retained for reference and historical architecture patterns.

**Infisical Agent Vault** ([GitHub](https://github.com/Infisical/agent-vault)) is an open-source credential broker and HTTP/HTTPS transparent MITM proxy that sits between AI agents and the APIs they call. It eliminates credential exfiltration risk by keeping secrets strictly off agent hosts and out of agent prompts and runtimes.

---

## 🎯 Overview & Architecture

* **Role**: HTTP credential broker, secret injection proxy, and agent access firewall.
* **Container Name**: `agent-vault`
* **Image**: `infisical/agent-vault:${AGENTVAULT_VERSION:-latest}`
* **Networks**:
  * `net1`: Traefik reverse proxy bridge for the Web UI & Control API (`vault.spencer.lan`, `agent-vault.spencer.lan`).
  * `ai`: Internal network for Docker agents (Hermes Agent, sandboxes) to access the proxy (`http://agent-vault:14322`).
  * `db`: Connection to the dedicated `pgvector` PostgreSQL container for encrypted persistence and CA management.
* **Ports & Ingress**:
  * **Web UI & Control API**: `https://vault.spencer.lan` (and `https://agent-vault.spencer.lan`) via Traefik (:443).
  * **MITM Credential Proxy**: `:14322` published on the host and internal DNS `agent-vault:14322`.

---

## 🔒 Security & Credential Brokering Model

1. **Brokered Access**: Agents are never configured with production API keys. Agents hold dummy placeholder strings (e.g. `__anthropic_api_key__`, `__github_token__`).
2. **On-The-Fly Substitution**: Outbound requests routed through port `14322` are intercepted by the transparent proxy. Agent Vault matches the destination domain, validates the agent token, and replaces placeholders in headers, URLs, or query parameters with the real credentials stored in the vault.
3. **Encryption at Rest**: Stored credentials and the MITM root CA private key are encrypted with AES-GCM using a Data Encryption Key (DEK), wrapped by the Master Password (`AGENT_VAULT_MASTER_PASSWORD`).
4. **Private Network Routing**: `AGENT_VAULT_ALLOW_PRIVATE_RANGES=true` was enabled to allow internal agent calls to other homelab endpoints through the proxy.

---

## ⚙️ Environment Variables (Historical)

| Variable | Reference / Example | Purpose |
|---|---|---|
| `AGENTVAULT_VERSION` | `latest` | Container image tag |
| `AGENTVAULT_POSTGRES_DB` | `agentvault` | Dedicated database in `pgvector` |
| `AGENTVAULT_POSTGRES_USER` | `agentvault` | Database role |
| `AGENTVAULT_POSTGRES_PASSWORD` | `<secure-hex-password>` | Role password |
| `AGENT_VAULT_MASTER_PASSWORD` | `<32-byte-hex-key>` | Master password protecting DEK |
| `AGENT_VAULT_ADDR` | `https://vault.spencer.lan` | Public authority URL |
| `AGENT_VAULT_ALLOW_PRIVATE_RANGES` | `true` | Permits routing to internal RFC-1918 IPs |
