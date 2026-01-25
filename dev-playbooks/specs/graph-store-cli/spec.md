---
last_referenced_by: 20260118-0057-upgrade-code-intelligence-capabilities
last_verified: 2026-01-18
health: active
---

# 规格：graph-store.sh 命令行接口扩展

| 属性 | 值 |
|------|-----|
| Spec-ID | SPEC-GRAPH-STORE-001 |
| Change-ID | 20260118-0057-upgrade-code-intelligence-capabilities |
| 版本 | 1.0.0 |
| 状态 | Active |
| 作者 | Spec Owner |
| 创建日期 | 2026-01-18 |

---

## 1. Requirements（需求规格）

### REQ-GS-001: migrate --status 返回 schema_version

**描述**：`graph-store.sh migrate --status` 命令必须返回包含 `schema_version` 字段的 JSON 对象。

**输出格式**：
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `db_path` | string | 是 | 数据库文件路径 |
| `schema_version` | integer | 是 | 当前 Schema 版本号 |
| `target_version` | integer | 是 | 目标 Schema 版本号 |
| `needs_migration` | string | 是 | "true" 或 "false" |
| `edges_by_type` | object | 是 | 各边类型的数量统计 |
| `total_nodes` | integer | 是 | 节点总数 |
| `total_edges` | integer | 是 | 边总数 |

---

### REQ-GS-002: migrate --apply 执行迁移并自动备份

**描述**：`graph-store.sh migrate --apply` 命令必须在执行迁移前自动创建数据库备份。

**行为规格**：
1. 迁移前创建备份文件：`{db_path}.backup.{YYYYMMDD_HHMMSS}`
2. 同时备份 WAL 和 SHM 文件（如存在）
3. 迁移失败时自动恢复备份
4. 迁移成功后返回成功状态

**输出格式**（成功）：
```json
{
  "status": "MIGRATED",
  "from_version": 2,
  "to_version": 3,
  "backup_path": ".devbooks/graph.db.backup.20260118_120000",
  "message": "Schema 迁移完成"
}
```

**输出格式**（已最新）：
```json
{
  "status": "UP_TO_DATE",
  "message": "Schema 已是最新，无需迁移"
}
```

**输出格式**（失败）：
```json
{
  "status": "FAILED",
  "error": "迁移失败原因",
  "backup_restored": true,
  "message": "已恢复备份"
}
```

---

### REQ-GS-003: stats 命令返回 edges_by_type 分布

**描述**：`graph-store.sh stats` 命令必须返回包含所有支持边类型数量分布的 `edges_by_type` 对象。

**边类型列表**：
| 边类型 | 说明 | 新增 |
|--------|------|------|
| `DEFINES` | 定义关系 | 否 |
| `IMPORTS` | 导入关系 | 否 |
| `CALLS` | 调用关系 | 否 |
| `MODIFIES` | 修改关系 | 否 |
| `REFERENCES` | 引用关系 | 否 |
| `IMPLEMENTS` | 接口实现关系 | 是 |
| `EXTENDS` | 类继承关系 | 是 |
| `RETURNS_TYPE` | 返回类型关系 | 是 |
| `ADR_RELATED` | ADR 关联关系 | 否 |

**输出格式**：
```json
{
  "nodes": 1234,
  "edges": 5678,
  "edges_by_type": {
    "DEFINES": 500,
    "IMPORTS": 200,
    "CALLS": 1500,
    "MODIFIES": 100,
    "REFERENCES": 800,
    "IMPLEMENTS": 45,
    "EXTENDS": 23,
    "RETURNS_TYPE": 178,
    "ADR_RELATED": 10
  }
}
```

---

### REQ-GS-004: migrate 并发保护

**描述**：多个 `migrate --apply` 进程同时执行时，必须有锁定机制防止并发迁移。

**行为规格**：
1. 使用锁文件：`{db_path}.migrate.lock`
2. 第二个进程检测到锁时返回错误
3. 锁文件在迁移完成（成功或失败）后自动清理

**输出格式**（锁定时）：
```json
{
  "status": "LOCKED",
  "error": "Migration in progress",
  "message": "另一个迁移进程正在运行"
}
```

---

## 2. Scenarios（场景规格）

### SC-GS-001: 查询迁移状态

**Given**：
- 数据库存在，Schema 版本为 2
- 目标 Schema 版本为 3

**When**：
- 执行 `graph-store.sh migrate --status`

**Then**：
```json
{
  "db_path": ".devbooks/graph.db",
  "schema_version": 2,
  "target_version": 3,
  "needs_migration": "true",
  "edges_by_type": {
    "DEFINES": 500,
    "IMPORTS": 200,
    "CALLS": 1500,
    "MODIFIES": 100,
    "REFERENCES": 800,
    "IMPLEMENTS": 0,
    "EXTENDS": 0,
    "RETURNS_TYPE": 0,
    "ADR_RELATED": 10
  },
  "total_nodes": 1234,
  "total_edges": 3110
}
```

---

### SC-GS-002: 执行 v2 -> v3 迁移

**Given**：
- 数据库存在，Schema 版本为 2
- 包含 1234 个节点和 3110 条边

**When**：
- 执行 `graph-store.sh migrate --apply`

**Then**：
1. 创建备份文件 `.devbooks/graph.db.backup.{timestamp}`
2. 执行迁移，创建新边类型索引
3. 返回成功响应：
```json
{
  "status": "MIGRATED",
  "from_version": 2,
  "to_version": 3,
  "backup_path": ".devbooks/graph.db.backup.20260118_120000",
  "message": "Schema 迁移完成"
}
```
4. 迁移后节点数和边数保持不变

---

### SC-GS-003: 迁移失败自动回滚

**Given**：
- 数据库存在，Schema 版本为 2
- 迁移过程中发生错误（如磁盘空间不足）

**When**：
- 执行 `graph-store.sh migrate --apply`

**Then**：
1. 检测到迁移失败
2. 自动恢复备份文件
3. 返回失败响应：
```json
{
  "status": "FAILED",
  "error": "SQLITE_FULL: database or disk is full",
  "backup_restored": true,
  "message": "已恢复备份"
}
```

---

### SC-GS-004: 并发迁移被拒绝

**Given**：
- 第一个迁移进程正在运行
- 锁文件存在

**When**：
- 第二个进程执行 `graph-store.sh migrate --apply`

**Then**：
```json
{
  "status": "LOCKED",
  "error": "Migration in progress",
  "message": "另一个迁移进程正在运行"
}
```
- 返回退出码 1

---

### SC-GS-005: 查询边类型统计

**Given**：
- 数据库已初始化
- 包含 IMPLEMENTS/EXTENDS/RETURNS_TYPE 边

**When**：
- 执行 `graph-store.sh stats`

**Then**：
```json
{
  "nodes": 1234,
  "edges": 5678,
  "edges_by_type": {
    "DEFINES": 500,
    "IMPORTS": 200,
    "CALLS": 1500,
    "MODIFIES": 100,
    "REFERENCES": 800,
    "IMPLEMENTS": 45,
    "EXTENDS": 23,
    "RETURNS_TYPE": 178,
    "ADR_RELATED": 10
  }
}
```

---

## 3. API/Schema 契约

### 3.1 命令行接口规格

#### migrate 命令

```
用法: graph-store.sh migrate [选项]

选项:
    --check                 仅检查是否需要迁移（不执行）
    --apply                 执行迁移（自动备份）
    --status                显示当前状态（JSON 格式）

退出码:
    0   成功/无需迁移
    1   需要迁移（--check）/ 迁移失败 / 锁定
```

#### stats 命令

```
用法: graph-store.sh stats

输出: JSON 格式，包含节点数、边数、边类型分布

退出码:
    0   成功
    1   数据库不存在或查询失败
```

### 3.2 JSON Schema 定义

#### migrate --status 输出

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "graph-store-migrate-status.schema.json",
  "title": "Graph Store Migrate Status",
  "type": "object",
  "properties": {
    "db_path": { "type": "string" },
    "schema_version": { "type": "integer", "minimum": 1 },
    "target_version": { "type": "integer", "minimum": 1 },
    "needs_migration": { "type": "string", "enum": ["true", "false"] },
    "edges_by_type": {
      "type": "object",
      "properties": {
        "DEFINES": { "type": "integer", "minimum": 0 },
        "IMPORTS": { "type": "integer", "minimum": 0 },
        "CALLS": { "type": "integer", "minimum": 0 },
        "MODIFIES": { "type": "integer", "minimum": 0 },
        "REFERENCES": { "type": "integer", "minimum": 0 },
        "IMPLEMENTS": { "type": "integer", "minimum": 0 },
        "EXTENDS": { "type": "integer", "minimum": 0 },
        "RETURNS_TYPE": { "type": "integer", "minimum": 0 },
        "ADR_RELATED": { "type": "integer", "minimum": 0 }
      },
      "required": ["DEFINES", "IMPORTS", "CALLS", "MODIFIES", "REFERENCES", "IMPLEMENTS", "EXTENDS", "RETURNS_TYPE", "ADR_RELATED"]
    },
    "total_nodes": { "type": "integer", "minimum": 0 },
    "total_edges": { "type": "integer", "minimum": 0 }
  },
  "required": ["db_path", "schema_version", "target_version", "needs_migration", "edges_by_type", "total_nodes", "total_edges"]
}
```

#### migrate --apply 输出

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "graph-store-migrate-apply.schema.json",
  "title": "Graph Store Migrate Apply Result",
  "type": "object",
  "properties": {
    "status": {
      "type": "string",
      "enum": ["MIGRATED", "UP_TO_DATE", "FAILED", "LOCKED", "INITIALIZED", "MISSING"]
    },
    "from_version": { "type": "integer" },
    "to_version": { "type": "integer" },
    "backup_path": { "type": "string" },
    "error": { "type": "string" },
    "backup_restored": { "type": "boolean" },
    "message": { "type": "string" }
  },
  "required": ["status"]
}
```

### 3.3 向后兼容性

| 变更类型 | 兼容性 | 说明 |
|----------|--------|------|
| `--status` 输出新增字段 | 向后兼容 | 新增字段，旧脚本可忽略 |
| `edges_by_type` 新增边类型 | 向后兼容 | 新增键值，旧脚本可忽略 |
| `--apply` 自动备份 | 向后兼容 | 新增行为，不影响旧用法 |
| 并发锁定机制 | 向后兼容 | 新增保护，不影响正常单进程使用 |

### 3.4 弃用策略

无弃用项。

---

## 4. Contract Tests

### CT-GS-001: migrate --status 返回 schema_version

**类型**：schema

**覆盖**：REQ-GS-001

**验证脚本**：
```bash
graph-store.sh migrate --status | jq -e '.schema_version >= 1'
```

---

### CT-GS-002: migrate --apply 创建备份

**类型**：behavior

**覆盖**：REQ-GS-002, SC-GS-002

**验证脚本**：
```bash
# 执行迁移
result=$(graph-store.sh migrate --apply)

# 验证备份文件存在
backup_path=$(echo "$result" | jq -r '.backup_path // empty')
if [[ -n "$backup_path" ]]; then
  test -f "$backup_path"
fi
```

---

### CT-GS-003: migrate --apply 失败回滚

**类型**：behavior

**覆盖**：REQ-GS-002, SC-GS-003

**验证脚本**：
```bash
# 记录迁移前状态
before_count=$(graph-store.sh stats | jq '.nodes')

# 模拟迁移失败（通过制造约束冲突）
# ... 测试设置 ...

# 验证数据恢复
after_count=$(graph-store.sh stats | jq '.nodes')
test "$before_count" = "$after_count"
```

---

### CT-GS-004: stats 返回 edges_by_type

**类型**：schema

**覆盖**：REQ-GS-003, SC-GS-005

**验证脚本**：
```bash
graph-store.sh stats | jq -e '.edges_by_type | has("IMPLEMENTS") and has("EXTENDS") and has("RETURNS_TYPE")'
```

---

### CT-GS-005: migrate 并发保护

**类型**：behavior

**覆盖**：REQ-GS-004, SC-GS-004

**验证脚本**：
```bash
# 创建锁文件模拟并发
touch "${GRAPH_DB_PATH}.migrate.lock"

# 执行迁移应返回 LOCKED
result=$(graph-store.sh migrate --apply)
status=$(echo "$result" | jq -r '.status')
test "$status" = "LOCKED"

# 清理
rm -f "${GRAPH_DB_PATH}.migrate.lock"
```

---

## 5. 追溯矩阵

| Contract Test ID | 类型 | 覆盖需求/场景 |
|------------------|------|---------------|
| CT-GS-001 | schema | REQ-GS-001, SC-GS-001 |
| CT-GS-002 | behavior | REQ-GS-002, SC-GS-002 |
| CT-GS-003 | behavior | REQ-GS-002, SC-GS-003 |
| CT-GS-004 | schema | REQ-GS-003, SC-GS-005 |
| CT-GS-005 | behavior | REQ-GS-004, SC-GS-004 |
