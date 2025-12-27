#!/bin/bash
# Main test runner script
# Runs integration tests (with root) and/or E2E tests
#
# Usage:
#   ./run-tests.sh                    # Run all tests (integration + E2E)
#   ./run-tests.sh --integration-only # Run only integration tests (requires root)
#   ./run-tests.sh --e2e-only         # Run only E2E tests
#
# Note: This script is designed to run inside a VM (via tests/vm/run-tests.sh).
# For local development, use:
#   - Unit tests: bats tests/unit/*.bats
#   - E2E CLI tests (no root): ./tests/e2e/test-e2e.sh

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test results
PHASE_PASSED=()
PHASE_FAILED=()

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_phase() {
    echo ""
    echo "========================================="
    echo "$*"
    echo "========================================="
    echo ""
}

# Integration Tests (requires root, runs in VM)
run_integration_tests() {
    log_phase "Integration Tests (requires root)"
    
    if [[ $EUID -ne 0 ]]; then
        log_error "Integration tests require root privileges"
        log_info "Run with: sudo $0 --integration-only"
        PHASE_FAILED+=("Integration Tests (root required)")
        return 1
    fi
    
    # Setup test environment
    log_info "Setting up test environment..."
    if ! "$SCRIPT_DIR/fixtures/setup-test-env.sh"; then
        log_error "Failed to setup test environment"
        log_info "Running cleanup after failed setup..."
        "$SCRIPT_DIR/fixtures/cleanup-test-env.sh" || true
        PHASE_FAILED+=("Integration Tests (setup failed)")
        return 1
    fi
    
    local test_files=(
        "$SCRIPT_DIR/integration/test-luks.sh"
        "$SCRIPT_DIR/integration/test-lvm.sh"
        "$SCRIPT_DIR/integration/test-mount.sh"
    )
    
    local failed=0
    
    for test_file in "${test_files[@]}"; do
        log_info "Running: $(basename "$test_file")"
        if "$test_file" 2>&1; then
            log_success "✓ $(basename "$test_file") passed"
        else
            local exit_code=$?
            log_error "✗ $(basename "$test_file") failed (exit code: $exit_code)"
            failed=1
        fi
    done
    
    # Cleanup test environment
    log_info "Cleaning up test environment..."
    "$SCRIPT_DIR/fixtures/cleanup-test-env.sh"
    
    if [[ $failed -eq 0 ]]; then
        PHASE_PASSED+=("Integration Tests")
        return 0
    else
        PHASE_FAILED+=("Integration Tests")
        return 1
    fi
}

# End-to-End Tests
run_e2e_tests() {
    log_phase "End-to-End Tests"
    
    local test_file="$SCRIPT_DIR/e2e/test-e2e.sh"
    
    if [[ ! -f "$test_file" ]]; then
        log_error "E2E test file not found: $test_file"
        PHASE_FAILED+=("E2E Tests (file not found)")
        return 1
    fi
    
    log_info "Running: $(basename "$test_file")"
    if "$test_file"; then
        log_success "✓ E2E tests passed"
        PHASE_PASSED+=("End-to-End Tests")
        return 0
    else
        log_error "✗ E2E tests failed"
        PHASE_FAILED+=("End-to-End Tests")
        return 1
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "========================================="
    echo "TEST SUMMARY"
    echo "========================================="
    echo ""
    
    if [[ ${#PHASE_PASSED[@]} -gt 0 ]]; then
        echo -e "${GREEN}Passed:${NC}"
        for phase in "${PHASE_PASSED[@]}"; do
            echo -e "  ${GREEN}✓${NC} $phase"
        done
        echo ""
    fi
    
    if [[ ${#PHASE_FAILED[@]} -gt 0 ]]; then
        echo -e "${RED}Failed:${NC}"
        for phase in "${PHASE_FAILED[@]}"; do
            echo -e "  ${RED}✗${NC} $phase"
        done
        echo ""
    fi
    
    local total_phases=$((${#PHASE_PASSED[@]} + ${#PHASE_FAILED[@]}))
    echo "Results: ${#PHASE_PASSED[@]}/$total_phases phases passed"
    echo ""
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Run srv-ctl test suites.

Options:
    --integration-only    Run only integration tests (requires root)
    --e2e-only           Run only E2E tests  
    -h, --help           Show this help message

Note: This script is designed to run inside a VM (via tests/vm/run-tests.sh).
For local development, use:
    - Unit tests: bats tests/unit/*.bats
    - Lint: shellcheck -x srv-ctl.sh lib/*.sh

EOF
}

# Main
main() {
    local run_e2e=true
    local run_integration=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --integration-only)
                run_e2e=false
                shift
                ;;
            --e2e-only)
                run_integration=false
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    log_info "Starting test suite..."

    if $run_integration; then
        run_integration_tests || true
    fi

    if $run_e2e; then
        run_e2e_tests || true
    fi

    print_summary

    # Exit with error if any phase failed
    if [[ ${#PHASE_FAILED[@]} -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
