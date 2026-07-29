# Homelab

Homelab GitOps configurations, shell scripts, and infrastructure-as-code automation for managing services on Ubuntu servers.

## Getting Started & Installation Order

To configure your homelab environment from scratch, it is recommended to set up services in the following order:

### 1. System Host Setup
Prepare the underlying virtual machine/container host environments:
- **Docker Engine Setup**: Run [system-config/install-docker.sh](system-config/install-docker.sh) to install Docker and Docker Compose.
- **QEMU/libvirt Setup**: Run [system-config/install-qemu.sh](system-config/install-qemu.sh) to configure QEMU, KVM hypervisor capabilities, networks, and storage pools.

### 2. Core Reverse Proxy & Networking
Launch the core ingress reverse proxy:
- **Traefik Proxy**: Deploy [traefik/docker-compose.yml](traefik/docker-compose.yml) to handle HTTPS certificates and route incoming subdomains.

### 3. Management & Dashboards
Deploy applications and user interfaces:
- **Portainer**: Deploy [portainer/docker-compose.yml](portainer/docker-compose.yml) for container management.
- **Infisical Secrets Manager**: Deploy [infisical/docker-compose.yml](infisical/docker-compose.yml) to manage platform credentials and secrets.
- **Homepage**: Deploy [homepage/docker-compose.yml](homepage/docker-compose.yml) to display the homelab dashboard.

---

## Docker Engine Installer (`system-config/install-docker.sh`)

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
sudo ./system-config/install-docker.sh
```

### Script CLI Options

| Flag | Description |
| --- | --- |
| `-h, --help` | Display the help menu |

---

## QEMU/libvirt Installer (`system-config/install-qemu.sh`)

Automated script to install and configure QEMU/KVM and libvirt on Ubuntu systems.

### Features
- Validates system requirements (supports Ubuntu only and checks for CPU hardware virtualization support).
- Installs QEMU/KVM hypervisor, libvirt daemon, client tools (`virsh`), and VM installer tools (`virt-install`).
- Adds the invoking user to `libvirt` and `kvm` groups for passwordless VM administration.
- Enables and starts the `libvirtd` systemd service automatically.
- Initializes and activates the default network (NAT by default, or bridged if a host bridge is specified).
- Initializes and activates the default VM storage pool (customizable path, defaults to `/var/lib/libvirt/images`).
- Initializes and activates a dedicated VM ISO storage pool (customizable path, defaults to `/var/lib/libvirt/isos`).
- Supports an optional flag to configure nested virtualization.

### Usage Examples

#### Default Installation
```bash
sudo ./system-config/install-qemu.sh
```

#### Install with Bridged Networking
```bash
sudo ./system-config/install-qemu.sh -b br0
```

#### Install with Custom Image and ISO Directories
```bash
sudo ./system-config/install-qemu.sh -d /mnt/storage/vms -i /mnt/storage/isos
```

#### Install with Nested Virtualization
```bash
sudo ./system-config/install-qemu.sh --nested
```

### Script CLI Options

| Flag | Description |
| --- | --- |
| `-b, --bridge NAME` | Configure the default libvirt network to use a host bridge (e.g., `br0`) |
| `-d, --image-dir PATH` | Custom directory path for the default VM storage pool (default: `/var/lib/libvirt/images`) |
| `-i, --iso-dir PATH` | Custom directory path for the VM ISO storage pool (default: `/var/lib/libvirt/isos`) |
| `--nested` | Enable nested virtualization configuration for Intel or AMD processors |
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

---

## Homepage Dashboard (`homepage/docker-compose.yml`)

Docker Compose configuration to deploy the Homepage dashboard.

### Features
- Exposes port `3000` locally.
- Mounts local configuration folder `./config` dynamically to `/app/config`.
- Integrates with the shared `web` network.
- Configures Traefik labels to expose the dashboard dynamically at `${HOMEPAGE_HOST}`.

### Usage Examples

#### Starting Homepage
```bash
cd homepage
docker compose up -d
```

#### Stopping Homepage
```bash
cd homepage
docker compose down
```

---

## Infisical Secrets Manager (`infisical/docker-compose.yml`)

Docker Compose configuration to deploy the Infisical secret management platform.

### Features
- Deploys the Infisical backend service.
- Configures Postgres 14 database for platform storage.
- Configures Redis 7 for caching and session management.
- Uses local directory bind mounts `./db-data` and `./redis-data` for persistence.
- Exposes port `8080` for backend API and dashboard interface.

### Usage Examples

#### Starting Infisical
1. Create and configure the environment variables:
   ```bash
   cp infisical/.env.example infisical/.env
   # Edit infisical/.env and generate keys as instructed
   ```
2. Start the services:
   ```bash
   cd infisical
   docker compose up -d
   ```

#### Stopping Infisical
```bash
cd infisical
docker compose down
```

