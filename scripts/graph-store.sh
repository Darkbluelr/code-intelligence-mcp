#!/bin/bash
# graph-store.sh - SQLite 图存储管理脚本
# 版本: 1.0
# 用途: 提供代码图数据的 CRUD 操作
#
# 覆盖 AC-001: SQLite 图存储支持 4 种核心边类型 CRUD
# 边类型: DEFINES, IMPORTS, CALLS, MODIFIES
#
# 环境变量:
#   GRAPH_DB_PATH - 数据库路径，默认 .devbooks/graph.db
#   GRAPH_WAL_MODE - 是否启用 WAL 模式，默认 true
#   DEVBOOKS_DIR - 工作目录，默认 .devbooks

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀
export LOG_PREFIX="graph-store"

# ==================== 配置 ====================

# 默认数据库路径
: "${DEVBOOKS_DIR:=.devbooks}"
: "${GRAPH_DB_PATH:=$DEVBOOKS_DIR/graph.db}"
: "${GRAPH_WAL_MODE:=true}"

# MP4: Schema 版本常量 (AC-004)
CURRENT_SCHEMA_VERSION=4

# 有效边类型（扩展 AC-G01: 支持 IMPLEMENTS/EXTENDS/RETURNS_TYPE/ADR_RELATED）
VALID_EDGE_TYPES=("DEFINES" "IMPORTS" "CALLS" "MODIFIES" "REFERENCES" "IMPLEMENTS" "EXTENDS" "RETURNS_TYPE" "ADR_RELATED")

# MP4: 闭包表最大深度
CLOSURE_MAX_DEPTH=5

# ==================== 辅助函数 ====================

# 检查边类型是否有效
is_valid_edge_type() {
    local edge_type="$1"
    for valid_type in "${VALID_EDGE_TYPES[@]}"; do
        if [[ "$edge_type" == "$valid_type" ]]; then
            return 0
        fi
    done
    return 1
}

# [C-002] SQL 注入防护：验证输入安全性
validate_sql_input() {
    local input="$1"
    local field_name="${2:-input}"
    local max_length="${3:-1000}"

    # 检查空值
    if [[ -z "$input" ]]; then
        return 0
    fi

    # [M-010 fix] 检查输入长度
    if [[ ${#input} -gt $max_length ]]; then
        log_error "Input too long in $field_name: ${#input} > $max_length"
        return 1
    fi

    # [M-010 fix] 检查危险字符模式（修正正则转义）
    if [[ "$input" =~ [\;\|\&\$\`] ]]; then
        log_error "Invalid characters in $field_name: contains shell metacharacters"
        return 1
    fi

    # [M-010 fix] 检查 Unicode 控制字符（兼容 macOS grep）
    if printf '%s' "$input" | LC_ALL=C tr -d '[:print:][:space:]' | grep -q .; then
        log_error "Invalid characters in $field_name: contains control characters"
        return 1
    fi

    # 检查 SQL 注入模式
    if echo "$input" | grep -qiE "(DROP|DELETE|TRUNCATE|ALTER|EXEC|UNION|INSERT|UPDATE).*TABLE"; then
        log_error "Potential SQL injection detected in $field_name"
        return 1
    fi

    return 0
}

# 安全转义 SQL 字符串
escape_sql_string() {
    local input="$1"
    echo "$input" | sed "s/'/''/g"
}

# 确保数据库目录存在
ensure_db_dir() {
    local db_dir
    db_dir=$(dirname "$GRAPH_DB_PATH")
    if [[ ! -d "$db_dir" ]]; then
        mkdir -p "$db_dir"
    fi
}

# 执行 SQL 查询
run_sql() {
    local sql="$1"
    sqlite3 "$GRAPH_DB_PATH" "$sql"
}

# 执行 SQL 查询并返回 JSON
run_sql_json() {
    local sql="$1"
    sqlite3 -json "$GRAPH_DB_PATH" "$sql"
}

# 生成唯一 ID
generate_id() {
    local prefix="${1:-}"
    local uuid
    uuid=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$-$RANDOM")
    if [[ -n "$prefix" ]]; then
        echo "${prefix}:${uuid}"
    else
        echo "$uuid"
    fi
}

# ==================== 数据库 Schema ====================

create_schema() {
    cat << 'EOF'
-- nodes 表
CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    symbol TEXT NOT NULL,
    kind TEXT NOT NULL,
    file_path TEXT NOT NULL,
    line_start INTEGER,
    line_end INTEGER,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_nodes_file ON nodes(file_path);
CREATE INDEX IF NOT EXISTS idx_nodes_symbol ON nodes(symbol);

-- edges 表（扩展 AC-G01: 支持 IMPLEMENTS/EXTENDS/RETURNS_TYPE/ADR_RELATED）
CREATE TABLE IF NOT EXISTS edges (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    edge_type TEXT NOT NULL CHECK(edge_type IN ('DEFINES', 'IMPORTS', 'CALLS', 'MODIFIES', 'REFERENCES', 'IMPLEMENTS', 'EXTENDS', 'RETURNS_TYPE', 'ADR_RELATED')),
    file_path TEXT,
    line INTEGER,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
);

CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);
CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);
CREATE INDEX IF NOT EXISTS idx_edges_type ON edges(edge_type);

-- MP4: transitive_closure 表（闭包表）
CREATE TABLE IF NOT EXISTS transitive_closure (
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    depth INTEGER NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    PRIMARY KEY (source_id, target_id),
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
);

CREATE INDEX IF NOT EXISTS idx_tc_source ON transitive_closure(source_id);
CREATE INDEX IF NOT EXISTS idx_tc_target ON transitive_closure(target_id);
CREATE INDEX IF NOT EXISTS idx_tc_depth ON transitive_closure(depth);

-- MP4: path_index 表（路径索引）
CREATE TABLE IF NOT EXISTS path_index (
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    path TEXT NOT NULL,
    edge_path TEXT,
    depth INTEGER NOT NULL,
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    PRIMARY KEY (source_id, target_id),
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
);

CREATE INDEX IF NOT EXISTS idx_path_source ON path_index(source_id);
CREATE INDEX IF NOT EXISTS idx_path_target ON path_index(target_id);
CREATE INDEX IF NOT EXISTS idx_path_depth ON path_index(depth);

-- MP7: user_signals 表（上下文信号）
CREATE TABLE IF NOT EXISTS user_signals (
    file_path TEXT NOT NULL,
    signal_type TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    weight REAL NOT NULL,
    PRIMARY KEY (file_path, signal_type, timestamp)
);

CREATE INDEX IF NOT EXISTS idx_user_signals_file ON user_signals(file_path);
CREATE INDEX IF NOT EXISTS idx_user_signals_time ON user_signals(timestamp);

-- virtual_edges 表（MP5: 联邦虚拟边）
-- Trace: AC-F05
CREATE TABLE IF NOT EXISTS virtual_edges (
    id TEXT PRIMARY KEY,
    source_repo TEXT NOT NULL,
    source_symbol TEXT NOT NULL,
    target_repo TEXT NOT NULL,
    target_symbol TEXT NOT NULL,
    edge_type TEXT NOT NULL CHECK(edge_type IN ('VIRTUAL_CALLS', 'VIRTUAL_IMPORTS')),
    contract_type TEXT NOT NULL CHECK(contract_type IN ('proto', 'openapi', 'graphql', 'typescript')),
    confidence REAL DEFAULT 1.0,
    confidence_level TEXT DEFAULT 'medium' CHECK(confidence_level IN ('low', 'medium', 'high')),
    exact_match REAL DEFAULT 0.0,
    signature_similarity REAL DEFAULT 0.5,
    contract_bonus REAL DEFAULT 0.0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_virtual_edges_source ON virtual_edges(source_repo, source_symbol);
CREATE INDEX IF NOT EXISTS idx_virtual_edges_target ON virtual_edges(target_repo, target_symbol);
CREATE INDEX IF NOT EXISTS idx_virtual_edges_type ON virtual_edges(edge_type);
CREATE INDEX IF NOT EXISTS idx_virtual_edges_contract ON virtual_edges(contract_type);
CREATE INDEX IF NOT EXISTS idx_virtual_edges_confidence ON virtual_edges(confidence);

-- 版本表
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- 元数据表（用于存储配置和版本戳）
CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- MP2: Schema v3 新增索引 (AC-U03)
CREATE INDEX IF NOT EXISTS idx_edges_implements ON edges(edge_type) WHERE edge_type = 'IMPLEMENTS';
CREATE INDEX IF NOT EXISTS idx_edges_extends ON edges(edge_type) WHERE edge_type = 'EXTENDS';
CREATE INDEX IF NOT EXISTS idx_edges_returns_type ON edges(edge_type) WHERE edge_type = 'RETURNS_TYPE';

INSERT OR IGNORE INTO schema_version (version) VALUES (4);
EOF
}

# ==================== 闭包表/路径索引 ====================

closure_tables_exist() {
    local db_path="${1:-$GRAPH_DB_PATH}"
    if [[ ! -f "$db_path" ]]; then
        return 1
    fi

    local has_tc has_pi
    has_tc=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='transitive_closure';" 2>/dev/null || echo "0")
    has_pi=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='path_index';" 2>/dev/null || echo "0")

    [[ "$has_tc" -gt 0 && "$has_pi" -gt 0 ]]
}

precompute_closure() {
    local max_depth="${1:-$CLOSURE_MAX_DEPTH}"

    closure_tables_exist "$GRAPH_DB_PATH" || return 0

    # M-014 fix: 添加进度反馈
    local node_count edge_count
    node_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
    edge_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges;" 2>/dev/null || echo "0")
    log_info "开始预计算闭包表 (nodes=$node_count, edges=$edge_count, max_depth=$max_depth)..."

    local sql="
BEGIN TRANSACTION;
DELETE FROM transitive_closure;
WITH RECURSIVE tc(source_id, target_id, depth) AS (
    SELECT source_id, target_id, 1 FROM edges
    UNION ALL
    SELECT tc.source_id, e.target_id, tc.depth + 1
    FROM tc
    JOIN edges e ON tc.target_id = e.source_id
    WHERE tc.depth < $max_depth
)
INSERT OR REPLACE INTO transitive_closure (source_id, target_id, depth)
SELECT source_id, target_id, MIN(depth) FROM tc GROUP BY source_id, target_id;

DELETE FROM path_index;
INSERT OR REPLACE INTO path_index (source_id, target_id, path, edge_path, depth)
SELECT
    e.source_id,
    e.target_id,
    json_array(e.source_id, e.target_id),
    json_array(json_object('from', e.source_id, 'to', e.target_id, 'type', e.edge_type)),
    1
FROM edges e;
COMMIT;
"

    if sqlite3 "$GRAPH_DB_PATH" "$sql" >/dev/null 2>&1; then
        local tc_count pi_count
        tc_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM transitive_closure;" 2>/dev/null || echo "0")
        pi_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM path_index;" 2>/dev/null || echo "0")
        log_info "闭包表预计算完成 (transitive_closure=$tc_count, path_index=$pi_count)"
    else
        log_warn "闭包表预计算失败，将在下次查询时重试"
    fi
}

precompute_closure_async() {
    local max_depth="${1:-$CLOSURE_MAX_DEPTH}"
    (precompute_closure "$max_depth" >/dev/null 2>&1) &
}

update_closure_for_edge() {
    local source_id="$1"
    local target_id="$2"
    local edge_type="$3"

    closure_tables_exist "$GRAPH_DB_PATH" || return 0

    local source_sql target_sql edge_sql
    source_sql="$(escape_sql_string "$source_id")"
    target_sql="$(escape_sql_string "$target_id")"
    edge_sql="$(escape_sql_string "$edge_type")"

    local sql="
INSERT OR REPLACE INTO transitive_closure (source_id, target_id, depth)
VALUES ('$source_sql', '$target_sql', 1);
INSERT OR REPLACE INTO path_index (source_id, target_id, path, edge_path, depth)
VALUES (
    '$source_sql',
    '$target_sql',
    json_array('$source_sql', '$target_sql'),
    json_array(json_object('from', '$source_sql', 'to', '$target_sql', 'type', '$edge_sql')),
    1
);
"

    sqlite3 "$GRAPH_DB_PATH" "$sql" >/dev/null 2>&1 || true
}

# ==================== 命令: init ====================

cmd_init() {
    check_dependencies sqlite3 || exit $EXIT_DEPS_MISSING

    local skip_precompute=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-precompute) skip_precompute=true; shift ;;
            *) shift ;;
        esac
    done

    ensure_db_dir

    if [[ -f "$GRAPH_DB_PATH" ]]; then
        # 检查数据库是否有效
        if sqlite3 "$GRAPH_DB_PATH" "SELECT 1 FROM schema_version LIMIT 1;" &>/dev/null; then
            log_info "Database already exists at $GRAPH_DB_PATH"
            echo '{"status":"exists","path":"'"$GRAPH_DB_PATH"'"}'
            return 0
        fi
    fi

    log_info "Initializing graph database at $GRAPH_DB_PATH"

    # 创建数据库和 schema
    create_schema | sqlite3 "$GRAPH_DB_PATH"

    # 启用 WAL 模式
    if [[ "$GRAPH_WAL_MODE" == "true" ]]; then
        sqlite3 "$GRAPH_DB_PATH" "PRAGMA journal_mode=WAL;"
    fi

    if [[ "$skip_precompute" != "true" ]]; then
        precompute_closure_async
    fi

    log_ok "Graph database initialized"
    echo '{"status":"created","path":"'"$GRAPH_DB_PATH"'"}'
}

# ==================== 命令: add-node ====================

cmd_add_node() {
    local id="" symbol="" kind="" file_path="" line_start="" line_end=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) id="$2"; shift 2 ;;
            --symbol) symbol="$2"; shift 2 ;;
            --kind) kind="$2"; shift 2 ;;
            --file) file_path="$2"; shift 2 ;;
            --line-start) line_start="$2"; shift 2 ;;
            --line-end) line_end="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # 验证必填字段
    if [[ -z "$id" || -z "$symbol" || -z "$kind" || -z "$file_path" ]]; then
        log_error "Missing required fields: --id, --symbol, --kind, --file"
        return $EXIT_ARGS_ERROR
    fi

    # [C-002] 输入验证
    validate_sql_input "$id" "id" || return $EXIT_ARGS_ERROR
    validate_sql_input "$symbol" "symbol" || return $EXIT_ARGS_ERROR
    validate_sql_input "$kind" "kind" || return $EXIT_ARGS_ERROR
    validate_sql_input "$file_path" "file_path" || return $EXIT_ARGS_ERROR

    # 处理可选字段
    local line_start_sql="NULL"
    local line_end_sql="NULL"
    [[ -n "$line_start" ]] && line_start_sql="$line_start"
    [[ -n "$line_end" ]] && line_end_sql="$line_end"

    # 插入节点（使用安全转义）
    local sql="INSERT OR REPLACE INTO nodes (id, symbol, kind, file_path, line_start, line_end) VALUES ('$(escape_sql_string "$id")', '$(escape_sql_string "$symbol")', '$(escape_sql_string "$kind")', '$(escape_sql_string "$file_path")', $line_start_sql, $line_end_sql);"

    if run_sql "$sql"; then
        echo '{"status":"ok","id":"'"$id"'"}'
    else
        log_error "Failed to add node"
        return $EXIT_RUNTIME_ERROR
    fi
}

# ==================== 命令: add-edge ====================

cmd_add_edge() {
    local source_id="" target_id="" edge_type="" file_path="" line=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source) source_id="$2"; shift 2 ;;
            --target) target_id="$2"; shift 2 ;;
            --type) edge_type="$2"; shift 2 ;;
            --file) file_path="$2"; shift 2 ;;
            --line) line="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # 验证必填字段
    if [[ -z "$source_id" || -z "$target_id" || -z "$edge_type" ]]; then
        log_error "Missing required fields: --source, --target, --type"
        return $EXIT_ARGS_ERROR
    fi

    # [C-002] 输入验证
    validate_sql_input "$source_id" "source_id" || return $EXIT_ARGS_ERROR
    validate_sql_input "$target_id" "target_id" || return $EXIT_ARGS_ERROR
    validate_sql_input "$file_path" "file_path" || return $EXIT_ARGS_ERROR

    # 验证边类型
    if ! is_valid_edge_type "$edge_type"; then
        log_error "Invalid edge type: $edge_type. Valid types: DEFINES, IMPORTS, CALLS, MODIFIES, REFERENCES, IMPLEMENTS, EXTENDS, RETURNS_TYPE, ADR_RELATED"
        return $EXIT_ARGS_ERROR
    fi

    # 生成确定性边 ID（基于 source_id, target_id, edge_type 的哈希，保证幂等性）
    local edge_id
    edge_id=$(hash_string_md5 "${source_id}:${target_id}:${edge_type}")

    # 处理可选字段
    local file_sql="NULL"
    local line_sql="NULL"
    [[ -n "$file_path" ]] && file_sql="'$(escape_sql_string "$file_path")'"
    [[ -n "$line" ]] && line_sql="$line"

    # 插入边（使用 INSERT OR REPLACE 保证幂等性，AC-006）
    local sql="INSERT OR REPLACE INTO edges (id, source_id, target_id, edge_type, file_path, line) VALUES ('$edge_id', '$(escape_sql_string "$source_id")', '$(escape_sql_string "$target_id")', '$edge_type', $file_sql, $line_sql);"

    if run_sql "$sql"; then
        update_closure_for_edge "$source_id" "$target_id" "$edge_type"
        echo '{"status":"ok","id":"'"$edge_id"'"}'
    else
        log_error "Failed to add edge"
        return $EXIT_RUNTIME_ERROR
    fi
}

# ==================== 命令: query-edges ====================

cmd_query_edges() {
    local from_node="" to_node="" edge_type="" direction="out"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) from_node="$2"; shift 2 ;;
            --to) to_node="$2"; shift 2 ;;
            --type) edge_type="$2"; shift 2 ;;
            --direction) direction="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local where_clauses=()

    if [[ -n "$from_node" ]]; then
        where_clauses+=("source_id = '$(echo "$from_node" | sed "s/'/''/g")'")
    fi

    if [[ -n "$to_node" ]]; then
        where_clauses+=("target_id = '$(echo "$to_node" | sed "s/'/''/g")'")
    fi

    if [[ -n "$edge_type" ]]; then
        where_clauses+=("edge_type = '$edge_type'")
    fi

    local where_sql=""
    if [[ ${#where_clauses[@]} -gt 0 ]]; then
        # 使用 printf 正确连接数组元素，避免 IFS 只使用第一个字符的问题
        local joined
        joined=$(printf '%s AND ' "${where_clauses[@]}")
        # 移除末尾多余的 " AND "
        joined="${joined% AND }"
        where_sql="WHERE $joined"
    fi

    local sql="SELECT json_group_array(json_object('id', id, 'source_id', source_id, 'target_id', target_id, 'edge_type', edge_type, 'file_path', file_path, 'line', line)) FROM edges $where_sql;"

    run_sql "$sql"
}

# ==================== 命令: find-orphans ====================

cmd_find_orphans() {
    local exclude_pattern=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --exclude) exclude_pattern="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # 查找没有入边的节点（孤儿）
    local sql
    if [[ -n "$exclude_pattern" ]]; then
        sql="SELECT json_group_array(json_object('id', n.id, 'symbol', n.symbol, 'kind', n.kind, 'file_path', n.file_path))
             FROM nodes n
             LEFT JOIN edges e ON n.id = e.target_id
             WHERE e.id IS NULL
             AND n.file_path NOT GLOB '*$exclude_pattern*';"
    else
        sql="SELECT json_group_array(json_object('id', n.id, 'symbol', n.symbol, 'kind', n.kind, 'file_path', n.file_path))
             FROM nodes n
             LEFT JOIN edges e ON n.id = e.target_id
             WHERE e.id IS NULL;"
    fi

    run_sql "$sql"
}

# ==================== 命令: batch-import ====================

cmd_batch_import() {
    local input_file=""
    local skip_precompute=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) input_file="$2"; shift 2 ;;
            --skip-precompute) skip_precompute=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$input_file" || ! -f "$input_file" ]]; then
        log_error "Input file not found: $input_file"
        return $EXIT_ARGS_ERROR
    fi

    check_dependencies jq || exit $EXIT_DEPS_MISSING

    # 验证 JSON 格式
    if ! jq empty "$input_file" 2>/dev/null; then
        log_error "Invalid JSON in input file"
        return $EXIT_ARGS_ERROR
    fi

    # 开始事务
    local sql="BEGIN TRANSACTION;"

    # 处理节点（使用单次 jq 提升大批量性能）
    if jq -e '.nodes | length > 0' "$input_file" >/dev/null 2>&1; then
        while IFS=$'\t' read -r id symbol kind file_path line_start line_end; do
            # 验证必填字段
            if [[ -z "$id" || "$id" == "null" || "$id" == "NULL" \
                || -z "$symbol" || "$symbol" == "null" || "$symbol" == "NULL" \
                || -z "$kind" || "$kind" == "null" || "$kind" == "NULL" \
                || -z "$file_path" || "$file_path" == "null" || "$file_path" == "NULL" ]]; then
                log_error "Node missing required fields: id, symbol, kind, file_path"
                return $EXIT_ARGS_ERROR
            fi

            # 处理 NULL 值
            [[ "$line_start" == "null" || "$line_start" == "NULL" || -z "$line_start" ]] && line_start="NULL"
            [[ "$line_end" == "null" || "$line_end" == "NULL" || -z "$line_end" ]] && line_end="NULL"

            sql+="INSERT OR REPLACE INTO nodes (id, symbol, kind, file_path, line_start, line_end) VALUES ('$(echo "$id" | sed "s/'/''/g")', '$(echo "$symbol" | sed "s/'/''/g")', '$(echo "$kind" | sed "s/'/''/g")', '$(echo "$file_path" | sed "s/'/''/g")', $line_start, $line_end);"
        done < <(jq -r '.nodes[] | [.id, .symbol, .kind, .file_path, (.line_start // "NULL"), (.line_end // "NULL")] | @tsv' "$input_file")
    fi

    # 处理边（使用单次 jq 提升大批量性能）
    if jq -e '.edges | length > 0' "$input_file" >/dev/null 2>&1; then
        while IFS=$'\t' read -r source_id target_id edge_type file_path line; do
            # 验证边类型
            if ! is_valid_edge_type "$edge_type"; then
                log_error "Invalid edge type: $edge_type"
                return $EXIT_ARGS_ERROR
            fi

            # 生成确定性边 ID（基于 source_id, target_id, edge_type 的哈希，保证幂等性，AC-006）
            local edge_id
            edge_id=$(hash_string_md5 "${source_id}:${target_id}:${edge_type}")

            # 处理 NULL 值
            [[ "$file_path" == "null" || "$file_path" == "NULL" || -z "$file_path" ]] && file_path="NULL" || file_path="'$(echo "$file_path" | sed "s/'/''/g")'"
            [[ "$line" == "null" || "$line" == "NULL" || -z "$line" ]] && line="NULL"

            # 使用 INSERT OR REPLACE 保证幂等性（AC-006）
            sql+="INSERT OR REPLACE INTO edges (id, source_id, target_id, edge_type, file_path, line) VALUES ('$edge_id', '$(echo "$source_id" | sed "s/'/''/g")', '$(echo "$target_id" | sed "s/'/''/g")', '$edge_type', $file_path, $line);"
        done < <(jq -r '.edges[] | [.source_id, .target_id, .edge_type, (.file_path // "NULL"), (.line // "NULL")] | @tsv' "$input_file")
    fi

    sql+="COMMIT;"

    if echo "$sql" | sqlite3 "$GRAPH_DB_PATH"; then
        if [[ "$skip_precompute" != "true" ]]; then
            precompute_closure_async
        fi
        local node_count edge_count
        node_count=$(jq '.nodes | length' "$input_file")
        edge_count=$(jq '.edges // [] | length' "$input_file")
        echo "{\"status\":\"ok\",\"nodes_imported\":$node_count,\"edges_imported\":$edge_count}"
    else
        log_error "Batch import failed, rolling back"
        run_sql "ROLLBACK;" 2>/dev/null || true
        # [M-009 fix] 清理可能已插入的部分数据和闭包表
        run_sql "VACUUM;" 2>/dev/null || true
        return $EXIT_RUNTIME_ERROR
    fi
}

# ==================== 命令: stats ====================

cmd_stats() {
    # SQLite: 使用单引号作为字符串字面量，双引号用于标识符
    local sql="SELECT json_object(
        'nodes', (SELECT COUNT(*) FROM nodes),
        'edges', (SELECT COUNT(*) FROM edges),
        'edges_by_type', json_object(
            'DEFINES', (SELECT COUNT(*) FROM edges WHERE edge_type = 'DEFINES'),
            'IMPORTS', (SELECT COUNT(*) FROM edges WHERE edge_type = 'IMPORTS'),
            'CALLS', (SELECT COUNT(*) FROM edges WHERE edge_type = 'CALLS'),
            'MODIFIES', (SELECT COUNT(*) FROM edges WHERE edge_type = 'MODIFIES'),
            'REFERENCES', (SELECT COUNT(*) FROM edges WHERE edge_type = 'REFERENCES'),
            'IMPLEMENTS', (SELECT COUNT(*) FROM edges WHERE edge_type = 'IMPLEMENTS'),
            'EXTENDS', (SELECT COUNT(*) FROM edges WHERE edge_type = 'EXTENDS'),
            'RETURNS_TYPE', (SELECT COUNT(*) FROM edges WHERE edge_type = 'RETURNS_TYPE'),
            'ADR_RELATED', (SELECT COUNT(*) FROM edges WHERE edge_type = 'ADR_RELATED')
        ),
        'db_path', '$GRAPH_DB_PATH',
        'db_size_bytes', (SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size())
    );"

    run_sql "$sql"
}

# ==================== 命令: query ====================

cmd_query() {
    local sql="$1"

    if [[ -z "$sql" ]]; then
        log_error "SQL query required"
        return $EXIT_ARGS_ERROR
    fi

    run_sql_json "$sql"
}

# ==================== 命令: get-node ====================

cmd_get_node() {
    local node_id="$1"

    if [[ -z "$node_id" ]]; then
        log_error "Node ID required"
        return $EXIT_ARGS_ERROR
    fi

    local sql="SELECT json_object('id', id, 'symbol', symbol, 'kind', kind, 'file_path', file_path, 'line_start', line_start, 'line_end', line_end, 'created_at', created_at) FROM nodes WHERE id = '$(echo "$node_id" | sed "s/'/''/g")';"

    run_sql "$sql"
}

# ==================== 命令: delete-node ====================

cmd_delete_node() {
    local node_id="$1"

    if [[ -z "$node_id" ]]; then
        log_error "Node ID required"
        return $EXIT_ARGS_ERROR
    fi

    # 删除相关边和节点
    run_sql "BEGIN TRANSACTION;
             DELETE FROM edges WHERE source_id = '$(echo "$node_id" | sed "s/'/''/g")' OR target_id = '$(echo "$node_id" | sed "s/'/''/g")';
             DELETE FROM nodes WHERE id = '$(echo "$node_id" | sed "s/'/''/g")';
             COMMIT;"

    echo '{"status":"ok","deleted":"'"$node_id"'"}'
}

# ==================== 命令: delete-edge ====================

cmd_delete_edge() {
    local edge_id="$1"

    if [[ -z "$edge_id" ]]; then
        log_error "Edge ID required"
        return $EXIT_ARGS_ERROR
    fi

    run_sql "DELETE FROM edges WHERE id = '$(echo "$edge_id" | sed "s/'/''/g")';"

    echo '{"status":"ok","deleted":"'"$edge_id"'"}'
}

# ==================== 命令: migrate (AC-G01a) ====================

# 当前 Schema 版本
CURRENT_SCHEMA_VERSION=4

# 检查 Schema 是否需要迁移
check_schema_version() {
    local db_path="${1:-$GRAPH_DB_PATH}"

    if [[ ! -f "$db_path" ]]; then
        echo "missing"
        return 0
    fi

    # 检查是否存在 schema_version 表
    local has_version_table
    has_version_table=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='schema_version';" 2>/dev/null || echo "0")

    if [[ "$has_version_table" == "0" ]]; then
        echo "1"  # 旧版本，无 version 表
        return 0
    fi

    # 获取当前版本
    local version
    version=$(sqlite3 "$db_path" "SELECT MAX(version) FROM schema_version;" 2>/dev/null || echo "1")
    echo "${version:-1}"
}

# 检查边类型 CHECK 约束是否包含新类型
check_edge_type_constraint() {
    local db_path="${1:-$GRAPH_DB_PATH}"

    if [[ ! -f "$db_path" ]]; then
        return 1
    fi

    # 获取 edges 表的 CREATE 语句
    local create_sql
    create_sql=$(sqlite3 "$db_path" "SELECT sql FROM sqlite_master WHERE type='table' AND name='edges';" 2>/dev/null)

    if [[ -z "$create_sql" ]]; then
        return 1
    fi

    # 检查是否包含新边类型
    if [[ "$create_sql" == *"IMPLEMENTS"* && "$create_sql" == *"EXTENDS"* && "$create_sql" == *"RETURNS_TYPE"* && "$create_sql" == *"ADR_RELATED"* ]]; then
        return 0  # 已是最新
    fi

    return 1  # 需要迁移
}

cmd_migrate() {
    local check_only=false
    local apply=false
    local status_only=false
    local skip_precompute=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) check_only=true; shift ;;
            --apply) apply=true; shift ;;
            --status) status_only=true; shift ;;
            --skip-precompute) skip_precompute=true; shift ;;
            *) shift ;;
        esac
    done

    check_dependencies sqlite3 || exit $EXIT_DEPS_MISSING

    # 确保数据库目录存在
    ensure_db_dir

    # MP2.4: 并发迁移保护 (AC-U11)
    # [M-003] 使用原子操作防止竞态条件
    local lock_file="${GRAPH_DB_PATH}.migrate.lock"
    if [[ "$apply" == "true" ]]; then
        # C-006 fix: Use flock instead of mkdir-based locking
        # Open file descriptor 200 for the lock file
        exec 200>"$lock_file"

        # Try to acquire exclusive lock (non-blocking)
        if ! flock -n 200; then
            log_error "Migration in progress, please retry later"
            echo '{"status":"LOCKED","message":"Another migration process is running"}'
            return $EXIT_RUNTIME_ERROR
        fi

        # Set up trap to release lock on exit
        trap "flock -u 200; rm -f '$lock_file'" EXIT
    fi

    if [[ ! -f "$GRAPH_DB_PATH" ]]; then
        if [[ "$check_only" == "true" ]]; then
            echo '{"status":"MISSING","message":"数据库不存在，无需迁移"}'
            return 0
        elif [[ "$status_only" == "true" ]]; then
            echo '{"status":"MISSING","db_path":"'"$GRAPH_DB_PATH"'","message":"数据库不存在"}'
            return 0
        else
            log_info "数据库不存在，正在初始化..."
            cmd_init
            echo '{"status":"INITIALIZED","message":"已创建新数据库"}'
            return 0
        fi
    fi

    # 获取当前版本
    local current_version
    current_version=$(check_schema_version "$GRAPH_DB_PATH")

    # 检查边类型约束
    local needs_migration=false
    if ! check_edge_type_constraint "$GRAPH_DB_PATH"; then
        needs_migration=true
    fi
    if ! closure_tables_exist "$GRAPH_DB_PATH"; then
        needs_migration=true
    fi

    if [[ "$status_only" == "true" ]]; then
        # 获取边类型分布
        local needs_migration_flag="false"
        if [[ "$needs_migration" == "true" ]] || [[ "$current_version" -lt "$CURRENT_SCHEMA_VERSION" ]]; then
            needs_migration_flag="true"
        fi
        local stats
        stats=$(run_sql "SELECT json_object(
            'db_path', '$GRAPH_DB_PATH',
            'schema_version', $current_version,
            'target_version', $CURRENT_SCHEMA_VERSION,
            'needs_migration', '$needs_migration_flag',
            'edges_by_type', (SELECT json_object(
                'DEFINES', (SELECT COUNT(*) FROM edges WHERE edge_type = 'DEFINES'),
                'IMPORTS', (SELECT COUNT(*) FROM edges WHERE edge_type = 'IMPORTS'),
                'CALLS', (SELECT COUNT(*) FROM edges WHERE edge_type = 'CALLS'),
                'MODIFIES', (SELECT COUNT(*) FROM edges WHERE edge_type = 'MODIFIES'),
                'REFERENCES', (SELECT COUNT(*) FROM edges WHERE edge_type = 'REFERENCES'),
                'IMPLEMENTS', (SELECT COUNT(*) FROM edges WHERE edge_type = 'IMPLEMENTS'),
                'EXTENDS', (SELECT COUNT(*) FROM edges WHERE edge_type = 'EXTENDS'),
                'RETURNS_TYPE', (SELECT COUNT(*) FROM edges WHERE edge_type = 'RETURNS_TYPE'),
                'ADR_RELATED', (SELECT COUNT(*) FROM edges WHERE edge_type = 'ADR_RELATED')
            )),
            'total_nodes', (SELECT COUNT(*) FROM nodes),
            'total_edges', (SELECT COUNT(*) FROM edges)
        );")
        echo "$stats"
        return 0
    fi

    if [[ "$check_only" == "true" ]]; then
        if [[ "$needs_migration" == "true" ]] || [[ "$current_version" -lt "$CURRENT_SCHEMA_VERSION" ]]; then
            echo "NEEDS_MIGRATION"
            log_info "检测到旧版 Schema (v$current_version)，需要迁移到 v$CURRENT_SCHEMA_VERSION"
            return 0
        else
            echo "UP_TO_DATE"
            log_info "Schema 已是最新 (v$current_version)"
            return 0
        fi
    fi

    if [[ "$apply" == "true" ]]; then
        # 创建备份
        local backup_path="${GRAPH_DB_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "创建备份: $backup_path"
        cp "$GRAPH_DB_PATH" "$backup_path"

        # 同时备份 WAL 和 SHM 文件（如果存在）
        [[ -f "${GRAPH_DB_PATH}-wal" ]] && cp "${GRAPH_DB_PATH}-wal" "${backup_path}-wal"
        [[ -f "${GRAPH_DB_PATH}-shm" ]] && cp "${GRAPH_DB_PATH}-shm" "${backup_path}-shm"

        # 检查是否需要迁移
        if [[ "$needs_migration" != "true" ]] && [[ "$current_version" -ge "$CURRENT_SCHEMA_VERSION" ]]; then
            echo "{\"status\":\"UP_TO_DATE\",\"backup_path\":\"$backup_path\",\"schema_version\":$CURRENT_SCHEMA_VERSION}"
            return 0
        fi

        log_info "执行 Schema 迁移..."

        # 执行迁移（使用单个事务）
        local migrate_sql="
-- MP2.5: 启用外键约束检查 (AC-U11)
PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- 1. 导出现有数据
CREATE TEMP TABLE temp_edges AS SELECT * FROM edges;
CREATE TEMP TABLE temp_nodes AS SELECT * FROM nodes;

-- 2. 删除旧表（级联删除索引）
DROP TABLE IF EXISTS edges;
DROP TABLE IF EXISTS nodes;

-- 3. 创建新 nodes 表
CREATE TABLE nodes (
    id TEXT PRIMARY KEY,
    symbol TEXT NOT NULL,
    kind TEXT NOT NULL,
    file_path TEXT NOT NULL,
    line_start INTEGER,
    line_end INTEGER,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX idx_nodes_file ON nodes(file_path);
CREATE INDEX idx_nodes_symbol ON nodes(symbol);

-- 4. 创建新 edges 表（带扩展 CHECK 约束）
CREATE TABLE edges (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    edge_type TEXT NOT NULL CHECK(edge_type IN ('DEFINES', 'IMPORTS', 'CALLS', 'MODIFIES', 'REFERENCES', 'IMPLEMENTS', 'EXTENDS', 'RETURNS_TYPE', 'ADR_RELATED')),
    file_path TEXT,
    line INTEGER,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
);

CREATE INDEX idx_edges_source ON edges(source_id);
CREATE INDEX idx_edges_target ON edges(target_id);
CREATE INDEX idx_edges_type ON edges(edge_type);

-- MP2: 新增专用索引 (AC-U03)
CREATE INDEX idx_edges_implements ON edges(edge_type) WHERE edge_type = 'IMPLEMENTS';
CREATE INDEX idx_edges_extends ON edges(edge_type) WHERE edge_type = 'EXTENDS';
CREATE INDEX idx_edges_returns_type ON edges(edge_type) WHERE edge_type = 'RETURNS_TYPE';

-- MP4: 新增闭包表与路径索引
CREATE TABLE transitive_closure (
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    depth INTEGER NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    PRIMARY KEY (source_id, target_id),
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
);

CREATE INDEX idx_tc_source ON transitive_closure(source_id);
CREATE INDEX idx_tc_target ON transitive_closure(target_id);
CREATE INDEX idx_tc_depth ON transitive_closure(depth);

CREATE TABLE path_index (
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    path TEXT NOT NULL,
    edge_path TEXT,
    depth INTEGER NOT NULL,
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    PRIMARY KEY (source_id, target_id),
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
);

CREATE INDEX idx_path_source ON path_index(source_id);
CREATE INDEX idx_path_target ON path_index(target_id);
CREATE INDEX idx_path_depth ON path_index(depth);

-- MP7: user_signals 表
CREATE TABLE user_signals (
    file_path TEXT NOT NULL,
    signal_type TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    weight REAL NOT NULL,
    PRIMARY KEY (file_path, signal_type, timestamp)
);

CREATE INDEX idx_user_signals_file ON user_signals(file_path);
CREATE INDEX idx_user_signals_time ON user_signals(timestamp);

-- 5. 恢复数据（处理 v2 到 v3 的列映射）
-- v2 nodes: (id, type, name, file_path, metadata)
-- v3 nodes: (id, symbol, kind, file_path, line_start, line_end, created_at)
INSERT INTO nodes (id, symbol, kind, file_path, line_start, line_end)
SELECT
    id,
    name as symbol,  -- v2 的 name 映射到 v3 的 symbol
    type as kind,    -- v2 的 type 映射到 v3 的 kind
    file_path,
    NULL as line_start,
    NULL as line_end
FROM temp_nodes;

-- v2 edges: (id, source_id, target_id, edge_type, metadata)
-- v3 edges: (id, source_id, target_id, edge_type, file_path, line, created_at)
INSERT INTO edges (id, source_id, target_id, edge_type, file_path, line)
SELECT
    hex(randomblob(16)) as id,  -- v2 使用 INTEGER AUTOINCREMENT，v3 使用 TEXT，需要重新生成
    source_id,
    target_id,
    edge_type,
    NULL as file_path,
    NULL as line
FROM temp_edges;

-- 6. 更新版本
INSERT OR REPLACE INTO schema_version (version) VALUES ($CURRENT_SCHEMA_VERSION);

-- 7. 清理临时表
DROP TABLE temp_edges;
DROP TABLE temp_nodes;

COMMIT;
"

        if sqlite3 "$GRAPH_DB_PATH" "$migrate_sql" 2>&1; then
            # [M-004] 迁移数据完整性验证
            local before_nodes before_edges after_nodes after_edges
            before_nodes=$(sqlite3 "$backup_path" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
            before_edges=$(sqlite3 "$backup_path" "SELECT COUNT(*) FROM edges;" 2>/dev/null || echo "0")
            after_nodes=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;")
            after_edges=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges;")

            # 验证数据完整性
            if [[ "$before_nodes" != "$after_nodes" ]] || [[ "$before_edges" != "$after_edges" ]]; then
                log_error "数据完整性验证失败: nodes $before_nodes->$after_nodes, edges $before_edges->$after_edges"
                log_error "正在恢复备份..."
                cp "$backup_path" "$GRAPH_DB_PATH"
                [[ -f "${backup_path}-wal" ]] && cp "${backup_path}-wal" "${GRAPH_DB_PATH}-wal"
                [[ -f "${backup_path}-shm" ]] && cp "${backup_path}-shm" "${GRAPH_DB_PATH}-shm"
                echo '{"status":"INTEGRITY_FAILED","message":"数据完整性验证失败，已恢复备份"}'
                return $EXIT_RUNTIME_ERROR
            fi

            # [M-011 fix] 添加 checksum 验证
            local before_checksum after_checksum
            before_checksum=$(sqlite3 "$backup_path" "SELECT GROUP_CONCAT(id || symbol || kind) FROM (SELECT id, symbol, kind FROM nodes ORDER BY id);" 2>/dev/null | hash_string_md5)
            after_checksum=$(sqlite3 "$GRAPH_DB_PATH" "SELECT GROUP_CONCAT(id || symbol || kind) FROM (SELECT id, symbol, kind FROM nodes ORDER BY id);" 2>/dev/null | hash_string_md5)

            if [[ "$before_checksum" != "$after_checksum" ]]; then
                log_error "数据内容 checksum 验证失败: nodes checksum 不匹配"
                log_error "正在恢复备份..."
                cp "$backup_path" "$GRAPH_DB_PATH"
                [[ -f "${backup_path}-wal" ]] && cp "${backup_path}-wal" "${GRAPH_DB_PATH}-wal"
                [[ -f "${backup_path}-shm" ]] && cp "${backup_path}-shm" "${GRAPH_DB_PATH}-shm"
                echo '{"status":"CHECKSUM_FAILED","message":"数据内容验证失败，已恢复备份"}'
                return $EXIT_RUNTIME_ERROR
            fi

            # 验证外键约束
            local fk_violations
            fk_violations=$(sqlite3 "$GRAPH_DB_PATH" "PRAGMA foreign_key_check;" 2>&1)
            if [[ -n "$fk_violations" ]]; then
                log_error "外键约束验证失败: $fk_violations"
                log_error "正在恢复备份..."
                cp "$backup_path" "$GRAPH_DB_PATH"
                [[ -f "${backup_path}-wal" ]] && cp "${backup_path}-wal" "${GRAPH_DB_PATH}-wal"
                [[ -f "${backup_path}-shm" ]] && cp "${backup_path}-shm" "${GRAPH_DB_PATH}-shm"
                echo '{"status":"FK_VIOLATION","message":"外键约束验证失败，已恢复备份"}'
                return $EXIT_RUNTIME_ERROR
            fi

            # [M-011 fix] 验证索引完整性
            local index_check
            index_check=$(sqlite3 "$GRAPH_DB_PATH" "PRAGMA integrity_check;" 2>&1)
            if [[ "$index_check" != "ok" ]]; then
                log_error "索引完整性验证失败: $index_check"
                log_error "正在恢复备份..."
                cp "$backup_path" "$GRAPH_DB_PATH"
                [[ -f "${backup_path}-wal" ]] && cp "${backup_path}-wal" "${GRAPH_DB_PATH}-wal"
                [[ -f "${backup_path}-shm" ]] && cp "${backup_path}-shm" "${GRAPH_DB_PATH}-shm"
                echo '{"status":"INDEX_INTEGRITY_FAILED","message":"索引完整性验证失败，已恢复备份"}'
                return $EXIT_RUNTIME_ERROR
            fi

            if [[ "$skip_precompute" != "true" ]]; then
                precompute_closure_async
            fi

            log_ok "迁移完成，数据完整性验证通过"
            echo "{\"status\":\"MIGRATED\",\"backup_path\":\"$backup_path\",\"nodes\":$after_nodes,\"edges\":$after_edges,\"schema_version\":$CURRENT_SCHEMA_VERSION}"
        else
            log_error "迁移失败，正在恢复备份..."
            cp "$backup_path" "$GRAPH_DB_PATH"
            [[ -f "${backup_path}-wal" ]] && cp "${backup_path}-wal" "${GRAPH_DB_PATH}-wal"
            [[ -f "${backup_path}-shm" ]] && cp "${backup_path}-shm" "${GRAPH_DB_PATH}-shm"
            echo '{"status":"FAILED","message":"迁移失败，已恢复备份"}'
            return $EXIT_RUNTIME_ERROR
        fi
    fi
}

# ==================== 命令: find-path (AC-G02) ====================

cmd_find_path() {
    local from_node="" to_node="" max_depth=10 edge_types=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) from_node="$2"; shift 2 ;;
            --to) to_node="$2"; shift 2 ;;
            --max-depth) max_depth="$2"; shift 2 ;;
            --edge-types) edge_types="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # 验证必填字段
    if [[ -z "$from_node" || -z "$to_node" ]]; then
        log_error "Missing required fields: --from, --to"
        return $EXIT_ARGS_ERROR
    fi

    # 验证 max_depth 范围
    if [[ "$max_depth" -lt 1 || "$max_depth" -gt 10 ]]; then
        max_depth=10
    fi

    check_dependencies sqlite3 jq || exit $EXIT_DEPS_MISSING

    if [[ ! -f "$GRAPH_DB_PATH" ]]; then
        echo '{"found":false,"path":[],"edges":[],"length":0,"error":"数据库不存在"}'
        return 0
    fi

    local from_sql to_sql
    from_sql="$(escape_sql_string "$from_node")"
    to_sql="$(escape_sql_string "$to_node")"

    # 构建边类型过滤条件
    local edge_filter=""
    if [[ -n "$edge_types" ]]; then
        # 将逗号分隔的类型转为 SQL IN 子句
        local types_sql
        types_sql=$(echo "$edge_types" | sed "s/,/','/g")
        edge_filter="AND e.edge_type IN ('$types_sql')"
    fi

    # MP4: 优先使用闭包表/路径索引（无边类型过滤时）
    if [[ -z "$edge_types" ]] && closure_tables_exist "$GRAPH_DB_PATH"; then
        local closure_count
        closure_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM transitive_closure;" 2>/dev/null || echo "0")
        if [[ "$closure_count" -gt 0 ]]; then
            local closure_depth
            closure_depth=$(sqlite3 "$GRAPH_DB_PATH" "SELECT depth FROM transitive_closure WHERE source_id='$from_sql' AND target_id='$to_sql' AND depth <= $max_depth LIMIT 1;" 2>/dev/null || echo "")

            if [[ -z "$closure_depth" ]]; then
                echo '{"found":false,"path":[],"edges":[],"length":0}'
                return 0
            fi

            local path_row
            path_row=$(sqlite3 -separator $'\t' "$GRAPH_DB_PATH" "SELECT path, edge_path, depth FROM path_index WHERE source_id='$from_sql' AND target_id='$to_sql' AND depth <= $max_depth LIMIT 1;" 2>/dev/null || true)
            if [[ -n "$path_row" ]]; then
                local path_json edge_json depth_val
                IFS=$'\t' read -r path_json edge_json depth_val <<< "$path_row"
                [[ -z "$edge_json" ]] && edge_json="[]"
                [[ -z "$depth_val" ]] && depth_val="$closure_depth"
                echo "{\"found\":true,\"path\":$path_json,\"edges\":$edge_json,\"length\":$depth_val}"
                return 0
            fi
        fi
    fi

    # 使用递归 CTE 进行 BFS 最短路径查询（字符串路径，避免 JSON 函数兼容性问题）
    local path_sql="
WITH RECURSIVE
    path_cte(node_id, path, depth) AS (
        SELECT
            '$from_sql',
            '$from_sql',
            0
        UNION ALL
        SELECT
            e.target_id,
            p.path || '>' || e.target_id,
            p.depth + 1
        FROM path_cte p
        JOIN edges e ON e.source_id = p.node_id
        WHERE p.depth < $max_depth
            AND instr(p.path, e.target_id) = 0
            $edge_filter
    )
SELECT
    p.node_id,
    p.path,
    p.depth
FROM path_cte p
WHERE p.node_id = '$to_sql'
ORDER BY p.depth ASC
LIMIT 1;
"

    local result
    result=$(sqlite3 -separator $'\t' "$GRAPH_DB_PATH" "$path_sql" 2>/dev/null)

    if [[ -z "$result" ]]; then
        echo '{"found":false,"path":[],"edges":[],"length":0}'
        return 0
    fi

    local node_id path_str depth
    IFS=$'\t' read -r node_id path_str depth <<< "$result"

    local path_json
    path_json=$(printf '%s\n' "$path_str" | tr '>' '\n' | jq -R '.' | jq -s '.')

    local edges_json='[]'
    local node_list=()
    IFS='>' read -r -a node_list <<< "$path_str"
    if [ "${#node_list[@]}" -gt 1 ]; then
        local i
        for ((i=0; i<${#node_list[@]}-1; i++)); do
            local from_id="${node_list[$i]}"
            local to_id="${node_list[$((i+1))]}"
            local edge_type
            edge_type=$(sqlite3 "$GRAPH_DB_PATH" "SELECT edge_type FROM edges WHERE source_id='$(escape_sql_string "$from_id")' AND target_id='$(escape_sql_string "$to_id")' LIMIT 1;" 2>/dev/null || true)
            edges_json=$(echo "$edges_json" | jq --arg from "$from_id" --arg to "$to_id" --arg type "$edge_type" \
              '. + [{from: $from, to: $to, type: $type}]')
        done
    fi

    echo "{\"found\":true,\"path\":$path_json,\"edges\":$edges_json,\"length\":$depth}"
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
graph-store.sh - SQLite 图存储管理

用法:
    graph-store.sh <command> [options]
    graph-store.sh --enable-all-features <command> [options]

命令:
    init                    初始化数据库
    add-node                添加节点
    add-edge                添加边
    query-edges             查询边
    find-orphans            查找孤儿节点
    find-path               查找最短路径（A→B）
    batch-import            批量导入
    stats                   统计信息
    migrate                 Schema 迁移
    query <sql>             执行 SQL 查询
    get-node <id>           获取节点
    delete-node <id>        删除节点
    delete-edge <id>        删除边

add-node 选项:
    --id <id>               节点 ID（必填）
    --symbol <symbol>       符号名称（必填）
    --kind <kind>           节点类型（必填）
    --file <path>           文件路径（必填）
    --line-start <n>        起始行号
    --line-end <n>          结束行号

add-edge 选项:
    --source <id>           源节点 ID（必填）
    --target <id>           目标节点 ID（必填）
    --type <type>           边类型（必填）: DEFINES, IMPORTS, CALLS, MODIFIES, REFERENCES,
                                           IMPLEMENTS, EXTENDS, RETURNS_TYPE, ADR_RELATED
    --file <path>           文件路径
    --line <n>              行号

init 选项:
    --skip-precompute       跳过闭包表预计算

query-edges 选项:
    --from <id>             源节点 ID
    --to <id>               目标节点 ID
    --type <type>           边类型

find-orphans 选项:
    --exclude <pattern>     排除模式（glob）

batch-import 选项:
    --file <path>           JSON 文件路径
    --skip-precompute       跳过闭包表预计算

find-path 选项:
    --from <id>             源节点 ID（必填）
    --to <id>               目标节点 ID（必填）
    --max-depth <n>         最大搜索深度（默认: 10）
    --edge-types <types>    逗号分隔的边类型过滤

migrate 选项:
    --check                 检查是否需要迁移
    --apply                 执行迁移（自动备份）
    --status                显示当前状态
    --skip-precompute       跳过闭包表预计算

环境变量:
    GRAPH_DB_PATH           数据库路径（默认: .devbooks/graph.db）
    GRAPH_WAL_MODE          WAL 模式（默认: true）

示例:
    # 初始化数据库
    graph-store.sh init

    # 添加节点
    graph-store.sh add-node --id "sym:func:main" --symbol "main" --kind "function" --file "src/index.ts"

    # 添加边
    graph-store.sh add-edge --source "sym:func:main" --target "sym:func:helper" --type CALLS

    # 查询出边
    graph-store.sh query-edges --from "sym:func:main" --type CALLS

    # 查找孤儿节点
    graph-store.sh find-orphans

    # 获取统计信息
    graph-store.sh stats
EOF
}

# ==================== 主入口 ====================

main() {
    if [[ "${1:-}" == "--enable-all-features" ]]; then
        DEVBOOKS_ENABLE_ALL_FEATURES=1
        shift
    fi

    if declare -f is_feature_enabled &>/dev/null; then
        if ! is_feature_enabled "graph_store"; then
            log_warn "图存储功能已禁用 (features.graph_store: false)"
            echo '{"status":"disabled","message":"graph_store disabled"}'
            return 0
        fi
    fi

    local command="${1:-help}"
    shift || true

    case "$command" in
        init)
            cmd_init "$@"
            ;;
        add-node)
            cmd_add_node "$@"
            ;;
        add-edge)
            cmd_add_edge "$@"
            ;;
        query-edges)
            cmd_query_edges "$@"
            ;;
        find-orphans)
            cmd_find_orphans "$@"
            ;;
        find-path)
            cmd_find_path "$@"
            ;;
        batch-import)
            cmd_batch_import "$@"
            ;;
        stats)
            cmd_stats "$@"
            ;;
        query)
            cmd_query "$@"
            ;;
        get-node)
            cmd_get_node "$@"
            ;;
        delete-node)
            cmd_delete_node "$@"
            ;;
        delete-edge)
            cmd_delete_edge "$@"
            ;;
        migrate)
            cmd_migrate "$@"
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
