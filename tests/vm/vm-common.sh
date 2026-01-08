#!/bin/bash
# Common VM functions for test runners

# Set by parent script
: "${OS_VERSION:?}"
: "${SCRIPT_DIR:?}"
: "${PROJECT_ROOT:=$(cd "$SCRIPT_DIR/../.." && pwd)}"

CACHE_DIR="${HOME}/.cache/vm-images"
# Used by child scripts (run-tests.sh, run-system-tests.sh)
export RESULTS_DIR="$SCRIPT_DIR/results"

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
    
    # Generate SSH key if it doesn't exist
    local ssh_key="$work_dir/id_rsa"
    if [[ ! -f "$ssh_key" ]]; then
        ssh-keygen -t rsa -b 2048 -f "$ssh_key" -N "" -C "srv-ctl-test" &>/dev/null
    fi
    local ssh_pub_key
    ssh_pub_key=$(cat "$ssh_key.pub")
    
    cat > "$work_dir/user-data" << EOF
#cloud-config
users:
  - name: testuser
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $ssh_pub_key

packages:
  - cryptsetup
  - cryptsetup-bin
  - lvm2
  - dosfstools
  - ntfs-3g
  - exfat-fuse
  - exfatprogs
  - cifs-utils
  - libkeyutils1
  - keyutils
  - libwbclient0
  - nfs-common
  - curl
  - samba
  - samba-common-bin
  - nfs-kernel-server

package_update: true
package_upgrade: true

runcmd:
  # Verify cryptsetup version and BitLocker support
  - echo "[INFO] Cryptsetup version:" >> /var/log/cloud-init-output.log
  - cryptsetup --version >> /var/log/cloud-init-output.log 2>&1
  - echo "[INFO] Cryptsetup supported formats:" >> /var/log/cloud-init-output.log
  - cryptsetup --help | grep -A 20 "supported" >> /var/log/cloud-init-output.log 2>&1 || true
  # Update library cache before starting services
  - ldconfig
  - systemctl restart sshd
  # Setup Samba test user and share
  - useradd -M testuser 2>/dev/null || true
  - echo -e "testpass\ntestpass" | smbpasswd -a -s testuser 2>/dev/null || true
  - mkdir -p /tmp/test_samba_share
  - chmod 777 /tmp/test_samba_share
  # Setup NFS test export
  - mkdir -p /tmp/test_nfs_share
  - chmod 777 /tmp/test_nfs_share
  - echo "/tmp/test_nfs_share *(rw,sync,no_subtree_check,insecure)" >> /etc/exports
  - exportfs -ra || true
  # Start services
  - systemctl enable smbd nfs-server || true
  - systemctl start smbd nfs-server || true

write_files:
  - path: /etc/ssh/sshd_config.d/test.conf
    content: |
      PermitRootLogin yes
      PubkeyAuthentication yes
    permissions: '0644'
  - path: /etc/samba/smb.conf
    content: |
      [global]
         workgroup = WORKGROUP
         security = user
         map to guest = Bad User
         bind interfaces only = no

      [testshare]
         path = /tmp/test_samba_share
         read only = no
         guest ok = yes
         force user = testuser
         create mask = 0755
         directory mask = 0755
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
    
    # Detect if KVM is available
    local accel="tcg"
    local cpu_type="qemu64"
    local max_wait=120
    if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
        accel="kvm"
        cpu_type="host"
        log_info "Using KVM acceleration"
    else
        log_info "KVM not available, using TCG (software emulation)"
        max_wait=300  # TCG is much slower, need more time
    fi
    
    qemu-system-x86_64 \
        -name "srv-ctl-test-${OS_VERSION}" \
        -machine type=q35,accel=$accel \
        -cpu $cpu_type \
        -m 2048 \
        -smp 2 \
        -drive file="$work_dir/disk.qcow2",if=virtio,format=qcow2 \
        -drive file="$work_dir/test-disk.qcow2",if=virtio,format=qcow2 \
        -drive file="$work_dir/cloud-init.img",if=virtio,format=raw \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -display none \
        -pidfile "$work_dir/qemu.pid" \
        -daemonize
    
    # Wait for SSH to be available
    log_info "Waiting for VM to boot..."
    local waited=0
    local ssh_key="$work_dir/id_rsa"
    
    while ! ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
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

# Cleanup VM
cleanup_vm() {
    local work_dir="$1"
    
    if [[ -f "$work_dir/qemu.pid" ]]; then
        local pid
        pid=$(cat "$work_dir/qemu.pid")
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
