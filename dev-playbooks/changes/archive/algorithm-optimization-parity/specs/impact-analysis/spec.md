# 规格：影响分析算法 (Impact Analysis)

> **Capability ID**: ALG-003
> **模块**: impact-analyzer.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-IA-001: BFS 图遍历

**描述**: 使用广度优先搜索遍历调用图，按深度层级处理节点。

**输入**:
- `start_symbol`: 起始符号 ID
- `max_depth`: 最大遍历深度 (1-5)
- `decay_factor`: 置信度衰减系数 (0-1)
- `threshold`: 最低置信度阈值 (0-1)

**输出**:
- 受影响节点列表，包含 id、symbol、depth、confidence

---

### REQ-IA-002: 置信度衰减计算

**描述**: 每增加一层深度，置信度按衰减系数递减。

**公式**:
```
confidence(depth) = base_impact × (decay_factor ^ depth)
```

**示例（decay_factor = 0.8）**:
- 深度 0: 1.0（起始节点，不输出）
- 深度 1: 0.8
- 深度 2: 0.64
- 深度 3: 0.512
- 深度 4: 0.4096
- 深度 5: 0.328 (约)

---

### REQ-IA-003: 阈值过滤

**描述**: 当计算得出的置信度低于阈值时，停止遍历该分支。

**行为**:
- 不将低于阈值的节点加入结果
- 不继续遍历低于阈值节点的下游

---

### REQ-IA-004: 去重处理

**描述**: 同一符号只访问一次，避免重复计算和循环遍历。

---

### REQ-IA-005: 结果排序

**描述**: 输出结果按置信度降序排列。

---

## Scenarios

### SC-IA-001: 标准 5 跳遍历

- **Given**: 起始符号 S，调用链 S → A → B → C → D → E
- **And**: decay_factor=0.8, threshold=0.1, max_depth=5
- **When**: 调用 `bfs_impact_analysis()` 函数
- **Then**: 返回:
  - A: depth=1, confidence=0.8
  - B: depth=2, confidence=0.64
  - C: depth=3, confidence=0.512
  - D: depth=4, confidence=0.41 (约)
  - E: depth=5, confidence=0.328 (约)

### SC-IA-002: 阈值过滤

- **Given**: threshold=0.5
- **And**: 遍历到深度 2 时 confidence=0.64
- **When**: 继续遍历
- **Then**: 深度 3 的 confidence=0.512 > 0.5，继续
- **And**: 深度 4 的 confidence=0.4096 < 0.5，停止该分支

### SC-IA-003: 循环调用图

- **Given**: A → B → C → A（存在循环）
- **When**: 从 A 开始遍历
- **Then**: A 只访问一次，不进入无限循环

### SC-IA-004: 空调用图

- **Given**: 起始符号没有下游调用
- **When**: 调用 `bfs_impact_analysis()` 函数
- **Then**: 返回空列表 `[]`

### SC-IA-005: 深度限制

- **Given**: max_depth=3，调用链深度为 10
- **When**: 调用 `bfs_impact_analysis()` 函数
- **Then**: 只返回深度 1-3 的节点

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-IA-001 | behavior | SC-IA-001 |
| CT-IA-002 | behavior | SC-IA-002 |
| CT-IA-003 | boundary | SC-IA-003 |
| CT-IA-004 | boundary | SC-IA-004 |
| CT-IA-005 | boundary | SC-IA-005 |
