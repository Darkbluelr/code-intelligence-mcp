---
last_referenced_by: 20260123-1206-add-auto-tool-orchestrator
last_verified: 2026-01-24
health: active
---

# Spec: 结构化上下文输出（structured-context-output）

> **Change ID**: `20260123-1206-add-auto-tool-orchestrator`
> **Capability**: structured-context-output
> **Version**: 2.0.0
> **Status**: Active
> **Created**: 2026-01-16
> **Updated**: 2026-01-24

---

## 概述

本规格定义“结构化上下文输出”的对外契约：系统必须输出可被工具链与模型共同消费的结构化 payload，并在 JSON 模式下提供可版本化的编排 envelope（用于工具计划/执行结果/降级信息的审计与回填）。

---

## Requirements（需求）

### REQ-SCO-001（v2）：JSON 输出必须支持“编排 envelope + 结构化 payload”

当入口脚本以 JSON 形式输出结构化上下文时，系统 MUST 输出包含编排 envelope 的 JSON（schema v1.0），并在以下位置提供结构化 payload：

- `fused_context.for_model.structured`：结构化对象（用于模型消费与可追溯）
- `fused_context.for_model.additional_context`：字符串（用于注入）

为兼容旧消费者，系统 SHOULD 同时提供 5 层字段作为顶层兼容字段：
`project_profile/current_state/task_context/recommended_tools/constraints`。

一致性约束：
- 若顶层 5 层字段存在，则它们 MUST 与 `fused_context.for_model.structured` 中的对应字段语义等价。

#### Scenario: SC-SCO-001（v2）：结构化输出 envelope 存在且 payload 可用

- **GIVEN** 用户在代码项目中触发结构化输出
- **WHEN** 入口层以 JSON 输出模式运行
- **THEN** 输出包含 `schema_version/run_id/tool_plan/tool_results/fused_context/degraded/enforcement`
- **AND** `fused_context.for_model.structured` 为 object

---

### REQ-SCO-002：5 层结构化 payload 字段定义

系统 MUST 提供 5 层结构化上下文 payload：

| 层级 | 字段名 | 内容 |
|------|--------|------|
| 1 | `project_profile` | 项目画像（名称/类型/技术栈/架构模式/关键约束） |
| 2 | `current_state` | 当前状态（索引状态/热点文件/最近提交） |
| 3 | `task_context` | 任务上下文（意图分析/相关代码片段/调用链） |
| 4 | `recommended_tools` | 推荐工具（基于意图的工具推荐和参数建议） |
| 5 | `constraints` | 约束提醒（架构约束/安全约束） |

#### Scenario: SC-SCO-002：5 层字段存在

- **GIVEN** 任意有效输入触发结构化输出
- **WHEN** 入口层以 JSON 输出模式运行
- **THEN** 输出（顶层或 payload）包含上述 5 个字段名

---

## 兼容与迁移策略

- 迁移期回退：当 `CI_AUTO_TOOLS_LEGACY=1` 时，允许输出 legacy 策略（例如更偏向旧消费者的字段/文案）；该行为必须可审计（例如 `enforcement.source="legacy"` 且 `[Limits]` 含固定提示）。
- 向前兼容：`schema_version` 采用 SemVer 的 `MAJOR.MINOR`。MINOR 只能新增可选字段/扩大枚举，不得改变既有字段语义；MAJOR 变化表示 breaking。
