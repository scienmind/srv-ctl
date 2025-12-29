#!/usr/bin/env bats
# Integration tests for network share mounting (CIFS/NFS)

teardown() {

setup() {
    export TEST_MOUNTPOINT="/mnt/test_network_share"
    mkdir -p "$TEST_MOUNTPOINT"
    bash "${BATS_TEST_DIRNAME}/../fixtures/setup-samba-test.sh"
    bash "${BATS_TEST_DIRNAME}/../fixtures/setup-nfs-test.sh"
}


    umount "$TEST_MOUNTPOINT" &>/dev/null || true
    rmdir "$TEST_MOUNTPOINT" &>/dev/null || true
    bash "${BATS_TEST_DIRNAME}/../fixtures/cleanup-samba-test.sh"
    bash "${BATS_TEST_DIRNAME}/../fixtures/cleanup-nfs-test.sh"
}

@test "Mount CIFS share with credentials file" {
    echo -e "username=testuser\npassword=testpass" > /tmp/cifs_creds
    run mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o credentials=/tmp/cifs_creds,vers=3.0
    [ "$status" -eq 0 ]
    run umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
    rm -f /tmp/cifs_creds
}

@test "Mount CIFS share with inline credentials" {
    run mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    [ "$status" -eq 0 ]
    run umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Mount CIFS share with invalid credentials" {
    run mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=wrong,password=wrong,vers=3.0
    [ "$status" -ne 0 ]
}

@test "Mount NFS share (v4)" {
    run mount -t nfs4 localhost:/tmp/test_nfs_share "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
    run umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Mount NFS share (v3)" {
    run mount -t nfs localhost:/tmp/test_nfs_share "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
    run umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Mount NFS share with network unreachable" {
    run mount -t nfs4 unreachable:/tmp/test_nfs_share "$TEST_MOUNTPOINT"
    [ "$status" -ne 0 ]
}

@test "Mount point permission issues (CIFS)" {
    chmod 000 "$TEST_MOUNTPOINT"
    run mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    [ "$status" -ne 0 ]
    chmod 777 "$TEST_MOUNTPOINT"
}

@test "Share already mounted (idempotency)" {
    run mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    [ "$status" -eq 0 ]
    run mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    [ "$status" -ne 0 ]
    run umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Unmount network share (CIFS)" {
    run mount -t cifs //localhost/testshare "$TEST_MOUNTPOINT" -o username=testuser,password=testpass,vers=3.0
    [ "$status" -eq 0 ]
    run umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}

@test "Unmount network share (NFS)" {
    run mount -t nfs4 localhost:/tmp/test_nfs_share "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
    run umount "$TEST_MOUNTPOINT"
    [ "$status" -eq 0 ]
}
