# SSHFS Mount Add-on

Mount remote SSH servers in Home Assistant.

[![License](https://img.shields.io/github/license/elijahr/home-assistant-sshfs-mount)](https://github.com/elijahr/home-assistant-sshfs-mount/blob/devel/LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/elijahr/home-assistant-sshfs-mount)](https://github.com/elijahr/home-assistant-sshfs-mount/releases)

## Installation

1. In Home Assistant, navigate to **Settings** → **Add-ons** → **Add-on Store**
2. Click the 3-dot menu (⋮) in the top right
3. Select **Repositories**
4. Add this repository URL: `https://github.com/elijahr/home-assistant-sshfs-mount`
5. Click **Close**
6. Find "SSHFS Mount" in the add-on store and click it
7. Click **Install**
8. Configure the add-on (see Configuration section below)
9. Start the add-on
10. Check the add-on logs for the IP address to use when mounting shares

## What This Add-on Does

This add-on connects to remote servers via SSH (using SSHFS) and makes them available as Samba/CIFS network shares within Home Assistant. You can then mount these shares in Home Assistant OS to access remote files as if they were local.

## Key Features

- **Multiple mountpoints** - Connect to as many remote servers as you need
- **Flexible authentication** - Use SSH keys or passwords for remote servers
- **Guest or authenticated access** - Choose whether Samba shares require authentication
- **Automatic cleanup** - Properly unmounts and remounts on configuration changes

## Configuration

### Quick Example

```yaml
allow_guest: false
samba_user: "myuser"
samba_pass: "mypassword"
mountpoints:
  - share_name: "media_server"
    remote_host: "192.168.1.100"
    remote_user: "media"
    remote_path: "/mnt/media"
    auth_type: "key"
    ssh_key: "-----BEGIN OPENSSH PRIVATE KEY-----\n..."
```

For detailed configuration options and examples, see the [Documentation](DOCS.md) tab in the add-on.

## Mounting Shares in Home Assistant

After configuring and starting this add-on, you need to **mount the shares in Home Assistant**:

1. **Check the add-on logs** to get the IP address (shown as `Container IP Address: X.X.X.X`)
2. Go to **Settings** → **System** → **Storage**
3. Click **Add network storage**
4. Select **CIFS** protocol
5. Use the IP address from step 1 as the **Server**
6. Enter the share name and credentials

**Note:** The IP address is stable across normal reboots. If it changes after a major update, just check the logs again.

See the **Documentation** tab for complete step-by-step instructions!

## Support

- [Open an issue](https://github.com/elijahr/home-assistant-sshfs-mount/issues) for bugs or feature requests
- Check the [CHANGELOG](CHANGELOG.md) for recent changes
- Read the [full documentation](DOCS.md) for detailed instructions

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

1. Clone the repository
2. Install pre-commit hooks: `pre-commit install`
3. Make your changes
4. Test locally in Home Assistant
5. Submit a PR

## Licenses

- MIT License - see [LICENSE](LICENSE) file for details.
- Apache 2.0 - Logo & Icon by [Pictogrammers Team](https://www.iconarchive.com/show/material-folder-icons-by-pictogrammers/folder-key-network-icon.html) - see [ICON-LICENSE.txt](./LICENSES/ICON-LICENSE.txt) for details.
