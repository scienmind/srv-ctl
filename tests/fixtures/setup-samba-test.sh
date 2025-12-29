#!/bin/bash
# Setup local Samba server for integration tests
set -e

TEST_SAMBA_DIR="/tmp/test_samba_share"
TEST_SAMBA_USER="testuser"
TEST_SAMBA_PASS="testpass"

mkdir -p "$TEST_SAMBA_DIR"
chmod 777 "$TEST_SAMBA_DIR"

# Install samba if not present
if ! command -v smbd &>/dev/null; then
    echo "Samba (smbd) not found. Please install samba package."
    exit 1
fi

# Create user
sudo useradd -M "$TEST_SAMBA_USER" || true
(echo "$TEST_SAMBA_PASS"; echo "$TEST_SAMBA_PASS") | sudo smbpasswd -a -s "$TEST_SAMBA_USER"

# Create minimal smb.conf
cat <<EOF | sudo tee /etc/samba/smb.conf > /dev/null
[testshare]
   path = $TEST_SAMBA_DIR
   read only = no
   guest ok = yes
   force user = $TEST_SAMBA_USER
EOF

sudo systemctl restart smbd
sleep 2

echo "Samba test share ready at //localhost/testshare with user $TEST_SAMBA_USER/$TEST_SAMBA_PASS"
