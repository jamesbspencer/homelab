#!/usr/bin/env bash
# ==============================================================================
# Script: install-docker.sh
# Description: Installs Docker Engine on Ubuntu following the official Docker
#              installation documentation guidelines.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Helper Logging Functions
# ------------------------------------------------------------------------------
log_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

log_warn() {
    echo -e "\033[1;33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
}

# ------------------------------------------------------------------------------
# 2. Help/Usage Menu
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Automated script to install Docker Engine on Ubuntu systems.

Options:
  -h, --help     Show this help menu and exit

Examples:
  sudo ./$(basename "$0")
EOF
    exit 0
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 3. System and Privilege Validation
# ------------------------------------------------------------------------------
# Privilege Check
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be executed with root privileges. Please run with sudo."
    exit 1
fi

# OS Check
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_error "This script is only supported on Ubuntu. Detected OS: ${NAME:-Unknown}"
        exit 1
    fi
else
    log_error "Cannot verify OS distribution: /etc/os-release is missing."
    exit 1
fi

# ------------------------------------------------------------------------------
# 4. Installation Steps
# ------------------------------------------------------------------------------
# Step 1: Remove potentially conflicting packages
log_info "Removing conflicting docker/containerd packages if they exist..."
conflicting_packages=(
    docker.io
    docker-compose
    docker-compose-v2
    docker-doc
    docker-buildx
    podman-docker
    containerd
    runc
)

for pkg in "${conflicting_packages[@]}"; do
    if dpkg -l "$pkg" &>/dev/null; then
        log_info "Removing package: $pkg"
        apt-get remove -y "$pkg" || log_warn "Failed to remove $pkg"
    fi
done

# Step 2: Set up official Docker GPG key
log_info "Setting up Docker's official GPG key..."
apt-get update -qq
apt-get install -y -qq ca-certificates curl

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Step 3: Set up official Docker Apt source (deb822 format)
log_info "Setting up Docker's official Apt source repository..."
tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Step 4: Update package lists and install Docker packages
log_info "Updating Apt package list..."
apt-get update -qq

log_info "Installing Docker Engine and associated plugins..."
apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Step 5: Start and Enable Docker daemon
log_info "Configuring Docker systemd service..."
systemctl daemon-reload
systemctl enable --now docker

# ------------------------------------------------------------------------------
# 5. Verification
# ------------------------------------------------------------------------------
if systemctl is-active --quiet docker; then
    log_success "Docker Engine has been successfully installed and is active!"
    docker --version
    docker compose version
else
    log_error "Docker installation completed, but the Docker service is not running."
    exit 1
fi
