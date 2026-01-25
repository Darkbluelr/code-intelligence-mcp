# 规格：SQLite 图存储（graph-store）

> **Change ID**: `augment-parity`
> **Capability**: graph-store
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-15

---

## Requirements（需求）

### REQ-GS-001：图存储初始化

系统应支持初始化 SQLite 图数据库，创建 `nodes` 和 `edges` 表结构。

**约束**：
- 数据库文件位置：`.devbooks/graph.db`
- 启用 WAL 模式以支持并发读
- 若数据库已存在，不覆盖现有数据

### REQ-GS-002：节点 CRUD 操作

系统应支持图节点的创建、读取、更新、删除操作。

**节点属性**：
| 属性 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 节点 ID（符号指纹） |
| symbol | string | 是 | 符号名称 |
| kind | string | 是 | 符号类型（function/class/variable/method/property） |
| file_path | string | 是 | 文件路径 |
| line_start | number | 否 | 起始行 |
| line_end | number | 否 | 结束行 |

### REQ-GS-003：边 CRUD 操作

系统应支持图边的创建、读取、更新、删除操作。

**边属性**：
| 属性 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 边 ID |
| source_id | string | 是 | 源节点 ID |
| target_id | string | 是 | 目标节点 ID |
| edge_type | EdgeType | 是 | 边类型 |
| file_path | string | 否 | 发生位置 |
| line | number | 否 | 行号 |

### REQ-GS-004：边类型约束

系统应支持 4 种核心边类型：

| 边类型 | 说明 | SCIP symbol_roles |
|--------|------|-------------------|
| DEFINES | 定义关系 | 1 (Definition) |
| IMPORTS | 导入关系 | 2 (Import) |
| CALLS | 调用关系 | 8 (ReadAccess) |
| MODIFIES | 修改关系 | 4 (WriteAccess) |

**约束**：写入非法边类型时应拒绝并返回错误。

### REQ-GS-005：图查询能力

系统应支持以下查询操作：

1. **按 ID 查询节点**：`get_node(id)`
2. **按符号名查询节点**：`find_nodes_by_symbol(symbol)`
3. **按文件路径查询节点**：`find_nodes_by_file(file_path)`
4. **查询出边**：`get_outgoing_edges(node_id, edge_type?)`
5. **查询入边**：`get_incoming_edges(node_id, edge_type?)`
6. **查询孤儿节点**：`find_orphan_nodes()`（入边数 = 0）

### REQ-GS-006：批量操作

系统应支持批量写入节点和边，以提高 SCIP 转换效率。

**约束**：
- 批量操作应在单个事务中完成
- 失败时整个批次回滚

### REQ-GS-007：数据库统计

系统应提供数据库统计信息：

- 节点总数
- 边总数
- 各边类型数量
- 数据库文件大小

---

## Scenarios（场景）

### SC-GS-001：初始化空数据库

**Given**: 项目目录下不存在 `.devbooks/graph.db`
**When**: 执行 `graph-store.sh init`
**Then**:
- 创建 `.devbooks/graph.db` 文件
- 创建 `nodes` 表（含索引）
- 创建 `edges` 表（含索引和外键约束）
- 启用 WAL 模式
- 返回成功状态

### SC-GS-002：创建节点

**Given**: 图数据库已初始化
**When**: 执行 `graph-store.sh add-node --id "sym:func:main" --symbol "main" --kind "function" --file "src/index.ts" --line-start 10 --line-end 20`
**Then**:
- 节点写入 `nodes` 表
- 返回节点 ID

### SC-GS-003：创建有效边

**Given**:
- 图数据库已初始化
- 存在源节点 `sym:func:main` 和目标节点 `sym:func:helper`
**When**: 执行 `graph-store.sh add-edge --source "sym:func:main" --target "sym:func:helper" --type CALLS --file "src/index.ts" --line 15`
**Then**:
- 边写入 `edges` 表
- 返回边 ID

### SC-GS-004：拒绝非法边类型

**Given**: 图数据库已初始化
**When**: 执行 `graph-store.sh add-edge --source "a" --target "b" --type INVALID_TYPE`
**Then**:
- 返回错误：`Invalid edge type: INVALID_TYPE. Must be one of: DEFINES, IMPORTS, CALLS, MODIFIES`
- 不写入任何数据

### SC-GS-005：查询出边

**Given**:
- 节点 A 有 3 条出边（2 条 CALLS，1 条 IMPORTS）
**When**: 执行 `graph-store.sh query-edges --from "A" --type CALLS`
**Then**:
- 返回 2 条 CALLS 类型边
- 不返回 IMPORTS 类型边

### SC-GS-006：查询孤儿节点

**Given**:
- 节点 A 有入边（被其他节点引用）
- 节点 B 无入边（孤儿）
- 节点 C 无入边（孤儿）
**When**: 执行 `graph-store.sh find-orphans`
**Then**:
- 返回节点 B 和 C
- 不返回节点 A

### SC-GS-007：批量写入

**Given**: 图数据库已初始化
**When**: 执行 `graph-store.sh batch-import --file nodes.json`（包含 100 个节点）
**Then**:
- 100 个节点全部写入
- 在单个事务中完成
- 返回成功状态和写入数量

### SC-GS-008：批量写入失败回滚

**Given**: 图数据库已初始化
**When**: 执行批量写入，其中第 50 个节点数据格式错误
**Then**:
- 整个批次回滚
- 数据库保持原状态
- 返回错误信息，指明失败位置

### SC-GS-009：统计信息

**Given**: 图数据库包含 187 个节点和 307 条边
**When**: 执行 `graph-store.sh stats`
**Then**:
- 返回 JSON 格式统计信息：
  ```json
  {
    "nodes": 187,
    "edges": 307,
    "edges_by_type": {
      "DEFINES": 50,
      "IMPORTS": 30,
      "CALLS": 200,
      "MODIFIES": 27
    },
    "db_size_bytes": 102400
  }
  ```

### SC-GS-010：数据库已存在时初始化

**Given**: `.devbooks/graph.db` 已存在且包含数据
**When**: 执行 `graph-store.sh init`
**Then**:
- 不覆盖现有数据
- 返回警告：`Database already exists, skipping initialization`
- 退出码 0

### SC-GS-011：空图查询孤儿

**Given**: 图数据库已初始化但无任何节点
**When**: 执行 `graph-store.sh find-orphans`
**Then**:
- 返回空列表 `[]`
- 不报错

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-GS-001 | SC-GS-001, SC-GS-010 | AC-001 |
| REQ-GS-002 | SC-GS-002 | AC-001 |
| REQ-GS-003 | SC-GS-003, SC-GS-004 | AC-001 |
| REQ-GS-004 | SC-GS-004 | AC-001 |
| REQ-GS-005 | SC-GS-005, SC-GS-006, SC-GS-011 | AC-001, AC-005 |
| REQ-GS-006 | SC-GS-007, SC-GS-008 | AC-002 |
| REQ-GS-007 | SC-GS-009 | AC-001 |
