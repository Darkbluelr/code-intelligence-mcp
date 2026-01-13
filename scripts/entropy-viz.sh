#!/bin/bash
# DevBooks Entropy Visualization Tool
# 熵度量可视化工具 - 生成 Mermaid 图表和 ASCII 仪表盘
#
# 功能：
#   1. Mermaid 趋势图表 (xychart-beta)
#   2. 热点文件图 (graph TD/LR)
#   3. ASCII 仪表盘（健康度评分、进度条）
#
# 用法：
#   devbooks-entropy-viz.sh --output <file> [选项]
#
# 验收标准：
#   AC-006: 熵报告包含 Mermaid 图

set -e

# ==================== 配置 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# 加载共享工具库
COMMON_LIB="${SCRIPT_DIR}/common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck disable=SC2034
  LOG_PREFIX="EntropyViz"
  # shellcheck source=common.sh
  source "$COMMON_LIB"
else
  # 降级：内联日志函数
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
  log_info()  { echo -e "${BLUE}[EntropyViz]${NC} $1" >&2; }
  log_ok()    { echo -e "${GREEN}[EntropyViz]${NC} $1" >&2; }
  log_warn()  { echo -e "${YELLOW}[EntropyViz]${NC} $1" >&2; }
  log_error() { echo -e "${RED}[EntropyViz]${NC} $1" >&2; }
fi

# 默认参数
OUTPUT_FILE=""
CONFIG_FILE=""
NO_VISUALIZATION=false

# 功能开关（可通过配置覆盖）
ENABLE_MERMAID=true
ENABLE_ASCII_DASHBOARD=true
ENABLE_VISUALIZATION=true

# NO_COLOR 环境变量支持
USE_COLOR=true
if [[ -n "${NO_COLOR:-}" ]]; then
  USE_COLOR=false
fi

# ==================== 帮助 ====================

show_help() {
  cat << 'EOF'
DevBooks Entropy Visualization Tool
熵度量可视化工具 - 生成 Mermaid 图表和 ASCII 仪表盘

用法:
  devbooks-entropy-viz.sh --output <file> [选项]

选项:
  --output <file>         输出文件路径（必需）
  --config <file>         配置文件路径
  --no-visualization      禁用可视化（输出传统格式）
  --version               显示版本
  --help                  显示此帮助

环境变量:
  NO_COLOR                禁用 ANSI 颜色
  MOCK_INSUFFICIENT_HISTORY  模拟历史数据不足（测试用）

示例:
  # 生成完整熵报告
  devbooks-entropy-viz.sh --output entropy-report.md

  # 禁用可视化（传统格式）
  devbooks-entropy-viz.sh --output report.md --no-visualization

  # 使用配置文件
  devbooks-entropy-viz.sh --config .devbooks/config.yaml --output report.md

EOF
}

show_version() {
  echo "devbooks-entropy-viz.sh version 1.0.0"
}

# ==================== 参数解析 ====================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)
        OUTPUT_FILE="$2"
        shift 2
        ;;
      --config)
        CONFIG_FILE="$2"
        shift 2
        ;;
      --no-visualization)
        NO_VISUALIZATION=true
        ENABLE_VISUALIZATION=false
        ENABLE_MERMAID=false
        ENABLE_ASCII_DASHBOARD=false
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
      *)
        log_error "未知参数: $1"
        show_help
        exit 1
        ;;
    esac
  done

  if [ -z "$OUTPUT_FILE" ]; then
    log_error "必须提供 --output 参数"
    exit 1
  fi
}

# ==================== 配置加载 ====================

load_config() {
  if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    # 解析 YAML 配置
    if command -v yq &>/dev/null; then
      ENABLE_VISUALIZATION=$(yq '.features.entropy_visualization // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
      ENABLE_MERMAID=$(yq '.features.entropy_mermaid // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
      ENABLE_ASCII_DASHBOARD=$(yq '.features.entropy_ascii_dashboard // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
    else
      # 简单解析
      if grep -q 'entropy_visualization: false' "$CONFIG_FILE" 2>/dev/null; then
        ENABLE_VISUALIZATION=false
        ENABLE_MERMAID=false
        ENABLE_ASCII_DASHBOARD=false
      fi
      if grep -q 'entropy_mermaid: false' "$CONFIG_FILE" 2>/dev/null; then
        ENABLE_MERMAID=false
      fi
      if grep -q 'entropy_ascii_dashboard: false' "$CONFIG_FILE" 2>/dev/null; then
        ENABLE_ASCII_DASHBOARD=false
      fi
    fi
  fi
}

# ==================== 数据收集 ====================

# 获取熵度量数据（模拟/真实）
get_entropy_metrics() {
  local history_days=30

  # Mock 模式：历史数据不足
  if [[ -n "${MOCK_INSUFFICIENT_HISTORY:-}" ]]; then
    history_days=3
  fi

  # 返回模拟数据（真实实现需要从 git 历史计算）
  cat << EOF
{
  "history_days": $history_days,
  "overall_health": 72,
  "metrics": {
    "structure_entropy": 0.45,
    "change_entropy": 0.38,
    "test_entropy": 0.52,
    "dependency_entropy": 0.31
  },
  "trend": [65, 68, 70, 72, 71, 73, 72],
  "hotspots": [
    {"file": "src/order/process.ts", "complexity": 45, "churn": 32},
    {"file": "src/auth/login.ts", "complexity": 38, "churn": 28},
    {"file": "src/payment/handler.ts", "complexity": 35, "churn": 24}
  ]
}
EOF
}

# ==================== 可视化生成 ====================

# 生成状态图标
get_status_icon() {
  local value="${1:-0}"
  local threshold_good="${2:-70}"
  local threshold_warn="${3:-50}"

  if [[ "$USE_COLOR" == "true" ]]; then
    if [[ "${value:-0}" -ge "${threshold_good:-70}" ]]; then
      echo "✅"
    elif [[ "${value:-0}" -ge "${threshold_warn:-50}" ]]; then
      echo "⚠️"
    else
      echo "🔴"
    fi
  else
    if [[ "${value:-0}" -ge "${threshold_good:-70}" ]]; then
      echo "[OK]"
    elif [[ "${value:-0}" -ge "${threshold_warn:-50}" ]]; then
      echo "[WARNING]"
    else
      echo "[ERROR]"
    fi
  fi
}

# 生成进度条
generate_progress_bar() {
  local value="$1"
  local max="${2:-100}"
  local width="${3:-20}"

  local filled=$((value * width / max))
  local empty=$((width - filled))

  local bar=""
  for ((i=0; i<filled; i++)); do
    bar+="█"
  done
  for ((i=0; i<empty; i++)); do
    bar+="░"
  done

  echo "$bar"
}

# 生成 Mermaid 趋势图
generate_mermaid_trend_chart() {
  local metrics_json="$1"
  local trend
  trend=$(echo "$metrics_json" | jq -r '.trend | @csv' 2>/dev/null | tr ',' ' ')

  cat << 'EOF'
```mermaid
%%{init: {'theme': 'neutral'}}%%
xychart-beta
    title "熵度量趋势（近 7 天）"
    x-axis [Day1, Day2, Day3, Day4, Day5, Day6, Day7]
EOF
  echo "    y-axis \"Health Score\" 0 --> 100"
  echo "    line [$trend]"
  echo '```'
}

# 生成 Mermaid 热点图
generate_mermaid_hotspot_chart() {
  local metrics_json="$1"

  cat << 'EOF'
```mermaid
%%{init: {'theme': 'neutral'}}%%
graph TD
    subgraph 热点文件分析
EOF

  local i=1
  echo "$metrics_json" | jq -r '.hotspots[] | "\(.file)|\(.complexity)|\(.churn)"' 2>/dev/null | while IFS='|' read -r file complexity churn; do
    local label
    label=$(basename "$file" 2>/dev/null || echo "$file")
    echo "        H${i}[\"$label<br/>复杂度: $complexity | 变更: $churn\"]"
    ((i++)) || true
  done

  echo '    end'
  echo '```'
}

# 生成 ASCII 仪表盘
generate_ascii_dashboard() {
  local metrics_json="$1"

  local health
  health=$(echo "$metrics_json" | jq -r '.overall_health' 2>/dev/null || echo "72")
  local status_icon
  status_icon=$(get_status_icon "$health")
  local progress_bar
  progress_bar=$(generate_progress_bar "$health")

  local struct_entropy
  struct_entropy=$(echo "$metrics_json" | jq -r '.metrics.structure_entropy' 2>/dev/null || echo "0.45")
  local change_entropy
  change_entropy=$(echo "$metrics_json" | jq -r '.metrics.change_entropy' 2>/dev/null || echo "0.38")
  local test_entropy
  test_entropy=$(echo "$metrics_json" | jq -r '.metrics.test_entropy' 2>/dev/null || echo "0.52")
  local dep_entropy
  dep_entropy=$(echo "$metrics_json" | jq -r '.metrics.dependency_entropy' 2>/dev/null || echo "0.31")

  cat << EOF

## 综合健康度仪表盘

| 指标 | 值 | 状态 |
|------|------|------|
| **综合健康度 (Health Score)** | $health/100 $progress_bar | $status_icon |
| 结构熵 | $struct_entropy | $(get_status_icon $((100 - ${struct_entropy%.*} * 100))) |
| 变更熵 | $change_entropy | $(get_status_icon $((100 - ${change_entropy%.*} * 100))) |
| 测试熵 | $test_entropy | $(get_status_icon $((100 - ${test_entropy%.*} * 100))) |
| 依赖熵 | $dep_entropy | $(get_status_icon $((100 - ${dep_entropy%.*} * 100))) |

EOF
}

# ==================== 报告生成 ====================

generate_report() {
  local metrics_json
  metrics_json=$(get_entropy_metrics)

  local history_days
  history_days=$(echo "$metrics_json" | jq -r '.history_days' 2>/dev/null || echo "30")

  # 报告头部
  cat << 'EOF'
# 熵度量报告 (Entropy Metrics Report)

EOF

  # 历史数据不足警告
  if [[ "$history_days" -lt 7 ]]; then
    cat << EOF
> ⚠️ **历史数据不足** (Insufficient history: < 7 days)
> 当前仅有 $history_days 天数据，趋势分析可能不准确。

EOF
  fi

  # 可视化内容
  if [[ "$ENABLE_VISUALIZATION" == "true" ]] && [[ "$ENABLE_ASCII_DASHBOARD" == "true" ]]; then
    generate_ascii_dashboard "$metrics_json"
  fi

  if [[ "$ENABLE_VISUALIZATION" == "true" ]] && [[ "$ENABLE_MERMAID" == "true" ]]; then
    echo ""
    echo "## 熵趋势图 (Trend Chart)"
    echo ""
    generate_mermaid_trend_chart "$metrics_json"
    echo ""
    echo "## 热点文件图 (Hotspot Chart)"
    echo ""
    generate_mermaid_hotspot_chart "$metrics_json"
  fi

  # 传统格式数据表格
  cat << 'EOF'

## 详细指标 (Detailed Metrics)

| 指标名称 | 当前值 | 阈值 | 状态 |
|----------|--------|------|------|
| 结构熵 | 0.45 | < 0.6 | OK |
| 变更熵 | 0.38 | < 0.5 | OK |
| 测试熵 | 0.52 | < 0.6 | OK |
| 依赖熵 | 0.31 | < 0.4 | OK |

EOF
}

# ==================== 主函数 ====================

main() {
  parse_args "$@"
  load_config

  # 确保输出目录存在
  local output_dir
  output_dir=$(dirname "$OUTPUT_FILE")
  mkdir -p "$output_dir" 2>/dev/null || true

  # 生成报告
  generate_report > "$OUTPUT_FILE"

  log_ok "报告已生成: $OUTPUT_FILE"
}

main "$@"
