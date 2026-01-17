# 规格：动态模式发现（pattern-discovery）

> **Change ID**: `augment-parity`
> **Capability**: pattern-discovery
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-15

---

## Requirements（需求）

### REQ-PD-001：自动模式发现

系统应支持自动发现代码库中的高频模式：

```bash
pattern-learner.sh learn --auto-discover [--min-frequency <N>] [--format <json|text>]
```

**参数**：
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--auto-discover` | - | 启用自动发现模式 |
| `--min-frequency` | 3 | 高频模式阈值 |
| `--format` | text | 输出格式 |

### REQ-PD-002：功能开关

动态模式发现应通过功能开关控制：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `features.pattern_discovery.enabled` | `true` | 是否启用 |
| `features.pattern_discovery.min_frequency` | `3` | 最小频率阈值 |

### REQ-PD-003：模式类型检测

系统应检测以下类型的模式：

| 模式类型 | 说明 | 检测方法 |
|----------|------|----------|
| 命名约定 | 变量/函数命名模式 | 正则统计 |
| 调用序列 | 常见函数调用顺序 | 调用图分析 |
| 结构模式 | 类/模块结构相似性 | AST 统计 |
| 导入模式 | 常见导入组合 | 导入图分析 |
| 错误处理 | try-catch 模式 | AST 统计 |

### REQ-PD-004：高频模式判定

模式被判定为"高频"的条件：

- 出现频率 >= `min_frequency`（默认 3 次）
- 在不同文件中出现
- 不是偶然相似

### REQ-PD-005：模式持久化

发现的模式应持久化到：

- 文件路径：`.devbooks/learned-patterns.json`
- 格式：JSON
- 支持增量更新

### REQ-PD-006：模式输出格式

发现的模式应包含以下信息：

```json
{
  "patterns": [
    {
      "id": "pat-001",
      "type": "naming",
      "description": "Handler functions end with 'Handler'",
      "frequency": 5,
      "confidence": 0.85,
      "examples": [
        "src/handlers/authHandler.ts:10",
        "src/handlers/userHandler.ts:15"
      ],
      "regex": "\\w+Handler$"
    }
  ],
  "metadata": {
    "discovered_at": "2026-01-15T10:00:00Z",
    "source_files": 25,
    "total_patterns": 5
  }
}
```

### REQ-PD-007：与现有模式合并

新发现的模式应与现有预定义模式合并：

- 不覆盖预定义模式
- 避免重复模式
- 更新频率统计

---

## Scenarios（场景）

### SC-PD-001：发现命名模式

**Given**:
- 代码库中有 5 个以 `Handler` 结尾的函数
- `min_frequency = 3`
**When**: 执行 `pattern-learner.sh learn --auto-discover`
**Then**:
- 发现命名模式：`*Handler`
- 频率 = 5
- 输出模式详情和示例

### SC-PD-002：发现调用序列模式

**Given**:
- 多处代码先调用 `validate()`，再调用 `process()`，最后调用 `save()`
- 该序列出现 4 次
**When**: 执行自动发现
**Then**:
- 发现调用序列模式：`validate → process → save`
- 频率 = 4
- 标记为"常见工作流"

### SC-PD-003：低于阈值不报告

**Given**:
- 某模式仅出现 2 次
- `min_frequency = 3`
**When**: 执行自动发现
**Then**:
- 不报告该模式
- 仅报告频率 >= 3 的模式

### SC-PD-004：自定义阈值

**Given**: 需要更严格的模式发现
**When**: 执行 `pattern-learner.sh learn --auto-discover --min-frequency 5`
**Then**:
- 仅报告频率 >= 5 的模式
- 结果更精确但数量更少

### SC-PD-005：JSON 格式输出

**Given**: 发现 3 种高频模式
**When**: 执行 `pattern-learner.sh learn --auto-discover --format json`
**Then**:
- 输出 JSON 格式结果
- 包含 patterns 数组和 metadata
- 可被程序解析

### SC-PD-006：模式持久化

**Given**: 发现新模式
**When**: 执行自动发现
**Then**:
- 模式写入 `.devbooks/learned-patterns.json`
- 保留已有模式
- 新模式追加到列表

### SC-PD-007：与预定义模式合并

**Given**:
- 已有预定义模式：错误处理模式
- 自动发现了相同的模式
**When**: 合并模式
**Then**:
- 不重复添加
- 更新频率统计
- 保留预定义模式的 ID

### SC-PD-008：至少发现 3 种模式

**Given**:
- 代码库规模适中（~200 个符号）
- 存在多种编码模式
**When**: 执行 `pattern-learner.sh learn --auto-discover`
**Then**:
- 至少发现 3 种高频模式
- 输出模式总数 >= 3

### SC-PD-009：功能禁用时跳过

**Given**: `features.pattern_discovery.enabled = false`
**When**: 执行自动发现
**Then**:
- 输出：`Pattern discovery is disabled`
- 跳过发现过程
- 退出码 0

### SC-PD-010：空代码库处理

**Given**: 图数据库为空或节点数 < 10
**When**: 执行自动发现
**Then**:
- 输出：`Insufficient data for pattern discovery (need >= 10 nodes)`
- 不报告任何模式
- 退出码 0

### SC-PD-011：置信度评估

**Given**: 发现某命名模式
**When**: 计算置信度
**Then**:
- 置信度 = 匹配数 / (匹配数 + 例外数)
- 高置信度模式（> 0.8）优先展示
- 低置信度模式标记为"需审核"

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-PD-001 | SC-PD-001, SC-PD-002, SC-PD-004 | AC-006 |
| REQ-PD-002 | SC-PD-009 | AC-006 |
| REQ-PD-003 | SC-PD-001, SC-PD-002 | AC-006 |
| REQ-PD-004 | SC-PD-003, SC-PD-008 | AC-006 |
| REQ-PD-005 | SC-PD-006 | AC-006 |
| REQ-PD-006 | SC-PD-005 | AC-006 |
| REQ-PD-007 | SC-PD-007 | AC-006 |
