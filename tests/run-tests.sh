#!/bin/bash
# Main test runner script
# Runs end-to-end and integration tests

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
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




# Phase 1: Integration Tests
run_integration_tests() {
    log_phase "PHASE 1: Integration Tests (requires root)"
    
    if [[ $EUID -ne 0 ]]; then
        log_error "Integration tests require root privileges"
        log_info "Run with: sudo $0 --integration"
        PHASE_FAILED+=("Phase 1: Integration Tests (root required)")
        return 1
    fi
    
    # Setup test environment
    log_info "Setting up test environment..."
    if ! "$SCRIPT_DIR/fixtures/setup-test-env.sh"; then
        log_error "Failed to setup test environment"
        log_info "Running cleanup after failed setup..."
        "$SCRIPT_DIR/fixtures/cleanup-test-env.sh" || true
        PHASE_FAILED+=("Phase 1: Integration Tests (setup failed)")
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
            log_success "✓ Integration tests passed"
        else
            exit_code=$?
            log_error "✗ Integration tests failed (exit code: $exit_code)"
            failed=1
        fi
    done
    
    # Cleanup test environment
    log_info "Cleaning up test environment..."
    "$SCRIPT_DIR/fixtures/cleanup-test-env.sh"
    
    if [[ $failed -eq 0 ]]; then
        PHASE_PASSED+=("Phase 1: Integration Tests")
        return 0
    else
        PHASE_FAILED+=("Phase 1: Integration Tests")
        return 1
    fi
}

# Phase 2: End-to-End Tests
run_e2e_tests() {
    log_phase "PHASE 2: End-to-End Tests"
    
    local test_file="$SCRIPT_DIR/e2e/test-e2e.sh"
    
    if [[ ! -f "$test_file" ]]; then
        log_error "E2E test file not found: $test_file"
        PHASE_FAILED+=("Phase 2: E2E Tests (file not found)")
        return 1
    fi
    
    log_info "Running: $(basename "$test_file")"
    if "$test_file"; then
        log_success "✓ E2E tests passed"
        PHASE_PASSED+=("Phase 2: End-to-End Tests")
        return 0
    else
        log_error "✗ E2E tests failed"
        PHASE_FAILED+=("Phase 2: End-to-End Tests")
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
        echo -e "${GREEN}Passed Phases:${NC}"
        for phase in "${PHASE_PASSED[@]}"; do
            echo -e "  ${GREEN}✓${NC} $phase"
        done
        echo ""
    fi
    
    if [[ ${#PHASE_FAILED[@]} -gt 0 ]]; then
        echo -e "${RED}Failed Phases:${NC}"
        for phase in "${PHASE_FAILED[@]}"; do
            echo -e "  ${RED}✗${NC} $phase"
        done
        echo ""
    fi
    
    local total_phases=$((${#PHASE_PASSED[@]} + ${#PHASE_FAILED[@]}))
    echo "Results: ${#PHASE_PASSED[@]}/$total_phases phases passed"
    echo ""
}

# Main
main() {
    local run_e2e=true
    local run_integration=true
    # No argument parsing for syntax/lint/unit phases; handled in dedicated CI jobs

    log_info "Starting test suite..."

    # Syntax/lint and unit tests are now run only in dedicated CI jobs

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
