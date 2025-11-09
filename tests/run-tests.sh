#!/bin/bash
# Main test runner script
# Runs syntax checks, unit tests, and integration tests

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

# Phase 1: Syntax and ShellCheck
run_syntax_checks() {
    log_phase "PHASE 1: Syntax and Lint Checks"
    
    local files=(
        "$PROJECT_ROOT/srv-ctl.sh"
        "$PROJECT_ROOT/lib/os-utils.sh"
        "$PROJECT_ROOT/lib/storage.sh"
    )
    
    local failed=0
    
    for file in "${files[@]}"; do
        log_info "Checking syntax: $(basename "$file")"
        if bash -n "$file"; then
            log_success "✓ Syntax check passed"
        else
            log_error "✗ Syntax check failed"
            failed=1
        fi
        
        # Run shellcheck if available
        if command -v shellcheck &>/dev/null; then
            log_info "Running shellcheck: $(basename "$file")"
            if shellcheck -x "$file"; then
                log_success "✓ ShellCheck passed"
            else
                log_error "✗ ShellCheck found issues"
                failed=1
            fi
        fi
    done
    
    if [[ $failed -eq 0 ]]; then
        PHASE_PASSED+=("Phase 1: Syntax and Lint")
        return 0
    else
        PHASE_FAILED+=("Phase 1: Syntax and Lint")
        return 1
    fi
}

# Phase 2: Unit Tests
run_unit_tests() {
    log_phase "PHASE 2: Unit Tests (bats)"
    
    if ! command -v bats &>/dev/null; then
        log_error "bats not installed. Install with: npm install -g bats"
        PHASE_FAILED+=("Phase 2: Unit Tests (bats not installed)")
        return 1
    fi
    
    local test_files=(
        "$SCRIPT_DIR/unit/test-os-utils.bats"
        "$SCRIPT_DIR/unit/test-storage.bats"
    )
    
    local failed=0
    
    for test_file in "${test_files[@]}"; do
        log_info "Running: $(basename "$test_file")"
        if bats "$test_file"; then
            log_success "✓ Unit tests passed"
        else
            log_error "✗ Unit tests failed"
            failed=1
        fi
    done
    
    if [[ $failed -eq 0 ]]; then
        PHASE_PASSED+=("Phase 2: Unit Tests")
        return 0
    else
        PHASE_FAILED+=("Phase 2: Unit Tests")
        return 1
    fi
}

# Phase 3: Integration Tests
run_integration_tests() {
    log_phase "PHASE 3: Integration Tests (requires root)"
    
    if [[ $EUID -ne 0 ]]; then
        log_error "Integration tests require root privileges"
        log_info "Run with: sudo $0 --integration"
        PHASE_FAILED+=("Phase 3: Integration Tests (root required)")
        return 1
    fi
    
    # Setup test environment
    log_info "Setting up test environment..."
    if ! "$SCRIPT_DIR/fixtures/setup-test-env.sh"; then
        log_error "Failed to setup test environment"
        PHASE_FAILED+=("Phase 3: Integration Tests (setup failed)")
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
        if "$test_file"; then
            log_success "✓ Integration tests passed"
        else
            log_error "✗ Integration tests failed"
            failed=1
        fi
    done
    
    # Cleanup test environment
    log_info "Cleaning up test environment..."
    "$SCRIPT_DIR/fixtures/cleanup-test-env.sh"
    
    if [[ $failed -eq 0 ]]; then
        PHASE_PASSED+=("Phase 3: Integration Tests")
        return 0
    else
        PHASE_FAILED+=("Phase 3: Integration Tests")
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
    local run_syntax=true
    local run_unit=true
    local run_integration=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --syntax-only)
                run_unit=false
                run_integration=false
                shift
                ;;
            --unit-only)
                run_syntax=false
                run_integration=false
                shift
                ;;
            --integration-only)
                run_syntax=false
                run_unit=false
                run_integration=true
                shift
                ;;
            --integration|--all)
                run_integration=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --syntax-only         Run only syntax and lint checks"
                echo "  --unit-only           Run only unit tests"
                echo "  --integration-only    Run only integration tests (requires root)"
                echo "  --integration, --all  Run all tests including integration (requires root)"
                echo "  --help                Show this help message"
                echo ""
                echo "Default: Run syntax checks and unit tests (no root required)"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    log_info "Starting test suite..."
    
    if $run_syntax; then
        run_syntax_checks || true
    fi
    
    if $run_unit; then
        run_unit_tests || true
    fi
    
    if $run_integration; then
        run_integration_tests || true
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
