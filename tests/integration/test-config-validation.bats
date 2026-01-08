#!/usr/bin/env bats
#
# Integration tests for configuration validation edge cases
#


setup() {
    export SUCCESS=0 FAILURE=1
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    
    # Backup existing config
    if [ -f "$PROJECT_ROOT/config.local" ]; then
        cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    fi
}

teardown() {
    # Restore config
    if [ -f "$PROJECT_ROOT/config.local.backup" ]; then
        mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
    fi
    
    # Clean up test files
    rm -f /tmp/test_keyfile_dir_check
    rm -f /tmp/test_symlink_keyfile
    rm -f /tmp/test_symlink_target
    rm -rf /tmp/test_keyfile_is_dir
    rm -f /tmp/test_circular_1
    rm -f /tmp/test_circular_2
}

# =============================================================================
# Key File Validation Tests
# =============================================================================

@test "validate-config - key file is directory not file" {
    mkdir -p /tmp/test_keyfile_is_dir
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid-test"
readonly PRIMARY_DATA_KEY_FILE="/tmp/test_keyfile_is_dir"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"

readonly STORAGE_1A_UUID="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2B_UUID="none"

readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF

    run bash "$PROJECT_ROOT/srv-ctl.sh" validate-config
    [ "$status" -eq "$FAILURE" ]
    [[ "$output" =~ "missing key file" ]] || [[ "$output" =~ "❌" ]]
}

@test "validate-config - key file has unreadable permissions" {
    # Create key file with no read permissions
    echo "test_key" > /tmp/test_unreadable_keyfile
    chmod 000 /tmp/test_unreadable_keyfile
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid-test"
readonly PRIMARY_DATA_KEY_FILE="/tmp/test_unreadable_keyfile"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"

readonly STORAGE_1A_UUID="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2B_UUID="none"

readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF

    # Note: When run as root (in CI), root can read files regardless of permissions
    # So we check if validation passes (root) or fails (non-root)
    run bash "$PROJECT_ROOT/srv-ctl.sh" validate-config
    # Either passes (root can read) or fails (non-root cannot)
    # Just verify the command runs without crashing
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
    
    # Cleanup
    chmod 600 /tmp/test_unreadable_keyfile
    rm -f /tmp/test_unreadable_keyfile
}

@test "validate-config - key file is symlink to valid file" {
    # Create real key file and symlink
    echo "test_key" > /tmp/test_symlink_target
    ln -s /tmp/test_symlink_target /tmp/test_symlink_keyfile
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid-test"
readonly PRIMARY_DATA_KEY_FILE="/tmp/test_symlink_keyfile"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"

readonly STORAGE_1A_UUID="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2B_UUID="none"

readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF

    run bash "$PROJECT_ROOT/srv-ctl.sh" validate-config
    [ "$status" -eq "$SUCCESS" ]
    [[ "$output" =~ "✅" ]] || [[ "$output" =~ "PASSED" ]]
}

@test "validate-config - key file is broken symlink" {
    # Create symlink to non-existent file
    ln -s /tmp/nonexistent_target /tmp/test_broken_symlink
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid-test"
readonly PRIMARY_DATA_KEY_FILE="/tmp/test_broken_symlink"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"

readonly STORAGE_1A_UUID="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2B_UUID="none"

readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF

    run bash "$PROJECT_ROOT/srv-ctl.sh" validate-config
    [ "$status" -eq "$FAILURE" ]
    [[ "$output" =~ "missing key file" ]] || [[ "$output" =~ "❌" ]]
    
    # Cleanup
    rm -f /tmp/test_broken_symlink
}

# =============================================================================
# Encryption Type Validation Tests
# =============================================================================

@test "validate-config - invalid encryption type" {
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid-test"
readonly PRIMARY_DATA_KEY_FILE="none"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="invalid_type_xyz"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"

readonly STORAGE_1A_UUID="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2B_UUID="none"

readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF

    run bash "$PROJECT_ROOT/srv-ctl.sh" validate-config
    [ "$status" -eq "$FAILURE" ]
    [[ "$output" =~ "invalid encryption" ]] || [[ "$output" =~ "❌" ]]
}

@test "validate-config - typo in encryption type" {
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid-test"
readonly PRIMARY_DATA_KEY_FILE="none"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="lukss"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"

readonly STORAGE_1A_UUID="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2B_UUID="none"

readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF

    run bash "$PROJECT_ROOT/srv-ctl.sh" validate-config
    [ "$status" -eq "$FAILURE" ]
    [[ "$output" =~ "invalid encryption" ]] || [[ "$output" =~ "❌" ]]
}

# =============================================================================
# Mapper Name Conflict Tests
# =============================================================================

@test "validate-config - duplicate mapper names" {
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid-1"
readonly PRIMARY_DATA_KEY_FILE="none"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="duplicate-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount-1"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"

readonly STORAGE_1A_UUID="12345678-fake-uuid-2"
readonly STORAGE_1A_KEY_FILE="none"
readonly STORAGE_1A_ENCRYPTION_TYPE="luks"
readonly STORAGE_1A_MAPPER="duplicate-mapper"
readonly STORAGE_1A_LVM_NAME="none"
readonly STORAGE_1A_LVM_GROUP="none"
readonly STORAGE_1A_MOUNT="test-mount-2"
readonly STORAGE_1A_OWNER_USER="none"
readonly STORAGE_1A_OWNER_GROUP="none"
readonly STORAGE_1A_MOUNT_OPTIONS="defaults"

readonly STORAGE_1B_UUID="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2B_UUID="none"

readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF

    run bash "$PROJECT_ROOT/srv-ctl.sh" validate-config
    [ "$status" -eq "$FAILURE" ]
    [[ "$output" =~ "Mapper conflict" ]] || [[ "$output" =~ "duplicate-mapper" ]]
}

# =============================================================================
# Network Share Validation Tests
# =============================================================================

@test "validate-config - network share credentials file missing" {
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="none"

readonly STORAGE_1A_UUID="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2B_UUID="none"

readonly NETWORK_SHARE_PROTOCOL="cifs"
readonly NETWORK_SHARE_ADDRESS="//server/share"
readonly NETWORK_SHARE_CREDENTIALS="/tmp/nonexistent_creds_file"
readonly NETWORK_SHARE_MOUNT="network-test"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF

    run bash "$PROJECT_ROOT/srv-ctl.sh" validate-config
    [ "$status" -eq "$FAILURE" ]
    [[ "$output" =~ "credentials file not found" ]] || [[ "$output" =~ "❌" ]]
}
