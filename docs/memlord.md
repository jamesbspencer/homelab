# Memlord MCP Memory Server

**Memlord** (`MyrikLD/memlord`) is a self-hosted **Model Context Protocol (MCP)** memory server engineered for persistent, structured, and multi-workspace agent memory. It features **hybrid search** combining BM25 full-text indexing with vector KNN (`pgvector`), fused via **Reciprocal Rank Fusion (RRF)**, and runs local ONNX embeddings with zero external API dependencies.

---

## 🎯 Overview & Architecture

* **Role**: Structured workspace memory, procedural knowledge store, and MCP toolset provider for AI agents and IDEs.
* **Container Name**: `memlord` (Service name: `memlord`)
* **Image**: `ghcr.io/myrikld/memlord:${MEMLORD_VERSION:-latest}`
* **Networks**:
  * `ai`: Internal AI network connecting Hermes Agent (`http://memlord:8000/mcp`).
  * `db`: Isolated database network connecting to dedicated `pgvector` database (`postgresql+asyncpg://memlord:...@pgvector:5432/memlord`).
  * `net1`: Traefik reverse proxy bridge exposing Web UI and external MCP endpoints.
* **Internal Ports**:
  * `8000`: HTTP Web UI & MCP endpoint (`/mcp`).
* **External Ingress**:
  * Internal LAN: `https://memlord.spencer.lan` (Direct access to Web UI & MCP; registration `/ui/register` protected by Authentik ForwardAuth).
  * Public WAN: `https://<public-domain>` (Protected via Authentik ForwardAuth with direct `/mcp` client bypass).

```mermaid
graph TD
    Traefik[Traefik Proxy] -->|memlord.spencer.lan :8000| MemlordUI[Memlord Web UI & MCP Server]
    Traefik -.->|Public WAN ForwardAuth :9000| Authentik[Authentik Server]
    
    subgraph AI Network
        Hermes[Hermes Agent] -->|Internal MCP HTTP :8000/mcp| MemlordUI
        MemlordUI -->|Zero-GPU Local Embeddings| LocalONNX[ONNX Embedding Model & Tokenizer]
    end

    subgraph DB Network
        MemlordUI -->|BM25 tsvector + pgvector KNN :5432| Pgvector[pgvector Container]
    end
```

---

## 🧠 Memory Architecture: Memlord & Hindsight Dual-Tier System

Spencer's Homelab operates a synergistic dual-tier memory system:

| Memory Tier | System | Access Pattern | Storage & Retrieval | Purpose |
|---|---|---|---|---|
| **Tier 1: Episodic & Reflective** | **Hindsight** (`:8888`) | Implicit (Auto-Retain / Auto-Recall) | Vector graph in `hindsight` DB + Ollama LLM extraction | Cross-session narrative history, user preferences, entity resolution, and temporal observations. |
| **Tier 2: Workspace & Procedural** | **Memlord** (`:8000`) | Explicit (11 MCP Tools) | BM25 (`tsvector`) + pgvector KNN fused with RRF in `memlord` DB | SOPs, repo conventions, project-specific notes, progressive disclosure snippets, and deliberate deduplication. |

---

## 🛠️ MCP Tools Reference (11 Tools)

Memlord exposes 11 native MCP tools:

| Tool Name | Parameters | Purpose |
|---|---|---|
| `store_memory` | `name`, `content`, `tags`, `workspace_id`, `expiry` | Saves a memory item with deduplication check against near-identical entries. |
| `retrieve_memory` | `query`, `limit`, `workspace_id`, `tags` | Executes hybrid semantic (vector) + BM25 keyword search fused via RRF. |
| `recall_memory` | `time_query`, `workspace_id` | Queries memories using natural language temporal expressions (e.g. "yesterday", "last week"). |
| `list_memories` | `workspace_id`, `page`, `page_size` | Lists paginated memories with optional tag and metadata filtering. |
| `search_by_tag` | `tags`, `operator` (`AND`/`OR`) | High-precision tag-based retrieval. |
| `get_memory` | `name` | Progressive disclosure: retrieves the complete, unabbreviated body of a memory. |
| `update_memory` | `name`, `content`, `tags`, `metadata` | Modifies an existing memory record. |
| `delete_memory` | `name` | Permanently deletes a memory record. |
| `move_memory` | `name`, `target_workspace_id` | Transfers a memory across workspace boundaries. |
| `list_workspaces` | *None* | Enumerates available workspaces and their identifiers. |
| `dream_report` | *None* | Guided consolidation pass analyzing memory conflicts and suggesting merges. |

---

## ⚙️ Configuration & Environment

### Environment Variables (`.env`)

| Variable | Reference / Value | Purpose |
|---|---|---|
| `MEMLORD_VERSION` | `latest` | Container image tag |
| `MEMLORD_POSTGRES_DB` | `memlord` | Database name on `pgvector` |
| `MEMLORD_POSTGRES_USER` | `memlord` | Database user on `pgvector` |
| `MEMLORD_POSTGRES_PASSWORD` | `${MEMLORD_POSTGRES_PASSWORD}` | Database password credential |
| `MEMLORD_OAUTH_JWT_SECRET` | `${MEMLORD_OAUTH_JWT_SECRET}` | JWT secret for OAuth 2.1 token issuance |
| `MEMLORD_PUBLIC_DOMAIN` | `memlord.jamesspencer.me` | Public ingress hostname |
| `MEMLORD_RRF_K` | `60` | Reciprocal Rank Fusion constant for hybrid rank fusion |
| `MEMLORD_SIM_THRESHOLD` | `0.7` | Minimum vector similarity threshold |
| `MEMLORD_DEDUP_THRESHOLD` | `0.95` | Deduplication threshold preventing near-identical saves |

### Docker Compose Service (`docker-compose.yaml`)

```yaml
  memlord:
    image: ghcr.io/myrikld/memlord:${MEMLORD_VERSION:-latest}
    container_name: memlord
    restart: unless-stopped
    volumes:
      - ./memlord/onnx:/app/src/memlord/onnx
    networks:
      - net1
      - ai
      - db
    environment:
      - MEMLORD_HOST=0.0.0.0
      - MEMLORD_PORT=8000
      - MEMLORD_DB_URL=postgresql+asyncpg://${MEMLORD_POSTGRES_USER:-memlord}:${MEMLORD_POSTGRES_PASSWORD}@pgvector:5432/${MEMLORD_POSTGRES_DB:-memlord}
      - MEMLORD_MODEL_DIR=/app/src/memlord/onnx
      - MEMLORD_BASE_URL=https://${MEMLORD_PUBLIC_DOMAIN:-memlord.spencer.lan}
      - MEMLORD_OAUTH_JWT_SECRET=${MEMLORD_OAUTH_JWT_SECRET}
      - MEMLORD_RRF_K=60
      - MEMLORD_DEFAULT_LIMIT=10
      - MEMLORD_SIM_THRESHOLD=0.7
      - MEMLORD_DEDUP_THRESHOLD=0.95
    depends_on:
      pgvector:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://localhost:8000/health')\" || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 25s
```

---

## 🔌 Connecting Clients to Memlord

### 1. Claude Desktop (`claude_desktop_config.json`)
```json
{
  "mcpServers": {
    "memlord": {
      "url": "https://memlord.spencer.lan/mcp",
      "transport": "http"
    }
  }
}
```

### 2. Cursor
In Cursor Settings -> Features -> MCP Servers -> Add New MCP Server:
* **Name**: `memlord`
* **Type**: `http`
* **URL**: `https://memlord.spencer.lan/mcp`

### 3. Hermes Agent (`hermes/config.yaml`)
```yaml
mcp_servers:
  memlord:
    url: "http://memlord:8000/mcp"
    transport: "http"
```

---

## 🛠️ Operational & Diagnostic Commands

### Checking Service Health
```bash
docker compose ps memlord
docker compose exec memlord python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/health').read().decode())"
```

### Inspecting Logs
```bash
docker logs -f memlord
```

### Viewing Database Schema & Tables in pgvector
```bash
docker compose exec -T pgvector psql -U memlord -d memlord -c '\dt'
```
