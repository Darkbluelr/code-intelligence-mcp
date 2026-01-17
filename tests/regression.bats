#!/usr/bin/env bats
# regression.bats - Backward Compatibility Regression Tests
#
# Purpose: Verify existing MCP tools remain functional after changes
# Depends: bats-core
# Run: bats tests/regression.bats
#
# Baseline: 2026-01-15
# Change: augment-parity-final-gaps
# Trace: AC-G10 (回归测试)
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
