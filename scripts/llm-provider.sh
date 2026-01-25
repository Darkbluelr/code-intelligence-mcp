#!/bin/bash
# DevBooks LLM Provider 抽象层
# 版本: 1.0.0
# 用途: 提供可插拔的 LLM Provider 接口，支持 Anthropic/OpenAI/Ollama/Mock
#
# 验收标准:
#   AC-001: 支持 Anthropic/OpenAI/Ollama/Mock 四种 Provider
#   AC-002: Provider 切换无需修改调用代码，切换延迟 <100ms
#
# 使用方式:
#   source scripts/llm-provider.sh
#   llm_load_provider "anthropic"  # 或 openai/ollama/mock
#   llm_rerank "查询" '[{"file":"a.ts","content":"..."}]'
#   llm_call "请分析这段代码..."

set -euo pipefail

# ==================== 脚本初始化 ====================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享函数库
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
  source "$SCRIPT_DIR/common.sh"
fi

# 设置日志前缀
: "${LOG_PREFIX:=LLMProvider}"

# ==================== 全局状态 ====================

# 当前加载的 Provider
_LLM_CURRENT_PROVIDER=""
_LLM_PROVIDER_SCRIPT=""
_LLM_PROVIDER_LOADED=false

# Provider 目录
LLM_PROVIDERS_DIR="${SCRIPT_DIR}/llm-providers"

# Provider 注册表配置文件
LLM_PROVIDERS_CONFIG="${LLM_PROVIDERS_CONFIG:-$(dirname "$SCRIPT_DIR")/config/llm-providers.yaml}"

# 默认配置
LLM_DEFAULT_PROVIDER="${LLM_DEFAULT_PROVIDER:-}"
LLM_DEFAULT_MODEL="${LLM_DEFAULT_MODEL:-}"
LLM_TIMEOUT_MS="${LLM_TIMEOUT_MS:-2000}"

# ==================== Provider 注册表解析 ====================

# 从配置文件读取 Provider 配置
# 参数: $1 - Provider 名称
# 参数: $2 - 配置键 (script/env_key/default_model/endpoint)
# 返回: 配置值
_llm_get_provider_config() {
  local provider="$1"
  local key="$2"
  local config_file="${LLM_PROVIDERS_CONFIG}"

  if [[ ! -f "$config_file" ]]; then
    # 返回内置默认值
    case "$provider" in
      anthropic)
        case "$key" in
          script) echo "anthropic.sh" ;;
          env_key) echo "ANTHROPIC_API_KEY" ;;
          default_model) echo "claude-3-haiku-20240307" ;;
          endpoint) echo "https://api.anthropic.com/v1" ;;
        esac
        ;;
      openai)
        case "$key" in
          script) echo "openai.sh" ;;
          env_key) echo "OPENAI_API_KEY" ;;
          default_model) echo "gpt-4o-mini" ;;
          endpoint) echo "https://api.openai.com/v1" ;;
        esac
        ;;
      ollama)
        case "$key" in
          script) echo "ollama.sh" ;;
          env_key) echo "" ;;
          default_model) echo "llama3" ;;
          endpoint) echo "http://localhost:11434" ;;
        esac
        ;;
      mock)
        case "$key" in
          script) echo "mock.sh" ;;
          env_key) echo "" ;;
          default_model) echo "mock" ;;
          endpoint) echo "" ;;
        esac
        ;;
    esac
    return
  fi

  # 解析 YAML 配置（简单解析）
  awk -v provider="$provider" -v key="$key" '
    BEGIN { in_providers = 0; in_target = 0 }
    /^providers:/ { in_providers = 1; next }
    /^[a-zA-Z]/ && !/^providers:/ { in_providers = 0; in_target = 0 }
    in_providers && $0 ~ "^[[:space:]][[:space:]]" provider ":" { in_target = 1; next }
    in_providers && /^[[:space:]][[:space:]][a-zA-Z]/ && in_target { in_target = 0 }
    in_target && $0 ~ key {
      sub(/^[^:]+:[[:space:]]*/, "")
      gsub(/[[:space:]]*#.*$/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
  ' "$config_file" 2>/dev/null
}

# 列出所有可用的 Provider
# 返回: Provider 名称列表（每行一个）
llm_list_providers() {
  local config_file="${LLM_PROVIDERS_CONFIG}"

  if [[ -f "$config_file" ]]; then
    awk '
      BEGIN { in_providers = 0 }
      /^providers:/ { in_providers = 1; next }
      /^[a-zA-Z]/ && !/^providers:/ { in_providers = 0 }
      in_providers && /^[[:space:]][[:space:]][a-zA-Z_-]+:/ {
        gsub(/^[[:space:]]+/, "")
        gsub(/:.*/, "")
        print
      }
    ' "$config_file" 2>/dev/null
  else
    # 返回内置 Provider
    echo "anthropic"
    echo "openai"
    echo "ollama"
    echo "mock"
  fi
}

# ==================== Provider 加载 ====================

# 加载指定的 LLM Provider
# 参数: $1 - Provider 名称 (anthropic/openai/ollama/mock)
# 返回: 0=成功, 1=失败
llm_load_provider() {
  local provider="${1:-}"

  # 如果未指定 Provider，自动检测
  if [[ -z "$provider" ]]; then
    provider=$(_llm_auto_detect_provider)
  fi

  if [[ -z "$provider" ]]; then
    log_error "未指定 Provider 且自动检测失败"
    return 1
  fi

  # 检查是否需要降级到 mock（API key 缺失且启用了 mock 模式）
  if [[ -n "${LLM_MOCK_MODE:-}" ]]; then
    local env_key
    env_key=$(_llm_get_provider_config "$provider" "env_key")
    # 只有当 env_key 非空且不是 "null" 时才检查 API key
    if [[ -n "$env_key" ]] && [[ "$env_key" != "null" ]] && [[ -z "${!env_key:-}" ]]; then
      # API key 缺失，降级到 mock
      provider="mock"
    fi
  fi

  # 获取 Provider 脚本路径
  local script
  script=$(_llm_get_provider_config "$provider" "script")

  if [[ -z "$script" ]]; then
    log_error "未知的 Provider: $provider"
    return 1
  fi

  local script_path="${LLM_PROVIDERS_DIR}/${script}"

  if [[ ! -f "$script_path" ]]; then
    log_error "Provider 脚本不存在: $script_path"
    return 1
  fi

  # 加载 Provider 脚本
  # shellcheck disable=SC1090
  source "$script_path"

  _LLM_CURRENT_PROVIDER="$provider"
  _LLM_PROVIDER_SCRIPT="$script_path"
  _LLM_PROVIDER_LOADED=true

  log_info "已加载 Provider: $provider"
  return 0
}

# 自动检测可用的 Provider
# 按优先级: 配置指定 > Anthropic > OpenAI > Ollama > Mock
_llm_auto_detect_provider() {
  # 1. 检查配置文件指定（支持两种变量名）
  if [[ -n "${LLM_PROVIDER:-}" ]]; then
    echo "$LLM_PROVIDER"
    return
  fi
  if [[ -n "${LLM_DEFAULT_PROVIDER:-}" ]]; then
    echo "$LLM_DEFAULT_PROVIDER"
    return
  fi

  # 2. 检查 Mock 响应环境变量（仅此变量触发 mock provider）
  if [[ -n "${LLM_MOCK_RESPONSE:-}" ]]; then
    echo "mock"
    return
  fi

  # 3. 检查 Anthropic API Key
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "anthropic"
    return
  fi

  # 4. 检查 OpenAI API Key
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    echo "openai"
    return
  fi

  # 5. 检查 Ollama 服务
  local ollama_endpoint
  ollama_endpoint=$(_llm_get_provider_config "ollama" "endpoint")
  ollama_endpoint="${ollama_endpoint:-http://localhost:11434}"
  if command -v curl &>/dev/null; then
    if curl -s --connect-timeout 1 "$ollama_endpoint/api/tags" &>/dev/null; then
      echo "ollama"
      return
    fi
  fi

  # 6. 降级到 Mock
  echo "mock"
}

# ==================== 统一接口 ====================

# 确保 Provider 已加载
_llm_ensure_loaded() {
  if [[ "$_LLM_PROVIDER_LOADED" != "true" ]]; then
    llm_load_provider || return 1
  fi
  return 0
}

# 统一重排序接口
# 参数: $1 - 查询内容
# 参数: $2 - 候选 JSON 数组
# 返回: 重排序后的 JSON 结果
llm_rerank() {
  local query="$1"
  local candidates="$2"

  _llm_ensure_loaded || return 1

  if [[ -z "$query" ]]; then
    echo '{"success": false, "error": "query is required"}' >&2
    return 1
  fi

  if [[ -z "$candidates" ]]; then
    echo '{"success": false, "error": "candidates is required"}' >&2
    return 1
  fi

  # 调用 Provider 的 rerank 实现
  local start_time
  # macOS 的 date 不支持 %N，使用兼容方式
  if date +%s%3N 2>/dev/null | grep -q 'N'; then
    # macOS: 使用秒级精度
    start_time=$(date +%s)000
  else
    start_time=$(date +%s%3N 2>/dev/null || echo "0")
  fi

  local result
  if result=$(_llm_provider_rerank "$query" "$candidates"); then
    local end_time
    if date +%s%3N 2>/dev/null | grep -q 'N'; then
      end_time=$(date +%s)000
    else
      end_time=$(date +%s%3N 2>/dev/null || echo "0")
    fi
    local latency_ms=$((end_time - start_time))

    # 包装成统一格式
    jq -n \
      --argjson result "$result" \
      --arg provider "$_LLM_CURRENT_PROVIDER" \
      --argjson latency "$latency_ms" \
      '{
        success: true,
        provider: $provider,
        ranked: $result,
        latency_ms: $latency
      }'
  else
    local error_msg="${result:-unknown error}"
    jq -n \
      --arg provider "$_LLM_CURRENT_PROVIDER" \
      --arg error "$error_msg" \
      '{
        success: false,
        provider: $provider,
        error: $error
      }'
    return 1
  fi
}

# 统一 LLM 调用接口
# 参数: $1 - prompt
# 返回: LLM 响应 JSON
llm_call() {
  local prompt="$1"

  _llm_ensure_loaded || return 1

  if [[ -z "$prompt" ]]; then
    echo '{"success": false, "error": "prompt is required"}' >&2
    return 1
  fi

  # 调用 Provider 的 call 实现
  local start_time
  # macOS 的 date 不支持 %N，使用兼容方式
  if date +%s%3N 2>/dev/null | grep -q 'N'; then
    start_time=$(date +%s)000
  else
    start_time=$(date +%s%3N 2>/dev/null || echo "0")
  fi

  local result
  if result=$(_llm_provider_call "$prompt"); then
    local end_time
    if date +%s%3N 2>/dev/null | grep -q 'N'; then
      end_time=$(date +%s)000
    else
      end_time=$(date +%s%3N 2>/dev/null || echo "0")
    fi
    local latency_ms=$((end_time - start_time))

    # 包装成统一格式
    jq -n \
      --arg result "$result" \
      --arg provider "$_LLM_CURRENT_PROVIDER" \
      --argjson latency "$latency_ms" \
      '{
        success: true,
        provider: $provider,
        content: $result,
        latency_ms: $latency
      }'
  else
    local error_msg="${result:-unknown error}"
    jq -n \
      --arg provider "$_LLM_CURRENT_PROVIDER" \
      --arg error "$error_msg" \
      '{
        success: false,
        provider: $provider,
        error: $error
      }'
    return 1
  fi
}

# 验证 Provider 配置
# 返回: 0=配置有效, 1=配置无效
llm_validate_config() {
  _llm_ensure_loaded || return 1

  # 调用 Provider 的 validate 实现
  if type _llm_provider_validate &>/dev/null; then
    _llm_provider_validate
  else
    # 默认验证：检查 API Key
    local env_key
    env_key=$(_llm_get_provider_config "$_LLM_CURRENT_PROVIDER" "env_key")

    if [[ -n "$env_key" ]]; then
      if [[ -z "${!env_key:-}" ]]; then
        log_error "缺少环境变量: $env_key"
        return 1
      fi
    fi
    return 0
  fi
}

# 获取 Provider 信息
# 返回: Provider 元信息 JSON
llm_get_info() {
  _llm_ensure_loaded || return 1

  local env_key default_model endpoint
  env_key=$(_llm_get_provider_config "$_LLM_CURRENT_PROVIDER" "env_key")
  default_model=$(_llm_get_provider_config "$_LLM_CURRENT_PROVIDER" "default_model")
  endpoint=$(_llm_get_provider_config "$_LLM_CURRENT_PROVIDER" "endpoint")

  # 检查 API Key 是否已配置
  local api_key_configured="false"
  if [[ -z "$env_key" ]] || [[ -n "${!env_key:-}" ]]; then
    api_key_configured="true"
  fi

  jq -n \
    --arg provider "$_LLM_CURRENT_PROVIDER" \
    --arg script "$_LLM_PROVIDER_SCRIPT" \
    --arg env_key "$env_key" \
    --arg default_model "$default_model" \
    --arg endpoint "$endpoint" \
    --argjson api_key_configured "$api_key_configured" \
    '{
      provider: $provider,
      script: $script,
      env_key: $env_key,
      default_model: $default_model,
      endpoint: $endpoint,
      api_key_configured: $api_key_configured
    }'
}

# ==================== Provider 切换 ====================

# 切换 Provider（无需重新加载脚本）
# 参数: $1 - 新的 Provider 名称
# 返回: 0=成功, 1=失败
llm_switch_provider() {
  local new_provider="$1"

  if [[ -z "$new_provider" ]]; then
    log_error "未指定新的 Provider"
    return 1
  fi

  if [[ "$new_provider" == "$_LLM_CURRENT_PROVIDER" ]]; then
    log_info "Provider 未变更: $new_provider"
    return 0
  fi

  # 重新加载新的 Provider
  _LLM_PROVIDER_LOADED=false
  llm_load_provider "$new_provider"
}

# 获取当前 Provider 名称
llm_get_current_provider() {
  echo "$_LLM_CURRENT_PROVIDER"
}

# ==================== 向后兼容接口 ====================

# 向后兼容: 检查 LLM 是否可用（保持 common.sh 的 API）
# 返回: 0=可用, 1=不可用
llm_available() {
  # 检查 Mock 模式
  if [[ -n "${LLM_MOCK_RESPONSE:-}" ]]; then
    return 0
  fi

  # 尝试加载 Provider
  if _llm_ensure_loaded 2>/dev/null; then
    llm_validate_config 2>/dev/null
    return $?
  fi

  return 1
}

# 向后兼容别名（测试期望的 API）
# llm_provider_rerank -> llm_rerank
llm_provider_rerank() {
  llm_rerank "$@"
}

# llm_provider_call -> llm_call
llm_provider_call() {
  llm_call "$@"
}

# llm_provider_info -> llm_get_info
llm_provider_info() {
  llm_get_info "$@"
}

# llm_provider_validate -> llm_validate_config
llm_provider_validate() {
  llm_validate_config "$@"
}

# ==================== CLI 接口 ====================

# 显示帮助
_llm_show_help() {
  cat << 'EOF'
DevBooks LLM Provider 抽象层

用法:
  source scripts/llm-provider.sh
  llm_load_provider [provider]
  llm_rerank "查询" '[{"file":"a.ts","content":"..."}]'
  llm_call "请分析..."

  # 或作为命令行工具
  ./llm-provider.sh [命令] [参数...]

命令:
  list                 列出所有可用的 Provider
  info [provider]      显示 Provider 信息
  test [provider]      测试 Provider 连接
  rerank               重排序（从 stdin 读取 JSON）
  call                 调用 LLM（从 stdin 读取 prompt）

选项:
  --provider <name>    指定 Provider (anthropic/openai/ollama/mock)
  --model <name>       指定模型
  --timeout <ms>       超时毫秒数（默认 2000）
  --help               显示此帮助
  --version            显示版本

环境变量:
  LLM_DEFAULT_PROVIDER   默认 Provider
  LLM_DEFAULT_MODEL      默认模型
  LLM_TIMEOUT_MS         超时毫秒数
  LLM_MOCK_RESPONSE      Mock 响应（测试用）
  LLM_MOCK_DELAY_MS      Mock 延迟（测试用）
  LLM_MOCK_FAIL_COUNT    Mock 失败次数（测试用）
  ANTHROPIC_API_KEY      Anthropic API 密钥
  OPENAI_API_KEY         OpenAI API 密钥

示例:
  # 列出 Provider
  ./llm-provider.sh list

  # 测试 Provider
  ./llm-provider.sh test anthropic

  # 重排序
  echo '{"query":"test","candidates":[...]}' | ./llm-provider.sh rerank --provider anthropic

  # LLM 调用
  echo "分析这段代码" | ./llm-provider.sh call --provider openai

EOF
}

_llm_show_version() {
  echo "llm-provider.sh version 1.0.0"
}

# CLI 主入口
_llm_cli_main() {
  local command=""
  local provider=""
  local model=""
  local timeout=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      list|info|test|rerank|call)
        command="$1"
        shift
        ;;
      --provider)
        provider="$2"
        shift 2
        ;;
      --model)
        model="$2"
        shift 2
        ;;
      --timeout)
        timeout="$2"
        shift 2
        ;;
      --help|-h)
        _llm_show_help
        exit 0
        ;;
      --version)
        _llm_show_version
        exit 0
        ;;
      *)
        # 可能是命令的参数
        if [[ -z "$command" ]]; then
          log_error "未知命令: $1"
          _llm_show_help
          exit 1
        fi
        break
        ;;
    esac
  done

  # 设置环境变量
  [[ -n "$provider" ]] && LLM_DEFAULT_PROVIDER="$provider"
  [[ -n "$model" ]] && LLM_DEFAULT_MODEL="$model"
  [[ -n "$timeout" ]] && LLM_TIMEOUT_MS="$timeout"

  case "$command" in
    list)
      llm_list_providers
      ;;
    info)
      llm_load_provider "${1:-$provider}" || exit 1
      llm_get_info
      ;;
    test)
      llm_load_provider "${1:-$provider}" || exit 1
      if llm_validate_config; then
        log_ok "Provider 连接测试成功: $_LLM_CURRENT_PROVIDER"
        llm_get_info
      else
        log_error "Provider 连接测试失败"
        exit 1
      fi
      ;;
    rerank)
      llm_load_provider "$provider" || exit 1
      local input
      input=$(cat)
      local query candidates
      query=$(echo "$input" | jq -r '.query // empty')
      candidates=$(echo "$input" | jq -c '.candidates // []')
      llm_rerank "$query" "$candidates"
      ;;
    call)
      llm_load_provider "$provider" || exit 1
      local prompt
      prompt=$(cat)
      llm_call "$prompt"
      ;;
    "")
      _llm_show_help
      exit 0
      ;;
    *)
      log_error "未知命令: $command"
      exit 1
      ;;
  esac
}

# 如果直接执行脚本（非 source），则运行 CLI
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _llm_cli_main "$@"
fi
