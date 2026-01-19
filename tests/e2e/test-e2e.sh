#!/bin/bash
# End-to-end tests for srv-ctl.sh
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
        cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.e2e_original_backup"
    fi
    
    # Install test config
    cp "$PROJECT_ROOT/tests/fixtures/config.local.test" "$PROJECT_ROOT/config.local"
    log_pass "Test config installed"
}

# Restore original config
restore_config() {
    if [ -f "$PROJECT_ROOT/config.local.e2e_original_backup" ]; then
        mv "$PROJECT_ROOT/config.local.e2e_original_backup" "$PROJECT_ROOT/config.local"
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
# E2E Tests with Real Environment (require root and test environment)
# ============================================================================

# Test 13: E2E unlock-only command
test_e2e_unlock_only() {
    run_test "E2E: unlock-only command"
    
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

# Test 14: E2E stop command (unmounts devices)
test_e2e_stop() {
    run_test "E2E: stop command"
    
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

# Test 15: E2E start command (full workflow)
test_e2e_start() {
    run_test "E2E: start command"
    
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

# Test 16: E2E stop-services-only command
test_e2e_stop_services_only() {
    run_test "E2E: stop-services-only command"
    
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

# Test 17: E2E idempotency - double start
test_e2e_double_start() {
    run_test "E2E: double start (idempotency)"
    
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

# Test 18: E2E idempotency - double stop
test_e2e_double_stop() {
    run_test "E2E: double stop (idempotency)"
    
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

# Setup E2E test environment (reuses integration test setup)
setup_e2e_environment() {
    if [ "$EUID" -ne 0 ]; then
        log_fail "E2E tests require root privileges. Skipping E2E tests."
        return 1
    fi
    
    # Run the integration test setup
    echo "Setting up E2E test environment..."
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
        

        # Create E2E config that uses the test environment

        cat > "$PROJECT_ROOT/config.local" <<EOF
#!/usr/bin/env bash
# E2E Test Configuration - uses integration test environment

readonly CRYPTSETUP_MIN_VERSION="2.4.0"

# Services (ST_SERVICE_1 set to 'ssh' for E2E test)
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

readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF
        
        log_pass "E2E test environment setup complete"
        return 0
    else
        log_fail "Test environment configuration not found"
        return 1
    fi
}

# Cleanup E2E environment
cleanup_e2e_environment() {
    if [ "$EUID" -eq 0 ]; then
        # Ensure everything is stopped/unmounted
        sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop &>/dev/null || true
        
        # Cleanup integration test environment
        if [ -f "$PROJECT_ROOT/tests/fixtures/cleanup-test-env.sh" ]; then
            sudo bash "$PROJECT_ROOT/tests/fixtures/cleanup-test-env.sh" &>/dev/null || true
        fi
    fi
}

# Main
main() {
    echo "========================================="
    echo "End-to-End Tests for srv-ctl"
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
    
    # E2E tests with real environment (require root)
    echo ""
    echo "========================================="
    echo "E2E Tests with Real Environment"
    echo "========================================="
    echo ""
    
    if setup_e2e_environment; then
        test_e2e_unlock_only
        test_e2e_stop
        test_e2e_start
        test_e2e_stop_services_only
        test_e2e_double_start
        test_e2e_double_stop
        
        cleanup_e2e_environment
    else
        # If running as root (which we should be in CI), setup failure is a test failure
        if [ "$EUID" -eq 0 ]; then
            echo "E2E test environment setup failed (this is a test failure in CI)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        else
            echo "Skipping E2E tests (requires root)"
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
