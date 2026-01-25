# 设计文档：补齐 Augment 对等最后差距（Final Gaps）

> **Change ID**: `augment-parity-final-gaps`
> **Design Owner**: Design Owner (Claude)
> **Date**: 2026-01-16
> **Last Updated**: 2026-01-16 (Design Backport: Bug 定位 CLI 契约)
> **Status**: Draft
> **Proposal Reference**: [proposal.md](./proposal.md)

---

## 1. What（做什么）

### 1.1 变更目标

在**轻资产**范围内弥合 Augment 最终差距，使本项目配合前序变更包后**完全达到 Augment 轻资产能力对等（100%）**。

### 1.2 功能范围

本变更包含 **12 个功能模块**，分为 5 个能力域：

#### 能力域 A：图存储与检索增强

| 模块 ID | 模块名称 | 能力描述 |
|---------|----------|----------|
| MOD-01 | 边类型扩展 | 新增 IMPLEMENTS/EXTENDS/RETURNS_TYPE 三种边类型，支持类型关系追踪 |
| MOD-02 | A-B 路径查询 | 基于 BFS 的 A→B 最短路径算法，支持影响分析链追踪 |

#### 能力域 B：上下文引擎增强

| 模块 ID | 模块名称 | 能力描述 |
|---------|----------|----------|
| MOD-03 | ADR 解析与关联 | 解析架构决策记录（ADR），关联到代码模块，提供架构决策上下文 |
| MOD-04 | 对话历史信号累积 | 记录多轮对话上下文，提升搜索结果的连续性和相关性 |
| MOD-11 | 结构化上下文输出 | 将上下文输出从自由文本升级为 5 层结构化模板 |
| MOD-12 | DevBooks 适配 | 自动检测 DevBooks 配置，提取高信噪比信息增强代码智能 |

#### 能力域 C：延迟与实时性优化

| 模块 ID | 模块名称 | 能力描述 |
|---------|----------|----------|
| MOD-05 | Daemon 预热机制 | 启动时预加载高频查询、热点子图，降低冷启动延迟 |
| MOD-06 | 请求取消机制 | 支持请求取消令牌，检测新请求时终止旧请求，释放资源 |
| MOD-07 | 子图 LRU 缓存 | 热点子图 SQLite 持久化 LRU 缓存，支持跨进程共享 |

#### 能力域 D：分析能力融合

| 模块 ID | 模块名称 | 能力描述 |
|---------|----------|----------|
| MOD-08 | Bug 定位 + 影响分析融合 | 集成影响分析到 Bug 定位输出，提升定位精度 |

#### 能力域 E：企业级治理

| 模块 ID | 模块名称 | 能力描述 |
|---------|----------|----------|
| MOD-09 | GitHub Action CI/CD | PR 自动架构检查（循环依赖、孤儿模块、架构规则违规） |
| MOD-10 | GitLab CI 模板 | GitLab CI 架构检查模板 |

### 1.3 交互模型

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              交互流程                                        │
│                                                                              │
│  [用户查询] ──→ [意图分析 4D] ──→ [对话上下文累积] ──→ [搜索/分析]           │
│                     │                    │                   │              │
│                     ▼                    ▼                   ▼              │
│            [DevBooks 适配]       [预热缓存命中]      [结构化输出]           │
│                     │                    │                   │              │
│                     └────────────────────┼───────────────────┘              │
│                                          ▼                                   │
│                              [5 层结构化上下文]                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 非目标（明确排除）

| 排除项 | 原因 |
|--------|------|
| 迁移到 Neo4j | 重资产，保持 SQLite 图存储 |
| IDE 插件开发 | 重资产，无隐式信号获取 |
| 实时文件监听 daemon | 需额外架构，增量索引由触发式驱动 |
| 分布式图数据库 | 重资产 |
| 自研 LLM 模型 | 重资产 |

---

## 2. Constraints（约束条件）

### 2.1 技术约束

| 约束 ID | 约束描述 | 来源 |
|---------|----------|------|
| CON-TECH-001 | **薄壳架构**：核心功能由 `scripts/*.sh` 实现，`src/server.ts` 仅处理 MCP 协议和工具调度 | project.md |
| CON-TECH-002 | **依赖方向**：`server.ts → scripts/*.sh → common.sh`，禁止反向依赖 | c4.md |
| CON-TECH-003 | **SQLite 图存储**：使用 SQLite + WAL 模式作为图存储后端，不迁移到 Neo4j | proposal.md |
| CON-TECH-004 | **向后兼容**：所有新功能通过可选参数/功能开关控制，不破坏现有 API | proposal.md |
| CON-TECH-005 | **跨进程持久化**：LRU 缓存使用 SQLite 持久化，支持跨进程共享 | proposal.md (MOD-01 修订) |

### 2.2 质量约束

| 约束 ID | 约束描述 | 验证方式 |
|---------|----------|----------|
| CON-QA-001 | **性能**：冷启动延迟降低 50%（目标 ~300ms） | benchmark.sh |
| CON-QA-002 | **缓存命中率**：重复查询 LRU 缓存命中率 > 80% | tests/cache-manager.bats |
| CON-QA-003 | **请求取消**：取消信号在 100ms 内生效 | tests/daemon.bats |
| CON-QA-004 | **测试覆盖**：所有新功能有对应 Bats 测试 | npm test |

### 2.3 数据约束

| 约束 ID | 约束描述 | 说明 |
|---------|----------|------|
| CON-DATA-001 | **边类型 Schema 迁移**：已有 graph.db 需通过迁移命令升级 | graph-store.sh migrate |
| CON-DATA-002 | **对话上下文大小**：最多保留 10 轮对话，超过后 FIFO 淘汰 | 可配置 |
| CON-DATA-003 | **LRU 缓存大小**：默认 100 个子图，可配置 | 50MB 上限 |

### 2.4 兼容性约束

| 约束 ID | 约束描述 | 验证方式 |
|---------|----------|----------|
| CON-COMPAT-001 | **SCIP 语言支持**：边类型扩展需支持 TypeScript、Python，其他语言降级到 REFERENCES | tests/graph-store.bats |
| CON-COMPAT-002 | **ADR 格式**：支持 MADR 和 Nygard 两种格式 | tests/adr-parser.bats |
| CON-COMPAT-003 | **CI 平台**：提供 GitHub Action 和 GitLab CI 模板 | actionlint 验证 |

---

## 3. Acceptance Criteria（验收标准）

### 3.1 图存储与检索（AC-G01 ~ AC-G02）

#### AC-G01: 边类型扩展

| 验收条件 | 验证方法 |
|----------|----------|
| TypeScript 项目索引后，graph.db 包含 IMPLEMENTS 边类型 | `sqlite3 .devbooks/graph.db "SELECT COUNT(*) FROM edges WHERE edge_type='IMPLEMENTS'"` > 0 |
| TypeScript 项目索引后，graph.db 包含 EXTENDS 边类型 | `sqlite3 .devbooks/graph.db "SELECT COUNT(*) FROM edges WHERE edge_type='EXTENDS'"` > 0 |
| TypeScript 项目索引后，graph.db 包含 RETURNS_TYPE 边类型 | `sqlite3 .devbooks/graph.db "SELECT COUNT(*) FROM edges WHERE edge_type='RETURNS_TYPE'"` > 0 |
| Python 项目索引后支持 IMPLEMENTS（需类型注解） | tests/graph-store.bats::test_edge_types_python |
| 不支持的语言降级到 REFERENCES，不报错 | tests/graph-store.bats::test_edge_types_fallback |

**测试脚本**：`tests/graph-store.bats::test_edge_types`

#### AC-G01a: 迁移命令

| 验收条件 | 验证方法 |
|----------|----------|
| `graph-store.sh migrate --check` 在旧 graph.db 上返回 NEEDS_MIGRATION | tests/graph-store.bats::test_migrate_check_old |
| `graph-store.sh migrate --check` 在新 graph.db 上返回 UP_TO_DATE | tests/graph-store.bats::test_migrate_check_new |
| `graph-store.sh migrate --apply` 成功迁移数据且不丢失 | tests/graph-store.bats::test_migrate_apply |
| 迁移前自动创建备份文件 | tests/graph-store.bats::test_migrate_backup |

**测试脚本**：`tests/graph-store.bats::test_migrate_*`

#### AC-G02: 路径查询

| 验收条件 | 验证方法 |
|----------|----------|
| `find-path --from A --to B` 返回 A 到 B 的最短路径 | tests/graph-store.bats::test_find_path_basic |
| 路径深度 1~10 均可工作 | tests/graph-store.bats::test_find_path_depth |
| 不存在路径时返回空结果，不报错 | tests/graph-store.bats::test_find_path_no_path |
| 路径结果包含路径节点列表和长度 | tests/graph-store.bats::test_find_path_output |

**测试脚本**：`tests/graph-store.bats::test_find_path`

### 3.2 上下文引擎（AC-G03 ~ AC-G04, AC-G11 ~ AC-G12）

#### AC-G03: ADR 解析

| 验收条件 | 验证方法 |
|----------|----------|
| 解析 MADR 格式 ADR 文件，正确提取 Status/Decision/Context | tests/adr-parser.bats::test_parse_madr |
| 解析 Nygard 格式 ADR 文件，正确提取 Status/Decision/Context | tests/adr-parser.bats::test_parse_nygard |
| ADR 关键词关联到 graph.db 节点，生成 ADR_RELATED 边 | tests/adr-parser.bats::test_adr_graph_link |
| 无 ADR 目录时不报错 | tests/adr-parser.bats::test_no_adr_dir |

**测试脚本**：`tests/adr-parser.bats`

#### AC-G04: 对话上下文

| 验收条件 | 验证方法 |
|----------|----------|
| 写入 5 条对话记录后可正确读取全部 5 条 | tests/intent-learner.bats::test_conversation_context_write_read |
| 上下文包含 turn、query、focus_symbols 字段 | tests/intent-learner.bats::test_conversation_context_schema |
| 超过 10 轮后 FIFO 淘汰最旧记录 | tests/intent-learner.bats::test_conversation_context_fifo |
| 搜索结果排序加入对话连续性加权 | tests/intent-learner.bats::test_conversation_context_weighting |

**测试脚本**：`tests/intent-learner.bats::test_conversation_context`

#### AC-G11: 结构化上下文输出

| 验收条件 | 验证方法 |
|----------|----------|
| 输出 JSON 包含 `project_profile` 字段 | tests/augment-context.bats::test_structured_output_profile |
| 输出 JSON 包含 `current_state` 字段 | tests/augment-context.bats::test_structured_output_state |
| 输出 JSON 包含 `task_context` 字段 | tests/augment-context.bats::test_structured_output_task |
| 输出 JSON 包含 `recommended_tools` 字段 | tests/augment-context.bats::test_structured_output_tools |
| 输出 JSON 包含 `constraints` 字段 | tests/augment-context.bats::test_structured_output_constraints |
| 输出符合定义的 JSON Schema | tests/augment-context.bats::test_structured_output_schema |

**输出 Schema**：
```json
{
  "project_profile": { "name": "string", "tech_stack": ["string"], "architecture": "string", "key_constraints": ["string"] },
  "current_state": { "index_status": "ready|stale|missing", "hotspot_files": ["string"], "recent_commits": ["string"] },
  "task_context": { "intent_analysis": {}, "relevant_snippets": [], "call_chains": [] },
  "recommended_tools": [{ "tool": "string", "reason": "string", "suggested_params": {} }],
  "constraints": { "architectural": ["string"], "security": ["string"] }
}
```

**测试脚本**：`tests/augment-context.bats::test_structured_output`

#### AC-G12: DevBooks 适配

| 验收条件 | 验证方法 |
|----------|----------|
| **正向测试**：有 `.devbooks/config.yaml` 时检测到 DevBooks 配置 | tests/augment-context.bats::test_devbooks_detection_positive |
| **正向测试**：注入项目画像（技术栈 + 架构模式） | tests/augment-context.bats::test_devbooks_profile_inject |
| **正向测试**：注入架构约束（分层规则） | tests/augment-context.bats::test_devbooks_constraints_inject |
| **负向测试**：无 `.devbooks/config.yaml` 时不报错 | tests/augment-context.bats::test_devbooks_detection_negative |
| **负向测试**：非 DevBooks 项目正常输出上下文 | tests/augment-context.bats::test_devbooks_fallback |

**测试脚本**：`tests/augment-context.bats::test_devbooks_*`

### 3.3 延迟与实时性（AC-G05 ~ AC-G07）

#### AC-G05: 预热机制

| 验收条件 | 验证方法 |
|----------|----------|
| `daemon.sh warmup` 执行成功 | tests/daemon.bats::test_warmup_success |
| 预热完成后 `cache-manager.sh stats` 显示已缓存条目 > 0 | tests/daemon.bats::test_warmup_cache_populated |
| 预热加载热点文件子图 | tests/daemon.bats::test_warmup_hotspot |
| 预热加载常用符号索引 | tests/daemon.bats::test_warmup_symbols |

**测试脚本**：`tests/daemon.bats::test_warmup`

#### AC-G06: 请求取消

| 验收条件 | 验证方法 |
|----------|----------|
| 启动长时间请求后，发起新请求时旧请求在 100ms 内终止 | tests/daemon.bats::test_cancel_concurrent |
| 取消信号使用 flock 文件锁保证原子性 | tests/daemon.bats::test_cancel_atomic |
| 取消后资源正确释放 | tests/daemon.bats::test_cancel_cleanup |
| 未取消的请求正常完成 | tests/daemon.bats::test_cancel_normal_completion |

**测试脚本**：`tests/daemon.bats::test_cancel_concurrent`

#### AC-G07: LRU 缓存

| 验收条件 | 验证方法 |
|----------|----------|
| 连续执行 10 次相同查询，命中率 > 80% | tests/cache-manager.bats::test_lru_hit_rate |
| 缓存使用 SQLite 持久化（`.devbooks/subgraph-cache.db`） | tests/cache-manager.bats::test_lru_persistence |
| 跨进程缓存有效（进程 1 写入，进程 2 读取） | tests/cache-manager.bats::test_lru_cross_process |
| 超过 100 个条目时 LRU 淘汰最旧条目 | tests/cache-manager.bats::test_lru_eviction |
| 缓存统计命令返回正确的条目数/命中率 | tests/cache-manager.bats::test_lru_stats |

**测试脚本**：`tests/cache-manager.bats::test_lru_*`

### 3.4 分析能力融合（AC-G08）

#### AC-G08: Bug 定位融合

| 验收条件 | 验证方法 |
|----------|----------|
| `--with-impact` 参数使输出 JSON 包含 `impact` 字段 | tests/bug-locator.bats::test_with_impact_field |
| `impact` 字段包含 `total_affected` 数值 | tests/bug-locator.bats::test_with_impact_total |
| `impact` 字段包含 `affected_files` 数组 | tests/bug-locator.bats::test_with_impact_files |
| 综合分数正确加入影响范围权重 | tests/bug-locator.bats::test_with_impact_scoring |
| 不带 `--with-impact` 时保持原有输出格式（向后兼容） | tests/bug-locator.bats::test_without_impact_compat |

**接口契约回写（Design Backport）**：
- 保持既有入口：`bug-locator.sh --error <desc>`；`--with-impact`/`--impact-depth` 为新增可选参数。
- 本变更不引入 `locate` 子命令；如未来引入，必须保证 `--error` 路径继续可用（向后兼容）。
- 输出保持现有 JSON 外层结构（schema_version + candidates[]）；`impact` 仅扩展 candidates 元素。

**输出 Schema**：
```json
{
  "schema_version": "string",
  "candidates": [
    {
      "symbol": "string",
      "file": "string",
      "line": "integer",
      "score": "number (0-100)",
      "impact": {
        "total_affected": "integer",
        "affected_files": ["string"],
        "max_depth": "integer"
      }
    }
  ]
}
```

**测试脚本**：`tests/bug-locator.bats::test_with_impact`

### 3.5 企业级治理（AC-G09）

#### AC-G09: GitHub Action

| 验收条件 | 验证方法 |
|----------|----------|
| `.github/workflows/arch-check.yml` 语法正确 | actionlint .github/workflows/arch-check.yml |
| workflow 在 PR 时触发 | tests/ci.bats::test_workflow_trigger |
| 循环依赖检测失败时 CI 失败 | tests/ci.bats::test_workflow_cycles |
| 架构规则违规时 CI 失败 | tests/ci.bats::test_workflow_violations |
| 检测通过时 CI 成功 | tests/ci.bats::test_workflow_success |

**测试脚本**：`tests/ci.bats::test_workflow_syntax`

### 3.6 向后兼容（AC-G10）

#### AC-G10: 回归测试

| 验收条件 | 验证方法 |
|----------|----------|
| `npm test` 全部通过 | npm test |
| 现有 MCP 工具（ci_search、ci_call_chain 等）无回归 | tests/mcp-contract.bats |
| 现有脚本无破坏性变更 | tests/*.bats |

**测试脚本**：全量测试套件

---

## 4. Documentation Impact（文档影响）

### 4.1 需要更新的文档

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| `README.md` | 新增 12 个功能模块的使用说明 | P0 |
| `docs/使用说明书.md`（如有） | 新增脚本和参数说明 | P0 |
| `CHANGELOG.md` | 记录本次变更 | P1 |
| `dev-playbooks/specs/architecture/c4.md` | 更新 Container/Component 图 | P1 |

### 4.2 文档更新检查清单

- [ ] `adr-parser.sh` 新增脚本已在使用文档中说明
- [ ] `graph-store.sh find-path` 新增命令已在使用文档中说明
- [ ] `graph-store.sh migrate` 新增命令已在使用文档中说明
- [ ] `bug-locator.sh --with-impact` 新增参数已在使用文档中说明
- [ ] `daemon.sh warmup` 新增命令已在使用文档中说明
- [ ] 结构化上下文输出格式已在文档中说明
- [ ] GitHub Action 使用方式已在 README 中说明
- [ ] 功能开关配置（features.yaml）已在配置文档中说明

---

## 5. Architecture Impact（架构影响）

### 5.1 有架构变更

本次变更影响 Container 和 Component 层级。

#### 5.2 C4 层级影响

| 层级 | 变更类型 | 影响描述 |
|------|----------|----------|
| Context | 无变更 | 外部系统关系不变 |
| Container | 新增 | 新增 adr-parser.sh 脚本容器 |
| Component | 新增/修改 | 多个脚本新增组件/函数 |

#### 5.3 Container 变更详情

| 操作 | Container | 描述 |
|------|-----------|------|
| **新增** | `scripts/adr-parser.sh` | ADR 解析与关联脚本 |
| **新增** | `.github/workflows/arch-check.yml` | GitHub Action CI/CD |
| **新增** | `.gitlab-ci.yml.template` | GitLab CI 模板 |
| **新增** | `tests/adr-parser.bats` | ADR 解析测试 |
| **新增** | `tests/augment-context.bats` | 上下文输出测试 |
| **新增** | `tests/ci.bats` | CI 测试 |
| 修改 | `scripts/scip-to-graph.sh` | 边类型扩展 |
| 修改 | `scripts/graph-store.sh` | 路径查询 + 迁移命令 |
| 修改 | `scripts/intent-learner.sh` | 对话上下文 |
| 修改 | `scripts/daemon.sh` | 预热 + 请求取消 |
| 修改 | `scripts/cache-manager.sh` | LRU 子图缓存 |
| 修改 | `scripts/bug-locator.sh` | 影响分析融合 |
| 修改 | `hooks/augment-context-global.sh` | 结构化输出 + DevBooks 适配 |
| 修改 | `scripts/common.sh` | DevBooks 检测函数 |

#### 5.4 Component 变更详情

| Container | 新增 Component | 职责 |
|-----------|----------------|------|
| `scip-to-graph.sh` | `map_role_to_edge_type()` | 扩展边类型映射（IMPLEMENTS/EXTENDS/RETURNS_TYPE） |
| `graph-store.sh` | `find_path()` | BFS 最短路径查询 |
| `graph-store.sh` | `migrate_schema()` | Schema 迁移命令 |
| `adr-parser.sh` | `parse_adr()` | ADR 文件解析 |
| `adr-parser.sh` | `extract_keywords()` | 关键词提取 |
| `adr-parser.sh` | `link_to_graph()` | 关联到 graph.db |
| `intent-learner.sh` | `save_conversation_context()` | 对话上下文保存 |
| `intent-learner.sh` | `load_conversation_context()` | 对话上下文加载 |
| `intent-learner.sh` | `apply_conversation_weighting()` | 对话连续性加权 |
| `daemon.sh` | `daemon_warmup()` | 预热机制 |
| `daemon.sh` | `handle_request()` | 请求处理（带取消） |
| `daemon.sh` | `cancel_request()` | 请求取消 |
| `cache-manager.sh` | `init_cache_db()` | SQLite 缓存初始化 |
| `cache-manager.sh` | `cache_subgraph()` | 写入缓存（带 LRU 淘汰） |
| `cache-manager.sh` | `get_cached_subgraph()` | 读取缓存（更新访问时间） |
| `cache-manager.sh` | `get_cache_stats()` | 缓存统计 |
| `bug-locator.sh` | `locate_bug_with_impact()` | 带影响分析的 Bug 定位 |
| `augment-context-global.sh` | `build_structured_context()` | 构建结构化上下文 |
| `augment-context-global.sh` | `build_project_profile()` | 构建项目画像 |
| `augment-context-global.sh` | `build_current_state()` | 构建当前状态 |
| `augment-context-global.sh` | `build_task_context()` | 构建任务上下文 |
| `augment-context-global.sh` | `recommend_tools()` | 工具推荐 |
| `augment-context-global.sh` | `get_active_constraints()` | 获取约束 |
| `common.sh` | `detect_devbooks()` | DevBooks 配置检测 |
| `common.sh` | `load_devbooks_context()` | 加载 DevBooks 上下文 |

#### 5.5 依赖变更

| 源 | 目标 | 变更类型 | 说明 |
|----|------|----------|------|
| `adr-parser.sh` | `graph-store.sh` | 新增 | ADR 边写入 |
| `bug-locator.sh` | `impact-analyzer.sh` | 新增 | 影响分析融合 |
| `daemon.sh` | `cache-manager.sh` | 新增 | 预热调用 |
| `daemon.sh` | `hotspot-analyzer.sh` | 新增 | 预热数据源 |
| `intent-learner.sh` | `augment-context-global.sh` | 新增 | 对话上下文注入 |
| `augment-context-global.sh` | `common.sh` | 新增 | DevBooks 检测 |

#### 5.6 分层约束影响

- [x] 本次变更遵守现有分层约束
- [ ] 本次变更需要修改分层约束

**合规性验证**：
- `adr-parser.sh`：core 层，依赖 `graph-store.sh`（core）和 `common.sh`（shared） ✅
- `augment-context-global.sh`：integration 层，依赖 `common.sh`（shared） ✅
- 所有新增依赖遵循 shared ← core ← integration 方向 ✅

---

## 6. C4 Delta（架构增量）

### 6.1 Container Level 增量

```
[NEW] scripts/adr-parser.sh
       │
       ├──→ scripts/graph-store.sh (ADR_RELATED 边写入)
       └──→ scripts/common.sh

[NEW] .github/workflows/arch-check.yml
       └──→ scripts/dependency-guard.sh
       └──→ scripts/boundary-detector.sh

[MODIFIED] scripts/daemon.sh
       │
       ├──→ [NEW] scripts/cache-manager.sh (预热调用)
       └──→ [NEW] scripts/hotspot-analyzer.sh (预热数据源)

[MODIFIED] scripts/bug-locator.sh
       └──→ [NEW] scripts/impact-analyzer.sh (影响分析融合)

[MODIFIED] hooks/augment-context-global.sh
       └──→ [NEW] scripts/common.sh::detect_devbooks() (DevBooks 检测)
```

### 6.2 Data Model 增量

**graph.db edges 表扩展**：

| 字段 | 类型 | 变更 |
|------|------|------|
| edge_type | TEXT | CHECK 约束扩展：新增 IMPLEMENTS, EXTENDS, RETURNS_TYPE, ADR_RELATED |

**新增数据文件**：

| 文件 | 用途 |
|------|------|
| `.devbooks/conversation-context.json` | 对话上下文存储 |
| `.devbooks/adr-index.json` | ADR 索引文件 |
| `.devbooks/subgraph-cache.db` | LRU 子图缓存（SQLite） |

---

## 7. Risk Assessment（风险评估）

### 7.1 技术风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| LRU 缓存内存占用过高 | 中 | 中 | 缓存大小可配置，默认 100 条目 |
| 递归 CTE 性能问题 | 低 | 中 | 最大深度限制（默认 10） |
| ADR 格式多样导致解析失败 | 中 | 低 | 支持 MADR + Nygard，其他格式跳过不报错 |
| 请求取消并发竞态 | 中 | 中 | 使用 flock 文件锁保证原子性 |
| common.sh 变更影响 18 个脚本 | 高 | 高 | 优先编写回归测试，变更最小化 |

### 7.2 高风险依赖链

**common.sh 修改需特别谨慎**：

被 common.sh 直接调用的脚本（18 个）：
- scip-to-graph, graph-store, daemon, intent-learner, vuln-tracker
- impact-analyzer, ast-delta, cod-visualizer, boundary-detector
- hotspot-analyzer, pattern-learner, call-chain, context-layer
- graph-rag, federation-lite, bug-locator, ast-diff, entropy-viz

**缓解措施**：
1. 新增函数（detect_devbooks, load_devbooks_context）为独立函数，不修改现有函数
2. 所有变更需通过全量测试套件
3. 优先编写 common.sh 变更的专项回归测试

---

## 8. Implementation Phases（实施阶段建议）

> **注意**：以下阶段仅为实施顺序建议，**所有工作在本变更包内完成**。

| 阶段 | 模块 | 优先级 | 依赖 |
|------|------|--------|------|
| Phase 1 | MOD-01 边类型扩展 | P0 | 无 |
| Phase 1 | MOD-02 路径查询 | P0 | 无 |
| Phase 2 | MOD-03 ADR 解析 | P1 | Phase 1 (graph-store) |
| Phase 2 | MOD-04 对话上下文 | P1 | 无 |
| Phase 3 | MOD-05 预热机制 | P1 | 无 |
| Phase 3 | MOD-06 请求取消 | P1 | 无 |
| Phase 3 | MOD-07 LRU 缓存 | P0 | 无 |
| Phase 4 | MOD-08 Bug 定位融合 | P1 | 无 |
| Phase 5 | MOD-09 GitHub Action | P2 | 无 |
| Phase 5 | MOD-10 GitLab CI | P2 | 无 |
| Phase 6 | MOD-11 结构化输出 | P1 | 无 |
| Phase 6 | MOD-12 DevBooks 适配 | P1 | 无 |

---

## 9. Evidence Artifacts（证据产物）

### 9.1 证据落点

| 证据类型 | 路径 |
|----------|------|
| Red 基线 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/red-baseline/` |
| Green 最终 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/green-final/` |
| 性能报告 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/performance-report.md` |
| 迁移测试 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/migrate-test.log` |
| LRU PoC 测试 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/lru-poc-test.log` |

### 9.2 性能基准脚本

性能基准测试脚本位于 `evidence/scripts/benchmark.sh`，覆盖：
- 冷启动 vs 预热启动延迟对比
- LRU 缓存命中率
- 重复查询提速倍数

---

## Appendix A: Traceability Matrix（追溯矩阵）

| Proposal AC | Design AC | Test File |
|-------------|-----------|-----------|
| AC-G01 | AC-G01 | tests/graph-store.bats::test_edge_types |
| AC-G01a | AC-G01a | tests/graph-store.bats::test_migrate_* |
| AC-G02 | AC-G02 | tests/graph-store.bats::test_find_path |
| AC-G03 | AC-G03 | tests/adr-parser.bats |
| AC-G04 | AC-G04 | tests/intent-learner.bats::test_conversation_context |
| AC-G05 | AC-G05 | tests/daemon.bats::test_warmup |
| AC-G06 | AC-G06 | tests/daemon.bats::test_cancel_concurrent |
| AC-G07 | AC-G07 | tests/cache-manager.bats::test_lru_* |
| AC-G08 | AC-G08 | tests/bug-locator.bats::test_with_impact |
| AC-G09 | AC-G09 | tests/ci.bats::test_workflow_syntax |
| AC-G10 | AC-G10 | npm test (全量) |
| AC-G11 | AC-G11 | tests/augment-context.bats::test_structured_output |
| AC-G12 | AC-G12 | tests/augment-context.bats::test_devbooks_* |

---

## Appendix B: Open Questions（待确认问题）

| 编号 | 问题 | 状态 | 处理建议 |
|------|------|------|----------|
| OQ-01 | ADR 关联边是否应该存储在单独表？ | Open | 建议复用 edges 表 + edge_type='ADR_RELATED' 区分 |
| OQ-02 | 对话上下文最大保留多少轮？ | Open | 建议 10 轮（可配置，features.yaml） |
| OQ-03 | Bug 定位 CLI 是否需要引入 `locate` 子命令？ | Open | 当前设计回写选择继续使用 `--error` 入口；若需引入 `locate`，应同步更新 spec 与向后兼容策略 |

---

**Design Owner 签名**：Design Owner (Claude)
**日期**：2026-01-16
