#!/bin/bash
# DevBooks Context Reranker
# 使用 LLM Provider 抽象层对候选上下文进行语义重排序
#
# 功能：
#   1. 接收候选列表 JSON
#   2. 使用可插拔的 LLM Provider 进行语义重排序
#   3. 返回重排序后的结果
#
# 用法：
#   reranker.sh --query "查询内容" [选项] < candidates.json
#   echo '{"candidates":[...]}' | reranker.sh --query "查询"
#
# 验收标准：
#   AC-001: 支持 Anthropic/OpenAI/Ollama/Mock 四种 Provider
#   AC-002: Provider 切换无需修改调用代码
#   AC-003: reranker.sh 成功执行，输出包含 ranked_results 字段
#   AC-007: reranker.enabled: false（默认）时跳过

set -euo pipefail

# P1-FIX: 添加 trap 清理机制
_cleanup() {
  # 清理临时文件（如果有）
  if [[ -n "${_TEMP_FILES:-}" ]]; then
    for f in $_TEMP_FILES; do
      [[ -f "$f" ]] && rm -f "$f" 2>/dev/null || true
    done
  fi
}
trap _cleanup EXIT INT TERM

# ==================== 配置 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 加载 LLM Provider 抽象层
if [[ -f "$SCRIPT_DIR/llm-provider.sh" ]]; then
  source "$SCRIPT_DIR/llm-provider.sh"
fi

# 加载共享函数库（如果未加载）
if ! type log_info &>/dev/null; then
  if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
  fi
fi

# 设置日志前缀
: "${LOG_PREFIX:=Reranker}"

# 默认参数
QUERY=""
MODEL=""
PROVIDER=""
MAX_CANDIDATES=20
RERANK_TIMEOUT_MS=5000
RERANK_STRATEGY="llm"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# 模式
MOCK_LLM=false
OUTPUT_FORMAT="json"

# ==================== 帮助 ====================

show_help() {
  cat << 'EOF'
DevBooks Context Reranker
使用 LLM Provider 抽象层对候选上下文进行语义重排序

用法:
  reranker.sh --query "查询内容" [选项] < candidates.json
  echo '{"candidates":[...]}' | reranker.sh --query "查询"

选项:
  --query <text>        查询内容（必需）
  --provider <name>     LLM Provider (anthropic/openai/ollama/mock，默认自动检测)
  --model <name>        重排序模型（默认根据 Provider 决定）
  --input <file>        输入文件（默认: stdin）
  --max <n>             最大候选数（默认: 20）
  --rerank-strategy <s> 重排序策略: llm | heuristic（默认: llm）
  --timeout-ms <ms>     LLM 超时毫秒（默认: 5000）
  --mock-llm            使用 Mock Provider（测试用）
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
    ],
    "provider": "anthropic"
  }

支持的 Provider:
  anthropic     Anthropic Claude (需要 ANTHROPIC_API_KEY)
  openai        OpenAI GPT (需要 OPENAI_API_KEY)
  ollama        本地 Ollama (需要运行 Ollama 服务)
  mock          测试用 Mock Provider

环境变量:
  ANTHROPIC_API_KEY      Anthropic API 密钥
  OPENAI_API_KEY         OpenAI API 密钥
  LLM_DEFAULT_PROVIDER   默认 Provider
  LLM_MODEL              覆盖默认模型
  LLM_MOCK_RESPONSE      Mock 响应（测试用）
  LLM_MOCK_DELAY_MS      Mock 延迟（测试用）
  LLM_MOCK_FAIL_COUNT    Mock 失败次数（测试用）

示例:
  # 使用自动检测的 Provider
  echo '{"candidates":[{"file_path":"a.ts","content":"..."}]}' | \
    reranker.sh --query "认证函数"

  # 指定使用 OpenAI
  reranker.sh --query "test" --provider openai < candidates.json

  # 测试模式
  reranker.sh --query "test" --mock-llm < candidates.json

EOF
}

show_version() {
  echo "reranker.sh version 2.0.0 (with LLM Provider abstraction)"
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
      --provider)
        PROVIDER="$2"
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
      --rerank-strategy)
        RERANK_STRATEGY="$2"
        shift 2
        ;;
      --timeout-ms)
        RERANK_TIMEOUT_MS="$2"
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

  if [[ -z "$QUERY" ]]; then
    log_error "必须提供 --query 参数"
    exit 1
  fi

  case "$RERANK_STRATEGY" in
    llm|heuristic) ;;
    *)
      log_error "无效的重排序策略: $RERANK_STRATEGY (支持: llm|heuristic)"
      exit 1
      ;;
  esac

  if ! [[ "$RERANK_TIMEOUT_MS" =~ ^[0-9]+$ ]]; then
    log_warn "无效的 timeout-ms: $RERANK_TIMEOUT_MS，使用默认值 5000"
    RERANK_TIMEOUT_MS=5000
  fi
}

# ==================== 输入读取 ====================

read_input() {
  if [[ -n "$INPUT_FILE" ]] && [[ -f "$INPUT_FILE" ]]; then
    cat "$INPUT_FILE"
  else
    # P1-FIX: 检测 stdin 是否有数据，避免无限等待
    if [[ -t 0 ]]; then
      # stdin 是终端且没有管道数据，报错退出
      log_error "未提供输入数据。请使用 --input <file> 或通过管道提供 JSON 数据。"
      log_error "示例: echo '{\"candidates\":[]}' | reranker.sh --query \"查询\""
      exit 1
    fi
    # stdin 有管道数据，正常读取
    cat
  fi
}

# ==================== Legacy Mock 函数 ====================

# 保留向后兼容的 mock_rerank 函数
legacy_mock_rerank() {
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
    score=$(echo "scale=2; 0.95 - $i * 0.05" | bc 2>/dev/null || echo "0.95")

    ranked=$(echo "$ranked" | jq --arg fp "$file_path" --argjson rank "$((i+1))" --argjson score "$score" \
      '. + [{file_path: $fp, rank: $rank, rerank_score: ($score | tonumber)}]')
  done

  echo "$ranked"
}

# ==================== 启发式重排序 ====================

get_mtime_seconds() {
  local path="$1"
  if [[ -f "$path" ]]; then
    if stat -f %m "$path" >/dev/null 2>&1; then
      stat -f %m "$path"
      return
    fi
    if stat -c %Y "$path" >/dev/null 2>&1; then
      stat -c %Y "$path"
      return
    fi
  fi
  echo ""
}

heuristic_rerank() {
  local candidates_json="$1"
  local now
  now=$(date +%s)

  local hotspot_list=()
  if type get_hotspot_files &>/dev/null; then
    while IFS= read -r hotspot; do
      [ -n "$hotspot" ] && hotspot_list+=("$hotspot")
    done < <(get_hotspot_files 20 2>/dev/null || true)
  fi

  local result='[]'
  local count
  count=$(echo "$candidates_json" | jq 'length')

  local limit="$count"
  if [[ "$limit" -gt "$MAX_CANDIDATES" ]]; then
    limit="$MAX_CANDIDATES"
  fi

  for ((i=0; i<limit; i++)); do
    local candidate file_path base_score ext ext_bonus mtime age_days recent_bonus hotspot_bonus final_score full_path
    candidate=$(echo "$candidates_json" | jq -c ".[$i]")
    file_path=$(echo "$candidate" | jq -r '.file_path // .file // ""')
    base_score=$(echo "$candidate" | jq -r '.relevance_score // .score // 0')

    ext="${file_path##*.}"
    case "$ext" in
      ts|tsx|js|jsx) ext_bonus="0.30" ;;
      sh) ext_bonus="0.10" ;;
      *) ext_bonus="0.00" ;;
    esac

    full_path="$PROJECT_ROOT/$file_path"
    mtime=$(get_mtime_seconds "$full_path")
    if [[ -n "$mtime" ]]; then
      age_days=$(( (now - mtime) / 86400 ))
      recent_bonus=$(awk -v days="$age_days" 'BEGIN {printf "%.3f", 0.30 / (1 + days)}')
    else
      recent_bonus="0.00"
    fi

    hotspot_bonus="0.00"
    if [[ ${#hotspot_list[@]} -gt 0 ]]; then
      for hotspot in "${hotspot_list[@]}"; do
        if [[ "$file_path" == "$hotspot" || "$file_path" == *"/$hotspot" ]]; then
          hotspot_bonus="0.40"
          break
        fi
      done
    fi

    final_score=$(awk -v base="$base_score" -v ext="$ext_bonus" -v recent="$recent_bonus" -v hot="$hotspot_bonus" \
      'BEGIN {printf "%.3f", base + ext + recent + hot}')

    result=$(echo "$result" | jq \
      --arg fp "$file_path" \
      --argjson score "$final_score" \
      --argjson base "$base_score" \
      --argjson recent "$recent_bonus" \
      --argjson hot "$hotspot_bonus" \
      --argjson ext "$ext_bonus" \
      '. + [{
        file_path: $fp,
        rerank_score: $score,
        heuristic_score: $score,
        components: {
          base: $base,
          recent: $recent,
          hotspot: $hot,
          extension: $ext
        }
      }]')
  done

  echo "$result" | jq 'sort_by(-.rerank_score) | to_entries | map(.value + {rank: (.key + 1)})'
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
  local used_provider="mock"

  # 处理 Mock 模式
  if [[ "$MOCK_LLM" == "true" ]]; then
    # 使用新的 Mock Provider
    PROVIDER="mock"
  fi

  # 设置环境变量供 Provider 使用
  [[ -n "$PROVIDER" ]] && export LLM_DEFAULT_PROVIDER="$PROVIDER"
  [[ -n "$MODEL" ]] && export LLM_MODEL="$MODEL"

  # 提取候选数组
  local candidates
  candidates=$(echo "$input" | jq -c '.candidates // []')

  # 限制候选数量
  local count
  count=$(echo "$candidates" | jq 'length')
  if [[ "$count" -gt "$MAX_CANDIDATES" ]]; then
    candidates=$(echo "$candidates" | jq -c ".[0:$MAX_CANDIDATES]")
    log_info "候选数量超过限制，截取前 $MAX_CANDIDATES 个"
  fi

  if [[ "$RERANK_STRATEGY" == "heuristic" ]]; then
    ranked=$(heuristic_rerank "$candidates" "$query")
    used_provider="heuristic"
  else
    export LLM_TIMEOUT_MS="$RERANK_TIMEOUT_MS"

    # 尝试使用 LLM Provider 抽象层
    if type llm_load_provider &>/dev/null; then
      # 加载 Provider
      if llm_load_provider "${PROVIDER:-}"; then
        used_provider=$(llm_get_current_provider)
        log_info "使用 Provider: $used_provider"

        # 调用 rerank
        local result
        if result=$(llm_rerank "$query" "$candidates" 2>/dev/null); then
          # 解析结果
          if echo "$result" | jq -e '.success == true' &>/dev/null; then
            # 从新格式转换为旧格式
            local raw_ranked
            raw_ranked=$(echo "$result" | jq -c '.ranked // []')

            # 转换格式：index/score/reason -> file_path/rank/rerank_score
            ranked='[]'
            local num_items
            num_items=$(echo "$raw_ranked" | jq 'length')

            local idx
            for ((idx=0; idx<num_items; idx++)); do
              local row orig_index score file_path rerank_score
              row=$(echo "$raw_ranked" | jq -c ".[$idx]")
              orig_index=$(echo "$row" | jq -r '.index // 0')
              score=$(echo "$row" | jq -r '.score // 5')
              # 从原始候选中获取 file_path
              file_path=$(echo "$candidates" | jq -r ".[$orig_index].file_path // .[$orig_index].file // \"file_$orig_index\"")

              # 将 1-10 分转换为 0-1 分
              rerank_score=$(echo "scale=2; $score / 10" | bc 2>/dev/null || echo "0.5")

              ranked=$(echo "$ranked" | jq \
                --arg fp "$file_path" \
                --argjson rank "$((idx + 1))" \
                --argjson score "$rerank_score" \
                '. + [{file_path: $fp, rank: $rank, rerank_score: ($score | tonumber)}]')
            done
          else
            log_warn "LLM Provider 调用失败，降级至启发式重排序"
            ranked=$(heuristic_rerank "$candidates" "$query")
            used_provider="heuristic"
          fi
        else
          log_warn "LLM rerank 失败或超时，降级至启发式重排序"
          ranked=$(heuristic_rerank "$candidates" "$query")
          used_provider="heuristic"
        fi
      else
        log_warn "Provider 加载失败，降级至启发式重排序"
        ranked=$(heuristic_rerank "$candidates" "$query")
        used_provider="heuristic"
      fi
    else
      # LLM Provider 抽象层不可用，使用启发式排序
      log_warn "LLM Provider 抽象层不可用，降级至启发式重排序"
      ranked=$(heuristic_rerank "$candidates" "$query")
      used_provider="heuristic"
    fi
  fi

  # 构建输出
  jq -n \
    --arg version "1.0" \
    --arg provider "$used_provider" \
    --argjson ranked "$ranked" \
    '{
      schema_version: $version,
      ranked_results: $ranked,
      provider: $provider
    }'
}

# ==================== 主函数 ====================

main() {
  parse_args "$@"

  # 读取输入
  local input
  input=$(read_input)

  if [[ -z "$input" ]]; then
    log_error "未提供输入数据"
    exit 1
  fi

  # 执行重排序
  rerank "$input" "$QUERY"
}

main "$@"
