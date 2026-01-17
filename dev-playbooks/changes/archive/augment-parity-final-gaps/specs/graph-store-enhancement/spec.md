# Spec Delta: 图存储增强（graph-store-enhancement）

> **Change ID**: `augment-parity-final-gaps`
> **Capability**: graph-store-enhancement
> **Base Spec**: `dev-playbooks/specs/graph-store/spec.md`
> **Version**: 2.0.0
> **Status**: Draft
> **Created**: 2026-01-16

---

## 概述

本规格增量扩展现有 graph-store 规格，新增：
1. **边类型扩展**：IMPLEMENTS/EXTENDS/RETURNS_TYPE 三种边类型
2. **A-B 路径查询**：BFS 最短路径算法
3. **Schema 迁移**：支持现有数据库升级

---

## Requirements（需求）

### REQ-GSE-001：扩展边类型

系统应支持 3 种新边类型（扩展 REQ-GS-004）：

| 边类型 | 说明 | SCIP 映射 | 适用语言 |
|--------|------|-----------|----------|
| IMPLEMENTS | 接口实现 | SymbolRole.Implementation | TypeScript, Python, Java, Go, Rust |
| EXTENDS | 类继承 | SymbolRole.Definition + inheritance relation | TypeScript, Python, Java |
| RETURNS_TYPE | 函数返回类型 | 函数签名中的返回类型引用 | TypeScript, Python*, Java, Go, Rust |

*Python 需要类型注解

**约束**：
- 边类型 CHECK 约束扩展为包含新类型
- 不支持的语言降级到 REFERENCES 边类型
- 降级时记录 debug 日志，不报错

### REQ-GSE-002：边类型降级策略

当 SCIP 索引器不支持特定边类型时，系统应优雅降级：

| 场景 | 检测方式 | 降级行为 |
|------|----------|----------|
| SCIP 无 Implementation role | `symbol_roles` 位图不含 0x10 | 降级为 REFERENCES |
| 语言无类继承（Go, Rust） | 语言检测 | 跳过 EXTENDS 边，不报错 |
| Python 无类型注解 | 返回类型字段为空 | 跳过 RETURNS_TYPE 边 |

**约束**：
- 降级日志级别为 DEBUG
- 降级不影响其他边类型的解析

### REQ-GSE-003：A-B 路径查询

系统应支持从节点 A 到节点 B 的最短路径查询：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| from | string | 是 | 源节点 ID |
| to | string | 是 | 目标节点 ID |
| max-depth | number | 否 | 最大深度（默认 10） |
| edge-types | string[] | 否 | 过滤边类型 |

**算法**：BFS（广度优先搜索）
**实现**：SQLite 递归 CTE

**约束**：
- 最大深度上限：10（防止性能问题）
- 无路径时返回空结果，不报错
- 存在环时正确处理（visited 集合）

### REQ-GSE-004：路径查询输出格式

路径查询应返回以下 JSON 结构：

```json
{
  "found": true,
  "path": [
    { "node_id": "A", "symbol": "main", "file": "src/index.ts" },
    { "node_id": "B", "symbol": "helper", "file": "src/utils.ts" },
    { "node_id": "C", "symbol": "target", "file": "src/target.ts" }
  ],
  "edges": [
    { "from": "A", "to": "B", "type": "CALLS" },
    { "from": "B", "to": "C", "type": "CALLS" }
  ],
  "length": 2
}
```

**约束**：
- 无路径时 `found: false`，`path` 和 `edges` 为空数组
- `length` 为边数（节点数 - 1）

### REQ-GSE-005：Schema 迁移命令

系统应提供 Schema 迁移命令处理边类型扩展：

| 子命令 | 功能 |
|--------|------|
| `migrate --check` | 检查是否需要迁移，返回 NEEDS_MIGRATION 或 UP_TO_DATE |
| `migrate --apply` | 执行迁移，自动备份后重建表 |
| `migrate --status` | 显示当前 Schema 版本和边类型分布 |

**约束**：
- 迁移前自动创建备份文件 `graph.db.backup.<timestamp>`
- 迁移在单个事务中完成
- 迁移失败时回滚，数据库保持原状态

### REQ-GSE-006：ADR 关联边

系统应支持 ADR（架构决策记录）关联边类型：

| 边类型 | 说明 | 来源 |
|--------|------|------|
| ADR_RELATED | ADR 与代码模块的关联 | adr-parser.sh 生成 |

**约束**：
- ADR_RELATED 边存储在 edges 表
- 边的 source_id 为 ADR 标识符（如 `adr:ADR-001`）
- 边的 target_id 为代码节点 ID

---

## Scenarios（场景）

### SC-GSE-001：创建 IMPLEMENTS 边

**Given**:
- TypeScript 项目 SCIP 索引已生成
- 存在接口 `IService` 和实现类 `ServiceImpl`
**When**: 执行 `scip-to-graph.sh` 转换
**Then**:
- 生成 IMPLEMENTS 边（source: ServiceImpl, target: IService）
- 边写入 edges 表
- `edge_type` 字段值为 `IMPLEMENTS`

### SC-GSE-002：创建 EXTENDS 边

**Given**:
- TypeScript 项目 SCIP 索引已生成
- 存在基类 `BaseHandler` 和子类 `ChildHandler extends BaseHandler`
**When**: 执行 `scip-to-graph.sh` 转换
**Then**:
- 生成 EXTENDS 边（source: ChildHandler, target: BaseHandler）
- 边写入 edges 表
- `edge_type` 字段值为 `EXTENDS`

### SC-GSE-003：创建 RETURNS_TYPE 边

**Given**:
- TypeScript 项目 SCIP 索引已生成
- 存在函数 `function getUser(): User`
**When**: 执行 `scip-to-graph.sh` 转换
**Then**:
- 生成 RETURNS_TYPE 边（source: getUser, target: User）
- 边写入 edges 表
- `edge_type` 字段值为 `RETURNS_TYPE`

### SC-GSE-004：Go 项目降级 EXTENDS

**Given**:
- Go 项目 SCIP 索引已生成
- Go 无类继承概念
**When**: 执行 `scip-to-graph.sh` 转换
**Then**:
- 不生成 EXTENDS 边
- 不报错
- 记录 DEBUG 日志：`Go 不支持 EXTENDS 边类型，跳过`

### SC-GSE-005：Python 无类型注解降级

**Given**:
- Python 项目 SCIP 索引已生成
- 函数 `def get_user():` 无返回类型注解
**When**: 执行 `scip-to-graph.sh` 转换
**Then**:
- 不生成 RETURNS_TYPE 边
- 不报错
- 记录 DEBUG 日志：`返回类型缺失，跳过 RETURNS_TYPE`

### SC-GSE-006：基本路径查询

**Given**:
- 图数据库包含节点 A → B → C 的调用链
**When**: 执行 `graph-store.sh find-path --from A --to C`
**Then**:
- 返回 JSON：`{"found": true, "path": [...], "edges": [...], "length": 2}`
- 路径为 A → B → C

### SC-GSE-007：路径查询深度限制

**Given**:
- 图数据库包含节点 A → B → C → D → E 的调用链（长度 4）
**When**: 执行 `graph-store.sh find-path --from A --to E --max-depth 3`
**Then**:
- 返回 JSON：`{"found": false, "path": [], "edges": [], "length": 0}`
- 因为路径长度 4 > max-depth 3

### SC-GSE-008：路径查询无路径

**Given**:
- 图数据库包含节点 A 和 B，但无连接
**When**: 执行 `graph-store.sh find-path --from A --to B`
**Then**:
- 返回 JSON：`{"found": false, "path": [], "edges": [], "length": 0}`
- 不报错

### SC-GSE-009：路径查询按边类型过滤

**Given**:
- 图数据库包含 A -CALLS-> B -IMPORTS-> C
**When**: 执行 `graph-store.sh find-path --from A --to C --edge-types CALLS`
**Then**:
- 返回 `{"found": false, ...}`
- 因为 B → C 是 IMPORTS 边，被过滤

### SC-GSE-010：路径查询处理环

**Given**:
- 图数据库包含环 A → B → C → A
**When**: 执行 `graph-store.sh find-path --from A --to B`
**Then**:
- 返回路径 A → B
- 不陷入死循环
- visited 集合正确排除已访问节点

### SC-GSE-011：迁移检查 - 需要迁移

**Given**:
- 现有 graph.db 使用旧 Schema（4 种边类型）
**When**: 执行 `graph-store.sh migrate --check`
**Then**:
- 输出：`NEEDS_MIGRATION: 边类型 Schema 需要更新`
- 列出缺失的边类型
- 退出码 1

### SC-GSE-012：迁移检查 - 已是最新

**Given**:
- graph.db 使用新 Schema（含所有边类型）
**When**: 执行 `graph-store.sh migrate --check`
**Then**:
- 输出：`UP_TO_DATE: Schema 已是最新`
- 退出码 0

### SC-GSE-013：执行迁移

**Given**:
- 现有 graph.db 使用旧 Schema
- 包含 100 个节点和 200 条边
**When**: 执行 `graph-store.sh migrate --apply`
**Then**:
- 创建备份文件 `graph.db.backup.<timestamp>`
- 重建 edges 表（带新 CHECK 约束）
- 迁移所有 200 条边
- 数据完整性验证通过
- 输出：`迁移完成。备份文件：graph.db.backup.*`

### SC-GSE-014：迁移状态查看

**Given**:
- graph.db 存在，包含边数据
**When**: 执行 `graph-store.sh migrate --status`
**Then**:
- 显示数据库路径
- 显示各边类型数量分布
- 显示 Schema 版本状态

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-GSE-001 | SC-GSE-001, SC-GSE-002, SC-GSE-003 | AC-G01 |
| REQ-GSE-002 | SC-GSE-004, SC-GSE-005 | AC-G01 |
| REQ-GSE-003 | SC-GSE-006, SC-GSE-007, SC-GSE-008, SC-GSE-010 | AC-G02 |
| REQ-GSE-004 | SC-GSE-006, SC-GSE-008, SC-GSE-009 | AC-G02 |
| REQ-GSE-005 | SC-GSE-011, SC-GSE-012, SC-GSE-013, SC-GSE-014 | AC-G01a |
| REQ-GSE-006 | - | AC-G03 |

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-GSE-001 | schema | REQ-GSE-001 | 新边类型 CHECK 约束 |
| CT-GSE-002 | behavior | REQ-GSE-001, SC-GSE-001 | IMPLEMENTS 边生成 |
| CT-GSE-003 | behavior | REQ-GSE-001, SC-GSE-002 | EXTENDS 边生成 |
| CT-GSE-004 | behavior | REQ-GSE-001, SC-GSE-003 | RETURNS_TYPE 边生成 |
| CT-GSE-005 | behavior | REQ-GSE-002, SC-GSE-004, SC-GSE-005 | 降级策略 |
| CT-GSE-006 | behavior | REQ-GSE-003, SC-GSE-006 | 基本路径查询 |
| CT-GSE-007 | behavior | REQ-GSE-003, SC-GSE-007 | 深度限制 |
| CT-GSE-008 | behavior | REQ-GSE-003, SC-GSE-008 | 无路径处理 |
| CT-GSE-009 | behavior | REQ-GSE-003, SC-GSE-010 | 环处理 |
| CT-GSE-010 | behavior | REQ-GSE-005, SC-GSE-011, SC-GSE-012 | 迁移检查 |
| CT-GSE-011 | behavior | REQ-GSE-005, SC-GSE-013 | 迁移执行 |

---

## 命令行接口（CLI）

### 路径查询

```bash
graph-store.sh find-path --from <node_id> --to <node_id> [--max-depth <n>] [--edge-types <types>]
```

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--from` | string | 是 | - | 源节点 ID |
| `--to` | string | 是 | - | 目标节点 ID |
| `--max-depth` | number | 否 | 10 | 最大搜索深度 |
| `--edge-types` | string | 否 | 全部 | 逗号分隔的边类型过滤 |

### Schema 迁移

```bash
graph-store.sh migrate [--check|--apply|--status]
```

| 子命令 | 说明 |
|--------|------|
| `--check` | 检查是否需要迁移 |
| `--apply` | 执行迁移（自动备份） |
| `--status` | 显示当前状态 |
