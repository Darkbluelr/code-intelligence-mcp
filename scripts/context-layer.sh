#!/bin/bash
# context-layer.sh - Context Layer Enhancement (Commit Classification + Bug History)
#
# Version: 1.0.0
# Purpose: Semantic commit classification and bug fix history extraction
# Depends: jq, git
#
# Usage:
#   context-layer.sh --classify <sha>
#   context-layer.sh --classify-batch --since "90 days ago"
#   context-layer.sh --bug-history --file <path>
#   context-layer.sh --index [--days 90]
#   context-layer.sh --help
#
# Environment Variables:
#   GIT_LOG_CMD           - Git log command (default: git log)
#   CONTEXT_INDEX_PATH    - Index file path (default: .devbooks/context-index.json)
#   BUG_HISTORY_DAYS      - Default time window (default: 90)
#   DEBUG                 - Enable debug output (default: false)
#
# Trace: AC-009 ~ AC-011, AC-014
# Change: augment-upgrade-phase2

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCHEMA_VERSION="1.0.0"
: "${GIT_LOG_CMD:=git log}"
: "${CONTEXT_INDEX_PATH:=.devbooks/context-index.json}"
: "${BUG_HISTORY_DAYS:=90}"
: "${DEBUG:=false}"

# ============================================================
# Utility Functions
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/common.sh"
COMMON_LIB_LOADED=false
if [[ -f "$COMMON_LIB" ]]; then
    # shellcheck disable=SC2034  # LOG_PREFIX is used by common.sh
    LOG_PREFIX="ContextLayer"
    # shellcheck source=common.sh
    source "$COMMON_LIB"
    COMMON_LIB_LOADED=true
fi

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[DEBUG] $1" >&2
    fi
}

if [[ "$COMMON_LIB_LOADED" != "true" ]]; then
    log_info() {
        echo "[INFO] $1" >&2
    }

    log_warn() {
        echo "[WARN] $1" >&2
    }

    log_error() {
        echo "[ERROR] $1" >&2
    }
fi

read -r -a GIT_LOG_CMD_ARRAY <<< "$GIT_LOG_CMD"
git_log() {
    "${GIT_LOG_CMD_ARRAY[@]}" "$@"
}

show_help() {
    cat << 'EOF'
context-layer.sh - Context Layer Enhancement (Commit Classification + Bug History)

Usage:
  context-layer.sh --classify <sha>
  context-layer.sh --classify-batch --since "90 days ago"
  context-layer.sh --bug-history --file <path>
  context-layer.sh --index [--days 90]
  context-layer.sh --help

Options:
  --classify <sha>      Classify a single commit by SHA
  --classify-batch      Classify multiple commits
  --since <date>        Start date for batch classification (default: 90 days ago)
  --bug-history         Extract bug fix history
  --file <path>         Target file for bug history
  --index               Generate context index
  --days <n>            Time window in days (default: 90)
  --format <type>       Output format: json or text (default: json)
  --debug               Enable debug output
  --help                Show this help message

Environment Variables:
  GIT_LOG_CMD           Git log command (default: git log)
  CONTEXT_INDEX_PATH    Index file path (default: .devbooks/context-index.json)
  BUG_HISTORY_DAYS      Default time window (default: 90)

Examples:
  # Classify a commit
  context-layer.sh --classify abc123

  # Classify all commits from last 30 days
  context-layer.sh --classify-batch --since "30 days ago"

  # Get bug history for a file
  context-layer.sh --bug-history --file src/server.ts

  # Generate context index
  context-layer.sh --index --days 90
EOF
}

# ============================================================
# Commit Classification (MP3.1)
# ============================================================

# Classification rules with priority (higher index = higher priority)
# REQ-CTX-001: Commit semantic classification
# Returns: type and confidence

classify_commit_message() {
    local message="$1"
    local msg_lower
    msg_lower=$(echo "$message" | tr '[:upper:]' '[:lower:]')

    # Priority 1: fix (highest)
    if declare -f is_bug_fix_message &>/dev/null; then
        if is_bug_fix_message "$message"; then
            echo "fix"
            echo "0.95"
            return
        fi
    else
        if [[ "$msg_lower" =~ ^fix[:\([:space:]] ]] || \
           [[ "$msg_lower" =~ (bug|issue|error|crash|broken|fail) ]]; then
            echo "fix"
            echo "0.95"
            return
        fi
    fi

    # Priority 2: feat
    if [[ "$msg_lower" =~ ^feat[:\([:space:]] ]] || \
       [[ "$msg_lower" =~ (^add[[:space:]]|^new[[:space:]]|implement|feature) ]]; then
        echo "feat"
        echo "0.95"
        return
    fi

    # Priority 3: refactor
    if [[ "$msg_lower" =~ ^refactor[:\([:space:]] ]] || \
       [[ "$msg_lower" =~ (refact|clean[[:space:]]up|improve|simplif|reorgani) ]]; then
        echo "refactor"
        echo "0.90"
        return
    fi

    # Priority 4: docs
    if [[ "$msg_lower" =~ ^docs[:\([:space:]] ]] || \
       [[ "$msg_lower" =~ (document|readme|comment|typo) ]]; then
        echo "docs"
        echo "0.90"
        return
    fi

    # Priority 5: chore (explicit)
    if [[ "$msg_lower" =~ ^chore[:\([:space:]] ]] || \
       [[ "$msg_lower" =~ (^build[:\([:space:]]|^ci[:\([:space:]]|dep|bump|version|release|merge) ]]; then
        echo "chore"
        echo "0.90"
        return
    fi

    # Default: chore with low confidence
    # SC-CTX-003: Ambiguous commits default to chore with confidence < 0.8
    echo "chore"
    echo "0.70"
}

# Classify a single commit by SHA
# REQ: CT-CTX-001, CT-CTX-002
classify_commit() {
    local sha="$1"
    local format="${2:-json}"

    # Get commit message
    local message
    message=$(git_log -1 --format="%s" "$sha" 2>/dev/null)

    if [[ -z "$message" ]]; then
        log_error "Could not find commit: $sha"
        return 1
    fi

    local result
    result=$(classify_commit_message "$message")
    local commit_type
    commit_type=$(echo "$result" | head -1)
    local confidence
    confidence=$(echo "$result" | tail -1)

    if [[ "$format" == "json" ]]; then
        jq -n \
            --arg sha "$sha" \
            --arg type "$commit_type" \
            --arg confidence "$confidence" \
            --arg message "$message" \
            '{
                sha: $sha,
                type: $type,
                confidence: ($confidence | tonumber),
                message: $message
            }'
    else
        echo "SHA: $sha"
        echo "Type: $commit_type"
        echo "Confidence: $confidence"
        echo "Message: $message"
    fi
}

# Classify batch of commits
# REQ: CT-CTX-008 - Accuracy >= 90%
classify_batch() {
    local since="${1:-90 days ago}"
    local format="${2:-json}"

    local results="[]"

    while IFS= read -r sha; do
        [[ -z "$sha" ]] && continue

        local message
        message=$(git_log -1 --format="%s" "$sha" 2>/dev/null)
        [[ -z "$message" ]] && continue

        local result
        result=$(classify_commit_message "$message")
        local commit_type
        commit_type=$(echo "$result" | head -1)
        local confidence
        confidence=$(echo "$result" | tail -1)

        results=$(echo "$results" | jq --arg sha "$sha" --arg type "$commit_type" \
            --arg confidence "$confidence" --arg message "$message" \
            '. + [{sha: $sha, type: $type, confidence: ($confidence | tonumber), message: $message}]')
    done < <(git_log --format="%H" --since="$since" 2>/dev/null)

    if [[ "$format" == "json" ]]; then
        jq -n --argjson results "$results" \
            --arg schema_version "$SCHEMA_VERSION" \
            '{
                schema_version: $schema_version,
                commits: $results,
                count: ($results | length)
            }'
    else
        echo "Classified $(echo "$results" | jq 'length') commits"
        echo "$results" | jq -r '.[] | "\(.sha[0:7]) \(.type) (\(.confidence)) - \(.message[0:50])"'
    fi
}

# ============================================================
# Bug Fix History Extraction (MP3.2)
# ============================================================

# Get bug fix history for a specific file
# REQ-CTX-002: Bug fix history extraction
# REQ: CT-CTX-004
get_bug_history_for_file() {
    local file_path="$1"
    local days="${2:-$BUG_HISTORY_DAYS}"
    local format="${3:-json}"

    if [[ ! -f "$file_path" ]]; then
        # File might have been deleted, still try to get history
        log_debug "File not found: $file_path (may have been deleted)"
    fi

    local bug_fix_commits="[]"
    local bug_fix_count=0
    local last_bug_fix=""

    # Get commits that modified this file
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local sha
        sha=$(echo "$line" | cut -d'|' -f1)
        local date
        date=$(echo "$line" | cut -d'|' -f2)
        local message
        message=$(echo "$line" | cut -d'|' -f3-)

        # Classify commit
        local result
        result=$(classify_commit_message "$message")
        local commit_type
        commit_type=$(echo "$result" | head -1)

        if [[ "$commit_type" == "fix" ]]; then
            bug_fix_count=$((bug_fix_count + 1))
            bug_fix_commits=$(echo "$bug_fix_commits" | jq --arg sha "$sha" '. + [$sha]')
            if [[ -z "$last_bug_fix" ]]; then
                last_bug_fix="$date"
            fi
        fi
    done < <(git_log --format="%H|%aI|%s" --since="$days days ago" -- "$file_path" 2>/dev/null)

    if [[ "$format" == "json" ]]; then
        jq -n \
            --arg file "$file_path" \
            --argjson bug_fix_count "$bug_fix_count" \
            --argjson bug_fix_commits "$bug_fix_commits" \
            --arg last_bug_fix "${last_bug_fix:-null}" \
            --arg days "$days" \
            '{
                file: $file,
                bug_fix_count: $bug_fix_count,
                bug_fix_commits: $bug_fix_commits,
                last_bug_fix: (if $last_bug_fix == "null" then null else $last_bug_fix end),
                time_window_days: ($days | tonumber)
            }'
    else
        echo "File: $file_path"
        echo "Bug Fix Count: $bug_fix_count"
        echo "Last Bug Fix: ${last_bug_fix:-N/A}"
        echo "Bug Fix Commits: $(echo "$bug_fix_commits" | jq -r 'join(", ")')"
    fi
}

# ============================================================
# Context Index Generation (MP3.3)
# ============================================================

# Generate context index for all files
# REQ-CTX-004: Context index format
# REQ: CT-CTX-007
generate_context_index() {
    local days="${1:-$BUG_HISTORY_DAYS}"

    log_info "Generating context index (last $days days)..."

    local files="[]"
    local indexed_at
    indexed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Get all files that have commits in the time window
    local tmp_file
    tmp_file=$(mktemp)
    trap "rm -f '$tmp_file'" EXIT

    # Get unique files from git log
    git_log --name-only --format="" --since="$days days ago" 2>/dev/null | \
        grep -v '^$' | sort -u > "$tmp_file" || true

    local file_count
    file_count=$(wc -l < "$tmp_file" | tr -d ' ')
    log_info "Found $file_count files with commits in last $days days"

    # Process each file
    while IFS= read -r file_path; do
        [[ -z "$file_path" ]] && continue

        local commit_types='{"fix": 0, "feat": 0, "refactor": 0, "docs": 0, "chore": 0}'
        local bug_fix_commits="[]"
        local bug_fix_count=0
        local last_bug_fix=""

        # Get commits for this file
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            local sha
            sha=$(echo "$line" | cut -d'|' -f1)
            local date
            date=$(echo "$line" | cut -d'|' -f2)
            local message
            message=$(echo "$line" | cut -d'|' -f3-)

            # Classify commit
            local result
            result=$(classify_commit_message "$message")
            local commit_type
            commit_type=$(echo "$result" | head -1)

            # Update commit type counts
            commit_types=$(echo "$commit_types" | jq --arg type "$commit_type" \
                '.[$type] = (.[$type] // 0) + 1')

            # Track bug fixes
            if [[ "$commit_type" == "fix" ]]; then
                bug_fix_count=$((bug_fix_count + 1))
                bug_fix_commits=$(echo "$bug_fix_commits" | jq --arg sha "$sha" '. + [$sha]')
                if [[ -z "$last_bug_fix" ]]; then
                    last_bug_fix="$date"
                fi
            fi
        done < <(git_log --format="%H|%aI|%s" --since="$days days ago" -- "$file_path" 2>/dev/null)

        # Add file entry
        files=$(echo "$files" | jq \
            --arg path "$file_path" \
            --argjson bug_fix_count "$bug_fix_count" \
            --argjson bug_fix_commits "$bug_fix_commits" \
            --arg last_bug_fix "${last_bug_fix:-null}" \
            --argjson commit_types "$commit_types" \
            '. + [{
                path: $path,
                bug_fix_count: $bug_fix_count,
                bug_fix_commits: $bug_fix_commits,
                last_bug_fix: (if $last_bug_fix == "null" then null else $last_bug_fix end),
                commit_types: $commit_types
            }]')

        log_debug "Processed: $file_path"
    done < "$tmp_file"

    # Generate index JSON
    local index_json
    index_json=$(jq -n \
        --arg schema_version "$SCHEMA_VERSION" \
        --arg indexed_at "$indexed_at" \
        --argjson time_window_days "$days" \
        --argjson files "$files" \
        '{
            schema_version: $schema_version,
            indexed_at: $indexed_at,
            time_window_days: $time_window_days,
            files: $files
        }')

    # Write to file
    local index_dir
    index_dir=$(dirname "$CONTEXT_INDEX_PATH")
    mkdir -p "$index_dir" 2>/dev/null

    echo "$index_json" > "$CONTEXT_INDEX_PATH"
    log_info "Context index written to: $CONTEXT_INDEX_PATH"

    # Output summary
    echo "$index_json"
}

# ============================================================
# Hotspot Integration Helper (MP3.4)
# ============================================================

# Get bug fix ratio for a file (for hotspot-analyzer.sh integration)
get_bug_fix_ratio() {
    local file_path="$1"
    local days="${2:-$BUG_HISTORY_DAYS}"

    local total_commits=0
    local bug_fix_count=0

    # Get commits for this file
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        total_commits=$((total_commits + 1))

        local message
        message=$(echo "$line" | cut -d'|' -f2-)

        local result
        result=$(classify_commit_message "$message")
        local commit_type
        commit_type=$(echo "$result" | head -1)

        if [[ "$commit_type" == "fix" ]]; then
            bug_fix_count=$((bug_fix_count + 1))
        fi
    done < <(git_log --format="%H|%s" --since="$days days ago" -- "$file_path" 2>/dev/null)

    if [[ $total_commits -eq 0 ]]; then
        echo "0.0"
    else
        # Calculate ratio using awk for floating point
        awk -v bug="$bug_fix_count" -v total="$total_commits" 'BEGIN { printf "%.4f", bug / total }'
    fi
}

# ============================================================
# Main Entry Point
# ============================================================

main() {
    local action=""
    local sha=""
    local file_path=""
    local since="90 days ago"
    local days="$BUG_HISTORY_DAYS"
    local format="json"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --classify)
                action="classify"
                if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                    sha="$2"
                    shift
                fi
                shift
                ;;
            --classify-batch)
                action="classify-batch"
                shift
                ;;
            --bug-history)
                action="bug-history"
                shift
                ;;
            --index)
                action="index"
                shift
                ;;
            --file)
                file_path="$2"
                shift 2
                ;;
            --since)
                since="$2"
                shift 2
                ;;
            --days)
                days="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
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
                # Try to use as SHA if no action set
                if [[ -z "$sha" && "$action" == "classify" ]]; then
                    sha="$1"
                fi
                shift
                ;;
        esac
    done

    # Ensure git is available
    if ! command -v git &>/dev/null; then
        log_error "git is required but not installed"
        exit 2
    fi

    # Ensure jq is available
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed"
        exit 2
    fi

    # Ensure we're in a git repo
    if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        log_error "Not inside a git repository"
        exit 3
    fi

    case "$action" in
        classify)
            if [[ -z "$sha" ]]; then
                log_error "Usage: context-layer.sh --classify <sha>"
                exit 1
            fi
            classify_commit "$sha" "$format"
            ;;
        classify-batch)
            classify_batch "$since" "$format"
            ;;
        bug-history)
            if [[ -z "$file_path" ]]; then
                log_error "Usage: context-layer.sh --bug-history --file <path>"
                exit 1
            fi
            get_bug_history_for_file "$file_path" "$days" "$format"
            ;;
        index)
            generate_context_index "$days"
            ;;
        "")
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown action: $action"
            show_help
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
