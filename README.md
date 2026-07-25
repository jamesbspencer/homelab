# Homelab

Home Lab GitOps & Automation Scripts.

## K3s Ubuntu Installer (`install-k3s.sh`)

Automated script to set up K3s lightweight Kubernetes cluster on Ubuntu systems.

### Features
- Configures prerequisites (`curl`, `ca-certificates`, `iptables`, `nfs-common`, `open-iscsi`).
- Supports **Server** (control-plane) and **Agent** (worker) installation modes.
- Configures non-root user `~/.kube/config` permissions and `KUBECONFIG` environment variable automatically when run with `sudo`.
- Option to disable default Traefik Ingress or ServiceLB (for custom ingress controllers such as Cilium or NGINX).
- Automatically provisions node-local PersistentVolume (`local-storage`) and PVC using `manifests/local-pv.yaml`.
- Verifies installation status and displays the cluster node token upon completion.

### Usage Examples

#### 1. Standalone Server Installation (Control Plane)
```bash
sudo ./install-k3s.sh
```

#### 2. Server Installation without Default Traefik Ingress
```bash
sudo ./install-k3s.sh --disable-traefik
```

#### 3. Agent (Worker) Node Installation
```bash
sudo ./install-k3s.sh --mode agent --server https://<SERVER-IP>:6443 --token <CLUSTER-TOKEN>
```

### Script CLI Options

| Flag | Description |
| --- | --- |
| `--mode <server\|agent>` | Installation mode (default: `server`) |
| `--version <VERSION>` | Pin to a specific K3s version tag (e.g. `v1.30.2+k3s1`) |
| `--server <URL>` | Target K3s server URL (required for agent mode) |
| `--token <TOKEN>` | Cluster join token (required for agent mode) |
| `--disable-traefik` | Disable bundled Traefik Ingress Controller |
| `--disable-servicelb` | Disable bundled Klipper ServiceLB |
| `--no-kubeconfig` | Skip non-root user `~/.kube/config` setup |
| `--no-storage-deps` | Skip installing NFS and iSCSI storage utilities |
| `--no-local-pv` | Skip automatic local PersistentVolume & StorageClass creation |
| `--local-pv-path <PATH>` | Host directory path for local PV (default: `/mnt/k8s-data`) |
| `--extra-args "<ARGS>"` | Pass extra arguments directly to K3s installer |
| `-h, --help` | Display help menu |

---

## Portainer Helm Installer (`install-portainer.sh`)

Automated script to install or upgrade [Portainer Community Edition](https://www.portainer.io/) on K3s/Kubernetes using the official Helm chart.

### Features
- Auto-detects K3s `KUBECONFIG` (`~/.kube/config` or `/etc/rancher/k3s/k3s.yaml`).
- Auto-installs `helm` and `helmfile` binaries if missing on the system.
- Pre-configured with **Traefik Ingress** enabled by default (`portainer.local`).
- Uses declarative `helmfiles/portainer.yaml` execution (`helmfile apply`).

### Usage Examples

#### 1. Default Installation with Traefik Ingress (http://portainer.local)
```bash
./install-portainer.sh
```

#### 2. Custom Ingress Hostname
```bash
./install-portainer.sh --ingress-host portainer.homelab.local
```

#### 3. NodePort Service Type (No Ingress)
```bash
./install-portainer.sh --service-type NodePort --no-ingress
```

### Script CLI Options

| Flag | Description |
| --- | --- |
| `-n, --namespace <NAME>` | Target Kubernetes namespace (default: `portainer`) |
| `--service-type <TYPE>` | Service type: `ClusterIP`, `NodePort`, or `LoadBalancer` (default: `ClusterIP`) |
| `--ingress-host <DOMAIN>` | Domain name for Kubernetes Ingress (default: `portainer.local`) |
| `--ingress-class <CLASS>` | IngressClass name (default: `traefik`) |
| `--no-ingress` | Disable Ingress resource creation |
| `--http-nodeport <PORT>` | HTTP NodePort when service type is `NodePort` (default: `30777`) |
| `--https-nodeport <PORT>` | HTTPS NodePort when service type is `NodePort` (default: `30779`) |
| `--storage-class <CLASS>` | StorageClass for persistent data PVC |
| `--extra-flags "<FLAGS>"` | Custom flags passed to `helmfile apply` |
| `-h, --help` | Display help menu |

### Declarative Deployment with Helmfile (`helmfiles/portainer.yaml`)

Declarative Helmfile deployment for GitOps workflows.

#### Usage
```bash
# Standard sync
helmfile -f helmfiles/portainer.yaml sync

# Or apply changes
helmfile -f helmfiles/portainer.yaml apply

# Environment variable overrides example:
PORTAINER_SERVICE_TYPE=LoadBalancer helmfile -f helmfiles/portainer.yaml apply
```

---

## Kubernetes Manifests

### Local Persistent Volume (`manifests/local-pv.yaml`)

Defines a `StorageClass`, node-local `PersistentVolume` (PV), and `PersistentVolumeClaim` (PVC) for binding local host paths to workloads.

#### Usage
1. Ensure the directory path exists on your host node:
   ```bash
   sudo mkdir -p /mnt/k8s-data
   ```
2. Apply the manifest to your cluster:
   ```bash
   kubectl apply -f manifests/local-pv.yaml
   ```


