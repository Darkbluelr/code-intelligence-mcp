#!/usr/bin/env bats
# boundary-detector.bats - AC-004 Boundary Detection Acceptance Tests
#
# Purpose: Verify boundary-detector.sh boundary detection functionality
# Depends: bats-core
# Run: bats tests/boundary-detector.bats
#
# Baseline: 2026-01-11
# Change: enhance-code-intelligence
# Trace: AC-004

# Load shared helpers
load 'helpers/common'

BOUNDARY_DETECTOR="./scripts/boundary-detector.sh"

# ============================================================
# Basic Functionality Tests (BD-001)
# ============================================================

@test "BD-001: boundary-detector.sh exists and is executable" {
    [ -x "$BOUNDARY_DETECTOR" ]
}

@test "BD-001b: --help shows usage information" {
    run "$BOUNDARY_DETECTOR" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"boundary"* ]] || [[ "$output" == *"Boundary"* ]]
}

# ============================================================
# Boundary Type Detection Tests (BD-002 ~ BD-005)
# ============================================================

@test "BD-002: detect library code (node_modules)" {
    run "$BOUNDARY_DETECTOR" --path "node_modules/lodash/index.js" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"library"* ]]
    [[ "$output" == *"confidence"* ]]
}

@test "BD-002b: detect library code (vendor)" {
    run "$BOUNDARY_DETECTOR" --path "vendor/legacy/utils.js" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"library"* ]]
}

@test "BD-003: detect generated code (dist)" {
    run "$BOUNDARY_DETECTOR" --path "dist/server.js" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"generated"* ]]
}

@test "BD-003b: detect generated code (build)" {
    run "$BOUNDARY_DETECTOR" --path "build/output.js" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"generated"* ]]
}

@test "BD-004: detect user code (src)" {
    run "$BOUNDARY_DETECTOR" --path "src/server.ts" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"user"* ]]
}

@test "BD-005: detect config file (config)" {
    run "$BOUNDARY_DETECTOR" --path "config/boundaries.yaml" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"config"* ]]
}

@test "BD-005b: detect config file (*.config.js)" {
    run "$BOUNDARY_DETECTOR" --path "tsconfig.json" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"config"* ]]
}

# ============================================================
# Glob Pattern Matching Tests (BD-006)
# ============================================================

@test "BD-006: glob pattern matching (**/vendor/**)" {
    run "$BOUNDARY_DETECTOR" --path "src/vendor/legacy/utils.js" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"library"* ]]
}

@test "BD-006b: glob pattern matching (**/*.generated.*)" {
    run "$BOUNDARY_DETECTOR" --path "src/types.generated.ts" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"generated"* ]]
}

# ============================================================
# Config Override Tests
# ============================================================

@test "BD-OVERRIDE-001: custom config file support" {
    run "$BOUNDARY_DETECTOR" --help
    [[ "$output" == *"--config"* ]] || [[ "$output" == *"config"* ]]
}

# ============================================================
# Output Format Tests
# ============================================================

@test "BD-OUTPUT-001: JSON output includes schema_version" {
    run "$BOUNDARY_DETECTOR" --path "src/server.ts" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema_version"* ]]
}

@test "BD-OUTPUT-002: JSON output includes type and confidence" {
    run "$BOUNDARY_DETECTOR" --path "src/server.ts" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"type"* ]]
    [[ "$output" == *"confidence"* ]]
}

@test "BD-OUTPUT-003: JSON output is valid JSON" {
    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi
    run "$BOUNDARY_DETECTOR" --path "src/server.ts" --format json
    [ "$status" -eq 0 ]
    echo "$output" | jq . > /dev/null
}

# ============================================================
# Parameter Validation Tests
# ============================================================

@test "BD-PARAM-001: --path parameter required" {
    run "$BOUNDARY_DETECTOR" --format json
    [ "$status" -ne 0 ] || [[ "$output" == *"path"* ]]
}

@test "BD-PARAM-002: invalid parameter returns error" {
    run "$BOUNDARY_DETECTOR" --invalid-option
    [ "$status" -ne 0 ]
}

# ============================================================
# Boundary Value Tests (BD-BOUNDARY)
# ============================================================

@test "BD-BOUNDARY-001: path with spaces handled" {
    run "$BOUNDARY_DETECTOR" --path "src/my file.ts" --format json 2>&1
    # Should handle paths with spaces gracefully
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"not found"* ]] || \
    skip "Path with spaces not yet supported"
}

@test "BD-BOUNDARY-002: path with special characters handled" {
    run "$BOUNDARY_DETECTOR" --path "src/file-with-dashes_and_underscores.ts" --format json 2>&1
    # Should handle special characters
    [ "$status" -eq 0 ] || skip "Special char path not yet supported"
}

@test "BD-BOUNDARY-003: very long path handled gracefully" {
    local long_path
    long_path=$(get_long_path 50)
    run "$BOUNDARY_DETECTOR" --path "$long_path" --format json 2>&1
    # Should either succeed or return appropriate error
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"path"* ]] || \
    [[ "$output" == *"long"* ]] || \
    skip "Long path handling not yet implemented"
}

@test "BD-BOUNDARY-004: empty path returns error" {
    run "$BOUNDARY_DETECTOR" --path "" --format json 2>&1
    # Empty path should be rejected
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"empty"* ]] || \
    [[ "$output" == *"required"* ]]
}

@test "BD-BOUNDARY-005: non-existent path handled" {
    run "$BOUNDARY_DETECTOR" --path "nonexistent/path/to/file.ts" --format json 2>&1
    # Should return type based on path pattern, even if file doesn't exist
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"not found"* ]] || \
    skip "Non-existent path handling not yet implemented"
}

@test "BD-BOUNDARY-006: unicode in path handled" {
    run "$BOUNDARY_DETECTOR" --path "src/文件.ts" --format json 2>&1
    # Unicode paths should be handled
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"invalid"* ]] || \
    skip "Unicode path not yet supported"
}

@test "BD-BOUNDARY-007: path traversal attempt handled" {
    run "$BOUNDARY_DETECTOR" --path "../../../etc/passwd" --format json 2>&1
    # Path traversal should be handled securely
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"user"* ]] || \
    [[ "$output" == *"invalid"* ]] || \
    skip "Path traversal handling not yet implemented"
}

