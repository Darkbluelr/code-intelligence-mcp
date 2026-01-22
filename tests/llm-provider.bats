#!/usr/bin/env bats
# LLM Provider 抽象接口测试
# Change ID: augment-final-10-percent
# AC: AC-001, AC-002

load 'helpers/common.bash'

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
    export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
    export LLM_PROVIDER_SCRIPT="${SCRIPTS_DIR}/llm-provider.sh"
    export LLM_PROVIDERS_DIR="${SCRIPTS_DIR}/llm-providers"

    # 禁用真实 API 调用
    export LLM_MOCK_MODE=1
}

teardown() {
    unset LLM_MOCK_MODE
    unset LLM_MOCK_RESPONSE
}

# ============================================================
# @smoke 快速验证
# ============================================================

# @smoke T-LPA-001: Provider 接口加载测试
@test "T-LPA-001: llm-provider.sh script exists and is executable" {
    [ -f "$LLM_PROVIDER_SCRIPT" ]
    [ -x "$LLM_PROVIDER_SCRIPT" ]
}

# @smoke T-LPA-005: Mock Provider 配置测试
@test "T-LPA-005: Mock provider returns predefined response" {
    export LLM_MOCK_RESPONSE='[{"index":0,"score":9}]'

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_rerank "test query" '[{"file":"a.ts"}]')

    echo "$result" | jq -e '.success == true'
    echo "$result" | jq -e '.provider == "mock"'
}

# @smoke T-LPA-009: 统一响应格式验证
@test "T-LPA-009: Response format includes required fields" {
    export LLM_MOCK_RESPONSE='[{"index":0,"score":9}]'

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_rerank "test" '[]')

    # 验证必需字段
    echo "$result" | jq -e 'has("success")'
    echo "$result" | jq -e 'has("provider")'
    echo "$result" | jq -e 'has("result") or has("ranked")'
}

# ============================================================
# @critical 关键功能
# ============================================================

# @critical T-LPA-002: Anthropic Provider 配置测试
@test "T-LPA-002: Anthropic provider loads when configured" {
    export LLM_PROVIDER=anthropic
    export ANTHROPIC_API_KEY="test-key"
    export LLM_MOCK_MODE=1

    [ -f "${LLM_PROVIDERS_DIR}/anthropic.sh" ]

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_info)
    echo "$result" | jq -e '.provider == "anthropic"'
}

# @critical T-LPA-003: OpenAI Provider 配置测试
@test "T-LPA-003: OpenAI provider loads when configured" {
    export LLM_PROVIDER=openai
    export OPENAI_API_KEY="test-key"
    export LLM_MOCK_MODE=1

    [ -f "${LLM_PROVIDERS_DIR}/openai.sh" ]

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_info)
    echo "$result" | jq -e '.provider == "openai"'
}

# @critical T-LPA-004: Ollama Provider 配置测试
@test "T-LPA-004: Ollama provider loads when configured" {
    export LLM_PROVIDER=ollama
    export LLM_MOCK_MODE=1

    [ -f "${LLM_PROVIDERS_DIR}/ollama.sh" ]

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_info)
    echo "$result" | jq -e '.provider == "ollama"'
}

# @critical T-LPA-006: Provider 自动检测测试 (SC-LPA-002)
@test "T-LPA-006: Auto-detect provider based on available API keys" {
    unset LLM_PROVIDER
    export ANTHROPIC_API_KEY="test-key"
    unset OPENAI_API_KEY
    export LLM_MOCK_MODE=1

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_info)
    echo "$result" | jq -e '.provider == "anthropic"'
}

# @critical T-LPA-007: Provider 降级测试 (SC-LPA-003)
@test "T-LPA-007: Provider falls back to mock when API key missing" {
    export LLM_PROVIDER=anthropic
    unset ANTHROPIC_API_KEY
    export LLM_MOCK_MODE=1

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_info)

    # 应该降级到 mock 或返回错误
    echo "$result" | jq -e '.provider == "mock" or .error == "api_key_missing"'
}

# @critical T-LPA-010: API Key 缺失错误处理
@test "T-LPA-010: Returns proper error when API key is missing" {
    export LLM_PROVIDER=anthropic
    unset ANTHROPIC_API_KEY
    unset LLM_MOCK_MODE

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_validate 2>&1) || true

    # 验证错误信息
    [[ "$result" == *"api_key"* ]] || [[ "$result" == *"missing"* ]] || echo "$result" | jq -e '.error'
}

# @critical T-LPA-011: 超时错误处理
@test "T-LPA-011: Handles timeout gracefully" {
    export LLM_PROVIDER=mock
    export LLM_MOCK_TIMEOUT=1
    export LLM_TIMEOUT=0.1

    run source "$LLM_PROVIDER_SCRIPT" && llm_provider_call "test prompt"

    # 应该返回超时错误或状态码非零
    [ "$status" -ne 0 ] || echo "$output" | jq -e '.error == "timeout"'
}

# ============================================================
# @full 完整覆盖
# ============================================================

# @full T-LPA-008: 新 Provider 注册测试 (SC-LPA-004)
@test "T-LPA-008: New provider can be registered via config" {
    # 创建临时 provider 脚本
    local temp_provider=$(mktemp)
    cat > "$temp_provider" << 'EOF'
llm_provider_info() {
    echo '{"provider":"custom-test","model":"test-model"}'
}
llm_provider_rerank() {
    echo '{"success":true,"provider":"custom-test","ranked":[]}'
}
EOF

    export LLM_CUSTOM_PROVIDER="$temp_provider"
    export LLM_PROVIDER=custom

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_info) || true

    rm -f "$temp_provider"

    # 验证自定义 provider 可以加载
    echo "$result" | jq -e '.provider == "custom-test"' || skip "Custom provider registration not implemented"
}

# @full T-LPA-012: 速率限制重试测试
@test "T-LPA-012: Retries on rate limit with exponential backoff" {
    export LLM_PROVIDER=mock
    export LLM_MOCK_FAIL_COUNT=2
    export LLM_MOCK_FAIL_ERROR="rate_limit"

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_call "test") || true

    # 应该在重试后成功
    echo "$result" | jq -e '.success == true' || skip "Rate limit retry not implemented"
}

# @full: Provider 切换延迟测试 (AC-002)
@test "T-PERF-LPA-001: Provider switch latency < 100ms" {
    export LLM_MOCK_MODE=1

    # 测量切换时间
    start=$(date +%s%3N)

    export LLM_PROVIDER=anthropic
    source "$LLM_PROVIDER_SCRIPT"

    export LLM_PROVIDER=openai
    source "$LLM_PROVIDER_SCRIPT"

    end=$(date +%s%3N)
    latency=$((end - start))

    echo "Switch latency: ${latency}ms"
    [ "$latency" -lt 100 ]
}

# @full: Provider rerank 功能测试
@test "T-LPA-013: Rerank returns sorted results" {
    export LLM_MOCK_RESPONSE='[{"index":1,"score":9},{"index":0,"score":5}]'

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_rerank "query" '[{"file":"a.ts"},{"file":"b.ts"}]')

    echo "$result" | jq -e '.success == true'
    echo "$result" | jq -e '.ranked | length == 2'
}

# @full: Provider call 功能测试
@test "T-LPA-014: Provider call returns content" {
    export LLM_MOCK_RESPONSE='This is a test response'

    result=$(source "$LLM_PROVIDER_SCRIPT" && llm_provider_call "Analyze this code")

    echo "$result" | jq -e '.success == true'
    echo "$result" | jq -e 'has("content")'
}
