# Homelab

Home Lab GitOps & Automation Scripts.

## Docker Engine Installer (`install-docker.sh`)

Automated script to set up Docker Engine on Ubuntu systems following the official Docker installation documentation.

### Features
- Validates system requirements (supports Ubuntu only).
- Removes potentially conflicting legacy packages (`docker.io`, `containerd`, etc.) if present.
- Configures Docker's official GPG key and the official `deb822` repository.
- Installs the latest stable Docker Engine, CLI, and modern plugins (`docker-buildx-plugin`, `docker-compose-plugin`).
- Enables and starts the Docker systemd service automatically.

### Usage Examples

#### Default Installation
```bash
sudo ./install-docker.sh
```

### Script CLI Options

| Flag | Description |
| --- | --- |
| `-h, --help` | Display the help menu |

---

## Portainer CE Deployment (`portainer/docker-compose.yml`)

Docker Compose configuration to deploy Portainer Community Edition (CE).

### Features
- Deploys the Portainer CE container (`lts` tag).
- Uses a local directory bind mount (`./data:/data`) for persistent data storage.
- Auto-starts on boot using the `always` restart policy.
- Exposes port `9443` for secure HTTPS management and port `8000` for the optional TCP agent tunnel.

### Usage Examples

#### Starting Portainer
```bash
cd portainer
docker compose up -d
```

#### Stopping Portainer
```bash
cd portainer
docker compose down
```

---

## Traefik Reverse Proxy (`traefik/docker-compose.yml`)

Docker Compose configuration to deploy the Traefik v3 reverse proxy.

### Features
- Exposes port `80` for HTTP, `443` for HTTPS, and `8080` for the dashboard.
- Monitors the Docker socket to auto-discover containers with routing labels.
- Automatically creates the `web` bridge network to connect other services (like Portainer).
- Preconfigured directory bind mount `./letsencrypt:/letsencrypt` for SSL certificates.

### Usage Examples

#### Starting Traefik
```bash
cd traefik
docker compose up -d
```

#### Stopping Traefik
```bash
cd traefik
docker compose down
```

