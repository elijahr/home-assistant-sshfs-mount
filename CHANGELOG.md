# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.15] - 2025-01-25

### Fixed
- Added `force user = root` to authenticated Samba shares to fix permission errors when creating files/directories

## [1.0.14] - 2025-01-25

### Changed
- Simplified logging output to show only container IP address
- Updated all documentation to reflect IP address approach for mounting
- Added explanation of why IP address is required instead of hostname
- Added troubleshooting section for IP address changes

### Fixed
- Clarified that Home Assistant host cannot resolve Docker container hostnames

## [1.0.13] - 2025-01-25

### Changed
- Updated instructions to use `local-sshfs-mount` hostname (with hyphens)

## [1.0.12] - 2025-01-25

### Changed
- Updated instructions to recommend `addon_local_sshfs_mount` container name

## [1.0.11] - 2025-01-25

### Fixed
- Added system user creation before Samba user creation to fix authentication errors

## [1.0.10] - 2025-01-25

### Changed
- Switched from port mapping to Docker EXPOSE for internal network access
- Removed host port binding to avoid conflicts with other Samba services

## [1.0.9] - 2025-01-25

### Added
- Initial release with multiple mountpoint support
- SSH key and password authentication
- Guest and authenticated Samba access options
- Automatic mount cleanup and validation
- Error notifications to Home Assistant UI
- Comprehensive documentation

## [Unreleased]

### Planned
- Additional authentication options
- Mount status monitoring
- Reconnection handling for dropped connections
