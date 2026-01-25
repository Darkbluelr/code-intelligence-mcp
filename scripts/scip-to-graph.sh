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
export LOG_PREFIX="scip-to-graph"

# ==================== 配置 ====================

: "${DEVBOOKS_DIR:=.devbooks}"
: "${SCIP_INDEX_PATH:=index.scip}"
: "${GRAPH_DB_PATH:=$DEVBOOKS_DIR/graph.db}"

# SCIP proto 配置
# Proto 发现策略（AC-003）：
#   1. $SCIP_PROTO_PATH 环境变量（CUSTOM）
#   2. vendored/scip.proto（VENDORED）
#   3. $CACHE_DIR/scip.proto（CACHED）
#   4. 下载（DOWNLOADED，仅当 allow_proto_download=true）
: "${SCIP_PROTO_CACHE_DIR:=/tmp}"
SCIP_PROTO_URL="https://raw.githubusercontent.com/sourcegraph/scip/main/scip.proto"

# Proto 发现结果（全局变量用于跟踪）
RESOLVED_PROTO_PATH=""
RESOLVED_PROTO_SOURCE=""
RESOLVED_PROTO_VERSION=""

# symbol_roles 映射（使用函数代替关联数组，兼容 bash 3）
# 1 -> DEFINES (Definition)
# 2 -> IMPORTS (Import)
# 4 -> MODIFIES (WriteAccess)
# 8 -> CALLS (ReadAccess)

# ==================== Proto 发现函数 (AC-003) ====================

# 从 proto 文件提取版本号
extract_proto_version_from_file() {
    local proto_file="$1"
    if [[ -f "$proto_file" ]]; then
        grep -E "^//[[:space:]]*Version:" "$proto_file" 2>/dev/null | head -1 | sed 's/.*Version:[[:space:]]*//' | tr -d '[:space:]' || echo "unknown"
    else
        echo "unknown"
    fi
}

# 从 features.yaml 读取离线 proto 配置
read_proto_config() {
    local config_key="$1"
    local default_value="$2"
    local config_file="${CONFIG_DIR:-$SCRIPT_DIR/../config}/features.yaml"

    if [[ ! -f "$config_file" ]]; then
        echo "$default_value"
        return
    fi

    # 解析 YAML（简单实现）
    local value
    value=$(awk -v key="$config_key" '
        BEGIN { in_indexer = 0 }
        /^[[:space:]]*indexer:/ { in_indexer = 1; next }
        /^[[:space:]]*[a-z]/ && !/^[[:space:]]*indexer:/ && in_indexer { in_indexer = 0 }
        in_indexer && $1 ~ key {
            gsub(/.*:/, "")
            gsub(/[[:space:]]/, "")
            gsub(/#.*/, "")
            print
            exit
        }
    ' "$config_file" 2>/dev/null)

    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default_value"
    fi
}

# 确保 SCIP proto 文件存在（离线优先策略）
# AC-003: Proto 发现策略实现
# 返回: 0=成功, 1=失败
# 副作用: 设置 RESOLVED_PROTO_PATH, RESOLVED_PROTO_SOURCE, RESOLVED_PROTO_VERSION
ensure_scip_proto() {
    local project_root
    project_root=$(cd "$SCRIPT_DIR/.." && pwd)

    # 读取配置
    local offline_proto allow_download
    offline_proto=$(read_proto_config "offline_proto" "true")
    allow_download=$(read_proto_config "allow_proto_download" "false")

    # 优先级 1: 环境变量 SCIP_PROTO_PATH（CUSTOM）
    if [[ -n "${SCIP_PROTO_PATH:-}" && -f "${SCIP_PROTO_PATH}" ]]; then
        RESOLVED_PROTO_PATH="$SCIP_PROTO_PATH"
        RESOLVED_PROTO_SOURCE="CUSTOM"
        RESOLVED_PROTO_VERSION=$(extract_proto_version_from_file "$RESOLVED_PROTO_PATH")
        log_info "Using custom proto: $RESOLVED_PROTO_PATH"
        return 0
    fi

    # 优先级 2: vendored/scip.proto（VENDORED）
    # 注意：如果 VENDORED_PROTO_PATH 被显式设置为空字符串，则跳过 vendored 路径
    if [[ -z "${VENDORED_PROTO_PATH+x}" ]]; then
        # VENDORED_PROTO_PATH 未设置，使用默认路径
        local vendored_path="$project_root/vendored/scip.proto"
        if [[ -f "$vendored_path" ]]; then
            RESOLVED_PROTO_PATH="$vendored_path"
            RESOLVED_PROTO_SOURCE="VENDORED"
            RESOLVED_PROTO_VERSION=$(extract_proto_version_from_file "$RESOLVED_PROTO_PATH")
            log_info "Using vendored proto: $RESOLVED_PROTO_PATH (v$RESOLVED_PROTO_VERSION)"
            return 0
        fi
    elif [[ -n "$VENDORED_PROTO_PATH" && -f "$VENDORED_PROTO_PATH" ]]; then
        # VENDORED_PROTO_PATH 被设置为非空值
        RESOLVED_PROTO_PATH="$VENDORED_PROTO_PATH"
        RESOLVED_PROTO_SOURCE="VENDORED"
        RESOLVED_PROTO_VERSION=$(extract_proto_version_from_file "$RESOLVED_PROTO_PATH")
        log_info "Using vendored proto: $RESOLVED_PROTO_PATH (v$RESOLVED_PROTO_VERSION)"
        return 0
    fi
    # 如果 VENDORED_PROTO_PATH="" (显式设置为空)，则跳过 vendored 路径

    # 优先级 3: 缓存目录（CACHED）
    local cached_path="$SCIP_PROTO_CACHE_DIR/scip.proto"
    if [[ -f "$cached_path" ]]; then
        RESOLVED_PROTO_PATH="$cached_path"
        RESOLVED_PROTO_SOURCE="CACHED"
        RESOLVED_PROTO_VERSION=$(extract_proto_version_from_file "$RESOLVED_PROTO_PATH")
        log_info "Using cached proto: $RESOLVED_PROTO_PATH"
        return 0
    fi

    # 优先级 4: 下载（DOWNLOADED，仅当 allow_proto_download=true）
    if [[ "$allow_download" == "true" ]]; then
        log_info "Downloading SCIP proto definition..."
        if command -v curl &>/dev/null; then
            if curl -s --connect-timeout 10 "$SCIP_PROTO_URL" -o "$cached_path" 2>/dev/null; then
                RESOLVED_PROTO_PATH="$cached_path"
                RESOLVED_PROTO_SOURCE="DOWNLOADED"
                RESOLVED_PROTO_VERSION="latest"
                log_ok "Downloaded proto to: $cached_path"
                return 0
            fi
        elif command -v wget &>/dev/null; then
            if wget -q --timeout=10 "$SCIP_PROTO_URL" -O "$cached_path" 2>/dev/null; then
                RESOLVED_PROTO_PATH="$cached_path"
                RESOLVED_PROTO_SOURCE="DOWNLOADED"
                RESOLVED_PROTO_VERSION="latest"
                log_ok "Downloaded proto to: $cached_path"
                return 0
            fi
        fi
        log_error "Failed to download SCIP proto"
    fi

    # 所有路径都失败
    log_error "SCIP proto not found."
    log_error "Expected locations (in priority order):"
    log_error "  1. \$SCIP_PROTO_PATH environment variable"
    log_error "  2. vendored/scip.proto"
    log_error "  3. $SCIP_PROTO_CACHE_DIR/scip.proto"
    log_info ""
    log_info "Suggestion: Run 'scripts/vendor-proto.sh --upgrade' to download and vendor the proto file."

    RESOLVED_PROTO_PATH=""
    RESOLVED_PROTO_SOURCE="NOT_FOUND"
    RESOLVED_PROTO_VERSION=""
    return 1
}

# ==================== 辅助函数 ====================

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

    # 确保 proto 文件存在（设置 RESOLVED_PROTO_PATH）
    ensure_scip_proto || return 1

    # 获取项目根目录（用于找到 node_modules）
    local project_root
    project_root=$(cd "$SCRIPT_DIR/.." && pwd)

    # 创建临时 Node.js 脚本（使用 .cjs 扩展名强制 CommonJS）
    local node_script="$project_root/.devbooks/parse-scip-temp.cjs"
    mkdir -p "$(dirname "$node_script")"

    # 注入 proto 路径到脚本
    local proto_path_for_node="$RESOLVED_PROTO_PATH"

    cat > "$node_script" << NODEJS_SCRIPT
const protobuf = require('protobufjs');
const fs = require('fs');

async function main() {
    const scipPath = process.argv[2];
    const outputPath = process.argv[3];
    // Proto 路径从 bash 注入（支持离线模式）
    const protoPath = '${proto_path_for_node}';

    try {
        const root = await protobuf.load(protoPath);
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

                                // MP1.1: IMPLEMENTS 边类型 (AC-U01)
                                if (rel.isImplementation) {
                                    edgeType = 'IMPLEMENTS';
                                }
                                // MP1.2: EXTENDS 边类型 (AC-U02)
                                else if (rel.isTypeDefinition && sym.symbol.includes('#')) {
                                    // 类继承关系
                                    edgeType = 'EXTENDS';
                                }
                                // 原有逻辑
                                else if (rel.isDefinition) {
                                    edgeType = 'DEFINES';
                                }
                                else if (rel.isReference) {
                                    edgeType = 'CALLS';
                                }

                                result.edges.push({
                                    source_id: nodeId,
                                    target_id: rel.symbol,
                                    edge_type: edgeType,
                                    file_path: filePath
                                });

                                if (edgeType === 'DEFINES') result.stats.defines++;
                                else if (edgeType === 'CALLS') result.stats.calls++;
                                else if (edgeType === 'IMPLEMENTS') {
                                    result.stats.implements = (result.stats.implements || 0) + 1;
                                }
                                else if (edgeType === 'EXTENDS') {
                                    result.stats.extends = (result.stats.extends || 0) + 1;
                                }
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

                        // MP1.3: RETURNS_TYPE 边类型 (AC-U09)
                        // 检测函数返回类型：通过符号名称模式识别
                        if (occ.symbol && occ.symbol.includes('()') && doc.text) {
                            const lines = doc.text.split('\n');
                            const occLine = occ.range && occ.range.length > 0 ? occ.range[0] : 0;
                            if (occLine < lines.length) {
                                const lineText = lines[occLine] || '';
                                // 检测显式返回类型声明 (TypeScript/Java 等)
                                if (lineText.match(/:\s*\w+/) || lineText.match(/\)\s*:\s*\w+/)) {
                                    edgeType = 'RETURNS_TYPE';
                                    result.stats.returns_type = (result.stats.returns_type || 0) + 1;
                                }
                            }
                        }

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
# MP1.4: 支持 IMPLEMENTS/EXTENDS/RETURNS_TYPE (AC-U10)
parse_with_regex() {
    local project_root="$1"
    local output_file="$2"

    local nodes=()
    local edges=()
    local symbols=0
    local defines=0
    local imports=0
    local calls=0
    local implements=0
    local extends=0
    local returns_type=0

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

                    # MP1.4: 检测函数返回类型 (RETURNS_TYPE)
                    if echo "$match" | grep -qE '\):\s*[a-zA-Z_]'; then
                        local return_type
                        return_type=$(echo "$match" | grep -oE '\):\s*[a-zA-Z_][a-zA-Z0-9_<>]*' | sed 's/)://; s/^[[:space:]]*//' | head -1)
                        if [[ -n "$return_type" && "$return_type" != "function" ]]; then
                            local type_id="type:$return_type"
                            edges+=("{\"source_id\":\"$node_id\",\"target_id\":\"$type_id\",\"edge_type\":\"RETURNS_TYPE\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                            ((returns_type++))
                        fi
                    fi
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

            # MP1.4: 提取 IMPLEMENTS 关系
            while IFS=: read -r line_num match; do
                local class_name interface_name
                class_name=$(echo "$match" | sed -E 's/.*class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                interface_name=$(echo "$match" | sed -E 's/.*implements[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                if [[ -n "$class_name" && -n "$interface_name" && "$class_name" != "$match" && "$interface_name" != "$match" ]]; then
                    local class_id="class:$rel_path:$class_name"
                    local interface_id="interface:$interface_name"
                    edges+=("{\"source_id\":\"$class_id\",\"target_id\":\"$interface_id\",\"edge_type\":\"IMPLEMENTS\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                    ((implements++))
                fi
            done < <(rg -n "class[[:space:]]+[a-zA-Z_].*implements" "$file" 2>/dev/null || true)

            # MP1.4: 提取 EXTENDS 关系
            while IFS=: read -r line_num match; do
                local class_name parent_name
                class_name=$(echo "$match" | sed -E 's/.*class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                parent_name=$(echo "$match" | sed -E 's/.*extends[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                if [[ -n "$class_name" && -n "$parent_name" && "$class_name" != "$match" && "$parent_name" != "$match" ]]; then
                    local class_id="class:$rel_path:$class_name"
                    local parent_id="class:$parent_name"
                    edges+=("{\"source_id\":\"$class_id\",\"target_id\":\"$parent_id\",\"edge_type\":\"EXTENDS\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                    ((extends++))
                fi
            done < <(rg -n "class[[:space:]]+[a-zA-Z_].*extends" "$file" 2>/dev/null || true)
        else
            # 使用 grep 作为后备
            while IFS=: read -r line_num match; do
                local func_name
                func_name=$(echo "$match" | sed -E 's/.*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                if [[ -n "$func_name" && "$func_name" != "$match" ]]; then
                    local node_id="func:$rel_path:$func_name"
                    nodes+=("{\"id\":\"$node_id\",\"symbol\":\"$func_name\",\"kind\":\"function\",\"file_path\":\"$rel_path\",\"line_start\":$line_num}")
                    edges+=("{\"source_id\":\"$file_node_id\",\"target_id\":\"$node_id\",\"edge_type\":\"DEFINES\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                    ((symbols++))
                    ((defines++))

                    # MP1.4: 检测函数返回类型 (RETURNS_TYPE) - grep 后备分支
                    if echo "$match" | grep -qE '\):\s*[a-zA-Z_]'; then
                        local return_type
                        return_type=$(echo "$match" | grep -oE '\):\s*[a-zA-Z_][a-zA-Z0-9_<>]*' | sed 's/)://; s/^[[:space:]]*//' | head -1)
                        if [[ -n "$return_type" && "$return_type" != "function" ]]; then
                            local type_id="type:$return_type"
                            edges+=("{\"source_id\":\"$node_id\",\"target_id\":\"$type_id\",\"edge_type\":\"RETURNS_TYPE\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                            ((returns_type++))
                        fi
                    fi
                fi
            done < <(grep -n "function[[:space:]]*[a-zA-Z_]" "$file" 2>/dev/null || true)

            # 提取 import 语句 - grep 后备分支
            while IFS=: read -r line_num match; do
                local import_from
                import_from=$(echo "$match" | sed -E "s/.*from[[:space:]]+['\"]([^'\"]+)['\"].*/\1/" | head -1)
                if [[ -n "$import_from" && "$import_from" != "$match" ]]; then
                    local target_id="module:$import_from"
                    edges+=("{\"source_id\":\"$file_node_id\",\"target_id\":\"$target_id\",\"edge_type\":\"IMPORTS\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                    ((imports++))
                fi
            done < <(grep -n "import.*from" "$file" 2>/dev/null || true)

            # MP1.4: 提取 IMPLEMENTS 关系 - grep 后备分支
            while IFS=: read -r line_num match; do
                local class_name interface_name
                class_name=$(echo "$match" | sed -E 's/.*class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                interface_name=$(echo "$match" | sed -E 's/.*implements[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                if [[ -n "$class_name" && -n "$interface_name" && "$class_name" != "$match" && "$interface_name" != "$match" ]]; then
                    local class_id="class:$rel_path:$class_name"
                    local interface_id="interface:$interface_name"
                    edges+=("{\"source_id\":\"$class_id\",\"target_id\":\"$interface_id\",\"edge_type\":\"IMPLEMENTS\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                    ((implements++))
                fi
            done < <(grep -n "class[[:space:]]*[a-zA-Z_].*implements" "$file" 2>/dev/null || true)

            # MP1.4: 提取 EXTENDS 关系 - grep 后备分支
            while IFS=: read -r line_num match; do
                local class_name parent_name
                class_name=$(echo "$match" | sed -E 's/.*class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                parent_name=$(echo "$match" | sed -E 's/.*extends[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | head -1)
                if [[ -n "$class_name" && -n "$parent_name" && "$class_name" != "$match" && "$parent_name" != "$match" ]]; then
                    local class_id="class:$rel_path:$class_name"
                    local parent_id="class:$parent_name"
                    edges+=("{\"source_id\":\"$class_id\",\"target_id\":\"$parent_id\",\"edge_type\":\"EXTENDS\",\"file_path\":\"$rel_path\",\"line\":$line_num}")
                    ((extends++))
                fi
            done < <(grep -n "class[[:space:]]*[a-zA-Z_].*extends" "$file" 2>/dev/null || true)
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
    "calls": $calls,
    "implements": $implements,
    "extends": $extends,
    "returns_type": $returns_type
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

# ==================== 命令: check-proto (AC-003) ====================

cmd_check_proto() {
    local format="text"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # 调用 ensure_scip_proto 来发现 proto 文件
    if ensure_scip_proto; then
        if [[ "$format" == "json" ]]; then
            jq -n \
                --arg path "$RESOLVED_PROTO_PATH" \
                --arg source "$RESOLVED_PROTO_SOURCE" \
                --arg version "$RESOLVED_PROTO_VERSION" \
                '{
                    status: "found",
                    path: $path,
                    source: $source,
                    version: $version
                }'
        else
            log_ok "Proto 检查结果"
            echo ""
            echo "  状态: found"
            echo "  路径: $RESOLVED_PROTO_PATH"
            echo "  来源: $RESOLVED_PROTO_SOURCE"
            echo "  版本: $RESOLVED_PROTO_VERSION"
        fi
        return 0
    else
        if [[ "$format" == "json" ]]; then
            jq -n \
                --arg source "$RESOLVED_PROTO_SOURCE" \
                '{
                    status: "not_found",
                    source: $source,
                    path: null,
                    version: null
                }'
        else
            log_error "Proto 未找到"
        fi
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
    check-proto         检查 SCIP proto 文件发现状态 (AC-003)

parse 选项:
    --incremental       增量更新（仅当 SCIP 比数据库新时解析）
    --force             强制完全重建
    --format <fmt>      输出格式: text, json
    --project-root <p>  项目根目录（用于正则降级）

check-proto 选项:
    --format <fmt>      输出格式: text, json

环境变量:
    SCIP_INDEX_PATH     SCIP 索引路径（默认: index.scip）
    GRAPH_DB_PATH       数据库路径（默认: .devbooks/graph.db）
    DEVBOOKS_DIR        工作目录（默认: .devbooks）
    SCIP_PROTO_PATH     自定义 proto 路径（优先级最高）

Proto 发现策略（优先级从高到低）:
    1. $SCIP_PROTO_PATH 环境变量
    2. vendored/scip.proto
    3. $SCIP_PROTO_CACHE_DIR/scip.proto（默认 /tmp）
    4. 下载（仅当 allow_proto_download=true）

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

    # 检查 proto 发现状态
    scip-to-graph.sh check-proto --format json
EOF
}

# ==================== 主入口 ====================

main() {
    # 检查是否使用新的参数格式（--input, --output, --fallback-regex, --check-proto）
    if [[ "$1" == --* ]]; then
        # 新格式：直接解析参数
        local input_file=""
        local output_db=""
        local fallback_regex=false
        local check_proto_mode=false
        local format="text"

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --input)
                    input_file="$2"
                    shift 2
                    ;;
                --output)
                    output_db="$2"
                    shift 2
                    ;;
                --fallback-regex)
                    fallback_regex=true
                    shift
                    ;;
                --check-proto)
                    check_proto_mode=true
                    shift
                    ;;
                --format)
                    format="$2"
                    shift 2
                    ;;
                --help|-h)
                    show_help
                    exit 0
                    ;;
                *)
                    log_error "Unknown parameter: $1"
                    exit $EXIT_ARGS_ERROR
                    ;;
            esac
        done

        # 如果是 check-proto 模式，直接调用
        if [[ "$check_proto_mode" == true ]]; then
            cmd_check_proto --format "$format"
            return $?
        fi

        # 验证必需参数
        if [[ -z "$input_file" || -z "$output_db" ]]; then
            log_error "Missing required parameters: --input and --output"
            exit $EXIT_ARGS_ERROR
        fi

        # 设置环境变量
        export GRAPH_DB_PATH="$output_db"

        # 初始化数据库
        bash "$SCRIPT_DIR/graph-store.sh" init >/dev/null 2>&1 || true

        # 确定项目根目录（输入文件的目录）
        local project_root
        project_root=$(dirname "$input_file")

        # 创建临时 JSON 文件
        local temp_json
        temp_json=$(mktemp)

        # 使用正则降级模式解析
        if parse_with_regex "$project_root" "$temp_json"; then
            # 导入到数据库
            bash "$SCRIPT_DIR/graph-store.sh" batch-import --file "$temp_json" >/dev/null 2>&1
            rm -f "$temp_json"
            return 0
        else
            rm -f "$temp_json"
            return $EXIT_RUNTIME_ERROR
        fi
    fi

    # 旧格式：子命令模式
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
        check-proto)
            cmd_check_proto "$@"
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
