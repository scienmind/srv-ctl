#!/bin/bash
# Integration tests for mount operations

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

# Test 1: Mount and unmount device
test_mount_unmount() {
    run_test "Mount and unmount device"
    
    if mount_device "$TEST_LV_MAPPER" "$TEST_MOUNT_POINT" "defaults"; then
        log_pass "Successfully mounted device"
    else
        log_fail "Failed to mount device"
        return 1
    fi
    
    # Verify it's mounted
    if mountpoint -q "/mnt/$TEST_MOUNT_POINT"; then
        log_pass "Device is mounted"
    else
        log_fail "Device is not mounted"
        return 1
    fi
    
    if unmount_device "$TEST_MOUNT_POINT"; then
        log_pass "Successfully unmounted device"
    else
        log_fail "Failed to unmount device"
        return 1
    fi
    
    # Verify it's unmounted
    if ! mountpoint -q "/mnt/$TEST_MOUNT_POINT"; then
        log_pass "Device is unmounted"
    else
        log_fail "Device is still mounted"
        return 1
    fi
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
        return 1
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
            return 1
        fi
    else
        log_fail "Test file does not exist after remount"
        return 1
    fi
    
    # Cleanup
    rm -f "$test_file"
    unmount_device "$TEST_MOUNT_POINT" &>/dev/null
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
        return 1
    fi
    
    # Cleanup
    unmount_device "$TEST_MOUNT_POINT" &>/dev/null
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
        return 1
    fi
}

# Test 5: Mount with "none" device handling
test_mount_none_device() {
    run_test "Mount with device='none'"
    
    # Mount with "none" device (library should skip)
    if mount_device "none" "test_none" "defaults"; then
        log_pass "mount_device with 'none' device handled correctly"
    else
        log_fail "mount_device with 'none' device returned error"
        return 1
    fi
    
    # Verify nothing was actually mounted
    if ! mountpoint -q "/mnt/test_none"; then
        log_pass "Nothing mounted for 'none' device"
    else
        log_fail "Something was mounted for 'none' device"
        unmount_device "test_none" &>/dev/null
        return 1
    fi
}

# Run all tests
main() {
    echo "========================================="
    echo "Mount Integration Tests"
    echo "========================================="
    echo ""
    
    echo "DEBUG: Starting test_mount_unmount" >&2
    test_mount_unmount || echo "DEBUG: test_mount_unmount returned $?" >&2
    echo "DEBUG: Starting test_mount_write_read" >&2
    test_mount_write_read || echo "DEBUG: test_mount_write_read returned $?" >&2
    echo "DEBUG: Starting test_double_mount" >&2
    test_double_mount || echo "DEBUG: test_double_mount returned $?" >&2
    echo "DEBUG: Starting test_double_unmount" >&2
    test_double_unmount || echo "DEBUG: test_double_unmount returned $?" >&2
    echo "DEBUG: Starting test_mount_none_device" >&2
    test_mount_none_device || echo "DEBUG: test_mount_none_device returned $?" >&2
    
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
