#!/bin/bash
# DevBooks 后台索引守护进程
# 监听文件变化，自动触发增量或全量索引
#
# optimize-indexing-pipeline: AC-001, AC-002, AC-006, AC-007, AC-008
#
# 调度策略：
#   1. 优先增量（AST Delta）路径
#   2. 条件不满足时回退全量重建
#   3. 防抖窗口聚合多次变更

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀
export LOG_PREFIX="indexer"

# ==================== 配置（优先环境变量，次配置文件，最后默认值）====================

# 配置文件路径
CONFIG_FILE="${CONFIG_DIR:-$SCRIPT_DIR/../config}/features.yaml"

# 从配置文件读取值的辅助函数
read_indexer_config() {
    local key="$1"
    local default="$2"

    # 首先检查环境变量（优先级最高）
    case "$key" in
        "debounce_seconds")
            [[ -n "${DEBOUNCE_SECONDS:-}" ]] && { echo "$DEBOUNCE_SECONDS"; return; } ;;
        "ast_delta_enabled")
            [[ -n "${CI_AST_DELTA_ENABLED:-}" ]] && { echo "$CI_AST_DELTA_ENABLED"; return; } ;;
        "file_threshold")
            [[ -n "${CI_FILE_THRESHOLD:-}" ]] && { echo "$CI_FILE_THRESHOLD"; return; } ;;
    esac

    # 然后从配置文件读取
    if [[ -f "$CONFIG_FILE" ]]; then
        local value
        case "$key" in
            "debounce_seconds")
                value=$(awk '/^[[:space:]]*indexer:/{found=1} found && /debounce_seconds:/{gsub(/.*:/,""); gsub(/[[:space:]]/,""); print; exit}' "$CONFIG_FILE" 2>/dev/null)
                ;;
            "ast_delta_enabled")
                value=$(awk '/^[[:space:]]*ast_delta:/{found=1} found && /enabled:/{gsub(/.*:/,""); gsub(/[[:space:]]/,""); print; exit}' "$CONFIG_FILE" 2>/dev/null)
                ;;
            "file_threshold")
                value=$(awk '/^[[:space:]]*ast_delta:/{found=1} found && /file_threshold:/{gsub(/.*:/,""); gsub(/[[:space:]]/,""); print; exit}' "$CONFIG_FILE" 2>/dev/null)
                ;;
        esac
        [[ -n "$value" ]] && { echo "$value"; return; }
    fi

    echo "$default"
}

# 配置变量
DEBOUNCE_SECONDS=$(read_indexer_config "debounce_seconds" "2")
AST_DELTA_ENABLED=$(read_indexer_config "ast_delta_enabled" "true")
FILE_THRESHOLD=$(read_indexer_config "file_threshold" "10")
INDEX_INTERVAL="${INDEX_INTERVAL:-300}"
WATCH_EXTENSIONS="ts,tsx,js,jsx,py,go,rs,java"
IGNORE_PATTERNS="node_modules|dist|build|\.git|__pycache__|\.lock"

# 版本戳文件路径
VERSION_STAMP_FILE="${DEVBOOKS_DIR:-.devbooks}/version-stamp"

# ==================== 调度核心 (AC-001, AC-002) ====================

# 检查 tree-sitter 是否可用
tree_sitter_available() {
    # 检查 ast-delta.sh 脚本是否存在且可执行
    if [[ -x "$SCRIPT_DIR/ast-delta.sh" ]]; then
        # 调用 ast-delta.sh status 检查
        if "$SCRIPT_DIR/ast-delta.sh" status --format json 2>/dev/null | grep -q '"status"'; then
            return 0
        fi
    fi
    return 1
}

# 读取版本戳
read_version_stamp() {
    local stamp_file="$1"
    if [[ -f "$stamp_file" ]]; then
        cat "$stamp_file" 2>/dev/null
    else
        echo ""
    fi
}

# 写入版本戳
write_version_stamp() {
    local stamp_file="$1"
    local value="$2"
    mkdir -p "$(dirname "$stamp_file")"
    echo "$value" > "$stamp_file"
}

# 获取数据库版本戳（基于修改时间）
get_db_version() {
    local db_path="${GRAPH_DB_PATH:-.devbooks/graph.db}"
    if [[ -f "$db_path" ]]; then
        stat -f "%m" "$db_path" 2>/dev/null || stat -c "%Y" "$db_path" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# 清理 AST 缓存（版本戳不一致时调用）
clear_ast_cache() {
    local cache_dir="${DEVBOOKS_DIR:-.devbooks}/ast-cache"
    if [[ -d "$cache_dir" ]]; then
        rm -rf "$cache_dir"/*
        log_info "AST 缓存已清理"
    fi
}

# 调度决策函数 (AC-001)
# 输入: changed_files 数组（全局变量）
# 输出: JSON 格式决策结果到 stdout
# 副作用: 设置 DISPATCH_DECISION, DISPATCH_REASON 全局变量
dispatch_index() {
    local -a changed_files=("$@")
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 初始化全局变量
    DISPATCH_DECISION=""
    DISPATCH_REASON=""

    # 条件 1: 无变更文件
    if [[ ${#changed_files[@]} -eq 0 ]]; then
        DISPATCH_DECISION="SKIP"
        DISPATCH_REASON="no_changes"
        output_decision "$DISPATCH_DECISION" "$DISPATCH_REASON" "$timestamp"
        return 0
    fi

    # 条件 2: 功能开关禁用
    if [[ "$AST_DELTA_ENABLED" != "true" ]]; then
        DISPATCH_DECISION="FULL_REBUILD"
        DISPATCH_REASON="feature_disabled"
        output_decision "$DISPATCH_DECISION" "$DISPATCH_REASON" "$timestamp" "${changed_files[@]}"
        return 0
    fi

    # 条件 3: tree-sitter 不可用
    if ! tree_sitter_available; then
        DISPATCH_DECISION="FULL_REBUILD"
        DISPATCH_REASON="tree_sitter_unavailable"
        output_decision "$DISPATCH_DECISION" "$DISPATCH_REASON" "$timestamp" "${changed_files[@]}"
        return 0
    fi

    # 条件 4: 版本戳不一致 (AC-008)
    local cache_version db_version
    cache_version=$(read_version_stamp "$VERSION_STAMP_FILE")
    db_version=$(get_db_version)

    if [[ -n "$cache_version" && -n "$db_version" && "$cache_version" != "$db_version" ]]; then
        clear_ast_cache
        DISPATCH_DECISION="FULL_REBUILD"
        DISPATCH_REASON="cache_version_mismatch"
        output_decision "$DISPATCH_DECISION" "$DISPATCH_REASON" "$timestamp" "${changed_files[@]}"
        return 0
    fi

    # 条件 5: 文件数超阈值
    if [[ ${#changed_files[@]} -gt $FILE_THRESHOLD ]]; then
        DISPATCH_DECISION="FULL_REBUILD"
        DISPATCH_REASON="file_count_exceeds_threshold"
        output_decision "$DISPATCH_DECISION" "$DISPATCH_REASON" "$timestamp" "${changed_files[@]}"
        return 0
    fi

    # 所有条件满足，走增量路径
    DISPATCH_DECISION="INCREMENTAL"
    DISPATCH_REASON="all_conditions_met"
    output_decision "$DISPATCH_DECISION" "$DISPATCH_REASON" "$timestamp" "${changed_files[@]}"
    return 0
}

# 输出决策 JSON
output_decision() {
    local decision="$1"
    local reason="$2"
    local timestamp="$3"
    shift 3
    local -a files=("$@")

    # 构建 JSON
    local files_json="[]"
    if [[ ${#files[@]} -gt 0 ]]; then
        files_json=$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .)
    fi

    jq -n \
        --arg decision "$decision" \
        --arg reason "$reason" \
        --arg timestamp "$timestamp" \
        --argjson changed_files "$files_json" \
        '{
            decision: $decision,
            reason: $reason,
            changed_files: $changed_files,
            timestamp: $timestamp
        }'
}

# ==================== 索引执行路径 ====================

# 增量路径执行 (AC-001)
execute_incremental() {
    local -a files=("$@")

    log_info "执行增量索引: ${#files[@]} 个文件"

    if [[ ${#files[@]} -eq 1 ]]; then
        # 单文件更新
        "$SCRIPT_DIR/ast-delta.sh" update "${files[0]}" 2>&1
    else
        # 批量更新
        local files_csv
        files_csv=$(IFS=','; echo "${files[*]}")
        "$SCRIPT_DIR/ast-delta.sh" batch --files "$files_csv" 2>&1
    fi

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_ok "增量索引完成"
    else
        log_warn "增量索引失败，回退到全量重建"
        execute_full_rebuild
    fi

    return $exit_code
}

# 全量重建路径 (AC-002)
execute_full_rebuild() {
    local dir="${PROJECT_DIR:-$(pwd)}"

    log_info "执行全量重建..."

    # 步骤 1: 生成 SCIP 索引
    local lang
    lang=$(detect_language "$dir")
    local cmd
    cmd=$(get_index_command "$lang")

    if [[ -z "$cmd" ]]; then
        log_error "无法为 $lang 项目生成索引（索引器未安装）"
        return 1
    fi

    local start_time
    start_time=$(date +%s)

    # 使用 bash -c 而不是 eval，更安全
    if ! (cd "$dir" && bash -c "$cmd" 2>/dev/null); then
        log_error "SCIP 索引生成失败"
        return 1
    fi

    # 步骤 2: 同步到图数据库
    if ! "$SCRIPT_DIR/scip-to-graph.sh" parse --incremental --format json 2>&1; then
        log_error "图数据同步失败"
        return 1
    fi

    # 步骤 3: 更新版本戳 (AC-008)
    local new_version
    new_version=$(get_db_version)
    write_version_stamp "$VERSION_STAMP_FILE" "$new_version"

    # 步骤 4: 清理 AST 缓存
    clear_ast_cache

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_ok "全量重建完成 (${duration}s)"
    return 0
}

# ==================== 防抖窗口聚合 (AC-007) ====================

# 全局变量用于防抖
PENDING_FILES=()
LAST_CHANGE_TIME=0
DEBOUNCE_TIMER_PID=""

# 添加文件到待处理列表
add_pending_file() {
    local file="$1"

    # 避免重复
    for f in "${PENDING_FILES[@]}"; do
        [[ "$f" == "$file" ]] && return
    done

    PENDING_FILES+=("$file")
    LAST_CHANGE_TIME=$(date +%s)
}

# 触发防抖定时器
trigger_debounce() {
    # 如果已有定时器在运行，不重复触发
    if [[ -n "$DEBOUNCE_TIMER_PID" ]] && kill -0 "$DEBOUNCE_TIMER_PID" 2>/dev/null; then
        return
    fi

    (
        sleep "$DEBOUNCE_SECONDS"

        # 检查是否在等待期间有新变更
        local now
        now=$(date +%s)
        local since_last=$((now - LAST_CHANGE_TIME))

        if [[ $since_last -ge $DEBOUNCE_SECONDS ]]; then
            # 触发索引
            dispatch_and_execute
        fi
    ) &
    DEBOUNCE_TIMER_PID=$!
}

# 调度并执行
dispatch_and_execute() {
    if [[ ${#PENDING_FILES[@]} -eq 0 ]]; then
        return
    fi

    # 调度决策
    dispatch_index "${PENDING_FILES[@]}"

    # 执行
    case "$DISPATCH_DECISION" in
        INCREMENTAL)
            execute_incremental "${PENDING_FILES[@]}"
            ;;
        FULL_REBUILD)
            execute_full_rebuild
            ;;
        SKIP)
            log_info "跳过索引（无变更）"
            ;;
    esac

    # 清空待处理列表
    PENDING_FILES=()
}

# ==================== 辅助函数 ====================

# 检测项目语言
detect_language() {
    local dir="$1"
    if [[ -f "$dir/tsconfig.json" ]] || [[ -f "$dir/package.json" ]]; then
        echo "typescript"
    elif [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/setup.py" ]] || [[ -f "$dir/requirements.txt" ]]; then
        echo "python"
    elif [[ -f "$dir/go.mod" ]]; then
        echo "go"
    elif [[ -f "$dir/Cargo.toml" ]]; then
        echo "rust"
    else
        echo "unknown"
    fi
}

# 获取索引命令
get_index_command() {
    local lang="$1"
    case "$lang" in
        typescript)
            if command -v scip-typescript &>/dev/null; then
                echo "scip-typescript index --output index.scip"
            else
                echo ""
            fi
            ;;
        python)
            if command -v scip-python &>/dev/null; then
                echo "scip-python index . --output index.scip"
            else
                echo ""
            fi
            ;;
        go)
            if command -v scip-go &>/dev/null; then
                echo "scip-go --output index.scip"
            else
                echo ""
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# 执行索引（保持向后兼容）
do_index() {
    local dir="$1"
    execute_full_rebuild
}

# 检查文件监听工具
check_watcher() {
    if command -v fswatch &>/dev/null; then
        echo "fswatch"
    elif command -v inotifywait &>/dev/null; then
        echo "inotifywait"
    else
        echo ""
    fi
}

# ==================== 监听模式 ====================

# 使用 fswatch 监听（macOS）
watch_with_fswatch() {
    local dir="$1"
    local last_index=0

    log_info "使用 fswatch 监听文件变化..."

    fswatch -r -e "$IGNORE_PATTERNS" \
        --include "\\.($WATCH_EXTENSIONS)$" \
        "$dir" | while read -r changed_file; do

        local now
        now=$(date +%s)
        local since_last=$((now - last_index))

        # 最小间隔检查
        if [[ $since_last -lt $INDEX_INTERVAL ]]; then
            continue
        fi

        log_info "检测到变化: $(basename "$changed_file")"
        add_pending_file "$changed_file"
        trigger_debounce

        if [[ "$DISPATCH_DECISION" != "SKIP" ]]; then
            last_index=$(date +%s)
        fi
    done
}

# 使用 inotifywait 监听（Linux）
watch_with_inotify() {
    local dir="$1"
    local last_index=0

    log_info "使用 inotifywait 监听文件变化..."

    inotifywait -r -m -e modify,create,delete \
        --exclude "$IGNORE_PATTERNS" \
        "$dir" | while read -r path action file; do

        # 检查文件扩展名
        if ! echo "$file" | grep -qE "\.($WATCH_EXTENSIONS)$"; then
            continue
        fi

        local now
        now=$(date +%s)
        local since_last=$((now - last_index))

        if [[ $since_last -lt $INDEX_INTERVAL ]]; then
            continue
        fi

        log_info "检测到变化: $file ($action)"
        add_pending_file "$path$file"
        trigger_debounce

        if [[ "$DISPATCH_DECISION" != "SKIP" ]]; then
            last_index=$(date +%s)
        fi
    done
}

# 轮询模式（无监听工具时的降级方案）
watch_with_polling() {
    local dir="$1"
    local poll_interval=${INDEX_INTERVAL:-300}

    log_warn "未找到文件监听工具，使用轮询模式（每 ${poll_interval}s）"

    while true; do
        local index_file="$dir/index.scip"

        if [[ ! -f "$index_file" ]]; then
            execute_full_rebuild
        else
            # 检查是否有比索引更新的文件
            local newer_files
            newer_files=$(find "$dir" \
                -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.py" -o -name "*.go" \) \
                -newer "$index_file" \
                ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/.git/*" \
                2>/dev/null | head -20)

            if [[ -n "$newer_files" ]]; then
                log_info "发现更新的文件，触发索引..."

                # 将文件列表转换为数组
                local -a files_array
                while IFS= read -r f; do
                    [[ -n "$f" ]] && files_array+=("$f")
                done <<< "$newer_files"

                # 调度并执行
                dispatch_index "${files_array[@]}"

                case "$DISPATCH_DECISION" in
                    INCREMENTAL)
                        execute_incremental "${files_array[@]}"
                        ;;
                    FULL_REBUILD)
                        execute_full_rebuild
                        ;;
                esac
            fi
        fi

        sleep "$poll_interval"
    done
}

# ==================== CLI 命令 (AC-004) ====================

# 状态命令
cmd_status() {
    local format="${1:-text}"

    # 获取配置状态
    local config_status
    config_status=$(jq -n \
        --arg ast_delta_enabled "$AST_DELTA_ENABLED" \
        --arg file_threshold "$FILE_THRESHOLD" \
        --arg debounce_seconds "$DEBOUNCE_SECONDS" \
        '{
            ast_delta_enabled: ($ast_delta_enabled == "true"),
            file_threshold: ($file_threshold | tonumber),
            debounce_seconds: ($debounce_seconds | tonumber)
        }')

    # 检查进程状态
    local daemon_running=false
    if launchctl list 2>/dev/null | grep -q "com.devbooks.indexer"; then
        daemon_running=true
    fi

    # 检查版本戳
    local cache_version db_version version_match
    cache_version=$(read_version_stamp "$VERSION_STAMP_FILE")
    db_version=$(get_db_version)
    if [[ -n "$cache_version" && "$cache_version" == "$db_version" ]]; then
        version_match=true
    elif [[ -z "$cache_version" && -z "$db_version" ]]; then
        version_match=true
    else
        version_match=false
    fi

    if [[ "$format" == "json" ]]; then
        jq -n \
            --argjson config "$config_status" \
            --argjson daemon_running "$daemon_running" \
            --argjson version_match "$version_match" \
            --arg cache_version "${cache_version:-null}" \
            --arg db_version "${db_version:-null}" \
            '{
                config: $config,
                daemon_running: $daemon_running,
                version_stamp: {
                    cache: $cache_version,
                    database: $db_version,
                    match: $version_match
                }
            }'
    else
        log_info "索引器状态 (Indexer status)"
        echo ""
        echo "  配置 (Config):"
        echo "    ast_delta.enabled: $AST_DELTA_ENABLED"
        echo "    ast_delta.file_threshold: $FILE_THRESHOLD"
        echo "    indexer.debounce_seconds: $DEBOUNCE_SECONDS"
        echo ""
        echo "  守护进程 (daemon): $([ "$daemon_running" = true ] && echo "running 运行中" || echo "not running 未运行")"
        echo ""
        echo "  版本戳 (Version stamp):"
        echo "    缓存: ${cache_version:-未设置}"
        echo "    数据库: ${db_version:-未设置}"
        echo "    一致性: $([ "$version_match" = true ] && echo "一致" || echo "不一致")"
    fi
}

# Dry-run 模式 (AC-004)
cmd_dry_run() {
    local files_csv="$1"

    if [[ -z "$files_csv" ]]; then
        log_error "需要指定文件列表: --dry-run --files <file1,file2,...>"
        exit 1
    fi

    # 解析文件列表
    local -a files
    IFS=',' read -ra files <<< "$files_csv"

    # Dry-run 只输出 JSON，不输出日志
    # 执行调度决策（但不实际执行）
    dispatch_index "${files[@]}"
}

# Once 模式 (AC-004)
cmd_once() {
    local files_csv="$1"

    if [[ -z "$files_csv" ]]; then
        log_error "需要指定文件列表: --once --files <file1,file2,...>"
        exit 1
    fi

    # 解析文件列表
    local -a files
    IFS=',' read -ra files <<< "$files_csv"

    log_info "一次性执行模式: ${#files[@]} 个文件"

    # 调度并执行
    dispatch_index "${files[@]}"

    case "$DISPATCH_DECISION" in
        INCREMENTAL)
            execute_incremental "${files[@]}"
            ;;
        FULL_REBUILD)
            execute_full_rebuild
            ;;
        SKIP)
            log_info "无需索引"
            ;;
    esac
}

# ==================== 主函数 ====================

main() {
    local project_dir="${1:-$(pwd)}"
    PROJECT_DIR="$project_dir"

    if [[ ! -d "$project_dir" ]]; then
        log_error "目录不存在: $project_dir"
        exit 1
    fi

    log_info "DevBooks 后台索引守护进程启动"
    log_info "项目目录: $project_dir"
    log_info "配置: AST Delta=${AST_DELTA_ENABLED}, 阈值=${FILE_THRESHOLD}, 防抖=${DEBOUNCE_SECONDS}s"

    local lang
    lang=$(detect_language "$project_dir")
    log_info "检测到语言: $lang"

    # 首次索引
    if [[ ! -f "$project_dir/index.scip" ]]; then
        log_info "首次运行，生成初始索引..."
        execute_full_rebuild
    else
        log_ok "索引已存在，跳过初始索引"
    fi

    # 选择监听方式
    local watcher
    watcher=$(check_watcher)

    case "$watcher" in
        fswatch)
            watch_with_fswatch "$project_dir"
            ;;
        inotifywait)
            watch_with_inotify "$project_dir"
            ;;
        *)
            watch_with_polling "$project_dir"
            ;;
    esac
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
DevBooks 后台索引守护进程

用法:
  indexer.sh [项目目录]                      启动守护进程
  indexer.sh --status [--format json]        检查状态
  indexer.sh --dry-run --files <files>       模拟调度决策（不执行）
  indexer.sh --once --files <files>          一次性执行索引
  indexer.sh --install [项目目录]            安装为 LaunchAgent (macOS)
  indexer.sh --uninstall                     卸载 LaunchAgent
  indexer.sh --help                          显示帮助

调度策略:
  1. 功能开关检查（CI_AST_DELTA_ENABLED 或 features.ast_delta.enabled）
  2. tree-sitter 可用性检查
  3. 版本戳一致性检查（缓存 vs 数据库）
  4. 文件数阈值检查（超过阈值回退全量）

环境变量:
  DEBOUNCE_SECONDS       防抖时间（默认从配置读取或 2s）
  INDEX_INTERVAL         最小索引间隔（默认 300s）
  CI_AST_DELTA_ENABLED   功能开关（覆盖配置文件）
  CI_FILE_THRESHOLD      文件数阈值（覆盖配置文件）

配置文件:
  config/features.yaml   功能开关和参数配置

依赖:
  - fswatch (macOS) 或 inotifywait (Linux) 用于文件监听
  - scip-typescript / scip-python / scip-go 用于生成索引
  - ast-delta.sh 用于增量索引

EOF
}

# 安装为 LaunchAgent (macOS)
install_launchagent() {
    local plist_path="$HOME/Library/LaunchAgents/com.devbooks.indexer.plist"
    local script_path
    script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    local project_dir="${1:-$(pwd)}"

    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.devbooks.indexer</string>
    <key>ProgramArguments</key>
    <array>
        <string>$script_path</string>
        <string>$project_dir</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/devbooks-indexer.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/devbooks-indexer.log</string>
</dict>
</plist>
EOF

    launchctl load "$plist_path"
    log_ok "LaunchAgent 已安装并启动"
    log_info "日志: /tmp/devbooks-indexer.log"
}

# ==================== 参数解析 ====================

# 解析参数
FILES_ARG=""
FORMAT_ARG="text"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --status)
            shift
            # 检查是否有 --format 参数
            if [[ "${1:-}" == "--format" ]]; then
                FORMAT_ARG="${2:-text}"
                shift 2 || true
            fi
            cmd_status "$FORMAT_ARG"
            exit 0
            ;;
        --dry-run)
            shift
            if [[ "${1:-}" == "--files" ]]; then
                FILES_ARG="${2:-}"
                shift 2 || true
            fi
            cmd_dry_run "$FILES_ARG"
            exit 0
            ;;
        --once)
            shift
            if [[ "${1:-}" == "--files" ]]; then
                FILES_ARG="${2:-}"
                shift 2 || true
            fi
            cmd_once "$FILES_ARG"
            exit 0
            ;;
        --files)
            FILES_ARG="${2:-}"
            shift 2 || true
            ;;
        --format)
            FORMAT_ARG="${2:-text}"
            shift 2 || true
            ;;
        --install)
            install_launchagent "${2:-$(pwd)}"
            exit 0
            ;;
        --uninstall)
            launchctl unload "$HOME/Library/LaunchAgents/com.devbooks.indexer.plist" 2>/dev/null || true
            rm -f "$HOME/Library/LaunchAgents/com.devbooks.indexer.plist"
            log_ok "LaunchAgent 已卸载"
            exit 0
            ;;
        *)
            main "$1"
            exit 0
            ;;
    esac
done

# 如果没有参数，启动守护进程
main "$(pwd)"
