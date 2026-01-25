# 规格：混合检索（RRF 融合）

> **Capability**: hybrid-retrieval
> **Version**: 1.0.0
> **Status**: Active
> **Created**: 2026-01-19
> **Last Referenced By**: 20260118-2112-enhance-code-intelligence-capabilities
> **Last Verified**: 2026-01-22
> **Health**: active

---

## Requirements（需求）

### REQ-HR-001：RRF 融合算法

系统应实现 Reciprocal Rank Fusion (RRF) 算法融合多种检索结果：

```
RRF_score(d) = Σ_r [ 1 / (k + rank_r(d)) ]

其中：
- d: 文档
- r: 检索方法（关键词、向量、图距离）
- rank_r(d): 文档 d 在方法 r 中的排名
- k: 常数（默认 60）

最终权重：
score(d) = w_keyword × RRF_keyword(d) + w_vector × RRF_vector(d) + w_graph × RRF_graph(d)
```

**默认权重**：
- 关键词：30%
- 向量：50%
- 图距离：20%

**Trace**: AC-005

---

### REQ-HR-002：混合检索命令

系统应扩展 `embedding.sh` 支持混合检索：

```bash
embedding.sh --hybrid <query> [options]

Options:
  --weights <k,v,g>        # 权重配置（默认: 0.3,0.5,0.2）
  --keyword-only           # 仅关键词检索
  --vector-only            # 仅向量检索
  --graph-only             # 仅图距离检索
  --top-k <n>              # 返回前 N 个结果（默认: 10）
```

**Trace**: AC-005

---

### REQ-HR-003：权重配置

系统应支持通过配置文件自定义权重：

```yaml
# config/features.yaml
hybrid_retrieval:
  enabled: true
  weights:
    keyword: 0.3
    vector: 0.5
    graph: 0.2
  rrf_k: 60
```

**约束**：
- 权重总和必须为 1.0
- 每个权重范围：0.0-1.0

**Trace**: AC-005

---

### REQ-HR-004：降级策略

系统应在部分检索方法不可用时自动降级：

| 场景 | 降级策略 |
|------|----------|
| 向量索引不可用 | 降级为关键词 + 图距离 |
| 图存储不可用 | 降级为关键词 + 向量 |
| 仅关键词可用 | 降级为纯关键词检索 |

**Trace**: AC-005

---

### REQ-HR-005：检索质量指标

系统应支持计算检索质量指标：

```bash
embedding.sh --benchmark <query-file>
```

**指标**：
- MRR@10 (Mean Reciprocal Rank)
- Recall@10
- Precision@10

**输出**：
```json
{
  "mrr_at_10": 0.69,
  "recall_at_10": 0.85,
  "precision_at_10": 0.75,
  "baseline_mrr": 0.54,
  "improvement": "+27.8%"
}
```

**Trace**: AC-005

---

## Scenarios（场景）

### SC-HR-001：基础混合检索

**Given**: 查询 "graph query optimization"
**When**: 运行 `embedding.sh --hybrid "graph query optimization"`
**Then**:
- 执行关键词、向量、图距离三种检索
- 使用 RRF 融合结果
- 返回前 10 个结果
- MRR@10 > 0.65

**Trace**: AC-005

---

### SC-HR-002：自定义权重

**Given**: 用户希望更重视向量检索
**When**: 运行 `embedding.sh --hybrid "query" --weights 0.2,0.6,0.2`
**Then**:
- 使用自定义权重（关键词 20%，向量 60%，图距离 20%）
- 向量检索结果权重更高
- 返回融合结果

**Trace**: AC-005

---

### SC-HR-003：向量索引不可用降级

**Given**: 向量索引未初始化
**When**: 运行 `embedding.sh --hybrid "query"`
**Then**:
- 检测到向量索引不可用
- 自动降级为关键词 + 图距离
- 输出警告：`Vector index unavailable, using keyword + graph only`
- 返回降级结果

**Trace**: AC-005

---

### SC-HR-004：检索质量对比

**Given**: 基线 MRR@10 = 0.54
**When**: 运行混合检索 benchmark
**Then**:
- 混合检索 MRR@10 > 0.65
- 提升 > 15%
- 输出对比报告

**Trace**: AC-005

---

### SC-HR-005：权重配置验证

**Given**: 用户配置权重总和 ≠ 1.0
**When**: 运行混合检索
**Then**:
- 返回错误：`Invalid weights: sum must equal 1.0`
- 不执行检索

**Trace**: AC-005

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-HR-001 | SC-HR-001, SC-HR-002 | AC-005 |
| REQ-HR-002 | SC-HR-001, SC-HR-002 | AC-005 |
| REQ-HR-003 | SC-HR-002, SC-HR-005 | AC-005 |
| REQ-HR-004 | SC-HR-003 | AC-005 |
| REQ-HR-005 | SC-HR-004 | AC-005 |

---

## 依赖关系

**依赖的现有能力**：
- `embedding.sh`：向量检索
- `graph-store.sh`：图距离计算
- `ripgrep`：关键词检索

**被依赖的能力**：
- `graph-rag.sh`：使用混合检索结果
- `bug-locator.sh`：使用混合检索定位 Bug

---

## 非功能需求

### 性能基准

| 场景 | 指标 | 阈值 |
|------|------|------|
| 混合检索（10 结果） | 延迟 | < 500ms |
| RRF 融合计算 | 延迟 | < 50ms |
| 权重配置加载 | 延迟 | < 10ms |

### 质量目标

| 指标 | 目标 | 基线 |
|------|------|------|
| MRR@10 | > 0.65 | 0.54 |
| Recall@10 | > 0.80 | 0.70 |
| Precision@10 | > 0.70 | 0.60 |
