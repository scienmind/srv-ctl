#!/bin/bash
# Integration tests for LUKS operations

set -euo pipefail

# Load test environment
if [[ ! -f /tmp/test_env.conf ]]; then
    echo "ERROR: Test environment not setup. Run setup-test-env.sh first."
    exit 1
fi
source /tmp/test_env.conf

# Load libraries
export SUCCESS=0
export FAILURE=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/os-utils.sh"
source "$SCRIPT_DIR/../../lib/storage.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
}

run_test() {
    ((TESTS_RUN++))
    log_test "$1"
}

# Test 1: Close and reopen LUKS container
test_luks_lock_unlock() {
    run_test "LUKS lock and unlock"
    
    if lock_device "$TEST_LUKS_MAPPER" "luks"; then
        log_pass "Successfully closed LUKS container"
    else
        log_fail "Failed to close LUKS container"
        return 1
    fi
    
    # Verify it's closed
    if [[ ! -e "/dev/mapper/$TEST_LUKS_MAPPER" ]]; then
        log_pass "LUKS container is closed"
    else
        log_fail "LUKS container still exists after close"
        return 1
    fi
    
    # Reopen LUKS using UUID
    if echo -n "$TEST_PASSWORD" | unlock_device "$TEST_LOOP_UUID" "$TEST_LUKS_MAPPER" "none" "luks"; then
        log_pass "Successfully reopened LUKS container"
    else
        log_fail "Failed to reopen LUKS container"
        return 1
    fi
    
    # Verify it's open
    if [[ -e "/dev/mapper/$TEST_LUKS_MAPPER" ]]; then
        log_pass "LUKS container is open"
    else
        log_fail "LUKS container does not exist after open"
        return 1
    fi
}

# Test 2: Wrong password handling
test_luks_wrong_password() {
    run_test "LUKS wrong password handling"
    
    # Close first
    lock_device "$TEST_LUKS_MAPPER" "luks" &>/dev/null
    
    # Try to open with wrong password
    if echo -n "wrongpassword" | unlock_device "$TEST_LOOP_UUID" "$TEST_LUKS_MAPPER" "none" "luks" 2>/dev/null; then
        log_fail "LUKS opened with wrong password (should have failed)"
        return 1
    else
        log_pass "LUKS correctly rejected wrong password"
    fi
    
    # Reopen with correct password for subsequent tests
    echo -n "$TEST_PASSWORD" | unlock_device "$TEST_LOOP_UUID" "$TEST_LUKS_MAPPER" "none" "luks" &>/dev/null
}

# Test 3: Double close handling
test_luks_double_close() {
    run_test "LUKS double close handling"
    
    # Close once
    lock_device "$TEST_LUKS_MAPPER" "luks" &>/dev/null
    
    # Try to close again (library should skip if already closed)
    if lock_device "$TEST_LUKS_MAPPER" "luks" 2>/dev/null; then
        log_pass "Double close handled gracefully"
    else
        log_fail "Double close returned error"
        return 1
    fi
    
    # Reopen for subsequent tests
    echo -n "$TEST_PASSWORD" | unlock_device "$TEST_LOOP_UUID" "$TEST_LUKS_MAPPER" "none" "luks" &>/dev/null
}

# Run all tests
main() {
    echo "========================================="
    echo "LUKS Integration Tests"
    echo "========================================="
    echo ""
    
    test_luks_lock_unlock
    test_luks_wrong_password
    test_luks_double_close
    
    echo ""
    echo "========================================="
    echo "Test Results"
    echo "========================================="
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

main "$@"
