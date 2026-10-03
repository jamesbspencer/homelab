# Dedicated pgvector Instance (Hindsight, LiteLLM, Authentik & Shared Services)

This dedicated `pgvector` service provides PostgreSQL with the `pgvector` extension enabled for **Hindsight** (Hermes long-term memory engine), **LiteLLM Proxy** (spend tracking & key persistence), and **Authentik** (centralized identity provider). It is decoupled from legacy single-app databases to ensure long-term stability and independent lifecycles.

---

## 🎯 Overview & Architecture

* **Role**: Primary vector and relational database for Hindsight, LiteLLM Proxy, Authentik, and homelab services.
* **Container Name**: `pgvector` (Service name: `pgvector`)
* **Image**: `pgvector/pgvector:${PGVECTOR_VERSION:-pg16}`
* **Network**: `db` (Strictly isolated database network; does **not** join `ai` or bind to host ports)
* **Internal Port**: `5432` (Accessible within `db` network via hostname `pgvector`)
* **Host Permissions**: Uses host user/group IDs (`PUID=1000`, `PGID=1000`) so all persistent data in `./pgvector/data` is owned by `suadmin` and accessible without `sudo`.

---

## 🔒 Security & Network Isolation

* **Isolated `db` Network**: Connected strictly to the internal `db` bridge network.
* **Service Access Requirement**: Any container requiring database access (Hindsight, LiteLLM, Authentik) must join the `db` network in `docker-compose.yaml`.
* **Zero Host Exposure**: Port `5432` is not bound to the host, preventing external access.

---

## ⚙️ Configuration & Environment

| Variable | Default / Source | Purpose |
|---|---|---|
| `PGVECTOR_VERSION` | `pg16` | PostgreSQL / pgvector version tag |
| `PGVECTOR_USER` | `postgres` | Superuser / administrator username |
| `PGVECTOR_PASSWORD` | `${PGVECTOR_PASSWORD}` in `.env` | Superuser password |
| `PGVECTOR_DB` | `postgres` | Default administrative database |
| `HINDSIGHT_POSTGRES_DB` | `hindsight` | Dedicated database for Hindsight memory engine |
| `HINDSIGHT_POSTGRES_USER` | `hindsight` | Service role for Hindsight |
| `HINDSIGHT_POSTGRES_PASSWORD` | `${HINDSIGHT_POSTGRES_PASSWORD}` in `.env` | Password for Hindsight service role |
| `LITELLM_POSTGRES_DB` | `litellm` | Dedicated database for LiteLLM key & spend persistence |
| `LITELLM_POSTGRES_USER` | `litellm` | Service role for LiteLLM |
| `LITELLM_POSTGRES_PASSWORD` | `${LITELLM_POSTGRES_PASSWORD}` in `.env` | Password for LiteLLM service role |
| `AUTHENTIK_POSTGRES_DB` | `authentik` | Dedicated database for Authentik IAM |
| `AUTHENTIK_POSTGRES_USER` | `authentik` | Service role for Authentik |
| `AUTHENTIK_POSTGRES_PASSWORD` | `${AUTHENTIK_POSTGRES_PASSWORD}` in `.env` | Password for Authentik service role |
| `PUID` / `PGID` | `1000` / `1000` | Host UID/GID mapping for file ownership |

---

## 🚀 Auto-Provisioning & Initialization

The container mounts `./pgvector/init/01-init-databases.sh` to `/docker-entrypoint-initdb.d/`. On initial bootstrap:
1. The `vector` extension is enabled on the primary database (`postgres`).
2. The `hindsight` user role and database are created with full privileges, and `vector` is enabled inside it.
3. The `litellm` user role and database are created with full privileges.
4. The `authentik` user role and database are created with full privileges.

### Connection Strings

* **Hindsight Service**:
  ```
  postgresql://hindsight:${HINDSIGHT_POSTGRES_PASSWORD}@pgvector:5432/hindsight
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

# Hindsight database connection
docker compose exec pgvector psql -U hindsight -d hindsight

# LiteLLM database connection
docker compose exec pgvector psql -U litellm -d litellm

# Authentik database connection
docker compose exec pgvector psql -U authentik -d authentik
```

### Verifying pgvector Extension
```bash
docker compose exec pgvector psql -U hindsight -d hindsight -c '\dx'
```

### Performing Database Backups
```bash
# Backup specific database (e.g. hindsight)
docker compose exec -T pgvector pg_dump -U postgres hindsight > hindsight_backup_$(date +%Y%m%d).sql

# Backup entire pgvector cluster
docker compose exec -T pgvector pg_dumpall -U postgres > pgvector_all_backup_$(date +%Y%m%d).sql
```

---

## 🧹 Periodic Maintenance & Vector Optimization Automation

To prevent unbounded table growth, HNSW vector graph fragmentation, and optimizer statistic decay, an automated pipeline is provided by [`scripts/pgvector-maintenance.sh`](file:///data/homelab/scripts/pgvector-maintenance.sh):

### Pipeline Operations
1. **Concurrent HNSW Vector Reindexing**: Runs `REINDEX TABLE CONCURRENTLY memory_units;` and `REINDEX TABLE CONCURRENTLY mental_models;` in Hindsight to rebuild vector indexes without locking reads or writes.
2. **Spend Log Archival & Pruning**: Archives aged `LiteLLM_SpendLogs` (> 30 days) to compressed gzip CSVs in `./pgvector/archives/` before deleting rows.
3. **Async Task State Pruning**: Archives and prunes finished tasks in `hindsight.async_operations` (> 14 days) and aged `llm_requests`.
4. **Cluster-wide Vacuuming**: Runs `VACUUM (ANALYZE)` across `hindsight`, `litellm`, `authentik`, and `gitea` to reclaim space and update PostgreSQL query planner statistics.
5. **Push Notifications**: Automatically dispatches a formatted run summary to Spencer's mobile and desktop devices via the self-hosted `ntfy` push gateway.

### Manual Execution
```bash
# Preview operations without altering tables (Simulated)
./scripts/pgvector-maintenance.sh --dry-run

# Run full live maintenance
./scripts/pgvector-maintenance.sh

# Custom retention windows (e.g., 60 days spend, 30 days async tasks)
./scripts/pgvector-maintenance.sh --spend-days 60 --async-days 30
```

### Scheduled Hermes Automation
Scheduled natively via the Hermes Agent scheduler (`hermes cron`):
* **Job ID**: `6ff939ca35e2`
* **Schedule**: `0 3 * * 0` (Weekly every Sunday at 03:00 UTC)
* **Mode**: `--no-agent` (runs script directly with zero LLM token overhead and dispatches ntfy alert)
* **Agent Skill**: Hermes possesses the `database-maintenance` skill (`hermes/skills/devops/database-maintenance/SKILL.md`) enabling on-demand conversational execution.
