# 代码评审（Code Reviewer）

Change ID：`20260123-0703-benchmarks-metrics-perf-upgrade`

结论：通过（Approved）

## 关键变更审阅

- `scripts/embedding.sh`：统一为毫秒级时间戳实现，修复语义搜索 `latency_ms` 可能为 0 的问题，保证关键指标可用。
- `scripts/cache-manager.sh`：修复“写入中检测”误判导致缓存几乎不可用的问题，使 Graph-RAG/Embedding 查询缓存与基准缓存项在 bash 3.2 下可稳定命中。
- `scripts/graph-rag-retrieval.sh`：改为调用 embedding 的 JSON 输出并用 `jq` 解析候选，避免 text 输出携带的文件预览导致的额外 I/O 与解析开销。
- `benchmarks/benchmark_lib.py`：缓存类指标固定使用独立迭代次数（默认 20），避免受 suite iterations 影响导致口径不一致。

## 风险与建议

- Graph-RAG cold 路径受“cache_clear”定义影响较大：本变更以 warm/cold 分离口径输出并将 baseline 更新为可复验基线，后续若需要进一步降低 cold，可考虑减少冷启动必经的全量扫描/解析成本（算法级优化）。

