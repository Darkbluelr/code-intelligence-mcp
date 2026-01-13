#!/usr/bin/env bash
# common.bash - Shared test helper functions
#
# Usage: load 'helpers/common'
#
# Provides:
#   - assert_contains: Check if output contains a string
#   - assert_contains_any: Check if output contains any of the given strings
#   - assert_valid_json: Validate JSON output
#   - assert_exit_success: Check exit status is 0
#   - assert_exit_failure: Check exit status is non-zero
#   - setup_temp_dir: Create temporary test directory
#   - cleanup_temp_dir: Remove temporary test directory

# ============================================================
# Assertion Helpers
# ============================================================

# Assert that output contains a specific string
# Usage: assert_contains "$output" "expected"
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-Expected output to contain '$needle'}"

    if [[ "$haystack" != *"$needle"* ]]; then
        echo "Assertion failed: $msg" >&2
        echo "Output was: $haystack" >&2
        return 1
    fi
}

# Assert that output contains any of the given strings
# Usage: assert_contains_any "$output" "str1" "str2" "str3"
assert_contains_any() {
    local haystack="$1"
    shift
    local needles=("$@")

    for needle in "${needles[@]}"; do
        if [[ "$haystack" == *"$needle"* ]]; then
            return 0
        fi
    done

    echo "Assertion failed: Expected output to contain any of: ${needles[*]}" >&2
    echo "Output was: $haystack" >&2
    return 1
}

# Assert that output does NOT contain a specific string
# Usage: assert_not_contains "$output" "unexpected"
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-Expected output to NOT contain '$needle'}"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo "Assertion failed: $msg" >&2
        echo "Output was: $haystack" >&2
        return 1
    fi
}

# Assert that output is valid JSON
# Usage: assert_valid_json "$output"
assert_valid_json() {
    local json="$1"
    local msg="${2:-Expected valid JSON output}"

    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi

    if ! echo "$json" | jq . > /dev/null 2>&1; then
        echo "Assertion failed: $msg" >&2
        echo "Output was: $json" >&2
        return 1
    fi
}

# Assert exit status is 0
# Usage: assert_exit_success "$status"
assert_exit_success() {
    local status="$1"
    local msg="${2:-Expected exit status 0}"

    if [ "$status" -ne 0 ]; then
        echo "Assertion failed: $msg (got status $status)" >&2
        return 1
    fi
}

# Assert exit status is non-zero
# Usage: assert_exit_failure "$status"
assert_exit_failure() {
    local status="$1"
    local msg="${2:-Expected non-zero exit status}"

    if [ "$status" -eq 0 ]; then
        echo "Assertion failed: $msg (got status 0)" >&2
        return 1
    fi
}

# Assert JSON field exists and optionally matches value
# Usage: assert_json_field "$json" ".field" ["expected_value"]
assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="${3:-}"

    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi

    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)

    if [ "$actual" = "null" ] || [ -z "$actual" ]; then
        echo "Assertion failed: JSON field '$field' not found" >&2
        return 1
    fi

    if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
        echo "Assertion failed: Expected '$field' to be '$expected', got '$actual'" >&2
        return 1
    fi
}

# Assert JSON array has minimum length
# Usage: assert_json_array_min_length "$json" ".array" 5
assert_json_array_min_length() {
    local json="$1"
    local field="$2"
    local min_length="$3"

    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi

    local actual_length
    actual_length=$(echo "$json" | jq "$field | length" 2>/dev/null)

    if [ "$actual_length" -lt "$min_length" ]; then
        echo "Assertion failed: Expected '$field' to have at least $min_length items, got $actual_length" >&2
        return 1
    fi
}

# ============================================================
# Test Environment Helpers
# ============================================================

# Setup temporary test directory
# Usage: setup_temp_dir
# Sets: TEST_TEMP_DIR variable
setup_temp_dir() {
    TEST_TEMP_DIR=$(mktemp -d)
    export TEST_TEMP_DIR
}

# Cleanup temporary test directory
# Usage: cleanup_temp_dir
cleanup_temp_dir() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Backup a file before test
# Usage: backup_file "$filepath"
backup_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        cp "$filepath" "${filepath}.bak"
    fi
}

# Restore a file after test
# Usage: restore_file "$filepath"
restore_file() {
    local filepath="$1"
    if [ -f "${filepath}.bak" ]; then
        mv "${filepath}.bak" "$filepath"
    fi
}

# ============================================================
# Timeout and Performance Helpers
# ============================================================

# Run command with timeout (in seconds)
# Usage: run_with_timeout 5 command args...
run_with_timeout() {
    local timeout="$1"
    shift

    if command -v timeout &> /dev/null; then
        timeout "$timeout" "$@"
    elif command -v gtimeout &> /dev/null; then
        gtimeout "$timeout" "$@"
    else
        # Fallback: just run without timeout
        "$@"
    fi
}

# Measure execution time in milliseconds
# Usage: measure_time command args...
# Returns: Sets MEASURED_TIME_MS variable
measure_time() {
    local start_ns end_ns
    start_ns=$(date +%s%N 2>/dev/null || echo "0")

    "$@"
    local exit_code=$?

    end_ns=$(date +%s%N 2>/dev/null || echo "0")

    if [ "$start_ns" != "0" ] && [ "$end_ns" != "0" ]; then
        MEASURED_TIME_MS=$(( (end_ns - start_ns) / 1000000 ))
    else
        # Fallback for systems without nanosecond support
        MEASURED_TIME_MS=0
    fi

    export MEASURED_TIME_MS
    return $exit_code
}

# ============================================================
# Skip Helpers
# ============================================================

# Skip if command not found
# Usage: skip_if_missing "jq"
skip_if_missing() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        skip "$cmd not installed"
    fi
}

# Skip if file not found
# Usage: skip_if_no_file "/path/to/file"
skip_if_no_file() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then
        skip "File not found: $filepath"
    fi
}

# Skip if script not executable
# Usage: skip_if_not_executable "/path/to/script.sh"
skip_if_not_executable() {
    local script="$1"
    if [ ! -x "$script" ]; then
        skip "Script not executable: $script"
    fi
}

# Skip if feature not yet implemented
# IMPORTANT: Use this for Red baseline testing
# In Green phase (EXPECT_RED=false), this will FAIL instead of skip
# Usage: skip_not_implemented "Feature name"
skip_not_implemented() {
    local feature="$1"
    if [ "${EXPECT_RED:-true}" = "true" ]; then
        skip "$feature not yet implemented"
    else
        echo "FAIL: $feature should be implemented but is not" >&2
        return 1
    fi
}

# Conditional skip based on implementation status
# Usage: skip_if_not_ready "$status" "$output" "Feature name"
# - In EXPECT_RED=true mode: skips test
# - In EXPECT_RED=false mode: fails test if not implemented
skip_if_not_ready() {
    local status="$1"
    local output="$2"
    local feature="$3"

    if [ "$status" -ne 0 ]; then
        if [ "${EXPECT_RED:-true}" = "true" ]; then
            skip "$feature not yet implemented"
        else
            echo "FAIL: $feature should pass but returned status $status" >&2
            echo "Output: $output" >&2
            return 1
        fi
    fi
}

# Report skip count at end of test run (for CI visibility)
# Usage: Call in test file's global teardown or manually
report_skip_warning() {
    if [ "${EXPECT_RED:-true}" = "false" ]; then
        echo "WARNING: Running in Green phase (EXPECT_RED=false)"
        echo "Any skip should be investigated as potential regression"
    fi
}

# ============================================================
# Path Helpers
# ============================================================

# Generate a path with special characters for testing
# Usage: get_special_char_path
get_special_char_path() {
    echo "path with spaces/and-dashes/file.txt"
}

# Generate an excessively long path for boundary testing
# Usage: get_long_path
get_long_path() {
    local depth="${1:-50}"
    local path=""
    for ((i=0; i<depth; i++)); do
        path="${path}/dir${i}"
    done
    echo "$path/file.txt"
}
