#!/usr/bin/env bats
# 评测基准测试（Benchmark Tests）
# Change ID: 20260118-2112-enhance-code-intelligence-capabilities
# AC: AC-009
#
# Purpose: 验证评测基准功能（自举数据集 + 公开数据集）
# Depends: bats-core, jq, sqlite3
# Run: bats tests/benchmark.bats
#
# Baseline: 2026-01-19
# Change: 20260118-2112-enhance-code-intelligence-capabilities
# Trace: AC-009, REQ-BM-001~006, T-BM-001~006
#
# Test Categories:
#   - BM-BASE: Basic functionality
#   - BM-SELF: Self-bootstrap dataset (T-BM-001, T-BM-002)
#   - BM-PUBLIC: Public dataset (T-BM-003)
#   - BM-METRICS: Metrics calculation (T-BM-004, T-BM-005)
#   - BM-REGRESSION: Regression detection (T-BM-006)
#
# Env:
#   BENCHMARK_REGRESSION_THRESHOLD_RELAXED - 回归检测宽松阈值
#   BENCHMARK_REGRESSION_THRESHOLD_STRICT  - 回归检测严格阈值

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
BENCHMARK_SCRIPT="${PROJECT_ROOT}/scripts/benchmark.sh"
FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/benchmark"
FIXTURE_QUERIES="${FIXTURE_DIR}/queries.jsonl"

# ============================================================
# Helper Functions
# ============================================================

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
}

require_file() {
    local path="$1"
    [ -f "$path" ] || fail "Missing file: $path"
}

require_executable() {
    local path="$1"
    [ -x "$path" ] || fail "Expected executable: $path"
}

# 创建自举数据集（使用项目代码库）
create_self_bootstrap_dataset() {
    local dataset_dir="$BENCHMARK_OUTPUT/self-bootstrap"
    mkdir -p "$dataset_dir"
    local copied=0

    # 使用项目中的真实文件作为测试数据
    if cp -r "$PROJECT_ROOT/src" "$dataset_dir/" 2>/dev/null; then
        copied=1
    fi
    if cp -r "$PROJECT_ROOT/scripts" "$dataset_dir/" 2>/dev/null; then
        copied=1
    fi
    [ "$copied" -eq 1 ] || fail "Self-bootstrap dataset missing src/scripts content"

    local file_list file_count line_count
    file_list=$(rg --files "$dataset_dir")
    [ -n "$file_list" ] || fail "Self-bootstrap dataset has no files"
    file_count=$(echo "$file_list" | wc -l | tr -d ' ')
    [ "$file_count" -ge 5 ] || fail "Self-bootstrap dataset too small: ${file_count} files"
    line_count=$(echo "$file_list" | xargs wc -l | tail -n 1 | awk '{print $1}')
    [ "$line_count" -ge 200 ] || fail "Self-bootstrap dataset too small: ${line_count} lines"

    echo "$dataset_dir"
}

# 创建模拟的公开数据集
create_mock_public_dataset() {
    local dataset_dir="$BENCHMARK_OUTPUT/codesearchnet"
    mkdir -p "$dataset_dir"

    # 创建模拟的 CodeSearchNet 格式数据
    cat > "$dataset_dir/queries.jsonl" << 'QUERYEOF'
{"query": "how to read file", "language": "typescript", "expected_file": "file-reader.ts"}
{"query": "database connection", "language": "typescript", "expected_file": "db-connector.ts"}
{"query": "parse json", "language": "typescript", "expected_file": "json-parser.ts"}
QUERYEOF

    # m-002 修复：补充 expected_file 对应的代码桩
    # 复制 fixture 中的 stub 文件到数据集目录
    local stub_dir="$BATS_TEST_DIRNAME/fixtures/benchmark"
    if [ -d "$stub_dir" ]; then
        cp -f "$stub_dir/file-reader.ts" "$dataset_dir/" 2>/dev/null || true
        cp -f "$stub_dir/db-connector.ts" "$dataset_dir/" 2>/dev/null || true
        cp -f "$stub_dir/json-parser.ts" "$dataset_dir/" 2>/dev/null || true
    fi

    # 验证 stub 文件存在
    local missing_stubs=""
    [ -f "$dataset_dir/file-reader.ts" ] || missing_stubs="$missing_stubs file-reader.ts"
    [ -f "$dataset_dir/db-connector.ts" ] || missing_stubs="$missing_stubs db-connector.ts"
    [ -f "$dataset_dir/json-parser.ts" ] || missing_stubs="$missing_stubs json-parser.ts"

    if [ -n "$missing_stubs" ]; then
        echo "警告: 缺少 stub 文件:$missing_stubs (数据集加载映射可能失败)" >&2
    fi

    echo "$dataset_dir"
}

# 验证 JSON 格式的评测报告
validate_benchmark_report() {
    local report_file="$1"

    require_file "$report_file"

    # 验证 JSON 格式
    jq empty "$report_file" 2>/dev/null || fail "Invalid JSON report: $report_file"

    # 验证必需字段
    jq -e '.mrr_at_10' "$report_file" >/dev/null || fail "Missing mrr_at_10"
    jq -e '.recall_at_10' "$report_file" >/dev/null || fail "Missing recall_at_10"
    jq -e '.p95_latency_ms' "$report_file" >/dev/null || fail "Missing p95_latency_ms"
}

# ============================================================
# Setup and Teardown
# ============================================================

setup() {
    require_cmd jq
    require_cmd rg
    require_executable "$BENCHMARK_SCRIPT"
    require_file "$FIXTURE_QUERIES"

    export BENCHMARK_OUTPUT="${BATS_TEST_TMPDIR}/benchmark-output"
    mkdir -p "$BENCHMARK_OUTPUT"

    # Enable all features for testing
    export DEVBOOKS_ENABLE_ALL_FEATURES=1
}

teardown() {
    rm -rf "$BENCHMARK_OUTPUT"
}

# ============================================================
# Basic Functionality Tests (BM-BASE)
# ============================================================

# @smoke
@test "BM-BASE-001: benchmark.sh exists and is executable" {
    [ -x "$BENCHMARK_SCRIPT" ]
}

# @smoke
@test "BM-BASE-002: --help includes benchmark dataset options" {
    run "$BENCHMARK_SCRIPT" --help 2>&1
    assert_exit_success "$status"
    assert_contains "$output" "--dataset"
    assert_contains "$output" "--baseline"
    assert_contains "$output" "--compare"
    assert_contains "$output" "--output"
}

# ============================================================
# Self-Bootstrap Dataset Tests (BM-SELF)
# T-BM-001: 自举数据集测试
# T-BM-002: 自举数据集查询测试
# ============================================================

# @critical
@test "T-BM-001: Self-bootstrap dataset can be created from project codebase" {
    # Given: 项目代码库存在
    [ -d "$PROJECT_ROOT/src" ] || [ -d "$PROJECT_ROOT/scripts" ] || fail "No source code found"

    # When: 创建自举数据集
    local dataset_dir
    dataset_dir=$(create_self_bootstrap_dataset)

    # Then: 数据集目录包含代码文件
    [ -d "$dataset_dir" ]
    local file_count
    file_count=$(find "$dataset_dir" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.sh" \) | wc -l)
    [ "$file_count" -gt 0 ]

    # 数据集质量检查：至少包含一定规模的代码行与函数/类定义
    local total_lines
    total_lines=$(find "$dataset_dir" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.sh" \) -print0 | \
        xargs -0 wc -l 2>/dev/null | awk 'END { print $1 }')
    [ -n "$total_lines" ] && [ "$total_lines" -ge 200 ] || fail "Dataset too small: ${total_lines} lines"

    rg -g "*.ts" -g "*.js" -g "*.sh" -e "function|class" "$dataset_dir" >/dev/null 2>&1 || \
        fail "Dataset lacks function/class definitions"
}

# @critical
@test "T-BM-002: Self-bootstrap benchmark generates report" {
    local report_file="$BENCHMARK_OUTPUT/self-report.json"

    run "$BENCHMARK_SCRIPT" --dataset self --queries "$FIXTURE_QUERIES" --output "$report_file" 2>&1

    assert_exit_success "$status"
    validate_benchmark_report "$report_file"
}

# ============================================================
# Public Dataset Tests (BM-PUBLIC)
# T-BM-003: 公开数据集测试
# ============================================================

# @full
@test "T-BM-003: Public dataset benchmark generates report" {
    local dataset_dir
    dataset_dir=$(create_mock_public_dataset)
    local report_file="$BENCHMARK_OUTPUT/public-report.json"

    run "$BENCHMARK_SCRIPT" --dataset public --queries "$dataset_dir/queries.jsonl" --output "$report_file" 2>&1

    assert_exit_success "$status"
    validate_benchmark_report "$report_file"
}

# ============================================================
# Metrics Calculation Tests (BM-METRICS)
# T-BM-004: MRR@10 计算测试
# T-BM-005: P95 延迟计算测试
# ============================================================

# @critical
@test "T-BM-004: MRR@10 metric is within 0.0~1.0" {
    local report_file="$BENCHMARK_OUTPUT/metric-report.json"

    run "$BENCHMARK_SCRIPT" --dataset self --queries "$FIXTURE_QUERIES" --output "$report_file" 2>&1

    assert_exit_success "$status"
    validate_benchmark_report "$report_file"

    local mrr
    mrr=$(jq -r '.mrr_at_10' "$report_file")
    awk -v mrr="$mrr" 'BEGIN { exit !(mrr >= 0.0 && mrr <= 1.0) }' || fail "Invalid MRR: $mrr"
}

# @critical
@test "T-BM-005: P95 latency is measured and positive" {
    local report_file="$BENCHMARK_OUTPUT/latency-report.json"

    run "$BENCHMARK_SCRIPT" --dataset self --queries "$FIXTURE_QUERIES" --output "$report_file" 2>&1

    assert_exit_success "$status"
    validate_benchmark_report "$report_file"

    local p95
    p95=$(jq -r '.p95_latency_ms' "$report_file")
    [ "$p95" -gt 0 ] || fail "Invalid P95 latency: $p95"
}

# ============================================================
# Regression Detection Tests (BM-REGRESSION)
# T-BM-006: 回归检测测试
# ============================================================

# @full
@test "T-BM-006: Regression detection compares against baseline" {
    local baseline_file="$FIXTURE_DIR/regression-baseline.json"
    local current_file="$FIXTURE_DIR/regression-current.json"
    local regressed_file="$FIXTURE_DIR/regression-regressed.json"
    local relaxed_threshold="${BENCHMARK_REGRESSION_THRESHOLD_RELAXED:-0.20}"
    local strict_threshold="${BENCHMARK_REGRESSION_THRESHOLD_STRICT:-0.03}"

    require_file "$baseline_file"
    require_file "$current_file"
    require_file "$regressed_file"
    validate_benchmark_report "$baseline_file"
    validate_benchmark_report "$current_file"
    validate_benchmark_report "$regressed_file"

    # baseline vs current：同一数据集/查询集下应不触发回归
    BENCHMARK_REGRESSION_THRESHOLD="$relaxed_threshold" \
      run "$BENCHMARK_SCRIPT" --compare "$baseline_file" "$current_file" 2>&1
    assert_exit_success "$status"

    BENCHMARK_REGRESSION_THRESHOLD="$strict_threshold" \
      run "$BENCHMARK_SCRIPT" --compare "$baseline_file" "$regressed_file" 2>&1
    assert_exit_failure "$status"
    assert_contains "$output" "regression"
}

# ============================================================
# Error Handling Tests (边界条件)
# ============================================================

# @smoke
@test "BM-ERROR-001: --dataset requires a valid value" {
    run "$BENCHMARK_SCRIPT" --dataset 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "dataset"
}

# @smoke
@test "BM-ERROR-002: invalid baseline file is rejected" {
    local invalid_file="$BENCHMARK_OUTPUT/invalid.json"
    echo "{ invalid json" > "$invalid_file"

    run "$BENCHMARK_SCRIPT" --baseline "$invalid_file" 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "invalid"
}

# ============================================================
# Integration Tests
# ============================================================

# @full
@test "BM-INTEGRATION-001: Full benchmark pipeline (self-bootstrap)" {
    local report_file="$BENCHMARK_OUTPUT/full-report.json"

    run "$BENCHMARK_SCRIPT" --dataset self --queries "$FIXTURE_QUERIES" --output "$report_file" 2>&1

    assert_exit_success "$status"
    validate_benchmark_report "$report_file"
}

# ============================================================
# Performance Tests
# ============================================================

# @full
@test "PERF-BM-001: Benchmark completes within configured timeout" {
    local report_file="$BENCHMARK_OUTPUT/perf-report.json"
    local start_time end_time elapsed
    local timeout="${BENCHMARK_TIMEOUT:-300}"

    start_time=$(date +%s)
    run "$BENCHMARK_SCRIPT" --dataset self --queries "$FIXTURE_QUERIES" --output "$report_file" 2>&1
    end_time=$(date +%s)

    elapsed=$((end_time - start_time))

    assert_exit_success "$status"
    [ "$elapsed" -lt "$timeout" ] || fail "Benchmark too slow: ${elapsed}s (limit ${timeout}s)"
}
