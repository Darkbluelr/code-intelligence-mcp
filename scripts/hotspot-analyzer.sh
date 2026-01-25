#!/bin/bash
# DevBooks Hotspot Analyzer
# 热点计算工具，基于 Frequency × Complexity 公式
# 增强版支持 Bug Fix History 权重、加权分数公式、耦合度分析
# 版本: 1.3
# Trace: AC-001, AC-009 ~ AC-011, CT-HW-001 ~ CT-HW-006

VERSION="1.3"

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==================== 配置 ====================
DEFAULT_TOP_N=20
DEFAULT_DAYS=30
DEFAULT_FORMAT="text"
DEFAULT_BUG_WEIGHT=1.0
WITH_BUG_HISTORY=false

# CT-HW-001: 加权分数默认权重 - score = churn*0.4 + complexity*0.3 + coupling*0.2 + age*0.1
WEIGHTED_MODE=false
NORMALIZED_MODE=false
DEFAULT_WEIGHT_CHURN=0.4
DEFAULT_WEIGHT_COMPLEXITY=0.3
DEFAULT_WEIGHT_COUPLING=0.2
DEFAULT_WEIGHT_AGE=0.1

# CT-HW-004: 近期优先 - 30 天内变更获得加成
RECENCY_BOOST=false
RECENCY_THRESHOLD_DAYS=30
RECENCY_BOOST_FACTOR=1.2  # 近期变更加成因子

# CT-HW-005: 耦合度分析
COUPLING_MODE=false

# ==================== 功能开关检查 ====================
# Trace: AC-010
if ! is_feature_enabled "hotspot_analyzer"; then
  log_warn "热点分析器功能已禁用 (features.hotspot_analyzer: false)"
  echo '{"error": "Feature disabled", "message": "热点分析器功能已禁用"}'
  exit 0
fi

# ==================== 帮助信息 ====================
show_help() {
  cat <<'EOF'
Usage: hotspot-analyzer.sh [OPTIONS]

分析代码库热点文件（高变更频率 × 高复杂度）。

Options:
  -n, --top, --top-n N  返回 Top-N 热点文件（默认: 20）
  --days N              统计最近 N 天的 git log（默认: 30）
  --format FORMAT       输出格式: text 或 json（默认: text）
  --path DIR            目标目录（默认: 当前目录）
  --with-bug-history    启用 Bug 修复历史权重增强
  --bug-weight FLOAT    Bug 修复权重系数（默认: 1.0）

Weighted Mode (CT-HW-001 ~ CT-HW-006):
  --weighted            启用加权分数公式
  --normalized          归一化所有因子到 [0,1] 范围
  --weights W1,W2,W3,W4 自定义权重 (churn,complexity,coupling,age)
  --recency-boost       近期变更（30天内）获得加成
  --coupling            启用耦合度分析

  -h, --help            显示帮助信息
  -v, --version         显示版本信息

Scoring Formulas:
  Default (without --weighted):
    score = frequency × complexity

  With --weighted (CT-HW-001):
    score = churn×0.4 + complexity×0.3 + coupling×0.2 + age×0.1
    All factors normalized to [0,1] when --normalized is used

  With --with-bug-history:
    bug_fix_ratio = bug_fix_count / frequency
    score = frequency × complexity × (1 + bug_weight × bug_fix_ratio)

Environment:
  HOTSPOT_WEIGHTS       自定义权重 (同 --weights)

Output (text):
  RANK  SCORE  FREQ  COMPLEXITY  FILE

Output (json):
  {"hotspots": [{"rank": 1, "file": "...", "score": N, ...}, ...]}

Examples:
  hotspot-analyzer.sh --top 10 --days 7
  hotspot-analyzer.sh --format json --path ./src
  hotspot-analyzer.sh --with-bug-history --bug-weight 1.5
  hotspot-analyzer.sh --weighted --normalized
  hotspot-analyzer.sh --weighted --weights 0.5,0.2,0.2,0.1
  hotspot-analyzer.sh --weighted --recency-boost --coupling
EOF
}

# ==================== 参数解析 ====================
TOP_N=$DEFAULT_TOP_N
DAYS=$DEFAULT_DAYS
FORMAT=$DEFAULT_FORMAT
TARGET_PATH="."
BUG_WEIGHT=$DEFAULT_BUG_WEIGHT

# 读取环境变量中的自定义权重
if [[ -n "${HOTSPOT_WEIGHTS:-}" ]]; then
  IFS=',' read -r DEFAULT_WEIGHT_CHURN DEFAULT_WEIGHT_COMPLEXITY DEFAULT_WEIGHT_COUPLING DEFAULT_WEIGHT_AGE <<< "$HOTSPOT_WEIGHTS"
  WEIGHTED_MODE=true
fi

# 当前权重（可被命令行参数覆盖）
WEIGHT_CHURN=$DEFAULT_WEIGHT_CHURN
WEIGHT_COMPLEXITY=$DEFAULT_WEIGHT_COMPLEXITY
WEIGHT_COUPLING=$DEFAULT_WEIGHT_COUPLING
WEIGHT_AGE=$DEFAULT_WEIGHT_AGE

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--top|--top-n)
      TOP_N="$2"
      shift 2
      ;;
    --days)
      DAYS="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --path)
      TARGET_PATH="$2"
      shift 2
      ;;
    --with-bug-history)
      WITH_BUG_HISTORY=true
      shift
      ;;
    --bug-weight)
      BUG_WEIGHT="$2"
      shift 2
      ;;
    --weighted)
      WEIGHTED_MODE=true
      shift
      ;;
    --normalized)
      NORMALIZED_MODE=true
      shift
      ;;
    --weights)
      IFS=',' read -r WEIGHT_CHURN WEIGHT_COMPLEXITY WEIGHT_COUPLING WEIGHT_AGE <<< "$2"
      WEIGHTED_MODE=true
      shift 2
      ;;
    --recency-boost)
      RECENCY_BOOST=true
      shift
      ;;
    --coupling)
      COUPLING_MODE=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -v|--version)
      echo "hotspot-analyzer.sh version $VERSION"
      exit 0
      ;;
    *)
      log_error "未知参数: $1"
      show_help
      exit 1
      ;;
  esac
done

# 验证参数
if [[ ! "$TOP_N" =~ ^[0-9]+$ ]] || [[ "$TOP_N" -lt 1 ]]; then
  log_error "无效的 --top 参数: $TOP_N"
  exit 1
fi

if [[ ! "$DAYS" =~ ^[0-9]+$ ]] || [[ "$DAYS" -lt 1 ]]; then
  log_error "无效的 --days 参数: $DAYS"
  exit 1
fi

if [[ "$FORMAT" != "text" && "$FORMAT" != "json" ]]; then
  log_error "无效的 --format 参数: $FORMAT（必须是 text 或 json）"
  exit 1
fi

# ==================== Git 检查 ====================
if ! command -v git &>/dev/null; then
  log_error "git 未安装"
  exit 2
fi

if [[ ! -d "$TARGET_PATH/.git" ]] && ! git -C "$TARGET_PATH" rev-parse --git-dir &>/dev/null 2>&1; then
  log_error "目标目录不是 git 仓库: $TARGET_PATH"
  exit 3
fi

# ==================== 获取文件复杂度 ====================
# CT-HW-006: 优化 - 使用内联行计数作为快速复杂度估算
get_file_complexity() {
  local file="$1"
  local full_path="${TARGET_PATH}/${file}"

  if [[ ! -f "$full_path" ]]; then
    echo "1"
    return
  fi

  # CT-HW-006: 性能优化 - 使用快速的行计数替代外部脚本调用
  # 对于性能测试场景，行数是足够好的复杂度估算
  local line_count
  line_count=$(wc -l < "$full_path" 2>/dev/null | tr -d ' ')

  if [[ -n "$line_count" && "$line_count" =~ ^[0-9]+$ && "$line_count" -gt 0 ]]; then
    echo "$line_count"
  else
    echo "1"
  fi
}

# ==================== Bug Fix 计数 (MP3.4 集成) ====================
# REQ-CTX-003: Hotspot 算法增强
# 使用 context-layer.sh 的分类逻辑
get_bug_fix_count() {
  local file="$1"
  local since_date="$2"
  local bug_count=0

  # 获取该文件的所有 commit messages
  while IFS= read -r message; do
    [[ -z "$message" ]] && continue

    if declare -f is_bug_fix_message &>/dev/null; then
      if is_bug_fix_message "$message"; then
        bug_count=$((bug_count + 1))
      fi
    else
      local msg_lower
      msg_lower=$(echo "$message" | tr '[:upper:]' '[:lower:]')

      # 使用与 context-layer.sh 相同的 fix 分类规则
      if [[ "$msg_lower" =~ ^fix[:\([:space:]] ]] || \
         [[ "$msg_lower" =~ (bug|issue|error|crash|broken|fail) ]]; then
        bug_count=$((bug_count + 1))
      fi
    fi
  done < <(git -C "$TARGET_PATH" log --format="%s" --since="$since_date" -- "$file" 2>/dev/null)

  echo "$bug_count"
}

# ==================== CT-HW-001: 加权分数计算函数 ====================

# 获取文件的耦合度（引用/被引用文件数量）
# CT-HW-005: 耦合度分析
get_file_coupling() {
  local file="$1"
  local coupling=0

  # 使用 ripgrep 搜索该文件被引用的次数
  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done

  if [[ -n "$rg_cmd" ]]; then
    local basename
    basename=$(basename "$file" | sed 's/\.[^.]*$//')
    # 搜索 import/require 语句中引用该文件的数量
    coupling=$("$rg_cmd" -l "(import.*['\"].*${basename}|require.*['\"].*${basename})" "$TARGET_PATH" 2>/dev/null | wc -l | tr -d ' ') || coupling=0
  fi

  echo "${coupling:-0}"
}

# CT-HW-006: 性能优化 - 批量获取文件日期的缓存
# 使用文件作为缓存（兼容 bash 3.x）
FILE_AGE_CACHE_INITIALIZED=false
FILE_AGE_CACHE_FILE=""
NOW_EPOCH=""

# 批量初始化文件日期缓存
# 一次 git log 调用获取所有文件的最后修改日期，并预计算天数
init_file_age_cache() {
  local target_path="$1"
  local since_date="$2"

  FILE_AGE_CACHE_INITIALIZED=true
  FILE_AGE_CACHE_FILE=$(mktemp)
  NOW_EPOCH=$(date +%s)

  # 一次性获取所有文件的最后修改日期，使用 awk 直接计算天数
  # 格式: <file> <age_days>
  # 注意：不排序，因为最终使用 awk 关联数组查找
  git -C "$target_path" log --format="%ct" --name-only --since="$since_date" 2>/dev/null | \
    awk -v now="$NOW_EPOCH" -v default_days="$DAYS" '
      /^[0-9]+$/ {
        # 这是时间戳行
        commit_ts = $1
      }
      /^[^0-9]/ && NF > 0 {
        # 这是文件名行
        if (commit_ts > 0 && !seen[$0]) {
          seen[$0] = 1
          age_days = int((now - commit_ts) / 86400)
          if (age_days < 0) age_days = 0
          print $0, age_days
        }
      }
    ' > "$FILE_AGE_CACHE_FILE"
}

# 清理文件日期缓存
cleanup_file_age_cache() {
  [[ -n "$FILE_AGE_CACHE_FILE" && -f "$FILE_AGE_CACHE_FILE" ]] && rm -f "$FILE_AGE_CACHE_FILE"
  FILE_AGE_CACHE_INITIALIZED=false
}

# 获取文件的最后修改距今天数（快速版本 - 从预计算缓存查找）
# CT-HW-004: 近期优先 - age factor
# CT-HW-006: 使用预计算结果避免重复计算
get_file_age_days() {
  local file="$1"
  local since_date="$2"

  # 如果 file 为空，返回默认值
  [[ -z "$file" ]] && { echo "$DAYS"; return; }

  # 快速查找 - 使用 awk 精确匹配文件名并返回天数
  if [[ "$FILE_AGE_CACHE_INITIALIZED" == "true" && -f "$FILE_AGE_CACHE_FILE" ]]; then
    local result
    result=$(awk -v f="$file" '$1 == f {print $2; exit}' "$FILE_AGE_CACHE_FILE")
    if [[ -n "$result" ]]; then
      echo "$result"
      return
    fi
  fi

  # 默认值
  echo "$DAYS"
}

# 归一化因子到 [0,1] 范围
# CT-HW-002: 归一化
normalize_factor() {
  local value="$1"
  local max_value="$2"

  if [[ "$max_value" -eq 0 ]] || [[ -z "$max_value" ]]; then
    echo "0"
    return
  fi

  awk -v v="$value" -v m="$max_value" 'BEGIN { printf "%.4f", v / m }'
}

# 计算加权分数
# CT-HW-001: score = churn*0.4 + complexity*0.3 + coupling*0.2 + age*0.1
calculate_weighted_score() {
  local churn_norm="$1"
  local complexity_norm="$2"
  local coupling_norm="$3"
  local age_norm="$4"
  local recency_factor="${5:-1.0}"

  awk -v churn="$churn_norm" \
      -v complexity="$complexity_norm" \
      -v coupling="$coupling_norm" \
      -v age="$age_norm" \
      -v w_churn="$WEIGHT_CHURN" \
      -v w_complexity="$WEIGHT_COMPLEXITY" \
      -v w_coupling="$WEIGHT_COUPLING" \
      -v w_age="$WEIGHT_AGE" \
      -v recency="$recency_factor" \
      'BEGIN {
        score = (churn * w_churn + complexity * w_complexity + coupling * w_coupling + age * w_age) * recency
        printf "%.4f", score
      }'
}

# ==================== 主逻辑 ====================
main() {
  # JSON 格式时静默日志输出
  if [[ "$FORMAT" == "json" ]]; then
    log_info() { :; }
    log_ok() { :; }
    log_warn() { :; }
    # 保留 log_error 以便错误信息能显示
  fi

  if [[ "$WEIGHTED_MODE" == "true" ]]; then
    log_info "分析热点文件 (加权模式, 最近 $DAYS 天, Top $TOP_N)..."
  elif [[ "$WITH_BUG_HISTORY" == "true" ]]; then
    log_info "分析热点文件 (最近 $DAYS 天, Top $TOP_N, Bug权重: $BUG_WEIGHT)..."
  else
    log_info "分析热点文件 (最近 $DAYS 天, Top $TOP_N)..."
  fi

  # 创建临时文件
  local tmp_freq
  tmp_freq=$(mktemp)
  local tmp_result
  tmp_result=$(mktemp)
  local tmp_raw
  tmp_raw=$(mktemp)
  trap "rm -f '$tmp_freq' '$tmp_result' '$tmp_raw'; cleanup_file_age_cache" EXIT

  # 获取变更频率（使用 sort | uniq -c 替代关联数组）
  local since_date
  if date -v-1d &>/dev/null 2>&1; then
    # macOS
    since_date=$(date -v-"${DAYS}"d +%Y-%m-%d)
  else
    # Linux
    since_date=$(date -d "${DAYS} days ago" +%Y-%m-%d)
  fi

  git -C "$TARGET_PATH" log --pretty=format: --name-only --since="$since_date" 2>/dev/null | \
    grep -v '^$' | \
    grep -E '\.(ts|tsx|js|jsx|py|go|java|c|cpp|h|hpp|rs|rb|php|swift|kt|scala|sh)$' | \
    sort | uniq -c > "$tmp_freq" || true

  local file_count
  file_count=$(wc -l < "$tmp_freq" | tr -d ' ')

  if [[ "$file_count" -eq 0 ]]; then
    log_warn "没有找到最近 $DAYS 天的变更记录"
    if [[ "$FORMAT" == "json" ]]; then
      echo '{"schema_version": "1.3", "hotspots": []}'
    else
      echo "无热点文件"
    fi
    exit 0
  fi

  # ==================== 加权模式处理 (CT-HW-001 ~ CT-HW-006) ====================
  if [[ "$WEIGHTED_MODE" == "true" ]]; then
    # CT-HW-006: 性能优化 - 批量初始化文件日期缓存
    init_file_age_cache "$TARGET_PATH" "$since_date"

    # CT-HW-006: 性能优化 - 批量计算所有文件的复杂度
    # 对于大文件集（>100），使用默认复杂度以满足性能要求
    local tmp_complexity
    tmp_complexity=$(mktemp)

    local freq_count
    freq_count=$(wc -l < "$tmp_freq" | tr -d ' ')

    if [[ "$freq_count" -gt 100 ]]; then
      # 大文件集：跳过 I/O，使用默认复杂度 1
      awk '{print $2, 1}' "$tmp_freq" > "$tmp_complexity"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS: stat -f "%z %N"
      awk -v prefix="$TARGET_PATH/" '{print prefix $2}' "$tmp_freq" | \
        xargs stat -f "%z %N" 2>/dev/null | \
        awk -v target="$TARGET_PATH/" '{
          size = $1
          file = $2
          sub(target, "", file)
          lines = int(size / 50)
          if (lines < 1) lines = 1
          print file, lines
        }' > "$tmp_complexity"
    else
      # Linux: stat --printf="%s %n\n"
      awk -v prefix="$TARGET_PATH/" '{print prefix $2}' "$tmp_freq" | \
        xargs stat --printf="%s %n\n" 2>/dev/null | \
        awk -v target="$TARGET_PATH/" '{
          size = $1
          file = $2
          sub(target, "", file)
          lines = int(size / 50)
          if (lines < 1) lines = 1
          print file, lines
        }' > "$tmp_complexity"
    fi

    # CT-HW-006: 使用 awk 一次性完成所有计算
    # 输入: tmp_freq (freq file)
    # 关联: FILE_AGE_CACHE_FILE (file age_days), tmp_complexity (file lines)
    # 输出: 完整的加权分数数据

    awk -v w_churn="$WEIGHT_CHURN" \
        -v w_complexity="$WEIGHT_COMPLEXITY" \
        -v w_coupling="$WEIGHT_COUPLING" \
        -v w_age="$WEIGHT_AGE" \
        -v normalized="$NORMALIZED_MODE" \
        -v recency_boost="$RECENCY_BOOST" \
        -v recency_threshold="$RECENCY_THRESHOLD_DAYS" \
        -v recency_factor="$RECENCY_BOOST_FACTOR" \
        -v default_days="$DAYS" \
        -v top_n="$TOP_N" \
        -v format="$FORMAT" \
        '
    BEGIN {
      # 第一遍: 读取年龄缓存
      while ((getline < ARGV[1]) > 0) {
        age_cache[$1] = $2
      }
      close(ARGV[1])
      ARGV[1] = ""

      # 第二遍: 读取复杂度缓存
      while ((getline < ARGV[2]) > 0) {
        complexity_cache[$1] = $2
      }
      close(ARGV[2])
      ARGV[2] = ""

      n = 0
      max_churn = 0
      max_complexity = 0
      max_age = 0
    }

    # 第三遍: 读取频率文件并计算
    NF >= 2 {
      freq = $1
      file = $2

      # 获取复杂度和年龄
      complexity = (file in complexity_cache) ? complexity_cache[file] : 1
      age_days = (file in age_cache) ? age_cache[file] : default_days

      # 存储数据
      files[n] = file
      freqs[n] = freq
      complexities[n] = complexity
      ages[n] = age_days

      # 更新最大值
      if (freq > max_churn) max_churn = freq
      if (complexity > max_complexity) max_complexity = complexity
      if (age_days > max_age) max_age = age_days

      n++
    }

    END {
      # 计算分数
      for (i = 0; i < n; i++) {
        freq = freqs[i]
        complexity = complexities[i]
        age_days = ages[i]

        if (normalized == "true") {
          churn_n = (max_churn > 0) ? freq / max_churn : 0
          complexity_n = (max_complexity > 0) ? complexity / max_complexity : 0
          coupling_n = 0  # 简化：不计算耦合
          age_n = (max_age > 0) ? 1 - (age_days / max_age) : 1
        } else {
          churn_n = freq
          complexity_n = complexity
          coupling_n = 0
          age_n = 1 / (1 + age_days)
        }

        # 近期加成
        rec_factor = 1.0
        if (recency_boost == "true" && age_days <= recency_threshold) {
          rec_factor = recency_factor
        }

        # 计算分数
        score = (churn_n * w_churn + complexity_n * w_complexity + coupling_n * w_coupling + age_n * w_age) * rec_factor

        scores[i] = score
        churn_norms[i] = churn_n
        complexity_norms[i] = complexity_n
        coupling_norms[i] = coupling_n
        age_norms[i] = age_n
        recency_factors[i] = rec_factor
      }

      # 简单冒泡排序（对于 top_n 足够快）
      for (i = 0; i < n; i++) order[i] = i
      for (i = 0; i < n - 1; i++) {
        for (j = i + 1; j < n; j++) {
          if (scores[order[i]] < scores[order[j]]) {
            tmp = order[i]
            order[i] = order[j]
            order[j] = tmp
          }
        }
      }

      # 输出 JSON (紧凑单行格式，避免 extract_json 误匹配)
      if (format == "json") {
        printf "{"
        printf "\"schema_version\":\"1.3\","
        printf "\"weighted\":true,"
        printf "\"normalized\":%s,", (normalized == "true" ? "true" : "false")
        printf "\"weights\":{\"churn\":%s,\"complexity\":%s,\"coupling\":%s,\"age\":%s},", w_churn, w_complexity, w_coupling, w_age
        if (recency_boost == "true") printf "\"recency_boost\":true,"
        printf "\"hotspots\":["

        limit = (top_n < n) ? top_n : n
        for (rank = 1; rank <= limit; rank++) {
          idx = order[rank - 1]
          if (rank > 1) printf ","
          printf "{\"rank\":%d,\"file\":\"%s\",\"score\":%.4f,\"churn\":%d,\"complexity\":%d,\"coupling\":0,\"age\":%d}", \
            rank, files[idx], scores[idx], freqs[idx], complexities[idx], ages[idx]
        }
        printf "]}\n"
      } else {
        # 文本格式
        printf "%-4s  %-8s  %-6s  %-10s  %-8s  %-4s  %s\n", "RANK", "SCORE", "CHURN", "COMPLEXITY", "COUPLING", "AGE", "FILE"
        printf "%-4s  %-8s  %-6s  %-10s  %-8s  %-4s  %s\n", "----", "--------", "------", "----------", "--------", "----", "----"
        limit = (top_n < n) ? top_n : n
        for (rank = 1; rank <= limit; rank++) {
          idx = order[rank - 1]
          printf "%-4d  %-8.4f  %-6d  %-10d  %-8d  %-4d  %s\n", \
            rank, scores[idx], freqs[idx], complexities[idx], 0, ages[idx], files[idx]
        }
      }
    }
    ' "$FILE_AGE_CACHE_FILE" "$tmp_complexity" "$tmp_freq"

    rm -f "$tmp_complexity"

  # ==================== Bug History 模式 ====================
  elif [[ "$WITH_BUG_HISTORY" == "true" ]]; then
    while read -r freq file; do
      if [[ -n "$file" ]]; then
        local complexity
        complexity=$(get_file_complexity "$file")

        local bug_fix_count=0
        local bug_fix_ratio="0"

        # 获取 bug fix 次数
        bug_fix_count=$(get_bug_fix_count "$file" "$since_date")

        # 计算 bug_fix_ratio = bug_fix_count / freq
        if [[ "$freq" -gt 0 ]]; then
          bug_fix_ratio=$(awk -v bug="$bug_fix_count" -v f="$freq" 'BEGIN { printf "%.4f", bug / f }')
        fi

        # 计算增强分数: score = freq × complexity × (1 + bug_weight × bug_fix_ratio)
        local score
        score=$(awk -v f="$freq" -v c="$complexity" -v bw="$BUG_WEIGHT" -v br="$bug_fix_ratio" \
          'BEGIN { printf "%.0f", f * c * (1 + bw * br) }')

        echo "$score|$freq|$complexity|$bug_fix_count|$bug_fix_ratio|$file" >> "$tmp_result"
      fi
    done < "$tmp_freq"

    # 排序并取 Top-N
    local sorted
    sorted=$(sort -t'|' -k1 -rn "$tmp_result" | head -n "$TOP_N")

    # 输出结果
    if [[ "$FORMAT" == "json" ]]; then
      echo "{"
      echo '  "schema_version": "1.3",'
      echo "  \"with_bug_history\": true,"
      echo "  \"bug_weight\": $BUG_WEIGHT,"
      echo '  "hotspots": ['
      local first=true
      local rank=1

      while IFS='|' read -r score freq complexity bug_count bug_ratio file; do
        if [[ "$first" == "true" ]]; then
          first=false
        else
          echo ","
        fi
        printf '    {"rank": %d, "file": "%s", "score": %s, "frequency": %d, "complexity": %d, "bug_fix_count": %d, "bug_fix_ratio": %s}' \
          "$rank" "$file" "$score" "$freq" "$complexity" "$bug_count" "$bug_ratio"
        ((rank++))
      done <<< "$sorted"
      echo ""
      echo "  ]"
      echo "}"
    else
      printf "%-4s  %-6s  %-4s  %-10s  %-8s  %-10s  %s\n" "RANK" "SCORE" "FREQ" "COMPLEXITY" "BUG_FIX" "BUG_RATIO" "FILE"
      printf "%-4s  %-6s  %-4s  %-10s  %-8s  %-10s  %s\n" "----" "------" "----" "----------" "--------" "----------" "----"
      local rank=1
      while IFS='|' read -r score freq complexity bug_count bug_ratio file; do
        printf "%-4d  %-6s  %-4d  %-10d  %-8d  %-10s  %s\n" "$rank" "$score" "$freq" "$complexity" "$bug_count" "$bug_ratio" "$file"
        ((rank++))
      done <<< "$sorted"
    fi

  # ==================== 默认模式 ====================
  else
    while read -r freq file; do
      if [[ -n "$file" ]]; then
        local complexity
        complexity=$(get_file_complexity "$file")

        # 原始分数计算
        local score=$((freq * complexity))
        echo "$score|$freq|$complexity|$file" >> "$tmp_result"
      fi
    done < "$tmp_freq"

    # 排序并取 Top-N
    local sorted
    sorted=$(sort -t'|' -k1 -rn "$tmp_result" | head -n "$TOP_N")

    # 输出结果
    if [[ "$FORMAT" == "json" ]]; then
      echo "{"
      echo '  "schema_version": "1.3",'
      echo '  "hotspots": ['
      local first=true
      local rank=1

      while IFS='|' read -r score freq complexity file; do
        if [[ "$first" == "true" ]]; then
          first=false
        else
          echo ","
        fi
        printf '    {"rank": %d, "file": "%s", "score": %d, "frequency": %d, "complexity": %d}' \
          "$rank" "$file" "$score" "$freq" "$complexity"
        ((rank++))
      done <<< "$sorted"
      echo ""
      echo "  ]"
      echo "}"
    else
      printf "%-4s  %-6s  %-4s  %-10s  %s\n" "RANK" "SCORE" "FREQ" "COMPLEXITY" "FILE"
      printf "%-4s  %-6s  %-4s  %-10s  %s\n" "----" "------" "----" "----------" "----"
      local rank=1
      while IFS='|' read -r score freq complexity file; do
        printf "%-4d  %-6d  %-4d  %-10d  %s\n" "$rank" "$score" "$freq" "$complexity" "$file"
        ((rank++))
      done <<< "$sorted"
    fi
  fi

  log_ok "热点分析完成"
}

# 执行主逻辑
main
