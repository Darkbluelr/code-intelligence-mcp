# 规格：SCIP 解析转换（scip-parser）

> **Change ID**: `augment-parity`
> **Capability**: scip-parser
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-15

---

## Requirements（需求）

### REQ-SP-001：SCIP 索引解析

系统应能解析 SCIP protobuf 格式的索引文件，提取符号和引用信息。

**约束**：
- 使用 protobufjs 解析 SCIP 格式
- 默认索引文件路径：`index.scip`
- 支持通过环境变量 `SCIP_INDEX_PATH` 指定路径

### REQ-SP-002：符号提取

系统应从 SCIP 索引中提取以下符号信息：

| 提取项 | SCIP 数据来源 | 说明 |
|--------|--------------|------|
| 符号 ID | `occurrence.symbol` | 唯一标识 |
| 符号名称 | 从 symbol 解析 | 最后一段 |
| 符号类型 | symbol 前缀 | function/class/variable 等 |
| 文件路径 | `document.relative_path` | 相对项目根 |
| 行号范围 | `occurrence.range` | [start_line, start_col, end_line, end_col] |

### REQ-SP-003：边类型映射

系统应根据 SCIP `symbol_roles` 映射到图边类型：

| symbol_roles 值 | 边类型 | 说明 |
|-----------------|--------|------|
| 1 (Definition) | DEFINES | 定义关系 |
| 2 (Import) | IMPORTS | 导入关系 |
| 4 (WriteAccess) | MODIFIES | 写入/修改关系 |
| 8 (ReadAccess) | CALLS | 读取/调用关系 |

### REQ-SP-004：图数据写入

系统应将解析结果写入 SQLite 图存储：

1. 为每个定义创建节点
2. 为每个引用创建边（定义节点 → 引用位置）
3. 使用批量写入提高效率

### REQ-SP-005：增量更新

系统应支持增量更新策略：

- 检测 SCIP 索引文件 mtime
- 若索引比数据库新，执行更新
- 更新时先清理对应文件的旧数据

### REQ-SP-006：降级策略

当 SCIP 解析失败时，系统应降级到正则匹配：

| 边类型 | 降级正则模式 |
|--------|-------------|
| CALLS | `\b(\w+)\s*\(` |
| IMPORTS | `import .* from ['"](.*)['"]` |
| DEFINES | `(function|class|const|let|var)\s+(\w+)` |

**约束**：降级时输出警告日志，标记置信度为 "low"。

### REQ-SP-007：解析统计

系统应输出解析统计信息：

- 解析的文档数
- 提取的符号数
- 提取的引用数
- 各边类型数量

---

## Scenarios（场景）

### SC-SP-001：成功解析 SCIP 索引

**Given**:
- 存在有效的 `index.scip` 文件（scip-typescript 生成）
- 图数据库已初始化
**When**: 执行 `scip-to-graph.sh parse`
**Then**:
- 解析成功，无错误
- 节点数 >= 187（当前项目基准）
- 边数 >= 307（当前项目基准）
- 输出解析统计信息

### SC-SP-002：边类型正确映射

**Given**: SCIP 索引包含以下 occurrence：
```
symbol: "npm scip-typescript 0.4.0 src/`server.ts`/main()."
symbol_roles: 1 (Definition)
```
**When**: 执行解析
**Then**:
- 创建节点，symbol = "main", kind = "function"
- 创建 DEFINES 类型边（若有引用）

### SC-SP-003：处理 ReadAccess 引用

**Given**: SCIP 索引包含：
- 节点 A 定义（symbol_roles = 1）
- 节点 B 对 A 的引用（symbol_roles = 8, ReadAccess）
**When**: 执行解析
**Then**:
- 创建边：B → A, type = CALLS

### SC-SP-004：SCIP 文件不存在

**Given**: `index.scip` 文件不存在
**When**: 执行 `scip-to-graph.sh parse`
**Then**:
- 返回错误：`SCIP index not found: index.scip`
- 提示运行索引命令：`Run: npx scip-typescript index`
- 退出码 1

### SC-SP-005：SCIP 解析失败降级

**Given**: `index.scip` 文件损坏或格式不兼容
**When**: 执行 `scip-to-graph.sh parse`
**Then**:
- 输出警告：`SCIP parsing failed, falling back to regex matching`
- 使用正则匹配扫描源文件
- 输出置信度标记：`confidence: low`
- 仍然生成图数据（精度降低）

### SC-SP-006：增量更新检测

**Given**:
- 图数据库存在且有数据
- `index.scip` mtime > 图数据库 mtime
**When**: 执行 `scip-to-graph.sh parse --incremental`
**Then**:
- 检测到索引更新
- 清理旧数据
- 重新导入新数据
- 输出：`Incremental update: index newer than database`

### SC-SP-007：无需更新

**Given**:
- 图数据库存在且有数据
- `index.scip` mtime < 图数据库 mtime
**When**: 执行 `scip-to-graph.sh parse --incremental`
**Then**:
- 输出：`Database up-to-date, skipping parse`
- 不执行解析
- 退出码 0

### SC-SP-008：强制完全重建

**Given**: 图数据库已存在
**When**: 执行 `scip-to-graph.sh parse --force`
**Then**:
- 清空现有数据
- 完全重新解析
- 输出：`Force rebuild: cleared existing data`

### SC-SP-009：解析统计输出

**Given**: 解析完成
**When**: 查看输出
**Then**:
- 输出 JSON 格式统计：
  ```json
  {
    "documents": 1,
    "symbols": 187,
    "occurrences": 494,
    "edges": {
      "DEFINES": 187,
      "IMPORTS": 0,
      "CALLS": 307,
      "MODIFIES": 0
    },
    "confidence": "high",
    "source": "scip"
  }
  ```

### SC-SP-010：自定义索引路径

**Given**: SCIP 索引位于 `build/index.scip`
**When**: 执行 `SCIP_INDEX_PATH=build/index.scip scip-to-graph.sh parse`
**Then**:
- 从 `build/index.scip` 读取索引
- 解析成功

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-SP-001 | SC-SP-001, SC-SP-004, SC-SP-010 | AC-002 |
| REQ-SP-002 | SC-SP-001, SC-SP-002 | AC-002 |
| REQ-SP-003 | SC-SP-002, SC-SP-003 | AC-002 |
| REQ-SP-004 | SC-SP-001 | AC-002 |
| REQ-SP-005 | SC-SP-006, SC-SP-007, SC-SP-008 | AC-002 |
| REQ-SP-006 | SC-SP-005 | AC-002 |
| REQ-SP-007 | SC-SP-009 | AC-002 |
