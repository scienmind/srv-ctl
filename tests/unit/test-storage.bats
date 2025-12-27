#!/usr/bin/env bats
# Unit tests for lib/storage.sh

# Setup test environment
setup() {
    # Load the libraries under test
    export SUCCESS=0
    export FAILURE=1
    source "${BATS_TEST_DIRNAME}/../../lib/os-utils.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/storage.sh"
}

# Test function declarations (smoke tests)
@test "wait_for_device function exists" {
    run bash -c 'source lib/storage.sh; declare -F wait_for_device'
    [ "$status" -eq 0 ]
}

@test "verify_lvm function exists" {
    run bash -c 'source lib/storage.sh; declare -F verify_lvm'
    [ "$status" -eq 0 ]
}

@test "lvm_is_active function exists" {
    run bash -c 'source lib/storage.sh; declare -F lvm_is_active'
    [ "$status" -eq 0 ]
}

@test "activate_lvm function exists" {
    run bash -c 'source lib/storage.sh; declare -F activate_lvm'
    [ "$status" -eq 0 ]
}

@test "deactivate_lvm function exists" {
    run bash -c 'source lib/storage.sh; declare -F deactivate_lvm'
    [ "$status" -eq 0 ]
}

@test "unlock_device function exists" {
    run bash -c 'source lib/storage.sh; declare -F unlock_device'
    [ "$status" -eq 0 ]
}

@test "lock_device function exists" {
    run bash -c 'source lib/storage.sh; declare -F lock_device'
    [ "$status" -eq 0 ]
}

@test "mount_device function exists" {
    run bash -c 'source lib/storage.sh; declare -F mount_device'
    [ "$status" -eq 0 ]
}

@test "unmount_device function exists" {
    run bash -c 'source lib/storage.sh; declare -F unmount_device'
    [ "$status" -eq 0 ]
}

@test "mount_network_path function exists" {
    run bash -c 'source lib/storage.sh; declare -F mount_network_path'
    [ "$status" -eq 0 ]
}

# Behavioral testing for storage.sh functions requires root and real devices.
# These smoke tests verify API stability - if a function is renamed or removed,
# these tests will catch the breaking change. Full behavioral coverage is in
# tests/integration/ (run via VM for isolation).
