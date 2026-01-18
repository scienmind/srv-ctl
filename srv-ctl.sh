#!/usr/bin/env bash
#
# srv-ctl.sh - Server Control Script
#
# DESCRIPTION:
#   Manages encrypted storage devices, LVM volumes, and services for a multi-user
#   Syncthing setup with support for LUKS/BitLocker encryption and network shares.
#
# FEATURES:
#   - Supports 2 parallel Syncthing services with separate users
#   - Manages 5 storage devices (1 primary data + 4 paired storage devices)
#   - LUKS and BitLocker encryption support via cryptsetup 2.4.0+
#   - Optional LVM integration per device
#   - Network share mounting (CIFS/NFS)
#   - Comprehensive error handling and validation
#
# USAGE:
#   ./srv-ctl.sh start              # Start all services and mount devices
#   ./srv-ctl.sh stop               # Stop services and unmount devices
#   ./srv-ctl.sh unlock-only        # Only unlock and mount devices
#   ./srv-ctl.sh stop-services-only # Only stop services
#   ./srv-ctl.sh validate-config    # Validate configuration without making changes
#   ./srv-ctl.sh help               # Show help message
#
# CONFIGURATION:
#   Copy config.local.template to config.local and customize settings.
#   All devices default to "none" (disabled) for safety.
#
# REQUIREMENTS:
#   - Run as root
#   - cryptsetup 2.4.0+ (for modern unified syntax and BitLocker support)
#   - lvm2 (if using LVM volumes)
#   - systemd (for service management)
#
set -eou pipefail

readonly SUCCESS=0
readonly FAILURE=1

# -----------------------------------------------------------------------------
# Source library files
# -----------------------------------------------------------------------------

# Get the directory where this script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Source library functions
# shellcheck disable=SC1091  # Library files exist
source "${SCRIPT_DIR}/lib/os-utils.sh"
source "${SCRIPT_DIR}/lib/storage.sh"


# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------

function show_usage() {
    echo "Usage:   $0  < start | stop | unlock-only | stop-services-only | validate-config | help | -h >"
    echo ""
    echo "Commands:"
    echo "  start               Start all services and mount devices"
    echo "  stop                Stop services and unmount devices"
    echo "  unlock-only         Only unlock and mount devices"
    echo "  stop-services-only  Only stop services"
    echo "  validate-config     Validate configuration without making changes"
    echo "  help, -h            Show this help message"
}


# -----------------------------------------------------------------------------
# Device Orchestration (combines library primitives)
# -----------------------------------------------------------------------------

function open_device() {
    local l_mount=$1
    local l_mapper=$2
    local l_lvm_name=$3
    local l_lvm_group=$4
    local l_uuid=$5
    local l_key_file=$6
    local l_encryption_type=${7:-luks}
    local l_owner_user=${8:-none}
    local l_owner_group=${9:-none}
    local l_additional_options=${10:-defaults}

    # Check if device is configured - UUID is the primary enable/disable flag
    if [ "$l_uuid" == "none" ]; then
        echo -e "Device not configured (uuid=\"none\"). Skipping.\n"
        return "$SUCCESS"
    fi

    # Validate that mapper and mount are also configured
    if [ "$l_mapper" == "none" ] || [ "$l_mount" == "none" ]; then
        echo "ERROR: Device UUID is set but mapper or mount point is 'none'"
        echo "       UUID: $l_uuid, MAPPER: $l_mapper, MOUNT: $l_mount"
        return "$FAILURE"
    fi

    # Build mount options from username/groupname
    local l_mount_options
    if ! l_mount_options=$(build_mount_options "$l_owner_user" "$l_owner_group" "$l_additional_options"); then
        echo "$l_mount_options"  # Print error message
        return "$FAILURE"
    fi

    # Step 1: Activate LVM (if configured)
    activate_lvm "$l_lvm_name" "$l_lvm_group" || return "$FAILURE"

    # Step 2: Unlock encrypted device  
    unlock_device "$l_uuid" "$l_mapper" "$l_key_file" "$l_encryption_type" || return "$FAILURE"

    # Step 3: Mount device
    mount_device "$l_mapper" "$l_mount" "$l_mount_options" "$l_owner_user" "$l_owner_group" || return "$FAILURE"
}

function close_device() {
    local l_mount=$1
    local l_mapper=$2
    local l_lvm_name=$3
    local l_lvm_group=$4
    local l_encryption_type=${5:-luks}

    # Check if any component is configured before attempting cleanup
    # Use mapper as the check since it's required for both lock and unmount
    if [ "$l_mapper" == "none" ] && [ "$l_mount" == "none" ]; then
        return "$SUCCESS"
    fi

    # Continue cleanup even if individual steps fail
    unmount_device "$l_mount" || true
    lock_device "$l_mapper" "$l_encryption_type" || true
    deactivate_lvm "$l_lvm_name" "$l_lvm_group" || true
}



function open_all_devices() {
    # open primary data device
    open_device "$PRIMARY_DATA_MOUNT" "$PRIMARY_DATA_MAPPER" \
        "$PRIMARY_DATA_LVM_NAME" "$PRIMARY_DATA_LVM_GROUP" \
        "$PRIMARY_DATA_UUID" "$PRIMARY_DATA_KEY_FILE" "$PRIMARY_DATA_ENCRYPTION_TYPE" \
        "$PRIMARY_DATA_OWNER_USER" "$PRIMARY_DATA_OWNER_GROUP" "$PRIMARY_DATA_MOUNT_OPTIONS" || return "$FAILURE"

    # open storage devices for service 1
    open_device "$STORAGE_1A_MOUNT" "$STORAGE_1A_MAPPER" \
        "$STORAGE_1A_LVM_NAME" "$STORAGE_1A_LVM_GROUP" \
        "$STORAGE_1A_UUID" "$STORAGE_1A_KEY_FILE" "$STORAGE_1A_ENCRYPTION_TYPE" \
        "$STORAGE_1A_OWNER_USER" "$STORAGE_1A_OWNER_GROUP" "$STORAGE_1A_MOUNT_OPTIONS" || return "$FAILURE"

    open_device "$STORAGE_1B_MOUNT" "$STORAGE_1B_MAPPER" \
        "$STORAGE_1B_LVM_NAME" "$STORAGE_1B_LVM_GROUP" \
        "$STORAGE_1B_UUID" "$STORAGE_1B_KEY_FILE" "$STORAGE_1B_ENCRYPTION_TYPE" \
        "$STORAGE_1B_OWNER_USER" "$STORAGE_1B_OWNER_GROUP" "$STORAGE_1B_MOUNT_OPTIONS" || return "$FAILURE"

    # open storage devices for service 2
    open_device "$STORAGE_2A_MOUNT" "$STORAGE_2A_MAPPER" \
        "$STORAGE_2A_LVM_NAME" "$STORAGE_2A_LVM_GROUP" \
        "$STORAGE_2A_UUID" "$STORAGE_2A_KEY_FILE" "$STORAGE_2A_ENCRYPTION_TYPE" \
        "$STORAGE_2A_OWNER_USER" "$STORAGE_2A_OWNER_GROUP" "$STORAGE_2A_MOUNT_OPTIONS" || return "$FAILURE"

    open_device "$STORAGE_2B_MOUNT" "$STORAGE_2B_MAPPER" \
        "$STORAGE_2B_LVM_NAME" "$STORAGE_2B_LVM_GROUP" \
        "$STORAGE_2B_UUID" "$STORAGE_2B_KEY_FILE" "$STORAGE_2B_ENCRYPTION_TYPE" \
        "$STORAGE_2B_OWNER_USER" "$STORAGE_2B_OWNER_GROUP" "$STORAGE_2B_MOUNT_OPTIONS" || return "$FAILURE"

    # open network storage
    mount_network_path "$NETWORK_SHARE_ADDRESS" "$NETWORK_SHARE_MOUNT" "$NETWORK_SHARE_PROTOCOL" \
        "$NETWORK_SHARE_CREDENTIALS" "$NETWORK_SHARE_OWNER_USER" "$NETWORK_SHARE_OWNER_GROUP" \
        "$NETWORK_SHARE_OPTIONS" || return "$FAILURE"
    
    return "$SUCCESS"
}

function close_all_devices() {
    # close storage devices for service 2
    close_device "$STORAGE_2B_MOUNT" "$STORAGE_2B_MAPPER" \
        "$STORAGE_2B_LVM_NAME" "$STORAGE_2B_LVM_GROUP" "$STORAGE_2B_ENCRYPTION_TYPE"

    close_device "$STORAGE_2A_MOUNT" "$STORAGE_2A_MAPPER" \
        "$STORAGE_2A_LVM_NAME" "$STORAGE_2A_LVM_GROUP" "$STORAGE_2A_ENCRYPTION_TYPE"

    # close storage devices for service 1
    close_device "$STORAGE_1B_MOUNT" "$STORAGE_1B_MAPPER" \
        "$STORAGE_1B_LVM_NAME" "$STORAGE_1B_LVM_GROUP" "$STORAGE_1B_ENCRYPTION_TYPE"

    close_device "$STORAGE_1A_MOUNT" "$STORAGE_1A_MAPPER" \
        "$STORAGE_1A_LVM_NAME" "$STORAGE_1A_LVM_GROUP" "$STORAGE_1A_ENCRYPTION_TYPE"

    # close primary data device
    close_device "$PRIMARY_DATA_MOUNT" "$PRIMARY_DATA_MAPPER" \
        "$PRIMARY_DATA_LVM_NAME" "$PRIMARY_DATA_LVM_GROUP" "$PRIMARY_DATA_ENCRYPTION_TYPE"

    # close network storage
    unmount_device "$NETWORK_SHARE_MOUNT"
}

# -----------------------------------------------------------------------------
# Service Orchestration
# -----------------------------------------------------------------------------

function start_all_services() {
    if [ "$ST_SERVICE_1" != "none" ] || [ "$ST_SERVICE_2" != "none" ] || [ "$DOCKER_SERVICE" != "none" ]; then
        echo "Reloading systemd units..."
        if ! systemctl daemon-reload; then
            echo "ERROR: Failed to reload systemd units"
            return "$FAILURE"
        fi
        echo -e "Done\n"
    else
        echo -e "No services managed. Skipping.\n"
        return "$SUCCESS"
    fi

    start_service "$ST_SERVICE_1" || return "$FAILURE"
    start_service "$ST_SERVICE_2" || return "$FAILURE"
    start_service "$DOCKER_SERVICE" || return "$FAILURE"
}

function stop_all_services() {
    stop_service "$ST_SERVICE_1"
    stop_service "$ST_SERVICE_2"
    stop_service "$DOCKER_SERVICE"
}

# -----------------------------------------------------------------------------
# High-level Workflows
# -----------------------------------------------------------------------------

function system_on() {
    stop_all_services
    
    if ! open_all_devices; then
        echo "ERROR: Failed to open devices. Rolling back..."
        close_all_devices
        return "$FAILURE"
    fi
    
    if ! start_all_services; then
        echo "ERROR: Failed to start services. Rolling back..."
        stop_all_services
        close_all_devices
        return "$FAILURE"
    fi

    echo "========================"
    echo -e "   System is ON :)\n"
}

function system_off() {
    stop_all_services
    close_all_devices

    echo "========================"
    echo -e "   System is OFF :)\n"
}

# -----------------------------------------------------------------------------
# Configuration and Requirements
# -----------------------------------------------------------------------------

function init_globals() {
    local l_config_file_name=$1
    local l_config_file="${SCRIPT_DIR}/${l_config_file_name}"

    if [ -f "$l_config_file" ]; then
        # shellcheck disable=SC1090  # Dynamic config file sourcing
        source "$l_config_file"
    else
        echo "ERROR: Configuration file \"$l_config_file_name\" is missing."
        return "$FAILURE"
    fi
}

function validate_encryption_type() {
    local l_encryption_type=$1
    local l_device_name=$2

    if [ "$l_encryption_type" != "luks" ] && [ "$l_encryption_type" != "bitlocker" ]; then
        echo "ERROR: Unknown encryption type \"$l_encryption_type\" for device \"$l_device_name\""
        echo "       Supported types: luks, bitlocker"
        return "$FAILURE"
    fi
    
    return "$SUCCESS"
}

function verify_requirements() {
    if [ "$EUID" -ne "0" ]; then
        echo "ERROR: Please run as root"
        return "$FAILURE"
    fi

    if ! command -v cryptsetup &>/dev/null; then
        echo "ERROR: 'cryptsetup' utility is not available"
        return "$FAILURE"
    fi

    # Check for LVM utilities if needed
    if [ "${STORAGE_1A_LVM_NAME:-none}" != "none" ] || \
       [ "${STORAGE_1B_LVM_NAME:-none}" != "none" ] || \
       [ "${STORAGE_2A_LVM_NAME:-none}" != "none" ] || \
       [ "${STORAGE_2B_LVM_NAME:-none}" != "none" ] || \
       [ "${PRIMARY_DATA_LVM_NAME:-none}" != "none" ]; then
        if ! command -v lvdisplay &>/dev/null; then
            echo "ERROR: 'lvm2' utility is not available"
            return "$FAILURE"
        fi
    fi

    # Validate service configuration
    if [ "${ST_USER_1:-none}" != "none" ] && [ -z "${ST_SERVICE_1:-}" ]; then
        echo "ERROR: ST_USER_1 is set but ST_SERVICE_1 is empty"
        return "$FAILURE"
    fi
    if [ "${ST_USER_2:-none}" != "none" ] && [ -z "${ST_SERVICE_2:-}" ]; then
        echo "ERROR: ST_USER_2 is set but ST_SERVICE_2 is empty"
        return "$FAILURE"
    fi

    # Validate encryption types for all configured devices
    local devices=(
        "PRIMARY_DATA:${PRIMARY_DATA_ENCRYPTION_TYPE:-luks}:${PRIMARY_DATA_UUID:-none}"
        "STORAGE_1A:${STORAGE_1A_ENCRYPTION_TYPE:-luks}:${STORAGE_1A_UUID:-none}"
        "STORAGE_1B:${STORAGE_1B_ENCRYPTION_TYPE:-luks}:${STORAGE_1B_UUID:-none}"
        "STORAGE_2A:${STORAGE_2A_ENCRYPTION_TYPE:-luks}:${STORAGE_2A_UUID:-none}"
        "STORAGE_2B:${STORAGE_2B_ENCRYPTION_TYPE:-luks}:${STORAGE_2B_UUID:-none}"
    )
    
    for device_info in "${devices[@]}"; do
        IFS=':' read -r device_name encryption_type device_uuid <<< "$device_info"
        # Only validate encryption type for enabled devices
        if [ "$device_uuid" != "none" ]; then
            validate_encryption_type "$encryption_type" "$device_name" || return "$FAILURE"
        fi
    done

    # Simple version check against minimum required version
    local l_cryptsetup_version_current
    l_cryptsetup_version_current="$(cryptsetup --version | cut -d" " -f2)"
    
    # Compare versions using sort -V (version sort)
    local l_version_check
    l_version_check="$(printf '%s\n%s\n' "$CRYPTSETUP_MIN_VERSION" "$l_cryptsetup_version_current" | sort -V | head -n1)"
    if [ "$l_version_check" != "$CRYPTSETUP_MIN_VERSION" ]; then
        echo "ERROR: cryptsetup version $CRYPTSETUP_MIN_VERSION or newer is required (current: $l_cryptsetup_version_current)"
        echo "       Version $CRYPTSETUP_MIN_VERSION+ is needed for full LUKS and BitLocker support"
        return "$FAILURE"
    fi
}

# -----------------------------------------------------------------------------
# Configuration Validation
# -----------------------------------------------------------------------------

function validate_config() {
    echo "=== Configuration Validation ==="
    
    local errors=0
    
    # Get script directory first
    local l_script_dir
    l_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check config file exists
    if [ ! -f "${l_script_dir}/config.local" ]; then
        echo "❌ config.local not found (copy config.local.template and customize)"
        return "$FAILURE"
    fi
    echo "✅ config.local found"
    
    # Load configuration
    # shellcheck disable=SC1090  # Dynamic config file sourcing
    source "${l_script_dir}/config.local"
    
    # Validate services
    echo ""
    echo "Services:"
    if ! _validate_service "ST1" "${ST_USER_1:-none}" "${ST_SERVICE_1:-}"; then
        errors=$((errors + 1))
    fi
    if ! _validate_service "ST2" "${ST_USER_2:-none}" "${ST_SERVICE_2:-}"; then
        errors=$((errors + 1))
    fi
    _validate_simple_service "Docker" "${DOCKER_SERVICE:-none}"
    
    # Validate devices
    echo ""
    echo "Storage Devices:"
    local enabled=0
    local -A mapper_names  # Track mapper names to detect duplicates
    
    for device in "Primary:PRIMARY_DATA" "1A:STORAGE_1A" "1B:STORAGE_1B" "2A:STORAGE_2A" "2B:STORAGE_2B"; do
        IFS=':' read -r label prefix <<< "$device"
        local uuid_var="${prefix}_UUID"
        local uuid="${!uuid_var:-none}"
        
        if [ "$uuid" != "none" ]; then
            if _validate_device "$label" "$prefix"; then
                enabled=$((enabled + 1))
                
                # Check for mapper name conflicts
                local mapper_var="${prefix}_MAPPER"
                local mapper="${!mapper_var:-none}"
                if [ "$mapper" != "none" ]; then
                    if [ -n "${mapper_names[$mapper]+_}" ]; then
                        echo "❌ Mapper conflict: '$mapper' used by both ${mapper_names[$mapper]} and $label"
                        errors=$((errors + 1))
                    else
                        mapper_names[$mapper]=$label
                    fi
                fi
            else
                errors=$((errors + 1))
            fi
        else
            echo "ℹ️  $label: disabled"
        fi
    done
    
    # Validate network share
    echo ""
    echo "Network Share:"
    if ! _validate_network_share; then
        errors=$((errors + 1))
    fi
    
    # Summary
    echo ""
    if [ "$errors" -eq 0 ]; then
        echo "🎉 Validation PASSED ($enabled devices enabled)"
        return "$SUCCESS"
    else
        echo "❌ Validation FAILED ($errors errors)"
        return "$FAILURE"
    fi
}

# Helper functions for compact validation
function _validate_service() {
    local name=$1 user=$2 service=$3
    if [ "$user" != "none" ]; then
        if [ -z "$service" ]; then
            echo "❌ $name: user '$user' set but service empty"
            return "$FAILURE"
        else
            echo "✅ $name: $service (user: $user)"
        fi
    else
        echo "ℹ️  $name: disabled"
    fi
    return "$SUCCESS"
}

function _validate_simple_service() {
    local name=$1 service=$2
    if [ "$service" != "none" ]; then
        echo "✅ $name: $service"
    else
        echo "ℹ️  $name: disabled"
    fi
    return "$SUCCESS"
}

function _validate_device() {
    local label=$1 prefix=$2
    local encryption_var="${prefix}_ENCRYPTION_TYPE" 
    local key_file_var="${prefix}_KEY_FILE"
    local owner_user_var="${prefix}_OWNER_USER"
    local owner_group_var="${prefix}_OWNER_GROUP"
    
    local encryption="${!encryption_var:-luks}"
    local key_file="${!key_file_var:-none}"
    local owner_user="${!owner_user_var:-none}"
    local owner_group="${!owner_group_var:-none}"
    
    local has_errors=false
    local error_details=""
    
    # Validate encryption type
    if [ "$encryption" != "luks" ] && [ "$encryption" != "bitlocker" ]; then
        error_details="invalid encryption '$encryption'"
        has_errors=true
    fi
    
    # Validate key file
    local key_status=""
    if [ "$key_file" != "none" ]; then
        if [ -f "$key_file" ]; then
            key_status=" (key: ✅)"
        else
            key_status=" (key: ❌)"
            if [ "$has_errors" = true ]; then
                error_details="$error_details, missing key file"
            else
                error_details="missing key file: $key_file"
            fi
            has_errors=true
        fi
    else
        key_status=" (interactive)"
    fi
    
    # Validate owner user
    if [ "$owner_user" != "none" ]; then
        if ! id "$owner_user" &>/dev/null; then
            if [ "$has_errors" = true ]; then
                error_details="$error_details, user '$owner_user' does not exist"
            else
                error_details="user '$owner_user' does not exist"
            fi
            has_errors=true
        fi
    fi
    
    # Validate owner group
    if [ "$owner_group" != "none" ]; then
        if ! getent group "$owner_group" &>/dev/null; then
            if [ "$has_errors" = true ]; then
                error_details="$error_details, group '$owner_group' does not exist"
            else
                error_details="group '$owner_group' does not exist"
            fi
            has_errors=true
        fi
    fi
    
    if [ "$has_errors" = true ]; then
        echo "❌ $label: $error_details"
        return "$FAILURE"
    else
        echo "✅ $label: $encryption$key_status"
        return "$SUCCESS"
    fi
}

function _validate_network_share() {
    local protocol="${NETWORK_SHARE_PROTOCOL:-none}"
    local address="${NETWORK_SHARE_ADDRESS:-none}"
    local credentials="${NETWORK_SHARE_CREDENTIALS:-none}"
    
    if [ "$protocol" = "none" ]; then
        echo "ℹ️  disabled"
        return "$SUCCESS"
    fi
    
    if [ "$credentials" != "none" ] && [ ! -f "$credentials" ]; then
        echo "❌ enabled but credentials file not found: $credentials"
        return "$FAILURE"
    fi
    
    echo "✅ enabled ($protocol: $address)"
    return "$SUCCESS"
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

function main() {
    if [ "$#" -ne 1 ]; then
        show_usage
        exit "$FAILURE"
    fi

    local l_action="$1"

    # Handle commands that don't need root privileges or requirements check
    case "$l_action" in
    validate-config)
        validate_config
        return $?
        ;;
    help|-h)
        show_usage
        exit "$SUCCESS"
        ;;
    start|stop|unlock-only|stop-services-only)
        # Valid commands that need root and requirements
        ;;
    *)
        # Invalid command
        show_usage
        exit "$FAILURE"
        ;;
    esac

    init_globals "config.local"
    verify_requirements

    case "$l_action" in
    start)
        system_on
        ;;
    stop)
        system_off
        ;;
    unlock-only)
        open_all_devices
        ;;
    stop-services-only)
        stop_all_services
        ;;
    esac
}

main "$@"
exit $?
