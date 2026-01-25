Truth Root：`dev-playbooks/specs`；Change Root：`dev-playbooks/changes`
这是第 2 次 Challenge。
专家视角：Product Manager、System Architect。

**结论**：Revise Required —— 修订已覆盖多数阻断项，但性能 AC 的可行性与回退策略、compare/基线版本对齐校验仍不足，无法保证本变更包可落地验收。

**阻断项（Blocking）**
- 性能 AC 可行性与回退策略不足：AC-008/009/010 要求 P95 相对基线 5%-10% 改善，但未给出基线波动范围、重复运行统计口径与“不达标的降级/回退机制”（如早停与子图缓存的开关策略），存在无法通过验收的高风险。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的 AC-008/009/010 与“交付范围 B”。验证方法：补充“至少 3 次重复运行取中位数/均值”的统计口径与性能开关；在同一硬件环境按提案命令运行 `python benchmarks/run_benchmarks.py --output benchmarks/results/benchmark_result.json` 并用 `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.json benchmarks/results/benchmark_result.json` 验证阈值与开关回退可通过。
- compare/基线流程缺少版本对齐校验：schema v1.1 引入 `schema_version` 与 `queries_version`，但提案未要求 compare 在版本不一致时直接失败，导致基线与当前结果可能来自不同查询集或 schema 而仍被比较。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的 schema v1.1 与 compare 规则未包含版本一致性检查。验证方法：补充 compare 的“schema_version/queries_version 必须一致，否则返回 regression/错误”规则，并用不同版本的 baseline/current 进行 `scripts/benchmark.sh --compare` 验证失败路径。

**遗漏项（Missing）**
- 缺少最小可运行的 baseline/current JSON 样例与 `benchmark_summary.md` 样例，难以校验 schema 字段与 compare 摘要的精确映射。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 仅提供字段表与摘要模板。验证方法：在提案中补充最小 JSON 片段（覆盖 `run.*`、`environment.*`、`metrics.*`、兼容字段）及与之对应的 Markdown 摘要样例。
- 查询集扩充与 `queries_version` 冻结流程未落地：提案要求“扩充到 ≥10 条并冻结版本”，但未给出版本命名规则与更新触发条件。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的“关键约束/风险”。验证方法：明确 `queries_version` 值来源与更新规则，并用 `wc -l tests/fixtures/benchmark/queries.jsonl` 与 JSON 中 `queries_version` 对齐校验。

**非阻断项（Non-blocking）**
- 修订已覆盖上一轮的基线路径、schema v1.1、compare 兼容与环境字段要求，建议在结论处显式标注“已响应 Challenge-1 关键阻断项”以便审计追踪。验证方法：对照 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/challenge-1.md` 与 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的对应段落。
- `metrics.retrieval_quality.precision_at_10` 已列为必填但未纳入 AC 与 compare 门槛，建议明确“是否纳入回归判定”以消除歧义。验证方法：在 AC 或 compare 规则中新增或声明排除该指标，并以 `scripts/benchmark.sh --compare` 输出确认。

**替代方案**
- 方案 1（最小可落地闭环）：本变更包仅交付 schema v1.1 + compare + 基线流程 + queries_version 冻结；性能优化（早停与缓存）改为“默认关闭的实验开关”，在同包内先落地开关与度量，再由后续变更包开启。验证方法：默认关闭时 compare 通过且 schema/summary 完整，开启开关时仅做实验记录不影响验收。
- 方案 2（两阶段交付）：先通过当前提案的 A 范围（指标补齐与闭环），第二阶段单独提性能优化与更严苛的 P95 改善目标。验证方法：第一阶段以 AC-001~AC-007 验收，第二阶段再以 AC-008~AC-010 验收。

**风险与证据缺口**
- 缺少性能改动的重复运行证据与噪声区间，AC-008/009/010 的稳定性不可验证。建议补充至少 3 次重复运行的对比结果并落在 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/`。验证方法：同机多次运行并记录 p95/p99 的统计摘要。
- 缺少 compare 版本对齐失败路径的证据，无法证明基线与当前结果不会“错配比较”。验证方法：构造不同 `queries_version` 的 baseline/current 并验证 compare 必失败。
- 缺少缓存清理对新增子图缓存的覆盖证据，cold/warm 定义可能失真。验证方法：确认 `scripts/cache-manager.sh cache-clear` 覆盖新缓存键，并提供清理前后缓存命中变化的简要记录。
