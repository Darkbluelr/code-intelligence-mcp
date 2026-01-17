#!/bin/bash
# scip-to-graph.sh - SCIP 索引解析转换脚本
# 版本: 1.0
# 用途: 将 SCIP 索引解析为图数据并写入 SQLite
#
# 覆盖 AC-002: SCIP -> 图数据转换成功
# 契约测试: CT-SP-001, CT-SP-002
#
# 环境变量:
#   SCIP_INDEX_PATH - SCIP 索引路径，默认 index.scip
#   GRAPH_DB_PATH - 数据库路径，默认 .devbooks/graph.db
#   DEVBOOKS_DIR - 工作目录，默认 .devbooks

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀
LOG_PREFIX="scip-to-graph"

# ==================== 配置 ====================

: "${DEVBOOKS_DIR:=.devbooks}"
: "${SCIP_INDEX_PATH:=index.scip}"
: "${GRAPH_DB_PATH:=$DEVBOOKS_DIR/graph.db}"

# SCIP proto 文件路径
SCIP_PROTO_PATH="/tmp/scip.proto"
SCIP_PROTO_URL="https://raw.githubusercontent.com/sourcegraph/scip/main/scip.proto"

# symbol_roles 映射（使用函数代替关联数组，兼容 bash 3）
# 1 -> DEFINES (Definition)
# 2 -> IMPORTS (Import)
# 4 -> MODIFIES (WriteAccess)
# 8 -> CALLS (ReadAccess)

# ==================== 辅助函数 ====================

# 确保 SCIP proto 文件存在
ensure_scip_proto() {
    if [[ ! -f "$SCIP_PROTO_PATH" ]]; then
        log_info "Downloading SCIP proto definition..."
        if command -v curl &>/dev/null; then
            curl -s "$SCIP_PROTO_URL" -o "$SCIP_PROTO_PATH" 2>/dev/null || return 1
        elif command -v wget &>/dev/null; then
            wget -q "$SCIP_PROTO_URL" -O "$SCIP_PROTO_PATH" 2>/dev/null || return 1
        else
            return 1
        fi
    fi
    return 0
}

# 检查 SCIP 索引是否比数据库新
is_scip_fresh() {
    local scip_path="$1"
    local db_path="$2"

    if [[ ! -f "$db_path" ]]; then
        return 0  # 数据库不存在，需要解析
    fi

    if [[ ! -f "$scip_path" ]]; then
        return 1  # SCIP 不存在
    fi

    # 比较修改时间
    if [[ "$scip_path" -nt "$db_path" ]]; then
        return 0  # SCIP 比数据库新
    fi

    return 1  # 数据库是最新的
}

# 映射 symbol_roles 到边类型
map_role_to_edge_type() {
    local role="$1"

    # 检查各个位
    if (( role & 1 )); then
        echo "DEFINES"
    elif (( role & 2 )); then
        echo "IMPORTS"
    elif (( role & 4 )); then
        echo "MODIFIES"
    elif (( role & 8 )); then
        echo "CALLS"
    else
        echo "CALLS"  # 默认为 CALLS
    fi
}

# 从符号字符串提取类型
extract_symbol_kind() {
    local symbol="$1"

    # SCIP 符号格式: scheme package descriptor
    # 例如: scip-typescript npm @types/node 18.0.0 path/`join`().
    if [[ "$symbol" == *"\`"*"()"* ]]; then
        echo "function"
    elif [[ "$symbol" == *"#"* ]]; then
        echo "class"
    elif [[ "$symbol" == *"."* ]]; then
        echo "variable"
    else
        echo "symbol"
    fi
}

# 生成节点 ID
generate_node_id() {
    local symbol="$1"
    # 使用 MD5 哈希生成稳定 ID
    hash_string_md5 "$symbol"
}

# ==================== SCIP 解析 (Node.js) ====================

# 使用 Node.js 解析 SCIP protobuf
parse_scip_with_node() {
    local scip_path="$1"
    local output_file="$2"

    # 确保 proto 文件存在
    ensure_scip_proto || return 1

    # 获取项目根目录（用于找到 node_modules）
    local project_root
    project_root=$(cd "$SCRIPT_DIR/.." && pwd)

    # 创建临时 Node.js 脚本（使用 .cjs 扩展名强制 CommonJS）
    local node_script="$project_root/.devbooks/parse-scip-temp.cjs"
    mkdir -p "$(dirname "$node_script")"

    cat > "$node_script" << 'NODEJS_SCRIPT'
const protobuf = require('protobufjs');
const fs = require('fs');

async function main() {
    const scipPath = process.argv[2];
    const outputPath = process.argv[3];

    try {
        const root = await protobuf.load('/tmp/scip.proto');
        const Index = root.lookupType('scip.Index');

        const buffer = fs.readFileSync(scipPath);
        const index = Index.decode(buffer);

        const result = {
            nodes: [],
            edges: [],
            stats: {
                documents: 0,
                symbols: 0,
                occurrences: 0,
                defines: 0,
                imports: 0,
                calls: 0,
                modifies: 0
            }
        };

        if (index.documents) {
            result.stats.documents = index.documents.length;

            index.documents.forEach(doc => {
                const filePath = doc.relativePath || '';

                // 处理符号定义
                if (doc.symbols) {
                    doc.symbols.forEach(sym => {
                        result.stats.symbols++;

                        const nodeId = sym.symbol;
                        const kind = sym.symbol.includes('`') && sym.symbol.includes('()') ? 'function' :
                                    sym.symbol.includes('#') ? 'class' : 'variable';

                        result.nodes.push({
                            id: nodeId,
                            symbol: sym.symbol,
                            kind: kind,
                            file_path: filePath
                        });

                        // 处理关系
                        if (sym.relationships) {
                            sym.relationships.forEach(rel => {
                                let edgeType = 'CALLS';
                                if (rel.isDefinition) edgeType = 'DEFINES';
                                else if (rel.isImplementation) edgeType = 'DEFINES';
                                else if (rel.isTypeDefinition) edgeType = 'DEFINES';
                                else if (rel.isReference) edgeType = 'CALLS';

                                result.edges.push({
                                    source_id: nodeId,
                                    target_id: rel.symbol,
                                    edge_type: edgeType,
                                    file_path: filePath
                                });

                                if (edgeType === 'DEFINES') result.stats.defines++;
                                else if (edgeType === 'CALLS') result.stats.calls++;
                            });
                        }
                    });
                }

                // 处理出现位置
                if (doc.occurrences) {
                    doc.occurrences.forEach(occ => {
                        result.stats.occurrences++;

                        const role = occ.symbolRoles || 0;
                        let edgeType = 'CALLS';

                        if (role & 1) { edgeType = 'DEFINES'; result.stats.defines++; }
                        else if (role & 2) { edgeType = 'IMPORTS'; result.stats.imports++; }
                        else if (role & 4) { edgeType = 'MODIFIES'; result.stats.modifies++; }
                        else if (role & 8) { edgeType = 'CALLS'; result.stats.calls++; }
                        else { result.stats.calls++; }

                        // 创建文件节点到符号的边
                        const fileNodeId = 'file:' + filePath;
                        const line = occ.range && occ.range.length > 0 ? occ.range[0] : null;

                        // 确保文件节点存在
                        if (!result.nodes.find(n => n.id === fileNodeId)) {
                            result.nodes.push({
                                id: fileNodeId,
                                symbol: filePath,
                                kind: 'file',
                                file_path: filePath
                            });
                        }

                        result.edges.push({
                            source_id: fileNodeId,
                            target_id: occ.symbol,
                            edge_type: edgeType,
                            file_path: filePath,
                            line: line
                        });
                    });
                }
            });
        }

        fs.writeFileSync(outputPath, JSON.stringify(result, null, 2));
        console.log(JSON.stringify({
            success: true,
            symbols: result.stats.symbols,
            documents: result.stats.documents,
            occurrences: result.stats.occurrences,
            edges: result.edges.length
        }));

    } catch (err) {
        console.error(JSON.stringify({ success: false, error: err.message }));
        process.exit(1);
    }
}

main();
NODEJS_SCRIPT

    # 运行 Node.js 脚本（在项目目录中执行以找到 node_modules）
    local result
    if result=$(cd "$project_root" && node "$node_script" "$scip_path" "$output_file" 2>&1); then
        rm -f "$node_script"
        echo "$result"
        return 0
    else
        rm -f "$node_script"
        echo "$result"
        return 1
    fi
}

# ==================== 正则降级解析 ====================

# 使用 ripgrep 正则解析源代码（降级方案）
parse_with_regex() {
    local project_root="$1"
    local output_file="$2"

    local nodes=()
    local edges=()
    local symbols=0
    local defines=0
    local imports=0
    local calls=0

    # 查找所有 TypeScript/JavaScript 文件
    local files
    files=$(find "$project_root" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
        -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)

    for file in $files; do
        local rel_path="${file#$project_root/}"
        local file_node_id="file:$rel_path"

        # 添加文件节点
        nodes+=("{\"id\":\"$file_node_id\",\"symbol\":\"$rel_path\",\"kind\":\"file\",\"file_path\":\"$rel_path\"}")

        # 提取函数定义
        if command -v rg &>/dev/null; then
            while IFS=: read -r line_num match; do
                local func_name
                func_name=$(echo "$match" | sed -E 's/.*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                if [[ -n "$func_name" && "$func_name" != "$match" ]]; then
                    local node_id="func:$rel_path:$func_name"
                    nodes+=("{\"id\":\"$node_id\",\"symbol\":\"$func_name\",\"kind\":\"function\",\"file_path\":\"$rel_path\",\"line_start\":$line_num}")
                    edges+=("{\"source_id\":\"$file_node_id\",\"target_id\":\"$node_id\",\"edge_type\":\"DEFINES\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                    ((symbols++))
                    ((defines++))
                fi
            done < <(rg -n "function[[:space:]]+[a-zA-Z_]" "$file" 2>/dev/null || true)

            # 提取 import 语句
            while IFS=: read -r line_num match; do
                local import_from
                import_from=$(echo "$match" | sed -E "s/.*from[[:space:]]+['\"]([^'\"]+)['\"].*/\1/" | head -1)
                if [[ -n "$import_from" && "$import_from" != "$match" ]]; then
                    local target_id="module:$import_from"
                    edges+=("{\"source_id\":\"$file_node_id\",\"target_id\":\"$target_id\",\"edge_type\":\"IMPORTS\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                    ((imports++))
                fi
            done < <(rg -n "import.*from" "$file" 2>/dev/null || true)
        else
            # 使用 grep 作为后备
            while IFS=: read -r line_num match; do
                local func_name
                func_name=$(echo "$match" | sed -E 's/.*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                if [[ -n "$func_name" && "$func_name" != "$match" ]]; then
                    local node_id="func:$rel_path:$func_name"
                    nodes+=("{\"id\":\"$node_id\",\"symbol\":\"$func_name\",\"kind\":\"function\",\"file_path\":\"$rel_path\"}")
                    edges+=("{\"source_id\":\"$file_node_id\",\"target_id\":\"$node_id\",\"edge_type\":\"DEFINES\",\"file_path\":\"$rel_path\"}")
                    ((symbols++))
                    ((defines++))
                fi
            done < <(grep -n "function[[:space:]]*[a-zA-Z_]" "$file" 2>/dev/null || true)
        fi
    done

    # 生成 JSON 输出
    local nodes_json
    local edges_json

    if [[ ${#nodes[@]} -gt 0 ]]; then
        nodes_json=$(printf '%s\n' "${nodes[@]}" | paste -sd ',' -)
    else
        nodes_json=""
    fi

    if [[ ${#edges[@]} -gt 0 ]]; then
        edges_json=$(printf '%s\n' "${edges[@]}" | paste -sd ',' -)
    else
        edges_json=""
    fi

    cat > "$output_file" << EOF
{
  "nodes": [${nodes_json}],
  "edges": [${edges_json}],
  "stats": {
    "symbols": $symbols,
    "defines": $defines,
    "imports": $imports,
    "calls": $calls
  }
}
EOF

    echo "{\"success\":true,\"symbols\":$symbols,\"confidence\":\"low\",\"source\":\"regex\"}"
}

# ==================== 命令: parse ====================

cmd_parse() {
    local incremental=false
    local force=false
    local format="text"
    local project_root="${PROJECT_ROOT:-$(pwd)}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --incremental) incremental=true; shift ;;
            --force) force=true; shift ;;
            --format) format="$2"; shift 2 ;;
            --project-root) project_root="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # 检查依赖
    check_dependencies sqlite3 jq node || exit $EXIT_DEPS_MISSING

    # 检查 SCIP 索引是否存在
    if [[ ! -f "$SCIP_INDEX_PATH" ]]; then
        log_error "SCIP index not found: $SCIP_INDEX_PATH"
        log_info "Generate with: npx scip-typescript index"
        return $EXIT_ARGS_ERROR
    fi

    # 确保数据库目录存在
    mkdir -p "$(dirname "$GRAPH_DB_PATH")"

    # 初始化数据库
    "$SCRIPT_DIR/graph-store.sh" init >/dev/null 2>&1

    # 增量更新检查
    if [[ "$incremental" == "true" && "$force" != "true" ]]; then
        if ! is_scip_fresh "$SCIP_INDEX_PATH" "$GRAPH_DB_PATH"; then
            log_info "Database is up-to-date, skipping parse"
            if [[ "$format" == "json" ]]; then
                echo '{"status":"up-to-date","symbols":0,"confidence":"high","source":"scip"}'
            fi
            return 0
        fi
        log_info "Incremental update: SCIP index is newer than database"
    fi

    # 强制重建
    if [[ "$force" == "true" ]]; then
        log_info "Force rebuild: clearing existing data"
        sqlite3 "$GRAPH_DB_PATH" "DELETE FROM edges; DELETE FROM nodes;" 2>/dev/null || true
    fi

    # 创建临时文件存储解析结果
    local temp_json
    temp_json=$(mktemp)

    # 尝试使用 Node.js 解析 SCIP
    local parse_result
    local parse_success=false
    local confidence="high"
    local source="scip"

    if parse_result=$(parse_scip_with_node "$SCIP_INDEX_PATH" "$temp_json" 2>&1); then
        if echo "$parse_result" | jq -e '.success == true' >/dev/null 2>&1; then
            parse_success=true
        fi
    fi

    # 如果 SCIP 解析失败，降级到正则
    if [[ "$parse_success" != "true" ]]; then
        log_warn "SCIP parsing failed, falling back to regex analysis"
        log_warn "confidence: low"
        if parse_result=$(parse_with_regex "$project_root" "$temp_json"); then
            parse_success=true
            confidence="low"
            source="regex"
        fi
    fi

    if [[ "$parse_success" != "true" ]]; then
        log_error "Failed to parse SCIP index"
        rm -f "$temp_json"
        return $EXIT_RUNTIME_ERROR
    fi

    # 导入数据到图数据库
    local import_result
    import_result=$("$SCRIPT_DIR/graph-store.sh" batch-import --file "$temp_json" 2>&1)

    # 获取统计信息
    local node_count edge_count
    node_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
    edge_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges;" 2>/dev/null || echo "0")

    # 清理临时文件
    rm -f "$temp_json"

    # 输出结果
    if [[ "$format" == "json" ]]; then
        local symbols
        symbols=$(echo "$parse_result" | jq -r '.symbols // 0' 2>/dev/null || echo "0")
        echo "{\"symbols\":$symbols,\"nodes\":$node_count,\"edges\":$edge_count,\"confidence\":\"$confidence\",\"source\":\"$source\"}"
    else
        log_ok "Parsed SCIP index: $node_count nodes, $edge_count edges"
    fi

    return 0
}

# ==================== 命令: stats ====================

cmd_stats() {
    local scip_path="${SCIP_INDEX_PATH}"

    if [[ ! -f "$scip_path" ]]; then
        echo '{"error":"SCIP index not found"}'
        return $EXIT_ARGS_ERROR
    fi

    # 使用 Node.js 获取统计信息
    local temp_json
    temp_json=$(mktemp)

    if parse_scip_with_node "$scip_path" "$temp_json" >/dev/null 2>&1; then
        jq '.stats' "$temp_json" 2>/dev/null || echo '{"error":"Failed to get stats"}'
        rm -f "$temp_json"
    else
        rm -f "$temp_json"
        echo '{"error":"Failed to parse SCIP index"}'
        return $EXIT_RUNTIME_ERROR
    fi
}

# ==================== 命令: is-fresh ====================

cmd_is_fresh() {
    local scip_path="${SCIP_INDEX_PATH}"
    local db_path="${GRAPH_DB_PATH}"

    if is_scip_fresh "$scip_path" "$db_path"; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
scip-to-graph.sh - SCIP 索引解析转换

用法:
    scip-to-graph.sh <command> [options]

命令:
    parse               解析 SCIP 索引并写入图数据库
    stats               获取 SCIP 索引统计信息
    is-fresh            检查 SCIP 索引是否比数据库新

parse 选项:
    --incremental       增量更新（仅当 SCIP 比数据库新时解析）
    --force             强制完全重建
    --format <fmt>      输出格式: text, json
    --project-root <p>  项目根目录（用于正则降级）

环境变量:
    SCIP_INDEX_PATH     SCIP 索引路径（默认: index.scip）
    GRAPH_DB_PATH       数据库路径（默认: .devbooks/graph.db）
    DEVBOOKS_DIR        工作目录（默认: .devbooks）

symbol_roles 映射:
    1 -> DEFINES (Definition)
    2 -> IMPORTS (Import)
    4 -> MODIFIES (WriteAccess)
    8 -> CALLS (ReadAccess)

示例:
    # 解析 SCIP 索引
    scip-to-graph.sh parse

    # 增量更新
    scip-to-graph.sh parse --incremental

    # 强制重建并输出 JSON
    scip-to-graph.sh parse --force --format json

    # 检查是否需要更新
    scip-to-graph.sh is-fresh
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
        stats)
            cmd_stats "$@"
            ;;
        is-fresh)
            cmd_is_fresh "$@"
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
