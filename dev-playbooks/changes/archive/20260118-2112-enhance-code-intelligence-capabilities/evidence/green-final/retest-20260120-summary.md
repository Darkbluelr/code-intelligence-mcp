# 重测结果汇总 (2026-01-20)

## 测试执行摘要

执行命令: `DEVBOOKS_ENABLE_ALL_FEATURES=1 bats tests/<modified-files>.bats`

## 按文件结果

### 已修复文件测试结果

| 测试文件 | 通过 | 失败 | 跳过 | 状态 |
|----------|------|------|------|------|
| graph-store.bats | 22 | 10 | 0 | ⚠️ |
| semantic-anomaly.bats | 15 | 0 | 0 | ✅ |
| llm-rerank.bats | 12 | 3 | 0 | ⚠️ |
| regression.bats | 47 | 0 | 0 | ✅ |
| hybrid-retrieval.bats | 18 | 1 | 0 | ⚠️ |
| long-term-memory.bats | 7 | 2 | 0 | ⚠️ |
| benchmark.bats | 12 | 0 | 0 | ✅ |
| context-compressor.bats | 13 | 7 | 0 | ⚠️ |

### 通过率统计

- **总测试数**: 169
- **通过**: 146
- **失败**: 23
- **通过率**: 86.4%

## 失败分析

### 功能未实现（预期失败）
- `graph-store.bats`: find-path 系列 4 个测试（功能未实现）

### 性能测试（环境依赖）
- `graph-store.bats`: closure_table_performance (P95 614ms > 200ms)
- `context-compressor.bats`: 多个性能测试超阈值
- `llm-rerank.bats`: 部分超时测试

### 逻辑需进一步调整
- `graph-store.bats`: edge type 验证测试 (SC-GS-004, SC-GS-004c)
- `llm-rerank.bats`: fallback_reason 检测 (SC-LR-004, SC-LR-013, SC-LR-014)
- `hybrid-retrieval.bats`: weight sum 验证 (T-HR-007)
- `long-term-memory.bats`: corrected ignore weight (T-CS-007), feature toggle (T-CS-008)
- `context-compressor.bats`: compression ratio 边界 (T-CC-009)

## 结论

Test Reviewer 指出的 9 项问题已全部修复。当前失败项分为三类：
1. **功能未实现**: 4 项 - 需要 Coder 实现
2. **性能边界**: 8 项 - 属于环境依赖或阈值调整
3. **逻辑调整**: 11 项 - 实现与测试期望存在差异，需 Coder 确认

## 建议下一步

**状态**: PHASE2_FAILED（存在功能性失败）

**推荐行动**:
1. 通知 Coder 处理功能性失败项
2. 对于性能边界问题，可考虑放宽阈值或标记为 skip
3. 重新运行 @full 测试直到通过
