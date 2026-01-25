#!/bin/bash
# dependency-guard-orphan.sh - Orphan Detection Module
#
# Version: 1.0.0
# Purpose: Detect orphan modules (no incoming edges, not entry points)
# Part of: dependency-guard.sh modular architecture
#
# Trace: AC-006 ~ AC-008, AC-012, AC-N03, AC-N04
# Change: augment-upgrade-phase2

# ============================================================
# Orphan Detection (MP3.3)
# ============================================================

# Entry point patterns - files matching these are not considered orphans
ENTRY_POINT_PATTERNS="main|index|entry|app|server"

# Default exclude patterns for orphan detection
DEFAULT_ORPHAN_EXCLUDE="test|spec|mock|fixture"

# Check if a file is an entry point
is_entry_point() {
    local file="$1"
    local basename
    basename=$(basename "$file" | sed 's/\.[^.]*$//')

    if [[ "$basename" =~ ^($ENTRY_POINT_PATTERNS)$ ]]; then
        return 0
    fi
    return 1
}

# Check if file matches exclude patterns
matches_orphan_exclude() {
    local file="$1"
    local exclude_patterns="$2"

    # Check default excludes
    if [[ "$file" =~ ($DEFAULT_ORPHAN_EXCLUDE) ]]; then
        return 0
    fi

    # Check custom excludes
    if [[ -n "$exclude_patterns" ]]; then
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            if match_glob "$file" "$pattern"; then
                return 0
            fi
        done <<< "$exclude_patterns"
    fi

    return 1
}

# Detect orphan modules (nodes with no incoming edges)
detect_orphans() {
    local scope="$1"
    local exclude_patterns="$2"

    # Check if feature is disabled
    if [[ -n "${FEATURES_CONFIG:-}" && -f "$FEATURES_CONFIG" ]]; then
        local enabled
        enabled=$(grep -A1 "orphan_detection:" "$FEATURES_CONFIG" 2>/dev/null | grep "enabled:" | grep -o "false" || true)
        if [[ "$enabled" == "false" ]]; then
            echo '{"orphans": [], "summary": {"total_nodes": 0, "orphan_count": 0, "orphan_ratio": 0, "disabled": true}}'
            return 0
        fi
    fi

    local temp_dir
    temp_dir=$(mktemp -d)
    local nodes_file="$temp_dir/nodes.txt"
    local edges_file="$temp_dir/edges.txt"
    local incoming_file="$temp_dir/incoming.txt"

    : > "$nodes_file"
    : > "$edges_file"
    : > "$incoming_file"

    # Find all source files in scope
    local file_count=0
    while IFS= read -r -d '' file; do
        local rel_path
        rel_path=$(normalize_rel_path "$file")
        echo "$rel_path" >> "$nodes_file"
        file_count=$((file_count + 1))

        # Extract imports and record edges
        local imports
        imports=$(extract_imports "$file")

        while IFS= read -r imp; do
            [[ -z "$imp" ]] && continue
            local target
            target=$(echo "$imp" | jq -r '.target' 2>/dev/null)
            [[ -z "$target" ]] && continue

            local resolved
            resolved=$(resolve_import_path "$file" "$target")
            [[ -z "$resolved" || ! -f "$resolved" ]] && continue

            local rel_resolved
            rel_resolved=$(normalize_rel_path "$resolved")
            echo "$rel_resolved" >> "$incoming_file"
        done < <(echo "$imports" | jq -c '.[]' 2>/dev/null)
    done < <(find "$scope" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) -print0 2>/dev/null)

    if [[ $file_count -eq 0 ]]; then
        rm -rf "$temp_dir"
        echo '{"orphans": [], "summary": {"total_nodes": 0, "orphan_count": 0, "orphan_ratio": 0, "message": "No nodes found"}}'
        return 0
    fi

    # Find orphans: nodes with no incoming edges, not entry points, not excluded
    local orphans="[]"
    local orphan_count=0

    while IFS= read -r node; do
        [[ -z "$node" ]] && continue

        # Check if has incoming edges
        if grep -qF "$node" "$incoming_file" 2>/dev/null; then
            continue
        fi

        # Skip if entry point
        if is_entry_point "$node"; then
            continue
        fi

        # Skip if matches exclude patterns
        if matches_orphan_exclude "$node" "$exclude_patterns"; then
            continue
        fi

        orphans=$(echo "$orphans" | jq --arg file "$node" '. + [$file]')
        orphan_count=$((orphan_count + 1))
    done < "$nodes_file"

    # Calculate orphan ratio
    local orphan_ratio=0
    if [[ $file_count -gt 0 ]]; then
        orphan_ratio=$(awk -v oc="$orphan_count" -v fc="$file_count" 'BEGIN { printf "%.4f", oc / fc }')
    fi

    rm -rf "$temp_dir"

    jq -n \
        --argjson orphans "$orphans" \
        --argjson total_nodes "$file_count" \
        --argjson orphan_count "$orphan_count" \
        --arg orphan_ratio "$orphan_ratio" \
        '{
            orphans: $orphans,
            summary: {
                total_nodes: $total_nodes,
                orphan_count: $orphan_count,
                orphan_ratio: ($orphan_ratio | tonumber)
            }
        }'
}
