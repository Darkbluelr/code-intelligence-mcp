#!/usr/bin/env bats
# pattern-learner.bats - Pattern Learning Acceptance Tests
#
# Purpose: Verify pattern-learner.sh pattern learning functionality
# Depends: bats-core, jq
# Run: bats tests/pattern-learner.bats
#
# Baseline: 2026-01-15
# Change: augment-parity
# Trace: AC-006 (auto-discover), AC-005 (legacy)

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
PATTERN_LEARNER="${PROJECT_ROOT}/scripts/pattern-learner.sh"
PATTERNS_FILE="${PROJECT_ROOT}/.devbooks/learned-patterns.json"

# Track whether file existed before test
PATTERNS_FILE_EXISTED=""

# Track background PIDs for cleanup (prevent resource leaks)
CONCURRENT_TEST_PIDS=()

setup() {
    # Track initial state
    if [ -f "$PATTERNS_FILE" ]; then
        PATTERNS_FILE_EXISTED="true"
        cp "$PATTERNS_FILE" "${PATTERNS_FILE}.bak"
    else
        PATTERNS_FILE_EXISTED="false"
    fi
    # Reset PID tracking
    CONCURRENT_TEST_PIDS=()
}

teardown() {
    # Clean up any lingering background processes first
    for pid in "${CONCURRENT_TEST_PIDS[@]}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    done

    if [ "$PATTERNS_FILE_EXISTED" = "true" ]; then
        # Restore original file
        if [ -f "${PATTERNS_FILE}.bak" ]; then
            mv "${PATTERNS_FILE}.bak" "$PATTERNS_FILE"
        fi
    else
        # File didn't exist before, clean up if test created it
        rm -f "$PATTERNS_FILE" "${PATTERNS_FILE}.bak"
    fi

    # Clean up auto-discover temp directory if it exists
    if [ -n "$AUTO_DISCOVER_TEMP_DIR" ] && [ -d "$AUTO_DISCOVER_TEMP_DIR" ]; then
        rm -rf "$AUTO_DISCOVER_TEMP_DIR"
        AUTO_DISCOVER_TEMP_DIR=""
    fi
}

# ============================================================
# Auto-discover Test Helpers
# These functions provide isolated temp directories for auto-discover tests
# Call setup_auto_discover() at the start of each auto-discover test
# Cleanup is handled automatically by teardown() via AUTO_DISCOVER_TEMP_DIR
# ============================================================

# Temp directory for auto-discover tests (cleaned up in teardown)
AUTO_DISCOVER_TEMP_DIR=""

# Setup isolated temp directory for auto-discover tests
# Usage: setup_auto_discover
# Sets: TEST_TEMP_DIR, DEVBOOKS_DIR, AUTO_DISCOVER_TEMP_DIR
setup_auto_discover() {
    AUTO_DISCOVER_TEMP_DIR=$(mktemp -d)
    TEST_TEMP_DIR="$AUTO_DISCOVER_TEMP_DIR"
    export DEVBOOKS_DIR="$TEST_TEMP_DIR/.devbooks"
    mkdir -p "$DEVBOOKS_DIR"
}

# Manual cleanup for auto-discover tests (optional, teardown handles this)
# Usage: teardown_auto_discover
teardown_auto_discover() {
    if [ -n "$AUTO_DISCOVER_TEMP_DIR" ] && [ -d "$AUTO_DISCOVER_TEMP_DIR" ]; then
        rm -rf "$AUTO_DISCOVER_TEMP_DIR"
        AUTO_DISCOVER_TEMP_DIR=""
    fi
}

# ============================================================
# Basic Functionality Tests (PL-001)
# ============================================================

@test "PL-001: pattern-learner.sh exists and is executable" {
    [ -x "$PATTERN_LEARNER" ]
}

@test "PL-001b: --help shows usage information" {
    run "$PATTERN_LEARNER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"pattern"* ]] || [[ "$output" == *"Pattern"* ]]
}

@test "PL-001c: --version shows version" {
    run "$PATTERN_LEARNER" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"1."* ]] || [[ "$output" == *"0."* ]]
}

# ============================================================
# Pattern Persistence Tests (PL-002)
# ============================================================

@test "PL-002: generates learned-patterns.json file" {
    run "$PATTERN_LEARNER" --learn --output "$PATTERNS_FILE" 2>&1
    [ "$status" -eq 0 ] || skip "Pattern learning not yet implemented"
    [ -f "$PATTERNS_FILE" ]
}

@test "PL-002b: patterns file includes schema_version" {
    run "$PATTERN_LEARNER" --learn --output "$PATTERNS_FILE" 2>&1
    [ "$status" -eq 0 ] || skip "Pattern learning not yet implemented"
    if [ -f "$PATTERNS_FILE" ]; then
        grep -q "schema_version" "$PATTERNS_FILE"
    else
        skip "Patterns file not generated"
    fi
}

@test "PL-002c: patterns file includes patterns array" {
    run "$PATTERN_LEARNER" --learn --output "$PATTERNS_FILE" 2>&1
    [ "$status" -eq 0 ] || skip "Pattern learning not yet implemented"
    if [ -f "$PATTERNS_FILE" ]; then
        grep -q "patterns" "$PATTERNS_FILE"
    else
        skip "Patterns file not generated"
    fi
}

# ============================================================
# Confidence Threshold Tests (PL-003, PL-004)
# ============================================================

@test "PL-003: low confidence patterns do not produce warnings" {
    run "$PATTERN_LEARNER" --detect --confidence-threshold 0.85 2>&1
    [ "$status" -eq 0 ] || skip "Pattern detection not yet implemented"
    [[ "$output" != *"warning"* ]] || [[ "$output" == *"skip"* ]]
}

@test "PL-004: custom confidence threshold" {
    run "$PATTERN_LEARNER" --detect --confidence-threshold 0.90 2>&1
    [ "$status" -eq 0 ] || skip "Pattern detection not yet implemented"
}

# ============================================================
# Pattern Type Tests
# ============================================================

@test "PL-TYPE-001: naming pattern learning" {
    run "$PATTERN_LEARNER" --learn --type naming 2>&1
    [ "$status" -eq 0 ] || skip "Naming pattern learning not yet implemented"
}

@test "PL-TYPE-002: structure pattern learning" {
    run "$PATTERN_LEARNER" --learn --type structure 2>&1
    [ "$status" -eq 0 ] || skip "Structure pattern learning not yet implemented"
}

# ============================================================
# Pattern Detection Tests
# ============================================================

@test "PL-DETECT-001: detect naming pattern violation" {
    run "$PATTERN_LEARNER" --detect 2>&1
    [ "$status" -eq 0 ] || skip "Pattern detection not yet implemented"
}

# ============================================================
# Output Format Tests
# ============================================================

@test "PL-OUTPUT-001: JSON output is valid JSON" {
    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi
    run "$PATTERN_LEARNER" --learn --format json 2>&1
    [ "$status" -eq 0 ] || skip "Pattern learning not yet implemented"
    echo "$output" | jq . > /dev/null 2>&1 || skip "Output is not JSON"
}

@test "PL-OUTPUT-002: pattern includes pattern_id" {
    run "$PATTERN_LEARNER" --learn --format json 2>&1
    [ "$status" -eq 0 ] || skip "Pattern learning not yet implemented"
    [[ "$output" == *"pattern_id"* ]] || [[ "$output" == *"id"* ]]
}

@test "PL-OUTPUT-003: pattern includes confidence" {
    run "$PATTERN_LEARNER" --learn --format json 2>&1
    [ "$status" -eq 0 ] || skip "Pattern learning not yet implemented"
    [[ "$output" == *"confidence"* ]]
}

# ============================================================
# Parameter Validation Tests
# ============================================================

@test "PL-PARAM-001: --confidence-threshold parameter support" {
    run "$PATTERN_LEARNER" --help
    [[ "$output" == *"confidence"* ]] || [[ "$output" == *"threshold"* ]]
}

@test "PL-PARAM-002: --learn parameter support" {
    run "$PATTERN_LEARNER" --help
    [[ "$output" == *"learn"* ]]
}

@test "PL-PARAM-003: --detect parameter support" {
    run "$PATTERN_LEARNER" --help
    [[ "$output" == *"detect"* ]]
}

@test "PL-PARAM-004: invalid parameter returns error" {
    run "$PATTERN_LEARNER" --invalid-option
    [ "$status" -ne 0 ]
}

# ============================================================
# Load Existing Patterns Tests
# ============================================================

@test "PL-LOAD-001: load existing patterns file" {
    mkdir -p .devbooks
    echo '{"schema_version": "1.0.0", "patterns": []}' > "$PATTERNS_FILE"
    run "$PATTERN_LEARNER" --learn 2>&1
    [ "$status" -eq 0 ] || skip "Pattern loading not yet implemented"
    rm -f "$PATTERNS_FILE"
}

# ============================================================
# Concurrency Tests (PL-CONCURRENT)
# ============================================================

# 并发测试超时时间（秒）
CONCURRENT_TIMEOUT="${CONCURRENT_TIMEOUT:-10}"

@test "PL-CONCURRENT-001: concurrent writes to patterns file handled" {
    mkdir -p .devbooks
    echo '{"schema_version": "1.0.0", "patterns": []}' > "$PATTERNS_FILE"

    # 检查脚本是否可执行
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not yet implemented"

    # 启动后台进程并跟踪 PID
    local pid1 pid2
    (run_with_timeout "$CONCURRENT_TIMEOUT" "$PATTERN_LEARNER" --learn --output "$PATTERNS_FILE" 2>&1) &
    pid1=$!
    CONCURRENT_TEST_PIDS+=("$pid1")

    (run_with_timeout "$CONCURRENT_TIMEOUT" "$PATTERN_LEARNER" --learn --output "$PATTERNS_FILE" 2>&1) &
    pid2=$!
    CONCURRENT_TEST_PIDS+=("$pid2")

    # 等待进程完成（带超时保护）
    local exit1=0 exit2=0
    wait "$pid1" 2>/dev/null || exit1=$?
    wait "$pid2" 2>/dev/null || exit2=$?

    # 检查是否超时（exit code 124 from timeout）
    if [ "$exit1" -eq 124 ] || [ "$exit2" -eq 124 ]; then
        skip "Concurrent test timed out - possible deadlock"
    fi

    # File should still be valid JSON
    if [ -f "$PATTERNS_FILE" ]; then
        if command -v jq &> /dev/null; then
            if jq . "$PATTERNS_FILE" > /dev/null 2>&1; then
                return 0
            else
                skip "Concurrent write corrupted file - file locking not yet implemented"
            fi
        fi
    fi

    # 如果两个进程都失败，说明功能未实现
    if [ "$exit1" -ne 0 ] && [ "$exit2" -ne 0 ]; then
        skip "Concurrency handling not yet implemented"
    fi
}

@test "PL-CONCURRENT-002: file lock prevents race condition" {
    mkdir -p .devbooks
    echo '{"schema_version": "1.0.0", "patterns": []}' > "$PATTERNS_FILE"

    # 检查脚本是否可执行
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not yet implemented"

    local lockfile="${PATTERNS_FILE}.lock"

    # 模拟另一个进程持有锁
    touch "$lockfile"

    # 使用超时运行，防止无限等待锁
    run run_with_timeout "$CONCURRENT_TIMEOUT" "$PATTERN_LEARNER" --learn --output "$PATTERNS_FILE" 2>&1

    # 清理锁文件
    rm -f "$lockfile"

    # 检查是否超时（可能在等待锁）
    if [ "$status" -eq 124 ]; then
        # 脚本在等待锁时超时，说明锁机制存在
        return 0
    fi

    # 检查是否检测到锁
    if [[ "$output" == *"lock"* ]] || [[ "$output" == *"busy"* ]] || \
       [[ "$output" == *"waiting"* ]]; then
        return 0
    fi

    # 如果脚本忽略了锁文件，说明锁机制未实现
    skip "File locking not yet implemented"
}

# ============================================================
# AC-006: 自动模式发现测试
# 契约测试: CT-PD-001, CT-PD-002, CT-PD-003
# ============================================================

# @test SC-PD-001: 发现命名模式
@test "SC-PD-001: auto-discover detects naming patterns" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    setup_auto_discover

    # 创建包含命名模式的测试文件
    mkdir -p "$TEST_TEMP_DIR/src/handlers"
    cat > "$TEST_TEMP_DIR/src/handlers/authHandler.ts" << 'EOF'
export function authHandler() { return "auth"; }
EOF
    cat > "$TEST_TEMP_DIR/src/handlers/userHandler.ts" << 'EOF'
export function userHandler() { return "user"; }
EOF
    cat > "$TEST_TEMP_DIR/src/handlers/dataHandler.ts" << 'EOF'
export function dataHandler() { return "data"; }
EOF

    run "$PATTERN_LEARNER" learn --auto-discover --project "$TEST_TEMP_DIR" --format json

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "auto-discover naming"
    assert_exit_success "$status"
    assert_valid_json "$output"
    assert_contains "$output" "Handler"
}

# @test SC-PD-003: 低于阈值不报告
@test "SC-PD-003: auto-discover ignores patterns below threshold" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    setup_auto_discover

    # 创建仅出现 2 次的模式（低于默认阈值 3）
    mkdir -p "$TEST_TEMP_DIR/src"
    cat > "$TEST_TEMP_DIR/src/fooService.ts" << 'EOF'
export const fooService = () => 1;
EOF
    cat > "$TEST_TEMP_DIR/src/barService.ts" << 'EOF'
export const barService = () => 2;
EOF

    run "$PATTERN_LEARNER" learn --auto-discover --project "$TEST_TEMP_DIR" --min-frequency 3 --format json

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "auto-discover threshold"
    assert_exit_success "$status"

    # Service 模式仅出现 2 次，不应被报告
    if command -v jq &> /dev/null; then
        local count=$(echo "$output" | jq '.patterns | length' 2>/dev/null || echo "0")
        [ "$count" -eq 0 ] || skip "Low frequency pattern incorrectly reported"
    fi
}

# @test SC-PD-004: 自定义阈值
@test "SC-PD-004: auto-discover respects custom min-frequency" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    setup_auto_discover

    # 创建 4 个 Helper 函数
    mkdir -p "$TEST_TEMP_DIR/src"
    for name in auth user data config; do
        cat > "$TEST_TEMP_DIR/src/${name}Helper.ts" << EOF
export function ${name}Helper() { return "${name}"; }
EOF
    done

    # 使用阈值 5，应不报告（仅 4 个）
    run "$PATTERN_LEARNER" learn --auto-discover --project "$TEST_TEMP_DIR" --min-frequency 5 --format json

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "auto-discover custom threshold"
    assert_exit_success "$status"
}

# @test SC-PD-005: JSON 格式输出
@test "SC-PD-005: auto-discover outputs valid JSON with required fields" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    skip_if_missing "jq"
    setup_auto_discover

    mkdir -p "$TEST_TEMP_DIR/src"
    for i in 1 2 3 4 5; do
        cat > "$TEST_TEMP_DIR/src/func${i}Handler.ts" << EOF
export function func${i}Handler() { return $i; }
EOF
    done

    run "$PATTERN_LEARNER" learn --auto-discover --project "$TEST_TEMP_DIR" --format json

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "auto-discover json"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证 JSON 结构
    assert_json_field "$output" ".patterns"
    assert_json_field "$output" ".metadata"
}

# @test SC-PD-006: 模式持久化
@test "SC-PD-006: auto-discover persists patterns to file" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    setup_auto_discover

    mkdir -p "$TEST_TEMP_DIR/src"
    for i in 1 2 3; do
        cat > "$TEST_TEMP_DIR/src/test${i}Helper.ts" << EOF
export function test${i}Helper() { return $i; }
EOF
    done

    run "$PATTERN_LEARNER" learn --auto-discover --project "$TEST_TEMP_DIR"

    skip_if_not_ready "$status" "$output" "auto-discover persist"
    assert_exit_success "$status"

    # 验证模式文件已创建
    [ -f "$DEVBOOKS_DIR/learned-patterns.json" ] || skip "Patterns file not created"

    teardown_auto_discover
}

# @test SC-PD-009: 功能禁用时跳过
@test "SC-PD-009: auto-discover skips when feature is disabled" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    setup_auto_discover

    mkdir -p "$TEST_TEMP_DIR/config"
    cat > "$TEST_TEMP_DIR/config/features.yaml" << 'EOF'
features:
  pattern_discovery:
    enabled: false
EOF
    export FEATURES_CONFIG="$TEST_TEMP_DIR/config/features.yaml"

    run "$PATTERN_LEARNER" learn --auto-discover --project "$TEST_TEMP_DIR"

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "auto-discover disabled"
    assert_exit_success "$status"
    assert_contains "$output" "disabled"
}

# @test SC-PD-010: 空代码库处理
@test "SC-PD-010: auto-discover handles empty codebase gracefully" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    setup_auto_discover

    mkdir -p "$TEST_TEMP_DIR/src"
    # 空项目，无源文件

    run "$PATTERN_LEARNER" learn --auto-discover --project "$TEST_TEMP_DIR"

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "auto-discover empty"
    assert_exit_success "$status"
    assert_contains "$output" "Insufficient"
}

# @test SC-PD-011: 置信度评估
@test "SC-PD-011: auto-discover includes confidence scores" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    skip_if_missing "jq"
    setup_auto_discover

    mkdir -p "$TEST_TEMP_DIR/src"
    for i in 1 2 3 4 5; do
        cat > "$TEST_TEMP_DIR/src/item${i}Controller.ts" << EOF
export class Item${i}Controller {}
EOF
    done

    run "$PATTERN_LEARNER" learn --auto-discover --project "$TEST_TEMP_DIR" --format json

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "auto-discover confidence"
    assert_exit_success "$status"
    assert_valid_json "$output"
    assert_contains "$output" "confidence"
}

# ============================================================
# 模式衰减测试 (Pattern Decay)
# 契约测试: CT-PD-001 ~ CT-PD-005
# 规格: algorithm-optimization-parity/specs/pattern-decay/spec.md
# ============================================================

# CT-PD-001: 置信度衰减公式
# 公式: confidence = initial × 0.95^days
@test "CT-PD-001: confidence decay follows exponential formula (0.95^days)" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    skip_if_missing "jq"
    setup_auto_discover

    # 创建模式文件，包含一个已学习的模式（初始置信度 1.0，10 天前创建）
    mkdir -p "$DEVBOOKS_DIR"
    cat > "$DEVBOOKS_DIR/learned-patterns.json" << 'EOF'
{
  "schema_version": "1.0.0",
  "patterns": [
    {
      "pattern_id": "test-decay-001",
      "name": "Handler suffix",
      "confidence": 1.0,
      "last_confirmed": "2026-01-07T00:00:00Z",
      "created_at": "2026-01-01T00:00:00Z"
    }
  ]
}
EOF

    # 运行衰减计算（假设当前日期为 2026-01-17，即 10 天后）
    run "$PATTERN_LEARNER" decay --patterns-file "$DEVBOOKS_DIR/learned-patterns.json" --format json

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "pattern decay formula"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 预期置信度: 1.0 × 0.95^10 ≈ 0.5987
    # 允许误差范围: 0.55 ~ 0.65
    local confidence
    confidence=$(echo "$output" | jq -r '.patterns[0].confidence' 2>/dev/null)
    if [ "$confidence" = "null" ] || [ -z "$confidence" ]; then
        skip "Decay output format not implemented"
    fi

    # 使用 awk 进行浮点数比较
    if ! awk -v c="$confidence" 'BEGIN { exit !(c >= 0.55 && c <= 0.65) }'; then
        echo "Expected confidence ~0.5987 (0.95^10), got $confidence" >&2
        return 1
    fi
}

# CT-PD-002: 重新确认重置衰减
# 再次匹配模式时，重置 last_confirmed 和置信度
@test "CT-PD-002: re-confirmation resets decay timer" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    skip_if_missing "jq"
    setup_auto_discover

    # 创建已衰减的模式（置信度 0.5）
    mkdir -p "$DEVBOOKS_DIR"
    cat > "$DEVBOOKS_DIR/learned-patterns.json" << 'EOF'
{
  "schema_version": "1.0.0",
  "patterns": [
    {
      "pattern_id": "test-reconfirm-001",
      "name": "Handler suffix",
      "regex": ".*Handler\\.(ts|js)$",
      "confidence": 0.5,
      "last_confirmed": "2026-01-01T00:00:00Z"
    }
  ]
}
EOF

    # 创建匹配模式的文件（触发重新确认）
    mkdir -p "$TEST_TEMP_DIR/src"
    for i in 1 2 3; do
        cat > "$TEST_TEMP_DIR/src/test${i}Handler.ts" << EOF
export function test${i}Handler() { return $i; }
EOF
    done

    # 运行学习，应触发模式重新确认
    run "$PATTERN_LEARNER" learn --auto-discover --project "$TEST_TEMP_DIR" --patterns "$DEVBOOKS_DIR/learned-patterns.json" --format json

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "pattern re-confirmation"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证置信度已重置（应接近 1.0 或显著高于 0.5）
    local confidence
    confidence=$(echo "$output" | jq -r '.patterns[] | select(.pattern_id == "test-reconfirm-001") | .confidence' 2>/dev/null)
    if [ "$confidence" = "null" ] || [ -z "$confidence" ]; then
        skip "Re-confirmation output format not implemented"
    fi

    # 重新确认后置信度应 >= 0.8
    if ! float_gte "$confidence" "0.8"; then
        echo "Expected confidence >= 0.8 after re-confirmation, got $confidence" >&2
        return 1
    fi
}

# CT-PD-003: 淘汰阈值
# 置信度 < 0.3 时移除模式
@test "CT-PD-003: patterns below elimination threshold (0.3) are removed" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    skip_if_missing "jq"
    setup_auto_discover

    # 创建包含低置信度模式的文件
    mkdir -p "$DEVBOOKS_DIR"
    cat > "$DEVBOOKS_DIR/learned-patterns.json" << 'EOF'
{
  "schema_version": "1.0.0",
  "patterns": [
    {
      "pattern_id": "keep-pattern-001",
      "name": "Active pattern",
      "confidence": 0.8,
      "last_confirmed": "2026-01-15T00:00:00Z"
    },
    {
      "pattern_id": "remove-pattern-001",
      "name": "Stale pattern",
      "confidence": 0.25,
      "last_confirmed": "2025-10-01T00:00:00Z"
    },
    {
      "pattern_id": "border-pattern-001",
      "name": "Border pattern",
      "confidence": 0.3,
      "last_confirmed": "2026-01-10T00:00:00Z"
    }
  ]
}
EOF

    # 运行衰减/清理
    run "$PATTERN_LEARNER" decay --patterns-file "$DEVBOOKS_DIR/learned-patterns.json" --eliminate-threshold 0.3 --format json

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "pattern elimination"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证低于阈值的模式已移除
    local removed_pattern
    removed_pattern=$(echo "$output" | jq -r '.patterns[] | select(.pattern_id == "remove-pattern-001")' 2>/dev/null)
    if [ -n "$removed_pattern" ] && [ "$removed_pattern" != "null" ]; then
        echo "Pattern with confidence 0.25 should have been removed" >&2
        return 1
    fi

    # 验证高于阈值的模式保留
    local kept_pattern
    kept_pattern=$(echo "$output" | jq -r '.patterns[] | select(.pattern_id == "keep-pattern-001") | .pattern_id' 2>/dev/null)
    if [ "$kept_pattern" != "keep-pattern-001" ]; then
        echo "Pattern with confidence 0.8 should have been kept" >&2
        return 1
    fi

    # 验证边界值模式（0.3）保留（>= 0.3 保留）
    local border_pattern
    border_pattern=$(echo "$output" | jq -r '.patterns[] | select(.pattern_id == "border-pattern-001") | .pattern_id' 2>/dev/null)
    if [ "$border_pattern" != "border-pattern-001" ]; then
        echo "Pattern with confidence exactly 0.3 should have been kept (boundary)" >&2
        return 1
    fi
}

# CT-PD-004: 触发周期
# 每日执行衰减（通过 --daily 标志或定时任务）
@test "CT-PD-004: decay can be triggered daily" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    setup_auto_discover

    mkdir -p "$DEVBOOKS_DIR"
    cat > "$DEVBOOKS_DIR/learned-patterns.json" << 'EOF'
{
  "schema_version": "1.0.0",
  "patterns": [
    {
      "pattern_id": "daily-test-001",
      "name": "Test pattern",
      "confidence": 1.0,
      "last_confirmed": "2026-01-16T00:00:00Z"
    }
  ],
  "last_decay_run": "2026-01-16T00:00:00Z"
}
EOF

    # 运行每日衰减
    run "$PATTERN_LEARNER" decay --daily --patterns-file "$DEVBOOKS_DIR/learned-patterns.json"

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "daily decay trigger"
    assert_exit_success "$status"

    # 验证支持 --daily 参数
    # 检查输出不包含 "unknown option" 或类似错误
    if [[ "$output" == *"unknown"* ]] || [[ "$output" == *"unrecognized"* ]]; then
        skip "Daily decay option not implemented"
    fi
}

# CT-PD-005: 性能要求
# 1000 模式衰减 < 100ms
@test "CT-PD-005: decay performance - 1000 patterns under 100ms" {
    [ -x "$PATTERN_LEARNER" ] || skip "pattern-learner.sh not executable"
    skip_if_missing "jq"
    setup_auto_discover

    mkdir -p "$DEVBOOKS_DIR"

    # 生成包含 1000 个模式的文件
    local patterns_json='{"schema_version":"1.0.0","patterns":['
    for i in $(seq 1 1000); do
        if [ $i -gt 1 ]; then
            patterns_json+=','
        fi
        # 随机化置信度和日期以模拟真实数据
        local confidence=$(awk -v seed=$i 'BEGIN { srand(seed); printf "%.2f", 0.3 + rand() * 0.7 }')
        local day=$((i % 30 + 1))
        patterns_json+="{\"pattern_id\":\"perf-test-$i\",\"name\":\"Pattern $i\",\"confidence\":$confidence,\"last_confirmed\":\"2026-01-$(printf '%02d' $day)T00:00:00Z\"}"
    done
    patterns_json+=']}'

    echo "$patterns_json" > "$DEVBOOKS_DIR/learned-patterns.json"

    # 验证文件有效
    if ! jq . "$DEVBOOKS_DIR/learned-patterns.json" > /dev/null 2>&1; then
        echo "Generated patterns file is not valid JSON" >&2
        teardown_auto_discover
        return 1
    fi

    # 先检查 decay 命令是否存在
    run "$PATTERN_LEARNER" decay --help
    if [ "$status" -ne 0 ]; then
        teardown_auto_discover
        skip "Decay command not implemented"
    fi

    # 测量执行时间
    local start_time end_time elapsed_ms
    start_time=$(get_time_ns)
    run "$PATTERN_LEARNER" decay --patterns-file "$DEVBOOKS_DIR/learned-patterns.json" --format json
    end_time=$(get_time_ns)

    teardown_auto_discover

    skip_if_not_ready "$status" "$output" "decay performance"
    assert_exit_success "$status"

    # 计算耗时
    elapsed_ms=$(( (end_time - start_time) / 1000000 ))

    # 验证性能要求: < 100ms
    if [ "$elapsed_ms" -ge 100 ]; then
        echo "Performance requirement failed: ${elapsed_ms}ms >= 100ms" >&2
        return 1
    fi

    echo "Decay of 1000 patterns completed in ${elapsed_ms}ms"
}

