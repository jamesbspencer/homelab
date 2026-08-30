# Valkey In-Memory Cache

Valkey is a high-performance, open-source in-memory key-value data store (a fully open Redis fork) providing ultra-low latency caching and rate-limiting.

---

## 🎯 Overview & Architecture

* **Role**: Primary key-value cache and session rate-limiting backend.
* **Container Name**: `valkey`
* **Image**: `docker.io/valkey/valkey:9-alpine`
* **Internal Port**: `6379`
* **Network**: `redis` (Dedicated Redis/Valkey bridge network)
* **Clients**: SearXNG, Firecrawl

---

## ⚙️ Configuration & Startup

Started with optimized snapshot persistence:
```yaml
command: >
  valkey-server
  --save 30 1
  --loglevel warning
```

### Health Check
```yaml
test: ["CMD", "valkey-cli", "ping"]
interval: 10s
timeout: 5s
retries: 3
```

---

## 📁 Mounted Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `./valkey/data` | `/data` | Snapshot persistence (`dump.rdb`) |

---

## 🛠️ Management Commands

```bash
docker compose exec valkey valkey-cli ping
docker compose exec valkey valkey-cli info memory
docker compose exec valkey valkey-cli dbsize
```
