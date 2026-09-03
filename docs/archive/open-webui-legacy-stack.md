# Legacy Service Archive: Open WebUI, PostgreSQL `db`, Open Terminal & Browserless

This archive document preserves the exact configurations, container architectures, environment variables, and restoration instructions for the retired Open WebUI stack.

---

## 📋 Overview of Retired Services

Prior to decommissioning, these services constituted the initial web chat interface and supporting execution/scraping engines:

| Service | Container Name | Image | Role | Port / Routing |
|---|---|---|---|---|
| **Open WebUI** | `open-webui` | `ghcr.io/open-webui/open-webui:main` | ChatGPT-style web UI client | `ai.spencer.lan` (:8080 internal) |
| **PostgreSQL** | `postgres` (service `db`) | `pgvector/pgvector:pg16` | Relational & vector database for Open WebUI | Internal port 5432 on `db` network |
| **Open Terminal** | `open-terminal` | `ghcr.io/open-webui/open-terminal:main` | Code interpreter execution sandbox | Internal port 8000 on `ai` network |
| **Browserless Chrome** | `browserless` | `browserless/chrome:latest` | Headless Chromium automation | Internal port 3000 on `ai` network |

**Why Retired**:
* **Superseded by Modern Stack**: Hermes Agent (with its Web Dashboard, Desktop App, MCP Server, and native Docker code execution sandbox), LiteLLM Proxy, and Hindsight Long-Term Memory provided full feature parity and superior agent autonomy.
* **Resource Reclamation**: Shutting down these 4 containers reclaimed **~1.02 GB of idle system memory** and eliminated redundant background polling.

---

## 🛠️ Docker Compose Configuration (Restoration Block)

If you ever wish to redeploy this stack, add the following service definitions back into [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml):

```yaml
  db:
    image: pgvector/pgvector:${POSTGRES_VERSION:-pg16}
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-openwebui}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-openwebui}
    volumes:
      - ./postgres:/var/lib/postgresql/data
    networks:
      - db
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-openwebui} -d ${POSTGRES_DB:-openwebui}"]
      interval: 5s
      timeout: 5s
      retries: 5

  open-webui:
    image: ghcr.io/open-webui/open-webui:${WEBUI_DOCKER_TAG:-main}
    container_name: open-webui
    restart: unless-stopped
    networks:
      - net1
      - ai
      - db
    volumes:
      - ./open-webui:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${OPENWEBUI_SECRET_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
      - VECTOR_DB=pgvector
      - VECTOR_DB_URI=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
      - ENABLE_RAG_WEB_SEARCH=True
      - RAG_WEB_SEARCH_ENGINE=searxng
      - SEARXNG_QUERY_URL=http://searxng:8080/search?q=<query>
      - WEB_SEARCH_TRUST_ENV=True
      - AIOHTTP_CLIENT_ASYNC_DNS_RESOLVER=False
      - GLOBAL_LOG_LEVEL=INFO
      - RAG_WEB_LOADER_ENGINE=playwright
      - PLAYWRIGHT_WS_URI=ws://browserless:3000
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.open-webui.rule=Host(`ai.spencer.lan`)"
      - "traefik.http.routers.open-webui.entrypoints=websecure"
      - "traefik.http.routers.open-webui.tls=true"
      - "traefik.http.services.open-webui.loadbalancer.server.port=8080"
    depends_on:
      - ollama
      - db
      - browserless
  
  open-terminal:
    image: ghcr.io/open-webui/open-terminal:${TERMINAL_DOCKER_TAG:-main}
    container_name: open-terminal
    restart: unless-stopped
    networks:
      - ai
    volumes:
      - ./open-terminal:/home/user
    environment:
      - OPEN_TERMINAL_API_KEY=${OPEN_TERMINAL_API_KEY}
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.25'
          memory: 512M

  browserless:
    image: browserless/chrome:latest
    container_name: browserless
    restart: unless-stopped
    networks:
      - ai
    environment:
      - MAX_CONCURRENT_SESSIONS=10
      - CONNECTION_TIMEOUT=60000
```

---

## 🔑 Environment Variables ([`.env`](file:///data/homelab/.env))

Add these variables back to `.env` if restoring:

```bash
# PostgreSQL (Legacy Open WebUI DB)
POSTGRES_USER=openwebui
POSTGRES_PASSWORD=<secure-password>
POSTGRES_DB=openwebui
POSTGRES_VERSION=pg16

# Open WebUI
WEBUI_DOCKER_TAG=main
OPENWEBUI_SECRET_KEY=<secret-key>

# Open Terminal
TERMINAL_DOCKER_TAG=main
OPEN_TERMINAL_API_KEY=<token>

# Browserless Chrome
BROWSER_CDP_URL=ws://browserless:3000
```

---

## 🚀 Restoration Procedure

1. **Ensure Directories Exist**:
   ```bash
   mkdir -p open-webui open-terminal postgres
   ```
2. **Re-add Compose Block**:
   Paste the services above into `docker-compose.yaml`.
3. **If `ai.spencer.lan` is aliased to Hermes**:
   Remove `Host('ai.spencer.lan')` from the `hermes-dashboard` router labels so Traefik does not route conflicting rules.
4. **Deploy Containers**:
   ```bash
   docker compose up -d open-terminal db browserless open-webui
   ```
5. **Verify**:
   Access `https://ai.spencer.lan` and confirm login.
