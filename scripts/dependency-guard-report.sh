#!/bin/bash
# dependency-guard-report.sh - Report Generation and Pre-commit Module
#
# Version: 1.0.0
# Purpose: Generate reports and handle pre-commit checks
# Part of: dependency-guard.sh modular architecture
#
# Trace: AC-006 ~ AC-008, AC-012, AC-N03, AC-N04
# Change: augment-upgrade-phase2

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
