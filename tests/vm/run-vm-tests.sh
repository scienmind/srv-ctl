#!/bin/bash
# Run integration tests in a QEMU VM
# Provides complete isolation with full systemd, network stack, etc.

set -euo pipefail

OS_VERSION="${1:-ubuntu-22.04}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CACHE_DIR="${HOME}/.cache/vm-images"
RESULTS_DIR="$SCRIPT_DIR/results"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_step() {
    echo -e "${YELLOW}[STEP]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    local missing=()
    
    command -v qemu-system-x86_64 &>/dev/null || missing+=("qemu-system-x86_64")
    command -v qemu-img &>/dev/null || missing+=("qemu-img")
    command -v cloud-localds &>/dev/null || missing+=("cloud-localds (cloud-image-utils)")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Install with: sudo apt-get install qemu-system-x86 qemu-utils cloud-image-utils"
        exit 1
    fi
}

# Create cloud-init configuration
create_cloud_init() {
    local work_dir="$1"
    
    cat > "$work_dir/user-data" << 'EOF'
#cloud-config
users:
  - name: testuser
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC srv-ctl-test

packages:
  - cryptsetup
  - lvm2
  - dosfstools
  - ntfs-3g
  - exfat-fuse
  - exfatprogs
  - cifs-utils
  - nfs-common
  - curl

runcmd:
  - systemctl enable systemd-networkd
  - systemctl start systemd-networkd

write_files:
  - path: /etc/ssh/sshd_config.d/test.conf
    content: |
      PermitRootLogin yes
      PasswordAuthentication yes
    permissions: '0644'

final_message: "VM ready for testing"
EOF

    cat > "$work_dir/meta-data" << EOF
instance-id: srv-ctl-test-${OS_VERSION}
local-hostname: srv-ctl-test
EOF

    cloud-localds "$work_dir/cloud-init.img" "$work_dir/user-data" "$work_dir/meta-data"
}

# Create test VM disk
create_vm_disk() {
    local work_dir="$1"
    local base_image="$CACHE_DIR/${OS_VERSION}.qcow2"
    
    if [[ ! -f "$base_image" ]]; then
        log_error "Base image not found: $base_image"
        log_info "Run: ./tests/vm/download-image.sh $OS_VERSION"
        exit 1
    fi
    
    # Create overlay disk (doesn't modify base image)
    qemu-img create -f qcow2 -b "$base_image" -F qcow2 "$work_dir/disk.qcow2" 20G
    
    # Create additional disk for storage tests
    qemu-img create -f qcow2 "$work_dir/test-disk.qcow2" 500M
}

# Start VM
start_vm() {
    local work_dir="$1"
    
    log_step "Starting VM..."
    
    qemu-system-x86_64 \
        -name "srv-ctl-test-${OS_VERSION}" \
        -machine type=q35,accel=kvm \
        -cpu host \
        -m 2048 \
        -smp 2 \
        -drive file="$work_dir/disk.qcow2",if=virtio,format=qcow2 \
        -drive file="$work_dir/test-disk.qcow2",if=virtio,format=qcow2 \
        -drive file="$work_dir/cloud-init.img",if=virtio,format=raw \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -nographic \
        -pidfile "$work_dir/qemu.pid" \
        -daemonize
    
    # Wait for SSH to be available
    log_info "Waiting for VM to boot..."
    local max_wait=120
    local waited=0
    
    while ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
              -p 2222 testuser@localhost "echo VM ready" &>/dev/null; do
        sleep 2
        waited=$((waited + 2))
        if [[ $waited -ge $max_wait ]]; then
            log_error "VM failed to boot within ${max_wait}s"
            return 1
        fi
    done
    
    log_info "VM booted successfully"
}

# Copy project to VM and run tests
run_tests_in_vm() {
    local work_dir="$1"
    
    log_step "Copying project to VM..."
    
    # Create tarball of project
    tar -czf "$work_dir/srv-ctl.tar.gz" -C "$PROJECT_ROOT" \
        --exclude='.git' \
        --exclude='*.qcow2' \
        --exclude='results' \
        .
    
    # Copy to VM
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -P 2222 "$work_dir/srv-ctl.tar.gz" testuser@localhost:/tmp/
    
    log_step "Running tests in VM..."
    
    # Run tests via SSH
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p 2222 testuser@localhost bash << 'EOSSH'
set -euo pipefail

# Extract project
cd /tmp
tar -xzf srv-ctl.tar.gz
cd /tmp

# Setup test config
cp tests/fixtures/config.local.test config.local

# Make scripts executable
chmod +x srv-ctl.sh
chmod +x tests/run-tests.sh
chmod +x tests/integration/*.sh
chmod +x tests/fixtures/*.sh
chmod +x tests/e2e/*.sh

# Install bats
curl -sSL https://github.com/bats-core/bats-core/archive/v1.10.0.tar.gz | tar -xz
cd bats-core-1.10.0
sudo ./install.sh /usr/local
cd /tmp

# Run all test phases
echo "========================================="
echo "Running full test suite in VM"
echo "OS: $(lsb_release -ds)"
echo "Kernel: $(uname -r)"
echo "========================================="
echo ""

sudo ./tests/run-tests.sh --all

EOSSH
    
    local exit_code=$?
    
    # Copy results back
    mkdir -p "$RESULTS_DIR"
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -P 2222 -r testuser@localhost:/tmp/test-results/* "$RESULTS_DIR/" 2>/dev/null || true
    
    return $exit_code
}

# Cleanup VM
cleanup_vm() {
    local work_dir="$1"
    
    if [[ -f "$work_dir/qemu.pid" ]]; then
        local pid=$(cat "$work_dir/qemu.pid")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping VM (PID: $pid)..."
            kill "$pid"
            # Wait for graceful shutdown
            sleep 5
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    
    rm -rf "$work_dir"
}

# Main
main() {
    log_info "VM-based test runner for srv-ctl"
    log_info "OS: $OS_VERSION"
    echo ""
    
    check_prerequisites
    
    # Create temporary work directory
    local work_dir=$(mktemp -d -t srv-ctl-vm-XXXXXX)
    trap "cleanup_vm '$work_dir'" EXIT INT TERM
    
    log_step "Setting up VM environment in: $work_dir"
    
    create_cloud_init "$work_dir"
    create_vm_disk "$work_dir"
    start_vm "$work_dir"
    
    if run_tests_in_vm "$work_dir"; then
        echo ""
        log_info "✓ All VM tests passed for $OS_VERSION"
        exit 0
    else
        echo ""
        log_error "✗ Some VM tests failed for $OS_VERSION"
        exit 1
    fi
}

main "$@"
