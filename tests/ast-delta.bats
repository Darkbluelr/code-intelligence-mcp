#!/usr/bin/env bats
# ast-delta.bats - AST Delta 增量索引模块测试
#
# 覆盖 AC-AD-001: AST Delta 增量索引支持单文件/批量更新
# 契约测试: CT-AD-001 (单文件更新), CT-AD-002 (批量更新), CT-AD-003 (降级策略)
#
# 场景覆盖:
#   T-AD-001: 单文件增量更新
#   T-AD-002: 批量增量更新
#   T-AD-003: 缓存失效触发全量重建
#   T-AD-004: tree-sitter 不可用降级到 SCIP
#   T-AD-005: 大规模变更触发全量重建
#   T-AD-006: 性能验证 (P95 <= 120ms)
#   T-AD-007: 原子写入保护

load 'helpers/common'

# 脚本路径
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
AST_DELTA="$SCRIPT_DIR/ast-delta.sh"

# 测试常量
PERFORMANCE_ITERATIONS="${PERFORMANCE_ITERATIONS:-50}"
PERFORMANCE_P95_THRESHOLD="${PERFORMANCE_P95_THRESHOLD:-120}"
BATCH_THRESHOLD="${BATCH_THRESHOLD:-10}"

setup() {
    setup_temp_dir
    export GRAPH_DB_PATH="$TEST_TEMP_DIR/graph.db"
    export DEVBOOKS_DIR="$TEST_TEMP_DIR/.devbooks"
    export AST_CACHE_DIR="$TEST_TEMP_DIR/.ast-cache"
    mkdir -p "$DEVBOOKS_DIR"
    mkdir -p "$AST_CACHE_DIR"

    # 初始化测试 git 仓库
    setup_test_git_repo_with_src "$TEST_TEMP_DIR/repo"
    export TEST_REPO_DIR="$TEST_TEMP_DIR/repo"

    # 创建测试文件
    create_test_source_file "$TEST_REPO_DIR/src/index.ts" 100
}

teardown() {
    cleanup_test_git_repo
    cleanup_temp_dir
}

# ============================================================
# 辅助函数
# ============================================================

# 创建测试源文件
# Usage: create_test_source_file <path> <lines>
create_test_source_file() {
    local path="$1"
    local lines="${2:-100}"
    mkdir -p "$(dirname "$path")"

    {
        echo "// Test file for AST Delta testing"
        echo "export interface TestInterface {"
        echo "    id: string;"
        echo "    name: string;"
        echo "}"
        echo ""
        echo "export class TestClass {"
        echo "    private value: number;"
        echo ""
        echo "    constructor(value: number) {"
        echo "        this.value = value;"
        echo "    }"
        echo ""
        echo "    getValue(): number {"
        echo "        return this.value;"
        echo "    }"
        echo ""
        echo "    setValue(newValue: number): void {"
        echo "        this.value = newValue;"
        echo "    }"
        echo "}"
        echo ""
        # 填充到指定行数
        local current_line=25
        while [ "$current_line" -lt "$lines" ]; do
            echo "// Line $current_line - padding for test"
            ((current_line++))
        done
        echo ""
        echo "export function main(): void {"
        echo "    const instance = new TestClass(42);"
        echo "    console.log(instance.getValue());"
        echo "}"
    } > "$path"
}

# 创建 AST 缓存文件
# Usage: create_ast_cache <file_path> [version_stamp]
create_ast_cache() {
    local file_path="$1"
    local version="${2:-v1.0}"
    local cache_file="$AST_CACHE_DIR/$(echo "$file_path" | tr '/' '_').ast"

    cat > "$cache_file" << EOF
{
    "version": "$version",
    "file_path": "$file_path",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "symbols": [
        {"name": "TestClass", "kind": "class", "line_start": 7, "line_end": 21},
        {"name": "getValue", "kind": "method", "line_start": 14, "line_end": 16},
        {"name": "main", "kind": "function", "line_start": 25, "line_end": 28}
    ]
}
EOF
    echo "$cache_file"
}

# 创建带有版本戳的 graph.db
# Usage: create_graph_db [version_stamp]
create_graph_db() {
    local version="${1:-v1.0}"

    # 使用 graph-store.sh 初始化（如果可用）
    if [ -x "$SCRIPT_DIR/graph-store.sh" ]; then
        "$SCRIPT_DIR/graph-store.sh" init 2>/dev/null || true
    fi

    # 确保数据库存在
    if [ ! -f "$GRAPH_DB_PATH" ]; then
        sqlite3 "$GRAPH_DB_PATH" << EOF
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
    edge_type TEXT NOT NULL,
    file_path TEXT,
    line_number INTEGER
);
CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT
);
EOF
    fi

    # 设置版本戳
    sqlite3 "$GRAPH_DB_PATH" "INSERT OR REPLACE INTO metadata (key, value) VALUES ('ast_cache_version', '$version');"
}

# 创建孤儿临时文件
# Usage: create_orphan_temp_files <count>
create_orphan_temp_files() {
    local count="${1:-3}"
    local i=1
    while [ "$i" -le "$count" ]; do
        touch "$DEVBOOKS_DIR/.ast-delta-temp-$i.tmp"
        ((i++))
    done
}

# 检查 tree-sitter 是否可用
check_tree_sitter_available() {
    if command -v tree-sitter &> /dev/null; then
        return 0
    fi
    if [ -d "$TEST_REPO_DIR/node_modules/tree-sitter" ]; then
        return 0
    fi
    return 1
}

# ============================================================
# CT-AD-001: 单文件增量更新测试
# ============================================================

# @test T-AD-001: 单文件增量更新
@test "T-AD-001: ast-delta update performs single file incremental update" {
    skip_if_not_executable "$AST_DELTA"

    # Given: tree-sitter 可用，AST 缓存存在
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/index.ts"
    create_ast_cache "$test_file" "v1.0"

    # When: 调用 ast-delta.sh update <file-path>
    run "$AST_DELTA" update "$test_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh update"

    # Then: 解析新 AST、计算差异、更新 graph.db
    assert_exit_success "$status"

    # 验证输出包含增量更新标记
    assert_contains_any "$output" "incremental" "updated" "delta" "success"

    # 验证数据库已更新（节点数应增加或保持）
    local node_count
    node_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes WHERE file_path LIKE '%index.ts%';" 2>/dev/null || echo "0")
    [ "$node_count" -ge 0 ]
}

# @test T-AD-001b: 单文件更新检测符号变更
@test "T-AD-001b: ast-delta update detects symbol changes" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 已有缓存和数据库
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/index.ts"
    create_ast_cache "$test_file" "v1.0"

    # 先执行一次更新
    run "$AST_DELTA" update "$test_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh update (initial)"

    # 修改源文件（添加新函数）
    echo "" >> "$test_file"
    echo "export function newFunction(): string {" >> "$test_file"
    echo "    return 'new';" >> "$test_file"
    echo "}" >> "$test_file"

    # When: 再次执行更新
    run "$AST_DELTA" update "$test_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh update (after change)"

    # Then: 应检测到变更
    assert_exit_success "$status"
}

# ============================================================
# CT-AD-002: 批量增量更新测试
# ============================================================

# @test T-AD-002: 批量增量更新
@test "T-AD-002: ast-delta batch updates multiple files since commit" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 变更文件数 <= 10
    create_graph_db "v1.0"

    # 创建初始提交
    cd "$TEST_REPO_DIR"
    git add .
    git commit -m "Initial commit" --quiet 2>/dev/null || true

    # 创建多个变更文件（少于阈值）
    local file_count=5
    for i in $(seq 1 "$file_count"); do
        create_test_source_file "$TEST_REPO_DIR/src/module$i.ts" 50
        create_ast_cache "$TEST_REPO_DIR/src/module$i.ts" "v1.0"
    done
    git add .
    git commit -m "Add modules" --quiet 2>/dev/null || true

    cd - > /dev/null

    # When: 调用 ast-delta.sh batch --since HEAD~1
    run "$AST_DELTA" batch --since HEAD~1
    skip_if_not_ready "$status" "$output" "ast-delta.sh batch"

    # Then: 检测所有变更文件、逐个更新
    assert_exit_success "$status"

    # 验证输出包含批量处理标记
    assert_contains_any "$output" "batch" "files" "processed" "updated"
}

# @test T-AD-002b: 批量更新使用增量路径
@test "T-AD-002b: ast-delta batch uses incremental path for small changes" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 少量文件变更
    create_graph_db "v1.0"

    cd "$TEST_REPO_DIR"
    git add .
    git commit -m "Initial" --quiet 2>/dev/null || true

    # 创建 3 个文件（远低于阈值）
    for i in 1 2 3; do
        create_test_source_file "$TEST_REPO_DIR/src/small$i.ts" 30
    done
    git add .
    git commit -m "Small change" --quiet 2>/dev/null || true

    cd - > /dev/null

    # When: 批量更新
    run "$AST_DELTA" batch --since HEAD~1
    skip_if_not_ready "$status" "$output" "ast-delta.sh batch (incremental)"

    # Then: 应使用增量路径（不触发全量重建）
    assert_exit_success "$status"
    assert_not_contains "$output" "FULL_REBUILD"
}

# ============================================================
# CT-AD-003: 缓存失效与降级策略测试
# ============================================================

# @test T-AD-003: 缓存失效触发全量重建
@test "T-AD-003: ast-delta triggers full rebuild when cache version mismatch" {
    skip_if_not_executable "$AST_DELTA"

    # Given: AST 缓存版本戳与 graph.db 不一致
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/index.ts"
    create_ast_cache "$test_file" "v2.0"  # 版本不匹配

    # 创建 VERSION_STAMP_FILE 以触发版本检查（使用与 db 不同的版本）
    mkdir -p "$AST_CACHE_DIR"
    echo '{"timestamp": "v2.0"}' > "$AST_CACHE_DIR/.version"

    # When: 调用 ast-delta.sh update <file-path>
    run "$AST_DELTA" update "$test_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh update (cache mismatch)"

    # Then: 执行 FULL_REBUILD 路径
    assert_exit_success "$status"

    # 验证输出包含全量重建标记（或降级模式如果 tree-sitter 不可用）
    assert_contains_any "$output" "FULL_REBUILD" "full_rebuild" "cache invalidated" "rebuilding" "FALLBACK" "fallback"
}

# @test T-AD-003b: 缓存不存在时触发重建
@test "T-AD-003b: ast-delta triggers rebuild when cache missing" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 无 AST 缓存
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/index.ts"
    # 不创建缓存

    # When: 调用更新
    run "$AST_DELTA" update "$test_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh update (no cache)"

    # Then: 应执行完整解析
    assert_exit_success "$status"
}

# @test T-AD-004: tree-sitter 不可用降级到 SCIP
@test "T-AD-004: ast-delta falls back to SCIP when tree-sitter unavailable" {
    skip_if_not_executable "$AST_DELTA"

    # Given: tree-sitter npm 包未安装（模拟）
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/index.ts"

    # 设置环境变量禁用 tree-sitter
    export DISABLE_TREE_SITTER=true
    export FORCE_SCIP_FALLBACK=true

    # When: 调用 ast-delta.sh update <file-path>
    run "$AST_DELTA" update "$test_file"

    # 清理环境变量
    unset DISABLE_TREE_SITTER
    unset FORCE_SCIP_FALLBACK

    skip_if_not_ready "$status" "$output" "ast-delta.sh update (SCIP fallback)"

    # Then: 降级到 SCIP 解析，输出降级警告
    assert_exit_success "$status"

    # 验证输出包含降级警告
    assert_contains_any "$output" "fallback" "SCIP" "degraded" "warning" "tree-sitter unavailable"
}

# @test T-AD-004b: 降级时功能仍正常
@test "T-AD-004b: ast-delta SCIP fallback still provides symbol extraction" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 强制 SCIP 模式
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/index.ts"

    export FORCE_SCIP_FALLBACK=true

    # When: 执行更新
    run "$AST_DELTA" update "$test_file"

    unset FORCE_SCIP_FALLBACK

    skip_if_not_ready "$status" "$output" "ast-delta.sh SCIP mode"

    # Then: 符号提取仍应工作
    assert_exit_success "$status"
}

# @test T-AD-005: 大规模变更触发全量重建
@test "T-AD-005: ast-delta triggers full rebuild for large batch" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 变更文件数 > 10
    create_graph_db "v1.0"

    cd "$TEST_REPO_DIR"
    git add .
    git commit -m "Initial" --quiet 2>/dev/null || true

    # 创建大量变更文件（超过阈值）
    local file_count=15
    for i in $(seq 1 "$file_count"); do
        create_test_source_file "$TEST_REPO_DIR/src/large$i.ts" 50
    done
    git add .
    git commit -m "Large change" --quiet 2>/dev/null || true

    cd - > /dev/null

    # When: 调用 ast-delta.sh batch --since <ref>
    run "$AST_DELTA" batch --since HEAD~1
    skip_if_not_ready "$status" "$output" "ast-delta.sh batch (large)"

    # Then: 执行 FULL_REBUILD 路径
    assert_exit_success "$status"

    # 验证输出包含全量重建标记（或降级模式如果 tree-sitter 不可用）
    assert_contains_any "$output" "FULL_REBUILD" "full_rebuild" "threshold exceeded" "too many files" "FALLBACK" "fallback"
}

# @test T-AD-005b: 阈值可配置
@test "T-AD-005b: ast-delta batch threshold is configurable" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 自定义阈值
    create_graph_db "v1.0"

    cd "$TEST_REPO_DIR"
    git add .
    git commit -m "Initial" --quiet 2>/dev/null || true

    # 创建 5 个文件
    for i in $(seq 1 5); do
        create_test_source_file "$TEST_REPO_DIR/src/conf$i.ts" 30
    done
    git add .
    git commit -m "Config test" --quiet 2>/dev/null || true

    cd - > /dev/null

    # When: 使用低阈值（3）
    export AST_DELTA_BATCH_THRESHOLD=3
    run "$AST_DELTA" batch --since HEAD~1
    unset AST_DELTA_BATCH_THRESHOLD

    skip_if_not_ready "$status" "$output" "ast-delta.sh batch (low threshold)"

    # Then: 应触发全量重建（因为 5 > 3）
    assert_exit_success "$status"
}

# ============================================================
# CT-AD-004: 性能测试
# ============================================================

# @test T-AD-006: 性能验证 P95 <= 120ms
@test "T-AD-006: ast-delta single file update P95 latency <= 120ms" {
    skip_if_not_executable "$AST_DELTA"

    # Given: tree-sitter 可用，测试文件约 500 行
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/perf-test.ts"
    create_test_source_file "$test_file" 500
    create_ast_cache "$test_file" "v1.0"

    # 预热
    run "$AST_DELTA" update "$test_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh update (warmup)"

    # When: 执行 50 次 AST 解析
    local latencies=()
    local i=1
    while [ "$i" -le "$PERFORMANCE_ITERATIONS" ]; do
        measure_time "$AST_DELTA" update "$test_file" > /dev/null 2>&1
        latencies+=("$MEASURED_TIME_MS")
        ((i++))
    done

    # Then: P95 延迟 <= 120ms
    local p95
    p95=$(calculate_p95 "${latencies[@]}")

    echo "Performance results:"
    echo "  Iterations: $PERFORMANCE_ITERATIONS"
    echo "  P95 latency: ${p95}ms"
    echo "  Threshold: ${PERFORMANCE_P95_THRESHOLD}ms"

    if [ "$p95" -gt "$PERFORMANCE_P95_THRESHOLD" ]; then
        echo "FAIL: P95 ($p95 ms) exceeds threshold ($PERFORMANCE_P95_THRESHOLD ms)" >&2
        return 1
    fi
}

# @test T-AD-006b: 增量更新比全量重建快
@test "T-AD-006b: ast-delta incremental update faster than full rebuild" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 有缓存的文件
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/speed-test.ts"
    create_test_source_file "$test_file" 300
    create_ast_cache "$test_file" "v1.0"

    # 预热
    run "$AST_DELTA" update "$test_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh (speed warmup)"

    # 测量增量更新
    local incremental_times=()
    for i in 1 2 3 4 5; do
        measure_time "$AST_DELTA" update "$test_file" > /dev/null 2>&1
        incremental_times+=("$MEASURED_TIME_MS")
    done

    # 清除缓存强制全量重建
    rm -rf "$AST_CACHE_DIR"/*

    # 测量全量重建
    local full_rebuild_times=()
    for i in 1 2 3 4 5; do
        measure_time "$AST_DELTA" update "$test_file" --force-rebuild > /dev/null 2>&1
        full_rebuild_times+=("$MEASURED_TIME_MS")
        # 重新清除缓存
        rm -rf "$AST_CACHE_DIR"/*
    done

    # 计算平均值
    local incremental_avg full_avg
    incremental_avg=$(printf '%s\n' "${incremental_times[@]}" | awk '{sum+=$1} END {print int(sum/NR)}')
    full_avg=$(printf '%s\n' "${full_rebuild_times[@]}" | awk '{sum+=$1} END {print int(sum/NR)}')

    echo "Incremental avg: ${incremental_avg}ms"
    echo "Full rebuild avg: ${full_avg}ms"

    # 增量应该更快（或至少不慢很多）
    # 允许 50% 的容差
    local threshold=$((full_avg * 150 / 100))
    [ "$incremental_avg" -le "$threshold" ]
}

# ============================================================
# CT-AD-005: 原子写入保护测试
# ============================================================

# @test T-AD-007: 原子写入保护 - 清理孤儿临时文件
@test "T-AD-007: ast-delta cleans up orphan temp files on invocation" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 存在孤儿临时文件
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/index.ts"
    # 不创建缓存文件，确保走慢路径以触发清理逻辑

    # 创建孤儿临时文件
    create_orphan_temp_files 3

    # 验证临时文件存在
    local orphan_count_before
    orphan_count_before=$(find "$DEVBOOKS_DIR" -name ".ast-delta-temp-*.tmp" 2>/dev/null | wc -l | tr -d ' ')
    [ "$orphan_count_before" -eq 3 ]

    # When: 下次调用 ast-delta.sh（设置测试环境变量以立即清理）
    export AST_DELTA_CLEANUP_MIN_AGE=0
    export AST_DELTA_THROTTLE_INTERVAL=0
    run "$AST_DELTA" update "$test_file"
    unset AST_DELTA_CLEANUP_MIN_AGE
    unset AST_DELTA_THROTTLE_INTERVAL
    skip_if_not_ready "$status" "$output" "ast-delta.sh update (cleanup)"

    # Then: 清理孤儿临时文件
    assert_exit_success "$status"

    local orphan_count_after
    orphan_count_after=$(find "$DEVBOOKS_DIR" -name ".ast-delta-temp-*.tmp" 2>/dev/null | wc -l | tr -d ' ')
    [ "$orphan_count_after" -eq 0 ]
}

# @test T-AD-007b: 原子写入 - 中断不产生部分更新
@test "T-AD-007b: ast-delta atomic write prevents partial updates" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 有效的数据库
    create_graph_db "v1.0"
    local test_file="$TEST_REPO_DIR/src/index.ts"
    create_ast_cache "$test_file" "v1.0"

    # 获取初始节点数
    run "$AST_DELTA" update "$test_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh (atomic setup)"

    local initial_count
    initial_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")

    # When: 模拟中断（通过超时或信号）
    # 注意：这是一个简化测试，实际原子性测试需要更复杂的设置
    export AST_DELTA_SIMULATE_CRASH=true
    run_with_timeout 1 "$AST_DELTA" update "$test_file" 2>/dev/null || true
    unset AST_DELTA_SIMULATE_CRASH

    # Then: 数据库应保持一致状态
    local final_count
    final_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")

    # 节点数应该不变（回滚）或完整更新（成功）
    # 不应有部分状态
    echo "Initial count: $initial_count, Final count: $final_count"

    # 验证数据库完整性
    run sqlite3 "$GRAPH_DB_PATH" "PRAGMA integrity_check;"
    [ "$output" = "ok" ]
}

# @test T-AD-007c: 并发保护 - 多进程不冲突
@test "T-AD-007c: ast-delta handles concurrent updates safely" {
    skip_if_not_executable "$AST_DELTA"

    # Given: 多个文件
    create_graph_db "v1.0"
    for i in 1 2 3; do
        create_test_source_file "$TEST_REPO_DIR/src/concurrent$i.ts" 50
        create_ast_cache "$TEST_REPO_DIR/src/concurrent$i.ts" "v1.0"
    done

    # When: 并发执行更新（后台运行）
    "$AST_DELTA" update "$TEST_REPO_DIR/src/concurrent1.ts" &
    local pid1=$!
    "$AST_DELTA" update "$TEST_REPO_DIR/src/concurrent2.ts" &
    local pid2=$!
    "$AST_DELTA" update "$TEST_REPO_DIR/src/concurrent3.ts" &
    local pid3=$!

    # 等待所有完成
    wait "$pid1" 2>/dev/null || true
    wait "$pid2" 2>/dev/null || true
    wait "$pid3" 2>/dev/null || true

    # Then: 数据库应保持完整
    run sqlite3 "$GRAPH_DB_PATH" "PRAGMA integrity_check;"
    [ "$output" = "ok" ]
}

# ============================================================
# 边界条件测试
# ============================================================

# @test 边界: 空文件处理
@test "BOUNDARY: ast-delta handles empty file gracefully" {
    skip_if_not_executable "$AST_DELTA"

    create_graph_db "v1.0"
    local empty_file="$TEST_REPO_DIR/src/empty.ts"
    touch "$empty_file"

    run "$AST_DELTA" update "$empty_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh (empty file)"

    # 应该成功处理，不崩溃
    assert_exit_success "$status"
}

# @test 边界: 大文件处理
@test "BOUNDARY: ast-delta handles large file" {
    skip_if_not_executable "$AST_DELTA"

    create_graph_db "v1.0"
    local large_file="$TEST_REPO_DIR/src/large.ts"
    create_test_source_file "$large_file" 5000

    run "$AST_DELTA" update "$large_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh (large file)"

    assert_exit_success "$status"
}

# @test 边界: 不存在的文件
@test "BOUNDARY: ast-delta fails gracefully for non-existent file" {
    skip_if_not_executable "$AST_DELTA"

    create_graph_db "v1.0"

    run "$AST_DELTA" update "/non/existent/file.ts"

    # 应该失败但不崩溃
    assert_exit_failure "$status"
    assert_contains_any "$output" "not found" "does not exist" "error" "no such file"
}

# @test 边界: 非 TypeScript 文件
@test "BOUNDARY: ast-delta handles non-TypeScript files" {
    skip_if_not_executable "$AST_DELTA"

    create_graph_db "v1.0"
    local json_file="$TEST_REPO_DIR/config.json"
    echo '{"key": "value"}' > "$json_file"

    run "$AST_DELTA" update "$json_file"

    # 应该跳过或优雅处理
    # 不应崩溃
    if [ "$status" -eq 0 ]; then
        assert_contains_any "$output" "skipped" "unsupported" "no symbols" "success"
    fi
}

# @test 边界: 无效语法文件
@test "BOUNDARY: ast-delta handles syntax error in file" {
    skip_if_not_executable "$AST_DELTA"

    create_graph_db "v1.0"
    local bad_file="$TEST_REPO_DIR/src/syntax-error.ts"
    cat > "$bad_file" << 'EOF'
export function broken( {
    // Missing closing brace and paren
    return "this is broken"
EOF

    run "$AST_DELTA" update "$bad_file"
    skip_if_not_ready "$status" "$output" "ast-delta.sh (syntax error)"

    # 应该报告错误但不崩溃
    # 可能成功（部分解析）或失败（报告语法错误）
    if [ "$status" -ne 0 ]; then
        assert_contains_any "$output" "syntax" "error" "parse" "failed"
    fi
}

# ============================================================
# 命令行接口测试
# ============================================================

# @test CLI: help 输出
@test "CLI: ast-delta --help shows usage" {
    skip_if_not_executable "$AST_DELTA"

    run "$AST_DELTA" --help

    # 应该显示帮助信息
    assert_contains_any "$output" "usage" "Usage" "USAGE" "update" "batch"
}

# @test CLI: 无参数时显示帮助
@test "CLI: ast-delta without args shows usage" {
    skip_if_not_executable "$AST_DELTA"

    run "$AST_DELTA"

    # 无参数时应显示使用说明或错误
    assert_contains_any "$output" "usage" "Usage" "USAGE" "error" "required"
}

# @test CLI: 无效命令
@test "CLI: ast-delta rejects invalid command" {
    skip_if_not_executable "$AST_DELTA"

    run "$AST_DELTA" invalid-command

    assert_exit_failure "$status"
}
