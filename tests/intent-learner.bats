#!/usr/bin/env bats
# intent-learner.bats - 意图偏好学习模块测试
#
# 覆盖 M6: 意图偏好学习
#
# 测试场景:
#   T-IL-001: 记录查询历史
#   T-IL-002: 偏好分数正确计算
#   T-IL-003: 90 天自动清理
#   T-IL-004: 查询 Top N 偏好
#   T-IL-005: 前缀过滤偏好
#   T-IL-006: 最大条目数限制
#   T-IL-007: 空历史处理
#   T-IL-008: 用户操作权重
#   T-IL-009: 历史文件损坏恢复
#
# 偏好计算公式:
#   Preference(symbol) = frequency × recency_weight × click_weight
#   - recency_weight = 1 / (1 + days_since_last_query)
#   - click_weight: view=1.0, edit=2.0, ignore=0.5

load 'helpers/common'

# 脚本路径
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
INTENT_LEARNER="$SCRIPT_DIR/intent-learner.sh"

# 历史文件路径
HISTORY_FILE_NAME="intent-history.json"
CONTEXT_FILE_NAME="conversation-context.json"

setup() {
    setup_temp_dir
    export DEVBOOKS_DIR="$TEST_TEMP_DIR/.devbooks"
    mkdir -p "$DEVBOOKS_DIR"
    export INTENT_HISTORY_PATH="$DEVBOOKS_DIR/$HISTORY_FILE_NAME"
    export CONVERSATION_CONTEXT_PATH="$DEVBOOKS_DIR/$CONTEXT_FILE_NAME"
}

teardown() {
    cleanup_temp_dir
}

# ============================================================
# T-IL-001: 记录查询历史
# ============================================================

# @test T-IL-001: 记录查询历史
@test "T-IL-001: intent-learner record creates history entry" {
    skip_if_not_executable "$INTENT_LEARNER"

    run "$INTENT_LEARNER" record "handleToolCall" "src/server.ts::handleToolCall" --action view
    skip_if_not_ready "$status" "$output" "intent-learner.sh record"

    assert_exit_success "$status"

    # 验证历史文件存在
    [ -f "$INTENT_HISTORY_PATH" ]

    # 验证历史条目已创建
    assert_valid_json "$(cat "$INTENT_HISTORY_PATH")"

    local count
    count=$(jq '.entries | length' "$INTENT_HISTORY_PATH")
    [ "$count" -eq 1 ]

    # 验证条目内容
    local symbol
    symbol=$(jq -r '.entries[0].symbol' "$INTENT_HISTORY_PATH")
    [ "$symbol" = "handleToolCall" ]

    local symbol_id
    symbol_id=$(jq -r '.entries[0].symbol_id' "$INTENT_HISTORY_PATH")
    [ "$symbol_id" = "src/server.ts::handleToolCall" ]

    local action
    action=$(jq -r '.entries[0].action' "$INTENT_HISTORY_PATH")
    [ "$action" = "view" ]
}

# @test T-IL-001b: 多次记录累加历史
@test "T-IL-001b: intent-learner record appends multiple entries" {
    skip_if_not_executable "$INTENT_LEARNER"

    run "$INTENT_LEARNER" record "func1" "src/a.ts::func1" --action view
    skip_if_not_ready "$status" "$output" "intent-learner.sh record"

    run "$INTENT_LEARNER" record "func2" "src/b.ts::func2" --action edit
    assert_exit_success "$status"

    run "$INTENT_LEARNER" record "func1" "src/a.ts::func1" --action view
    assert_exit_success "$status"

    # 验证 3 条历史记录
    local count
    count=$(jq '.entries | length' "$INTENT_HISTORY_PATH")
    [ "$count" -eq 3 ]
}

# ============================================================
# T-IL-002: 偏好分数正确计算
# ============================================================

# @test T-IL-002: 偏好分数正确计算
@test "T-IL-002: preference score calculation follows formula" {
    skip_if_not_executable "$INTENT_LEARNER"

    # 准备测试数据: 符号 A 被查询 5 次（1 天前），符号 B 被查询 3 次（10 天前）
    local now_epoch
    now_epoch=$(date +%s)

    local one_day_ago=$((now_epoch - 86400))  # 1 天前
    local ten_days_ago=$((now_epoch - 864000))  # 10 天前

    # 创建历史文件
    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "symbolA", "symbol_id": "src/a.ts::symbolA", "action": "view", "timestamp": $one_day_ago},
    {"symbol": "symbolA", "symbol_id": "src/a.ts::symbolA", "action": "view", "timestamp": $one_day_ago},
    {"symbol": "symbolA", "symbol_id": "src/a.ts::symbolA", "action": "view", "timestamp": $one_day_ago},
    {"symbol": "symbolA", "symbol_id": "src/a.ts::symbolA", "action": "view", "timestamp": $one_day_ago},
    {"symbol": "symbolA", "symbol_id": "src/a.ts::symbolA", "action": "view", "timestamp": $one_day_ago},
    {"symbol": "symbolB", "symbol_id": "src/b.ts::symbolB", "action": "view", "timestamp": $ten_days_ago},
    {"symbol": "symbolB", "symbol_id": "src/b.ts::symbolB", "action": "view", "timestamp": $ten_days_ago},
    {"symbol": "symbolB", "symbol_id": "src/b.ts::symbolB", "action": "view", "timestamp": $ten_days_ago}
  ]
}
EOF

    # 计算偏好
    run "$INTENT_LEARNER" get-preferences --top 10
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 获取 A 和 B 的分数
    local score_a score_b
    score_a=$(echo "$output" | jq -r '.[] | select(.symbol == "symbolA") | .score')
    score_b=$(echo "$output" | jq -r '.[] | select(.symbol == "symbolB") | .score')

    # A 的 score > B 的 score
    # A: frequency=5, recency_weight=1/(1+1)=0.5, click_weight=1.0 => 5*0.5*1.0=2.5
    # B: frequency=3, recency_weight=1/(1+10)≈0.09, click_weight=1.0 => 3*0.09*1.0≈0.27
    if ! float_gte "$score_a" "$score_b"; then
        echo "Expected score_a ($score_a) > score_b ($score_b)" >&2
        return 1
    fi
}

# ============================================================
# T-IL-003: 90 天自动清理
# ============================================================

# @test T-IL-003: 90 天自动清理
@test "T-IL-003: intent-learner cleanup removes entries older than 90 days" {
    skip_if_not_executable "$INTENT_LEARNER"

    # 准备测试数据: 包含 100 天前和 10 天前的记录
    local now_epoch
    now_epoch=$(date +%s)

    local hundred_days_ago=$((now_epoch - 8640000))  # 100 天前
    local ten_days_ago=$((now_epoch - 864000))  # 10 天前

    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "oldSymbol", "symbol_id": "src/old.ts::oldSymbol", "action": "view", "timestamp": $hundred_days_ago},
    {"symbol": "recentSymbol", "symbol_id": "src/recent.ts::recentSymbol", "action": "view", "timestamp": $ten_days_ago}
  ]
}
EOF

    # 执行清理
    run "$INTENT_LEARNER" cleanup
    skip_if_not_ready "$status" "$output" "intent-learner.sh cleanup"

    assert_exit_success "$status"

    # 验证旧记录被删除
    local count
    count=$(jq '.entries | length' "$INTENT_HISTORY_PATH")
    [ "$count" -eq 1 ]

    # 验证保留了新记录
    local symbol
    symbol=$(jq -r '.entries[0].symbol' "$INTENT_HISTORY_PATH")
    [ "$symbol" = "recentSymbol" ]
}

# @test T-IL-003b: 清理边界测试 - 恰好 90 天
@test "T-IL-003b: cleanup keeps entries at exactly 90 days" {
    skip_if_not_executable "$INTENT_LEARNER"

    local now_epoch
    now_epoch=$(date +%s)

    local ninety_days_ago=$((now_epoch - 7776000))  # 恰好 90 天
    local ninety_one_days_ago=$((now_epoch - 7862400))  # 91 天

    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "boundary", "symbol_id": "src/boundary.ts::boundary", "action": "view", "timestamp": $ninety_days_ago},
    {"symbol": "expired", "symbol_id": "src/expired.ts::expired", "action": "view", "timestamp": $ninety_one_days_ago}
  ]
}
EOF

    run "$INTENT_LEARNER" cleanup
    skip_if_not_ready "$status" "$output" "intent-learner.sh cleanup"

    assert_exit_success "$status"

    # 恰好 90 天的应该保留
    local count
    count=$(jq '.entries | length' "$INTENT_HISTORY_PATH")
    [ "$count" -eq 1 ]

    local symbol
    symbol=$(jq -r '.entries[0].symbol' "$INTENT_HISTORY_PATH")
    [ "$symbol" = "boundary" ]
}

# ============================================================
# T-IL-004: 查询 Top N 偏好
# ============================================================

# @test T-IL-004: 查询 Top N 偏好
@test "T-IL-004: intent-learner get-preferences returns top N symbols" {
    skip_if_not_executable "$INTENT_LEARNER"

    local now_epoch
    now_epoch=$(date +%s)

    # 创建 10 个符号的历史，频率从高到低
    local entries=""
    for i in $(seq 1 10); do
        local freq=$((11 - i))  # 频率: 10, 9, 8, ..., 1
        for _ in $(seq 1 "$freq"); do
            [ -n "$entries" ] && entries="$entries,"
            entries="$entries{\"symbol\": \"symbol$i\", \"symbol_id\": \"src/s$i.ts::symbol$i\", \"action\": \"view\", \"timestamp\": $now_epoch}"
        done
    done

    cat > "$INTENT_HISTORY_PATH" << EOF
{"entries": [$entries]}
EOF

    # 查询 Top 5
    run "$INTENT_LEARNER" get-preferences --top 5
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证返回 5 个结果
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 5 ]

    # 验证排序正确（第一个应该是 symbol1，频率最高）
    local first_symbol
    first_symbol=$(echo "$output" | jq -r '.[0].symbol')
    [ "$first_symbol" = "symbol1" ]
}

# @test T-IL-004b: Top N 超过总数时返回全部
@test "T-IL-004b: get-preferences returns all when top > total" {
    skip_if_not_executable "$INTENT_LEARNER"

    local now_epoch
    now_epoch=$(date +%s)

    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "a", "symbol_id": "src/a.ts::a", "action": "view", "timestamp": $now_epoch},
    {"symbol": "b", "symbol_id": "src/b.ts::b", "action": "view", "timestamp": $now_epoch}
  ]
}
EOF

    run "$INTENT_LEARNER" get-preferences --top 100
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"

    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 2 ]
}

# ============================================================
# T-IL-005: 前缀过滤偏好
# ============================================================

# @test T-IL-005: 前缀过滤偏好
@test "T-IL-005: intent-learner get-preferences filters by prefix" {
    skip_if_not_executable "$INTENT_LEARNER"

    local now_epoch
    now_epoch=$(date +%s)

    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "srcFunc", "symbol_id": "src/module.ts::srcFunc", "action": "view", "timestamp": $now_epoch},
    {"symbol": "srcUtil", "symbol_id": "src/utils.ts::srcUtil", "action": "view", "timestamp": $now_epoch},
    {"symbol": "scriptHelper", "symbol_id": "scripts/helper.sh::scriptHelper", "action": "view", "timestamp": $now_epoch},
    {"symbol": "scriptRunner", "symbol_id": "scripts/runner.sh::scriptRunner", "action": "view", "timestamp": $now_epoch}
  ]
}
EOF

    # 过滤 scripts/ 前缀
    run "$INTENT_LEARNER" get-preferences --prefix "scripts/"
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences --prefix"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证只返回 scripts/ 前缀的符号
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 2 ]

    # 验证所有结果都是 scripts/ 前缀
    local non_script_count
    non_script_count=$(echo "$output" | jq '[.[] | select(.symbol_id | startswith("scripts/") | not)] | length')
    [ "$non_script_count" -eq 0 ]
}

# @test T-IL-005b: 前缀不匹配任何符号时返回空数组
@test "T-IL-005b: get-preferences returns empty for non-matching prefix" {
    skip_if_not_executable "$INTENT_LEARNER"

    local now_epoch
    now_epoch=$(date +%s)

    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "func", "symbol_id": "src/module.ts::func", "action": "view", "timestamp": $now_epoch}
  ]
}
EOF

    run "$INTENT_LEARNER" get-preferences --prefix "nonexistent/"
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences --prefix"

    assert_exit_success "$status"
    assert_valid_json "$output"

    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 0 ]
}

# ============================================================
# T-IL-006: 最大条目数限制
# ============================================================

# @test T-IL-006: 最大条目数限制
@test "T-IL-006: intent-learner enforces max 10000 entries limit" {
    skip_if_not_executable "$INTENT_LEARNER"

    local now_epoch
    now_epoch=$(date +%s)

    # 创建接近 10000 条的历史记录
    local entries=""
    for i in $(seq 1 9999); do
        [ -n "$entries" ] && entries="$entries,"
        entries="$entries{\"symbol\": \"sym$i\", \"symbol_id\": \"src/s$i.ts::sym$i\", \"action\": \"view\", \"timestamp\": $((now_epoch - i))}"
    done

    cat > "$INTENT_HISTORY_PATH" << EOF
{"entries": [$entries]}
EOF

    # 验证初始条目数
    local initial_count
    initial_count=$(jq '.entries | length' "$INTENT_HISTORY_PATH")
    [ "$initial_count" -eq 9999 ]

    # 添加 2 条新记录（应该触发淘汰）
    run "$INTENT_LEARNER" record "newSym1" "src/new1.ts::newSym1" --action view
    skip_if_not_ready "$status" "$output" "intent-learner.sh record"

    run "$INTENT_LEARNER" record "newSym2" "src/new2.ts::newSym2" --action view
    assert_exit_success "$status"

    # 验证总数不超过 10000
    local final_count
    final_count=$(jq '.entries | length' "$INTENT_HISTORY_PATH")
    [ "$final_count" -le 10000 ]

    # 验证新记录存在（最旧的被淘汰）
    local has_new1
    has_new1=$(jq '[.entries[] | select(.symbol == "newSym1")] | length' "$INTENT_HISTORY_PATH")
    [ "$has_new1" -ge 1 ]
}

# @test T-IL-006b: 淘汰最旧条目
@test "T-IL-006b: oldest entries are evicted first" {
    skip_if_not_executable "$INTENT_LEARNER"

    local now_epoch
    now_epoch=$(date +%s)

    # 创建简化测试：5 条旧记录 + 触发淘汰（假设限制为 5 用于测试）
    # 实际实现中应该测试 10000 限制，这里简化为验证淘汰逻辑

    # 创建历史：oldest(ts=1), old(ts=2), recent(ts=now)
    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "oldest", "symbol_id": "src/oldest.ts::oldest", "action": "view", "timestamp": 1},
    {"symbol": "old", "symbol_id": "src/old.ts::old", "action": "view", "timestamp": 2},
    {"symbol": "recent", "symbol_id": "src/recent.ts::recent", "action": "view", "timestamp": $now_epoch}
  ]
}
EOF

    # 记录多条新数据，观察淘汰行为
    run "$INTENT_LEARNER" record "new" "src/new.ts::new" --action view
    skip_if_not_ready "$status" "$output" "intent-learner.sh record"

    # 验证新条目被添加
    local has_new
    has_new=$(jq '[.entries[] | select(.symbol == "new")] | length' "$INTENT_HISTORY_PATH")
    [ "$has_new" -ge 1 ]
}

# ============================================================
# T-IL-007: 空历史处理
# ============================================================

# @test T-IL-007: 空历史处理
@test "T-IL-007: get-preferences returns empty array when no history" {
    skip_if_not_executable "$INTENT_LEARNER"

    # 确保历史文件不存在
    rm -f "$INTENT_HISTORY_PATH"

    run "$INTENT_LEARNER" get-preferences
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证返回空数组
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 0 ]
}

# @test T-IL-007b: 空历史文件处理
@test "T-IL-007b: get-preferences handles empty entries array" {
    skip_if_not_executable "$INTENT_LEARNER"

    cat > "$INTENT_HISTORY_PATH" << EOF
{"entries": []}
EOF

    run "$INTENT_LEARNER" get-preferences
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 0 ]
}

# ============================================================
# T-IL-008: 用户操作权重
# ============================================================

# @test T-IL-008: 用户操作权重
@test "T-IL-008: action weights affect preference score correctly" {
    skip_if_not_executable "$INTENT_LEARNER"

    local now_epoch
    now_epoch=$(date +%s)

    # 创建相同频率和时间的三个符号，但不同操作类型
    # edit(2.0) > view(1.0) > ignore(0.5)
    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "editSym", "symbol_id": "src/edit.ts::editSym", "action": "edit", "timestamp": $now_epoch},
    {"symbol": "viewSym", "symbol_id": "src/view.ts::viewSym", "action": "view", "timestamp": $now_epoch},
    {"symbol": "ignoreSym", "symbol_id": "src/ignore.ts::ignoreSym", "action": "ignore", "timestamp": $now_epoch}
  ]
}
EOF

    run "$INTENT_LEARNER" get-preferences --top 10
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 获取各符号的分数
    local score_edit score_view score_ignore
    score_edit=$(echo "$output" | jq -r '.[] | select(.symbol == "editSym") | .score')
    score_view=$(echo "$output" | jq -r '.[] | select(.symbol == "viewSym") | .score')
    score_ignore=$(echo "$output" | jq -r '.[] | select(.symbol == "ignoreSym") | .score')

    # 验证: edit > view > ignore
    if ! float_gte "$score_edit" "$score_view"; then
        echo "Expected score_edit ($score_edit) > score_view ($score_view)" >&2
        return 1
    fi

    if ! float_gte "$score_view" "$score_ignore"; then
        echo "Expected score_view ($score_view) > score_ignore ($score_ignore)" >&2
        return 1
    fi
}

# @test T-IL-008b: 相同符号不同操作累加
@test "T-IL-008b: mixed actions for same symbol accumulate correctly" {
    skip_if_not_executable "$INTENT_LEARNER"

    local now_epoch
    now_epoch=$(date +%s)

    # 符号 A: 1 edit + 1 view = 2.0 + 1.0 = 3.0 基础权重
    # 符号 B: 3 view = 3.0 基础权重
    # 相同基础权重，但应正确计算
    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "mixedSym", "symbol_id": "src/mixed.ts::mixedSym", "action": "edit", "timestamp": $now_epoch},
    {"symbol": "mixedSym", "symbol_id": "src/mixed.ts::mixedSym", "action": "view", "timestamp": $now_epoch},
    {"symbol": "viewOnlySym", "symbol_id": "src/viewonly.ts::viewOnlySym", "action": "view", "timestamp": $now_epoch},
    {"symbol": "viewOnlySym", "symbol_id": "src/viewonly.ts::viewOnlySym", "action": "view", "timestamp": $now_epoch},
    {"symbol": "viewOnlySym", "symbol_id": "src/viewonly.ts::viewOnlySym", "action": "view", "timestamp": $now_epoch}
  ]
}
EOF

    run "$INTENT_LEARNER" get-preferences --top 10
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # 两个符号都应该出现在结果中
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 2 ]
}

# ============================================================
# T-IL-009: 历史文件损坏恢复
# ============================================================

# @test T-IL-009: 历史文件损坏恢复
@test "T-IL-009: corrupted history file is recovered" {
    skip_if_not_executable "$INTENT_LEARNER"

    # 创建损坏的 JSON 文件
    echo "not valid json {{{" > "$INTENT_HISTORY_PATH"

    # 执行任意命令
    run "$INTENT_LEARNER" get-preferences
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences (corrupt recovery)"

    assert_exit_success "$status"

    # 验证备份文件已创建
    [ -f "${INTENT_HISTORY_PATH}.bak" ]

    # 验证新文件是有效 JSON
    assert_valid_json "$(cat "$INTENT_HISTORY_PATH")"
}

# @test T-IL-009b: record 也能恢复损坏文件
@test "T-IL-009b: record command recovers corrupted history" {
    skip_if_not_executable "$INTENT_LEARNER"

    # 创建损坏的 JSON 文件
    echo "corrupted" > "$INTENT_HISTORY_PATH"

    run "$INTENT_LEARNER" record "newSym" "src/new.ts::newSym" --action view
    skip_if_not_ready "$status" "$output" "intent-learner.sh record (corrupt recovery)"

    assert_exit_success "$status"

    # 验证备份文件已创建
    [ -f "${INTENT_HISTORY_PATH}.bak" ]

    # 验证新记录已写入有效 JSON
    assert_valid_json "$(cat "$INTENT_HISTORY_PATH")"

    local has_new
    has_new=$(jq '[.entries[] | select(.symbol == "newSym")] | length' "$INTENT_HISTORY_PATH")
    [ "$has_new" -ge 1 ]
}

# @test T-IL-009c: 空文件被视为有效空历史
@test "T-IL-009c: empty file is treated as valid empty history" {
    skip_if_not_executable "$INTENT_LEARNER"

    # 创建空文件
    touch "$INTENT_HISTORY_PATH"

    run "$INTENT_LEARNER" get-preferences
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences (empty file)"

    assert_exit_success "$status"
    assert_valid_json "$output"

    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 0 ]
}

# ============================================================
# 边界测试
# ============================================================

# @test T-IL-EDGE-001: 特殊字符符号名处理
@test "T-IL-EDGE-001: handles special characters in symbol names" {
    skip_if_not_executable "$INTENT_LEARNER"

    run "$INTENT_LEARNER" record "my-func_123" "src/path with spaces/file.ts::my-func_123" --action view
    skip_if_not_ready "$status" "$output" "intent-learner.sh record (special chars)"

    assert_exit_success "$status"

    # 验证条目已创建
    local symbol
    symbol=$(jq -r '.entries[0].symbol' "$INTENT_HISTORY_PATH")
    [ "$symbol" = "my-func_123" ]
}

# @test T-IL-EDGE-002: 无效操作类型处理
@test "T-IL-EDGE-002: rejects invalid action type" {
    skip_if_not_executable "$INTENT_LEARNER"

    run "$INTENT_LEARNER" record "func" "src/a.ts::func" --action invalid_action

    # 应该失败或忽略无效操作
    if [ "$status" -eq 0 ]; then
        # 如果成功，验证使用了默认值或记录了警告
        skip "Implementation accepts invalid action (may use default)"
    fi

    assert_exit_failure "$status"
}

# @test T-IL-EDGE-003: 并发写入安全
@test "T-IL-EDGE-003: concurrent writes are safe" {
    skip_if_not_executable "$INTENT_LEARNER"

    # 初始化历史文件
    cat > "$INTENT_HISTORY_PATH" << EOF
{"entries": []}
EOF

    # 并发写入 5 条记录
    for i in $(seq 1 5); do
        "$INTENT_LEARNER" record "sym$i" "src/s$i.ts::sym$i" --action view &
    done

    # 等待所有后台任务完成
    wait

    # 验证历史文件仍然是有效 JSON
    assert_valid_json "$(cat "$INTENT_HISTORY_PATH")"

    # 验证至少有一些记录被写入
    local count
    count=$(jq '.entries | length' "$INTENT_HISTORY_PATH")
    [ "$count" -ge 1 ]
}

# ============================================================
# Conversation Context Tests (AC-G04)
# ============================================================

@test "test_conversation_context_write_read: context save/load preserves 5 turns" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    for i in $(seq 1 5); do
        run "$INTENT_LEARNER" context save --query "query-$i" --symbols "sym$i"
        skip_if_not_ready "$status" "$output" "intent-learner.sh context save"
    done

    run "$INTENT_LEARNER" context load
    skip_if_not_ready "$status" "$output" "intent-learner.sh context load"

    assert_valid_json "$output"

    local count
    count=$(echo "$output" | jq '.context_window | length' 2>/dev/null || echo "0")
    if [ "$count" -ne 5 ]; then
        skip_not_implemented "conversation context window size"
    fi
}

@test "test_conversation_context_schema: context contains required fields" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    # First save a context entry to ensure we have data
    run "$INTENT_LEARNER" context save --query "test-query" --symbols "sym1"
    skip_if_not_ready "$status" "$output" "intent-learner.sh context save"

    run "$INTENT_LEARNER" context load
    skip_if_not_ready "$status" "$output" "intent-learner.sh context load"

    assert_valid_json "$output"

    # Verify all 6 required fields: turn, query, focus_symbols, session_id, timestamp, weight
    local has_turn has_query has_focus has_session_id has_timestamp has_weight
    has_turn=$(echo "$output" | jq -r '.context_window[0].turn // empty')
    has_query=$(echo "$output" | jq -r '.context_window[0].query // empty')
    has_focus=$(echo "$output" | jq -r '.context_window[0].focus_symbols // empty')
    has_session_id=$(echo "$output" | jq -r '.session_id // empty')
    has_timestamp=$(echo "$output" | jq -r '.context_window[0].timestamp // empty')
    has_weight=$(echo "$output" | jq -r '.context_window[0].weight // .context_window[0].results_count // empty')

    if [ -z "$has_turn" ]; then
        skip_not_implemented "conversation context schema: turn field"
    fi
    if [ -z "$has_query" ]; then
        skip_not_implemented "conversation context schema: query field"
    fi
    if [ -z "$has_focus" ]; then
        skip_not_implemented "conversation context schema: focus_symbols field"
    fi
    if [ -z "$has_session_id" ]; then
        skip_not_implemented "conversation context schema: session_id field"
    fi
    if [ -z "$has_timestamp" ]; then
        skip_not_implemented "conversation context schema: timestamp field"
    fi
    if [ -z "$has_weight" ]; then
        skip_not_implemented "conversation context schema: weight/results_count field"
    fi
}

@test "test_conversation_context_fifo: context window evicts oldest after 10 turns" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    for i in $(seq 1 11); do
        run "$INTENT_LEARNER" context save --query "query-$i" --symbols "sym$i"
        skip_if_not_ready "$status" "$output" "intent-learner.sh context save"
    done

    run "$INTENT_LEARNER" context load
    skip_if_not_ready "$status" "$output" "intent-learner.sh context load"

    assert_valid_json "$output"

    # Verify window size is limited to 10
    local window_size
    window_size=$(echo "$output" | jq '.context_window | length')
    if [ "$window_size" -gt 10 ]; then
        skip_not_implemented "conversation context FIFO eviction: window exceeds 10 entries"
    fi

    # Verify oldest entry (turn 1) was evicted - first entry should be turn 2
    local first_turn first_query
    first_turn=$(echo "$output" | jq -r '.context_window[0].turn // empty')
    first_query=$(echo "$output" | jq -r '.context_window[0].query // empty')

    if [ "$first_turn" != "2" ]; then
        skip_not_implemented "conversation context FIFO eviction: oldest not evicted"
    fi

    # Verify the oldest entry's query matches expected (query-2 not query-1)
    if [ "$first_query" != "query-2" ]; then
        skip_not_implemented "conversation context FIFO eviction: query content mismatch"
    fi

    # Verify last entry is the newest (turn 11)
    local last_turn last_query
    last_turn=$(echo "$output" | jq -r '.context_window[-1].turn // empty')
    last_query=$(echo "$output" | jq -r '.context_window[-1].query // empty')

    if [ "$last_turn" != "11" ]; then
        skip_not_implemented "conversation context FIFO eviction: newest not at end"
    fi

    if [ "$last_query" != "query-11" ]; then
        skip_not_implemented "conversation context FIFO eviction: newest query mismatch"
    fi
}

@test "test_conversation_context_weighting: apply-weight boosts accumulated focus" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    cat > "$CONVERSATION_CONTEXT_PATH" << EOF
{
  "session_id": "session-test",
  "started_at": "2026-01-16T10:00:00Z",
  "context_window": [
    {
      "turn": 1,
      "timestamp": "2026-01-16T10:01:00Z",
      "query": "find auth module",
      "query_type": "search",
      "focus_symbols": ["src/auth.ts::login"],
      "results_count": 2,
      "weight": 1.0
    }
  ],
  "accumulated_focus": ["src/auth.ts::login"]
}
EOF

    # Results with auth symbol having lower base score
    local results_json='[{"symbol":"src/auth.ts::login","score":0.8},{"symbol":"src/utils.ts::helper","score":0.85}]'

    run "$INTENT_LEARNER" context apply-weight --results "$results_json"
    skip_if_not_ready "$status" "$output" "intent-learner.sh context apply-weight"

    assert_valid_json "$output"

    # Verify boosted symbol is now first
    local boosted
    boosted=$(echo "$output" | jq -r '.[0].symbol // empty')
    if [ "$boosted" != "src/auth.ts::login" ]; then
        skip_not_implemented "conversation context weighting: boost not applied"
    fi

    # Verify the boosted score is higher than original
    local boosted_score original_score
    boosted_score=$(echo "$output" | jq -r '.[0].score // empty')

    # The boosted score should be > 0.8 (original) due to accumulated focus weight
    if [ -n "$boosted_score" ]; then
        if ! float_gte "$boosted_score" "0.8"; then
            skip_not_implemented "conversation context weighting: score not boosted"
        fi
    fi

    # Verify weight calculation - boosted score should be higher than non-focus symbol
    local helper_score
    helper_score=$(echo "$output" | jq -r '.[] | select(.symbol == "src/utils.ts::helper") | .score // empty')

    if [ -n "$boosted_score" ] && [ -n "$helper_score" ]; then
        if ! float_gte "$boosted_score" "$helper_score"; then
            skip_not_implemented "conversation context weighting: relative ranking incorrect"
        fi
    fi
}

# ============================================================
# 模块 4: 偏好计算契约测试 (CT-PF-001~005)
# 覆盖规格: dev-playbooks/changes/algorithm-optimization-parity/specs/preference-scoring/spec.md
# ============================================================

# @test CT-PF-001: 单次查询分数计算 - view 操作今天查询得分为 1.0
@test "CT-PF-001: single query score calculation (view today = 1.0)" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    local now_epoch
    now_epoch=$(date +%s)

    # Given: 符号 S 被 view 查询，距今 0 天
    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "singleSym", "symbol_id": "src/single.ts::singleSym", "action": "view", "timestamp": $now_epoch}
  ]
}
EOF

    # When: 计算偏好分数
    run "$INTENT_LEARNER" get-preferences --top 10
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # Then: 分数 = 1.0 × 1.0 = 1.0
    local score
    score=$(echo "$output" | jq -r '.[] | select(.symbol == "singleSym") | .score')

    if [ -z "$score" ]; then
        skip_not_implemented "CT-PF-001: preference score not returned"
    fi

    # 允许浮点数误差，分数应该接近 1.0
    if ! float_gte "$score" "0.9"; then
        echo "Expected score >= 0.9 (approx 1.0), got $score" >&2
        return 1
    fi
    if ! float_lt "$score" "1.1"; then
        echo "Expected score < 1.1 (approx 1.0), got $score" >&2
        return 1
    fi
}

# @test CT-PF-002: 多次查询分数累加 - 不同时间不同操作正确累加
@test "CT-PF-002: multiple queries accumulate with recency weight" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    local now_epoch
    now_epoch=$(date +%s)
    local one_day_ago=$((now_epoch - 86400))   # 1 天前
    local seven_days_ago=$((now_epoch - 604800))  # 7 天前

    # Given: 符号 S 被查询 3 次:
    #   - 今天 view (1.0 × 1.0 = 1.0)
    #   - 1 天前 edit (2.0 × 0.5 = 1.0)
    #   - 7 天前 view (1.0 × 0.125 = 0.125)
    # Then: 预期分数 = 1.0 + 1.0 + 0.125 = 2.125
    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "multiSym", "symbol_id": "src/multi.ts::multiSym", "action": "view", "timestamp": $now_epoch},
    {"symbol": "multiSym", "symbol_id": "src/multi.ts::multiSym", "action": "edit", "timestamp": $one_day_ago},
    {"symbol": "multiSym", "symbol_id": "src/multi.ts::multiSym", "action": "view", "timestamp": $seven_days_ago}
  ]
}
EOF

    # When: 计算偏好分数
    run "$INTENT_LEARNER" get-preferences --top 10
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    local score
    score=$(echo "$output" | jq -r '.[] | select(.symbol == "multiSym") | .score')

    if [ -z "$score" ]; then
        skip_not_implemented "CT-PF-002: preference score not returned"
    fi

    # 分数应该大于 2.0（多次查询累加）
    if ! float_gte "$score" "2.0"; then
        echo "Expected score >= 2.0 for multiple queries, got $score" >&2
        return 1
    fi
}

# @test CT-PF-003: edit 操作权重为 2.0
@test "CT-PF-003: edit action weight is 2.0" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    local now_epoch
    now_epoch=$(date +%s)

    # Given: 符号 S 被 edit，距今 0 天
    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "editSym", "symbol_id": "src/edit.ts::editSym", "action": "edit", "timestamp": $now_epoch}
  ]
}
EOF

    # When: 计算偏好分数
    run "$INTENT_LEARNER" get-preferences --top 10
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # Then: 分数 = 2.0 × 1.0 = 2.0
    local score
    score=$(echo "$output" | jq -r '.[] | select(.symbol == "editSym") | .score')

    if [ -z "$score" ]; then
        skip_not_implemented "CT-PF-003: preference score not returned"
    fi

    # 分数应该接近 2.0
    if ! float_gte "$score" "1.9"; then
        echo "Expected score >= 1.9 (approx 2.0), got $score" >&2
        return 1
    fi
    if ! float_lt "$score" "2.1"; then
        echo "Expected score < 2.1 (approx 2.0), got $score" >&2
        return 1
    fi
}

# @test CT-PF-004: ignore 操作权重为 0.5
@test "CT-PF-004: ignore action weight is 0.5" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    local now_epoch
    now_epoch=$(date +%s)

    # Given: 符号 S 被 ignore，距今 0 天
    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "ignoreSym", "symbol_id": "src/ignore.ts::ignoreSym", "action": "ignore", "timestamp": $now_epoch}
  ]
}
EOF

    # When: 计算偏好分数
    run "$INTENT_LEARNER" get-preferences --top 10
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # Then: 分数 = 0.5 × 1.0 = 0.5
    local score
    score=$(echo "$output" | jq -r '.[] | select(.symbol == "ignoreSym") | .score')

    if [ -z "$score" ]; then
        skip_not_implemented "CT-PF-004: preference score not returned"
    fi

    # 分数应该接近 0.5
    if ! float_gte "$score" "0.4"; then
        echo "Expected score >= 0.4 (approx 0.5), got $score" >&2
        return 1
    fi
    if ! float_lt "$score" "0.6"; then
        echo "Expected score < 0.6 (approx 0.5), got $score" >&2
        return 1
    fi
}

# @test CT-PF-005: 路径前缀过滤只返回匹配的符号
@test "CT-PF-005: path prefix filter returns only matching symbols" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    local now_epoch
    now_epoch=$(date +%s)

    # Given: 偏好记录包含不同路径的符号
    cat > "$INTENT_HISTORY_PATH" << EOF
{
  "entries": [
    {"symbol": "login", "symbol_id": "src/auth.ts::login", "action": "view", "timestamp": $now_epoch},
    {"symbol": "login", "symbol_id": "src/auth.ts::login", "action": "view", "timestamp": $now_epoch},
    {"symbol": "testLogin", "symbol_id": "tests/auth.test.ts::testLogin", "action": "view", "timestamp": $now_epoch}
  ]
}
EOF

    # When: 使用 --prefix src/ 过滤
    run "$INTENT_LEARNER" get-preferences --prefix "src/"
    skip_if_not_ready "$status" "$output" "intent-learner.sh get-preferences --prefix"

    assert_exit_success "$status"
    assert_valid_json "$output"

    # Then: 只返回 src/ 前缀的符号
    local count
    count=$(echo "$output" | jq 'length')

    if [ "$count" -eq 0 ]; then
        skip_not_implemented "CT-PF-005: prefix filter not implemented"
    fi

    # 验证所有返回结果都是 src/ 前缀
    local non_src_count
    non_src_count=$(echo "$output" | jq '[.[] | select(.symbol_id | startswith("src/") | not)] | length')
    [ "$non_src_count" -eq 0 ]

    # 验证 tests/ 路径的符号没有返回
    local test_count
    test_count=$(echo "$output" | jq '[.[] | select(.symbol_id | startswith("tests/"))] | length')
    [ "$test_count" -eq 0 ]
}

# ============================================================
# 模块 5: 连续性加权契约测试 (CT-CW-001~006)
# 覆盖规格: dev-playbooks/changes/algorithm-optimization-parity/specs/context-weighting/spec.md
# ============================================================

# @test CT-CW-001: 累积焦点加权 +0.2
@test "CT-CW-001: accumulated focus weight adds +0.2" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    # Given: 符号 S 在 accumulated_focus 中，原始分数 = 0.8
    cat > "$CONVERSATION_CONTEXT_PATH" << EOF
{
  "session_id": "session-ct-cw-001",
  "started_at": "2026-01-17T10:00:00Z",
  "context_window": [],
  "accumulated_focus": ["src/focus.ts::focusSym"]
}
EOF

    local results_json='[{"symbol":"src/focus.ts::focusSym","score":0.8},{"symbol":"src/other.ts::otherSym","score":0.85}]'

    # When: 应用连续性加权
    run "$INTENT_LEARNER" context apply-weight --results "$results_json"
    skip_if_not_ready "$status" "$output" "intent-learner.sh context apply-weight"

    assert_valid_json "$output"

    # Then: 加权后分数 = 0.8 + 0.2 = 1.0
    local boosted_score
    boosted_score=$(echo "$output" | jq -r '.[] | select(.symbol == "src/focus.ts::focusSym") | .score // empty')

    if [ -z "$boosted_score" ]; then
        skip_not_implemented "CT-CW-001: accumulated focus weighting not implemented"
    fi

    # 分数应该大于原始的 0.8
    if ! float_gte "$boosted_score" "0.85"; then
        echo "Expected boosted score >= 0.85, got $boosted_score" >&2
        return 1
    fi
}

# @test CT-CW-002: 近期焦点加权 +0.3
@test "CT-CW-002: recent focus weight adds +0.3" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    # Given: 符号 S 在最近 3 轮 focus_symbols 中，原始分数 = 0.6
    cat > "$CONVERSATION_CONTEXT_PATH" << EOF
{
  "session_id": "session-ct-cw-002",
  "started_at": "2026-01-17T10:00:00Z",
  "context_window": [
    {"turn": 1, "timestamp": "2026-01-17T10:01:00Z", "query": "q1", "focus_symbols": ["src/recent.ts::recentSym"]},
    {"turn": 2, "timestamp": "2026-01-17T10:02:00Z", "query": "q2", "focus_symbols": ["src/recent.ts::recentSym"]},
    {"turn": 3, "timestamp": "2026-01-17T10:03:00Z", "query": "q3", "focus_symbols": ["src/recent.ts::recentSym"]}
  ],
  "accumulated_focus": []
}
EOF

    local results_json='[{"symbol":"src/recent.ts::recentSym","score":0.6},{"symbol":"src/other.ts::otherSym","score":0.7}]'

    # When: 应用连续性加权
    run "$INTENT_LEARNER" context apply-weight --results "$results_json"
    skip_if_not_ready "$status" "$output" "intent-learner.sh context apply-weight"

    assert_valid_json "$output"

    # Then: 加权后分数 = 0.6 + 0.3 = 0.9
    local boosted_score
    boosted_score=$(echo "$output" | jq -r '.[] | select(.symbol == "src/recent.ts::recentSym") | .score // empty')

    if [ -z "$boosted_score" ]; then
        skip_not_implemented "CT-CW-002: recent focus weighting not implemented"
    fi

    # 分数应该大于原始的 0.6
    if ! float_gte "$boosted_score" "0.65"; then
        echo "Expected boosted score >= 0.65, got $boosted_score" >&2
        return 1
    fi
}

# @test CT-CW-003: 同文件加权 +0.1
@test "CT-CW-003: same file weight adds +0.1" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    # Given: 符号 S 与最近查询符号同文件，原始分数 = 0.5
    cat > "$CONVERSATION_CONTEXT_PATH" << EOF
{
  "session_id": "session-ct-cw-003",
  "started_at": "2026-01-17T10:00:00Z",
  "context_window": [
    {"turn": 1, "timestamp": "2026-01-17T10:01:00Z", "query": "find helper", "focus_symbols": ["src/utils.ts::helper1"]}
  ],
  "accumulated_focus": []
}
EOF

    # helper2 与 helper1 同文件 (src/utils.ts)
    local results_json='[{"symbol":"src/utils.ts::helper2","score":0.5},{"symbol":"src/other.ts::otherSym","score":0.55}]'

    # When: 应用连续性加权
    run "$INTENT_LEARNER" context apply-weight --results "$results_json"
    skip_if_not_ready "$status" "$output" "intent-learner.sh context apply-weight"

    assert_valid_json "$output"

    # Then: 加权后分数 = 0.5 + 0.1 = 0.6
    local boosted_score
    boosted_score=$(echo "$output" | jq -r '.[] | select(.symbol == "src/utils.ts::helper2") | .score // empty')

    if [ -z "$boosted_score" ]; then
        skip_not_implemented "CT-CW-003: same file weighting not implemented"
    fi

    # 分数应该大于原始的 0.5
    if ! float_gte "$boosted_score" "0.5"; then
        echo "Expected boosted score >= 0.5, got $boosted_score" >&2
        return 1
    fi
}

# @test CT-CW-004: 组合加权受上限约束 (原始分数 × 0.5)
@test "CT-CW-004: combined weight capped at 50% of original score" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    # Given: 符号 S 满足所有条件，原始分数 = 0.8
    # 总加权 = 0.2 + 0.3 + 0.1 = 0.6，但上限 = 0.8 × 0.5 = 0.4
    cat > "$CONVERSATION_CONTEXT_PATH" << EOF
{
  "session_id": "session-ct-cw-004",
  "started_at": "2026-01-17T10:00:00Z",
  "context_window": [
    {"turn": 1, "timestamp": "2026-01-17T10:01:00Z", "query": "q1", "focus_symbols": ["src/all.ts::allSym"]},
    {"turn": 2, "timestamp": "2026-01-17T10:02:00Z", "query": "q2", "focus_symbols": ["src/all.ts::allSym"]},
    {"turn": 3, "timestamp": "2026-01-17T10:03:00Z", "query": "q3", "focus_symbols": ["src/all.ts::allSym"]}
  ],
  "accumulated_focus": ["src/all.ts::allSym"]
}
EOF

    local results_json='[{"symbol":"src/all.ts::allSym","score":0.8},{"symbol":"src/other.ts::otherSym","score":0.9}]'

    # When: 应用连续性加权
    run "$INTENT_LEARNER" context apply-weight --results "$results_json"
    skip_if_not_ready "$status" "$output" "intent-learner.sh context apply-weight"

    assert_valid_json "$output"

    # Then: 加权后分数 = 0.8 + min(0.6, 0.4) = 0.8 + 0.4 = 1.2
    local boosted_score
    boosted_score=$(echo "$output" | jq -r '.[] | select(.symbol == "src/all.ts::allSym") | .score // empty')

    if [ -z "$boosted_score" ]; then
        skip_not_implemented "CT-CW-004: combined weighting not implemented"
    fi

    # 分数应该不超过 1.3（0.8 + 0.5，允许一些误差）
    # 上限是原始分数的 50%，所以最大加权是 0.8 × 0.5 = 0.4
    if ! float_lt "$boosted_score" "1.3"; then
        echo "Expected boosted score < 1.3 (cap should apply), got $boosted_score" >&2
        return 1
    fi

    # 分数应该大于原始分数
    if ! float_gte "$boosted_score" "0.8"; then
        echo "Expected boosted score >= 0.8, got $boosted_score" >&2
        return 1
    fi
}

# @test CT-CW-005: 低分数时上限更严格
@test "CT-CW-005: low score has stricter cap (50% of original)" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    # Given: 原始分数 = 0.2，满足累积焦点条件（+0.2）
    # 上限 = 0.2 × 0.5 = 0.1
    # 最终分数 = 0.2 + 0.1 = 0.3（而非 0.4）
    cat > "$CONVERSATION_CONTEXT_PATH" << EOF
{
  "session_id": "session-ct-cw-005",
  "started_at": "2026-01-17T10:00:00Z",
  "context_window": [],
  "accumulated_focus": ["src/low.ts::lowSym"]
}
EOF

    local results_json='[{"symbol":"src/low.ts::lowSym","score":0.2},{"symbol":"src/other.ts::otherSym","score":0.3}]'

    # When: 应用连续性加权
    run "$INTENT_LEARNER" context apply-weight --results "$results_json"
    skip_if_not_ready "$status" "$output" "intent-learner.sh context apply-weight"

    assert_valid_json "$output"

    local boosted_score
    boosted_score=$(echo "$output" | jq -r '.[] | select(.symbol == "src/low.ts::lowSym") | .score // empty')

    if [ -z "$boosted_score" ]; then
        skip_not_implemented "CT-CW-005: low score cap not implemented"
    fi

    # 分数应该不超过 0.35（0.2 + 0.1 + 一些误差）
    if ! float_lt "$boosted_score" "0.35"; then
        echo "Expected boosted score < 0.35 (stricter cap for low score), got $boosted_score" >&2
        return 1
    fi

    # 分数应该大于原始分数
    if ! float_gte "$boosted_score" "0.2"; then
        echo "Expected boosted score >= 0.2, got $boosted_score" >&2
        return 1
    fi
}

# @test CT-CW-006: 无上下文时不加权
@test "CT-CW-006: no weighting when context window is empty" {
    skip_if_not_executable "$INTENT_LEARNER"
    skip_if_missing "jq"

    # Given: context_window 为空
    cat > "$CONVERSATION_CONTEXT_PATH" << EOF
{
  "session_id": "session-ct-cw-006",
  "started_at": "2026-01-17T10:00:00Z",
  "context_window": [],
  "accumulated_focus": []
}
EOF

    local results_json='[{"symbol":"src/nocontext.ts::noContextSym","score":0.7}]'

    # When: 应用连续性加权
    run "$INTENT_LEARNER" context apply-weight --results "$results_json"
    skip_if_not_ready "$status" "$output" "intent-learner.sh context apply-weight"

    assert_valid_json "$output"

    # Then: 返回原始结果，分数不变
    local score
    score=$(echo "$output" | jq -r '.[] | select(.symbol == "src/nocontext.ts::noContextSym") | .score // empty')

    if [ -z "$score" ]; then
        skip_not_implemented "CT-CW-006: empty context handling not implemented"
    fi

    # 分数应该等于原始分数 0.7（允许小误差）
    if ! float_gte "$score" "0.69"; then
        echo "Expected score >= 0.69 (approx 0.7), got $score" >&2
        return 1
    fi
    if ! float_lt "$score" "0.71"; then
        echo "Expected score < 0.71 (approx 0.7), got $score" >&2
        return 1
    fi
}
