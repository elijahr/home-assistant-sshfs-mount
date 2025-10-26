#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Mock bashio functions
bashio::log.info() { echo "[INFO] $*" >/dev/null; }
bashio::log.warning() { echo "[WARNING] $*" >/dev/null; }
bashio::log.error() { echo "[ERROR] $*" >/dev/null; }
bashio::log.debug() { echo "[DEBUG] $*" >/dev/null; }
bashio::api.supervisor() { return 0; }
bashio::config() { echo ""; }
bashio::config.exists() { return 1; }
bashio::config.true() { return 0; }

# Source helper functions first (disable set -e temporarily)
set +e
source "${SCRIPT_DIR}/../rootfs/usr/bin/mount-helper.sh"
set -e

# Extract state management functions from mount-monitor.sh
STATE_DIR="/tmp/test_mount_state_$$"

initialize_state_dir() {
    local share_name="$1"
    local share_state_dir="${STATE_DIR}/${share_name}"

    mkdir -p "$share_state_dir"

    if [ ! -f "${share_state_dir}/status" ]; then
        echo "MOUNTED" > "${share_state_dir}/status"
    fi

    if [ ! -f "${share_state_dir}/retry_count" ]; then
        echo "0" > "${share_state_dir}/retry_count"
    fi

    if [ ! -f "${share_state_dir}/last_check" ]; then
        date +%s > "${share_state_dir}/last_check"
    fi

    if [ ! -f "${share_state_dir}/last_success" ]; then
        date +%s > "${share_state_dir}/last_success"
    fi
}

get_state() {
    local share_name="$1"
    local field="$2"
    local state_file="${STATE_DIR}/${share_name}/${field}"

    if [ -f "$state_file" ]; then
        cat "$state_file"
    else
        echo ""
    fi
}

set_state() {
    local share_name="$1"
    local field="$2"
    local value="$3"
    local state_file="${STATE_DIR}/${share_name}/${field}"

    echo "$value" > "$state_file"
}

test_suite_start "State Management"

# Setup
mkdir -p "$STATE_DIR"

# Test: initialize_state_dir creates directory
test_start "initialize_state_dir creates state directory"
initialize_state_dir "test_share" >/dev/null 2>&1
assert_dir_exists "${STATE_DIR}/test_share"

# Test: initialize_state_dir creates status file
test_start "initialize_state_dir creates status file"
assert_file_exists "${STATE_DIR}/test_share/status"

# Test: initialize_state_dir sets default status
test_start "initialize_state_dir sets default status to MOUNTED"
result=$(cat "${STATE_DIR}/test_share/status")
assert_equals "MOUNTED" "$result"

# Test: initialize_state_dir creates retry_count file
test_start "initialize_state_dir creates retry_count file"
assert_file_exists "${STATE_DIR}/test_share/retry_count"

# Test: initialize_state_dir sets default retry_count
test_start "initialize_state_dir sets default retry_count to 0"
result=$(cat "${STATE_DIR}/test_share/retry_count")
assert_equals "0" "$result"

# Test: initialize_state_dir creates timestamps
test_start "initialize_state_dir creates last_check timestamp"
assert_file_exists "${STATE_DIR}/test_share/last_check"

test_start "initialize_state_dir creates last_success timestamp"
assert_file_exists "${STATE_DIR}/test_share/last_success"

# Test: get_state retrieves correct value
test_start "get_state retrieves status"
result=$(get_state "test_share" "status")
assert_equals "MOUNTED" "$result"

test_start "get_state retrieves retry_count"
result=$(get_state "test_share" "retry_count")
assert_equals "0" "$result"

test_start "get_state returns empty for non-existent field"
result=$(get_state "test_share" "nonexistent")
assert_equals "" "$result"

# Test: set_state updates value
test_start "set_state updates status"
set_state "test_share" "status" "FAILED"
result=$(get_state "test_share" "status")
assert_equals "FAILED" "$result"

test_start "set_state updates retry_count"
set_state "test_share" "retry_count" "5"
result=$(get_state "test_share" "retry_count")
assert_equals "5" "$result"

# Test: set_state creates new field
test_start "set_state creates new field"
set_state "test_share" "custom_field" "custom_value"
result=$(get_state "test_share" "custom_field")
assert_equals "custom_value" "$result"

# Test: Multiple shares
test_start "initialize_state_dir handles multiple shares"
initialize_state_dir "share1" >/dev/null 2>&1
initialize_state_dir "share2" >/dev/null 2>&1
assert_dir_exists "${STATE_DIR}/share1"

test_start "Multiple shares have independent state"
set_state "share1" "status" "MOUNTED"
set_state "share2" "status" "FAILED"
result1=$(get_state "share1" "status")
result2=$(get_state "share2" "status")
if [ "$result1" = "MOUNTED" ] && [ "$result2" = "FAILED" ]; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    share1 status: $result1 (expected: MOUNTED)"
    echo "    share2 status: $result2 (expected: FAILED)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: State persistence simulation
test_start "State persists across function calls"
set_state "test_share" "last_attempt" "$(date +%s)"
sleep 1
result=$(get_state "test_share" "last_attempt")
if [ -n "$result" ] && [ "$result" != "0" ]; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC}"
    echo "    last_attempt was not persisted"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Cleanup
rm -rf "$STATE_DIR"

test_suite_end
exit_with_status
