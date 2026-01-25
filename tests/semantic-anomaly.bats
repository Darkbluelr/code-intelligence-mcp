#!/usr/bin/env bats
# 语义异常检测测试
# Change ID: 20260118-2112-enhance-code-intelligence-capabilities
# AC: AC-008

load 'helpers/common.bash'

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
}

require_executable() {
    local path="$1"
    [ -x "$path" ] || fail "Expected executable: $path"
}

validate_ground_truth_fixture() {
    local fixture="$1"
    jq -e 'type == "array" and length > 0 and all(.type and .file)' "$fixture" >/dev/null || \
      fail "Invalid ground-truth.json fixture"

    local expected_types=(
        "UNUSED_IMPORT"
        "MISSING_ERROR_HANDLER"
        "NAMING_VIOLATION"
        "MISSING_LOG"
        "INCONSISTENT_API_CALL"
    )
    for expected_type in "${expected_types[@]}"; do
        local count
        count=$(jq -r --arg type "$expected_type" 'map(select(.type == $type)) | length' "$fixture")
        [ "$count" -ge 2 ] || fail "ground-truth has too few samples for type: $expected_type"
    done
}

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
    export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
    export SEMANTIC_ANOMALY_SCRIPT="${SCRIPTS_DIR}/semantic-anomaly.sh"
    export FIXTURE_SOURCE_DIR="${BATS_TEST_DIRNAME}/fixtures/semantic-anomaly"
    setup_temp_dir
    export WORK_DIR="$TEST_TEMP_DIR/semantic-anomaly"
    mkdir -p "$WORK_DIR"
    export DEVBOOKS_DIR="$WORK_DIR/.devbooks"
    mkdir -p "$DEVBOOKS_DIR"

    require_cmd jq
    require_cmd bc
    require_executable "$SEMANTIC_ANOMALY_SCRIPT"
    [ -d "$FIXTURE_SOURCE_DIR" ] || fail "Missing fixture source: $FIXTURE_SOURCE_DIR"
    [ -f "$FIXTURE_SOURCE_DIR/benchmark.ts" ] || fail "Missing fixture: benchmark.ts"
    [ -f "$FIXTURE_SOURCE_DIR/ground-truth.json" ] || fail "Missing fixture: ground-truth.json"
    [ -f "$FIXTURE_SOURCE_DIR/clean.ts" ] || fail "Missing fixture: clean.ts"
    validate_ground_truth_fixture "$FIXTURE_SOURCE_DIR/ground-truth.json"
}

teardown() {
    cleanup_temp_dir
    unset DEVBOOKS_DIR
}

# ============================================================
# @smoke 快速验证
# ============================================================

# @smoke T-SA-001: 缺失错误处理检测 (SC-SA-001)
@test "T-SA-001: Detects missing error handler for async calls" {
    cat > "$WORK_DIR/missing-catch.ts" << 'EOF'
async function fetchData() {
    const response = await fetch('/api/data');
    return response.json();
}
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/missing-catch.ts")

    echo "$result" | jq -e '.anomalies | length > 0'
    echo "$result" | jq -e '.anomalies[] | select(.type == "MISSING_ERROR_HANDLER" and (.file | endswith("missing-catch.ts")) and (.line > 0))'
}

# @smoke T-SA-009: 输出格式验证
@test "T-SA-009: Output format matches specification" {
    cat > "$WORK_DIR/simple.ts" << 'EOF'
const x = 1;
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/simple.ts")

    echo "$result" | jq -e 'has("anomalies")'
    echo "$result" | jq -e 'has("summary")'
    echo "$result" | jq -e '.summary | has("total")'
    echo "$result" | jq -e '.summary | has("by_type")'
    echo "$result" | jq -e '.summary | has("by_severity")'
}

# ============================================================
# @critical 关键功能
# ============================================================

# @critical T-SA-002: 不一致 API 调用检测 (SC-SA-002)
@test "T-SA-002: Detects inconsistent API call patterns" {
    cat > "$WORK_DIR/file-a.ts" << 'EOF'
import { logger } from './logger';
function foo() {
    logger.info("Using logger");
}
EOF

    cat > "$WORK_DIR/file-b.ts" << 'EOF'
function bar() {
    console.log("Using console");
}
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/")

    echo "$result" | jq -e '.anomalies[] | select(.type == "INCONSISTENT_API_CALL")'
}

# @critical T-SA-003: 命名约定违规检测 (SC-SA-003)
@test "T-SA-003: Detects naming convention violations" {
    cat > "$WORK_DIR/naming.ts" << 'EOF'
// Project uses camelCase but this file has snake_case
const user_name = "test";
const user_age = 25;
function get_user_data() {}
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/naming.ts")

    echo "$result" | jq -e '.anomalies[] | select(.type == "NAMING_VIOLATION")'
}

# @critical T-SA-004: 缺失日志检测
@test "T-SA-004: Detects missing logging in critical operations" {
    cat > "$WORK_DIR/no-log.ts" << 'EOF'
async function processPayment(amount: number) {
    const result = await paymentGateway.charge(amount);
    return result;
}
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/no-log.ts")

    echo "$result" | jq -e '.anomalies[] | select(.type == "MISSING_LOG")'
}

# @critical T-SA-007: Pattern Learner 集成 (SC-SA-004)
@test "T-SA-007: Integrates with pattern-learner for learned patterns" {
    export PATTERN_LEARNER_DB="${WORK_DIR}/patterns.json"
    cat > "$PATTERN_LEARNER_DB" << 'EOF'
{
    "patterns": [
        {
            "id": "error-handling-001",
            "type": "error_handling",
            "description": "All DB operations must be in transaction",
            "confidence": 0.95
        }
    ]
}
EOF

    cat > "$WORK_DIR/no-tx.ts" << 'EOF'
async function updateUser(id: string, data: any) {
    await db.update('users', id, data);  // No transaction
}
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/no-tx.ts")

    echo "$result" | jq -e '.anomalies[] | select(.pattern_source | startswith("learned:"))'
}

# @critical T-SA-008: AST 分析准确性
@test "T-SA-008: AST analysis correctly identifies function boundaries" {
    cat > "$WORK_DIR/nested.ts" << 'EOF'
function outer() {
    try {
        function inner() {
            fetch('/api');  // This should be flagged
        }
    } catch (e) {}
}
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/nested.ts")

    echo "$result" | jq -e '.anomalies[] | select(.message | contains("inner"))'
}

# ============================================================
# @full 完整覆盖
# ============================================================

# @full T-SA-005: 未使用导入检测
@test "T-SA-005: Detects unused imports" {
    cat > "$WORK_DIR/unused-import.ts" << 'EOF'
import { foo, bar, baz } from './utils';

function test() {
    return foo();  // bar and baz are unused
}
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/unused-import.ts")

    echo "$result" | jq -e '.anomalies[] | select(.type == "UNUSED_IMPORT")'
}

# @full T-SA-006: 废弃模式检测
@test "T-SA-006: Detects deprecated patterns" {
    cat > "$WORK_DIR/deprecated.ts" << 'EOF'
// Using old callback style instead of async/await
function getData(callback) {
    fetch('/api').then(r => r.json()).then(callback);
}
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/deprecated.ts")

    echo "$result" | jq -e '.anomalies[] | select(.type == "DEPRECATED_PATTERN")'
}

# @full T-SA-010: 严重程度分级
@test "T-SA-010: Correctly assigns severity levels" {
    cat > "$WORK_DIR/mixed-severity.ts" << 'EOF'
// Error level: missing error handling
async function critical() {
    const data = await fetch('/api');
}

// Warning level: naming violation
const user_name = "test";

// Info level: unused import
import { unused } from './lib';
EOF

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$WORK_DIR/mixed-severity.ts")

    echo "$result" | jq -e '.anomalies[] | select(.severity == "error")'
    echo "$result" | jq -e '.anomalies[] | select(.severity == "warning")'
    echo "$result" | jq -e '.anomalies[] | select(.severity == "info")'
}

# @full T-SA-011: 召回率基准测试 (AC-008)
@test "T-SA-011: Recall rate >= 80% for known anomalies" {
    local benchmark="$WORK_DIR/benchmark.ts"
    local ground_truth="$FIXTURE_SOURCE_DIR/ground-truth.json"

    cp "$FIXTURE_SOURCE_DIR/benchmark.ts" "$benchmark"

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$benchmark")

    # M-003 修复：统一使用 unique 去重后的长度计算召回率
    # 原问题：expected 和 detected 使用 unique，但分母 total 取原始长度
    expected=$(jq -c '[.[] | "\(.type):\(.file)"] | unique' "$ground_truth")
    detected=$(echo "$result" | jq -c '[.anomalies[] | "\(.type):\(.file | split("/") | last)"] | unique')
    matches=$(jq -n --argjson expected "$expected" --argjson detected "$detected" '$expected | map(select(. as $e | $detected | index($e))) | length')

    # 修复：分母使用 unique 后的长度，与分子保持一致
    total=$(jq -c '[.[] | "\(.type):\(.file)"] | unique | length' "$ground_truth")

    # 验证计算一致性
    local expected_count
    expected_count=$(echo "$expected" | jq 'length')
    [ "$total" -eq "$expected_count" ] || fail "召回率计算不一致: total=$total, expected_count=$expected_count"

    recall=$(echo "scale=2; $matches / $total" | bc)
    echo "Recall: $matches / $total = $recall (unique-based)"

    [ $(echo "$recall >= 0.8" | bc) -eq 1 ]
}

# @full T-SA-012: 误报率基准测试 (AC-008)
@test "T-SA-012: False positive rate < 20% for clean code" {
    local clean="$WORK_DIR/clean.ts"

    cp "$FIXTURE_SOURCE_DIR/clean.ts" "$clean"

    result=$("$SEMANTIC_ANOMALY_SCRIPT" "$clean")

    total=$(echo "$result" | jq -r '.summary.total')
    errors=$(echo "$result" | jq -r '.summary.by_severity.error // 0')
    warnings=$(echo "$result" | jq -r '.summary.by_severity.warning // 0')

    [ "$errors" -eq 0 ] || fail "Unexpected error findings: $errors"
    [ "$warnings" -eq 0 ] || fail "Unexpected warning findings: $warnings"
    [ "$total" -le 1 ] || fail "Too many findings for clean code: $total"
}

# @full T-SA-013: 异常结果输出 (REQ-SA-001)
@test "T-SA-013: Outputs anomalies.jsonl with required fields" {
    local benchmark="$WORK_DIR/benchmark.ts"
    local output_file="$WORK_DIR/anomalies.jsonl"

    cp "$FIXTURE_SOURCE_DIR/benchmark.ts" "$benchmark"

    run "$SEMANTIC_ANOMALY_SCRIPT" --output "$output_file" "$benchmark"

    assert_exit_success "$status"
    [ -f "$output_file" ] || fail "Expected output file: $output_file"

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        echo "$line" | jq -e 'has("file") and has("type") and has("confidence") and has("line") and has("description")' >/dev/null || \
          fail "Invalid JSONL line: $line"
    done < "$output_file"
}

# @full T-SA-014: 用户反馈机制 (REQ-SA-004)
@test "T-SA-014: Records user feedback in JSONL" {
    local target_file="$WORK_DIR/benchmark.ts"
    export DEVBOOKS_DIR="$WORK_DIR/devbooks"

    mkdir -p "$DEVBOOKS_DIR"
    cp "$FIXTURE_SOURCE_DIR/benchmark.ts" "$target_file"

    run "$SEMANTIC_ANOMALY_SCRIPT" --feedback "$target_file" 5 normal
    assert_exit_success "$status"

    feedback_file=$(find "$DEVBOOKS_DIR" -maxdepth 1 -name "*.jsonl" | head -n 1)
    [ -n "$feedback_file" ] || fail "Feedback JSONL not found in $DEVBOOKS_DIR"

    line=$(head -n 1 "$feedback_file")
    echo "$line" | jq -e 'has("file") and has("line") and has("feedback") and has("timestamp")'
}

# @full T-SA-015: 异常报告生成 (REQ-SA-005)
@test "T-SA-015: Generates semantic anomaly report" {
    local report_root="$WORK_DIR/report-root"
    mkdir -p "$report_root/evidence"

    PROJECT_ROOT="$report_root" "$SEMANTIC_ANOMALY_SCRIPT" --report

    [ -f "$report_root/evidence/semantic-anomaly-report.md" ] || fail "Missing report"
    [ -s "$report_root/evidence/semantic-anomaly-report.md" ] || fail "Report is empty"
}
