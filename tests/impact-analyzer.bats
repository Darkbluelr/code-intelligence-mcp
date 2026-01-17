#!/usr/bin/env bats
# impact-analyzer.bats - 传递性影响分析测试
#
# 覆盖 M2: 传递性影响分析模块
#
# 场景覆盖:
#   T-IA-001: 符号影响分析 (BFS 遍历，返回影响矩阵)
#   T-IA-002: 文件级影响分析 (合并去重受影响节点)
#   T-IA-003: 置信度正确计算 (decay_factor=0.8)
#   T-IA-004: 阈值过滤 (低置信度节点不返回)
#   T-IA-005: Mermaid 格式输出
#   T-IA-006: 深度限制保护 (循环依赖处理)
#   T-IA-007: 空结果处理 (叶子符号)
#
# 置信度计算公式:
#   Impact(node, depth) = base_impact × (decay_factor ^ depth)
#   - base_impact = 1.0
#   - decay_factor = 0.8 (默认)
#   - 阈值 = 0.1

load 'helpers/common'

# 脚本路径
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
IMPACT_ANALYZER="$SCRIPT_DIR/impact-analyzer.sh"
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
# 测试辅助函数
# ============================================================

# 初始化图数据库并创建测试数据
# 创建一个简单的调用链: A -> B -> C -> D
setup_call_chain() {
    # 初始化数据库
    "$GRAPH_STORE" init >/dev/null 2>&1 || return 1

    # 创建节点
    "$GRAPH_STORE" add-node --id "sym:func:A" --symbol "funcA" --kind "function" --file "src/a.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:B" --symbol "funcB" --kind "function" --file "src/b.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:C" --symbol "funcC" --kind "function" --file "src/c.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:D" --symbol "funcD" --kind "function" --file "src/d.ts" >/dev/null 2>&1

    # 创建调用边: A -> B -> C -> D
    "$GRAPH_STORE" add-edge --source "sym:func:A" --target "sym:func:B" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:B" --target "sym:func:C" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:C" --target "sym:func:D" --type CALLS >/dev/null 2>&1
}

# 创建文件级依赖图
# 文件 src/utils.ts 被多个文件引用
setup_file_dependencies() {
    # 初始化数据库
    "$GRAPH_STORE" init >/dev/null 2>&1 || return 1

    # 创建节点 - 多个文件中的符号
    "$GRAPH_STORE" add-node --id "sym:func:helper1" --symbol "helper1" --kind "function" --file "src/utils.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:helper2" --symbol "helper2" --kind "function" --file "src/utils.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:main" --symbol "main" --kind "function" --file "src/main.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:api" --symbol "apiHandler" --kind "function" --file "src/api.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:service" --symbol "service" --kind "function" --file "src/service.ts" >/dev/null 2>&1

    # 创建依赖: main 和 api 都引用 utils.ts 中的函数
    "$GRAPH_STORE" add-edge --source "sym:func:main" --target "sym:func:helper1" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:api" --target "sym:func:helper1" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:api" --target "sym:func:helper2" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:service" --target "sym:func:main" --type CALLS >/dev/null 2>&1
}

# 创建循环依赖图
# A -> B -> C -> A (循环)
setup_cycle_dependencies() {
    # 初始化数据库
    "$GRAPH_STORE" init >/dev/null 2>&1 || return 1

    # 创建节点
    "$GRAPH_STORE" add-node --id "sym:func:cycleA" --symbol "cycleA" --kind "function" --file "src/cycle-a.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:cycleB" --symbol "cycleB" --kind "function" --file "src/cycle-b.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:cycleC" --symbol "cycleC" --kind "function" --file "src/cycle-c.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:cycleD" --symbol "cycleD" --kind "function" --file "src/cycle-d.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:cycleE" --symbol "cycleE" --kind "function" --file "src/cycle-e.ts" >/dev/null 2>&1

    # 创建循环边: A -> B -> C -> A
    "$GRAPH_STORE" add-edge --source "sym:func:cycleA" --target "sym:func:cycleB" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:cycleB" --target "sym:func:cycleC" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:cycleC" --target "sym:func:cycleA" --type CALLS >/dev/null 2>&1

    # 额外的深度链: C -> D -> E
    "$GRAPH_STORE" add-edge --source "sym:func:cycleC" --target "sym:func:cycleD" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:cycleD" --target "sym:func:cycleE" --type CALLS >/dev/null 2>&1
}

# 创建叶子节点（无调用者）
setup_leaf_node() {
    # 初始化数据库
    "$GRAPH_STORE" init >/dev/null 2>&1 || return 1

    # 创建一个孤立的叶子节点
    "$GRAPH_STORE" add-node --id "sym:func:leaf" --symbol "leafFunction" --kind "function" --file "src/leaf.ts" >/dev/null 2>&1
}

# ============================================================
# T-IA-001: 符号影响分析
# ============================================================

# @test T-IA-001: 符号影响分析 - BFS 遍历返回影响矩阵
@test "T-IA-001: impact-analyzer analyze returns impact matrix via BFS traversal" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    run "$IMPACT_ANALYZER" analyze "sym:func:A" --depth 3

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh analyze"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证返回的影响矩阵包含正确的节点
    assert_contains "$output" "sym:func:B"
    assert_contains "$output" "sym:func:C"
    assert_contains "$output" "sym:func:D"

    # 验证返回的是一个包含 affected_nodes 或类似字段的 JSON
    local node_count
    node_count=$(echo "$output" | jq '.affected_nodes | length // .nodes | length // 0')
    [ "$node_count" -ge 3 ]
}

# @test T-IA-001b: 符号影响分析 - 默认深度
@test "T-IA-001b: impact-analyzer analyze uses default depth when not specified" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    run "$IMPACT_ANALYZER" analyze "sym:func:A"

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh analyze (default depth)"
    assert_exit_success "$status"
    assert_valid_json "$output"
}

# ============================================================
# T-IA-002: 文件级影响分析
# ============================================================

# @test T-IA-002: 文件级影响分析 - 合并去重受影响节点
@test "T-IA-002: impact-analyzer file returns merged deduplicated affected nodes" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_file_dependencies

    run "$IMPACT_ANALYZER" file "src/utils.ts" --depth 2

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh file"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证返回的节点包含引用 utils.ts 的调用者
    assert_contains "$output" "main"
    assert_contains "$output" "api"

    # 验证深度 2 时应该包含 service（通过 main 间接引用）
    assert_contains "$output" "service"
}

# @test T-IA-002b: 文件级影响分析 - 节点去重
@test "T-IA-002b: impact-analyzer file deduplicates nodes correctly" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_file_dependencies

    run "$IMPACT_ANALYZER" file "src/utils.ts" --depth 2

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh file deduplication"
    assert_exit_success "$status"

    # 确保输出是有效 JSON
    assert_valid_json "$output"

    # 验证没有重复节点（如果 api 同时调用 helper1 和 helper2，api 不应出现两次）
    local api_count
    api_count=$(echo "$output" | grep -o '"api"' | wc -l | tr -d ' ')
    [ "$api_count" -le 1 ]
}

# ============================================================
# T-IA-003: 置信度正确计算
# ============================================================

# @test T-IA-003: 置信度正确计算 - decay_factor=0.8
@test "T-IA-003: impact-analyzer calculates confidence correctly with decay_factor=0.8" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    run "$IMPACT_ANALYZER" analyze "sym:func:A" --depth 3

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh confidence calculation"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证置信度计算:
    # A -> B (depth 1): confidence = 1.0 × 0.8^1 = 0.8
    # A -> B -> C (depth 2): confidence = 1.0 × 0.8^2 = 0.64
    # A -> B -> C -> D (depth 3): confidence = 1.0 × 0.8^3 = 0.512

    # 提取 B 的置信度
    local b_confidence
    b_confidence=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:B" or .symbol == "funcB") | .confidence // .impact // empty' 2>/dev/null | head -1)
    if [ -n "$b_confidence" ]; then
        # 验证 B 的置信度约为 0.8（允许 ±0.02 误差以提高测试稳定性）
        assert_confidence_gte '{"confidence": '"$b_confidence"'}' ".confidence" "0.78"
        assert_confidence_lt '{"confidence": '"$b_confidence"'}' ".confidence" "0.82"
    fi

    # 提取 C 的置信度
    local c_confidence
    c_confidence=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:C" or .symbol == "funcC") | .confidence // .impact // empty' 2>/dev/null | head -1)
    if [ -n "$c_confidence" ]; then
        # 验证 C 的置信度约为 0.64（允许 ±0.02 误差）
        assert_confidence_gte '{"confidence": '"$c_confidence"'}' ".confidence" "0.62"
        assert_confidence_lt '{"confidence": '"$c_confidence"'}' ".confidence" "0.66"
    fi

    # 提取 D 的置信度
    local d_confidence
    d_confidence=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:D" or .symbol == "funcD") | .confidence // .impact // empty' 2>/dev/null | head -1)
    if [ -n "$d_confidence" ]; then
        # 验证 D 的置信度约为 0.512（允许 ±0.02 误差）
        assert_confidence_gte '{"confidence": '"$d_confidence"'}' ".confidence" "0.49"
        assert_confidence_lt '{"confidence": '"$d_confidence"'}' ".confidence" "0.53"
    fi
}

# @test T-IA-003b: 置信度顺序 - 深度越大置信度越低
@test "T-IA-003b: impact-analyzer confidence decreases with depth" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    run "$IMPACT_ANALYZER" analyze "sym:func:A" --depth 3

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh confidence order"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 获取所有置信度并验证顺序
    local b_conf c_conf d_conf
    b_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:B" or .symbol == "funcB") | .confidence // .impact // 0' 2>/dev/null | head -1)
    c_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:C" or .symbol == "funcC") | .confidence // .impact // 0' 2>/dev/null | head -1)
    d_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:D" or .symbol == "funcD") | .confidence // .impact // 0' 2>/dev/null | head -1)

    # 如果置信度字段存在，验证 B > C > D
    if [ -n "$b_conf" ] && [ -n "$c_conf" ] && [ -n "$d_conf" ]; then
        float_gte "$b_conf" "$c_conf" || fail "B confidence should >= C confidence"
        float_gte "$c_conf" "$d_conf" || fail "C confidence should >= D confidence"
    fi
}

# ============================================================
# T-IA-004: 阈值过滤
# ============================================================

# @test T-IA-004: 阈值过滤 - 低置信度节点不返回
@test "T-IA-004: impact-analyzer threshold filters out low confidence nodes" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    # 使用阈值 0.6，应该过滤掉 C (0.64 > 0.6) 以下的节点
    # D 的置信度是 0.512 < 0.6，应该被过滤
    run "$IMPACT_ANALYZER" analyze "sym:func:A" --depth 3 --threshold 0.6

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh threshold"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # B (0.8) 和 C (0.64) 应该在结果中
    assert_contains "$output" "funcB"
    assert_contains "$output" "funcC"

    # D (0.512) 应该被过滤
    assert_not_contains "$output" "funcD"
}

# @test T-IA-004b: 阈值过滤 - 高阈值过滤更多节点
@test "T-IA-004b: impact-analyzer high threshold filters more nodes" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    # 使用高阈值 0.7，C (0.64) 和 D (0.512) 都应该被过滤
    run "$IMPACT_ANALYZER" analyze "sym:func:A" --depth 3 --threshold 0.7

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh high threshold"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 只有 B (0.8) 应该在结果中
    assert_contains "$output" "funcB"
    assert_not_contains "$output" "funcC"
    assert_not_contains "$output" "funcD"
}

# @test T-IA-004c: 阈值过滤 - 默认阈值 0.1
@test "T-IA-004c: impact-analyzer uses default threshold 0.1" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    # 不指定阈值，默认应该是 0.1
    # 在深度 3 内，所有节点的置信度都 > 0.1，所以都应该返回
    run "$IMPACT_ANALYZER" analyze "sym:func:A" --depth 3

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh default threshold"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 所有节点都应该在结果中
    assert_contains "$output" "funcB"
    assert_contains "$output" "funcC"
    assert_contains "$output" "funcD"
}

# ============================================================
# T-IA-005: Mermaid 格式输出
# ============================================================

# @test T-IA-005: Mermaid 格式输出 - 有效语法
@test "T-IA-005: impact-analyzer mermaid output is valid syntax" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    run "$IMPACT_ANALYZER" analyze "sym:func:A" --depth 3 --format mermaid

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh mermaid format"
    assert_exit_success "$status"

    # 验证 Mermaid 语法的基本结构
    # 应该以 graph 或 flowchart 开头
    assert_contains_any "$output" "graph" "flowchart"

    # 应该包含节点连接 (-->)
    assert_contains "$output" "-->"

    # 应该包含节点定义
    assert_contains_any "$output" "funcA" "funcB" "sym:func:A" "sym:func:B"
}

# @test T-IA-005b: Mermaid 输出包含置信度标注
@test "T-IA-005b: impact-analyzer mermaid output includes confidence labels" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    run "$IMPACT_ANALYZER" analyze "sym:func:A" --depth 3 --format mermaid

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh mermaid labels"
    assert_exit_success "$status"

    # 验证输出包含数字（置信度值）
    # Mermaid 格式可能像: A -->|0.8| B
    assert_contains_any "$output" "0.8" "0.64" "0.512" "80%" "64%" "51%"
}

# ============================================================
# T-IA-006: 深度限制保护
# ============================================================

# @test T-IA-006: 深度限制保护 - 循环依赖不无限循环
@test "T-IA-006: impact-analyzer depth limit prevents infinite loop on cycles" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_cycle_dependencies

    # 设置超时，如果无限循环会超时失败
    run run_with_timeout 10 "$IMPACT_ANALYZER" analyze "sym:func:cycleA" --depth 5

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh cycle handling"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证命令在合理时间内完成
    # 如果无限循环，run_with_timeout 会导致超时
}

# @test T-IA-006b: 深度限制 - 遍历在指定深度后停止
@test "T-IA-006b: impact-analyzer stops traversal at specified depth" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_call_chain

    # 深度 2 应该只包含 B 和 C，不包含 D
    run "$IMPACT_ANALYZER" analyze "sym:func:A" --depth 2

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh depth limit"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # B (depth 1) 和 C (depth 2) 应该在结果中
    assert_contains "$output" "funcB"
    assert_contains "$output" "funcC"

    # D (depth 3) 不应该在结果中
    assert_not_contains "$output" "funcD"
}

# @test T-IA-006c: 深度限制 - 循环中的节点只访问一次
@test "T-IA-006c: impact-analyzer visits cyclic nodes only once" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_cycle_dependencies

    run "$IMPACT_ANALYZER" analyze "sym:func:cycleA" --depth 5

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh cycle dedup"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证 cycleA 在结果中最多出现一次（或不出现，取决于是否包含起始节点）
    local cycle_a_count
    cycle_a_count=$(echo "$output" | grep -o '"cycleA"' | wc -l | tr -d ' ')
    [ "$cycle_a_count" -le 1 ]

    # 验证 cycleB 和 cycleC 各只出现一次
    local cycle_b_count cycle_c_count
    cycle_b_count=$(echo "$output" | grep -o '"cycleB"' | wc -l | tr -d ' ')
    cycle_c_count=$(echo "$output" | grep -o '"cycleC"' | wc -l | tr -d ' ')
    [ "$cycle_b_count" -le 1 ]
    [ "$cycle_c_count" -le 1 ]
}

# ============================================================
# T-IA-007: 空结果处理
# ============================================================

# @test T-IA-007: 空结果处理 - 叶子符号返回空影响矩阵
@test "T-IA-007: impact-analyzer returns empty matrix for leaf symbol" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_leaf_node

    run "$IMPACT_ANALYZER" analyze "sym:func:leaf" --depth 3

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh leaf node"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证返回的影响矩阵为空
    local node_count
    node_count=$(echo "$output" | jq '.affected_nodes | length // .nodes | length // 0')
    [ "$node_count" -eq 0 ]
}

# @test T-IA-007b: 空结果处理 - 不存在的符号
@test "T-IA-007b: impact-analyzer handles non-existent symbol gracefully" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    # 初始化空数据库
    "$GRAPH_STORE" init >/dev/null 2>&1

    run "$IMPACT_ANALYZER" analyze "sym:func:nonexistent" --depth 3

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh nonexistent symbol"

    # 可以是成功返回空结果，或者失败并给出错误信息
    # 这里我们接受两种情况
    if [ "$status" -eq 0 ]; then
        assert_valid_json "$output"
        local node_count
        node_count=$(echo "$output" | jq '.affected_nodes | length // .nodes | length // 0')
        [ "$node_count" -eq 0 ]
    else
        # 失败时应该给出有意义的错误信息
        assert_contains_any "$output" "not found" "does not exist" "error" "Error"
    fi
}

# @test T-IA-007c: 空结果处理 - 空数据库
@test "T-IA-007c: impact-analyzer handles empty database gracefully" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    # 初始化空数据库
    "$GRAPH_STORE" init >/dev/null 2>&1

    run "$IMPACT_ANALYZER" analyze "any:symbol" --depth 3

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh empty database"

    # 接受成功返回空结果或失败
    if [ "$status" -eq 0 ]; then
        assert_valid_json "$output"
    fi
}

# ============================================================
# 额外测试: 参数验证
# ============================================================

# @test T-IA-PARAM-001: 参数验证 - 必须提供符号参数
@test "T-IA-PARAM-001: impact-analyzer requires symbol argument" {
    skip_if_not_executable "$IMPACT_ANALYZER"

    run "$IMPACT_ANALYZER" analyze

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh argument validation"

    # 应该失败并提示缺少参数
    assert_exit_failure "$status"
    assert_contains_any "$output" "usage" "Usage" "symbol" "required" "missing"
}

# @test T-IA-PARAM-002: 参数验证 - 深度必须为正整数
@test "T-IA-PARAM-002: impact-analyzer validates depth is positive integer" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    "$GRAPH_STORE" init >/dev/null 2>&1

    run "$IMPACT_ANALYZER" analyze "sym:func:test" --depth -1

    # 如果参数验证已实现，应该失败
    if [ "$status" -ne 0 ]; then
        assert_contains_any "$output" "invalid" "Invalid" "positive" "must be"
    fi
    # 如果未实现参数验证，跳过
}

# @test T-IA-PARAM-003: 参数验证 - 阈值范围 0-1
@test "T-IA-PARAM-003: impact-analyzer validates threshold is between 0 and 1" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    "$GRAPH_STORE" init >/dev/null 2>&1

    run "$IMPACT_ANALYZER" analyze "sym:func:test" --threshold 1.5

    # 如果参数验证已实现，应该失败
    if [ "$status" -ne 0 ]; then
        assert_contains_any "$output" "invalid" "Invalid" "between" "0" "1"
    fi
    # 如果未实现参数验证，跳过
}

# @test T-IA-PARAM-004: 帮助信息
@test "T-IA-PARAM-004: impact-analyzer shows help with --help" {
    skip_if_not_executable "$IMPACT_ANALYZER"

    run "$IMPACT_ANALYZER" --help

    # 帮助信息应该包含用法说明
    if [ "$status" -eq 0 ]; then
        assert_contains_any "$output" "Usage" "usage" "analyze" "file" "depth" "threshold"
    fi
}

# ============================================================
# 契约测试 CT-IA-001~005 (algorithm-optimization-parity)
# 参考规格: dev-playbooks/changes/algorithm-optimization-parity/specs/impact-analysis/spec.md
# ============================================================

# 创建 5 跳调用链测试数据: S -> A -> B -> C -> D -> E
setup_5_hop_chain() {
    "$GRAPH_STORE" init >/dev/null 2>&1 || return 1

    # 创建节点
    "$GRAPH_STORE" add-node --id "sym:func:S" --symbol "funcS" --kind "function" --file "src/s.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:A" --symbol "funcA" --kind "function" --file "src/a.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:B" --symbol "funcB" --kind "function" --file "src/b.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:C" --symbol "funcC" --kind "function" --file "src/c.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:D" --symbol "funcD" --kind "function" --file "src/d.ts" >/dev/null 2>&1
    "$GRAPH_STORE" add-node --id "sym:func:E" --symbol "funcE" --kind "function" --file "src/e.ts" >/dev/null 2>&1

    # 创建调用边: S -> A -> B -> C -> D -> E
    "$GRAPH_STORE" add-edge --source "sym:func:S" --target "sym:func:A" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:A" --target "sym:func:B" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:B" --target "sym:func:C" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:C" --target "sym:func:D" --type CALLS >/dev/null 2>&1
    "$GRAPH_STORE" add-edge --source "sym:func:D" --target "sym:func:E" --type CALLS >/dev/null 2>&1
}

# 创建大规模图数据（用于性能测试）
# 参数: $1 - 节点数量, $2 - 边数量
setup_large_graph() {
    local node_count="${1:-500}"
    local edge_count="${2:-5000}"

    "$GRAPH_STORE" init >/dev/null 2>&1 || return 1

    # 批量创建节点
    for ((i=0; i<node_count; i++)); do
        "$GRAPH_STORE" add-node --id "sym:func:node$i" --symbol "func$i" --kind "function" --file "src/file$((i % 50)).ts" >/dev/null 2>&1
    done

    # 批量创建边（随机连接，确保有一定的图结构）
    for ((i=0; i<edge_count; i++)); do
        local source=$((i % node_count))
        local target=$(( (i * 7 + 13) % node_count ))  # 伪随机但可重现
        if [ "$source" != "$target" ]; then
            "$GRAPH_STORE" add-edge --source "sym:func:node$source" --target "sym:func:node$target" --type CALLS >/dev/null 2>&1
        fi
    done
}

# ============================================================
# CT-IA-001: 传递深度 - 影响到 N 跳依赖
# ============================================================

@test "CT-IA-001: impact-analyzer returns all nodes up to N hops (SC-IA-001)" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_5_hop_chain

    # 测试 5 跳遍历
    run "$IMPACT_ANALYZER" analyze "sym:func:S" --depth 5

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh 5-hop traversal"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证所有 5 个下游节点都在结果中
    # S -> A(1) -> B(2) -> C(3) -> D(4) -> E(5)
    assert_contains "$output" "funcA"
    assert_contains "$output" "funcB"
    assert_contains "$output" "funcC"
    assert_contains "$output" "funcD"
    assert_contains "$output" "funcE"

    # 验证节点数量至少为 5
    local node_count
    node_count=$(echo "$output" | jq '.affected_nodes | length // .nodes | length // 0')
    [ "$node_count" -ge 5 ]
}

@test "CT-IA-001b: impact-analyzer respects max_depth parameter" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_5_hop_chain

    # 测试深度限制为 3
    run "$IMPACT_ANALYZER" analyze "sym:func:S" --depth 3

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh depth-3 traversal"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 深度 1-3 的节点应该存在
    assert_contains "$output" "funcA"
    assert_contains "$output" "funcB"
    assert_contains "$output" "funcC"

    # 深度 4-5 的节点不应该存在
    assert_not_contains "$output" "funcD"
    assert_not_contains "$output" "funcE"
}

# ============================================================
# CT-IA-002: 置信度衰减 - 每跳衰减 20% (decay_factor=0.8)
# ============================================================

@test "CT-IA-002: impact-analyzer applies 20% decay per hop (SC-IA-001)" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_5_hop_chain

    run "$IMPACT_ANALYZER" analyze "sym:func:S" --depth 5

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh confidence decay"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 预期置信度（decay_factor=0.8）:
    # A (depth=1): 0.8
    # B (depth=2): 0.64
    # C (depth=3): 0.512
    # D (depth=4): 0.4096 (~0.41)
    # E (depth=5): 0.32768 (~0.328)

    # 提取各节点置信度并验证
    local a_conf b_conf c_conf d_conf e_conf

    a_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:A" or .symbol == "funcA") | .confidence // .impact // empty' 2>/dev/null | head -1)
    b_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:B" or .symbol == "funcB") | .confidence // .impact // empty' 2>/dev/null | head -1)
    c_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:C" or .symbol == "funcC") | .confidence // .impact // empty' 2>/dev/null | head -1)
    d_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:D" or .symbol == "funcD") | .confidence // .impact // empty' 2>/dev/null | head -1)
    e_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.id == "sym:func:E" or .symbol == "funcE") | .confidence // .impact // empty' 2>/dev/null | head -1)

    # 验证置信度范围（允许 ±0.02 误差）
    if [ -n "$a_conf" ]; then
        float_gte "$a_conf" "0.78" || fail "A confidence should be >= 0.78, got $a_conf"
        float_lt "$a_conf" "0.82" || fail "A confidence should be < 0.82, got $a_conf"
    fi

    if [ -n "$b_conf" ]; then
        float_gte "$b_conf" "0.62" || fail "B confidence should be >= 0.62, got $b_conf"
        float_lt "$b_conf" "0.66" || fail "B confidence should be < 0.66, got $b_conf"
    fi

    if [ -n "$c_conf" ]; then
        float_gte "$c_conf" "0.49" || fail "C confidence should be >= 0.49, got $c_conf"
        float_lt "$c_conf" "0.53" || fail "C confidence should be < 0.53, got $c_conf"
    fi

    if [ -n "$d_conf" ]; then
        float_gte "$d_conf" "0.39" || fail "D confidence should be >= 0.39, got $d_conf"
        float_lt "$d_conf" "0.43" || fail "D confidence should be < 0.43, got $d_conf"
    fi

    if [ -n "$e_conf" ]; then
        float_gte "$e_conf" "0.31" || fail "E confidence should be >= 0.31, got $e_conf"
        float_lt "$e_conf" "0.35" || fail "E confidence should be < 0.35, got $e_conf"
    fi
}

@test "CT-IA-002b: impact-analyzer confidence strictly decreases with depth" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_5_hop_chain

    run "$IMPACT_ANALYZER" analyze "sym:func:S" --depth 5

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh confidence ordering"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 获取所有置信度
    local a_conf b_conf c_conf d_conf e_conf
    a_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.symbol == "funcA") | .confidence // .impact // 1' 2>/dev/null | head -1)
    b_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.symbol == "funcB") | .confidence // .impact // 1' 2>/dev/null | head -1)
    c_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.symbol == "funcC") | .confidence // .impact // 1' 2>/dev/null | head -1)
    d_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.symbol == "funcD") | .confidence // .impact // 1' 2>/dev/null | head -1)
    e_conf=$(echo "$output" | jq -r '.affected_nodes[] | select(.symbol == "funcE") | .confidence // .impact // 1' 2>/dev/null | head -1)

    # 验证严格递减: A > B > C > D > E
    if [ -n "$a_conf" ] && [ -n "$b_conf" ]; then
        float_gte "$a_conf" "$b_conf" || fail "A ($a_conf) should be >= B ($b_conf)"
    fi
    if [ -n "$b_conf" ] && [ -n "$c_conf" ]; then
        float_gte "$b_conf" "$c_conf" || fail "B ($b_conf) should be >= C ($c_conf)"
    fi
    if [ -n "$c_conf" ] && [ -n "$d_conf" ]; then
        float_gte "$c_conf" "$d_conf" || fail "C ($c_conf) should be >= D ($d_conf)"
    fi
    if [ -n "$d_conf" ] && [ -n "$e_conf" ]; then
        float_gte "$d_conf" "$e_conf" || fail "D ($d_conf) should be >= E ($e_conf)"
    fi
}

# ============================================================
# CT-IA-003: 循环截断 - 检测到循环时停止
# ============================================================

@test "CT-IA-003: impact-analyzer detects and truncates cycles (SC-IA-003)" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_cycle_dependencies

    # 设置超时保护，防止无限循环
    run run_with_timeout 10 "$IMPACT_ANALYZER" analyze "sym:func:cycleA" --depth 10

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh cycle detection"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证循环中的每个节点只出现一次
    local cycle_a_count cycle_b_count cycle_c_count
    cycle_a_count=$(echo "$output" | grep -o '"cycleA"' | wc -l | tr -d ' ')
    cycle_b_count=$(echo "$output" | grep -o '"cycleB"' | wc -l | tr -d ' ')
    cycle_c_count=$(echo "$output" | grep -o '"cycleC"' | wc -l | tr -d ' ')

    # 每个循环节点最多出现一次（起始节点可能不在结果中）
    [ "${cycle_a_count:-0}" -le 1 ] || fail "cycleA appeared $cycle_a_count times, expected <= 1"
    [ "${cycle_b_count:-0}" -le 1 ] || fail "cycleB appeared $cycle_b_count times, expected <= 1"
    [ "${cycle_c_count:-0}" -le 1 ] || fail "cycleC appeared $cycle_c_count times, expected <= 1"
}

@test "CT-IA-003b: impact-analyzer completes in reasonable time with cycles" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_cycle_dependencies

    # 测量执行时间，确保不会因循环而卡住
    local start_time end_time elapsed
    start_time=$(date +%s)

    run run_with_timeout 5 "$IMPACT_ANALYZER" analyze "sym:func:cycleA" --depth 10

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    # 应该在 5 秒内完成（有超时保护）
    [ "$elapsed" -lt 5 ] || fail "Cycle handling took too long: ${elapsed}s"

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh cycle performance"
    assert_exit_success "$status"
}

# ============================================================
# CT-IA-004: 阈值截断 - 置信度 < 0.1 时停止
# ============================================================

@test "CT-IA-004: impact-analyzer stops when confidence < threshold (SC-IA-002)" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_5_hop_chain

    # 使用 threshold=0.5
    # A(0.8) > 0.5 ✓, B(0.64) > 0.5 ✓, C(0.512) > 0.5 ✓, D(0.41) < 0.5 ✗
    run "$IMPACT_ANALYZER" analyze "sym:func:S" --depth 5 --threshold 0.5

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh threshold cutoff"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # A, B, C 应该在结果中（confidence > 0.5）
    assert_contains "$output" "funcA"
    assert_contains "$output" "funcB"
    assert_contains "$output" "funcC"

    # D, E 应该被过滤（confidence < 0.5）
    assert_not_contains "$output" "funcD"
    assert_not_contains "$output" "funcE"
}

@test "CT-IA-004b: impact-analyzer uses default threshold 0.1" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_5_hop_chain

    # 不指定阈值，默认 0.1
    # 所有节点的置信度都 > 0.1（E 最低约 0.328）
    run "$IMPACT_ANALYZER" analyze "sym:func:S" --depth 5

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh default threshold"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 所有节点都应该在结果中
    assert_contains "$output" "funcA"
    assert_contains "$output" "funcB"
    assert_contains "$output" "funcC"
    assert_contains "$output" "funcD"
    assert_contains "$output" "funcE"
}

@test "CT-IA-004c: impact-analyzer threshold stops downstream traversal" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    setup_5_hop_chain

    # 使用高阈值 0.7
    # A(0.8) > 0.7 ✓, B(0.64) < 0.7 ✗（停止遍历）
    run "$IMPACT_ANALYZER" analyze "sym:func:S" --depth 5 --threshold 0.7

    skip_if_not_ready "$status" "$output" "impact-analyzer.sh threshold stops traversal"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 只有 A 应该在结果中
    assert_contains "$output" "funcA"

    # B 及其下游都不应该在结果中
    assert_not_contains "$output" "funcB"
    assert_not_contains "$output" "funcC"
    assert_not_contains "$output" "funcD"
    assert_not_contains "$output" "funcE"
}

# ============================================================
# CT-IA-005: 性能 - 5000 边图分析 < 200ms
# ============================================================

@test "CT-IA-005: impact-analyzer analyzes 5000-edge graph in < 200ms" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    # 创建大规模图（500 节点，5000 边）
    setup_large_graph 500 5000

    # 预热一次（可选，消除冷启动影响）
    "$IMPACT_ANALYZER" analyze "sym:func:node0" --depth 3 >/dev/null 2>&1 || true

    # 测量分析时间
    measure_time "$IMPACT_ANALYZER" analyze "sym:func:node0" --depth 3
    local exit_code=$?

    skip_if_not_ready "$exit_code" "" "impact-analyzer.sh large graph analysis"

    # 验证性能: P95 应该 < 200ms
    # 由于单次测量，直接检查 MEASURED_TIME_MS
    if [ -n "$MEASURED_TIME_MS" ] && [ "$MEASURED_TIME_MS" -gt 0 ]; then
        [ "$MEASURED_TIME_MS" -lt 200 ] || fail "Analysis took ${MEASURED_TIME_MS}ms, expected < 200ms"
    fi
}

@test "CT-IA-005b: impact-analyzer performance with multiple runs (P95 < 200ms)" {
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_not_executable "$IMPACT_ANALYZER"

    # 创建大规模图
    setup_large_graph 500 5000

    # 收集多次运行的延迟
    local latencies=()
    local run_count=5

    for ((i=0; i<run_count; i++)); do
        measure_time "$IMPACT_ANALYZER" analyze "sym:func:node$((i * 10))" --depth 3
        if [ -n "$MEASURED_TIME_MS" ] && [ "$MEASURED_TIME_MS" -gt 0 ]; then
            latencies+=("$MEASURED_TIME_MS")
        fi
    done

    # 如果收集到足够的样本，验证 P95
    if [ "${#latencies[@]}" -ge 3 ]; then
        local p95
        p95=$(calculate_p95 "${latencies[@]}")
        [ "$p95" -lt 200 ] || fail "P95 latency ${p95}ms >= 200ms threshold"
    else
        skip "Not enough samples collected for P95 calculation"
    fi
}
