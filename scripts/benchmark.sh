#!/bin/bash
# benchmark.sh - Performance Benchmark for Cache and Core Tools
#
# Version: 1.0.0
# Purpose: Validate P95 latency targets for cache operations and queries
# Depends: jq, cache-manager.sh
#
# Usage:
#   benchmark.sh --cache
#   benchmark.sh --full
#   benchmark.sh --all
#
# Trace: AC-N01, AC-N02, AC-N03, AC-N04
# Change: augment-upgrade-phase2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"

# ============================================================
# Configuration
# ============================================================

: "${BENCHMARK_ITERATIONS:=20}"
: "${CACHE_SCRIPT:=$SCRIPT_DIR/cache-manager.sh}"
: "${EVIDENCE_DIR:=$PROJECT_ROOT/evidence}"
FEATURES_CONFIG_FILE="${FEATURES_CONFIG:-$PROJECT_ROOT/config/features.yaml}"

# ============================================================
# Utility Functions
# ============================================================

log_info() {
    echo "[INFO] $1" >&2
}

log_ok() {
    echo "[OK] $1" >&2
}

log_fail() {
    echo "[FAIL] $1" >&2
}

feature_enabled() {
    local feature="$1"

    if [[ -n "${DEVBOOKS_ENABLE_ALL_FEATURES:-}" ]]; then
        return 0
    fi

    if [[ ! -f "$FEATURES_CONFIG_FILE" ]]; then
        return 0
    fi

    local value
    value=$(awk -v feature="$feature" '
        BEGIN { in_features = 0 }
        /^features:/ { in_features = 1; next }
        /^[a-zA-Z]/ && !/^features:/ { in_features = 0 }
        in_features && $0 ~ feature ":" {
            getline
            if ($0 ~ /enabled:/) {
                sub(/^[^:]+:[[:space:]]*/, "")
                gsub(/#.*/, "")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                print
                exit
            }
        }
    ' "$FEATURES_CONFIG_FILE" 2>/dev/null)

    case "$value" in
        false|False|FALSE|no|No|NO|0)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

show_help() {
    cat << 'EOF'
benchmark.sh - Retrieval Benchmark Runner

用法:
  benchmark.sh --dataset <self|public> --queries <file> --output <report.json>
  benchmark.sh --compare <baseline.json> <current.json>
  benchmark.sh --baseline <baseline.json>

选项:
  --dataset <self|public>  数据集类型
  --queries <file>         查询集（JSONL）
  --output <file>          输出报告路径
  --baseline <file>        基线报告（JSON）
  --compare <a> <b>        对比两个报告并检测回归
  --enable-all-features    忽略功能开关配置，强制启用所有功能

兼容模式:
  --cache | --full | --precommit | --all
  --iterations <n>

EOF
}

# Get current time in milliseconds (cross-platform)
get_time_ms() {
    if date +%s%N 2>/dev/null | grep -q 'N'; then
        # date doesn't support %N (macOS)
        if command -v gdate &>/dev/null; then
            echo "$(($(gdate +%s%N) / 1000000))"
        elif command -v perl &>/dev/null; then
            perl -MTime::HiRes -e 'printf "%d\n", Time::HiRes::time() * 1000'
        else
            echo "$(($(date +%s) * 1000))"
        fi
    else
        echo "$(($(date +%s%N) / 1000000))"
    fi
}

# Calculate P95 from array of values
calculate_p95() {
    local values=("$@")
    local count=${#values[@]}

    if [[ $count -lt 1 ]]; then
        echo "0"
        return
    fi

    # Sort values
    local sorted
    sorted=$(printf '%s\n' "${values[@]}" | sort -n)

    # P95 index
    local p95_index
    p95_index=$(awk -v n="$count" 'BEGIN { idx = int(0.95 * n); if (0.95 * n > idx) idx++; print idx }')

    [[ $p95_index -lt 1 ]] && p95_index=1
    [[ $p95_index -gt $count ]] && p95_index=$count

    echo "$sorted" | awk -v idx="$p95_index" 'NR == idx { print; exit }'
}

validate_json_file() {
    local file="$1"

    if [[ -z "$file" || ! -f "$file" ]]; then
        log_fail "baseline file not found: $file"
        return 1
    fi

    if ! jq empty "$file" >/dev/null 2>&1; then
        log_fail "baseline file invalid JSON: $file"
        return 1
    fi

    return 0
}

run_dataset_benchmark() {
    local dataset="$1"
    local queries_file="$2"
    local output_file="$3"

    if [[ -z "$dataset" ]]; then
        log_fail "dataset is required"
        echo "dataset missing" >&2
        return 1
    fi

    case "$dataset" in
        self|public) ;;
        *)
            log_fail "dataset must be self or public"
            echo "dataset invalid" >&2
            return 1
            ;;
    esac

    if [[ -z "$queries_file" || ! -f "$queries_file" ]]; then
        log_fail "queries file not found: $queries_file"
        return 1
    fi

    if [[ -z "$output_file" ]]; then
        log_fail "output file required"
        return 1
    fi

    log_info "Running benchmark on dataset: $dataset"

    local query_count
    query_count=$(wc -l < "$queries_file" | tr -d ' ')
    query_count="${query_count:-0}"

    if [[ "$query_count" -eq 0 ]]; then
        log_fail "queries file is empty"
        return 1
    fi

    local total_rr=0
    local total_recall=0
    local total_precision=0
    local latencies=()
    local valid_queries=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local query expected_files
        query=$(echo "$line" | jq -r '.query // empty' 2>/dev/null)
        [[ -z "$query" ]] && continue

        expected_files=$(echo "$line" | jq -r '.expected[]? // empty' 2>/dev/null)

        local start_ms end_ms latency
        start_ms=$(get_time_ms)

        local results
        if [[ "$dataset" == "self" ]]; then
            results=$(rg -l "$query" "$PROJECT_ROOT/src" "$PROJECT_ROOT/scripts" 2>/dev/null | head -10 || true)
        else
            results=$(rg -l "$query" "$PROJECT_ROOT" 2>/dev/null | head -10 || true)
        fi

        end_ms=$(get_time_ms)
        latency=$((end_ms - start_ms))
        latencies+=("$latency")

        if [[ -n "$expected_files" ]]; then
            local rank=0
            local found=false
            local relevant_count=0
            local retrieved_count=0

            retrieved_count=$(echo "$results" | grep -c . 2>/dev/null || echo 0)
            retrieved_count=$(echo "$retrieved_count" | tr -d '\n\r ')

            while IFS= read -r expected; do
                [[ -z "$expected" ]] && continue
                relevant_count=$((relevant_count + 1))

                local current_rank=0
                while IFS= read -r result; do
                    [[ -z "$result" ]] && continue
                    current_rank=$((current_rank + 1))

                    if echo "$result" | grep -qF "$expected"; then
                        if [[ "$found" == "false" ]]; then
                            rank=$current_rank
                            found=true
                        fi
                        break
                    fi
                done <<< "$results"
            done <<< "$expected_files"

            if [[ "$found" == "true" && "$rank" -gt 0 ]]; then
                local rr
                rr=$(awk -v r="$rank" 'BEGIN {printf "%.6f", 1.0/r}')
                total_rr=$(awk -v t="$total_rr" -v r="$rr" 'BEGIN {printf "%.6f", t+r}')
            fi

            if [[ "$found" == "true" ]]; then
                total_recall=$(awk -v t="$total_recall" 'BEGIN {printf "%.6f", t+1.0}')
            fi

            if [[ "$retrieved_count" -gt 0 && "$found" == "true" ]]; then
                local prec
                prec=$(awk -v rel="$relevant_count" -v ret="$retrieved_count" 'BEGIN {printf "%.6f", rel/ret}')
                total_precision=$(awk -v t="$total_precision" -v p="$prec" 'BEGIN {printf "%.6f", t+p}')
            fi
        fi

        valid_queries=$((valid_queries + 1))
    done < "$queries_file"

    if [[ "$valid_queries" -eq 0 ]]; then
        log_fail "no valid queries found"
        return 1
    fi

    local mrr recall precision p95_latency
    mrr=$(awk -v t="$total_rr" -v n="$valid_queries" 'BEGIN {printf "%.6f", t/n}')
    recall=$(awk -v t="$total_recall" -v n="$valid_queries" 'BEGIN {printf "%.6f", t/n}')
    precision=$(awk -v t="$total_precision" -v n="$valid_queries" 'BEGIN {printf "%.6f", t/n}')
    p95_latency=$(calculate_p95 "${latencies[@]}")

    mkdir -p "$(dirname "$output_file")"
    jq -n \
        --argjson mrr "$mrr" \
        --argjson recall "$recall" \
        --argjson precision "$precision" \
        --argjson p95 "$p95_latency" \
        --argjson queries "$valid_queries" \
        '{
          mrr_at_10: $mrr,
          recall_at_10: $recall,
          precision_at_10: $precision,
          p95_latency_ms: $p95,
          queries: $queries
        }' > "$output_file"

    log_ok "Benchmark report saved to $output_file"
    log_info "MRR@10: $mrr, Recall@10: $recall, P95: ${p95_latency}ms"
}

compare_reports() {
    local baseline_file="$1"
    local current_file="$2"

    if ! validate_json_file "$baseline_file"; then
        return 1
    fi

    if [[ -z "$current_file" || ! -f "$current_file" ]]; then
        log_fail "current file not found: $current_file"
        return 1
    fi

    if ! jq empty "$current_file" >/dev/null 2>&1; then
        log_fail "current file invalid JSON: $current_file"
        return 1
    fi

    local base_mrr base_recall base_p95 curr_mrr curr_recall curr_p95
    base_mrr=$(jq -r '.mrr_at_10 // 0' "$baseline_file")
    base_recall=$(jq -r '.recall_at_10 // 0' "$baseline_file")
    base_p95=$(jq -r '.p95_latency_ms // 0' "$baseline_file")
    curr_mrr=$(jq -r '.mrr_at_10 // 0' "$current_file")
    curr_recall=$(jq -r '.recall_at_10 // 0' "$current_file")
    curr_p95=$(jq -r '.p95_latency_ms // 0' "$current_file")

    local mrr_threshold recall_threshold p95_threshold
    if [[ -n "${BENCHMARK_REGRESSION_THRESHOLD:-}" ]]; then
        local threshold
        threshold="${BENCHMARK_REGRESSION_THRESHOLD}"
        if ! echo "$threshold" | grep -qE '^[0-9]+\.?[0-9]*$'; then
            log_fail "invalid BENCHMARK_REGRESSION_THRESHOLD: $threshold"
            return 1
        fi
        mrr_threshold=$(awk -v base="$base_mrr" -v thr="$threshold" 'BEGIN {printf "%.6f", base * (1 - thr)}')
        recall_threshold=$(awk -v base="$base_recall" -v thr="$threshold" 'BEGIN {printf "%.6f", base * (1 - thr)}')
        p95_threshold=$(awk -v base="$base_p95" -v thr="$threshold" 'BEGIN {printf "%.2f", base * (1 + thr)}')
    else
        mrr_threshold=$(awk -v base="$base_mrr" 'BEGIN {printf "%.6f", base * 0.95}')
        recall_threshold=$(awk -v base="$base_recall" 'BEGIN {printf "%.6f", base * 0.95}')
        p95_threshold=$(awk -v base="$base_p95" 'BEGIN {printf "%.2f", base * 1.10}')
    fi

    local regression=false
    if awk -v curr="$curr_mrr" -v thr="$mrr_threshold" 'BEGIN {exit !(curr < thr)}'; then
        regression=true
    fi
    if awk -v curr="$curr_recall" -v thr="$recall_threshold" 'BEGIN {exit !(curr < thr)}'; then
        regression=true
    fi
    if awk -v curr="$curr_p95" -v thr="$p95_threshold" 'BEGIN {exit !(curr > thr)}'; then
        regression=true
    fi

    if [[ "$regression" == "true" ]]; then
        echo "regression detected"
        return 1
    fi

    echo "no regression detected"
    return 0
}

# ============================================================
# Cache Benchmark (AC-N01)
# ============================================================

benchmark_cache() {
    log_info "Running cache benchmark ($BENCHMARK_ITERATIONS iterations)..."

    # Setup
    local test_file="$PROJECT_ROOT/scripts/common.sh"
    if [[ ! -f "$test_file" ]]; then
        log_fail "Test file not found: $test_file"
        return 1
    fi

    local query_hash="benchmark-test-$(date +%s)"
    local test_value="benchmark result data for testing"

    # Clear any existing cache for this test
    export CACHE_DIR="${TMPDIR:-/tmp}/.ci-cache-benchmark"
    rm -rf "$CACHE_DIR" 2>/dev/null
    mkdir -p "$CACHE_DIR/l2"

    # First, set a cache entry
    "$CACHE_SCRIPT" --set "$test_file" --query "$query_hash" --value "$test_value" 2>/dev/null

    # Benchmark cache hits
    local latencies=()

    for ((i=1; i<=BENCHMARK_ITERATIONS; i++)); do
        local start_ms end_ms latency
        start_ms=$(get_time_ms)

        "$CACHE_SCRIPT" --get "$test_file" --query "$query_hash" >/dev/null 2>&1 || true

        end_ms=$(get_time_ms)
        latency=$((end_ms - start_ms))
        latencies+=("$latency")
    done

    # Calculate P95
    local p95
    p95=$(calculate_p95 "${latencies[@]}")

    # Cleanup
    rm -rf "$CACHE_DIR" 2>/dev/null

    # Report
    local target=100
    if [[ $p95 -lt $target ]]; then
        log_ok "Cache hit P95: ${p95}ms (target: <${target}ms)"
        echo "PASS"
    else
        log_fail "Cache hit P95: ${p95}ms (target: <${target}ms)"
        echo "FAIL"
    fi

    # Return metrics
    echo "cache_hit_p95_ms=$p95"
}

# ============================================================
# Full Query Benchmark (AC-N02)
# ============================================================

benchmark_full_query() {
    log_info "Running full query benchmark (simulated)..."

    # Since we don't have a real query endpoint here,
    # we simulate by timing cache-manager operations

    local test_file="$PROJECT_ROOT/scripts/common.sh"
    local latencies=()

    export CACHE_DIR="${TMPDIR:-/tmp}/.ci-cache-benchmark"
    rm -rf "$CACHE_DIR" 2>/dev/null

    for ((i=1; i<=BENCHMARK_ITERATIONS; i++)); do
        local query_hash="query-$i-$(date +%s)"
        local start_ms end_ms latency

        start_ms=$(get_time_ms)

        # Simulate full query: miss + compute + set
        "$CACHE_SCRIPT" --get "$test_file" --query "$query_hash" >/dev/null 2>&1 || true
        "$CACHE_SCRIPT" --set "$test_file" --query "$query_hash" --value "result-$i" 2>/dev/null

        end_ms=$(get_time_ms)
        latency=$((end_ms - start_ms))
        latencies+=("$latency")
    done

    # Calculate P95
    local p95
    p95=$(calculate_p95 "${latencies[@]}")

    # Cleanup
    rm -rf "$CACHE_DIR" 2>/dev/null

    # Report
    local target=500
    if [[ $p95 -lt $target ]]; then
        log_ok "Full query P95: ${p95}ms (target: <${target}ms)"
        echo "PASS"
    else
        log_fail "Full query P95: ${p95}ms (target: <${target}ms)"
        echo "FAIL"
    fi

    echo "full_query_p95_ms=$p95"
}

# ============================================================
# Pre-commit Benchmark (AC-N03, AC-N04)
# ============================================================

benchmark_precommit() {
    log_info "Running pre-commit benchmark..."

    local guard_script="$PROJECT_ROOT/scripts/dependency-guard.sh"
    if [[ ! -x "$guard_script" ]]; then
        log_fail "dependency-guard.sh not found or not executable"
        return 1
    fi

    # Test staged-only mode
    local latencies_staged=()
    for ((i=1; i<=5; i++)); do
        local start_ms end_ms latency
        start_ms=$(get_time_ms)

        "$guard_script" --pre-commit --format json >/dev/null 2>&1 || true

        end_ms=$(get_time_ms)
        latency=$((end_ms - start_ms))
        latencies_staged+=("$latency")
    done

    local p95_staged
    p95_staged=$(calculate_p95 "${latencies_staged[@]}")

    # Test with-deps mode
    local latencies_deps=()
    for ((i=1; i<=5; i++)); do
        local start_ms end_ms latency
        start_ms=$(get_time_ms)

        "$guard_script" --pre-commit --with-deps --format json >/dev/null 2>&1 || true

        end_ms=$(get_time_ms)
        latency=$((end_ms - start_ms))
        latencies_deps+=("$latency")
    done

    local p95_deps
    p95_deps=$(calculate_p95 "${latencies_deps[@]}")

    # Report
    local target_staged=2000
    local target_deps=5000

    if [[ $p95_staged -lt $target_staged ]]; then
        log_ok "Pre-commit (staged) P95: ${p95_staged}ms (target: <${target_staged}ms)"
    else
        log_fail "Pre-commit (staged) P95: ${p95_staged}ms (target: <${target_staged}ms)"
    fi

    if [[ $p95_deps -lt $target_deps ]]; then
        log_ok "Pre-commit (with-deps) P95: ${p95_deps}ms (target: <${target_deps}ms)"
    else
        log_fail "Pre-commit (with-deps) P95: ${p95_deps}ms (target: <${target_deps}ms)"
    fi

    echo "precommit_staged_p95_ms=$p95_staged"
    echo "precommit_deps_p95_ms=$p95_deps"
}

# ============================================================
# Main Entry Point
# ============================================================

main() {
    local mode="all"
    local dataset=""
    local queries=""
    local output=""
    local baseline=""
    local compare_base=""
    local compare_current=""
    local use_new=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dataset)
                if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                    log_fail "dataset is required"
                    exit 1
                fi
                dataset="$2"
                use_new=true
                shift 2
                ;;
            --queries)
                queries="${2:-}"
                use_new=true
                shift 2
                ;;
            --output)
                output="${2:-}"
                use_new=true
                shift 2
                ;;
            --baseline)
                baseline="${2:-}"
                use_new=true
                shift 2
                ;;
            --compare)
                compare_base="${2:-}"
                compare_current="${3:-}"
                use_new=true
                shift 3
                ;;
            --enable-all-features)
                DEVBOOKS_ENABLE_ALL_FEATURES=1
                shift
                ;;
            --cache)
                mode="cache"
                shift
                ;;
            --full)
                mode="full"
                shift
                ;;
            --precommit)
                mode="precommit"
                shift
                ;;
            --all)
                mode="all"
                shift
                ;;
            --iterations)
                BENCHMARK_ITERATIONS="$2"
                shift 2
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

    if [[ "$use_new" == "true" ]]; then
        if [[ -n "$baseline" ]]; then
            if ! validate_json_file "$baseline"; then
                return 1
            fi
        fi

        if [[ -n "$compare_base" ]]; then
            if ! feature_enabled "performance_regression"; then
                log_info "performance_regression disabled"
                return 0
            fi
            compare_reports "$compare_base" "$compare_current"
            return $?
        fi

        if ! feature_enabled "benchmark"; then
            log_info "benchmark disabled"
            return 0
        fi

        run_dataset_benchmark "$dataset" "$queries" "$output"
        return $?
    fi

    # Legacy benchmark mode
    mkdir -p "$EVIDENCE_DIR"

    local log_file="$EVIDENCE_DIR/cache-benchmark.log"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    {
        echo "=== Performance Benchmark Report ==="
        echo "Timestamp: $timestamp"
        echo "Iterations: $BENCHMARK_ITERATIONS"
        echo ""

        case "$mode" in
            cache)
                benchmark_cache
                ;;
            full)
                benchmark_full_query
                ;;
            precommit)
                benchmark_precommit
                ;;
            all)
                echo "--- Cache Hit Benchmark ---"
                benchmark_cache
                echo ""
                echo "--- Full Query Benchmark ---"
                benchmark_full_query
                echo ""
                echo "--- Pre-commit Benchmark ---"
                benchmark_precommit
                ;;
        esac

        echo ""
        echo "=== End of Report ==="
    } | tee "$log_file"

    log_info "Benchmark report saved to: $log_file"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
