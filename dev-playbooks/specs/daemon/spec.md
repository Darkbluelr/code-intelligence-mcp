# 规格：常驻守护进程（daemon）

> **Change ID**: `augment-parity`
> **Capability**: daemon
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-15

---

## Requirements（需求）

### REQ-DM-001：守护进程启动

系统应支持启动常驻守护进程，监听 Unix Socket 请求。

**约束**：
- Socket 路径：`.devbooks/daemon.sock`
- PID 文件：`.devbooks/daemon.pid`
- 单实例约束：同一项目只允许一个守护进程

### REQ-DM-002：PID 文件锁机制

系统应通过 PID 文件防止多实例冲突：

1. 启动时检查 PID 文件是否存在
2. 若存在，验证进程是否仍在运行
3. 若进程已死，清理陈旧 PID 文件和 Socket
4. 若进程存活，拒绝启动并提示

### REQ-DM-003：请求处理

守护进程应支持以下请求类型：

| action | 功能 | 说明 |
|--------|------|------|
| ping | 健康检查 | 返回 `{"status": "ok"}` |
| query | 图查询 | 执行 SQL 查询并返回结果 |
| write | 图写入 | 执行写入操作 |
| stats | 统计信息 | 返回数据库统计 |

### REQ-DM-004：请求队列

系统应使用请求队列处理并发请求：

- 单线程顺序处理（FIFO）
- 队列长度上限：10 个待处理请求
- 队列满时返回 `{"status": "busy"}` 响应

### REQ-DM-005：通信协议

请求和响应应使用 JSON 格式：

**请求格式**：
```json
{
  "action": "query|write|ping|stats",
  "payload": { ... }
}
```

**响应格式**：
```json
{
  "status": "ok|error|busy",
  "data": [...],
  "latency_ms": 15,
  "error_message": "optional"
}
```

### REQ-DM-006：生命周期管理

系统应支持以下生命周期操作：

| 操作 | 命令 | 说明 |
|------|------|------|
| 启动 | `daemon.sh start` | 后台启动守护进程 |
| 停止 | `daemon.sh stop` | 优雅停止守护进程 |
| 重启 | `daemon.sh restart` | 停止后重新启动 |
| 状态 | `daemon.sh status` | 检查运行状态 |

### REQ-DM-007：崩溃恢复

系统应支持崩溃后自动重启：

- 最大重启次数：3 次
- 重启间隔：指数退避（2s → 4s → 8s）
- 超过重试上限后进入 FAILED 状态

### REQ-DM-008：心跳检测

守护进程应定期写入心跳记录：

- 心跳间隔：30 秒
- 心跳文件：`.devbooks/daemon.heartbeat`（覆盖写入）
- 心跳超时：60 秒（超时视为死亡）

### REQ-DM-009：日志轮转

系统应支持日志轮转：

- 日志文件：`.devbooks/daemon.log`
- 轮转阈值：10MB
- 保留策略：压缩旧日志（`.log.1.gz`）

### REQ-DM-010：优雅退出

收到 SIGTERM/SIGINT 时应优雅退出：

1. 停止接受新请求
2. 完成当前正在处理的请求
3. 清理 PID 文件和 Socket 文件
4. 记录退出日志

---

## Scenarios（场景）

### SC-DM-001：首次启动守护进程

**Given**: 项目目录下无运行中的守护进程
**When**: 执行 `daemon.sh start`
**Then**:
- 创建 `.devbooks/daemon.pid` 文件
- 创建 `.devbooks/daemon.sock` Unix Socket
- 开始监听请求
- 输出：`Daemon started (PID: xxx)`

### SC-DM-002：防止多实例启动

**Given**: 守护进程已在运行（PID 12345）
**When**: 执行 `daemon.sh start`
**Then**:
- 检测到已有实例运行
- 输出：`Daemon already running (PID: 12345)`
- 退出码 1，不启动新实例

### SC-DM-003：清理陈旧 PID 文件

**Given**:
- 存在 `.devbooks/daemon.pid` 文件（内容为 99999）
- 但进程 99999 已不存在
**When**: 执行 `daemon.sh start`
**Then**:
- 检测到陈旧 PID 文件
- 输出：`Cleaning stale PID file`
- 删除旧 PID 文件和 Socket
- 正常启动新守护进程

### SC-DM-004：健康检查（ping）

**Given**: 守护进程正在运行
**When**: 发送请求 `{"action": "ping"}`
**Then**:
- 返回：`{"status": "ok", "latency_ms": <N>}`

### SC-DM-005：图查询请求

**Given**:
- 守护进程正在运行
- 图数据库包含数据
**When**: 发送请求：
```json
{
  "action": "query",
  "payload": {
    "sql": "SELECT * FROM nodes LIMIT 5"
  }
}
```
**Then**:
- 返回查询结果和延迟：
  ```json
  {
    "status": "ok",
    "data": [...],
    "latency_ms": 15
  }
  ```

### SC-DM-006：队列满响应

**Given**:
- 守护进程正在运行
- 当前队列已有 10 个待处理请求
**When**: 发送第 11 个请求
**Then**:
- 返回：`{"status": "busy", "error_message": "Request queue full"}`
- 不阻塞，立即响应

### SC-DM-007：优雅停止

**Given**: 守护进程正在运行，正在处理 1 个请求
**When**: 执行 `daemon.sh stop`
**Then**:
- 发送 SIGTERM 信号
- 等待当前请求完成
- 清理 PID 文件和 Socket 文件
- 输出：`Daemon stopped gracefully`

### SC-DM-008：崩溃自动重启

**Given**:
- 守护进程通过 wrapper 启动
- 已重启 0 次
**When**: 守护进程崩溃（exit code != 0）
**Then**:
- 等待 2 秒后自动重启
- 输出：`Daemon crashed, restarting (1/3)...`
- 重启成功后继续服务

### SC-DM-009：超过重启上限

**Given**: 守护进程已重启 3 次仍然崩溃
**When**: 第 4 次崩溃
**Then**:
- 不再重启
- 输出：`Daemon failed after 3 restart attempts`
- 进入 FAILED 状态
- 需要手动干预

### SC-DM-010：状态检查

**Given**: 守护进程正在运行（PID 12345）
**When**: 执行 `daemon.sh status`
**Then**:
- 输出 JSON 格式状态：
  ```json
  {
    "running": true,
    "pid": 12345,
    "uptime_seconds": 3600,
    "queue_size": 2,
    "last_heartbeat": "2026-01-15T10:30:00Z"
  }
  ```

### SC-DM-011：未运行时状态检查

**Given**: 守护进程未运行
**When**: 执行 `daemon.sh status`
**Then**:
- 输出：`{"running": false}`
- 退出码 0

### SC-DM-012：P95 延迟验证

**Given**: 守护进程正在运行（热启动）
**When**: 连续发送 100 次 ping 请求
**Then**:
- 记录所有延迟
- 排序后第 95 位延迟 <= 600ms（500ms + 20% 波动）
- 输出：`P95 Latency: <N>ms (PASS/FAIL)`

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-DM-001 | SC-DM-001 | AC-003 |
| REQ-DM-002 | SC-DM-002, SC-DM-003 | AC-003 |
| REQ-DM-003 | SC-DM-004, SC-DM-005 | AC-003 |
| REQ-DM-004 | SC-DM-006 | AC-003 |
| REQ-DM-005 | SC-DM-004, SC-DM-005, SC-DM-006 | AC-003 |
| REQ-DM-006 | SC-DM-001, SC-DM-007, SC-DM-010, SC-DM-011 | AC-003 |
| REQ-DM-007 | SC-DM-008, SC-DM-009 | AC-003 |
| REQ-DM-008 | SC-DM-010 | AC-003 |
| REQ-DM-009 | - | AC-003 |
| REQ-DM-010 | SC-DM-007 | AC-003 |
| - | SC-DM-012 | AC-003, AC-N01 |
