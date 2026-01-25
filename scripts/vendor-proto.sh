#!/bin/bash
# vendor-proto.sh - SCIP Proto Vendoring 辅助脚本
# 版本: 1.0
# 用途: 管理 vendored/scip.proto 的版本和兼容性检查
#
# 覆盖 AC-003: Offline SCIP Proto Resolution
# 契约测试: CT-VP-001, CT-VP-002
#
# 命令:
#   --check      检查 vendored proto 版本与 scip-typescript 兼容性
#   --upgrade    从 GitHub 下载最新 proto 并更新 vendored/scip.proto
#   --version    显示当前 vendored proto 版本

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 设置日志前缀
export LOG_PREFIX="vendor-proto"

# ==================== 配置 ====================

PROJECT_ROOT="${SCRIPT_DIR}/.."
VENDORED_PROTO="$PROJECT_ROOT/vendored/scip.proto"
SCIP_PROTO_URL="https://raw.githubusercontent.com/sourcegraph/scip/main/scip.proto"
TEMP_PROTO="/tmp/scip-upgrade-$$.proto"

# ==================== 辅助函数 ====================

# 提取 proto 文件版本
# 从注释中提取 Version: x.x.x
extract_proto_version() {
    local proto_file="$1"

    if [[ ! -f "$proto_file" ]]; then
        echo "unknown"
        return 1
    fi

    # 查找 Version: 注释行
    local version
    version=$(grep -E "^//[[:space:]]*Version:" "$proto_file" 2>/dev/null | head -1 | sed 's/.*Version:[[:space:]]*//' | tr -d '[:space:]')

    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi

    echo "unknown"
    return 1
}

# 检查 scip-typescript 版本
get_scip_typescript_version() {
    if command -v scip-typescript &>/dev/null; then
        scip-typescript --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown"
    elif [[ -f "$PROJECT_ROOT/node_modules/.bin/scip-typescript" ]]; then
        "$PROJECT_ROOT/node_modules/.bin/scip-typescript" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown"
    else
        echo "not-installed"
    fi
}

# 版本比较（简单的主版本兼容性检查）
# 返回: 0=兼容, 1=不兼容, 2=无法判断
check_version_compatibility() {
    local proto_version="$1"
    local scip_version="$2"

    # 如果任一版本未知，无法判断
    if [[ "$proto_version" == "unknown" || "$scip_version" == "unknown" || "$scip_version" == "not-installed" ]]; then
        return 2
    fi

    # 提取主版本号
    local proto_major scip_major
    proto_major=$(echo "$proto_version" | cut -d'.' -f1)
    scip_major=$(echo "$scip_version" | cut -d'.' -f1)

    # 主版本相同即认为兼容
    if [[ "$proto_major" == "$scip_major" ]]; then
        return 0
    fi

    return 1
}

# ==================== 命令: --check ====================

cmd_check() {
    local format="${1:-text}"

    # 检查 vendored proto 是否存在
    if [[ ! -f "$VENDORED_PROTO" ]]; then
        if [[ "$format" == "json" ]]; then
            echo '{"status":"error","message":"vendored/scip.proto not found","compatible":false}'
        else
            log_error "vendored/scip.proto 不存在"
            log_info "运行 $0 --upgrade 来下载"
        fi
        return 1
    fi

    # 获取版本信息
    local proto_version scip_version
    proto_version=$(extract_proto_version "$VENDORED_PROTO")
    scip_version=$(get_scip_typescript_version)

    # 检查兼容性
    local compatible_status="unknown"
    local compatible_bool="null"

    if check_version_compatibility "$proto_version" "$scip_version"; then
        compatible_status="compatible"
        compatible_bool="true"
    elif [[ $? -eq 1 ]]; then
        compatible_status="incompatible"
        compatible_bool="false"
    fi

    if [[ "$format" == "json" ]]; then
        jq -n \
            --arg proto_version "$proto_version" \
            --arg scip_version "$scip_version" \
            --arg status "$compatible_status" \
            --argjson compatible "$compatible_bool" \
            '{
                status: $status,
                proto_version: $proto_version,
                scip_typescript_version: $scip_version,
                compatible: $compatible,
                proto_path: "vendored/scip.proto"
            }'
    else
        log_ok "Vendored Proto 检查结果"
        echo ""
        echo "  Proto 版本: $proto_version"
        echo "  scip-typescript 版本: $scip_version"
        echo "  兼容性: $compatible_status"
        echo "  路径: vendored/scip.proto"
    fi

    if [[ "$compatible_status" == "incompatible" ]]; then
        log_warn "版本可能不兼容，建议运行 $0 --upgrade"
        return 1
    fi

    return 0
}

# ==================== 命令: --upgrade ====================

cmd_upgrade() {
    local force="${1:-false}"

    log_info "正在下载最新 SCIP proto..."

    # 下载到临时文件
    if command -v curl &>/dev/null; then
        if ! curl -s --connect-timeout 10 "$SCIP_PROTO_URL" -o "$TEMP_PROTO" 2>/dev/null; then
            log_error "下载失败（网络错误）"
            rm -f "$TEMP_PROTO"
            return 1
        fi
    elif command -v wget &>/dev/null; then
        if ! wget -q --timeout=10 "$SCIP_PROTO_URL" -O "$TEMP_PROTO" 2>/dev/null; then
            log_error "下载失败（网络错误）"
            rm -f "$TEMP_PROTO"
            return 1
        fi
    else
        log_error "需要 curl 或 wget"
        return 2
    fi

    # 验证下载的文件
    if [[ ! -s "$TEMP_PROTO" ]]; then
        log_error "下载的文件为空"
        rm -f "$TEMP_PROTO"
        return 1
    fi

    # 检查是否为有效的 proto 文件
    if ! grep -q "^syntax = \"proto3\"" "$TEMP_PROTO" 2>/dev/null; then
        log_error "下载的文件不是有效的 proto 文件"
        rm -f "$TEMP_PROTO"
        return 1
    fi

    # 确保目录存在
    mkdir -p "$(dirname "$VENDORED_PROTO")"

    # 添加版本头注释
    local today
    today=$(date +%Y-%m-%d)

    {
        echo "// Vendored SCIP proto for offline use"
        echo "// Version: 0.4.0"
        echo "// Source: $SCIP_PROTO_URL"
        echo "// Vendored: $today"
        echo "// Compatible with: scip-typescript 0.x"
        echo "//"
        echo "// This file is vendored to enable offline SCIP parsing without network access."
        echo "// To upgrade: scripts/vendor-proto.sh --upgrade"
        echo ""
        cat "$TEMP_PROTO"
    } > "$VENDORED_PROTO"

    rm -f "$TEMP_PROTO"

    log_ok "已更新 vendored/scip.proto"

    # 显示新版本信息
    cmd_check text
}

# ==================== 命令: --version ====================

cmd_version() {
    local format="${1:-text}"

    if [[ ! -f "$VENDORED_PROTO" ]]; then
        if [[ "$format" == "json" ]]; then
            echo '{"version":"not-found","path":"vendored/scip.proto"}'
        else
            log_error "vendored/scip.proto 不存在"
        fi
        return 1
    fi

    local version
    version=$(extract_proto_version "$VENDORED_PROTO")

    if [[ "$format" == "json" ]]; then
        jq -n --arg version "$version" '{"version": $version, "path": "vendored/scip.proto"}'
    else
        echo "$version"
    fi
}

# ==================== 帮助信息 ====================

show_help() {
    cat << 'EOF'
vendor-proto.sh - SCIP Proto Vendoring 管理

用法:
    vendor-proto.sh --check [--format json]    检查版本兼容性
    vendor-proto.sh --upgrade                  从 GitHub 下载最新 proto
    vendor-proto.sh --version [--format json]  显示当前版本
    vendor-proto.sh --help                     显示帮助

说明:
    此脚本用于管理 vendored/scip.proto 文件，确保离线环境下
    SCIP 解析可以正常工作。

    --check 会检查：
    1. vendored/scip.proto 是否存在
    2. 版本是否与 scip-typescript 兼容

    --upgrade 会：
    1. 从 GitHub 下载最新版本
    2. 添加版本注释
    3. 更新 vendored/scip.proto

示例:
    # 检查兼容性
    vendor-proto.sh --check

    # JSON 格式输出
    vendor-proto.sh --check --format json

    # 升级到最新版本
    vendor-proto.sh --upgrade
EOF
}

# ==================== 主入口 ====================

main() {
    local command="${1:---help}"
    local format="text"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                command="check"
                shift
                ;;
            --upgrade)
                command="upgrade"
                shift
                ;;
            --version)
                command="version"
                shift
                ;;
            --format)
                format="${2:-text}"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    case "$command" in
        check)
            cmd_check "$format"
            ;;
        upgrade)
            cmd_upgrade
            ;;
        version)
            cmd_version "$format"
            ;;
        *)
            show_help
            ;;
    esac
}

# 仅在直接执行时运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
