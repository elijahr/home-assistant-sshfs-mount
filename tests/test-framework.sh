#!/usr/bin/env bash

set -e

# Simple bash test framework
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_start() {
    CURRENT_TEST="$1"
    echo -n "  ${CURRENT_TEST}... "
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "    Expected: '$expected'"
        echo "    Actual:   '$actual'"
        echo "    Message:  $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_success() {
    local message="${1:-Command should succeed}"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "    Message: $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_failure() {
    local message="${1:-Command should fail}"

    if [ $? -ne 0 ]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "    Message: $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "    Expected to contain: '$needle'"
        echo "    Actual:              '$haystack'"
        echo "    Message:             $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local filepath="$1"
    local message="${2:-File should exist}"

    if [ -f "$filepath" ]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "    Expected file: '$filepath'"
        echo "    Message:       $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_dir_exists() {
    local dirpath="$1"
    local message="${2:-Directory should exist}"

    if [ -d "$dirpath" ]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "    Expected directory: '$dirpath'"
        echo "    Message:            $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_gt() {
    local value1="$1"
    local value2="$2"
    local message="${3:-Value1 should be greater than Value2}"

    if [ "$value1" -gt "$value2" ]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "    Expected: $value1 > $value2"
        echo "    Message:  $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_lt() {
    local value1="$1"
    local value2="$2"
    local message="${3:-Value1 should be less than Value2}"

    if [ "$value1" -lt "$value2" ]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "    Expected: $value1 < $value2"
        echo "    Message:  $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

test_suite_start() {
    echo ""
    echo -e "${YELLOW}Running: $1${NC}"
    echo "----------------------------------------"
}

test_suite_end() {
    echo ""
    echo "----------------------------------------"
    echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
    echo ""
}

exit_with_status() {
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}
