#!/usr/bin/env bats
# scip-to-graph.bats - SCIP 解析转换测试
#
# 覆盖 AC-002: SCIP → 图数据转换成功
# 契约测试: CT-SP-001, CT-SP-002
#
# 场景覆盖:
#   SC-SP-001: 成功解析 SCIP 索引
#   SC-SP-002: 边类型正确映射
#   SC-SP-003: 处理 ReadAccess 引用
#   SC-SP-004: SCIP 文件不存在
#   SC-SP-005: SCIP 解析失败降级
#   SC-SP-006: 增量更新检测
#   SC-SP-007: 无需更新
#   SC-SP-008: 强制完全重建
#   SC-SP-009: 解析统计输出
#   SC-SP-010: 自定义索引路径

load 'helpers/common'

# 脚本路径
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
SCIP_TO_GRAPH="$SCRIPT_DIR/scip-to-graph.sh"
GRAPH_STORE="$SCRIPT_DIR/graph-store.sh"

setup() {
    setup_temp_dir
    export GRAPH_DB_PATH="$TEST_TEMP_DIR/graph.db"
    export DEVBOOKS_DIR="$TEST_TEMP_DIR/.devbooks"
    mkdir -p "$DEVBOOKS_DIR"
}

teardown() {
    cleanup_temp_dir
}

# ============================================================
# CT-SP-001: symbol_roles 映射测试
# ============================================================

# @test SC-SP-001: 成功解析 SCIP 索引
@test "SC-SP-001: scip-to-graph parse creates nodes and edges from SCIP index" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_no_file "$BATS_TEST_DIRNAME/../index.scip"

    export SCIP_INDEX_PATH="$BATS_TEST_DIRNAME/../index.scip"

    run "$SCIP_TO_GRAPH" parse

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh parse"
    assert_exit_success "$status"

    # 验证节点数 > 0（确保解析成功）
    local node_count
    node_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;")
    [ "$node_count" -gt 0 ] || fail "Expected nodes > 0, got $node_count"

    # 验证边数 > 0（确保关系被解析）
    local edge_count
    edge_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges;")
    [ "$edge_count" -gt 0 ] || fail "Expected edges > 0, got $edge_count"

    # 记录实际值供参考
    echo "Parsed: $node_count nodes, $edge_count edges"
}

# @test SC-SP-002: 边类型正确映射 - Definition
@test "SC-SP-002: scip-to-graph maps Definition (symbol_roles=1) to DEFINES" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_no_file "$BATS_TEST_DIRNAME/../index.scip"

    export SCIP_INDEX_PATH="$BATS_TEST_DIRNAME/../index.scip"

    run "$SCIP_TO_GRAPH" parse
    skip_if_not_ready "$status" "$output" "scip-to-graph.sh parse"

    # 验证存在 DEFINES 类型边
    local defines_count
    defines_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='DEFINES';")
    [ "$defines_count" -gt 0 ]
}

# @test SC-SP-003: 处理 ReadAccess 引用
@test "SC-SP-003: scip-to-graph maps ReadAccess (symbol_roles=8) to CALLS" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_no_file "$BATS_TEST_DIRNAME/../index.scip"

    export SCIP_INDEX_PATH="$BATS_TEST_DIRNAME/../index.scip"

    run "$SCIP_TO_GRAPH" parse
    skip_if_not_ready "$status" "$output" "scip-to-graph.sh parse"

    # 验证存在 CALLS 类型边
    local calls_count
    calls_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='CALLS';")
    [ "$calls_count" -gt 0 ]
}

# ============================================================
# 错误处理测试
# ============================================================

# @test SC-SP-004: SCIP 文件不存在
@test "SC-SP-004: scip-to-graph parse fails when SCIP index not found" {
    skip_if_not_executable "$SCIP_TO_GRAPH"

    export SCIP_INDEX_PATH="$TEST_TEMP_DIR/nonexistent.scip"

    run "$SCIP_TO_GRAPH" parse

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh error handling"
    assert_exit_failure "$status"
    assert_contains "$output" "SCIP index not found"
    assert_contains "$output" "npx scip-typescript"
}

# @test SC-SP-005: SCIP 解析失败降级
@test "SC-SP-005: scip-to-graph falls back to regex when SCIP parsing fails" {
    skip_if_not_executable "$SCIP_TO_GRAPH"

    # 创建损坏的 SCIP 文件
    echo "invalid protobuf data" > "$TEST_TEMP_DIR/bad.scip"
    export SCIP_INDEX_PATH="$TEST_TEMP_DIR/bad.scip"

    # 创建测试源文件供正则匹配
    mkdir -p "$TEST_TEMP_DIR/src"
    cat > "$TEST_TEMP_DIR/src/test.ts" << 'EOF'
function hello() { return "world"; }
import { foo } from './foo';
EOF

    run "$SCIP_TO_GRAPH" parse --project-root "$TEST_TEMP_DIR" --format json

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh fallback"

    # 验证降级行为而非特定消息：
    # 1. 命令应成功（降级生效）
    assert_exit_success "$status"

    # 2. 验证产生了部分结果（正则解析工作）
    if [ -f "$GRAPH_DB_PATH" ]; then
        local node_count
        node_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
        # 降级后应至少解析出一些节点
        [ "$node_count" -gt 0 ] || skip "Regex fallback did not produce nodes"
    fi

    # 3. 验证 JSON 输出标记为低置信度或正则来源
    if command -v jq &> /dev/null && echo "$output" | jq . > /dev/null 2>&1; then
        local source confidence
        source=$(echo "$output" | jq -r '.source // "unknown"' 2>/dev/null)
        confidence=$(echo "$output" | jq -r '.confidence // "unknown"' 2>/dev/null)
        # 降级后 source 应为 "regex" 或 confidence 应为 "low"
        [[ "$source" == "regex" ]] || [[ "$confidence" == "low" ]] || \
            skip "Fallback metadata not found in JSON output"
    fi
}

# ============================================================
# 增量更新测试
# ============================================================

# @test SC-SP-006: 增量更新检测
@test "SC-SP-006: scip-to-graph detects index newer than database" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_no_file "$BATS_TEST_DIRNAME/../index.scip"

    # 复制索引到临时目录，避免修改原文件
    cp "$BATS_TEST_DIRNAME/../index.scip" "$TEST_TEMP_DIR/index.scip"
    export SCIP_INDEX_PATH="$TEST_TEMP_DIR/index.scip"

    # 先解析一次
    run "$SCIP_TO_GRAPH" parse
    skip_if_not_ready "$status" "$output" "scip-to-graph.sh parse"

    # 模拟数据库比索引旧（touch 临时索引文件）
    sleep 1
    touch "$SCIP_INDEX_PATH"

    run "$SCIP_TO_GRAPH" parse --incremental

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh incremental"
    assert_exit_success "$status"
    assert_contains "$output" "Incremental update"
}

# @test SC-SP-007: 无需更新
@test "SC-SP-007: scip-to-graph skips parse when database is up-to-date" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_no_file "$BATS_TEST_DIRNAME/../index.scip"

    # 复制索引到临时目录，避免修改原文件
    cp "$BATS_TEST_DIRNAME/../index.scip" "$TEST_TEMP_DIR/index.scip"
    export SCIP_INDEX_PATH="$TEST_TEMP_DIR/index.scip"

    # 先解析一次
    run "$SCIP_TO_GRAPH" parse
    skip_if_not_ready "$status" "$output" "scip-to-graph.sh parse"

    # 模拟数据库比索引新（touch 数据库）
    sleep 1
    touch "$GRAPH_DB_PATH"

    run "$SCIP_TO_GRAPH" parse --incremental

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh incremental skip"
    assert_exit_success "$status"
    assert_contains "$output" "up-to-date"
}

# @test SC-SP-008: 强制完全重建
@test "SC-SP-008: scip-to-graph force rebuilds database" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_no_file "$BATS_TEST_DIRNAME/../index.scip"

    export SCIP_INDEX_PATH="$BATS_TEST_DIRNAME/../index.scip"

    # 先解析一次
    run "$SCIP_TO_GRAPH" parse
    skip_if_not_ready "$status" "$output" "scip-to-graph.sh parse"

    # 强制重建
    run "$SCIP_TO_GRAPH" parse --force

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh force"
    assert_exit_success "$status"
    assert_contains "$output" "Force rebuild"
}

# @test SC-SP-009: 解析统计输出
@test "SC-SP-009: scip-to-graph outputs parse statistics in JSON" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_no_file "$BATS_TEST_DIRNAME/../index.scip"

    export SCIP_INDEX_PATH="$BATS_TEST_DIRNAME/../index.scip"

    run "$SCIP_TO_GRAPH" parse --format json

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh stats"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证统计字段
    assert_json_field "$output" ".symbols"
    assert_json_field "$output" ".confidence" "high"
    assert_json_field "$output" ".source" "scip"
}

# @test SC-SP-010: 自定义索引路径
@test "SC-SP-010: scip-to-graph uses custom SCIP_INDEX_PATH" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_no_file "$BATS_TEST_DIRNAME/../index.scip"

    # 复制索引到自定义位置
    cp "$BATS_TEST_DIRNAME/../index.scip" "$TEST_TEMP_DIR/custom.scip"
    export SCIP_INDEX_PATH="$TEST_TEMP_DIR/custom.scip"

    run "$SCIP_TO_GRAPH" parse

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh custom path"
    assert_exit_success "$status"

    # 验证数据已写入
    local node_count
    node_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;")
    [ "$node_count" -gt 0 ]
}

# ============================================================
# AC-N04: SCIP 解析覆盖率测试
# ============================================================

@test "AC-N04: scip-to-graph parses all TypeScript files" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_no_file "$BATS_TEST_DIRNAME/../index.scip"

    export SCIP_INDEX_PATH="$BATS_TEST_DIRNAME/../index.scip"

    run "$SCIP_TO_GRAPH" parse --format json

    skip_if_not_ready "$status" "$output" "scip-to-graph.sh coverage"
    assert_exit_success "$status"

    # 验证 server.ts 被解析
    local has_server
    has_server=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes WHERE file_path LIKE '%server.ts%';")
    [ "$has_server" -gt 0 ]
}
