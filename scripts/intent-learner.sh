#!/bin/bash
# intent-learner.sh - 意图偏好学习模块
# Trace: AC-F06, AC-F09, AC-G04
#
# 用途: 记录查询历史、计算偏好分数、自动清理过期记录、对话上下文管理
#
# 命令:
#   record <query> <symbol_id> [--action view|edit|ignore]  - 记录查询历史
#   get-preferences [--top <n>] [--prefix <path>]           - 查询偏好分数
#   cleanup [--days <n>]                                     - 清理过期记录
#   context save --query <q> --symbols <s1,s2>              - 保存对话上下文
#   context load                                             - 加载对话上下文
#   context apply-weight --results <json>                   - 应用对话连续性加权
#   session new                                              - 创建新会话
#   session resume <id>                                      - 恢复会话
#   session list                                             - 列出会话
#   session clear                                            - 清除会话
#
# 偏好计算公式:
#   Preference(symbol) = frequency * recency_weight * click_weight
#   其中:
#     - frequency = 该符号被查询的次数
#     - recency_weight = 1 / (1 + days_since_last_query)
#     - click_weight = 用户操作权重 (view=1.5, edit=2.0, ignore=-0.5)
#
# 对话连续性加权规则:
#   - 符号在 accumulated_focus 中: +0.2
#   - 符号在最近 3 轮 focus_symbols 中: +0.3
#   - 符号与最近查询同文件: +0.1
#   - 加权不超过原始分数的 50%
#
# 环境变量:
#   INTENT_HISTORY_PATH - 历史文件路径 (默认: .devbooks/intent-history.json)
#   INTENT_MAX_ENTRIES  - 最大条目数 (默认: 10000)
#   INTENT_RETENTION_DAYS - 保留天数 (默认: 90)
#   CONVERSATION_CONTEXT_PATH - 对话上下文路径 (默认: .devbooks/conversation-context.json)
#   CONVERSATION_MAX_TURNS - 最大对话轮数 (默认: 10)
#   CONVERSATION_MAX_FOCUS_SYMBOLS - 最大焦点符号数 (默认: 50)
#   CONVERSATION_WEIGHT_ACCUMULATED - 累积焦点加权 (默认: 0.2)
#   CONVERSATION_WEIGHT_RECENT - 近期焦点加权 (默认: 0.3)
#   CONVERSATION_WEIGHT_SAME_FILE - 同文件加权 (默认: 0.1)
#   CONVERSATION_WEIGHT_MAX_RATIO - 最大加权比例 (默认: 0.5)

set -euo pipefail

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀
export LOG_PREFIX="IntentLearner"

# ==================== 配置 ====================

# 历史文件路径
: "${INTENT_HISTORY_PATH:=${DEVBOOKS_DIR:-.devbooks}/intent-history.json}"
# 最大条目数
: "${INTENT_MAX_ENTRIES:=10000}"
# 保留天数
: "${INTENT_RETENTION_DAYS:=90}"

# 对话上下文配置 (Trace: AC-G04)
: "${CONVERSATION_CONTEXT_PATH:=${DEVBOOKS_DIR:-.devbooks}/conversation-context.json}"
# 最大对话轮数 (FIFO 淘汰)
: "${CONVERSATION_MAX_TURNS:=10}"
# 最大焦点符号数 (按访问频率淘汰)
: "${CONVERSATION_MAX_FOCUS_SYMBOLS:=50}"
# 对话连续性加权配置
: "${CONVERSATION_WEIGHT_ACCUMULATED:=0.2}"   # 累积焦点加权
: "${CONVERSATION_WEIGHT_RECENT:=0.3}"        # 近期焦点加权（最近 3 轮）
: "${CONVERSATION_WEIGHT_SAME_FILE:=0.1}"     # 同文件加权
: "${CONVERSATION_WEIGHT_MAX_RATIO:=0.5}"     # 最大加权比例（不超过原分数 50%）

# 操作权重
ACTION_WEIGHT_VIEW=1.5
ACTION_WEIGHT_EDIT=2.0
ACTION_WEIGHT_IGNORE=-0.5

# ==================== 辅助函数 ====================

# 获取操作权重
# 参数: $1 - 操作类型 (view/edit/ignore)
# 返回: 权重值
get_action_weight() {
    local action="$1"
    case "$action" in
        view)   echo "$ACTION_WEIGHT_VIEW" ;;
        edit)   echo "$ACTION_WEIGHT_EDIT" ;;
        ignore) echo "$ACTION_WEIGHT_IGNORE" ;;
        *)      echo "$ACTION_WEIGHT_VIEW" ;;  # 默认 view
    esac
}

# 验证操作类型
# 参数: $1 - 操作类型
# 返回: 0=有效, 1=无效
validate_action() {
    local action="$1"
    case "$action" in
        view|edit|ignore) return 0 ;;
        *) return 1 ;;
    esac
}

# 确保历史文件目录存在
ensure_history_dir() {
    local dir
    dir=$(dirname "$INTENT_HISTORY_PATH")
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

# 初始化空历史文件
init_empty_history() {
    ensure_history_dir
    echo '{"entries": []}' > "$INTENT_HISTORY_PATH"
}

# 检测并恢复损坏的历史文件
# 总是返回 0，因为无论如何文件都会变成有效状态
recover_corrupted_history() {
    # 如果文件不存在，创建空文件
    if [[ ! -f "$INTENT_HISTORY_PATH" ]]; then
        init_empty_history
        return 0
    fi

    # 如果文件为空，初始化为空历史
    if [[ ! -s "$INTENT_HISTORY_PATH" ]]; then
        init_empty_history
        return 0
    fi

    # 尝试解析 JSON
    if ! jq . "$INTENT_HISTORY_PATH" > /dev/null 2>&1; then
        log_warn "检测到损坏的历史文件，正在恢复..."

        # 备份损坏文件
        cp "$INTENT_HISTORY_PATH" "${INTENT_HISTORY_PATH}.bak"
        log_info "已备份损坏文件到 ${INTENT_HISTORY_PATH}.bak"

        # 创建新的空历史文件
        init_empty_history
        log_info "已创建新的空历史文件"
    fi

    return 0
}

# 获取当前时间戳（Unix epoch 秒）
get_current_timestamp() {
    date +%s
}

# 读取历史文件
# 返回: JSON 内容
read_history() {
    recover_corrupted_history
    cat "$INTENT_HISTORY_PATH"
}

# 写入历史文件（原子操作）
# 参数: $1 - JSON 内容
write_history() {
    local content="$1"
    local temp_file="${INTENT_HISTORY_PATH}.tmp"

    ensure_history_dir

    # 写入临时文件
    echo "$content" > "$temp_file"

    # 原子移动
    mv "$temp_file" "$INTENT_HISTORY_PATH"
}

# 执行自动清理（90 天）
auto_cleanup() {
    local now
    now=$(get_current_timestamp)
    local cutoff=$((now - INTENT_RETENTION_DAYS * 86400))

    local history
    history=$(read_history)

    # 过滤掉过期记录
    local cleaned
    cleaned=$(echo "$history" | jq --argjson cutoff "$cutoff" '
        .entries = [.entries[] | select(.timestamp >= $cutoff)]
    ')

    write_history "$cleaned"
}

# 强制最大条目数限制（淘汰最旧记录）
enforce_max_entries() {
    local history
    history=$(read_history)

    local count
    count=$(echo "$history" | jq '.entries | length')

    if [[ "$count" -gt "$INTENT_MAX_ENTRIES" ]]; then
        local excess=$((count - INTENT_MAX_ENTRIES))
        log_info "条目数 ($count) 超过限制 ($INTENT_MAX_ENTRIES)，淘汰 $excess 条最旧记录"

        # 按时间戳排序，保留最新的 INTENT_MAX_ENTRIES 条
        local trimmed
        trimmed=$(echo "$history" | jq --argjson max "$INTENT_MAX_ENTRIES" '
            .entries = (.entries | sort_by(.timestamp) | .[-$max:])
        ')

        write_history "$trimmed"
    fi
}

# ==================== 对话上下文函数 (Trace: AC-G04) ====================

# 生成会话 ID
generate_session_id() {
    local uuid
    if command -v uuidgen &>/dev/null; then
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    else
        # 降级方案：使用时间戳和随机数
        uuid="$(date +%s)-$RANDOM-$RANDOM"
    fi
    echo "session-${uuid}"
}

# 获取 ISO8601 时间戳
get_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 确保对话上下文目录存在
ensure_context_dir() {
    local dir
    dir=$(dirname "$CONVERSATION_CONTEXT_PATH")
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

# 初始化空对话上下文
init_empty_context() {
    ensure_context_dir
    local session_id
    session_id=$(generate_session_id)
    local started_at
    started_at=$(get_iso_timestamp)

    jq -n \
        --arg session_id "$session_id" \
        --arg started_at "$started_at" \
        '{
            session_id: $session_id,
            started_at: $started_at,
            context_window: [],
            accumulated_focus: []
        }' > "$CONVERSATION_CONTEXT_PATH"

    echo "$session_id"
}

# 读取对话上下文（无文件时返回空结构）
read_context() {
    ensure_context_dir

    # 如果文件不存在，返回空结构
    if [[ ! -f "$CONVERSATION_CONTEXT_PATH" ]]; then
        jq -n '{
            session_id: null,
            started_at: null,
            context_window: [],
            accumulated_focus: []
        }'
        return 0
    fi

    # 如果文件为空，返回空结构
    if [[ ! -s "$CONVERSATION_CONTEXT_PATH" ]]; then
        jq -n '{
            session_id: null,
            started_at: null,
            context_window: [],
            accumulated_focus: []
        }'
        return 0
    fi

    # 尝试读取并验证 JSON
    if ! jq . "$CONVERSATION_CONTEXT_PATH" 2>/dev/null; then
        log_warn "对话上下文文件损坏，返回空结构"
        jq -n '{
            session_id: null,
            started_at: null,
            context_window: [],
            accumulated_focus: []
        }'
    fi
}

# 写入对话上下文（原子操作）
write_context() {
    local content="$1"
    local temp_file="${CONVERSATION_CONTEXT_PATH}.tmp"

    ensure_context_dir

    # 写入临时文件
    echo "$content" > "$temp_file"

    # 原子移动
    mv "$temp_file" "$CONVERSATION_CONTEXT_PATH"
}

# 保存对话上下文（一轮对话）
# 参数: --query <q> --symbols <s1,s2> [--query-type <type>] [--results-count <n>]
save_context_turn() {
    local query=""
    local symbols=""
    local query_type="search"
    local results_count=0

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --query)
                query="$2"
                shift 2
                ;;
            --symbols)
                symbols="$2"
                shift 2
                ;;
            --query-type)
                query_type="$2"
                shift 2
                ;;
            --results-count)
                results_count="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$query" ]]; then
        log_error "缺少必需参数: --query"
        return 1
    fi

    # 读取当前上下文
    local context
    context=$(read_context)

    # 如果没有会话，创建新会话
    local session_id
    session_id=$(echo "$context" | jq -r '.session_id // empty')
    if [[ -z "$session_id" ]]; then
        session_id=$(generate_session_id)
        local started_at
        started_at=$(get_iso_timestamp)
        context=$(echo "$context" | jq \
            --arg session_id "$session_id" \
            --arg started_at "$started_at" \
            '.session_id = $session_id | .started_at = $started_at')
    fi

    # 计算新的 turn 号
    local next_turn
    next_turn=$(echo "$context" | jq '(.context_window | length) + 1')

    # 当前时间戳
    local timestamp
    timestamp=$(get_iso_timestamp)

    # 将 symbols 字符串转为数组
    local symbols_array
    if [[ -n "$symbols" ]]; then
        symbols_array=$(echo "$symbols" | tr ',' '\n' | jq -R . | jq -s .)
    else
        symbols_array="[]"
    fi

    # 创建新的 turn 条目
    local new_turn
    new_turn=$(jq -n \
        --argjson turn "$next_turn" \
        --arg timestamp "$timestamp" \
        --arg query "$query" \
        --arg query_type "$query_type" \
        --argjson focus_symbols "$symbols_array" \
        --argjson results_count "$results_count" \
        '{
            turn: $turn,
            timestamp: $timestamp,
            query: $query,
            query_type: $query_type,
            focus_symbols: $focus_symbols,
            results_count: $results_count
        }')

    # 添加到 context_window
    context=$(echo "$context" | jq --argjson new_turn "$new_turn" '
        .context_window += [$new_turn]
    ')

    # 更新 accumulated_focus
    context=$(echo "$context" | jq --argjson symbols "$symbols_array" '
        .accumulated_focus = ((.accumulated_focus + $symbols) | unique)
    ')

    # FIFO 淘汰：超过 max_turns 时删除最旧的
    # 注意：保留原始 turn 编号，不重新编号（保持历史连续性）
    local max_turns="$CONVERSATION_MAX_TURNS"
    context=$(echo "$context" | jq --argjson max "$max_turns" '
        if (.context_window | length) > $max then
            # 删除最旧的 turn，保留原始编号
            .context_window = (.context_window | .[-$max:])
        else
            .
        end
    ')

    # 焦点符号淘汰：超过 max_focus_symbols 时淘汰最少访问的
    local max_focus="$CONVERSATION_MAX_FOCUS_SYMBOLS"
    context=$(echo "$context" | jq --argjson max "$max_focus" '
        if (.accumulated_focus | length) > $max then
            # 统计每个符号的出现次数
            . as $ctx |
            ($ctx.context_window | [.[].focus_symbols[]] | group_by(.) | map({symbol: .[0], count: length}) | sort_by(-.count) | .[0:$max] | map(.symbol)) as $top_symbols |
            .accumulated_focus = ($ctx.accumulated_focus | map(select(. as $s | $top_symbols | index($s))))
        else
            .
        end
    ')

    # 写入文件
    write_context "$context"

    log_ok "已保存对话上下文 (turn=$next_turn)"
}

# 应用对话连续性加权
# 参数: --results <json>
apply_context_weight() {
    local results_json=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --results)
                results_json="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$results_json" ]]; then
        log_error "缺少必需参数: --results"
        return 1
    fi

    # 读取对话上下文
    local context
    context=$(read_context)

    # 如果既没有 context_window 也没有 accumulated_focus，直接返回原结果
    local context_len acc_len
    context_len=$(echo "$context" | jq '.context_window | length // 0')
    acc_len=$(echo "$context" | jq '.accumulated_focus | length // 0')
    if [[ "$context_len" -eq 0 ]] && [[ "$acc_len" -eq 0 ]]; then
        echo "$results_json"
        return 0
    fi

    # 获取配置
    local weight_accumulated="$CONVERSATION_WEIGHT_ACCUMULATED"
    local weight_recent="$CONVERSATION_WEIGHT_RECENT"
    local weight_same_file="$CONVERSATION_WEIGHT_SAME_FILE"
    local max_ratio="$CONVERSATION_WEIGHT_MAX_RATIO"

    # 应用加权
    local weighted
    weighted=$(echo "$results_json" | jq \
        --argjson context "$context" \
        --argjson w_acc "$weight_accumulated" \
        --argjson w_recent "$weight_recent" \
        --argjson w_file "$weight_same_file" \
        --argjson max_ratio "$max_ratio" \
        '
        # 获取累积焦点
        ($context.accumulated_focus // []) as $accumulated |

        # 获取最近 3 轮的焦点符号
        ([$context.context_window[-3:]? // [] | .[].focus_symbols[]?] | unique) as $recent |

        # 获取最近查询的文件（从最后一轮的 focus_symbols 提取）
        ([$context.context_window[-1]?.focus_symbols[]?] | map(split("::")[0]) | unique) as $recent_files |

        # 对每个结果应用加权
        map(
            . as $item |
            ($item.symbol // $item.symbol_id // "") as $sym |
            ($sym | split("::")[0]) as $file |
            ($item.score // 0) as $orig_score |

            # 计算加权
            (if ($accumulated | index($sym)) then $w_acc else 0 end) as $acc_boost |
            (if ($recent | index($sym)) then $w_recent else 0 end) as $recent_boost |
            (if ($recent_files | index($file)) then $w_file else 0 end) as $file_boost |

            # 总加权（不超过原分数的 max_ratio）
            ([$acc_boost + $recent_boost + $file_boost, $orig_score * $max_ratio] | min) as $total_boost |

            # 更新分数
            $item + {
                score: ($orig_score + $total_boost),
                original_score: $orig_score,
                context_boost: $total_boost
            }
        )
        | sort_by(-.score)
        ')

    echo "$weighted"
}

# ==================== 会话管理命令 (Trace: AC-G04) ====================

# session new: 创建新会话
cmd_session_new() {
    local session_id
    session_id=$(init_empty_context)

    log_ok "已创建新会话: $session_id"

    # 返回会话信息
    jq -n --arg session_id "$session_id" '{
        status: "created",
        session_id: $session_id
    }'
}

# session resume: 恢复会话
cmd_session_resume() {
    if [[ $# -lt 1 ]]; then
        log_error "用法: intent-learner session resume <session_id>"
        exit $EXIT_ARGS_ERROR
    fi

    local target_id="$1"

    # 读取当前上下文
    local context
    context=$(read_context)

    local current_id
    current_id=$(echo "$context" | jq -r '.session_id // empty')

    if [[ "$current_id" == "$target_id" ]]; then
        log_ok "会话已激活: $target_id"
        echo "$context"
        return 0
    fi

    # 目前仅支持单会话，resume 只是验证
    if [[ -z "$current_id" ]]; then
        log_warn "无活动会话，请先创建新会话"
        jq -n '{
            status: "not_found",
            session_id: null
        }'
        return 1
    fi

    log_warn "会话 $target_id 不存在或已过期"
    jq -n --arg target_id "$target_id" '{
        status: "not_found",
        session_id: $target_id
    }'
    return 1
}

# session list: 列出会话
cmd_session_list() {
    local context
    context=$(read_context)

    local session_id
    session_id=$(echo "$context" | jq -r '.session_id // empty')

    if [[ -z "$session_id" ]]; then
        jq -n '{
            sessions: []
        }'
        return 0
    fi

    # 返回当前会话信息
    echo "$context" | jq '{
        sessions: [{
            session_id: .session_id,
            started_at: .started_at,
            turns: (.context_window | length),
            focus_count: (.accumulated_focus | length)
        }]
    }'
}

# session clear: 清除会话
cmd_session_clear() {
    if [[ -f "$CONVERSATION_CONTEXT_PATH" ]]; then
        rm -f "$CONVERSATION_CONTEXT_PATH"
        log_ok "已清除会话上下文"
    else
        log_info "无会话上下文需要清除"
    fi

    jq -n '{
        status: "cleared"
    }'
}

# session 命令路由
cmd_session() {
    if [[ $# -lt 1 ]]; then
        log_error "用法: intent-learner session <new|resume|list|clear>"
        exit $EXIT_ARGS_ERROR
    fi

    local subcmd="$1"
    shift

    case "$subcmd" in
        new)
            cmd_session_new "$@"
            ;;
        resume)
            cmd_session_resume "$@"
            ;;
        list)
            cmd_session_list "$@"
            ;;
        clear)
            cmd_session_clear "$@"
            ;;
        *)
            log_error "未知子命令: $subcmd"
            log_info "可用子命令: new, resume, list, clear"
            exit $EXIT_ARGS_ERROR
            ;;
    esac
}

# context 命令路由
cmd_context() {
    if [[ $# -lt 1 ]]; then
        log_error "用法: intent-learner context <save|load|apply-weight>"
        exit $EXIT_ARGS_ERROR
    fi

    local subcmd="$1"
    shift

    case "$subcmd" in
        save)
            save_context_turn "$@"
            ;;
        load)
            read_context
            ;;
        apply-weight)
            apply_context_weight "$@"
            ;;
        *)
            log_error "未知子命令: $subcmd"
            log_info "可用子命令: save, load, apply-weight"
            exit $EXIT_ARGS_ERROR
            ;;
    esac
}

# ==================== 命令实现 ====================

# record 命令：记录查询历史
# 参数: $1 - 符号名 (query)
# 参数: $2 - 符号 ID (symbol_id)
# 选项: --action view|edit|ignore
cmd_record() {
    if [[ $# -lt 2 ]]; then
        log_error "用法: intent-learner record <symbol> <symbol_id> [--action view|edit|ignore]"
        exit $EXIT_ARGS_ERROR
    fi

    local symbol="$1"
    local symbol_id="$2"
    shift 2

    # 默认操作
    local action="view"

    # 解析选项
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --action)
                if [[ $# -lt 2 ]]; then
                    log_error "--action 需要参数"
                    exit $EXIT_ARGS_ERROR
                fi
                action="$2"
                if ! validate_action "$action"; then
                    log_error "无效的操作类型: $action (有效值: view, edit, ignore)"
                    exit $EXIT_ARGS_ERROR
                fi
                shift 2
                ;;
            *)
                log_error "未知选项: $1"
                exit $EXIT_ARGS_ERROR
                ;;
        esac
    done

    # 恢复损坏文件（如有）
    recover_corrupted_history

    # 执行自动清理
    auto_cleanup

    local timestamp
    timestamp=$(get_current_timestamp)

    # 创建新条目
    local new_entry
    new_entry=$(jq -n \
        --arg symbol "$symbol" \
        --arg symbol_id "$symbol_id" \
        --arg action "$action" \
        --argjson timestamp "$timestamp" \
        '{
            symbol: $symbol,
            symbol_id: $symbol_id,
            action: $action,
            timestamp: $timestamp
        }')

    # 追加到历史
    local history
    history=$(read_history)

    local updated
    updated=$(echo "$history" | jq --argjson entry "$new_entry" '
        .entries += [$entry]
    ')

    write_history "$updated"

    # 强制最大条目数限制
    enforce_max_entries

    log_ok "已记录: $symbol ($action)"
}

# get-preferences 命令：查询偏好分数
# 选项: --top <n>     - 返回前 N 个（默认 10）
# 选项: --prefix <path> - 按路径前缀过滤
cmd_get_preferences() {
    local top=10
    local prefix=""

    # 解析选项
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --top)
                if [[ $# -lt 2 ]]; then
                    log_error "--top 需要参数"
                    exit $EXIT_ARGS_ERROR
                fi
                top="$2"
                shift 2
                ;;
            --prefix)
                if [[ $# -lt 2 ]]; then
                    log_error "--prefix 需要参数"
                    exit $EXIT_ARGS_ERROR
                fi
                prefix="$2"
                shift 2
                ;;
            *)
                log_error "未知选项: $1"
                exit $EXIT_ARGS_ERROR
                ;;
        esac
    done

    # 恢复损坏文件（如有）
    recover_corrupted_history

    local history
    history=$(read_history)

    local now
    now=$(get_current_timestamp)

    # 计算偏好分数
    # 公式: Preference = sum(frequency * recency_weight * click_weight) + correction_bonus
    # 其中 recency_weight = 1 / (1 + days_since_last_query)
    # 修正权重: 当一个符号先被 ignore 后又被 edit 时，给予额外 +1.5 的修正加分
    local preferences
    preferences=$(echo "$history" | jq --argjson now "$now" --arg prefix "$prefix" --argjson top "$top" '
        # 定义操作权重
        def action_weight:
            if . == "edit" then 2.0
            elif . == "ignore" then -0.5
            else 1.5
            end;

        # 计算天数差
        def days_since($ts):
            (($now - $ts) / 86400) | floor;

        # 计算 recency 权重
        def recency_weight($ts):
            1 / (1 + days_since($ts));

        # 检测修正模式: ignore 后有 edit（同一秒或之后）
        # 返回修正加分 (如果存在修正模式则返回 1.5，否则返回 0)
        def correction_bonus(entries):
            (entries | map(select(.action == "ignore")) | min_by(.timestamp) // null) as $first_ignore |
            if $first_ignore == null then 0
            else
                # 使用 >= 检测同一秒或之后的 edit（允许相同时间戳）
                (entries | map(select(.action == "edit" and .timestamp >= $first_ignore.timestamp)) | length) as $edits_after_ignore |
                if $edits_after_ignore > 0 then 1.5 else 0 end
            end;

        # 按 symbol_id 分组并计算分数
        .entries
        | if $prefix != "" then [.[] | select(.symbol_id | startswith($prefix))] else . end
        | group_by(.symbol_id)
        | map(. as $entries | {
            symbol: .[0].symbol,
            symbol_id: .[0].symbol_id,
            frequency: length,
            last_query: (map(.timestamp) | max),
            weighted_sum: (map((.action | action_weight) * recency_weight(.timestamp)) | add),
            correction: correction_bonus($entries)
        })
        | map(. + {
            score: (.weighted_sum + .correction)  # 加权和 + 修正加分
        })
        | map({symbol, symbol_id, frequency, score})
        | sort_by(-.score)
        | .[:$top]
    ')

    echo "$preferences"
}

# cleanup 命令：清理过期记录
# 选项: --days <n> - 清理超过 N 天的记录（默认 90）
cmd_cleanup() {
    local days="$INTENT_RETENTION_DAYS"

    # 解析选项
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days)
                if [[ $# -lt 2 ]]; then
                    log_error "--days 需要参数"
                    exit $EXIT_ARGS_ERROR
                fi
                days="$2"
                shift 2
                ;;
            *)
                log_error "未知选项: $1"
                exit $EXIT_ARGS_ERROR
                ;;
        esac
    done

    # 恢复损坏文件（如有）
    recover_corrupted_history

    local now
    now=$(get_current_timestamp)
    local cutoff=$((now - days * 86400))

    local history
    history=$(read_history)

    local before_count
    before_count=$(echo "$history" | jq '.entries | length')

    # 过滤掉过期记录
    local cleaned
    cleaned=$(echo "$history" | jq --argjson cutoff "$cutoff" '
        .entries = [.entries[] | select(.timestamp >= $cutoff)]
    ')

    write_history "$cleaned"

    local after_count
    after_count=$(echo "$cleaned" | jq '.entries | length')

    local removed=$((before_count - after_count))

    if [[ "$removed" -gt 0 ]]; then
        log_ok "已清理 $removed 条过期记录 (超过 $days 天)"
    else
        log_info "无需清理，所有记录都在 $days 天内"
    fi
}

# 显示帮助信息
show_help() {
    cat << 'EOF'
意图偏好学习模块

用法:
  intent-learner <command> [options]

命令:
  record <symbol> <symbol_id> [--action view|edit|ignore]
    记录查询历史

    参数:
      symbol      符号名称
      symbol_id   符号完整 ID (如 src/server.ts::handleToolCall)
      --action    用户操作类型 (默认: view)
                  view=1.5, edit=2.0, ignore=-0.5

  get-preferences [--top <n>] [--prefix <path>]
    查询偏好分数

    选项:
      --top <n>       返回前 N 个结果 (默认: 10)
      --prefix <path> 按路径前缀过滤

  cleanup [--days <n>]
    清理过期记录

    选项:
      --days <n>  清理超过 N 天的记录 (默认: 90)

  context save --query <q> --symbols <s1,s2> [--query-type <type>]
    保存对话上下文

    选项:
      --query <q>        查询内容 (必需)
      --symbols <s1,s2>  焦点符号列表，逗号分隔
      --query-type <t>   查询类型 (默认: search)
      --results-count <n> 结果数量

  context load
    加载当前对话上下文

  context apply-weight --results <json>
    对搜索结果应用对话连续性加权

    选项:
      --results <json>  搜索结果 JSON 数组

  session new
    创建新会话

  session resume <id>
    恢复指定会话

  session list
    列出当前会话

  session clear
    清除会话上下文

环境变量:
  INTENT_HISTORY_PATH           历史文件路径 (默认: .devbooks/intent-history.json)
  INTENT_MAX_ENTRIES            最大条目数 (默认: 10000)
  INTENT_RETENTION_DAYS         保留天数 (默认: 90)
  CONVERSATION_CONTEXT_PATH     对话上下文路径 (默认: .devbooks/conversation-context.json)
  CONVERSATION_MAX_TURNS        最大对话轮数 (默认: 10)
  CONVERSATION_MAX_FOCUS_SYMBOLS 最大焦点符号数 (默认: 50)
  CONVERSATION_WEIGHT_ACCUMULATED 累积焦点加权 (默认: 0.2)
  CONVERSATION_WEIGHT_RECENT     近期焦点加权 (默认: 0.3)
  CONVERSATION_WEIGHT_SAME_FILE  同文件加权 (默认: 0.1)
  CONVERSATION_WEIGHT_MAX_RATIO  最大加权比例 (默认: 0.5)

偏好计算公式:
  Preference(symbol) = frequency * recency_weight * click_weight

  其中:
    - frequency = 该符号被查询的次数
    - recency_weight = 1 / (1 + days_since_last_query)
    - click_weight = 用户操作权重 (view=1.5, edit=2.0, ignore=-0.5)

对话连续性加权规则:
  - 符号在 accumulated_focus 中: +0.2
  - 符号在最近 3 轮 focus_symbols 中: +0.3
  - 符号与最近查询同文件: +0.1
  - 加权不超过原始分数的 50%

示例:
  # 记录一次查询
  intent-learner record handleToolCall src/server.ts::handleToolCall --action view

  # 查询偏好 Top 5
  intent-learner get-preferences --top 5

  # 查询 src/ 目录下的偏好
  intent-learner get-preferences --prefix src/

  # 清理超过 30 天的记录
  intent-learner cleanup --days 30

  # 保存对话上下文
  intent-learner context save --query "find auth module" --symbols "src/auth.ts,src/auth.ts::login"

  # 加载对话上下文
  intent-learner context load

  # 应用对话连续性加权
  intent-learner context apply-weight --results '[{"symbol":"src/auth.ts::login","score":0.8}]'

  # 创建新会话
  intent-learner session new

  # 列出会话
  intent-learner session list

  # 清除会话
  intent-learner session clear
EOF
}

# ==================== 主入口 ====================

main() {
    # 检查依赖
    if ! check_dependency "jq"; then
        log_error "缺少依赖: jq"
        log_info "请安装: brew install jq 或 apt install jq"
        exit $EXIT_DEPS_MISSING
    fi

    if [[ "${1:-}" == "--enable-all-features" ]]; then
        DEVBOOKS_ENABLE_ALL_FEATURES=1
        shift
    fi

    if declare -f is_feature_enabled &>/dev/null; then
        if ! is_feature_enabled "context_signals"; then
            # T-CS-008: 功能禁用时静默返回空数组，不输出警告（避免污染 stdout/stderr 混合输出）
            echo '[]'
            exit 0
        fi
    fi

    if [[ $# -lt 1 ]]; then
        show_help
        exit $EXIT_ARGS_ERROR
    fi

    local command="$1"
    shift

    case "$command" in
        record)
            cmd_record "$@"
            ;;
        get-preferences)
            cmd_get_preferences "$@"
            ;;
        cleanup)
            cmd_cleanup "$@"
            ;;
        context)
            cmd_context "$@"
            ;;
        session)
            cmd_session "$@"
            ;;
        --help|-h|help)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit $EXIT_ARGS_ERROR
            ;;
    esac
}

main "$@"
