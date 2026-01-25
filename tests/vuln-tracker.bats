#!/usr/bin/env bats
# vuln-tracker.bats - 安全漏洞基础追踪模块测试
#
# 覆盖 M7: 安全漏洞基础追踪
# 规格: dev-playbooks/specs/vuln-tracker/spec.md
#
# 场景覆盖:
#   T-VT-001: 基本漏洞扫描
#   T-VT-002: npm 7+ 格式解析
#   T-VT-003: npm 6.x 格式解析
#   T-VT-004: 严重性阈值过滤
#   T-VT-005: 依赖传播追踪
#   T-VT-006: npm audit 不可用降级
#   T-VT-007: JSON 输出格式
#   T-VT-008: Markdown 输出格式
#   T-VT-009: 无漏洞结果
#   T-VT-010: 开发依赖包含/排除

load 'helpers/common'

# 脚本路径
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
VULN_TRACKER="$SCRIPT_DIR/vuln-tracker.sh"

# 严重性等级顺序: low < moderate < high < critical
SEVERITY_ORDER=("low" "moderate" "high" "critical")

setup() {
    setup_temp_dir
    export TEST_PROJECT_DIR="$TEST_TEMP_DIR/project"
    mkdir -p "$TEST_PROJECT_DIR"

    # 创建基本的 package.json
    cat > "$TEST_PROJECT_DIR/package.json" << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "dependencies": {
    "lodash": "4.17.15",
    "express": "4.17.1"
  },
  "devDependencies": {
    "jest": "26.0.0"
  }
}
EOF
}

teardown() {
    cleanup_temp_dir
}

# ============================================================
# T-VT-001: 基本漏洞扫描
# ============================================================

# @test T-VT-001: 基本漏洞扫描
@test "T-VT-001: vuln-tracker scan executes npm audit and parses results" {
    skip_if_not_executable "$VULN_TRACKER"

    cd "$TEST_PROJECT_DIR" || skip "Cannot cd to test project"

    run "$VULN_TRACKER" scan
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh scan"

    # 基本功能：返回成功或有漏洞信息
    # 无论是否发现漏洞，scan 命令应该成功执行
    assert_exit_success "$status"

    # 输出应包含扫描相关信息
    # 可能是 JSON 格式或文本格式
    [ -n "$output" ]
}

# @test T-VT-001b: scan 在指定目录执行
@test "T-VT-001b: vuln-tracker scan works with --dir option" {
    skip_if_not_executable "$VULN_TRACKER"

    run "$VULN_TRACKER" scan --dir "$TEST_PROJECT_DIR"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh scan --dir"

    assert_exit_success "$status"
}

# ============================================================
# T-VT-002: npm 7+ 格式解析
# ============================================================

# @test T-VT-002: npm 7+ 格式正确解析 .vulnerabilities 结构
@test "T-VT-002: vuln-tracker parses npm 7+ audit format correctly" {
    skip_if_not_executable "$VULN_TRACKER"

    # 创建 npm 7+ 格式的模拟 audit 输出
    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/npm7-audit.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {
    "lodash": {
      "name": "lodash",
      "severity": "high",
      "isDirect": true,
      "via": [
        {
          "source": 1234,
          "name": "lodash",
          "dependency": "lodash",
          "title": "Prototype Pollution",
          "url": "https://npmjs.com/advisories/1234",
          "severity": "high",
          "range": "<4.17.21"
        }
      ],
      "effects": [],
      "range": "<4.17.21",
      "nodes": ["node_modules/lodash"],
      "fixAvailable": true
    }
  },
  "metadata": {
    "vulnerabilities": {
      "info": 0,
      "low": 0,
      "moderate": 0,
      "high": 1,
      "critical": 0,
      "total": 1
    }
  }
}
EOF

    # 测试解析功能（使用模拟输入）
    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/npm7-audit.json" --format npm7
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh parse npm7"

    assert_exit_success "$status"

    # 验证解析结果包含漏洞信息
    assert_contains "$output" "lodash"
    assert_contains_any "$output" "high" "HIGH" "High"
}

# ============================================================
# T-VT-003: npm 6.x 格式解析
# ============================================================

# @test T-VT-003: npm 6.x 格式正确解析 .advisories 结构
@test "T-VT-003: vuln-tracker parses npm 6.x audit format correctly" {
    skip_if_not_executable "$VULN_TRACKER"

    # 创建 npm 6.x 格式的模拟 audit 输出
    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/npm6-audit.json" << 'EOF'
{
  "advisories": {
    "1234": {
      "id": 1234,
      "module_name": "lodash",
      "severity": "high",
      "title": "Prototype Pollution",
      "url": "https://npmjs.com/advisories/1234",
      "findings": [
        {
          "version": "4.17.15",
          "paths": ["lodash"]
        }
      ],
      "vulnerable_versions": "<4.17.21",
      "patched_versions": ">=4.17.21"
    }
  },
  "metadata": {
    "vulnerabilities": {
      "info": 0,
      "low": 0,
      "moderate": 0,
      "high": 1,
      "critical": 0
    }
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/npm6-audit.json" --format npm6
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh parse npm6"

    assert_exit_success "$status"

    # 验证解析结果
    assert_contains "$output" "lodash"
    assert_contains_any "$output" "high" "HIGH" "High"
}

# ============================================================
# T-VT-004: 严重性阈值过滤
# ============================================================

# @test T-VT-004: --severity high 仅返回 high 和 critical 漏洞
@test "T-VT-004: vuln-tracker scan --severity filters by threshold" {
    skip_if_not_executable "$VULN_TRACKER"

    # 创建包含多种严重性的模拟数据
    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/mixed-severity.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {
    "pkg-low": {
      "name": "pkg-low",
      "severity": "low",
      "via": [{"severity": "low", "title": "Low Issue"}]
    },
    "pkg-moderate": {
      "name": "pkg-moderate",
      "severity": "moderate",
      "via": [{"severity": "moderate", "title": "Moderate Issue"}]
    },
    "pkg-high": {
      "name": "pkg-high",
      "severity": "high",
      "via": [{"severity": "high", "title": "High Issue"}]
    },
    "pkg-critical": {
      "name": "pkg-critical",
      "severity": "critical",
      "via": [{"severity": "critical", "title": "Critical Issue"}]
    }
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/mixed-severity.json" --severity high
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh --severity"

    assert_exit_success "$status"

    # 应包含 high 和 critical
    assert_contains "$output" "pkg-high"
    assert_contains "$output" "pkg-critical"

    # 不应包含 low 和 moderate
    assert_not_contains "$output" "pkg-low"
    assert_not_contains "$output" "pkg-moderate"
}

# @test T-VT-004b: 严重性阈值支持所有级别
@test "T-VT-004b: vuln-tracker supports all severity levels" {
    skip_if_not_executable "$VULN_TRACKER"

    # 测试 --severity moderate (应返回 moderate, high, critical)
    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/mixed-severity.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {
    "pkg-low": {"name": "pkg-low", "severity": "low"},
    "pkg-moderate": {"name": "pkg-moderate", "severity": "moderate"},
    "pkg-high": {"name": "pkg-high", "severity": "high"},
    "pkg-critical": {"name": "pkg-critical", "severity": "critical"}
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/mixed-severity.json" --severity moderate
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh --severity moderate"

    assert_exit_success "$status"

    # moderate 及以上应包含
    assert_contains "$output" "pkg-moderate"
    assert_contains "$output" "pkg-high"
    assert_contains "$output" "pkg-critical"

    # low 不应包含
    assert_not_contains "$output" "pkg-low"
}

# ============================================================
# T-VT-005: 依赖传播追踪
# ============================================================

# @test T-VT-005: trace 命令显示依赖链和受影响文件
@test "T-VT-005: vuln-tracker trace shows dependency chain" {
    skip_if_not_executable "$VULN_TRACKER"

    cd "$TEST_PROJECT_DIR" || skip "Cannot cd to test project"

    # 创建使用有漏洞依赖的文件
    mkdir -p "$TEST_PROJECT_DIR/src"
    cat > "$TEST_PROJECT_DIR/src/index.js" << 'EOF'
const lodash = require('lodash');
const _ = lodash;
module.exports = { merge: _.merge };
EOF

    run "$VULN_TRACKER" trace lodash --dir "$TEST_PROJECT_DIR"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh trace"

    assert_exit_success "$status"

    # 应显示依赖链信息
    # 输出应包含包名和使用该包的文件
    assert_contains_any "$output" "lodash" "dependency" "chain" "src/index.js"
}

# @test T-VT-005b: trace 命令处理间接依赖
@test "T-VT-005b: vuln-tracker trace handles transitive dependencies" {
    skip_if_not_executable "$VULN_TRACKER"

    cd "$TEST_PROJECT_DIR" || skip "Cannot cd to test project"

    # 间接依赖场景：express -> body-parser -> qs (假设的漏洞依赖)
    run "$VULN_TRACKER" trace qs --dir "$TEST_PROJECT_DIR"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh trace transitive"

    # 即使是间接依赖，也应该返回成功
    assert_exit_success "$status"
}

# ============================================================
# T-VT-006: npm audit 不可用降级
# ============================================================

# @test T-VT-006: npm audit 失败时优雅降级
@test "T-VT-006: vuln-tracker gracefully handles npm audit failure" {
    skip_if_not_executable "$VULN_TRACKER"

    # 创建一个没有 package.json 的目录
    mkdir -p "$TEST_TEMP_DIR/empty-project"

    cd "$TEST_TEMP_DIR/empty-project" || skip "Cannot cd to empty project"

    run "$VULN_TRACKER" scan --dir "$TEST_TEMP_DIR/empty-project"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh scan fallback"

    # 应该返回成功（退出码 0）但输出警告
    assert_exit_success "$status"

    # 应包含警告信息
    assert_contains_any "$output" "warning" "Warning" "WARNING" "无法" "not found" "empty"
}

# @test T-VT-006b: 无效项目目录处理
@test "T-VT-006b: vuln-tracker handles invalid project directory" {
    skip_if_not_executable "$VULN_TRACKER"

    run "$VULN_TRACKER" scan --dir "/nonexistent/path"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh invalid dir"

    # 可以返回失败或成功并带警告
    # 重要的是不应崩溃
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ============================================================
# T-VT-007: JSON 输出格式
# ============================================================

# @test T-VT-007: --format json 输出有效 JSON
@test "T-VT-007: vuln-tracker outputs valid JSON with --format json" {
    skip_if_not_executable "$VULN_TRACKER"

    cd "$TEST_PROJECT_DIR" || skip "Cannot cd to test project"

    run "$VULN_TRACKER" scan --format json --dir "$TEST_PROJECT_DIR"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh --format json"

    assert_exit_success "$status"

    # 验证输出是有效 JSON
    local json
    json=$(extract_json "$output")
    assert_valid_json "$json"

    # 验证 JSON 结构包含必需字段
    assert_json_field "$json" ".scan_time"

    # vulnerabilities 应该是数组（可能为空）
    local vuln_type
    vuln_type=$(echo "$json" | jq -r '.vulnerabilities | type' 2>/dev/null)
    [ "$vuln_type" = "array" ]
}

# @test T-VT-007b: JSON 输出包含完整漏洞结构
@test "T-VT-007b: vuln-tracker JSON output includes complete vulnerability structure" {
    skip_if_not_executable "$VULN_TRACKER"

    # 使用有漏洞的模拟数据
    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/vuln-audit.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {
    "lodash": {
      "name": "lodash",
      "severity": "critical",
      "via": [{"title": "Prototype Pollution", "severity": "critical"}],
      "fixAvailable": true
    }
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/vuln-audit.json" --format json
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh parse --format json"

    assert_exit_success "$status"

    local json
    json=$(extract_json "$output")
    assert_valid_json "$json"

    # 验证结构
    # total 应该是数字
    local total
    total=$(echo "$json" | jq -r '.total' 2>/dev/null)
    [ "$total" -ge 0 ] 2>/dev/null || [ "$total" = "null" ]

    # by_severity 应该存在
    assert_json_field "$json" ".by_severity"
}

# ============================================================
# T-VT-008: Markdown 输出格式
# ============================================================

# @test T-VT-008: --format md 输出 Markdown 表格
@test "T-VT-008: vuln-tracker outputs Markdown table with --format md" {
    skip_if_not_executable "$VULN_TRACKER"

    # 使用有漏洞的模拟数据
    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/vuln-audit.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {
    "lodash": {
      "name": "lodash",
      "severity": "high",
      "via": [{"title": "Prototype Pollution"}]
    }
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/vuln-audit.json" --format md
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh --format md"

    assert_exit_success "$status"

    # Markdown 表格应包含 | 分隔符
    assert_contains "$output" "|"

    # 应包含表头分隔线 (---)
    assert_contains "$output" "---"

    # 应包含漏洞名称
    assert_contains "$output" "lodash"
}

# @test T-VT-008b: Markdown 输出包含严重性徽章
@test "T-VT-008b: vuln-tracker Markdown output includes severity badges" {
    skip_if_not_executable "$VULN_TRACKER"

    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/critical-vuln.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {
    "critical-pkg": {
      "name": "critical-pkg",
      "severity": "critical",
      "via": [{"title": "RCE"}]
    }
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/critical-vuln.json" --format md
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh --format md badges"

    assert_exit_success "$status"

    # 应包含严重性标识（可以是徽章、emoji 或文本）
    assert_contains_any "$output" "critical" "CRITICAL" "Critical" ":red_circle:" "🔴"
}

# ============================================================
# T-VT-009: 无漏洞结果
# ============================================================

# @test T-VT-009: 无漏洞时输出友好消息
@test "T-VT-009: vuln-tracker shows friendly message when no vulnerabilities" {
    skip_if_not_executable "$VULN_TRACKER"

    # 创建无漏洞的模拟数据
    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/clean-audit.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {},
  "metadata": {
    "vulnerabilities": {
      "info": 0,
      "low": 0,
      "moderate": 0,
      "high": 0,
      "critical": 0,
      "total": 0
    }
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/clean-audit.json"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh no vulnerabilities"

    assert_exit_success "$status"

    # 应显示无漏洞消息
    assert_contains_any "$output" "未发现" "no vulnerabilities" "No vulnerabilities" "0 vulnerabilities" "clean"
}

# @test T-VT-009b: 无漏洞时 JSON 输出正确
@test "T-VT-009b: vuln-tracker JSON output correct when no vulnerabilities" {
    skip_if_not_executable "$VULN_TRACKER"

    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/clean-audit.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {}
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/clean-audit.json" --format json
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh no vuln json"

    assert_exit_success "$status"

    local json
    json=$(extract_json "$output")
    assert_valid_json "$json"

    # total 应该是 0
    local total
    total=$(echo "$json" | jq -r '.total' 2>/dev/null)
    [ "$total" = "0" ] || [ "$total" = "null" ]

    # vulnerabilities 应该是空数组
    local vuln_count
    vuln_count=$(echo "$json" | jq '.vulnerabilities | length' 2>/dev/null)
    [ "$vuln_count" = "0" ] || [ "$vuln_count" = "null" ]
}

# ============================================================
# T-VT-010: 开发依赖包含/排除
# ============================================================

# @test T-VT-010: 默认排除开发依赖漏洞
@test "T-VT-010: vuln-tracker excludes devDependencies by default" {
    skip_if_not_executable "$VULN_TRACKER"

    # 创建包含 dev 依赖漏洞的模拟数据
    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/dev-vuln-audit.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {
    "prod-pkg": {
      "name": "prod-pkg",
      "severity": "high",
      "via": [{"title": "Issue"}],
      "isDirect": true,
      "dev": false
    },
    "dev-pkg": {
      "name": "dev-pkg",
      "severity": "high",
      "via": [{"title": "Dev Issue"}],
      "isDirect": true,
      "dev": true
    }
  }
}
EOF

    # 默认模式（排除 dev）
    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/dev-vuln-audit.json"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh exclude dev"

    assert_exit_success "$status"

    # 应包含生产依赖
    assert_contains "$output" "prod-pkg"

    # 不应包含开发依赖
    assert_not_contains "$output" "dev-pkg"
}

# @test T-VT-010b: --include-dev 包含开发依赖漏洞
@test "T-VT-010b: vuln-tracker --include-dev includes devDependencies" {
    skip_if_not_executable "$VULN_TRACKER"

    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/dev-vuln-audit.json" << 'EOF'
{
  "auditReportVersion": 2,
  "vulnerabilities": {
    "prod-pkg": {
      "name": "prod-pkg",
      "severity": "high",
      "dev": false
    },
    "dev-pkg": {
      "name": "dev-pkg",
      "severity": "high",
      "dev": true
    }
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/dev-vuln-audit.json" --include-dev
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh --include-dev"

    assert_exit_success "$status"

    # 应同时包含生产和开发依赖
    assert_contains "$output" "prod-pkg"
    assert_contains "$output" "dev-pkg"
}

# ============================================================
# 边界条件测试
# ============================================================

# @test EDGE-001: 空 vulnerabilities 对象
@test "EDGE-001: vuln-tracker handles empty vulnerabilities object" {
    skip_if_not_executable "$VULN_TRACKER"

    mkdir -p "$TEST_TEMP_DIR/mock"
    echo '{"vulnerabilities": {}}' > "$TEST_TEMP_DIR/mock/empty.json"

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/empty.json"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh empty"

    assert_exit_success "$status"
}

# @test EDGE-002: 畸形 JSON 输入
@test "EDGE-002: vuln-tracker handles malformed JSON gracefully" {
    skip_if_not_executable "$VULN_TRACKER"

    mkdir -p "$TEST_TEMP_DIR/mock"
    echo 'invalid json {' > "$TEST_TEMP_DIR/mock/malformed.json"

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/malformed.json"

    # 应该失败但不崩溃
    if [ "$status" -ne 0 ]; then
        # 失败是可接受的，应该有错误消息
        assert_contains_any "$output" "error" "Error" "invalid" "Invalid" "parse" "JSON"
    fi
}

# @test EDGE-003: 超长包名处理
@test "EDGE-003: vuln-tracker handles very long package names" {
    skip_if_not_executable "$VULN_TRACKER"

    mkdir -p "$TEST_TEMP_DIR/mock"
    local long_name
    long_name=$(printf 'a%.0s' {1..200})

    cat > "$TEST_TEMP_DIR/mock/long-name.json" << EOF
{
  "vulnerabilities": {
    "$long_name": {
      "name": "$long_name",
      "severity": "low"
    }
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/long-name.json"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh long name"

    # 应该成功处理或优雅失败
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# @test EDGE-004: 特殊字符包名
@test "EDGE-004: vuln-tracker handles special characters in package names" {
    skip_if_not_executable "$VULN_TRACKER"

    mkdir -p "$TEST_TEMP_DIR/mock"
    cat > "$TEST_TEMP_DIR/mock/special-chars.json" << 'EOF'
{
  "vulnerabilities": {
    "@scope/pkg-name": {
      "name": "@scope/pkg-name",
      "severity": "moderate"
    }
  }
}
EOF

    run "$VULN_TRACKER" parse --input "$TEST_TEMP_DIR/mock/special-chars.json"
    skip_if_not_ready "$status" "$output" "vuln-tracker.sh special chars"

    assert_exit_success "$status"
    assert_contains "$output" "@scope/pkg-name"
}

# ============================================================
# 帮助和版本信息
# ============================================================

# @test HELP-001: --help 显示使用说明
@test "HELP-001: vuln-tracker --help shows usage" {
    skip_if_not_executable "$VULN_TRACKER"

    run "$VULN_TRACKER" --help

    # --help 应该成功
    assert_exit_success "$status"

    # 应包含使用说明
    assert_contains_any "$output" "Usage" "usage" "USAGE" "scan" "trace"
}

# @test HELP-002: 无参数显示帮助
@test "HELP-002: vuln-tracker shows help with no arguments" {
    skip_if_not_executable "$VULN_TRACKER"

    run "$VULN_TRACKER"

    # 无参数可以显示帮助或返回错误
    # 重要的是有输出
    [ -n "$output" ]
}
