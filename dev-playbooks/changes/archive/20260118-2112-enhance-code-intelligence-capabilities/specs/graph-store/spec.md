# 规格 Delta：图查询加速（闭包表）

> **Change-ID**: `20260118-2112-enhance-code-intelligence-capabilities`
> **Capability**: graph-store
> **Delta Type**: EXTEND
> **Version**: 2.0.0
> **Created**: 2026-01-19

---

## MODIFIED Requirements

### REQ-GS-008：Schema 版本管理（新增）

系统应支持 Schema 版本管理：

```sql
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  description TEXT
);
```

**当前版本**：v1 → v2

**版本检测**：
```bash
graph-store.sh --version
# 输出：Schema version: 2
```

**Trace**: AC-004, AC-012

---

### REQ-GS-009：闭包表实现（新增）

系统应实现闭包表以加速图查询：

```sql
CREATE TABLE IF NOT EXISTS transitive_closure (
  ancestor TEXT NOT NULL,
  descendant TEXT NOT NULL,
  depth INTEGER NOT NULL,
  PRIMARY KEY (ancestor, descendant)
);

CREATE INDEX idx_closure_ancestor ON transitive_closure(ancestor);
CREATE INDEX idx_closure_descendant ON transitive_closure(descendant);
CREATE INDEX idx_closure_depth ON transitive_closure(depth);
```

**预计算策略**：
- 启动时异步预计算
- 增量更新（新增边时更新闭包表）
- 支持手动重建：`graph-store.sh --rebuild-closure`

**Trace**: AC-004

---

### REQ-GS-010：路径索引表（新增）

系统应实现路径索引表以缓存常用路径：

```sql
CREATE TABLE IF NOT EXISTS path_index (
  path_id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL,
  target TEXT NOT NULL,
  path TEXT NOT NULL,  -- JSON 数组
  length INTEGER NOT NULL,
  frequency INTEGER DEFAULT 1,
  last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_path_source ON path_index(source);
CREATE INDEX idx_path_target ON path_index(target);
CREATE INDEX idx_path_length ON path_index(length);
```

**缓存策略**：
- 记录查询频率
- LRU 淘汰（保留最近访问的 1000 条路径）

**Trace**: AC-004

---

### REQ-GS-011：Schema 迁移（新增）

系统应支持自动 Schema 迁移：

```bash
graph-store.sh --migrate
```

**迁移步骤**：
1. 检测当前 Schema 版本
2. 备份数据库：`cp graph.db graph.db.backup`
3. 执行迁移 SQL
4. 预计算闭包表
5. 更新 schema_version
6. 验证数据完整性

**失败回滚**：
- 迁移失败时自动恢复备份
- 记录迁移日志到 `.devbooks/migration.log`

**Trace**: AC-004, AC-012

---

### REQ-GS-012：图查询性能优化（新增）

系统应使用闭包表优化图查询：

```sql
-- 原查询（递归 CTE，慢）
WITH RECURSIVE paths AS (
  SELECT source_id, target_id, 1 as depth
  FROM edges
  WHERE source_id = ?
  UNION ALL
  SELECT p.source_id, e.target_id, p.depth + 1
  FROM paths p
  JOIN edges e ON p.target_id = e.source_id
  WHERE p.depth < ?
)
SELECT * FROM paths;

-- 优化查询（闭包表，快）
SELECT ancestor, descendant, depth
FROM transitive_closure
WHERE ancestor = ? AND depth <= ?;
```

**性能目标**：
- 3 跳查询 P95 延迟 < 200ms
- 相比递归 CTE 提升 > 5x

**Trace**: AC-004

---

## ADDED Scenarios

### SC-GS-012：Schema 迁移成功

**Given**: 数据库 Schema 版本为 v1
**When**: 运行 `graph-store.sh --migrate`
**Then**:
- 备份数据库到 `graph.db.backup`
- 创建闭包表和路径索引表
- 预计算闭包表
- 更新 schema_version 为 2
- 输出：`Migration completed successfully`

**Trace**: AC-004, AC-012

---

### SC-GS-013：Schema 迁移失败回滚

**Given**: 迁移过程中发生错误（如磁盘空间不足）
**When**: 运行 `graph-store.sh --migrate`
**Then**:
- 检测到错误
- 自动恢复备份：`mv graph.db.backup graph.db`
- 输出错误消息和回滚日志
- 数据库保持原状态

**Trace**: AC-012

---

### SC-GS-014：闭包表查询性能

**Given**: 图包含 500 个节点，3000 条边
**When**: 运行 3 跳查询 100 次
**Then**:
- P95 延迟 < 200ms
- 平均延迟 < 100ms
- 相比递归 CTE 提升 > 5x

**Trace**: AC-004

---

### SC-GS-015：增量更新闭包表

**Given**: 闭包表已预计算
**When**: 新增一条边 A → B
**Then**:
- 自动更新闭包表（新增 A 的所有祖先到 B 的所有后代的路径）
- 更新耗时 < 50ms
- 不需要重建整个闭包表

**Trace**: AC-004

---

### SC-GS-016：手动重建闭包表

**Given**: 闭包表数据不一致或损坏
**When**: 运行 `graph-store.sh --rebuild-closure`
**Then**:
- 清空闭包表
- 重新计算所有可达路径
- 输出进度：`Processing 100/500 nodes...`
- 完成后输出：`Closure table rebuilt successfully`

**Trace**: AC-004

---

### SC-GS-017：跳过预计算

**Given**: 用户希望快速启动，跳过预计算
**When**: 运行 `graph-store.sh --migrate --skip-precompute`
**Then**:
- 创建闭包表结构
- 不预计算数据
- 首次查询时按需计算并缓存

**Trace**: AC-004

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-GS-008（新增） | SC-GS-012, SC-GS-013 | AC-004, AC-012 |
| REQ-GS-009（新增） | SC-GS-014, SC-GS-015, SC-GS-016 | AC-004 |
| REQ-GS-010（新增） | SC-GS-014 | AC-004 |
| REQ-GS-011（新增） | SC-GS-012, SC-GS-013 | AC-004, AC-012 |
| REQ-GS-012（新增） | SC-GS-014 | AC-004 |

---

## 与现有规格的关系

**扩展自**：`dev-playbooks/specs/graph-store/spec.md` v1.0.0

**主要变更**：
1. 新增 Schema 版本管理（v1 → v2）
2. 新增闭包表实现
3. 新增路径索引表
4. 新增自动迁移逻辑
5. 优化图查询性能（P95 < 200ms）

**兼容性**：
- 自动迁移，向后兼容
- 通过 `graph_acceleration` 配置开关控制
- 迁移失败时自动回滚

---

## 非功能需求

### 性能基准

| 场景 | 指标 | 阈值 |
|------|------|------|
| 3 跳查询（500 节点） | P95 延迟 | < 200ms |
| 闭包表预计算（500 节点） | 耗时 | < 10s |
| 增量更新闭包表 | 耗时 | < 50ms |
| Schema 迁移 | 耗时 | < 5min |

### 存储空间

| 数据 | 大小估算 |
|------|----------|
| 闭包表（500 节点） | 约 2-3x 原图大小 |
| 路径索引表 | 约 500KB（1000 条路径） |
| 总增量 | 约 500MB（10000 节点） |
