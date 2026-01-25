---
last_referenced_by: 20260118-0057-upgrade-code-intelligence-capabilities
last_verified: 2026-01-18
health: active
---

# 规格：daemon.sh 接口扩展

| 属性 | 值 |
|------|-----|
| Spec-ID | SPEC-DAEMON-001 |
| Change-ID | 20260118-0057-upgrade-code-intelligence-capabilities |
| 版本 | 1.0.0 |
| 状态 | Active |
| 作者 | Spec Owner |
| 创建日期 | 2026-01-18 |

---

## 1. Requirements（需求规格）

### REQ-DM-001: start 后自动 warmup

**描述**：`daemon.sh start` 命令执行成功后，必须自动触发预热（warmup）流程。

**行为规格**：
1. `start` 命令启动 daemon 进程后，**异步**触发 warmup
2. warmup 不阻塞 start 命令返回
3. warmup 在后台执行，超时 30s
4. warmup 失败或超时不影响 daemon 正常运行

**约束**：
- 启动时间 < 2s（不等待 warmup 完成）
- warmup 超时阈值：30s
- 超时后标记 `warmup_status = "timeout"`，但 daemon 继续运行

---

### REQ-DM-002: status 返回 warmup_status

**描述**：`daemon.sh status` 命令的 JSON 输出必须包含 `warmup_status` 字段。

**输出格式**：
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `warmup_status` | string | 是 | 预热状态 |
| `warmup_started_at` | string | 条件 | 预热开始时间（ISO 8601） |
| `warmup_completed_at` | string | 条件 | 预热完成时间（ISO 8601） |
| `items_cached` | integer | 条件 | 已缓存项目数 |

**warmup_status 枚举值**：
| 值 | 说明 |
|----|------|
| `disabled` | 预热被禁用（DAEMON_WARMUP_ENABLED=false） |
| `pending` | 预热尚未开始 |
| `running` | 预热正在进行中 |
| `completed` | 预热成功完成 |
| `timeout` | 预热超时（>30s） |
| `failed` | 预热失败 |

---

### REQ-DM-003: warmup 预热内容

**描述**：warmup 流程必须预热以下内容。

**预热项目**：
| 项目 | 说明 | 来源 |
|------|------|------|
| 热点文件 | 最近 30 天高频变更文件 | `hotspot.sh` |
| 热点查询 | 预设常见查询 | `DAEMON_WARMUP_QUERIES` 环境变量 |
| 图索引 | 图数据库预加载到内存 | `graph-store.sh` |

**默认热点查询**：
```
main, server, handler, config, test, auth, api, utils
```

**配置项**：
| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `DAEMON_WARMUP_ENABLED` | `true` | 是否启用预热 |
| `DAEMON_WARMUP_TIMEOUT` | `30` | 预热超时秒数 |
| `DAEMON_WARMUP_HOTSPOT_LIMIT` | `10` | 预热热点文件数量 |
| `DAEMON_WARMUP_QUERIES` | `main,server,handler` | 预热查询列表 |

---

### REQ-DM-004: status 输出完整性

**描述**：`daemon.sh status` 命令必须返回完整的 daemon 状态信息。

**输出格式**：
```json
{
  "running": true,
  "pid": 12345,
  "state": "running",
  "restarts": 0,
  "queue_size": 5,
  "warmup_status": "completed",
  "warmup_started_at": "2026-01-18T12:00:00Z",
  "warmup_completed_at": "2026-01-18T12:00:15Z",
  "items_cached": 25
}
```

---

## 2. Scenarios（场景规格）

### SC-DM-001: 启动后自动触发预热

**Given**：
- daemon 未运行
- `DAEMON_WARMUP_ENABLED=true`

**When**：
- 执行 `daemon.sh start`

**Then**：
1. daemon 进程启动
2. start 命令在 < 2s 内返回
3. 立即查询 status：`warmup_status = "running"` 或 `"pending"`
4. 等待 15s 后查询 status：`warmup_status = "completed"`

---

### SC-DM-002: 预热完成状态

**Given**：
- daemon 已启动
- warmup 已执行

**When**：
- 执行 `daemon.sh status`

**Then**：
```json
{
  "running": true,
  "pid": 12345,
  "state": "running",
  "warmup_status": "completed",
  "warmup_started_at": "2026-01-18T12:00:00Z",
  "warmup_completed_at": "2026-01-18T12:00:15Z",
  "items_cached": 25
}
```

---

### SC-DM-003: 预热超时

**Given**：
- daemon 已启动
- warmup 执行超过 30s

**When**：
- 执行 `daemon.sh status`

**Then**：
```json
{
  "running": true,
  "warmup_status": "timeout",
  "warmup_started_at": "2026-01-18T12:00:00Z"
}
```
- daemon 继续正常运行
- `warmup_completed_at` 不存在

---

### SC-DM-004: 预热被禁用

**Given**：
- `DAEMON_WARMUP_ENABLED=false`

**When**：
- 执行 `daemon.sh start`
- 执行 `daemon.sh status`

**Then**：
```json
{
  "running": true,
  "warmup_status": "disabled"
}
```
- 不执行预热流程
- 不存在 `warmup_started_at` 等字段

---

### SC-DM-005: 启动时间不受预热影响

**Given**：
- daemon 未运行
- `DAEMON_WARMUP_ENABLED=true`

**When**：
- 计时执行 `time daemon.sh start`

**Then**：
- 启动命令耗时 < 2s
- warmup 在后台异步执行

---

### SC-DM-006: daemon 停止时清理预热状态

**Given**：
- daemon 运行中
- warmup 已完成

**When**：
- 执行 `daemon.sh stop`
- 执行 `daemon.sh start`

**Then**：
- 重新触发 warmup
- `warmup_status` 重置为 `"running"` 或 `"pending"`

---

## 3. API/Schema 契约

### 3.1 命令行接口规格

#### start 命令

```
用法: daemon.sh start

描述: 启动 daemon 守护进程，自动触发预热

行为:
    1. 检查是否已运行
    2. 启动 daemon 进程
    3. 异步触发 warmup（不阻塞）
    4. 返回成功状态

环境变量:
    DAEMON_WARMUP_ENABLED       启用/禁用预热（默认: true）
    DAEMON_WARMUP_TIMEOUT       预热超时秒数（默认: 30）
    DAEMON_WARMUP_HOTSPOT_LIMIT 预热热点文件数量（默认: 10）
    DAEMON_WARMUP_QUERIES       预热查询列表（默认: main,server,handler）

退出码:
    0   成功启动
    1   启动失败
```

#### status 命令

```
用法: daemon.sh status

描述: 查询 daemon 状态，包括预热状态

输出: JSON 格式

退出码:
    0   成功（无论 daemon 是否运行）
```

### 3.2 JSON Schema 定义

#### status 输出 Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "daemon-status.schema.json",
  "title": "Daemon Status Output",
  "type": "object",
  "properties": {
    "running": { "type": "boolean" },
    "pid": { "type": ["integer", "null"] },
    "state": {
      "type": "string",
      "enum": ["running", "stopped", "failed", "starting"]
    },
    "restarts": { "type": "integer", "minimum": 0 },
    "queue_size": { "type": "integer", "minimum": 0 },
    "warmup_status": {
      "type": "string",
      "enum": ["disabled", "pending", "running", "completed", "timeout", "failed"]
    },
    "warmup_started_at": {
      "type": "string",
      "format": "date-time"
    },
    "warmup_completed_at": {
      "type": "string",
      "format": "date-time"
    },
    "items_cached": {
      "type": "integer",
      "minimum": 0
    }
  },
  "required": ["running", "state", "warmup_status"]
}
```

### 3.3 向后兼容性

| 变更类型 | 兼容性 | 说明 |
|----------|--------|------|
| `start` 自动触发 warmup | 向后兼容 | 新增行为，不影响旧用法 |
| status 输出新增 `warmup_status` | 向后兼容 | 新增字段，旧脚本可忽略 |
| status 输出新增 `warmup_started_at` | 向后兼容 | 新增字段，旧脚本可忽略 |
| status 输出新增 `warmup_completed_at` | 向后兼容 | 新增字段，旧脚本可忽略 |
| status 输出新增 `items_cached` | 向后兼容 | 新增字段，旧脚本可忽略 |

### 3.4 弃用策略

无弃用项。

---

## 4. Contract Tests

### CT-DM-001: start 后 warmup 自动触发

**类型**：behavior

**覆盖**：REQ-DM-001, SC-DM-001

**验证脚本**：
```bash
daemon.sh stop 2>/dev/null || true
daemon.sh start
sleep 2
status=$(daemon.sh status)
warmup_status=$(echo "$status" | jq -r '.warmup_status')
# warmup_status 应为 "running", "completed", 或 "pending"
test "$warmup_status" != "disabled"
```

---

### CT-DM-002: status 返回 warmup_status

**类型**：schema

**覆盖**：REQ-DM-002

**验证脚本**：
```bash
daemon.sh status | jq -e 'has("warmup_status")'
```

---

### CT-DM-003: warmup 完成后状态

**类型**：behavior

**覆盖**：REQ-DM-002, SC-DM-002

**验证脚本**：
```bash
daemon.sh stop 2>/dev/null || true
daemon.sh start
# 等待预热完成
sleep 35
status=$(daemon.sh status)
echo "$status" | jq -e '.warmup_status == "completed" or .warmup_status == "timeout"'
```

---

### CT-DM-004: warmup 超时处理

**类型**：behavior

**覆盖**：REQ-DM-001, SC-DM-003

**验证脚本**：
```bash
# 模拟慢预热
DAEMON_WARMUP_TIMEOUT=1 daemon.sh stop 2>/dev/null || true
DAEMON_WARMUP_TIMEOUT=1 daemon.sh start
sleep 5
status=$(daemon.sh status)
# daemon 应继续运行
echo "$status" | jq -e '.running == true'
```

---

### CT-DM-005: warmup 禁用

**类型**：behavior

**覆盖**：REQ-DM-002, SC-DM-004

**验证脚本**：
```bash
DAEMON_WARMUP_ENABLED=false daemon.sh stop 2>/dev/null || true
DAEMON_WARMUP_ENABLED=false daemon.sh start
status=$(DAEMON_WARMUP_ENABLED=false daemon.sh status)
echo "$status" | jq -e '.warmup_status == "disabled"'
```

---

### CT-DM-006: 启动时间不受预热影响

**类型**：behavior

**覆盖**：REQ-DM-001, SC-DM-005

**验证脚本**：
```bash
daemon.sh stop 2>/dev/null || true
start_time=$(date +%s%N)
daemon.sh start
end_time=$(date +%s%N)
elapsed_ms=$(( (end_time - start_time) / 1000000 ))
# 启动时间应 < 2000ms
test $elapsed_ms -lt 2000
```

---

### CT-DM-007: status 输出完整性

**类型**：schema

**覆盖**：REQ-DM-004

**验证脚本**：
```bash
daemon.sh status | jq -e '
  has("running") and
  has("state") and
  has("warmup_status") and
  has("restarts") and
  has("queue_size")
'
```

---

## 5. 追溯矩阵

| Contract Test ID | 类型 | 覆盖需求/场景 |
|------------------|------|---------------|
| CT-DM-001 | behavior | REQ-DM-001, SC-DM-001 |
| CT-DM-002 | schema | REQ-DM-002 |
| CT-DM-003 | behavior | REQ-DM-002, SC-DM-002 |
| CT-DM-004 | behavior | REQ-DM-001, SC-DM-003 |
| CT-DM-005 | behavior | REQ-DM-002, SC-DM-004 |
| CT-DM-006 | behavior | REQ-DM-001, SC-DM-005 |
| CT-DM-007 | schema | REQ-DM-004 |
