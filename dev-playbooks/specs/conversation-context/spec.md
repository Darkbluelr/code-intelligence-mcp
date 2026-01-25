---
last_referenced_by: augment-parity-final-gaps
last_verified: 2026-01-16
health: active
---


# Spec: 对话历史信号累积（conversation-context）

> **Change ID**: `augment-parity-final-gaps`
> **Capability**: conversation-context
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-16

---

## 概述

本规格定义对话历史信号累积功能。系统应能够：
1. 记录多轮对话上下文
2. 累积焦点符号，提升搜索连续性
3. 在搜索结果排序中加入对话连续性加权

---

## Requirements（需求）

### REQ-CC-001：对话上下文存储

系统应存储对话上下文到持久化文件：

- 存储位置：`.devbooks/conversation-context.json`
- 格式：JSON
- 更新时机：每次查询完成后

### REQ-CC-002：对话上下文结构

对话上下文应包含以下字段：

```json
{
  "session_id": "session-<uuid>",
  "started_at": "2026-01-16T10:00:00Z",
  "context_window": [
    {
      "turn": 1,
      "timestamp": "2026-01-16T10:01:00Z",
      "query": "find auth module",
      "query_type": "search|call_chain|bug_locate|...",
      "focus_symbols": ["src/auth.ts"],
      "results_count": 5
    }
  ],
  "accumulated_focus": ["src/auth.ts", "src/auth.ts::login"]
}
```

### REQ-CC-003：上下文窗口大小

系统应限制上下文窗口大小：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `max_turns` | 10 | 最大保留轮数 |
| `max_focus_symbols` | 50 | 最大焦点符号数 |

**约束**：
- 超过 `max_turns` 时 FIFO 淘汰最旧记录
- 超过 `max_focus_symbols` 时淘汰最少访问的符号

### REQ-CC-004：焦点符号累积

系统应累积对话过程中涉及的焦点符号：

**累积来源**：
- 搜索结果中用户选择的符号
- 调用链查询的根符号
- Bug 定位的候选符号

**权重计算**：
- 最近访问的符号权重更高
- 多次访问的符号权重累加

### REQ-CC-005：对话连续性加权

系统应在搜索结果排序中加入对话连续性加权：

**加权规则**：
| 条件 | 加权因子 |
|------|----------|
| 符号在 `accumulated_focus` 中 | +0.2 |
| 符号在最近 3 轮 `focus_symbols` 中 | +0.3 |
| 符号与最近查询同文件 | +0.1 |

**约束**：
- 加权因子可配置
- 加权不应超过原始分数的 50%

### REQ-CC-006：会话管理

系统应支持会话管理：

| 操作 | 命令 | 说明 |
|------|------|------|
| 新建会话 | `intent-learner.sh session new` | 创建新会话，清空上下文 |
| 继续会话 | `intent-learner.sh session resume <id>` | 恢复指定会话 |
| 列出会话 | `intent-learner.sh session list` | 列出最近会话 |
| 清除会话 | `intent-learner.sh session clear` | 清除当前会话上下文 |

---

## Scenarios（场景）

### SC-CC-001：写入对话上下文

**Given**:
- 当前无对话上下文（首次查询）
**When**: 执行查询 `find auth module`，返回 5 个结果
**Then**:
- 创建 `.devbooks/conversation-context.json`
- 写入第一轮对话记录
- `turn` = 1
- `focus_symbols` 包含结果中的符号

### SC-CC-002：读取对话上下文

**Given**:
- 已有 5 轮对话记录
**When**: 读取对话上下文
**Then**:
- 返回完整的 5 轮记录
- 返回 `accumulated_focus` 列表
- 返回 `session_id`

### SC-CC-003：FIFO 淘汰

**Given**:
- 已有 10 轮对话记录（达到上限）
**When**: 写入第 11 轮对话
**Then**:
- 删除第 1 轮（最旧）记录
- 保留第 2-11 轮记录
- 总轮数仍为 10

### SC-CC-004：对话连续性加权

**Given**:
- `accumulated_focus` 包含 `src/auth.ts::login`
- 搜索结果包含 `src/auth.ts::login`（原始分数 0.8）和 `src/utils.ts::helper`（原始分数 0.85）
**When**: 应用对话连续性加权
**Then**:
- `src/auth.ts::login` 加权后分数 = 0.8 + 0.2 = 1.0
- `src/utils.ts::helper` 分数 = 0.85
- `src/auth.ts::login` 排名上升

### SC-CC-005：新建会话

**Given**:
- 存在当前会话
**When**: 执行 `intent-learner.sh session new`
**Then**:
- 创建新 `session_id`
- 清空 `context_window`
- 清空 `accumulated_focus`
- 返回新会话 ID

### SC-CC-006：恢复会话

**Given**:
- 存在历史会话 `session-abc123`
**When**: 执行 `intent-learner.sh session resume session-abc123`
**Then**:
- 加载历史会话的上下文
- 继续累积焦点符号
- 返回会话信息

### SC-CC-007：空上下文读取

**Given**:
- 无对话上下文文件
**When**: 读取对话上下文
**Then**:
- 返回空上下文结构
- `context_window`: []
- `accumulated_focus`: []
- 不报错

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-CC-001 | SC-CC-001 | AC-G04 |
| REQ-CC-002 | SC-CC-001, SC-CC-002 | AC-G04 |
| REQ-CC-003 | SC-CC-003 | AC-G04 |
| REQ-CC-004 | SC-CC-001, SC-CC-002 | AC-G04 |
| REQ-CC-005 | SC-CC-004 | AC-G04 |
| REQ-CC-006 | SC-CC-005, SC-CC-006, SC-CC-007 | AC-G04 |

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-CC-001 | behavior | REQ-CC-001, SC-CC-001 | 写入对话上下文 |
| CT-CC-002 | behavior | REQ-CC-002, SC-CC-002 | 读取对话上下文 |
| CT-CC-003 | behavior | REQ-CC-003, SC-CC-003 | FIFO 淘汰 |
| CT-CC-004 | behavior | REQ-CC-005, SC-CC-004 | 对话连续性加权 |
| CT-CC-005 | schema | REQ-CC-002 | 上下文 JSON Schema |

---

## 命令行接口（CLI）

```bash
intent-learner.sh context <command> [options]
```

| 命令 | 说明 |
|------|------|
| `context save --query <q> --symbols <s1,s2>` | 保存对话上下文 |
| `context load` | 加载当前对话上下文 |
| `context apply-weight --results <json>` | 对结果应用对话连续性加权 |

| 命令 | 说明 |
|------|------|
| `session new` | 创建新会话 |
| `session resume <id>` | 恢复会话 |
| `session list` | 列出会话 |
| `session clear` | 清除会话 |
