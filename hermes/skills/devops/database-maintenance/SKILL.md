---
name: database-maintenance
description: "Optimize pgvector HNSW indexes and prune aged database logs."
version: 1.0.0
author: "Spencer & Hermes Agent"
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Database, Postgres, pgvector, HNSW, Maintenance, Cleanup, Vacuum]
prerequisites:
  commands: [docker, bash]
---

# Database & Vector Index Maintenance (pgvector)

Automates periodic maintenance, HNSW vector index optimization, ephemeral state cleanup, and bloat reclamation across the homelab's PostgreSQL cluster.

## When to Use

- When vector search latency increases or HNSW memory index graph fragmentation occurs.
- When `LiteLLM_SpendLogs` or `async_operations` accumulate large amounts of JSON data.
- When performing scheduled weekly or monthly database health optimization.
- DO NOT use continuously or in tight loops (concurrent reindexing and vacuuming incur I/O load).

## Prerequisites

- Access to the Docker socket `/var/run/docker.sock` to interact with the `pgvector` container.
- Script installed at `/opt/data/scripts/pgvector-maintenance.sh` (or `/data/homelab/scripts/pgvector-maintenance.sh`).
- Push notifications routed via `notify.sh` to the `backups` topic on ntfy.

## How to Run

### 1. Simulated Dry Run
Inspect records to be pruned without altering database tables:
```bash
/opt/data/scripts/pgvector-maintenance.sh --dry-run
```

### 2. Live Full Maintenance
Reindex HNSW vector indexes, prune aged logs (>30d spend, >14d async ops), vacuum all databases, and push completion alert to ntfy:
```bash
/opt/data/scripts/pgvector-maintenance.sh
```

### 3. Custom Retention Windows
Override the retention thresholds:
```bash
/opt/data/scripts/pgvector-maintenance.sh --spend-days 60 --async-days 30
```

### 4. Skip Reindexing (Vacuum & Prune Only)
Run vacuuming and cleanup without index rebuild:
```bash
/opt/data/scripts/pgvector-maintenance.sh --no-reindex
```

## Scheduled Cron Automation

A persistent background cron job is registered with the Hermes scheduler:
* **Job ID**: `6ff939ca35e2` (`pgvector-maintenance`)
* **Schedule**: `0 3 * * 0` (Every Sunday at 03:00 UTC)
* **Mode**: `--no-agent` (runs script directly, dispatches alerts via ntfy)

To inspect or trigger manually:
```bash
# Check status
hermes cron list

# Trigger next run immediately
hermes cron run 6ff939ca35e2
```

## Pitfalls

- Reindexing large tables concurrently uses additional temporary disk space.
- Never terminate a concurrent reindex mid-flight with `kill -9`, as PostgreSQL will leave an invalid temporary index that requires cleanup.

## Verification

Check archived data files and recent ntfy events:
```bash
ls -lh /data/homelab/pgvector/archives/
```
