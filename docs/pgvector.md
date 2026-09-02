# Dedicated pgvector Instance (Hindsight & Shared Services)

This dedicated `pgvector` service provides PostgreSQL with the `pgvector` extension enabled for **Hindsight** (Hermes long-term memory engine) and future homelab microservices. It is decoupled from the legacy Open WebUI database to ensure long-term stability and independent lifecycles.

---

## 🎯 Overview & Architecture

* **Role**: Primary vector and relational database for Hindsight and upcoming homelab services.
* **Container Name**: `pgvector` (Service name: `pgvector`)
* **Image**: `pgvector/pgvector:${PGVECTOR_VERSION:-pg16}`
* **Network**: `db` (Strictly isolated database network; does **not** join `ai` or bind to host ports)
* **Internal Port**: `5432` (Accessible within `db` network via hostname `pgvector`)
* **Host Permissions**: Uses host user/group IDs (`PUID=1000`, `PGID=1000`) so all persistent data in `./pgvector/data` is owned by `suadmin` and accessible without `sudo`.

---

## 🔒 Security & Network Isolation

* **Isolated `db` Network**: Connected strictly to the internal `db` bridge network.
* **Service Access Requirement**: Any container or agent requiring database access (e.g. Hermes Agent or Hindsight services) must join the `db` network in `docker-compose.yaml`.
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
| `PUID` / `PGID` | `1000` / `1000` | Host UID/GID mapping for file ownership |

---

## 🚀 Auto-Provisioning & Initialization

The container mounts `./pgvector/init/01-init-databases.sh` to `/docker-entrypoint-initdb.d/`. On initial bootstrap:
1. The `vector` extension is enabled on the primary database (`postgres`).
2. The `hindsight` user role and database are created with full privileges.
3. The `vector` extension is enabled inside the `hindsight` database.

### Connection Strings

* **Hindsight Service**:
  ```
  postgresql://hindsight:${HINDSIGHT_POSTGRES_PASSWORD}@pgvector:5432/hindsight
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
```

### Verifying pgvector Extension
```bash
docker compose exec pgvector psql -U hindsight -d hindsight -c '\dx'
```

### Performing Database Backups
```bash
# Backup hindsight database
docker compose exec -T pgvector pg_dump -U postgres hindsight > hindsight_backup_$(date +%Y%m%d).sql

# Backup entire pgvector cluster
docker compose exec -T pgvector pg_dumpall -U postgres > pgvector_all_backup_$(date +%Y%m%d).sql
```
