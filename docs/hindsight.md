# Hindsight Long-Term Memory Engine

**Hindsight** (by Vectorize.io) is an agent memory system that extracts facts, models entities, and maintains consolidated observations across conversations. It enables **Nous Research Hermes Agent** to retain long-term context and learn continuously over time.

---

## 🎯 Overview & Architecture

* **Role**: Dedicated long-term memory engine and memory bank API for Hermes Agent.
* **Container Name**: `hindsight` (Service name: `hindsight`)
* **Image**: `ghcr.io/vectorize-io/hindsight:${HINDSIGHT_VERSION:-latest}`
* **Networks**:
  * `ai`: Inter-service AI network connecting Hermes Agent (`http://hindsight:8888`) and Ollama (`http://ollama:11434/v1`).
  * `db`: Isolated database network connecting to the dedicated `pgvector` PostgreSQL instance.
  * `net1`: Traefik reverse proxy bridge exposing the Hindsight Control Plane Web UI.
* **Internal Ports**:
  * `8888`: Hindsight HTTP API endpoint (consumed by Hermes Agent).
  * `9999`: Hindsight Control Plane Web UI.
* **External Ingress**:
  * Control Plane Dashboard: `https://hindsight.spencer.lan` (`:9999` via Traefik).

```mermaid
graph TD
    Traefik[Traefik Proxy] -->|hindsight.spencer.lan :9999| HindsightUI[Hindsight Control Plane UI]
    
    subgraph AI Network
        Hermes[Hermes Agent] -->|API Calls :8888| HindsightAPI[Hindsight Service]
        HindsightAPI -->|Fact Extraction & Reflection| Ollama[Ollama :11434]
    end

    subgraph DB Network
        HindsightAPI -->|Vector & Relational Storage :5432| Pgvector[pgvector Container]
    end
```

---

## 🔒 Security & Network Isolation

* **Strict Network Segmentation**:
  * Hindsight bridges `ai` and `db` without exposing `pgvector` directly to Hermes or other agent runtimes.
  * Port `8888` (API) is restricted to the internal Docker `ai` network and is not directly accessible from the host.
  * Port `9999` (Control Plane) is routed securely through Traefik with TLS termination at `hindsight.spencer.lan`.

---

## ⚙️ Configuration & Environment

### 1. Docker Compose Environment Variables

| Variable | Default / Reference | Purpose |
|---|---|---|
| `HINDSIGHT_VERSION` | `latest` | Hindsight container image tag |
| `HINDSIGHT_API_DATABASE_URL` | `postgresql://hindsight:...@pgvector:5432/hindsight` | Connection string to dedicated pgvector database |
| `HINDSIGHT_API_VECTOR_EXTENSION` | `pgvector` | Vector algorithm (`pgvector`) |
| `HINDSIGHT_API_WORKER_ID` | `hindsight-worker` | Static worker identifier for task recovery |
| `HINDSIGHT_API_LLM_PROVIDER` | `ollama` | Provider backend for fact extraction and reflection |
| `HINDSIGHT_API_LLM_BASE_URL` | `http://ollama:11434/v1` | Ollama OpenAI-compatible API endpoint |
| `HINDSIGHT_API_LLM_MODEL` | `qwen2.5:14b` | Model used for memory consolidation |
| `HINDSIGHT_API_LLM_MAX_CONCURRENT` | `1` | Concurrency limit to prevent local LLM slot exhaustion |
| `HINDSIGHT_API_EMBEDDINGS_PROVIDER` | `local` | Built-in local embeddings (`BAAI/bge-small-en-v1.5`) |

### 2. Hermes Agent Memory Configuration

In `hermes/config.yaml`:
```yaml
memory:
  provider: hindsight
```

In `hermes/hindsight/config.json`:
```json
{
  "mode": "local_external",
  "api_url": "http://hindsight:8888",
  "bank_id": "hermes",
  "recall_budget": "mid",
  "auto_recall": true,
  "auto_retain": true
}
```

---

## 🧠 Hermes Memory Capabilities & Tools

When Hindsight is activated in Hermes:
* **Automatic Ingestion (`auto_retain`)**: Turns are sent asynchronously to Hindsight after each interaction. Hindsight parses entities, relations, and observations.
* **Automatic Recall (`auto_recall`)**: Relevant memories and observations are prefetched and injected directly into Hermes' context before each prompt.
* **Agent Tools**: Hermes is equipped with Hindsight toolset:
  * `hindsight_retain`: Manually store specific knowledge or instructions with tags.
  * `hindsight_recall`: Query the semantic memory graph across entities and observations.
  * `hindsight_reflect`: Synthesize cross-memory inferences and high-level summaries.

---

## 🛠️ Operational & Diagnostic Commands

### Checking Service Health
```bash
# Check container status
docker compose ps hindsight

# Query Hindsight health endpoint from internal network
docker compose exec hermes curl -s http://hindsight:8888/health
```

### Inspecting Hindsight Logs
```bash
docker logs -f hindsight
```

### Viewing Stored Tables & Entities in pgvector
```bash
# Connect to pgvector container and inspect hindsight schema
docker compose exec -T pgvector psql -U hindsight -d hindsight -c '\dt'
```

### Verifying Hermes Integration
```bash
# Verify active memory provider in Hermes
docker compose exec -T hermes python -c "from plugins.memory import _get_active_memory_provider; print('Active provider:', _get_active_memory_provider())"
```
