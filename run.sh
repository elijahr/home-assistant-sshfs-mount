#!/usr/bin/with-contenv bashio

# ==============================================================================
# Home Assistant Add-on: SSHFS Mount with Multiple Mountpoints
# ==============================================================================

set -e

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Send error notification to Home Assistant UI
send_error_notification() {
    local title="$1"
    local message="$2"

    bashio::api.supervisor POST /core/api/services/persistent_notification/create \
        notification_id="sshfs_mount_error" \
        title="${title}" \
        message="${message}" \
        >/dev/null 2>&1 || true
}

# Validate share name format (alphanumeric, underscore, hyphen only)
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

# Generate auto share name based on index
generate_auto_share_name() {
    local index="$1"
    echo "mount_${index}"
}

# Unmount all SSHFS mounts in /mnt/*
cleanup_mounts() {
    bashio::log.info "Cleaning up existing SSHFS mounts..."

    local mount_dir
    for mount_dir in /mnt/*; do
        if [ -d "$mount_dir" ] && mountpoint -q "$mount_dir"; then
            local fs_type
            fs_type=$(stat -f -c %T "$mount_dir" 2>/dev/null || echo "unknown")

            if [ "$fs_type" = "fuse.sshfs" ] || [ "$fs_type" = "fuseblk.sshfs" ]; then
                bashio::log.info "Unmounting SSHFS at ${mount_dir}..."
                fusermount -u "$mount_dir" || umount -l "$mount_dir" || true
            fi
        fi
    done
}

# Clean orphaned SSH keys
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

# ==============================================================================
# STARTUP CLEANUP
# ==============================================================================

cleanup_mounts

# ==============================================================================
# LOAD AND VALIDATE CONFIGURATION
# ==============================================================================

bashio::log.info "Loading configuration..."

ALLOW_GUEST=$(bashio::config 'allow_guest')
SAMBA_USER=$(bashio::config 'samba_user' || echo "")
SAMBA_PASS=$(bashio::config 'samba_pass' || echo "")

# Validate Samba credentials if guest access is disabled
if [ "$ALLOW_GUEST" = "false" ]; then
    if [ -z "$SAMBA_USER" ]; then
        bashio::log.error "Samba username is required when guest access is disabled."
        bashio::log.error "Either enable guest access or provide a Samba username."
        send_error_notification \
            "SSHFS Mount - Configuration Error" \
            "Samba username is required when guest access is disabled. Please check your configuration."
        exit 1
    fi

    if [ -z "$SAMBA_PASS" ]; then
        bashio::log.error "Samba password is required when guest access is disabled."
        bashio::log.error "Either enable guest access or provide a Samba password."
        send_error_notification \
            "SSHFS Mount - Configuration Error" \
            "Samba password is required when guest access is disabled. Please check your configuration."
        exit 1
    fi

    if [[ ! "$SAMBA_USER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        bashio::log.error "Samba username '${SAMBA_USER}' contains invalid characters."
        bashio::log.error "Only alphanumeric, underscore, and hyphen are allowed."
        exit 1
    fi

    if [ ${#SAMBA_USER} -gt 32 ]; then
        bashio::log.error "Samba username is too long (max 32 characters)"
        exit 1
    fi

    bashio::log.info "Using authenticated Samba access with user: ${SAMBA_USER}"
else
    bashio::log.warning "==================== SECURITY WARNING ===================="
    bashio::log.warning "Guest access is ENABLED!"
    bashio::log.warning "Anyone on your network can access the mounted shares"
    bashio::log.warning "without authentication. Use only on trusted networks."
    bashio::log.warning "========================================================"
fi

# Parse mountpoints array
declare -a MOUNTPOINT_SHARE_NAMES
declare -a MOUNTPOINT_HOSTS
declare -a MOUNTPOINT_PORTS
declare -a MOUNTPOINT_USERS
declare -a MOUNTPOINT_PATHS
declare -a MOUNTPOINT_AUTH_TYPES
declare -a MOUNTPOINT_SSH_KEYS
declare -a MOUNTPOINT_SSH_PASSWORDS

mountpoint_count=0
index=0

while true; do
    if ! bashio::config.exists "mountpoints[${index}]"; then
        break
    fi

    # Read mountpoint configuration
    share_name=$(bashio::config "mountpoints[${index}].share_name" || echo "")
    remote_host=$(bashio::config "mountpoints[${index}].remote_host" || echo "")
    remote_port=$(bashio::config "mountpoints[${index}].remote_port" || echo "22")
    remote_user=$(bashio::config "mountpoints[${index}].remote_user" || echo "")
    remote_path=$(bashio::config "mountpoints[${index}].remote_path" || echo "")
    auth_type=$(bashio::config "mountpoints[${index}].auth_type" || echo "")
    ssh_key=$(bashio::config "mountpoints[${index}].ssh_key" || echo "")
    ssh_password=$(bashio::config "mountpoints[${index}].ssh_password" || echo "")

    # Validate required fields
    if [ -z "$remote_host" ]; then
        bashio::log.error "Mountpoint ${index}: remote_host is required"
        exit 1
    fi

    if [ -z "$remote_user" ]; then
        bashio::log.error "Mountpoint ${index}: remote_user is required"
        exit 1
    fi

    if [ -z "$remote_path" ]; then
        bashio::log.error "Mountpoint ${index}: remote_path is required"
        exit 1
    fi

    if [ -z "$auth_type" ]; then
        bashio::log.error "Mountpoint ${index}: auth_type is required (must be 'key' or 'password')"
        exit 1
    fi

    # Generate share_name if not provided
    if [ -z "$share_name" ]; then
        share_name=$(generate_auto_share_name "$index")
        bashio::log.info "Mountpoint ${index}: Auto-generated share name: ${share_name}"
    fi

    # Validate share_name format
    if ! validate_share_name "$share_name"; then
        bashio::log.error "Mountpoint ${index}: Invalid share name"
        exit 1
    fi

    # Validate remote_port
    if ! [[ "$remote_port" =~ ^[0-9]+$ ]] || [ "$remote_port" -lt 1 ] || [ "$remote_port" -gt 65535 ]; then
        bashio::log.error "Mountpoint ${index} (${share_name}): Invalid port '${remote_port}' (must be 1-65535)"
        exit 1
    fi

    # Check for duplicate share names
    for existing_share in "${MOUNTPOINT_SHARE_NAMES[@]}"; do
        if [ "$share_name" = "$existing_share" ]; then
            bashio::log.error "Duplicate share name '${share_name}' found at mountpoint ${index}."
            exit 1
        fi
    done

    # Validate auth_type
    if [ "$auth_type" != "key" ] && [ "$auth_type" != "password" ]; then
        bashio::log.error "Mountpoint ${index} (${share_name}): Invalid auth_type '${auth_type}'"
        bashio::log.error "Must be 'key' or 'password'"
        exit 1
    fi

    # Validate auth credentials
    if [ "$auth_type" = "key" ]; then
        if [ -z "$ssh_key" ]; then
            bashio::log.error "Mountpoint ${index} (${share_name}): SSH key is required when auth_type='key'"
            bashio::log.error "Either provide an ssh_key or change auth_type to 'password'"
            exit 1
        fi
        if [ -n "$ssh_password" ]; then
            bashio::log.error "Mountpoint ${index} (${share_name}): Both ssh_key and ssh_password provided"
            bashio::log.error "Please specify only one authentication method"
            exit 1
        fi
        if [ ${#ssh_key} -lt 100 ]; then
            bashio::log.warning "Mountpoint ${index} (${share_name}): SSH key seems very short - is it complete?"
        fi
    elif [ "$auth_type" = "password" ]; then
        if [ -z "$ssh_password" ]; then
            bashio::log.error "Mountpoint ${index} (${share_name}): SSH password is required when auth_type='password'"
            bashio::log.error "Either provide an ssh_password or change auth_type to 'key'"
            exit 1
        fi
        if [ -n "$ssh_key" ]; then
            bashio::log.error "Mountpoint ${index} (${share_name}): Both ssh_key and ssh_password provided"
            bashio::log.error "Please specify only one authentication method"
            exit 1
        fi
    fi

    # Store configuration
    MOUNTPOINT_SHARE_NAMES+=("$share_name")
    MOUNTPOINT_HOSTS+=("$remote_host")
    MOUNTPOINT_PORTS+=("$remote_port")
    MOUNTPOINT_USERS+=("$remote_user")
    MOUNTPOINT_PATHS+=("$remote_path")
    MOUNTPOINT_AUTH_TYPES+=("$auth_type")
    MOUNTPOINT_SSH_KEYS+=("$ssh_key")
    MOUNTPOINT_SSH_PASSWORDS+=("$ssh_password")

    mountpoint_count=$((mountpoint_count + 1))
    index=$((index + 1))
done

if [ $mountpoint_count -eq 0 ]; then
    bashio::log.error "No mountpoints configured. Please add at least one mountpoint."
    send_error_notification \
        "SSHFS Mount - Configuration Error" \
        "No mountpoints configured. Please add at least one mountpoint to your configuration."
    exit 1
fi

bashio::log.info "Found ${mountpoint_count} mountpoint(s) to configure."

# Clean up SSH keys for share names no longer in config
cleanup_ssh_keys "${MOUNTPOINT_SHARE_NAMES[@]}"

# ==============================================================================
# MOUNT SSHFS SHARES
# ==============================================================================

declare -a SUCCESSFUL_MOUNTS
successful_count=0
failed_count=0

for i in "${!MOUNTPOINT_SHARE_NAMES[@]}"; do
    share_name="${MOUNTPOINT_SHARE_NAMES[$i]}"
    host="${MOUNTPOINT_HOSTS[$i]}"
    port="${MOUNTPOINT_PORTS[$i]}"
    user="${MOUNTPOINT_USERS[$i]}"
    path="${MOUNTPOINT_PATHS[$i]}"
    auth_type="${MOUNTPOINT_AUTH_TYPES[$i]}"
    ssh_key="${MOUNTPOINT_SSH_KEYS[$i]}"
    ssh_password="${MOUNTPOINT_SSH_PASSWORDS[$i]}"

    mount_dir="/mnt/${share_name}"

    bashio::log.info "==> Mounting ${share_name}: ${user}@${host}:${path} (auth: ${auth_type})"

    # Create mount directory
    mkdir -p "$mount_dir"

    # Setup authentication
    if [ "$auth_type" = "key" ]; then
        # Setup SSH key
        key_file="/root/.ssh/id_rsa_${share_name}"
        mkdir -p /root/.ssh
        echo "${ssh_key}" > "$key_file"
        chmod 600 "$key_file"

        # Mount with SSH key
        if sshfs -o allow_other \
                  -o StrictHostKeyChecking=no \
                  -o IdentityFile="$key_file" \
                  -p "$port" \
                  "${user}@${host}:${path}" \
                  "$mount_dir"; then
            bashio::log.info "    SUCCESS: Mounted ${share_name} at ${mount_dir}"
            SUCCESSFUL_MOUNTS+=("$i")
            successful_count=$((successful_count + 1))
        else
            bashio::log.error "    FAILED: Could not mount ${share_name}"
            failed_count=$((failed_count + 1))
        fi

    elif [ "$auth_type" = "password" ]; then
        # Mount with password using sshpass
        if echo "$ssh_password" | sshpass -p "$ssh_password" sshfs -o allow_other \
                  -o StrictHostKeyChecking=no \
                  -o password_stdin \
                  -p "$port" \
                  "${user}@${host}:${path}" \
                  "$mount_dir"; then
            bashio::log.info "    SUCCESS: Mounted ${share_name} at ${mount_dir}"
            SUCCESSFUL_MOUNTS+=("$i")
            successful_count=$((successful_count + 1))
        else
            bashio::log.error "    FAILED: Could not mount ${share_name}"
            failed_count=$((failed_count + 1))
        fi
    fi
done

# Log summary
bashio::log.info "Mount summary: ${successful_count} successful, ${failed_count} failed"

if [ $successful_count -eq 0 ]; then
    bashio::log.error "All mounts failed. Cannot continue."
    send_error_notification \
        "SSHFS Mount - Startup Failed" \
        "All configured mounts failed to connect. Please check the add-on logs for details about each mount failure."
    exit 1
fi

# ==============================================================================
# GENERATE SAMBA CONFIGURATION
# ==============================================================================

bashio::log.info "Generating Samba configuration..."

# Start with global section from template
cat /smb.conf.template > /etc/samba/smb.conf

# Add share for each successful mount
for i in "${SUCCESSFUL_MOUNTS[@]}"; do
    share_name="${MOUNTPOINT_SHARE_NAMES[$i]}"
    mount_dir="/mnt/${share_name}"

    bashio::log.info "Adding Samba share: [${share_name}] -> ${mount_dir}"

    if [ "$ALLOW_GUEST" = "true" ]; then
        # Guest access enabled - no authentication required
        cat >> /etc/samba/smb.conf <<EOF

[${share_name}]
   path = ${mount_dir}
   browsable = yes
   writable = yes
   guest ok = yes
   read only = no
   create mask = 0777
   directory mask = 0777
   force user = root
EOF
    else
        # Authenticated access - require valid user
        cat >> /etc/samba/smb.conf <<EOF

[${share_name}]
   path = ${mount_dir}
   browsable = yes
   writable = yes
   guest ok = no
   read only = no
   create mask = 0755
   directory mask = 0755
   valid users = ${SAMBA_USER}
   force user = root
EOF
    fi
done

# ==============================================================================
# SETUP SAMBA USER
# ==============================================================================

if [ "$ALLOW_GUEST" = "false" ]; then
    bashio::log.info "Configuring Samba user..."

    # Create system user if it doesn't exist
    if ! id "${SAMBA_USER}" >/dev/null 2>&1; then
        bashio::log.info "Creating system user '${SAMBA_USER}'..."
        adduser -D -H -s /sbin/nologin "${SAMBA_USER}"
    fi

    # Remove existing Samba user if present (ensures clean state)
    smbpasswd -x "${SAMBA_USER}" >/dev/null 2>&1 || true

    # Add user to Samba with password
    if ! (echo "${SAMBA_PASS}"; echo "${SAMBA_PASS}") | smbpasswd -a -s "${SAMBA_USER}" >/dev/null 2>&1; then
        bashio::log.error "Failed to create Samba user '${SAMBA_USER}'"
        send_error_notification \
            "SSHFS Mount - Samba User Error" \
            "Failed to create Samba user. Authentication will not work. Check add-on logs."
        exit 1
    fi

    # Verify user was created successfully
    if ! pdbedit -L 2>/dev/null | grep -q "^${SAMBA_USER}:"; then
        bashio::log.error "Samba user verification failed"
        send_error_notification \
            "SSHFS Mount - Samba User Error" \
            "Samba user creation could not be verified. Authentication may not work."
        exit 1
    fi

    bashio::log.info "Samba user '${SAMBA_USER}' configured successfully"
else
    bashio::log.info "Skipping Samba user configuration (guest access enabled)"
fi

# ==============================================================================
# VALIDATE SAMBA CONFIGURATION
# ==============================================================================

bashio::log.info "Validating Samba configuration..."

# Test that smbd exists and is executable
if ! command -v /usr/sbin/smbd >/dev/null 2>&1; then
    bashio::log.error "Samba daemon not found"
    send_error_notification \
        "SSHFS Mount - Samba Error" \
        "Samba server not found. The add-on may need to be reinstalled."
    exit 1
fi

# Validate Samba configuration syntax
if ! testparm -s /etc/samba/smb.conf >/dev/null 2>&1; then
    bashio::log.error "Invalid Samba configuration generated"
    send_error_notification \
        "SSHFS Mount - Configuration Error" \
        "Generated Samba configuration is invalid. Please report this issue."
    exit 1
fi

bashio::log.info "Samba configuration validated successfully"

# ==============================================================================
# START SAMBA SERVER
# ==============================================================================

bashio::log.info ""
bashio::log.info "=============================================================="
bashio::log.info "SUCCESS! SSHFS Mount add-on is running"
bashio::log.info "=============================================================="
bashio::log.info ""
bashio::log.info "Available Samba shares:"
for i in "${SUCCESSFUL_MOUNTS[@]}"; do
    share="${MOUNTPOINT_SHARE_NAMES[$i]}"
    host="${MOUNTPOINT_HOSTS[$i]}"
    user="${MOUNTPOINT_USERS[$i]}"
    path="${MOUNTPOINT_PATHS[$i]}"
    bashio::log.info "  - [${share}] -> ${user}@${host}:${path}"
done
bashio::log.info ""

# Get container network information
CONTAINER_IP=$(hostname -i 2>/dev/null || echo "unknown")

bashio::log.info "Container IP Address: ${CONTAINER_IP}"
bashio::log.info ""
bashio::log.info "NEXT STEPS - Mount these shares in Home Assistant:"
bashio::log.info "  1. Go to Settings > System > Storage"
bashio::log.info "  2. Click 'Add network storage'"
bashio::log.info "  3. Select 'CIFS' protocol"
bashio::log.info "  4. Configure connection:"
bashio::log.info "     - Server: ${CONTAINER_IP}"
bashio::log.info "     - Workgroup: WORKGROUP"
bashio::log.info "     - Share: (pick from list above)"
if [ "$ALLOW_GUEST" = "true" ]; then
    bashio::log.info "     - Authentication: None (guest access enabled)"
else
    bashio::log.info "     - Username: ${SAMBA_USER}"
    bashio::log.info "     - Password: (your samba_pass from config)"
fi
bashio::log.info ""
bashio::log.info "IMPORTANT NOTES:"
bashio::log.info "  - The IP address shown above is stable across normal reboots"
bashio::log.info "  - If the IP changes after a major system update, check these logs"
bashio::log.info "    for the new IP and update your network storage configuration"
bashio::log.info "  - Port 445 is exposed internally only (no external access)"
bashio::log.info "  - This avoids conflicts with other Samba services"
bashio::log.info ""
bashio::log.info "See the Documentation tab for complete instructions!"
bashio::log.info "=============================================================="
bashio::log.info ""
bashio::log.info "Starting Samba daemon..."

exec /usr/sbin/smbd -F --no-process-group
