#!/usr/bin/env bats
# Integration tests for LUKS key file authentication

setup() {
    export TEST_LOOP_DEV="/tmp/test_luks_loop.img"
    export TEST_MAPPER="test_luks_mapper"
    export TEST_KEYFILE="/tmp/test_luks_keyfile.key"
    export TEST_WRONG_KEYFILE="/tmp/test_luks_wrong_keyfile.key"
    export TEST_MOUNTPOINT="/mnt/test_luks_mount"
    dd if=/dev/zero of="$TEST_LOOP_DEV" bs=1M count=32 &>/dev/null
    losetup -fP "$TEST_LOOP_DEV"
    LOOPDEV=$(losetup -j "$TEST_LOOP_DEV" | cut -d: -f1)
    echo -n "supersecretkey" > "$TEST_KEYFILE"
    echo -n "wrongkeymaterial" > "$TEST_WRONG_KEYFILE"
    chmod 600 "$TEST_KEYFILE" "$TEST_WRONG_KEYFILE"
    mkdir -p "$TEST_MOUNTPOINT"
    cryptsetup luksFormat "$LOOPDEV" "$TEST_KEYFILE" --batch-mode
}

teardown() {
    umount "$TEST_MOUNTPOINT" &>/dev/null || true
    cryptsetup luksClose "$TEST_MAPPER" &>/dev/null || true
    losetup -d "$(losetup -j "$TEST_LOOP_DEV" | cut -d: -f1)" &>/dev/null || true
    rm -f "$TEST_LOOP_DEV" "$TEST_KEYFILE" "$TEST_WRONG_KEYFILE"
    rmdir "$TEST_MOUNTPOINT" &>/dev/null || true
}

@test "Unlock LUKS with valid key file" {
    run cryptsetup luksOpen "$LOOPDEV" "$TEST_MAPPER" --key-file "$TEST_KEYFILE"
    [ "$status" -eq 0 ]
    cryptsetup luksClose "$TEST_MAPPER"
}

@test "Unlock LUKS with missing key file" {
    run cryptsetup luksOpen "$LOOPDEV" "$TEST_MAPPER" --key-file /tmp/does_not_exist.key
    [ "$status" -ne 0 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "Unlock LUKS with wrong key file" {
    run cryptsetup luksOpen "$LOOPDEV" "$TEST_MAPPER" --key-file "$TEST_WRONG_KEYFILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No key available"* ]]
}

@test "Unlock LUKS with unreadable key file" {
    chmod 000 "$TEST_KEYFILE"
    run cryptsetup luksOpen "$LOOPDEV" "$TEST_MAPPER" --key-file "$TEST_KEYFILE"
    [ "$status" -ne 0 ]
    chmod 600 "$TEST_KEYFILE"
}

@test "Unlock LUKS with symlinked key file" {
    ln -sf "$TEST_KEYFILE" /tmp/test_luks_symlink.key
    run cryptsetup luksOpen "$LOOPDEV" "$TEST_MAPPER" --key-file /tmp/test_luks_symlink.key
    [ "$status" -eq 0 ]
    cryptsetup luksClose "$TEST_MAPPER"
    rm -f /tmp/test_luks_symlink.key
}

@test "Unlock LUKS with key file path containing spaces" {
    cp "$TEST_KEYFILE" "/tmp/test keyfile with spaces.key"
    run cryptsetup luksOpen "$LOOPDEV" "$TEST_MAPPER" --key-file "/tmp/test keyfile with spaces.key"
    [ "$status" -eq 0 ]
    cryptsetup luksClose "$TEST_MAPPER"
    rm -f "/tmp/test keyfile with spaces.key"
}
