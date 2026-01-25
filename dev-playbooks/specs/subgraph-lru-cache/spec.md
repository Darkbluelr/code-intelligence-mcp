---
last_referenced_by: augment-parity-final-gaps
last_verified: 2026-01-16
health: active
---


# Spec Delta: 子图 LRU 缓存（subgraph-lru-cache）

> **Change ID**: `augment-parity-final-gaps`
> **Capability**: subgraph-lru-cache
> **Base Spec**: `dev-playbooks/specs/cache-manager/spec.md`
> **Version**: 2.0.0
> **Status**: Draft
> **Created**: 2026-01-16

---

## 概述

本规格增量扩展现有 cache-manager 规格，新增：
1. **子图 LRU 缓存**：热点子图持久化缓存，支持跨进程共享
2. **SQLite 持久化**：使用 SQLite 替代 Bash 关联数组，解决进程隔离问题

---

## Requirements（需求）

### REQ-SLC-001：子图缓存存储

系统应使用 SQLite 数据库存储子图缓存：

- 数据库文件：`.devbooks/subgraph-cache.db`
- 启用 WAL 模式（支持并发读）
- 支持跨进程共享

### REQ-SLC-002：缓存表结构

缓存表结构如下：

```sql
CREATE TABLE IF NOT EXISTS subgraph_cache (
    cache_key TEXT PRIMARY KEY,
    cache_value TEXT NOT NULL,
    access_time INTEGER NOT NULL,
    created_time INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_access_time ON subgraph_cache(access_time);
```

### REQ-SLC-003：LRU 淘汰策略

当缓存条目达到上限时，系统应执行 LRU 淘汰：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `CACHE_MAX_SIZE` | 100 | 最大缓存条目数 |

**淘汰规则**：
- 删除 `access_time` 最旧的条目
- 在写入新条目的同一事务中执行淘汰
- 淘汰后条目数 ≤ `CACHE_MAX_SIZE`

### REQ-SLC-004：缓存 Key 计算

子图缓存 Key 计算规则：

```
<root_node_id>:<edge_types>:<depth>:<options_hash>
```

| 组成部分 | 说明 |
|----------|------|
| root_node_id | 子图根节点 ID |
| edge_types | 包含的边类型（排序后拼接） |
| depth | 子图深度 |
| options_hash | 其他选项的 MD5 哈希 |

### REQ-SLC-005：缓存读取（更新访问时间）

读取缓存时应更新访问时间：

```sql
UPDATE subgraph_cache SET access_time = $now WHERE cache_key = '$key';
SELECT cache_value FROM subgraph_cache WHERE cache_key = '$key';
```

**约束**：
- 读取和更新在同一事务中执行
- 缓存未命中时返回空，不报错

### REQ-SLC-006：缓存写入（带淘汰）

写入缓存时应在同一事务中执行淘汰：

```sql
BEGIN;
-- 淘汰最旧条目（如果超过上限）
DELETE FROM subgraph_cache
WHERE cache_key IN (
    SELECT cache_key FROM subgraph_cache
    ORDER BY access_time ASC
    LIMIT MAX(0, (SELECT COUNT(*) FROM subgraph_cache) - $MAX_SIZE + 1)
);
-- 插入或更新
INSERT OR REPLACE INTO subgraph_cache (cache_key, cache_value, access_time, created_time)
VALUES ('$key', '$value', $now, COALESCE(
    (SELECT created_time FROM subgraph_cache WHERE cache_key = '$key'), $now
));
COMMIT;
```

### REQ-SLC-007：缓存统计

系统应提供缓存统计信息：

```json
{
  "total_entries": 85,
  "oldest_access": 1705132800,
  "newest_access": 1705133600,
  "hit_rate": 0.85,
  "cache_size_bytes": 512000
}
```

### REQ-SLC-008：跨进程共享

缓存应支持跨进程共享：

- 进程 A 写入缓存
- 进程 B 立即可读取
- 无需进程间通信

**验证方式**：
```bash
# 进程 1 写入
./scripts/cache-manager.sh cache-set "key1" "value1"

# 进程 2 读取（新进程）
./scripts/cache-manager.sh cache-get "key1"  # 应返回 "value1"
```

### REQ-SLC-009：缓存命中率计算

系统应跟踪缓存命中率：

| 统计项 | 说明 |
|--------|------|
| `hits` | 缓存命中次数 |
| `misses` | 缓存未命中次数 |
| `hit_rate` | `hits / (hits + misses)` |

**存储位置**：单独的统计表或文件

---

## Scenarios（场景）

### SC-SLC-001：缓存写入

**Given**:
- 缓存数据库已初始化
- 缓存当前有 50 条目（低于上限）
**When**: 执行 `cache-manager.sh cache-set "key1" "value1"`
**Then**:
- 条目写入 `subgraph_cache` 表
- `access_time` 和 `created_time` 设置为当前时间
- 返回成功

### SC-SLC-002：缓存读取（命中）

**Given**:
- 缓存包含 `key1` → `value1`
**When**: 执行 `cache-manager.sh cache-get "key1"`
**Then**:
- 返回 `value1`
- 更新 `access_time` 为当前时间
- 命中计数 +1

### SC-SLC-003：缓存读取（未命中）

**Given**:
- 缓存不包含 `key2`
**When**: 执行 `cache-manager.sh cache-get "key2"`
**Then**:
- 返回空
- 退出码 1
- 未命中计数 +1

### SC-SLC-004：LRU 淘汰

**Given**:
- 缓存已有 100 条目（达到上限）
- 最旧条目的 `access_time` 为 T0
**When**: 写入第 101 条目
**Then**:
- 删除 `access_time` = T0 的条目
- 写入新条目
- 总条目数仍为 100

### SC-SLC-005：跨进程缓存共享

**Given**:
- 进程 A 写入缓存 `key1` → `value1`
- 进程 A 退出
**When**: 进程 B（新进程）读取 `key1`
**Then**:
- 返回 `value1`
- 证明缓存跨进程持久化

### SC-SLC-006：命中率计算

**Given**:
- 执行 10 次查询
- 8 次命中，2 次未命中
**When**: 执行 `cache-manager.sh stats`
**Then**:
- 返回 `hit_rate: 0.8`
- 返回 `hits: 8`
- 返回 `misses: 2`

### SC-SLC-007：缓存初始化

**Given**:
- 缓存数据库不存在
**When**: 首次调用缓存操作
**Then**:
- 创建 `.devbooks/subgraph-cache.db`
- 创建 `subgraph_cache` 表
- 创建索引
- 启用 WAL 模式

### SC-SLC-008：并发写入

**Given**:
- 两个进程同时写入不同 Key
**When**: 并发执行
**Then**:
- 两个条目都写入成功
- 无数据损坏
- WAL 模式处理并发

### SC-SLC-009：重复 Key 更新

**Given**:
- 缓存包含 `key1` → `value1`，`created_time` = T0
**When**: 执行 `cache-set "key1" "value2"`
**Then**:
- `cache_value` 更新为 `value2`
- `access_time` 更新为当前时间
- `created_time` 保持为 T0

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-SLC-001 | SC-SLC-007 | AC-G07 |
| REQ-SLC-002 | SC-SLC-007 | AC-G07 |
| REQ-SLC-003 | SC-SLC-004 | AC-G07 |
| REQ-SLC-004 | SC-SLC-001, SC-SLC-002 | AC-G07 |
| REQ-SLC-005 | SC-SLC-002, SC-SLC-003 | AC-G07 |
| REQ-SLC-006 | SC-SLC-001, SC-SLC-004, SC-SLC-009 | AC-G07 |
| REQ-SLC-007 | SC-SLC-006 | AC-G07 |
| REQ-SLC-008 | SC-SLC-005 | AC-G07 |
| REQ-SLC-009 | SC-SLC-006 | AC-G07 |

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-SLC-001 | behavior | REQ-SLC-001, SC-SLC-007 | 缓存初始化 |
| CT-SLC-002 | behavior | REQ-SLC-005, SC-SLC-002 | 缓存读取（命中） |
| CT-SLC-003 | behavior | REQ-SLC-005, SC-SLC-003 | 缓存读取（未命中） |
| CT-SLC-004 | behavior | REQ-SLC-006, SC-SLC-001 | 缓存写入 |
| CT-SLC-005 | behavior | REQ-SLC-003, SC-SLC-004 | LRU 淘汰 |
| CT-SLC-006 | behavior | REQ-SLC-008, SC-SLC-005 | 跨进程共享 |
| CT-SLC-007 | behavior | REQ-SLC-009, SC-SLC-006 | 命中率计算 |
| CT-SLC-008 | behavior | SC-SLC-008 | 并发写入 |

---

## 命令行接口（CLI）

```bash
cache-manager.sh <command> [options]
```

| 命令 | 说明 |
|------|------|
| `cache-set <key> <value>` | 写入缓存 |
| `cache-get <key>` | 读取缓存 |
| `cache-delete <key>` | 删除缓存 |
| `cache-clear` | 清空所有缓存 |
| `stats` | 显示缓存统计 |
| `warmup-symbols` | 预热常用符号到缓存 |

| 选项 | 说明 |
|------|------|
| `--max-size <n>` | 覆盖默认最大条目数 |
| `--format json|text` | 输出格式 |

---

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `CACHE_MAX_SIZE` | 100 | 最大缓存条目数 |
| `SUBGRAPH_CACHE_DB` | `.devbooks/subgraph-cache.db` | 缓存数据库路径 |
| `CACHE_DEBUG` | 0 | 启用调试日志 |
