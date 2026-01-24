# Testing Guide

## Quick Start

```bash
# Local development tests (fast, no root required)
bats tests/unit/*.bats            # Unit tests
shellcheck -x srv-ctl.sh lib/*.sh # Lint

# Full VM tests (CI primary) - requires QEMU/KVM
./tests/vm/run-tests.sh <os-name>        # Integration tests
./tests/vm/run-system-tests.sh <os-name> # System tests
```

## Test Architecture

| Level           | Environment | Root | Use Case                          |
|-----------------|-------------|------|-----------------------------------|
| **Unit**        | Local       | No   | Fast function-level tests (bats)  |
| **Lint**        | Local       | No   | Static analysis (ShellCheck)      |
| **System**      | VM          | Yes  | CLI workflows with real devices   |
| **Integration** | VM          | Yes  | Storage operations (LUKS/LVM)     |

### Unit Tests

Fast, isolated tests using the bats framework. No root or special setup required.

```bash
bats tests/unit/*.bats
```

### Lint

Static analysis with ShellCheck to catch common shell scripting errors.

```bash
shellcheck -x srv-ctl.sh lib/*.sh
```

### VM Tests (CI Primary)

Full system validation in QEMU VMs with real systemd, devices, and multi-OS testing.

```bash
# Integration tests (LUKS, LVM, mount operations)
./tests/vm/run-tests.sh ubuntu-22.04

# System tests (full workflows)
./tests/vm/run-system-tests.sh ubuntu-22.04
```

Supported OS versions (cryptsetup >=2.4.0 required for BitLocker):

- `ubuntu-22.04`, `ubuntu-24.04`
- `debian-12`, `debian-13`

**Requirements**: `qemu-system-x86`, `qemu-utils`, `cloud-image-utils`

## CI/CD Workflows

Tests run automatically via GitHub Actions:

| Workflow                   | Trigger          | Description                     |
|----------------------------|------------------|---------------------------------|
| `lint.yml`                 | Push, PR         | ShellCheck + syntax validation  |
| `test-unit.yml`            | Push, PR         | Bats unit tests                 |
| `test-integration-vm.yml`  | Push, PR         | VM integration tests (4 OSes)   |
| `test-system.yml`          | Push, PR         | VM system tests (4 OSes)        |

## Writing Tests

### Unit Tests (bats)

```bash
@test "function_name does something" {
    run function_name arg1 arg2
    [ "$status" -eq 0 ]
    [ "$output" = "expected output" ]
}
```

### Integration Tests

Integration tests cover real storage operations (LUKS, LVM, mount, network shares, BitLocker, service management) using BATS and real services. No mocks or fakes are used.

- **test-luks-keyfile.bats**: LUKS key file authentication (valid, missing, unreadable, wrong key, symlink, spaces, error handling)
- **test-network-shares.bats**: Network share mounting (CIFS/NFS) with real Samba/NFS servers, credentials, error handling, idempotency, and permission scenarios
- **test-bitlocker.bats**: BitLocker encryption support (unlock/lock with key files, error handling, idempotency, integration with srv-ctl.sh)
- **test-services.bats**: Service management edge cases (start/stop, idempotency, error handling for nonexistent/failing services, SAMBA_SERVICE integration)

All integration tests are run in CI via VM on all supported OSes.

### System Tests

System tests validate full CLI workflows using srv-ctl.sh, including device orchestration, service management, and network share mounting. These tests use real services and config patching to simulate production scenarios.

- **test-system.sh**: Covers start/stop/unlock workflows, config validation, error handling, multi-device orchestration (PRIMARY + multiple STORAGE + NETWORK_SHARE), service management (including SAMBA_SERVICE with real smbd), and key file authentication tests as part of the main workflow.

All system tests are run in CI via VM on all supported OSes.

## Safety

- ✅ **Unit/Lint**: Zero system impact, no root
- ✅ **VM tests**: Full isolation in QEMU VMs
- ❌ **Never run integration tests directly on host** (use VM)

## Troubleshooting

### Bats not found

```bash
# Install bats
git clone --branch v1.13.0 --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
sudo /tmp/bats/install.sh /usr/local
```

### VM tests fail

```bash
# Download OS image first
./tests/vm/download-image.sh ubuntu-22.04

# Verify QEMU is installed
which qemu-system-x86_64
```

## Project Structure

```text
tests/
├── run-tests.sh          # Test runner (for use inside VM)
├── unit/                 # Unit tests (bats)
│   ├── test-os-utils.bats
│   └── test-storage.bats
├── system/               # System tests
│   └── test-system.sh
├── integration/          # Integration tests (VM only)
│   ├── test-luks.sh
│   ├── test-lvm.sh
│   ├── test-mount.sh
│   ├── test-luks-keyfile.bats
│   ├── test-network-shares.bats
│   ├── test-bitlocker.bats
│   └── test-services.bats
├── fixtures/             # Test configs and setup helpers
│   ├── config.local.test
│   ├── setup-test-env.sh
│   └── cleanup-test-env.sh
└── vm/                   # VM test infrastructure
    ├── run-tests.sh         # VM integration test runner
    ├── run-system-tests.sh  # VM system test runner
    ├── download-image.sh    # Cloud image downloader
    ├── cleanup.sh           # VM cleanup script
    └── vm-common.sh         # Shared VM functions
```

## Coverage Notes

- **Network shares (CIFS/NFS), key file authentication, BitLocker encryption, and service management tests are now fully implemented and CI-integrated.**
- **Multi-device orchestration** tests validate simultaneous operation of PRIMARY + multiple STORAGE + NETWORK_SHARE devices.
- All major scenarios, error handling, and idempotency are covered at both integration (BATS) and system (workflow) levels.
- No mocks/fakes are used; all tests use real services, encryption operations, and I/O.
- Overall test coverage: **~85%** (excellent coverage across all major features)
- See [TEST_COVERAGE_GAPS.md](TEST_COVERAGE_GAPS.md) for detailed coverage tracking.
