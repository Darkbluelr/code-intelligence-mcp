# tasks.md：20260123-0702-improve-demo-suite-ab-metrics

> truth-root = `dev-playbooks/specs`；change-root = `dev-playbooks/changes`  
> 产物路径：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md`  
> 输入真理源：
> - design：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/design.md`
> - spec：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/specs/demo-suite/spec.md`
>
> 范围红线（必须遵守）：只允许改动 `demo/` + 文档/归档层（例如 `docs/`、`dev-playbooks/docs/`）；本变更不改业务逻辑与对外契约（`src/`、`scripts/`、`hooks/` 的对外行为与输出契约保持不变）；`tests/` 仅允许在 Test Owner 阶段为验收新增/修改，Coder 阶段禁止修改 `tests/`。

## 模式选择

默认：主线计划模式（Main Plan Area）。临时任务仅进入“临时计划区”。

## 主线计划区（Main Plan Area）

### MP1：单次运行标准产物闭合（AC-001）

- [x] MP1.1 新增/收敛 `demo/demo-suite.sh` 单入口：out-dir 安全校验 + run-id 生成 + 标准目录布局
  - Why：将现有 `demo/00-*.sh`~`demo/05-*.sh` 升级为可复用“demo-suite”，并为后续 A/B、compare、写入边界提供统一编排与可审计落点。
  - AC：AC-001（为产物闭合提供单入口与稳定路径）；AC-002（out-dir 安全约束前置）。
  - Anchors：
    - CT-DS-001/CT-DS-002 的前置路径稳定性（`<out-dir>/single/*`）。
    - Spec Contract 1（out-dir 安全约束：非空、非 `.`/`..`、非符号链接；默认落点 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/<run-id>/`）。
  - Deps：无（允许先只实现参数解析、目录创建、空跑框架）。
  - Risks：
    - out-dir 校验不严导致证据漂移或越界写入。
    - 目录布局与设计文档示例不一致（见“Design Backport Candidates”）。

- [x] MP1.2 产出 `single/metrics.json`（schema v1.0）并确保最小 jq 契约可过
  - Why：提供机器可读的最小稳定产物，用于 compare 与后续自动化验收；并为降级/缺失提供可审计表达。
  - AC：AC-001。
  - Anchors：
    - CT-DS-001（Spec Contract 2.6：对 `<out-dir>/single/metrics.json` 执行 `jq -e` 校验）。
    - Spec Contract 2.4（缺失/降级表示法：`null` + `missing_fields[]` + `reasons[]` + `status/degraded` 一致）。
    - AC-007（未执行 AI A/B 时，`metrics.json.ai_ab.status`/`ai_ab.skipped_reason` 必填）。
  - Deps：MP1.1（需要 out-dir 与目录布局）。
  - Risks：
    - 必填字段遗漏导致契约不闭合（即使短期未被 CT 覆盖，仍会破坏 AC-003/AC-004 的可审计性前提）。
    - 误把不可得信息写成“假值”，破坏可审计性（必须用缺失/降级表示法）。

- [x] MP1.3 产出 `single/report.md`（非空）且与 `single/metrics.json` 的 `status/reasons` 一致
  - Why：提供人类可读报告，且与机器可读产物一致，避免“报告说通过但 JSON 说降级/失败”的不可审计状态。
  - AC：AC-001。
  - Anchors：
    - CT-DS-002（断言 `<out-dir>/single/report.md` 存在且非空）。
    - Spec Contract 3（`report.md` 与同目录 `metrics.json.status` / `metrics.json.reasons[]` 一致）。
  - Deps：MP1.2（需要 status/reasons 来源）。
  - Risks：report 仅描述“成功”但未同步降级原因码，导致审计失败。

### MP2：写入边界修复与可证明证据（AC-002）

- [x] MP2.1 修复已知风险点：`demo/05-performance.sh` 不再写入硬编码 change-id，且所有输出受 out-dir 约束
  - Why：消除“写入其他 change-id/散落证据”的已知风险点，满足 out-dir 唯一最终落盘边界要求。
  - AC：AC-002。
  - Anchors：
    - 运行 demo-suite 后，写入边界扫描应证明 out-dir 之外无新增/更新文件（CT-DS-004）。
    - 复查 `demo/05-performance.sh` 不再包含硬编码 `dev-playbooks/changes/<other-id>/...`。
  - Deps：MP1.1（demo-suite 需要能向子脚本传递 out-dir 或在 out-dir 下落盘 raw/）。
  - Risks：脚本仍把输出写到仓库内固定位置，导致越界写入被写入边界扫描捕获。

- [x] MP2.2 修复 `/tmp` 风险点：`demo/04-quality.sh` 不再写入 `/tmp/ci-drift-snapshot.json`（默认策略），或确保退出清理且不遗留
  - Why：满足“默认无系统 `/tmp` 残留”的写入边界要求，并与 Spec Contract 5 对齐。
  - AC：AC-002。
  - Anchors：
    - CT-DS-005（断言 `/tmp/ci-drift-snapshot.json` 不存在）。
    - Spec Contract 5（如确需 `/tmp`，仅允许 `/tmp/ci-demo-<run-id>-*` 且退出清理；清理失败视为降级并记录 `tmp_leak_detected`）。
  - Deps：MP1.1（需要 run-id 与 out-dir/.tmp 目录可用）。
  - Risks：外部工具默认写入 `/tmp` 无法完全控制；需通过 wrapper/参数化把临时文件重定向到 `<out-dir>/.tmp/`。

- [x] MP2.3 写入边界证据闭合：生成哨兵 + 扫描证据文件，并将“越界/残留”机器可读化
  - Why：提供可重复、可自动验证的写入边界证据，确保 out-dir 之外无新增/更新文件，且默认无 `/tmp` 残留。
  - AC：AC-002。
  - Anchors：
    - CT-DS-003（`<out-dir>/write-boundary/write-boundary-sentinel` 存在）。
    - CT-DS-004（`<out-dir>/write-boundary/new-or-updated-files.txt` 为空）。
    - CT-DS-005（`/tmp/ci-drift-snapshot.json` 不存在）。
  - Deps：MP1.1（需要 out-dir 目录结构与 run-id）。
  - Risks：
    - 扫描策略把 out-dir 自身的写入误判为越界（必须明确“out-dir 之外”的边界定义）。
    - 扫描漏报导致“假通过”（建议以 `git status --porcelain` + 路径过滤、以及 `/tmp` 特定文件扫描双重保障）。

### MP3：版本 A/B 可审计双 run（AC-003）

- [x] MP3.1 实现 `ab-version`：解析 A/B 两个 `git.ref_input`，在 out-dir 下隔离运行并产出双 run 标准产物
  - Why：为“版本对比”提供可重复、可审计的双 run 产物闭环（两份 metrics/report + 后续 compare）。
  - AC：AC-003（双 run 可审计）；为 AC-005（compare）提供输入。
  - Anchors：
    - CT-DS-006（对 `<out-dir>/ab-version/run-a/metrics.json` 与 `<out-dir>/ab-version/run-b/metrics.json` 执行 Spec Contract 2.6 的 `jq -e` 校验）。
    - Spec Contract 1（路径布局：`ab-version/run-a/*`、`ab-version/run-b/*`）。
  - Deps：MP1.1~MP1.3（单次运行产物与字段结构复用）。
  - Risks：
    - git 隔离策略与 dirty 规则处理不当导致 A/B 不可比（需按 `proposal.md` 的“版本 A/B 语义（ref 输入 / dirty 规则 / 隔离）”落地）。
    - 依赖/缓存/索引未隔离导致变量漂移（需在 metrics 中可审计表达）。

### MP4：compare 产物闭合（ab-version，AC-005）

- [x] MP4.1 生成 `ab-version/compare/compare.json` 与 `compare.md`，并闭合 compare 最小契约
  - Why：把两份 `metrics.json` 转为机器可校验的对比结论，并输出人类可读摘要，形成长期可复用的对比资产。
  - AC：AC-005。
  - Anchors：
    - CT-DS-007（对 `<out-dir>/ab-version/compare/compare.json` 执行 Spec Contract 4.5 的 `jq -e` 校验）。
    - Spec Contract 4.2（阈值文件不可解析必须失败并写入 `reasons=["invalid_thresholds_config"]`）。
    - Spec Contract 4.3（缺失字段 → 指标 verdict 必为 `unknown`；unknown>0 → `overall_verdict="inconclusive"`）。
  - Deps：MP3.1（需要 `ab-version/run-a` 与 `run-b` 两份 metrics）。
  - Risks：
    - compare 未记录阈值来源与 sha256，导致结论不可审计。
    - overall 聚合规则与 `proposal.md` 不一致（需以 `proposal.md` 的“Boundaries & Contracts” 为权威来源）。

### MP5：配置 A/B 可审计双 run + 漂移即不可下结论（AC-004/AC-005）

- [x] MP5.1 实现 `ab-config`：同一 `git.ref_resolved` 下运行两套开关配置并产出双 run 标准产物
  - Why：为“开关对比”（`context_injection_mode`、`cache_mode`）提供可审计、可复现的双 run 输入，满足“唯一区别控制原则”。
  - AC：AC-004（配置 A/B 可审计）。
  - Anchors：
    - Spec Contract 1（路径布局：`ab-config/run-a/*`、`ab-config/run-b/*`）。
    - Spec Contract 2.2（`config.toggles.*.value/source` + `config.hash` + `config.devbooks_config.*` 可审计）。
  - Deps：MP1.1~MP1.3（单次运行字段结构复用）。
  - Risks：开关注入来源不可追溯（env/cli/config_file），导致 config.hash 不稳定或不可解释。

- [x] MP5.2 生成 `ab-config/compare/compare.json` 与 `compare.md` 并通过最小契约校验
  - Why：闭合“配置 A/B”对比产物，保证 compare 机制在同一 ref 下可复用且可审计。
  - AC：AC-004、AC-005。
  - Anchors：
    - CT-DS-008（对 `<out-dir>/ab-config/compare/compare.json` 执行 Spec Contract 4.5 的 `jq -e` 校验）。
  - Deps：MP5.1（需要 ab-config 双 run metrics）。
  - Risks：compare 输出结构与 ab-version 不一致，导致工具链不可复用（应保持同一 compare 契约）。

- [x] MP5.3 变量漂移检测：当 compare 检测到非目标变量漂移时，必须 `overall_verdict="inconclusive"` 且原因码包含 `variable_drift_detected`
  - Why：防止“假对比”：如果 A/B 之间除了目标开关外仍存在差异，任何结论都不可下。
  - AC：AC-004。
  - Anchors：
    - CT-DS-009（漂移触发时断言 `overall_verdict=="inconclusive"` 且原因码包含 `variable_drift_detected`）。
  - Deps：MP5.2（漂移检测落盘于 compare 产物）；MP5.1（需要目标开关与其他变量的审计字段可比）。
  - Risks：
    - 漂移判定过严导致频繁 `inconclusive`（需明确“固定变量/允许变化变量”的清单与来源）。
    - 漂移判定过松导致“假通过”（必须覆盖 git/dataset/environment/config/hash 等关键变量）。

### MP6：简单/复杂双场景可判真 + 降级表示法一致（AC-006）

- [x] MP6.1 简单场景（SC-DS-005）：产出可判真的 `metrics.diagnosis.simple.*` 字段，并在缺失时按契约降级
  - Why：为“速度/定位”维度提供固定输入与可判真锚点，避免主观结论。
  - AC：AC-006。
  - Anchors：
    - Spec Contract 6（字段：`metrics.diagnosis.simple.has_expected_hit`/`duration_ms`/`candidates_count`）。
    - Spec Scenario SC-DS-005 的锚点要求（`src/server.ts`、符号 `handleToolCall`、候选定位包含 `src/server.ts`）。
  - Deps：MP1.2（metrics.json 基础结构与 missing_fields/reasons 机制）。
  - Risks：仅输出工具原始文本而无机器可读判真字段，导致 AC-006 Fail。

- [x] MP6.2 复杂场景（SC-DS-006）：产出可判真的 `metrics.diagnosis.complex.*` 字段，并在缺失时按契约降级
  - Why：为“能力/调用链+影响面”维度提供固定输入与可判真锚点，支持 compare。
  - AC：AC-006。
  - Anchors：
    - Spec Contract 6（字段：`metrics.diagnosis.complex.has_expected_hit`/`duration_ms`/`has_call_chain`/`has_impact`）。
    - Spec Scenario SC-DS-006 的锚点要求（call chain 输出含 `src/server.ts`；未降级时 impact 输出含 `src/server.ts`）。
  - Deps：MP1.2（metrics.json 基础结构）。
  - Risks：影响分析依赖缺失时未按契约把字段置 `null` 并记录 `impact_db_missing`，导致降级不可审计。

- [x] MP6.3 降级：当 `jq` 缺失触发降级时，必须写入 `null + missing_fields + reasons=["missing_jq"]` 并保持 report 一致
  - Why：保证在依赖缺失时仍可输出可审计产物，并使降级可被 contract tests 稳定断言。
  - AC：AC-006。
  - Anchors：
    - CT-DS-010（断言 `metrics.diagnosis.simple.has_expected_hit==null` 且 `missing_fields[]` 包含对应路径且 `reasons[]` 包含 `missing_jq`）。
  - Deps：MP6.1（需要 simple 场景字段存在）；MP1.3（report 与 metrics 一致）。
  - Risks：将缺失误报为 false/0，导致“假结论”；必须用 `null` 表达缺失。

- [x] MP6.4 降级：当影响分析依赖缺失触发降级时，相关字段必须为 `null` 且 `reasons[]` 包含 `impact_db_missing`
  - Why：确保复杂场景在依赖不可用时仍可输出可审计、可比较的降级结果。
  - AC：AC-006。
  - Anchors：
    - CT-DS-011（断言相关字段为 `null` 且 `reasons[]` 包含 `impact_db_missing`）。
  - Deps：MP6.2（需要 impact 相关字段定义与落盘）。
  - Risks：依赖缺失时直接让 demo-suite 失败退出，导致产物不闭合（AC-001/AC-006 Fail）。

### MP7：AI 双代理 scorecard 半自动沉淀（AC-007）

- [x] MP7.1 提供 scorecard 产物落盘与最小契约闭合（含 anchors[].evidence_path/check_command，4 份 scorecard.json）
  - Why：把“两次独立 AI 会话”的结果以最小可审计结构沉淀，并可被 compare 机制消费。
  - AC：AC-007。
  - Anchors：
    - CT-DS-012（对 4 份 `<out-dir>/ai-ab/<task-id>/<agent-id>/scorecard.json` 执行 Spec Contract 7.4 的 `jq -e` 校验）。
  - Deps：MP1.1（out-dir/run-id 目录基础）；不依赖业务逻辑修改（保持半自动，不做 AI 编排系统）。
  - Risks：scorecard 缺少证据路径或变量清单，导致无法审计或无法 compare。

### MP8：质量闸门可复现（仅 demo/）（AC-008）

- [x] MP8.1 收敛并固化质量闸门：ShellCheck 仅覆盖 `demo/` 目录树下 `*.sh`，并可重复执行
  - Why：保证质量闸门可复现且不被历史债务拖垮（范围红线：不把 `scripts/`/`hooks/` 纳入本次 DoD）。
  - AC：AC-008。
  - Anchors：
    - ShellCheck 仅对 `demo/**/*.sh` 运行（范围自检：不得包含 `scripts/`、`hooks/`）。
    - 运行结果写入 demo-suite 的 steps/report 以便归档审计（证据落点位于 out-dir）。
  - Deps：MP1.1（demo-suite steps 记录能力）；可并行于 MP1~MP7。
  - Risks：误扩大闸门范围导致无法通过（触发“闸门范围失控”Fail）。

### MP9：文档与公开归档层对齐（不改业务逻辑）

- [x] MP9.1 更新 `demo/DEMO-GUIDE.md`：单入口用法、out-dir、产物解释、A/B 跑法、compare/降级原因码
  - Why：降低演示者心智负担，确保 demo-suite 的“可复用性”不依赖口口相传。
  - AC：AC-001（产物可解释）；AC-004/AC-005（A/B 与 compare 语义可被理解与复核）；AC-008（闸门命令可复现）。
  - Anchors：文档示例目录与 Spec Contract 1 路径布局一致；示例中明确“只归档小体积产物，禁止 raw/”。
  - Deps：MP1~MP8（以实现落地后的真实行为为准）。
  - Risks：文档与实际产物路径不一致导致误用（需同步校对）。

- [x] MP9.2 更新 `dev-playbooks/docs/长期可复用演示方案.md`：对齐本次 demo-suite 的契约、写入边界与归档约定
  - Why：作为 DevBooks 变更闭环的“长期真理”，沉淀本次约束与示例，便于后续复用与归档审计。
  - AC：AC-001~AC-008（文档化所有关键边界与验收锚点）。
  - Anchors：文档中引用的契约与锚点以本变更包 `design.md`/`spec.md` 为准（避免引用 tests/ 反推）。
  - Deps：MP1~MP8。
  - Risks：文档引用了不存在路径或过时命令（需以 repo 实际文件与 spec 为证据）。

- [x] MP9.3 新增 `docs/demos/README.md` 并明确公开归档约束（仅小体积产物、run-id 命名、禁止 raw/）
  - Why：为对外展示提供稳定落点与约束，避免把大文件/敏感信息误归档进仓库。
  - AC：AC-001（产物可归档）；AC-002（写入边界明确）；AC-008（证据落点一致）。
  - Anchors：设计文档“公开归档落点仅允许：`docs/demos/<run-id>/`”约束被清晰写明且可执行。
  - Deps：无（可并行）。
  - Risks：目录约束不清导致 raw/ 被提交进仓库（需明确禁止与示例）。

## 临时计划区（Temporary Plan Area）

> 仅用于计划外高优修复；新增时必须写清触发原因/影响面/回归锚点，并保持“只改 demo/与文档层”的红线。

- （当前无）

## 计划细化区（Details）

### Scope & Non-goals（范围与非目标）

- 允许改动：
  - `demo/**`（新增 `demo/demo-suite.sh`、修复 `demo/04-quality.sh`/`demo/05-performance.sh`、补充产物落盘与报告能力）
  - `docs/**`（仅归档层与说明文档；新增 `docs/demos/README.md`）
  - `dev-playbooks/docs/**`（方案文档对齐）
  - `README.zh-CN.md`（如需补充入口说明，按 design.md 的 Doc Impact 执行）
- 禁止改动：
  - `src/**`、`scripts/**`、`hooks/**` 的对外行为与输出契约（不改业务逻辑）
  - `tests/**`（Planner/Coder 均不得修改；测试由 Test Owner 在独立会话产出）

### Data Contracts（契约锚点与版本化）

- `metrics.json`：schema v`1.0`（Spec Contract 2.*），缺失/降级表示法（2.4）必须一致。
- `compare.json`：最小契约（Spec Contract 4.*），阈值来源与 sha256 必须可审计（4.2）。
- `scorecard.json`：schema v`1.0`（Spec Contract 7.*），4 份固定路径产物（7.1）。

### Quality Gates（质量闸门）

- Contract Tests（由 Test Owner 负责实现/运行，Planner 仅绑定锚点）：
  - CT-DS-001~CT-DS-012（见 Spec Contract Test IDs 表）
- 静态检查：
  - ShellCheck：仅 `demo/**/*.sh`（AC-008）
- 变更边界自检（建议作为实现验收锚点之一）：
  - `git diff --name-only` 的改动路径应限定在 `demo/` 与文档/归档层目录内

### Traceability（AC/CT 覆盖矩阵）

**AC 覆盖**

| AC | 覆盖任务 |
|---|---|
| AC-001 | MP1.1、MP1.2、MP1.3、MP9.1 |
| AC-002 | MP1.1、MP2.1、MP2.2、MP2.3、MP9.3 |
| AC-003 | MP3.1 |
| AC-004 | MP5.1、MP5.2、MP5.3 |
| AC-005 | MP4.1、MP5.2 |
| AC-006 | MP6.1、MP6.2、MP6.3、MP6.4 |
| AC-007 | MP7.1 |
| AC-008 | MP8.1 |

**Contract Test IDs 覆盖**

| CT | 覆盖任务 |
|---|---|
| CT-DS-001 | MP1.2 |
| CT-DS-002 | MP1.3 |
| CT-DS-003 | MP2.3 |
| CT-DS-004 | MP2.3 |
| CT-DS-005 | MP2.2、MP2.3 |
| CT-DS-006 | MP3.1 |
| CT-DS-007 | MP4.1 |
| CT-DS-008 | MP5.2 |
| CT-DS-009 | MP5.3 |
| CT-DS-010 | MP6.3 |
| CT-DS-011 | MP6.4 |
| CT-DS-012 | MP7.1 |

### Algorithm Spec（compare 最小判定逻辑，抽象伪代码）

> 目标：把 Spec Contract 4.2~4.4 的规则落为可实现、可测试的最小逻辑；更详细的阈值/方向/容忍区间以 `proposal.md` 为权威来源。

**Inputs**

- `metrics_a.json`、`metrics_b.json`
- `thresholds`（builtin 或 file；含 `direction`/`tolerance` 等元数据）
- `target_toggles`（仅对配置 A/B：允许变化的开关集合）

**Outputs**

- `compare.json`（`overall_verdict` + `metrics[]` + `thresholds.*`）

**Pseudocode（≤40 行）**

```
LOAD A, B
IF thresholds.file_specified AND parse_fail:
  EMIT compare.status="failed", reasons=["invalid_thresholds_config"]; STOP

IF comparing_config_ab:
  drift = DIFF(A.config, B.config) EXCLUDING target_toggles
  drift = drift OR DIFF(A.git.ref_resolved, B.git.ref_resolved)
  drift = drift OR DIFF(A.dataset.queries.sha256, B.dataset.queries.sha256)
  IF drift:
    EMIT overall_verdict="inconclusive", reasons+=["variable_drift_detected"]

unknown_count = 0
regression_count = 0
improvement_count = 0

FOR EACH metric_def IN thresholds.metrics:
  a = READ(A, metric_def.path)
  b = READ(B, metric_def.path)
  IF a IS null OR b IS null OR metric_def.path IN A.missing_fields OR metric_def.path IN B.missing_fields:
    verdict="unknown"; unknown_count += 1
  ELSE:
    verdict = COMPARE_BY(direction, tolerance, a, b)  # 按 Spec 4.4
    IF verdict=="regression": regression_count += 1
    IF verdict=="improvement": improvement_count += 1
  EMIT metric verdict

IF unknown_count > 0:
  EMIT overall_verdict="inconclusive"
ELSE IF regression_count > 0:
  EMIT overall_verdict="regression"
ELSE IF improvement_count > 0:
  EMIT overall_verdict="improvement"
ELSE:
  EMIT overall_verdict="no_change"
```

### Design Backport Candidates（需回写设计）

- `design.md` 的 out-dir 示例结构包含 `<out-dir>/metrics.json` 与 `<out-dir>/report.md`；但本变更 spec/CT 使用 `<out-dir>/single/metrics.json` 与 `<out-dir>/single/report.md`（以 `specs/demo-suite/spec.md` 为准，建议回写 design 示例以消除歧义）。

### Open Questions（<=3）

1) `compare.md` 的最小呈现结构（标题/指标表/原因码/阈值指纹）是否在 `proposal.md` 中有硬性模板要求？若有，以 `proposal.md` 为准。
2) `config.devbooks_config.mode` 在本仓库场景下的期望值（`copied|generated|disabled|missing`）是否需要强制固定？若需要，需在实现前对齐 `proposal.md` 的约束。

## 断点区（Context Switch Breakpoint Area）

- Last progress:
- Current blocker:
- Next shortest path:
