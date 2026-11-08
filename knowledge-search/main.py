import os
import time
import json
import math
import logging
from typing import Optional, List, Dict, Any
from contextlib import asynccontextmanager

import httpx
import asyncpg
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

# Configure logging
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("knowledge-search")

# Environment variables & Configuration
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@pgvector:5432/openwebui_knowledge"
)
CORE_DATABASE_URL = os.getenv(
    "CORE_DATABASE_URL",
    "postgresql://postgres:postgres@pgvector:5432/openwebui"
)
LLAMA_EMBED_URL = os.getenv(
    "LLAMA_EMBED_URL",
    "http://llama-embed:8081/v1/embeddings"
)
LLAMA_EMBED_API_KEY = os.getenv("LLAMA_EMBED_API_KEY", "llama-local")
LLAMA_EMBED_MODEL = os.getenv("LLAMA_EMBED_MODEL", "nomic-embed-text")
VECTOR_TARGET_DIMS = int(os.getenv("VECTOR_TARGET_DIMS", "1536"))
APP_VERSION = "1.0.0"

# Global connection pools
db_pool: Optional[asyncpg.Pool] = None
core_db_pool: Optional[asyncpg.Pool] = None
collection_meta_cache: Dict[str, Dict[str, Any]] = {}
meta_cache_last_updated = 0.0


async def init_pools():
    global db_pool, core_db_pool
    try:
        logger.info(f"Connecting to primary knowledge database at {DATABASE_URL.split('@')[-1]}...")
        db_pool = await asyncpg.create_pool(
            DATABASE_URL,
            min_size=2,
            max_size=10,
            timeout=10.0,
            command_timeout=30.0
        )
        logger.info("Connected to primary knowledge database.")
    except Exception as e:
        logger.error(f"Failed to connect to primary database: {e}")

    try:
        logger.info(f"Connecting to core openwebui database at {CORE_DATABASE_URL.split('@')[-1]}...")
        core_db_pool = await asyncpg.create_pool(
            CORE_DATABASE_URL,
            min_size=1,
            max_size=5,
            timeout=10.0,
            command_timeout=30.0
        )
        logger.info("Connected to core openwebui database.")
    except Exception as e:
        logger.warning(f"Core database connection skipped or failed: {e}")


async def close_pools():
    global db_pool, core_db_pool
    if db_pool:
        await db_pool.close()
    if core_db_pool:
        await core_db_pool.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_pools()
    yield
    await close_pools()


app = FastAPI(
    title="pgvector Knowledge Search",
    description="Vector & Full-Text Search Explorer for pgvector Knowledge Chunks",
    version=APP_VERSION,
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Pydantic Models
class SearchRequest(BaseModel):
    query: str = Field(..., min_length=1, description="Search query string")
    mode: str = Field("hybrid", description="Search mode: hybrid, vector, or keyword")
    collection: Optional[str] = Field(None, description="Optional collection name filter")
    database: str = Field("openwebui_knowledge", description="Target database (openwebui_knowledge or openwebui)")
    limit: int = Field(15, ge=1, le=100, description="Max results to return")
    threshold: float = Field(0.0, ge=0.0, le=1.0, description="Minimum similarity threshold")
    vector_weight: float = Field(0.7, ge=0.0, le=1.0, description="Vector search weight for hybrid mode")


class SimilarRequest(BaseModel):
    chunk_id: str = Field(..., description="Source chunk ID to find nearest neighbors for")
    limit: int = Field(10, ge=1, le=50, description="Max similar results")
    database: str = Field("openwebui_knowledge", description="Target database")


async def get_embedding(text: str) -> List[float]:
    """Generates an embedding vector using the llama-embed companion service and zero-pads to 1536 dims."""
    headers = {"Content-Type": "application/json"}
    if LLAMA_EMBED_API_KEY:
        headers["Authorization"] = f"Bearer {LLAMA_EMBED_API_KEY}"

    payload = {
        "input": text,
        "model": LLAMA_EMBED_MODEL
    }

    async with httpx.AsyncClient(timeout=20.0) as client:
        resp = await client.post(LLAMA_EMBED_URL, json=payload, headers=headers)
        if resp.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail=f"Embedding service returned {resp.status_code}: {resp.text}"
            )
        data = resp.json()
        raw_embedding = data["data"][0]["embedding"]

    # Zero-pad or truncate to match table schema dimension (1536)
    curr_len = len(raw_embedding)
    if curr_len < VECTOR_TARGET_DIMS:
        padded = raw_embedding + [0.0] * (VECTOR_TARGET_DIMS - curr_len)
    else:
        padded = raw_embedding[:VECTOR_TARGET_DIMS]

    return padded


def vector_to_sql_literal(vec: List[float]) -> str:
    """Formats float list into pgvector string literal '[0.1,0.2,...]'."""
    return "[" + ",".join(f"{x:.8f}" for x in vec) + "]"


async def refresh_collection_metadata():
    """Fetches human-readable knowledge titles and file mappings from core database."""
    global collection_meta_cache, meta_cache_last_updated
    now = time.time()
    if now - meta_cache_last_updated < 60.0 and collection_meta_cache:
        return collection_meta_cache

    new_cache = {}
    if core_db_pool:
        try:
            async with core_db_pool.acquire() as conn:
                # Query knowledge bases
                knowledge_rows = await conn.fetch("SELECT id, name, description FROM knowledge")
                for row in knowledge_rows:
                    new_cache[row["id"]] = {
                        "name": row["name"],
                        "description": row["description"] or "",
                        "type": "Knowledge Base"
                    }

                # Query files
                file_rows = await conn.fetch("SELECT id, filename, meta FROM file")
                for row in file_rows:
                    meta_raw = row["meta"]
                    meta_dict = {}
                    if isinstance(meta_raw, str):
                        try:
                            meta_dict = json.loads(meta_raw)
                        except Exception:
                            pass
                    elif isinstance(meta_raw, dict):
                        meta_dict = meta_raw

                    file_id = row["id"]
                    friendly_name = meta_dict.get("name") or row["filename"]
                    data_obj = meta_dict.get("data") or {}
                    source_url = data_obj.get("source_url") or ""

                    # Map both file-ID and direct ID
                    info = {
                        "name": friendly_name,
                        "description": f"File source: {source_url}" if source_url else f"Filename: {row['filename']}",
                        "source_url": source_url,
                        "type": "Document File"
                    }
                    new_cache[f"file-{file_id}"] = info
                    new_cache[file_id] = info
        except Exception as e:
            logger.warning(f"Error querying core database for collection metadata: {e}")

    collection_meta_cache = new_cache
    meta_cache_last_updated = now
    return collection_meta_cache


def resolve_collection_info(col_name: str, meta_cache: Dict[str, Any]) -> Dict[str, str]:
    """Resolves friendly title and badges for collection IDs."""
    if col_name in meta_cache:
        cached = meta_cache[col_name]
        return {
            "display_name": cached.get("name", col_name),
            "description": cached.get("description", ""),
            "type": cached.get("type", "Knowledge Collection")
        }

    if col_name.startswith("user-memory-"):
        return {
            "display_name": "User Conversational Memory",
            "description": "Dynamic long-term user memories and context facts saved by Open WebUI.",
            "type": "Memory"
        }
    elif col_name.startswith("web-search-"):
        return {
            "display_name": "Web Search & Crawl Cache",
            "description": "Grounding search chunks retrieved via SearXNG and Firecrawl.",
            "type": "Web Grounding"
        }
    elif col_name == "knowledge-bases":
        return {
            "display_name": "System Knowledge Base Directory",
            "description": "Top-level metadata index for registered collections.",
            "type": "System"
        }
    elif col_name.startswith("file-"):
        return {
            "display_name": f"Document {col_name[:12]}...",
            "description": "Uploaded or synchronized document collection.",
            "type": "Document File"
        }
    else:
        return {
            "display_name": col_name,
            "description": "pgvector document collection.",
            "type": "Collection"
        }


# API Endpoints
@app.api_route("/healthz", methods=["GET", "HEAD"])
async def healthz():
    db_ok = False
    embed_ok = False

    if db_pool:
        try:
            async with db_pool.acquire() as conn:
                await conn.fetchval("SELECT 1")
                db_ok = True
        except Exception:
            pass

    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(LLAMA_EMBED_URL.replace("/v1/embeddings", "/health"))
            if resp.status_code == 200:
                embed_ok = True
    except Exception:
        pass

    status = "ok" if (db_ok and embed_ok) else "degraded"
    return {
        "status": status,
        "database": "connected" if db_ok else "disconnected",
        "embeddings": "connected" if embed_ok else "unavailable",
        "version": APP_VERSION
    }


@app.get("/api/stats")
async def get_system_stats():
    if not db_pool:
        raise HTTPException(status_code=503, detail="Database pool not ready")

    meta_cache = await refresh_collection_metadata()

    async with db_pool.acquire() as conn:
        # Check pgvector version
        pgvector_version = await conn.fetchval(
            "SELECT default_version FROM pg_available_extensions WHERE name = 'vector'"
        )
        pg_version = await conn.fetchval("SELECT version()")

        # Chunk counts & collections
        total_chunks = await conn.fetchval("SELECT count(*) FROM document_chunk")
        total_collections = await conn.fetchval("SELECT count(DISTINCT collection_name) FROM document_chunk")

        # Database disk size
        db_size_bytes = await conn.fetchval("SELECT pg_database_size(current_database())")
        table_size_bytes = await conn.fetchval("SELECT pg_total_relation_size('document_chunk')")

    return {
        "total_chunks": total_chunks or 0,
        "total_collections": total_collections or 0,
        "db_size_mb": round((db_size_bytes or 0) / (1024 * 1024), 2),
        "table_size_mb": round((table_size_bytes or 0) / (1024 * 1024), 2),
        "pgvector_version": pgvector_version or "0.7+",
        "postgres_version": (pg_version or "").split(",")[0],
        "embedding_model": LLAMA_EMBED_MODEL,
        "embedding_dimensions_active": 768,
        "embedding_dimensions_schema": VECTOR_TARGET_DIMS,
        "embedding_endpoint": LLAMA_EMBED_URL
    }


@app.get("/api/collections")
async def list_collections():
    if not db_pool:
        raise HTTPException(status_code=503, detail="Database pool not ready")

    meta_cache = await refresh_collection_metadata()

    async with db_pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT
                collection_name,
                count(*) AS chunk_count,
                min(length(text)) AS min_length,
                max(length(text)) AS max_length,
                round(avg(length(text))) AS avg_length,
                (SELECT left(text, 140) FROM document_chunk dc2 WHERE dc2.collection_name = dc1.collection_name LIMIT 1) AS sample_snippet
            FROM document_chunk dc1
            GROUP BY collection_name
            ORDER BY chunk_count DESC
        """)

    collections = []
    for row in rows:
        col_name = row["collection_name"]
        info = resolve_collection_info(col_name, meta_cache)
        collections.append({
            "collection_name": col_name,
            "display_name": info["display_name"],
            "description": info["description"],
            "type": info["type"],
            "chunk_count": row["chunk_count"],
            "min_length": row["min_length"],
            "max_length": row["max_length"],
            "avg_length": row["avg_length"],
            "sample_snippet": row["sample_snippet"] or ""
        })

    return {"collections": collections, "total": len(collections)}


@app.post("/api/search")
async def search_chunks(req: SearchRequest):
    if not db_pool:
        raise HTTPException(status_code=503, detail="Database pool not ready")

    start_time = time.time()
    embedding_time_ms = 0.0
    meta_cache = await refresh_collection_metadata()

    target_pool = db_pool
    # If user explicitly requested openwebui core db
    if req.database == "openwebui" and core_db_pool:
        target_pool = core_db_pool

    query_vec_literal: Optional[str] = None
    if req.mode in ("vector", "hybrid"):
        emb_start = time.time()
        try:
            vec = await get_embedding(req.query)
            query_vec_literal = vector_to_sql_literal(vec)
            embedding_time_ms = round((time.time() - emb_start) * 1000, 2)
        except Exception as e:
            logger.error(f"Embedding error: {e}")
            if req.mode == "vector":
                raise HTTPException(status_code=502, detail=f"Failed to generate query embedding: {e}")
            # Fall back to keyword if hybrid fails
            logger.warning("Falling back from hybrid to keyword search due to embedding error")
            req.mode = "keyword"

    results = []

    async with target_pool.acquire() as conn:
        if req.mode == "vector":
            rows = await conn.fetch("""
                SELECT
                    id,
                    collection_name,
                    text,
                    vmetadata,
                    1 - (vector <=> $1::vector) AS similarity_score
                FROM document_chunk
                WHERE ($2::text IS NULL OR collection_name = $2)
                  AND (1 - (vector <=> $1::vector)) >= $3
                ORDER BY vector <=> $1::vector ASC
                LIMIT $4
            """, query_vec_literal, req.collection, req.threshold, req.limit)

            for rank, r in enumerate(rows, 1):
                col_name = r["collection_name"]
                info = resolve_collection_info(col_name, meta_cache)
                vmeta = r["vmetadata"]
                if isinstance(vmeta, str):
                    try:
                        vmeta = json.loads(vmeta)
                    except Exception:
                        vmeta = {}

                sim = float(r["similarity_score"] or 0.0)
                results.append({
                    "id": r["id"],
                    "collection_name": col_name,
                    "display_name": info["display_name"],
                    "collection_type": info["type"],
                    "text": r["text"] or "",
                    "metadata": vmeta or {},
                    "similarity_score": round(sim, 4),
                    "similarity_pct": round(max(0.0, min(100.0, sim * 100.0)), 1),
                    "rank": rank
                })

        elif req.mode == "keyword":
            rows = await conn.fetch("""
                SELECT
                    id,
                    collection_name,
                    text,
                    vmetadata,
                    ts_rank_cd(to_tsvector('simple', COALESCE(text, '')), plainto_tsquery('simple', $1)) AS rank_score
                FROM document_chunk
                WHERE ($2::text IS NULL OR collection_name = $2)
                  AND (
                      to_tsvector('simple', COALESCE(text, '')) @@ plainto_tsquery('simple', $1)
                      OR text ILIKE '%' || $1 || '%'
                  )
                ORDER BY rank_score DESC, length(text) ASC
                LIMIT $3
            """, req.query, req.collection, req.limit)

            for rank, r in enumerate(rows, 1):
                col_name = r["collection_name"]
                info = resolve_collection_info(col_name, meta_cache)
                vmeta = r["vmetadata"]
                if isinstance(vmeta, str):
                    try:
                        vmeta = json.loads(vmeta)
                    except Exception:
                        vmeta = {}

                r_score = float(r["rank_score"] or 0.0)
                results.append({
                    "id": r["id"],
                    "collection_name": col_name,
                    "display_name": info["display_name"],
                    "collection_type": info["type"],
                    "text": r["text"] or "",
                    "metadata": vmeta or {},
                    "rank_score": round(r_score, 4),
                    "rank": rank
                })

        elif req.mode == "hybrid":
            # Run vector search
            candidate_limit = max(req.limit * 2, 30)
            v_rows = await conn.fetch("""
                SELECT
                    id,
                    collection_name,
                    text,
                    vmetadata,
                    1 - (vector <=> $1::vector) AS similarity_score
                FROM document_chunk
                WHERE ($2::text IS NULL OR collection_name = $2)
                  AND (1 - (vector <=> $1::vector)) >= $3
                ORDER BY vector <=> $1::vector ASC
                LIMIT $4
            """, query_vec_literal, req.collection, req.threshold, candidate_limit)

            # Run keyword search
            k_rows = await conn.fetch("""
                SELECT
                    id,
                    collection_name,
                    text,
                    vmetadata,
                    ts_rank_cd(to_tsvector('simple', COALESCE(text, '')), plainto_tsquery('simple', $1)) AS rank_score
                FROM document_chunk
                WHERE ($2::text IS NULL OR collection_name = $2)
                  AND (
                      to_tsvector('simple', COALESCE(text, '')) @@ plainto_tsquery('simple', $1)
                      OR text ILIKE '%' || $1 || '%'
                  )
                ORDER BY rank_score DESC, length(text) ASC
                LIMIT $3
            """, req.query, req.collection, candidate_limit)

            # Reciprocal Rank Fusion (RRF)
            # RRF score = sum(weight / (60 + rank))
            rrf_k = 60.0
            w_v = req.vector_weight
            w_k = 1.0 - req.vector_weight

            merged_chunks: Dict[str, Dict[str, Any]] = {}

            for v_rank, r in enumerate(v_rows, 1):
                chunk_id = r["id"]
                sim = float(r["similarity_score"] or 0.0)
                score = w_v * (1.0 / (rrf_k + v_rank))

                vmeta = r["vmetadata"]
                if isinstance(vmeta, str):
                    try:
                        vmeta = json.loads(vmeta)
                    except Exception:
                        vmeta = {}

                merged_chunks[chunk_id] = {
                    "id": chunk_id,
                    "collection_name": r["collection_name"],
                    "text": r["text"] or "",
                    "metadata": vmeta or {},
                    "similarity_score": round(sim, 4),
                    "similarity_pct": round(max(0.0, min(100.0, sim * 100.0)), 1),
                    "rank_score": 0.0,
                    "rrf_score": score,
                    "vector_rank": v_rank,
                    "keyword_rank": None
                }

            for k_rank, r in enumerate(k_rows, 1):
                chunk_id = r["id"]
                r_score = float(r["rank_score"] or 0.0)
                score = w_k * (1.0 / (rrf_k + k_rank))

                if chunk_id in merged_chunks:
                    merged_chunks[chunk_id]["rrf_score"] += score
                    merged_chunks[chunk_id]["rank_score"] = round(r_score, 4)
                    merged_chunks[chunk_id]["keyword_rank"] = k_rank
                else:
                    vmeta = r["vmetadata"]
                    if isinstance(vmeta, str):
                        try:
                            vmeta = json.loads(vmeta)
                        except Exception:
                            vmeta = {}

                    merged_chunks[chunk_id] = {
                        "id": chunk_id,
                        "collection_name": r["collection_name"],
                        "text": r["text"] or "",
                        "metadata": vmeta or {},
                        "similarity_score": 0.0,
                        "similarity_pct": 0.0,
                        "rank_score": round(r_score, 4),
                        "rrf_score": score,
                        "vector_rank": None,
                        "keyword_rank": k_rank
                    }

            # Sort by combined RRF score descending
            sorted_items = sorted(
                merged_chunks.values(),
                key=lambda x: x["rrf_score"],
                reverse=True
            )[:req.limit]

            for rank, item in enumerate(sorted_items, 1):
                col_name = item["collection_name"]
                info = resolve_collection_info(col_name, meta_cache)
                item["display_name"] = info["display_name"]
                item["collection_type"] = info["type"]
                item["rank"] = rank
                # Scale RRF score to human-friendly 0-100 range
                item["hybrid_score_pct"] = round(item["rrf_score"] * 3000.0, 1)
                results.append(item)

    search_time_ms = round((time.time() - start_time) * 1000, 2)

    return {
        "results": results,
        "query": req.query,
        "mode": req.mode,
        "total_results": len(results),
        "search_time_ms": search_time_ms,
        "embedding_time_ms": embedding_time_ms,
        "collection_filter": req.collection,
        "database": req.database
    }


@app.get("/api/chunks/{chunk_id}")
async def get_chunk_details(chunk_id: str, database: str = Query("openwebui_knowledge")):
    if not db_pool:
        raise HTTPException(status_code=503, detail="Database pool not ready")

    target_pool = db_pool
    if database == "openwebui" and core_db_pool:
        target_pool = core_db_pool

    meta_cache = await refresh_collection_metadata()

    async with target_pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT
                id,
                collection_name,
                text,
                vmetadata,
                vector::text AS vector_str
            FROM document_chunk
            WHERE id = $1
        """, chunk_id)

    if not row:
        raise HTTPException(status_code=404, detail="Chunk not found")

    col_name = row["collection_name"]
    info = resolve_collection_info(col_name, meta_cache)

    raw_text = row["text"] or ""
    vmeta = row["vmetadata"]
    if isinstance(vmeta, str):
        try:
            vmeta = json.loads(vmeta)
        except Exception:
            vmeta = {}

    # Inspect vector components
    vector_str = row["vector_str"] or "[]"
    clean_vec = vector_str.strip("[]")
    vec_floats = [float(x) for x in clean_vec.split(",") if x.strip()] if clean_vec else []

    total_dims = len(vec_floats)
    non_zero_dims = sum(1 for x in vec_floats if abs(x) > 1e-7)
    l2_norm = math.sqrt(sum(x * x for x in vec_floats)) if vec_floats else 0.0

    return {
        "id": row["id"],
        "collection_name": col_name,
        "display_name": info["display_name"],
        "collection_type": info["type"],
        "text": raw_text,
        "character_length": len(raw_text),
        "estimated_tokens": max(1, round(len(raw_text) / 4)),
        "metadata": vmeta or {},
        "vector_stats": {
            "total_dimensions": total_dims,
            "non_zero_dimensions": non_zero_dims,
            "zero_padded_dimensions": total_dims - non_zero_dims,
            "l2_norm": round(l2_norm, 4),
            "preview": vec_floats[:8]
        }
    }


@app.post("/api/similar")
async def find_similar_chunks(req: SimilarRequest):
    if not db_pool:
        raise HTTPException(status_code=503, detail="Database pool not ready")

    target_pool = db_pool
    if req.database == "openwebui" and core_db_pool:
        target_pool = core_db_pool

    meta_cache = await refresh_collection_metadata()

    async with target_pool.acquire() as conn:
        # Check source chunk
        source = await conn.fetchrow("""
            SELECT id, collection_name, left(text, 100) as snippet, vector
            FROM document_chunk
            WHERE id = $1
        """, req.chunk_id)

        if not source:
            raise HTTPException(status_code=404, detail="Source chunk not found")

        # Find nearest neighbors by cosine similarity
        rows = await conn.fetch("""
            SELECT
                id,
                collection_name,
                text,
                vmetadata,
                1 - (vector <=> (SELECT vector FROM document_chunk WHERE id = $1)) AS similarity_score
            FROM document_chunk
            WHERE id != $1
            ORDER BY vector <=> (SELECT vector FROM document_chunk WHERE id = $1) ASC
            LIMIT $2
        """, req.chunk_id, req.limit)

    results = []
    for rank, r in enumerate(rows, 1):
        col_name = r["collection_name"]
        info = resolve_collection_info(col_name, meta_cache)
        vmeta = r["vmetadata"]
        if isinstance(vmeta, str):
            try:
                vmeta = json.loads(vmeta)
            except Exception:
                vmeta = {}

        sim = float(r["similarity_score"] or 0.0)
        results.append({
            "id": r["id"],
            "collection_name": col_name,
            "display_name": info["display_name"],
            "collection_type": info["type"],
            "text": r["text"] or "",
            "metadata": vmeta or {},
            "similarity_score": round(sim, 4),
            "similarity_pct": round(max(0.0, min(100.0, sim * 100.0)), 1),
            "rank": rank
        })

    return {
        "source_chunk_id": req.chunk_id,
        "results": results,
        "total_results": len(results)
    }


# Mount static directory and root index.html
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.api_route("/", methods=["GET", "HEAD"], response_class=HTMLResponse)
async def serve_index():
    index_path = os.path.join(os.path.dirname(__file__), "static", "index.html")
    if not os.path.exists(index_path):
        return HTMLResponse("<h1>Static index.html not found</h1>", status_code=404)
    with open(index_path, "r", encoding="utf-8") as f:
        return HTMLResponse(f.read())
