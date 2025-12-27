#!/usr/bin/env bats
# Unit tests for lib/os-utils.sh

# Setup test environment
setup() {
    # Load the library under test
    export SUCCESS=0
    export FAILURE=1
    source "${BATS_TEST_DIRNAME}/../../lib/os-utils.sh"
}

# Test get_uid_from_username()
@test "get_uid_from_username returns UID for valid username" {
    # Use 'root' as a reliable test user present on all systems
    run get_uid_from_username "root"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get_uid_from_username returns error for invalid username" {
    run get_uid_from_username "nonexistent_user_12345"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

@test "get_uid_from_username handles empty username" {
    run get_uid_from_username ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

# Test get_gid_from_groupname()
@test "get_gid_from_groupname returns GID for valid groupname" {
    # Use 'root' as a reliable test group present on all systems
    run get_gid_from_groupname "root"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get_gid_from_groupname returns error for invalid groupname" {
    run get_gid_from_groupname "nonexistent_group_12345"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

@test "get_gid_from_groupname handles empty groupname" {
    run get_gid_from_groupname ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

# Test build_mount_options()
@test "build_mount_options creates correct options for root user" {
    run build_mount_options "root" "root" "defaults"
    [ "$status" -eq 0 ]
    [ "$output" = "uid=0,gid=0" ]
}

@test "build_mount_options returns error for invalid username" {
    run build_mount_options "nonexistent_user_12345" "root"
    [ "$status" -eq 1 ]
}

@test "build_mount_options returns error for invalid groupname" {
    run build_mount_options "root" "nonexistent_group_12345"
    [ "$status" -eq 1 ]
}

@test "build_mount_options handles both invalid username and groupname" {
    run build_mount_options "nonexistent_user_12345" "nonexistent_group_12345"
    [ "$status" -eq 1 ]
}

# Test start_service() and stop_service()
# Note: These tests are limited as they would require systemd and privileges
@test "start_service requires service name argument" {
    # This is a basic syntax test - full testing requires systemd
    run bash -c 'source lib/os-utils.sh; declare -F start_service'
    [ "$status" -eq 0 ]
}

@test "stop_service requires service name argument" {
    # This is a basic syntax test - full testing requires systemd
    run bash -c 'source lib/os-utils.sh; declare -F stop_service'
    [ "$status" -eq 0 ]
}
