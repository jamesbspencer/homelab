# Infisical Agent Vault - AI Agent Credential Proxy & Broker

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
  * **MITM Credential Proxy**: `:14322` published on the host (`0.0.0.0:14322->14322/tcp`) and internal DNS `agent-vault:14322`.
* **State & CA Certificate**:
  * Root CA certificate: Stored encrypted in PostgreSQL, accessible publicly at `https://vault.spencer.lan/v1/mitm/ca.pem` and exported locally to `./agent-vault/data/ca.pem`.

```mermaid
graph TD
    User([Browser / Admin]) -->|HTTPS :443| Traefik[Traefik Reverse Proxy]
    Traefik -->|vault.spencer.lan :14321| AgentVaultAPI[Agent Vault Web UI / API]
    
    subgraph Agent Vault Service
        AgentVaultAPI
        AgentVaultProxy[MITM Credential Proxy :14322]
    end

    subgraph External & LAN Agents
        DevLaptop[Claude Code / Cursor on LAN] -->|HTTP_PROXY :14322| AgentVaultProxy
    end

    subgraph Homelab Agent Stack (ai network)
        Hermes[Hermes Agent] -->|HTTPS_PROXY :14322| AgentVaultProxy
        AgentVaultProxy -->|Substituted Keys| ExternalAPIs[Public APIs: Anthropic, GitHub, Slack, Telegram]
        AgentVaultProxy -->|Internal Proxying| LiteLLM[LiteLLM Proxy :4000]
    end

    subgraph Database Layer (db network)
        AgentVaultAPI -->|PostgreSQL :5432| Pgvector[pgvector Container]
    end
```

---

## 🔒 Security & Credential Brokering Model

1. **Brokered Access**: Agents are never configured with production API keys. Agents hold dummy placeholder strings (e.g. `__anthropic_api_key__`, `__github_token__`, `__slack_bot_token__`).
2. **On-The-Fly Substitution**: Outbound requests routed through port `14322` are intercepted by the transparent proxy. Agent Vault matches the destination domain, validates the agent token, and replaces placeholders in headers, URLs, or query parameters with the real credentials stored in the vault.
3. **Encryption at Rest**: Stored credentials and the MITM root CA private key are encrypted with AES-GCM using a Data Encryption Key (DEK), wrapped by the Master Password (`AGENT_VAULT_MASTER_PASSWORD`).
4. **Private Network Routing**: `AGENT_VAULT_ALLOW_PRIVATE_RANGES=true` is enabled to allow internal agent calls to other homelab endpoints (e.g., LiteLLM, SearXNG) through the proxy.

---

## ⚙️ Environment Variables

Configured in [`.env`](file:///data/homelab/.env) and [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml):

| Variable | Reference / Example | Purpose |
|---|---|---|
| `AGENTVAULT_VERSION` | `latest` | Container image tag |
| `AGENTVAULT_POSTGRES_DB` | `agentvault` | Dedicated database in `pgvector` |
| `AGENTVAULT_POSTGRES_USER` | `agentvault` | Database role |
| `AGENTVAULT_POSTGRES_PASSWORD` | `<secure-hex-password>` | Role password |
| `AGENT_VAULT_MASTER_PASSWORD` | `<32-byte-hex-key>` | Master password protecting DEK |
| `AGENT_VAULT_ADDR` | `https://vault.spencer.lan` | Public authority URL for discovery and invites |
| `AGENT_VAULT_ALLOW_PRIVATE_RANGES` | `true` | Permits routing to internal RFC-1918 homelab IPs |
| `AGENT_VAULT_LOG_LEVEL` | `info` | Structured logging verbosity |
| `AGENT_VAULT_TELEMETRY` | `false` | Disables anonymous telemetry |

---

## 🚀 Getting Started & First-Time Setup

### 1. Register Instance Owner
Open `https://vault.spencer.lan` (or `https://vault.spencer.lan/register`) in your browser to create the initial owner account. The first registered user becomes the instance admin with full rights over the default vault.

### 2. Create a Vault & Add Credentials
1. In the Web UI, navigate to **Vaults** → **New Vault** (e.g., `prod` or `homelab`).
2. Go to **Credentials** → **Add Credential**:
   - `ANTHROPIC_API_KEY`: Real Anthropic API key (`sk-ant-...`)
   - `GITHUB_TOKEN`: GitHub PAT (`ghp_...`)
   - `SLACK_BOT_TOKEN`: Slack token (`xoxb-...`)
   - `TELEGRAM_BOT_TOKEN`: Telegram bot token

### 3. Configure Services & URL Substitutions
Under **Services** → **Add Service**:
- **Name**: `Anthropic API`
- **Host**: `api.anthropic.com`
- **Authentication**: `Passthrough`
- **URL Substitutions**:
  - **Placeholder**: `__anthropic_api_key__`
  - **Surface**: `header` (matches `x-api-key: __anthropic_api_key__`)
  - **Credential**: `ANTHROPIC_API_KEY`

### 4. Create an Agent Token
1. Go to **All Agents** → **Add Agent**.
2. Name the agent (e.g., `hermes` or `laptop-claude`).
3. Assign access to your vault with the `proxy` role.
4. Copy the generated agent token (`av_agt_...`).

---

## 🤖 Connecting Agents

### A. Nous Research Hermes Agent (Docker)
To route Hermes Agent traffic through Agent Vault:

1. Configure placeholder keys in Hermes `.env` or container environment:
   ```bash
   ANTHROPIC_API_KEY=__anthropic_api_key__
   GITHUB_TOKEN=__github_token__
   ```
2. Pass the proxy configuration to the `hermes` service in `docker-compose.yaml`:
   ```yaml
   environment:
     - HTTP_PROXY=http://<AGENT_TOKEN>@agent-vault:14322
     - HTTPS_PROXY=http://<AGENT_TOKEN>@agent-vault:14322
     - NO_PROXY=localhost,127.0.0.1,ollama,litellm,searxng,firecrawl,hindsight,authentik-server,pgvector,valkey,rabbitmq,nuq-postgres,playwright-service,agent-vault,traefik,.spencer.lan
     - REQUESTS_CA_BUNDLE=/opt/data/ca.pem
     - SSL_CERT_FILE=/opt/data/ca.pem
     - NODE_EXTRA_CA_CERTS=/opt/data/ca.pem
     - CURL_CA_BUNDLE=/opt/data/ca.pem
   volumes:
     - ./agent-vault/data/ca.pem:/opt/data/ca.pem:ro
     - ./agent-vault/data/ca.pem:/etc/ssl/certs/agent-vault-ca.pem:ro
   ```

### B. LiteLLM Proxy (Cloud Fallback Credential Brokering)
LiteLLM routes external provider calls (OpenRouter, Groq, DeepSeek) through Agent Vault:
```yaml
environment:
  - HTTP_PROXY=http://${LITELLM_AGENT_VAULT_TOKEN:-${HERMES_AGENT_VAULT_TOKEN}}@agent-vault:14322
  - HTTPS_PROXY=http://${LITELLM_AGENT_VAULT_TOKEN:-${HERMES_AGENT_VAULT_TOKEN}}@agent-vault:14322
  - NO_PROXY=localhost,127.0.0.1,ollama,searxng,firecrawl,hindsight,pgvector,valkey,authentik-server,agent-vault,traefik,.spencer.lan
  - REQUESTS_CA_BUNDLE=/etc/ssl/certs/agent-vault-ca.pem
  - SSL_CERT_FILE=/etc/ssl/certs/agent-vault-ca.pem
  - CURL_CA_BUNDLE=/etc/ssl/certs/agent-vault-ca.pem
volumes:
  - ./agent-vault/data/ca.pem:/etc/ssl/certs/agent-vault-ca.pem:ro
```
Dummy API keys configured in `.env` (e.g. `OPENROUTER_API_KEY=OPENROUTER_API_KEY`) are dynamically replaced with real keys when LiteLLM calls upstream endpoints.

### C. SearXNG Metasearch Engine
Outbound search queries to upstream search engines are routed through Agent Vault:
```yaml
environment:
  - HTTP_PROXY=http://${SEARXNG_AGENT_VAULT_TOKEN:-${HERMES_AGENT_VAULT_TOKEN}}@agent-vault:14322
  - HTTPS_PROXY=http://${SEARXNG_AGENT_VAULT_TOKEN:-${HERMES_AGENT_VAULT_TOKEN}}@agent-vault:14322
  - NO_PROXY=localhost,127.0.0.1,valkey,agent-vault,.spencer.lan
  - REQUESTS_CA_BUNDLE=/etc/ssl/certs/agent-vault-ca.pem
  - SSL_CERT_FILE=/etc/ssl/certs/agent-vault-ca.pem
  - CURL_CA_BUNDLE=/etc/ssl/certs/agent-vault-ca.pem
volumes:
  - ./agent-vault/data/ca.pem:/etc/searxng/ca.pem:ro
  - ./agent-vault/data/ca.pem:/etc/ssl/certs/agent-vault-ca.pem:ro
```

### D. Firecrawl & Playwright Scraping Stack
Scraping web pages and headless Chromium browser instances route outbound fetches through Agent Vault to mitigate SSRF:
```yaml
# playwright-service
environment:
  - PROXY_SERVER=http://agent-vault:14322
  - PROXY_USERNAME=${FIRECRAWL_AGENT_VAULT_TOKEN:-${HERMES_AGENT_VAULT_TOKEN}}
  - HTTP_PROXY=http://${FIRECRAWL_AGENT_VAULT_TOKEN:-${HERMES_AGENT_VAULT_TOKEN}}@agent-vault:14322
  - HTTPS_PROXY=http://${FIRECRAWL_AGENT_VAULT_TOKEN:-${HERMES_AGENT_VAULT_TOKEN}}@agent-vault:14322
  - NO_PROXY=localhost,127.0.0.1,agent-vault,.spencer.lan
  - NODE_EXTRA_CA_CERTS=/etc/ssl/certs/agent-vault-ca.pem
volumes:
  - ./agent-vault/data/ca.pem:/etc/ssl/certs/agent-vault-ca.pem:ro

# firecrawl
environment:
  - HTTP_PROXY=http://${FIRECRAWL_AGENT_VAULT_TOKEN:-${HERMES_AGENT_VAULT_TOKEN}}@agent-vault:14322
  - HTTPS_PROXY=http://${FIRECRAWL_AGENT_VAULT_TOKEN:-${HERMES_AGENT_VAULT_TOKEN}}@agent-vault:14322
  - NO_PROXY=localhost,127.0.0.1,valkey,rabbitmq,nuq-postgres,playwright-service,searxng,agent-vault,pgvector,ollama,litellm,traefik,.spencer.lan
  - NODE_EXTRA_CA_CERTS=/etc/ssl/certs/agent-vault-ca.pem
volumes:
  - ./agent-vault/data/ca.pem:/etc/ssl/certs/agent-vault-ca.pem:ro
```

### E. Claude Code / Cursor on Developer Laptop (LAN)
1. Download the Agent Vault CA certificate:
   ```bash
   curl -O https://vault.spencer.lan/v1/mitm/ca.pem
   ```
2. Export the proxy environment variables:
   ```bash
   export HTTPS_PROXY="http://<AGENT_TOKEN>@<homelab-ip>:14322"
   export HTTP_PROXY="http://<AGENT_TOKEN>@<homelab-ip>:14322"
   export NODE_EXTRA_CA_CERTS="$PWD/ca.pem"
   export SSL_CERT_FILE="$PWD/ca.pem"
   export REQUESTS_CA_BUNDLE="$PWD/ca.pem"
   ```
3. Run your agent with placeholder credentials:
   ```bash
   export ANTHROPIC_API_KEY="__anthropic_api_key__"
   claude
   ```

---


## 🩺 Operational Checks & Maintenance

* **Healthcheck**:
  ```bash
  docker compose exec agent-vault wget -q -O- http://localhost:14321/health
  # Expected: {"status":"ok"}
  ```
* **Fetch Root CA**:
  ```bash
  curl -s http://localhost:14321/v1/mitm/ca.pem
  ```
* **Logs Inspection**:
  ```bash
  docker compose logs -f agent-vault
  ```
* **Database Inspection**:
  ```bash
  docker compose exec pgvector psql -U postgres -d agentvault -c "\dt"
  ```
