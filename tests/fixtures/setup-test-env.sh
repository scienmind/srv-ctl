#!/bin/bash
# Setup script for integration tests
# Creates loop devices, LUKS containers, and LVM volumes for testing

set -euo pipefail

# Test configuration
readonly TEST_LOOP_SIZE_MB=100
readonly TEST_LUKS_NAME="test_luks"
readonly TEST_VG_NAME="test_vg"
readonly TEST_LV_NAME="test_lv"
readonly TEST_MOUNT_POINT="/tmp/test_mount"
readonly TEST_PASSWORD="test123456"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running with required privileges
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Install required packages
install_dependencies() {
    log_info "Installing test dependencies..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq \
            cryptsetup \
            lvm2 \
            dosfstools \
            ntfs-3g \
            exfat-fuse \
            exfatprogs \
            util-linux
    elif command -v yum &> /dev/null; then
        yum install -y -q \
            cryptsetup \
            lvm2 \
            dosfstools \
            ntfs-3g \
            exfat-utils \
            util-linux
    else
        log_error "Unsupported package manager"
        exit 1
    fi
    
    log_info "Dependencies installed"
}

# Create a loop device for testing
create_loop_device() {
    log_info "Creating loop device (${TEST_LOOP_SIZE_MB}MB)..."
    
    # Create a file for the loop device
    local loop_file="/tmp/test_loop.img"
    dd if=/dev/zero of="$loop_file" bs=1M count=$TEST_LOOP_SIZE_MB status=none
    
    # Setup loop device
    local loop_dev=$(losetup -f)
    losetup "$loop_dev" "$loop_file"
    
    echo "$loop_dev"
    log_info "Loop device created: $loop_dev"
}

# Create LUKS container on loop device
create_luks_container() {
    local loop_dev=$1
    
    log_info "Creating LUKS container on $loop_dev..."
    
    # Format as LUKS
    echo -n "$TEST_PASSWORD" | cryptsetup luksFormat --type luks2 "$loop_dev" -
    
    # Open the LUKS container
    echo -n "$TEST_PASSWORD" | cryptsetup open "$loop_dev" "$TEST_LUKS_NAME" -
    
    log_info "LUKS container created and opened as /dev/mapper/$TEST_LUKS_NAME"
}

# Create LVM on LUKS container
create_lvm_on_luks() {
    log_info "Creating LVM on LUKS container..."
    
    local luks_dev="/dev/mapper/$TEST_LUKS_NAME"
    
    # Create physical volume
    pvcreate "$luks_dev"
    
    # Create volume group
    vgcreate "$TEST_VG_NAME" "$luks_dev"
    
    # Create logical volume (use most of the space)
    lvcreate -L 90M -n "$TEST_LV_NAME" "$TEST_VG_NAME"
    
    # Format with ext4
    mkfs.ext4 -q "/dev/$TEST_VG_NAME/$TEST_LV_NAME"
    
    log_info "LVM created: /dev/$TEST_VG_NAME/$TEST_LV_NAME"
}

# Create mount point
create_mount_point() {
    log_info "Creating test mount point: $TEST_MOUNT_POINT"
    mkdir -p "$TEST_MOUNT_POINT"
}

# Export test configuration
export_test_config() {
    local loop_dev=$1
    local config_file="/tmp/test_env.conf"
    
    # Get UUID of the loop device (for unlock_device function)
    local loop_uuid
    loop_uuid=$(blkid -s UUID -o value "$loop_dev")
    
    # Get UUID of the LVM logical volume (for mount tests)
    local lv_uuid
    lv_uuid=$(blkid -s UUID -o value "/dev/$TEST_VG_NAME/$TEST_LV_NAME")
    
    cat > "$config_file" <<EOF
# Test environment configuration
export TEST_LUKS_NAME="$TEST_LUKS_NAME"
export TEST_VG_NAME="$TEST_VG_NAME"
export TEST_LV_NAME="$TEST_LV_NAME"
export TEST_MOUNT_POINT="$TEST_MOUNT_POINT"
export TEST_PASSWORD="$TEST_PASSWORD"
export TEST_LUKS_DEV="/dev/mapper/$TEST_LUKS_NAME"
export TEST_LV_DEV="/dev/$TEST_VG_NAME/$TEST_LV_NAME"
export TEST_LOOP_UUID="$loop_uuid"
export TEST_LV_UUID="$lv_uuid"
export TEST_LUKS_MAPPER="$TEST_LUKS_NAME"
export TEST_LV_MAPPER="$TEST_VG_NAME-$TEST_LV_NAME"
EOF
    
    log_info "Test configuration exported to $config_file"
    log_info "  Loop device UUID: $loop_uuid"
    log_info "  LV UUID: $lv_uuid"
    log_info "Source with: source $config_file"
}

# Main setup
main() {
    log_info "Setting up integration test environment..."
    
    check_privileges
    install_dependencies
    
    local loop_dev
    loop_dev=$(create_loop_device)
    create_luks_container "$loop_dev"
    create_lvm_on_luks
    create_mount_point
    export_test_config "$loop_dev"
    
    log_info "Test environment setup complete!"
    log_info ""
    log_info "Test resources created:"
    log_info "  - Loop device: $loop_dev"
    log_info "  - LUKS container: /dev/mapper/$TEST_LUKS_NAME"
    log_info "  - Volume group: $TEST_VG_NAME"
    log_info "  - Logical volume: /dev/$TEST_VG_NAME/$TEST_LV_NAME"
    log_info "  - Mount point: $TEST_MOUNT_POINT"
    log_info ""
    log_info "Run cleanup-test-env.sh when done testing"
}

main "$@"
