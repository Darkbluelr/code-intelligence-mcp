# 规格：击键级请求取消

> **Capability**: keystroke-cancel
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-17
> **Last Referenced By**: augment-final-10-percent
> **Last Verified**: 2026-01-17
> **Health**: pending

---

## Requirements（需求）

### REQ-KC-001：取消延迟目标

系统应将请求取消延迟从当前的 50ms 优化到 <10ms：

| 指标 | 当前 | 目标 |
|------|------|------|
| P50 延迟 | 25ms | <5ms |
| P95 延迟 | 50ms | <10ms |
| P99 延迟 | 80ms | <15ms |

### REQ-KC-002：信号驱动机制

系统应采用信号驱动机制替代轮询：

```bash
# 信号处理器注册
trap 'handle_cancel' SIGUSR1

# 取消令牌机制
cancel_token=$(mktemp -u)
mkfifo "$cancel_token"

# 原子检查（非阻塞读取）
read -t 0 <"$cancel_token" && exit 130
```

### REQ-KC-003：取消令牌生命周期

系统应管理取消令牌的完整生命周期：

| 阶段 | 操作 |
|------|------|
| 创建 | 请求开始时创建命名管道 |
| 传递 | 将令牌路径传递给所有子进程 |
| 触发 | 取消时向管道写入信号 |
| 清理 | 请求结束时删除管道 |

### REQ-KC-004：子进程取消传播

系统应将取消信号传播到所有子进程：

```bash
# 进程组管理
set -m  # 启用作业控制
# 子进程继承进程组
# 取消时向整个进程组发送信号
kill -SIGUSR1 -$$
```

### REQ-KC-005：取消状态码

系统应使用标准退出码表示取消：

| 退出码 | 含义 |
|--------|------|
| 0 | 正常完成 |
| 1 | 一般错误 |
| 130 | 用户取消（SIGINT 类似） |
| 137 | 被强制终止（SIGKILL） |

### REQ-KC-006：优雅降级

系统应在取消时执行清理：

```bash
# 取消处理器
handle_cancel() {
  # 1. 设置取消标志
  CANCELLED=1
  # 2. 清理临时文件
  rm -f "$TEMP_FILES"
  # 3. 关闭网络连接
  exec 3>&-
  # 4. 退出
  exit 130
}
```

### REQ-KC-007：性能监控

系统应记录取消延迟指标：

```bash
# 记录取消请求时间
echo "$(date +%s.%N) CANCEL_REQUESTED" >> "$METRICS_LOG"
# 记录实际停止时间
echo "$(date +%s.%N) CANCEL_COMPLETE" >> "$METRICS_LOG"
```

---

## Scenarios（场景）

### SC-KC-001：快速取消正在执行的查询

**Given**: 正在执行 `graph-rag.sh` 查询
**When**: 用户按下 Ctrl+C（发送 SIGUSR1）
**Then**:
- 延迟 < 10ms 内响应取消
- 返回退出码 130
- 清理所有临时文件

### SC-KC-002：取消传播到子进程

**Given**:
- 主进程正在执行
- 主进程启动了 3 个子进程（SCIP 查询、LLM 调用、缓存更新）
**When**: 主进程收到取消信号
**Then**:
- 所有子进程在 10ms 内收到取消信号
- 所有子进程正常退出
- 无孤儿进程残留

### SC-KC-003：取消时资源清理

**Given**:
- 进程创建了临时文件 `/tmp/ckb-query-*`
- 进程打开了网络连接
**When**: 收到取消信号
**Then**:
- 临时文件被删除
- 网络连接被关闭
- 无资源泄漏

### SC-KC-004：并发取消处理

**Given**: 同时有 5 个查询正在执行
**When**: 发送全局取消信号
**Then**:
- 所有查询在 10ms 内响应
- 无竞态条件
- 日志记录完整

### SC-KC-005：取消超时保护

**Given**: 子进程无响应（卡死）
**When**: 取消信号发送后 100ms 仍未退出
**Then**:
- 发送 SIGKILL 强制终止
- 记录超时警告
- 返回退出码 137

### SC-KC-006：取消期间的部分结果

**Given**: 查询已返回部分结果
**When**: 收到取消信号
**Then**:
- 返回已获取的部分结果
- 标记 `"partial": true`
- 记录取消点

---

## API 契约

### daemon_start_with_cancel

```bash
# 启动支持取消的守护进程
# 输入：命令、参数
# 输出：进程 ID + 取消令牌路径
daemon_start_with_cancel "graph-rag.sh" "query args"

# 返回
{
  "pid": 12345,
  "cancel_token": "/tmp/ckb-cancel-12345",
  "start_time": 1705500000.123
}
```

### daemon_cancel

```bash
# 取消正在执行的请求
# 输入：进程 ID 或取消令牌
# 输出：取消结果
daemon_cancel 12345

# 返回
{
  "cancelled": true,
  "latency_ms": 3.5,
  "cleanup_complete": true
}
```

### daemon_cancel_all

```bash
# 取消所有正在执行的请求
daemon_cancel_all

# 返回
{
  "cancelled_count": 3,
  "failed_count": 0,
  "total_latency_ms": 8.2
}
```

### 取消令牌文件协议

```bash
# 令牌路径格式
/tmp/ckb-cancel-<PID>

# 令牌内容（FIFO）
# 写入任意数据表示取消
echo "cancel" > "$cancel_token"

# 检查令牌（非阻塞）
if read -t 0 <"$cancel_token" 2>/dev/null; then
  # 已取消
fi
```

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-KC-001 | SC-KC-001, SC-KC-004 | AC-005 |
| REQ-KC-002 | SC-KC-001 | AC-005 |
| REQ-KC-003 | SC-KC-003 | AC-005 |
| REQ-KC-004 | SC-KC-002 | AC-005 |
| REQ-KC-005 | SC-KC-001, SC-KC-005 | AC-005 |
| REQ-KC-006 | SC-KC-003 | AC-005 |
| REQ-KC-007 | SC-KC-001, SC-KC-004 | AC-005 |

---

## 非功能需求

### 性能基准

| 场景 | 指标 | 阈值 |
|------|------|------|
| 单进程取消 | P95 延迟 | <10ms |
| 多进程取消（5个） | P95 延迟 | <15ms |
| 带清理取消 | P95 延迟 | <20ms |

### 可靠性要求

| 场景 | 要求 |
|------|------|
| 取消成功率 | ≥99.9% |
| 资源清理成功率 | 100% |
| 无孤儿进程 | 100% |

---

## 测试契约

### 单元测试

```bash
# @smoke 快速验证
test_cancel_latency_under_10ms

# @critical 关键功能
test_cancel_propagation_to_children
test_cleanup_on_cancel

# @full 完整覆盖
test_concurrent_cancel
test_cancel_timeout_protection
test_partial_results_on_cancel
```

### 性能测试

```bash
# 基准测试
benchmark_cancel_latency --iterations 1000 --percentile 95
# 期望输出：P95 < 10ms
```
