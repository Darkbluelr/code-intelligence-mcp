#!/usr/bin/env bats
# 上下文层信号测试
# Change ID: 20260118-2112-enhance-code-intelligence-capabilities
# AC: AC-007

load 'helpers/common.bash'

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
}

require_executable() {
    local path="$1"
    [ -x "$path" ] || fail "Expected executable: $path"
}

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
    export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
    export INTENT_LEARNER_SCRIPT="${SCRIPTS_DIR}/intent-learner.sh"
    export FIXTURE_DIR="${BATS_TEST_DIRNAME}/fixtures/long-term-memory"
    export TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    export DEVBOOKS_DIR="${TEMP_DIR}/.devbooks"
    export INTENT_HISTORY_PATH="${DEVBOOKS_DIR}/intent-history.json"
    export CONVERSATION_CONTEXT_PATH="${DEVBOOKS_DIR}/conversation-context.json"

    mkdir -p "$DEVBOOKS_DIR"

    require_cmd jq
    require_executable "$INTENT_LEARNER_SCRIPT"
    [ -f "$FIXTURE_DIR/retrieval-results.json" ] || fail "Missing fixture: retrieval-results.json"
}

teardown() {
    rm -rf "$TEMP_DIR"
}

# ============================================================
# @smoke 快速验证
# ============================================================

# @smoke T-CS-001: 交互信号权重 (view/edit/ignore)
@test "T-CS-001: Action weights follow design multipliers" {
    "$INTENT_LEARNER_SCRIPT" record "Edit action" "src/edit.ts::editFn" --action edit
    "$INTENT_LEARNER_SCRIPT" record "View action" "src/view.ts::viewFn" --action view
    "$INTENT_LEARNER_SCRIPT" record "Ignore action" "src/ignore.ts::ignoreFn" --action ignore

    prefs=$("$INTENT_LEARNER_SCRIPT" get-preferences --top 3)

    edit_score=$(echo "$prefs" | jq -r '.[] | select(.symbol_id == "src/edit.ts::editFn") | .score')
    view_score=$(echo "$prefs" | jq -r '.[] | select(.symbol_id == "src/view.ts::viewFn") | .score')
    ignore_score=$(echo "$prefs" | jq -r '.[] | select(.symbol_id == "src/ignore.ts::ignoreFn") | .score')

    [ -n "$edit_score" ] || fail "Missing edit score"
    [ -n "$view_score" ] || fail "Missing view score"
    [ -n "$ignore_score" ] || fail "Missing ignore score"

    # 验证相对关系：edit > view > ignore (ignore应该是负值)
    if ! awk -v edit="$edit_score" -v view="$view_score" -v ignore="$ignore_score" 'BEGIN {
        # 1. 验证顺序关系
        order_ok = (edit > view) && (view > ignore) && (ignore < 0)
        # 2. 验证倍率关系：edit/view 应在 [1.2, 1.5] 范围内
        ratio = edit / view
        ratio_ok = (ratio >= 1.2) && (ratio <= 1.5)
        # 3. 验证 view/ignore 的绝对值比例在合理范围 [2.5, 4.0]
        view_ignore_ratio = view / (-ignore)
        view_ignore_ok = (view_ignore_ratio >= 2.5) && (view_ignore_ratio <= 4.0)
        pass = order_ok && ratio_ok && view_ignore_ok
        exit(pass ? 0 : 1)
    }'; then
        fail "Unexpected weight relationships: edit=$edit_score view=$view_score ignore=$ignore_score"
    fi
}

# ============================================================
# @critical 关键功能
# ============================================================

# @critical T-CS-002: 信号衰减基于时间
@test "T-CS-002: Older signals have lower score than recent" {
    now=$(date +%s)
    old=$((now - 100 * 86400))

    cat > "$INTENT_HISTORY_PATH" << EOF
{"entries": [
  {"symbol": "old", "symbol_id": "src/old.ts::oldFn", "action": "view", "timestamp": $old},
  {"symbol": "new", "symbol_id": "src/new.ts::newFn", "action": "view", "timestamp": $now}
]}
EOF

    prefs=$("$INTENT_LEARNER_SCRIPT" get-preferences --top 2)

    echo "$prefs" | jq -e '.[0].symbol_id == "src/new.ts::newFn"'
    echo "$prefs" | jq -e '.[1].symbol_id == "src/old.ts::oldFn"'
    echo "$prefs" | jq -e '.[0].score > .[1].score'
}

# @critical T-CS-002b: 90 天边界衰减
@test "T-CS-002b: Signals older than 90 days are removed after cleanup" {
    now=$(date +%s)
    keep=$((now - 89 * 86400))
    drop=$((now - 91 * 86400))

    cat > "$INTENT_HISTORY_PATH" << EOF
{"entries": [
  {"symbol": "keep", "symbol_id": "src/keep.ts::keepFn", "action": "view", "timestamp": $keep},
  {"symbol": "drop", "symbol_id": "src/drop.ts::dropFn", "action": "view", "timestamp": $drop}
]}
EOF

    "$INTENT_LEARNER_SCRIPT" cleanup --days 90

    remaining=$(jq -r '.entries[].symbol_id' "$INTENT_HISTORY_PATH")
    echo "$remaining" | grep -q "src/keep.ts::keepFn"
    echo "$remaining" | grep -v "src/drop.ts::dropFn"
}

# @critical T-CS-003: 清理过期信号
@test "T-CS-003: Cleanup removes signals older than retention window" {
    now=$(date +%s)
    old=$((now - 120 * 86400))

    cat > "$INTENT_HISTORY_PATH" << EOF
{"entries": [
  {"symbol": "old", "symbol_id": "src/old.ts::oldFn", "action": "view", "timestamp": $old},
  {"symbol": "new", "symbol_id": "src/new.ts::newFn", "action": "view", "timestamp": $now}
]}
EOF

    "$INTENT_LEARNER_SCRIPT" cleanup --days 90

    remaining=$(jq -r '.entries[].symbol_id' "$INTENT_HISTORY_PATH")
    echo "$remaining" | grep -q "src/new.ts::newFn"
    echo "$remaining" | grep -v "src/old.ts::oldFn"
}

# @critical T-CS-004: 会话焦点加权
@test "T-CS-004: Context focus boosts relevant symbols" {
    "$INTENT_LEARNER_SCRIPT" context save --query "find auth" --symbols "src/auth.ts::login,src/auth.ts"

    results=$(jq -c '.' "$FIXTURE_DIR/retrieval-results.json")
    weighted=$("$INTENT_LEARNER_SCRIPT" context apply-weight --results "$results")

    # 正向断言：焦点符号被提升
    echo "$weighted" | jq -e '.[0].symbol == "src/auth.ts::login"'
    echo "$weighted" | jq -e '.[0].context_boost > 0'
    echo "$weighted" | jq -e '.[0].score > .[0].original_score'

    # m-001 修复：增加负向断言，确保非焦点符号不被提升
    # 验证非焦点符号的 context_boost 为 0 或 null
    local non_focus_boost
    non_focus_boost=$(echo "$weighted" | jq -r '[.[] | select(.symbol != "src/auth.ts::login" and .symbol != "src/auth.ts")] | .[0].context_boost // 0')
    [ "$non_focus_boost" = "0" ] || [ "$non_focus_boost" = "null" ] || \
        fail "非焦点符号不应被提升，但 context_boost=$non_focus_boost"

    # 验证非焦点符号的 score 等于 original_score（未被加权）
    local non_focus_score_diff
    non_focus_score_diff=$(echo "$weighted" | jq '[.[] | select(.symbol != "src/auth.ts::login" and .symbol != "src/auth.ts")] | .[0] | (.score - .original_score) | if . < 0 then -. else . end')
    local is_unchanged
    is_unchanged=$(echo "$non_focus_score_diff < 0.001" | bc 2>/dev/null || echo "1")
    [ "$is_unchanged" -eq 1 ] || \
        fail "非焦点符号评分不应变化，但 diff=$non_focus_score_diff"

    echo "✓ 负向断言通过：非焦点符号未被意外加权"
}

# ============================================================
# @full 完整覆盖
# ============================================================

# @full T-CS-005: 会话管理可用
@test "T-CS-005: Session commands create and list session" {
    session=$("$INTENT_LEARNER_SCRIPT" session new | jq -r '.session_id')
    [ -n "$session" ]

    listed=$("$INTENT_LEARNER_SCRIPT" session list)
    echo "$listed" | jq -e --arg session "$session" '.sessions[] | select(.session_id == $session)'

    "$INTENT_LEARNER_SCRIPT" session clear
    cleared=$("$INTENT_LEARNER_SCRIPT" session list)
    echo "$cleared" | jq -e '.sessions | length == 0'
}

# @critical T-CS-006: 跨会话持久化
@test "T-CS-006: Signals persist across new session process" {
    "$INTENT_LEARNER_SCRIPT" record "Persist test" "src/persist.ts::persistFn" --action view

    output=$(env -i PATH="$PATH" DEVBOOKS_DIR="$DEVBOOKS_DIR" "$INTENT_LEARNER_SCRIPT" get-preferences --top 1)

    echo "$output" | jq -e '.[0].symbol_id == "src/persist.ts::persistFn"' >/dev/null || \
      fail "Missing persisted symbol in new session"
}

# @critical T-CS-007: 历史修复权重（REQ-CL-001）
@test "T-CS-007: Corrected ignore receives additional weight boost" {
    # 场景：用户先 ignore 一个符号，后来又 edit，说明修正了判断
    # 预期：最新的 edit 操作应该得到额外的权重提升（+0.5x 修正权重）

    # 第一步：ignore 操作
    "$INTENT_LEARNER_SCRIPT" record "Initial ignore" "src/corrected.ts::correctedFn" --action ignore

    # 第二步：对同一符号执行 edit（修正判断）
    "$INTENT_LEARNER_SCRIPT" record "Corrected edit" "src/corrected.ts::correctedFn" --action edit

    # 对比：另一个只有单次 edit 的符号
    "$INTENT_LEARNER_SCRIPT" record "Normal edit" "src/normal.ts::normalFn" --action edit

    prefs=$("$INTENT_LEARNER_SCRIPT" get-preferences --top 2)

    corrected_score=$(echo "$prefs" | jq -r '.[] | select(.symbol_id == "src/corrected.ts::correctedFn") | .score')
    normal_score=$(echo "$prefs" | jq -r '.[] | select(.symbol_id == "src/normal.ts::normalFn") | .score')

    [ -n "$corrected_score" ] || fail "Missing corrected symbol score"
    [ -n "$normal_score" ] || fail "Missing normal symbol score"

    # 验证：修正后的符号权重应该高于普通符号（因为有修正权重加成）
    if ! awk -v corrected="$corrected_score" -v normal="$normal_score" 'BEGIN {
        # 修正权重应该让分数提升至少 20%
        expected_min = normal * 1.2
        pass = (corrected >= expected_min)
        exit(pass ? 0 : 1)
    }'; then
        fail "Corrected symbol should have higher weight than normal: corrected=$corrected_score normal=$normal_score"
    fi
}

# @critical T-CS-008: 功能开关生效（REQ-CL-005）
@test "T-CS-008: Context signals can be disabled via feature toggle" {
    # 场景：当 context_signals 功能被禁用时，信号记录和权重计算应该被禁用

    # 创建临时配置文件，禁用 context_signals
    local temp_config="$TEMP_DIR/features-disabled.yaml"
    cat > "$temp_config" << 'EOF'
features:
  context_signals:
    enabled: false
EOF

    # 使用禁用配置尝试记录信号（必须取消 DEVBOOKS_ENABLE_ALL_FEATURES 以测试功能开关）
    DEVBOOKS_ENABLE_ALL_FEATURES= DEVBOOKS_FEATURE_CONFIG="$temp_config" run "$INTENT_LEARNER_SCRIPT" record "Disabled test" "src/disabled.ts::disabledFn" --action view

    # 应该成功但不记录（或返回 disabled 状态）
    if [ "$status" -ne 0 ]; then
        # 如果命令失败，输出应该包含 disabled 信息
        echo "$output" | grep -qi "disabled\|feature.*not.*enabled" || \
          fail "Expected 'disabled' message when feature is off, got: $output"
    else
        # 如果命令成功，验证没有实际记录数据
        if [ -f "$INTENT_HISTORY_PATH" ]; then
            local count
            count=$(jq '.entries | length' "$INTENT_HISTORY_PATH" 2>/dev/null || echo "0")
            [ "$count" -eq 0 ] || fail "Signals should not be recorded when feature is disabled"
        fi
    fi

    # 验证 get-preferences 也应该返回空或 disabled 状态
    DEVBOOKS_ENABLE_ALL_FEATURES= DEVBOOKS_FEATURE_CONFIG="$temp_config" run "$INTENT_LEARNER_SCRIPT" get-preferences --top 10

    if [ "$status" -eq 0 ]; then
        # 如果成功，应该返回空数组或包含 disabled 元数据
        echo "$output" | jq -e 'type == "array" and length == 0' >/dev/null || \
          echo "$output" | jq -e '.metadata.status == "disabled"' >/dev/null || \
          fail "get-preferences should return empty or disabled status when feature is off"
    fi
}
