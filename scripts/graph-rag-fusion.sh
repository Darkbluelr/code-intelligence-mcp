#!/bin/bash
# Graph-RAG 融合模块
# 包含：RRF 融合、LLM 重排序、启发式重排序

# ==================== 重排序状态变量 ====================

RERANK_RESULT_RERANKED=false
RERANK_RESULT_PROVIDER=""
RERANK_RESULT_FALLBACK_REASON=""
RERANK_RESULT_RETRY_COUNT=0
RERANK_RESULT_TRUNCATED=false
RERANK_RESULT_MAX_CANDIDATE_LENGTH=0

# ==================== RRF 融合 ====================

rrf_fusion() {
  local keyword_json="$1"
  local vector_json="$2"
  local graph_json="$3"
  local weight_keyword="$4"
  local weight_vector="$5"
  local weight_graph="$6"
  local rrf_k="$7"

  jq -n \
    --argjson keyword "$keyword_json" \
    --argjson vector "$vector_json" \
    --argjson graph "$graph_json" \
    --argjson wk "$weight_keyword" \
    --argjson wv "$weight_vector" \
    --argjson wg "$weight_graph" \
    --argjson rrf_k "$rrf_k" \
    '
    def rank_entries(list; source):
      list | to_entries | map({file_path: .value.file_path, rank: (.key + 1), source: source, data: .value});
    def weight_for(source):
      if source == "keyword" then $wk elif source == "vector" then $wv else $wg end;
    def score(rank; weight): weight / ($rrf_k + rank);

    (rank_entries($keyword; "keyword") + rank_entries($vector; "vector") + rank_entries($graph; "graph"))
    | group_by(.file_path)
    | map({
        file_path: .[0].file_path,
        fusion_score: (map(score(.rank; weight_for(.source))) | add),
        merged: (map(.data) | reduce .[] as $item ({}; . * $item))
      })
    | map(.merged + {fusion_score: .fusion_score} | . + {relevance_score: (.relevance_score // .fusion_score)})
    | sort_by(-.fusion_score)
    '
}

# ==================== LLM 重排序 ====================

_is_llm_rerank_enabled() {
  local config_file="${FEATURES_CONFIG:-${DEVBOOKS_FEATURE_CONFIG:-}}"

  if [[ ! -f "$config_file" ]]; then
    return 1
  fi

  local enabled
  enabled=$(awk '
    BEGIN { in_features = 0; in_llm_rerank = 0 }
    /^features:/ { in_features = 1; next }
    /^[a-zA-Z]/ && !/^features:/ { in_features = 0; in_llm_rerank = 0 }
    in_features && /llm_rerank:/ { in_llm_rerank = 1; next }
    in_features && /^[[:space:]][[:space:]][a-zA-Z]/ && !/llm_rerank/ { in_llm_rerank = 0 }
    in_llm_rerank && /enabled:/ {
      sub(/^[^:]+:[[:space:]]*/, "")
      gsub(/#.*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ' "$config_file" 2>/dev/null)

  case "$enabled" in
    true|True|TRUE|yes|Yes|YES|1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_build_rerank_prompt() {
  local query="$1"
  local candidates_json="$2"
  local max_candidates="${3:-$RERANK_MAX_CANDIDATES}"

  local truncated
  truncated=$(echo "$candidates_json" | jq ".[0:$max_candidates]")

  local candidates_text=""
  local count
  count=$(echo "$truncated" | jq 'length')

  for ((i=0; i<count; i++)); do
    local file_path score
    file_path=$(echo "$truncated" | jq -r ".[$i].file_path")
    score=$(echo "$truncated" | jq -r ".[$i].relevance_score // 0")
    candidates_text="${candidates_text}[$i] $file_path (score: $score)
"
  done

  cat << EOF
You are a code relevance ranker. Given a query and a list of code file candidates,
rank them by relevance to the query. Return a JSON array of objects with:
- index: original index (0-based)
- score: relevance score (0-10, 10 being most relevant)
- reason: brief explanation (optional)

Query: $query

Candidates:
$candidates_text

Return ONLY valid JSON array, no other text. Example:
[{"index": 0, "score": 8, "reason": "directly related"}, {"index": 1, "score": 5, "reason": "partially related"}]
EOF
}

_parse_rerank_response() {
  local response="$1"
  local original_candidates="$2"

  if ! echo "$response" | jq -e '.' &>/dev/null; then
    log_warn "LLM 重排序响应格式无效: invalid JSON"
    RERANK_RESULT_FALLBACK_REASON="invalid_json"
    echo "$original_candidates"
    return 1
  fi

  if ! echo "$response" | jq -e 'type == "array"' &>/dev/null; then
    log_warn "LLM 重排序响应不是数组"
    RERANK_RESULT_FALLBACK_REASON="invalid_format"
    echo "$original_candidates"
    return 1
  fi

  local reranked='[]'
  local rankings
  rankings=$(echo "$response" | jq 'sort_by(-.score)')

  local rank_count
  rank_count=$(echo "$rankings" | jq 'length')
  local orig_count
  orig_count=$(echo "$original_candidates" | jq 'length')

  for ((i=0; i<rank_count; i++)); do
    local idx score reason
    idx=$(echo "$rankings" | jq -r ".[$i].index // -1")
    score=$(echo "$rankings" | jq -r ".[$i].score // 0")
    reason=$(echo "$rankings" | jq -r ".[$i].reason // \"\"")

    if [[ "$idx" -ge 0 && "$idx" -lt "$orig_count" ]]; then
      local candidate
      candidate=$(echo "$original_candidates" | jq ".[$idx]")
      candidate=$(echo "$candidate" | jq \
        --argjson llm_score "$score" \
        --arg llm_reason "$reason" \
        '. + {llm_score: $llm_score, llm_reason: $llm_reason}')
      reranked=$(echo "$reranked" | jq --argjson c "$candidate" '. + [$c]')
    fi
  done

  echo "$reranked"
  return 0
}

get_file_mtime() {
  local path="$1"
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    echo 0
    return
  fi
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
  elif stat -c %Y "$path" >/dev/null 2>&1; then
    stat -c %Y "$path"
  else
    echo 0
  fi
}

heuristic_rerank_candidates() {
  local query="$1"
  local candidates_json="$2"
  local normalized_query
  normalized_query=$(echo "$query" | tr 'A-Z' 'a-z')

  local updated='[]'
  local count
  count=$(echo "$candidates_json" | jq 'length' 2>/dev/null || echo 0)

  [[ ! "$count" =~ ^[0-9]+$ ]] && count=0

  local i=0
  while [ "$i" -lt "$count" ]; do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")

    local file_path base_name base_stem
    file_path=$(echo "$candidate" | jq -r '.file_path // .file // ""')
    [ -z "$file_path" ] && file_path="unknown"
    base_name=$(basename "$file_path" 2>/dev/null || echo "$file_path")
    base_stem="${base_name%.*}"

    local base_lower
    base_lower=$(echo "$base_stem" | tr 'A-Z' 'a-z')

    local match="0"
    if [ -n "$base_lower" ]; then
      if [[ "$base_lower" == *"$normalized_query"* ]] || [[ "$normalized_query" == *"$base_lower"* ]]; then
        match="1"
      else
        for token in $normalized_query; do
          if [[ "$base_lower" == *"$token"* ]] || [[ "$token" == *"$base_lower"* ]]; then
            match="1"
            break
          fi
        done
      fi
    fi

    local depth="999"
    if [ -n "$file_path" ] && [ "$file_path" != "unknown" ]; then
      depth=$(echo "$file_path" | awk -F'/' '{print NF}')
      [[ ! "$depth" =~ ^[0-9]+$ ]] && depth="999"
    fi

    local mtime
    mtime=$(get_file_mtime "$CWD/$file_path" 2>/dev/null)
    [ -z "$mtime" ] && mtime="0"
    [[ ! "$mtime" =~ ^[0-9]+$ ]] && mtime="0"

    local heuristic_score
    heuristic_score=$(awk -v m="$match" -v d="$depth" -v t="$mtime" \
      'BEGIN {printf "%.2f", (m * 1000) + (100 - d) + (t / 1000000000)}')
    [ -z "$heuristic_score" ] && heuristic_score="0.00"

    candidate=$(echo "$candidate" | jq \
      --argjson match "$match" \
      --argjson depth "$depth" \
      --argjson mtime "$mtime" \
      --argjson score "$heuristic_score" \
      '. + {heuristic_score: $score, _heuristic_match: $match, _heuristic_depth: $depth, _heuristic_mtime: $mtime}')

    updated=$(echo "$updated" | jq --argjson c "$candidate" '. + [$c]')

    i=$((i + 1))
  done

  updated=$(echo "$updated" | jq 'sort_by(-._heuristic_match, ._heuristic_depth, -._heuristic_mtime) | map(del(._heuristic_match, ._heuristic_depth, ._heuristic_mtime))')

  echo "$updated"
}

llm_rerank_candidates() {
  local query="$1"
  local candidates_json="$2"
  local state_file="${3:-}"

  RERANK_RESULT_RERANKED=false
  RERANK_RESULT_PROVIDER=""
  RERANK_RESULT_FALLBACK_REASON=""
  RERANK_RESULT_RETRY_COUNT=0
  RERANK_RESULT_TRUNCATED=false
  RERANK_RESULT_MAX_CANDIDATE_LENGTH=0

  _write_rerank_state() {
    if [[ -n "$state_file" ]]; then
      cat > "$state_file" << EOF
RERANK_RESULT_RERANKED=$RERANK_RESULT_RERANKED
RERANK_RESULT_PROVIDER="$RERANK_RESULT_PROVIDER"
RERANK_RESULT_FALLBACK_REASON="$RERANK_RESULT_FALLBACK_REASON"
RERANK_RESULT_RETRY_COUNT=$RERANK_RESULT_RETRY_COUNT
RERANK_RESULT_TRUNCATED=$RERANK_RESULT_TRUNCATED
RERANK_RESULT_MAX_CANDIDATE_LENGTH=$RERANK_RESULT_MAX_CANDIDATE_LENGTH
EOF
    fi
  }

  if ! _is_llm_rerank_enabled; then
    RERANK_RESULT_FALLBACK_REASON="disabled"
    _write_rerank_state
    echo "$candidates_json"
    return 0
  fi

  local provider
  provider=$(_get_llm_config "provider" "anthropic")
  RERANK_RESULT_PROVIDER="$provider"

  local max_candidate_length
  max_candidate_length=$(_get_llm_config "max_candidate_length" "")
  local rerank_limit="$RERANK_MAX_CANDIDATES"
  if [[ "$max_candidate_length" =~ ^[0-9]+$ ]] && [[ "$max_candidate_length" -gt 0 ]]; then
    rerank_limit="$max_candidate_length"
    RERANK_RESULT_MAX_CANDIDATE_LENGTH=$max_candidate_length
  fi

  local count
  count=$(echo "$candidates_json" | jq 'length' 2>/dev/null || echo 0)
  if [[ "$count" -gt "$rerank_limit" ]]; then
    RERANK_RESULT_TRUNCATED=true
  fi
  if [[ "$count" -eq 0 ]]; then
    RERANK_RESULT_FALLBACK_REASON="empty_candidates"
    _write_rerank_state
    echo "$candidates_json"
    return 0
  fi

  if [[ "$provider" == "heuristic" ]]; then
    local reranked
    reranked=$(heuristic_rerank_candidates "$query" "$candidates_json")
    RERANK_RESULT_PROVIDER="heuristic"
    RERANK_RESULT_RERANKED=true
    _write_rerank_state
    echo "$reranked"
    return 0
  fi

  if [[ -z "${LLM_MOCK_RESPONSE:-}" && -z "${LLM_MOCK_DELAY_MS:-}" ]]; then
    if ! llm_available; then
      local reranked
      reranked=$(heuristic_rerank_candidates "$query" "$candidates_json")
      RERANK_RESULT_PROVIDER="heuristic"
      RERANK_RESULT_RERANKED=true
      RERANK_RESULT_FALLBACK_REASON="api_key_missing"
      _write_rerank_state
      echo "$reranked"
      return 0
    fi
  fi

  local prompt
  prompt=$(_build_rerank_prompt "$query" "$candidates_json" "$rerank_limit")

  local max_retries
  max_retries=$(_get_llm_config "max_retries" "0")
  [[ ! "$max_retries" =~ ^[0-9]+$ ]] && max_retries=0

  local attempt=0
  local response
  local exit_code
  local last_error=""

  while [[ $attempt -le $max_retries ]]; do
    if [[ $attempt -gt 0 ]]; then
      RERANK_RESULT_RETRY_COUNT=$attempt
      log_warn "LLM 重排序重试 ($attempt/$max_retries)"
    fi

    local response_file
    response_file=$(mktemp)
    if llm_call "$prompt" >"$response_file" 2>&1; then
      exit_code=0
    else
      exit_code=$?
    fi
    response=$(cat "$response_file")
    rm -f "$response_file"

    if [[ $exit_code -eq 124 ]]; then
      last_error="timeout"
      ((attempt++))
      continue
    fi

    if [[ $exit_code -ne 0 ]] || echo "$response" | jq -e '.error' &>/dev/null; then
      last_error=$(echo "$response" | jq -r '.error // "unknown error"' 2>/dev/null || echo "llm_error")
      ((attempt++))
      continue
    fi

    if ! echo "$response" | jq -e '.' &>/dev/null; then
      last_error="invalid_json"
      ((attempt++))
      continue
    fi

    if ! echo "$response" | jq -e 'type == "array"' &>/dev/null; then
      last_error="invalid_format"
      ((attempt++))
      continue
    fi

    local reranked
    reranked=$(_parse_rerank_response "$response" "$candidates_json")

    if [[ $? -eq 0 ]] && [[ -n "$reranked" ]] && [[ "$reranked" != "[]" ]]; then
      RERANK_RESULT_RERANKED=true
      _write_rerank_state
      echo "$reranked"
      return 0
    else
      last_error="parse_error"
      ((attempt++))
      continue
    fi
  done

  RERANK_RESULT_FALLBACK_REASON="${last_error:-max_retries_exhausted}"
  _write_rerank_state
  log_warn "LLM 重排序降级: $RERANK_RESULT_FALLBACK_REASON (retries: $RERANK_RESULT_RETRY_COUNT)"
  echo "$candidates_json"
  return 0
}

# 快速 Mock 输出
fast_mock_context() {
  local keyword_candidates='[
    {"file_path":"src/auth.ts","relevance_score":0.5,"distance":2,"source":"keyword"},
    {"file_path":"src/user.ts","relevance_score":0.4,"distance":3,"source":"keyword"}
  ]'
  local vector_candidates='[
    {"file_path":"src/auth.ts","relevance_score":0.8,"distance":2,"source":"vector"},
    {"file_path":"src/user.ts","relevance_score":0.6,"distance":3,"source":"vector"}
  ]'
  local graph_candidates='[
    {"file_path":"src/graph.ts","relevance_score":0.9,"distance":1,"source":"graph"}
  ]'

  local candidates_json
  if [ "$FUSION_DEPTH" -gt 0 ]; then
    candidates_json=$(rrf_fusion "$keyword_candidates" "$vector_candidates" "$graph_candidates" \
      "$HYBRID_WEIGHT_KEYWORD" "$HYBRID_WEIGHT_VECTOR" "$HYBRID_WEIGHT_GRAPH" "$HYBRID_RRF_K")
  else
    candidates_json="$vector_candidates"
  fi

  local graph_count
  graph_count=$(echo "$graph_candidates" | jq 'length' 2>/dev/null || echo 0)
  local subgraph='{"nodes":[],"edges":[]}'
  local fusion_weights="${HYBRID_WEIGHT_KEYWORD},${HYBRID_WEIGHT_VECTOR},${HYBRID_WEIGHT_GRAPH}"
  printf '{"schema_version":"1.0","source":"graph-rag","token_count":0,"subgraph":%s,"candidates":%s,"metadata":{"ckb_available":true,"ckb_fallback_reason":null,"fusion_depth":%s,"fusion_weights":"%s","graph_depth":%s,"token_count":0,"boundary_filtered":0,"legacy_mode":%s,"reranked":false,"provider":null,"fallback_reason":null,"retry_count":null,"graph_candidates":%s}}\n' \
    "$subgraph" "$candidates_json" "$FUSION_DEPTH" "$fusion_weights" "$MAX_DEPTH" "$LEGACY_MODE" "$graph_count"
}
