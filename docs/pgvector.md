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
