# SSHFS Mount Add-on Test Suite

## Overview

This directory contains comprehensive bash tests for the SSHFS Mount add-on. The tests verify the functionality of helper functions, state management, and reconnection logic.

## Test Structure

```
tests/
├── test-framework.sh         # Simple assertion library
├── test-mount-helper.sh      # Tests for mount-helper.sh functions
├── test-state-management.sh  # Tests for state persistence
├── run-all-tests.sh          # Test runner (executes all suites)
└── README.md                 # This file
```

## Running Tests

### Run All Tests

```bash
cd tests
chmod +x *.sh
./run-all-tests.sh
```

### Run Individual Test Suite

```bash
cd tests
./test-mount-helper.sh
./test-state-management.sh
```

## Test Coverage

### mount-helper.sh Tests

- **validate_share_name()**
  - ✓ Accepts valid alphanumeric names
  - ✓ Accepts hyphens and underscores
  - ✓ Rejects empty strings
  - ✓ Rejects spaces and special characters
  - ✓ Rejects names over 80 characters

- **generate_auto_share_name()**
  - ✓ Generates correct format `mount_N`
  - ✓ Handles different indices

- **calculate_backoff_delay()**
  - ✓ Calculates exponential backoff correctly
  - ✓ Respects maximum delay cap
  - ✓ Handles edge cases (retry 0, high retry counts)

- **unmount_share()**
  - ✓ Handles non-existent directories gracefully

- **check_mount_health()**
  - ✓ Fails for non-existent directories
  - ✓ Uses timeout correctly

- **cleanup_ssh_keys()**
  - ✓ Removes orphaned SSH keys
  - ✓ Preserves valid SSH keys

### State Management Tests

- **initialize_state_dir()**
  - ✓ Creates state directory structure
  - ✓ Creates all required state files
  - ✓ Sets correct default values
  - ✓ Handles multiple shares independently

- **get_state()**
  - ✓ Retrieves correct values
  - ✓ Returns empty for non-existent fields

- **set_state()**
  - ✓ Updates existing values
  - ✓ Creates new fields
  - ✓ Persists across function calls

- **Multi-share isolation**
  - ✓ Each share has independent state
  - ✓ State changes don't affect other shares

## Test Framework

The test suite uses a custom bash testing framework (`test-framework.sh`) with the following assertions:

### Assertions

- `assert_equals expected actual [message]`
- `assert_success [message]` - Checks $? == 0
- `assert_failure [message]` - Checks $? != 0
- `assert_contains haystack needle [message]`
- `assert_file_exists filepath [message]`
- `assert_dir_exists dirpath [message]`
- `assert_gt value1 value2 [message]` - Greater than
- `assert_lt value1 value2 [message]` - Less than

### Test Structure

```bash
#!/usr/bin/env bash
set -e

source "$(dirname "$0")/test-framework.sh"

test_suite_start "My Test Suite"

test_start "Test description"
# ... test code ...
assert_equals "expected" "actual"

test_start "Another test"
some_function >/dev/null 2>&1
assert_success

test_suite_end
exit_with_status
```

## Adding New Tests

1. Create a new test file: `test-your-feature.sh`
2. Source the test framework
3. Mock required bashio functions
4. Write tests using the assertion functions
5. Add to `run-all-tests.sh`

Example:

```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Mock bashio functions
bashio::log.info() { echo "[INFO] $*" >/dev/null; }

# Source code under test
source "${SCRIPT_DIR}/../rootfs/usr/bin/your-script.sh"

test_suite_start "Your Feature"

test_start "Test something"
result=$(your_function "input")
assert_equals "expected" "$result"

test_suite_end
exit_with_status
```

## CI/CD Integration

These tests can be integrated into GitHub Actions or other CI systems:

```yaml
- name: Run bash tests
  run: |
    cd tests
    chmod +x *.sh
    ./run-all-tests.sh
```

## Continuous Testing

For development, you can use `watch` to run tests automatically:

```bash
watch -n 2 ./run-all-tests.sh
```

## Test Output

The test framework provides colored output:
- 🟢 Green checkmark (✓) for passed tests
- 🔴 Red cross (✗) for failed tests
- Yellow for test suite headers
- Blue for overall summary

Example output:
```
Running: mount-helper.sh
----------------------------------------
  validate_share_name accepts valid alphanumeric... ✓
  validate_share_name accepts hyphens... ✓
  validate_share_name rejects empty string... ✓
  ...
----------------------------------------
Passed: 15
Failed: 0

All tests passed!
```

## Debugging Failed Tests

When a test fails, the framework shows:
- Expected value
- Actual value
- Custom message (if provided)

Example:
```
  calculate_backoff_delay - retry 1, base 5... ✗
    Expected: '10'
    Actual:   '5'
    Message:  Exponential backoff calculation
```

## Best Practices

1. **Mock External Dependencies**: Always mock bashio functions
2. **Cleanup**: Remove temporary files/directories after tests
3. **Isolation**: Each test should be independent
4. **Clear Names**: Use descriptive test names
5. **Assert Messages**: Provide helpful failure messages
6. **Edge Cases**: Test boundary conditions

## Known Limitations

- Tests run on the host system, not in the container
- Some integration tests require docker/s6-overlay (not included)
- Mount-related tests are limited without FUSE support

## Future Enhancements

- [ ] Integration tests for full service lifecycle
- [ ] Mock mount/unmount operations
- [ ] Performance benchmarks
- [ ] Code coverage reporting
- [ ] Automated test generation
