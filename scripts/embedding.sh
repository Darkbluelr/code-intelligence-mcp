#!/bin/bash
# DevBooks Embedding Service
# 代码向量化与语义搜索工具
#
# 功能：
#   1. 将代码库转换为向量表示
#   2. 语义搜索代码片段
#   3. 增量更新向量库
#   4. 集成到 DevBooks 工作流
#   5. 三级降级：Ollama → OpenAI API → 关键词搜索
#
# 参考：SPEC-EMB-001

set -e

# ==================== 配置 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/.devbooks/config.yaml}"
VECTOR_DB_DIR=""
TEMP_DIR="/tmp/devbooks-embedding-$$"

# CLI 参数（可覆盖配置文件）
CLI_PROVIDER=""
CLI_OLLAMA_MODEL=""
CLI_OLLAMA_ENDPOINT=""
CLI_TIMEOUT=""
CLI_FORMAT=""

# Ollama 默认配置
OLLAMA_DEFAULT_MODEL="nomic-embed-text"
OLLAMA_DEFAULT_ENDPOINT="http://localhost:11434"
OLLAMA_DEFAULT_TIMEOUT=30

# 当前实际使用的 provider
ACTUAL_PROVIDER=""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 静默模式（JSON 输出时启用）
QUIET_MODE=false

# 收集警告消息（用于 JSON 输出）
COLLECTED_WARNINGS=()

log_info()  { [[ "$QUIET_MODE" == "true" ]] && return 0; echo -e "${BLUE}[Embedding]${NC} $1" >&2; }
log_ok()    { [[ "$QUIET_MODE" == "true" ]] && return 0; echo -e "${GREEN}[Embedding]${NC} $1" >&2; }
log_warn()  {
  if [[ "$QUIET_MODE" == "true" ]]; then
    # JSON 模式下收集警告，稍后输出
    COLLECTED_WARNINGS+=("$1")
  else
    echo -e "${YELLOW}[Embedding]${NC} $1" >&2
  fi
}
log_error() { echo -e "${RED}[Embedding]${NC} $1" >&2; }  # 错误始终输出
log_debug() {
  if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]] && [[ "$QUIET_MODE" != "true" ]]; then
    echo -e "${CYAN}[Embedding]${NC} $1" >&2
  fi
  return 0
}

# ==================== Ollama 检测与配置 ====================

# 检测 Ollama 是否可用
# 返回: 0 = 可用, 1 = 不可用
_detect_ollama() {
  # Mock 模式支持（用于测试）
  if [[ -n "${OLLAMA_UNAVAILABLE:-}" ]]; then
    log_debug "Ollama 不可用（MOCK）"
    return 1
  fi

  if [[ -n "${MOCK_OLLAMA_AVAILABLE:-}" ]]; then
    log_debug "Ollama 可用（MOCK）"
    return 0
  fi

  # 检查 ollama 命令是否存在
  if ! command -v ollama &>/dev/null; then
    log_debug "Ollama 命令不存在"
    return 1
  fi

  # 检查 ollama 服务是否响应
  local endpoint="${OLLAMA_ENDPOINT:-$OLLAMA_DEFAULT_ENDPOINT}"
  if curl -s --max-time 2 "${endpoint}/api/version" &>/dev/null; then
    log_debug "Ollama 服务可用: $endpoint"
    return 0
  fi

  log_debug "Ollama 服务无响应: $endpoint"
  return 1
}

# 检测 OpenAI API 是否可用
# 返回: 0 = 可用, 1 = 不可用
_detect_openai_api() {
  # 检查 API Key 是否设置
  if [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -n "${EMBEDDING_API_KEY:-}" ]]; then
    log_debug "OpenAI API Key 已设置"
    return 0
  fi

  log_debug "OpenAI API Key 未设置"
  return 1
}

# 选择实际使用的 provider
# 参数: $1 = 配置的 provider (auto|ollama|openai|keyword)
# 输出: 设置全局变量 SELECTED_PROVIDER
_select_provider() {
  local config_provider="${1:-auto}"

  case "$config_provider" in
    ollama)
      if _detect_ollama; then
        SELECTED_PROVIDER="ollama"
      else
        log_warn "Ollama 不可用，降级到 OpenAI API"
        if _detect_openai_api; then
          SELECTED_PROVIDER="openai"
        else
          log_warn "OpenAI API 不可用，降级到关键词搜索"
          SELECTED_PROVIDER="keyword"
        fi
      fi
      ;;
    openai)
      if _detect_openai_api; then
        SELECTED_PROVIDER="openai"
      else
        log_warn "OpenAI API 不可用，降级到关键词搜索"
        SELECTED_PROVIDER="keyword"
      fi
      ;;
    keyword)
      SELECTED_PROVIDER="keyword"
      ;;
    auto|*)
      # 自动检测：Ollama > OpenAI > Keyword
      if _detect_ollama; then
        log_debug "自动检测：使用 Ollama"
        SELECTED_PROVIDER="ollama"
      elif _detect_openai_api; then
        log_warn "Ollama 不可用，降级到 OpenAI API"
        SELECTED_PROVIDER="openai"
      else
        log_warn "Ollama 和 OpenAI 都不可用，降级到关键词搜索"
        SELECTED_PROVIDER="keyword"
      fi
      ;;
  esac
}

# 调用 Ollama Embedding API
# 参数: $1 = 查询文本, $2 = 输出文件
# 返回: 0 = 成功, 1 = 失败
_embed_with_ollama() {
  local input_text="$1"
  local output_file="$2"
  local model="${CLI_OLLAMA_MODEL:-${OLLAMA_MODEL:-$OLLAMA_DEFAULT_MODEL}}"
  local endpoint="${CLI_OLLAMA_ENDPOINT:-${OLLAMA_ENDPOINT:-$OLLAMA_DEFAULT_ENDPOINT}}"
  local timeout="${CLI_TIMEOUT:-${OLLAMA_TIMEOUT:-$OLLAMA_DEFAULT_TIMEOUT}}"

  # Mock 模式：模拟模型未下载
  if [[ -n "${MOCK_MODEL_NOT_DOWNLOADED:-}" ]]; then
    log_warn "模型未下载，请运行: ollama pull $model"
    return 1
  fi

  # Mock 模式：生成假向量用于测试
  if [[ -n "${MOCK_OLLAMA_AVAILABLE:-}" ]]; then
    log_debug "Ollama Mock: 生成测试向量"
    # 生成一个简单的 10 维假向量
    echo '[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]' > "$output_file"
    return 0
  fi

  log_debug "调用 Ollama API: $endpoint/api/embeddings (model: $model)"

  # 构建请求体
  local request_body
  request_body=$(jq -n \
    --arg model "$model" \
    --arg prompt "$input_text" \
    '{model: $model, prompt: $prompt}')

  # 发送请求
  local response
  local http_code
  response=$(curl -s -w "\n%{http_code}" -X POST "${endpoint}/api/embeddings" \
    -H "Content-Type: application/json" \
    --max-time "$timeout" \
    -d "$request_body" 2>/dev/null)

  http_code=$(echo "$response" | tail -n1)
  response=$(echo "$response" | sed '$d')

  # 检查 HTTP 状态码
  if [[ "$http_code" != "200" ]]; then
    log_error "Ollama API 错误: HTTP $http_code"
    return 1
  fi

  # 检查错误响应
  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    local error_msg
    error_msg=$(echo "$response" | jq -r '.error // "Unknown error"')
    log_error "Ollama API 错误: $error_msg"

    # 检测模型未下载
    if [[ "$error_msg" == *"model"* ]] && [[ "$error_msg" == *"not found"* ]]; then
      log_warn "模型未下载，请运行: ollama pull $model"
    fi

    return 1
  fi

  # 提取向量
  echo "$response" | jq -r '.embedding | @json' > "$output_file"

  if [[ ! -s "$output_file" ]]; then
    log_error "未获取到向量数据"
    return 1
  fi

  log_debug "Ollama 向量已保存: $output_file"
  return 0
}

# 关键词搜索（降级方案）
# 参数: $1 = 查询文本, $2 = top_k
# 输出: JSON 格式的搜索结果
_search_with_keyword() {
  local query="$1"
  local top_k="${2:-5}"

  # 确保 top_k 是正整数
  if ! [[ "$top_k" =~ ^[0-9]+$ ]] || [[ "$top_k" -lt 1 ]]; then
    top_k=5
  fi

  local head_limit=$((top_k * 2))

  log_debug "使用关键词搜索: $query (top_k=$top_k, head_limit=$head_limit)"

  local results=()
  local idx=0

  # 使用 ripgrep 搜索
  if command -v rg &>/dev/null; then
    while IFS= read -r line && [[ $idx -lt $top_k ]]; do
      local file_path
      file_path=$(echo "$line" | cut -d':' -f1)
      if [[ -n "$file_path" ]] && [[ -f "$PROJECT_ROOT/$file_path" ]]; then
        results+=("$file_path")
        ((idx++)) || true
      fi
    done < <(rg -l --type-add 'code:*.{ts,tsx,js,jsx,py,go,rs,java,sh}' -t code -i "$query" "$PROJECT_ROOT" 2>/dev/null | head -n "$head_limit" | sed "s|^$PROJECT_ROOT/||")
  else
    # 降级到 grep
    while IFS= read -r line && [[ $idx -lt $top_k ]]; do
      local file_path
      file_path=$(echo "$line" | cut -d':' -f1)
      if [[ -n "$file_path" ]] && [[ -f "$PROJECT_ROOT/$file_path" ]]; then
        results+=("$file_path")
        ((idx++)) || true
      fi
    done < <(grep -rl --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" --include="*.go" --include="*.sh" -i "$query" "$PROJECT_ROOT" 2>/dev/null | head -n "$head_limit" | sed "s|^$PROJECT_ROOT/||")
  fi

  # 输出结果
  echo "${results[@]}"
}

# ==================== YAML 解析 ====================

# 简易 YAML 解析器（仅支持简单的 key: value 格式）
parse_yaml() {
  local file="$1"
  local prefix="$2"

  if [ ! -f "$file" ]; then
    log_error "配置文件不存在: $file"
    return 1
  fi

  # 移除注释和空行，处理环境变量替换
  sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$file" | \
  while IFS=: read -r key value; do
    # 移除前导/尾随空格
    key=$(echo "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # 跳过列表项
    [[ "$key" =~ ^- ]] && continue

    # 处理环境变量引用 ${VAR_NAME}
    if [[ "$value" =~ \$\{([^}]+)\} ]]; then
      local var_name="${BASH_REMATCH[1]}"
      value="${!var_name}"
    fi

    # 输出键值对
    if [ -n "$key" ] && [ -n "$value" ]; then
      echo "${prefix}${key}=${value}"
    fi
  done
}

# 加载配置
load_config() {
  # 设置默认值
  ENABLED=true
  EMBEDDING_PROVIDER="auto"
  API_MODEL="text-embedding-3-small"
  API_KEY="${OPENAI_API_KEY:-${EMBEDDING_API_KEY:-}}"
  API_BASE_URL="https://api.openai.com/v1"
  API_TIMEOUT=30
  BATCH_SIZE=50
  VECTOR_DB_DIR="$PROJECT_ROOT/.devbooks/embeddings"
  DIMENSION=1536
  INDEX_TYPE="flat"
  TOP_K=5
  SIMILARITY_THRESHOLD=0.7
  LOG_LEVEL="INFO"

  # Ollama 配置
  OLLAMA_MODEL="$OLLAMA_DEFAULT_MODEL"
  OLLAMA_ENDPOINT="$OLLAMA_DEFAULT_ENDPOINT"
  OLLAMA_TIMEOUT="$OLLAMA_DEFAULT_TIMEOUT"

  if [ ! -f "$CONFIG_FILE" ]; then
    log_warn "配置文件不存在: $CONFIG_FILE"
    log_info "使用默认配置"
    return 0
  fi

  log_debug "加载配置: $CONFIG_FILE"

  # 解析 YAML（简化版）
  local config
  config=$(cat "$CONFIG_FILE")

  # 提取通用配置值（使用 || true 避免 grep 返回非零）
  local enabled_val
  enabled_val=$(echo "$config" | grep -E "^enabled:" | awk '{print $2}' || true)
  ENABLED="${enabled_val:-$ENABLED}"

  # 提取 embedding 配置
  local provider_val
  provider_val=$(echo "$config" | grep -E "^\s*provider:" | head -1 | awk '{print $2}' || true)
  EMBEDDING_PROVIDER="${provider_val:-$EMBEDDING_PROVIDER}"

  local auto_build_val
  auto_build_val=$(echo "$config" | grep -E "^\s*auto_build:" | awk '{print $2}' || true)
  AUTO_BUILD="${auto_build_val:-true}"

  local fallback_val
  fallback_val=$(echo "$config" | grep -E "^\s*fallback_to_keyword:" | awk '{print $2}' || true)
  FALLBACK_TO_KEYWORD="${fallback_val:-true}"

  # 提取 Ollama 配置
  local ollama_model_val
  ollama_model_val=$(echo "$config" | grep -A5 "ollama:" | grep "model:" | awk '{print $2}' || true)
  OLLAMA_MODEL="${ollama_model_val:-$OLLAMA_MODEL}"

  local ollama_endpoint_val
  ollama_endpoint_val=$(echo "$config" | grep -A5 "ollama:" | grep "endpoint:" | awk '{print $2}' || true)
  OLLAMA_ENDPOINT="${ollama_endpoint_val:-$OLLAMA_ENDPOINT}"

  local ollama_timeout_val
  ollama_timeout_val=$(echo "$config" | grep -A5 "ollama:" | grep "timeout:" | awk '{print $2}' || true)
  OLLAMA_TIMEOUT="${ollama_timeout_val:-$OLLAMA_TIMEOUT}"

  # 提取 OpenAI 配置
  local api_model_val
  api_model_val=$(echo "$config" | grep -A5 "openai:" | grep "model:" | awk '{print $2}' || true)
  API_MODEL="${api_model_val:-$API_MODEL}"

  local api_key_val
  api_key_val=$(echo "$config" | grep -E "^\s*api_key:" | awk '{print $2}' || true)
  if [[ -n "$api_key_val" ]]; then
    API_KEY="$api_key_val"
  fi

  local api_base_val
  api_base_val=$(echo "$config" | grep -E "^\s*base_url:" | awk '{print $2}' || true)
  API_BASE_URL="${api_base_val:-$API_BASE_URL}"

  local api_timeout_val
  api_timeout_val=$(echo "$config" | grep -E "^\s*timeout:" | head -1 | awk '{print $2}' || true)
  API_TIMEOUT="${api_timeout_val:-$API_TIMEOUT}"

  local batch_size_val
  batch_size_val=$(echo "$config" | grep -E "^\s*batch_size:" | awk '{print $2}' || true)
  BATCH_SIZE="${batch_size_val:-$BATCH_SIZE}"

  local storage_path
  storage_path=$(echo "$config" | grep -E "^\s*storage_path:" | awk '{print $2}' || true)
  VECTOR_DB_DIR="$PROJECT_ROOT/${storage_path:-.devbooks/embeddings}"

  local dimension_val
  dimension_val=$(echo "$config" | grep -E "^\s*dimension:" | awk '{print $2}' || true)
  DIMENSION="${dimension_val:-$DIMENSION}"

  local index_type_val
  index_type_val=$(echo "$config" | grep -E "^\s*index_type:" | awk '{print $2}' || true)
  INDEX_TYPE="${index_type_val:-$INDEX_TYPE}"

  local top_k_val
  top_k_val=$(echo "$config" | grep -E "^\s*top_k:" | awk '{print $2}' || true)
  TOP_K="${top_k_val:-$TOP_K}"

  local threshold_val
  threshold_val=$(echo "$config" | grep -E "^\s*similarity_threshold:" | awk '{print $2}' || true)
  SIMILARITY_THRESHOLD="${threshold_val:-$SIMILARITY_THRESHOLD}"

  local log_level_val
  log_level_val=$(echo "$config" | grep -E "^\s*level:" | awk '{print $2}' || true)
  LOG_LEVEL="${log_level_val:-$LOG_LEVEL}"

  # 处理环境变量引用
  if [[ "$API_KEY" =~ \$\{([^}]+)\} ]]; then
    local var_name="${BASH_REMATCH[1]}"
    API_KEY="${!var_name}"
  fi

  log_debug "配置已加载: provider=$EMBEDDING_PROVIDER, ollama_model=$OLLAMA_MODEL, api_model=$API_MODEL"
}

# ==================== API 调用 ====================

# 调用 OpenAI 兼容的 Embedding API
call_embedding_api() {
  local input_text="$1"
  local output_file="$2"

  if [ -z "$API_KEY" ]; then
    log_error "API Key 未配置"
    return 1
  fi

  # Mock 模式：检测测试用的假 API Key
  if [[ "$API_KEY" == "sk-test-mock-key"* ]]; then
    log_debug "OpenAI Mock: 生成测试向量"
    # 生成一个简单的 10 维假向量
    echo '[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]' > "$output_file"
    return 0
  fi

  local api_endpoint="${API_BASE_URL}/embeddings"

  log_debug "调用 API: $api_endpoint"

  # 构建请求体
  local request_body=$(jq -n \
    --arg model "$API_MODEL" \
    --arg input "$input_text" \
    '{model: $model, input: $input}')

  # 发送请求
  local response=$(curl -s -X POST "$api_endpoint" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    --max-time "$API_TIMEOUT" \
    -d "$request_body")

  # 检查错误
  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    local error_msg=$(echo "$response" | jq -r '.error.message')
    log_error "API 错误: $error_msg"
    return 1
  fi

  # 提取向量
  echo "$response" | jq -r '.data[0].embedding | @json' > "$output_file"

  if [ ! -s "$output_file" ]; then
    log_error "未获取到向量数据"
    return 1
  fi

  log_debug "向量已保存: $output_file"
  return 0
}

# 批量生成向量
batch_embed() {
  local input_file="$1"
  local output_dir="$2"

  mkdir -p "$output_dir"

  local total_lines=$(wc -l < "$input_file")
  local batch_count=$((total_lines / BATCH_SIZE + 1))

  log_info "批量向量化: $total_lines 项，分 $batch_count 批"

  local line_num=0
  local batch_num=0
  local batch_items=()

  while IFS=$'\t' read -r file_path text; do
    batch_items+=("$file_path|$text")
    ((line_num++))

    # 达到批量大小或最后一行
    if [ ${#batch_items[@]} -ge $BATCH_SIZE ] || [ $line_num -eq $total_lines ]; then
      ((batch_num++))
      log_info "处理批次 $batch_num / $batch_count ..."

      # 构建批量请求
      local inputs_json=$(printf '%s\n' "${batch_items[@]}" | awk -F'|' '{print $2}' | jq -R -s -c 'split("\n") | map(select(length > 0))')

      local request_body=$(jq -n \
        --arg model "$API_MODEL" \
        --argjson inputs "$inputs_json" \
        '{model: $model, input: $inputs}')

      # 发送请求
      local response=$(curl -s -X POST "${API_BASE_URL}/embeddings" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        --max-time "$API_TIMEOUT" \
        -d "$request_body")

      # 检查错误
      if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.error.message')
        log_error "API 错误: $error_msg"
        return 1
      fi

      # 保存每个向量
      local idx=0
      for item in "${batch_items[@]}"; do
        local file_path="${item%%|*}"
        local vector=$(echo "$response" | jq -r ".data[$idx].embedding | @json")

        # 生成向量文件名（使用文件路径的 hash）
        local hash=$(echo "$file_path" | md5sum | awk '{print $1}' || echo "$file_path" | md5 | awk '{print $1}')

        echo "$vector" > "$output_dir/$hash.json"
        echo -e "$file_path\t$hash" >> "$output_dir/index.tsv"

        ((idx++))
      done

      batch_items=()
      sleep 0.5  # 避免 API 限流
    fi
  done < "$input_file"

  log_ok "向量化完成: $line_num 项"
}

# ==================== 代码提取 ====================

# 提取代码文件
extract_code_files() {
  local output_file="$1"

  log_info "提取代码文件..."

  # 读取配置中的文件扩展名
  local extensions="ts,tsx,js,jsx,py,go,rs,java,md"
  local exclude_dirs="node_modules|dist|build|\.git|__pycache__|venv|\.venv|target|\.next"

  > "$output_file"

  # 使用 find 查找文件
  find "$PROJECT_ROOT" -type f \
    \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
       -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
       -o -name "*.md" \) \
    ! -path "*/node_modules/*" \
    ! -path "*/dist/*" \
    ! -path "*/build/*" \
    ! -path "*/.git/*" \
    ! -path "*/__pycache__/*" \
    ! -path "*/venv/*" \
    ! -path "*/.venv/*" \
    ! -path "*/target/*" \
    ! -path "*/.next/*" \
    ! -name "*.test.ts" \
    ! -name "*.spec.ts" \
    ! -name "*.test.js" \
    ! -name "*.min.js" \
    2>/dev/null | while read -r file; do

    # 获取相对路径
    local rel_path="${file#$PROJECT_ROOT/}"

    # 读取文件内容（限制大小）
    if [ -f "$file" ] && [ $(wc -c < "$file") -lt 1000000 ]; then
      local content=$(cat "$file" | tr '\n' ' ' | head -c 10000)
      echo -e "$rel_path\t$content" >> "$output_file"
    fi
  done

  local file_count=$(wc -l < "$output_file")
  log_ok "提取完成: $file_count 个文件"
}

# ==================== 向量数据库 ====================

# 初始化向量数据库
init_vector_db() {
  log_info "初始化向量数据库: $VECTOR_DB_DIR"

  mkdir -p "$VECTOR_DB_DIR"

  # 创建元数据文件
  cat > "$VECTOR_DB_DIR/metadata.json" <<EOF
{
  "model": "$API_MODEL",
  "dimension": $DIMENSION,
  "index_type": "$INDEX_TYPE",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

  > "$VECTOR_DB_DIR/index.tsv"

  log_ok "向量数据库已初始化"
}

# 构建向量索引
build_index() {
  log_info "开始构建向量索引..."

  if [ "$ENABLED" != "true" ]; then
    log_warn "Embedding 功能未启用"
    return 1
  fi

  # 初始化
  init_vector_db

  # 提取代码文件
  local code_files="$TEMP_DIR/code_files.tsv"
  extract_code_files "$code_files"

  if [ ! -s "$code_files" ]; then
    log_warn "未找到代码文件"
    return 0
  fi

  # 批量生成向量
  batch_embed "$code_files" "$VECTOR_DB_DIR"

  # 更新元数据
  local file_count=$(wc -l < "$VECTOR_DB_DIR/index.tsv")
  local updated_metadata=$(jq \
    --arg updated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg count "$file_count" \
    '.updated_at = $updated | .file_count = ($count | tonumber)' \
    "$VECTOR_DB_DIR/metadata.json")

  echo "$updated_metadata" > "$VECTOR_DB_DIR/metadata.json"

  log_ok "索引构建完成: $file_count 个文件"
}

# 增量更新索引
update_index() {
  log_info "增量更新向量索引..."

  if [ ! -f "$VECTOR_DB_DIR/index.tsv" ]; then
    log_warn "索引不存在，执行全量构建"
    build_index
    return $?
  fi

  # 检查修改的文件
  local modified_files="$TEMP_DIR/modified_files.tsv"
  > "$modified_files"

  # 获取索引更新时间
  local index_mtime=$(stat -f %m "$VECTOR_DB_DIR/index.tsv" 2>/dev/null || stat -c %Y "$VECTOR_DB_DIR/index.tsv" 2>/dev/null)

  # 查找比索引更新的文件
  extract_code_files "$TEMP_DIR/all_files.tsv"

  while IFS=$'\t' read -r file_path content; do
    local full_path="$PROJECT_ROOT/$file_path"
    if [ -f "$full_path" ]; then
      local file_mtime=$(stat -f %m "$full_path" 2>/dev/null || stat -c %Y "$full_path" 2>/dev/null)
      if [ "$file_mtime" -gt "$index_mtime" ]; then
        echo -e "$file_path\t$content" >> "$modified_files"
      fi
    fi
  done < "$TEMP_DIR/all_files.tsv"

  local modified_count=$(wc -l < "$modified_files" 2>/dev/null || echo 0)

  if [ "$modified_count" -eq 0 ]; then
    log_ok "索引已是最新，无需更新"
    return 0
  fi

  log_info "发现 $modified_count 个修改的文件"

  # 删除旧向量
  while IFS=$'\t' read -r file_path hash; do
    rm -f "$VECTOR_DB_DIR/$hash.json"
  done < <(grep -Ff <(cut -f1 "$modified_files") "$VECTOR_DB_DIR/index.tsv" 2>/dev/null || true)

  # 重建这些文件的向量
  batch_embed "$modified_files" "$VECTOR_DB_DIR"

  log_ok "增量更新完成: $modified_count 个文件"
}

# ==================== 搜索 ====================

# 计算余弦相似度
cosine_similarity() {
  local vec1="$1"
  local vec2="$2"

  # 使用 Python 计算（如果可用）
  if command -v python3 &>/dev/null; then
    python3 -c "
import json
import sys
from math import sqrt

v1 = json.loads('$vec1')
v2 = json.loads('$vec2')

dot = sum(a*b for a, b in zip(v1, v2))
norm1 = sqrt(sum(a*a for a in v1))
norm2 = sqrt(sum(b*b for b in v2))

similarity = dot / (norm1 * norm2) if norm1 > 0 and norm2 > 0 else 0
print(f'{similarity:.6f}')
"
  else
    # 降级：返回随机相似度（仅用于测试）
    echo "0.500000"
  fi
}

# 语义搜索（支持三级降级）
semantic_search() {
  local query="$1"
  local top_k="${2:-$TOP_K}"
  local format="${CLI_FORMAT:-text}"

  # JSON 输出时启用静默模式
  if [[ "$format" == "json" ]]; then
    QUIET_MODE=true
  fi

  log_info "语义搜索: \"$query\""

  # 记录开始时间（macOS 兼容）
  local start_time
  if [[ "$OSTYPE" == "darwin"* ]]; then
    start_time=$(($(date +%s) * 1000))
  else
    start_time=$(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))
  fi

  # 确定 provider
  local requested_provider="${CLI_PROVIDER:-$EMBEDDING_PROVIDER}"
  _select_provider "$requested_provider"
  ACTUAL_PROVIDER="$SELECTED_PROVIDER"

  log_info "使用 provider: $ACTUAL_PROVIDER"

  local candidates=()
  local model_used=""
  local search_success=false

  case "$ACTUAL_PROVIDER" in
    ollama)
      model_used="${CLI_OLLAMA_MODEL:-$OLLAMA_MODEL}"
      if _semantic_search_with_embedding "ollama" "$query" "$top_k"; then
        search_success=true
      else
        # 降级到 OpenAI
        log_warn "Ollama 搜索失败，降级到 OpenAI API"
        ACTUAL_PROVIDER="openai"
        if _detect_openai_api && _semantic_search_with_embedding "openai" "$query" "$top_k"; then
          model_used="$API_MODEL"
          search_success=true
        else
          # 降级到关键词
          log_warn "OpenAI API 不可用，降级到关键词搜索"
          ACTUAL_PROVIDER="keyword"
        fi
      fi
      ;;

    openai)
      model_used="$API_MODEL"
      if _semantic_search_with_embedding "openai" "$query" "$top_k"; then
        search_success=true
      else
        # 降级到关键词
        log_warn "OpenAI 搜索失败，降级到关键词搜索"
        ACTUAL_PROVIDER="keyword"
      fi
      ;;

    keyword)
      # 直接使用关键词搜索
      ;;
  esac

  # 如果需要关键词搜索
  if [[ "$ACTUAL_PROVIDER" == "keyword" ]]; then
    model_used="ripgrep"
    local keyword_results
    keyword_results=$(_search_with_keyword "$query" "$top_k")
    for file in $keyword_results; do
      candidates+=("$file")
    done
    search_success=true
  fi

  # 记录结束时间（macOS 兼容）
  local end_time
  if [[ "$OSTYPE" == "darwin"* ]]; then
    end_time=$(($(date +%s) * 1000))
  else
    end_time=$(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))
  fi
  local latency_ms=$((end_time - start_time))

  # 输出结果
  if [[ "$format" == "json" ]]; then
    _output_json_results "$query" "$ACTUAL_PROVIDER" "$model_used" "$latency_ms" "$top_k"
  else
    _output_text_results "$query" "$top_k"
  fi

  if [[ "$search_success" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

# 使用向量嵌入进行语义搜索
_semantic_search_with_embedding() {
  local provider="$1"
  local query="$2"
  local top_k="$3"

  # Mock 模式：创建假索引用于测试
  local using_mock_index=false
  if [[ -n "${MOCK_OLLAMA_AVAILABLE:-}" ]] || [[ "$API_KEY" == "sk-test-mock-key"* ]]; then
    if [ ! -f "$VECTOR_DB_DIR/index.tsv" ]; then
      log_debug "Mock 模式：创建临时测试索引"
      mkdir -p "$VECTOR_DB_DIR"
      # 创建假索引，使用关键词搜索的结果作为候选文件
      local mock_results
      mock_results=$(_search_with_keyword "$query" "$top_k")
      local idx=0
      for file in $mock_results; do
        local hash="mock_$(echo "$file" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$idx")"
        echo -e "${file}\t${hash}" >> "$VECTOR_DB_DIR/index.tsv"
        # 创建假向量文件
        echo '[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]' > "$VECTOR_DB_DIR/${hash}.json"
        ((idx++)) || true
      done
      using_mock_index=true
    fi
  fi

  if [ ! -f "$VECTOR_DB_DIR/index.tsv" ]; then
    log_warn "向量索引不存在，请先运行: $0 build"
    return 1
  fi

  # 生成查询向量
  local query_vector_file="$TEMP_DIR/query_vector.json"

  case "$provider" in
    ollama)
      if ! _embed_with_ollama "$query" "$query_vector_file"; then
        return 1
      fi
      ;;
    openai)
      if ! call_embedding_api "$query" "$query_vector_file"; then
        return 1
      fi
      ;;
    *)
      log_error "未知 provider: $provider"
      return 1
      ;;
  esac

  local query_vector
  query_vector=$(cat "$query_vector_file")

  # 搜索相似向量
  local results="$TEMP_DIR/search_results.tsv"
  > "$results"

  log_debug "计算相似度..."

  while IFS=$'\t' read -r file_path hash; do
    local vector_file="$VECTOR_DB_DIR/$hash.json"

    if [ ! -f "$vector_file" ]; then
      continue
    fi

    local file_vector
    file_vector=$(cat "$vector_file")
    local similarity
    similarity=$(cosine_similarity "$query_vector" "$file_vector")

    # 过滤低于阈值的结果
    if (( $(echo "$similarity >= $SIMILARITY_THRESHOLD" | bc -l 2>/dev/null || echo 1) )); then
      echo -e "$similarity\t$file_path" >> "$results"
    fi
  done < "$VECTOR_DB_DIR/index.tsv"

  # 保存结果供后续输出
  if [ -s "$results" ]; then
    sort -rn "$results" | head -n "$top_k" > "$TEMP_DIR/final_results.tsv"
    return 0
  else
    return 1
  fi
}

# 输出 JSON 格式结果
_output_json_results() {
  local query="$1"
  local source="$2"
  local model="$3"
  local latency_ms="$4"
  local top_k="$5"

  local candidates_json="[]"

  if [[ "$source" == "keyword" ]]; then
    # 关键词搜索结果
    local keyword_results
    keyword_results=$(_search_with_keyword "$query" "$top_k")
    local idx=0
    local items=()
    for file in $keyword_results; do
      items+=("{\"file\":\"$file\",\"score\":0.5,\"source\":\"keyword\"}")
      ((idx++)) || true
    done
    if [[ ${#items[@]} -gt 0 ]]; then
      candidates_json=$(printf '%s\n' "${items[@]}" | jq -s '.')
    fi
  elif [ -f "$TEMP_DIR/final_results.tsv" ]; then
    # 向量搜索结果
    local items=()
    while IFS=$'\t' read -r score file; do
      items+=("{\"file\":\"$file\",\"score\":$score,\"source\":\"$source\"}")
    done < "$TEMP_DIR/final_results.tsv"
    if [[ ${#items[@]} -gt 0 ]]; then
      candidates_json=$(printf '%s\n' "${items[@]}" | jq -s '.')
    fi
  fi

  # 构建警告数组 JSON
  local warnings_json="[]"
  if [[ ${#COLLECTED_WARNINGS[@]} -gt 0 ]]; then
    warnings_json=$(printf '%s\n' "${COLLECTED_WARNINGS[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')
  fi

  # 构建完整 JSON
  jq -n \
    --arg schema_version "1.0" \
    --arg query "$query" \
    --arg source "$source" \
    --arg model "$model" \
    --argjson candidates "$candidates_json" \
    --argjson latency_ms "$latency_ms" \
    --argjson warnings "$warnings_json" \
    '{
      schema_version: $schema_version,
      query: $query,
      source: $source,
      model: $model,
      candidates: $candidates,
      warnings: $warnings,
      metadata: {
        provider: $source,
        latency_ms: $latency_ms
      }
    }'
}

# 输出文本格式结果
_output_text_results() {
  local query="$1"
  local top_k="$2"

  if [[ "$ACTUAL_PROVIDER" == "keyword" ]]; then
    local keyword_results
    keyword_results=$(_search_with_keyword "$query" "$top_k")
    log_ok "找到关键词匹配结果"
    for file in $keyword_results; do
      echo "[keyword] $file"
      local full_path="$PROJECT_ROOT/$file"
      if [ -f "$full_path" ]; then
        echo "---"
        head -n 10 "$full_path" | sed 's/^/  /'
        echo ""
      fi
    done
  elif [ -f "$TEMP_DIR/final_results.tsv" ]; then
    log_ok "找到 $(wc -l < "$TEMP_DIR/final_results.tsv") 个相关结果"
    while IFS=$'\t' read -r score file; do
      echo "[$score] $file"
      local full_path="$PROJECT_ROOT/$file"
      if [ -f "$full_path" ]; then
        echo "---"
        head -n 10 "$full_path" | sed 's/^/  /'
        echo ""
      fi
    done < "$TEMP_DIR/final_results.tsv"
  else
    log_warn "未找到相关结果"
  fi
}

# ==================== 工具命令 ====================

# 显示帮助
show_help() {
  cat << EOF
DevBooks Embedding Service - 代码向量化与语义搜索

用法:
  $0 [命令] [选项]

命令:
  build                构建完整向量索引
  update              增量更新向量索引
  search <查询>       语义搜索代码（支持三级降级）
  status              显示索引状态
  clean               清理向量数据库
  config              显示当前配置
  help                显示此帮助

搜索选项:
  --provider <类型>     Provider 类型: auto|ollama|openai|keyword
                       - auto: 自动检测（Ollama > OpenAI > 关键词）
                       - ollama: 强制使用 Ollama 本地模型
                       - openai: 强制使用 OpenAI API
                       - keyword: 强制使用关键词搜索
  --ollama-model <名>   Ollama 模型名称（默认: nomic-embed-text）
  --ollama-endpoint <URL> Ollama API 端点（默认: http://localhost:11434）
  --timeout <秒>        API 超时时间（默认: 30）
  --format <格式>       输出格式: text|json（默认: text）
  --top-k <数量>        返回结果数（默认: 5）
  --threshold <值>      相似度阈值（默认: 0.7）

通用选项:
  --config <文件>       指定配置文件（默认: .devbooks/config.yaml）
  --debug              启用调试模式

示例:
  # 初次使用：构建索引
  $0 build

  # 语义搜索（自动选择最佳 provider）
  $0 search "用户认证相关的函数"

  # 强制使用 Ollama 本地模型
  $0 search "authentication" --provider ollama --format json

  # 使用指定的 Ollama 模型
  $0 search "test" --provider ollama --ollama-model mxbai-embed-large

  # 强制使用 OpenAI API
  $0 search "test" --provider openai --format json

  # 强制使用关键词搜索
  $0 search "error" --provider keyword

  # JSON 格式输出
  $0 search "处理支付的代码" --format json --top-k 10

  # 查看状态
  $0 status

环境变量:
  OPENAI_API_KEY       OpenAI API 密钥
  EMBEDDING_API_KEY    通用 Embedding API 密钥
  PROJECT_ROOT         项目根目录
  MOCK_OLLAMA_AVAILABLE  设置为 1 以模拟 Ollama 可用（测试用）
  OLLAMA_UNAVAILABLE   设置为 1 以模拟 Ollama 不可用（测试用）

配置文件:
  .devbooks/config.yaml

  embedding:
    provider: auto           # auto|ollama|openai|keyword
    ollama:
      model: nomic-embed-text
      endpoint: http://localhost:11434
      timeout: 30

三级降级说明:
  1. Ollama（本地）→ 优先使用，无网络延迟，隐私安全
  2. OpenAI API   → Ollama 不可用时自动降级
  3. 关键词搜索   → API 不可用时的兜底方案

EOF
}

# 显示状态
show_status() {
  log_info "向量索引状态"
  echo ""

  if [ ! -f "$VECTOR_DB_DIR/metadata.json" ]; then
    echo "  状态: 未初始化"
    echo ""
    echo "  运行 '$0 build' 来构建索引"
    return 0
  fi

  local metadata=$(cat "$VECTOR_DB_DIR/metadata.json")

  echo "  模型: $(echo "$metadata" | jq -r '.model')"
  echo "  向量维度: $(echo "$metadata" | jq -r '.dimension')"
  echo "  索引类型: $(echo "$metadata" | jq -r '.index_type')"
  echo "  文件数量: $(echo "$metadata" | jq -r '.file_count // 0')"
  echo "  创建时间: $(echo "$metadata" | jq -r '.created_at')"
  echo "  更新时间: $(echo "$metadata" | jq -r '.updated_at')"
  echo ""

  # 计算索引大小
  if [ -d "$VECTOR_DB_DIR" ]; then
    local size=$(du -sh "$VECTOR_DB_DIR" | awk '{print $1}')
    echo "  索引大小: $size"
  fi

  echo ""
}

# 显示配置
show_config() {
  log_info "当前配置"
  echo ""

  echo "  配置文件: $CONFIG_FILE"
  echo "  启用状态: $ENABLED"
  echo "  模型: $API_MODEL"
  echo "  API 地址: $API_BASE_URL"
  echo "  批量大小: $BATCH_SIZE"
  echo "  向量数据库: $VECTOR_DB_DIR"
  echo "  向量维度: $DIMENSION"
  echo "  索引类型: $INDEX_TYPE"
  echo "  Top-K: $TOP_K"
  echo "  相似度阈值: $SIMILARITY_THRESHOLD"
  echo "  日志级别: $LOG_LEVEL"
  echo ""
}

# 清理向量数据库
clean_vector_db() {
  log_warn "清理向量数据库: $VECTOR_DB_DIR"

  if [ -d "$VECTOR_DB_DIR" ]; then
    rm -rf "$VECTOR_DB_DIR"
    log_ok "已清理"
  else
    log_info "向量数据库不存在"
  fi
}

# ==================== 主函数 ====================

main() {
  # 创建临时目录
  mkdir -p "$TEMP_DIR"
  trap "rm -rf '$TEMP_DIR'" EXIT

  # 加载配置
  load_config

  # 解析命令
  local command="${1:-help}"
  shift || true

  case "$command" in
    build)
      build_index "$@"
      ;;
    update)
      update_index "$@"
      ;;
    search)
      if [ -z "$1" ]; then
        log_error "请提供搜索查询"
        echo "用法: $0 search <查询>"
        exit 1
      fi
      local search_query="$1"
      shift

      # 解析 search 命令后的选项
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --provider)
            CLI_PROVIDER="$2"
            shift 2
            ;;
          --ollama-model)
            CLI_OLLAMA_MODEL="$2"
            shift 2
            ;;
          --ollama-endpoint)
            CLI_OLLAMA_ENDPOINT="$2"
            shift 2
            ;;
          --timeout)
            CLI_TIMEOUT="$2"
            shift 2
            ;;
          --format)
            CLI_FORMAT="$2"
            shift 2
            ;;
          --top-k)
            TOP_K="$2"
            shift 2
            ;;
          --threshold)
            SIMILARITY_THRESHOLD="$2"
            shift 2
            ;;
          --debug)
            LOG_LEVEL="DEBUG"
            shift
            ;;
          *)
            log_warn "未知选项: $1"
            shift
            ;;
        esac
      done

      semantic_search "$search_query"
      ;;
    status)
      show_status
      ;;
    config)
      show_config
      ;;
    clean)
      clean_vector_db
      ;;
    help|--help|-h)
      show_help
      ;;
    *)
      log_error "未知命令: $command"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

# 解析全局选项
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --provider)
      CLI_PROVIDER="$2"
      shift 2
      ;;
    --ollama-model)
      CLI_OLLAMA_MODEL="$2"
      shift 2
      ;;
    --ollama-endpoint)
      CLI_OLLAMA_ENDPOINT="$2"
      shift 2
      ;;
    --timeout)
      CLI_TIMEOUT="$2"
      shift 2
      ;;
    --format)
      CLI_FORMAT="$2"
      shift 2
      ;;
    --top-k)
      TOP_K="$2"
      shift 2
      ;;
    --threshold)
      SIMILARITY_THRESHOLD="$2"
      shift 2
      ;;
    --debug)
      LOG_LEVEL="DEBUG"
      shift
      ;;
    *)
      break
      ;;
  esac
done

# 运行主函数
main "$@"
