#!/bin/bash
# DevBooks Ollama LLM Provider
# 版本: 1.0.0
# 用途: 实现本地 Ollama API 调用
#
# 支持模型:
#   - llama3 (默认)
#   - codellama
#   - mistral
#   - 其他 Ollama 支持的模型

# ==================== 配置 ====================

# API 配置
_OLLAMA_ENDPOINT="${LLM_ENDPOINT:-http://localhost:11434}"
_OLLAMA_MODEL="${LLM_MODEL:-llama3}"
_OLLAMA_TIMEOUT_SEC=$(( (${LLM_TIMEOUT_MS:-2000} + 999) / 1000 ))

# ==================== Mock 模式检查 ====================

_ollama_check_mock() {
  # Mock 响应
  if [[ -n "${LLM_MOCK_RESPONSE:-}" ]]; then
    # 模拟延迟
    if [[ -n "${LLM_MOCK_DELAY_MS:-}" ]]; then
      local delay_sec=$(( LLM_MOCK_DELAY_MS / 1000 ))
      [[ "$delay_sec" -gt 0 ]] && sleep "$delay_sec" 2>/dev/null || true
    fi

    # 模拟失败计数
    if [[ -n "${LLM_MOCK_FAIL_COUNT:-}" && "${LLM_MOCK_FAIL_COUNT}" -gt 0 ]]; then
      export LLM_MOCK_FAIL_COUNT=$((LLM_MOCK_FAIL_COUNT - 1))
      echo "mock failure" >&2
      return 1
    fi

    echo "$LLM_MOCK_RESPONSE"
    return 0
  fi

  return 2  # 非 Mock 模式
}

# ==================== Provider 接口实现 ====================

# 重排序接口
# 参数: $1 - 查询内容
# 参数: $2 - 候选 JSON 数组
# 返回: 排序后的 JSON 数组
_llm_provider_rerank() {
  local query="$1"
  local candidates="$2"

  # 检查 Mock 模式
  local mock_result
  mock_result=$(_ollama_check_mock)
  local mock_status=$?
  if [[ $mock_status -eq 0 ]]; then
    echo "$mock_result"
    return 0
  elif [[ $mock_status -eq 1 ]]; then
    return 1
  fi

  # 检查 Ollama 服务
  if ! _ollama_check_service; then
    echo "Ollama service not available at $_OLLAMA_ENDPOINT" >&2
    return 1
  fi

  # 构建候选列表文本
  local candidates_text=""
  local count
  count=$(echo "$candidates" | jq 'length')

  local i
  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates" | jq ".[$i]")
    local file_path content
    file_path=$(echo "$candidate" | jq -r '.file_path // .file // ""')
    content=$(echo "$candidate" | jq -r '.content // ""' | head -c 500)

    candidates_text="${candidates_text}
[$i] $file_path
$content
---"
  done

  # 构建 Prompt
  local prompt="Given the user query: \"$query\"

Please rank the following code candidates by relevance to the query. Return a JSON array with the ranked results.

Candidates:
$candidates_text

Return format (JSON only, no explanation):
[{\"index\": 0, \"score\": 9, \"reason\": \"...\"}, ...]

Important:
- Return ONLY valid JSON array, no other text
- Score range: 1-10 (10 = most relevant)
- Include all candidates in the ranking"

  # 调用 API
  local response
  response=$(_ollama_api_call "$prompt")
  local api_status=$?

  if [[ $api_status -ne 0 ]]; then
    echo "API call failed" >&2
    return 1
  fi

  # 解析响应，提取 JSON 数组
  local ranked
  ranked=$(echo "$response" | grep -oE '\[.*\]' | head -1)

  if [[ -z "$ranked" ]]; then
    echo "Failed to parse ranking response" >&2
    return 1
  fi

  # 验证 JSON 格式
  if ! echo "$ranked" | jq -e '.' &>/dev/null; then
    echo "Invalid JSON in response" >&2
    return 1
  fi

  echo "$ranked"
}

# LLM 调用接口
# 参数: $1 - prompt
# 返回: LLM 响应文本
_llm_provider_call() {
  local prompt="$1"

  # 检查 Mock 模式
  local mock_result
  mock_result=$(_ollama_check_mock)
  local mock_status=$?
  if [[ $mock_status -eq 0 ]]; then
    echo "$mock_result"
    return 0
  elif [[ $mock_status -eq 1 ]]; then
    return 1
  fi

  # 检查 Ollama 服务
  if ! _ollama_check_service; then
    echo "Ollama service not available at $_OLLAMA_ENDPOINT" >&2
    return 1
  fi

  # 调用 API
  _ollama_api_call "$prompt"
}

# 验证配置
_llm_provider_validate() {
  # 检查 Ollama 服务是否可用
  _ollama_check_service
}

# ==================== 内部函数 ====================

# 检查 Ollama 服务是否可用
_ollama_check_service() {
  if ! command -v curl &>/dev/null; then
    return 1
  fi

  curl -s --connect-timeout 2 "${_OLLAMA_ENDPOINT}/api/tags" &>/dev/null
}

# 调用 Ollama Generate API
# 参数: $1 - prompt
# 返回: 响应内容文本
_ollama_api_call() {
  local prompt="$1"

  # 检查 curl
  if ! command -v curl &>/dev/null; then
    echo "curl is required" >&2
    return 2
  fi

  # 检查 jq
  if ! command -v jq &>/dev/null; then
    echo "jq is required" >&2
    return 2
  fi

  # 构建请求体
  local request_body
  request_body=$(jq -n \
    --arg model "$_OLLAMA_MODEL" \
    --arg prompt "$prompt" \
    '{
      model: $model,
      prompt: $prompt,
      stream: false
    }' 2>/dev/null)

  # 发送请求
  local response
  response=$(timeout "$_OLLAMA_TIMEOUT_SEC" curl -s \
    -X POST "${_OLLAMA_ENDPOINT}/api/generate" \
    -H "Content-Type: application/json" \
    -d "$request_body" 2>/dev/null)

  local exit_code=$?
  if [[ $exit_code -eq 124 ]]; then
    echo "Request timeout" >&2
    return 124
  fi

  # 检查错误
  if echo "$response" | jq -e '.error' &>/dev/null; then
    local error_msg
    error_msg=$(echo "$response" | jq -r '.error // "Unknown error"')
    echo "API error: $error_msg" >&2
    return 1
  fi

  # 提取响应内容
  local content
  content=$(echo "$response" | jq -r '.response // empty' 2>/dev/null)

  if [[ -z "$content" ]]; then
    echo "Empty response from API" >&2
    return 1
  fi

  echo "$content"
}
