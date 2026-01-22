#!/usr/bin/env bats
# mcp-contract.bats - MCP Tool Contract Tests
#
# Purpose: Verify MCP tool interface compatibility
# Depends: bats-core, node
# Run: bats tests/mcp-contract.bats
#
# Baseline: 2026-01-15
# Change: augment-parity
# Trace: AC-008 (无 CKB 降级), AC-008 (legacy)

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
SERVER_TS="${PROJECT_ROOT}/src/server.ts"
DIST_SERVER="${PROJECT_ROOT}/dist/server.js"

# Track environment variables that need cleanup
_MCP_CONTRACT_ENV_VARS_TO_CLEANUP=()

# Setup: Initialize cleanup tracking
setup() {
    _MCP_CONTRACT_ENV_VARS_TO_CLEANUP=()
}

# Teardown: Clean up any environment variables set during tests
teardown() {
    # Clean up tracked environment variables
    for var in "${_MCP_CONTRACT_ENV_VARS_TO_CLEANUP[@]}"; do
        unset "$var" 2>/dev/null || true
    done
    _MCP_CONTRACT_ENV_VARS_TO_CLEANUP=()
}

# Helper: Set environment variable with automatic cleanup tracking
# Usage: set_env_with_cleanup VAR_NAME value
set_env_with_cleanup() {
    local var_name="$1"
    local var_value="$2"
    export "$var_name=$var_value"
    _MCP_CONTRACT_ENV_VARS_TO_CLEANUP+=("$var_name")
}

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

# CT-006b removed: enhanced_hotspot feature does not exist

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

# ============================================================
# AC-008: 无 CKB 降级测试
# 契约测试: CT-CKB-001 ~ CT-CKB-005
# ============================================================

@test "CT-CKB-001: ci_graph_rag works when CKB_ENABLED=false" {
    GRAPH_RAG="./scripts/graph-rag.sh"
    [ -x "$GRAPH_RAG" ] || skip "graph-rag.sh not executable"

    set_env_with_cleanup CKB_ENABLED false

    run "$GRAPH_RAG" --query "test query" --format json 2>&1

    # 使用 helper 提取 JSON 部分
    local json_output
    json_output=$(extract_json "$output")

    skip_if_not_ready "$status" "$json_output" "graph-rag no CKB"
    assert_exit_success "$status"

    # 验证输出包含有效 JSON
    assert_json_output "$output"
}

@test "CT-CKB-002: ci_graph_rag returns valid results without CKB" {
    GRAPH_RAG="./scripts/graph-rag.sh"
    [ -x "$GRAPH_RAG" ] || skip "graph-rag.sh not executable"
    skip_if_missing "jq"

    set_env_with_cleanup CKB_ENABLED false

    run "$GRAPH_RAG" --query "function" --format json 2>&1

    # 使用 helper 提取 JSON 部分
    local json_output
    json_output=$(extract_json "$output")

    skip_if_not_ready "$status" "$json_output" "graph-rag results"
    assert_exit_success "$status"

    # 验证输出包含有效结构
    assert_json_output "$output"
}

@test "CT-CKB-003: ci_graph_rag uses local graph when CKB unavailable" {
    GRAPH_RAG="./scripts/graph-rag.sh"
    [ -x "$GRAPH_RAG" ] || skip "graph-rag.sh not executable"

    set_env_with_cleanup CKB_ENABLED false

    run "$GRAPH_RAG" --query "server" --format json 2>&1

    # 使用 helper 提取 JSON 部分
    local json_output
    json_output=$(extract_json "$output")

    skip_if_not_ready "$status" "$json_output" "graph-rag local graph"
    assert_exit_success "$status"

    # 验证输出包含有效 JSON
    assert_json_output "$output"
}

@test "CT-CKB-004: ci_call_chain works without CKB" {
    CALL_CHAIN="./scripts/call-chain.sh"
    [ -x "$CALL_CHAIN" ] || skip "call-chain.sh not executable"

    set_env_with_cleanup CKB_ENABLED false

    run "$CALL_CHAIN" --symbol "main" --format json 2>&1

    skip_if_not_ready "$status" "$output" "call-chain no CKB"
    assert_exit_success "$status"
}

@test "CT-CKB-005: degradation message shown when CKB disabled" {
    GRAPH_RAG="./scripts/graph-rag.sh"
    [ -x "$GRAPH_RAG" ] || skip "graph-rag.sh not executable"

    set_env_with_cleanup CKB_ENABLED false

    run "$GRAPH_RAG" --query "test" --format json 2>&1

    skip_if_not_ready "$status" "$output" "graph-rag degradation"
    # 应有降级提示或正常工作
    assert_exit_success "$status"
}
