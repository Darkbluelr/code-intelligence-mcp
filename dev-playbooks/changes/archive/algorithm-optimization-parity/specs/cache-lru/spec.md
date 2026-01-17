# 规格：LRU 缓存与版本校验 (Cache LRU)

> **Capability ID**: ALG-010
> **模块**: cache-manager.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-CL-001: LRU 淘汰策略

**描述**: 当缓存达到容量上限时，淘汰最久未使用的条目。

**算法**:
1. 每次访问更新条目的访问时间戳
2. 插入新条目时，若超容量，删除访问时间最早的条目

---

### REQ-CL-002: 版本校验失效

**描述**: 缓存条目关联文件版本，文件修改后缓存自动失效。

**校验方式**:
- 比较文件修改时间（mtime）
- 比较文件内容哈希（可选）

---

### REQ-CL-003: 缓存容量配置

**描述**: 缓存最大条目数可配置。

**配置键**: `features.ast_delta.cache_max_size_mb`
**默认值**: 50 MB

---

### REQ-CL-004: 缓存 TTL

**描述**: 缓存条目有最大存活时间，超时自动失效。

**配置键**: `features.ast_delta.cache_ttl_days`
**默认值**: 30 天

---

### REQ-CL-005: 原子写入

**描述**: 缓存写入使用原子操作，避免并发写入导致数据损坏。

**实现**: 先写临时文件，再原子移动

---

## Scenarios

### SC-CL-001: 缓存命中

- **Given**: 文件 F 的缓存条目存在
- **And**: F 未被修改
- **When**: 获取 F 的缓存
- **Then**: 返回缓存内容
- **And**: 更新访问时间戳

### SC-CL-002: 版本失效

- **Given**: 文件 F 的缓存条目存在
- **And**: F 已被修改（mtime 更新）
- **When**: 获取 F 的缓存
- **Then**: 返回缓存未命中
- **And**: 删除旧缓存条目

### SC-CL-003: LRU 淘汰

- **Given**: 缓存已有 100 个条目（容量上限）
- **And**: 最旧条目为 X
- **When**: 添加新条目 Y
- **Then**: 删除条目 X
- **And**: 添加条目 Y

### SC-CL-004: TTL 过期

- **Given**: 缓存条目创建于 31 天前
- **And**: TTL = 30 天
- **When**: 获取该缓存
- **Then**: 返回缓存未命中
- **And**: 删除过期条目

### SC-CL-005: 并发写入

- **Given**: 两个进程同时写入同一缓存键
- **When**: 写入完成
- **Then**: 缓存文件完整
- **And**: 只保留最后一次写入的内容

### SC-CL-006: 空缓存初始化

- **Given**: 缓存目录不存在
- **When**: 首次写入缓存
- **Then**: 自动创建缓存目录
- **And**: 写入成功

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-CL-001 | behavior | SC-CL-001 |
| CT-CL-002 | behavior | SC-CL-002 |
| CT-CL-003 | behavior | SC-CL-003 |
| CT-CL-004 | behavior | SC-CL-004 |
| CT-CL-005 | concurrency | SC-CL-005 |
| CT-CL-006 | boundary | SC-CL-006 |
