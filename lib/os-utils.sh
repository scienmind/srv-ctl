#!/usr/bin/env bash
#
# os-utils.sh - Operating System Utilities
#
# DESCRIPTION:
#   Provides OS-level utility functions for user/group resolution and
#   systemd service management.
#
# FUNCTIONS:
#   - get_uid_from_username()    - Resolve username to UID
#   - get_gid_from_groupname()   - Resolve group name to GID
#   - build_mount_options()      - Build mount options from usernames + additional options
#   - start_service()            - Start a systemd service
#   - stop_service()             - Stop a systemd service
#
# DEPENDENCIES:
#   - id command (for UID lookup)
#   - getent command (for GID lookup)
#   - systemctl (for service management)
#
# NOTES:
#   - Functions return SUCCESS/FAILURE status codes
#

# Constants (use existing values if already defined)
readonly SUCCESS=${SUCCESS:-0}
readonly FAILURE=${FAILURE:-1}

# -----------------------------------------------------------------------------
# User and Group Resolution
# -----------------------------------------------------------------------------

function get_uid_from_username() {
    local l_username=$1
    
    if [ "$l_username" == "none" ]; then
        echo ""
        return "$SUCCESS"
    fi
    
    local l_uid
    l_uid=$(id -u "$l_username" 2>/dev/null)
    
    if [ -z "$l_uid" ]; then
        echo "ERROR: User \"$l_username\" not found"
        return "$FAILURE"
    fi
    
    echo "$l_uid"
    return "$SUCCESS"
}

function get_gid_from_groupname() {
    local l_groupname=$1
    
    if [ "$l_groupname" == "none" ]; then
        echo ""
        return "$SUCCESS"
    fi
    
    local l_gid
    l_gid=$(getent group "$l_groupname" | cut -d: -f3)
    
    if [ -z "$l_gid" ]; then
        echo "ERROR: Group \"$l_groupname\" not found"
        return "$FAILURE"
    fi
    
    echo "$l_gid"
    return "$SUCCESS"
}

function build_mount_options() {
    local l_owner_user=$1
    local l_owner_group=$2
    local l_additional_options=$3

    local l_uid
    local l_gid
    local l_final_options=""
    
    # Get UID from username
    if [ "$l_owner_user" != "none" ]; then
        l_uid=$(get_uid_from_username "$l_owner_user")
        if [ $? -ne "$SUCCESS" ]; then
            echo "$l_uid"  # Print error message
            return "$FAILURE"
        fi
        l_final_options="uid=$l_uid"
    fi

    # Get GID from groupname
    if [ "$l_owner_group" != "none" ]; then
        l_gid=$(get_gid_from_groupname "$l_owner_group")
        if [ $? -ne "$SUCCESS" ]; then
            echo "$l_gid"  # Print error message
            return "$FAILURE"
        fi
        if [ -n "$l_final_options" ]; then
            l_final_options="$l_final_options,gid=$l_gid"
        else
            l_final_options="gid=$l_gid"
        fi
    fi

    # Add additional options (never combine 'defaults' with explicit options)
    if [ "$l_additional_options" != "none" ] && [ "$l_additional_options" != "defaults" ]; then
        if [ -n "$l_final_options" ]; then
            l_final_options="$l_final_options,$l_additional_options"
        else
            l_final_options="$l_additional_options"
        fi
    fi

    # If no options specified, use defaults
    if [ -z "$l_final_options" ]; then
        l_final_options="defaults"
    fi

    echo "$l_final_options"
    return "$SUCCESS"
}

# -----------------------------------------------------------------------------
# Service Management
# -----------------------------------------------------------------------------

function stop_service() {
    local l_service=$1


    if [ "$l_service" == "none" ]; then
        return "$SUCCESS"
    fi
    if [ -z "$l_service" ]; then
        echo "ERROR: stop_service called with empty service name" >&2
        return "$FAILURE"
    fi

    echo "Stopping \"$l_service\" service..."
    if systemctl is-active --quiet "$l_service"; then
        if ! systemctl stop "$l_service"; then
            echo "WARNING: Failed to stop service \"$l_service\""
            return "$FAILURE"
        fi
        echo -e "Done\n"
    else
        echo -e "Service \"$l_service\" inactive. Skipping.\n"
    fi
}

function start_service() {
    local l_service=$1


    if [ "$l_service" == "none" ]; then
        return "$SUCCESS"
    fi
    if [ -z "$l_service" ]; then
        echo "ERROR: start_service called with empty service name" >&2
        return "$FAILURE"
    fi

    echo "Starting \"$l_service\" service..."
    if systemctl is-active --quiet "$l_service"; then
        echo -e "Service \"$l_service\" active. Skipping.\\n"
    else
        if ! systemctl start "$l_service"; then
            echo "ERROR: Failed to start service \"$l_service\""
            return "$FAILURE"
        fi
        echo -e "Done\n"
    fi
}
