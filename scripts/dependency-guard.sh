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
# Module Loading
# ============================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all module files
source "${SCRIPT_DIR}/dependency-guard-extract.sh"
source "${SCRIPT_DIR}/dependency-guard-check.sh"
source "${SCRIPT_DIR}/dependency-guard-rules.sh"
source "${SCRIPT_DIR}/dependency-guard-orphan.sh"
source "${SCRIPT_DIR}/dependency-guard-report.sh"

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
