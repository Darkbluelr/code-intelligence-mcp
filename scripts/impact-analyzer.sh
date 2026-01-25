#!/bin/bash
# impact-analyzer.sh - 传递性影响分析模块
# 版本: 1.0
# 用途: 多跳图遍历 + 置信度衰减算法，量化符号变更的传递性影响
#
# 覆盖 M2: 传递性影响分析模块
#   - AC-F02: 5 跳内置信度正确计算
#
# 核心算法: BFS + 置信度衰减
#   Impact(node, depth) = base_impact × (decay_factor ^ depth)
#
# 环境变量:
#   GRAPH_DB_PATH - 数据库路径，默认 .devbooks/graph.db
#   DEVBOOKS_DIR - 工作目录，默认 .devbooks

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀
export LOG_PREFIX="impact-analyzer"

# ==================== 配置 ====================

# 默认数据库路径
: "${DEVBOOKS_DIR:=.devbooks}"
: "${GRAPH_DB_PATH:=$DEVBOOKS_DIR/graph.db}"

# 默认参数
DEFAULT_MAX_DEPTH=5
DEFAULT_DECAY_FACTOR="0.8"
DEFAULT_THRESHOLD="0.1"

# 加载功能开关配置（如果存在）
FEATURES_CONFIG="${FEATURES_CONFIG:-config/features.yaml}"
if [[ -f "$FEATURES_CONFIG" ]]; then
    # 尝试从配置文件读取默认值
    _config_depth=$(awk '/impact_analyzer:/,/^[^ ]/ { if (/max_depth:/) { gsub(/.*:[ ]*/, ""); gsub(/[[:space:]]/, ""); print; exit } }' "$FEATURES_CONFIG" 2>/dev/null)
    _config_decay=$(awk '/impact_analyzer:/,/^[^ ]/ { if (/decay_factor:/) { gsub(/.*:[ ]*/, ""); gsub(/[[:space:]]/, ""); print; exit } }' "$FEATURES_CONFIG" 2>/dev/null)
    _config_threshold=$(awk '/impact_analyzer:/,/^[^ ]/ { if (/threshold:/) { gsub(/.*:[ ]*/, ""); gsub(/[[:space:]]/, ""); print; exit } }' "$FEATURES_CONFIG" 2>/dev/null)

    [[ -n "${_config_depth:-}" ]] && DEFAULT_MAX_DEPTH="$_config_depth"
    [[ -n "${_config_decay:-}" ]] && DEFAULT_DECAY_FACTOR="$_config_decay"
    [[ -n "${_config_threshold:-}" ]] && DEFAULT_THRESHOLD="$_config_threshold"
fi

# ==================== 辅助函数 ====================

# 检查数据库是否存在
check_database() {
    if [[ ! -f "$GRAPH_DB_PATH" ]]; then
        log_error "Graph database not found: $GRAPH_DB_PATH"
        log_info "Run 'graph-store.sh init' to initialize the database"
        return 1
    fi
}

# 执行 SQL 查询
run_sql() {
    local sql="$1"
    sqlite3 "$GRAPH_DB_PATH" "$sql"
}

# 浮点数比较: a >= b
float_gte() {
    local a="$1"
    local b="$2"
    awk -v a="$a" -v b="$b" 'BEGIN { exit !(a >= b) }'
}

# 浮点数乘法
float_mul() {
    local a="$1"
    local b="$2"
    awk -v a="$a" -v b="$b" 'BEGIN { printf "%.6f", a * b }'
}

# 浮点数幂运算: base ^ exp
float_pow() {
    local base="$1"
    local exp="$2"
    awk -v base="$base" -v exp="$exp" 'BEGIN { printf "%.6f", base ^ exp }'
}

# 获取符号的被调用者（正向遍历 CALLS 边）
# 在影响分析中，如果 A 变化，A 所调用的 B 也会受到影响
# 返回格式: target_id|symbol|file_path (一行一个)
get_downstream_nodes() {
    local symbol_id="$1"
    # 在 edges 表中，source -> target 表示 source 调用 target
    # 所以下游节点是 target（被调用者）
    run_sql "SELECT e.target_id, n.symbol, n.file_path
             FROM edges e
             JOIN nodes n ON e.target_id = n.id
             WHERE e.source_id = '$(echo "$symbol_id" | sed "s/'/''/g")'
             AND e.edge_type = 'CALLS';" | \
        sed 's/|/\t/g' | while IFS=$'\t' read -r id sym file; do
            echo "${id}|${sym}|${file}"
        done
}

# 获取符号的调用者（反向遍历 CALLS 边）
# 在文件级影响分析中，如果文件中的符号变化，调用它的代码会受影响
# 返回格式: source_id|symbol|file_path (一行一个)
get_upstream_nodes() {
    local symbol_id="$1"
    # 在 edges 表中，source -> target 表示 source 调用 target
    # 所以上游节点是 source（调用者）
    run_sql "SELECT e.source_id, n.symbol, n.file_path
             FROM edges e
             JOIN nodes n ON e.source_id = n.id
             WHERE e.target_id = '$(echo "$symbol_id" | sed "s/'/''/g")'
             AND e.edge_type = 'CALLS';" | \
        sed 's/|/\t/g' | while IFS=$'\t' read -r id sym file; do
            echo "${id}|${sym}|${file}"
        done
}

# 获取符号信息
get_symbol_info() {
    local symbol_id="$1"
    run_sql "SELECT id, symbol, kind, file_path FROM nodes WHERE id = '$(echo "$symbol_id" | sed "s/'/''/g")';"
}

# 获取文件中的所有符号
get_file_symbols() {
    local file_path="$1"
    run_sql "SELECT id, symbol, kind FROM nodes WHERE file_path = '$(echo "$file_path" | sed "s/'/''/g")';" | \
        sed 's/|/\t/g' | while IFS=$'\t' read -r id sym kind; do
            echo "${id}|${sym}|${kind}"
        done
}

# ==================== 核心算法: BFS + 置信度衰减 ====================

# BFS 遍历并计算置信度
# 参数:
#   $1 - 起始符号 ID
#   $2 - 最大深度
#   $3 - 衰减系数
#   $4 - 阈值
# 返回: JSON 格式的影响矩阵
bfs_impact_analysis() {
    local start_symbol="$1"
    local max_depth="$2"
    local decay_factor="$3"
    local threshold="$4"

    # 使用临时文件存储队列和已访问集合
    local queue_file=$(mktemp)
    local visited_file=$(mktemp)
    local result_file=$(mktemp)

    trap "rm -f '$queue_file' '$visited_file' '$result_file'" EXIT

    # 初始化: 将起始节点加入队列
    # 格式: symbol_id|depth|impact
    echo "${start_symbol}|0|1.0" > "$queue_file"

    # 结果数组（不包含起始节点自身，因为它不是受影响的节点）
    echo "[]" > "$result_file"

    while [[ -s "$queue_file" ]]; do
        # 从队列头部取出一个节点
        local current
        current=$(head -1 "$queue_file")
        tail -n +2 "$queue_file" > "${queue_file}.tmp"
        mv "${queue_file}.tmp" "$queue_file"

        # 解析节点信息
        local node_id depth impact
        node_id=$(echo "$current" | cut -d'|' -f1)
        depth=$(echo "$current" | cut -d'|' -f2)
        impact=$(echo "$current" | cut -d'|' -f3)

        # 检查是否已访问
        if grep -qF "$node_id" "$visited_file" 2>/dev/null; then
            continue
        fi

        # 标记为已访问
        echo "$node_id" >> "$visited_file"

        # 如果不是起始节点且影响度 >= 阈值，添加到结果
        if [[ "$node_id" != "$start_symbol" ]] && float_gte "$impact" "$threshold"; then
            # 获取符号信息
            local info
            info=$(get_symbol_info "$node_id")
            if [[ -n "$info" ]]; then
                local sym file kind
                sym=$(echo "$info" | cut -d'|' -f2)
                kind=$(echo "$info" | cut -d'|' -f3)
                file=$(echo "$info" | cut -d'|' -f4)

                # 读取当前结果，添加新节点
                local current_result
                current_result=$(cat "$result_file")
                # 使用 jq 添加新元素
                echo "$current_result" | jq --arg id "$node_id" \
                                            --arg sym "$sym" \
                                            --arg kind "$kind" \
                                            --arg file "$file" \
                                            --argjson depth "$depth" \
                                            --argjson impact "$impact" \
                    '. + [{"id": $id, "symbol": $sym, "kind": $kind, "file_path": $file, "depth": $depth, "confidence": ($impact | tonumber | . * 1000 | round / 1000)}]' \
                    > "${result_file}.tmp"
                mv "${result_file}.tmp" "$result_file"
            fi
        fi

        # 如果未达到最大深度，继续遍历
        if [[ "$depth" -lt "$max_depth" ]]; then
            local new_depth=$((depth + 1))
            local new_impact
            new_impact=$(float_mul "$impact" "$decay_factor")

            # 只有当新的影响度 >= 阈值时才继续
            if float_gte "$new_impact" "$threshold"; then
                # 获取下游节点（被当前符号调用的节点）
                # 如果 A 调用 B，当 A 变化时，B 也会受到影响
                local downstream
                downstream=$(get_downstream_nodes "$node_id")

                while IFS='|' read -r ds_id ds_sym ds_file; do
                    [[ -z "$ds_id" ]] && continue
                    # 检查是否已访问
                    if ! grep -qF "$ds_id" "$visited_file" 2>/dev/null; then
                        echo "${ds_id}|${new_depth}|${new_impact}" >> "$queue_file"
                    fi
                done <<< "$downstream"
            fi
        fi
    done

    # 返回结果，按影响度降序排列
    cat "$result_file" | jq 'sort_by(-.confidence)'
}

# 反向 BFS 遍历并计算置信度
# 用于文件级影响分析：找到所有依赖于给定符号的代码
# 参数:
#   $1 - 起始符号 ID
#   $2 - 最大深度
#   $3 - 衰减系数
#   $4 - 阈值
# 返回: JSON 格式的影响矩阵
bfs_reverse_impact_analysis() {
    local start_symbol="$1"
    local max_depth="$2"
    local decay_factor="$3"
    local threshold="$4"

    # 使用临时文件存储队列和已访问集合
    local queue_file=$(mktemp)
    local visited_file=$(mktemp)
    local result_file=$(mktemp)

    trap "rm -f '$queue_file' '$visited_file' '$result_file'" EXIT

    # 初始化: 将起始节点加入队列
    echo "${start_symbol}|0|1.0" > "$queue_file"

    # 结果数组
    echo "[]" > "$result_file"

    while [[ -s "$queue_file" ]]; do
        local current
        current=$(head -1 "$queue_file")
        tail -n +2 "$queue_file" > "${queue_file}.tmp"
        mv "${queue_file}.tmp" "$queue_file"

        local node_id depth impact
        node_id=$(echo "$current" | cut -d'|' -f1)
        depth=$(echo "$current" | cut -d'|' -f2)
        impact=$(echo "$current" | cut -d'|' -f3)

        if grep -qF "$node_id" "$visited_file" 2>/dev/null; then
            continue
        fi

        echo "$node_id" >> "$visited_file"

        if [[ "$node_id" != "$start_symbol" ]] && float_gte "$impact" "$threshold"; then
            local info
            info=$(get_symbol_info "$node_id")
            if [[ -n "$info" ]]; then
                local sym file kind
                sym=$(echo "$info" | cut -d'|' -f2)
                kind=$(echo "$info" | cut -d'|' -f3)
                file=$(echo "$info" | cut -d'|' -f4)

                local current_result
                current_result=$(cat "$result_file")
                echo "$current_result" | jq --arg id "$node_id" \
                                            --arg sym "$sym" \
                                            --arg kind "$kind" \
                                            --arg file "$file" \
                                            --argjson depth "$depth" \
                                            --argjson impact "$impact" \
                    '. + [{"id": $id, "symbol": $sym, "kind": $kind, "file_path": $file, "depth": $depth, "confidence": ($impact | tonumber | . * 1000 | round / 1000)}]' \
                    > "${result_file}.tmp"
                mv "${result_file}.tmp" "$result_file"
            fi
        fi

        if [[ "$depth" -lt "$max_depth" ]]; then
            local new_depth=$((depth + 1))
            local new_impact
            new_impact=$(float_mul "$impact" "$decay_factor")

            if float_gte "$new_impact" "$threshold"; then
                # 获取上游节点（调用当前符号的节点）
                # 如果 A 调用 B，当 B 变化时，A 会受到影响
                local upstream
                upstream=$(get_upstream_nodes "$node_id")

                while IFS='|' read -r us_id us_sym us_file; do
                    [[ -z "$us_id" ]] && continue
                    if ! grep -qF "$us_id" "$visited_file" 2>/dev/null; then
                        echo "${us_id}|${new_depth}|${new_impact}" >> "$queue_file"
                    fi
                done <<< "$upstream"
            fi
        fi
    done

    cat "$result_file" | jq 'sort_by(-.confidence)'
}

# ==================== 命令: analyze ====================

cmd_analyze() {
    local symbol=""
    local depth="$DEFAULT_MAX_DEPTH"
    local decay="$DEFAULT_DECAY_FACTOR"
    local threshold="$DEFAULT_THRESHOLD"
    local format="json"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth)
                depth="$2"
                shift 2
                ;;
            --decay)
                decay="$2"
                shift 2
                ;;
            --threshold)
                threshold="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                return $EXIT_ARGS_ERROR
                ;;
            *)
                if [[ -z "$symbol" ]]; then
                    symbol="$1"
                fi
                shift
                ;;
        esac
    done

    # 验证参数
    if [[ -z "$symbol" ]]; then
        log_error "Symbol argument is required"
        echo "Usage: impact-analyzer.sh analyze <symbol> [--depth <n>] [--threshold <t>] [--format json|md|mermaid]" >&2
        return $EXIT_ARGS_ERROR
    fi

    # 验证深度是否为正整数
    if ! [[ "$depth" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Depth must be a positive integer, got: $depth"
        return $EXIT_ARGS_ERROR
    fi

    # 验证阈值范围
    if ! awk -v t="$threshold" 'BEGIN { exit !(t >= 0 && t <= 1) }'; then
        log_error "Threshold must be between 0 and 1, got: $threshold"
        return $EXIT_ARGS_ERROR
    fi

    check_dependencies sqlite3 jq || return $EXIT_DEPS_MISSING
    check_database || return $EXIT_RUNTIME_ERROR

    # 执行 BFS 影响分析
    local affected_nodes
    affected_nodes=$(bfs_impact_analysis "$symbol" "$depth" "$decay" "$threshold")

    # 计算统计信息
    local total_affected
    total_affected=$(echo "$affected_nodes" | jq 'length')

    # 根据格式输出结果
    case "$format" in
        json)
            jq -n \
                --arg root "$symbol" \
                --argjson depth "$depth" \
                --argjson decay "$decay" \
                --argjson threshold "$threshold" \
                --argjson affected "$affected_nodes" \
                --argjson total "$total_affected" \
                '{
                    "root": $root,
                    "depth": $depth,
                    "decay_factor": $decay,
                    "threshold": $threshold,
                    "affected_nodes": $affected,
                    "total_affected": $total
                }'
            ;;
        mermaid)
            output_mermaid "$symbol" "$affected_nodes"
            ;;
        md|markdown)
            output_markdown "$symbol" "$affected_nodes" "$total_affected"
            ;;
        *)
            log_error "Unknown format: $format. Supported: json, md, mermaid"
            return $EXIT_ARGS_ERROR
            ;;
    esac
}

# ==================== 命令: file ====================

cmd_file() {
    local file_path=""
    local depth="$DEFAULT_MAX_DEPTH"
    local decay="$DEFAULT_DECAY_FACTOR"
    local threshold="$DEFAULT_THRESHOLD"
    local format="json"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth)
                depth="$2"
                shift 2
                ;;
            --decay)
                decay="$2"
                shift 2
                ;;
            --threshold)
                threshold="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                return $EXIT_ARGS_ERROR
                ;;
            *)
                if [[ -z "$file_path" ]]; then
                    file_path="$1"
                fi
                shift
                ;;
        esac
    done

    # 验证参数
    if [[ -z "$file_path" ]]; then
        log_error "File path argument is required"
        echo "Usage: impact-analyzer.sh file <file-path> [--depth <n>] [--threshold <t>]" >&2
        return $EXIT_ARGS_ERROR
    fi

    check_dependencies sqlite3 jq || return $EXIT_DEPS_MISSING
    check_database || return $EXIT_RUNTIME_ERROR

    # 获取文件中的所有符号
    local symbols
    symbols=$(get_file_symbols "$file_path")

    if [[ -z "$symbols" ]]; then
        log_warn "No symbols found in file: $file_path"
        # 返回空结果
        jq -n \
            --arg file "$file_path" \
            --argjson depth "$depth" \
            '{
                "file": $file,
                "depth": $depth,
                "affected_nodes": [],
                "total_affected": 0
            }'
        return 0
    fi

    # 对每个符号执行反向影响分析，然后合并去重
    # 文件级分析使用反向 BFS：找到所有依赖于文件中符号的代码
    local all_affected="[]"
    local visited_ids=""

    while IFS='|' read -r sym_id sym_name sym_kind; do
        [[ -z "$sym_id" ]] && continue

        local affected
        affected=$(bfs_reverse_impact_analysis "$sym_id" "$depth" "$decay" "$threshold")

        # 合并结果，去重
        while IFS= read -r node; do
            [[ -z "$node" || "$node" == "null" ]] && continue

            local node_id
            node_id=$(echo "$node" | jq -r '.id')

            # 检查是否已经在结果中
            if [[ ! "$visited_ids" =~ "$node_id" ]]; then
                visited_ids="${visited_ids}|${node_id}"
                all_affected=$(echo "$all_affected" | jq --argjson node "$node" '. + [$node]')
            fi
        done < <(echo "$affected" | jq -c '.[]')
    done <<< "$symbols"

    # 按影响度排序并计算总数
    all_affected=$(echo "$all_affected" | jq 'sort_by(-.confidence)')
    local total_affected
    total_affected=$(echo "$all_affected" | jq 'length')

    # 根据格式输出结果
    case "$format" in
        json)
            jq -n \
                --arg file "$file_path" \
                --argjson depth "$depth" \
                --argjson decay "$decay" \
                --argjson threshold "$threshold" \
                --argjson affected "$all_affected" \
                --argjson total "$total_affected" \
                '{
                    "file": $file,
                    "depth": $depth,
                    "decay_factor": $decay,
                    "threshold": $threshold,
                    "affected_nodes": $affected,
                    "total_affected": $total
                }'
            ;;
        mermaid)
            output_mermaid "$file_path" "$all_affected"
            ;;
        md|markdown)
            output_markdown "$file_path" "$all_affected" "$total_affected"
            ;;
        *)
            log_error "Unknown format: $format"
            return $EXIT_ARGS_ERROR
            ;;
    esac
}

# ==================== 输出格式函数 ====================

# 输出 Mermaid 格式
output_mermaid() {
    local root="$1"
    local affected_nodes="$2"

    # 获取根节点的简短名称
    local root_name
    root_name=$(echo "$root" | sed 's/.*:://' | sed 's/sym:func://' | sed 's/sym://')

    echo "graph TD"
    echo "    ${root_name}[${root_name}:1.0]"

    # 为每个受影响的节点生成边
    echo "$affected_nodes" | jq -r '.[] | "\(.symbol)|\(.confidence)|\(.depth)"' | while IFS='|' read -r sym conf dep; do
        [[ -z "$sym" ]] && continue

        # 找到父节点（深度 - 1）
        # 简化处理：将所有深度为 1 的节点连接到根节点
        # 深度 > 1 的节点连接到前一深度的某个节点
        local conf_display
        conf_display=$(printf "%.2f" "$conf")

        if [[ "$dep" -eq 1 ]]; then
            echo "    ${root_name} -->|${conf_display}| ${sym}[${sym}:${conf_display}]"
        fi
    done

    # 处理更深层次的连接（需要根据实际依赖关系）
    # 这里简化为线性连接，实际应该根据图数据库的边信息
    local prev_sym=""
    local prev_depth=0
    echo "$affected_nodes" | jq -r 'sort_by(.depth) | .[] | "\(.symbol)|\(.confidence)|\(.depth)"' | while IFS='|' read -r sym conf dep; do
        [[ -z "$sym" ]] && continue

        local conf_display
        conf_display=$(printf "%.2f" "$conf")

        if [[ "$dep" -gt 1 && -n "$prev_sym" && "$prev_depth" -eq $((dep - 1)) ]]; then
            echo "    ${prev_sym} -->|${conf_display}| ${sym}[${sym}:${conf_display}]"
        fi

        prev_sym="$sym"
        prev_depth="$dep"
    done
}

# 输出 Markdown 格式
output_markdown() {
    local root="$1"
    local affected_nodes="$2"
    local total="$3"

    echo "# Impact Analysis: $root"
    echo ""
    echo "**Total Affected Nodes**: $total"
    echo ""
    echo "| Symbol | File | Depth | Confidence |"
    echo "|--------|------|-------|------------|"

    echo "$affected_nodes" | jq -r '.[] | "| \(.symbol) | \(.file_path) | \(.depth) | \(.confidence) |"'
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
impact-analyzer.sh - 传递性影响分析

用法:
    impact-analyzer.sh <command> [options]

命令:
    analyze <symbol>        符号级影响分析
    file <file-path>        文件级影响分析

analyze 选项:
    --depth <n>             最大遍历深度（默认 5）
    --decay <factor>        衰减系数（默认 0.8）
    --threshold <t>         影响阈值（默认 0.1）
    --format <fmt>          输出格式: json | md | mermaid（默认 json）

file 选项:
    --depth <n>             最大遍历深度（默认 5）
    --decay <factor>        衰减系数（默认 0.8）
    --threshold <t>         影响阈值（默认 0.1）
    --format <fmt>          输出格式: json | md | mermaid（默认 json）

置信度计算公式:
    Impact(node, depth) = base_impact × (decay_factor ^ depth)

    示例（decay_factor = 0.8）:
    - 深度 0: 1.0（起始节点）
    - 深度 1: 0.8
    - 深度 2: 0.64
    - 深度 3: 0.512
    - 深度 4: 0.4096
    - 深度 5: 0.328

环境变量:
    GRAPH_DB_PATH           数据库路径（默认: .devbooks/graph.db）

示例:
    # 分析符号影响
    impact-analyzer.sh analyze "sym:func:handleToolCall" --depth 3

    # 分析文件影响
    impact-analyzer.sh file "src/server.ts" --depth 3

    # 使用阈值过滤低影响节点
    impact-analyzer.sh analyze "sym:func:main" --threshold 0.5

    # 输出 Mermaid 流程图
    impact-analyzer.sh analyze "sym:func:main" --format mermaid

EOF
}

# ==================== 主入口 ====================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        analyze)
            cmd_analyze "$@"
            ;;
        file)
            cmd_file "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit $EXIT_ARGS_ERROR
            ;;
    esac
}

# 仅在直接执行时运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
