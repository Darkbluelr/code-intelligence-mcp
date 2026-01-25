# 设计文档：长期可复用的 Demo Suite（演示/对比/归档）+ A/B + 指标标准化

> truth-root = `dev-playbooks/specs`；change-root = `dev-playbooks/changes`  
> 输入（Approved）：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/proposal.md`（Decision Log: Approved / Judge-6）  
> 角色视角：`Product Manager` + `System Architect`  
> 最后更新：2026-01-24  
> 总约束：本变更不修改任何业务逻辑（不改变 `src/`、`scripts/`、`hooks/` 的对外行为与输出契约），仅新增/整理演示与归档展示能力。

## Problem Context

- 现有 `demo/00-quick-compare.sh` ~ `demo/05-performance.sh` 更像“单次演示脚本集合”：入口分散、产物不统一、难以稳定复现与归档，导致演示收益难以量化与对外展示。
- 缺少可机器校验的稳定输出契约（`metrics.json`）与可读报告（`report.md`），使得版本/配置差异只能依赖人工感知，A/B 结论不可审计。
- 写入边界存在已知风险（例如脚本硬编码 change-id、系统 `/tmp` 残留等），会污染仓库与证据落点，破坏可追溯性。
- 需要同时覆盖“简单 Bug（速度）/复杂 Bug（能力）”两类代表性场景，但当前缺少可判真锚点与统一的降级/缺失表达，容易产生“主观结论”。

## Design Rationale

- 以“产物契约”作为长期复用的最小闭环：每次运行稳定输出 `metrics.json`（机器可读）+ `report.md`（人类可读），并将版本/配置/AI 双代理的对比统一收敛到 `compare.*`/`scorecard.json` 的可审计产物。
- 以 out-dir 作为唯一落盘边界：将最终产物与运行期临时/缓存/DevBooks 工作目录都约束在 out-dir 下，并配合写入边界证据，使演示结果可复现、可清理、可归档。
- 以“可审计前提”约束 A/B：要求记录 git 解析结果、隔离语义、配置/依赖/缓存/索引状态、数据集指纹与环境摘要；缺失时采用统一降级表示法，必要时对比结论判定为 `inconclusive`，避免误导性结论。
- 以单一权威来源避免契约漂移：字段清单、阈值/方向/容忍区间与 `jq -e` 校验方式以 `proposal.md` 的 “Boundaries & Contracts” 为准；design 仅描述目标、约束与验收的可观察判据。

## Trade-offs

- 选择“脚本 + Markdown/JSON 报告”而非 Web Dashboard：降低引入新服务/依赖的成本，代价是交互性与可视化能力受限。
- 选择对 `demo/` 设定独立质量闸门边界（ShellCheck 仅覆盖 `demo/**/*.sh`）：避免历史债务扩散，代价是全仓库脚本质量不在本次 DoD 内提升。
- 选择 AI 双代理 A/B 的“半自动最小闭环”（scorecard 契约 + 对比）而非全自动编排：降低噪声与维护成本，代价是需要人工触发两次独立会话并沉淀证据。
- 选择严格的隔离与审计字段要求：提升 A/B 可信度，代价是运行成本（时间/磁盘）与复杂度上升；当环境不满足依赖时需要降级并可能产出 `inconclusive`。

## Acceptance Criteria（验收标准）

> 说明：验收锚点与可执行校验命令以 `proposal.md` 的 “Boundaries & Contracts” 与 “Validation / Quality gates / Evidence location” 为准；本设计仅重申可观察的 Pass/Fail 判据。

- AC-001（标准产物，A）  
  **Pass**：任意一次 demo-suite 运行在指定 out-dir 下生成 `metrics.json` 与 `report.md`（可选 `raw/`）；且 `metrics.json` 满足 v1.0 最小契约并通过 `proposal.md` 中对应的 `jq -e` 契约校验命令。  
  **Fail**：缺少任一核心文件，或 `jq -e` 校验失败（在可用 `jq` 的前提下），或未按缺失/降级表示法输出。

- AC-002（写入边界修复，A）  
  **Pass**：已知风险点 `demo/05-performance.sh` 不再写入硬编码 change-id；并且 demo-suite 运行后可用写入边界扫描证明“out-dir 之外无新增/更新文件”，且默认无 `/tmp` 残留（允许的例外与清理/降级规则以 `proposal.md` 为准）。  
  **Fail**：发现越界写入、写入其他 change-id、或存在未声明/未清理的系统临时残留。

- AC-003（版本 A/B 可审计，A）  
  **Pass**：版本 A/B 两次运行分别产出 `run-a/metrics.json` 与 `run-b/metrics.json`（及对应 `report.md`），且每份 `metrics.json` 均包含 `proposal.md` 指定的审计字段（`git.*`/隔离信息、依赖/缓存/索引、数据集指纹、环境快照、write boundary、steps）；缺失时按降级表示法处理并可被审计。  
  **Fail**：缺失关键审计字段导致 A/B 结果不可追溯，或 dirty 规则/隔离语义未被记录。

- AC-004（配置 A/B 可审计，A）  
  **Pass**：同一 `git.ref_resolved` 下，至少两套开关配置（`context_injection_mode` 与 `cache_mode`）分别产出 `run-a/metrics.json` 与 `run-b/metrics.json`，并在 `metrics.json.config.toggles` + `config.hash` 中可追溯；compare 能证明“唯一区别来自开关”，否则 `overall_verdict=inconclusive` 且包含原因码（见 `proposal.md`）。  
  **Fail**：开关状态不可追溯，或 compare 无法识别变量漂移/无法给出可审计的不可下结论。

- AC-005（`compare.*` 契约闭合，A）  
  **Pass**：由两份 `metrics.json` 生成 `compare/compare.json` 与 `compare/compare.md`，并满足 `proposal.md` 定义的：指标方向、阈值/容忍区间来源与指纹（sha256）、缺失字段处理、回归/提升判定规则；`compare.json` 通过 `proposal.md` 中对应的 `jq -e` 契约校验命令。  
  **Fail**：缺失对比产物、阈值来源不可追溯、或 verdict 规则与契约不一致。

- AC-006（复杂/简单双场景可判真，B）  
  **Pass**：简单与复杂两类场景均具备固定输入与“可在目标仓库事实中判真”的期望锚点；且以下固定参数在 `metrics.json` 中可审计：`metrics.diagnosis.simple.candidates_limit`、`metrics.diagnosis.simple.expected_hit_rank`（未命中可为 `null`）、`metrics.diagnosis.complex.call_chain.depth`、`metrics.diagnosis.complex.call_chain.direction`、`metrics.diagnosis.complex.impact.depth`。锚点命中与降级必须在 `metrics.json` 中被机器可读表达（`has_expected_hit` / `missing_fields[]` / `reasons[]`），且与 `report.md` 的降级说明一致。  
  **Fail**：锚点不可判真、或固定参数不可审计、或只给主观结论无可核验证据、或降级/缺失未被机器可读表达。

- AC-007（AI 双代理 A/B 可选且可审计，A）  
  **Pass**：AI A/B 默认可选；`metrics.json.ai_ab.status` 取值限定为 `executed|skipped`。未执行时必须为 `skipped` 且 `ai_ab.skipped_reason` 必填，`compare.json.overall_verdict` 不受其影响。若执行，`ai_ab.status="executed"` 且 `ai_ab.skipped_reason` 为空或缺省；`scorecard.json` 满足最小契约（字段/证据/变量清单/评分规则）并通过 `proposal.md` 中对应的 `jq -e` 契约校验命令；且 `anchors[]` 必须包含 `evidence_path` 与 `check_command` 以支持可复核审计；其结论可被纳入同一 compare 机制（允许 `inconclusive`，但禁止无证据的主观结论）。  
  **Fail**：`ai_ab.status` 取值不在 `executed|skipped`，或未执行却缺少 `ai_ab.skipped_reason`，或执行后 scorecard 缺少关键审计字段/锚点证据字段，或无法被机器校验。

- AC-008（质量闸门可复现，A）  
  **Pass**：仅对 demo-suite 相关脚本执行 ShellCheck（`demo/` 目录树下所有 `*.sh`，不包含 `scripts/*.sh`/`hooks/*.sh`）并可重复执行通过；且证据落点与最小结构满足 `proposal.md` 的要求。  
  **Fail**：闸门范围失控（误纳入历史债务），或命令不可重复执行/不通过，或证据落点不符合约定。

## What（做什么）

### 目标与范围（Goals / Scope）

- 将现有 `demo/00-quick-compare.sh` ~ `demo/05-performance.sh` 升级为“长期可复用的 demo suite 资产”：同一入口、同一输出契约、可对比、可归档、可审计。
- 在不修改业务逻辑的前提下，新增/整理“展示层能力”：
  - 统一产物：`metrics.json`（机器可读）+ `report.md`（人类可读）作为每次运行的最小稳定输出。
  - A/B：版本 A/B + 配置 A/B 的自动化运行与对比产物（`compare.json` + `compare.md`）。
  - AI 双代理 A/B：仅做“半自动结果采集与对比契约”（scorecard），覆盖 2 个代表性任务（简单/复杂），不做脚本自动驱动两 AI 编码编排系统。
- 修复并收敛写入边界：确保最终产物只落在 out-dir，且默认不产生系统 `/tmp` 残留与“散落文件”。

### 非目标（Non-goals）

- 不修改 `src/`、`scripts/`、`hooks/` 的对外行为与输出契约；不引入业务 API/Schema/Event 变更。
- 不做 Web Dashboard；输出仅为终端脚本 + Markdown/JSON 报告。
- 不做“脚本自动并行驱动两个 AI 编码对比”的全自动系统（避免把演示体系变成高耦合编排系统）。

### Demo Suite 入口（单入口）

- 统一入口：`demo/demo-suite.sh`
  - 职责：编排并运行 demo 维度脚本（覆盖现有 00~05），记录每一步的 `status`/`duration_ms`/关键摘要（若可得），并生成标准化产物。
  - 兼容性：保留现有 `demo/00-*.sh` ~ `demo/05-*.sh` 可单独运行（不破坏既有使用习惯）。
  - out-dir 传入与默认值：支持显式 out-dir（`--out-dir` 或 `CI_DEMO_OUT_DIR`）；未指定时默认落点为 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/<run-id>/`。

### 产物目录结构（out-dir 契约落地）

> out-dir 的写入边界、安全约束、`/tmp` 策略与“如何证明最终产物只在 out-dir”的可执行检查方式，以 `proposal.md` 的 “写入边界（out-dir / 临时目录 / /tmp）” 为准。

**每次运行的 out-dir 最小结构**（路径稳定、内容可变）：

```text
<out-dir>/
  metrics.json
  report.md
  raw/                                   # 可选：原始 JSON/终端日志等追溯材料（不得作为 compare 的唯一数据源）
  compare/                               # 可选：对比产物输出目录
    compare.json
    compare.md
  ai-ab/                                 # 可选：AI 双代理 A/B 半自动产物
    simple_bug/
      A/scorecard.json
      B/scorecard.json
    complex_bug/
      A/scorecard.json
      B/scorecard.json
  write-boundary/                        # 可选：写入边界可证明证据
    write-boundary-sentinel
  .tmp/                                  # 运行期临时目录（默认）
  .cache/                                # 运行期缓存目录（默认）
  .devbooks/                              # DevBooks/图/索引等工作目录（默认）
  .worktrees/                             # 版本 A/B 需要隔离时的工作区（如使用 worktree；具体策略见 proposal）
  .clones/                                # 版本 A/B 备选隔离策略的工作区（如临时 clone；具体策略见 proposal）
```

### 契约范围（metrics / compare / scorecard）

- 产物契约的权威定义：`proposal.md` 的 “Boundaries & Contracts” 小节（含 `metrics.json`、`compare.*`、`scorecard.json` 的最小契约、缺失/降级表示法、阈值/方向/容忍区间与判定规则、以及 `jq -e` 校验方式）。本设计不在此重复完整字段清单。
- 契约适用范围（边界）：
  - **仅作用于 demo-suite 的产物与报告层**；不改变任何 MCP 工具的输出契约，不改变 `scripts/*.sh` 与 `hooks/*.sh` 的行为。
  - `schema_version` 的演进遵循 `proposal.md` 约定（MAJOR=breaking、MINOR 仅新增可选字段/指标且不得改变既有字段语义）。

### A/B 对比语义（版本 / 配置 / AI 双代理）

- 版本 A/B（全自动）  
  - 输入：同一目标与数据集，对比 `git ref A` vs `git ref B` 的 `metrics.json`。  
  - 输出：`compare/compare.json` + `compare/compare.md`，并包含可审计的阈值来源与指纹。  
  - 审计要求与隔离语义：以 `proposal.md` 的 “版本 A/B 语义（ref 输入 / dirty 规则 / 隔离 / 依赖-缓存-索引策略）” 为准。

- 配置 A/B（全自动）  
  - 输入：同一 `git.ref_resolved` 下，对比至少两个可控开关（`context_injection_mode`、`cache_mode`），并坚持“唯一区别控制原则”。  
  - 输出：同版本 A/B（`compare.*`），且 compare 必须能识别变量漂移并在必要时判定 `overall_verdict=inconclusive`（含原因码，见 `proposal.md`）。  
  - `.devbooks/config.yaml` 的隔离与审计策略：以 `proposal.md` 为准，必须在 `metrics.json.config.devbooks_config.*` 中可追溯。

- AI 双代理 A/B（半自动，最小闭环）  
  - 定位：不追求全自动编排，仅提供可复用的 scorecard 契约与对比机制，支持两次独立 AI 会话结果沉淀为 `scorecard.json` 并纳入 compare。  
  - 默认可选：未执行时必须在 `metrics.json` 中记录 `ai_ab.status="skipped"` 与 `ai_ab.skipped_reason`，且 `compare.json.overall_verdict` 不受其影响。  
  - 可审计锚点：`scorecard.json.anchors[]` 必须包含 `evidence_path` 与 `check_command`，用于可复核校验。  
  - 覆盖任务：仅 `simple_bug` 与 `complex_bug` 两类代表性任务（见 `proposal.md` 的场景契约与 scorecard 契约）。

### 公开归档（对外展示）

- 公开归档落点仅允许：`docs/demos/<run-id>/`。  
  - 仅允许存放小体积 `metrics.json`/`report.md`/`compare.*`；不允许 raw 大文件。  
  - 归档目录结构与命名建议以 `proposal.md` 的归档约定为准。

## Constraints（约束）

### 红线（GIP）

- 不修改任何业务逻辑：不改变 `src/`、`scripts/`、`hooks/` 的对外行为与输出契约；本变更仅触达演示编排与报告层（主要在 `demo/` 与文档/归档层）。
- 不扩大质量闸门范围：ShellCheck 的 DoD 范围严格限定为 `demo/` 目录树下 `*.sh`（见 `proposal.md` 的 AC-008）。

### 写入边界（out-dir / 临时目录 / /tmp）

- out-dir 是唯一最终落盘根目录，默认落点为变更包 evidence 子目录；禁止写入仓库根、其他 change-id 目录、或系统 `/tmp` 作为最终落点。
- out-dir 必须是目录路径且满足安全约束（禁止空/`.`/`..`、禁止符号链接）；临时/缓存/DevBooks 工作目录默认必须位于 `<out-dir>` 之下（`.tmp/`、`.cache/`、`.devbooks/`）。
- `/tmp` 默认不允许；如因外部工具必须使用 `/tmp`，仅允许带 `run_id` 前缀并要求退出清理；清理失败必须按 `proposal.md` 规则降级并写入原因码。

### 可审计与可复现（A/B 的可信前提）

- 任意 run 必须输出可审计元信息（git/dataset/environment/config/write_boundary/steps），并遵循一致的缺失/降级表示法；否则结果不得用于自动化 A/B 结论（应判定 `inconclusive` 或 `degraded`，规则以 `proposal.md` 为准）。
- compare 必须记录阈值来源（file/builtin）与内容 sha256；阈值文件不可解析必须失败并给出稳定原因码。

### 依赖与降级策略

- 必需：Bash（可运行 demo-suite）。
- 推荐：`git`（ref 解析与版本对比审计）、`jq`（契约校验与 JSON 摘要）、`shellcheck`（质量闸门）。
- 可选：`sqlite3`/图数据库/CKB MCP 等；缺失时允许降级继续输出，但必须在 `metrics.json` + `report.md` 中显式标记并可审计。

### Spec 真理影响（追溯性声明）

- 本次变更不修改 `dev-playbooks/specs/**` 中任何既有能力规格；新增的仅为 demo-suite 产物契约，权威定义位于本变更包的 `proposal.md`（Boundaries & Contracts）。

## Variation Points（变体点）

> 目的：把“允许变化、但必须可审计/可复现”的参数显式列出，避免 A/B 结论被隐含变量污染。

- Variation Point：`out-dir`（最终落盘根目录）与 `run-id`（目录命名）  
  - 影响：目录布局稳定性、可归档性、写入边界证据落点。
- Variation Point：运行模式 `single | ab-version | ab-config`  
  - 影响：产物路径（`single/`、`ab-version/*`、`ab-config/*`）与 compare 产物是否生成。
- Variation Point：阈值配置来源（builtin vs file）  
  - 触发：`CI_DEMO_COMPARE_THRESHOLDS` 指向文件时；不可解析必须失败并给稳定原因码。
- Variation Point：AI 双代理 A/B 是否执行  
  - 表达：`metrics.json.ai_ab.status = executed|skipped`，`skipped_reason` 在 `status=skipped` 时必填。
- Variation Point：依赖与降级  
  - 依赖缺失（`jq`/`git`/`shellcheck`/`sqlite3` 等）必须反映为 `metrics.json.status/degraded/reasons/missing_fields`，并与 `report.md` 一致。

## Documentation Impact（文档影响）

### 需要更新/新增的文档

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| `dev-playbooks/docs/长期可复用演示方案.md` | 与本次落地的 demo-suite 入口、out-dir 写入边界、产物契约与归档约定对齐 | P0 |
| `demo/DEMO-GUIDE.md` | 补充 demo-suite 单入口、A/B 跑法与产物解释（面向演示者） | P0 |
| `README.zh-CN.md` | 增补 demo-suite 快速入口与“输出在 out-dir/可公开归档在 docs/demos/”的说明（面向首次使用者） | P1 |
| `docs/demos/README.md`（新增） | 说明公开归档目录的约束（仅小体积产物、run-id 命名）与示例结构 | P2 |

## Architecture Impact（架构影响）

### 无架构变更

- [x] 本次变更不影响模块边界、依赖方向或组件结构
- 原因说明：本变更仅新增/整理演示编排与报告产物（主要位于 `demo/` 与文档/归档层）；不修改 `src/`/`scripts/`/`hooks/` 的对外行为，不引入新服务或新外部系统，也不改变现有依赖方向。
