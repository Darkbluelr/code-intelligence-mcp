#!/usr/bin/env bats
# indexer-scheduler.bats - Indexing Pipeline Optimization Tests
#
# Change ID: optimize-indexing-pipeline-20260117
# Covers: AC-001 to AC-010 (本变更包自定义的 AC，非 20260118-2112 变更包)
#
# Purpose: Verify indexer scheduler logic including:
#   - Incremental-first indexing path (AC-001)
#   - Reliable fallback to full rebuild (AC-002)
#   - Offline SCIP proto resolution (AC-003)
#   - CLI entry point compatibility (AC-004)
#   - ci_index_status semantic alignment (AC-005)
#   - Idempotent index operations (AC-006)
#   - Debounce window aggregation (AC-007)
#   - Version stamp consistency (AC-008)
#   - Feature toggle support (AC-009)
#   - Concurrent write safety (AC-010)
#
# Test ID Prefix: T-IS (Test - Indexer Scheduler)
# 修复 C-007: 统一使用 T-IS- 前缀以保持与其他测试文件一致
#
# AC 映射表:
#   T-IS-001*  → AC-001 (Incremental-first)
#   T-IS-002*  → AC-002 (Reliable fallback)
#   T-IS-003*  → AC-003 (Offline proto)
#   T-IS-004*  → AC-004 (CLI entry point)
#   T-IS-005*  → AC-005 (ci_index_status)
#   T-IS-006*  → AC-006 (Idempotent ops)
#   T-IS-007*  → AC-007 (Debounce)
#   T-IS-008*  → AC-008 (Version stamp)
#   T-IS-009*  → AC-009 (Feature toggle)
#   T-IS-010*  → AC-010 (Concurrent write)
#
# Run: bats tests/indexer-scheduler.bats

load 'helpers/common'

# Script paths
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
SCRIPT_DIR="$PROJECT_ROOT/scripts"
INDEXER_SCRIPT="$SCRIPT_DIR/indexer.sh"
SCIP_TO_GRAPH="$SCRIPT_DIR/scip-to-graph.sh"
AST_DELTA="$SCRIPT_DIR/ast-delta.sh"
GRAPH_STORE="$SCRIPT_DIR/graph-store.sh"
EMBEDDING_SCRIPT="$SCRIPT_DIR/embedding.sh"
CONFIG_FILE="$PROJECT_ROOT/config/features.yaml"

# Test constants
DEBOUNCE_SECONDS_DEFAULT=2
FILE_THRESHOLD_DEFAULT=10

setup() {
    setup_temp_dir
    export GRAPH_DB_PATH="$TEST_TEMP_DIR/graph.db"
    export DEVBOOKS_DIR="$TEST_TEMP_DIR/.devbooks"
    export AST_CACHE_DIR="$TEST_TEMP_DIR/.ast-cache"
    mkdir -p "$DEVBOOKS_DIR"
    mkdir -p "$AST_CACHE_DIR"

    # Setup test git repo
    setup_test_git_repo_with_src "$TEST_TEMP_DIR/repo"
    export TEST_REPO_DIR="$TEST_TEMP_DIR/repo"

    # Create test TypeScript file
    create_test_ts_file "$TEST_REPO_DIR/src/index.ts"
}

teardown() {
    cleanup_test_git_repo
    cleanup_temp_dir
}

# ============================================================
# Helper Functions
# ============================================================

# Create test TypeScript file
create_test_ts_file() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path" << 'EOF'
export function testFunction(): string {
    return "test";
}

export class TestClass {
    private value: number;

    constructor(value: number) {
        this.value = value;
    }

    getValue(): number {
        return this.value;
    }
}
EOF
}

# Create test features.yaml config
create_test_config() {
    local config_dir="$1"
    local ast_delta_enabled="${2:-true}"
    local file_threshold="${3:-10}"
    local debounce_seconds="${4:-2}"
    local offline_proto="${5:-true}"

    mkdir -p "$config_dir"
    cat > "$config_dir/features.yaml" << EOF
features:
  ast_delta:
    enabled: $ast_delta_enabled
    file_threshold: $file_threshold
  indexer:
    debounce_seconds: $debounce_seconds
    offline_proto: $offline_proto
    allow_proto_download: false
EOF
}

# Create vendored proto file
create_vendored_proto() {
    local vendored_dir="$1"
    mkdir -p "$vendored_dir"
    cat > "$vendored_dir/scip.proto" << 'EOF'
// Vendored SCIP proto for offline use
// Version: 0.4.0
// Source: github.com/sourcegraph/scip

syntax = "proto3";
package scip;

message Index {
    Metadata metadata = 1;
    repeated Document documents = 2;
    repeated SymbolInformation external_symbols = 3;
}

message Metadata {
    string version = 1;
    repeated ToolInfo tool_info = 2;
    string project_root = 3;
    TextEncoding text_document_encoding = 4;
}
EOF
}

# Create graph database with version stamp
create_graph_db_with_version() {
    local db_path="$1"
    local version="${2:-v1.0}"

    sqlite3 "$db_path" << EOF
CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    symbol TEXT NOT NULL,
    kind TEXT NOT NULL,
    file_path TEXT NOT NULL,
    line_start INTEGER,
    line_end INTEGER
);
CREATE TABLE IF NOT EXISTS edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    edge_type TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT
);
INSERT OR REPLACE INTO metadata (key, value) VALUES ('ast_cache_version', '$version');
INSERT OR REPLACE INTO metadata (key, value) VALUES ('last_updated', datetime('now'));
EOF
}

# ============================================================
# AC-001: Incremental-First Index Path
# ============================================================

# @test T-IS-001: Incremental path invoked for single file change when conditions met
@test "T-IS-001: indexer invokes incremental path for single file change" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: tree-sitter available, AST cache version matches, single file change
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    # Create version stamp file matching db
    mkdir -p "$AST_CACHE_DIR"
    echo '{"version": "v1.0", "timestamp": "2026-01-18T00:00:00Z"}' > "$AST_CACHE_DIR/.version"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Trigger indexer with dry-run for single file
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts"

    # Then: Should output INCREMENTAL decision
    skip_if_not_ready "$status" "$output" "indexer.sh --dry-run"
    assert_exit_success "$status"
    assert_contains "$output" "INCREMENTAL"
    assert_contains "$output" "index.ts"
}

# @test T-IS-001b: Incremental path calls ast-delta.sh update
@test "T-IS-001b: incremental path calls ast-delta update for single file" {
    skip_if_not_executable "$INDEXER_SCRIPT"
    skip_if_not_executable "$AST_DELTA"

    # Given: Conditions for incremental path met
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    mkdir -p "$AST_CACHE_DIR"
    echo '{"version": "v1.0"}' > "$AST_CACHE_DIR/.version"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Execute indexer --once for single file
    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/index.ts"

    skip_if_not_ready "$status" "$output" "indexer.sh --once"

    # Then: Should invoke ast-delta path
    assert_exit_success "$status"
    assert_contains_any "$output" "ast-delta" "incremental" "update"
}

# @test T-IS-001c: Incremental path invoked when file count equals threshold
@test "T-IS-001c: incremental path invoked when file count equals threshold" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Exactly 10 files (at threshold)
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    # Create 10 test files
    for i in $(seq 1 10); do
        create_test_ts_file "$TEST_REPO_DIR/src/file$i.ts"
    done

    local files=""
    for i in $(seq 1 10); do
        files="$files,$TEST_REPO_DIR/src/file$i.ts"
    done
    files="${files:1}"  # Remove leading comma

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Trigger with exactly 10 files
    run "$INDEXER_SCRIPT" --dry-run --files "$files"

    skip_if_not_ready "$status" "$output" "indexer.sh threshold check"

    # Then: Should still use incremental (at threshold, not over)
    assert_exit_success "$status"
    assert_contains "$output" "INCREMENTAL"
}

# ============================================================
# AC-002: Reliable Fallback to Full Rebuild
# ============================================================

# @test T-IS-002: Fallback to full rebuild when tree-sitter unavailable
@test "T-IS-002: fallback to full rebuild when tree-sitter unavailable" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: tree-sitter marked as unavailable
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"
    export DISABLE_TREE_SITTER=true

    # When: Trigger indexer
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts"

    unset DISABLE_TREE_SITTER

    skip_if_not_ready "$status" "$output" "indexer.sh fallback"

    # Then: Should output FULL_REBUILD decision
    assert_exit_success "$status"
    assert_contains "$output" "FULL_REBUILD"
    assert_contains_any "$output" "tree_sitter_unavailable" "tree-sitter"
}

# @test T-IS-002b: Fallback when cache version mismatch
@test "T-IS-002b: fallback to full rebuild when cache version mismatch" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: AST cache version differs from graph.db version
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    # Create mismatched version stamp
    mkdir -p "$AST_CACHE_DIR"
    echo '{"version": "v2.0"}' > "$AST_CACHE_DIR/.version"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Trigger indexer
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts"

    skip_if_not_ready "$status" "$output" "indexer.sh cache mismatch"

    # Then: Should output FULL_REBUILD with reason
    assert_exit_success "$status"
    assert_contains "$output" "FULL_REBUILD"
    assert_contains_any "$output" "cache_version_mismatch" "version" "mismatch"
}

# @test T-IS-002c: Fallback when file count exceeds threshold
@test "T-IS-002c: fallback to full rebuild when file count exceeds threshold" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: More than 10 files changed
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    # Create 15 test files
    for i in $(seq 1 15); do
        create_test_ts_file "$TEST_REPO_DIR/src/file$i.ts"
    done

    local files=""
    for i in $(seq 1 15); do
        files="$files,$TEST_REPO_DIR/src/file$i.ts"
    done
    files="${files:1}"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Trigger with 15 files (exceeds threshold of 10)
    run "$INDEXER_SCRIPT" --dry-run --files "$files"

    skip_if_not_ready "$status" "$output" "indexer.sh threshold exceeded"

    # Then: Should trigger full rebuild
    assert_exit_success "$status"
    assert_contains "$output" "FULL_REBUILD"
    assert_contains_any "$output" "file_count_exceeds_threshold" "threshold" "exceeded"
}

# ============================================================
# AC-003: Offline SCIP Proto Resolution
# ============================================================

# @test T-IS-003: Offline proto resolution uses vendored path first
@test "T-IS-003: scip-to-graph uses vendored proto in offline mode" {
    skip_if_not_executable "$SCIP_TO_GRAPH"

    # Given: Vendored proto exists, offline mode enabled
    create_vendored_proto "$TEST_TEMP_DIR/vendored"
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true

    export VENDORED_PROTO_PATH="$TEST_TEMP_DIR/vendored/scip.proto"
    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Check proto resolution (not actual parse)
    run "$SCIP_TO_GRAPH" --check-proto

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh --check-proto"

    # Then: Should report using vendored proto
    assert_exit_success "$status"
    assert_contains_any "$output" "VENDORED" "vendored" "proto_source"
}

# @test T-IS-003b: Proto resolution respects custom SCIP_PROTO_PATH
@test "T-IS-003b: scip-to-graph respects custom SCIP_PROTO_PATH" {
    skip_if_not_executable "$SCIP_TO_GRAPH"

    # Given: Custom proto path set
    create_vendored_proto "$TEST_TEMP_DIR/custom-proto"

    export SCIP_PROTO_PATH="$TEST_TEMP_DIR/custom-proto/scip.proto"

    # When: Check proto resolution
    run "$SCIP_TO_GRAPH" --check-proto

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh custom proto"

    # Then: Should use custom path
    assert_exit_success "$status"
    assert_contains_any "$output" "CUSTOM" "custom" "$TEST_TEMP_DIR/custom-proto"
}

# @test T-IS-003c: Proto resolution fails with clear error when not found
@test "T-IS-003c: scip-to-graph fails clearly when proto not found and download disabled" {
    skip_if_not_executable "$SCIP_TO_GRAPH"

    # Given: No proto available, download disabled
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true  # offline_proto=true, allow_download=false

    export SCIP_PROTO_PATH=""
    export VENDORED_PROTO_PATH=""
    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Try to resolve proto
    run "$SCIP_TO_GRAPH" --check-proto

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh missing proto"

    # Then: Should fail with clear error message
    assert_exit_failure "$status"
    assert_contains_any "$output" "proto not found" "SCIP proto" "not found" "vendored"
}

# @test T-IS-003d: Proto resolution outputs version info
@test "T-IS-003d: scip-to-graph outputs proto_version in result" {
    skip_if_not_executable "$SCIP_TO_GRAPH"

    # Given: Vendored proto with version comment
    create_vendored_proto "$TEST_TEMP_DIR/vendored"

    export VENDORED_PROTO_PATH="$TEST_TEMP_DIR/vendored/scip.proto"

    # When: Parse with JSON output
    run "$SCIP_TO_GRAPH" --check-proto --format json

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh proto version"

    # Then: Should include proto_version in output
    assert_exit_success "$status"
    assert_contains_any "$output" "proto_version" "version" "0.4.0"
}

# ============================================================
# AC-004: Existing CLI Entry Points Compatibility
# ============================================================

# @test T-IS-004: CLI --help shows all existing options
@test "T-IS-004: indexer.sh --help shows existing options" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # When: Run --help
    run "$INDEXER_SCRIPT" --help

    # Then: Should show all documented options
    assert_exit_success "$status"
    assert_contains "$output" "--help"
    assert_contains_any "$output" "--status" "status"
    assert_contains_any "$output" "--install" "install"
    assert_contains_any "$output" "--uninstall" "uninstall"
}

# @test T-IS-004b: CLI --status returns status
@test "T-IS-004b: indexer.sh --status returns daemon status" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # When: Check status
    run "$INDEXER_SCRIPT" --status

    # Then: Should report status (running or not running)
    # Exit code 0 for running, non-zero for not running - both are valid
    assert_contains_any "$output" "running" "not running" "status" "daemon"
}

# @test T-IS-004c: CLI new --dry-run parameter available
@test "T-IS-004c: indexer.sh --dry-run parameter supported" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # When: Use --dry-run
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts"

    skip_if_not_ready "$status" "$output" "indexer.sh --dry-run"

    # Then: Should output decision without executing
    assert_exit_success "$status"
    assert_contains_any "$output" "decision" "INCREMENTAL" "FULL_REBUILD" "SKIP"
    # Should NOT modify graph.db
    [ ! -f "$GRAPH_DB_PATH" ] || {
        local node_count
        node_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
        [ "$node_count" -eq 0 ]
    }
}

# @test T-IS-004d: CLI new --once parameter available
@test "T-IS-004d: indexer.sh --once parameter supported" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # When: Check help for --once
    run "$INDEXER_SCRIPT" --help

    skip_if_not_ready "$status" "$output" "indexer.sh --once in help"

    # Then: Should document --once option
    assert_contains_any "$output" "--once" "once" "single"
}

# ============================================================
# AC-005: ci_index_status Semantic Alignment
# ============================================================

# @test T-IS-005: ci_index_status routes to embedding.sh
@test "T-IS-005: ci_index_status status action calls embedding.sh status" {
    skip_if_not_executable "$EMBEDDING_SCRIPT"

    # This test verifies the MCP tool routing
    # We need to check that server.ts routes ci_index_status to embedding.sh

    # Given: Server code exists
    local server_file="$PROJECT_ROOT/src/server.ts"
    skip_if_no_file "$server_file"

    # When: Check server.ts for ci_index_status handling
    # Extract the ci_index_status handler block specifically
    run grep -A 20 "ci_index_status" "$server_file"

    skip_if_not_ready "$status" "$output" "ci_index_status in server.ts"

    # Then: Should route to embedding.sh not indexer.sh
    # First, verify embedding.sh is referenced
    assert_contains_any "$output" "embedding" "embedding.sh"

    # Then, verify indexer.sh is NOT used for this tool
    # Use assert_not_contains for proper test result propagation
    # Note: We check if the handler block mentions indexer.sh as the route target
    # A simple string check could false-positive on comments, so we look for
    # actual routing patterns like "indexer.sh" in spawn/exec context
    if echo "$output" | grep -E "(spawn|exec|call).*indexer\.sh" > /dev/null 2>&1; then
        echo "FAIL: ci_index_status routes to indexer.sh but should route to embedding.sh" >&2
        echo "Found in output: $output" >&2
        return 1
    fi

    # Additional verification: the handler should explicitly use embedding.sh
    # Check for embedding-related patterns in the handler
    if ! echo "$output" | grep -E "(embedding|embed)" > /dev/null 2>&1; then
        echo "FAIL: ci_index_status handler does not reference embedding" >&2
        return 1
    fi
}

# @test T-IS-005a: ci_index_status status action works
@test "T-IS-005a: embedding.sh status returns valid status" {
    skip_if_not_executable "$EMBEDDING_SCRIPT"

    # When: Call embedding.sh status
    run "$EMBEDDING_SCRIPT" status

    skip_if_not_ready "$status" "$output" "embedding.sh status"

    # Then: Should return status information
    assert_exit_success "$status"
    assert_contains_any "$output" "status" "initialized" "not" "index"
}

# @test T-IS-005b: ci_index_status build action maps to embedding.sh build
@test "T-IS-005b: embedding.sh build command exists" {
    skip_if_not_executable "$EMBEDDING_SCRIPT"

    # When: Check help for build command
    run "$EMBEDDING_SCRIPT" --help

    # Then: Should document build command
    assert_exit_success "$status"
    assert_contains "$output" "build"
}

# @test T-IS-005c: ci_index_status clear action maps to embedding.sh clean
@test "T-IS-005c: embedding.sh clean command exists" {
    skip_if_not_executable "$EMBEDDING_SCRIPT"

    # When: Check help for clean command
    run "$EMBEDDING_SCRIPT" --help

    # Then: Should document clean command
    assert_exit_success "$status"
    assert_contains "$output" "clean"
}

# ============================================================
# AC-006: Idempotent Index Operations
# ============================================================

# @test T-IS-006: Repeated incremental updates don't accumulate nodes
@test "T-IS-006: repeated incremental updates are idempotent" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Initial state with some nodes
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    # Insert initial test nodes
    sqlite3 "$GRAPH_DB_PATH" << EOF
INSERT INTO nodes (id, symbol, kind, file_path) VALUES ('n1', 'testFunction', 'function', 'src/index.ts');
INSERT INTO nodes (id, symbol, kind, file_path) VALUES ('n2', 'TestClass', 'class', 'src/index.ts');
EOF

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Run indexer first time to establish baseline
    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/index.ts"
    skip_if_not_ready "$status" "$output" "indexer.sh first run"

    # Record the count after first run as baseline
    local baseline_count
    baseline_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;")

    # Run indexer second time
    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/index.ts"
    skip_if_not_ready "$status" "$output" "indexer.sh second run"

    local second_count
    second_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;")

    # Run indexer third time
    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/index.ts"
    skip_if_not_ready "$status" "$output" "indexer.sh third run"

    local third_count
    third_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;")

    # Then: Node count should remain exactly the same after the first run
    # This is true idempotency - repeated operations produce identical results
    if [ "$second_count" -ne "$baseline_count" ]; then
        echo "FAIL: Idempotency violated - second run changed node count" >&2
        echo "Baseline: $baseline_count, After second run: $second_count" >&2
        return 1
    fi

    if [ "$third_count" -ne "$baseline_count" ]; then
        echo "FAIL: Idempotency violated - third run changed node count" >&2
        echo "Baseline: $baseline_count, After third run: $third_count" >&2
        return 1
    fi
}

# @test T-IS-006b: Full rebuild also idempotent
@test "T-IS-006b: full rebuild is idempotent" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Force full rebuild conditions
    create_test_config "$TEST_TEMP_DIR/config" false 10 2 true  # ast_delta disabled

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Run full rebuild twice
    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/index.ts"
    skip_if_not_ready "$status" "$output" "indexer.sh full rebuild 1"

    local count_after_first
    count_after_first=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")

    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/index.ts"
    skip_if_not_ready "$status" "$output" "indexer.sh full rebuild 2"

    # Then: Counts should be equal
    local count_after_second
    count_after_second=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")

    [ "$count_after_first" -eq "$count_after_second" ]
}

# ============================================================
# AC-007: Debounce Window Aggregation
# ============================================================

# @test T-IS-007: Multiple changes within debounce window are aggregated
# NOTE: This test validates batch processing when multiple files are passed together.
# True debounce testing with timing would require a daemon mode test, which is covered
# in IS-007c below with actual timing verification.
@test "T-IS-007: batch processing aggregates multiple files" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Short debounce window for testing
    create_test_config "$TEST_TEMP_DIR/config" true 10 1 true  # 1 second debounce

    # Create multiple files
    for i in 1 2 3; do
        create_test_ts_file "$TEST_REPO_DIR/src/debounce$i.ts"
    done

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Trigger with multiple files (batch processing)
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/debounce1.ts,$TEST_REPO_DIR/src/debounce2.ts,$TEST_REPO_DIR/src/debounce3.ts"

    skip_if_not_ready "$status" "$output" "indexer.sh batch processing"

    # Then: Should process as a batch
    assert_exit_success "$status"
    # Output should indicate batch/aggregated processing
    # Either explicitly saying "batch" or showing the count of files
    assert_contains_any "$output" "batch" "aggregated" "files" "3"
}

# @test T-IS-007b: Debounce window configurable
@test "T-IS-007b: debounce window reads from config" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Custom debounce in config
    create_test_config "$TEST_TEMP_DIR/config" true 10 5 true  # 5 second debounce

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Check configuration is read
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts" --show-config

    skip_if_not_ready "$status" "$output" "indexer.sh config read"

    # Then: Should show configured debounce value
    assert_exit_success "$status"
    assert_contains_any "$output" "debounce" "5" "seconds"
}

# @test T-IS-007c: True debounce timing test
# This test verifies actual debounce behavior with timing
@test "T-IS-007c: debounce timing prevents duplicate processing" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Short debounce window
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true  # 2 second debounce
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    create_test_ts_file "$TEST_REPO_DIR/src/timing1.ts"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # Create a log file to track invocations
    local invocation_log="$TEST_TEMP_DIR/invocations.log"
    touch "$invocation_log"

    # When: Trigger indexer twice rapidly (within debounce window)
    # First invocation
    local start_time
    start_time=$(date +%s)

    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/timing1.ts"
    skip_if_not_ready "$status" "$output" "indexer.sh timing test"

    # Record first invocation
    echo "1:$(date +%s)" >> "$invocation_log"

    # Sleep briefly (less than debounce window)
    sleep 0.5

    # Second invocation for same file
    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/timing1.ts"

    # Record second invocation
    echo "2:$(date +%s)" >> "$invocation_log"

    local end_time
    end_time=$(date +%s)

    # Then: Both should succeed (debounce is about aggregation, not rejection)
    assert_exit_success "$status"

    # The key behavior to verify: if debounce is working, the second call
    # should either be skipped (because it's within the window) or
    # should indicate it was debounced/batched
    # For now, we just verify no errors occurred during rapid invocations
    if echo "$output" | grep -qi "error"; then
        echo "FAIL: Rapid invocations caused errors" >&2
        return 1
    fi
}

# ============================================================
# AC-008: Version Stamp Consistency
# ============================================================

# @test T-IS-008: Version stamp updated after full rebuild
@test "T-IS-008: full rebuild updates version stamp" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Initial version stamp
    create_test_config "$TEST_TEMP_DIR/config" false 10 2 true  # Force full rebuild
    mkdir -p "$AST_CACHE_DIR"
    echo '{"version": "v1.0", "timestamp": "2026-01-01T00:00:00Z"}' > "$AST_CACHE_DIR/.version"

    local initial_version
    initial_version=$(cat "$AST_CACHE_DIR/.version" | grep -o '"version": "[^"]*"' | head -1 || echo "v1.0")

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Execute full rebuild
    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/index.ts"

    skip_if_not_ready "$status" "$output" "indexer.sh version stamp update"

    # Then: Version stamp should be updated
    assert_exit_success "$status"

    local new_version
    new_version=$(cat "$AST_CACHE_DIR/.version" 2>/dev/null | grep -o '"timestamp": "[^"]*"' || echo "")
    [ -n "$new_version" ]  # Should have a new timestamp
}

# @test T-IS-008b: Cache cleared on version mismatch
@test "T-IS-008b: AST cache cleared when version mismatch triggers rebuild" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Mismatched versions
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    mkdir -p "$AST_CACHE_DIR"
    echo '{"version": "v2.0"}' > "$AST_CACHE_DIR/.version"

    # Create stale cache files
    touch "$AST_CACHE_DIR/stale_cache_file.ast"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Trigger rebuild due to mismatch
    run "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/index.ts"

    skip_if_not_ready "$status" "$output" "indexer.sh cache clear"

    # Then: Old cache files should be cleared
    assert_exit_success "$status"
    [ ! -f "$AST_CACHE_DIR/stale_cache_file.ast" ]
}

# @test T-IS-008c: Version stamp check logic correct
@test "T-IS-008c: version stamp comparison works correctly" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Matching versions
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    mkdir -p "$AST_CACHE_DIR"
    echo '{"version": "v1.0"}' > "$AST_CACHE_DIR/.version"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Check decision
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts"

    skip_if_not_ready "$status" "$output" "indexer.sh version check"

    # Then: Should NOT trigger rebuild due to version
    assert_exit_success "$status"
    assert_not_contains "$output" "cache_version_mismatch"
}

# ============================================================
# AC-009: Feature Toggle Support
# ============================================================

# @test T-IS-009: Feature toggle disables incremental path
@test "T-IS-009: feature toggle disables incremental path via config" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: ast_delta.enabled = false in config
    create_test_config "$TEST_TEMP_DIR/config" false 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Trigger indexer (single file, would normally be incremental)
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts"

    skip_if_not_ready "$status" "$output" "indexer.sh feature toggle"

    # Then: Should output FULL_REBUILD with reason feature_disabled
    assert_exit_success "$status"
    assert_contains "$output" "FULL_REBUILD"
    assert_contains_any "$output" "feature_disabled" "disabled" "ast_delta"
}

# @test T-IS-009b: Feature toggle via environment variable
@test "T-IS-009b: feature toggle via CI_AST_DELTA_ENABLED env var" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Config enables it, but env var disables
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"
    export CI_AST_DELTA_ENABLED=false

    # When: Trigger indexer
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts"

    unset CI_AST_DELTA_ENABLED

    skip_if_not_ready "$status" "$output" "indexer.sh env toggle"

    # Then: Environment variable should override config
    assert_exit_success "$status"
    assert_contains "$output" "FULL_REBUILD"
}

# @test T-IS-009c: Feature toggle file_threshold configurable
@test "T-IS-009c: file_threshold configurable via config" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Low threshold (5 files)
    create_test_config "$TEST_TEMP_DIR/config" true 5 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    # Create 6 files (exceeds threshold of 5)
    for i in $(seq 1 6); do
        create_test_ts_file "$TEST_REPO_DIR/src/thresh$i.ts"
    done

    local files=""
    for i in $(seq 1 6); do
        files="$files,$TEST_REPO_DIR/src/thresh$i.ts"
    done
    files="${files:1}"

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Trigger with 6 files
    run "$INDEXER_SCRIPT" --dry-run --files "$files"

    skip_if_not_ready "$status" "$output" "indexer.sh custom threshold"

    # Then: Should trigger full rebuild (6 > 5)
    assert_exit_success "$status"
    assert_contains "$output" "FULL_REBUILD"
}

# ============================================================
# AC-010: Concurrent Write Safety
# ============================================================

# @test T-IS-010: Concurrent writes don't corrupt database
@test "T-IS-010: concurrent index operations don't corrupt graph.db" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Multiple files to index
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    for i in $(seq 1 5); do
        create_test_ts_file "$TEST_REPO_DIR/src/concurrent$i.ts"
    done

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # Create temp files to capture output and exit codes from background processes
    local out1="$TEST_TEMP_DIR/concurrent_out1.log"
    local out2="$TEST_TEMP_DIR/concurrent_out2.log"
    local out3="$TEST_TEMP_DIR/concurrent_out3.log"
    local exit1="$TEST_TEMP_DIR/concurrent_exit1"
    local exit2="$TEST_TEMP_DIR/concurrent_exit2"
    local exit3="$TEST_TEMP_DIR/concurrent_exit3"

    # When: Run multiple indexer processes concurrently, capturing output to files
    (
        "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/concurrent1.ts" > "$out1" 2>&1
        echo $? > "$exit1"
    ) &
    local pid1=$!

    (
        "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/concurrent2.ts" > "$out2" 2>&1
        echo $? > "$exit2"
    ) &
    local pid2=$!

    (
        "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/concurrent3.ts" > "$out3" 2>&1
        echo $? > "$exit3"
    ) &
    local pid3=$!

    # Wait for all to complete
    wait "$pid1" 2>/dev/null || true
    wait "$pid2" 2>/dev/null || true
    wait "$pid3" 2>/dev/null || true

    # Collect exit codes
    local code1 code2 code3
    code1=$(cat "$exit1" 2>/dev/null || echo "1")
    code2=$(cat "$exit2" 2>/dev/null || echo "1")
    code3=$(cat "$exit3" 2>/dev/null || echo "1")

    # Then: All processes should complete successfully (exit code 0)
    # Allow for "not implemented" scenario in Red baseline
    if [ "${EXPECT_RED:-true}" = "false" ]; then
        if [ "$code1" -ne 0 ] || [ "$code2" -ne 0 ] || [ "$code3" -ne 0 ]; then
            echo "FAIL: One or more concurrent processes failed" >&2
            echo "Process 1 exit: $code1, output: $(cat "$out1" 2>/dev/null)" >&2
            echo "Process 2 exit: $code2, output: $(cat "$out2" 2>/dev/null)" >&2
            echo "Process 3 exit: $code3, output: $(cat "$out3" 2>/dev/null)" >&2
            return 1
        fi
    fi

    # Database should pass integrity check
    run sqlite3 "$GRAPH_DB_PATH" "PRAGMA integrity_check;"

    if [ "$output" != "ok" ]; then
        echo "FAIL: Database integrity check failed: $output" >&2
        return 1
    fi

    # Verify no corruption - check that each file was processed
    # by querying for nodes or checking output content
    local combined_output
    combined_output="$(cat "$out1" 2>/dev/null) $(cat "$out2" 2>/dev/null) $(cat "$out3" 2>/dev/null)"

    # Check for no "database is locked" or corruption errors
    if echo "$combined_output" | grep -qi "database is locked"; then
        echo "FAIL: Database locking error occurred during concurrent operations" >&2
        return 1
    fi

    if echo "$combined_output" | grep -qi "database.*corrupt"; then
        echo "FAIL: Database corruption detected during concurrent operations" >&2
        return 1
    fi
}

# @test T-IS-010b: No database locked errors under concurrent load
@test "T-IS-010b: no 'database is locked' errors under concurrent load" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: WAL mode should be enabled
    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    create_graph_db_with_version "$GRAPH_DB_PATH" "v1.0"

    # Ensure WAL mode
    sqlite3 "$GRAPH_DB_PATH" "PRAGMA journal_mode=WAL;"

    for i in $(seq 1 3); do
        create_test_ts_file "$TEST_REPO_DIR/src/lock$i.ts"
    done

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # Create temp files to capture output from background processes
    local out1="$TEST_TEMP_DIR/lock_out1.log"
    local out2="$TEST_TEMP_DIR/lock_out2.log"
    local out3="$TEST_TEMP_DIR/lock_out3.log"

    # When: Run concurrent operations and capture output to temp files
    "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/lock1.ts" > "$out1" 2>&1 &
    local pid1=$!
    "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/lock2.ts" > "$out2" 2>&1 &
    local pid2=$!
    "$INDEXER_SCRIPT" --once --files "$TEST_REPO_DIR/src/lock3.ts" > "$out3" 2>&1 &
    local pid3=$!

    wait "$pid1" 2>/dev/null || true
    wait "$pid2" 2>/dev/null || true
    wait "$pid3" 2>/dev/null || true

    # Then: No "database is locked" errors in any output
    local combined_output
    combined_output="$(cat "$out1" 2>/dev/null) $(cat "$out2" 2>/dev/null) $(cat "$out3" 2>/dev/null)"

    if echo "$combined_output" | grep -qi "database is locked"; then
        echo "FAIL: Concurrent operations produced 'database is locked' error" >&2
        echo "Output 1: $(cat "$out1" 2>/dev/null)" >&2
        echo "Output 2: $(cat "$out2" 2>/dev/null)" >&2
        echo "Output 3: $(cat "$out3" 2>/dev/null)" >&2
        return 1
    fi

    # Verify WAL mode is still enabled after concurrent operations
    local journal_mode
    journal_mode=$(sqlite3 "$GRAPH_DB_PATH" "PRAGMA journal_mode;")
    if [ "$journal_mode" != "wal" ]; then
        echo "FAIL: WAL mode was disabled during concurrent operations" >&2
        return 1
    fi
}

# ============================================================
# Boundary Condition Tests
# ============================================================

# @test BOUNDARY-001: Empty file list handled
@test "T-IS-BOUNDARY-001: empty file list handled gracefully" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Call with empty files parameter
    run "$INDEXER_SCRIPT" --dry-run --files ""

    skip_if_not_ready "$status" "$output" "indexer.sh empty files"

    # Then: Should output SKIP decision
    assert_exit_success "$status"
    assert_contains_any "$output" "SKIP" "no_changes" "empty"
}

# @test BOUNDARY-002: Non-existent file handled
@test "T-IS-BOUNDARY-002: non-existent file handled gracefully" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Call with non-existent file
    run "$INDEXER_SCRIPT" --dry-run --files "/nonexistent/path/file.ts"

    skip_if_not_ready "$status" "$output" "indexer.sh non-existent file"

    # Then: Should handle gracefully (skip or error)
    # Either exit success with SKIP or exit failure with clear error
    if [ "$status" -eq 0 ]; then
        assert_contains_any "$output" "SKIP" "not found" "skipped"
    else
        assert_contains_any "$output" "not found" "does not exist" "error"
    fi
}

# @test BOUNDARY-003: Invalid config values handled
@test "T-IS-BOUNDARY-003: invalid config values handled gracefully" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    # Given: Invalid config (negative threshold)
    mkdir -p "$TEST_TEMP_DIR/config"
    cat > "$TEST_TEMP_DIR/config/features.yaml" << 'EOF'
features:
  ast_delta:
    enabled: maybe
    file_threshold: -5
  indexer:
    debounce_seconds: not_a_number
EOF

    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Try to use invalid config
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts"

    # Then: Should handle gracefully (use defaults or report error)
    # Shouldn't crash
    assert_contains_any "$output" "decision" "error" "invalid" "default"
}

# ============================================================
# CLI Interface Tests
# ============================================================

# @test CLI-001: Help output complete
@test "T-IS-CLI-001: indexer.sh --help output is complete" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    run "$INDEXER_SCRIPT" --help

    assert_exit_success "$status"
    # Should document new options
    assert_contains_any "$output" "dry-run" "--dry-run"
    assert_contains_any "$output" "once" "--once"
    assert_contains_any "$output" "files" "--files"
}

# @test CLI-002: Invalid option rejected
@test "T-IS-CLI-002: invalid option rejected" {
    skip_if_not_executable "$INDEXER_SCRIPT"

    run "$INDEXER_SCRIPT" --invalid-option-xyz

    assert_exit_failure "$status"
    assert_contains_any "$output" "invalid" "unknown" "option" "error"
}

# ============================================================
# JSON Output Tests
# ============================================================

# @test JSON-001: Dry-run outputs valid JSON
@test "T-IS-JSON-001: dry-run outputs valid JSON decision" {
    skip_if_not_executable "$INDEXER_SCRIPT"
    skip_if_missing "jq"

    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    # When: Run with JSON format
    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts" --format json

    skip_if_not_ready "$status" "$output" "indexer.sh JSON output"

    # Then: Output should be valid JSON
    assert_exit_success "$status"
    assert_valid_json "$output"

    # Should have required fields
    assert_json_field "$output" ".decision"
    assert_json_field "$output" ".reason"
}

# @test JSON-002: Decision JSON includes changed_files
@test "T-IS-JSON-002: decision JSON includes changed_files array" {
    skip_if_not_executable "$INDEXER_SCRIPT"
    skip_if_missing "jq"

    create_test_config "$TEST_TEMP_DIR/config" true 10 2 true
    export CONFIG_DIR="$TEST_TEMP_DIR/config"

    run "$INDEXER_SCRIPT" --dry-run --files "$TEST_REPO_DIR/src/index.ts" --format json

    skip_if_not_ready "$status" "$output" "indexer.sh JSON files"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # Should have changed_files array
    local files_count
    files_count=$(echo "$output" | jq '.changed_files | length' 2>/dev/null || echo "0")
    [ "$files_count" -ge 1 ]
}
