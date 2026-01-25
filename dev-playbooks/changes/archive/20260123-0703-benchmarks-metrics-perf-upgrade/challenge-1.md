Truth Root：`dev-playbooks/specs`；Change Root：`dev-playbooks/changes`

**结论**：Revise（Revise Required）——从 Product Manager 与 System Architect 视角，当前提案无法保证“真实性能提升”的交付闭环且关键指标口径不可验证；这是第 1 次 Challenge。

**阻断项（Blocking）**
- 范围与“真实性能提升”目标不对齐：提案明确“本阶段不直接实现性能优化/不改业务逻辑”，导致只做度量补齐而无法交付性能提升。建议明确本变更包的最小可交付优化，或拆分为“指标补全”与“性能优化”两个变更包。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的“本提案不会导致/Out of scope”。验证：复核该段并补充交付边界与里程碑。
- 回归对比工具与目标 JSON 结构不一致：`scripts/benchmark.sh --compare` 只读取顶层 `mrr_at_10/recall_at_10/p95_latency_ms`，而 `benchmark_result.json` 使用 `metrics.*` 嵌套结构；提案要求统一到 `benchmark_result.json` 并以 `--compare` 判定回归，现有机制无法覆盖新字段。证据：`scripts/benchmark.sh`、`benchmark_result.json`。验证：对比脚本 `compare_reports` 的 jq 路径与 `benchmark_result.json` 字段路径。
- 基线策略不可执行：提案虽默认“固定基线”，但未定义基线文件存放路径、生成/更新流程、审批与回滚规则；AC-005 依赖 `--compare`，却未指明 baseline/current 的产物落点与生成命令。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 的“隐藏需求 1/AC-005”。验证：检查提案是否给出基线文件路径与更新流程。
- 指标口径与方向未定义导致阈值不可验证：`compression_ratio`、`speedup_pct` 等未明确“越大越好/越小越好”的判定方向与计算公式，`hit_rate_at_10/expected_count` 也未定义计算口径，导致阈值无法落地。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 指标表与 AC。验证：检查指标表是否包含公式与方向说明。

**遗漏项（Missing）**
- JSON schema 约定缺失：未定义字段完整路径、必填/可选字段、`schema_version` 升级策略与兼容读取规则（现有文件为 `schema_version: 1.0`）。证据：`benchmark_result.json`、`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md`。验证：确认提案是否包含 schema 说明或样例输出。
- 环境与运行条件记录不足：性能对比需记录 CPU/内存、OS 版本、依赖版本、运行模式（legacy/dataset）、缓存清理规则与冷/热定义，提案未给出可重复证据字段。证据：`benchmark_result.json` 仅含 `python/platform`。验证：对照现有 JSON 字段与提案内容。
- 查询集治理缺失：当前查询集仅 3 条（`tests/fixtures/benchmark/queries.jsonl`），提案将“扩充到 ≥10 条”放在 Debate 选项中，未给出选择标准与变更控制，导致质量指标易波动。证据：`tests/fixtures/benchmark/queries.jsonl`、`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` Debate Packet。验证：`wc -l tests/fixtures/benchmark/queries.jsonl` 与提案对照。
- 回滚策略缺失：未定义新指标/新 schema 引入后出现噪声或回归误判时的回滚路径（例如保留旧字段、双写或基线回退）。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md` 风险/DoD。验证：检查提案是否包含回滚步骤。

**非阻断项（Non-blocking）**
- 阈值优先级未说明：`scripts/benchmark.sh` 支持 `BENCHMARK_REGRESSION_THRESHOLD` 环境变量，但提案给出每指标阈值，未定义冲突时的优先级。建议在提案中声明“全局阈值 vs 每指标阈值”的优先级。证据：`scripts/benchmark.sh`。验证：对照脚本阈值逻辑与提案说明。
- 人类可读摘要格式未定义：提案默认“JSON + Markdown 摘要”，但未规定摘要字段与判定结论格式，可能造成归档不一致。建议给出摘要模板。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md`。验证：检查提案是否提供模板或示例。
- 资源指标采集方式需更具体：提案提到 `time/ps`，但未说明跨平台差异与单位规范。建议明确字段单位与兼容策略。证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md`。验证：检查提案是否给出采集命令与字段单位说明。

**替代方案**
- 方案 1（拆分最小闭环）：先做“指标 schema + compare 兼容”变更包，定义 `benchmark_result.json` v1.1 样例、字段路径和 `--compare` 读取逻辑；性能优化另起变更包并绑定明确指标目标。验证：提供基线/当前样例 JSON 并运行 `scripts/benchmark.sh --compare <baseline> <current>`。
- 方案 2（双轨过渡）：保留现有 `benchmark.sh` 输出格式用于回归判定，同时在 `benchmark_result.json` 中双写新字段，稳定后切换。验证：同一次运行输出两份 JSON，`--compare` 可判定且新字段存在。
- 方案 3（先扩容数据集再定阈值）：先把查询集扩充并冻结版本，再基于至少三次重复运行确定 p95/p99 阈值。验证：`wc -l tests/fixtures/benchmark/queries.jsonl` 与多次运行结果对比。

**风险与证据缺口**
- 缺少“基线结果/当前结果”样例文件与存放位置，无法验证 AC-005。需提供至少一对样例 JSON 与生成命令。验证：提供路径并运行 `scripts/benchmark.sh --compare <baseline> <current>`。
- 缺少“冷/热启动定义与缓存清理证据”，导致 `cold_latency`/`warm_latency` 不可复现。需提供清理步骤或命令。验证：提供命令与运行日志摘要。
- 缺少“指标稳定性证据”（重复运行的分位数波动范围），无法判断阈值合理性。需至少三次重复运行的结果对比。验证：提交运行记录或 JSON 差异摘要。
- 缺少“环境一致性证据”（CPU/内存/依赖版本），跨机器对比风险高。需在结果中记录环境字段或附带说明。验证：在 JSON 中补充环境字段并示例输出。
