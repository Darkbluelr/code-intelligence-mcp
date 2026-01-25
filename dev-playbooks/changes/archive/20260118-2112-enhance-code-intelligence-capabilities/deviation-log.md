# 偏离日志

## 待回写记录

| 时间 | 类型 | 描述 | 涉及文件 | 已回写 |
|---|---|---|---|:---:|
| 2026-01-19 04:51 | CONSTRAINT_CHANGE | 上下文压缩实现使用基于规则的签名抽取，未接入 tree-sitter AST（与"基于 AST"约束不一致） | scripts/context-compressor.sh | ✅ |
| 2026-01-19 04:51 | CONSTRAINT_CHANGE | 单文件快速模式可能导致压缩率超出 50% 上限 | scripts/context-compressor.sh | ✅ (IMPL_ONLY) |
| 2026-01-19 05:38 | IMPLEMENTATION_GAP | scripts/benchmark.sh 未实现 --dataset/--baseline/--compare（评测基准与回归检测） | scripts/benchmark.sh, tests/benchmark.bats | ✅ |
| 2026-01-19 05:38 | IMPLEMENTATION_GAP | scripts/embedding.sh 缺少 --benchmark 支持（混合检索质量指标） | scripts/embedding.sh, tests/hybrid-retrieval.bats | ✅ |
| 2026-01-19 05:38 | IMPLEMENTATION_GAP | semantic-anomaly.sh 未实现 --output <file> JSONL/--feedback/--report（AC-008 规格增量） | scripts/semantic-anomaly.sh, tests/semantic-anomaly.bats | ✅ |
| 2026-01-19 05:38 | CONSTRAINT_CHANGE | 功能开关默认读取 .devbooks/config.yaml，与设计要求 config/features.yaml 不一致 | scripts/common.sh, config/features.yaml | ✅ |
| 2026-01-19 05:38 | IMPLEMENTATION_GAP | config/features.yaml 缺少新能力开关（context_compressor, drift_detector, hybrid_retrieval, context_signals, benchmark, performance_regression） | config/features.yaml | ✅ |
| 2026-01-19 05:38 | SPEC_DRIFT | truth spec 的 long-term-memory（memory_* API）与本变更 AC-007（context signals）不一致 | dev-playbooks/specs/long-term-memory/spec.md, dev-playbooks/changes/20260118-2112-enhance-code-intelligence-capabilities/design.md | ✅ |
| 2026-01-19 05:38 | CONSTRAINT_CHANGE | 交互信号权重设计值（view 1.5x / edit 2.0x / ignore -0.5x）与 intent-learner 实现权重不一致 | scripts/intent-learner.sh, dev-playbooks/changes/20260118-2112-enhance-code-intelligence-capabilities/design.md | ✅ |
| 2026-01-19 05:38 | IMPLEMENTATION_GAP | 缺少 --enable-all-features 一键启用入口 | scripts/graph-rag.sh, dev-playbooks/changes/20260118-2112-enhance-code-intelligence-capabilities/design.md | ✅ |
| 2026-01-19 06:20 | DESIGN_GAP | 上下文压缩未定义不支持语言的错误反馈（新增 T-CC-ERROR-004 期望友好提示） | dev-playbooks/specs/context-compressor/spec.md, tests/context-compressor.bats | ✅ (IMPL_ONLY) |
| 2026-01-19 08:09 | TEST_COVERAGE | tasks.md 计划包含 tests/reranker.bats，但仓库缺失该文件且禁止修改 tests/；改用 reranker-performance.json 与 llm-rerank.bats 作为验证 | dev-playbooks/changes/20260118-2112-enhance-code-intelligence-capabilities/tasks.md, scripts/reranker.sh, tests/llm-rerank.bats | ✅ (IMPL_ONLY) |
| 2026-01-20 18:55 | REFACTOR | 创建 src/tool-handlers.ts 文件，将 handleToolCall 从 374 行 switch 语句重构为策略模式（修复 C-001, C-002） | src/server.ts, src/tool-handlers.ts | ✅ |
| 2026-01-20 19:30 | TEST_QUALITY | 修复 M-004：tests/context-compressor.bats:481-522 并发测试添加缓存隔离验证（验证缓存目录创建和交叉污染检测） | tests/context-compressor.bats | ✅ |
| 2026-01-20 19:30 | TEST_QUALITY | 修复 M-006：tests/hybrid-retrieval.bats:395-419 性能测试添加预热验证（每次预热失败时立即报错） | tests/hybrid-retrieval.bats | ✅ |
| 2026-01-20 19:30 | TEST_QUALITY | 修复 M-007：tests/llm-rerank.bats:345-402 并发测试添加竞态条件验证（时间戳验证确保真正并发执行） | tests/llm-rerank.bats | ✅ |
| 2026-01-20 19:10 | REFACTOR | 修复 M-008：重构 compress_file 函数，拆分为 _cf_process_signature_line 等子函数，降低复杂度（130行→70行） - **已回滚**，重构引入重复输出 bug | scripts/context-compressor.sh | ✅ (IMPL_ONLY) |
| 2026-01-20 19:10 | REFACTOR | 修复 M-013：重构 _main_build_output_json 函数，使用全局变量减少参数数量（9→0） | scripts/context-compressor.sh | ✅ |
| 2026-01-21 00:30 | BUG_FIX | 回滚 M-008 重构：恢复原始 compress_file 函数，修复重复输出 bug（constructor 和签名被重复输出，导致压缩率 >1） | scripts/context-compressor.sh | ✅ (IMPL_ONLY) |
| 2026-01-20 20:15 | SECURITY_FIX | 修复 M-009：cmd_batch_import 添加事务回滚后的 VACUUM 清理，防止部分数据残留 | scripts/graph-store.sh | ✅ |
| 2026-01-20 20:15 | SECURITY_FIX | 修复 M-010：validate_sql_input 增强 SQL 注入防护（添加长度检查、修正正则转义、检查控制字符） | scripts/graph-store.sh | ✅ |
| 2026-01-20 20:15 | DATA_INTEGRITY | 修复 M-011：迁移数据完整性验证增强（添加 checksum 验证和索引完整性检查） | scripts/graph-store.sh | ✅ |

## 已解决记录

| 时间 | 类型 | 描述 | 解决方式 |
|---|---|---|
| 2026-01-19 05:38 | IMPLEMENTATION_GAP | LLM Mock 机制未实现 | graph-rag.sh 已调用 common.sh 的 llm_call，支持 LLM_MOCK_* 环境变量 |
| 2026-01-19 05:38 | IMPLEMENTATION_GAP | 性能测试基准数据缺失 | 已补充 tests/fixtures/performance/ 与 baseline.json |
| 2026-01-19 05:38 | TEST_QUALITY | 混合检索骨架测试过多 | tests/hybrid-retrieval.bats 已转为实际断言 |
| 2026-01-19 05:38 | TEST_COVERAGE | 评测基准测试大量 skip | tests/benchmark.bats 已移除 skip 并补全断言 |
| 2026-01-19 | CONSTRAINT_CHANGE | 功能开关默认读取 .devbooks/config.yaml，与设计要求 config/features.yaml 不一致 | 修改 scripts/common.sh 第 405-409 行，统一使用 config/features.yaml，移除降级逻辑 |
| 2026-01-19 | IMPLEMENTATION_GAP | config/features.yaml 缺少新能力开关 | 已补全所有新能力开关（context_compressor, drift_detector, hybrid_retrieval, context_signals, benchmark, performance_regression 等），默认值设为 false |
| 2026-01-19 13:54 | IMPLEMENTATION_GAP | semantic-anomaly.sh 输出格式功能缺失 | 修改功能开关检查逻辑，当使用 --output/--report 参数时自动启用检测，无需额外的 --enable-anomaly-detection 参数 |
| 2026-01-19 | IMPLEMENTATION_GAP | scripts/benchmark.sh 核心功能缺失 | 已实现 --dataset/--baseline/--compare 参数，支持自举和公开数据集评测，输出 JSON 格式报告 |
| 2026-01-19 | IMPLEMENTATION_GAP | scripts/embedding.sh --benchmark 缺失 | 已实现 --benchmark 参数，输出 MRR@10/Recall@10/Precision@10 质量指标 |
| 2026-01-19 | SPEC_DRIFT | long-term-memory 规格冲突 | 已在 design.md 中澄清：AC-007 使用 intent-learner.sh 实现上下文层信号，与 long-term-memory spec（对话长期记忆）是不同功能，可以共存 |

## 偏离分析

### 1. 评测基准脚本缺口

**影响**：AC-009 的评测与回归检测无法执行。

**建议**：扩展 benchmark.sh 支持 --dataset/--baseline/--compare 并输出 MRR@10/P95。

**优先级**：P0

### 2. 长期记忆规格与设计冲突

**影响**：测试依据与实现方向不一致，可能导致错误验收。

**建议**：在 design.md 中明确采用 context signals 或补齐 long-term-memory 实现。

**优先级**：P1

## 下一步行动

1. Test Owner（当前）：完成 Red 基线日志落盘并更新 verification.md 状态
2. Coder（下一步）：补齐功能开关解析、benchmark/semantic-anomaly/embedding CLI
3. Test Owner（阶段 2）：审计 Green 证据并勾选 AC 矩阵
