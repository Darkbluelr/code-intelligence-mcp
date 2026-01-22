#!/bin/bash
# Graph-RAG 核心配置和工具函数

# ==================== 配置 ====================

# 默认参数
QUERY=""
TOP_K=10
MAX_DEPTH=3
MAX_ALLOWED_DEPTH=5
FUSION_DEPTH=1
TOKEN_BUDGET=8000
MIN_RELEVANCE=0.0
CACHE_TTL=300

# MP5: 混合检索权重 (RRF)
HYBRID_WEIGHT_KEYWORD=0.3
HYBRID_WEIGHT_VECTOR=0.5
HYBRID_WEIGHT_GRAPH=0.2
HYBRID_RRF_K=60
HYBRID_ENABLED=true

# MP4.2 优先级权重配置
PRIORITY_WEIGHT_RELEVANCE=0.4
PRIORITY_WEIGHT_HOTSPOT=0.3
PRIORITY_WEIGHT_DISTANCE=0.3

# 边界检测器路径
BOUNDARY_DETECTOR="${SCRIPT_DIR}/boundary-detector.sh"

# 缓存管理器路径
CACHE_MANAGER="${SCRIPT_DIR}/cache-manager.sh"

# 缓存相关配置
: "${GRAPH_RAG_CACHE_ENABLED:=true}"

# 缓存目录
CACHE_DIR="${TMPDIR:-/tmp}/.devbooks-cache/graph-rag"

# 输出模式
OUTPUT_FORMAT="text"
MOCK_EMBEDDING=false

# LLM 重排序配置
RERANK_ENABLED=false
RERANK_CLI_DISABLED=false
RERANK_MAX_CANDIDATES=10

# 新增标志
LEGACY_MODE=false

# ==================== 配置加载 ====================

# 解析功能开关配置文件路径
_resolve_feature_config() {
  if [[ -n "${FEATURES_CONFIG:-}" && -f "$FEATURES_CONFIG" ]]; then
    echo "$FEATURES_CONFIG"
    return 0
  fi

  if [[ -n "${DEVBOOKS_FEATURE_CONFIG:-}" && -f "$DEVBOOKS_FEATURE_CONFIG" ]]; then
    echo "$DEVBOOKS_FEATURE_CONFIG"
    return 0
  fi

  if [[ -f "$CWD/config/features.yaml" ]]; then
    echo "$CWD/config/features.yaml"
    return 0
  fi

  if [[ -f "$PROJECT_ROOT/config/features.yaml" ]]; then
    echo "$PROJECT_ROOT/config/features.yaml"
    return 0
  fi

  echo ""
}

# 从配置文件加载优先级权重
_load_priority_weights() {
  local config_file
  config_file=$(_resolve_feature_config)

  if [[ -z "$config_file" || ! -f "$config_file" ]]; then
    return 0
  fi

  local in_smart_pruning=false
  local in_priority_weights=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^[[:space:]]*smart_pruning: ]]; then
      in_smart_pruning=true
      continue
    fi

    if [[ ! "$line" =~ ^[[:space:]] ]] && [[ "$in_smart_pruning" == "true" ]]; then
      in_smart_pruning=false
      in_priority_weights=false
      continue
    fi

    if [[ "$in_smart_pruning" == "true" ]]; then
      if [[ "$line" =~ ^[[:space:]]+priority_weights: ]]; then
        in_priority_weights=true
        continue
      fi

      if [[ "$line" =~ ^[[:space:]]{2,4}[a-z] ]] && [[ "$in_priority_weights" == "true" ]] && [[ ! "$line" =~ ^[[:space:]]{4,} ]]; then
        in_priority_weights=false
      fi

      if [[ "$in_priority_weights" == "true" ]]; then
        if [[ "$line" =~ ^[[:space:]]+relevance:[[:space:]]*([0-9.]+) ]]; then
          PRIORITY_WEIGHT_RELEVANCE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+hotspot:[[:space:]]*([0-9.]+) ]]; then
          PRIORITY_WEIGHT_HOTSPOT="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+distance:[[:space:]]*([0-9.]+) ]]; then
          PRIORITY_WEIGHT_DISTANCE="${BASH_REMATCH[1]}"
        fi
      fi
    fi
  done < "$config_file"
}

_load_hybrid_weights() {
  local config_file
  config_file=$(_resolve_feature_config)

  if [[ -z "$config_file" || ! -f "$config_file" ]]; then
    return 0
  fi

  local in_features=false
  local in_hybrid=false
  local in_weights=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^features: ]]; then
      in_features=true
      in_hybrid=false
      in_weights=false
      continue
    fi

    if [[ ! "$line" =~ ^[[:space:]] ]] && [[ "$in_features" == "true" ]]; then
      in_features=false
      in_hybrid=false
      in_weights=false
      continue
    fi

    if [[ "$in_features" == "true" ]]; then
      if [[ "$line" =~ ^[[:space:]]+hybrid_retrieval: ]]; then
        in_hybrid=true
        in_weights=false
        continue
      fi

      if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z_] ]] && [[ "$in_hybrid" == "true" ]] && [[ ! "$line" =~ hybrid_retrieval: ]]; then
        in_hybrid=false
        in_weights=false
      fi
    fi

    if [[ "$in_hybrid" == "true" ]]; then
      if [[ "$line" =~ ^[[:space:]]+enabled:[[:space:]]*([^[:space:]]+) ]]; then
        case "${BASH_REMATCH[1]}" in
          true|True|TRUE|yes|Yes|YES|1) HYBRID_ENABLED=true ;;
          *) HYBRID_ENABLED=false ;;
        esac
      fi

      if [[ "$line" =~ ^[[:space:]]+weights: ]]; then
        in_weights=true
        continue
      fi

      if [[ "$line" =~ ^[[:space:]]{4}[a-zA-Z_] ]] && [[ "$in_weights" == "true" ]] && [[ ! "$line" =~ ^[[:space:]]{6,} ]]; then
        in_weights=false
      fi

      if [[ "$in_weights" == "true" ]]; then
        if [[ "$line" =~ ^[[:space:]]+keyword:[[:space:]]*([0-9.]+) ]]; then
          HYBRID_WEIGHT_KEYWORD="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+vector:[[:space:]]*([0-9.]+) ]]; then
          HYBRID_WEIGHT_VECTOR="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+graph:[[:space:]]*([0-9.]+) ]]; then
          HYBRID_WEIGHT_GRAPH="${BASH_REMATCH[1]}"
        fi
      fi

      if [[ "$line" =~ ^[[:space:]]+rrf_k:[[:space:]]*([0-9]+) ]]; then
        HYBRID_RRF_K="${BASH_REMATCH[1]}"
      fi
    fi
  done < "$config_file"

  if [[ -n "${DEVBOOKS_ENABLE_ALL_FEATURES:-}" ]]; then
    HYBRID_ENABLED=true
  fi
}

# ==================== 缓存机制 ====================

get_cache_key() {
  if declare -f hash_string_md5 &>/dev/null; then
    hash_string_md5 "$1"
  elif command -v md5sum &>/dev/null; then
    printf '%s' "$1" | md5sum 2>/dev/null | cut -d' ' -f1
  elif command -v md5 &>/dev/null; then
    if md5 -q /dev/null >/dev/null 2>&1; then
      printf '%s' "$1" | md5 -q 2>/dev/null
    else
      printf '%s' "$1" | md5 2>/dev/null
    fi
  else
    printf '%s' "$1" | cksum 2>/dev/null | cut -d' ' -f1
  fi
}

resolve_graph_rag_cache_anchor() {
  local root="$1"
  local candidates=(
    "$root/.git/index"
    "$root/.git/HEAD"
    "$root/package.json"
    "$root/README.md"
    "$SCRIPT_DIR/graph-rag.sh"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

get_cached() {
  local cache_key="$1"
  local query_hash
  query_hash=$(get_cache_key "$cache_key")

  if [[ "$GRAPH_RAG_CACHE_ENABLED" == "true" ]] && [[ -x "$CACHE_MANAGER" ]]; then
    local cache_anchor
    cache_anchor=$(resolve_graph_rag_cache_anchor "$CWD") || cache_anchor=""

    local cache_result
    if [[ -n "$cache_anchor" ]]; then
      cache_result=$("$CACHE_MANAGER" --get "$cache_anchor" --query "$query_hash" 2>/dev/null)
    else
      cache_result=""
    fi

    if [[ -n "$cache_result" ]] && echo "$cache_result" | jq -e '.schema_version' &>/dev/null; then
      log_info "缓存命中 (cache-manager, key: ${query_hash:0:8}...)"
      echo "$cache_result"
      return 0
    fi
  fi

  local cache_file="$CACHE_DIR/$query_hash"

  if [ -f "$cache_file" ]; then
    local age
    local mtime
    mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
    age=$(($(date +%s) - ${mtime:-0}))
    if [ "${age:-0}" -lt "${CACHE_TTL:-300}" ]; then
      cat "$cache_file"
      return 0
    fi
  fi
  return 1
}

set_cache() {
  local cache_key="$1"
  local value="$2"
  local query_hash
  query_hash=$(get_cache_key "$cache_key")

  if [[ "$GRAPH_RAG_CACHE_ENABLED" == "true" ]] && [[ -x "$CACHE_MANAGER" ]]; then
    local cache_anchor
    cache_anchor=$(resolve_graph_rag_cache_anchor "$CWD") || cache_anchor=""
    if [[ -n "$cache_anchor" ]]; then
      "$CACHE_MANAGER" --set "$cache_anchor" --query "$query_hash" --value "$value" 2>/dev/null || true
    fi
    return 0
  fi

  mkdir -p "$CACHE_DIR" 2>/dev/null
  echo "$value" > "$CACHE_DIR/$query_hash" 2>/dev/null
}

# ==================== 边界检测 ====================

BOUNDARY_FILTERED_COUNT=0

is_library_code() {
  local file_path="$1"

  if [[ "$file_path" == node_modules/* ]] || \
     [[ "$file_path" == vendor/* ]] || \
     [[ "$file_path" == .git/* ]] || \
     [[ "$file_path" == dist/* ]] || \
     [[ "$file_path" == build/* ]]; then
    return 0
  fi

  if [ -x "$BOUNDARY_DETECTOR" ]; then
    local result
    result=$("$BOUNDARY_DETECTOR" --format json "$file_path" 2>/dev/null) || true

    if [ -n "$result" ]; then
      local boundary_type
      boundary_type=$(echo "$result" | jq -r '.type // "user"' 2>/dev/null)

      case "$boundary_type" in
        library|vendor|generated)
          return 0
          ;;
      esac
    fi
  fi

  return 1
}

filter_library_code() {
  local candidates_json="$1"
  local result='[]'

  local count
  count=$(echo "$candidates_json" | jq 'length' 2>/dev/null || echo 0)

  for ((i=0; i<count; i++)); do
    local candidate
    candidate=$(echo "$candidates_json" | jq ".[$i]")
    local file_path
    file_path=$(echo "$candidate" | jq -r '.file_path')

    if ! is_library_code "$file_path"; then
      result=$(echo "$result" | jq --argjson c "$candidate" '. + [$c]')
    else
      ((BOUNDARY_FILTERED_COUNT++)) || true
    fi
  done

  echo "$result"
}
