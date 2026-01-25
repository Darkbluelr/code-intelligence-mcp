---
last_referenced_by: algorithm-optimization-parity
last_verified: 2026-01-17
health: active
---

# 规格：复杂度加权热点 (Hotspot Weighting)

> **Capability ID**: ALG-008
> **模块**: hotspot-analyzer.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-HW-001: 热点分数公式（复杂度加权）

**描述**: 热点分数基于修改次数和圈复杂度计算。

**公式**:
```
Score = churn_count × (1 + log10(complexity))
```

**说明**:
- `churn_count`: 文件修改次数
- `complexity`: 圈复杂度（最小为 1）
- 使用 log10 压缩复杂度的影响

---

### REQ-HW-002: 热点分数公式（无复杂度）

**描述**: 当复杂度加权功能禁用时，仅使用修改次数。

**公式**:
```
Score = churn_count
```

---

### REQ-HW-003: 功能开关

**描述**: 复杂度加权可通过配置开关控制。

**配置键**: `features.complexity_weighted_hotspot`
**默认值**: true

---

### REQ-HW-004: 复杂度获取

**描述**: 从静态分析工具获取圈复杂度，无法获取时默认为 1。

**降级行为**: 复杂度获取失败时，退化为无复杂度公式。

---

### REQ-HW-005: 热点数量限制

**描述**: 返回的热点文件数量受配置限制。

**配置键**: `features.hotspot_limit`
**默认值**: 5

---

## Scenarios

### SC-HW-001: 标准复杂度加权

- **Given**: 文件 F，churn_count=10，complexity=100
- **And**: 复杂度加权启用
- **When**: 计算热点分数
- **Then**: Score = 10 × (1 + log10(100)) = 10 × 3 = 30

### SC-HW-002: 低复杂度

- **Given**: 文件 F，churn_count=10，complexity=1
- **And**: 复杂度加权启用
- **When**: 计算热点分数
- **Then**: Score = 10 × (1 + log10(1)) = 10 × 1 = 10

### SC-HW-003: 复杂度加权禁用

- **Given**: 文件 F，churn_count=10，complexity=100
- **And**: `complexity_weighted_hotspot: false`
- **When**: 计算热点分数
- **Then**: Score = 10（不使用复杂度）

### SC-HW-004: 复杂度获取失败

- **Given**: 文件 F，churn_count=10
- **And**: 无法获取复杂度
- **When**: 计算热点分数
- **Then**: 默认 complexity=1，Score = 10

### SC-HW-005: 热点数量限制

- **Given**: 15 个热点文件
- **And**: `hotspot_limit: 5`
- **When**: 获取热点列表
- **Then**: 只返回分数最高的 5 个

### SC-HW-006: 高修改低复杂度 vs 低修改高复杂度

- **Given**:
  - 文件 A: churn=20, complexity=2
  - 文件 B: churn=5, complexity=1000
- **When**: 计算并比较分数
- **Then**:
  - A: 20 × (1 + 0.3) = 26
  - B: 5 × (1 + 3) = 20
  - A 排名更高（修改次数权重更大）

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-HW-001 | behavior | SC-HW-001 |
| CT-HW-002 | behavior | SC-HW-002 |
| CT-HW-003 | config | SC-HW-003 |
| CT-HW-004 | fallback | SC-HW-004 |
| CT-HW-005 | boundary | SC-HW-005 |
| CT-HW-006 | behavior | SC-HW-006 |
