# Spec Delta: auto-tool-orchestrator

> **Change ID**: 20260123-1206-add-auto-tool-orchestrator  
> **Capability**: auto-tool-orchestrator  
> **Type**: ADDED  
> **Owner**: Spec Owner  
> **Created**: 2026-01-24  
> truth-root = `dev-playbooks/specs`  
> change-root = `dev-playbooks/changes`

---

## 冲突检测（Spec 真理冲突）

- 已在 `dev-playbooks/specs` 内对 `auto-tool`/`orchestrator`/`tool_plan`/`tool_results`/`fused_context` 关键词做全局检索：未发现同名能力规格；但发现 `structured-context-output` 规格将 Hook 输出定义为“5 层 JSON”，本变更将与其产生契约演进关系（见本包 `specs/structured-context-output/spec.md`）。

---

## ADDED Requirements

### Requirement: REQ-ATO-001：编排内核必须输出稳定 JSON schema（v1.0）并包含最小字段集

系统 SHALL 输出稳定 JSON，且最小字段集必须包含：
- `schema_version`（SemVer 字符串，默认 `1.0`）
- `run_id`（可重复/可审计；plan/dry-run 下必须稳定）
- `tool_plan`（含 `tier_max`、`budget`、`tools[]`、plan/dry-run 下的 `planned_codex_command`）
- `tool_results[]`（含 `tool/status/duration_ms/summary/truncated/error.code`）
- `fused_context.for_model.additional_context`（注入字符串，允许为空）
- `fused_context.for_user.limits_text`（以 `[Limits]` 开头的可读说明，允许为空但字段必须存在）
- `degraded`（含 `is_degraded/reason/degraded_to`）

Trace: AC-001, AC-014

#### Scenario: SC-ATO-001：基本输出包含关键字段

- **GIVEN** 输入 prompt 为任意代码相关问题
- **WHEN** 入口层以 JSON 输出模式运行
- **THEN** 输出为合法 JSON object
- **AND** 至少包含 `schema_version/run_id/tool_plan/tool_results/fused_context/degraded`

Trace: AC-001, AC-014

---

### Requirement: REQ-ATO-002：控制面优先级 env > config > default，且 Tier-2 仅允许 env 启用

- 系统 SHALL 按优先级解析开关与预算：env > `config/auto-tools.yaml` > default。
- 系统 SHALL 强制 Tier-2 默认禁用：默认 `CI_AUTO_TOOLS_TIER_MAX=1`。
- 即使 `config/auto-tools.yaml` 中出现任何等价于 “tier_max >= 2” 的配置，系统 MUST 忽略并在 `[Limits]` 明示：`[Limits] tier-2 requires CI_AUTO_TOOLS_TIER_MAX=2 (config ignored)`。

Trace: AC-004, AC-009

#### Scenario: SC-ATO-002：Tier-2 配置绕过被忽略

- **GIVEN** `config/auto-tools.yaml` 声明 `tier_max: 2`（或同义字段）
- **AND** 未设置 `CI_AUTO_TOOLS_TIER_MAX=2`
- **WHEN** 运行编排（plan 或 run）
- **THEN** `tool_plan.tier_max` MUST 为 `1`
- **AND** `fused_context.for_user.limits_text` MUST 包含 `tier-2 requires CI_AUTO_TOOLS_TIER_MAX=2 (config ignored)`

Trace: AC-009

---

### Requirement: REQ-ATO-003：plan/dry-run 必须确定性且不得调用外部 codex 子进程

- 当 `CI_AUTO_TOOLS_MODE=plan` 或 `CI_AUTO_TOOLS_DRY_RUN=1` 时：
  - 系统 SHALL 仅输出计划与 [Limits]，不得执行任何工具调用或外部 codex 子进程。
  - 输出 MUST 包含 `tool_plan.planned_codex_command`，且该字段必须可通过 env（`CI_CODEX_SESSION_MODE`）确定性控制。

Trace: AC-002, AC-003

#### Scenario: SC-ATO-003：plan 模式 planned_codex_command 可控

- **GIVEN** `CI_AUTO_TOOLS_MODE=plan`
- **WHEN** 设置 `CI_CODEX_SESSION_MODE=resume_last`
- **THEN** `tool_plan.planned_codex_command` MUST 为 `codex exec resume --last`
- **WHEN** 设置 `CI_CODEX_SESSION_MODE=exec`
- **THEN** `tool_plan.planned_codex_command` MUST 为 `codex exec`

Trace: AC-002, AC-003

---

### Requirement: REQ-ATO-004：白名单/参数裁剪/路径过滤/脱敏必须默认生效且可解释

系统 SHALL 默认启用以下安全策略，并将裁剪/拒绝原因写入 [Limits]：
- 工具白名单（未在白名单 → skipped）
- 参数裁剪（如 `ci_graph_rag.depth` 超上限 → clamp，并输出 `depth clamped to 2`）
- 路径过滤（禁止 repo-root 外读取、禁止 `..` 逃逸、屏蔽敏感模式如 `.env`/`id_rsa*`）
- 输出脱敏（Bearer/Private Key/AKIA 等）

Trace: AC-006

#### Scenario: SC-ATO-004：超限参数被裁剪且 [Limits] 可见

- **GIVEN** 计划包含 `ci_graph_rag.depth=10`
- **WHEN** 编排生成最终 args
- **THEN** depth MUST 被裁剪为 `2`
- **AND** [Limits] MUST 包含 `depth clamped to 2`

Trace: AC-006

---

### Requirement: REQ-ATO-005：预算/并发/回填限额必须为明确数字且默认可用

- 系统 SHALL 提供明确的 `budget.wall_ms/max_concurrency/max_injected_chars` 默认值。
- 当结果/回填超出预算或上限时，系统 MUST 标记 `truncated=true` 并在 [Limits] 明示。

Trace: AC-007

#### Scenario: SC-ATO-005：结果截断标记可测

- **GIVEN** 工具结果或融合文本超出 `max_injected_chars`
- **WHEN** 生成最终输出
- **THEN** `tool_results[].truncated` 或等价字段 MUST 为 true
- **AND** [Limits] MUST 包含截断说明

Trace: AC-007

---

### Requirement: REQ-ATO-006：fail-open 与降级可见，且编排不可用时输出空注入 JSON（exit=10）

- 任何单工具超时/失败 SHALL 不阻塞输出（fail-open），但 MUST 将降级原因写入 `degraded` 与 [Limits]。
- 当编排不可用（脚本缺失/不可执行）或输出不可解析时，入口层 MUST 输出“空注入 JSON”并以 exit code `10` 退出。

Trace: AC-008, AC-012

#### Scenario: SC-ATO-006：编排不可用空注入兜底

- **GIVEN** 编排脚本不可执行
- **WHEN** 入口层运行
- **THEN** stdout MUST 为合法 JSON
- **AND** `fused_context.for_model.additional_context` MUST 为空
- **AND** [Limits] MUST 说明 `orchestrator unavailable`（或等价原因）
- **AND** exit code MUST 为 `10`

Trace: AC-008, AC-012

---

### Requirement: REQ-ATO-007：入口层互斥与唯一执行点必须可验证

- 入口层脚本不得包含任何 `ci_` 可执行调用，也不得直连底层工具脚本；唯一执行点为编排内核。
- 兼容包装 `hooks/augment-context-global.sh` 必须保持等价转发到 `hooks/context-inject-global.sh`。

Trace: AC-013, AC-016

#### Scenario: SC-ATO-007：静态扫描验证入口层无直连

- **GIVEN** bats 静态扫描入口层脚本
- **THEN** 不得出现任何 `ci_` 工具调用模式
- **AND** 不得出现对底层脚本（`scripts/*.sh`）的直接执行

Trace: AC-006, AC-016

---

### Requirement: REQ-ATO-008：MVP（CI_AUTO_TOOLS=auto）行为边界必须自洽且可测

- `CI_AUTO_TOOLS=auto` 且 Tier-2 默认禁用时：
  - 非代码意图 MUST 输出空注入（避免噪音）。
  - Tier-0/1 代码意图 MUST 进入计划并输出 [Auto Tools]/[Limits]。
  - 需要 Tier-2 的意图 MUST 不进入 Tier-2，并输出固定 [Limits] 提示：`[Limits] tier-2 disabled by default; set CI_AUTO_TOOLS_TIER_MAX=2 to enable`。

Trace: AC-017

#### Scenario: SC-ATO-008：Tier-2 需求仅提示不自动进入

- **GIVEN** 输入触发 Tier-2 判定
- **AND** `CI_AUTO_TOOLS=auto` 且 `CI_AUTO_TOOLS_TIER_MAX=1`
- **WHEN** 运行编排
- **THEN** `tool_plan.tier_max` MUST 为 1
- **AND** [Limits] MUST 包含 `tier-2 disabled by default; set CI_AUTO_TOOLS_TIER_MAX=2 to enable`

Trace: AC-009, AC-017

---

### Requirement: REQ-ATO-009：迁移期 legacy 回退可审计

- 当 `CI_AUTO_TOOLS_LEGACY=1` 时：
  - 输出 MUST 包含 `[Limits] legacy mode enabled; using legacy policy`。
  - 结构化输出必须标记 `enforcement.source="legacy"`（或等价字段）。

Trace: AC-018

#### Scenario: SC-ATO-009：legacy 模式可识别

- **GIVEN** `CI_AUTO_TOOLS_LEGACY=1`
- **WHEN** 运行入口层输出
- **THEN** [Limits] MUST 包含 `legacy mode enabled; using legacy policy`
- **AND** 输出包含 `enforcement.source="legacy"`（或等价字段）

Trace: AC-018

---

## Contract（输出契约与兼容策略）

> 本 Contract 以 `proposal.md` 的 “编排内核 I/O 契约 + 错误码/退出码契约 + [Limits] 文案锚点” 为权威来源；本文件仅固定“最小可执行校验锚点”。

### 1) Schema 版本化

- `schema_version` MUST 为 `MAJOR.MINOR`（例如 `1.0`）。
- 兼容规则：
  - MAJOR 变化 = breaking；bats/消费者必须显式适配。
  - MINOR 只能新增可选字段或扩大枚举，不得改变既有字段语义。

### 2) [Limits] 文案锚点（强制）

输出中的 `fused_context.for_user.limits_text`（或等价字段）MUST 以 `[Limits]` 开头，并覆盖以下固定文案锚点（按需出现）：
- Tier-2 默认关闭：`[Limits] tier-2 disabled by default; set CI_AUTO_TOOLS_TIER_MAX=2 to enable`
- 配置绕过被忽略：`[Limits] tier-2 requires CI_AUTO_TOOLS_TIER_MAX=2 (config ignored)`
- 会话降级：`[Limits] session continuity unavailable; fallback to stateless exec`
- 入口层绕过拒绝：`[Limits] tool invocation must go through orchestrator`
- 超时/预算：`[Limits] tool timeout; degraded to plan-only` / `[Limits] budget exceeded; results truncated`
- 解析失败：`[Limits] orchestrator output invalid; fallback to empty context`

### 3) 错误码/退出码

- `tool_results.error.code` 枚举与入口层退出码必须与 `proposal.md` 的“设计要点 7.1”一致（AC-012）。

