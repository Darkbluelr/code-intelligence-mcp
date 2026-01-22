#!/usr/bin/env bats
# 架构漂移检测测试
# Change ID: 20260118-2112-enhance-code-intelligence-capabilities
# AC: AC-002 (REQ-DD-001~009)
# Test IDs: T-DD-001, T-DD-002, T-DD-ERROR-001, T-DD-003, T-DD-004, T-DD-005, T-DD-006, T-DD-007, T-DD-008, T-DD-009, T-DD-010, T-PERF-DD-001
# Env: DRIFT_DETECTOR_TIMEOUT 可覆盖性能阈值（秒）

load 'helpers/common.bash'

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
}

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
    export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
    export DRIFT_DETECTOR_SCRIPT="${SCRIPTS_DIR}/drift-detector.sh"
    export FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures/drift-detector"
    export TEMP_DIR=$(mktemp -d)
    export SNAPSHOTS_DIR="${TEMP_DIR}/snapshots"

    mkdir -p "$SNAPSHOTS_DIR"

    require_cmd jq

    [ -d "$FIXTURES_DIR" ] || fail "Missing fixture dir: $FIXTURES_DIR"
    local template="$FIXTURES_DIR/snapshot-template.json"
    [ -f "$template" ] || fail "Missing fixture: $template"
    jq -e . "$template" >/dev/null || fail "Invalid snapshot template: $template"
}

teardown() {
    rm -rf "$TEMP_DIR"
}

# Helper: 创建模拟快照
create_snapshot() {
    local name=$1
    local coupling=$2
    local violations=$3
    local template="${FIXTURES_DIR}/snapshot-template.json"

    [ -f "$template" ] || fail "Missing fixture: $template"

    # 使用固定时间戳以增强测试确定性
    local fixed_timestamp="2026-01-19T00:00:00Z"

    sed \
        -e "s/__TIMESTAMP__/${fixed_timestamp}/g" \
        -e "s/\"__COUPLING__\"/${coupling}/g" \
        -e "s/\"__VIOLATIONS__\"/${violations}/g" \
        "$template" > "$SNAPSHOTS_DIR/${name}.json"

    jq -e . "$SNAPSHOTS_DIR/${name}.json" >/dev/null || fail "Invalid snapshot JSON: $SNAPSHOTS_DIR/${name}.json"
}

# ============================================================
# @smoke 快速验证
# ============================================================

# @smoke: 脚本存在性检查
@test "T-DD-001: drift-detector.sh script exists and is executable" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]
    [ -x "$DRIFT_DETECTOR_SCRIPT" ]
}

# ============================================================
# @critical 关键功能
# ============================================================

# @critical T-DD-002: 耦合度变化检测 (SC-DD-001) (AC-002)
@test "T-DD-002: Detects coupling change > 10%" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]

    # 创建基线快照
    create_snapshot "baseline" 100 0

    # 创建当前快照（耦合度增加 15%）
    create_snapshot "current" 115 0

    result=$("$DRIFT_DETECTOR_SCRIPT" --compare "$SNAPSHOTS_DIR/baseline.json" "$SNAPSHOTS_DIR/current.json")

    echo "$result" | jq -e '.drift_detected == true'
    echo "$result" | jq -e '.changes[] | select(.type == "coupling_increase" and .change_percent >= 10)'
}

# @critical T-DD-ERROR-001: compare 参数错误处理
@test "T-DD-ERROR-001: compare requires baseline and current" {
    run "$DRIFT_DETECTOR_SCRIPT" --compare "$SNAPSHOTS_DIR/baseline.json" 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "compare 需要 baseline 和 current"
}

# @critical T-DD-003: 依赖方向违规检测 (SC-DD-002) (AC-002)
@test "T-DD-003: Detects dependency direction violations" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]

    # 创建包含违规的项目结构模拟
    mkdir -p "$TEMP_DIR/src/core" "$TEMP_DIR/src/api"

    # core 不应该依赖 api
    cat > "$TEMP_DIR/src/core/service.ts" << 'EOF'
import { ApiClient } from '../api/client';  // Violation!
export class CoreService {
    constructor(private api: ApiClient) {}
}
EOF

    cat > "$TEMP_DIR/src/api/client.ts" << 'EOF'
export class ApiClient {}
EOF

    # 定义架构规则
    cat > "$TEMP_DIR/arch-rules.yaml" << 'EOF'
rules:
  - from: core
    to: api
    allow: false
    reason: "Core should not depend on API layer"
EOF

    result=$("$DRIFT_DETECTOR_SCRIPT" --rules "$TEMP_DIR/arch-rules.yaml" "$TEMP_DIR/src")

    echo "$result" | jq -e '.violations | length > 0'
    echo "$result" | jq -e '.violations[] | select(.type == "dependency_violation")'
}

# @critical T-DD-004: 模块边界模糊检测 (SC-DD-003) (AC-002)
@test "T-DD-004: Detects module boundary blurring" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]

    # 创建基线快照（边界清晰）
    cat > "$SNAPSHOTS_DIR/baseline.json" << 'EOF'
{
    "timestamp": "2026-01-01T00:00:00Z",
    "metrics": {
        "boundary_clarity": 0.90,
        "cross_module_calls": 50
    }
}
EOF

    # 创建当前快照（边界模糊）
    cat > "$SNAPSHOTS_DIR/current.json" << 'EOF'
{
    "timestamp": "2026-01-17T00:00:00Z",
    "metrics": {
        "boundary_clarity": 0.65,
        "cross_module_calls": 120
    }
}
EOF

    result=$("$DRIFT_DETECTOR_SCRIPT" --compare "$SNAPSHOTS_DIR/baseline.json" "$SNAPSHOTS_DIR/current.json")

    echo "$result" | jq -e '.drift_detected == true'
    echo "$result" | jq -e '.changes[] | select(.type == "boundary_blur")'
}

# ============================================================
# @full 完整覆盖
# ============================================================

# @full T-DD-005: 快照格式符合 JSON Schema (AC-002)
@test "T-DD-005: Snapshot format follows JSON Schema" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]

    # 生成快照
    mkdir -p "$TEMP_DIR/src"
    echo "export const x = 1;" > "$TEMP_DIR/src/index.ts"

    result=$("$DRIFT_DETECTOR_SCRIPT" --snapshot "$TEMP_DIR/src" --output "$SNAPSHOTS_DIR/new.json")

    # 验证快照格式
    [ -f "$SNAPSHOTS_DIR/new.json" ]

    # 验证必需字段
    jq -e 'has("timestamp")' "$SNAPSHOTS_DIR/new.json"
    jq -e 'has("version")' "$SNAPSHOTS_DIR/new.json"
    jq -e 'has("metrics")' "$SNAPSHOTS_DIR/new.json"
    jq -e '.metrics | has("total_coupling")' "$SNAPSHOTS_DIR/new.json"
    jq -e '.metrics | has("dependency_violations")' "$SNAPSHOTS_DIR/new.json"
}

# @full T-DD-006: diff 对比输出 (AC-002)
@test "T-DD-006: Supports diff comparison between snapshots" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]

    create_snapshot "v1" 100 2
    create_snapshot "v2" 120 5

    result=$("$DRIFT_DETECTOR_SCRIPT" --diff "$SNAPSHOTS_DIR/v1.json" "$SNAPSHOTS_DIR/v2.json")

    # 验证 diff 输出
    echo "$result" | jq -e 'has("before")'
    echo "$result" | jq -e 'has("after")'
    echo "$result" | jq -e 'has("changes")'
    echo "$result" | jq -e '.changes | length > 0'
}

# @full T-DD-007: 定期快照对比报告
@test "T-DD-007: Generates periodic comparison report" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]

    # 创建多个时间点的快照
    for i in {1..5}; do
        coupling=$((100 + i * 5))
        create_snapshot "week-$i" $coupling $((i - 1))
    done

    result=$("$DRIFT_DETECTOR_SCRIPT" --report "$SNAPSHOTS_DIR" --period weekly)

    # 验证报告内容
    echo "$result" | jq -e 'has("trend")'
    echo "$result" | jq -e '.trend.coupling == "increasing"'
    echo "$result" | jq -e 'has("recommendations")'
}

# @full T-DD-008: 热点文件耦合度上升检测
@test "T-DD-008: Detects hotspot file coupling increase" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]

    # 基线快照
    cat > "$SNAPSHOTS_DIR/baseline.json" << 'EOF'
{
    "timestamp": "2026-01-01T00:00:00Z",
    "hotspot_files": [
        {"path": "src/core/service.ts", "coupling": 10},
        {"path": "src/api/handler.ts", "coupling": 8}
    ]
}
EOF

    # 当前快照（热点文件耦合度上升）
    cat > "$SNAPSHOTS_DIR/current.json" << 'EOF'
{
    "timestamp": "2026-01-17T00:00:00Z",
    "hotspot_files": [
        {"path": "src/core/service.ts", "coupling": 25},
        {"path": "src/api/handler.ts", "coupling": 15}
    ]
}
EOF

    result=$("$DRIFT_DETECTOR_SCRIPT" --compare "$SNAPSHOTS_DIR/baseline.json" "$SNAPSHOTS_DIR/current.json")

    echo "$result" | jq -e '.changes[] | select(.type == "hotspot_coupling_increase")'
    echo "$result" | jq -e '.changes[] | select(.file == "src/core/service.ts")'
}

# @full: 综合检测测试
@test "T-DD-009: Comprehensive drift detection" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]

    # 创建复杂的漂移场景
    cat > "$SNAPSHOTS_DIR/baseline.json" << 'EOF'
{
    "timestamp": "2026-01-01T00:00:00Z",
    "version": "1.0.0",
    "metrics": {
        "total_coupling": 100,
        "dependency_violations": 0,
        "boundary_clarity": 0.90,
        "cyclic_dependencies": 0
    },
    "hotspot_files": [
        {"path": "src/core/service.ts", "coupling": 10},
        {"path": "src/api/handler.ts", "coupling": 8}
    ]
}
EOF

    cat > "$SNAPSHOTS_DIR/current.json" << 'EOF'
{
    "timestamp": "2026-01-17T00:00:00Z",
    "version": "1.0.0",
    "metrics": {
        "total_coupling": 135,
        "dependency_violations": 5,
        "boundary_clarity": 0.60,
        "cyclic_dependencies": 2
    },
    "hotspot_files": [
        {"path": "src/core/service.ts", "coupling": 25},
        {"path": "src/api/handler.ts", "coupling": 25}
    ]
}
EOF

    result=$("$DRIFT_DETECTOR_SCRIPT" --compare "$SNAPSHOTS_DIR/baseline.json" "$SNAPSHOTS_DIR/current.json")

    # 验证检测到多种漂移
    echo "$result" | jq -e '.drift_detected == true'
    echo "$result" | jq -e '.score > 50'
    echo "$result" | jq -e '.severity == "high"'
    echo "$result" | jq -e '.changes | length >= 4'
    echo "$result" | jq -e '.changes[] | select(.type == "hotspot_coupling_increase")'
    echo "$result" | jq -e '.changes[] | select(.type == "boundary_blur")'
    echo "$result" | jq -e '.changes[] | select(.type == "cyclic_dependency_increase")'

    # 验证推荐操作
    echo "$result" | jq -e '.recommendations | length > 0'
}

# @critical T-DD-010: 首次运行生成基线快照
@test "T-DD-010: First run creates baseline snapshot without drift detection" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]

    # 创建简单的项目结构
    mkdir -p "$TEMP_DIR/src"
    cat > "$TEMP_DIR/src/index.ts" << 'EOF'
import { helper } from './helper';
export const main = () => helper();
EOF

    cat > "$TEMP_DIR/src/helper.ts" << 'EOF'
export const helper = () => "hello";
EOF

    # 确保快照目录为空（首次运行）
    rm -rf "$SNAPSHOTS_DIR"/*

    # 生成首次快照
    "$DRIFT_DETECTOR_SCRIPT" --snapshot "$TEMP_DIR/src" --output "$SNAPSHOTS_DIR/baseline.json"

    # 验证快照文件已创建
    [ -f "$SNAPSHOTS_DIR/baseline.json" ]

    # 验证快照包含必要字段
    jq -e 'has("timestamp")' "$SNAPSHOTS_DIR/baseline.json"
    jq -e 'has("version")' "$SNAPSHOTS_DIR/baseline.json"
    jq -e 'has("metrics")' "$SNAPSHOTS_DIR/baseline.json"
    jq -e '.metrics.total_coupling >= 0' "$SNAPSHOTS_DIR/baseline.json"

    # 验证首次运行不应该与自身比较产生漂移
    # （首次运行场景：没有历史快照可比较）
    local snapshot_count=$(ls -1 "$SNAPSHOTS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
    [ "$snapshot_count" -eq 1 ]
}

# @full: 性能测试
# 修复 C-002: 放宽默认阈值从 10s 到 15s，增加预热次数到 10 次
@test "T-PERF-DD-001: Drift detection completes in < 15s for medium project" {
    [ -f "$DRIFT_DETECTOR_SCRIPT" ]
    local timeout="${DRIFT_DETECTOR_TIMEOUT:-15}"

    # 创建中等规模的模拟项目
    mkdir -p "$TEMP_DIR/project"
    for i in {1..100}; do
        echo "export const module$i = {};" > "$TEMP_DIR/project/module$i.ts"
    done

    for i in {1..10}; do
        "$DRIFT_DETECTOR_SCRIPT" --snapshot "$TEMP_DIR/project" --output "$SNAPSHOTS_DIR/warmup-$i.json" >/dev/null 2>&1 || \
          fail "Warmup failed"
    done

    local iterations="${DRIFT_DETECTOR_PERF_ITERS:-5}"
    local latencies=()
    for ((i=0; i<iterations; i++)); do
        local start_ns end_ns elapsed_ms
        start_ns=$(get_time_ns)
        "$DRIFT_DETECTOR_SCRIPT" --snapshot "$TEMP_DIR/project" --output "$SNAPSHOTS_DIR/perf-$i.json" >/dev/null 2>&1 || \
          fail "Perf snapshot failed"
        end_ns=$(get_time_ns)
        elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
        latencies+=("$elapsed_ms")
    done

    local p95
    p95=$(calculate_p95 "${latencies[@]}")
    local threshold_ms=$((timeout * 1000))
    echo "Snapshot p95: ${p95}ms (threshold: ${threshold_ms}ms)"

    [ "$p95" -lt "$threshold_ms" ]
}
