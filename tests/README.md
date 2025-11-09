# Testing Guide

This directory contains the test suite for srv-ctl. Tests are organized into three phases:

1. **Syntax and Lint Checks** - Fast syntax validation and ShellCheck
2. **Unit Tests** - Tests for pure functions using bats
3. **Integration Tests** - System-level tests with LUKS, LVM, and mounts

## Directory Structure

```
tests/
├── unit/                      # Unit tests (bats)
│   ├── test-os-utils.bats    # Tests for lib/os-utils.sh
│   └── test-storage.bats     # Tests for lib/storage.sh
├── integration/               # Integration tests
│   ├── test-luks.sh          # LUKS encryption tests
│   ├── test-lvm.sh           # LVM tests
│   └── test-mount.sh         # Mount operation tests
├── fixtures/                  # Test setup and utilities
│   ├── setup-test-env.sh     # Creates test environment
│   └── cleanup-test-env.sh   # Cleans up test environment
├── run-tests.sh              # Main test runner
└── README.md                 # This file
```

## Running Tests Locally

### Prerequisites

- **For syntax and unit tests**:
  - Bash 4.0+
  - ShellCheck (optional but recommended): `sudo apt-get install shellcheck`
  - bats (Bash Automated Testing System): `npm install -g bats`

- **For integration tests**:
  - All of the above, plus:
  - Root/sudo access
  - cryptsetup 2.4.0+
  - lvm2
  - dosfstools, ntfs-3g, util-linux

### Quick Start

```bash
# Run syntax checks and unit tests (no root required)
./tests/run-tests.sh

# Run all tests including integration tests (requires root)
sudo ./tests/run-tests.sh --all
```

### Specific Test Phases

```bash
# Syntax and lint checks only
./tests/run-tests.sh --syntax-only

# Unit tests only
./tests/run-tests.sh --unit-only

# Integration tests only (requires root)
sudo ./tests/run-tests.sh --integration-only
```

### Individual Test Files

```bash
# Run a specific unit test
bats tests/unit/test-os-utils.bats

# Run a specific integration test (requires root)
sudo bash tests/integration/test-luks.sh
```

## CI/CD with GitHub Actions

Tests run automatically on:
- Push to `main`, `master`, or `develop` branches
- Pull requests to these branches
- Manual workflow dispatch

### Test Matrix

Integration tests run on:
- Debian 10, 11, 12, 13
- Ubuntu 18.04, 20.04, 22.04, 24.04

### Workflow Stages

1. **Syntax and Lint** - Runs on Ubuntu latest
2. **Unit Tests** - Runs on Ubuntu latest
3. **Integration Tests** - Runs in Docker containers with privileged mode

View workflow results at: `.github/workflows/test.yml`

## Test Environment

### Unit Tests

Unit tests mock or skip system-level operations:
- Tests pure functions like `get_uid_from_username()`
- Uses known system entities (e.g., `root` user)
- No special privileges required

### Integration Tests

Integration tests use real system operations:
- Creates 100MB loop device with LUKS encryption
- Sets up LVM on encrypted container
- Performs actual mount/unmount operations
- Requires root privileges

**Test environment details:**
- LUKS container: `test_luks`
- Volume group: `test_vg`
- Logical volume: `test_lv` (90MB)
- Mount point: `/tmp/test_mount`
- Test password: `test123456`

## Writing New Tests

### Adding Unit Tests

1. Create or edit a `.bats` file in `tests/unit/`
2. Follow this structure:

```bash
#!/usr/bin/env bats

setup() {
    export SUCCESS=0
    export FAILURE=1
    source "${BATS_TEST_DIRNAME}/../../lib/your-lib.sh"
}

@test "descriptive test name" {
    run your_function "arg1" "arg2"
    [ "$status" -eq 0 ]
    [ "$output" = "expected output" ]
}
```

### Adding Integration Tests

1. Create a `.sh` file in `tests/integration/`
2. Follow this structure:

```bash
#!/bin/bash
set -euo pipefail

# Load test environment
source /tmp/test_env.conf
source "$(dirname "$0")/../../lib/os-utils.sh"
source "$(dirname "$0")/../../lib/storage.sh"

# Test implementation...
```

3. The test environment is automatically setup/cleanup by the runner

## Troubleshooting

### Unit Tests

**Problem**: bats not found
```bash
# Install bats via npm
npm install -g bats

# Or via package manager
sudo apt-get install bats
```

**Problem**: Function not found
- Ensure the library is sourced in `setup()`
- Check that constants (SUCCESS/FAILURE) are exported

### Integration Tests

**Problem**: Permission denied
```bash
# Integration tests require root
sudo ./tests/run-tests.sh --integration
```

**Problem**: cryptsetup or lvm2 not found
```bash
# Install required packages
sudo apt-get install cryptsetup lvm2 dosfstools ntfs-3g
```

**Problem**: Loop device creation fails
```bash
# Check available loop devices
losetup -f

# Check if loop module is loaded
lsmod | grep loop

# Load loop module if needed
sudo modprobe loop
```

**Problem**: Test environment not cleaned up
```bash
# Manually run cleanup
sudo ./tests/fixtures/cleanup-test-env.sh
```

## Best Practices

1. **Keep unit tests fast** - No system operations, mock when possible
2. **Make integration tests isolated** - Each test should be independent
3. **Clean up resources** - Always cleanup in test teardown or on exit
4. **Test error cases** - Test both success and failure paths
5. **Use descriptive names** - Test names should explain what's being tested
6. **Document assumptions** - Note any system requirements or limitations

## CI Performance

Typical CI run times:
- Syntax and lint: ~30 seconds
- Unit tests: ~1 minute
- Integration tests (per OS): ~3-5 minutes
- Total (all 8 OS): ~25-35 minutes

## Contributing

When adding new functionality to srv-ctl:

1. Add unit tests for pure functions
2. Add integration tests for system operations
3. Update this README if adding new test types
4. Ensure all tests pass locally before pushing
5. Check GitHub Actions results after pushing

## Support

For issues with tests:
1. Check this README first
2. Review test output for specific errors
3. Try running individual tests to isolate problems
4. Check GitHub Actions logs for CI failures
