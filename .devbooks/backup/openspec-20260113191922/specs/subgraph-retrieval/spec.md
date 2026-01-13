# Spec: subgraph-retrieval

> **Version**: 1.0.0
> **Status**: Active
> **Owner**: Spec Owner
> **Created**: 2026-01-11
> **Last Verified**: 2026-01-11
> **Freshness Check**: 90 days
> **Source Change**: enhance-code-intelligence

---

## Purpose

提供子图检索能力，基于 CKB 图数据库返回符号的调用/引用边关系，支持边界过滤和深度控制，增强 Graph-RAG 上下文质量。

---

## Requirements

### Requirement: Subgraph Retrieval with Edge Relations

系统 SHALL 在检索代码时保留符号间的边关系（调用、引用、继承等），而非返回孤立的线性列表。

#### Scenario: Retrieve subgraph with call edges

- **GIVEN** 查询符号 `handleToolCall`
- **AND** CKB MCP 可用
- **WHEN** 执行子图检索
- **THEN** 返回包含该符号的子图
- **AND** 子图包含 `--calls-->` 边关系
- **AND** 子图包含调用者和被调用者

Trace: AC-003

#### Scenario: Retrieve subgraph with reference edges

- **GIVEN** 查询符号 `TOOLS` 常量
- **AND** CKB MCP 可用
- **WHEN** 执行子图检索
- **THEN** 返回包含该符号的子图
- **AND** 子图包含 `--refs-->` 边关系

Trace: AC-003

#### Scenario: Subgraph depth control

- **GIVEN** 查询符号 `main`
- **AND** 指定深度为 3
- **WHEN** 执行子图检索
- **THEN** 返回从该符号出发深度不超过 3 的子图
- **AND** 深度超过 3 的节点不包含在结果中

Trace: AC-003

#### Scenario: Subgraph max depth exceeded

- **GIVEN** 查询符号需要深度 6 的遍历
- **AND** 最大深度限制为 5
- **WHEN** 执行子图检索
- **THEN** 返回深度 5 的子图
- **AND** 输出警告 "深度已达最大值 5，结果可能不完整"

Trace: AC-003

---

### Requirement: Graceful Degradation to Linear List

系统 SHALL 在 CKB MCP 不可用时降级为线性列表检索。

#### Scenario: CKB unavailable fallback

- **GIVEN** CKB MCP 不可用
- **WHEN** 执行子图检索
- **THEN** 降级使用 ripgrep 文本搜索
- **AND** 返回线性列表结果（无边关系）
- **AND** 输出提示 "CKB 不可用，降级为文本搜索"

Trace: AC-003

---

## Data Examples

### Subgraph Output Format

```json
{
  "nodes": [
    {"id": "ckb:...:handleToolCall", "type": "function"},
    {"id": "ckb:...:runScript", "type": "function"},
    {"id": "ckb:...:TOOLS", "type": "constant"}
  ],
  "edges": [
    {"from": "handleToolCall", "to": "runScript", "type": "calls"},
    {"from": "handleToolCall", "to": "TOOLS", "type": "refs"}
  ]
}
```

### Linear List Fallback Format

```json
{
  "results": [
    {"file": "src/server.ts", "line": 144, "match": "handleToolCall"},
    {"file": "src/server.ts", "line": 29, "match": "TOOLS"}
  ],
  "degraded": true,
  "reason": "CKB MCP unavailable"
}
```
