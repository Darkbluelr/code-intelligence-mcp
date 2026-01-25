#!/bin/bash
# DevBooks Call-Chain Tracer
#
# 功能：
#   1. 调用链追踪：callers/callees 方向遍历
#   2. 入口路径追溯：从入口点到目标符号
#   3. 循环检测：检测并标记循环依赖
#   4. 数据流追踪：完整的污点传播分析
#
# 用法：
#   call-chain-tracer.sh --symbol "funcName" [选项]
#
# 验收标准：
#   AC-004: 输出包含 ≥ 2 层嵌套的调用链 JSON
# shellcheck disable=SC2034  # 未使用变量（配置项）

set -euo pipefail

# P1-FIX: 添加 trap 清理机制，确保资源正确释放
_cleanup() {
  # 清理临时文件（如果有）
  if [[ -n "${_TEMP_FILES:-}" ]]; then
    for f in $_TEMP_FILES; do
      [[ -f "$f" ]] && rm -f "$f" 2>/dev/null || true
    done
  fi
  # C-007 fix: Check function existence before calling
  # This prevents errors if call-chain-dataflow.sh failed to load
  if declare -f _reset_data_flow_state &>/dev/null; then
    _reset_data_flow_state
  fi
}
trap _cleanup EXIT INT TERM

# ==================== 初始化 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CWD="${PROJECT_ROOT}"

# 加载共享工具库
COMMON_LIB="${SCRIPT_DIR}/common.sh"
if [ -f "$COMMON_LIB" ]; then
  LOG_PREFIX="CallChain"
  # shellcheck source=common.sh
  source "$COMMON_LIB"
else
  # 降级：内联日志函数
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
  log_info()  { echo -e "${BLUE}[CallChain]${NC} $1" >&2; }
  log_ok()    { echo -e "${GREEN}[CallChain]${NC} $1" >&2; }
  log_warn()  { echo -e "${YELLOW}[CallChain]${NC} $1" >&2; }
  log_error() { echo -e "${RED}[CallChain]${NC} $1" >&2; }
fi

# 检查必需依赖
if declare -f check_dependencies &>/dev/null; then
  check_dependencies jq || exit 2
else
  command -v jq &>/dev/null || { log_error "缺少依赖: jq"; exit 2; }
fi

# ==================== 加载模块 ====================

# 加载核心配置和参数解析模块
CORE_MODULE="${SCRIPT_DIR}/call-chain-core.sh"
if [ -f "$CORE_MODULE" ]; then
  # shellcheck source=call-chain-core.sh
  source "$CORE_MODULE"
else
  log_error "缺少核心模块: $CORE_MODULE"
  exit 2
fi

# 加载调用链追踪模块
TRACE_MODULE="${SCRIPT_DIR}/call-chain-trace.sh"
if [ -f "$TRACE_MODULE" ]; then
  # shellcheck source=call-chain-trace.sh
  source "$TRACE_MODULE"
else
  log_error "缺少追踪模块: $TRACE_MODULE"
  exit 2
fi

# 加载数据流追踪模块
DATAFLOW_MODULE="${SCRIPT_DIR}/call-chain-dataflow.sh"
if [ -f "$DATAFLOW_MODULE" ]; then
  # shellcheck source=call-chain-dataflow.sh
  source "$DATAFLOW_MODULE"
else
  log_error "缺少数据流模块: $DATAFLOW_MODULE"
  exit 2
fi

# ==================== 主逻辑 ====================

build_call_chain() {
  local symbol="$1"

  # M3: 完整数据流追踪模式 (AC-004)
  if [ "$DATA_FLOW_ENABLED" = true ]; then
    trace_full_data_flow "$symbol"
    return 0
  fi

  # 数据流追踪模式 (AC-006)
  if [ "$TRACE_DATA_FLOW" = true ]; then
    trace_data_flow "$symbol"
    return 0
  fi

  : # _detect_ckb removed

  # 重置全局状态（避免跨调用状态泄漏）
  VISITED_NODES='[]'
  CYCLE_DETECTED=false

  local call_chain

  if [ "$TRACE_USAGE" = true ]; then
    call_chain=$(trace_usage_paths "$symbol")
  else
    call_chain=$(traverse_call_chain "$symbol" 0 "$DEPTH" "$DIRECTION")

    # 转换为数组格式并添加 is_cycle 字段
    if [[ "$(echo "$call_chain" | jq 'type')" != '"array"' ]]; then
      call_chain="[$call_chain]"
    fi
    call_chain=$(echo "$call_chain" | jq '[.[] | . + {is_cycle: false}]')
  fi

  # 确保是数组
  if [[ "$(echo "$call_chain" | jq 'type')" != '"array"' ]]; then
    call_chain="[$call_chain]"
  fi

  # 构建输出（使用 call_chain 而不是 paths）
  jq -n \
    --arg version "1.0" \
    --arg symbol "$SYMBOL" \
    --arg direction "$DIRECTION" \
    --argjson depth "$DEPTH" \
    --argjson cycle "$CYCLE_DETECTED" \
    --argjson call_chain "$call_chain" \
    '{
      schema_version: $version,
      target_symbol: $symbol,
      direction: $direction,
      cycle_detected: $cycle,
      call_chain: $call_chain,
      metadata: {
        max_depth: $depth,
      }
    }'
}

# 递归打印调用链路径（顶层函数，避免嵌套定义）
# 参数: $1=paths JSON, $2=indent string, $3=current depth (optional)
# m-008 fix: 添加最大递归深度检查（20 层）
_print_call_chain_paths() {
  local paths="$1"
  local indent="$2"
  local current_depth="${3:-0}"
  local max_depth=20

  # m-008 fix: 防止栈溢出
  if [ "$current_depth" -ge "$max_depth" ]; then
    echo "${indent}├── ... (max depth $max_depth reached)"
    return
  fi

  local count
  count=$(echo "$paths" | jq 'if type == "array" then length else 1 end')

  for ((i=0; i<count; i++)); do
    local node
    node=$(echo "$paths" | jq "if type == \"array\" then .[$i] else . end")

    local sym file line
    sym=$(echo "$node" | jq -r '.symbol_id // "?"')
    file=$(echo "$node" | jq -r '.file_path // "?"')
    line=$(echo "$node" | jq -r '.line // "?"')

    echo "${indent}├── $sym ($file:$line)"

    local callers callees
    callers=$(echo "$node" | jq '.callers // []')
    callees=$(echo "$node" | jq '.callees // []')

    if [ "$(echo "$callers" | jq 'length')" -gt 0 ]; then
      echo "${indent}│   ↑ Callers:"
      _print_call_chain_paths "$callers" "${indent}│   " $((current_depth + 1))
    fi

    if [ "$(echo "$callees" | jq 'length')" -gt 0 ]; then
      echo "${indent}│   ↓ Callees:"
      _print_call_chain_paths "$callees" "${indent}│   " $((current_depth + 1))
    fi
  done
}

# 输出结果
output_result() {
  local result="$1"

  if [ "$OUTPUT_FORMAT" = "json" ]; then
    echo "$result"
  elif [ "$OUTPUT_FORMAT" = "mermaid" ]; then
    # M3: Mermaid 格式（数据流追踪）
    if [ "$DATA_FLOW_ENABLED" = true ]; then
      format_data_flow_mermaid "$result"
    else
      # 调用链的 Mermaid 输出（暂不支持）
      echo "# Mermaid 格式仅支持 --data-flow 模式"
      echo "$result"
    fi
  else
    # 文本格式
    # M3: 数据流追踪使用专用格式
    if [ "$DATA_FLOW_ENABLED" = true ]; then
      format_data_flow_text "$result"
    else
      # 原有调用链文本格式
      local symbol direction depth cycle
      symbol=$(echo "$result" | jq -r '.target_symbol')
      direction=$(echo "$result" | jq -r '.direction')
      depth=$(echo "$result" | jq -r '.metadata.max_depth')
      cycle=$(echo "$result" | jq -r '.cycle_detected')

      echo "调用链追踪: $symbol"
      echo "方向: $direction, 深度: $depth"
      [ "$cycle" = "true" ] && echo "Warning: 检测到循环依赖"
      echo ""

      local call_chain
      call_chain=$(echo "$result" | jq '.call_chain')
      _print_call_chain_paths "$call_chain" ""
    fi
  fi
}

# ==================== 主函数 ====================

main() {
  parse_args "$@"

  if [[ "$DATA_FLOW_ENABLED" = true ]] && declare -f is_feature_enabled &>/dev/null; then
    if ! is_feature_enabled "data_flow_tracing"; then
      log_warn "数据流追踪已禁用 (features.data_flow_tracing: false)"
      echo '{"error":"data_flow_tracing disabled","code":"FEATURE_DISABLED"}'
      exit 0
    fi
  fi

  # 构建调用链
  local result
  result=$(build_call_chain "$SYMBOL")

  # 输出结果
  output_result "$result"
}

main "$@"
