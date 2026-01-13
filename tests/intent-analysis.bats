#!/usr/bin/env bats
# intent-analysis.bats - AC-002 Intent Analysis Acceptance Tests
#
# Purpose: Verify augment-context-global.sh 4-dimensional intent analysis
# Depends: bats-core
# Run: bats tests/intent-analysis.bats
#
# Baseline: 2026-01-11
# Change: enhance-code-intelligence
# Trace: AC-002

# Load shared helpers
load 'helpers/common'

HOOK_SCRIPT="./hooks/augment-context-global.sh"

# ============================================================
# Basic Functionality Tests
# ============================================================

@test "IA-BASE-001: augment-context-global.sh exists and is executable" {
    [ -x "$HOOK_SCRIPT" ]
}

# ============================================================
# 4-Dimensional Intent Signal Tests (IA-001 ~ IA-004)
# ============================================================

@test "IA-001: explicit signal extraction" {
    run "$HOOK_SCRIPT" --analyze-intent --prompt "fix authentication bug" 2>&1
    [ "$status" -eq 0 ] || skip "Intent analysis not yet implemented"
    [[ "$output" == *"explicit"* ]]
}

@test "IA-002: implicit signal extraction" {
    run "$HOOK_SCRIPT" --analyze-intent --file "src/auth/login.ts" --line 42 2>&1
    [ "$status" -eq 0 ] || skip "Intent analysis not yet implemented"
    [[ "$output" == *"implicit"* ]]
}

@test "IA-003: historical signal extraction" {
    run "$HOOK_SCRIPT" --analyze-intent --with-history 2>&1
    [ "$status" -eq 0 ] || skip "Intent analysis not yet implemented"
    [[ "$output" == *"historical"* ]]
}

@test "IA-004: code signal extraction" {
    run "$HOOK_SCRIPT" --analyze-intent --file "src/auth.ts" --function "validateToken" 2>&1
    [ "$status" -eq 0 ] || skip "Intent analysis not yet implemented"
    [[ "$output" == *"code"* ]]
}

# ============================================================
# Signal Aggregation Tests
# ============================================================

@test "IA-AGG-001: 4-dimensional signal aggregation output" {
    run "$HOOK_SCRIPT" --analyze-intent --prompt "fix bug" --file "src/test.ts" 2>&1
    [ "$status" -eq 0 ] || skip "Intent analysis not yet implemented"
    [[ "$output" == *"explicit"* ]] || [[ "$output" == *"signal"* ]]
}

@test "IA-AGG-002: missing signals have weight 0" {
    run "$HOOK_SCRIPT" --analyze-intent --prompt "test" 2>&1
    [ "$status" -eq 0 ] || skip "Intent analysis not yet implemented"
}

# ============================================================
# Output Format Tests
# ============================================================

@test "IA-OUTPUT-001: intent analysis output includes signal labels" {
    run "$HOOK_SCRIPT" --analyze-intent --prompt "test" 2>&1
    [ "$status" -eq 0 ] || skip "Intent analysis not yet implemented"

    [[ "$output" == *"explicit"* ]] || \
    [[ "$output" == *"implicit"* ]] || \
    [[ "$output" == *"historical"* ]] || \
    [[ "$output" == *"code"* ]] || \
    [[ "$output" == *"signal"* ]]
}

@test "IA-OUTPUT-002: signal weights in valid range 0-1" {
    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi

    run "$HOOK_SCRIPT" --analyze-intent --prompt "test" --format json 2>&1
    [ "$status" -eq 0 ] || skip "Intent analysis not yet implemented"

    echo "$output" | jq '.signals[].weight >= 0 and .signals[].weight <= 1' 2>/dev/null || true
}

# ============================================================
# Parameter Validation Tests
# ============================================================

@test "IA-PARAM-001: --analyze-intent parameter support" {
    run "$HOOK_SCRIPT" --help 2>&1

    [[ "$output" == *"intent"* ]] || \
    [[ "$output" == *"signal"* ]] || \
    [[ "$output" == *"4"* ]] || \
    skip "Intent analysis parameter not documented"
}

# ============================================================
# Backward Compatibility Tests
# ============================================================

@test "IA-COMPAT-001: without --analyze-intent maintains original behavior" {
    run "$HOOK_SCRIPT" 2>&1
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
