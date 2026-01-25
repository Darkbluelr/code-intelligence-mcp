# 基准测试关键指标补齐 + 性能提升闭环提案（修订版 v4）

> `truth-root` = `dev-playbooks/specs`
> `change-root` = `dev-playbooks/changes`
> 产物位置：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md`
> 状态：Approved
> 当前版本：修订版 v4（已按 Revise Required 调整）

- 决策状态： Approved

## Why

- Value Signal and Observation: 以 `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json` 的 `result=no_regression` 为回归判定信号，并在 `benchmark_summary.median.md` 中对 `mrr_at_10`、`recall_at_10`、`precision_at_10`、`hit_rate_at_10`、`p95_latency_ms`、`semantic_search.latency_p95_ms`、`graph_rag.*_latency_p95_ms`、`precommit_*_p95_ms`、`compression_latency_ms` 等关键指标给出方向/阈值/结论；价值以“指标口径可复验 + 证据可归档 + 本变更包内交付可量化性能提升（AC-008/009/010）”体现。
- Value Stream Bottleneck Hypothesis: 端到端基准的主要瓶颈来自 Graph-RAG/语义检索路径的重复解析与图扩展（冷启动）以及缺少跨查询复用（热启动）；通过减少脚本内 `jq`/解析开销、Graph-RAG 动态早停、embedding 查询级缓存与 subgraph LRU 缓存，在质量阈值不回归的前提下降低 `*_latency_p95_ms` 并缩短 `precommit_*_p95_ms`。
- 现状痛点：`benchmark_result.json` schema v1.0 缺少关键指标与口径（分位数/迭代次数/缓存与预提交 P95/压缩耗时与 token 统计等），且 compare 仅能读顶层字段，无法覆盖 `metrics.*`。
- 闭环缺失：基线与当前产物路径未固定，`--compare` 无法形成可操作、可追溯的回归判定闭环。
- 可复现不足：缺少环境元信息与运行规则（冷/热定义、缓存清理、随机性控制），导致对比不可复验、结论不可审计。

## What Changes

- 升级 `benchmark_result.json` schema 到 v1.1：补齐关键指标，固定字段路径/单位/方向/公式/必填性，并在迁移期双写 `metrics.*` 与顶层兼容字段。
- 固定 baseline/current 的三次运行与中位数产物落点，明确 `--compare` 仅以中位数产物为唯一口径，并定义基线更新/回滚流程。
- 强化 `scripts/benchmark.sh --compare`：优先读取 `metrics.*`，缺失回退顶层；强制校验 `schema_version` 与 `queries_version` 一致性，不一致则失败并返回非零退出码。
- 在同一变更包内交付性能提升（代码/算法/架构层）：减少重复解析、Graph-RAG 动态早停、embedding 查询缓存、subgraph 缓存，并提供开关与回退策略。
- 补齐可重复证据字段与运行规则：记录 `environment.*` 与 `run.*`（冷/热定义、cache_clear、random_seed、iterations），并输出可审阅的 `benchmark_summary*.md`。

## Impact

- 对外契约：不改变 MCP 工具命名与对外语义；变更集中在基准产物 schema、基准脚本与性能相关实现。
- 产物与流程：新增/调整 baseline/current 的产物路径与“中位数口径”规范，compare 输出成为可归档证据链的一部分。
- 兼容策略：迁移期通过 v1.1 双写与 compare 回退读取，避免历史字段断档；后续移除顶层兼容字段需伴随 compare 迁移说明。

## Risks

- 性能优化引入质量回归风险（动态早停/缓存）：以质量底线阈值拦截，提供开关与回退路径，验收仅采信“全开”结果。
- 缓存键/失效策略不当导致结果不一致：缓存键纳入参数与版本，配置 TTL 与清理命令，并在产物中记录 `run.cache_clear`。
- 指标噪声导致误判：固定随机种子、记录环境与迭代次数，并以三次运行中位数作为唯一判定口径。

## Validation

- 生成 baseline/current 的三次运行产物与中位数产物，产出对应 `benchmark_summary*.md`。
- 执行 `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json`，以 `result=no_regression` 为通过判定，并在 stdout `summary=JSON` 中核对关键指标与阈值方向。
- 构造 `schema_version` 或 `queries_version` 不一致的 baseline/current，compare 必须输出失败/回归并返回非零退出码（不进行阈值比较）。
- 记录“开关全开/全关”两组 compare 结果与产物到本变更包 `evidence/`，并明确最终采信仅基于“全开”结果。

## Debate Packet

- 方案 A：拆分为两个变更包（指标闭环 vs 性能优化）。优点是风险隔离；缺点是周期变长且难以在一次交付中形成“指标→对比→优化→验收”的完整闭环。
- 方案 B：只维护 legacy 顶层字段与 compare，不升级 schema。短期改动小，但关键指标口径继续缺失，`metrics.*` 漂移问题无法根治。
- 方案 C：只做 schema/对比闭环，不在本变更包内交付性能提升。与“同一变更包内交付可量化性能提升（AC-008/009/010）”目标不一致。

## 🎯 结论先行（30秒阅读）

**本提案会导致**：
- ✅ 基准测试结果升级为 `benchmark_result.json` schema v1.1，关键指标补齐、单位/方向/公式固定。
- ✅ 基线与当前的三次运行产物分离落点（baseline：`benchmarks/baselines/run-1/`、`benchmarks/baselines/run-2/`、`benchmarks/baselines/run-3/`；current：`benchmarks/results/run-1/`、`benchmarks/results/run-2/`、`benchmarks/results/run-3/`），中位数产物固定为 `benchmarks/baselines/benchmark_result.median.json` 与 `benchmarks/results/benchmark_result.median.json`，`--compare` 以中位数为唯一口径。
- ✅ 在本变更包内完成可验证的性能提升实现（代码/算法/架构三层），并以指标验收。
- ✅ 引入可重复证据字段与运行规则（冷/热定义、缓存清理、环境与随机性）。

**本提案不会导致**：
- ❌ 不会引入新的外部服务依赖或改变联网要求。
- ❌ 不会改变 MCP 对外接口语义或工具命名规范。
- ❌ 不会在指标输出之外新增与性能无关的功能。

**一句话总结**：把基准指标与对比机制做成可验证闭环，并在同一变更包内交付可量化的性能提升。

---

## 🤔 需求对齐（5分钟阅读）

### 目标角色（固定假设）

- 质量把关者：需要稳定的回归判定与可重复证据。
- 性能改进者：需要用可量化指标驱动优化并证明提升。
- 平台维护者：需要稳定 schema 与兼容策略，便于长期演进。

### 核心需求（固定）

- A. 基准指标补齐 + 统一输出 + compare 回归判定闭环。
- B. 项目性能提升（代码/算法/架构层面）在本变更包内完成实现并可验收。
- 基线与当前结果路径固定且有生成、更新、回滚流程。
- `benchmark_result.json` schema v1.1 明确字段路径、单位、方向、公式与必填性。
- 对比脚本兼容 `metrics.*` 与顶层字段读取，避免断档。

### 关键约束（已决策）

- 统一输出格式：JSON + Markdown 摘要（机器对比 + 人工审阅）。
- 基线策略：固定基线，仅在验收通过后通过显式命令更新。
- 分位数迭代次数：默认 N=5（可配置，但结果中必须记录 iterations）。
- 查询集：扩充到 ≥10 条并冻结 `queries_version`。

---

## 📋 详细提案（AI阅读）

### Why（为什么要改）

#### 问题描述

- `benchmark_result.json` 仍为 schema v1.0，缺少分位数、迭代次数、缓存/预提交 P95、压缩耗时与 token 统计等关键指标，且 compare 只能读顶层字段，无法覆盖 `metrics.*`。
- 基线与当前产物路径未固定，`scripts/benchmark.sh --compare` 无法形成可操作闭环。
- 缺少环境元信息与运行规则，导致性能对比不可复现。

#### 影响

- 性能回归无法自动判定，优化效果无法被证据化验证。
- 指标口径不一致，跨版本对比失真。

---

### What（要改什么）

#### 交付范围 A：指标补齐 + 统一输出 + compare 闭环

1) **固定产物路径与流程**
- Baseline runs：
  - `benchmarks/baselines/run-1/benchmark_result.json`
  - `benchmarks/baselines/run-2/benchmark_result.json`
  - `benchmarks/baselines/run-3/benchmark_result.json`
- Baseline median：`benchmarks/baselines/benchmark_result.median.json`
- Current runs：
  - `benchmarks/results/run-1/benchmark_result.json`
  - `benchmarks/results/run-2/benchmark_result.json`
  - `benchmarks/results/run-3/benchmark_result.json`
- Current median：`benchmarks/results/benchmark_result.median.json`

**生成流程**
- 生成 current（三次完整基准运行）：
  - `python benchmarks/run_benchmarks.py --output benchmarks/results/run-1/benchmark_result.json`
  - `python benchmarks/run_benchmarks.py --output benchmarks/results/run-2/benchmark_result.json`
  - `python benchmarks/run_benchmarks.py --output benchmarks/results/run-3/benchmark_result.json`
- 生成 current 中位数产物：按“性能验收统计口径”的规则从 run-1、run-2、run-3 计算，输出到 `benchmarks/results/benchmark_result.median.json` 与 `benchmarks/results/benchmark_summary.median.md`。
- 生成 compare 结果（使用中位数产物）：
  - `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json`

**更新条件**
- compare 结果为通过（无回归）且本变更包验收通过后，执行显式更新命令（同步中位数与 3 次运行产物）：
  - `cp benchmarks/results/benchmark_result.median.json benchmarks/baselines/benchmark_result.median.json`
  - `cp benchmarks/results/benchmark_summary.median.md benchmarks/baselines/benchmark_summary.median.md`
  - `cp benchmarks/results/run-1/benchmark_result.json benchmarks/baselines/run-1/benchmark_result.json`
  - `cp benchmarks/results/run-1/benchmark_summary.md benchmarks/baselines/run-1/benchmark_summary.md`
  - `cp benchmarks/results/run-2/benchmark_result.json benchmarks/baselines/run-2/benchmark_result.json`
  - `cp benchmarks/results/run-2/benchmark_summary.md benchmarks/baselines/run-2/benchmark_summary.md`
  - `cp benchmarks/results/run-3/benchmark_result.json benchmarks/baselines/run-3/benchmark_result.json`
  - `cp benchmarks/results/run-3/benchmark_summary.md benchmarks/baselines/run-3/benchmark_summary.md`

**回滚**
- 基线更新前保留目录级备份：
  - `cp -R benchmarks/baselines benchmarks/baselines.bak`
- 回滚操作：
  - `rm -rf benchmarks/baselines`
  - `mv benchmarks/baselines.bak benchmarks/baselines`

2) **统一输出产物（JSON + Markdown）**

- Baseline JSON（单次运行）：
  - `benchmarks/baselines/run-1/benchmark_result.json`
  - `benchmarks/baselines/run-2/benchmark_result.json`
  - `benchmarks/baselines/run-3/benchmark_result.json`
- Baseline JSON（中位数）：`benchmarks/baselines/benchmark_result.median.json`
- Baseline Markdown 摘要（单次运行）：
  - `benchmarks/baselines/run-1/benchmark_summary.md`
  - `benchmarks/baselines/run-2/benchmark_summary.md`
  - `benchmarks/baselines/run-3/benchmark_summary.md`
- Baseline Markdown 摘要（中位数）：`benchmarks/baselines/benchmark_summary.median.md`
- Current JSON（单次运行）：
  - `benchmarks/results/run-1/benchmark_result.json`
  - `benchmarks/results/run-2/benchmark_result.json`
  - `benchmarks/results/run-3/benchmark_result.json`
- Current JSON（中位数）：`benchmarks/results/benchmark_result.median.json`
- Current Markdown 摘要（单次运行）：
  - `benchmarks/results/run-1/benchmark_summary.md`
  - `benchmarks/results/run-2/benchmark_summary.md`
  - `benchmarks/results/run-3/benchmark_summary.md`
- Current Markdown 摘要（中位数）：`benchmarks/results/benchmark_summary.median.md`

**摘要格式（固定模板）**
```
# Benchmark Summary

- generated_at: 2026-01-23T07:15:00Z
- schema_version: 1.1
- queries_version: sha256:1a2b3c4d
- result: pass

## Environment
- os: macOS 14.2 23.2.0
- cpu: Apple M2 8 cores / 8 threads / arm64
- memory_total_mb: 16384
- node: v20.11.0
- python: 3.11.6
- rg: 13.0.0
- jq: 1.7
- git: 2.43.0

## Regression Summary
| metric | direction | baseline | current | threshold | result |
|---|---|---:|---:|---:|---|
| mrr_at_10 | higher | 0.30 | 0.31 | 0.285 | pass |
| recall_at_10 | higher | 0.28 | 0.29 | 0.266 | pass |
| precision_at_10 | higher | 0.25 | 0.24 | 0.237 | pass |
| hit_rate_at_10 | higher | 0.60 | 0.61 | 0.57 | pass |
| p50_latency_ms | lower | 40 | 38 | 44 | pass |
| p95_latency_ms | lower | 80 | 75 | 88 | pass |
| p99_latency_ms | lower | 120 | 118 | 132 | pass |
| semantic_search.latency_p95_ms | lower | 900 | 860 | 990 | pass |
| graph_rag.warm_latency_p95_ms | lower | 300 | 270 | 330 | pass |
| graph_rag.cold_latency_p95_ms | lower | 420 | 400 | 462 | pass |
| cache_hit_p95_ms | lower | 90 | 85 | 99 | pass |
| full_query_p95_ms | lower | 480 | 470 | 528 | pass |
| precommit_staged_p95_ms | lower | 1800 | 1700 | 1980 | pass |
| precommit_deps_p95_ms | lower | 4200 | 4100 | 4620 | pass |
| compression_latency_ms | lower | 1500 | 1400 | 1650 | pass |
```

3) **`scripts/benchmark.sh --compare` 预期输出与阈值规则**

**输入（固定为中位数产物）**
- `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json`

**输出（stdout）**
- 第一行：`result=no_regression` 或 `result=regression`
- 第二行：`summary=JSON`，固定字段如下（示例值用于展示格式）：

```json
{"status":"pass","threshold_mode":"per-metric","metrics":[{"name":"mrr_at_10","direction":"higher","baseline":0.30,"current":0.31,"threshold":0.285,"result":"pass"},{"name":"recall_at_10","direction":"higher","baseline":0.28,"current":0.29,"threshold":0.266,"result":"pass"},{"name":"precision_at_10","direction":"higher","baseline":0.25,"current":0.24,"threshold":0.237,"result":"pass"},{"name":"hit_rate_at_10","direction":"higher","baseline":0.60,"current":0.61,"threshold":0.57,"result":"pass"},{"name":"p50_latency_ms","direction":"lower","baseline":40,"current":38,"threshold":44,"result":"pass"},{"name":"p95_latency_ms","direction":"lower","baseline":80,"current":75,"threshold":88,"result":"pass"},{"name":"p99_latency_ms","direction":"lower","baseline":120,"current":118,"threshold":132,"result":"pass"},{"name":"semantic_search.latency_p95_ms","direction":"lower","baseline":900,"current":860,"threshold":990,"result":"pass"},{"name":"graph_rag.warm_latency_p95_ms","direction":"lower","baseline":300,"current":270,"threshold":330,"result":"pass"},{"name":"graph_rag.cold_latency_p95_ms","direction":"lower","baseline":420,"current":400,"threshold":462,"result":"pass"},{"name":"cache_hit_p95_ms","direction":"lower","baseline":90,"current":85,"threshold":99,"result":"pass"},{"name":"full_query_p95_ms","direction":"lower","baseline":480,"current":470,"threshold":528,"result":"pass"},{"name":"precommit_staged_p95_ms","direction":"lower","baseline":1800,"current":1700,"threshold":1980,"result":"pass"},{"name":"precommit_deps_p95_ms","direction":"lower","baseline":4200,"current":4100,"threshold":4620,"result":"pass"},{"name":"compression_latency_ms","direction":"lower","baseline":1500,"current":1400,"threshold":1650,"result":"pass"}]}
```

**版本对齐校验（强制）**
- baseline 与 current 的 `schema_version` 与 `queries_version` 必须一致；不一致时 compare 必须：
  - stdout 第一行输出 `result=regression`
  - stdout 第二行 `summary=JSON`，包含 `status="fail"`、`reason="version_mismatch"`、`baseline.schema_version`/`current.schema_version`、`baseline.queries_version`/`current.queries_version`
  - 退出码非零（建议 2），且不进行任何指标阈值比较

**阈值规则**
- 每指标阈值优先级：`metric.threshold`（显式配置） > `BENCHMARK_REGRESSION_THRESHOLD`（全局相对阈值） > 默认规则。
- 默认规则：
  - 方向为 **higher**：`threshold = baseline * 0.95`（当前 < threshold 判定回归）
  - 方向为 **lower**：`threshold = baseline * 1.10`（当前 > threshold 判定回归）
- `BENCHMARK_REGRESSION_THRESHOLD = t` 时：
  - higher：`threshold = baseline * (1 - t)`
  - lower：`threshold = baseline * (1 + t)`
- `precision_at_10` 纳入回归判定门槛，与 `mrr_at_10`/`recall_at_10`/`hit_rate_at_10` 同口径比较。

4) **schema v1.1（字段路径/单位/方向/公式/必填性）**

| 字段路径 | 类型 | 单位 | 方向 | 计算公式/来源 | 必填 |
|---|---|---|---|---|---|
| schema_version | string | - | - | 固定为 `"1.1"` | 必填 |
| generated_at | string(ISO8601) | - | - | 生成时间 | 必填 |
| project_root | string | - | - | 项目根目录 | 必填 |
| git_commit | string | - | - | `git rev-parse HEAD` | 可选 |
| queries_version | string | - | - | 查询集版本号（冻结） | 必填 |
| run.mode | string | - | - | `full` / `dataset` / `legacy` | 必填 |
| run.cold_definition | string | - | - | 冷启动定义说明 | 必填 |
| run.warm_definition | string | - | - | 热启动定义说明 | 必填 |
| run.cache_clear | array(string) | - | - | 缓存清理命令清单 | 必填 |
| run.random_seed | integer | - | - | 随机种子 | 必填 |
| environment.os.name | string | - | - | 操作系统名称 | 必填 |
| environment.os.version | string | - | - | 操作系统版本 | 必填 |
| environment.os.kernel | string | - | - | 内核版本 | 必填 |
| environment.cpu.model | string | - | - | CPU 型号 | 必填 |
| environment.cpu.cores | integer | 核 | - | 物理核心数 | 必填 |
| environment.cpu.threads | integer | 线程 | - | 逻辑线程数 | 必填 |
| environment.cpu.arch | string | - | - | 架构（x86_64/arm64） | 必填 |
| environment.memory.total_mb | integer | MB | - | 总内存 | 必填 |
| environment.runtime.node | string | - | - | `node -v` | 必填 |
| environment.runtime.python | string | - | - | `python --version` | 必填 |
| environment.dependencies.rg | string | - | - | `rg --version` | 必填 |
| environment.dependencies.jq | string | - | - | `jq --version` | 必填 |
| environment.dependencies.git | string | - | - | `git --version` | 必填 |
| metrics.semantic_search.iterations | integer | 次 | - | 运行次数 | 必填 |
| metrics.semantic_search.latency_p50_ms | number | ms | lower | N 次延迟 P50 | 必填 |
| metrics.semantic_search.latency_p95_ms | number | ms | lower | N 次延迟 P95 | 必填 |
| metrics.semantic_search.latency_p99_ms | number | ms | lower | N 次延迟 P99 | 必填 |
| metrics.graph_rag.iterations | integer | 次 | - | 运行次数 | 必填 |
| metrics.graph_rag.cold_latency_p50_ms | number | ms | lower | 冷启动延迟 P50 | 必填 |
| metrics.graph_rag.cold_latency_p95_ms | number | ms | lower | 冷启动延迟 P95 | 必填 |
| metrics.graph_rag.cold_latency_p99_ms | number | ms | lower | 冷启动延迟 P99 | 必填 |
| metrics.graph_rag.warm_latency_p50_ms | number | ms | lower | 热启动延迟 P50 | 必填 |
| metrics.graph_rag.warm_latency_p95_ms | number | ms | lower | 热启动延迟 P95 | 必填 |
| metrics.graph_rag.warm_latency_p99_ms | number | ms | lower | 热启动延迟 P99 | 必填 |
| metrics.graph_rag.speedup_pct | number | % | higher | `(cold_p95 - warm_p95) / cold_p95 * 100` | 必填 |
| metrics.retrieval_quality.iterations | integer | 次 | - | 运行次数 | 必填 |
| metrics.retrieval_quality.dataset | string | - | - | `self`/`public` | 必填 |
| metrics.retrieval_quality.query_count | integer | 条 | - | 有效查询数 | 必填 |
| metrics.retrieval_quality.expected_count | integer | 条 | - | `sum(expected[])` | 必填 |
| metrics.retrieval_quality.mrr_at_10 | number | - | higher | `sum(1/rank) / query_count` | 必填 |
| metrics.retrieval_quality.recall_at_10 | number | - | higher | `hits / query_count` | 必填 |
| metrics.retrieval_quality.precision_at_10 | number | - | higher | `relevant/retrieved` 均值 | 必填 |
| metrics.retrieval_quality.hit_rate_at_10 | number | - | higher | `queries_with_hit / query_count` | 必填 |
| metrics.retrieval_quality.latency_p50_ms | number | ms | lower | 查询延迟 P50 | 必填 |
| metrics.retrieval_quality.latency_p95_ms | number | ms | lower | 查询延迟 P95 | 必填 |
| metrics.retrieval_quality.latency_p99_ms | number | ms | lower | 查询延迟 P99 | 必填 |
| metrics.context_compression.iterations | integer | 次 | - | 运行次数 | 必填 |
| metrics.context_compression.compression_latency_ms | number | ms | lower | 压缩命令耗时 | 必填 |
| metrics.context_compression.tokens_before | integer | token | - | 原始 token 数 | 必填 |
| metrics.context_compression.tokens_after | integer | token | - | 压缩后 token 数 | 必填 |
| metrics.context_compression.compression_ratio | number | - | lower | `tokens_after / tokens_before` | 必填 |
| metrics.context_compression.information_retention | number | - | higher | `retained_key_lines / original_key_lines` | 必填 |
| metrics.context_compression.compression_level | string | - | - | `low/medium/high` | 必填 |
| metrics.cache.iterations | integer | 次 | - | 运行次数 | 必填 |
| metrics.cache.cache_hit_p95_ms | number | ms | lower | 缓存命中 P95 | 必填 |
| metrics.cache.full_query_p95_ms | number | ms | lower | 全量查询 P95 | 必填 |
| metrics.cache.precommit_staged_p95_ms | number | ms | lower | 预提交 staged P95 | 必填 |
| metrics.cache.precommit_deps_p95_ms | number | ms | lower | 预提交 deps P95 | 必填 |
| mrr_at_10 | number | - | higher | `metrics.retrieval_quality.mrr_at_10` 兼容字段 | 必填 |
| recall_at_10 | number | - | higher | `metrics.retrieval_quality.recall_at_10` 兼容字段 | 必填 |
| precision_at_10 | number | - | higher | `metrics.retrieval_quality.precision_at_10` 兼容字段 | 必填 |
| hit_rate_at_10 | number | - | higher | `metrics.retrieval_quality.hit_rate_at_10` 兼容字段 | 必填 |
| p50_latency_ms | number | ms | lower | `metrics.retrieval_quality.latency_p50_ms` 兼容字段 | 必填 |
| p95_latency_ms | number | ms | lower | `metrics.retrieval_quality.latency_p95_ms` 兼容字段 | 必填 |
| p99_latency_ms | number | ms | lower | `metrics.retrieval_quality.latency_p99_ms` 兼容字段 | 必填 |
| cache_hit_p95_ms | number | ms | lower | `metrics.cache.cache_hit_p95_ms` 兼容字段 | 必填 |
| full_query_p95_ms | number | ms | lower | `metrics.cache.full_query_p95_ms` 兼容字段 | 必填 |
| precommit_staged_p95_ms | number | ms | lower | `metrics.cache.precommit_staged_p95_ms` 兼容字段 | 必填 |
| precommit_deps_p95_ms | number | ms | lower | `metrics.cache.precommit_deps_p95_ms` 兼容字段 | 必填 |
| compression_latency_ms | number | ms | lower | `metrics.context_compression.compression_latency_ms` 兼容字段 | 必填 |

5) **`queries_version` 命名与更新规则**
- 命名：推荐 `queries_version = "sha256:1a2b3c4d"`，取 `tests/fixtures/benchmark/queries.jsonl` 内容的 SHA-256 前 8 位。
- 示例：`queries_version = "sha256:1a2b3c4d"`。
- 可执行校验（macOS）：`shasum -a 256 tests/fixtures/benchmark/queries.jsonl | cut -c1-8` → 输出 `1a2b3c4d`，JSON 中填 `queries_version = "sha256:1a2b3c4d"`。
- 可执行校验（Linux）：`sha256sum tests/fixtures/benchmark/queries.jsonl | cut -c1-8` → 输出 `1a2b3c4d`，与 JSON 中 `sha256:1a2b3c4d` 对齐。
- 更新触发：`tests/fixtures/benchmark/queries.jsonl` 内容有任何变更（增删、顺序、字段）时必须更新。
- compare 校验：compare 必须校验 baseline/current 的 `queries_version` 一致性；不一致走“版本对齐校验”失败路径。

6) **最小 baseline/current JSON 与 `benchmark_summary.median.md` 样例**

**baseline 中位数（`benchmarks/baselines/benchmark_result.median.json`）**
```json
{
  "schema_version": "1.1",
  "generated_at": "2026-01-23T07:15:00Z",
  "project_root": "/Users/ozbombor/Projects/code-intelligence-mcp",
  "git_commit": "abcdef1234567890",
  "queries_version": "sha256:1a2b3c4d",
  "run": {
    "mode": "full",
    "cold_definition": "cache cleared before each cold sample",
    "warm_definition": "same process, cache retained, N consecutive queries",
    "cache_clear": [
      "rm -rf ${TMPDIR:-/tmp}/.ci-cache",
      "rm -rf ${TMPDIR:-/tmp}/.devbooks-cache/graph-rag",
      "scripts/cache-manager.sh cache-clear"
    ],
    "random_seed": 42
  },
  "environment": {
    "os": {
      "name": "macOS",
      "version": "14.2",
      "kernel": "23.2.0"
    },
    "cpu": {
      "model": "Apple M2",
      "cores": 8,
      "threads": 8,
      "arch": "arm64"
    },
    "memory": {
      "total_mb": 16384
    },
    "runtime": {
      "node": "v20.11.0",
      "python": "Python 3.11.7"
    },
    "dependencies": {
      "rg": "14.1.0",
      "jq": "1.7",
      "git": "2.43.0"
    }
  },
  "metrics": {
    "semantic_search": {
      "iterations": 5,
      "latency_p50_ms": 35,
      "latency_p95_ms": 70,
      "latency_p99_ms": 100
    },
    "graph_rag": {
      "iterations": 5,
      "cold_latency_p50_ms": 250,
      "cold_latency_p95_ms": 420,
      "cold_latency_p99_ms": 520,
      "warm_latency_p50_ms": 180,
      "warm_latency_p95_ms": 300,
      "warm_latency_p99_ms": 380,
      "speedup_pct": 28.6
    },
    "retrieval_quality": {
      "iterations": 5,
      "dataset": "self",
      "query_count": 12,
      "expected_count": 12,
      "mrr_at_10": 0.30,
      "recall_at_10": 0.28,
      "precision_at_10": 0.25,
      "hit_rate_at_10": 0.60,
      "latency_p50_ms": 40,
      "latency_p95_ms": 80,
      "latency_p99_ms": 120
    },
    "context_compression": {
      "iterations": 5,
      "compression_latency_ms": 1500,
      "tokens_before": 2000,
      "tokens_after": 800,
      "compression_ratio": 0.40,
      "information_retention": 0.78,
      "compression_level": "medium"
    },
    "cache": {
      "iterations": 5,
      "cache_hit_p95_ms": 90,
      "full_query_p95_ms": 480,
      "precommit_staged_p95_ms": 1800,
      "precommit_deps_p95_ms": 4200
    }
  },
  "mrr_at_10": 0.30,
  "recall_at_10": 0.28,
  "precision_at_10": 0.25,
  "hit_rate_at_10": 0.60,
  "p50_latency_ms": 40,
  "p95_latency_ms": 80,
  "p99_latency_ms": 120,
  "cache_hit_p95_ms": 90,
  "full_query_p95_ms": 480,
  "precommit_staged_p95_ms": 1800,
  "precommit_deps_p95_ms": 4200,
  "compression_latency_ms": 1500
}
```

**current 中位数（`benchmarks/results/benchmark_result.median.json`）**
```json
{
  "schema_version": "1.1",
  "generated_at": "2026-01-23T07:45:00Z",
  "project_root": "/Users/ozbombor/Projects/code-intelligence-mcp",
  "git_commit": "abcdef1234567890",
  "queries_version": "sha256:1a2b3c4d",
  "run": {
    "mode": "full",
    "cold_definition": "cache cleared before each cold sample",
    "warm_definition": "same process, cache retained, N consecutive queries",
    "cache_clear": [
      "rm -rf ${TMPDIR:-/tmp}/.ci-cache",
      "rm -rf ${TMPDIR:-/tmp}/.devbooks-cache/graph-rag",
      "scripts/cache-manager.sh cache-clear"
    ],
    "random_seed": 42
  },
  "environment": {
    "os": {
      "name": "macOS",
      "version": "14.2",
      "kernel": "23.2.0"
    },
    "cpu": {
      "model": "Apple M2",
      "cores": 8,
      "threads": 8,
      "arch": "arm64"
    },
    "memory": {
      "total_mb": 16384
    },
    "runtime": {
      "node": "v20.11.0",
      "python": "Python 3.11.7"
    },
    "dependencies": {
      "rg": "14.1.0",
      "jq": "1.7",
      "git": "2.43.0"
    }
  },
  "metrics": {
    "semantic_search": {
      "iterations": 5,
      "latency_p50_ms": 33,
      "latency_p95_ms": 65,
      "latency_p99_ms": 95
    },
    "graph_rag": {
      "iterations": 5,
      "cold_latency_p50_ms": 230,
      "cold_latency_p95_ms": 400,
      "cold_latency_p99_ms": 500,
      "warm_latency_p50_ms": 170,
      "warm_latency_p95_ms": 270,
      "warm_latency_p99_ms": 360,
      "speedup_pct": 32.5
    },
    "retrieval_quality": {
      "iterations": 5,
      "dataset": "self",
      "query_count": 12,
      "expected_count": 12,
      "mrr_at_10": 0.31,
      "recall_at_10": 0.29,
      "precision_at_10": 0.26,
      "hit_rate_at_10": 0.62,
      "latency_p50_ms": 38,
      "latency_p95_ms": 75,
      "latency_p99_ms": 110
    },
    "context_compression": {
      "iterations": 5,
      "compression_latency_ms": 1400,
      "tokens_before": 2000,
      "tokens_after": 780,
      "compression_ratio": 0.39,
      "information_retention": 0.80,
      "compression_level": "medium"
    },
    "cache": {
      "iterations": 5,
      "cache_hit_p95_ms": 85,
      "full_query_p95_ms": 470,
      "precommit_staged_p95_ms": 1700,
      "precommit_deps_p95_ms": 4100
    }
  },
  "mrr_at_10": 0.31,
  "recall_at_10": 0.29,
  "precision_at_10": 0.26,
  "hit_rate_at_10": 0.62,
  "p50_latency_ms": 38,
  "p95_latency_ms": 75,
  "p99_latency_ms": 110,
  "cache_hit_p95_ms": 85,
  "full_query_p95_ms": 470,
  "precommit_staged_p95_ms": 1700,
  "precommit_deps_p95_ms": 4100,
  "compression_latency_ms": 1400
}
```

**`benchmark_summary.median.md` 样例（与上述 baseline/current 中位数对应）**
```markdown
# Benchmark Summary

- generated_at: 2026-01-23T07:45:00Z
- schema_version: 1.1
- queries_version: sha256:1a2b3c4d
- result: pass

## Environment
- os: macOS 14.2 23.2.0
- cpu: Apple M2 8 cores / 8 threads / arm64
- memory_total_mb: 16384
- node: v20.11.0
- python: Python 3.11.7
- rg: 14.1.0
- jq: 1.7
- git: 2.43.0

## Regression Summary
| metric | direction | baseline | current | threshold | result |
|---|---|---:|---:|---:|---|
| mrr_at_10 | higher | 0.30 | 0.31 | 0.285 | pass |
| recall_at_10 | higher | 0.28 | 0.29 | 0.266 | pass |
| precision_at_10 | higher | 0.25 | 0.26 | 0.237 | pass |
| hit_rate_at_10 | higher | 0.60 | 0.62 | 0.57 | pass |
| p50_latency_ms | lower | 40 | 38 | 44 | pass |
| p95_latency_ms | lower | 80 | 75 | 88 | pass |
| p99_latency_ms | lower | 120 | 110 | 132 | pass |
| semantic_search.latency_p95_ms | lower | 70 | 65 | 77 | pass |
| graph_rag.warm_latency_p95_ms | lower | 300 | 270 | 330 | pass |
| graph_rag.cold_latency_p95_ms | lower | 420 | 400 | 462 | pass |
| cache_hit_p95_ms | lower | 90 | 85 | 99 | pass |
| full_query_p95_ms | lower | 480 | 470 | 528 | pass |
| precommit_staged_p95_ms | lower | 1800 | 1700 | 1980 | pass |
| precommit_deps_p95_ms | lower | 4200 | 4100 | 4620 | pass |
| compression_latency_ms | lower | 1500 | 1400 | 1650 | pass |
```

7) **compare 兼容策略**
- **双写**：schema v1.1 同时写入 `metrics.*` 与顶层兼容字段（mrr/recall/precision/hit_rate/p50/p95/p99、cache/precommit、compression_latency）。
- **兼容读取**：`scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json` 优先读取 `metrics.*`，缺失时回退到顶层字段。
- **迁移期策略**：v1.1 维持双写；v1.2 后移除顶层兼容字段时必须更新 compare 并提供迁移说明。

8) **可重复证据字段与运行规则**
- 冷启动定义：每次冷启动样本都在**清理缓存后**执行一次查询。
- 热启动定义：在不清理缓存的前提下，连续执行 N 次查询。
- 缓存清理命令清单（必须写入 `run.cache_clear`）：
  - `rm -rf ${TMPDIR:-/tmp}/.ci-cache`
  - `rm -rf ${TMPDIR:-/tmp}/.devbooks-cache/graph-rag`
  - `scripts/cache-manager.sh cache-clear`
- 环境信息：写入 `environment.*`（OS/CPU/内存/Node/Python/rg/jq/git）。
- 随机性控制：`run.random_seed` 固定（默认 42），查询集顺序固定为文件顺序。

#### 交付范围 B：性能提升实现（代码/算法/架构）

1) **代码层：减少 Graph-RAG 与语义搜索的重复解析开销**
- 变更点：
  - `scripts/graph-rag-query.sh`：减少循环内多次 `jq` 调用，改为一次性提取所需字段再迭代处理。
  - `scripts/embedding.sh`：加入查询级缓存（基于 query + top_k + index_version），复用 `cache-manager.sh`。
- 验证方法：
  - 语义搜索 `latency_p95_ms` 与 Graph-RAG `warm_latency_p95_ms` 对比基线下降。

2) **算法层：Graph-RAG 动态早停**
- 变更点：
  - 当向量候选已满足 `MIN_RELEVANCE` 且数量达到 `TOP_K` 时，跳过图扩展与 RRF 融合。
  - 低相关度查询自动降低 `MAX_DEPTH`，减少扩展范围。
- 验证方法：
  - Graph-RAG `cold_latency_p95_ms` 下降，且 `retrieval_quality.*` 不低于基线阈值。

3) **架构层：持久化子图缓存**
- 变更点：
  - 使用 `cache-manager.sh` 的 subgraph LRU 缓存保存图扩展结果，缓存键包含 query + depth + fusion_weights + top_k。
  - 设定 TTL 与最大条目数，避免缓存膨胀。
- 验证方法：
  - Graph-RAG `warm_latency_p95_ms` 下降且缓存命中率可观（通过缓存统计输出验证）。

#### 性能开关与回退策略

- 开关与默认值（默认开启，关闭=0）：
  - `CI_BENCH_EARLY_STOP`：Graph-RAG 动态早停开关（默认 `1`）
  - `CI_BENCH_SUBGRAPH_CACHE`：子图缓存开关（默认 `1`）
  - `CI_BENCH_EMBEDDING_QUERY_CACHE`：embedding 查询缓存开关（默认 `1`）
- 验收边界：AC-008/009/010 的通过判定仅基于“开关全部开启”的 3 次运行中位数结果；开关关闭仅用于安全回退与诊断，不计入验收通过。
- 回退路径：若质量指标低于阈值或 compare 不通过，则在同机同环境将上述开关全部设为 `0`，执行 `run.cache_clear` 中的清理命令，重新跑 3 次完整基准并生成 current 中位数产物后，使用 `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json`；关闭开关结果不作为验收通过依据。
- 证据要求：`evidence/` 中必须记录“开关开启/关闭”两组 compare 结果（含 baseline/current 的 `benchmark_result.median.json` 与 `benchmark_summary.median.md`），并标注采信仅基于开启结果。

---

### Impact（影响分析）

#### Transaction Scope

- None

#### 受影响的模块

| 模块 | 影响类型 | 影响程度 |
|------|----------|----------|
| `benchmarks/run_benchmarks.py` | 修改 | 中 |
| `scripts/benchmark.sh` | 修改 | 中 |
| `benchmark_result.json` | 结构升级 | 中 |
| `tests/fixtures/benchmark/queries.jsonl` | 扩充 | 中 |
| `scripts/graph-rag-query.sh` | 修改 | 中 |
| `scripts/graph-rag-core.sh` | 修改 | 中 |
| `scripts/embedding.sh` | 修改 | 中 |
| `scripts/cache-manager.sh` | 配置/调用调整 | 低 |

#### 风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 动态早停导致质量下降 | 中 | 中 | 质量指标设置底线阈值，低于阈值则禁用早停 |
| 缓存失效导致结果不一致 | 中 | 中 | 缓存键加入参数与版本；设置 TTL；提供清理命令 |
| 指标噪声导致误判 | 中 | 中 | 固定随机种子，记录环境与迭代次数 |
| 查询集扩充影响历史可比性 | 中 | 低 | 固定 `queries_version`，基线随版本更新 |

---

### Alternatives（备选方案）

#### 方案 A：拆分为两个变更包（未采用）

- 优势：指标闭环与性能优化风险隔离
- 劣势：周期变长，无法在本次形成完整闭环
- 结论：不采用，按要求在同一变更包内交付 A+B

#### 方案 B：仅维持 legacy compare（未采用）

- 优势：改动面最小
- 劣势：无法覆盖 `metrics.*` 与新增指标
- 结论：不采用，必须实现兼容读取与双写

---

### Decisions（已决策）

- 统一输出方案：`benchmark_result.json` schema v1.1 + 顶层兼容字段双写。
- 基线策略：固定基线路径，更新必须通过显式命令与验收。
- 产物形式：JSON + Markdown 摘要（模板已在本提案定义）。
- 分位数迭代次数：默认 N=5，写入 `iterations`。
- 查询集：扩充到 ≥10 条并冻结 `queries_version`。
- compare 兼容策略：`metrics.*` 优先读取，顶层字段回退。

---

### 性能验收统计口径

- baseline 与 current 各进行 ≥3 次完整基准运行（同机同环境），每次产出完整 JSON 与 `benchmark_summary.md`。
- baseline 运行产物（JSON）：
  - `benchmarks/baselines/run-1/benchmark_result.json`
  - `benchmarks/baselines/run-2/benchmark_result.json`
  - `benchmarks/baselines/run-3/benchmark_result.json`
- baseline 运行产物（摘要）：
  - `benchmarks/baselines/run-1/benchmark_summary.md`
  - `benchmarks/baselines/run-2/benchmark_summary.md`
  - `benchmarks/baselines/run-3/benchmark_summary.md`
- current 运行产物（JSON）：
  - `benchmarks/results/run-1/benchmark_result.json`
  - `benchmarks/results/run-2/benchmark_result.json`
  - `benchmarks/results/run-3/benchmark_result.json`
- current 运行产物（摘要）：
  - `benchmarks/results/run-1/benchmark_summary.md`
  - `benchmarks/results/run-2/benchmark_summary.md`
  - `benchmarks/results/run-3/benchmark_summary.md`
- 对 AC-008/009/010 涉及的指标，取 3 次结果的中位数进行阈值比较（降低噪声与偶发抖动）。
- baseline 中位数产物：`benchmarks/baselines/benchmark_result.median.json` 与 `benchmarks/baselines/benchmark_summary.median.md`。
- current 中位数产物：`benchmarks/results/benchmark_result.median.json` 与 `benchmarks/results/benchmark_summary.median.md`。
- compare 输入固定为中位数产物：`scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json`；这是 AC-008/009/010 的唯一采信口径。
- 中位数计算规则：对同一指标的三次数值结果按数值排序取中间值；方向字段仅用于阈值比较，不参与中位数计算。

### DoD/验收锚点（基准测试与性能提升闭环）

- AC-001：`benchmark_result.json` schema_version = 1.1，字段满足 “schema v1.1” 表中必填要求。
- AC-002：基线与当前产物路径固定（baseline/current 各 3 次运行 + 中位数），`scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json` 输出符合本提案定义格式，exit code 与回归判定一致。
- AC-003：`metrics.*` 与顶层兼容字段双写，compare 能读取新旧字段。
- AC-004：分位数与 iterations 覆盖语义搜索、Graph-RAG、检索质量三类指标。
- AC-005：cache_hit/full_query/precommit P95 指标写入 `benchmark_result.json`。
- AC-006：压缩耗时与 tokens（before/after）写入 `benchmark_result.json`，`compression_ratio` 与 `information_retention` 有公式且可计算。
- AC-007：环境元信息与运行规则写入 `environment.*` 与 `run.*`。
- 验收边界（强制）：AC-008/009/010 的通过判定仅基于“开关全部开启”的 3 次运行中位数结果；比较使用 `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json`，该 compare 为唯一采信口径；开关关闭仅用于安全回退与诊断，不计入验收通过。
- AC-008：Graph-RAG `warm_latency_p95_ms` ≤ 基线中位数 * 0.90，`cold_latency_p95_ms` ≤ 基线中位数 * 0.95（以 baseline/current 各 3 次运行中位数对比）。
- AC-009：语义搜索 `latency_p95_ms` ≤ 基线中位数 * 0.95（以 baseline/current 各 3 次运行中位数对比）。
- AC-010：`retrieval_quality.mrr_at_10`、`recall_at_10`、`precision_at_10`、`hit_rate_at_10` ≥ 基线中位数 * 0.95（以 baseline/current 各 3 次运行中位数对比）。

**证据建议落点**：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/`

---

## 批准历史

| 时间 | 阶段 | 操作 | 操作者 | 理由 |
|------|------|------|--------|------|
| 2026-01-22T23:17:06Z | Proposal | 创建 | AI | - |

## Decision Log

### 2026-01-22 裁决：Revise

**理由摘要**：
- 目标与范围不一致：当前承诺“性能提升方向”但不交付优化实现，无法形成真实性能提升闭环。
- 回归判定机制与目标输出不兼容：`scripts/benchmark.sh --compare` 仅读取顶层字段，而 `benchmark_result.json` 采用 `metrics.*` 结构，AC-005 现状不可验证。
- 基线策略不可执行：缺少基线文件路径、生成/更新/回滚流程，AC-005 依赖的 baseline/current 产物未定义。
- 指标口径不完整：`compression_ratio`、`speedup_pct`、`hit_rate_at_10` 等缺少方向与公式，阈值不可验证。
- Schema 与可重复证据缺失：字段路径/必填项/版本升级策略与环境信息未明确，跨版本对比缺乏证据基础。

**必须修改项**（若 Revise）：
- [ ] 将本变更包目标明确为“指标与回归判定闭环”，性能优化实现拆分到后续变更包；同步修订标题、结论、范围、DoD 与“性能提升方向”表述，删除所有交互式裁决/表单式措辞。
- [ ] 直接落地决策并写入提案：方案 A（统一输出）为最终方案；基线策略=固定基线；产物形式=JSON + Markdown 摘要；分位数迭代次数=N=5；资源指标=可选且不作为回归门槛；查询集规模=扩充到 ≥10 条并冻结版本。
- [ ] 明确基线文件与流程：基线产物路径固定为 `benchmarks/baselines/benchmark_result.json`；给出生成命令、更新条件（需显式批准）与回滚步骤；明确 current 产物路径与 `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json` 的使用方式。
- [ ] 对 `benchmark_result.json` 给出 schema v1.1 约定：字段完整路径、必填/可选、单位、方向（越大越好/越小越好）与公式；覆盖 `compression_ratio`、`speedup_pct`、`hit_rate_at_10`、`expected_count` 的计算定义。
- [ ] 说明回归判定口径的兼容策略：`scripts/benchmark.sh --compare` 的读取路径与阈值优先级（全局阈值 vs 单项阈值），以及 legacy/dataset 的映射规则。
- [ ] 增补可重复证据字段：环境（OS/CPU/内存/Node 版本）、运行模式、缓存清理与冷/热定义，写入 `benchmark_result.json` 并在提案中给出样例。

**验证要求**：
- [ ] 在提案中给出一对样例 baseline/current JSON（路径明确）并说明 `scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json` 的预期输出。
- [ ] 提供查询集扩充后的文件行数与版本号说明（例如在 JSON 中增加 `queries_version` 字段），保证可重复性。
- [ ] 提供 schema v1.1 的字段清单与示例片段（覆盖新增字段）。

### 2026-01-23 裁决：Revise

**理由摘要**：
- 性能 AC（AC-008/009/010）缺少重复运行统计口径与不达标回退/开关策略，验收可行性不足。
- compare 未要求 `schema_version` 与 `queries_version` 一致性校验，存在错配比较风险。
- 缺少最小可运行 baseline/current JSON 与对应 `benchmark_summary.md` 样例，schema/compare 映射不可验证。
- `queries_version` 仅要求冻结但未定义命名规则与更新触发，追溯性不足。

**必须修改项**（若 Revise）：
- [ ] 补充性能 AC 的可行性口径（至少 3 次重复运行统计口径）并定义早停/子图缓存等性能改动的回退/开关策略，明确不达标时的关闭路径。
- [ ] 在 compare 规则中加入 `schema_version` 与 `queries_version` 一致性校验，不一致时直接判定失败/回归并说明输出行为。
- [ ] 在提案内提供最小可运行的 baseline/current JSON 样例与对应 `benchmark_summary.md` 样例，覆盖 `run.*`、`environment.*`、`metrics.*` 与兼容字段。
- [ ] 明确 `queries_version` 的命名规则与更新触发条件，并说明与 `tests/fixtures/benchmark/queries.jsonl` 的对齐校验方式。

**验证要求**：
- [ ] 同机至少 3 次运行并给出统计口径（中位数/均值）与性能开关关闭/开启的 compare 结果，证明 AC 可落地与可回退。
- [ ] 构造 `schema_version` 或 `queries_version` 不一致的 baseline/current，`scripts/benchmark.sh --compare` 必须输出失败/回归并返回非零或明确状态。
- [ ] 提供样例 baseline/current JSON 与 summary 的一致映射说明（字段对照/示例输出）。
- [ ] 给出 `queries_version` 命名示例与 `wc -l tests/fixtures/benchmark/queries.jsonl` 的对齐校验说明。

### 2026-01-23 裁决：Revise

**理由摘要**：
- “回退即验收”与“必须性能提升”目标冲突：当前文本允许关闭开关后通过验收，违背 AC-008/009/010 的提升目标。（证据：本提案“性能开关与回退策略”“DoD/验收锚点”“结论先行”）
- 验收边界未明确到“仅以开关开启结果判定通过”，缺少采信规则，导致验收可被回退绕过。
- 3 次运行取中位数的计算产物落点与计算方式未定义，AC-008/009/010 统计口径可被实现阶段自由解释。
- `queries_version` 仅描述命名/触发，缺少可执行校验命令，无法形成可复验链路。

**必须修改项**（若 Revise）：
- [ ] 明确验收边界：AC-008/009/010 的通过判定**仅**基于“开关全部开启”的 3 次运行中位数结果；开关关闭仅用于安全回退与诊断，不计入验收通过。若必须允许“回退即验收”，则必须移除 AC-008/009/010 并将性能提升降级为后续变更包。
- [ ] 补充 median-of-3 计算产物与方式（最小化即可）：例如将 3 次运行产物保存为 `benchmarks/results/run-1/benchmark_result.json`、`benchmarks/results/run-2/benchmark_result.json`、`benchmarks/results/run-3/benchmark_result.json`，并将中位数结果写入 `benchmarks/results/benchmark_result.median.json` 与 `benchmarks/results/benchmark_summary.median.md`；说明中位数计算规则（逐指标取中位数，方向字段不参与计算）。
- [ ] 增加 `queries_version` 校验命令建议（至少一条可执行命令）：例如 `shasum -a 256 tests/fixtures/benchmark/queries.jsonl | cut -c1-8` 并与 JSON 中 `queries_version` 的 `sha256:1a2b3c4d` 对齐；如在 Linux 用 `sha256sum` 请写出等效命令。

**验证要求**：
- [ ] 提供开启/关闭开关两组 compare 结果并标注最终采信依据；验收结果必须基于“开启”结果。
- [ ] 给出 3 次运行的原始产物与中位数产物的对应关系说明（文件路径 + 计算规则）。
- [ ] 在提案中给出 `queries_version` 对齐的示例输出或命令执行说明。

### 2026-01-23 裁决：Revise

**理由摘要**：
- median-of-3 产物落点未区分 baseline/current：当前只定义 `benchmarks/results/run-*` 与 `benchmarks/results/benchmark_result.median.json` 等路径，存在覆盖与混淆风险，AC-008/009/010 无法稳定复验。
- baseline 与 current 的中位数产物未形成对称目录结构，证据链不可追溯到同口径样本集合。
- compare 的输入未明确绑定到“中位数产物”，阈值比较口径仍可被实现阶段自由解释。

**必须修改项**（若 Revise）：
- [ ] 在“性能验收统计口径”中明确 baseline 与 current 的**两套**产物落点与命名规则，避免覆盖。建议对称结构：baseline 运行产物为 `benchmarks/baselines/run-1/benchmark_result.json`、`benchmarks/baselines/run-2/benchmark_result.json`、`benchmarks/baselines/run-3/benchmark_result.json`，baseline 中位数为 `benchmarks/baselines/benchmark_result.median.json` 与 `benchmarks/baselines/benchmark_summary.median.md`；current 保持 `benchmarks/results/run-1/..`、`run-2/..`、`run-3/..` 与 `benchmarks/results/benchmark_result.median.json`、`benchmarks/results/benchmark_summary.median.md`。
- [ ] 在同一段落明确 compare 的输入文件路径，固定为中位数产物：`scripts/benchmark.sh --compare benchmarks/baselines/benchmark_result.median.json benchmarks/results/benchmark_result.median.json`（或等效但必须显式写清）。

**验证要求**：
- [ ] 检查“性能验收统计口径”段落已同时包含 baseline 与 current 两套互不冲突的 run/median 路径定义。
- [ ] 检查 compare 示例命令已明确使用 baseline/current 的中位数产物作为输入。

### 2026-01-23 裁决：Approved

**理由摘要**：
- baseline/current 的 run 与中位数产物路径成对定义，compare 输入固定为中位数产物，统计口径可复验。（证据：本提案“固定产物路径与流程”“性能验收统计口径”）
- compare 规则补齐 `schema_version` 与 `queries_version` 一致性校验与失败行为，避免错配比较。（证据：本提案“版本对齐校验（强制）”“`queries_version` 命名与更新规则”）
- 性能开关与回退策略明确，且验收边界锁定“开关全部开启”结果，回退不计入通过。（证据：本提案“性能开关与回退策略”“DoD/验收锚点”）
- 关键指标、口径与证据路径已完整闭环，阻断项已清零。（证据：本提案“DoD/验收锚点”“可重复证据字段与运行规则”）

**验证要求**：
- [ ] 执行阶段在 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/` 保存 baseline/current 的中位数产物与摘要（`benchmark_result.median.json`/`benchmark_summary.median.md`）。
- [ ] 记录“开关全开/全关”两组 `scripts/benchmark.sh --compare` stdout（含命令与输出），并明确最终采信仅基于“全开”结果。
