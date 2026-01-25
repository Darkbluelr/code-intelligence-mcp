# 规格 Delta：上下文层信号增强

> **Change-ID**: `20260118-2112-enhance-code-intelligence-capabilities`
> **Capability**: context-layer
> **Delta Type**: EXTEND
> **Version**: 2.0.0
> **Created**: 2026-01-19

---

## ADDED Requirements

### REQ-CL-001：历史修复权重（新增）

系统应提取历史修复权重并纳入检索：

```bash
# 权重计算
fix_weight = bug_fix_count * 0.6 + recent_fixes * 0.4

# 集成到检索
priority_score = base_score * (1 + fix_weight * 0.2)
```

**数据来源**：
- Git commit 历史（关键词：fix/bug/patch）
- Issue 关联（如有）

**Trace**: AC-007

---

### REQ-CL-002：意图权重（新增）

系统应提取用户查询历史并计算意图权重：

```bash
# 意图权重计算
intent_weight = query_frequency * 0.5 + recent_queries * 0.3 + click_through * 0.2

# 集成到检索
priority_score = base_score * (1 + intent_weight * 0.15)
```

**数据来源**：
- 用户查询历史（存储在 `.devbooks/intent-history.jsonl`）
- 点击行为（用户选择的结果）

**Trace**: AC-007

---

### REQ-CL-003：会话焦点（新增）

系统应提取当前会话焦点并加权：

```bash
# 会话焦点
session_focus = {
  "files": ["src/graph-store.sh", "src/call-chain.sh"],
  "symbols": ["query_graph", "trace_calls"],
  "topics": ["graph query", "performance"]
}

# 焦点加权
if file in session_focus.files:
  priority_score *= 1.5
```

**数据来源**：
- 当前对话中提及的文件/符号
- 最近打开的文件

**Trace**: AC-007

---

### REQ-CL-004：信号衰减（新增）

系统应实现信号衰减机制：

```bash
# 时间衰减
decay_factor = exp(-days_since_event / 90)

# 应用衰减
decayed_weight = original_weight * decay_factor
```

**衰减周期**：
- 历史修复权重：90 天衰减至 0
- 意图权重：30 天衰减至 0
- 会话焦点：当前会话有效

**Trace**: AC-007

---

### REQ-CL-005：信号开关（新增）

系统应支持通过配置开关控制信号：

```yaml
# config/features.yaml
context_signals:
  enabled: true
  fix_weight: true
  intent_weight: true
  session_focus: true
  decay_enabled: true
```

**Trace**: AC-007

---

## ADDED Scenarios

### SC-CL-001：历史修复权重加权

**Given**:
- 文件 A 有 10 次 Bug 修复记录
- 文件 B 有 0 次 Bug 修复记录

**When**: 运行检索，两个文件基础分数相同
**Then**:
- 文件 A 的优先级分数更高（历史修复权重加成）
- 文件 A 排名靠前

**Trace**: AC-007

---

### SC-CL-002：意图权重加权

**Given**:
- 用户最近 5 次查询都与 "graph query" 相关
- 文件 A 与 "graph query" 高度相关
- 文件 B 与 "graph query" 无关

**When**: 运行检索
**Then**:
- 文件 A 获得意图权重加成
- 文件 A 排名靠前

**Trace**: AC-007

---

### SC-CL-003：会话焦点加权

**Given**:
- 当前会话中提及 "src/graph-store.sh"
- 检索结果包含 "src/graph-store.sh" 和其他文件

**When**: 运行检索
**Then**:
- "src/graph-store.sh" 获得 1.5x 焦点加权
- 排名显著提升

**Trace**: AC-007

---

### SC-CL-004：信号衰减

**Given**:
- 文件 A 在 100 天前有 Bug 修复记录
- 文件 B 在 10 天前有 Bug 修复记录

**When**: 运行检索
**Then**:
- 文件 A 的修复权重已衰减至接近 0
- 文件 B 的修复权重保持较高
- 文件 B 排名更高

**Trace**: AC-007

---

### SC-CL-005：禁用信号

**Given**: 配置 `context_signals.enabled = false`
**When**: 运行检索
**Then**:
- 不应用任何上下文信号
- 仅使用基础检索分数
- 结果与禁用前不同

**Trace**: AC-007

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-CL-001（新增） | SC-CL-001, SC-CL-004 | AC-007 |
| REQ-CL-002（新增） | SC-CL-002 | AC-007 |
| REQ-CL-003（新增） | SC-CL-003 | AC-007 |
| REQ-CL-004（新增） | SC-CL-004 | AC-007 |
| REQ-CL-005（新增） | SC-CL-005 | AC-007 |

---

## 依赖关系

**依赖的现有能力**：
- `graph-rag.sh`：集成信号到检索权重
- Git 历史：提取修复记录
- 用户交互日志：提取意图权重

**被依赖的能力**：
- `graph-rag.sh`：使用上下文信号

---

## 非功能需求

### 性能基准

| 场景 | 指标 | 阈值 |
|------|------|------|
| 信号提取 | 延迟 | < 50ms |
| 信号加权计算 | 延迟 | < 10ms |
| 衰减计算 | 延迟 | < 5ms |

### 准确性要求

| 检查项 | 要求 |
|--------|------|
| 修复记录提取准确性 | > 90% |
| 意图权重计算准确性 | > 85% |
| 会话焦点识别准确性 | > 95% |
