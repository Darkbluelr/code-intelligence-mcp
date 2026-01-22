#!/usr/bin/env bats
# 击键级请求取消测试
# Change ID: augment-final-10-percent
# AC: AC-005, AC-005a

load 'helpers/common.bash'

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
    export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
    export DAEMON_SCRIPT="${SCRIPTS_DIR}/daemon.sh"
    export TEMP_DIR=$(mktemp -d)
    export METRICS_LOG="${TEMP_DIR}/metrics.log"
}

teardown() {
    # 清理所有测试进程
    pkill -f "keystroke-cancel-test" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}

# ============================================================
# @smoke 快速验证
# ============================================================

# @smoke T-KC-001: 单进程取消延迟测试 (SC-KC-001)
@test "T-KC-001: Single process cancel latency < 10ms (P95)" {
    [ -f "$DAEMON_SCRIPT" ]
    [ -x "$DAEMON_SCRIPT" ]

    latencies=()

    for i in {1..20}; do
        # 启动一个模拟长时间运行的进程
        source "$DAEMON_SCRIPT"
        result=$(daemon_start_with_cancel "sleep" "10" "--name=keystroke-cancel-test")
        pid=$(echo "$result" | jq -r '.pid')
        cancel_token=$(echo "$result" | jq -r '.cancel_token')

        # 记录取消开始时间
        start=$(date +%s%N)

        # 发送取消信号
        daemon_cancel "$pid"

        # 记录取消完成时间
        end=$(date +%s%N)

        latency=$(( (end - start) / 1000000 ))  # 转换为毫秒
        latencies+=($latency)
    done

    # 计算 P95
    sorted=$(printf '%s\n' "${latencies[@]}" | sort -n)
    p95_index=$(( ${#latencies[@]} * 95 / 100 ))
    p95=$(echo "$sorted" | sed -n "${p95_index}p")

    echo "P95 latency: ${p95}ms"
    [ "$p95" -lt 10 ]
}

# @smoke T-KC-009: 取消状态码验证
@test "T-KC-009: Cancel returns exit code 130" {
    [ -f "$DAEMON_SCRIPT" ]

    source "$DAEMON_SCRIPT"

    # 启动进程
    result=$(daemon_start_with_cancel "sleep" "10")
    pid=$(echo "$result" | jq -r '.pid')

    # 取消并获取退出码
    daemon_cancel "$pid"
    wait "$pid" 2>/dev/null || exit_code=$?

    [ "$exit_code" -eq 130 ]
}

# ============================================================
# @critical 关键功能
# ============================================================

# @critical T-KC-002: 子进程取消传播 (SC-KC-002)
@test "T-KC-002: Cancel propagates to all child processes" {
    [ -f "$DAEMON_SCRIPT" ]

    source "$DAEMON_SCRIPT"

    # 创建一个会启动子进程的脚本
    cat > "${TEMP_DIR}/parent.sh" << 'EOF'
#!/bin/bash
sleep 100 &
child1=$!
sleep 100 &
child2=$!
sleep 100 &
child3=$!
wait
EOF
    chmod +x "${TEMP_DIR}/parent.sh"

    # 启动父进程
    result=$(daemon_start_with_cancel "${TEMP_DIR}/parent.sh")
    parent_pid=$(echo "$result" | jq -r '.pid')

    # 等待子进程启动
    sleep 0.1

    # 记录子进程数量
    children_before=$(pgrep -P "$parent_pid" | wc -l)
    [ "$children_before" -ge 3 ]

    # 取消
    start=$(date +%s%N)
    daemon_cancel "$parent_pid"
    end=$(date +%s%N)

    latency=$(( (end - start) / 1000000 ))
    echo "Cancel propagation latency: ${latency}ms"

    # 验证子进程已终止
    sleep 0.1
    children_after=$(pgrep -P "$parent_pid" 2>/dev/null | wc -l)
    [ "$children_after" -eq 0 ]

    # 延迟应该 < 15ms
    [ "$latency" -lt 15 ]
}

# @critical T-KC-003: 资源清理测试 (SC-KC-003)
@test "T-KC-003: Cancel cleans up all resources" {
    [ -f "$DAEMON_SCRIPT" ]

    source "$DAEMON_SCRIPT"

    # 创建一个会创建临时文件的脚本
    cat > "${TEMP_DIR}/with-resources.sh" << 'EOF'
#!/bin/bash
temp_file=$(mktemp /tmp/ckb-test-XXXXXX)
echo "data" > "$temp_file"
trap "rm -f $temp_file" EXIT TERM
sleep 100
EOF
    chmod +x "${TEMP_DIR}/with-resources.sh"

    # 启动
    result=$(daemon_start_with_cancel "${TEMP_DIR}/with-resources.sh")
    pid=$(echo "$result" | jq -r '.pid')

    # 等待临时文件创建
    sleep 0.1
    temp_files_before=$(ls /tmp/ckb-test-* 2>/dev/null | wc -l)

    # 取消
    daemon_cancel "$pid"
    wait "$pid" 2>/dev/null || true

    # 验证临时文件已清理
    sleep 0.1
    temp_files_after=$(ls /tmp/ckb-test-* 2>/dev/null | wc -l)

    [ "$temp_files_after" -lt "$temp_files_before" ] || [ "$temp_files_after" -eq 0 ]
}

# @critical T-KC-007: 取消令牌生命周期
@test "T-KC-007: Cancel token lifecycle is properly managed" {
    [ -f "$DAEMON_SCRIPT" ]

    source "$DAEMON_SCRIPT"

    # 启动进程
    result=$(daemon_start_with_cancel "sleep" "10")
    pid=$(echo "$result" | jq -r '.pid')
    cancel_token=$(echo "$result" | jq -r '.cancel_token')

    # 验证令牌已创建
    [ -e "$cancel_token" ]

    # 取消
    daemon_cancel "$pid"
    wait "$pid" 2>/dev/null || true

    # 验证令牌已清理
    sleep 0.1
    [ ! -e "$cancel_token" ]
}

# @critical T-KC-008: 信号驱动机制验证
@test "T-KC-008: Uses signal-driven cancel mechanism" {
    [ -f "$DAEMON_SCRIPT" ]

    # 检查脚本是否使用信号机制而非轮询
    grep -q "trap.*SIGUSR1" "$DAEMON_SCRIPT" || \
    grep -q "trap.*USR1" "$DAEMON_SCRIPT" || \
    grep -q "signal" "$DAEMON_SCRIPT"
}

# ============================================================
# @full 完整覆盖
# ============================================================

# @full T-KC-004: 并发取消处理 (SC-KC-004)
@test "T-KC-004: Concurrent cancellation of 5 processes" {
    [ -f "$DAEMON_SCRIPT" ]

    source "$DAEMON_SCRIPT"

    pids=()
    for i in {1..5}; do
        result=$(daemon_start_with_cancel "sleep" "100")
        pid=$(echo "$result" | jq -r '.pid')
        pids+=($pid)
    done

    # 同时取消所有进程
    start=$(date +%s%N)
    daemon_cancel_all
    end=$(date +%s%N)

    latency=$(( (end - start) / 1000000 ))
    echo "Concurrent cancel latency: ${latency}ms"

    # 验证所有进程已终止
    sleep 0.1
    for pid in "${pids[@]}"; do
        ! kill -0 "$pid" 2>/dev/null
    done

    # P95 延迟 < 15ms
    [ "$latency" -lt 15 ]
}

# @full T-KC-005: 取消超时保护 (SC-KC-005)
@test "T-KC-005: Timeout protection kills unresponsive process" {
    [ -f "$DAEMON_SCRIPT" ]

    source "$DAEMON_SCRIPT"

    # 创建一个忽略信号的进程
    cat > "${TEMP_DIR}/ignore-signals.sh" << 'EOF'
#!/bin/bash
trap '' SIGUSR1 SIGTERM
sleep 100
EOF
    chmod +x "${TEMP_DIR}/ignore-signals.sh"

    result=$(daemon_start_with_cancel "${TEMP_DIR}/ignore-signals.sh")
    pid=$(echo "$result" | jq -r '.pid')

    # 取消（应该最终使用 SIGKILL）
    daemon_cancel "$pid" --timeout 100

    # 验证进程已终止
    sleep 0.2
    ! kill -0 "$pid" 2>/dev/null

    # 检查退出码应该是 137 (SIGKILL)
    wait "$pid" 2>/dev/null || exit_code=$?
    [ "$exit_code" -eq 137 ] || [ "$exit_code" -eq 130 ]
}

# @full T-KC-006: 部分结果返回 (SC-KC-006)
@test "T-KC-006: Partial results are returned on cancel" {
    [ -f "$DAEMON_SCRIPT" ]

    source "$DAEMON_SCRIPT"

    # 创建一个逐步产生结果的脚本
    cat > "${TEMP_DIR}/progressive.sh" << 'EOF'
#!/bin/bash
for i in {1..10}; do
    echo "result-$i"
    sleep 0.1
done
EOF
    chmod +x "${TEMP_DIR}/progressive.sh"

    result=$(daemon_start_with_cancel "${TEMP_DIR}/progressive.sh")
    pid=$(echo "$result" | jq -r '.pid')
    output_file=$(echo "$result" | jq -r '.output_file')

    # 等待部分结果产生
    sleep 0.3

    # 取消
    cancel_result=$(daemon_cancel "$pid")

    # 验证返回了部分结果
    echo "$cancel_result" | jq -e '.partial == true'

    # 验证有一些结果被保留
    lines=$(wc -l < "$output_file")
    [ "$lines" -ge 2 ]
    [ "$lines" -lt 10 ]
}

# @full T-PERF-KC-001: P95 延迟基准测试 (AC-005)
@test "T-PERF-KC-001: Cancel latency P95 < 10ms (hot), < 50ms (cold)" {
    [ -f "$DAEMON_SCRIPT" ]

    source "$DAEMON_SCRIPT"

    # 冷启动测试
    cold_start=$(date +%s%N)
    result=$(daemon_start_with_cancel "sleep" "10")
    pid=$(echo "$result" | jq -r '.pid')
    daemon_cancel "$pid"
    cold_end=$(date +%s%N)
    cold_latency=$(( (cold_end - cold_start) / 1000000 ))

    echo "Cold start latency: ${cold_latency}ms"
    [ "$cold_latency" -lt 50 ]

    # 热启动测试（多次运行取 P95）
    hot_latencies=()
    for i in {1..100}; do
        result=$(daemon_start_with_cancel "sleep" "10")
        pid=$(echo "$result" | jq -r '.pid')

        start=$(date +%s%N)
        daemon_cancel "$pid"
        end=$(date +%s%N)

        latency=$(( (end - start) / 1000000 ))
        hot_latencies+=($latency)
    done

    sorted=$(printf '%s\n' "${hot_latencies[@]}" | sort -n)
    p95_index=95
    p95=$(echo "$sorted" | sed -n "${p95_index}p")

    echo "Hot start P95 latency: ${p95}ms"
    [ "$p95" -lt 10 ]
}
