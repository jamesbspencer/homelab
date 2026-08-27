# Agent Guidelines for Spencer's Homelab Workspace

This file defines guidelines, rules, and architecture constraints that AI agents must follow when operating in the `/data/homelab` workspace.

---

## 🔍 System Context & Architecture

- **Services**:
  - **Traefik Reverse Proxy**: Single entry point for all HTTP/HTTPS traffic to the homelab.
  - **Ollama**: Local LLM server configured with GPU hardware acceleration.
  - **Open WebUI**: User interface client for interacting with Ollama, serving at `ai.spencer.lan`.
  - **PostgreSQL Database**: Standalone database container configured to run on the dedicated `db` network.
- **Domain Suffix**: All services in this homelab are routed under the local `.spencer.lan` domain (e.g., `traefik.spencer.lan`).
- **Networking**:
  - The Traefik container and proxied services requiring external web access (like Open WebUI) must belong to the bridge network named `net1`.
  - Internal AI communication (e.g., between Open WebUI and Ollama) occurs on the isolated bridge network named `ai`.
  - Database services (like PostgreSQL) should be isolated on a dedicated bridge network named `db` and must **not** expose ports to the host.
  - Proxied services should **not** expose ports to the host directly. Instead, expose them internally and let Traefik handle routing via container labels.

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
