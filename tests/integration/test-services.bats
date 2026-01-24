#!/usr/bin/env bats
# Integration tests for service management edge cases

# Source the os-utils library that contains service management functions
setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    
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
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh && start_service none"
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
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh && stop_service none"
    [ "$status" -eq 0 ]
}

@test "stop_service: Empty service name" {
    run sudo bash -c "source $PROJECT_ROOT/lib/os-utils.sh && stop_service ''"
    [ "$status" -ne 0 ]
}

@test "SAMBA_SERVICE integration: Service properly managed when configured" {
    # This test verifies that when SAMBA_SERVICE is configured in config.local,
    # it's properly included in the start_all_services and stop_all_services workflow
    
    # Backup existing config
    [ -f "$PROJECT_ROOT/config.local" ] && cp "$PROJECT_ROOT/config.local" "$PROJECT_ROOT/config.local.test_backup"
    
    # Create minimal config with SAMBA_SERVICE pointing to our test service
    cat > "$PROJECT_ROOT/config.local" <<EOF
readonly CRYPTSETUP_MIN_VERSION="2.4.0"
readonly ST_USER_1="none"
readonly ST_USER_2="none"
readonly ST_SERVICE_1="none"
readonly ST_SERVICE_2="none"
readonly DOCKER_SERVICE="none"
readonly SAMBA_SERVICE="test-dummy-service.service"

readonly PRIMARY_DATA_UUID="none"
readonly STORAGE_1A_UUID="none"
readonly STORAGE_1B_UUID="none"
readonly STORAGE_2A_UUID="none"
readonly STORAGE_2B_UUID="none"

readonly NETWORK_SHARE_PROTOCOL="none"
readonly NETWORK_SHARE_ADDRESS="none"
readonly NETWORK_SHARE_CREDENTIALS="none"
readonly NETWORK_SHARE_MOUNT="none"
readonly NETWORK_SHARE_OWNER_USER="none"
readonly NETWORK_SHARE_OWNER_GROUP="none"
readonly NETWORK_SHARE_OPTIONS="defaults"
EOF
    
    # Ensure test service is stopped
    sudo systemctl stop test-dummy-service 2>/dev/null || true
    
    # Source srv-ctl and call start_all_services
    run sudo bash -c "source $PROJECT_ROOT/config.local && source $PROJECT_ROOT/lib/os-utils.sh && start_all_services"
    [ "$status" -eq 0 ]
    
    # Verify test service is now running (Samba was started)
    run sudo systemctl is-active test-dummy-service
    [ "$status" -eq 0 ]
    
    # Call stop_all_services
    run sudo bash -c "source $PROJECT_ROOT/config.local && source $PROJECT_ROOT/lib/os-utils.sh && stop_all_services"
    [ "$status" -eq 0 ]
    
    # Verify test service is now stopped (Samba was stopped)
    run sudo systemctl is-active test-dummy-service
    [ "$status" -ne 0 ]
    
    # Restore config
    [ -f "$PROJECT_ROOT/config.local.test_backup" ] && mv "$PROJECT_ROOT/config.local.test_backup" "$PROJECT_ROOT/config.local"
    rm -f "$PROJECT_ROOT/config.local.test_backup"
}
