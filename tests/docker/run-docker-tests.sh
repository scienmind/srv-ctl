#!/bin/bash
# Build and run tests in Docker container
# This provides complete isolation from the host system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_step() {
    echo -e "${YELLOW}[STEP]${NC} $*"
}

# Parse arguments
TEST_ARGS="--all"
REBUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --rebuild)
            REBUILD=true
            shift
            ;;
        --syntax-only|--unit-only|--e2e-only|--integration-only)
            TEST_ARGS="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--rebuild] [--syntax-only|--unit-only|--e2e-only|--integration-only]"
            exit 1
            ;;
    esac
done

log_info "Docker-based Test Runner for srv-ctl"
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed or not in PATH"
    echo "Install Docker: https://docs.docker.com/engine/install/"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo "ERROR: Docker daemon is not running"
    echo "Start Docker and try again"
    exit 1
fi

# Build image if needed
IMAGE_NAME="srv-ctl-test"
if $REBUILD || ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    log_step "Building Docker image..."
    docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile" "$PROJECT_ROOT"
    echo ""
fi

# Run tests in container
log_step "Running tests in isolated container..."
echo ""

# Run with --privileged to allow device operations
# Remove container after tests complete
docker run \
    --rm \
    --privileged \
    --name srv-ctl-test-runner \
    "$IMAGE_NAME" \
    $TEST_ARGS

exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
    log_info "✓ All tests passed in Docker container"
else
    log_info "✗ Some tests failed (exit code: $exit_code)"
fi

exit $exit_code
