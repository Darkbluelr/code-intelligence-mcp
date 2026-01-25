# 规格：M1 AST Delta 增量索引

> **模块 ID**: `ast-delta`
> **Change ID**: `achieve-augment-full-parity`
> **Date**: 2026-01-16
> **Status**: Draft

---

## Requirements（需求）

### REQ-AD-001: 增量 AST 解析

系统必须支持对单个文件的增量 AST 解析，而非每次变更都进行全量重建。

**约束**：
- 使用 tree-sitter npm 包（`tree-sitter` + `tree-sitter-typescript`）
- 解析目标：TypeScript 文件
- 必须支持降级路径（tree-sitter → SCIP → regex）

### REQ-AD-002: AST 缓存管理

系统必须维护 AST 缓存以支持增量更新。

**约束**：
- 缓存位置：`.devbooks/ast-cache/`
- 缓存大小上限：50MB
- 缓存 TTL：30 天
- 必须使用原子写入策略

### REQ-AD-003: 索引协调协议

系统必须实现 tree-sitter 增量更新与 SCIP 全量重建之间的协调机制。

**约束**：
- 版本戳一致性检查
- SCIP 重建后自动清理 AST 缓存
- 变更文件数阈值：10 个

### REQ-AD-004: 性能要求

单文件增量更新必须满足性能目标。

**约束**：
- P95 延迟 < 100ms（±20%，上限 120ms）
- 测试条件：100-1000 行 TypeScript 文件

---

## Scenarios（场景）

### SC-AD-001: 单文件增量更新

**Given**：
- tree-sitter 可用
- AST 缓存存在且版本戳一致
- 用户修改了单个 TypeScript 文件

**When**：
- 调用 `ast-delta.sh update <file-path>`

**Then**：
- 系统解析新 AST
- 计算与缓存 AST 的差异（added/removed/modified）
- 更新 graph.db 中的对应节点和边
- 更新 AST 缓存
- 返回 Delta 摘要

**验证**：`tests/ast-delta.bats::test_single_file_update`

### SC-AD-002: 批量增量更新

**Given**：
- tree-sitter 可用
- AST 缓存存在
- 变更文件数 ≤ 10

**When**：
- 调用 `ast-delta.sh batch --since HEAD~1`

**Then**：
- 系统检测所有变更文件
- 对每个文件执行增量更新
- 返回批量 Delta 摘要

**验证**：`tests/ast-delta.bats::test_batch_update`

### SC-AD-003: 缓存失效触发全量重建

**Given**：
- AST 缓存版本戳与 graph.db 不一致
- 或 AST 缓存不存在

**When**：
- 调用 `ast-delta.sh update <file-path>`

**Then**：
- 系统检测到缓存失效
- 执行 FULL_REBUILD 路径
- 清理旧 AST 缓存
- 调用 SCIP 全量重建
- 更新版本戳

**验证**：`tests/ast-delta.bats::test_cache_invalidation`

### SC-AD-004: tree-sitter 不可用降级

**Given**：
- tree-sitter npm 包未安装或加载失败

**When**：
- 调用 `ast-delta.sh update <file-path>`

**Then**：
- 系统检测到 tree-sitter 不可用
- 执行 FALLBACK 路径
- 降级到 SCIP 解析（如可用）
- 或降级到 regex 匹配（最低保障）
- 输出降级警告

**验证**：`tests/ast-delta.bats::test_fallback_to_scip`

### SC-AD-005: 大规模变更触发全量重建

**Given**：
- 变更文件数 > 10

**When**：
- 调用 `ast-delta.sh batch --since <ref>`

**Then**：
- 系统检测到变更规模过大
- 执行 FULL_REBUILD 路径
- 输出提示信息

**验证**：`tests/ast-delta.bats::test_large_change_triggers_rebuild`

### SC-AD-006: 性能验证

**Given**：
- tree-sitter 可用
- 测试文件：src/server.ts（约 500 行）

**When**：
- 执行 50 次 AST 解析（排除首次预热）

**Then**：
- P95 延迟 ≤ 120ms
- 输出性能报告

**验证**：`tests/ast-delta.bats::test_performance`

### SC-AD-007: 原子写入保护

**Given**：
- 正在写入 AST 缓存时进程被终止

**When**：
- 下次调用 ast-delta.sh

**Then**：
- 系统清理孤儿临时文件（.tmp.* 文件超过 5 分钟）
- 不会读取到损坏的缓存文件
- 正常执行更新流程

**验证**：`tests/ast-delta.bats::test_atomic_write`

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios |
|-------------|-----------|
| REQ-AD-001 | SC-AD-001, SC-AD-002, SC-AD-004 |
| REQ-AD-002 | SC-AD-003, SC-AD-007 |
| REQ-AD-003 | SC-AD-003, SC-AD-005 |
| REQ-AD-004 | SC-AD-006 |

| Scenario | Test ID |
|----------|---------|
| SC-AD-001 | `tests/ast-delta.bats::test_single_file_update` |
| SC-AD-002 | `tests/ast-delta.bats::test_batch_update` |
| SC-AD-003 | `tests/ast-delta.bats::test_cache_invalidation` |
| SC-AD-004 | `tests/ast-delta.bats::test_fallback_to_scip` |
| SC-AD-005 | `tests/ast-delta.bats::test_large_change_triggers_rebuild` |
| SC-AD-006 | `tests/ast-delta.bats::test_performance` |
| SC-AD-007 | `tests/ast-delta.bats::test_atomic_write` |
