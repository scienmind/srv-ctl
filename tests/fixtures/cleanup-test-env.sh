#!/bin/bash
# Cleanup script for integration tests
# Removes all test resources created by setup-test-env.sh

set -euo pipefail

# Test configuration (must match setup-test-env.sh)
readonly TEST_LUKS_NAME="test_luks"
readonly TEST_VG_NAME="test_vg"
readonly TEST_LV_NAME="test_lv"
readonly TEST_MOUNT_POINT="/tmp/test_mount"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if running with required privileges
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Unmount test mount point
unmount_test_volume() {
    if mountpoint -q "$TEST_MOUNT_POINT" 2>/dev/null; then
        log_info "Unmounting $TEST_MOUNT_POINT..."
        umount "$TEST_MOUNT_POINT" || log_warn "Failed to unmount $TEST_MOUNT_POINT"
    fi
}

# Remove mount point
remove_mount_point() {
    if [[ -d "$TEST_MOUNT_POINT" ]]; then
        log_info "Removing mount point $TEST_MOUNT_POINT..."
        rmdir "$TEST_MOUNT_POINT" 2>/dev/null || log_warn "Failed to remove $TEST_MOUNT_POINT"
    fi
}

# Deactivate LVM
deactivate_lvm() {
    if lvs "$TEST_VG_NAME/$TEST_LV_NAME" &>/dev/null; then
        log_info "Deactivating LVM..."
        lvchange -an "$TEST_VG_NAME/$TEST_LV_NAME" 2>/dev/null || log_warn "Failed to deactivate LV"
    fi
    
    if vgs "$TEST_VG_NAME" &>/dev/null; then
        log_info "Removing volume group..."
        vgremove -f "$TEST_VG_NAME" 2>/dev/null || log_warn "Failed to remove VG"
    fi
    
    # Remove any remaining physical volumes
    for pv in $(pvs --noheadings -o pv_name 2>/dev/null | grep mapper || true); do
        log_info "Removing physical volume $pv..."
        pvremove -f "$pv" 2>/dev/null || log_warn "Failed to remove PV $pv"
    done
}

# Close LUKS container
close_luks() {
    if [[ -e "/dev/mapper/$TEST_LUKS_NAME" ]]; then
        log_info "Closing LUKS container..."
        cryptsetup close "$TEST_LUKS_NAME" || log_warn "Failed to close LUKS container"
    fi
}

# Detach loop devices
detach_loop_devices() {
    log_info "Detaching loop devices..."
    
    # Remove UUID symlinks for loop devices
    if [[ -f /tmp/test_env.conf ]]; then
        source /tmp/test_env.conf 2>/dev/null || true
        if [[ -n "${TEST_LOOP_UUID:-}" && -L "/dev/disk/by-uuid/$TEST_LOOP_UUID" ]]; then
            log_info "Removing UUID symlink /dev/disk/by-uuid/$TEST_LOOP_UUID..."
            rm -f "/dev/disk/by-uuid/$TEST_LOOP_UUID"
        fi
    fi
    
    # Find and detach all loop devices using our test file
    for loop_dev in $(losetup -j /tmp/test_loop.img 2>/dev/null | cut -d: -f1); do
        log_info "Detaching $loop_dev..."
        losetup -d "$loop_dev" || log_warn "Failed to detach $loop_dev"
    done
    
    # Remove the loop file
    if [[ -f /tmp/test_loop.img ]]; then
        log_info "Removing loop file..."
        rm -f /tmp/test_loop.img
    fi
}

# Remove test configuration
remove_test_config() {
    if [[ -f /tmp/test_env.conf ]]; then
        log_info "Removing test configuration..."
        rm -f /tmp/test_env.conf
    fi
}

# Main cleanup
main() {
    log_info "Cleaning up integration test environment..."
    
    check_privileges
    
    unmount_test_volume
    remove_mount_point
    deactivate_lvm
    close_luks
    detach_loop_devices
    remove_test_config
    
    log_info "Test environment cleanup complete!"
}

main "$@"
