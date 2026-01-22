#!/bin/bash
# vuln-tracker.sh - 安全漏洞基础追踪模块
# 版本: 1.0
# 用途: 集成 npm audit 进行依赖漏洞扫描，追踪漏洞的依赖传播路径
#
# 覆盖 M7: 安全漏洞基础追踪
# AC-F07: npm audit 输出正确解析
# AC-F10: 漏洞严重性阈值过滤正确
#
# 环境变量:
#   VULN_SEVERITY_THRESHOLD - 最低严重性（默认 moderate）
#   VULN_INCLUDE_DEV - 是否包含开发依赖（默认 false）
#   FEATURES_CONFIG - 功能开关配置文件路径

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀（被 common.sh 的日志函数使用）
# shellcheck disable=SC2034
export LOG_PREFIX="vuln-tracker"

# ==================== 配置 ====================

# 严重性等级顺序（低到高）
SEVERITY_ORDER=("low" "moderate" "high" "critical")

# 默认配置
: "${VULN_SEVERITY_THRESHOLD:=moderate}"
: "${VULN_INCLUDE_DEV:=false}"
: "${FEATURES_CONFIG:=config/features.yaml}"

# ==================== 辅助函数 ====================

# 检测 npm audit 格式版本
# npm 7+ 使用新格式 (.vulnerabilities)
# npm 6.x 使用旧格式 (.advisories)
detect_npm_audit_format() {
    local npm_version
    npm_version=$(npm --version 2>/dev/null || echo "0.0.0")
    local major_version
    major_version=$(echo "$npm_version" | cut -d. -f1)

    if [[ $major_version -ge 7 ]]; then
        echo "npm7"
    else
        echo "npm6"
    fi
}

# 获取严重性等级的数字索引
# 用于比较严重性
get_severity_index() {
    local severity="$1"
    local index=0
    for s in "${SEVERITY_ORDER[@]}"; do
        if [[ "$s" == "$severity" ]]; then
            echo "$index"
            return 0
        fi
        ((index++))
    done
    # 未知严重性，返回 -1
    echo "-1"
}

# 检查严重性是否满足阈值
# 返回 0 表示满足（严重性 >= 阈值），1 表示不满足
severity_meets_threshold() {
    local severity="$1"
    local threshold="$2"

    local sev_index thr_index
    sev_index=$(get_severity_index "$severity")
    thr_index=$(get_severity_index "$threshold")

    if [[ "$sev_index" -ge "$thr_index" ]]; then
        return 0
    fi
    return 1
}

# 获取严重性徽章（用于 Markdown 输出）
get_severity_badge() {
    local severity="$1"
    case "$severity" in
        critical) echo "🔴 critical" ;;
        high)     echo "🟠 high" ;;
        moderate) echo "🟡 moderate" ;;
        low)      echo "🟢 low" ;;
        *)        echo "$severity" ;;
    esac
}

# 获取当前 ISO 8601 时间戳
get_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ==================== npm 7+ 格式解析 ====================

# 解析 npm 7+ audit JSON 格式
# 输入: JSON 字符串
# 输出: 统一的漏洞数组 JSON
parse_npm7_format() {
    local json="$1"
    local threshold="${2:-moderate}"
    local include_dev="${3:-false}"

    check_dependencies jq || return "$EXIT_DEPS_MISSING"

    # 提取并过滤漏洞
    echo "$json" | jq --arg threshold "$threshold" --arg include_dev "$include_dev" '
        # 定义严重性排序
        def severity_order:
            {"low": 0, "moderate": 1, "high": 2, "critical": 3};

        # 获取严重性索引
        def severity_index(s):
            severity_order[s] // -1;

        # 检查严重性是否满足阈值
        def meets_threshold(sev; thr):
            severity_index(sev) >= severity_index(thr);

        # 处理 vulnerabilities 对象
        (.vulnerabilities // {}) | to_entries | map(
            select(
                # 过滤严重性
                meets_threshold(.value.severity; $threshold) and
                # 过滤开发依赖（如果不包含）
                (if $include_dev == "true" then true else (.value.dev // false) == false end)
            ) |
            {
                name: .key,
                severity: .value.severity,
                via: (
                    if (.value.via | type) == "array" then
                        .value.via | map(
                            if type == "string" then . else .title // .name // "Unknown" end
                        )
                    else
                        [.value.via // "Unknown"]
                    end
                ),
                effects: (.value.effects // []),
                fixAvailable: (.value.fixAvailable // false),
                isDirect: (.value.isDirect // false)
            }
        )
    ' 2>/dev/null
}

# ==================== npm 6.x 格式解析 ====================

# 解析 npm 6.x audit JSON 格式
# 输入: JSON 字符串
# 输出: 统一的漏洞数组 JSON
parse_npm6_format() {
    local json="$1"
    local threshold="${2:-moderate}"
    local include_dev="${3:-false}"

    check_dependencies jq || return "$EXIT_DEPS_MISSING"

    echo "$json" | jq --arg threshold "$threshold" --arg include_dev "$include_dev" '
        # 定义严重性排序
        def severity_order:
            {"low": 0, "moderate": 1, "high": 2, "critical": 3};

        # 获取严重性索引
        def severity_index(s):
            severity_order[s] // -1;

        # 检查严重性是否满足阈值
        def meets_threshold(sev; thr):
            severity_index(sev) >= severity_index(thr);

        # 处理 advisories 对象
        (.advisories // {}) | to_entries | map(
            select(
                meets_threshold(.value.severity; $threshold)
            ) |
            {
                name: .value.module_name,
                severity: .value.severity,
                via: [.value.title // "Unknown"],
                effects: [],
                fixAvailable: ((.value.patched_versions // "") != ""),
                isDirect: true,
                path: ((.value.findings[0].paths // []) | .[0] // "")
            }
        )
    ' 2>/dev/null
}

# ==================== 输出格式化 ====================

# 生成 JSON 格式输出
format_json_output() {
    local vulnerabilities="$1"

    check_dependencies jq || return "$EXIT_DEPS_MISSING"

    local scan_time
    scan_time=$(get_iso_timestamp)

    # 计算统计信息
    local total by_severity
    total=$(echo "$vulnerabilities" | jq 'length')

    by_severity=$(echo "$vulnerabilities" | jq '
        group_by(.severity) | map({
            key: .[0].severity,
            value: length
        }) | from_entries | . as $counts |
        {
            critical: ($counts.critical // 0),
            high: ($counts.high // 0),
            moderate: ($counts.moderate // 0),
            low: ($counts.low // 0)
        }
    ')

    # 构建最终 JSON
    jq -n \
        --arg scan_time "$scan_time" \
        --argjson total "$total" \
        --argjson by_severity "$by_severity" \
        --argjson vulnerabilities "$vulnerabilities" \
        '{
            scan_time: $scan_time,
            total: $total,
            by_severity: $by_severity,
            vulnerabilities: $vulnerabilities
        }'
}

# 生成 Markdown 格式输出
format_md_output() {
    local vulnerabilities="$1"

    check_dependencies jq || return "$EXIT_DEPS_MISSING"

    local total
    total=$(echo "$vulnerabilities" | jq 'length')

    # 输出标题
    echo "# 漏洞扫描报告"
    echo ""
    echo "**扫描时间**: $(get_iso_timestamp)"
    echo "**发现漏洞**: $total"
    echo ""

    if [[ "$total" -eq 0 ]]; then
        echo "未发现漏洞。项目安全。"
        return 0
    fi

    # 输出表格头
    echo "| 包名 | 严重性 | 描述 | 可修复 |"
    echo "|------|--------|------|--------|"

    # 输出每个漏洞
    echo "$vulnerabilities" | jq -r '.[] | [
        .name,
        .severity,
        (.via | join(", ")),
        (if .fixAvailable then "是" else "否" end)
    ] | @tsv' | while IFS=$'\t' read -r name severity via fixable; do
        local badge
        badge=$(get_severity_badge "$severity")
        echo "| $name | $badge | $via | $fixable |"
    done
}

# ==================== 命令: scan ====================

cmd_scan() {
    local format="json"
    local severity="$VULN_SEVERITY_THRESHOLD"
    local include_dev="$VULN_INCLUDE_DEV"
    local dir="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            --severity) severity="$2"; shift 2 ;;
            --include-dev) include_dev="true"; shift ;;
            --dir) dir="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # 验证目录
    if [[ ! -d "$dir" ]]; then
        log_warn "目录不存在: $dir"
        if [[ "$format" == "json" ]]; then
            format_json_output "[]"
        else
            echo "Warning: 目录不存在: $dir"
        fi
        return 0
    fi

    # 检查 package.json 是否存在
    if [[ ! -f "$dir/package.json" ]]; then
        log_warn "未找到 package.json: $dir"
        if [[ "$format" == "json" ]]; then
            format_json_output "[]"
        else
            echo "Warning: 未找到 package.json，无法执行漏洞扫描"
        fi
        return 0
    fi

    # 检查 npm 是否可用
    if ! check_dependency npm; then
        log_warn "npm 不可用，跳过漏洞扫描"
        if [[ "$format" == "json" ]]; then
            format_json_output "[]"
        else
            echo "Warning: npm 不可用"
        fi
        return 0
    fi

    # 检测 npm audit 格式
    local npm_format
    npm_format=$(detect_npm_audit_format)
    log_info "检测到 npm 格式: $npm_format"

    # 执行 npm audit
    local audit_json
    cd "$dir" || return 1

    # npm audit 可能返回非零退出码（当发现漏洞时）
    # 所以我们捕获输出而不是退出码
    audit_json=$(npm audit --json 2>/dev/null || true)
    cd - > /dev/null || true

    # 如果 npm audit 失败或返回空
    if [[ -z "$audit_json" ]]; then
        log_warn "npm audit 返回空结果"
        if [[ "$format" == "json" ]]; then
            format_json_output "[]"
        else
            echo "Warning: npm audit 无法获取结果"
        fi
        return 0
    fi

    # 解析漏洞
    local vulnerabilities
    if [[ "$npm_format" == "npm7" ]]; then
        vulnerabilities=$(parse_npm7_format "$audit_json" "$severity" "$include_dev")
    else
        vulnerabilities=$(parse_npm6_format "$audit_json" "$severity" "$include_dev")
    fi

    # 处理解析失败
    if [[ -z "$vulnerabilities" || "$vulnerabilities" == "null" ]]; then
        vulnerabilities="[]"
    fi

    # 格式化输出
    case "$format" in
        json)
            format_json_output "$vulnerabilities"
            ;;
        md|markdown)
            format_md_output "$vulnerabilities"
            ;;
        *)
            log_error "不支持的格式: $format"
            return "$EXIT_ARGS_ERROR"
            ;;
    esac
}

# ==================== 命令: parse ====================

# 解析已有的 npm audit JSON 文件（用于测试和离线分析）
cmd_parse() {
    local input=""
    local format="text"
    local npm_format="npm7"
    local severity="$VULN_SEVERITY_THRESHOLD"
    local include_dev="$VULN_INCLUDE_DEV"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input) input="$2"; shift 2 ;;
            --format)
                # 支持 npm6/npm7 作为输入格式或 json/md 作为输出格式
                case "$2" in
                    npm6|npm7) npm_format="$2" ;;
                    *) format="$2" ;;
                esac
                shift 2
                ;;
            --severity) severity="$2"; shift 2 ;;
            --include-dev) include_dev="true"; shift ;;
            *) shift ;;
        esac
    done

    # 验证输入文件
    if [[ -z "$input" ]]; then
        log_error "请指定输入文件: --input <file>"
        return "$EXIT_ARGS_ERROR"
    fi

    if [[ ! -f "$input" ]]; then
        log_error "输入文件不存在: $input"
        return "$EXIT_ARGS_ERROR"
    fi

    # 读取输入文件
    local audit_json
    audit_json=$(cat "$input")

    # 验证 JSON 格式
    if ! echo "$audit_json" | jq empty 2>/dev/null; then
        log_error "无效的 JSON 文件: $input"
        return "$EXIT_ARGS_ERROR"
    fi

    # 自动检测格式（如果包含 .vulnerabilities 则为 npm7）
    if echo "$audit_json" | jq -e '.vulnerabilities' > /dev/null 2>&1; then
        npm_format="npm7"
    elif echo "$audit_json" | jq -e '.advisories' > /dev/null 2>&1; then
        npm_format="npm6"
    fi

    # 解析漏洞
    local vulnerabilities
    if [[ "$npm_format" == "npm7" ]]; then
        vulnerabilities=$(parse_npm7_format "$audit_json" "$severity" "$include_dev")
    else
        vulnerabilities=$(parse_npm6_format "$audit_json" "$severity" "$include_dev")
    fi

    # 处理解析失败
    if [[ -z "$vulnerabilities" || "$vulnerabilities" == "null" ]]; then
        vulnerabilities="[]"
    fi

    # 检查是否有漏洞
    local total
    total=$(echo "$vulnerabilities" | jq 'length')

    # 格式化输出
    case "$format" in
        json)
            format_json_output "$vulnerabilities"
            ;;
        md|markdown)
            format_md_output "$vulnerabilities"
            ;;
        *)
            # 默认简单输出
            if [[ "$total" -eq 0 ]]; then
                echo "No vulnerabilities found."
            else
                echo "$vulnerabilities" | jq -r '.[] | "\(.name): \(.severity)"'
            fi
            ;;
    esac
}

# ==================== 命令: trace ====================

# 追踪依赖传播路径
cmd_trace() {
    local package_name=""
    local dir="."

    # 解析参数
    if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
        package_name="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir) dir="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$package_name" ]]; then
        log_error "请指定包名: vuln-tracker trace <package-name>"
        return "$EXIT_ARGS_ERROR"
    fi

    # 验证目录
    if [[ ! -d "$dir" ]]; then
        log_warn "目录不存在: $dir"
        echo "{\"package\": \"$package_name\", \"chain\": [], \"files\": []}"
        return 0
    fi

    # 检查 package.json
    if [[ ! -f "$dir/package.json" ]]; then
        log_warn "未找到 package.json"
        echo "{\"package\": \"$package_name\", \"chain\": [], \"files\": []}"
        return 0
    fi

    log_info "追踪依赖: $package_name"

    # 获取依赖链（使用 npm ls）
    local dep_tree=""
    cd "$dir" || return 1
    dep_tree=$(npm ls "$package_name" --json 2>/dev/null || echo "{}")
    cd - > /dev/null || true

    # 查找使用该包的文件
    local using_files=()
    if [[ -d "$dir/src" ]]; then
        while IFS= read -r file; do
            using_files+=("$file")
        done < <(grep -rl "require.*['\"]${package_name}['\"]" "$dir/src" 2>/dev/null || true)
        while IFS= read -r file; do
            using_files+=("$file")
        done < <(grep -rl "from ['\"]${package_name}['\"]" "$dir/src" 2>/dev/null || true)
    fi

    # 构建依赖链
    local chain=()
    # 从 npm ls 输出中提取依赖路径
    if echo "$dep_tree" | jq -e '.dependencies' > /dev/null 2>&1; then
        local dep_name
        dep_name=$(echo "$dep_tree" | jq -r '.name // "project"')
        chain+=("$dep_name")

        # 简化：直接添加目标包
        if echo "$dep_tree" | jq -e ".dependencies[\"$package_name\"]" > /dev/null 2>&1; then
            chain+=("$package_name")
        else
            # 查找间接依赖
            local indirect
            indirect=$(echo "$dep_tree" | jq -r ".. | objects | select(.dependencies[\"$package_name\"]?) | .name // empty" 2>/dev/null | head -1)
            if [[ -n "$indirect" ]]; then
                chain+=("$indirect")
                chain+=("$package_name")
            fi
        fi
    fi

    # 输出结果
    check_dependencies jq || return "$EXIT_DEPS_MISSING"

    # 处理空数组情况
    local chain_json files_json
    if [[ ${#chain[@]} -gt 0 ]]; then
        chain_json=$(printf '%s\n' "${chain[@]}" | jq -R . | jq -s .)
    else
        chain_json="[]"
    fi

    if [[ ${#using_files[@]} -gt 0 ]]; then
        files_json=$(printf '%s\n' "${using_files[@]}" | jq -R . | jq -s .)
    else
        files_json="[]"
    fi

    jq -n \
        --arg package "$package_name" \
        --argjson chain "$chain_json" \
        --argjson files "$files_json" \
        '{
            package: $package,
            chain: $chain,
            files: $files
        }'
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
vuln-tracker.sh - 安全漏洞基础追踪

用法:
    vuln-tracker.sh <command> [options]

命令:
    scan            执行漏洞扫描（调用 npm audit）
    parse           解析已有的 npm audit JSON 文件
    trace           追踪依赖传播路径

scan 选项:
    --format <fmt>      输出格式: json (默认), md
    --severity <level>  最低严重性: low, moderate (默认), high, critical
    --include-dev       包含开发依赖
    --dir <path>        项目目录（默认当前目录）

parse 选项:
    --input <file>      输入的 npm audit JSON 文件（必需）
    --format <fmt>      输出格式: json (默认), md, npm6, npm7
    --severity <level>  最低严重性阈值
    --include-dev       包含开发依赖

trace 选项:
    <package-name>      要追踪的包名（必需）
    --dir <path>        项目目录（默认当前目录）

严重性等级（从低到高）:
    low < moderate < high < critical

输出格式:
    json - JSON 格式，包含 scan_time, total, by_severity, vulnerabilities
    md   - Markdown 表格格式，包含严重性徽章

环境变量:
    VULN_SEVERITY_THRESHOLD  默认严重性阈值（默认: moderate）
    VULN_INCLUDE_DEV         默认是否包含开发依赖（默认: false）

示例:
    # 扫描当前项目的漏洞
    vuln-tracker.sh scan

    # 仅扫描高危及以上漏洞，输出 Markdown
    vuln-tracker.sh scan --severity high --format md

    # 包含开发依赖
    vuln-tracker.sh scan --include-dev

    # 解析已有的 audit 文件
    vuln-tracker.sh parse --input audit.json --format json

    # 追踪 lodash 的依赖传播
    vuln-tracker.sh trace lodash

    # 在指定目录执行扫描
    vuln-tracker.sh scan --dir /path/to/project
EOF
}

# ==================== 主入口 ====================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        scan)
            cmd_scan "$@"
            ;;
        parse)
            cmd_parse "$@"
            ;;
        trace)
            cmd_trace "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit "$EXIT_ARGS_ERROR"
            ;;
    esac
}

# 仅在直接执行时运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
