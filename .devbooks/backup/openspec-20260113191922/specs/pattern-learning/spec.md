# Spec: pattern-learning

> **Version**: 1.0.0
> **Status**: Active
> **Owner**: Spec Owner
> **Created**: 2026-01-11
> **Last Verified**: 2026-01-11
> **Freshness Check**: 90 days
> **Source Change**: enhance-code-intelligence

---

## Purpose

提供语义模式学习能力，从代码历史中学习命名、结构、调用模式，在偏离高置信度模式时生成警告，辅助代码审查和一致性检查。

---

## Requirements

### Requirement: Pattern Learning and Detection

系统 SHALL 从代码库中学习语义模式，并检测偏离模式的异常。

#### Scenario: Learn naming pattern

- **GIVEN** 项目中 80% 的 handler 函数命名为 `handle<Action>`
- **WHEN** 执行模式学习
- **THEN** 学习到模式 `handler_naming: handle<Action>`
- **AND** 模式置信度 >= 0.85

Trace: AC-005

#### Scenario: Detect pattern violation

- **GIVEN** 已学习模式 `handler_naming: handle<Action>`
- **AND** 存在函数 `processOrder` 但功能为 handler
- **WHEN** 执行模式检测
- **THEN** 检测到异常 `processOrder 不符合 handler 命名模式`
- **AND** 异常置信度 >= 0.85

Trace: AC-005

#### Scenario: Ignore low confidence patterns

- **GIVEN** 某模式的置信度为 0.70（< 0.85 阈值）
- **WHEN** 执行模式检测
- **THEN** 该模式不产生警告
- **AND** 日志记录 "模式 X 置信度不足，已跳过"

Trace: AC-005

---

### Requirement: Pattern Persistence

系统 SHALL 将学习到的模式持久化到 `.devbooks/learned-patterns.json`。

#### Scenario: Persist learned patterns

- **GIVEN** 学习到 3 个有效模式
- **WHEN** 执行模式持久化
- **THEN** 生成 `.devbooks/learned-patterns.json`
- **AND** 文件包含 3 个模式定义
- **AND** 每个模式包含 `pattern_id`, `confidence`, `examples`

Trace: AC-005

#### Scenario: Load existing patterns

- **GIVEN** `.devbooks/learned-patterns.json` 已存在
- **WHEN** 启动模式学习器
- **THEN** 加载已有模式
- **AND** 新学习的模式与已有模式合并

Trace: AC-005

---

### Requirement: Confidence Threshold Configuration

系统 SHALL 支持配置置信度阈值（默认 0.85）。

#### Scenario: Custom confidence threshold

- **GIVEN** 用户设置 `--confidence-threshold 0.90`
- **AND** 某模式置信度为 0.87
- **WHEN** 执行模式检测
- **THEN** 该模式不产生警告（0.87 < 0.90）

Trace: AC-005

---

## Data Examples

### learned-patterns.json Format

```json
{
  "schema_version": "1.0.0",
  "generated_at": "2026-01-11T10:00:00Z",
  "patterns": [
    {
      "pattern_id": "PAT-001",
      "type": "naming",
      "pattern": "handle<Action>",
      "scope": "functions",
      "confidence": 0.92,
      "examples": ["handleRequest", "handleToolCall", "handleError"],
      "counter_examples": ["processOrder"]
    },
    {
      "pattern_id": "PAT-002",
      "type": "structure",
      "pattern": "scripts/*.sh sources common.sh",
      "scope": "files",
      "confidence": 0.88,
      "examples": ["embedding.sh", "bug-locator.sh"]
    }
  ]
}
```

### Pattern Types

| 模式类型 | 说明 | 示例 |
|----------|------|------|
| naming | 命名约定 | `handle<Action>`, `use<Hook>` |
| structure | 结构约定 | 所有脚本引用 common.sh |
| dependency | 依赖约定 | controller → service → repository |
| error | 错误处理约定 | 所有 async 函数有 try-catch |
