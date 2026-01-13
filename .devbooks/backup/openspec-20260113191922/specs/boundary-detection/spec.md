# Spec: boundary-detection

> **Version**: 1.0.0
> **Status**: Active
> **Owner**: Spec Owner
> **Created**: 2026-01-11
> **Last Verified**: 2026-01-11
> **Freshness Check**: 90 days
> **Source Change**: enhance-code-intelligence

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
