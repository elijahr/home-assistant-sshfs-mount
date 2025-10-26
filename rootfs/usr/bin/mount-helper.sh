#!/usr/bin/with-contenv bashio

set -eu

send_error_notification() {
    local title="$1"
    local message="$2"

    bashio::api.supervisor POST /core/api/services/persistent_notification/create \
        notification_id="sshfs_mount_error" \
        title="${title}" \
        message="${message}" \
        >/dev/null 2>&1 || true
}

validate_share_name() {
    local name="$1"

    if [ -z "$name" ]; then
        bashio::log.error "Share name cannot be empty"
        return 1
    fi

    if [ ${#name} -gt 80 ]; then
        bashio::log.error "Share name '${name}' is too long (max 80 characters)"
        return 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        bashio::log.error "Share name '${name}' contains invalid characters. Only alphanumeric, underscore, and hyphen are allowed."
        return 1
    fi

    return 0
}

generate_auto_share_name() {
    local index="$1"
    echo "mount_${index}"
}

unmount_share() {
    local mount_dir="$1"

    if [ ! -d "$mount_dir" ]; then
        return 0
    fi

    if mountpoint -q "$mount_dir"; then
        local fs_type
        fs_type=$(stat -f -c %T "$mount_dir" 2>/dev/null || echo "unknown")

        if [ "$fs_type" = "fuse.sshfs" ] || [ "$fs_type" = "fuseblk.sshfs" ]; then
            bashio::log.info "Unmounting SSHFS at ${mount_dir}..."
            fusermount -uz "$mount_dir" || umount -l "$mount_dir" || true
        fi
    fi

    return 0
}

cleanup_mounts() {
    bashio::log.info "Cleaning up existing SSHFS mounts..."

    local mount_dir
    for mount_dir in /mnt/*; do
        unmount_share "$mount_dir"
    done
}

cleanup_ssh_keys() {
    local valid_share_names=("$@")
    bashio::log.info "Cleaning up orphaned SSH keys..."

    local key_file
    for key_file in /root/.ssh/id_rsa_*; do
        if [ -f "$key_file" ]; then
            local key_share_name
            key_share_name=$(basename "$key_file" | sed 's/^id_rsa_//' | sed 's/\.pub$//')

            local found=0
            for valid_name in "${valid_share_names[@]}"; do
                if [ "$key_share_name" = "$valid_name" ]; then
                    found=1
                    break
                fi
            done

            if [ $found -eq 0 ]; then
                bashio::log.info "Removing orphaned key: ${key_file}"
                rm -f "$key_file" "${key_file}.pub"
            fi
        fi
    done
}

mount_share() {
    local share_name="$1"
    local host="$2"
    local port="$3"
    local user="$4"
    local path="$5"
    local auth_type="$6"
    local ssh_key="$7"
    local ssh_password="$8"

    local mount_dir="/mnt/${share_name}"

    mkdir -p "$mount_dir"

    if [ "$auth_type" = "key" ]; then
        local key_file="/root/.ssh/id_rsa_${share_name}"
        mkdir -p /root/.ssh
        echo "${ssh_key}" >"$key_file"
        chmod 600 "$key_file"

        if sshfs -o allow_other \
            -o StrictHostKeyChecking=no \
            -o IdentityFile="$key_file" \
            -p "$port" \
            "${user}@${host}:${path}" \
            "$mount_dir" 2>&1; then
            return 0
        else
            return 1
        fi

    elif [ "$auth_type" = "password" ]; then
        if echo "$ssh_password" | sshpass -p "$ssh_password" sshfs -o allow_other \
            -o StrictHostKeyChecking=no \
            -o password_stdin \
            -p "$port" \
            "${user}@${host}:${path}" \
            "$mount_dir" 2>&1; then
            return 0
        else
            return 1
        fi
    fi

    return 1
}

check_mount_health() {
    local mount_dir="$1"
    local timeout="${2:-5}"

    if [ ! -d "$mount_dir" ]; then
        return 1
    fi

    if ! mountpoint -q "$mount_dir"; then
        return 1
    fi

    if ! timeout "$timeout" stat "$mount_dir" >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

calculate_backoff_delay() {
    local retry_count="$1"
    local base_delay="${2:-5}"
    local max_delay="${3:-3600}"

    local delay=$((base_delay * (2 ** retry_count)))

    if [ "$delay" -gt "$max_delay" ]; then
        echo "$max_delay"
    else
        echo "$delay"
    fi
}

load_mount_config() {
    declare -g -a MOUNTPOINT_SHARE_NAMES
    declare -g -a MOUNTPOINT_HOSTS
    declare -g -a MOUNTPOINT_PORTS
    declare -g -a MOUNTPOINT_USERS
    declare -g -a MOUNTPOINT_PATHS
    declare -g -a MOUNTPOINT_AUTH_TYPES
    declare -g -a MOUNTPOINT_SSH_KEYS
    declare -g -a MOUNTPOINT_SSH_PASSWORDS
    declare -g MOUNTPOINT_COUNT=0

    local index=0

    while true; do
        if ! bashio::config.exists "mountpoints[${index}]"; then
            break
        fi

        local share_name
        share_name=$(bashio::config "mountpoints[${index}].share_name" || echo "")
        local remote_host
        remote_host=$(bashio::config "mountpoints[${index}].remote_host" || echo "")
        local remote_port
        remote_port=$(bashio::config "mountpoints[${index}].remote_port" || echo "22")
        local remote_user
        remote_user=$(bashio::config "mountpoints[${index}].remote_user" || echo "")
        local remote_path
        remote_path=$(bashio::config "mountpoints[${index}].remote_path" || echo "")
        local auth_type
        auth_type=$(bashio::config "mountpoints[${index}].auth_type" || echo "")
        local ssh_key
        ssh_key=$(bashio::config "mountpoints[${index}].ssh_key" || echo "")
        local ssh_password
        ssh_password=$(bashio::config "mountpoints[${index}].ssh_password" || echo "")

        if [ -z "$remote_host" ]; then
            bashio::log.error "Mountpoint ${index}: remote_host is required"
            return 1
        fi

        if [ -z "$remote_user" ]; then
            bashio::log.error "Mountpoint ${index}: remote_user is required"
            return 1
        fi

        if [ -z "$remote_path" ]; then
            bashio::log.error "Mountpoint ${index}: remote_path is required"
            return 1
        fi

        if [ -z "$auth_type" ]; then
            bashio::log.error "Mountpoint ${index}: auth_type is required (must be 'key' or 'password')"
            return 1
        fi

        if [ -z "$share_name" ]; then
            share_name=$(generate_auto_share_name "$index")
            bashio::log.info "Mountpoint ${index}: Auto-generated share name: ${share_name}"
        fi

        if ! validate_share_name "$share_name"; then
            bashio::log.error "Mountpoint ${index}: Invalid share name"
            return 1
        fi

        if ! [[ "$remote_port" =~ ^[0-9]+$ ]] || [ "$remote_port" -lt 1 ] || [ "$remote_port" -gt 65535 ]; then
            bashio::log.error "Mountpoint ${index} (${share_name}): Invalid port '${remote_port}' (must be 1-65535)"
            return 1
        fi

        for existing_share in "${MOUNTPOINT_SHARE_NAMES[@]}"; do
            if [ "$share_name" = "$existing_share" ]; then
                bashio::log.error "Duplicate share name '${share_name}' found at mountpoint ${index}."
                return 1
            fi
        done

        if [ "$auth_type" != "key" ] && [ "$auth_type" != "password" ]; then
            bashio::log.error "Mountpoint ${index} (${share_name}): Invalid auth_type '${auth_type}'"
            bashio::log.error "Must be 'key' or 'password'"
            return 1
        fi

        if [ "$auth_type" = "key" ]; then
            if [ -z "$ssh_key" ]; then
                bashio::log.error "Mountpoint ${index} (${share_name}): SSH key is required when auth_type='key'"
                bashio::log.error "Either provide an ssh_key or change auth_type to 'password'"
                return 1
            fi
            if [ -n "$ssh_password" ]; then
                bashio::log.error "Mountpoint ${index} (${share_name}): Both ssh_key and ssh_password provided"
                bashio::log.error "Please specify only one authentication method"
                return 1
            fi
            if [ ${#ssh_key} -lt 100 ]; then
                bashio::log.warning "Mountpoint ${index} (${share_name}): SSH key seems very short - is it complete?"
            fi
        elif [ "$auth_type" = "password" ]; then
            if [ -z "$ssh_password" ]; then
                bashio::log.error "Mountpoint ${index} (${share_name}): SSH password is required when auth_type='password'"
                bashio::log.error "Either provide an ssh_password or change auth_type to 'key'"
                return 1
            fi
            if [ -n "$ssh_key" ]; then
                bashio::log.error "Mountpoint ${index} (${share_name}): Both ssh_key and ssh_password provided"
                bashio::log.error "Please specify only one authentication method"
                return 1
            fi
        fi

        MOUNTPOINT_SHARE_NAMES+=("$share_name")
        MOUNTPOINT_HOSTS+=("$remote_host")
        MOUNTPOINT_PORTS+=("$remote_port")
        MOUNTPOINT_USERS+=("$remote_user")
        MOUNTPOINT_PATHS+=("$remote_path")
        MOUNTPOINT_AUTH_TYPES+=("$auth_type")
        MOUNTPOINT_SSH_KEYS+=("$ssh_key")
        MOUNTPOINT_SSH_PASSWORDS+=("$ssh_password")

        MOUNTPOINT_COUNT=$((MOUNTPOINT_COUNT + 1))
        index=$((index + 1))
    done

    if [ $MOUNTPOINT_COUNT -eq 0 ]; then
        bashio::log.error "No mountpoints configured. Please add at least one mountpoint."
        return 1
    fi

    bashio::log.info "Found ${MOUNTPOINT_COUNT} mountpoint(s) to configure."
    return 0
}
