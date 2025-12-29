#!/bin/bash
# Setup local NFS server for integration tests
set -e

TEST_NFS_DIR="/tmp/test_nfs_share"

mkdir -p "$TEST_NFS_DIR"
chmod 777 "$TEST_NFS_DIR"

# Install nfs-kernel-server if not present
if ! command -v exportfs &>/dev/null; then
    echo "NFS server not found. Please install nfs-kernel-server package."
    exit 1
fi

# Add export
echo "$TEST_NFS_DIR *(rw,sync,no_subtree_check)" | sudo tee /etc/exports > /dev/null
sudo exportfs -ra
sudo systemctl restart nfs-server
sleep 2

echo "NFS test share ready at localhost:$TEST_NFS_DIR"
