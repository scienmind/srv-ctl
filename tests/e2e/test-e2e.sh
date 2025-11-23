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
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "$1"
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
        log_pass "Help command executed successfully"
    else
        log_fail "Help command failed"
        return 1
    fi
}

# Test 2: Validate config command works
test_validate_config() {
    run_test "Validate config command"
    
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_pass "Config validation passed"
        
        # Verify validation output shows disabled devices
        if echo "$output" | grep -q "disabled"; then
            log_pass "Config correctly shows disabled devices"
        else
            log_fail "Config validation output unexpected"
            return 1
        fi
    else
        log_fail "Config validation failed"
        echo "$output"
        return 1
    fi
}

# Test 3: Help command variations
test_help_variations() {
    run_test "Help command variations (-h)"
    
    if bash "$PROJECT_ROOT/srv-ctl.sh" -h > /dev/null 2>&1; then
        log_pass "-h flag shows help"
    else
        log_fail "-h flag failed"
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
    
    # Try to run validate-config (should fail without config)
    # Note: Can't test start/stop commands as they require root
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1) || true
    
    # Restore config before checking result
    if [ -f "$PROJECT_ROOT/config.local.backup" ]; then
        mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
    fi
    
    if echo "$output" | grep -q "config.local.*not found"; then
        log_pass "Missing config detected correctly"
    else
        log_fail "Missing config not detected"
        echo "Output was: $output"
        return 1
    fi
}

# Test 5: Root check (when not root)
test_root_check() {
    run_test "Root privilege check"
    
    if [ "$EUID" -ne 0 ]; then
        # Not root, should fail with error
        local output
        output=$(bash "$PROJECT_ROOT/srv-ctl.sh" start 2>&1) || true
        
        if echo "$output" | grep -q "run as root"; then
            log_pass "Root check working correctly"
        else
            log_fail "Root check not working"
            echo "Output was: $output"
            return 1
        fi
    else
        log_pass "Running as root, skipping root check test"
    fi
}

# Test 6: Config with all disabled devices
test_all_disabled_config() {
    run_test "Config with all devices disabled"
    
    local output
    output=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1)
    
    if echo "$output" | grep -q "0 devices enabled"; then
        log_pass "All devices correctly disabled in test config"
    else
        log_fail "Device count unexpected"
        echo "$output"
        return 1
    fi
}

# Test 7: Test config structure validation
test_config_structure() {
    run_test "Config structure validation"
    
    # Verify test config has expected structure
    if grep -q "readonly PRIMARY_DATA_UUID" "$PROJECT_ROOT/config.local"; then
        log_pass "Config has proper structure"
    else
        log_fail "Config structure invalid"
        return 1
    fi
    
    # Verify test config has all UUIDs set to "none"
    local enabled_count
    enabled_count=$(bash "$PROJECT_ROOT/srv-ctl.sh" validate-config 2>&1 | grep -oP '\d+(?= devices enabled)' || echo "unknown")
    
    if [ "$enabled_count" = "0" ]; then
        log_pass "All test devices properly disabled"
    else
        log_fail "Expected 0 enabled devices, got: $enabled_count"
        return 1
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
