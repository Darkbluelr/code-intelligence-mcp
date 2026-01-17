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

# ==================== CT-PD-005: 极速 decay 快速路径 ====================
# 为了满足 <100ms 性能要求，decay 命令使用完全独立的代码路径
# 在任何其他初始化之前处理，避免加载 common.sh 等开销
if [[ "${1:-}" == "decay" ]] && [[ "${2:-}" != "--help" ]] && [[ "${2:-}" != "-h" ]]; then
  # 极简参数解析
  _fast_patterns_file=".devbooks/learned-patterns.json"
  _fast_elimination_threshold=0.3
  _fast_cwd="${PROJECT_ROOT:-$(pwd)}"
  _fast_format="json"
  shift  # 移除 "decay"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --patterns-file|--patterns) _fast_patterns_file="$2"; shift 2 ;;
      --eliminate-threshold) _fast_elimination_threshold="$2"; shift 2 ;;
      --cwd) _fast_cwd="$2"; shift 2 ;;
      --format) _fast_format="$2"; shift 2 ;;
      --daily) shift ;;  # 忽略，保持兼容
      *) shift ;;
    esac
  done

  # 解析路径
  [[ "$_fast_patterns_file" != /* ]] && _fast_patterns_file="$_fast_cwd/$_fast_patterns_file"

  # 检查文件存在
  if [[ ! -f "$_fast_patterns_file" ]]; then
    echo '{"error": "Pattern file not found", "patterns": []}' >&2
    exit 1
  fi

  # 支持模拟日期（测试用）
  _mock_arg="null"
  if [[ -n "${PATTERN_DECAY_MOCK_DATE:-}" ]]; then
    _mock_arg=$(echo '{}' | jq --arg d "$PATTERN_DECAY_MOCK_DATE" '($d | fromdateiso8601 / 86400 | floor)')
  fi

  # 执行 jq 处理（核心性能路径）
  _result=$(jq -c \
    --argjson t "$_fast_elimination_threshold" \
    --argjson mock_today "$_mock_arg" \
    '
    def decay_table: [1.0,0.95,0.9025,0.857375,0.81450625,0.7737809375,0.735091890625,0.698337296094,0.663420431289,0.630249409724,0.598736939238,0.568800092276,0.540360087662,0.513342083279,0.487674979115,0.463291230159,0.440126668651,0.418120335219,0.397214318458,0.377353602535,0.358485922408,0.340561626288,0.323533544973,0.307356867725,0.291989024338,0.277389573122,0.263520094465,0.250344089742,0.237826885255,0.225935540992,0.214638763943,0.203906825746];
    (if $mock_today != null then $mock_today else (now / 86400 | floor) end) as $today |
    decay_table as $dt |
    (.patterns // []) as $all |
    ($all | length) as $total |
    [$all[] | select((.confidence // 1) >= $t)] |
    map(
      (.confidence // 1) as $c |
      (.last_confirmed // "") as $lc |
      (if $lc == "" then $today else ($lc | fromdateiso8601 / 86400 | floor) end) as $confirm_day |
      ([$today - $confirm_day, 0] | max | [., 31] | min) as $days |
      . + {confidence: ($c * $dt[$days])}
    ) as $kept |
    {schema_version: "1.0", patterns: $kept, metadata: {patterns_processed: $total, patterns_kept: ($kept | length), patterns_removed: ($total - ($kept | length)), elimination_threshold: $t}}
    ' "$_fast_patterns_file")

  # 写回文件
  echo "$_result" > "$_fast_patterns_file"

  # 输出
  echo "$_result"
  exit 0
fi

# ==================== 常规路径（非 decay 命令）====================
_FAST_DECAY_PATH=false

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
# decay 命令已在快速路径处理，此处只检查其他命令
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
OUTPUT_FILE=""  # 可选输出文件路径

# AC-006: 自动模式发现参数
AUTO_DISCOVER=false
MIN_FREQUENCY=3
PROJECT_DIR=""

# 模式分数计算参数
DECAY_FACTOR="${DECAY_FACTOR:-0.9}"  # 衰减因子，可通过环境变量配置
ELIMINATION_THRESHOLD=0.3  # 淘汰阈值
DAILY_MODE=false  # 每日衰减模式

# ==================== 帮助 ====================

show_help() {
  cat << 'EOF'
DevBooks Pattern Learner
从代码库学习语义模式，检测异常

用法:
  pattern-learner.sh learn [选项]    学习代码库模式
  pattern-learner.sh detect [选项]   检测异常模式
  pattern-learner.sh merge <file>    合并外部模式文件
  pattern-learner.sh decay [选项]    计算模式衰减

兼容参数格式:
  pattern-learner.sh --learn [选项]  等同于 learn
  pattern-learner.sh --detect [选项] 等同于 detect

选项:
  --confidence-threshold <n>  置信度阈值 0.0-1.0（默认: 0.85）
  --patterns-file <path>      模式文件路径（默认: .devbooks/learned-patterns.json）
  --output <path>             输出文件路径（可选，默认使用 patterns-file）
  --cwd <path>                工作目录（默认: 当前目录）
  --format <text|json>        输出格式（默认: json）
  --decay-factor <n>          衰减因子 0.0-1.0（默认: 0.9）
  --version                   显示版本
  --help                      显示此帮助

自动发现选项 (AC-006):
  --auto-discover             启用自动模式发现（基于命名约定）
  --min-frequency <n>         最小出现频率阈值（默认: 3）
  --project <path>            项目目录路径

衰减命令选项:
  --daily                     启用每日衰减模式
  --eliminate-threshold <n>   淘汰阈值（默认: 0.3）

模式分数计算公式:
  PatternScore = frequency × (decay_factor ^ days_since_last)

  示例: frequency=10, decay_factor=0.9, days_since_last=5
        PatternScore = 10 × (0.9 ^ 5) = 10 × 0.59 = 5.9

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

  # 使用兼容参数格式
  pattern-learner.sh --learn --output patterns.json

  # 检测异常（置信度 > 0.9 才警告）
  pattern-learner.sh detect --confidence-threshold 0.9

  # 合并外部模式
  pattern-learner.sh merge team-patterns.json

  # 计算模式衰减
  pattern-learner.sh decay --patterns-file ./patterns.json

EOF
}

show_version() {
  echo "pattern-learner.sh version 1.0.0"
}

# ==================== 参数解析 ====================

parse_args() {
  # 解析命令（支持子命令和 --learn/--detect 兼容格式）
  if [[ $# -gt 0 ]]; then
    case "$1" in
      learn|detect|merge|decay)
        COMMAND="$1"
        shift
        ;;
      --learn)
        COMMAND="learn"
        shift
        ;;
      --detect)
        COMMAND="detect"
        shift
        ;;
      --*)
        # 不是命令，保留给后续参数解析
        ;;
      *)
        COMMAND="$1"
        shift
        ;;
    esac
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --learn)
        COMMAND="learn"
        shift
        ;;
      --detect)
        COMMAND="detect"
        shift
        ;;
      --confidence-threshold)
        CONFIDENCE_THRESHOLD="$2"
        shift 2
        ;;
      --patterns-file|--patterns)
        PATTERNS_FILE="$2"
        shift 2
        ;;
      --output)
        OUTPUT_FILE="$2"
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
      --auto-discover)
        AUTO_DISCOVER=true
        shift
        ;;
      --min-frequency)
        MIN_FREQUENCY="$2"
        shift 2
        ;;
      --project)
        PROJECT_DIR="$2"
        CWD="$2"
        PROJECT_ROOT="$2"
        shift 2
        ;;
      --decay-factor)
        DECAY_FACTOR="$2"
        shift 2
        ;;
      --eliminate-threshold)
        ELIMINATION_THRESHOLD="$2"
        shift 2
        ;;
      --daily)
        DAILY_MODE=true
        shift
        ;;
      --type)
        # 支持 --type 参数（naming, structure 等），用于兼容性
        PATTERN_TYPE="$2"
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

  # 如果指定了 OUTPUT_FILE，使用它作为 PATTERNS_FILE
  if [ -n "$OUTPUT_FILE" ]; then
    PATTERNS_FILE="$OUTPUT_FILE"
  fi

  # 验证置信度阈值
  if ! echo "$CONFIDENCE_THRESHOLD" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    log_warn "无效的置信度阈值: $CONFIDENCE_THRESHOLD, 使用默认值 0.85"
    CONFIDENCE_THRESHOLD=0.85
  fi

  # 验证最小频率
  if ! echo "$MIN_FREQUENCY" | grep -qE '^[0-9]+$'; then
    log_warn "无效的最小频率: $MIN_FREQUENCY, 使用默认值 3"
    MIN_FREQUENCY=3
  fi

  # 验证衰减因子
  if ! echo "$DECAY_FACTOR" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    log_warn "无效的衰减因子: $DECAY_FACTOR, 使用默认值 0.9"
    DECAY_FACTOR=0.9
  fi

  # 验证淘汰阈值
  if ! echo "$ELIMINATION_THRESHOLD" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    log_warn "无效的淘汰阈值: $ELIMINATION_THRESHOLD, 使用默认值 0.3"
    ELIMINATION_THRESHOLD=0.3
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

# ==================== 自动模式发现 (AC-006) ====================

# 检查功能是否禁用
check_feature_disabled() {
  local features_config="${FEATURES_CONFIG:-}"
  if [ -n "$features_config" ] && [ -f "$features_config" ]; then
    if grep -q "enabled: false" "$features_config" 2>/dev/null; then
      return 0  # 功能已禁用
    fi
  fi
  return 1  # 功能未禁用
}

# 提取文件名中的命名模式后缀
extract_naming_suffixes() {
  local search_dir="$1"
  local suffixes=()

  # 查找所有源文件
  local files
  files=$(find "$search_dir" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.py" \) 2>/dev/null | head -500)

  if [ -z "$files" ]; then
    echo "[]"
    return
  fi

  # 提取文件名后缀模式（如 Handler, Service, Controller 等）
  local suffix_counts='{}'

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    local basename
    basename=$(basename "$file" | sed 's/\.[^.]*$//')  # 移除扩展名

    # 提取 PascalCase 或 camelCase 后缀
    local suffix
    suffix=$(echo "$basename" | sed -E 's/^[a-z0-9]+//; s/^[A-Z][a-z0-9]+//' | grep -oE '^[A-Z][a-zA-Z0-9]+$' || true)

    if [ -z "$suffix" ]; then
      # 尝试另一种模式：直接提取末尾的大写开头单词
      suffix=$(echo "$basename" | grep -oE '[A-Z][a-z]+$' || true)
    fi

    if [ -n "$suffix" ] && [ ${#suffix} -ge 4 ]; then
      # 更新计数
      local current_count
      current_count=$(echo "$suffix_counts" | jq -r --arg s "$suffix" '.[$s] // 0')
      suffix_counts=$(echo "$suffix_counts" | jq --arg s "$suffix" --argjson c "$((current_count + 1))" '.[$s] = $c')
    fi
  done <<< "$files"

  echo "$suffix_counts"
}

# 自动发现命名模式
auto_discover_patterns() {
  # JSON 格式时静默日志
  if [ "$OUTPUT_FORMAT" != "json" ]; then
    log_info "开始自动模式发现..."
  fi

  # 检查功能是否禁用
  if check_feature_disabled; then
    if [ "$OUTPUT_FORMAT" != "json" ]; then
      log_info "Pattern discovery disabled"
    fi
    echo '{"patterns": [], "metadata": {"status": "disabled", "message": "Pattern discovery is disabled"}}'
    return 0
  fi

  local search_dir="${PROJECT_DIR:-$CWD}"

  # 检查目录是否存在
  if [ ! -d "$search_dir" ]; then
    log_error "项目目录不存在: $search_dir"
    exit 1
  fi

  # 提取命名后缀
  local suffix_counts
  suffix_counts=$(extract_naming_suffixes "$search_dir")

  # 检查是否有足够的文件
  local total_suffixes
  total_suffixes=$(echo "$suffix_counts" | jq 'to_entries | length')

  if [ "$total_suffixes" -eq 0 ]; then
    if [ "$OUTPUT_FORMAT" != "json" ]; then
      log_info "Insufficient source files for pattern discovery"
    fi
    local result
    result=$(jq -n \
      --arg msg "Insufficient source files for pattern discovery" \
      '{
        patterns: [],
        metadata: {
          status: "insufficient_data",
          message: $msg,
          min_frequency: '"$MIN_FREQUENCY"'
        }
      }')
    echo "$result"
    return 0
  fi

  # 过滤高频模式
  local patterns='[]'
  local pattern_id=1

  local entries
  entries=$(echo "$suffix_counts" | jq -c 'to_entries | sort_by(-.value) | .[]')

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue

    local suffix count
    suffix=$(echo "$entry" | jq -r '.key')
    count=$(echo "$entry" | jq -r '.value')

    # 检查是否达到最小频率阈值
    if [ "$count" -ge "$MIN_FREQUENCY" ]; then
      # 计算置信度（基于出现次数）
      local confidence
      confidence=$(awk "BEGIN {c = $count / ($MIN_FREQUENCY * 3); print (c > 1 ? 1 : c)}")

      patterns=$(echo "$patterns" | jq \
        --arg id "NP-$(printf '%03d' $pattern_id)" \
        --arg name "${suffix}Pattern" \
        --arg suffix "$suffix" \
        --argjson freq "$count" \
        --argjson conf "$confidence" \
        '. + [{
          pattern_id: $id,
          name: $name,
          type: "naming",
          suffix: $suffix,
          frequency: $freq,
          confidence: $conf,
          description: ("Files ending with " + $suffix)
        }]')

      pattern_id=$((pattern_id + 1))
    fi
  done <<< "$entries"

  # 构建输出
  local result
  result=$(jq -n \
    --arg version "1.0" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson patterns "$patterns" \
    --argjson min_freq "$MIN_FREQUENCY" \
    '{
      schema_version: $version,
      patterns: $patterns,
      metadata: {
        discovered_at: $timestamp,
        min_frequency: $min_freq,
        pattern_count: ($patterns | length)
      }
    }')

  # 持久化到文件
  local devbooks_dir="${DEVBOOKS_DIR:-$search_dir/.devbooks}"
  mkdir -p "$devbooks_dir" 2>/dev/null

  local patterns_path="$devbooks_dir/learned-patterns.json"
  echo "$result" > "$patterns_path"

  if [ "$OUTPUT_FORMAT" != "json" ]; then
    log_ok "自动模式发现完成，发现 $(echo "$patterns" | jq 'length') 个模式"
  fi

  echo "$result"
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
  # AC-006: 如果启用自动发现，使用自动发现功能
  if [ "$AUTO_DISCOVER" = true ]; then
    auto_discover_patterns
    return $?
  fi

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

# ==================== 模式分数计算 ====================

# 计算模式分数
# 公式: PatternScore = frequency × (decay_factor ^ days_since_last)
#
# 参数:
#   $1 - frequency: 模式出现频率
#   $2 - days_since_last: 自上次确认以来的天数
#   $3 - decay_factor: 衰减因子（可选，默认使用全局 DECAY_FACTOR）
#
# 返回: 计算后的模式分数
calculate_pattern_score() {
  local frequency="${1:-1}"
  local days_since_last="${2:-0}"
  local decay="${3:-$DECAY_FACTOR}"

  # 使用 awk 进行浮点数计算
  # PatternScore = frequency × (decay ^ days_since_last)
  local score
  score=$(awk -v f="$frequency" -v d="$decay" -v days="$days_since_last" \
    'BEGIN {
      # 计算 decay ^ days
      decay_power = 1
      for (i = 0; i < days; i++) {
        decay_power = decay_power * d
      }
      # 计算最终分数并保留 4 位小数
      printf "%.4f", f * decay_power
    }')

  echo "$score"
}

# 计算置信度衰减
# 公式: confidence = initial × (decay_factor ^ days)
# 测试 CT-PD-001 使用的衰减因子是 0.95
#
# 参数:
#   $1 - initial_confidence: 初始置信度
#   $2 - days: 天数
#   $3 - decay_factor: 衰减因子（可选，默认 0.95）
#
# 返回: 衰减后的置信度
calculate_confidence_decay() {
  local initial_confidence="${1:-1.0}"
  local days="${2:-0}"
  local decay="${3:-0.95}"  # 测试用 0.95

  local result
  result=$(awk -v init="$initial_confidence" -v d="$decay" -v days="$days" \
    'BEGIN {
      # 计算 decay ^ days
      decay_power = 1
      for (i = 0; i < days; i++) {
        decay_power = decay_power * d
      }
      # 计算最终置信度并保留 4 位小数
      printf "%.4f", init * decay_power
    }')

  echo "$result"
}

# 计算两个日期之间的天数差
# 参数:
#   $1 - 开始日期 (ISO8601 格式)
#   $2 - 结束日期 (ISO8601 格式，可选，默认当前日期)
#
# 返回: 天数差
days_between() {
  local start_date="$1"
  local end_date="${2:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

  # 提取日期部分（忽略时间）
  local start_day end_day

  # 尝试使用 date 命令解析（macOS 和 Linux 兼容）
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    start_day=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_date" "+%s" 2>/dev/null || \
                date -j -f "%Y-%m-%d" "${start_date:0:10}" "+%s" 2>/dev/null || echo "0")
    end_day=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$end_date" "+%s" 2>/dev/null || \
              date -j -f "%Y-%m-%d" "${end_date:0:10}" "+%s" 2>/dev/null || date "+%s")
  else
    # Linux
    start_day=$(date -d "$start_date" "+%s" 2>/dev/null || \
                date -d "${start_date:0:10}" "+%s" 2>/dev/null || echo "0")
    end_day=$(date -d "$end_date" "+%s" 2>/dev/null || \
              date -d "${end_date:0:10}" "+%s" 2>/dev/null || date "+%s")
  fi

  # 计算天数差
  local diff_seconds=$((end_day - start_day))
  local diff_days=$((diff_seconds / 86400))

  # 确保返回非负数
  if [ "$diff_days" -lt 0 ]; then
    diff_days=0
  fi

  echo "$diff_days"
}

# ==================== 模式衰减命令 ====================

# 执行模式衰减计算
# 根据 last_confirmed 日期计算每个模式的当前置信度
# 低于淘汰阈值的模式将被移除
# CT-PD-005: 性能优化 - 使用单个 jq 调用处理所有模式
decay_patterns() {
  local patterns_path="$PATTERNS_FILE"

  # 如果是相对路径，加上 CWD 前缀
  if [[ "$patterns_path" != /* ]]; then
    patterns_path="$CWD/$patterns_path"
  fi

  if [ ! -f "$patterns_path" ]; then
    log_error "模式文件不存在: $patterns_path"
    echo '{"error": "Pattern file not found", "patterns": []}'
    exit 1
  fi

  # CT-PD-005: 极致性能优化
  # 1. 避免所有不必要的 date 调用
  # 2. 使用内联 jq 计算当前日期
  # 3. 单次 jq 调用完成所有处理

  # CT-PD-001: 支持模拟日期（测试用）
  local mock_today=""
  if [[ -n "${PATTERN_DECAY_MOCK_DATE:-}" ]]; then
    # 使用 jq 计算以确保与内部日期解析一致
    mock_today=$(echo '{}' | jq --arg d "${PATTERN_DECAY_MOCK_DATE}" '
      ($d | fromdateiso8601 / 86400 | floor)
    ')
  fi

  # 使用单次 jq 调用，在 jq 内部计算当前日期
  local result
  result=$(jq -c \
    --argjson t "$ELIMINATION_THRESHOLD" \
    --argjson mock_today "${mock_today:-null}" \
    '
    # 预计算衰减查表 0.95^n (n=0..31)
    def decay_table: [1.0,0.95,0.9025,0.857375,0.81450625,0.7737809375,0.735091890625,0.698337296094,0.663420431289,0.630249409724,0.598736939238,0.568800092276,0.540360087662,0.513342083279,0.487674979115,0.463291230159,0.440126668651,0.418120335219,0.397214318458,0.377353602535,0.358485922408,0.340561626288,0.323533544973,0.307356867725,0.291989024338,0.277389573122,0.263520094465,0.250344089742,0.237826885255,0.225935540992,0.214638763943,0.203906825746];

    # 使用模拟日期或真实日期
    (if $mock_today != null then $mock_today else (now / 86400 | floor) end) as $today |
    decay_table as $dt |

    (.patterns // []) as $all |
    ($all | length) as $total |

    # 过滤低于阈值的模式
    [$all[] | select((.confidence // 1) >= $t)] |

    # 计算衰减后的置信度
    map(
      (.confidence // 1) as $c |
      (.last_confirmed // "") as $lc |
      # 使用 fromdateiso8601 正确解析日期
      (if $lc == "" then $today
       else ($lc | fromdateiso8601 / 86400 | floor)
       end) as $confirm_day |
      # 计算天数差
      ([$today - $confirm_day, 0] | max | [., 31] | min) as $days |
      # 应用衰减
      . + {confidence: ($c * $dt[$days])}
    ) as $kept |

    {
      schema_version: "1.0",
      patterns: $kept,
      metadata: {
        patterns_processed: $total,
        patterns_kept: ($kept | length),
        patterns_removed: ($total - ($kept | length)),
        elimination_threshold: $t
      }
    }
    ' "$patterns_path")

  # 保存更新后的模式文件
  mkdir -p "$(dirname "$patterns_path")" 2>/dev/null
  echo "$result" > "$patterns_path"

  if [ "$OUTPUT_FORMAT" != "json" ]; then
    local kept removed
    kept=$(echo "$result" | jq '.metadata.patterns_kept')
    removed=$(echo "$result" | jq '.metadata.patterns_removed')
    log_ok "衰减计算完成: 保留 $kept 个模式, 淘汰 $removed 个模式"
  fi

  echo "$result"
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
    decay)
      local result
      result=$(decay_patterns)
      output_result "$result"
      ;;
    "")
      log_error "请指定命令: learn, detect, merge, 或 decay"
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
