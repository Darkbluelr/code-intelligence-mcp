#!/bin/bash
# DevBooks Context Reranker
# 使用 LLM (Haiku) 对候选上下文进行语义重排序
#
# 功能：
#   1. 接收候选列表 JSON
#   2. 调用 Anthropic API (Haiku) 进行语义重排序
#   3. 返回重排序后的结果
#
# 用法：
#   context-reranker.sh --query "查询内容" [选项] < candidates.json
#   echo '{"candidates":[...]}' | context-reranker.sh --query "查询"
#
# 验收标准：
#   AC-003: context-reranker.sh 成功执行，输出包含 ranked_results 字段
#   AC-007: reranker.enabled: false（默认）时跳过

set -e

# ==================== 配置 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 默认参数
QUERY=""
MODEL="haiku"
API_KEY="${ANTHROPIC_API_KEY:-}"
API_BASE_URL="https://api.anthropic.com/v1"
API_TIMEOUT=30
MAX_CANDIDATES=20

# 模式
MOCK_LLM=false
OUTPUT_FORMAT="json"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[Reranker]${NC} $1" >&2; }
log_ok()    { echo -e "${GREEN}[Reranker]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[Reranker]${NC} $1" >&2; }
log_error() { echo -e "${RED}[Reranker]${NC} $1" >&2; }

# ==================== 帮助 ====================

show_help() {
  cat << 'EOF'
DevBooks Context Reranker
使用 LLM (Haiku) 对候选上下文进行语义重排序

用法:
  context-reranker.sh --query "查询内容" [选项] < candidates.json
  echo '{"candidates":[...]}' | context-reranker.sh --query "查询"

选项:
  --query <text>        查询内容（必需）
  --model <name>        重排序模型（默认: haiku）
  --input <file>        输入文件（默认: stdin）
  --max <n>             最大候选数（默认: 20）
  --mock-llm            使用模拟 LLM 返回固定结果（测试用）
  --version             显示版本
  --help                显示此帮助

输入格式 (JSON):
  {
    "candidates": [
      {"file_path": "src/auth.ts", "relevance_score": 0.85, "content": "..."},
      {"file_path": "src/user.ts", "relevance_score": 0.75, "content": "..."}
    ]
  }

输出格式 (JSON):
  {
    "schema_version": "1.0",
    "ranked_results": [
      {"file_path": "src/auth.ts", "rank": 1, "rerank_score": 0.95},
      {"file_path": "src/user.ts", "rank": 2, "rerank_score": 0.80}
    ]
  }

环境变量:
  ANTHROPIC_API_KEY    Anthropic API 密钥

示例:
  # 基本用法
  echo '{"candidates":[{"file_path":"a.ts","content":"..."}]}' | \
    context-reranker.sh --query "认证函数"

  # 测试模式
  context-reranker.sh --query "test" --mock-llm < candidates.json

EOF
}

show_version() {
  echo "context-reranker.sh version 1.0.0"
}

# ==================== 参数解析 ====================

INPUT_FILE=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --query)
        QUERY="$2"
        shift 2
        ;;
      --model)
        MODEL="$2"
        shift 2
        ;;
      --input)
        INPUT_FILE="$2"
        shift 2
        ;;
      --max)
        MAX_CANDIDATES="$2"
        shift 2
        ;;
      --mock-llm)
        MOCK_LLM=true
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
}

# ==================== 输入读取 ====================

read_input() {
  if [ -n "$INPUT_FILE" ] && [ -f "$INPUT_FILE" ]; then
    cat "$INPUT_FILE"
  else
    cat
  fi
}

# ==================== 模拟 LLM ====================

mock_rerank() {
  local input="$1"
  local query="$2"

  # 提取候选列表
  local candidates
  candidates=$(echo "$input" | jq '.candidates // []')

  # 简单模拟：按原始顺序返回，添加递减的 rerank_score
  local count
  count=$(echo "$candidates" | jq 'length')

  local ranked='[]'
  for ((i=0; i<count && i<MAX_CANDIDATES; i++)); do
    local candidate
    candidate=$(echo "$candidates" | jq ".[$i]")
    local file_path
    file_path=$(echo "$candidate" | jq -r '.file_path')
    local score
    score=$(echo "scale=2; 0.95 - $i * 0.05" | bc)

    ranked=$(echo "$ranked" | jq --arg fp "$file_path" --argjson rank "$((i+1))" --argjson score "$score" \
      '. + [{file_path: $fp, rank: $rank, rerank_score: ($score | tonumber)}]')
  done

  echo "$ranked"
}

# ==================== Anthropic API 调用 ====================

call_anthropic_api() {
  local candidates_json="$1"
  local query="$2"

  if [ -z "$API_KEY" ]; then
    log_error "ANTHROPIC_API_KEY 未配置"
    return 1
  fi

  # 构建 prompt
  local candidate_list=""
  local count
  count=$(echo "$candidates_json" | jq '.candidates | length')

  for ((i=0; i<count && i<MAX_CANDIDATES; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".candidates[$i]")
    local file_path content
    file_path=$(echo "$candidate" | jq -r '.file_path')
    content=$(echo "$candidate" | jq -r '.content // ""' | head -c 500)

    candidate_list="${candidate_list}
[$i] $file_path
$content
---"
  done

  local prompt="Given the user query: \"$query\"

Please rank the following code candidates by relevance to the query. Return a JSON array with the ranked results.

Candidates:
$candidate_list

Return format (JSON only, no explanation):
[{\"file_path\": \"...\", \"rank\": 1, \"rerank_score\": 0.95}, ...]"

  # 选择模型
  local model_id="claude-3-5-haiku-20241022"
  if [ "$MODEL" = "sonnet" ]; then
    model_id="claude-sonnet-4-20250514"
  fi

  # 调用 API
  local response
  response=$(curl -s -X POST "${API_BASE_URL}/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    --max-time "$API_TIMEOUT" \
    -d "$(jq -n \
      --arg model "$model_id" \
      --arg prompt "$prompt" \
      '{
        model: $model,
        max_tokens: 1024,
        messages: [{role: "user", content: $prompt}]
      }')")

  # 检查错误
  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    local error_msg
    error_msg=$(echo "$response" | jq -r '.error.message // .error.type // "Unknown error"')
    log_error "API 错误: $error_msg"
    return 1
  fi

  # 提取结果
  local content
  content=$(echo "$response" | jq -r '.content[0].text // empty')

  if [ -z "$content" ]; then
    log_error "API 返回空内容"
    return 1
  fi

  # 尝试解析 JSON
  local ranked
  ranked=$(echo "$content" | grep -oE '\[.*\]' | head -1)

  if [ -z "$ranked" ]; then
    log_warn "无法解析 API 返回的 JSON，使用原始排序"
    mock_rerank "$candidates_json" "$query"
    return 0
  fi

  echo "$ranked"
}

# ==================== 主逻辑 ====================

rerank() {
  local input="$1"
  local query="$2"

  # 验证输入
  if ! echo "$input" | jq -e '.candidates' >/dev/null 2>&1; then
    log_error "输入格式错误：缺少 candidates 字段"
    exit 1
  fi

  local ranked

  if [ "$MOCK_LLM" = true ]; then
    ranked=$(mock_rerank "$input" "$query")
  else
    ranked=$(call_anthropic_api "$input" "$query")
    if [ $? -ne 0 ]; then
      log_warn "API 调用失败，使用模拟排序"
      ranked=$(mock_rerank "$input" "$query")
    fi
  fi

  # 构建输出
  jq -n \
    --arg version "1.0" \
    --argjson ranked "$ranked" \
    '{
      schema_version: $version,
      ranked_results: $ranked
    }'
}

# ==================== 主函数 ====================

main() {
  parse_args "$@"

  # 读取输入
  local input
  input=$(read_input)

  if [ -z "$input" ]; then
    log_error "未提供输入数据"
    exit 1
  fi

  # 执行重排序
  rerank "$input" "$QUERY"
}

main "$@"
