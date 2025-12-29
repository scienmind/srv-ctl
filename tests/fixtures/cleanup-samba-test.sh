#!/bin/bash
# Cleanup local Samba server after integration tests
set -e

TEST_SAMBA_USER="testuser"
TEST_SAMBA_DIR="/tmp/test_samba_share"

sudo systemctl stop smbd || true
sudo userdel "$TEST_SAMBA_USER" || true
sudo smbpasswd -x "$TEST_SAMBA_USER" || true
sudo rm -rf "$TEST_SAMBA_DIR"
# Optionally restore original smb.conf if needed
