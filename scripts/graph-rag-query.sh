#!/bin/bash
# Graph-RAG 查询处理模块
# 包含：Token 预算管理、子图构建、主查询逻辑

# ==================== Token 预算与智能裁剪 ====================

estimate_tokens() {
  local text="$1"
  local char_count=${#text}

  local base_estimate=$(( char_count / 4 ))

  local conservative_estimate=$(( base_estimate + base_estimate / 10 ))

  if [ "$char_count" -gt 0 ] && [ "$conservative_estimate" -lt 1 ]; then
    conservative_estimate=1
  fi

  echo "$conservative_estimate"
}

estimate_file_tokens() {
  local file_path="$1"
  local full_path="$CWD/$file_path"
  local content_tokens=0

  if [ -f "$full_path" ]; then
    local content
    content=$(head -50 "$full_path" 2>/dev/null)
    content_tokens=$(estimate_tokens "$content")
  fi

  echo "$content_tokens"
}

calculate_priority() {
  local candidate_json="$1"

  local relevance hotspot distance

  relevance=$(echo "$candidate_json" | jq -r '.relevance // .relevance_score // 0')
  hotspot=$(echo "$candidate_json" | jq -r '.hotspot // 0')
  distance=$(echo "$candidate_json" | jq -r '.distance // .depth // 1')

  if [ -z "$distance" ] || [ "$distance" = "null" ] || [ "$distance" = "0" ]; then
    distance=1
  fi

  awk -v r="$relevance" -v h="$hotspot" -v d="$distance" \
    -v wr="$PRIORITY_WEIGHT_RELEVANCE" -v wh="$PRIORITY_WEIGHT_HOTSPOT" -v wd="$PRIORITY_WEIGHT_DISTANCE" \
    'BEGIN {
      if (r == "" || r == "null") r = 0
      if (h == "" || h == "null") h = 0
      if (d == "" || d == "null" || d <= 0) d = 1
      priority = r * wr + h * wh + (1/d) * wd
      printf "%.4f", priority
    }'
}

add_priority_scores() {
  local candidates_json="$1"
  local result='[]'

  local count
  count=$(echo "$candidates_json" | jq 'length' 2>/dev/null || echo 0)

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")

    candidate=$(echo "$candidate" | jq '
      . + {
        relevance_score: (.relevance_score // .relevance // 0),
        hotspot: (.hotspot // 0),
        distance: (.distance // .depth // 1)
      }
    ')

    local priority
    priority=$(calculate_priority "$candidate")

    local file_path
    file_path=$(echo "$candidate" | jq -r '.file_path')
    local tokens
    tokens=$(estimate_file_tokens "$file_path")

    candidate=$(echo "$candidate" | jq \
      --argjson priority "$priority" \
      --argjson tokens "$tokens" \
      '. + {priority: $priority, tokens: $tokens}')

    result=$(echo "$result" | jq --argjson c "$candidate" '. + [$c]')
  done

  echo "$result"
}

validate_budget() {
  local budget="$1"

  if ! [[ "$budget" =~ ^-?[0-9]+$ ]]; then
    log_warn "无效的预算值: $budget, 使用默认值 8000" >&2
    echo "8000"
    return 0
  fi

  if [ "$budget" -lt 0 ]; then
    log_warn "预算不能为负数: $budget, 使用 0" >&2
    echo "0"
    return 0
  fi

  echo "$budget"
}

trim_by_budget() {
  local candidates_json="$1"
  local budget="$2"

  budget=$(validate_budget "$budget")

  if [ "$budget" -eq 0 ]; then
    log_warn "Token 预算为 0，返回空结果" >&2
    echo '[]'
    return 0
  fi

  local total_tokens=0
  local result='[]'
  local skipped_oversized=0

  local count
  count=$(echo "$candidates_json" | jq 'length' 2>/dev/null || echo 0)

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")

    local file_path
    file_path=$(echo "$candidate" | jq -r '.file_path')

    local content_tokens
    content_tokens=$(echo "$candidate" | jq -r '.tokens // 0')

    if [ "$content_tokens" -eq 0 ]; then
      content_tokens=$(estimate_file_tokens "$file_path")
    fi

    if [ "$content_tokens" -gt "$budget" ]; then
      ((skipped_oversized++)) || true
      log_warn "片段 $file_path ($content_tokens tokens) 超过预算 ($budget)，跳过" >&2
      continue
    fi

    if [ $((total_tokens + content_tokens)) -gt "$budget" ]; then
      break
    fi

    total_tokens=$((total_tokens + content_tokens))
    result=$(echo "$result" | jq --argjson c "$candidate" '. + [$c]')
  done

  if [ "$(echo "$result" | jq 'length')" -eq 0 ] && [ "$skipped_oversized" -gt 0 ]; then
    log_warn "所有 $skipped_oversized 个候选片段都超过预算 ($budget tokens)" >&2
  fi

  echo "$result"
}

# ==================== 子图构建 ====================

build_subgraph() {
  local candidates_json="$1"
  local nodes='[]'
  local edges='[]'

  local count
  count=$(echo "$candidates_json" | jq 'length' 2>/dev/null || echo 0)

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")

    local file_path symbol_id relevance_score depth
    file_path=$(echo "$candidate" | jq -r '.file_path')
    symbol_id=$(echo "$candidate" | jq -r '.symbol_id // empty')
    relevance_score=$(echo "$candidate" | jq -r '.relevance_score // 0')
    depth=$(echo "$candidate" | jq -r '.depth // 0')

    local node_id
    if [ -n "$symbol_id" ] && [ "$symbol_id" != "null" ]; then
      node_id="$symbol_id"
    else
      node_id="${file_path}::main"
    fi

    nodes=$(echo "$nodes" | jq --arg id "$node_id" --arg file "$file_path" \
      --argjson score "$relevance_score" --argjson depth "$depth" \
      '. + [{id: $id, file_path: $file, relevance_score: $score, depth: $depth}]')

    local callers callees
    callers=$(echo "$candidate" | jq '.callers // []')
    callees=$(echo "$candidate" | jq '.callees // []')

    local caller_count
    caller_count=$(echo "$callers" | jq 'length' 2>/dev/null || echo 0)
    for ((j=0; j<caller_count; j++)); do
      local caller
      caller=$(echo "$callers" | jq ".[$j]")
      local caller_id
      caller_id=$(echo "$caller" | jq -r '.symbol_id // .file_path // empty')
      if [ -n "$caller_id" ] && [ "$caller_id" != "null" ]; then
        edges=$(echo "$edges" | jq --arg from "$caller_id" --arg to "$node_id" \
          '. + [{from: $from, to: $to, type: "refs"}]')
      fi
    done

    local callee_count
    callee_count=$(echo "$callees" | jq 'length' 2>/dev/null || echo 0)
    for ((j=0; j<callee_count; j++)); do
      local callee
      callee=$(echo "$callees" | jq ".[$j]")
      local callee_id
      callee_id=$(echo "$callee" | jq -r '.symbol_id // .file_path // empty')
      if [ -n "$callee_id" ] && [ "$callee_id" != "null" ]; then
        edges=$(echo "$edges" | jq --arg from "$node_id" --arg to "$callee_id" \
          '. + [{from: $from, to: $to, type: "calls"}]')
      fi
    done
  done

  jq -n --argjson nodes "$nodes" --argjson edges "$edges" \
    '{nodes: $nodes, edges: $edges}'
}

# ==================== 主查询逻辑 ====================

build_context() {
  local query="$1"

  : # _detect_ckb removed

  BOUNDARY_FILTERED_COUNT=0

  # 初始化缓存键和回退原因
  local cache_key="graph-rag:${query}"
  local ckb_fallback_reason=""

  local cached
  cached=$(get_cached "$cache_key")
  if [ -n "$cached" ]; then
    echo "$cached"
    return 0
  fi

  local candidates='[]'
  local vector_candidates='[]'
  local keyword_candidates='[]'
  local graph_candidates='[]'

  vector_candidates=$(embedding_search "$query" "$TOP_K")
  [ -z "$vector_candidates" ] && vector_candidates='[]'

  if [[ "$MOCK_EMBEDDING" != true ]]; then
    keyword_candidates=$(keyword_search "$query" "$TOP_K")
  fi
  [ -z "$keyword_candidates" ] && keyword_candidates='[]'

  if [ "$FUSION_DEPTH" -gt 0 ]; then
    graph_candidates=$(_expand_with_import_analysis "$vector_candidates" "$MAX_DEPTH")

    [ -z "$graph_candidates" ] && graph_candidates='[]'
    candidates=$(rrf_fusion "$keyword_candidates" "$vector_candidates" "$graph_candidates" \
      "$HYBRID_WEIGHT_KEYWORD" "$HYBRID_WEIGHT_VECTOR" "$HYBRID_WEIGHT_GRAPH" "$HYBRID_RRF_K")
  else
    candidates="$vector_candidates"
    if [ -z "$candidates" ] || [ "$candidates" = "[]" ]; then
      candidates="$keyword_candidates"
    fi
  fi

  if [ -z "$candidates" ] || [ "$candidates" = "[]" ]; then
    candidates='[]'
  fi

  local graph_candidates_count
  graph_candidates_count=$(echo "$graph_candidates" | jq 'length' 2>/dev/null || echo 0)

  candidates=$(filter_library_code "$candidates")

  if [ -n "$MIN_RELEVANCE" ] && [[ "$MIN_RELEVANCE" != "0" ]] && [[ "$MIN_RELEVANCE" != "0.0" ]]; then
    candidates=$(echo "$candidates" | jq --argjson threshold "$MIN_RELEVANCE" \
      '[.[] | select((.relevance_score // .relevance // 0) >= $threshold)]')
  fi

  candidates=$(add_priority_scores "$candidates")

  candidates=$(echo "$candidates" | jq 'sort_by(-.priority // -.relevance_score // 0)')

  if [ "$RERANK_ENABLED" = true ]; then
    local rerank_state_file
    rerank_state_file=$(mktemp)
    candidates=$(llm_rerank_candidates "$query" "$candidates" "$rerank_state_file")
    if [[ -f "$rerank_state_file" ]]; then
      # shellcheck disable=SC1090
      source "$rerank_state_file"
      rm -f "$rerank_state_file"
    fi
  elif [ "$RERANK_CLI_DISABLED" = true ]; then
    RERANK_RESULT_RERANKED=false
    RERANK_RESULT_FALLBACK_REASON="cli_disabled"
  fi

  local trimmed
  trimmed=$(trim_by_budget "$candidates" "$TOKEN_BUDGET")

  local total_tokens=0
  local candidate_count
  candidate_count=$(echo "$trimmed" | jq 'length')

  for ((i=0; i<candidate_count; i++)); do
    local precomputed_tokens
    precomputed_tokens=$(echo "$trimmed" | jq -r ".[$i].tokens // 0")

    if [ "$precomputed_tokens" -gt 0 ]; then
      total_tokens=$((total_tokens + precomputed_tokens))
    else
      local file_path
      file_path=$(echo "$trimmed" | jq -r ".[$i].file_path")
      local full_path="$CWD/$file_path"

      if [ -f "$full_path" ]; then
        local content
        content=$(head -50 "$full_path" 2>/dev/null)
        total_tokens=$((total_tokens + $(estimate_tokens "$content")))
      fi
    fi
  done

  local subgraph='{"nodes":[],"edges":[]}'
  if [ "$LEGACY_MODE" = false ]; then
    subgraph=$(build_subgraph "$trimmed")
  fi

  local result

  result=$(jq -n \
    --arg version "1.0" \
    --arg source "graph-rag" \
    --argjson tokens "$total_tokens" \
    --argjson subgraph "$subgraph" \
    --argjson candidates "$trimmed" \
    --argjson graph_depth "$MAX_DEPTH" \
    --argjson fusion_depth "$FUSION_DEPTH" \
    --arg fusion_weights "${HYBRID_WEIGHT_KEYWORD},${HYBRID_WEIGHT_VECTOR},${HYBRID_WEIGHT_GRAPH}" \
    --argjson boundary_filtered "$BOUNDARY_FILTERED_COUNT" \
    --argjson legacy "$LEGACY_MODE" \
    --argjson reranked "$RERANK_RESULT_RERANKED" \
    --argjson truncated "$RERANK_RESULT_TRUNCATED" \
    --arg provider "${RERANK_RESULT_PROVIDER:-}" \
    --arg fallback_reason "${RERANK_RESULT_FALLBACK_REASON:-}" \
    --arg ckb_fallback_reason "$ckb_fallback_reason" \
    --argjson retry_count "${RERANK_RESULT_RETRY_COUNT:-0}" \
    --argjson max_candidate_length "${RERANK_RESULT_MAX_CANDIDATE_LENGTH:-0}" \
    --argjson graph_candidates_count "$graph_candidates_count" \
    '{
      schema_version: $version,
      source: $source,
      token_count: $tokens,
      subgraph: $subgraph,
      candidates: $candidates,
      metadata: {
        ckb_fallback_reason: (if $ckb_fallback_reason != "" then $ckb_fallback_reason else null end),
        fusion_depth: $fusion_depth,
        fusion_weights: $fusion_weights,
        graph_depth: $graph_depth,
        token_count: $tokens,
        boundary_filtered: $boundary_filtered,
        legacy_mode: $legacy,
        reranked: $reranked,
        truncated: (if $truncated == true then true else null end),
        graph_candidates: $graph_candidates_count,
        provider: (if $provider != "" then $provider else null end),
        fallback_reason: (if $fallback_reason != "" then $fallback_reason else null end),
        retry_count: (if $retry_count > 0 then $retry_count else null end),
        max_candidate_length: (if $max_candidate_length > 0 then $max_candidate_length else null end)
      }
    }')

  set_cache "$cache_key" "$result"

  echo "$result"
}

# ==================== 输出结果 ====================

output_result() {
  local result="$1"

  if [ "$OUTPUT_FORMAT" = "json" ]; then
    echo "$result"
  else
    local candidate_count
    candidate_count=$(echo "$result" | jq '.candidates | length')
    local token_count
    token_count=$(echo "$result" | jq '.token_count')
    local edge_count
    edge_count=$(echo "$result" | jq '.subgraph.edges | length')
    local filtered_count
    filtered_count=$(echo "$result" | jq '.metadata.boundary_filtered // 0')

    echo "找到 $candidate_count 个相关结果（约 $token_count tokens）"
    [ "$filtered_count" -gt 0 ] && echo "（已过滤 $filtered_count 个库代码文件）"
    echo ""

    if [ "$edge_count" -gt 0 ] && [ "$LEGACY_MODE" = false ]; then
      echo "调用关系图："
      local j=0
      while [ "$j" -lt "$edge_count" ] && [ "$j" -lt 20 ]; do
        local edge
        edge=$(echo "$result" | jq ".subgraph.edges[$j]")
        local from to edge_type
        from=$(echo "$edge" | jq -r '.from')
        to=$(echo "$edge" | jq -r '.to')
        edge_type=$(echo "$edge" | jq -r '.type')

        if [ "$edge_type" = "calls" ]; then
          echo "  $from --calls--> $to"
        else
          echo "  $from --refs--> $to"
        fi
        ((j++)) || true
      done
      echo ""
    fi

    echo "相关文件："
    for ((i=0; i<candidate_count && i<10; i++)); do
      local candidate
      candidate=$(echo "$result" | jq ".candidates[$i]")
      local file_path score
      file_path=$(echo "$candidate" | jq -r '.file_path')
      score=$(echo "$candidate" | jq -r '.relevance_score // "N/A"')

      echo "[$score] $file_path"

      local full_path="$CWD/$file_path"
      if [ -f "$full_path" ]; then
        echo "---"
        head -10 "$full_path" 2>/dev/null | sed 's/^/  /'
        echo ""
      fi
    done
  fi
}
