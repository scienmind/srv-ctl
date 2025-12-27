#!/bin/bash
# Run E2E tests in a QEMU VM
# Provides complete isolation with full systemd, network stack, etc.

set -euo pipefail

OS_VERSION="${1:-ubuntu-22.04}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export OS_VERSION SCRIPT_DIR PROJECT_ROOT

# Source common VM functions
source "$SCRIPT_DIR/vm-common.sh"

# Override test command for E2E tests
run_tests_in_vm() {
    local work_dir="$1"
    local ssh_key="$work_dir/id_rsa"
    
    log_step "Copying project to VM..."
    
    # Create tarball
    local tar_file="$work_dir/srv-ctl.tar.gz"
    (cd "$PROJECT_ROOT" && tar -czf "$tar_file" \
        --exclude='.git' \
        --exclude='*.tar.gz' \
        --exclude='tests/vm/work' \
        --exclude='tests/vm/results' \
        .)
    
    # Copy to VM
    scp -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -P 2222 "$tar_file" testuser@localhost:/tmp/srv-ctl.tar.gz
    
    log_step "Running E2E tests in VM..."
    
    # Run tests via SSH
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p 2222 testuser@localhost << 'EOSSH'
set -euo pipefail

# Wait for cloud-init to complete
echo "Waiting for cloud-init to finish..."
cloud-init status --wait || true

# Extract project
mkdir -p /tmp/srv-ctl-test
cd /tmp/srv-ctl-test
tar -xzf /tmp/srv-ctl.tar.gz

# Setup test config
cp tests/fixtures/config.local.test config.local

# Make scripts executable
chmod +x srv-ctl.sh
chmod +x tests/run-tests.sh
chmod +x tests/e2e/*.sh
chmod +x tests/fixtures/*.sh

# Run E2E tests only
echo "========================================="
echo "Running E2E tests in VM"
echo "OS: $(lsb_release -ds)"
echo "Kernel: $(uname -r)"
echo "========================================="
echo ""

sudo ./tests/run-tests.sh --e2e-only

EOSSH
    
    local exit_code=$?
    
    # Copy results back
    mkdir -p "$RESULTS_DIR"
    scp -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -P 2222 -r testuser@localhost:/tmp/test-results/* "$RESULTS_DIR/" 2>/dev/null || true
    
    return $exit_code
}

# Main
main() {
    log_info "E2E test runner for srv-ctl"
    log_info "OS: $OS_VERSION"
    echo ""
    
    check_prerequisites
    
    # Create temporary work directory
    local work_dir
    work_dir=$(mktemp -d -t srv-ctl-vm-XXXXXX)
    trap 'cleanup_vm "$work_dir"' EXIT INT TERM
    
    log_step "Setting up VM environment in: $work_dir"
    
    create_cloud_init "$work_dir"
    create_vm_disk "$work_dir"
    start_vm "$work_dir"
    
    if run_tests_in_vm "$work_dir"; then
        echo ""
        log_info "✓ All E2E tests passed for $OS_VERSION"
        exit 0
    else
        echo ""
        log_error "✗ Some E2E tests failed for $OS_VERSION"
        exit 1
    fi
}

main "$@"
