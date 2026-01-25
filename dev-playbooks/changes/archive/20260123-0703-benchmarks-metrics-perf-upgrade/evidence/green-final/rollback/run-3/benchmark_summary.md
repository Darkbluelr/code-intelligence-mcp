# Benchmark Summary

- generated_at: 2026-01-24T06:32:27.200385Z
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
| mrr_at_10 | higher | 0.3472 | 0.3472 | 0.3299 | pass |
| recall_at_10 | higher | 1.0000 | 1.0000 | 0.9500 | pass |
| precision_at_10 | higher | 0.3377 | 0.3377 | 0.3208 | pass |
| hit_rate_at_10 | higher | 1.0000 | 1.0000 | 0.9500 | pass |
| p50_latency_ms | lower | 6.4157 | 6.4157 | 7.0573 | pass |
| p95_latency_ms | lower | 9.3970 | 9.3970 | 10.3367 | pass |
| p99_latency_ms | lower | 10.4255 | 10.4255 | 11.4681 | pass |
| semantic_search.latency_p95_ms | lower | 477.0000 | 477.0000 | 524.7000 | pass |
| graph_rag.warm_latency_p95_ms | lower | 100.1924 | 100.1924 | 110.2116 | pass |
| graph_rag.cold_latency_p95_ms | lower | 872.4430 | 872.4430 | 959.6873 | pass |
| cache_hit_p95_ms | lower | 74.0000 | 74.0000 | 81.4000 | pass |
| full_query_p95_ms | lower | 108.0000 | 108.0000 | 118.8000 | pass |
| precommit_staged_p95_ms | lower | 37.0000 | 37.0000 | 40.7000 | pass |
| precommit_deps_p95_ms | lower | 38.0000 | 38.0000 | 41.8000 | pass |
| compression_latency_ms | lower | 10.1351 | 10.1351 | 11.1486 | pass |
