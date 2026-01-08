#!/usr/bin/env bats
#
# Integration tests for mount ownership and permission validation
#


setup_file() {
    echo "# Setting up ownership test environment..." >&3
    
    # Create test users if they don't exist
    if ! id test_user_1 &>/dev/null; then
        sudo useradd -r -s /bin/false test_user_1
    fi
    if ! id test_user_2 &>/dev/null; then
        sudo useradd -r -s /bin/false test_user_2
    fi
    
    # Create test groups if they don't exist
    if ! getent group test_group_1 &>/dev/null; then
        sudo groupadd test_group_1
    fi
    if ! getent group test_group_2 &>/dev/null; then
        sudo groupadd test_group_2
    fi
    
    # Create test loop device
    TEST_LOOP_IMG="/tmp/test-ownership.img"
    dd if=/dev/zero of="$TEST_LOOP_IMG" bs=1M count=100 2>/dev/null
    TEST_LOOP_DEV=$(sudo losetup -f --show "$TEST_LOOP_IMG")
    
    # Format with LUKS
    echo -n "test_password" | sudo cryptsetup luksFormat --type luks2 "$TEST_LOOP_DEV" -
    
    # Create and add key file
    echo -n "test_password" > /tmp/test_ownership_key.key
    chmod 600 /tmp/test_ownership_key.key
    echo -n "test_password" | sudo cryptsetup luksAddKey "$TEST_LOOP_DEV" /tmp/test_ownership_key.key -
    
    TEST_UUID=$(sudo cryptsetup luksUUID "$TEST_LOOP_DEV")
    
    echo "# Test environment ready (UUID: $TEST_UUID)" >&3
    
    export TEST_LOOP_DEV TEST_UUID TEST_LOOP_IMG
}

teardown_file() {
    echo "# Cleaning up ownership test environment..." >&3
    
    # Unmount and close
    sudo umount /mnt/test_ownership_* 2>/dev/null || true
    sudo cryptsetup close test_ownership_mapper 2>/dev/null || true
    
    # Detach loop device
    if [ -n "$TEST_LOOP_DEV" ]; then
        sudo losetup -d "$TEST_LOOP_DEV" 2>/dev/null || true
    fi
    
    # Remove temp files
    rm -f /tmp/test_ownership_key.key
    rm -f "$TEST_LOOP_IMG"
    
    # Note: We don't delete test users/groups as they may be used by other tests
    # and deleting users can be problematic if processes are running as those users
}

setup() {
    export SUCCESS=0 FAILURE=1
    source lib/os-utils.sh
    source lib/storage.sh
    
    # Ensure device is unlocked and formatted for each test
    if ! cryptsetup status test_ownership_mapper >/dev/null 2>&1; then
        sudo cryptsetup open --type luks --key-file=/tmp/test_ownership_key.key \
            "$TEST_LOOP_DEV" test_ownership_mapper
        
        # Format if not already formatted
        if ! sudo blkid /dev/mapper/test_ownership_mapper | grep -q ext4; then
            sudo mkfs.ext4 -q /dev/mapper/test_ownership_mapper
        fi
    fi
}

teardown() {
    # Clean up mount points
    sudo umount /mnt/test_ownership_* 2>/dev/null || true
    sudo rmdir /mnt/test_ownership_* 2>/dev/null || true
}

# =============================================================================
# Non-Root Mount Ownership Tests
# =============================================================================

@test "mount with non-root user ownership" {
    # Mount with user ownership
    run mount_device "test_ownership_mapper" "test_ownership_user" "defaults" "test_user_1" "none"
    [ "$status" -eq "$SUCCESS" ]
    
    # Verify ownership
    local owner
    owner=$(stat -c '%U' /mnt/test_ownership_user)
    [ "$owner" = "test_user_1" ]
}

@test "mount with non-root group ownership" {
    # Mount with group ownership
    run mount_device "test_ownership_mapper" "test_ownership_group" "defaults" "none" "test_group_1"
    [ "$status" -eq "$SUCCESS" ]
    
    # Verify ownership
    local group
    group=$(stat -c '%G' /mnt/test_ownership_group)
    [ "$group" = "test_group_1" ]
}

@test "mount with both user and group ownership" {
    # Mount with both user and group
    run mount_device "test_ownership_mapper" "test_ownership_both" "defaults" "test_user_2" "test_group_2"
    [ "$status" -eq "$SUCCESS" ]
    
    # Verify ownership
    local owner group
    owner=$(stat -c '%U' /mnt/test_ownership_both)
    group=$(stat -c '%G' /mnt/test_ownership_both)
    [ "$owner" = "test_user_2" ]
    [ "$group" = "test_group_2" ]
}

# =============================================================================
# ST_USER Service User Tests
# =============================================================================

@test "validate-config - ST_USER_1 scenarios" {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    
    # Backup config
    [ -f "$PROJECT_ROOT/config.local" ] && cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="test_user_1"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="syncthing@test_user_1.service"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="none"
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
    [[ "$output" =~ "test_user_1" ]]
    
    # Restore config
    [ -f "$PROJECT_ROOT/config.local.backup" ] && mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
}

@test "validate-config - ST_USER_2 scenarios" {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    
    # Backup config
    [ -f "$PROJECT_ROOT/config.local" ] && cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="test_user_2"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="syncthing@test_user_2.service"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="none"
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
    [[ "$output" =~ "test_user_2" ]]
    
    # Restore config
    [ -f "$PROJECT_ROOT/config.local.backup" ] && mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
}

@test "validate-config - both ST_USER_1 and ST_USER_2" {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    
    # Backup config
    [ -f "$PROJECT_ROOT/config.local" ] && cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="test_user_1"
readonly ST_USER_2="test_user_2"
readonly ST_SERVICE_1="syncthing@test_user_1.service"
readonly ST_SERVICE_2="syncthing@test_user_2.service"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="none"
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
    [[ "$output" =~ "test_user_1" ]]
    [[ "$output" =~ "test_user_2" ]]
    
    # Restore config
    [ -f "$PROJECT_ROOT/config.local.backup" ] && mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
}

@test "validate-config - ST_USER set but service empty" {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    
    # Backup config
    [ -f "$PROJECT_ROOT/config.local" ] && cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="test_user_1"
readonly ST_USER_2="none"
readonly ST_SERVICE_1=""
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="none"
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
    [[ "$output" =~ "service empty" ]] || [[ "$output" =~ "❌" ]]
    
    # Restore config
    [ -f "$PROJECT_ROOT/config.local.backup" ] && mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
}

# =============================================================================
# Group Ownership Validation Tests
# =============================================================================

@test "validate-config - OWNER_GROUP specified for device" {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    
    # Backup config
    [ -f "$PROJECT_ROOT/config.local" ] && cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid"
readonly PRIMARY_DATA_KEY_FILE="none"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="test_group_1"
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
    [[ "$output" =~ "test_group_1" ]] || [[ "$output" =~ "✅" ]]
    
    # Restore config
    [ -f "$PROJECT_ROOT/config.local.backup" ] && mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
}

@test "validate-config - OWNER_USER and OWNER_GROUP both specified" {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    
    # Backup config
    [ -f "$PROJECT_ROOT/config.local" ] && cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid"
readonly PRIMARY_DATA_KEY_FILE="none"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="test_user_1"
readonly PRIMARY_DATA_OWNER_GROUP="test_group_1"
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
    [[ "$output" =~ "✅" ]]
    
    # Restore config
    [ -f "$PROJECT_ROOT/config.local.backup" ] && mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
}

@test "validate-config - nonexistent OWNER_USER" {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    
    # Backup config
    [ -f "$PROJECT_ROOT/config.local" ] && cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid"
readonly PRIMARY_DATA_KEY_FILE="none"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="nonexistent_user_xyz"
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
    [[ "$output" =~ "does not exist" ]] || [[ "$output" =~ "❌" ]]
    
    # Restore config
    [ -f "$PROJECT_ROOT/config.local.backup" ] && mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
}

@test "validate-config - nonexistent OWNER_GROUP" {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    
    # Backup config
    [ -f "$PROJECT_ROOT/config.local" ] && cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.backup"
    
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"

readonly PRIMARY_DATA_UUID="12345678-fake-uuid"
readonly PRIMARY_DATA_KEY_FILE="none"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="luks"
readonly PRIMARY_DATA_MAPPER="test-mapper"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="test-mount"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="nonexistent_group_xyz"
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
    [[ "$output" =~ "does not exist" ]] || [[ "$output" =~ "❌" ]]
    
    # Restore config
    [ -f "$PROJECT_ROOT/config.local.backup" ] && mv "$PROJECT_ROOT/config.local.backup" "$PROJECT_ROOT/config.local"
}
