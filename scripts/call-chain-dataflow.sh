#!/bin/bash
# DevBooks Call-Chain Tracer - Data Flow Module
# 完整数据流追踪：污点传播、正向/反向追踪、格式化输出

# ==================== M3: 完整数据流追踪 (AC-004) ====================
# 实现: T3.2-T3.6

# ==================== R-006: DATA_FLOW 状态模块 ====================
# 以下全局变量用于数据流追踪，通过 getter/setter 函数访问
# P1-FIX: 使用 _reset_data_flow_state() 在入口点统一重置，避免跨调用状态泄漏

# --- 内部状态变量（应通过函数访问） ---
TAINTED_SYMBOLS='[]'
DATA_FLOW_PATHS='[]'
DATA_FLOW_VISITED='[]'
DATA_FLOW_CYCLE_DETECTED=false
DATA_FLOW_CYCLE_PATH=""
DATA_FLOW_CACHE='{}'
DATA_FLOW_START_TIME=0
DATA_FLOW_TRUNCATED=false
DATA_FLOW_PATH_NODES_JSON=""
DATA_FLOW_TAINTED_JSON="[]"
DATA_FLOW_TAINTED_COUNT=0
DATA_FLOW_NODE_COUNT=0
DATA_FLOW_SYMBOL_INDEX_READY=false
DATA_FLOW_SYMBOL_INDEX='{}'

# R-006: Getter 函数 - 获取循环检测状态
_df_get_cycle_detected() {
  echo "$DATA_FLOW_CYCLE_DETECTED"
}

# R-006: Setter 函数 - 设置循环检测状态
_df_set_cycle_detected() {
  DATA_FLOW_CYCLE_DETECTED="$1"
  DATA_FLOW_CYCLE_PATH="${2:-}"
}

# R-006: Getter 函数 - 获取截断状态
_df_get_truncated() {
  echo "$DATA_FLOW_TRUNCATED"
}

# R-006: Setter 函数 - 设置结果状态
_df_set_result() {
  DATA_FLOW_TRUNCATED="$1"
  DATA_FLOW_PATH_NODES_JSON="$2"
  DATA_FLOW_NODE_COUNT="$3"
  DATA_FLOW_TAINTED_JSON="$4"
  DATA_FLOW_TAINTED_COUNT="$5"
}

# R-006: Getter 函数 - 获取结果 JSON
_df_get_path_nodes_json() {
  echo "$DATA_FLOW_PATH_NODES_JSON"
}

# R-006: Getter 函数 - 获取污染符号 JSON
_df_get_tainted_json() {
  echo "$DATA_FLOW_TAINTED_JSON"
}

# R-006: Getter 函数 - 获取污染符号数量
_df_get_tainted_count() {
  echo "$DATA_FLOW_TAINTED_COUNT"
}

# R-006: 符号索引相关函数
_df_is_symbol_index_ready() {
  [ "$DATA_FLOW_SYMBOL_INDEX_READY" = true ]
}

_df_set_symbol_index_ready() {
  DATA_FLOW_SYMBOL_INDEX_READY=true
}

_df_get_symbol_from_index() {
  local symbol="$1"
  echo "$DATA_FLOW_SYMBOL_INDEX" | jq -r --arg s "$symbol" '.[$s] // empty'
}

_df_add_symbol_to_index() {
  local name="$1"
  local file="$2"
  local line="$3"
  DATA_FLOW_SYMBOL_INDEX=$(echo "$DATA_FLOW_SYMBOL_INDEX" | jq --arg k "$name" --arg v "${file}|${line}" '. + {($k): $v}')
}

# P1-FIX: 统一状态重置函数，防止全局状态污染
# 必须在所有数据流追踪入口点调用
_reset_data_flow_state() {
  TAINTED_SYMBOLS='[]'
  DATA_FLOW_PATHS='[]'
  DATA_FLOW_VISITED='[]'
  DATA_FLOW_CYCLE_DETECTED=false
  DATA_FLOW_CYCLE_PATH=""
  DATA_FLOW_CACHE='{}'
  DATA_FLOW_START_TIME=0
  DATA_FLOW_TRUNCATED=false
  DATA_FLOW_PATH_NODES_JSON=""
  DATA_FLOW_TAINTED_JSON="[]"
  DATA_FLOW_TAINTED_COUNT=0
  DATA_FLOW_NODE_COUNT=0
  DATA_FLOW_SYMBOL_INDEX_READY=false
  DATA_FLOW_SYMBOL_INDEX='{}'
}

# ==================== END DATA_FLOW 状态模块 ====================

is_supported_data_flow_file() {
  local file="$1"
  case "$file" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_data_flow_file() {
  if [ -z "$DATA_FLOW_FILE" ]; then
    return 0
  fi

  local resolved="$DATA_FLOW_FILE"
  if [[ "$resolved" != /* ]]; then
    resolved="${CWD}/${resolved}"
  fi

  if [ ! -f "$resolved" ]; then
    log_error "文件不存在: $DATA_FLOW_FILE"
    exit 1
  fi

  if ! is_supported_data_flow_file "$resolved"; then
    log_error "仅支持 TypeScript/JavaScript 文件进行数据流追踪"
    exit 1
  fi

  DATA_FLOW_FILE="$resolved"
  CWD="$(cd "$(dirname "$resolved")" && pwd)"
  PROJECT_ROOT="$CWD"
}

normalize_path() {
  local base="$1"
  local rel="$2"

  if command -v python3 &>/dev/null; then
    python3 - "$base" "$rel" << 'PY'
import os
import sys
print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))
PY
    return
  fi

  if command -v node &>/dev/null; then
    node -e 'const path=require("path"); console.log(path.resolve(process.argv[1], process.argv[2]));' "$base" "$rel"
    return
  fi

  local dir
  dir=$(cd "$base" 2>/dev/null && cd "$(dirname "$rel")" 2>/dev/null && pwd)
  echo "${dir}/$(basename "$rel")"
}

resolve_import_target() {
  local base_dir="$1"
  local import_path="$2"

  local resolved
  resolved=$(normalize_path "$base_dir" "$import_path")

  local candidates=(
    "$resolved"
    "${resolved}.ts"
    "${resolved}.tsx"
    "${resolved}.js"
    "${resolved}.jsx"
    "${resolved}.mjs"
    "${resolved}.cjs"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done

  if [ -d "$resolved" ]; then
    local index_candidate
    for index_candidate in \
      "${resolved}/index.ts" \
      "${resolved}/index.tsx" \
      "${resolved}/index.js" \
      "${resolved}/index.jsx" \
      "${resolved}/index.mjs" \
      "${resolved}/index.cjs"; do
      if [ -f "$index_candidate" ]; then
        echo "$index_candidate"
        return
      fi
    done
  fi

  echo "$resolved"
}

collect_import_map() {
  local file="$1"
  local map=""
  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done
  [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

  local lines
  if [ -n "$rg_cmd" ]; then
    lines=$("$rg_cmd" -n "^import " "$file" 2>/dev/null || true)
  else
    lines=$(grep -nE "^import " "$file" 2>/dev/null || true)
  fi

  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue

    local import_path
    import_path=$(printf '%s\n' "$line" | sed -E "s/.*from[[:space:]]+['\\\"]([^'\\\"]+)['\\\"].*/\\1/")
    if [ "$import_path" = "$line" ]; then
      import_path=""
    fi

    if [[ "$line" =~ ^import[[:space:]]+\\*[[:space:]]+as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      map+="${BASH_REMATCH[1]}|${import_path}"$'\n'
      continue
    fi

    if [[ "$line" =~ ^import[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+from[[:space:]]+ ]]; then
      map+="${BASH_REMATCH[1]}|${import_path}"$'\n'
      continue
    fi

    local symbols
    symbols=$(echo "$line" | sed -E 's/.*[{]([^}]*)[}].*/\1/')
    if [ "$symbols" != "$line" ]; then
      IFS=',' read -r -a items <<< "$symbols"
      local item
      for item in "${items[@]}"; do
        item=$(echo "$item" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        if [[ "$item" == *" as "* ]]; then
          item=$(echo "$item" | awk '{print $3}')
        fi
        [ -n "$item" ] && map+="${item}|${import_path}"$'\n'
      done
    fi
  done <<< "$lines"

  printf '%s' "$map"
}

lookup_import_path() {
  local map="$1"
  local symbol="$2"
  echo "$map" | awk -F'|' -v sym="$symbol" '$1==sym {print $2; exit}'
}

extract_function_calls() {
  local file="$1"
  local symbol="$2"
  local start_line=""

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done
  [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

  if [ -n "$rg_cmd" ]; then
    start_line=$("$rg_cmd" -n "function[[:space:]]+${symbol}\\b" "$file" 2>/dev/null | head -1 | cut -d: -f1)
  else
    start_line=$(grep -nE "function[[:space:]]+${symbol}\\b" "$file" 2>/dev/null | head -1 | cut -d: -f1)
  fi

  if [ -z "$start_line" ]; then
    return 0
  fi

  local body
  body=$(awk -v start="$start_line" '
    NR < start { next }
    {
      line = $0
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "{") depth++
        else if (c == "}") depth--
      }
      if (NR == start) started = 1
      if (started) print line
      if (started && depth == 0 && NR > start) exit
    }' "$file")

  body=$(echo "$body" | sed -E "/function[[:space:]]+${symbol}[[:space:]]*\\(/d")

  echo "$body" | \
    grep -oE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[(]' | \
    sed -E 's/[[:space:]]*[(]//g' | \
    grep -vE '^(if|for|while|switch|return|catch|function)$' | \
    sort -u
}

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

build_json_array() {
  local out="["
  local first=true
  local item
  for item in "$@"; do
    if [ "$first" = true ]; then
      first=false
    else
      out+=","
    fi
    out+="$item"
  done
  out+="]"
  printf '%s' "$out"
}

build_string_array() {
  local out="["
  local first=true
  local item
  for item in "$@"; do
    local escaped
    escaped=$(json_escape "$item")
    if [ "$first" = true ]; then
      first=false
    else
      out+=","
    fi
    out+="\"$escaped\""
  done
  out+="]"
  printf '%s' "$out"
}

find_symbol_definition_fast() {
  local symbol="$1"
  local cached_value=""
  if [ "$DATA_FLOW_SYMBOL_INDEX_READY" = true ]; then
    cached_value=$(echo "$DATA_FLOW_SYMBOL_INDEX" | jq -r --arg s "$symbol" '.[$s] // empty')
    if [ -n "$cached_value" ]; then
      echo "$cached_value"
      return 0
    fi
  fi

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done
  [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

  if [ -n "$rg_cmd" ]; then
    local result
    result=$("$rg_cmd" -n --max-count=1 \
      -g '*.ts' -g '*.tsx' -g '*.js' -g '*.jsx' -g '*.mjs' -g '*.cjs' \
      "function[[:space:]]+${symbol}\\b" "$CWD" 2>/dev/null || true)
    if [ -n "$result" ]; then
      local file="${result%%:*}"
      local rest="${result#*:}"
      local line="${rest%%:*}"
      file="${file#"$CWD"/}"
      echo "${file}|${line}"
      return 0
    fi
  fi

  local files=()
  local f
  for f in "$CWD"/*.ts "$CWD"/*.tsx "$CWD"/*.js "$CWD"/*.jsx "$CWD"/*.mjs "$CWD"/*.cjs; do
    [ -f "$f" ] && files+=("$f")
  done

  [ "${#files[@]}" -eq 0 ] && return 1

  local result
  result=$(awk -v sym="$symbol" '
    $0 ~ "function[[:space:]]+" sym "[[:space:]]*\\(" {
      print FILENAME "|" NR
      exit
    }' "${files[@]}" 2>/dev/null)
  [ -z "$result" ] && return 1

  local file="${result%%|*}"
  local line="${result#*|}"
  file="${file#"$CWD"/}"
  echo "${file}|${line}"
}

build_symbol_index() {
  if [ "$DATA_FLOW_SYMBOL_INDEX_READY" = true ]; then
    return 0
  fi

  DATA_FLOW_SYMBOL_INDEX_READY=true
  DATA_FLOW_SYMBOL_INDEX='{}'

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done
  [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

  [ -z "$rg_cmd" ] && return 0

  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local file rest line_num text name
    file="${line%%:*}"
    rest="${line#*:}"
    line_num="${rest%%:*}"
    text="${rest#*:}"
    name=$(echo "$text" | sed -nE 's/.*function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[^A-Za-z0-9_].*/\1/p')
    [ -z "$name" ] && continue
    # Check if key already exists in JSON
    local existing
    existing=$(echo "$DATA_FLOW_SYMBOL_INDEX" | jq -r --arg s "$name" '.[$s] // empty')
    if [ -z "$existing" ]; then
      file="${file#"$CWD"/}"
      DATA_FLOW_SYMBOL_INDEX=$(echo "$DATA_FLOW_SYMBOL_INDEX" | jq --arg k "$name" --arg v "${file}|${line_num}" '. + {($k): $v}')
    fi
  done < <("$rg_cmd" -n --pcre2 \
    -g '*.ts' -g '*.tsx' -g '*.js' -g '*.jsx' -g '*.mjs' -g '*.cjs' \
    'function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$CWD" 2>/dev/null || true)
}

symbol_exists() {
  local symbol="$1"

  if find_symbol_definition_fast "$symbol" >/dev/null 2>&1; then
    return 0
  fi

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done
  [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

  if [ -n "$rg_cmd" ]; then
    "$rg_cmd" -n --max-count=1 \
      -g '*.ts' -g '*.tsx' -g '*.js' -g '*.jsx' -g '*.mjs' -g '*.cjs' \
      "${symbol}\\b" "$CWD" >/dev/null 2>&1
    return $?
  fi

  grep -R -n -m 1 -E "${symbol}\\b" "$CWD" >/dev/null 2>&1
}

get_next_call_in_file() {
  local file="$1"
  local symbol="$2"

  awk -v sym="$symbol" '
    function record_call(name) {
      if (name ~ /^(if|for|while|switch|return|catch|function)$/) return
      last = name
    }
    BEGIN { in_func = 0; depth = 0; last = ""; started = 0; }
    {
      if (!in_func && $0 ~ "function[[:space:]]+" sym "[[:space:]]*\\(") {
        in_func = 1
        started = 0
      }
      if (in_func) {
        line = $0
        for (i = 1; i <= length(line); i++) {
          c = substr(line, i, 1)
          if (c == "{") depth++
          else if (c == "}") depth--
        }
        if (started == 1) {
          while (match(line, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/)) {
            name = substr(line, RSTART, RLENGTH)
            sub(/[[:space:]]*\($/, "", name)
            record_call(name)
            line = substr(line, RSTART + RLENGTH)
          }
        } else {
          started = 1
        }
        if (depth == 0) { in_func = 0; exit }
      }
    }
    END { if (last != "") print last }
  ' "$file"
}

# Select next call for data-flow tracing.
# Prefer imported calls to ensure cross-file traversal.
select_preferred_call() {
  local full_path="$1"
  local symbol="$2"

  local calls
  calls=$(extract_function_calls "$full_path" "$symbol" || true)
  [ -z "$calls" ] && return 1

  local import_map
  import_map=$(collect_import_map "$full_path")

  local first_local=""
  local call
  while IFS= read -r call; do
    [ -z "$call" ] && continue
    [ -z "$first_local" ] && first_local="$call"

    local import_path
    import_path=$(lookup_import_path "$import_map" "$call")
    if [ -n "$import_path" ]; then
      echo "${call}|${import_path}"
      return 0
    fi
  done <<< "$calls"

  if [ -n "$first_local" ]; then
    echo "${first_local}|"
    return 0
  fi

  return 1
}

resolve_call_file() {
  local current_file="$1"
  local import_path="$2"

  if [ -z "$current_file" ]; then
    echo ""
    return 0
  fi

  if [ -z "$import_path" ]; then
    echo "$current_file"
    return 0
  fi

  local full_path="$CWD/$current_file"
  local resolved
  resolved=$(resolve_import_target "$(dirname "$full_path")" "$import_path")

  if [[ "$resolved" == "$CWD"* ]]; then
    echo "${resolved#"$CWD"/}"
  else
    echo "$import_path"
  fi
}

# Build a single linear data-flow path for performance.
build_linear_flow_path() {
  local source_symbol="$1"
  local source_file="$2"
  local max_depth="$3"

  local path_nodes=()
  local tainted_list=()
  local tainted_seen="|"
  local visited="|"
  local depth=0
  local current_symbol="$source_symbol"
  local current_file="$source_file"
  local truncated=false

  if [ -n "$source_symbol" ]; then
    tainted_list+=("$source_symbol")
    tainted_seen="|$source_symbol|"
  fi

  while [ "$depth" -lt "$max_depth" ]; do
    [ -z "$current_symbol" ] && break

    if [[ "$visited" == *"|$current_symbol|"* ]]; then
      DATA_FLOW_CYCLE_DETECTED=true
      DATA_FLOW_CYCLE_PATH="${visited}${current_symbol}"
      break
    fi
    visited="${visited}${current_symbol}|"

    if [ -z "$current_file" ]; then
      break
    fi

    local full_path="$CWD/$current_file"
    [ -f "$full_path" ] || break

    local next_symbol
    next_symbol=$(get_next_call_in_file "$full_path" "$current_symbol")
    [ -z "$next_symbol" ] && break

    local next_file="$current_file"
    if [ "$max_depth" -gt 1 ]; then
      local next_def
      next_def=$(find_symbol_definition_fast "$next_symbol" || true)
      if [ -n "$next_def" ]; then
        next_file="${next_def%%|*}"
      fi
    fi

    local node
    node=$(printf '{"symbol":"%s","file":"%s","line":0,"transform":"function_call","type":"usage"}' \
      "$(json_escape "$next_symbol")" "$(json_escape "$next_file")")
    path_nodes+=("$node")

    if [[ "$tainted_seen" != *"|$next_symbol|"* ]]; then
      tainted_list+=("$next_symbol")
      tainted_seen="${tainted_seen}${next_symbol}|"
    fi

    current_symbol="$next_symbol"
    current_file="$next_file"
    depth=$((depth + 1))
  done

  if [ "$depth" -ge "$max_depth" ]; then
    local full_path=""
    if [ -n "$current_file" ]; then
      full_path="$CWD/$current_file"
    fi
    if [ -n "$full_path" ] && [ -f "$full_path" ]; then
      local extra_call
      extra_call=$(get_next_call_in_file "$full_path" "$current_symbol")
      [ -n "$extra_call" ] && truncated=true
    fi
  fi

  DATA_FLOW_TRUNCATED="$truncated"
  DATA_FLOW_PATH_NODES_JSON=$(build_json_array "${path_nodes[@]}")
  DATA_FLOW_NODE_COUNT="${#path_nodes[@]}"
  DATA_FLOW_TAINTED_JSON=$(build_string_array "${tainted_list[@]}")
  DATA_FLOW_TAINTED_COUNT="${#tainted_list[@]}"
}

# T3.2: 污点传播算法
# 参数: $1=符号名, $2=方向(forward/backward/both), $3=最大深度
# 返回: JSON 格式数据流路径
taint_propagate() {
  local source_symbol="$1"
  local direction="$2"
  local max_depth="$3"

  _reset_data_flow_state

  resolve_data_flow_file
  build_symbol_index

  if ! symbol_exists "$source_symbol"; then
    log_error "symbol not found: $source_symbol"
    exit 1
  fi

  local start_seconds=$SECONDS

  local source_def=""
  local source_file=""
  local source_line=0
  local source_type="unknown"

  if [ -n "$DATA_FLOW_FILE" ]; then
    source_file="${DATA_FLOW_FILE#"$CWD"/}"
  fi

  source_def=$(find_symbol_definition_fast "$source_symbol" || true)
  if [ -n "$source_def" ]; then
    source_file="${source_def%%|*}"
    source_line="${source_def#*|}"
    source_type="function"
  fi

  build_linear_flow_path "$source_symbol" "$source_file" "$max_depth"
  local path_nodes_json="$DATA_FLOW_PATH_NODES_JSON"

  if [ -z "$path_nodes_json" ] || [ "$path_nodes_json" = "[]" ]; then
    local fallback_node
    fallback_node=$(printf '{"symbol":"%s","file":"%s","line":%s,"transform":"definition","type":"definition"}' \
      "$(json_escape "$source_symbol")" "$(json_escape "$source_file")" "$source_line")
    path_nodes_json=$(build_json_array "$fallback_node")
    DATA_FLOW_PATH_NODES_JSON="$path_nodes_json"
    DATA_FLOW_NODE_COUNT=1
    DATA_FLOW_TAINTED_JSON=$(build_string_array "$source_symbol")
    DATA_FLOW_TAINTED_COUNT=1
  fi

  local paths_json="[$path_nodes_json]"

  local elapsed_ms=$(( (SECONDS - start_seconds) * 1000 ))

  local cycle_path_json="null"
  if [ "$DATA_FLOW_CYCLE_DETECTED" = "true" ]; then
    cycle_path_json="\"$(json_escape "$DATA_FLOW_CYCLE_PATH")\""
  fi

  printf '{'
  printf '"schema_version":"1.0",'
  printf '"source":{"symbol":"%s","file":"%s","line":%s,"type":"%s"},' \
    "$(json_escape "$source_symbol")" "$(json_escape "$source_file")" "$source_line" "$(json_escape "$source_type")"
  printf '"direction":"%s","max_depth":%s,' \
    "$(json_escape "$direction")" "$max_depth"
  printf '"paths":%s,' "$paths_json"
  printf '"tainted_symbols":%s,' "$DATA_FLOW_TAINTED_JSON"
  printf '"cycle_detected":%s,' "$DATA_FLOW_CYCLE_DETECTED"
  printf '"cycle_path":%s,' "$cycle_path_json"
  printf '"truncated":%s,' "$DATA_FLOW_TRUNCATED"
  printf '"metadata":{"elapsed_ms":%s,"path_count":1,"tainted_count":%s}' \
    "$elapsed_ms" "$DATA_FLOW_TAINTED_COUNT"
  printf '}\n'
}

# 检测符号类型
detect_symbol_type() {
  local symbol="$1"
  local file="$2"
  local line="$3"

  if [ -z "$file" ] || [ ! -f "$CWD/$file" ]; then
    echo "unknown"
    return
  fi

  # 读取符号所在行
  local content
  content=$(sed -n "${line}p" "$CWD/$file" 2>/dev/null || echo "")

  # 检测类型
  if [[ "$content" =~ function[[:space:]]+${symbol} ]] || [[ "$content" =~ ${symbol}[[:space:]]*\( ]]; then
    echo "function"
  elif [[ "$content" =~ (const|let|var)[[:space:]]+${symbol} ]]; then
    echo "variable"
  elif [[ "$content" =~ class[[:space:]]+${symbol} ]]; then
    echo "class"
  elif [[ "$content" =~ interface[[:space:]]+${symbol} ]]; then
    echo "interface"
  elif [[ "$content" =~ \(.*${symbol}.*\) ]]; then
    echo "parameter"
  else
    echo "unknown"
  fi
}

# T3.3: 正向追踪（从定义到使用）
trace_forward_flow() {
  local symbol="$1"
  local source_file="$2"

  local results='[]'

  if [ -n "$source_file" ] && [ -f "$CWD/$source_file" ]; then
    local full_path="$CWD/$source_file"
    local import_map
    import_map=$(collect_import_map "$full_path")

    local calls
    calls=$(extract_function_calls "$full_path" "$symbol")

    local call
    while IFS= read -r call; do
      [ -z "$call" ] && continue
      [ "$call" = "$symbol" ] && continue

      local target_file="$source_file"
      local import_path
      import_path=$(lookup_import_path "$import_map" "$call")
      if [ -n "$import_path" ]; then
        local resolved
        resolved=$(resolve_import_target "$(dirname "$full_path")" "$import_path")
        if [[ "$resolved" == "$CWD"* ]]; then
          target_file="${resolved#"$CWD"/}"
        else
          target_file="$import_path"
        fi
      fi

      results=$(echo "$results" | jq \
        --arg symbol "$call" \
        --arg file "$target_file" \
        --argjson line 0 \
        --arg transform "function_call" \
        --arg type "usage" \
        '. + [{symbol: $symbol, file: $file, line: $line, transform: $transform, type: $type}]')
    done <<< "$calls"
  fi

  local result_len
  result_len=$(echo "$results" | jq 'length')
  if [ "$result_len" -gt 0 ]; then
    echo "$results"
    return
  fi

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done
  [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

  if [ -n "$rg_cmd" ]; then
    # 查找使用此符号的位置
    local usages
    usages=$("$rg_cmd" -n --max-count=20 -t py -t js -t ts -t go \
      "\\b${symbol}\\b" "$CWD" 2>/dev/null | head -20)

    while IFS= read -r usage; do
      [ -z "$usage" ] && continue

      local file_path line content
      file_path=$(echo "$usage" | cut -d: -f1)
      line=$(echo "$usage" | cut -d: -f2)
      content=$(echo "$usage" | cut -d: -f3-)
      file_path="${file_path#"$CWD"/}"

      if [[ "$content" =~ function[[:space:]]+${symbol}\\b ]]; then
        continue
      fi

      # 检测转换类型
      local transform="usage"
      if [[ "$content" =~ ${symbol}[[:space:]]*\( ]]; then
        transform="function_call"
      elif [[ "$content" =~ =[[:space:]]*${symbol} ]]; then
        transform="assignment"
      elif [[ "$content" =~ \(.*${symbol} ]]; then
        transform="parameter_pass"
      elif [[ "$content" =~ return[[:space:]]+${symbol} ]]; then
        transform="return_value"
      fi

      # 检测目标符号（赋值左侧）
      local target_sym="$symbol"
      if [[ "$content" =~ ^[[:space:]]*(const|let|var)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*= ]]; then
        target_sym="${BASH_REMATCH[2]}"
        transform="assignment: $target_sym = $symbol"
      fi

      results=$(echo "$results" | jq \
        --arg symbol "$target_sym" \
        --arg file "$file_path" \
        --argjson line "$line" \
        --arg transform "$transform" \
        --arg type "usage" \
        '. + [{symbol: $symbol, file: $file, line: $line, transform: $transform, type: $type}]')
    done <<< "$usages"
  fi

  echo "$results"
}

# T3.3: 反向追踪（从使用到来源）
trace_backward_flow() {
  local symbol="$1"
  local source_file="$2"

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done
  [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

  local results='[]'

  if [ -n "$rg_cmd" ]; then
    # 查找定义或赋值此符号的位置
    local definitions
    definitions=$("$rg_cmd" -n --max-count=20 -t py -t js -t ts -t go \
      "(function|def|class|const|let|var|type|interface)\\s+${symbol}\\b|${symbol}\\s*=" "$CWD" 2>/dev/null | head -20)

    while IFS= read -r def; do
      [ -z "$def" ] && continue

      local file_path line content
      file_path=$(echo "$def" | cut -d: -f1)
      line=$(echo "$def" | cut -d: -f2)
      content=$(echo "$def" | cut -d: -f3-)
      file_path="${file_path#"$CWD"/}"

      # 检测转换类型
      local transform="definition"
      local source_sym=""

      if [[ "$content" =~ ${symbol}[[:space:]]*=[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
        source_sym="${BASH_REMATCH[1]}"
        transform="assignment_from: $source_sym"
      elif [[ "$content" =~ ${symbol}[[:space:]]*=[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\s*\( ]]; then
        source_sym="${BASH_REMATCH[1]}"
        transform="function_result: $source_sym()"
      elif [[ "$content" =~ (function|def)[[:space:]]+${symbol} ]]; then
        transform="function_definition"
        source_sym="$symbol"
      fi

      [ -z "$source_sym" ] && source_sym="$symbol"

      results=$(echo "$results" | jq \
        --arg symbol "$source_sym" \
        --arg file "$file_path" \
        --argjson line "$line" \
        --arg transform "$transform" \
        --arg type "definition" \
        '. + [{symbol: $symbol, file: $file, line: $line, transform: $transform, type: $type}]')
    done <<< "$definitions"
  fi

  echo "$results"
}

# T3.6: 数据流结果格式化输出
format_data_flow_output() {
  local result="$1"
  local format="$2"

  case "$format" in
    mermaid)
      format_data_flow_mermaid "$result"
      ;;
    text)
      format_data_flow_text "$result"
      ;;
    json|*)
      echo "$result"
      ;;
  esac
}

# T3.6: Mermaid 格式输出
format_data_flow_mermaid() {
  local result="$1"

  echo "flowchart LR"

  local source_sym source_file
  source_sym=$(echo "$result" | jq -r '.source.symbol')
  source_file=$(echo "$result" | jq -r '.source.file')

  echo "    ${source_sym}[\"${source_sym}<br/>${source_file}\"]"

  local paths
  paths=$(echo "$result" | jq '.paths')
  local path_count
  path_count=$(echo "$paths" | jq 'length')

  local node_id=0
  for ((i=0; i<path_count && i<10; i++)); do
    local path
    path=$(echo "$paths" | jq ".[$i]")
    local path_len
    path_len=$(echo "$path" | jq 'length')

    local prev_node="$source_sym"
    for ((j=0; j<path_len; j++)); do
      local node
      node=$(echo "$path" | jq ".[$j]")

      local sym file transform
      sym=$(echo "$node" | jq -r '.symbol')
      file=$(echo "$node" | jq -r '.file')
      transform=$(echo "$node" | jq -r '.transform')

      local node_name="${sym}_${node_id}"
      echo "    ${node_name}[\"${sym}<br/>${file}\"]"
      echo "    ${prev_node} -->|${transform}| ${node_name}"

      prev_node="$node_name"
      ((node_id++))
    done
  done

  # 标记循环
  local cycle_detected
  cycle_detected=$(echo "$result" | jq '.cycle_detected')
  if [ "$cycle_detected" = "true" ]; then
    echo "    style ${source_sym} fill:#f99,stroke:#f00"
    echo "    %% CYCLE_DETECTED"
  fi
}

# T3.6: 文本格式输出
format_data_flow_text() {
  local result="$1"

  local source_sym source_file direction max_depth cycle_detected truncated
  source_sym=$(echo "$result" | jq -r '.source.symbol')
  source_file=$(echo "$result" | jq -r '.source.file')
  direction=$(echo "$result" | jq -r '.direction')
  max_depth=$(echo "$result" | jq '.max_depth')
  cycle_detected=$(echo "$result" | jq '.cycle_detected')
  truncated=$(echo "$result" | jq '.truncated')

  echo "数据流追踪: $source_sym"
  echo "源文件: $source_file"
  echo "方向: $direction, 最大深度: $max_depth"

  [ "$cycle_detected" = "true" ] && echo "⚠️ 检测到循环依赖: $(echo "$result" | jq -r '.cycle_path')"
  [ "$truncated" = "true" ] && echo "⚠️ 已截断（达到深度限制）"

  echo ""
  echo "数据流路径:"

  local paths
  paths=$(echo "$result" | jq '.paths')
  local path_count
  path_count=$(echo "$paths" | jq 'length')

  for ((i=0; i<path_count && i<20; i++)); do
    local path
    path=$(echo "$paths" | jq ".[$i]")

    echo "  路径 $((i+1)):"
    echo "    $source_sym ($source_file)"

    local path_len
    path_len=$(echo "$path" | jq 'length')

    for ((j=0; j<path_len; j++)); do
      local node
      node=$(echo "$path" | jq ".[$j]")

      local sym file line transform
      sym=$(echo "$node" | jq -r '.symbol')
      file=$(echo "$node" | jq -r '.file')
      line=$(echo "$node" | jq '.line')
      transform=$(echo "$node" | jq -r '.transform')

      echo "    └── $sym ($file:$line) [$transform]"
    done

    echo ""
  done

  # 元数据
  local elapsed_ms path_count_total tainted_count
  elapsed_ms=$(echo "$result" | jq '.metadata.elapsed_ms')
  path_count_total=$(echo "$result" | jq '.metadata.path_count')
  tainted_count=$(echo "$result" | jq '.metadata.tainted_count')

  echo "统计: 路径数=$path_count_total, 污点符号数=$tainted_count, 耗时=${elapsed_ms}ms"
}

# M3 主入口：完整数据流追踪
trace_full_data_flow() {
  local symbol="$1"

  taint_propagate "$symbol" "$DATA_FLOW_DIRECTION" "$DATA_FLOW_MAX_DEPTH"
}
