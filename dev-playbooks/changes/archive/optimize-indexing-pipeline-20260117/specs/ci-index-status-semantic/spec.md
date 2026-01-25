# Spec Delta: ci_index_status Semantic Alignment（MCP 工具语义对齐）

> **Change ID**: `optimize-indexing-pipeline-20260117`
> **Capability**: ci-index-status-semantic
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-18
> **Affects**: `dev-playbooks/specs/_meta/project-profile.md`（更新工具说明）

---

## Requirements（需求）

### REQ-CIS-001: 工具语义归属

`ci_index_status` MCP 工具必须明确归属 Embedding 索引管理。

**约束**：
- `status` 参数映射到 `scripts/embedding.sh status`
- `build` 参数映射到 `scripts/embedding.sh build`
- `clear` 参数映射到 `scripts/embedding.sh clean`
- 不再调用 `scripts/indexer.sh`

### REQ-CIS-002: 接口稳定性

工具名称和输入 schema 保持不变。

**约束**：
- 工具名：`ci_index_status`
- 输入参数：`action`（string，可选值：`status`/`build`/`clear`）
- 输出格式兼容

### REQ-CIS-003: 调用路由正确性

`src/server.ts` 中的调用路由必须正确指向 `embedding.sh`。

**约束**：
- 移除对 `indexer.sh` 的调用
- 参数传递正确（action -> embedding.sh 子命令映射）

---

## Scenarios（场景）

### SC-CIS-001: status 参数调用

**Given**：
- 用户通过 MCP 协议调用 `ci_index_status`
- 参数：`{ "action": "status" }`

**When**：
- `src/server.ts` 处理工具调用

**Then**：
- 调用 `scripts/embedding.sh status`
- 返回 Embedding 索引状态信息
- 输出包含：索引文件数、最后更新时间、Embedding 提供者状态

**Trace**: AC-005

### SC-CIS-002: build 参数调用

**Given**：
- 用户通过 MCP 协议调用 `ci_index_status`
- 参数：`{ "action": "build" }`

**When**：
- `src/server.ts` 处理工具调用

**Then**：
- 调用 `scripts/embedding.sh build`
- 执行 Embedding 索引构建
- 返回构建结果（成功/失败、索引数量、耗时）

**Trace**: AC-005

### SC-CIS-003: clear 参数调用

**Given**：
- 用户通过 MCP 协议调用 `ci_index_status`
- 参数：`{ "action": "clear" }`

**When**：
- `src/server.ts` 处理工具调用

**Then**：
- 调用 `scripts/embedding.sh clean`
- 清理 Embedding 索引
- 返回清理结果

**Trace**: AC-005

### SC-CIS-004: 无效 action 参数

**Given**：
- 用户调用 `ci_index_status`
- 参数：`{ "action": "invalid" }`

**When**：
- `src/server.ts` 处理工具调用

**Then**：
- 返回错误：`Invalid action. Valid values: status, build, clear`
- 不执行任何脚本

**Trace**: AC-005

### SC-CIS-005: 默认 action 参数

**Given**：
- 用户调用 `ci_index_status`
- 参数：`{}`（未指定 action）

**When**：
- `src/server.ts` 处理工具调用

**Then**：
- 默认执行 `status` 动作
- 调用 `scripts/embedding.sh status`
- 返回索引状态

**Trace**: AC-005

---

## API / Schema 变更

### MCP 工具 Schema（不变）

```json
{
  "name": "ci_index_status",
  "description": "Manage Embedding index status",
  "inputSchema": {
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["status", "build", "clear"],
        "default": "status",
        "description": "Action to perform on Embedding index"
      }
    }
  }
}
```

### 调用路由变更

**Before（当前实现）**：

```typescript
case "ci_index_status":
  return runScript("indexer.sh", [action]);  // 错误的映射
```

**After（正确实现）**：

```typescript
case "ci_index_status":
  const embedAction = action === "clear" ? "clean" : action;
  return runScript("embedding.sh", [embedAction]);
```

### 输出格式

**status 输出（JSON）**：

```json
{
  "indexed_files": 36,
  "last_updated": "2026-01-18T12:00:00Z",
  "embedding_provider": "ollama",
  "embedding_model": "nomic-embed-text",
  "index_size_bytes": 1024000,
  "status": "ready"
}
```

**build 输出（JSON）**：

```json
{
  "result": "success",
  "files_indexed": 36,
  "embeddings_generated": 245,
  "duration_ms": 12500
}
```

**clear 输出（JSON）**：

```json
{
  "result": "success",
  "files_cleared": 36,
  "cache_cleared": true
}
```

---

## 兼容策略

### 向后兼容

- 工具名称不变：`ci_index_status`
- 输入参数不变：`action`（status/build/clear）
- 输出格式兼容（可能新增字段，不删除字段）

### 语义变更说明

本次变更修正了工具的语义归属：

| 参数 | 旧行为 | 新行为 |
|------|--------|--------|
| `status` | 调用 `indexer.sh status` | 调用 `embedding.sh status` |
| `build` | 调用 `indexer.sh build` | 调用 `embedding.sh build` |
| `clear` | 调用 `indexer.sh clear` | 调用 `embedding.sh clean` |

### 迁移影响评估

**影响范围**：
- 依赖 `ci_index_status` 返回 SCIP/图索引状态的用户可能受影响

**迁移建议**：
- 若需要 SCIP/图索引管理，使用 `ci_ast_delta` 或直接调用 `scripts/indexer.sh`
- README.md 需更新工具说明

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 | 验证命令 |
|---------|------|----------|----------|
| CT-CIS-001 | behavior | SC-CIS-001 | `tests/server.bats::test_ci_index_status_status` |
| CT-CIS-002 | behavior | SC-CIS-002 | `tests/server.bats::test_ci_index_status_build` |
| CT-CIS-003 | behavior | SC-CIS-003 | `tests/server.bats::test_ci_index_status_clear` |
| CT-CIS-004 | behavior | SC-CIS-004, SC-CIS-005 | `tests/server.bats::test_ci_index_status_validation` |

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-CIS-001 | SC-CIS-001, SC-CIS-002, SC-CIS-003 | AC-005 |
| REQ-CIS-002 | SC-CIS-001 ~ SC-CIS-005 | AC-005 |
| REQ-CIS-003 | SC-CIS-001, SC-CIS-002, SC-CIS-003 | AC-005 |

---

## 文档影响

### 需要更新的文档

| 文档 | 更新内容 |
|------|----------|
| `README.md` | 更新 `ci_index_status` 工具说明，明确其管理 Embedding 索引 |
| `dev-playbooks/specs/_meta/project-profile.md` | 更新核心功能表格中的 `ci_index_status` 描述 |
