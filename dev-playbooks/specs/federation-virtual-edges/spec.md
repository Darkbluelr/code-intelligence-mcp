# 规格：M5 联邦虚拟边连接

> **模块 ID**: `federation-virtual-edges`
> **Change ID**: `achieve-augment-full-parity`
> **Date**: 2026-01-16
> **Status**: Draft

---

## Requirements（需求）

### REQ-FV-001: 虚拟边生成

系统必须能够生成跨仓库的虚拟边，连接本地调用点与远程服务定义。

**约束**：
- 边类型：`VIRTUAL_CALLS`、`VIRTUAL_IMPORTS`
- 区分于真实边（edge_type 前缀 VIRTUAL_）
- 存储位置：graph.db 的 virtual_edges 表

### REQ-FV-002: 置信度计算

系统必须为每条虚拟边计算匹配置信度。

**约束**：
- 公式：`confidence = exact_match × 0.6 + signature_similarity × 0.3 + contract_bonus × 0.1`
- exact_match：名称匹配度（精确=1.0，前缀=0.7，模糊=0.4）
- signature_similarity：签名相似度
- contract_bonus：契约类型加权（Proto=0.1，OpenAPI=0.05，GraphQL=0.08）

### REQ-FV-003: 置信度阈值过滤

系统必须根据置信度阈值过滤低质量虚拟边。

**约束**：
- 默认阈值：0.5
- 高置信阈值：0.8（标记为"高置信"）
- 低于阈值的匹配不生成虚拟边

### REQ-FV-004: 契约类型支持

系统必须支持多种契约类型的跨仓匹配。

**约束**：
- 支持类型：Proto/gRPC、OpenAPI、GraphQL、TypeScript
- 优先匹配强类型契约（Proto > GraphQL > OpenAPI > TypeScript）

### REQ-FV-005: 虚拟边索引

系统必须为虚拟边建立索引以支持高效查询。

**约束**：
- 索引：source_repo + source_symbol
- 索引：target_repo + target_symbol
- 索引：edge_type

---

## Scenarios（场景）

### SC-FV-001: Proto 契约虚拟边生成

**Given**：
- 本地代码调用 `userClient.getUserById(userId)`
- federation-index.json 中存在远程服务定义 `UserService::GetUserById`
- 契约类型：proto

**When**：
- 调用 `federation-lite.sh generate-virtual-edges`

**Then**：
- 系统匹配本地调用与远程定义
- 计算置信度（预期 > 0.5）
- 生成虚拟边记录
- 写入 graph.db virtual_edges 表

**验证**：`tests/federation-lite.bats::test_proto_virtual_edge`

### SC-FV-002: 置信度正确计算

**Given**：
- 本地符号：`getUserById`
- 远程符号：`GetUserById`（Proto）
- 参数数量一致但类型封装不同

**When**：
- 计算置信度

**Then**：
- exact_match = 0.7（前缀匹配，忽略大小写后相同）
- signature_similarity = 0.6（参数数量一致，类型不同）
- contract_bonus = 0.1（Proto）
- confidence = 0.7×0.6 + 0.6×0.3 + 0.1×0.1 = 0.61
- 0.61 > 0.5，生成虚拟边

**验证**：`tests/federation-lite.bats::test_confidence_calculation`

### SC-FV-003: 低置信度过滤

**Given**：
- 本地符号：`processData`
- 远程符号：`handleRequest`（无明显关联）

**When**：
- 计算置信度

**Then**：
- exact_match = 0.0（无匹配）
- confidence < 0.5
- 不生成虚拟边

**验证**：`tests/federation-lite.bats::test_low_confidence_filter`

### SC-FV-004: 虚拟边查询

**Given**：
- graph.db 中存在虚拟边记录

**When**：
- 调用 `federation-lite.sh query-virtual getUserById`

**Then**：
- 系统查询 virtual_edges 表
- 返回匹配的虚拟边信息
- 包含 source_repo、target_repo、confidence

**验证**：`tests/federation-lite.bats::test_virtual_edge_query`

### SC-FV-005: 高置信标记

**Given**：
- 虚拟边置信度 = 0.85

**When**：
- 生成虚拟边

**Then**：
- 虚拟边被标记为"高置信"
- 查询结果显示置信级别

**验证**：`tests/federation-lite.bats::test_high_confidence_mark`

### SC-FV-006: OpenAPI 契约虚拟边

**Given**：
- 本地代码调用 `fetch('/api/users/{id}')`
- federation-index.json 中存在 OpenAPI 定义 `GET /api/users/{id}`

**When**：
- 调用 `federation-lite.sh generate-virtual-edges`

**Then**：
- 系统匹配路径模式
- contract_bonus = 0.05（OpenAPI）
- 生成 VIRTUAL_CALLS 边

**验证**：`tests/federation-lite.bats::test_openapi_virtual_edge`

### SC-FV-007: 虚拟边更新（同步）

**Given**：
- 已存在虚拟边
- 远程服务定义变更

**When**：
- 调用 `federation-lite.sh generate-virtual-edges --sync`

**Then**：
- 删除失效的虚拟边
- 更新现有虚拟边的置信度
- 新增新匹配的虚拟边
- updated_at 字段更新

**验证**：`tests/federation-lite.bats::test_virtual_edge_sync`

### SC-FV-008: 模糊匹配算法（Jaro-Winkler）

**Given**：
- 本地符号：`fetchUser`
- 远程符号：`getUser`

**When**：
- 计算 exact_match（模糊匹配）

**Then**：
- 使用 Jaro-Winkler 算法计算相似度
- 相似度 > 阈值时返回 0.4（模糊匹配）

**验证**：`tests/federation-lite.bats::test_fuzzy_match`

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios |
|-------------|-----------|
| REQ-FV-001 | SC-FV-001, SC-FV-006 |
| REQ-FV-002 | SC-FV-002, SC-FV-008 |
| REQ-FV-003 | SC-FV-003, SC-FV-005 |
| REQ-FV-004 | SC-FV-001, SC-FV-006 |
| REQ-FV-005 | SC-FV-004 |

| Scenario | Test ID |
|----------|---------|
| SC-FV-001 | `tests/federation-lite.bats::test_proto_virtual_edge` |
| SC-FV-002 | `tests/federation-lite.bats::test_confidence_calculation` |
| SC-FV-003 | `tests/federation-lite.bats::test_low_confidence_filter` |
| SC-FV-004 | `tests/federation-lite.bats::test_virtual_edge_query` |
| SC-FV-005 | `tests/federation-lite.bats::test_high_confidence_mark` |
| SC-FV-006 | `tests/federation-lite.bats::test_openapi_virtual_edge` |
| SC-FV-007 | `tests/federation-lite.bats::test_virtual_edge_sync` |
| SC-FV-008 | `tests/federation-lite.bats::test_fuzzy_match` |

---

## Schema 变更

### virtual_edges 表（新增）

```sql
CREATE TABLE virtual_edges (
    id TEXT PRIMARY KEY,
    source_repo TEXT NOT NULL,
    source_symbol TEXT NOT NULL,
    target_repo TEXT NOT NULL,
    target_symbol TEXT NOT NULL,
    edge_type TEXT NOT NULL,          -- VIRTUAL_CALLS/VIRTUAL_IMPORTS
    contract_type TEXT NOT NULL,      -- proto/openapi/graphql/typescript
    confidence REAL DEFAULT 1.0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_virtual_edges_source ON virtual_edges(source_repo, source_symbol);
CREATE INDEX idx_virtual_edges_target ON virtual_edges(target_repo, target_symbol);
CREATE INDEX idx_virtual_edges_type ON virtual_edges(edge_type);
```
