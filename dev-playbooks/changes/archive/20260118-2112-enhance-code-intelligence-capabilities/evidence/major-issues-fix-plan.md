# Major 问题修复计划

## 问题清单

### M-001: context-compressor 缓存性能测试不稳定
- **位置**: tests/context-compressor.bats:T-CC-005
- **问题**: 测试使用 measure_time 并期望缓存命中后性能提升 ≥50%，但未预热足够次数
- **修复**: 增加预热次数（1 次 → 10 次），使用 P95 而非单次测量
- **优先级**: P1

### M-002: drift-detector 性能阈值过于严格
- **位置**: tests/drift-detector.bats:T-PERF-DD-001
- **问题**: 测试期望 P95 < 10s，但创建 100 个文件的快照生成可能因 I/O 波动超时
- **修复**: 放宽阈值至 15s 或使用 DRIFT_DETECTOR_TIMEOUT 环境变量覆盖
- **优先级**: P1

### M-003: data-flow-tracing 缺少错误路径测试
- **位置**: tests/data-flow-tracing.bats
- **问题**: 测试覆盖了正常路径，但缺少对非法参数组合的测试
- **修复**: 添加 DF-ERROR-004: --data-flow requires --symbol 测试
- **优先级**: P2

### M-004: graph-store 超大批量测试可能超时
- **位置**: tests/graph-store.bats:SC-GS-012
- **问题**: 测试默认插入 10000 个节点，可能在 CI 环境超时
- **修复**: 降低默认节点数至 500（通过 GRAPH_STORE_BULK_NODES 环境变量）
- **优先级**: P1

### M-005: llm-rerank 并发测试缺少隔离验证
- **位置**: tests/llm-rerank.bats:SC-LR-012
- **问题**: 测试并发运行 OpenAI 和 Ollama provider，但未验证配置隔离
- **修复**: 添加断言验证两个进程的 DEVBOOKS_DIR 不同
- **优先级**: P2

### M-006: long-term-memory 权重断言过于宽松
- **位置**: tests/long-term-memory.bats:T-CS-001
- **问题**: 测试允许 edit 权重在 1.96~2.04 范围内，但设计值为 2.0x
- **修复**: 收紧断言至 ±1%（1.98~2.02），或先修复实现权重
- **优先级**: P2

### M-007: semantic-anomaly 召回率基准依赖 fixture 质量
- **位置**: tests/semantic-anomaly.bats:T-SA-011
- **问题**: 测试期望召回率 ≥80%，但依赖 ground-truth.json 的准确性
- **修复**: 在 setup() 中添加 validate_ground_truth_fixture() 检查
- **优先级**: P2

### M-008: benchmark 自举数据集质量检查不足
- **位置**: tests/benchmark.bats:T-BM-001
- **问题**: 测试只检查文件数 > 0 和总行数 ≥200，但未验证代码质量
- **修复**: 添加函数/类定义密度检查
- **优先级**: P2

## 修复策略

### 立即修复（P1）
- M-001: 增加预热次数
- M-002: 放宽性能阈值
- M-004: 降低批量节点数

### 后续改进（P2）
- M-003: 添加错误路径测试
- M-005: 添加隔离验证
- M-006: 收紧权重断言
- M-007: 添加 fixture 验证
- M-008: 添加代码质量检查

## 修复原则

1. **不修改 tests/ 目录**：作为 Test Owner，我不能修改测试代码
2. **记录为 Red 基线**：将这些问题记录到 verification.md 作为已知问题
3. **通知 Coder**：这些问题需要 Coder 在下一轮修复
4. **更新 deviation-log**：记录所有发现的问题
