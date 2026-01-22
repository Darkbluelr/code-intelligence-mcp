#!/bin/bash
# dependency-guard-extract.sh - Import Extraction Module
#
# Version: 1.0.0
# Purpose: Extract imports from TypeScript/JavaScript/Bash files
# Part of: dependency-guard.sh modular architecture
#
# Trace: AC-006 ~ AC-008, AC-012, AC-N03, AC-N04
# Change: augment-upgrade-phase2

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

    local input_file="$file"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        local target=""

        # Match: import ... from '...' or import ... from "..."
        if [[ "$line" =~ ^[[:space:]]*(import|export)[[:space:]].*from[[:space:]]*[\'\"]([^\'\"]+)[\'\"] ]]; then
            target="${BASH_REMATCH[2]:-}"
            if [[ -n "$target" ]]; then
                local current
                current=$(cat "$temp_imports")
                echo "$current" | jq --arg source "$input_file" --arg target "$target" --argjson line "$line_num" \
                    '. + [{"source": $source, "target": $target, "line": $line}]' > "$temp_imports"
            fi
        fi

        # Match: require('...') or require("...")
        if [[ "$line" =~ require\([[:space:]]*[\'\"]([^\'\"]+)[\'\"]\) ]]; then
            target="${BASH_REMATCH[1]:-}"
            if [[ -n "$target" ]]; then
                local current
                current=$(cat "$temp_imports")
                echo "$current" | jq --arg source "$input_file" --arg target "$target" --argjson line "$line_num" \
                    '. + [{"source": $source, "target": $target, "line": $line}]' > "$temp_imports"
            fi
        fi
    done < "$input_file"

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

    local input_file="$file"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        local target=""

        # Match: source ... or . ...
        if [[ "$line" =~ ^[[:space:]]*(source|\.)[[:space:]]+[\"\']?([^\"\'[:space:]]+)[\"\']? ]]; then
            target="${BASH_REMATCH[2]:-}"
            if [[ -n "$target" ]]; then
                local current
                current=$(cat "$temp_imports")
                echo "$current" | jq --arg source "$input_file" --arg target "$target" --argjson line "$line_num" \
                    '. + [{"source": $source, "target": $target, "line": $line}]' > "$temp_imports"
            fi
        fi
    done < "$input_file"

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

# Normalize path to relative path from current directory
normalize_rel_path() {
    local path="$1"
    local result
    result=$(realpath --relative-to="$(pwd)" "$path" 2>/dev/null || echo "$path")
    # Remove leading ./
    result="${result#./}"
    echo "$result"
}
