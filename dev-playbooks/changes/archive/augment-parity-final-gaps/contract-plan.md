# 契约计划（Contract Plan）

> **Change ID**: `augment-parity-final-gaps`
> **Date**: 2026-01-16
> **Status**: Draft

---

## 概述

本文档整合变更包 `augment-parity-final-gaps` 中所有 API/Schema 变更的契约计划。

---

## 1. API 变更

### 1.1 graph-store.sh 新增命令

#### find-path（路径查询）

| 项目 | 内容 |
|------|------|
| 命令 | `graph-store.sh find-path --from <id> --to <id> [--max-depth <n>] [--edge-types <types>]` |
| 类型 | 新增 |
| 兼容性 | 向后兼容（新增命令） |

**输入参数**：
| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--from` | string | 是 | - | 源节点 ID |
| `--to` | string | 是 | - | 目标节点 ID |
| `--max-depth` | number | 否 | 10 | 最大搜索深度 |
| `--edge-types` | string | 否 | 全部 | 逗号分隔的边类型过滤 |

**输出 Schema**：
```json
{
  "found": "boolean",
  "path": [{ "node_id": "string", "symbol": "string", "file": "string" }],
  "edges": [{ "from": "string", "to": "string", "type": "string" }],
  "length": "number"
}
```

#### migrate（Schema 迁移）

| 项目 | 内容 |
|------|------|
| 命令 | `graph-store.sh migrate [--check|--apply|--status]` |
| 类型 | 新增 |
| 兼容性 | 向后兼容（新增命令） |

**子命令**：
| 子命令 | 输出 |
|--------|------|
| `--check` | `NEEDS_MIGRATION` 或 `UP_TO_DATE` |
| `--apply` | 迁移执行结果 |
| `--status` | Schema 状态和边类型分布 |

---

### 1.2 adr-parser.sh（新增脚本）

| 项目 | 内容 |
|------|------|
| 脚本 | `scripts/adr-parser.sh` |
| 类型 | 新增 |
| 兼容性 | N/A（新脚本） |

**命令**：
| 命令 | 说明 |
|------|------|
| `parse <file>` | 解析单个 ADR 文件 |
| `scan [--link]` | 扫描所有 ADR 文件 |
| `keywords <file>` | 提取关键词 |
| `status` | 显示索引状态 |

**输出 Schema（scan）**：
```json
{
  "adrs": [{
    "id": "string",
    "title": "string",
    "status": "string",
    "file_path": "string",
    "keywords": ["string"],
    "related_nodes": ["string"]
  }],
  "edges_generated": "number"
}
```

---

### 1.3 bug-locator.sh 新增参数

| 项目 | 内容 |
|------|------|
| 命令 | `bug-locator.sh locate <description> [--with-impact] [--impact-depth <n>]` |
| 类型 | 参数扩展 |
| 兼容性 | 向后兼容（可选参数） |

**新增参数**：
| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--with-impact` | flag | 否 | 启用影响分析 |
| `--impact-depth` | number | 3 | 影响分析深度 |
| `--impact-weight` | number | 0.2 | 影响范围权重 |

**扩展输出 Schema**：
```json
{
  "symbol": "string",
  "file": "string",
  "line": "number",
  "score": "number",
  "original_score": "number（--with-impact 时）",
  "impact": {
    "total_affected": "number",
    "affected_files": ["string"],
    "max_depth": "number"
  }
}
```

---

### 1.4 daemon.sh 新增命令

| 项目 | 内容 |
|------|------|
| 命令 | `daemon.sh warmup [--timeout <seconds>]` |
| 类型 | 新增 |
| 兼容性 | 向后兼容（新增命令） |

**状态输出扩展**：
```json
{
  "running": "boolean",
  "pid": "number",
  "warmup_status": "completed|in_progress|disabled|failed",
  "warmup_completed_at": "string",
  "items_cached": "number"
}
```

---

### 1.5 cache-manager.sh 新增命令

| 项目 | 内容 |
|------|------|
| 命令 | `cache-manager.sh cache-set/cache-get/cache-delete/stats` |
| 类型 | 新增 |
| 兼容性 | 向后兼容（新增命令） |

**命令**：
| 命令 | 说明 |
|------|------|
| `cache-set <key> <value>` | 写入子图缓存 |
| `cache-get <key>` | 读取子图缓存 |
| `cache-delete <key>` | 删除缓存条目 |
| `stats` | 显示缓存统计 |
| `warmup-symbols` | 预热常用符号 |

**stats 输出 Schema**：
```json
{
  "total_entries": "number",
  "oldest_access": "number",
  "newest_access": "number",
  "hit_rate": "number",
  "cache_size_bytes": "number"
}
```

---

### 1.6 intent-learner.sh 新增命令

| 项目 | 内容 |
|------|------|
| 命令 | `intent-learner.sh context/session` |
| 类型 | 新增 |
| 兼容性 | 向后兼容（新增命令） |

**命令**：
| 命令 | 说明 |
|------|------|
| `context save --query <q> --symbols <s>` | 保存对话上下文 |
| `context load` | 加载对话上下文 |
| `context apply-weight --results <json>` | 应用对话连续性加权 |
| `session new` | 创建新会话 |
| `session resume <id>` | 恢复会话 |
| `session list` | 列出会话 |
| `session clear` | 清除会话 |

---

### 1.7 augment-context-global.sh 输出变更

| 项目 | 内容 |
|------|------|
| 变更 | 输出从自由文本升级为结构化 JSON |
| 类型 | 输出格式变更 |
| 兼容性 | **可能不兼容**（输出格式变化） |

**新输出 Schema**：
```json
{
  "project_profile": { "name", "tech_stack", "architecture", "key_constraints" },
  "current_state": { "index_status", "hotspot_files", "recent_commits" },
  "task_context": { "intent_analysis", "relevant_snippets", "call_chains" },
  "recommended_tools": [{ "tool", "reason", "suggested_params" }],
  "constraints": { "architectural", "security" }
}
```

**兼容策略**：
- 提供 `--format text` 选项保持原有文本输出
- 默认切换为 JSON 输出

---

## 2. Schema 变更

### 2.1 graph.db edges 表

| 项目 | 内容 |
|------|------|
| 变更 | `edge_type` CHECK 约束扩展 |
| 类型 | Schema 扩展 |
| 兼容性 | 需迁移 |

**原有边类型**：
- DEFINES, IMPORTS, CALLS, MODIFIES

**新增边类型**：
- IMPLEMENTS, EXTENDS, RETURNS_TYPE, ADR_RELATED

**迁移方式**：
```bash
./scripts/graph-store.sh migrate --apply
```

---

### 2.2 新增数据文件

| 文件 | 用途 | Schema |
|------|------|--------|
| `.devbooks/conversation-context.json` | 对话上下文 | 见 REQ-CC-002 |
| `.devbooks/adr-index.json` | ADR 索引 | 见 REQ-ADR-006 |
| `.devbooks/subgraph-cache.db` | 子图 LRU 缓存 | 见 REQ-SLC-002 |

---

## 3. 兼容策略

### 3.1 向后兼容保证

| 变更 | 兼容性 | 说明 |
|------|--------|------|
| graph-store.sh find-path | ✅ 兼容 | 新增命令 |
| graph-store.sh migrate | ✅ 兼容 | 新增命令 |
| adr-parser.sh | ✅ 兼容 | 新脚本 |
| bug-locator.sh --with-impact | ✅ 兼容 | 可选参数 |
| daemon.sh warmup | ✅ 兼容 | 新增命令 |
| cache-manager.sh 缓存命令 | ✅ 兼容 | 新增命令 |
| intent-learner.sh context/session | ✅ 兼容 | 新增命令 |
| augment-context-global.sh 输出 | ⚠️ 需注意 | 输出格式变化 |
| graph.db edge_type | ⚠️ 需迁移 | Schema 扩展 |

### 3.2 弃用策略

无弃用项。

### 3.3 迁移方案

**graph.db 迁移**：

1. 检查迁移需求：
   ```bash
   ./scripts/graph-store.sh migrate --check
   ```

2. 执行迁移（自动备份）：
   ```bash
   ./scripts/graph-store.sh migrate --apply
   ```

3. 验证迁移：
   ```bash
   ./scripts/graph-store.sh migrate --status
   ```

**augment-context-global.sh 输出迁移**：

如果下游依赖原有文本输出：
```bash
# 继续使用文本格式
./hooks/augment-context-global.sh --format text
```

---

## 4. Contract Test IDs

| Test ID | 类型 | 覆盖契约 |
|---------|------|----------|
| CT-API-001 | API | find-path 命令 |
| CT-API-002 | API | migrate 命令 |
| CT-API-003 | API | adr-parser 命令 |
| CT-API-004 | API | bug-locator --with-impact |
| CT-API-005 | API | daemon warmup |
| CT-API-006 | API | cache-manager 缓存命令 |
| CT-API-007 | API | intent-learner context/session |
| CT-SCHEMA-001 | Schema | edges 表扩展 |
| CT-SCHEMA-002 | Schema | conversation-context.json |
| CT-SCHEMA-003 | Schema | adr-index.json |
| CT-SCHEMA-004 | Schema | subgraph-cache.db |
| CT-SCHEMA-005 | Schema | 结构化上下文输出 |

---

## 5. 追溯矩阵（Contract → Spec → AC）

| Contract | Spec | AC |
|----------|------|-----|
| CT-API-001 | REQ-GSE-003 | AC-G02 |
| CT-API-002 | REQ-GSE-005 | AC-G01a |
| CT-API-003 | REQ-ADR-001~007 | AC-G03 |
| CT-API-004 | REQ-BLF-001~006 | AC-G08 |
| CT-API-005 | REQ-DME-001~003 | AC-G05 |
| CT-API-006 | REQ-SLC-001~009 | AC-G07 |
| CT-API-007 | REQ-CC-001~006 | AC-G04 |
| CT-SCHEMA-001 | REQ-GSE-001 | AC-G01 |
| CT-SCHEMA-002 | REQ-CC-002 | AC-G04 |
| CT-SCHEMA-003 | REQ-ADR-006~007 | AC-G03 |
| CT-SCHEMA-004 | REQ-SLC-001~002 | AC-G07 |
| CT-SCHEMA-005 | REQ-SCO-001~007 | AC-G11 |
