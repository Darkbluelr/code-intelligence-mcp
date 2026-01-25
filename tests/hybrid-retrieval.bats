#!/usr/bin/env bats
# 混合检索测试（Hybrid Retrieval Tests）
# Change ID: 20260118-2112-enhance-code-intelligence-capabilities
# AC: AC-005
#
# Purpose: 验证混合检索功能（关键词 + 向量 + 图距离的 RRF 融合）
# Depends: bats-core, jq, sqlite3
# Run: bats tests/hybrid-retrieval.bats
#
# Baseline: 2026-01-19
# Change: 20260118-2112-enhance-code-intelligence-capabilities
# Trace: AC-005, REQ-HR-001~005, SC-HR-001~005
# Coverage: REQ-HR-001 (RRF), REQ-HR-002 (命令), REQ-HR-003 (权重), REQ-HR-004 (降级), REQ-HR-005 (质量)
#
# Test Categories:
#   - HR-BASE: Basic functionality
#   - HR-RRF: RRF fusion algorithm (SC-HR-001)
#   - HR-WEIGHT: Weight configuration (SC-HR-002, SC-HR-005)
#     - T-HR-002: Weight config exists
#     - T-HR-006: Weight affects ranking
#     - T-HR-007: Weight sum validation
#   - HR-QUALITY: Retrieval quality (REQ-HR-005)
#   - HR-AB: A/B testing framework (SC-HR-004)

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
GRAPH_RAG_SCRIPT="${PROJECT_ROOT}/scripts/graph-rag.sh"
EMBEDDING_SCRIPT="${PROJECT_ROOT}/scripts/embedding.sh"
CONFIG_FEATURES_FILE="${PROJECT_ROOT}/config/features.yaml"

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

require_file() {
    local path="$1"
    [ -f "$path" ] || fail "Missing file: $path"
}

run_graph_rag_with_mock_env() {
    # Mock 参数:
    #   MOCK_GRAPH_AVAILABLE=1 强制启用 Graph mock
    #   --mock-embedding / --mock-graph 使用离线 mock 数据
    MOCK_GRAPH_AVAILABLE=1 \
      DEVBOOKS_DIR="$WORKDIR/.devbooks" \
      DEVBOOKS_FEATURE_CONFIG="$WORKDIR/config/features.yaml" \
      FEATURES_CONFIG="$WORKDIR/config/features.yaml" \
      run "$@" 2>&1
}

validate_graph_rag_mock_output() {
    local payload="$1"
    local status_code="$2"

    if [ "$status_code" -eq 0 ]; then
        echo "$payload" | jq -e 'has("metadata") and has("candidates")' >/dev/null || \
          fail "Mock output missing metadata/candidates"
        echo "$payload" | jq -e '.metadata | has("graph_available") and has("fusion_depth")' >/dev/null || \
          fail "Mock metadata missing required fields"
    fi
}

run_graph_rag_mock() {
    local query="$1"
    local depth="$2"

    run_graph_rag_with_mock_env "$GRAPH_RAG_SCRIPT" \
      --query "$query" \
      --fusion-depth "$depth" \
      --format json \
      --mock-embedding \
      --mock-graph \
      --cwd "$WORKDIR"

    validate_graph_rag_mock_output "$output" "$status"
}

# ============================================================
# Setup
# ============================================================

setup() {
    require_cmd jq
    require_cmd rg
    require_executable "$GRAPH_RAG_SCRIPT"
    require_executable "$EMBEDDING_SCRIPT"

    setup_temp_dir
    WORKDIR="$TEST_TEMP_DIR/hybrid"
    mkdir -p "$WORKDIR" "$WORKDIR/config" "$WORKDIR/.devbooks"
    export DEVBOOKS_DIR="$WORKDIR/.devbooks"
    export DEVBOOKS_FEATURE_CONFIG="$WORKDIR/config/features.yaml"
    export FEATURES_CONFIG="$WORKDIR/config/features.yaml"

    cat > "$WORKDIR/sample.ts" << 'SAMPLEEOF'
export function hybridEntry() {
  const payload = "graph retrieval";
  return payload;
}
SAMPLEEOF

    cat > "$WORKDIR/config/features.yaml" << 'FEATURESEOF'
features:
  hybrid_retrieval:
    enabled: true
    weights:
      keyword: 0.3
      vector: 0.5
      graph: 0.2
    rrf_k: 60
FEATURESEOF
}

teardown() {
    cleanup_temp_dir
    unset DEVBOOKS_DIR
    unset DEVBOOKS_FEATURE_CONFIG
    unset FEATURES_CONFIG
    # C-003 fix: Clean up mock environment variables
    unset MOCK_GRAPH_AVAILABLE
    unset LLM_MOCK_RESPONSE
    unset LLM_MOCK_DELAY_MS
    unset LLM_MOCK_FAIL_COUNT
}

# ============================================================
# Basic Functionality Tests (HR-BASE)
# ============================================================

# @smoke
@test "HR-BASE-001: graph-rag.sh exists and is executable" {
    [ -x "$GRAPH_RAG_SCRIPT" ]
}

# @smoke
@test "HR-BASE-002: --help includes fusion/hybrid retrieval description" {
    run "$GRAPH_RAG_SCRIPT" --help 2>&1
    assert_exit_success "$status"
    assert_contains "$output" "fusion"
    assert_contains "$output" "--fusion-depth"
}

# ============================================================
# RRF Fusion Algorithm Tests (SC-HR-001)
# T-HR-001: RRF 融合算法测试
# ============================================================

# @critical
@test "T-HR-001: Fusion output includes graph + vector signals" {
    run_graph_rag_mock "graph store" 1

    assert_exit_success "$status"

    echo "$output" | jq -e '.metadata.fusion_depth == 1' >/dev/null || fail "Missing fusion_depth"
    echo "$output" | jq -e '.metadata.graph_available == true' >/dev/null || fail "Graph should be available in mock mode"
    echo "$output" | jq -e '.candidates | length > 0' >/dev/null || fail "No candidates returned"
    echo "$output" | jq -e '.candidates[] | select(.source == "vector") | (has("file_path") and has("relevance_score"))' >/dev/null || \
      fail "Missing vector candidates"
    echo "$output" | jq -e '.candidates[] | select(.source == "graph") | (has("file_path") and has("distance"))' >/dev/null || \
      fail "Missing graph candidates"

    # 候选必须包含向量与图信号字段（relevance_score + distance）
    echo "$output" | jq -e '.candidates[] | has("relevance_score") and (has("distance") or has("depth"))' >/dev/null || \
      fail "Candidates missing relevance_score or distance"
}

# @critical
@test "T-HR-GRAPH-001: Mock Graph candidates follow graph output schema" {
    run_graph_rag_mock "graph store" 1

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.graph_candidates >= 1' >/dev/null || fail "graph_candidates should be >= 1"
    echo "$output" | jq -e '.candidates[] | select(.source == "graph") | has("distance")' >/dev/null || \
      fail "Graph candidates missing distance"
    echo "$output" | jq -e '.candidates[] | select(.source == "graph") | (has("file_path") or has("file"))' >/dev/null || \
      fail "Graph candidates missing file path"
}

# ============================================================
# Weight Configuration Tests (SC-HR-002, SC-HR-005)
# ============================================================

# @critical
@test "T-HR-002: Weight configuration exists in config/features.yaml" {
    require_file "$CONFIG_FEATURES_FILE"

    run grep -n "hybrid_retrieval" "$CONFIG_FEATURES_FILE"
    assert_exit_success "$status"

    run grep -n "weights" "$CONFIG_FEATURES_FILE"
    assert_exit_success "$status"
}

# @critical
@test "T-HR-006: Weight configuration affects ranking order" {
    cat > "$WORKDIR/config/features.yaml" << 'FEATURESEOF'
features:
  hybrid_retrieval:
    enabled: true
    weights:
      keyword: 0.1
      vector: 0.1
      graph: 0.8
    rrf_k: 60
FEATURESEOF

    run_graph_rag_mock "graph store" 1
    assert_exit_success "$status"
    local top_graph
    top_graph=$(echo "$output" | jq -r '.candidates[0].file_path // .candidates[0].file')
    local top_graph_source
    top_graph_source=$(echo "$output" | jq -r '.candidates[0].source')
    [ -n "$top_graph" ] || fail "Missing top candidate for graph-heavy weights"
    [ "$top_graph_source" = "graph" ] || fail "Expected graph-heavy top source, got: $top_graph_source"

    cat > "$WORKDIR/config/features.yaml" << 'FEATURESEOF'
features:
  hybrid_retrieval:
    enabled: true
    weights:
      keyword: 0.1
      vector: 0.8
      graph: 0.1
    rrf_k: 60
FEATURESEOF

    run_graph_rag_mock "graph store" 1
    assert_exit_success "$status"
    local top_vector
    top_vector=$(echo "$output" | jq -r '.candidates[0].file_path // .candidates[0].file')
    local top_vector_source
    top_vector_source=$(echo "$output" | jq -r '.candidates[0].source')
    [ -n "$top_vector" ] || fail "Missing top candidate for vector-heavy weights"
    [ "$top_vector_source" = "vector" ] || fail "Expected vector-heavy top source, got: $top_vector_source"

    [ "$top_graph" != "$top_vector" ] || fail "Ranking unchanged after weight shift"
}

# @critical
@test "T-HR-007: Weight sum validation equals 1.0" {
    # 场景：混合检索融合三种权重（关键词、向量、图距离）
    # 验证：默认权重配置权重总和 = 1.0
    # Trace: REQ-HR-003 (权重约束), SC-HR-005 (权重配置验证)

    # Test 1: 默认权重配置
    require_file "$CONFIG_FEATURES_FILE"
    local keyword_weight vector_weight graph_weight weight_sum

    keyword_weight=$(yq '.features.hybrid_retrieval.weights.keyword' "$CONFIG_FEATURES_FILE" 2>/dev/null || echo "0.3")
    vector_weight=$(yq '.features.hybrid_retrieval.weights.vector' "$CONFIG_FEATURES_FILE" 2>/dev/null || echo "0.5")
    graph_weight=$(yq '.features.hybrid_retrieval.weights.graph' "$CONFIG_FEATURES_FILE" 2>/dev/null || echo "0.2")

    # 如果 yq 不可用，回退到 grep + awk
    if ! command -v yq >/dev/null 2>&1; then
        keyword_weight=$(grep -A3 "weights:" "$CONFIG_FEATURES_FILE" | grep "keyword:" | awk '{print $2}')
        vector_weight=$(grep -A3 "weights:" "$CONFIG_FEATURES_FILE" | grep "vector:" | awk '{print $2}')
        graph_weight=$(grep -A3 "weights:" "$CONFIG_FEATURES_FILE" | grep "graph:" | awk '{print $2}')
    fi

    # M-006 修复：使用容差比较代替字符串等值
    # 原问题：[ "$weight_sum" = "1.00" ] 对小数精度敏感
    if command -v bc >/dev/null 2>&1; then
        weight_sum=$(echo "scale=4; $keyword_weight + $vector_weight + $graph_weight" | bc)
        # 使用容差比较：|sum - 1.0| < 0.01
        local diff
        diff=$(echo "scale=4; x = $weight_sum - 1.0; if (x < 0) -x else x" | bc)
        local is_valid
        is_valid=$(echo "$diff < 0.01" | bc)
        [ "$is_valid" -eq 1 ] || fail "Default weight sum is $weight_sum, expected ~1.0 (tolerance 0.01), diff=$diff (keyword=$keyword_weight, vector=$vector_weight, graph=$graph_weight)"
    else
        weight_sum=$(awk "BEGIN {printf \"%.4f\", $keyword_weight + $vector_weight + $graph_weight}")
        # awk 容差比较
        local is_valid
        is_valid=$(awk "BEGIN {diff = $weight_sum - 1.0; if (diff < 0) diff = -diff; print (diff < 0.01) ? 1 : 0}")
        [ "$is_valid" -eq 1 ] || fail "Default weight sum is $weight_sum, expected ~1.0 (tolerance 0.01) (keyword=$keyword_weight, vector=$vector_weight, graph=$graph_weight)"
    fi

    echo "Weight sum validation: $weight_sum (tolerance ±0.01)"

    # Test 2: 自定义权重配置 --fusion-weights
    # 测试有效权重配置
    run_graph_rag_with_mock_env "$GRAPH_RAG_SCRIPT" \
      --query "test query" \
      --fusion-depth 1 \
      --fusion-weights "0.25,0.50,0.25" \
      --format json \
      --mock-embedding \
      --mock-graph \
      --cwd "$WORKDIR"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.fusion_weights' >/dev/null || fail "Missing fusion_weights in metadata"

    # 验证配置的权重总和为 1.0
    local custom_sum
    if command -v bc >/dev/null 2>&1; then
        custom_sum=$(echo "scale=2; 0.25 + 0.50 + 0.25" | bc)
    else
        custom_sum=$(awk "BEGIN {printf \"%.2f\", 0.25 + 0.50 + 0.25}")
    fi
    [ "$custom_sum" = "1.00" ] || fail "Custom weight sum is $custom_sum, expected 1.00"

    # Test 3: 无效权重配置（总和 ≠ 1.0）应该失败
    run "$GRAPH_RAG_SCRIPT" \
      --query "test query" \
      --fusion-depth 1 \
      --fusion-weights "0.3,0.4,0.2" \
      --format json \
      --mock-embedding \
      --mock-graph \
      --cwd "$WORKDIR" 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "sum must equal 1.0"
}

# @smoke
@test "T-HR-003: Fusion depth accepts 0~5 and rejects invalid values" {
    run_graph_rag_mock "graph store" 0
    assert_exit_success "$status"

    run_graph_rag_mock "graph store" 5
    assert_exit_success "$status"

    run "$GRAPH_RAG_SCRIPT" --query "graph store" --fusion-depth 6 --format json --mock-embedding --mock-graph --cwd "$WORKDIR" 2>&1
    assert_exit_failure "$status"
    assert_contains "$output" "invalid fusion-depth"
}

# ============================================================
# Retrieval Quality Tests (REQ-HR-005)
# T-HR-004: MRR@10 质量测试
# ============================================================

# @critical
@test "T-HR-004: Hybrid benchmark reports quality metrics" {
    run "$EMBEDDING_SCRIPT" --benchmark "${PROJECT_ROOT}/tests/fixtures/benchmark/queries.jsonl" 2>&1

    assert_exit_success "$status"
    # 期望输出包含质量指标
    echo "$output" | jq -e '.mrr_at_10 and .recall_at_10 and .precision_at_10' >/dev/null || \
      fail "Benchmark output missing metrics"
}

# ============================================================
# A/B Testing Framework Tests (SC-HR-004)
# T-HR-005: A/B 测试框架
# ============================================================

# @full
@test "T-HR-005: Different fusion depths produce different result sets" {
    run_graph_rag_mock "graph store" 0
    local output_depth0="$output"

    run_graph_rag_mock "graph store" 2
    local output_depth2="$output"

    [ "$output_depth0" != "$output_depth2" ] || fail "Results identical across depths"
}

# ============================================================
# Integration Tests (HR-INTEGRATION)
# ============================================================

# @full
@test "HR-INTEGRATION-001: Hybrid retrieval integrates with embedding search" {
    run_graph_rag_mock "graph store" 1

    assert_exit_success "$status"
    echo "$output" | jq -e '.candidates[] | select(.file_path == "src/auth.ts")' >/dev/null || \
      fail "Embedding mock candidates missing"
}

# @full
@test "HR-INTEGRATION-002: Hybrid retrieval integrates with graph store" {
    run_graph_rag_mock "graph store" 1

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.graph_available == true' >/dev/null || fail "Graph not available"
}

# ============================================================
# Performance Tests (HR-PERF)
# ============================================================

# @full
@test "HR-PERF-001: Hybrid retrieval P95 latency < 500ms" {
    local latencies=()
    local iterations=10

    # M-006 修复：验证预热是否成功
    for ((i=0; i<10; i++)); do
        MOCK_GRAPH_AVAILABLE=1 "$GRAPH_RAG_SCRIPT" --query "warmup" --fusion-depth 1 --format json --mock-embedding --mock-graph --cwd "$WORKDIR" >/dev/null 2>&1 || \
          fail "Warmup iteration $i failed"
    done

    for ((i=0; i<iterations; i++)); do
        local start_ns end_ns elapsed
        start_ns=$(get_time_ns)
        run_graph_rag_mock "graph store" 1
        end_ns=$(get_time_ns)

        assert_exit_success "$status"
        elapsed=$(( (end_ns - start_ns) / 1000000 ))
        latencies+=("$elapsed")
    done

    local p95
    p95=$(calculate_p95 "${latencies[@]}")

    [ "$p95" -lt 500 ] || fail "P95 latency ${p95}ms exceeds 500ms"
}

# ============================================================
# Error Handling Tests (HR-ERROR)
# ============================================================

# @smoke
@test "HR-ERROR-001: Embedding unavailable falls back to keyword search" {
    run "$GRAPH_RAG_SCRIPT" --query "graph" --fusion-depth 1 --format json --cwd "$WORKDIR" 2>&1

    assert_exit_success "$status"
    echo "$output" | jq -e '.candidates | length > 0' >/dev/null || fail "No candidates from keyword fallback"
}

# @smoke
@test "HR-ERROR-002: Graph store unavailable triggers fallback" {
    GRAPH_UNAVAILABLE=1 run "$GRAPH_RAG_SCRIPT" --query "graph" --fusion-depth 1 --format json --mock-embedding --cwd "$WORKDIR" 2>&1

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.graph_available == false' >/dev/null || fail "Graph should be unavailable"
    echo "$output" | jq -e '.metadata.graph_fallback_reason == "graph_unavailable"' >/dev/null || \
      fail "Missing Graph fallback reason"
}

# ============================================================
# Output Format Tests (HR-OUTPUT)
# ============================================================

# @smoke
@test "HR-OUTPUT-001: Output format is valid JSON with required fields" {
    run_graph_rag_mock "graph store" 1

    assert_exit_success "$status"
    echo "$output" | jq -e '.candidates and .metadata' >/dev/null || fail "Missing candidates or metadata"
    echo "$output" | jq -e '.metadata.fusion_depth' >/dev/null || fail "Missing fusion_depth"
    echo "$output" | jq -e '.metadata.graph_depth' >/dev/null || fail "Missing graph_depth"
}

# ============================================================
# Boundary Tests
# ============================================================

# @smoke
@test "HR-ERROR-003: Negative fusion-depth is rejected" {
    run "$GRAPH_RAG_SCRIPT" --query "test" --fusion-depth -1 --format json --mock-embedding --mock-graph --cwd "$WORKDIR" 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "invalid fusion-depth"
}

# @smoke
@test "HR-ERROR-004: Empty query is rejected" {
    run "$GRAPH_RAG_SCRIPT" --query "" --fusion-depth 1 --format json --mock-embedding --mock-graph --cwd "$WORKDIR" 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "query"
}

# @smoke
@test "HR-ERROR-005: Empty result set when no matches and no mocks" {
    local empty_dir="$WORKDIR/empty"
    mkdir -p "$empty_dir"

    GRAPH_UNAVAILABLE=1 run "$GRAPH_RAG_SCRIPT" --query "no_match_token_12345" --fusion-depth 0 --format json --cwd "$empty_dir" 2>&1

    assert_exit_success "$status"
    echo "$output" | jq -e '.candidates | length == 0' >/dev/null || fail "Expected empty candidates"
    echo "$output" | jq -e '.metadata.graph_available == false' >/dev/null || fail "Graph should be unavailable"
}
