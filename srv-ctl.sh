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
#   ./srv-ctl.sh validate-config    # Validate configuration
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

function wait_for_device() {
    local l_device_uuid="$1"

    for i in {1..5}; do
        if [ -e "/dev/disk/by-uuid/$l_device_uuid" ]; then
            return $SUCCESS
        else
            echo "Waiting for device $l_device_uuid... ${i}s"
            sleep 1
        fi
    done

    echo "ERROR: Device \"$l_device_uuid\" is not available."
    return $FAILURE
}

function verify_lvm() {
    local l_lvm_name=$1
    local l_lvm_group=$2

    if lvdisplay "$l_lvm_group/$l_lvm_name" >/dev/null; then
        return $SUCCESS
    fi

    echo "ERROR: Logic volume \"$l_lvm_name\" is not available."
    return $FAILURE
}

function lvm_is_active() {
    local l_lvm_name=$1
    local l_lvm_group=$2

    # Use lvs to check if volume is active (more reliable than parsing lvdisplay)
    if lvs --noheadings -o lv_active "$l_lvm_group/$l_lvm_name" 2>/dev/null | grep -q "active"; then
        return $SUCCESS
    else
        return $FAILURE
    fi
}

function activate_lvm() {
    local l_lvm_name=$1
    local l_lvm_group=$2

    if [ "$l_lvm_name" == "none" ] || [ "$l_lvm_group" == "none" ]; then
        return $SUCCESS
    fi

    verify_lvm "$l_lvm_name" "$l_lvm_group"
    if lvm_is_active "$l_lvm_name" "$l_lvm_group"; then
        echo -e "Logic volume \"$l_lvm_name\" already activated. Skipping.\n"
    else
        echo "Activating $l_lvm_name..."
        if ! lvchange -ay "$l_lvm_group/$l_lvm_name"; then
            echo "ERROR: Failed to activate LVM logical volume \"$l_lvm_group/$l_lvm_name\""
            return $FAILURE
        fi
        echo -e "Done\n"
    fi
}

function deactivate_lvm() {
    local l_lvm_name=$1
    local l_lvm_group=$2

    if [ "$l_lvm_name" == "none" ] || [ "$l_lvm_group" == "none" ]; then
        return $SUCCESS
    fi

    verify_lvm "$l_lvm_name" "$l_lvm_group"

    if lvm_is_active "$l_lvm_name" "$l_lvm_group"; then
        echo "Deactivating $l_lvm_name..."
        if ! lvchange -an "$l_lvm_group/$l_lvm_name"; then
            echo "WARNING: Failed to deactivate LVM logical volume \"$l_lvm_group/$l_lvm_name\""
            return $FAILURE
        fi
        echo -e "Done\n"
    else
        echo -e "Logic volume \"$l_lvm_name\" already deactivated. Skipping.\n"
    fi
}

function unlock_device() {
    local l_device_uuid=$1
    local l_mapper=$2
    local l_key_file=$3
    local l_encryption_type=${4:-luks}

    if [ "$l_device_uuid" == "none" ] || [ "$l_mapper" == "none" ]; then
        echo -e "Device not configured (device_uuid=\"$l_device_uuid\"; mapper=\"$l_mapper\"). Skipping.\n"
        return $SUCCESS
    fi

    # Check if already unlocked
    if cryptsetup status "$l_mapper" >/dev/null; then
        echo -e "Partition \"$l_mapper\" unlocked. Skipping.\n"
        return $SUCCESS
    fi

    echo "Unlocking $l_mapper ($l_encryption_type)..."
    wait_for_device "$l_device_uuid"
    
    # Determine the device path - prefer by-uuid for consistency
    local l_device_path="/dev/disk/by-uuid/$l_device_uuid"

    if [ "$l_encryption_type" == "bitlocker" ]; then
        # BitLocker support using native cryptsetup (v2.4.0+)
        if [ "$l_key_file" != "none" ] && [ -f "$l_key_file" ]; then
            if ! cryptsetup open --type bitlk "$l_device_path" "$l_mapper" --key-file="$l_key_file"; then
                echo "ERROR: Failed to unlock BitLocker device \"$l_device_uuid\" as \"$l_mapper\" using key file"
                return $FAILURE
            fi
        else
            if ! cryptsetup open --type bitlk "$l_device_path" "$l_mapper"; then
                echo "ERROR: Failed to unlock BitLocker device \"$l_device_uuid\" as \"$l_mapper\" with interactive password"
                return $FAILURE
            fi
        fi
    elif [ "$l_encryption_type" == "luks" ]; then
        # LUKS support
        if [ "$l_key_file" != "none" ] && [ -f "$l_key_file" ]; then
            if ! cryptsetup open --type luks "$l_device_path" "$l_mapper" --key-file="$l_key_file"; then
                echo "ERROR: Failed to unlock LUKS device \"$l_device_uuid\" as \"$l_mapper\" using key file"
                return $FAILURE
            fi
        else
            if ! cryptsetup open --type luks "$l_device_path" "$l_mapper"; then
                echo "ERROR: Failed to unlock LUKS device \"$l_device_uuid\" as \"$l_mapper\" with interactive password"
                return $FAILURE
            fi
        fi
    else
        echo "ERROR: Unsupported encryption type \"$l_encryption_type\" for device \"$l_mapper\""
        return $FAILURE
    fi

    echo -e "Done\n"
}

function lock_device() {
    local l_mapper=$1
    local l_encryption_type=${2:-luks}

    if cryptsetup status "$l_mapper" >/dev/null; then
        echo "Locking $l_mapper ($l_encryption_type)..."
        if ! cryptsetup close "$l_mapper"; then
            echo "WARNING: Failed to lock device \"$l_mapper\""
            return $FAILURE
        fi
        echo -e "Done\n"
    else
        echo -e "Partition \"$l_mapper\" locked. Skipping.\n"
    fi
}

function mount_network_path() {
    local l_network_path=$1
    local l_mount_path=$2
    local l_protocol=$3
    local l_credentials=$4
    local l_options=$5

    if [ "$l_protocol" == "none" ]; then
        return $SUCCESS
    fi

    if mountpoint -q "/mnt/$l_mount_path"; then
        echo -e "Mountpoint \"$l_mount_path\" mounted. Skipping.\n"
    else
        echo "Mounting $l_mount_path..."
        mkdir -p "/mnt/$l_mount_path"
        if ! mount -t "$l_protocol" -o "credentials=$l_credentials,$l_options" "$l_network_path" "/mnt/$l_mount_path"; then
            echo "ERROR: Failed to mount network path \"$l_network_path\" to \"/mnt/$l_mount_path\""
            return $FAILURE
        fi
        echo -e "Done\n"
    fi
}

function mount_device() {
    local l_mapper=$1
    local l_mount=$2

    if [ "$l_mapper" == "none" ] || [ "$l_mount" == "none" ]; then
        echo -e "Mount not configured (mapper=\"$l_mapper\"; mount_point=\"$l_mount\"). Skipping.\n"
    elif mountpoint -q "/mnt/$l_mount"; then
        echo -e "Mountpoint \"$l_mount\" mounted. Skipping.\n"
    else
        echo "Mounting $l_mount..."
        mkdir -p "/mnt/$l_mount"
        if ! mount "/dev/mapper/$l_mapper" "/mnt/$l_mount"; then
            echo "ERROR: Failed to mount \"/dev/mapper/$l_mapper\" to \"/mnt/$l_mount\""
            return $FAILURE
        fi
        echo -e "Done\n"
    fi
}

function unmount_device() {
    local l_mount=$1

    if mountpoint -q "/mnt/$l_mount"; then
        echo "Unmounting $l_mount..."
        if ! umount "/mnt/$l_mount"; then
            echo "WARNING: Failed to unmount \"/mnt/$l_mount\""
            return $FAILURE
        else
            echo -e "Done\n"
        fi
    else
        echo -e "Mountpoint \"$l_mount\" unmounted. Skipping.\n"
    fi
}

function open_device() {
    local l_mount=$1
    local l_mapper=$2
    local l_lvm_name=$3
    local l_lvm_group=$4
    local l_uuid=$5
    local l_key_file=$6
    local l_encryption_type=${7:-luks}

    # Step 1: Activate LVM
    activate_lvm "$l_lvm_name" "$l_lvm_group" || return $FAILURE

    # Step 2: Unlock encrypted device  
    unlock_device "$l_uuid" "$l_mapper" "$l_key_file" "$l_encryption_type" || return $FAILURE

    # Step 3: Mount device
    mount_device "$l_mapper" "$l_mount" || return $FAILURE
}

function close_device() {
    local l_mount=$1
    local l_mapper=$2
    local l_lvm_name=$3
    local l_lvm_group=$4
    local l_encryption_type=${5:-luks}

    # Continue cleanup even if individual steps fail
    unmount_device "$l_mount" || true
    lock_device "$l_mapper" "$l_encryption_type" || true
    deactivate_lvm "$l_lvm_name" "$l_lvm_group" || true
}

function stop_service() {
    local l_service=$1

    if [ "$l_service" == "none" ]; then
        return $SUCCESS
    fi

    echo "Stopping \"$l_service\" service..."
    if systemctl is-active --quiet "$l_service"; then
        if ! systemctl stop "$l_service"; then
            echo "WARNING: Failed to stop service \"$l_service\""
            return $FAILURE
        fi
        echo -e "Done\n"
    else
        echo -e "Service \"$l_service\" inactive. Skipping.\n"
    fi
}

function start_service() {
    local l_service=$1

    if [ "$l_service" == "none" ]; then
        return $SUCCESS
    fi

    echo "Starting \"$l_service\" service..."
    if systemctl is-active --quiet "$l_service"; then
        echo -e "Service \"$l_service\" active. Skipping.\n"
    else
        if ! systemctl start "$l_service"; then
            echo "ERROR: Failed to start service \"$l_service\""
            return $FAILURE
        fi
        echo -e "Done\n"
    fi
}

function open_all_devices() {
    # open primary data device
    open_device "$PRIMARY_DATA_MOUNT" "$PRIMARY_DATA_MAPPER" \
        "$PRIMARY_DATA_LVM_NAME" "$PRIMARY_DATA_LVM_GROUP" \
        "$PRIMARY_DATA_UUID" "$PRIMARY_DATA_KEY_FILE" "$PRIMARY_DATA_ENCRYPTION_TYPE"

    # open storage devices for service 1
    open_device "$STORAGE_1A_MOUNT" "$STORAGE_1A_MAPPER" \
        "$STORAGE_1A_LVM_NAME" "$STORAGE_1A_LVM_GROUP" \
        "$STORAGE_1A_UUID" "$STORAGE_1A_KEY_FILE" "$STORAGE_1A_ENCRYPTION_TYPE"

    open_device "$STORAGE_1B_MOUNT" "$STORAGE_1B_MAPPER" \
        "$STORAGE_1B_LVM_NAME" "$STORAGE_1B_LVM_GROUP" \
        "$STORAGE_1B_UUID" "$STORAGE_1B_KEY_FILE" "$STORAGE_1B_ENCRYPTION_TYPE"

    # open storage devices for service 2
    open_device "$STORAGE_2A_MOUNT" "$STORAGE_2A_MAPPER" \
        "$STORAGE_2A_LVM_NAME" "$STORAGE_2A_LVM_GROUP" \
        "$STORAGE_2A_UUID" "$STORAGE_2A_KEY_FILE" "$STORAGE_2A_ENCRYPTION_TYPE"

    open_device "$STORAGE_2B_MOUNT" "$STORAGE_2B_MAPPER" \
        "$STORAGE_2B_LVM_NAME" "$STORAGE_2B_LVM_GROUP" \
        "$STORAGE_2B_UUID" "$STORAGE_2B_KEY_FILE" "$STORAGE_2B_ENCRYPTION_TYPE"

    # open network storage
    mount_network_path "$NETWORK_SHARE_ADDRESS" "$NETWORK_SHARE_MOUNT" "$NETWORK_SHARE_PROTOCOL" \
        "$NETWORK_SHARE_CREDENTIALS" "$NETWORK_SHARE_OPTIONS"
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

function start_all_services() {
    if [ "$ST_SERVICE_1" != "none" ] || [ "$ST_SERVICE_2" != "none" ] || [ "$DOCKER_SERVICE" != "none" ]; then
        echo "Reloading systemd units..."
        if ! systemctl daemon-reload; then
            echo "ERROR: Failed to reload systemd units"
            return $FAILURE
        fi
        echo -e "Done\n"
    else
        echo -e "No services managed. Skipping.\n"
        return $SUCCESS
    fi

    start_service "$ST_SERVICE_1"
    start_service "$ST_SERVICE_2"
    start_service "$DOCKER_SERVICE"
}

function stop_all_services() {
    stop_service "$ST_SERVICE_1"
    stop_service "$ST_SERVICE_2"
    stop_service "$DOCKER_SERVICE"
}

function system_on() {
    stop_all_services
    open_all_devices
    start_all_services

    echo "========================"
    echo -e "   System is ON :)\n"
}

function system_off() {
    stop_all_services
    close_all_devices

    echo "========================"
    echo -e "   System is OFF :)\n"
}

function init_globals() {
    local l_config_file_name=$1
    local l_script_dir
    l_script_dir="$(
        cd "$(dirname "${BASH_SOURCE[0]}")"
        pwd
    )"
    local l_config_file="${l_script_dir}/${l_config_file_name}"

    if [ -f "$l_config_file" ]; then
        # shellcheck source=/dev/null
        source "$l_config_file"
    else
        echo "ERROR: Configuration file \"$l_config_file_name\" is missing."
        return $FAILURE
    fi
}

function validate_encryption_type() {
    local l_encryption_type=$1
    local l_device_name=$2

    if [ "$l_encryption_type" != "luks" ] && [ "$l_encryption_type" != "bitlocker" ]; then
        echo "ERROR: Unknown encryption type \"$l_encryption_type\" for device \"$l_device_name\""
        echo "       Supported types: luks, bitlocker"
        return $FAILURE
    fi
    
    return $SUCCESS
}

function verify_requirements() {
    if [ "$EUID" -ne "0" ]; then
        echo "ERROR: Please run as root"
        return $FAILURE
    fi

    if ! command -v cryptsetup &>/dev/null; then
        echo "ERROR: 'cryptsetup' utility is not available"
        return $FAILURE
    fi

    # Check for LVM utilities if needed
    if [ "${STORAGE_1A_LVM_NAME:-none}" != "none" ] || \
       [ "${STORAGE_1B_LVM_NAME:-none}" != "none" ] || \
       [ "${STORAGE_2A_LVM_NAME:-none}" != "none" ] || \
       [ "${STORAGE_2B_LVM_NAME:-none}" != "none" ] || \
       [ "${PRIMARY_DATA_LVM_NAME:-none}" != "none" ]; then
        if ! command -v lvdisplay &>/dev/null; then
            echo "ERROR: 'lvm2' utility is not available"
            return $FAILURE
        fi
    fi

    # Validate service configuration
    if [ "${ST_USER_1:-none}" != "none" ] && [ -z "${ST_SERVICE_1:-}" ]; then
        echo "ERROR: ST_USER_1 is set but ST_SERVICE_1 is empty"
        return $FAILURE
    fi
    if [ "${ST_USER_2:-none}" != "none" ] && [ -z "${ST_SERVICE_2:-}" ]; then
        echo "ERROR: ST_USER_2 is set but ST_SERVICE_2 is empty"
        return $FAILURE
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
            validate_encryption_type "$encryption_type" "$device_name" || return $FAILURE
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
        return $FAILURE
    fi
}

function validate_config() {
    echo "=== Configuration Validation ==="
    
    local errors=0
    
    # Check config file exists
    if [ ! -f "config.local" ]; then
        echo "❌ config.local not found (copy config.local.template and customize)"
        return $FAILURE
    fi
    echo "✅ config.local found"
    
    # Load configuration
    local l_script_dir
    l_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
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
    for device in "Primary:PRIMARY_DATA" "1A:STORAGE_1A" "1B:STORAGE_1B" "2A:STORAGE_2A" "2B:STORAGE_2B"; do
        IFS=':' read -r label prefix <<< "$device"
        local uuid_var="${prefix}_UUID"
        local uuid="${!uuid_var:-none}"
        
        if [ "$uuid" != "none" ]; then
            if _validate_device "$label" "$prefix"; then
                enabled=$((enabled + 1))
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
        return $SUCCESS
    else
        echo "❌ Validation FAILED ($errors errors)"
        return $FAILURE
    fi
}

# Helper functions for compact validation
function _validate_service() {
    local name=$1 user=$2 service=$3
    if [ "$user" != "none" ]; then
        if [ -z "$service" ]; then
            echo "❌ $name: user '$user' set but service empty"
            return $FAILURE
        else
            echo "✅ $name: $service (user: $user)"
        fi
    else
        echo "ℹ️  $name: disabled"
    fi
}

function _validate_simple_service() {
    local name=$1 service=$2
    if [ "$service" != "none" ]; then
        echo "✅ $name: $service"
    else
        echo "ℹ️  $name: disabled"
    fi
}

function _validate_device() {
    local label=$1 prefix=$2
    local encryption_var="${prefix}_ENCRYPTION_TYPE" 
    local key_file_var="${prefix}_KEY_FILE"
    
    local encryption="${!encryption_var:-luks}"
    local key_file="${!key_file_var:-none}"
    
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
    
    if [ "$has_errors" = true ]; then
        echo "❌ $label: $error_details"
        return $FAILURE
    else
        echo "✅ $label: $encryption$key_status"
        return $SUCCESS
    fi
}

function _validate_network_share() {
    local address="${NETWORK_SHARE_ADDRESS:-none}"
    local credentials="${NETWORK_SHARE_CREDENTIALS:-none}"
    
    if [ "$address" = "none" ]; then
        echo "ℹ️  disabled"
        return $SUCCESS
    fi
    
    if [ "$credentials" != "none" ] && [ ! -f "$credentials" ]; then
        echo "❌ enabled but credentials file not found: $credentials"
        return $FAILURE
    fi
    
    echo "✅ enabled ($address)"
    return $SUCCESS
}

function main() {
    if [ "$#" -ne 1 ]; then
        show_usage
        exit $FAILURE
    fi

    local l_action="$1"

    # Handle commands that don't need root privileges
    case "$l_action" in
    validate-config)
        validate_config
        return $?
        ;;
    help)
        show_usage
        exit $SUCCESS
        ;;
    -h)
        show_usage
        exit $SUCCESS
        ;;
    esac

    init_globals "config.local"
    verify_requirements "$@"

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
    *)
        show_usage
        exit $FAILURE
        ;;
    esac
}

main "$@"
exit $?
