---
last_referenced_by: optimize-indexing-pipeline-20260117
last_verified: 2026-01-18
health: active
---

# Spec Delta: Indexer Scheduler（索引调度器）

> **Change ID**: `optimize-indexing-pipeline-20260117`
> **Capability**: indexer-scheduler
> **Version**: 1.0.0
> **Status**: Active
> **Created**: 2026-01-18
> **Affects**: `dev-playbooks/specs/incremental-indexing/spec.md`（扩展）

---

## Requirements（需求）

### REQ-IS-001: 增量优先调度策略

系统必须在文件变更时优先选择增量更新路径，仅在增量条件不满足时回退到全量重建。

**约束**：
- 增量条件检查顺序：功能开关 -> tree-sitter 可用性 -> 缓存版本戳一致性 -> 变更文件数阈值
- 默认阈值：10 个文件
- 阈值可通过 `config/features.yaml` 配置

### REQ-IS-002: 防抖窗口聚合

系统必须支持在防抖窗口内聚合多个文件变更，避免高频触发。

**约束**：
- 默认防抖窗口：2 秒
- 可通过环境变量 `DEBOUNCE_SECONDS` 配置
- 窗口内变更聚合为单次批量操作

### REQ-IS-003: 调度决策可观测性

系统必须输出调度决策信息，支持问题诊断。

**约束**：
- 输出决策类型（INCREMENTAL / FULL_REBUILD / SKIP）
- 输出决策原因
- 支持 `--dry-run` 模式输出决策而不实际执行

### REQ-IS-004: CLI 入口向后兼容

既有 CLI 入口必须保持向后兼容。

**约束**：
- `--help`、`--status`、`--install`、`--uninstall` 行为不变
- 默认启动模式（守护进程）行为不变
- 新增入口不影响既有调用方式

### REQ-IS-005: 幂等索引操作

索引操作必须保持幂等性，重复触发不会破坏数据一致性。

**约束**：
- 增量更新后 `graph.db` 节点/边数量不因重复触发而累积或丢失
- SCIP 全量重建后 AST 缓存版本戳必须更新
- 回退路径成功后需同步 `graph.db`（`scip-to-graph.sh parse --incremental`）

### REQ-IS-006: 功能开关支持

系统必须支持通过配置禁用增量路径。

**约束**：
- 配置路径：`config/features.yaml` 中 `features.ast_delta.enabled`
- 环境变量：`CI_AST_DELTA_ENABLED`
- 默认值：`true`（启用增量）

---

## Scenarios（场景）

### SC-IS-001: 单文件变更走增量路径

**Given**：
- `features.ast_delta.enabled: true`
- tree-sitter 可用
- AST 缓存版本戳一致
- 监听到单个文件变更

**When**：
- 调度器处理变更事件

**Then**：
- 决策类型：INCREMENTAL
- 调用 `ast-delta.sh update <file>`
- `graph.db` 中对应节点/边更新
- 输出决策日志

**Trace**: AC-001

### SC-IS-002: 多文件变更走增量路径

**Given**：
- 增量条件满足
- 防抖窗口内累积 5 个文件变更

**When**：
- 防抖窗口结束触发调度

**Then**：
- 决策类型：INCREMENTAL
- 调用 `ast-delta.sh batch` 或内部批处理
- 5 个文件的节点/边更新
- 输出聚合日志

**Trace**: AC-007

### SC-IS-003: 超过阈值回退全量重建

**Given**：
- 变更文件数 > 10（阈值）

**When**：
- 调度器处理变更事件

**Then**：
- 决策类型：FULL_REBUILD
- 执行 SCIP 全量生成 `index.scip`
- 调用 `scip-to-graph.sh parse --incremental` 同步图
- 清理 AST 缓存并更新版本戳
- 输出回退原因

**Trace**: AC-002

### SC-IS-004: tree-sitter 不可用回退全量重建

**Given**：
- tree-sitter npm 包未安装或加载失败

**When**：
- 调度器处理变更事件

**Then**：
- 决策类型：FULL_REBUILD
- 原因：`tree_sitter_unavailable`
- 执行 SCIP 全量路径

**Trace**: AC-002

### SC-IS-005: 缓存版本戳不一致回退全量重建

**Given**：
- AST 缓存版本戳与 `graph.db` 不一致

**When**：
- 调度器处理变更事件

**Then**：
- 决策类型：FULL_REBUILD
- 原因：`cache_version_mismatch`
- 清理旧缓存
- 执行全量路径

**Trace**: AC-002, AC-008

### SC-IS-006: 功能开关禁用增量

**Given**：
- `features.ast_delta.enabled: false` 或 `CI_AST_DELTA_ENABLED=false`

**When**：
- 调度器处理任何变更事件

**Then**：
- 决策类型：FULL_REBUILD
- 原因：`feature_disabled`
- 始终走全量路径

**Trace**: AC-009

### SC-IS-007: dry-run 模式

**Given**：
- 调用 `indexer.sh --dry-run --files file1.ts,file2.ts`

**When**：
- 调度器评估变更

**Then**：
- 输出决策类型和原因
- 不实际执行任何索引操作
- 不修改 `graph.db` 或缓存

**Trace**: AC-001

### SC-IS-008: 既有入口兼容性

**Given**：
- 用户使用既有命令

**When**：
- 执行 `indexer.sh --help` / `--status` / `--install` / `--uninstall`

**Then**：
- 行为与变更前一致
- 输出格式不变
- 退出码语义不变

**Trace**: AC-004

### SC-IS-009: 幂等性验证

**Given**：
- 对同一文件连续触发两次增量更新

**When**：
- 第二次更新完成

**Then**：
- `graph.db` 中该文件的节点/边数量与第一次一致
- 无重复节点或边

**Trace**: AC-006

### SC-IS-010: SCIP 重建后版本戳更新

**Given**：
- 执行 SCIP 全量重建路径

**When**：
- 重建完成

**Then**：
- AST 缓存被清理
- 版本戳更新为当前时间戳
- 后续增量更新能正确检测版本戳一致性

**Trace**: AC-008

---

## API / Schema 变更

### CLI 变更

**现有入口（保持兼容）**：

| 命令 | 行为 | 兼容性 |
|------|------|--------|
| `indexer.sh --help` | 显示帮助 | 不变 |
| `indexer.sh --status` | 显示索引状态 | 不变 |
| `indexer.sh --install` | 安装守护进程 | 不变 |
| `indexer.sh --uninstall` | 卸载守护进程 | 不变 |
| `indexer.sh`（无参数） | 启动守护模式 | 不变 |

**新增入口**：

| 命令 | 行为 | 说明 |
|------|------|------|
| `indexer.sh --dry-run --files <file1,file2>` | 输出调度决策 | 不实际执行 |
| `indexer.sh --once --files <file1,file2>` | 一次性执行索引 | 非守护模式 |

### 配置 Schema 变更

**扩展 `config/features.yaml`**：

```yaml
features:
  ast_delta:
    enabled: true                    # 启用增量路径
    file_threshold: 10               # 超过此数量回退到全量
  indexer:
    debounce_seconds: 2              # 防抖窗口
    offline_proto: true              # 使用 vendored proto（见 scip-parser spec delta）
    allow_proto_download: false      # 是否允许下载更新
```

### 输出格式

**调度决策输出（JSON）**：

```json
{
  "decision": "INCREMENTAL",
  "reason": "all_conditions_met",
  "changed_files": ["src/server.ts"],
  "timestamp": "2026-01-18T12:00:00Z"
}
```

**回退决策输出（JSON）**：

```json
{
  "decision": "FULL_REBUILD",
  "reason": "file_count_exceeds_threshold",
  "changed_files_count": 15,
  "threshold": 10,
  "timestamp": "2026-01-18T12:00:00Z"
}
```

---

## 兼容策略

### 向后兼容

- 所有既有 CLI 入口行为保持不变
- 默认启动模式（守护进程）行为保持不变
- 无 breaking change

### 新功能可选

- 增量路径默认启用，可通过功能开关禁用
- 新增 CLI 入口（`--dry-run`、`--once`）不影响既有调用

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 | 验证命令 |
|---------|------|----------|----------|
| CT-IS-001 | behavior | SC-IS-001, SC-IS-002 | `tests/indexer.bats::test_incremental_path_invoked` |
| CT-IS-002 | behavior | SC-IS-003, SC-IS-004, SC-IS-005 | `tests/indexer.bats::test_fallback_to_full_rebuild` |
| CT-IS-003 | behavior | SC-IS-007 | `tests/indexer.bats::test_dry_run_mode` |
| CT-IS-004 | behavior | SC-IS-008 | `tests/indexer.bats::test_cli_compatibility` |
| CT-IS-005 | behavior | SC-IS-009 | `tests/indexer.bats::test_idempotency` |
| CT-IS-006 | behavior | SC-IS-006 | `tests/indexer.bats::test_feature_toggle` |
| CT-IS-007 | behavior | SC-IS-002 | `tests/indexer.bats::test_debounce_aggregation` |
| CT-IS-008 | behavior | SC-IS-010 | `tests/indexer.bats::test_version_stamp_consistency` |

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-IS-001 | SC-IS-001, SC-IS-003, SC-IS-004, SC-IS-005 | AC-001, AC-002 |
| REQ-IS-002 | SC-IS-002 | AC-007 |
| REQ-IS-003 | SC-IS-007 | AC-001 |
| REQ-IS-004 | SC-IS-008 | AC-004 |
| REQ-IS-005 | SC-IS-009, SC-IS-010 | AC-006, AC-008 |
| REQ-IS-006 | SC-IS-006 | AC-009 |
