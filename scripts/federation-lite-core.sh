#!/bin/bash
# federation-lite-core.sh - Core utilities and configuration
#
# Version: 1.0.0
# Purpose: Shared utilities, logging, and configuration for federation-lite
# Trace: AC-011
# Change: augment-upgrade-phase2

# Prevent multiple sourcing
[[ -n "${FEDERATION_LITE_CORE_LOADED:-}" ]] && return 0
FEDERATION_LITE_CORE_LOADED=1

# ============================================================
# Configuration
# ============================================================

SCHEMA_VERSION="1.0.0"
: "${FEDERATION_CONFIG:=config/federation.yaml}"
: "${FEDERATION_INDEX:=.devbooks/federation-index.json}"
: "${GRAPH_DB:=.devbooks/graph.db}"
: "${DEBUG:=false}"

# Confidence thresholds
DEFAULT_MIN_CONFIDENCE="0.5"
HIGH_CONFIDENCE_THRESHOLD="0.8"

# ============================================================
# Logging Functions
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

# ============================================================
# Utility Functions
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

# ============================================================
# Configuration Loading
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
# Help Text
# ============================================================

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
