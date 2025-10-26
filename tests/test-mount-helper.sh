#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Mock bashio functions for testing
bashio::log.info() { echo "[INFO] $*" >/dev/null; }
bashio::log.warning() { echo "[WARNING] $*" >/dev/null; }
bashio::log.error() { echo "[ERROR] $*" >/dev/null; }
bashio::api.supervisor() { return 0; }
bashio::config() { echo ""; }
bashio::config.exists() { return 1; }

# Source the helper functions (disable set -e temporarily)
set +e
source "${SCRIPT_DIR}/../rootfs/usr/bin/mount-helper.sh"
set -e

test_suite_start "mount-helper.sh"

# Test: validate_share_name - valid names
test_start "validate_share_name accepts valid alphanumeric"
validate_share_name "media_server" >/dev/null 2>&1
assert_success

test_start "validate_share_name accepts hyphens"
validate_share_name "my-share-123" >/dev/null 2>&1
assert_success

test_start "validate_share_name accepts underscores"
validate_share_name "my_share_123" >/dev/null 2>&1
assert_success

# Test: validate_share_name - invalid names
test_start "validate_share_name rejects empty string"
if validate_share_name "" >/dev/null 2>&1; then
    echo -e "${RED}✗${NC}"
    echo "    Expected failure for empty string"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

test_start "validate_share_name rejects spaces"
if validate_share_name "my share" >/dev/null 2>&1; then
    echo -e "${RED}✗${NC}"
    echo "    Expected failure for spaces"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

test_start "validate_share_name rejects special chars"
if validate_share_name "my@share" >/dev/null 2>&1; then
    echo -e "${RED}✗${NC}"
    echo "    Expected failure for special chars"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

test_start "validate_share_name rejects dots"
if validate_share_name "my.share" >/dev/null 2>&1; then
    echo -e "${RED}✗${NC}"
    echo "    Expected failure for dots"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

test_start "validate_share_name rejects too long (>80 chars)"
if validate_share_name "$(printf 'a%.0s' {1..81})" >/dev/null 2>&1; then
    echo -e "${RED}✗${NC}"
    echo "    Expected failure for too long name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test: generate_auto_share_name
test_start "generate_auto_share_name generates correct format"
result=$(generate_auto_share_name 0)
assert_equals "mount_0" "$result"

test_start "generate_auto_share_name handles index 5"
result=$(generate_auto_share_name 5)
assert_equals "mount_5" "$result"

# Test: calculate_backoff_delay
test_start "calculate_backoff_delay - retry 0, base 5"
result=$(calculate_backoff_delay 0 5 3600)
assert_equals "5" "$result"

test_start "calculate_backoff_delay - retry 1, base 5"
result=$(calculate_backoff_delay 1 5 3600)
assert_equals "10" "$result"

test_start "calculate_backoff_delay - retry 2, base 5"
result=$(calculate_backoff_delay 2 5 3600)
assert_equals "20" "$result"

test_start "calculate_backoff_delay - retry 3, base 5"
result=$(calculate_backoff_delay 3 5 3600)
assert_equals "40" "$result"

test_start "calculate_backoff_delay - retry 10, base 5, capped at max"
result=$(calculate_backoff_delay 10 5 100)
assert_equals "100" "$result"

test_start "calculate_backoff_delay - exponential growth works"
retry0=$(calculate_backoff_delay 0 5 3600)
retry1=$(calculate_backoff_delay 1 5 3600)
assert_gt "$retry1" "$retry0"

test_start "calculate_backoff_delay - respects max delay"
result=$(calculate_backoff_delay 20 5 3600)
assert_equals "3600" "$result"

# Test: unmount_share with non-existent directory
test_start "unmount_share handles non-existent directory"
unmount_share "/tmp/nonexistent_test_mount_$$" >/dev/null 2>&1
assert_success

# Test: check_mount_health with non-existent directory
test_start "check_mount_health fails for non-existent directory"
if check_mount_health "/tmp/nonexistent_test_mount_$$" 1 >/dev/null 2>&1; then
    echo -e "${RED}✗${NC}"
    echo "    Expected failure for non-existent directory"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test: cleanup_ssh_keys - Skip this test as it requires root/.ssh directory modification
# which is complex to test in isolation. The function is tested via integration tests.
test_start "cleanup_ssh_keys function exists"
if type cleanup_ssh_keys >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    cleanup_ssh_keys function not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

test_suite_end
exit_with_status
