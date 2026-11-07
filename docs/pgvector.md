# Dedicated pgvector Instance (Open WebUI, Authentik & Gitea)

This dedicated `pgvector` service provides PostgreSQL with the `pgvector` extension enabled for **Open WebUI** (user conversation memory & RAG vector store), **Authentik** (centralized identity provider), and **Gitea** (repository metadata & issues). *(Note: Legacy LiteLLM database has been retired and archived to `pgvector/archives/litellm_final_backup.sql.gz`, as OmniRoute utilizes a zero-PostgreSQL local SQLite architecture).*

---

## 🎯 Overview & Architecture

* **Role**: Primary vector and relational database for Open WebUI, Authentik, Gitea, and homelab services.
* **Container Name**: `pgvector` (Service name: `pgvector`)
* **Image**: `pgvector/pgvector:${PGVECTOR_VERSION:-pg16}`
* **Network**: `db` (Strictly isolated database network; does **not** join `ai` or bind to host ports)
* **Internal Port**: `5432` (Accessible within `db` network via hostname `pgvector`)
* **Host Permissions**: Uses host user/group IDs (`PUID=1000`, `PGID=1000`) so all persistent data in `./pgvector/data` is owned by `suadmin` and accessible without `sudo`.

---

## 🔒 Security & Network Isolation

* **Isolated `db` Network**: Connected strictly to the internal `db` bridge network.
* **Service Access Requirement**: Any container requiring database access (Open WebUI, Authentik, Gitea) must join the `db` network in `docker-compose.yaml`.
* **Zero Host Exposure**: Port `5432` is not bound to the host, preventing external access.

---

## ⚙️ Configuration & Environment

| Variable | Default / Source | Purpose |
|---|---|---|
| `PGVECTOR_VERSION` | `pg16` | PostgreSQL / pgvector version tag |
| `PGVECTOR_USER` | `postgres` | Superuser / administrator username |
| `PGVECTOR_PASSWORD` | `${PGVECTOR_PASSWORD}` in `.env` | Superuser password |
| `PGVECTOR_DB` | `postgres` | Default administrative database |
| `OPENWEBUI_POSTGRES_DB` | `openwebui` | Dedicated database for Open WebUI user memory & RAG |
| `OPENWEBUI_POSTGRES_USER` | `openwebui` | Service role for Open WebUI |
| `OPENWEBUI_POSTGRES_PASSWORD` | `${OPENWEBUI_POSTGRES_PASSWORD}` in `.env` | Password for Open WebUI service role |
| `AUTHENTIK_POSTGRES_DB` | `authentik` | Dedicated database for Authentik IAM |
| `AUTHENTIK_POSTGRES_USER` | `authentik` | Service role for Authentik |
| `AUTHENTIK_POSTGRES_PASSWORD` | `${AUTHENTIK_POSTGRES_PASSWORD}` in `.env` | Password for Authentik service role |
| `GITEA_POSTGRES_DB` | `gitea` | Dedicated database for Gitea |
| `GITEA_POSTGRES_USER` | `gitea` | Service role for Gitea |
| `GITEA_POSTGRES_PASSWORD` | `${GITEA_POSTGRES_PASSWORD}` in `.env` | Password for Gitea service role |
| `PUID` / `PGID` | `1000` / `1000` | Host UID/GID mapping for file ownership |

---

## 🚀 Auto-Provisioning & Initialization

The container mounts `./pgvector/init/01-init-databases.sh` to `/docker-entrypoint-initdb.d/`. On initial bootstrap:
1. The `vector` extension is enabled on the primary database (`postgres`).
2. The `openwebui` user role and database are created with full privileges, and `vector` is enabled inside it.
3. The `litellm` user role and database are created with full privileges.
4. The `authentik` user role and database are created with full privileges.
5. The `gitea` user role and database are created with full privileges.

### Connection Strings

* **Open WebUI Service**:
  ```
  postgresql://openwebui:${OPENWEBUI_POSTGRES_PASSWORD}@pgvector:5432/openwebui
  ```
* **LiteLLM Proxy Service**:
  ```
  postgresql://litellm:${LITELLM_POSTGRES_PASSWORD}@pgvector:5432/litellm
  ```
* **Authentik Server & Worker**:
  ```
  postgresql://authentik:${AUTHENTIK_POSTGRES_PASSWORD}@pgvector:5432/authentik
  ```
* **Administrative / Superuser**:
  ```
  postgresql://postgres:${PGVECTOR_PASSWORD}@pgvector:5432/postgres
  ```

---

## 📁 Storage & Persistence

* **Data Volume**: `./pgvector/data:/var/lib/postgresql/data` (owned by `suadmin:suadmin`).
* **Initialization Scripts**: `./pgvector/init:/docker-entrypoint-initdb.d:ro`.

---

## 🛠️ Operational Commands

### Connecting via psql
```bash
# Administrative connection
docker compose exec pgvector psql -U postgres -d postgres

# Open WebUI database connection
docker compose exec pgvector psql -U openwebui -d openwebui

# LiteLLM database connection
docker compose exec pgvector psql -U litellm -d litellm

# Authentik database connection
docker compose exec pgvector psql -U authentik -d authentik
```

### Verifying pgvector Extension
```bash
docker compose exec pgvector psql -U openwebui -d openwebui -c '\dx'
```

### Performing Database Backups
```bash
# Backup specific database (e.g. openwebui)
docker compose exec -T pgvector pg_dump -U postgres openwebui > openwebui_backup_$(date +%Y%m%d).sql

# Backup entire pgvector cluster
docker compose exec -T pgvector pg_dumpall -U postgres > pgvector_all_backup_$(date +%Y%m%d).sql
```

---

## 🧹 Periodic Maintenance & Optimization Automation

To prevent unbounded table growth and optimizer statistic decay, an automated pipeline is provided by [`scripts/pgvector-maintenance.sh`](file:///data/homelab/scripts/pgvector-maintenance.sh):

### Pipeline Operations
1. **Spend Log Archival & Pruning**: Gracefully checks for and archives aged legacy spend logs to compressed gzip CSVs in `./pgvector/archives/`.
2. **Cluster-wide Vacuuming**: Runs `VACUUM (ANALYZE)` across active databases (`openwebui`, `authentik`, and `gitea`) to reclaim space and refresh PostgreSQL query planner statistics.
3. **Push Notifications**: Automatically dispatches a formatted run summary to Spencer's mobile and desktop devices via the self-hosted `ntfy` push gateway.

### Manual Execution
```bash
# Preview operations without altering tables (Simulated)
./scripts/pgvector-maintenance.sh --dry-run

# Run full live maintenance
./scripts/pgvector-maintenance.sh

# Custom retention windows (e.g., 60 days spend, 30 days async tasks)
./scripts/pgvector-maintenance.sh --spend-days 60 --async-days 30
```

### Scheduled Host Crontab Automation
Scheduled natively via host crontab (`crontab -e` for `suadmin`):
* **Schedule**: `0 3 * * 0` (Weekly every Sunday at 03:00 UTC)
* **Command**: `/data/homelab/scripts/pgvector-maintenance.sh >> /data/homelab/pgvector/archives/maintenance.log 2>&1`
* **Execution**: Runs script directly with zero LLM token overhead, archives aged records, vacuums databases, rebuilds HNSW indexes, and dispatches ntfy alerts.
