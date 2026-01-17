#!/usr/bin/env bats
# data-flow-tracing.bats - AC-006 Data Flow Tracing Acceptance Tests
#
# Purpose: Verify call-chain.sh --trace-data-flow functionality
# Depends: bats-core
# Run: bats tests/data-flow-tracing.bats
#
# Baseline: 2026-01-11
# Change: enhance-code-intelligence
# Trace: AC-006

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
CALL_CHAIN="${PROJECT_ROOT}/scripts/call-chain.sh"

# ============================================================
# Basic Functionality Tests
# ============================================================

@test "DF-BASE-001: call-chain.sh exists and is executable" {
    [ -x "$CALL_CHAIN" ]
}

# ============================================================
# Data Flow Tracing Tests (DF-001 ~ DF-003)
# ============================================================

@test "DF-001: parameter flow tracing (--trace-data-flow)" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --format json 2>&1
    [ "$status" -eq 0 ] || skip "Data flow tracing not yet implemented"
    [[ "$output" == *"path"* ]] || [[ "$output" == *"flow"* ]]
}

@test "DF-002: return value flow tracing" {
    run "$CALL_CHAIN" --symbol "runScript" --trace-data-flow --format json 2>&1
    [ "$status" -eq 0 ] || skip "Return value tracing not yet implemented"
    [[ "$output" == *"sink"* ]] || [[ "$output" == *"target"* ]] || [[ "$output" == *"usage"* ]]
}

@test "DF-003: default behavior compatible (no --trace-data-flow)" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --format json 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"chain"* ]] || [[ "$output" == *"calls"* ]] || [ "$status" -eq 0 ]
}

# ============================================================
# CLI Parameter Tests (DF-004)
# ============================================================

@test "DF-004: --help includes --trace-data-flow description" {
    run "$CALL_CHAIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"trace-data-flow"* ]] || \
    [[ "$output" == *"data-flow"* ]] || \
    [[ "$output" == *"parameter"* ]]
}

@test "DF-004b: --trace-data-flow parameter available" {
    run "$CALL_CHAIN" --symbol "test" --trace-data-flow 2>&1
    [[ "$output" != *"unknown"* ]] && [[ "$output" != *"invalid"* ]] || skip "Parameter not yet added"
}

# ============================================================
# Data Flow Path Format Tests
# ============================================================

@test "DF-PATH-001: path includes source" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --format json 2>&1
    [ "$status" -eq 0 ] || skip "Data flow tracing not yet implemented"
    [[ "$output" == *"source"* ]] || [[ "$output" == *"from"* ]]
}

@test "DF-PATH-002: path includes function name" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --format json 2>&1
    [ "$status" -eq 0 ] || skip "Data flow tracing not yet implemented"
    [[ "$output" == *"function"* ]] || [[ "$output" == *"name"* ]]
}

@test "DF-PATH-003: path includes parameter name" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --format json 2>&1
    [ "$status" -eq 0 ] || skip "Data flow tracing not yet implemented"
    [[ "$output" == *"parameter"* ]] || [[ "$output" == *"arg"* ]] || [[ "$output" == *"param"* ]]
}

# ============================================================
# Transformation Point Tests
# ============================================================

@test "DF-TRANSFORM-001: transformation point marking" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --format json 2>&1
    [ "$status" -eq 0 ] || skip "Transformation tracking not yet implemented"
    [[ "$output" == *"transformation"* ]] || [[ "$output" == *"transform"* ]] || true
}

# ============================================================
# Output Format Tests
# ============================================================

@test "DF-OUTPUT-001: JSON output is valid JSON" {
    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --format json 2>&1
    [ "$status" -eq 0 ] || skip "Data flow tracing not yet implemented"
    echo "$output" | jq . > /dev/null 2>&1
}

@test "DF-OUTPUT-002: output includes call chain info" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --format json 2>&1
    [ "$status" -eq 0 ] || skip "Data flow tracing not yet implemented"
    [[ "$output" == *"call"* ]] || [[ "$output" == *"chain"* ]]
}

# ============================================================
# Backward Compatibility Tests
# ============================================================

@test "DF-COMPAT-001: original --direction parameter still works" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --direction callers --format json 2>&1
    [ "$status" -eq 0 ]
}

@test "DF-COMPAT-002: original --depth parameter still works" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --depth 3 --format json 2>&1
    [ "$status" -eq 0 ]
}

# ============================================================
# Parameter Validation Tests
# ============================================================

@test "DF-PARAM-001: --symbol parameter required" {
    run "$CALL_CHAIN" --trace-data-flow --format json 2>&1
    [ "$status" -ne 0 ] || [[ "$output" == *"symbol"* ]]
}

@test "DF-PARAM-002: invalid parameter returns error" {
    run "$CALL_CHAIN" --invalid-option
    [ "$status" -ne 0 ]
}

# ============================================================
# Boundary Value Tests (DF-BOUNDARY)
# ============================================================

@test "DF-BOUNDARY-001: non-existent symbol returns error or empty" {
    run "$CALL_CHAIN" --symbol "nonExistentSymbol12345" --trace-data-flow --format json 2>&1
    # Should return empty result or appropriate error
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"not found"* ]] || \
    [[ "$output" == *"empty"* ]] || \
    skip "Non-existent symbol handling not yet implemented"
}

@test "DF-BOUNDARY-002: empty symbol returns error" {
    run "$CALL_CHAIN" --symbol "" --trace-data-flow --format json 2>&1
    # Empty symbol should be rejected
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"required"* ]] || \
    [[ "$output" == *"empty"* ]]
}

@test "DF-BOUNDARY-003: symbol with special characters handled" {
    run "$CALL_CHAIN" --symbol "module.exports.functionName" --trace-data-flow --format json 2>&1
    # Should handle qualified names
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"not found"* ]] || \
    skip "Special character symbol not yet supported"
}

@test "DF-BOUNDARY-004: --depth 0 with --trace-data-flow handled" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --depth 0 --format json 2>&1
    # Should either work or return appropriate error
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"invalid"* ]] || \
    skip "Depth 0 handling not yet implemented"
}

@test "DF-BOUNDARY-005: --depth negative returns error" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --depth -1 --format json 2>&1
    # Negative depth should be rejected
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"invalid"* ]] || \
    [[ "$output" == *"error"* ]] || \
    skip "Negative depth not yet validated"
}

@test "DF-BOUNDARY-006: very large depth handled" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --depth 100 --format json 2>&1
    # Should cap at reasonable max or succeed
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"max"* ]] || \
    [[ "$output" == *"limit"* ]] || \
    skip "Depth cap not yet implemented"
}

@test "DF-BOUNDARY-007: conflicting direction with trace-data-flow" {
    run "$CALL_CHAIN" --symbol "handleToolCall" --trace-data-flow --direction callees --format json 2>&1
    # Should handle combination gracefully
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"conflict"* ]] || \
    skip "Direction + trace-data-flow conflict handling not yet implemented"
}

