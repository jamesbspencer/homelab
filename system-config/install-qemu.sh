#!/usr/bin/env bash
# ==============================================================================
# Script: install-qemu.sh
# Description: Installs and configures QEMU/KVM and libvirt on Ubuntu systems.
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

Automated script to install and configure QEMU, KVM, and libvirt on Ubuntu.

Options:
  -b, --bridge NAME     Configure the default network to use a host bridge (e.g., br0)
  -d, --image-dir PATH  Custom directory path for the default VM storage pool (default: /var/lib/libvirt/images)
  --nested              Enable nested virtualization configuration (Intel/AMD)
  -h, --help            Show this help menu and exit

Examples:
  sudo ./$(basename "$0")
  sudo ./$(basename "$0") -b br0
  sudo ./$(basename "$0") -d /mnt/storage/vms
  sudo ./$(basename "$0") --nested
EOF
    exit 0
}

# Parse command line options
NESTED_VIRT=false
IMAGE_DIR="/var/lib/libvirt/images"
BRIDGE_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nested)
            NESTED_VIRT=true
            shift
            ;;
        -b|--bridge)
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                BRIDGE_NAME="$2"
                shift 2
            else
                log_error "Option $1 requires a non-empty bridge interface name."
                usage
            fi
            ;;
        -d|--image-dir)
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                IMAGE_DIR="$2"
                shift 2
            else
                log_error "Option $1 requires a non-empty directory path argument."
                usage
            fi
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
# 4. Hardware Virtualization Check
# ------------------------------------------------------------------------------
log_info "Verifying CPU support for hardware virtualization..."
if grep -E -q 'vmx|svm' /proc/cpuinfo; then
    log_success "Hardware virtualization (VT-x/AMD-V) is supported by the CPU."
else
    log_warn "Hardware virtualization (VT-x/AMD-V) does not appear to be supported by the CPU."
    log_warn "Virtual machines might fail to launch or run extremely slowly without KVM acceleration."
fi

# ------------------------------------------------------------------------------
# 5. Enable Nested Virtualization (If Requested)
# ------------------------------------------------------------------------------
enable_nested_virtualization() {
    log_info "Configuring nested virtualization..."
    if grep -q -i "intel" /proc/cpuinfo; then
        log_info "Intel CPU detected."
        if [[ -f /sys/module/kvm_intel/parameters/nested ]]; then
            local nested_status
            nested_status=$(cat /sys/module/kvm_intel/parameters/nested)
            if [[ "$nested_status" == "Y" || "$nested_status" == "1" ]]; then
                log_info "Nested virtualization is already enabled in the kernel module."
                return
            fi
        fi
        echo "options kvm_intel nested=1" | tee /etc/modprobe.d/kvm_intel.conf > /dev/null
        log_success "Configured nested virtualization for Intel."
        log_warn "A reboot or reloading of the KVM module (modprobe -r kvm_intel && modprobe kvm_intel) is required for changes to take effect."
    elif grep -q -i "amd" /proc/cpuinfo; then
        log_info "AMD CPU detected."
        if [[ -f /sys/module/kvm_amd/parameters/nested ]]; then
            local nested_status
            nested_status=$(cat /sys/module/kvm_amd/parameters/nested)
            if [[ "$nested_status" == "1" || "$nested_status" == "Y" ]]; then
                log_info "Nested virtualization is already enabled in the kernel module."
                return
            fi
        fi
        echo "options kvm_amd nested=1" | tee /etc/modprobe.d/kvm_amd.conf > /dev/null
        log_success "Configured nested virtualization for AMD."
        log_warn "A reboot or reloading of the KVM module (modprobe -r kvm_amd && modprobe kvm_amd) is required for changes to take effect."
    else
        log_warn "Unknown CPU vendor. Skipping nested virtualization configuration."
    fi
}

if [[ "$NESTED_VIRT" == true ]]; then
    enable_nested_virtualization
fi

# ------------------------------------------------------------------------------
# 6. Installation
# ------------------------------------------------------------------------------
log_info "Updating Apt package list..."
apt-get update -qq

log_info "Installing QEMU, KVM, and libvirt packages..."
apt-get install -y -qq \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    cpu-checker \
    virtinst

# ------------------------------------------------------------------------------
# 7. User and Group Configuration
# ------------------------------------------------------------------------------
log_info "Configuring group memberships..."
if [[ -n "${SUDO_USER:-}" ]]; then
    log_info "Adding user '$SUDO_USER' to 'libvirt' and 'kvm' groups..."
    usermod -aG libvirt "$SUDO_USER"
    usermod -aG kvm "$SUDO_USER"
    log_success "User '$SUDO_USER' added to libvirt and kvm groups."
    log_warn "Note: You must log out and log back in (or restart your ssh session) for group membership changes to apply."
else
    log_warn "No SUDO_USER detected. Skip adding user to groups."
    log_warn "You can manually add your user with: sudo usermod -aG libvirt,kvm <username>"
fi

# ------------------------------------------------------------------------------
# 8. Service and Configuration Initialization
# ------------------------------------------------------------------------------
log_info "Starting and enabling libvirtd service..."
systemctl daemon-reload
systemctl enable --now libvirtd

# Give libvirtd a few seconds to initialize
log_info "Waiting for libvirt daemon to stabilize..."
for i in {1..5}; do
    if virsh list --all &>/dev/null; then
        break
    fi
    sleep 1
done

# Configure default libvirt network
if [[ -n "$BRIDGE_NAME" ]]; then
    log_info "Configuring default libvirt network as a bridged network on interface '$BRIDGE_NAME'..."
    
    # Check if host bridge exists
    if ! ip link show "$BRIDGE_NAME" &>/dev/null; then
        log_warn "Host bridge interface '$BRIDGE_NAME' does not exist."
        log_warn "You will need to configure '$BRIDGE_NAME' on your Ubuntu host (e.g., via Netplan) for bridging to work."
        log_warn "Example Netplan configuration:"
        cat <<EOF

network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:       # Replace with your physical interface name
      dhcp4: no
      dhcp6: no
  bridges:
    ${BRIDGE_NAME}:
      interfaces: [eth0]
      dhcp4: yes
      parameters:
        stp: true
        forward-delay: 0
EOF
    fi

    # Create temporary XML file for the network definition
    tmp_xml=$(mktemp)
    cat <<EOF > "$tmp_xml"
<network>
  <name>default</name>
  <forward mode='bridge'/>
  <bridge name='${BRIDGE_NAME}'/>
</network>
EOF

    # Stop and undefine existing default network if it exists
    if virsh net-info default &>/dev/null; then
        log_info "Stopping and undefining existing default network..."
        if virsh net-info default | grep -q "Active: *yes"; then
            virsh net-destroy default || true
        fi
        virsh net-undefine default || true
    fi

    # Define and start the new bridged default network
    log_info "Defining new default network using bridge '$BRIDGE_NAME'..."
    virsh net-define "$tmp_xml"
    rm -f "$tmp_xml"
    
    virsh net-autostart default || true
    virsh net-start default || true
    log_success "Default network configured as bridge '$BRIDGE_NAME' and started."
else
    log_info "Configuring default NAT network..."
    if virsh net-info default &>/dev/null; then
        virsh net-autostart default || true
        if ! virsh net-info default | grep -q "Active: *yes"; then
            log_info "Starting default libvirt network..."
            virsh net-start default || true
        fi
        log_success "Default NAT network is active and set to autostart."
    else
        log_warn "Default libvirt network not found. Defining standard NAT network..."
        tmp_xml=$(mktemp)
        cat <<EOF > "$tmp_xml"
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
        virsh net-define "$tmp_xml"
        rm -f "$tmp_xml"
        virsh net-autostart default || true
        virsh net-start default || true
        log_success "Standard NAT default network has been defined, started, and set to autostart."
    fi
fi

# Configure default storage pool
log_info "Configuring default storage pool..."
# Ensure the requested directory exists and has appropriate permissions
mkdir -p "$IMAGE_DIR"
chown root:root "$IMAGE_DIR"
chmod 711 "$IMAGE_DIR"

if virsh pool-info default &>/dev/null; then
    # Default pool exists, let's check its current path
    current_pool_path=$(virsh pool-dumpxml default 2>/dev/null | grep -o '<path>[^<]*</path>' | sed 's|<path>||;s|</path>||' || true)
    
    if [[ "$current_pool_path" != "$IMAGE_DIR" ]]; then
        log_info "Updating default storage pool directory from '$current_pool_path' to '$IMAGE_DIR'..."
        if virsh pool-info default | grep -q "Active: *yes"; then
            virsh pool-destroy default || true
        fi
        virsh pool-undefine default || true
        
        virsh pool-define-as default dir - - - - "$IMAGE_DIR" || true
        virsh pool-build default || true
        virsh pool-start default || true
        virsh pool-autostart default || true
        log_success "Default storage pool has been updated, started, and set to autostart at '$IMAGE_DIR'."
    else
        log_info "Default storage pool is already configured with path '$IMAGE_DIR'."
        virsh pool-autostart default || true
        if ! virsh pool-info default | grep -q "Active: *yes"; then
            log_info "Starting default storage pool..."
            virsh pool-start default || true
        fi
        log_success "Default storage pool is active and set to autostart."
    fi
else
    log_info "Default storage pool not found. Defining default pool at '$IMAGE_DIR'..."
    virsh pool-define-as default dir - - - - "$IMAGE_DIR" || true
    virsh pool-build default || true
    virsh pool-start default || true
    virsh pool-autostart default || true
    log_success "Default storage pool has been defined, started, and set to autostart."
fi

# ------------------------------------------------------------------------------
# 9. Verification
# ------------------------------------------------------------------------------
log_info "Verifying installation status..."
if systemctl is-active --quiet libvirtd; then
    log_success "libvirtd service is active and running!"
else
    log_error "libvirtd service is not running."
    exit 1
fi

if [[ -e /dev/kvm ]]; then
    log_success "KVM device /dev/kvm is available."
else
    log_warn "/dev/kvm is not present. Nested virtualization or KVM kernel modules might not be loaded."
fi

log_success "QEMU/KVM and libvirt setup completed successfully!"
