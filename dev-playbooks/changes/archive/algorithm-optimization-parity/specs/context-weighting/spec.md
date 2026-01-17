# 规格：对话连续性加权 (Context Weighting)

> **Capability ID**: ALG-005
> **模块**: intent-learner.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-CW-001: 累积焦点加权

**描述**: 符号在 `accumulated_focus` 列表中时，分数增加。

**加权值**: +0.2

---

### REQ-CW-002: 近期焦点加权

**描述**: 符号在最近 3 轮对话的 `focus_symbols` 中时，分数增加。

**加权值**: +0.3

---

### REQ-CW-003: 同文件加权

**描述**: 符号与最近查询的符号在同一文件时，分数增加。

**加权值**: +0.1

---

### REQ-CW-004: 加权上限

**描述**: 总加权不超过原始分数的 50%。

**公式**:
```
total_boost = min(acc_boost + recent_boost + file_boost, original_score × 0.5)
```

---

### REQ-CW-005: 加权后重排序

**描述**: 应用加权后，结果按新分数重新排序。

---

## Scenarios

### SC-CW-001: 累积焦点加权

- **Given**: 符号 S 在 `accumulated_focus` 中
- **And**: 原始分数 = 0.8
- **When**: 应用连续性加权
- **Then**: 加权后分数 = 0.8 + 0.2 = 1.0

### SC-CW-002: 近期焦点加权

- **Given**: 符号 S 在最近 3 轮 `focus_symbols` 中
- **And**: 原始分数 = 0.6
- **When**: 应用连续性加权
- **Then**: 加权后分数 = 0.6 + 0.3 = 0.9

### SC-CW-003: 同文件加权

- **Given**: 符号 S 与最近查询符号同文件
- **And**: 原始分数 = 0.5
- **When**: 应用连续性加权
- **Then**: 加权后分数 = 0.5 + 0.1 = 0.6

### SC-CW-004: 组合加权

- **Given**: 符号 S 满足所有条件（累积焦点 + 近期焦点 + 同文件）
- **And**: 原始分数 = 0.8
- **When**: 应用连续性加权
- **Then**: 总加权 = 0.2 + 0.3 + 0.1 = 0.6
- **But**: 上限 = 0.8 × 0.5 = 0.4
- **Then**: 加权后分数 = 0.8 + 0.4 = 1.2

### SC-CW-005: 低分数高加权上限

- **Given**: 原始分数 = 0.2
- **And**: 满足累积焦点条件（+0.2）
- **When**: 应用连续性加权
- **Then**: 上限 = 0.2 × 0.5 = 0.1
- **Then**: 加权后分数 = 0.2 + 0.1 = 0.3（而非 0.4）

### SC-CW-006: 无上下文时不加权

- **Given**: `context_window` 为空
- **When**: 应用连续性加权
- **Then**: 返回原始结果，分数不变

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-CW-001 | behavior | SC-CW-001 |
| CT-CW-002 | behavior | SC-CW-002 |
| CT-CW-003 | behavior | SC-CW-003 |
| CT-CW-004 | behavior | SC-CW-004 |
| CT-CW-005 | boundary | SC-CW-005 |
| CT-CW-006 | boundary | SC-CW-006 |
