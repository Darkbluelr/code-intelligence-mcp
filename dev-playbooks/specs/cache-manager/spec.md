# Spec: Cache Manager（多级缓存管理）

> **Change ID**: `augment-upgrade-phase2`
> **Capability**: cache-manager
> **Version**: 1.0.0
> **Status**: Approved

---

## Requirements

### REQ-CACHE-001: 多级缓存架构

系统应提供两级缓存架构：
- **L1（内存层）**：会话级缓存，使用 Bash 关联数组
- **L2（文件层）**：跨会话缓存，使用 JSON 文件存储

**约束**：
- L1 缓存在脚本进程结束时自动失效
- L2 缓存持久化到 `$CACHE_DIR/l2/` 目录

---

### REQ-CACHE-002: 精确缓存失效

缓存条目必须基于以下条件失效：

| 条件 | 检测方式 | 行为 |
|------|----------|------|
| 文件 mtime 变化 | `stat -c %Y` / `stat -f %m` | 立即失效 |
| Git blob hash 变化 | `git hash-object <file>` | 立即失效 |
| mtime 变化间隔 < 1s | 时间戳比较 | 视为"写入中"，跳过缓存 |

**约束**：
- 禁止使用 TTL（时间到期）失效策略
- Untracked 文件使用 `md5sum`/`md5` 替代 blob hash

---

### REQ-CACHE-003: 缓存 Key 格式

缓存 Key 必须包含以下组成部分：

```
<file_path>:<mtime>:<blob_hash>:<query_hash>
```

| 组成部分 | 来源 | 说明 |
|----------|------|------|
| file_path | 输入参数 | 原始文件路径 |
| mtime | `stat` 命令 | 文件最后修改时间戳 |
| blob_hash | `git hash-object` 或 `md5` | 文件内容指纹 |
| query_hash | `md5sum <<< "$query"` | 查询参数指纹 |

---

### REQ-CACHE-004: 竞态条件处理

系统必须处理以下竞态条件：

| 竞态场景 | 处理策略 |
|----------|----------|
| 文件写入中 | 检测 mtime 变化间隔 < 1s，跳过缓存直接计算 |
| 并发读写 | 使用 `flock` 文件锁保护缓存写入 |
| 原子写入 | 先写临时文件 `*.tmp.$$`，再 `mv` 替换 |

---

### REQ-CACHE-005: LRU 淘汰策略

当缓存占用达到上限时，必须执行 LRU 淘汰：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `CACHE_MAX_SIZE_MB` | 50 | 缓存上限（MB） |
| 淘汰比例 | 20% | 删除最旧条目的比例 |
| 排序依据 | `accessed_at` 字段 | 按最后访问时间排序 |

**约束**：
- 必须记录淘汰事件到日志
- 淘汰后缓存大小必须低于上限

---

### REQ-CACHE-006: 缓存条目格式

L2 缓存条目必须使用以下 JSON 格式：

```json
{
  "schema_version": "1.0.0",
  "key": "<computed_key>",
  "file_path": "src/server.ts",
  "mtime": 1705132800,
  "blob_hash": "a1b2c3d4e5f6...",
  "query_hash": "x1y2z3...",
  "value": "<cached_result>",
  "created_at": 1705132800,
  "accessed_at": 1705132800
}
```

**约束**：
- `schema_version` 变更时，不兼容的旧条目自动失效

---

## Scenarios

### SC-CACHE-001: L1 缓存命中

**Given**: 同一会话内已执行过相同查询
**When**: 再次执行相同查询
**Then**:
- 直接从内存返回结果
- 延迟 < 10ms
- 不触发文件 I/O

---

### SC-CACHE-002: L2 缓存命中

**Given**: 跨会话但文件未变更
**When**: 执行相同查询
**Then**:
- 从 L2 文件缓存读取
- 验证 mtime + blob hash
- 延迟 < 100ms
- 结果写入 L1

---

### SC-CACHE-003: 缓存未命中

**Given**: 首次查询或文件已变更
**When**: 执行查询
**Then**:
- 执行完整计算
- 结果同时写入 L1 + L2
- 缓存 Key 包含正确的 blob hash

---

### SC-CACHE-004: 文件写入中检测

**Given**: 文件正在被写入（mtime 变化 < 1s）
**When**: 执行缓存查询
**Then**:
- 跳过缓存
- 直接执行计算
- 不写入缓存

---

### SC-CACHE-005: 并发写入保护

**Given**: 两个进程同时写入同一缓存 Key
**When**: 并发执行
**Then**:
- 使用 `flock -x` 串行化写入
- 最终缓存内容一致
- 无数据损坏

---

### SC-CACHE-006: LRU 淘汰触发

**Given**: 缓存占用达到 50MB 上限
**When**: 写入新缓存条目
**Then**:
- 删除 `accessed_at` 最旧的 20% 条目
- 记录淘汰日志
- 写入成功

---

### SC-CACHE-007: Git 不可用降级

**Given**: 文件不在 Git 仓库中或 Git 不可用
**When**: 计算 blob hash
**Then**:
- 降级使用 `md5sum`/`md5` 计算内容指纹
- 缓存功能正常工作

---

### SC-CACHE-008: Schema 版本不兼容

**Given**: L2 缓存条目的 `schema_version` 与当前版本不兼容
**When**: 读取缓存
**Then**:
- 视为缓存未命中
- 删除旧条目
- 重新计算并写入新格式

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-CACHE-001 | behavior | REQ-CACHE-001, SC-CACHE-001 | L1 命中路径 |
| CT-CACHE-002 | behavior | REQ-CACHE-001, SC-CACHE-002 | L2 命中路径 |
| CT-CACHE-003 | behavior | REQ-CACHE-002, SC-CACHE-003 | 缓存失效重算 |
| CT-CACHE-004 | behavior | REQ-CACHE-004, SC-CACHE-004 | 写入中检测 |
| CT-CACHE-005 | behavior | REQ-CACHE-004, SC-CACHE-005 | 并发写入保护 |
| CT-CACHE-006 | behavior | REQ-CACHE-005, SC-CACHE-006 | LRU 淘汰 |
| CT-CACHE-007 | behavior | REQ-CACHE-002, SC-CACHE-007 | Git 不可用降级 |
| CT-CACHE-008 | schema | REQ-CACHE-006, SC-CACHE-008 | Schema 兼容性 |

---

## 环境变量接口

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `CACHE_DIR` | `.ci-cache` | 缓存根目录 |
| `CACHE_MAX_SIZE_MB` | `50` | 缓存上限（MB） |
| `GIT_HASH_CMD` | `git hash-object` | Git hash 命令（可 Mock） |
| `CACHE_DEBUG` | `0` | 启用调试日志 |
