# Testing Guide

## Quick Start

```bash
# Local tests (syntax + unit + e2e) - SAFE, no root required
./tests/run-tests.sh

# VM tests (full system validation) - CI only, multi-OS
./tests/vm/run-vm-tests.sh <os-name>
```

## Test Levels

| Level      | Safety | Root | Isolation | Use Case                          |
|------------|--------|------|-----------|-----------------------------------|
| **Local**  | ✅ Safe | No   | None      | Quick development feedback        |
| **VM**     | ✅ Safe | No   | Full VM   | Multi-OS validation, systemd      |

### Local Tests

Syntax checks, unit tests (bats), and e2e tests. Fast feedback loop for development.

```bash
./tests/run-tests.sh              # All local tests
./tests/run-tests.sh --syntax-only
./tests/run-tests.sh --unit-only
./tests/run-tests.sh --e2e-only
```

**Requirements**: `bats`, `shellcheck`

### VM Tests (CI Primary)

Complete validation with real systemd, network shares, and multi-OS support.

```bash
./tests/vm/run-vm-tests.sh <os-name>  # See tests/vm/ for available OS images
```

**Requirements**: QEMU/KVM

## CI/CD

Tests run automatically via GitHub Actions on push to main and pull requests:

- **Lint**: ShellCheck and bash syntax validation
- **Unit Tests**: bats framework
- **VM Integration**: QEMU VMs with cloud-init across multiple OS versions

See `.github/workflows/` for workflow definitions and the current OS matrix.

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

### Integration Tests (VM only)

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
- ✅ **VM tests**: Full VMs, no host interaction
- ❌ **Never run integration tests directly on host** (use VM)

## Troubleshooting

### Bats not found

```bash
npm install -g bats
```

### VM tests fail

```bash
# Download OS image
./tests/vm/download-image.sh <os-name>

# Check QEMU/KVM
which qemu-system-x86_64
```

## Project Structure

```text
tests/
├── run-tests.sh          # Main local test runner
├── unit/                 # Unit tests (bats)
├── e2e/                  # End-to-end tests  
├── integration/          # Integration tests (VM only)
├── fixtures/             # Test configs and helpers
└── vm/                   # VM test infrastructure
```

Run `tree tests/` or `find tests/ -type f` for the complete file listing.
