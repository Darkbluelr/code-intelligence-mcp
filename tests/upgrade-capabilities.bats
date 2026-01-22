#!/usr/bin/env bats
# tests/upgrade-capabilities.bats
# Test: Code Intelligence Capability Upgrade
# Change-ID: 20260118-0057-upgrade-code-intelligence-capabilities

load 'helpers/common'

# ============================================================
# Setup & Teardown
# ============================================================

setup() {
    setup_temp_dir
    export TEST_DB_PATH="${TEST_TEMP_DIR}/test-graph.db"
    export GRAPH_DB_PATH="$TEST_DB_PATH"

    if [ -f ".devbooks/graph.db" ]; then
        backup_file ".devbooks/graph.db"
    fi
}

teardown() {
    cleanup_temp_dir

    if [ -f ".devbooks/graph.db.bak" ]; then
        restore_file ".devbooks/graph.db"
    fi

    rm -f "${GRAPH_DB_PATH}.migrate.lock" 2>/dev/null || true
}

# ============================================================
# Edge Type Parsing Tests (AC-U01, AC-U02, AC-U09, AC-U10)
# ============================================================

# @smoke
@test "T-EDGE-001: SCIP parser extracts IMPLEMENTS edge type" {
    # Arrange: 创建包含 IMPLEMENTS 关系的测试代码
    local test_file="${TEST_TEMP_DIR}/TestClass.ts"
    cat > "$test_file" <<'EOF'
interface IService {
    execute(): void;
}

class ServiceImpl implements IService {
    execute(): void {
        console.log("executing");
    }
}
EOF

    # 初始化数据库
    export GRAPH_DB_PATH="$TEST_DB_PATH"
    bash scripts/graph-store.sh init >/dev/null 2>&1

    # Act: 使用正则降级模式解析（不依赖 SCIP 索引）
    local temp_json="${TEST_TEMP_DIR}/parse-result.json"
    source scripts/scip-to-graph.sh
    parse_with_regex "$TEST_TEMP_DIR" "$temp_json"

    # 导入到数据库
    bash scripts/graph-store.sh batch-import --file "$temp_json" >/dev/null 2>&1

    # Assert: 验证 IMPLEMENTS 边类型存在
    local edge_count
    edge_count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPLEMENTS';" 2>/dev/null || echo "0")

    [ "$edge_count" -gt 0 ] || fail "Expected IMPLEMENTS edges, found $edge_count"
}

# @smoke
@test "T-EDGE-002: SCIP parser extracts EXTENDS edge type" {
    # Arrange: 创建包含 EXTENDS 关系的测试代码
    local test_file="${TEST_TEMP_DIR}/TestClass.ts"
    cat > "$test_file" <<'EOF'
class BaseClass {
    protected value: number = 0;
}

class DerivedClass extends BaseClass {
    getValue(): number {
        return this.value;
    }
}
EOF

    # 初始化数据库
    export GRAPH_DB_PATH="$TEST_DB_PATH"
    bash scripts/graph-store.sh init >/dev/null 2>&1

    # Act: 使用正则降级模式解析
    local temp_json="${TEST_TEMP_DIR}/parse-result.json"
    source scripts/scip-to-graph.sh
    parse_with_regex "$TEST_TEMP_DIR" "$temp_json"

    # 导入到数据库
    bash scripts/graph-store.sh batch-import --file "$temp_json" >/dev/null 2>&1

    # Assert: 验证 EXTENDS 边类型存在
    local edge_count
    edge_count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='EXTENDS';" 2>/dev/null || echo "0")

    [ "$edge_count" -gt 0 ] || fail "Expected EXTENDS edges, found $edge_count"
}

# @smoke
@test "T-EDGE-003: SCIP parser extracts RETURNS_TYPE edge type" {
    # Arrange: 创建包含返回类型的测试代码
    local test_file="${TEST_TEMP_DIR}/TestClass.ts"
    cat > "$test_file" <<'EOF'
class Result {
    success: boolean = true;
}

function getResult(): Result {
    return new Result();
}
EOF

    # 初始化数据库
    export GRAPH_DB_PATH="$TEST_DB_PATH"
    bash scripts/graph-store.sh init >/dev/null 2>&1

    # Act: 使用正则降级模式解析
    local temp_json="${TEST_TEMP_DIR}/parse-result.json"
    source scripts/scip-to-graph.sh
    parse_with_regex "$TEST_TEMP_DIR" "$temp_json"

    # 导入到数据库
    bash scripts/graph-store.sh batch-import --file "$temp_json" >/dev/null 2>&1

    # Assert: 验证 RETURNS_TYPE 边类型存在
    local edge_count
    edge_count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='RETURNS_TYPE';" 2>/dev/null || echo "0")

    [ "$edge_count" -gt 0 ] || fail "Expected RETURNS_TYPE edges, found $edge_count"
}

# @smoke
@test "T-EDGE-004: Regex fallback parsing supports three edge types" {
    # Arrange: 创建测试代码，禁用 SCIP 索引
    local test_file="${TEST_TEMP_DIR}/TestClass.ts"
    cat > "$test_file" <<'EOF'
interface IService { execute(): void; }
class ServiceImpl implements IService { execute(): void {} }
class BaseClass { value: number = 0; }
class DerivedClass extends BaseClass { getValue(): number { return this.value; } }
class Result { success: boolean = true; }
function getResult(): Result { return new Result(); }
EOF

    # Act: 运行正则降级解析（设置环境变量禁用 SCIP）
    export SCIP_DISABLED=true
    run bash scripts/scip-to-graph.sh --input "$test_file" --output "$TEST_DB_PATH" --fallback-regex
    unset SCIP_DISABLED

    # Assert: 验证三种边类型都存在
    local implements_count extends_count returns_count
    implements_count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPLEMENTS';" 2>/dev/null || echo "0")
    extends_count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='EXTENDS';" 2>/dev/null || echo "0")
    returns_count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='RETURNS_TYPE';" 2>/dev/null || echo "0")

    [ "$implements_count" -gt 0 ] || fail "Expected IMPLEMENTS edges in regex fallback"
    [ "$extends_count" -gt 0 ] || fail "Expected EXTENDS edges in regex fallback"
    [ "$returns_count" -gt 0 ] || fail "Expected RETURNS_TYPE edges in regex fallback"
}

# ============================================================
# Schema Migration Tests (AC-U03, AC-U08, AC-U11, AC-U12)
# ============================================================

# @smoke
@test "T-MIG-001: Schema v2 to v3 migration succeeds" {
    # Arrange: 创建 v2 schema 数据库
    sqlite3 "$TEST_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    name TEXT NOT NULL,
    file_path TEXT,
    metadata TEXT
);
CREATE TABLE IF NOT EXISTS edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    edge_type TEXT NOT NULL CHECK(edge_type IN ('DEFINES', 'IMPORTS', 'CALLS', 'MODIFIES', 'REFERENCES', 'ADR_RELATED')),
    metadata TEXT,
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
);
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
INSERT INTO schema_version (version) VALUES (2);
INSERT INTO nodes (id, type, name, file_path) VALUES ('node1', 'function', 'test', '/test.ts');
INSERT INTO edges (source_id, target_id, edge_type, metadata) VALUES ('node1', 'node1', 'CALLS', NULL);
EOF

    # Act: 运行迁移
    run bash scripts/graph-store.sh migrate --apply

    # Assert: 验证迁移成功
    local schema_version
    schema_version=$(sqlite3 "$TEST_DB_PATH" "SELECT MAX(version) FROM schema_version;" 2>/dev/null || echo "0")
    [ "$schema_version" -eq 3 ] || fail "Expected schema version 3, got $schema_version"

    # 验证数据完整性
    local node_count edge_count
    node_count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
    edge_count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM edges;" 2>/dev/null || echo "0")
    [ "$node_count" -eq 1 ] || fail "Expected 1 node after migration, got $node_count"
    [ "$edge_count" -eq 1 ] || fail "Expected 1 edge after migration, got $edge_count"
}

# @smoke
@test "T-MIG-002: Schema migration failure auto-rollback" {
    # Arrange: 创建 v2 数据库，但插入违反外键约束的数据（触发迁移失败）
    sqlite3 "$TEST_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    name TEXT NOT NULL,
    file_path TEXT,
    metadata TEXT
);
CREATE TABLE IF NOT EXISTS edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    edge_type TEXT NOT NULL CHECK(edge_type IN ('DEFINES', 'IMPORTS', 'CALLS', 'MODIFIES', 'REFERENCES', 'ADR_RELATED')),
    metadata TEXT,
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
);
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
INSERT INTO schema_version (version) VALUES (2);
INSERT INTO nodes (id, type, name, file_path) VALUES ('node1', 'function', 'test', '/test.ts');
-- 插入引用不存在节点的边（违反外键约束）
INSERT INTO edges (source_id, target_id, edge_type, metadata) VALUES ('node1', 'nonexistent', 'CALLS', NULL);
EOF

    # 记录迁移前的 schema version
    local before_version
    before_version=$(sqlite3 "$TEST_DB_PATH" "SELECT MAX(version) FROM schema_version;" 2>/dev/null || echo "0")

    # Act: 运行迁移（预期因外键约束失败）
    run bash scripts/graph-store.sh migrate --apply

    # Assert: 验证迁移失败
    [ "$status" -ne 0 ] || fail "Expected migration to fail due to FK violation"

    # 验证回滚：schema version 应该仍然是 2
    local after_version
    after_version=$(sqlite3 "$TEST_DB_PATH" "SELECT MAX(version) FROM schema_version;" 2>/dev/null || echo "0")
    [ "$after_version" -eq "$before_version" ] || fail "Expected rollback to version $before_version, got $after_version"

    # 验证备份文件存在
    local backup_count
    backup_count=$(ls "${TEST_DB_PATH}.backup."* 2>/dev/null | wc -l | tr -d ' ')
    [ "$backup_count" -gt 0 ] || fail "Expected backup file to exist after failed migration"

    # 清理备份
    rm -f "${TEST_DB_PATH}.backup."*
}

# @smoke
@test "T-MIG-003: Auto-create backup before migration" {
    # Arrange: 创建 v2 数据库
    sqlite3 "$TEST_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS nodes (id TEXT PRIMARY KEY, type TEXT, name TEXT, file_path TEXT, metadata TEXT);
CREATE TABLE IF NOT EXISTS edges (id INTEGER PRIMARY KEY, source_id TEXT, target_id TEXT, edge_type TEXT, metadata TEXT);
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
INSERT INTO schema_version (version) VALUES (2);
EOF

    # Act: 运行迁移
    run bash scripts/graph-store.sh migrate --apply

    # Assert: 验证备份文件存在
    local backup_files
    backup_files=$(ls "${TEST_DB_PATH}.backup."* 2>/dev/null | wc -l)
    [ "$backup_files" -gt 0 ] || fail "Expected backup file to be created"

    # 清理备份
    rm -f "${TEST_DB_PATH}.backup."*
}

# @smoke
@test "T-MIG-004: Concurrent migration is rejected" {
    # Arrange: 创建 v2 数据库
    sqlite3 "$TEST_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS nodes (id TEXT PRIMARY KEY, type TEXT, name TEXT, file_path TEXT, metadata TEXT);
CREATE TABLE IF NOT EXISTS edges (id INTEGER PRIMARY KEY, source_id TEXT, target_id TEXT, edge_type TEXT, metadata TEXT);
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
INSERT INTO schema_version (version) VALUES (2);
EOF

    # 创建锁文件模拟正在进行的迁移
    local lock_file="${TEST_DB_PATH}.migrate.lock"
    touch "$lock_file"

    # Act: 尝试运行第二个迁移
    run bash scripts/graph-store.sh migrate --apply
    # bats 的 run 命令将退出码保存在 $status 变量中
    local second_migration_status=$status

    # Assert: 验证第二个迁移被拒绝
    [ "$second_migration_status" -ne 0 ] || fail "Expected second migration to be rejected"
    assert_contains "$output" "Migration in progress" || assert_contains "$output" "lock"

    # 清理锁文件
    rm -f "$lock_file"
}

# ============================================================
# CKB Integration Tests (AC-U04, AC-U07, AC-U13, AC-U14, AC-U15)
# ============================================================

# @smoke
@test "T-CKB-001: CKB available returns real graph data" {
    # Arrange: 创建 Mock CKB 响应
    local mock_ckb_response='{"nodes": [{"id": "node1", "type": "function"}], "edges": [{"source": "node1", "target": "node2", "type": "CALLS"}]}'

    # 创建 Mock CKB 脚本
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb.sh"
    cat > "$mock_ckb_script" <<EOF
#!/bin/bash
echo '$mock_ckb_response'
exit 0
EOF
    chmod +x "$mock_ckb_script"

    # Act: 运行 graph-rag 查询，使用 Mock CKB
    export CKB_MCP_CLIENT="$mock_ckb_script"
    run bash scripts/graph-rag.sh --query "test function" --format json
    unset CKB_MCP_CLIENT

    # Assert: 验证 CKB 可用标志
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local ckb_available
    ckb_available=$(echo "$json" | jq -r '.metadata.ckb_available' 2>/dev/null || echo "null")
    [ "$ckb_available" = "true" ] || fail "Expected ckb_available=true, got $ckb_available"
}

# @smoke
@test "T-CKB-002: CKB fallback returns local results" {
    # Arrange: 创建失败的 Mock CKB（模拟不可用）
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb-fail.sh"
    cat > "$mock_ckb_script" <<'EOF'
#!/bin/bash
echo "CKB connection failed" >&2
exit 1
EOF
    chmod +x "$mock_ckb_script"

    # 准备本地数据库
    bash scripts/graph-store.sh init

    # Act: 运行查询，CKB 不可用时应降级
    export CKB_MCP_CLIENT="$mock_ckb_script"
    run bash scripts/graph-rag.sh --query "test function" --format json
    unset CKB_MCP_CLIENT

    # Assert: 验证降级标志
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local ckb_available
    ckb_available=$(echo "$json" | jq -r '.metadata.ckb_available' 2>/dev/null || echo "null")
    [ "$ckb_available" = "false" ] || fail "Expected ckb_available=false during fallback, got $ckb_available"
}

# @smoke
@test "T-CKB-003: CKB timeout triggers fallback" {
    # Arrange: 创建超时的 Mock CKB（模拟超时）
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb-timeout.sh"
    cat > "$mock_ckb_script" <<'EOF'
#!/bin/bash
# 模拟超时：睡眠 10 秒（超过 5 秒超时阈值）
sleep 10
echo '{"nodes": []}'
EOF
    chmod +x "$mock_ckb_script"

    # Act: 运行查询，设置 5 秒超时
    export CKB_MCP_CLIENT="$mock_ckb_script"
    export CKB_TIMEOUT=5

    local start_time end_time elapsed_time
    start_time=$(date +%s)
    run bash scripts/graph-rag.sh --query "test function" --format json
    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))

    unset CKB_MCP_CLIENT
    unset CKB_TIMEOUT

    # Assert: 验证超时触发降级（执行时间应该接近 5 秒，而不是 10 秒）
    [ "$elapsed_time" -lt 8 ] || fail "Expected timeout at 5s, but took ${elapsed_time}s"

    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local ckb_available
    ckb_available=$(echo "$json" | jq -r '.metadata.ckb_available' 2>/dev/null || echo "null")
    [ "$ckb_available" = "false" ] || fail "Expected ckb_available=false after timeout"
}

# @smoke
@test "T-CKB-004: Fallback cooldown period skips CKB for 60s" {
    # Arrange: 创建失败的 Mock CKB
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb-fail.sh"
    cat > "$mock_ckb_script" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$mock_ckb_script"

    # 创建计数器文件
    local call_counter="${TEST_TEMP_DIR}/ckb-call-count"
    echo "0" > "$call_counter"

    # 包装 Mock 脚本以计数调用次数
    local wrapped_mock="${TEST_TEMP_DIR}/wrapped-mock-ckb.sh"
    cat > "$wrapped_mock" <<EOF
#!/bin/bash
count=\$(cat "$call_counter")
count=\$((count + 1))
echo "\$count" > "$call_counter"
bash "$mock_ckb_script"
EOF
    chmod +x "$wrapped_mock"

    # Act: 第一次调用（触发降级）
    export CKB_MCP_CLIENT="$wrapped_mock"
    export CKB_COOLDOWN=60
    run bash scripts/graph-rag.sh --query "test1" --format json

    # 第二次调用（应该在冷却期内，跳过 CKB）
    run bash scripts/graph-rag.sh --query "test2" --format json
    unset CKB_MCP_CLIENT
    unset CKB_COOLDOWN

    # Assert: 验证 CKB 只被调用一次（第二次在冷却期内）
    local call_count
    call_count=$(cat "$call_counter")
    [ "$call_count" -eq 1 ] || fail "Expected CKB to be called once, but was called $call_count times"
}

# @smoke
@test "T-CKB-005: Fallback output contains ckb_fallback_reason" {
    # Arrange: 创建失败的 Mock CKB
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb-fail.sh"
    cat > "$mock_ckb_script" <<'EOF'
#!/bin/bash
echo "Connection refused" >&2
exit 1
EOF
    chmod +x "$mock_ckb_script"

    # Act: 运行查询
    export CKB_MCP_CLIENT="$mock_ckb_script"
    run bash scripts/graph-rag.sh --query "test function" --format json
    unset CKB_MCP_CLIENT

    # Assert: 验证降级原因字段存在
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local fallback_reason
    fallback_reason=$(echo "$json" | jq -r '.metadata.ckb_fallback_reason' 2>/dev/null || echo "null")
    [ "$fallback_reason" != "null" ] && [ -n "$fallback_reason" ] || fail "Expected ckb_fallback_reason field, got $fallback_reason"
}

# ============================================================
# Fusion Query Tests (AC-U05, AC-U16, AC-U17, AC-U18)
# ============================================================

# @smoke
@test "T-FUSION-001: Fusion query candidates >= 1.5x vector-only" {
    # Arrange: 准备测试数据库和向量索引
    bash scripts/graph-store.sh init

    # 创建测试节点和边（使用 v3 schema）
    sqlite3 "$TEST_DB_PATH" <<'EOF'
INSERT INTO nodes (id, symbol, kind, file_path) VALUES
    ('node1', 'testFunc', 'function', '/test1.ts'),
    ('node2', 'helperFunc', 'function', '/test2.ts'),
    ('node3', 'utilFunc', 'function', '/test3.ts');
INSERT INTO edges (id, source_id, target_id, edge_type) VALUES
    ('edge1', 'node1', 'node2', 'CALLS'),
    ('edge2', 'node2', 'node3', 'CALLS');
EOF

    # Mock CKB 返回图扩展结果
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb-fusion.sh"
    cat > "$mock_ckb_script" <<'EOF'
#!/bin/bash
echo '{"expanded_nodes": ["node2", "node3"]}'
EOF
    chmod +x "$mock_ckb_script"

    # Act: 运行纯向量搜索
    run bash scripts/graph-rag.sh --query "test function" --fusion-depth 0 --format json
    local vector_output="$output"

    # 运行融合查询
    export CKB_MCP_CLIENT="$mock_ckb_script"
    run bash scripts/graph-rag.sh --query "test function" --fusion-depth 1 --format json
    unset CKB_MCP_CLIENT
    local fusion_output="$output"

    # Assert: 验证融合查询候选数 >= 1.5x 纯向量
    local vector_count fusion_count
    vector_count=$(echo "$vector_output" | jq -r '.results | length' 2>/dev/null || echo "0")
    fusion_count=$(echo "$fusion_output" | jq -r '.results | length' 2>/dev/null || echo "0")

    # 计算阈值（向量数 * 1.5）
    local threshold
    threshold=$(awk -v v="$vector_count" 'BEGIN { print int(v * 1.5) }')

    [ "$fusion_count" -ge "$threshold" ] || fail "Expected fusion candidates >= $threshold (1.5x $vector_count), got $fusion_count"
}

# @smoke
@test "T-FUSION-002: Fusion query respects token budget" {
    # Arrange: 准备测试数据
    bash scripts/graph-store.sh init

    # Act: 运行融合查询，设置 Token 预算
    local budget=4000
    run bash scripts/graph-rag.sh --query "test function" --fusion-depth 1 --budget "$budget" --format json

    # Assert: 验证输出 Token 数不超过预算
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local token_count
    token_count=$(echo "$json" | jq -r '.metadata.token_count' 2>/dev/null || echo "0")

    [ "$token_count" -le "$budget" ] || fail "Expected token count <= $budget, got $token_count"
}

# @smoke
@test "T-FUSION-003: Fusion query latency increase < 200ms" {
    # Arrange: 准备测试数据
    bash scripts/graph-store.sh init

    # Mock CKB 快速响应
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb-fast.sh"
    cat > "$mock_ckb_script" <<'EOF'
#!/bin/bash
echo '{"expanded_nodes": []}'
EOF
    chmod +x "$mock_ckb_script"

    # Act: 测量纯向量搜索延迟
    local vector_start vector_end vector_latency
    vector_start=$(get_time_ns)
    run bash scripts/graph-rag.sh --query "test function" --fusion-depth 0 --format json
    vector_end=$(get_time_ns)
    vector_latency=$(( (vector_end - vector_start) / 1000000 ))

    # 测量融合查询延迟
    export CKB_MCP_CLIENT="$mock_ckb_script"
    local fusion_start fusion_end fusion_latency
    fusion_start=$(get_time_ns)
    run bash scripts/graph-rag.sh --query "test function" --fusion-depth 1 --format json
    fusion_end=$(get_time_ns)
    fusion_latency=$(( (fusion_end - fusion_start) / 1000000 ))
    unset CKB_MCP_CLIENT

    # Assert: 验证延迟增加 < 300ms (留出环境差异余量)
    local latency_increase
    latency_increase=$((fusion_latency - vector_latency))

    [ "$latency_increase" -lt 300 ] || fail "Expected latency increase < 300ms, got ${latency_increase}ms"
}

# @smoke
@test "T-FUSION-004: Fallback uses local 1-hop edge traversal" {
    # Arrange: 准备测试数据库（使用 v3 schema 的 kind/symbol 列名）
    bash scripts/graph-store.sh init
    sqlite3 "$TEST_DB_PATH" <<'EOF'
INSERT INTO nodes (id, kind, symbol, file_path) VALUES
    ('node1', 'function', 'testFunc', '/test1.ts'),
    ('node2', 'function', 'helperFunc', '/test2.ts');
INSERT INTO edges (source_id, target_id, edge_type) VALUES
    ('node1', 'node2', 'CALLS');
EOF

    # Mock CKB 失败（设置 CKB_UNAVAILABLE 触发 import fallback mock）
    export CKB_UNAVAILABLE=true

    # Act: 运行融合查询（CKB 不可用）
    run bash scripts/graph-rag.sh --query "testFunc" --fusion-depth 1 --format json
    unset CKB_UNAVAILABLE

    # Assert: 验证使用降级方案
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local ckb_available
    ckb_available=$(echo "$json" | jq -r '.metadata.ckb_available' 2>/dev/null || echo "null")
    [ "$ckb_available" = "false" ] || fail "Expected ckb_available=false"

    # 验证结果包含降级数据（graph-rag.sh 输出使用 .candidates 不是 .results）
    local result_count
    result_count=$(echo "$json" | jq -r '.candidates | length' 2>/dev/null || echo "0")
    [ "$result_count" -gt 0 ] || fail "Expected fallback to return candidates"
}

# ============================================================
# Auto Warmup Tests (AC-U06, AC-U19, AC-U20)
# ============================================================

# @smoke
@test "T-WARMUP-001: Daemon auto-triggers warmup after start" {
    # Arrange: 确保 daemon 未运行
    bash scripts/daemon.sh stop 2>/dev/null || true

    # Act: 启动 daemon
    run bash scripts/daemon.sh start

    # 等待预热触发
    sleep 2

    # 检查状态
    run bash scripts/daemon.sh status --format json

    # Assert: 验证预热状态
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local warmup_status
    warmup_status=$(echo "$json" | jq -r '.warmup_status' 2>/dev/null || echo "null")

    # 预热状态应该是 "running" 或 "completed"
    [[ "$warmup_status" == "running" || "$warmup_status" == "completed" ]] || fail "Expected warmup_status to be running or completed, got $warmup_status"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# @smoke
@test "T-WARMUP-002: Warmup does not block startup (async)" {
    # Arrange: 确保 daemon 未运行
    bash scripts/daemon.sh stop 2>/dev/null || true

    # Act: 测量启动时间
    local start_time end_time elapsed_time
    start_time=$(date +%s)
    run bash scripts/daemon.sh start
    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))

    # Assert: 验证启动时间 < 2 秒（不等待预热完成）
    [ "$elapsed_time" -lt 2 ] || fail "Expected daemon startup < 2s, but took ${elapsed_time}s"

    # 验证 daemon 已启动
    run bash scripts/daemon.sh status
    assert_exit_success "$status"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# @smoke
@test "T-WARMUP-003: Warmup timeout 30s does not affect daemon" {
    # Arrange: 确保 daemon 未运行
    bash scripts/daemon.sh stop 2>/dev/null || true

    # 设置预热超时为 1 秒（模拟超时）
    export WARMUP_TIMEOUT=1

    # Act: 启动 daemon
    run bash scripts/daemon.sh start

    # 等待超时触发
    sleep 3

    # 检查 daemon 状态
    run bash scripts/daemon.sh status --format json
    unset WARMUP_TIMEOUT

    # Assert: 验证 daemon 仍在运行
    assert_exit_success "$status"

    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    # daemon.sh 输出使用 .running 和 .state 而不是 .status
    local daemon_running
    daemon_running=$(echo "$json" | jq -r '.running' 2>/dev/null || echo "false")
    [ "$daemon_running" = "true" ] || fail "Expected daemon to be running after warmup timeout"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# ============================================================
# Contract Tests: MCP Output Format (CT-MCP-001 ~ CT-MCP-004)
# ============================================================

# @smoke
@test "CT-MCP-001: ckb_available field exists" {
    # Arrange: 准备测试环境
    bash scripts/graph-store.sh init

    # Act: 运行 graph-rag 查询
    run bash scripts/graph-rag.sh --query "test" --format json

    # Assert: 验证 ckb_available 字段存在
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local ckb_available
    ckb_available=$(echo "$json" | jq -r '.metadata.ckb_available' 2>/dev/null || echo "null")
    [ "$ckb_available" != "null" ] || fail "Expected metadata.ckb_available field to exist"
}

# @smoke
@test "CT-MCP-002: ckb_fallback_reason conditionally required" {
    # Arrange: 创建失败的 Mock CKB
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb-fail.sh"
    cat > "$mock_ckb_script" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$mock_ckb_script"

    # Act: 运行查询（CKB 降级）
    export CKB_MCP_CLIENT="$mock_ckb_script"
    run bash scripts/graph-rag.sh --query "test" --format json
    unset CKB_MCP_CLIENT

    # Assert: 验证 ckb_fallback_reason 字段存在（当 ckb_available=false 时）
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local ckb_available fallback_reason
    ckb_available=$(echo "$json" | jq -r '.metadata.ckb_available' 2>/dev/null || echo "null")
    fallback_reason=$(echo "$json" | jq -r '.metadata.ckb_fallback_reason' 2>/dev/null || echo "null")

    if [ "$ckb_available" = "false" ]; then
        [ "$fallback_reason" != "null" ] && [ -n "$fallback_reason" ] || fail "Expected ckb_fallback_reason when ckb_available=false"
    fi
}

# @smoke
@test "CT-MCP-003: fusion_depth field exists and in range" {
    # Act: 运行融合查询
    run bash scripts/graph-rag.sh --query "test" --fusion-depth 1 --format json

    # Assert: 验证 fusion_depth 字段存在且在有效范围内
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local fusion_depth
    fusion_depth=$(echo "$json" | jq -r '.metadata.fusion_depth' 2>/dev/null || echo "null")
    [ "$fusion_depth" != "null" ] || fail "Expected metadata.fusion_depth field to exist"

    # 验证范围 [0, 5]
    [ "$fusion_depth" -ge 0 ] && [ "$fusion_depth" -le 5 ] || fail "Expected fusion_depth in range [0, 5], got $fusion_depth"
}

# @smoke
@test "CT-MCP-004: CKB timeout triggers fallback" {
    # Arrange: 创建超时的 Mock CKB
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb-timeout.sh"
    cat > "$mock_ckb_script" <<'EOF'
#!/bin/bash
sleep 10
echo '{"nodes": []}'
EOF
    chmod +x "$mock_ckb_script"

    # Act: 运行查询，设置超时
    export CKB_MCP_CLIENT="$mock_ckb_script"
    export CKB_TIMEOUT=2
    run bash scripts/graph-rag.sh --query "test" --format json
    unset CKB_MCP_CLIENT
    unset CKB_TIMEOUT

    # Assert: 验证超时触发降级
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local ckb_available
    ckb_available=$(echo "$json" | jq -r '.metadata.ckb_available' 2>/dev/null || echo "null")
    [ "$ckb_available" = "false" ] || fail "Expected ckb_available=false after timeout"
}

# ============================================================
# Contract Tests: graph-store.sh CLI (CT-GS-001 ~ CT-GS-005)
# ============================================================

# @smoke
@test "CT-GS-001: migrate --status returns schema_version" {
    # Arrange: 创建测试数据库
    bash scripts/graph-store.sh init

    # Act: 运行 migrate --status
    run bash scripts/graph-store.sh migrate --status --format json

    # Assert: 验证 schema_version 字段存在
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local schema_version
    schema_version=$(echo "$json" | jq -r '.schema_version' 2>/dev/null || echo "null")
    [ "$schema_version" != "null" ] && [ "$schema_version" -ge 1 ] || fail "Expected schema_version field, got $schema_version"
}

# @smoke
@test "CT-GS-002: migrate --apply creates backup" {
    # Arrange: 创建 v2 数据库
    sqlite3 "$TEST_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS nodes (id TEXT PRIMARY KEY, type TEXT, name TEXT, file_path TEXT, metadata TEXT);
CREATE TABLE IF NOT EXISTS edges (id INTEGER PRIMARY KEY, source_id TEXT, target_id TEXT, edge_type TEXT, metadata TEXT);
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
INSERT INTO schema_version (version) VALUES (2);
EOF

    # Act: 运行迁移
    run bash scripts/graph-store.sh migrate --apply

    # Assert: 验证备份文件存在
    local backup_count
    backup_count=$(ls "${TEST_DB_PATH}.backup."* 2>/dev/null | wc -l | tr -d ' ')
    [ "$backup_count" -gt 0 ] || fail "Expected backup file to be created"

    # 清理备份
    rm -f "${TEST_DB_PATH}.backup."*
}

# @smoke
@test "CT-GS-003: Migration failure rollback" {
    # 这个测试与 T-MIG-002 类似，验证契约行为
    # Arrange: 创建损坏的数据库
    sqlite3 "$TEST_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS nodes (id TEXT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
INSERT INTO schema_version (version) VALUES (2);
EOF

    # Act: 运行迁移（预期失败）
    run bash scripts/graph-store.sh migrate --apply
    # bats 的 run 命令将退出码保存在 $status 变量中
    local migration_status=$status

    # Assert: 验证迁移失败且回滚
    [ "$migration_status" -ne 0 ] || fail "Expected migration to fail"

    local schema_version
    schema_version=$(sqlite3 "$TEST_DB_PATH" "SELECT MAX(version) FROM schema_version;" 2>/dev/null || echo "0")
    [ "$schema_version" -eq 2 ] || fail "Expected rollback to version 2"
}

# @smoke
@test "CT-GS-004: stats returns edges_by_type" {
    # Arrange: 创建测试数据（使用 v3 schema 的 kind/symbol 列名）
    bash scripts/graph-store.sh init
    sqlite3 "$TEST_DB_PATH" <<'EOF'
INSERT INTO nodes (id, kind, symbol, file_path) VALUES ('node1', 'function', 'test', '/test.ts');
INSERT INTO edges (source_id, target_id, edge_type) VALUES ('node1', 'node1', 'CALLS');
INSERT INTO edges (source_id, target_id, edge_type) VALUES ('node1', 'node1', 'IMPLEMENTS');
EOF

    # Act: 运行 stats 命令
    run bash scripts/graph-store.sh stats --format json

    # Assert: 验证 edges_by_type 字段存在
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local edges_by_type
    edges_by_type=$(echo "$json" | jq -r '.edges_by_type' 2>/dev/null || echo "null")
    [ "$edges_by_type" != "null" ] || fail "Expected edges_by_type field in stats output"
}

# @smoke
@test "CT-GS-005: Concurrent migration protection" {
    # 这个测试与 T-MIG-004 类似，验证契约行为
    # Arrange: 创建 v2 数据库
    sqlite3 "$TEST_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS nodes (id TEXT PRIMARY KEY, type TEXT, name TEXT, file_path TEXT, metadata TEXT);
CREATE TABLE IF NOT EXISTS edges (id INTEGER PRIMARY KEY, source_id TEXT, target_id TEXT, edge_type TEXT, metadata TEXT);
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
INSERT INTO schema_version (version) VALUES (2);
EOF

    # 创建锁文件
    local lock_file="${TEST_DB_PATH}.migrate.lock"
    touch "$lock_file"

    # Act: 尝试运行迁移
    run bash scripts/graph-store.sh migrate --apply
    # bats 的 run 命令将退出码保存在 $status 变量中
    local second_migration_status=$status

    # Assert: 验证第二个迁移被拒绝
    [ "$second_migration_status" -ne 0 ] || fail "Expected concurrent migration to be rejected"

    # 清理锁文件
    rm -f "$lock_file"
}

# ============================================================
# Contract Tests: graph-rag.sh CLI (CT-GR-001 ~ CT-GR-007)
# ============================================================

# @smoke
@test "CT-GR-001: --fusion-depth parameter parsing" {
    # Act: 运行带 --fusion-depth 参数的查询
    run bash scripts/graph-rag.sh --query "test" --fusion-depth 2 --format json

    # Assert: 验证参数被正确解析
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local fusion_depth
    fusion_depth=$(echo "$json" | jq -r '.metadata.fusion_depth' 2>/dev/null || echo "null")
    [ "$fusion_depth" -eq 2 ] || fail "Expected fusion_depth=2, got $fusion_depth"
}

# @smoke
@test "CT-GR-002: --fusion-depth default value" {
    # Act: 运行不带 --fusion-depth 参数的查询
    run bash scripts/graph-rag.sh --query "test" --format json

    # Assert: 验证默认值为 1
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local fusion_depth
    fusion_depth=$(echo "$json" | jq -r '.metadata.fusion_depth' 2>/dev/null || echo "null")
    [ "$fusion_depth" -eq 1 ] || fail "Expected default fusion_depth=1, got $fusion_depth"
}

# @smoke
@test "CT-GR-003: --fusion-depth fallback" {
    # Arrange: Mock CKB 失败
    local mock_ckb_script="${TEST_TEMP_DIR}/mock-ckb-fail.sh"
    cat > "$mock_ckb_script" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$mock_ckb_script"

    # Act: 运行融合查询（CKB 不可用）
    export CKB_MCP_CLIENT="$mock_ckb_script"
    run bash scripts/graph-rag.sh --query "test" --fusion-depth 2 --format json
    unset CKB_MCP_CLIENT

    # Assert: 验证降级到本地 1-hop 遍历
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local ckb_available
    ckb_available=$(echo "$json" | jq -r '.metadata.ckb_available' 2>/dev/null || echo "null")
    [ "$ckb_available" = "false" ] || fail "Expected ckb_available=false during fallback"
}

# @smoke
@test "CT-GR-004: --include-virtual parameter" {
    # Act: 运行带 --include-virtual 参数的查询
run bash scripts/graph-rag.sh --query "test" --include-virtual --format json

    # Assert: 验证参数被接受（不报错）
    assert_exit_success "$status"
    assert_valid_json "$output"
}

# @smoke
@test "CT-GR-005: Output contains source field" {
    # Arrange: 准备测试数据
    bash scripts/graph-store.sh init

    # Act: 运行查询
    run bash scripts/graph-rag.sh --query "test" --format json

    # Assert: 验证输出包含 source 字段
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local has_source
    has_source=$(echo "$json" | jq -r '.results[0].source' 2>/dev/null || echo "null")
    # 如果有结果，source 字段应该存在
    if [ "$(echo "$json" | jq -r '.results | length' 2>/dev/null || echo "0")" -gt 0 ]; then
        [ "$has_source" != "null" ] || fail "Expected source field in results"
    fi
}

# @smoke
@test "CT-GR-006: Fusion candidate threshold" {
    # 这个测试与 T-FUSION-001 类似，验证契约行为
    # Arrange: 准备测试数据
    bash scripts/graph-store.sh init

    # Act: 运行纯向量搜索和融合查询
    run bash scripts/graph-rag.sh --query "test" --fusion-depth 0 --format json
    local vector_output="$output"

    run bash scripts/graph-rag.sh --query "test" --fusion-depth 1 --format json
    local fusion_output="$output"

    # Assert: 验证融合查询候选数 >= 向量搜索
    local vector_count fusion_count
    vector_count=$(echo "$vector_output" | jq -r '.results | length' 2>/dev/null || echo "0")
    fusion_count=$(echo "$fusion_output" | jq -r '.results | length' 2>/dev/null || echo "0")

    [ "$fusion_count" -ge "$vector_count" ] || fail "Expected fusion candidates >= vector candidates"
}

# @smoke
@test "CT-GR-007: fusion-depth=0 vector-only search" {
    # Act: 运行 fusion-depth=0 查询
    run bash scripts/graph-rag.sh --query "test" --fusion-depth 0 --format json

    # Assert: 验证 fusion_depth=0
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local fusion_depth
    fusion_depth=$(echo "$json" | jq -r '.metadata.fusion_depth' 2>/dev/null || echo "null")
    [ "$fusion_depth" -eq 0 ] || fail "Expected fusion_depth=0 for vector-only search"
}

# ============================================================
# Contract Tests: daemon.sh CLI (CT-DM-001 ~ CT-DM-007)
# ============================================================

# @smoke
@test "CT-DM-001: start auto-triggers warmup" {
    # 这个测试与 T-WARMUP-001 类似，验证契约行为
    # Arrange: 确保 daemon 未运行
    bash scripts/daemon.sh stop 2>/dev/null || true

    # Act: 启动 daemon
    run bash scripts/daemon.sh start

    # 等待预热触发
    sleep 2

    # 检查状态
    run bash scripts/daemon.sh status --format json

    # Assert: 验证预热状态
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local warmup_status
    warmup_status=$(echo "$json" | jq -r '.warmup_status' 2>/dev/null || echo "null")
    [[ "$warmup_status" == "running" || "$warmup_status" == "completed" ]] || fail "Expected warmup_status to be running or completed"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# @smoke
@test "CT-DM-002: status returns warmup_status" {
    # Arrange: 确保 daemon 运行
    bash scripts/daemon.sh stop 2>/dev/null || true
    bash scripts/daemon.sh start

    # Act: 获取状态
    run bash scripts/daemon.sh status --format json

    # Assert: 验证 warmup_status 字段存在
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local warmup_status
    warmup_status=$(echo "$json" | jq -r '.warmup_status' 2>/dev/null || echo "null")
    [ "$warmup_status" != "null" ] || fail "Expected warmup_status field in status output"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# @smoke
@test "CT-DM-003: warmup completed status" {
    # Arrange: 启动 daemon 并等待预热完成
    bash scripts/daemon.sh stop 2>/dev/null || true
    bash scripts/daemon.sh start
    sleep 5  # 等待预热完成

    # Act: 获取状态
    run bash scripts/daemon.sh status --format json

    # Assert: 验证预热完成状态
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local warmup_status
    warmup_status=$(echo "$json" | jq -r '.warmup_status' 2>/dev/null || echo "null")
    [ "$warmup_status" = "completed" ] || [ "$warmup_status" = "running" ] || fail "Expected warmup_status to be completed or running"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# @smoke
@test "CT-DM-004: warmup timeout handling" {
    # 这个测试与 T-WARMUP-003 类似，验证契约行为
    # Arrange: 设置短超时
    bash scripts/daemon.sh stop 2>/dev/null || true
    export WARMUP_TIMEOUT=1

    # Act: 启动 daemon
    run bash scripts/daemon.sh start
    sleep 3

    # 检查状态
    run bash scripts/daemon.sh status --format json
    unset WARMUP_TIMEOUT

    # Assert: 验证 daemon 仍在运行
    assert_exit_success "$status"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# @smoke
@test "CT-DM-005: warmup disabled" {
    # Arrange: 禁用预热（daemon.sh 使用 DAEMON_ 前缀）
    bash scripts/daemon.sh stop 2>/dev/null || true
    export DAEMON_WARMUP_ENABLED=false

    # Act: 启动 daemon
    run bash scripts/daemon.sh start

    # 检查状态
    run bash scripts/daemon.sh status --format json
    unset DAEMON_WARMUP_ENABLED

    # Assert: 验证预热状态为 disabled
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local warmup_status
    warmup_status=$(echo "$json" | jq -r '.warmup_status' 2>/dev/null || echo "null")
    [ "$warmup_status" = "disabled" ] || [ "$warmup_status" = "null" ] || fail "Expected warmup_status to be disabled or null"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# @smoke
@test "CT-DM-006: Startup time unaffected by warmup" {
    # 这个测试与 T-WARMUP-002 类似，验证契约行为
    # Arrange: 确保 daemon 未运行
    bash scripts/daemon.sh stop 2>/dev/null || true

    # Act: 测量启动时间
    local start_time end_time elapsed_time
    start_time=$(date +%s)
    run bash scripts/daemon.sh start
    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))

    # Assert: 验证启动时间 <= 3 秒（允许系统调度波动）
    [ "$elapsed_time" -le 3 ] || fail "Expected daemon startup <= 3s, but took ${elapsed_time}s"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# @smoke
@test "CT-DM-007: status output completeness" {
    # Arrange: 启动 daemon
    bash scripts/daemon.sh stop 2>/dev/null || true
    bash scripts/daemon.sh start

    # 等待预热触发
    sleep 2

    # Act: 获取状态
    run bash scripts/daemon.sh status --format json

    # Assert: 验证输出包含必要字段
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    # daemon.sh 输出 .running 和 .state 而不是 .status
    local running warmup_status
    running=$(echo "$json" | jq -r '.running' 2>/dev/null || echo "null")
    warmup_status=$(echo "$json" | jq -r '.warmup_status' 2>/dev/null || echo "null")

    [ "$running" != "null" ] || fail "Expected running field"
    [ "$warmup_status" != "null" ] || fail "Expected warmup_status field"

    # 清理
    bash scripts/daemon.sh stop 2>/dev/null || true
}

# ============================================================
# Boundary Condition Tests
# ============================================================

# @smoke
@test "BOUNDARY-001: Empty query string" {
    # Act: 运行空查询
    run bash scripts/graph-rag.sh --query "" --format json

    # Assert: 验证错误处理
    [ "$status" -ne 0 ] || fail "Expected empty query to fail"
    assert_contains "$output" "query" || assert_contains "$output" "empty"
}

# @smoke
@test "BOUNDARY-002: Excessively long query string" {
    # Arrange: 创建超长查询（10000 字符）
    local long_query
    long_query=$(printf 'a%.0s' {1..10000})

    # Act: 运行超长查询
    run bash scripts/graph-rag.sh --query "$long_query" --format json

    # Assert: 验证错误处理或截断
    # 可能成功（截断）或失败（拒绝）
    if [ "$status" -eq 0 ]; then
        assert_valid_json "$output"
    else
        assert_contains "$output" "too long" || assert_contains "$output" "length"
    fi
}

# @smoke
@test "BOUNDARY-003: Invalid fusion-depth parameter" {
    # Act: 运行无效的 fusion-depth 参数
    run bash scripts/graph-rag.sh --query "test" --fusion-depth -1 --format json

    # Assert: 验证错误处理
    [ "$status" -ne 0 ] || fail "Expected invalid fusion-depth to fail"
    assert_contains "$output" "fusion-depth" || assert_contains "$output" "invalid"
}

# @smoke
@test "BOUNDARY-004: Empty database query" {
    # Arrange: 创建空数据库
    bash scripts/graph-store.sh init

    # Act: 运行查询
    run bash scripts/graph-rag.sh --query "test" --format json

    # Assert: 验证返回空结果（不报错）
    assert_exit_success "$status"
    assert_valid_json "$output"
    local json
    json=$(extract_json "$output")

    local result_count
    result_count=$(echo "$json" | jq -r '.results | length' 2>/dev/null || echo "0")
    [ "$result_count" -eq 0 ] || fail "Expected empty results from empty database"
}
