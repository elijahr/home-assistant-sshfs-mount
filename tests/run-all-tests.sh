#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   SSHFS Mount Add-on Test Suite          ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
SUITE_COUNT=0
FAILED_SUITES=()

run_test_suite() {
    local test_file="$1"
    local test_name=$(basename "$test_file")

    SUITE_COUNT=$((SUITE_COUNT + 1))

    if bash "$test_file"; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        FAILED_SUITES+=("$test_name")
    fi
}

# Run all test suites
run_test_suite "${SCRIPT_DIR}/test-mount-helper.sh"
run_test_suite "${SCRIPT_DIR}/test-state-management.sh"

# Summary
echo ""
echo -e "${BLUE}════════════════════════════════════════════${NC}"
echo -e "${BLUE}               SUMMARY                      ${NC}"
echo -e "${BLUE}════════════════════════════════════════════${NC}"
echo ""
echo "Test Suites: $SUITE_COUNT"
echo -e "Passed:      ${GREEN}${TOTAL_PASSED}${NC}"
echo -e "Failed:      ${RED}${TOTAL_FAILED}${NC}"
echo ""

if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
    echo -e "${RED}Failed Suites:${NC}"
    for suite in "${FAILED_SUITES[@]}"; do
        echo -e "  ${RED}✗${NC} $suite"
    done
    echo ""
fi

if [ $TOTAL_FAILED -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ALL TESTS PASSED! 🎉                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║     SOME TESTS FAILED                     ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
fi
