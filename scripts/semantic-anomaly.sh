#!/bin/bash
# DevBooks Semantic Anomaly Detector
# 版本: 1.0.0
# 用途: 基于 pattern-learner 扩展，检测违反项目隐式规范的代码
#
# 验收标准:
#   AC-003: 召回率 >=80%，误报率 <20%
#
# 异常类型 (REQ-SA-001):
#   - MISSING_ERROR_HANDLER: 缺失错误处理
#   - INCONSISTENT_API_CALL: 不一致的 API 调用
#   - NAMING_VIOLATION: 命名约定违规
#   - MISSING_LOG: 缺失日志
#   - UNUSED_IMPORT: 未使用的导入
#   - DEPRECATED_PATTERN: 使用已废弃模式
#
# 使用方式:
#   semantic-anomaly.sh <path>                 检测指定路径
#   semantic-anomaly.sh --pattern <file> <path>  使用自定义模式文件
#   semantic-anomaly.sh --output json <path>   指定输出格式
#   semantic-anomaly.sh --threshold 0.8 <path> 设置置信度阈值
#
# shellcheck disable=SC2034  # 未使用变量（配置项）

set -euo pipefail

# RM-003: trap 清理机制，确保资源正确释放
_cleanup() {
  # 清理临时文件（如果有）
  if [[ -n "${_TEMP_FILES:-}" ]]; then
    for f in $_TEMP_FILES; do
      [[ -f "$f" ]] && rm -f "$f" 2>/dev/null || true
    done
  fi
  # 清理模式缓存文件（如果有）
  if [[ -n "${_PATTERN_CACHE:-}" ]] && [[ -f "$_PATTERN_CACHE" ]]; then
    rm -f "$_PATTERN_CACHE" 2>/dev/null || true
  fi
}
trap _cleanup EXIT INT TERM

# ==================== 脚本初始化 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CWD="${PROJECT_ROOT}"

# 加载共享工具库
COMMON_LIB="${SCRIPT_DIR}/common.sh"
if [ -f "$COMMON_LIB" ]; then
  LOG_PREFIX="SemanticAnomaly"
  # shellcheck source=common.sh
  source "$COMMON_LIB"
else
  # 降级：内联日志函数
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
  log_info()  { echo -e "${BLUE}[SemanticAnomaly]${NC} $1" >&2; }
  log_ok()    { echo -e "${GREEN}[SemanticAnomaly]${NC} $1" >&2; }
  log_warn()  { echo -e "${YELLOW}[SemanticAnomaly]${NC} $1" >&2; }
  log_error() { echo -e "${RED}[SemanticAnomaly]${NC} $1" >&2; }
fi

# 检查必需依赖
if declare -f check_dependencies &>/dev/null; then
  check_dependencies jq || exit 2
else
  command -v jq &>/dev/null || { log_error "缺少依赖: jq"; exit 2; }
fi

# ==================== 默认参数 ====================

OUTPUT_FORMAT="json"
OUTPUT_FILE=""
PATTERNS_FILE=""
CONFIDENCE_THRESHOLD=0.8
TARGET_PATH=""
VERBOSE=false
REPORT_MODE=false
FEEDBACK_MODE=false
FEEDBACK_FILE=""
FEEDBACK_LINE=""
FEEDBACK_STATUS=""
FORCE_ENABLE_ANOMALY=false

# Pattern Learner 配置
PATTERN_LEARNER_SCRIPT="${SCRIPT_DIR}/pattern-learner.sh"
PATTERN_LEARNER_DB="${PATTERN_LEARNER_DB:-.devbooks/learned-patterns.json}"

# 检测器开关（可通过配置禁用）
ENABLE_MISSING_ERROR_HANDLER=true
ENABLE_INCONSISTENT_API_CALL=true
ENABLE_NAMING_VIOLATION=true
ENABLE_MISSING_LOG=true
ENABLE_UNUSED_IMPORT=true
ENABLE_DEPRECATED_PATTERN=true

# 收集的异常
ANOMALIES_JSON='[]'

# ==================== 帮助文档 ====================

show_help() {
  cat << 'EOF'
DevBooks Semantic Anomaly Detector
基于 pattern-learner 扩展，检测违反项目隐式规范的代码

用法:
  semantic-anomaly.sh [选项] <路径>

选项:
 --pattern <file>       使用自定义模式文件
  --output <file|format> 输出文件（JSONL）或格式: json | text
  --threshold <0.0-1.0>  置信度阈值 (默认: 0.8)
  --verbose              显示详细输出
  --report               生成报告到 evidence/semantic-anomaly-report.md
  --feedback <file> <line> <feedback>
                         记录用户反馈 (normal/anomaly)
  --enable-anomaly-detection
                         忽略功能开关配置，强制启用检测
  --enable-all-features  忽略功能开关配置，强制启用所有功能
  --help                 显示此帮助
  --version              显示版本

异常类型:
  MISSING_ERROR_HANDLER   缺失错误处理 (async/await 无 try-catch)
  INCONSISTENT_API_CALL   不一致的 API 调用 (logger vs console.log)
  NAMING_VIOLATION        命名约定违规 (camelCase vs snake_case)
  MISSING_LOG             缺失日志 (关键操作无日志)
  UNUSED_IMPORT           未使用的导入
  DEPRECATED_PATTERN      使用已废弃模式 (callback vs async)

输出格式 (JSON):
  {
    "anomalies": [
      {
        "type": "MISSING_ERROR_HANDLER",
        "file": "src/api.ts",
        "line": 42,
        "severity": "warning",
        "message": "调用 fetch() 未处理可能的网络错误",
        "suggestion": "添加 try-catch 或 .catch() 处理",
        "pattern_source": "learned:error-handling-001"
      }
    ],
    "summary": {
      "total": 5,
      "by_type": {"MISSING_ERROR_HANDLER": 2, "NAMING_VIOLATION": 3},
      "by_severity": {"warning": 4, "info": 1}
    }
  }

示例:
  # 检测单个文件
  semantic-anomaly.sh src/api.ts

  # 检测目录
  semantic-anomaly.sh src/

  # 使用自定义模式
  semantic-anomaly.sh --pattern my-patterns.json src/

  # 设置高置信度阈值
  semantic-anomaly.sh --threshold 0.9 src/

EOF
}

show_version() {
  echo "semantic-anomaly.sh version 1.0.0"
}

# ==================== 参数解析 ====================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pattern)
        PATTERNS_FILE="$2"
        shift 2
        ;;
      --output)
        if [[ -z "${2:-}" ]]; then
          log_error "--output 需要参数"
          exit 1
        fi
        if [[ "$2" == "json" || "$2" == "text" ]]; then
          OUTPUT_FORMAT="$2"
        else
          OUTPUT_FILE="$2"
        fi
        shift 2
        ;;
      --threshold)
        CONFIDENCE_THRESHOLD="$2"
        shift 2
        ;;
      --report)
        REPORT_MODE=true
        shift
        ;;
      --feedback)
        FEEDBACK_MODE=true
        FEEDBACK_FILE="${2:-}"
        FEEDBACK_LINE="${3:-}"
        FEEDBACK_STATUS="${4:-}"
        shift 4
        ;;
      --enable-anomaly-detection)
        FORCE_ENABLE_ANOMALY=true
        shift
        ;;
      --enable-all-features)
        DEVBOOKS_ENABLE_ALL_FEATURES=1
        shift
        ;;
      --verbose|-v)
        VERBOSE=true
        shift
        ;;
      --version)
        show_version
        exit 0
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      -*)
        log_error "未知选项: $1"
        show_help
        exit 1
        ;;
      *)
        TARGET_PATH="$1"
        shift
        ;;
    esac
  done

  if [[ "$FEEDBACK_MODE" == "true" ]]; then
    if [[ -z "$FEEDBACK_FILE" || -z "$FEEDBACK_LINE" || -z "$FEEDBACK_STATUS" ]]; then
      log_error "--feedback 需要 <file> <line> <feedback>"
      exit 1
    fi
    return 0
  fi

  # 报告模式默认使用项目根目录
  if [[ "$REPORT_MODE" == "true" && -z "$TARGET_PATH" ]]; then
    TARGET_PATH="$PROJECT_ROOT"
  fi

  # 验证目标路径
  if [ -z "$TARGET_PATH" ]; then
    log_error "请指定检测路径"
    show_help
    exit 1
  fi

  if [ ! -e "$TARGET_PATH" ]; then
    log_error "路径不存在: $TARGET_PATH"
    exit 1
  fi

  # 验证置信度阈值
  if ! echo "$CONFIDENCE_THRESHOLD" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    log_warn "无效的置信度阈值: $CONFIDENCE_THRESHOLD, 使用默认值 0.8"
    CONFIDENCE_THRESHOLD=0.8
  fi
}

# ==================== Pattern Loader 模块 (T2.2) ====================

# 已加载的模式
LOADED_PATTERNS='[]'

# 从 pattern-learner.sh 加载已学习模式
# REQ-SA-002: 系统应与 pattern-learner.sh 集成
load_patterns_from_learner() {
  local patterns_path=""

  # 检查自定义模式文件（--pattern 参数优先）
  if [ -n "$PATTERNS_FILE" ]; then
    if [ -f "$PATTERNS_FILE" ]; then
      patterns_path="$PATTERNS_FILE"
    else
      log_warn "自定义模式文件不存在: $PATTERNS_FILE"
    fi
  fi

  # 如果没有自定义文件，检查环境变量或默认路径
  if [ -z "$patterns_path" ]; then
    # PATTERN_LEARNER_DB 可以是绝对路径或相对路径
    if [[ "$PATTERN_LEARNER_DB" == /* ]]; then
      # 绝对路径，直接使用
      patterns_path="$PATTERN_LEARNER_DB"
    else
      # 相对路径，基于 CWD
      patterns_path="$CWD/$PATTERN_LEARNER_DB"
    fi
  fi

  if [ -f "$patterns_path" ]; then
    local patterns
    patterns=$(jq -c '.patterns // []' "$patterns_path" 2>/dev/null || echo '[]')
    LOADED_PATTERNS="$patterns"
    if [ "$VERBOSE" = true ]; then
      log_info "从 $patterns_path 加载了 $(echo "$patterns" | jq 'length') 个模式"
    fi
  else
    if [ "$VERBOSE" = true ]; then
      log_info "未找到已学习模式文件，使用内置规则"
    fi
    LOADED_PATTERNS='[]'
  fi
}

# 检查是否有学习到的模式匹配当前检测
# 参数: $1 - 模式类型 (error_handling, naming, etc.)
# 返回: 匹配的模式 ID 或空
get_learned_pattern_id() {
  local pattern_type="$1"

  if [ "$LOADED_PATTERNS" = '[]' ]; then
    echo ""
    return
  fi

  local matched_pattern
  matched_pattern=$(echo "$LOADED_PATTERNS" | jq -r --arg type "$pattern_type" '
    [.[] | select(.type == $type or .name == $type)] | first | .id // ""
  ' 2>/dev/null)

  if [ -n "$matched_pattern" ] && [ "$matched_pattern" != "null" ]; then
    echo "learned:$matched_pattern"
  else
    echo ""
  fi
}

# ==================== 添加异常到结果 ====================

# 添加检测到的异常
# 参数: $1 - type, $2 - file, $3 - line, $4 - severity, $5 - message, $6 - suggestion, $7 - pattern_source
add_anomaly() {
  local type="$1"
  local file="$2"
  local line="$3"
  local severity="$4"
  local message="$5"
  local suggestion="${6:-}"
  local pattern_source="${7:-builtin}"

  ANOMALIES_JSON=$(echo "$ANOMALIES_JSON" | jq \
    --arg type "$type" \
    --arg file "$file" \
    --argjson line "$line" \
    --arg severity "$severity" \
    --arg message "$message" \
    --arg suggestion "$suggestion" \
    --arg pattern_source "$pattern_source" \
    '. + [{
      type: $type,
      file: $file,
      line: $line,
      severity: $severity,
      message: $message,
      suggestion: $suggestion,
      pattern_source: $pattern_source
    }]')
}

# ==================== 辅助函数 ====================

# 找到包含指定行的最近函数名
# 参数: $1 - 文件内容, $2 - 行号
# 返回: 函数名或空
get_enclosing_function_name() {
  local content="$1"
  local target_line="$2"

  # 从目标行向上查找最近的 function 声明
  local before_content
  before_content=$(echo "$content" | head -n "$target_line")

  # 查找所有函数声明行（从后向前）
  # 支持: function name(), async function name(), const name = () =>, const name = async () =>
  local func_line func_name=""

  # 获取所有函数声明行号和内容
  local func_declarations
  func_declarations=$(echo "$before_content" | grep -n 'function[[:space:]]\+[a-zA-Z_][a-zA-Z0-9_]*' 2>/dev/null | tail -1 || true)

  if [ -n "$func_declarations" ]; then
    func_line=$(echo "$func_declarations" | cut -d: -f2-)

    # 提取函数名（使用 extended regex）
    func_name=$(echo "$func_line" | sed -E 's/.*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
  fi

  # 如果没找到 function 格式，尝试 const name = 格式
  if [ -z "$func_name" ]; then
    func_declarations=$(echo "$before_content" | grep -n '[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=[[:space:]]*\(async[[:space:]]*\)\?(' 2>/dev/null | tail -1 || true)

    if [ -n "$func_declarations" ]; then
      func_line=$(echo "$func_declarations" | cut -d: -f2-)
      func_name=$(echo "$func_line" | sed -E 's/.*(const|let|var)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=.*/\2/')
    fi
  fi

  echo "$func_name"
}

# 检查指定行是否在嵌套函数内（函数定义在另一个函数或try块内）
# 参数: $1 - 文件内容, $2 - 行号
# 返回: true 如果在嵌套函数内，否则 false
is_in_nested_function() {
  local content="$1"
  local target_line="$2"

  local before_content
  before_content=$(echo "$content" | head -n "$target_line")

  # 计算函数声明数量
  local func_count
  func_count=$(echo "$before_content" | grep -c 'function\s\+[a-zA-Z_]' 2>/dev/null || true)
  func_count="${func_count:-0}"

  # 如果有多于1个函数声明，说明在嵌套函数内
  if [ "$func_count" -gt 1 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# 检查指定行的函数是否有自己的 try-catch 块
# 参数: $1 - 文件内容, $2 - 行号
# 返回: true 如果函数内有 try-catch，否则 false
function_has_own_try_catch() {
  local content="$1"
  local target_line="$2"

  local before_content
  before_content=$(echo "$content" | head -n "$target_line")

  # 找到最近的函数声明行号
  local func_line_num
  func_line_num=$(echo "$before_content" | grep -n 'function\s\+[a-zA-Z_]' 2>/dev/null | tail -1 | cut -d: -f1 || true)

  if [ -z "$func_line_num" ]; then
    echo "false"
    return
  fi

  # 获取从函数声明到当前行的内容
  local func_content
  func_content=$(echo "$content" | sed -n "${func_line_num},${target_line}p")

  # 在这个范围内检查 try-catch
  local try_count catch_count
  try_count=$(echo "$func_content" | grep -c 'try\s*{' 2>/dev/null || true)
  try_count="${try_count:-0}"
  catch_count=$(echo "$func_content" | grep -c 'catch\s*(' 2>/dev/null || true)
  catch_count="${catch_count:-0}"

  if [ "$try_count" -gt "$catch_count" ]; then
    echo "true"
  else
    echo "false"
  fi
}

# ==================== MISSING_ERROR_HANDLER 检测器 (T2.3) ====================

# R-005: 拆分辅助函数 - 检测未处理的 await 调用
# 参数: $1=file, $2=content
_detect_unhandled_await() {
  local file="$1"
  local content="$2"

  local await_lines
  await_lines=$(echo "$content" | grep -n 'await\s' 2>/dev/null | cut -d: -f1 || true)

  for line_num in $await_lines; do
    local is_in_try=false
    local before_content
    before_content=$(echo "$content" | head -n "$line_num")

    local try_count catch_count
    try_count=$(echo "$before_content" | grep -c 'try\s*{' 2>/dev/null || true)
    try_count="${try_count:-0}"
    catch_count=$(echo "$before_content" | grep -c 'catch\s*(' 2>/dev/null || true)
    catch_count="${catch_count:-0}"

    if [ "$try_count" -gt "$catch_count" ]; then
      is_in_try=true
    fi

    local current_line
    current_line=$(echo "$content" | sed -n "${line_num}p")
    if echo "$current_line" | grep -q '\.catch(' ; then
      is_in_try=true
    fi

    if [ "$is_in_try" = false ]; then
      local call_name
      call_name=$(echo "$current_line" | sed -n 's/.*await\s\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p' | head -1)
      call_name="${call_name:-async operation}"

      local enclosing_func
      enclosing_func=$(get_enclosing_function_name "$content" "$line_num")

      local pattern_source
      pattern_source=$(get_learned_pattern_id "error_handling")
      [ -z "$pattern_source" ] && pattern_source="builtin:async-try-catch"

      local message
      if [ -n "$enclosing_func" ]; then
        message="函数 ${enclosing_func} 中调用 ${call_name}() 未处理可能的错误"
      else
        message="调用 ${call_name}() 未处理可能的错误"
      fi

      add_anomaly \
        "MISSING_ERROR_HANDLER" \
        "$file" \
        "$line_num" \
        "error" \
        "$message" \
        "添加 try-catch 包裹或使用 .catch() 处理" \
        "$pattern_source"
    fi
  done
}

# R-005: 拆分辅助函数 - 检测未处理的 Promise rejection
_detect_unhandled_promise() {
  local file="$1"
  local content="$2"

  local promise_lines
  promise_lines=$(echo "$content" | grep -n '\.then\s*(' 2>/dev/null | grep -v '\.catch' | cut -d: -f1 || true)

  for line_num in $promise_lines; do
    local current_line
    current_line=$(echo "$content" | sed -n "${line_num}p")

    local next_lines
    next_lines=$(echo "$content" | tail -n "+$((line_num + 1))" | head -5)

    if ! echo "$next_lines" | grep -q '\.catch\s*(' && ! echo "$current_line" | grep -q '\.catch\s*('; then
      local before_content
      before_content=$(echo "$content" | head -n "$line_num")
      local try_count catch_count
      try_count=$(echo "$before_content" | grep -c 'try\s*{' 2>/dev/null || true)
      try_count="${try_count:-0}"
      catch_count=$(echo "$before_content" | grep -c 'catch\s*(' 2>/dev/null || true)
      catch_count="${catch_count:-0}"

      if [ "$try_count" -le "$catch_count" ]; then
        local pattern_source
        pattern_source=$(get_learned_pattern_id "error_handling")
        [ -z "$pattern_source" ] && pattern_source="builtin:promise-catch"

        add_anomaly \
          "MISSING_ERROR_HANDLER" \
          "$file" \
          "$line_num" \
          "warning" \
          "Promise 链缺少 .catch() 错误处理" \
          "添加 .catch() 处理 Promise rejection" \
          "$pattern_source"
      fi
    fi
  done
}

# R-005: 拆分辅助函数 - 检测裸 fetch() 调用
_detect_bare_fetch() {
  local file="$1"
  local content="$2"

  local bare_fetch_lines
  bare_fetch_lines=$(echo "$content" | grep -n 'fetch\s*(' 2>/dev/null | grep -v 'await\s*fetch' | grep -v '\.then' | grep -v '\.catch' | cut -d: -f1 || true)

  for line_num in $bare_fetch_lines; do
    local current_line
    current_line=$(echo "$content" | sed -n "${line_num}p")

    # 跳过变量赋值
    if echo "$current_line" | grep -qE '^\s*(const|let|var)\s+[a-zA-Z_]'; then
      continue
    fi

    local enclosing_func
    enclosing_func=$(get_enclosing_function_name "$content" "$line_num")

    local in_nested
    in_nested=$(is_in_nested_function "$content" "$line_num")

    local func_has_try
    func_has_try=$(function_has_own_try_catch "$content" "$line_num")

    local should_report=false
    if [ "$in_nested" = "true" ] && [ "$func_has_try" = "false" ]; then
      should_report=true
    fi

    if [ "$in_nested" = "false" ]; then
      local before_content
      before_content=$(echo "$content" | head -n "$line_num")
      local try_count catch_count
      try_count=$(echo "$before_content" | grep -c 'try\s*{' 2>/dev/null || true)
      try_count="${try_count:-0}"
      catch_count=$(echo "$before_content" | grep -c 'catch\s*(' 2>/dev/null || true)
      catch_count="${catch_count:-0}"

      if [ "$try_count" -le "$catch_count" ]; then
        should_report=true
      fi
    fi

    if [ "$should_report" = true ]; then
      local pattern_source
      pattern_source=$(get_learned_pattern_id "error_handling")
      [ -z "$pattern_source" ] && pattern_source="builtin:fetch-error"

      local message
      if [ -n "$enclosing_func" ]; then
        message="函数 ${enclosing_func} 中 fetch() 调用未处理可能的网络错误"
      else
        message="fetch() 调用未处理可能的网络错误"
      fi

      add_anomaly \
        "MISSING_ERROR_HANDLER" \
        "$file" \
        "$line_num" \
        "warning" \
        "$message" \
        "使用 await + try-catch 或 .then().catch() 处理" \
        "$pattern_source"
    fi
  done
}

# 检测缺失的错误处理
# REQ-SA-001: 检测缺失错误处理
# SC-SA-001: 检测缺失的 try-catch 块
detect_missing_error_handler() {
  local file="$1"

  if [ "$ENABLE_MISSING_ERROR_HANDLER" != true ]; then
    return
  fi

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done

  if [ -z "$rg_cmd" ]; then
    rg_cmd="grep -n"
  fi

  local content
  content=$(cat "$file" 2>/dev/null || true)

  if [ -z "$content" ]; then
    return
  fi

  # R-005: 使用辅助函数执行检测
  _detect_unhandled_await "$file" "$content"
  _detect_unhandled_promise "$file" "$content"
  _detect_bare_fetch "$file" "$content"
}

# ==================== INCONSISTENT_API_CALL 检测器 (T2.4) ====================

# 检测不一致的 API 调用模式
# REQ-SA-001: 检测不一致 API 调用
# SC-SA-002: 检测同一 API 的不同调用方式
detect_inconsistent_api_call() {
  local file="$1"

  if [ "$ENABLE_INCONSISTENT_API_CALL" != true ]; then
    return
  fi

  local content
  content=$(cat "$file" 2>/dev/null || true)

  if [ -z "$content" ]; then
    return
  fi

  # 检测 console.log vs logger 的使用
  # 如果项目中有 logger 但也使用了 console.log，视为不一致
  local has_logger_import
  has_logger_import=$(echo "$content" | grep -c "import.*logger\|require.*logger" 2>/dev/null || true)
  has_logger_import="${has_logger_import:-0}"

  if [ "$has_logger_import" -gt 0 ]; then
    # 有 logger 导入但使用了 console.log
    local console_lines
    console_lines=$(echo "$content" | grep -n 'console\.\(log\|warn\|error\|info\|debug\)' 2>/dev/null | cut -d: -f1 || true)

    for line_num in $console_lines; do
      local pattern_source
      pattern_source=$(get_learned_pattern_id "logging")
      [ -z "$pattern_source" ] && pattern_source="builtin:consistent-logging"

      add_anomaly \
        "INCONSISTENT_API_CALL" \
        "$file" \
        "$line_num" \
        "warning" \
        "使用 console.log 而非导入的 logger" \
        "使用 logger.info/warn/error 保持日志一致性" \
        "$pattern_source"
    done
  else
    # 没有 logger 导入，检测是否应该使用 logger
    # 通过检查目录中其他文件是否使用 logger 来判断
    local console_lines
    console_lines=$(echo "$content" | grep -n 'console\.\(log\|warn\|error\|info\)' 2>/dev/null | cut -d: -f1 || true)

    for line_num in $console_lines; do
      local pattern_source
      pattern_source=$(get_learned_pattern_id "logging")
      [ -z "$pattern_source" ] && pattern_source="builtin:console-usage"

      add_anomaly \
        "INCONSISTENT_API_CALL" \
        "$file" \
        "$line_num" \
        "info" \
        "使用 console 而非结构化 logger" \
        "考虑使用结构化 logger 提升可观测性" \
        "$pattern_source"
    done
  fi
}

# ==================== NAMING_VIOLATION 检测器 (T2.5) ====================

# 检测命名约定违规
# REQ-SA-001: 检测命名约定违规
# SC-SA-003: 检测驼峰/下划线命名混用
detect_naming_violation() {
  local file="$1"

  if [ "$ENABLE_NAMING_VIOLATION" != true ]; then
    return
  fi

  local content
  content=$(cat "$file" 2>/dev/null || true)

  if [ -z "$content" ]; then
    return
  fi

  # 检测 snake_case 变量（在 TypeScript/JavaScript 中通常使用 camelCase）
  local ext="${file##*.}"
  if [[ "$ext" == "ts" || "$ext" == "js" || "$ext" == "tsx" || "$ext" == "jsx" ]]; then
    # 查找 const/let/var 声明中的 snake_case 变量
    local snake_case_lines
    snake_case_lines=$(echo "$content" | grep -nE '(const|let|var)[[:space:]]+[a-z][a-z0-9]*_[a-z]' 2>/dev/null | cut -d: -f1 || true)

    for line_num in $snake_case_lines; do
      local current_line
      current_line=$(echo "$content" | sed -n "${line_num}p")

      # 提取变量名
      local var_name
      var_name=$(echo "$current_line" | sed -E 's/.*(const|let|var)[[:space:]]+([a-z][a-z0-9_]*).*/\2/')

      # 跳过全大写常量 (如 MAX_SIZE)
      if echo "$var_name" | grep -q '^[A-Z_]*$'; then
        continue
      fi

      local pattern_source
      pattern_source=$(get_learned_pattern_id "naming")
      [ -z "$pattern_source" ] && pattern_source="builtin:camelCase"

      # 生成建议的 camelCase 名称
      local suggested_name
      suggested_name=$(echo "$var_name" | sed 's/_\([a-z]\)/\U\1/g')

      add_anomaly \
        "NAMING_VIOLATION" \
        "$file" \
        "$line_num" \
        "warning" \
        "变量 '${var_name}' 使用 snake_case 命名" \
        "建议重命名为 camelCase: ${suggested_name}" \
        "$pattern_source"
    done

    # 检测 snake_case 函数名
    local snake_func_lines
    snake_func_lines=$(echo "$content" | grep -nE 'function[[:space:]]+[a-z][a-z0-9]*_[a-z]' 2>/dev/null | cut -d: -f1 || true)

    for line_num in $snake_func_lines; do
      local current_line
      current_line=$(echo "$content" | sed -n "${line_num}p")

      local func_name
      func_name=$(echo "$current_line" | sed -E 's/.*function[[:space:]]+([a-z][a-z0-9_]*).*/\1/')

      local pattern_source
      pattern_source=$(get_learned_pattern_id "naming")
      [ -z "$pattern_source" ] && pattern_source="builtin:camelCase"

      local suggested_name
      suggested_name=$(echo "$func_name" | sed 's/_\([a-z]\)/\U\1/g')

      add_anomaly \
        "NAMING_VIOLATION" \
        "$file" \
        "$line_num" \
        "warning" \
        "函数 '${func_name}' 使用 snake_case 命名" \
        "建议重命名为 camelCase: ${suggested_name}" \
        "$pattern_source"
    done
  fi
}

# ==================== MISSING_LOG 检测器 (T2.6) ====================

# 检测关键路径缺失日志
# REQ-SA-001: 检测缺失日志
detect_missing_log() {
  local file="$1"

  if [ "$ENABLE_MISSING_LOG" != true ]; then
    return
  fi

  local content
  content=$(cat "$file" 2>/dev/null || true)

  if [ -z "$content" ]; then
    return
  fi

  # 检测关键操作函数（payment, charge, transfer, delete, update 等）
  local critical_patterns=(
    "payment"
    "charge"
    "transfer"
    "delete"
    "remove"
    "update"
    "create"
    "insert"
  )

  for pattern in "${critical_patterns[@]}"; do
    # 查找包含关键词的函数定义
    # 支持: function payment(), async function payment(), const payment = async ()
    local func_lines
    func_lines=$(echo "$content" | grep -ni "\(async\s\+\)\?function\s\+[a-zA-Z_]*${pattern}[a-zA-Z_]*\|[a-zA-Z_]*${pattern}[a-zA-Z_]*\s*=\s*\(async\s*\)\?(" 2>/dev/null | cut -d: -f1 || true)

    for line_num in $func_lines; do
      # 获取函数体（简化：取后 20 行）
      local func_body
      func_body=$(echo "$content" | tail -n "+$line_num" | head -20)

      # 检查是否有日志记录
      local has_log
      has_log=$(echo "$func_body" | grep -c '\(console\.\|logger\.\|log\.\)\(info\|warn\|error\|debug\|log\)' 2>/dev/null || true)
      has_log="${has_log:-0}"

      if [ "$has_log" -eq 0 ]; then
        local current_line
        current_line=$(echo "$content" | sed -n "${line_num}p")

        local func_name
        func_name=$(echo "$current_line" | sed -n 's/.*function\s\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p')
        [ -z "$func_name" ] && func_name=$(echo "$current_line" | sed -n 's/.*\([a-zA-Z_][a-zA-Z0-9_]*\)\s*=.*/\1/p')
        func_name="${func_name:-critical operation}"

        local pattern_source
        pattern_source=$(get_learned_pattern_id "logging")
        [ -z "$pattern_source" ] && pattern_source="builtin:critical-logging"

        add_anomaly \
          "MISSING_LOG" \
          "$file" \
          "$line_num" \
          "warning" \
          "关键操作 '${func_name}' 缺失日志记录" \
          "添加入口/出口日志和错误日志" \
          "$pattern_source"
      fi
    done
  done

  # 检测空的 catch 块（无日志）
  local catch_lines
  catch_lines=$(echo "$content" | grep -n 'catch\s*(' 2>/dev/null | cut -d: -f1 || true)

  for line_num in $catch_lines; do
    # 获取 catch 块内容（简化：取后 5 行）
    local catch_body
    catch_body=$(echo "$content" | tail -n "+$line_num" | head -5)

    # 检查是否有日志或 throw
    local has_handling
    has_handling=$(echo "$catch_body" | grep -c '\(console\.\|logger\.\|log\.\|throw\)' 2>/dev/null || true)
    has_handling="${has_handling:-0}"

    if [ "$has_handling" -eq 0 ]; then
      local pattern_source
      pattern_source=$(get_learned_pattern_id "error_handling")
      [ -z "$pattern_source" ] && pattern_source="builtin:catch-logging"

      add_anomaly \
        "MISSING_LOG" \
        "$file" \
        "$line_num" \
        "warning" \
        "catch 块缺失错误日志记录" \
        "添加 logger.error 记录异常信息" \
        "$pattern_source"
    fi
  done
}

# ==================== UNUSED_IMPORT 检测器 ====================

# 检测未使用的导入
# REQ-SA-001: 检测未使用导入
detect_unused_import() {
  local file="$1"

  if [ "$ENABLE_UNUSED_IMPORT" != true ]; then
    return
  fi

  local content
  content=$(cat "$file" 2>/dev/null || true)

  if [ -z "$content" ]; then
    return
  fi

  # 提取 import 语句
  local import_lines
  import_lines=$(echo "$content" | grep -n '^import ' 2>/dev/null | head -50 || true)

  while IFS= read -r import_line; do
    [ -z "$import_line" ] && continue

    local line_num
    line_num=$(echo "$import_line" | cut -d: -f1)
    local line_content
    line_content=$(echo "$import_line" | cut -d: -f2-)

    # 提取导入的标识符
    local imported_names=""

    # 处理 import { a, b, c } from 'module' 格式
    if echo "$line_content" | grep -q '{'; then
      imported_names=$(echo "$line_content" | sed -E 's/.*\{[[:space:]]*//' | sed -E 's/[[:space:]]*\}.*//' | tr ',' '\n' | sed -E 's/[[:space:]]*as[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*//' | tr -d ' ')
    # 处理 import name from 'module' 格式
    elif echo "$line_content" | grep -q 'import [a-zA-Z_]'; then
      imported_names=$(echo "$line_content" | sed -E 's/import[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
    fi

    # 检查每个导入的标识符是否被使用
    for name in $imported_names; do
      [ -z "$name" ] && continue

      # 移除导入行后的内容中查找使用情况
      local remaining_content
      remaining_content=$(echo "$content" | tail -n "+$((line_num + 1))")

      # 排除注释行后检查使用情况
      # 只保留非注释行（简化：排除以 // 开头的行和 /* */ 块注释）
      local code_only
      code_only=$(echo "$remaining_content" | grep -v '^\s*//' | sed 's|//.*||g')

      # 使用 grep -w 进行单词边界匹配
      local usage_count
      usage_count=$(echo "$code_only" | grep -cw "${name}" 2>/dev/null || true)
      usage_count="${usage_count:-0}"

      if [ "$usage_count" -eq 0 ]; then
        local pattern_source
        pattern_source=$(get_learned_pattern_id "imports")
        [ -z "$pattern_source" ] && pattern_source="builtin:unused-import"

        add_anomaly \
          "UNUSED_IMPORT" \
          "$file" \
          "$line_num" \
          "info" \
          "导入 '${name}' 未被使用" \
          "移除未使用的导入以减少打包体积" \
          "$pattern_source"
      fi
    done
  done <<< "$import_lines"
}

# ==================== DEPRECATED_PATTERN 检测器 ====================

# 检测使用已废弃的代码模式
# REQ-SA-001: 检测废弃模式
detect_deprecated_pattern() {
  local file="$1"

  if [ "$ENABLE_DEPRECATED_PATTERN" != true ]; then
    return
  fi

  local content
  content=$(cat "$file" 2>/dev/null || true)

  if [ -z "$content" ]; then
    return
  fi

  # 检测 callback 风格的异步代码（应该使用 async/await）
  local callback_lines
  callback_lines=$(echo "$content" | grep -n '\.then[[:space:]]*(' 2>/dev/null | cut -d: -f1 || true)

  for line_num in $callback_lines; do
    local current_line
    current_line=$(echo "$content" | sed -n "${line_num}p")

    # 检查是否是旧式 callback 链（多个 .then）
    local next_lines
    next_lines=$(echo "$content" | tail -n "+$line_num" | head -10)

    # 计算 .then 出现的次数（不是行数）
    local then_count
    then_count=$(echo "$next_lines" | grep -o '\.then[[:space:]]*(' 2>/dev/null | wc -l || true)
    then_count=$(echo "$then_count" | tr -d ' ')
    then_count="${then_count:-0}"

    if [ "$then_count" -ge 2 ]; then
      local pattern_source
      pattern_source=$(get_learned_pattern_id "async_patterns")
      [ -z "$pattern_source" ] && pattern_source="builtin:async-await"

      add_anomaly \
        "DEPRECATED_PATTERN" \
        "$file" \
        "$line_num" \
        "info" \
        "使用 Promise 链而非 async/await" \
        "重构为 async/await 提升可读性" \
        "$pattern_source"
    fi
  done

  # 检测 var 声明（应该使用 const/let）
  local var_lines
  var_lines=$(echo "$content" | grep -nw 'var' 2>/dev/null | cut -d: -f1 || true)

  for line_num in $var_lines; do
    local pattern_source
    pattern_source=$(get_learned_pattern_id "variable_declaration")
    [ -z "$pattern_source" ] && pattern_source="builtin:const-let"

    add_anomaly \
      "DEPRECATED_PATTERN" \
      "$file" \
      "$line_num" \
      "info" \
      "使用 var 声明变量" \
      "使用 const 或 let 替代 var" \
      "$pattern_source"
  done
}

# ==================== 主检测函数 ====================

# 扫描单个文件
scan_file() {
  local file="$1"

  # 过滤非代码文件
  local ext="${file##*.}"
  case "$ext" in
    ts|tsx|js|jsx|mjs|cjs)
      ;;
    *)
      return
      ;;
  esac

  if [ "$VERBOSE" = true ]; then
    log_info "扫描文件: $file"
  fi

  # 运行所有检测器
  detect_missing_error_handler "$file"
  detect_inconsistent_api_call "$file"
  detect_naming_violation "$file"
  detect_missing_log "$file"
  detect_unused_import "$file"
  detect_deprecated_pattern "$file"
}

# 扫描目录
scan_directory() {
  local dir="$1"

  # 查找所有代码文件
  local files
  files=$(find "$dir" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    2>/dev/null)

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    scan_file "$file"
  done <<< "$files"
}

# ==================== Report Generator 模块 (T2.7) ====================

# 生成摘要
generate_summary() {
  local summary
  summary=$(echo "$ANOMALIES_JSON" | jq '{
    total: length,
    by_type: (group_by(.type) | map({key: .[0].type, value: length}) | from_entries),
    by_severity: (group_by(.severity) | map({key: .[0].severity, value: length}) | from_entries)
  }')

  echo "$summary"
}

write_anomalies_jsonl() {
  local output_file="$1"

  if [ -z "$output_file" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$output_file")"

  echo "$ANOMALIES_JSON" | jq -c '
    .[] | {
      file: .file,
      type: .type,
      confidence: (
        if .severity == "error" then 0.9
        elif .severity == "warning" then 0.7
        else 0.6
        end
      ),
      line: .line,
      description: (.message // "")
    }
  ' > "$output_file"
}

record_feedback() {
  local target_file="$1"
  local target_line="$2"
  local feedback="$3"

  if [ -z "$target_file" ] || [ -z "$target_line" ] || [ -z "$feedback" ]; then
    log_error "feedback 参数缺失"
    exit 1
  fi

  if ! [[ "$target_line" =~ ^[0-9]+$ ]]; then
    log_error "line 必须为数字: $target_line"
    exit 1
  fi

  local devbooks_dir="${DEVBOOKS_DIR:-.devbooks}"
  mkdir -p "$devbooks_dir"

  local output_file="${devbooks_dir}/semantic-anomaly-feedback.jsonl"
  local ts
  ts=$(date +%s)

  jq -cn \
    --arg file "$target_file" \
    --argjson line "$target_line" \
    --arg feedback "$feedback" \
    --argjson timestamp "$ts" \
    '{file: $file, line: $line, feedback: $feedback, timestamp: $timestamp}' >> "$output_file"
}

write_report() {
  local summary
  summary=$(generate_summary)

  local report_dir="${PROJECT_ROOT}/evidence"
  local report_file="${report_dir}/semantic-anomaly-report.md"
  mkdir -p "$report_dir"

  {
    echo "# Semantic Anomaly Report"
    echo ""
    echo "- Total: $(echo "$summary" | jq -r '.total')"
    echo "- By Type:"
    echo "$summary" | jq -r '.by_type | to_entries[] | "  - \(.key): \(.value)"'
    echo "- By Severity:"
    echo "$summary" | jq -r '.by_severity | to_entries[] | "  - \(.key): \(.value)"'
    echo ""
    echo "## Details"
    echo ""
    echo "$ANOMALIES_JSON" | jq -r '.[] | "- [\(.severity)] \(.file):\(.line) \(.type) - \(.message)"'
  } > "$report_file"
}

# 输出 JSON 格式报告
output_json() {
  local summary
  summary=$(generate_summary)

  jq -n \
    --argjson anomalies "$ANOMALIES_JSON" \
    --argjson summary "$summary" \
    '{
      anomalies: $anomalies,
      summary: $summary
    }'
}

# 输出文本格式报告
output_text() {
  local summary
  summary=$(generate_summary)

  echo "================================"
  echo "Semantic Anomaly Detection Report"
  echo "================================"
  echo ""
  echo "Summary:"
  echo "  Total anomalies: $(echo "$summary" | jq -r '.total')"
  echo ""
  echo "By Type:"
  echo "$summary" | jq -r '.by_type | to_entries[] | "  \(.key): \(.value)"'
  echo ""
  echo "By Severity:"
  echo "$summary" | jq -r '.by_severity | to_entries[] | "  \(.key): \(.value)"'
  echo ""
  echo "Details:"
  echo "--------"

  echo "$ANOMALIES_JSON" | jq -r '.[] | "\(.severity | ascii_upcase) \(.file):\(.line) [\(.type)]\n  \(.message)\n  Suggestion: \(.suggestion)\n"'
}

# ==================== 主函数 ====================

main() {
  parse_args "$@"

  if [[ "$FEEDBACK_MODE" == "true" ]]; then
    record_feedback "$FEEDBACK_FILE" "$FEEDBACK_LINE" "$FEEDBACK_STATUS"
    exit 0
  fi

  # 如果用户明确请求输出（--output, --report）或强制启用，则跳过功能开关检查
  local skip_feature_check=false
  if [[ "$FORCE_ENABLE_ANOMALY" == "true" || "$REPORT_MODE" == "true" || -n "$OUTPUT_FILE" ]]; then
    skip_feature_check=true
  fi

  if [[ "$skip_feature_check" != "true" ]] && declare -f is_feature_enabled &>/dev/null; then
    if ! is_feature_enabled "semantic_anomaly"; then
      echo '{"anomalies": [], "summary": {"total": 0, "by_type": {}, "by_severity": {}}, "metadata": {"status": "disabled"}}'
      exit 0
    fi
  fi

  # 加载模式
  load_patterns_from_learner

  # 执行扫描
  if [ -d "$TARGET_PATH" ]; then
    scan_directory "$TARGET_PATH"
  else
    scan_file "$TARGET_PATH"
  fi

  if [ -n "$OUTPUT_FILE" ]; then
    write_anomalies_jsonl "$OUTPUT_FILE"
  fi

  if [[ "$REPORT_MODE" == "true" ]]; then
    write_report
  fi

  # 输出报告
  case "$OUTPUT_FORMAT" in
    json)
      output_json
      ;;
    text)
      output_text
      ;;
    *)
      log_error "未知输出格式: $OUTPUT_FORMAT"
      exit 1
      ;;
  esac
}

main "$@"
