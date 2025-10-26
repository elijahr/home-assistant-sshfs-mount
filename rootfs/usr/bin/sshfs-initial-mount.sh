#!/usr/bin/with-contenv bashio

set -eu

source /usr/bin/mount-helper.sh

bashio::log.info "Starting SSHFS Initial Mount Service..."

cleanup_mounts

bashio::log.info "Loading configuration..."

ALLOW_GUEST=$(bashio::config 'allow_guest')
SAMBA_USER=$(bashio::config 'samba_user' || echo "")
SAMBA_PASS=$(bashio::config 'samba_pass' || echo "")

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

if ! load_mount_config; then
    send_error_notification \
        "SSHFS Mount - Configuration Error" \
        "No mountpoints configured. Please add at least one mountpoint to your configuration."
    exit 1
fi

cleanup_ssh_keys "${MOUNTPOINT_SHARE_NAMES[@]}"

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

    bashio::log.info "==> Mounting ${share_name}: ${user}@${host}:${path} (auth: ${auth_type})"

    if mount_share "$share_name" "$host" "$port" "$user" "$path" "$auth_type" "$ssh_key" "$ssh_password"; then
        bashio::log.info "    SUCCESS: Mounted ${share_name} at /mnt/${share_name}"
        SUCCESSFUL_MOUNTS+=("$i")
        successful_count=$((successful_count + 1))
    else
        bashio::log.error "    FAILED: Could not mount ${share_name}"
        failed_count=$((failed_count + 1))
    fi
done

bashio::log.info "Mount summary: ${successful_count} successful, ${failed_count} failed"

if [ $successful_count -eq 0 ]; then
    bashio::log.error "All mounts failed. Cannot continue."
    send_error_notification \
        "SSHFS Mount - Startup Failed" \
        "All configured mounts failed to connect. Please check the add-on logs for details about each mount failure."
    exit 1
fi

bashio::log.info "Generating Samba configuration..."

cat /etc/smb.conf.template >/etc/samba/smb.conf

for i in "${SUCCESSFUL_MOUNTS[@]}"; do
    share_name="${MOUNTPOINT_SHARE_NAMES[$i]}"
    mount_dir="/mnt/${share_name}"

    bashio::log.info "Adding Samba share: [${share_name}] -> ${mount_dir}"

    if [ "$ALLOW_GUEST" = "true" ]; then
        cat >>/etc/samba/smb.conf <<EOF

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
        cat >>/etc/samba/smb.conf <<EOF

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

if [ "$ALLOW_GUEST" = "false" ]; then
    bashio::log.info "Configuring Samba user..."

    if ! id "${SAMBA_USER}" >/dev/null 2>&1; then
        bashio::log.info "Creating system user '${SAMBA_USER}'..."
        adduser -D -H -s /sbin/nologin "${SAMBA_USER}"
    fi

    smbpasswd -x "${SAMBA_USER}" >/dev/null 2>&1 || true

    if ! (
        echo "${SAMBA_PASS}"
        echo "${SAMBA_PASS}"
    ) | smbpasswd -a -s "${SAMBA_USER}" >/dev/null 2>&1; then
        bashio::log.error "Failed to create Samba user '${SAMBA_USER}'"
        send_error_notification \
            "SSHFS Mount - Samba User Error" \
            "Failed to create Samba user. Authentication will not work. Check add-on logs."
        exit 1
    fi

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

bashio::log.info "Validating Samba configuration..."

if ! command -v /usr/sbin/smbd >/dev/null 2>&1; then
    bashio::log.error "Samba daemon not found"
    send_error_notification \
        "SSHFS Mount - Samba Error" \
        "Samba server not found. The add-on may need to be reinstalled."
    exit 1
fi

if ! testparm -s /etc/samba/smb.conf >/dev/null 2>&1; then
    bashio::log.error "Invalid Samba configuration generated"
    send_error_notification \
        "SSHFS Mount - Configuration Error" \
        "Generated Samba configuration is invalid. Please report this issue."
    exit 1
fi

bashio::log.info "Samba configuration validated successfully"

CONTAINER_IP=$(hostname -i 2>/dev/null || echo "unknown")

bashio::log.info ""
bashio::log.info "=============================================================="
bashio::log.info "SSHFS mounts configured successfully"
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
bashio::log.info "See the Documentation tab for complete instructions!"
bashio::log.info "=============================================================="

bashio::log.info "Initial mount service completed successfully"
exit 0
