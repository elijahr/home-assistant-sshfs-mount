# SSHFS Mount Add-on Documentation

## Overview

This add-on allows you to mount remote SSH servers using SSHFS and share them via Samba/CIFS network shares. This is useful for:

- Accessing media files stored on a NAS
- Using remote storage for backups
- Accessing files from another server or cloud instance
- Making remote directories available to Home Assistant and other devices

## How It Works

1. The add-on connects to your remote server(s) via SSH
2. Mounts the remote filesystem using SSHFS
3. Shares the mounted files via Samba (SMB/CIFS protocol)
4. You can then mount these shares in Home Assistant OS or access from other devices

## Prerequisites

Before configuring this add-on, you need:

- **SSH access** to the remote server(s) you want to mount
- **Either:**
  - An SSH private key that has access to the remote server, OR
  - A password for SSH authentication
- **Network connectivity** from Home Assistant to the remote server

## Configuration

### Global Settings

**Allow Guest Access** (checkbox)
- Enable unauthenticated access to all Samba shares
- ⚠️ **Security Warning**: Anyone on your network can access files without credentials
- Only use on trusted/private networks
- When disabled, you must provide Samba username and password

**Samba Username** (text)
- Username for accessing the Samba shares
- Required when guest access is disabled
- Can be any username you choose (doesn't need to match remote server)
- Only alphanumeric, underscore, and hyphen characters allowed

**Samba Password** (password)
- Password for the Samba user
- Required when guest access is disabled
- Keep this secure - it protects all your mounted shares

### Reconnection Settings (Advanced)

The add-on includes automatic reconnection for failed mounts. These settings are optional and have sensible defaults.

**Reconnect Enabled** (checkbox, default: true)
- Enable automatic reconnection for failed mounts
- When enabled, the add-on continuously monitors mount health
- Failed mounts will automatically retry with exponential backoff
- Disable only if you want manual control over reconnections

**Reconnect Check Interval** (number, default: 60)
- How often (in seconds) to check mount health
- Range: 10-600 seconds
- Lower values = faster detection but more overhead
- Recommended: 60 seconds for most use cases

**Reconnect Use Events** (checkbox, default: true)
- Use network event monitoring for immediate reconnection
- When network changes are detected, health checks trigger instantly
- Falls back to interval-based checking if events unavailable
- Recommended: keep enabled for best responsiveness

**Reconnect Base Delay** (number, default: 5)
- Base delay in seconds for exponential backoff
- First retry after 5s, then 10s, 20s, 40s, etc.
- Range: 1-60 seconds
- Lower values = more aggressive retries

**Reconnect Max Delay** (number, default: 3600)
- Maximum delay (in seconds) between retry attempts
- Caps the exponential backoff at this value
- Range: 60-7200 seconds (1 minute to 2 hours)
- Default: 3600 seconds (1 hour)

**Reconnect Notify HA** (checkbox, default: true)
- Send Home Assistant notifications for mount events
- Notifies on first failure, successful recovery, and auth errors
- Disable if you don't want persistent notifications
- Recommended: keep enabled to stay informed

### SSH Debug Mode (Advanced)

**SSH Enabled** (checkbox, default: false)
- **⚠️ FOR DEBUGGING ONLY** - Not for production use
- Enables SSH access to the container for troubleshooting
- Fixed credentials: user `root`, password `sshfs-mount`
- Access via container IP on port 22
- ⚠️ **Security Warning**: Uses weak fixed password
- Only enable temporarily when debugging issues
- Disable immediately after troubleshooting

### Mountpoint Configuration

You can configure multiple mountpoints. Each mountpoint requires:

**Share Name** (text, required)
- Unique name for this share
- Becomes the Samba share name (e.g., `\\homeassistant\share_name`)
- Only alphanumeric, underscore, and hyphen characters
- Examples: `media_server`, `backup-nas`, `photos`

**Remote Host** (text, required)
- IP address or hostname of the remote SSH server
- Examples: `192.168.1.100`, `nas.local`, `myserver.example.com`

**Remote Port** (number, optional)
- SSH port on the remote server
- Default: 22 (standard SSH port)
- Only change if your server uses a non-standard port

**Remote Username** (text, required)
- Username for SSH authentication on the remote server
- This is the SSH user, not the Samba user

**Remote Path** (text, required)
- Absolute path on the remote server to mount
- Must be a full path starting with `/`
- Examples: `/mnt/storage`, `/home/user/media`, `/volume1/shared`

**Authentication Type** (dropdown, required)
- `key` - Use SSH key authentication (more secure, recommended)
- `password` - Use password authentication (simpler)

**SSH Private Key** (text, required if auth_type=key)
- Your SSH private key for authentication
- Include the full key with header (`-----BEGIN OPENSSH PRIVATE KEY-----`) and footer
- Can be RSA, ED25519, or other SSH key types
- Keep this secure - anyone with this key can access your remote server

**SSH Password** (password, required if auth_type=password)
- Password for SSH authentication
- Only provide this OR an SSH key, not both

## Configuration Examples

### Example 1: Single media server with SSH key

```yaml
allow_guest: false
samba_user: "homeassistant"
samba_pass: "secure-password-123"
mountpoints:
  - share_name: "media"
    remote_host: "192.168.1.100"
    remote_port: 22
    remote_user: "mediauser"
    remote_path: "/mnt/media"
    auth_type: "key"
    ssh_key: |
      -----BEGIN OPENSSH PRIVATE KEY-----
      b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
      ... (rest of key) ...
      -----END OPENSSH PRIVATE KEY-----
```

### Example 2: Multiple mounts with password auth and guest access

```yaml
allow_guest: true
samba_user: ""
samba_pass: ""
mountpoints:
  - share_name: "nas_media"
    remote_host: "nas.local"
    remote_user: "admin"
    remote_path: "/volume1/media"
    auth_type: "password"
    ssh_password: "nas-password"

  - share_name: "backup_server"
    remote_host: "192.168.1.200"
    remote_port: 2222
    remote_user: "backup"
    remote_path: "/backups/homeassistant"
    auth_type: "password"
    ssh_password: "backup-password"
```

### Example 3: Mixed authentication methods

```yaml
allow_guest: false
samba_user: "myuser"
samba_pass: "mypassword"
mountpoints:
  - share_name: "secure_nas"
    remote_host: "nas.local"
    remote_user: "admin"
    remote_path: "/secure/data"
    auth_type: "key"
    ssh_key: "-----BEGIN OPENSSH PRIVATE KEY-----\n..."

  - share_name: "cloud_storage"
    remote_host: "cloud.example.com"
    remote_user: "clouduser"
    remote_path: "/home/clouduser/storage"
    auth_type: "password"
    ssh_password: "cloud-password"
```

## Next Steps: Mounting Shares in Home Assistant

After you've configured and started this add-on, the Samba server will be running on **port 445** (internal network only), but **you still need to mount the shares** to use them in Home Assistant.

> **Note:** Port 445 is exposed only on the internal Docker network, avoiding conflicts with other Samba services. The add-on logs will show the hostname/IP to use for mounting.

### Step-by-Step Instructions for Home Assistant OS

1. **Open Home Assistant Settings**
   - Click **Settings** in the sidebar
   - Navigate to **System** → **Storage**

2. **Add Network Storage**
   - Click the **Add Network Storage** button
   - Select **CIFS** as the protocol

3. **Enter Connection Details**

   **First, check the add-on logs to get the IP address.** The logs will show:
   ```
   Container IP Address: 172.30.33.X
   ```

   Then configure:
   - **Name**: Choose a friendly name (e.g., "Media Server")
   - **Server**: Enter the IP address from logs (e.g., `172.30.33.5`)
   - **Share**: Enter the `share_name` from your configuration (e.g., `media`)
   - **Workgroup**: `WORKGROUP` (if prompted)
   - **Username**:
     - If **guest access enabled**: Leave blank or check "No authentication"
     - If **guest access disabled**: Enter your `samba_user` from config
   - **Password**:
     - If **guest access enabled**: Leave blank
     - If **guest access disabled**: Enter your `samba_pass` from config

4. **Click Connect**
   - Home Assistant will mount the share
   - The share will appear in your storage list
   - Files will be accessible at `/media/<name>` in Home Assistant

5. **Repeat for Each Share**
   - If you configured multiple mountpoints, add each one separately
   - Each share needs its own "Add Network Storage" configuration

### Example

If your configuration has:
```yaml
mountpoints:
  - share_name: "media_server"
    ...
  - share_name: "backup-nas"
    ...
```

You would:
1. Add network storage for `media_server` share (server: check logs for hostname/IP)
2. Add network storage for `backup-nas` share (server: same hostname/IP)

### Accessing from Other Devices (External Access)

> **Important:** Port 445 is only exposed on the internal Docker network. **External devices (Windows/Mac/Linux computers) cannot access these shares** unless you configure port mapping.

If you need external access from other devices on your network:

1. **Option A: Use the official Samba add-on instead** - It's designed for sharing Home Assistant directories externally
2. **Option B: Modify this add-on** to add port mapping in config.yaml (but this will conflict with other Samba services)

This add-on is optimized for **mounting remote SSH shares and accessing them within Home Assistant**, not for external network sharing.

## Important Connection Information

When connecting to shares from Home Assistant:
- **Server**: Use the IP address shown in the add-on logs (e.g., `172.30.33.5`)
  - This IP is stable across normal reboots
  - Only changes after major system updates or Docker network resets
  - If the IP changes, check the add-on logs for the new IP
- **Port**: 445 (standard SMB port, internal network only)
- **Workgroup**: WORKGROUP (the default Samba workgroup)

### Why IP Address Instead of Hostname?

The add-on runs in a Docker container on Home Assistant's internal network. While the container has a network alias (`local-sshfs-mount`), Home Assistant's storage mounting system runs at the host level and cannot resolve Docker container hostnames. The IP address is the only reliable way to connect.

## Troubleshooting

### "Failed to mount SSHFS" Error

**Possible causes:**
- Network connectivity issue - verify you can ping the remote host
- Incorrect SSH credentials - double-check username, key, or password
- SSH key format issue - ensure key includes header and footer lines
- Remote path doesn't exist - verify the path exists on remote server
- SSH port blocked - check firewall rules
- Host key verification failed - the add-on disables this, but check SSH server config

**Solutions:**
- Check add-on logs for specific error messages
- Test SSH connection manually: `ssh user@host -p port`
- Verify SSH key has correct permissions on remote server
- Ensure remote user has read/write access to remote path

### "Cannot connect to share" in Home Assistant

**Possible causes:**
- Add-on not running - check add-on status
- Incorrect share name - must match `share_name` from config exactly
- Wrong server IP - IP may have changed after system update
- Credential mismatch - verify username/password match config

**Solutions:**
- Check that add-on is running and shows "started"
- Review add-on logs for mount success messages
- **Check the add-on logs for the current IP address** and update your network storage configuration if it changed
- Double-check `samba_user` and `samba_pass` values

### IP Address Changed After Update

**Symptom:** Shares were working but stopped after a system update or Docker reset

**Solution:**
1. Open the SSHFS Mount add-on logs
2. Look for the line showing: `Container IP Address: X.X.X.X`
3. Go to Settings > System > Storage
4. Find your network storage entry and click it
5. Update the **Server** field with the new IP address
6. Save and test the connection

### Mount Fails After Restart

**Possible causes:**
- Remote server unreachable on startup
- Network not ready when add-on starts

**Solutions:**
- Restart the add-on manually after Home Assistant is fully booted
- Check remote server is online and accessible

### Duplicate Share Name Error

**Error:** "Duplicate share name 'xxx' found"

**Solution:** Each `share_name` must be unique. Change one of the conflicting share names.

### Permission Denied When Accessing Files

**Possible causes:**
- Remote user doesn't have permissions
- Samba authentication failed

**Solutions:**
- Verify remote user has read/write access on remote server
- If guest access disabled, ensure correct Samba credentials
- Check SSHFS mount succeeded in add-on logs

## Security Best Practices

1. **Use SSH Keys Instead of Passwords**
   - SSH keys are more secure than passwords
   - Generate dedicated keys for this add-on
   - Never share private keys

2. **Disable Guest Access When Possible**
   - Require authentication for Samba shares
   - Use strong Samba passwords
   - Only enable guest access on trusted networks

3. **Use Dedicated SSH Users**
   - Create specific SSH users for mounting
   - Grant only necessary permissions
   - Don't use root or admin accounts

4. **Limit Remote Paths**
   - Only mount directories you need
   - Don't mount entire filesystems (`/`)
   - Use specific subdirectories

5. **Keep SSH Keys Secure**
   - Store keys safely
   - Never commit keys to version control
   - Rotate keys periodically

6. **Monitor Access**
   - Review add-on logs regularly
   - Check for failed mount attempts
   - Monitor Samba access logs if needed

## FAQ

**Q: Can I mount the same remote server multiple times?**

A: Yes! You can create multiple mountpoints to the same server with different `remote_path` values. Each needs a unique `share_name`.

**Q: What happens if one mount fails?**

A: The add-on continues with other mounts. Only mounts that fail are skipped. Samba will share the successful mounts.

**Q: Can I use different authentication for each mount?**

A: Yes! Each mountpoint can use `key` or `password` independently.

**Q: Do I need to restart the add-on after changing configuration?**

A: Yes. Home Assistant automatically restarts add-ons when you save configuration changes.

**Q: Can I mount NFS or other protocols?**

A: No, this add-on only supports SSH/SSHFS. Use other add-ons for NFS or different protocols.

**Q: Will files stay mounted if the remote server goes offline?**

A: No, but the add-on will automatically reconnect! When a remote server goes offline or network connectivity is lost, the mount monitoring service detects the failure and automatically attempts to reconnect with exponential backoff. You'll receive Home Assistant notifications when mounts fail and recover. The reconnection happens automatically - no restart needed.

**Q: Can I write files to the mounted shares?**

A: Yes, if the remote user has write permissions. The Samba shares are configured as read/write.

**Q: How does automatic reconnection work?**

A: The add-on runs a monitoring service that checks mount health every 60 seconds (configurable). It also listens for network events for instant detection. When a mount fails, it uses exponential backoff (5s, 10s, 20s, 40s, ..., up to 1 hour) to avoid hammering the remote server. Authentication failures won't retry indefinitely - the add-on is smart enough to distinguish network issues from credential problems.

**Q: How do I enable SSH access for debugging?**

A: Set `ssh_enabled: true` in the configuration. This enables SSH access with fixed credentials (root/sshfs-mount) on port 22 of the container IP. **Important**: This is only for debugging - disable it immediately after troubleshooting. The password is intentionally weak to discourage production use.

**Q: Will reconnection work if my network interface restarts?**

A: Yes! The add-on monitors network events and triggers immediate health checks when network changes are detected. This means reconnection happens within seconds of network recovery, not minutes.

## Support

For issues, questions, or feature requests:

- Check the add-on logs for error messages
- Review this documentation thoroughly
- Search existing issues on GitHub
- Create a new GitHub issue with logs and configuration (redact sensitive info)

## License

This add-on is provided as-is without warranty. Use at your own risk.
