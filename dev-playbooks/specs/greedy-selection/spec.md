---
last_referenced_by: algorithm-optimization-parity
last_verified: 2026-01-17
health: active
---

# 规格：贪婪选择策略 (Greedy Selection)

> **Capability ID**: ALG-002
> **模块**: graph-rag.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-GS-001: Token 预算贪婪选择

**描述**: 在给定 Token 预算下，按优先级降序贪婪选择候选片段，直到预算耗尽。

**输入**:
- `candidates`: 候选列表（已计算 priority 和 tokens）
- `budget`: Token 预算（正整数）

**输出**:
- 选中的候选子集（保持优先级排序）

**算法**:
1. 按 priority 降序排序
2. 依次选择，累计 tokens ≤ budget
3. 单片段超预算则跳过（不截断）
4. 累计超预算则停止

---

### REQ-GS-002: Token 估算

**描述**: 使用字符数估算 Token 数，采用保守策略。

**公式**:
```
tokens = ceil(char_count / 4 × 1.1)
```

- 基础估算：字符数 / 4
- 保守裕量：+10%

---

### REQ-GS-003: 零预算处理

**描述**: 当预算为 0 时，返回空结果并记录警告。

---

### REQ-GS-004: 负预算处理

**描述**: 当预算为负数时，视为 0 处理。

---

## Scenarios

### SC-GS-001: 正常贪婪选择

- **Given**: 候选列表:
  - A: priority=0.9, tokens=100
  - B: priority=0.7, tokens=200
  - C: priority=0.5, tokens=150
- **And**: Token 预算 = 250
- **When**: 调用 `trim_by_budget()` 函数
- **Then**: 选择 [A, C]（总 250 tokens），跳过 B（加上 B 会超预算）

### SC-GS-002: 单片段超预算

- **Given**: 候选列表:
  - A: priority=0.9, tokens=1000
  - B: priority=0.7, tokens=100
- **And**: Token 预算 = 500
- **When**: 调用 `trim_by_budget()` 函数
- **Then**: 选择 [B]，跳过 A（单片段超预算）

### SC-GS-003: 所有片段超预算

- **Given**: 所有候选 tokens > budget
- **When**: 调用 `trim_by_budget()` 函数
- **Then**: 返回空列表 `[]`，记录警告日志

### SC-GS-004: 零预算

- **Given**: Token 预算 = 0
- **When**: 调用 `trim_by_budget()` 函数
- **Then**: 返回空列表 `[]`，记录警告日志

### SC-GS-005: Token 估算准确性

- **Given**: 文本内容 400 字符
- **When**: 调用 `estimate_tokens()` 函数
- **Then**: 返回 `ceil(400/4 × 1.1) = ceil(110) = 110`

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-GS-001 | behavior | SC-GS-001 |
| CT-GS-002 | boundary | SC-GS-002 |
| CT-GS-003 | boundary | SC-GS-003 |
| CT-GS-004 | boundary | SC-GS-004 |
| CT-GS-005 | unit | SC-GS-005 |
