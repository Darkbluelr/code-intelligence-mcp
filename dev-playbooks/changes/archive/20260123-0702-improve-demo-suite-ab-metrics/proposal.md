# Proposal: 长期可复用的 Demo Suite（演示/对比/归档）+ A/B + 指标标准化

> truth-root = `dev-playbooks/specs`  
> change-root = `dev-playbooks/changes`  
> 产物位置：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/proposal.md`  
> Status: Pending（已按 Judge-2 必须修改项修订为 Proposal v3，待再裁决）  
> 约束：本变更**不修改任何业务逻辑**（不改 `src/`、`scripts/`、`hooks/` 的行为），仅新增/整理演示与归档能力（脚本、文档、可复用报告/指标输出、对比机制）。

## Why

- 问题（现状痛点）
  - 现有 demo 脚本已覆盖多个维度，但缺少“长期复用”的关键要素：**固定输出契约**（`metrics.json` + `report.md`）与**版本/配置对比报告**（差异表、阈值判定、可归档目录结构）。
  - `demo/05-performance.sh` 存在硬编码输出路径：`OUT_DIR="dev-playbooks/changes/20260122-verify-metrics/evidence"`，会把演示输出写入与当前变更无关的 change-id，破坏可复现与可追溯。
  - 目前 demo 更像“单次演示脚本集合”，缺少“统一编排入口 + 统一产物 + 可对比归档”的体系化闭环，导致升级收益难以量化与对外展示。
  - 演示场景覆盖不完整：需要同时覆盖
    - **复杂 Bug（能力）**：需要多工具协作（定位 → 调用链 → 影响面）才能清晰呈现价值。
    - **简单 Bug（速度）**：以最短路径展示“更快得到可行动线索/更快收敛”。
  - A/B 机制不清晰：当前只能人工感知差异，缺少可重复的 A/B 运行与对比产物。

- 目标（要达成的结果）
  - 把 `dev-playbooks/docs/长期可复用演示方案.md` 落地为一个**长期可复用的演示/对比/归档体系**：同一脚本、同一数据集、同一目标仓库，输出标准化产物并可跨版本对比。
  - 明确并落地 A/B 机制（自动化优先）：**版本 A/B + 配置 A/B 全自动**，AI 双代理 A/B 仅做“半自动、可复用、低屎山”的最小闭环。
  - 在不改业务逻辑的前提下，把演示从“看热闹”升级为“可量化、可归档、可对比”的工程资产。

## What Changes

- In scope（要做）
  - 统一输出契约（长期复用核心）
    - 每次演示运行产出最小、稳定的两类核心文件：
      - `metrics.json`：机器可读、用于 A/B 与版本对比（含 `schema_version`、`run_id`、`git_ref`、环境信息、分维度指标与耗时）。
      - `report.md`：人类可读、用于对外展示与归档（含环境摘要、关键命令、关键结果、降级说明、对比结论）。
    - 支持在同一输出目录下附带 `raw/`（可选）：收集 demo 各步骤原始 JSON 输出与终端日志，便于追溯。

  - Demo Suite 的统一编排入口
    - 提供一个“单入口”运行全维度 demo（覆盖 `demo/00-quick-compare.sh` ~ `demo/05-performance.sh`），并为每一步记录：
      - `status`（success/degraded/failed）、`duration_ms`、关键字段摘要（例如 benchmark 的 `mrr_at_10`、`recall_at_10`、`p95_latency_ms`）。
    - 保持现有 demo 脚本可单独运行（避免破坏用户习惯），但引入统一的 out-dir 规范与产物归集策略。

  - A/B 对比机制（推荐默认：两层）
    - **自动化 A/B（本次必做）**
      - 版本 A/B：同一目标与数据集，对比 `git ref A` vs `git ref B` 的 `metrics.json`，输出 `compare.md + compare.json`（差异表 + 阈值判定）。
      - 配置 A/B：同一 `git ref` 下，对比“有/无上下文注入”“有/无预热/缓存”等可控开关的差异（以 demo/runner 方式统一执行并对比）。
    - **AI 双代理 A/B（本次只做最小闭环，半自动）**
      - 不在脚本里自动驱动/并行运行两个 AI 进行编码（高噪声 + 高耦合 + 容易屎山）。
      - 仅提供可复用的“结果采集与对比契约”（scorecard 结构 + report 模板 + 对比生成器），用于把两次独立 AI 会话的结果沉淀为 `metrics.json + report.md` 并纳入对比报告。
      - 覆盖范围：**只覆盖 2 个代表性任务**（见下方“复杂/简单 Bug 双场景”），避免全量 A/B 造成维护负担与结论不可信。

  - 复杂/简单 Bug 双场景（能力 + 速度）
    - 简单 Bug（速度）：以“单一错误信息 → 快速定位候选”呈现价值（示例输入沿用 demo/02-diagnosis.sh：`TypeError: Cannot read property 'user'`）。
    - 复杂 Bug（能力）：以“错误信息/符号 → 调用链 → 影响面”呈现价值（示例符号沿用 demo/02-diagnosis.sh：`handleToolCall`，并结合影响分析输出）。
    - 两类场景都必须在 `metrics.json` 中有可比较字段（例如 `duration_ms`、`candidates_count`、`has_expected_hit`、`degradation_flags`）。

  - 修复演示输出路径与写入边界
    - 修复 `demo/05-performance.sh` 的硬编码 change-id 输出路径，改为：**只写入显式指定的 out-dir**（默认不写入任意 `dev-playbooks/changes/<other-id>/`）。
    - Demo Suite 运行过程不得产生“散落文件”（例如无意写入项目根目录、`/tmp` 仅允许作为临时中间产物且不得作为最终归档位置）。

  - 归档约定（长期复用）
    - 定义一个可版本化的归档目录结构（推荐：`docs/demos/<run-id>/` 或 `docs/demos/<tag-or-date>/`），用于存放可公开的 `metrics.json`、`report.md` 与对比报告。
    - 变更内的可验证证据（建议）放在：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/`，其中包含至少两次运行（A/B）与对比产物。

- Out of scope（不做 / Non-goals）
  - 不修改任何 MCP 工具行为与核心脚本逻辑：不改 `src/`、`scripts/`、`hooks/` 的对外行为与输出契约（本变更只做“外部演示编排与报告层”）。
  - 不做 Web Dashboard（可视化界面）；只做终端脚本 + Markdown/JSON 报告。
  - 不做“脚本自动并行驱动两个 AI 编码对比”的全自动系统（避免把演示系统变成编排屎山）。
  - 不引入大型外部演示仓库的 vendoring；默认目标仓库可先用本仓库自举，外部仓库仅作为可选扩展（由后续变更处理）。

- Impact scope（模块/能力/契约/不变量）
  - 受影响目录：`demo/`（演示脚本与统一编排）、`docs/`（归档与报告落点）、`dev-playbooks/docs/`（演示方案落地指引的引用与对齐）。
  - 外部契约：无（新增的仅为演示产物契约：`metrics.json`/`report.md`/对比报告格式）。
  - 数据不变量：无（不改业务数据、不引入迁移）。

## Boundaries & Contracts（Proposal v2：闭合 Judge-1 必须项）

> 本节是本提案的“可审计契约层”：边界 + 最小 Schema + 判定规则 + 可执行验收锚点。目标是把演示资产从“可跑”升级到“可复用/可对比/可归档/可审计”。

### 写入边界（out-dir / 临时目录 / /tmp）

- out-dir 定义
  - Demo Suite 每次运行必须接收一个 out-dir 作为“唯一最终落盘根目录”（推荐参数：`--out-dir`；或环境变量：`CI_DEMO_OUT_DIR`）。
  - 所有最终产物（`metrics.json`、`report.md`、`compare.json`、`compare.md`、AI scorecard 等）与运行期缓存/临时文件，必须都位于 out-dir 下（不允许写入仓库根、其他 change-id、或系统 `/tmp` 作为最终落点）。
- out-dir 规则（默认落点 + 安全约束）
  - 若未显式指定 out-dir，默认落点必须为：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/<run-id>/`（确保验收证据落在变更包内）。
  - out-dir 必须是目录路径；禁止为空/`.`/`..`；禁止指向符号链接（避免越界写入与证据漂移风险）。
  - 允许的“公开归档”落点仅限：`docs/demos/<run-id>/`（仅存放小体积 `metrics.json`/`report.md`/`compare.*`；不允许 raw 大文件）。
- 临时目录策略（默认不触碰系统 /tmp）
  - 默认临时目录：`<out-dir>/.tmp/`
  - 默认运行期缓存目录：`<out-dir>/.cache/`
  - 默认 DevBooks 工作目录（图/子图 DB 等）：`<out-dir>/.devbooks/`
  - 要求：运行 Demo Suite 时必须将 `TMPDIR`、`CACHE_DIR`、`DEVBOOKS_DIR` 重定向到上述 out-dir 子目录，避免落到系统 `/tmp` 或仓库根的 `.devbooks/`。
- `/tmp` 策略（默认：不允许）
  - 默认不允许把任何文件写入系统 `/tmp`（必须覆盖已知风险点：`demo/04-quality.sh` 当前写入的 `/tmp/ci-drift-snapshot.json`）。
  - 若某些外部工具强制使用系统 `/tmp`（极少数场景），仅允许使用带 `run_id` 前缀的路径（例如 `/tmp/ci-demo-<run-id>-*`），并必须在退出时清理；清理失败必须在 `metrics.json` 中标记 `degraded=true` 并写入 `reasons[]`（例如 `tmp_leak_detected`）。
- “如何证明最终产物只在 out-dir”的可执行检查方式（不依赖 git ignore）
  - 约定：以下命令**从仓库根目录执行**，且 `<out-dir>` 使用“相对仓库根目录的路径”（不带 `./` 前缀），避免 `find -path` 前缀不一致导致 out-dir 排除失效误报。
  - 运行前在 out-dir 写入哨兵文件（统一落点）：`mkdir -p "<out-dir>/write-boundary" && touch "<out-dir>/write-boundary/write-boundary-sentinel"`
  - 运行后检查 out-dir 之外是否有新增/更新文件（示例命令；预期输出为空；推荐 `-prune` 排除 out-dir 目录树）：
    - `find . -path "./.git" -prune -o -path "./node_modules" -prune -o -path "./<out-dir>" -prune -o -type f -newer "<out-dir>/write-boundary/write-boundary-sentinel" -print`
  - 运行后检查系统临时残留（默认要求不存在）：
    - `test ! -e /tmp/ci-drift-snapshot.json`
    - `find /tmp -maxdepth 1 -name "ci-demo-<run-id>-*" -print`（预期为空）

### 版本 A/B 语义（ref 输入 / dirty 规则 / 隔离 / 依赖-缓存-索引策略）

- `ref` 输入形式（必须可解析为 commit）
  - 支持：commit SHA（全/短）、tag、branch（本地）。
  - 解析规则：必须可被 `git rev-parse "<ref>^{commit}"` 解析为 commit；解析失败则该 run 视为 `failed`（或 `degraded`，取决于 runner 策略，但必须在 `metrics.json.reasons[]` 明确写出 `invalid_git_ref`）。
  - `metrics.json` 必须记录：
    - `git.ref_input`：原始输入
    - `git.ref_resolved`：解析后的 40 位 commit SHA
    - `git.describe`：`git describe --always --dirty`（可选；若不可得则置空并记录原因）
- dirty working tree 规则（目标：可复现 + 可审计）
  - 版本 A/B 的每个 ref 必须在隔离工作目录中运行，且该目录必须是 clean（不得夹带本地修改）。
  - 若无法保证 clean（例如误用当前工作区直接 checkout），则该 run 必须标记 `degraded=true`，并在 `metrics.json` 写入：`git.dirty=true` + `reasons[]=["dirty_worktree"]`（并明确该结果不得用于自动化 A/B 结论）。
- 隔离策略（概念层即可，但必须可审计）
  - 推荐默认：`git worktree`（每个 ref 一个 worktree，目录位于 `<out-dir>/.worktrees/<label>/`），避免污染当前工作区。
  - 备选：临时 clone（目录位于 `<out-dir>/.clones/<label>/`），更隔离但更慢。
  - `metrics.json` 必须记录：`git.isolation.strategy`（`worktree|temp_clone|in_place`）与 `git.isolation.workdir`（相对 out-dir 的路径）。
- `.devbooks/config.yaml` 隔离与审计（必须；确保 compare 可自证“同环境/同配置”）
  - 背景事实：`.devbooks/config.yaml` 在本仓库被 `.gitignore` 忽略，但可能被 hooks/脚本读取；隔离工作目录若缺失/漂移，会导致 A/B 差异不可解释。
  - 策略（推荐默认：`copied`）
    - 允许模式：`copied|generated|disabled|missing`（必须在产物中可审计；不得“隐式存在/隐式缺失”）。
    - `copied`：若在启动 runner 的仓库根目录存在 `.devbooks/config.yaml`，则必须将其复制到隔离工作目录的 `.devbooks/config.yaml`，并记录内容 hash。
    - `missing`：若启动时不存在该文件，则隔离工作目录必须同样不存在，并记录 `missing=true`。
    - `generated|disabled`：若选择生成/禁用策略，必须在 `metrics.json` 中记录生成来源/禁用方式，并记录最终内容 hash（或声明 `missing=true`）。
  - Compare 审计规则（最小闭合）
    - 版本 A/B 与配置 A/B 均必须保证 `config.devbooks_config.sha256` 相同（或都 `missing=true`）；否则 `overall_verdict=inconclusive`，原因码建议为 `devbooks_config_drift`。
- 依赖/缓存/索引策略（必须落进 `metrics.json`，否则 A/B 不可审计）
  - 依赖安装
    - 默认：每个 ref 的依赖在其隔离工作目录内自洽（`node_modules` 不跨 ref 共享）。
    - 若允许复用缓存（加速），必须以 lockfile 指纹为条件，并记录：`deps.lockfile_path`、`deps.lockfile_sha256`、`deps.install_strategy`（`fresh|reuse_by_lockfile`）。
  - 缓存与索引隔离
    - 任意缓存/索引（例如 `.ci-cache`、`.devbooks` 图数据库、embedding 索引）必须位于 out-dir 下，并以 `ref_resolved + dataset_fingerprint + config_hash` 作为 scope key（避免 A/B 污染）。
    - `metrics.json` 必须记录：`cache.policy`（`cold|warm`）、`cache.scope_key`、`cache.dir`；以及 `index.state`（`missing|ready|rebuilt`）、`index.dir`、`index.scope_key`。

### 配置 A/B 语义（至少 2 个开关 + 默认值 + “唯一区别”控制原则）

- 开关 1：`context_injection_mode`
  - 枚举：`on | off`
  - 默认：`on`
  - 语义：是否启用“上下文注入相关步骤/输出”（例如将 context-injection 的产物摘要写入 `report.md`，并把其开关状态写入 `metrics.json`）。
- 开关 2：`cache_mode`
  - 枚举：`cold | warm`
  - 默认：`cold`（对比更可解释；warm 作为对照/体验优化）
  - 语义：
    - `cold`：该 run 开始前保证 out-dir 内缓存/索引目录为空或使用全新 scope（避免历史缓存影响结果）。
    - `warm`：允许复用同 scope 的缓存/索引（仍必须保证 scope 由 ref+dataset+config 唯一确定）。
- 变量控制原则（配置 A/B 必须满足，否则 compare 必须判定为 `inconclusive`）
  - A/B 必须在同一 `git.ref_resolved`、同一 `dataset.fingerprint`、同一 `environment` 下运行；除目标开关外，其他配置必须完全一致。
  - compare 必须在 `compare.json` 中显式列出“保持一致的变量清单”与“检测到的差异清单”；若差异清单非空，则 `overall_verdict=inconclusive`。
- 开关状态必须写入 `metrics.json`
  - `config.toggles.<name>.value`（必填）
  - `config.toggles.<name>.source`：`default|env|cli|config_file`（必填）
  - `config.hash`：对“除 out-dir 以外的配置”做 hash，用于审计与 compare（必填；建议覆盖 `config.toggles` + `.devbooks/config.yaml` 的可审计状态）

### `metrics.json` 最小契约（必填/可选、缺失/降级、schema_version、数据集指纹、环境快照、校验方式）

- `schema_version` 演进策略
  - `MAJOR.MINOR` 字符串（例如 `1.0`）。
  - 规则：MAJOR 变化 = breaking（compare 工具只保证同 MAJOR 兼容）；MINOR 只能新增可选字段或新增可比较指标（不得改变既有字段语义）。
- 顶层必填字段（v1.0）
  - `schema_version`（string）
  - `run_id`（string，稳定且可用于目录命名）
  - `generated_at`（string，ISO-8601）
  - `status`（`success|degraded|failed`）
  - `degraded`（boolean，`status=="degraded"` 时必须为 true）
  - `reasons`（string[]，缺失/降级/失败原因的稳定编码集合；允许为空数组）
  - `git.ref_input`（string）、`git.ref_resolved`（string）、`git.dirty`（boolean）、`git.isolation.strategy`（string）、`git.isolation.workdir`（string）
  - `dataset.queries.path`（string）、`dataset.queries.line_count`（number）、`dataset.queries.sha256`（string）
  - `environment.os`（string）、`environment.arch`（string）、`environment.node`（string）
  - `config.toggles`（object，至少包含 `context_injection_mode` 与 `cache_mode` 两个键）与 `config.hash`（string）
  - `config.devbooks_config.mode`（`copied|generated|disabled|missing`）、`config.devbooks_config.path`（string 或 null）、`config.devbooks_config.sha256`（string 或 null）、`config.devbooks_config.missing`（boolean）
  - `write_boundary.out_dir`（string）、`write_boundary.tmp_dir`（string）、`write_boundary.allow_system_tmp`（boolean）
  - `metrics.demo_suite.total_duration_ms`（number）
  - `steps[]`（array，至少包含 step `id`/`status`/`duration_ms`；用于审计与 compare）
- 顶层可选字段（v1.x 允许按需扩展）
  - `environment.tools`（工具版本快照，如 `jq/rg/shellcheck/sqlite3` 等，缺失则置空并写入 `reasons[]`）
  - `metrics.performance.*`、`metrics.quality.*`、`metrics.diagnosis.*`、`metrics.impact.*`（各维度指标；缺失时按“缺失表示法”处理）
  - `ai_ab.status`（`executed|skipped`）与 `ai_ab.skipped_reason`（string 或 null；未执行 AI A/B 时必填）
  - `missing_fields[]`：列出缺失指标字段路径（例如 `metrics.performance.mrr_at_10`），用于 compare 的缺失处理
- 缺失/降级表示法（必须一致）
  - 缺失指标：对应值置为 `null`，并在 `missing_fields[]` 中列出字段路径，同时在 `reasons[]` 中包含稳定原因编码（例如 `missing_jq`、`impact_db_missing`、`benchmark_report_missing`）。
  - 降级：`status="degraded"` 且 `degraded=true`，并在 `reasons[]` 写明原因；`report.md` 必须同步呈现“降级说明”。
- 数据集指纹（必填；避免“假对比”）
  - 至少包含：`dataset.queries.path` + `dataset.queries.line_count` + `dataset.queries.sha256`（sha256）。
- 环境快照字段（必填最小集）
  - `environment.os`、`environment.arch`、`environment.node`
  - 建议额外记录到 `environment.tools`：`git`、`jq`、`rg`、`shellcheck`、`sqlite3` 的 `available` 与 `version`（缺失则降级并记录原因）。
- 契约校验方式（可执行；最小可跑）
  - `jq -e '(.schema_version|type==\"string\") and (.run_id|type==\"string\") and (.git.ref_resolved|type==\"string\") and (.dataset.queries.sha256|type==\"string\") and (.config.hash|type==\"string\") and (.config.devbooks_config.mode|type==\"string\") and (.metrics.demo_suite.total_duration_ms|type==\"number\") and (.steps|type==\"array\")' "<out-dir>/metrics.json" >/dev/null`

### `compare.json` / `compare.md` 契约（方向、阈值/容忍区间、缺失处理、回归/提升判定）

- 输入/输出
  - 输入：两份 `metrics.json`（A、B）+ 可选阈值配置（优先级：`CI_DEMO_COMPARE_THRESHOLDS` 指向的 JSON 文件 > 内置默认阈值）。
  - 输出：`compare.json`（机器可读）+ `compare.md`（人类可读），均位于 out-dir 下（推荐：`<out-dir>/compare/`）。
- 指标方向（higher/lower is better）
  - 必须在 `compare.json.metrics[]` 中逐项写入 `direction`，至少覆盖本提案要求的核心指标：
    - `metrics.performance.mrr_at_10`：higher is better
    - `metrics.performance.recall_at_10`：higher is better
    - `metrics.performance.precision_at_10`：higher is better
    - `metrics.performance.p95_latency_ms`：lower is better
    - `metrics.demo_suite.total_duration_ms`：lower is better
    - `metrics.diagnosis.simple.has_expected_hit`：true is better（布尔方向）
    - `metrics.diagnosis.complex.has_expected_hit`：true is better（布尔方向）
- 阈值/容忍区间配置位置（必须可追溯）
  - 若提供阈值文件（`CI_DEMO_COMPARE_THRESHOLDS=<path>`），则 compare 必须读取该文件；若文件不存在/不可解析为 JSON，则 compare 必须失败（`status="failed"`）并写入 `reasons[]=["invalid_thresholds_config"]`。
  - 若未提供阈值文件，则 compare 必须使用“内置默认阈值”（可审计），并将实际使用的阈值内容写入 `compare.json.thresholds.used`。
  - 无论阈值来源为何，`compare.json` 必须写入：
    - `thresholds.source`：`file|builtin`
    - `thresholds.path`：string 或 null
    - `thresholds.sha256`：对“阈值内容本身”的 sha256（确保报告可审计）
- 内置默认阈值（可选加分；建议最小集，口径为“绝对值 tolerance”，单位见字段名）
  - `metrics.performance.mrr_at_10`：`tolerance=0.01`
  - `metrics.performance.recall_at_10`：`tolerance=0.01`
  - `metrics.performance.precision_at_10`：`tolerance=0.01`
  - `metrics.performance.p95_latency_ms`：`tolerance=50`（ms）
  - `metrics.demo_suite.total_duration_ms`：`tolerance=5000`（ms）
  - `metrics.diagnosis.simple.has_expected_hit` / `metrics.diagnosis.complex.has_expected_hit`：`tolerance=0`（布尔不允许回归；缺失则按 `unknown` 处理）
- 缺失字段处理（必须有定义）
  - 若任一侧指标为缺失（字段不存在或值为 `null`，或在 `missing_fields[]` 中声明缺失），则该指标的 `verdict` 必须为 `unknown`，并在 `compare.md` 中显式列出“缺失指标清单 + 缺失原因”。
  - 当 `unknown` 指标数量超过阈值（默认建议：>0 即判定不可下结论；可由阈值配置覆盖），`overall_verdict` 必须为 `inconclusive`。
- 回归/提升判定规则（必须一致）
  - 对数值指标：基于 `direction` 与 `tolerance` 判定
    - `higher`：`b - a > tolerance` → improvement；`a - b > tolerance` → regression；否则 no_change
    - `lower`：`a - b > tolerance` → improvement；`b - a > tolerance` → regression；否则 no_change
  - 对布尔指标（true is better）：`false→true` = improvement；`true→false` = regression；相同 = no_change
  - `compare.json` 必须写入：`a`、`b`、`delta_abs`（数值）、`delta_pct`（数值可选）、`tolerance`、`verdict`、`reason`（可选）
- 契约校验方式（可执行；最小可跑）
  - `jq -e '(.schema_version|type==\"string\") and (.overall_verdict|type==\"string\") and (.metrics|type==\"array\")' "<out-dir>/compare/compare.json" >/dev/null`

### 复杂/简单场景契约（固定输入 + 期望命中锚点 + 允许降级条件）

> 要求：锚点必须能在“目标仓库事实”中判真（文件/符号/调用链片段/影响文件集合等），避免 `has_expected_hit` 退化为形式指标。

- 简单场景（速度）：单一错误信息 → 快速定位候选
  - 固定输入（示例，稳定且可解析）：`TypeError: Cannot read property 'user' at handleToolCall (src/server.ts:1)`
  - 可复现参数（固定值）
    - `ci_bug_locate` `limit=5`（Top-N=5，命中 rank 按返回顺序计算）
    - `metrics.diagnosis.simple.candidates_limit=5`
    - `metrics.diagnosis.simple.expected_hit_rank`：1..5；未命中则为 `null`；若候选列表因降级缺失则为 `null` 且列入 `missing_fields[]`
  - 期望命中锚点（可判真）
    - 锚点 1：`src/server.ts` 文件存在
    - 锚点 2：`src/server.ts` 内存在符号 `handleToolCall`
    - 锚点 3（工具输出锚点，若不降级）：`ci_bug_locate` 输出的 Top-N candidates 中包含 `src/server.ts`
  - 允许降级条件
    - 若 `jq` 不可用导致 `ci_bug_locate` 不可运行：允许降级，但必须在 `metrics.json` 中标记 `degraded=true`，并写入 `reasons[]=["missing_jq"]`；此时 `has_expected_hit` 必须为 `null` 且列入 `missing_fields[]`。
- 复杂场景（能力）：符号 → 调用链 → 影响面
  - 固定输入
    - 符号：`handleToolCall`
    - 影响分析目标：文件 `src/server.ts`
  - 可复现参数（固定值）
    - `ci_call_chain` `depth=3`、`direction=both`
    - `ci_impact` `depth=3`
    - `metrics.diagnosis.complex.call_chain.depth=3`
    - `metrics.diagnosis.complex.call_chain.direction="both"`
    - `metrics.diagnosis.complex.impact.depth=3`
  - 期望命中锚点（可判真）
    - 锚点 1：调用链输出中（递归任意层）存在 `file_path == "src/server.ts"`（可用 `jq '..|objects|select(.file_path?==\"src/server.ts\")'` 验真）
    - 锚点 2：影响分析输出中包含 `src/server.ts` 的影响记录（若图数据库可用）
  - 允许降级条件
    - 若缺少图数据库（例如 `<DEVBOOKS_DIR>/graph.db` 不存在）或缺少 `sqlite3`：允许降级，但必须在 `metrics.json` 中写入 `reasons[]=["impact_db_missing"]`（或更精确编码），并将 `metrics.impact.*` 置为 `null` 且列入 `missing_fields[]`。
- 随版本变化的维护策略（避免锚点失效）
  - 若 `handleToolCall` 重命名/移动：必须同步更新场景定义与期望锚点，并在 `metrics.json.scenarios.version`（可选字段）或 `report.md` 中记录“锚点变更说明”，否则 compare 的能力结论视为不可追溯。

### AI 双代理 A/B：scorecard 契约（半自动；字段/评分/证据/变量清单）

- 定位：AI 双代理 A/B 不追求全自动编排；本变更只要求“可复用的对比契约 + 可审计证据”以支持两次独立会话结果沉淀与对比。
- 执行边界（默认可选）
  - 若未执行：`metrics.json.ai_ab.status="skipped"` 且 `ai_ab.skipped_reason` 必填；`report.md` 同步摘要；`compare.json.overall_verdict` 不受 AI A/B 影响。
  - 若执行：`metrics.json.ai_ab.status="executed"`，并按固定路径产出 4 份 scorecard。
- `scorecard.json` 最小契约（schema v1.0，文件位置建议：`<out-dir>/ai-ab/<task-id>/<agent-id>/scorecard.json`）
  - 必填字段
    - `schema_version`（string，`1.0`）
    - `task_id`（`simple_bug|complex_bug`）
    - `agent_id`（`A|B`）
    - `git.ref_input`、`git.ref_resolved`（string）
    - `run.started_at`、`run.ended_at`（ISO-8601）、`run.duration_ms`（number）、`run.turns`（number）
    - `variables.fixed[]`（必须保持一致的变量清单：任务说明、时间预算、允许工具、起始代码状态/仓库、数据集）
    - `variables.varied[]`（允许变化的变量清单：模型、提示词策略、是否使用某些工具）
    - `evidence`（object，至少包含 `command_log_path`、`output_diff_path`，以及是否通过某个锚点的证据路径）
    - `anchors`（array，元素包含 `id`、`passed`、`reason`、`evidence_path`、`check_command`；禁止仅靠 `reason`）
- 评分规则（最小且可审计）
  - `passed_anchors_count`（number）= `anchors[].passed==true` 的数量
  - `score`（number）建议= `passed_anchors_count / anchors.length`（0~1）
  - compare 仅基于 `score` + 关键锚点（例如“复杂场景锚点 1/2”）给出提升/回归/不可下结论
- 契约校验方式（可执行；最小可跑）
  - `jq -e '(.schema_version==\"1.0\") and (.task_id|IN(\"simple_bug\",\"complex_bug\")) and (.agent_id|IN(\"A\",\"B\")) and (.git.ref_resolved|type==\"string\") and (.run.duration_ms|type==\"number\") and (.run.turns|type==\"number\") and (.variables.fixed|type==\"array\") and (.variables.varied|type==\"array\") and (.anchors|type==\"array\") and (all(.anchors[]; (.evidence_path|type==\"string\") and (.check_command|type==\"string\"))) and (.evidence.command_log_path|type==\"string\") and (.evidence.output_diff_path|type==\"string\")' "<out-dir>/ai-ab/<task-id>/<agent-id>/scorecard.json" >/dev/null`

## Impact

- Transaction Scope: None

- External contracts（API/Schema/Event）
  - 无业务 API/Schema/Event 变更。
  - 新增“演示产物契约”（仅对 demo suite 生效）：`metrics.json`/`report.md`/`compare.json`/`compare.md`。

- Data and migration
  - 无数据迁移、无持久化格式变更（演示产物为新增文件，不影响运行时数据）。

- Affected modules and dependencies
  - `demo/`：作为 demo-suite 的入口与编排层（现有 00~05 脚本继续保留）。
  - `docs/`：新增/扩展可公开归档目录（建议仅存放小体积 JSON/MD）。
  - 运行依赖：Bash（必需），`jq`（建议，用于 JSON 摘要与对比），`git`（建议，用于记录 `git_ref` 与生成版本对比）。

- Testing and quality gates
  - Shell 质量：新增/修改的 demo 脚本必须通过 `shellcheck`（至少覆盖 `demo/*.sh`）。
  - 可复现性：在同一环境、同一 `git_ref`、同一数据集下重复运行，`metrics.json` 的关键字段应保持稳定（允许耗时类指标有小幅波动）。
  - 写入边界：所有最终产物必须写入指定 out-dir；不得写入任何硬编码 change-id 目录。

- Value Signal and Observation:
  - 价值信号（最小集，写入 `metrics.json`）
    - `demo_suite.total_duration_ms`
    - `performance.mrr_at_10`、`performance.recall_at_10`、`performance.precision_at_10`、`performance.p95_latency_ms`（来源于现有 benchmark 输出摘要）
    - `diagnosis.simple.duration_ms`、`diagnosis.simple.candidates_count`、`diagnosis.simple.degraded`
    - `diagnosis.complex.duration_ms`、`diagnosis.complex.has_call_chain`、`diagnosis.complex.has_impact`、`diagnosis.complex.degraded`
  - 观测方式
    - 运行产物：`metrics.json`、`report.md`
    - A/B 产物：`compare.json`、`compare.md`（包含差异表与“是否回归/是否提升”的判定）

- Value Stream Bottleneck Hypothesis:
  - 当前瓶颈在“演示结果不可复用/不可对比/不可归档”，每次升级都需要人工解释与人工对比。
  - 标准化产物 + 对比报告可以把瓶颈从“讲故事”转为“读报告”，降低演示与回归验证成本。

## Risks & Rollback

- 风险
  - 指标噪声：耗时类指标受机器负载影响，导致 A/B 结论不稳定。
    - 缓解：记录环境信息（CPU/OS/Node 版本/是否开启缓存/是否有 jq），对耗时类指标采用阈值+容忍区间，并在报告中标注“噪声敏感”字段。
  - 可选依赖缺失：缺少 `jq`、CKB MCP、或 benchmark 依赖时，部分指标无法生成。
    - 缓解：demo suite 必须输出“降级标记”（`degraded: true` + `reasons[]`），并保证仍能生成 `report.md`（不因缺少可选依赖而整体失败）。
  - 归档膨胀：长期把 raw 日志/大 JSON 放入 `docs/` 会导致仓库膨胀。
    - 缓解：`docs/demos/` 只存放小体积 `metrics.json`/`report.md`/对比报告；raw 日志仅保留在变更包 `evidence/`，或按需外置存储。
  - AI 双代理 A/B 结论不可信：LLM 输出高方差，容易被“偶然性”误导。
    - 缓解：本次仅提供半自动的结果归档与对比契约，限定为 2 个代表性任务；将其定位为“演示性证据”，而非科学基准。

- Degradation strategy
  - 默认允许降级：缺少可选依赖时不阻断整套 demo；明确在 `metrics.json` 与 `report.md` 中记录降级原因与缺失项。

- Rollback strategy
  - 仅涉及文档与 demo 层脚本：回滚策略为 git revert / 恢复到上一版 demo-suite；不涉及数据回滚。

## Validation

- Candidate acceptance anchors（可执行验收方向；不写实现步骤）
  - AC-001（标准产物）：任意一次 demo-suite 运行都会在指定 out-dir 下产出 `metrics.json` 与 `report.md`（可选 `raw/`），并满足 `metrics.json` 的 v1.0 最小契约（见上文）。
  - AC-002（写入边界修复）：已知风险点 `demo/05-performance.sh` 不再写入硬编码 change-id；并满足“最终产物只在 out-dir”的边界约束。
  - AC-003（版本 A/B 可审计）：A/B 两次运行分别产出 `run-a/metrics.json`、`run-b/metrics.json`，且每份 `metrics.json` 均写入 `git.ref_input/ref_resolved/dirty/isolation`、`deps.*`、`cache.*`、`index.*`（缺失时按降级表示法处理）。
  - AC-004（配置 A/B 可审计）：同一 `git.ref_resolved` 下，两套开关配置（至少 `context_injection_mode` 与 `cache_mode`）分别产出 `run-a/metrics.json`、`run-b/metrics.json`，并在 `metrics.json.config.toggles` 中可追溯；compare 必须能证明“唯一区别来自开关”（否则 `overall_verdict=inconclusive`）。
  - AC-005（`compare.*` 契约闭合）：由两份 `metrics.json` 生成 `compare.json` 与 `compare.md`，且 compare 明确指标方向、阈值/容忍区间来源与指纹、缺失字段处理、回归/提升判定规则（见上文契约）。
  - AC-006（复杂/简单双场景可判真）：两个场景均有固定输入与可判真的期望锚点；锚点命中/降级必须在 `metrics.json` 中被机器可读地表达（`has_expected_hit`/`missing_fields`/`reasons`）。
  - AC-007（AI 双代理 A/B 可审计 + 可选）：AI A/B 默认可选；若执行则必须产出 4 份 scorecard（simple/complex × A/B）并满足最小契约；若未执行则 `metrics.json.ai_ab.status="skipped"` 且 `ai_ab.skipped_reason` 必填、`report.md` 同步说明；compare 的 `overall_verdict` 不受其影响。
  - AC-008（质量闸门可复现）：仅对 demo-suite 相关脚本执行 ShellCheck（定义为 `demo/` 目录树下所有 `*.sh`；不包含既有 `scripts/*.sh`/`hooks/*.sh`），并形成可重复执行的闸门命令与证据文件。

- Quality gates（必须给出可执行命令）
  - ShellCheck（仅本变更 demo-suite 范围；不把 `scripts/*.sh`/`hooks/*.sh` 纳入本变更 DoD）：`find demo -type f -name "*.sh" -print0 | xargs -0 shellcheck`
  - TypeScript build（回归保险）：`npm run build`
- 契约校验（metrics/compare/scorecard；scorecard 仅当 `ai_ab.status=executed`）：见上文各自的 `jq -e ...`（如 `jq` 缺失则必须走降级路径并记录原因）

- Evidence location（本变更验收证据强制落点 + 最小结构）
  - 根目录：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/`
- 最小结构（必须完整存在；ai-ab 仅当 `ai_ab.status=executed` 时要求；文件内容允许随运行变化，但路径必须一致）：
    - `gates/shellcheck.txt`
    - `gates/build.txt`
    - `gates/tool-versions.json`
    - `gates/metrics-schema.txt`
    - `gates/compare-schema.txt`
    - `gates/scorecard-schema.txt`
    - `single/metrics.json`
    - `single/report.md`
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
    - `write-boundary/write-boundary-sentinel`（哨兵文件留存，用于证明检查可复现；与检查命令同一路径/文件名）
    - `write-boundary/new-or-updated-files.txt`
    - `write-boundary/tmp-scan.txt`
    - `ai-ab/simple_bug/A/scorecard.json`
    - `ai-ab/simple_bug/B/scorecard.json`
    - `ai-ab/complex_bug/A/scorecard.json`
    - `ai-ab/complex_bug/B/scorecard.json`

## Debate Packet

> 说明：以下为“可争议点”，已给出**推荐默认决策**；不要求用户在 Proposal 阶段逐项拍板，但为 Challenger/Judge 提供审查抓手（<=7 项）。

1) 归档位置：`docs/demos/` vs `dev-playbooks/specs/_meta/**`
   - 推荐：`docs/demos/` 存放可公开的小体积产物；变更证据仍放在 change 包 `evidence/`。
2) A/B 覆盖范围：仅演示工具作用（版本/配置 A/B） vs 工具 + AI 双代理 A/B（半自动） vs 全自动双 AI 编码对比
   - 推荐：工具 + AI 双代理 A/B（半自动）；版本/配置 A/B 全自动，AI 仅做结果采集与对比契约，不做脚本自动并行编码。
3) 目标仓库策略：默认用本仓库自举 vs 默认外部开源仓库
   - 推荐：默认用本仓库自举（稳定、无需网络）；外部仓库作为可选扩展（后续变更再做）。
4) 指标稳定性：严格一致 vs 容忍区间
   - 推荐：对质量类/结构类指标追求稳定；对耗时类指标采用阈值+容忍区间，并记录环境。
5) 降级策略：缺少可选依赖即失败 vs 标记降级继续输出
   - 推荐：标记降级继续输出（保证演示可跑通），并在报告中显式呈现缺失项。
6) 归档体积策略：保留 raw 日志到 `docs/` vs 仅保留摘要
   - 推荐：`docs/` 仅保留摘要（JSON/MD），raw 日志留在 change evidence（或外置）。
7) 场景数量：全量覆盖 vs 代表性覆盖
   - 推荐：代表性覆盖（复杂+简单 2 场景）作为首版；后续按需扩展，不在本变更追求“全量 A/B”。

## Decision Log

- Decision Status: Approved
- Decision summary
  - 采用“演示编排层 + 标准产物契约 + 对比报告 + 归档目录”的最小闭环，落地长期可复用演示体系。
  - A/B 策略：版本/配置 A/B 全自动；AI 双代理 A/B 半自动且仅覆盖 2 个代表性任务（复杂+简单），不做全量与不做脚本自动驱动两 AI 编码。
  - 场景策略：同时覆盖复杂 Bug（能力）与简单 Bug（速度），并以“固定输入 + 可判真锚点 + 允许降级条件”定义可比较字段。
  - 写入边界：out-dir/临时目录/禁止系统 `/tmp` 默认策略已成文，并给出“如何证明最终产物只在 out-dir”的可执行检查。
  - 契约闭合：`metrics.json`/`compare.*`/`scorecard.json` 的最小契约、缺失/降级表示法、阈值与判定规则、以及可执行校验方式已成文。
- Questions requiring decision
  - 无（以上为推荐默认决策；如需偏离，优先在 Judge 阶段基于 Debate Packet 记录裁决与理由）。

### [2026-01-23 07:27:45 +0800] 裁决：Revise（Judge-1）

**理由摘要**：
- A/B（版本/配置/AI 双代理）的输入语义、隔离策略与变量控制未闭合，按现状难以形成可复现、可审计的对比证据。
- `metrics.json`/`compare.*` 的契约与判定规则仍偏口头（必填/可选/降级表示、阈值/方向/容忍区间、缺失字段处理），不足以支撑“读报告式”长期复用。
- 写入边界与临时文件策略未闭合（已知存在硬编码写入与 `/tmp` 残留风险点），AC-002/“无散落文件”难以验真。
- 复杂/简单场景缺少可判真的“期望命中锚点”，`has_expected_hit` 等指标可能退化为形式指标，无法支撑能力对比结论。
- 质量闸门与可执行验证命令未明确（例如 demo 脚本是否纳入 ShellCheck/CI、证据最小集与落点），AC-001~AC-005 的可执行性不足。

**必须修改项**（Revise）：
- [ ] 明确写入边界与临时目录策略：是否允许 `/tmp` 残留文件、清理要求、以及“如何证明最终产物只在 out-dir”的检查方式（需覆盖已知风险点：硬编码 change-id 写入、以及 demo 中 `/tmp` 写入行为）。
- [ ] 明确版本 A/B 的可执行语义：`ref` 输入形式（commit/tag/branch）、是否允许 dirty working tree、隔离策略（如 `git worktree`/临时 clone）、依赖安装/缓存/索引策略，并要求把 `git_ref`/dirty 状态/环境快照写入 `metrics.json`。
- [ ] 明确配置 A/B 的开关枚举（至少 2 个）与默认值：每个开关影响哪一层、如何保证“唯一区别来自该开关”、缓存/索引的隔离/清理策略，并要求开关状态写入 `metrics.json`。
- [ ] 补齐 `metrics.json` 最小契约：必填字段、可选字段、缺失/降级表示法（例如 `degraded=true` + `reasons[]`）、`schema_version` 演进策略、数据集指纹（路径/行数/hash）与环境快照字段，并给出一个可执行的契约校验方式。
- [ ] 补齐 `compare.json`/`compare.md` 契约：输入输出、指标方向（higher/lower is better）、阈值与容忍区间配置位置、字段缺失/降级时的对比行为、以及“回归/提升”判定规则。
- [ ] 为复杂/简单场景分别定义“固定输入 + 期望命中锚点 + 允许降级条件”：期望锚点需可在目标仓库中判真（文件/符号/调用链片段/影响文件集合等），并说明随版本变化的维护策略。
- [ ] 定义 AI 双代理 A/B 的 scorecard 契约：字段、评分规则、证据要求（至少包含起始 `git_ref`、命令记录/日志、输出 diff、时间/轮次、是否通过某个验证锚点），以及需要保持一致/允许变化的变量清单。
- [ ] 明确质量闸门与证据最小集：demo-suite 与 demo 脚本的 ShellCheck/lint 入口与命令、以及 `evidence/` 里最小必须包含的 A/B 运行产物与对比产物结构。

**验证要求**：
- [ ] 提供一组“单次成功运行”证据：指定 out-dir 下生成 `metrics.json` + `report.md`，并通过“契约校验方式”。
- [ ] 提供一组“版本 A/B”证据：两份不同 `git_ref` 的 `metrics.json` → 生成 `compare.json` + `compare.md`，报告包含阈值判定与结论。
- [ ] 提供一组“配置 A/B”证据：同一 `git_ref` 下两套开关配置 → 生成对比报告，并在产物中可追溯到开关状态与隔离策略。
- [ ] 提供一组“降级路径”证据：缺少可选依赖时仍产出 `metrics.json`/`report.md`，且 `degraded`/`reasons[]` 完整；对比逻辑对缺失字段的行为符合定义。
- [ ] 提供“写入边界可证明”证据：最终产物仅在 out-dir；若允许使用 `/tmp`，必须证明清理/隔离策略有效且无残留散落文件。
- [ ] 提供“质量闸门可复现”证据：demo-suite 相关脚本通过 ShellCheck（或等价 lint），且命令可在仓库内重复执行得到一致结果。

### [2026-01-23 08:15:00 +0800] Proposal v2 修订说明（Proposal Author）

- 已补齐写入边界：out-dir 规则、临时目录策略、默认禁止 `/tmp`、清理与“只在 out-dir 落盘”的可执行检查方式（覆盖已知风险点：`demo/05-performance.sh` 硬编码写入与 `demo/04-quality.sh` 的 `/tmp` 写入）。
- 已补齐版本 A/B 语义：ref 输入形式、dirty 规则、隔离策略（worktree/临时 clone）、依赖/缓存/索引策略，且相关元信息强制写入 `metrics.json`。
- 已补齐配置 A/B：至少 2 个开关（`context_injection_mode`、`cache_mode`）的枚举/默认值/“唯一区别”控制原则，并要求开关状态与 `config.hash` 写入 `metrics.json`。
- 已补齐 `metrics.json`/`compare.*`/`scorecard.json` 最小契约：必填/可选、缺失/降级表示法、`schema_version` 演进策略、数据集指纹、环境快照字段、阈值/方向/容忍区间与回归/提升判定规则、以及 `jq -e` 可执行校验方式。

### [2026-01-23 08:29:32 +0800] 裁决：Revise（Judge-2）

**理由摘要**：
- AC-008 的 ShellCheck 闸门当前定义为 `shellcheck scripts/*.sh hooks/*.sh demo/*.sh`，但在当前仓库执行会失败（例如 `scripts/show-context.sh` 存在语法解析错误），导致 DoD 不可达且会隐性放大范围。
- 写入边界的“哨兵文件命名/落点”在 v2 文档中不一致，且 `find` 排除 out-dir 的示例命令存在路径前缀匹配风险，影响可复现验真。
- A/B 隔离策略未闭合 `.devbooks/config.yaml` 的处理：该文件被 `.gitignore` 忽略且被 hooks/脚本读取，若不定义复制/禁用/审计策略，版本/配置 A/B 的“同环境”不可自证。
- `scorecard.json` 虽定义字段/评分规则，但缺少最小可执行的契约校验方式（`jq -e`/等价），与“契约层可审计”目标不一致。

**必须修改项**（Revise）：
- [ ] 收敛或重定义 AC-008 ShellCheck 闸门范围（至少聚焦 `demo/*.sh` + 本变更新增/修改脚本），或在提案中显式承诺并列出需修复的现存脚本清单与边界；确保本变更 DoD 可达且范围可控。
- [ ] 统一写入边界哨兵文件的路径与文件名：在全文（检查命令 + evidence 最小结构）统一选用 `<out-dir>/write-boundary/write-boundary-sentinel`。
- [ ] 修正写入边界检查的 `find` 示例命令：明确从哪个工作目录执行，并确保 out-dir 排除规则与 `find` 输出路径前缀一致，避免把 out-dir 内文件误判为越界写入。
- [ ] 为 `scorecard.json` 补齐最小契约校验方式（`jq -e`/等价），并把该校验纳入“质量闸门/证据最小集”的定义。
- [ ] 在版本/配置 A/B 的隔离语义中明确 `.devbooks/config.yaml` 的处理策略（复制/生成/显式禁用其影响），并要求在 `metrics.json` 中记录其 `path/hash` 或 `missing=true` 等审计字段，避免配置漂移导致对比结论不可信。

**验证要求**：
- [ ] 更新后的“质量闸门命令 + 目标文件范围”必须在仓库内可重复执行且可通过（以其声明的范围为准），并在 evidence 中留存命令与输出摘要。
- [ ] 写入边界检查（含哨兵与 out-dir 排除）必须可按文档从仓库根目录复现执行，且不会误报 out-dir 内文件；证据需能支撑“最终产物仅落在 out-dir”的结论。
- [ ] `scorecard.json` 的契约校验命令需能在最小示例文件上通过，并能在字段缺失时失败（可审计）。
- [ ] `.devbooks/config.yaml` 的隔离/审计策略需在产物（至少 `metrics.json`）中可追溯；对比报告需能解释“为何可认为两次运行处于同环境/同配置”。

### [2026-01-23 08:45:00 +0800] Proposal v3 修订说明（Proposal Author）

- 已将 AC-008/Quality gates 的 ShellCheck 范围收敛为 **仅 demo-suite 相关脚本**（定义为 `demo/` 目录树下 `*.sh`），明确不把既有 `scripts/*.sh`/`hooks/*.sh` 的历史 ShellCheck 债务纳入本变更 DoD；并补齐对应证据落点（`evidence/gates/shellcheck.txt`）。
- 已统一写入边界哨兵文件落点为 `<out-dir>/write-boundary/write-boundary-sentinel`，确保“检查命令 + evidence 最小结构”一致。
- 已修正写入边界 `find` 示例命令：明确从仓库根目录执行，并采用 `-prune` 形式排除 `./<out-dir>` 目录树，避免路径前缀不一致导致 out-dir 排除失效误报。
- 已为 `scorecard.json` 补齐最小可执行契约校验方式（`jq -e ...`），并将其纳入质量闸门/证据最小集（新增 `evidence/gates/scorecard-schema.txt`）。
- 已补齐 `.devbooks/config.yaml` 的 A/B 隔离与审计策略：定义 `copied|generated|disabled|missing` 模式，要求在 `metrics.json.config.devbooks_config.*` 记录 `path/sha256/missing`，并规定 compare 对 config 漂移的判定（`inconclusive` + `devbooks_config_drift`）。
- （可选加分）已给出 compare 内置默认阈值最小集（可被阈值文件覆盖），降低实现侧“拍脑袋选阈值”的不确定性。

### [2026-01-23 09:08:08 +0800] 裁决：Approved（Judge-3）

**理由摘要**：
- Proposal v3 已闭合 Judge-2 全部必须修改项：ShellCheck 范围收敛、写入边界哨兵统一、`find -prune` 排除 out-dir 的可复现写法、`scorecard.json` 的 `jq -e` 校验、以及 `.devbooks/config.yaml` 的隔离/审计与漂移判定。
- 质量闸门与 DoD 的范围收敛且可达：明确只对 `demo/` 目录树脚本执行 ShellCheck，不把既有 `scripts/*.sh`/`hooks/*.sh` 的历史债务纳入本变更，避免范围失控。
- 已在当前仓库验证闸门可跑且通过：`find demo -type f -name "*.sh" -print0 | xargs -0 shellcheck` 与 `npm run build` 均通过（exit 0）。
- 契约层闭合并可执行校验：`metrics.json` / `compare.*` / `scorecard.json` 的最小 schema、缺失/降级表示法、阈值/方向/容忍区间与判定规则均已成文，且给出可跑的 `jq -e` 校验命令，满足长期可复用与可审计目标。
- 写入边界与 A/B 可审计性闭合：哨兵 + 越界扫描 + 证据最小结构可支撑“最终产物仅落在 out-dir”，并通过 devbooks 配置审计字段与 drift→`inconclusive` 规则保证对比结论可信。

**验证要求**：
- [ ] 进入 Apply/Coder 前补齐并通过职责分离检查：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/design.md`（只写 What/Constraints + AC）与 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md`（只写 How）。
- [ ] 产出并归档最小证据集：单次运行的 `metrics.json` + `report.md`，以及对应 `jq -e` 校验命令与输出摘要，落在 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/`。
- [ ] 产出一组版本 A/B 与一组配置 A/B 的 `compare.json` + `compare.md`，并在 `compare.json.thresholds.*` 中记录阈值来源与 sha256；结论可复核。
- [ ] 兑现写入边界可证明：按提案命令从仓库根目录执行越界扫描，不误报 out-dir 内文件；留存 `write-boundary/*` 证据（含哨兵与越界文件清单）。
- [ ] 兑现 `.devbooks/config.yaml` 审计字段：两次运行的 `metrics.json.config.devbooks_config.*` 可复核；若发生漂移，compare 必须产出 `overall_verdict=inconclusive` 且包含原因码 `devbooks_config_drift`。
- [ ] （建议，非阻断）移除简单场景示例中的虚构行号（如 `src/server.ts:1`）并补充 `<out-dir>` 取值示例（避免带 `./` 前缀造成误用）。

### [2026-01-24 00:24:21 +0800] 裁决：Revise（Judge-4）

**理由摘要**：
- `challenge-4.md` 未找到，无法评估新增质疑点并形成可审计裁决。
- 职责分离未通过：`design.md` 包含实现伪代码/算法流程（Algorithm Spec），混入 How。
- 职责分离未通过：`tasks.md` 包含范围/非目标/契约定义等 What/Constraints，混入设计层内容。
- 上述职责混淆违反裁决前置检查，继续推进会放大实现偏差风险。

**必须修改项**（Revise）：
- [ ] 补齐 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/challenge-4.md`（或给出其实际路径），并在 `proposal.md` 中逐条回应其结论/风险点。
- [ ] 清理 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/design.md`：移除实现步骤/伪代码/算法流程，仅保留 What/Constraints + AC；实现细节迁移至 `tasks.md` 或 specs。
- [ ] 清理 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md`：移除 What/Constraints 内容（范围/非目标/契约定义），仅保留可执行实现步骤与依赖顺序。
- [ ] 完成职责分离自检：确保 design 仅写 What/Constraints，tasks 仅写 How，并在新裁决中记录通过结论。

**验证要求**：
- [ ] `challenge-4.md` 可被读取且其内容已在 `proposal.md` 中得到回应。
- [ ] `design.md` 不包含实现步骤/伪代码/算法流程。
- [ ] `tasks.md` 不包含范围/非目标/契约/验收标准定义，仅保留实现步骤。

### [2026-01-24 01:09:00 +0800] 裁决：Revise（Judge-5，复议）

**理由摘要**：
- `tasks.md` 包含“Scope & Non-goals（范围与非目标）”与“范围红线”等 What/Constraints 内容，违背“tasks 仅写 How”的职责分离前置检查。
- `tasks.md` 包含“Data Contracts（契约锚点与版本化）”等契约定义，属于设计/规格层约束，不应出现在实现步骤清单中。
- `tasks.md` 包含“Quality Gates/Traceability（AC/CT 覆盖矩阵）”等验收与追溯定义，仍属于 What/Constraints，导致 Plan 与 Design 职责混淆。

**必须修改项**（Revise）：
- [ ] 清理 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md`：移除或迁移所有 What/Constraints 内容（范围/非目标/红线、契约锚点、质量闸门、AC/CT 覆盖矩阵等），仅保留可执行实现步骤与依赖顺序。
- [ ] 完成职责分离自检：`design.md` 仅保留 What/Constraints + AC；`tasks.md` 仅保留 How（实现步骤/依赖顺序），不含范围/契约/验收定义。

**验证要求**：
- [ ] `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/design.md` 中不出现伪代码/算法流程/具体实现步骤。
- [ ] `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md` 中不出现范围/非目标/契约/验收标准定义，仅保留实现步骤与依赖顺序。

### [2026-01-24 01:31:41 +0800] 裁决：Approved（Judge-6，复议）

**理由摘要**：
- Proposal 覆盖 Why/What/Impact/Risks/Validation/Debate Packet/Decision Log，结构完整且可审计。
- 已回应 challenge-4 阻断项：scorecard anchors 增加 `evidence_path` 与 `check_command`，并纳入 `jq -e` 校验。
- AI A/B 执行边界已闭合为“可选”，并明确 `ai_ab.status/ai_ab.skipped_reason` 与 compare 不受影响规则。
- 简单/复杂场景的可复现参数已固定（Top-N、call_chain/impact depth/direction）并落入 `metrics.json` 字段。

**验证要求**：
- [ ] `scorecard.json` 的 `anchors[].evidence_path` 与 `anchors[].check_command` 存在性校验写入 `jq -e`，并落入 `evidence/gates/scorecard-schema.txt` 的命令/输出摘要。
- [ ] `metrics.json` 包含 `metrics.diagnosis.simple.candidates_limit`、`metrics.diagnosis.simple.expected_hit_rank`、`metrics.diagnosis.complex.call_chain.depth`、`metrics.diagnosis.complex.call_chain.direction`、`metrics.diagnosis.complex.impact.depth` 的固定值。
- [ ] 未执行 AI A/B 时，`metrics.json.ai_ab.status="skipped"` 与 `ai_ab.skipped_reason` 必填，且 `compare.json.overall_verdict` 不受影响。
