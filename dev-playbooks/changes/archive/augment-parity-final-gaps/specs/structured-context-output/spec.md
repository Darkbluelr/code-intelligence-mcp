# Spec: 结构化上下文输出（structured-context-output）

> **Change ID**: `augment-parity-final-gaps`
> **Capability**: structured-context-output
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-16

---

## 概述

本规格定义结构化上下文输出功能。系统应将上下文输出从自由文本升级为 5 层结构化模板，提升 AI 理解效率。

---

## Requirements（需求）

### REQ-SCO-001：5 层结构化输出

系统应输出 5 层结构化上下文：

| 层级 | 字段名 | 内容 |
|------|--------|------|
| 1 | `project_profile` | 项目画像（名称/类型/技术栈/架构模式/关键约束） |
| 2 | `current_state` | 当前状态（索引状态/热点文件/最近提交） |
| 3 | `task_context` | 任务上下文（意图分析/相关代码片段/调用链） |
| 4 | `recommended_tools` | 推荐工具（基于意图的工具推荐和参数建议） |
| 5 | `constraints` | 约束提醒（架构约束/安全约束） |

### REQ-SCO-002：project_profile 结构

项目画像层应包含以下字段：

```json
{
  "project_profile": {
    "name": "code-intelligence-mcp",
    "type": "mcp-server",
    "tech_stack": ["Node.js", "TypeScript", "Bash", "SQLite"],
    "architecture": "thin-shell",
    "key_constraints": [
      "CON-TECH-002: MCP Server 使用 Node.js 薄壳调用 Shell 脚本"
    ]
  }
}
```

**数据来源**：
- `dev-playbooks/specs/_meta/project-profile.md`（如存在）
- `package.json`（技术栈推断）
- 代码目录结构分析

### REQ-SCO-003：current_state 结构

当前状态层应包含以下字段：

```json
{
  "current_state": {
    "index_status": "ready|stale|missing",
    "hotspot_files": ["src/server.ts", "scripts/graph-store.sh", ...],
    "recent_commits": [
      "abc1234: feat: add path query",
      "def5678: fix: edge type validation"
    ]
  }
}
```

**数据来源**：
- `index_status`：检查 SCIP/Embedding/CKB 索引状态
- `hotspot_files`：调用 `hotspot-analyzer.sh` 获取 Top 5
- `recent_commits`：`git log -3 --oneline`

**约束**：
- `hotspot_files` 最多 5 个
- `recent_commits` 最多 3 条

### REQ-SCO-004：task_context 结构

任务上下文层应包含以下字段：

```json
{
  "task_context": {
    "intent_analysis": {
      "primary_intent": "explore|modify|debug|understand",
      "target_scope": "file|module|project",
      "confidence": 0.85
    },
    "relevant_snippets": [
      {
        "file": "src/server.ts",
        "lines": "10-25",
        "relevance": 0.9
      }
    ],
    "call_chains": [
      {
        "root": "main",
        "chain": ["main", "startServer", "handleRequest"]
      }
    ]
  }
}
```

**数据来源**：
- `intent_analysis`：调用 `intent-learner.sh analyze`
- `relevant_snippets`：基于意图的相关代码检索
- `call_chains`：调用 `call-chain.sh`（如相关）

### REQ-SCO-005：recommended_tools 结构

推荐工具层应包含以下字段：

```json
{
  "recommended_tools": [
    {
      "tool": "ci_call_chain",
      "reason": "查询调用链有助于理解函数关系",
      "suggested_params": {
        "symbol": "handleRequest",
        "depth": 3
      }
    }
  ]
}
```

**推荐规则**：
| 意图 | 推荐工具 |
|------|----------|
| explore | ci_search, ci_graph_rag |
| modify | ci_call_chain, ci_bug_locate |
| debug | ci_bug_locate, ci_call_chain |
| understand | ci_complexity, ci_graph_rag |

### REQ-SCO-006：constraints 结构

约束提醒层应包含以下字段：

```json
{
  "constraints": {
    "architectural": [
      "分层规则：shared ← core ← integration",
      "禁止：scripts/*.sh → src/*.ts"
    ],
    "security": [
      "敏感文件：.env, credentials.json"
    ]
  }
}
```

**数据来源**：
- `architectural`：从 `c4.md` 或架构规则配置提取
- `security`：检测敏感文件模式

### REQ-SCO-007：输出格式

系统应支持两种输出格式：

| 格式 | 选项 | 说明 |
|------|------|------|
| JSON | `--format json` | 完整 JSON 结构（默认） |
| Text | `--format text` | 人类可读的文本摘要 |

---

## Scenarios（场景）

### SC-SCO-001：完整结构化输出

**Given**:
- 项目已初始化
- SCIP 索引可用
**When**: 执行 `augment-context-global.sh --format json`
**Then**:
- 输出包含 `project_profile` 字段
- 输出包含 `current_state` 字段
- 输出包含 `task_context` 字段
- 输出包含 `recommended_tools` 字段
- 输出包含 `constraints` 字段
- JSON 格式有效

### SC-SCO-002：project_profile 提取

**Given**:
- 存在 `package.json`，技术栈为 Node.js + TypeScript
**When**: 构建 project_profile
**Then**:
- `tech_stack` 包含 `Node.js` 和 `TypeScript`
- `name` 从 package.json 提取

### SC-SCO-003：current_state 提取

**Given**:
- SCIP 索引存在且新鲜
- 最近有 3 次提交
**When**: 构建 current_state
**Then**:
- `index_status` = `ready`
- `hotspot_files` 包含 Top 5 热点文件
- `recent_commits` 包含 3 条提交记录

### SC-SCO-004：task_context 意图分析

**Given**:
- 用户查询：`how does the auth module work?`
**When**: 分析意图并构建 task_context
**Then**:
- `intent_analysis.primary_intent` = `understand`
- `relevant_snippets` 包含 auth 相关代码
- 推荐工具包含 `ci_graph_rag`

### SC-SCO-005：recommended_tools 生成

**Given**:
- 意图分析结果：`debug`
**When**: 生成推荐工具
**Then**:
- 推荐列表包含 `ci_bug_locate`
- 推荐列表包含 `ci_call_chain`
- 每个工具有 `reason` 说明

### SC-SCO-006：constraints 提取

**Given**:
- 存在 `dev-playbooks/specs/architecture/c4.md`
- C4 文档定义了分层约束
**When**: 构建 constraints
**Then**:
- `architectural` 包含分层规则
- `security` 包含敏感文件提醒

### SC-SCO-007：索引不可用降级

**Given**:
- SCIP 索引不存在
**When**: 构建 current_state
**Then**:
- `index_status` = `missing`
- `hotspot_files` 基于 Git churn 降级计算
- 不报错

### SC-SCO-008：文本格式输出

**Given**:
- 用户指定 `--format text`
**When**: 执行结构化输出
**Then**:
- 输出人类可读文本
- 包含项目摘要
- 包含热点文件列表
- 包含推荐工具

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-SCO-001 | SC-SCO-001 | AC-G11 |
| REQ-SCO-002 | SC-SCO-002 | AC-G11 |
| REQ-SCO-003 | SC-SCO-003, SC-SCO-007 | AC-G11 |
| REQ-SCO-004 | SC-SCO-004 | AC-G11 |
| REQ-SCO-005 | SC-SCO-005 | AC-G11 |
| REQ-SCO-006 | SC-SCO-006 | AC-G11 |
| REQ-SCO-007 | SC-SCO-001, SC-SCO-008 | AC-G11 |

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-SCO-001 | schema | REQ-SCO-001 | 完整输出 Schema 验证 |
| CT-SCO-002 | behavior | REQ-SCO-002, SC-SCO-002 | project_profile 提取 |
| CT-SCO-003 | behavior | REQ-SCO-003, SC-SCO-003 | current_state 提取 |
| CT-SCO-004 | behavior | REQ-SCO-004, SC-SCO-004 | task_context 意图分析 |
| CT-SCO-005 | behavior | REQ-SCO-005, SC-SCO-005 | recommended_tools 生成 |
| CT-SCO-006 | behavior | REQ-SCO-006, SC-SCO-006 | constraints 提取 |
| CT-SCO-007 | behavior | REQ-SCO-003, SC-SCO-007 | 索引不可用降级 |

---

## JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["project_profile", "current_state", "task_context", "recommended_tools", "constraints"],
  "properties": {
    "project_profile": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "type": { "type": "string" },
        "tech_stack": { "type": "array", "items": { "type": "string" } },
        "architecture": { "type": "string" },
        "key_constraints": { "type": "array", "items": { "type": "string" } }
      }
    },
    "current_state": {
      "type": "object",
      "properties": {
        "index_status": { "type": "string", "enum": ["ready", "stale", "missing"] },
        "hotspot_files": { "type": "array", "items": { "type": "string" }, "maxItems": 5 },
        "recent_commits": { "type": "array", "items": { "type": "string" }, "maxItems": 3 }
      }
    },
    "task_context": {
      "type": "object",
      "properties": {
        "intent_analysis": {
          "type": "object",
          "properties": {
            "primary_intent": { "type": "string", "enum": ["explore", "modify", "debug", "understand"] },
            "target_scope": { "type": "string", "enum": ["file", "module", "project"] },
            "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
          }
        },
        "relevant_snippets": { "type": "array" },
        "call_chains": { "type": "array" }
      }
    },
    "recommended_tools": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "tool": { "type": "string" },
          "reason": { "type": "string" },
          "suggested_params": { "type": "object" }
        }
      }
    },
    "constraints": {
      "type": "object",
      "properties": {
        "architectural": { "type": "array", "items": { "type": "string" } },
        "security": { "type": "array", "items": { "type": "string" } }
      }
    }
  }
}
```
