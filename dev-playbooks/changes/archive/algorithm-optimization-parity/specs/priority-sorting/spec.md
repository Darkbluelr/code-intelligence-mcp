# 规格：优先级排序算法 (Priority Sorting)

> **Capability ID**: ALG-001
> **模块**: graph-rag.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-PS-001: 多因子优先级计算

**描述**: 候选代码片段的优先级应基于多个因子加权计算，而非单一相关性分数。

**输入**:
- `relevance_score`: 语义相关性分数 (0-1)
- `hotspot`: 热点分数 (0-1)
- `distance`: 图距离（跳数，≥1）

**输出**:
- `priority`: 综合优先级分数 (0-1)

**公式**:
```
Priority = relevance × W_r + hotspot × W_h + (1/distance) × W_d
```

其中默认权重: W_r=0.4, W_h=0.3, W_d=0.3

---

### REQ-PS-002: 权重可配置

**描述**: 优先级计算的权重应从配置文件读取，支持运行时调整。

**配置路径**: `config/features.yaml`
**配置键**: `smart_pruning.priority_weights.{relevance,hotspot,distance}`

---

### REQ-PS-003: 边界处理

**描述**: 算法应正确处理以下边界情况：
- `distance = 0` → 视为 1（避免除零）
- 缺失字段 → 使用默认值 0
- 负值输入 → 视为 0

---

## Scenarios

### SC-PS-001: 标准优先级计算

- **Given**: 候选 `{relevance_score: 0.8, hotspot: 0.6, distance: 2}`
- **When**: 调用 `calculate_priority()` 函数
- **Then**: 返回 `0.8×0.4 + 0.6×0.3 + 0.5×0.3 = 0.32 + 0.18 + 0.15 = 0.65`

### SC-PS-002: 距离为零处理

- **Given**: 候选 `{relevance_score: 0.5, hotspot: 0.5, distance: 0}`
- **When**: 调用 `calculate_priority()` 函数
- **Then**: distance 被视为 1，返回 `0.5×0.4 + 0.5×0.3 + 1×0.3 = 0.65`

### SC-PS-003: 缺失字段处理

- **Given**: 候选 `{relevance_score: 0.9}`（缺少 hotspot 和 distance）
- **When**: 调用 `calculate_priority()` 函数
- **Then**: 缺失字段使用默认值，返回 `0.9×0.4 + 0×0.3 + 1×0.3 = 0.66`

### SC-PS-004: 自定义权重

- **Given**: 配置文件设置 `relevance: 0.6, hotspot: 0.2, distance: 0.2`
- **And**: 候选 `{relevance_score: 0.8, hotspot: 0.4, distance: 1}`
- **When**: 调用 `calculate_priority()` 函数
- **Then**: 使用自定义权重，返回 `0.8×0.6 + 0.4×0.2 + 1×0.2 = 0.76`

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-PS-001 | behavior | SC-PS-001 |
| CT-PS-002 | boundary | SC-PS-002 |
| CT-PS-003 | boundary | SC-PS-003 |
| CT-PS-004 | config | SC-PS-004 |
