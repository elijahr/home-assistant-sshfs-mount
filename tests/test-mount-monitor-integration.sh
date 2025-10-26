#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Mock bashio functions for testing
bashio::log.info() { echo "[INFO] $*" >/dev/null; }
bashio::log.warning() { echo "[WARNING] $*" >/dev/null; }
bashio::log.error() { echo "[ERROR] $*" >/dev/null; }
bashio::log.debug() { echo "[DEBUG] $*" >/dev/null; }
bashio::api.supervisor() { return 0; }
bashio::config() { echo ""; }
bashio::config.exists() { return 1; }
bashio::config.true() { return 0; }

test_suite_start "mount-monitor.sh Integration Tests"

# Test: Script syntax check
test_start "mount-monitor.sh has valid bash syntax"
if bash -n "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Syntax check failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Script doesn't call undefined variables at load time
test_start "mount-monitor.sh doesn't use undefined variables at load"
# This would catch the NETWORK_MONITOR_PID bug
if bash -c 'set -u; grep -v "^main" '"${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh"' | bash -u' 2>&1 | grep -qi "unbound variable"; then
    echo -e "${RED}✗${NC}"
    echo "    Script uses unbound variables"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test: Global variables are initialized
test_start "Global variables are declared in script"
if grep -q 'STATE_DIR="/data/mount_state"' "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" \
    && grep -q 'EVENT_PIPE="/tmp/network_events"' "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" \
    && grep -q 'NETWORK_MONITOR_PID=""' "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Global variables not properly initialized"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Required functions exist
test_start "Required functions are defined in script"
if grep -q "initialize_state_dir()" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" \
    && grep -q "get_state()" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" \
    && grep -q "set_state()" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" \
    && grep -q "send_notification()" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" \
    && grep -q "start_network_event_monitor()" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" \
    && grep -q "check_and_reconnect_mount()" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    One or more required functions are missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Trap is properly set
test_start "EXIT trap is properly configured in script"
if grep -q "^trap.*EVENT_PIPE.*EXIT" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" \
    && grep -q 'NETWORK_MONITOR_PID.*EVENT_PIPE' "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    EXIT trap not properly configured"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: initialize_state_dir function creates expected structure
test_start "initialize_state_dir creates proper state structure"
# This test is already covered in test-state-management.sh
# Just verify the function definition exists and creates required files
if grep -q "initialize_state_dir()" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" \
    && grep -A 20 "initialize_state_dir()" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" | grep -q "status" \
    && grep -A 20 "initialize_state_dir()" "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" | grep -q "retry_count"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    initialize_state_dir not properly defined"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: set -u is enabled in script
test_start "Script has set -eu enabled"
if head -5 "${SCRIPT_DIR}/../rootfs/usr/bin/mount-monitor.sh" | grep -q "set -eu"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    set -eu not found in script header"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

test_suite_end
exit_with_status
