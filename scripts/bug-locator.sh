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

# 影响分析配置（MP6 - Bug 定位 + 影响分析融合）
: "${BUG_LOCATOR_WITH_IMPACT:=false}"
: "${BUG_LOCATOR_IMPACT_DEPTH:=3}"
: "${BUG_LOCATOR_IMPACT_WEIGHT:=0.2}"
: "${BUG_LOCATOR_IMPACT_TIMEOUT:=5}"
: "${BUG_LOCATOR_IMPACT_TOP_N:=10}"

# 影响分析器路径
IMPACT_ANALYZER="${SCRIPT_DIR}/impact-analyzer.sh"

# 热点分析器路径
HOTSPOT_ANALYZER="${SCRIPT_DIR}/hotspot-analyzer.sh"

# 缓存管理器路径 (MP5.1 集成)
CACHE_MANAGER="${SCRIPT_DIR}/cache-manager.sh"

# 缓存相关配置
: "${BUG_LOCATOR_CACHE_ENABLED:=true}"

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
  --with-impact         启用影响分析融合（AC-G08）
  --impact-depth <n>    影响分析深度（默认: 3）
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

带影响分析的输出格式 (--with-impact):
  {
    "schema_version": "1.0",
    "candidates": [
      {
        "symbol": "string",
        "file": "string",
        "line": 10,
        "score": 85.5,
        "original_score": 78.2,
        "impact": {
          "total_affected": 12,
          "affected_files": ["src/handlers/auth.ts"],
          "max_depth": 3
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

  # 启用影响分析
  bug-locator.sh --error "authentication error" --with-impact --impact-depth 3

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
      --with-impact)
        BUG_LOCATOR_WITH_IMPACT=true
        shift
        ;;
      --impact-depth)
        BUG_LOCATOR_IMPACT_DEPTH="$2"
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
  local call_chain_tool="${SCRIPT_DIR}/call-chain.sh"

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

    # 提取调用链中的文件（兼容 call_chain 和 paths 两种格式）
    local paths
    paths=$(echo "$chain_result" | jq '.call_chain // .paths // []')

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

# ==================== 缓存集成 (MP5.1) ====================

# 计算查询缓存 key
_compute_bug_locator_cache_key() {
  local error="$1"
  local key_input="${error}:${TOP_N}:${HISTORY_DEPTH}:${CWD}"

  if declare -f hash_string_md5 &>/dev/null; then
    hash_string_md5 "$key_input"
  elif command -v md5sum &>/dev/null; then
    printf '%s' "$key_input" | md5sum | cut -d' ' -f1
  elif command -v md5 &>/dev/null; then
    if md5 -q /dev/null >/dev/null 2>&1; then
      printf '%s' "$key_input" | md5 -q
    else
      printf '%s' "$key_input" | md5
    fi
  else
    printf '%s' "$key_input" | cksum | cut -d' ' -f1
  fi
}

# 选择一个存在的缓存锚点文件（用于 cache-manager 校验）
_resolve_bug_locator_cache_anchor() {
  local root="$1"
  local candidates=(
    "$root/.git/index"
    "$root/.git/HEAD"
    "$root/package.json"
    "$root/README.md"
    "$SCRIPT_DIR/bug-locator.sh"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

# 获取缓存结果
_get_cached_bug_result() {
  local query_hash="$1"

  # 检查缓存是否启用
  if [[ "$BUG_LOCATOR_CACHE_ENABLED" != "true" ]]; then
    return 1
  fi

  # 检查缓存管理器是否可用
  if [[ ! -x "$CACHE_MANAGER" ]]; then
    return 1
  fi

  # 使用真实文件作为缓存锚点，避免 cache-manager 直接 miss
  local cache_anchor
  cache_anchor=$(_resolve_bug_locator_cache_anchor "$CWD") || return 1

  local cache_result
  cache_result=$("$CACHE_MANAGER" --get "$cache_anchor" --query "$query_hash" 2>/dev/null)

  if [[ -n "$cache_result" ]] && echo "$cache_result" | jq -e '.candidates' &>/dev/null; then
    _maybe_log_info "缓存命中 (key: ${query_hash:0:8}...)"
    echo "$cache_result"
    return 0
  fi

  return 1
}

# 设置缓存结果
_set_cached_bug_result() {
  local query_hash="$1"
  local result="$2"

  # 检查缓存是否启用
  if [[ "$BUG_LOCATOR_CACHE_ENABLED" != "true" ]]; then
    return 0
  fi

  # 检查缓存管理器是否可用
  if [[ ! -x "$CACHE_MANAGER" ]]; then
    return 0
  fi

  local cache_anchor
  cache_anchor=$(_resolve_bug_locator_cache_anchor "$CWD") || return 0

  # 缓存结果
  "$CACHE_MANAGER" --set "$cache_anchor" --query "$query_hash" --value "$result" 2>/dev/null || true
}

# ==================== 主逻辑 ====================

locate_bug() {
  local error="$1"

  # MP5.1: 检查缓存
  local query_hash
  query_hash=$(_compute_bug_locator_cache_key "$error")

  local cached_result
  if cached_result=$(_get_cached_bug_result "$query_hash"); then
    echo "$cached_result"
    return 0
  fi

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
  local result
  result=$(jq -n \
    --arg version "1.0" \
    --argjson candidates "$final" \
    '{
      schema_version: $version,
      candidates: $candidates
    }')

  # MP5.1: 缓存结果
  _set_cached_bug_result "$query_hash" "$result"

  echo "$result"
}

# ==================== 影响分析融合 (MP6.2, MP6.3) ====================

# 计算影响分析缓存 key（MP6.3）
# 格式: impact:${symbol_or_file}:${depth}
_compute_impact_cache_key() {
  local symbol_or_file="$1"
  local depth="$2"
  echo "impact:${symbol_or_file}:${depth}"
}

# 获取单个候选的影响分析
# 参数: $1=symbol_id, $2=file_path
# 返回: impact JSON 或空
# MP6.3: 支持子图 LRU 缓存复用以降低影响分析成本
_get_candidate_impact() {
  local symbol_id="$1"
  local file_path="$2"
  local depth="${BUG_LOCATOR_IMPACT_DEPTH:-3}"
  local timeout="${BUG_LOCATOR_IMPACT_TIMEOUT:-5}"

  # 检查影响分析器是否可用
  if [[ ! -x "$IMPACT_ANALYZER" ]]; then
    _maybe_log_warn "影响分析器不可用，跳过影响分析"
    echo '{}'
    return 0
  fi

  # 确定分析目标（优先使用 symbol_id，否则使用 file_path）
  local analysis_target
  local analysis_type
  if [[ -n "$symbol_id" && "$symbol_id" != "null" ]]; then
    analysis_target="$symbol_id"
    analysis_type="analyze"
  elif [[ -n "$file_path" && "$file_path" != "null" ]]; then
    analysis_target="$file_path"
    analysis_type="file"
  else
    echo '{}'
    return 0
  fi

  # MP6.3: 检查子图 LRU 缓存
  local cache_key
  cache_key=$(_compute_impact_cache_key "$analysis_target" "$depth")

  if [[ -x "$CACHE_MANAGER" ]]; then
    local cached_result
    cached_result=$("$CACHE_MANAGER" cache-get "$cache_key" 2>/dev/null) || true

    if [[ -n "$cached_result" ]] && echo "$cached_result" | jq -e '.' >/dev/null 2>&1; then
      _maybe_log_info "影响分析缓存命中 (key=${cache_key:0:30}...)"
      echo "$cached_result"
      return 0
    fi
  fi

  # 执行影响分析（带超时降级：优先 timeout > gtimeout > 直接执行）
  local impact_result
  local timeout_cmd=""

  # 检测可用的超时命令（macOS 上可能需要 gtimeout 或无超时）
  if command -v timeout &>/dev/null; then
    timeout_cmd="timeout ${timeout}s"
  elif command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout ${timeout}s"
  else
    # 无超时命令时直接执行（但在日志中警告）
    _maybe_log_warn "timeout 命令不可用，影响分析将无超时限制"
    timeout_cmd=""
  fi

  if [[ "$analysis_type" == "analyze" ]]; then
    # 符号级影响分析
    if [[ -n "$timeout_cmd" ]]; then
      impact_result=$($timeout_cmd "$IMPACT_ANALYZER" analyze "$analysis_target" --depth "$depth" --format json 2>/dev/null) || true
    else
      impact_result=$("$IMPACT_ANALYZER" analyze "$analysis_target" --depth "$depth" --format json 2>/dev/null) || true
    fi
  else
    # 文件级影响分析
    if [[ -n "$timeout_cmd" ]]; then
      impact_result=$($timeout_cmd "$IMPACT_ANALYZER" file "$analysis_target" --depth "$depth" --format json 2>/dev/null) || true
    else
      impact_result=$("$IMPACT_ANALYZER" file "$analysis_target" --depth "$depth" --format json 2>/dev/null) || true
    fi
  fi

  # 验证输出
  if [[ -z "$impact_result" ]] || ! echo "$impact_result" | jq -e '.' >/dev/null 2>&1; then
    # 超时或无效输出
    _maybe_log_warn "影响分析超时或无效输出 (target=$analysis_target)"
    echo '{}'
    return 0
  fi

  # MP6.3: 将结果写入子图 LRU 缓存
  if [[ -x "$CACHE_MANAGER" ]]; then
    # 异步写入缓存，不阻塞主流程
    "$CACHE_MANAGER" cache-set "$cache_key" "$impact_result" 2>/dev/null &
  fi

  echo "$impact_result"
}

# 融合影响分析到候选结果
# 参数: $1=candidates JSON
# 返回: 带影响分析的 candidates JSON
add_impact_analysis() {
  local candidates_json="$1"
  local impact_weight="${BUG_LOCATOR_IMPACT_WEIGHT:-0.2}"
  local top_n="${BUG_LOCATOR_IMPACT_TOP_N:-10}"

  local result='[]'
  local count
  count=$(echo "$candidates_json" | jq 'length')

  _maybe_log_info "对 Top ${top_n} 候选执行影响分析..."

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")

    local file_path symbol_id original_score
    file_path=$(echo "$candidate" | jq -r '.file_path // .file // ""')
    symbol_id=$(echo "$candidate" | jq -r '.symbol // ""')
    original_score=$(echo "$candidate" | jq -r '.confidence // .score // 0')

    # 只对 Top N 执行影响分析（REQ-BLF-005）
    if [[ $i -lt $top_n ]]; then
      local impact_result
      impact_result=$(_get_candidate_impact "$symbol_id" "$file_path")

      if [[ -n "$impact_result" && "$impact_result" != '{}' ]]; then
        # 提取影响数据
        local total_affected affected_files max_depth
        total_affected=$(echo "$impact_result" | jq -r '.total_affected // 0')
        max_depth=$(echo "$impact_result" | jq -r '.depth // 3')

        # 提取受影响文件列表（去重并限制数量）
        affected_files=$(echo "$impact_result" | jq '[.affected_nodes[].file_path // empty] | unique | .[0:20]')
        [[ "$affected_files" == "null" || -z "$affected_files" ]] && affected_files='[]'

        # 计算归一化影响分数 (normalized_impact = min(total_affected / 100, 1.0))
        local normalized_impact impact_score
        if declare -f float_calc &>/dev/null; then
          normalized_impact=$(float_calc "$total_affected / 100")
          local cmp
          cmp=$(float_calc "$normalized_impact > 1" 0)
          [[ "$cmp" = "1" ]] && normalized_impact="1.0"
          impact_score=$(float_calc "$normalized_impact")
        else
          normalized_impact=$(echo "scale=4; $total_affected / 100" | bc 2>/dev/null || echo "0")
          [[ $(echo "$normalized_impact > 1" | bc 2>/dev/null || echo 0) -eq 1 ]] && normalized_impact="1.0"
          impact_score="$normalized_impact"
        fi

        # 重新计算综合分数 (REQ-BLF-003)
        # final_score = original_score * (1 + impact_weight * normalized_impact)
        local final_score
        if declare -f float_calc &>/dev/null; then
          final_score=$(float_calc "$original_score * (1 + $impact_weight * $normalized_impact)")
        else
          final_score=$(echo "scale=4; $original_score * (1 + $impact_weight * $normalized_impact)" | bc 2>/dev/null || echo "$original_score")
        fi

        # 添加影响字段到候选
        candidate=$(echo "$candidate" | jq \
          --argjson total_affected "$total_affected" \
          --argjson affected_files "$affected_files" \
          --argjson max_depth "$max_depth" \
          --argjson impact_score "$impact_score" \
          --argjson original_score "$original_score" \
          --argjson final_score "$final_score" \
          '. + {
            original_score: $original_score,
            score: $final_score,
            impact: {
              total_affected: $total_affected,
              affected_files: $affected_files,
              max_depth: $max_depth,
              impact_score: $impact_score
            }
          }')
      else
        # 影响分析不可用时保留原始分数
        candidate=$(echo "$candidate" | jq \
          --argjson original_score "$original_score" \
          '. + {original_score: $original_score, score: $original_score}')
      fi
    else
      # 超出 Top N 的候选不执行影响分析，保留原始分数
      candidate=$(echo "$candidate" | jq \
        --argjson original_score "$original_score" \
        '. + {original_score: $original_score, score: $original_score}')
    fi

    result=$(echo "$result" | jq --argjson c "$candidate" '. + [$c]')
  done

  # 按新分数重新排序
  echo "$result" | jq 'sort_by(-.score)'
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

  # MP6.2: 如果启用影响分析，融合影响数据
  if [[ "$BUG_LOCATOR_WITH_IMPACT" = true ]]; then
    local candidates
    candidates=$(echo "$result" | jq '.candidates')

    # 添加影响分析（包含 Top 10 限制、5s 超时降级、子图 LRU 缓存复用）
    local enhanced_candidates
    enhanced_candidates=$(add_impact_analysis "$candidates")

    # 重建结果
    result=$(echo "$result" | jq --argjson enhanced "$enhanced_candidates" '.candidates = $enhanced')
  fi

  # 输出结果
  output_result "$result"
}

main "$@"
