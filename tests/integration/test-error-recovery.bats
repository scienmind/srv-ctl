#!/usr/bin/env bats
#
# Integration tests for error recovery and cleanup scenarios
#

setup_file() {
    echo "# Setting up error recovery test environment..." >&3
    
    # Create test loop devices
    TEST_LOOP_IMG_1="/tmp/test-error-recovery-1.img"
    TEST_LOOP_IMG_2="/tmp/test-error-recovery-2.img"
    
    dd if=/dev/zero of="$TEST_LOOP_IMG_1" bs=1M count=100 2>/dev/null
    dd if=/dev/zero of="$TEST_LOOP_IMG_2" bs=1M count=100 2>/dev/null
    
    TEST_LOOP_DEV_1=$(sudo losetup -f --show "$TEST_LOOP_IMG_1")
    TEST_LOOP_DEV_2=$(sudo losetup -f --show "$TEST_LOOP_IMG_2")
    
    # Format first device with LUKS
    echo -n "test_password" | sudo cryptsetup luksFormat --type luks2 "$TEST_LOOP_DEV_1" -
    
    # Create key file
    echo -n "test_password" > /tmp/test_error_key.key
    chmod 600 /tmp/test_error_key.key
    echo -n "test_password" | sudo cryptsetup luksAddKey "$TEST_LOOP_DEV_1" /tmp/test_error_key.key -
    
    # Get UUID
    TEST_UUID_1=$(sudo cryptsetup luksUUID "$TEST_LOOP_DEV_1")
    
    echo "# Test environment ready (UUID: $TEST_UUID_1)" >&3
    
    export TEST_LOOP_DEV_1 TEST_LOOP_DEV_2 TEST_UUID_1
    export TEST_LOOP_IMG_1 TEST_LOOP_IMG_2
}

teardown_file() {
    echo "# Cleaning up error recovery test environment..." >&3
    
    # Close any open mappers
    sudo cryptsetup close test_error_mapper 2>/dev/null || true
    sudo cryptsetup close test_collision_1 2>/dev/null || true
    sudo cryptsetup close test_collision_2 2>/dev/null || true
    
    # Detach loop devices
    if [ -n "$TEST_LOOP_DEV_1" ]; then
        sudo losetup -d "$TEST_LOOP_DEV_1" 2>/dev/null || true
    fi
    if [ -n "$TEST_LOOP_DEV_2" ]; then
        sudo losetup -d "$TEST_LOOP_DEV_2" 2>/dev/null || true
    fi
    
    # Remove temp files
    rm -f /tmp/test_error_key.key
    rm -f "$TEST_LOOP_IMG_1" "$TEST_LOOP_IMG_2"
}

setup() {
    # Define constants for test assertions
    readonly SUCCESS=0
    readonly FAILURE=1
    
    source lib/os-utils.sh
    source lib/storage.sh
}

# =============================================================================
# Device Operation Error Tests
# =============================================================================

@test "device timeout - UUID does not exist" {
    run wait_for_device "00000000-fake-uuid-does-not-exist"
    [ "$status" -eq "$FAILURE" ]
    [[ "$output" =~ "ERROR: Device" ]]
}

@test "unlock device - device already unlocked externally" {
    # Manually unlock device first
    echo -n "test_password" | sudo cryptsetup open --type luks "$TEST_LOOP_DEV_1" test_error_mapper -
    
    # Now try to unlock via function (should handle gracefully)
    run unlock_device "$TEST_UUID_1" "test_error_mapper" "/tmp/test_error_key.key" "luks"
    [ "$status" -eq "$SUCCESS" ]
    [[ "$output" =~ "already unlocked" ]] || [[ "$output" =~ "Skipping" ]]
    
    # Cleanup
    sudo cryptsetup close test_error_mapper
}

@test "unlock device - wrong key file" {
    # Create wrong key file
    echo -n "wrong_password" > /tmp/test_wrong_key.key
    chmod 600 /tmp/test_wrong_key.key
    
    run unlock_device "$TEST_UUID_1" "test_error_mapper" "/tmp/test_wrong_key.key" "luks"
    [ "$status" -eq "$FAILURE" ]
    [[ "$output" =~ "ERROR" ]] || [[ "$output" =~ "Failed" ]]
    
    rm -f /tmp/test_wrong_key.key
}

@test "unlock device - mapper name collision" {
    # Unlock with one mapper
    echo -n "test_password" | sudo cryptsetup open --type luks "$TEST_LOOP_DEV_1" test_collision_1 -
    
    # Try to create another device with same mapper name (using loop device 2)
    # This should fail because mapper already exists
    echo -n "test_password" | sudo cryptsetup luksFormat --type luks2 "$TEST_LOOP_DEV_2" -
    TEST_UUID_2=$(sudo cryptsetup luksUUID "$TEST_LOOP_DEV_2")
    
    # Try to unlock with same mapper name
    run bash -c "echo -n 'test_password' | sudo cryptsetup open --type luks /dev/disk/by-uuid/$TEST_UUID_2 test_collision_1 -"
    [ "$status" -ne 0 ]
    
    # Cleanup
    sudo cryptsetup close test_collision_1
}

@test "lock device - device not unlocked" {
    run lock_device "nonexistent_mapper" "luks"
    [ "$status" -eq "$SUCCESS" ]  # Should handle gracefully
    [[ "$output" =~ "locked" ]] || [[ "$output" =~ "Skipping" ]]
}

@test "lock device - device busy (mounted)" {
    # Unlock and mount
    echo -n "test_password" | sudo cryptsetup open --type luks "$TEST_LOOP_DEV_1" test_error_mapper -
    sudo mkfs.ext4 -q /dev/mapper/test_error_mapper
    sudo mkdir -p /mnt/test_error_mount
    sudo mount /dev/mapper/test_error_mapper /mnt/test_error_mount
    
    # Try to lock while mounted - should fail
    run bash -c "sudo cryptsetup close test_error_mapper 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "busy" ]] || [[ "$output" =~ "in use" ]]
    
    # Cleanup properly
    sudo umount /mnt/test_error_mount
    sudo cryptsetup close test_error_mapper
    sudo rmdir /mnt/test_error_mount
}

# =============================================================================
# Mount Operation Error Tests  
# =============================================================================

@test "mount device - mapper does not exist" {
    run mount_device "nonexistent_mapper" "test_error_mount" "defaults"
    [ "$status" -eq "$SUCCESS" ]  # Should skip gracefully
    [[ "$output" =~ "does not exist" ]] || [[ "$output" =~ "Skipping" ]]
}

@test "mount device - already mounted idempotency" {
    # Setup: unlock, format, and mount
    echo -n "test_password" | sudo cryptsetup open --type luks "$TEST_LOOP_DEV_1" test_error_mapper -
    sudo mkfs.ext4 -q /dev/mapper/test_error_mapper 2>/dev/null || true
    sudo mkdir -p /mnt/test_error_mount
    sudo mount /dev/mapper/test_error_mapper /mnt/test_error_mount
    
    # Try to mount again
    run mount_device "test_error_mapper" "test_error_mount" "defaults"
    [ "$status" -eq "$SUCCESS" ]
    [[ "$output" =~ "mounted" ]] || [[ "$output" =~ "Skipping" ]]
    
    # Cleanup
    sudo umount /mnt/test_error_mount
    sudo cryptsetup close test_error_mapper
    sudo rmdir /mnt/test_error_mount
}

@test "unmount device - not mounted idempotency" {
    run unmount_device "nonexistent_mount"
    [ "$status" -eq "$SUCCESS" ]  # Should handle gracefully
}

@test "mount device - invalid mount options" {
    # Setup: unlock and format
    echo -n "test_password" | sudo cryptsetup open --type luks "$TEST_LOOP_DEV_1" test_error_mapper -
    sudo mkfs.ext4 -q /dev/mapper/test_error_mapper 2>/dev/null || true
    
    # Try to mount with invalid options
    run bash -c "sudo mkdir -p /mnt/test_error_mount && sudo mount -o 'invalid_option_12345' /dev/mapper/test_error_mapper /mnt/test_error_mount 2>&1"
    [ "$status" -ne 0 ]
    
    # Cleanup
    sudo cryptsetup close test_error_mapper
    sudo rmdir /mnt/test_error_mount 2>/dev/null || true
}
