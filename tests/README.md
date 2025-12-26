# Testing Guide

## Quick Start

```bash
# Local tests (syntax + unit + e2e) - SAFE, no root required
./tests/run-tests.sh

# Docker tests (includes integration) - SAFE, isolated container
./tests/docker/run-docker-tests.sh

# VM tests (full system validation) - CI only, multi-OS
./tests/vm/run-vm-tests.sh ubuntu-22.04
```

## Test Levels

### Local Tests ✅ SAFE
- **What**: Syntax checks, unit tests (bats), e2e tests
- **Requirements**: `bats`, `shellcheck`
- **Time**: ~30 seconds
- **Root**: Not required
- **Safe**: No system modifications

```bash
./tests/run-tests.sh              # All local tests
./tests/run-tests.sh --syntax-only
./tests/run-tests.sh --unit-only
./tests/run-tests.sh --e2e-only
```

### Docker Tests ✅ SAFE (Recommended)
- **What**: All local tests + integration tests (LUKS, LVM, mounting)
- **Requirements**: Docker
- **Time**: ~2-3 minutes
- **Root**: Not required (Docker handles isolation)
- **Safe**: Complete isolation, no host impact

```bash
./tests/docker/run-docker-tests.sh           # All tests
./tests/docker/run-docker-tests.sh --rebuild # Force rebuild
```

### VM Tests ✅ SAFE (CI Primary)
- **What**: Complete validation with systemd, network shares, multi-OS
- **Requirements**: QEMU/KVM
- **Time**: ~5-10 minutes per OS
- **Root**: Not required
- **Safe**: Full VM isolation

```bash
# Tested OS versions
./tests/vm/run-vm-tests.sh ubuntu-22.04
./tests/vm/run-vm-tests.sh ubuntu-24.04
./tests/vm/run-vm-tests.sh debian-11
./tests/vm/run-vm-tests.sh debian-12
```

## Structure

```text
tests/
├── run-tests.sh                    # Main local test runner
├── unit/                           # Unit tests (bats)
│   ├── test-os-utils.bats
│   └── test-storage.bats
├── e2e/                            # End-to-end tests
│   └── test-e2e.sh
├── integration/                    # Integration tests (root required)
│   ├── test-luks.sh
│   ├── test-lvm.sh
│   └── test-mount.sh
├── fixtures/                       # Test infrastructure
│   ├── config.local.test          # Safe test configuration
│   ├── setup-test-env.sh
│   └── cleanup-test-env.sh
├── docker/                         # Docker testing
│   ├── Dockerfile
│   └── run-docker-tests.sh
└── vm/                             # VM testing
    ├── run-vm-tests.sh
    ├── download-image.sh
    └── cleanup.sh
```

## CI/CD

Tests run automatically in GitHub Actions:

**Lint** (`.github/workflows/lint.yml`):
- Runs on: Push to main, pull requests
- Checks: ShellCheck, bash syntax validation

**Unit Tests** (`.github/workflows/test-unit.yml`):
- Runs on: Push to main, pull requests
- Uses: bats framework

**Docker Integration** (`.github/workflows/test-integration-docker.yml`):
- Runs on: Push to main, pull requests
- Matrix: 5 OS versions (Debian 11/12/13, Ubuntu 22.04/24.04)
- Uses: Privileged Docker containers

**VM Integration** (`.github/workflows/test-integration-vm.yml`):
- Runs on: Push to main, pull requests
- Matrix: 5 OS versions (Debian 11/12/13, Ubuntu 22.04/24.04)
- Uses: QEMU VMs with cloud-init

## Writing Tests

### Unit Tests (bats)

```bash
@test "function_name does something" {
    run function_name arg1 arg2
    [ "$status" -eq 0 ]
    [ "$output" = "expected output" ]
}
```

### E2E Tests

```bash
test_feature() {
    run_test "Feature description"
    
    if command_succeeds; then
        log_pass "Test passed"
    else
        log_fail "Test failed"
        return 1
    fi
}
```

### Integration Tests (Docker/VM only)

```bash
test_system_operation() {
    # Setup
    setup_test_device
    
    # Test
    if perform_operation; then
        echo "✓ Operation successful"
    else
        echo "✗ Operation failed"
        return 1
    fi
    
    # Cleanup
    cleanup_test_device
}
```

## Safety

- ✅ **Local tests**: Zero system impact
- ✅ **Docker tests**: Isolated containers, auto-cleanup
- ✅ **VM tests**: Full VMs, no host interaction
- ❌ **Never run integration tests directly on host** (use Docker/VM)

## Troubleshooting

### Bats not found

```bash
npm install -g bats
```

### Docker tests fail

```bash
# Ensure Docker is running
docker info

# Rebuild image
./tests/docker/run-docker-tests.sh --rebuild
```

### VM tests fail

```bash
# Download OS image
./tests/vm/download-image.sh ubuntu-22.04

# Check QEMU/KVM
which qemu-system-x86_64
```

## Coverage

- **Unit tests**: Function-level testing with bats
- **E2E tests**: High-level workflow validation
- **Integration tests**: LUKS, LVM, and mount operations
- **Platforms**: Debian 11/12/13, Ubuntu 22.04/24.04
