# Traefik Reverse Proxy

Traefik acts as the centralized edge router and reverse proxy for all inbound HTTP/HTTPS traffic to Spencer's Homelab.

---

## 🎯 Overview & Architecture

* **Role**: Single entry point for routing external and LAN requests to internal Docker containers based on host headers (`*.spencer.lan`).
* **Container Name**: `traefik`
* **Image**: `traefik:latest`
* **Network**: `net1` (Bridge network for routed web services)
* **Bound Host Ports**: `80:80` (HTTP), `443:443` (HTTPS)
* **Web UI / Dashboard**: `https://traefik.spencer.lan`

```mermaid
graph LR
    Client([Client Browser]) -->|HTTP :80 / HTTPS :443| Traefik
    Traefik -->|ai.spencer.lan| OpenWebUI[Open WebUI :8080]
    Traefik -->|hermes.spencer.lan| HermesGateway[Hermes Gateway :8642]
    Traefik -->|hermes-dashboard.spencer.lan| HermesDash[Hermes Dashboard :9119]
    Traefik -->|traefik.spencer.lan| TraefikDash[Traefik Dashboard]
```

---

## ⚙️ Configuration

Traefik uses a dual-configuration approach:

### 1. Static Configuration (`traefik/traefik.yml`)
Configures global entrypoints, API/Dashboard enablement, logging, and provider declarations:
* **Entrypoints**:
  * `web` on `:80`
  * `websecure` on `:443`
* **Providers**:
  * `docker`: Watches Docker socket for container labels (`exposedByDefault: false`).
  * `file`: Dynamically watches `traefik/dynamic.yml` (`watch: true`).

> [!IMPORTANT]
> Changes to `traefik/traefik.yml` require a container restart:
> ```bash
> docker compose up -d --force-recreate traefik
> ```

### 2. Dynamic Configuration (`traefik/dynamic.yml`)
Configures dynamic TLS certificates and internal dashboard routing:
* **TLS Certificates**: Loads wildcard certificates from `traefik/certs/cert.pem` and `traefik/certs/key.pem`.
* **Dashboard Router**: Routes `traefik.spencer.lan` to internal `api@internal` service.

---

## 📁 Mounted Volumes

| Host Path | Container Path | Purpose | Access |
|---|---|---|---|
| `./traefik/traefik.yml` | `/etc/traefik/traefik.yml` | Static configuration | Read/Write |
| `./traefik/dynamic.yml` | `/etc/traefik/dynamic.yml` | Dynamic configuration & TLS | Read/Write |
| `./traefik/acme.json` | `/etc/traefik/acme.json` | ACME storage (permissions 600) | Read/Write |
| `./traefik/certs` | `/etc/traefik/certs` | Wildcard TLS certificates | Read-Only |
| `/var/run/docker.sock` | `/var/run/docker.sock` | Docker provider event socket | Read-Only |

---

## 🏷️ Service Registration Example

To expose any container via Traefik:
```yaml
services:
  my-service:
    image: my-service:latest
    networks:
      - net1
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.my-service.rule=Host(`myservice.spencer.lan`)"
      - "traefik.http.routers.my-service.entrypoints=websecure"
      - "traefik.http.routers.my-service.tls=true"
      - "traefik.http.services.my-service.loadbalancer.server.port=8080"
```
