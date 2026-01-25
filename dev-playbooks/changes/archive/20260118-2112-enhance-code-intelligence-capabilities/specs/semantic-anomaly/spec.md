# 规格 Delta：语义异常检测闭环

> **Change-ID**: `20260118-2112-enhance-code-intelligence-capabilities`
> **Capability**: semantic-anomaly
> **Delta Type**: EXTEND
> **Version**: 2.0.0
> **Created**: 2026-01-19

---

## ADDED Requirements

### REQ-SA-001：异常结果输出（新增）

系统应将异常检测结果输出到标准化文件：

```bash
semantic-anomaly.sh --output anomalies.jsonl
```

**输出格式**：
```jsonl
{"file": "src/service.ts", "type": "pattern_deviation", "confidence": 0.85, "line": 42, "description": "Unusual error handling pattern"}
{"file": "src/utils.ts", "type": "complexity_spike", "confidence": 0.92, "line": 100, "description": "Function complexity 3x higher than average"}
```

**字段说明**：
- `file`: 文件路径
- `type`: 异常类型（pattern_deviation/complexity_spike/naming_inconsistency）
- `confidence`: 置信度（0.0-1.0）
- `line`: 行号
- `description`: 异常描述

**Trace**: AC-008

---

### REQ-SA-002：与 Bug 定位集成（新增）

系统应将异常检测结果集成到 Bug 定位：

```bash
# bug-locator.sh 自动读取 anomalies.jsonl
bug-locator.sh --error "NullPointerException"

# 优先推荐异常文件
# 输出：
# 1. src/service.ts (anomaly_score: 0.85, hotspot: 0.70)
# 2. src/utils.ts (anomaly_score: 0.92, hotspot: 0.50)
```

**优先级计算**：
```bash
priority_score = base_score * (1 + anomaly_confidence * 0.3)
```

**Trace**: AC-008

---

### REQ-SA-003：模式学习反馈（新增）

系统应将异常检测结果反馈到模式学习：

```bash
# pattern-learner.sh 读取 anomalies.jsonl
pattern-learner.sh --learn-from-anomalies

# 学习异常模式
# 输出：
# Learned 5 new anomaly patterns
# Updated pattern database
```

**学习内容**：
- 异常模式特征
- 异常出现频率
- 异常与 Bug 的关联

**Trace**: AC-008

---

### REQ-SA-004：用户反馈机制（新增）

系统应支持用户标记异常为正常/异常：

```bash
semantic-anomaly.sh --feedback <file> <line> <normal|anomaly>
```

**反馈存储**：
```jsonl
{"file": "src/service.ts", "line": 42, "feedback": "normal", "timestamp": "2026-01-19T10:00:00Z"}
```

**反馈应用**：
- 调整异常检测阈值
- 更新模式学习权重
- 减少误报

**Trace**: AC-008

---

### REQ-SA-005：异常报告生成（新增）

系统应生成异常检测报告：

```bash
semantic-anomaly.sh --report
```

**报告内容**：
1. 异常总数和分布
2. 高置信度异常列表
3. 异常与 Bug 的关联分析
4. 建议的修复优先级

**报告存储**：`evidence/semantic-anomaly-report.md`

**Trace**: AC-008

---

## ADDED Scenarios

### SC-SA-001：输出异常结果

**Given**: 检测到 3 个异常
**When**: 运行 `semantic-anomaly.sh --output anomalies.jsonl`
**Then**:
- 生成 `anomalies.jsonl` 文件
- 包含 3 条异常记录
- 每条记录包含完整字段

**Trace**: AC-008

---

### SC-SA-002：Bug 定位优先推荐异常文件

**Given**:
- `anomalies.jsonl` 包含 `src/service.ts`（confidence: 0.85）
- Bug 定位基础分数：`src/service.ts` = 0.70

**When**: 运行 `bug-locator.sh --error "NullPointerException"`
**Then**:
- `src/service.ts` 获得异常加权（0.70 * 1.255 = 0.88）
- 排名提升
- 优先推荐给用户

**Trace**: AC-008

---

### SC-SA-003：模式学习从异常学习

**Given**: `anomalies.jsonl` 包含 5 个异常模式
**When**: 运行 `pattern-learner.sh --learn-from-anomalies`
**Then**:
- 学习 5 个新异常模式
- 更新模式数据库
- 输出学习摘要

**Trace**: AC-008

---

### SC-SA-004：用户标记误报

**Given**: 异常检测误报（正常代码被标记为异常）
**When**: 运行 `semantic-anomaly.sh --feedback src/service.ts 42 normal`
**Then**:
- 记录用户反馈
- 调整该模式的检测阈值
- 下次检测时不再误报

**Trace**: AC-008

---

### SC-SA-005：生成异常报告

**Given**: 检测到 10 个异常
**When**: 运行 `semantic-anomaly.sh --report`
**Then**:
- 生成 Markdown 格式报告
- 包含异常分布、高置信度异常、关联分析
- 保存到 `evidence/semantic-anomaly-report.md`

**Trace**: AC-008

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-SA-001（新增） | SC-SA-001 | AC-008 |
| REQ-SA-002（新增） | SC-SA-002 | AC-008 |
| REQ-SA-003（新增） | SC-SA-003 | AC-008 |
| REQ-SA-004（新增） | SC-SA-004 | AC-008 |
| REQ-SA-005（新增） | SC-SA-005 | AC-008 |

---

## 依赖关系

**依赖的现有能力**：
- `semantic-anomaly.sh`：异常检测基础
- `pattern-learner.sh`：模式学习
- `bug-locator.sh`：Bug 定位

**被依赖的能力**：
- `bug-locator.sh`：使用异常检测结果
- `pattern-learner.sh`：从异常学习模式

---

## 非功能需求

### 性能基准

| 场景 | 指标 | 阈值 |
|------|------|------|
| 异常结果输出 | 延迟 | < 100ms |
| Bug 定位集成 | 延迟增量 | < 50ms |
| 模式学习 | 延迟 | < 2s |
| 用户反馈记录 | 延迟 | < 10ms |

### 准确性要求

| 检查项 | 要求 |
|--------|------|
| 异常检测准确率 | > 80% |
| 误报率 | < 20% |
| Bug 关联准确率 | > 75% |
