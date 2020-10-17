#!/usr/bin/env bash
set -eou pipefail

readonly SUCCESS=0
readonly FAILURE=1

function usage() {
    echo "Usage:   $0  start | stop | unlock-only | stop-services-only"
    return $FAILURE
}

function wait_for_device() {
    local l_device_uuid="$1"

    for i in {1..5}; do
        if ls "/dev/disk/by-uuid/$l_device_uuid" >/dev/null; then
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

    echo "ERROR: Logic volume \"$l_device_uuid\" is not available."
    return $FAILURE
}

function activate_lvm() {
    local l_lvm_name=$1
    local l_lvm_group=$2
    local l_lvm_status

    if [ "$l_lvm_name" == "none" ] || [ "$l_lvm_group" == "none" ]; then
        return $SUCCESS
    fi

    verify_lvm "$l_lvm_name" "$l_lvm_group"
    l_lvm_status=$(lvdisplay "$l_lvm_group/$l_lvm_name" | grep 'Status' | grep -v -c 'NOT available')

    if [ "$l_lvm_status" -eq "1" ]; then
        echo -e "Logic volume \"$l_lvm_name\" already activated. Skipping.\n"
    else
        echo "Activating $l_lvm_name..."
        lvchange -ay "$l_lvm_group/$l_lvm_name"
        echo -e "Done\n"
    fi
}

function deactivate_lvm() {
    local l_lvm_name=$1
    local l_lvm_group=$2
    local l_lvm_status

    if [ "$l_lvm_name" == "none" ] || [ "$l_lvm_group" == "none" ]; then
        return $SUCCESS
    fi

    verify_lvm "$l_lvm_name" "$l_lvm_group"
    l_lvm_status=$(lvdisplay "$l_lvm_group/$l_lvm_name" | grep 'Status' | grep -v -c 'NOT available')

    if [ "$l_lvm_status" -eq "1" ]; then
        echo "Deactivating $l_lvm_name..."
        lvchange -an "$l_lvm_group/$l_lvm_name"
        echo -e "Done\n"
    else
        echo -e "Logic volume \"$l_lvm_name\" already deactivated. Skipping.\n"
    fi
}

function unlock_device() {
    local l_device_uuid=$1
    local l_mapper=$2
    local l_key_file=$3

    if cryptsetup status "$l_mapper" >/dev/null; then
        echo -e "Partition \"$l_mapper\" unlocked. Skipping.\n"
    else
        echo "Unlocking $l_mapper..."
        wait_for_device "$l_device_uuid"

        if [ -f "$l_key_file" ]; then
            cryptsetup luksOpen "/dev/disk/by-uuid/$l_device_uuid" "$l_mapper" --key-file="$l_key_file"
        else
            cryptsetup luksOpen "/dev/disk/by-uuid/$l_device_uuid" "$l_mapper"
        fi

        echo -e "Done\n"
    fi
}

function lock_device() {
    local l_mapper=$1

    if cryptsetup status "$l_mapper" >/dev/null; then
        echo "Locking $l_mapper..."
        cryptsetup luksClose "$l_mapper"
        echo -e "Done\n"
    else
        echo -e "Partition \"$l_mapper\" locked. Skipping.\n"
    fi
}

function mount_device() {
    local l_mapper=$1
    local l_mount=$2

    if mountpoint -q "/mnt/$l_mount"; then
        echo -e "Mountpoint \"$l_mount\" mounted. Skipping.\n"
    else
        echo "Mounting $l_mount..."
        mkdir -p "/mnt/$l_mount"
        mount "/dev/mapper/$l_mapper" "/mnt/$l_mount"
        echo -e "Done\n"
    fi
}

function unmount_device() {
    local l_mount=$1

    if mountpoint -q "/mnt/$l_mount"; then
        echo "Unmounting $l_mount..."
        umount "/mnt/$l_mount"
        echo -e "Done\n"
    else
        echo -e "Mountpoint \"$l_mount\" unmounted. Skipping.\n"
    fi
}

function close_device() {
    local l_lvm_name=$1
    local l_lvm_group=$2
    local l_mapper=$3
    local l_mount=$4

    unmount_device "$l_mount"
    lock_device "$l_mapper"
}

function stop_service() {
    local l_service=$1

    echo "Stopping service..."
    if systemctl is-active --quiet "$l_service"; then
        systemctl stop "$l_service"
        echo -e "Done\n"
    else
        echo -e "Service \"$l_service\" inactive. Skipping.\n"
    fi
}

function start_service() {
    local l_service=$1

    echo "Starting service..."
    if systemctl is-active --quiet "$l_service"; then
        echo -e "Service \"$l_service\" active. Skipping.\n"
    else
        systemctl start "$l_service"
        echo -e "Done\n"
    fi
}

function open_all_devices() {
    # open active data device
    activate_lvm "no_lvm_name" "no_lvm_group"
    unlock_device "$ACTIVE_DATA_UUID" "$ACTIVE_DATA_MAPPER" "no_key_file"
    mount_device "$ACTIVE_DATA_MAPPER" "$ACTIVE_DATA_MOUNT"

    # open storage data device
    activate_lvm "$STORAGE_DATA_LVM_NAME" "$STORAGE_DATA_LVM_GROUP"
    unlock_device "$STORAGE_DATA_UUID" "$STORAGE_DATA_MAPPER" "$STORAGE_DATA_KEY_FILE"
    mount_device "$STORAGE_DATA_MAPPER" "$STORAGE_DATA_MOUNT"
}

function close_all_devices() {
    # close storage data device
    unmount_device "$STORAGE_DATA_MOUNT"
    lock_device "$STORAGE_DATA_MAPPER"
    deactivate_lvm "$STORAGE_DATA_LVM_NAME" "$STORAGE_DATA_LVM_GROUP"

    # close active data device
    unmount_device "$ACTIVE_DATA_MOUNT"
    lock_device "$ACTIVE_DATA_MAPPER"
    deactivate_lvm "no_lvm_name" "no_lvm_group"
}

start_all_services() {
    if [ "$ST_SERVICE" != "none" ]; then
        start_service "$ST_SERVICE"
    fi
}

stop_all_services() {
    if [ "$ST_SERVICE" != "none" ]; then
        stop_service "$ST_SERVICE"
    fi
}

function system_on() {
    stop_all_services
    open_all_devices
    start_all_services

    echo "========================"
    echo -e "   ST System is ON :)\n"
}

function system_off() {
    stop_all_services
    close_all_devices

    echo "========================"
    echo -e "   ST System is OFF :)\n"
}

function init_globals() {
    local l_config_file_name=$1
    local l_script_dir="$(
        cd "$(dirname "${BASH_SOURCE[0]}")"
        pwd
    )"
    local l_config_file="${l_script_dir}/${l_config_file_name}"

    if [ -f "$l_config_file" ]; then
        . "$l_config_file"
    else
        echo "ERROR: Configuration file \"$l_config_file_name\" is missing."
        return $FAILURE
    fi
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

    if [ "$STORAGE_DATA_LVM_NAME" != "none" ] &&
        command -v lvdisplay &>/dev/null; then
        echo "ERROR: 'lvm2' utility is not available"
        return $FAILURE
    fi

    local l_cryptsetup_version_major_current="$(cryptsetup --version | cut -d" " -f2 | cut -d"." -f1)"
    local l_cryptsetup_version_major_required="$LUKS_MIN_VERSION"

    if [ "$l_cryptsetup_version_major_current" -lt "$l_cryptsetup_version_major_required" ]; then
        echo "ERROR: Unsupported version of 'cryptsetup' utility, please use version $l_cryptsetup_version_major_required or newer"
        return $FAILURE
    fi
}

function main() {
    if [ "$#" -ne 1 ]; then
        usage
        return $FAILURE
    fi

    init_globals "config.local"
    verify_requirements $@

    local l_action="$1"

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
        usage
        ;;
    esac
}

main $@
exit $?
