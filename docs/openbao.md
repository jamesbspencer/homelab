# OpenBao - Secrets & Encryption Management Service

**OpenBao** ([GitHub](https://github.com/openbao/openbao)) is an open-source, community-driven identity-based secret and encryption management system stewarded under the Linux Foundation. Originally forked from HashiCorp Vault prior to its license change, OpenBao provides a secure, unified platform for managing static and dynamic secrets, transit encryption, certificate generation (PKI), and access control policies across homelab services and autonomous agents.

---

## 🎯 Architecture & Configuration

* **Role**: Centralized secret storage, key-value engines (KV v1/v2), encryption-as-a-service, and credential broker for homelab agents and services.
* **Container Name**: `openbao`
* **Image**: `openbao/openbao:${OPENBAO_VERSION:-latest}` (running OpenBao v2.7.2+)
* **Networks**:
  * `net1`: Traefik reverse proxy bridge for HTTPS web access and Web UI routing.
  * `ai`: Isolated internal network allowing AI services (e.g., Hermes, LiteLLM) to access OpenBao directly via `http://openbao:8200`.
* **Storage Backend**: Raft integrated transactional storage located at `/openbao/file` on container, mapped to `./openbao/data` on host.
* **Ingress & URLs**:
  * **Primary Web UI & API**: `https://vault.spencer.lan` (Internal LAN only, TLS termination via Traefik wildcard cert)
  * **Secondary Alias**: `https://openbao.spencer.lan`
  * **Internal Service API**: `http://openbao:8200` (on `ai` network)
  * **Cluster Communication**: `http://openbao:8201` (Raft consensus)

---

## 📂 File Structure

```text
openbao/
├── config/
│   └── bao.hcl             # OpenBao server configuration file
└── data/                   # Persistent Raft transactional database (excluded in .gitignore)
    └── .gitkeep
```

---

## ⚙️ Configuration Reference (`openbao/config/bao.hcl`)

```hcl
ui = true

storage "raft" {
  path    = "/openbao/file"
  node_id = "openbao-1"
}

listener "tcp" {
  address                          = "0.0.0.0:8200"
  tls_disable                      = true
  x_forwarded_for_authorized_addrs = "127.0.0.1/32,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
}

api_addr     = "https://vault.spencer.lan"
cluster_addr = "http://openbao:8201"
```

---

## 🚀 First-Time Initialization & Unsealing

When newly deployed, OpenBao starts in an uninitialized and sealed state. You can initialize OpenBao either through the Web UI or via the CLI.

### Option 1: Web UI Initialization (Recommended)

1. Open your browser and navigate to:
   ```text
   https://vault.spencer.lan
   ```
2. The OpenBao setup wizard will appear prompting you to initialize the key shares:
   * **Key Shares**: Number of unseal key shares to generate (e.g., `5` for multi-party or `1` for simple homelab).
   * **Key Threshold**: Number of key shares required to unseal (e.g., `3` for standard or `1` for simple homelab).
3. Click **Initialize**.
4. **Important**: Download and securely save your unseal keys and initial root token.
5. Provide the required unseal keys to unseal the vault and log in using your initial root token.

### Option 2: CLI Initialization

To initialize via the Docker container CLI:

```bash
# Check current status
docker compose exec openbao bao status

# Initialize with Shamir keys (e.g. 5 shares, 3 threshold)
docker compose exec openbao bao operator init -key-shares=5 -key-threshold=3

# Or for simple single-operator homelab:
# docker compose exec openbao bao operator init -key-shares=1 -key-threshold=1
```

Save the output unseal keys and Initial Root Token securely.

To unseal:
```bash
docker compose exec openbao bao operator unseal <KEY_1>
docker compose exec openbao bao operator unseal <KEY_2>
docker compose exec openbao bao operator unseal <KEY_3>
```

Verify status:
```bash
docker compose exec openbao bao status
```

---

## ⚡ Automated Unsealing on System Start (`openbao-unseal`)

To ensure OpenBao automatically unseals whenever the machine boots or the container stack restarts, the stack includes a dedicated auto-unseal watcher container (`openbao-unseal`):

* **Service Name**: `openbao-unseal`
* **Image**: `alpine:latest`
* **Restart Policy**: `unless-stopped` (ensures execution upon host / Docker daemon startup)
* **Script**: [`openbao/unseal.sh`](file:///data/homelab/openbao/unseal.sh)
* **Mechanism**:
  1. Polls OpenBao health (`/v1/sys/health`) and seal status (`/v1/sys/seal-status`).
  2. If OpenBao is in a sealed state, it reads the Shamir unseal keys and sequentially submits them to `/v1/sys/unseal`.
  3. Stops once the threshold (`"sealed": false`) is satisfied.
  4. Continues to monitor periodically so future container restarts are automatically unsealed within seconds.

### Adding Unseal Keys for Auto-Unseal

You can configure your unseal keys in either of two locations (both strictly excluded from Git):

#### Option A: In `.env.passwords` (Recommended)
Add your threshold unseal keys (minimum of 3) to `.env.passwords`:
```ini
# OpenBao
token=<root_token>
unseal_key_1=<your_unseal_key_1>
unseal_key_2=<your_unseal_key_2>
unseal_key_3=<your_unseal_key_3>
```

#### Option B: In `openbao/unseal.keys`
Place one unseal key per line into `openbao/unseal.keys`:
```text
<your_unseal_key_1>
<your_unseal_key_2>
<your_unseal_key_3>
```

Permissions on either file should be kept restricted (`chmod 600`).

---

## 🛠️ Operational Tasks & Maintenance

### Checking Status
```bash
docker compose exec openbao bao status
```

### Logging into the CLI
```bash
docker compose exec -it openbao bao login
```

### Enabling Key-Value (KV v2) Secret Engine
```bash
docker compose exec openbao bao secrets enable -version=2 -path=secret kv
```

### Creating and Reading Secrets
```bash
# Write a secret
docker compose exec openbao bao kv put secret/homelab/api-keys \
  openai="sk-..." \
  database="your_db_password_here"

# Read a secret
docker compose exec openbao bao kv get secret/homelab/api-keys
```

### Homelab Dedicated Namespace (`homelab/`)

OpenBao includes built-in namespace multi-tenancy. A dedicated namespace has been configured for the homelab:

* **Namespace Name**: `homelab/`
* **Secrets Engine**: Dedicated KV v2 engine enabled at `kv/`
* **Authentication**: `userpass` enabled with user `jspencer` and `kv-all` policy attached
* **Web UI Access**: Select `homelab/` from the namespace dropdown in the top-right header of [https://vault.spencer.lan](https://vault.spencer.lan)
* **CLI Access**:
  ```bash
  # List secrets in the homelab namespace
  docker compose exec openbao bao kv list -ns=homelab kv/

  # Write a secret to the homelab namespace
  docker compose exec openbao bao kv put -ns=homelab kv/services/my-app api_key="secret-value"

  # Read a secret from the homelab namespace
  docker compose exec openbao bao kv get -ns=homelab kv/services/my-app
  ```

### Docker & AI Access Credentials (Machine-to-Machine)

Two purpose-built credential sets and policies are provisioned in OpenBao:

1. **Docker / Container Access (`docker-read`)**:
   * **Purpose**: Allows automated Docker containers and deployment scripts to read secrets.
   * **Capabilities**: Read-only (`read`, `list`) across `kv/*` and `homelab/kv/*`. Write/create actions are strictly denied.
   * **Auth Methods**:
     * **AppRole**: `role_id` and `secret_id` configured under `auth/approle/role/docker`
     * **Userpass**: Username `docker`
     * **Service Token**: 1-year renewable service token (`docker-runner`)
   * **Stored Details**: Managed securely in OpenBao at `kv/credentials/docker`.

2. **AI Agent Access (`ai-creator`)**:
   * **Purpose**: Allows autonomous AI agents (Hermes, LiteLLM, toolchains) to dynamically create, rotate, and manage secrets.
   * **Capabilities**: Full lifecycle (`create`, `read`, `update`, `delete`, `list`) across `kv/*` and `homelab/kv/*`.
   * **Auth Methods**:
     * **AppRole**: `role_id` and `secret_id` configured under `auth/approle/role/ai`
     * **Userpass**: Username `ai`
     * **Service Token**: 1-year renewable service token (`ai-agent`)
   * **Stored Details**: Managed securely in OpenBao at `kv/credentials/ai`.

#### Usage Examples

**Authenticating via AppRole in a Container / Script**:
```bash
# Obtain a client token using AppRole
BAO_TOKEN=$(curl -s -X POST http://openbao:8200/v1/auth/approle/login \
  -d "{\"role_id\": \"$ROLE_ID\", \"secret_id\": \"$SECRET_ID\"}" | jq -r .auth.client_token)

# Fetch a secret (Docker read)
curl -s -H "X-Vault-Token: $BAO_TOKEN" http://openbao:8200/v1/kv/data/services/database

# Create a secret (AI create)
curl -s -X POST -H "X-Vault-Token: $BAO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"data": {"api_key": "generated-token-xyz"}}' \
  http://openbao:8200/v1/kv/data/ai/new-tool-secret
```

### Access Control Policies & User Management

To grant users access to KV secrets (such as the `kv-all` policy):

```hcl
# Allow listing mounted secrets engines in the UI
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/internal/ui/mounts" {
  capabilities = ["read"]
}
path "sys/internal/ui/mounts/*" {
  capabilities = ["read"]
}
path "sys/namespaces" {
  capabilities = ["read", "list"]
}

# Full access to kv secrets engine (data, metadata, delete, destroy)
path "kv/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "kv/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "kv/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "kv/delete/*" {
  capabilities = ["update"]
}
path "kv/undelete/*" {
  capabilities = ["update"]
}
path "kv/destroy/*" {
  capabilities = ["update"]
}
path "kv/subkeys/*" {
  capabilities = ["read", "list"]
}

# Wildcard access to any additional KV engines in root namespace (+/*)
path "+/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "+/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "+/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

Assigning the policy to a userpass user:
```bash
docker compose exec openbao bao write auth/userpass/users/<username> token_policies="kv-all"
```

### Creating Raft Database Snapshots (Backups)
OpenBao integrated Raft storage supports point-in-time consistent snapshots without service interruption:

```bash
docker compose exec openbao bao operator raft snapshot save /openbao/file/backup-$(date +%Y%m%d).snap
```

To restore a snapshot:
```bash
docker compose exec openbao bao operator raft snapshot restore -force /openbao/file/backup-<date>.snap
```

### Healthcheck
The container includes an automated healthcheck query that honors both uninitialized and sealed states:
```bash
wget -q --spider "http://127.0.0.1:8200/v1/sys/health?uninitcode=200&sealedcode=200"
```

---

## 🔒 Security Posture & Zero-Leak Policy

* **Internal Only**: OpenBao is routed exclusively on `vault.spencer.lan` and `openbao.spencer.lan` with no external WAN exposure or public cert resolver.
* **Privilege Dropping**: The container starts as root in Docker to manage local volume ownership, then automatically drops privileges to unprivileged user `openbao` (UID 100) via `su-exec`.
* **Zero Credentials Stored in Git**: Unseal keys, root tokens, and encryption keys are strictly excluded from git tracking (`openbao/data/*` in `.gitignore`).
