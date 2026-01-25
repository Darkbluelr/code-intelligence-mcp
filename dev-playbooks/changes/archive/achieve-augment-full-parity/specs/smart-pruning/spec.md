# 规格：M4 子图智能裁剪

> **模块 ID**: `smart-pruning`
> **Change ID**: `achieve-augment-full-parity`
> **Date**: 2026-01-16
> **Status**: Draft

---

## Requirements（需求）

### REQ-SP-001: Token 预算控制

系统必须支持通过 Token 预算控制输出子图大小。

**约束**：
- 默认预算：8000 tokens
- 预算参数：`--budget <tokens>`
- 输出 Token 数必须 ≤ 预算值

### REQ-SP-002: 优先级评分算法

系统必须实现优先级评分算法，决定保留哪些代码片段。

**约束**：
- 公式：`Priority = relevance × 0.4 + hotspot × 0.3 + (1/distance) × 0.3`
- relevance：与查询的语义相关度（0-1）
- hotspot：热点分数（0-1）
- distance：到查询根节点的图距离（1-N）

### REQ-SP-003: 贪婪选择策略

系统必须使用贪婪选择策略在预算内最大化信息量。

**约束**：
- 按优先级降序排列候选片段
- 贪婪选择直到预算耗尽
- 不分割单个代码片段

### REQ-SP-004: Token 估算方法

系统必须提供 Token 估算方法。

**约束**：
- 基础方法：字符数 / 4（适用于英文代码）
- 可配置更精确的估算器

---

## Scenarios（场景）

### SC-SP-001: 基本预算裁剪

**Given**：
- graph-rag 搜索返回 20 个候选片段
- 总 Token 数超过预算

**When**：
- 调用 `graph-rag.sh search "handleToolCall" --budget 4000`

**Then**：
- 系统计算每个片段的 Token 数
- 计算优先级分数
- 按优先级贪婪选择
- 输出 Token 数 ≤ 4000

**验证**：`tests/graph-rag.bats::test_budget_pruning`

### SC-SP-002: 优先级正确计算

**Given**：
- 候选片段 A：relevance=0.9, hotspot=0.8, distance=1
- 候选片段 B：relevance=0.7, hotspot=0.5, distance=2

**When**：
- 计算优先级分数

**Then**：
- A 的优先级 = 0.9×0.4 + 0.8×0.3 + 1.0×0.3 = 0.36 + 0.24 + 0.30 = 0.90
- B 的优先级 = 0.7×0.4 + 0.5×0.3 + 0.5×0.3 = 0.28 + 0.15 + 0.15 = 0.58
- A 优先于 B

**验证**：`tests/graph-rag.bats::test_priority_calculation`

### SC-SP-003: 预算边界精确控制

**Given**：
- 预算 = 1000 tokens
- 候选片段 Token 数：[400, 300, 350, 200]
- 按优先级排序后

**When**：
- 执行贪婪选择

**Then**：
- 选择前两个片段（400 + 300 = 700 ≤ 1000）
- 跳过第三个片段（700 + 350 = 1050 > 1000）
- 选择第四个片段（700 + 200 = 900 ≤ 1000）
- 最终输出 900 tokens

**验证**：`tests/graph-rag.bats::test_budget_boundary`

### SC-SP-004: 默认预算行为

**Given**：
- 未指定 --budget 参数

**When**：
- 调用 `graph-rag.sh search "query"`

**Then**：
- 使用默认预算 8000 tokens
- 正常执行裁剪

**验证**：`tests/graph-rag.bats::test_default_budget`

### SC-SP-005: 零预算处理

**Given**：
- 预算 = 0

**When**：
- 调用 `graph-rag.sh search "query" --budget 0`

**Then**：
- 返回空结果或最小必要信息
- 不报错

**验证**：`tests/graph-rag.bats::test_zero_budget`

### SC-SP-006: 单片段超预算

**Given**：
- 预算 = 100 tokens
- 所有候选片段 Token 数 > 100

**When**：
- 执行裁剪

**Then**：
- 返回空结果或截断提示
- 警告"预算过小，无法包含任何完整片段"

**验证**：`tests/graph-rag.bats::test_single_fragment_exceeds_budget`

### SC-SP-007: 与意图偏好集成

**Given**：
- intent-learner 有用户偏好数据
- 启用意图偏好加权

**When**：
- 调用 `graph-rag.sh search "query" --budget 5000`

**Then**：
- 用户偏好高的符号获得额外优先级加权
- 最终选择结果反映用户偏好

**验证**：`tests/graph-rag.bats::test_intent_preference_integration`

### SC-SP-008: Token 估算准确性

**Given**：
- 代码片段内容已知

**When**：
- 调用 Token 估算函数

**Then**：
- 估算值与实际值误差 < 20%
- 估算偏保守（宁多估不少估）

**验证**：`tests/graph-rag.bats::test_token_estimation`

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios |
|-------------|-----------|
| REQ-SP-001 | SC-SP-001, SC-SP-003, SC-SP-004, SC-SP-005 |
| REQ-SP-002 | SC-SP-002 |
| REQ-SP-003 | SC-SP-003, SC-SP-006 |
| REQ-SP-004 | SC-SP-008 |

| Scenario | Test ID |
|----------|---------|
| SC-SP-001 | `tests/graph-rag.bats::test_budget_pruning` |
| SC-SP-002 | `tests/graph-rag.bats::test_priority_calculation` |
| SC-SP-003 | `tests/graph-rag.bats::test_budget_boundary` |
| SC-SP-004 | `tests/graph-rag.bats::test_default_budget` |
| SC-SP-005 | `tests/graph-rag.bats::test_zero_budget` |
| SC-SP-006 | `tests/graph-rag.bats::test_single_fragment_exceeds_budget` |
| SC-SP-007 | `tests/graph-rag.bats::test_intent_preference_integration` |
| SC-SP-008 | `tests/graph-rag.bats::test_token_estimation` |
