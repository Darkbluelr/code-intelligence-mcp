#!/bin/bash
# DevBooks Complexity Calculator
# 独立的复杂度计算工具，支持多语言、多工具适配与降级策略
# 版本: 1.0

set -euo pipefail

# ==================== 配置 ====================
DEFAULT_COMPLEXITY=1
TIMEOUT_SEC=1

# ==================== 工具检测 ====================
# 检测复杂度工具可用性
# 输出: 安装提示到 stderr（如有缺失工具）
check_complexity_tools() {
  local missing=()

  command -v radon &>/dev/null || missing+=("radon (pip install radon)")
  command -v scc &>/dev/null || missing+=("scc (brew install scc)")
  command -v gocyclo &>/dev/null || missing+=("gocyclo (go install github.com/fzipp/gocyclo/cmd/gocyclo@latest)")

  if [ ${#missing[@]} -eq 3 ]; then
    echo "⚠️ 复杂度工具缺失，建议安装：" >&2
    for tool in "${missing[@]}"; do
      echo "   - $tool" >&2
    done
    return 1
  fi
  return 0
}

# ==================== 超时执行 ====================
# macOS 兼容的超时函数
run_with_timeout() {
  local timeout_sec="$1"
  shift
  if command -v gtimeout &>/dev/null; then
    gtimeout "$timeout_sec" "$@" 2>/dev/null
  elif command -v timeout &>/dev/null; then
    timeout "$timeout_sec" "$@" 2>/dev/null
  else
    # 无超时命令，直接执行
    "$@" 2>/dev/null
  fi
}

# ==================== 复杂度计算 ====================
# 使用 radon 计算 Python 文件复杂度
get_python_complexity() {
  local file="$1"

  if ! command -v radon &>/dev/null; then
    return 1
  fi

  # radon cc 输出格式: "path:line func - A (5)"
  # 提取最大复杂度值
  local result
  result=$(run_with_timeout "$TIMEOUT_SEC" radon cc "$file" -s 2>/dev/null | \
    sed -n 's/.*(\([0-9]*\))$/\1/p' | \
    sort -rn | head -1)

  if [ -n "$result" ] && [ "$result" -gt 0 ]; then
    echo "$result"
    return 0
  fi
  return 1
}

# 使用 scc 计算通用文件复杂度
get_scc_complexity() {
  local file="$1"

  if ! command -v scc &>/dev/null; then
    return 1
  fi

  # scc JSON 输出: [{"Complexity": N, ...}]
  local result
  result=$(run_with_timeout "$TIMEOUT_SEC" scc --format json "$file" 2>/dev/null | \
    jq -r '.[0].Complexity // empty' 2>/dev/null)

  if [ -n "$result" ] && [ "$result" -gt 0 ]; then
    echo "$result"
    return 0
  fi
  return 1
}

# 使用 gocyclo 计算 Go 文件复杂度
get_go_complexity() {
  local file="$1"

  if ! command -v gocyclo &>/dev/null; then
    return 1
  fi

  # gocyclo 输出格式: "5 package funcName path:line"
  # 提取最大复杂度值
  local result
  result=$(run_with_timeout "$TIMEOUT_SEC" gocyclo "$file" 2>/dev/null | \
    awk '{print $1}' | sort -rn | head -1)

  if [ -n "$result" ] && [ "$result" -gt 0 ]; then
    echo "$result"
    return 0
  fi
  return 1
}

# ==================== 统一接口 ====================
# 获取文件复杂度
# 输入: 文件路径
# 输出: 复杂度分数 (>=1)
get_complexity() {
  local file="$1"

  # 检查文件存在性
  if [ ! -f "$file" ]; then
    echo "$DEFAULT_COMPLEXITY"
    return 0
  fi

  # 根据扩展名选择工具
  local ext="${file##*.}"
  local complexity=""

  case "$ext" in
    py)
      # Python: 优先 radon，降级到 scc
      complexity=$(get_python_complexity "$file") || \
      complexity=$(get_scc_complexity "$file") || \
      complexity=""
      ;;
    go)
      # Go: 优先 gocyclo，降级到 scc
      complexity=$(get_go_complexity "$file") || \
      complexity=$(get_scc_complexity "$file") || \
      complexity=""
      ;;
    js|jsx|ts|tsx|java|c|cpp|h|hpp|rs|rb|php|swift|kt|scala)
      # 其他语言: 使用 scc
      complexity=$(get_scc_complexity "$file") || complexity=""
      ;;
    *)
      # 未知语言: 使用 scc 降级
      complexity=$(get_scc_complexity "$file") || complexity=""
      ;;
  esac

  # 返回复杂度或默认值
  if [ -n "$complexity" ] && [ "$complexity" -gt 0 ]; then
    echo "$complexity"
  else
    echo "$DEFAULT_COMPLEXITY"
  fi
}

# ==================== 主逻辑 ====================
main() {
  local file="${1:-}"

  # 检查参数
  if [ -z "$file" ]; then
    echo "Usage: devbooks-complexity.sh <file>" >&2
    echo "Returns the cyclomatic complexity of a file (>=1)" >&2
    exit 1
  fi

  # 检测工具（仅输出提示，不阻塞）
  check_complexity_tools || true

  # 计算并输出复杂度
  get_complexity "$file"
}

# 如果直接执行脚本（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
