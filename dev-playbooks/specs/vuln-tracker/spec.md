# 规格：M7 安全漏洞基础追踪

> **模块 ID**: `vuln-tracker`
> **Change ID**: `achieve-augment-full-parity`
> **Date**: 2026-01-16
> **Status**: Draft

---

## Requirements（需求）

### REQ-VT-001: npm audit 集成

系统必须集成 npm audit 进行依赖漏洞扫描。

**约束**：
- 支持 npm 6.x 和 7.x+ 两种输出格式
- 自动检测 npm 版本并适配解析器
- 无 npm audit 时输出警告并跳过

### REQ-VT-002: 严重性等级过滤

系统必须支持按严重性等级过滤漏洞。

**约束**：
- 等级顺序：low < moderate < high < critical
- 默认阈值：moderate（包含 moderate、high、critical）
- 可配置：通过 `--severity` 参数或 `VULN_SEVERITY_THRESHOLD` 环境变量

### REQ-VT-003: 依赖传播追踪

系统必须追踪漏洞依赖的传播路径。

**约束**：
- 识别直接依赖和间接依赖
- 显示受影响的项目文件
- 与 graph.db 依赖图关联

### REQ-VT-004: 降级策略

外部工具不可用时必须优雅降级。

**约束**：
- npm audit 不可用：跳过并输出警告
- osv-scanner 不可用：降级到仅 npm audit

---

## Scenarios（场景）

### SC-VT-001: 基本漏洞扫描

**Given**：
- 项目 package.json 存在
- npm audit 可用

**When**：
- 调用 `vuln-tracker.sh scan`

**Then**：
- 系统执行 npm audit --json
- 解析漏洞列表
- 按严重性分类输出
- 返回漏洞摘要

**验证**：`tests/vuln-tracker.bats::test_basic_scan`

### SC-VT-002: npm 7+ 格式解析

**Given**：
- npm 版本 >= 7
- npm audit 返回新格式 JSON

**When**：
- 解析扫描结果

**Then**：
- 正确解析 `.vulnerabilities` 结构
- 提取 name、severity、via、effects 字段

**验证**：`tests/vuln-tracker.bats::test_npm7_format`

### SC-VT-003: npm 6.x 格式解析

**Given**：
- npm 版本 < 7
- npm audit 返回旧格式 JSON

**When**：
- 解析扫描结果

**Then**：
- 正确解析 `.advisories` 结构
- 提取 module_name、severity、title、findings 字段

**验证**：`tests/vuln-tracker.bats::test_npm6_format`

### SC-VT-004: 严重性阈值过滤

**Given**：
- 扫描结果包含 low、moderate、high、critical 漏洞
- 阈值设置为 high

**When**：
- 调用 `vuln-tracker.sh scan --severity high`

**Then**：
- 仅返回 high 和 critical 漏洞
- low 和 moderate 漏洞被过滤

**验证**：`tests/vuln-tracker.bats::test_severity_filter`

### SC-VT-005: 依赖传播追踪

**Given**：
- 漏洞存在于间接依赖 `lodash@4.17.0`
- 直接依赖 `express` → 间接依赖 `lodash`

**When**：
- 调用 `vuln-tracker.sh trace lodash`

**Then**：
- 显示依赖链：project → express → lodash
- 列出受影响的项目文件（使用 lodash 的文件）

**验证**：`tests/vuln-tracker.bats::test_dependency_trace`

### SC-VT-006: npm audit 不可用降级

**Given**：
- npm audit 执行失败或不可用

**When**：
- 调用 `vuln-tracker.sh scan`

**Then**：
- 输出警告："npm audit 不可用，跳过漏洞扫描"
- 返回空结果
- 退出码为 0（非错误）

**验证**：`tests/vuln-tracker.bats::test_npm_audit_fallback`

### SC-VT-007: JSON 输出格式

**Given**：
- 扫描发现漏洞

**When**：
- 调用 `vuln-tracker.sh scan --format json`

**Then**：
- 输出有效 JSON
- 包含 vulnerabilities 数组
- 每个漏洞包含 name、severity、description、path

**验证**：`tests/vuln-tracker.bats::test_json_output`

### SC-VT-008: Markdown 输出格式

**Given**：
- 扫描发现漏洞

**When**：
- 调用 `vuln-tracker.sh scan --format md`

**Then**：
- 输出 Markdown 格式报告
- 包含表格和严重性徽章
- 可嵌入文档

**验证**：`tests/vuln-tracker.bats::test_markdown_output`

### SC-VT-009: 无漏洞结果

**Given**：
- 项目无已知漏洞

**When**：
- 调用 `vuln-tracker.sh scan`

**Then**：
- 输出"未发现漏洞"
- 返回空漏洞列表
- 退出码为 0

**验证**：`tests/vuln-tracker.bats::test_no_vulnerabilities`

### SC-VT-010: 开发依赖包含/排除

**Given**：
- 漏洞存在于 devDependencies

**When**：
- 调用 `vuln-tracker.sh scan --include-dev`
- 或 `vuln-tracker.sh scan`（不含 --include-dev）

**Then**：
- 使用 --include-dev 时包含开发依赖漏洞
- 不使用时仅报告生产依赖漏洞

**验证**：`tests/vuln-tracker.bats::test_dev_dependencies`

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios |
|-------------|-----------|
| REQ-VT-001 | SC-VT-001, SC-VT-002, SC-VT-003 |
| REQ-VT-002 | SC-VT-004 |
| REQ-VT-003 | SC-VT-005 |
| REQ-VT-004 | SC-VT-006 |

| Scenario | Test ID |
|----------|---------|
| SC-VT-001 | `tests/vuln-tracker.bats::test_basic_scan` |
| SC-VT-002 | `tests/vuln-tracker.bats::test_npm7_format` |
| SC-VT-003 | `tests/vuln-tracker.bats::test_npm6_format` |
| SC-VT-004 | `tests/vuln-tracker.bats::test_severity_filter` |
| SC-VT-005 | `tests/vuln-tracker.bats::test_dependency_trace` |
| SC-VT-006 | `tests/vuln-tracker.bats::test_npm_audit_fallback` |
| SC-VT-007 | `tests/vuln-tracker.bats::test_json_output` |
| SC-VT-008 | `tests/vuln-tracker.bats::test_markdown_output` |
| SC-VT-009 | `tests/vuln-tracker.bats::test_no_vulnerabilities` |
| SC-VT-010 | `tests/vuln-tracker.bats::test_dev_dependencies` |

---

## 输出格式示例

### JSON 格式

```json
{
  "scan_time": "2026-01-16T10:30:00Z",
  "total": 3,
  "by_severity": {
    "critical": 1,
    "high": 1,
    "moderate": 1,
    "low": 0
  },
  "vulnerabilities": [
    {
      "name": "lodash",
      "version": "4.17.0",
      "severity": "critical",
      "title": "Prototype Pollution",
      "cwe": "CWE-1321",
      "path": ["express", "lodash"],
      "affected_files": ["src/utils.ts", "src/api.ts"]
    }
  ]
}
```

### Markdown 格式

```markdown
# 漏洞扫描报告

**扫描时间**: 2026-01-16 10:30:00
**漏洞总数**: 3

## 严重性分布

| 级别 | 数量 |
|------|------|
| 🔴 Critical | 1 |
| 🟠 High | 1 |
| 🟡 Moderate | 1 |
| 🟢 Low | 0 |

## 漏洞详情

### 🔴 lodash@4.17.0 - Prototype Pollution

- **严重性**: Critical
- **CWE**: CWE-1321
- **依赖路径**: express → lodash
- **受影响文件**: src/utils.ts, src/api.ts
```

---

## 严重性等级定义

| 等级 | 数值 | 说明 |
|------|------|------|
| low | 0 | 低风险，可延后处理 |
| moderate | 1 | 中等风险，建议尽快修复 |
| high | 2 | 高风险，应优先修复 |
| critical | 3 | 严重风险，必须立即修复 |
