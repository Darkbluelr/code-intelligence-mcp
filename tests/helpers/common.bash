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
# Test Constants
# ============================================================

# Git test user credentials (avoid magic strings in tests)
GIT_TEST_EMAIL="${GIT_TEST_EMAIL:-test@test.com}"
GIT_TEST_NAME="${GIT_TEST_NAME:-Test User}"
export GIT_TEST_EMAIL GIT_TEST_NAME

# ============================================================
# Assertion Helpers
# ============================================================

# Fail the test immediately with a message
# Usage: fail "reason for failure"
# Note: This is a basic fail function for bats tests
fail() {
    local msg="${1:-Test failed}"
    echo "FAIL: $msg" >&2
    return 1
}

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

# Get current time in nanoseconds (cross-platform)
# Usage: get_time_ns
# Returns: timestamp in nanoseconds via stdout
# Note: macOS date doesn't support %N, use gdate or perl fallback
get_time_ns() {
    if date +%s%N 2>/dev/null | grep -q 'N'; then
        # date doesn't support %N (macOS)
        if command -v gdate &>/dev/null; then
            gdate +%s%N
        elif command -v perl &>/dev/null; then
            perl -MTime::HiRes -e 'printf "%d\n", Time::HiRes::time() * 1e9'
        else
            # Fallback to seconds precision (multiply by 1e9)
            echo "$(date +%s)000000000"
        fi
    else
        date +%s%N
    fi
}

# Measure execution time in milliseconds
# Usage: measure_time command args...
# Returns: Sets MEASURED_TIME_MS variable
measure_time() {
    local start_ns end_ns
    start_ns=$(get_time_ns)

    "$@"
    local exit_code=$?

    end_ns=$(get_time_ns)

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
            local first_line=""
            first_line=$(echo "$output" | head -n 1 | tr -d '\r')
            if [ -n "$first_line" ]; then
                skip "$feature not yet implemented (status=$status): $first_line"
            else
                skip "$feature not yet implemented (status=$status)"
            fi
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

# Skip if feature output indicates not implemented
# Usage: skip_if_feature_not_implemented "$output" "feature-name"
# Checks for common "not implemented" patterns in output
skip_if_feature_not_implemented() {
    local output="$1"
    local feature="${2:-feature}"
    if [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"--help"* ]] || \
       [[ "$output" == *"unknown option"* ]] || [[ "$output" == *"unrecognized"* ]] || \
       [[ "$output" == *"not implemented"* ]] || [[ "$output" == *"not yet"* ]]; then
        skip "$feature not yet implemented"
    fi
}

# ============================================================
# Git Test Helpers
# ============================================================

# Setup a test git repository with initial commit
# Usage: setup_test_git_repo "$TEST_TEMP_DIR/repo"
# Sets: GIT_TEST_REPO_DIR variable
setup_test_git_repo() {
    local repo_dir="${1:-$TEST_TEMP_DIR/repo}"
    mkdir -p "$repo_dir"
    cd "$repo_dir" || return 1

    git init --quiet 2>/dev/null || return 1
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    GIT_TEST_REPO_DIR="$repo_dir"
    export GIT_TEST_REPO_DIR
}

# Setup test git repo with src directory
# Usage: setup_test_git_repo_with_src "$TEST_TEMP_DIR/repo"
setup_test_git_repo_with_src() {
    local repo_dir="${1:-$TEST_TEMP_DIR/repo}"
    setup_test_git_repo "$repo_dir" || return 1
    mkdir -p "$repo_dir/src"
}

# Cleanup and return from test git repo
# Usage: cleanup_test_git_repo
cleanup_test_git_repo() {
    cd - > /dev/null 2>&1 || true
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

# ============================================================
# Float Comparison Helpers (Cross-platform)
# ============================================================

# Compare float >= threshold using awk (portable across all Unix systems)
# Usage: float_gte "0.95" "0.9" && echo "yes"
# Returns 0 if first >= second, 1 otherwise
float_gte() {
    awk -v v="$1" -v t="$2" 'BEGIN { exit !(v >= t) }'
}

# Compare float < threshold using awk (portable)
# Usage: float_lt "0.7" "0.8" && echo "yes"
float_lt() {
    awk -v v="$1" -v t="$2" 'BEGIN { exit !(v < t) }'
}

# Assert confidence >= threshold with proper error message
# Usage: assert_confidence_gte "$output" ".confidence" "0.9"
assert_confidence_gte() {
    local json="$1"
    local field="$2"
    local threshold="$3"

    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi

    local confidence
    confidence=$(echo "$json" | jq -r "$field" 2>/dev/null)

    if [ "$confidence" = "null" ] || [ -z "$confidence" ]; then
        echo "Assertion failed: confidence field '$field' not found" >&2
        return 1
    fi

    if ! float_gte "$confidence" "$threshold"; then
        echo "Assertion failed: confidence $confidence < $threshold" >&2
        return 1
    fi
}

# Assert confidence < threshold
# Usage: assert_confidence_lt "$output" ".confidence" "0.8"
assert_confidence_lt() {
    local json="$1"
    local field="$2"
    local threshold="$3"

    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi

    local confidence
    confidence=$(echo "$json" | jq -r "$field" 2>/dev/null)

    if [ "$confidence" = "null" ] || [ -z "$confidence" ]; then
        echo "Assertion failed: confidence field '$field' not found" >&2
        return 1
    fi

    if ! float_lt "$confidence" "$threshold"; then
        echo "Assertion failed: confidence $confidence >= $threshold" >&2
        return 1
    fi
}

# ============================================================
# Percentile Calculation Helpers
# ============================================================

# Calculate P95 from an array of values (nearest-rank, 1-based index)
# Usage: calculate_p95 "${latencies[@]}"
# Returns: P95 value via stdout
calculate_p95() {
    local values=("$@")
    local count=${#values[@]}

    if [ "$count" -lt 1 ]; then
        echo "0"
        return 1
    fi

    # Sort values numerically to apply percentile index on ordered data.
    local sorted
    sorted=$(printf '%s\n' "${values[@]}" | sort -n)

    # Calculate P95 index using nearest-rank (ceil(0.95 * N)).
    # Keeps index within [1, N] to avoid empty selection.
    local p95_index
    p95_index=$(awk -v n="$count" 'BEGIN { idx = int(0.95 * n); if (0.95 * n > idx) idx++; print idx }')

    # Ensure index is within bounds [1, count]
    if [ "$p95_index" -lt 1 ]; then
        p95_index=1
    fi
    if [ "$p95_index" -gt "$count" ]; then
        p95_index=$count
    fi

    # Extract the indexed value with awk for portable 1-based lookup.
    echo "$sorted" | awk -v idx="$p95_index" 'NR == idx { print; exit }'
}

# Assert P95 is below threshold
# Usage: assert_p95_below "${latencies[@]}" 100
# Last argument is the threshold
assert_p95_below() {
    local threshold="${!#}"  # Get last argument
    local values=("${@:1:$#-1}")  # Get all but last argument

    local p95
    p95=$(calculate_p95 "${values[@]}")

    if [ -z "$p95" ] || [ "$p95" = "0" ]; then
        echo "Could not calculate P95" >&2
        return 1
    fi

    if [ "$p95" -ge "$threshold" ]; then
        echo "P95 ($p95) >= threshold ($threshold)" >&2
        return 1
    fi
}

# ============================================================
# JSON Extraction Helpers
# ============================================================

# Extract JSON from mixed output (stdout + stderr merged by BATS run).
# Strategy: try single-line object/array → multiline object by brace depth → marker line → whole input.
# Usage: extract_json "$output"
# Returns: Pure JSON string via stdout
# Handles: JSON objects {}, arrays [], multiline JSON, mixed stderr/stdout
extract_json() {
    local input="$1"

    # Return empty if input is empty
    if [ -z "$input" ]; then
        return 1
    fi

    # Strategy 1: Try to find a complete JSON object on a single line
    local single_line_json
    single_line_json=$(echo "$input" | grep -E '^\s*\{.*\}\s*$' | head -1)
    if [ -n "$single_line_json" ] && echo "$single_line_json" | jq . > /dev/null 2>&1; then
        echo "$single_line_json"
        return 0
    fi

    # Strategy 2: Try to find a complete JSON array on a single line
    single_line_json=$(echo "$input" | grep -E '^\s*\[.*\]\s*$' | head -1)
    if [ -n "$single_line_json" ] && echo "$single_line_json" | jq . > /dev/null 2>&1; then
        echo "$single_line_json"
        return 0
    fi

    # Strategy 3: Extract multiline JSON object (from first { to matching })
    local multiline_json
    multiline_json=$(echo "$input" | awk '
        BEGIN { depth = 0; started = 0; json = "" }
        /\{/ && !started { started = 1 }
        started {
            json = json $0 "\n"
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") depth++
                else if (c == "}") depth--
            }
            if (depth == 0 && started) {
                print json
                exit
            }
        }
    ')
    if [ -n "$multiline_json" ] && echo "$multiline_json" | jq . > /dev/null 2>&1; then
        echo "$multiline_json"
        return 0
    fi

    # Strategy 4: Look for lines with common JSON markers
    local marker_json
    marker_json=$(echo "$input" | grep -E '"schema_version"|"hotspots"|"type"|"results"' | head -1)
    if [ -n "$marker_json" ] && echo "$marker_json" | jq . > /dev/null 2>&1; then
        echo "$marker_json"
        return 0
    fi

    # Strategy 5: Last resort - try the entire input as JSON
    if echo "$input" | jq . > /dev/null 2>&1; then
        echo "$input"
        return 0
    fi

    # No valid JSON found
    return 1
}

# Run command and capture only JSON output (redirect stderr to /dev/null)
# Usage: run_json_only command args...
# Sets: output (JSON only), status
run_json_only() {
    output=$("$@" 2>/dev/null)
    status=$?
}

# Assert that output contains valid JSON
# Usage: assert_json_output "$output"
assert_json_output() {
    local input="$1"

    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi

    # Try to extract and validate JSON
    local json
    json=$(extract_json "$input")

    if [ -z "$json" ]; then
        echo "No JSON found in output" >&2
        echo "Output was: $input" >&2
        return 1
    fi

    if ! echo "$json" | jq . > /dev/null 2>&1; then
        echo "Invalid JSON: $json" >&2
        return 1
    fi
}
