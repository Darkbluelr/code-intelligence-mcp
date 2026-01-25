# 规格增量：基准测试指标与回归对比契约（benchmark）

> Change ID: 20260123-0703-benchmarks-metrics-perf-upgrade
> Capability: benchmark
> Base Spec: dev-playbooks/specs/benchmark/spec.md
> Version: 1.1.0-delta
> Status: Draft
> Owner: Spec Owner

---

## 冲突检测声明

- 与 `dev-playbooks/specs/benchmark/spec.md` 的 REQ-BM-002/003/004/005 存在输出格式与指标口径差异：旧版 compare JSON 结构、基线路径与回归阈值不再适用。
- 处理方式：本 Spec Delta 以 v1.1 契约为准，归档阶段合并更新基准 Spec；旧字段视为兼容读取，不再作为回归判定口径。

---

## ADDED Requirements

### Requirement: REQ-BM-007 `benchmark_result.json` Schema v1.1
系统 SHALL 产出 `benchmark_result.json`（schema v1.1），字段、必填性、单位、方向与公式必须符合「Schema」章节定义。系统 SHALL 在 v1.1 期间同时写入 `metrics.*` 与顶层兼容字段，且数值一致。

Trace: AC-001, AC-002, AC-007

#### Scenario: SC-BM-101 Schema v1.1 双写一致性
- **GIVEN** 已完成一次基准运行并生成 `benchmark_result.json`
- **WHEN** 系统写入 schema v1.1 产物
- **THEN** `metrics.*` 与顶层兼容字段同时存在且数值一致
- **THEN** 产物包含 `environment.*` 与 `run.*` 的必填字段

Trace: REQ-BM-007, REQ-BM-002

---

### Requirement: REQ-BM-008 compare 输出契约与版本对齐
系统 SHALL 在 baseline/current 均为中位数产物时执行 compare。compare stdout 必须严格两行：
- 第 1 行：`result=no_regression` 或 `result=regression`
- 第 2 行：`summary=<JSON>`，符合「Schema」章节的 compare summary JSON 结构

当 `schema_version` 或 `queries_version` 不一致时，系统 SHALL：
- 输出 `result=regression`
- `summary` 仅包含 `status="fail"`、`reason="version_mismatch"` 与 baseline/current 版本字段
- 退出码为 2，且不得进行阈值比较

Trace: AC-005, AC-006

#### Scenario: SC-BM-103 无回归对比
- **GIVEN** baseline 与 current 的版本一致，且所有指标满足阈值
- **WHEN** 触发 compare
- **THEN** stdout 第 1 行为 `result=no_regression`
- **THEN** stdout 第 2 行以 `summary=` 开头，且 `summary.status="pass"` 且 `metrics[].result` 均为 `pass`
- **THEN** 退出码为 0

Trace: REQ-BM-008, REQ-BM-004

---

### Requirement: REQ-BM-009 baseline/current 产物路径与 median-of-3
系统 SHALL 生成 baseline 与 current 各 3 次 run 产物与 1 份 median 产物，路径必须符合「API」章节的产物清单。median-of-3 规则 SHALL 为逐指标取中位数，direction 仅用于阈值比较，不参与中位数计算。compare 仅使用 median 产物。

Trace: AC-003, AC-004

#### Scenario: SC-BM-102 baseline/current 产物对称与中位数口径
- **GIVEN** baseline 与 current 各有 3 次 run 产物
- **WHEN** 系统生成 median 产物
- **THEN** median 为逐指标取中位数且不受方向影响
- **THEN** compare 仅使用 median 产物

Trace: REQ-BM-009, REQ-BM-003, REQ-BM-005

---

### Requirement: REQ-BM-010 `queries_version` 规则
系统 SHALL 在 `benchmark_result.json` 中写入 `queries_version`，并遵循「兼容策略」章节的命名与更新规则。compare SHALL 校验 baseline/current 的 `queries_version` 一致性。

Trace: AC-001, AC-005

#### Scenario: SC-BM-104 版本不一致
- **GIVEN** baseline 与 current 的 `schema_version` 或 `queries_version` 不一致
- **WHEN** 触发 compare
- **THEN** stdout 第 1 行为 `result=regression`
- **THEN** stdout 第 2 行以 `summary=` 开头，且 `summary.status="fail"` 且 `summary.reason="version_mismatch"`
- **THEN** 不输出 `metrics[]`，退出码为 2

Trace: REQ-BM-008, REQ-BM-010

---

## MODIFIED Requirements

### Requirement: REQ-BM-002 评测指标
评测指标集合 SHALL 以 schema v1.1 的 `metrics.*` 定义为准，覆盖语义搜索、Graph-RAG、检索质量、上下文压缩与缓存类指标。除 `metrics.*` 外，顶层兼容字段仅用于兼容读取与回归判定，不扩展额外语义。

Trace: AC-001, AC-002

#### Scenario: SC-BM-101 Schema v1.1 双写一致性（复用）
- 断言同 `REQ-BM-007` 下 SC-BM-101。

Trace: REQ-BM-007, REQ-BM-002

---

### Requirement: REQ-BM-003 基线对比
基线对比 SHALL 以 baseline/current 的 median 产物作为唯一比较口径，且 compare 输出必须符合「compare 输出契约」。旧版 `evidence/baseline-metrics.json` 对比格式不再作为规范输出。

Trace: AC-003, AC-004, AC-006

#### Scenario: SC-BM-102 baseline/current 产物对称与中位数口径（复用）
- 断言同 `REQ-BM-009` 下 SC-BM-102。

Trace: REQ-BM-009, REQ-BM-003, REQ-BM-005

---

### Requirement: REQ-BM-004 回归检测
回归检测 SHALL 使用「阈值规则」与「阈值优先级」，并覆盖 `mrr_at_10`、`recall_at_10`、`precision_at_10`、`hit_rate_at_10` 与各性能指标。任一指标触发回归即判定整体回归，退出码与 result 需一致。

Trace: AC-006

#### Scenario: SC-BM-105 阈值优先级示例
- **GIVEN** baseline=100、current=112、direction=lower，且 `metric.threshold=110`
- **WHEN** 触发 compare
- **THEN** 以 `metric.threshold` 为优先阈值，判定为回归，stdout 第 1 行为 `result=regression`
- **THEN** 退出码为 1

| baseline | current | direction | metric.threshold | 全局阈值 | 默认阈值 | 结果 |
|---:|---:|---|---:|---:|---:|---|
| 100 | 112 | lower | 110 | 110 | 110 | regression |

Trace: REQ-BM-004, REQ-BM-008

---

### Requirement: REQ-BM-005 报告生成
系统 SHALL 生成 JSON 与 Markdown 摘要报告，摘要格式必须符合「Schema」章节模板；baseline/current 的 run 与 median 产物均需要对应摘要。

Trace: AC-007

#### Scenario: SC-BM-107 摘要模板一致性
- **GIVEN** baseline 与 current 的 run 与 median 产物已生成
- **WHEN** 系统输出 Markdown 摘要
- **THEN** 摘要包含 `generated_at/schema_version/queries_version/result` 与 Regression Summary 表

Trace: REQ-BM-005

---

### Requirement: REQ-BM-006 查询样本管理
系统 SHALL 以固定查询集作为评测输入，并在输出中记录 `queries_version` 与 `query_count`；当查询集内容变化时必须更新 `queries_version`。

Trace: AC-001

#### Scenario: SC-BM-106 查询集版本更新
- **GIVEN** 查询集内容发生变更
- **WHEN** 生成新的 `benchmark_result.json`
- **THEN** `queries_version` 变化且与查询集内容一致

Trace: REQ-BM-006, REQ-BM-010

---

## API

### compare 命令
- **命令形式**：`scripts/benchmark.sh --compare <baseline_median_json> <current_median_json>`
- **输入口径**：仅接受 median 产物

### stdout 契约
- **第 1 行**：`result=no_regression` 或 `result=regression`
- **第 2 行**：`summary=<JSON>`

### 退出码
- `0`：无回归（`result=no_regression`）
- `1`：回归（阈值比较失败）
- `2`：版本不一致（`version_mismatch`）

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

---

## Schema

### 1) `benchmark_result.json` Schema v1.1

| 字段路径 | 类型 | 单位 | 方向 | 公式/来源 | 必填 |
|---|---|---|---|---|---|
| schema_version | string | - | - | 固定为 "1.1" | 是 |
| generated_at | string(ISO8601) | - | - | 生成时间 | 是 |
| project_root | string | - | - | 项目根目录 | 是 |
| git_commit | string | - | - | `git rev-parse HEAD` | 否 |
| queries_version | string | - | - | 查询集版本号 | 是 |
| run.mode | string | - | - | `full` / `dataset` / `legacy` | 是 |
| run.cold_definition | string | - | - | 冷启动定义 | 是 |
| run.warm_definition | string | - | - | 热启动定义 | 是 |
| run.cache_clear | array(string) | - | - | 缓存清理命令清单 | 是 |
| run.random_seed | integer | - | - | 随机种子 | 是 |
| environment.os.name | string | - | - | 操作系统名称 | 是 |
| environment.os.version | string | - | - | 操作系统版本 | 是 |
| environment.os.kernel | string | - | - | 内核版本 | 是 |
| environment.cpu.model | string | - | - | CPU 型号 | 是 |
| environment.cpu.cores | integer | 核 | - | 物理核心数 | 是 |
| environment.cpu.threads | integer | 线程 | - | 逻辑线程数 | 是 |
| environment.cpu.arch | string | - | - | 架构（x86_64/arm64） | 是 |
| environment.memory.total_mb | integer | MB | - | 总内存 | 是 |
| environment.runtime.node | string | - | - | `node -v` | 是 |
| environment.runtime.python | string | - | - | `python --version` | 是 |
| environment.dependencies.rg | string | - | - | `rg --version` | 是 |
| environment.dependencies.jq | string | - | - | `jq --version` | 是 |
| environment.dependencies.git | string | - | - | `git --version` | 是 |
| metrics.semantic_search.iterations | integer | 次 | - | 运行次数 | 是 |
| metrics.semantic_search.latency_p50_ms | number | ms | lower | N 次延迟 P50 | 是 |
| metrics.semantic_search.latency_p95_ms | number | ms | lower | N 次延迟 P95 | 是 |
| metrics.semantic_search.latency_p99_ms | number | ms | lower | N 次延迟 P99 | 是 |
| metrics.graph_rag.iterations | integer | 次 | - | 运行次数 | 是 |
| metrics.graph_rag.cold_latency_p50_ms | number | ms | lower | 冷启动延迟 P50 | 是 |
| metrics.graph_rag.cold_latency_p95_ms | number | ms | lower | 冷启动延迟 P95 | 是 |
| metrics.graph_rag.cold_latency_p99_ms | number | ms | lower | 冷启动延迟 P99 | 是 |
| metrics.graph_rag.warm_latency_p50_ms | number | ms | lower | 热启动延迟 P50 | 是 |
| metrics.graph_rag.warm_latency_p95_ms | number | ms | lower | 热启动延迟 P95 | 是 |
| metrics.graph_rag.warm_latency_p99_ms | number | ms | lower | 热启动延迟 P99 | 是 |
| metrics.graph_rag.speedup_pct | number | % | higher | `(cold_p95 - warm_p95) / cold_p95 * 100` | 是 |
| metrics.retrieval_quality.iterations | integer | 次 | - | 运行次数 | 是 |
| metrics.retrieval_quality.dataset | string | - | - | `self`/`public` | 是 |
| metrics.retrieval_quality.query_count | integer | 条 | - | 有效查询数 | 是 |
| metrics.retrieval_quality.expected_count | integer | 条 | - | `sum(expected[])` | 是 |
| metrics.retrieval_quality.mrr_at_10 | number | - | higher | `sum(1/rank) / query_count` | 是 |
| metrics.retrieval_quality.recall_at_10 | number | - | higher | `hits / query_count` | 是 |
| metrics.retrieval_quality.precision_at_10 | number | - | higher | `relevant/retrieved` 均值 | 是 |
| metrics.retrieval_quality.hit_rate_at_10 | number | - | higher | `queries_with_hit / query_count` | 是 |
| metrics.retrieval_quality.latency_p50_ms | number | ms | lower | 查询延迟 P50 | 是 |
| metrics.retrieval_quality.latency_p95_ms | number | ms | lower | 查询延迟 P95 | 是 |
| metrics.retrieval_quality.latency_p99_ms | number | ms | lower | 查询延迟 P99 | 是 |
| metrics.context_compression.iterations | integer | 次 | - | 运行次数 | 是 |
| metrics.context_compression.compression_latency_ms | number | ms | lower | 压缩命令耗时 | 是 |
| metrics.context_compression.tokens_before | integer | token | - | 原始 token 数 | 是 |
| metrics.context_compression.tokens_after | integer | token | - | 压缩后 token 数 | 是 |
| metrics.context_compression.compression_ratio | number | - | lower | `tokens_after / tokens_before` | 是 |
| metrics.context_compression.information_retention | number | - | higher | `retained_key_lines / original_key_lines` | 是 |
| metrics.context_compression.compression_level | string | - | - | `low/medium/high` | 是 |
| metrics.cache.iterations | integer | 次 | - | 运行次数 | 是 |
| metrics.cache.cache_hit_p95_ms | number | ms | lower | 缓存命中 P95 | 是 |
| metrics.cache.full_query_p95_ms | number | ms | lower | 全量查询 P95 | 是 |
| metrics.cache.precommit_staged_p95_ms | number | ms | lower | 预提交 staged P95 | 是 |
| metrics.cache.precommit_deps_p95_ms | number | ms | lower | 预提交 deps P95 | 是 |
| mrr_at_10 | number | - | higher | `metrics.retrieval_quality.mrr_at_10` | 是 |
| recall_at_10 | number | - | higher | `metrics.retrieval_quality.recall_at_10` | 是 |
| precision_at_10 | number | - | higher | `metrics.retrieval_quality.precision_at_10` | 是 |
| hit_rate_at_10 | number | - | higher | `metrics.retrieval_quality.hit_rate_at_10` | 是 |
| p50_latency_ms | number | ms | lower | `metrics.retrieval_quality.latency_p50_ms` | 是 |
| p95_latency_ms | number | ms | lower | `metrics.retrieval_quality.latency_p95_ms` | 是 |
| p99_latency_ms | number | ms | lower | `metrics.retrieval_quality.latency_p99_ms` | 是 |
| cache_hit_p95_ms | number | ms | lower | `metrics.cache.cache_hit_p95_ms` | 是 |
| full_query_p95_ms | number | ms | lower | `metrics.cache.full_query_p95_ms` | 是 |
| precommit_staged_p95_ms | number | ms | lower | `metrics.cache.precommit_staged_p95_ms` | 是 |
| precommit_deps_p95_ms | number | ms | lower | `metrics.cache.precommit_deps_p95_ms` | 是 |
| compression_latency_ms | number | ms | lower | `metrics.context_compression.compression_latency_ms` | 是 |

### 2) compare summary JSON Schema

**常规（无版本不一致）**：

| 字段 | 类型 | 说明 | 必填 |
|---|---|---|---|
| status | string | `pass`/`fail` | 是 |
| threshold_mode | string | `per-metric`/`global` | 是 |
| metrics | array | 回归判定明细 | 是 |

`metrics[]` 对象：

| 字段 | 类型 | 说明 | 必填 |
|---|---|---|---|
| name | string | 指标名 | 是 |
| direction | string | `higher`/`lower` | 是 |
| baseline | number | baseline 数值 | 是 |
| current | number | current 数值 | 是 |
| threshold | number | 判定阈值 | 是 |
| result | string | `pass`/`fail` | 是 |

**版本不一致**：

| 字段 | 类型 | 说明 | 必填 |
|---|---|---|---|
| status | string | 固定为 `fail` | 是 |
| reason | string | 固定为 `version_mismatch` | 是 |
| baseline.schema_version | string | baseline 版本 | 是 |
| baseline.queries_version | string | baseline 查询集版本 | 是 |
| current.schema_version | string | current 版本 | 是 |
| current.queries_version | string | current 查询集版本 | 是 |

### 3) `benchmark_summary.median.md` 模板
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

---

## 兼容策略

- **双写兼容**：v1.1 SHALL 同时写入 `metrics.*` 与顶层兼容字段，数值一致。
- **兼容读取**：compare SHALL 优先读取 `metrics.*`，缺失时回退到顶层兼容字段。
- **未知字段**：compare SHALL 忽略未声明字段，不得导致失败。
- **旧指标**：未纳入 v1.1 Schema 的旧指标可作为扩展字段保留，但不参与回归判定。
- **版本对齐**：`schema_version` 与 `queries_version` 不一致时直接失败，不进行阈值比较。

---

## 迁移

- **v1.0 → v1.1**：进入双写期，旧消费者可读取顶层字段，新消费者以 `metrics.*` 为准。
- **v1.1 → v1.2（计划）**：仅在完成迁移窗口后允许移除顶层兼容字段，并同步更新 compare 契约。
- **基线与当前产物**：迁移期内 baseline/current 必须为 v1.1，避免版本错配对比。

---

## 阈值规则

- **优先级**：`metric.threshold` > `BENCHMARK_REGRESSION_THRESHOLD` > 默认规则。
- **默认规则**：
  - `higher`：`threshold = baseline * 0.95`（当前 < threshold 判定回归）
  - `lower`：`threshold = baseline * 1.10`（当前 > threshold 判定回归）
- **全局阈值**（`BENCHMARK_REGRESSION_THRESHOLD = t`）：
  - `higher`：`threshold = baseline * (1 - t)`
  - `lower`：`threshold = baseline * (1 + t)`
- **回归判定覆盖**：`precision_at_10` SHALL 参与回归判定。

---

## Contract Tests 建议

| Test ID | 类型 | 覆盖 | 断言点 |
|---|---|---|---|
| CT-BM-001 | schema | REQ-BM-007 | schema v1.1 必填字段齐全且双写一致 |
| CT-BM-002 | behavior | REQ-BM-009 | baseline/current run 与 median 产物路径完整 |
| CT-BM-003 | behavior | REQ-BM-008 | compare stdout 两行且 summary JSON 符合结构 |
| CT-BM-004 | behavior | REQ-BM-008, REQ-BM-010 | version_mismatch 触发失败且退出码为 2 |
| CT-BM-005 | behavior | REQ-BM-004 | 阈值优先级生效（metric.threshold 优先） |
| CT-BM-006 | behavior | REQ-BM-005 | Markdown 摘要模板字段齐全 |
| CT-BM-007 | behavior | REQ-BM-006 | queries_version 与查询集一致且可变更 |

---

## 追溯摘要

| AC | 覆盖 Requirement |
|---|---|
| AC-001 | REQ-BM-007, REQ-BM-010, REQ-BM-002, REQ-BM-006 |
| AC-002 | REQ-BM-007, REQ-BM-002 |
| AC-003 | REQ-BM-009 |
| AC-004 | REQ-BM-009, REQ-BM-003 |
| AC-005 | REQ-BM-008, REQ-BM-010 |
| AC-006 | REQ-BM-008, REQ-BM-004 |
| AC-007 | REQ-BM-007, REQ-BM-005 |
