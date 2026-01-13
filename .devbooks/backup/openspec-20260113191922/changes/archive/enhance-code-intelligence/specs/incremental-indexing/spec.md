# Spec Delta: incremental-indexing

> **Change ID**: enhance-code-intelligence
> **Capability**: incremental-indexing
> **Type**: ADDED
> **Owner**: Spec Owner
> **Created**: 2026-01-11

---

## ADDED Requirements

### Requirement: SCIP-Based Incremental Indexing

系统 SHALL 基于 SCIP 索引实现增量更新，单文件变更不需要全量重建索引。

前置条件：`index.scip` 文件存在。

#### Scenario: Incremental update single file

- **GIVEN** `index.scip` 已存在
- **AND** 用户修改了 `src/server.ts` 单个文件
- **WHEN** 执行增量索引
- **THEN** 只更新 `src/server.ts` 相关的索引节点
- **AND** 其他文件的索引保持不变
- **AND** 更新耗时 < 1 秒

Trace: AC-007

#### Scenario: Incremental update multiple files

- **GIVEN** `index.scip` 已存在
- **AND** 用户修改了 3 个文件
- **WHEN** 执行增量索引
- **THEN** 只更新这 3 个文件相关的索引节点
- **AND** 更新耗时与修改文件数成正比

Trace: AC-007

#### Scenario: Full reindex when SCIP missing

- **GIVEN** `index.scip` 不存在
- **WHEN** 执行索引操作
- **THEN** 返回错误提示 "SCIP 索引不存在，请先运行 scip-typescript index"
- **AND** 不执行任何索引操作

Trace: AC-007

---

### Requirement: Change Detection via Git Diff

系统 SHALL 使用 git diff 检测自上次索引以来的文件变更。

#### Scenario: Detect changed files

- **GIVEN** 上次索引时间戳记录在 `.ci-cache/last-index-time`
- **WHEN** 执行变更检测
- **THEN** 返回自该时间戳以来变更的文件列表
- **AND** 列表包含新增、修改、删除的文件

Trace: AC-007

#### Scenario: No changes detected

- **GIVEN** 自上次索引以来无文件变更
- **WHEN** 执行增量索引
- **THEN** 返回 "索引已是最新，无需更新"
- **AND** 不执行任何索引操作

Trace: AC-007

---

### Requirement: Graceful Degradation to Full Index

系统 SHALL 在增量索引失败时降级为全量索引。

#### Scenario: Incremental fails, fallback to full

- **GIVEN** 增量索引过程中发生错误
- **WHEN** 检测到错误
- **THEN** 降级执行全量索引
- **AND** 日志记录 "增量索引失败，降级为全量索引"

Trace: AC-007

---

## Data Examples

### Incremental Index Output

```json
{
  "operation": "incremental",
  "changed_files": [
    {"path": "src/server.ts", "action": "modified"},
    {"path": "scripts/new-script.sh", "action": "added"}
  ],
  "updated_symbols": 15,
  "duration_ms": 450,
  "timestamp": "2026-01-11T10:30:00Z"
}
```

### Full Index Fallback Output

```json
{
  "operation": "full",
  "reason": "incremental_failed",
  "error": "Symbol reference mismatch",
  "total_files": 36,
  "total_symbols": 245,
  "duration_ms": 3200,
  "timestamp": "2026-01-11T10:31:00Z"
}
```

### Performance Expectations

| 场景 | 文件数 | 预期耗时 |
|------|--------|----------|
| 单文件增量 | 1 | < 1s |
| 多文件增量 | 5 | < 2s |
| 全量索引 | 36 | < 5s |
| 大型项目全量 | 1000 | < 60s |
