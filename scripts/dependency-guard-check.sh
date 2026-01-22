#!/bin/bash
# dependency-guard-check.sh - Cycle Detection Module
#
# Version: 1.0.0
# Purpose: Detect circular dependencies in codebase
# Part of: dependency-guard.sh modular architecture
#
# Trace: AC-006 ~ AC-008, AC-012, AC-N03, AC-N04
# Change: augment-upgrade-phase2

# ============================================================
# Cycle Detection Algorithm (MP2.2)
# ============================================================

# Build dependency graph from files
build_dependency_graph() {
    local scope="$1"
    local files=()

    # Find all source files
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$scope" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.sh" \) -print0 2>/dev/null)

    local graph="{}"

    for file in "${files[@]}"; do
        local imports
        imports=$(extract_imports "$file")

        local edges="[]"
        echo "$imports" | jq -c '.[]' 2>/dev/null | while read -r imp; do
            local target
            target=$(echo "$imp" | jq -r '.target')
            local resolved
            resolved=$(resolve_import_path "$file" "$target")

            if [[ -n "$resolved" && -f "$resolved" ]]; then
                edges=$(echo "$edges" | jq --arg target "$resolved" '. + [$target]')
            fi
        done

        graph=$(echo "$graph" | jq --arg file "$file" --argjson deps "$(echo "$imports" | jq '[.[] | .target]')" \
            '.[$file] = $deps')
    done

    echo "$graph"
}

# Detect cycles using DFS with color marking
# State: 0=WHITE (not visited), 1=GRAY (in stack), 2=BLACK (done)
detect_cycles() {
    local scope="$1"
    local whitelist="${2:-}"

    local cycles="[]"
    local files=()

    # Find all source files in scope
    while IFS= read -r file; do
        # Check whitelist
        local skip=false
        if [[ -n "$whitelist" ]]; then
            echo "$whitelist" | tr ',' '\n' | while read -r pattern; do
                if [[ "$file" == *"$pattern"* ]]; then
                    skip=true
                    break
                fi
            done
        fi
        [[ "$skip" == "true" ]] && continue
        files+=("$file")
    done < <(find "$scope" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) 2>/dev/null)

    # Build adjacency list
    declare -A adj_list
    declare -A file_imports

    for file in "${files[@]}"; do
        local imports
        imports=$(extract_imports "$file")

        local deps=""
        echo "$imports" | jq -c '.[]' 2>/dev/null | while read -r imp; do
            local target
            target=$(echo "$imp" | jq -r '.target')
            local resolved
            resolved=$(resolve_import_path "$file" "$target")

            if [[ -n "$resolved" && -f "$resolved" ]]; then
                deps="$deps $resolved"
            fi
        done

        adj_list["$file"]="$deps"
    done

    # DFS with cycle detection
    declare -A color  # 0=WHITE, 1=GRAY, 2=BLACK

    for file in "${files[@]}"; do
        color["$file"]=0
    done

    dfs_detect() {
        local node="$1"
        local path="$2"

        color["$node"]=1  # GRAY
        local new_path="${path}:${node}"

        for dep in ${adj_list["$node"]:-}; do
            if [[ "${color[$dep]:-0}" -eq 1 ]]; then
                # Found cycle (GRAY -> GRAY edge)
                local cycle_start
                cycle_start=$(echo "$new_path" | tr ':' '\n' | grep -n "^${dep}$" | cut -d: -f1 | head -1)
                if [[ -n "$cycle_start" ]]; then
                    local cycle_path
                    cycle_path=$(echo "$new_path" | tr ':' '\n' | tail -n "+$cycle_start")
                    cycle_path="$cycle_path
$dep"
                    cycles=$(echo "$cycles" | jq --arg path "$cycle_path" '. + [{"path": ($path | split("\n")), "severity": "error"}]')
                fi
            elif [[ "${color[$dep]:-0}" -eq 0 ]]; then
                dfs_detect "$dep" "$new_path"
            fi
        done

        color["$node"]=2  # BLACK
    }

    for file in "${files[@]}"; do
        if [[ "${color[$file]:-0}" -eq 0 ]]; then
            dfs_detect "$file" ""
        fi
    done

    echo "$cycles"
}

# Build cycle edges for detection
build_cycle_edges() {
    local edges_file="$1"
    local ignore_json="$2"
    local whitelist_json="$3"
    shift 3
    local files=("$@")

    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue
        local rel_src
        rel_src=$(normalize_rel_path "$file")
        if matches_pattern_list "$rel_src" "$ignore_json"; then
            continue
        fi
        if matches_pattern_list "$rel_src" "$whitelist_json"; then
            continue
        fi

        local imports
        imports=$(extract_imports "$file")

        while IFS= read -r imp; do
            local target
            target=$(echo "$imp" | jq -r '.target')
            local resolved
            resolved=$(resolve_import_path "$file" "$target")
            [[ -z "$resolved" ]] && continue

            local rel_dst
            rel_dst=$(normalize_rel_path "$resolved")
            if matches_pattern_list "$rel_dst" "$ignore_json"; then
                continue
            fi
            if matches_pattern_list "$rel_dst" "$whitelist_json"; then
                continue
            fi

            echo "$rel_src -> $rel_dst" >> "$edges_file"
        done < <(echo "$imports" | jq -c '.[]' 2>/dev/null)
    done
}

# Detect cycles from edge list
detect_cycles_from_edges() {
    local edges_file="$1"

    local python_bin=""
    if command -v python3 &>/dev/null; then
        python_bin="python3"
    elif command -v python &>/dev/null; then
        python_bin="python"
    fi

    if [[ -n "$python_bin" ]]; then
        "$python_bin" - "$edges_file" << 'PY'
import json
import sys

edges_file = sys.argv[1]
edges = []
with open(edges_file, "r", encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line or "->" not in line:
            continue
        src, dst = [part.strip() for part in line.split("->", 1)]
        edges.append((src, dst))

adj = {}
nodes = set()
for src, dst in edges:
    adj.setdefault(src, set()).add(dst)
    nodes.add(src)
    nodes.add(dst)

cycles = []
seen = set()

def normalize_cycle(cycle):
    cycle_nodes = cycle[:-1]
    min_index = min(range(len(cycle_nodes)), key=lambda i: cycle_nodes[i])
    rotated = cycle_nodes[min_index:] + cycle_nodes[:min_index]
    return tuple(rotated)

def dfs(node, path, visiting):
    visiting.add(node)
    path.append(node)
    for neighbor in adj.get(node, []):
        if neighbor in visiting:
            if neighbor in path:
                idx = path.index(neighbor)
                cycle = path[idx:] + [neighbor]
                key = normalize_cycle(cycle)
                if key not in seen:
                    seen.add(key)
                    cycles.append(cycle)
        else:
            dfs(neighbor, path, visiting)
    path.pop()
    visiting.remove(node)

for node in sorted(nodes):
    dfs(node, [], set())

result = [{"path": cycle, "severity": "error"} for cycle in cycles]
print(json.dumps(result))
PY
        return 0
    fi

    local cycles="[]"
    local input_edges="$edges_file"
    while IFS= read -r edge1; do
        [[ -z "$edge1" ]] && continue
        local src1 dst1
        src1=$(echo "$edge1" | sed 's/ -> .*//')
        dst1=$(echo "$edge1" | sed 's/.* -> //')

        if grep -qF "${dst1} -> ${src1}" "$input_edges" 2>/dev/null; then
            cycles=$(echo "$cycles" | jq --arg src "$src1" --arg dst "$dst1" \
                '. + [{"path": [$src, $dst, $src], "severity": "error"}]')
        fi
    done < "$input_edges"

    cycles=$(echo "$cycles" | jq 'unique_by(.path | sort)')
    echo "$cycles"
}

# Simplified cycle detection using file scanning
detect_cycles_simple() {
    local scope="$1"
    local whitelist_json="${2:-[]}"
    local ignore_json="${3:-[]}"

    local temp_dir
    temp_dir=$(mktemp -d)
    local edges_file="$temp_dir/edges.txt"
    : > "$edges_file"

    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$scope" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) -print0 2>/dev/null)

    if [[ ${#files[@]} -gt 0 ]]; then
        build_cycle_edges "$edges_file" "$ignore_json" "$whitelist_json" "${files[@]}"
    fi
    local cycles
    cycles=$(detect_cycles_from_edges "$edges_file")

    rm -rf "$temp_dir"
    echo "$cycles"
}

# Detect cycles for specific files
detect_cycles_for_files() {
    local whitelist_json="$1"
    local ignore_json="$2"
    shift 2
    local files=("$@")

    local temp_dir
    temp_dir=$(mktemp -d)
    local edges_file="$temp_dir/edges.txt"
    : > "$edges_file"

    if [[ ${#files[@]} -gt 0 ]]; then
        build_cycle_edges "$edges_file" "$ignore_json" "$whitelist_json" "${files[@]}"
    fi
    local cycles
    cycles=$(detect_cycles_from_edges "$edges_file")

    rm -rf "$temp_dir"
    echo "$cycles"
}
