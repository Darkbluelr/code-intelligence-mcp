# Red 基线摘要

**建立时间**: 2026-01-14
**变更包**: `augment-upgrade-phase2`
**测试框架**: Bats 1.13.0

---

## 测试执行结果

**总测试数**: 105
**通过**: 105 (含 skip)
**失败**: 0
**跳过**: 50+（因脚本未实现）

---

## 按模块统计

| 模块 | 总测试 | 跳过 | 通过 | 原因 |
|------|--------|------|------|------|
| Cache Manager | 15 | 15 | 0 | `cache-manager.sh` 未实现 |
| Dependency Guard | 17 | 17 | 0 | `dependency-guard.sh` 未实现 |
| Context Layer | 16 | 14 | 2 | `context-layer.sh` 未实现 |
| Federation Lite | 19 | 19 | 0 | `federation-lite.sh` 未实现 |
| Regression | 29 | 1 | 28 | 现有工具正常 |
| Performance | 9 | 6 | 3 | 新脚本未实现 |

---

## 需要 Coder 实现的脚本

1. **cache-manager.sh** - 多级缓存管理
   - 测试: CT-CACHE-001 ~ CT-CACHE-008
   - 关联 AC: AC-001 ~ AC-005, AC-N01, AC-N05, AC-N06

2. **dependency-guard.sh** - 架构守护
   - 测试: CT-GUARD-001 ~ CT-GUARD-011
   - 关联 AC: AC-006 ~ AC-008, AC-012, AC-N03, AC-N04

3. **context-layer.sh** - 上下文层
   - 测试: CT-CTX-001 ~ CT-CTX-009
   - 关联 AC: AC-009, AC-010, AC-014

4. **federation-lite.sh** - 联邦索引
   - 测试: CT-FED-001 ~ CT-FED-011
   - 关联 AC: AC-011

5. **server.ts 更新** - MCP 工具注册
   - 注册 `ci_arch_check`
   - 注册 `ci_federation`
   - 关联 AC: AC-013

---

## 回归测试基线

回归测试全部通过，确认：
- 现有 8 个 MCP 工具正常 (ci_search, ci_call_chain, ci_bug_locate, ci_complexity, ci_graph_rag, ci_index_status, ci_hotspot, ci_boundary)
- TypeScript 编译正常
- 现有脚本语法正确

---

## 性能基线

| 指标 | 当前值 | 目标 |
|------|--------|------|
| hotspot-analyzer 延迟 | ~206ms | < 500ms |
| bug-locator 延迟 | ~2092ms | < 500ms (with cache) |

---

## Green 完成条件

当 Coder 完成实现后，以下条件必须满足：

1. **所有 skip 的测试变为 pass** - 脚本实现后测试应通过
2. **回归测试保持通过** - 不破坏现有功能
3. **性能目标达成**:
   - 缓存命中 P95 < 100ms
   - 完整查询 P95 < 500ms
   - Pre-commit P95 < 2s/5s

---

## 证据文件

- 完整日志: `evidence/red-baseline/test-2026-01-14.log`
- 本摘要: `evidence/red-baseline/summary.md`
