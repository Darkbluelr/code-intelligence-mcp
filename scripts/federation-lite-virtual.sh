#!/bin/bash
# federation-lite-virtual.sh - Virtual edge operations
#
# Version: 1.0.0
# Purpose: Generate and query virtual edges for cross-repo symbol matching
# Trace: AC-011, AC-F05
# Change: augment-upgrade-phase2

# Prevent multiple sourcing
[[ -n "${FEDERATION_LITE_VIRTUAL_LOADED:-}" ]] && return 0
FEDERATION_LITE_VIRTUAL_LOADED=1

# ============================================================
# Matching Algorithms
# ============================================================

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

# ============================================================
# Virtual Edge Generation
# ============================================================

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

# ============================================================
# Virtual Edge Query
# ============================================================

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
