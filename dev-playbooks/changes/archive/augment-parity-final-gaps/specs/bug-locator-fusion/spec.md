# Spec Delta: Bug 定位 + 影响分析融合（bug-locator-fusion）

> **Change ID**: `augment-parity-final-gaps`
> **Capability**: bug-locator-fusion
> **Base Spec**: `dev-playbooks/specs/hotspot-analysis/spec.md`（部分关联）
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-16

---

## 概述

本规格定义 Bug 定位与影响分析融合功能。系统应能够：
1. 在 Bug 定位结果中集成传递性影响范围
2. 重新计算综合分数（加入影响范围权重）
3. 保持向后兼容（不带参数时保持原有行为）

---

## Requirements（需求）

### REQ-BLF-001：影响分析集成

系统应支持在 Bug 定位输出中集成影响分析结果：

**触发参数**：
- `--with-impact`：启用影响分析集成
- `--impact-depth <n>`：影响分析深度（默认 3）

**约束**：
- 不带 `--with-impact` 时保持原有输出格式
- 影响分析调用 `impact-analyzer.sh`

### REQ-BLF-002：融合输出格式

带影响分析的 Bug 定位输出格式：

> **设计回写**（2026-01-16）：为保持向后兼容（REQ-BLF-006），实现保持对象包装格式 `{schema_version, candidates:[...]}`，而非纯数组。此格式与 `--error` 入口的既有输出一致。

```json
{
  "schema_version": "1.0",
  "candidates": [
    {
      "symbol": "src/server.ts::handleRequest",
      "file": "src/server.ts",
      "line": 150,
      "score": 85.5,
      "original_score": 78.2,
      "scoring_factors": {
        "hotspot": 0.3,
        "complexity": 0.2,
        "recency": 0.25,
        "relevance": 0.25
      },
      "impact": {
        "total_affected": 12,
        "affected_files": [
          "src/handlers/auth.ts",
          "src/handlers/user.ts",
          "tests/server.test.ts"
        ],
        "max_depth": 3,
        "impact_score": 0.15
      }
    }
  ]
}
```

### REQ-BLF-003：综合分数计算

系统应重新计算综合分数，加入影响范围权重：

**计算公式**：
```
final_score = original_score * (1 + impact_weight * normalized_impact)
```

其中：
- `original_score`：原始四维评分
- `impact_weight`：影响范围权重（默认 0.2）
- `normalized_impact`：归一化影响范围（`total_affected / 100`，上限 1.0）

### REQ-BLF-004：影响范围获取

系统应从 `impact-analyzer.sh` 获取影响范围：

```bash
./scripts/impact-analyzer.sh analyze "$symbol" --depth "$impact_depth" --format json
```

**返回字段**：
| 字段 | 类型 | 说明 |
|------|------|------|
| `total_affected` | number | 受影响节点总数 |
| `affected_files` | string[] | 受影响文件列表 |
| `max_depth` | number | 实际分析深度 |

### REQ-BLF-005：性能优化

影响分析应优化性能：

| 场景 | 优化策略 |
|------|----------|
| 候选数量 > 10 | 只对 Top 10 执行影响分析 |
| 影响分析超时 | 单个分析超时 5 秒，跳过并标记 |
| 缓存命中 | 复用 LRU 缓存中的子图数据 |

### REQ-BLF-006：向后兼容

不带 `--with-impact` 时，输出保持原有对象包装格式：

```json
{
  "schema_version": "1.0",
  "candidates": [
    {
      "symbol": "src/server.ts::handleRequest",
      "file": "src/server.ts",
      "line": 150,
      "score": 78.2,
      "scoring_factors": {
        "hotspot": 0.3,
        "complexity": 0.2,
        "recency": 0.25,
        "relevance": 0.25
      }
    }
  ]
}
```

---

## Scenarios（场景）

### SC-BLF-001：带影响分析的 Bug 定位

**Given**:
- Bug 描述：`authentication error in login flow`
- `--with-impact` 参数启用
**When**: 执行 `bug-locator.sh locate "authentication error" --with-impact`
**Then**:
- 输出 JSON 包含 `impact` 字段
- `impact.total_affected` > 0
- `impact.affected_files` 为数组
- `score` 为重新计算的综合分数

### SC-BLF-002：影响范围加权计算

**Given**:
- 候选符号 A 原始分数 80，影响范围 20 个节点
- 候选符号 B 原始分数 85，影响范围 5 个节点
**When**: 计算综合分数（impact_weight = 0.2）
**Then**:
- A 综合分数 = 80 * (1 + 0.2 * 0.2) = 83.2
- B 综合分数 = 85 * (1 + 0.2 * 0.05) = 85.85
- B 排名仍高于 A（影响范围不足以逆转）

### SC-BLF-003：高影响范围提升排名

**Given**:
- 候选符号 A 原始分数 75，影响范围 50 个节点
- 候选符号 B 原始分数 78，影响范围 3 个节点
**When**: 计算综合分数（impact_weight = 0.2）
**Then**:
- A 综合分数 = 75 * (1 + 0.2 * 0.5) = 82.5
- B 综合分数 = 78 * (1 + 0.2 * 0.03) = 78.47
- A 排名上升超过 B

### SC-BLF-004：向后兼容（无 --with-impact）

**Given**:
- 现有脚本调用 `bug-locator.sh locate "error"`
- 不带 `--with-impact` 参数
**When**: 执行 Bug 定位
**Then**:
- 输出 JSON 不包含 `impact` 字段
- `score` 为原始四维评分
- 输出格式与之前版本完全一致

### SC-BLF-005：影响分析深度控制

**Given**:
- `--impact-depth 5` 参数
**When**: 执行影响分析
**Then**:
- 影响分析深度为 5
- `impact.max_depth` = 5

### SC-BLF-006：影响分析超时

**Given**:
- 候选符号 A 的影响分析需要 10 秒（超时）
**When**: 执行带影响分析的 Bug 定位
**Then**:
- 符号 A 的影响分析跳过
- 符号 A 的 `impact` 字段为 `null` 或不存在
- 记录警告日志
- 其他候选正常处理

### SC-BLF-007：候选数量限制

**Given**:
- Bug 定位返回 20 个候选
- `--with-impact` 启用
**When**: 执行影响分析
**Then**:
- 只对 Top 10 执行影响分析
- 剩余 10 个候选无 `impact` 字段
- 日志记录：`影响分析限制为 Top 10 候选`

### SC-BLF-008：输出 Schema 验证

**Given**:
- 带影响分析的 Bug 定位输出
**When**: 验证输出 Schema
**Then**:
- `symbol` 为必填字符串
- `score` 为必填数值（0-100）
- `impact` 为可选对象
- `impact.total_affected` 为整数
- `impact.affected_files` 为字符串数组

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-BLF-001 | SC-BLF-001 | AC-G08 |
| REQ-BLF-002 | SC-BLF-001, SC-BLF-008 | AC-G08 |
| REQ-BLF-003 | SC-BLF-002, SC-BLF-003 | AC-G08 |
| REQ-BLF-004 | SC-BLF-001, SC-BLF-005 | AC-G08 |
| REQ-BLF-005 | SC-BLF-006, SC-BLF-007 | AC-G08 |
| REQ-BLF-006 | SC-BLF-004 | AC-G08 |

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-BLF-001 | behavior | REQ-BLF-001, SC-BLF-001 | 带影响分析的 Bug 定位 |
| CT-BLF-002 | behavior | REQ-BLF-003, SC-BLF-002, SC-BLF-003 | 综合分数计算 |
| CT-BLF-003 | behavior | REQ-BLF-006, SC-BLF-004 | 向后兼容 |
| CT-BLF-004 | behavior | REQ-BLF-005, SC-BLF-006 | 超时处理 |
| CT-BLF-005 | behavior | REQ-BLF-005, SC-BLF-007 | 候选数量限制 |
| CT-BLF-006 | schema | REQ-BLF-002, SC-BLF-008 | 输出 Schema |

---

## JSON Schema

> **设计回写**（2026-01-16）：Schema 更新为对象包装格式，与实现保持一致。

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["schema_version", "candidates"],
  "properties": {
    "schema_version": { "type": "string" },
    "candidates": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["symbol", "file", "line", "score"],
        "properties": {
          "symbol": { "type": "string" },
          "file": { "type": "string" },
          "line": { "type": "integer", "minimum": 1 },
          "score": { "type": "number", "minimum": 0, "maximum": 100 },
          "original_score": { "type": "number", "minimum": 0, "maximum": 100 },
          "scoring_factors": {
            "type": "object",
            "properties": {
              "hotspot": { "type": "number" },
              "complexity": { "type": "number" },
              "recency": { "type": "number" },
              "relevance": { "type": "number" }
            }
          },
          "impact": {
            "type": ["object", "null"],
            "properties": {
              "total_affected": { "type": "integer", "minimum": 0 },
              "affected_files": {
                "type": "array",
                "items": { "type": "string" }
              },
              "max_depth": { "type": "integer", "minimum": 1 },
              "impact_score": { "type": "number", "minimum": 0, "maximum": 1 }
            },
            "required": ["total_affected", "affected_files"]
          }
        }
      }
    }
  }
}
```

---

## 命令行接口（CLI）

```bash
bug-locator.sh locate <description> [options]
```

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--with-impact` | flag | 否 | 启用影响分析集成 |
| `--impact-depth` | number | 3 | 影响分析深度 |
| `--impact-weight` | number | 0.2 | 影响范围权重 |
| `--impact-timeout` | number | 5 | 单个影响分析超时（秒） |
| `--format` | string | json | 输出格式（json/text） |

---

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `BUG_LOCATOR_IMPACT_WEIGHT` | 0.2 | 影响范围权重 |
| `BUG_LOCATOR_IMPACT_TIMEOUT` | 5 | 影响分析超时秒数 |
| `BUG_LOCATOR_IMPACT_TOP_N` | 10 | 影响分析候选数限制 |
