#!/bin/bash
# Cleanup local NFS server after integration tests
set -e

TEST_NFS_DIR="/tmp/test_nfs_share"

sudo systemctl stop nfs-server || true
sudo rm -rf "$TEST_NFS_DIR"
sudo sed -i '/\/tmp\/test_nfs_share/d' /etc/exports
sudo exportfs -ra
