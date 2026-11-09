# Open WebUI Architecture & Operational Guide

This document provides architecture specifications, integration details, configuration parameters, and maintenance procedures for the **Open WebUI** service in Spencer's homelab.

---

## 📋 Overview

| Attribute | Specification |
|---|---|
| **Service Name** | `open-webui` |
| **Container Name** | `open-webui` |
| **Image** | `ghcr.io/open-webui/open-webui:main` (v0.13.0+) |
| **Role** | Multi-Model Generative AI Chat & Agent Client Interface |
| **Routing Domains** | `https://chat.spencer.lan` (Primary), `https://ai.spencer.lan` (Legacy Alias), `https://${OPENWEBUI_PUBLIC_DOMAIN}` |
| **Internal Port** | `8080` |
| **Database** | PostgreSQL 16 on `pgvector` container (DB: `openwebui`, isolated `db` network) |
| **Vector Knowledge DB** | Dedicated PostgreSQL 16 database (`openwebui_knowledge` on `pgvector` container) for RAG document chunks, external knowledge collections, web cache, and user memory vectors (`VECTOR_DB=pgvector`) |
| **Embedding Engine** | Offloaded to `llama-embed` (`nomic-embed-text`, 768-dim, CPU AVX-512) |
| **Model Ingress** | Direct Llama.cpp MoE Router Server (`http://llama-server:8080/v1` supporting `qwen3.6-35b-a3b` and `qwen3-coder-30b-a3b`) |
| **Web Search Grounding** | Local Firecrawl Cluster (`http://firecrawl:3002`) & SearXNG (`http://searxng:8080`) |
| **Web Loader / Scraper** | Firecrawl Headless Cluster (`http://firecrawl:3002/v2/scrape`) |
| **Agent Action Substrate**| Open Terminal (`http://open-terminal:8000`, isolated `ai` network) |
| **Network Attachments**| `net1` (Traefik Ingress), `ai` (llama-server, llama-embed, OmniRoute, SearXNG, Firecrawl, Open Terminal), `db` (pgvector) |
| **Persistent Storage** | `/data/homelab/open-webui` (`/app/backend/data` in container) |

---

## 🏗️ System Architecture

```mermaid
graph TD
    User["User Client / Browser"] -->|HTTPS :443| Traefik["Traefik Reverse Proxy<br/>(chat.spencer.lan & ai.spencer.lan)"]
    Traefik -->|Forward :8080| OWUI["Open WebUI (v0.13.0+)<br/>ghcr.io/open-webui/open-webui:main"]

    subgraph Storage & Data
        OWUI -->|db network: core state| PG["pgvector (PostgreSQL 16)<br/>openwebui DB (relational)"]
        OWUI -->|db network: RAG vectors| PGK["pgvector (PostgreSQL 16)<br/>openwebui_knowledge DB (vectors)"]
        OWUI -->|local volume| Disk["/data/homelab/open-webui<br/>(/app/backend/data)"]
    end

    subgraph AI Backends & Grounding
        OWUI -->|ai network: direct inference| LlamaServer["llama-server (:8080)<br/>Qwen3.6-35B-A3B MoE"]
        OWUI -->|ai network: direct embeddings| LlamaEmbed["llama-embed (:8081)<br/>nomic-embed-text"]
        OWUI -->|ai network: standalone proxy| OmniRoute["OmniRoute Gateway (:20128)"]
        OWUI -->|ai network| Firecrawl["Firecrawl Scraper & Search (:3002)"]
        OWUI -->|ai network| SearXNG["SearXNG Search (:8080)"]
        OWUI -->|ai network| OT["Open Terminal (:8000)<br/>Remote Shell & File Workspace"]
    end
```

---

## 🧠 Memory Management & Cross-AI Synchronization

### 1. Zero-RAM In-Container Embedding Offload
By default, Open WebUI loads PyTorch and SentenceTransformer weights in memory (~500 MB–1 GB RAM). In our modernized configuration, embeddings are completely offloaded to the dedicated `llama-embed` companion container:
* `RAG_EMBEDDING_ENGINE=openai`
* `RAG_OPENAI_API_BASE_URL=http://llama-embed:8081/v1`
* `RAG_OPENAI_API_KEY=${LLAMA_EMBED_API_KEY:-llama-local}`
* `RAG_EMBEDDING_MODEL=nomic-embed-text`

Open WebUI acts as a pure API client, retaining a minimal memory footprint (~350 MB) while vectorizing documents and user memories at GPU speeds.

### 2. Native Memory Architecture & Historical Migration
Open WebUI operates its own self-contained conversational memory engine backed directly by PostgreSQL on `pgvector`:
* **Native Memory Store**: User memories are stored in the `memory` table and vector-indexed directly using PostgreSQL's `pgvector` extension (`VECTOR_DB=pgvector`).
* **Historical Memory Migration**: All legacy procedural memories and conversational facts from retired memory servers (Memlord and Hindsight) were migrated into Open WebUI via [`scripts/import-memories-to-openwebui.py`](file:///data/homelab/scripts/import-memories-to-openwebui.py), establishing Open WebUI as the consolidated conversational memory system.
* **API Access**: Memories can be queried or managed via Open WebUI's REST API (`GET /api/v1/memories/`, `POST /api/v1/memories/query`).

---

## 🛠️ Configuration Parameters

Key environment variables in [`.env`](file:///data/homelab/.env) and [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml):

```bash
# Core Application
OPENWEBUI_VERSION=main
OPENWEBUI_SECRET_KEY=<secure-secret-key>
OPENWEBUI_PUBLIC_DOMAIN=ai.example.com
ENABLE_SIGNUP=False
ENABLE_VALVE_ENCRYPTION=True

# PostgreSQL & pgvector
OPENWEBUI_POSTGRES_DB=openwebui
OPENWEBUI_KNOWLEDGE_POSTGRES_DB=openwebui_knowledge
OPENWEBUI_POSTGRES_USER=openwebui
OPENWEBUI_POSTGRES_PASSWORD=<secure-password>

# Open Terminal Integration
OPEN_TERMINAL_VERSION=latest
OPEN_TERMINAL_API_KEY=<secure-terminal-api-key>
```

---

## 🗂️ Workspace Models & IDE Integration

Open WebUI provides curated workspace models with custom capability profiles for different operational environments:

| Model ID | Name | Base Model | Capabilities | Target Use Case |
|---|---|---|---|---|
| `qwen3.6-35b-a3b` | Qwen 3.6 35B A3B | Upstream MoE | Full (web search, terminal, tool calling, citations) | Interactive conversational chat with full homelab tooling |
| `qwen` | qwen-all | `qwen3.6-35b-a3b` | Full + Homelab Docs Knowledge Base (`homelab-docs`) | Homelab operations, infrastructure troubleshooting, knowledge queries |
| `qwen3-coder-30b-a3b` | Qwen 3 Coder 30B A3B | Upstream MoE | Raw coding model | Local coding generation and code refactoring |
| `vscode-coder` (alias `vscode`) | VSCode Coder | `qwen3-coder-30b-a3b` | **Raw Passthrough**: No tools, no memory, no knowledge, no web search | VS Code extensions (Continue, Cline, Roo Code, Aider) requiring clean prompt passthrough without prompt contamination |

### Connecting VS Code to Open WebUI
Configure your VS Code AI extension (Continue, Cline, Roo Code, etc.) with the following parameters:
- **Base URL**: `https://chat.spencer.lan/api/v1` (or `https://ai.spencer.lan/api/v1`)
- **API Key**: User Open WebUI API key (`Settings` > `Account` > `API Keys`)
- **Model**: `vscode-coder` (or `vscode`)

---

## 💻 Open Terminal Agent Execution Substrate

Open WebUI integrates natively with **Open Terminal** (`ghcr.io/open-webui/open-terminal:latest`) to provide an isolated computer substrate for AI assistants:

* **Internal Routing**: Communicates via `http://open-terminal:8000` on the private `ai` Docker network.
* **Declarative Configuration**: Injected declaratively on container boot via `TERMINAL_SERVER_CONNECTIONS` in `docker-compose.yaml`:
  ```json
  [{"id":"open-terminal","name":"Open Terminal","enabled":true,"url":"http://open-terminal:8000","key":"${OPEN_TERMINAL_API_KEY}","auth_type":"bearer","config":{"access_grants":[]}}]
  ```
* **Capabilities**: Equips models with remote bash execution, Python scripting, Jupyter notebook execution, and workspace file management with real-time UI tabs.
* **Backend Proxying**: All client interactions and WebSockets are authenticated and proxied through Open WebUI at `/api/v1/terminals/open-terminal/*`.
* **Dedicated Guide**: See [`docs/open-terminal.md`](file:///data/homelab/docs/open-terminal.md) for full operational specifications.

---

## 🔒 Security & Traefik Ingress

* **Middlewares**: Protected globally on Traefik entryPoint `websecure` with `geoblock@file` and `crowdsec-bouncer@file`.
* **TLS**: Traefik automatically terminates TLS using homelab wildcard certificates (`*.spencer.lan`) and Let's Encrypt for public WAN domains.
* **Authentication**: Native user authentication (`WEBUI_AUTH=True`) with email/password and role-based permissions (`admin`, `user`).
* **Valve Encryption at Rest**: Enabled via `ENABLE_VALVE_ENCRYPTION=True`. Open WebUI encrypts all Tool and Function plugin configurations, sensitive API keys, and user valves stored in PostgreSQL using Fernet (AES-128) symmetric encryption. Cryptographic keys are derived deterministically from the persistent `OPENWEBUI_SECRET_KEY` (see [Open WebUI Valves Documentation](https://docs.openwebui.com/features/extensibility/plugin/development/valves/)). Existing unencrypted valve dictionaries remain readable and will be encrypted upon subsequent saves.

---

## 🔍 Health Checks & Operational Verification

```bash
# 1. Container health
docker compose ps open-webui

# 2. Local container health endpoint
docker exec open-webui curl -s http://localhost:8080/health

# 3. Traefik ingress check (LAN)
curl -kfsS https://chat.spencer.lan/health
curl -kfsS https://ai.spencer.lan/health

# 4. View memory entries in PostgreSQL
docker exec pgvector psql -U postgres -d openwebui -c "SELECT count(*) FROM memory;"

# 5. Query user memory via REST API
curl -s -H "Authorization: Bearer <OPENWEBUI_API_KEY>" https://chat.spencer.lan/api/v1/memories/
```

