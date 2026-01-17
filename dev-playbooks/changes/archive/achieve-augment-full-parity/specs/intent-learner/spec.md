# 规格：M6 意图偏好学习

> **模块 ID**: `intent-learner`
> **Change ID**: `achieve-augment-full-parity`
> **Date**: 2026-01-16
> **Status**: Draft

---

## Requirements（需求）

### REQ-IL-001: 查询历史记录

系统必须记录用户的代码查询历史。

**约束**：
- 存储位置：`.devbooks/intent-history.json`
- 记录内容：query、matched_symbols、user_action、timestamp、session_id
- 隐私模式：纯本地存储，不传输

### REQ-IL-002: 偏好分数计算

系统必须基于历史记录计算符号偏好分数。

**约束**：
- 公式：`Preference(symbol) = frequency × recency_weight × click_weight`
- frequency：查询次数
- recency_weight：`1 / (1 + days_since_last_query)`
- click_weight：用户操作权重（默认 1.0）

### REQ-IL-003: 自动清理机制

系统必须自动清理过期的历史记录。

**约束**：
- 保留期限：90 天
- 最大条目数：10000 条
- 清理触发：每次 intent-learner.sh 启动时

### REQ-IL-004: 偏好查询接口

系统必须提供偏好查询接口，供其他模块使用。

**约束**：
- 返回 Top N 偏好符号
- 支持按前缀过滤

---

## Scenarios（场景）

### SC-IL-001: 记录查询历史

**Given**：
- 用户执行代码搜索
- 匹配到符号 `src/server.ts::handleToolCall`

**When**：
- 调用 `intent-learner.sh record "handleToolCall" "src/server.ts::handleToolCall" --action view`

**Then**：
- 系统创建新的历史条目
- 条目包含 id、timestamp、query、matched_symbols、user_action
- 写入 intent-history.json

**验证**：`tests/intent-learner.bats::test_record_history`

### SC-IL-002: 偏好分数正确计算

**Given**：
- 符号 A 被查询 5 次，最后查询 1 天前
- 符号 B 被查询 3 次，最后查询 10 天前

**When**：
- 计算偏好分数

**Then**：
- A 的 recency_weight = 1 / (1 + 1) = 0.5
- A 的 score = 5 × 0.5 × 1.0 = 2.5
- B 的 recency_weight = 1 / (1 + 10) ≈ 0.09
- B 的 score = 3 × 0.09 × 1.0 ≈ 0.27
- A 的偏好高于 B

**验证**：`tests/intent-learner.bats::test_preference_calculation`

### SC-IL-003: 90 天自动清理

**Given**：
- intent-history.json 包含 100 天前的记录

**When**：
- 调用 `intent-learner.sh cleanup`

**Then**：
- 超过 90 天的记录被删除
- 90 天内的记录保留
- 日志显示清理数量

**验证**：`tests/intent-learner.bats::test_90_day_cleanup`

### SC-IL-004: 查询 Top N 偏好

**Given**：
- 历史中有多个符号的查询记录

**When**：
- 调用 `intent-learner.sh get-preferences --top 5`

**Then**：
- 返回偏好分数最高的 5 个符号
- 按分数降序排列
- 包含 symbol、score 字段

**验证**：`tests/intent-learner.bats::test_top_n_preferences`

### SC-IL-005: 前缀过滤偏好

**Given**：
- 历史包含 `src/` 和 `scripts/` 下的符号

**When**：
- 调用 `intent-learner.sh get-preferences --prefix "scripts/"`

**Then**：
- 仅返回 `scripts/` 前缀的符号偏好
- 其他前缀的符号不包含在结果中

**验证**：`tests/intent-learner.bats::test_prefix_filter`

### SC-IL-006: 最大条目数限制

**Given**：
- 历史条目数接近 10000

**When**：
- 继续记录新查询

**Then**：
- 最旧的条目被淘汰
- 总条目数不超过 10000
- 新条目正常记录

**验证**：`tests/intent-learner.bats::test_max_entries_limit`

### SC-IL-007: 空历史处理

**Given**：
- intent-history.json 不存在或为空

**When**：
- 调用 `intent-learner.sh get-preferences`

**Then**：
- 返回空数组或提示"无历史记录"
- 不报错

**验证**：`tests/intent-learner.bats::test_empty_history`

### SC-IL-008: 用户操作权重

**Given**：
- 同一符号有不同操作记录
- view 权重 = 1.0，edit 权重 = 2.0，ignore 权重 = 0.5

**When**：
- 计算偏好分数

**Then**：
- 不同操作的记录使用不同权重
- 最终 click_weight 为加权平均

**验证**：`tests/intent-learner.bats::test_action_weight`

### SC-IL-009: 历史文件损坏恢复

**Given**：
- intent-history.json 文件格式错误（非有效 JSON）

**When**：
- 调用 intent-learner.sh 任意命令

**Then**：
- 系统检测到损坏
- 备份损坏文件（.bak）
- 创建新的空历史文件
- 输出警告日志

**验证**：`tests/intent-learner.bats::test_corrupt_recovery`

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios |
|-------------|-----------|
| REQ-IL-001 | SC-IL-001, SC-IL-009 |
| REQ-IL-002 | SC-IL-002, SC-IL-008 |
| REQ-IL-003 | SC-IL-003, SC-IL-006 |
| REQ-IL-004 | SC-IL-004, SC-IL-005, SC-IL-007 |

| Scenario | Test ID |
|----------|---------|
| SC-IL-001 | `tests/intent-learner.bats::test_record_history` |
| SC-IL-002 | `tests/intent-learner.bats::test_preference_calculation` |
| SC-IL-003 | `tests/intent-learner.bats::test_90_day_cleanup` |
| SC-IL-004 | `tests/intent-learner.bats::test_top_n_preferences` |
| SC-IL-005 | `tests/intent-learner.bats::test_prefix_filter` |
| SC-IL-006 | `tests/intent-learner.bats::test_max_entries_limit` |
| SC-IL-007 | `tests/intent-learner.bats::test_empty_history` |
| SC-IL-008 | `tests/intent-learner.bats::test_action_weight` |
| SC-IL-009 | `tests/intent-learner.bats::test_corrupt_recovery` |

---

## 数据格式

### intent-history.json Schema

```json
{
  "version": "1.0",
  "entries": [
    {
      "id": "uuid-xxx",
      "timestamp": "2026-01-16T10:30:00Z",
      "query": "handleToolCall",
      "matched_symbols": ["src/server.ts::handleToolCall"],
      "user_action": "view",
      "session_id": "session-xxx"
    }
  ],
  "preferences": {
    "src/server.ts::handleToolCall": {
      "frequency": 5,
      "last_query": "2026-01-16T10:30:00Z",
      "score": 0.85
    }
  }
}
```

### 用户操作权重表

| 操作 | 权重 | 说明 |
|------|------|------|
| view | 1.0 | 查看代码 |
| edit | 2.0 | 编辑代码（表示高兴趣） |
| ignore | 0.5 | 忽略结果（表示低兴趣） |
| default | 1.0 | 未指定操作时 |
