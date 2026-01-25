---
last_referenced_by: 20260123-0703-benchmarks-metrics-perf-upgrade
last_verified: 2026-01-24
health: active
---

# 规格：评测基准（benchmark）

| 属性 | 值 |
|------|-----|
| Spec-ID | SPEC-BENCHMARK-001 |
| Change-ID | 20260123-0703-benchmarks-metrics-perf-upgrade |
| 版本 | 1.1.0 |
| 状态 | Active |
| 作者 | Spec Owner |
| 创建日期 | 2026-01-19 |

---

## 1. 目的（Goals）

- 提供**可复验**的性能与检索质量基准：固定查询集版本、固定产物路径、固定 schema。
- 提供**可归档**的回归判定：compare 输出与退出码稳定、证据可落盘。
- 允许在迁移窗口内保持兼容：v1.1 双写 `metrics.*` 与顶层兼容字段，compare 优先 `metrics.*`，缺失时回退。

---

## 2. Requirements（需求规格）

### REQ-BM-001：评测数据集支持

系统 SHALL 支持两种评测数据集：

| 数据集类型 | 说明 | 用途 |
|-----------|------|------|
| `self` | 本项目代码库 | 回归对比 |
| `public` | 公开数据集（可选接入） | 标准化对比 |

命令（dataset runner）：
```bash
scripts/benchmark.sh --dataset <self|public> --queries <file.jsonl> --output <report.json>
```

---

### REQ-BM-007：`benchmark_result.json` Schema v1.1（关键指标补齐 + 双写兼容）

系统 SHALL 产出 `benchmark_result.json`，且：

- `schema_version` 固定为 `"1.1"`
- 必填字段、单位与方向符合下方「Schema v1.1 字段清单」
- v1.1 期间同时写入 `metrics.*` 与顶层兼容字段，且数值一致

Trace: AC-001, AC-002, AC-007

---

### REQ-BM-010：`queries_version` 规则（可复验）

系统 SHALL 在 `benchmark_result.json` 中写入 `queries_version`，命名规则：

- `queries_version = sha256:<8>`（取查询集文件内容 sha256 的前 8 位）
- 查询集内容变化时，`queries_version` 必须变化
- compare SHALL 校验 baseline/current 的 `queries_version` 一致性

Trace: AC-001, AC-005

---

### REQ-BM-009：baseline/current 产物路径与 median-of-3

系统 SHALL 生成 baseline 与 current 各 3 次 run 产物与 1 份 median 产物，路径如下：

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

median-of-3 规则 SHALL 为逐指标取中位数，direction 仅用于阈值比较，不参与中位数计算。compare 仅使用 median 产物。

Trace: AC-003, AC-004

---

### REQ-BM-008：compare 输出契约与版本对齐

系统 SHALL 在 baseline/current 均为 median 产物时执行 compare。compare stdout 必须严格两行：

- 第 1 行：`result=no_regression` 或 `result=regression`
- 第 2 行：`summary=<JSON>`，符合下方「compare summary JSON Schema」

当 `schema_version` 或 `queries_version` 不一致时，系统 SHALL：

- 输出 `result=regression`
- `summary` 仅包含 `status="fail"`、`reason="version_mismatch"` 与 baseline/current 版本字段
- 退出码为 2，且不得进行阈值比较

退出码约定：

- `0`：无回归（`result=no_regression`）
- `1`：回归（阈值比较失败）
- `2`：版本不一致（`version_mismatch`）

Trace: AC-005, AC-006

---

### REQ-BM-004：回归检测（阈值规则与优先级）

系统 SHALL 使用以下阈值优先级进行回归判定：

`metric.threshold` > `BENCHMARK_REGRESSION_THRESHOLD` > 默认规则

默认规则：

- `higher`：`threshold = baseline * 0.95`（当 `current < threshold` 判定回归）
- `lower`：`threshold = baseline * 1.10`（当 `current > threshold` 判定回归）

全局阈值（`BENCHMARK_REGRESSION_THRESHOLD = t`）：

- `higher`：`threshold = baseline * (1 - t)`
- `lower`：`threshold = baseline * (1 + t)`

回归判定覆盖：

- `precision_at_10` SHALL 参与回归判定

Trace: AC-006

---

### REQ-BM-005：报告生成（JSON + Markdown）

系统 SHALL 生成 JSON 与 Markdown 摘要报告。

`benchmark_summary.median.md` 模板：

```md
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

Trace: AC-007

---

## 3. Schema（契约）

### 3.1 `benchmark_result.json` Schema v1.1 字段清单

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

---

### 3.2 compare summary JSON Schema

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

---

## 4. 兼容策略（Compatibility）

- **双写兼容**：v1.1 SHALL 同时写入 `metrics.*` 与顶层兼容字段，数值一致。
- **兼容读取**：compare SHALL 优先读取 `metrics.*`，缺失时回退到顶层兼容字段。
- **未知字段**：compare SHALL 忽略未声明字段，不得导致失败。
- **版本对齐**：`schema_version` 与 `queries_version` 不一致时直接失败（exit=2），不得进行阈值比较。

