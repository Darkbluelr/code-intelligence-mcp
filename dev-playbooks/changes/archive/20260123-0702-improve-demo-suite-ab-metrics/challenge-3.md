# Challenge-3：Proposal v3 质疑报告（Proposal Challenger）

`<truth-root>` = `dev-playbooks/specs`，`<change-root>` = `dev-playbooks/changes`

> 专家视角：System Architect + Product Manager（关注范围可控、DoD 可达、可审计性与长期维护成本）。

1) **结论（第 3 次 Challenge）**：`Approve` —— Proposal v3 已闭合 Judge-2 的全部“必须修改项”，且关键质量闸门命令在当前仓库可重复执行并通过（已实测 ShellCheck 范围收敛为 `demo/`；`npm run build` 通过）。

2) **阻断项（Blocking）**

- 无（Judge-2 必须项已全部在 Proposal v3 中闭合，且未发现新的阻断缺口）。

3) **遗漏项（Missing）**

- 无（对 Judge-2 的要求：ShellCheck 范围收敛、哨兵路径统一、`find` 排除 out-dir 的可复现写法、`scorecard.json` 的 `jq -e` 校验、以及 `.devbooks/config.yaml` 的隔离/审计策略，均已在 Proposal v3 文本中成文）。

4) **非阻断项（Non-blocking）**

- **简单场景固定输入仍包含虚构行号**：`TypeError: ... (src/server.ts:1)`（见“复杂/简单场景契约”）。建议改为不含行号或使用真实行号，避免示例降低可信度（不影响“文件/符号/候选包含”的可判真锚点设计）。
- **写入边界检查命令的可读性仍可再增强**：Proposal v3 已用 `-prune` 规避路径前缀误报风险；建议补一条“`<out-dir>` 取值示例（不带 `./` 前缀）”来降低使用者误填概率（不影响可复现性）。

5) **替代方案**

- 无需替代方案：保持 Proposal v3 的“范围收敛 + 契约闭合 + 可审计对比”路径即可进入 Judge 再裁决。

6) **风险与证据缺口**

- **写入边界检查的可复现性仍依赖 apply 阶段 evidence 落盘**：Proposal v3 已给出“从仓库根执行、哨兵路径统一、out-dir 用 `-prune` 排除”的检查命令；仍需在实现后按其 Evidence 结构产出可复现记录（例如 `evidence/write-boundary/*` 的检查输入与输出摘要），以支撑“最终产物仅落在 out-dir”的可审计结论。
- **`.devbooks/config.yaml` 审计字段需在真实 A/B 产物中兑现**：Proposal v3 已定义 `copied|generated|disabled|missing` 与 `metrics.json.config.devbooks_config.*` 审计字段，并规定 compare 对 config 漂移的 `inconclusive` 行为；仍需在实际 `metrics.json`/`compare.json` 中体现并可被复核。

