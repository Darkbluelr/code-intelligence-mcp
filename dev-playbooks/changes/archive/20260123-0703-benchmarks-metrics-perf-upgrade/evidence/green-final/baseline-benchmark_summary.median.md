# Benchmark Summary

- generated_at: 2026-01-24T06:27:38.888012Z
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
| mrr_at_10 | higher | 0.4264 | 0.4264 | 0.4051 | pass |
| recall_at_10 | higher | 1.0000 | 1.0000 | 0.9500 | pass |
| precision_at_10 | higher | 0.3377 | 0.3377 | 0.3208 | pass |
| hit_rate_at_10 | higher | 1.0000 | 1.0000 | 0.9500 | pass |
| p50_latency_ms | lower | 5.7220 | 5.7220 | 6.2942 | pass |
| p95_latency_ms | lower | 6.0980 | 6.0980 | 6.7078 | pass |
| p99_latency_ms | lower | 6.5954 | 6.5954 | 7.2549 | pass |
| semantic_search.latency_p95_ms | lower | 222.0000 | 222.0000 | 244.2000 | pass |
| graph_rag.warm_latency_p95_ms | lower | 69.3651 | 69.3651 | 76.3016 | pass |
| graph_rag.cold_latency_p95_ms | lower | 862.6394 | 862.6394 | 948.9033 | pass |
| cache_hit_p95_ms | lower | 75.0000 | 75.0000 | 82.5000 | pass |
| full_query_p95_ms | lower | 89.0000 | 89.0000 | 97.9000 | pass |
| precommit_staged_p95_ms | lower | 35.0000 | 35.0000 | 38.5000 | pass |
| precommit_deps_p95_ms | lower | 27.0000 | 27.0000 | 29.7000 | pass |
| compression_latency_ms | lower | 8.9518 | 8.9518 | 9.8469 | pass |
