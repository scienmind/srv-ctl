#!/bin/bash
# Cleanup local Samba server after integration tests
set +e  # Don't exit on errors during cleanup

TEST_SAMBA_USER="testuser"
TEST_SAMBA_DIR="/tmp/test_samba_share"

# Kill any processes owned by the test user first
sudo pkill -u "$TEST_SAMBA_USER" 2>/dev/null || true
sleep 1

# Remove samba password (may not exist)
if command -v smbpasswd &>/dev/null; then
    sudo smbpasswd -x "$TEST_SAMBA_USER" 2>/dev/null || true
fi

# Delete user
sudo userdel -r "$TEST_SAMBA_USER" 2>/dev/null || true

# Stop service (may not be loaded)
sudo systemctl stop smbd 2>/dev/null || true

# Clean up directory
sudo rm -rf "$TEST_SAMBA_DIR"
