#!/bin/bash
# DevBooks Hotspot Analyzer
# 热点计算工具，基于 Frequency × Complexity 公式
# 版本: 1.0
# Trace: AC-001

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==================== 配置 ====================
DEFAULT_TOP_N=20
DEFAULT_DAYS=30
DEFAULT_FORMAT="text"

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
  -n, --top N        返回 Top-N 热点文件（默认: 20）
  --days N           统计最近 N 天的 git log（默认: 30）
  --format FORMAT    输出格式: text 或 json（默认: text）
  --path DIR         目标目录（默认: 当前目录）
  -h, --help         显示帮助信息

Output (text):
  RANK  SCORE  FREQ  COMPLEXITY  FILE

Output (json):
  [{"rank": 1, "file": "...", "score": N, "frequency": N, "complexity": N}, ...]

Examples:
  hotspot-analyzer.sh --top 10 --days 7
  hotspot-analyzer.sh --format json --path ./src
EOF
}

# ==================== 参数解析 ====================
TOP_N=$DEFAULT_TOP_N
DAYS=$DEFAULT_DAYS
FORMAT=$DEFAULT_FORMAT
TARGET_PATH="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--top)
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
    -h|--help)
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
get_file_complexity() {
  local file="$1"
  local full_path="${TARGET_PATH}/${file}"

  if [[ ! -f "$full_path" ]]; then
    echo "1"
    return
  fi

  # 调用 complexity.sh 获取复杂度
  if [[ -x "${SCRIPT_DIR}/complexity.sh" ]]; then
    local complexity
    complexity=$("${SCRIPT_DIR}/complexity.sh" "$full_path" 2>/dev/null) || complexity="1"
    if [[ "$complexity" =~ ^[0-9]+$ ]] && [[ "$complexity" -gt 0 ]]; then
      echo "$complexity"
    else
      echo "1"
    fi
  else
    echo "1"
  fi
}

# ==================== 主逻辑 ====================
main() {
  log_info "分析热点文件 (最近 $DAYS 天, Top $TOP_N)..."

  # 创建临时文件
  local tmp_freq
  tmp_freq=$(mktemp)
  local tmp_result
  tmp_result=$(mktemp)
  trap "rm -f '$tmp_freq' '$tmp_result'" EXIT

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
    sort | uniq -c | sort -rn > "$tmp_freq" || true

  local file_count
  file_count=$(wc -l < "$tmp_freq" | tr -d ' ')

  if [[ "$file_count" -eq 0 ]]; then
    log_warn "没有找到最近 $DAYS 天的变更记录"
    if [[ "$FORMAT" == "json" ]]; then
      echo "[]"
    else
      echo "无热点文件"
    fi
    exit 0
  fi

  # 计算热点分数
  while read -r freq file; do
    if [[ -n "$file" ]]; then
      local complexity
      complexity=$(get_file_complexity "$file")
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
    echo '  "schema_version": "1.0",'
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

  log_ok "热点分析完成"
}

# 执行主逻辑
main
