#!/bin/bash
# Integration tests for mount operations

set -euo pipefail

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
    ((TESTS_PASSED++)) || true
}

fail_test() {
    ((TESTS_FAILED++)) || true
}

# Test 1: Mount and unmount device
test_mount_unmount() {
    run_test "Mount and unmount device"
    
    if mount_device "$TEST_LV_MAPPER" "$TEST_MOUNT_POINT" "defaults"; then
        log_pass "Successfully mounted device"
    else
        log_fail "Failed to mount device"
        return "$FAILURE"
    fi
    
    # Verify it's mounted
    if mountpoint -q "/mnt/$TEST_MOUNT_POINT"; then
        log_pass "Device is mounted"
    else
        log_fail "Device is not mounted"
        return "$FAILURE"
    fi
    
    if unmount_device "$TEST_MOUNT_POINT"; then
        log_pass "Successfully unmounted device"
    else
        log_fail "Failed to unmount device"
        return "$FAILURE"
    fi
    
    # Verify it's unmounted
    if ! mountpoint -q "/mnt/$TEST_MOUNT_POINT"; then
        log_pass "Device is unmounted"
    else
        log_fail "Device is still mounted"
        return "$FAILURE"
    fi
    
    return "$SUCCESS"
}

# Test 2: Write and read test
test_mount_write_read() {
    run_test "Mount, write, unmount, remount, read"
    
    local test_file="/mnt/$TEST_MOUNT_POINT/test_file.txt"
    local test_content="Hello from integration tests!"
    
    mount_device "$TEST_LV_MAPPER" "$TEST_MOUNT_POINT" "defaults" &>/dev/null
    
    # Write test file
    if echo "$test_content" > "$test_file"; then
        log_pass "Successfully wrote test file"
    else
        log_fail "Failed to write test file"
        return "$FAILURE"
    fi
    
    unmount_device "$TEST_MOUNT_POINT" &>/dev/null
    
    # Remount
    mount_device "$TEST_LV_MAPPER" "$TEST_MOUNT_POINT" "defaults" &>/dev/null
    
    # Read and verify
    if [[ -f "$test_file" ]]; then
        local read_content
        read_content=$(cat "$test_file")
        if [[ "$read_content" == "$test_content" ]]; then
            log_pass "Successfully read test file with correct content"
        else
            log_fail "Test file content mismatch"
            return "$FAILURE"
        fi
    else
        log_fail "Test file does not exist after remount"
        return "$FAILURE"
    fi
    
    # Cleanup
    rm -f "$test_file"
    unmount_device "$TEST_MOUNT_POINT" &>/dev/null
    
    return "$SUCCESS"
}

# Test 3: Double mount handling
test_double_mount() {
    run_test "Double mount handling"
    
    # Mount once
    mount_device "$TEST_LV_MAPPER" "$TEST_MOUNT_POINT" "defaults" &>/dev/null
    
    # Try to mount again (library should skip if already mounted)
    if mount_device "$TEST_LV_MAPPER" "$TEST_MOUNT_POINT" "defaults" 2>/dev/null; then
        log_pass "Double mount handled gracefully"
    else
        log_fail "Double mount returned error"
        unmount_device "$TEST_MOUNT_POINT" &>/dev/null
        return "$FAILURE"
    fi
    
    # Cleanup
    unmount_device "$TEST_MOUNT_POINT" &>/dev/null
    
    return "$SUCCESS"
}

# Test 4: Double unmount handling
test_double_unmount() {
    run_test "Double unmount handling"
    
    # Mount first
    mount_device "$TEST_LV_MAPPER" "$TEST_MOUNT_POINT" "defaults" &>/dev/null
    
    # Unmount once
    unmount_device "$TEST_MOUNT_POINT" &>/dev/null
    
    # Try to unmount again (library should skip if not mounted)
    if unmount_device "$TEST_MOUNT_POINT" 2>/dev/null; then
        log_pass "Double unmount handled gracefully"
    else
        log_fail "Double unmount returned error"
        return "$FAILURE"
    fi
    
    return "$SUCCESS"
}

# Test 5: Mount with "none" device handling
test_mount_none_device() {
    run_test "Mount with device='none'"
    
    # Mount with "none" device (library should skip)
    if mount_device "none" "test_none" "defaults"; then
        log_pass "mount_device with 'none' device handled correctly"
    else
        log_fail "mount_device with 'none' device returned error"
        return "$FAILURE"
    fi
    
    # Verify nothing was actually mounted
    if ! mountpoint -q "/mnt/test_none"; then
        log_pass "Nothing mounted for 'none' device"
    else
        log_fail "Something was mounted for 'none' device"
        unmount_device "test_none" &>/dev/null
        return "$FAILURE"
    fi
    
    return "$SUCCESS"
}

# Run all tests
main() {
    echo "========================================="
    echo "Mount Integration Tests"
    echo "========================================="
    echo ""
    
    if test_mount_unmount; then
        pass_test
    else
        fail_test
    fi
    
    if test_mount_write_read; then
        pass_test
    else
        fail_test
    fi
    
    if test_double_mount; then
        pass_test
    else
        fail_test
    fi
    
    if test_double_unmount; then
        pass_test
    else
        fail_test
    fi
    
    if test_mount_none_device; then
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
