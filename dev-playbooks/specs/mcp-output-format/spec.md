---
last_referenced_by: 20260118-0057-upgrade-code-intelligence-capabilities
last_verified: 2026-01-18
health: active
---

# 规格：MCP 工具 JSON 输出格式扩展

| 属性 | 值 |
|------|-----|
| Spec-ID | SPEC-MCP-OUTPUT-001 |
| Change-ID | 20260118-0057-upgrade-code-intelligence-capabilities |
| 版本 | 1.0.0 |
| 状态 | Active |
| 作者 | Spec Owner |
| 创建日期 | 2026-01-18 |

---

## 1. Requirements（需求规格）

### REQ-MCP-001: metadata.ckb_available 字段

**描述**：所有返回 JSON 的 MCP 工具必须在 `metadata` 对象中包含 `ckb_available` 布尔字段，指示 CKB MCP 服务是否可用。

**触发工具**：
- `ci_graph_rag`
- `ci_call_chain`（如有 CKB 增强）

**字段定义**：
| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `metadata.ckb_available` | boolean | 是 | - | CKB MCP 是否可用 |

**取值规则**：
- `true`：CKB MCP 健康检查通过，使用 CKB 图数据
- `false`：CKB MCP 不可用，使用本地降级数据

---

### REQ-MCP-002: metadata.ckb_fallback_reason 字段

**描述**：当 `ckb_available = false` 时，必须提供 `ckb_fallback_reason` 字段说明降级原因。

**字段定义**：
| 字段 | 类型 | 必需 | 条件 | 说明 |
|------|------|------|------|------|
| `metadata.ckb_fallback_reason` | string | 条件 | 当 `ckb_available = false` | 降级原因 |

**枚举值**：
| 值 | 说明 |
|----|------|
| `connection_timeout` | CKB 连接超时（>5s） |
| `mcp_error` | CKB MCP 工具调用错误 |
| `health_check_failed` | CKB 健康检查失败 |
| `cooldown` | 处于降级冷却期（60s 内） |
| `disabled` | CKB 集成被禁用（配置） |

---

### REQ-MCP-003: metadata.fusion_depth 字段

**描述**：融合查询返回的结果中必须包含 `fusion_depth` 字段，指示图扩展的实际深度。

**字段定义**：
| 字段 | 类型 | 必需 | 范围 | 说明 |
|------|------|------|------|------|
| `metadata.fusion_depth` | integer | 是 | 0-5 | 融合查询的图扩展深度 |

**取值规则**：
- `0`：仅向量搜索，无图扩展
- `1`：1-hop 图扩展（默认，当前版本固定值）
- `2-5`：多跳图扩展（未来版本支持）

---

## 2. Scenarios（场景规格）

### SC-MCP-001: CKB 可用时的正常输出

**Given**：
- CKB MCP Server 运行中
- CKB 健康检查通过（<5s 响应）

**When**：
- 调用 `ci_graph_rag` 工具，query = "test function"

**Then**：
```json
{
  "candidates": [
    {"file": "src/test.ts", "relevance": 0.85, "content": "..."}
  ],
  "metadata": {
    "ckb_available": true,
    "fusion_depth": 1,
    "total_candidates": 12,
    "query_time_ms": 150
  }
}
```

---

### SC-MCP-002: CKB 连接超时降级

**Given**：
- CKB MCP Server 响应延迟 > 5s

**When**：
- 调用 `ci_graph_rag` 工具

**Then**：
```json
{
  "candidates": [...],
  "metadata": {
    "ckb_available": false,
    "ckb_fallback_reason": "connection_timeout",
    "ckb_last_error": "Connection timeout after 5000ms",
    "fallback_mode": "local_graph",
    "fusion_depth": 1
  }
}
```

---

### SC-MCP-003: CKB 降级冷却期

**Given**：
- CKB 刚降级（<60s 前）

**When**：
- 调用 `ci_graph_rag` 工具

**Then**：
```json
{
  "candidates": [...],
  "metadata": {
    "ckb_available": false,
    "ckb_fallback_reason": "cooldown",
    "ckb_cooldown_remaining_s": 45,
    "fusion_depth": 1
  }
}
```

---

### SC-MCP-004: CKB 禁用时的输出

**Given**：
- 配置 `ckb_integration.enabled = false`

**When**：
- 调用 `ci_graph_rag` 工具

**Then**：
```json
{
  "candidates": [...],
  "metadata": {
    "ckb_available": false,
    "ckb_fallback_reason": "disabled",
    "fusion_depth": 1
  }
}
```

---

## 3. API/Schema 契约

### 3.1 JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "mcp-output-metadata.schema.json",
  "title": "MCP Output Metadata",
  "description": "MCP 工具输出的 metadata 字段规格",
  "type": "object",
  "properties": {
    "ckb_available": {
      "type": "boolean",
      "description": "CKB MCP 是否可用"
    },
    "ckb_fallback_reason": {
      "type": "string",
      "enum": ["connection_timeout", "mcp_error", "health_check_failed", "cooldown", "disabled"],
      "description": "CKB 降级原因（仅当 ckb_available = false）"
    },
    "ckb_last_error": {
      "type": "string",
      "description": "CKB 最近的错误信息"
    },
    "ckb_cooldown_remaining_s": {
      "type": "integer",
      "minimum": 0,
      "maximum": 60,
      "description": "降级冷却剩余秒数"
    },
    "fallback_mode": {
      "type": "string",
      "enum": ["local_graph", "vector_only"],
      "description": "降级模式"
    },
    "fusion_depth": {
      "type": "integer",
      "minimum": 0,
      "maximum": 5,
      "description": "融合查询图扩展深度"
    }
  },
  "required": ["ckb_available", "fusion_depth"],
  "if": {
    "properties": { "ckb_available": { "const": false } }
  },
  "then": {
    "required": ["ckb_fallback_reason"]
  }
}
```

### 3.2 向后兼容性

| 变更类型 | 兼容性 | 说明 |
|----------|--------|------|
| 新增 `metadata.ckb_available` | 向后兼容 | 新增字段，旧客户端可忽略 |
| 新增 `metadata.ckb_fallback_reason` | 向后兼容 | 新增字段，旧客户端可忽略 |
| 新增 `metadata.fusion_depth` | 向后兼容 | 新增字段，旧客户端可忽略 |

### 3.3 弃用策略

无弃用项。

---

## 4. Contract Tests

### CT-MCP-001: ckb_available 字段存在性

**类型**：schema

**覆盖**：REQ-MCP-001

**验证脚本**：
```bash
graph-rag.sh --query "test" --format json | jq -e '.metadata | has("ckb_available")'
```

---

### CT-MCP-002: ckb_fallback_reason 条件必需

**类型**：behavior

**覆盖**：REQ-MCP-002

**验证脚本**：
```bash
# 模拟 CKB 不可用
CKB_UNAVAILABLE=1 graph-rag.sh --query "test" --format json | \
  jq -e '.metadata.ckb_available == false and .metadata.ckb_fallback_reason != null'
```

---

### CT-MCP-003: fusion_depth 字段存在性和范围

**类型**：schema

**覆盖**：REQ-MCP-003

**验证脚本**：
```bash
graph-rag.sh --query "test" --format json | \
  jq -e '.metadata.fusion_depth >= 0 and .metadata.fusion_depth <= 5'
```

---

### CT-MCP-004: CKB 超时降级

**类型**：behavior

**覆盖**：SC-MCP-002

**验证脚本**：
```bash
# 模拟网络延迟 > 5s
CKB_MOCK_DELAY_MS=6000 graph-rag.sh --query "test" --format json | \
  jq -e '.metadata.ckb_available == false and .metadata.ckb_fallback_reason == "connection_timeout"'
```

---

## 5. 追溯矩阵

| Contract Test ID | 类型 | 覆盖需求/场景 |
|------------------|------|---------------|
| CT-MCP-001 | schema | REQ-MCP-001 |
| CT-MCP-002 | behavior | REQ-MCP-002, SC-MCP-002 |
| CT-MCP-003 | schema | REQ-MCP-003 |
| CT-MCP-004 | behavior | SC-MCP-002 |
