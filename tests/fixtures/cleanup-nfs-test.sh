#!/bin/bash
# Cleanup local NFS server after integration tests
set +e  # Don't exit on errors during cleanup

TEST_NFS_DIR="/tmp/test_nfs_share"

# Remove exports entry if file exists
if [[ -f /etc/exports ]]; then
    sudo sed -i '/\/tmp\/test_nfs_share/d' /etc/exports 2>/dev/null || true
    if command -v exportfs &>/dev/null; then
        sudo exportfs -ra 2>/dev/null || true
    fi
fi

# Stop service (may not be loaded)
sudo systemctl stop nfs-server 2>/dev/null || true

# Clean up directory
sudo rm -rf "$TEST_NFS_DIR"
