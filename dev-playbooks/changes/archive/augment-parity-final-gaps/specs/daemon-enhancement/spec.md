# Spec Delta: 守护进程增强（daemon-enhancement）

> **Change ID**: `augment-parity-final-gaps`
> **Capability**: daemon-enhancement
> **Base Spec**: `dev-playbooks/specs/daemon/spec.md`
> **Version**: 2.0.0
> **Status**: Draft
> **Created**: 2026-01-16

---

## 概述

本规格增量扩展现有 daemon 规格，新增：
1. **预热机制**：启动时预加载高频查询和热点子图
2. **请求取消机制**：支持请求取消令牌，检测新请求时终止旧请求

---

## Requirements（需求）

### REQ-DME-001：预热机制

系统应支持启动时预热，降低冷启动延迟：

**预热内容**：
| 预热项 | 来源 | 优先级 |
|--------|------|--------|
| 热点文件子图 | `hotspot-analyzer.sh` Top 10 | P0 |
| 常用查询 | 预配置查询列表 | P1 |
| 符号索引 | `cache-manager.sh` | P2 |

**约束**：
- 预热在后台异步执行，不阻塞启动
- 预热超时：30 秒
- 预热失败不影响正常服务

### REQ-DME-002：预热配置

系统应支持预热配置：

```yaml
# config/features.yaml
daemon:
  warmup:
    enabled: true
    timeout_seconds: 30
    queries:
      - "main"
      - "server"
      - "handler"
    hotspot_limit: 10
```

### REQ-DME-003：预热状态查询

系统应提供预热状态查询：

```json
{
  "warmup_status": "completed|in_progress|disabled|failed",
  "warmup_started_at": "2026-01-16T10:00:00Z",
  "warmup_completed_at": "2026-01-16T10:00:05Z",
  "items_cached": 15
}
```

### REQ-DME-004：请求取消机制

系统应支持请求取消，释放资源：

**取消触发条件**：
- 收到同一客户端的新请求
- 收到显式取消信号

**取消机制**：
- 使用 `flock` 文件锁保证原子性
- 取消信号文件：`.devbooks/cancel/<request_id>`
- 取消检测间隔：每个处理步骤前检查

### REQ-DME-005：请求取消协议

**取消信号文件格式**：
- 文件存在且内容为空：请求进行中
- 文件存在且内容非空（`cancelled`）：请求已取消
- 文件不存在：请求已完成或从未开始

**原子性保证**：
```bash
# 使用 flock 保证取消操作原子性
(
    flock -x 200
    echo "cancelled" > "$cancel_file"
) 200>"$LOCK_FILE"
```

### REQ-DME-006：取消响应时间

请求取消应在 100ms 内生效：

| 指标 | 目标值 |
|------|--------|
| 取消检测延迟 | < 100ms |
| 资源释放时间 | < 200ms |

### REQ-DME-007：取消后清理

请求取消后应正确清理资源：

- 终止子进程
- 释放文件锁
- 删除临时文件
- 记录取消日志

---

## Scenarios（场景）

### SC-DME-001：预热成功

**Given**:
- 守护进程启动
- 预热配置启用
- 热点文件存在
**When**: 执行预热
**Then**:
- 加载 Top 10 热点文件子图到缓存
- 执行预配置查询
- `cache-manager.sh stats` 显示已缓存条目 > 0
- `warmup_status` = `completed`

### SC-DME-002：预热超时

**Given**:
- 预热配置启用
- 预热超时设为 5 秒
- 热点文件数量很大（预热需 10 秒）
**When**: 执行预热
**Then**:
- 5 秒后预热超时中断
- 已完成的部分缓存保留
- `warmup_status` = `completed`（部分完成）
- 记录警告日志

### SC-DME-003：预热禁用

**Given**:
- 预热配置 `enabled: false`
**When**: 启动守护进程
**Then**:
- 跳过预热
- `warmup_status` = `disabled`
- 正常启动服务

### SC-DME-004：请求取消 - 新请求触发

**Given**:
- 守护进程正在处理请求 A（长时间查询）
**When**: 同一客户端发起请求 B
**Then**:
- 请求 A 在 100ms 内被取消
- 请求 A 返回取消响应：`{"status": "cancelled"}`
- 请求 B 开始处理

### SC-DME-005：请求取消 - 资源清理

**Given**:
- 请求 A 正在执行，占用文件锁
**When**: 请求 A 被取消
**Then**:
- 文件锁释放
- 临时文件删除
- 取消信号文件删除
- 日志记录：`Request A cancelled`

### SC-DME-006：请求取消 - 并发安全

**Given**:
- 多个并发请求同时到达
**When**: 使用 flock 处理取消
**Then**:
- 取消操作串行化
- 无竞态条件
- 最新请求执行，旧请求取消

### SC-DME-007：正常请求完成

**Given**:
- 请求 A 正在处理
- 无新请求或取消信号
**When**: 请求 A 处理完成
**Then**:
- 返回正常响应
- 清理取消信号文件
- `status` = `ok`

### SC-DME-008：预热状态查询

**Given**:
- 预热已完成
- 缓存了 15 个条目
**When**: 执行 `daemon.sh status`
**Then**:
- 输出包含 `warmup_status: completed`
- 输出包含 `items_cached: 15`
- 输出包含预热完成时间

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-DME-001 | SC-DME-001, SC-DME-002 | AC-G05 |
| REQ-DME-002 | SC-DME-001, SC-DME-003 | AC-G05 |
| REQ-DME-003 | SC-DME-008 | AC-G05 |
| REQ-DME-004 | SC-DME-004, SC-DME-006 | AC-G06 |
| REQ-DME-005 | SC-DME-004, SC-DME-006 | AC-G06 |
| REQ-DME-006 | SC-DME-004 | AC-G06 |
| REQ-DME-007 | SC-DME-005, SC-DME-007 | AC-G06 |

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-DME-001 | behavior | REQ-DME-001, SC-DME-001 | 预热成功 |
| CT-DME-002 | behavior | REQ-DME-001, SC-DME-002 | 预热超时 |
| CT-DME-003 | behavior | REQ-DME-002, SC-DME-003 | 预热禁用 |
| CT-DME-004 | behavior | REQ-DME-004, SC-DME-004 | 请求取消触发 |
| CT-DME-005 | behavior | REQ-DME-007, SC-DME-005 | 资源清理 |
| CT-DME-006 | behavior | REQ-DME-005, SC-DME-006 | 并发安全 |
| CT-DME-007 | behavior | REQ-DME-006, SC-DME-004 | 取消响应时间 |

---

## 命令行接口（CLI）

### 预热命令

```bash
daemon.sh warmup [--timeout <seconds>] [--queries <q1,q2>]
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--timeout` | number | 30 | 预热超时秒数 |
| `--queries` | string | 配置文件 | 预热查询列表 |

### 状态输出扩展

```json
{
  "running": true,
  "pid": 12345,
  "uptime_seconds": 3600,
  "queue_size": 2,
  "last_heartbeat": "2026-01-16T10:30:00Z",
  "warmup_status": "completed",
  "warmup_completed_at": "2026-01-16T10:00:05Z",
  "items_cached": 15
}
```
