#!/bin/bash
# DevBooks Bug Locator
# 基于调用链 + 变更历史输出 Bug 候选位置推荐
#
# 功能：
#   1. 解析错误信息，提取相关符号
#   2. 调用链分析，获取相关代码位置
#   3. Git 历史关联，最近修改文件权重更高
#   4. 热点文件交叉，标记高风险区域
#
# 用法：
#   bug-locator.sh --error "错误信息" [选项]
#
# 验收标准：
#   AC-005: 输出 Top-5 候选列表，10 个预设 case 命中率 ≥ 60%
# shellcheck disable=SC2034  # 未使用变量（配置项）

set -euo pipefail

# ==================== 配置 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CWD="${PROJECT_ROOT}"

# 加载共享工具库
COMMON_LIB="${SCRIPT_DIR}/common.sh"
if [ -f "$COMMON_LIB" ]; then
  LOG_PREFIX="BugLocator"
  # shellcheck source=common.sh
  source "$COMMON_LIB"
else
  # 降级：内联日志函数
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
  log_info()  { echo -e "${BLUE}[BugLocator]${NC} $1" >&2; }
  log_ok()    { echo -e "${GREEN}[BugLocator]${NC} $1" >&2; }
  log_warn()  { echo -e "${YELLOW}[BugLocator]${NC} $1" >&2; }
  log_error() { echo -e "${RED}[BugLocator]${NC} $1" >&2; }
  float_calc() { echo "scale=${2:-2}; $1" | bc 2>/dev/null || awk "BEGIN {printf \"%.${2:-2}f\", $1}"; }
fi

# JSON 模式下抑制日志的包装函数
_maybe_log_info()  { [ "$OUTPUT_FORMAT" != "json" ] && log_info  "$1" || true; }
_maybe_log_warn()  { [ "$OUTPUT_FORMAT" != "json" ] && log_warn  "$1" || true; }
_maybe_log_error() { log_error "$1"; }  # 错误总是输出

# 检查必需依赖
if declare -f check_dependencies &>/dev/null; then
  check_dependencies jq || exit 2
else
  command -v jq &>/dev/null || { log_error "缺少依赖: jq"; exit 2; }
fi

# 默认参数
ERROR_INFO=""
TOP_N=5
HISTORY_DEPTH=30  # Git 历史天数

# 权重配置（可通过 config.yaml 覆盖）
WEIGHT_CALL_CHAIN=0.40
WEIGHT_HISTORY=0.30
WEIGHT_HOTSPOT=0.15
WEIGHT_ERROR_PATTERN=0.15

# 热点分析器路径
HOTSPOT_ANALYZER="${SCRIPT_DIR}/hotspot-analyzer.sh"

# 尝试从配置加载热点权重
_load_weight_config() {
  if declare -f get_feature_value &>/dev/null; then
    local w
    w=$(get_feature_value "hotspot_weight" "")
    if [ -n "$w" ]; then
      WEIGHT_HOTSPOT="$w"
    fi
  fi
}
_load_weight_config

# 模式
OUTPUT_FORMAT="json"

# ==================== 帮助 ====================

show_help() {
  cat << 'EOF'
DevBooks Bug Locator
基于调用链 + 变更历史输出 Bug 候选位置推荐

用法:
  bug-locator.sh --error "错误信息" [选项]

选项:
  --error <text>        错误信息（必需）
  --top-n <n>           返回候选数量（默认: 5）
  --history-depth <d>   Git 历史天数（默认: 30）
  --cwd <path>          工作目录（默认: 当前目录）
  --format <text|json>  输出格式（默认: json）
  --version             显示版本
  --help                显示此帮助

输出格式 (JSON):
  {
    "schema_version": "1.0",
    "candidates": [
      {
        "file_path": "src/auth.ts",
        "line_range": [10, 25],
        "confidence": 0.85,
        "reason": "调用链命中 + 最近修改",
        "is_hotspot": true,
        "scores": {
          "call_chain_score": 0.9,
          "history_score": 0.8,
          "hotspot_score": 0.7,
          "error_pattern_score": 0.6
        }
      }
    ]
  }

示例:
  # 基本用法
  bug-locator.sh --error "TypeError: Cannot read property 'id' of undefined"

  # 指定历史深度
  bug-locator.sh --error "NullPointerException at User.getName" --history-depth 60

  # 文本输出
  bug-locator.sh --error "Error in payment processing" --format text

EOF
}

show_version() {
  echo "bug-locator.sh version 1.0.0"
}

# ==================== 参数解析 ====================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --error)
        ERROR_INFO="$2"
        shift 2
        ;;
      --top-n)
        TOP_N="$2"
        shift 2
        ;;
      --history-depth)
        HISTORY_DEPTH="$2"
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
        log_error "未知参数: $1"
        show_help
        exit 1
        ;;
    esac
  done

  if [ -z "$ERROR_INFO" ]; then
    log_error "必须提供 --error 参数"
    exit 1
  fi
}

# ==================== 错误信息解析 ====================

# 从错误信息中提取符号和文件
parse_error_info() {
  local error="$1"

  local symbols='[]'
  local files='[]'

  # 提取文件路径（常见格式）
  # 格式1: at file.ts:10:5
  # 格式2: File "file.py", line 10
  # 格式3: file.go:10
  local file_matches
  file_matches=$(echo "$error" | grep -oE '[a-zA-Z0-9_/.-]+\.(ts|tsx|js|jsx|py|go|java|rs):[0-9]+' | head -10)

  while IFS= read -r match; do
    [ -z "$match" ] && continue
    local file_path line
    file_path=$(echo "$match" | cut -d: -f1)
    line=$(echo "$match" | cut -d: -f2)

    files=$(echo "$files" | jq --arg f "$file_path" --argjson l "$line" \
      '. + [{file_path: $f, line: $l}]')
  done <<< "$file_matches"

  # 提取符号名称
  # 格式1: at ClassName.methodName
  # 格式2: in function_name
  # 格式3: TypeError: ... 'propertyName'

  # camelCase/PascalCase 符号
  local symbol_matches
  symbol_matches=$(echo "$error" | grep -oE '\b[a-zA-Z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*\b' | head -10)

  while IFS= read -r sym; do
    [ -z "$sym" ] && continue
    symbols=$(echo "$symbols" | jq --arg s "$sym" '. + [$s]')
  done <<< "$symbol_matches"

  # snake_case 符号
  local snake_matches
  snake_matches=$(echo "$error" | grep -oE '\b[a-z]+_[a-z_]+\b' | head -5)

  while IFS= read -r sym; do
    [ -z "$sym" ] && continue
    symbols=$(echo "$symbols" | jq --arg s "$sym" '. + [$s]')
  done <<< "$snake_matches"

  # 引号内的属性名
  local quoted_matches
  quoted_matches=$(echo "$error" | grep -oE "'[a-zA-Z_][a-zA-Z0-9_]*'" | tr -d "'" | head -5)

  while IFS= read -r sym; do
    [ -z "$sym" ] && continue
    symbols=$(echo "$symbols" | jq --arg s "$sym" '. + [$s]')
  done <<< "$quoted_matches"

  # 去重
  symbols=$(echo "$symbols" | jq 'unique')
  files=$(echo "$files" | jq 'unique_by(.file_path)')

  jq -n --argjson symbols "$symbols" --argjson files "$files" \
    '{symbols: $symbols, files: $files}'
}

# ==================== 调用链分析 ====================

# 用于调用链分析的候选列表（模块级变量）
_CALL_CHAIN_CANDIDATES='[]'

# 递归提取调用链节点中的文件（顶层函数，避免嵌套定义）
# 参数: $1=node JSON, $2=depth
_extract_files_from_node() {
  local node="$1"
  local depth="$2"

  local file_path
  file_path=$(echo "$node" | jq -r '.file_path // empty')
  local line
  line=$(echo "$node" | jq -r '.line // 0')

  if [ -n "$file_path" ] && [ "$file_path" != "null" ]; then
    # 计算距离分数（越近分数越高）
    local distance_score
    if declare -f float_calc &>/dev/null; then
      distance_score=$(float_calc "1 - $depth * 0.2")
    else
      distance_score=$(echo "scale=2; 1 - $depth * 0.2" | bc 2>/dev/null || echo "0.8")
    fi

    _CALL_CHAIN_CANDIDATES=$(echo "$_CALL_CHAIN_CANDIDATES" | jq \
      --arg f "$file_path" \
      --argjson l "$line" \
      --argjson score "$distance_score" \
      '. + [{file_path: $f, line: $l, call_chain_score: $score}]')
  fi

  # 递归处理 callers 和 callees
  local callers callees
  callers=$(echo "$node" | jq '.callers // []')
  callees=$(echo "$node" | jq '.callees // []')

  local count j
  count=$(echo "$callers" | jq 'length')
  for ((j=0; j<count; j++)); do
    _extract_files_from_node "$(echo "$callers" | jq ".[$j]")" $((depth + 1))
  done

  count=$(echo "$callees" | jq 'length')
  for ((j=0; j<count; j++)); do
    _extract_files_from_node "$(echo "$callees" | jq ".[$j]")" $((depth + 1))
  done
}

# 获取符号的调用链候选
get_call_chain_candidates() {
  local symbols_json="$1"
  local call_chain_tool="${SCRIPT_DIR}/call-chain-tracer.sh"

  # 重置候选列表
  _CALL_CHAIN_CANDIDATES='[]'

  # 如果调用链工具不存在，降级处理
  if [ ! -x "$call_chain_tool" ]; then
    _maybe_log_warn "调用链工具不可用，跳过调用链分析"
    echo "$_CALL_CHAIN_CANDIDATES"
    return 0
  fi

  local symbol_count
  symbol_count=$(echo "$symbols_json" | jq '.symbols | length')

  for ((i=0; i<symbol_count && i<5; i++)); do
    local symbol
    symbol=$(echo "$symbols_json" | jq -r ".symbols[$i]")

    # 调用调用链工具
    local chain_result
    chain_result=$("$call_chain_tool" --symbol "$symbol" --depth 2 --cwd "$CWD" 2>/dev/null || echo '{}')

    # 提取路径中的文件
    local paths
    paths=$(echo "$chain_result" | jq '.paths // []')

    local path_count
    path_count=$(echo "$paths" | jq 'if type == "array" then length else 1 end')

    for ((j=0; j<path_count; j++)); do
      local path
      path=$(echo "$paths" | jq "if type == \"array\" then .[$j] else . end")
      _extract_files_from_node "$path" 1
    done
  done

  # 直接添加错误信息中的文件
  local file_count
  file_count=$(echo "$symbols_json" | jq '.files | length')

  for ((i=0; i<file_count; i++)); do
    local file_path line
    file_path=$(echo "$symbols_json" | jq -r ".files[$i].file_path")
    line=$(echo "$symbols_json" | jq -r ".files[$i].line")

    _CALL_CHAIN_CANDIDATES=$(echo "$_CALL_CHAIN_CANDIDATES" | jq \
      --arg f "$file_path" \
      --argjson l "$line" \
      '. + [{file_path: $f, line: $l, call_chain_score: 1.0}]')
  done

  # 去重并取最高分
  echo "$_CALL_CHAIN_CANDIDATES" | jq 'group_by(.file_path) | map(max_by(.call_chain_score))'
}

# ==================== Git 历史分析 ====================

# 获取最近修改的文件及其分数
get_history_scores() {
  local candidates_json="$1"

  if [ ! -d "$CWD/.git" ]; then
    echo "$candidates_json"
    return 0
  fi

  # 获取最近修改的文件列表
  local recent_files
  recent_files=$(git -C "$CWD" log \
    --since="${HISTORY_DEPTH} days ago" \
    --name-only \
    --pretty=format: \
    --max-count=500 \
    2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn)

  # 计算最大修改次数（用于归一化）
  local max_changes
  max_changes=$(echo "$recent_files" | head -1 | awk '{print $1}')
  [ -z "$max_changes" ] && max_changes=1

  # 为每个候选添加历史分数
  local result='[]'
  local count
  count=$(echo "$candidates_json" | jq 'length')

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")
    local file_path
    file_path=$(echo "$candidate" | jq -r '.file_path')

    # 查找文件的修改次数
    local changes
    changes=$(echo "$recent_files" | grep -E "\s${file_path}$" | awk '{print $1}' | head -1)
    [ -z "$changes" ] && changes=0

    # 计算归一化分数
    local history_score
    if declare -f float_calc &>/dev/null; then
      history_score=$(float_calc "$changes / $max_changes")
    else
      history_score=$(echo "scale=2; $changes / $max_changes" | bc 2>/dev/null || echo "0")
    fi

    candidate=$(echo "$candidate" | jq --argjson score "$history_score" '. + {history_score: $score}')
    result=$(echo "$result" | jq --argjson c "$candidate" '. + [$c]')
  done

  echo "$result"
}

# ==================== 热点文件分析 ====================

# 获取项目热点文件
# Trace: AC-001 - 调用 hotspot-analyzer.sh 获取热点分数
get_hotspot_files() {
  if [ ! -d "$CWD/.git" ]; then
    echo '[]'
    return 0
  fi

  # AC-010: 检查 hotspot_analyzer 功能是否启用
  local hotspot_enabled=true
  if declare -f is_feature_enabled &>/dev/null; then
    is_feature_enabled "hotspot_analyzer" || hotspot_enabled=false
  fi

  # 优先使用 hotspot-analyzer.sh（AC-001）
  if [ "$hotspot_enabled" = true ] && [ -x "$HOTSPOT_ANALYZER" ]; then
    local hotspot_result
    hotspot_result=$("$HOTSPOT_ANALYZER" --format json --path "$CWD" --top 20 --days "$HISTORY_DEPTH" 2>/dev/null) || true

    # 验证是否为有效 JSON（新格式：{schema_version, hotspots: [...]}）
    if echo "$hotspot_result" | jq -e '.hotspots' >/dev/null 2>&1; then
      # 新格式：hotspot-analyzer 输出 {schema_version: "1.0", hotspots: [{file, score, frequency, complexity}...]}
      # bug-locator 需要 [{file_path, change_count, score, complexity}]
      echo "$hotspot_result" | jq '[.hotspots[] | {
        file_path: .file,
        change_count: .frequency,
        score: .score,
        complexity: .complexity
      }]'
      return 0
    fi
    # 如果解析失败，记录警告并降级
    _maybe_log_warn "hotspot-analyzer.sh 输出无效，降级到内置实现"
  else
    if [ "$hotspot_enabled" = false ]; then
      _maybe_log_warn "hotspot_analyzer 功能已禁用，使用内置热点计算"
    else
      _maybe_log_warn "hotspot-analyzer.sh 不可用，使用内置热点计算"
    fi
  fi

  # 降级：使用内置实现（保持向后兼容）
  local freq_data
  freq_data=$(git -C "$CWD" log \
    --since="${HISTORY_DEPTH} days ago" \
    --name-only \
    --pretty=format: \
    --max-count=200 \
    2>/dev/null | \
    grep -v '^$' | \
    grep -vE 'node_modules|dist|build|\.lock|\.md$|\.json$|__pycache__|\.pyc$' | \
    sort | uniq -c | sort -rn | head -20) || true

  local hotspots='[]'

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local count file
    count=$(echo "$line" | awk '{print $1}')
    file=$(echo "$line" | awk '{print $2}')

    # 阈值：修改次数 >= 3 认为是热点
    if [ "$count" -ge 3 ]; then
      hotspots=$(echo "$hotspots" | jq --arg f "$file" --argjson c "$count" \
        '. + [{file_path: $f, change_count: $c, score: '$count'}]')
    fi
  done <<< "$freq_data"

  echo "$hotspots"
}

# 为候选添加热点分数
# Trace: AC-001 - 使用 hotspot-analyzer.sh 的综合分数（Frequency × Complexity）
add_hotspot_scores() {
  local candidates_json="$1"
  local hotspots_json="$2"

  local result='[]'
  local count
  count=$(echo "$candidates_json" | jq 'length')

  # 获取热点最高分用于归一化
  local max_score
  max_score=$(echo "$hotspots_json" | jq '[.[].score // 0] | max // 1')
  [ -z "$max_score" ] || [ "$max_score" = "null" ] && max_score=1

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")
    local file_path
    file_path=$(echo "$candidate" | jq -r '.file_path')

    # 检查是否是热点
    local is_hotspot hotspot_score raw_score
    local hotspot_entry
    hotspot_entry=$(echo "$hotspots_json" | jq --arg f "$file_path" '.[] | select(.file_path == $f)')

    if [ -n "$hotspot_entry" ] && [ "$hotspot_entry" != "null" ]; then
      is_hotspot=true
      raw_score=$(echo "$hotspot_entry" | jq -r '.score // 0')

      # 使用 hotspot-analyzer.sh 的综合分数（已考虑 Frequency × Complexity）
      # 归一化到 [0, 1]
      if declare -f float_calc &>/dev/null; then
        hotspot_score=$(float_calc "$raw_score / $max_score")
        local cmp_result
        cmp_result=$(float_calc "$hotspot_score > 1" 0)
        [ "$cmp_result" = "1" ] && hotspot_score=1.0
      else
        hotspot_score=$(echo "scale=2; $raw_score / $max_score" | bc 2>/dev/null || echo "0.5")
        [ "$(echo "$hotspot_score > 1" | bc 2>/dev/null || echo 0)" -eq 1 ] && hotspot_score=1.0
      fi
    else
      is_hotspot=false
      hotspot_score=0
    fi

    candidate=$(echo "$candidate" | jq \
      --argjson is_hot "$is_hotspot" \
      --argjson score "$hotspot_score" \
      '. + {is_hotspot: $is_hot, hotspot_score: $score}')

    result=$(echo "$result" | jq --argjson c "$candidate" '. + [$c]')
  done

  echo "$result"
}

# ==================== 错误模式分析 ====================

# 根据错误类型计算分数
add_error_pattern_scores() {
  local candidates_json="$1"
  local error="$2"

  local result='[]'
  local count
  count=$(echo "$candidates_json" | jq 'length')

  # 检测错误类型
  local error_type="unknown"
  if echo "$error" | grep -qiE "TypeError|undefined|null"; then
    error_type="null_reference"
  elif echo "$error" | grep -qiE "SyntaxError|parse"; then
    error_type="syntax"
  elif echo "$error" | grep -qiE "ReferenceError|not defined"; then
    error_type="reference"
  elif echo "$error" | grep -qiE "NetworkError|fetch|request"; then
    error_type="network"
  elif echo "$error" | grep -qiE "AuthError|unauthorized|forbidden"; then
    error_type="auth"
  fi

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")
    local file_path
    file_path=$(echo "$candidate" | jq -r '.file_path')

    # 根据文件名和错误类型匹配
    local error_pattern_score=0.5

    case "$error_type" in
      null_reference)
        # 可能在类型定义、数据处理相关文件
        if echo "$file_path" | grep -qiE "types?|model|data|util"; then
          error_pattern_score=0.7
        fi
        ;;
      auth)
        if echo "$file_path" | grep -qiE "auth|login|user|session"; then
          error_pattern_score=0.9
        fi
        ;;
      network)
        if echo "$file_path" | grep -qiE "api|fetch|request|http|client"; then
          error_pattern_score=0.9
        fi
        ;;
    esac

    candidate=$(echo "$candidate" | jq --argjson score "$error_pattern_score" \
      '. + {error_pattern_score: $score}')

    result=$(echo "$result" | jq --argjson c "$candidate" '. + [$c]')
  done

  echo "$result"
}

# ==================== 综合置信度计算 ====================

calculate_confidence() {
  local candidates_json="$1"

  local result='[]'
  local count
  count=$(echo "$candidates_json" | jq 'length')

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")

    local call_chain_score history_score hotspot_score error_pattern_score
    call_chain_score=$(echo "$candidate" | jq -r '.call_chain_score // 0')
    history_score=$(echo "$candidate" | jq -r '.history_score // 0')
    hotspot_score=$(echo "$candidate" | jq -r '.hotspot_score // 0')
    error_pattern_score=$(echo "$candidate" | jq -r '.error_pattern_score // 0.5')

    # 综合置信度计算
    local confidence
    local expr="$WEIGHT_CALL_CHAIN * $call_chain_score + $WEIGHT_HISTORY * $history_score + $WEIGHT_HOTSPOT * $hotspot_score + $WEIGHT_ERROR_PATTERN * $error_pattern_score"
    if declare -f float_calc &>/dev/null; then
      confidence=$(float_calc "$expr")
    else
      confidence=$(echo "scale=2; $expr" | bc 2>/dev/null || echo "0.5")
    fi

    # 生成原因说明（使用辅助函数比较浮点数）
    local reasons=()
    local cmp_call cmp_hist cmp_err
    if declare -f float_calc &>/dev/null; then
      cmp_call=$(float_calc "$call_chain_score > 0.5" 0)
      cmp_hist=$(float_calc "$history_score > 0.3" 0)
      cmp_err=$(float_calc "$error_pattern_score > 0.6" 0)
    else
      cmp_call=$(echo "$call_chain_score > 0.5" | bc 2>/dev/null || echo 0)
      cmp_hist=$(echo "$history_score > 0.3" | bc 2>/dev/null || echo 0)
      cmp_err=$(echo "$error_pattern_score > 0.6" | bc 2>/dev/null || echo 0)
    fi
    [ "$cmp_call" = "1" ] && reasons+=("调用链命中")
    [ "$cmp_hist" = "1" ] && reasons+=("最近修改")
    [ "$(echo "$candidate" | jq -r '.is_hotspot')" = "true" ] && reasons+=("热点文件")
    [ "$cmp_err" = "1" ] && reasons+=("错误模式匹配")

    local reason
    reason=$(IFS=', '; echo "${reasons[*]:-无明显特征}")

    candidate=$(echo "$candidate" | jq \
      --argjson conf "$confidence" \
      --arg reason "$reason" \
      '. + {confidence: $conf, reason: $reason}')

    result=$(echo "$result" | jq --argjson c "$candidate" '. + [$c]')
  done

  echo "$result"
}

# ==================== 主逻辑 ====================

locate_bug() {
  local error="$1"

  # Step 1: 解析错误信息
  local parsed
  parsed=$(parse_error_info "$error")

  _maybe_log_info "提取到 $(echo "$parsed" | jq '.symbols | length') 个符号，$(echo "$parsed" | jq '.files | length') 个文件"

  # Step 2: 调用链分析
  local candidates
  candidates=$(get_call_chain_candidates "$parsed")

  if [ -z "$candidates" ] || [ "$candidates" = "[]" ]; then
    _maybe_log_warn "未找到调用链候选，返回基于热点的默认候选"
    # 降级：使用热点文件
    candidates=$(get_hotspot_files | jq '[.[] | {file_path, call_chain_score: 0.3}]')
  fi

  # Step 3: Git 历史分析
  candidates=$(get_history_scores "$candidates")

  # Step 4: 热点交叉
  local hotspots
  hotspots=$(get_hotspot_files)
  candidates=$(add_hotspot_scores "$candidates" "$hotspots")

  # Step 5: 错误模式分析
  candidates=$(add_error_pattern_scores "$candidates" "$error")

  # Step 6: 综合置信度计算
  candidates=$(calculate_confidence "$candidates")

  # Step 7: 排序并返回 Top-N
  candidates=$(echo "$candidates" | jq "sort_by(-.confidence) | .[:$TOP_N]")

  # 添加行范围（估算）
  local final='[]'
  local count
  count=$(echo "$candidates" | jq 'length')

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates" | jq ".[$i]")
    local line
    line=$(echo "$candidate" | jq -r '.line // 1')

    # 估算行范围
    local line_start line_end
    line_start=$((line - 5))
    [ "$line_start" -lt 1 ] && line_start=1
    line_end=$((line + 15))

    candidate=$(echo "$candidate" | jq \
      --argjson start "$line_start" \
      --argjson end "$line_end" \
      '. + {line_range: [$start, $end]}')

    final=$(echo "$final" | jq --argjson c "$candidate" '. + [$c]')
  done

  # 构建输出
  jq -n \
    --arg version "1.0" \
    --argjson candidates "$final" \
    '{
      schema_version: $version,
      candidates: $candidates
    }'
}

# 输出结果
output_result() {
  local result="$1"

  if [ "$OUTPUT_FORMAT" = "json" ]; then
    echo "$result"
  else
    # 文本格式
    local count
    count=$(echo "$result" | jq '.candidates | length')

    echo "Bug 候选位置 (Top-$count):"
    echo ""

    for ((i=0; i<count; i++)); do
      local candidate
      candidate=$(echo "$result" | jq ".candidates[$i]")

      local file_path confidence reason is_hotspot line_range
      file_path=$(echo "$candidate" | jq -r '.file_path')
      confidence=$(echo "$candidate" | jq -r '.confidence')
      reason=$(echo "$candidate" | jq -r '.reason')
      is_hotspot=$(echo "$candidate" | jq -r '.is_hotspot')
      line_range=$(echo "$candidate" | jq -r '.line_range | "\(.[0])-\(.[1])"')

      local hotspot_marker=""
      [ "$is_hotspot" = "true" ] && hotspot_marker=" 🔥"

      echo "$((i+1)). $file_path:$line_range$hotspot_marker"
      echo "   置信度: $confidence | 原因: $reason"
      echo ""
    done
  fi
}

# ==================== 主函数 ====================

main() {
  parse_args "$@"

  # 定位 Bug
  local result
  result=$(locate_bug "$ERROR_INFO")

  # 输出结果
  output_result "$result"
}

main "$@"
