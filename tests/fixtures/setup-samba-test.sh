#!/bin/bash
# Setup local Samba server for integration tests
set -e

TEST_SAMBA_DIR="/tmp/test_samba_share"
TEST_SAMBA_USER="testuser"
TEST_SAMBA_PASS="testpass"

mkdir -p "$TEST_SAMBA_DIR"
chmod 777 "$TEST_SAMBA_DIR"

# Verify samba is available
if ! command -v smbd &>/dev/null; then
    echo "ERROR: Samba (smbd) not found. Please install samba package."
    exit 1
fi

if ! command -v smbpasswd &>/dev/null; then
    echo "ERROR: smbpasswd not found. Please install samba package."
    exit 1
fi

# Kill any processes owned by testuser to allow cleanup
sudo pkill -u "$TEST_SAMBA_USER" || true
sleep 1

# Create user
sudo useradd -M "$TEST_SAMBA_USER" 2>/dev/null || true
(echo "$TEST_SAMBA_PASS"; echo "$TEST_SAMBA_PASS") | sudo smbpasswd -a -s "$TEST_SAMBA_USER" 2>/dev/null || true

# Create minimal smb.conf
cat <<EOF | sudo tee /etc/samba/smb.conf > /dev/null
[global]
   workgroup = WORKGROUP
   security = user
   map to guest = Bad User
   bind interfaces only = no

[testshare]
   path = $TEST_SAMBA_DIR
   read only = no
   guest ok = yes
   force user = $TEST_SAMBA_USER
   create mask = 0755
   directory mask = 0755
EOF

# Start or reload smbd without blocking
# Use reload-or-restart to avoid full stop/start cycle
if sudo systemctl is-active --quiet smbd 2>/dev/null; then
    # Service is running, just reload config
    (sudo systemctl reload smbd 2>/dev/null || true) &
else
    # Service not running, start it in background
    (sudo systemctl start smbd 2>/dev/null || sudo smbd -D 2>/dev/null || true) &
fi

# Wait for smbd to be ready (with timeout)
for _ in {1..20}; do
    if sudo systemctl is-active --quiet smbd 2>/dev/null || pgrep -x smbd >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

# Give it a moment to fully initialize
sleep 0.5

echo "Samba test share ready at //localhost/testshare with user $TEST_SAMBA_USER/$TEST_SAMBA_PASS"
