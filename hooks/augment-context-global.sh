#!/bin/bash
# DevBooks Global Context Injection Hook
# 全局生效，自动检测代码项目并注入上下文
# 版本: 3.0 - 新增：Graph-RAG 集成 + Embedding 自动构建 + 优雅降级

# ==================== 环境设置 ====================
# 注意：不全局修改 PATH，以便支持测试时的隔离环境
# 复杂度工具检测使用 command -v，会尊重当前 PATH 设置

# 查找 rg (ripgrep) - 优先系统安装，其次 Claude Code 内置
# 这里使用显式路径检查，不依赖 PATH
find_rg() {
  # 系统路径（显式检查，不受 PATH 限制）
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { echo "$p"; return; }
  done

  # Claude Code 内置（使用平台检测，避免硬编码）
  local arch platform
  arch=$(uname -m)
  platform=$(uname -s | tr '[:upper:]' '[:lower:]')
  local cc_rg="$HOME/.cli-versions/claude-code/claude-latest/node_modules/@anthropic-ai/claude-code/vendor/ripgrep/${arch}-${platform}/rg"
  [ -x "$cc_rg" ] && { echo "$cc_rg"; return; }

  # 使用 glob 模式查找（比 find 更快，避免遍历整个目录树）
  for p in "$HOME/.cli-versions/claude-code"/*/node_modules/@anthropic-ai/claude-code/vendor/ripgrep/*/rg; do
    [ -x "$p" ] && { echo "$p"; return; }
  done

  echo ""
}

RG_CMD=$(find_rg)

# ==================== 配置 ====================
MAX_SNIPPETS=3
MAX_LINES=20
# shellcheck disable=SC2034  # Reserved for future use
SEARCH_TIMEOUT=2
CACHE_DIR="${TMPDIR:-/tmp}/.devbooks-cache"
CACHE_TTL=300

# 热点算法配置
HOTSPOT_LIMIT=5
# shellcheck disable=SC2034  # Reserved for future use
COMPLEXITY_TIMEOUT=1

# 复杂度工具路径（相对于脚本位置或绝对路径）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLEXITY_TOOL="${SCRIPT_DIR}/../../tools/devbooks-complexity.sh"

# ==================== 帮助信息 ====================
show_help() {
  cat <<'EOF'
Usage: augment-context-global.sh [OPTIONS]

DevBooks 全局上下文注入 Hook。自动检测代码项目并注入相关上下文。

Options:
  --help                显示帮助信息
  --analyze-intent      执行 4 维意图分析并输出结果
  --prompt TEXT         指定要分析的提示文本（与 --analyze-intent 配合使用）
  --file PATH           指定相关文件路径（隐式信号来源）
  --line N              指定文件行号
  --function NAME       指定函数名（代码信号来源）
  --with-history        启用历史信号分析
  --format FORMAT       输出格式: text 或 json（默认: json）

4-Dimensional Intent Signals:
  - explicit:    直接指令词（fix, add, remove, update, etc.）
  - implicit:    问题描述（error, bug, issue, crash, etc.）
  - historical:  文件引用（@file, 文件路径）
  - code:        代码片段（反引号内容, 函数名）

Examples:
  echo '{"prompt":"fix auth bug"}' | augment-context-global.sh
  augment-context-global.sh --analyze-intent --prompt "fix authentication bug"
  augment-context-global.sh --analyze-intent --file src/auth.ts --line 42
EOF
}

# ==================== 命令行参数解析（早期处理） ====================
CLI_MODE=""
CLI_PROMPT=""
CLI_FILE=""
CLI_LINE=""
CLI_FUNCTION=""
CLI_WITH_HISTORY=false
CLI_FORMAT="json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --analyze-intent)
      CLI_MODE="analyze-intent"
      shift
      ;;
    --prompt)
      CLI_PROMPT="$2"
      shift 2
      ;;
    --file)
      CLI_FILE="$2"
      shift 2
      ;;
    --line)
      CLI_LINE="$2"
      shift 2
      ;;
    --function)
      CLI_FUNCTION="$2"
      shift 2
      ;;
    --with-history)
      CLI_WITH_HISTORY=true
      shift
      ;;
    --format)
      CLI_FORMAT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# 加载共享缓存工具库
CACHE_UTILS="${SCRIPT_DIR}/../../tools/devbooks-cache-utils.sh"
if [ -f "$CACHE_UTILS" ]; then
  # shellcheck source=../../tools/devbooks-cache-utils.sh
  source "$CACHE_UTILS"
fi

# 加载共享工具库（意图检测等）
COMMON_UTILS="${SCRIPT_DIR}/../../tools/devbooks-common.sh"
if [ -f "$COMMON_UTILS" ]; then
  # shellcheck source=../../tools/devbooks-common.sh
  source "$COMMON_UTILS"
fi

# 加载 scripts/common.sh（DevBooks 适配函数）
SCRIPTS_COMMON="${SCRIPT_DIR}/../scripts/common.sh"
if [ -f "$SCRIPTS_COMMON" ]; then
  # shellcheck source=../scripts/common.sh
  source "$SCRIPTS_COMMON"
fi

# 如果共享库加载失败，在非 CLI 模式下退出
# CLI 模式（如 --analyze-intent 或 --format json/text）不需要完整的 Hook 功能
if ! declare -f is_code_intent &>/dev/null || ! declare -f get_cache_key &>/dev/null; then
  # 如果 is_code_intent 不可用，但 get_intent_type 可用（来自 common.sh），定义一个简单版本
  if ! declare -f is_code_intent &>/dev/null && declare -f get_intent_type &>/dev/null; then
    is_code_intent() {
      local input="$1"
      local intent_type
      intent_type=$(get_intent_type "$input")
      case "$intent_type" in
        debug|refactor|feature) return 0 ;;
        docs) return 1 ;;
        *) return 0 ;;
      esac
    }
  fi

  # 如果 get_cache_key 不可用，定义一个简单版本
  if ! declare -f get_cache_key &>/dev/null; then
    get_cache_key() { echo "$1" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$1"; }
    get_cached() { echo ""; }
    set_cache() { :; }
  fi

  # 如果 is_non_code 不可用，定义一个简单版本
  if ! declare -f is_non_code &>/dev/null; then
    is_non_code() {
      echo "$1" | grep -qiE '^(天气|weather|翻译|translate|写邮件|email|闲聊|chat|你好|hello|hi)'
    }
  fi

  # CLI 模式可以继续（有内置的 analyze_intent_4d 函数）
  if [ -z "$CLI_MODE" ] && [ "$CLI_FORMAT" = "json" -o "$CLI_FORMAT" = "text" ]; then
    # --format json/text 模式也可以继续
    :
  elif [ -z "$CLI_MODE" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":""}}'
    exit 0
  fi
fi

# 排除模式 - 使用 grep -v 更可靠（rg glob 在某些情况下行为不一致）
EXCLUDE_PATTERN='(node_modules|dist|build|\.git|coverage|__pycache__|\.venv|venv|/tests/|/test/|_test\.|\.test\.|\.spec\.|example|mock|fixture|__mocks__|\.lock)'

# Embedding 索引路径
EMBEDDING_INDEX=""

# Graph-RAG 配置（默认值，将被 config.yaml 覆盖）
GRAPH_RAG_ENABLED=true
GRAPH_RAG_MAX_DEPTH=2
GRAPH_RAG_TOKEN_BUDGET=8000
GRAPH_RAG_TOP_K=10
GRAPH_RAG_CACHE_TTL=300

# Reranker 配置（默认关闭）
RERANKER_ENABLED=false
RERANKER_MODEL="haiku"

# Embedding 配置
EMBEDDING_AUTO_BUILD=true
EMBEDDING_FALLBACK_TO_KEYWORD=true

# 降级状态追踪
FALLBACK_REASON=""
FALLBACK_DEGRADED_TO=""

# ==================== 配置加载 ====================
# 从 config.yaml 读取配置值（顶层 key）
read_yaml_value() {
  local file="$1"
  local key="$2"
  local default="$3"

  if [ ! -f "$file" ]; then
    echo "$default"
    return
  fi

  # 简易 YAML 读取（支持 key: value 格式）
  local value
  value=$(grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 | sed 's/.*:\s*//' | sed 's/\s*$//' | sed 's/#.*//')

  if [ -n "$value" ] && [ "$value" != "null" ]; then
    echo "$value"
  else
    echo "$default"
  fi
}

# 从 YAML section 中读取嵌套值（通用函数，消除重复）
# 参数: $1=文件路径, $2=section名称, $3=key名称, $4=默认值
read_yaml_section_value() {
  local file="$1"
  local section="$2"
  local key="$3"
  local default="$4"

  if [ ! -f "$file" ]; then
    echo "$default"
    return
  fi

  local section_content
  section_content=$(grep -A 10 "^${section}:" "$file" 2>/dev/null)

  if [ -z "$section_content" ]; then
    echo "$default"
    return
  fi

  local value
  value=$(echo "$section_content" | grep "${key}:" | head -1 | sed 's/.*:\s*//' | sed 's/\s*$//' | sed 's/#.*//')

  if [ -n "$value" ] && [ "$value" != "null" ]; then
    echo "$value"
  else
    echo "$default"
  fi
}

# 加载项目配置
load_project_config() {
  local config_file="$CWD/.devbooks/config.yaml"

  if [ ! -f "$config_file" ]; then
    return
  fi

  # Graph-RAG 配置（使用通用函数）
  GRAPH_RAG_ENABLED=$(read_yaml_section_value "$config_file" "graph_rag" "enabled" "$GRAPH_RAG_ENABLED")
  GRAPH_RAG_MAX_DEPTH=$(read_yaml_section_value "$config_file" "graph_rag" "max_depth" "$GRAPH_RAG_MAX_DEPTH")
  GRAPH_RAG_TOKEN_BUDGET=$(read_yaml_section_value "$config_file" "graph_rag" "token_budget" "$GRAPH_RAG_TOKEN_BUDGET")
  GRAPH_RAG_TOP_K=$(read_yaml_section_value "$config_file" "graph_rag" "top_k" "$GRAPH_RAG_TOP_K")
  GRAPH_RAG_CACHE_TTL=$(read_yaml_section_value "$config_file" "graph_rag" "cache_ttl" "$GRAPH_RAG_CACHE_TTL")

  # Reranker 配置（使用通用函数）
  local re_enabled
  re_enabled=$(read_yaml_section_value "$config_file" "reranker" "enabled" "")
  [ -n "$re_enabled" ] && RERANKER_ENABLED="$re_enabled"
  local re_model
  re_model=$(read_yaml_section_value "$config_file" "reranker" "model" "")
  [ -n "$re_model" ] && RERANKER_MODEL="$re_model"

  # Embedding 配置（使用通用函数）
  local emb_auto
  emb_auto=$(read_yaml_section_value "$config_file" "embedding" "auto_build" "")
  [ -n "$emb_auto" ] && EMBEDDING_AUTO_BUILD="$emb_auto"
  local emb_fallback
  emb_fallback=$(read_yaml_section_value "$config_file" "embedding" "fallback_to_keyword" "")
  # shellcheck disable=SC2034  # Config variable for future use
  [ -n "$emb_fallback" ] && EMBEDDING_FALLBACK_TO_KEYWORD="$emb_fallback"
}

# ==================== 输入处理（延迟 CLI 处理） ====================
# 如果是 CLI 模式，不从 stdin 读取
if [ -n "$CLI_MODE" ]; then
  INPUT=""
  PROMPT="$CLI_PROMPT"
else
  INPUT=$(cat)
  PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
fi

CWD="${WORKING_DIRECTORY:-$(pwd)}"

# CLI 模式处理将延迟到 analyze_intent_4d 函数定义之后
# 见下面的 "CLI 模式入口" 部分

[ -z "$PROMPT" ] && [ -z "$CLI_MODE" ] && { echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":""}}'; exit 0; }

# ==================== 项目检测 ====================
is_code_project() {
  local dir="$1"
  # 检查常见项目标识文件
  [ -f "$dir/package.json" ] && return 0
  [ -f "$dir/tsconfig.json" ] && return 0
  [ -f "$dir/pyproject.toml" ] && return 0
  [ -f "$dir/setup.py" ] && return 0
  [ -f "$dir/requirements.txt" ] && return 0
  [ -f "$dir/go.mod" ] && return 0
  [ -f "$dir/Cargo.toml" ] && return 0
  [ -f "$dir/pom.xml" ] && return 0
  [ -f "$dir/build.gradle" ] && return 0
  [ -f "$dir/Makefile" ] && return 0
  [ -f "$dir/CMakeLists.txt" ] && return 0
  [ -d "$dir/.git" ] && return 0
  return 1
}

# 非代码项目则跳过
is_code_project "$CWD" || { echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":""}}'; exit 0; }

# 检测 Embedding 索引
check_embedding_index() {
  local index_path="$CWD/.devbooks/embeddings/index.tsv"
  if [ -f "$index_path" ] && [ -s "$index_path" ]; then
    EMBEDDING_INDEX="$index_path"
    return 0
  fi
  return 1
}

# 检测是否有 API Key 可用
has_embedding_api_key() {
  [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${EMBEDDING_API_KEY:-}" ] || [ -n "${AZURE_OPENAI_API_KEY:-}" ]
}

# 后台触发 Embedding 索引构建
trigger_embedding_build() {
  local embedding_tool="${SCRIPT_DIR}/../../tools/devbooks-embedding.sh"
  local lock_file="$CWD/.devbooks/.embedding-building"
  local log_file="$CWD/.devbooks/logs/embedding-build.log"

  # 检查工具是否存在
  if [ ! -x "$embedding_tool" ]; then
    return 1
  fi

  # 检查是否已有构建进程
  if [ -f "$lock_file" ]; then
    local pid
    pid=$(cat "$lock_file" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0  # 构建进行中
    fi
    rm -f "$lock_file"
  fi

  # 确保日志目录存在
  mkdir -p "$(dirname "$log_file")" 2>/dev/null

  # 后台启动构建（不阻塞 Hook）
  (
    trap 'rm -f "$lock_file"' EXIT TERM INT
    echo $$ > "$lock_file"
    cd "$CWD" && PROJECT_ROOT="$CWD" "$embedding_tool" build >> "$log_file" 2>&1
  ) &

  return 0
}

# Embedding 索引检测与自动构建 (MP1.1 + MP1.2 + MP1.3)
setup_embedding() {
  # 先检测现有索引
  if check_embedding_index; then
    return 0  # 索引可用
  fi

  # 无索引，检查是否有 API Key
  if ! has_embedding_api_key; then
    # 无 API Key：记录降级原因
    FALLBACK_REASON="no_api_key"
    FALLBACK_DEGRADED_TO="keyword"
    return 1
  fi

  # 有 API Key 但无索引
  if [ "$EMBEDDING_AUTO_BUILD" = "true" ]; then
    # 触发后台构建
    trigger_embedding_build
    FALLBACK_REASON="building"
    FALLBACK_DEGRADED_TO="keyword"
  else
    FALLBACK_REASON="index_not_found"
    FALLBACK_DEGRADED_TO="keyword"
  fi

  return 1
}

# ==================== 缓存机制（使用共享库） ====================
# 缓存函数由 tools/devbooks-cache-utils.sh 提供
# 不再提供内联降级实现，已在脚本开头统一检查并退出

# ==================== 意图检测 ====================
# 意图检测函数由 tools/devbooks-common.sh 提供（CODE_INTENT_PATTERN, NON_CODE_PATTERN, is_code_intent, is_non_code）

# ==================== 四维意图分析 (AC-002) ====================
# 聚合显式/隐式/历史/代码 4 维信号，提升意图理解深度
# 返回 JSON 格式：{explicit: w1, implicit: w2, historical: w3, code: w4, signals: [...]}
analyze_intent_4d() {
  local prompt="$1"
  local signals='[]'

  # 1. 显式信号 (explicit) - 直接指令词
  local explicit_weight=0
  local explicit_patterns='(fix|add|remove|update|create|delete|implement|refactor|debug|test|review)'
  if echo "$prompt" | grep -qiE "$explicit_patterns"; then
    explicit_weight=1.0
    local matched
    matched=$(echo "$prompt" | grep -oiE "$explicit_patterns" | head -1)
    signals=$(echo "$signals" | jq --arg t "explicit" --arg m "$matched" '. + [{type: $t, match: $m, weight: 1.0}]')
  fi

  # 2. 隐式信号 (implicit) - 问题描述、错误信息
  local implicit_weight=0
  local implicit_patterns='(error|exception|bug|issue|problem|crash|fail|not working|broken)'
  if echo "$prompt" | grep -qiE "$implicit_patterns"; then
    implicit_weight=0.8
    local matched
    matched=$(echo "$prompt" | grep -oiE "$implicit_patterns" | head -1)
    signals=$(echo "$signals" | jq --arg t "implicit" --arg m "$matched" '. + [{type: $t, match: $m, weight: 0.8}]')
  fi

  # 3. 历史信号 (historical) - 文件引用、之前的上下文
  local historical_weight=0
  # 检查是否有 @file 引用或文件路径
  if echo "$prompt" | grep -qE '@[a-zA-Z0-9_./]+|[a-zA-Z0-9_/]+\.(ts|js|py|go|sh)'; then
    historical_weight=0.6
    local matched
    matched=$(echo "$prompt" | grep -oE '@[a-zA-Z0-9_./]+|[a-zA-Z0-9_/]+\.(ts|js|py|go|sh)' | head -1)
    signals=$(echo "$signals" | jq --arg t "historical" --arg m "$matched" '. + [{type: $t, match: $m, weight: 0.6}]')
  fi

  # 4. 代码信号 (code) - 代码片段、符号名
  local code_weight=0
  # 检查是否有反引号代码或函数名模式
  if echo "$prompt" | grep -qE '\`[^\`]+\`|[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*|[A-Z][a-zA-Z0-9]*[a-z][a-zA-Z0-9]*'; then
    code_weight=0.7
    local matched
    matched=$(echo "$prompt" | grep -oE '\`[^\`]+\`|[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*' | head -1)
    signals=$(echo "$signals" | jq --arg t "code" --arg m "$matched" '. + [{type: $t, match: $m, weight: 0.7}]')
  fi

  # 构建输出 JSON
  jq -n \
    --argjson explicit "$explicit_weight" \
    --argjson implicit "$implicit_weight" \
    --argjson historical "$historical_weight" \
    --argjson code "$code_weight" \
    --argjson signals "$signals" \
    '{
      weights: {
        explicit: $explicit,
        implicit: $implicit,
        historical: $historical,
        code: $code
      },
      signals: $signals,
      total_weight: ($explicit + $implicit + $historical + $code),
      dominant_dimension: (
        if $explicit >= $implicit and $explicit >= $historical and $explicit >= $code then "explicit"
        elif $implicit >= $explicit and $implicit >= $historical and $implicit >= $code then "implicit"
        elif $historical >= $explicit and $historical >= $implicit and $historical >= $code then "historical"
        else "code"
        end
      )
    }'
}

# ==================== 符号提取 ====================
extract_symbols() {
  local q="$1"
  local cached
  cached=$(get_cached "symbols:$q")
  [ -n "$cached" ] && { echo "$cached"; return; }

  local result
  result=$(
    {
      # camelCase (如 getUserById)
      echo "$q" | grep -oE '\b[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*\b'
      # PascalCase (如 UserService)
      echo "$q" | grep -oE '\b[A-Z][a-zA-Z0-9]*[a-z][a-zA-Z0-9]*\b'
      # 反引号内容 (如 `search`)
      echo "$q" | grep -oE '\`[^\`]+\`' | tr -d '\`'
      # 文件路径
      echo "$q" | grep -oE '[a-zA-Z0-9_/\-]+\.(ts|tsx|js|jsx|py|go|sh|md)'
      # snake_case (如 get_user_by_id)
      echo "$q" | grep -oE '\b[a-z]+_[a-z_]+\b'
      # 英文单词（4+ 字符且不是常见停用词）
      echo "$q" | tr ' ' '\n' | grep -oE '^[a-zA-Z]{4,}$' | grep -ivE '^(that|this|with|from|have|been|will|would|could|should|about|after|before|through|function|class|method|implement|analyze|analysis)$'
    } | grep -v '^$' | awk '!seen[$0]++' | head -$MAX_SNIPPETS
  )
  set_cache "symbols:$q" "$result"
  echo "$result"
}

# ==================== @file/@folder 引用 ====================
# 提取 @file 和 @folder 引用
extract_at_refs() {
  local q="$1"
  # 匹配 @file:path 或 @folder:path 或 @path（简化语法）
  echo "$q" | grep -oE '@(file:|folder:)?[a-zA-Z0-9_./-]+' | sed 's/^@//' | sed 's/^file://' | sed 's/^folder://'
}

# 读取 @file 引用的文件内容
read_file_ref() {
  local path="$1"
  local full_path=""

  # 移除尾部斜杠
  path="${path%/}"

  # 尝试解析路径
  if [[ "$path" = /* ]]; then
    full_path="$path"
  else
    full_path="$CWD/$path"
  fi

  # 检查是文件还是目录
  if [ -f "$full_path" ]; then
    # 文件：读取内容（限制行数）
    local rel_path="${full_path#"$CWD"/}"
    echo "📄 $rel_path:"
    echo '```'
    head -30 "$full_path" 2>/dev/null
    local lines
    lines=$(wc -l < "$full_path" 2>/dev/null | tr -d ' ')
    if [ "$lines" -gt 30 ]; then
      echo "... (共 $lines 行)"
    fi
    echo '```'
  elif [ -d "$full_path" ]; then
    # 目录：列出文件
    local rel_path="${full_path#"$CWD"/}"
    echo "📁 $rel_path/:"
    echo '```'
    ls -la "$full_path" 2>/dev/null | head -20
    echo '```'
  fi
}

# 处理所有 @引用
process_at_refs() {
  local refs="$1"
  local result=""

  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    local content
    content=$(read_file_ref "$ref")
    if [ -n "$content" ]; then
      result="${result}

$content"
    fi
  done <<< "$refs"

  echo "$result"
}

# ==================== 代码搜索 ====================
# macOS 兼容的超时函数
run_with_timeout() {
  local timeout_sec="$1"
  shift
  if command -v gtimeout &>/dev/null; then
    gtimeout "$timeout_sec" "$@"
  elif command -v timeout &>/dev/null; then
    timeout "$timeout_sec" "$@"
  else
    # 无超时命令，直接执行（依赖 ripgrep 自身的性能）
    "$@"
  fi
}

# 搜索符号定义（class/def/function）
search_definition() {
  local sym="$1"
  [ -z "$sym" ] && return

  local result=""
  if [ -n "$RG_CMD" ]; then
    # 构建定义模式：class Foo, def foo, function foo, const foo =, let foo =
    local def_pattern="(class|def|function|const|let|var|type|interface|struct|enum)\\s+${sym}\\b"

    # 搜索更多结果（10个），过滤后取第一个定义
    local raw_result
    raw_result=$("$RG_CMD" \
      --max-count=10 \
      --max-filesize=500K \
      --pcre2 \
      -n -C 3 \
      -t py -t js -t ts -t go -t sh \
      "$def_pattern" "$CWD" 2>/dev/null)

    # 过滤排除模式，移除空的 -- 分隔符，转换为相对路径，截断
    result=$(echo "$raw_result" | grep -vE "$EXCLUDE_PATTERN" | grep -v '^--$' | sed "s|$CWD/||g" | head -$MAX_LINES)
  fi
  echo "$result"
}

# 搜索符号引用（降级方案）
search_reference() {
  local sym="$1"
  [ -z "$sym" ] && return

  local result=""
  if [ -n "$RG_CMD" ]; then
    result=$("$RG_CMD" \
      --max-count=3 \
      --max-filesize=500K \
      --smart-case \
      -n -C 3 \
      -t py -t js -t ts -t go -t sh \
      "\\b${sym}\\b" "$CWD" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" | grep -v '^--$' | sed "s|$CWD/||g" | head -$MAX_LINES)
  else
    result=$(grep -rn \
      --include='*.ts' --include='*.js' --include='*.py' --include='*.go' \
      -A 2 -B 1 "$sym" "$CWD" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" | grep -v '^--$' | sed "s|$CWD/||g" | head -$MAX_LINES)
  fi
  echo "$result"
}

# 智能搜索：优先定义，降级到引用
search_symbol() {
  local sym="$1"
  [ -z "$sym" ] && return

  local cached
  cached=$(get_cached "search:$CWD:$sym")
  [ -n "$cached" ] && { echo "$cached"; return; }

  local result=""

  # 1. 首先尝试搜索定义
  result=$(search_definition "$sym")

  # 2. 如果没找到定义，搜索引用
  if [ -z "$result" ]; then
    result=$(search_reference "$sym")
  fi

  [ -n "$result" ] && set_cache "search:$CWD:$sym" "$result"
  echo "$result"
}

# 顺序搜索（简化版，避免子 shell 问题）
do_search() {
  local symbols="$1"
  local results=""

  while IFS= read -r symbol; do
    [ -z "$symbol" ] && continue
    local snippet
    snippet=$(search_symbol "$symbol")
    if [ -n "$snippet" ]; then
      results="${results}

🔍 $symbol:
\`\`\`
$snippet
\`\`\`"
    fi
  done <<< "$symbols"

  echo "$results"
}

# ==================== 热点文件 ====================
# 检测复杂度工具是否可用
COMPLEXITY_TOOLS_AVAILABLE=false
check_complexity_tools_available() {
  command -v radon &>/dev/null && { COMPLEXITY_TOOLS_AVAILABLE=true; return 0; }
  command -v scc &>/dev/null && { COMPLEXITY_TOOLS_AVAILABLE=true; return 0; }
  command -v gocyclo &>/dev/null && { COMPLEXITY_TOOLS_AVAILABLE=true; return 0; }
  [ -x "$COMPLEXITY_TOOL" ] && { COMPLEXITY_TOOLS_AVAILABLE=true; return 0; }
  return 1
}

# 获取安装提示（工具缺失时）
get_complexity_install_hint() {
  echo "⚠️ 复杂度工具缺失，建议安装：pip install radon 或 brew install scc"
}

# 获取文件复杂度（调用外部工具或返回默认值）
# 策略：语言专用工具 → scc 通用降级 → 外部工具 → 默认值 1
get_file_complexity() {
  local file="$1"
  local full_path="$CWD/$file"
  local ext="${file##*.}"
  local complexity=""

  # 第一优先级：语言专用工具
  case "$ext" in
    py)
      if command -v radon &>/dev/null; then
        complexity=$(radon cc "$full_path" -s 2>/dev/null | \
          sed -n 's/.*(\([0-9]*\))$/\1/p' | \
          sort -rn | head -1)
      fi
      ;;
    go)
      if command -v gocyclo &>/dev/null; then
        complexity=$(gocyclo "$full_path" 2>/dev/null | \
          awk '{print $1}' | sort -rn | head -1)
      fi
      ;;
  esac

  # 第二优先级：scc 通用降级（所有语言）
  if [ -z "$complexity" ] || ! [ "$complexity" -gt 0 ] 2>/dev/null; then
    if command -v scc &>/dev/null; then
      complexity=$(scc --format json "$full_path" 2>/dev/null | \
        jq -r '.[0].Complexity // empty' 2>/dev/null)
    fi
  fi

  # 第三优先级：外部复杂度工具
  if [ -z "$complexity" ] || ! [ "$complexity" -gt 0 ] 2>/dev/null; then
    if [ -x "$COMPLEXITY_TOOL" ]; then
      complexity=$("$COMPLEXITY_TOOL" "$full_path" 2>/dev/null)
    fi
  fi

  # 返回复杂度或默认值 1
  if [ -n "$complexity" ] && [ "$complexity" -gt 0 ] 2>/dev/null; then
    echo "$complexity"
  else
    echo "1"
  fi
}

# ==================== 热点计算子函数 ====================
# 获取 Git 变更频率数据
get_frequency_data() {
  git -C "$CWD" log \
    --since="30 days ago" \
    --name-only \
    --pretty=format: \
    --max-count=200 \
    2>/dev/null | \
    grep -v '^$' | \
    grep -vE 'node_modules|dist|build|\.lock|\.md$|\.json$|__pycache__|\.pyc$' | \
    sort | uniq -c | sort -rn | head -"$HOTSPOT_LIMIT"
}

# 计算单个文件的热点分数并格式化输出
calculate_hotspot_entry() {
  local freq="$1"
  local file="$2"

  if [ "$COMPLEXITY_TOOLS_AVAILABLE" = true ]; then
    # 工具可用：获取复杂度并显示完整格式
    local complexity
    complexity=$(get_file_complexity "$file")

    # 计算分数
    local score=$((freq * complexity))

    # 格式化输出（包含复杂度字段）
    echo "  🔥 \"$file\" ($freq changes, complexity: $complexity, score: $score)"
  else
    # 工具不可用：纯频率模式（不显示 complexity 字段）
    echo "  🔥 \"$file\" ($freq changes)"
  fi
}

get_hotspots() {
  [ -d "$CWD/.git" ] || return
  local cached
  cached=$(get_cached "hotspots:$CWD")
  [ -n "$cached" ] && { echo "$cached"; return; }

  # 检测复杂度工具可用性
  check_complexity_tools_available

  # 获取频率数据（使用子函数）
  local freq_data
  freq_data=$(get_frequency_data)

  # 无数据则返回
  [ -z "$freq_data" ] && return

  # 如果工具缺失，先输出安装提示
  local install_hint=""
  if [ "$COMPLEXITY_TOOLS_AVAILABLE" = false ]; then
    install_hint=$(get_complexity_install_hint)
  fi

  # 计算热点（使用子函数）
  local result=""
  while IFS= read -r line; do
    local freq file
    freq=$(echo "$line" | awk '{print $1}')
    file=$(echo "$line" | awk '{print $2}')

    [ -z "$file" ] && continue

    local entry
    entry=$(calculate_hotspot_entry "$freq" "$file")
    result="${result}${entry}
"
  done <<< "$freq_data"

  # 添加安装提示（如果有）
  if [ -n "$install_hint" ]; then
    result="${install_hint}
${result}"
  fi

  # 去除末尾换行并缓存
  result="${result%$'\n'}"
  [ -n "$result" ] && set_cache "hotspots:$CWD" "$result"
  echo "$result"
}

# shellcheck disable=SC2034  # index_type reserved for future use
check_index() {
  local status=""
  local index_type=""

  # 检查各类索引（按优先级）
  if [ -n "$EMBEDDING_INDEX" ] && [ -f "$EMBEDDING_INDEX" ]; then
    local count
    count=$(wc -l < "$EMBEDDING_INDEX" 2>/dev/null | tr -d ' ')
    status="✅ Embedding semantic index available ($count files)"
    index_type="embedding"
  elif [ -f "$CWD/index.scip" ]; then
    status="✅ SCIP 索引可用"
    index_type="scip"
  elif [ -d "$CWD/.git/ckb" ]; then
    status="✅ CKB 索引可用"
    index_type="ckb"
  else
    # 无索引：输出引导提示（包含运行命令）
    status="💡 提示：可启用 CKB 加速代码分析，运行 /devbooks-index-bootstrap 生成索引"
    index_type="none"
  fi

  echo "$status"
}

# ==================== Graph-RAG 集成 ====================
# 调用 Graph-RAG 上下文引擎
call_graph_rag() {
  local query="$1"
  local graph_rag_tool="${SCRIPT_DIR}/../../tools/graph-rag-context.sh"

  # 检查工具和配置
  if [ "$GRAPH_RAG_ENABLED" != "true" ]; then
    return 1
  fi

  if [ ! -x "$graph_rag_tool" ]; then
    return 1
  fi

  # 调用 Graph-RAG 工具
  local result
  result=$("$graph_rag_tool" \
    --query "$query" \
    --top-k "$GRAPH_RAG_TOP_K" \
    --max-depth "$GRAPH_RAG_MAX_DEPTH" \
    --token-budget "$GRAPH_RAG_TOKEN_BUDGET" \
    --cwd "$CWD" \
    2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$result" ]; then
    echo "$result"
    return 0
  fi

  return 1
}

# 调用重排序工具
call_reranker() {
  local candidates_json="$1"
  local query="$2"
  local reranker_tool="${SCRIPT_DIR}/../../tools/context-reranker.sh"

  # 检查工具和配置
  if [ "$RERANKER_ENABLED" != "true" ]; then
    return 1
  fi

  if [ ! -x "$reranker_tool" ]; then
    return 1
  fi

  # 调用重排序工具
  local result
  local rc
  result=$(echo "$candidates_json" | "$reranker_tool" \
    --query "$query" \
    --model "$RERANKER_MODEL" \
    2>/dev/null)
  rc=$?

  if [ "$rc" -eq 0 ] && [ -n "$result" ]; then
    echo "$result"
    return 0
  fi

  return 1
}

# ==================== 主逻辑子函数 ====================
# 构建基础上下文
build_base_context() {
  local context
  context="[DevBooks 自动上下文]

$(check_index)"

  # 处理 @file/@folder 引用
  local at_refs="$1"
  if [ -n "$at_refs" ]; then
    local at_content
    at_content=$(process_at_refs "$at_refs")
    if [ -n "$at_content" ]; then
      context="${context}

📎 引用内容：$at_content"
    fi
  fi

  echo "$context"
}

# ==================== 结构化输出构建函数 ====================
# Trace: AC-G11, AC-G12

# 获取索引状态
get_index_status() {
  if [ -n "$EMBEDDING_INDEX" ] && [ -f "$EMBEDDING_INDEX" ]; then
    echo "ready"
  elif [ -f "$CWD/index.scip" ]; then
    # 检查 SCIP 索引是否过时（超过 7 天）
    local mtime
    if stat -f %m "$CWD/index.scip" &>/dev/null 2>&1; then
      mtime=$(stat -f %m "$CWD/index.scip")
    else
      mtime=$(stat -c %Y "$CWD/index.scip" 2>/dev/null || echo "0")
    fi
    local now
    now=$(date +%s)
    local age=$((now - mtime))
    if [ "$age" -gt 604800 ]; then
      echo "stale"
    else
      echo "ready"
    fi
  elif [ -d "$CWD/.git/ckb" ]; then
    echo "ready"
  else
    echo "missing"
  fi
}

# 获取热点文件 Top N（JSON 数组）
get_hotspot_files_json() {
  local limit="${1:-5}"
  local hotspot_script="${SCRIPT_DIR}/../scripts/hotspot-analyzer.sh"

  # 尝试调用 hotspot-analyzer.sh
  if [ -x "$hotspot_script" ]; then
    local result
    result=$("$hotspot_script" --format json --top "$limit" --path "$CWD" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
      echo "$result" | jq -r '[.hotspots[].file] // []' 2>/dev/null
      return 0
    fi
  fi

  # 降级：使用 git log 分析
  if [ -d "$CWD/.git" ]; then
    local files
    files=$(git -C "$CWD" log --since="30 days ago" --name-only --pretty=format: 2>/dev/null | \
      grep -v '^$' | \
      grep -vE 'node_modules|dist|build|\.lock|\.md$|__pycache__|\.pyc$' | \
      sort | uniq -c | sort -rn | head -"$limit" | awk '{print $2}')

    if [ -n "$files" ]; then
      echo "$files" | jq -R -s 'split("\n") | map(select(length > 0))'
      return 0
    fi
  fi

  echo '[]'
}

# 获取最近提交 Top N（JSON 数组）
get_recent_commits_json() {
  local limit="${1:-3}"

  if [ -d "$CWD/.git" ]; then
    git -C "$CWD" log --oneline -"$limit" 2>/dev/null | \
      jq -R -s 'split("\n") | map(select(length > 0))'
    return 0
  fi

  echo '[]'
}

# 映射意图分析结果到标准格式
map_intent_to_standard() {
  local intent_4d="$1"

  # 从 4 维意图分析结果提取主要意图
  local dominant
  dominant=$(echo "$intent_4d" | jq -r '.dominant_dimension // "explore"')

  local primary_intent
  case "$dominant" in
    explicit)
      # 检查是否是 debug 相关
      if echo "$intent_4d" | jq -r '.signals[]?.match' | grep -qiE 'fix|debug|bug'; then
        primary_intent="debug"
      else
        primary_intent="modify"
      fi
      ;;
    implicit)
      primary_intent="debug"
      ;;
    code)
      primary_intent="modify"
      ;;
    *)
      primary_intent="explore"
      ;;
  esac

  local total_weight
  total_weight=$(echo "$intent_4d" | jq -r '.total_weight // 0')

  # 计算置信度（基于总权重）
  local confidence
  confidence=$(awk -v w="$total_weight" 'BEGIN { c = w / 4; if (c > 1) c = 1; printf "%.2f", c }')

  jq -n \
    --arg intent "$primary_intent" \
    --arg confidence "$confidence" \
    '{
      primary_intent: $intent,
      target_scope: "project",
      confidence: ($confidence | tonumber)
    }'
}

# 根据意图推荐工具
get_recommended_tools() {
  local intent="$1"
  local symbols="$2"

  local tools='[]'

  case "$intent" in
    debug)
      tools=$(jq -n '[
        {"tool": "ci_bug_locate", "reason": "定位 Bug 相关代码", "suggested_params": {}},
        {"tool": "ci_call_chain", "reason": "追踪调用链路", "suggested_params": {"depth": 3}}
      ]')
      ;;
    modify)
      tools=$(jq -n '[
        {"tool": "ci_call_chain", "reason": "理解函数调用关系", "suggested_params": {"depth": 3}},
        {"tool": "ci_impact_analysis", "reason": "分析修改影响范围", "suggested_params": {}}
      ]')
      ;;
    explore|understand)
      tools=$(jq -n '[
        {"tool": "ci_search", "reason": "搜索相关代码", "suggested_params": {}},
        {"tool": "ci_graph_rag", "reason": "理解代码结构", "suggested_params": {}}
      ]')
      ;;
    *)
      tools=$(jq -n '[
        {"tool": "ci_search", "reason": "搜索相关代码", "suggested_params": {}}
      ]')
      ;;
  esac

  echo "$tools"
}

# 检测敏感文件
get_security_constraints() {
  local sensitive_files='[]'
  local patterns=(".env" "credentials.json" ".secrets" "*.pem" "*.key")

  for pattern in "${patterns[@]}"; do
    if ls "$CWD"/$pattern &>/dev/null 2>&1; then
      sensitive_files=$(echo "$sensitive_files" | jq --arg p "$pattern" '. + ["敏感文件: " + $p]')
    fi
  done

  echo "$sensitive_files"
}

# 构建结构化输出 JSON
build_structured_output() {
  local prompt="$1"

  # 1. 获取 DevBooks 上下文
  local devbooks_ctx
  if declare -f load_devbooks_context &>/dev/null; then
    devbooks_ctx=$(load_devbooks_context "$CWD" 2>/dev/null) || devbooks_ctx='{}'
  else
    devbooks_ctx='{}'
  fi

  # 2. 构建 project_profile
  local project_name
  project_name=$(jq -r '.name // empty' "$CWD/package.json" 2>/dev/null)
  [ -z "$project_name" ] && project_name=$(basename "$CWD")

  local tech_stack
  tech_stack=$(echo "$devbooks_ctx" | jq -r '.project_profile.tech_stack // []')
  # 如果 DevBooks 没有技术栈，从 package.json 推断
  if [ "$tech_stack" = "[]" ] && [ -f "$CWD/package.json" ]; then
    local has_ts=false
    [ -f "$CWD/tsconfig.json" ] && has_ts=true
    if [ "$has_ts" = true ]; then
      tech_stack='["Node.js", "TypeScript"]'
    else
      tech_stack='["Node.js"]'
    fi
  fi

  local key_constraints
  key_constraints=$(echo "$devbooks_ctx" | jq -r '.project_profile.key_constraints // []')

  local architecture
  architecture=$(echo "$devbooks_ctx" | jq -r '.project_profile.architecture // "unknown"')
  [ "$architecture" = "null" ] && architecture="unknown"

  local project_profile
  project_profile=$(jq -n \
    --arg name "$project_name" \
    --argjson tech_stack "$tech_stack" \
    --arg architecture "$architecture" \
    --argjson key_constraints "$key_constraints" \
    '{
      name: $name,
      tech_stack: $tech_stack,
      architecture: $architecture,
      key_constraints: $key_constraints
    }')

  # 3. 构建 current_state
  local index_status
  index_status=$(get_index_status)

  local hotspot_files
  hotspot_files=$(get_hotspot_files_json 5)

  local recent_commits
  recent_commits=$(get_recent_commits_json 3)

  local current_state
  current_state=$(jq -n \
    --arg index_status "$index_status" \
    --argjson hotspot_files "$hotspot_files" \
    --argjson recent_commits "$recent_commits" \
    '{
      index_status: $index_status,
      hotspot_files: $hotspot_files,
      recent_commits: $recent_commits
    }')

  # 4. 构建 task_context
  local intent_4d
  intent_4d=$(analyze_intent_4d "$prompt")

  local intent_analysis
  intent_analysis=$(map_intent_to_standard "$intent_4d")

  local primary_intent
  primary_intent=$(echo "$intent_analysis" | jq -r '.primary_intent')

  # 提取符号并搜索相关代码片段
  local symbols
  symbols=$(extract_symbols "$prompt")

  local relevant_snippets='[]'
  if [ -n "$symbols" ]; then
    local first_symbol
    first_symbol=$(echo "$symbols" | head -1)
    if [ -n "$first_symbol" ]; then
      local snippet_result
      snippet_result=$(search_symbol "$first_symbol")
      if [ -n "$snippet_result" ]; then
        local first_file
        # 提取文件名（冒号前的部分，去掉行号等信息）
        first_file=$(echo "$snippet_result" | head -1 | sed 's/:.*//' | sed 's/-[0-9]*$//')
        if [ -n "$first_file" ] && [ ! "$first_file" = "$snippet_result" ]; then
          relevant_snippets=$(jq -n --arg file "$first_file" '[{"file": $file, "relevance": 0.8}]')
        fi
      fi
    fi
  fi

  local task_context
  task_context=$(jq -n \
    --argjson intent_analysis "$intent_analysis" \
    --argjson relevant_snippets "$relevant_snippets" \
    '{
      intent_analysis: $intent_analysis,
      relevant_snippets: $relevant_snippets,
      call_chains: []
    }')

  # 5. 构建 recommended_tools
  local recommended_tools
  recommended_tools=$(get_recommended_tools "$primary_intent" "$symbols")

  # 6. 构建 constraints
  local architectural_constraints
  architectural_constraints=$(echo "$devbooks_ctx" | jq -r '.constraints.architectural // []')

  local security_constraints
  security_constraints=$(get_security_constraints)

  local constraints
  constraints=$(jq -n \
    --argjson architectural "$architectural_constraints" \
    --argjson security "$security_constraints" \
    '{
      architectural: $architectural,
      security: $security
    }')

  # 组合最终输出
  jq -n \
    --argjson project_profile "$project_profile" \
    --argjson current_state "$current_state" \
    --argjson task_context "$task_context" \
    --argjson recommended_tools "$recommended_tools" \
    --argjson constraints "$constraints" \
    '{
      project_profile: $project_profile,
      current_state: $current_state,
      task_context: $task_context,
      recommended_tools: $recommended_tools,
      constraints: $constraints
    }'
}

# 构建文本格式输出
build_text_output() {
  local json_output="$1"

  local output=""

  # 项目画像
  output+="=== 项目画像 ===\n"
  output+="名称: $(echo "$json_output" | jq -r '.project_profile.name')\n"
  output+="技术栈: $(echo "$json_output" | jq -r '.project_profile.tech_stack | join(", ")')\n"
  output+="架构: $(echo "$json_output" | jq -r '.project_profile.architecture')\n"

  # 当前状态
  output+="\n=== 当前状态 ===\n"
  output+="索引状态: $(echo "$json_output" | jq -r '.current_state.index_status')\n"
  output+="热点文件:\n"
  # 使用 process substitution 避免子 shell 变量丢失问题
  local hotspot_list
  hotspot_list=$(echo "$json_output" | jq -r '.current_state.hotspot_files[]' 2>/dev/null)
  if [ -n "$hotspot_list" ]; then
    while IFS= read -r file; do
      [ -n "$file" ] && output+="  - $file\n"
    done <<< "$hotspot_list"
  fi
  output+="最近提交:\n"
  local commits_list
  commits_list=$(echo "$json_output" | jq -r '.current_state.recent_commits[]' 2>/dev/null)
  if [ -n "$commits_list" ]; then
    while IFS= read -r commit; do
      [ -n "$commit" ] && output+="  - $commit\n"
    done <<< "$commits_list"
  fi

  # 任务上下文
  output+="\n=== 任务上下文 ===\n"
  output+="主要意图: $(echo "$json_output" | jq -r '.task_context.intent_analysis.primary_intent')\n"
  output+="置信度: $(echo "$json_output" | jq -r '.task_context.intent_analysis.confidence')\n"

  # 推荐工具
  output+="\n=== 推荐工具 ===\n"
  local tools_list
  tools_list=$(echo "$json_output" | jq -r '.recommended_tools[] | "  - \(.tool): \(.reason)"' 2>/dev/null)
  if [ -n "$tools_list" ]; then
    output+="$tools_list\n"
  fi

  # 约束
  output+="\n=== 约束 ===\n"
  local arch_constraints
  arch_constraints=$(echo "$json_output" | jq -r '.constraints.architectural[]' 2>/dev/null)
  if [ -n "$arch_constraints" ]; then
    while IFS= read -r c; do
      [ -n "$c" ] && output+="  - $c\n"
    done <<< "$arch_constraints"
  fi
  local sec_constraints
  sec_constraints=$(echo "$json_output" | jq -r '.constraints.security[]' 2>/dev/null)
  if [ -n "$sec_constraints" ]; then
    while IFS= read -r c; do
      [ -n "$c" ] && output+="  - $c\n"
    done <<< "$sec_constraints"
  fi

  printf '%b' "$output"
}

# 添加 Graph-RAG 上下文（或降级到关键词搜索）
add_graph_context() {
  local context="$1"
  local symbols="$2"
  local graph_context=""
  local snippets=""

  # 尝试 Graph-RAG（如果启用且工具可用）
  if [ "$GRAPH_RAG_ENABLED" = "true" ]; then
    graph_context=$(call_graph_rag "$PROMPT")
    if [ -n "$graph_context" ]; then
      context="${context}

📊 Graph-RAG 上下文：
$graph_context"
    fi
  fi

  # 如果 Graph-RAG 未启用或失败，降级到关键词搜索
  if [ -z "$graph_context" ] && [ -n "$symbols" ]; then
    snippets=$(do_search "$symbols")
    if [ -z "$graph_context" ] && [ "$GRAPH_RAG_ENABLED" = "true" ]; then
      # Graph-RAG 失败，记录降级
      [ -z "$FALLBACK_REASON" ] && FALLBACK_REASON="graph_rag_unavailable"
      [ -z "$FALLBACK_DEGRADED_TO" ] && FALLBACK_DEGRADED_TO="keyword"
    fi
  fi

  if [ -n "$snippets" ]; then
    context="${context}

📦 相关代码：$snippets"
  fi

  # 添加热点文件
  local hotspots
  hotspots=$(get_hotspots)
  if [ -n "$hotspots" ]; then
    context="${context}

🔥 热点文件：
$hotspots"
  fi

  echo "$context"
}

# 添加降级信息和工具提示
add_fallback_info() {
  local context="$1"

  context="${context}

💡 可用工具：analyzeImpact / findReferences / getCallGraph"

  # 添加降级信息（如果有）
  if [ -n "$FALLBACK_REASON" ]; then
    context="${context}

⚠️ 降级模式：${FALLBACK_REASON} → ${FALLBACK_DEGRADED_TO}"
  fi

  echo "$context"
}

# 输出 Hook 响应 JSON
output_hook_response() {
  local context="$1"
  jq -n --arg ctx "$context" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": $ctx
      }
    }'
}

# 空响应
empty_response() {
  echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":""}}'
}

# ==================== CLI 模式入口 ====================
# 处理 --analyze-intent 等 CLI 模式命令
if [ "$CLI_MODE" = "analyze-intent" ]; then
  # 如果没有 prompt，使用文件和函数信息构造
  if [ -z "$PROMPT" ]; then
    if [ -n "$CLI_FILE" ]; then
      PROMPT="file: $CLI_FILE"
      [ -n "$CLI_LINE" ] && PROMPT="$PROMPT at line $CLI_LINE"
    fi
    if [ -n "$CLI_FUNCTION" ]; then
      PROMPT="${PROMPT:+$PROMPT }function: $CLI_FUNCTION"
    fi
  fi

  # 执行 4 维意图分析
  if [ -z "$PROMPT" ]; then
    echo '{"error": "No prompt or file specified"}'
    exit 1
  fi

  # 构建分析结果
  result=$(analyze_intent_4d "$PROMPT")

  # 添加额外信号（来自命令行参数）
  if [ -n "$CLI_FILE" ]; then
    result=$(echo "$result" | jq --arg f "$CLI_FILE" '.signals += [{type: "implicit", match: $f, weight: 0.6}]')
  fi
  if [ -n "$CLI_FUNCTION" ]; then
    result=$(echo "$result" | jq --arg fn "$CLI_FUNCTION" '.signals += [{type: "code", match: $fn, weight: 0.7}]')
  fi
  if [ "$CLI_WITH_HISTORY" = true ]; then
    result=$(echo "$result" | jq '.signals += [{type: "historical", match: "with-history", weight: 0.6}]')
  fi

  if [ "$CLI_FORMAT" = "text" ]; then
    echo "Intent Analysis:"
    echo "  explicit:    $(echo "$result" | jq -r '.weights.explicit')"
    echo "  implicit:    $(echo "$result" | jq -r '.weights.implicit')"
    echo "  historical:  $(echo "$result" | jq -r '.weights.historical')"
    echo "  code:        $(echo "$result" | jq -r '.weights.code')"
    echo "  dominant:    $(echo "$result" | jq -r '.dominant_dimension')"
    echo "Signals:"
    echo "$result" | jq -r '.signals[] | "  - \(.type): \(.match) (weight: \(.weight))"'
  else
    echo "$result"
  fi
  exit 0
fi

# ==================== 主入口 ====================
main() {
  # 结构化输出模式（当 --format json 且有 prompt 时）
  # 这是 MP7/MP8 的主要输出模式
  if [ "$CLI_FORMAT" = "json" ] && [ -n "$PROMPT" ]; then
    # 构建 5 层结构化输出
    local structured_output
    structured_output=$(build_structured_output "$PROMPT")

    # 直接输出结构化 JSON（不包装在 hookSpecificOutput 中）
    echo "$structured_output"
    exit 0
  fi

  # 文本格式输出模式
  if [ "$CLI_FORMAT" = "text" ] && [ -n "$PROMPT" ]; then
    local structured_output
    structured_output=$(build_structured_output "$PROMPT")

    # 输出文本格式
    build_text_output "$structured_output"
    exit 0
  fi

  # 非代码意图快速退出（原有 Hook 模式）
  is_non_code "$PROMPT" && { empty_response; exit 0; }

  # 加载项目配置
  load_project_config

  # 设置 Embedding（检测索引 + 自动构建）
  setup_embedding

  # 检查是否有 @引用 - 有 @引用时跳过代码意图检测
  local AT_REFS
  AT_REFS=$(extract_at_refs "$PROMPT")
  local HAS_AT_REFS=false
  [ -n "$AT_REFS" ] && HAS_AT_REFS=true

  # 无 @引用时检查代码意图
  if [ "$HAS_AT_REFS" = false ]; then
    is_code_intent "$PROMPT" || { empty_response; exit 0; }
  fi

  # 构建上下文（使用子函数）
  local CONTEXT
  CONTEXT=$(build_base_context "$AT_REFS")

  # 提取符号
  local SYMBOLS
  SYMBOLS=$(extract_symbols "$PROMPT")

  # 添加 Graph-RAG 或搜索结果
  CONTEXT=$(add_graph_context "$CONTEXT" "$SYMBOLS")

  # 添加降级信息和工具提示
  CONTEXT=$(add_fallback_info "$CONTEXT")

  # 输出响应
  output_hook_response "$CONTEXT"
}

# 带总超时执行 - 直接调用 main（内部搜索已有独立超时）
main
