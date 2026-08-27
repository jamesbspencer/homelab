# Spencer's Homelab Reverse Proxy, Ollama & Open WebUI Setup

A lightweight, production-grade reverse proxy, LLM runtime, and user interface configuration for a local homelab environment, powered by **Traefik**, **Ollama**, **Open WebUI**, and **Docker Compose**. 

This setup provides:
- **Traefik Reverse Proxy**: Automatic SSL termination using local TLS certificates, dynamic routing based on Docker container labels, and hosts the Traefik dashboard locally.
- **Ollama LLM Server**: Local LLM runner with NVIDIA GPU acceleration enabled.
- **Open WebUI Client**: Premium ChatGPT-style web client interface for interacting with local LLM models, exposed at `https://ai.spencer.lan`.
- **PostgreSQL Database**: Dedicated persistent database configuration for storing Open WebUI data.
- **Open WebUI Terminal (Open Terminal)**: Sandboxed web terminal service for executing command tasks directly inside Open WebUI.
- **SearXNG Search Engine**: Privacy-respecting metasearch engine to give Open WebUI web search integration capabilities.
- **Valkey**: High-performance in-memory key-value data structure store serving as the caching backend for SearXNG.

---

## 🏗️ Architecture Overview

The reverse proxy serves as the single entry point for all HTTP/HTTPS traffic to the homelab:

* **Entrypoints**:
  * **HTTP (`:80`)**: Automatic routing (usually redirected to HTTPS, though not enforced globally here).
  * **HTTPS (`:443`)**: Secured using local TLS certificates.
* **Ollama Service (`:11434`)**:
  * Runs the Ollama server container inside an isolated `ai` network.
  * Configured with GPU pass-through (`nvidia` driver, all GPUs) to accelerate model inference.
  * Mounts local volume `./ollama` to persist downloaded models.
* **PostgreSQL Database (`:5432` internally)**:
  * Runs the Postgres database container inside an isolated `db` network.
  * Mounts local volume `./postgres` to persist database records.
* **Open WebUI Service (`:8080` internally)**:
  * Running web UI client.
  * Joins the `net1` network (for Traefik reverse proxy access), the `ai` network (for ollama/terminal access), and the `db` network (to connect to PostgreSQL).
  * Mounts local volume `./open-webui` to persist user accounts, chat histories, and UI settings.
* **Open Terminal Service (Internal/Sandboxed)**:
  * Runs the Open Terminal container on the `ai` network to provide shell access/sandboxed workspace execution environment for Open WebUI.
  * Configured with CPU (limit: 2, reservation: 0.25) and memory (limit: 2048M, reservation: 512M) resource constraints for safe sandboxing.
  * Mounts local volume `./open-terminal` to persist workspace files.
* **SearXNG Service (Internal/`:8080` internally)**:
  * Privacy-respecting metasearch engine enabling web search capabilities in Open WebUI.
  * Joins the `redis` and `ai` networks.
  * Mounts `./searxng/config/` for settings (using Valkey for caching) and `./searxng/data/` for cache directories.
* **Valkey Service (Internal/`:6379` internally)**:
  * Fast caching service backend for SearXNG.
  * Joins the `redis` network.
  * Mounts local volume `./valkey/data` to persist cache database records.
* **Providers**:
  * **Docker Provider**: Automatically registers and routes services using Docker container labels.
  * **File Provider**: Monitors `traefik/dynamic.yml` for static TLS configuration and internal Traefik routing.
* **Domain Name System (DNS)**:
  * Tailored for local domains ending in `.spencer.lan`.
  * The Traefik Dashboard is exposed at `https://traefik.spencer.lan`.
  * Open WebUI is exposed at `https://ai.spencer.lan`.
* **Networks**:
  * **`net1`**: Dedicated bridge network for Traefik routing to exposed web interfaces.
  * **`ai`**: Dedicated internal bridge network for backend AI and terminal communications.
  * **`db`**: Dedicated isolated bridge network for database traffic.
  * **`redis`**: Dedicated internal bridge network for SearXNG and Valkey communication.

---

## 📁 File Structure

```text
/data/homelab/
├── docker-compose.yaml      # Docker Compose configuration for Traefik, Ollama, Open WebUI, etc.
├── README.md                # System documentation
├── AGENTS.md                # AI Agent guidelines and rules for this workspace
├── .env                     # Environment variables (contains local secrets like WEBUI_SECRET_KEY, POSTGRES_*, etc.)
├── ollama/                  # Local directory for stored LLM models (automatically created)
├── open-terminal/           # Local directory for Open Terminal home folders (automatically created)
├── open-webui/              # Local directory for Open WebUI database/settings (automatically created)
├── postgres/                # Local directory for database records (automatically created)
├── valkey/                  # Local directory for Valkey cache data (automatically created)
├── searxng/                 # Local directory for SearXNG config and cache data
│   ├── config/
│   │   ├── settings.yml     # SearXNG configuration settings (port, secret key, valkey connection)
│   │   └── limiter.toml     # SearXNG bot detection limiter configuration
│   └── data/                # Cache data (automatically created)
└── traefik/
    ├── traefik.yml          # Static Traefik configuration (entrypoints, providers)
    ├── dynamic.yml          # Dynamic Traefik configuration (TLS certificates, local dashboard routing)
    ├── acme.json            # Empty (retained for ACME Let's Encrypt configurations if needed)
    └── certs/
        ├── cert.pem         # SSL Certificate for local *.spencer.lan domains
        └── key.pem          # SSL Private Key for local *.spencer.lan domains
```

---

## ⚙️ Configuration Files

### 1. Docker Compose Configuration
[`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml) defines the Traefik, Ollama, Open WebUI, PostgreSQL db, Open Terminal, Valkey, and SearXNG services. 
- **Traefik** binds ports `80` and `443`.
- **Ollama** exposes port `11434`, mounts the model cache, and requests NVIDIA GPUs on the `ai` network.
- **PostgreSQL (`db`)** runs on its own isolated `db` network.
- **Open WebUI** joins `net1`, `ai`, and `db` networks, exposing its interface via Traefik at `ai.spencer.lan`.
- **Open Terminal** runs on the `ai` network with CPU/memory resource limits to securely process backend terminal tasks.
- **Valkey** runs on the `redis` network as a fast health-checked cache backend.
- **SearXNG** joins the `redis` and `ai` networks, acting as a private metasearch engine backend for Open WebUI web search.

### 2. Static Configuration
[`traefik/traefik.yml`](file:///data/homelab/traefik/traefik.yml) configures basic log levels, entrypoints (`web` and `websecure`), the API/Dashboard dashboard, and enables the Docker and File configuration providers.

### 3. Dynamic Configuration
[`traefik/dynamic.yml`](file:///data/homelab/traefik/dynamic.yml) sets up local TLS certificate registration and configures the router for the internal Traefik API/dashboard, matching the host `traefik.spencer.lan`.

---

## 🚀 Getting Started

### Prerequisites
1. **Docker & Docker Compose**: Ensure Docker and the Compose plugin are installed and running.
2. **NVIDIA Container Toolkit**: Required for the GPU pass-through on the Ollama service.
3. **Local DNS Resolution**: Point `*.spencer.lan` (or at least `traefik.spencer.lan`) to your Docker host's local IP address (e.g., using Pi-hole, AdGuard Home, dnsmasq, or local `/etc/hosts` file).
4. **Local TLS Certificates**: Place your wildcard or domain-specific PEM certificates in `traefik/certs/cert.pem` and `traefik/certs/key.pem`.

### Starting the Services
Run the following command from the root `/data/homelab` directory:
```bash
docker compose up -d
```

### Accessing the Dashboard
Open your browser and navigate to `https://traefik.spencer.lan`.

---

## 📖 How-To Guides

### 1. Exposing a New Service via Traefik
To expose a new Docker container through the reverse proxy, add it to your `docker-compose.yaml` (or create a separate one on the same network) and define Traefik labels.

Here is an Nginx web server example:

```yaml
services:
  my-app:
    image: nginx:alpine
    container_name: my-app
    restart: unless-stopped
    networks:
      - net1
    labels:
      - "traefik.enable=true"
      # Route rule matching your local domain
      - "traefik.http.routers.myapp.rule=Host(`myapp.spencer.lan`)"
      # Define the HTTPS entrypoint
      - "traefik.http.routers.myapp.entrypoints=websecure"
      # Enable TLS termination
      - "traefik.http.routers.myapp.tls=true"
      # Inform Traefik of the port Nginx listens on inside the container
      - "traefik.http.services.myapp.loadbalancer.server.port=80"

networks:
  net1:
    external: true
```

> [!IMPORTANT]
> - Ensure the service joins the external network `net1`.
> - The label `traefik.enable=true` is required because `exposedByDefault` is set to `false` in `traefik.yml`.

### 2. Generating Self-Signed Certificates (Quick Start)
If you don't have existing certificates, you can generate a self-signed wildcard certificate for `.spencer.lan` using OpenSSL:

```bash
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout traefik/certs/key.pem -out traefik/certs/cert.pem \
  -subj "/CN=*.spencer.lan" \
  -addext "subjectAltName=DNS:*.spencer.lan,DNS:spencer.lan"
```

Restart Traefik or let the file provider reload to apply the new certificates.

### 3. Exposing Ollama via Traefik
If you want to route external network requests to Ollama through Traefik instead of direct port exposure, add Traefik labels to the `ollama` service in `docker-compose.yaml`:

```yaml
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ollama.rule=Host(`ollama.spencer.lan`)"
      - "traefik.http.routers.ollama.entrypoints=websecure"
      - "traefik.http.routers.ollama.tls=true"
      - "traefik.http.services.ollama.loadbalancer.server.port=11434"
```

---

## 🛠️ Troubleshooting & Health Checks

### General Troubleshooting
- **Check Container Logs**:
  ```bash
  docker compose logs -f traefik
  docker compose logs -f ollama
  docker compose logs -f open-webui
  docker compose logs -f db
  docker compose logs -f open-terminal
  docker compose logs -f valkey
  docker compose logs -f searxng
  ```
- **Permission Issues on `acme.json`**:
  If using ACME Let's Encrypt, the `acme.json` file must have exact permissions:
  ```bash
  chmod 600 traefik/acme.json
  ```
- **DNS Lookup Failure**:
  Verify DNS resolution by running `ping traefik.spencer.lan` on your local client machine.

### PostgreSQL Verification & Management
Verify that the database is running properly and ready:

- **Check Database Service Health**:
  Ensure the database container status is healthy:
  ```bash
  docker compose ps db
  ```
- **Run Readiness Check**:
  ```bash
  docker compose exec db pg_isready -U openwebui -d openwebui
  ```

### Ollama Verification & Management
You can check the health and manage models in the Ollama service using these commands:

- **Verify Ollama Service Status**:
  Ensure the API server is up and responsive:
  ```bash
  curl http://localhost:11434/
  ```
- **List Installed Models**:
  ```bash
  docker compose exec ollama ollama list
  ```
- **Check Currently Running Models (Loaded in Memory/VRAM)**:
  ```bash
  docker compose exec ollama ollama ps
  ```
- **Verify GPU Detection in Ollama Logs**:
  Ensure Ollama detects the NVIDIA GPU on startup:
  ```bash
  docker compose logs ollama | grep -i -E "gpu|cuda"
  ```
- **Verify GPU inside Container**:
  Check if the NVIDIA GPU is correctly passed through and accessible inside the Ollama container:
  ```bash
  docker exec -it ollama nvidia-smi
  ```
- **Check GPU Status on Host**:
  Run `nvidia-smi` on the host system to verify overall GPU utilization:
  ```bash
  nvidia-smi
  ```
- **Download a New Model**:
  ```bash
  docker compose exec ollama ollama pull llama3
  ```
- **Test Run a Model**:
  ```bash
  docker compose exec ollama ollama run llama3 "Hello, tell me a joke."
  ```
- **Query Installed Models via API**:
  ```bash
  curl http://localhost:11434/api/tags
  ```

### Open Terminal Verification & Management
- **Verify Status**:
  Ensure the open-terminal service is running:
  ```bash
  docker compose ps open-terminal
  ```

### Valkey Verification & Management
- **Check Valkey Health Status**:
  Ensure the container status is healthy:
  ```bash
  docker compose ps valkey
  ```
- **Run Ping Health Check**:
  Test Valkey responsiveness via CLI:
  ```bash
  docker compose exec valkey valkey-cli ping
  ```

### SearXNG Verification & Management
- **Check Container Logs**:
  ```bash
  docker compose logs -f searxng
  ```
- **Verify Status**:
  ```bash
  docker compose ps searxng
  ```
- **Test Web Search API Connectivity**:
  Verify Open WebUI can successfully request search results from SearXNG's JSON endpoint inside the `ai` network:
  ```bash
  docker compose exec open-webui curl "http://searxng:8080/search?q=docker&format=json"
  ```
