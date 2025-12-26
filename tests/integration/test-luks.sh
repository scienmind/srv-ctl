#!/bin/bash
# Integration tests for LUKS operations

set -euo pipefail

# Debug mode - set TEST_DEBUG=1 to enable verbose output
DEBUG="${TEST_DEBUG:-0}"
debug() { [[ "$DEBUG" == "1" ]] && echo "DEBUG: $*" >&2 || true; }

# Trap errors to show what failed
trap 'echo "ERROR: Command failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# Load test environment
debug "Loading test environment from /tmp/test_env.conf"
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
debug "Libraries loaded successfully"

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
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

run_test() {
    ((TESTS_RUN++))
    log_test "$1"
}

pass_test() {
    ((TESTS_PASSED++))
}

fail_test() {
    ((TESTS_FAILED++))
}

# Test 1: Close and reopen LUKS container
test_luks_lock_unlock() {
    debug "Inside test_luks_lock_unlock"
    run_test "LUKS lock and unlock"
    
    # Deactivate LVM first (LUKS can't be closed while in use)
    lvchange -an "$TEST_VG_NAME/$TEST_LV_NAME" 2>/dev/null && log_pass "Deactivated LVM logical volume" || log_warn "LVM already inactive or deactivation failed"
    vgchange -an "$TEST_VG_NAME" 2>/dev/null && log_pass "Deactivated volume group" || log_warn "VG already inactive"
    
    # Wait for device to be released
    sleep 1
    udevadm settle
    
    debug "About to call lock_device"
    if lock_device "$TEST_LUKS_MAPPER" "luks"; then
        log_pass "Successfully closed LUKS container"
    else
        log_fail "Failed to close LUKS container"
        return "$FAILURE"
    fi
    
    # Verify it's closed
    if [[ ! -e "/dev/mapper/$TEST_LUKS_MAPPER" ]]; then
        log_pass "LUKS container is closed"
    else
        log_fail "LUKS container still exists after close"
        return "$FAILURE"
    fi
    
    # Reopen LUKS using UUID
    if echo -n "$TEST_PASSWORD" | unlock_device "$TEST_LOOP_UUID" "$TEST_LUKS_MAPPER" "none" "luks"; then
        log_pass "Successfully reopened LUKS container"
    else
        log_fail "Failed to reopen LUKS container"
        return "$FAILURE"
    fi
    
    # Verify it's open
    if [[ -e "/dev/mapper/$TEST_LUKS_MAPPER" ]]; then
        log_pass "LUKS container is open"
    else
        log_fail "LUKS container does not exist after open"
        return "$FAILURE"
    fi
    
    # Reactivate LVM for subsequent tests
    vgchange -ay "$TEST_VG_NAME" 2>/dev/null && log_pass "Reactivated volume group" || log_warn "Failed to reactivate VG"
    lvchange -ay "$TEST_VG_NAME/$TEST_LV_NAME" 2>/dev/null && log_pass "Reactivated LVM after reopening LUKS" || log_warn "Failed to reactivate LVM"
    
    return "$SUCCESS"
}

# Test 2: Wrong password handling
test_luks_wrong_password() {
    run_test "LUKS wrong password handling"
    
    # Deactivate LVM completely (LV + VG)
    lvchange -an "$TEST_VG_NAME/$TEST_LV_NAME" 2>/dev/null && log_pass "Deactivated LVM logical volume" || log_warn "Failed to deactivate LVM"
    vgchange -an "$TEST_VG_NAME" 2>/dev/null && log_pass "Deactivated volume group" || log_warn "Failed to deactivate VG"
    
    # Wait for device to be released
    sleep 1
    udevadm settle
    
    if lock_device "$TEST_LUKS_MAPPER" "luks"; then
        log_pass "Closed LUKS container"
    else
        log_fail "Failed to close LUKS"
        return "$FAILURE"
    fi
    
    # Try to open with wrong password
    if echo -n "wrongpassword" | unlock_device "$TEST_LOOP_UUID" "$TEST_LUKS_MAPPER" "none" "luks" 2>/dev/null; then
        log_fail "LUKS opened with wrong password (should have failed)"
        return "$FAILURE"
    else
        log_pass "LUKS correctly rejected wrong password"
    fi
    
    # Reopen with correct password for subsequent tests
    echo -n "$TEST_PASSWORD" | unlock_device "$TEST_LOOP_UUID" "$TEST_LUKS_MAPPER" "none" "luks" &>/dev/null
    vgchange -ay "$TEST_VG_NAME" 2>/dev/null || true
    lvchange -ay "$TEST_VG_NAME/$TEST_LV_NAME" 2>/dev/null || true
    
    return "$SUCCESS"
}

# Test 3: Double close handling
test_luks_double_close() {
    run_test "LUKS double close handling"
    
    # Deactivate LVM completely
    lvchange -an "$TEST_VG_NAME/$TEST_LV_NAME" 2>/dev/null || true
    vgchange -an "$TEST_VG_NAME" 2>/dev/null || true
    sleep 1
    udevadm settle
    
    # Close once
    lock_device "$TEST_LUKS_MAPPER" "luks" &>/dev/null
    
    # Try to close again (library should skip if already closed)
    if lock_device "$TEST_LUKS_MAPPER" "luks" 2>/dev/null; then
        log_pass "Double close handled gracefully"
    else
        log_fail "Double close returned error"
        return "$FAILURE"
    fi
    
    # Reopen for subsequent tests
    echo -n "$TEST_PASSWORD" | unlock_device "$TEST_LOOP_UUID" "$TEST_LUKS_MAPPER" "none" "luks" &>/dev/null
    vgchange -ay "$TEST_VG_NAME" 2>/dev/null || true
    lvchange -ay "$TEST_VG_NAME/$TEST_LV_NAME" 2>/dev/null || true
    
    return "$SUCCESS"
}

# Run all tests
main() {
    echo "========================================="
    echo "LUKS Integration Tests"
    echo "========================================="
    echo ""
    
    if test_luks_lock_unlock; then
        pass_test
    else
        fail_test
    fi
    
    if test_luks_wrong_password; then
        pass_test
    else
        fail_test
    fi
    
    if test_luks_double_close; then
        pass_test
    else
        fail_test
    fi
    
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
