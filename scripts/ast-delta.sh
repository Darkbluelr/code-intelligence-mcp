#!/bin/bash
# ast-delta.sh - AST Delta 增量索引协调脚本
# 版本: 1.0
# 用途: 协调 tree-sitter 解析、缓存管理和图存储更新
#
# 覆盖 AC-F01: AST Delta 增量索引：单文件更新 P95 < 100ms（±20%）
#
# 命令:
#   update <file-path>     - 单文件增量更新
#   batch [--since <ref>]  - 批量增量更新
#   status                 - 显示索引状态
#   clear-cache            - 清理 AST 缓存
#
# 状态机:
#   IDLE → CHECK → INCREMENTAL/FULL_REBUILD/FALLBACK → CLEANUP
#
# 环境变量:
#   GRAPH_DB_PATH          - 图数据库路径
#   AST_CACHE_DIR          - AST 缓存目录
#   AST_DELTA_BATCH_THRESHOLD - 触发全量重建的文件数阈值（默认 10）
#   DISABLE_TREE_SITTER    - 禁用 tree-sitter（用于测试降级）
#   FORCE_SCIP_FALLBACK    - 强制使用 SCIP 降级

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀
LOG_PREFIX="ast-delta"

# ==================== 配置 ====================

# 默认配置
: "${DEVBOOKS_DIR:=.devbooks}"
: "${GRAPH_DB_PATH:=$DEVBOOKS_DIR/graph.db}"
: "${AST_CACHE_DIR:=$DEVBOOKS_DIR/ast-cache}"
: "${AST_DELTA_BATCH_THRESHOLD:=10}"
: "${AST_CACHE_MAX_SIZE_MB:=50}"
: "${AST_CACHE_TTL_DAYS:=30}"

# 版本戳文件
VERSION_STAMP_FILE="$AST_CACHE_DIR/.version"

# 状态常量
STATE_IDLE="IDLE"
STATE_CHECK="CHECK"
STATE_INCREMENTAL="INCREMENTAL"
STATE_FULL_REBUILD="FULL_REBUILD"
STATE_FALLBACK="FALLBACK"
STATE_CLEANUP="CLEANUP"

# ==================== 辅助函数 ====================

# 确保目录存在
ensure_dirs() {
    mkdir -p "$DEVBOOKS_DIR"
    mkdir -p "$AST_CACHE_DIR"
}

# 上次清理时间戳
_LAST_CLEANUP_TIME=0

# 清理孤儿临时文件（带节流，最多每 60 秒一次）
cleanup_orphan_temp_files() {
    local current_time
    current_time=$(date +%s)

    # 节流：如果距离上次清理不足 60 秒，跳过（可通过 AST_DELTA_THROTTLE_INTERVAL 配置）
    local throttle_interval="${AST_DELTA_THROTTLE_INTERVAL:-60}"
    if (( current_time - _LAST_CLEANUP_TIME < throttle_interval )); then
        return 0
    fi

    _LAST_CLEANUP_TIME=$current_time

    # 清理孤儿临时文件（默认只清理超过 1 分钟的文件，可通过 AST_DELTA_CLEANUP_MIN_AGE 配置）
    local min_age="${AST_DELTA_CLEANUP_MIN_AGE:-1}"
    local temp_files
    if [[ "$min_age" -eq 0 ]]; then
        temp_files=$(find "$DEVBOOKS_DIR" -name ".ast-delta-temp-*.tmp" 2>/dev/null || true)
    else
        temp_files=$(find "$DEVBOOKS_DIR" -name ".ast-delta-temp-*.tmp" -mmin +"$min_age" 2>/dev/null || true)
    fi
    if [[ -n "$temp_files" ]]; then
        log_info "Cleaning up orphan temp files..."
        echo "$temp_files" | xargs rm -f 2>/dev/null || true
    fi
}

# 获取文件的缓存路径
get_cache_path() {
    local file_path="$1"
    # 将路径中的 / 替换为 _
    local safe_path
    safe_path=$(echo "$file_path" | sed 's/\//_/g')
    echo "$AST_CACHE_DIR/${safe_path}.ast"
}

# 缓存 tree-sitter 可用性检查结果
_TREE_SITTER_AVAILABLE=""

# 检查 tree-sitter 是否可用（带缓存）
check_tree_sitter_available() {
    # 如果已经检查过，返回缓存结果
    if [[ -n "$_TREE_SITTER_AVAILABLE" ]]; then
        [[ "$_TREE_SITTER_AVAILABLE" == "yes" ]]
        return
    fi

    # 检查环境变量禁用
    if [[ "${DISABLE_TREE_SITTER:-false}" == "true" ]]; then
        _TREE_SITTER_AVAILABLE="no"
        return 1
    fi

    # 检查 Node.js 可用性
    if ! command -v node &>/dev/null; then
        _TREE_SITTER_AVAILABLE="no"
        return 1
    fi

    # 检查 tree-sitter 模块
    local check_script='
        try {
            require("tree-sitter");
            require("tree-sitter-typescript");
            process.exit(0);
        } catch (e) {
            process.exit(1);
        }
    '

    if node -e "$check_script" 2>/dev/null; then
        _TREE_SITTER_AVAILABLE="yes"
        return 0
    else
        _TREE_SITTER_AVAILABLE="no"
        return 1
    fi
}

# 读取版本戳
read_version_stamp() {
    if [[ -f "$VERSION_STAMP_FILE" ]]; then
        cat "$VERSION_STAMP_FILE" 2>/dev/null || echo "{}"
    else
        echo "{}"
    fi
}

# 写入版本戳（原子操作）
write_version_stamp() {
    local content="$1"
    local tmp_file="$VERSION_STAMP_FILE.tmp.$$"

    echo "$content" > "$tmp_file"

    if [[ -s "$tmp_file" ]]; then
        mv "$tmp_file" "$VERSION_STAMP_FILE"
    else
        rm -f "$tmp_file"
        return 1
    fi
}

# 获取数据库版本戳
get_db_version_stamp() {
    if [[ ! -f "$GRAPH_DB_PATH" ]]; then
        echo ""
        return
    fi

    sqlite3 "$GRAPH_DB_PATH" "SELECT value FROM metadata WHERE key = 'ast_cache_version';" 2>/dev/null || echo ""
}

# 设置数据库版本戳
set_db_version_stamp() {
    local version="$1"

    if [[ ! -f "$GRAPH_DB_PATH" ]]; then
        return 1
    fi

    # 确保 metadata 表存在
    sqlite3 "$GRAPH_DB_PATH" "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT);" 2>/dev/null

    sqlite3 "$GRAPH_DB_PATH" "INSERT OR REPLACE INTO metadata (key, value) VALUES ('ast_cache_version', '$version');" 2>/dev/null
}

# 生成当前版本戳
generate_version_stamp() {
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local scip_mtime=""
    if [[ -f "index.scip" ]]; then
        scip_mtime=$(stat -c %Y "index.scip" 2>/dev/null || stat -f %m "index.scip" 2>/dev/null || echo "")
    fi

    local file_count
    file_count=$(find "$AST_CACHE_DIR" -name "*.ast" 2>/dev/null | wc -l | tr -d ' ')

    # 生成 JSON 格式的版本戳
    cat << EOF
{
    "timestamp": "$timestamp",
    "scip_mtime": "$scip_mtime",
    "file_count": $file_count
}
EOF
}

# 原子写入缓存文件
atomic_write_cache() {
    local file_path="$1"
    local content="$2"
    local cache_file
    cache_file=$(get_cache_path "$file_path")
    local tmp_file="$cache_file.tmp.$$"

    # 确保缓存目录存在
    mkdir -p "$(dirname "$cache_file")"

    # 写入临时文件
    echo "$content" > "$tmp_file"

    # 验证写入成功
    if [[ ! -s "$tmp_file" ]]; then
        rm -f "$tmp_file"
        return 1
    fi

    # 原子移动
    mv "$tmp_file" "$cache_file"
}

# 使用 Node.js 解析文件
parse_file_with_node() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        echo '{"error": "file not found"}'
        return 1
    fi

    # 检查是否为 TypeScript/JavaScript 文件
    local ext="${file_path##*.}"
    case "$ext" in
        ts|tsx|js|jsx|mts|mjs)
            ;;
        *)
            # 非 TypeScript/JavaScript 文件，返回空 AST
            echo '{"id": "'"$file_path"':program:1", "type": "program", "startLine": 1, "endLine": 1, "children": []}'
            return 0
            ;;
    esac

    # 创建 Node.js 解析脚本
    local parse_script='
        const fs = require("fs");
        const path = require("path");

        const filePath = process.argv[1];
        const code = fs.readFileSync(filePath, "utf-8");

        // 尝试加载 ast-delta 模块
        let astDelta;
        try {
            // 首先尝试从 dist 目录加载
            astDelta = require(path.join(process.cwd(), "dist", "ast-delta.js"));
        } catch (e1) {
            try {
                // 然后尝试从 src 目录加载（需要 ts-node）
                require("ts-node/register");
                astDelta = require(path.join(process.cwd(), "src", "ast-delta.ts"));
            } catch (e2) {
                // 降级到直接使用 tree-sitter
                const Parser = require("tree-sitter");
                const TypeScript = require("tree-sitter-typescript").typescript;
                const parser = new Parser();
                parser.setLanguage(TypeScript);
                const tree = parser.parse(code);
                const result = {
                    id: filePath + ":program:1",
                    type: "program",
                    startLine: 1,
                    endLine: code.split("\n").length,
                    children: []
                };
                console.log(JSON.stringify(result));
                process.exit(0);
            }
        }

        const result = astDelta.parseTypeScript(code, { filePath: filePath });
        console.log(JSON.stringify(result));
    '

    # 执行解析
    node -e "$parse_script" "$file_path" 2>/dev/null
}

# 使用正则表达式解析（降级模式）
parse_file_with_regex() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        echo '{"error": "file not found"}'
        return 1
    fi

    local content
    content=$(cat "$file_path" 2>/dev/null || echo "")
    local line_count
    line_count=$(echo "$content" | wc -l | tr -d ' ')

    # 简单的符号提取
    local symbols='[]'

    # 使用 grep 提取函数和类定义
    local funcs
    funcs=$(grep -n "^[[:space:]]*\(export[[:space:]]\+\)\?\(async[[:space:]]\+\)\?function[[:space:]]\+" "$file_path" 2>/dev/null || true)

    local classes
    classes=$(grep -n "^[[:space:]]*\(export[[:space:]]\+\)\?\(abstract[[:space:]]\+\)\?class[[:space:]]\+" "$file_path" 2>/dev/null || true)

    # 构建 JSON 结果
    cat << EOF
{
    "id": "$file_path:program:1",
    "type": "program",
    "startLine": 1,
    "endLine": $line_count,
    "children": []
}
EOF
}

# 决策状态（返回应执行的状态）
determine_state() {
    local file_count="${1:-1}"

    # 条件 C：tree-sitter 不可用 -> FALLBACK
    if [[ "${FORCE_SCIP_FALLBACK:-false}" == "true" ]]; then
        echo "$STATE_FALLBACK"
        return
    fi

    if ! check_tree_sitter_available; then
        echo "$STATE_FALLBACK"
        return
    fi

    # 条件 B：缓存不存在或版本不一致或文件数过多 -> FULL_REBUILD
    if [[ ! -d "$AST_CACHE_DIR" ]] || [[ ! -f "$VERSION_STAMP_FILE" ]]; then
        echo "$STATE_FULL_REBUILD"
        return
    fi

    local cache_version
    cache_version=$(cat "$VERSION_STAMP_FILE" 2>/dev/null | grep -o '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    local db_version
    db_version=$(get_db_version_stamp)

    # 检查版本一致性（如果数据库有版本戳）
    if [[ -n "$db_version" ]] && [[ "$cache_version" != "$db_version" ]]; then
        echo "$STATE_FULL_REBUILD"
        return
    fi

    # 检查文件数阈值
    if [[ "$file_count" -gt "$AST_DELTA_BATCH_THRESHOLD" ]]; then
        echo "$STATE_FULL_REBUILD"
        return
    fi

    # 条件 A：满足增量更新条件 -> INCREMENTAL
    echo "$STATE_INCREMENTAL"
}

# 更新图数据库
update_graph_db() {
    local file_path="$1"
    local ast_json="$2"

    # 检查 graph-store.sh 是否存在
    if [[ ! -x "$SCRIPT_DIR/graph-store.sh" ]]; then
        log_warn "graph-store.sh not found, skipping graph update"
        return 0
    fi

    # 确保数据库已初始化
    "$SCRIPT_DIR/graph-store.sh" init >/dev/null 2>&1 || true

    # 从 AST 中提取符号并添加到图数据库
    if command -v jq &>/dev/null; then
        # 解析 AST JSON 并添加节点
        local nodes
        nodes=$(echo "$ast_json" | jq -c 'recurse(.children[]?) | select(.name != null)' 2>/dev/null || true)

        if [[ -n "$nodes" ]]; then
            while IFS= read -r node; do
                local id name kind line_start line_end

                id=$(echo "$node" | jq -r '.id // empty')
                name=$(echo "$node" | jq -r '.name // empty')
                kind=$(echo "$node" | jq -r '.type // empty')
                line_start=$(echo "$node" | jq -r '.startLine // empty')
                line_end=$(echo "$node" | jq -r '.endLine // empty')

                if [[ -n "$id" && -n "$name" && -n "$kind" ]]; then
                    "$SCRIPT_DIR/graph-store.sh" add-node \
                        --id "$id" \
                        --symbol "$name" \
                        --kind "$kind" \
                        --file "$file_path" \
                        --line-start "$line_start" \
                        --line-end "$line_end" >/dev/null 2>&1 || true
                fi
            done <<< "$nodes"
        fi
    fi
}

# ==================== 命令: update ====================

cmd_update() {
    local file_path=""
    local force_rebuild=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force-rebuild)
                force_rebuild=true
                shift
                ;;
            *)
                file_path="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$file_path" ]]; then
        log_error "File path required"
        echo '{"error": "file path required"}'
        return 1
    fi

    # 验证文件存在
    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        echo '{"error": "file not found", "path": "'"$file_path"'"}'
        return 1
    fi

    # 快速路径：检查缓存是否有效（跳过所有其他检查）
    # 内联 cache_path 计算以避免子进程开销
    # 使用 "源文件不比缓存新" 而非 "缓存比源文件新" 以处理同秒创建的情况
    local cache_file="$AST_CACHE_DIR/${file_path//\//_}.ast"
    if [[ "$force_rebuild" != "true" ]] && [[ -f "$cache_file" ]] && ! [[ "$file_path" -nt "$cache_file" ]]; then
        # 快速版本检查：确保缓存版本与数据库一致
        local cache_version_ok=true
        if [[ -f "$VERSION_STAMP_FILE" ]] && [[ -f "$GRAPH_DB_PATH" ]]; then
            local cache_ts db_ts
            cache_ts=$(grep -o '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' "$VERSION_STAMP_FILE" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            db_ts=$(sqlite3 "$GRAPH_DB_PATH" "SELECT value FROM metadata WHERE key = 'ast_cache_version';" 2>/dev/null || echo "")
            if [[ -n "$db_ts" ]] && [[ "$cache_ts" != "$db_ts" ]]; then
                cache_version_ok=false
            fi
        fi

        if [[ "$cache_version_ok" == "true" ]]; then
            # 缓存有效，直接返回
            echo "{\"status\":\"success\",\"mode\":\"cache_hit\",\"state\":\"CACHE_HIT\",\"file\":\"$file_path\"}"
            return 0
        fi
    fi

    ensure_dirs
    cleanup_orphan_temp_files

    # 确定状态
    local state
    if [[ "$force_rebuild" == "true" ]]; then
        state="$STATE_FULL_REBUILD"
    else
        state=$(determine_state 1)
    fi

    log_info "State: $state for file: $file_path"

    local ast_json=""
    local status="success"
    local mode=""

    case "$state" in
        "$STATE_INCREMENTAL")
            mode="incremental"
            # 检查缓存是否有效（源文件不比缓存新）
            local cache_file
            cache_file=$(get_cache_path "$file_path")
            if [[ -f "$cache_file" ]] && ! [[ "$file_path" -nt "$cache_file" ]]; then
                # 缓存有效，直接使用缓存
                mode="cache_hit"
                ast_json=$(cat "$cache_file")
            else
                # 使用 tree-sitter 解析
                ast_json=$(parse_file_with_node "$file_path" 2>/dev/null) || true
                if [[ -z "$ast_json" || "$ast_json" == *'"error"'* ]]; then
                    log_warn "Parse failed, falling back to regex"
                    ast_json=$(parse_file_with_regex "$file_path")
                    mode="fallback"
                fi
            fi
            ;;

        "$STATE_FULL_REBUILD")
            mode="full_rebuild"
            log_info "FULL_REBUILD: cache invalidated or missing"
            # 清理旧缓存
            rm -rf "${AST_CACHE_DIR:?}"/*
            # 解析文件
            ast_json=$(parse_file_with_node "$file_path" 2>/dev/null) || true
            if [[ -z "$ast_json" || "$ast_json" == *'"error"'* ]]; then
                ast_json=$(parse_file_with_regex "$file_path")
                mode="full_rebuild_fallback"
            fi
            ;;

        "$STATE_FALLBACK")
            mode="fallback"
            # 检查缓存是否有效（源文件不比缓存新）
            local cache_file_fb
            cache_file_fb=$(get_cache_path "$file_path")
            if [[ -f "$cache_file_fb" ]] && ! [[ "$file_path" -nt "$cache_file_fb" ]]; then
                # 缓存有效，直接使用缓存
                mode="cache_hit"
                ast_json=$(cat "$cache_file_fb")
            else
                log_warn "tree-sitter unavailable, using fallback mode"
                ast_json=$(parse_file_with_regex "$file_path")
            fi
            ;;
    esac

    # 跳过写入操作如果是缓存命中
    if [[ "$mode" != "cache_hit" ]]; then
        # 写入缓存
        if [[ -n "$ast_json" ]]; then
            atomic_write_cache "$file_path" "$ast_json"
        fi

        # 更新图数据库
        update_graph_db "$file_path" "$ast_json"

        # 更新版本戳
        local new_stamp
        new_stamp=$(generate_version_stamp)
        write_version_stamp "$new_stamp"

        # 同步到数据库
        local timestamp
        timestamp=$(echo "$new_stamp" | grep -o '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        set_db_version_stamp "$timestamp" 2>/dev/null || true
    fi

    echo "{\"status\":\"$status\",\"mode\":\"$mode\",\"state\":\"$state\",\"file\":\"$file_path\"}"
}

# ==================== 命令: batch ====================

cmd_batch() {
    local since=""
    local files=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since)
                since="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    ensure_dirs
    cleanup_orphan_temp_files

    # 获取变更文件列表
    if [[ -n "$since" ]]; then
        # 使用 git diff 获取变更文件
        if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    files+=("$file")
                fi
            done < <(git diff --name-only "$since" 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|mts|mjs)$' || true)
        fi
    else
        # 获取所有 TypeScript/JavaScript 文件
        while IFS= read -r file; do
            files+=("$file")
        done < <(find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
            -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" 2>/dev/null || true)
    fi

    local file_count=${#files[@]}

    if [[ $file_count -eq 0 ]]; then
        log_info "No files to update"
        echo '{"status":"success","files_processed":0}'
        return 0
    fi

    log_info "Found $file_count files to process"

    # 确定状态
    local state
    state=$(determine_state "$file_count")

    log_info "Batch state: $state (threshold: $AST_DELTA_BATCH_THRESHOLD)"

    local processed=0
    local failed=0
    local mode=""

    case "$state" in
        "$STATE_INCREMENTAL")
            mode="incremental"
            for file in "${files[@]}"; do
                if cmd_update "$file" >/dev/null 2>&1; then
                    ((processed++))
                else
                    ((failed++))
                fi
            done
            ;;

        "$STATE_FULL_REBUILD")
            mode="full_rebuild"
            log_info "FULL_REBUILD: too many files ($file_count > $AST_DELTA_BATCH_THRESHOLD)"

            # 清理缓存
            rm -rf "${AST_CACHE_DIR:?}"/*

            # 如果有 scip-to-graph.sh，使用它进行全量重建
            if [[ -x "$SCRIPT_DIR/scip-to-graph.sh" ]]; then
                log_info "Using scip-to-graph.sh for full rebuild"
                "$SCRIPT_DIR/scip-to-graph.sh" 2>/dev/null || true
            fi

            # 然后处理每个文件
            for file in "${files[@]}"; do
                if cmd_update "$file" >/dev/null 2>&1; then
                    ((processed++))
                else
                    ((failed++))
                fi
            done
            ;;

        "$STATE_FALLBACK")
            mode="fallback"
            log_warn "tree-sitter unavailable, using SCIP fallback"

            # 尝试使用 scip-to-graph.sh
            if [[ -x "$SCRIPT_DIR/scip-to-graph.sh" ]]; then
                "$SCRIPT_DIR/scip-to-graph.sh" 2>/dev/null || true
            fi

            for file in "${files[@]}"; do
                if cmd_update "$file" >/dev/null 2>&1; then
                    ((processed++))
                else
                    ((failed++))
                fi
            done
            ;;
    esac

    # 更新版本戳
    local new_stamp
    new_stamp=$(generate_version_stamp)
    write_version_stamp "$new_stamp"

    echo "{\"status\":\"success\",\"mode\":\"$mode\",\"state\":\"$state\",\"files_processed\":$processed,\"files_failed\":$failed}"
}

# ==================== 命令: status ====================

cmd_status() {
    ensure_dirs

    local tree_sitter_available="false"
    if check_tree_sitter_available; then
        tree_sitter_available="true"
    fi

    local cache_file_count
    cache_file_count=$(find "$AST_CACHE_DIR" -name "*.ast" 2>/dev/null | wc -l | tr -d ' ')

    local cache_size_kb
    cache_size_kb=$(du -sk "$AST_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")

    local version_stamp
    version_stamp=$(read_version_stamp)

    local db_version
    db_version=$(get_db_version_stamp)

    local db_exists="false"
    if [[ -f "$GRAPH_DB_PATH" ]]; then
        db_exists="true"
    fi

    cat << EOF
{
    "tree_sitter_available": $tree_sitter_available,
    "cache_dir": "$AST_CACHE_DIR",
    "cache_file_count": $cache_file_count,
    "cache_size_kb": $cache_size_kb,
    "cache_max_size_mb": $AST_CACHE_MAX_SIZE_MB,
    "batch_threshold": $AST_DELTA_BATCH_THRESHOLD,
    "version_stamp": $version_stamp,
    "db_version": "$db_version",
    "db_exists": $db_exists,
    "db_path": "$GRAPH_DB_PATH"
}
EOF
}

# ==================== 命令: clear-cache ====================

cmd_clear_cache() {
    ensure_dirs

    log_info "Clearing AST cache..."

    local file_count
    file_count=$(find "$AST_CACHE_DIR" -name "*.ast" 2>/dev/null | wc -l | tr -d ' ')

    rm -rf "$AST_CACHE_DIR"/*

    # 重置版本戳
    rm -f "$VERSION_STAMP_FILE"

    log_ok "Cleared $file_count cache files"
    echo "{\"status\":\"ok\",\"files_cleared\":$file_count}"
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
ast-delta.sh - AST Delta 增量索引

Usage / 用法:
    ast-delta.sh <command> [options]

命令:
    update <file-path>     单文件增量更新
    batch [--since <ref>]  批量增量更新
    status                 显示索引状态
    clear-cache            清理 AST 缓存

update 选项:
    --force-rebuild        强制执行全量重建

batch 选项:
    --since <ref>          Git 引用（如 HEAD~1, main）

环境变量:
    GRAPH_DB_PATH          图数据库路径（默认: .devbooks/graph.db）
    AST_CACHE_DIR          AST 缓存目录（默认: .devbooks/ast-cache）
    AST_DELTA_BATCH_THRESHOLD  触发全量重建的文件数阈值（默认: 10）
    DISABLE_TREE_SITTER    禁用 tree-sitter（用于测试）
    FORCE_SCIP_FALLBACK    强制使用 SCIP/regex 降级

状态机:
    IDLE → CHECK → INCREMENTAL/FULL_REBUILD/FALLBACK → CLEANUP

决策条件:
    条件 A（增量更新）：tree-sitter 可用 ∧ 缓存存在 ∧ 版本一致 ∧ 文件数 ≤ 阈值
    条件 B（全量重建）：缓存不存在 ∨ 版本不一致 ∨ 文件数 > 阈值
    条件 C（降级模式）：tree-sitter 不可用

示例:
    # 单文件更新
    ast-delta.sh update src/index.ts

    # 批量更新（自上次提交以来）
    ast-delta.sh batch --since HEAD~1

    # 查看状态
    ast-delta.sh status

    # 清理缓存
    ast-delta.sh clear-cache
EOF
}

# ==================== 主入口 ====================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        update)
            cmd_update "$@"
            ;;
        batch)
            cmd_batch "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        clear-cache)
            cmd_clear_cache "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# 仅在直接执行时运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
