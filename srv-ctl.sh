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

function unlock_and_mount_device() {
    local l_device_uuid=$1
    local l_mapper=$2
    local l_mount=$3
    local l_key_file=$4

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

    if mountpoint -q "/mnt/$l_mount"; then
        echo -e "Mountpoint \"$l_mount\" mounted. Skipping.\n"
    else
        echo "Mounting $l_mount..."
        mkdir -p "/mnt/$l_mount"
        mount "/dev/mapper/$l_mapper" "/mnt/$l_mount"
        echo -e "Done\n"
    fi
}

function lock_and_unmount_device() {
    local l_device_uuid=$1
    local l_mapper=$2
    local l_mount=$3

    if mountpoint -q "/mnt/$l_mount"; then
        echo "Unmounting $l_mount..."
        umount "/mnt/$l_mount"
        echo -e "Done\n"
    else
        echo -e "Mountpoint \"$l_mount\" unmounted. Skipping.\n"
    fi

    if cryptsetup status "$l_mapper" >/dev/null; then
        echo "Locking $l_mapper..."
        cryptsetup luksClose "$l_mapper"
        echo -e "Done\n"
    else
        echo -e "Partition \"$l_mapper\" locked. Skipping.\n"
    fi
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

function unlock_and_mount_all() {
    unlock_and_mount_device "$ACTIVE_DATA_UUID" "$ACTIVE_DATA_MAPPER" "$ACTIVE_DATA_MOUNT" "no_key_file"
    unlock_and_mount_device "$STORAGE_DATA_UUID" "$STORAGE_DATA_MAPPER" "$STORAGE_DATA_MOUNT" "$STORAGE_DATA_KEY_FILE"
}

function lock_and_unmount_all() {
    lock_and_unmount_device "$STORAGE_DATA_UUID" "$STORAGE_DATA_MAPPER" "$STORAGE_DATA_MOUNT"
    lock_and_unmount_device "$ACTIVE_DATA_UUID" "$ACTIVE_DATA_MAPPER" "$ACTIVE_DATA_MOUNT"
}

start_all_services() {
    start_service "$ST_SERVICE"
}

stop_all_services() {
    stop_service "$ST_SERVICE"
}

function system_on() {
    stop_all_services
    unlock_and_mount_all
    start_all_services

    echo "========================"
    echo -e "   ST System is ON :)\n"
}

function system_off() {
    stop_all_services
    lock_and_unmount_all

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
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Please run as root"
        return $FAILURE
    fi

    if ! command -v cryptsetup &>/dev/null; then
        echo "ERROR: 'cryptsetup' utility is not available"
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
        unlock_and_mount_all
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
