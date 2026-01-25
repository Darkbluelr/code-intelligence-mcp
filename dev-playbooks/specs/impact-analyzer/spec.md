# 规格：M2 传递性影响分析

> **模块 ID**: `impact-analyzer`
> **Change ID**: `achieve-augment-full-parity`
> **Date**: 2026-01-16
> **Status**: Draft

---

## Requirements（需求）

### REQ-IA-001: 多跳图遍历

系统必须支持多跳图遍历，以分析符号变更的传递性影响。

**约束**：
- 最大遍历深度：5 跳（可配置）
- 遍历算法：BFS（广度优先搜索）
- 边类型：CALLS、IMPORTS、DEFINES、MODIFIES

### REQ-IA-002: 置信度衰减算法

系统必须实现置信度衰减算法，量化传递性影响的可信程度。

**约束**：
- 衰减公式：`Impact(node, depth) = base_impact × (decay_factor ^ depth)`
- 默认衰减系数：0.8
- 影响阈值：0.1（低于此值忽略）

### REQ-IA-003: 多种输出格式

系统必须支持多种输出格式以适应不同使用场景。

**约束**：
- 支持格式：JSON、Markdown、Mermaid
- 默认格式：JSON

### REQ-IA-004: 性能要求

5 跳深度的影响分析必须在合理时间内完成。

**约束**：
- 响应时间 < 1 秒
- 支持中间结果缓存

---

## Scenarios（场景）

### SC-IA-001: 符号影响分析

**Given**：
- graph.db 中存在符号 `src/server.ts::handleToolCall`
- 存在调用关系链

**When**：
- 调用 `impact-analyzer.sh analyze src/server.ts::handleToolCall --depth 3`

**Then**：
- 系统执行 3 跳 BFS 遍历
- 计算每个受影响节点的置信度
- 过滤低于阈值的节点
- 返回影响矩阵

**验证**：`tests/impact-analyzer.bats::test_symbol_impact`

### SC-IA-002: 文件级影响分析

**Given**：
- 文件 `scripts/common.sh` 被多个脚本依赖

**When**：
- 调用 `impact-analyzer.sh file scripts/common.sh --depth 2`

**Then**：
- 系统识别文件中所有符号
- 对每个符号执行影响分析
- 合并去重受影响节点
- 返回文件级影响矩阵

**验证**：`tests/impact-analyzer.bats::test_file_impact`

### SC-IA-003: 置信度正确计算

**Given**：
- 符号 A 被 B 调用（深度 1）
- 符号 B 被 C 调用（深度 2）
- 符号 C 被 D 调用（深度 3）
- decay_factor = 0.8

**When**：
- 调用 `impact-analyzer.sh analyze A --depth 5`

**Then**：
- B 的 impact = 0.8（1.0 × 0.8^1）
- C 的 impact = 0.64（1.0 × 0.8^2）
- D 的 impact = 0.512（1.0 × 0.8^3）
- 所有值高于阈值 0.1，均被包含在结果中

**验证**：`tests/impact-analyzer.bats::test_confidence_calculation`

### SC-IA-004: 阈值过滤

**Given**：
- 调用链深度 > 10 跳
- 部分节点置信度 < 0.1

**When**：
- 调用 `impact-analyzer.sh analyze <symbol> --depth 5 --threshold 0.1`

**Then**：
- 置信度 < 0.1 的节点不出现在结果中
- 返回过滤后的影响矩阵

**验证**：`tests/impact-analyzer.bats::test_threshold_filter`

### SC-IA-005: Mermaid 格式输出

**Given**：
- 影响分析产生多个受影响节点

**When**：
- 调用 `impact-analyzer.sh analyze <symbol> --format mermaid`

**Then**：
- 系统输出有效的 Mermaid 流程图语法
- 节点包含置信度标注
- 边标注深度

**验证**：`tests/impact-analyzer.bats::test_mermaid_output`

### SC-IA-006: 深度限制保护

**Given**：
- 存在循环依赖或超深调用链

**When**：
- 调用 `impact-analyzer.sh analyze <symbol> --depth 5`

**Then**：
- 遍历在达到深度 5 后停止
- 不会无限循环
- 返回深度范围内的结果

**验证**：`tests/impact-analyzer.bats::test_depth_limit`

### SC-IA-007: 空结果处理

**Given**：
- 符号无调用者

**When**：
- 调用 `impact-analyzer.sh analyze <leaf-symbol>`

**Then**：
- 返回空影响矩阵
- 明确指示"无受影响节点"

**验证**：`tests/impact-analyzer.bats::test_empty_result`

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios |
|-------------|-----------|
| REQ-IA-001 | SC-IA-001, SC-IA-002, SC-IA-006 |
| REQ-IA-002 | SC-IA-003, SC-IA-004 |
| REQ-IA-003 | SC-IA-005 |
| REQ-IA-004 | SC-IA-001, SC-IA-006 |

| Scenario | Test ID |
|----------|---------|
| SC-IA-001 | `tests/impact-analyzer.bats::test_symbol_impact` |
| SC-IA-002 | `tests/impact-analyzer.bats::test_file_impact` |
| SC-IA-003 | `tests/impact-analyzer.bats::test_confidence_calculation` |
| SC-IA-004 | `tests/impact-analyzer.bats::test_threshold_filter` |
| SC-IA-005 | `tests/impact-analyzer.bats::test_mermaid_output` |
| SC-IA-006 | `tests/impact-analyzer.bats::test_depth_limit` |
| SC-IA-007 | `tests/impact-analyzer.bats::test_empty_result` |
