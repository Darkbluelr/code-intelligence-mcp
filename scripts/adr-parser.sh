#!/bin/bash
# adr-parser.sh - ADR (Architecture Decision Records) 解析与关联脚本
# 版本: 1.0
# 用途: 解析 MADR 和 Nygard 格式的 ADR 文件，提取关键词并关联到代码图
#
# Trace: AC-G03
# 覆盖需求: REQ-ADR-001~007
#
# 环境变量:
#   DEVBOOKS_DIR - 工作目录，默认 .devbooks
#   GRAPH_DB_PATH - 图数据库路径，默认 .devbooks/graph.db
#   ADR_INDEX_PATH - ADR 索引文件路径，默认 .devbooks/adr-index.json

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀
export LOG_PREFIX="adr-parser"

# ==================== 配置 ====================

: "${DEVBOOKS_DIR:=.devbooks}"
: "${GRAPH_DB_PATH:=$DEVBOOKS_DIR/graph.db}"
: "${ADR_INDEX_PATH:=$DEVBOOKS_DIR/adr-index.json}"

# ADR 搜索路径（按优先级）
ADR_SEARCH_PATHS=("docs/adr" "doc/adr" "ADR" "adr")

# 通用停用词（过滤掉过短或过于通用的词）
STOP_WORDS=(
    "the" "a" "an" "is" "are" "was" "were" "be" "been" "being"
    "have" "has" "had" "do" "does" "did" "will" "would" "could" "should"
    "may" "might" "must" "shall" "can" "need" "dare" "ought" "used"
    "we" "our" "us" "they" "them" "their" "it" "its" "this" "that"
    "which" "who" "whom" "what" "where" "when" "why" "how"
    "and" "or" "but" "if" "then" "else" "for" "of" "to" "from"
    "in" "on" "at" "by" "with" "about" "against" "between" "into"
    "through" "during" "before" "after" "above" "below" "up" "down"
    "out" "off" "over" "under" "again" "further" "once"
    "all" "any" "both" "each" "few" "more" "most" "other" "some" "such"
    "no" "nor" "not" "only" "own" "same" "so" "than" "too" "very"
    "just" "also" "now" "here" "there"
    "use" "using" "used"
    # 常见通用英文词
    "cache" "data" "system" "simple" "record" "mode" "need" "make"
    "context" "decision" "status" "title" "file" "path" "type" "name"
)

# ==================== 辅助函数 ====================

# 检查是否为停用词
is_stop_word() {
    local word="$1"
    local lower_word
    lower_word=$(echo "$word" | tr '[:upper:]' '[:lower:]')

    # 检查长度（< 3 字符）
    if [[ ${#lower_word} -lt 3 ]]; then
        return 0  # 是停用词
    fi

    # 检查停用词列表
    for stop in "${STOP_WORDS[@]}"; do
        if [[ "$lower_word" == "$stop" ]]; then
            return 0  # 是停用词
        fi
    done

    return 1  # 不是停用词
}

# 清理关键词（去除标点等）
clean_keyword() {
    local word="$1"
    # 移除前后标点，保留 - _ . /
    echo "$word" | sed 's/^[^a-zA-Z0-9_\-\.\/]*//' | sed 's/[^a-zA-Z0-9_\-\.\/]*$//'
}

# 发现 ADR 目录
# REQ-ADR-001
find_adr_dir() {
    local base_dir="${1:-.}"

    for search_path in "${ADR_SEARCH_PATHS[@]}"; do
        local full_path="$base_dir/$search_path"
        if [[ -d "$full_path" ]]; then
            # 检查目录非空（包含 .md 文件）
            if ls "$full_path"/*.md &>/dev/null; then
                echo "$full_path"
                return 0
            fi
        fi
    done

    # 未找到 ADR 目录
    return 1
}

# 检测 ADR 格式（MADR 或 Nygard）
# REQ-ADR-002, REQ-ADR-003
detect_adr_format() {
    local file="$1"

    # 读取第一行标题
    local first_line
    first_line=$(head -1 "$file" | tr -d '\r')

    # MADR 格式: # ADR-xxx: Title
    if [[ "$first_line" =~ ^#[[:space:]]*ADR-[0-9]+: ]]; then
        echo "madr"
        return 0
    fi

    # Nygard 格式: # N. Title（数字开头）
    if [[ "$first_line" =~ ^#[[:space:]]*[0-9]+\.[[:space:]] ]]; then
        echo "nygard"
        return 0
    fi

    # 未知格式，尝试 MADR 解析
    echo "unknown"
    return 0
}

# 提取章节内容
# 参数: $1 - 文件路径, $2 - 章节名
extract_section() {
    local file="$1"
    local section="$2"

    awk -v section="$section" '
        BEGIN { in_section = 0; content = "" }
        /^##[[:space:]]/ {
            if (in_section) { exit }
            gsub(/^##[[:space:]]*/, "")
            gsub(/[[:space:]]*$/, "")
            if (tolower($0) == tolower(section)) {
                in_section = 1
                next
            }
        }
        in_section && /^[^#]/ {
            # 去除空行前后的内容
            gsub(/^[[:space:]]+/, "")
            gsub(/[[:space:]]+$/, "")
            if (length($0) > 0) {
                if (length(content) > 0) content = content " "
                content = content $0
            }
        }
        END { print content }
    ' "$file"
}

# 解析 MADR 格式
# REQ-ADR-002
parse_madr() {
    local file="$1"

    # 提取 ID 和标题
    local first_line
    first_line=$(head -1 "$file" | tr -d '\r')

    local adr_id=""
    local title=""

    if [[ "$first_line" =~ ^#[[:space:]]*(ADR-[0-9]+):[[:space:]]*(.*)$ ]]; then
        adr_id="${BASH_REMATCH[1]}"
        title="${BASH_REMATCH[2]}"
    fi

    # 提取各章节
    local status
    status=$(extract_section "$file" "Status")
    [[ -z "$status" ]] && status="Unknown"

    local context
    context=$(extract_section "$file" "Context")

    local decision
    decision=$(extract_section "$file" "Decision")

    local consequences
    consequences=$(extract_section "$file" "Consequences")

    # 输出 JSON
    jq -n \
        --arg id "$adr_id" \
        --arg title "$title" \
        --arg status "$status" \
        --arg context "$context" \
        --arg decision "$decision" \
        --arg consequences "$consequences" \
        --arg file_path "$file" \
        --arg format "madr" \
        '{
            id: $id,
            title: $title,
            status: $status,
            context: $context,
            decision: $decision,
            consequences: $consequences,
            file_path: $file_path,
            format: $format
        }'
}

# 解析 Nygard 格式
# REQ-ADR-003
parse_nygard() {
    local file="$1"

    # 提取 ID 和标题
    local first_line
    first_line=$(head -1 "$file" | tr -d '\r')

    local adr_id=""
    local title=""

    if [[ "$first_line" =~ ^#[[:space:]]*([0-9]+)\.[[:space:]]*(.*)$ ]]; then
        adr_id="${BASH_REMATCH[1]}"
        title="${BASH_REMATCH[2]}"
    fi

    # 提取 Date（Nygard 格式特有）
    local adr_date=""
    adr_date=$(grep -E "^Date:" "$file" 2>/dev/null | head -1 | sed 's/^Date:[[:space:]]*//' | tr -d '\r')

    # 提取各章节
    local status
    status=$(extract_section "$file" "Status")
    [[ -z "$status" ]] && status="Unknown"

    local context
    context=$(extract_section "$file" "Context")

    local decision
    decision=$(extract_section "$file" "Decision")

    local consequences
    consequences=$(extract_section "$file" "Consequences")

    # 输出 JSON
    jq -n \
        --arg id "$adr_id" \
        --arg title "$title" \
        --arg status "$status" \
        --arg date "$adr_date" \
        --arg context "$context" \
        --arg decision "$decision" \
        --arg consequences "$consequences" \
        --arg file_path "$file" \
        --arg format "nygard" \
        '{
            id: $id,
            title: $title,
            status: $status,
            date: $date,
            context: $context,
            decision: $decision,
            consequences: $consequences,
            file_path: $file_path,
            format: $format
        }'
}

# 解析单个 ADR 文件
parse_adr_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "文件不存在: $file"
        return 1
    fi

    local format
    format=$(detect_adr_format "$file")

    case "$format" in
        madr)
            parse_madr "$file"
            ;;
        nygard)
            parse_nygard "$file"
            ;;
        *)
            # 尝试 MADR 解析
            parse_madr "$file"
            ;;
    esac
}

# 提取关键词
# REQ-ADR-004
extract_keywords() {
    local adr_json="$1"

    # 从 decision、context、title 中提取关键词
    local decision context title
    decision=$(echo "$adr_json" | jq -r '.decision // ""')
    context=$(echo "$adr_json" | jq -r '.context // ""')
    title=$(echo "$adr_json" | jq -r '.title // ""')

    local all_text="$title $decision $context"
    local keywords=()

    # 1. 提取反引号包裹的代码标识符
    while IFS= read -r match; do
        [[ -n "$match" ]] && keywords+=("$match")
    done < <(echo "$all_text" | grep -oE '\`[^\`]+\`' | sed 's/\`//g')

    # 2. 提取 PascalCase 标识符（包括 SQLite 这类混合大小写术语）
    while IFS= read -r match; do
        if [[ -n "$match" ]] && ! is_stop_word "$match"; then
            keywords+=("$match")
        fi
    done < <(echo "$all_text" | grep -oE '\b[A-Z][a-z]+([A-Z][a-z]*)+\b')

    # 2b. 提取首字母大写的技术术语（如 SQLite）
    while IFS= read -r match; do
        if [[ -n "$match" ]] && ! is_stop_word "$match" && [[ ${#match} -ge 4 ]]; then
            keywords+=("$match")
        fi
    done < <(echo "$all_text" | grep -oE '\b[A-Z][a-zA-Z]+\b')

    # 3. 提取 camelCase 标识符
    while IFS= read -r match; do
        if [[ -n "$match" ]] && ! is_stop_word "$match"; then
            keywords+=("$match")
        fi
    done < <(echo "$all_text" | grep -oE '\b[a-z]+([A-Z][a-z]+)+\b')

    # 4. 提取 SCREAMING_CASE 标识符
    while IFS= read -r match; do
        if [[ -n "$match" ]] && ! is_stop_word "$match"; then
            keywords+=("$match")
        fi
    done < <(echo "$all_text" | grep -oE '\b[A-Z][A-Z_]+\b')

    # 5. 提取文件路径（使用 POSIX 兼容的范围）
    while IFS= read -r match; do
        [[ -n "$match" ]] && keywords+=("$match")
    done < <(echo "$all_text" | grep -oE '[a-zA-Z0-9_-]+\.(ts|tsx|js|jsx|py|go|sh|md)' 2>/dev/null || true)

    # 6. 提取带路径的文件
    while IFS= read -r match; do
        [[ -n "$match" ]] && keywords+=("$match")
    done < <(echo "$all_text" | grep -oE '[a-zA-Z0-9_/.-]+\.(ts|tsx|js|jsx|py|go|sh)' 2>/dev/null || true)

    # 去重并清理
    local unique_keywords=()

    # 处理空数组的情况
    if [[ ${#keywords[@]} -eq 0 ]]; then
        echo '[]'
        return 0
    fi

    # 使用关联数组模式进行去重（兼容 bash 3）
    local seen_list=""
    for kw in "${keywords[@]}"; do
        local cleaned
        cleaned=$(clean_keyword "$kw")
        if [[ -n "$cleaned" && ${#cleaned} -ge 3 ]]; then
            # 检查是否已见过
            if [[ "$seen_list" != *"|$cleaned|"* ]]; then
                seen_list="${seen_list}|$cleaned|"
                unique_keywords+=("$cleaned")
            fi
        fi
    done

    # 输出 JSON 数组
    if [[ ${#unique_keywords[@]} -eq 0 ]]; then
        echo '[]'
        return 0
    fi
    printf '%s\n' "${unique_keywords[@]}" | jq -R . | jq -s .
}

# 关联关键词到图节点
# REQ-ADR-005
link_keywords_to_graph() {
    local adr_id="$1"
    local keywords_json="$2"

    if [[ ! -f "$GRAPH_DB_PATH" ]]; then
        log_info "graph.db 不存在，跳过关联"
        echo '{"related_nodes": [], "edges_added": 0}'
        return 0
    fi

    local related_nodes=()
    local edges_added=0

    # 遍历关键词
    while IFS= read -r keyword; do
        [[ -z "$keyword" ]] && continue

        # 在 graph.db 中搜索匹配的节点
        # 1. 精确匹配 symbol
        # 2. 文件路径匹配
        # 3. 部分匹配 symbol

        local matches
        matches=$(sqlite3 "$GRAPH_DB_PATH" "
            SELECT id, symbol, file_path FROM nodes
            WHERE symbol = '$(echo "$keyword" | sed "s/'/''/g")'
               OR file_path LIKE '%$(echo "$keyword" | sed "s/'/''/g")%'
               OR symbol LIKE '%$(echo "$keyword" | sed "s/'/''/g")%'
            LIMIT 10;
        " 2>/dev/null || true)

        if [[ -n "$matches" ]]; then
            # shellcheck disable=SC2034
            while IFS='|' read -r node_id symbol file_path; do
                [[ -z "$node_id" ]] && continue

                # 添加到相关节点列表
                related_nodes+=("$node_id")

                # 生成 ADR_RELATED 边
                local edge_id
                edge_id="edge:adr:$(date +%s)-$RANDOM"
                local source_id="adr:$adr_id"

                # 检查边是否已存在
                local existing
                existing=$(sqlite3 "$GRAPH_DB_PATH" "
                    SELECT COUNT(*) FROM edges
                    WHERE source_id = '$source_id'
                      AND target_id = '$(echo "$node_id" | sed "s/'/''/g")'
                      AND edge_type = 'ADR_RELATED';
                " 2>/dev/null || echo "0")

                if [[ "$existing" == "0" ]]; then
                    # 插入新边
                    sqlite3 "$GRAPH_DB_PATH" "
                        INSERT INTO edges (id, source_id, target_id, edge_type)
                        VALUES ('$edge_id', '$source_id', '$(echo "$node_id" | sed "s/'/''/g")', 'ADR_RELATED');
                    " 2>/dev/null && ((edges_added++)) || true
                fi
            done <<< "$matches"
        fi
    done < <(echo "$keywords_json" | jq -r '.[]')

    # 去重相关节点
    local unique_nodes
    if [[ ${#related_nodes[@]} -eq 0 ]]; then
        unique_nodes='[]'
    else
        unique_nodes=$(printf '%s\n' "${related_nodes[@]}" | sort -u | jq -R . | jq -s .)
    fi

    jq -n \
        --argjson related_nodes "$unique_nodes" \
        --argjson edges_added "$edges_added" \
        '{related_nodes: $related_nodes, edges_added: $edges_added}'
}

# ==================== 命令: parse ====================

cmd_parse() {
    local file=""
    local format="json"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            *) file="$1"; shift ;;
        esac
    done

    if [[ -z "$file" ]]; then
        log_error "请指定 ADR 文件路径"
        return $EXIT_ARGS_ERROR
    fi

    check_dependencies jq || return $EXIT_DEPS_MISSING

    local adr_json
    adr_json=$(parse_adr_file "$file")

    # 提取关键词
    local keywords_json
    keywords_json=$(extract_keywords "$adr_json")

    # 合并输出
    local result
    result=$(echo "$adr_json" | jq --argjson keywords "$keywords_json" '. + {keywords: $keywords}')

    # 包装为 adrs 数组格式
    jq -n --argjson adr "$result" '{adrs: [$adr], edges_generated: 0}'
}

# ==================== 命令: keywords ====================

cmd_keywords() {
    local file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            *) file="$1"; shift ;;
        esac
    done

    if [[ -z "$file" ]]; then
        log_error "请指定 ADR 文件路径"
        return $EXIT_ARGS_ERROR
    fi

    check_dependencies jq || return $EXIT_DEPS_MISSING

    local adr_json
    adr_json=$(parse_adr_file "$file")

    extract_keywords "$adr_json"
}

# ==================== 命令: scan ====================

cmd_scan() {
    local adr_dir=""
    local link=false
    local format="json"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --adr-dir) adr_dir="$2"; shift 2 ;;
            --link) link=true; shift ;;
            --format) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    check_dependencies jq || return $EXIT_DEPS_MISSING

    # 发现 ADR 目录
    if [[ -z "$adr_dir" ]]; then
        adr_dir=$(find_adr_dir "." 2>/dev/null) || true
    fi

    # 无 ADR 目录时优雅返回
    # REQ-ADR-001: 无 ADR 目录时返回空列表，不报错
    if [[ -z "$adr_dir" || ! -d "$adr_dir" ]]; then
        log_info "未找到 ADR 目录，返回空结果"
        echo '{"adrs": [], "edges_generated": 0}'
        return 0
    fi

    local adrs=()
    local total_edges=0

    # 遍历 ADR 文件
    for adr_file in "$adr_dir"/*.md; do
        [[ -f "$adr_file" ]] || continue

        log_info "解析: $adr_file"

        # 解析 ADR
        local adr_json
        adr_json=$(parse_adr_file "$adr_file")

        # 提取关键词
        local keywords_json
        keywords_json=$(extract_keywords "$adr_json")

        # 合并关键词到 ADR
        adr_json=$(echo "$adr_json" | jq --argjson keywords "$keywords_json" '. + {keywords: $keywords}')

        # 如果启用 --link，关联到图
        if $link; then
            local adr_id
            adr_id=$(echo "$adr_json" | jq -r '.id')

            local link_result
            link_result=$(link_keywords_to_graph "$adr_id" "$keywords_json")

            local edges_added
            edges_added=$(echo "$link_result" | jq -r '.edges_added')
            ((total_edges += edges_added)) || true

            local related_nodes
            related_nodes=$(echo "$link_result" | jq '.related_nodes')

            adr_json=$(echo "$adr_json" | jq --argjson related "$related_nodes" '. + {related_nodes: $related}')
        fi

        adrs+=("$adr_json")
    done

    # 构建输出
    local adrs_array
    if [[ ${#adrs[@]} -eq 0 ]]; then
        adrs_array='[]'
    else
        adrs_array=$(printf '%s\n' "${adrs[@]}" | jq -s .)
    fi

    local result
    result=$(jq -n \
        --argjson adrs "$adrs_array" \
        --argjson edges "$total_edges" \
        '{adrs: $adrs, edges_generated: $edges}')

    # 如果启用 --link，更新索引文件
    # REQ-ADR-007
    if $link; then
        update_adr_index "$result"
    fi

    echo "$result"
}

# ==================== 命令: status ====================

cmd_status() {
    check_dependencies jq || return $EXIT_DEPS_MISSING

    local adr_dir
    adr_dir=$(find_adr_dir "." 2>/dev/null) || true

    local adr_count=0
    local index_exists=false
    local index_mtime=""
    local edge_count=0

    if [[ -n "$adr_dir" && -d "$adr_dir" ]]; then
        adr_count=$(ls "$adr_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [[ -f "$ADR_INDEX_PATH" ]]; then
        index_exists=true
        index_mtime=$(stat -f "%m" "$ADR_INDEX_PATH" 2>/dev/null || stat -c "%Y" "$ADR_INDEX_PATH" 2>/dev/null || echo "0")
    fi

    if [[ -f "$GRAPH_DB_PATH" ]]; then
        edge_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='ADR_RELATED';" 2>/dev/null || echo "0")
    fi

    jq -n \
        --arg adr_dir "${adr_dir:-none}" \
        --argjson adr_count "$adr_count" \
        --argjson index_exists "$index_exists" \
        --arg index_mtime "$index_mtime" \
        --argjson edge_count "$edge_count" \
        '{
            adr_directory: $adr_dir,
            adr_file_count: $adr_count,
            index_exists: $index_exists,
            index_last_updated: $index_mtime,
            adr_related_edges: $edge_count
        }'
}

# ==================== 索引更新 ====================

# 更新 ADR 索引文件
# REQ-ADR-007: 增量更新（检测 ADR 文件 mtime）
update_adr_index() {
    local scan_result="$1"

    # 确保目录存在
    mkdir -p "$(dirname "$ADR_INDEX_PATH")"

    local now
    now=$(date +%s)

    # 添加时间戳和元数据
    local index_content
    index_content=$(echo "$scan_result" | jq \
        --argjson updated_at "$now" \
        '. + {updated_at: $updated_at, version: "1.0"}')

    echo "$index_content" > "$ADR_INDEX_PATH"
    log_ok "索引已更新: $ADR_INDEX_PATH"
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
adr-parser.sh - ADR 解析与关联

用法:
    adr-parser.sh <command> [options]

命令:
    parse <file>        解析单个 ADR 文件
    keywords <file>     提取单个 ADR 的关键词
    scan [options]      扫描所有 ADR 文件
    status              显示 ADR 索引状态

parse 选项:
    --format json|text  输出格式（默认 json）

scan 选项:
    --adr-dir <path>    指定 ADR 目录（覆盖自动发现）
    --link              生成关联边写入 graph.db
    --format json|text  输出格式（默认 json）

支持的 ADR 格式:
    - MADR (Markdown Architectural Decision Records)
      标题格式: # ADR-xxx: Title

    - Nygard (Michael Nygard 原始格式)
      标题格式: # N. Title

自动发现路径（按优先级）:
    1. docs/adr/
    2. doc/adr/
    3. ADR/
    4. adr/

环境变量:
    DEVBOOKS_DIR        工作目录（默认: .devbooks）
    GRAPH_DB_PATH       图数据库路径（默认: .devbooks/graph.db）
    ADR_INDEX_PATH      索引文件路径（默认: .devbooks/adr-index.json）

示例:
    # 解析单个 ADR
    adr-parser.sh parse docs/adr/0001-use-sqlite.md

    # 扫描所有 ADR
    adr-parser.sh scan

    # 扫描并关联到代码图
    adr-parser.sh scan --link

    # 查看索引状态
    adr-parser.sh status
EOF
}

# ==================== 主入口 ====================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        parse)
            cmd_parse "$@"
            ;;
        keywords)
            cmd_keywords "$@"
            ;;
        scan)
            cmd_scan "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit $EXIT_ARGS_ERROR
            ;;
    esac
}

# 仅在直接执行时运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
