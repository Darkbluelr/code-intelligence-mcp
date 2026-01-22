#!/bin/bash
# context-compressor.sh - Context skeleton compressor for TS/JS
#
# 输出:
#   JSON，包含 compressed_context 和 metadata
#
# 依赖:
#   jq

set -euo pipefail

# C-005 fix: Use array for temporary files to handle filenames with spaces
declare -a _TEMP_FILES=()

# RM-001: trap 清理机制，确保资源正确释放
_cleanup() {
  # 清理临时文件（如果有）
  if [[ ${#_TEMP_FILES[@]} -gt 0 ]]; then
    for f in "${_TEMP_FILES[@]}"; do
      [[ -f "$f" ]] && rm -f "$f" 2>/dev/null || true
    done
  fi
  # 清理缓存锁文件（如果有）
  if [[ -n "${_CACHE_LOCK:-}" ]] && [[ -f "$_CACHE_LOCK" ]]; then
    rm -f "$_CACHE_LOCK" 2>/dev/null || true
  fi
}
trap _cleanup EXIT INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/common.sh"
if [ -f "$COMMON_LIB" ]; then
  export LOG_PREFIX="ContextCompressor"
  # shellcheck source=common.sh
  source "$COMMON_LIB"
else
  log_info()  { echo "[ContextCompressor] $1" >&2; }
  log_warn()  { echo "[ContextCompressor] $1" >&2; }
  log_error() { echo "[ContextCompressor] $1" >&2; }
fi

if declare -f check_dependencies &>/dev/null; then
  check_dependencies jq || exit 2
else
  command -v jq &>/dev/null || { log_error "缺少依赖: jq"; exit 2; }
fi

: "${DEVBOOKS_DIR:=.devbooks}"
: "${CONTEXT_COMPRESSOR_MAX_MB:=10}"

MODE="skeleton"
COMPRESS_LEVEL="medium"
BUDGET=""
HOTSPOT_DIR=""
CACHE_ENABLED=false
CACHE_DIR="${DEVBOOKS_DIR}/context-compressor-cache"
INPUT_PATHS=()

show_help() {
  cat << 'EOF'
Context Compressor (skeleton mode)

用法:
  context-compressor.sh [选项] <file|dir>...

选项:
  --mode <skeleton>           压缩模式（默认: skeleton）
  --compress <low|medium|high> 压缩级别（默认: medium）
  --budget <n>                token 预算（按非空行计）
  --hotspot <dir>             以热度优先排序目录文件
  --cache [dir]               启用缓存（可选目录）
  --enable-all-features       忽略功能开关配置，强制启用所有功能
  --help                      显示帮助
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        MODE="$2"
        shift 2
        ;;
      --compress)
        COMPRESS_LEVEL="$2"
        shift 2
        ;;
      --budget)
        BUDGET="$2"
        shift 2
        ;;
      --hotspot)
        HOTSPOT_DIR="$2"
        shift 2
        ;;
      --cache)
        CACHE_ENABLED=true
        shift
        ;;
      --enable-all-features)
        export DEVBOOKS_ENABLE_ALL_FEATURES=1
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        INPUT_PATHS+=("$1")
        shift
        ;;
    esac
  done
}

is_valid_mode() {
  case "$1" in
    skeleton) return 0 ;;
    *) return 1 ;;
  esac
}

is_valid_level() {
  case "$1" in
    low|medium|high) return 0 ;;
    *) return 1 ;;
  esac
}

count_non_empty_lines() {
  awk 'NF {c++} END {print c+0}'
}

count_compressed_tokens() {
  awk 'NF && $0 !~ /^=+/{c++} END {print c+0}'
}

is_supported_extension() {
  local file="$1"
  case "$file" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py) return 0 ;;
    *) return 1 ;;
  esac
}

file_size_mb() {
  local file="$1"
  local bytes=0
  if stat -f %z "$file" >/dev/null 2>&1; then
    bytes=$(stat -f %z "$file")
  elif stat -c %s "$file" >/dev/null 2>&1; then
    bytes=$(stat -c %s "$file")
  else
    bytes=$(wc -c < "$file" 2>/dev/null || echo 0)
  fi
  if [ "$bytes" -le 0 ]; then
    echo 0
    return
  fi
  echo $(( (bytes + 1048575) / 1048576 ))
}

validate_ts_syntax() {
  local file="$1"

  if command -v node >/dev/null 2>&1; then
    if node -e "require('typescript')" >/dev/null 2>&1; then
      node - "$file" << 'NODE'
const fs = require("fs");
const ts = require("typescript");
const file = process.argv[2];
const source = fs.readFileSync(file, "utf8");
const sourceFile = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
const diagnostics = sourceFile.parseDiagnostics || [];
if (diagnostics.length > 0) {
  console.error("syntax error");
  process.exit(1);
}
NODE
      return $?
    fi
  fi

  local content
  content=$(cat "$file" 2>/dev/null || true)
  [ -z "$content" ] && return 0

  local paren_open paren_close brace_open brace_close
  paren_open=$(echo "$content" | tr -cd '(' | wc -c | tr -d ' ')
  paren_close=$(echo "$content" | tr -cd ')' | wc -c | tr -d ' ')
  brace_open=$(echo "$content" | tr -cd '{' | wc -c | tr -d ' ')
  brace_close=$(echo "$content" | tr -cd '}' | wc -c | tr -d ' ')

  if [ "$paren_open" -ne "$paren_close" ] || [ "$brace_open" -ne "$brace_close" ]; then
    echo "syntax error" >&2
    return 1
  fi

  return 0
}

get_mtime() {
  local path="$1"
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
  elif stat -c %Y "$path" >/dev/null 2>&1; then
    stat -c %Y "$path"
  else
    echo 0
  fi
}

collect_files() {
  local path="$1"
  if [ -f "$path" ]; then
    echo "$path"
  elif [ -d "$path" ]; then
    find "$path" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.mjs" -o -name "*.cjs" -o -name "*.py" \) 2>/dev/null
  else
    log_warn "路径不存在: $path"
  fi
}

sort_by_hotspot() {
  local files=("$@")
  local with_mtime=()
  local file
  for file in "${files[@]}"; do
    with_mtime+=("$(get_mtime "$file")|$file")
  done
  printf '%s\n' "${with_mtime[@]}" | sort -rn | cut -d'|' -f2
}

brace_delta() {
  local line="$1"
  local opens closes
  opens=$(printf '%s' "$line" | tr -cd '{' | wc -c)
  closes=$(printf '%s' "$line" | tr -cd '}' | wc -c)
  echo $(( opens - closes ))
}

leading_indent() {
  local line="$1"
  echo "${line%%[^[:space:]]*}"
}

is_signature_start() {
  local line="$1"

  # 跳过注释
  [[ "$line" =~ ^[[:space:]]*// ]] && return 1
  [[ "$line" =~ ^[[:space:]]*/\* ]] && return 1
  [[ "$line" =~ ^[[:space:]]*\* ]] && return 1
  [[ "$line" =~ ^[[:space:]]*# ]] && return 1

  # 跳过控制流语句
  [[ "$line" =~ ^[[:space:]]*(if|for|while|switch|catch|case|else|return)[[:space:]\(] ]] && return 1
  # 跳过结构定义（这些由 is_structural_line 处理）
  [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(interface|type|class|enum)[[:space:]] ]] && return 1

  # TypeScript/JavaScript 函数
  [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+[A-Za-z_][A-Za-z0-9_]* ]] && return 0
  # 箭头函数和变量声明
  [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*= ]] && return 0
  # 带修饰符的类方法（支持多个修饰符如 private async）
  [[ "$line" =~ ^[[:space:]]*(public|private|protected|static|async)([[:space:]]+(public|private|protected|static|async))*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\( ]] && return 0
  # 构造函数
  [[ "$line" =~ ^[[:space:]]*constructor[[:space:]]*\( ]] && return 0
  # 不带修饰符的类方法（如 methodName(params): Type）
  # 必须是缩进的（在类内），且有返回类型注解或直接跟 {
  if [[ "$line" =~ ^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\( ]]; then
    [[ "$line" =~ \)[[:space:]]*:[[:space:]] ]] && return 0
    [[ "$line" =~ \)[[:space:]]*\{ ]] && return 0
  fi

  # Python: def/async def
  [[ "$line" =~ ^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+[A-Za-z_][A-Za-z0-9_]* ]] && return 0

  return 1
}

is_structural_line() {
  local line="$1"

  # TypeScript/JavaScript
  [[ "$line" =~ ^[[:space:]]*import[[:space:]] ]] && return 0
  [[ "$line" =~ ^[[:space:]]*export[[:space:]]+\{ ]] && return 0
  [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(class|interface|type|enum)[[:space:]] ]] && return 0

  # Python
  [[ "$line" =~ ^from[[:space:]] ]] && return 0
  [[ "$line" =~ ^[[:space:]]*@[A-Za-z_] ]] && return 0  # 装饰器
  [[ "$line" =~ ^class[[:space:]]+[A-Za-z_] ]] && return 0

  return 1
}

compress_file() {
  local file="$1"
  local level="$2"
  local keep_body_lines=2

  case "$level" in
    low) keep_body_lines=5 ;;
    medium) keep_body_lines=2 ;;
    high) keep_body_lines=0 ;;
  esac

  # 检测文件类型
  local is_python=false
  case "$file" in
    *.py) is_python=true ;;
  esac

  local in_signature=false
  local in_body=false
  local skip_depth=0
  local body_kept=0
  local body_indent=0  # Python: 函数体的缩进级别
  local signature_lines=()
  local output_lines=()
  local decorator_lines=()

  while IFS= read -r line || [ -n "$line" ]; do
    # 获取当前行缩进
    local line_indent=${#line}
    local trimmed="${line#"${line%%[![:space:]]*}"}"
    line_indent=$((line_indent - ${#trimmed}))

    if [ "$in_signature" = true ]; then
      signature_lines+=("$line")
      # 签名结束条件：{ 或 ; (TS/JS) 或 : (Python def)
      local sig_complete=false
      if [ "$is_python" = true ]; then
        [[ "$line" =~ :$ ]] && sig_complete=true
      else
        [[ "$line" == *"{"* || "$line" == *";"* ]] && sig_complete=true
      fi
      if [ "$sig_complete" = true ]; then
        if [ "${#decorator_lines[@]}" -gt 0 ]; then
          output_lines+=("${decorator_lines[@]}")
          decorator_lines=()
        fi
        output_lines+=("${signature_lines[@]}")
        signature_lines=()
        in_signature=false

        # 进入函数体
        if [ "$is_python" = true ]; then
          if [[ "$line" =~ :$ ]]; then
            in_body=true
            body_indent=$line_indent
            body_kept=0
            if [ "$keep_body_lines" -eq 0 ]; then
              output_lines+=("$(leading_indent "$line")# body omitted")
            fi
          fi
        else
          if [[ "$line" == *"{"* ]]; then
            in_body=true
            skip_depth=$(brace_delta "$line")
            body_kept=0
            if [ "$keep_body_lines" -eq 0 ]; then
              output_lines+=("$(leading_indent "$line")// body omitted")
            fi
            if [ "$skip_depth" -le 0 ]; then
              in_body=false
            fi
          fi
        fi
      fi
      continue
    fi

    if [ "$in_body" = true ]; then
      local output_line=false
      if [ "$keep_body_lines" -gt 0 ] && [ "$body_kept" -lt "$keep_body_lines" ]; then
        output_line=true
        if [[ -n "$line" ]]; then
          body_kept=$((body_kept + 1))
        fi
      fi

      # 检测函数体结束
      if [ "$is_python" = true ]; then
        # Python: 缩进回到或低于函数定义级别时结束
        if [ -n "$trimmed" ] && [ "$line_indent" -le "$body_indent" ]; then
          in_body=false
          # 不输出这一行，让它进入下一轮迭代处理
          # 但需要继续处理而不是 continue
        else
          if [ "$output_line" = true ]; then
            output_lines+=("$line")
          fi
          continue
        fi
      else
        local delta
        delta=$(brace_delta "$line")
        skip_depth=$((skip_depth + delta))

        if [ "$skip_depth" -le 0 ]; then
          in_body=false
          if [[ "$line" == *"}"* ]]; then
            output_line=true
          fi
        fi

        if [ "$output_line" = true ]; then
          output_lines+=("$line")
        fi
        continue
      fi
    fi

    if [[ "$line" =~ ^[[:space:]]*@ ]]; then
      decorator_lines+=("$line")
      continue
    fi

    if is_signature_start "$line"; then
      in_signature=true
      signature_lines=("$line")
      # 单行签名检测
      local sig_complete=false
      if [ "$is_python" = true ]; then
        [[ "$line" =~ :$ ]] && sig_complete=true
      else
        [[ "$line" == *"{"* || "$line" == *";"* ]] && sig_complete=true
      fi
      if [ "$sig_complete" = true ]; then
        if [ "${#decorator_lines[@]}" -gt 0 ]; then
          output_lines+=("${decorator_lines[@]}")
          decorator_lines=()
        fi
        output_lines+=("${signature_lines[@]}")
        signature_lines=()
        in_signature=false

        if [ "$is_python" = true ]; then
          if [[ "$line" =~ :$ ]]; then
            in_body=true
            body_indent=$line_indent
            body_kept=0
            if [ "$keep_body_lines" -eq 0 ]; then
              output_lines+=("$(leading_indent "$line")# body omitted")
            fi
          fi
        else
          if [[ "$line" == *"{"* ]]; then
            in_body=true
            skip_depth=$(brace_delta "$line")
            body_kept=0
            if [ "$keep_body_lines" -eq 0 ]; then
              output_lines+=("$(leading_indent "$line")// body omitted")
            fi
            if [ "$skip_depth" -le 0 ]; then
              in_body=false
            fi
          fi
        fi
      fi
      continue
    fi

    if is_structural_line "$line"; then
      if [ "${#decorator_lines[@]}" -gt 0 ]; then
        output_lines+=("${decorator_lines[@]}")
        decorator_lines=()
      fi
      output_lines+=("$line")
      # 对于 interface/type/enum，收集完整定义体
      # 对于 class，只输出声明行，内部方法由后续迭代处理
      if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(interface|type|enum)[[:space:]] ]]; then
        if [[ "$line" == *"{"* ]]; then
          local struct_depth
          struct_depth=$(brace_delta "$line")
          if [ "$struct_depth" -gt 0 ]; then
            while IFS= read -r inner_line || [ -n "$inner_line" ]; do
              output_lines+=("$inner_line")
              local inner_delta
              inner_delta=$(brace_delta "$inner_line")
              struct_depth=$((struct_depth + inner_delta))
              if [ "$struct_depth" -le 0 ]; then
                break
              fi
            done
          fi
        elif [[ "$line" == *"="* && ! "$line" == *";"* ]]; then
          # 多行 type 定义
          while IFS= read -r inner_line || [ -n "$inner_line" ]; do
            output_lines+=("$inner_line")
            if [[ "$inner_line" == *";"* ]]; then
              break
            fi
          done
        fi
      fi
      # class 声明不收集 body，让内部方法被后续迭代检测
      continue
    fi
  done < "$file"

  if [ "$in_signature" = true ] && [ "${#signature_lines[@]}" -gt 0 ]; then
    if [ "${#decorator_lines[@]}" -gt 0 ]; then
      output_lines+=("${decorator_lines[@]}")
      decorator_lines=()
    fi
    output_lines+=("${signature_lines[@]}")
  elif [ "${#decorator_lines[@]}" -gt 0 ]; then
    output_lines+=("${decorator_lines[@]}")
  fi

  printf '%s\n' "${output_lines[@]}"
}

extract_signature_name() {
  local line="$1"
  local name=""

  # 提取 function 名称
  name=$(echo "$line" | sed -nE 's/.*function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[^A-Za-z0-9_].*/\1/p')
  if [ -z "$name" ]; then
    # 提取方法名称 (async/public/private/protected/static 修饰符)
    name=$(echo "$line" | sed -nE 's/.*(async|public|private|protected|static)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(.*/\2/p')
  fi
  if [ -z "$name" ] && echo "$line" | grep -q 'constructor[[:space:]]*('; then
    name="constructor"
  fi

  echo "$name"
}

collect_signatures() {
  local file="$1"
  local signatures='[]'
  local in_signature=false
  local signature_lines=()
  local current_name=""

  local input_file="$file"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_signature" = true ]; then
      signature_lines+=("$line")
      if [[ "$line" == *"{"* || "$line" == *";"* ]]; then
        local signature_text
        signature_text=$(printf '%s\n' "${signature_lines[@]}")
        if [ -n "$current_name" ]; then
          signatures=$(echo "$signatures" | jq \
            --arg name "$current_name" \
            --arg signature "$signature_text" \
            --arg file "$input_file" \
            '. + [{name: $name, signature: $signature, file: $file}]')
        fi
        signature_lines=()
        current_name=""
        in_signature=false
      fi
      continue
    fi

    if is_signature_start "$line"; then
      current_name=$(extract_signature_name "$line")
      signature_lines=("$line")
      in_signature=true
      if [[ "$line" == *"{"* || "$line" == *";"* ]]; then
        local signature_text
        signature_text=$(printf '%s\n' "${signature_lines[@]}")
        if [ -n "$current_name" ]; then
          signatures=$(echo "$signatures" | jq \
            --arg name "$current_name" \
            --arg signature "$signature_text" \
            --arg file "$input_file" \
            '. + [{name: $name, signature: $signature, file: $file}]')
        fi
        signature_lines=()
        current_name=""
        in_signature=false
      fi
    fi
  done < "$input_file"

  echo "$signatures"
}

load_from_cache() {
  local key="$1"
  local cache_file="${CACHE_DIR}/${key}.json"
  if [ -f "$cache_file" ]; then
    cat "$cache_file"
    return 0
  fi
  return 1
}

save_to_cache() {
  local key="$1"
  local content="$2"
  mkdir -p "$CACHE_DIR"
  printf '%s' "$content" > "${CACHE_DIR}/${key}.json"
}

# R-002: 拆分辅助函数 - 验证输入并收集文件列表
# 输出: 填充 _MAIN_FILES 数组
_main_validate_and_collect_files() {
  if declare -f is_feature_enabled &>/dev/null; then
    if ! is_feature_enabled "context_compressor"; then
      log_warn "上下文压缩功能已禁用 (features.context_compressor: false)"
      echo '{"compressed_context":"","metadata":{"status":"disabled"}}'
      exit 0
    fi
  fi

  if [ "${#INPUT_PATHS[@]}" -eq 0 ] && [ -n "$HOTSPOT_DIR" ]; then
    INPUT_PATHS+=("$HOTSPOT_DIR")
  fi

  if [ "${#INPUT_PATHS[@]}" -eq 0 ]; then
    log_error "缺少输入文件或目录"
    show_help
    exit 1
  fi

  if ! is_valid_mode "$MODE"; then
    log_error "无效模式: $MODE"
    exit 1
  fi

  if ! is_valid_level "$COMPRESS_LEVEL"; then
    log_error "无效压缩级别: $COMPRESS_LEVEL"
    exit 1
  fi

  _MAIN_FILES=()
  local input
  for input in "${INPUT_PATHS[@]}"; do
    while IFS= read -r f; do
      [ -n "$f" ] && _MAIN_FILES+=("$f")
    done < <(collect_files "$input")
  done

  if [ "${#_MAIN_FILES[@]}" -eq 0 ]; then
    log_error "未找到可压缩文件"
    exit 1
  fi

  if [ -n "$HOTSPOT_DIR" ]; then
    local sorted=()
    while IFS= read -r f; do
      [ -n "$f" ] && sorted+=("$f")
    done < <(sort_by_hotspot "${_MAIN_FILES[@]}")
    _MAIN_FILES=("${sorted[@]}")
  fi
}

# R-002: 拆分辅助函数 - 处理单个文件并返回结果
# 参数: $1=文件路径
# 输出: JSON 对象 {compressed_file, original_count, file_tokens, file_sigs}
_main_process_single_file() {
  local input="$1"

  if ! is_supported_extension "$input"; then
    log_error "unsupported language: $input"
    exit 1
  fi

  local size_mb
  size_mb=$(file_size_mb "$input")
  if [ "$size_mb" -gt "$CONTEXT_COMPRESSOR_MAX_MB" ]; then
    log_error "file too large: ${input} (${size_mb}MB, max ${CONTEXT_COMPRESSOR_MAX_MB}MB)"
    exit 1
  fi

  local content
  content=$(cat "$input")
  local original_count
  original_count=$(printf '%s\n' "$content" | count_non_empty_lines)
  if [ "$original_count" -eq 0 ]; then
    log_error "empty file: $input"
    exit 1
  fi
  if [[ "$input" == *.ts || "$input" == *.tsx ]]; then
    if ! validate_ts_syntax "$input"; then
      log_error "syntax error in $input"
      exit 1
    fi
  fi

  local key_count
  key_count=$(printf '%s\n' "$content" | grep -cE '^[[:space:]]*(@|export|import|class|interface|type|enum|function|async|public|private|protected|constructor)\b' || true)

  local cache_key=""
  local compressed_file=""
  local cache_hit=false
  if [ "$CACHE_ENABLED" = true ] && declare -f hash_string_md5 &>/dev/null; then
    local mtime
    mtime=$(get_mtime "$input")
    cache_key=$(hash_string_md5 "${input}:${mtime}:${MODE}:${COMPRESS_LEVEL}")
    if compressed_file=$(load_from_cache "$cache_key"); then
      cache_hit=true
    else
      compressed_file=$(compress_file "$input" "$COMPRESS_LEVEL")
      save_to_cache "$cache_key" "$compressed_file"
    fi
  else
    compressed_file=$(compress_file "$input" "$COMPRESS_LEVEL")
  fi

  local file_tokens
  file_tokens=$(printf '%s\n' "$compressed_file" | count_non_empty_lines)

  local file_sigs
  file_sigs=$(collect_signatures "$input")

  # 输出结果到全局变量
  _PSF_COMPRESSED_FILE="$compressed_file"
  _PSF_ORIGINAL_COUNT="$original_count"
  _PSF_FILE_TOKENS="$file_tokens"
  _PSF_FILE_SIGS="$file_sigs"
  _PSF_KEY_COUNT="$key_count"
  _PSF_CACHE_HIT="$cache_hit"
}

# M-013 fix: 重构 _main_build_output_json 函数，使用全局变量减少参数数量
# 全局变量:
#   _OUTPUT_COMPRESSED_CONTEXT, _OUTPUT_FILES_JSON, _OUTPUT_SIGNATURES_JSON
#   _OUTPUT_ORIGINAL_TOKENS, _OUTPUT_COMPRESSED_TOKENS, _OUTPUT_CACHE_HITS
#   _OUTPUT_FILE_COUNT, _OUTPUT_TRUNCATED, _OUTPUT_ORIGINAL_KEY_LINES
_main_build_output_json() {
  local compressed_key_lines=0
  if [ -n "$_OUTPUT_COMPRESSED_CONTEXT" ]; then
    compressed_key_lines=$(echo "$_OUTPUT_COMPRESSED_CONTEXT" | grep -cE '^[[:space:]]*(@|export|import|class|interface|type|enum|function|async|public|private|protected|constructor)\b' || true)
  fi

  local compression_ratio="0"
  if [ "$_OUTPUT_ORIGINAL_TOKENS" -gt 0 ]; then
    if declare -f float_calc &>/dev/null; then
      compression_ratio=$(float_calc "${_OUTPUT_COMPRESSED_TOKENS} / ${_OUTPUT_ORIGINAL_TOKENS}" 2)
    else
      compression_ratio=$(awk -v c="$_OUTPUT_COMPRESSED_TOKENS" -v o="$_OUTPUT_ORIGINAL_TOKENS" 'BEGIN {printf "%.2f", (o>0?c/o:0)}')
    fi
  fi

  local retention_rate="1.00"
  if [ "$_OUTPUT_ORIGINAL_KEY_LINES" -gt 0 ]; then
    if declare -f float_calc &>/dev/null; then
      retention_rate=$(float_calc "${compressed_key_lines} / ${_OUTPUT_ORIGINAL_KEY_LINES}" 2)
    else
      retention_rate=$(awk -v c="$compressed_key_lines" -v o="$_OUTPUT_ORIGINAL_KEY_LINES" 'BEGIN {printf "%.2f", (o>0?c/o:0)}')
    fi
  fi

  # M-013 fix: 使用临时文件避免参数过长
  local temp_context_file
  temp_context_file=$(mktemp)
  _TEMP_FILES+=("$temp_context_file")
  echo "$_OUTPUT_COMPRESSED_CONTEXT" > "$temp_context_file"

  jq -n \
    --rawfile compressed_context "$temp_context_file" \
    --arg mode "$MODE" \
    --arg level "$COMPRESS_LEVEL" \
    --argjson files "$_OUTPUT_FILES_JSON" \
    --argjson preserved_signatures "$_OUTPUT_SIGNATURES_JSON" \
    --argjson original_tokens "$_OUTPUT_ORIGINAL_TOKENS" \
    --argjson compressed_tokens "$_OUTPUT_COMPRESSED_TOKENS" \
    --argjson cache_hits "$_OUTPUT_CACHE_HITS" \
    --argjson file_count "$_OUTPUT_FILE_COUNT" \
    --argjson truncated "$_OUTPUT_TRUNCATED" \
    --argjson budget "${BUDGET:-0}" \
    --argjson compression_ratio "$compression_ratio" \
    --argjson retention_rate "$retention_rate" \
    '{
      compressed_context: $compressed_context,
      files: $files,
      preserved_signatures: $preserved_signatures,
      metadata: {
        mode: $mode,
        compression_level: $level,
        original_tokens: $original_tokens,
        compressed_tokens: $compressed_tokens,
        compression_ratio: $compression_ratio,
        information_retention: $retention_rate,
        cache_hits: $cache_hits,
        file_count: $file_count,
        budget: (if $budget == 0 then null else $budget end),
        truncated: $truncated
      }
    }'
}

main() {
  parse_args "$@"

  # R-002: 使用辅助函数验证输入并收集文件
  _main_validate_and_collect_files

  local compressed_context=""
  local original_tokens=0
  local compressed_tokens=0
  local cache_hits=0
  local file_count=0
  local truncated=false
  local original_key_lines=0
  local files_json='[]'
  local signatures_json='[]'

  for input in "${_MAIN_FILES[@]}"; do
    file_count=$((file_count + 1))

    # R-002: 使用辅助函数处理单个文件
    _main_process_single_file "$input"

    local compressed_file="$_PSF_COMPRESSED_FILE"
    local original_count="$_PSF_ORIGINAL_COUNT"
    local file_tokens="$_PSF_FILE_TOKENS"
    local file_sigs="$_PSF_FILE_SIGS"
    local key_count="$_PSF_KEY_COUNT"

    original_tokens=$((original_tokens + original_count))
    original_key_lines=$((original_key_lines + key_count))
    if [ "$_PSF_CACHE_HIT" = true ]; then
      cache_hits=$((cache_hits + 1))
    fi

    local header="========== ${input} =========="
    local file_block="${header}"$'\n'"${compressed_file}"
    if [ -z "$compressed_context" ]; then
      compressed_context="$file_block"
    else
      compressed_context="${compressed_context}"$'\n'"${file_block}"
    fi

    compressed_tokens=$((compressed_tokens + file_tokens))

    local file_ratio="0"
    if [ "$original_count" -gt 0 ]; then
      if declare -f float_calc &>/dev/null; then
        file_ratio=$(float_calc "${file_tokens} / ${original_count}" 2)
      else
        file_ratio=$(awk -v c="$file_tokens" -v o="$original_count" 'BEGIN {printf "%.2f", (o>0?c/o:0)}')
      fi
    fi

    if [ -n "$file_sigs" ] && [ "$file_sigs" != "[]" ]; then
      signatures_json=$(echo "$signatures_json" | jq --argjson sigs "$file_sigs" '. + $sigs')
    fi

    files_json=$(echo "$files_json" | jq \
      --arg path "$input" \
      --argjson original_tokens "$original_count" \
      --argjson compressed_tokens "$file_tokens" \
      --argjson compression_ratio "$file_ratio" \
      '. + [{path: $path, original_tokens: $original_tokens, compressed_tokens: $compressed_tokens, compression_ratio: $compression_ratio}]')

    if [ -n "${BUDGET:-}" ] && [[ "$BUDGET" =~ ^[0-9]+$ ]] && [ "$compressed_tokens" -gt "$BUDGET" ]; then
      truncated=true
      break
    fi
  done

  if [ -n "${BUDGET:-}" ] && [[ "$BUDGET" =~ ^[0-9]+$ ]] && [ "$compressed_tokens" -gt "$BUDGET" ]; then
    truncated=true
    compressed_context=$(printf '%s\n' "$compressed_context" | awk -v limit="$BUDGET" 'NF {count++} count<=limit {print} END {if (count>limit) exit 0}')
    compressed_tokens=$(printf '%s\n' "$compressed_context" | count_compressed_tokens)
  fi

  # M-013 fix: 使用全局变量传递参数
  _OUTPUT_COMPRESSED_CONTEXT="$compressed_context"
  _OUTPUT_FILES_JSON="$files_json"
  _OUTPUT_SIGNATURES_JSON="$signatures_json"
  _OUTPUT_ORIGINAL_TOKENS="$original_tokens"
  _OUTPUT_COMPRESSED_TOKENS="$compressed_tokens"
  _OUTPUT_CACHE_HITS="$cache_hits"
  _OUTPUT_FILE_COUNT="$file_count"
  _OUTPUT_TRUNCATED="$truncated"
  _OUTPUT_ORIGINAL_KEY_LINES="$original_key_lines"

  _main_build_output_json
}

main "$@"
