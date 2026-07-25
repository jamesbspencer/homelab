#!/usr/bin/env bash
# ==============================================================================
# Script: install-portainer.sh
# Description: Automated installer script for Portainer on K3s/Kubernetes
#              using declarative Helmfile (helmfiles/portainer.yaml) with Traefik Ingress.
# ==============================================================================

set -euo pipefail

# Color Output Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Default Options (Ingress with Traefik enabled by default for K3s)
NAMESPACE="portainer"
RELEASE_NAME="portainer"
SERVICE_TYPE="ClusterIP"
ENABLE_INGRESS=true
INGRESS_HOST="portainer.local"
INGRESS_CLASS="traefik"
HTTP_NODEPORT="30777"
HTTPS_NODEPORT="30779"
STORAGE_CLASS=""
EXTRA_HELMFILE_FLAGS=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install or upgrade Portainer Community Edition on K3s/Kubernetes via Helmfile.
Uses K3s default Traefik Ingress Controller by default.

Options:
  -n, --namespace <NAME>       Target Kubernetes namespace (default: portainer)
  --service-type <TYPE>        Service type: ClusterIP, NodePort, or LoadBalancer (default: ClusterIP)
  --ingress-host <DOMAIN>      Ingress host domain name (default: portainer.local)
  --ingress-class <CLASS>      IngressClass name (default: traefik)
  --no-ingress                 Disable Ingress deployment
  --http-nodeport <PORT>       HTTP NodePort when service type is NodePort (default: 30777)
  --https-nodeport <PORT>      HTTPS NodePort when service type is NodePort (default: 30779)
  --storage-class <CLASS>      StorageClass for persistent data (default: cluster default / local-path)
  --extra-flags "<FLAGS>"      Additional flags to pass directly to helmfile apply
  -h, --help                   Show this help message

Examples:
  # Basic installation with default Traefik Ingress (http://portainer.local):
  ./install-portainer.sh

  # Install with custom Ingress hostname:
  ./install-portainer.sh --ingress-host portainer.homelab.local

  # Install using NodePort service type instead of Ingress:
  ./install-portainer.sh --service-type NodePort --no-ingress
EOF
    exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --service-type)
            SERVICE_TYPE="$2"
            shift 2
            ;;
        --ingress-host)
            INGRESS_HOST="$2"
            shift 2
            ;;
        --ingress-class)
            INGRESS_CLASS="$2"
            shift 2
            ;;
        --no-ingress)
            ENABLE_INGRESS=false
            shift
            ;;
        --http-nodeport)
            HTTP_NODEPORT="$2"
            shift 2
            ;;
        --https-nodeport)
            HTTPS_NODEPORT="$2"
            shift 2
            ;;
        --storage-class)
            STORAGE_CLASS="$2"
            shift 2
            ;;
        --extra-flags)
            EXTRA_HELMFILE_FLAGS="$2"
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

setup_kubeconfig() {
    if [[ -z "${KUBECONFIG:-}" ]]; then
        if [[ -f "$HOME/.kube/config" ]]; then
            export KUBECONFIG="$HOME/.kube/config"
        elif [[ -f "/etc/rancher/k3s/k3s.yaml" ]]; then
            log_info "KUBECONFIG not explicitly set. Using /etc/rancher/k3s/k3s.yaml"
            export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        fi
    fi
}

check_dependencies() {
    log_info "Checking cluster connectivity and tool dependencies..."

    setup_kubeconfig

    if ! command -v kubectl &>/dev/null; then
        if command -v k3s &>/dev/null; then
            log_info "kubectl alias not found, using 'k3s kubectl'"
            alias kubectl='k3s kubectl'
        else
            log_error "'kubectl' command line tool not found. Please ensure K3s or kubectl is installed."
            exit 1
        fi
    fi

    if ! kubectl cluster-info &>/dev/null; then
        log_error "Unable to connect to Kubernetes cluster. Verify KUBECONFIG or cluster health."
        exit 1
    fi

    if ! command -v helm &>/dev/null; then
        log_warn "'helm' binary not found in PATH. Attempting automatic installation..."
        if [[ $EUID -ne 0 ]]; then
            log_info "Installing Helm requires sudo privileges..."
            curl -fsSL https://raw.githubusercontent.com/helm/main/scripts/get-helm-3 | sudo bash
        else
            curl -fsSL https://raw.githubusercontent.com/helm/main/scripts/get-helm-3 | bash
        fi
        log_success "Helm installed successfully."
    fi

    if ! command -v helmfile &>/dev/null; then
        log_warn "'helmfile' binary not found in PATH. Attempting automatic installation..."
        local HELMFILE_VER="v0.169.2"
        local ARCH
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64) ARCH="amd64" ;;
            aarch64) ARCH="arm64" ;;
        esac
        
        local TMP_DIR
        TMP_DIR=$(mktemp -d)
        curl -fsSL "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VER}/helmfile_${HELMFILE_VER#v}_linux_${ARCH}.tar.gz" | tar -xz -C "$TMP_DIR"
        
        if [[ $EUID -ne 0 ]]; then
            log_info "Installing helmfile to /usr/local/bin requires sudo..."
            sudo mv "${TMP_DIR}/helmfile" /usr/local/bin/helmfile
            sudo chmod +x /usr/local/bin/helmfile
        else
            mv "${TMP_DIR}/helmfile" /usr/local/bin/helmfile
            chmod +x /usr/local/bin/helmfile
        fi
        rm -rf "$TMP_DIR"
        log_success "Helmfile installed successfully."
    fi
}

install_portainer_helmfile() {
    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local HELMFILE_PATH="${SCRIPT_DIR}/helmfiles/portainer.yaml"

    if [[ ! -f "$HELMFILE_PATH" ]]; then
        log_error "Helmfile not found at ${HELMFILE_PATH}"
        exit 1
    fi

    log_info "Exporting environment variables for Helmfile template rendering..."
    export PORTAINER_SERVICE_TYPE="${SERVICE_TYPE}"
    export PORTAINER_INGRESS_ENABLED="${ENABLE_INGRESS}"
    export PORTAINER_INGRESS_HOST="${INGRESS_HOST}"
    export PORTAINER_INGRESS_CLASS="${INGRESS_CLASS}"
    export PORTAINER_HTTP_NODEPORT="${HTTP_NODEPORT}"
    export PORTAINER_HTTPS_NODEPORT="${HTTPS_NODEPORT}"
    export PORTAINER_STORAGE_CLASS="${STORAGE_CLASS}"

    local HELMFILE_CMD=("helmfile" "-f" "$HELMFILE_PATH" "apply")

    if [[ -n "$EXTRA_HELMFILE_FLAGS" ]]; then
        read -r -a EXTRA_FLAGS_ARR <<< "$EXTRA_HELMFILE_FLAGS"
        HELMFILE_CMD+=("${EXTRA_FLAGS_ARR[@]}")
    fi

    log_info "Applying Portainer Helmfile deployment (${HELMFILE_PATH})..."
    "${HELMFILE_CMD[@]}"

    log_success "Helmfile deployment completed successfully."
}

verify_deployment() {
    log_info "Waiting for Portainer deployment rollout..."
    kubectl rollout status deployment/portainer -n "$NAMESPACE" --timeout=120s || log_warn "Deployment rollout check timed out. Verification continuing..."

    echo ""
    log_success "Portainer installation complete!"
    log_info "Namespace: ${NAMESPACE}"
    log_info "Service Type: ${SERVICE_TYPE}"

    if [[ "$ENABLE_INGRESS" == true ]]; then
        log_info "Traefik Ingress Host: http://${INGRESS_HOST} (IngressClass: ${INGRESS_CLASS})"
    elif [[ "$SERVICE_TYPE" == "NodePort" ]]; then
        log_info "NodePort HTTP Access:  http://<NODE-IP>:${HTTP_NODEPORT}"
        log_info "NodePort HTTPS Access: https://<NODE-IP>:${HTTPS_NODEPORT}"
    elif [[ "$SERVICE_TYPE" == "LoadBalancer" ]]; then
        log_info "Service IP details:"
        kubectl get svc -n "$NAMESPACE" "$RELEASE_NAME"
    fi
}

main() {
    check_dependencies
    install_portainer_helmfile
    verify_deployment
}

main "$@"
