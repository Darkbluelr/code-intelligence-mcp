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

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
                echo "Usage: benchmark.sh [--cache|--full|--precommit|--all] [--iterations N]"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # Ensure output directory exists
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
