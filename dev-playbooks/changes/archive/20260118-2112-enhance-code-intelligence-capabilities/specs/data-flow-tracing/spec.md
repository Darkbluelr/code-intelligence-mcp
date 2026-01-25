# 规格 Delta：数据流追踪增强

> **Change-ID**: `20260118-2112-enhance-code-intelligence-capabilities`
> **Capability**: data-flow-tracing
> **Delta Type**: EXTEND
> **Version**: 3.0.0
> **Created**: 2026-01-19

---

## MODIFIED Requirements

### REQ-DFT-001：数据流追踪命令（扩展）

**原命令**：
```bash
call-chain.sh --data-flow <symbol> [options]
```

**新增选项**：
```bash
--max-depth <n>          # 最大深度限制（默认: 5，范围: 1-10）
--output <file>          # 输出到文件
--format <json|mermaid|text>  # 输出格式（新增 text）
```

**Trace**: AC-003

---

### REQ-DFT-007：跨函数追踪深度限制（新增）

系统应支持最多 5 跳的跨函数追踪：

| 深度 | 说明 | 用途 |
|------|------|------|
| 1-3 | 近距离追踪 | 快速定位 |
| 4-5 | 中距离追踪 | 完整路径分析 |
| > 5 | 禁止（截断） | 防止性能问题 |

**超过限制时**：
- 标记 `truncated: true`
- 输出警告：`Data flow truncated at depth 5`

**Trace**: AC-003

---

### REQ-DFT-008：循环引用检测（新增）

系统应检测并处理循环引用：

```
算法：Cycle Detection

1. 维护访问集合 VISITED = {}
2. 对每个符号 S：
   a. 如果 S in VISITED: 检测到循环
   b. 记录循环路径
   c. 终止该分支追踪
3. 输出循环警告
```

**输出示例**：
```json
{
  "cycle_detected": true,
  "cycle_path": ["funcA", "funcB", "funcC", "funcA"],
  "message": "Circular data flow detected, stopping trace"
}
```

**Trace**: AC-003

---

### REQ-DFT-009：非 TS/JS 语言处理（新增）

系统应对非 TypeScript/JavaScript 文件返回友好错误：

```bash
# 追踪 Python 文件
call-chain.sh --data-flow process_data --file src/utils.py

# 输出
Error: Data flow tracing only supports TypeScript/JavaScript files.
File: src/utils.py (Python)
Suggestion: Use call-chain.sh without --data-flow for basic call chain analysis.
```

**Trace**: AC-003

---

## ADDED Scenarios

### SC-DFT-005：深度限制截断

**Given**: 数据流深度超过 5 跳
**When**: 运行 `call-chain.sh --data-flow x --max-depth 5`
**Then**:
- 在第 5 跳停止追踪
- 标记 `truncated: true`
- 输出警告消息

**Trace**: AC-003

---

### SC-DFT-006：循环引用检测

**Given**: 函数 A → B → C → A 形成循环
**When**: 运行 `call-chain.sh --data-flow A --direction forward`
**Then**:
- 检测到循环引用
- 输出循环路径
- 终止该分支追踪
- 不陷入无限循环

**Trace**: AC-003

---

### SC-DFT-007：非支持语言错误提示

**Given**: 尝试追踪 Python 文件中的符号
**When**: 运行 `call-chain.sh --data-flow process_data --file src/utils.py`
**Then**:
- 返回友好错误消息
- 说明仅支持 TypeScript/JavaScript
- 提供替代方案建议

**Trace**: AC-003

---

### SC-DFT-008：跨文件追踪验证

**Given**: 数据流跨越 3 个文件传递
**When**: 运行数据流追踪
**Then**:
- 完整追踪跨文件路径
- 正确记录每个文件边界
- 输出包含所有文件路径

**Trace**: AC-003

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-DFT-001（扩展） | All | AC-003 |
| REQ-DFT-007（新增） | SC-DFT-005 | AC-003 |
| REQ-DFT-008（新增） | SC-DFT-006 | AC-003 |
| REQ-DFT-009（新增） | SC-DFT-007 | AC-003 |

---

## 与现有规格的关系

**扩展自**：`dev-playbooks/specs/data-flow-tracing/spec.md` v2.0.0

**主要变更**：
1. 新增深度限制（最多 5 跳）
2. 新增循环引用检测
3. 新增非支持语言错误处理
4. 扩展输出格式选项

**兼容性**：向后兼容，默认行为保持不变
