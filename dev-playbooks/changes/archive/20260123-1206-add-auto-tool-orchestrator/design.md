# 设计文档：自动工具编排 + 结果融合的上下文注入（Claude Code / Codex CLI）

> 版本：1.0.0  
> 状态：Draft  
> 更新时间：2026-01-24  
> 变更包：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator`  
> Owner：Design Owner  
> truth-root：`dev-playbooks/specs/`  
> change-root：`dev-playbooks/changes/`  

## Acceptance Criteria（验收标准）

本设计以 `proposal.md` 中已批准的 AC-001 ~ AC-018 为唯一验收口径（逐条实现/测试/留证据，不新增“口头验收”）。

关键 AC 摘要（不替代原文）：
- AC-001：Claude Code 在模型输出前完成编排并回填（输出包含 `tool_plan/tools`、`tool_results`、`fused_context`）。
- AC-002/003/015：Codex CLI 两入口（会话恢复/单次注入）可验证且可降级；plan/dry-run 确定性且不依赖外部 codex。
- AC-004/009/017/018：控制面优先级 env > config > default；Tier-2 默认禁用且仅 env 启用；MVP 行为边界可测；legacy 回退可审计。
- AC-006/016：入口层去编排化（静态扫描可证）；白名单/参数裁剪/路径过滤/脱敏与绕过拒绝；唯一工具通道为编排内核。
- AC-007/008/010/011/012/014：预算/并发/回填限额明确；fail-open 降级可见；提示注入防护；结果融合确定性；错误码/退出码契约一致；schema 版本化清晰。
- AC-013：`augment-context-global.sh` 继续兼容并等价转发。

## ⚡ Goals / Non-goals + Red Lines

### Goals
- 为 Claude Code 与 Codex CLI 提供“模型输出前”的自动工具编排：Intent → Tool Plan → Tool Calls → Tool Results → Fused Context → 注入。
- 自动调用策略遵循“尽可能多，但受预算与风险边界约束”：Tier-0/1 默认自动；Tier-2 默认关闭且仅 env 显式启用。
- 统一输出稳定 JSON（`schema_version` + `run_id` + Tool Plan/Results/Fused Context），并提供用户可见 [Limits] 与降级说明。
- 入口层收敛为“输入采集 + 输出注入”，所有工具调用、裁剪、预算、融合逻辑进入 `hooks/auto-tool-orchestrator.sh`。
- 同包内提供迁移与回滚：`CI_AUTO_TOOLS_LEGACY=1` 可审计回退；无编排/不可用时空注入兜底。

### Non-goals
- 不适配 Cursor/其他 IDE（明确排除）。
- 不改变 Thin Shell 约束：TypeScript 仍是 MCP 薄壳；核心能力仍在 Bash 脚本与工具侧。
- 不引入“无上限全工具跑一遍”的默认行为（必须受预算/阈值/白名单约束）。

### Red Lines
- 入口层（`hooks/context-inject-global.sh`、`hooks/augment-context-global.sh`）不得直接调用任何 `ci_*` 或底层工具脚本；唯一工具通道必须可被静态扫描验证（AC-006/016）。
- Tier-2 默认禁用，且启用入口必须唯一：`CI_AUTO_TOOLS_TIER_MAX=2`（AC-009/017）。
- 任何降级/裁剪/拒绝必须在 [Limits] 可见（含原因与关键键名），fail-open 不得阻塞主回答（AC-008/012）。
- 工具输出视为不可信数据，必须具备提示注入防护（AC-010）。

## 执行摘要

本设计新增 `hooks/auto-tool-orchestrator.sh` 作为唯一编排执行点，并将现有 `hooks/context-inject-global.sh` 收敛为“采集输入/输出注入”的薄适配层。编排内核输出稳定 JSON schema v1.0（`schema_version/run_id/tool_plan/tool_results/fused_context/degraded`），同时提供 plan/dry-run 的确定性输出以支撑 bats 验证与 Codex CLI 的可降级实现。控制面由 `config/auto-tools.yaml` 承载，优先级为 env > config > default，并强制 Tier-2 仅 env 启用以避免配置绕过。

## Problem Context（问题背景）

- 当前 Hook 能输出 5 层结构化上下文，但“工具建议/检索/融合”逻辑分散在入口层内，难扩展、难测试、难统一降级与安全策略。
- 新需求要求：在模型输出前自动调用“合适的多工具组合”，并对结果做确定性融合与用户可见解释，同时兼顾延迟与可控性。
- Codex CLI 的“会话连续性 + 可测降级”链路在当前 repo 中不存在，需要新增但必须可在 plan/dry-run 下确定性验证（不依赖外部 codex）。

## Design Rationale（设计依据）

- 采用“入口层薄适配 + 编排内核唯一通道”：将工具调用、安全过滤、预算/并发/超时、结果融合与降级策略集中在单一执行点，满足入口层可被静态扫描验证“不得直连工具”的硬约束（AC-006/016），并降低策略分叉导致的不可审计风险。
- 以稳定、版本化的 Orchestrator JSON schema 作为共享契约：让 Claude Code Hook 与 Codex CLI 两条入口在“同一字段集合/同一退出码语义”下收敛，且为 plan/dry-run 提供确定性输出锚点，支撑可重复验证与回归（AC-001/002/003/011/012/014/015）。
- 控制面优先级 env > config > default，且 Tier-2 仅允许 env 启用：防止配置绕过带来的隐式升权与不可追责行为，使高风险能力只能由显式、可审计的运行时开关开启（AC-009/017/018）。
- fail-open 但必须可见：任何失败不得阻塞主回答，但必须在结构化输出与用户可见 [Limits] 中明确“发生了什么/为何降级/影响范围”，保证可解释与可运维（AC-008/012）。

## Trade-offs（权衡）

- 放弃入口层“就地编排”的灵活性：入口侧不能临时追加工具调用；换取策略集中、行为一致、边界可证明（AC-006/016）。
- 强化确定性输出会牺牲部分信息密度/自由度：为稳定排序、摘要与截断规则付出信息损失风险；换取测试可重复与回归稳定（AC-011）。
- 默认安全与路径/参数约束可能降低自动工具覆盖率与命中率：以更小的风险暴露面换取默认安全（AC-010）。
- Tier-2 默认关闭降低“尽可能多工具”效果：以明确的风险分层与显式启用换取可控性与合规性（AC-009/017）。

## 设计原则（Design Principles）

- **唯一编排通道**：所有工具调用只发生在编排内核，入口层永不直连。
- **确定性优先**：plan/dry-run 输出在同输入下可重复（排序/摘要长度/截断策略稳定）。
- **可控优先**：预算、并发、超时、Tier 边界为明确数字；Tier-2 必须显式启用。
- **fail-open + 可见降级**：任何失败不阻塞输出，但必须可审计（[Limits] + `degraded` 字段 + exit code 契约）。
- **安全默认**：路径过滤、脱敏、提示注入防护默认开启；工具输出不可信。

## Variation Points（可变点）

- Variation Point: 工具集合与分层策略（Tier-0/1 默认集、Tier-2 白名单）可调整，但必须保持“Tier-2 仅 env 启用”与白名单/裁剪/审计边界不变（AC-009/017）。
- Variation Point: 预算/并发/超时/回填限额参数可调整，但必须在 [Limits] 明示并保持可裁剪、可审计（AC-007/008/014）。
- Variation Point: 结果融合规则（claim_key、冲突判定、排序/摘要长度）可演进，但必须保持确定性与兼容策略清晰（AC-011）。
- Variation Point: 输出/注入形态（Claude Hook additionalContext vs CLI JSON）可替换，但必须共享同一 schema 与退出码语义（AC-001/012/015）。
- Variation Point: legacy/迁移窗口策略（CI_AUTO_TOOLS_LEGACY）可调整，但不得绕过“唯一工具通道”的红线（AC-013/016）。

## 目标架构（Architecture Overview）

### 组件划分

- **入口层（Adapters）**
  - `hooks/context-inject-global.sh`：Claude Code `UserPromptSubmit` Hook 适配；负责输入采集与输出注入（additionalContext 或 CLI JSON）。
  - `hooks/augment-context-global.sh`：兼容包装（保持旧入口名）。
  - （新增）Codex CLI wrapper/入口脚本：提供入口 A（会话恢复）与入口 B（单次注入），并共享同一编排内核。

- **编排内核（Kernel）**
  - `hooks/auto-tool-orchestrator.sh`：唯一工具调用点；负责意图分析、工具计划、执行、裁剪、融合、输出 schema、降级与退出码契约。

### 依赖方向（约束）

- 入口层 → 编排内核 →（脚本/工具执行器）
- 入口层不允许：直接调用 `scripts/*.sh` 或任何 `ci_*`。
- 编排内核可调用：本仓库脚本能力（例如 `scripts/*`）或等价执行器，但必须通过白名单与参数裁剪控制风险。

## 输出契约（I/O Contract）

### Orchestrator JSON schema v1.0（摘要）

以 `proposal.md` 的“设计要点 6/7.1”作为权威来源。设计阶段仅强调以下不变点：
- 必须字段：`schema_version`、`run_id`、`tool_plan`、`tool_results`、`fused_context`、`degraded`。
- 必须可测字段：`tool_plan.tier_max`、`tool_plan.budget.*`、`tool_plan.tools[]`、`tool_plan.planned_codex_command`（plan/dry-run）、`fused_context.for_model.additional_context`、`fused_context.for_user.limits_text`。
- 退出码与 `tool_results.error.code` 枚举必须与 AC-012 一致。

### Hook / CLI 输出形态

- Claude Code Hook：入口层输出 Claude Code 期望的 `hookSpecificOutput.additionalContext`；其内容来自 `fused_context.for_model.additional_context`（并可在调试/plan 下附带 [Auto Tools] 摘要与 [Limits]）。
- CLI（bats 验证优先）：入口层支持输出完整 Orchestrator JSON（用于 AC 验证与可重复回归）；legacy 模式输出策略由 `CI_AUTO_TOOLS_LEGACY` 控制并可审计。

## 控制面（Configuration Surface）

### 优先级

- env > `config/auto-tools.yaml` > default
- **Tier-2 启用唯一入口**：仅 `CI_AUTO_TOOLS_TIER_MAX=2` 可启用 Tier-2；配置文件中任何等价字段必须被忽略并在 [Limits] 明示（AC-009）。

### 核心环境变量（不新增“隐藏开关”）

- `CI_AUTO_TOOLS=off|auto|on`（默认 `auto`）：是否启用自动编排。
- `CI_AUTO_TOOLS_MODE=plan|run`（默认 `run`）：plan 不执行工具，只输出计划与 [Limits]。
- `CI_AUTO_TOOLS_DRY_RUN=0|1`：等价 plan 但保留更强的“绝不执行外部进程”约束。
- `CI_AUTO_TOOLS_TIER_MAX=1|2`（默认 `1`）：Tier-2 仅显式启用。
- `CI_AUTO_TOOLS_LEGACY=0|1`（默认 `0`）：迁移期回退，输出必须可审计（[Limits] + `enforcement.source`）。
- `CI_CODEX_SESSION_MODE=resume_last|exec`（plan/dry-run 可验证）：决定 `planned_codex_command` 的形态（AC-002/003）。

## 安全策略（Security）

设计阶段将安全策略视为硬约束（AC-006/010）：
- **白名单**：仅允许声明在 `config/auto-tools.yaml` 的工具集合被计划/执行。
- **参数裁剪**：对深度、top_k、token_budget、路径等参数做上限裁剪，并在 [Limits] 逐条记录。
- **路径过滤**：只允许 `<repo-root>` 内路径（realpath 校验，禁止 `..` 逃逸），并默认屏蔽敏感文件模式（`.env`、`*.pem`、`id_rsa*` 等）。
- **脱敏**：注入文本必须做 token/密钥模式脱敏（Bearer/Private Key/AKIA 等）。
- **提示注入防护**：过滤工具输出中的“忽略指令/执行命令”等模式，并在 `fused_context.for_model.safety` 与 [Limits] 中标记。

## 结果融合（Deterministic Fusion）

- 去重键（claim_key）、稳定排序、摘要长度与截断策略必须确定性（AC-011）。
- 冲突判定必须可执行：同一 `claim_key` 且 polarity 对立（support/oppose）→ `conflict=true`，并在用户输出中并列展示证据来源。

## 迁移与回滚（Migration）

采用“重构迁移（Refactor Migration）”：
- 入口层去编排化，强制单通道；legacy 回退仅改变“策略/输出”，不允许绕过编排内核直连工具。
- 回滚入口：`CI_AUTO_TOOLS_LEGACY=1`（可审计），以及 `CI_AUTO_TOOLS=off`（空注入兜底）。

## Spec 影响与追溯（Truth Root）

### 受影响的现有 Spec（必须遵守/需要更新）
- `dev-playbooks/specs/structured-context-output/spec.md`
  - 当前定义为“5 层结构化输出”；本变更将引入 Orchestrator JSON schema v1.0，需明确兼容/迁移（可能为 major 升级或 legacy 模式）。
- `dev-playbooks/specs/architecture/c4.md` / `dev-playbooks/specs/architecture/module-graph.md`
  - 需要补充“Auto Tool Orchestrator”组件与依赖关系变化（入口层收敛、唯一编排通道）。
- `dev-playbooks/specs/_meta/project-profile.md`
  - 可能需要同步 Hook/入口脚本说明与验证锚点。

### Gap 声明
- Gap-ATO-001：现有 `structured-context-output` 将“5 层 JSON”定义为顶层字段；本设计引入新的顶层 schema，需要在 spec-contract 阶段明确：是否升级为新 major 并提供 legacy 输出，或提供顶层字段双写兼容窗口。

## Documentation Impact（文档影响）

### 需要更新的文档

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| `docs/TECHNICAL.md` | Hook 输出从“5-layer structured JSON”迁移到 Orchestrator JSON schema（含 plan/dry-run、[Limits]、退出码） | P0 |
| `docs/TECHNICAL_zh.md` | 同步中文技术文档 | P0 |
| `README.md` | 新增/变更 Hook/自动编排的启用方式与开关说明 | P1 |
| `README.zh-CN.md` | 同步中文说明 | P1 |

### 无需更新的文档
- [ ] 本次变更为内部重构，不影响用户可见功能
- [ ] 本次变更仅修复 bug，不引入新功能或改变使用方式

### 文档更新检查清单
- [ ] 新增脚本/命令已在使用文档中说明
- [ ] 新增配置项已在配置文档中说明
- [ ] 新增工作流/流程已在指南中说明
- [x] API/接口变更已在相关文档中更新

## Architecture Impact（架构影响）

### 有架构变更

#### C4 层级影响

| 层级 | 变更类型 | 影响描述 |
|------|----------|----------|
| Context | 修改 | 在“AI 客户端”侧新增“自动工具编排 + 结果融合”的预调用链路（仅 Claude Code/Codex CLI） |
| Container | 无变更 | 不新增独立服务；仍为本地脚本 + MCP server 薄壳 |
| Component | 新增/修改 | 新增 `hooks/auto-tool-orchestrator.sh`；修改 `hooks/context-inject-global.sh` 由“做事”变为“适配器” |

#### Component 变更详情

- [新增] `hooks/auto-tool-orchestrator.sh`：工具计划/执行/融合/安全过滤/输出契约。
- [修改] `hooks/context-inject-global.sh`：输入采集 + 输出注入（委托编排内核）。
- [兼容] `hooks/augment-context-global.sh`：保持转发与兼容。

#### 依赖变更

| 源 | 目标 | 变更类型 | 说明 |
|----|------|----------|------|
| `hooks/context-inject-global.sh` | `hooks/auto-tool-orchestrator.sh` | 新增 | 入口层统一委托编排内核 |
| `hooks/augment-context-global.sh` | `hooks/context-inject-global.sh` | 保持 | 兼容转发不变 |

## ⚡ DoD 完成定义（Definition of Done）

- AC-001 ~ AC-018 全部通过（bats + 证据目录留档）。
- `tests/**` 无 skip/todo/not_implemented 空壳测试。
- `dev-playbooks/changes/<id>/verification.md` 的 AC 覆盖率 100%。
- `dev-playbooks/changes/<id>/evidence/green-final/` 存在且包含最终闸门输出（至少 npm test/bats 输出摘要）。
- 文档更新项已覆盖 TECHNICAL（中英文）；安装/启用方式可复现。

## Open Questions

1. `structured-context-output` 的兼容策略最终选择：major 升级 + legacy 输出，还是顶层字段双写的迁移窗口？
2. Codex CLI 入口 A/B 的最终落点：新增 wrapper 放在 `bin/` 还是 `hooks/`（需满足 AC-002/015 的可测性与降级边界）。
3. 工具白名单的默认集合与 Tier 映射：最小 MVP（Tier-0/1）默认跑哪些工具，才能同时满足“尽可能多”与预算约束？
4. 冲突判定最小可执行规则的字段设计：`claim_key/polarity/evidence_refs` 的最小集合与排序规则如何固定以支撑 AC-011？
5. 入口层输出（Hook 适配 vs CLI JSON）如何共享同一 schema 同时不破坏 Claude Code 的 `hookSpecificOutput` 协议？
