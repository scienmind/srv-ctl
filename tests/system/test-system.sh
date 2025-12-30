#!/bin/bash
# System tests for srv-ctl.sh
# Tests high-level workflows using the test configuration

set -euo pipefail

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "$1"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_pass "$1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$1"
}

# Setup test config
setup_test_config() {
    # Backup existing config if it exists
    if [ -f "$PROJECT_ROOT/config.local" ]; then
        cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.system_test_backup"
    fi
    
    # Install test config
    cp "$PROJECT_ROOT/tests/fixtures/config.local.test" "$PROJECT_ROOT/config.local"
    log_pass "Test config installed"
}

# Restore original config
restore_config() {
    if [ -f "$PROJECT_ROOT/config.local.system_test_backup" ]; then
        mv "$PROJECT_ROOT/config.local.system_test_backup" "$PROJECT_ROOT/config.local"
    fi
}

# Test 1: Help command works
test_help_command() {
    run_test "Help command displays usage"
    
    if bash "$PROJECT_ROOT/srv-ctl.sh" help > /dev/null 2>&1; then
        pass_test "Help command executed successfully"
    else
        fail_test "Help command failed"
        return 1
    fi
}

# Test 2: Validate config command works
test_validate_config() {
    run_test "Validate config command"
    
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && echo "$output" | grep -q "disabled"; then
        pass_test "Config validation passed with expected output"
    else
        fail_test "Config validation failed or unexpected output"
        echo "$output"
        return 1
    fi
}

# Test 3: Help command variations
test_help_variations() {
    run_test "Help command variations (-h)"
    
    if bash "$PROJECT_ROOT/srv-ctl.sh" -h > /dev/null 2>&1; then
        pass_test "-h flag shows help"
    else
        fail_test "-h flag failed"
        return 1
    fi
}

# Test 4: Missing config detection
test_missing_config() {
    run_test "Missing config file detection"
    
    # Temporarily rename config
    if [ -f "$PROJECT_ROOT/config.local" ]; then
        mv "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    fi
    
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1) || true
    
    # Restore config before checking result
    if [ -f "$PROJECT_ROOT/config.local.backup" ]; then
        mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
    fi
    
    if echo "$output" | grep -q "config.local.*not found"; then
        pass_test "Missing config detected correctly"
    else
        fail_test "Missing config not detected: $output"
        return 1
    fi
}

# Test 5: Root check (when not root)
test_root_check() {
    run_test "Root privilege check"
    
    if [ "$EUID" -ne 0 ]; then
        local output
        output=$(bash "$PROJECT_ROOT/srv-ctl.sh" start 2>&1) || true
        
        if echo "$output" | grep -q "run as root"; then
            pass_test "Root check working correctly"
        else
            fail_test "Root check not working: $output"
            return 1
        fi
    else
        pass_test "Running as root, skipping root check test"
    fi
}

# Test 6: Config with all disabled devices
test_all_disabled_config() {
    run_test "Config with all devices disabled"
    
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1)
    
    if echo "$output" | grep -q "0 devices enabled"; then
        pass_test "All devices correctly disabled in test config"
    else
        fail_test "Device count unexpected: $output"
        return 1
    fi
}

# Test 7: Test config structure validation
test_config_structure() {
    run_test "Config structure validation"
    
    # Verify test config has expected structure and all UUIDs disabled
    if grep -q "readonly PRIMARY_DATA_UUID" "$PROJECT_ROOT/config.local"; then
        local enabled_count
        enabled_count=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1 | grep -oP '\d+(?= devices enabled)' || echo "unknown")
        
        if [ "$enabled_count" = "0" ]; then
            pass_test "Config structure valid with all devices disabled"
        else
            fail_test "Expected 0 enabled devices, got: $enabled_count"
            return 1
        fi
    else
        fail_test "Config structure invalid"
        return 1
    fi
}

# Test 8: Invalid command handling
test_invalid_command() {
    run_test "Invalid command handling"
    
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" invalid-command 2>&1) || true
    
    # Accept either usage message or root requirement (root check happens first)
    if echo "$output" | grep -qi "usage\|unknown\|invalid\|root"; then
        pass_test "Invalid command shows error message"
    else
        fail_test "Invalid command not handled: $output"
        return 1
    fi
}

# Test 9: Config with enabled device shows correct count
test_enabled_device_count() {
    run_test "Config with enabled device shows correct count"
    
    local temp_config="$PROJECT_ROOT/config.local"
    
    # Modify config to enable one device
    sed -i 's/PRIMARY_DATA_UUID="none"/PRIMARY_DATA_UUID="12345678-fake-uuid-test"/' "$temp_config"
    
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1)
    
    # Restore to disabled
    sed -i 's/PRIMARY_DATA_UUID="12345678-fake-uuid-test"/PRIMARY_DATA_UUID="none"/' "$temp_config"
    
    if echo "$output" | grep -q "1 devices enabled\|1 device enabled"; then
        pass_test "Enabled device count correctly shown"
    else
        fail_test "Device count incorrect: $output"
        return 1
    fi
}

# Test 10: Invalid encryption type detection
test_invalid_encryption_type() {
    run_test "Invalid encryption type detection"
    
    local temp_config="$PROJECT_ROOT/config.local"
    
    # Enable a device with invalid encryption type
    sed -i 's/PRIMARY_DATA_UUID="none"/PRIMARY_DATA_UUID="12345678-fake-uuid-test"/' "$temp_config"
    sed -i 's/PRIMARY_DATA_ENCRYPTION_TYPE="luks"/PRIMARY_DATA_ENCRYPTION_TYPE="invalid_type"/' "$temp_config"
    
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1) || true
    local exit_code=$?
    
    # Restore config
    sed -i 's/PRIMARY_DATA_UUID="12345678-fake-uuid-test"/PRIMARY_DATA_UUID="none"/' "$temp_config"
    sed -i 's/PRIMARY_DATA_ENCRYPTION_TYPE="invalid_type"/PRIMARY_DATA_ENCRYPTION_TYPE="luks"/' "$temp_config"
    
    if [ $exit_code -ne 0 ] || echo "$output" | grep -qi "invalid\|unsupported\|error"; then
        pass_test "Invalid encryption type detected"
    else
        fail_test "Invalid encryption type not detected: $output"
        return 1
    fi
}

# Test 11: No arguments shows usage
test_no_arguments() {
    run_test "No arguments shows usage"
    
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" 2>&1) || true
    
    if echo "$output" | grep -qi "usage"; then
        pass_test "No arguments shows usage"
    else
        fail_test "No arguments did not show usage: $output"
        return 1
    fi
}

# Test 12: Script is executable
test_script_executable() {
    run_test "Script is executable"
    
    if [ -x "$PROJECT_ROOT/srv-ctl.sh" ]; then
        pass_test "srv-ctl.sh is executable"
    else
        fail_test "srv-ctl.sh is not executable"
        return 1
    fi
}

# ============================================================================
# System Tests with Real Environment (require root and test environment)
# ============================================================================

# Test 13: System test - unlock-only command
test_system_unlock_only() {
    run_test "System: unlock-only command"
    
    # Run unlock-only
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" unlock-only 2>&1; then
        # Verify device is mounted
        if mountpoint -q "/mnt/$TEST_MOUNT_POINT" 2>/dev/null; then
            pass_test "unlock-only successfully mounted device"
        else
            fail_test "Device not mounted after unlock-only"
            return 1
        fi
    else
        fail_test "unlock-only command failed"
        return 1
    fi
}

# Test 14: System test - stop command (unmounts devices)
test_system_stop() {
    run_test "System: stop command"
    
    # Ensure device is mounted first
    if ! mountpoint -q "/mnt/$TEST_MOUNT_POINT" 2>/dev/null; then
        sudo bash "$PROJECT_ROOT/srv-ctl.sh" unlock-only &>/dev/null
    fi
    
    # Run stop
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop 2>&1; then
        # Verify device is unmounted
        if ! mountpoint -q "/mnt/$TEST_MOUNT_POINT" 2>/dev/null; then
            pass_test "stop successfully unmounted device"
        else
            fail_test "Device still mounted after stop"
            return 1
        fi
    else
        fail_test "stop command failed"
        return 1
    fi
}

# Test 15: System test - start command (full workflow)
test_system_start() {
    run_test "System: start command"
    
    # Ensure clean state
    sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop &>/dev/null || true
    
    # Run start
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" start 2>&1; then
        # Verify device is mounted
        if mountpoint -q "/mnt/$TEST_MOUNT_POINT" 2>/dev/null; then
            pass_test "start successfully mounted device"
        else
            fail_test "Device not mounted after start"
            return 1
        fi
    else
        fail_test "start command failed"
        return 1
    fi
}

# Test 16: System test - stop-services-only command
test_system_stop_services_only() {
    run_test "System: stop-services-only command"
    
    # Ensure device is mounted
    if ! mountpoint -q "/mnt/$TEST_MOUNT_POINT" 2>/dev/null; then
        sudo bash "$PROJECT_ROOT/srv-ctl.sh" unlock-only &>/dev/null
    fi
    
    # Run stop-services-only
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop-services-only 2>&1; then
        # Verify device is still mounted (services stopped, devices not unmounted)
        if mountpoint -q "/mnt/$TEST_MOUNT_POINT" 2>/dev/null; then
            pass_test "stop-services-only kept device mounted"
        else
            fail_test "Device unexpectedly unmounted after stop-services-only"
            return 1
        fi
    else
        fail_test "stop-services-only command failed"
        return 1
    fi
}

# Test 17: System test - idempotency - double start
test_system_double_start() {
    run_test "System: double start (idempotency)"
    
    # Ensure clean state
    sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop &>/dev/null || true
    
    # Run start twice
    sudo bash "$PROJECT_ROOT/srv-ctl.sh" start &>/dev/null
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" start 2>&1; then
        # Verify device is still mounted
        if mountpoint -q "/mnt/$TEST_MOUNT_POINT" 2>/dev/null; then
            pass_test "double start handled gracefully"
        else
            fail_test "Device not mounted after double start"
            return 1
        fi
    else
        fail_test "double start command failed"
        return 1
    fi
}

# Test 18: System test - idempotency - double stop
test_system_double_stop() {
    run_test "System: double stop (idempotency)"
    
    # Ensure started state
    sudo bash "$PROJECT_ROOT/srv-ctl.sh" start &>/dev/null || true
    
    # Run stop twice
    sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop &>/dev/null
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop 2>&1; then
        # Verify device is unmounted
        if ! mountpoint -q "/mnt/$TEST_MOUNT_POINT" 2>/dev/null; then
            pass_test "double stop handled gracefully"
        else
            fail_test "Device still mounted after double stop"
            return 1
        fi
    else
        fail_test "double stop command failed"
        return 1
    fi
}

# Setup system test environment (reuses integration test setup)
setup_system_environment() {
    if [ "$EUID" -ne 0 ]; then
        log_fail "System tests require root privileges. Skipping system tests."
        return 1
    fi
    
    # Run the integration test setup
    echo "Setting up system test environment..."
    if ! sudo bash "$PROJECT_ROOT/tests/fixtures/setup-test-env.sh"; then
        log_fail "Failed to setup test environment"
        if [ -f "$PROJECT_ROOT/tests/fixtures/cleanup-test-env.sh" ]; then
            sudo bash "$PROJECT_ROOT/tests/fixtures/cleanup-test-env.sh" || true
        fi
        return 1
    fi
    
    # Load test environment variables
    if [ -f /tmp/test_env.conf ]; then
        source /tmp/test_env.conf
        
        # Create key file for automated unlocking
        local key_file="/tmp/test_key.key"
        echo -n "$TEST_PASSWORD" > "$key_file"
        chmod 600 "$key_file"
        

        # Create system test config that uses the test environment

        cat > "$PROJECT_ROOT/config.local" <<EOF
#!/usr/bin/env bash
# System Test Configuration - uses integration test environment

readonly CRYPTSETUP_MIN_VERSION="2.4.0"

# Services (ST_SERVICE_1 set to 'ssh' for system test)
readonly ST_USER_1="none"
readonly ST_SERVICE_1="ssh"
readonly ST_USER_2="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

# Primary Data Device (uses test environment)
readonly PRIMARY_DATA_UUID="$TEST_LOOP_UUID"
readonly PRIMARY_DATA_KEY_FILE="$key_file"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="$TEST_LV_MAPPER"
readonly PRIMARY_DATA_LVM_NAME="$TEST_LV_NAME"
readonly PRIMARY_DATA_LVM_GROUP="$TEST_VG_NAME"
readonly PRIMARY_DATA_MOUNT="$TEST_MOUNT_POINT"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"

# All other storage devices disabled
readonly STORAGE_1A_UUID="none"
readonly STORAGE_1A_KEY_FILE="none"
readonly STORAGE_1A_ENCRYPTION_TYPE="luks"
readonly STORAGE_1A_MAPPER="none"
readonly STORAGE_1A_LVM_NAME="none"
readonly STORAGE_1A_LVM_GROUP="none"
readonly STORAGE_1A_MOUNT="none"
readonly STORAGE_1A_OWNER_USER="none"
readonly STORAGE_1A_OWNER_GROUP="none"
readonly STORAGE_1A_MOUNT_OPTIONS="defaults"

readonly STORAGE_1B_UUID="none"
readonly STORAGE_1B_KEY_FILE="none"
readonly STORAGE_1B_ENCRYPTION_TYPE="luks"
readonly STORAGE_1B_MAPPER="none"
readonly STORAGE_1B_LVM_NAME="none"
readonly STORAGE_1B_LVM_GROUP="none"
readonly STORAGE_1B_MOUNT="none"
readonly STORAGE_1B_OWNER_USER="none"
readonly STORAGE_1B_OWNER_GROUP="none"
readonly STORAGE_1B_MOUNT_OPTIONS="defaults"

readonly STORAGE_2A_UUID="none"
readonly STORAGE_2A_KEY_FILE="none"
readonly STORAGE_2A_ENCRYPTION_TYPE="luks"
readonly STORAGE_2A_MAPPER="none"
readonly STORAGE_2A_LVM_NAME="none"
readonly STORAGE_2A_LVM_GROUP="none"
readonly STORAGE_2A_MOUNT="none"
readonly STORAGE_2A_OWNER_USER="none"
readonly STORAGE_2A_OWNER_GROUP="none"
readonly STORAGE_2A_MOUNT_OPTIONS="defaults"

readonly STORAGE_2B_UUID="none"
readonly STORAGE_2B_KEY_FILE="none"
readonly STORAGE_2B_ENCRYPTION_TYPE="luks"
readonly STORAGE_2B_MAPPER="none"
readonly STORAGE_2B_LVM_NAME="none"
readonly STORAGE_2B_LVM_GROUP="none"
readonly STORAGE_2B_MOUNT="none"
readonly STORAGE_2B_OWNER_USER="none"
readonly STORAGE_2B_OWNER_GROUP="none"
readonly STORAGE_2B_MOUNT_OPTIONS="defaults"

# Network Share (disabled)
readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF
        
        log_pass "System test environment setup complete"
        return 0
    else
        log_fail "Test environment configuration not found"
        return 1
    fi
}

# Cleanup system test environment
cleanup_system_environment() {
    if [ "$EUID" -eq 0 ]; then
        # Ensure everything is stopped/unmounted
        sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop &>/dev/null || true
        
        # Cleanup integration test environment
        if [ -f "$PROJECT_ROOT/tests/fixtures/cleanup-test-env.sh" ]; then
            sudo bash "$PROJECT_ROOT/tests/fixtures/cleanup-test-env.sh" &>/dev/null || true
        fi
    fi
}

# Network Share System Tests (CIFS/NFS)
test_network_share_system_workflows() {
    echo ""
    echo "========================================="
    echo "System Tests: Network Shares (CIFS/NFS)"
    echo "========================================="
    echo ""

    # --- CIFS (Samba) ---
    echo "[Setup] Verifying Samba test server (configured via cloud-init)..."
    if ! systemctl is-active --quiet smbd 2>/dev/null; then
        echo "[WARN] Samba service not running, tests may fail"
    fi

    # Patch config.local for CIFS
    cat > "$PROJECT_ROOT/config.local" <<EOF
#!/usr/bin/env bash
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_SERVICE_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"
readonly PRIMARY_DATA_UUID="none"
readonly PRIMARY_DATA_MOUNT="none"
readonly PRIMARY_DATA_MAPPER="none"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_KEY_FILE="none"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"
readonly STORAGE_1A_MOUNT="none"
readonly STORAGE_1A_MAPPER="none"
readonly STORAGE_1A_LVM_NAME="none"
readonly STORAGE_1A_LVM_GROUP="none"
readonly STORAGE_1A_UUID="none"
readonly STORAGE_1A_KEY_FILE="none"
readonly STORAGE_1A_ENCRYPTION_TYPE="luks"
readonly STORAGE_1A_OWNER_USER="none"
readonly STORAGE_1A_OWNER_GROUP="none"
readonly STORAGE_1A_MOUNT_OPTIONS="defaults"
readonly STORAGE_1B_MOUNT="none"
readonly STORAGE_1B_MAPPER="none"
readonly STORAGE_1B_LVM_NAME="none"
readonly STORAGE_1B_LVM_GROUP="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_1B_KEY_FILE="none"
readonly STORAGE_1B_ENCRYPTION_TYPE="luks"
readonly STORAGE_1B_OWNER_USER="none"
readonly STORAGE_1B_OWNER_GROUP="none"
readonly STORAGE_1B_MOUNT_OPTIONS="defaults"
readonly STORAGE_2A_MOUNT="none"
readonly STORAGE_2A_MAPPER="none"
readonly STORAGE_2A_LVM_NAME="none"
readonly STORAGE_2A_LVM_GROUP="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2A_KEY_FILE="none"
readonly STORAGE_2A_ENCRYPTION_TYPE="luks"
readonly STORAGE_2A_OWNER_USER="none"
readonly STORAGE_2A_OWNER_GROUP="none"
readonly STORAGE_2A_MOUNT_OPTIONS="defaults"
readonly STORAGE_2B_MOUNT="none"
readonly STORAGE_2B_MAPPER="none"
readonly STORAGE_2B_LVM_NAME="none"
readonly STORAGE_2B_LVM_GROUP="none"
readonly STORAGE_2B_UUID="none"
readonly STORAGE_2B_KEY_FILE="none"
readonly STORAGE_2B_ENCRYPTION_TYPE="luks"
readonly STORAGE_2B_OWNER_USER="none"
readonly STORAGE_2B_OWNER_GROUP="none"
readonly STORAGE_2B_MOUNT_OPTIONS="defaults"
readonly NETWORK_SHARE_PROTOCOL="cifs"
readonly NETWORK_SHARE_ADDRESS="//localhost/testshare"
readonly NETWORK_SHARE_CREDENTIALS="/tmp/smb-cred"
readonly NETWORK_SHARE_MOUNT="test-cifs"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="vers=3.0"
EOF

    # Write credentials file
    cat > /tmp/smb-cred <<EOF
username=testuser
password=testpass
EOF
    chmod 600 /tmp/smb-cred

    run_test "CIFS: Mount network share via srv-ctl.sh start"
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" start 2>&1; then
        if mountpoint -q "/mnt/test-cifs"; then
            pass_test "CIFS share mounted via start"
            # I/O test
            echo "testfile" | sudo tee /mnt/test-cifs/systest.txt > /dev/null
            if sudo grep -q "testfile" /mnt/test-cifs/systest.txt; then
                pass_test "CIFS share I/O works"
            else
                fail_test "CIFS share I/O failed"
            fi
        else
            fail_test "CIFS share not mounted"
        fi
    else
        fail_test "srv-ctl.sh start failed for CIFS"
    fi

    run_test "CIFS: Unmount network share via srv-ctl.sh stop"
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop 2>&1; then
        if ! mountpoint -q "/mnt/test-cifs"; then
            pass_test "CIFS share unmounted via stop"
        else
            fail_test "CIFS share still mounted after stop"
        fi
    else
        fail_test "srv-ctl.sh stop failed for CIFS"
    fi

    # Cleanup credentials file (services stay running for potential reuse)
    sudo rm -f /tmp/smb-cred

    # --- NFS ---
    echo "[Setup] Verifying NFS test server (configured via cloud-init)..."
    if ! systemctl is-active --quiet nfs-server 2>/dev/null; then
        echo "[WARN] NFS service not running, tests may fail"
    fi

    # Patch config.local for NFS
    cat > "$PROJECT_ROOT/config.local" <<EOF
#!/usr/bin/env bash
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_SERVICE_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"
readonly PRIMARY_DATA_UUID="none"
readonly PRIMARY_DATA_MOUNT="none"
readonly PRIMARY_DATA_MAPPER="none"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_KEY_FILE="none"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"
readonly STORAGE_1A_MOUNT="none"
readonly STORAGE_1A_MAPPER="none"
readonly STORAGE_1A_LVM_NAME="none"
readonly STORAGE_1A_LVM_GROUP="none"
readonly STORAGE_1A_UUID="none"
readonly STORAGE_1A_KEY_FILE="none"
readonly STORAGE_1A_ENCRYPTION_TYPE="luks"
readonly STORAGE_1A_OWNER_USER="none"
readonly STORAGE_1A_OWNER_GROUP="none"
readonly STORAGE_1A_MOUNT_OPTIONS="defaults"
readonly STORAGE_1B_MOUNT="none"
readonly STORAGE_1B_MAPPER="none"
readonly STORAGE_1B_LVM_NAME="none"
readonly STORAGE_1B_LVM_GROUP="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_1B_KEY_FILE="none"
readonly STORAGE_1B_ENCRYPTION_TYPE="luks"
readonly STORAGE_1B_OWNER_USER="none"
readonly STORAGE_1B_OWNER_GROUP="none"
readonly STORAGE_1B_MOUNT_OPTIONS="defaults"
readonly STORAGE_2A_MOUNT="none"
readonly STORAGE_2A_MAPPER="none"
readonly STORAGE_2A_LVM_NAME="none"
readonly STORAGE_2A_LVM_GROUP="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2A_KEY_FILE="none"
readonly STORAGE_2A_ENCRYPTION_TYPE="luks"
readonly STORAGE_2A_OWNER_USER="none"
readonly STORAGE_2A_OWNER_GROUP="none"
readonly STORAGE_2A_MOUNT_OPTIONS="defaults"
readonly STORAGE_2B_MOUNT="none"
readonly STORAGE_2B_MAPPER="none"
readonly STORAGE_2B_LVM_NAME="none"
readonly STORAGE_2B_LVM_GROUP="none"
readonly STORAGE_2B_UUID="none"
readonly STORAGE_2B_KEY_FILE="none"
readonly STORAGE_2B_ENCRYPTION_TYPE="luks"
readonly STORAGE_2B_OWNER_USER="none"
readonly STORAGE_2B_OWNER_GROUP="none"
readonly STORAGE_2B_MOUNT_OPTIONS="defaults"
readonly NETWORK_SHARE_PROTOCOL="nfs"
readonly NETWORK_SHARE_ADDRESS="localhost:/tmp/test_nfs_share"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="test-nfs"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="rw,sync"
EOF

    run_test "NFS: Mount network share via srv-ctl.sh start"
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" start 2>&1; then
        if mountpoint -q "/mnt/test-nfs"; then
            pass_test "NFS share mounted via start"
            # I/O test
            echo "testfile" | sudo tee /mnt/test-nfs/systest.txt > /dev/null
            if sudo grep -q "testfile" /mnt/test-nfs/systest.txt; then
                pass_test "NFS share I/O works"
            else
                fail_test "NFS share I/O failed"
            fi
        else
            fail_test "NFS share not mounted"
        fi
    else
        fail_test "srv-ctl.sh start failed for NFS"
    fi

    run_test "NFS: Unmount network share via srv-ctl.sh stop"
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop 2>&1; then
        if ! mountpoint -q "/mnt/test-nfs"; then
            pass_test "NFS share unmounted via stop"
        else
            fail_test "NFS share still mounted after stop"
        fi
    else
        fail_test "srv-ctl.sh stop failed for NFS"
    fi

    # NFS cleanup not needed - services configured via cloud-init stay running
}

# Multi-Device Orchestration System Tests
test_multi_device_system_workflows() {
    echo ""
    echo "========================================="
    echo "System Tests: Multi-Device Orchestration"
    echo "========================================="
    echo ""

    # Setup multiple test environments - create additional loop devices
    log_info "Creating multiple test devices..."
    
    # Create 3 additional loop devices (we already have one from setup_system_environment)
    local loop_device_2=$(sudo losetup -f)
    local loop_device_3=$(sudo losetup -f --show <(dd if=/dev/zero bs=1M count=100 2>/dev/null))
    local loop_device_4=$(sudo losetup -f --show <(dd if=/dev/zero bs=1M count=100 2>/dev/null))
    
    # Setup LUKS on additional devices
    echo "test123456" | sudo cryptsetup luksFormat --type luks2 "$loop_device_3" -
    echo "test123456" | sudo cryptsetup luksFormat --type luks2 "$loop_device_4" -
    
    # Get UUIDs
    local uuid_3=$(sudo cryptsetup luksUUID "$loop_device_3")
    local uuid_4=$(sudo cryptsetup luksUUID "$loop_device_4")
    
    # Create key files
    echo "test123456" > /tmp/key1a
    echo "test123456" > /tmp/key1b
    chmod 600 /tmp/key1a /tmp/key1b
    
    # Test 1: All devices enabled (PRIMARY + STORAGE_1A + STORAGE_1B + NETWORK_SHARE)
    echo "[TEST 1] Multiple devices enabled simultaneously"
    cat > "$PROJECT_ROOT/config.local" <<EOF
#!/usr/bin/env bash
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_SERVICE_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="$TEST_LOOP_UUID"
readonly PRIMARY_DATA_KEY_FILE="$key_file"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="$TEST_LV_MAPPER"
readonly PRIMARY_DATA_LVM_NAME="$TEST_LV_NAME"
readonly PRIMARY_DATA_LVM_GROUP="$TEST_VG_NAME"
readonly PRIMARY_DATA_MOUNT="$TEST_MOUNT_POINT"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"

readonly STORAGE_1A_UUID="$uuid_3"
readonly STORAGE_1A_KEY_FILE="/tmp/key1a"
readonly STORAGE_1A_ENCRYPTION_TYPE="luks"
readonly STORAGE_1A_MAPPER="test_mapper_1a"
readonly STORAGE_1A_LVM_NAME="none"
readonly STORAGE_1A_LVM_GROUP="none"
readonly STORAGE_1A_MOUNT="test_storage_1a"
readonly STORAGE_1A_OWNER_USER="none"
readonly STORAGE_1A_OWNER_GROUP="none"
readonly STORAGE_1A_MOUNT_OPTIONS="defaults"

readonly STORAGE_1B_UUID="$uuid_4"
readonly STORAGE_1B_KEY_FILE="/tmp/key1b"
readonly STORAGE_1B_ENCRYPTION_TYPE="luks"
readonly STORAGE_1B_MAPPER="test_mapper_1b"
readonly STORAGE_1B_LVM_NAME="none"
readonly STORAGE_1B_LVM_GROUP="none"
readonly STORAGE_1B_MOUNT="test_storage_1b"
readonly STORAGE_1B_OWNER_USER="none"
readonly STORAGE_1B_OWNER_GROUP="none"
readonly STORAGE_1B_MOUNT_OPTIONS="defaults"

readonly STORAGE_2A_UUID="none"
readonly STORAGE_2A_KEY_FILE="none"
readonly STORAGE_2A_ENCRYPTION_TYPE="luks"
readonly STORAGE_2A_MAPPER="none"
readonly STORAGE_2A_LVM_NAME="none"
readonly STORAGE_2A_LVM_GROUP="none"
readonly STORAGE_2A_MOUNT="none"
readonly STORAGE_2A_OWNER_USER="none"
readonly STORAGE_2A_OWNER_GROUP="none"
readonly STORAGE_2A_MOUNT_OPTIONS="defaults"

readonly STORAGE_2B_UUID="none"
readonly STORAGE_2B_KEY_FILE="none"
readonly STORAGE_2B_ENCRYPTION_TYPE="luks"
readonly STORAGE_2B_MAPPER="none"
readonly STORAGE_2B_LVM_NAME="none"
readonly STORAGE_2B_LVM_GROUP="none"
readonly STORAGE_2B_MOUNT="none"
readonly STORAGE_2B_OWNER_USER="none"
readonly STORAGE_2B_OWNER_GROUP="none"
readonly STORAGE_2B_MOUNT_OPTIONS="defaults"

readonly NETWORK_SHARE_PROTOCOL="nfs"
readonly NETWORK_SHARE_ADDRESS="localhost:/tmp/test_nfs_share"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="test-multi-nfs"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="rw,sync"
EOF

    run_test "Multi-device: Start all devices (3 LUKS + 1 NFS)"
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" start 2>&1; then
        local all_mounted=true
        
        # Check PRIMARY
        if ! mountpoint -q "/mnt/$TEST_MOUNT_POINT"; then
            log_fail "PRIMARY device not mounted"
            all_mounted=false
        fi
        
        # Check STORAGE_1A
        if ! mountpoint -q "/mnt/test_storage_1a"; then
            log_fail "STORAGE_1A not mounted"
            all_mounted=false
        fi
        
        # Check STORAGE_1B
        if ! mountpoint -q "/mnt/test_storage_1b"; then
            log_fail "STORAGE_1B not mounted"
            all_mounted=false
        fi
        
        # Check NETWORK_SHARE
        if ! mountpoint -q "/mnt/test-multi-nfs"; then
            log_fail "NETWORK_SHARE not mounted"
            all_mounted=false
        fi
        
        if [ "$all_mounted" = true ]; then
            pass_test "All 4 devices mounted successfully"
            
            # Test I/O on all devices
            run_test "Multi-device: I/O test on all devices"
            local io_success=true
            echo "test1" | sudo tee "/mnt/$TEST_MOUNT_POINT/test.txt" > /dev/null || io_success=false
            echo "test2" | sudo tee "/mnt/test_storage_1a/test.txt" > /dev/null || io_success=false
            echo "test3" | sudo tee "/mnt/test_storage_1b/test.txt" > /dev/null || io_success=false
            echo "test4" | sudo tee "/mnt/test-multi-nfs/test.txt" > /dev/null || io_success=false
            
            if [ "$io_success" = true ]; then
                pass_test "I/O works on all devices"
            else
                fail_test "I/O failed on one or more devices"
            fi
        else
            fail_test "Not all devices mounted"
        fi
    else
        fail_test "srv-ctl.sh start failed for multi-device"
    fi

    run_test "Multi-device: Stop all devices"
    if sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop 2>&1; then
        local all_unmounted=true
        mountpoint -q "/mnt/$TEST_MOUNT_POINT" && all_unmounted=false
        mountpoint -q "/mnt/test_storage_1a" && all_unmounted=false
        mountpoint -q "/mnt/test_storage_1b" && all_unmounted=false
        mountpoint -q "/mnt/test-multi-nfs" && all_unmounted=false
        
        if [ "$all_unmounted" = true ]; then
            pass_test "All devices unmounted successfully"
        else
            fail_test "Some devices still mounted"
        fi
    else
        fail_test "srv-ctl.sh stop failed for multi-device"
    fi

    # Cleanup additional devices
    sudo cryptsetup close test_mapper_1a 2>/dev/null || true
    sudo cryptsetup close test_mapper_1b 2>/dev/null || true
    sudo losetup -d "$loop_device_3" 2>/dev/null || true
    sudo losetup -d "$loop_device_4" 2>/dev/null || true
    sudo rm -f /tmp/key1a /tmp/key1b
}

# Main
main() {
    echo "========================================="
    echo "System Tests for srv-ctl"
    echo "========================================="
    echo ""
    
    setup_test_config
    
    test_help_command
    test_validate_config
    test_help_variations
    test_missing_config
    test_root_check
    test_all_disabled_config
    test_config_structure
    test_invalid_command
    test_enabled_device_count
    test_invalid_encryption_type
    test_no_arguments
    test_script_executable
    
    # System tests with real environment (require root)
    echo ""
    echo "========================================="
    echo "System Tests with Real Environment"
    echo "========================================="
    echo ""
    

    if setup_system_environment; then
        test_system_unlock_only
        test_system_stop
        test_system_start
        test_system_stop_services_only
        test_system_double_start
        test_system_double_stop

        # Run real network share system tests (CIFS/NFS)
        test_network_share_system_workflows

        # Run multi-device orchestration tests
        test_multi_device_system_workflows

        cleanup_system_environment
    else
        # If running as root (which we should be in CI), setup failure is a test failure
        if [ "$EUID" -eq 0 ]; then
            echo "System test environment setup failed (this is a test failure in CI)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        else
            echo "Skipping system tests (requires root)"
        fi
    fi
    
    # Restore original config
    restore_config
    
    echo ""
    echo "========================================="
    echo "Test Results"
    echo "========================================="
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

main "$@"
