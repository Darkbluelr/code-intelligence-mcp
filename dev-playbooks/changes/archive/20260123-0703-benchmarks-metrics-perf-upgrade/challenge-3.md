Truth Root：`dev-playbooks/specs`；Change Root：`dev-playbooks/changes`
这是第 3 次 Challenge。
专家视角：Product Manager、System Architect。

**结论**：Revise Required —— 这是第 3 次 Challenge；提案已覆盖性能统计口径+回退开关、版本对齐校验、样例、queries_version 规则与 precision 门槛一致性，但“回退即验收”表述与“必须性能提升”目标存在冲突，需澄清验收边界。

**阻断项（Blocking）**
- 回退策略与性能验收目标冲突：提案写明“质量指标低于阈值或 compare 不通过时关闭开关后结果可作为可验收基线/当前结果”，这等同于允许在性能优化失败时以关闭开关通过验收，违背“本变更包内完成可验证性能提升”与 AC-008/009/010 的提升目标。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的“性能开关与回退策略”“DoD/验收锚点”“结论先行”。验证方法：在提案中明确验收边界（例如仅以开关开启结果满足 AC-008/009/010 才可验收；关闭开关仅作安全回退不作为验收通过），并在 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/` 中分别给出开启/关闭两组 compare 结果与最终采信依据。

**遗漏项（Missing）**
- 无（本轮核查项已覆盖：性能统计口径+回退开关、版本对齐校验、样例、queries_version 规则、precision 门槛一致性；见 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的“性能验收统计口径”“性能开关与回退策略”“版本对齐校验（强制）”“最小 baseline/current JSON 与 benchmark_summary.md 样例”“queries_version 命名与更新规则”“阈值规则/AC-010”）。

**非阻断项（Non-blocking）**
- 统计口径落地建议：补充“3 次运行取中位数”的计算方式与产物落点（例如产出 `benchmark_result.median.json` 或记录计算脚本），避免 AC-008/009/010 的统计口径在实现阶段被随意解释。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的“性能验收统计口径”仅描述取中位数但未定义计算产物。验证方法：提供计算步骤或脚本，并用 3 份结果生成中位数产物后存入 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/`。
- queries_version 实测校验建议：新增一条“对齐校验命令”或脚本，用于验证 `queries_version` 与 `tests/fixtures/benchmark/queries.jsonl` 的哈希一致。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的“queries_version 命名与更新规则”只描述命名与触发。验证方法：执行 `sha256sum tests/fixtures/benchmark/queries.jsonl`（或等效命令）并对比 JSON 中 `queries_version`。

**替代方案**
- 方案 A（保持性能目标）：保留 AC-008/009/010，明确回退仅用于安全降级，不作为验收通过依据。
- 方案 B（缩小范围）：若必须允许回退即验收，则移除 AC-008/009/010 并将性能提升降级为后续变更包。

**风险与证据缺口**
- 尚未提供“开关开启/关闭”两组 compare 证据与选择依据，无法判断性能目标与回退策略是否冲突地落地。验证方法：按提案命令运行并将 JSON + `benchmark_summary.md` 记录到 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/`，标注采信路径。
- 版本对齐校验与样例/queries_version 规则已写入提案，但尚无失败路径证据（version mismatch）与样例输出映射证据。验证方法：构造不同 `schema_version` 或 `queries_version` 的 baseline/current 运行 `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.json benchmarks/results/benchmark_result.json` 并保存输出。
