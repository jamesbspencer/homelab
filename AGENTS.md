# Agent Guidelines for Spencer's Homelab Workspace

This file defines guidelines, rules, and architecture constraints that AI agents must follow when operating in the `/data/homelab` workspace.

---

## 🔍 System Context & Architecture

- **Services**:
  - **Traefik Reverse Proxy**: Single entry point for all HTTP/HTTPS traffic to the homelab (`traefik.spencer.lan`).
  - **Ollama**: Local LLM server configured with NVIDIA GPU hardware acceleration.
  - **MoMoE**: Hybrid Mixture-of-Experts (MoE) LLM inference engine combining GPU VRAM and host RAM/AVX-512 on internal port `8080` (accessible via OmniRoute).
  - **OmniRoute AI Gateway**: Universal AI gateway, OpenAI/Anthropic model router, prompt compressor, and rate limiter on internal port `20128` and `llm.spencer.lan`.
  - **Open WebUI**: Multi-model generative AI chat interface and conversational memory client on internal port `8080` (`chat.spencer.lan`, `ai.spencer.lan`) with OmniRoute embedding offload and unified pgvector database.
  - **Firecrawl Stack**: Web scraping, crawling, and search cluster (`firecrawl`, `rabbitmq`, `nuq-postgres`, `playwright-service`) on internal port `3002`.
  - **SearXNG**: Privacy-respecting metasearch engine providing JSON search endpoints on internal port `8080`.
  - **Valkey**: High-performance in-memory key-value cache and rate limiter on internal port `6379`.
  - **CrowdSec & Traefik Bouncer**: Intrusion detection and prevention engine parsing Traefik access logs with in-memory stream mode enforcement via the Traefik bouncer plugin.
  - **Authentik**: Centralized identity provider, single sign-on (SSO), OIDC/SAML provider, and visual flow engine (`sso.spencer.lan`, `login.spencer.lan`) protecting internal dashboards via Traefik ForwardAuth Outpost.
  - **Dozzle**: Lightweight real-time container log viewer and streaming server (`logs.spencer.lan`, `dozzle.spencer.lan`) protected by Authentik ForwardAuth.
  - **ntfy**: Lightweight push notification gateway and alert broker on internal port `80` (`push.spencer.lan`, `ntfy.spencer.lan`) with dual-router Authentik ForwardAuth for Web UI and direct API/mobile bypass.
  - **OpenBao**: Open-source identity-based secrets and encryption management server on internal port `8200` (`vault.spencer.lan`, `openbao.spencer.lan`) with Raft transactional storage.
  - **Gitea**: Self-hosted lightweight Git platform and repository manager on internal port `3000` (`git.spencer.lan`, `gitea.spencer.lan`) with Git SSH on port `2222` and Authentik OIDC integration.
  - **Homepage**: Centralized homelab dashboard, service status monitor, and launch directory on internal port `3000` (`home.spencer.lan`, `homepage.spencer.lan`) protected by Authentik ForwardAuth.
  - **PostgreSQL Database (`pgvector`)**: Unified relational and vector database container configured on the isolated `db` network for Open WebUI, Authentik, and Gitea.
- **Domain Suffix**: All services in this homelab are routed under the local `.spencer.lan` domain (e.g., `traefik.spencer.lan`, `sso.spencer.lan`, `login.spencer.lan`, `chat.spencer.lan`, `ai.spencer.lan`, `llm.spencer.lan`, `logs.spencer.lan`, `dozzle.spencer.lan`, `push.spencer.lan`, `ntfy.spencer.lan`, `vault.spencer.lan`, `openbao.spencer.lan`, `git.spencer.lan`, `gitea.spencer.lan`, `home.spencer.lan`, `homepage.spencer.lan`).
- **Networking**:
  - The Traefik container and proxied services requiring external web access (Open WebUI, OmniRoute, Authentik Server, Dozzle, ntfy, OpenBao, Gitea, Homepage) as well as the CrowdSec Local API engine must belong to the bridge network named `net1`.
  - Internal AI communication (between Open WebUI, OmniRoute, Ollama, MoMoE, OpenBao, SearXNG, Firecrawl, ntfy, Gitea, Homepage) occurs on the isolated bridge network named `ai`.
  - Database services (`pgvector`) are isolated on the dedicated bridge network named `db` and must **not** expose ports to the host or attach to the `ai` network. Any service needing database access must connect to the `db` network (Open WebUI, Authentik, Gitea).
  - Cache services (Valkey, OmniRoute, SearXNG, Firecrawl, Authentik sessions & queue, Gitea cache & queue) communicate on the dedicated bridge network named `redis`.
  - Internal backend services (Firecrawl, SearXNG, Valkey, pgvector, MoMoE) should **not** expose ports to the host or Traefik unless explicitly requested. Proxied web services let Traefik handle routing via container labels.
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

### 6. Information Gathering & Inspection Hierarchy
- When researching service capabilities, schemas, environment variables, or debugging issues, agents **must prioritize information sources in the following order**:
  1. **Service APIs**: Query service REST/OpenAPI endpoints, discovery metadata, and health/introspection APIs.
  2. **Local Documentation**: Check workspace architecture and service guides in [`docs/`](file:///data/homelab/docs/README.md) and configuration files.
  3. **Online Documentation & Web Search**: Consult official product and vendor documentation (e.g., OmniRoute, Authentik, Traefik docs) via web search or public docs.
  4. **Container Code as Last Resort Only**: Do **not** inspect or grep through application code inside running containers (`docker exec ...`) unless APIs and documentation have been thoroughly exhausted.

### 7. Documentation Synchronization & Root Markdown Maintenance
- **Root Markdown Files Integrity**: Whenever adding, modifying, removing, or refactoring services, configurations, or architecture in `/data/homelab`, AI agents **must** keep the root markdown files up to date with recent changes:
  - [`README.md`](file:///data/homelab/README.md): Keep the service directory table, the Mermaid architecture diagram, the repository file tree, and operational health checks aligned with active services.
  - [`CHANGELOG.md`](file:///data/homelab/CHANGELOG.md): Record date-based entries (`[YYYY-MM-DD]`) detailing added, changed, deprecated, or removed services and configurations.
  - [`TODO.md`](file:///data/homelab/TODO.md): Check off completed initiatives and register newly identified maintenance tasks or roadmap items.
  - [`AGENTS.md`](file:///data/homelab/AGENTS.md): Keep the system context, service catalog, network boundaries, and operational rules synchronized.
  - [`docs/`](file:///data/homelab/docs/README.md): Update the corresponding service guide and ensure the `docs/README.md` index reflects all deployed components.

### 8. Strict Credential, Privacy & Network Sanitization (Zero-Leak Policy)
- **Zero-Leak Guarantee**: Never commit or stage real credentials, secrets, tokens, passwords, private keys, personally identifiable usernames (PII), or sensitive internal IP addresses to version control or code files.
- **Environment Parameterization**: Always enforce environment variables (`${VAR_NAME}`) and placeholder templates in `.env.example` (`your_secret_here`, `example.com`).
- **Pre-Commit Audit**:
  - Always execute pre-commit diff inspections (`git diff`, `git status`) to verify that no sensitive keys, private data, or real secrets have leaked into tracked files.
  - Ensure `.gitignore` explicitly excludes all local secret files (`.env`, `.env.passwords`, `.bws`, keys, certs, token caches, large binary weights, and runtime databases).
- **Network & Identity Privacy**:
  - Mask or parameterize specific internal IP addresses (e.g., replace `192.168.x.x` or specific private subnets with standardized domain aliases, localhost, or environment variables).
  - Strip personal machine usernames, absolute home paths with personal identifiers, and private account credentials from public code and commits.

