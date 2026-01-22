#!/bin/bash
# DevBooks 共享工具函数库
# 版本: 3.0
# 用途: 提供日志、颜色、依赖检查等通用函数

# ==================== 颜色定义 ====================
# 终端颜色（可通过 NO_COLOR 环境变量禁用）
if [ -z "${NO_COLOR:-}" ] && [ -t 2 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'  # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# ==================== 日志函数 ====================
# 用法: log_info "message"
# 所有日志输出到 stderr，避免污染 stdout 的 JSON 输出

# 设置日志前缀（默认 DevBooks）
: "${LOG_PREFIX:=DevBooks}"

log_info()  { echo -e "${BLUE}[${LOG_PREFIX}]${NC} $1" >&2; }
log_ok()    { echo -e "${GREEN}[${LOG_PREFIX}]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[${LOG_PREFIX}]${NC} $1" >&2; }
log_error() { echo -e "${RED}[${LOG_PREFIX}]${NC} $1" >&2; }

# ==================== 依赖检查 ====================
# 检查必需的命令是否存在
# 用法: check_dependency "jq" || exit 2
check_dependency() {
  local cmd="$1"
  if command -v "$cmd" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

# 检查多个依赖并报告缺失的
# 用法: check_dependencies jq bc curl
# 返回: 0=全部存在, 2=有缺失
check_dependencies() {
  local missing=()
  for cmd in "$@"; do
    if ! check_dependency "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "缺少依赖: ${missing[*]}"
    log_info "请安装: brew install ${missing[*]} 或 apt install ${missing[*]}"
    return 2
  fi
  return 0
}

# 检查可选依赖，缺失时返回警告但不失败
# 用法: check_optional_dependency "bc" "浮点运算将使用 awk 替代"
check_optional_dependency() {
  local cmd="$1"
  local fallback_msg="${2:-}"

  if ! check_dependency "$cmd"; then
    if [ -n "$fallback_msg" ]; then
      log_warn "可选依赖 $cmd 未安装: $fallback_msg"
    fi
    return 1
  fi
  return 0
}

# ==================== 浮点运算辅助 ====================
# 使用 bc 或 awk 进行浮点运算（自动降级）
# 用法: float_calc "1.5 * 2 + 0.3"
float_calc() {
  local expr="$1"
  local scale="${2:-2}"

  if check_dependency "bc"; then
    echo "scale=$scale; $expr" | bc 2>/dev/null
  else
    # 使用 awk 作为降级方案
    awk "BEGIN {printf \"%.${scale}f\", $expr}" 2>/dev/null
  fi
}

# ==================== 哈希工具 ====================
# 统一字符串哈希（避免 macOS md5 输出前缀差异）
hash_string_md5() {
  local input="$1"

  if command -v md5sum &>/dev/null; then
    printf '%s' "$input" | md5sum 2>/dev/null | cut -d' ' -f1
  elif command -v md5 &>/dev/null; then
    if md5 -q /dev/null >/dev/null 2>&1; then
      printf '%s' "$input" | md5 -q 2>/dev/null
    else
      printf '%s' "$input" | md5 2>/dev/null
    fi
  else
    printf '%s' "$input" | cksum 2>/dev/null | cut -d' ' -f1
  fi
}

# ==================== Bug Fix 规则（共享） ====================
is_bug_fix_message() {
  local message="$1"
  local msg_lower
  msg_lower=$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')

  if [[ "$msg_lower" =~ ^fix[:\([:space:]] ]] || \
     [[ "$msg_lower" =~ (bug|issue|error|crash|broken|fail) ]]; then
    return 0
  fi

  return 1
}

# ==================== 错误码约定 ====================
# 0 = 成功
# 1 = 参数错误
# 2 = 依赖缺失
# 3 = 运行时错误

export EXIT_SUCCESS=0
export EXIT_ARGS_ERROR=1
export EXIT_DEPS_MISSING=2
export EXIT_RUNTIME_ERROR=3

# ==================== 意图检测（共享正则） ====================
# 代码相关意图的正则模式
export CODE_INTENT_PATTERN='修复|fix|bug|错误|重构|refactor|优化|添加|新增|实现|implement|删除|remove|修改|update|change|分析|analyze|影响|impact|引用|reference|调用|call|依赖|depend|函数|function|方法|method|类|class|模块|module|\.ts|\.tsx|\.js|\.py|\.go|src/|lib/'

# 非代码意图的正则模式
export NON_CODE_PATTERN='^(天气|weather|翻译|translate|写邮件|email|闲聊|chat|你好|hello|hi)'

# 四分类意图关键词模式（按优先级排序）
# 优先级: debug > refactor > docs > feature (default)
export INTENT_DEBUG_PATTERN='fix|debug|bug|crash|fail|error|issue|resolve|problem|broken'
export INTENT_REFACTOR_PATTERN='refactor|optimize|improve|clean|simplify|quality|performance|restructure'
export INTENT_DOCS_PATTERN='doc|comment|readme|explain|guide|write.*guide|注释|文档'

# 检测是否为代码相关意图
# 参数: $1 - 用户输入
# 返回: 0 表示是代码意图，1 表示不是
is_code_intent() {
  local input="$1"
  local lower_input
  lower_input=$(echo "$input" | tr '[:upper:]' '[:lower:]')

  # 使用新的四分类：debug/refactor/feature 都是代码意图，docs 不是
  local intent_type
  intent_type=$(get_intent_type "$input")

  case "$intent_type" in
    debug|refactor|feature)
      return 0  # 是代码意图
      ;;
    docs)
      return 1  # 不是代码意图
      ;;
    *)
      # 降级到旧逻辑
      echo "$input" | grep -qiE "$CODE_INTENT_PATTERN"
      ;;
  esac
}

# 检测是否为非代码意图
# 参数: $1 - 用户输入
# 返回: 0 表示是非代码意图，1 表示不是
is_non_code() {
  echo "$1" | grep -qiE "$NON_CODE_PATTERN"
}

# 四分类意图检测
# 参数: $1 - 用户输入
# 返回: debug | refactor | docs | feature
# 优先级: debug > refactor > docs > feature (default)
get_intent_type() {
  local input="$1"

  # 边界处理：空字符串、纯空白、特殊字符 -> 默认 feature
  if [[ -z "$input" ]] || [[ "$input" =~ ^[[:space:]]*$ ]] || [[ ! "$input" =~ [a-zA-Z] ]]; then
    echo "feature"
    return 0
  fi

  # 转小写以便不区分大小写匹配
  local lower_input
  lower_input=$(echo "$input" | tr '[:upper:]' '[:lower:]')

  # 按优先级检测
  # 1. Debug 类（最高优先级）
  if echo "$lower_input" | grep -qiE "$INTENT_DEBUG_PATTERN"; then
    echo "debug"
    return 0
  fi

  # 2. Refactor 类
  if echo "$lower_input" | grep -qiE "$INTENT_REFACTOR_PATTERN"; then
    echo "refactor"
    return 0
  fi

  # 3. Docs 类
  if echo "$lower_input" | grep -qiE "$INTENT_DOCS_PATTERN"; then
    echo "docs"
    return 0
  fi

  # 4. Feature 类（默认）
  echo "feature"
  return 0
}

# ==================== 版本信息 ====================
DEVBOOKS_COMMON_VERSION="3.0"

# ==================== 配置管理 ====================
# 配置存储（使用简单变量，兼容 bash 3）
DEVBOOKS_CONFIG_FILE=""
DEVBOOKS_CONFIG_LOADED=false

# 默认配置值（使用函数返回，兼容 bash 3）
_get_default_config() {
  local key="$1"
  case "$key" in
    "embedding.provider") echo "auto" ;;
    "embedding.enabled") echo "true" ;;
    "embedding.auto_build") echo "true" ;;
    "embedding.fallback_to_keyword") echo "true" ;;
    "embedding.ollama.model") echo "nomic-embed-text" ;;
    "embedding.ollama.endpoint") echo "http://localhost:11434" ;;
    "embedding.ollama.timeout") echo "30" ;;
    "graph_rag.enabled") echo "true" ;;
    "graph_rag.max_depth") echo "2" ;;
    "graph_rag.token_budget") echo "8000" ;;
    "graph_rag.top_k") echo "10" ;;
    "graph_rag.ckb.enabled") echo "true" ;;
    "graph_rag.ckb.fallback_to_import") echo "true" ;;
    "features.complexity_weighted_hotspot") echo "true" ;;
    "features.hotspot_limit") echo "5" ;;
    "features.entropy_visualization") echo "true" ;;
    "features.entropy_mermaid") echo "true" ;;
    "features.entropy_ascii_dashboard") echo "true" ;;
    *) echo "" ;;
  esac
}

# 从配置文件读取值（简单 YAML 解析）
_read_config_from_file() {
  local config_file="$1"
  local key="$2"

  if [[ ! -f "$config_file" ]]; then
    return 1
  fi

  # 将 key 转换为 YAML 路径查找
  # 例如 "embedding.provider" -> 查找 embedding: 下的 provider:
  local parts
  IFS='.' read -ra parts <<< "$key"
  local depth=${#parts[@]}

  if [[ $depth -eq 2 ]]; then
    # 两级路径：section.key
    local section="${parts[0]}"
    local subkey="${parts[1]}"

    # 使用 awk 解析
    awk -v section="$section" -v subkey="$subkey" '
      BEGIN { in_section = 0 }
      /^[a-zA-Z_]+:/ {
        gsub(/:.*/, "", $1)
        in_section = ($1 == section) ? 1 : 0
      }
      in_section && /^[[:space:]]+[a-zA-Z_]+:/ {
        gsub(/^[[:space:]]+/, "", $0)
        gsub(/:.*/, "", $1)
        if ($1 == subkey) {
          value = $0
          gsub(/^[^:]+:[[:space:]]*/, "", value)
          gsub(/[[:space:]]*#.*$/, "", value)
          gsub(/^["'"'"']|["'"'"']$/, "", value)
          print value
          exit
        }
      }
    ' "$config_file" 2>/dev/null
  elif [[ $depth -eq 3 ]]; then
    # 三级路径：section.subsection.key
    local section="${parts[0]}"
    local subsection="${parts[1]}"
    local subkey="${parts[2]}"

    awk -v section="$section" -v subsection="$subsection" -v subkey="$subkey" '
      BEGIN { in_section = 0; in_subsection = 0 }
      /^[a-zA-Z_]+:/ {
        gsub(/:.*/, "", $1)
        in_section = ($1 == section) ? 1 : 0
        in_subsection = 0
      }
      in_section && /^[[:space:]][[:space:]][a-zA-Z_]+:/ {
        gsub(/^[[:space:]]+/, "", $0)
        gsub(/:.*/, "", $1)
        in_subsection = ($1 == subsection) ? 1 : 0
      }
      in_section && in_subsection && /^[[:space:]][[:space:]][[:space:]][[:space:]][a-zA-Z_]+:/ {
        gsub(/^[[:space:]]+/, "", $0)
        gsub(/:.*/, "", $1)
        if ($1 == subkey) {
          value = $0
          gsub(/^[^:]+:[[:space:]]*/, "", value)
          gsub(/[[:space:]]*#.*$/, "", value)
          gsub(/^["'"'"']|["'"'"']$/, "", value)
          print value
          exit
        }
      }
    ' "$config_file" 2>/dev/null
  fi
}

# 加载配置文件
# 参数: $1 - 配置文件路径
# 返回: 0=成功, 1=文件不存在或解析失败
load_config() {
  local config_file="$1"
  DEVBOOKS_CONFIG_FILE="$config_file"
  DEVBOOKS_CONFIG_LOADED=true
  return 0
}

# 获取配置值
# 参数: $1 - 配置路径（如 "embedding.provider"）
# 参数: $2 - 默认值（可选）
# 返回: 配置值或默认值
get_config_value() {
  local key="$1"
  local default="${2:-}"

  # 首先尝试从配置文件读取
  if [[ -n "$DEVBOOKS_CONFIG_FILE" && -f "$DEVBOOKS_CONFIG_FILE" ]]; then
    local value
    value=$(_read_config_from_file "$DEVBOOKS_CONFIG_FILE" "$key")
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
  fi

  # 其次返回默认值
  local def_value
  def_value=$(_get_default_config "$key")
  if [[ -n "$def_value" ]]; then
    echo "$def_value"
    return 0
  fi

  # 返回提供的默认值
  if [[ -n "$default" ]]; then
    echo "$default"
    return 0
  fi

  return 1
}

# ==================== 热点文件（Legacy 函数） ====================

# 获取热点文件列表
# 参数: $1 - 限制数量（默认 5）
# 返回: 热点文件列表（一行一个）
get_hotspot_files() {
  local limit="${1:-5}"
  local project_root="${PROJECT_ROOT:-$(pwd)}"

  # 使用 git log 分析高频修改文件
  if command -v git &>/dev/null && [[ -d "$project_root/.git" ]]; then
    git -C "$project_root" log --pretty=format: --name-only --since="30 days ago" 2>/dev/null | \
      grep -v '^$' | \
      sort | uniq -c | sort -rn | \
      head -"$limit" | \
      awk '{print $2}'
  else
    # 降级：返回最近修改的文件
    find "$project_root" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" \) \
      -not -path "*/node_modules/*" -not -path "*/.git/*" \
      -mtime -30 2>/dev/null | head -"$limit"
  fi
}

# ==================== 功能开关 ====================
# Trace: AC-010

# 默认配置文件路径（统一使用 config/features.yaml）
if [[ -z "${DEVBOOKS_FEATURE_CONFIG:-}" ]]; then
  feature_root="${PROJECT_ROOT:-$(pwd)}"
  DEVBOOKS_FEATURE_CONFIG="$feature_root/config/features.yaml"
fi

# 一键启用所有功能开关（CLI --enable-all-features 可设置）
: "${DEVBOOKS_ENABLE_ALL_FEATURES:=}"

# 检查功能是否启用
# 参数: $1 - 功能名称 (如 hotspot_analyzer)
# 返回: 0=启用, 1=禁用
is_feature_enabled() {
  local feature="$1"
  local config_file="${DEVBOOKS_FEATURE_CONFIG}"

  if [[ -n "${DEVBOOKS_ENABLE_ALL_FEATURES:-}" ]]; then
    return 0
  fi

  # 如果配置文件不存在，默认禁用
  if [[ ! -f "$config_file" ]]; then
    return 1
  fi

  # 查找功能配置值
  local value
  value=$(awk -v feature="$feature" '
    BEGIN { in_features = 0; in_target = 0 }
    /^features:/ { in_features = 1; next }
    /^[a-zA-Z]/ && !/^features:/ { in_features = 0; in_target = 0 }
    in_features && $0 ~ "^[[:space:]]{2}" feature ":" { in_target = 1; next }
    in_features && in_target && $0 ~ "^[[:space:]]{2}[a-zA-Z0-9_]+" && $0 !~ "^[[:space:]]{2}" feature ":" { in_target = 0 }
    in_target && /enabled:/ {
      sub(/^[^:]+:[[:space:]]*/, "")
      gsub(/#.*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ' "$config_file" 2>/dev/null)

  # 检查值（默认禁用）
  case "$value" in
    true|True|TRUE|yes|Yes|YES|1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 获取功能配置值
# 参数: $1 - 功能名称 (如 hotspot_limit)
# 参数: $2 - 默认值
# 返回: 配置值或默认值
get_feature_value() {
  local feature="$1"
  local default="${2:-}"
  local config_file="${DEVBOOKS_FEATURE_CONFIG}"

  # 如果配置文件不存在，返回默认值
  if [[ ! -f "$config_file" ]]; then
    echo "$default"
    return
  fi

  # 查找功能配置值
  local value
  value=$(awk -v feature="$feature" '
    BEGIN { in_features = 0 }
    /^features:/ { in_features = 1; next }
    /^[a-zA-Z]/ && !/^features:/ { in_features = 0 }
    in_features && $0 ~ feature {
      gsub(/.*:/, "")
      gsub(/[[:space:]]/, "")
      gsub(/#.*/, "")
      print
      exit
    }
  ' "$config_file" 2>/dev/null)

  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "$default"
  fi
}

# ==================== LLM 调用函数 ====================
# Trace: AC-004

# 获取 LLM 配置值
# 参数: $1 - 配置键 (如 provider, model, timeout_ms)
# 参数: $2 - 默认值
# 返回: 配置值
_get_llm_config() {
  local key="$1"
  local default="${2:-}"
  local config_file="${FEATURES_CONFIG:-${DEVBOOKS_FEATURE_CONFIG}}"

  # 如果配置文件不存在，返回默认值
  if [[ ! -f "$config_file" ]]; then
    echo "$default"
    return
  fi

  # 解析 features.llm_rerank.<key> 配置
  local value
  value=$(awk -v key="$key" '
    BEGIN { in_features = 0; in_llm_rerank = 0 }
    /^features:/ { in_features = 1; next }
    /^[a-zA-Z]/ && !/^features:/ { in_features = 0; in_llm_rerank = 0 }
    in_features && /llm_rerank:/ { in_llm_rerank = 1; next }
    in_features && /^[[:space:]][[:space:]][a-zA-Z]/ && !/llm_rerank/ { in_llm_rerank = 0 }
    in_llm_rerank && $0 ~ key {
      # 只删除第一个冒号之前的内容（key: value 格式）
      sub(/^[^:]+:[[:space:]]*/, "")
      gsub(/#.*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ' "$config_file" 2>/dev/null)

  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "$default"
  fi
}

# 检查 LLM 是否可用
# 返回: 0=可用, 1=不可用
llm_available() {
  # 检查 Mock 模式
  if [[ -n "${LLM_MOCK_RESPONSE:-}" ]]; then
    return 0
  fi

  # 获取 provider
  local provider="${LLM_PROVIDER:-$(_get_llm_config "provider" "anthropic")}"

  # 根据 provider 检查 API Key
  case "$provider" in
    anthropic)
      [[ -n "${ANTHROPIC_API_KEY:-}" ]] && return 0
      ;;
    openai)
      [[ -n "${OPENAI_API_KEY:-}" ]] && return 0
      ;;
    ollama)
      # Ollama 不需要 API Key，检查服务是否可用
      local endpoint="${LLM_ENDPOINT:-$(_get_llm_config "endpoint" "http://localhost:11434")}"
      if command -v curl &>/dev/null; then
        curl -s --connect-timeout 1 "$endpoint/api/tags" &>/dev/null && return 0
      fi
      return 1
      ;;
  esac

  return 1
}

# 调用 LLM API
# 参数: $1 - prompt (必需)
# 环境变量:
#   LLM_PROVIDER - 提供商 (anthropic/openai/ollama)
#   LLM_MODEL - 模型名称
#   LLM_TIMEOUT_MS - 超时毫秒数 (默认 2000)
#   LLM_MOCK_RESPONSE - Mock 响应 (测试用)
#   LLM_MOCK_DELAY_MS - Mock 延迟毫秒数 (测试用)
# 返回: JSON 格式响应
llm_call() {
  local prompt="$1"

  if [[ -z "$prompt" ]]; then
    echo '{"error": "prompt is required"}' >&2
    return 1
  fi

  # 获取配置
  local provider="${LLM_PROVIDER:-$(_get_llm_config "provider" "anthropic")}"
  local model="${LLM_MODEL:-$(_get_llm_config "model" "claude-3-haiku")}"
  local timeout_ms="${LLM_TIMEOUT_MS:-$(_get_llm_config "timeout_ms" "2000")}"
  local endpoint="${LLM_ENDPOINT:-$(_get_llm_config "endpoint" "")}"

  # 转换超时为秒（向上取整）
  local timeout_sec=$(( (timeout_ms + 999) / 1000 ))

  # Mock 模式（用于测试）
  if [[ -n "${LLM_MOCK_RESPONSE:-}" ]] || [[ -n "${LLM_MOCK_DELAY_MS:-}" ]]; then
    # 模拟延迟并检查超时
    if [[ -n "${LLM_MOCK_DELAY_MS:-}" ]]; then
      local delay_ms="${LLM_MOCK_DELAY_MS}"
      # 如果延迟超过配置的超时，返回超时错误
      if [[ "$delay_ms" -gt "$timeout_ms" ]]; then
        return 124  # timeout exit code
      fi
      local delay_sec=$(( delay_ms / 1000 ))
      [[ "$delay_sec" -gt 0 ]] && sleep "$delay_sec" 2>/dev/null || true
    fi

    # 模拟失败计数
    if [[ -n "${LLM_MOCK_FAIL_COUNT:-}" && "${LLM_MOCK_FAIL_COUNT}" -gt 0 ]]; then
      export LLM_MOCK_FAIL_COUNT=$((LLM_MOCK_FAIL_COUNT - 1))
      echo '{"error": "mock failure"}' >&2
      return 1
    fi

    # 返回 Mock 响应（如果设置了）或默认空数组
    echo "${LLM_MOCK_RESPONSE:-[]}"
    return 0
  fi

  # 检查 API Key
  if ! llm_available; then
    echo '{"error": "api_key not configured for provider: '"$provider"'"}' >&2
    return 1
  fi

  # 检查 curl 依赖
  if ! command -v curl &>/dev/null; then
    echo '{"error": "curl is required"}' >&2
    return 2
  fi

  # 根据 provider 调用不同的 API
  local response
  case "$provider" in
    anthropic)
      response=$(_llm_call_anthropic "$prompt" "$model" "$timeout_sec")
      ;;
    openai)
      response=$(_llm_call_openai "$prompt" "$model" "$timeout_sec")
      ;;
    ollama)
      response=$(_llm_call_ollama "$prompt" "$model" "$timeout_sec" "$endpoint")
      ;;
    *)
      echo '{"error": "unsupported provider: '"$provider"'"}' >&2
      return 1
      ;;
  esac

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo '{"error": "timeout or request failed"}' >&2
    return $exit_code
  fi

  echo "$response"
}

# Anthropic API 调用
_llm_call_anthropic() {
  local prompt="$1"
  local model="$2"
  local timeout_sec="$3"

  local api_key="${ANTHROPIC_API_KEY:-}"
  local max_tokens="${LLM_MAX_TOKENS:-1024}"

  # 构建请求体
  local request_body
  request_body=$(jq -n \
    --arg model "$model" \
    --arg prompt "$prompt" \
    --argjson max_tokens "$max_tokens" \
    '{
      model: $model,
      max_tokens: $max_tokens,
      messages: [{role: "user", content: $prompt}]
    }' 2>/dev/null)

  # 发送请求
  local response
  response=$(timeout "$timeout_sec" curl -s \
    -X POST "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01" \
    -d "$request_body" 2>/dev/null)

  local exit_code=$?
  if [[ $exit_code -eq 124 ]]; then
    return 124  # timeout
  fi

  # 提取响应内容
  if command -v jq &>/dev/null; then
    echo "$response" | jq -r '.content[0].text // .error.message // .' 2>/dev/null
  else
    echo "$response"
  fi
}

# OpenAI API 调用
_llm_call_openai() {
  local prompt="$1"
  local model="$2"
  local timeout_sec="$3"

  local api_key="${OPENAI_API_KEY:-}"
  local max_tokens="${LLM_MAX_TOKENS:-1024}"

  # 构建请求体
  local request_body
  request_body=$(jq -n \
    --arg model "$model" \
    --arg prompt "$prompt" \
    --argjson max_tokens "$max_tokens" \
    '{
      model: $model,
      max_tokens: $max_tokens,
      messages: [{role: "user", content: $prompt}]
    }' 2>/dev/null)

  # 发送请求
  local response
  response=$(timeout "$timeout_sec" curl -s \
    -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_key" \
    -d "$request_body" 2>/dev/null)

  local exit_code=$?
  if [[ $exit_code -eq 124 ]]; then
    return 124  # timeout
  fi

  # 提取响应内容
  if command -v jq &>/dev/null; then
    echo "$response" | jq -r '.choices[0].message.content // .error.message // .' 2>/dev/null
  else
    echo "$response"
  fi
}

# Ollama API 调用
_llm_call_ollama() {
  local prompt="$1"
  local model="$2"
  local timeout_sec="$3"
  local endpoint="${4:-http://localhost:11434}"

  # 构建请求体
  local request_body
  request_body=$(jq -n \
    --arg model "$model" \
    --arg prompt "$prompt" \
    '{
      model: $model,
      prompt: $prompt,
      stream: false
    }' 2>/dev/null)

  # 发送请求
  local response
  response=$(timeout "$timeout_sec" curl -s \
    -X POST "$endpoint/api/generate" \
    -H "Content-Type: application/json" \
    -d "$request_body" 2>/dev/null)

  local exit_code=$?
  if [[ $exit_code -eq 124 ]]; then
    return 124  # timeout
  fi

  # 提取响应内容
  if command -v jq &>/dev/null; then
    echo "$response" | jq -r '.response // .error // .' 2>/dev/null
  else
    echo "$response"
  fi
}

# ==================== DevBooks 适配函数 ====================
# Trace: AC-G12, REQ-DBA-001~008

# DevBooks 检测结果缓存
_DEVBOOKS_ROOT=""
_DEVBOOKS_CACHE_TIME=0
_DEVBOOKS_CACHE_TTL=60  # 缓存 60 秒

# 检测 DevBooks 配置
# 返回: DevBooks 真理目录路径（如 "dev-playbooks/"），未检测到返回空
# 按优先级检测:
#   1. .devbooks/config.yaml (最高优先级)
#   2. dev-playbooks/project.md
#   3. openspec/project.md
#   4. .openspec/project.md (最低优先级)
detect_devbooks() {
  local project_root="${1:-$(pwd)}"

  # 检查缓存是否有效
  local now
  now=$(date +%s)
  if [[ -n "$_DEVBOOKS_ROOT" && $((now - _DEVBOOKS_CACHE_TIME)) -lt $_DEVBOOKS_CACHE_TTL ]]; then
    echo "$_DEVBOOKS_ROOT"
    return 0
  fi

  local devbooks_root=""

  # 优先级 1: .devbooks/config.yaml
  if [[ -f "$project_root/.devbooks/config.yaml" ]]; then
    # 解析 root 字段
    local root_value
    root_value=$(grep -E "^root:" "$project_root/.devbooks/config.yaml" 2>/dev/null | head -1 | sed 's/^root:[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/#.*//')
    if [[ -n "$root_value" && "$root_value" != "null" ]]; then
      # 移除引号
      root_value="${root_value%\"}"
      root_value="${root_value#\"}"
      root_value="${root_value%\'}"
      root_value="${root_value#\'}"
      devbooks_root="$root_value"
    else
      # 如果没有 root 字段，使用默认值 dev-playbooks/
      devbooks_root="dev-playbooks/"
    fi
  # 优先级 2: dev-playbooks/project.md
  elif [[ -f "$project_root/dev-playbooks/project.md" ]]; then
    devbooks_root="dev-playbooks/"
  # 优先级 3: openspec/project.md
  elif [[ -f "$project_root/openspec/project.md" ]]; then
    devbooks_root="openspec/"
  # 优先级 4: .openspec/project.md
  elif [[ -f "$project_root/.openspec/project.md" ]]; then
    devbooks_root=".openspec/"
  fi

  # 更新缓存
  _DEVBOOKS_ROOT="$devbooks_root"
  _DEVBOOKS_CACHE_TIME=$now

  echo "$devbooks_root"
}

# 提取项目画像从 project-profile.md
# 参数: $1 - DevBooks 根目录的绝对路径
# 返回: JSON 格式项目画像
# 支持格式：列表格式（- item）和表格格式（| key | value |）
_extract_project_profile() {
  local devbooks_path="$1"
  local profile_file="$devbooks_path/specs/_meta/project-profile.md"

  if [[ ! -f "$profile_file" ]]; then
    log_info "project-profile.md 缺失，使用基础画像" >&2
    echo '{}'
    return 0
  fi

  local tech_stack='[]'
  local constraints='[]'
  local key_commands='{}'

  # 提取技术栈（从表格中"技术栈"行或 ### 技术栈详情 表格）
  # 格式 1: | 技术栈 | TypeScript + Node.js + Shell Scripts |
  # 格式 2: ### 技术栈详情 表格中的技术列
  local line
  while IFS= read -r line; do
    # 解析表格中的技术栈行（| 技术栈 | value |）
    if [[ "$line" =~ \|[[:space:]]*技术栈[[:space:]]*\| ]]; then
      local tech_value
      tech_value=$(echo "$line" | sed 's/.*|[[:space:]]*技术栈[[:space:]]*|[[:space:]]*//' | sed 's/[[:space:]]*|.*//')
      if [[ -n "$tech_value" ]]; then
        # 按 + 分割
        local IFS_BAK="$IFS"
        IFS='+'
        for item in $tech_value; do
          item=$(echo "$item" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
          [[ -n "$item" ]] && tech_stack=$(echo "$tech_stack" | jq --arg item "$item" '. + [$item]')
        done
        IFS="$IFS_BAK"
      fi
      break  # 只取第一个技术栈行
    fi
  done < "$profile_file"

  # 如果表格方式没找到，尝试 ### 技术栈详情 表格
  if [[ "$(echo "$tech_stack" | jq -r 'length')" -eq 0 ]]; then
    local in_tech_table=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^###[[:space:]]*技术栈详情 ]]; then
        in_tech_table=true
        continue
      fi
      if [[ "$line" =~ ^### ]] && [[ "$in_tech_table" == "true" ]]; then
        break
      fi
      # 解析表格行（| 层级 | 技术 | 版本 |）
      if [[ "$in_tech_table" == "true" && "$line" =~ ^\|[[:space:]]*(运行时|语言|协议|脚本|工具)[[:space:]]*\| ]]; then
        local tech_name
        tech_name=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')
        if [[ -n "$tech_name" && "$tech_name" != "技术" && "$tech_name" != "-" ]]; then
          tech_stack=$(echo "$tech_stack" | jq --arg item "$tech_name" '. + [$item]')
        fi
      fi
    done < "$profile_file"
  fi

  # 提取约束（从 ### 已知设计约束 表格）
  local in_constraints_section=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]*已知设计约束 ]]; then
      in_constraints_section=true
      continue
    fi
    if [[ "$line" =~ ^### ]] && [[ "$in_constraints_section" == "true" ]]; then
      break
    fi
    # 解析表格格式（| CON-XXX | 描述 |）
    if [[ "$in_constraints_section" == "true" && "$line" =~ \|[[:space:]]*(CON-[A-Z0-9-]+)[[:space:]]*\| ]]; then
      local con_id con_desc
      con_id=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')
      con_desc=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')
      if [[ -n "$con_id" && -n "$con_desc" && "$con_id" != "约束 ID" ]]; then
        local full_constraint="$con_id: $con_desc"
        constraints=$(echo "$constraints" | jq --arg item "$full_constraint" '. + [$item]')
      fi
    fi
  done < "$profile_file"

  # 提取快速命令（从 ### 命令速查 表格）
  local in_commands_section=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]*命令速查 ]]; then
      in_commands_section=true
      continue
    fi
    if [[ "$line" =~ ^### ]] && [[ "$in_commands_section" == "true" ]]; then
      break
    fi
    # 解析表格格式 | `command` | 用途 |
    if [[ "$in_commands_section" == "true" && "$line" =~ ^\|[[:space:]]*\`[a-z] ]]; then
      local cmd_raw cmd_name cmd_desc
      cmd_raw=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')
      cmd_desc=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')
      # 移除反引号
      cmd_name=$(echo "$cmd_raw" | tr -d '`')
      if [[ -n "$cmd_name" && -n "$cmd_desc" && "$cmd_name" != "命令" ]]; then
        # 用描述的第一个词（小写）作为 key
        local key_simple
        key_simple=$(echo "$cmd_desc" | sed 's/[[:space:]].*//' | tr '[:upper:]' '[:lower:]')
        [[ -n "$key_simple" ]] && key_commands=$(echo "$key_commands" | jq --arg k "$key_simple" --arg v "$cmd_name" '. + {($k): $v}')
      fi
    fi
  done < "$profile_file"

  jq -n \
    --argjson tech_stack "$tech_stack" \
    --argjson constraints "$constraints" \
    --argjson key_commands "$key_commands" \
    '{
      tech_stack: $tech_stack,
      key_constraints: $constraints,
      key_commands: $key_commands
    }'
}

# 提取架构约束从 c4.md
# 参数: $1 - DevBooks 根目录的绝对路径
# 返回: JSON 格式架构约束
_extract_architecture_constraints() {
  local devbooks_path="$1"
  local c4_file="$devbooks_path/specs/architecture/c4.md"

  if [[ ! -f "$c4_file" ]]; then
    log_info "c4.md 缺失，跳过架构约束" >&2
    echo '{"architectural": [], "security": []}'
    return 0
  fi

  local architectural='[]'
  local security='[]'

  # 提取分层约束（从 ## 分层约束 章节）
  local in_layering_section=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]*分层约束 ]] || [[ "$line" =~ ^##[[:space:]]*Layer ]]; then
      in_layering_section=true
      continue
    fi
    if [[ "$line" =~ ^## ]] && [[ "$in_layering_section" == "true" ]]; then
      break
    fi
    if [[ "$in_layering_section" == "true" && "$line" =~ ^-[[:space:]]+ ]]; then
      local item
      item=$(echo "$line" | sed 's/^-[[:space:]]*//' | sed 's/[[:space:]]*$//')
      if [[ -n "$item" ]]; then
        # 提取规则部分（中文或英文冒号后的内容）
        # 使用 sed 处理，因为 bash 正则对 Unicode 支持不好
        local extracted
        extracted=$(echo "$item" | sed 's/^[^:：]*[：:][[:space:]]*//')
        if [[ "$extracted" != "$item" && -n "$extracted" ]]; then
          item="$extracted"
        fi
        architectural=$(echo "$architectural" | jq --arg item "$item" '. + [$item]')
      fi
    fi
  done < "$c4_file"

  jq -n \
    --argjson architectural "$architectural" \
    --argjson security "$security" \
    '{
      architectural: $architectural,
      security: $security
    }'
}

# 检测活跃变更包
# 参数: $1 - DevBooks 根目录的绝对路径
# 返回: JSON 格式活跃变更列表
_detect_active_changes() {
  local devbooks_path="$1"
  local changes_dir="$devbooks_path/changes"

  if [[ ! -d "$changes_dir" ]]; then
    echo '[]'
    return 0
  fi

  local active_changes='[]'

  # 遍历 changes 目录下的子目录
  for change_dir in "$changes_dir"/*/; do
    [[ -d "$change_dir" ]] || continue
    local proposal_file="$change_dir/proposal.md"
    [[ -f "$proposal_file" ]] || continue

    # 读取 Status 字段（使用 change_status 避免与 shell 内置变量冲突）
    local change_status
    change_status=$(grep -E "^\*\*Status\*\*:|^Status:" "$proposal_file" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' | sed 's/[[:space:]]*$//')

    # 只保留 Pending 或 Approved 状态的变更
    if [[ "$change_status" == "Pending" || "$change_status" == "Approved" || "$change_status" == "In Progress" ]]; then
      local change_id
      change_id=$(basename "$change_dir")

      # 读取标题（通常是第一行 # 开头）
      local title
      title=$(grep -E "^#[^#]" "$proposal_file" 2>/dev/null | head -1 | sed 's/^#[[:space:]]*//')

      active_changes=$(echo "$active_changes" | jq \
        --arg id "$change_id" \
        --arg status "$change_status" \
        --arg title "$title" \
        '. + [{id: $id, status: $status, title: $title}]')
    fi
  done

  echo "$active_changes"
}

# 加载 DevBooks 上下文
# 参数: $1 - 项目根目录（可选，默认当前目录）
# 返回: JSON 格式完整上下文
# 包含: project_profile, constraints, active_changes
load_devbooks_context() {
  local project_root="${1:-$(pwd)}"

  # 检测 DevBooks
  local devbooks_rel
  devbooks_rel=$(detect_devbooks "$project_root")

  if [[ -z "$devbooks_rel" ]]; then
    # 未检测到 DevBooks，返回空上下文
    log_info "未检测到 DevBooks 配置，使用基础上下文" >&2
    jq -n '{
      devbooks_detected: false,
      project_profile: {},
      constraints: {architectural: [], security: []},
      active_changes: []
    }'
    return 0
  fi

  local devbooks_path="$project_root/$devbooks_rel"

  # 提取各部分信息
  local profile
  profile=$(_extract_project_profile "$devbooks_path")

  local constraints
  constraints=$(_extract_architecture_constraints "$devbooks_path")

  local active_changes
  active_changes=$(_detect_active_changes "$devbooks_path")

  # 组合输出
  jq -n \
    --argjson profile "$profile" \
    --argjson constraints "$constraints" \
    --argjson active_changes "$active_changes" \
    --arg devbooks_root "$devbooks_rel" \
    '{
      devbooks_detected: true,
      devbooks_root: $devbooks_root,
      project_profile: $profile,
      constraints: $constraints,
      active_changes: $active_changes
    }'
}
