#!/usr/bin/env bats
# Integration tests for service management edge cases

# Source the os-utils library that contains service management functions
setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SUCCESS=0
    export FAILURE=1
    
    # Create a test service unit file for testing
    sudo tee /etc/systemd/system/test-dummy-service.service > /dev/null <<EOF
[Unit]
Description=Dummy Test Service for srv-ctl Tests
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Create a test service that fails to start
    sudo tee /etc/systemd/system/test-failing-service.service > /dev/null <<EOF
[Unit]
Description=Failing Test Service for srv-ctl Tests
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/false
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    
    # Ensure services are stopped initially
    sudo systemctl stop test-dummy-service 2>/dev/null || true
    sudo systemctl stop test-failing-service 2>/dev/null || true
}

teardown_file() {
    # Cleanup test services
    sudo systemctl stop test-dummy-service 2>/dev/null || true
    sudo systemctl stop test-failing-service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/test-dummy-service.service
    sudo rm -f /etc/systemd/system/test-failing-service.service
    sudo systemctl daemon-reload
}

setup() {
    # Source the library functions
    source "$PROJECT_ROOT/lib/os-utils.sh"
}

@test "start_service: Start a stopped service" {
    sudo systemctl stop test-dummy-service 2>/dev/null || true
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh; start_service test-dummy-service"
    [ "$status" -eq 0 ]
    run sudo systemctl is-active test-dummy-service
    [ "$status" -eq 0 ]
}

@test "start_service: Start already running service (idempotent)" {
    sudo systemctl start test-dummy-service
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh; start_service test-dummy-service"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "active. Skipping" ]]
}

@test "start_service: Service doesn't exist" {
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh; start_service nonexistent-service-12345"
    [ "$status" -ne 0 ]
}

@test "start_service: Service fails to start" {
    sudo systemctl stop test-failing-service 2>/dev/null || true
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh; start_service test-failing-service"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Failed to start" ]]
}

@test "start_service: Service name is 'none'" {
    run sudo bash -c "export SUCCESS=0 FAILURE=1 && source $PROJECT_ROOT/lib/os-utils.sh && start_service none"
    [ "$status" -eq 0 ]
}

@test "start_service: Empty service name" {
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh; start_service ''"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "empty service name" ]]
}

@test "stop_service: Stop a running service" {
    sudo systemctl start test-dummy-service
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh; stop_service test-dummy-service"
    [ "$status" -eq 0 ]
    run sudo systemctl is-active test-dummy-service
    [ "$status" -ne 0 ]
}

@test "stop_service: Stop already stopped service (idempotent)" {
    sudo systemctl stop test-dummy-service 2>/dev/null || true
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh; stop_service test-dummy-service"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "inactive. Skipping" ]]
}

@test "stop_service: Service doesn't exist" {
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh; stop_service nonexistent-service-12345"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "inactive. Skipping" ]]
}

@test "stop_service: Service name is 'none'" {
    run sudo bash -c "export SUCCESS=0 FAILURE=1 && source $PROJECT_ROOT/lib/os-utils.sh && stop_service none"
    [ "$status" -eq 0 ]
}

@test "stop_service: Empty service name" {
    run sudo bash -c "export SUCCESS=0 FAILURE=1 && source $PROJECT_ROOT/lib/os-utils.sh && stop_service ''"
    [ "$status" -ne 0 ]
}
