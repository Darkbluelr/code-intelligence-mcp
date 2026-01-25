---
last_referenced_by: algorithm-optimization-parity
last_verified: 2026-01-17
health: active
---

# Spec: boundary-detection

> **Version**: 1.1.0
> **Status**: Active
> **Owner**: Spec Owner
> **Created**: 2026-01-11
> **Last Verified**: 2026-01-17
> **Freshness Check**: 90 days
> **Source Change**: enhance-code-intelligence
> **Last Referenced By**: algorithm-optimization-parity

---

## Purpose

提供代码边界识别能力，区分用户代码、库代码、生成代码和配置文件，支持 Graph-RAG 搜索时过滤非用户代码，提升结果质量。

---

## Requirements

### Requirement: Code Boundary Detection

系统 SHALL 能够区分用户代码、库代码、生成代码和配置文件。

边界类型定义：
- **user**：用户编写的源代码（可修改）
- **library**：第三方库代码（不可修改）
- **generated**：工具生成的代码（禁止手动修改）
- **config**：配置文件（复制后可修改）

#### Scenario: Detect library code

- **GIVEN** 路径为 `node_modules/lodash/index.js`
- **WHEN** 执行边界检测
- **THEN** 返回边界类型为 `library`
- **AND** 置信度为 1.0

Trace: AC-004

#### Scenario: Detect generated code

- **GIVEN** 路径为 `dist/server.js`
- **WHEN** 执行边界检测
- **THEN** 返回边界类型为 `generated`
- **AND** 置信度为 1.0

Trace: AC-004

#### Scenario: Detect user code

- **GIVEN** 路径为 `src/server.ts`
- **AND** 该路径不匹配任何 library/generated/config 规则
- **WHEN** 执行边界检测
- **THEN** 返回边界类型为 `user`
- **AND** 置信度为 1.0

Trace: AC-004

#### Scenario: Detect config file

- **GIVEN** 路径为 `config/boundaries.yaml`
- **WHEN** 执行边界检测
- **THEN** 返回边界类型为 `config`
- **AND** 置信度为 1.0

Trace: AC-004

---

### Requirement: Boundary Configuration with Glob Patterns

系统 SHALL 支持通过 glob 模式配置边界规则。

#### Scenario: Match glob pattern

- **GIVEN** 配置 `library: ["**/vendor/**"]`
- **AND** 路径为 `src/vendor/legacy/utils.js`
- **WHEN** 执行边界检测
- **THEN** 返回边界类型为 `library`

Trace: AC-004

#### Scenario: Custom override

- **GIVEN** 默认配置将 `dist/` 标记为 `generated`
- **AND** 用户在 overrides 中指定 `dist/custom.js` 为 `user`
- **WHEN** 检测 `dist/custom.js`
- **THEN** 返回边界类型为 `user`（override 优先）

Trace: AC-004

---

### Requirement: Boundary MCP Tool

系统 SHALL 通过 MCP 工具 `ci_boundary` 暴露边界检测能力。

#### Scenario: Invoke ci_boundary

- **GIVEN** MCP 服务器运行中
- **WHEN** 调用 `ci_boundary` 工具，参数 `path=node_modules/express/index.js`
- **THEN** 返回 `{type: "library", confidence: 1.0}`

Trace: AC-004, AC-008

---

## Data Examples

### Default Boundary Configuration

| 类型 | 默认 Glob 模式 |
|------|----------------|
| library | `node_modules/**`, `**/vendor/**`, `**/.yarn/**` |
| generated | `dist/**`, `build/**`, `**/*.generated.*` |
| config | `config/**`, `*.config.js`, `*.config.ts` |
| user | (其他所有路径) |

### Detection Output

| 路径 | 类型 | 置信度 |
|------|------|--------|
| `src/server.ts` | user | 1.0 |
| `node_modules/express/index.js` | library | 1.0 |
| `dist/server.js` | generated | 1.0 |
| `tsconfig.json` | config | 1.0 |

---

## Fast Path Optimization (Added by algorithm-optimization-parity)

### REQ-BD-001: 快速路径规则

**描述**: 对常见库代码路径使用快速匹配规则，避免完整边界检测。

**快速规则列表**:
- `node_modules/*` → 库代码
- `vendor/*` → 库代码
- `.git/*` → 库代码
- `dist/*` → 库代码
- `build/*` → 库代码

---

### REQ-BD-002: 快速路径优先

**描述**: 快速规则匹配成功后，不调用完整边界检测器。

**性能要求**: 快速路径检测 < 1ms

---

### REQ-BD-003: 完整检测降级

**描述**: 快速规则未匹配时，调用完整边界检测器。

---

## Fast Path Contract Tests

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-BD-001 | behavior | node_modules 快速匹配 |
| CT-BD-002 | behavior | vendor 快速匹配 |
| CT-BD-003 | behavior | 用户代码路径 |
| CT-BD-004 | boundary | 嵌套路径处理 |
| CT-BD-005 | behavior | dist 目录 |
| CT-BD-006 | performance | 批量检测 < 100ms |
