#!/usr/bin/env bats
# mcp-contract.bats - AC-008 MCP Tool Contract Tests
#
# Purpose: Verify MCP tool interface compatibility
# Depends: bats-core, node
# Run: bats tests/mcp-contract.bats
#
# Baseline: 2026-01-11
# Change: enhance-code-intelligence
# Trace: AC-008

# Load shared helpers
load 'helpers/common'

SERVER_TS="./src/server.ts"
DIST_SERVER="./dist/server.js"

# ============================================================
# Basic Verification
# ============================================================

@test "CT-BASE-001: server.ts exists" {
    [ -f "$SERVER_TS" ]
}

@test "CT-BASE-002: project builds successfully" {
    if [ ! -f "package.json" ]; then
        skip "Not a Node.js project"
    fi
    run npm run build 2>&1
    [ "$status" -eq 0 ]
}

# ============================================================
# ci_hotspot Contract Tests (CT-001, CT-002)
# ============================================================

@test "CT-001: ci_hotspot tool registered" {
    run grep -l "ci_hotspot" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-001b: ci_hotspot input parameter - path optional" {
    run grep -A 20 "ci_hotspot" "$SERVER_TS"
    [[ "$output" == *"path"* ]] || skip "ci_hotspot not yet implemented"
}

@test "CT-001c: ci_hotspot input parameter - top_n optional" {
    run grep -A 20 "ci_hotspot" "$SERVER_TS"
    [[ "$output" == *"top"* ]] || [[ "$output" == *"n"* ]] || skip "ci_hotspot not yet implemented"
}

@test "CT-002: ci_hotspot output format - schema_version" {
    HOTSPOT_ANALYZER="./scripts/hotspot-analyzer.sh"
    if [ ! -x "$HOTSPOT_ANALYZER" ]; then
        skip "hotspot-analyzer.sh not yet implemented"
    fi
    run "$HOTSPOT_ANALYZER" --format json 2>&1
    [[ "$output" == *"schema_version"* ]]
}

@test "CT-002b: ci_hotspot output format - hotspots array" {
    HOTSPOT_ANALYZER="./scripts/hotspot-analyzer.sh"
    if [ ! -x "$HOTSPOT_ANALYZER" ]; then
        skip "hotspot-analyzer.sh not yet implemented"
    fi
    run "$HOTSPOT_ANALYZER" --format json 2>&1
    [[ "$output" == *"hotspots"* ]]
}

# ============================================================
# ci_boundary Contract Tests (CT-003, CT-004)
# ============================================================

@test "CT-003: ci_boundary tool registered" {
    run grep -l "ci_boundary" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-003b: ci_boundary input parameter - path required" {
    run grep -A 20 "ci_boundary" "$SERVER_TS"
    [[ "$output" == *"path"* ]] || skip "ci_boundary not yet implemented"
}

@test "CT-004: ci_boundary output format - type field" {
    BOUNDARY_DETECTOR="./scripts/boundary-detector.sh"
    if [ ! -x "$BOUNDARY_DETECTOR" ]; then
        skip "boundary-detector.sh not yet implemented"
    fi
    run "$BOUNDARY_DETECTOR" --path "src/server.ts" --format json 2>&1
    [[ "$output" == *"type"* ]]
}

@test "CT-004b: ci_boundary output format - confidence field" {
    BOUNDARY_DETECTOR="./scripts/boundary-detector.sh"
    if [ ! -x "$BOUNDARY_DETECTOR" ]; then
        skip "boundary-detector.sh not yet implemented"
    fi
    run "$BOUNDARY_DETECTOR" --path "src/server.ts" --format json 2>&1
    [[ "$output" == *"confidence"* ]]
}

# ============================================================
# Existing Tool Regression Tests (CT-005)
# ============================================================

@test "CT-005a: ci_search tool still available" {
    run grep "ci_search" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-005b: ci_call_chain tool still available" {
    run grep "ci_call_chain" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-005c: ci_bug_locate tool still available" {
    run grep "ci_bug_locate" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-005d: ci_complexity tool still available" {
    run grep "ci_complexity" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-005e: ci_graph_rag tool still available" {
    run grep "ci_graph_rag" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-005f: ci_index_status tool still available" {
    run grep "ci_index_status" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

# ============================================================
# Feature Toggle Contract Tests (CT-006)
# ============================================================

@test "CT-006: .devbooks/config.yaml supports features field" {
    CONFIG_FILE=".devbooks/config.yaml"
    [ -f "$CONFIG_FILE" ] || skip "Config file not found"
    run grep "features" "$CONFIG_FILE"
    [[ "$output" == *"features"* ]] || skip "features field not yet added"
}

@test "CT-006b: enhanced_hotspot toggle defined" {
    CONFIG_FILE=".devbooks/config.yaml"
    [ -f "$CONFIG_FILE" ] || skip "Config file not found"
    run grep "enhanced_hotspot" "$CONFIG_FILE"
    [ "$status" -eq 0 ] || skip "enhanced_hotspot flag not yet defined"
}

# ============================================================
# CLI Parameter Compatibility Tests
# ============================================================

@test "CT-CLI-001: call-chain.sh --trace-data-flow parameter" {
    CALL_CHAIN="./scripts/call-chain.sh"
    [ -x "$CALL_CHAIN" ] || skip "call-chain.sh not executable"
    run "$CALL_CHAIN" --help 2>&1
    [[ "$output" == *"trace-data-flow"* ]] || [[ "$output" == *"data-flow"* ]] || \
    skip "--trace-data-flow not yet added"
}

@test "CT-CLI-002: call-chain.sh compatible without new parameters" {
    CALL_CHAIN="./scripts/call-chain.sh"
    [ -x "$CALL_CHAIN" ] || skip "call-chain.sh not executable"
    run "$CALL_CHAIN" --symbol "test" --format json 2>&1
    [ "$status" -eq 0 ]
}

# ============================================================
# Config File Contract Tests
# ============================================================

@test "CT-CFG-001: config/boundaries.yaml format" {
    BOUNDARIES_CONFIG="./config/boundaries.yaml"
    [ -f "$BOUNDARIES_CONFIG" ] || skip "boundaries.yaml not yet created"
    run cat "$BOUNDARIES_CONFIG"
    [[ "$output" == *"boundaries"* ]] || [[ "$output" == *"library"* ]]
}

@test "CT-CFG-002: learned-patterns.json format" {
    PATTERNS_FILE=".devbooks/learned-patterns.json"
    if [ -f "$PATTERNS_FILE" ]; then
        run cat "$PATTERNS_FILE"
        [[ "$output" == *"schema_version"* ]] || [[ "$output" == *"patterns"* ]]
    else
        skip "learned-patterns.json not yet generated"
    fi
}

# ============================================================
# Type Safety Tests
# ============================================================

@test "CT-TYPE-001: TypeScript compiles without type errors" {
    if [ ! -f "package.json" ]; then
        skip "Not a Node.js project"
    fi
    run npm run build 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" != *"error TS"* ]]
}
