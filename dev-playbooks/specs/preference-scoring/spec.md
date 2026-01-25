---
last_referenced_by: algorithm-optimization-parity
last_verified: 2026-01-17
health: active
---

# 规格：偏好分数计算 (Preference Scoring)

> **Capability ID**: ALG-004
> **模块**: intent-learner.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-PF-001: 偏好分数公式

**描述**: 符号偏好分数基于查询频率、时间衰减和用户操作权重计算。

**公式**:
```
Preference(symbol) = Σ(action_weight × recency_weight)
```

其中:
- `action_weight` = 用户操作权重
- `recency_weight` = 1 / (1 + days_since_query)

---

### REQ-PF-002: 操作权重定义

**描述**: 不同用户操作有不同的权重值。

| 操作 | 权重 | 说明 |
|------|------|------|
| view | 1.0 | 查看但未操作 |
| edit | 2.0 | 编辑/修改 |
| ignore | 0.5 | 显式忽略 |

---

### REQ-PF-003: 时间衰减

**描述**: 越近的查询记录权重越高。

**公式**: `recency_weight = 1 / (1 + days)`

**示例**:
- 今天查询: 1 / (1 + 0) = 1.0
- 1 天前: 1 / (1 + 1) = 0.5
- 7 天前: 1 / (1 + 7) = 0.125
- 30 天前: 1 / (1 + 30) = 0.032

---

### REQ-PF-004: 查询结果排序

**描述**: 偏好查询结果按分数降序排列，支持 `--top N` 限制。

---

### REQ-PF-005: 路径前缀过滤

**描述**: 支持 `--prefix <path>` 参数过滤特定目录的偏好。

---

## Scenarios

### SC-PF-001: 单次查询分数

- **Given**: 符号 S 被 view 查询，距今 0 天
- **When**: 计算偏好分数
- **Then**: 分数 = 1.0 × 1.0 = 1.0

### SC-PF-002: 多次查询累加

- **Given**: 符号 S 被查询 3 次:
  - 今天 view
  - 1 天前 edit
  - 7 天前 view
- **When**: 计算偏好分数
- **Then**: 分数 = (1.0 × 1.0) + (2.0 × 0.5) + (1.0 × 0.125) = 2.125

### SC-PF-003: edit 操作权重

- **Given**: 符号 S 被 edit，距今 0 天
- **When**: 计算偏好分数
- **Then**: 分数 = 2.0 × 1.0 = 2.0

### SC-PF-004: ignore 操作权重

- **Given**: 符号 S 被 ignore，距今 0 天
- **When**: 计算偏好分数
- **Then**: 分数 = 0.5 × 1.0 = 0.5

### SC-PF-005: 路径前缀过滤

- **Given**: 偏好记录:
  - `src/auth.ts::login`: score=2.0
  - `tests/auth.test.ts::testLogin`: score=1.5
- **And**: 参数 `--prefix src/`
- **When**: 查询偏好
- **Then**: 只返回 `src/auth.ts::login`

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-PF-001 | unit | SC-PF-001 |
| CT-PF-002 | behavior | SC-PF-002 |
| CT-PF-003 | unit | SC-PF-003 |
| CT-PF-004 | unit | SC-PF-004 |
| CT-PF-005 | behavior | SC-PF-005 |
