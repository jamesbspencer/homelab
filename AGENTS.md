# Agent Guidelines for Spencer's Homelab Workspace

This file defines guidelines, rules, and architecture constraints that AI agents must follow when operating in the `/data/homelab` workspace.

---

## 🔍 System Context & Architecture

- **Services**:
  - **Traefik Reverse Proxy**: Single entry point for all HTTP/HTTPS traffic to the homelab (`traefik.spencer.lan`).
  - **Ollama**: Local LLM server configured with NVIDIA GPU hardware acceleration.
  - **LiteLLM Proxy**: Unified LLM routing gateway, spend manager, and model fallback router on internal port `4000` and `llm.spencer.lan`.
  - **Nous Research Hermes Agent**: Autonomous AI agent runtime, management dashboard, and Model Context Protocol (MCP) server (`hermes.spencer.lan`, `ai.spencer.lan`, `hermes-api.spencer.lan`, `mcp.spencer.lan`) with Docker execution sandbox.
  - **Hindsight Long-Term Memory**: Persistent memory engine for Hermes Agent on internal port `8888` and Control Plane UI on `hindsight.spencer.lan` (`:9999`).
  - **Firecrawl Stack**: Web scraping, crawling, and search cluster (`firecrawl`, `rabbitmq`, `nuq-postgres`, `playwright-service`) on internal port `3002`.
  - **SearXNG**: Privacy-respecting metasearch engine providing JSON search endpoints on internal port `8080`.
  - **Valkey**: High-performance in-memory key-value cache and rate limiter on internal port `6379`.
  - **CrowdSec & Traefik Bouncer**: Intrusion detection and prevention engine parsing Traefik access logs with in-memory stream mode enforcement via the Traefik bouncer plugin.
  - **PostgreSQL Database (`pgvector`)**: Unified relational and vector database container configured on the isolated `db` network for Hindsight and LiteLLM.
- **Domain Suffix**: All services in this homelab are routed under the local `.spencer.lan` domain (e.g., `traefik.spencer.lan`, `llm.spencer.lan`, `hermes.spencer.lan`, `ai.spencer.lan`, `hermes-api.spencer.lan`, `mcp.spencer.lan`, `hindsight.spencer.lan`).
- **Networking**:
  - The Traefik container and proxied services requiring external web access (Hermes Gateway, Hermes Dashboard, Hermes MCP, Hindsight UI, LiteLLM) as well as the CrowdSec Local API engine must belong to the bridge network named `net1`.
  - Internal AI communication (between Hermes, Hindsight, LiteLLM, Ollama, SearXNG, Firecrawl) occurs on the isolated bridge network named `ai`.
  - Database services (`pgvector`) are isolated on the dedicated bridge network named `db` and must **not** expose ports to the host or attach to the `ai` network. Any service needing database access must connect to the `db` network.
  - Cache services (Valkey, SearXNG, Firecrawl) communicate on the dedicated bridge network named `redis`.
  - Internal backend services (Firecrawl, SearXNG, Valkey, pgvector) should **not** expose ports to the host or Traefik unless explicitly requested. Proxied web services let Traefik handle routing via container labels.
- **Documentation**: Detailed architecture, configuration, and operational guides for every service reside in [`docs/`](file:///data/homelab/docs/README.md). Always update the corresponding service guide when adding or modifying service configurations. Legacy/retired stack guides reside in [`docs/archive/`](file:///data/homelab/docs/archive/open-webui-legacy-stack.md).

---

## 🛠️ Operational Rules & Safety Guidelines

### 1. Docker Compose & Configuration Changes
- Before applying edits to [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml), verify syntax validity. You can check config validity by running:
  ```bash
  docker compose config
  ```
- **Do not** modify ports `80` and `443` binding on the Traefik container, as they are reserved for the reverse proxy entrypoints.
- **GPU Resource Pass-through**: Do not remove or alter the `nvidia` GPU resource reservations block for the `ollama` service without explicit user instructions, as hardware acceleration is required for local LLM inference.

### 2. Traefik Configurations
- **Static vs. Dynamic Configuration**:
  - **Static Configuration** is located in [`traefik/traefik.yml`](file:///data/homelab/traefik/traefik.yml). Edits to this file **require a restart** of the Traefik container:
    ```bash
    docker compose up -d --force-recreate traefik
    ```
  - **Dynamic Configuration** is located in [`traefik/dynamic.yml`](file:///data/homelab/traefik/dynamic.yml). The File Provider is configured with `watch: true`, so edits here are **automatically applied** by Traefik without requiring a restart.
- **Service Registration**:
  - Since `exposedByDefault` is set to `false` in `traefik.yml`, any container you want to expose via Traefik **must** include the label:
    ```yaml
    labels:
      - "traefik.enable=true"
    ```

### 3. TLS Certificates & ACME
- Wildcard certificates are stored in [`traefik/certs/cert.pem`](file:///data/homelab/traefik/certs/cert.pem) and [`traefik/certs/key.pem`](file:///data/homelab/traefik/certs/key.pem).
- If you configure Let's Encrypt (ACME), the ACME storage file `acme.json` **must** have its permissions set to `600` (read/write by owner only). If you recreate or touch this file, run:
  ```bash
  chmod 600 traefik/acme.json
  ```

### 4. Code Style & Formats
- Keep YAML documents formatted with **2-space indentations**.
- Retain comments in YAML files where they describe configuration logic.

### 5. Automated Command Execution & Safety
- **Read-Only / Non-Modifying Commands**: Gemini and AI agents are explicitly permitted to automatically propose and execute read-only, non-destructive commands without pausing or asking for interactive confirmation. This includes commands such as:
  - System and container status queries (`docker ps`, `docker inspect`, `docker logs`)
  - Network and endpoint testing (`curl`, `nc`, `ping`, HTTP status checks)
  - File viewing, diffing, and searching (`git status`, `git diff`, `grep`, `cat`, `find`)
  - Diagnostic and inspection scripts that do not alter state
- **State-Changing / Destructive Commands**: Any command that creates, destroys, modifies, or restarts services (e.g., `docker compose up -d`, `docker compose down`, `rm`, `kill`, schema migrations) should align with the current implementation plan or task scope.

