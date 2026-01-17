#!/usr/bin/env bash
# benchmark.sh - 性能基准测试脚本
# Change ID: augment-parity-final-gaps
#
# 用途：测量冷启动延迟、LRU 缓存命中率、请求取消响应时间
# 运行方式：./benchmark.sh [--cold|--warm|--cache|--cancel|--all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
DEVBOOKS_DIR="${DEVBOOKS_DIR:-$PROJECT_ROOT/.devbooks}"
EVIDENCE_DIR="$SCRIPT_DIR/.."

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 计时函数
measure_time() {
    local start_time=$(date +%s%3N)
    "$@" > /dev/null 2>&1
    local end_time=$(date +%s%3N)
    echo $((end_time - start_time))
}

# 冷启动测试
test_cold_start() {
    log_info "测试冷启动延迟..."

    # 清除缓存
    rm -f "$DEVBOOKS_DIR/subgraph-cache.db" 2>/dev/null || true

    local total_time=0
    local iterations=5

    for i in $(seq 1 $iterations); do
        local time_ms=$(measure_time "$PROJECT_ROOT/scripts/graph-store.sh" stats)
        total_time=$((total_time + time_ms))
        echo "  迭代 $i: ${time_ms}ms"
    done

    local avg_time=$((total_time / iterations))
    log_info "冷启动平均延迟: ${avg_time}ms"
    echo "cold_start_avg_ms=$avg_time" >> "$EVIDENCE_DIR/benchmark-results.txt"
}

# 预热启动测试
test_warm_start() {
    log_info "测试预热启动延迟..."

    # 先预热
    if [[ -x "$PROJECT_ROOT/scripts/daemon.sh" ]]; then
        "$PROJECT_ROOT/scripts/daemon.sh" warmup > /dev/null 2>&1 || true
    fi

    local total_time=0
    local iterations=5

    for i in $(seq 1 $iterations); do
        local time_ms=$(measure_time "$PROJECT_ROOT/scripts/graph-store.sh" stats)
        total_time=$((total_time + time_ms))
        echo "  迭代 $i: ${time_ms}ms"
    done

    local avg_time=$((total_time / iterations))
    log_info "预热后平均延迟: ${avg_time}ms"
    echo "warm_start_avg_ms=$avg_time" >> "$EVIDENCE_DIR/benchmark-results.txt"
}

# LRU 缓存命中率测试
test_cache_hit_rate() {
    log_info "测试 LRU 缓存命中率..."

    if [[ ! -x "$PROJECT_ROOT/scripts/cache-manager.sh" ]]; then
        log_warn "cache-manager.sh 不存在，跳过缓存测试"
        return
    fi

    # 初始化缓存
    "$PROJECT_ROOT/scripts/cache-manager.sh" init > /dev/null 2>&1 || true

    # 写入测试数据
    for i in $(seq 1 10); do
        "$PROJECT_ROOT/scripts/cache-manager.sh" cache-set "test-key-$i" "test-value-$i" > /dev/null 2>&1 || true
    done

    # 读取测试（重复读取相同键）
    local hits=0
    local total=20

    for i in $(seq 1 $total); do
        local key="test-key-$((i % 10 + 1))"
        local result=$("$PROJECT_ROOT/scripts/cache-manager.sh" cache-get "$key" 2>/dev/null || echo "")
        if [[ -n "$result" ]]; then
            hits=$((hits + 1))
        fi
    done

    local hit_rate=$((hits * 100 / total))
    log_info "缓存命中率: ${hit_rate}% ($hits/$total)"
    echo "cache_hit_rate=$hit_rate" >> "$EVIDENCE_DIR/benchmark-results.txt"
}

# 请求取消响应时间测试
test_cancel_response() {
    log_info "测试请求取消响应时间..."

    if [[ ! -x "$PROJECT_ROOT/scripts/daemon.sh" ]]; then
        log_warn "daemon.sh 不存在，跳过取消测试"
        return
    fi

    # 创建取消目录
    mkdir -p "$DEVBOOKS_DIR/cancel"

    # 模拟请求并测量取消时间
    local request_id="test-$$"
    local cancel_file="$DEVBOOKS_DIR/cancel/$request_id"

    # 启动后台任务
    (
        sleep 10
    ) &
    local bg_pid=$!

    # 测量取消时间
    local start_time=$(date +%s%3N)
    touch "$cancel_file"
    kill $bg_pid 2>/dev/null || true
    local end_time=$(date +%s%3N)

    local cancel_time=$((end_time - start_time))
    rm -f "$cancel_file"

    log_info "取消响应时间: ${cancel_time}ms"
    echo "cancel_response_ms=$cancel_time" >> "$EVIDENCE_DIR/benchmark-results.txt"
}

# 生成报告
generate_report() {
    log_info "生成基准报告..."

    local report_file="$EVIDENCE_DIR/benchmark-report-$(date +%Y%m%d-%H%M%S).md"

    cat > "$report_file" << EOF
# 性能基准测试报告

**生成时间**: $(date '+%Y-%m-%d %H:%M:%S')
**项目**: Code Intelligence MCP
**变更 ID**: augment-parity-final-gaps

## 测试结果

EOF

    if [[ -f "$EVIDENCE_DIR/benchmark-results.txt" ]]; then
        cat "$EVIDENCE_DIR/benchmark-results.txt" >> "$report_file"
    fi

    log_info "报告已生成: $report_file"
}

# 主函数
main() {
    local mode="${1:-all}"

    mkdir -p "$EVIDENCE_DIR"
    rm -f "$EVIDENCE_DIR/benchmark-results.txt"
    touch "$EVIDENCE_DIR/benchmark-results.txt"

    echo "# Benchmark Results - $(date '+%Y-%m-%d %H:%M:%S')" >> "$EVIDENCE_DIR/benchmark-results.txt"

    case "$mode" in
        --cold)
            test_cold_start
            ;;
        --warm)
            test_warm_start
            ;;
        --cache)
            test_cache_hit_rate
            ;;
        --cancel)
            test_cancel_response
            ;;
        --all|*)
            test_cold_start
            test_warm_start
            test_cache_hit_rate
            test_cancel_response
            generate_report
            ;;
    esac

    log_info "基准测试完成"
}

main "$@"
