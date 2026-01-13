#!/bin/bash
# DevBooks Pattern Learner
# 从代码库学习语义模式，检测异常
#
# 功能：
#   1. 学习：分析代码库提取常见模式
#   2. 检测：比对当前代码与已学习模式
#   3. 合并：加载已有模式并增量更新
#
# 用法：
#   pattern-learner.sh learn [选项]
#   pattern-learner.sh detect [选项]
#
# 验收标准：
#   AC-005: 学习到的模式写入 .devbooks/learned-patterns.json
# shellcheck disable=SC2034  # 未使用变量（配置项）

set -euo pipefail

# ==================== 配置 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CWD="${PROJECT_ROOT}"

# 加载共享工具库
COMMON_LIB="${SCRIPT_DIR}/common.sh"
if [ -f "$COMMON_LIB" ]; then
  LOG_PREFIX="PatternLearner"
  # shellcheck source=common.sh
  source "$COMMON_LIB"
else
  # 降级：内联日志函数
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
  log_info()  { echo -e "${BLUE}[PatternLearner]${NC} $1" >&2; }
  log_ok()    { echo -e "${GREEN}[PatternLearner]${NC} $1" >&2; }
  log_warn()  { echo -e "${YELLOW}[PatternLearner]${NC} $1" >&2; }
  log_error() { echo -e "${RED}[PatternLearner]${NC} $1" >&2; }
fi

# 检查必需依赖
if declare -f check_dependencies &>/dev/null; then
  check_dependencies jq || exit 2
else
  command -v jq &>/dev/null || { log_error "缺少依赖: jq"; exit 2; }
fi

# ==================== 功能开关检查 ====================
# Trace: AC-010
if declare -f is_feature_enabled &>/dev/null; then
  if ! is_feature_enabled "pattern_learner"; then
    log_warn "模式学习器功能已禁用 (features.pattern_learner: false)"
    echo '{"error": "Feature disabled", "message": "模式学习器功能已禁用"}'
    exit 0
  fi
fi

# 默认参数
COMMAND=""
CONFIDENCE_THRESHOLD=0.85
OUTPUT_FORMAT="json"
PATTERNS_FILE=".devbooks/learned-patterns.json"

# ==================== 帮助 ====================

show_help() {
  cat << 'EOF'
DevBooks Pattern Learner
从代码库学习语义模式，检测异常

用法:
  pattern-learner.sh learn [选项]    学习代码库模式
  pattern-learner.sh detect [选项]   检测异常模式
  pattern-learner.sh merge <file>    合并外部模式文件

选项:
  --confidence-threshold <n>  置信度阈值 0.0-1.0（默认: 0.85）
  --patterns-file <path>      模式文件路径（默认: .devbooks/learned-patterns.json）
  --cwd <path>                工作目录（默认: 当前目录）
  --format <text|json>        输出格式（默认: json）
  --version                   显示版本
  --help                      显示此帮助

输出格式 (JSON):
  {
    "schema_version": "1.0",
    "patterns": [
      {
        "id": "P-001",
        "name": "error_handling",
        "description": "try-catch 包裹 async 调用",
        "occurrences": 15,
        "confidence": 0.92,
        "examples": ["src/auth.ts:10", "src/api.ts:25"]
      }
    ],
    "anomalies": [
      {
        "file_path": "src/legacy.ts",
        "line": 45,
        "pattern_id": "P-001",
        "message": "缺少 try-catch 包裹"
      }
    ]
  }

示例:
  # 学习代码库模式
  pattern-learner.sh learn --cwd ./src

  # 检测异常（置信度 > 0.9 才警告）
  pattern-learner.sh detect --confidence-threshold 0.9

  # 合并外部模式
  pattern-learner.sh merge team-patterns.json

EOF
}

show_version() {
  echo "pattern-learner.sh version 1.0.0"
}

# ==================== 参数解析 ====================

parse_args() {
  # 解析命令
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    COMMAND="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confidence-threshold)
        CONFIDENCE_THRESHOLD="$2"
        shift 2
        ;;
      --patterns-file)
        PATTERNS_FILE="$2"
        shift 2
        ;;
      --cwd)
        CWD="$2"
        PROJECT_ROOT="$2"
        shift 2
        ;;
      --format)
        OUTPUT_FORMAT="$2"
        shift 2
        ;;
      --version)
        show_version
        exit 0
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        # 可能是 merge 的文件参数
        if [ "$COMMAND" = "merge" ] && [ -z "${MERGE_FILE:-}" ]; then
          MERGE_FILE="$1"
          shift
        else
          log_error "未知参数: $1"
          show_help
          exit 1
        fi
        ;;
    esac
  done

  # 验证置信度阈值
  if ! echo "$CONFIDENCE_THRESHOLD" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    log_warn "无效的置信度阈值: $CONFIDENCE_THRESHOLD, 使用默认值 0.85"
    CONFIDENCE_THRESHOLD=0.85
  fi
}

# ==================== 模式定义 ====================

# 预定义的代码模式规则
get_pattern_definitions() {
  cat << 'EOF'
[
  {
    "id": "P-001",
    "name": "async_try_catch",
    "description": "async 函数使用 try-catch 包裹",
    "regex": "async\\s+function.*\\{[^}]*try\\s*\\{",
    "languages": ["ts", "js"],
    "min_occurrences": 3
  },
  {
    "id": "P-002",
    "name": "error_logging",
    "description": "catch 块包含日志记录",
    "regex": "catch\\s*\\([^)]*\\)\\s*\\{[^}]*(console\\.error|log\\.error|logger\\.error)",
    "languages": ["ts", "js"],
    "min_occurrences": 3
  },
  {
    "id": "P-003",
    "name": "null_check",
    "description": "访问属性前检查 null/undefined",
    "regex": "(if\\s*\\([^)]*[!=]==?\\s*(null|undefined)|\\?\\.|\\?\\.)",
    "languages": ["ts", "js"],
    "min_occurrences": 5
  },
  {
    "id": "P-004",
    "name": "type_annotation",
    "description": "函数参数有类型注解",
    "regex": "function\\s+\\w+\\s*\\([^)]*:\\s*\\w+",
    "languages": ["ts"],
    "min_occurrences": 5
  },
  {
    "id": "P-005",
    "name": "docstring",
    "description": "函数有文档注释",
    "regex": "(\\/\\*\\*[\\s\\S]*?\\*\\/|\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?''')\\s*(async\\s+)?(function|def|class)",
    "languages": ["ts", "js", "py"],
    "min_occurrences": 3
  }
]
EOF
}

# ==================== 学习模式 ====================

# 搜索模式出现次数
count_pattern_occurrences() {
  local pattern="$1"
  local languages="$2"

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done

  if [ -z "$rg_cmd" ]; then
    echo "0"
    return
  fi

  # 构建类型参数
  local type_args=""
  for lang in $(echo "$languages" | jq -r '.[]'); do
    type_args="$type_args -t $lang"
  done

  # 搜索并计数
  local count
  # shellcheck disable=SC2086  # type_args 需要分词
  count=$("$rg_cmd" -c $type_args "$pattern" "$CWD" 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}') || echo "0"
  echo "${count:-0}"
}

# 获取模式示例
get_pattern_examples() {
  local pattern="$1"
  local languages="$2"
  local max_examples="${3:-3}"

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done

  if [ -z "$rg_cmd" ]; then
    echo "[]"
    return
  fi

  # 构建类型参数
  local type_args=""
  for lang in $(echo "$languages" | jq -r '.[]'); do
    type_args="$type_args -t $lang"
  done

  local examples='[]'
  local results
  # shellcheck disable=SC2086  # type_args 需要分词
  results=$("$rg_cmd" -n --max-count="$max_examples" $type_args "$pattern" "$CWD" 2>/dev/null | head -"$max_examples") || true

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local file_line
    file_line=$(echo "$line" | cut -d: -f1-2)
    file_line="${file_line#"$CWD"/}"
    examples=$(echo "$examples" | jq --arg e "$file_line" '. + [$e]')
  done <<< "$results"

  echo "$examples"
}

# 学习代码库模式
learn_patterns() {
  log_info "开始学习代码库模式..."

  local definitions
  definitions=$(get_pattern_definitions)

  local patterns='[]'
  local pattern_count
  pattern_count=$(echo "$definitions" | jq 'length')

  for ((i=0; i<pattern_count; i++)); do
    local definition
    definition=$(echo "$definitions" | jq ".[$i]")

    local id name description regex languages min_occurrences
    id=$(echo "$definition" | jq -r '.id')
    name=$(echo "$definition" | jq -r '.name')
    description=$(echo "$definition" | jq -r '.description')
    regex=$(echo "$definition" | jq -r '.regex')
    languages=$(echo "$definition" | jq '.languages')
    min_occurrences=$(echo "$definition" | jq -r '.min_occurrences')

    log_info "分析模式: $name"

    # 计数
    local occurrences
    occurrences=$(count_pattern_occurrences "$regex" "$languages")

    # 计算置信度（基于出现次数）
    local confidence
    if [ "$occurrences" -ge "$min_occurrences" ]; then
      # 置信度 = min(1.0, occurrences / (min_occurrences * 3))
      confidence=$(awk "BEGIN {c = $occurrences / ($min_occurrences * 3); print (c > 1 ? 1 : c)}")
    else
      confidence=$(awk "BEGIN {print $occurrences / $min_occurrences}")
    fi

    # 获取示例
    local examples
    examples=$(get_pattern_examples "$regex" "$languages" 3)

    # 添加到结果
    patterns=$(echo "$patterns" | jq \
      --arg id "$id" \
      --arg name "$name" \
      --arg desc "$description" \
      --argjson occ "$occurrences" \
      --argjson conf "$confidence" \
      --argjson examples "$examples" \
      '. + [{
        id: $id,
        name: $name,
        description: $desc,
        occurrences: $occ,
        confidence: $conf,
        examples: $examples
      }]')
  done

  # 构建输出
  local result
  result=$(jq -n \
    --arg version "1.0" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson patterns "$patterns" \
    '{
      schema_version: $version,
      learned_at: $timestamp,
      patterns: $patterns
    }')

  # 保存到文件
  local patterns_path="$CWD/$PATTERNS_FILE"
  mkdir -p "$(dirname "$patterns_path")" 2>/dev/null
  echo "$result" > "$patterns_path"

  log_ok "模式学习完成，保存到 $PATTERNS_FILE"

  echo "$result"
}

# ==================== 检测异常 ====================

# 检测违反模式的文件
# 对于高置信度模式，查找应该遵循但未遵循的代码位置
detect_pattern_violations() {
  local pattern_id="$1"
  local pattern_name="$2"
  local regex="$3"
  local languages="$4"

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done

  if [ -z "$rg_cmd" ]; then
    echo "[]"
    return
  fi

  local anomalies='[]'

  # 根据模式类型检测异常
  case "$pattern_name" in
    async_try_catch)
      # 查找没有 try-catch 的 async 函数
      local async_without_try
      # shellcheck disable=SC2086
      async_without_try=$("$rg_cmd" -n --max-count=5 -t ts -t js \
        'async\s+(function\s+\w+|\w+\s*=\s*async)' "$CWD" 2>/dev/null | \
        grep -v 'try\s*{' | head -5) || true

      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local file_path line_num
        file_path=$(echo "$line" | cut -d: -f1)
        file_path="${file_path#"$CWD"/}"
        line_num=$(echo "$line" | cut -d: -f2)

        anomalies=$(echo "$anomalies" | jq \
          --arg file "$file_path" \
          --argjson line "$line_num" \
          --arg pid "$pattern_id" \
          --arg msg "async 函数未使用 try-catch 包裹" \
          '. + [{
            file_path: $file,
            line: $line,
            pattern_id: $pid,
            message: $msg
          }]')
      done <<< "$async_without_try"
      ;;

    error_logging)
      # 查找空的 catch 块
      local empty_catch
      # shellcheck disable=SC2086
      empty_catch=$("$rg_cmd" -n --max-count=5 -t ts -t js \
        'catch\s*\([^)]*\)\s*\{\s*\}' "$CWD" 2>/dev/null | head -5) || true

      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local file_path line_num
        file_path=$(echo "$line" | cut -d: -f1)
        file_path="${file_path#"$CWD"/}"
        line_num=$(echo "$line" | cut -d: -f2)

        anomalies=$(echo "$anomalies" | jq \
          --arg file "$file_path" \
          --argjson line "$line_num" \
          --arg pid "$pattern_id" \
          --arg msg "catch 块为空，缺少错误日志记录" \
          '. + [{
            file_path: $file,
            line: $line,
            pattern_id: $pid,
            message: $msg
          }]')
      done <<< "$empty_catch"
      ;;

    *)
      # 其他模式暂不检测异常
      ;;
  esac

  echo "$anomalies"
}

# 检测不符合模式的代码
detect_anomalies() {
  local patterns_path="$CWD/$PATTERNS_FILE"

  if [ ! -f "$patterns_path" ]; then
    log_error "模式文件不存在: $PATTERNS_FILE"
    log_info "请先运行: pattern-learner.sh learn"
    exit 1
  fi

  log_info "开始检测异常模式..."

  local patterns_data
  patterns_data=$(cat "$patterns_path")

  local patterns
  patterns=$(echo "$patterns_data" | jq '.patterns // []')

  local anomalies='[]'
  local pattern_count
  pattern_count=$(echo "$patterns" | jq 'length')

  for ((i=0; i<pattern_count; i++)); do
    local pattern
    pattern=$(echo "$patterns" | jq ".[$i]")

    local id name confidence
    id=$(echo "$pattern" | jq -r '.id')
    name=$(echo "$pattern" | jq -r '.name')
    confidence=$(echo "$pattern" | jq -r '.confidence')

    # AC-005: 低于阈值的模式不产生警告
    local is_below_threshold
    is_below_threshold=$(awk "BEGIN {print ($confidence < $CONFIDENCE_THRESHOLD)}")
    if [ "$is_below_threshold" = "1" ]; then
      continue
    fi

    log_info "检查模式: $name (置信度: $confidence)"

    # 获取模式的正则表达式和语言
    local definitions
    definitions=$(get_pattern_definitions)

    local definition
    definition=$(echo "$definitions" | jq --arg id "$id" '.[] | select(.id == $id)')

    if [ -z "$definition" ] || [ "$definition" = "null" ]; then
      continue
    fi

    local regex languages
    regex=$(echo "$definition" | jq -r '.regex // ""')
    languages=$(echo "$definition" | jq '.languages // []')

    if [ -z "$regex" ]; then
      continue
    fi

    # 检测不遵循模式的文件
    local detected_anomalies
    detected_anomalies=$(detect_pattern_violations "$id" "$name" "$regex" "$languages")

    if [ -n "$detected_anomalies" ] && [ "$detected_anomalies" != "[]" ]; then
      anomalies=$(echo "$anomalies" | jq --argjson new "$detected_anomalies" '. + $new')
    fi
  done

  # 构建输出
  local result
  result=$(jq -n \
    --arg version "1.0" \
    --argjson patterns "$patterns" \
    --argjson anomalies "$anomalies" \
    --argjson threshold "$CONFIDENCE_THRESHOLD" \
    '{
      schema_version: $version,
      confidence_threshold: $threshold,
      patterns_checked: ($patterns | length),
      anomalies: $anomalies
    }')

  log_ok "异常检测完成"

  echo "$result"
}

# ==================== 合并模式 ====================

# 合并外部模式文件
merge_patterns() {
  local merge_file="$1"
  local patterns_path="$CWD/$PATTERNS_FILE"

  if [ ! -f "$merge_file" ]; then
    log_error "合并文件不存在: $merge_file"
    exit 1
  fi

  log_info "合并模式文件: $merge_file"

  local external_patterns
  external_patterns=$(cat "$merge_file")

  local existing_patterns='{"patterns":[]}'
  if [ -f "$patterns_path" ]; then
    existing_patterns=$(cat "$patterns_path")
  fi

  # 合并模式（以 ID 为键，外部覆盖本地）
  local merged
  merged=$(jq -n \
    --argjson existing "$existing_patterns" \
    --argjson external "$external_patterns" \
    '{
      schema_version: "1.0",
      learned_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
      patterns: (
        ($existing.patterns // []) + ($external.patterns // [])
        | group_by(.id)
        | map(last)
      )
    }')

  # 保存
  mkdir -p "$(dirname "$patterns_path")" 2>/dev/null
  echo "$merged" > "$patterns_path"

  local pattern_count
  pattern_count=$(echo "$merged" | jq '.patterns | length')

  log_ok "合并完成，共 $pattern_count 个模式"

  echo "$merged"
}

# ==================== 输出 ====================

output_result() {
  local result="$1"

  if [ "$OUTPUT_FORMAT" = "json" ]; then
    echo "$result"
  else
    # 文本格式
    local pattern_count
    pattern_count=$(echo "$result" | jq '.patterns | length // 0')

    echo "模式学习器结果"
    echo "==============="
    echo ""

    if [ "$pattern_count" -gt 0 ]; then
      echo "发现 $pattern_count 个模式:"
      echo ""

      for ((i=0; i<pattern_count; i++)); do
        local pattern
        pattern=$(echo "$result" | jq ".patterns[$i]")

        local id name occurrences confidence
        id=$(echo "$pattern" | jq -r '.id')
        name=$(echo "$pattern" | jq -r '.name')
        occurrences=$(echo "$pattern" | jq -r '.occurrences')
        confidence=$(echo "$pattern" | jq -r '.confidence')

        echo "[$id] $name"
        echo "    出现次数: $occurrences, 置信度: $confidence"
        echo ""
      done
    fi

    local anomaly_count
    anomaly_count=$(echo "$result" | jq '.anomalies | length // 0')

    if [ "$anomaly_count" -gt 0 ]; then
      echo "检测到 $anomaly_count 个异常:"
      echo ""

      for ((i=0; i<anomaly_count; i++)); do
        local anomaly
        anomaly=$(echo "$result" | jq ".anomalies[$i]")

        local file_path line message
        file_path=$(echo "$anomaly" | jq -r '.file_path')
        line=$(echo "$anomaly" | jq -r '.line')
        message=$(echo "$anomaly" | jq -r '.message')

        echo "  - $file_path:$line: $message"
      done
    fi
  fi
}

# ==================== 主函数 ====================

main() {
  parse_args "$@"

  case "$COMMAND" in
    learn)
      local result
      result=$(learn_patterns)
      output_result "$result"
      ;;
    detect)
      local result
      result=$(detect_anomalies)
      output_result "$result"
      ;;
    merge)
      if [ -z "${MERGE_FILE:-}" ]; then
        log_error "merge 命令需要指定文件"
        exit 1
      fi
      local result
      result=$(merge_patterns "$MERGE_FILE")
      output_result "$result"
      ;;
    "")
      log_error "请指定命令: learn, detect, 或 merge"
      show_help
      exit 1
      ;;
    *)
      log_error "未知命令: $COMMAND"
      show_help
      exit 1
      ;;
  esac
}

main "$@"
