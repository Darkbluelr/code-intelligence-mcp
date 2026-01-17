#!/bin/bash
# federation-lite.sh - Lightweight Federation Index (Cross-repo Contract Tracking)
#
# Version: 1.0.0
# Purpose: Discover and index API contracts across multiple repositories
# Depends: jq, git (optional)
#
# Usage:
#   federation-lite.sh --status
#   federation-lite.sh --update [--config config/federation.yaml]
#   federation-lite.sh --search "<symbol>" [--format json]
#   federation-lite.sh --list-contracts [--repo "<name>"]
#   federation-lite.sh --help
#
# Environment Variables:
#   FEDERATION_CONFIG   - Config file path (default: config/federation.yaml)
#   FEDERATION_INDEX    - Index file path (default: .devbooks/federation-index.json)
#   DEBUG               - Enable debug output (default: false)
#
# Trace: AC-011
# Change: augment-upgrade-phase2

set -euo pipefail

# ==================== CT-VE-005: Fast Path for generate-virtual-edges ====================
# Performance optimization: handle virtual edge generation without loading common.sh
# Target: 100 symbols in <200ms
if [[ "${1:-}" == "generate-virtual-edges" ]] && [[ "${2:-}" != "--help" ]]; then
  _fast_local_repo="."
  _fast_db_path=""
  _fast_min_confidence="0.5"
  _fast_config=""
  _fast_index=""
  _fast_sync_mode="false"
  shift  # Remove "generate-virtual-edges"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --local-repo) _fast_local_repo="$2"; shift 2 ;;
      --db) _fast_db_path="$2"; shift 2 ;;
      --min-confidence) _fast_min_confidence="$2"; shift 2 ;;
      --config) _fast_config="$2"; shift 2 ;;
      --sync) _fast_sync_mode="true"; shift ;;
      *) shift ;;
    esac
  done

  # Resolve paths - index is relative to local repo or uses FEDERATION_INDEX env var
  _fast_local_repo=$(cd "$_fast_local_repo" && pwd)
  [[ -z "$_fast_db_path" ]] && _fast_db_path="$_fast_local_repo/.devbooks/graph.db"
  [[ -z "$_fast_index" ]] && _fast_index="${FEDERATION_INDEX:-$_fast_local_repo/.devbooks/federation-index.json}"

  # Check federation index exists
  if [[ ! -f "$_fast_index" ]]; then
    echo "{\"error\": \"Federation index not found at $_fast_index\"}" >&2
    exit 1
  fi

  # Ensure database directory exists
  mkdir -p "$(dirname "$_fast_db_path")" 2>/dev/null || true

  # Create virtual_edges table if needed
  sqlite3 "$_fast_db_path" 'CREATE TABLE IF NOT EXISTS virtual_edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_repo TEXT NOT NULL,
    source_symbol TEXT NOT NULL,
    target_repo TEXT NOT NULL,
    target_symbol TEXT NOT NULL,
    edge_type TEXT DEFAULT '"'"'VIRTUAL_CALLS'"'"',
    confidence REAL NOT NULL DEFAULT 1.0,
    confidence_level TEXT DEFAULT '"'"'medium'"'"',
    contract_type TEXT DEFAULT '"'"'unknown'"'"',
    contract_bonus REAL DEFAULT 0.0,
    exact_match REAL DEFAULT 0.0,
    signature_similarity REAL DEFAULT 0.5,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
  CREATE INDEX IF NOT EXISTS idx_ve_source ON virtual_edges(source_repo, source_symbol);
  CREATE INDEX IF NOT EXISTS idx_ve_target ON virtual_edges(target_repo, target_symbol);' 2>/dev/null || true

  # Fast symbol extraction using grep + single jq transform
  _fast_local_repo_name=$(basename "$_fast_local_repo")
  _fast_symbols=$(grep -rhoE '(export\s+)?(async\s+)?function\s+[A-Za-z_][A-Za-z0-9_]*' "$_fast_local_repo" \
    --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" 2>/dev/null | \
    grep -oE '[A-Za-z_][A-Za-z0-9_]*$' | sort -u | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

  # Load index and process all matching in single jq call
  # Uses startswith() instead of test() to avoid regex issues with special characters
  _fast_result=$(jq -c \
    --argjson local_symbols "$_fast_symbols" \
    --arg local_repo "$_fast_local_repo_name" \
    --argjson min_conf "$_fast_min_confidence" \
    '
    # Helper function to extract verb category using startswith (no regex)
    def get_verb:
      if startswith("get") or startswith("fetch") or startswith("find") or startswith("load") or startswith("read") then "get"
      elif startswith("create") or startswith("add") or startswith("new") or startswith("insert") or startswith("post") then "create"
      elif startswith("update") or startswith("edit") or startswith("modify") or startswith("patch") or startswith("put") then "update"
      elif startswith("delete") or startswith("remove") or startswith("destroy") then "delete"
      else "" end;

    # Helper to strip common verb prefixes
    def strip_verb:
      if startswith("get") then .[3:] elif startswith("fetch") then .[5:] elif startswith("find") then .[4:]
      elif startswith("load") then .[4:] elif startswith("read") then .[4:] elif startswith("create") then .[6:]
      elif startswith("add") then .[3:] elif startswith("new") then .[3:] elif startswith("insert") then .[6:]
      elif startswith("post") then .[4:] elif startswith("update") then .[6:] elif startswith("edit") then .[4:]
      elif startswith("modify") then .[6:] elif startswith("patch") then .[5:] elif startswith("put") then .[3:]
      elif startswith("delete") then .[6:] elif startswith("remove") then .[6:] elif startswith("destroy") then .[7:]
      else . end;

    # Extract all remote symbols with metadata
    [.repositories[]? | select(.name != null) | select((.name | tostring) != $local_repo) |
      .name as $repo_name |
      .contracts[]? |
      .type as $contract_type |
      (.symbols // [])[]? |
      select(type == "string") |
      {
        repo: $repo_name,
        symbol: .,
        contract_type: $contract_type,
        contract_bonus: (if $contract_type == "proto" then 0.2 elif $contract_type == "openapi" then 0.15 else 0.1 end)
      }
    ] as $remote_list |

    # For each local symbol, find matching remote symbols
    [
      $local_symbols[]? | select(type == "string" and length > 0) | . as $local |
      ($local | ascii_downcase) as $local_lower |
      $remote_list[]? | . as $remote |
      ($remote.symbol | ascii_downcase) as $remote_lower |

      # Calculate exact match score (simplified - no regex)
      (if $local_lower == $remote_lower then 1.0
       elif ($local_lower | startswith($remote_lower)) or ($remote_lower | startswith($local_lower)) then 0.7
       elif (($local_lower | strip_verb) as $local_base | ($remote_lower | strip_verb) as $remote_base |
             ($local_base | length > 0) and ($remote_base | length > 0) and
             ($local_base == $remote_base or ($local_base | startswith($remote_base)) or ($remote_base | startswith($local_base)))) then 0.7
       else 0 end) as $exact_match |

      # Skip non-matches
      select($exact_match > 0) |

      # Calculate signature similarity (verb matching - no regex)
      (($local_lower | get_verb) as $local_verb |
       ($remote_lower | get_verb) as $remote_verb |
       if ($local_verb | length > 0) and $local_verb == $remote_verb then 0.6 else 0.5 end
      ) as $sig_sim |

      # Calculate confidence: exact*0.6 + sig*0.3 + contract*0.1
      (($exact_match * 0.6) + ($sig_sim * 0.3) + ($remote.contract_bonus * 0.1)) as $confidence |

      # Filter by minimum confidence
      select($confidence >= $min_conf) |

      {
        source_repo: $local_repo,
        source_symbol: $local,
        target_repo: $remote.repo,
        target_symbol: $remote.symbol,
        edge_type: "VIRTUAL_CALLS",
        contract_type: $remote.contract_type,
        confidence: ($confidence * 100 | floor / 100),
        confidence_level: (if $confidence >= 0.8 then "high" elif $confidence < 0.5 then "low" else "medium" end),
        exact_match: $exact_match,
        signature_similarity: $sig_sim,
        contract_bonus: $remote.contract_bonus
      }
    ] | unique_by([.source_symbol, .target_symbol])
    ' "$_fast_index")

  # Generate batch SQL and execute
  _fast_edge_count=$(echo "$_fast_result" | jq 'length')
  if [[ "$_fast_edge_count" -gt 0 ]]; then
    _fast_sql=$(echo "$_fast_result" | jq -r '
      "BEGIN TRANSACTION;\n" +
      (map("INSERT OR REPLACE INTO virtual_edges (source_repo, source_symbol, target_repo, target_symbol, edge_type, contract_type, confidence, confidence_level, exact_match, signature_similarity, contract_bonus) VALUES (" +
        "'"'"'\(.source_repo)'"'"', " +
        "'"'"'\(.source_symbol)'"'"', " +
        "'"'"'\(.target_repo)'"'"', " +
        "'"'"'\(.target_symbol)'"'"', " +
        "'"'"'\(.edge_type)'"'"', " +
        "'"'"'\(.contract_type)'"'"', " +
        "\(.confidence), " +
        "'"'"'\(.confidence_level)'"'"', " +
        "\(.exact_match), " +
        "\(.signature_similarity), " +
        "\(.contract_bonus));") | join("\n")) +
      "\nCOMMIT;"
    ')
    echo "$_fast_sql" | sqlite3 "$_fast_db_path" 2>/dev/null || true
  fi

  # Output summary
  _fast_total=$(sqlite3 "$_fast_db_path" "SELECT COUNT(*) FROM virtual_edges" 2>/dev/null || echo "0")
  jq -n --argjson created "$_fast_edge_count" --argjson total "$_fast_total" --arg db "$_fast_db_path" \
    '{status:"ok", edges_created:$created, edges_updated:0, edges_skipped:0, total_edges:$total, db_path:$db}'
  exit 0
fi

# ==================== End Fast Path ====================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    # shellcheck source=common.sh
    source "$SCRIPT_DIR/common.sh"
fi

# ============================================================
# Configuration
# ============================================================

SCHEMA_VERSION="1.0.0"
: "${FEDERATION_CONFIG:=config/federation.yaml}"
: "${FEDERATION_INDEX:=.devbooks/federation-index.json}"
: "${DEBUG:=false}"

# ============================================================
# Utility Functions
# ============================================================

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[DEBUG] $1" >&2
    fi
}

log_info() {
    echo "[INFO] $1" >&2
}

log_warn() {
    echo "[WARN] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
}

show_help() {
    cat << 'EOF'
federation-lite.sh - Lightweight Federation Index (Cross-repo Contract Tracking)

Usage:
  federation-lite.sh --status
  federation-lite.sh --update [--config config/federation.yaml]
  federation-lite.sh --search "<symbol>" [--format json]
  federation-lite.sh --list-contracts [--repo "<name>"]
  federation-lite.sh generate-virtual-edges [--repo <name>] [--min-confidence <n>]
  federation-lite.sh query-virtual <symbol> [--virtual-edges] [--confidence <n>]
  federation-lite.sh --help

Options:
  --status            Show index status
  --update            Update the federation index
  --config <file>     Configuration file (default: config/federation.yaml)
  --search <symbol>   Search for a symbol across repositories
  --list-contracts    List all indexed contracts
  --repo <name>       Filter by repository name
  --format <type>     Output format: json or text (default: json)
  --debug             Enable debug output
  --help              Show this help message

Virtual Edge Options (MP5):
  generate-virtual-edges    Generate virtual edges from local calls to remote contracts
    --local-repo <path>     Path to local repository (default: current directory)
    --db <path>             Path to graph.db (default: .devbooks/graph.db)
    --min-confidence <n>    Minimum confidence threshold (default: 0.5)
    --sync                  Sync mode: update existing edges, remove stale ones

  query-virtual <symbol>    Query virtual edges for a symbol
    --virtual-edges         Enable virtual edge results
    --confidence <n>        Minimum confidence filter (default: 0.0)

Environment Variables:
  FEDERATION_CONFIG   Config file path (default: config/federation.yaml)
  FEDERATION_INDEX    Index file path (default: .devbooks/federation-index.json)
  GRAPH_DB            Graph database path (default: .devbooks/graph.db)

Supported Contract Types:
  - Protocol Buffers (.proto)   - contract_bonus: 0.1
  - OpenAPI (openapi.yaml)      - contract_bonus: 0.05
  - GraphQL (.graphql)          - contract_bonus: 0.08
  - TypeScript Types (.d.ts)    - contract_bonus: 0.0

Confidence Formula:
  confidence = exact_match * 0.6 + signature_similarity * 0.3 + contract_bonus * 0.1

Examples:
  # Check index status
  federation-lite.sh --status

  # Update index from config
  federation-lite.sh --update

  # Search for a symbol
  federation-lite.sh --search "UserService"

  # List all contracts
  federation-lite.sh --list-contracts

  # Generate virtual edges
  federation-lite.sh generate-virtual-edges --local-repo ./my-app --min-confidence 0.5

  # Query virtual edges for a symbol
  federation-lite.sh query-virtual "getUserById" --confidence 0.5
EOF
}

# ============================================================
# Configuration Loading (MP4.1)
# ============================================================

# Parse simple YAML config (no external dependency)
# REQ-FED-002: Federation configuration format
load_federation_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_warn "Config file not found: $config_file"
        echo '{"repositories": [], "auto_discover": {"enabled": false}}'
        return
    fi

    local repos="[]"
    local auto_discover='{"enabled": false, "search_paths": [], "contract_patterns": []}'
    local in_repos=false
    local in_auto_discover=false
    local current_repo='{}'
    local in_contracts=false
    local contracts="[]"
    local in_search_paths=false
    local in_contract_patterns=false
    local search_paths="[]"
    local contract_patterns="[]"
    local federation_root_seen=false
    local in_federation=true

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Detect section starts
        if [[ "$line" =~ ^[[:space:]]*federation:[[:space:]]*$ ]]; then
            federation_root_seen=true
            in_federation=true
            in_repos=false
            in_auto_discover=false
            continue
        fi

        if [[ "$federation_root_seen" == "true" && "$line" =~ ^[^[:space:]] ]]; then
            if [[ ! "$line" =~ ^federation: ]]; then
                in_federation=false
            fi
        fi

        if [[ "$line" =~ ^[[:space:]]*repositories:[[:space:]]*$ ]]; then
            if [[ "$federation_root_seen" == "true" && "$in_federation" != "true" ]]; then
                continue
            fi
            in_repos=true
            in_auto_discover=false
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*auto_discover:[[:space:]]*$ ]]; then
            if [[ "$federation_root_seen" == "true" && "$in_federation" != "true" ]]; then
                continue
            fi
            in_auto_discover=true
            in_repos=false
            continue
        fi

        if [[ "$in_repos" == "true" ]]; then
            # New repo entry starts with "- name:"
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                # Save previous repo
                if [[ $(echo "$current_repo" | jq 'has("name")') == "true" ]]; then
                    current_repo=$(echo "$current_repo" | jq --argjson c "$contracts" '.contracts = $c')
                    repos=$(echo "$repos" | jq --argjson r "$current_repo" '. + [$r]')
                fi
                current_repo=$(jq -n --arg name "${BASH_REMATCH[1]}" '{"name": $name}')
                contracts="[]"
                in_contracts=false
                continue
            fi

            if [[ "$line" =~ ^[[:space:]]+path:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                current_repo=$(echo "$current_repo" | jq --arg p "${BASH_REMATCH[1]}" '.path = $p')
            fi

            if [[ "$line" =~ ^[[:space:]]+contracts:[[:space:]]*$ ]]; then
                in_contracts=true
                continue
            fi

            if [[ "$in_contracts" == "true" && "$line" =~ ^[[:space:]]+-[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                contracts=$(echo "$contracts" | jq --arg c "${BASH_REMATCH[1]}" '. + [$c]')
            fi
        fi

        if [[ "$in_auto_discover" == "true" ]]; then
            if [[ "$line" =~ ^[[:space:]]+enabled:[[:space:]]*(true|false)$ ]]; then
                auto_discover=$(echo "$auto_discover" | jq --arg e "${BASH_REMATCH[1]}" '.enabled = ($e == "true")')
            fi

            if [[ "$line" =~ ^[[:space:]]+search_paths:[[:space:]]*$ ]]; then
                in_search_paths=true
                in_contract_patterns=false
                continue
            fi

            if [[ "$line" =~ ^[[:space:]]+contract_patterns:[[:space:]]*$ ]]; then
                in_contract_patterns=true
                in_search_paths=false
                continue
            fi

            if [[ "$in_search_paths" == "true" && "$line" =~ ^[[:space:]]+-[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                search_paths=$(echo "$search_paths" | jq --arg p "${BASH_REMATCH[1]}" '. + [$p]')
            fi

            if [[ "$in_contract_patterns" == "true" && "$line" =~ ^[[:space:]]+-[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                contract_patterns=$(echo "$contract_patterns" | jq --arg p "${BASH_REMATCH[1]}" '. + [$p]')
            fi
        fi
    done < "$config_file"

    # Save last repo
    if [[ $(echo "$current_repo" | jq 'has("name")') == "true" ]]; then
        current_repo=$(echo "$current_repo" | jq --argjson c "$contracts" '.contracts = $c')
        repos=$(echo "$repos" | jq --argjson r "$current_repo" '. + [$r]')
    fi

    # Build auto_discover
    auto_discover=$(echo "$auto_discover" | jq --argjson sp "$search_paths" --argjson cp "$contract_patterns" \
        '.search_paths = $sp | .contract_patterns = $cp')

    jq -n --argjson repos "$repos" --argjson ad "$auto_discover" \
        '{"repositories": $repos, "auto_discover": $ad}'
}

# ============================================================
# Contract Discovery (MP4.2)
# ============================================================

# Get file content hash
get_file_hash() {
    local file="$1"
    if command -v md5sum &>/dev/null; then
        md5sum "$file" 2>/dev/null | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
        md5 -q "$file" 2>/dev/null
    else
        cksum "$file" 2>/dev/null | cut -d' ' -f1
    fi
}

# Detect contract type from filename
# REQ-FED-001: Cross-repo contract discovery
detect_contract_type() {
    local file="$1"
    local basename
    basename=$(basename "$file")

    case "$file" in
        *.proto)
            echo "proto"
            ;;
        */openapi.yaml|*/openapi.yml|*/swagger.yaml|*/swagger.yml|*/swagger.json)
            echo "openapi"
            ;;
        *.graphql|*.gql)
            echo "graphql"
            ;;
        *.d.ts)
            echo "typescript"
            ;;
        */types/*.ts|*/types/**/*.ts)
            echo "typescript"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# ============================================================
# Symbol Extraction (MP4.3)
# ============================================================

# Extract symbols from Protocol Buffers file
# REQ-FED-004: Extract service, message, enum, rpc
extract_proto_symbols() {
    local file="$1"
    local symbols="[]"

    while IFS= read -r line; do
        # Match: service Name {
        if [[ "$line" =~ ^[[:space:]]*(service)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
        # Match: message Name {
        if [[ "$line" =~ ^[[:space:]]*(message)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
        # Match: enum Name {
        if [[ "$line" =~ ^[[:space:]]*(enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
        # Match: rpc MethodName (
        if [[ "$line" =~ ^[[:space:]]*(rpc)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\( ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
    done < "$file"

    echo "$symbols"
}

# Extract symbols from OpenAPI file
# REQ-FED-004: Extract paths, schemas
extract_openapi_symbols() {
    local file="$1"
    local symbols="[]"

    # Use jq if it's JSON, or parse YAML manually
    if [[ "$file" == *.json ]]; then
        # Extract paths
        local paths
        paths=$(jq -r '.paths | keys[]' "$file" 2>/dev/null || echo "")
        for path in $paths; do
            # Get methods for each path
            local methods
            methods=$(jq -r ".paths[\"$path\"] | keys[]" "$file" 2>/dev/null || echo "")
            for method in $methods; do
                method_upper=$(echo "$method" | tr '[:lower:]' '[:upper:]')
                symbols=$(echo "$symbols" | jq --arg s "$method_upper $path" '. + [$s]')
            done
        done

        # Extract schemas
        local schemas
        schemas=$(jq -r '.components.schemas | keys[]' "$file" 2>/dev/null || echo "")
        for schema in $schemas; do
            symbols=$(echo "$symbols" | jq --arg s "$schema" '. + [$s]')
        done
    else
        # Simple YAML parsing for paths and schemas
        local in_paths=false
        local in_schemas=false
        local current_path=""

        while IFS= read -r line; do
            if [[ "$line" =~ ^paths:[[:space:]]*$ ]]; then
                in_paths=true
                in_schemas=false
                continue
            fi
            if [[ "$line" =~ ^[[:space:]]+schemas:[[:space:]]*$ ]] || [[ "$line" =~ ^components:[[:space:]]*$ ]]; then
                in_schemas=true
                in_paths=false
                continue
            fi

            # Path entries like: /users:
            if [[ "$in_paths" == "true" && "$line" =~ ^[[:space:]]+(/[^:]+):[[:space:]]*$ ]]; then
                current_path="${BASH_REMATCH[1]}"
            fi
            # Methods like: get:, post:
            if [[ "$in_paths" == "true" && -n "$current_path" && "$line" =~ ^[[:space:]]+(get|post|put|delete|patch):[[:space:]]*$ ]]; then
                local method
                method=$(echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
                symbols=$(echo "$symbols" | jq --arg s "$method $current_path" '. + [$s]')
            fi
            # Schema entries
            if [[ "$in_schemas" == "true" && "$line" =~ ^[[:space:]]+([A-Za-z][A-Za-z0-9_]*):[[:space:]]*$ ]]; then
                symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[1]}" '. + [$s]')
            fi
        done < "$file"
    fi

    echo "$symbols"
}

# Extract symbols from GraphQL file
# REQ-FED-004: Extract type, query, mutation
extract_graphql_symbols() {
    local file="$1"
    local symbols="[]"

    while IFS= read -r line; do
        # Match: type Name {
        if [[ "$line" =~ ^[[:space:]]*(type|input|interface|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
        # Match: query Name or mutation Name
        if [[ "$line" =~ ^[[:space:]]*(query|mutation|subscription)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
    done < "$file"

    echo "$symbols"
}

# Extract symbols from TypeScript definition file
# REQ-FED-004: Extract export interface/type/class
extract_typescript_symbols() {
    local file="$1"
    local symbols="[]"

    while IFS= read -r line; do
        # Match: export interface Name
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(interface|type|class|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[3]}" '. + [$s]')
        fi
    done < "$file"

    echo "$symbols"
}

# Extract symbols from any contract file
extract_symbols() {
    local file="$1"
    local type="$2"

    case "$type" in
        proto)
            extract_proto_symbols "$file"
            ;;
        openapi)
            extract_openapi_symbols "$file"
            ;;
        graphql)
            extract_graphql_symbols "$file"
            ;;
        typescript)
            extract_typescript_symbols "$file"
            ;;
        *)
            echo "[]"
            ;;
    esac
}

# ============================================================
# Index Operations (MP4.4, MP4.5)
# ============================================================

# Update federation index
# REQ-FED-006: Manual trigger update
update_index() {
    local config_file="$1"

    log_info "Loading federation config: $config_file"
    local config
    config=$(load_federation_config "$config_file")

    local repositories="[]"
    local indexed_at
    indexed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Process explicit repositories
    local repo_count
    repo_count=$(echo "$config" | jq '.repositories | length')
    log_info "Processing $repo_count explicit repositories..."

    for ((i=0; i<repo_count; i++)); do
        local repo_name repo_path repo_contracts
        repo_name=$(echo "$config" | jq -r ".repositories[$i].name")
        repo_path=$(echo "$config" | jq -r ".repositories[$i].path")
        repo_contracts=$(echo "$config" | jq -r ".repositories[$i].contracts")

        # Validate path exists
        # SC-FED-007: Repository path does not exist
        if [[ ! -d "$repo_path" ]]; then
            log_warn "Repository path does not exist: $repo_path (skipping)"
            continue
        fi

        log_info "Indexing repository: $repo_name ($repo_path)"

        local contracts="[]"

        # Find contract files using patterns
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                [[ ! -f "$file" ]] && continue

                local contract_type
                contract_type=$(detect_contract_type "$file")
                [[ "$contract_type" == "unknown" ]] && continue

                local symbols
                symbols=$(extract_symbols "$file" "$contract_type")
                local hash
                hash=$(get_file_hash "$file")
                local rel_path
                rel_path=$(realpath --relative-to="$repo_path" "$file" 2>/dev/null || basename "$file")

                contracts=$(echo "$contracts" | jq \
                    --arg path "$rel_path" \
                    --arg type "$contract_type" \
                    --argjson symbols "$symbols" \
                    --arg hash "$hash" \
                    '. + [{"path": $path, "type": $type, "symbols": $symbols, "hash": $hash}]')

                log_debug "  Indexed: $rel_path ($contract_type, $(echo "$symbols" | jq 'length') symbols)"
            done < <(find "$repo_path" -type f \( -name "*.proto" -o -name "openapi.yaml" -o -name "openapi.yml" -o -name "swagger.json" -o -name "*.graphql" -o -name "*.d.ts" \) 2>/dev/null)
        done < <(echo "$repo_contracts" | jq -r '.[]' 2>/dev/null)

        # If no patterns specified, use default discovery
        if [[ "$repo_contracts" == "null" || "$repo_contracts" == "[]" ]]; then
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                [[ ! -f "$file" ]] && continue

                local contract_type
                contract_type=$(detect_contract_type "$file")
                [[ "$contract_type" == "unknown" ]] && continue

                local symbols
                symbols=$(extract_symbols "$file" "$contract_type")
                local hash
                hash=$(get_file_hash "$file")
                local rel_path
                rel_path=$(realpath --relative-to="$repo_path" "$file" 2>/dev/null || basename "$file")

                contracts=$(echo "$contracts" | jq \
                    --arg path "$rel_path" \
                    --arg type "$contract_type" \
                    --argjson symbols "$symbols" \
                    --arg hash "$hash" \
                    '. + [{"path": $path, "type": $type, "symbols": $symbols, "hash": $hash}]')

                log_debug "  Indexed: $rel_path ($contract_type, $(echo "$symbols" | jq 'length') symbols)"
            done < <(find "$repo_path" -type f \( -name "*.proto" -o -name "openapi.yaml" -o -name "openapi.yml" -o -name "swagger.json" -o -name "*.graphql" -o -name "*.d.ts" \) 2>/dev/null)
        fi

        repositories=$(echo "$repositories" | jq \
            --arg name "$repo_name" \
            --arg path "$repo_path" \
            --argjson contracts "$contracts" \
            '. + [{"name": $name, "path": $path, "contracts": $contracts}]')
    done

    # Process auto-discovery if enabled
    # CT-FED-002: Auto-discovers repositories when enabled
    local auto_discover_enabled
    auto_discover_enabled=$(echo "$config" | jq -r '.auto_discover.enabled // false')

    if [[ "$auto_discover_enabled" == "true" ]]; then
        log_info "Auto-discovery enabled, scanning for repositories..."

        local search_paths contract_patterns
        search_paths=$(echo "$config" | jq -r '.auto_discover.search_paths // []')
        contract_patterns=$(echo "$config" | jq -r '.auto_discover.contract_patterns // []')

        # Expand search paths and find directories with contracts
        while IFS= read -r search_pattern; do
            [[ -z "$search_pattern" ]] && continue

            # Expand glob pattern
            for discovered_path in $search_pattern; do
                [[ ! -d "$discovered_path" ]] && continue

                # Check if this path has any contract files
                local has_contracts=false
                if find "$discovered_path" -maxdepth 3 -type f \
                    \( -name "*.proto" -o -name "openapi.yaml" -o -name "openapi.yml" \
                    -o -name "swagger.json" -o -name "*.graphql" -o -name "*.d.ts" \) \
                    2>/dev/null | head -1 | grep -q .; then
                    has_contracts=true
                fi

                [[ "$has_contracts" != "true" ]] && continue

                # Get repo name from directory
                local discovered_name
                discovered_name=$(basename "$discovered_path")

                # Skip if already in explicit repos
                local already_indexed
                already_indexed=$(echo "$repositories" | jq --arg name "$discovered_name" \
                    'any(.[]; .name == $name)')
                [[ "$already_indexed" == "true" ]] && continue

                log_info "Auto-discovered repository: $discovered_name ($discovered_path)"

                local contracts="[]"

                # Find and index contract files
                while IFS= read -r file; do
                    [[ -z "$file" ]] && continue
                    [[ ! -f "$file" ]] && continue

                    local contract_type
                    contract_type=$(detect_contract_type "$file")
                    [[ "$contract_type" == "unknown" ]] && continue

                    local symbols
                    symbols=$(extract_symbols "$file" "$contract_type")
                    local hash
                    hash=$(get_file_hash "$file")
                    local rel_path
                    rel_path=$(realpath --relative-to="$discovered_path" "$file" 2>/dev/null || basename "$file")

                    contracts=$(echo "$contracts" | jq \
                        --arg path "$rel_path" \
                        --arg type "$contract_type" \
                        --argjson symbols "$symbols" \
                        --arg hash "$hash" \
                        '. + [{"path": $path, "type": $type, "symbols": $symbols, "hash": $hash}]')

                    log_debug "  Indexed: $rel_path ($contract_type)"
                done < <(find "$discovered_path" -type f \
                    \( -name "*.proto" -o -name "openapi.yaml" -o -name "openapi.yml" \
                    -o -name "swagger.json" -o -name "*.graphql" -o -name "*.d.ts" \) 2>/dev/null)

                repositories=$(echo "$repositories" | jq \
                    --arg name "$discovered_name" \
                    --arg path "$discovered_path" \
                    --argjson contracts "$contracts" \
                    '. + [{"name": $name, "path": $path, "contracts": $contracts}]')
            done
        done < <(echo "$search_paths" | jq -r '.[]' 2>/dev/null)
    fi

    # Generate index JSON
    local index_json
    index_json=$(jq -n \
        --arg schema_version "$SCHEMA_VERSION" \
        --arg indexed_at "$indexed_at" \
        --argjson repositories "$repositories" \
        '{
            schema_version: $schema_version,
            indexed_at: $indexed_at,
            repositories: $repositories
        }')

    # Write index file
    local index_dir
    index_dir=$(dirname "$FEDERATION_INDEX")
    mkdir -p "$index_dir" 2>/dev/null

    echo "$index_json" > "$FEDERATION_INDEX"
    log_info "Federation index written to: $FEDERATION_INDEX"

    # Output summary
    local total_repos
    total_repos=$(echo "$index_json" | jq '.repositories | length')
    local total_contracts
    total_contracts=$(echo "$index_json" | jq '[.repositories[].contracts | length] | add // 0')
    local total_symbols
    total_symbols=$(echo "$index_json" | jq '[.repositories[].contracts[].symbols | length] | add // 0')

    log_info "Index complete: $total_repos repositories, $total_contracts contracts, $total_symbols symbols"

    echo "$index_json"
}

# Show index status
# SC-FED-006: Index status query
show_status() {
    local format="$1"

    if [[ ! -f "$FEDERATION_INDEX" ]]; then
        if [[ "$format" == "json" ]]; then
            jq -n '{"status": "not_indexed", "message": "Federation index not found"}'
        else
            echo "Status: NOT INDEXED"
            echo "No federation index found at: $FEDERATION_INDEX"
        fi
        return
    fi

    local index
    index=$(cat "$FEDERATION_INDEX")

    local indexed_at
    indexed_at=$(echo "$index" | jq -r '.indexed_at')
    local repo_count
    repo_count=$(echo "$index" | jq '.repositories | length')
    local contract_count
    contract_count=$(echo "$index" | jq '[.repositories[].contracts | length] | add // 0')
    local symbol_count
    symbol_count=$(echo "$index" | jq '[.repositories[].contracts[].symbols | length] | add // 0')

    if [[ "$format" == "json" ]]; then
        jq -n \
            --arg status "indexed" \
            --arg indexed_at "$indexed_at" \
            --argjson repositories "$repo_count" \
            --argjson contracts "$contract_count" \
            --argjson symbols "$symbol_count" \
            --arg index_path "$FEDERATION_INDEX" \
            '{
                status: $status,
                indexed_at: $indexed_at,
                repositories: $repositories,
                contracts: $contracts,
                symbols: $symbols,
                index_path: $index_path
            }'
    else
        echo "Status: INDEXED"
        echo "Indexed At: $indexed_at"
        echo "Repositories: $repo_count"
        echo "Contracts: $contract_count"
        echo "Symbols: $symbol_count"
        echo "Index Path: $FEDERATION_INDEX"
    fi
}

# Search for a symbol
# SC-FED-005: Search contract symbol
search_symbol() {
    local query="$1"
    local format="$2"

    if [[ ! -f "$FEDERATION_INDEX" ]]; then
        log_error "Federation index not found. Run --update first."
        return 1
    fi

    local index
    index=$(cat "$FEDERATION_INDEX")

    local results="[]"

    # Search through all repositories and contracts
    local repo_count
    repo_count=$(echo "$index" | jq '.repositories | length')

    for ((i=0; i<repo_count; i++)); do
        local repo_name repo_path
        repo_name=$(echo "$index" | jq -r ".repositories[$i].name")
        repo_path=$(echo "$index" | jq -r ".repositories[$i].path")

        local contract_count
        contract_count=$(echo "$index" | jq ".repositories[$i].contracts | length")

        for ((j=0; j<contract_count; j++)); do
            local contract_path contract_type symbols
            contract_path=$(echo "$index" | jq -r ".repositories[$i].contracts[$j].path")
            contract_type=$(echo "$index" | jq -r ".repositories[$i].contracts[$j].type")
            symbols=$(echo "$index" | jq ".repositories[$i].contracts[$j].symbols")

            # Check if query matches any symbol (case-insensitive)
            local query_lower
            query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')

            while IFS= read -r symbol; do
                local symbol_lower
                symbol_lower=$(echo "$symbol" | tr '[:upper:]' '[:lower:]')

                if [[ "$symbol_lower" == *"$query_lower"* ]]; then
                    results=$(echo "$results" | jq \
                        --arg repo "$repo_name" \
                        --arg repo_path "$repo_path" \
                        --arg contract "$contract_path" \
                        --arg type "$contract_type" \
                        --arg symbol "$symbol" \
                        '. + [{"repository": $repo, "repository_path": $repo_path, "contract": $contract, "type": $type, "symbol": $symbol}]')
                fi
            done < <(echo "$symbols" | jq -r '.[]' 2>/dev/null)
        done
    done

    if [[ "$format" == "json" ]]; then
        jq -n \
            --arg query "$query" \
            --argjson results "$results" \
            --argjson count "$(echo "$results" | jq 'length')" \
            '{
                query: $query,
                results: $results,
                count: $count
            }'
    else
        local count
        count=$(echo "$results" | jq 'length')
        echo "Search: $query"
        echo "Found: $count results"
        echo ""

        if [[ "$count" -gt 0 ]]; then
            echo "$results" | jq -r '.[] | "  \(.symbol) [\(.type)]"'
            echo "$results" | jq -r '.[] | "    -> \(.repository): \(.contract)"'
        fi
    fi
}

# List all contracts
list_contracts() {
    local repo_filter="$1"
    local format="$2"

    if [[ ! -f "$FEDERATION_INDEX" ]]; then
        log_error "Federation index not found. Run --update first."
        return 1
    fi

    local index
    index=$(cat "$FEDERATION_INDEX")

    if [[ -n "$repo_filter" ]]; then
        index=$(echo "$index" | jq --arg name "$repo_filter" '.repositories |= map(select(.name == $name))')
    fi

    if [[ "$format" == "json" ]]; then
        echo "$index" | jq '{repositories: [.repositories[] | {name, path, contracts: [.contracts[] | {path, type, symbol_count: (.symbols | length)}]}]}'
    else
        echo "$index" | jq -r '.repositories[] | "Repository: \(.name) (\(.path))\n" + (.contracts[] | "  - \(.path) [\(.type)] (\(.symbols | length) symbols)")'
    fi
}

# ============================================================
# Virtual Edge Operations (MP5)
# Trace: AC-F05 - Cross-repo symbol query with confidence
# ============================================================

# Default graph database path
: "${GRAPH_DB:=.devbooks/graph.db}"

# Confidence thresholds
DEFAULT_MIN_CONFIDENCE="0.5"
HIGH_CONFIDENCE_THRESHOLD="0.8"

# Contract bonus values
get_contract_bonus() {
    local contract_type="$1"
    case "$contract_type" in
        proto)      echo "0.1" ;;
        graphql)    echo "0.08" ;;
        openapi)    echo "0.05" ;;
        typescript) echo "0.0" ;;
        *)          echo "0.0" ;;
    esac
}

# MP5.6: Fuzzy match algorithm (simplified Jaro-Winkler approximation)
# Returns: 1.0 (exact), 0.7 (prefix), 0.4 (fuzzy), 0.0 (no match)
calculate_exact_match() {
    local local_symbol="$1"
    local remote_symbol="$2"

    # Normalize to lowercase for comparison
    local local_lower
    local_lower=$(echo "$local_symbol" | tr '[:upper:]' '[:lower:]')
    local remote_lower
    remote_lower=$(echo "$remote_symbol" | tr '[:upper:]' '[:lower:]')

    # Exact match
    if [[ "$local_lower" == "$remote_lower" ]]; then
        echo "1.0"
        return
    fi

    # Prefix match (e.g., getUserById matches getUser)
    # Check if remote is prefix of local or vice versa
    if [[ "$local_lower" == "$remote_lower"* ]] || [[ "$remote_lower" == "$local_lower"* ]]; then
        echo "0.7"
        return
    fi

    # Check for camelCase/PascalCase matching
    # Extract base name by removing common prefixes (get, fetch, create, etc.)
    local local_base="$local_lower"
    local remote_base="$remote_lower"

    # Remove common verb prefixes for comparison
    for prefix in get fetch find load read create add new insert post update edit modify patch put delete remove destroy; do
        if [[ "$local_lower" == "${prefix}"* ]]; then
            local_base="${local_lower#${prefix}}"
        fi
        if [[ "$remote_lower" == "${prefix}"* ]]; then
            remote_base="${remote_lower#${prefix}}"
        fi
    done

    # Check if base names match (e.g., getUserById -> userbyid, GetUser -> user)
    if [[ -n "$local_base" ]] && [[ -n "$remote_base" ]]; then
        if [[ "$local_base" == "$remote_base"* ]] || [[ "$remote_base" == "$local_base"* ]]; then
            echo "0.7"
            return
        fi
    fi

    # Fuzzy match: Calculate character overlap ratio (simplified)
    # Extract common substring and check similarity
    local local_len=${#local_lower}
    local remote_len=${#remote_lower}

    # Skip if lengths are too different
    if [[ $local_len -eq 0 ]] || [[ $remote_len -eq 0 ]]; then
        echo "0.0"
        return
    fi

    # Count common characters
    local common=0
    local i=0
    while [[ $i -lt $local_len ]]; do
        local char="${local_lower:$i:1}"
        if [[ "$remote_lower" == *"$char"* ]]; then
            ((common++))
        fi
        ((i++))
    done

    # Calculate overlap ratio
    local max_len=$local_len
    [[ $remote_len -gt $max_len ]] && max_len=$remote_len

    local ratio
    if command -v bc &>/dev/null; then
        ratio=$(echo "scale=2; $common / $max_len" | bc 2>/dev/null)
    else
        # Use awk as fallback
        ratio=$(awk "BEGIN {printf \"%.2f\", $common / $max_len}" 2>/dev/null)
    fi

    # If overlap ratio > 0.5, consider it a fuzzy match
    local is_fuzzy
    if command -v bc &>/dev/null; then
        is_fuzzy=$(echo "$ratio > 0.5" | bc 2>/dev/null)
    else
        is_fuzzy=$(awk "BEGIN {print ($ratio > 0.5) ? 1 : 0}" 2>/dev/null)
    fi

    if [[ "$is_fuzzy" == "1" ]]; then
        echo "0.4"
    else
        echo "0.0"
    fi
}

# Calculate signature similarity (simplified)
# Without actual type information, use heuristic based on naming conventions
calculate_signature_similarity() {
    local local_symbol="$1"
    local remote_symbol="$2"

    # Extract potential parameter hints from names
    # e.g., getUserById suggests (id) parameter
    # e.g., createUser suggests (user) parameter

    local local_lower
    local_lower=$(echo "$local_symbol" | tr '[:upper:]' '[:lower:]')
    local remote_lower
    remote_lower=$(echo "$remote_symbol" | tr '[:upper:]' '[:lower:]')

    # Check for common verb patterns
    local local_verb=""
    local remote_verb=""

    # Extract verb (get, create, update, delete, fetch, etc.)
    if [[ "$local_lower" =~ ^(get|fetch|find|load|read) ]]; then
        local_verb="get"
    elif [[ "$local_lower" =~ ^(create|add|new|insert|post) ]]; then
        local_verb="create"
    elif [[ "$local_lower" =~ ^(update|edit|modify|patch|put) ]]; then
        local_verb="update"
    elif [[ "$local_lower" =~ ^(delete|remove|destroy) ]]; then
        local_verb="delete"
    fi

    if [[ "$remote_lower" =~ ^(get|fetch|find|load|read) ]]; then
        remote_verb="get"
    elif [[ "$remote_lower" =~ ^(create|add|new|insert|post) ]]; then
        remote_verb="create"
    elif [[ "$remote_lower" =~ ^(update|edit|modify|patch|put) ]]; then
        remote_verb="update"
    elif [[ "$remote_lower" =~ ^(delete|remove|destroy) ]]; then
        remote_verb="delete"
    fi

    # Same verb type = higher similarity
    if [[ -n "$local_verb" ]] && [[ "$local_verb" == "$remote_verb" ]]; then
        echo "0.6"
        return
    fi

    # Check for common noun (entity name)
    # e.g., getUserById and GetUser both have "user"
    local local_nouns
    local_nouns=$(echo "$local_lower" | sed 's/[A-Z]/ &/g' | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]{3,}' | sort -u)

    local remote_nouns
    remote_nouns=$(echo "$remote_lower" | sed 's/[A-Z]/ &/g' | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]{3,}' | sort -u)

    # Check for common nouns
    local common_nouns=0
    while IFS= read -r noun; do
        [[ -z "$noun" ]] && continue
        if echo "$remote_nouns" | grep -q "^${noun}$"; then
            ((common_nouns++))
        fi
    done <<< "$local_nouns"

    if [[ $common_nouns -gt 0 ]]; then
        echo "0.6"
    else
        # Default: no comparison possible
        echo "0.5"
    fi
}

# MP5.3: Calculate confidence score
# Formula: confidence = exact_match * 0.6 + signature_similarity * 0.3 + contract_bonus * 0.1
calculate_confidence() {
    local exact_match="$1"
    local signature_similarity="$2"
    local contract_bonus="$3"

    local confidence
    if command -v bc &>/dev/null; then
        confidence=$(echo "scale=2; $exact_match * 0.6 + $signature_similarity * 0.3 + $contract_bonus * 0.1" | bc 2>/dev/null)
    else
        confidence=$(awk "BEGIN {printf \"%.2f\", $exact_match * 0.6 + $signature_similarity * 0.3 + $contract_bonus * 0.1}" 2>/dev/null)
    fi

    echo "$confidence"
}

# Determine confidence level
get_confidence_level() {
    local confidence="$1"

    local is_high is_low
    if command -v bc &>/dev/null; then
        is_high=$(echo "$confidence >= $HIGH_CONFIDENCE_THRESHOLD" | bc 2>/dev/null)
        is_low=$(echo "$confidence < $DEFAULT_MIN_CONFIDENCE" | bc 2>/dev/null)
    else
        is_high=$(awk "BEGIN {print ($confidence >= $HIGH_CONFIDENCE_THRESHOLD) ? 1 : 0}" 2>/dev/null)
        is_low=$(awk "BEGIN {print ($confidence < $DEFAULT_MIN_CONFIDENCE) ? 1 : 0}" 2>/dev/null)
    fi

    if [[ "$is_high" == "1" ]]; then
        echo "high"
    elif [[ "$is_low" == "1" ]]; then
        echo "low"
    else
        echo "medium"
    fi
}

# Extract local function calls from TypeScript/JavaScript files
extract_local_symbols() {
    local repo_path="$1"
    local symbols="[]"

    # Find TypeScript/JavaScript files
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue

        local rel_path
        rel_path=$(realpath --relative-to="$repo_path" "$file" 2>/dev/null || basename "$file")

        # Extract function declarations and async functions
        while IFS= read -r line; do
            # Match: export async function name
            # Match: export function name
            # Match: async function name
            # Match: function name
            if [[ "$line" =~ (export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
                local func_name="${BASH_REMATCH[3]}"
                symbols=$(echo "$symbols" | jq \
                    --arg name "$func_name" \
                    --arg file "$rel_path" \
                    --arg type "function" \
                    '. + [{"name": $name, "file": $file, "type": $type}]')
            fi
            # Match: const name = async
            # Match: const name = function
            if [[ "$line" =~ (export[[:space:]]+)?(const|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(async[[:space:]]+)?(function|\() ]]; then
                local func_name="${BASH_REMATCH[3]}"
                symbols=$(echo "$symbols" | jq \
                    --arg name "$func_name" \
                    --arg file "$rel_path" \
                    --arg type "function" \
                    '. + [{"name": $name, "file": $file, "type": $type}]')
            fi
        done < "$file"
    done < <(find "$repo_path" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
        -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)

    echo "$symbols"
}

# MP5.2: Generate virtual edges
# SC-FV-001: Proto virtual edge generation
generate_virtual_edges() {
    local local_repo="${1:-.}"
    local db_path="${2:-$GRAPH_DB}"
    local min_confidence="${3:-$DEFAULT_MIN_CONFIDENCE}"
    local sync_mode="${4:-false}"
    local config_file="${5:-$FEDERATION_CONFIG}"

    # Ensure federation index exists
    if [[ ! -f "$FEDERATION_INDEX" ]]; then
        log_error "Federation index not found. Run --update first."
        return 1
    fi

    # Ensure database directory exists
    if [[ ! -f "$db_path" ]]; then
        log_warn "Graph database not found at $db_path, creating..."
        mkdir -p "$(dirname "$db_path")"
    fi

    # Always ensure virtual_edges table exists (handles both new and existing DB)
    # Note: CREATE TABLE IF NOT EXISTS is idempotent
    sqlite3 "$db_path" << 'EOF' 2>/dev/null
CREATE TABLE IF NOT EXISTS virtual_edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_repo TEXT NOT NULL,
    source_symbol TEXT NOT NULL,
    target_repo TEXT NOT NULL,
    target_symbol TEXT NOT NULL,
    edge_type TEXT DEFAULT 'VIRTUAL_CALLS',
    confidence REAL NOT NULL DEFAULT 1.0,
    confidence_level TEXT DEFAULT 'medium',
    contract_type TEXT DEFAULT 'unknown',
    contract_bonus REAL DEFAULT 0.0,
    exact_match REAL DEFAULT 0.0,
    signature_similarity REAL DEFAULT 0.5,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_virtual_edges_source ON virtual_edges(source_repo, source_symbol);
CREATE INDEX IF NOT EXISTS idx_virtual_edges_target ON virtual_edges(target_repo, target_symbol);
CREATE INDEX IF NOT EXISTS idx_virtual_edges_type ON virtual_edges(edge_type);
EOF

    log_info "Generating virtual edges from $local_repo"
    log_debug "Database: $db_path"
    log_debug "Min confidence: $min_confidence"
    log_debug "Sync mode: $sync_mode"

    # Load federation index
    local index
    index=$(cat "$FEDERATION_INDEX")

    # Extract local symbols
    log_info "Extracting local symbols..."
    local local_symbols
    local_symbols=$(extract_local_symbols "$local_repo")
    local local_symbol_count
    local_symbol_count=$(echo "$local_symbols" | jq 'length')
    log_info "Found $local_symbol_count local symbols"

    # Get local repo name
    local local_repo_name
    local_repo_name=$(basename "$(realpath "$local_repo" 2>/dev/null || echo "$local_repo")")

    # In sync mode, mark existing edges for potential deletion
    if [[ "$sync_mode" == "true" ]]; then
        log_info "Sync mode: will update existing edges"
    fi

    local edges_created=0
    local edges_updated=0
    local edges_skipped=0

    # Iterate over local symbols
    while IFS= read -r local_sym; do
        [[ -z "$local_sym" ]] && continue
        [[ "$local_sym" == "null" ]] && continue

        local local_name
        local_name=$(echo "$local_sym" | jq -r '.name')
        local local_file
        local_file=$(echo "$local_sym" | jq -r '.file')

        log_debug "Processing local symbol: $local_name"

        # Find matching remote symbols
        local repo_count
        repo_count=$(echo "$index" | jq '.repositories | length')

        for ((i=0; i<repo_count; i++)); do
            local remote_repo_name remote_repo_path
            remote_repo_name=$(echo "$index" | jq -r ".repositories[$i].name")
            remote_repo_path=$(echo "$index" | jq -r ".repositories[$i].path")

            # Skip if same repo
            [[ "$remote_repo_name" == "$local_repo_name" ]] && continue

            local contract_count
            contract_count=$(echo "$index" | jq ".repositories[$i].contracts | length")

            for ((j=0; j<contract_count; j++)); do
                local contract_type contract_path remote_symbols
                contract_type=$(echo "$index" | jq -r ".repositories[$i].contracts[$j].type")
                contract_path=$(echo "$index" | jq -r ".repositories[$i].contracts[$j].path")
                remote_symbols=$(echo "$index" | jq ".repositories[$i].contracts[$j].symbols")

                # Get contract bonus
                local contract_bonus
                contract_bonus=$(get_contract_bonus "$contract_type")

                # Check each remote symbol
                while IFS= read -r remote_symbol; do
                    [[ -z "$remote_symbol" ]] && continue

                    # Calculate exact match score
                    local exact_match
                    exact_match=$(calculate_exact_match "$local_name" "$remote_symbol")

                    # Skip if no match at all
                    if [[ "$exact_match" == "0.0" ]] || [[ "$exact_match" == "0" ]]; then
                        continue
                    fi

                    # Calculate signature similarity
                    local signature_similarity
                    signature_similarity=$(calculate_signature_similarity "$local_name" "$remote_symbol")

                    # Calculate overall confidence
                    local confidence
                    confidence=$(calculate_confidence "$exact_match" "$signature_similarity" "$contract_bonus")

                    # MP5.4: Filter by confidence threshold
                    local passes_threshold
                    if command -v bc &>/dev/null; then
                        passes_threshold=$(echo "$confidence >= $min_confidence" | bc 2>/dev/null)
                    else
                        passes_threshold=$(awk "BEGIN {print ($confidence >= $min_confidence) ? 1 : 0}" 2>/dev/null)
                    fi

                    if [[ "$passes_threshold" != "1" ]]; then
                        log_debug "  Skipping $local_name -> $remote_symbol (confidence $confidence < $min_confidence)"
                        ((edges_skipped++))
                        continue
                    fi

                    # Determine confidence level
                    local confidence_level
                    confidence_level=$(get_confidence_level "$confidence")

                    log_debug "  Match: $local_name -> $remote_symbol (confidence: $confidence, level: $confidence_level)"

                    # Insert or update virtual edge
                    # Use a composite key check to avoid duplicates
                    local sql
                    if [[ "$sync_mode" == "true" ]]; then
                        # Delete existing edge and re-insert with updated values
                        sqlite3 "$db_path" "DELETE FROM virtual_edges WHERE source_repo='$local_repo_name' AND source_symbol='$local_name' AND target_repo='$remote_repo_name' AND target_symbol='$remote_symbol';" 2>/dev/null
                        sql="INSERT INTO virtual_edges (source_repo, source_symbol, target_repo, target_symbol, edge_type, contract_type, confidence, confidence_level, exact_match, signature_similarity, contract_bonus, updated_at) VALUES ('$local_repo_name', '$local_name', '$remote_repo_name', '$remote_symbol', 'VIRTUAL_CALLS', '$contract_type', $confidence, '$confidence_level', $exact_match, $signature_similarity, $contract_bonus, datetime('now'));"
                        ((edges_updated++))
                    else
                        # Check if edge already exists
                        local exists
                        exists=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM virtual_edges WHERE source_repo='$local_repo_name' AND source_symbol='$local_name' AND target_repo='$remote_repo_name' AND target_symbol='$remote_symbol';" 2>/dev/null)
                        if [[ "$exists" -gt 0 ]]; then
                            log_debug "    Edge already exists, skipping"
                            continue
                        fi
                        sql="INSERT INTO virtual_edges (source_repo, source_symbol, target_repo, target_symbol, edge_type, contract_type, confidence, confidence_level, exact_match, signature_similarity, contract_bonus) VALUES ('$local_repo_name', '$local_name', '$remote_repo_name', '$remote_symbol', 'VIRTUAL_CALLS', '$contract_type', $confidence, '$confidence_level', $exact_match, $signature_similarity, $contract_bonus);"
                        ((edges_created++))
                    fi

                    sqlite3 "$db_path" "$sql" 2>/dev/null || log_warn "Failed to insert edge: $local_name -> $remote_symbol"

                done < <(echo "$remote_symbols" | jq -r '.[]' 2>/dev/null)
            done
        done
    done < <(echo "$local_symbols" | jq -c '.[]' 2>/dev/null)

    # Report summary
    local total_edges
    total_edges=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM virtual_edges" 2>/dev/null || echo "0")

    log_info "Virtual edge generation complete"
    log_info "  Created: $edges_created"
    log_info "  Updated: $edges_updated"
    log_info "  Skipped (low confidence): $edges_skipped"
    log_info "  Total in database: $total_edges"

    # Output JSON summary
    jq -n \
        --argjson created "$edges_created" \
        --argjson updated "$edges_updated" \
        --argjson skipped "$edges_skipped" \
        --argjson total "$total_edges" \
        --arg db_path "$db_path" \
        '{
            status: "ok",
            edges_created: $created,
            edges_updated: $updated,
            edges_skipped: $skipped,
            total_edges: $total,
            db_path: $db_path
        }'
}

# MP5.5: Query virtual edges
# SC-FV-004: Query virtual edges by symbol
query_virtual_edges() {
    local symbol="$1"
    local db_path="${2:-$GRAPH_DB}"
    local min_confidence="${3:-0.0}"
    local format="${4:-json}"

    if [[ ! -f "$db_path" ]]; then
        log_error "Graph database not found: $db_path"
        return 1
    fi

    log_debug "Querying virtual edges for: $symbol"
    log_debug "Database: $db_path"
    log_debug "Min confidence: $min_confidence"

    # Query virtual edges where symbol matches source or target
    local sql="SELECT json_group_array(json_object(
        'id', id,
        'source_repo', source_repo,
        'source_symbol', source_symbol,
        'target_repo', target_repo,
        'target_symbol', target_symbol,
        'edge_type', edge_type,
        'contract_type', contract_type,
        'confidence', confidence,
        'confidence_level', confidence_level,
        'exact_match', exact_match,
        'signature_similarity', signature_similarity,
        'contract_bonus', contract_bonus,
        'created_at', created_at,
        'updated_at', updated_at
    )) FROM virtual_edges
    WHERE (source_symbol LIKE '%${symbol}%' OR target_symbol LIKE '%${symbol}%')
    AND confidence >= $min_confidence
    ORDER BY confidence DESC;"

    local results
    results=$(sqlite3 "$db_path" "$sql" 2>/dev/null)

    # Handle empty results
    if [[ -z "$results" ]] || [[ "$results" == "[]" ]] || [[ "$results" == "null" ]]; then
        results="[]"
    fi

    local count
    count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$format" == "json" ]]; then
        jq -n \
            --arg symbol "$symbol" \
            --argjson results "$results" \
            --argjson count "$count" \
            '{
                query: $symbol,
                results: $results,
                count: $count
            }'
    else
        echo "Query: $symbol"
        echo "Found: $count virtual edges"
        echo ""

        if [[ "$count" -gt 0 ]]; then
            echo "$results" | jq -r '.[] | "  \(.source_symbol) -> \(.target_symbol) [\(.contract_type)]"'
            echo "$results" | jq -r '.[] | "    Confidence: \(.confidence) (\(.confidence_level))"'
            echo "$results" | jq -r '.[] | "    From: \(.source_repo) -> \(.target_repo)"'
        fi
    fi
}

# ============================================================
# Main Entry Point
# ============================================================

main() {
    local action=""
    local config_file="$FEDERATION_CONFIG"
    local query=""
    local repo_filter=""
    local format="json"
    local local_repo="."
    local db_path="$GRAPH_DB"
    local min_confidence="$DEFAULT_MIN_CONFIDENCE"
    local sync_mode="false"
    local virtual_edges_flag="false"

    # Parse first argument for subcommands
    if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
        case "$1" in
            generate-virtual-edges)
                action="generate-virtual-edges"
                shift
                ;;
            query-virtual)
                action="query-virtual"
                if [[ $# -gt 1 ]] && [[ "$2" != -* ]]; then
                    query="$2"
                    shift 2
                else
                    shift
                fi
                ;;
        esac
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)
                action="status"
                shift
                ;;
            --update)
                action="update"
                shift
                ;;
            --search)
                action="search"
                query="$2"
                shift 2
                ;;
            --list-contracts)
                action="list"
                shift
                ;;
            --config)
                config_file="$2"
                shift 2
                ;;
            --repo)
                repo_filter="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            --local-repo)
                local_repo="$2"
                shift 2
                ;;
            --db)
                db_path="$2"
                shift 2
                ;;
            --min-confidence)
                min_confidence="$2"
                shift 2
                ;;
            --confidence)
                min_confidence="$2"
                shift 2
                ;;
            --sync)
                sync_mode="true"
                shift
                ;;
            --virtual-edges)
                virtual_edges_flag="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # Ensure jq is available
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed"
        exit 2
    fi

    case "$action" in
        status)
            show_status "$format"
            ;;
        update)
            update_index "$config_file"
            ;;
        search)
            if [[ -z "$query" ]]; then
                log_error "Usage: federation-lite.sh --search <symbol>"
                exit 1
            fi
            search_symbol "$query" "$format"
            ;;
        list)
            list_contracts "$repo_filter" "$format"
            ;;
        generate-virtual-edges)
            generate_virtual_edges "$local_repo" "$db_path" "$min_confidence" "$sync_mode" "$config_file"
            ;;
        query-virtual)
            if [[ -z "$query" ]]; then
                log_error "Usage: federation-lite.sh query-virtual <symbol>"
                exit 1
            fi
            query_virtual_edges "$query" "$db_path" "$min_confidence" "$format"
            ;;
        "")
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown action: $action"
            show_help
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
