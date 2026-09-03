# Agent Guidelines for Spencer's Homelab Workspace

This file defines guidelines, rules, and architecture constraints that AI agents must follow when operating in the `/data/homelab` workspace.

---

## 🔍 System Context & Architecture

- **Services**:
  - **Traefik Reverse Proxy**: Single entry point for all HTTP/HTTPS traffic to the homelab (`traefik.spencer.lan`).
  - **Ollama**: Local LLM server configured with NVIDIA GPU hardware acceleration.
  - **Open WebUI**: User interface client for interacting with Ollama, serving at `ai.spencer.lan`.
  - **Nous Research Hermes Agent**: Autonomous AI agent runtime and management dashboard (`hermes.spencer.lan`, `hermes-dashboard.spencer.lan`) with Docker execution sandbox.
  - **Hindsight Long-Term Memory**: Persistent memory engine for Hermes Agent on internal port `8888` and Control Plane UI on `hindsight.spencer.lan` (`:9999`).
  - **Firecrawl Stack**: Web scraping, crawling, and search cluster (`firecrawl`, `rabbitmq`, `nuq-postgres`, `playwright-service`) on internal port `3002`.
  - **SearXNG**: Privacy-respecting metasearch engine providing JSON search endpoints on internal port `8080`.
  - **Valkey**: High-performance in-memory key-value cache and rate limiter on internal port `6379`.
  - **Browserless Chrome**: Headless Chromium browser for Playwright scraping and CDP automation on internal port `3000`.
  - **Open Terminal**: Sandboxed code execution environment on internal port `8000`.
  - **PostgreSQL Database (Legacy `db` & Standalone `pgvector`)**: Database containers configured to run on the dedicated `db` network (`pgvector` for Hindsight and general services; `db` for Open WebUI).
- **Domain Suffix**: All services in this homelab are routed under the local `.spencer.lan` domain (e.g., `traefik.spencer.lan`, `ai.spencer.lan`, `hermes.spencer.lan`, `hindsight.spencer.lan`).
- **Networking**:
  - The Traefik container and proxied services requiring external web access (Open WebUI, Hermes Gateway, Hermes Dashboard, Hindsight UI) must belong to the bridge network named `net1`.
  - Internal AI communication (between Open WebUI, Hermes, Hindsight, Ollama, SearXNG, Firecrawl, Browserless, Open Terminal) occurs on the isolated bridge network named `ai`.
  - Database services (PostgreSQL / `pgvector`) are isolated on the dedicated bridge network named `db` and must **not** expose ports to the host or attach to the `ai` network. Any service needing database access must connect to the `db` network.
  - Cache services (Valkey, SearXNG, Firecrawl) communicate on the dedicated bridge network named `redis`.
  - Internal backend services (Firecrawl, SearXNG, Valkey, Browserless, PostgreSQL, pgvector) should **not** expose ports to the host or Traefik unless explicitly requested. Proxied web services let Traefik handle routing via container labels.
- **Documentation**: Detailed architecture, configuration, and operational guides for every service reside in [`docs/`](file:///data/homelab/docs/README.md). Always update the corresponding service guide when adding or modifying service configurations.

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
