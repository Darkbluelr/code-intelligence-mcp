# 规格：LLM 重排序（llm-rerank）

> **Change ID**: `augment-parity`
> **Capability**: llm-rerank
> **Version**: 1.0.0
> **Status**: Active
> **Created**: 2026-01-15
> **Last Referenced By**: 20260118-2112-enhance-code-intelligence-capabilities
> **Last Verified**: 2026-01-22
> **Health**: active

---

## Requirements（需求）

### REQ-LR-001：功能开关控制

LLM 重排序应通过功能开关控制：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `features.llm_rerank.enabled` | `false` | 是否启用 LLM 重排序 |
| `features.llm_rerank.provider` | `anthropic` | LLM 提供商 |
| `features.llm_rerank.model` | `claude-3-haiku` | 使用的模型 |
| `features.llm_rerank.timeout_ms` | `2000` | 超时时间（毫秒） |

**约束**：
- 默认关闭，用户无需配置即可使用基础功能
- 启用时需配置对应的 API Key 环境变量

### REQ-LR-002：多模型支持

系统应支持以下 LLM 提供商：

| 提供商 | provider 值 | 环境变量 | 模型示例 |
|--------|-------------|----------|----------|
| Anthropic | `anthropic` | `ANTHROPIC_API_KEY` | claude-3-haiku |
| OpenAI | `openai` | `OPENAI_API_KEY` | gpt-4o-mini |
| Ollama | `ollama` | - | llama3 |

### REQ-LR-003：重排序流程

重排序流程应遵循以下步骤：

1. 接收向量检索 Top-K 候选（最多 10 个）
2. 构建重排序 Prompt
3. 调用 LLM API（2s 超时）
4. 解析 JSON 响应
5. 按 score 降序重排候选
6. 返回重排后结果

### REQ-LR-004：Prompt 模板

系统应使用标准化 Prompt 模板：

```
You are a code relevance judge. Given a user query and a list of code snippets,
rank the snippets by their relevance to the query.

**User Query**: {query}

**Candidate Code Snippets**:
{candidates}

**Instructions**:
1. Evaluate each snippet's relevance to the query (0-10 scale)
2. Consider: semantic match, symbol references, call relationships, context fit
3. Return a JSON array of rankings

**Output Format** (JSON only, no explanation):
[
  {"index": 0, "score": 8, "reason": "direct match"},
  {"index": 1, "score": 5, "reason": "partial relevance"},
  ...
]
```

### REQ-LR-005：Token 预算控制

系统应控制 Token 使用：

| 限制项 | 值 | 说明 |
|--------|-----|------|
| 最大候选数 | 10 | 单次重排序最多 10 个候选 |
| 每个候选最大 tokens | 500 | 截断超长代码片段 |
| 总输入预算 | ~6000 | query + candidates + prompt |
| 预期输出 | ~200 | JSON 响应 |

### REQ-LR-006：降级策略

当以下情况发生时，应跳过重排序并返回原始排序：

| 情况 | 降级行为 |
|------|----------|
| `features.llm_rerank.enabled = false` | 直接跳过 |
| API Key 未配置 | 跳过，输出警告 |
| LLM 调用超时（2s） | 跳过，输出警告 |
| LLM 返回非 JSON | 跳过，输出警告 |
| LLM 返回格式错误 | 跳过，输出警告 |

**约束**：降级时系统仍正常工作，不抛出错误。

### REQ-LR-007：重试机制

LLM 调用应支持重试：

- 最大重试次数：3 次
- 重试间隔：指数退避（1s → 2s → 4s）
- 重试条件：网络错误、429 Too Many Requests

### REQ-LR-008：结果格式

重排序结果应包含以下信息：

```json
{
  "candidates": [
    {
      "index": 0,
      "original_rank": 2,
      "score": 8,
      "reason": "direct match",
      "snippet": "..."
    }
  ],
  "metadata": {
    "reranked": true,
    "provider": "anthropic",
    "model": "claude-3-haiku",
    "latency_ms": 450
  }
}
```

---

## Scenarios（场景）

### SC-LR-001：禁用时直接返回原始排序

**Given**: `features.llm_rerank.enabled = false`（默认）
**When**: 执行 `graph-rag.sh --query "auth handler" --rerank`
**Then**:
- 跳过 LLM 重排序
- 返回原始向量检索排序
- metadata 标记 `reranked: false`

### SC-LR-002：启用后成功重排序

**Given**:
- `features.llm_rerank.enabled = true`
- `ANTHROPIC_API_KEY` 已配置
- 向量检索返回 5 个候选
**When**: 执行 `graph-rag.sh --query "auth handler" --rerank`
**Then**:
- 调用 Claude API 进行重排序
- 按 LLM 评分重新排序候选
- metadata 标记 `reranked: true`
- 输出延迟信息

### SC-LR-003：超时降级

**Given**:
- `features.llm_rerank.enabled = true`
- LLM 调用耗时 > 2000ms
**When**: 执行重排序
**Then**:
- 超时后终止 LLM 调用
- 输出警告：`LLM rerank timeout after 2000ms, using original ranking`
- 返回原始排序
- metadata 标记 `reranked: false, skip_reason: "timeout"`

### SC-LR-004：API Key 未配置降级

**Given**:
- `features.llm_rerank.enabled = true`
- `ANTHROPIC_API_KEY` 未配置
**When**: 执行重排序
**Then**:
- 输出警告：`LLM API key not configured, skipping rerank`
- 返回原始排序
- metadata 标记 `reranked: false, skip_reason: "api_key_missing"`

### SC-LR-005：切换到 OpenAI

**Given**:
- `features.llm_rerank.provider = openai`
- `features.llm_rerank.model = gpt-4o-mini`
- `OPENAI_API_KEY` 已配置
**When**: 执行重排序
**Then**:
- 使用 OpenAI API
- 成功重排序
- metadata 标记 `provider: "openai"`

### SC-LR-006：使用本地 Ollama

**Given**:
- `features.llm_rerank.provider = ollama`
- `features.llm_rerank.model = llama3`
- Ollama 服务运行中
**When**: 执行重排序
**Then**:
- 调用本地 Ollama API
- 成功重排序
- metadata 标记 `provider: "ollama"`

### SC-LR-007：响应格式错误降级

**Given**:
- LLM 返回非 JSON 响应（如纯文本解释）
**When**: 解析响应
**Then**:
- 输出警告：`LLM response is not valid JSON, using original ranking`
- 返回原始排序
- metadata 标记 `reranked: false, skip_reason: "invalid_response"`

### SC-LR-008：候选截断

**Given**: 某个代码片段超过 500 tokens
**When**: 构建 Prompt
**Then**:
- 截断超长片段到 500 tokens
- 添加 `[truncated]` 标记
- 正常进行重排序

### SC-LR-009：重试成功

**Given**:
- 第一次调用返回 429 Too Many Requests
- 第二次调用成功
**When**: 执行重排序
**Then**:
- 第一次失败后等待 1s
- 重试成功
- 输出：`LLM call retry 1/3 succeeded`
- 返回重排序结果

### SC-LR-010：重试耗尽

**Given**: 连续 3 次调用均失败（网络错误）
**When**: 执行重排序
**Then**:
- 输出：`LLM call failed after 3 retries, using original ranking`
- 返回原始排序
- metadata 标记 `reranked: false, skip_reason: "max_retries_exceeded"`

### SC-LR-011：空候选列表

**Given**: 向量检索返回 0 个候选
**When**: 执行重排序
**Then**:
- 跳过 LLM 调用
- 返回空列表
- metadata 标记 `reranked: false, skip_reason: "no_candidates"`

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-LR-001 | SC-LR-001, SC-LR-002 | AC-004 |
| REQ-LR-002 | SC-LR-005, SC-LR-006 | AC-004 |
| REQ-LR-003 | SC-LR-002 | AC-004 |
| REQ-LR-004 | SC-LR-002 | AC-004 |
| REQ-LR-005 | SC-LR-008 | AC-004 |
| REQ-LR-006 | SC-LR-001, SC-LR-003, SC-LR-004, SC-LR-007, SC-LR-011 | AC-004 |
| REQ-LR-007 | SC-LR-009, SC-LR-010 | AC-004 |
| REQ-LR-008 | SC-LR-002 | AC-004 |
