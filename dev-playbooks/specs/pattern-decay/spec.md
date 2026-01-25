---
last_referenced_by: algorithm-optimization-parity
last_verified: 2026-01-17
health: active
---

# 规格：模式频率与时间衰减 (Pattern Decay)

> **Capability ID**: ALG-007
> **模块**: pattern-learner.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-PD-001: 模式分数计算

**描述**: 学习到的代码模式分数基于出现频率和时间衰减计算。

**公式**:
```
Score = frequency × recency_weight
recency_weight = 1 / (1 + days_since_last_occurrence / 30)
```

**说明**: 以 30 天为半衰期计算时间衰减。

---

### REQ-PD-002: 最小频率阈值

**描述**: 只有出现次数 ≥ 最小阈值的模式才会被记录。

**配置键**: `pattern_discovery.min_frequency`
**默认值**: 3

---

### REQ-PD-003: 频率统计

**描述**: 准确统计模式在代码库中的出现次数。

**统计范围**:
- 用户代码（排除 node_modules、vendor 等）
- 按符号级别去重

---

### REQ-PD-004: 时间戳记录

**描述**: 记录模式每次出现的时间戳，用于时间衰减计算。

---

## Scenarios

### SC-PD-001: 新模式首次出现

- **Given**: 模式 P 首次出现，frequency = 1
- **When**: 判断是否记录
- **Then**: 不记录（低于 min_frequency=3）

### SC-PD-002: 达到最小频率

- **Given**: 模式 P 第 3 次出现
- **And**: 距今 0 天
- **When**: 计算模式分数
- **Then**: Score = 3 × 1.0 = 3.0，记录模式

### SC-PD-003: 时间衰减

- **Given**: 模式 P 出现 5 次
- **And**: 最后一次出现距今 30 天
- **When**: 计算模式分数
- **Then**: recency_weight = 1 / (1 + 30/30) = 0.5
- **Then**: Score = 5 × 0.5 = 2.5

### SC-PD-004: 长期未出现

- **Given**: 模式 P 出现 10 次
- **And**: 最后一次出现距今 90 天
- **When**: 计算模式分数
- **Then**: recency_weight = 1 / (1 + 90/30) = 0.25
- **Then**: Score = 10 × 0.25 = 2.5

### SC-PD-005: 高频近期模式

- **Given**: 模式 P 出现 20 次
- **And**: 最后一次出现距今 1 天
- **When**: 计算模式分数
- **Then**: recency_weight = 1 / (1 + 1/30) ≈ 0.97
- **Then**: Score = 20 × 0.97 ≈ 19.4

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-PD-001 | boundary | SC-PD-001 |
| CT-PD-002 | behavior | SC-PD-002 |
| CT-PD-003 | behavior | SC-PD-003 |
| CT-PD-004 | behavior | SC-PD-004 |
| CT-PD-005 | behavior | SC-PD-005 |
