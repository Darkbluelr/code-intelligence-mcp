#!/bin/bash
# DevBooks Call-Chain Tracer - Core Module
# 核心配置、参数解析、帮助信息
# shellcheck disable=SC2034  # 未使用变量（配置项）

# ==================== 配置 ====================

# 默认参数
SYMBOL=""
DIRECTION="both"  # callers | callees | both
DEPTH=2
TRACE_USAGE=false
TRACE_DATA_FLOW=false  # 新增：数据流追踪 (AC-006)

# 数据流追踪参数 (M3: AC-004)
DATA_FLOW_ENABLED=false
DATA_FLOW_DIRECTION="both"  # forward | backward | both
DATA_FLOW_MAX_DEPTH=5       # 默认最大深度 5 跳 (REQ-DFT-006)
DATA_FLOW_INCLUDE_TRANSFORMS=false  # 包含转换详情
DATA_FLOW_FILE=""                  # 指定数据流入口文件

# 模式
OUTPUT_FORMAT="json"


# 已访问节点（用于循环检测）
VISITED_NODES='[]'
CYCLE_DETECTED=false

# ==================== 帮助 ====================

show_help() {
  cat << 'EOF'
DevBooks Call-Chain Tracer

用法:
  call-chain-tracer.sh --symbol "funcName" [选项]

选项:
  --symbol <name>       目标符号名称（必需）
  --direction <dir>     遍历方向: callers | callees | both（默认: both）
  --depth <n>           最大遍历深度 1-4（默认: 2）
  --trace-usage         追溯从入口到目标的调用路径
  --trace-data-flow     追踪数据流：显示参数如何在函数间流动 (AC-006)
  --data-flow           启用完整数据流追踪模式 (M3: AC-004)
  --data-flow-direction <dir>  数据流追踪方向: forward | backward | both（默认: both）
                        - forward: 从定义追踪到使用（影响分析）
                        - backward: 从使用追踪到来源（根因分析）
                        - both: 双向追踪（完整数据流）
  --file <path>         指定数据流追踪入口文件（仅支持 TS/JS）
  --max-depth <n>       数据流追踪最大深度 1-10（默认: 5）
  --include-transforms  在数据流追踪中包含转换详情
  --cwd <path>          工作目录（默认: 当前目录）
  --format <text|json|mermaid>  输出格式（默认: json）
  --enable-all-features 忽略功能开关配置，强制启用所有功能
  --mock-ckb            使用模拟数据（测试用）
  --version             显示版本
  --help                显示此帮助

输出格式 (JSON):
  {
    "schema_version": "1.0",
    "target_symbol": "funcName",
    "direction": "both",
    "depth": 2,
    "cycle_detected": false,
    "paths": [
      {
        "symbol_id": "module::func",
        "file_path": "src/lib.ts",
        "line": 10,
        "depth": 1,
        "callers": [...],
        "callees": [...]
      }
    ]
  }

数据流输出格式 (--data-flow):
  {
    "source": {"symbol": "x", "file": "a.ts", "line": 10, "type": "parameter"},
    "sink": {"symbol": "z", "file": "c.ts", "line": 50, "type": "function_call"},
    "path": [
      {"symbol": "x", "transform": "parameter_input", "file": "a.ts", "line": 10},
      {"symbol": "y", "transform": "assignment", "file": "b.ts", "line": 20},
      {"symbol": "z", "transform": "function_call", "file": "c.ts", "line": 50}
    ],
    "depth": 3,
    "cycle_detected": false,
    "truncated": false
  }

示例:
  # 查找函数的调用方
  call-chain-tracer.sh --symbol "getUserById" --direction callers

  # 查找函数调用的其他函数
  call-chain-tracer.sh --symbol "processPayment" --direction callees --depth 3

  # 追溯入口路径
  call-chain-tracer.sh --symbol "handleError" --trace-usage

  # 数据流追踪：从用户输入追踪到数据库
  call-chain-tracer.sh --symbol "userInput" --data-flow --data-flow-direction forward

  # 数据流追踪：反向追踪错误来源
  call-chain-tracer.sh --symbol "errorData" --data-flow --data-flow-direction backward --max-depth 10

EOF
}

show_version() {
  echo "call-chain-tracer.sh version 1.0.0"
}

# ==================== 参数解析 ====================

parse_args() {
  # Workaround: If first arg doesn't start with --, treat it as symbol
  # This handles cases where --symbol flag is dropped by MCP transport
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    SYMBOL="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --symbol)
        SYMBOL="$2"
        shift 2
        ;;
      --direction)
        DIRECTION="$2"
        shift 2
        ;;
      --depth)
        DEPTH="$2"
        shift 2
        ;;
      --trace-usage)
        TRACE_USAGE=true
        shift
        ;;
      --trace-data-flow)
        TRACE_DATA_FLOW=true
        shift
        ;;
      --data-flow)
        # M3: AC-004 - 完整数据流追踪模式
        DATA_FLOW_ENABLED=true
        shift
        ;;
      --data-flow-direction)
        # M3: REQ-DFT-002 - 追踪方向
        DATA_FLOW_DIRECTION="$2"
        shift 2
        ;;
      --max-depth)
        # M3: REQ-DFT-006 - 数据流追踪深度
        DATA_FLOW_MAX_DEPTH="$2"
        shift 2
        ;;
      --include-transforms)
        # M3: REQ-DFT-003 - 包含转换详情
        DATA_FLOW_INCLUDE_TRANSFORMS=true
        shift
        ;;
      --file)
        DATA_FLOW_FILE="$2"
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
      --enable-all-features)
        DEVBOOKS_ENABLE_ALL_FEATURES=1
        shift
        ;;
      --mock-ckb)
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

  if [ -z "$SYMBOL" ]; then
    log_error "必须提供 --symbol 参数"
    exit 1
  fi

  # 验证深度（必须是整数且在 1-4 之间）
  # JSON 格式时静默处理，避免污染输出
  if ! [[ "$DEPTH" =~ ^[0-9]+$ ]]; then
    [[ "$OUTPUT_FORMAT" != "json" ]] && log_warn "深度必须是整数，使用默认值 2"
    DEPTH=2
  elif [ "$DEPTH" -lt 1 ]; then
    [[ "$OUTPUT_FORMAT" != "json" ]] && log_warn "深度必须至少为 1，使用最小值 1"
    DEPTH=1
  elif [ "$DEPTH" -gt 4 ]; then
    [[ "$OUTPUT_FORMAT" != "json" ]] && log_warn "深度最大为 4，使用最大值 4"
    DEPTH=4
  fi

  # 验证方向
  case "$DIRECTION" in
    callers|callees|both) ;;
    *)
      [[ "$OUTPUT_FORMAT" != "json" ]] && log_warn "无效的方向: $DIRECTION，使用默认值 both"
      DIRECTION="both"
      ;;
  esac

  # M3: 验证数据流追踪参数
  if [ "$DATA_FLOW_ENABLED" = true ]; then
    # 验证数据流方向
    case "$DATA_FLOW_DIRECTION" in
      forward|backward|both) ;;
      *)
        [[ "$OUTPUT_FORMAT" != "json" ]] && log_warn "无效的数据流方向: $DATA_FLOW_DIRECTION，使用默认值 both"
        DATA_FLOW_DIRECTION="both"
        ;;
    esac

    # 验证数据流深度（REQ-DFT-006: 可配置范围 1-10）
    if ! [[ "$DATA_FLOW_MAX_DEPTH" =~ ^-?[0-9]+$ ]]; then
      log_error "data-flow depth 必须是整数"
      exit 1
    elif [ "$DATA_FLOW_MAX_DEPTH" -lt 1 ]; then
      log_error "data-flow depth 必须至少为 1"
      exit 1
    elif [ "$DATA_FLOW_MAX_DEPTH" -gt 10 ]; then
      [[ "$OUTPUT_FORMAT" != "json" ]] && log_warn "数据流深度最大为 10，使用最大值 10"
      DATA_FLOW_MAX_DEPTH=10
    fi
  fi

  if [ -n "$CWD" ] && [ ! -d "$CWD" ]; then
    log_error "invalid cwd: $CWD"
    exit 1
  fi
}

# ==================== 模拟数据 ====================

mock_call_chain() {
  local symbol="$1"
  local depth="$2"

  # 支持循环检测测试
  if [[ -n "${MOCK_SIMPLE_CYCLE:-}" ]]; then
    cat << EOF
[
  {"symbol_id": "ckb:test:sym:cyclic_a", "file_path": "src/cyclic_a.ts", "line": 10, "depth": 0, "is_cycle": false},
  {"symbol_id": "ckb:test:sym:cyclic_b", "file_path": "src/cyclic_b.ts", "line": 20, "depth": 1, "is_cycle": false},
  {"symbol_id": "ckb:test:sym:cyclic_a", "file_path": "src/cyclic_a.ts", "line": 10, "depth": 2, "is_cycle": true}
]
EOF
    return 0
  fi

  # 标准 Mock 数据
  local result='[]'

  # 根符号（depth 0）
  result=$(echo "$result" | jq --arg sym "ckb:test:sym:$symbol" \
    --arg file "src/${symbol}.ts" \
    '. + [{symbol_id: $sym, file_path: $file, line: 10, depth: 0, is_cycle: false}]')

  # 添加更多深度
  if [[ $depth -ge 1 ]]; then
    result=$(echo "$result" | jq \
      '. + [{symbol_id: "ckb:test:sym:helper", file_path: "src/helper.ts", line: 20, depth: 1, is_cycle: false}]')
  fi

  if [[ $depth -ge 2 ]]; then
    result=$(echo "$result" | jq \
      '. + [{symbol_id: "ckb:test:sym:util", file_path: "src/util.ts", line: 30, depth: 2, is_cycle: false}]')
  fi

  if [[ $depth -ge 3 ]]; then
    result=$(echo "$result" | jq \
      '. + [{symbol_id: "ckb:test:sym:core", file_path: "src/core.ts", line: 40, depth: 3, is_cycle: false}]')
  fi

  if [[ $depth -ge 4 ]]; then
    result=$(echo "$result" | jq \
      '. + [{symbol_id: "ckb:test:sym:base", file_path: "src/base.ts", line: 50, depth: 4, is_cycle: false}]')
  fi

  echo "$result"
}
