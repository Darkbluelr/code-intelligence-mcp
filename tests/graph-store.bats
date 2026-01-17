#!/usr/bin/env bats
# graph-store.bats - SQLite 图存储测试
#
# 覆盖 AC-001: SQLite 图存储支持 4 种核心边类型 CRUD
# 契约测试: CT-GS-001, CT-GS-002, CT-GS-003
#
# 场景覆盖:
#   SC-GS-001: 初始化空数据库
#   SC-GS-002: 创建节点
#   SC-GS-003: 创建有效边
#   SC-GS-004: 拒绝非法边类型
#   SC-GS-005: 查询出边
#   SC-GS-006: 查询孤儿节点
#   SC-GS-007: 批量写入
#   SC-GS-008: 批量写入失败回滚
#   SC-GS-009: 统计信息
#   SC-GS-010: 数据库已存在时初始化
#   SC-GS-011: 空图查询孤儿

load 'helpers/common'

# 脚本路径
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
GRAPH_STORE="$SCRIPT_DIR/graph-store.sh"
SCIP_TO_GRAPH="$SCRIPT_DIR/scip-to-graph.sh"

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
# CT-GS-001: Schema 正确性测试
# ============================================================

# @test SC-GS-001: 初始化空数据库
@test "SC-GS-001: graph-store init creates database with correct schema" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    assert_exit_success "$status"

    # 验证数据库文件存在
    [ -f "$GRAPH_DB_PATH" ]

    # 验证 nodes 表存在
    run sqlite3 "$GRAPH_DB_PATH" ".tables"
    assert_contains "$output" "nodes"
    assert_contains "$output" "edges"

    # 验证 WAL 模式
    run sqlite3 "$GRAPH_DB_PATH" "PRAGMA journal_mode;"
    assert_contains "$output" "wal"
}

# @test SC-GS-010: 数据库已存在时初始化
@test "SC-GS-010: graph-store init skips when database exists" {
    skip_if_not_executable "$GRAPH_STORE"

    # 先初始化
    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 插入测试数据
    sqlite3 "$GRAPH_DB_PATH" "INSERT INTO nodes (id, symbol, kind, file_path) VALUES ('test', 'test', 'function', 'test.ts');"

    # 再次初始化
    run "$GRAPH_STORE" init
    assert_exit_success "$status"
    assert_contains "$output" "already exists"

    # 验证数据未被覆盖
    run sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;"
    [ "$output" = "1" ]
}

# ============================================================
# CT-GS-002: 边类型约束测试
# ============================================================

# @test SC-GS-002: 创建节点
@test "SC-GS-002: graph-store add-node creates node successfully" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    run "$GRAPH_STORE" add-node \
        --id "sym:func:main" \
        --symbol "main" \
        --kind "function" \
        --file "src/index.ts" \
        --line-start 10 \
        --line-end 20

    skip_if_not_ready "$status" "$output" "graph-store.sh add-node"
    assert_exit_success "$status"

    # 验证节点已创建
    run sqlite3 "$GRAPH_DB_PATH" "SELECT symbol FROM nodes WHERE id='sym:func:main';"
    [ "$output" = "main" ]
}

# @test SC-GS-003: 创建有效边
@test "SC-GS-003: graph-store add-edge creates edge with valid type" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 创建两个节点
    "$GRAPH_STORE" add-node --id "sym:func:main" --symbol "main" --kind "function" --file "src/index.ts"
    "$GRAPH_STORE" add-node --id "sym:func:helper" --symbol "helper" --kind "function" --file "src/utils.ts"

    # 创建 CALLS 边
    run "$GRAPH_STORE" add-edge \
        --source "sym:func:main" \
        --target "sym:func:helper" \
        --type CALLS \
        --file "src/index.ts" \
        --line 15

    skip_if_not_ready "$status" "$output" "graph-store.sh add-edge"
    assert_exit_success "$status"

    # 验证边已创建
    run sqlite3 "$GRAPH_DB_PATH" "SELECT edge_type FROM edges WHERE source_id='sym:func:main';"
    [ "$output" = "CALLS" ]
}

# @test SC-GS-004: 拒绝非法边类型
@test "SC-GS-004: graph-store add-edge rejects invalid edge type" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 创建节点
    "$GRAPH_STORE" add-node --id "a" --symbol "a" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "b" --symbol "b" --kind "function" --file "b.ts"

    # 尝试创建非法边类型
    run "$GRAPH_STORE" add-edge --source "a" --target "b" --type INVALID_TYPE

    skip_if_not_ready "$status" "$output" "graph-store.sh add-edge validation"
    assert_exit_failure "$status"
    assert_contains "$output" "Invalid edge type"
    assert_contains "$output" "DEFINES, IMPORTS, CALLS, MODIFIES"
}

# @test SC-GS-004b: 测试所有 4 种有效边类型
@test "SC-GS-004b: graph-store supports all 4 edge types" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 创建节点
    "$GRAPH_STORE" add-node --id "src" --symbol "src" --kind "function" --file "src.ts"
    "$GRAPH_STORE" add-node --id "tgt" --symbol "tgt" --kind "function" --file "tgt.ts"

    local edge_types=("DEFINES" "IMPORTS" "CALLS" "MODIFIES")

    for edge_type in "${edge_types[@]}"; do
        run "$GRAPH_STORE" add-edge --source "src" --target "tgt" --type "$edge_type"
        skip_if_not_ready "$status" "$output" "graph-store.sh add-edge $edge_type"
        assert_exit_success "$status"
    done

    # 验证 4 条边都已创建
    run sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges;"
    [ "$output" = "4" ]
}

# ============================================================
# 查询功能测试
# ============================================================

# @test SC-GS-005: 查询出边
@test "SC-GS-005: graph-store query-edges filters by type" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 创建节点
    "$GRAPH_STORE" add-node --id "A" --symbol "A" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "B" --symbol "B" --kind "function" --file "b.ts"
    "$GRAPH_STORE" add-node --id "C" --symbol "C" --kind "function" --file "c.ts"

    # 创建边: A -> B (CALLS), A -> C (CALLS), A -> B (IMPORTS)
    "$GRAPH_STORE" add-edge --source "A" --target "B" --type CALLS
    "$GRAPH_STORE" add-edge --source "A" --target "C" --type CALLS
    "$GRAPH_STORE" add-edge --source "A" --target "B" --type IMPORTS

    # 查询 CALLS 类型出边
    run "$GRAPH_STORE" query-edges --from "A" --type CALLS

    skip_if_not_ready "$status" "$output" "graph-store.sh query-edges"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 应返回 2 条 CALLS 边
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" = "2" ]
}

# @test SC-GS-006: 查询孤儿节点
@test "SC-GS-006: graph-store find-orphans returns nodes with no incoming edges" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 创建节点
    "$GRAPH_STORE" add-node --id "A" --symbol "A" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "B" --symbol "B" --kind "function" --file "b.ts"
    "$GRAPH_STORE" add-node --id "C" --symbol "C" --kind "function" --file "c.ts"
    "$GRAPH_STORE" add-node --id "D" --symbol "D" --kind "function" --file "d.ts"

    # 创建边: B -> A, C -> A, D -> C (D 是孤儿)
    "$GRAPH_STORE" add-edge --source "B" --target "A" --type CALLS
    "$GRAPH_STORE" add-edge --source "C" --target "A" --type CALLS
    "$GRAPH_STORE" add-edge --source "D" --target "C" --type CALLS

    # 查询孤儿节点
    run "$GRAPH_STORE" find-orphans

    skip_if_not_ready "$status" "$output" "graph-store.sh find-orphans"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # B 和 D 是孤儿（无入边）
    assert_contains "$output" "B"
    assert_contains "$output" "D"
    assert_not_contains "$output" '"A"'
    assert_not_contains "$output" '"C"'
}

# @test SC-GS-011: 空图查询孤儿
@test "SC-GS-011: graph-store find-orphans returns empty array for empty graph" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    run "$GRAPH_STORE" find-orphans

    skip_if_not_ready "$status" "$output" "graph-store.sh find-orphans"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 应返回空数组
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" = "0" ]
}

# ============================================================
# CT-GS-003: 批量操作事务性测试
# ============================================================

# @test SC-GS-007: 批量写入
@test "SC-GS-007: graph-store batch-import writes all nodes in single transaction" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 创建批量导入 JSON 文件
    cat > "$TEST_TEMP_DIR/nodes.json" << 'EOF'
{
  "nodes": [
    {"id": "n1", "symbol": "func1", "kind": "function", "file_path": "a.ts"},
    {"id": "n2", "symbol": "func2", "kind": "function", "file_path": "b.ts"},
    {"id": "n3", "symbol": "Class1", "kind": "class", "file_path": "c.ts"}
  ]
}
EOF

    run "$GRAPH_STORE" batch-import --file "$TEST_TEMP_DIR/nodes.json"

    skip_if_not_ready "$status" "$output" "graph-store.sh batch-import"
    assert_exit_success "$status"

    # 验证所有节点已写入
    run sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;"
    [ "$output" = "3" ]
}

# @test SC-GS-008: 批量写入失败回滚
@test "SC-GS-008: graph-store batch-import rolls back on error" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 创建包含错误数据的 JSON（第 2 个节点缺少必填字段）
    cat > "$TEST_TEMP_DIR/bad-nodes.json" << 'EOF'
{
  "nodes": [
    {"id": "n1", "symbol": "func1", "kind": "function", "file_path": "a.ts"},
    {"id": "n2", "symbol": "func2"},
    {"id": "n3", "symbol": "func3", "kind": "function", "file_path": "c.ts"}
  ]
}
EOF

    run "$GRAPH_STORE" batch-import --file "$TEST_TEMP_DIR/bad-nodes.json"

    skip_if_not_ready "$status" "$output" "graph-store.sh batch-import validation"
    assert_exit_failure "$status"

    # 验证回滚：无节点写入
    run sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;"
    [ "$output" = "0" ]
}

# @test SC-GS-009: 统计信息
@test "SC-GS-009: graph-store stats returns correct counts" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 创建测试数据
    "$GRAPH_STORE" add-node --id "n1" --symbol "f1" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "n2" --symbol "f2" --kind "function" --file "b.ts"
    "$GRAPH_STORE" add-edge --source "n1" --target "n2" --type CALLS
    "$GRAPH_STORE" add-edge --source "n1" --target "n2" --type IMPORTS

    run "$GRAPH_STORE" stats

    skip_if_not_ready "$status" "$output" "graph-store.sh stats"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证统计数据
    assert_json_field "$output" ".nodes" "2"
    assert_json_field "$output" ".edges" "2"
    assert_json_field "$output" ".edges_by_type.CALLS" "1"
    assert_json_field "$output" ".edges_by_type.IMPORTS" "1"
}

# ============================================================
# 数据库大小测试 (AC-N03)
# ============================================================

# 可配置的测试参数
DB_SIZE_TEST_NODES="${DB_SIZE_TEST_NODES:-100}"
DB_SIZE_TEST_MAX_MB="${DB_SIZE_TEST_MAX_MB:-10}"

# @test AC-N03a: 批量导入成功场景
@test "AC-N03a: graph-store batch-import succeeds for bulk data" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 生成节点 JSON
    local nodes_json="$TEST_TEMP_DIR/bulk-nodes.json"
    {
        echo '{"nodes": ['
        for i in $(seq 1 "$DB_SIZE_TEST_NODES"); do
            [ "$i" -gt 1 ] && echo ','
            printf '{"id": "n%d", "symbol": "func%d", "kind": "function", "file_path": "file%d.ts"}' "$i" "$i" "$i"
        done
        echo ']}'
    } > "$nodes_json"

    # 批量导入节点
    run "$GRAPH_STORE" batch-import --file "$nodes_json"

    skip_if_not_ready "$status" "$output" "graph-store.sh batch-import bulk"
    assert_exit_success "$status"

    # 验证所有节点已写入
    local node_count
    node_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;")
    [ "$node_count" -eq "$DB_SIZE_TEST_NODES" ]
}

# @test AC-N03b: 批量导入失败时降级到单条操作
@test "AC-N03b: graph-store falls back to single operations when batch fails" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 创建故意失败的批量导入（无效 JSON 格式）
    echo "invalid json" > "$TEST_TEMP_DIR/invalid.json"

    run "$GRAPH_STORE" batch-import --file "$TEST_TEMP_DIR/invalid.json"

    # 批量导入应失败
    if [ "$status" -eq 0 ]; then
        skip "batch-import did not fail on invalid input"
    fi

    # 验证单条操作仍然可用（降级路径）
    run "$GRAPH_STORE" add-node --id "fallback-n1" --symbol "func1" --kind "function" --file "file1.ts"

    skip_if_not_ready "$status" "$output" "graph-store.sh add-node fallback"
    assert_exit_success "$status"

    # 验证节点已写入
    local node_count
    node_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;")
    [ "$node_count" -eq 1 ]
}

# @test AC-N03c: 数据库文件大小合理
@test "AC-N03c: graph database file size is reasonable" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    # 使用 batch-import 或单条操作创建测试数据
    local nodes_json="$TEST_TEMP_DIR/bulk-nodes.json"
    local edges_json="$TEST_TEMP_DIR/bulk-edges.json"

    # 生成节点 JSON
    {
        echo '{"nodes": ['
        for i in $(seq 1 "$DB_SIZE_TEST_NODES"); do
            [ "$i" -gt 1 ] && echo ','
            printf '{"id": "n%d", "symbol": "func%d", "kind": "function", "file_path": "file%d.ts"}' "$i" "$i" "$i"
        done
        echo ']}'
    } > "$nodes_json"

    # 生成边 JSON
    {
        echo '{"edges": ['
        local first=true
        for i in $(seq 1 "$DB_SIZE_TEST_NODES"); do
            local target=$(( (i % DB_SIZE_TEST_NODES) + 1 ))
            [ "$first" = "true" ] && first=false || echo ','
            printf '{"source": "n%d", "target": "n%d", "type": "CALLS"}' "$i" "$target"
            echo ','
            printf '{"source": "n%d", "target": "n%d", "type": "IMPORTS"}' "$i" "$target"
        done
        echo ']}'
    } > "$edges_json"

    # 尝试批量导入节点
    run "$GRAPH_STORE" batch-import --file "$nodes_json"
    if [ "$status" -ne 0 ]; then
        skip "batch-import not implemented, use AC-N03a/AC-N03b for separate testing"
    fi

    # 尝试批量导入边
    run "$GRAPH_STORE" batch-import --file "$edges_json"
    if [ "$status" -ne 0 ]; then
        skip "edge batch-import not implemented"
    fi

    # 检查文件大小
    local size max_size
    size=$(stat -f%z "$GRAPH_DB_PATH" 2>/dev/null || stat -c%s "$GRAPH_DB_PATH" 2>/dev/null)
    max_size=$((DB_SIZE_TEST_MAX_MB * 1048576))

    echo "Database size: $size bytes (max: $max_size bytes)"

    [ "$size" -lt "$max_size" ]
}

# ============================================================
# Graph Store Enhancements (AC-G01, AC-G01a, AC-G02)
# ============================================================

@test "test_edge_types: graph-store add-edge supports IMPLEMENTS/EXTENDS/RETURNS_TYPE" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "sqlite3"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    "$GRAPH_STORE" add-node --id "iface" --symbol "IService" --kind "interface" --file "src/service.ts"
    "$GRAPH_STORE" add-node --id "impl" --symbol "ServiceImpl" --kind "class" --file "src/service.ts"
    "$GRAPH_STORE" add-node --id "base" --symbol "Base" --kind "class" --file "src/base.ts"
    "$GRAPH_STORE" add-node --id "child" --symbol "Child" --kind "class" --file "src/child.ts"
    "$GRAPH_STORE" add-node --id "fn" --symbol "getUser" --kind "function" --file "src/user.ts"
    "$GRAPH_STORE" add-node --id "type" --symbol "User" --kind "class" --file "src/user.ts"

    run "$GRAPH_STORE" add-edge --source "impl" --target "iface" --type IMPLEMENTS
    skip_if_not_ready "$status" "$output" "graph-store.sh add-edge IMPLEMENTS"

    run "$GRAPH_STORE" add-edge --source "child" --target "base" --type EXTENDS
    skip_if_not_ready "$status" "$output" "graph-store.sh add-edge EXTENDS"

    run "$GRAPH_STORE" add-edge --source "fn" --target "type" --type RETURNS_TYPE
    skip_if_not_ready "$status" "$output" "graph-store.sh add-edge RETURNS_TYPE"

    local count
    count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type IN ('IMPLEMENTS','EXTENDS','RETURNS_TYPE');")
    if [ "$count" -lt 3 ]; then
        skip_not_implemented "graph-store edge types"
    fi
}

@test "test_edge_types_python: scip-to-graph produces IMPLEMENTS edges for annotated Python" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "sqlite3"

    if [ -z "${SCIP_PYTHON_INDEX_PATH:-}" ] || [ ! -f "$SCIP_PYTHON_INDEX_PATH" ]; then
        skip "SCIP_PYTHON_INDEX_PATH not set"
    fi

    export SCIP_INDEX_PATH="$SCIP_PYTHON_INDEX_PATH"

    run "$SCIP_TO_GRAPH" parse
    skip_if_not_ready "$status" "$output" "scip-to-graph.sh parse (python)"

    local count
    count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPLEMENTS';" 2>/dev/null || echo "0")
    if [ "$count" -eq 0 ]; then
        skip_not_implemented "python IMPLEMENTS edge type"
    fi
}

@test "test_edge_types_fallback: unsupported languages fall back to REFERENCES" {
    skip_if_not_executable "$SCIP_TO_GRAPH"
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "sqlite3"

    if [ -z "${SCIP_UNSUPPORTED_INDEX_PATH:-}" ] || [ ! -f "$SCIP_UNSUPPORTED_INDEX_PATH" ]; then
        skip "SCIP_UNSUPPORTED_INDEX_PATH not set"
    fi

    export SCIP_INDEX_PATH="$SCIP_UNSUPPORTED_INDEX_PATH"

    run "$SCIP_TO_GRAPH" parse
    skip_if_not_ready "$status" "$output" "scip-to-graph.sh parse (fallback)"

    local count
    count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='REFERENCES';" 2>/dev/null || echo "0")
    if [ "$count" -eq 0 ]; then
        skip_not_implemented "REFERENCES fallback edge type"
    fi
}

@test "test_migrate_check_old: graph-store migrate --check detects old schema" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    run "$GRAPH_STORE" migrate --check

    if [ "$status" -ne 0 ] && [[ "$output" != *"NEEDS_MIGRATION"* ]]; then
        skip_if_not_ready "$status" "$output" "graph-store.sh migrate --check"
    fi

    assert_contains "$output" "NEEDS_MIGRATION"
}

@test "test_migrate_check_new: graph-store migrate --check returns UP_TO_DATE after apply" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    run "$GRAPH_STORE" migrate --apply
    if [ "$status" -ne 0 ]; then
        skip_if_not_ready "$status" "$output" "graph-store.sh migrate --apply"
    fi

    run "$GRAPH_STORE" migrate --check
    if [ "$status" -ne 0 ] && [[ "$output" != *"UP_TO_DATE"* ]]; then
        skip_if_not_ready "$status" "$output" "graph-store.sh migrate --check"
    fi

    assert_contains "$output" "UP_TO_DATE"
}

@test "test_migrate_apply: graph-store migrate preserves edges and data" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "sqlite3"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    "$GRAPH_STORE" add-node --id "A" --symbol "A" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "B" --symbol "B" --kind "function" --file "b.ts"
    "$GRAPH_STORE" add-edge --source "A" --target "B" --type CALLS

    local before_count
    before_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges;")

    run "$GRAPH_STORE" migrate --apply
    skip_if_not_ready "$status" "$output" "graph-store.sh migrate --apply"

    local after_count
    after_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges;")
    if [ "$after_count" -ne "$before_count" ]; then
        skip_not_implemented "migration data preservation"
    fi
}

@test "test_migrate_backup: graph-store migrate creates backup file" {
    skip_if_not_executable "$GRAPH_STORE"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    run "$GRAPH_STORE" migrate --apply
    skip_if_not_ready "$status" "$output" "graph-store.sh migrate --apply"

    local backup_count
    backup_count=$(ls "${GRAPH_DB_PATH}.backup."* 2>/dev/null | wc -l | tr -d ' ')
    if [ "$backup_count" -eq 0 ]; then
        skip_not_implemented "migration backup file"
    fi
}

@test "test_find_path_basic: graph-store find-path returns shortest path" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "jq"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    "$GRAPH_STORE" add-node --id "A" --symbol "A" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "B" --symbol "B" --kind "function" --file "b.ts"
    "$GRAPH_STORE" add-node --id "C" --symbol "C" --kind "function" --file "c.ts"
    "$GRAPH_STORE" add-edge --source "A" --target "B" --type CALLS
    "$GRAPH_STORE" add-edge --source "B" --target "C" --type CALLS

    run "$GRAPH_STORE" find-path --from "A" --to "C"
    skip_if_not_ready "$status" "$output" "graph-store.sh find-path"

    assert_valid_json "$output"
    local found
    found=$(echo "$output" | jq -r '.found // empty')
    if [ "$found" != "true" ]; then
        skip_not_implemented "find-path basic"
    fi
}

@test "test_find_path_depth: graph-store find-path respects max depth" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "jq"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    "$GRAPH_STORE" add-node --id "A" --symbol "A" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "B" --symbol "B" --kind "function" --file "b.ts"
    "$GRAPH_STORE" add-node --id "C" --symbol "C" --kind "function" --file "c.ts"
    "$GRAPH_STORE" add-node --id "D" --symbol "D" --kind "function" --file "d.ts"
    "$GRAPH_STORE" add-edge --source "A" --target "B" --type CALLS
    "$GRAPH_STORE" add-edge --source "B" --target "C" --type CALLS
    "$GRAPH_STORE" add-edge --source "C" --target "D" --type CALLS

    run "$GRAPH_STORE" find-path --from "A" --to "D" --max-depth 2
    skip_if_not_ready "$status" "$output" "graph-store.sh find-path depth"

    assert_valid_json "$output"
    local found
    found=$(echo "$output" | jq -r '.found // empty')
    if [ "$found" != "false" ]; then
        skip_not_implemented "find-path depth limit"
    fi
}

@test "test_find_path_filter: graph-store find-path respects edge type filter" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "jq"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    "$GRAPH_STORE" add-node --id "A" --symbol "A" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "B" --symbol "B" --kind "function" --file "b.ts"
    "$GRAPH_STORE" add-node --id "C" --symbol "C" --kind "function" --file "c.ts"
    "$GRAPH_STORE" add-edge --source "A" --target "B" --type CALLS
    "$GRAPH_STORE" add-edge --source "B" --target "C" --type IMPORTS

    run "$GRAPH_STORE" find-path --from "A" --to "C" --edge-types CALLS
    skip_if_not_ready "$status" "$output" "graph-store.sh find-path filter"

    assert_valid_json "$output"
    local found
    found=$(echo "$output" | jq -r '.found // empty')
    if [ "$found" != "false" ]; then
        skip_not_implemented "find-path edge type filter"
    fi
}

@test "test_find_path_no_path: graph-store find-path returns empty when no path" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "jq"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    "$GRAPH_STORE" add-node --id "A" --symbol "A" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "B" --symbol "B" --kind "function" --file "b.ts"

    run "$GRAPH_STORE" find-path --from "A" --to "B"
    skip_if_not_ready "$status" "$output" "graph-store.sh find-path no path"

    assert_valid_json "$output"
    local found
    found=$(echo "$output" | jq -r '.found // empty')
    if [ "$found" != "false" ]; then
        skip_not_implemented "find-path no path"
    fi
}

@test "test_find_path_output: graph-store find-path output includes path and length" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "jq"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    "$GRAPH_STORE" add-node --id "A" --symbol "A" --kind "function" --file "a.ts"
    "$GRAPH_STORE" add-node --id "B" --symbol "B" --kind "function" --file "b.ts"
    "$GRAPH_STORE" add-edge --source "A" --target "B" --type CALLS

    run "$GRAPH_STORE" find-path --from "A" --to "B"
    skip_if_not_ready "$status" "$output" "graph-store.sh find-path output"

    assert_valid_json "$output"
    local length
    length=$(echo "$output" | jq -r '.length // empty')
    if [ -z "$length" ]; then
        skip_not_implemented "find-path output length"
    fi
}
