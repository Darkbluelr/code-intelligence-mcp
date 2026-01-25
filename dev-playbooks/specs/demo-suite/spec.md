---
last_referenced_by: 20260123-0702-improve-demo-suite-ab-metrics
last_verified: 2026-01-24
health: active
---

# Spec Delta: demo-suite

> **Change ID**: 20260123-0702-improve-demo-suite-ab-metrics  
> **Capability**: demo-suite  
> **Type**: ADDED  
> **Owner**: Spec Owner  
> **Created**: 2026-01-23  
> truth-root = `dev-playbooks/specs`  
> change-root = `dev-playbooks/changes`

---

## 冲突检测（Spec 真理冲突）

- 已在 `dev-playbooks/specs` 内对 `demo-suite`/`metrics.json`/`compare.json`/`scorecard.json`/`write-boundary` 等关键词做全局检索，未发现与本能力重复或冲突的现有规格。

---

## ADDED Requirements

### Requirement: REQ-DS-001: Demo Suite 单次运行必须产出标准产物

demo-suite SHALL 在指定 out-dir 内产出“机器可读 + 人类可读”的最小闭环产物：

- 机器可读：`metrics.json`
- 人类可读：`report.md`
- 可选：`raw/`（用于追溯的原始输出与日志）

Trace: AC-001

#### Scenario: SC-DS-001: 单次运行（标准产物）

- **GIVEN** 用户指定一个 out-dir 作为最终落盘根目录
- **WHEN** demo-suite 完成一次运行
- **THEN** out-dir 内存在 `single/metrics.json` 与 `single/report.md`
- **AND** 若存在 `single/raw/`，其内容 MUST 仅作为可选追溯信息，不影响 `metrics.json` 的最小契约校验结论

Trace: AC-001

---

### Requirement: REQ-DS-002: out-dir 是唯一最终落盘边界，且必须可证明未越界写入

demo-suite SHALL 将 out-dir 视为“唯一最终落盘根目录”，并通过“写入边界哨兵 + 扫描证据”证明 out-dir 之外无新增/更新文件，且默认无系统临时残留（允许的例外与降级见 Contract）。

Trace: AC-002

#### Scenario: SC-DS-002: 写入边界证明（哨兵 + 扫描证据）

- **GIVEN** demo-suite 在 out-dir 内写入写入边界哨兵文件
- **WHEN** demo-suite 运行结束并执行边界扫描
- **THEN** out-dir 内存在 `write-boundary/write-boundary-sentinel`
- **AND** out-dir 内存在 `write-boundary/new-or-updated-files.txt`，且内容为空表示“out-dir 之外无新增/更新文件”
- **AND** out-dir 内存在 `write-boundary/tmp-scan.txt`，且默认不包含系统 `/tmp` 残留（详见 Contract 的 `/tmp` 策略）

Trace: AC-002

---

### Requirement: REQ-DS-003: 版本 A/B 必须产出可审计的双 run 产物与 compare 产物

demo-suite SHALL 支持“版本 A/B”（不同 `git.ref_input`）的两次运行产物与对比产物：

- 两次运行分别产出各自的 `metrics.json`/`report.md`
- 生成 `compare/compare.json` 与 `compare/compare.md`
- 所有审计字段缺失时 MUST 按降级表示法输出，避免“假对比”

Trace: AC-003, AC-005

#### Scenario: SC-DS-003: 版本 A/B（可审计 + compare 产物闭合）

- **GIVEN** 用户提供两个可解析为 commit 的 `git.ref_input`（A 与 B）
- **WHEN** demo-suite 分别完成 A 与 B 的运行并生成对比产物
- **THEN** out-dir 内存在 `ab-version/run-a/metrics.json` 与 `ab-version/run-b/metrics.json`
- **AND** out-dir 内存在 `ab-version/run-a/report.md` 与 `ab-version/run-b/report.md`
- **AND** out-dir 内存在 `ab-version/compare/compare.json` 与 `ab-version/compare/compare.md`
- **AND** compare 产物对每个指标提供一致的判定语义（direction/tolerance/缺失处理/回归提升规则）

Trace: AC-003, AC-005

---

### Requirement: REQ-DS-004: 配置 A/B 必须产出可审计的双 run 产物与 compare 产物

demo-suite SHALL 支持“配置 A/B”（同一 `git.ref_resolved` 下，至少两个可控开关）：

- `context_injection_mode`：`on|off`（默认 `on`）
- `cache_mode`：`cold|warm`（默认 `cold`）

并且 compare MUST 能识别变量漂移：当“除目标开关外”检测到差异时，`overall_verdict` MUST 为 `inconclusive` 且包含原因码。

Trace: AC-004, AC-005

#### Scenario: SC-DS-004: 配置 A/B（唯一区别控制 + 漂移即不可下结论）

- **GIVEN** A 与 B 在同一 `git.ref_resolved`、同一数据集指纹、同一环境快照下运行
- **WHEN** A 与 B 仅在目标开关（`context_injection_mode` 或 `cache_mode`）上不同，其余变量保持一致
- **THEN** out-dir 内存在 `ab-config/run-a/metrics.json` 与 `ab-config/run-b/metrics.json`
- **AND** out-dir 内存在 `ab-config/compare/compare.json` 与 `ab-config/compare/compare.md`
- **AND** 若 compare 检测到非目标变量漂移，则 `overall_verdict` MUST 为 `inconclusive` 且原因码包含 `variable_drift_detected`

Trace: AC-004, AC-005

---

### Requirement: REQ-DS-005: 简单/复杂双场景必须具备可判真的锚点，且支持一致的降级表示法

demo-suite SHALL 覆盖两个代表性诊断场景，并以“固定输入 + 可判真锚点 + 允许降级条件”定义可比较字段；当工具/依赖缺失时 MUST 使用一致的降级表示法（见 Contract）。

Trace: AC-006

#### Scenario: SC-DS-005: 简单场景（速度）锚点可判真

- **GIVEN** 固定输入为一个可解析的错误信息：`TypeError: Cannot read property 'user' at handleToolCall (src/server.ts:1)`
- **WHEN** demo-suite 生成简单场景的诊断指标
- **THEN** `metrics.json` 中对简单场景给出机器可读结论字段（见 Contract）
- **AND** 简单场景锚点至少包含：
  - 锚点 1：目标仓库中存在 `src/server.ts`
  - 锚点 2：目标仓库中存在符号 `handleToolCall`
  - 锚点 3（未降级时）：候选定位结果中包含 `src/server.ts`

Trace: AC-006

#### Scenario: SC-DS-006: 复杂场景（能力）锚点可判真

- **GIVEN** 固定输入包含符号：`handleToolCall`，且目标为“调用链 + 影响面”
- **WHEN** demo-suite 生成复杂场景的诊断指标
- **THEN** `metrics.json` 中对复杂场景给出机器可读结论字段（见 Contract）
- **AND** 复杂场景锚点至少包含：
  - 锚点 1：调用链输出中存在 `file_path == "src/server.ts"`
  - 锚点 2（未降级时）：影响分析输出中包含 `src/server.ts`

Trace: AC-006

---

### Requirement: REQ-DS-006: AI 双代理 A/B 默认可选；执行时必须以 scorecard.json 半自动沉淀并可审计

demo-suite SHALL 支持 AI 双代理 A/B 的"半自动、可复用、可审计"结果沉淀，默认可选：

- 当 `metrics.json.ai_ab.status="executed"` 时，每个任务（`simple_bug|complex_bug`）每个代理（`A|B`）产出 `scorecard.json`
- 当 `metrics.json.ai_ab.status="skipped"` 时，`metrics.json.ai_ab.skipped_reason` 与 `report.md` 必须可审计
- scorecard MUST 声明固定变量与允许变化变量，并以证据路径支撑结论

**A/B 配置定义（核心语义）**：

AI 双代理 A/B 的核心目标是**对比 MCP 工具相比原生能力的价值增益**：

| 代理 | 配置 | 可用工具 | 目标 |
|------|------|----------|------|
| **A（With MCP）** | 启用 Code Intelligence MCP | `ci_search`, `ci_call_chain`, `ci_impact`, `ci_bug_locate`, `ci_graph_rag` 等 | 验证 MCP 工具的价值 |
| **B（Without MCP）** | 禁用 MCP | 仅使用原生 Claude Code 能力：`Grep`, `Glob`, `Read`, `LSP`, `Bash` 等 | 作为基线对照 |

**对比维度**：
- 速度：完成相同任务的时间（`run.duration_ms`）
- 准确性：锚点命中率（`passed_anchors_count / anchors.length`）
- 轮次效率：完成任务所需的对话轮次（`run.turns`）

**变量控制原则**：
- `variables.fixed[]` MUST 包含：任务说明、时间预算、起始代码状态、数据集、目标仓库
- `variables.varied[]` MUST 仅包含：`mcp_enabled: true|false`

Trace: AC-007

#### Scenario: SC-DS-007: AI 双代理 A/B（可选 + scorecard 审计）

- **GIVEN** `metrics.json.ai_ab.status` 被标记为 `executed` 或 `skipped`
- **WHEN** 用户按 scorecard 契约沉淀结果或选择跳过
- **THEN** 当 `metrics.json.ai_ab.status="executed"` 时，out-dir 内存在：
  - `ai-ab/simple_bug/A/scorecard.json`（代理 A，启用 MCP）
  - `ai-ab/simple_bug/B/scorecard.json`（代理 B，禁用 MCP）
  - `ai-ab/complex_bug/A/scorecard.json`（代理 A，启用 MCP）
  - `ai-ab/complex_bug/B/scorecard.json`（代理 B，禁用 MCP）
- **AND** 当 `metrics.json.ai_ab.status="skipped"` 时，`metrics.json.ai_ab.skipped_reason` 与 `report.md` 中的对应说明可审计
- **AND** 若生成 scorecard，每份 scorecard 均可被机器校验其最小契约，并可被 compare 机制消费（允许 `inconclusive`，但禁止无证据主观结论）
- **AND** scorecard.variables.varied MUST 包含 `mcp_enabled` 字段，值为 `true`（代理 A）或 `false`（代理 B）

Trace: AC-007

---

## Contract（产物契约与兼容策略）

> 本 Contract 聚焦 demo-suite 的可观察产物与其最小可执行校验锚点；字段语义以 `proposal.md` 的 “Boundaries & Contracts” 为权威来源，本文件给出可直接执行的最小校验方式与稳定路径约定。

### 1) out-dir 与路径布局（产物契约）

- out-dir：demo-suite 的“唯一最终落盘根目录”（推荐 `--out-dir` 或 `CI_DEMO_OUT_DIR`）。
- out-dir 默认值：若未显式指定，默认 out-dir SHOULD 为 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/<run-id>/`。
- out-dir 安全约束（拒绝越界与证据漂移）：
  - out-dir MUST 是目录路径且非空
  - out-dir MUST NOT 为 `.`/`..`
  - out-dir MUST NOT 指向符号链接

**标准相对路径布局（相对 out-dir）**：

- `single/metrics.json`
- `single/report.md`
- `single/raw/`（可选）
- `ab-version/run-a/metrics.json`
- `ab-version/run-a/report.md`
- `ab-version/run-b/metrics.json`
- `ab-version/run-b/report.md`
- `ab-version/compare/compare.json`
- `ab-version/compare/compare.md`
- `ab-config/run-a/metrics.json`
- `ab-config/run-a/report.md`
- `ab-config/run-b/metrics.json`
- `ab-config/run-b/report.md`
- `ab-config/compare/compare.json`
- `ab-config/compare/compare.md`
- `degraded/metrics.json`
- `degraded/report.md`
- `write-boundary/write-boundary-sentinel`
- `write-boundary/new-or-updated-files.txt`
- `write-boundary/tmp-scan.txt`
- `ai-ab/simple_bug/A/scorecard.json`
- `ai-ab/simple_bug/B/scorecard.json`
- `ai-ab/complex_bug/A/scorecard.json`
- `ai-ab/complex_bug/B/scorecard.json`

注：`ai-ab/**/scorecard.json` 仅当 `metrics.json.ai_ab.status="executed"` 时要求存在；当 `metrics.json.ai_ab.status="skipped"` 时，`metrics.json.ai_ab.skipped_reason` 与 `report.md` MUST 可审计。

### 2) `metrics.json` 最小契约（schema v1.0）

#### 2.1 版本化与兼容

- `schema_version` MUST 为 `MAJOR.MINOR` 字符串（例如 `1.0`）。
- 兼容规则：
  - MAJOR 变化 = breaking；compare 工具只保证同一 MAJOR 的兼容
  - MINOR 只能新增可选字段或新增可比较指标；MUST NOT 改变既有字段语义

#### 2.2 顶层必填字段（v1.0）

- `schema_version`（string）
- `run_id`（string）
- `generated_at`（string，ISO-8601）
- `status`（`success|degraded|failed`）
- `degraded`（boolean；当 `status=="degraded"` 时 MUST 为 true）
- `reasons`（string[]；稳定原因码集合，可为空数组）
- `git.ref_input`（string）
- `git.ref_resolved`（string；40 位 commit SHA）
- `git.dirty`（boolean）
- `git.isolation.strategy`（string：`worktree|temp_clone|in_place`）
- `git.isolation.workdir`（string；相对 out-dir 的路径）
- `dataset.queries.path`（string）
- `dataset.queries.line_count`（number）
- `dataset.queries.sha256`（string）
- `environment.os`（string）
- `environment.arch`（string）
- `environment.node`（string）
- `config.toggles.context_injection_mode.value`（string：`on|off`）
- `config.toggles.context_injection_mode.source`（string：`default|env|cli|config_file`）
- `config.toggles.cache_mode.value`（string：`cold|warm`）
- `config.toggles.cache_mode.source`（string：`default|env|cli|config_file`）
- `config.hash`（string）
- `config.devbooks_config.mode`（`copied|generated|disabled|missing`）
- `config.devbooks_config.path`（string 或 null）
- `config.devbooks_config.sha256`（string 或 null）
- `config.devbooks_config.missing`（boolean）
- `write_boundary.out_dir`（string）
- `write_boundary.tmp_dir`（string）
- `write_boundary.allow_system_tmp`（boolean）
- `metrics.demo_suite.total_duration_ms`（number）
- `steps`（array；每个元素至少包含 `id`/`status`/`duration_ms`）

#### 2.3 可选字段（v1.x 可扩展）

- `environment.tools`（工具可用性与版本快照）
- `missing_fields`（string[]；缺失字段路径列表，例如 `metrics.performance.mrr_at_10`）
- `ai_ab.status`（`executed|skipped`；当未执行 AI A/B 时 MUST 为 `skipped`）
- `ai_ab.skipped_reason`（string 或 null；当 `ai_ab.status="skipped"` 时必填）
- `metrics.performance.*`、`metrics.quality.*`、`metrics.diagnosis.*`、`metrics.impact.*`

#### 2.4 缺失/降级表示法（必须一致）

- 缺失指标：对应值 MUST 为 `null`；并且 MUST 在 `missing_fields[]` 列出字段路径；同时 `reasons[]` MUST 包含稳定原因码。
- 降级：`status="degraded"` 且 `degraded=true`，并在 `reasons[]` 中写明原因；`report.md` MUST 同步呈现降级说明。

#### 2.5 稳定原因码（最小集）

- `invalid_git_ref`
- `dirty_worktree`
- `devbooks_config_drift`
- `missing_jq`
- `impact_db_missing`
- `tmp_leak_detected`
- `write_boundary_violation`
- `invalid_out_dir`

#### 2.6 机器可执行校验（jq）

```bash
jq -e '(.schema_version|type=="string") and (.run_id|type=="string") and (.git.ref_resolved|type=="string") and (.dataset.queries.sha256|type=="string") and (.config.hash|type=="string") and (.config.devbooks_config.mode|type=="string") and (.metrics.demo_suite.total_duration_ms|type=="number") and (.steps|type=="array")' "<out-dir>/<run-scope>/metrics.json" >/dev/null
```

其中 `<run-scope>` 是 `single`、`ab-version/run-a`、`ab-version/run-b`、`ab-config/run-a`、`ab-config/run-b`、`degraded` 之一。

### 3) `report.md` 最小契约

- `report.md` MUST 存在且非空。
- `report.md` MUST 与同目录的 `metrics.json.status` 与 `metrics.json.reasons[]` 一致呈现（允许更详细解释，但禁止相互矛盾）。
- 当 `metrics.json.ai_ab.status="skipped"` 时，`report.md` MUST 说明跳过原因且与 `metrics.json.ai_ab.skipped_reason` 一致。

### 4) `compare.json` / `compare.md` 最小契约

#### 4.1 `compare.json` 必填字段

- `schema_version`（string）
- `overall_verdict`（string；至少允许：`improvement|regression|no_change|inconclusive|unknown`）
- `metrics`（array）
- `thresholds.source`（`file|builtin`）
- `thresholds.path`（string 或 null）
- `thresholds.sha256`（string）

#### 4.2 阈值来源与失败语义

- 若提供阈值文件（`CI_DEMO_COMPARE_THRESHOLDS=<path>`）但文件不存在/不可解析为 JSON，则 compare MUST 失败并写入：
  - `status="failed"`
  - `reasons[]=["invalid_thresholds_config"]`

#### 4.3 缺失字段处理（unknown 与不可下结论）

- 若任一侧指标缺失（字段不存在或值为 `null`，或在 `missing_fields[]` 中声明缺失），该指标 `verdict` MUST 为 `unknown`。
- 当 `unknown` 指标数量超过阈值（默认：`>0`），`overall_verdict` MUST 为 `inconclusive`。

#### 4.4 回归/提升判定（与 direction/tolerance 一致）

- 数值指标：
  - `higher`：`b - a > tolerance` → improvement；`a - b > tolerance` → regression；否则 no_change
  - `lower`：`a - b > tolerance` → improvement；`b - a > tolerance` → regression；否则 no_change
- 布尔指标（true is better）：`false→true` = improvement；`true→false` = regression；相同 = no_change

#### 4.5 机器可执行校验（jq）

```bash
jq -e '(.schema_version|type=="string") and (.overall_verdict|type=="string") and (.metrics|type=="array")' "<out-dir>/<compare-scope>/compare/compare.json" >/dev/null
```

其中 `<compare-scope>` 是 `ab-version` 或 `ab-config`。

### 5) 写入边界检查与哨兵文件

- demo-suite MUST 在 out-dir 内写入哨兵文件：`write-boundary/write-boundary-sentinel`
- demo-suite MUST 产出边界扫描证据：
  - `write-boundary/new-or-updated-files.txt`：记录 out-dir 之外的新/改文件列表（为空表示无越界）
  - `write-boundary/tmp-scan.txt`：记录系统临时残留扫描结果
- `/tmp` 默认策略：不允许
  - 默认 MUST 不存在：`/tmp/ci-drift-snapshot.json`
  - 若外部工具强制使用 `/tmp`，仅允许 `/tmp/ci-demo-<run-id>-*`，且退出时 MUST 清理；清理失败 MUST 视为降级并写入 `tmp_leak_detected`

### 6) 简单/复杂场景指标与锚点（可比较字段）

`metrics.json` MUST 以机器可读方式记录双场景结果；最小字段集（允许扩展）：

- `metrics.diagnosis.simple.has_expected_hit`（boolean 或 null）
- `metrics.diagnosis.simple.duration_ms`（number 或 null）
- `metrics.diagnosis.simple.candidates_count`（number 或 null）
- `metrics.diagnosis.complex.has_expected_hit`（boolean 或 null）
- `metrics.diagnosis.complex.duration_ms`（number 或 null）
- `metrics.diagnosis.complex.has_call_chain`（boolean 或 null）
- `metrics.diagnosis.complex.has_impact`（boolean 或 null）

降级规则（示例最小集）：

- 若 `jq` 不可用导致无法生成候选定位可判真证据，则：
  - `metrics.diagnosis.simple.has_expected_hit` MUST 为 `null`
  - `missing_fields[]` MUST 包含 `metrics.diagnosis.simple.has_expected_hit`
  - `reasons[]` MUST 包含 `missing_jq`
- 若缺少图数据库或 `sqlite3` 导致无法生成影响面证据，则：
  - 影响分析相关字段 MUST 为 `null`
  - `missing_fields[]` MUST 覆盖对应字段路径
  - `reasons[]` MUST 包含 `impact_db_missing`

### 7) `scorecard.json`（AI 双代理 A/B，schema v1.0）

#### 7.1 产物路径（相对 out-dir）

- `ai-ab/simple_bug/A/scorecard.json`
- `ai-ab/simple_bug/B/scorecard.json`
- `ai-ab/complex_bug/A/scorecard.json`
- `ai-ab/complex_bug/B/scorecard.json`

#### 7.2 最小契约字段

- `schema_version`（string；固定为 `1.0`）
- `task_id`（`simple_bug|complex_bug`）
- `agent_id`（`A|B`）
- `git.ref_input`（string）
- `git.ref_resolved`（string）
- `run.started_at`（string；ISO-8601）
- `run.ended_at`（string；ISO-8601）
- `run.duration_ms`（number）
- `run.turns`（number）
- `variables.fixed`（array；必须保持一致的变量清单）
- `variables.varied`（array；允许变化的变量清单）
- `anchors`（array；元素包含 `id`/`passed`/`reason`/`evidence_path`/`check_command`）
- `evidence.command_log_path`（string）
- `evidence.output_diff_path`（string）

#### 7.3 评分语义（最小且可审计）

- `passed_anchors_count`（number）= `anchors[].passed==true` 的数量
- `score`（number）建议 = `passed_anchors_count / anchors.length`（0~1）
- compare MAY 基于 `score` 与关键锚点给出提升/回归/不可下结论（允许 `inconclusive`）

#### 7.4 机器可执行校验（jq）

```bash
jq -e '(.schema_version=="1.0") and (.task_id|IN("simple_bug","complex_bug")) and (.agent_id|IN("A","B")) and (.git.ref_resolved|type=="string") and (.run.duration_ms|type=="number") and (.run.turns|type=="number") and (.variables.fixed|type=="array") and (.variables.varied|type=="array") and (.anchors|type=="array") and (all(.anchors[]; (.evidence_path|type=="string") and (.check_command|type=="string"))) and (.evidence.command_log_path|type=="string") and (.evidence.output_diff_path|type=="string")' "<out-dir>/ai-ab/<task-id>/<agent-id>/scorecard.json" >/dev/null
```

---

## Contract Test IDs（CT-xxx）

| Test ID | 类型 | 断言点（可执行） | 覆盖 |
|---|---|---|---|
| CT-DS-001 | schema | 执行 Contract 2.6 的 jq 校验命令，目标文件：`<out-dir>/single/metrics.json` | REQ-DS-001, SC-DS-001, AC-001 |
| CT-DS-002 | behavior | 断言 `<out-dir>/single/report.md` 存在且非空 | REQ-DS-001, SC-DS-001, AC-001 |
| CT-DS-003 | behavior | 断言 `<out-dir>/write-boundary/write-boundary-sentinel` 存在 | REQ-DS-002, SC-DS-002, AC-002 |
| CT-DS-004 | behavior | 断言 `<out-dir>/write-boundary/new-or-updated-files.txt` 为空（`test ! -s "<out-dir>/write-boundary/new-or-updated-files.txt"`） | REQ-DS-002, SC-DS-002, AC-002 |
| CT-DS-005 | behavior | 断言 `/tmp/ci-drift-snapshot.json` 不存在（`test ! -e /tmp/ci-drift-snapshot.json`） | REQ-DS-002, SC-DS-002, AC-002 |
| CT-DS-006 | schema | 执行 Contract 2.6 的 jq 校验命令，分别校验：`<out-dir>/ab-version/run-a/metrics.json` 与 `<out-dir>/ab-version/run-b/metrics.json` | REQ-DS-003, SC-DS-003, AC-003 |
| CT-DS-007 | schema | 执行 Contract 4.5 的 jq 校验命令，目标文件：`<out-dir>/ab-version/compare/compare.json` | REQ-DS-003, SC-DS-003, AC-005 |
| CT-DS-008 | schema | 执行 Contract 4.5 的 jq 校验命令，目标文件：`<out-dir>/ab-config/compare/compare.json` | REQ-DS-004, SC-DS-004, AC-004, AC-005 |
| CT-DS-009 | behavior | 当 compare 检测到非目标变量漂移时，断言 `overall_verdict=="inconclusive"` 且原因码包含 `variable_drift_detected` | REQ-DS-004, SC-DS-004, AC-004 |
| CT-DS-010 | behavior | 当 `jq` 缺失触发降级时，断言 `metrics.diagnosis.simple.has_expected_hit==null` 且 `missing_fields[]` 包含对应路径且 `reasons[]` 包含 `missing_jq` | REQ-DS-005, SC-DS-005, AC-006 |
| CT-DS-011 | behavior | 当影响分析依赖缺失触发降级时，断言相关字段为 `null` 且 `reasons[]` 包含 `impact_db_missing` | REQ-DS-005, SC-DS-006, AC-006 |
| CT-DS-012 | schema | 当 `<out-dir>/single/metrics.json` 的 `ai_ab.status="executed"` 时，执行 Contract 7.4 的 jq 校验命令，分别校验四份 scorecard：`<out-dir>/ai-ab/simple_bug/A/scorecard.json`、`<out-dir>/ai-ab/simple_bug/B/scorecard.json`、`<out-dir>/ai-ab/complex_bug/A/scorecard.json`、`<out-dir>/ai-ab/complex_bug/B/scorecard.json` | REQ-DS-006, SC-DS-007, AC-007 |
