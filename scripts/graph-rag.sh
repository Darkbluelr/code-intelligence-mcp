#!/bin/bash
# DevBooks Graph-RAG Context Engine
#
# 功能：
#   1. 向量搜索：从 Embedding 索引检索相关代码片段
#   3. Token 预算：动态裁剪输出
#   4. 缓存：查询结果缓存
#
# 用法：
#   graph-rag-context.sh --query "查询内容" [选项]
#
# 验收标准：
#   AC-002: 10 个预设查询相关性 ≥ 70%
#   AC-007: graph_rag.enabled: false 时跳过
#   AC-008: P95 延迟 < 3s

set -euo pipefail

# ==================== 初始化 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CWD="${PROJECT_ROOT}"

# 加载共享工具库
COMMON_LIB="${SCRIPT_DIR}/common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck disable=SC2034  # LOG_PREFIX is used by common.sh
  LOG_PREFIX="Graph-RAG"
  # shellcheck source=common.sh
  source "$COMMON_LIB"
else
  # 降级：内联日志函数
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
  log_info()  { echo -e "${BLUE}[Graph-RAG]${NC} $1" >&2; }
  log_ok()    { echo -e "${GREEN}[Graph-RAG]${NC} $1" >&2; }
  log_warn()  { echo -e "${YELLOW}[Graph-RAG]${NC} $1" >&2; }
  log_error() { echo -e "${RED}[Graph-RAG]${NC} $1" >&2; }
fi

# 检查必需依赖
if declare -f check_dependencies &>/dev/null; then
  check_dependencies jq || exit 2
else
  command -v jq &>/dev/null || { log_error "缺少依赖: jq"; exit 2; }
fi

# ==================== 加载子模块 ====================

# shellcheck source=graph-rag-core.sh
source "${SCRIPT_DIR}/graph-rag-core.sh"

# shellcheck source=graph-rag-retrieval.sh
source "${SCRIPT_DIR}/graph-rag-retrieval.sh"

# 加载融合模块（RRF 融合、LLM 重排序）
# shellcheck source=graph-rag-fusion.sh
source "${SCRIPT_DIR}/graph-rag-fusion.sh"

# 加载查询处理模块（Token 预算、子图构建、主查询逻辑）
# shellcheck source=graph-rag-query.sh
source "${SCRIPT_DIR}/graph-rag-query.sh"

# ==================== 帮助 ====================

show_help() {
  cat << 'EOF'
DevBooks Graph-RAG Context Engine

用法:
  graph-rag-context.sh --query "查询内容" [选项]

选项:
  --query <text>        查询内容（必需）
  --top-k <n>           向量搜索返回数量（默认: 10）
  --depth <n>           图遍历最大深度 1-5（默认: 3）
  --fusion-depth <n>    融合查询深度 0-5（默认: 1，0=仅向量搜索）
  --fusion-weights <w>  混合检索权重 "keyword,vector,graph"（默认: 0.3,0.5,0.2，总和须=1.0）
  --token-budget <n>    Token 预算（默认: 8000）
  --budget <n>          同 --token-budget
  --min-relevance <n>   最低相关度阈值（默认: 0.0）
  --cwd <path>          工作目录（默认: 当前目录）
  --format <text|json>  输出格式（默认: text）
  --rerank              启用 LLM 重排序（默认关闭）
  --no-rerank           禁用重排序（CLI 覆盖配置）
  --legacy              使用线性列表输出（兼容旧版本）
  --include-virtual     包含虚拟边查询（实验性）
  --enable-all-features 忽略功能开关配置，强制启用所有功能
  --mock-embedding      使用模拟 Embedding 数据（测试用）
  --version             显示版本
  --help                显示此帮助

示例:
  # 基本用法
  graph-rag-context.sh --query "用户认证相关的函数"

  # 指定参数
  graph-rag-context.sh --query "处理支付的代码" --top-k 20 --max-depth 3

  # JSON 输出
  graph-rag-context.sh --query "错误处理" --format json

输出格式 (JSON):
  {
    "schema_version": "1.0",
    "source": "graph-rag",
    "token_count": 1234,
    "subgraph": {
      "nodes": [
        {
          "id": "src/auth.ts::handleAuth",
          "file_path": "src/auth.ts",
          "line_start": 10,
          "line_end": 25,
          "relevance_score": 0.85
        }
      ],
      "edges": [
        {
          "from": "src/auth.ts::handleAuth",
          "to": "src/user.ts::getUser",
          "type": "calls"
        },
        {
          "from": "src/handler.ts::main",
          "to": "src/auth.ts::handleAuth",
          "type": "refs"
        }
      ]
    },
    "candidates": [...],
    "metadata": {
      "graph_available": true,
      "graph_depth": 3,
      "boundary_filtered": 5
    }
  }

EOF
}

show_version() {
  echo "graph-rag-context.sh version 1.0.0"
}

# ==================== 参数解析 ====================

parse_args() {
  # Workaround: If first arg doesn't start with --, treat it as query
  # This handles cases where --query flag is dropped by MCP transport
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    QUERY="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --query)
        QUERY="$2"
        shift 2
        ;;
      --top-k)
        TOP_K="$2"
        shift 2
        ;;
      --depth|--max-depth)
        MAX_DEPTH="$2"
        shift 2
        ;;
      --fusion-depth)
        FUSION_DEPTH="$2"
        shift 2
        ;;
      --fusion-weights)
        # 解析权重: "keyword,vector,graph"
        IFS=',' read -r HYBRID_WEIGHT_KEYWORD HYBRID_WEIGHT_VECTOR HYBRID_WEIGHT_GRAPH <<< "$2"
        # 验证权重总和 = 1.0
        if command -v bc >/dev/null 2>&1; then
          local weight_sum diff is_valid
          weight_sum=$(echo "scale=4; $HYBRID_WEIGHT_KEYWORD + $HYBRID_WEIGHT_VECTOR + $HYBRID_WEIGHT_GRAPH" | bc)
          diff=$(echo "scale=4; x = $weight_sum - 1.0; if (x < 0) -x else x" | bc)
          is_valid=$(echo "$diff < 0.01" | bc)
          if [ "$is_valid" -ne 1 ]; then
            log_error "Invalid fusion-weights: sum must equal 1.0 (got $weight_sum)"
            exit 1
          fi
        else
          local weight_sum is_valid
          weight_sum=$(awk "BEGIN {printf \"%.4f\", $HYBRID_WEIGHT_KEYWORD + $HYBRID_WEIGHT_VECTOR + $HYBRID_WEIGHT_GRAPH}")
          is_valid=$(awk "BEGIN {diff = $weight_sum - 1.0; if (diff < 0) diff = -diff; print (diff < 0.01) ? 1 : 0}")
          if [ "$is_valid" -ne 1 ]; then
            log_error "Invalid fusion-weights: sum must equal 1.0 (got $weight_sum)"
            exit 1
          fi
        fi
        FUSION_WEIGHTS_SET=true
        shift 2
        ;;
      --token-budget|--budget)
        TOKEN_BUDGET="$2"
        shift 2
        ;;
      --min-relevance)
        MIN_RELEVANCE="$2"
        shift 2
        ;;
      --cwd)
        CWD="$2"
        PROJECT_ROOT="$2"
        if [[ -z "${FEATURES_CONFIG:-}" ]]; then
          FEATURES_CONFIG="$CWD/config/features.yaml"
        fi
        if [[ -z "${DEVBOOKS_FEATURE_CONFIG:-}" ]]; then
          DEVBOOKS_FEATURE_CONFIG="$CWD/config/features.yaml"
        fi
        shift 2
        ;;
      --format)
        OUTPUT_FORMAT="$2"
        shift 2
        ;;
      --legacy)
        LEGACY_MODE=true
        shift
        ;;
      --rerank)
        RERANK_ENABLED=true
        OUTPUT_FORMAT="json"  # 重排序模式默认使用 JSON 输出
        shift
        ;;
      --no-rerank)
        RERANK_ENABLED=false
        RERANK_CLI_DISABLED=true
        OUTPUT_FORMAT="json"
        shift
        ;;
      --include-virtual)
        INCLUDE_VIRTUAL=true
        shift
        ;;
      --enable-all-features)
        DEVBOOKS_ENABLE_ALL_FEATURES=1
        HYBRID_ENABLED=true
        shift
        ;;
      --mock-embedding)
        MOCK_EMBEDDING=true
        shift
        ;;
      --mock-graph)
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

  if [ -z "$QUERY" ]; then
    log_error "必须提供 --query 参数"
    exit 1
  fi

  # AC-003: 深度验证（1-5）
  if ! [[ "$MAX_DEPTH" =~ ^[0-9]+$ ]]; then
    log_warn "无效的深度值: $MAX_DEPTH, 使用默认值 3"
    MAX_DEPTH=3
  elif [ "$MAX_DEPTH" -lt 1 ]; then
    log_warn "深度最小为 1, 使用最小值"
    MAX_DEPTH=1
  elif [ "$MAX_DEPTH" -gt "$MAX_ALLOWED_DEPTH" ]; then
    log_warn "深度最大为 $MAX_ALLOWED_DEPTH, 使用最大值"
    MAX_DEPTH=$MAX_ALLOWED_DEPTH
  fi

  # MP4: 融合深度验证（0-5）
  if ! [[ "$FUSION_DEPTH" =~ ^[0-9]+$ ]]; then
    log_error "无效的融合深度值: $FUSION_DEPTH, 必须为 0-5 之间的整数"
    echo '{"error":"invalid fusion-depth: must be integer 0-5","code":"INVALID_PARAM"}'
    exit 1
  elif [ "$FUSION_DEPTH" -lt 0 ]; then
    log_error "融合深度不能为负数: $FUSION_DEPTH"
    echo '{"error":"invalid fusion-depth: cannot be negative","code":"INVALID_PARAM"}'
    exit 1
  elif [ "$FUSION_DEPTH" -gt "$MAX_ALLOWED_DEPTH" ]; then
    log_error "无效的融合深度值: $FUSION_DEPTH, 必须为 0-5 之间的整数"
    echo '{"error":"invalid fusion-depth: must be integer 0-5","code":"INVALID_PARAM"}'
    exit 1
  fi

  # JSON 输出模式下禁用日志（避免污染 JSON 输出）
  if [ "$OUTPUT_FORMAT" = "json" ]; then
    log_info()  { :; }
    log_ok()    { :; }
    log_warn()  { :; }
    log_error() { :; }
  fi

  # CT-PS-004: 从配置文件加载自定义权重
  _load_priority_weights
  _load_hybrid_weights

  if [[ "$HYBRID_ENABLED" != "true" ]] && [[ "$FUSION_DEPTH" -gt 0 ]]; then
    log_warn "hybrid_retrieval 已禁用，降级为向量检索"
    FUSION_DEPTH=0
  fi
}

# ==================== 主函数 ====================

main() {
  parse_args "$@"

  # 构建上下文
  local result
  result=$(build_context "$QUERY")

  # 输出结果
  output_result "$result"
}

main "$@"
