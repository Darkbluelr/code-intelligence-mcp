---
last_referenced_by: 20260123-1206-add-auto-tool-orchestrator
last_verified: 2026-01-24
health: active
---

# Spec: 自动工具编排器（auto-tool-orchestrator）

> **Change ID**: `20260123-1206-add-auto-tool-orchestrator`
> **Capability**: auto-tool-orchestrator
> **Version**: 1.0.0
> **Status**: Active
> **Created**: 2026-01-24

---

## Requirements（需求）

### REQ-ATO-001：编排内核必须输出稳定 JSON schema（v1.0）并包含最小字段集

系统 MUST 输出稳定 JSON，且最小字段集必须包含：
- `schema_version`（SemVer 字符串，默认 `1.0`）
- `run_id`（可重复/可审计；plan/dry-run 下必须稳定）
- `tool_plan`（含 `tier_max`、`budget`、`tools[]`、plan/dry-run 下的 `planned_codex_command`）
- `tool_results[]`（含 `tool/status/duration_ms/summary/truncated/error.code`）
- `fused_context.for_model.additional_context`（注入字符串，允许为空）
- `fused_context.for_user.limits_text`（以 `[Limits]` 开头的可读说明，允许为空但字段必须存在）
- `degraded`（含 `is_degraded/reason/degraded_to`）

#### Scenario: SC-ATO-001：基本输出包含关键字段

- **GIVEN** 输入 prompt 为任意代码相关问题
- **WHEN** 入口层以 JSON 输出模式运行
- **THEN** 输出为合法 JSON object
- **AND** 至少包含 `schema_version/run_id/tool_plan/tool_results/fused_context/degraded`

---

### REQ-ATO-002：控制面优先级 env > config > default，且 Tier-2 仅允许 env 启用

- 系统 MUST 按优先级解析开关与预算：env > `config/auto-tools.yaml` > default。
- 系统 MUST 强制 Tier-2 默认禁用：默认 `CI_AUTO_TOOLS_TIER_MAX=1`。
- 即使 `config/auto-tools.yaml` 中出现任何等价于 “tier_max >= 2” 的配置，系统 MUST 忽略并在 `[Limits]` 明示：`[Limits] tier-2 requires CI_AUTO_TOOLS_TIER_MAX=2 (config ignored)`。

#### Scenario: SC-ATO-002：Tier-2 配置绕过被忽略

- **GIVEN** `config/auto-tools.yaml` 声明 `tier_max: 2`（或同义字段）
- **AND** 未设置 `CI_AUTO_TOOLS_TIER_MAX=2`
- **WHEN** 运行编排（plan 或 run）
- **THEN** `tool_plan.tier_max` MUST 为 `1`
- **AND** `[Limits]` MUST 包含 `tier-2 requires CI_AUTO_TOOLS_TIER_MAX=2 (config ignored)`

---

### REQ-ATO-003：plan/dry-run 必须确定性且不得调用外部 codex 子进程

当 `CI_AUTO_TOOLS_MODE=plan` 或 `CI_AUTO_TOOLS_DRY_RUN=1` 时：
- 系统 MUST 仅输出计划与 [Limits]，不得执行任何工具调用或外部 codex 子进程。
- 输出 MUST 包含 `tool_plan.planned_codex_command`，且该字段必须可通过 env（`CI_CODEX_SESSION_MODE`）确定性控制。

#### Scenario: SC-ATO-003：plan 模式 planned_codex_command 可控

- **GIVEN** `CI_AUTO_TOOLS_MODE=plan`
- **WHEN** 设置 `CI_CODEX_SESSION_MODE=resume_last`
- **THEN** `tool_plan.planned_codex_command` MUST 为 `codex exec resume --last`
- **WHEN** 设置 `CI_CODEX_SESSION_MODE=exec`
- **THEN** `tool_plan.planned_codex_command` MUST 为 `codex exec`

---

### REQ-ATO-006：fail-open 与降级可见，且编排不可用时输出空注入 JSON（exit=10）

- 任何单工具超时/失败 MUST 不阻塞输出（fail-open），但 MUST 将降级原因写入 `degraded` 与 [Limits]。
- 当编排不可用（脚本缺失/不可执行）或输出不可解析时，入口层 MUST 输出“空注入 JSON”并以 exit code `10` 或 `30` 退出（分别表示不可用/解析失败）。

#### Scenario: SC-ATO-006：编排不可用空注入兜底

- **GIVEN** 编排脚本不可执行
- **WHEN** 入口层运行
- **THEN** stdout MUST 为合法 JSON
- **AND** `fused_context.for_model.additional_context` MUST 为空
- **AND** [Limits] MUST 说明 `orchestrator unavailable`（或等价原因）
- **AND** exit code MUST 为 `10`

---

### REQ-ATO-007：入口层互斥与唯一执行点必须可验证

- 入口层脚本不得包含任何工具直连；唯一执行点为编排内核。
- 兼容包装 `hooks/augment-context-global.sh` MUST 保持等价转发到 `hooks/context-inject-global.sh`。

#### Scenario: SC-ATO-007：静态扫描验证入口层无直连

- **GIVEN** 静态扫描入口层脚本
- **THEN** 不得出现任何工具直连模式

---

### REQ-ATO-009：迁移期 legacy 回退可审计

- 当 `CI_AUTO_TOOLS_LEGACY=1` 时：
  - 输出 MUST 包含 `[Limits] legacy mode enabled; using legacy policy`。
  - 输出 MUST 标记 `enforcement.source="legacy"`（或等价字段）。

#### Scenario: SC-ATO-009：legacy 模式可识别

- **GIVEN** `CI_AUTO_TOOLS_LEGACY=1`
- **WHEN** 运行入口层输出
- **THEN** [Limits] MUST 包含 `legacy mode enabled; using legacy policy`
- **AND** 输出包含 `enforcement.source="legacy"`（或等价字段）
