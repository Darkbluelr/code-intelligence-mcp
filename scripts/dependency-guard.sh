#!/bin/bash
# dependency-guard.sh - Architecture Guard (Cycle Detection + Rule Validation)
#
# Version: 1.0.0
# Purpose: Detect circular dependencies and validate architecture rules
# Depends: jq, ripgrep (rg), git
#
# Usage:
#   dependency-guard.sh --cycles --scope "src/" --format json
#   dependency-guard.sh --rules <rules.yaml> --format json
#   dependency-guard.sh --all --scope "src/" --rules <rules.yaml>
#   dependency-guard.sh --pre-commit [--with-deps]
#   dependency-guard.sh --help
#
# Environment Variables:
#   ARCH_RULES_FILE     - Path to architecture rules file (default: config/arch-rules.yaml)
#   DEBUG               - Enable debug output (default: false)
#
# Trace: AC-006 ~ AC-008, AC-012, AC-N03, AC-N04
# Change: augment-upgrade-phase2

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

REPORT_SCHEMA_VERSION="1.0.0"
: "${ARCH_RULES_FILE:=config/arch-rules.yaml}"
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
dependency-guard.sh - Architecture Guard (Cycle Detection + Rule Validation)

Usage:
  dependency-guard.sh --cycles --scope "src/" --format json
  dependency-guard.sh --rules <rules.yaml> --format json
  dependency-guard.sh --all --scope "src/" --rules <rules.yaml>
  dependency-guard.sh --orphan-check --scope "src/" --format json
  dependency-guard.sh --pre-commit [--with-deps]
  dependency-guard.sh --help

Options:
  --cycles            Detect circular dependencies
  --rules <file>      Validate architecture rules from file
  --all               Run both cycle detection and rule validation
  --orphan-check      Detect orphan modules (no incoming edges, not entry points)
  --exclude <pattern> Exclude pattern for orphan detection (can be repeated)
  --scope <pattern>   Scope for cycle detection (default: src/)
  --format <type>     Output format: text or json (default: json)
  --pre-commit        Check only staged files
  --with-deps         Include first-level dependencies
  --help              Show this help message

Environment Variables:
  ARCH_RULES_FILE     Path to architecture rules file (default: config/arch-rules.yaml)

Examples:
  # Detect cycles in src/
  dependency-guard.sh --cycles --scope "src/" --format json

  # Validate architecture rules
  dependency-guard.sh --rules config/arch-rules.yaml

  # Pre-commit hook
  dependency-guard.sh --pre-commit --with-deps
EOF
}

# ============================================================
# Import Extraction (MP2.1)
# ============================================================

# Extract imports from a TypeScript/JavaScript file
# Output: JSON array of imports
extract_imports_ts() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "[]"
        return
    fi

    # Use a temp file to collect imports for better performance
    local temp_imports
    temp_imports=$(mktemp)
    # Ensure temp file is cleaned up on function exit (trap RETURN)
    trap "rm -f '$temp_imports'" RETURN
    echo "[]" > "$temp_imports"

    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        local target=""

        # Match: import ... from '...' or import ... from "..."
        if [[ "$line" =~ ^[[:space:]]*(import|export)[[:space:]].*from[[:space:]]*[\'\"]([^\'\"]+)[\'\"] ]]; then
            target="${BASH_REMATCH[2]:-}"
            if [[ -n "$target" ]]; then
                local current
                current=$(cat "$temp_imports")
                echo "$current" | jq --arg source "$file" --arg target "$target" --argjson line "$line_num" \
                    '. + [{"source": $source, "target": $target, "line": $line}]' > "$temp_imports"
            fi
        fi

        # Match: require('...') or require("...")
        if [[ "$line" =~ require\([[:space:]]*[\'\"]([^\'\"]+)[\'\"]\) ]]; then
            target="${BASH_REMATCH[1]:-}"
            if [[ -n "$target" ]]; then
                local current
                current=$(cat "$temp_imports")
                echo "$current" | jq --arg source "$file" --arg target "$target" --argjson line "$line_num" \
                    '. + [{"source": $source, "target": $target, "line": $line}]' > "$temp_imports"
            fi
        fi
    done < "$file"

    cat "$temp_imports"
}

# Extract imports from a Bash script
extract_imports_bash() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "[]"
        return
    fi

    local temp_imports
    temp_imports=$(mktemp)
    # Ensure temp file is cleaned up on function exit (trap RETURN)
    trap "rm -f '$temp_imports'" RETURN
    echo "[]" > "$temp_imports"

    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        local target=""

        # Match: source ... or . ...
        if [[ "$line" =~ ^[[:space:]]*(source|\.)[[:space:]]+[\"\']?([^\"\'[:space:]]+)[\"\']? ]]; then
            target="${BASH_REMATCH[2]:-}"
            if [[ -n "$target" ]]; then
                local current
                current=$(cat "$temp_imports")
                echo "$current" | jq --arg source "$file" --arg target "$target" --argjson line "$line_num" \
                    '. + [{"source": $source, "target": $target, "line": $line}]' > "$temp_imports"
            fi
        fi
    done < "$file"

    cat "$temp_imports"
}

# Extract imports from any supported file
extract_imports() {
    local file="$1"

    case "$file" in
        *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
            extract_imports_ts "$file"
            ;;
        *.sh|*.bash)
            extract_imports_bash "$file"
            ;;
        *)
            echo "[]"
            ;;
    esac
}

# Resolve relative import path to absolute path
resolve_import_path() {
    local source_file="$1"
    local import_target="$2"

    # Skip external modules (no ./ or ../)
    if [[ ! "$import_target" =~ ^\.\.?/ ]]; then
        echo ""
        return
    fi

    local source_dir
    source_dir=$(dirname "$source_file")

    # Build the resolved path manually (cross-platform)
    local resolved=""
    if [[ "$import_target" =~ ^\.\/ ]]; then
        # ./foo -> source_dir/foo
        resolved="${source_dir}/${import_target#./}"
    elif [[ "$import_target" =~ ^\.\.\/ ]]; then
        # ../foo -> parent(source_dir)/foo
        local parent_dir
        parent_dir=$(dirname "$source_dir")
        resolved="${parent_dir}/${import_target#../}"
    else
        resolved="${source_dir}/${import_target}"
    fi

    # Normalize path (remove ./ and handle ..)
    if command -v python3 &>/dev/null; then
        resolved=$(python3 -c "import os.path; print(os.path.normpath('$resolved'))" 2>/dev/null) || resolved="$resolved"
    elif command -v python &>/dev/null; then
        resolved=$(python -c "import os.path; print(os.path.normpath('$resolved'))" 2>/dev/null) || resolved="$resolved"
    fi

    if [[ -z "$resolved" ]]; then
        return
    fi

    # Try common extensions
    for ext in "" ".ts" ".tsx" ".js" ".jsx" ".sh"; do
        local candidate="${resolved}${ext}"
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    done

    # Try index files if it's a directory
    if [[ -d "$resolved" ]]; then
        for idx in "index.ts" "index.tsx" "index.js" "index.jsx"; do
            local candidate="${resolved}/${idx}"
            if [[ -f "$candidate" ]]; then
                echo "$candidate"
                return
            fi
        done
    fi

    echo ""
}

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

# Cross-platform realpath for relative paths
# Resolves ./foo or ../bar relative to a directory
resolve_relative_path() {
    local dir="$1"
    local target="$2"

    # Normalize the path manually
    local result=""
    if [[ "$target" =~ ^\.\/ ]]; then
        # ./foo -> dir/foo
        result="${dir}/${target#./}"
    elif [[ "$target" =~ ^\.\.\/ ]]; then
        # ../foo -> parent(dir)/foo
        result="$(dirname "$dir")/${target#../}"
    else
        result="${dir}/${target}"
    fi

    # Normalize double slashes and resolve ..
    result=$(echo "$result" | sed 's|/\./|/|g; s|//|/|g')

    # Use Python if available for proper normalization, else use simple approach
    if command -v python3 &>/dev/null; then
        python3 -c "import os.path; print(os.path.normpath('$result'))" 2>/dev/null || echo "$result"
    elif command -v python &>/dev/null; then
        python -c "import os.path; print(os.path.normpath('$result'))" 2>/dev/null || echo "$result"
    else
        echo "$result"
    fi
}

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
    while IFS= read -r edge1; do
        [[ -z "$edge1" ]] && continue
        local src1 dst1
        src1=$(echo "$edge1" | sed 's/ -> .*//')
        dst1=$(echo "$edge1" | sed 's/.* -> //')

        if grep -qF "${dst1} -> ${src1}" "$edges_file" 2>/dev/null; then
            cycles=$(echo "$cycles" | jq --arg src "$src1" --arg dst "$dst1" \
                '. + [{"path": [$src, $dst, $src], "severity": "error"}]')
        fi
    done < "$edges_file"

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

# ============================================================
# Architecture Rule Validation (MP2.3)
# ============================================================

# Load architecture rules from YAML file
load_arch_rules() {
    local rules_file="$1"

    if [[ ! -f "$rules_file" ]]; then
        echo '{"rules": [], "config": {"on_violation": "warn"}}'
        return
    fi

    # Simple YAML to JSON conversion for our format
    local rules="[]"
    local in_rules=false
    local current_rule="{}"
    local in_cannot_import=false
    local cannot_import_list="[]"
    local config='{"on_violation": "warn"}'
    local in_config=false
    local whitelist="[]"
    local in_whitelist=false
    local ignore_list="[]"
    local in_ignore=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Detect section starts
        if [[ "$line" =~ ^rules:[[:space:]]*$ ]]; then
            in_rules=true
            in_config=false
            continue
        fi

        if [[ "$line" =~ ^config:[[:space:]]*$ ]]; then
            in_config=true
            in_rules=false
            continue
        fi

        if [[ "$in_config" == "true" ]]; then
            if [[ "$line" =~ ^[[:space:]]+on_violation:[[:space:]]*(.+)$ ]]; then
                local val="${BASH_REMATCH[1]}"
                val="${val//\"/}"
                val="${val//\'/}"
                config=$(echo "$config" | jq --arg v "$val" '.on_violation = $v')
                in_ignore=false
            elif [[ "$line" =~ ^[[:space:]]+ignore:[[:space:]]*$ ]]; then
                in_ignore=true
                continue
            fi

            if [[ "$in_ignore" == "true" && "$line" =~ ^[[:space:]]+-[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                ignore_list=$(echo "$ignore_list" | jq --arg v "${BASH_REMATCH[1]}" '. + [$v]')
            fi
        fi

        if [[ "$in_rules" == "true" ]]; then
            # New rule starts with "- name:"
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                # Save previous rule if exists
                if [[ $(echo "$current_rule" | jq 'has("name")') == "true" ]]; then
                    current_rule=$(echo "$current_rule" | jq --argjson ci "$cannot_import_list" '.cannot_import = $ci')
                    current_rule=$(echo "$current_rule" | jq --argjson wl "$whitelist" '.whitelist = $wl')
                    rules=$(echo "$rules" | jq --argjson rule "$current_rule" '. + [$rule]')
                fi

                current_rule=$(jq -n --arg name "${BASH_REMATCH[1]}" '{"name": $name}')
                cannot_import_list="[]"
                whitelist="[]"
                in_cannot_import=false
                in_whitelist=false
                continue
            fi

            # Parse rule properties
            if [[ "$line" =~ ^[[:space:]]+from:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                current_rule=$(echo "$current_rule" | jq --arg v "${BASH_REMATCH[1]}" '.from = $v')
            fi

            if [[ "$line" =~ ^[[:space:]]+severity:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                current_rule=$(echo "$current_rule" | jq --arg v "${BASH_REMATCH[1]}" '.severity = $v')
            fi

            if [[ "$line" =~ ^[[:space:]]+type:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                current_rule=$(echo "$current_rule" | jq --arg v "${BASH_REMATCH[1]}" '.type = $v')
            fi

            if [[ "$line" =~ ^[[:space:]]+scope:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                current_rule=$(echo "$current_rule" | jq --arg v "${BASH_REMATCH[1]}" '.scope = $v')
            fi

            if [[ "$line" =~ ^[[:space:]]+cannot_import:[[:space:]]*$ ]]; then
                in_cannot_import=true
                in_whitelist=false
                continue
            fi

            if [[ "$line" =~ ^[[:space:]]+whitelist:[[:space:]]*$ ]]; then
                in_whitelist=true
                in_cannot_import=false
                continue
            fi

            if [[ "$in_cannot_import" == "true" && "$line" =~ ^[[:space:]]+-[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                cannot_import_list=$(echo "$cannot_import_list" | jq --arg v "${BASH_REMATCH[1]}" '. + [$v]')
            fi

            if [[ "$in_whitelist" == "true" && "$line" =~ ^[[:space:]]+-[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                whitelist=$(echo "$whitelist" | jq --arg v "${BASH_REMATCH[1]}" '. + [$v]')
            fi
        fi
    done < "$rules_file"

    # Save last rule
    if [[ $(echo "$current_rule" | jq 'has("name")') == "true" ]]; then
        current_rule=$(echo "$current_rule" | jq --argjson ci "$cannot_import_list" '.cannot_import = $ci')
        current_rule=$(echo "$current_rule" | jq --argjson wl "$whitelist" '.whitelist = $wl')
        rules=$(echo "$rules" | jq --argjson rule "$current_rule" '. + [$rule]')
    fi

    config=$(echo "$config" | jq --argjson ignore "$ignore_list" '.ignore = $ignore')
    echo "{\"rules\": $rules, \"config\": $config}"
}

# Check if path matches glob pattern
match_glob() {
    local path="$1"
    local pattern="$2"

    # Convert glob to regex
    local regex="${pattern//\*\*/.*}"
    regex="${regex//\*/[^/]*}"
    regex="^${regex}$"

    [[ "$path" =~ $regex ]]
}

normalize_rel_path() {
    local path="$1"
    local result
    result=$(realpath --relative-to="$(pwd)" "$path" 2>/dev/null || echo "$path")
    # Remove leading ./
    result="${result#./}"
    echo "$result"
}

matches_pattern_list() {
    local path="$1"
    local patterns_json="$2"

    if [[ -z "$patterns_json" || "$patterns_json" == "null" ]]; then
        return 1
    fi

    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        if match_glob "$path" "$pattern"; then
            return 0
        fi
    done < <(echo "$patterns_json" | jq -r '.[]' 2>/dev/null)

    return 1
}

# Check architecture rule violations
check_rule_violations() {
    local scope="$1"
    local rules_json="$2"

    local temp_violations
    temp_violations=$(mktemp)
    echo "[]" > "$temp_violations"

    local ignore
    ignore=$(echo "$rules_json" | jq '.config.ignore // []')

    # Get import rules (not cycle-detection type)
    local import_rules
    import_rules=$(echo "$rules_json" | jq '.rules | map(select(.type != "cycle-detection" and .from != null))')

    # Collect files first to avoid subshell issues
    local files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
    done < <(find "$scope" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) 2>/dev/null)

    for file in "${files[@]}"; do
        local rel_path
        rel_path=$(normalize_rel_path "$file")
        if matches_pattern_list "$rel_path" "$ignore"; then
            continue
        fi

        # Collect rules
        local rules_arr=()
        while IFS= read -r rule; do
            [[ -n "$rule" ]] && rules_arr+=("$rule")
        done < <(echo "$import_rules" | jq -c '.[]' 2>/dev/null)

        for rule in "${rules_arr[@]}"; do
            local from_pattern
            from_pattern=$(echo "$rule" | jq -r '.from // ""')

            [[ -z "$from_pattern" ]] && continue

            # Check if file matches "from" pattern
            if match_glob "$rel_path" "$from_pattern"; then
                local cannot_import
                cannot_import=$(echo "$rule" | jq -c '.cannot_import // []')
                local rule_name
                rule_name=$(echo "$rule" | jq -r '.name')
                local severity
                severity=$(echo "$rule" | jq -r '.severity // "error"')

                # Check imports
                local imports
                imports=$(extract_imports "$file")

                # Collect imports
                local imps_arr=()
                while IFS= read -r imp; do
                    [[ -n "$imp" ]] && imps_arr+=("$imp")
                done < <(echo "$imports" | jq -c '.[]' 2>/dev/null)

                for imp in "${imps_arr[@]}"; do
                    local target
                    target=$(echo "$imp" | jq -r '.target')
                    local line
                    line=$(echo "$imp" | jq -r '.line')

                    local resolved
                    resolved=$(resolve_import_path "$file" "$target")
                    [[ -z "$resolved" ]] && continue

                    local rel_resolved
                    rel_resolved=$(normalize_rel_path "$resolved")
                    if matches_pattern_list "$rel_resolved" "$ignore"; then
                        continue
                    fi

                    # Collect patterns
                    local patterns_arr=()
                    while IFS= read -r pattern; do
                        [[ -n "$pattern" ]] && patterns_arr+=("$pattern")
                    done < <(echo "$cannot_import" | jq -r '.[]' 2>/dev/null)

                    for pattern in "${patterns_arr[@]}"; do
                        if match_glob "$rel_resolved" "$pattern"; then
                            local current
                            current=$(cat "$temp_violations")
                            echo "$current" | jq \
                                --arg rule "$rule_name" \
                                --arg severity "$severity" \
                                --arg source "$rel_path" \
                                --arg target "$rel_resolved" \
                                --argjson line "$line" \
                                --arg msg "Violation of rule '$rule_name': $rel_path imports $rel_resolved" \
                                '. + [{"rule": $rule, "severity": $severity, "source": $source, "target": $target, "line": $line, "message": $msg}]' > "$temp_violations"
                        fi
                    done
                done
            fi
        done
    done

    cat "$temp_violations"
    rm -f "$temp_violations"
}

check_rule_violations_for_files() {
    local rules_json="$1"
    shift
    local files=("$@")

    local violations="[]"
    local ignore
    ignore=$(echo "$rules_json" | jq '.config.ignore // []')

    local import_rules
    import_rules=$(echo "$rules_json" | jq '.rules | map(select(.type != "cycle-detection" and .from != null))')

    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue
        local rel_path
        rel_path=$(normalize_rel_path "$file")
        if matches_pattern_list "$rel_path" "$ignore"; then
            continue
        fi

        while IFS= read -r rule; do
            local from_pattern
            from_pattern=$(echo "$rule" | jq -r '.from // ""')

            [[ -z "$from_pattern" ]] && continue

            if match_glob "$rel_path" "$from_pattern"; then
                local cannot_import
                cannot_import=$(echo "$rule" | jq -c '.cannot_import // []')
                local rule_name
                rule_name=$(echo "$rule" | jq -r '.name')
                local severity
                severity=$(echo "$rule" | jq -r '.severity // "error"')

                local imports
                imports=$(extract_imports "$file")

                while IFS= read -r imp; do
                    local target
                    target=$(echo "$imp" | jq -r '.target')
                    local line
                    line=$(echo "$imp" | jq -r '.line')

                    local resolved
                    resolved=$(resolve_import_path "$file" "$target")
                    [[ -z "$resolved" ]] && continue

                    local rel_resolved
                    rel_resolved=$(normalize_rel_path "$resolved")
                    if matches_pattern_list "$rel_resolved" "$ignore"; then
                        continue
                    fi

                    while IFS= read -r pattern; do
                        if match_glob "$rel_resolved" "$pattern"; then
                            violations=$(echo "$violations" | jq \
                                --arg rule "$rule_name" \
                                --arg severity "$severity" \
                                --arg source "$rel_path" \
                                --arg target "$rel_resolved" \
                                --argjson line "$line" \
                                --arg msg "Violation of rule '$rule_name': $rel_path imports $rel_resolved" \
                                '. + [{"rule": $rule, "severity": $severity, "source": $source, "target": $target, "line": $line, "message": $msg}]')
                        fi
                    done < <(echo "$cannot_import" | jq -r '.[]' 2>/dev/null)
                done < <(echo "$imports" | jq -c '.[]' 2>/dev/null)
            fi
        done < <(echo "$import_rules" | jq -c '.[]' 2>/dev/null)
    done

    echo "$violations"
}

# Simplified rule checking
check_rule_violations_simple() {
    local scope="$1"
    local rules_file="$2"

    if [[ ! -f "$rules_file" ]]; then
        echo "[]"
        return
    fi
    local rules_json
    rules_json=$(load_arch_rules "$rules_file")
    check_rule_violations "$scope" "$rules_json"
}

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

# ============================================================
# Pre-commit Mode (MP2.5)
# ============================================================

# Get staged files from git
get_staged_files() {
    git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|sh)$' || true
}

# Get first-level dependencies of a file
get_first_level_deps() {
    local file="$1"
    local deps=""

    local imports
    imports=$(extract_imports "$file")

    echo "$imports" | jq -r '.[].target' 2>/dev/null | while read -r target; do
        local resolved
        resolved=$(resolve_import_path "$file" "$target")
        if [[ -n "$resolved" && -f "$resolved" ]]; then
            echo "$resolved"
        fi
    done
}

# ============================================================
# Report Generation (MP2.4)
# ============================================================

generate_report() {
    local violations="$1"
    local cycles="$2"
    local format="$3"
    local config="$4"
    local files_checked="${5:-[]}"

    local total_violations
    total_violations=$(echo "$violations" | jq 'length')
    local total_cycles
    total_cycles=$(echo "$cycles" | jq 'length')

    # Determine if blocked
    local blocked=false
    local on_violation
    on_violation=$(echo "$config" | jq -r '.on_violation // "warn"')

    if [[ "$on_violation" == "block" && ($total_violations -gt 0 || $total_cycles -gt 0) ]]; then
        blocked=true
    fi

    if [[ "$format" == "text" ]]; then
        echo "=== Dependency Guard Report ==="
        echo ""
        echo "Violations: $total_violations"
        echo "Cycles: $total_cycles"
        echo "Blocked: $blocked"
        echo ""

        if [[ $total_violations -gt 0 ]]; then
            echo "--- Violations ---"
            echo "$violations" | jq -r '.[] | "[\(.severity)] \(.source):\(.line) - \(.message)"'
            echo ""
        fi

        if [[ $total_cycles -gt 0 ]]; then
            echo "--- Cycles ---"
            echo "$cycles" | jq -r '.[] | "Cycle: \(.path | join(" -> "))"'
        fi
    else
        jq -n \
            --arg schema_version "$REPORT_SCHEMA_VERSION" \
            --argjson violations "$violations" \
            --argjson cycles "$cycles" \
            --argjson total_violations "$total_violations" \
            --argjson total_cycles "$total_cycles" \
            --argjson blocked "$blocked" \
            --argjson files_checked "$files_checked" \
            '{
                schema_version: $schema_version,
                violations: $violations,
                cycles: $cycles,
                files_checked: $files_checked,
                summary: {
                    total_violations: $total_violations,
                    total_cycles: $total_cycles,
                    blocked: $blocked
                }
            }'
    fi
}

# ============================================================
# Main Entry Point
# ============================================================

main() {
    local mode=""
    local scope="."
    local scope_set=false
    local rules_file="$ARCH_RULES_FILE"
    local format="json"
    local with_deps=false
    local exclude_patterns=""
    local do_orphan_check=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cycles)
                mode="cycles"
                shift
                ;;
            --orphan-check)
                do_orphan_check=true
                if [[ -z "$mode" ]]; then
                    mode="orphan-check"
                fi
                shift
                ;;
            --exclude)
                if [[ -n "$exclude_patterns" ]]; then
                    exclude_patterns="${exclude_patterns}"$'\n'"$2"
                else
                    exclude_patterns="$2"
                fi
                shift 2
                ;;
            --rules)
                rules_file="$2"
                if [[ -z "$mode" ]]; then
                    mode="rules"
                fi
                shift 2
                ;;
            --all)
                mode="all"
                shift
                ;;
            --pre-commit)
                mode="pre-commit"
                shift
                ;;
            --scope)
                scope="$2"
                scope_set=true
                shift 2
                ;;
            --path)
                scope="$2"
                scope_set=true
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --with-deps)
                with_deps=true
                shift
                ;;
            --debug)
                DEBUG="true"
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

    local violations="[]"
    local cycles="[]"
    local files_checked="[]"
    local config='{"on_violation": "warn"}'

    case "$mode" in
        cycles)
            local rules_json=""
            local ignore="[]"
            local whitelist="[]"

            if [[ -f "$rules_file" ]]; then
                rules_json=$(load_arch_rules "$rules_file")
                config=$(echo "$rules_json" | jq '.config')
                ignore=$(echo "$rules_json" | jq '.config.ignore // []')
                local cycle_rule
                cycle_rule=$(echo "$rules_json" | jq '.rules | map(select(.type == "cycle-detection")) | .[0] // {}')
                whitelist=$(echo "$cycle_rule" | jq '.whitelist // []')
                if [[ "$scope_set" == "false" ]]; then
                    local rule_scope
                    rule_scope=$(echo "$cycle_rule" | jq -r '.scope // ""')
                    if [[ -n "$rule_scope" ]]; then
                        scope="$rule_scope"
                    fi
                fi
            fi

            cycles=$(detect_cycles_simple "$scope" "$whitelist" "$ignore")

            # Handle combined orphan-check with cycles
            if [[ "$do_orphan_check" == "true" ]]; then
                local orphan_result
                orphan_result=$(detect_orphans "$scope" "$exclude_patterns")
                local orphans
                orphans=$(echo "$orphan_result" | jq '.orphans')
                local orphan_summary
                orphan_summary=$(echo "$orphan_result" | jq '.summary')

                # Generate combined report
                local total_cycles
                total_cycles=$(echo "$cycles" | jq 'length')

                if [[ "$format" == "text" ]]; then
                    echo "=== Dependency Guard Report (Combined) ==="
                    echo ""
                    echo "Cycles: $total_cycles"
                    echo "Orphans: $(echo "$orphan_summary" | jq '.orphan_count')"
                    echo ""
                    if [[ $total_cycles -gt 0 ]]; then
                        echo "--- Cycles ---"
                        echo "$cycles" | jq -r '.[] | "Cycle: \(.path | join(" -> "))"'
                        echo ""
                    fi
                    if [[ $(echo "$orphan_summary" | jq '.orphan_count') -gt 0 ]]; then
                        echo "--- Orphan Modules ---"
                        echo "$orphans" | jq -r '.[]'
                    fi
                else
                    jq -n \
                        --arg schema_version "$REPORT_SCHEMA_VERSION" \
                        --argjson cycles "$cycles" \
                        --argjson orphans "$orphans" \
                        --argjson total_cycles "$total_cycles" \
                        --argjson orphan_summary "$orphan_summary" \
                        '{
                            schema_version: $schema_version,
                            cycles: $cycles,
                            orphans: $orphans,
                            summary: {
                                total_cycles: $total_cycles,
                                total_nodes: $orphan_summary.total_nodes,
                                orphan_count: $orphan_summary.orphan_count,
                                orphan_ratio: $orphan_summary.orphan_ratio
                            }
                        }'
                fi
                exit 0
            fi
            ;;
        rules)
            if [[ -f "$rules_file" ]]; then
                local rules_json
                rules_json=$(load_arch_rules "$rules_file")
                config=$(echo "$rules_json" | jq '.config')
                violations=$(check_rule_violations "$scope" "$rules_json")
            fi
            ;;
        orphan-check)
            local orphan_result
            orphan_result=$(detect_orphans "$scope" "$exclude_patterns")

            # Output orphan-specific report
            if [[ "$format" == "text" ]]; then
                echo "=== Orphan Detection Report ==="
                echo ""
                local orphan_count
                orphan_count=$(echo "$orphan_result" | jq '.summary.orphan_count')
                local total_nodes
                total_nodes=$(echo "$orphan_result" | jq '.summary.total_nodes')
                echo "Total nodes: $total_nodes"
                echo "Orphan count: $orphan_count"
                echo ""
                if [[ "$orphan_count" -gt 0 ]]; then
                    echo "--- Orphan Modules ---"
                    echo "$orphan_result" | jq -r '.orphans[]'
                fi
            else
                # Merge orphan result with standard report structure
                local orphans
                orphans=$(echo "$orphan_result" | jq '.orphans')
                local orphan_summary
                orphan_summary=$(echo "$orphan_result" | jq '.summary')

                jq -n \
                    --arg schema_version "$REPORT_SCHEMA_VERSION" \
                    --argjson orphans "$orphans" \
                    --argjson summary "$orphan_summary" \
                    '{
                        schema_version: $schema_version,
                        orphans: $orphans,
                        summary: $summary
                    }'
            fi
            exit 0
            ;;
        all)
            local rules_json=""
            local ignore="[]"
            local whitelist="[]"
            if [[ -f "$rules_file" ]]; then
                rules_json=$(load_arch_rules "$rules_file")
                config=$(echo "$rules_json" | jq '.config')
                ignore=$(echo "$rules_json" | jq '.config.ignore // []')
                local cycle_rule
                cycle_rule=$(echo "$rules_json" | jq '.rules | map(select(.type == "cycle-detection")) | .[0] // {}')
                whitelist=$(echo "$cycle_rule" | jq '.whitelist // []')
                if [[ "$scope_set" == "false" ]]; then
                    local rule_scope
                    rule_scope=$(echo "$cycle_rule" | jq -r '.scope // ""')
                    if [[ -n "$rule_scope" ]]; then
                        scope="$rule_scope"
                    fi
                fi
                violations=$(check_rule_violations "$scope" "$rules_json")
            fi
            cycles=$(detect_cycles_simple "$scope" "$whitelist" "$ignore")
            ;;
        pre-commit)
            local staged_files
            staged_files=$(get_staged_files)

            if [[ -z "$staged_files" ]]; then
                generate_report "[]" "[]" "$format" "$config" "[]"
                exit 0
            fi

            # Build files list
            local files_to_check=()
            while IFS= read -r file; do
                [[ -n "$file" ]] && files_to_check+=("$file")
            done <<< "$staged_files"

            # Add dependencies if requested
            if [[ "$with_deps" == "true" ]]; then
                for file in "${files_to_check[@]}"; do
                    while IFS= read -r dep; do
                        [[ -n "$dep" ]] && files_to_check+=("$dep")
                    done < <(get_first_level_deps "$file")
                done
            fi

            local rules_json=""
            local ignore="[]"
            local whitelist="[]"
            if [[ -f "$rules_file" ]]; then
                rules_json=$(load_arch_rules "$rules_file")
                config=$(echo "$rules_json" | jq '.config')
                ignore=$(echo "$rules_json" | jq '.config.ignore // []')
                local cycle_rule
                cycle_rule=$(echo "$rules_json" | jq '.rules | map(select(.type == "cycle-detection")) | .[0] // {}')
                whitelist=$(echo "$cycle_rule" | jq '.whitelist // []')
            fi

            # Normalize, filter, and dedupe
            local normalized_files=()
            for file in "${files_to_check[@]}"; do
                [[ -f "$file" ]] || continue
                local rel
                rel=$(normalize_rel_path "$file")
                if matches_pattern_list "$rel" "$ignore"; then
                    continue
                fi
                normalized_files+=("$rel")
            done

            local deduped_files=()
            while IFS= read -r file; do
                deduped_files+=("$file")
            done < <(printf '%s\n' "${normalized_files[@]}" | awk 'NF' | awk '!seen[$0]++')
            files_to_check=("${deduped_files[@]}")

            # Build files_checked JSON
            files_checked="[]"
            for file in "${files_to_check[@]}"; do
                files_checked=$(echo "$files_checked" | jq --arg f "$file" '. + [$f]')
            done
            files_checked=$(echo "$files_checked" | jq 'unique')

            if [[ -n "$rules_json" ]]; then
                violations=$(check_rule_violations_for_files "$rules_json" "${files_to_check[@]}")
            fi

            if [[ "${#files_to_check[@]}" -gt 0 ]]; then
                cycles=$(detect_cycles_for_files "$whitelist" "$ignore" "${files_to_check[@]}")
            fi
            ;;
        "")
            show_help
            exit 0
            ;;
    esac

    generate_report "$violations" "$cycles" "$format" "$config" "$files_checked"

    # Exit with error if blocked
    local blocked
    blocked=$(generate_report "$violations" "$cycles" "json" "$config" "$files_checked" | jq -r '.summary.blocked')
    if [[ "$blocked" == "true" ]]; then
        exit 1
    fi
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
