# SSHFS Reconnection Implementation Plan
## Based on Home Assistant Best Practices

## Research Summary

Based on official Home Assistant documentation and community best practices:

### Key Findings:

1. **s6-overlay v3** is the standard process supervisor for Home Assistant add-ons
2. **Watchdog feature** provides built-in health monitoring and automatic restarts
3. **s6-rc services** are the recommended way to define supervised processes
4. **Event-driven approaches** are preferred over polling when possible
5. **init: false** must be set in config.yaml (already present)

## Architecture Overview

### Multi-Service Container Structure

```
Container (s6-overlay as PID 1)
├── Service 1: sshfs-mount (oneshot)
│   └── Mounts all SSHFS shares during initialization
├── Service 2: smbd (longrun)
│   └── Runs Samba daemon continuously
├── Service 3: mount-monitor (longrun)
│   └── Monitors mount health and handles reconnections
└── Service 4: sshd (longrun, optional)
    └── SSH daemon for container debugging/administration
```

## Implementation Strategy

### 1. Use s6-overlay Service Definitions

Instead of a single `run.sh` script, we'll use s6-rc service definitions:

**Directory Structure:**
```
rootfs/
├── etc/
│   ├── s6-overlay/
│   │   └── s6-rc.d/
│   │       ├── sshfs-mount/          # Initial mount service (oneshot)
│   │       │   ├── type
│   │       │   ├── up
│   │       │   └── dependencies.d/
│   │       │       └── base
│   │       ├── smbd/                 # Samba daemon service (longrun)
│   │       │   ├── type
│   │       │   ├── run
│   │       │   └── dependencies.d/
│   │       │       └── sshfs-mount
│   │       ├── mount-monitor/        # Monitoring service (longrun)
│   │       │   ├── type
│   │       │   ├── run
│   │       │   └── dependencies.d/
│   │       │       └── sshfs-mount
│   │       ├── sshd/                 # SSH daemon service (longrun, optional)
│   │       │   ├── type
│   │       │   ├── run
│   │       │   └── dependencies.d/
│   │       │       └── base
│   │       └── user/
│   │           └── contents.d/
│   │               ├── sshfs-mount
│   │               ├── smbd
│   │               ├── mount-monitor
│   │               └── sshd (conditionally added)
│   ├── ssh/
│   │   └── sshd_config               # SSH daemon configuration
│   └── smb.conf.template             # Moved from root
├── usr/
│   └── bin/
│       ├── mount-helper.sh           # Extracted mount functions
│       ├── sshfs-initial-mount.sh    # Initial mounting script
│       ├── smbd-start.sh             # Samba daemon wrapper
│       └── mount-monitor.sh          # Monitoring daemon
```

### 2. Home Assistant Watchdog Integration

Add watchdog configuration to monitor the Samba service:

**config.yaml addition:**
```yaml
watchdog: "tcp://[HOST]:445"
```

This enables:
- Automatic restart if Samba becomes unresponsive
- Health monitoring by Home Assistant Supervisor
- Integration with HA notification system

### 3. Mount Monitoring Approach

#### Primary Strategy: Periodic Health Checks with Smart Triggers

The monitor service will:

1. **Health Check Loop**
   - Check every 60 seconds (configurable)
   - Use `timeout 5 stat <mount_dir>` to detect hung mounts
   - Fast-fail on timeouts to trigger reconnection

2. **Network Event Listening** (Optional Enhancement)
   - Monitor `/proc/net/route` using `inotifywait`
   - Trigger immediate health check on network changes
   - Fallback to periodic checks if inotify unavailable

3. **Reconnection Logic**
   - Exponential backoff: 5s, 10s, 20s, 40s, 80s... (max 1 hour)
   - Per-mount retry state tracking
   - Reset retry count on successful mount
   - Never give up (retry forever with capped backoff)

#### Why Not Pure Event-Driven?

- Network events don't catch all failure modes (remote server crashes, hung processes)
- Periodic health checks are more reliable for detecting stale mounts
- Combination approach gives best of both worlds

### 4. State Management

Store per-mount state in `/data/mount_state/<share_name>/`:

```
/data/mount_state/
└── <share_name>/
    ├── status           # MOUNTED | FAILED | RECONNECTING
    ├── retry_count      # Current retry attempt
    ├── last_check       # Timestamp of last check
    ├── last_success     # Timestamp of last successful mount
    └── last_failure     # Timestamp and reason for last failure
```

State persists across container restarts.

### 5. Error Handling & Notifications

**Failure Types:**

1. **Transient Network Issues**
   - Retry with exponential backoff
   - Log as WARNING
   - Notify HA on first failure only

2. **Authentication Failures**
   - Parse sshfs error output
   - Don't retry on auth errors
   - Log as ERROR
   - Notify HA immediately

3. **Remote Server Down**
   - Retry with exponential backoff
   - Log as WARNING
   - Notify HA on first failure only

4. **Hung/Stale Mounts**
   - Detected via stat timeout
   - Force unmount with `fusermount -uz`
   - Retry mount immediately
   - Log as WARNING

**Home Assistant Notifications:**

Send notifications via `bashio::api.supervisor` for:
- First mount failure (per mount)
- Successful reconnection after failure
- Authentication errors (immediate, no retry)

### 6. Configuration Options

Add to `config.yaml`:

```yaml
options:
  # ... existing options ...

  # Reconnection settings
  reconnect_enabled: true
  reconnect_check_interval: 60        # seconds between health checks
  reconnect_use_events: true          # Use network event monitoring
  reconnect_base_delay: 5             # Base delay for exponential backoff
  reconnect_max_delay: 3600           # Max delay cap (1 hour)
  reconnect_notify_ha: true           # Send HA notifications

  # SSH access settings (for container debugging ONLY)
  ssh_enabled: false                  # Enable SSH daemon (user: root, password: sshfs-mount)

schema:
  # ... existing schema ...

  reconnect_enabled: bool?
  reconnect_check_interval: int(10,600)?
  reconnect_use_events: bool?
  reconnect_base_delay: int(1,60)?
  reconnect_max_delay: int(60,7200)?
  reconnect_notify_ha: bool?

  ssh_enabled: bool?
```

## Detailed Service Definitions

### Service 1: sshfs-mount (oneshot)

**Purpose:** Initial mounting of all SSHFS shares

**File: `/etc/s6-overlay/s6-rc.d/sshfs-mount/type`**
```
oneshot
```

**File: `/etc/s6-overlay/s6-rc.d/sshfs-mount/up`**
```
/usr/bin/sshfs-initial-mount.sh
```

**Dependencies:** base

**Script:** Extracted from run.sh lines 102-358, refactored to use mount-helper.sh

### Service 2: smbd (longrun)

**Purpose:** Run Samba daemon

**File: `/etc/s6-overlay/s6-rc.d/smbd/type`**
```
longrun
```

**File: `/etc/s6-overlay/s6-rc.d/smbd/run`**
```bash
#!/command/with-contenv bashio
exec /usr/sbin/smbd -F --no-process-group
```

**Dependencies:** sshfs-mount

**Notes:**
- Uses `-F` for foreground mode (required for s6 supervision)
- s6 will automatically restart if smbd crashes
- Watchdog monitors TCP port 445 for health

### Service 3: mount-monitor (longrun)

**Purpose:** Monitor mount health and handle reconnections

**File: `/etc/s6-overlay/s6-rc.d/mount-monitor/type`**
```
longrun
```

**File: `/etc/s6-overlay/s6-rc.d/mount-monitor/run`**
```bash
#!/command/with-contenv bashio
exec /usr/bin/mount-monitor.sh
```

**Dependencies:** sshfs-mount

**Script Logic:**
1. Initialize state directory structure
2. Start network event listener (if enabled)
3. Enter main loop:
   - Check each mount's health
   - Handle failures with exponential backoff
   - Update state files
   - Sleep until next check interval or event trigger

### Service 4: sshd (longrun, optional)

**Purpose:** SSH daemon for container debugging ONLY

**File: `/etc/s6-overlay/s6-rc.d/sshd/type`**
```
longrun
```

**File: `/etc/s6-overlay/s6-rc.d/sshd/run`**
```bash
#!/command/with-contenv bashio

if ! bashio::config.true 'ssh_enabled'; then
    bashio::log.info "SSH debugging mode is disabled"
    exec sleep infinity
fi

bashio::log.warning "=========================================="
bashio::log.warning "  SSH DEBUG MODE ENABLED"
bashio::log.warning "  User: root"
bashio::log.warning "  Password: sshfs-mount"
bashio::log.warning "  This is for debugging purposes ONLY!"
bashio::log.warning "=========================================="

# Generate host keys if they don't exist
if [ ! -f /data/ssh/ssh_host_rsa_key ]; then
    bashio::log.info "Generating SSH host keys..."
    mkdir -p /data/ssh
    ssh-keygen -t rsa -f /data/ssh/ssh_host_rsa_key -N ''
    ssh-keygen -t ed25519 -f /data/ssh/ssh_host_ed25519_key -N ''
fi

# Set fixed root password for debugging
echo "root:sshfs-mount" | chpasswd

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
```

**Dependencies:** base

**Notes:**
- **DEBUGGING ONLY** - Not for production use
- Only starts if `ssh_enabled: true` in configuration
- Fixed credentials: `root` / `sshfs-mount`
- Host keys stored in `/data/ssh/` for persistence across restarts
- Runs on default SSH port (22) - accessible via Docker container IP
- Defaults to disabled for security
- Logs prominent warning when enabled

**SSH Configuration File: `/etc/ssh/sshd_config`**
```
Port 22
Protocol 2
HostKey /data/ssh/ssh_host_rsa_key
HostKey /data/ssh/ssh_host_ed25519_key
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile /root/.ssh/authorized_keys
ChallengeResponseAuthentication no
UsePAM yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/ssh/sftp-server
```

## Implementation Phases

### Phase 1: Foundation & Refactoring
**Goal:** Extract mount logic and prepare for multi-service architecture

1. Create `mount-helper.sh` with functions:
   - `load_mount_config()` - Parse mount configuration
   - `mount_share()` - Mount a single share
   - `unmount_share()` - Unmount a single share
   - `check_mount_health()` - Health check with timeout
   - `calculate_backoff_delay()` - Exponential backoff calculator

2. Create `sshfs-initial-mount.sh`:
   - Use mount-helper.sh functions
   - Perform initial cleanup (existing unmount logic)
   - Mount all configured shares
   - Generate Samba configuration
   - Exit with success/failure code

3. Test that refactored code works identically to current implementation

### Phase 2: s6-overlay Service Structure
**Goal:** Migrate to multi-service architecture

1. Create rootfs directory structure
2. Define sshfs-mount oneshot service
3. Define smbd longrun service
4. Update Dockerfile to copy rootfs and use /init
5. Test multi-service startup

### Phase 3: Basic Health Monitoring
**Goal:** Implement simple polling-based health checks

1. Create `mount-monitor.sh` with:
   - Configuration loading
   - State directory initialization
   - Basic health check loop (polling only)
   - Simple retry logic (no backoff yet)

2. Define mount-monitor service
3. Test detection of mount failures
4. Verify basic reconnection works

### Phase 4: Exponential Backoff & State Management
**Goal:** Add production-ready retry logic

1. Implement retry state management:
   - State file read/write
   - Retry counter tracking
   - Timestamp management

2. Add exponential backoff algorithm
3. Implement retry count and delay limits
4. Add reset logic on successful reconnection
5. Test backoff behavior with simulated failures

### Phase 5: Network Event Monitoring
**Goal:** Add event-driven health checks

1. Add `inotify-tools` to Dockerfile
2. Implement network event listener in mount-monitor.sh:
   - Monitor `/proc/net/route` with inotifywait
   - Trigger health check on events
   - Graceful fallback if inotify unavailable

3. Test event-driven reconnection

### Phase 6: Error Classification & Notifications
**Goal:** Intelligent error handling

1. Add error output parsing to mount_share():
   - Detect authentication failures
   - Detect network issues
   - Detect permission issues

2. Implement error-specific handling:
   - Don't retry auth failures
   - Fast retry for transient network issues
   - Slow backoff for server down scenarios

3. Add Home Assistant notification integration:
   - Use bashio::api.supervisor
   - Send on first failure
   - Send on successful recovery
   - Send on permanent errors

### Phase 7: Watchdog Integration
**Goal:** Leverage HA's built-in health monitoring

1. Add watchdog configuration to config.yaml
2. Test automatic restart on Samba failure
3. Verify integration with HA notifications

### Phase 8: SSH Daemon Integration
**Goal:** Add optional SSH access for debugging

1. Add `openssh-server` to Dockerfile
2. Create sshd service definition with fixed credentials
3. Create sshd_config configuration file
4. Add SSH configuration option (`ssh_enabled`) to config.yaml
5. Test SSH access with fixed credentials (root / sshfs-mount)
6. Verify prominent warning is logged when SSH enabled

### Phase 9: Configuration & Polish
**Goal:** Make all behavior configurable

1. Add reconnection options to config.yaml
2. Update mount-monitor.sh to use config values
3. Add configuration validation for all new options
4. Set sensible defaults
5. Ensure SSH service only starts when enabled

### Phase 10: Documentation & Testing
**Goal:** Comprehensive testing and user documentation

1. Test scenarios:
   - Remote server shutdown/restart
   - Network interface down/up
   - Authentication failure
   - Multiple mounts (one fails, others continue)
   - Container restart with failed mounts
   - SSH access with fixed credentials (root / sshfs-mount)
   - SSH disabled (default state)
   - SSH warning messages in logs

2. Update DOCS.md:
   - Document new configuration options (reconnection + SSH)
   - Explain reconnection behavior
   - Document SSH debug mode (with security warnings)
   - Add troubleshooting section

3. Update CHANGELOG.md with new features

4. Bump version to 1.0.16

## Success Criteria

- [ ] Mounts automatically reconnect after network interruption
- [ ] Mounts automatically reconnect after remote server restart
- [ ] Exponential backoff prevents server hammering
- [ ] Network events trigger immediate health checks (no wait)
- [ ] Samba daemon continues running during reconnection
- [ ] Authentication failures don't cause infinite retries
- [ ] Hung/stale mounts are detected and remounted
- [ ] Home Assistant receives notifications for failures
- [ ] All reconnection behavior is configurable
- [ ] Works across container restarts (state persists)
- [ ] No performance impact during normal operation
- [ ] Watchdog monitors Samba health
- [ ] Logs provide clear visibility into reconnection activity
- [ ] SSH debug mode works with fixed credentials (root / sshfs-mount)
- [ ] SSH is disabled by default for security
- [ ] SSH logs prominent warning when enabled
- [ ] SSH host keys persist across container restarts

## Technical Notes

### Why s6-overlay Instead of Simple Supervisor Script?

1. **Home Assistant Standard:** All HA add-ons use s6-overlay
2. **Built-in Features:** Process supervision, logging, signal handling
3. **Proven Reliability:** Battle-tested in thousands of containers
4. **Future Compatibility:** Aligns with HA ecosystem evolution
5. **AppArmor Integration:** Works with HA's security model

### Why Watchdog for Samba?

1. **External Monitoring:** More reliable than in-container checks
2. **Supervisor Integration:** Ties into HA's service management
3. **Automatic Restart:** No custom logic needed
4. **User Visibility:** Shows up in HA UI

### Why Not Pure Event-Driven?

1. **Coverage Gaps:** Events miss server crashes, hung processes
2. **Reliability:** Periodic checks guarantee detection
3. **Simplicity:** Easier to understand and debug
4. **Hybrid Benefits:** Events provide fast response, polling guarantees coverage

## Open Questions & Decisions

### Q: Should we give up after max retries or retry forever?
**Decision:** Retry forever with capped backoff (1 hour max)
**Rationale:** Network issues can last hours/days; giving up requires manual intervention

### Q: How to handle authentication failures?
**Decision:** Don't retry, notify user immediately
**Rationale:** Auth failures won't self-resolve; user must fix credentials

### Q: Should monitoring be optional?
**Decision:** Yes, add `reconnect_enabled` config option
**Rationale:** Users may want manual control; debugging scenarios

### Q: State persistence across updates?
**Decision:** Use `/data` directory (persists across updates)
**Rationale:** HA add-ons preserve `/data` across container recreations

### Q: Logging verbosity?
**Decision:**
- INFO: Successful mounts, recoveries
- WARNING: Retries, temporary failures
- ERROR: Authentication failures, config errors
**Rationale:** Balance between visibility and noise

### Q: Should SSH be enabled by default?
**Decision:** No, SSH disabled by default (`ssh_enabled: false`)
**Rationale:**
- Security best practice: minimize attack surface
- SSH is for debugging ONLY, not normal operation
- Fixed weak credentials intentionally discourage permanent use

### Q: What credentials for SSH debugging access?
**Decision:** Fixed credentials - user: `root`, password: `sshfs-mount`
**Rationale:**
- Simple, no configuration needed
- Fixed password makes it clear this is for debugging only
- Weak password intentionally discourages production use
- Logs prominent warning when enabled
- Still requires explicit opt-in via `ssh_enabled: true`

### Q: Where to store SSH host keys?
**Decision:** `/data/ssh/` directory
**Rationale:**
- Persists across container restarts
- Prevents "host key changed" warnings during debugging sessions
- Consistent with other persistent data

## Migration Path for Existing Users

The implementation is **backward compatible**:

1. Default configuration maintains current behavior
2. Reconnection enabled by default (can be disabled)
3. No configuration changes required
4. State files created on first run
5. Existing mounts continue working

Users can opt-in to new features or disable reconnection if desired.

## Estimated Complexity

- **Phase 1-2:** Low - Mostly refactoring
- **Phase 3-4:** Medium - Core monitoring logic
- **Phase 5:** Low - Event monitoring enhancement
- **Phase 6:** Medium - Error classification
- **Phase 7:** Low - Watchdog configuration
- **Phase 8:** Low - SSH daemon integration
- **Phase 9-10:** Low - Configuration and polish

**Total Estimated Effort:** ~2-3 days for full implementation and testing
