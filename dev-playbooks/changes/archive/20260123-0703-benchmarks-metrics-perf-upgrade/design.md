# 设计文档：基准测试指标补齐 + 性能提升闭环（Schema v1.1）

> 版本：1.0.0
> 状态：Draft
> 更新时间：2026-01-23
> 适用范围：`benchmark_result.json`、`benchmark_summary.median.md`、`scripts/benchmark.sh --compare` 输出、Graph-RAG/embedding/cache 性能提升
> Owner：Design Owner
> last_verified：2026-01-23
> freshness_check：30d

## Acceptance Criteria
（验收标准）
- AC-001（A）：`benchmark_result.json` 的 `schema_version` 固定为 `"1.1"`，且满足「Schema v1.1 字段清单」中所有必填字段与类型约束；Trace: REQ-BM-002、REQ-BM-005。
- AC-002（A）：`metrics.*` 与顶层兼容字段双写且数值一致；compare 优先读取 `metrics.*`，缺失时回退到顶层字段；Trace: REQ-BM-003、REQ-BM-004。
- AC-003（A）：baseline/current 各 3 次 run 产物与 median 产物落点完全符合「产物路径」清单，且 JSON/Markdown 摘要齐全；Trace: REQ-BM-003、REQ-BM-005。
- AC-004（A）：median-of-3 按“逐指标取中位数”计算，方向字段不参与中位数计算；compare 仅使用 median 产物；Trace: REQ-BM-003、REQ-BM-004。
- AC-005（A）：compare 版本对齐校验：`schema_version` 或 `queries_version` 不一致时输出 `result=regression`，summary JSON 含 `status="fail"`、`reason="version_mismatch"`、baseline/current 的版本字段，退出码非零；Trace: REQ-BM-004。
- AC-006（A）：compare 输出严格两行，第二行 `summary=<JSON>` 含 `status`、`threshold_mode`、`metrics[]`（`name/direction/baseline/current/threshold/result`）；阈值优先级与公式符合「阈值规则」；`precision_at_10` 参与回归判定；Trace: REQ-BM-003、REQ-BM-004。
- AC-007（A）：`benchmark_summary.median.md` 与单次 run 摘要符合固定模板（含 `generated_at/schema_version/queries_version/result` 与 Regression Summary 表）；Trace: REQ-BM-005。
- AC-008（B）：性能开关 `CI_BENCH_EARLY_STOP`、`CI_BENCH_SUBGRAPH_CACHE`、`CI_BENCH_EMBEDDING_QUERY_CACHE` 默认开启；验收仅基于“全开”结果；关闭仅用于回退与诊断且保留证据；Trace: DoD。
- AC-009（A）：Graph-RAG 指标在全开场景满足：`warm_latency_p95_ms <= baseline_median * 0.90`，`cold_latency_p95_ms <= baseline_median * 0.95`；Trace: REQ-BM-004。
- AC-010（A）：语义搜索 `latency_p95_ms <= baseline_median * 0.95`（全开场景）；Trace: REQ-BM-004。
- AC-011（A）：`retrieval_quality.mrr_at_10/recall_at_10/precision_at_10/hit_rate_at_10 >= baseline_median * 0.95`（全开场景）；Trace: REQ-HR-005、REQ-BM-004。

## ⚡ Goals / Non-goals + Red Lines

### Goals
- 升级 `benchmark_result.json` 为 schema v1.1，并保持顶层兼容字段双写。
- 固定 baseline/current 的 3 次 run 产物与 median 产物落点，形成可追溯证据链。
- compare 输出与阈值规则标准化，包含版本对齐校验与回归判定闭环。
- 在不改变外部契约的前提下交付 Graph-RAG/embedding/cache 性能提升，并用指标验收。
- 强化可重复性：固定 `queries_version`、运行规则与环境元信息。

### Non-goals
- 不引入新的外部服务依赖或联网要求。
- 不改变 MCP 工具命名、外部语义与 Graph-RAG JSON 输出契约。
- 不调整除 benchmark 以外的功能逻辑或业务流程。
- 不在本次设计中移除顶层兼容字段（仅规划 v1.2 之后的弃用窗口）。

### Red Lines
- 任何 compare 版本不一致必须直接判定回归且退出非零。
- v1.1 必须双写顶层兼容字段，且 compare 必须能回退读取。
- 性能验收仅以“开关全开”的 median 结果判定通过。
- 不允许通过“回退结果”替代性能验收口径。

## 执行摘要
本设计将 benchmark 输出升级为 schema v1.1，并通过固定产物路径、median-of-3 与版本对齐校验构建可复验的回归判定闭环。在保持对外契约不变的前提下，引入 Graph-RAG/embedding/cache 性能优化点，并以指标阈值与证据链作为唯一验收口径。

## Problem Context（问题背景）
- 现有基准输出缺少关键指标与运行规则字段，compare 仅支持顶层字段，导致回归判定不完整。
- baseline/current 产物路径不固定，无法建立稳定证据链与可重复对比。
- 性能提升缺少统一验收口径与回退机制，存在“不可复验/不可证据化”风险。

## 价值链映射
- 目标：可复验的回归判定 + 可量化的性能提升。
- 阻碍：schema 字段缺失、compare 版本错配风险、产物落点不稳定、噪声过大。
- 最小方案：schema v1.1 + 双写兼容字段 + 固定产物路径 + median-of-3 + 版本对齐校验 + 性能开关与回退。

## 背景与现状评估
- `benchmark_result.json` 仍为 v1.0，无法覆盖 `metrics.*`、环境元信息与运行规则。
- compare 仅能读取顶层字段，无法对新增指标进行一致性判定。
- baseline 与 current 的产物路径缺少明确约束，导致证据链可追溯性不足。

## 设计原则（含变化点识别）
- **兼容优先**：v1.1 必须双写顶层兼容字段，compare 必须兼容读取。
- **可复验**：固定产物路径 + median-of-3 + 版本对齐校验，保证对比可重复。
- **可度量**：所有性能提升必须转化为可测阈值与可观测指标。
- **最小侵入**：不改变外部接口与 MCP 工具语义。

**变化点（Variation Points）**：
- `schema_version` 的演进（v1.1 → v1.2 兼容字段弃用）。
- `queries_version` 的更新（查询集变更时触发）。
- 阈值模式（`metric.threshold` / 全局阈值 / 默认规则）。
- 性能开关默认值与回退策略。

## 目标架构（Bounded Context & 依赖方向）
- **Benchmark 产物链**：`run_benchmarks.py` → `benchmark_result.json`/`benchmark_summary.md` → compare 输出。
- **性能路径**：Graph-RAG/embedding/cache 内部优化不改变外部输出契约。
- **依赖约束**：遵循现有脚本依赖方向，不新增服务或跨模块依赖。

### Testability & Seams（可测试性与接缝）
- compare 的 stdout 与退出码作为主验收接缝。
- `benchmark_result.json` 作为 schema 验收接缝。
- 性能开关作为 A/B 对照接缝（全开/全关）。
- `run.cache_clear` 命令清单作为可重复性接缝。

## 领域模型（Domain Model）

### Data Model
- `@Entity` BenchmarkRun：单次 run（run-1/run-2/run-3）
- `@Entity` BenchmarkArtifactSet：baseline/current 的产物集合
- `@Entity` BenchmarkResult：单次或 median 的结果对象
- `@ValueObject` BenchmarkSummary：Markdown 摘要
- `@ValueObject` CompareSummary：compare 输出的 summary JSON
- `@ValueObject` RunRules：cold/warm 定义、cache_clear、random_seed
- `@ValueObject` QuerySetVersion：`queries_version`
- `@ValueObject` ThresholdRule：阈值优先级与方向
- `@ValueObject` ToggleSet：性能开关组合

### Business Rules
- BR-001：baseline 与 current 的 `schema_version` 与 `queries_version` 必须一致，否则 compare 失败。
- BR-002：median 仅基于 3 次 run 逐指标取中位数，direction 不参与计算。
- BR-003：回归判定按指标方向与阈值规则执行，`precision_at_10` 必须纳入判定。
- BR-004：每次 run 与 median 均需产出 JSON + Markdown 摘要。

### Invariants（固定规则）
- [Invariant] v1.1 输出必须同时包含 `metrics.*` 与顶层兼容字段，并保持数值一致。
- [Invariant] baseline/current 各自包含 3 次 run 与 1 份 median 产物，compare 仅使用 median 产物。
- [Invariant] `schema_version` 固定为 `"1.1"`（v1.1 阶段）。

### Integrations（集成边界）
- 无外部系统新增；仅使用现有本地脚本、CLI 与缓存能力。

## 核心数据与事件契约

### 1) `benchmark_result.json` Schema v1.1 字段清单
| 字段路径 | 类型 | 单位 | 方向 | 计算公式/来源 | 必填 |
|---|---|---|---|---|---|
| schema_version | string | - | - | 固定为 `"1.1"` | 必填 |
| generated_at | string(ISO8601) | - | - | 生成时间 | 必填 |
| project_root | string | - | - | 项目根目录 | 必填 |
| git_commit | string | - | - | `git rev-parse HEAD` | 可选 |
| queries_version | string | - | - | 查询集版本号 | 必填 |
| run.mode | string | - | - | `full` / `dataset` / `legacy` | 必填 |
| run.cold_definition | string | - | - | 冷启动定义 | 必填 |
| run.warm_definition | string | - | - | 热启动定义 | 必填 |
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

### 2) `benchmark_summary.median.md` 固定模板
```
# Benchmark Summary

- generated_at: <ISO8601>
- schema_version: 1.1
- queries_version: <string>
- result: pass|fail

## Environment
- os: <name> <version> <kernel>
- cpu: <model> <cores> cores / <threads> threads / <arch>
- memory_total_mb: <int>
- node: <version>
- python: <version>
- rg: <version>
- jq: <version>
- git: <version>

## Regression Summary
| metric | direction | baseline | current | threshold | result |
|---|---|---:|---:|---:|---|
| mrr_at_10 | higher | <n> | <n> | <n> | pass|fail |
| recall_at_10 | higher | <n> | <n> | <n> | pass|fail |
| precision_at_10 | higher | <n> | <n> | <n> | pass|fail |
| hit_rate_at_10 | higher | <n> | <n> | <n> | pass|fail |
| p50_latency_ms | lower | <n> | <n> | <n> | pass|fail |
| p95_latency_ms | lower | <n> | <n> | <n> | pass|fail |
| p99_latency_ms | lower | <n> | <n> | <n> | pass|fail |
| semantic_search.latency_p95_ms | lower | <n> | <n> | <n> | pass|fail |
| graph_rag.warm_latency_p95_ms | lower | <n> | <n> | <n> | pass|fail |
| graph_rag.cold_latency_p95_ms | lower | <n> | <n> | <n> | pass|fail |
| cache_hit_p95_ms | lower | <n> | <n> | <n> | pass|fail |
| full_query_p95_ms | lower | <n> | <n> | <n> | pass|fail |
| precommit_staged_p95_ms | lower | <n> | <n> | <n> | pass|fail |
| precommit_deps_p95_ms | lower | <n> | <n> | <n> | pass|fail |
| compression_latency_ms | lower | <n> | <n> | <n> | pass|fail |
```

### 3) compare 输出契约
- **stdout 第 1 行**：`result=no_regression` 或 `result=regression`
- **stdout 第 2 行**：`summary=<JSON>`

**summary JSON（常规）**：
```json
{"status":"pass","threshold_mode":"per-metric","metrics":[{"name":"mrr_at_10","direction":"higher","baseline":0.30,"current":0.31,"threshold":0.285,"result":"pass"}]}
```

**summary JSON（版本不一致）**：
```json
{"status":"fail","reason":"version_mismatch","baseline":{"schema_version":"1.1","queries_version":"sha256:xxxx"},"current":{"schema_version":"1.0","queries_version":"sha256:yyyy"}}
```

### 4) 版本化与兼容策略
- v1.1 必须双写 `metrics.*` 与顶层兼容字段。
- compare 必须优先读取 `metrics.*`，缺失时回退到顶层字段。
- v1.2 及后续若移除顶层字段，必须更新 compare 并提供迁移说明。

## 关键机制

### 产物路径（baseline/current）
**Baseline runs**：
- `benchmarks/baselines/run-1/benchmark_result.json`
- `benchmarks/baselines/run-2/benchmark_result.json`
- `benchmarks/baselines/run-3/benchmark_result.json`

**Baseline median**：
- `benchmarks/baselines/benchmark_result.median.json`
- `benchmarks/baselines/benchmark_summary.median.md`

**Baseline summaries**：
- `benchmarks/baselines/run-1/benchmark_summary.md`
- `benchmarks/baselines/run-2/benchmark_summary.md`
- `benchmarks/baselines/run-3/benchmark_summary.md`

**Current runs**：
- `benchmarks/results/run-1/benchmark_result.json`
- `benchmarks/results/run-2/benchmark_result.json`
- `benchmarks/results/run-3/benchmark_result.json`

**Current median**：
- `benchmarks/results/benchmark_result.median.json`
- `benchmarks/results/benchmark_summary.median.md`

**Current summaries**：
- `benchmarks/results/run-1/benchmark_summary.md`
- `benchmarks/results/run-2/benchmark_summary.md`
- `benchmarks/results/run-3/benchmark_summary.md`

### median-of-3 规则
- 对同一指标的 3 次数值结果排序后取中间值。
- direction 仅用于阈值比较，不参与中位数计算。
- compare 仅使用 median 产物作为输入口径。

### compare 版本对齐校验
- baseline 与 current 的 `schema_version`、`queries_version` 必须一致。
- 任一不一致：立即判定回归，不做阈值比较。

### 阈值规则（回归判定）
- 优先级：`metric.threshold` > `BENCHMARK_REGRESSION_THRESHOLD` > 默认规则。
- 默认规则：
  - higher：`threshold = baseline * 0.95`（当前 < threshold 判定回归）
  - lower：`threshold = baseline * 1.10`（当前 > threshold 判定回归）
- `BENCHMARK_REGRESSION_THRESHOLD = t`：
  - higher：`threshold = baseline * (1 - t)`
  - lower：`threshold = baseline * (1 + t)`

### 运行规则（可重复性）
- 冷启动定义：每个 cold 样本前执行 `run.cache_clear`。
- 热启动定义：不清理缓存，连续执行 N 次查询。
- 缓存清理命令清单：
  - `rm -rf ${TMPDIR:-/tmp}/.ci-cache`
  - `rm -rf ${TMPDIR:-/tmp}/.devbooks-cache/graph-rag`
  - `scripts/cache-manager.sh cache-clear`
- 随机性控制：`run.random_seed` 固定（默认 42）。
- 查询集版本：`queries_version = "sha256:<8>"`，对齐 `tests/fixtures/benchmark/queries.jsonl` 的 SHA-256 前 8 位。

### 性能开关与回退策略
- 开关默认开启：
  - `CI_BENCH_EARLY_STOP=1`
  - `CI_BENCH_SUBGRAPH_CACHE=1`
  - `CI_BENCH_EMBEDDING_QUERY_CACHE=1`
- 验收口径：仅采信“全开”结果的 median-of-3 compare。
- 回退路径：全部开关设为 `0`，执行 `run.cache_clear` 清理后重新跑 3 次并生成 median 产物；回退结果只用于诊断，不作为验收通过依据。

## Graph-RAG / Embedding / Cache 性能提升设计点

| 设计点 | 要做什么 | 关键约束 | 验收关联 |
|---|---|---|---|
| Graph-RAG 动态早停 | 在满足相关度与候选数条件时跳过图扩展或降低深度 | 不改变 `graph-rag.sh` CLI 与输出 schema；CKB 可用时仍需满足 REQ-GR-004 候选数约束 | AC-009、AC-011 |
| Embedding 查询缓存 | 对重复查询复用 embedding 结果，降低语义搜索延迟 | 缓存需符合 REQ-CACHE-003/REQ-CACHE-004/REQ-CACHE-005；不得引入 TTL 失效（除非更新 Spec） | AC-010 |
| 子图缓存（LRU） | 复用图扩展结果，提升 warm 路径与缓存命中 | 必须符合 REQ-SLC-001~REQ-SLC-009，优先 LRU 淘汰；跨进程可读 | AC-009 |

## 可观测性与验收
- 基准输出必须包含 `metrics.*` 与兼容字段，可用于自动回归判定。
- compare 输出 stdout 与退出码作为 CI 判定依据。
- 证据文件保存到 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/`。

## 安全、合规与多租户隔离
- 仅处理本地代码与本地缓存，不新增外部数据出入口。
- 不引入多租户隔离需求。

## 里程碑（设计层面）
- M1：Schema v1.1 与 compare 契约定稿（字段清单、阈值规则、版本对齐）。
- M2：baseline/current 产物落点与 median-of-3 口径定稿。
- M3：性能优化点与验收阈值绑定，完成证据链定义。

## Deprecation Plan（弃用计划）
- v1.1 保留顶层兼容字段；v1.2 才允许移除兼容字段。
- 移除前必须更新 compare 与文档，并声明迁移窗口与示例。

## Design Rationale（设计决策理由）
- 采用 median-of-3 降低抖动，避免单次异常误判。
- 双写兼容字段确保 compare 与历史工具链可平滑过渡。
- 版本对齐校验避免跨查询集/跨 schema 的错误比较。

## Trade-offs（权衡取舍）
- 3 次 run 增加耗时，但换取可复验性与抗噪声能力。
- 双写字段增加产物体积，但保障兼容期平稳过渡。
- 早停与缓存提升性能，但需以质量阈值严格约束。

## 风险与降级策略（Failure Modes + Degrade Paths）
- 风险：早停导致质量下降。
  - 降级：关闭 `CI_BENCH_EARLY_STOP` 并重跑；仍以全开结果验收。
- 风险：缓存导致结果不一致。
  - 降级：执行 `run.cache_clear` 并关闭缓存开关重跑；记录对照证据。
- 风险：版本错配导致比较失真。
  - 降级：compare 直接失败并输出 version_mismatch，阻断误判。

## 影响的能力 / 模块 / 对外契约
- 能力：benchmark、Graph-RAG、embedding、cache-manager/subgraph-lru-cache。
- 模块：`benchmarks/run_benchmarks.py`、`scripts/benchmark.sh`、`scripts/graph-rag-query.sh`、`scripts/embedding.sh`、`scripts/cache-manager.sh`。
- 对外契约：`benchmark_result.json` schema v1.1、`benchmark_summary.median.md` 模板、compare stdout（result + summary JSON）。

## Spec 影响与追溯（Truth Root）

### 受影响的现有 Spec（必须遵守）
- `dev-playbooks/specs/benchmark/spec.md`
  - REQ-BM-002（评测指标）
  - REQ-BM-003（基线对比）
  - REQ-BM-004（回归检测阈值与退出码）
  - REQ-BM-005（Markdown/JSON 报告）
  - REQ-BM-006（查询样本管理）
- `dev-playbooks/specs/hybrid-retrieval/spec.md`
  - REQ-HR-005（检索质量指标）
- `dev-playbooks/specs/graph-rag-cli/spec.md`
  - REQ-GR-001（fusion-depth 行为）
  - REQ-GR-003（融合查询输出格式）
  - REQ-GR-004（融合候选数阈值）
- `dev-playbooks/specs/cache-manager/spec.md`
  - REQ-CACHE-002（禁止 TTL 失效）
  - REQ-CACHE-003（缓存 Key 组成）
  - REQ-CACHE-004（并发/原子写入）
  - REQ-CACHE-005（LRU 淘汰）
- `dev-playbooks/specs/subgraph-lru-cache/spec.md`
  - REQ-SLC-001~REQ-SLC-009（SQLite、LRU、跨进程与统计）
- `dev-playbooks/specs/context-compressor/spec.md`
  - REQ-CC-001（压缩率目标）
  - REQ-CC-007（增量压缩）

### Gap 声明
- Gap-001：提案中提及“子图缓存 TTL”，但 REQ-CACHE-002 明确禁止 TTL 失效；本设计默认遵循“无 TTL + LRU”，如需 TTL 必须先更新 Spec 并重新评审。

## Documentation Impact（文档影响）

### 需要更新的文档

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| README.md | 更新 `benchmark_result.json` schema v1.1 与基准产物路径说明 | P0 |
| README.zh-CN.md | 同步中文说明（schema v1.1 与产物路径） | P0 |
| docs/TECHNICAL.md | 更新 `benchmark.sh --compare` 输入、输出格式与产物落点 | P0 |
| docs/TECHNICAL_zh.md | 同步中文技术文档更新 | P0 |

### 无需更新的文档
- [ ] 本次变更为内部重构，不影响用户可见功能
- [ ] 本次变更仅修复 bug，不引入新功能或改变使用方式

### 文档更新检查清单
- [ ] 新增脚本/命令已在使用文档中说明
- [ ] 新增配置项已在配置文档中说明
- [ ] 新增工作流/流程已在指南中说明
- [x] API/接口变更已在相关文档中更新

## Architecture Impact（架构影响）

### 无架构变更
- [x] 本次变更不影响模块边界、依赖方向或组件结构
- 原因说明：仅更新 benchmark 产物与 compare 契约，并在现有脚本内做性能优化，不引入新服务或新模块边界

## ⚡ DoD 完成定义（Definition of Done）
- AC-001 ~ AC-011 全部通过，并留存对应证据。
- compare 输出 stdout 与退出码记录到 `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/`。
- baseline/current 的 median 产物与摘要已保存到证据目录。
- 文档更新项已覆盖 README/TECHNICAL（中英文）。

## Open Questions
1. 是否需要更新 Spec 以允许子图缓存 TTL？若需要，TTL 的默认值与退出条件是什么？
2. Embedding 查询缓存如何映射到 REQ-CACHE-003 的 `file_path/mtime/blob_hash` 约束（以索引文件还是查询集为 Key）？
3. Graph-RAG 子图缓存的 Key 如何在不违背 REQ-SLC-004 的前提下纳入 `query/top_k/fusion_weights` 影响因子？
