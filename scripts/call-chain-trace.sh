#!/bin/bash
# DevBooks Call-Chain Tracer - Trace Module
# 调用链追踪逻辑：符号查找、调用链遍历、入口路径追溯

# ==================== 符号查找 ====================

# 在代码库中查找符号定义
find_symbol_definition() {
  local symbol="$1"

  # 使用 ripgrep 查找定义
  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done

  if [ -z "$rg_cmd" ]; then
    return 1
  fi

  # 构建定义模式
  local def_pattern="(function|def|class|const|let|var|type|interface|struct|enum)\\s+${symbol}\\b"

  local result
  result=$("$rg_cmd" \
    --max-count=1 \
    -n \
    --pcre2 \
    -t py -t js -t ts -t go \
    "$def_pattern" "$CWD" 2>/dev/null | head -1)

  if [ -n "$result" ]; then
    local file_path line
    file_path=$(echo "$result" | cut -d: -f1)
    line=$(echo "$result" | cut -d: -f2)
    file_path="${file_path#"$CWD"/}"

    jq -n \
      --arg symbol "$symbol" \
      --arg file "$file_path" \
      --argjson line "$line" \
      '{symbol_id: $symbol, file_path: $file, line: $line}'
    return 0
  fi

  return 1
}

# ==================== 调用链分析 ====================

# 检查节点是否已访问（循环检测）
is_visited() {
  local node="$1"
  echo "$VISITED_NODES" | jq -e --arg n "$node" 'index($n)' >/dev/null 2>&1
}

# 标记节点为已访问
mark_visited() {
  local node="$1"
  VISITED_NODES=$(echo "$VISITED_NODES" | jq --arg n "$node" '. + [$n]')
}

# 分析文件中的函数调用
analyze_function_calls() {
  local file_path="$1"
  local symbol="$2"
  local direction="$3"

  local full_path="$CWD/$file_path"
  if [ ! -f "$full_path" ]; then
    echo '[]'
    return 0
  fi

  local results='[]'

  if [ "$direction" = "callees" ] || [ "$direction" = "both" ]; then
    # 查找此函数调用的其他函数
    # 简化实现：查找函数体内的函数调用
    local function_body
    function_body=$(sed -n "/${symbol}/,/^[^ ]/p" "$full_path" 2>/dev/null | head -50)

    # 提取函数调用模式
    local calls
    calls=$(echo "$function_body" | grep -oE '\b[a-zA-Z_][a-zA-Z0-9_]*\s*\(' | \
      sed 's/\s*(//' | grep -vE '^(if|for|while|switch|return|print|console|log)$' | \
      sort -u | head -10)

    while IFS= read -r callee; do
      [ -z "$callee" ] && continue
      results=$(echo "$results" | jq --arg c "$callee" '. + [{symbol_id: $c, type: "callee"}]')
    done <<< "$calls"
  fi

  if [ "$direction" = "callers" ] || [ "$direction" = "both" ]; then
    # 查找调用此函数的其他位置
    local rg_cmd=""
    for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
      [ -x "$p" ] && { rg_cmd="$p"; break; }
    done

    if [ -n "$rg_cmd" ]; then
      local callers
      callers=$("$rg_cmd" -l --max-count=5 -t py -t js -t ts -t go \
        "${symbol}\\s*\\(" "$CWD" 2>/dev/null | grep -v "$file_path" | head -5)

      while IFS= read -r caller_file; do
        [ -z "$caller_file" ] && continue
        local rel_path="${caller_file#"$CWD"/}"
        results=$(echo "$results" | jq --arg f "$rel_path" '. + [{file_path: $f, type: "caller"}]')
      done <<< "$callers"
    fi
  fi

  echo "$results"
}

# 递归遍历调用链
traverse_call_chain() {
  local symbol="$1"
  local current_depth="$2"
  local max_depth="$3"
  local direction="$4"

  # 深度检查
  if [ "$current_depth" -gt "$max_depth" ]; then
    echo '{"depth_limit_reached": true}'
    return 0
  fi

  # 循环检测
  if is_visited "$symbol"; then
    CYCLE_DETECTED=true
    echo '{"cycle_detected": true, "symbol": "'"$symbol"'"}'
    return 0
  fi

  mark_visited "$symbol"

  # 查找符号定义
  local definition
  definition=$(find_symbol_definition "$symbol")

  if [ -z "$definition" ]; then
    echo '{"symbol_id": "'"$symbol"'", "not_found": true}'
    return 0
  fi

  local file_path line
  file_path=$(echo "$definition" | jq -r '.file_path')
  line=$(echo "$definition" | jq -r '.line')

  # 分析调用关系
  local calls
  calls=$(analyze_function_calls "$file_path" "$symbol" "$direction")

  # 构建节点
  local node
  node=$(jq -n \
    --arg symbol "$symbol" \
    --arg file "$file_path" \
    --argjson line "$line" \
    --argjson depth "$current_depth" \
    '{
      symbol_id: $symbol,
      file_path: $file,
      line: $line,
      depth: $depth
    }')

  # 递归遍历（如果深度允许）
  if [ "$current_depth" -lt "$max_depth" ]; then
    local callers='[]'
    local callees='[]'

    local call_count
    call_count=$(echo "$calls" | jq 'length')

    for ((i=0; i<call_count && i<5; i++)); do
      local call
      call=$(echo "$calls" | jq ".[$i]")
      local call_type
      call_type=$(echo "$call" | jq -r '.type')
      local call_symbol
      call_symbol=$(echo "$call" | jq -r '.symbol_id // .file_path')

      if [ "$call_type" = "callee" ] && [ "$direction" != "callers" ]; then
        local child
        child=$(traverse_call_chain "$call_symbol" $((current_depth + 1)) "$max_depth" "callees")
        callees=$(echo "$callees" | jq --argjson c "$child" '. + [$c]')
      elif [ "$call_type" = "caller" ] && [ "$direction" != "callees" ]; then
        callers=$(echo "$callers" | jq --argjson c "$call" '. + [$c]')
      fi
    done

    node=$(echo "$node" | jq --argjson callers "$callers" --argjson callees "$callees" \
      '. + {callers: $callers, callees: $callees}')
  fi

  echo "$node"
}

# ==================== 入口路径追溯 ====================

trace_usage_paths() {
  local symbol="$1"

  # 简化实现：查找所有调用此符号的位置，构建路径
  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done

  if [ -z "$rg_cmd" ]; then
    echo '[]'
    return 0
  fi

  local usages
  usages=$("$rg_cmd" -n --max-count=10 -t py -t js -t ts -t go \
    "${symbol}\\s*\\(" "$CWD" 2>/dev/null | head -10)

  local paths='[]'

  while IFS= read -r usage; do
    [ -z "$usage" ] && continue
    local file_path line
    file_path=$(echo "$usage" | cut -d: -f1)
    line=$(echo "$usage" | cut -d: -f2)
    file_path="${file_path#"$CWD"/}"

    paths=$(echo "$paths" | jq \
      --arg file "$file_path" \
      --argjson line "$line" \
      --arg symbol "$symbol" \
      '. + [{file_path: $file, line: $line, symbol_name: $symbol}]')
  done <<< "$usages"

  echo "$paths"
}

# ==================== 数据流追踪 (AC-006) ====================

# 追踪参数在函数调用链中的流动
# 输出格式: source → path → sink
trace_data_flow() {
  local symbol="$1"

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done

  # If ripgrep not found in standard paths, try using PATH
  if [ -z "$rg_cmd" ]; then
    rg_cmd=$(command -v rg 2>/dev/null || true)
  fi

  if [ -z "$rg_cmd" ]; then
    # Return a valid JSON structure with expected fields even when ripgrep is unavailable
    jq -n \
      --arg symbol "$symbol" \
      '{
        schema_version: "1.0",
        target_symbol: $symbol,
        source: {file: null, line: 0, function: null},
        data_flows: [],
        call_chain: [],
        flow_summary: {
          total_flows: 0,
          unique_sources: 0,
          parameter_count: 0
        },
        error: "ripgrep not available - install with: brew install ripgrep"
      }'
    return 0
  fi

  # 查找符号定义
  local definition
  definition=$(find_symbol_definition "$symbol")

  local source_file="" source_line=""
  if [ -n "$definition" ]; then
    source_file=$(echo "$definition" | jq -r '.file_path')
    source_line=$(echo "$definition" | jq -r '.line')
  fi

  # 查找所有调用此符号的位置并分析参数
  local usages
  usages=$("$rg_cmd" -n --max-count=20 -t py -t js -t ts -t go \
    "${symbol}\\s*\\(" "$CWD" 2>/dev/null | head -20)

  local flows='[]'

  while IFS= read -r usage; do
    [ -z "$usage" ] && continue

    local file_path line content
    file_path=$(echo "$usage" | cut -d: -f1)
    line=$(echo "$usage" | cut -d: -f2)
    content=$(echo "$usage" | cut -d: -f3-)
    file_path="${file_path#"$CWD"/}"

    # 提取参数（简化实现）
    local args
    args=$(echo "$content" | grep -oE "${symbol}\\s*\\([^)]*\\)" | sed "s/${symbol}\\s*(//;s/)$//" | head -1)

    # 构建数据流路径
    local flow
    flow=$(jq -n \
      --arg source "$source_file:$source_line" \
      --arg path "$file_path:$line" \
      --arg sink "$symbol" \
      --arg args "$args" \
      '{
        source: $source,
        path: $path,
        sink: $sink,
        arguments: $args,
        flow_type: "parameter_pass"
      }')

    flows=$(echo "$flows" | jq --argjson f "$flow" '. + [$f]')
  done <<< "$usages"

  # 构建输出
  jq -n \
    --arg symbol "$symbol" \
    --arg source_file "$source_file" \
    --argjson source_line "${source_line:-0}" \
    --argjson flows "$flows" \
    '{
      schema_version: "1.0",
      target_symbol: $symbol,
      source: {file: $source_file, line: $source_line, function: $symbol},
      data_flows: $flows,
      call_chain: $flows,
      flow_summary: {
        total_flows: ($flows | length),
        unique_sources: ([$flows[].source] | unique | length),
        parameter_count: ([$flows[].arguments] | map(select(. != "")) | length)
      }
    }'
}
