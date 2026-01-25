# Spec Delta: structured-context-output

> **Change ID**: 20260123-1206-add-auto-tool-orchestrator  
> **Capability**: structured-context-output  
> **Type**: CHANGED  
> **Owner**: Spec Owner  
> **Created**: 2026-01-24  
> truth-root = `dev-playbooks/specs`  
> change-root = `dev-playbooks/changes`

---

## 变更动机

真理目录中的 `structured-context-output` 当前将 Hook/CLI 的“结构化上下文”定义为 5 层顶层 JSON 字段（`project_profile/current_state/task_context/recommended_tools/constraints`）。本变更引入“自动工具编排 + 结果融合”的编排内核输出契约（Tool Plan/Results/Fused Context），需要对结构化输出的“顶层 envelope”做版本化演进，同时保留可迁移路径与回滚机制。

---

## MODIFIED Requirements

### Requirement: REQ-SCO-001（v2）：结构化输出必须支持“编排 envelope + 结构化 payload”

系统 SHALL 输出包含编排 envelope 的结构化 JSON（schema v1.0），并在以下位置提供结构化 payload：
- `fused_context.for_model.structured`：结构化对象（用于模型消费与可追溯）
- `fused_context.for_model.additional_context`：字符串（用于注入）

说明：5 层结构化字段（`project_profile/current_state/task_context/recommended_tools/constraints`）在本变更后属于“payload”范畴，可作为 `fused_context.for_model.structured` 的内容（字段名保持不变），而不再强制要求作为顶层字段出现。

Trace: AC-001, AC-014

#### Scenario: SC-SCO-001（v2）：结构化输出 envelope 存在且 payload 可用

- **GIVEN** 用户在代码项目中触发结构化输出
- **WHEN** 入口层以 JSON 输出模式运行
- **THEN** 输出包含 `schema_version/tool_plan/tool_results/fused_context/degraded`
- **AND** `fused_context.for_model.structured` 为 object

Trace: AC-001, AC-014

---

## 兼容与迁移策略

- 迁移期回退：当 `CI_AUTO_TOOLS_LEGACY=1` 时，允许输出 legacy 结构（5 层顶层字段）以兼容旧消费者；该行为必须可审计（AC-018）。
- 向前兼容：schema v1.0 的新增字段只允许“可选新增/扩大枚举”，不得改变既有字段语义（AC-014）。
