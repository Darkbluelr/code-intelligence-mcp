---
last_referenced_by: 20260118-0057-upgrade-code-intelligence-capabilities
last_verified: 2026-01-18
health: active
---

# 规格：graph-rag.sh 查询接口扩展

| 属性 | 值 |
|------|-----|
| Spec-ID | SPEC-GRAPH-RAG-001 |
| Change-ID | 20260118-0057-upgrade-code-intelligence-capabilities |
| 版本 | 1.0.0 |
| 状态 | Active |
| 作者 | Spec Owner |
| 创建日期 | 2026-01-18 |

---

## 1. Requirements（需求规格）

### REQ-GR-001: --fusion-depth 参数

**描述**：`graph-rag.sh` 必须支持 `--fusion-depth` 可选参数，控制图+向量融合查询的图扩展深度。

**参数定义**：
| 参数 | 类型 | 必需 | 默认值 | 范围 | 说明 |
|------|------|------|--------|------|------|
| `--fusion-depth` | integer | 否 | 1 | 0-5 | 图扩展深度 |

**取值行为**：
| 值 | 行为 |
|----|------|
| `0` | 仅向量搜索，不进行图扩展 |
| `1` | 1-hop 图扩展（直接邻居） |
| `2-5` | 多跳图扩展（需 CKB 可用，否则降级为 1） |

**约束**：
- 当 `--fusion-depth > 1` 且 CKB 不可用时，自动降级为 `1`
- 降级时在 `metadata` 中标记实际使用的深度

---

### REQ-GR-002: --include-virtual 参数

**描述**：`graph-rag.sh` 必须支持 `--include-virtual` 可选参数，控制是否包含虚拟边（跨仓库联邦边）。

**参数定义**：
| 参数 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `--include-virtual` | flag | 否 | false | 是否包含虚拟边 |

**行为规格**：
- 不指定：仅查询本地图边
- 指定：同时查询 `virtual_edges` 表中的跨仓库边

**虚拟边类型**：
| 边类型 | 说明 |
|--------|------|
| `VIRTUAL_CALLS` | 跨仓库函数调用 |
| `VIRTUAL_IMPORTS` | 跨仓库导入 |

---

### REQ-GR-003: 融合查询输出格式

**描述**：融合查询的 JSON 输出必须包含融合相关的元数据字段。

**输出格式**：
```json
{
  "candidates": [
    {
      "file": "src/example.ts",
      "relevance": 0.85,
      "content": "...",
      "source": "embedding|graph|virtual",
      "distance": 0
    }
  ],
  "metadata": {
    "query": "original query",
    "total_candidates": 15,
    "embedding_candidates": 10,
    "graph_candidates": 5,
    "virtual_candidates": 0,
    "fusion_depth": 1,
    "fusion_depth_requested": 1,
    "include_virtual": false,
    "ckb_available": true,
    "query_time_ms": 150
  }
}
```

**字段说明**：
| 字段 | 类型 | 说明 |
|------|------|------|
| `candidates[].source` | string | 结果来源：embedding/graph/virtual |
| `candidates[].distance` | integer | 图距离（0=锚点，1=1-hop 等） |
| `metadata.embedding_candidates` | integer | 来自向量搜索的候选数 |
| `metadata.graph_candidates` | integer | 来自图扩展的候选数 |
| `metadata.virtual_candidates` | integer | 来自虚拟边的候选数 |
| `metadata.fusion_depth` | integer | 实际使用的融合深度 |
| `metadata.fusion_depth_requested` | integer | 请求的融合深度 |
| `metadata.include_virtual` | boolean | 是否包含虚拟边 |

---

### REQ-GR-004: 融合查询候选数阈值

**描述**：融合查询（CKB 可用时）的候选数必须 >= 纯向量搜索候选数的 1.5 倍。

**验收标准**：
```
fusion_candidates >= vector_only_candidates * 1.5
```

**约束**：
- 此标准仅在 CKB 可用时适用
- CKB 不可用时，使用本地 1-hop 边遍历，候选数可能相同或略多

---

## 2. Scenarios（场景规格）

### SC-GR-001: 默认融合查询（depth=1）

**Given**：
- CKB MCP 可用
- 向量索引已建立
- 图数据库包含边数据

**When**：
- 执行 `graph-rag.sh --query "authentication handler" --format json`

**Then**：
```json
{
  "candidates": [
    {"file": "src/auth/handler.ts", "relevance": 0.92, "source": "embedding", "distance": 0},
    {"file": "src/auth/middleware.ts", "relevance": 0.85, "source": "graph", "distance": 1},
    {"file": "src/auth/types.ts", "relevance": 0.78, "source": "graph", "distance": 1}
  ],
  "metadata": {
    "total_candidates": 12,
    "embedding_candidates": 5,
    "graph_candidates": 7,
    "fusion_depth": 1,
    "fusion_depth_requested": 1,
    "ckb_available": true,
    "include_virtual": false
  }
}
```

---

### SC-GR-002: 指定融合深度

**Given**：
- CKB MCP 可用

**When**：
- 执行 `graph-rag.sh --query "test" --fusion-depth 2 --format json`

**Then**：
```json
{
  "candidates": [...],
  "metadata": {
    "fusion_depth": 2,
    "fusion_depth_requested": 2,
    "ckb_available": true
  }
}
```

---

### SC-GR-003: 融合深度降级（CKB 不可用）

**Given**：
- CKB MCP 不可用
- 请求 `--fusion-depth 3`

**When**：
- 执行 `CKB_UNAVAILABLE=1 graph-rag.sh --query "test" --fusion-depth 3 --format json`

**Then**：
```json
{
  "candidates": [...],
  "metadata": {
    "fusion_depth": 1,
    "fusion_depth_requested": 3,
    "ckb_available": false,
    "ckb_fallback_reason": "disabled"
  }
}
```
- 实际深度降级为 1
- 标记请求深度和实际深度不同

---

### SC-GR-004: 仅向量搜索（depth=0）

**Given**：
- 向量索引已建立

**When**：
- 执行 `graph-rag.sh --query "test" --fusion-depth 0 --format json`

**Then**：
```json
{
  "candidates": [...],
  "metadata": {
    "fusion_depth": 0,
    "fusion_depth_requested": 0,
    "embedding_candidates": 10,
    "graph_candidates": 0
  }
}
```
- 仅返回向量搜索结果
- `graph_candidates = 0`

---

### SC-GR-005: 包含虚拟边

**Given**：
- `virtual_edges` 表包含跨仓库边数据

**When**：
- 执行 `graph-rag.sh --query "api call" --include-virtual --format json`

**Then**：
```json
{
  "candidates": [
    {"file": "src/client.ts", "relevance": 0.88, "source": "embedding", "distance": 0},
    {"file": "external-repo://api/handler.ts", "relevance": 0.75, "source": "virtual", "distance": 1}
  ],
  "metadata": {
    "total_candidates": 8,
    "embedding_candidates": 5,
    "graph_candidates": 2,
    "virtual_candidates": 1,
    "include_virtual": true
  }
}
```

---

### SC-GR-006: 无效融合深度参数

**Given**：
- 无

**When**：
- 执行 `graph-rag.sh --query "test" --fusion-depth 10 --format json`

**Then**：
- 返回错误或自动限制为最大值 5
- 如果自动限制：
```json
{
  "metadata": {
    "fusion_depth": 5,
    "fusion_depth_requested": 10,
    "warning": "fusion-depth capped at maximum 5"
  }
}
```

---

## 3. API/Schema 契约

### 3.1 命令行接口规格

```
用法: graph-rag.sh --query <查询> [选项]

必需参数:
    --query <string>        查询内容

可选参数:
    --top-k <int>           返回候选数（默认: 10）
    --depth <int>           图遍历深度（默认: 3，最大: 5）
    --budget <int>          Token 预算（默认: 8000）
    --format <text|json>    输出格式（默认: text）
    --fusion-depth <int>    融合查询图扩展深度（默认: 1，范围: 0-5）
    --include-virtual       包含虚拟边（跨仓库）
    --min-relevance <float> 最低相关度阈值（默认: 0.0）
    --rerank                启用 LLM 重排序

环境变量:
    CKB_UNAVAILABLE=1       强制禁用 CKB MCP
    GRAPH_RAG_CACHE_ENABLED 缓存开关（默认: true）

退出码:
    0   成功
    1   参数错误
    2   依赖缺失
    3   查询失败
```

### 3.2 JSON Schema 定义

#### 输出 Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "graph-rag-output.schema.json",
  "title": "Graph-RAG Query Output",
  "type": "object",
  "properties": {
    "candidates": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "file": { "type": "string" },
          "relevance": { "type": "number", "minimum": 0, "maximum": 1 },
          "content": { "type": "string" },
          "source": { "type": "string", "enum": ["embedding", "graph", "virtual"] },
          "distance": { "type": "integer", "minimum": 0 }
        },
        "required": ["file", "relevance"]
      }
    },
    "metadata": {
      "type": "object",
      "properties": {
        "query": { "type": "string" },
        "total_candidates": { "type": "integer", "minimum": 0 },
        "embedding_candidates": { "type": "integer", "minimum": 0 },
        "graph_candidates": { "type": "integer", "minimum": 0 },
        "virtual_candidates": { "type": "integer", "minimum": 0 },
        "fusion_depth": { "type": "integer", "minimum": 0, "maximum": 5 },
        "fusion_depth_requested": { "type": "integer", "minimum": 0 },
        "include_virtual": { "type": "boolean" },
        "ckb_available": { "type": "boolean" },
        "ckb_fallback_reason": { "type": "string" },
        "query_time_ms": { "type": "integer", "minimum": 0 },
        "warning": { "type": "string" }
      },
      "required": ["fusion_depth", "ckb_available"]
    }
  },
  "required": ["candidates", "metadata"]
}
```

### 3.3 向后兼容性

| 变更类型 | 兼容性 | 说明 |
|----------|--------|------|
| 新增 `--fusion-depth` 参数 | 向后兼容 | 可选参数，不指定时使用默认值 1 |
| 新增 `--include-virtual` 参数 | 向后兼容 | 可选参数，不指定时不包含虚拟边 |
| 输出新增 `source` 字段 | 向后兼容 | 新增字段，旧脚本可忽略 |
| 输出新增 `distance` 字段 | 向后兼容 | 新增字段，旧脚本可忽略 |
| metadata 新增字段 | 向后兼容 | 新增字段，旧脚本可忽略 |

### 3.4 弃用策略

无弃用项。

---

## 4. Contract Tests

### CT-GR-001: --fusion-depth 参数解析

**类型**：behavior

**覆盖**：REQ-GR-001, SC-GR-002

**验证脚本**：
```bash
graph-rag.sh --query "test" --fusion-depth 2 --format json | \
  jq -e '.metadata.fusion_depth_requested == 2'
```

---

### CT-GR-002: --fusion-depth 默认值

**类型**：behavior

**覆盖**：REQ-GR-001, SC-GR-001

**验证脚本**：
```bash
graph-rag.sh --query "test" --format json | \
  jq -e '.metadata.fusion_depth == 1'
```

---

### CT-GR-003: --fusion-depth 降级

**类型**：behavior

**覆盖**：REQ-GR-001, SC-GR-003

**验证脚本**：
```bash
CKB_UNAVAILABLE=1 graph-rag.sh --query "test" --fusion-depth 3 --format json | \
  jq -e '.metadata.fusion_depth == 1 and .metadata.fusion_depth_requested == 3'
```

---

### CT-GR-004: --include-virtual 参数

**类型**：behavior

**覆盖**：REQ-GR-002, SC-GR-005

**验证脚本**：
```bash
graph-rag.sh --query "test" --include-virtual --format json | \
  jq -e '.metadata.include_virtual == true'
```

---

### CT-GR-005: 输出包含 source 字段

**类型**：schema

**覆盖**：REQ-GR-003

**验证脚本**：
```bash
graph-rag.sh --query "test" --format json | \
  jq -e '.candidates[0] | has("source")'
```

---

### CT-GR-006: 融合候选数阈值

**类型**：behavior

**覆盖**：REQ-GR-004

**验证脚本**：
```bash
# 仅向量搜索
vector_count=$(graph-rag.sh --query "test" --fusion-depth 0 --format json | jq '.metadata.total_candidates')

# 融合搜索
fusion_count=$(graph-rag.sh --query "test" --fusion-depth 1 --format json | jq '.metadata.total_candidates')

# 验证比例（CKB 可用时）
ckb_available=$(graph-rag.sh --query "test" --format json | jq '.metadata.ckb_available')
if [ "$ckb_available" = "true" ]; then
  test $(echo "$fusion_count >= $vector_count * 1.5" | bc) -eq 1
fi
```

---

### CT-GR-007: fusion-depth=0 仅向量搜索

**类型**：behavior

**覆盖**：REQ-GR-001, SC-GR-004

**验证脚本**：
```bash
graph-rag.sh --query "test" --fusion-depth 0 --format json | \
  jq -e '.metadata.graph_candidates == 0'
```

---

## 5. 追溯矩阵

| Contract Test ID | 类型 | 覆盖需求/场景 |
|------------------|------|---------------|
| CT-GR-001 | behavior | REQ-GR-001, SC-GR-002 |
| CT-GR-002 | behavior | REQ-GR-001, SC-GR-001 |
| CT-GR-003 | behavior | REQ-GR-001, SC-GR-003 |
| CT-GR-004 | behavior | REQ-GR-002, SC-GR-005 |
| CT-GR-005 | schema | REQ-GR-003 |
| CT-GR-006 | behavior | REQ-GR-004 |
| CT-GR-007 | behavior | REQ-GR-001, SC-GR-004 |
