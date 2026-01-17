# 验收验证与追溯文档

> **Change ID**: `augment-parity`
> **Version**: 1.0.0
> **Status**: 🟢 Archived (归档于 2026-01-15)
> **Test Owner**: Test Owner
> **Created**: 2026-01-15
> **Last Updated**: 2026-01-15

---

## 1. 测试分层策略

| 类型 | 数量 | 覆盖场景 | 预期执行时间 |
|------|------|----------|--------------|
| 单元测试 | 45 | AC-001 ~ AC-008 | < 30s |
| 集成测试 | 8 | 守护进程通信、SCIP 解析 | < 60s |
| 性能测试 | 2 | AC-003, AC-N01 | < 120s |
| 回归测试 | 1 | AC-007 | < 60s |

## 2. 测试环境要求

| 测试类型 | 运行环境 | 依赖 |
|----------|----------|------|
| 单元测试 | Bash + Bats | sqlite3, jq |
| 集成测试 | Bash + Bats | sqlite3, jq, nc (netcat) |
| 性能测试 | Bash + Bats | sqlite3, jq, time |

---

## 3. AC 追溯矩阵

### 3.1 功能验收标准

| AC ID | 验收项 | 测试文件 | 测试用例 | 状态 |
|-------|--------|----------|----------|------|
| AC-001 | SQLite 图存储 4 种边类型 CRUD | tests/graph-store.bats | SC-GS-001 ~ SC-GS-011 | 🟢 Green |
| AC-002 | SCIP → 图数据转换 | tests/scip-to-graph.bats | SC-SP-001 ~ SC-SP-010 | 🟢 Green |
| AC-003 | 守护进程 P95 < 500ms | tests/daemon.bats | SC-DM-001 ~ SC-DM-012 | 🟢 Green |
| AC-004 | LLM 重排序开关 | tests/llm-rerank.bats | SC-LR-001 ~ SC-LR-011 | 🟢 Green |
| AC-005 | 孤儿模块检测 | tests/dependency-guard.bats | SC-OD-001 ~ SC-OD-010 | 🟢 Green |
| AC-006 | 自动模式发现 >= 3 种 | tests/pattern-learner.bats | SC-PD-001 ~ SC-PD-011 | 🟢 Green |
| AC-007 | 现有测试无回归 | tests/regression.bats | 全量回归 | 🟢 Green |
| AC-008 | 无 CKB 时正常工作 | tests/mcp-contract.bats | CT-CKB-001 ~ CT-CKB-005 | 🟢 Green |

### 3.2 非功能验收标准

| AC ID | 验收项 | 测试文件 | 阈值 | 状态 |
|-------|--------|----------|------|------|
| AC-N01 | P95 延迟 | tests/daemon.bats | < 600ms | 🟢 Green |
| AC-N02 | 冷启动延迟 | tests/daemon.bats | 记录 | 🟢 Green |
| AC-N03 | 图数据库大小 | tests/graph-store.bats | < 10MB | 🟢 Green |
| AC-N04 | SCIP 解析覆盖率 | tests/scip-to-graph.bats | 100% TS | 🟢 Green |

---

## 4. 契约测试追溯

| Test ID | 类型 | 覆盖 | 验证内容 | 测试文件 |
|---------|------|------|----------|----------|
| CT-GS-001 | schema | REQ-GS-001 | 图数据库 Schema | graph-store.bats |
| CT-GS-002 | behavior | REQ-GS-004 | 边类型约束 | graph-store.bats |
| CT-GS-003 | behavior | REQ-GS-006 | 批量操作事务性 | graph-store.bats |
| CT-SP-001 | behavior | REQ-SP-003 | symbol_roles 映射 | scip-to-graph.bats |
| CT-SP-002 | behavior | REQ-SP-006 | 降级策略 | scip-to-graph.bats |
| CT-DM-001 | behavior | REQ-DM-002 | PID 文件锁 | daemon.bats |
| CT-DM-002 | behavior | REQ-DM-004 | 请求队列限制 | daemon.bats |
| CT-DM-003 | behavior | REQ-DM-005 | 协议格式 | daemon.bats |
| CT-DM-004 | performance | AC-003 | P95 延迟 | daemon.bats |
| CT-LR-001 | behavior | REQ-LR-001 | 功能开关 | llm-rerank.bats |
| CT-LR-002 | behavior | REQ-LR-006 | 降级策略 | llm-rerank.bats |
| CT-LR-003 | schema | REQ-LR-008 | 结果格式 | llm-rerank.bats |
| CT-OD-001 | behavior | REQ-OD-001 | 孤儿定义 | dependency-guard.bats |
| CT-OD-002 | behavior | REQ-OD-003 | 排除模式 | dependency-guard.bats |
| CT-PD-001 | behavior | REQ-PD-004 | 高频模式阈值 | pattern-learner.bats |
| CT-PD-002 | behavior | REQ-PD-005 | 模式持久化 | pattern-learner.bats |
| CT-BC-001 | regression | AC-007 | 无回归 | regression.bats |
| CT-BC-002 | behavior | AC-008 | 无 CKB 功能 | mcp-contract.bats |

---

## 5. 测试文件清单

| 文件 | 状态 | 测试数 | 覆盖 AC |
|------|------|--------|---------|
| tests/graph-store.bats | 🆕 新增 | 11 | AC-001 |
| tests/scip-to-graph.bats | 🆕 新增 | 10 | AC-002 |
| tests/daemon.bats | 🆕 新增 | 12 | AC-003, AC-N01, AC-N02 |
| tests/llm-rerank.bats | 🆕 新增 | 11 | AC-004 |
| tests/dependency-guard.bats | 📝 修改 | +10 | AC-005 |
| tests/pattern-learner.bats | 📝 修改 | +11 | AC-006 |
| tests/regression.bats | 📝 修改 | +1 | AC-007 |
| tests/mcp-contract.bats | 📝 修改 | +5 | AC-008 |

---

## 6. 测试隔离要求

- [x] 每个测试独立运行，不依赖执行顺序
- [x] 使用 `setup()` / `teardown()` 清理临时文件
- [x] 测试数据库使用临时路径 `$TEST_TEMP_DIR`
- [x] 禁止使用共享可变状态
- [x] Mock LLM 调用使用 `LLM_MOCK_RESPONSE` 环境变量

---

## 7. Red 基线证据

**证据路径**: `dev-playbooks/changes/augment-parity/evidence/red-baseline/`

| 证据文件 | 说明 | 状态 |
|----------|------|------|
| summary.md | 失败摘要 | ✅ 已生成 |

---

## 7b. Green 最终证据

**证据路径**: `dev-playbooks/changes/augment-parity/evidence/green-final/`

| 证据文件 | 说明 | 状态 |
|----------|------|------|
| test-run-20260115.log | 测试运行完整日志 | ✅ 已生成 |
| performance-report.md | 性能测试报告 | ✅ 已生成 |

---

## 8. DoD 检查清单

### 8.1 行为闸门

- [x] graph-store.bats 全部通过
- [x] scip-to-graph.bats 全部通过
- [x] daemon.bats 全部通过
- [x] llm-rerank.bats 全部通过
- [x] dependency-guard.bats 孤儿检测测试通过
- [x] pattern-learner.bats 自动发现测试通过

### 8.2 性能闸门

- [x] P95 延迟 < 600ms（100 次热请求）
- [x] 图数据库文件 < 10MB

### 8.3 回归闸门

- [x] `npm test` 全部通过
- [x] 无 CKB 时 `ci_graph_rag` 正常工作

### 8.4 证据闸门

- [x] Red 基线日志已记录
- [x] Green 最终日志已记录
- [x] 性能报告已生成
