#!/bin/bash
# dependency-guard-rules.sh - Architecture Rule Validation Module
#
# Version: 1.0.0
# Purpose: Load and validate architecture rules
# Part of: dependency-guard.sh modular architecture
#
# Trace: AC-006 ~ AC-008, AC-012, AC-N03, AC-N04
# Change: augment-upgrade-phase2

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

# Check if path matches any pattern in JSON array
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

# Check rule violations for specific files
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
