Truth Root：`dev-playbooks/specs`；Change Root：`dev-playbooks/changes`
这是第 4 次 Challenge。
专家视角：Product Manager、System Architect。

**结论**：Revise Required —— 验收边界与 `queries_version` 校验命令已明确，但 median-of-3 产物落点未区分 baseline/current，导致 AC-008/009/010 的中位数对比无法稳定复验。

**阻断项（Blocking）**
- median-of-3 产物落点冲突：提案在“性能验收统计口径”写明 baseline 与 current 各自进行 3 次运行并取中位数，但运行产物与中位数产物只定义为 `benchmarks/results/run-1/`、`benchmarks/results/run-2/`、`benchmarks/results/run-3/` 以及 `benchmarks/results/benchmark_result.median.json`、`benchmarks/results/benchmark_summary.median.md`，未给出 baseline 侧的独立落点与命名，存在覆盖与混淆风险。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的“性能验收统计口径”。验证方法：在同一段落内明确 baseline 与 current 两套产物落点与命名规则，例如 baseline 运行产物落在 `benchmarks/baselines/run-1/`、`benchmarks/baselines/run-2/`、`benchmarks/baselines/run-3/`，baseline 中位数落在 `benchmarks/baselines/benchmark_result.median.json` 与 `benchmarks/baselines/benchmark_summary.median.md`，current 保持 `benchmarks/results/`；修订后检查 `proposal.md` 该段落是否包含两套互不冲突路径。

**遗漏项（Missing）**
- 无。

**非阻断项（Non-blocking）**
- `queries_version` 校验命令已提供 macOS 与 Linux 版本，但未声明其作为前置依赖或替代路径。建议在“`queries_version` 命名与更新规则”补一句前置依赖或补充一条 Node.js 等效命令，避免环境缺失导致校验无法执行。验证方法：检查 `proposal.md` 中该小节是否包含“前置工具清单”或等效命令说明。
- 验收边界已在“性能开关与回退策略”和“DoD/验收锚点”双处出现，存在未来修改时产生不一致的风险。建议在其中一处增加指向另一处的引用或合并为单一权威段落。验证方法：检查 `proposal.md` 中是否形成单一权威表述或明确引用。

**替代方案**
- 方案 A（最小改动）：仅补齐 baseline 侧产物落点，不改统计口径；保持 current 产物在 `benchmarks/results/`，baseline 产物在 `benchmarks/baselines/`，中位数产物按目录对称落点。
- 方案 B（集中产物）：保留 `benchmarks/results/` 为 current，但将 baseline 3 次运行与中位数全部放入 `benchmarks/baselines/` 并在 compare 时显式使用基线中位数文件作为 baseline 输入，避免结果混淆。

**风险与证据缺口**
- 若 baseline 与 current 的 median-of-3 产物落点不分离，将无法证明 AC-008/009/010 的阈值比较基于同口径中位数，验收证据链不可复验。验证方法：修订 `proposal.md` 的“性能验收统计口径”后，核对是否存在两套互不冲突的 run 与 median 产物路径定义。
- 交付范围同时覆盖指标升级与性能优化实现，范围仍可落地但对节奏敏感；若未先稳定 compare 与统计口径，性能改动的验证可能受阻。验证方法：在 `proposal.md` 的“DoD/验收锚点”中补充先后顺序或最小可验证路径说明，确认验收链条闭合。
