#!/bin/bash
# Integration tests for LVM operations

set -euo pipefail

# Trap errors to show what failed
trap 'echo "ERROR: Command failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# Load test environment
echo "DEBUG: Loading test environment from /tmp/test_env.conf" >&2
if [[ ! -f /tmp/test_env.conf ]]; then
    echo "ERROR: Test environment not setup. Run setup-test-env.sh first."
    exit 1
fi
source /tmp/test_env.conf
echo "DEBUG: Test environment loaded" >&2

# Load libraries
echo "DEBUG: Setting up constants" >&2
export SUCCESS=0
export FAILURE=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "DEBUG: SCRIPT_DIR=$SCRIPT_DIR" >&2
echo "DEBUG: Loading lib/os-utils.sh" >&2
source "$SCRIPT_DIR/../../lib/os-utils.sh"
echo "DEBUG: Loading lib/storage.sh" >&2
source "$SCRIPT_DIR/../../lib/storage.sh"
echo "DEBUG: Libraries loaded successfully" >&2

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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

run_test() {
    ((TESTS_RUN++))
    log_test "$1"
}

# Test 1: Verify LVM
test_lvm_verify() {
    run_test "LVM verification"
    
    if verify_lvm "$TEST_LV_NAME" "$TEST_VG_NAME"; then
        log_pass "LVM verification successful"
    else
        log_fail "LVM verification failed"
        return 1
    fi
}

# Test 2: Check if LVM is active
test_lvm_is_active() {
    run_test "LVM active check"
    
    if lvm_is_active "$TEST_LV_NAME" "$TEST_VG_NAME"; then
        log_pass "LVM is active"
    else
        log_fail "LVM is not active"
        return 1
    fi
}

# Test 3: Deactivate and reactivate LVM
test_lvm_deactivate_activate() {
    run_test "LVM deactivate and reactivate"
    
    # Deactivate
    if deactivate_lvm "$TEST_LV_NAME" "$TEST_VG_NAME"; then
        log_pass "Successfully deactivated LVM"
    else
        log_fail "Failed to deactivate LVM"
        return 1
    fi
    
    # Verify it's inactive
    if ! lvm_is_active "$TEST_LV_NAME" "$TEST_VG_NAME"; then
        log_pass "LVM is inactive"
    else
        log_fail "LVM is still active after deactivation"
        return 1
    fi
    
    # Reactivate
    if activate_lvm "$TEST_LV_NAME" "$TEST_VG_NAME"; then
        log_pass "Successfully reactivated LVM"
    else
        log_fail "Failed to reactivate LVM"
        return 1
    fi
    
    # Verify it's active
    if lvm_is_active "$TEST_LV_NAME" "$TEST_VG_NAME"; then
        log_pass "LVM is active after reactivation"
    else
        log_fail "LVM is not active after reactivation"
        return 1
    fi
}

# Test 4: Double deactivation handling
test_lvm_double_deactivate() {
    run_test "LVM double deactivation handling"
    
    # Deactivate once
    deactivate_lvm "$TEST_LV_NAME" "$TEST_VG_NAME" &>/dev/null
    
    # Try to deactivate again
    if deactivate_lvm "$TEST_LV_NAME" "$TEST_VG_NAME" 2>/dev/null; then
        log_pass "Double deactivation handled gracefully"
    else
        log_fail "Double deactivation returned error"
        return 1
    fi
    
    # Reactivate for subsequent tests
    activate_lvm "$TEST_LV_NAME" "$TEST_VG_NAME" &>/dev/null
}

# Test 5: Verify nonexistent VG/LV
test_lvm_verify_nonexistent() {
    run_test "LVM verify nonexistent volume"
    
    if verify_lvm "nonexistent_lv" "nonexistent_vg" 2>/dev/null; then
        log_fail "verify_lvm succeeded for nonexistent volume (should fail)"
        return 1
    else
        log_pass "verify_lvm correctly failed for nonexistent volume"
    fi
}

# Run all tests
main() {
    echo "========================================="
    echo "LVM Integration Tests"
    echo "========================================="
    echo ""
    
    echo "DEBUG: Starting test_lvm_verify" >&2
    test_lvm_verify || echo "DEBUG: test_lvm_verify returned $?" >&2
    echo "DEBUG: Starting test_lvm_is_active" >&2
    test_lvm_is_active || echo "DEBUG: test_lvm_is_active returned $?" >&2
    echo "DEBUG: Starting test_lvm_deactivate_activate" >&2
    test_lvm_deactivate_activate || echo "DEBUG: test_lvm_deactivate_activate returned $?" >&2
    echo "DEBUG: Starting test_lvm_double_deactivate" >&2
    test_lvm_double_deactivate || echo "DEBUG: test_lvm_double_deactivate returned $?" >&2
    echo "DEBUG: Starting test_lvm_verify_nonexistent" >&2
    test_lvm_verify_nonexistent || echo "DEBUG: test_lvm_verify_nonexistent returned $?" >&2
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
