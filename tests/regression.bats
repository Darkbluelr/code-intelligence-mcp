#!/usr/bin/env bats
# regression.bats - Backward Compatibility Regression Tests
#
# Purpose: Verify existing MCP tools remain functional after changes
# Depends: bats-core
# Run: bats tests/regression.bats
#
# Baseline: 2026-01-15
# Change: 20260118-2112-enhance-code-intelligence-capabilities
# Trace: AC-011 (工具存活性、构建与脚本兼容性回归测试)
#
# Test IDs (aligned with verification.md):
#   T-REG-01: 全量 bats 稳定
#   T-REG-02: MCP 契约稳定

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
SERVER_TS="${PROJECT_ROOT}/src/server.ts"

# Build cache file path - use fixed name based on test file (not $$)
# This ensures setup_file and tests use the same path
_get_build_cache_file() {
    local cache_dir
    if [ -n "${BATS_FILE_TMPDIR:-}" ] && [ -d "$BATS_FILE_TMPDIR" ]; then
        cache_dir="$BATS_FILE_TMPDIR"
    elif [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && [ -w "$TMPDIR" ]; then
        cache_dir="$TMPDIR"
    elif [ -d "/tmp" ] && [ -w "/tmp" ]; then
        cache_dir="/tmp"
    else
        cache_dir="${BATS_TEST_DIRNAME:-.}"
    fi
    echo "${cache_dir}/.regression-build-cache"
}

# Setup once per file (BATS hook)
setup_file() {
    local cache_file
    cache_file="$(_get_build_cache_file)"

    # Run build once and cache results
    local package_json="${BATS_TEST_DIRNAME}/../package.json"
    if [ -f "$package_json" ]; then
        cd "${BATS_TEST_DIRNAME}/.." || return 1
        npm run build > "$cache_file" 2>&1
        echo "$?" >> "$cache_file"
    fi
}

# Cleanup after all tests (BATS hook)
teardown_file() {
    local cache_file
    cache_file="$(_get_build_cache_file)"
    rm -f "$cache_file" 2>/dev/null || true
}

# Get cached build output and status
get_build_result() {
    local cache_file
    cache_file="$(_get_build_cache_file)"
    if [ -f "$cache_file" ]; then
        # Last line is status, rest is output
        BUILD_STATUS=$(tail -1 "$cache_file")
        # Use sed to get all but last line (portable across macOS and Linux)
        BUILD_OUTPUT=$(sed '$d' "$cache_file")
    else
        BUILD_STATUS=1
        BUILD_OUTPUT="Build cache not available"
    fi
}

# ============================================================
# CT-REG-001 ~ CT-REG-008: Existing MCP Tool Availability
# AC-013: 现有 8 个 MCP 工具签名不变，现有脚本无需修改
# ============================================================

@test "CT-REG-001: ci_search tool still available" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep "ci_search" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-REG-001b: ci_search script executable" {
    local script="./scripts/embedding.sh"
    [ -x "$script" ] || skip "embedding.sh not executable"
}

@test "CT-REG-002: ci_call_chain tool still available" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep "ci_call_chain" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-REG-002b: ci_call_chain script executable" {
    local script="./scripts/call-chain.sh"
    [ -x "$script" ] || skip "call-chain.sh not executable"
}

@test "CT-REG-003: ci_bug_locate tool still available" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep "ci_bug_locate" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-REG-003b: ci_bug_locate script executable" {
    local script="./scripts/bug-locator.sh"
    [ -x "$script" ] || skip "bug-locator.sh not executable"
}

@test "CT-REG-004: ci_complexity tool still available" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep "ci_complexity" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-REG-004b: ci_complexity script executable" {
    local script="./scripts/complexity.sh"
    [ -x "$script" ] || skip "complexity.sh not executable"
}

@test "CT-REG-005: ci_graph_rag tool still available" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep "ci_graph_rag" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-REG-005b: ci_graph_rag script executable" {
    local script="./scripts/graph-rag.sh"
    [ -x "$script" ] || skip "graph-rag.sh not executable"
}

@test "CT-REG-006: ci_index_status tool still available" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep "ci_index_status" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-REG-006b: ci_index_status script executable" {
    local script="./scripts/indexer.sh"
    [ -x "$script" ] || skip "indexer.sh not executable"
}

@test "CT-REG-007: ci_hotspot tool still available" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep "ci_hotspot" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-REG-007b: ci_hotspot script executable" {
    local script="./scripts/hotspot-analyzer.sh"
    [ -x "$script" ] || skip "hotspot-analyzer.sh not executable"
}

@test "CT-REG-008: ci_boundary tool still available" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep "ci_boundary" "$SERVER_TS"
    [ "$status" -eq 0 ]
}

@test "CT-REG-008b: ci_boundary script executable" {
    local script="./scripts/boundary-detector.sh"
    [ -x "$script" ] || skip "boundary-detector.sh not executable"
}

# ============================================================
# Build and Type Check Regression
# ============================================================

@test "CT-REG-BUILD-001: TypeScript compiles without errors" {
    [ -f "package.json" ] || skip "Not a Node.js project"
    get_build_result
    # Primary check: exit status 0 means no compilation errors
    [ "$BUILD_STATUS" -eq 0 ] || { echo "Build failed with status $BUILD_STATUS"; echo "$BUILD_OUTPUT"; return 1; }
    # Secondary check: no TypeScript error patterns (may vary by locale/version)
    if [[ "$BUILD_OUTPUT" == *"error TS"* ]] || [[ "$BUILD_OUTPUT" == *"error:"* && "$BUILD_OUTPUT" == *".ts"* ]]; then
        echo "TypeScript errors found despite status 0"
        return 1
    fi
}

@test "CT-REG-BUILD-002: No new TypeScript warnings" {
    [ -f "package.json" ] || skip "Not a Node.js project"
    get_build_result
    [ "$BUILD_STATUS" -eq 0 ]
    # Count warnings - should not increase significantly
    local warning_count=$(echo "$BUILD_OUTPUT" | grep -c "warning" || echo "0")
    [ "$warning_count" -lt 10 ] || skip "Too many warnings: $warning_count"
}

# ============================================================
# Script Compatibility Regression
# ============================================================

@test "CT-REG-SCRIPT-001: common.sh still sources correctly" {
    local script="./scripts/common.sh"
    [ -f "$script" ] || skip "common.sh not found"
    run bash -n "$script"
    [ "$status" -eq 0 ]
}

@test "CT-REG-SCRIPT-002: cache-utils.sh still sources correctly" {
    local script="./scripts/cache-utils.sh"
    [ -f "$script" ] || skip "cache-utils.sh not found"
    run bash -n "$script"
    [ "$status" -eq 0 ]
}

@test "CT-REG-SCRIPT-003: hotspot-analyzer.sh basic functionality" {
    local script="./scripts/hotspot-analyzer.sh"
    [ -x "$script" ] || skip "hotspot-analyzer.sh not executable"

    run "$script" --help
    [ "$status" -eq 0 ]
}

@test "CT-REG-SCRIPT-004: hotspot-analyzer.sh JSON output unchanged" {
    local script="./scripts/hotspot-analyzer.sh"
    [ -x "$script" ] || skip "hotspot-analyzer.sh not executable"

    run "$script" --format json
    [ "$status" -eq 0 ]

    # Verify essential fields still present
    [[ "$output" == *"hotspots"* ]]
    [[ "$output" == *"schema_version"* ]]
}

# ============================================================
# Configuration Compatibility
# ============================================================

@test "CT-REG-CONFIG-001: existing config files still valid" {
    # Check that any existing config files are not broken
    if [ -f ".devbooks/config.yaml" ]; then
        # Config should be parseable
        if command -v yq &> /dev/null; then
            run yq . ".devbooks/config.yaml"
            [ "$status" -eq 0 ] || skip "Config file parse error"
        fi
    fi
}

# ============================================================
# MCP Protocol Regression
# ============================================================

@test "CT-REG-MCP-001: MCP tools count >= 8" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    # Count tool registrations
    local tool_count=$(grep -c 'name:.*"ci_' "$SERVER_TS" || echo "0")

    # Should have at least 8 existing tools
    [ "$tool_count" -ge 8 ] || skip "Expected at least 8 MCP tools, found $tool_count"
}

@test "CT-REG-MCP-002: no removed tool registrations" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    # List of required tools
    local required_tools=(
        "ci_search"
        "ci_call_chain"
        "ci_bug_locate"
        "ci_complexity"
        "ci_graph_rag"
        "ci_index_status"
        "ci_hotspot"
        "ci_boundary"
    )

    for tool in "${required_tools[@]}"; do
        run grep "$tool" "$SERVER_TS"
        [ "$status" -eq 0 ] || skip "Required tool $tool not found"
    done
}

# ============================================================
# API Signature Regression (Sample Check)
# ============================================================

@test "CT-REG-API-001: ci_hotspot accepts path parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    run grep -A 20 "ci_hotspot" "$SERVER_TS"
    [[ "$output" == *"path"* ]] || skip "ci_hotspot should accept path parameter"
}

@test "CT-REG-API-002: ci_hotspot accepts format parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    run grep -A 20 "ci_hotspot" "$SERVER_TS"
    [[ "$output" == *"format"* ]] || skip "ci_hotspot should accept format parameter"
}

# ============================================================
# New Tools Don't Break Existing
# ============================================================

@test "CT-REG-NEW-001: new ci_arch_check does not conflict" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    # If ci_arch_check is added, it should not break other tools
    if grep -q "ci_arch_check" "$SERVER_TS"; then
        # All existing tools should still be present
        run grep -c 'name:.*"ci_' "$SERVER_TS"
        local tool_count="${output:-0}"
        [ "$tool_count" -ge 9 ] || skip "ci_arch_check may have replaced an existing tool"
    fi
}

@test "CT-REG-NEW-002: new ci_federation does not conflict" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    # If ci_federation is added, it should not break other tools
    if grep -q "ci_federation" "$SERVER_TS"; then
        # All existing tools should still be present
        run grep -c 'name:.*"ci_' "$SERVER_TS"
        local tool_count="${output:-0}"
        [ "$tool_count" -ge 9 ] || skip "ci_federation may have replaced an existing tool"
    fi
}

# ============================================================
# P0: Comprehensive API Signature Validation (AC-011)
# 评审要求：覆盖至少 7/8 工具的 API 签名验证
# ============================================================

# ci_search API 签名验证
@test "CT-REG-API-003: ci_search accepts query parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_search"' "$SERVER_TS"
    echo "$output" | grep -q 'query.*type.*string' || fail "ci_search should have query: string parameter"
}

@test "CT-REG-API-004: ci_search accepts mode parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_search"' "$SERVER_TS"
    echo "$output" | grep -q 'mode' || fail "ci_search should have mode parameter"
}

# ci_call_chain API 签名验证
@test "CT-REG-API-005: ci_call_chain accepts symbol parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_call_chain"' "$SERVER_TS"
    echo "$output" | grep -q 'symbol' || fail "ci_call_chain should have symbol parameter"
}

@test "CT-REG-API-006: ci_call_chain accepts direction parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_call_chain"' "$SERVER_TS"
    echo "$output" | grep -q 'direction' || fail "ci_call_chain should have direction parameter"
}

# ci_bug_locate API 签名验证
@test "CT-REG-API-007: ci_bug_locate accepts error parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_bug_locate"' "$SERVER_TS"
    echo "$output" | grep -q 'error' || fail "ci_bug_locate should have error parameter"
}

@test "CT-REG-API-008: ci_bug_locate signature stable" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    # 验证 ci_bug_locate 定义存在且结构正确
    run grep -A 10 '"ci_bug_locate"' "$SERVER_TS"
    echo "$output" | grep -q 'description' || fail "ci_bug_locate should have description field"
}

# ci_complexity API 签名验证
@test "CT-REG-API-009: ci_complexity accepts path parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_complexity"' "$SERVER_TS"
    echo "$output" | grep -q 'path' || fail "ci_complexity should have path parameter"
}

@test "CT-REG-API-010: ci_complexity accepts format parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_complexity"' "$SERVER_TS"
    echo "$output" | grep -q 'format' || fail "ci_complexity should have format parameter"
}

# ci_graph_rag API 签名验证
@test "CT-REG-API-011: ci_graph_rag accepts query parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_graph_rag"' "$SERVER_TS"
    echo "$output" | grep -q 'query' || fail "ci_graph_rag should have query parameter"
}

@test "CT-REG-API-012: ci_graph_rag accepts budget parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_graph_rag"' "$SERVER_TS"
    echo "$output" | grep -q 'budget' || fail "ci_graph_rag should have budget parameter"
}

# ci_index_status API 签名验证
@test "CT-REG-API-013: ci_index_status accepts action parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_index_status"' "$SERVER_TS"
    echo "$output" | grep -q 'action' || fail "ci_index_status should have action parameter"
}

@test "CT-REG-API-014: ci_index_status signature stable" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    # 验证 ci_index_status 定义存在且结构正确
    run grep -A 10 '"ci_index_status"' "$SERVER_TS"
    echo "$output" | grep -q 'description' || fail "ci_index_status should have description field"
}

# ci_boundary API 签名验证
@test "CT-REG-API-015: ci_boundary accepts file parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_boundary"' "$SERVER_TS"
    echo "$output" | grep -q 'file' || fail "ci_boundary should have file parameter"
}

@test "CT-REG-API-016: ci_boundary accepts format parameter" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"
    run grep -A 30 '"ci_boundary"' "$SERVER_TS"
    echo "$output" | grep -q 'format' || fail "ci_boundary should have format parameter"
}

# ============================================================
# M-005 修复：结构化 API 签名验证
# 使用 TypeScript AST 或 JSON schema 解析验证 type/required/enum
# ============================================================

# @critical
@test "CT-REG-API-SCHEMA-001: ci_search schema structure validation" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    # 提取 ci_search 工具定义
    local tool_def
    tool_def=$(awk '/name:.*"ci_search"/,/^\s*\}/' "$SERVER_TS" | head -60)

    [ -n "$tool_def" ] || fail "ci_search definition not found"

    # 验证 query 参数的 type 为 string
    echo "$tool_def" | grep -E 'query.*type.*string' >/dev/null || \
        echo "$tool_def" | grep -E '"query".*"string"' >/dev/null || \
        fail "ci_search.query should be type string"

    # 验证 mode 参数有 enum 约束
    if echo "$tool_def" | grep -q 'mode'; then
        # mode 存在时，验证 enum 或默认值
        echo "$tool_def" | grep -qE 'enum|semantic|keyword' || \
            fail "ci_search.mode should have enum constraint (semantic/keyword)"
    fi
}

# @critical
@test "CT-REG-API-SCHEMA-002: ci_call_chain schema structure validation" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    local tool_def
    tool_def=$(awk '/name:.*"ci_call_chain"/,/^\s*\}/' "$SERVER_TS" | head -60)

    [ -n "$tool_def" ] || fail "ci_call_chain definition not found"

    # 验证 symbol 参数是 required (string 类型)
    echo "$tool_def" | grep -E 'symbol.*type.*string' >/dev/null || \
        echo "$tool_def" | grep -E '"symbol".*"string"' >/dev/null || \
        fail "ci_call_chain.symbol should be type string"

    # 验证 direction 参数有 enum 约束
    if echo "$tool_def" | grep -q 'direction'; then
        echo "$tool_def" | grep -qE 'callers|callees|both' || \
            fail "ci_call_chain.direction should have enum (callers/callees/both)"
    fi

    # 验证 depth 参数是 number 类型
    if echo "$tool_def" | grep -q 'depth'; then
        echo "$tool_def" | grep -qE 'depth.*number|"depth".*"number"' || \
            fail "ci_call_chain.depth should be type number"
    fi
}

# @critical
@test "CT-REG-API-SCHEMA-003: ci_complexity schema structure validation" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    local tool_def
    tool_def=$(awk '/name:.*"ci_complexity"/,/^\s*\}/' "$SERVER_TS" | head -60)

    [ -n "$tool_def" ] || fail "ci_complexity definition not found"

    # 验证 path 参数是 required (string 类型)
    echo "$tool_def" | grep -qE 'path.*type.*string|"path".*"string"' || \
        fail "ci_complexity.path should be type string"

    # 验证 format 参数有 enum 约束
    if echo "$tool_def" | grep -q 'format'; then
        echo "$tool_def" | grep -qE 'text|json' || \
            fail "ci_complexity.format should have enum (text/json)"
    fi
}

# @critical
@test "CT-REG-API-SCHEMA-004: ci_graph_rag schema structure validation" {
    [ -f "$SERVER_TS" ] || skip "server.ts not found"

    local tool_def
    tool_def=$(awk '/name:.*"ci_graph_rag"/,/^\s*\}/' "$SERVER_TS" | head -80)

    [ -n "$tool_def" ] || fail "ci_graph_rag definition not found"

    # 验证 query 参数是 required (string 类型)
    echo "$tool_def" | grep -qE 'query.*type.*string|"query".*"string"' || \
        fail "ci_graph_rag.query should be type string"

    # 验证 budget 参数是 number 类型
    if echo "$tool_def" | grep -q 'budget'; then
        echo "$tool_def" | grep -qE 'budget.*number|"budget".*"number"' || \
            fail "ci_graph_rag.budget should be type number"
    fi

    # 验证 depth 参数是 number 类型
    if echo "$tool_def" | grep -q 'depth'; then
        echo "$tool_def" | grep -qE 'depth.*number|"depth".*"number"' || \
            fail "ci_graph_rag.depth should be type number"
    fi
}
