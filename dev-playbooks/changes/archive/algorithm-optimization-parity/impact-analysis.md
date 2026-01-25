# 影响分析：算法优化与轻资产能力对等

> **Change ID**: algorithm-optimization-parity
> **分析日期**: 2026-01-17
> **分析模式**: 基础模式（Grep 文本搜索）
> **CKB 状态**: SCIP 不可用，Git 可用

---

## 检测结果

```
- 配置文件：.devbooks/config.yaml
- 真理目录根：dev-playbooks/specs/
- 变更包目录根：dev-playbooks/changes/
- CKB 索引：SCIP 不可用，Git 可用
- proposal.md 状态：Approved，Impact 章节已存在
- 运行模式：增量分析（增强/验证已有分析）
```

⚠️ CKB 不可用，使用 Grep 文本搜索进行影响分析。

---

## Scope

### 直接影响：9 个文件

| 文件 | 变更类型 | 变更内容 |
|------|----------|----------|
| `scripts/graph-rag.sh` | 修改 | 背包算法、TF-IDF、去重融合、距离度量、LLM 重排序 |
| `scripts/impact-analyzer.sh` | 修改 | 内存 BFS、动态衰减 |
| `scripts/intent-learner.sh` | 修改 | 半衰期衰减、动作权重、乘法加权 |
| `scripts/common.sh` | 修改 | 智能 Token 估算 |
| `config/features.yaml` | 修改 | LLM 重排序配置项 |
| `tests/graph-rag.bats` | 修改 | 背包算法、TF-IDF、去重测试 |
| `tests/impact-analyzer.bats` | 修改 | 内存 BFS、动态衰减测试 |
| `tests/intent-learner.bats` | 修改 | 半衰期、动作权重测试 |
| `tests/common.bats` | 新增 | Token 估算测试 |

### 间接影响：4 个文件

| 文件 | 影响原因 |
|------|----------|
| `src/server.ts` | 调用 graph-rag.sh、impact-analyzer.sh、intent-learner.sh（通过 runScript） |
| `.devbooks/corpus-stats.json` | 运行时生成的 TF-IDF 语料库统计文件 |
| `scripts/reranker.sh` | LLM 重排序的实际执行脚本 |
| `hooks/augment-context-global.sh` | 引用 llm_rerank 配置和 reranker 工具 |

---

## Impacts

| 文件 | 影响类型 | 风险等级 | 说明 |
|------|----------|----------|------|
| `scripts/graph-rag.sh` | 直接修改 | 🔴 高 | 核心检索逻辑，5 个算法模块变更 |
| `scripts/impact-analyzer.sh` | 直接修改 | 🟡 中 | BFS 算法重构，影响传递性分析 |
| `scripts/intent-learner.sh` | 直接修改 | 🟡 中 | 权重公式变更，影响偏好计算 |
| `scripts/common.sh` | 直接修改 | 🟢 低 | 新增函数，不影响现有函数 |
| `config/features.yaml` | 直接修改 | 🟢 低 | 新增可选配置项，向后兼容 |
| `src/server.ts` | 间接依赖 | 🟢 低 | 无接口变更，透明优化 |
| `scripts/reranker.sh` | 间接集成 | 🟢 低 | 已存在，LLM 重排序配置化 |

### 依赖关系图

```
server.ts ──调用──> graph-rag.sh ──加载──> common.sh
                         │                     │
                         │                     └──> estimate_tokens_smart()
                         └──> _is_llm_rerank_enabled()
                         └──> llm_rerank_candidates() ──调用──> reranker.sh

server.ts ──调用──> impact-analyzer.sh ──加载──> common.sh
                         │
                         └──> bfs_impact_fast()
                         └──> calculate_dynamic_decay()

server.ts ──调用──> intent-learner.sh ──加载──> common.sh
                         │
                         └──> calculate_recency_weight_halflife()
                         └──> calculate_preference_score()
                         └──> apply_context_boost_multiplicative()
```

### 引用分析

#### graph-rag.sh 被引用位置

| 引用文件 | 行号 | 引用方式 |
|----------|------|----------|
| `src/server.ts` | 426 | `runScript("graph-rag.sh", [...])` |
| `tests/graph-rag.bats` | 全文件 | 测试脚本 |
| `tests/llm-rerank.bats` | 多处 | `$GRAPH_RAG --query ...` |
| `tests/subgraph-retrieval.bats` | 多处 | 集成测试 |

#### impact-analyzer.sh 被引用位置

| 引用文件 | 行号 | 引用方式 |
|----------|------|----------|
| `src/server.ts` | 614 | `runScript("impact-analyzer.sh", scriptArgs)` |
| `tests/impact-analyzer.bats` | 全文件 | 测试脚本 |

#### intent-learner.sh 被引用位置

| 引用文件 | 行号 | 引用方式 |
|----------|------|----------|
| `src/server.ts` | 687 | `runScript("intent-learner.sh", scriptArgs)` |
| `tests/intent-learner.bats` | 全文件 | 测试脚本 |

---

## Risks

| 风险 | 可能性 | 影响 | 缓解措施 | 状态 |
|------|--------|------|----------|------|
| 背包算法性能（大候选集 n>100, B>8000） | 低 | 中 | 自动降级到 awk 实现 | ✅ B-01 已解决 |
| TF-IDF 首次构建阻塞查询 | 中 | 低 | 异步构建 + 降级为纯 TF | ✅ B-02 已解决 |
| 内存 BFS 大图 OOM（>10000 节点） | 低 | 高 | 深度限制 + 分批加载边 | ⚠️ 待补充节点上限策略 |
| IGNORE 负权重累积导致负分 | 中 | 低 | 分数下限保护 max(0, score) | ✅ B-03 已解决 |
| 中文检测正则不兼容 macOS/Linux | 高 | 中 | 使用 `[一-龥]` 替代 Unicode 转义 | ✅ B-04 已解决 |
| bc 浮点精度不足 | 低 | 低 | 使用 scale=6，足够精度 | ✅ 已处理 |
| 半衰期模型过度惩罚新查询 | 低 | 低 | 参数可配置，默认 decay_rate=0.02 | ✅ 已处理 |

---

## Minimal Diff

### 核心函数变更清单

| 模块 | 原函数 | 新函数 | 变更类型 |
|------|--------|--------|----------|
| graph-rag.sh | `select_within_budget()` | `knapsack_select()` | 替换 |
| graph-rag.sh | `extract_keywords()` | `extract_keywords_tfidf()` | 替换 |
| graph-rag.sh | `merge_candidates()` | `merge_candidates_with_fusion()` | 替换 |
| graph-rag.sh | `calculate_distance()` | `calculate_multidim_distance()` | 替换 |
| impact-analyzer.sh | `bfs_impact_analysis()` | `bfs_impact_fast()` | 替换 |
| impact-analyzer.sh | - | `calculate_dynamic_decay()` | 新增 |
| intent-learner.sh | `calculate_recency_weight()` | `calculate_recency_weight_halflife()` | 替换 |
| intent-learner.sh | `calculate_preference_score()` | `calculate_preference_score()` | 修改（负权重+下限保护） |
| intent-learner.sh | `apply_context_boost()` | `apply_context_boost_multiplicative()` | 替换 |
| common.sh | - | `estimate_tokens_smart()` | 新增 |

### 配置项变更

```yaml
# config/features.yaml 新增（向后兼容，默认关闭）
llm_rerank:
  enabled: false  # 默认关闭
  provider: auto  # auto | anthropic | openai | ollama
  model: auto
  max_candidates: 50
  timeout_ms: 5000
  fallback_on_error: true
```

### 运行时生成文件

| 文件 | 生成时机 | 用途 |
|------|----------|------|
| `.devbooks/corpus-stats.json` | 首次查询时异步构建 | TF-IDF 语料库统计 |

---

## Open Questions

| 编号 | 问题 | 影响 | 建议处理 | 状态 |
|------|------|------|----------|------|
| OQ-A01 | 语料库统计是否应该随代码变更增量更新？ | TF-IDF 准确度 | 建议 commit hook 触发更新 | ✅ proposal 已说明 |
| OQ-A02 | 动态衰减是否应该考虑边类型权重？ | 衰减精度 | 建议先简单实现，后续迭代 | 待确认 |
| OQ-A03 | 用户活跃度检测的回溯天数？ | 半衰期准确度 | 建议 30 天，可配置 | ✅ proposal 已说明 |
| OQ-A04 | 内存 BFS 的节点上限？ | 大图性能 | 建议 10000 节点，超过分批 | 待确认 |

---

## 现有分析验证

对比 proposal.md 第 3 节的 Impact 分析：

| 维度 | proposal 原分析 | 本次验证 | 结论 |
|------|----------------|----------|------|
| 直接影响文件数 | 10 个 | 9 个（修改+新增） | ✅ 一致 |
| MCP 工具接口 | 无变更 | 确认无变更 | ✅ 一致 |
| 配置文件兼容性 | 向后兼容 | 确认向后兼容 | ✅ 一致 |
| 性能影响 | +10-100x | 需验证基准 | ⚠️ 待 Red 基线证据 |

---

## 结论与建议

### 结论

1. **影响范围可控**：变更集中在 4 个核心脚本 + 1 个配置文件 + 4 个测试文件
2. **风险已缓解**：proposal 的 B-01 至 B-04 阻断项已解决
3. **向后兼容**：所有优化对外接口透明，配置项均有默认值

### 建议补充

| 建议 | 目标文档 | 优先级 |
|------|----------|--------|
| 明确内存 BFS 的节点上限策略 | design.md | P1 |
| 补充 AC→证据映射表 | verification.md | P1 |
| 记录 Red 基线性能数据 | evidence/red-baseline/ | P0 |

---

**Impact Analyst 签名**：Impact Analyst (Claude)
**日期**：2026-01-17
