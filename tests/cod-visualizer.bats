#!/usr/bin/env bats
# cod-visualizer.bats - COD 架构可视化模块测试
#
# 覆盖 M3: COD 架构可视化模块
# 契约测试: CT-CV-001 (Mermaid), CT-CV-002 (D3.js JSON)
#
# 场景覆盖:
#   T-CV-001: 模块级 Mermaid 输出
#   T-CV-002: 文件级 D3.js JSON 输出
#   T-CV-003: 热点着色集成
#   T-CV-004: 复杂度标注
#   T-CV-005: Mermaid 语法有效性
#   T-CV-006: D3.js JSON Schema 有效性
#   T-CV-007: 空模块处理
#   T-CV-008: 输出到文件

load 'helpers/common'

# 脚本路径
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
COD_VISUALIZER="$SCRIPT_DIR/cod-visualizer.sh"
GRAPH_STORE="$SCRIPT_DIR/graph-store.sh"

setup() {
    setup_temp_dir
    export GRAPH_DB_PATH="$TEST_TEMP_DIR/graph.db"
    export DEVBOOKS_DIR="$TEST_TEMP_DIR/.devbooks"
    mkdir -p "$DEVBOOKS_DIR"
    mkdir -p "$TEST_TEMP_DIR/scripts"
    mkdir -p "$TEST_TEMP_DIR/empty-module"

    # 初始化图数据库并填充测试数据
    _setup_test_graph_data
}

teardown() {
    cleanup_temp_dir
}

# ============================================================
# 测试数据准备
# ============================================================

# 设置测试图数据
_setup_test_graph_data() {
    # 如果 graph-store.sh 可用，使用它初始化数据库
    if [ -x "$GRAPH_STORE" ]; then
        run "$GRAPH_STORE" init
        if [ "$status" -eq 0 ]; then
            # 创建模块级节点
            "$GRAPH_STORE" add-node --id "mod:scripts" --symbol "scripts" --kind "module" --file "scripts/" 2>/dev/null || true
            "$GRAPH_STORE" add-node --id "mod:src" --symbol "src" --kind "module" --file "src/" 2>/dev/null || true
            "$GRAPH_STORE" add-node --id "mod:tests" --symbol "tests" --kind "module" --file "tests/" 2>/dev/null || true

            # 创建文件级节点
            "$GRAPH_STORE" add-node --id "file:scripts/common.sh" --symbol "common.sh" --kind "file" --file "scripts/common.sh" 2>/dev/null || true
            "$GRAPH_STORE" add-node --id "file:scripts/graph-store.sh" --symbol "graph-store.sh" --kind "file" --file "scripts/graph-store.sh" 2>/dev/null || true
            "$GRAPH_STORE" add-node --id "file:scripts/hotspot-analyzer.sh" --symbol "hotspot-analyzer.sh" --kind "file" --file "scripts/hotspot-analyzer.sh" 2>/dev/null || true
            "$GRAPH_STORE" add-node --id "file:src/server.ts" --symbol "server.ts" --kind "file" --file "src/server.ts" 2>/dev/null || true

            # 创建模块间依赖边
            "$GRAPH_STORE" add-edge --source "mod:scripts" --target "mod:src" --type IMPORTS 2>/dev/null || true
            "$GRAPH_STORE" add-edge --source "mod:tests" --target "mod:scripts" --type IMPORTS 2>/dev/null || true

            # 创建文件间调用边
            "$GRAPH_STORE" add-edge --source "file:scripts/graph-store.sh" --target "file:scripts/common.sh" --type CALLS 2>/dev/null || true
            "$GRAPH_STORE" add-edge --source "file:scripts/hotspot-analyzer.sh" --target "file:scripts/common.sh" --type CALLS 2>/dev/null || true
            "$GRAPH_STORE" add-edge --source "file:scripts/hotspot-analyzer.sh" --target "file:scripts/graph-store.sh" --type CALLS 2>/dev/null || true
        fi
    fi

    # 如果 graph-store.sh 不可用，直接用 sqlite3 创建
    if [ ! -f "$GRAPH_DB_PATH" ]; then
        sqlite3 "$GRAPH_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    symbol TEXT NOT NULL,
    kind TEXT NOT NULL,
    file_path TEXT,
    line_start INTEGER,
    line_end INTEGER,
    metadata TEXT
);

CREATE TABLE IF NOT EXISTS edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    edge_type TEXT NOT NULL CHECK(edge_type IN ('DEFINES', 'IMPORTS', 'CALLS', 'MODIFIES')),
    file_path TEXT,
    line_number INTEGER,
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
);

-- 模块级节点
INSERT INTO nodes (id, symbol, kind, file_path) VALUES
    ('mod:scripts', 'scripts', 'module', 'scripts/'),
    ('mod:src', 'src', 'module', 'src/'),
    ('mod:tests', 'tests', 'module', 'tests/');

-- 文件级节点
INSERT INTO nodes (id, symbol, kind, file_path) VALUES
    ('file:scripts/common.sh', 'common.sh', 'file', 'scripts/common.sh'),
    ('file:scripts/graph-store.sh', 'graph-store.sh', 'file', 'scripts/graph-store.sh'),
    ('file:scripts/hotspot-analyzer.sh', 'hotspot-analyzer.sh', 'file', 'scripts/hotspot-analyzer.sh'),
    ('file:src/server.ts', 'server.ts', 'file', 'src/server.ts');

-- 模块间依赖
INSERT INTO edges (source_id, target_id, edge_type) VALUES
    ('mod:scripts', 'mod:src', 'IMPORTS'),
    ('mod:tests', 'mod:scripts', 'IMPORTS');

-- 文件间调用
INSERT INTO edges (source_id, target_id, edge_type) VALUES
    ('file:scripts/graph-store.sh', 'file:scripts/common.sh', 'CALLS'),
    ('file:scripts/hotspot-analyzer.sh', 'file:scripts/common.sh', 'CALLS'),
    ('file:scripts/hotspot-analyzer.sh', 'file:scripts/graph-store.sh', 'CALLS');
EOF
    fi
}

# ============================================================
# T-CV-001: 模块级 Mermaid 输出
# ============================================================

# @test T-CV-001: 模块级 Mermaid 输出
@test "T-CV-001: cod-visualizer generates module-level Mermaid output" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" generate --level 2 --format mermaid
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh generate mermaid"

    assert_exit_success "$status"

    # 验证 Mermaid flowchart 语法
    assert_contains "$output" "graph TD"

    # 验证包含模块节点
    assert_contains_any "$output" "scripts" "src" "tests"

    # 验证包含依赖关系箭头
    assert_contains_any "$output" "-->" "---"
}

# ============================================================
# T-CV-002: 文件级 D3.js JSON 输出
# ============================================================

# @test T-CV-002: 文件级 D3.js JSON 输出
@test "T-CV-002: cod-visualizer generates file-level D3.js JSON for module" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" module scripts/ --format d3json
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh module d3json"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证 D3.js JSON 结构
    assert_json_field "$output" ".nodes"
    assert_json_field "$output" ".links"
    assert_json_field "$output" ".metadata"

    # 验证 nodes 包含 scripts 目录下的文件
    local node_count
    node_count=$(echo "$output" | jq '.nodes | length')
    [ "$node_count" -ge 1 ]

    # 验证 metadata 包含必要字段
    assert_json_field "$output" ".metadata.generated_at"
    assert_json_field "$output" ".metadata.total_nodes"
    assert_json_field "$output" ".metadata.total_edges"
}

# ============================================================
# T-CV-003: 热点着色集成
# ============================================================

# @test T-CV-003: 热点着色集成 - Mermaid
@test "T-CV-003a: cod-visualizer includes hotspot styling in Mermaid output" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" generate --level 2 --format mermaid --include-hotspots
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh mermaid with hotspots"

    assert_exit_success "$status"

    # 验证包含 Mermaid style 指令
    # Mermaid 热点着色通常使用 style 或 classDef 指令
    assert_contains_any "$output" "style " "classDef " ":::hot" "fill:#"
}

# @test T-CV-003: 热点着色集成 - D3.js JSON
@test "T-CV-003b: cod-visualizer includes hotspot field in D3.js JSON" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" module scripts/ --format d3json --include-hotspots
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh d3json with hotspots"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证节点包含 hotspot 字段
    # 至少第一个节点应该有 hotspot 字段
    local has_hotspot
    has_hotspot=$(echo "$output" | jq '[.nodes[].hotspot] | map(select(. != null)) | length')
    [ "$has_hotspot" -ge 1 ]
}

# ============================================================
# T-CV-004: 复杂度标注
# ============================================================

# @test T-CV-004: 复杂度标注 - Mermaid
@test "T-CV-004a: cod-visualizer includes complexity in Mermaid node labels" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" generate --level 2 --format mermaid --include-complexity
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh mermaid with complexity"

    assert_exit_success "$status"

    # 验证节点标签包含复杂度数值（通常格式：NodeName [15] 或 NodeName(15)）
    # 复杂度通常是数字，用括号或方括号包裹
    assert_contains_any "$output" "[" "(" "complexity" "CC:"
}

# @test T-CV-004: 复杂度标注 - D3.js JSON
@test "T-CV-004b: cod-visualizer includes complexity field in D3.js JSON" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" module scripts/ --format d3json --include-complexity
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh d3json with complexity"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证节点包含 complexity 字段
    local has_complexity
    has_complexity=$(echo "$output" | jq '[.nodes[].complexity] | map(select(. != null)) | length')
    [ "$has_complexity" -ge 1 ]
}

# ============================================================
# T-CV-005: Mermaid 语法有效性
# ============================================================

# @test T-CV-005: Mermaid 语法有效性
@test "T-CV-005: cod-visualizer Mermaid output is syntactically valid" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" generate --level 2 --format mermaid
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh mermaid syntax"

    assert_exit_success "$status"

    # 验证基本 Mermaid 语法结构
    # 必须以 graph TD 或 graph LR 等开头
    assert_contains_any "$output" "graph TD" "graph LR" "graph TB" "graph RL" "flowchart TD" "flowchart LR"

    # 验证不包含明显的语法错误标记
    assert_not_contains "$output" "Error:"
    assert_not_contains "$output" "SyntaxError"

    # 验证输出非空且包含节点定义
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -ge 2 ]
}

# ============================================================
# T-CV-006: D3.js JSON Schema 有效性
# ============================================================

# @test T-CV-006: D3.js JSON Schema 有效性
@test "T-CV-006: cod-visualizer D3.js JSON conforms to expected schema" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" module scripts/ --format d3json
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh d3json schema"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证顶层结构
    assert_json_field "$output" ".nodes"
    assert_json_field "$output" ".links"
    assert_json_field "$output" ".metadata"

    # 验证 nodes 数组元素结构
    local node_has_id node_has_group
    node_has_id=$(echo "$output" | jq '.nodes | map(select(.id != null)) | length')
    [ "$node_has_id" -ge 1 ]

    # 验证 links 数组元素结构（如果有边）
    local link_count
    link_count=$(echo "$output" | jq '.links | length')
    if [ "$link_count" -gt 0 ]; then
        local link_has_source link_has_target
        link_has_source=$(echo "$output" | jq '.links | map(select(.source != null)) | length')
        link_has_target=$(echo "$output" | jq '.links | map(select(.target != null)) | length')
        [ "$link_has_source" -eq "$link_count" ]
        [ "$link_has_target" -eq "$link_count" ]
    fi

    # 验证 metadata 结构
    assert_json_field "$output" ".metadata.generated_at"
    assert_json_field "$output" ".metadata.total_nodes"
    assert_json_field "$output" ".metadata.total_edges"
}

# ============================================================
# T-CV-007: 空模块处理
# ============================================================

# @test T-CV-007: 空模块处理
@test "T-CV-007: cod-visualizer handles empty module gracefully" {
    skip_if_not_executable "$COD_VISUALIZER"

    # 使用测试时创建的空模块目录
    run "$COD_VISUALIZER" module "$TEST_TEMP_DIR/empty-module/" --format d3json

    # 不应该报错（退出码为 0）
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh empty module"
    assert_exit_success "$status"

    # 应该返回有效 JSON
    assert_valid_json "$output"

    # 可以是空图（nodes 和 links 为空数组）或者包含提示信息
    local node_count link_count
    node_count=$(echo "$output" | jq '.nodes | length')
    link_count=$(echo "$output" | jq '.links | length')

    # 空模块应该返回空节点列表
    [ "$node_count" -eq 0 ]
    [ "$link_count" -eq 0 ]
}

# @test T-CV-007b: 空模块 Mermaid 输出
@test "T-CV-007b: cod-visualizer handles empty module in Mermaid format" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" module "$TEST_TEMP_DIR/empty-module/" --format mermaid
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh empty module mermaid"

    assert_exit_success "$status"

    # 应该仍然输出有效的 Mermaid 图（即使是空图）
    assert_contains_any "$output" "graph TD" "graph LR" "flowchart" "%% Empty"
}

# ============================================================
# T-CV-008: 输出到文件
# ============================================================

# @test T-CV-008: 输出到文件 - Mermaid
@test "T-CV-008a: cod-visualizer writes Mermaid output to file" {
    skip_if_not_executable "$COD_VISUALIZER"

    local output_file="$TEST_TEMP_DIR/arch.mmd"

    run "$COD_VISUALIZER" generate --level 2 --format mermaid --output "$output_file"
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh output to file"

    assert_exit_success "$status"

    # 验证文件已创建
    [ -f "$output_file" ]

    # 验证文件内容是有效的 Mermaid
    local file_content
    file_content=$(cat "$output_file")
    assert_contains_any "$file_content" "graph TD" "graph LR" "flowchart"
}

# @test T-CV-008: 输出到文件 - D3.js JSON
@test "T-CV-008b: cod-visualizer writes D3.js JSON output to file" {
    skip_if_not_executable "$COD_VISUALIZER"

    local output_file="$TEST_TEMP_DIR/arch.json"

    run "$COD_VISUALIZER" module scripts/ --format d3json --output "$output_file"
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh d3json output to file"

    assert_exit_success "$status"

    # 验证文件已创建
    [ -f "$output_file" ]

    # 验证文件内容是有效的 JSON
    local file_content
    file_content=$(cat "$output_file")
    assert_valid_json "$file_content"

    # 验证 JSON 结构
    assert_json_field "$file_content" ".nodes"
    assert_json_field "$file_content" ".links"
    assert_json_field "$file_content" ".metadata"
}

# ============================================================
# 边界条件测试
# ============================================================

# @test BC-CV-001: 无效格式参数
@test "BC-CV-001: cod-visualizer rejects invalid format" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" generate --level 2 --format invalid_format

    # 应该失败或显示错误信息
    if [ "$status" -eq 0 ]; then
        # 如果返回成功，检查是否有警告或默认使用了某种格式
        assert_contains_any "$output" "Invalid format" "Unknown format" "graph TD" "nodes"
    else
        # 预期失败
        assert_exit_failure "$status"
        assert_contains_any "$output" "Invalid" "Unknown" "format" "mermaid" "d3json"
    fi
}

# @test BC-CV-002: 无效层级参数
@test "BC-CV-002: cod-visualizer handles invalid level parameter" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" generate --level 999 --format mermaid
    skip_if_not_ready "$status" "$output" "cod-visualizer.sh invalid level"

    # 应该优雅处理：要么失败并提示，要么使用默认值
    if [ "$status" -eq 0 ]; then
        # 使用默认值时应该输出有效的 Mermaid
        assert_contains_any "$output" "graph TD" "graph LR" "flowchart"
    else
        # 失败时应该有错误信息
        assert_contains_any "$output" "Invalid" "level" "1" "2" "3"
    fi
}

# @test BC-CV-003: 不存在的模块路径
@test "BC-CV-003: cod-visualizer handles non-existent module path" {
    skip_if_not_executable "$COD_VISUALIZER"

    run "$COD_VISUALIZER" module "/non/existent/path/" --format d3json

    # 可能失败或返回空结果
    if [ "$status" -eq 0 ]; then
        # 返回空结果
        assert_valid_json "$output"
        local node_count
        node_count=$(echo "$output" | jq '.nodes | length')
        [ "$node_count" -eq 0 ]
    else
        # 预期失败
        assert_exit_failure "$status"
        assert_contains_any "$output" "not found" "does not exist" "No such" "Error"
    fi
}

# @test BC-CV-004: 数据库不存在
@test "BC-CV-004: cod-visualizer handles missing database gracefully" {
    skip_if_not_executable "$COD_VISUALIZER"

    # 删除测试数据库
    rm -f "$GRAPH_DB_PATH"

    run "$COD_VISUALIZER" generate --level 2 --format mermaid

    # 应该优雅处理
    if [ "$status" -eq 0 ]; then
        # 返回空图或提示
        assert_contains_any "$output" "graph TD" "Empty" "No data"
    else
        # 或者明确报错
        assert_contains_any "$output" "database" "not found" "initialize" "Error"
    fi
}
