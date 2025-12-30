#!/bin/bash
# Setup local NFS server for integration tests
set -e

TEST_NFS_DIR="/tmp/test_nfs_share"

mkdir -p "$TEST_NFS_DIR"
chmod 777 "$TEST_NFS_DIR"

# Verify NFS is available
if ! command -v exportfs &>/dev/null; then
    echo "ERROR: NFS server not found. Please install nfs-kernel-server package."
    exit 1
fi

# Ensure /etc/exports exists
sudo touch /etc/exports

# Remove any existing test exports
sudo sed -i '/\/tmp\/test_nfs_share/d' /etc/exports

# Add export
echo "$TEST_NFS_DIR *(rw,sync,no_subtree_check,insecure)" | sudo tee -a /etc/exports > /dev/null

# Apply exports and start service without blocking
if sudo systemctl is-active --quiet nfs-server 2>/dev/null; then
    # Just re-export, don't touch the service
    (sudo exportfs -ra 2>/dev/null || true) &
else
    # Start in background
    (sudo systemctl start nfs-server 2>/dev/null || true) &
    sleep 0.3
    (sudo exportfs -ra 2>/dev/null || true) &
fi

# Wait for NFS to be ready (with timeout)
for _ in {1..20}; do
    if sudo systemctl is-active --quiet nfs-server 2>/dev/null || showmount -e localhost >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

# Give it a moment to fully initialize
sleep 0.5

echo "NFS test share ready at localhost:$TEST_NFS_DIR"
