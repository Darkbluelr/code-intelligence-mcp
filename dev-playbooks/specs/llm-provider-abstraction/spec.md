# 规格：LLM Provider 抽象接口

> **Capability**: llm-provider-abstraction
> **Version**: 1.0.0
> **Status**: Active
> **Created**: 2026-01-17
> **Last Referenced By**: augment-final-10-percent
> **Last Verified**: 2026-01-17
> **Health**: active

---

## Requirements（需求）

### REQ-LPA-001：Provider 接口定义

系统应定义标准化的 LLM Provider 接口：

```bash
# 接口函数签名
llm_provider_rerank(query, candidates_json) → ranked_json
llm_provider_call(prompt) → response
llm_provider_validate() → bool
llm_provider_info() → json
```

### REQ-LPA-002：Provider 注册机制

系统应支持通过配置文件注册 Provider：

```yaml
# config/llm-providers.yaml
providers:
  <provider_name>:
    script: llm-providers/<name>.sh
    env_key: <ENV_VAR_NAME>
    default_model: <model_id>
    endpoint: <optional_endpoint>
```

### REQ-LPA-003：支持的 Provider

系统必须内置以下 Provider 实现：

| Provider | 脚本 | 环境变量 | 默认模型 |
|----------|------|----------|----------|
| Anthropic | anthropic.sh | ANTHROPIC_API_KEY | claude-3-haiku |
| OpenAI | openai.sh | OPENAI_API_KEY | gpt-4o-mini |
| Ollama | ollama.sh | - | llama3 |
| Mock | mock.sh | - | mock |

### REQ-LPA-004：自动 Provider 选择

系统应按以下优先级自动选择 Provider：

1. 配置文件显式指定
2. 检测可用的 API Key（优先顺序：Anthropic → OpenAI → Ollama）
3. 降级到 Mock（测试环境）

### REQ-LPA-005：统一响应格式

所有 Provider 必须返回统一的响应格式：

```json
{
  "success": true,
  "provider": "anthropic",
  "model": "claude-3-haiku",
  "result": [...],
  "usage": {
    "input_tokens": 1000,
    "output_tokens": 200
  },
  "latency_ms": 450
}
```

### REQ-LPA-006：错误处理

Provider 必须处理以下错误场景：

| 错误类型 | 处理方式 |
|----------|----------|
| API Key 缺失 | 返回 `{"success": false, "error": "api_key_missing"}` |
| 超时 | 返回 `{"success": false, "error": "timeout"}` |
| 速率限制 | 重试 3 次，指数退避 |
| 无效响应 | 返回 `{"success": false, "error": "invalid_response"}` |

### REQ-LPA-007：Mock 模式

Provider 必须支持 Mock 模式用于测试：

```bash
# 环境变量控制
LLM_MOCK_RESPONSE='[...]'     # 模拟响应
LLM_MOCK_DELAY_MS=100         # 模拟延迟
LLM_MOCK_FAIL_COUNT=2         # 模拟前 N 次失败
```

---

## Scenarios（场景）

### SC-LPA-001：配置指定 Provider

**Given**: `config/features.yaml` 指定 `provider: openai`
**When**: 调用 `llm_rerank()`
**Then**:
- 加载 `llm-providers/openai.sh`
- 使用 OpenAI API
- 返回标准格式结果

### SC-LPA-002：自动检测 Provider

**Given**:
- 未配置 `provider`
- 设置了 `ANTHROPIC_API_KEY`
**When**: 调用 `llm_rerank()`
**Then**:
- 自动选择 Anthropic Provider
- 正常执行重排序

### SC-LPA-003：Provider 降级

**Given**:
- 配置 `provider: anthropic`
- `ANTHROPIC_API_KEY` 未设置
**When**: 调用 `llm_rerank()`
**Then**:
- 输出警告
- 降级到 Mock Provider（或跳过重排序）

### SC-LPA-004：新增 Provider

**Given**: 需要添加 Azure OpenAI 支持
**When**:
1. 创建 `llm-providers/azure-openai.sh`
2. 在配置中注册
**Then**:
- 无需修改核心代码
- 新 Provider 可正常使用

### SC-LPA-005：Mock 测试模式

**Given**: 设置 `LLM_MOCK_RESPONSE='[{"index":0,"score":9}]'`
**When**: 调用 `llm_rerank()`
**Then**:
- 不调用真实 API
- 返回 Mock 响应

---

## API 契约

### llm_provider_rerank

```bash
# 输入
llm_provider_rerank "用户查询" '[{"file":"a.ts","content":"..."}]'

# 输出
{
  "success": true,
  "provider": "anthropic",
  "ranked": [
    {"index": 0, "score": 9, "reason": "直接匹配"}
  ]
}
```

### llm_provider_call

```bash
# 输入
llm_provider_call "请分析这段代码..."

# 输出
{
  "success": true,
  "provider": "openai",
  "content": "这段代码..."
}
```

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-LPA-001 | SC-LPA-001, SC-LPA-002 | AC-001 |
| REQ-LPA-002 | SC-LPA-004 | AC-002 |
| REQ-LPA-003 | SC-LPA-001 | AC-001 |
| REQ-LPA-004 | SC-LPA-002, SC-LPA-003 | AC-001 |
| REQ-LPA-005 | All | AC-001 |
| REQ-LPA-006 | SC-LPA-003 | AC-001 |
| REQ-LPA-007 | SC-LPA-005 | AC-001 |
