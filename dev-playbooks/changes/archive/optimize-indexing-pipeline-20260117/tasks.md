# Implementation Plan: Indexing Pipeline Optimization

> **Change ID**: `optimize-indexing-pipeline-20260117`
> **Version**: 1.0.0
> **Status**: Ready for Implementation
> **Created**: 2026-01-18
> **Maintainer**: Planner
> **Input Materials**: `proposal.md`, `design.md`, `specs/indexer-scheduler/spec.md`, `specs/scip-parser-offline/spec.md`, `specs/ci-index-status-semantic/spec.md`

---

## Mode Selection

**Current Mode**: `主线计划模式`

---

## 主线计划区 (Main Plan Area)

### MP1: Vendored Proto 基础设施 (AC-003)

**目的（Why）**：为 SCIP 解析器提供离线可用的 proto 定义，消除运行时网络依赖。

**交付物（Deliverables）**：
- `vendored/scip.proto` 固定版本文件
- `scripts/vendor-proto.sh` vendoring 辅助脚本

**影响范围（Files/Modules）**：
- 新增：`vendored/scip.proto`
- 新增：`scripts/vendor-proto.sh`

**依赖（Dependencies）**：无（独立任务包）

**风险（Risks）**：Proto 版本与 scip-typescript 不兼容

- [x] MP1.1 创建 `vendored/` 目录并添加固定版本 `scip.proto`（包含版本注释）(AC-003)
- [x] MP1.2 创建 `scripts/vendor-proto.sh` 支持 `--upgrade` 和 `--check` 命令 (AC-003)

**验收标准（Acceptance Criteria）**：
- 类型：契约测试（`tests/scip-to-graph.bats::test_vendored_proto`）
- `vendored/scip.proto` 存在且包含版本标注
- `scripts/vendor-proto.sh --check` 返回版本兼容状态

---

### MP2: SCIP 解析器离线化改造 (AC-003)

**目的（Why）**：修改 `scip-to-graph.sh` 的 proto 发现策略，实现"本地优先"。

**交付物（Deliverables）**：
- 修改后的 `scripts/scip-to-graph.sh`（新增 `ensure_scip_proto()` 离线策略）
- 输出中新增 `proto_source` 和 `proto_version` 字段

**影响范围（Files/Modules）**：
- 修改：`scripts/scip-to-graph.sh`
- 读取：`config/features.yaml`

**依赖（Dependencies）**：MP1（需要 vendored proto）

**风险（Risks）**：现有用户依赖隐式下载行为

- [x] MP2.1 实现 `ensure_scip_proto()` 函数，按优先级发现 proto：`$SCIP_PROTO_PATH` -> `vendored/scip.proto` -> `$CACHE_DIR/scip.proto` -> 下载（若允许）(AC-003)
- [x] MP2.2 读取 `config/features.yaml` 中 `features.indexer.offline_proto` 和 `allow_proto_download` 配置 (AC-003)
- [x] MP2.3 在解析输出中添加 `proto_source`（VENDORED/CUSTOM/CACHED/DOWNLOADED）和 `proto_version` 字段 (AC-003)
- [x] MP2.4 实现明确错误信息：proto 不存在时输出路径和修复建议，不静默失败 (AC-003)

**验收标准（Acceptance Criteria）**：
- 类型：行为测试（`tests/scip-to-graph.bats::test_offline_proto_resolution`）
- 离线环境下 `scip-to-graph.sh parse` 可成功执行
- 输出 JSON 包含 `proto_source` 字段

---

### MP3: 配置 Schema 扩展 (AC-009)

**目的（Why）**：为索引调度器和 proto 发现提供统一的配置入口。

**交付物（Deliverables）**：
- 扩展后的 `config/features.yaml`

**影响范围（Files/Modules）**：
- 修改：`config/features.yaml`

**依赖（Dependencies）**：无（独立任务包，但建议与 MP1 并行）

**风险（Risks）**：配置项命名需要与现有配置风格一致

- [x] MP3.1 在 `config/features.yaml` 添加 `features.ast_delta.enabled` 和 `features.ast_delta.file_threshold` 配置项 (AC-009)
- [x] MP3.2 在 `config/features.yaml` 添加 `features.indexer.debounce_seconds`、`offline_proto`、`allow_proto_download` 配置项 (AC-003, AC-007)
- [x] MP3.3 添加配置项注释说明默认值和用途 (AC-009)

**验收标准（Acceptance Criteria）**：
- 类型：静态检查（YAML 语法）+ 行为测试
- 配置文件可正确解析
- 脚本可读取新增配置项

---

### MP4: Indexer 调度逻辑实现 (AC-001, AC-002, AC-006, AC-007, AC-008)

**目的（Why）**：实现"增量优先 + 可靠回退"的索引调度策略。

**交付物（Deliverables）**：
- 修改后的 `scripts/indexer.sh`（新增 `dispatch_index()` 调度函数）
- 防抖窗口聚合逻辑
- 版本戳一致性检查

**影响范围（Files/Modules）**：
- 修改：`scripts/indexer.sh`
- 调用：`scripts/ast-delta.sh`
- 调用：`scripts/scip-to-graph.sh`
- 读取：`config/features.yaml`

**依赖（Dependencies）**：MP2、MP3

**风险（Risks）**：调度逻辑复杂度、并发写入竞争

- [x] MP4.1 实现配置读取：从 `features.yaml` 和环境变量读取 `ast_delta.enabled`、`file_threshold`、`debounce_seconds` (AC-009)
- [x] MP4.2 实现增量条件检查函数：功能开关 -> tree-sitter 可用性 -> 缓存版本戳一致性 -> 变更文件数阈值 (AC-001)
- [x] MP4.3 实现 `dispatch_index()` 调度函数，根据条件选择 INCREMENTAL 或 FULL_REBUILD 路径 (AC-001, AC-002)
- [x] MP4.4 实现防抖窗口聚合：在 `DEBOUNCE_SECONDS` 窗口内聚合变更文件列表，批量触发索引 (AC-007)
- [x] MP4.5 实现增量路径：调用 `ast-delta.sh update <file>` 或 `ast-delta.sh batch <files>` (AC-001)
- [x] MP4.6 实现回退路径：生成 `index.scip` 后调用 `scip-to-graph.sh parse --incremental` 同步图数据 (AC-002)
- [x] MP4.7 实现版本戳更新：SCIP 全量重建后清理 AST 缓存并更新版本戳 (AC-008)
- [x] MP4.8 实现幂等性保证：重复触发不累积或丢失节点/边 (AC-006)
- [x] MP4.9 输出调度决策 JSON（decision, reason, changed_files, timestamp）(AC-001)

**验收标准（Acceptance Criteria）**：
- 类型：行为测试（`tests/indexer.bats::test_incremental_path_invoked`、`test_fallback_to_full_rebuild`、`test_debounce_aggregation`、`test_version_stamp_consistency`、`test_idempotency`、`test_feature_toggle`）
- 单文件变更走增量路径
- 超阈值变更回退全量
- 防抖窗口聚合生效

---

### MP5: Indexer CLI 扩展 (AC-004)

**目的（Why）**：新增 `--dry-run` 和 `--once` 入口，保持既有入口兼容。

**交付物（Deliverables）**：
- `scripts/indexer.sh` 新增 CLI 参数

**影响范围（Files/Modules）**：
- 修改：`scripts/indexer.sh`

**依赖（Dependencies）**：MP4

**风险（Risks）**：参数解析复杂度

- [x] MP5.1 新增 `--dry-run --files <file1,file2>` 参数：输出调度决策但不实际执行 (AC-001, AC-004)
- [x] MP5.2 新增 `--once --files <file1,file2>` 参数：一次性执行索引（非守护模式）(AC-004)
- [x] MP5.3 验证既有入口 `--help`、`--status`、`--install`、`--uninstall` 行为不变 (AC-004)
- [x] MP5.4 更新 `--help` 输出，包含新增参数说明 (AC-004)

**验收标准（Acceptance Criteria）**：
- 类型：行为测试（`tests/indexer.bats::test_cli_compatibility`、`test_dry_run_mode`）
- `--dry-run` 输出决策但不修改数据
- 既有 CLI 入口行为保持不变

---

### MP6: ci_index_status 语义对齐 (AC-005)

**目的（Why）**：将 `ci_index_status` MCP 工具的调用路由从 `indexer.sh` 改为 `embedding.sh`，明确其 Embedding 索引管理语义。

**交付物（Deliverables）**：
- 修改后的 `src/server.ts`

**影响范围（Files/Modules）**：
- 修改：`src/server.ts`（`handleToolCall()` 中 `ci_index_status` 分支）

**依赖（Dependencies）**：无（独立任务包，可与 MP1-MP5 并行）

**风险（Risks）**：依赖旧行为的用户可能受影响

- [x] MP6.1 修改 `src/server.ts` 中 `ci_index_status` 的调用路由：`status` -> `embedding.sh status`；`build` -> `embedding.sh build`；`clear` -> `embedding.sh clean` (AC-005)
- [x] MP6.2 实现参数映射：`action === "clear"` 时映射为 `clean` (AC-005)
- [x] MP6.3 实现默认 action：未指定时默认执行 `status` (AC-005)
- [x] MP6.4 实现参数校验：无效 action 返回错误信息 (AC-005)

**验收标准（Acceptance Criteria）**：
- 类型：行为测试（`tests/server.bats::test_ci_index_status_semantic`、`test_ci_index_status_status`、`test_ci_index_status_build`、`test_ci_index_status_clear`、`test_ci_index_status_validation`）
- TypeScript 构建通过
- `ci_index_status` 调用 `embedding.sh` 而非 `indexer.sh`

---

### MP7: 并发安全验证 (AC-010)

**目的（Why）**：验证多实例并发写入时 `graph.db` 的稳定性。

**交付物（Deliverables）**：
- 并发测试脚本或测试用例
- 并发测试日志

**影响范围（Files/Modules）**：
- 验证：`scripts/indexer.sh`、`scripts/graph-store.sh`

**依赖（Dependencies）**：MP4

**风险（Risks）**：SQLite 锁竞争导致测试不稳定

- [x] MP7.1 验证 SQLite WAL 模式配置正确（`PRAGMA journal_mode=WAL`）(AC-010)
- [x] MP7.2 编写并发写入测试场景：多个索引操作同时触发 (AC-010)
- [x] MP7.3 验证无 "database is locked" 错误或数据损坏 (AC-010)

**验收标准（Acceptance Criteria）**：
- 类型：工具证据 + 人签核
- 并发测试日志无错误
- `graph.db` 数据完整

---

### MP8: 文档更新

**目的（Why）**：更新用户文档，反映本次变更的功能和语义变化。

**交付物（Deliverables）**：
- 更新后的 `README.md`
- 更新后的 `docs/使用说明书.md`（如存在）

**影响范围（Files/Modules）**：
- 修改：`README.md`

**依赖（Dependencies）**：MP6（语义对齐完成后）

**风险（Risks）**：文档与实现不一致

- [x] MP8.1 更新 `README.md` 中 `ci_index_status` 工具说明：明确其管理 Embedding 索引 (AC-005)
- [x] MP8.2 添加 vendored proto 使用说明和离线模式说明 (AC-003)
- [x] MP8.3 添加功能开关配置说明（`features.ast_delta.enabled`、`CI_AST_DELTA_ENABLED`）(AC-009)

**验收标准（Acceptance Criteria）**：
- 类型：人工检查
- 文档与实现一致
- 关键配置项有说明

---

## 临时计划区 (Temporary Plan Area)

> 用于计划外高优任务。当前为空。

---

## 断点区 (Context Switch Breakpoint Area)

> 用于记录上下文切换时的断点信息。

**Last Checkpoint**: N/A
**Active Task**: N/A
**Blocked By**: N/A
**Resume Notes**: N/A

---

## 计划细化区

### Scope & Non-goals

**In Scope**:
- `scripts/indexer.sh` 增量调度逻辑
- `scripts/scip-to-graph.sh` 离线 proto 支持
- `src/server.ts` 中 `ci_index_status` 语义对齐
- `vendored/scip.proto` 添加
- `config/features.yaml` 配置扩展

**Out of Scope (Non-goals)**:
- 引入新的向量数据库或 `sqlite-vec`
- 修改 `scripts/embedding.sh` 存储模型
- 修改 `scripts/graph-store.sh` Schema
- 引入 LSP、容器沙盒、联邦学习等能力

### Architecture Delta

**新增组件**:
- `vendored/scip.proto`：固定版本的 SCIP proto 定义
- `scripts/vendor-proto.sh`：Proto vendoring 辅助脚本

**修改组件**:
- `scripts/indexer.sh`：新增 `dispatch_index()` 调度组件
- `scripts/scip-to-graph.sh`：修改 `ensure_scip_proto()` 为"本地优先"策略
- `src/server.ts`：`ci_index_status` 调用路由变更

**新增依赖边**:
- `indexer.sh` -> `ast-delta.sh`（增量路径调用）
- `indexer.sh` -> `scip-to-graph.sh`（回退路径同步）
- `scip-to-graph.sh` -> `vendored/scip.proto`

**删除依赖边**:
- `ci_index_status` -> `indexer.sh`（语义对齐）

**新增依赖边**:
- `ci_index_status` -> `embedding.sh`

### Data Contracts

**配置 Schema**:
```yaml
features:
  ast_delta:
    enabled: true           # 启用增量路径
    file_threshold: 10      # 超过此数量回退到全量
  indexer:
    debounce_seconds: 2     # 防抖窗口
    offline_proto: true     # 使用 vendored proto
    allow_proto_download: false  # 是否允许下载
```

**调度决策输出**:
```json
{
  "decision": "INCREMENTAL | FULL_REBUILD | SKIP",
  "reason": "string",
  "changed_files": ["string"],
  "timestamp": "ISO8601"
}
```

**proto_source 枚举**:
- `VENDORED`：使用 vendored/scip.proto
- `CUSTOM`：使用 SCIP_PROTO_PATH 指定路径
- `CACHED`：使用缓存的下载 proto
- `DOWNLOADED`：本次下载的 proto

### Milestones

| Phase | 任务包 | AC 覆盖 | 预计工作量 |
|-------|--------|---------|------------|
| M1 | MP1, MP3 | AC-003, AC-009 | 0.5 天 |
| M2 | MP2 | AC-003 | 0.5 天 |
| M3 | MP4 | AC-001, AC-002, AC-006, AC-007, AC-008, AC-009 | 1.5 天 |
| M4 | MP5 | AC-004 | 0.5 天 |
| M5 | MP6 | AC-005 | 0.5 天 |
| M6 | MP7, MP8 | AC-010 | 0.5 天 |

**总计**：约 4 天

### Work Breakdown

**可并行任务**:
- MP1 (Vendored Proto) 与 MP3 (配置扩展) 与 MP6 (语义对齐) 可并行
- MP2 (离线化改造) 依赖 MP1
- MP4 (调度逻辑) 依赖 MP2、MP3
- MP5 (CLI 扩展) 依赖 MP4
- MP7 (并发验证) 依赖 MP4
- MP8 (文档) 依赖 MP6

**依赖关系图**:
```
MP1 ──────┐
          │
MP3 ──────┼──▶ MP4 ──▶ MP5
          │      │
MP2 ──────┘      └──▶ MP7

MP6 ──────────────────▶ MP8
```

**PR 切分建议**:
1. PR#1: MP1 + MP3（基础设施）
2. PR#2: MP2（离线化改造）
3. PR#3: MP4 + MP5（调度逻辑 + CLI）
4. PR#4: MP6 + MP8（语义对齐 + 文档）
5. PR#5: MP7（并发验证 - 可选单独 PR）

### Deprecation & Cleanup

**弃用计划**:
- `scip.proto` 在线下载：默认禁用，保留 `allow_proto_download: true` 作为后门
- 计划在 v1.0 稳定后评估移除下载后门

**回滚条件**:
- 功能开关 `features.ast_delta.enabled: false` 可禁用增量路径
- Proto 回滚 `features.indexer.allow_proto_download: true` 可恢复下载行为

### Dependency Policy

**外部依赖**:
- `scip.proto`：固定版本 vendoring，升级需显式流程
- `scip-typescript`：确保 proto 版本与索引器版本兼容

**升级策略**:
- 运行 `scripts/vendor-proto.sh --upgrade` 更新 proto
- 更新后运行 `scripts/vendor-proto.sh --check` 验证兼容性
- 提交更新到版本控制

### Quality Gates

| 闸门 | 验证命令 | 覆盖 |
|------|----------|------|
| ShellCheck | `npm run lint` | 所有 `.sh` 脚本 |
| TypeScript Build | `npm run build` | `src/server.ts` |
| Unit Tests | `npm test` | 全部 AC |
| CLI 兼容性 | `./scripts/indexer.sh --help` | AC-004 |

### Guardrail Conflicts

**无代理指标冲突**：本计划未触发代理指标驱动的风险信号。

**结构完整性评估**：
- MP4 调度逻辑预计约 150 行改动，符合 ≤200 行约束
- MP6 语义对齐预计约 30 行改动，符合约束

### Observability

**日志落点**:
- 调度决策输出到 stdout（JSON 格式）
- 错误信息输出到 stderr

**关键指标**:
- `index.decision`：按决策类型统计
- `index.duration_ms`：索引操作耗时

### Rollout & Rollback

**灰度策略**:
- 通过功能开关 `features.ast_delta.enabled` 控制
- 默认启用，可随时禁用

**回滚策略**:
- 设置 `features.ast_delta.enabled: false` 禁用增量路径
- 设置 `features.indexer.allow_proto_download: true` 恢复下载
- 完整回滚：revert 本变更包的所有代码改动

### Risks & Edge Cases

| 风险 | 影响 | 缓解策略 |
|------|------|----------|
| tree-sitter 不可用 | 始终回退全量 | 加载失败检测 + 日志 |
| AST 缓存损坏 | 版本戳不一致 | 自动清理 + 全量重建 |
| graph.db 锁竞争 | 写入超时 | WAL 模式 + 重试 |
| vendored proto 不兼容 | 解析失败 | 版本检查 + 升级建议 |

**边界条件**:
- 变更文件数恰好等于阈值（10）：走增量路径
- 防抖窗口内无变更：跳过索引
- 首次运行无缓存：版本戳初始化

### Algorithm Spec: 调度决策逻辑

**Inputs**:
- `changed_files[]`：变更文件路径列表
- `config`：features.yaml 配置对象
- `cache_version`：AST 缓存版本戳
- `db_version`：graph.db 版本戳

**Outputs**:
- `decision`：INCREMENTAL | FULL_REBUILD | SKIP
- `reason`：决策原因

**Invariants**:
- 增量更新后节点/边数量不累积
- 版本戳在全量重建后必须更新

**Failure Modes**:
- tree-sitter 加载失败 -> FULL_REBUILD (reason: tree_sitter_unavailable)
- 配置读取失败 -> FULL_REBUILD (reason: config_error)

**Core Flow**:
```
FUNCTION dispatch_index(changed_files, config):
  IF changed_files IS EMPTY:
    RETURN (SKIP, "no_changes")

  IF config.ast_delta.enabled IS FALSE:
    RETURN (FULL_REBUILD, "feature_disabled")

  IF tree_sitter_available() IS FALSE:
    RETURN (FULL_REBUILD, "tree_sitter_unavailable")

  IF cache_version != db_version:
    CLEAR ast_cache
    RETURN (FULL_REBUILD, "cache_version_mismatch")

  IF LENGTH(changed_files) > config.ast_delta.file_threshold:
    RETURN (FULL_REBUILD, "file_count_exceeds_threshold")

  RETURN (INCREMENTAL, "all_conditions_met")
```

**Complexity**:
- Time: O(1) 条件检查
- Space: O(n) 变更文件列表

**Test Case Points**:
1. 空文件列表 -> SKIP
2. 功能开关禁用 -> FULL_REBUILD
3. tree-sitter 不可用 -> FULL_REBUILD
4. 版本戳不一致 -> FULL_REBUILD + 清理缓存
5. 文件数超阈值 -> FULL_REBUILD
6. 所有条件满足 -> INCREMENTAL

### Algorithm Spec: Proto 发现策略

**Inputs**:
- `SCIP_PROTO_PATH`：环境变量（可选）
- `config.indexer.offline_proto`：离线模式开关
- `config.indexer.allow_proto_download`：下载允许开关

**Outputs**:
- `proto_path`：proto 文件路径
- `proto_source`：VENDORED | CUSTOM | CACHED | DOWNLOADED

**Core Flow**:
```
FUNCTION ensure_scip_proto(config):
  IF $SCIP_PROTO_PATH IS SET AND EXISTS:
    RETURN ($SCIP_PROTO_PATH, CUSTOM)

  IF EXISTS vendored/scip.proto:
    RETURN (vendored/scip.proto, VENDORED)

  IF EXISTS $CACHE_DIR/scip.proto:
    RETURN ($CACHE_DIR/scip.proto, CACHED)

  IF config.allow_proto_download IS TRUE:
    DOWNLOAD proto TO $CACHE_DIR/scip.proto
    IF DOWNLOAD SUCCESS:
      RETURN ($CACHE_DIR/scip.proto, DOWNLOADED)
    ELSE:
      EMIT ERROR "Failed to download SCIP proto"
      EXIT 1

  EMIT ERROR "SCIP proto not found. Expected: vendored/scip.proto"
  EMIT SUGGESTION "Run: scripts/vendor-proto.sh to download and vendor"
  EXIT 1
```

**Test Case Points**:
1. 自定义路径存在 -> CUSTOM
2. vendored proto 存在 -> VENDORED
3. 缓存 proto 存在 -> CACHED
4. 允许下载且成功 -> DOWNLOADED
5. 不允许下载且无本地 -> 报错

### Open Questions

1. **vendored proto 升级流程**：当 Sourcegraph 发布新版 scip.proto 时，是否需要 CI 自动检查兼容性？（建议：CI 检查 + CHANGELOG 记录）

2. **并发调度互斥**：当多个文件监听器实例同时触发索引操作时，是否需要 flock 级别的进程互斥？（当前设计依赖 SQLite WAL）

3. **ci_index_status 迁移通知**：是否需要在工具调用时输出 deprecation warning？（例如"ci_index_status now manages Embedding index"）

---

## 推荐的下一步

**下一步：`devbooks-test-owner`**（必须在单独的会话中）

原因：实现计划已完成。下一步是让 Test Owner 创建验证测试并产出 Red 基线。Test Owner 和 Coder 必须在不同会话中工作以确保角色隔离。

### 如何调用（在新会话中）
```
运行 devbooks-test-owner skill 处理变更 optimize-indexing-pipeline-20260117
```

**重要**：Test Owner 产出 Red 基线后，在另一个单独的会话中启动 Coder：
```
运行 devbooks-coder skill 处理变更 optimize-indexing-pipeline-20260117
```
