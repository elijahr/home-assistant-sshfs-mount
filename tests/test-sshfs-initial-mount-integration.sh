#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Mock bashio functions for testing
bashio::log.info() { echo "[INFO] $*" >/dev/null; }
bashio::log.warning() { echo "[WARNING] $*" >/dev/null; }
bashio::log.error() { echo "[ERROR] $*" >/dev/null; }
bashio::log.debug() { echo "[DEBUG] $*" >/dev/null; }
bashio::api.supervisor() { return 0; }
bashio::config() {
    case "$1" in
        'allow_guest') echo "false" ;;
        'samba_user') echo "testuser" ;;
        'samba_pass') echo "testpass" ;;
        *) echo "" ;;
    esac
}
bashio::config.exists() { return 1; }
bashio::config.has_value() { return 0; }
bashio::config.is_empty() { return 1; }

test_suite_start "sshfs-initial-mount.sh Integration Tests"

# Test: Script syntax check
test_start "sshfs-initial-mount.sh has valid bash syntax"
if bash -n "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh" 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Syntax check failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Required commands exist in script
test_start "Script contains required function calls"
if grep -q "cleanup_mounts" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh" \
    && grep -q "load_mount_config" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh" \
    && grep -q "mount_share" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Missing required function calls"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Global variables are initialized
test_start "Configuration variables are properly set"
if grep -q "ALLOW_GUEST=\$(bashio::config" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh" \
    && grep -q "SAMBA_USER=\$(bashio::config" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh" \
    && grep -q "SAMBA_PASS=\$(bashio::config" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Configuration variables not properly initialized"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Samba configuration template is referenced
test_start "Samba configuration template is used"
if grep -q "/etc/smb.conf.template" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh" \
    && grep -q "/etc/samba/smb.conf" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Samba configuration template not referenced"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Security checks for Samba user
test_start "Samba user validation is present"
if grep -q "if \[ -z \"\$SAMBA_USER\"" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh" \
    && grep -q "if \[ -z \"\$SAMBA_PASS\"" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Samba user/password validation missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Username validation regex exists
test_start "Username format validation is present"
if grep -q '\[\[ ! "\$SAMBA_USER" =~ ' "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Username format validation missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: set -u is enabled in script
test_start "Script has set -eu enabled"
if head -5 "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh" | grep -q "set -eu"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    set -eu not found in script header"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Sources mount-helper.sh
test_start "Script sources mount-helper.sh"
if grep -q "source /usr/bin/mount-helper.sh" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    mount-helper.sh not sourced"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Container IP detection
test_start "Container IP detection is present"
if grep -q "CONTAINER_IP=\$(hostname -i" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Container IP detection missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: Guest access warning
test_start "Guest access security warning is present"
if grep -q "SECURITY WARNING" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh" \
    && grep -q "Guest access is ENABLED" "${SCRIPT_DIR}/../rootfs/usr/bin/sshfs-initial-mount.sh"; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    Guest access security warning missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

test_suite_end
exit_with_status
