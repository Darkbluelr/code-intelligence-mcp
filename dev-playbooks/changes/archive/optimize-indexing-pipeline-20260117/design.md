# Design Doc: Indexing Pipeline Optimization

> **Change ID**: `optimize-indexing-pipeline-20260117`
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-18
> **Owner**: Design Owner
> **Last Verified**: 2026-01-18
> **Freshness Check**: 90 days

---

## Acceptance Criteria

### AC-001: Incremental-First Index Path [A]

**Pass**: 当监听到单文件变更且满足增量条件（tree-sitter 可用、AST 缓存版本戳一致、变更文件数 <= 10）时，`scripts/indexer.sh` 触发 `scripts/ast-delta.sh update <file>`，并在 `.devbooks/graph.db` 中可观测到对应节点/边变化。

**Fail**: 满足增量条件的单文件变更仍触发全量重建，或 `graph.db` 中无对应变更。

**验收方式**: A（机器裁判）- `tests/indexer.bats::test_incremental_path_invoked`

### AC-002: Reliable Fallback to Full Rebuild [A]

**Pass**: 当不满足增量条件（tree-sitter 不可用、缓存失效、变更文件数 > 10）时，`scripts/indexer.sh` 成功执行全量生成 `index.scip`，并通过 `scripts/scip-to-graph.sh parse --incremental` 更新 `graph.db`。

**Fail**: 回退路径失败导致 `graph.db` 未更新或状态不一致。

**验收方式**: A（机器裁判）- `tests/indexer.bats::test_fallback_to_full_rebuild`

### AC-003: Offline SCIP Proto Resolution [A]

**Pass**: 在无网络环境下（`/tmp/scip.proto` 不存在且网络受限），`scripts/scip-to-graph.sh parse` 成功从 vendored proto 加载并完成 `parse --incremental`，不触发在线下载。

**Fail**: 脚本尝试下载 `scip.proto` 或因缺少 proto 而失败。

**验收方式**: A（机器裁判）- `tests/scip-to-graph.bats::test_offline_proto_resolution`

### AC-004: Existing CLI Entry Points Compatibility [A]

**Pass**: `scripts/indexer.sh --help`、`--status`、`--install`、`--uninstall` 行为保持可用且输出格式不变。

**Fail**: 任一既有入口行为被破坏或输出格式发生 breaking change。

**验收方式**: A（机器裁判）- `tests/indexer.bats::test_cli_compatibility`

### AC-005: ci_index_status Semantic Alignment [A]

**Pass**: `ci_index_status` MCP 工具的 `status/build/clear` 参数明确映射到 `scripts/embedding.sh` 对应动作（`status` -> embedding.sh status；`build` -> embedding.sh build；`clear` -> embedding.sh clean），且 `src/server.ts` 中的调用路径正确。

**Fail**: `ci_index_status` 仍调用 `scripts/indexer.sh`，或语义与 Embedding 索引不一致。

**验收方式**: A（机器裁判）- `tests/server.bats::test_ci_index_status_semantic`

### AC-006: Idempotent Index Operations [A]

**Pass**: 对同一文件变更重复触发增量更新或全量回退，`graph.db` 状态保持一致（节点/边数量不因重复触发而累积或丢失）。

**Fail**: 重复触发导致 `graph.db` 出现重复节点/边或数据丢失。

**验收方式**: A（机器裁判）- `tests/indexer.bats::test_idempotency`

### AC-007: Debounce Window Aggregation [A]

**Pass**: 在 `DEBOUNCE_SECONDS`（默认 2s）窗口内的多个文件变更被聚合为单次批量更新（`ast-delta.sh batch` 或内部批处理），而非逐文件即时触发。

**Fail**: 窗口内每个变更都立即触发独立的索引操作。

**验收方式**: A（机器裁判）- `tests/indexer.bats::test_debounce_aggregation`

### AC-008: Version Stamp Consistency [A]

**Pass**: SCIP 全量重建后自动清理 AST 缓存，版本戳更新为当前时间戳；后续增量更新能正确检测版本戳一致性。

**Fail**: 版本戳不一致但未触发缓存清理，或版本戳检查逻辑错误导致永远回退到全量重建。

**验收方式**: A（机器裁判）- `tests/indexer.bats::test_version_stamp_consistency`

### AC-009: Feature Toggle Support [A]

**Pass**: 通过 `config/features.yaml` 中 `features.ast_delta.enabled: false` 或环境变量 `CI_AST_DELTA_ENABLED=false` 可禁用增量路径，回滚到"仅全量 SCIP 索引"模式。

**Fail**: 开关无效或未正确读取配置。

**验收方式**: A（机器裁判）- `tests/indexer.bats::test_feature_toggle`

### AC-010: Concurrent Write Safety [B]

**Pass**: 多个监听实例同时触发索引操作时，`graph.db` 不出现"database is locked"错误或数据损坏（WAL 模式 + 锁等待策略生效）。

**Fail**: 并发写入导致错误或数据不一致。

**验收方式**: B（工具证据 + 人签核）- 并发测试日志 + 人工确认无错误

---

## Goals / Non-goals / Red Lines

### Goals（本次变更要达成什么）

1. **打通增量优先的索引闭环**：文件变更时优先走 tree-sitter 增量更新 `graph.db`，必要时可靠回退到 SCIP 全量重建并同步图数据。
2. **离线化 `scip.proto` 来源**：`scripts/scip-to-graph.sh` 默认从 vendored proto 加载，消除运行时网络依赖。
3. **明确 `ci_index_status` 语义**：该工具归属 Embedding 索引管理，与 `scripts/embedding.sh` 对齐，避免契约漂移。

### Non-goals（明确不做）

1. 引入新的向量数据库或 `sqlite-vec`，不改造 `scripts/embedding.sh` 存储模型。
2. 引入 LSP、容器沙盒、联邦学习、神经符号验证等能力。
3. 修改 `scripts/graph-store.sh` 的 Schema（除非验证后确认是必要的最小修复）。
4. 变更 MCP 工具清单或扩展对外 API。

### Red Lines（不可破的约束）

1. **向后兼容**：`scripts/indexer.sh` 的既有入口（`--install/--uninstall/--status`）行为不可破坏。
2. **测试不可回退**：不可修改 `tests/**` 下的现有测试（符合 GIP-02）。
3. **分层约束**：禁止 `scripts/*.sh` → `src/*.ts` 的反向依赖（`ast-delta.sh` 调用 `ast-delta.ts` 例外）。
4. **数据完整性**：任何索引操作不可导致 `graph.db` 数据损坏或丢失。

---

## Executive Summary（执行摘要）

当前索引链路存在三个核心痛点：(1) 文件变更触发全量索引导致延迟与资源浪费；(2) `scip-to-graph.sh` 依赖在线下载 `scip.proto`，离线/受限网络下断链；(3) `ci_index_status` 工具与脚本职责边界不清。

本设计通过引入"增量优先 + 可靠回退"的调度策略、vendoring `scip.proto` 到仓库、以及明确工具语义归属，打通近实时索引闭环，同时保持系统可用性与可维护性。

---

## Problem Context（问题背景）

### 为什么要解决这个问题

- **业务驱动**：AI 辅助编程的上下文新鲜度直接影响建议质量；滞后的索引会导致"无效回合"（反复问、反复修正）。
- **技术债**：当前 `scripts/indexer.sh` 未串联 `scripts/ast-delta.sh` 的增量能力，浪费了已有实现。
- **可用性缺口**：离线/受限网络下 `scip.proto` 下载失败会导致整条解析链路不可用。

### 当前系统摩擦点

1. **indexer.sh**：文件监听后触发全量生成 `index.scip`，无增量链路。
2. **scip-to-graph.sh**：缺少本地 `scip.proto` 时会下载，存在隐式网络依赖。
3. **ci_index_status**：`src/server.ts` 当前把 `status/build/clear` 直接传给 `scripts/indexer.sh`，但 indexer 是 SCIP/图索引守护进程，语义不匹配。

### 不解决的后果

- 上下文滞后持续影响 AI 辅助质量，用户体验下降。
- 离线用户无法使用图基分析能力。
- 工具契约漂移继续扩大，后续维护成本增加。

---

## Value Chain Mapping（价值链映射）

| Goal | Blocker | Lever | Minimal Solution |
|------|---------|-------|------------------|
| 近实时上下文 | 全量索引延迟 | 增量更新能力 | indexer.sh 调度增量路径 |
| 离线可用性 | scip.proto 网络依赖 | 本地 proto | vendoring scip.proto |
| 契约清晰 | 语义不匹配 | 职责对齐 | ci_index_status → embedding.sh |

---

## Background Assessment（背景与现状评估）

### 现有资产

| 资产 | 路径 | 状态 | 备注 |
|------|------|------|------|
| AST Delta 增量更新 | `scripts/ast-delta.sh` | 已实现 | 支持 `update`/`batch` 命令 |
| SCIP 解析转换 | `scripts/scip-to-graph.sh` | 已实现 | 支持 `parse --incremental` |
| 图存储 | `scripts/graph-store.sh` | 已实现 | SQLite WAL 模式 |
| 文件监听 | `scripts/indexer.sh` | 部分实现 | fswatch/inotifywait/polling 三路径 |
| Embedding 索引 | `scripts/embedding.sh` | 已实现 | 支持 `status/build/clean` |

### 主要风险

| 风险 | 影响 | 缓解策略 |
|------|------|----------|
| 并发写入 `graph.db` | 数据损坏或锁等待 | WAL 模式 + 互斥调度 |
| 版本漂移（vendored proto） | 解析失配 | 明确升级策略 + 版本注释 |
| 增量覆盖不足 | 回退频率高 | 阈值可配置 + 日志监控 |

---

## Design Principles（设计原则）

### 核心原则

1. **增量优先、可靠回退**：默认走增量路径，失败时有确定性的回退策略。
2. **离线优先、在线可选**：默认不依赖网络，显式允许时才下载。
3. **职责单一、边界清晰**：indexer 负责调度，ast-delta 负责增量，scip-to-graph 负责解析。

### Variation Points（变化点识别）

| 变化点 | 可能的变化 | 封装策略 |
|--------|-----------|----------|
| 增量能力 | tree-sitter 不可用 | 降级链：tree-sitter → SCIP → regex |
| Proto 来源 | 需要升级版本 | 升级脚本 + 版本注释 |
| 防抖窗口 | 不同项目需要不同值 | 环境变量 `DEBOUNCE_SECONDS` |
| 阈值参数 | 文件数阈值可能调整 | `config/features.yaml` |

---

## Target Architecture（目标架构）

### Bounded Context

本变更主要发生在 **Indexing Pipeline** 边界内：

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Indexing Pipeline Context                        │
│                                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────┐  │
│  │ indexer.sh  │───▶│ ast-delta.sh│───▶│ graph.db                │  │
│  │ (Scheduler) │    │ (Incremental)│    │ (via graph-store.sh)   │  │
│  └─────────────┘    └─────────────┘    └─────────────────────────┘  │
│         │                                                            │
│         │ fallback                                                   │
│         ▼                                                            │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ SCIP Rebuild Path                                                ││
│  │  [scip-typescript] → [index.scip] → [scip-to-graph.sh] → graph.db│
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
│  ┌─────────────┐                                                     │
│  │scip.proto   │ ← vendored（默认） / download（显式允许）            │
│  │(vendored)   │                                                     │
│  └─────────────┘                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 依赖方向

```
src/server.ts
    │
    ├──▶ scripts/embedding.sh (ci_index_status)  [NEW: 对齐后]
    │
    ├──▶ scripts/indexer.sh (ci_ast_delta / daemon 入口)
    │       │
    │       ├──▶ scripts/ast-delta.sh (增量路径)
    │       │       └──▶ scripts/graph-store.sh
    │       │
    │       └──▶ scripts/scip-to-graph.sh (回退路径)
    │               ├──▶ scripts/graph-store.sh
    │               └──▶ vendored/scip.proto [NEW]
    │
    └──▶ scripts/common.sh
```

### Testability & Seams（可测试性与接缝）

**Seams**:
- `indexer.sh` 调度逻辑可通过 `--dry-run` 输出决策路径而不实际执行
- `scip-to-graph.sh` 的 proto 发现逻辑可通过环境变量 `SCIP_PROTO_PATH` 注入
- 防抖窗口通过 `DEBOUNCE_SECONDS` 环境变量可配置

**Pinch Points**:
- `indexer.sh:dispatch_index()` - 所有监听路径（fswatch/inotify/polling）的调度汇聚点
- `scip-to-graph.sh:ensure_scip_proto()` - 所有解析路径的 proto 发现入口
- `src/server.ts:handleToolCall()::ci_index_status` - MCP 工具调用入口

**依赖隔离**:
- `graph.db` 写入通过 `graph-store.sh` 接口隔离
- Proto 文件通过 vendoring + 环境变量隔离

---

## Domain Model（领域模型）

### Data Model

| 对象 | 类型 | 说明 |
|------|------|------|
| `IndexTask` | @ValueObject | 索引任务描述（文件列表、触发时间、任务类型） |
| `IndexDecision` | @ValueObject | 调度决策（INCREMENTAL / FULL_REBUILD / SKIP） |
| `ProtoSource` | @ValueObject | Proto 来源（VENDORED / DOWNLOADED / CUSTOM） |

### Business Rules

| Rule ID | 规则 | 触发条件 | 约束 | 违反行为 |
|---------|------|----------|------|----------|
| BR-001 | 增量优先 | 文件变更且满足增量条件 | 优先调用 ast-delta.sh | - |
| BR-002 | 可靠回退 | 增量条件不满足 | 必须完成全量重建并同步图 | - |
| BR-003 | 离线优先 | scip.proto 加载 | 优先使用 vendored proto | 显式允许时才下载 |
| BR-004 | 防抖聚合 | 窗口内多次变更 | 聚合为单次批量操作 | - |

### Invariants（固定规则）

- `[Invariant]` 增量更新后 graph.db 节点/边数量不因重复触发而累积或丢失
- `[Invariant]` SCIP 全量重建后 AST 缓存版本戳必须更新
- `[Invariant]` vendored scip.proto 版本与 scip-typescript 版本兼容

---

## Core Data & Contracts（核心数据与事件契约）

### Artifacts

| 产物 | 路径 | 说明 |
|------|------|------|
| Vendored Proto | `vendored/scip.proto` | 固定版本的 SCIP proto 定义 |
| 索引状态 | `.devbooks/index-state.json` | 最后索引时间戳、版本戳 |
| AST 缓存 | `.devbooks/ast-cache/` | tree-sitter 解析缓存 |
| 图数据库 | `.devbooks/graph.db` | SQLite 图存储 |

### Configuration Schema

```yaml
# config/features.yaml（扩展）
features:
  ast_delta:
    enabled: true                    # 启用增量路径
    file_threshold: 10               # 超过此数量回退到全量
  indexer:
    debounce_seconds: 2              # 防抖窗口
    offline_proto: true              # 使用 vendored proto
    allow_proto_download: false      # 是否允许下载更新
```

---

## Key Mechanisms（关键机制）

### 调度决策逻辑

```
Input: changed_files[]

IF ast_delta.enabled == false:
    RETURN FULL_REBUILD

IF tree_sitter_available == false:
    RETURN FULL_REBUILD

IF cache_version_mismatch:
    RETURN FULL_REBUILD

IF len(changed_files) > file_threshold:
    RETURN FULL_REBUILD

RETURN INCREMENTAL
```

### Proto 发现策略

```
1. 检查 $SCIP_PROTO_PATH（自定义路径）
2. 检查 vendored/scip.proto（仓库内 vendoring）
3. 检查 $CACHE_DIR/scip.proto（缓存）
4. 若 allow_proto_download == true:
     下载到 $CACHE_DIR/scip.proto
   ELSE:
     报错退出（可诊断的明确错误）
```

---

## Observability & Validation（可观测性与验收）

### Metrics

| 指标 | 类型 | 说明 |
|------|------|------|
| `index.decision` | Counter | 按决策类型（INCREMENTAL/FULL_REBUILD/SKIP）统计 |
| `index.duration_ms` | Histogram | 索引操作耗时分布 |
| `index.proto_source` | Counter | Proto 来源统计 |

### SLO

| 指标 | 目标 | 备注 |
|------|------|------|
| 单文件增量延迟 p95 | < 120ms | 参考 REQ-AD-004 |
| 回退路径成功率 | 100% | 不允许因回退失败导致索引不可用 |

---

## Security & Compliance（安全与合规）

### 安全考量

- **网络隔离**：默认离线运行，不暴露网络攻击面。
- **数据完整性**：SQLite WAL 模式 + 原子写入保护。
- **权限控制**：脚本执行权限不变。

---

## Milestones（里程碑）

| Phase | 内容 | AC 覆盖 |
|-------|------|---------|
| M1 | indexer.sh 调度逻辑 + 增量路径串联 | AC-001, AC-006, AC-007, AC-008 |
| M2 | scip-to-graph.sh 离线 proto 支持 | AC-003 |
| M3 | ci_index_status 语义对齐 | AC-005 |
| M4 | 回退路径验证 + 兼容性测试 | AC-002, AC-004 |
| M5 | 功能开关 + 并发安全验证 | AC-009, AC-010 |

---

## Deprecation Plan（弃用计划）

- **scip.proto 在线下载**：默认禁用，保留 `allow_proto_download: true` 作为后门；计划在 v1.0 稳定后移除该后门。

---

## Trade-offs（权衡取舍）

1. **放弃即时新鲜度**：选择防抖窗口聚合（DP-03 选 B），牺牲 ~2s 延迟换取稳定吞吐。
2. **接受版本固定**：vendoring proto 带来版本漂移风险，但降低了运行时复杂度。
3. **语义拆分代价**：`ci_index_status` 对齐 Embedding 后，需要用户更新使用习惯（若有）。

---

## Risks & Degrade Paths（风险与降级策略）

### Failure Modes

| 失败模式 | 检测方式 | 降级路径 |
|----------|----------|----------|
| tree-sitter 不可用 | 加载失败检测 | 回退 SCIP 全量 |
| AST 缓存损坏 | 版本戳校验 | 清理缓存 + 全量重建 |
| graph.db 锁竞争 | 超时检测 | 重试 + 日志告警 |
| vendored proto 不兼容 | 解析失败 | 允许下载更新（后门） |

### 回滚策略

- **功能开关回滚**：`features.ast_delta.enabled: false` 禁用增量路径。
- **Proto 回滚**：`features.indexer.allow_proto_download: true` 允许下载覆盖。
- **完整回滚**：revert 本变更包的所有代码改动。

---

## Documentation Impact（文档影响）

### 需要更新的文档

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| README.md | ci_index_status 语义变更说明 | P0 |
| docs/使用说明书.md | 新增 vendored proto 说明、功能开关说明 | P0 |
| CHANGELOG.md | 记录本次变更 | P1 |

### 文档更新检查清单

- [ ] ci_index_status 语义变更已在 README.md 说明
- [ ] 离线 proto 使用方式已在使用文档中说明
- [ ] 功能开关配置项已在配置文档中说明

---

## Architecture Impact（架构影响）

### 有架构变更

#### C4 层级影响

| 层级 | 变更类型 | 影响描述 |
|------|----------|----------|
| Context | 无变更 | - |
| Container | 新增 | 新增 `vendored/scip.proto` 资源文件 |
| Component | 修改 | indexer.sh 新增调度组件、scip-to-graph.sh 新增 proto 发现组件 |

#### C4 Delta

**Container 变更**:
- [新增] `vendored/scip.proto`: 固定版本的 SCIP proto 定义文件，作为离线解析的依赖资源

**Component 变更**:
- [修改] `scripts/indexer.sh`: 新增 `dispatch_index()` 调度组件，负责增量/全量决策
- [修改] `scripts/scip-to-graph.sh`: 修改 `ensure_scip_proto()` 组件，改为"本地优先"发现策略
- [修改] `src/server.ts`: `ci_index_status` 调用路由从 `indexer.sh` 改为 `embedding.sh`

#### 依赖变更

| 源 | 目标 | 变更类型 | 说明 |
|----|------|----------|------|
| `indexer.sh` | `ast-delta.sh` | 新增 | 增量路径调用 |
| `indexer.sh` | `scip-to-graph.sh` | 新增 | 回退路径同步图 |
| `scip-to-graph.sh` | `vendored/scip.proto` | 新增 | 离线 proto 依赖 |
| `ci_index_status` | `indexer.sh` | 删除 | 语义对齐 |
| `ci_index_status` | `embedding.sh` | 新增 | 语义对齐 |

#### 分层约束影响

- [x] 本次变更遵守现有分层约束
- [ ] 本次变更需要修改分层约束（需在下方说明）

---

## Definition of Done（DoD 完成定义）

### 本设计何时算"完成"

1. 所有 AC（AC-001 至 AC-010）通过机器验证或人工签核。
2. 所有必须通过的闸门通过。
3. 必须产出的证据已归档。

### 必须通过的闸门清单

| 闸门 | 验证命令 | AC 交叉引用 |
|------|----------|-------------|
| ShellCheck | `npm run lint` | AC-001 ~ AC-009 |
| TypeScript Build | `npm run build` | AC-005 |
| Unit Tests | `npm test` | AC-001 ~ AC-010 |
| CLI 兼容性 | `./scripts/indexer.sh --help` | AC-004 |

### 必须产出的证据

| 证据 | 路径 | 说明 |
|------|------|------|
| Red 基线 | `dev-playbooks/changes/optimize-indexing-pipeline-20260117/evidence/red-baseline/` | 测试失败日志 |
| Green 最终 | `dev-playbooks/changes/optimize-indexing-pipeline-20260117/evidence/green-final/` | 测试通过日志 + lint + build |
| 离线验证 | `evidence/green-final/offline-proto.log` | 离线环境下 parse 成功日志 |

---

## Affected Specs（受影响的规格真理）

| Spec | 路径 | 影响类型 | 说明 |
|------|------|----------|------|
| SCIP Parser | `dev-playbooks/specs/scip-parser/spec.md` | EXTEND | 补充"离线 proto"场景（SC-SP-xxx） |
| AST Delta | `dev-playbooks/specs/ast-delta/spec.md` | NO CHANGE | 已有场景覆盖增量逻辑 |
| Incremental Indexing | `dev-playbooks/specs/incremental-indexing/spec.md` | EXTEND | 补充调度链路场景 |
| C4 Architecture | `dev-playbooks/specs/architecture/c4.md` | EXTEND | 更新 Container/Component 清单 |
| Project Profile | `dev-playbooks/specs/_meta/project-profile.md` | EXTEND | 更新 ci_index_status 工具说明 |

---

## Open Questions（<= 3）

1. **vendored proto 升级流程**：当 Sourcegraph 发布新版 scip.proto 时，如何安全升级 vendored 文件？（建议：CI 检查 + CHANGELOG 记录）

2. **并发调度互斥**：当多个文件监听器实例同时触发索引操作时，是否需要 flock 级别的互斥？（当前依赖 SQLite WAL，但调度层可能需要额外保护）

3. **ci_index_status 迁移通知**：是否需要在工具调用时输出 deprecation warning（例如"ci_index_status now manages Embedding index"）？

---

## AC Summary（验收标准摘要）

| AC ID | 标题 | 验收方式 |
|-------|------|----------|
| AC-001 | 增量优先索引路径 | A |
| AC-002 | 可靠回退到全量重建 | A |
| AC-003 | 离线 SCIP Proto 解析 | A |
| AC-004 | 既有 CLI 入口兼容性 | A |
| AC-005 | ci_index_status 语义对齐 | A |
| AC-006 | 幂等索引操作 | A |
| AC-007 | 防抖窗口聚合 | A |
| AC-008 | 版本戳一致性 | A |
| AC-009 | 功能开关支持 | A |
| AC-010 | 并发写入安全 | B |
