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

# ==================== 错误码约定 ====================
# 0 = 成功
# 1 = 参数错误
# 2 = 依赖缺失
# 3 = 运行时错误

EXIT_SUCCESS=0
EXIT_ARGS_ERROR=1
EXIT_DEPS_MISSING=2
EXIT_RUNTIME_ERROR=3

# ==================== 意图检测（共享正则） ====================
# 代码相关意图的正则模式
CODE_INTENT_PATTERN='修复|fix|bug|错误|重构|refactor|优化|添加|新增|实现|implement|删除|remove|修改|update|change|分析|analyze|影响|impact|引用|reference|调用|call|依赖|depend|函数|function|方法|method|类|class|模块|module|\.ts|\.tsx|\.js|\.py|\.go|src/|lib/'

# 非代码意图的正则模式
NON_CODE_PATTERN='^(天气|weather|翻译|translate|写邮件|email|闲聊|chat|你好|hello|hi)'

# 四分类意图关键词模式（按优先级排序）
# 优先级: debug > refactor > docs > feature (default)
INTENT_DEBUG_PATTERN='fix|debug|bug|crash|fail|error|issue|resolve|problem|broken'
INTENT_REFACTOR_PATTERN='refactor|optimize|improve|clean|simplify|quality|performance|restructure'
INTENT_DOCS_PATTERN='doc|comment|readme|explain|guide|write.*guide|注释|文档'

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

# 默认配置文件路径
DEVBOOKS_FEATURE_CONFIG="${DEVBOOKS_FEATURE_CONFIG:-.devbooks/config.yaml}"

# 检查功能是否启用
# 参数: $1 - 功能名称 (如 hotspot_analyzer)
# 返回: 0=启用, 1=禁用
is_feature_enabled() {
  local feature="$1"
  local config_file="${DEVBOOKS_FEATURE_CONFIG}"

  # 如果配置文件不存在，默认启用
  if [[ ! -f "$config_file" ]]; then
    return 0
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

  # 检查值
  case "$value" in
    false|False|FALSE|no|No|NO|0)
      return 1
      ;;
    *)
      return 0
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
