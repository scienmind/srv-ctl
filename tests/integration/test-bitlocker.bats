#!/usr/bin/env bats
# Integration tests for BitLocker encryption support
# Requires cryptsetup 2.4.0+ with BitLocker support

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_BITLOCKER_FIXTURE="$PROJECT_ROOT/tests/fixtures/bitlocker/bitlocker-test.img"
    export TEST_BITLOCKER_IMAGE="/tmp/test-bitlocker.img"
    export TEST_BITLOCKER_MAPPER="test_bitlocker"
    export TEST_BITLOCKER_PASSWORD="TestBitLocker123"
    export TEST_BITLOCKER_KEY_FILE="/tmp/test-bitlocker-key"
    export SUCCESS=0
    export FAILURE=1
    
    # Check if cryptsetup supports BitLocker unlocking
    if ! cryptsetup --help | grep -q "bitlk"; then
        skip "BitLocker support not available in cryptsetup (requires 2.4.0+)"
    fi
    
    echo "Setting up BitLocker test environment..."
    
    # Check if pre-created BitLocker fixture exists
    if [ -f "$TEST_BITLOCKER_FIXTURE" ]; then
        echo "Using pre-created BitLocker test image"
        cp "$TEST_BITLOCKER_FIXTURE" "$TEST_BITLOCKER_IMAGE"
    else
        echo "Pre-created BitLocker fixture not found, attempting to create with cryptsetup..."
        # Try to create with cryptsetup (may fail if it only supports unlocking)
        dd if=/dev/zero of="$TEST_BITLOCKER_IMAGE" bs=1M count=100 2>/dev/null
        
        # Setup loop device for creation attempt
        local temp_loop=$(sudo losetup -f --show "$TEST_BITLOCKER_IMAGE")
        
        if ! echo "$TEST_BITLOCKER_PASSWORD" | sudo cryptsetup luksFormat --type bitlk "$temp_loop" - 2>/dev/null; then
            sudo losetup -d "$temp_loop" 2>/dev/null || true
            rm -f "$TEST_BITLOCKER_IMAGE"
            skip "BitLocker fixture not available and cryptsetup cannot create BitLocker volumes. See tests/fixtures/bitlocker/README.md"
        fi
        
        sudo losetup -d "$temp_loop" 2>/dev/null || true
    fi
    
    # Setup loop device for testing (with partition scanning for disk images)
    export TEST_BITLOCKER_LOOP=$(sudo losetup -f --show -P "$TEST_BITLOCKER_IMAGE")
    
    # If using a disk image with partitions, use partition 1
    if [ -b "${TEST_BITLOCKER_LOOP}p1" ]; then
        export TEST_BITLOCKER_DEVICE="${TEST_BITLOCKER_LOOP}p1"
    else
        export TEST_BITLOCKER_DEVICE="$TEST_BITLOCKER_LOOP"
    fi
    
    # Create key file
    echo "$TEST_BITLOCKER_PASSWORD" > "$TEST_BITLOCKER_KEY_FILE"
    chmod 600 "$TEST_BITLOCKER_KEY_FILE"
    
    # Get UUID
    export TEST_BITLOCKER_UUID=$(sudo cryptsetup luksUUID "$TEST_BITLOCKER_DEVICE" 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")
    echo "BitLocker UUID: $TEST_BITLOCKER_UUID" >&3
    echo "BitLocker Device: $TEST_BITLOCKER_DEVICE" >&3
    
    # Create symlink for UUID-based device lookup (for testing)
    sudo mkdir -p /dev/disk/by-uuid
    sudo ln -sf "$TEST_BITLOCKER_DEVICE" "/dev/disk/by-uuid/$TEST_BITLOCKER_UUID" 2>/dev/null || true
    
    # Verify symlink was created
    if [ -L "/dev/disk/by-uuid/$TEST_BITLOCKER_UUID" ]; then
        echo "UUID symlink created successfully" >&3
    else
        echo "WARNING: UUID symlink creation failed" >&3
    fi
    
    # Source the library
    source "$PROJECT_ROOT/lib/storage.sh"
}

teardown_file() {
    # Cleanup UUID symlink
    sudo rm -f "/dev/disk/by-uuid/$TEST_BITLOCKER_UUID" 2>/dev/null || true
    
    # Cleanup
    sudo cryptsetup close "$TEST_BITLOCKER_MAPPER" 2>/dev/null || true
    sudo losetup -d "$TEST_BITLOCKER_LOOP" 2>/dev/null || true
    rm -f "$TEST_BITLOCKER_IMAGE"
    rm -f "$TEST_BITLOCKER_KEY_FILE"
}

teardown() {
    # Ensure device is closed after each test
    sudo cryptsetup close "$TEST_BITLOCKER_MAPPER" 2>/dev/null || true
}

@test "BitLocker: Unlock device with key file" {
    run sudo bash -c "source $PROJECT_ROOT/lib/storage.sh; unlock_device $TEST_BITLOCKER_UUID $TEST_BITLOCKER_MAPPER $TEST_BITLOCKER_KEY_FILE bitlocker"
    if [ "$status" -ne 0 ]; then
        echo "unlock_device failed with status: $status" >&3
        echo "Output: $output" >&3
        echo "UUID: $TEST_BITLOCKER_UUID" >&3
        echo "Device: $TEST_BITLOCKER_DEVICE" >&3
        ls -l "/dev/disk/by-uuid/$TEST_BITLOCKER_UUID" >&3 || echo "UUID symlink not found" >&3
    fi
    [ "$status" -eq 0 ]
    run sudo cryptsetup status "$TEST_BITLOCKER_MAPPER"
    [ "$status" -eq 0 ]
}

@test "BitLocker: Device already unlocked (idempotent)" {
    # Unlock first time
    echo "$TEST_BITLOCKER_PASSWORD" | sudo cryptsetup open --type bitlk "$TEST_BITLOCKER_DEVICE" "$TEST_BITLOCKER_MAPPER"
    
    # Try to unlock again
    run sudo bash -c "source $PROJECT_ROOT/lib/storage.sh; unlock_device $TEST_BITLOCKER_UUID $TEST_BITLOCKER_MAPPER $TEST_BITLOCKER_KEY_FILE bitlocker"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "unlocked. Skipping" ]]
}

@test "BitLocker: Wrong key file" {
    echo "wrongpassword" > /tmp/wrong-bitlocker-key
    chmod 600 /tmp/wrong-bitlocker-key
    
    run sudo bash -c "source $PROJECT_ROOT/lib/storage.sh; unlock_device $TEST_BITLOCKER_UUID $TEST_BITLOCKER_MAPPER /tmp/wrong-bitlocker-key bitlocker"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Failed to unlock BitLocker" ]]
    
    rm -f /tmp/wrong-bitlocker-key
}

@test "BitLocker: Missing key file" {
    run sudo bash -c "source $PROJECT_ROOT/lib/storage.sh; unlock_device $TEST_BITLOCKER_UUID $TEST_BITLOCKER_MAPPER /nonexistent/key bitlocker"
    [ "$status" -ne 0 ]
}

@test "BitLocker: Key file set to 'none'" {
    # This should trigger interactive password mode
    # We can't test interactive mode in automated tests, so we expect failure
    run timeout 2 sudo bash -c "source $PROJECT_ROOT/lib/storage.sh; unlock_device $TEST_BITLOCKER_UUID $TEST_BITLOCKER_MAPPER none bitlocker" < /dev/null
    [ "$status" -ne 0 ]
}

@test "BitLocker: Lock device" {
    # Unlock first
    echo "$TEST_BITLOCKER_PASSWORD" | sudo cryptsetup open --type bitlk "$TEST_BITLOCKER_DEVICE" "$TEST_BITLOCKER_MAPPER"
    
    # Verify it's unlocked
    run sudo cryptsetup status "$TEST_BITLOCKER_MAPPER"
    [ "$status" -eq 0 ]
    
    # Lock it
    run sudo bash -c "source $PROJECT_ROOT/lib/storage.sh; lock_device $TEST_BITLOCKER_MAPPER bitlocker"
    [ "$status" -eq 0 ]
    
    # Verify it's locked
    run sudo cryptsetup status "$TEST_BITLOCKER_MAPPER"
    [ "$status" -ne 0 ]
}

@test "BitLocker: Lock already locked device (idempotent)" {
    # Ensure it's closed
    sudo cryptsetup close "$TEST_BITLOCKER_MAPPER" 2>/dev/null || true
    
    # Try to lock
    run sudo bash -c "source $PROJECT_ROOT/lib/storage.sh; lock_device $TEST_BITLOCKER_MAPPER bitlocker"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "locked. Skipping" ]]
}

@test "BitLocker: UUID and mapper set to 'none'" {
    run sudo bash -c "source $PROJECT_ROOT/lib/storage.sh; unlock_device none none none bitlocker"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "not configured" ]]
}

@test "BitLocker: Integration with srv-ctl.sh via config" {
    # Create temporary config with BitLocker device
    local config_file="$PROJECT_ROOT/config.local"
    cat > "$config_file" <<EOF
#!/usr/bin/env bash
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_SERVICE_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"
readonly PRIMARY_DATA_UUID="$TEST_BITLOCKER_UUID"
readonly PRIMARY_DATA_KEY_FILE="$TEST_BITLOCKER_KEY_FILE"
readonly PRIMARY_DATA_ENCRYPTION_TYPE="bitlocker"
readonly PRIMARY_DATA_MAPPER="$TEST_BITLOCKER_MAPPER"
readonly PRIMARY_DATA_LVM_NAME="none"
readonly PRIMARY_DATA_LVM_GROUP="none"
readonly PRIMARY_DATA_MOUNT="none"
readonly PRIMARY_DATA_OWNER_USER="none"
readonly PRIMARY_DATA_OWNER_GROUP="none"
readonly PRIMARY_DATA_MOUNT_OPTIONS="defaults"
readonly STORAGE_1A_UUID="none"
readonly STORAGE_1A_KEY_FILE="none"
readonly STORAGE_1A_ENCRYPTION_TYPE="luks"
readonly STORAGE_1A_MAPPER="none"
readonly STORAGE_1A_LVM_NAME="none"
readonly STORAGE_1A_LVM_GROUP="none"
readonly STORAGE_1A_MOUNT="none"
readonly STORAGE_1A_OWNER_USER="none"
readonly STORAGE_1A_OWNER_GROUP="none"
readonly STORAGE_1A_MOUNT_OPTIONS="defaults"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_1B_KEY_FILE="none"
readonly STORAGE_1B_ENCRYPTION_TYPE="luks"
readonly STORAGE_1B_MAPPER="none"
readonly STORAGE_1B_LVM_NAME="none"
readonly STORAGE_1B_LVM_GROUP="none"
readonly STORAGE_1B_MOUNT="none"
readonly STORAGE_1B_OWNER_USER="none"
readonly STORAGE_1B_OWNER_GROUP="none"
readonly STORAGE_1B_MOUNT_OPTIONS="defaults"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2A_KEY_FILE="none"
readonly STORAGE_2A_ENCRYPTION_TYPE="luks"
readonly STORAGE_2A_MAPPER="none"
readonly STORAGE_2A_LVM_NAME="none"
readonly STORAGE_2A_LVM_GROUP="none"
readonly STORAGE_2A_MOUNT="none"
readonly STORAGE_2A_OWNER_USER="none"
readonly STORAGE_2A_OWNER_GROUP="none"
readonly STORAGE_2A_MOUNT_OPTIONS="defaults"
readonly STORAGE_2B_UUID="none"
readonly STORAGE_2B_KEY_FILE="none"
readonly STORAGE_2B_ENCRYPTION_TYPE="luks"
readonly STORAGE_2B_MAPPER="none"
readonly STORAGE_2B_LVM_NAME="none"
readonly STORAGE_2B_LVM_GROUP="none"
readonly STORAGE_2B_MOUNT="none"
readonly STORAGE_2B_OWNER_USER="none"
readonly STORAGE_2B_OWNER_GROUP="none"
readonly STORAGE_2B_MOUNT_OPTIONS="defaults"
readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF
    
    # Test unlock-only command
    run sudo bash "$PROJECT_ROOT/srv-ctl.sh" unlock-only
    [ "$status" -eq 0 ]
    
    # Verify device is unlocked
    run sudo cryptsetup status "$TEST_BITLOCKER_MAPPER"
    [ "$status" -eq 0 ]
    
    # Stop to close device
    sudo bash "$PROJECT_ROOT/srv-ctl.sh" stop 2>/dev/null || true
    
    # Cleanup config
    rm -f "$config_file"
}
