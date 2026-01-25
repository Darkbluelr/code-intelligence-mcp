# 第 4 次 Challenge：Proposal v3 质疑报告（Proposal Challenger）

`<truth-root>` = `dev-playbooks/specs`，`<change-root>` = `dev-playbooks/changes`

> 专家视角：System Architect + Product Manager（关注可审计性、范围边界与可复现对比）

1) **结论（第 4 次 Challenge）**：`Revise` —— Proposal v3 已明确 A/B 的总体边界，但在“AI 双代理 A/B 结果可审计性”与“复杂/简单场景可判真锚点的可复现规则”上仍存在导致主观结论的缺口，未满足“可判真 + 可审计”目标。

2) **阻断项（Blocking）**

- **AI 双代理 A/B 的 scorecard 仍允许主观判定，缺少“锚点证据与可复核校验”**
  - 现状：`scorecard.json` 的 `anchors[]` 仅含 `id/passed/reason`，`evidence` 仅要求 `command_log_path` 与 `output_diff_path`，无法把“锚点是否通过”与可复核证据强绑定，容易形成主观结论。
  - 必须修改：为 `anchors[]` 增加可审计字段（至少包含 `evidence_path` 与 `check_command` 或 `expected/observed`），并将其纳入 `jq -e` 校验；要求每个锚点都有可复核命令或证据路径，禁止仅靠文字 `reason`。
  - 验证方式：新增/更新 `scorecard.json` 后运行 `jq -e` 校验命令（需包含 `anchors[].evidence_path` 与 `anchors[].check_command` 的存在性校验），并在 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/gates/scorecard-schema.txt` 留存校验命令与结果摘要。

3) **遗漏项（Missing）**

- **AI A/B 的“是否必做/可选”与默认执行边界未显式闭合**
  - 现状：文本强调“半自动、不并行驱动两个 AI”，但 `evidence` 最小结构包含 4 份 `ai-ab/*/scorecard.json`，容易导致“是否必须执行 AI A/B 才算通过”的理解冲突。
  - 建议补充：在 Proposal 的 AC 或 Validation 中明确三选一：
    - A) **必做**：AI A/B 作为本变更验收必选项，必须产出 4 份 scorecard；
    - B) **可选**：AI A/B 非必选，若未执行必须写入 `metrics.json.ai_ab.status=skipped` 与 `ai_ab.skipped_reason`，且 compare 的 `overall_verdict` 不受其影响；
    - C) **仅演示**：AI A/B 产物仅作为附录证据，不进入正式 A/B 比较与 DoD。
  - 验证方式：检查 `metrics.json` 与 `report.md` 是否明确记录 `ai_ab.status` 与 `ai_ab.skipped_reason`，并在 `compare.json` 中验证 `overall_verdict` 是否按规则受影响或不受影响。

- **简单/复杂场景“可判真锚点”的提取规则缺少可复现参数**
  - 现状：简单场景使用 “Top-N candidates 包含 `src/server.ts`” 的锚点，但未定义 N 与提取规则；复杂场景未明确 `ci_call_chain` 的 depth/direction 与 `ci_impact` 的深度或范围，导致同一输入在不同环境下不可稳定复现。
  - 建议补充：
    - 简单场景：明确 `candidates_limit`（例如 `N=5` 或 `N=10`），并在 `metrics.json.metrics.diagnosis.simple` 中记录 `candidates_limit` 与 `expected_hit_rank`（若未命中则为 `null`）。
    - 复杂场景：明确 `call_chain.depth`、`call_chain.direction`、`impact.depth` 的固定参数，并在 `metrics.json.scenarios`（或等价字段）中记录这些参数。
  - 验证方式：在 `metrics.json` 中检查新增字段是否存在且为固定值；用 `jq` 从 `metrics.json` 中抽取 `candidates_limit`、`expected_hit_rank`、`call_chain.depth`、`call_chain.direction`、`impact.depth` 做一致性校验。

4) **非阻断项（Non-blocking）**

- 简单场景固定输入仍包含虚构行号 `src/server.ts:1`，建议改为不含行号或使用真实行号，降低示例误导性。
- 可在 `report.md` 中增加一行“AI A/B 是否执行”的摘要，减少读者误解（不影响机器对比）。

5) **替代方案**

- **若要彻底规避主观性**：将 AI A/B 限定为“工具输出一致性对比”，不对“AI 修复结果”打分，仅对 `anchors[]` 的可复核证据做 `pass/fail` 统计，报告结论只允许 `pass/failed/inconclusive` 三态。
- **若要降低范围成本**：把 AI A/B 产物归为“可选附录”，默认不纳入 `overall_verdict`；在需要展示 AI 能力时再补充 scorecard 证据，不阻塞 demo-suite 的常规运行。

6) **风险与证据缺口**

- **主观结论风险**：`anchors[]` 缺少“证据路径 + 可复核命令”会使 scorecard 依赖主观判断，难以满足“可审计对比”目标。
- **可复现性风险**：Top-N 未定义、调用链/影响分析参数未固定，可能导致同一输入在不同运行中出现“是否命中锚点”的摇摆。
- **证据缺口**：当前未要求示例 `scorecard.json` 展示“锚点证据路径 + 校验命令”的最小样例，无法证明规则可落地且可复核。
