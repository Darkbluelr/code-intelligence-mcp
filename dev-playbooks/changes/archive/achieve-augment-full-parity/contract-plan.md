# 契约计划：achieve-augment-full-parity

> **Change ID**: `achieve-augment-full-parity`
> **Date**: 2026-01-16
> **Status**: Draft

---

## 1. API 变更（MCP 工具接口）

### 1.1 新增工具（5 个）

#### ci_ast_delta

| 属性 | 值 |
|------|-----|
| 名称 | `ci_ast_delta` |
| 描述 | 增量更新 AST 索引 |
| 变更类型 | 新增 |
| 向后兼容 | 是（新增工具） |

**输入 Schema**：

```json
{
  "type": "object",
  "properties": {
    "file": {
      "type": "string",
      "description": "文件路径（可选，不指定则批量更新）"
    },
    "since": {
      "type": "string",
      "description": "Git 引用（用于批量更新，如 HEAD~1）"
    }
  }
}
```

**输出 Schema**：

```json
{
  "type": "object",
  "properties": {
    "strategy": {
      "type": "string",
      "enum": ["INCREMENTAL", "FULL_REBUILD", "FALLBACK"]
    },
    "files_updated": { "type": "integer" },
    "delta": {
      "type": "object",
      "properties": {
        "added": { "type": "integer" },
        "removed": { "type": "integer" },
        "modified": { "type": "integer" }
      }
    },
    "latency_ms": { "type": "number" }
  }
}
```

---

#### ci_impact

| 属性 | 值 |
|------|-----|
| 名称 | `ci_impact` |
| 描述 | 分析符号变更的传递性影响 |
| 变更类型 | 新增 |
| 向后兼容 | 是（新增工具） |

**输入 Schema**：

```json
{
  "type": "object",
  "properties": {
    "symbol": {
      "type": "string",
      "description": "待分析的符号"
    },
    "depth": {
      "type": "integer",
      "description": "最大深度（默认 5）",
      "default": 5,
      "minimum": 1,
      "maximum": 10
    },
    "format": {
      "type": "string",
      "enum": ["json", "md", "mermaid"],
      "default": "json"
    },
    "threshold": {
      "type": "number",
      "description": "影响阈值（默认 0.1）",
      "default": 0.1
    }
  },
  "required": ["symbol"]
}
```

**输出 Schema**：

```json
{
  "type": "object",
  "properties": {
    "root": { "type": "string" },
    "depth": { "type": "integer" },
    "affected": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "symbol": { "type": "string" },
          "depth": { "type": "integer" },
          "impact": { "type": "number" }
        }
      }
    },
    "total_affected": { "type": "integer" }
  }
}
```

---

#### ci_cod

| 属性 | 值 |
|------|-----|
| 名称 | `ci_cod` |
| 描述 | 生成代码库概览图 |
| 变更类型 | 新增 |
| 向后兼容 | 是（新增工具） |

**输入 Schema**：

```json
{
  "type": "object",
  "properties": {
    "level": {
      "type": "integer",
      "enum": [1, 2, 3],
      "description": "可视化层级",
      "default": 2
    },
    "format": {
      "type": "string",
      "enum": ["mermaid", "d3json"],
      "default": "mermaid"
    },
    "module": {
      "type": "string",
      "description": "模块路径（可选，用于 Level 3）"
    },
    "include_hotspots": {
      "type": "boolean",
      "default": true
    },
    "include_complexity": {
      "type": "boolean",
      "default": true
    }
  }
}
```

**输出 Schema**：

Mermaid 格式返回字符串，D3.js JSON 返回：

```json
{
  "type": "object",
  "properties": {
    "nodes": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": { "type": "string" },
          "group": { "type": "string" },
          "hotspot": { "type": "number" },
          "complexity": { "type": "integer" }
        }
      }
    },
    "links": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "source": { "type": "string" },
          "target": { "type": "string" },
          "type": { "type": "string" }
        }
      }
    },
    "metadata": {
      "type": "object",
      "properties": {
        "generated_at": { "type": "string" },
        "level": { "type": "integer" },
        "total_nodes": { "type": "integer" },
        "total_edges": { "type": "integer" }
      }
    }
  }
}
```

---

#### ci_intent

| 属性 | 值 |
|------|-----|
| 名称 | `ci_intent` |
| 描述 | 记录或查询用户查询意图 |
| 变更类型 | 新增 |
| 向后兼容 | 是（新增工具） |

**输入 Schema**：

```json
{
  "type": "object",
  "properties": {
    "action": {
      "type": "string",
      "enum": ["record", "query", "cleanup"]
    },
    "query": {
      "type": "string",
      "description": "查询字符串（record 时必需）"
    },
    "symbols": {
      "type": "array",
      "items": { "type": "string" },
      "description": "匹配的符号（record 时必需）"
    },
    "user_action": {
      "type": "string",
      "enum": ["view", "edit", "ignore"],
      "default": "view"
    },
    "top": {
      "type": "integer",
      "description": "返回 Top N 偏好（query 时使用）",
      "default": 10
    },
    "prefix": {
      "type": "string",
      "description": "按前缀过滤（query 时使用）"
    }
  },
  "required": ["action"]
}
```

**输出 Schema**：

```json
{
  "type": "object",
  "properties": {
    "success": { "type": "boolean" },
    "preferences": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "symbol": { "type": "string" },
          "score": { "type": "number" }
        }
      }
    },
    "cleaned_count": { "type": "integer" }
  }
}
```

---

#### ci_vuln

| 属性 | 值 |
|------|-----|
| 名称 | `ci_vuln` |
| 描述 | 扫描和追踪安全漏洞 |
| 变更类型 | 新增 |
| 向后兼容 | 是（新增工具） |

**输入 Schema**：

```json
{
  "type": "object",
  "properties": {
    "action": {
      "type": "string",
      "enum": ["scan", "trace"]
    },
    "package": {
      "type": "string",
      "description": "包名（trace 时必需）"
    },
    "severity": {
      "type": "string",
      "enum": ["low", "moderate", "high", "critical"],
      "default": "moderate"
    },
    "include_dev": {
      "type": "boolean",
      "default": false
    },
    "format": {
      "type": "string",
      "enum": ["json", "md"],
      "default": "json"
    }
  },
  "required": ["action"]
}
```

**输出 Schema**：

```json
{
  "type": "object",
  "properties": {
    "scan_time": { "type": "string" },
    "total": { "type": "integer" },
    "by_severity": {
      "type": "object",
      "properties": {
        "critical": { "type": "integer" },
        "high": { "type": "integer" },
        "moderate": { "type": "integer" },
        "low": { "type": "integer" }
      }
    },
    "vulnerabilities": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "version": { "type": "string" },
          "severity": { "type": "string" },
          "title": { "type": "string" },
          "path": { "type": "array", "items": { "type": "string" } }
        }
      }
    }
  }
}
```

---

### 1.2 增强工具（2 个）

#### ci_graph_rag（新增参数）

| 属性 | 值 |
|------|-----|
| 名称 | `ci_graph_rag` |
| 变更类型 | 参数新增 |
| 向后兼容 | 是（可选参数，默认值保持现有行为） |

**新增参数**：

```json
{
  "budget": {
    "type": "integer",
    "description": "Token 预算（默认 8000）",
    "default": 8000,
    "minimum": 0
  },
  "min_relevance": {
    "type": "number",
    "description": "最低相关度阈值（默认 0.3）",
    "default": 0.3
  }
}
```

---

#### ci_federation（新增参数）

| 属性 | 值 |
|------|-----|
| 名称 | `ci_federation` |
| 变更类型 | 参数新增 |
| 向后兼容 | 是（可选参数，默认值保持现有行为） |

**新增参数**：

```json
{
  "virtual_edges": {
    "type": "boolean",
    "description": "启用虚拟边查询（默认 false）",
    "default": false
  },
  "confidence": {
    "type": "number",
    "description": "最低置信度阈值（默认 0.5）",
    "default": 0.5
  }
}
```

---

## 2. Schema 变更

### 2.1 graph.db 新增表

#### virtual_edges

```sql
CREATE TABLE virtual_edges (
    id TEXT PRIMARY KEY,
    source_repo TEXT NOT NULL,
    source_symbol TEXT NOT NULL,
    target_repo TEXT NOT NULL,
    target_symbol TEXT NOT NULL,
    edge_type TEXT NOT NULL,          -- VIRTUAL_CALLS/VIRTUAL_IMPORTS
    contract_type TEXT NOT NULL,      -- proto/openapi/graphql/typescript
    confidence REAL DEFAULT 1.0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- 索引
CREATE INDEX idx_virtual_edges_source ON virtual_edges(source_repo, source_symbol);
CREATE INDEX idx_virtual_edges_target ON virtual_edges(target_repo, target_symbol);
CREATE INDEX idx_virtual_edges_type ON virtual_edges(edge_type);
```

### 2.2 metadata 表扩展

```sql
-- 新增版本戳字段（用于索引协调）
INSERT INTO metadata (key, value) VALUES ('version_stamp', '{}');
```

---

## 3. 兼容策略

### 3.1 向后兼容性

| 变更类型 | 兼容性 | 说明 |
|---------|--------|------|
| 新增 MCP 工具（5 个） | ✅ 向后兼容 | 新增工具不影响现有工具 |
| 新增参数（ci_graph_rag） | ✅ 向后兼容 | 可选参数，默认值保持现有行为 |
| 新增参数（ci_federation） | ✅ 向后兼容 | 可选参数，默认值保持现有行为 |
| 新增 virtual_edges 表 | ✅ 向后兼容 | 新表不影响现有表 |
| 新增 metadata 字段 | ✅ 向后兼容 | 新增字段不影响现有查询 |

### 3.2 迁移策略

**无需迁移**：所有变更均为新增，现有数据和功能不受影响。

首次使用新功能时：
1. `ci_ast_delta` 会自动创建 `.devbooks/ast-cache/` 目录
2. `ci_intent` 会自动创建 `.devbooks/intent-history.json`
3. `ci_federation --virtual-edges` 会自动创建 `virtual_edges` 表

---

## 4. Contract Test IDs

| Test ID | 类型 | 覆盖场景 | 规格引用 |
|---------|------|----------|----------|
| CT-001 | schema | ci_ast_delta 输入输出 Schema | REQ-AD-001 |
| CT-002 | behavior | ci_ast_delta 性能 < 120ms | REQ-AD-004, AC-F01 |
| CT-003 | schema | ci_impact 输入输出 Schema | REQ-IA-001 |
| CT-004 | behavior | ci_impact 置信度计算 | REQ-IA-002, AC-F02 |
| CT-005 | schema | ci_cod Mermaid 语法有效 | REQ-CV-002, AC-F03 |
| CT-006 | schema | ci_cod D3.js JSON Schema | REQ-CV-003 |
| CT-007 | behavior | ci_graph_rag Token 预算控制 | REQ-SP-001, AC-F04 |
| CT-008 | schema | ci_federation virtual_edges Schema | REQ-FV-001 |
| CT-009 | behavior | ci_federation 置信度计算 | REQ-FV-002, AC-F05 |
| CT-010 | schema | ci_intent 输入输出 Schema | REQ-IL-001, AC-F06 |
| CT-011 | behavior | ci_intent 90 天清理 | REQ-IL-003, AC-F09 |
| CT-012 | schema | ci_vuln 输入输出 Schema | REQ-VT-001, AC-F07 |
| CT-013 | behavior | ci_vuln 严重性过滤 | REQ-VT-002, AC-F10 |
| CT-014 | integration | 现有测试回归 | AC-F08 |

---

## 5. 验证检查清单

- [ ] CT-001~CT-014 全部通过
- [ ] 现有测试 100% 通过（向后兼容）
- [ ] MCP 工具注册正确（server.ts）
- [ ] 功能开关正确配置（features.yaml）
- [ ] Schema 迁移脚本可用（如需要）
