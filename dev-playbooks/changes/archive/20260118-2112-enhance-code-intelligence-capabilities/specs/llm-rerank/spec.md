# 规格 Delta：重排序管线集成

> **Change-ID**: `20260118-2112-enhance-code-intelligence-capabilities`
> **Capability**: llm-rerank
> **Delta Type**: EXTEND
> **Version**: 2.0.0
> **Created**: 2026-01-19

---

## MODIFIED Requirements

### REQ-LR-001：默认启用重排序（修改）

**原要求**：重排序为可选功能

**新要求**：重排序作为 `graph-rag.sh` 的默认管线

```bash
# 默认启用
graph-rag.sh <query>  # 自动调用 reranker.sh

# 禁用重排序
graph-rag.sh <query> --no-rerank
```

**配置开关**：
```yaml
# config/features.yaml
reranker:
  enabled: true  # 默认启用
  strategy: auto  # auto/llm/heuristic
```

**Trace**: AC-006

---

### REQ-LR-002：双策略支持（新增）

系统应支持两种重排序策略：

| 策略 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| LLM 重排序 | 使用 Ollama 进行语义重排序 | 效果好 | 依赖外部服务 |
| 启发式重排序 | 基于代码相似度规则 | 无外部依赖 | 效果一般 |

**命令**：
```bash
graph-rag.sh <query> --rerank-strategy <llm|heuristic>
```

**Trace**: AC-006

---

### REQ-LR-003：自动降级（新增）

系统应在 LLM 重排序失败时自动降级：

```
降级链：
LLM 重排序 → 启发式重排序 → 无重排序

触发条件：
- LLM 服务不可用
- LLM 超时（> 5s）
- LLM 返回错误
```

**降级日志**：
```
WARN: LLM reranker timeout, falling back to heuristic reranker
INFO: Heuristic reranker completed in 50ms
```

**Trace**: AC-006

---

### REQ-LR-004：重排序质量指标（新增）

系统应支持评估重排序效果：

```bash
reranker.sh --benchmark <query-file>
```

**指标**：
- 重排序后 MRR@10 提升
- 重排序延迟
- 降级频率

**目标**：
- MRR@10 提升 > 10%
- LLM 重排序延迟 < 5s
- 启发式重排序延迟 < 100ms

**Trace**: AC-006

---

## ADDED Scenarios

### SC-LR-001：默认重排序

**Given**: 用户查询 "graph query optimization"
**When**: 运行 `graph-rag.sh "graph query optimization"`
**Then**:
- 自动调用 reranker.sh
- 使用配置的默认策略（auto）
- 返回重排序后的结果

**Trace**: AC-006

---

### SC-LR-002：LLM 重排序

**Given**: Ollama 服务可用
**When**: 运行 `graph-rag.sh <query> --rerank-strategy llm`
**Then**:
- 使用 LLM 进行语义重排序
- 延迟 < 5s
- MRR@10 提升 > 10%

**Trace**: AC-006

---

### SC-LR-003：启发式重排序

**Given**: 用户希望避免外部依赖
**When**: 运行 `graph-rag.sh <query> --rerank-strategy heuristic`
**Then**:
- 使用启发式规则重排序
- 延迟 < 100ms
- 无外部服务依赖

**Trace**: AC-006

---

### SC-LR-004：LLM 超时降级

**Given**: LLM 服务响应超过 5s
**When**: 运行 LLM 重排序
**Then**:
- 检测到超时
- 自动降级到启发式重排序
- 输出降级警告
- 返回启发式重排序结果

**Trace**: AC-006

---

### SC-LR-005：禁用重排序

**Given**: 用户希望跳过重排序
**When**: 运行 `graph-rag.sh <query> --no-rerank`
**Then**:
- 跳过重排序步骤
- 直接返回检索结果
- 延迟更低

**Trace**: AC-006

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-LR-001（修改） | SC-LR-001, SC-LR-005 | AC-006 |
| REQ-LR-002（新增） | SC-LR-002, SC-LR-003 | AC-006 |
| REQ-LR-003（新增） | SC-LR-004 | AC-006 |
| REQ-LR-004（新增） | SC-LR-002, SC-LR-003 | AC-006 |

---

## 与现有规格的关系

**扩展自**：`dev-playbooks/specs/llm-rerank/spec.md` v1.0.0

**主要变更**：
1. 重排序从可选变为默认启用
2. 新增双策略支持（LLM + 启发式）
3. 新增自动降级机制
4. 集成到 graph-rag.sh 管线

**兼容性**：向后兼容，可通过 `--no-rerank` 禁用
