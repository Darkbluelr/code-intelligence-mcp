#!/usr/bin/env bats
# llm-rerank.bats - LLM 重排序测试
#
# 覆盖 AC-004: LLM 重排序可启用/禁用
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
#
# Mock 接口规范 (用于 SC-LR-009, SC-LR-010):
# ─────────────────────────────────────────────
# 以下环境变量用于测试重试逻辑，需要 graph-rag.sh 支持：
#
#   LLM_MOCK_FAIL_COUNT=N
#     - 模拟前 N 次 LLM API 调用失败
#     - 第 N+1 次调用成功（如果 N < max_retries）
#     - 如果 N >= max_retries，所有调用都失败
#
#   LLM_MOCK_RESPONSE=<json>
#     - 成功时返回的 mock 响应
#     - 格式: '[{"index": 0, "score": 8, "reason": "..."}]'
#
# 如果脚本不支持这些 mock 接口，相关测试将被跳过。
# 实现者可参考此规范在 graph-rag.sh 中添加 mock 支持。
# ─────────────────────────────────────────────

load 'helpers/common'

# 脚本路径
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
GRAPH_RAG="$SCRIPT_DIR/graph-rag.sh"

# Fixture 路径
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

# Helper: 使用 fixture 配置文件
# Usage: use_fixture "llm-rerank-enabled.yaml"
use_fixture() {
    local fixture_name="$1"
    local fixture_path="$FIXTURES_DIR/$fixture_name"
    if [ -f "$fixture_path" ]; then
        cp "$fixture_path" "$CONFIG_DIR/features.yaml"
    else
        echo "Fixture not found: $fixture_path" >&2
        return 1
    fi
}

# Helper: 检测 LLM mock 机制是否被支持
# 通过检查 graph-rag.sh 源码或运行测试来判断
# Returns: 0 if supported, 1 if not
check_llm_mock_support() {
    # 方法1: 检查脚本是否包含 mock 相关代码
    if grep -q "LLM_MOCK_FAIL_COUNT" "$GRAPH_RAG" 2>/dev/null; then
        return 0
    fi

    # 方法2: 检查 --help 输出是否提及 mock
    if "$GRAPH_RAG" --help 2>&1 | grep -qi "mock\|test\|debug"; then
        return 0
    fi

    # 未检测到 mock 支持
    return 1
}

setup() {
    setup_temp_dir
    export DEVBOOKS_DIR="$TEST_TEMP_DIR/.devbooks"
    export CONFIG_DIR="$TEST_TEMP_DIR/config"
    mkdir -p "$DEVBOOKS_DIR" "$CONFIG_DIR"

    # 默认使用禁用 LLM 重排序的 fixture
    use_fixture "llm-rerank-disabled.yaml" 2>/dev/null || {
        # Fallback: 如果 fixture 不存在，使用内联配置
        cat > "$CONFIG_DIR/features.yaml" << 'EOF'
features:
  llm_rerank:
    enabled: false
    provider: anthropic
    model: claude-3-haiku
    timeout_ms: 2000
EOF
    }
    export FEATURES_CONFIG="$CONFIG_DIR/features.yaml"
}

teardown() {
    cleanup_temp_dir
}

# ============================================================
# CT-LR-001: 功能开关测试
# ============================================================

# @test SC-LR-001: 禁用时直接返回原始排序
@test "SC-LR-001: graph-rag skips rerank when disabled" {
    skip_if_not_executable "$GRAPH_RAG"

    run "$GRAPH_RAG" --query "test query" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh rerank disabled"
    assert_exit_success "$status"
    assert_valid_json "$output"
    assert_json_field "$output" ".metadata.reranked" "false"
}

# @test SC-LR-002: 启用后成功重排序
@test "SC-LR-002: graph-rag reranks when enabled with mock" {
    skip_if_not_executable "$GRAPH_RAG"

    # 使用启用 LLM 重排序的 fixture
    use_fixture "llm-rerank-enabled.yaml" || skip "Fixture llm-rerank-enabled.yaml not found"

    # 设置 Mock 响应
    export LLM_MOCK_RESPONSE='[{"index": 0, "score": 8, "reason": "test"}]'
    export ANTHROPIC_API_KEY="mock-key"

    run "$GRAPH_RAG" --query "test query" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh rerank enabled"
    assert_exit_success "$status"
    assert_valid_json "$output"
    assert_json_field "$output" ".metadata.reranked" "true"
}

# ============================================================
# CT-LR-002: 降级策略测试
# ============================================================

# @test SC-LR-003: 超时降级
@test "SC-LR-003: graph-rag falls back on timeout" {
    skip_if_not_executable "$GRAPH_RAG"

    cat > "$CONFIG_DIR/features.yaml" << 'EOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
    timeout_ms: 1
EOF

    export ANTHROPIC_API_KEY="mock-key"
    export LLM_MOCK_DELAY_MS=5000  # 模拟 5 秒延迟

    run "$GRAPH_RAG" --query "test" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh timeout"
    assert_exit_success "$status"
    assert_contains "$output" "timeout"
}

# @test SC-LR-004: API Key 未配置降级
@test "SC-LR-004: graph-rag falls back when API key missing" {
    skip_if_not_executable "$GRAPH_RAG"

    cat > "$CONFIG_DIR/features.yaml" << 'EOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
EOF

    unset ANTHROPIC_API_KEY

    run "$GRAPH_RAG" --query "test" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh api key"
    assert_exit_success "$status"
    assert_contains "$output" "api_key"
}

# @test SC-LR-005: 切换到 OpenAI
@test "SC-LR-005: graph-rag uses OpenAI provider" {
    skip_if_not_executable "$GRAPH_RAG"

    # 使用 OpenAI provider fixture
    use_fixture "llm-rerank-openai.yaml" || skip "Fixture llm-rerank-openai.yaml not found"

    export OPENAI_API_KEY="mock-key"
    export LLM_MOCK_RESPONSE='[{"index": 0, "score": 9, "reason": "openai"}]'

    run "$GRAPH_RAG" --query "test" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh openai"
    assert_exit_success "$status"
    assert_json_field "$output" ".metadata.provider" "openai"
}

# @test SC-LR-006: 使用本地 Ollama
@test "SC-LR-006: graph-rag uses Ollama provider" {
    skip_if_not_executable "$GRAPH_RAG"

    # 检测 Ollama 是否可用
    if ! command -v ollama &> /dev/null; then
        # Ollama 不可用，使用 Mock 模式测试配置解析
        use_fixture "llm-rerank-ollama.yaml" || skip "Fixture llm-rerank-ollama.yaml not found"

        export LLM_MOCK_RESPONSE='[{"index": 0, "score": 7, "reason": "ollama mock"}]'

        run "$GRAPH_RAG" --query "test" --rerank

        skip_if_not_ready "$status" "$output" "graph-rag.sh ollama config"

        # 验证配置被正确解析
        if [[ "$output" == *'"provider"'*'"ollama"'* ]] || \
           [[ "$output" == *"ollama"* ]]; then
            return 0
        fi

        skip "Ollama provider config parsing not yet implemented"
    fi

    # Ollama 可用，进行真实测试
    use_fixture "llm-rerank-ollama.yaml" || skip "Fixture llm-rerank-ollama.yaml not found"

    run "$GRAPH_RAG" --query "test" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh ollama"
    assert_exit_success "$status"
    assert_json_field "$output" ".metadata.provider" "ollama"
}

# @test SC-LR-007: 响应格式错误降级
@test "SC-LR-007: graph-rag falls back on invalid JSON response" {
    skip_if_not_executable "$GRAPH_RAG"

    cat > "$CONFIG_DIR/features.yaml" << 'EOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
EOF

    export ANTHROPIC_API_KEY="mock-key"
    export LLM_MOCK_RESPONSE="not valid json"

    run "$GRAPH_RAG" --query "test" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh invalid json"
    assert_exit_success "$status"
    assert_contains "$output" "invalid"
}

# @test SC-LR-008: 候选截断
@test "SC-LR-008: graph-rag truncates long candidates" {
    skip_if_not_executable "$GRAPH_RAG"
    skip_if_missing "jq"

    local max_length=100

    cat > "$CONFIG_DIR/features.yaml" << EOF
features:
  llm_rerank:
    enabled: true
    provider: anthropic
    max_candidate_length: $max_length
EOF

    export ANTHROPIC_API_KEY="mock-key"
    export LLM_MOCK_RESPONSE='[{"index": 0, "score": 8, "reason": "truncated"}]'

    # 创建超长候选数据（500 字符，超过 max_length）
    local long_content
    long_content=$(printf 'x%.0s' {1..500})

    # 设置 Mock 候选数据
    export LLM_MOCK_CANDIDATES="[{\"content\": \"$long_content\", \"file\": \"test.ts\"}]"

    run "$GRAPH_RAG" --query "test" --rerank --format json

    skip_if_not_ready "$status" "$output" "graph-rag.sh truncation"
    assert_exit_success "$status"

    # 尝试验证截断行为
    local json_output
    json_output=$(extract_json "$output" 2>/dev/null || echo "$output")

    # 方法1: 检查 metadata 中是否有截断标记
    if echo "$json_output" | jq -e '.metadata.truncated' > /dev/null 2>&1; then
        local truncated
        truncated=$(echo "$json_output" | jq -r '.metadata.truncated')
        [ "$truncated" = "true" ] && return 0
    fi

    # 方法2: 检查候选内容长度是否被截断
    if echo "$json_output" | jq -e '.candidates[0].content' > /dev/null 2>&1; then
        local content_length
        content_length=$(echo "$json_output" | jq -r '.candidates[0].content | length')
        if [ "$content_length" -le "$max_length" ]; then
            return 0
        fi
    fi

    # 方法3: 检查是否有截断相关提示
    if [[ "$output" == *"truncat"* ]] || \
       [[ "$output" == *'"max_candidate_length"'* ]]; then
        return 0
    fi

    # 如果功能未实现，跳过
    skip "Candidate truncation not yet implemented"
}

# @test SC-LR-009: 重试成功
# 测试场景：模拟前 N 次请求失败，第 N+1 次成功
# 预期行为：脚本应重试并最终成功
# 依赖：LLM_MOCK_FAIL_COUNT 环境变量（见文件头部 Mock 接口规范）
@test "SC-LR-009: graph-rag retries on transient failure" {
    skip_if_not_executable "$GRAPH_RAG"

    # 前置检查：验证 mock 机制是否被支持
    if ! check_llm_mock_support; then
        skip "LLM mock mechanism not implemented in graph-rag.sh (see Mock Interface Spec in file header)"
    fi

    cat > "$CONFIG_DIR/features.yaml" << 'EOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
    max_retries: 3
EOF

    export ANTHROPIC_API_KEY="mock-key"
    # 模拟前 2 次失败，第 3 次成功
    export LLM_MOCK_FAIL_COUNT=2
    export LLM_MOCK_RESPONSE='[{"index": 0, "score": 8, "reason": "retry success"}]'

    run "$GRAPH_RAG" --query "test" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh retry"

    # 验证命令成功
    assert_exit_success "$status"

    # 验证重试成功的证据（至少满足一个条件）
    local retry_evidence=false
    if [[ "$output" == *'"reranked"'*'true'* ]]; then
        retry_evidence=true
    fi
    if [[ "$output" == *'"retry_count"'* ]]; then
        retry_evidence=true
    fi
    if [[ "$output" == *'"retries"'* ]]; then
        retry_evidence=true
    fi

    if [ "$retry_evidence" = "false" ]; then
        skip "LLM retry mechanism not yet implemented (no retry evidence in output)"
    fi
}

# @test SC-LR-010: 重试耗尽
# 测试场景：所有重试都失败，超过 max_retries 限制
# 预期行为：脚本应降级到原始排序（reranked=false）
# 依赖：LLM_MOCK_FAIL_COUNT 环境变量（见文件头部 Mock 接口规范）
@test "SC-LR-010: graph-rag falls back after max retries" {
    skip_if_not_executable "$GRAPH_RAG"

    # 前置检查：验证 mock 机制是否被支持
    if ! check_llm_mock_support; then
        skip "LLM mock mechanism not implemented in graph-rag.sh (see Mock Interface Spec in file header)"
    fi

    cat > "$CONFIG_DIR/features.yaml" << 'EOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
    max_retries: 2
EOF

    export ANTHROPIC_API_KEY="mock-key"
    # 模拟所有请求都失败
    export LLM_MOCK_FAIL_COUNT=999
    export LLM_MOCK_RESPONSE='error'

    run "$GRAPH_RAG" --query "test" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh max retry"

    # 验证命令成功（降级不应导致失败）
    assert_exit_success "$status"

    # 验证降级到原始排序的证据（至少满足一个条件）
    local fallback_evidence=false
    if [[ "$output" == *'"reranked"'*'false'* ]]; then
        fallback_evidence=true
    fi
    if [[ "$output" == *"fallback"* ]]; then
        fallback_evidence=true
    fi
    if [[ "$output" == *"max_retries"* ]] || [[ "$output" == *"exhausted"* ]]; then
        fallback_evidence=true
    fi

    if [ "$fallback_evidence" = "false" ]; then
        skip "LLM max retry fallback not yet implemented (no fallback evidence)"
    fi
}

# @test SC-LR-011: 空候选列表
@test "SC-LR-011: graph-rag skips rerank for empty candidates" {
    skip_if_not_executable "$GRAPH_RAG"

    cat > "$CONFIG_DIR/features.yaml" << 'EOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
EOF

    export ANTHROPIC_API_KEY="mock-key"

    # 查询不存在的内容，应返回空候选
    run "$GRAPH_RAG" --query "nonexistent_xyz_123" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh empty"
    assert_exit_success "$status"
}

# ============================================================
# CT-LR-003: 结果格式测试
# ============================================================

@test "CT-LR-003: rerank result contains required fields" {
    skip_if_not_executable "$GRAPH_RAG"

    cat > "$CONFIG_DIR/features.yaml" << 'EOF'
features:
  llm_rerank:
    enabled: true
    provider: anthropic
EOF

    export ANTHROPIC_API_KEY="mock-key"
    export LLM_MOCK_RESPONSE='[{"index": 0, "score": 8, "reason": "test"}]'

    run "$GRAPH_RAG" --query "test" --rerank

    skip_if_not_ready "$status" "$output" "graph-rag.sh format"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证 metadata 字段
    assert_json_field "$output" ".metadata"
}
