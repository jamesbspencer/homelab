#!/usr/bin/env bash
# ==============================================================================
# Script: install-k3s.sh
# Description: Automated K3s installer script for Ubuntu systems.
# Supports single-node server, HA control-plane, and worker (agent) nodes.
# ==============================================================================

set -euo pipefail

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Default flags and options
MODE="server"
K3S_VERSION=""
K3S_TOKEN=""
K3S_URL=""
DISABLE_TRAEFIK=false
DISABLE_SERVICELB=false
SETUP_KUBECONFIG=true
INSTALL_STORAGE_DEPS=true
CREATE_LOCAL_PV=true
LOCAL_PV_PATH="/mnt/k8s-data"
EXTRA_ARGS=""

usage() {
    cat <<EOF
Usage: sudo $(basename "$0") [OPTIONS]

K3s Automated Installation Script for Ubuntu

Options:
  --mode <server|agent>      Installation mode (default: server)
  --version <VERSION>        Specific K3s version (e.g., v1.30.2+k3s1)
  --server <URL>             K3s server URL (required for agent mode, e.g., https://192.168.1.50:6443)
  --token <TOKEN>            K3s cluster join token (required for agent mode)
  --disable-traefik          Disable bundled Traefik ingress controller
  --disable-servicelb        Disable bundled ServiceLB (Klipper) load balancer
  --no-kubeconfig            Skip configuring local ~/.kube/config for non-root user
  --no-storage-deps          Skip installing NFS and iSCSI storage utilities (nfs-common, open-iscsi)
  --no-local-pv              Skip creating local PersistentVolume and StorageClass
  --local-pv-path <PATH>     Host directory path for local PV (default: /mnt/k8s-data)
  --extra-args "<ARGS>"      Pass additional CLI flags directly to K3s installer
  -h, --help                 Show this help message

Examples:
  # Install standard standalone K3s server with local PV:
  sudo ./install-k3s.sh

  # Install server without Traefik (e.g. for custom ingress like NGINX or Cilium):
  sudo ./install-k3s.sh --disable-traefik

  # Join worker node to existing server:
  sudo ./install-k3s.sh --mode agent --server https://192.168.1.100:6443 --token MY_SECRET_TOKEN
EOF
    exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --version)
            K3S_VERSION="$2"
            shift 2
            ;;
        --server)
            K3S_URL="$2"
            shift 2
            ;;
        --token)
            K3S_TOKEN="$2"
            shift 2
            ;;
        --disable-traefik)
            DISABLE_TRAEFIK=true
            shift
            ;;
        --disable-servicelb)
            DISABLE_SERVICELB=true
            shift
            ;;
        --no-kubeconfig)
            SETUP_KUBECONFIG=false
            shift
            ;;
        --no-storage-deps)
            INSTALL_STORAGE_DEPS=false
            shift
            ;;
        --no-local-pv)
            CREATE_LOCAL_PV=false
            shift
            ;;
        --local-pv-path)
            LOCAL_PV_PATH="$2"
            shift 2
            ;;
        --extra-args)
            EXTRA_ARGS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo privilege."
        exit 1
    fi
}

check_ubuntu() {
    log_info "Checking system distribution..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"ubuntu"* ]]; then
            log_warn "This script is tailored for Ubuntu. Detected OS: ${PRETTY_NAME:-Unknown}"
        else
            log_info "Detected OS: ${PRETTY_NAME}"
        fi
    else
        log_warn "Unable to verify OS from /etc/os-release."
    fi
}

validate_inputs() {
    if [[ "$MODE" != "server" && "$MODE" != "agent" ]]; then
        log_error "Invalid mode '$MODE'. Must be 'server' or 'agent'."
        exit 1
    fi

    if [[ "$MODE" == "agent" ]]; then
        if [[ -z "$K3S_URL" ]]; then
            log_error "--server URL is required for agent mode."
            exit 1
        fi
        if [[ -z "$K3S_TOKEN" ]]; then
            log_error "--token is required for agent mode."
            exit 1
        fi
    fi
}

install_prerequisites() {
    log_info "Installing system prerequisites..."
    apt-get update -qq

    local PKGS=("curl" "ca-certificates" "iptables")
    if [[ "$INSTALL_STORAGE_DEPS" == true ]]; then
        PKGS+=("nfs-common" "open-iscsi")
    fi

    apt-get install -y -qq "${PKGS[@]}"

    if [[ "$INSTALL_STORAGE_DEPS" == true ]]; then
        systemctl enable --now iscsid || true
    fi
}

configure_k3s_args() {
    local K3S_EXEC_ARGS=""

    if [[ "$MODE" == "server" ]]; then
        if [[ "$DISABLE_TRAEFIK" == true ]]; then
            K3S_EXEC_ARGS="$K3S_EXEC_ARGS --disable traefik"
        fi
        if [[ "$DISABLE_SERVICELB" == true ]]; then
            K3S_EXEC_ARGS="$K3S_EXEC_ARGS --disable servicelb"
        fi
    fi

    if [[ -n "$EXTRA_ARGS" ]]; then
        K3S_EXEC_ARGS="$K3S_EXEC_ARGS $EXTRA_ARGS"
    fi

    export INSTALL_K3S_EXEC="${K3S_EXEC_ARGS# }"
}

install_k3s() {
    log_info "Running official K3s installer in ${MODE} mode..."

    export K3S_TOKEN="${K3S_TOKEN}"
    export K3S_URL="${K3S_URL}"

    if [[ -n "$K3S_VERSION" ]]; then
        export INSTALL_K3S_VERSION="$K3S_VERSION"
    fi

    if [[ "$MODE" == "agent" ]]; then
        curl -sfL https://get.k3s.io | K3S_URL="${K3S_URL}" K3S_TOKEN="${K3S_TOKEN}" sh -s - agent
    else
        curl -sfL https://get.k3s.io | sh -s -
    fi

    log_success "K3s installation completed successfully."
}

configure_user_kubeconfig() {
    if [[ "$MODE" != "server" || "$SETUP_KUBECONFIG" != true ]]; then
        return
    fi

    local TARGET_USER="${SUDO_USER:-}"
    if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
        log_info "Running directly as root user. Skipping user-level ~/.kube/config setup."
        return
    fi

    local USER_HOME
    USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

    if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
        log_warn "Home directory for '$TARGET_USER' not found. Skipping kubeconfig user copy."
        return
    fi

    log_info "Configuring kubectl config for user '$TARGET_USER'..."

    local KUBE_DIR="${USER_HOME}/.kube"
    mkdir -p "$KUBE_DIR"
    cp /etc/rancher/k3s/k3s.yaml "${KUBE_DIR}/config"
    chown -R "${TARGET_USER}:${TARGET_USER}" "$KUBE_DIR"
    chmod 600 "${KUBE_DIR}/config"

    local BASHRC="${USER_HOME}/.bashrc"
    if [[ -f "$BASHRC" ]] && ! grep -q "KUBECONFIG" "$BASHRC"; then
        echo 'export KUBECONFIG=~/.kube/config' >> "$BASHRC"
        chown "${TARGET_USER}:${TARGET_USER}" "$BASHRC"
    fi

    log_success "Kubeconfig written to ${KUBE_DIR}/config with appropriate permissions."
}

setup_local_persistent_volume() {
    if [[ "$MODE" != "server" || "$CREATE_LOCAL_PV" != true ]]; then
        return
    fi

    log_info "Setting up local PersistentVolume..."

    # Ensure local directory exists on host
    mkdir -p "$LOCAL_PV_PATH"

    local CURRENT_HOSTNAME
    CURRENT_HOSTNAME=$(hostname)

    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local MANIFEST_FILE="${SCRIPT_DIR}/manifests/local-pv.yaml"

    if [[ -f "$MANIFEST_FILE" ]]; then
        log_info "Applying local PV manifest from '${MANIFEST_FILE}' for host '${CURRENT_HOSTNAME}'..."
        sed "s/ubuntu/${CURRENT_HOSTNAME}/g" "$MANIFEST_FILE" | sed "s|/mnt/k8s-data|${LOCAL_PV_PATH}|g" | k3s kubectl apply -f -
        log_success "Local PersistentVolume and PVC applied successfully."
    else
        log_info "Applying inline local PV manifest..."
        cat <<EOF | k3s kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-data
  labels:
    type: local
    app: homelab
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: ${LOCAL_PV_PATH}
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - ${CURRENT_HOSTNAME}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-pvc-data
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  resources:
    requests:
      storage: 10Gi
EOF
        log_success "Local PersistentVolume applied successfully."
    fi
}

verify_installation() {
    log_info "Verifying K3s service status..."

    local SERVICE_NAME="k3s"
    if [[ "$MODE" == "agent" ]]; then
        SERVICE_NAME="k3s-agent"
    fi

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service '${SERVICE_NAME}' is active and running."
    else
        log_warn "Service '${SERVICE_NAME}' is starting up or inactive. Check with: systemctl status ${SERVICE_NAME}"
    fi

    if [[ "$MODE" == "server" ]]; then
        log_info "Checking node status..."
        sleep 3
        if k3s kubectl get nodes; then
            echo ""
            log_success "K3s cluster is online."
            if [[ -f /etc/rancher/k3s/server/node-token ]]; then
                echo -e "${BLUE}Cluster Node Token:${NC} $(cat /etc/rancher/k3s/server/node-token)"
            fi
        fi
    fi
}

main() {
    check_root
    check_ubuntu
    validate_inputs
    install_prerequisites
    configure_k3s_args
    install_k3s
    configure_user_kubeconfig
    verify_installation
    setup_local_persistent_volume
}

main "$@"
