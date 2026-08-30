# PostgreSQL & pgvector Database

The database service runs PostgreSQL with the `pgvector` extension enabled, providing relational data storage and high-dimensional vector embeddings for Open WebUI.

---

## 🎯 Overview & Architecture

* **Role**: Primary database and vector storage backend.
* **Container Name**: `postgres` (Service name: `db`)
* **Image**: `pgvector/pgvector:${POSTGRES_VERSION}` (default `pg16`)
* **Network**: `db` (Dedicated, isolated database bridge network)
* **Internal Port**: `5432` (No host port exposure)

---

## 🔒 Security & Network Isolation

* **Isolated Network**: Connected only to the internal `db` network. Containers needing database access (like `open-webui`) join `db`.
* **No Host Port Binding**: Port `5432` is not bound to the host network, preventing external access.

---

## ⚙️ Configuration & Environment

| Variable | Source | Purpose |
|---|---|---|
| `POSTGRES_USER` | `${POSTGRES_USER}` in `.env` | Database administrator user |
| `POSTGRES_PASSWORD` | `${POSTGRES_PASSWORD}` in `.env` | Database user password |
| `POSTGRES_DB` | `${POSTGRES_DB}` in `.env` | Default database name (`openwebui`) |

---

## 📁 Mounted Volumes & Health Check

* **Volume**: `./postgres:/var/lib/postgresql/data` (stores PostgreSQL data files).
* **Health Check**:
  ```yaml
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
  interval: 5s
  timeout: 5s
  retries: 5
  ```

---

## 🛠️ Management & Backup

### Connecting via psql
```bash
docker compose exec db psql -U openwebui -d openwebui
```

### Exporting Database Backup
```bash
docker compose exec -T db pg_dump -U openwebui openwebui > openwebui_backup_$(date +%Y%m%d).sql
```
