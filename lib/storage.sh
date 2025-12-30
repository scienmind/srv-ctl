#!/usr/bin/env bash
#
# storage.sh - Storage Operations Library
#
# DESCRIPTION:
#   Provides low-level primitives for storage device management including
#   encryption (LUKS/BitLocker), LVM, mounting, and network shares.
#
# FUNCTIONS:
#   Device waiting:
#     - wait_for_device()          - Wait for device to appear by UUID
#
#   LVM management:
#     - verify_lvm()               - Verify LVM logical volume exists
#     - lvm_is_active()            - Check if LVM volume is active
#     - activate_lvm()             - Activate LVM logical volume
#     - deactivate_lvm()           - Deactivate LVM logical volume
#
#   Encryption:
#     - unlock_device()            - Unlock LUKS/BitLocker device
#     - lock_device()              - Lock encrypted device
#
#   Mounting:
#     - mount_device()             - Mount a device mapper to mount point
#     - unmount_device()           - Unmount a mount point
#     - mount_network_path()       - Mount network share (CIFS/NFS)
#
# DEPENDENCIES:
#   - cryptsetup 2.4.0+ (for LUKS and BitLocker support)
#   - lvm2 (for LVM operations)
#   - mount/umount commands
#   - build_mount_options() from os-utils.sh (for mount_network_path)
#
# NOTES:
#   - Functions return SUCCESS/FAILURE status codes
#   - Functions expect SUCCESS and FAILURE constants to be defined
#   - All mount operations use /mnt/ as the base directory
#

# -----------------------------------------------------------------------------
# Device Waiting
# -----------------------------------------------------------------------------

function wait_for_device() {
    local l_device_uuid="$1"

    for i in {1..5}; do
        if [ -e "/dev/disk/by-uuid/$l_device_uuid" ]; then
            return "$SUCCESS"
        else
            echo "Waiting for device $l_device_uuid... ${i}s"
            sleep 1
        fi
    done

    echo "ERROR: Device \"$l_device_uuid\" is not available."
    return "$FAILURE"
}

# -----------------------------------------------------------------------------
# LVM Management
# -----------------------------------------------------------------------------

function verify_lvm() {
    local l_lvm_name=$1
    local l_lvm_group=$2

    if lvdisplay "$l_lvm_group/$l_lvm_name" >/dev/null 2>&1; then
        return "$SUCCESS"
    fi

    echo "ERROR: Logical volume \"$l_lvm_name\" is not available."
    return "$FAILURE"
}

function lvm_is_active() {
    local l_lvm_name=$1
    local l_lvm_group=$2

    # Use lvs to check if volume is active (more reliable than parsing lvdisplay)
    if lvs --noheadings -o lv_active "$l_lvm_group/$l_lvm_name" 2>/dev/null | grep -q "active"; then
        return "$SUCCESS"
    else
        return "$FAILURE"
    fi
}

function activate_lvm() {
    local l_lvm_name=$1
    local l_lvm_group=$2

    if [ "$l_lvm_name" == "none" ] || [ "$l_lvm_group" == "none" ]; then
        return "$SUCCESS"
    fi

    verify_lvm "$l_lvm_name" "$l_lvm_group"
    if lvm_is_active "$l_lvm_name" "$l_lvm_group"; then
        echo -e "Logical volume \"$l_lvm_name\" already activated. Skipping.\n"
    else
        echo "Activating $l_lvm_name..."
        if ! lvchange -ay "$l_lvm_group/$l_lvm_name"; then
            echo "ERROR: Failed to activate LVM logical volume \"$l_lvm_group/$l_lvm_name\""
            return "$FAILURE"
        fi
        echo -e "Done\n"
    fi
}

function deactivate_lvm() {
    local l_lvm_name=$1
    local l_lvm_group=$2

    if [ "$l_lvm_name" == "none" ] || [ "$l_lvm_group" == "none" ]; then
        return "$SUCCESS"
    fi

    # Skip if LVM doesn't exist (may have been removed)
    if ! lvdisplay "$l_lvm_group/$l_lvm_name" >/dev/null 2>&1; then
        return "$SUCCESS"
    fi

    if lvm_is_active "$l_lvm_name" "$l_lvm_group"; then
        echo "Deactivating $l_lvm_name..."
        if ! lvchange -an "$l_lvm_group/$l_lvm_name"; then
            echo "WARNING: Failed to deactivate LVM logical volume \"$l_lvm_group/$l_lvm_name\""
            return "$FAILURE"
        fi
        echo -e "Done\n"
    else
        echo -e "Logical volume \"$l_lvm_name\" already deactivated. Skipping.\n"
    fi
}

# -----------------------------------------------------------------------------
# Encryption Operations
# -----------------------------------------------------------------------------

function unlock_device() {
    local l_device_uuid=$1
    local l_mapper=$2
    local l_key_file=$3
    local l_encryption_type=${4:-luks}

    if [ "$l_device_uuid" == "none" ] || [ "$l_mapper" == "none" ]; then
        echo -e "Device not configured (device_uuid=\"$l_device_uuid\"; mapper=\"$l_mapper\"). Skipping.\n"
        return "$SUCCESS"
    fi

    # Check if already unlocked
    if cryptsetup status "$l_mapper" >/dev/null 2>&1; then
        echo -e "Partition \"$l_mapper\" unlocked. Skipping.\n"
        return "$SUCCESS"
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
                return "$FAILURE"
            fi
        else
            if ! cryptsetup open --type bitlk "$l_device_path" "$l_mapper"; then
                echo "ERROR: Failed to unlock BitLocker device \"$l_device_uuid\" as \"$l_mapper\" with interactive password"
                return "$FAILURE"
            fi
        fi
    elif [ "$l_encryption_type" == "luks" ]; then
        # LUKS support
        if [ "$l_key_file" != "none" ] && [ -f "$l_key_file" ]; then
            if ! cryptsetup open --type luks "$l_device_path" "$l_mapper" --key-file="$l_key_file"; then
                echo "ERROR: Failed to unlock LUKS device \"$l_device_uuid\" as \"$l_mapper\" using key file"
                return "$FAILURE"
            fi
        else
            if ! cryptsetup open --type luks "$l_device_path" "$l_mapper"; then
                echo "ERROR: Failed to unlock LUKS device \"$l_device_uuid\" as \"$l_mapper\" with interactive password"
                return "$FAILURE"
            fi
        fi
    else
        echo "ERROR: Unsupported encryption type \"$l_encryption_type\" for device \"$l_mapper\""
        return "$FAILURE"
    fi

    echo -e "Done\n"
}

function lock_device() {
    local l_mapper=$1
    local l_encryption_type=${2:-luks}

    if [ "$l_mapper" == "none" ]; then
        return "$SUCCESS"
    fi

    if cryptsetup status "$l_mapper" >/dev/null 2>&1; then
        echo "Locking $l_mapper ($l_encryption_type)..."
        if ! cryptsetup close "$l_mapper"; then
            echo "WARNING: Failed to lock device \"$l_mapper\""
            return "$FAILURE"
        fi
        echo -e "Done\n"
    else
        echo -e "Partition \"$l_mapper\" locked. Skipping.\n"
    fi
}

# -----------------------------------------------------------------------------
# Mount Operations
# -----------------------------------------------------------------------------

function mount_device() {
    local l_mapper=$1
    local l_mount=$2
    local l_mount_options=${3:-defaults}

    if [ "$l_mapper" == "none" ] || [ "$l_mount" == "none" ]; then
        echo -e "Mount not configured (mapper=\"$l_mapper\"; mount_point=\"$l_mount\"). Skipping.\n"
        return "$SUCCESS"
    elif mountpoint -q "/mnt/$l_mount"; then
        echo -e "Mountpoint \"$l_mount\" mounted. Skipping.\n"
    else
        # Check if mapper device exists before attempting mount
        if [ ! -e "/dev/mapper/$l_mapper" ]; then
            echo -e "Mapper device \"/dev/mapper/$l_mapper\" does not exist. Skipping mount.\n"
            return "$SUCCESS"
        fi
        
        echo "Mounting $l_mount..."
        mkdir -p "/mnt/$l_mount"
        
        if ! mount -o "$l_mount_options" "/dev/mapper/$l_mapper" "/mnt/$l_mount"; then
            echo "ERROR: Failed to mount \"/dev/mapper/$l_mapper\" to \"/mnt/$l_mount\""
            return "$FAILURE"
        fi
        echo -e "Done\n"
    fi
}

function unmount_device() {
    local l_mount=$1

    if [ "$l_mount" == "none" ]; then
        return "$SUCCESS"
    fi

    if mountpoint -q "/mnt/$l_mount"; then
        echo "Unmounting $l_mount..."
        if ! umount "/mnt/$l_mount"; then
            echo "WARNING: Failed to unmount \"/mnt/$l_mount\""
            return "$FAILURE"
        else
            echo -e "Done\n"
        fi
    else
        echo -e "Mountpoint \"$l_mount\" unmounted. Skipping.\n"
    fi
}

function mount_network_path() {
    local l_network_path=$1
    local l_mount_path=$2
    local l_protocol=$3
    local l_credentials=$4
    local l_owner_user=$5
    local l_owner_group=$6
    local l_additional_options=$7

    if [ "$l_protocol" == "none" ]; then
        return "$SUCCESS"
    fi

    if mountpoint -q "/mnt/$l_mount_path"; then
        echo -e "Mountpoint \"$l_mount_path\" mounted. Skipping.\n"
    else
        echo "Mounting $l_mount_path..."
        mkdir -p "/mnt/$l_mount_path"
        
        # Build mount options from username/groupname
        local l_mount_options
        l_mount_options=$(build_mount_options "$l_owner_user" "$l_owner_group" "$l_additional_options")
        if [ $? -ne "$SUCCESS" ]; then
            echo "$l_mount_options"  # Print error message
            return "$FAILURE"
        fi
        
        # Prepend credentials if provided
        if [ "$l_credentials" != "none" ]; then
            l_mount_options="credentials=$l_credentials,$l_mount_options"
            echo "[DEBUG storage.sh] Credentials file: $l_credentials" >&2
            ls -la "$l_credentials" >&2 || echo "[DEBUG] Cannot stat credentials file" >&2
        fi
        
        # Debug: Show the exact mount command being executed
        echo "[DEBUG storage.sh] About to execute: mount -t $l_protocol -o $l_mount_options $l_network_path /mnt/$l_mount_path" >&2
        echo "[DEBUG storage.sh] UID=$UID EUID=$EUID USER=$USER HOME=$HOME" >&2
        
        if ! mount -t "$l_protocol" -o "$l_mount_options" "$l_network_path" "/mnt/$l_mount_path"; then
            echo "ERROR: Failed to mount network path \"$l_network_path\" to \"/mnt/$l_mount_path\""
            return "$FAILURE"
        fi
        echo -e "Done\n"
    fi
}
