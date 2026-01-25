#!/usr/bin/env bash
# verify-change.sh - 变更包验证脚本
# Change ID: augment-parity-final-gaps
#
# 用途：运行所有验收测试并生成 Green 证据
# 运行方式：./verify-change.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
EVIDENCE_DIR="$SCRIPT_DIR/../green-final"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."

    local missing=()

    command -v node >/dev/null 2>&1 || missing+=("node")
    command -v npm >/dev/null 2>&1 || missing+=("npm")
    command -v bats >/dev/null 2>&1 || missing+=("bats")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v sqlite3 >/dev/null 2>&1 || missing+=("sqlite3")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "缺少依赖: ${missing[*]}"
        log_warn "部分测试可能被跳过"
    else
        log_info "所有依赖已满足"
    fi
}

# 运行测试
run_tests() {
    log_info "运行全量测试..."

    mkdir -p "$EVIDENCE_DIR"

    local test_log="$EVIDENCE_DIR/test-$TIMESTAMP.log"

    cd "$PROJECT_ROOT"

    # 运行 npm test
    if npm test 2>&1 | tee "$test_log"; then
        log_info "测试通过 ✅"
        echo "TEST_STATUS=PASSED" >> "$test_log"
        return 0
    else
        log_error "测试失败 ❌"
        echo "TEST_STATUS=FAILED" >> "$test_log"
        return 1
    fi
}

# 验证证据文件
verify_evidence() {
    log_info "验证证据文件..."

    local evidence_base="$SCRIPT_DIR/.."
    local missing=()

    # 检查必需的证据文件
    [[ -f "$evidence_base/performance-report.md" ]] || missing+=("performance-report.md")
    [[ -f "$evidence_base/migrate-test.log" ]] || missing+=("migrate-test.log")
    [[ -f "$evidence_base/lru-poc-test.log" ]] || missing+=("lru-poc-test.log")
    [[ -d "$evidence_base/red-baseline" ]] || missing+=("red-baseline/")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "缺少证据文件: ${missing[*]}"
    else
        log_info "所有证据文件存在 ✅"
    fi
}

# 生成摘要
generate_summary() {
    log_info "生成验证摘要..."

    local summary_file="$EVIDENCE_DIR/summary-$TIMESTAMP.md"

    cat > "$summary_file" << EOF
# 变更包验证摘要

**Change ID**: augment-parity-final-gaps
**验证时间**: $(date '+%Y-%m-%d %H:%M:%S')
**验证者**: Coder (CI)

## 测试结果

- 测试日志: test-$TIMESTAMP.log
- 状态: 见测试日志末尾 TEST_STATUS

## 证据清单

| 文件 | 状态 |
|------|------|
| red-baseline/ | $(ls -d "$SCRIPT_DIR/../red-baseline" 2>/dev/null && echo "✅" || echo "❌") |
| green-final/ | ✅ |
| performance-report.md | $(test -f "$SCRIPT_DIR/../performance-report.md" && echo "✅" || echo "❌") |
| migrate-test.log | $(test -f "$SCRIPT_DIR/../migrate-test.log" && echo "✅" || echo "❌") |
| lru-poc-test.log | $(test -f "$SCRIPT_DIR/../lru-poc-test.log" && echo "✅" || echo "❌") |

## AC 覆盖

参考: verification.md 中的 AC 覆盖矩阵

## 下一步

- [ ] Test Owner 验证并打勾 verification.md
- [ ] Code Review
- [ ] Archive
EOF

    log_info "摘要已生成: $summary_file"
}

# 主函数
main() {
    log_info "开始变更包验证: augment-parity-final-gaps"

    check_dependencies
    verify_evidence

    if run_tests; then
        generate_summary
        log_info "验证完成 ✅"
        exit 0
    else
        log_error "验证失败 ❌"
        exit 1
    fi
}

main "$@"
