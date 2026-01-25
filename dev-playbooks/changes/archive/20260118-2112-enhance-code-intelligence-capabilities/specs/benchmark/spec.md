# 规格 Delta：评测基准

> **Change-ID**: `20260118-2112-enhance-code-intelligence-capabilities`
> **Capability**: benchmark
> **Delta Type**: NEW
> **Version**: 1.0.0
> **Created**: 2026-01-19

---

## ADDED Requirements

### REQ-BM-001：评测数据集支持

系统应支持两种评测数据集：

| 数据集类型 | 说明 | 用途 |
|-----------|------|------|
| 自举数据集 | 本项目代码库 | 回归测试 |
| 公开数据集 | CodeSearchNet | 标准化对比 |

**命令**：
```bash
benchmark.sh --dataset <self|public|both>
```

**Trace**: AC-009

---

### REQ-BM-002：评测指标

系统应支持以下评测指标：

| 指标 | 说明 | 计算方式 |
|------|------|----------|
| MRR@10 | 平均倒数排名 | 1/rank（前 10 个结果） |
| Recall@10 | 召回率 | 相关结果数 / 总相关结果数 |
| P95 延迟 | 95 分位延迟 | 排序后第 95% 位置的延迟 |
| 压缩率 | 上下文压缩率 | 输出 token / 输入 token |
| 漂移检测准确率 | 架构漂移检测准确率 | 正确检测数 / 总检测数 |

**Trace**: AC-009

---

### REQ-BM-003：基线对比

系统应支持与基线对比：

```bash
# 建立基线
benchmark.sh --baseline

# 对比基线
benchmark.sh --compare evidence/baseline-metrics.json
```

**对比输出**：
```json
{
  "current": {
    "mrr_at_10": 0.69,
    "p95_latency_ms": 180
  },
  "baseline": {
    "mrr_at_10": 0.54,
    "p95_latency_ms": 1200
  },
  "improvement": {
    "mrr_at_10": "+27.8%",
    "p95_latency_ms": "-85.0%"
  },
  "regression_detected": false
}
```

**Trace**: AC-009

---

### REQ-BM-004：回归检测

系统应自动检测性能回退：

**阈值**：
- P95 延迟：不得超过基线 × 1.1
- MRR@10：不得低于基线 × 0.95
- 内存使用：不得超过基线 × 1.2

**回退时**：
- 返回非零退出码
- 输出详细回退报告
- 提供回滚建议

**Trace**: AC-009, AC-011

---

### REQ-BM-005：报告生成

系统应生成 Markdown 和 JSON 两种格式的报告：

```bash
benchmark.sh --output evidence/benchmark-report.md
```

**报告内容**：
1. 评测摘要（指标总览）
2. 详细指标（按功能点分组）
3. 基线对比（如有）
4. 回归检测结果
5. 性能趋势图（可选）

**Trace**: AC-009

---

### REQ-BM-006：查询样本管理

系统应支持管理查询样本：

```bash
# 查询样本文件格式
# queries.jsonl
{"query": "graph query", "expected": ["graph-store.sh", "call-chain.sh"]}
{"query": "bug locate", "expected": ["bug-locator.sh"]}

# 运行评测
benchmark.sh --queries queries.jsonl
```

**Trace**: AC-009

---

## ADDED Scenarios

### SC-BM-001：自举数据集评测

**Given**: 本项目代码库（32 个脚本）
**When**: 运行 `benchmark.sh --dataset self`
**Then**:
- 使用本项目代码作为评测数据
- 计算 MRR@10、P95 延迟等指标
- 输出评测报告

**Trace**: AC-009

---

### SC-BM-002：公开数据集评测

**Given**: CodeSearchNet 数据集
**When**: 运行 `benchmark.sh --dataset public`
**Then**:
- 下载或使用本地 CodeSearchNet 数据
- 运行标准化评测
- 输出对比报告

**Trace**: AC-009

---

### SC-BM-003：建立基线

**Given**: 变更前的系统状态
**When**: 运行 `benchmark.sh --baseline`
**Then**:
- 运行完整评测
- 保存基线数据到 `evidence/baseline-metrics.json`
- 输出基线指标

**Trace**: AC-009

---

### SC-BM-004：检测性能回退

**Given**: 基线 P95 延迟 = 1200ms
**When**: 运行 `benchmark.sh --compare evidence/baseline-metrics.json`
**Then**:
- 当前 P95 延迟 = 1400ms（超过基线 × 1.1）
- 检测到性能回退
- 返回退出码 1
- 输出回退报告

**Trace**: AC-009, AC-011

---

### SC-BM-005：无回退场景

**Given**: 基线 MRR@10 = 0.54
**When**: 运行对比，当前 MRR@10 = 0.69
**Then**:
- 未检测到回退
- 返回退出码 0
- 输出改进报告：`MRR@10 improved by +27.8%`

**Trace**: AC-009, AC-011

---

### SC-BM-006：生成 Markdown 报告

**Given**: 评测完成
**When**: 运行 `benchmark.sh --output evidence/benchmark-report.md`
**Then**:
- 生成 Markdown 格式报告
- 包含所有指标和对比
- 包含性能趋势图（如有）

**Trace**: AC-009

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-BM-001 | SC-BM-001, SC-BM-002 | AC-009 |
| REQ-BM-002 | All | AC-009 |
| REQ-BM-003 | SC-BM-003, SC-BM-004, SC-BM-005 | AC-009 |
| REQ-BM-004 | SC-BM-004, SC-BM-005 | AC-009, AC-011 |
| REQ-BM-005 | SC-BM-006 | AC-009 |
| REQ-BM-006 | All | AC-009 |

---

## 依赖关系

**依赖的现有能力**：
- 所有功能脚本（用于评测）
- `embedding.sh`：检索质量评测
- `graph-store.sh`：图查询性能评测
- `context-compressor.sh`：压缩率评测
- `drift-detector.sh`：漂移检测准确率评测

**被依赖的能力**：无

---

## 非功能需求

### 性能基准

| 场景 | 指标 | 阈值 |
|------|------|------|
| 自举数据集评测 | 耗时 | < 2min |
| 公开数据集评测 | 耗时 | < 5min |
| 基线对比 | 耗时 | < 10s |

### 准确性要求

| 检查项 | 要求 |
|--------|------|
| 指标计算准确性 | 100% |
| 回归检测准确性 | > 95% |
| 报告完整性 | 100% |
