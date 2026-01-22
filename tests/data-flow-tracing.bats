#!/usr/bin/env bats
# data-flow-tracing.bats - AC-003 Data Flow Tracing Acceptance Tests
#
# Purpose: Verify call-chain.sh --data-flow functionality
# Depends: bats-core, rg, jq
# Run: bats tests/data-flow-tracing.bats
#
# Baseline: 2026-01-19
# Change: 20260118-2112-enhance-code-intelligence-capabilities
# Trace: AC-003, REQ-DFT-001~009, SC-DFT-001~008
# Env: DATA_FLOW_P95_MAX_MS, DATA_FLOW_TOTAL_MAX_MS for perf thresholds

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
CALL_CHAIN="${PROJECT_ROOT}/scripts/call-chain.sh"
FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/performance/data-flow"

# ============================================================
# Helper Functions
# ============================================================

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
}

require_executable() {
    local path="$1"
    [ -x "$path" ] || fail "Expected executable: $path"
}

run_data_flow() {
    local symbol="$1"
    local direction="$2"
    local depth="$3"

    if [ -n "$direction" ]; then
        run "$CALL_CHAIN" --symbol "$symbol" --data-flow --data-flow-direction "$direction" --max-depth "$depth" --format json --cwd "$FIXTURE_DIR" 2>&1
    else
        run "$CALL_CHAIN" --symbol "$symbol" --data-flow --max-depth "$depth" --format json --cwd "$FIXTURE_DIR" 2>&1
    fi
}

warmup_data_flow() {
    local symbol="$1"
    local direction="$2"
    local depth="$3"

    for ((i=0; i<3; i++)); do
        "$CALL_CHAIN" --symbol "$symbol" --data-flow --data-flow-direction "$direction" --max-depth "$depth" --format json --cwd "$FIXTURE_DIR" >/dev/null 2>&1 || \
          fail "Warmup failed"
    done
}

# ============================================================
# Setup
# ============================================================

setup() {
    require_cmd jq
    require_cmd rg
    require_executable "$CALL_CHAIN"
    [ -d "$FIXTURE_DIR" ] || fail "Missing fixture directory: $FIXTURE_DIR"

    # Fixture completeness checks for repeatable perf/cycle tests.
    for fixture in source.ts transform.ts sink.ts cycle.ts large.ts; do
        [ -f "$FIXTURE_DIR/$fixture" ] || fail "Missing fixture file: $FIXTURE_DIR/$fixture"
    done
    # large.ts uses a 200+ line baseline to keep perf tests comparable across runs.
    large_lines=$(wc -l < "$FIXTURE_DIR/large.ts" | tr -d ' ')
    [ "$large_lines" -ge 200 ] || fail "Fixture large.ts too small: ${large_lines} lines"

    rg -q "loopA" "$FIXTURE_DIR/cycle.ts" || fail "Fixture cycle.ts missing loopA"
    rg -q "loopB" "$FIXTURE_DIR/cycle.ts" || fail "Fixture cycle.ts missing loopB"
    rg -q "sourceInput" "$FIXTURE_DIR/source.ts" || fail "Fixture source.ts missing sourceInput"
    rg -q "entry" "$FIXTURE_DIR/sink.ts" || fail "Fixture sink.ts missing entry symbol"
    rg -q "step1" "$FIXTURE_DIR/transform.ts" || fail "Fixture transform.ts missing step1"
    rg -q "sink" "$FIXTURE_DIR/sink.ts" || fail "Fixture sink.ts missing sink"
}

# ============================================================
# Basic Functionality Tests (DF-BASE)
# ============================================================

# @smoke
@test "DF-BASE-001: call-chain.sh exists and is executable" {
    [ -x "$CALL_CHAIN" ]
}

# @smoke
@test "DF-BASE-002: --data-flow parameter is recognized" {
    run_data_flow "entry" "" 2

    assert_exit_success "$status"
    echo "$output" | jq -e '.source.symbol == "entry"' >/dev/null || fail "Missing source symbol"
}

# @smoke
@test "DF-BASE-003: --help includes --data-flow description" {
    run "$CALL_CHAIN" --help 2>&1
    assert_exit_success "$status"
    assert_contains "$output" "--data-flow"
    assert_contains "$output" "forward"
    assert_contains "$output" "backward"
    assert_contains "$output" "both"
}

# @smoke
@test "DF-BASE-004: --symbol parameter required for data flow" {
    run "$CALL_CHAIN" --data-flow --format json 2>&1
    assert_exit_failure "$status"
    assert_contains "$output" "symbol"
}

# ============================================================
# Direction Tests (SC-DFT-001/002)
# ============================================================

# @critical
@test "DF-FORWARD-001: forward direction tracking" {
    run_data_flow "entry" "forward" 3

    assert_exit_success "$status"
    echo "$output" | jq -e '.direction == "forward"' >/dev/null || fail "direction should be forward"
    echo "$output" | jq -e '.paths | length >= 1' >/dev/null || fail "paths should not be empty"
}

# @critical
@test "DF-BACKWARD-001: backward direction tracking" {
    run_data_flow "entry" "backward" 3

    assert_exit_success "$status"
    echo "$output" | jq -e '.direction == "backward"' >/dev/null || fail "direction should be backward"
    echo "$output" | jq -e '.paths | length >= 1' >/dev/null || fail "paths should not be empty"
}

# @critical
@test "DF-BOTH-001: default direction is both" {
    run_data_flow "entry" "" 3

    assert_exit_success "$status"
    echo "$output" | jq -e '.direction == "both"' >/dev/null || fail "direction should be both"
}

# ============================================================
# Cross-File Tracking Tests (SC-DFT-008)
# ============================================================

# @critical
@test "DF-CROSS-001: cross-file tracking records file boundaries" {
    run_data_flow "entry" "both" 5

    assert_exit_success "$status"
    echo "$output" | jq -e '.paths | length >= 1' >/dev/null || fail "paths should not be empty"
    echo "$output" | jq -e '.paths[][] | select(.file | endswith("source.ts"))' >/dev/null || fail "missing source.ts"
    echo "$output" | jq -e '.paths[][] | select(.file | endswith("transform.ts"))' >/dev/null || fail "missing transform.ts"
    echo "$output" | jq -e '.paths[][] | select(.file | endswith("sink.ts"))' >/dev/null || fail "missing sink.ts"
}

# ============================================================
# Depth Limit Tests (REQ-DFT-007)
# ============================================================

# @critical
@test "DF-DEPTH-001: max depth respects 1-10 range" {
    run_data_flow "entry" "both" 1

    assert_exit_success "$status"
    echo "$output" | jq -e '.max_depth == 1' >/dev/null || fail "max_depth should be 1"

    run "$CALL_CHAIN" --symbol "entry" --data-flow --max-depth 999 --format json --cwd "$FIXTURE_DIR" 2>&1
    assert_exit_success "$status"
    echo "$output" | jq -e '.max_depth == 10' >/dev/null || fail "max_depth should be capped at 10"
}

# @critical
@test "DF-DEPTH-002: negative depth rejected" {
    run "$CALL_CHAIN" --symbol "entry" --data-flow --max-depth -1 --format json --cwd "$FIXTURE_DIR" 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "depth"
}

# @critical
@test "DF-DEPTH-003: zero depth rejected" {
    run "$CALL_CHAIN" --symbol "entry" --data-flow --max-depth 0 --format json --cwd "$FIXTURE_DIR" 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "depth"
}

# ============================================================
# Output Format Validation (REQ-DFT-005)
# ============================================================

# @critical
@test "DF-OUTPUT-001: JSON output includes required fields" {
    run_data_flow "entry" "both" 5

    assert_exit_success "$status"
    echo "$output" | jq -e '.source.symbol and .source.file and .source.line' >/dev/null || fail "missing source fields"
    echo "$output" | jq -e '.paths and .metadata' >/dev/null || fail "missing paths or metadata"
    echo "$output" | jq -e '.metadata.elapsed_ms >= 0' >/dev/null || fail "missing elapsed_ms"
}

# @full
@test "DF-OUTPUT-002: path nodes include transform and file metadata" {
    run_data_flow "entry" "both" 5

    assert_exit_success "$status"
    echo "$output" | jq -e '.paths[][] | has("transform") and has("file")' >/dev/null || fail "missing transform or file in path"
}

# ============================================================
# Cycle Detection Tests (REQ-DFT-008)
# ============================================================

# @critical
@test "DF-CYCLE-001: cycle detection flag present" {
    run "$CALL_CHAIN" --symbol "loopA" --data-flow --data-flow-direction forward --format json --cwd "$FIXTURE_DIR" 2>&1

    assert_exit_success "$status"
    echo "$output" | jq -e '.cycle_detected == true' >/dev/null || fail "cycle_detected should be true"
    echo "$output" | jq -e '.paths | length > 0' >/dev/null || fail "missing cycle paths"
    echo "$output" | jq -e '.paths[][] | select(.symbol == "loopA")' >/dev/null || fail "missing loopA in cycle path"
    echo "$output" | jq -e '.paths[][] | select(.symbol == "loopB")' >/dev/null || fail "missing loopB in cycle path"
}

# ============================================================
# Non-TS/JS Handling (REQ-DFT-009)
# ============================================================

# @critical
@test "DF-LANG-001: Python file returns friendly error" {
    local py_file="$BATS_TEST_TMPDIR/sample.py"
    cat > "$py_file" << 'PYEOF'
import os

def process_data(x):
    return x
PYEOF

    run "$CALL_CHAIN" --symbol "process_data" --data-flow --file "$py_file" --format json 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "TypeScript"
    assert_contains "$output" "JavaScript"
}

# ============================================================
# Error Handling Tests (DF-ERROR)
# ============================================================

# @critical
# 修复 C-003: 增强错误断言，验证错误消息包含具体符号名称
@test "DF-ERROR-001: missing symbol returns error" {
    run "$CALL_CHAIN" --symbol "does_not_exist_123" --data-flow --format json --cwd "$FIXTURE_DIR" 2>&1

    assert_exit_failure "$status"
    echo "$output" | grep -Eqi "not found|symbol" || fail "Missing not found error"
    # 验证错误消息包含具体符号名称
    assert_contains "$output" "does_not_exist_123"
}

# @critical
@test "DF-ERROR-002: invalid cwd returns error" {
    run "$CALL_CHAIN" --symbol "entry" --data-flow --format json --cwd "$FIXTURE_DIR/does-not-exist" 2>&1

    assert_exit_failure "$status"
    echo "$output" | grep -Eqi "cwd|directory|path" || fail "Missing invalid cwd error"
}

# @critical
@test "DF-ERROR-003: depth limit marks truncated path" {
    run "$CALL_CHAIN" --symbol "loopA" --data-flow --data-flow-direction forward --max-depth 1 --format json --cwd "$FIXTURE_DIR" 2>&1

    assert_exit_success "$status"
    echo "$output" | jq -e '.truncated == true' >/dev/null || fail "Missing truncated flag"
}

# ============================================================
# Performance Benchmark Tests (AC-003)
# ============================================================

# @full
@test "PERF-DFT-001: single hop latency within threshold" {
    local latencies=()
    local iterations=10

    warmup_data_flow "entry" "both" 1

    for ((i=0; i<iterations; i++)); do
        local start_ns end_ns elapsed
        start_ns=$(get_time_ns)
        run_data_flow "entry" "both" 1
        end_ns=$(get_time_ns)

        assert_exit_success "$status"
        elapsed=$(( (end_ns - start_ns) / 1000000 ))
        latencies+=("$elapsed")
    done

    local p95
    p95=$(calculate_p95 "${latencies[@]}")

    local threshold="${DATA_FLOW_P95_MAX_MS:-100}"
    [ "$p95" -lt "$threshold" ] || fail "P95 latency ${p95}ms exceeds ${threshold}ms"
}

# @full
@test "PERF-DFT-002: total tracking time within threshold" {
    local start_ns end_ns elapsed
    start_ns=$(get_time_ns)

    warmup_data_flow "entry" "both" 5
    run_data_flow "entry" "both" 5

    end_ns=$(get_time_ns)
    elapsed=$(( (end_ns - start_ns) / 1000000 ))

    assert_exit_success "$status"
    local threshold="${DATA_FLOW_TOTAL_MAX_MS:-500}"
    [ "$elapsed" -lt "$threshold" ] || fail "Total time ${elapsed}ms exceeds ${threshold}ms"
}
