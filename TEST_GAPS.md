# Test Coverage Gaps Analysis

## Issue: Unbound Variable Bug Missed by Tests

### What Happened

- `mount-monitor.sh` had an unbound variable error: `NETWORK_MONITOR_PID`
- The variable was used in a trap before being initialized
- All 36 unit tests passed, but the bug still existed
- Bug was only discovered when running in production

### Why Tests Missed It

#### 1. No Integration Tests

Current test suite only has **unit tests**:

- `test-mount-helper.sh` - Tests individual helper functions
- `test-state-management.sh` - Tests state management functions in isolation

**Missing:**

- No tests that actually execute `mount-monitor.sh`
- No tests that execute `sshfs-initial-mount.sh`
- No tests that run the `main()` function
- No tests for service startup flow

#### 2. Tests Re-implement Rather Than Import

`test-state-management.sh` extracts and re-implements the state functions:

```bash
# Extract state management functions from mount-monitor.sh
initialize_state_dir() {
    # Re-implemented here
}
```

This means:

- Tests don't catch bugs in the actual script
- Tests can pass even if the actual script is broken
- Script-level issues (like traps, global vars) are never tested

#### 3. Scripts Use `set -e` Instead of `set -u`

All scripts have `set -e` (exit on error) but NOT `set -u` (exit on unbound variable):

```bash
#!/usr/bin/with-contenv bashio
set -e  # Exit on error (commands that fail)
# Missing: set -u  # Exit on unbound variables
```

**Impact:**

- Unbound variable access doesn't cause immediate failure
- Bugs can hide until the variable is actually used
- No compile-time or load-time detection

## Recommendations

### 1. Add Integration Tests

Create `tests/test-mount-monitor-integration.sh`:

```bash
#!/usr/bin/env bash

test_start "mount-monitor.sh loads without errors"
# Actually source and initialize the script
# Check that traps are set correctly
# Verify global variables are initialized
```

### 2. Add `set -u` to All Scripts

Update all production scripts:

```bash
#!/usr/bin/with-contenv bashio
set -e  # Exit on error
set -u  # Exit on unbound variables (prevents bugs like this)
```

**Benefits:**

- Catches unbound variable access immediately
- Forces explicit initialization of all variables
- Prevents silent failures

**Risks:**

- May break existing code that assumes unset variables default to empty
- Requires careful review of all variable usage
- bashio library may not be compatible with `set -u`

### 3. Add Static Analysis to CI

Integrate shellcheck into test suite:

```bash
# In run-all-tests.sh or CI
shellcheck -s bash -S warning rootfs/usr/bin/*.sh
```

This would have flagged (if shellcheck could parse bashio shebang):

- Unused variables
- Unquoted expansions
- Potential logic errors

### 4. Add Script Startup Tests

Test that scripts can at least be sourced without errors:

```bash
test_start "mount-monitor.sh can be loaded"
if bash -n rootfs/usr/bin/mount-monitor.sh; then
    assert_success
fi

test_start "mount-monitor.sh initializes without errors"
# Mock out dependencies, then:
if timeout 1 bash rootfs/usr/bin/mount-monitor.sh & then
    assert_success
fi
```

### 5. Test in Docker Container

The scripts use Home Assistant-specific features:

- `#!/usr/bin/with-contenv bashio`
- bashio library functions
- s6-overlay environment

**Recommendation:** Add Docker-based integration tests that:

- Build the actual addon image
- Start it with test configuration
- Verify services start correctly
- Check logs for errors

## Priority

1. **HIGH:** Add `set -u` to scripts (after testing compatibility)
2. **HIGH:** Add integration test that sources mount-monitor.sh
3. **MEDIUM:** Add shellcheck to CI pipeline
4. **MEDIUM:** Add Docker-based integration tests
5. **LOW:** Improve unit test coverage for edge cases

## Similar Issues Found

**Good news:** After reviewing all scripts, no similar unbound variable issues exist.

All global variables are now properly initialized:

- `STATE_DIR="/data/mount_state"` ✓
- `EVENT_PIPE="/tmp/network_events"` ✓
- `NETWORK_MONITOR_PID=""` ✓ (fixed)
- `ALLOW_GUEST=$(bashio::config ...)` ✓
- `SAMBA_USER=$(bashio::config ...)` ✓
- `SAMBA_PASS=$(bashio::config ...)` ✓

## Lessons Learned

1. **Unit tests alone are insufficient** - They test functions in isolation but miss integration issues
2. **Test the real code path** - Re-implementing functions in tests can mask bugs
3. **`set -e` is not enough** - Need `set -u` to catch unbound variables early
4. **Static analysis helps** - Tools like shellcheck can catch many issues automatically
5. **Test startup flows** - Traps, global initialization, and script loading are critical paths
