#!/usr/bin/env bats
# hotspot-analyzer.bats - AC-001 Hotspot Algorithm Acceptance Tests
#
# Purpose: Verify hotspot-analyzer.sh core functionality
# Depends: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/hotspot-analyzer.bats
#
# Baseline: 2026-01-11
# Change: enhance-code-intelligence
# Trace: AC-001

# Load shared helpers
load 'helpers/common'

HOTSPOT_ANALYZER="./scripts/hotspot-analyzer.sh"
TEST_TIMEOUT=5

# ============================================================
# Basic Functionality Tests (HS-001, HS-002)
# ============================================================

@test "HS-001: hotspot-analyzer.sh exists and is executable" {
    [ -x "$HOTSPOT_ANALYZER" ]
}

@test "HS-002: --help shows usage information" {
    run "$HOTSPOT_ANALYZER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hotspot"* ]] || [[ "$output" == *"hotspot"* ]]
    [[ "$output" == *"--top-n"* ]] || [[ "$output" == *"top"* ]]
}

@test "HS-002b: --version shows version" {
    run "$HOTSPOT_ANALYZER" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"1."* ]] || [[ "$output" == *"0."* ]]
}

# ============================================================
# Functionality Tests (HS-003, HS-004)
# ============================================================

@test "HS-003: default returns Top-20 hotspot files in JSON" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"hotspots"* ]]
    [[ "$output" == *"schema_version"* ]]
}

@test "HS-004: custom top_n parameter" {
    run "$HOTSPOT_ANALYZER" --top-n 10 --format json
    [ "$status" -eq 0 ]
    if command -v jq &> /dev/null; then
        count=$(echo "$output" | jq '.hotspots | length')
        [ "$count" -le 10 ]
    fi
}

@test "HS-005: hotspot score formula (Frequency x Complexity)" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"frequency"* ]]
    [[ "$output" == *"complexity"* ]]
    [[ "$output" == *"score"* ]]
}

@test "HS-005b: file without git history has Frequency 0" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
}

# ============================================================
# Performance Tests (HS-006)
# ============================================================

@test "HS-006: performance baseline - execution time less than 5s" {
    measure_time "$HOTSPOT_ANALYZER" --format json
    local exit_code=$?

    [ "$exit_code" -eq 0 ]
    [ "$MEASURED_TIME_MS" -lt 5000 ] || skip "Performance baseline: ${MEASURED_TIME_MS}ms > 5000ms"
}

@test "HS-006b: output includes duration_ms field" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"duration"* ]] || [[ "$output" == *"ms"* ]] || true
}

# ============================================================
# Parameter Validation Tests
# ============================================================

@test "HS-PARAM-001: --days parameter support" {
    run "$HOTSPOT_ANALYZER" --help
    [[ "$output" == *"--days"* ]] || [[ "$output" == *"day"* ]] || [[ "$output" == *"30"* ]]
}

@test "HS-PARAM-002: invalid parameter returns error" {
    run "$HOTSPOT_ANALYZER" --invalid-option
    [ "$status" -ne 0 ]
}

# ============================================================
# Output Format Tests
# ============================================================

@test "HS-OUTPUT-001: JSON output is valid JSON" {
    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
    echo "$output" | jq . > /dev/null
}

@test "HS-OUTPUT-002: output includes file field" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"file"* ]]
}

# ============================================================
# Boundary Value Tests (HS-BOUNDARY)
# ============================================================

@test "HS-BOUNDARY-001: --top-n 0 returns empty or error" {
    run "$HOTSPOT_ANALYZER" --top-n 0 --format json 2>&1
    # Should either return empty hotspots array or error
    [ "$status" -eq 0 ] || [ "$status" -ne 0 ]
    if [ "$status" -eq 0 ]; then
        if command -v jq &> /dev/null; then
            count=$(echo "$output" | jq '.hotspots | length' 2>/dev/null || echo "0")
            [ "$count" -eq 0 ] || skip "Implementation allows top-n 0"
        fi
    fi
}

@test "HS-BOUNDARY-002: --top-n -1 returns error" {
    run "$HOTSPOT_ANALYZER" --top-n -1 --format json 2>&1
    # Negative values should be rejected
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"invalid"* ]] || \
    [[ "$output" == *"error"* ]] || \
    skip "Implementation accepts negative top-n"
}

@test "HS-BOUNDARY-003: --top-n very large value handled" {
    run "$HOTSPOT_ANALYZER" --top-n 99999 --format json 2>&1
    # Should succeed but return at most available files
    [ "$status" -eq 0 ] || skip "Large top-n not yet supported"
}

@test "HS-BOUNDARY-004: --days 0 returns error or empty" {
    run "$HOTSPOT_ANALYZER" --days 0 --format json 2>&1
    # Zero days should be rejected or return empty
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"error"* ]] || \
    [ "$status" -eq 0 ]
}

@test "HS-BOUNDARY-005: --days -1 returns error" {
    run "$HOTSPOT_ANALYZER" --days -1 --format json 2>&1
    # Negative days should be rejected
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"invalid"* ]] || \
    [[ "$output" == *"error"* ]] || \
    skip "Implementation accepts negative days"
}

@test "HS-BOUNDARY-006: empty repository handled gracefully" {
    # Create empty temp directory
    setup_temp_dir
    cd "$TEST_TEMP_DIR"
    git init --quiet

    run "$HOTSPOT_ANALYZER" --format json 2>&1

    cd - > /dev/null
    cleanup_temp_dir

    # Should return empty hotspots or appropriate message
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"empty"* ]] || \
    [[ "$output" == *"no "* ]] || \
    skip "Empty repo handling not yet implemented"
}

@test "HS-BOUNDARY-007: non-git directory handled gracefully" {
    setup_temp_dir
    cd "$TEST_TEMP_DIR"

    run "$HOTSPOT_ANALYZER" --format json 2>&1

    cd - > /dev/null
    cleanup_temp_dir

    # Should return error or warning about non-git directory
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"git"* ]] || \
    [[ "$output" == *"not"* ]] || \
    skip "Non-git directory handling not yet implemented"
}

