# pgvector Knowledge Search Guide

A dedicated, lightweight vector and full-text search web interface and REST API for exploring, auditing, and querying Open WebUI's knowledge chunk database in `pgvector`.

---

## 🎯 Overview & Architecture

* **Role**: Interactive web dashboard and API for searching, inspecting, and auditing vector knowledge chunks, user memories, and RAG document partitions.
* **Container Name**: `knowledge-search`
* **Local Ingress**: [`https://knowledge.spencer.lan`](https://knowledge.spencer.lan), [`https://rag.spencer.lan`](https://rag.spencer.lan)
* **Internal Port**: `8000`
* **Networks**:
  * `net1`: Attached for Traefik reverse proxy ingress and TLS termination.
  * `db`: Attached for direct high-performance binary connection to `pgvector:5432` (`openwebui_knowledge` and `openwebui`).
  * `ai`: Attached for fast zero-VRAM text vector embeddings via `llama-embed:8081` (`nomic-embed-text`).
* **Technology Stack**: Python 3.12 (slim), FastAPI, asyncpg, httpx, Uvicorn, Tailwind CSS, Marked.js.

---

## 🔍 Retrieval Engines & Features

### 1. Hybrid Search (Reciprocal Rank Fusion - RRF)
Combines dense semantic vector retrieval with sparse full-text keyword ranking using standard Reciprocal Rank Fusion:
$$\text{RRF Score}(d) = \frac{w_v}{60 + \text{rank}_v} + \frac{w_k}{60 + \text{rank}_k}$$
Where $w_v = 0.7$ (vector weight) and $w_k = 0.3$ (keyword weight). Provides optimal recall for both high-level semantic questions and exact code/identifier queries.

### 2. Dense Semantic Vector Search
* Generates query embeddings on-the-fly via the local CPU AVX-512 accelerated `llama-embed` companion container using model `nomic-embed-text`.
* Embeddings (768 dimensions) are automatically zero-padded to 1536 dimensions to align seamlessly with Open WebUI's `vector(1536)` PostgreSQL schema.
* Cosine distance calculation in PostgreSQL:
  ```sql
  SELECT id, collection_name, text, vmetadata,
         1 - (vector <=> $1::vector) AS similarity_score
  FROM document_chunk
  WHERE ($2::text IS NULL OR collection_name = $2)
    AND (1 - (vector <=> $1::vector)) >= $3
  ORDER BY vector <=> $1::vector ASC
  LIMIT $4;
  ```

### 3. Sparse Full-Text / Keyword Search
* Leverages PostgreSQL's pre-indexed GIN `to_tsvector('simple', text)` full-text search engine.
* Calculates document rank via `ts_rank_cd` and falls back gracefully to `ILIKE` substring search for symbols, URLs, and hash identifiers.

### 4. Interactive Chunk Inspection & Similarity Explorer
* **Nearest Neighbors Explorer (`/api/similar`)**: Click "Find Similar" on any result card to compute cosine similarity against the chunk's vector and find related chunks across all collections.
* **Vector Telemetry**: Inspect vector dimensions (1536 schema / 768 active), zero-padded dimensions, and L2 norm.
* **JSON Metadata Viewer**: Formatted view of all chunk tags, source URLs, start indices, and timestamps.
* **Collection Directory**: Visual directory of all collections with chunk counts, average character lengths, and sample snippets.

---

## ⚙️ Configuration & Environment

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | `postgresql://${PGVECTOR_USER}:${PGVECTOR_PASSWORD}@pgvector:5432/${OPENWEBUI_KNOWLEDGE_POSTGRES_DB}` | Primary knowledge vector database connection string |
| `CORE_DATABASE_URL` | `postgresql://${PGVECTOR_USER}:${PGVECTOR_PASSWORD}@pgvector:5432/${OPENWEBUI_POSTGRES_DB}` | Core Open WebUI database for mapping collection and file titles |
| `LLAMA_EMBED_URL` | `http://llama-embed:8081/v1/embeddings` | Internal companion endpoint for vector embeddings |
| `LLAMA_EMBED_API_KEY` | `${LLAMA_EMBED_API_KEY:-llama-local}` | Companion authentication bearer token |
| `LLAMA_EMBED_MODEL` | `nomic-embed-text` | Embedding model identifier |
| `VECTOR_TARGET_DIMS` | `1536` | Target schema vector dimension (zero-padded) |

---

## 📡 REST API Reference

### Healthcheck
```http
GET /healthz
```
Response:
```json
{
  "status": "ok",
  "database": "connected",
  "embeddings": "connected",
  "version": "1.0.0"
}
```

### Knowledge Base Telemetry
```http
GET /api/stats
```
Response:
```json
{
  "total_chunks": 630,
  "total_collections": 7,
  "db_size_mb": 14.64,
  "table_size_mb": 6.83,
  "pgvector_version": "0.8.6",
  "postgres_version": "PostgreSQL 16.15 ...",
  "embedding_model": "nomic-embed-text",
  "embedding_dimensions_active": 768,
  "embedding_dimensions_schema": 1536,
  "embedding_endpoint": "http://llama-embed:8081/v1/embeddings"
}
```

### Collections Directory
```http
GET /api/collections
```

### Search Chunks
```http
POST /api/search
Content-Type: application/json

{
  "query": "Traefik reverse proxy configuration",
  "mode": "hybrid",
  "collection": null,
  "database": "openwebui_knowledge",
  "limit": 15,
  "threshold": 0.5
}
```

### Chunk Inspection
```http
GET /api/chunks/{chunk_id}
```

### Nearest Neighbor Similarity
```http
POST /api/similar
Content-Type: application/json

{
  "chunk_id": "cef6441e-990b-4b04-add7-9e52da655be2",
  "limit": 10
}
```

---

## 🛠️ Operational Commands

* **Build and Start Service**:
  ```bash
  docker compose up -d --build knowledge-search
  ```
* **View Real-Time Logs**:
  ```bash
  docker logs -f knowledge-search
  ```
* **Execute Direct CLI Test Search**:
  ```bash
  curl -k -s -X POST https://knowledge.spencer.lan/api/search \
    -H "Content-Type: application/json" \
    -d '{"query": "Authentik SSO", "mode": "hybrid", "limit": 3}' | jq .
  ```
