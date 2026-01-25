#!/bin/bash
# Graph-RAG 检索模块

# ==================== 向量搜索 ====================

embedding_search() {
  local query="$1"
  local top_k="$2"
  local embedding_tool="${SCRIPT_DIR}/embedding.sh"
  local index_path="$CWD/.devbooks/embeddings/index.tsv"
  local workspace_name="${CI_WORKSPACE:-}"
  if [[ "$workspace_name" == "all" ]]; then
    workspace_name=""
  fi

  local ci_config_helper="${SCRIPT_DIR}/ci-config.sh"
  if [ -f "$ci_config_helper" ]; then
    # shellcheck source=ci-config.sh
    source "$ci_config_helper"
    if declare -f ci_config_get_root &>/dev/null; then
      local config_root
      config_root="$(ci_config_get_root 2>/dev/null || echo "$CWD")"
      local index_dir
      index_dir="$(ci_config_get_global_index_dir 2>/dev/null || true)"
      [[ -z "$index_dir" ]] && index_dir=".ci-index"
      if [[ "$index_dir" != /* ]]; then
        index_dir="${config_root}/${index_dir}"
      fi
      if [[ -z "$workspace_name" ]]; then
        workspace_name="$(ci_config_get_default_workspace_name 2>/dev/null || echo "main")"
      fi
      index_path="${index_dir}/workspaces/${workspace_name}/embeddings/index.tsv"
    fi
  fi

  if [ "$MOCK_EMBEDDING" = true ]; then
    echo '[{"file_path":"src/auth.ts","relevance_score":0.8,"hotspot":0.6,"distance":2},{"file_path":"src/user.ts","relevance_score":0.6,"hotspot":0.4,"distance":3}]'
    return 0
  fi

  if [ ! -f "$index_path" ]; then
    log_warn "Embedding 索引不存在: $index_path（将退化为关键词或内置 provider）"
  fi

  if [ -x "$embedding_tool" ]; then
    local result
    result=$(cd "$CWD" && PROJECT_ROOT="$CWD" CI_WORKSPACE="$workspace_name" CI_CONFIG_FILE="${CI_CONFIG_FILE:-}" "$embedding_tool" search "$query" --top-k "$top_k" --format json 2>/dev/null || echo "")
    if [ -n "$result" ] && echo "$result" | jq -e . >/dev/null 2>&1; then
      # embedding.sh JSON: {candidates:[{file,score,source}], ...}
      echo "$result" | jq -c '
        [.candidates[]? | {file_path: (.file // .file_path // ""), relevance_score: (.score // .relevance_score // 0)} | select(.file_path != "")]
      ' 2>/dev/null
      return 0
    fi
  fi

  keyword_search "$query" "$top_k"
}

# ==================== 关键词搜索 ====================

keyword_search() {
  local query="$1"
  local top_k="$2"

  local keywords
  keywords=$(echo "$query" | tr ' ' '\n' | grep -E '^[a-zA-Z]{3,}$' | head -5)

  if [ -z "$keywords" ]; then
    echo '[]'
    return 0
  fi

  local results=()
  local rg_cmd=""

  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done

  if [ -z "$rg_cmd" ]; then
    echo '[]'
    return 0
  fi

  while IFS= read -r keyword; do
    [ -z "$keyword" ] && continue
    local files
    files=$("$rg_cmd" -l --max-count=5 -t py -t js -t ts -t go \
      "$keyword" "$CWD" 2>/dev/null | head -"$top_k")

    while IFS= read -r file; do
      [ -z "$file" ] && continue
      local rel_path="${file#"$CWD"/}"
      results+=("$rel_path")
    done <<< "$files"
  done <<< "$keywords"

  printf '%s\n' "${results[@]}" | sort -u | head -"$top_k" | \
    jq -R -s 'split("\n") | map(select(length > 0)) | to_entries | map({file_path: .value, relevance_score: (1 - .key * 0.1)})'
}

# ==================== Import 分析图遍历 ====================

# 使用 import 解析进行图遍历
import_graph_traverse() {
  local file_path="$1"
  local _max_depth="$2"

  local imports
  local full_path="$CWD/$file_path"

  if [ ! -f "$full_path" ]; then
    echo '[]'
    return 0
  fi

  imports=$(grep -E "^import|^from .* import" "$full_path" 2>/dev/null | head -10)

  local graph_results='[]'

  while IFS= read -r import_line; do
    [ -z "$import_line" ] && continue

    local imported
    imported=$(echo "$import_line" | grep -oE "'[^']+'" | tr -d "'" | head -1)
    [ -z "$imported" ] && imported=$(echo "$import_line" | grep -oE '"[^"]+"' | tr -d '"' | head -1)

    if [ -n "$imported" ]; then
      if [[ "$imported" == ./* ]] || [[ "$imported" == ../* ]]; then
        local import_path="${imported%.ts}.ts"
        graph_results=$(echo "$graph_results" | jq --arg path "$import_path" '. + [{file_path: $path, depth: 1, source: "import"}]')
      fi
    fi
  done <<< "$imports"

  echo "$graph_results"
}

# 使用 import 解析扩展候选
_expand_with_import_analysis() {
  local anchors="$1"
  local max_depth="$2"

  local all_candidates="$anchors"
  local visited='[]'

  local anchor_count
  anchor_count=$(echo "$anchors" | jq 'length' 2>/dev/null || echo "0")

  for ((i=0; i<anchor_count && i<5; i++)); do
    local anchor
    anchor=$(echo "$anchors" | jq ".[$i]")
    local file_path
    file_path=$(echo "$anchor" | jq -r '.file_path')

    if echo "$visited" | jq -e --arg p "$file_path" 'index($p)' >/dev/null 2>&1; then
      continue
    fi

    visited=$(echo "$visited" | jq --arg p "$file_path" '. + [$p]')

    anchor=$(echo "$anchor" | jq '.source = "import"')
    all_candidates=$(echo "$all_candidates" | jq --argjson a "$anchor" \
      'map(if .file_path == ($a.file_path) then . + {source: "import"} else . end)')

    if [ "$max_depth" -gt 0 ]; then
      local graph_nodes
      graph_nodes=$(import_graph_traverse "$file_path" "$max_depth")

      if [ -n "$graph_nodes" ] && [ "$graph_nodes" != "[]" ]; then
        graph_nodes=$(echo "$graph_nodes" | jq '[.[] | . + {source: "import"}]')
        all_candidates=$(echo "$all_candidates" "$graph_nodes" | jq -s 'add | unique_by(.file_path)')
      fi
    fi
  done

  all_candidates=$(echo "$all_candidates" | jq '[.[] | . + {source: (.source // "import")}]')

  echo "$all_candidates"
}
