# 编码计划：基准测试指标补齐 + 性能提升闭环（Schema v1.1）

- 维护者：Planner
- 关联规范：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/design.md`；`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/specs/benchmarks/spec.md`
- 输入材料：设计文档、规格增量
- 变更包：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/`

## 模式选择
主线计划模式

## 主线计划区 (Main Plan Area)

### MP1：Schema v1.1 产物双写与元信息补齐
- 目的（Why）：确保 `benchmark_result.json` 升级到 v1.1 且保持向后兼容读取。
- 交付物（Deliverables）：v1.1 必填字段写入、metrics.* 与顶层兼容字段双写映射、固定 `schema_version=1.1`。
- 影响范围（Files/Modules）：`benchmarks/run_benchmarks.py`、`scripts/benchmark.sh`、`benchmark_result.json` 产出链路。
- 验收标准（Acceptance Criteria）：AC-001、AC-002、AC-007。
- 依赖（Dependencies）：REQ-BM-007/REQ-BM-002、Schema v1.1 字段清单。
- 风险（Risks）：字段缺失或双写不一致导致 compare 回退错误。
- [x] MP1.1 补齐 v1.1 必填字段写入与类型约束（AC-001；验收锚点：schema 字段清单核对、JSON 结构校验）
- [x] MP1.2 metrics.* 与顶层兼容字段双写映射且数值一致（AC-002；验收锚点：双写一致性比对）
- [x] MP1.3 run/environment 元信息与 project_root/generated_at 写入（AC-001、AC-007；验收锚点：产物字段审计）

### MP2：queries_version 生成与校验入口
- 目的（Why）：确保查询集版本可复验并参与 compare 对齐校验。
- 交付物（Deliverables）：`queries_version=sha256:<8>` 生成逻辑与对齐校验入口。
- 影响范围（Files/Modules）：`benchmarks/run_benchmarks.py`、`scripts/benchmark.sh`、查询集版本生成规则。
- 验收标准（Acceptance Criteria）：AC-001、AC-005。
- 依赖（Dependencies）：REQ-BM-006/REQ-BM-010、查询集文件路径规则。
- 风险（Risks）：版本计算不一致导致 compare 误判。
- [x] MP2.1 实现 queries_version 哈希计算与写入规则（AC-001；验收锚点：benchmark_result.json 中 queries_version 字段一致性校验）
- [x] MP2.2 提供 queries_version 校验命令入口并对齐 compare 校验（AC-005；验收锚点：版本不一致时 compare 输出与退出码校验，需先设计确认/回写后实施）

### MP3：baseline/current 产物路径与 median-of-3 产出
- 目的（Why）：固定证据链与回归口径，减少噪声。
- 交付物（Deliverables）：baseline/current 各 3 次 run 产物与对应摘要、median JSON 与 summary 产物。
- 影响范围（Files/Modules）：`benchmarks/run_benchmarks.py`、产物目录 `benchmarks/baselines` 与 `benchmarks/results`。
- 验收标准（Acceptance Criteria）：AC-003、AC-004、AC-007。
- 依赖（Dependencies）：REQ-BM-009/REQ-BM-005、产物路径清单。
- 风险（Risks）：路径不一致或缺失导致证据链断裂。
- [x] MP3.1 固定 baseline/current run-1..3 产物路径并输出 JSON+Markdown 摘要（AC-003、AC-007；验收锚点：产物清单与摘要模板核对）
- [x] MP3.2 生成 baseline/current median JSON 与 summary 产物（AC-003、AC-007；验收锚点：median 产物路径与摘要模板核对）
- [x] MP3.3 median-of-3 按逐指标取中位数且 compare 仅使用 median 产物（AC-004；验收锚点：中位数计算规则审计、compare 输入路径核对）

### MP4：compare 输出契约、版本对齐与阈值规则
- 目的（Why）：确保回归判定可复验且输出稳定。
- 交付物（Deliverables）：两行 stdout 契约、summary JSON 结构、阈值优先级与 metrics 映射、版本不一致处理。
- 影响范围（Files/Modules）：`scripts/benchmark.sh --compare`、compare 逻辑、summary JSON 生成。
- 验收标准（Acceptance Criteria）：AC-005、AC-006、AC-002。
- 依赖（Dependencies）：REQ-BM-008/REQ-BM-004、阈值规则与优先级。
- 风险（Risks）：阈值优先级错误导致误报或漏报。
- [x] MP4.1 实现版本对齐校验与退出码映射（0/1/2）（AC-005；验收锚点：version_mismatch 输出与退出码校验）
- [x] MP4.2 compare stdout 严格两行且 summary JSON 符合结构（AC-006；验收锚点：stdout 捕获与 JSON 结构校验）
- [x] MP4.3 优先读取 metrics.*，缺失回退顶层字段；按阈值优先级判定并纳入 precision_at_10（AC-002、AC-006；验收锚点：metrics 映射表核对与阈值优先级示例验证）

### MP5：性能开关默认开启与回退策略实现点
- 目的（Why）：确保性能优化可控并具备诊断回退路径。
- 交付物（Deliverables）：三项开关默认开启的读取/传递路径、回退执行步骤与产物复验口径。
- 影响范围（Files/Modules）：`scripts/benchmark.sh`、`scripts/graph-rag-query.sh`、`scripts/embedding.sh`、`scripts/cache-manager.sh`。
- 验收标准（Acceptance Criteria）：AC-008。
- 依赖（Dependencies）：运行规则与 cache_clear 清单。
- 风险（Risks）：开关状态不一致导致可重复性下降。
- [x] MP5.1 默认启用 CI_BENCH_EARLY_STOP/CI_BENCH_SUBGRAPH_CACHE/CI_BENCH_EMBEDDING_QUERY_CACHE（AC-008；验收锚点：运行配置输出与产物标记核对）
- [x] MP5.2 回退路径实现点：全关开关 + 执行 cache_clear + 重跑 3 次生成 median 产物（AC-008；验收锚点：回退证据与产物清单核对）

### MP6：Graph-RAG 动态早停优化
- 目的（Why）：降低 Graph-RAG 延迟并维持检索质量。
- 交付物（Deliverables）：动态早停策略实现点与候选数约束保持。
- 影响范围（Files/Modules）：`scripts/graph-rag-query.sh`、Graph-RAG 查询流程。
- 验收标准（Acceptance Criteria）：AC-009、AC-011。
- 依赖（Dependencies）：REQ-GR-004、性能开关默认开启。
- 风险（Risks）：早停导致质量指标下滑。
- [x] MP6.1 实现 Graph-RAG 动态早停并保持输出契约不变（AC-009、AC-011；验收锚点：Graph-RAG 延迟与质量指标对比）

### MP7：Embedding 查询缓存优化
- 目的（Why）：降低语义搜索延迟并减少重复计算。
- 交付物（Deliverables）：embedding 查询缓存策略与命中路径。
- 影响范围（Files/Modules）：`scripts/embedding.sh`、缓存管理脚本。
- 验收标准（Acceptance Criteria）：AC-010。
- 依赖（Dependencies）：REQ-CACHE-003/REQ-CACHE-004/REQ-CACHE-005。
- 风险（Risks）：缓存键不一致导致命中失效或数据污染。
- [x] MP7.1 按缓存规范实现 embedding 查询缓存与键规则（AC-010；验收锚点：语义搜索延迟指标与缓存命中验证，需先设计确认/回写后实施）

### MP8：子图缓存（LRU）优化
- 目的（Why）：提升 Graph-RAG warm 路径并稳定缓存命中。
- 交付物（Deliverables）：子图缓存 LRU 策略与跨进程可读实现点。
- 影响范围（Files/Modules）：`scripts/cache-manager.sh`、`scripts/graph-rag-query.sh`、`subgraph-lru-cache` 相关实现。
- 验收标准（Acceptance Criteria）：AC-009。
- 依赖（Dependencies）：REQ-SLC-001~REQ-SLC-009。
- 风险（Risks）：缓存键定义不清导致回归难以复验。
- [x] MP8.1 实现子图缓存 LRU 策略与键规则（AC-009；验收锚点：warm 延迟指标与缓存命中对比，需先设计确认/回写后实施）

### MP9：证据产物采集与文档同步
- 目的（Why）：为 Green-Verify 留存完整证据链并同步对外说明。
- 交付物（Deliverables）：compare stdout/退出码与 median 产物证据、README/TECHNICAL 文档更新。
- 影响范围（Files/Modules）：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/`、`README.md`、`README.zh-CN.md`、`docs/TECHNICAL.md`、`docs/TECHNICAL_zh.md`。
- 验收标准（Acceptance Criteria）：AC-001、AC-003、AC-005、AC-006、AC-008。
- 依赖（Dependencies）：产物路径与 compare 输出契约已落地。
- 风险（Risks）：证据缺失导致 DoD 无法验收。
- [x] MP9.1 采集 compare stdout/退出码与 baseline/current median 产物到证据目录（AC-003、AC-005、AC-006、AC-008；验收锚点：evidence 目录清单核对）
- [x] MP9.2 更新 README 与 TECHNICAL 中英文说明（schema v1.1、产物路径、compare 契约）（AC-001、AC-003、AC-006；验收锚点：文档条目对照检查）

## 临时计划区 (Temporary Plan Area)
- 当前无临时任务

## 计划细化区

### Scope & Non-goals
- 范围：Schema v1.1 双写、固定产物路径、median-of-3、compare 输出契约、queries_version 规则、性能开关与三类性能优化点、证据采集与文档同步。
- 非目标：新增外部服务、修改 MCP 工具语义、移除顶层兼容字段、改变 Graph-RAG JSON 输出契约。

### Architecture Delta
- 无模块边界变更；沿用脚本依赖方向与薄壳架构约束。

### Data Contracts
- `benchmark_result.json`：schema_version 固定为 1.1，双写 metrics.* 与顶层兼容字段。
- `benchmark_summary.median.md`：固定模板字段与 Regression Summary 表。
- compare summary JSON：两行 stdout、`status/threshold_mode/metrics[]` 或 `version_mismatch` 结构。
- `queries_version`：`sha256:<8>`，与查询集内容一致。

### Milestones
- M1（Schema 与 compare 定稿）：完成 MP1、MP2、MP4；以 compare 契约与版本对齐为准。
- M2（产物与 median 口径定稿）：完成 MP3；以路径与 median 产物完整性为准。
- M3（性能优化与证据链）：完成 MP5~MP9；以全开场景指标与证据链为准。

### Work Breakdown
- 并行优先：MP1 与 MP2 并行；MP3 与 MP4 并行；MP6/MP7/MP8 并行。
- 依赖顺序：MP3 与 MP4 依赖 MP1/MP2 的产物字段与版本规则；MP9 依赖 MP3 与 MP4 产物与 compare 输出。
- PR 切分建议：按 MP 维度切分，避免跨模块大改；性能优化独立 PR。

### Deprecation & Cleanup
- v1.1 保持顶层兼容字段；v1.2 才考虑移除，需同步更新 compare 与迁移说明。
- 旧 compare 输出结构仅保留兼容读取，不作为回归判定口径。

### Dependency Policy
- 不新增外部依赖；遵循现有脚本与工具链（rg、jq、git、python）。
- 严格遵守脚本依赖方向：scripts 不依赖 src。

### Quality Gates
- 静态检查：ShellCheck、TypeScript typecheck（如受影响）。
- 行为验证：compare stdout/退出码、schema v1.1 字段校验、产物路径检查。
- 契约校验：summary JSON 结构与 Markdown 模板字段完整性。

### Guardrail Conflicts
- 目前未触发代理指标冲突；若性能优化导致跨模块大规模同质化改动，需切分为多 PR 并补充验收锚点。

### Observability
- 产物与 compare 输出作为可观测锚点：baseline/current median 产物、summary、stdout/退出码。
- 证据目录作为 Green-Verify 入口：保存 compare 输出与 median 产物。

### Rollout & Rollback
- 默认全开：CI_BENCH_EARLY_STOP=1，CI_BENCH_SUBGRAPH_CACHE=1，CI_BENCH_EMBEDDING_QUERY_CACHE=1。
- 回退流程：关闭开关 + 执行 run.cache_clear + 重跑 3 次生成 median 产物，仅用于诊断。

### Risks & Edge Cases
- 版本不一致：compare 直接失败并返回非零退出码。
- metrics 缺失：compare 需回退读取顶层字段，仍要输出完整 metrics 列表。
- 缓存键不一致：可能导致命中失效或交叉污染，需要设计确认。
- 早停策略偏激：检索质量指标可能跌破阈值。

### Algorithm Spec

**Algorithm A：median-of-3 指标聚合**
- Inputs：run-1/2/3 的 metrics.* 与兼容字段数值
- Outputs：median 产物的 metrics.* 与兼容字段数值
- Invariants：只对数值指标取中位数；direction 不参与计算
- Failure Modes：任一 run 缺失指标；指标值为非数值
- Pseudocode:
```
FOR EACH metric_name IN metrics_catalog
  COLLECT values FROM run-1, run-2, run-3
  IF any value is missing OR not numeric
    EMIT error "median_input_invalid"
  SORT values ASC
  median_value = values[1]
  WRITE median_result.metric_name = median_value
  IF has_compat_field(metric_name)
    WRITE median_result.compat_field = median_value
END FOR
```
- Complexity：Time O(M log 3)，Space O(M)
- Edge Cases：缺失 run；单项指标为 NaN；run 数值相同；指标方向为 higher 或 lower；兼容字段缺失

**Algorithm B：compare 版本校验与阈值判定**
- Inputs：baseline_median、current_median、metric.threshold（可选）、全局阈值（可选）
- Outputs：result 行、summary JSON、退出码
- Invariants：版本不一致直接失败；阈值优先级固定
- Failure Modes：baseline/current 缺失 metrics；阈值计算溢出
- Pseudocode:
```
IF schema_version OR queries_version mismatch
  EMIT result=regression
  EMIT summary with status=fail reason=version_mismatch
  EXIT code 2
FOR EACH metric IN required_metrics
  baseline = read_metric(metric, baseline_median)
  current = read_metric(metric, current_median)
  threshold = resolve_threshold(metric.threshold, global_threshold, default_rule)
  result = compare_by_direction(metric.direction, baseline, current, threshold)
  APPEND to summary.metrics[]
END FOR
overall = fail IF any metric result is fail ELSE pass
EMIT result line and summary line
EXIT code 0 if overall pass else 1
```
- Complexity：Time O(M)，Space O(M)
- Edge Cases：precision_at_10 未纳入；metrics.* 缺失但顶层存在；阈值为 0；baseline 为 0；方向值未知

### Design Backport Candidates（需回写设计）
- queries_version 校验命令的对外入口定义（命令名与参数形式需在设计中明确）。
- Embedding 查询缓存与子图缓存的 key 组成细则（需对齐 REQ-CACHE-003 与 REQ-SLC-004）。

### Open Questions
1. 是否需要更新 Spec 以允许子图缓存 TTL？若需要，TTL 的默认值与退出条件是什么？
2. Embedding 查询缓存如何映射到 REQ-CACHE-003 的 `file_path/mtime/blob_hash` 约束？
3. Graph-RAG 子图缓存的 Key 如何在不违背 REQ-SLC-004 的前提下纳入 `query/top_k/fusion_weights` 影响因子？

## 断点区 (Context Switch Breakpoint Area)
- 当前无断点记录
