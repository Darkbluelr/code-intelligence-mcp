# Spec: ADR 解析与关联（adr-parser）

> **Change ID**: `augment-parity-final-gaps`
> **Capability**: adr-parser
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-16

---

## 概述

本规格定义 ADR（Architecture Decision Records）解析与关联功能。系统应能够：
1. 解析 MADR 和 Nygard 格式的 ADR 文件
2. 提取关键词并关联到代码模块
3. 生成 ADR_RELATED 边写入 graph.db

---

## Requirements（需求）

### REQ-ADR-001：ADR 文件发现

系统应自动发现项目中的 ADR 文件：

| 搜索路径 | 优先级 |
|----------|--------|
| `docs/adr/*.md` | 1（最高） |
| `doc/adr/*.md` | 2 |
| `ADR/*.md` | 3 |
| `adr/*.md` | 4 |

**约束**：
- 按优先级顺序搜索，找到第一个非空目录后停止
- 无 ADR 目录时返回空列表，不报错

### REQ-ADR-002：MADR 格式解析

系统应支持 MADR（Markdown Architectural Decision Records）格式：

```markdown
# ADR-001: 使用 SQLite 作为图存储

## Status
Accepted

## Context
需要一个轻量级的图存储解决方案...

## Decision
使用 SQLite + WAL 模式...

## Consequences
- 正面：部署简单、无外部依赖
- 负面：大规模扩展受限
```

**提取字段**：
| 字段 | 必填 | 来源 |
|------|------|------|
| id | 是 | 标题中的 ADR-xxx |
| title | 是 | 标题（去除 ADR-xxx 前缀） |
| status | 是 | ## Status 章节内容 |
| context | 否 | ## Context 章节内容 |
| decision | 否 | ## Decision 章节内容 |
| consequences | 否 | ## Consequences 章节内容 |

### REQ-ADR-003：Nygard 格式解析

系统应支持 Michael Nygard 原始 ADR 格式：

```markdown
# 1. Record architecture decisions

Date: 2026-01-16

## Status

Accepted

## Context

We need to record...

## Decision

We will use Architecture Decision Records...

## Consequences

We will have a trail...
```

**提取字段**：
- id：从标题提取数字
- date：Date 行
- status、context、decision、consequences：同 MADR

### REQ-ADR-004：关键词提取

系统应从 ADR 中提取技术关键词：

**提取来源**：
- Decision 章节
- Context 章节
- Title

**提取规则**：
1. 识别代码标识符（`backtick` 包裹）
2. 识别技术术语（PascalCase、camelCase、SCREAMING_CASE）
3. 识别文件路径（含 `/` 或 `.ts`、`.sh` 等扩展名）

**过滤规则**：
- 过滤通用词汇（the, a, is, we, will 等）
- 过滤过短词汇（< 3 字符）

### REQ-ADR-005：代码关联

系统应将提取的关键词关联到 graph.db 中的代码节点：

**匹配算法**：
1. 精确匹配：关键词 = 节点 symbol 名
2. 文件路径匹配：关键词 = 节点 file_path（部分匹配）
3. 模糊匹配：关键词包含在 symbol 中

**关联边生成**：
- edge_type: `ADR_RELATED`
- source_id: `adr:<adr_id>`（如 `adr:ADR-001`）
- target_id: 匹配的代码节点 ID

### REQ-ADR-006：输出格式

ADR 解析结果应输出为 JSON：

```json
{
  "adrs": [
    {
      "id": "ADR-001",
      "title": "使用 SQLite 作为图存储",
      "status": "Accepted",
      "file_path": "docs/adr/0001-use-sqlite.md",
      "keywords": ["SQLite", "graph-store", "WAL"],
      "related_nodes": ["sym:graph-store.sh", "sym:graph.db"]
    }
  ],
  "edges_generated": 5
}
```

### REQ-ADR-007：索引文件生成

系统应生成 ADR 索引文件用于快速查询：

- 文件路径：`.devbooks/adr-index.json`
- 内容：所有 ADR 的元数据和关联关系
- 更新策略：增量更新（检测 ADR 文件 mtime）

---

## Scenarios（场景）

### SC-ADR-001：解析 MADR 格式 ADR

**Given**:
- 存在 `docs/adr/0001-use-sqlite.md` 文件
- 文件使用 MADR 格式
**When**: 执行 `adr-parser.sh parse docs/adr/0001-use-sqlite.md`
**Then**:
- 正确提取 id: `ADR-001`
- 正确提取 status: `Accepted`
- 正确提取 decision 内容
- 输出 JSON 格式解析结果

### SC-ADR-002：解析 Nygard 格式 ADR

**Given**:
- 存在 `docs/adr/0001-record-decisions.md` 文件
- 文件使用 Nygard 格式（标题为 `# 1. Record architecture decisions`）
**When**: 执行 `adr-parser.sh parse docs/adr/0001-record-decisions.md`
**Then**:
- 正确提取 id: `1`
- 正确提取 date
- 正确提取 status、context、decision、consequences
- 输出 JSON 格式解析结果

### SC-ADR-003：关键词提取

**Given**:
- ADR Decision 章节包含：`We will use SQLite with WAL mode for the graph-store.sh`
**When**: 执行关键词提取
**Then**:
- 提取关键词：`SQLite`, `WAL`, `graph-store.sh`
- 不提取：`We`, `will`, `use`, `with`, `mode`, `for`, `the`

### SC-ADR-004：代码关联

**Given**:
- ADR 提取关键词：`graph-store`
- graph.db 包含节点：`scripts/graph-store.sh::main`
**When**: 执行关联
**Then**:
- 生成 ADR_RELATED 边
- source_id: `adr:ADR-001`
- target_id: `scripts/graph-store.sh::main`

### SC-ADR-005：无 ADR 目录

**Given**:
- 项目无 `docs/adr/`、`doc/adr/`、`ADR/`、`adr/` 目录
**When**: 执行 `adr-parser.sh scan`
**Then**:
- 返回空列表 `{"adrs": [], "edges_generated": 0}`
- 不报错
- 退出码 0

### SC-ADR-006：批量解析

**Given**:
- `docs/adr/` 目录包含 3 个 ADR 文件
**When**: 执行 `adr-parser.sh scan --link`
**Then**:
- 解析所有 3 个 ADR 文件
- 生成关联边写入 graph.db
- 生成 `.devbooks/adr-index.json` 索引文件
- 输出处理摘要

### SC-ADR-007：混合格式处理

**Given**:
- `docs/adr/` 包含 MADR 和 Nygard 混合格式的 ADR
**When**: 执行 `adr-parser.sh scan`
**Then**:
- 正确识别并解析两种格式
- 无格式解析错误

### SC-ADR-008：无效 ADR 格式

**Given**:
- ADR 文件无 ## Status 章节
**When**: 执行解析
**Then**:
- 记录警告：`ADR 缺少 Status 章节`
- status 字段为 `Unknown`
- 继续处理，不中断

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-ADR-001 | SC-ADR-005, SC-ADR-006 | AC-G03 |
| REQ-ADR-002 | SC-ADR-001, SC-ADR-007 | AC-G03 |
| REQ-ADR-003 | SC-ADR-002, SC-ADR-007 | AC-G03 |
| REQ-ADR-004 | SC-ADR-003 | AC-G03 |
| REQ-ADR-005 | SC-ADR-004 | AC-G03 |
| REQ-ADR-006 | SC-ADR-001, SC-ADR-005 | AC-G03 |
| REQ-ADR-007 | SC-ADR-006 | AC-G03 |

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-ADR-001 | behavior | REQ-ADR-002, SC-ADR-001 | MADR 格式解析 |
| CT-ADR-002 | behavior | REQ-ADR-003, SC-ADR-002 | Nygard 格式解析 |
| CT-ADR-003 | behavior | REQ-ADR-004, SC-ADR-003 | 关键词提取 |
| CT-ADR-004 | behavior | REQ-ADR-005, SC-ADR-004 | 代码关联 |
| CT-ADR-005 | behavior | REQ-ADR-001, SC-ADR-005 | 无 ADR 目录 |
| CT-ADR-006 | schema | REQ-ADR-006 | 输出 JSON Schema |

---

## 命令行接口（CLI）

```bash
adr-parser.sh <command> [options]
```

| 命令 | 说明 |
|------|------|
| `parse <file>` | 解析单个 ADR 文件 |
| `scan [--link]` | 扫描所有 ADR 文件，可选生成关联边 |
| `keywords <file>` | 提取单个 ADR 的关键词 |
| `status` | 显示 ADR 索引状态 |

| 选项 | 说明 |
|------|------|
| `--format json|text` | 输出格式（默认 json） |
| `--link` | 生成关联边写入 graph.db |
| `--adr-dir <path>` | 指定 ADR 目录（覆盖自动发现） |
