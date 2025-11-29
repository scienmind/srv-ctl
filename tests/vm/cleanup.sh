#!/bin/bash
# Cleanup VM test artifacts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Kill any running QEMU VMs for srv-ctl tests
pkill -f "srv-ctl-test" || true

# Clean up result directories
rm -rf "$SCRIPT_DIR/results"

# Clean up temporary work directories
rm -rf /tmp/srv-ctl-vm-*

echo "VM test cleanup complete"
