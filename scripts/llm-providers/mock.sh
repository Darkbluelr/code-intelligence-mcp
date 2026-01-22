#!/bin/bash
# DevBooks Mock LLM Provider
# 版本: 1.0.0
# 用途: 提供测试用的 Mock LLM Provider
#
# 环境变量:
#   LLM_MOCK_RESPONSE    - 自定义响应内容
#   LLM_MOCK_DELAY_MS    - 模拟延迟（毫秒）
#   LLM_MOCK_FAIL_COUNT  - 前 N 次调用返回失败

# ==================== Mock 行为控制 ====================

# 处理 Mock 模式逻辑
# 返回: 0=返回 Mock 响应, 1=模拟失败, 2=使用默认行为
_mock_handle_request() {
  # 模拟延迟
  if [[ -n "${LLM_MOCK_DELAY_MS:-}" ]]; then
    local delay_sec=$(( LLM_MOCK_DELAY_MS / 1000 ))
    local delay_ms=$(( LLM_MOCK_DELAY_MS % 1000 ))

    if [[ "$delay_sec" -gt 0 ]]; then
      sleep "$delay_sec" 2>/dev/null || true
    fi
    # 亚秒级延迟（如果支持）
    if [[ "$delay_ms" -gt 0 ]] && command -v perl &>/dev/null; then
      perl -e "select(undef,undef,undef,$delay_ms/1000)" 2>/dev/null || true
    fi
  fi

  # 模拟失败计数
  if [[ -n "${LLM_MOCK_FAIL_COUNT:-}" && "${LLM_MOCK_FAIL_COUNT}" -gt 0 ]]; then
    export LLM_MOCK_FAIL_COUNT=$((LLM_MOCK_FAIL_COUNT - 1))
    echo "mock failure (remaining: $LLM_MOCK_FAIL_COUNT)" >&2
    return 1
  fi

  # 返回自定义响应（如果设置）
  if [[ -n "${LLM_MOCK_RESPONSE:-}" ]]; then
    echo "$LLM_MOCK_RESPONSE"
    return 0
  fi

  # 使用默认行为
  return 2
}

# ==================== Provider 接口实现 ====================

# 重排序接口
# 参数: $1 - 查询内容
# 参数: $2 - 候选 JSON 数组
# 返回: 排序后的 JSON 数组
_llm_provider_rerank() {
  local query="$1"
  local candidates="$2"

  # 处理 Mock 逻辑
  local mock_result
  mock_result=$(_mock_handle_request)
  local mock_status=$?

  if [[ $mock_status -eq 0 ]]; then
    echo "$mock_result"
    return 0
  elif [[ $mock_status -eq 1 ]]; then
    return 1
  fi

  # 默认行为：按原始顺序返回，分配递减分数
  local count
  count=$(echo "$candidates" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    echo '[]'
    return 0
  fi

  # 生成默认排序结果
  local ranked='[]'
  local i
  for ((i=0; i<count; i++)); do
    local score=$((10 - i))
    [[ $score -lt 1 ]] && score=1

    local file_path
    file_path=$(echo "$candidates" | jq -r ".[$i].file_path // .[$i].file // \"file_$i\"")

    ranked=$(echo "$ranked" | jq \
      --argjson index "$i" \
      --argjson score "$score" \
      --arg reason "Mock ranking (position $i)" \
      '. + [{index: $index, score: $score, reason: $reason}]')
  done

  echo "$ranked"
}

# LLM 调用接口
# 参数: $1 - prompt
# 返回: LLM 响应文本
_llm_provider_call() {
  local prompt="$1"

  # 处理 Mock 逻辑
  local mock_result
  mock_result=$(_mock_handle_request)
  local mock_status=$?

  if [[ $mock_status -eq 0 ]]; then
    echo "$mock_result"
    return 0
  elif [[ $mock_status -eq 1 ]]; then
    return 1
  fi

  # 默认行为：返回简单的 Mock 响应
  local prompt_preview
  prompt_preview=$(echo "$prompt" | head -c 50)

  cat << EOF
This is a mock LLM response.

Your prompt was: "${prompt_preview}..."

Mock provider is active. To get real responses, configure:
- ANTHROPIC_API_KEY for Anthropic Claude
- OPENAI_API_KEY for OpenAI GPT
- Or run a local Ollama instance
EOF
}

# 验证配置
_llm_provider_validate() {
  # Mock provider 总是有效
  return 0
}

# ==================== Mock 辅助函数 ====================

# 设置 Mock 响应
# 参数: $1 - 响应内容
mock_set_response() {
  export LLM_MOCK_RESPONSE="$1"
}

# 设置 Mock 延迟
# 参数: $1 - 延迟毫秒数
mock_set_delay() {
  export LLM_MOCK_DELAY_MS="$1"
}

# 设置 Mock 失败次数
# 参数: $1 - 失败次数
mock_set_fail_count() {
  export LLM_MOCK_FAIL_COUNT="$1"
}

# 重置所有 Mock 设置
mock_reset() {
  unset LLM_MOCK_RESPONSE
  unset LLM_MOCK_DELAY_MS
  unset LLM_MOCK_FAIL_COUNT
}

# 生成 Mock 重排序响应
# 参数: $1 - 候选数量
# 返回: JSON 数组
mock_generate_ranking() {
  local count="${1:-3}"
  local ranked='[]'

  local i
  for ((i=0; i<count; i++)); do
    local score=$((10 - i))
    [[ $score -lt 1 ]] && score=1

    ranked=$(echo "$ranked" | jq \
      --argjson index "$i" \
      --argjson score "$score" \
      --arg reason "Generated mock ranking" \
      '. + [{index: $index, score: $score, reason: $reason}]')
  done

  echo "$ranked"
}
