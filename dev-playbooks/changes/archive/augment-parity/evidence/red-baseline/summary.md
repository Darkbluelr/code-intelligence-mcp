# Red 基线证据摘要

> **Change ID**: `augment-parity`
> **执行时间**: 2026-01-15
> **执行者**: Test Owner (Claude)

---

## 测试执行结果

### AC-001: SQLite 图存储 (graph-store.bats)
- **测试数**: 13
- **通过**: 0
- **跳过**: 13 (脚本未实现)
- **失败**: 0
- **状态**: ✅ Red 基线符合预期

### AC-002: SCIP 解析 (scip-to-graph.bats)
- **测试数**: 11
- **通过**: 0
- **跳过**: 11 (脚本未实现)
- **失败**: 0
- **状态**: ✅ Red 基线符合预期

### AC-003: 守护进程 (daemon.bats)
- **测试数**: 13
- **通过**: 0
- **跳过**: 13 (脚本未实现)
- **失败**: 0
- **状态**: ✅ Red 基线符合预期

### AC-004: LLM 重排序 (llm-rerank.bats)
- **测试数**: 12
- **通过**: 0
- **跳过**: 12 (功能未实现)
- **失败**: 0
- **状态**: ✅ Red 基线符合预期

### AC-005: 孤儿检测 (dependency-guard.bats SC-OD-*)
- **测试数**: 10
- **通过**: 0
- **跳过**: 10 (--orphan-check 未实现)
- **失败**: 0
- **状态**: ✅ Red 基线符合预期

### AC-006: 模式发现 (pattern-learner.bats SC-PD-*)
- **测试数**: 8
- **通过**: 0
- **跳过**: 8 (--auto-discover 未实现)
- **失败**: 0
- **状态**: ✅ Red 基线符合预期

### AC-007: 回归测试 (regression.bats)
- **状态**: 现有测试继续通过

### AC-008: 无 CKB 降级 (mcp-contract.bats CT-CKB-*)
- **测试数**: 5
- **通过**: 5
- **跳过**: 0
- **失败**: 0
- **状态**: ✅ 现有功能正常工作

---

## 总结

| AC | 测试文件 | 测试数 | 状态 |
|----|----------|--------|------|
| AC-001 | graph-store.bats | 13 | Red (全部跳过) |
| AC-002 | scip-to-graph.bats | 11 | Red (全部跳过) |
| AC-003 | daemon.bats | 13 | Red (全部跳过) |
| AC-004 | llm-rerank.bats | 12 | Red (全部跳过) |
| AC-005 | dependency-guard.bats | 10 | Red (全部跳过) |
| AC-006 | pattern-learner.bats | 8 | Red (全部跳过) |
| AC-007 | regression.bats | - | Green (现有功能) |
| AC-008 | mcp-contract.bats | 5 | Green (现有功能) |

**Red 基线建立成功**：所有新功能测试正确跳过，等待 Coder 实现。

---

## 证据文件

- `core-tests.txt` - AC-001 ~ AC-004 测试输出
- `orphan-tests.txt` - AC-005 孤儿检测测试输出
- `pattern-tests.txt` - AC-006 模式发现测试输出
- `ckb-tests.txt` - AC-008 无 CKB 降级测试输出
