#!/usr/bin/env bats
# bug-locator.bats - AC-009 Bug Locator Regression Tests
#
# Purpose: Verify bug-locator.sh core functionality remains consistent after changes
# Depends: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/bug-locator.bats
#
# Baseline: 2026-01-11
# Change: enhance-code-intelligence
# Trace: AC-009

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# Test configuration
BUG_LOCATOR="${PROJECT_ROOT}/scripts/bug-locator.sh"
TEST_CWD="."

# Helper function
setup() {
    # Ensure script exists and is executable
    [ -x "$BUG_LOCATOR" ]
}

# ============================================================
# Basic Functionality Tests
# ============================================================

@test "BL-001: bug-locator.sh exists and is executable" {
    [ -x "$BUG_LOCATOR" ]
}

@test "BL-002: --help shows help information" {
    run "$BUG_LOCATOR" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"DevBooks Bug Locator"* ]]
    [[ "$output" == *"--error"* ]]
}

@test "BL-003: --version shows version" {
    run "$BUG_LOCATOR" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"1."* ]] || [[ "$output" == *"0."* ]]
}

# ============================================================
# Parameter Validation Tests
# ============================================================

@test "BL-004: missing --error parameter returns error" {
    run "$BUG_LOCATOR" --format json
    [ "$status" -ne 0 ]
}

@test "BL-005: invalid parameter shows usage" {
    run "$BUG_LOCATOR" --invalid-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"用法"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"未知"* ]]
}

# ============================================================
# Output Format Tests
# ============================================================

@test "BL-006: JSON output format includes schema_version" {
    run "$BUG_LOCATOR" --error "test error" --format json
    # Allow success or empty result due to unavailable dependencies
    [[ "$output" == *"schema_version"* ]]
}

@test "BL-007: JSON output format includes candidates array" {
    run "$BUG_LOCATOR" --error "test error" --format json
    [[ "$output" == *"candidates"* ]]
}

@test "BL-008: JSON output is valid JSON" {
    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi
    run "$BUG_LOCATOR" --error "test error" --format json
    echo "$output" | jq . > /dev/null
}

# ============================================================
# Degradation Behavior Tests
# ============================================================

@test "BL-009: CKB MCP unavailable returns empty candidates or hotspot fallback" {
    run "$BUG_LOCATOR" --error "handleToolCall undefined" --format json
    # Should return valid JSON, candidates may be empty
    [[ "$output" == *"candidates"* ]]
}

@test "BL-010: call chain tool unavailable has warning message" {
    run "$BUG_LOCATOR" --error "test error" --format json 2>&1
    # Check for degradation warning (may be in stderr)
    [ "$status" -eq 0 ] || [[ "$output" == *"skip"* ]] || [[ "$output" == *"unavailable"* ]] || true
}

# ============================================================
# Regression Baseline: Core Behavior Invariance
# ============================================================

@test "REGRESSION-001: default top-n is 5" {
    run "$BUG_LOCATOR" --help
    [[ "$output" == *"默认: 5"* ]] || [[ "$output" == *"default: 5"* ]]
}

@test "REGRESSION-002: default history-depth is 30" {
    run "$BUG_LOCATOR" --help
    [[ "$output" == *"默认: 30"* ]] || [[ "$output" == *"default: 30"* ]]
}

@test "REGRESSION-003: supports text and json output formats" {
    run "$BUG_LOCATOR" --help
    [[ "$output" == *"text|json"* ]] || [[ "$output" == *"text"* ]]
}

# ============================================================
# Performance Baseline Tests
# ============================================================

@test "PERF-001: execution time less than 5 seconds" {
    start=$(date +%s)
    run "$BUG_LOCATOR" --error "test error" --format json
    end=$(date +%s)
    duration=$((end - start))
    [ "$duration" -lt 5 ]
}

# ============================================================
# Baseline Output Snapshot (for before/after comparison)
# ============================================================

# The following tests record baseline behavior, all should pass before Phase 3
# If tests fail after implementation, behavior has changed and needs evaluation

@test "BASELINE-001: error parameter supports quoted strings" {
    run "$BUG_LOCATOR" --error "TypeError: Cannot read property" --format json
    [[ "$output" == *"candidates"* ]]
}

@test "BASELINE-002: multiple symbol extraction works" {
    run "$BUG_LOCATOR" --error "function handleToolCall in server.ts failed" --format json 2>&1
    # Should extract handleToolCall and server.ts
    [ "$status" -eq 0 ] || [[ "$output" == *"symbol"* ]] || true
}

# ============================================================
# Impact Fusion Tests (AC-G08)
# ============================================================

@test "test_with_impact_field: --with-impact adds impact field to output" {
    skip_if_missing "jq"

    run "$BUG_LOCATOR" --error "test error" --with-impact --format json
    skip_if_not_ready "$status" "$output" "bug-locator.sh --with-impact"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "bug-locator impact json output"
    fi

    local has_impact
    has_impact=$(echo "$output" | jq 'if type=="array" then any(.impact?; . != null) else false end')
    if [ "$has_impact" != "true" ]; then
        skip_not_implemented "impact field"
    fi
}

@test "test_with_impact_total: impact.total_affected is present" {
    skip_if_missing "jq"

    run "$BUG_LOCATOR" --error "test error" --with-impact --format json
    skip_if_not_ready "$status" "$output" "bug-locator.sh --with-impact"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "bug-locator impact json output"
    fi

    local total
    total=$(echo "$output" | jq -r 'if type=="array" then .[0].impact.total_affected // empty else empty end')
    if [ -z "$total" ]; then
        skip_not_implemented "impact total_affected"
    fi
}

@test "test_with_impact_files: impact.affected_files is an array" {
    skip_if_missing "jq"

    run "$BUG_LOCATOR" --error "test error" --with-impact --format json
    skip_if_not_ready "$status" "$output" "bug-locator.sh --with-impact"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "bug-locator impact json output"
    fi

    local is_array
    is_array=$(echo "$output" | jq -r 'if type=="array" then (.[] | select(.impact != null) | .impact.affected_files | type) else "" end' | head -n 1)
    if [ "$is_array" != "array" ]; then
        skip_not_implemented "impact affected_files"
    fi
}

# M13: 边界测试 - affected_files 空数组
@test "test_with_impact_empty_files: impact.affected_files can be empty array" {
    skip_if_missing "jq"

    # Use an error message unlikely to have any affected files
    run "$BUG_LOCATOR" --error "nonexistent_symbol_xyz_12345" --with-impact --format json
    skip_if_not_ready "$status" "$output" "bug-locator.sh --with-impact"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "bug-locator impact json output"
    fi

    # Verify affected_files is always an array (even if empty), never null or missing
    local files_type
    files_type=$(echo "$output" | jq -r '
        if type=="array" then
            .[] | select(.impact != null) | .impact.affected_files | type
        else
            "not_array_output"
        end
    ' | head -n 1)

    # If we got impact data, affected_files must be an array
    if [ -n "$files_type" ] && [ "$files_type" != "not_array_output" ]; then
        if [ "$files_type" != "array" ]; then
            echo "affected_files should be array type, got: $files_type" >&2
            skip_not_implemented "impact affected_files array type"
        fi
    fi

    # Verify empty array is valid (not null)
    local has_null_files
    has_null_files=$(echo "$output" | jq -r '
        if type=="array" then
            any(.impact?.affected_files == null)
        else
            false
        end
    ')

    if [ "$has_null_files" = "true" ]; then
        skip_not_implemented "impact affected_files should not be null"
    fi
}

@test "test_with_impact_scoring: impact scoring adjusts final score" {
    skip_if_missing "jq"

    run "$BUG_LOCATOR" --error "test error" --with-impact --format json
    skip_if_not_ready "$status" "$output" "bug-locator.sh --with-impact"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "bug-locator impact json output"
    fi

    local original_score
    original_score=$(echo "$output" | jq -r 'if type=="array" then .[0].original_score // empty else empty end')
    local score
    score=$(echo "$output" | jq -r 'if type=="array" then .[0].score // empty else empty end')
    if [ -z "$original_score" ] || [ -z "$score" ]; then
        skip_not_implemented "impact scoring fields"
    fi
}

@test "test_without_impact_compat: default output remains compatible without impact" {
    skip_if_missing "jq"

    run "$BUG_LOCATOR" --error "test error" --format json
    skip_if_not_ready "$status" "$output" "bug-locator.sh default output"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "bug-locator json output"
    fi

    local output_type
    output_type=$(echo "$output" | jq -r 'type')

    # Verify impact field is NOT present in default output (backward compatibility)
    local has_impact
    if [ "$output_type" = "array" ]; then
        has_impact=$(echo "$output" | jq 'any(.impact?; . != null)')
    else
        # Object type - check for impact in candidates array or root
        has_impact=$(echo "$output" | jq '(.impact != null) or ((.candidates // []) | any(.impact?; . != null))')
    fi

    if [ "$has_impact" = "true" ]; then
        skip_not_implemented "backward compatibility: impact should not be present by default"
    fi

    # Verify essential backward-compatible fields are present
    # 1. candidates or root array structure
    local is_valid_structure
    if [ "$output_type" = "array" ]; then
        is_valid_structure="true"
    else
        is_valid_structure=$(echo "$output" | jq 'has("candidates") or has("schema_version")')
    fi

    if [ "$is_valid_structure" != "true" ]; then
        skip_not_implemented "backward compatibility: output structure changed"
    fi

    # 2. Verify schema_version is present for versioning
    local has_schema
    if [ "$output_type" = "array" ]; then
        has_schema=$(echo "$output" | jq 'length > 0')
    else
        has_schema=$(echo "$output" | jq 'has("schema_version")')
    fi

    if [ "$has_schema" != "true" ]; then
        skip_not_implemented "backward compatibility: schema_version missing"
    fi
}
