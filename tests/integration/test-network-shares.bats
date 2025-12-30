#!/usr/bin/env bats
# Integration tests for network share mounting (CIFS/NFS)
# Note: Services are pre-configured in the VM environment before tests run

# Shared variable for all tests
TEST_MOUNTPOINT="/mnt/test_network_share"

# Run once before all tests in this file
setup_file() {
    mkdir -p "$TEST_MOUNTPOINT"
    # Services are already running from VM setup, just verify they exist
    if ! command -v smbd &>/dev/null || ! command -v exportfs &>/dev/null; then
        echo "ERROR: Required services not available"
        return 1
    fi
}

# Run once after all tests in this file
teardown_file() {
    # Services configured via cloud-init stay running - no cleanup needed
    rmdir "$TEST_MOUNTPOINT" 2>/dev/null || true
}

# Run after each individual test
teardown() {
    # Ensure mountpoint is clean for next test
    sudo umount "$TEST_MOUNTPOINT" &>/dev/null || true
}

@test "Mount CIFS share with credentials file" {
    echo -e "username=testuser\npassword=testpass" > /tmp/cifs_creds
    run sudo mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o credentials=/tmp/cifs_creds,vers=3.0
    if [ "$status" -ne 0 ]; then
        echo "Mount failed with: $output"
    fi
    [ "$status" -eq 0 ]
    run sudo umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
    rm -f /tmp/cifs_creds
}

@test "Mount CIFS share with inline credentials" {
    run sudo mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    [ "$status" -eq 0 ]
    run sudo umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Mount CIFS share with invalid credentials" {
    # With guest ok = yes in smb.conf, invalid credentials fall back to guest access
    # This is expected behavior - mount succeeds as guest
    run sudo mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=wrong,password=wrong,vers=3.0
    [ "$status" -eq 0 ]
    run sudo umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Mount NFS share (v4)" {
    run sudo mount -t nfs4 localhost:/tmp/test_nfs_share "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
    run sudo umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Mount NFS share (v3)" {
    run sudo mount -t nfs localhost:/tmp/test_nfs_share "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
    run sudo umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Mount NFS share with network unreachable" {
    run sudo mount -t nfs4 unreachable:/tmp/test_nfs_share "$TEST_MOUNTPOINT"
    [ "$status" -ne 0 ]
}

@test "Mount point permission issues (CIFS)" {
    # Test: sudo can mount to directories with restrictive permissions
    chmod 000 "$TEST_MOUNTPOINT"
    run sudo mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    # Mount succeeds because sudo bypasses local directory permissions
    [ "$status" -eq 0 ]
    # Cleanup
    sudo umount "$TEST_MOUNTPOINT"
    chmod 777 "$TEST_MOUNTPOINT"
}

@test "Share already mounted (idempotency)" {
    run sudo mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    [ "$status" -eq 0 ]
    run sudo mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    [ "$status" -ne 0 ]
    run sudo umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Unmount network share (CIFS)" {
    run sudo mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    [ "$status" -eq 0 ]
    run sudo umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Unmount network share (NFS)" {
    run sudo mount -t nfs4 localhost:/tmp/test_nfs_share "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
    run sudo umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}
