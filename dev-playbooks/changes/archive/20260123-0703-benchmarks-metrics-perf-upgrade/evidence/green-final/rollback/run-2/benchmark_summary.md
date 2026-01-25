# Benchmark Summary

- generated_at: 2026-01-24T06:32:19.391477Z
- schema_version: 1.1
- queries_version: sha256:2a944e88
- result: pass

## Environment
- os: Darwin Darwin Kernel Version 25.2.0: Tue Nov 18 21:08:48 PST 2025; root:xnu-12377.61.12~1/RELEASE_ARM64_T8132 25.2.0
- cpu: Apple M4 10 cores / 10 threads / arm64
- memory_total_mb: 16384
- node: v22.15.0
- python: Python 3.12.9
- rg: ripgrep 15.1.0
- jq: jq-1.7.1-apple
- git: git version 2.51.2

## Regression Summary
| metric | direction | baseline | current | threshold | result |
|---|---|---:|---:|---:|---|
| mrr_at_10 | higher | 0.4861 | 0.4861 | 0.4618 | pass |
| recall_at_10 | higher | 1.0000 | 1.0000 | 0.9500 | pass |
| precision_at_10 | higher | 0.3377 | 0.3377 | 0.3208 | pass |
| hit_rate_at_10 | higher | 1.0000 | 1.0000 | 0.9500 | pass |
| p50_latency_ms | lower | 5.8043 | 5.8043 | 6.3848 | pass |
| p95_latency_ms | lower | 6.0311 | 6.0311 | 6.6342 | pass |
| p99_latency_ms | lower | 6.1420 | 6.1420 | 6.7562 | pass |
| semantic_search.latency_p95_ms | lower | 244.0000 | 244.0000 | 268.4000 | pass |
| graph_rag.warm_latency_p95_ms | lower | 70.8012 | 70.8012 | 77.8814 | pass |
| graph_rag.cold_latency_p95_ms | lower | 1153.1620 | 1153.1620 | 1268.4782 | pass |
| cache_hit_p95_ms | lower | 59.0000 | 59.0000 | 64.9000 | pass |
| full_query_p95_ms | lower | 97.0000 | 97.0000 | 106.7000 | pass |
| precommit_staged_p95_ms | lower | 27.0000 | 27.0000 | 29.7000 | pass |
| precommit_deps_p95_ms | lower | 27.0000 | 27.0000 | 29.7000 | pass |
| compression_latency_ms | lower | 9.3194 | 9.3194 | 10.2514 | pass |
