# Testing Guide

## Quick Start

```bash
# Local development tests (fast, no root required)
bats tests/unit/*.bats            # Unit tests
shellcheck -x srv-ctl.sh lib/*.sh # Lint

# Full VM tests (CI primary) - requires QEMU/KVM
./tests/vm/run-tests.sh <os-name>     # Integration tests
./tests/vm/run-e2e-tests.sh <os-name> # E2E tests
```

## Test Architecture

| Level           | Environment | Root | Use Case                          |
|-----------------|-------------|------|-----------------------------------|
| **Unit**        | Local       | No   | Fast function-level tests (bats)  |
| **Lint**        | Local       | No   | Static analysis (ShellCheck)      |
| **E2E**         | VM          | Yes  | CLI workflows with real devices   |
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

# E2E tests (full workflows)
./tests/vm/run-e2e-tests.sh ubuntu-22.04
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
| `test-e2e.yml`             | Push, PR         | VM E2E tests (4 OSes)           |

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

```bash
test_operation() {
    run_test "Operation description"
    
    if perform_operation; then
        log_pass "Operation successful"
    else
        log_fail "Operation failed"
        return 1
    fi
}
```

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
├── e2e/                  # End-to-end tests
│   └── test-e2e.sh
├── integration/          # Integration tests (VM only)
│   ├── test-luks.sh
│   ├── test-lvm.sh
│   └── test-mount.sh
├── fixtures/             # Test configs and setup helpers
│   ├── config.local.test
│   ├── setup-test-env.sh
│   └── cleanup-test-env.sh
└── vm/                   # VM test infrastructure
    ├── run-tests.sh      # VM integration test runner
    ├── run-e2e-tests.sh  # VM E2E test runner
    ├── download-image.sh # Cloud image downloader
    ├── cleanup.sh        # VM cleanup script
    └── vm-common.sh      # Shared VM functions
```
