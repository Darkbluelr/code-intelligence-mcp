# Proposal Challenger 质疑报告（第 1 次）
- Change ID：`20260123-1206-add-auto-tool-orchestrator`
- Truth Root：`dev-playbooks/specs/`
- Change Root：`dev-playbooks/changes/`
- 被质疑文档：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/proposal.md`
- 专家视角：Product Manager / System Architect
- 治理约束：本报告**不提出拆分变更包**的要求（遵守 proposal 的“单变更包交付”约束），仅建议在同一变更包内补齐/澄清。

---

## 1) 结论：Revise
一句话理由：Hook 输出契约的演进映射、plan/dry-run 与 run 的“真实性边界”、Tier-2 的可测触发规则、以及退出码/错误码与 fail-open 的上游消费假设仍存在未闭合与不自洽点，导致 AC-001/003/009/012/014/017 的“可重复验收”风险偏高。

---

## 2) 阻断项（Blocking）

### B1. Hook 输出契约演进未闭合：三种输出形态的映射与 canonical 字段未写死
**证据锚点（proposal 与 specs）**：
- proposal「Impacts A」同时声明两种对外输出：  
  - `hooks/context-inject-global.sh --format json` 从 5-layer 升级为编排器 schema（含 `schema_version/tool_plan/tool_results/fused_context/degraded/enforcement`），并“保留顶层 5-layer 兼容字段”；  
  - Claude Code 默认 Hook 输出仍为 `hookSpecificOutput.additionalContext`（文本），内容来自编排结果，含 `[Auto Tools] / [Results] / [Limits]`。
- `dev-playbooks/changes/.../specs/structured-context-output/spec.md`（Spec Delta）把 5-layer 从“顶层字段”下沉为 payload：允许作为 `fused_context.for_model.structured`，且不再强制顶层出现。
- proposal 同时引入迁移期回退 `CI_AUTO_TOOLS_LEGACY=1`（AC-018），但未把 legacy 输出与上述两种输出的关系写成“可验证的映射契约”。

**问题/风险**：
- 未定义“5-layer 顶层兼容字段”与 `fused_context.for_model.structured` 的一致性规则：两者是否必须同构/同值？哪个是 canonical？消费者按哪个读才算“兼容策略生效”（影响 AC-014）。
- 未定义 Claude Hook 文本输出与编排 JSON 的映射规则：  
  - `hookSpecificOutput.additionalContext` 来自 `fused_context.for_model.additional_context` 还是拼接 `fused_context.for_user.{tool_plan_text,results_text,limits_text}`？  
  - 是否强制包含 `run_id`、是否强制包含 `[Limits]`（即使为空也要保留字段/空段落）？
- legacy 模式只写了“可审计”（AC-018），但未写清：legacy 输出是“回到旧 5-layer 顶层 JSON”、还是“新 envelope + legacy policy 标记 + 兼容字段超集”。这会直接影响回滚可控性与文档/脚本兼容。

**必须补齐（同包内，不拆包）**：
- 在 proposal 的“编排内核 I/O 契约”处增加**输出模式矩阵**并写死 canonical 读取位置，至少覆盖：  
  1) Claude Hook 默认输出（`hookSpecificOutput.additionalContext`）  
  2) `--format json` 输出（编排 JSON envelope）  
  3) `CI_AUTO_TOOLS_LEGACY=1` 输出（必须明确与 1/2 的关系）
- 写死 5-layer 的兼容策略：若保留顶层 5-layer，必须声明其与 `fused_context.for_model.structured` 的一致性约束（例如“顶层字段若存在必须与 structured 同构同值”），并声明 canonical（消费者应优先读哪一处）。
- 给出至少 1 个**完整的 Claude Hook 文本示例**（含 `[Auto Tools] / [Results] / [Limits]` 的顺序与最小内容要求），以便把“文本输出契约”落成可验收锚点（对应 AC-001/AC-014/AC-018）。
