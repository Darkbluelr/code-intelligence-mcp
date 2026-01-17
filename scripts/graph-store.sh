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
LOG_PREFIX="graph-store"

# ==================== 配置 ====================

# 默认数据库路径
: "${DEVBOOKS_DIR:=.devbooks}"
: "${GRAPH_DB_PATH:=$DEVBOOKS_DIR/graph.db}"
: "${GRAPH_WAL_MODE:=true}"

# 有效边类型（扩展 AC-G01: 支持 IMPLEMENTS/EXTENDS/RETURNS_TYPE/ADR_RELATED）
VALID_EDGE_TYPES=("DEFINES" "IMPORTS" "CALLS" "MODIFIES" "REFERENCES" "IMPLEMENTS" "EXTENDS" "RETURNS_TYPE" "ADR_RELATED")

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

INSERT OR IGNORE INTO schema_version (version) VALUES (2);
EOF
}

# ==================== 命令: init ====================

cmd_init() {
    check_dependencies sqlite3 || exit $EXIT_DEPS_MISSING

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

    # 处理可选字段
    local line_start_sql="NULL"
    local line_end_sql="NULL"
    [[ -n "$line_start" ]] && line_start_sql="$line_start"
    [[ -n "$line_end" ]] && line_end_sql="$line_end"

    # 插入节点（使用参数化查询防止 SQL 注入）
    local sql="INSERT OR REPLACE INTO nodes (id, symbol, kind, file_path, line_start, line_end) VALUES ('$(echo "$id" | sed "s/'/''/g")', '$(echo "$symbol" | sed "s/'/''/g")', '$(echo "$kind" | sed "s/'/''/g")', '$(echo "$file_path" | sed "s/'/''/g")', $line_start_sql, $line_end_sql);"

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

    # 验证边类型
    if ! is_valid_edge_type "$edge_type"; then
        log_error "Invalid edge type: $edge_type. Valid types: DEFINES, IMPORTS, CALLS, MODIFIES, REFERENCES, IMPLEMENTS, EXTENDS, RETURNS_TYPE, ADR_RELATED"
        return $EXIT_ARGS_ERROR
    fi

    # 生成边 ID
    local edge_id
    edge_id=$(generate_id "edge")

    # 处理可选字段
    local file_sql="NULL"
    local line_sql="NULL"
    [[ -n "$file_path" ]] && file_sql="'$(echo "$file_path" | sed "s/'/''/g")'"
    [[ -n "$line" ]] && line_sql="$line"

    # 插入边
    local sql="INSERT INTO edges (id, source_id, target_id, edge_type, file_path, line) VALUES ('$edge_id', '$(echo "$source_id" | sed "s/'/''/g")', '$(echo "$target_id" | sed "s/'/''/g")', '$edge_type', $file_sql, $line_sql);"

    if run_sql "$sql"; then
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

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) input_file="$2"; shift 2 ;;
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

    # 处理节点
    local nodes
    nodes=$(jq -c '.nodes // []' "$input_file")

    if [[ "$nodes" != "[]" ]]; then
        while IFS= read -r node; do
            local id symbol kind file_path line_start line_end

            id=$(echo "$node" | jq -r '.id // empty')
            symbol=$(echo "$node" | jq -r '.symbol // empty')
            kind=$(echo "$node" | jq -r '.kind // empty')
            file_path=$(echo "$node" | jq -r '.file_path // empty')
            line_start=$(echo "$node" | jq -r '.line_start // "NULL"')
            line_end=$(echo "$node" | jq -r '.line_end // "NULL"')

            # 验证必填字段
            if [[ -z "$id" || -z "$symbol" || -z "$kind" || -z "$file_path" ]]; then
                log_error "Node missing required fields: id, symbol, kind, file_path"
                return $EXIT_ARGS_ERROR
            fi

            # 处理 NULL 值
            [[ "$line_start" == "null" ]] && line_start="NULL"
            [[ "$line_end" == "null" ]] && line_end="NULL"

            sql+="INSERT OR REPLACE INTO nodes (id, symbol, kind, file_path, line_start, line_end) VALUES ('$(echo "$id" | sed "s/'/''/g")', '$(echo "$symbol" | sed "s/'/''/g")', '$(echo "$kind" | sed "s/'/''/g")', '$(echo "$file_path" | sed "s/'/''/g")', $line_start, $line_end);"
        done < <(echo "$nodes" | jq -c '.[]')
    fi

    # 处理边
    local edges
    edges=$(jq -c '.edges // []' "$input_file")

    if [[ "$edges" != "[]" ]]; then
        while IFS= read -r edge; do
            local source_id target_id edge_type file_path line

            source_id=$(echo "$edge" | jq -r '.source_id // empty')
            target_id=$(echo "$edge" | jq -r '.target_id // empty')
            edge_type=$(echo "$edge" | jq -r '.edge_type // empty')
            file_path=$(echo "$edge" | jq -r '.file_path // "NULL"')
            line=$(echo "$edge" | jq -r '.line // "NULL"')

            # 验证边类型
            if ! is_valid_edge_type "$edge_type"; then
                log_error "Invalid edge type: $edge_type"
                return $EXIT_ARGS_ERROR
            fi

            local edge_id
            edge_id=$(generate_id "edge")

            # 处理 NULL 值
            [[ "$file_path" == "null" || "$file_path" == "NULL" ]] && file_path="NULL" || file_path="'$(echo "$file_path" | sed "s/'/''/g")'"
            [[ "$line" == "null" ]] && line="NULL"

            sql+="INSERT INTO edges (id, source_id, target_id, edge_type, file_path, line) VALUES ('$edge_id', '$(echo "$source_id" | sed "s/'/''/g")', '$(echo "$target_id" | sed "s/'/''/g")', '$edge_type', $file_path, $line);"
        done < <(echo "$edges" | jq -c '.[]')
    fi

    sql+="COMMIT;"

    if echo "$sql" | sqlite3 "$GRAPH_DB_PATH"; then
        local node_count edge_count
        node_count=$(jq '.nodes | length' "$input_file")
        edge_count=$(jq '.edges // [] | length' "$input_file")
        echo "{\"status\":\"ok\",\"nodes_imported\":$node_count,\"edges_imported\":$edge_count}"
    else
        log_error "Batch import failed, rolling back"
        run_sql "ROLLBACK;" 2>/dev/null || true
        return $EXIT_RUNTIME_ERROR
    fi
}

# ==================== 命令: stats ====================

cmd_stats() {
    local sql='SELECT json_object(
        "nodes", (SELECT COUNT(*) FROM nodes),
        "edges", (SELECT COUNT(*) FROM edges),
        "edges_by_type", json_object(
            "DEFINES", (SELECT COUNT(*) FROM edges WHERE edge_type = "DEFINES"),
            "IMPORTS", (SELECT COUNT(*) FROM edges WHERE edge_type = "IMPORTS"),
            "CALLS", (SELECT COUNT(*) FROM edges WHERE edge_type = "CALLS"),
            "MODIFIES", (SELECT COUNT(*) FROM edges WHERE edge_type = "MODIFIES"),
            "REFERENCES", (SELECT COUNT(*) FROM edges WHERE edge_type = "REFERENCES"),
            "IMPLEMENTS", (SELECT COUNT(*) FROM edges WHERE edge_type = "IMPLEMENTS"),
            "EXTENDS", (SELECT COUNT(*) FROM edges WHERE edge_type = "EXTENDS"),
            "RETURNS_TYPE", (SELECT COUNT(*) FROM edges WHERE edge_type = "RETURNS_TYPE"),
            "ADR_RELATED", (SELECT COUNT(*) FROM edges WHERE edge_type = "ADR_RELATED")
        ),
        "db_path", "'"$GRAPH_DB_PATH"'",
        "db_size_bytes", (SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size())
    );'

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
CURRENT_SCHEMA_VERSION=3

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

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) check_only=true; shift ;;
            --apply) apply=true; shift ;;
            --status) status_only=true; shift ;;
            *) shift ;;
        esac
    done

    check_dependencies sqlite3 || exit $EXIT_DEPS_MISSING

    # 确保数据库目录存在
    ensure_db_dir

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

    if [[ "$status_only" == "true" ]]; then
        # 获取边类型分布
        local stats
        stats=$(run_sql "SELECT json_object(
            'db_path', '$GRAPH_DB_PATH',
            'schema_version', $current_version,
            'target_version', $CURRENT_SCHEMA_VERSION,
            'needs_migration', CASE WHEN $current_version < $CURRENT_SCHEMA_VERSION THEN 'true' ELSE 'false' END,
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
            return 1
        else
            echo "UP_TO_DATE"
            log_info "Schema 已是最新 (v$current_version)"
            return 0
        fi
    fi

    if [[ "$apply" == "true" ]]; then
        # 检查是否需要迁移
        if [[ "$needs_migration" != "true" ]] && [[ "$current_version" -ge "$CURRENT_SCHEMA_VERSION" ]]; then
            echo '{"status":"UP_TO_DATE","message":"Schema 已是最新，无需迁移"}'
            return 0
        fi

        # 创建备份
        local backup_path="${GRAPH_DB_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "创建备份: $backup_path"
        cp "$GRAPH_DB_PATH" "$backup_path"

        # 同时备份 WAL 和 SHM 文件（如果存在）
        [[ -f "${GRAPH_DB_PATH}-wal" ]] && cp "${GRAPH_DB_PATH}-wal" "${backup_path}-wal"
        [[ -f "${GRAPH_DB_PATH}-shm" ]] && cp "${GRAPH_DB_PATH}-shm" "${backup_path}-shm"

        log_info "执行 Schema 迁移..."

        # 执行迁移（使用单个事务）
        local migrate_sql="
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

-- 5. 恢复数据
INSERT INTO nodes SELECT * FROM temp_nodes;
INSERT INTO edges SELECT * FROM temp_edges;

-- 6. 更新版本
INSERT OR REPLACE INTO schema_version (version) VALUES ($CURRENT_SCHEMA_VERSION);

-- 7. 清理临时表
DROP TABLE temp_edges;
DROP TABLE temp_nodes;

COMMIT;
"

        if sqlite3 "$GRAPH_DB_PATH" "$migrate_sql" 2>&1; then
            local after_nodes after_edges
            after_nodes=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM nodes;")
            after_edges=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges;")

            log_ok "迁移完成"
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

    # 构建边类型过滤条件
    local edge_filter=""
    if [[ -n "$edge_types" ]]; then
        # 将逗号分隔的类型转为 SQL IN 子句
        local types_sql
        types_sql=$(echo "$edge_types" | sed "s/,/','/g")
        edge_filter="AND e.edge_type IN ('$types_sql')"
    fi

    # 使用递归 CTE 进行 BFS 最短路径查询
    # 注意：SQLite 的递归 CTE 天然是 BFS（广度优先），因为它按层级展开
    local path_sql="
WITH RECURSIVE
    -- 起始点
    path_cte(node_id, path, edge_path, depth, visited) AS (
        SELECT
            '$from_node',
            json_array('$from_node'),
            json_array(),
            0,
            ',$from_node,'

        UNION ALL

        -- 递归扩展
        SELECT
            e.target_id,
            json_insert(p.path, '\$[#]', e.target_id),
            json_insert(p.edge_path, '\$[#]', json_object('from', e.source_id, 'to', e.target_id, 'type', e.edge_type)),
            p.depth + 1,
            p.visited || e.target_id || ','
        FROM path_cte p
        JOIN edges e ON e.source_id = p.node_id
        WHERE p.depth < $max_depth
            AND p.visited NOT LIKE '%,' || e.target_id || ',%'
            $edge_filter
    )
SELECT
    p.node_id,
    p.path,
    p.edge_path,
    p.depth
FROM path_cte p
WHERE p.node_id = '$to_node'
ORDER BY p.depth ASC
LIMIT 1;
"

    local result
    result=$(sqlite3 -separator $'\t' "$GRAPH_DB_PATH" "$path_sql" 2>/dev/null)

    if [[ -z "$result" ]]; then
        # 未找到路径
        echo '{"found":false,"path":[],"edges":[],"length":0}'
        return 0
    fi

    # 解析结果
    local node_id path edge_path depth
    IFS=$'\t' read -r node_id path edge_path depth <<< "$result"

    # 构建包含节点详情的完整路径
    local path_nodes
    path_nodes=$(sqlite3 -json "$GRAPH_DB_PATH" "
        SELECT n.id as node_id, n.symbol, n.file_path as file
        FROM nodes n
        WHERE n.id IN (SELECT value FROM json_each('$path'))
        ORDER BY (
            SELECT key FROM json_each('$path') WHERE value = n.id
        );
    " 2>/dev/null)

    # 如果节点查询失败，使用简单格式
    if [[ -z "$path_nodes" || "$path_nodes" == "[]" ]]; then
        path_nodes="$path"
    fi

    # 输出结果
    echo "{\"found\":true,\"path\":$path_nodes,\"edges\":$edge_path,\"length\":$depth}"
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
graph-store.sh - SQLite 图存储管理

用法:
    graph-store.sh <command> [options]

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

query-edges 选项:
    --from <id>             源节点 ID
    --to <id>               目标节点 ID
    --type <type>           边类型

find-orphans 选项:
    --exclude <pattern>     排除模式（glob）

batch-import 选项:
    --file <path>           JSON 文件路径

find-path 选项:
    --from <id>             源节点 ID（必填）
    --to <id>               目标节点 ID（必填）
    --max-depth <n>         最大搜索深度（默认: 10）
    --edge-types <types>    逗号分隔的边类型过滤

migrate 选项:
    --check                 检查是否需要迁移
    --apply                 执行迁移（自动备份）
    --status                显示当前状态

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
