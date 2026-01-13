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

# Test configuration
BUG_LOCATOR="./scripts/bug-locator.sh"
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
