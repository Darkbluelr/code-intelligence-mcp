# 验证计划：20260123-0703-benchmarks-metrics-perf-upgrade

========================
A) 测试计划指令表
========================

### 主线计划区 (Main Plan Area)

- [ ] TP1.1 对比契约与退出码一致性
  - Why：compare 输出与退出码是 CI 回归判定的唯一锚点
  - Acceptance Criteria（引用 AC-xxx / Requirement）：AC-005、AC-006（REQ-BM-008、REQ-BM-004）
  - Test Type：contract
  - Non-goals：不验证性能提升幅度，不运行完整 benchmark
  - Candidate Anchors（Test IDs / commands / evidence）：
    - Test IDs：CT-BM-201、CT-BM-202、CT-BM-203、CT-BM-205、CT-BM-402、CT-BM-403、CT-BM-404
    - Commands：`bats tests/benchmark-contract-v1_1.bats`，`bats tests/benchmarks-contract.bats`

- [ ] TP1.2 Schema v1.1 与双写兼容字段一致性
  - Why：v1.1 双写是兼容期对外契约，必须稳定
  - Acceptance Criteria（引用 AC-xxx / Requirement）：AC-001、AC-002、AC-007（REQ-BM-007、REQ-BM-002、REQ-BM-005）
  - Test Type：contract
  - Non-goals：不验证真实环境采集结果，仅验证契约与样例
  - Candidate Anchors（Test IDs / commands / evidence）：
    - Test IDs：CT-BM-101、CT-BM-102、CT-BM-103、CT-BM-204、CT-BM-401、CT-BM-405、CT-BM-407
    - Commands：`bats tests/benchmark-contract-v1_1.bats`，`bats tests/benchmarks-contract.bats`

- [ ] TP1.3 median-of-3 规则与产物路径清单
  - Why：固定产物路径与中位数口径保证可复验
  - Acceptance Criteria（引用 AC-xxx / Requirement）：AC-003、AC-004（REQ-BM-009、REQ-BM-003）
  - Test Type：contract
  - Non-goals：不生成真实性能数据
  - Candidate Anchors（Test IDs / commands / evidence）：
    - Test IDs：CT-BM-301、CT-BM-406
    - Commands：`bats tests/benchmark-contract-v1_1.bats`，`bats tests/benchmarks-contract.bats`

- [ ] TP1.4 性能开关与性能阈值人工验收
  - Why：性能阈值受环境影响，需人工复核证据
  - Acceptance Criteria（引用 AC-xxx / Requirement）：AC-008、AC-009、AC-010、AC-011（REQ-BM-004、REQ-HR-005）
  - Test Type：manual
  - Non-goals：不在 Red 阶段判定通过
  - Candidate Anchors（Test IDs / commands / evidence）：
    - Test IDs：MANUAL-001、MANUAL-002、MANUAL-003、MANUAL-004
    - Commands：`python benchmarks/run_benchmarks.py --output <median_json> --update-readme`，`scripts/benchmark.sh --compare <baseline_median_json> <current_median_json>`

### 临时计划区 (Temporary Plan Area)

- 本轮无临时任务

### 断点区 (Context Switch Breakpoint Area)

- 上次进度：已新增 contract tests（`tests/benchmarks-contract.bats`），已跑出 Red 基线
- 当前阻塞：compare/median/产物路径契约尚未实现，测试仍失败
- 下一步最短路径：交给 Coder 按 design/spec 实现 compare 输出、版本校验、median 产物与路径生成

---

### 计划细化区

#### Scope & Non-goals
- Scope：compare 输出与退出码、schema v1.1 双写一致性、median-of-3 规则、产物路径清单、摘要模板契约
- Non-goals：不验证性能提升幅度、不引入新依赖、不修改实现代码

#### 测试金字塔与分层策略
| 类型 | 数量 | 覆盖场景 | 预期执行时间 |
|---|---:|---|---|
| 单元测试 | 0 | 无 | < 5s |
| 契约测试 | 16 | compare/schema/median/路径 | < 10s |
| 集成测试 | 0 | 无 | < 30s |
| E2E 测试 | 0 | 无 | < 60s |

#### 测试矩阵（Requirement/Risk → Test IDs → 断言点 → 覆盖的验收标准）
| Requirement/Risk | Test IDs | 断言点 | 覆盖 AC |
|---|---|---|---|
| REQ-BM-007 Schema v1.1 + 必填字段 | CT-BM-101、CT-BM-401 | schema_version=1.1、字段类型与必填性 | AC-001 |
| REQ-BM-002 双写一致性与兼容读取 | CT-BM-102、CT-BM-204、CT-BM-405、CT-BM-407 | metrics.* 与顶层字段数值一致、compare 优先 metrics.* | AC-002 |
| REQ-BM-005 摘要模板 | CT-BM-103 | summary 模板字段齐全 | AC-007 |
| REQ-BM-008 compare 输出契约 | CT-BM-201、CT-BM-402 | stdout 两行、summary JSON 字段完整 | AC-006 |
| REQ-BM-008 版本对齐 | CT-BM-202、CT-BM-404 | version_mismatch → result=regression + exit=2 | AC-005 |
| REQ-BM-004 阈值优先级 | CT-BM-203、CT-BM-205、CT-BM-403 | metric.threshold 优先并触发回归 | AC-006 |
| REQ-BM-009 median-of-3 | CT-BM-301 | 逐指标取中位数 | AC-004 |
| 产物路径固定化 | CT-BM-406 | baseline/current run 与 median 路径存在 | AC-003 |
| 性能开关与阈值验收 | MANUAL-001~004 | 全开场景证据与阈值校验 | AC-008~AC-011 |

#### 测试数据与夹具策略
- 基准样例：`tests/fixtures/benchmark/schema-v1.1.sample.json`
- 查询集：`tests/fixtures/benchmark/queries.jsonl`
- 对比样例：`tests/fixtures/benchmark/regression-baseline.json`、`tests/fixtures/benchmark/regression-current.json`

#### 业务语言约束
- 使用 domain 术语：baseline/current/median、result/no_regression/regression、schema_version/queries_version
- 不在测试描述中引入实现细节（函数名/内部流程）

#### 可复现性策略
- 全部使用固定 fixtures；不依赖网络
- compare 测试通过临时文件构造 baseline/current
- median-of-3 测试使用固定数值集

#### 风险与降级
- 风险：本机无 `bats` 或 `jq` 时无法执行
- 降级：在 Coder 阶段用 CI 环境执行，或安装依赖后重跑

#### 配置与依赖变更验证
- `BENCHMARK_REGRESSION_THRESHOLD` 覆盖阈值规则（CT-BM-203/403）
- `BENCHMARK_METRIC_THRESHOLDS` 覆盖 per-metric 阈值优先级（CT-BM-205）
- `queries_version` 通过 `tests/fixtures/benchmark/queries.jsonl` 计算（CT-BM-202/404）

#### 坏味道检测策略
- 使用现有静态闸门：`npm run lint`（shellcheck scripts）
- 若 compare 输出格式在多个脚本重复定义，建议统一在单一脚本内

#### Test Oracle Spec

**Oracle-Threshold（阈值优先级）**
- Inputs：baseline、current、direction、metric.threshold、BENCHMARK_REGRESSION_THRESHOLD
- Outputs：threshold_mode、per-metric threshold、result、exit code
- Invariants：当 metric.threshold 存在时必须优先；precision_at_10 必须参与判定
- Failure Modes：使用全局阈值覆盖 metric.threshold；回归仍返回 exit 0；遗漏 precision_at_10
- Pseudocode：
  1. if metric.threshold exists → threshold = metric.threshold
  2. else if global threshold exists → threshold = baseline * (1±t)
  3. else → threshold = baseline * default_ratio
  4. compare current vs threshold by direction
  5. any fail → result=regression, exit=1
- Boundary Conditions（>=5）：
  - metric.threshold 等于 current
  - baseline 为 0 且 direction=lower
  - metric.threshold 缺失但全局阈值存在
  - current 精确等于 threshold
  - 同时包含 precision_at_10 与 latency 指标
- Test ID Mapping：CT-BM-201、CT-BM-203、CT-BM-205、CT-BM-403

**Oracle-Median（median-of-3）**
- Inputs：run1/run2/run3 的同一指标值
- Outputs：median 产物中的对应指标值
- Invariants：逐指标取中位数，direction 不参与计算
- Failure Modes：使用平均值；将 direction 影响排序；忽略某个 run
- Pseudocode：
  1. values = [run1, run2, run3]
  2. sort(values)
  3. median = values[1]
  4. write median into output
- Boundary Conditions（>=5）：
  - 三个值完全相同
  - 值包含浮点数
  - 值包含负数
  - 值包含极端大数
  - run2 缺失指标字段
- Test ID Mapping：CT-BM-301、CT-BM-406

#### 架构异味报告
- Setup 复杂度：中（依赖 bats/jq）
- Mock/Fixture 数量：中（多份基准 JSON）
- 清理难度：低（临时文件在测试目录内）
- 建议：compare 输出契约集中定义，避免跨脚本重复逻辑

---

## 元信息

- Change ID：`20260123-0703-benchmarks-metrics-perf-upgrade`
- 状态：`Done`
- Status: Done
- 关联：
  - Proposal：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/proposal.md`
  - Design：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/design.md`
  - Spec deltas：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/specs/benchmarks/spec.md`
- 维护者：Test Owner
- 更新时间：2026-01-24
- Test Owner（独立对话）：gpt-5.2-codex xhigh
- Coder（独立对话）：未指派
- Red 基线命令：`bats tests/benchmark-contract-v1_1.bats tests/benchmarks-contract.bats`
- Red 基线失败证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/red-baseline/bats-contract-20260124-124550.log`

---

## 测试策略

### 测试类型分布
| 测试类型 | 数量 | 用途 | 预期耗时 |
|---|---:|---|---|
| 单元测试 | 0 | 无 | < 5s |
| 集成测试 | 0 | 无 | < 30s |
| E2E 测试 | 0 | 无 | < 60s |
| 契约测试 | 16 | compare/schema/median/路径 | < 10s |

### 测试分层策略
| 类型 | 数量 | 覆盖场景 | 预期执行时间 |
|---|---:|---|---|
| 单元测试 | 0 | 无 | < 5s |
| 契约测试 | 16 | AC-001~AC-007 | < 10s |
| 集成测试 | 0 | 无 | < 30s |
| E2E 测试 | 0 | 无 | < 60s |

### 测试环境要求
| 测试类型 | 运行环境 | 依赖 |
|---|---|---|
| 契约测试 | macOS / bash | bats, jq |

---

## AC 覆盖矩阵

| AC-ID | 描述 | 测试类型 | Test ID | 优先级 | 状态 |
|---|---|---|---|---|---|
| AC-001 | schema_version=1.1 且字段必填 | 契约 | CT-BM-101, CT-BM-401 | P0 | [ ] |
| AC-002 | metrics.* 双写一致 + compare 回退 | 契约 | CT-BM-102, CT-BM-204, CT-BM-405, CT-BM-407 | P0 | [ ] |
| AC-003 | baseline/current 产物路径齐全 | 契约 | CT-BM-406 | P0 | [ ] |
| AC-004 | median-of-3 逐指标中位数 | 契约 | CT-BM-301 | P0 | [ ] |
| AC-005 | version_mismatch → result=regression + exit=2 | 契约 | CT-BM-202, CT-BM-404 | P0 | [ ] |
| AC-006 | compare 两行输出 + 阈值规则 + precision_at_10 | 契约 | CT-BM-201, CT-BM-203, CT-BM-205, CT-BM-402, CT-BM-403 | P0 | [ ] |
| AC-007 | benchmark_summary.median.md 模板 | 契约 | CT-BM-103 | P1 | [ ] |
| AC-008 | 性能开关默认全开且仅采信全开结果 | 手动 | MANUAL-001 | P1 | [ ] |
| AC-009 | Graph-RAG warm/cold P95 阈值 | 手动 | MANUAL-002 | P1 | [ ] |
| AC-010 | 语义搜索 P95 阈值 | 手动 | MANUAL-003 | P1 | [ ] |
| AC-011 | 检索质量指标阈值 | 手动 | MANUAL-004 | P1 | [ ] |

**覆盖摘要**：
- AC 总数：11
- 已有测试覆盖：11
- 覆盖率：11/11 = 100%

---

## 边界条件检查清单

### 输入验证
- [ ] 空输入 / null 值
- [ ] 超过最大长度
- [ ] 无效格式（版本号/JSON）

### 状态边界
- [ ] baseline/current 任一缺失
- [ ] 指标为 0 或极端值
- [ ] 指标为负数

### 并发与时序
- [ ] 多次 compare 连续执行

### 错误处理
- [ ] JSON 无效时退出非零
- [ ] schema_version/queries_version 不一致时阻断

---

## 测试优先级

| 优先级 | 定义 | Red 基线要求 |
|---|---|---|
| P0 | 契约硬约束 | 必须在 Red 基线中失败 |
| P1 | 重要补充 | 可在 Red 基线中失败 |
| P2 | 锦上添花 | Red 基线中可选 |

### P0 测试（必须在 Red 基线中）
1. CT-BM-201: compare stdout 两行 + summary JSON
2. CT-BM-202: version_mismatch 退出码=2
3. CT-BM-203: 阈值优先级 metric.threshold
4. CT-BM-205: per-metric 阈值优先级
5. CT-BM-301: median-of-3 逐指标中位数
6. CT-BM-406: 产物路径清单存在
7. CT-BM-407: metrics.* 优先读取

### P1 测试（应该在 Red 基线中）
1. CT-BM-101: schema v1.1 必填字段
2. CT-BM-102: 双写一致性
3. CT-BM-103: summary 模板字段

### P2 测试（可选）
- 无

---

========================
B) 追溯矩阵（Traceability Matrix）
========================

| AC | Requirement/Scenario | Test IDs / Commands | Evidence / MANUAL-* | Status | 因果链完整性 |
|---|---|---|---|---|---|
| AC-001 | REQ-BM-007, SC-BM-101 | CT-BM-101, CT-BM-401 | `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/red-baseline/bats-contract-20260124-065846.log` | Red | [ ] 完整 |
| AC-002 | REQ-BM-007, REQ-BM-002, SC-BM-101 | CT-BM-102, CT-BM-204, CT-BM-405, CT-BM-407 | `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/red-baseline/bats-contract-20260124-065846.log` | Red | [ ] 完整 |
| AC-003 | REQ-BM-009, SC-BM-102 | CT-BM-406 | `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/red-baseline/bats-contract-20260124-065846.log` | Red | [ ] 完整 |
| AC-004 | REQ-BM-009, SC-BM-102 | CT-BM-301 | `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/red-baseline/bats-contract-20260124-065846.log` | Red | [ ] 完整 |
| AC-005 | REQ-BM-008, SC-BM-104 | CT-BM-202, CT-BM-404 | `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/red-baseline/bats-contract-20260124-065846.log` | Red | [ ] 完整 |
| AC-006 | REQ-BM-008, REQ-BM-004, SC-BM-103, SC-BM-105 | CT-BM-201, CT-BM-203, CT-BM-205, CT-BM-402, CT-BM-403 | `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/red-baseline/bats-contract-20260124-065846.log` | Red | [ ] 完整 |
| AC-007 | REQ-BM-005, SC-BM-107 | CT-BM-103 | `dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/red-baseline/bats-contract-20260124-065846.log` | Red | [ ] 完整 |
| AC-008 | DoD | MANUAL-001 | MANUAL-001 | Planned | [ ] 完整 |
| AC-009 | REQ-BM-004 | MANUAL-002 | MANUAL-002 | Planned | [ ] 完整 |
| AC-010 | REQ-BM-004 | MANUAL-003 | MANUAL-003 | Planned | [ ] 完整 |
| AC-011 | REQ-HR-005 | MANUAL-004 | MANUAL-004 | Planned | [ ] 完整 |

### 追溯矩阵完整性检查清单

- [ ] 无孤儿 AC
- [ ] 无孤儿测试
- [ ] 无无证据 DONE
- [x] Red 基线存在
- [ ] Green 证据存在

---

========================
C) 执行锚点（Deterministic Anchors）
========================

### 1) 行为（Behavior）
- contract：`/opt/homebrew/bin/bats tests/benchmarks-contract.bats`

### 2) 契约（Contract）
- contract tests：`/opt/homebrew/bin/bats tests/benchmark-contract-v1_1.bats`

### 3) 结构（Structure / Fitness Functions）
- 无（本次变更无架构变更）

### 4) 静态与安全（Static/Security）
- lint/typecheck/build：`npm run lint`（未在 Red 阶段执行）
- 报告格式：text
- 质量闸门：shellcheck scripts/*.sh

---

========================
D) MANUAL-* 清单（人工/混合验收）
========================

- [ ] MANUAL-001 性能开关默认全开且仅采信全开结果
  - Pass/Fail 判据：`CI_BENCH_EARLY_STOP=1`、`CI_BENCH_SUBGRAPH_CACHE=1`、`CI_BENCH_EMBEDDING_QUERY_CACHE=1` 为默认值，且 compare 证据来自全开 median
  - Evidence：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/performance/` 下的基线与当前 median 产物
  - 责任人/签字：待 Coder/Reviewer

- [ ] MANUAL-002 Graph-RAG P95 阈值
  - Pass/Fail 判据：warm_latency_p95_ms <= baseline_median * 0.90 且 cold_latency_p95_ms <= baseline_median * 0.95
  - Evidence：`benchmark_result.median.json` 与 compare summary JSON
  - 责任人/签字：待 Coder/Reviewer

- [ ] MANUAL-003 语义搜索 P95 阈值
  - Pass/Fail 判据：latency_p95_ms <= baseline_median * 0.95
  - Evidence：`benchmark_result.median.json` 与 compare summary JSON
  - 责任人/签字：待 Coder/Reviewer

- [ ] MANUAL-004 检索质量指标阈值
  - Pass/Fail 判据：mrr/recall/precision/hit_rate >= baseline_median * 0.95
  - Evidence：`benchmark_result.median.json` 与 compare summary JSON
  - 责任人/签字：待 Coder/Reviewer

---

========================
E) 风险与降级（可选）
========================

- 风险：compare 仍输出旧格式导致 CI 判断失效
- 降级策略：在 CI 阶段优先使用新 compare 输出，旧格式仅保留兼容读取
- 回滚策略：保留 v1.1 双写兼容字段，避免旧消费者中断

========================
F) 结构质量守门记录（可选）
========================

- 冲突点：无代理指标驱动要求
- 评估影响（内聚/耦合/可测试性）：无结构性风险
- 替代闸门（复杂度/耦合/依赖方向/测试质量）：保持 shellcheck + bats 契约测试
- 决策与授权：无

========================
G) 价值流与度量（可选，但必须显式填"无"）
========================

- 目标价值信号：无
- 价值流瓶颈假设：无
- 交付与稳定性指标：无
- 观测窗口与触发点：无
- Evidence：无

========================
H) 审计与证据管理（推荐）
========================

- Red 基线证据：`dev-playbooks/changes/20260123-0703-benchmarks-metrics-perf-upgrade/evidence/red-baseline/bats-contract-20260124-065846.log`
- Green 最终证据：待 Coder 产出
