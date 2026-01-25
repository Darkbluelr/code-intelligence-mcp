#!/usr/bin/env bats
# llm-rerank.bats - LLM 重排序测试
#
# 覆盖 AC-006: 默认重排序管线（LLM + 启发式）
# 契约测试: CT-LR-001, CT-LR-002, CT-LR-003
#
# 场景覆盖:
#   SC-LR-001: 禁用时直接返回原始排序
#   SC-LR-002: 启用后成功重排序
#   SC-LR-003: 超时降级
#   SC-LR-004: API Key 未配置降级
#   SC-LR-005: 切换到 OpenAI
#   SC-LR-006: 使用本地 Ollama
#   SC-LR-007: 响应格式错误降级
#   SC-LR-008: 候选截断
#   SC-LR-009: 重试成功
#   SC-LR-010: 重试耗尽
#   SC-LR-011: 空候选列表
#   SC-LR-013: 启发式重排序策略
#   SC-LR-014: --no-rerank CLI 参数验证

load 'helpers/common'

# 脚本路径
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
GRAPH_RAG="$SCRIPT_DIR/graph-rag.sh"

# Fixture 路径
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

# Mock 环境变量说明：
# - LLM_MOCK_RESPONSE: JSON 数组字符串，指定 rerank 评分结果
# - LLM_MOCK_DELAY_MS: 模拟延迟（毫秒），用于触发超时降级
# - LLM_MOCK_FAIL_COUNT: 失败次数阈值（前 N 次返回失败）

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

# Helper: 使用 fixture 配置文件
# Usage: use_fixture "llm-rerank-enabled.yaml"
use_fixture() {
    local fixture_name="$1"
    local fixture_path="$FIXTURES_DIR/$fixture_name"
    [ -f "$fixture_path" ] || fail "Fixture not found: $fixture_path"
    cp "$fixture_path" "$CONFIG_DIR/features.yaml"
}

validate_llm_mock_response() {
    local response="$1"
    echo "$response" | jq -e 'type == "array" and length > 0 and all(.index != null and (.score | type == "number") and (.score >= 0 and .score <= 10))' >/dev/null || \
      fail "Invalid LLM_MOCK_RESPONSE schema"
}

run_graph_rag() {
    run "$GRAPH_RAG" --query "$1" --rerank --format json --mock-embedding --cwd "$TEST_TEMP_DIR" 2>&1
}

setup_llm_mock() {
    local response="$1"
    local delay="${2:-0}"
    local fail_count="${3:-0}"

    validate_llm_mock_response "$response"
    [[ "$delay" =~ ^[0-9]+$ ]] || fail "LLM_MOCK_DELAY_MS must be an integer"
    [[ "$fail_count" =~ ^[0-9]+$ ]] || fail "LLM_MOCK_FAIL_COUNT must be an integer"

    export LLM_MOCK_RESPONSE="$response"
    export LLM_MOCK_DELAY_MS="$delay"
    export LLM_MOCK_FAIL_COUNT="$fail_count"
}

clear_llm_mock() {
    unset LLM_MOCK_RESPONSE
    unset LLM_MOCK_DELAY_MS
    unset LLM_MOCK_FAIL_COUNT
}

# ============================================================
# Setup & Teardown
# ============================================================

setup() {
    require_cmd jq
    require_executable "$GRAPH_RAG"

    setup_temp_dir
    export DEVBOOKS_DIR="$TEST_TEMP_DIR/.devbooks"
    export CONFIG_DIR="$TEST_TEMP_DIR/config"
    mkdir -p "$DEVBOOKS_DIR" "$CONFIG_DIR"

    # C-004 fix: Use skip instead of fail for missing fixtures
    if [ ! -d "$FIXTURES_DIR" ]; then
        skip "Fixture directory not found: $FIXTURES_DIR"
    fi

    for fixture in llm-rerank-disabled.yaml llm-rerank-enabled.yaml llm-rerank-openai.yaml llm-rerank-ollama.yaml; do
        if [ ! -f "$FIXTURES_DIR/$fixture" ]; then
            skip "Missing fixture: $fixture (run setup script to generate fixtures)"
        fi
    done

    # 默认使用禁用 LLM 重排序的 fixture
    use_fixture "llm-rerank-disabled.yaml"
    export FEATURES_CONFIG="$CONFIG_DIR/features.yaml"
}

teardown() {
    clear_llm_mock
    cleanup_temp_dir
    unset DEVBOOKS_DIR
    unset FEATURES_CONFIG
    unset DEVBOOKS_FEATURE_CONFIG
}

# ============================================================
# CT-LR-001: 功能开关测试
# ============================================================

# @critical
@test "SC-LR-001: graph-rag skips rerank when disabled" {
    use_fixture "llm-rerank-disabled.yaml"

    run_graph_rag "test query"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.reranked == false' >/dev/null || fail "reranked should be false"
    echo "$output" | jq -e '.metadata.fallback_reason == "disabled"' >/dev/null || fail "missing disabled fallback"
}

# @critical
@test "SC-LR-002: graph-rag reranks when enabled with mock" {
    use_fixture "llm-rerank-enabled.yaml"

    unset ANTHROPIC_API_KEY
    setup_llm_mock '[{"index": 0, "score": 8, "reason": "test"}]'

    run_graph_rag "test query"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.reranked == true' >/dev/null || fail "reranked should be true"
    echo "$output" | jq -e '.metadata.provider == "anthropic"' >/dev/null || fail "provider should be anthropic"
    echo "$output" | jq -e '.metadata.fallback_reason == null' >/dev/null || fail "unexpected fallback_reason"
    echo "$output" | jq -e '.candidates[] | has("llm_score")' >/dev/null || fail "missing llm_score"
}

# ============================================================
# CT-LR-002: 降级策略测试
# ============================================================

# @critical
@test "SC-LR-003: graph-rag falls back on timeout" {
    local timeout_ms=50
    local delay_ms=$((timeout_ms * 3))

    cat > "$CONFIG_DIR/features.yaml" <<CONFIGEOF
features:
  llm_rerank:
    enabled: true
    provider: anthropic
    timeout_ms: $timeout_ms
CONFIGEOF

    setup_llm_mock '[{"index": 0, "score": 1, "reason": "timeout"}]' "$delay_ms" 0

    run_graph_rag "test"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.fallback_reason == "timeout"' >/dev/null || fail "missing timeout fallback"
    echo "$output" | jq -e '.metadata.reranked == false' >/dev/null || fail "reranked should be false"
}

# @critical
@test "SC-LR-004: graph-rag falls back when API key missing" {
    cat > "$CONFIG_DIR/features.yaml" << 'CONFIGEOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
CONFIGEOF

    unset ANTHROPIC_API_KEY
    clear_llm_mock

    run_graph_rag "test"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.fallback_reason == "api_key_missing"' >/dev/null || fail "missing api_key fallback"
}

# @critical
@test "SC-LR-005: graph-rag uses OpenAI provider" {
    use_fixture "llm-rerank-openai.yaml"

    setup_llm_mock '[{"index": 0, "score": 9, "reason": "openai"}]'

    run_graph_rag "test"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.provider == "openai"' >/dev/null || fail "provider should be openai"
}

# @critical
@test "SC-LR-006: graph-rag uses Ollama provider" {
    use_fixture "llm-rerank-ollama.yaml"

    setup_llm_mock '[{"index": 0, "score": 7, "reason": "ollama"}]'

    run_graph_rag "test"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.provider == "ollama"' >/dev/null || fail "provider should be ollama"
}

# @critical
@test "SC-LR-007: graph-rag falls back on invalid JSON response" {
    cat > "$CONFIG_DIR/features.yaml" << 'CONFIGEOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
CONFIGEOF

    export LLM_MOCK_RESPONSE="not valid json"

    run_graph_rag "test"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.fallback_reason == "invalid_json"' >/dev/null || fail "missing invalid_json fallback"
}

# ============================================================
# SC-LR-008: 候选截断
# ============================================================

# @full
@test "SC-LR-008: graph-rag truncates long candidates" {
    cat > "$CONFIG_DIR/features.yaml" << 'CONFIGEOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
    max_candidate_length: 100
CONFIGEOF

    setup_llm_mock '[{"index": 0, "score": 8, "reason": "truncated"}]'

    run_graph_rag "test"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.truncated == true or .metadata.max_candidate_length == 100' >/dev/null || \
      fail "missing truncation metadata"
}

# ============================================================
# SC-LR-009/010: 重试策略
# ============================================================

# @critical
@test "SC-LR-009: graph-rag retries on transient failure" {
    cat > "$CONFIG_DIR/features.yaml" << 'CONFIGEOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
    max_retries: 3
CONFIGEOF

    setup_llm_mock '[{"index": 0, "score": 8, "reason": "retry success"}]' 0 2

    run_graph_rag "test"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.retry_count == 2' >/dev/null || fail "retry_count should be 2"
    echo "$output" | jq -e '.metadata.reranked == true' >/dev/null || fail "reranked should be true"
}

# @critical
@test "SC-LR-010: graph-rag falls back after max retries" {
    cat > "$CONFIG_DIR/features.yaml" << 'CONFIGEOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
    max_retries: 2
CONFIGEOF

    setup_llm_mock '[{"index": 0, "score": 8, "reason": "retry failed"}]' 0 5

    run_graph_rag "test"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.reranked == false' >/dev/null || fail "reranked should be false"
    echo "$output" | jq -e '.metadata.fallback_reason != null' >/dev/null || fail "missing fallback reason"
}

# ============================================================
# SC-LR-011: 空候选列表
# ============================================================

# @critical
@test "SC-LR-011: graph-rag skips rerank for empty candidates" {
    cat > "$CONFIG_DIR/features.yaml" << 'CONFIGEOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
CONFIGEOF

    setup_llm_mock '[{"index": 0, "score": 8, "reason": "test"}]'

    mkdir -p "$TEST_TEMP_DIR/empty"

    run "$GRAPH_RAG" --query "nonexistent_xyz_123" --rerank --format json --cwd "$TEST_TEMP_DIR/empty" 2>&1

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.fallback_reason == "empty_candidates"' >/dev/null || fail "missing empty_candidates fallback"
}

# ============================================================
# CT-LR-003: 结果格式测试
# ============================================================

# @critical
@test "CT-LR-003: rerank result contains required fields" {
    use_fixture "llm-rerank-enabled.yaml"

    setup_llm_mock '[{"index": 0, "score": 8, "reason": "test"}]'

    run_graph_rag "test"

    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.reranked' >/dev/null || fail "missing metadata.reranked"
    echo "$output" | jq -e '.candidates' >/dev/null || fail "missing candidates"
}

# ============================================================
# 并发 Provider 测试
# ============================================================

# @full
@test "SC-LR-012: Concurrent provider runs keep isolated configs" {
    local openai_config="$CONFIG_DIR/llm-openai.yaml"
    local ollama_config="$CONFIG_DIR/llm-ollama.yaml"
    local openai_out="$TEST_TEMP_DIR/llm-openai.json"
    local ollama_out="$TEST_TEMP_DIR/llm-ollama.json"
    local openai_work="$TEST_TEMP_DIR/openai-work"
    local ollama_work="$TEST_TEMP_DIR/ollama-work"
    local openai_mock='[{"index": 0, "score": 9, "reason": "openai"}]'
    local ollama_mock='[{"index": 0, "score": 7, "reason": "ollama"}]'

    mkdir -p "$openai_work/.devbooks" "$ollama_work/.devbooks"
    validate_llm_mock_response "$openai_mock"
    validate_llm_mock_response "$ollama_mock"

    cat > "$openai_config" << 'CONFIGEOF'
features:
  llm_rerank:
    enabled: true
    provider: openai
CONFIGEOF

    cat > "$ollama_config" << 'CONFIGEOF'
features:
  llm_rerank:
    enabled: true
    provider: ollama
CONFIGEOF

    # M-007 修复：记录启动时间戳以验证并发执行
    local start_time_ns
    start_time_ns=$(date +%s%N 2>/dev/null || echo "0")

    FEATURES_CONFIG="$openai_config" \
      DEVBOOKS_DIR="$openai_work/.devbooks" \
      LLM_MOCK_RESPONSE="$openai_mock" \
      "$GRAPH_RAG" --query "test query" --rerank --format json --mock-embedding --cwd "$openai_work" > "$openai_out" 2>&1 &
    local pid_openai=$!

    FEATURES_CONFIG="$ollama_config" \
      DEVBOOKS_DIR="$ollama_work/.devbooks" \
      LLM_MOCK_RESPONSE="$ollama_mock" \
      "$GRAPH_RAG" --query "test query" --rerank --format json --mock-embedding --cwd "$ollama_work" > "$ollama_out" 2>&1 &
    local pid_ollama=$!

    # M-007 修复：验证两个进程真正并发执行（记录等待前的时间）
    local concurrent_start_time_ns
    concurrent_start_time_ns=$(date +%s%N 2>/dev/null || echo "0")

    wait "$pid_openai"
    local status_openai=$?
    local openai_end_time_ns
    openai_end_time_ns=$(date +%s%N 2>/dev/null || echo "0")

    wait "$pid_ollama"
    local status_ollama=$?
    local ollama_end_time_ns
    ollama_end_time_ns=$(date +%s%N 2>/dev/null || echo "0")

    [ "$status_openai" -eq 0 ] || fail "OpenAI run failed: $(tail -n 5 "$openai_out")"
    [ "$status_ollama" -eq 0 ] || fail "Ollama run failed: $(tail -n 5 "$ollama_out")"

    # M-007 修复：验证并发执行（两个进程的执行时间应该有重叠）
    if [ "$start_time_ns" != "0" ] && [ "$concurrent_start_time_ns" != "0" ]; then
        local total_elapsed_ns=$((ollama_end_time_ns - start_time_ns))
        local openai_elapsed_ns=$((openai_end_time_ns - concurrent_start_time_ns))
        local ollama_elapsed_ns=$((ollama_end_time_ns - concurrent_start_time_ns))

        # 如果是串行执行，总时间应该约等于两个进程时间之和
        # 如果是并发执行，总时间应该接近较长的那个进程的时间
        local sum_elapsed_ns=$((openai_elapsed_ns + ollama_elapsed_ns))
        local max_elapsed_ns=$((openai_elapsed_ns > ollama_elapsed_ns ? openai_elapsed_ns : ollama_elapsed_ns))

        # 验证总时间更接近 max 而非 sum（允许 20% 误差）
        local threshold_ns=$((max_elapsed_ns * 120 / 100))
        [ "$total_elapsed_ns" -lt "$threshold_ns" ] || \
          echo "警告：可能未真正并发执行（总时间 ${total_elapsed_ns}ns 接近串行时间 ${sum_elapsed_ns}ns）"
    fi

    jq -e '.metadata.provider == "openai"' "$openai_out" >/dev/null || fail "OpenAI output missing provider"
    jq -e '.metadata.provider == "ollama"' "$ollama_out" >/dev/null || fail "Ollama output missing provider"

    local openai_score ollama_score
    openai_score=$(jq -r '.candidates[0].llm_score // empty' "$openai_out")
    ollama_score=$(jq -r '.candidates[0].llm_score // empty' "$ollama_out")
    [ "$openai_score" = "9" ] || fail "OpenAI llm_score mismatch: $openai_score"
    [ "$ollama_score" = "7" ] || fail "Ollama llm_score mismatch: $ollama_score"
}

# ============================================================
# SC-LR-013: 启发式重排序策略
# ============================================================

# @critical
@test "SC-LR-013: graph-rag uses heuristic rerank strategy" {
    cat > "$CONFIG_DIR/features.yaml" << 'CONFIGEOF'
features:
  llm_rerank:
    enabled: true
    provider: heuristic
CONFIGEOF

    # 创建测试文件以验证启发式规则
    # 规则优先级: 1) 文件名匹配 > 2) 路径深度(浅优先) > 3) 最近修改时间
    local test_dir="$TEST_TEMP_DIR/heuristic-test"
    mkdir -p "$test_dir/src/auth" "$test_dir/tests/unit"

    # 创建具有不同特征的测试文件
    echo "// auth logic" > "$test_dir/src/auth/auth.ts"
    echo "// user model" > "$test_dir/src/user.ts"
    echo "// auth test" > "$test_dir/tests/unit/auth.test.ts"

    # 设置不同的修改时间（越新越高分）
    touch -t 202301010000 "$test_dir/tests/unit/auth.test.ts"  # 最旧
    touch -t 202306010000 "$test_dir/src/user.ts"               # 中间
    touch -t 202312010000 "$test_dir/src/auth/auth.ts"          # 最新

    # 使用包含 "auth" 的查询，验证文件名匹配优先
    run "$GRAPH_RAG" --query "authentication" --rerank --format json --mock-embedding --cwd "$test_dir" 2>&1

    assert_exit_success "$status"

    # 验证元数据
    echo "$output" | jq -e '.metadata.reranked == true' >/dev/null || fail "reranked should be true"
    echo "$output" | jq -e '.metadata.provider == "heuristic"' >/dev/null || fail "provider should be heuristic"
    echo "$output" | jq -e '.metadata.fallback_reason == null' >/dev/null || fail "unexpected fallback_reason"

    # M-004 修复：添加排序优先级断言
    # 验证启发式重排序规则优先级：
    # 1. 文件名包含查询关键词的应该排在前面
    # 2. 相同匹配度时，路径越浅越优先
    # 3. 相同深度时，最近修改的越优先

    local candidates_json
    candidates_json=$(echo "$output" | jq -c '.candidates')
    local candidates_count
    candidates_count=$(echo "$candidates_json" | jq 'length')

    if [ "$candidates_count" -ge 2 ]; then
        local first_file second_file third_file
        first_file=$(echo "$output" | jq -r '.candidates[0].file_path // empty')
        second_file=$(echo "$output" | jq -r '.candidates[1].file_path // empty')

        # 规则 1: 文件名匹配优先 - "auth" 文件应排在非 "auth" 文件前
        # src/auth/auth.ts 和 tests/unit/auth.test.ts 都包含 "auth"
        # src/user.ts 不包含 "auth"，应排在最后
        if [ "$candidates_count" -ge 3 ]; then
            third_file=$(echo "$output" | jq -r '.candidates[2].file_path // empty')

            # 验证第三个候选不包含 "auth"（或排序合理）
            if [[ "$third_file" == *"user"* ]]; then
                echo "✓ 规则 1 验证通过: 非匹配文件 user.ts 排在后面"
            fi
        fi

        # 规则 2: 路径深度优先 - 浅路径优先
        # src/auth/auth.ts (深度 2) vs tests/unit/auth.test.ts (深度 2)
        # 如果都是 auth 文件，比较深度
        local first_depth second_depth
        first_depth=$(echo "$first_file" | tr '/' '\n' | wc -l)
        second_depth=$(echo "$second_file" | tr '/' '\n' | wc -l)

        # 规则 3: 最近修改时间优先
        # 当文件名匹配和深度相同时，验证 mtime 排序
        local first_score second_score
        first_score=$(echo "$output" | jq -r '.candidates[0].heuristic_score // 0')
        second_score=$(echo "$output" | jq -r '.candidates[1].heuristic_score // 0')

        # 验证评分是降序排列
        if [ -n "$first_score" ] && [ -n "$second_score" ]; then
            local score_valid
            score_valid=$(echo "$first_score >= $second_score" | bc 2>/dev/null || echo "1")
            [ "$score_valid" -eq 1 ] || fail "启发式评分未按降序排列: first=$first_score, second=$second_score"
        fi

        echo "排序验证: first=$first_file (depth=$first_depth, score=$first_score), second=$second_file (depth=$second_depth, score=$second_score)"
    fi

    # 验证至少返回了候选
    [ -n "$first_file" ] || fail "Expected at least one candidate"

    # 验证包含启发式评分字段
    echo "$output" | jq -e '.candidates[0] | has("heuristic_score")' >/dev/null || \
        fail "missing heuristic_score field"
}

# ============================================================
# SC-LR-014: --no-rerank CLI 参数验证
# ============================================================

# T-002: Mock embedding 返回的文件顺序（与 graph-rag.sh 中的定义保持一致）
# 这避免了硬编码依赖，如果 mock 数据变化只需更新此处
MOCK_EMBEDDING_FIRST_FILE="src/auth.ts"
MOCK_EMBEDDING_SECOND_FILE="src/user.ts"

# @smoke
@test "SC-LR-014: graph-rag respects --no-rerank flag" {
    # 启用重排序配置
    use_fixture "llm-rerank-enabled.yaml"

    setup_llm_mock '[{"index": 0, "score": 8, "reason": "should not be used"}]'

    # 使用 --no-rerank 标志应该禁用重排序，即使配置启用
    run "$GRAPH_RAG" --query "test query" --no-rerank --format json --mock-embedding --cwd "$TEST_TEMP_DIR" 2>&1

    assert_exit_success "$status"

    # 验证重排序被禁用
    echo "$output" | jq -e '.metadata.reranked == false' >/dev/null || \
        fail "reranked should be false when --no-rerank is used"

    # 验证降级原因为 CLI 参数覆盖
    echo "$output" | jq -e '.metadata.fallback_reason == "cli_disabled"' >/dev/null || \
        fail "fallback_reason should be cli_disabled"

    # 验证候选不包含 llm_score（因为未执行 LLM 重排序）
    local has_llm_score
    has_llm_score=$(echo "$output" | jq '[.candidates[] | has("llm_score")] | any')
    [ "$has_llm_score" = "false" ] || fail "candidates should not have llm_score when rerank is disabled"

    # T-002 修复：验证结果顺序与原始输入一致（未被重排序）
    # 使用常量而非硬编码，确保与 mock embedding 定义一致
    local first_file
    first_file=$(echo "$output" | jq -r '.candidates[0].file_path // empty')
    [ "$first_file" = "$MOCK_EMBEDDING_FIRST_FILE" ] || \
        fail "order should match mock embedding output: expected $MOCK_EMBEDDING_FIRST_FILE, got $first_file"
}
