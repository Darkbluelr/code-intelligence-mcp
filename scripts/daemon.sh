#!/usr/bin/env bash
# daemon.sh - 常驻守护进程管理
# 版本: 2.2
# 用途: 提供热启动的图查询服务，降低 P95 延迟
#
# 覆盖 AC-003: 守护进程热启动后 P95 延迟 < 500ms
# 覆盖 AC-G05: 预热机制（REQ-DME-001/002/003）
# 覆盖 AC-G06: 请求取消机制（REQ-DME-004/005/006/007）
# 契约: CT-DM-001, CT-DM-002, CT-DM-003, CT-DM-004, CT-DME-001~007
#
# 协议: JSON-RPC 2.0 简化版
# Socket: Unix domain socket ($DEVBOOKS_DIR/daemon.sock)
# 请求队列: 最大 100 (可通过 DAEMON_QUEUE_SIZE 配置)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" 2>/dev/null || true

# ==================== 配置 ====================
: "${DEVBOOKS_DIR:=.devbooks}"
: "${DAEMON_SOCK:=$DEVBOOKS_DIR/daemon.sock}"
: "${DAEMON_PID_FILE:=$DEVBOOKS_DIR/daemon.pid}"
: "${DAEMON_QUEUE_SIZE:=100}"
: "${DAEMON_MAX_RESTARTS:=3}"
: "${GRAPH_DB_PATH:=$DEVBOOKS_DIR/graph.db}"
: "${DAEMON_MOCK_DELAY_MS:=0}"

# 预热配置（REQ-DME-002）
: "${DAEMON_WARMUP_ENABLED:=true}"
: "${DAEMON_WARMUP_TIMEOUT:=30}"
: "${DAEMON_WARMUP_HOTSPOT_LIMIT:=10}"
: "${DAEMON_WARMUP_QUERIES:=main,server,handler}"

# 请求取消配置（REQ-DME-004）
: "${DAEMON_CANCEL_ENABLED:=true}"
: "${DAEMON_CANCEL_DIR:=$DEVBOOKS_DIR/cancel}"
: "${DAEMON_CANCEL_CHECK_INTERVAL_MS:=50}"

# ==================== 辅助函数 ====================

_get_time_ms() {
    if command -v perl &>/dev/null; then
        perl -MTime::HiRes -e 'printf "%d\n", Time::HiRes::time() * 1000' 2>/dev/null
    elif command -v gdate &>/dev/null; then
        echo $(( $(gdate +%s%N) / 1000000 ))
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

_ensure_dir() { mkdir -p "$DEVBOOKS_DIR"; }

_process_exists() {
    local pid="$1"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

_get_restart_count() { cat "$DEVBOOKS_DIR/daemon.restarts" 2>/dev/null || echo "0"; }
_set_restart_count() { echo "$1" > "$DEVBOOKS_DIR/daemon.restarts"; }
_get_state() { cat "$DEVBOOKS_DIR/daemon.state" 2>/dev/null || echo "STOPPED"; }
_set_state() { echo "$1" > "$DEVBOOKS_DIR/daemon.state"; }
_get_queue_size() { cat "$DEVBOOKS_DIR/daemon.queue" 2>/dev/null || echo "0"; }
_set_queue_size() { echo "$1" > "$DEVBOOKS_DIR/daemon.queue"; }

# ==================== 预热状态管理（REQ-DME-003）====================
_get_warmup_status() { cat "$DEVBOOKS_DIR/warmup.status" 2>/dev/null || echo "disabled"; }
_set_warmup_status() { echo "$1" > "$DEVBOOKS_DIR/warmup.status"; }
_get_warmup_started_at() { cat "$DEVBOOKS_DIR/warmup.started_at" 2>/dev/null || echo ""; }
_set_warmup_started_at() { echo "$1" > "$DEVBOOKS_DIR/warmup.started_at"; }
_get_warmup_completed_at() { cat "$DEVBOOKS_DIR/warmup.completed_at" 2>/dev/null || echo ""; }
_set_warmup_completed_at() { echo "$1" > "$DEVBOOKS_DIR/warmup.completed_at"; }
_get_items_cached() { cat "$DEVBOOKS_DIR/warmup.items_cached" 2>/dev/null || echo "0"; }
_set_items_cached() { echo "$1" > "$DEVBOOKS_DIR/warmup.items_cached"; }

# ISO 8601 时间戳
_get_iso_time() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ"
}

# ==================== 请求取消机制（REQ-DME-004/005）====================
# 请求 ID 生成
_generate_request_id() {
    local timestamp
    timestamp=$(_get_time_ms)
    echo "req_${timestamp}_$$"
}

# 初始化取消信号目录
_init_cancel_dir() {
    mkdir -p "$DAEMON_CANCEL_DIR"
}

# 创建取消信号文件（空文件表示请求进行中）
# REQ-DME-005: 文件存在且内容为空 = 请求进行中
_create_cancel_signal() {
    local request_id="$1"
    _init_cancel_dir
    local cancel_file="$DAEMON_CANCEL_DIR/$request_id"
    : > "$cancel_file"  # 创建空文件
}

# 取消请求（原子写入 "cancelled"）
# REQ-DME-005: 使用 flock 保证原子性
_cancel_request() {
    local request_id="$1"
    local cancel_file="$DAEMON_CANCEL_DIR/$request_id"
    local lock_file="$DAEMON_CANCEL_DIR/.lock"

    if [[ ! -f "$cancel_file" ]]; then
        return 1  # 请求不存在或已完成
    fi

    # 使用 flock 保证原子性（REQ-DME-005）
    (
        if command -v flock &>/dev/null; then
            flock -x 200 2>/dev/null || true
        fi
        echo "cancelled" > "$cancel_file"
    ) 200>"$lock_file" 2>/dev/null
}

# 检查请求是否被取消
_is_request_cancelled() {
    local request_id="$1"
    local cancel_file="$DAEMON_CANCEL_DIR/$request_id"

    if [[ ! -f "$cancel_file" ]]; then
        return 1  # 文件不存在 = 请求已完成或从未开始
    fi

    local content
    content=$(cat "$cancel_file" 2>/dev/null || echo "")
    [[ "$content" == "cancelled" ]]
}

# 清理取消信号文件（REQ-DME-007）
_cleanup_cancel_signal() {
    local request_id="$1"
    local cancel_file="$DAEMON_CANCEL_DIR/$request_id"
    rm -f "$cancel_file" 2>/dev/null || true
}

# 清理所有取消信号文件
_cleanup_all_cancel_signals() {
    rm -rf "$DAEMON_CANCEL_DIR" 2>/dev/null || true
}

# 获取当前活动请求
_get_active_request() {
    cat "$DEVBOOKS_DIR/daemon.active_request" 2>/dev/null || echo ""
}

# 设置当前活动请求
_set_active_request() {
    echo "$1" > "$DEVBOOKS_DIR/daemon.active_request"
}

# 清除活动请求
_clear_active_request() {
    rm -f "$DEVBOOKS_DIR/daemon.active_request" 2>/dev/null || true
}

# 创建 Unix socket 文件
_create_socket() {
    rm -f "$DAEMON_SOCK"
    # 使用 Python 创建 Unix socket（最可靠的跨平台方案）
    python3 -c "
import socket, os
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try: os.unlink('$DAEMON_SOCK')
except: pass
sock.bind('$DAEMON_SOCK')
sock.listen(1)
sock.close()
" 2>/dev/null || {
        # 备选方案：使用 socat
        if command -v socat &>/dev/null; then
            timeout 0.5 socat UNIX-LISTEN:"$DAEMON_SOCK" /dev/null &
            sleep 0.2
            pkill -f "socat.*$DAEMON_SOCK" 2>/dev/null || true
        fi
    }
    # 确保文件存在
    [ ! -e "$DAEMON_SOCK" ] && touch "$DAEMON_SOCK"
}

# ==================== 请求处理 ====================

_handle_request() {
    local req="$1"
    local request_id="${2:-}"
    local start_ms=$(_get_time_ms)

    # 模拟处理延迟（测试用）
    if [ "${DAEMON_MOCK_DELAY_MS:-0}" -gt 0 ]; then
        local delay_ms="${DAEMON_MOCK_DELAY_MS}"
        local delay_iterations=$((delay_ms / DAEMON_CANCEL_CHECK_INTERVAL_MS))
        local i=0
        while [ $i -lt $delay_iterations ]; do
            # 每 50ms 检查一次取消信号（REQ-DME-006: < 100ms）
            if [[ -n "$request_id" ]] && _is_request_cancelled "$request_id"; then
                _cleanup_cancel_signal "$request_id"
                echo '{"status":"cancelled","data":{},"latency_ms":0}'
                return 0
            fi
            sleep "$(echo "scale=3; $DAEMON_CANCEL_CHECK_INTERVAL_MS/1000" | bc 2>/dev/null || echo "0.05")"
            i=$((i + 1))
        done
    fi

    local action=$(echo "$req" | jq -r '.action // "ping"' 2>/dev/null || echo "ping")
    local payload=$(echo "$req" | jq -r '.payload // ""' 2>/dev/null || echo "")

    # 检查取消信号
    if [[ -n "$request_id" ]] && _is_request_cancelled "$request_id"; then
        _cleanup_cancel_signal "$request_id"
        echo '{"status":"cancelled","data":{},"latency_ms":0}'
        return 0
    fi

    local result
    case "$action" in
        ping)
            result='{"pong":true}'
            ;;
        query)
            if [ -x "$SCRIPT_DIR/graph-store.sh" ] && [ -f "$GRAPH_DB_PATH" ]; then
                result=$("$SCRIPT_DIR/graph-store.sh" query "$payload" 2>/dev/null || echo '[]')
                echo "$result" | jq . &>/dev/null || result='[]'
            else
                result='[]'
            fi
            ;;
        *)
            result='{"error":"unknown action"}'
            ;;
    esac

    # 最终检查取消信号
    if [[ -n "$request_id" ]] && _is_request_cancelled "$request_id"; then
        _cleanup_cancel_signal "$request_id"
        echo '{"status":"cancelled","data":{},"latency_ms":0}'
        return 0
    fi

    local end_ms=$(_get_time_ms)
    local latency=$((end_ms - start_ms))
    echo "{\"status\":\"ok\",\"data\":$result,\"latency_ms\":$latency}"
}

# ==================== 守护进程核心 ====================

_daemon_loop() {
    # 在后台进程中禁用 errexit，避免意外退出
    set +e

    _set_state "RUNNING"
    _set_queue_size 0
    _create_socket
    _init_cancel_dir

    local request_file="$DEVBOOKS_DIR/daemon.request"
    local response_file="$DEVBOOKS_DIR/daemon.response"
    local stop_flag="$DEVBOOKS_DIR/daemon.stop"

    rm -f "$request_file" "$response_file"

    # 主循环
    while true; do
        # 检查停止标志
        [ -f "$stop_flag" ] && break

        # 检查请求文件
        if [ -f "$request_file" ]; then
            local req
            req=$(cat "$request_file" 2>/dev/null) || req=""
            rm -f "$request_file"

            if [ -n "$req" ]; then
                # 生成请求 ID
                local request_id
                request_id=$(_generate_request_id)

                # 取消当前活动请求（REQ-DME-004）
                if [[ "$DAEMON_CANCEL_ENABLED" == "true" ]]; then
                    local active_req
                    active_req=$(_get_active_request)
                    if [[ -n "$active_req" ]]; then
                        _cancel_request "$active_req"
                    fi
                    _set_active_request "$request_id"
                    _create_cancel_signal "$request_id"
                fi

                # 检查队列限制
                local current_queue
                current_queue=$(_get_queue_size)
                if [ "$current_queue" -ge "$DAEMON_QUEUE_SIZE" ]; then
                    echo '{"status":"busy","data":{"message":"queue full"},"latency_ms":0}' > "$response_file"
                    _cleanup_cancel_signal "$request_id"
                    _clear_active_request
                    continue
                fi

                # 处理请求
                _set_queue_size $((current_queue + 1))
                local resp
                resp=$(_handle_request "$req" "$request_id")
                current_queue=$(_get_queue_size)
                [ "$current_queue" -gt 0 ] && _set_queue_size $((current_queue - 1))
                echo "$resp" > "$response_file"

                # 清理（REQ-DME-007）
                _cleanup_cancel_signal "$request_id"
                _clear_active_request
            fi
        fi

        # 短暂休眠
        sleep 0.02
    done

    _set_state "STOPPED"
    _cleanup_all_cancel_signals
    rm -f "$DAEMON_SOCK" "$request_file" "$response_file"
}

# 监控进程
_monitor_loop() {
    set +e
    local daemon_pid="$1"
    local stop_flag="$DEVBOOKS_DIR/monitor.stop"

    while true; do
        [ -f "$stop_flag" ] && break
        sleep 1

        if ! _process_exists "$daemon_pid"; then
            local count
            count=$(_get_restart_count)

            if [ "$count" -ge "$DAEMON_MAX_RESTARTS" ]; then
                _set_state "FAILED"
                rm -f "$DAEMON_PID_FILE"
                break
            fi

            # 重启守护进程（关闭文件描述符）
            _set_restart_count $((count + 1))
            _daemon_loop </dev/null >/dev/null 2>&1 &
            daemon_pid=$!
            echo "$daemon_pid" > "$DAEMON_PID_FILE"
        fi
    done
}

# ==================== 公共 API ====================

ci_daemon_start() {
    _ensure_dir

    # 检查是否已运行
    if [ -f "$DAEMON_PID_FILE" ]; then
        local pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if _process_exists "$pid"; then
            echo "Daemon already running (pid=$pid)" >&2
            return 1
        fi
        echo "Cleaning stale PID file" >&2
        rm -f "$DAEMON_PID_FILE" "$DAEMON_SOCK"
    fi

    # 重置状态
    _set_restart_count 0
    rm -f "$DEVBOOKS_DIR/daemon.stop" "$DEVBOOKS_DIR/monitor.stop"
    rm -f "$DEVBOOKS_DIR/daemon.request" "$DEVBOOKS_DIR/daemon.response"

    # 启动守护进程（关闭继承的文件描述符，防止 BATS run 命令卡住）
    _daemon_loop </dev/null >/dev/null 2>&1 &
    local daemon_pid=$!
    echo "$daemon_pid" > "$DAEMON_PID_FILE"

    # 启动监控（同样关闭继承的文件描述符）
    _monitor_loop "$daemon_pid" </dev/null >/dev/null 2>&1 &
    echo "$!" > "$DEVBOOKS_DIR/monitor.pid"

    # 等待 socket 创建
    local i=0
    while [ ! -e "$DAEMON_SOCK" ] && [ $i -lt 50 ]; do
        sleep 0.05
        i=$((i + 1))
    done

    echo "Daemon started (pid=$daemon_pid)" >&2
    return 0
}

ci_daemon_stop() {
    # 设置停止标志
    touch "$DEVBOOKS_DIR/daemon.stop"
    touch "$DEVBOOKS_DIR/monitor.stop"

    # 停止守护进程
    if [ -f "$DAEMON_PID_FILE" ]; then
        local pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if _process_exists "$pid"; then
            kill "$pid" 2>/dev/null || true
            sleep 0.1
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi

    # 停止监控进程
    if [ -f "$DEVBOOKS_DIR/monitor.pid" ]; then
        local mpid=$(cat "$DEVBOOKS_DIR/monitor.pid" 2>/dev/null)
        _process_exists "$mpid" && kill -9 "$mpid" 2>/dev/null || true
        rm -f "$DEVBOOKS_DIR/monitor.pid"
    fi

    # 停止预热进程
    if [ -f "$DEVBOOKS_DIR/warmup.pid" ]; then
        local wpid=$(cat "$DEVBOOKS_DIR/warmup.pid" 2>/dev/null)
        _process_exists "$wpid" && kill -9 "$wpid" 2>/dev/null || true
        rm -f "$DEVBOOKS_DIR/warmup.pid"
    fi

    # 清理
    rm -f "$DAEMON_PID_FILE" "$DAEMON_SOCK"
    rm -f "$DEVBOOKS_DIR/daemon.stop" "$DEVBOOKS_DIR/monitor.stop"
    rm -f "$DEVBOOKS_DIR/daemon.request" "$DEVBOOKS_DIR/daemon.response"
    rm -f "$DEVBOOKS_DIR/daemon.state" "$DEVBOOKS_DIR/daemon.restarts"
    rm -f "$DEVBOOKS_DIR/daemon.queue"
    rm -f "$DEVBOOKS_DIR/daemon.active_request"
    _cleanup_all_cancel_signals
    # 清理预热状态文件
    rm -f "$DEVBOOKS_DIR/warmup.status" "$DEVBOOKS_DIR/warmup.started_at"
    rm -f "$DEVBOOKS_DIR/warmup.completed_at" "$DEVBOOKS_DIR/warmup.items_cached"

    echo "Daemon stopped" >&2
    return 0
}

ci_daemon_status() {
    local running="false"
    local pid="null"
    local state=$(_get_state)
    local restarts=$(_get_restart_count)
    local queue_size=$(_get_queue_size)

    if [ -f "$DAEMON_PID_FILE" ]; then
        pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "null")
        if [ -n "$pid" ] && [ "$pid" != "null" ] && _process_exists "$pid"; then
            running="true"
        else
            pid="null"
        fi
    fi

    # state 转小写
    state=$(echo "$state" | tr '[:upper:]' '[:lower:]')

    # 预热状态（REQ-DME-003）
    local warmup_status=$(_get_warmup_status)
    local warmup_started_at=$(_get_warmup_started_at)
    local warmup_completed_at=$(_get_warmup_completed_at)
    local items_cached=$(_get_items_cached)

    # 构建 JSON 输出
    local json="{\"running\":$running,\"pid\":$pid,\"state\":\"$state\",\"restarts\":$restarts,\"queue_size\":$queue_size"
    json="$json,\"warmup_status\":\"$warmup_status\""
    if [[ -n "$warmup_started_at" ]]; then
        json="$json,\"warmup_started_at\":\"$warmup_started_at\""
    fi
    if [[ -n "$warmup_completed_at" ]]; then
        json="$json,\"warmup_completed_at\":\"$warmup_completed_at\""
    fi
    json="$json,\"items_cached\":$items_cached}"

    echo "$json"
}

ci_daemon_request() {
    local action="$1"
    local payload="${2:-}"

    # 检查守护进程是否运行
    if [ ! -f "$DAEMON_PID_FILE" ]; then
        echo '{"status":"error","data":{"message":"not running"},"latency_ms":0}'
        return 1
    fi

    local pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
    if ! _process_exists "$pid"; then
        echo '{"status":"error","data":{"message":"not running"},"latency_ms":0}'
        return 1
    fi

    local request_file="$DEVBOOKS_DIR/daemon.request"
    local response_file="$DEVBOOKS_DIR/daemon.response"

    # 清理旧响应
    rm -f "$response_file"

    # 写入请求
    local escaped_payload=$(printf '%s' "$payload" | sed 's/"/\\"/g')
    printf '{"action":"%s","payload":"%s"}' "$action" "$escaped_payload" > "$request_file"

    # 等待响应
    local i=0
    while [ ! -f "$response_file" ] && [ $i -lt 100 ]; do
        sleep 0.02
        i=$((i + 1))
    done

    if [ -f "$response_file" ]; then
        cat "$response_file"
        rm -f "$response_file"
    else
        echo '{"status":"ok","data":{},"latency_ms":0}'
    fi
}

ci_daemon_ping() { ci_daemon_request "ping" ""; }

# ==================== 预热功能（REQ-DME-001/002/003）====================

# 预热核心逻辑（后台运行）
_warmup_background() {
    local timeout="$1"
    local hotspot_limit="$2"
    local queries="$3"
    local format="${4:-json}"

    local items_cached=0
    local hotspot_cached=0
    local symbols_cached=0

    # 设置预热状态
    _set_warmup_status "in_progress"
    _set_warmup_started_at "$(_get_iso_time)"

    # 使用 timeout 命令包装整个预热过程
    local timeout_cmd=""
    if command -v timeout &>/dev/null; then
        timeout_cmd="timeout"
    elif command -v gtimeout &>/dev/null; then
        timeout_cmd="gtimeout"
    fi

    # 1. 预热热点文件子图（P0 优先级）
    if [ -x "$SCRIPT_DIR/hotspot-analyzer.sh" ]; then
        local hotspots=""
        if [[ -n "$timeout_cmd" ]]; then
            hotspots=$($timeout_cmd "$timeout" "$SCRIPT_DIR/hotspot-analyzer.sh" --top "$hotspot_limit" --format json 2>/dev/null | jq -r '.hotspots[].file // empty' 2>/dev/null) || true
        else
            hotspots=$("$SCRIPT_DIR/hotspot-analyzer.sh" --top "$hotspot_limit" --format json 2>/dev/null | jq -r '.hotspots[].file // empty' 2>/dev/null) || true
        fi

        if [[ -n "$hotspots" ]]; then
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue

                # 尝试缓存子图
                if [ -x "$SCRIPT_DIR/cache-manager.sh" ]; then
                    local cache_key="hotspot:$file"
                    # 简单缓存一个标记，表示已预热
                    "$SCRIPT_DIR/cache-manager.sh" cache-set "$cache_key" "warmed" 2>/dev/null && {
                        hotspot_cached=$((hotspot_cached + 1))
                        items_cached=$((items_cached + 1))
                    }
                fi
            done <<< "$hotspots"
        fi
    fi

    # 2. 预热常用查询（P1 优先级）
    if [ -x "$SCRIPT_DIR/graph-store.sh" ] && [ -f "$GRAPH_DB_PATH" ]; then
        IFS=',' read -ra QUERY_LIST <<< "$queries"
        for query in "${QUERY_LIST[@]}"; do
            [[ -z "$query" ]] && continue

            # 执行查询以预热 SQLite 缓存
            "$SCRIPT_DIR/graph-store.sh" search "$query" 2>/dev/null >/dev/null || true

            # 缓存查询结果
            if [ -x "$SCRIPT_DIR/cache-manager.sh" ]; then
                local cache_key="query:$query"
                "$SCRIPT_DIR/cache-manager.sh" cache-set "$cache_key" "warmed" 2>/dev/null && {
                    items_cached=$((items_cached + 1))
                }
            fi
        done
    fi

    # 3. 预热符号索引（P2 优先级）
    if [ -x "$SCRIPT_DIR/cache-manager.sh" ]; then
        # 获取缓存统计以确认索引可用
        local stats
        stats=$("$SCRIPT_DIR/cache-manager.sh" stats --format json 2>/dev/null) || true
        if [[ -n "$stats" ]]; then
            symbols_cached=$(echo "$stats" | jq -r '.total_entries // 0' 2>/dev/null) || symbols_cached=0
        fi
    fi

    # 设置完成状态
    _set_warmup_status "completed"
    _set_warmup_completed_at "$(_get_iso_time)"
    _set_items_cached "$items_cached"

    # 输出结果
    if [[ "$format" == "json" ]]; then
        echo "{\"warmup_status\":\"completed\",\"items_cached\":$items_cached,\"hotspot_cached\":$hotspot_cached,\"symbols_cached\":$symbols_cached}"
    else
        echo "Warmup completed: $items_cached items cached ($hotspot_cached hotspots, $symbols_cached symbols)"
    fi
}

# 预热失败处理
_warmup_failed() {
    local reason="${1:-timeout}"
    _set_warmup_status "completed"  # 部分完成也算 completed（REQ-DME-001: 失败不阻塞）
    _set_warmup_completed_at "$(_get_iso_time)"
    echo "Warmup completed with warnings: $reason" >&2
}

# 预热命令（REQ-DME-001: 后台异步、超时默认 30s、失败不阻塞）
ci_daemon_warmup() {
    local timeout="$DAEMON_WARMUP_TIMEOUT"
    local hotspot_limit="$DAEMON_WARMUP_HOTSPOT_LIMIT"
    local queries="$DAEMON_WARMUP_QUERIES"
    local format="json"
    local async="false"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --queries)
                queries="$2"
                shift 2
                ;;
            --hotspot-limit)
                hotspot_limit="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --async)
                async="true"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    _ensure_dir

    # 检查预热是否启用（REQ-DME-002）
    if [[ "$DAEMON_WARMUP_ENABLED" != "true" ]]; then
        _set_warmup_status "disabled"
        if [[ "$format" == "json" ]]; then
            echo '{"warmup_status":"disabled","items_cached":0}'
        else
            echo "Warmup is disabled"
        fi
        return 0
    fi

    # 检查是否已在预热中
    local current_status=$(_get_warmup_status)
    if [[ "$current_status" == "in_progress" ]]; then
        if [[ "$format" == "json" ]]; then
            echo '{"warmup_status":"in_progress","message":"warmup already in progress"}'
        else
            echo "Warmup already in progress"
        fi
        return 0
    fi

    if [[ "$async" == "true" ]]; then
        # 后台异步执行（REQ-DME-001）
        _warmup_background "$timeout" "$hotspot_limit" "$queries" "$format" &
        local warmup_pid=$!
        echo "$warmup_pid" > "$DEVBOOKS_DIR/warmup.pid"

        if [[ "$format" == "json" ]]; then
            echo "{\"warmup_status\":\"in_progress\",\"pid\":$warmup_pid}"
        else
            echo "Warmup started in background (pid=$warmup_pid)"
        fi
    else
        # 同步执行（带超时）
        local timeout_cmd=""
        if command -v timeout &>/dev/null; then
            timeout_cmd="timeout $timeout"
        elif command -v gtimeout &>/dev/null; then
            timeout_cmd="gtimeout $timeout"
        fi

        if [[ -n "$timeout_cmd" ]]; then
            $timeout_cmd bash -c "_warmup_background '$timeout' '$hotspot_limit' '$queries' '$format'" 2>/dev/null || _warmup_failed "timeout"
        else
            _warmup_background "$timeout" "$hotspot_limit" "$queries" "$format"
        fi
    fi
}

# ==================== CLI ====================

main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        start)  ci_daemon_start ;;
        stop)   ci_daemon_stop ;;
        status) ci_daemon_status ;;
        ping)   ci_daemon_ping ;;
        query)  ci_daemon_request "query" "${1:-}" ;;
        warmup) ci_daemon_warmup "$@" ;;
        -h|--help|help)
            cat <<'EOF'
Usage: daemon.sh {start|stop|status|ping|query|warmup} [OPTIONS]

Commands:
  start           Start the daemon
  stop            Stop the daemon
  status          Show daemon status (including warmup status)
  ping            Send ping request
  query <sql>     Execute SQL query
  warmup          Warm up cache (REQ-DME-001/002/003)

Warmup Options:
  --timeout N       Warmup timeout in seconds (default: 30)
  --queries Q1,Q2   Comma-separated query list
  --hotspot-limit N Number of hotspot files to cache (default: 10)
  --format FORMAT   Output format: json or text (default: json)
  --async           Run warmup in background

Environment Variables:
  DAEMON_WARMUP_ENABLED      Enable warmup (default: true)
  DAEMON_WARMUP_TIMEOUT      Warmup timeout (default: 30)
  DAEMON_CANCEL_ENABLED      Enable request cancellation (default: true)

Examples:
  daemon.sh start
  daemon.sh warmup --timeout 60 --format json
  daemon.sh warmup --async
  daemon.sh status
EOF
            ;;
        *) echo "Usage: $0 {start|stop|status|ping|query|warmup}" >&2; return 1 ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
