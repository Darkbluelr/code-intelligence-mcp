#!/bin/bash
# cod-visualizer.sh - COD (Code Overview Diagram) 架构可视化模块
# 版本: 1.0
# 用途: 生成代码库概览图，支持 Mermaid 和 D3.js JSON 格式
#
# 覆盖 M3: COD 架构可视化模块
# 验收标准: AC-F03 - Mermaid 输出可在 Mermaid Live Editor 渲染
#
# 环境变量:
#   GRAPH_DB_PATH - 数据库路径，默认 .devbooks/graph.db
#   DEVBOOKS_DIR - 工作目录，默认 .devbooks

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀
export LOG_PREFIX="cod-visualizer"

# ==================== 配置 ====================

# 默认数据库路径
: "${DEVBOOKS_DIR:=.devbooks}"
: "${GRAPH_DB_PATH:=$DEVBOOKS_DIR/graph.db}"

# 默认参数
DEFAULT_LEVEL=2
DEFAULT_FORMAT="mermaid"

# 热点着色阈值
HOTSPOT_HIGH_THRESHOLD=0.7
HOTSPOT_MED_THRESHOLD=0.3

# 热点颜色
HOTSPOT_COLOR_HIGH="#ff6b6b"  # 红色
HOTSPOT_COLOR_MED="#ffd93d"   # 黄色
HOTSPOT_COLOR_LOW="#69db7c"   # 绿色（默认）

# ==================== 功能开关检查 ====================

# 检查 cod_visualizer 功能是否启用
_check_feature_enabled() {
    local config_file="${FEATURES_CONFIG:-config/features.yaml}"

    if [[ ! -f "$config_file" ]]; then
        return 0  # 配置文件不存在则默认启用
    fi

    local enabled
    enabled=$(awk '
        BEGIN { in_cod = 0 }
        /^[[:space:]]*cod_visualizer:/ { in_cod = 1; next }
        /^[[:space:]]*[a-zA-Z_]+:/ && !/^[[:space:]]*enabled:/ { in_cod = 0 }
        in_cod && /enabled:/ {
            gsub(/.*enabled:[[:space:]]*/, "")
            gsub(/[[:space:]]*#.*/, "")
            print
            exit
        }
    ' "$config_file" 2>/dev/null)

    case "$enabled" in
        false|False|FALSE|no|No|NO|0)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# ==================== 辅助函数 ====================

# 检查数据库是否存在
_check_db() {
    if [[ ! -f "$GRAPH_DB_PATH" ]]; then
        return 1
    fi
    return 0
}

# 执行 SQL 查询
_run_sql() {
    local sql="$1"
    sqlite3 "$GRAPH_DB_PATH" "$sql" 2>/dev/null
}

# 执行 SQL 查询返回 JSON
_run_sql_json() {
    local sql="$1"
    sqlite3 -json "$GRAPH_DB_PATH" "$sql" 2>/dev/null
}

# 转义 Mermaid 节点 ID（移除特殊字符）
_escape_mermaid_id() {
    local id="$1"
    # 替换特殊字符为下划线
    echo "$id" | sed 's/[^a-zA-Z0-9_]/_/g' | sed 's/__*/_/g' | sed 's/^_//' | sed 's/_$//'
}

# 转义 Mermaid 标签（处理引号）
_escape_mermaid_label() {
    local label="$1"
    # 移除路径，只保留文件名
    echo "$label" | sed 's/.*\///' | sed 's/"//g'
}

# 获取热点分数（0.0 - 1.0）
_get_hotspot_score() {
    local file_path="$1"
    local hotspot_script="$SCRIPT_DIR/hotspot-analyzer.sh"

    if [[ ! -x "$hotspot_script" ]]; then
        echo "0.0"
        return
    fi

    # 尝试从热点分析器获取分数（简化实现）
    # 实际场景中可以缓存热点数据
    local hotspot_data
    hotspot_data=$("$hotspot_script" --format json --top 100 2>/dev/null || echo '{"hotspots":[]}')

    # 提取该文件的热点分数
    local max_score total_score file_score normalized

    if command -v jq &>/dev/null; then
        max_score=$(echo "$hotspot_data" | jq '[.hotspots[].score] | max // 1' 2>/dev/null || echo "1")
        file_score=$(echo "$hotspot_data" | jq --arg f "$file_path" '.hotspots[] | select(.file == $f) | .score // 0' 2>/dev/null || echo "0")

        if [[ "$max_score" != "0" && "$max_score" != "null" && -n "$file_score" && "$file_score" != "null" ]]; then
            normalized=$(awk -v fs="$file_score" -v ms="$max_score" 'BEGIN { printf "%.2f", fs / ms }')
            echo "$normalized"
        else
            echo "0.0"
        fi
    else
        echo "0.0"
    fi
}

# 获取文件复杂度
_get_file_complexity() {
    local file_path="$1"
    local full_path="${file_path}"

    # 如果路径不是绝对路径，假设是相对于当前目录
    if [[ ! -f "$full_path" ]]; then
        full_path="./$file_path"
    fi

    if [[ ! -f "$full_path" ]]; then
        echo "1"
        return
    fi

    # 简单复杂度估算：行数 / 10
    local lines
    lines=$(wc -l < "$full_path" 2>/dev/null | tr -d ' ')
    if [[ -n "$lines" && "$lines" -gt 0 ]]; then
        echo $(( (lines / 10) + 1 ))
    else
        echo "1"
    fi
}

# 根据热点分数获取颜色
_get_hotspot_color() {
    local score="$1"

    if awk -v s="$score" -v t="$HOTSPOT_HIGH_THRESHOLD" 'BEGIN { exit !(s > t) }'; then
        echo "$HOTSPOT_COLOR_HIGH"
    elif awk -v s="$score" -v t="$HOTSPOT_MED_THRESHOLD" 'BEGIN { exit !(s > t) }'; then
        echo "$HOTSPOT_COLOR_MED"
    else
        echo "$HOTSPOT_COLOR_LOW"
    fi
}

# ==================== Level 1: 系统上下文 ====================

_generate_level1_mermaid() {
    local include_hotspots="${1:-false}"
    local include_complexity="${2:-false}"

    echo "graph TD"
    echo "    subgraph System[\"Code Intelligence System\"]"
    echo "        CORE[Core Modules]"
    echo "        SCRIPTS[Scripts]"
    echo "        CONFIG[Configuration]"
    echo "    end"
    echo ""
    echo "    USER((User)) --> CORE"
    echo "    CORE --> SCRIPTS"
    echo "    SCRIPTS --> CONFIG"

    if [[ "$include_hotspots" == "true" ]]; then
        echo ""
        echo "    style SCRIPTS fill:$HOTSPOT_COLOR_MED"
    fi
}

_generate_level1_d3json() {
    local include_hotspots="${1:-false}"
    local include_complexity="${2:-false}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat << EOF
{
  "nodes": [
    {"id": "core", "group": "system", "label": "Core Modules", "hotspot": 0.5, "complexity": 10},
    {"id": "scripts", "group": "system", "label": "Scripts", "hotspot": 0.7, "complexity": 15},
    {"id": "config", "group": "system", "label": "Configuration", "hotspot": 0.2, "complexity": 5},
    {"id": "user", "group": "external", "label": "User", "hotspot": 0, "complexity": 0},
  ],
  "links": [
    {"source": "user", "target": "core", "type": "USES"},
    {"source": "core", "target": "scripts", "type": "IMPORTS"},
    {"source": "scripts", "target": "config", "type": "IMPORTS"}
  ],
  "metadata": {
    "generated_at": "$timestamp",
    "level": 1,
    "total_nodes": 5,
    "total_edges": 4
  }
}
EOF
}

# ==================== Level 2: 模块级 ====================

_generate_level2_mermaid() {
    local include_hotspots="${1:-false}"
    local include_complexity="${2:-false}"

    echo "graph TD"

    # 查询模块级节点
    local modules
    if _check_db; then
        modules=$(_run_sql "SELECT DISTINCT symbol, file_path FROM nodes WHERE kind = 'module' ORDER BY symbol;" 2>/dev/null || echo "")
    fi

    # 如果没有模块数据，使用默认目录结构
    if [[ -z "$modules" ]]; then
        # 检测实际目录结构
        local dirs=()
        [[ -d "src" ]] && dirs+=("src")
        [[ -d "scripts" ]] && dirs+=("scripts")
        [[ -d "hooks" ]] && dirs+=("hooks")
        [[ -d "config" ]] && dirs+=("config")
        [[ -d "tests" ]] && dirs+=("tests")

        if [[ ${#dirs[@]} -eq 0 ]]; then
            dirs=("src" "scripts" "config")
        fi

        for dir in "${dirs[@]}"; do
            local node_id
            node_id=$(_escape_mermaid_id "mod_$dir")
            local label="$dir"

            if [[ "$include_complexity" == "true" ]]; then
                local complexity
                complexity=$(_get_file_complexity "$dir")
                label="$dir [$complexity]"
            fi

            echo "    ${node_id}[\"$label\"]"
        done

        # 添加基本依赖关系
        echo ""
        if [[ -d "src" && -d "scripts" ]]; then
            echo "    mod_src --> mod_scripts"
        fi
        if [[ -d "tests" && -d "src" ]]; then
            echo "    mod_tests --> mod_src"
        fi
        if [[ -d "scripts" && -d "config" ]]; then
            echo "    mod_scripts --> mod_config"
        fi
    else
        # 使用数据库中的模块数据
        local seen_modules=""
        while IFS='|' read -r symbol file_path; do
            [[ -z "$symbol" ]] && continue

            local node_id
            node_id=$(_escape_mermaid_id "mod_$symbol")

            # 避免重复
            if [[ "$seen_modules" == *"$node_id"* ]]; then
                continue
            fi
            seen_modules="$seen_modules $node_id"

            local label="$symbol"

            if [[ "$include_complexity" == "true" ]]; then
                local complexity
                complexity=$(_get_file_complexity "$file_path")
                label="$symbol [$complexity]"
            fi

            echo "    ${node_id}[\"$label\"]"
        done <<< "$modules"

        # 查询模块间边
        local edges
        edges=$(_run_sql "SELECT DISTINCT
            n1.symbol as source,
            n2.symbol as target,
            e.edge_type
            FROM edges e
            JOIN nodes n1 ON e.source_id = n1.id
            JOIN nodes n2 ON e.target_id = n2.id
            WHERE n1.kind = 'module' AND n2.kind = 'module';" 2>/dev/null || echo "")

        if [[ -n "$edges" ]]; then
            echo ""
            while IFS='|' read -r source target edge_type; do
                [[ -z "$source" || -z "$target" ]] && continue
                local src_id tgt_id
                src_id=$(_escape_mermaid_id "mod_$source")
                tgt_id=$(_escape_mermaid_id "mod_$target")
                echo "    $src_id --> $tgt_id"
            done <<< "$edges"
        fi
    fi

    # 热点着色
    if [[ "$include_hotspots" == "true" ]]; then
        echo ""
        echo "    %% Hotspot styling"
        # 为 scripts 添加热点样式作为示例
        if [[ -d "scripts" ]]; then
            echo "    style mod_scripts fill:$HOTSPOT_COLOR_MED"
        fi
    fi
}

_generate_level2_d3json() {
    local include_hotspots="${1:-false}"
    local include_complexity="${2:-false}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local nodes_json="[]"
    local links_json="[]"
    local total_nodes=0
    local total_edges=0

    # 查询模块级节点
    if _check_db; then
        local modules
        modules=$(_run_sql "SELECT DISTINCT symbol, file_path FROM nodes WHERE kind = 'module';" 2>/dev/null || echo "")

        if [[ -n "$modules" ]]; then
            local nodes_arr=()
            while IFS='|' read -r symbol file_path; do
                [[ -z "$symbol" ]] && continue

                local hotspot="0.0"
                local complexity="1"

                if [[ "$include_hotspots" == "true" ]]; then
                    hotspot=$(_get_hotspot_score "$file_path")
                fi

                if [[ "$include_complexity" == "true" ]]; then
                    complexity=$(_get_file_complexity "$file_path")
                fi

                nodes_arr+=("{\"id\": \"$symbol\", \"group\": \"module\", \"hotspot\": $hotspot, \"complexity\": $complexity}")
                ((total_nodes++))
            done <<< "$modules"

            # 构建 JSON 数组
            if [[ ${#nodes_arr[@]} -gt 0 ]]; then
                nodes_json=$(printf '%s\n' "${nodes_arr[@]}" | paste -sd ',' -)
                nodes_json="[$nodes_json]"
            fi
        fi

        # 查询边
        local edges
        edges=$(_run_sql "SELECT DISTINCT
            n1.symbol as source,
            n2.symbol as target,
            e.edge_type
            FROM edges e
            JOIN nodes n1 ON e.source_id = n1.id
            JOIN nodes n2 ON e.target_id = n2.id
            WHERE n1.kind = 'module' AND n2.kind = 'module';" 2>/dev/null || echo "")

        if [[ -n "$edges" ]]; then
            local links_arr=()
            while IFS='|' read -r source target edge_type; do
                [[ -z "$source" || -z "$target" ]] && continue
                links_arr+=("{\"source\": \"$source\", \"target\": \"$target\", \"type\": \"$edge_type\"}")
                ((total_edges++))
            done <<< "$edges"

            if [[ ${#links_arr[@]} -gt 0 ]]; then
                links_json=$(printf '%s\n' "${links_arr[@]}" | paste -sd ',' -)
                links_json="[$links_json]"
            fi
        fi
    fi

    # 如果没有数据库数据，使用目录结构
    if [[ "$nodes_json" == "[]" ]]; then
        local dirs=()
        [[ -d "src" ]] && dirs+=("src")
        [[ -d "scripts" ]] && dirs+=("scripts")
        [[ -d "hooks" ]] && dirs+=("hooks")
        [[ -d "config" ]] && dirs+=("config")
        [[ -d "tests" ]] && dirs+=("tests")

        if [[ ${#dirs[@]} -eq 0 ]]; then
            dirs=("src" "scripts" "config")
        fi

        local nodes_arr=()
        for dir in "${dirs[@]}"; do
            local hotspot="0.0"
            local complexity="1"

            if [[ "$include_hotspots" == "true" ]]; then
                hotspot=$(_get_hotspot_score "$dir")
            fi

            if [[ "$include_complexity" == "true" ]]; then
                complexity=$(_get_file_complexity "$dir")
            fi

            nodes_arr+=("{\"id\": \"$dir\", \"group\": \"module\", \"hotspot\": $hotspot, \"complexity\": $complexity}")
            ((total_nodes++))
        done

        nodes_json=$(printf '%s\n' "${nodes_arr[@]}" | paste -sd ',' -)
        nodes_json="[$nodes_json]"

        # 添加基本链接
        local links_arr=()
        if [[ -d "src" && -d "scripts" ]]; then
            links_arr+=("{\"source\": \"src\", \"target\": \"scripts\", \"type\": \"IMPORTS\"}")
            ((total_edges++))
        fi
        if [[ -d "tests" && -d "src" ]]; then
            links_arr+=("{\"source\": \"tests\", \"target\": \"src\", \"type\": \"IMPORTS\"}")
            ((total_edges++))
        fi
        if [[ ${#links_arr[@]} -gt 0 ]]; then
            links_json=$(printf '%s\n' "${links_arr[@]}" | paste -sd ',' -)
            links_json="[$links_json]"
        fi
    fi

    cat << EOF
{
  "nodes": $nodes_json,
  "links": $links_json,
  "metadata": {
    "generated_at": "$timestamp",
    "level": 2,
    "total_nodes": $total_nodes,
    "total_edges": $total_edges
  }
}
EOF
}

# ==================== Level 3: 文件级 ====================

_generate_level3_mermaid() {
    local module_path="${1:-.}"
    local include_hotspots="${2:-false}"
    local include_complexity="${3:-false}"

    echo "graph TD"

    # 规范化模块路径
    module_path="${module_path%/}"

    # 查询该模块下的文件
    local files
    if _check_db; then
        files=$(_run_sql "SELECT symbol, file_path FROM nodes WHERE kind = 'file' AND file_path LIKE '${module_path}%';" 2>/dev/null || echo "")
    fi

    # 如果没有数据库数据，使用文件系统
    if [[ -z "$files" ]]; then
        if [[ -d "$module_path" ]]; then
            files=$(find "$module_path" -maxdepth 2 -type f \( -name "*.sh" -o -name "*.ts" -o -name "*.js" -o -name "*.py" \) 2>/dev/null | head -20)

            if [[ -z "$files" ]]; then
                echo "    %% Empty module: $module_path"
                return
            fi

            local subgraph_name
            subgraph_name=$(_escape_mermaid_label "$module_path")
            echo "    subgraph $subgraph_name"

            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                local node_id label
                node_id=$(_escape_mermaid_id "$file")
                label=$(_escape_mermaid_label "$file")

                if [[ "$include_complexity" == "true" ]]; then
                    local complexity
                    complexity=$(_get_file_complexity "$file")
                    label="$label [$complexity]"
                fi

                echo "        ${node_id}[\"$label\"]"
            done <<< "$files"

            echo "    end"
        else
            echo "    %% Module not found: $module_path"
            return
        fi
    else
        local subgraph_name
        subgraph_name=$(_escape_mermaid_label "$module_path")
        echo "    subgraph $subgraph_name"

        while IFS='|' read -r symbol file_path; do
            [[ -z "$symbol" ]] && continue
            local node_id
            node_id=$(_escape_mermaid_id "$file_path")
            local label="$symbol"

            if [[ "$include_complexity" == "true" ]]; then
                local complexity
                complexity=$(_get_file_complexity "$file_path")
                label="$symbol [$complexity]"
            fi

            echo "        ${node_id}[\"$label\"]"
        done <<< "$files"

        echo "    end"

        # 查询文件间边
        local edges
        edges=$(_run_sql "SELECT DISTINCT
            e.source_id,
            e.target_id,
            e.edge_type
            FROM edges e
            JOIN nodes n1 ON e.source_id = n1.id
            JOIN nodes n2 ON e.target_id = n2.id
            WHERE n1.kind = 'file' AND n2.kind = 'file'
            AND n1.file_path LIKE '${module_path}%'
            AND n2.file_path LIKE '${module_path}%';" 2>/dev/null || echo "")

        if [[ -n "$edges" ]]; then
            echo ""
            while IFS='|' read -r source target edge_type; do
                [[ -z "$source" || -z "$target" ]] && continue
                local src_id tgt_id
                src_id=$(_escape_mermaid_id "$source")
                tgt_id=$(_escape_mermaid_id "$target")
                echo "    $src_id --> $tgt_id"
            done <<< "$edges"
        fi
    fi

    # 热点着色
    if [[ "$include_hotspots" == "true" ]]; then
        echo ""
        echo "    %% Hotspot styling"
        # 添加示例热点样式
        if _check_db; then
            while IFS='|' read -r symbol file_path; do
                [[ -z "$file_path" ]] && continue
                local hotspot
                hotspot=$(_get_hotspot_score "$file_path")
                local color
                color=$(_get_hotspot_color "$hotspot")
                local node_id
                node_id=$(_escape_mermaid_id "$file_path")
                if [[ "$color" != "$HOTSPOT_COLOR_LOW" ]]; then
                    echo "    style $node_id fill:$color"
                fi
            done <<< "$files"
        fi
    fi
}

_generate_level3_d3json() {
    local module_path="${1:-.}"
    local include_hotspots="${2:-false}"
    local include_complexity="${3:-false}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 规范化模块路径
    module_path="${module_path%/}"

    local nodes_json="[]"
    local links_json="[]"
    local total_nodes=0
    local total_edges=0

    # 查询文件级节点
    if _check_db; then
        local files
        files=$(_run_sql "SELECT symbol, file_path FROM nodes WHERE kind = 'file' AND file_path LIKE '${module_path}%';" 2>/dev/null || echo "")

        if [[ -n "$files" ]]; then
            local nodes_arr=()
            while IFS='|' read -r symbol file_path; do
                [[ -z "$symbol" ]] && continue

                local hotspot="0.0"
                local complexity="1"

                if [[ "$include_hotspots" == "true" ]]; then
                    hotspot=$(_get_hotspot_score "$file_path")
                fi

                if [[ "$include_complexity" == "true" ]]; then
                    complexity=$(_get_file_complexity "$file_path")
                fi

                nodes_arr+=("{\"id\": \"$file_path\", \"group\": \"$module_path\", \"hotspot\": $hotspot, \"complexity\": $complexity}")
                ((total_nodes++))
            done <<< "$files"

            if [[ ${#nodes_arr[@]} -gt 0 ]]; then
                nodes_json=$(printf '%s\n' "${nodes_arr[@]}" | paste -sd ',' -)
                nodes_json="[$nodes_json]"
            fi
        fi

        # 查询文件间边
        local edges
        edges=$(_run_sql "SELECT DISTINCT
            n1.file_path as source,
            n2.file_path as target,
            e.edge_type
            FROM edges e
            JOIN nodes n1 ON e.source_id = n1.id
            JOIN nodes n2 ON e.target_id = n2.id
            WHERE n1.kind = 'file' AND n2.kind = 'file'
            AND n1.file_path LIKE '${module_path}%'
            AND n2.file_path LIKE '${module_path}%';" 2>/dev/null || echo "")

        if [[ -n "$edges" ]]; then
            local links_arr=()
            while IFS='|' read -r source target edge_type; do
                [[ -z "$source" || -z "$target" ]] && continue
                links_arr+=("{\"source\": \"$source\", \"target\": \"$target\", \"type\": \"$edge_type\"}")
                ((total_edges++))
            done <<< "$edges"

            if [[ ${#links_arr[@]} -gt 0 ]]; then
                links_json=$(printf '%s\n' "${links_arr[@]}" | paste -sd ',' -)
                links_json="[$links_json]"
            fi
        fi
    fi

    # 如果没有数据库数据，使用文件系统
    if [[ "$nodes_json" == "[]" ]]; then
        if [[ -d "$module_path" ]]; then
            local file_list
            file_list=$(find "$module_path" -maxdepth 2 -type f \( -name "*.sh" -o -name "*.ts" -o -name "*.js" -o -name "*.py" \) 2>/dev/null | head -20)

            if [[ -n "$file_list" ]]; then
                local nodes_arr=()
                while IFS= read -r file; do
                    [[ -z "$file" ]] && continue

                    local hotspot="0.0"
                    local complexity="1"
                    local basename
                    basename=$(basename "$file")

                    if [[ "$include_hotspots" == "true" ]]; then
                        hotspot=$(_get_hotspot_score "$file")
                    fi

                    if [[ "$include_complexity" == "true" ]]; then
                        complexity=$(_get_file_complexity "$file")
                    fi

                    nodes_arr+=("{\"id\": \"$file\", \"group\": \"$module_path\", \"hotspot\": $hotspot, \"complexity\": $complexity}")
                    ((total_nodes++))
                done <<< "$file_list"

                if [[ ${#nodes_arr[@]} -gt 0 ]]; then
                    nodes_json=$(printf '%s\n' "${nodes_arr[@]}" | paste -sd ',' -)
                    nodes_json="[$nodes_json]"
                fi
            fi
        fi
    fi

    cat << EOF
{
  "nodes": $nodes_json,
  "links": $links_json,
  "metadata": {
    "generated_at": "$timestamp",
    "level": 3,
    "module": "$module_path",
    "total_nodes": $total_nodes,
    "total_edges": $total_edges
  }
}
EOF
}

# ==================== 命令: generate ====================

cmd_generate() {
    local level="$DEFAULT_LEVEL"
    local format="$DEFAULT_FORMAT"
    local include_hotspots="false"
    local include_complexity="false"
    local output_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --level)
                level="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --include-hotspots)
                include_hotspots="true"
                shift
                ;;
            --include-complexity)
                include_complexity="true"
                shift
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # 验证参数
    if [[ ! "$level" =~ ^[123]$ ]]; then
        log_warn "Invalid level: $level. Using default level 2."
        level=2
    fi

    if [[ "$format" != "mermaid" && "$format" != "d3json" ]]; then
        log_error "Invalid format: $format. Valid formats: mermaid, d3json"
        return $EXIT_ARGS_ERROR
    fi

    # 仅在 Mermaid 格式且非输出到文件时显示日志
    if [[ "$format" == "mermaid" && -z "$output_file" ]]; then
        log_info "Generating COD visualization (level=$level, format=$format)" >&2
    fi

    local result

    case "$level" in
        1)
            if [[ "$format" == "mermaid" ]]; then
                result=$(_generate_level1_mermaid "$include_hotspots" "$include_complexity")
            else
                result=$(_generate_level1_d3json "$include_hotspots" "$include_complexity")
            fi
            ;;
        2)
            if [[ "$format" == "mermaid" ]]; then
                result=$(_generate_level2_mermaid "$include_hotspots" "$include_complexity")
            else
                result=$(_generate_level2_d3json "$include_hotspots" "$include_complexity")
            fi
            ;;
        3)
            if [[ "$format" == "mermaid" ]]; then
                result=$(_generate_level3_mermaid "." "$include_hotspots" "$include_complexity")
            else
                result=$(_generate_level3_d3json "." "$include_hotspots" "$include_complexity")
            fi
            ;;
    esac

    # 输出结果
    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
        log_ok "Output written to $output_file"
    else
        echo "$result"
    fi
}

# ==================== 命令: module ====================

cmd_module() {
    local module_path=""
    local format="$DEFAULT_FORMAT"
    local include_hotspots="false"
    local include_complexity="false"
    local output_file=""

    # 第一个非选项参数是模块路径
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                format="$2"
                shift 2
                ;;
            --include-hotspots)
                include_hotspots="true"
                shift
                ;;
            --include-complexity)
                include_complexity="true"
                shift
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            -*)
                shift
                ;;
            *)
                if [[ -z "$module_path" ]]; then
                    module_path="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$module_path" ]]; then
        log_error "Module path required"
        return $EXIT_ARGS_ERROR
    fi

    # 验证格式
    if [[ "$format" != "mermaid" && "$format" != "d3json" ]]; then
        log_error "Invalid format: $format. Valid formats: mermaid, d3json"
        return $EXIT_ARGS_ERROR
    fi

    # 仅在 Mermaid 格式时显示日志（JSON 输出需要保持纯净）
    if [[ "$format" == "mermaid" ]]; then
        log_info "Generating module visualization for: $module_path" >&2
    fi

    local result

    if [[ "$format" == "mermaid" ]]; then
        result=$(_generate_level3_mermaid "$module_path" "$include_hotspots" "$include_complexity")
    else
        result=$(_generate_level3_d3json "$module_path" "$include_hotspots" "$include_complexity")
    fi

    # 输出结果
    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
        log_ok "Output written to $output_file"
    else
        echo "$result"
    fi
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
cod-visualizer.sh - COD 架构可视化生成器

用法:
    cod-visualizer.sh <command> [options]

命令:
    generate            生成代码库概览图
    module <path>       生成模块级可视化

generate 选项:
    --level <1|2|3>         可视化层级（默认: 2）
                            1: 系统上下文
                            2: 模块级
                            3: 文件级
    --format <format>       输出格式（默认: mermaid）
                            mermaid: Mermaid 流程图语法
                            d3json: D3.js 兼容 JSON
    --include-hotspots      包含热点着色
    --include-complexity    包含复杂度标注
    --output <file>         输出到文件

module 选项:
    --format <format>       输出格式（默认: mermaid）
    --include-hotspots      包含热点着色
    --include-complexity    包含复杂度标注
    --output <file>         输出到文件

热点着色规则:
    高热点 (>0.7):  #ff6b6b (红色)
    中热点 (>0.3):  #ffd93d (黄色)
    低热点 (<=0.3): 默认颜色

示例:
    # 生成模块级 Mermaid 图
    cod-visualizer.sh generate --level 2 --format mermaid

    # 生成带热点着色的 D3.js JSON
    cod-visualizer.sh generate --level 2 --format d3json --include-hotspots

    # 生成 scripts 模块的文件级视图
    cod-visualizer.sh module scripts/ --format d3json

    # 输出到文件
    cod-visualizer.sh generate --level 2 --format mermaid --output arch.mmd

环境变量:
    GRAPH_DB_PATH       图数据库路径（默认: .devbooks/graph.db）
EOF
}

# ==================== 主入口 ====================

main() {
    check_dependencies sqlite3 || exit $EXIT_DEPS_MISSING

    local command="${1:-help}"
    shift || true

    case "$command" in
        generate)
            cmd_generate "$@"
            ;;
        module)
            cmd_module "$@"
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
