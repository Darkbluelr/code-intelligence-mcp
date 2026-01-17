# Spec: Dependency Guard（架构守护）

> **Change ID**: `augment-upgrade-phase2`
> **Capability**: dependency-guard
> **Version**: 1.0.0
> **Status**: Draft

---

## Requirements

### REQ-GUARD-001: 循环依赖检测

系统必须检测模块间的循环依赖：

| 检测范围 | 说明 |
|----------|------|
| TypeScript | `import`/`require` 语句 |
| Bash | `source`/`.` 语句 |

**算法**：DFS + 访问状态标记（WHITE/GRAY/BLACK）

**约束**：
- 检测覆盖率 >= 95%
- 误报率 < 5%
- 支持白名单排除（如 `src/types/**`）

---

### REQ-GUARD-002: 架构规则校验

系统必须基于 `config/arch-rules.yaml` 校验依赖关系：

| 规则类型 | 语法 | 说明 |
|----------|------|------|
| 禁止导入 | `from` + `cannot_import` | 源文件不能导入指定模块 |
| 循环检测 | `type: cycle-detection` | 在指定范围内检测循环 |

**规则优先级**：`rule.severity` > `config.on_violation`

---

### REQ-GUARD-003: 违规报告格式

架构违规必须输出以下 JSON 格式：

```json
{
  "schema_version": "1.0.0",
  "violations": [
    {
      "rule": "<rule_name>",
      "severity": "error|warning",
      "source": "<source_file>",
      "target": "<imported_module>",
      "line": <line_number>,
      "message": "<human_readable_message>"
    }
  ],
  "cycles": [
    {
      "path": ["a.ts", "b.ts", "c.ts", "a.ts"],
      "severity": "error"
    }
  ],
  "summary": {
    "total_violations": <number>,
    "total_cycles": <number>,
    "blocked": <boolean>
  }
}
```

---

### REQ-GUARD-004: Pre-commit 集成

系统必须提供 Pre-commit Hook：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| 检查范围 | Staged 文件 | `git diff --cached --name-only` |
| `--with-deps` | 禁用 | 扩展到一级 import 依赖 |
| 耗时限制 | 2s（仅 staged）/ 5s（含依赖） | 超时则跳过 |

**约束**：
- 默认警告不阻断
- 可配置为阻断（`config.on_violation: block`）

---

### REQ-GUARD-005: MCP 工具接口

新增 MCP 工具 `ci_arch_check`：

```typescript
{
  name: "ci_arch_check",
  inputSchema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Target directory (default: .)" },
      format: { type: "string", enum: ["text", "json"], description: "Output format" },
      rules: { type: "string", description: "Path to arch-rules.yaml" }
    }
  }
}
```

**约束**：
- 向后兼容：不影响现有 8 个工具
- 默认使用 `config/arch-rules.yaml`

---

## Scenarios

### SC-GUARD-001: 检测简单循环依赖

**Given**: 文件 A 导入 B，B 导入 A
**When**: 执行 `dependency-guard.sh --scope src/`
**Then**:
- 检测到循环 `["src/a.ts", "src/b.ts", "src/a.ts"]`
- 输出 severity = "error"
- summary.total_cycles = 1

---

### SC-GUARD-002: 检测多节点循环

**Given**: A → B → C → D → A（4 节点循环）
**When**: 执行循环检测
**Then**:
- 检测到完整循环路径
- 路径长度 = 5（含回到起点）

---

### SC-GUARD-003: 白名单排除

**Given**: `arch-rules.yaml` 中配置 `whitelist: ["src/types/**"]`
**When**: `src/types/common.ts` 参与循环
**Then**:
- 不报告该循环
- 日志记录白名单命中

---

### SC-GUARD-004: 架构规则违规

**Given**: 规则 `ui-no-direct-db: from src/ui/** cannot_import src/db/**`
**When**: `src/ui/Dashboard.tsx` 导入 `src/db/connection.ts`
**Then**:
- 输出违规记录
- message = "UI 组件不能直接导入数据库模块"
- line = 导入语句行号

---

### SC-GUARD-005: Pre-commit 仅检查 Staged

**Given**: 3 个 Staged 文件 + 10 个未 Staged 修改
**When**: 执行 Pre-commit Hook
**Then**:
- 仅检查 3 个 Staged 文件
- 不检查未 Staged 文件
- 耗时 < 2s

---

### SC-GUARD-006: Pre-commit 含依赖检查

**Given**: 10 个 Staged 文件，共有 50 个一级依赖
**When**: 执行 Pre-commit Hook with `--with-deps`
**Then**:
- 检查 10 + 50 = 60 个文件
- 耗时 < 5s

---

### SC-GUARD-007: 违规警告模式

**Given**: `config.on_violation: warn`
**When**: 检测到架构违规
**Then**:
- 输出警告信息
- summary.blocked = false
- Pre-commit 不阻断

---

### SC-GUARD-008: 违规阻断模式

**Given**: `config.on_violation: block`
**When**: 检测到 severity = "error" 的违规
**Then**:
- 输出错误信息
- summary.blocked = true
- Pre-commit 阻断（exit 1）

---

### SC-GUARD-009: 误报率验证

**Given**: 测试集包含 10+ 真循环 + 10+ 非循环样本
**When**: 执行检测
**Then**:
- 真循环检出率 >= 95%
- 非循环误报率 < 5%

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-GUARD-001 | behavior | REQ-GUARD-001, SC-GUARD-001 | 简单循环检测 |
| CT-GUARD-002 | behavior | REQ-GUARD-001, SC-GUARD-002 | 多节点循环检测 |
| CT-GUARD-003 | behavior | REQ-GUARD-001, SC-GUARD-003 | 白名单排除 |
| CT-GUARD-004 | behavior | REQ-GUARD-002, SC-GUARD-004 | 规则违规检测 |
| CT-GUARD-005 | behavior | REQ-GUARD-004, SC-GUARD-005 | Pre-commit staged only |
| CT-GUARD-006 | behavior | REQ-GUARD-004, SC-GUARD-006 | Pre-commit with deps |
| CT-GUARD-007 | behavior | REQ-GUARD-002, SC-GUARD-007 | 警告模式 |
| CT-GUARD-008 | behavior | REQ-GUARD-002, SC-GUARD-008 | 阻断模式 |
| CT-GUARD-009 | behavior | REQ-GUARD-001, SC-GUARD-009 | 误报率 < 5% |
| CT-GUARD-010 | schema | REQ-GUARD-003 | 违规报告格式 |
| CT-GUARD-011 | contract | REQ-GUARD-005 | MCP 工具签名 |

---

## 配置 Schema

### config/arch-rules.yaml

```yaml
schema_version: "1.0.0"

rules:
  - name: "<rule_name>"
    description: "<human_readable>"
    from: "<glob_pattern>"
    cannot_import:
      - "<glob_pattern>"
    severity: "error|warning"

  - name: "no-circular-deps"
    type: "cycle-detection"
    scope: "<glob_pattern>"
    severity: "error"
    whitelist:
      - "<glob_pattern>"

config:
  on_violation: "warn|block"
  ignore:
    - "<glob_pattern>"
```

---

## 脚本接口

```bash
# 检测循环依赖
dependency-guard.sh --cycles --scope src/

# 校验架构规则
dependency-guard.sh --rules config/arch-rules.yaml

# 完整检查
dependency-guard.sh --all --format json

# Pre-commit 模式
dependency-guard.sh --pre-commit [--with-deps]
```

| 参数 | 说明 |
|------|------|
| `--cycles` | 仅检测循环依赖 |
| `--rules <file>` | 指定规则文件 |
| `--scope <pattern>` | 限定检测范围 |
| `--format text\|json` | 输出格式 |
| `--pre-commit` | Pre-commit 模式 |
| `--with-deps` | 包含一级依赖 |
