#!/bin/bash
# federation-lite-index.sh - Index operations
#
# Version: 1.0.0
# Purpose: Update, query, and manage federation index
# Trace: AC-011
# Change: augment-upgrade-phase2

# Prevent multiple sourcing
[[ -n "${FEDERATION_LITE_INDEX_LOADED:-}" ]] && return 0
FEDERATION_LITE_INDEX_LOADED=1

# ============================================================
# Index Operations
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
