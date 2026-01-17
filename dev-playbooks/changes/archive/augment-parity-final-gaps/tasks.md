# 编码计划（Implementation Plan）：augment-parity-final-gaps

Truth Root：`dev-playbooks/specs/`；Change Root：`dev-playbooks/changes/`

> **Change ID**: `augment-parity-final-gaps`  
> **Planner**: Codex（Implementation Plan）  
> **Date**: 2026-01-16  
> **Inputs**（真理输入）：
> - 设计文档：`dev-playbooks/changes/augment-parity-final-gaps/design.md`
> - 规格增量：
>   - `dev-playbooks/changes/augment-parity-final-gaps/specs/graph-store-enhancement/spec.md`
>   - `dev-playbooks/changes/augment-parity-final-gaps/specs/adr-parser/spec.md`
>   - `dev-playbooks/changes/augment-parity-final-gaps/specs/conversation-context/spec.md`
>   - `dev-playbooks/changes/augment-parity-final-gaps/specs/structured-context-output/spec.md`
>   - `dev-playbooks/changes/augment-parity-final-gaps/specs/devbooks-adapter/spec.md`
>   - `dev-playbooks/changes/augment-parity-final-gaps/specs/subgraph-lru-cache/spec.md`
>   - `dev-playbooks/changes/augment-parity-final-gaps/specs/daemon-enhancement/spec.md`
>   - `dev-playbooks/changes/augment-parity-final-gaps/specs/bug-locator-fusion/spec.md`
>   - `dev-playbooks/changes/augment-parity-final-gaps/specs/ci-cd-integration/spec.md`

## 模式选择

默认使用 **主线计划模式**。

## 主线计划区 (Main Plan Area)

### MP1：图存储与检索增强（MOD-01, MOD-02）

**Why**：补齐 Augment 对等的图能力底座：更丰富的类型关系边 + 最短路径查询 + 平滑迁移。  
**Deliverables**：新增/扩展边类型（含 `ADR_RELATED`）、`graph-store.sh migrate`、`graph-store.sh find-path`、必要的 feature/参数开关。  
**影响范围（Files/Modules）**：`scripts/scip-to-graph.sh`、`scripts/graph-store.sh`、SQLite `graph.db` schema/迁移逻辑。  
**验收标准（AC）**：`AC-G01`、`AC-G01a`、`AC-G02`。  
**依赖（Dependencies）**：Test Owner 提供/补齐对应验收测试（如设计中提及的 `tests/graph-store.bats` 用例）。  
**风险（Risks）**：Schema 迁移失败/数据丢失风险；多语言边类型支持差异导致回归风险。

- [x] MP1.1 扩展 `edge_type` 支持 IMPLEMENTS/EXTENDS/RETURNS_TYPE/ADR_RELATED（AC-G01；锚点：`npm test` + `sqlite3 .devbooks/graph.db` 统计校验）
- [x] MP1.2 增加 `graph-store.sh migrate --check/--apply/--status` 与备份机制（AC-G01a；锚点：`npm test` + 备份文件存在性检查）
- [x] MP1.3 增加 `graph-store.sh find-path`（BFS/递归 CTE、最大深度默认 10、无路径安全返回）（AC-G02；锚点：`npm test`）

### MP2：ADR 解析与关联（MOD-03）

**Why**：将架构决策（ADR）变为可检索的“架构上下文”，并与代码图连接，提升检索与推理质量。  
**Deliverables**：新增 `scripts/adr-parser.sh`（发现/解析/索引/关联）、生成 `.devbooks/adr-index.json`、写入 `ADR_RELATED` 边。  
**影响范围（Files/Modules）**：`scripts/adr-parser.sh`、`scripts/graph-store.sh`（写边入口/复用）、`.devbooks/adr-index.json`。  
**验收标准（AC）**：`AC-G03`。  
**依赖（Dependencies）**：依赖 MP1.1 的 `ADR_RELATED` edge_type 可用；Test Owner 创建 `tests/adr-parser.bats`（设计引用）。  
**风险（Risks）**：ADR 格式多样导致解析失败；关键词提取/关联过宽导致噪音上升（需降级与过滤）。

- [x] MP2.1 实现 ADR 发现与解析（MADR + Nygard），输出 JSON（AC-G03；锚点：`npm test`）
- [x] MP2.2 实现关键词提取 + graph.db 节点匹配，并生成 `ADR_RELATED` 边（AC-G03；锚点：`npm test` + SQLite 边计数校验）
- [x] MP2.3 生成并增量更新 `.devbooks/adr-index.json`（按 mtime），缺失 ADR 目录时优雅返回（AC-G03；锚点：`npm test`）

### MP3：对话历史信号累积（MOD-04）

**Why**：将“多轮对话的焦点/意图”转为可用信号，提升搜索与分析的连续性与相关性。  
**Deliverables**：对话上下文文件 `.devbooks/conversation-context.json`、会话管理命令、对话连续性加权信号输出。  
**影响范围（Files/Modules）**：`scripts/intent-learner.sh`（存储/读取/加权）、与消费方的接口（由实现阶段确定）。  
**验收标准（AC）**：`AC-G04`。  
**依赖（Dependencies）**：Test Owner 可能需扩展/新增 `tests/intent-learner.bats` 对应用例（设计引用）。  
**风险（Risks）**：上下文文件膨胀/并发写入；加权策略误伤排序（需可配置与阈值保护）。

- [x] MP3.1 实现对话上下文持久化与 schema（含 max_turns=10 FIFO、max_focus_symbols=50 淘汰）（AC-G04；锚点：`npm test`）
- [x] MP3.2 实现会话管理子命令（new/resume/list/clear）并保证无文件时返回空结构（AC-G04；锚点：`npm test`）
- [x] MP3.3 输出"对话连续性加权"信号并接入排序链路（保持可配置且加权不超过原始分数 50%）（AC-G04；锚点：`npm test`）

### MP4：守护进程增强：预热 + 请求取消（MOD-05, MOD-06）

**Why**：降低冷启动延迟并提升交互实时性，避免并发请求浪费资源。  
**Deliverables**：`daemon.sh warmup`、预热状态查询、取消信号文件协议与并发安全实现、配置项落地（`config/features.yaml`）。  
**影响范围（Files/Modules）**：`scripts/daemon.sh`、`scripts/cache-manager.sh`、`scripts/hotspot-analyzer.sh`、`config/features.yaml`。  
**验收标准（AC）**：`AC-G05`、`AC-G06`。  
**依赖（Dependencies）**：预热优先依赖 MP5（LRU 缓存）以兑现跨进程收益；Test Owner 维护 `tests/daemon.bats` 用例（已存在）。  
**风险（Risks）**：取消竞态导致误杀/资源泄漏；预热任务影响常规请求（需后台异步、超时与降级）。

- [x] MP4.1 实现 warmup（后台异步、超时默认 30s、失败不阻塞），并写入可查询状态（AC-G05；锚点：`npm test`）
- [x] MP4.2 实现请求取消协议（`.devbooks/cancel/<request_id>` + `flock` 原子性 + 清理）并满足 100ms 生效目标（AC-G06；锚点：`npm test`）
- [x] MP4.3 在 `config/features.yaml` 增加 warmup/cancel 相关开关与默认值（AC-G05/AC-G06；锚点：`npm test` + 手工配置检查清单）

### MP5：子图 LRU 缓存（MOD-07）

**Why**：让热点子图可跨进程复用，支撑预热与影响分析等高频图查询的性能目标。  
**Deliverables**：`.devbooks/subgraph-cache.db`（WAL）、LRU 淘汰、cache key 规范、统计（命中率等）、跨进程可用。  
**影响范围（Files/Modules）**：`scripts/cache-manager.sh`、`.devbooks/subgraph-cache.db`、（可能）子图生产/消费脚本的调用点。  
**验收标准（AC）**：`AC-G07`。  
**依赖（Dependencies）**：Test Owner 维护 `tests/cache-manager.bats`（已存在）；MP4 warmup 与 MP6 影响分析可复用缓存。  
**风险（Risks）**：SQLite 并发/锁争用；缓存污染（key 设计不稳定）导致命中率虚高或错误复用。

- [x] MP5.1 在 `cache-manager.sh` 实现 SQLite 缓存初始化（WAL）与表结构（AC-G07；锚点：`npm test`）
- [x] MP5.2 实现 cache-get/cache-set（读更新 access_time、写入同事务淘汰、MAX_SIZE 默认 100）（AC-G07；锚点：`npm test`）
- [x] MP5.3 实现 stats（条目数/命中率/大小）与跨进程读写一致性（AC-G07；锚点：`npm test`）

### MP6：Bug 定位 + 影响分析融合（MOD-08）

**Why**：把“影响范围”纳入 Bug 定位结果，提升定位置信度与可行动性，同时保持向后兼容。  
**Deliverables**：`bug-locator.sh --with-impact`、`--impact-depth`、Top 10 限制与超时策略、融合后的输出 schema。  
**影响范围（Files/Modules）**：`scripts/bug-locator.sh`、`scripts/impact-analyzer.sh`（调用契约）、（可选）复用 MP5 子图缓存。  
**验收标准（AC）**：`AC-G08`。  
**依赖（Dependencies）**：Test Owner 维护 `tests/bug-locator.bats`（已存在）；影响分析脚本输出 JSON 契约稳定。  
**风险（Risks）**：性能退化（每个候选都跑影响分析）；输出兼容性破坏（必须保持无参数时原格式）。

- [x] MP6.1 增加 `--with-impact/--impact-depth` 参数与向后兼容输出（AC-G08；锚点：`npm test`）
- [x] MP6.2 融合 impact 输出并按公式重算分数（含 Top 10 限制与单次 5s 超时降级）（AC-G08；锚点：`npm test`）
- [x] MP6.3（可选但高 ROI）复用子图 LRU 缓存以降低影响分析成本（AC-G08；锚点：`npm test` + 性能基准对比）

### MP7：结构化上下文输出（MOD-11）

**Why**：把“上下文”从自由文本升级为稳定结构，便于模型消费与后续演进。  
**Deliverables**：5 层结构化输出（JSON 默认 + text 可选）、字段来源落地（hotspot/commit/意图/约束）、输出 schema 稳定。  
**影响范围（Files/Modules）**：`hooks/augment-context-global.sh`、`scripts/hotspot-analyzer.sh`、`scripts/intent-learner.sh`、（可能）Git 调用。  
**验收标准（AC）**：`AC-G11`。  
**依赖（Dependencies）**：Test Owner 创建 `tests/augment-context.bats`（设计引用）；MP8 DevBooks 适配会注入部分字段。  
**风险（Risks）**：输出字段不稳定导致下游使用困难；在非 Git 环境或缺少可选工具时需优雅降级。

- [x] MP7.1 在 `augment-context-global.sh` 输出 5 层结构化 JSON（project_profile/current_state/task_context/recommended_tools/constraints）（AC-G11；锚点：`npm test`）
- [x] MP7.2 支持 `--format text` 并保持默认 JSON（AC-G11；锚点：`npm test`）
- [x] MP7.3 实现 current_state 数据源（hotspot_files Top5、recent_commits Top3）并限制输出规模（AC-G11；锚点：`npm test`）

### MP8：DevBooks 适配（MOD-12）

**Why**：自动识别 DevBooks 项目并提取高信噪比真理信息，为“增强上下文”提供确定性来源。  
**Deliverables**：DevBooks 检测（含缓存 60s）、真理信息提取（project-profile/glossary/c4/active changes）、注入结构化输出、降级策略。  
**影响范围（Files/Modules）**：`scripts/common.sh`（新增函数）、`hooks/augment-context-global.sh`、（可能）搜索/意图模块的 query 扩展点。  
**验收标准（AC）**：`AC-G12`。  
**依赖（Dependencies）**：高风险：`common.sh` 被 18 个脚本直接调用（见“风险与边界”）；Test Owner 创建 `tests/augment-context.bats`（设计引用）。  
**风险（Risks）**：`common.sh` 变更引发全局回归；提取逻辑读取文件失败需严格降级不报错。

- [x] MP8.1 在 `common.sh` 新增 `detect_devbooks()`（按优先级探测，缓存 60s）与 `load_devbooks_context()`（只新增、不修改既有函数）（AC-G12；锚点：`npm test`）
- [x] MP8.2 提取 project-profile/glossary/c4/active changes 并注入结构化输出字段（AC-G12；锚点：`npm test`）
- [x] MP8.3 实现降级策略：缺失任一文件时 INFO 记录并继续输出基础上下文（AC-G12；锚点：`npm test`）

### MP9：企业级治理：CI/CD 架构检查模板（MOD-09, MOD-10）

**Why**：把架构约束与依赖规则前移到 PR/MR 阶段，防止结构熵劣化。  
**Deliverables**：`.github/workflows/arch-check.yml`、`.gitlab-ci.yml.template`、JSON 结果输出约定、actionlint 语法通过。  
**影响范围（Files/Modules）**：GitHub/GitLab CI 配置文件、已有脚本 `scripts/dependency-guard.sh` 与 `scripts/boundary-detector.sh` 的调用方式（不改行为为主）。  
**验收标准（AC）**：`AC-G09`。  
**依赖（Dependencies）**：actionlint 可用性（本地或 CI 环境）；不引入新依赖时需给出替代校验方式。  
**风险（Risks）**：CI 环境与本地差异导致误报；PR 评论能力依赖权限（需可选开关或降级）。

- [x] MP9.1 新增 GitHub Action：PR 触发 + 运行 cycles/orphan/rules 检查并输出 JSON（AC-G09；锚点：`actionlint` + `npm test`）
- [x] MP9.2 新增 GitLab CI 模板并文档说明"复制启用"方式（AC-G09；锚点：`npm test` + 人工检查清单）

### MP10：文档、证据与收尾（AC-G10 + DoD）

**Why**：把功能/契约/结构/证据闭环落地，确保可交付与可归档。  
**Deliverables**：README 与 `docs/Augment.md` 同步、（如需）新增 `CHANGELOG.md`、evidence 目录与性能基准脚本、全量回归通过。  
**影响范围（Files/Modules）**：`README.md`、`docs/Augment.md`、`dev-playbooks/changes/augment-parity-final-gaps/evidence/**`、（可选）`CHANGELOG.md`。  
**验收标准（AC）**：`AC-G10`（全量 `npm test` 通过）+ 设计文档第 9 章证据落点齐备。  
**依赖（Dependencies）**：Test Owner 在独立会话产出 Red 基线与 `verification.md`；Coder 在独立会话产出 Green 证据。  
**风险（Risks）**：文档与实际 CLI/输出不一致；证据落点写错导致归档失败。

- [x] MP10.1 同步用户文档：在 `README.md` 与 `docs/Augment.md` 补齐新增命令/参数/输出结构说明（AC-G10；锚点：文档检查清单 + `npm test`）
- [x] MP10.2 建立证据目录并记录基准与迁移日志（按设计第 9 章路径）（AC-G10；锚点：证据文件存在性检查清单）
- [x] MP10.3（LSC）新增变更包脚本目录并提供批量验证/复现脚本（例如 `evidence/scripts/benchmark.sh`）（AC-G10；锚点：脚本可重复执行 + 证据产出落点正确）
- [x] MP10.4 全量回归：`npm test` 全绿，并输出 Green 证据到 `evidence/green-final/`（AC-G10；锚点：测试报告/日志归档）

## 临时计划区 (Temporary Plan Area)

当前无临时任务。若出现计划外 P0 事项，必须以“最小修复范围 + 回归锚点”形式追加到本区，且不得破坏主线架构约束。

模板（追加时使用）：
- [ ] TP1 紧急任务描述（触发原因/最小范围/回归锚点/回滚条件）

---

## 计划细化区

## Scope & Non-goals

**Scope（本次覆盖）**：
- 设计文档定义的 12 个模块（MOD-01~MOD-12）在“轻资产”范围内落地。
- 所有新增能力通过可选参数或 feature 开关控制，保持向后兼容（CON-TECH-004）。

**Non-goals（不做）**（来自设计 1.4）：
- 迁移到 Neo4j
- IDE 插件开发
- 实时文件监听 daemon
- 分布式图数据库
- 自研 LLM 模型

**Assumptions（必要假设）**：
- 本仓库以 `config/features.yaml` 作为 feature 开关主要落点；若实际开关机制不同，以“新增不破坏”的方式适配并在实现时回写到设计/规格增量。
- CI 语法校验工具 `actionlint` 在目标环境可用；若不可用，则以“CI 运行时校验/替代 lint”作为降级策略并记录证据。
- `CHANGELOG.md` 当前不存在；若项目不希望引入 changelog，则将 MP10 中该交付物替换为 “release notes 写入 README 或 dev-playbooks/changes 内文档”。

## Architecture Delta

**新增/修改容器与依赖**（来自设计 5/6 章）：
- 新增：`scripts/adr-parser.sh`；新增：`.github/workflows/arch-check.yml`；新增：`.gitlab-ci.yml.template`。
- 修改：`scripts/scip-to-graph.sh`、`scripts/graph-store.sh`、`scripts/intent-learner.sh`、`scripts/daemon.sh`、`scripts/cache-manager.sh`、`scripts/bug-locator.sh`、`hooks/augment-context-global.sh`、`scripts/common.sh`。

**依赖方向约束**：
- 维持 shared ← core ← integration 方向；禁止 `scripts/*.sh → src/*.ts`（CON-TECH-002）。

## Data Contracts

**graph.db**：
- `edges.edge_type`：扩展 CHECK 约束，新增 `IMPLEMENTS`、`EXTENDS`、`RETURNS_TYPE`、`ADR_RELATED`（设计 6.2）。
- 迁移策略：提供 `graph-store.sh migrate`，迁移前备份，迁移在事务中完成（设计 AC-G01a / Spec REQ-GSE-005）。

**新增数据文件**（设计 6.2）：
- `.devbooks/conversation-context.json`：对话上下文（Spec REQ-CC-001/002）。
- `.devbooks/adr-index.json`：ADR 索引（Spec REQ-ADR-007）。
- `.devbooks/subgraph-cache.db`：子图 LRU 缓存（Spec REQ-SLC-001/002）。

**结构化输出契约**：
- 5 层字段与限制：`project_profile/current_state/task_context/recommended_tools/constraints`（Spec REQ-SCO-001~007；设计 AC-G11）。

## Milestones

- M1（图能力底座）：MP1 完成并通过 `AC-G01/AC-G01a/AC-G02`。
- M2（性能底座）：MP5 完成并通过 `AC-G07`；MP4 warmup 可复用缓存并通过 `AC-G05/AC-G06`。
- M3（上下文增强）：MP2/MP3/MP7/MP8 完成并通过 `AC-G03/AC-G04/AC-G11/AC-G12`。
- M4（分析融合）：MP6 完成并通过 `AC-G08`。
- M5（治理与收尾）：MP9 完成并通过 `AC-G09`；MP10 完成并通过 `AC-G10` + 证据闭环。

## Work Breakdown

**建议 PR 切分（可并行点）**：
- PR-A：MP1（图存储与检索增强）
- PR-B：MP5（子图 LRU 缓存）
- PR-C：MP4（daemon warmup/cancel，依赖 PR-B 可先做框架后做集成）
- PR-D：MP6（bug-locator 融合，依赖 PR-B 可选集成）
- PR-E：MP2（adr-parser，依赖 PR-A 的 ADR_RELATED）
- PR-F：MP3（intent-learner 对话上下文）
- PR-G：MP7+MP8（augment-context 结构化输出 + DevBooks 适配；注意 `common.sh` 风险，建议先小步合入 MP8.1）
- PR-H：MP9（CI/CD 模板）
- PR-I：MP10（文档与证据）

**断点续做协议**：
- 每个 MP 子任务建议独立合入；若单子任务预计 >200 行改动，优先拆分为“契约/接口先行”与“实现/性能优化”两步，并在 Guardrail Conflicts 说明原因。

## Deprecation & Cleanup

- 不移除既有 CLI/输出；所有新能力必须提供默认关闭或不影响默认路径的行为（CON-TECH-004、AC-G10）。
- 若引入新数据文件（`.devbooks/*`），需明确清理命令或在 README 中说明“可安全删除并自动重建”的范围与边界。

## Dependency Policy

- 默认不新增 npm 依赖；若必须新增，需在 proposal/design 中补充 Impact 与回滚策略，并将新增依赖纳入 `npm test`/lint 闸门。
- CLI 依赖（如 `sqlite3`、`jq`、`rg`、`actionlint`）必须提供“存在则用、缺失则降级/提示”的策略，避免硬崩溃。

## Quality Gates

- 行为闸门：`npm test`（AC-G10）。
- 契约闸门：结构化输出 JSON schema 可验证；CLI 输出向后兼容（AC-G11/AC-G12/AC-G08）。
- 结构闸门：分层依赖方向不被破坏（CON-TECH-002）；CI 模板能运行依赖检查脚本（AC-G09）。
- 数据闸门：迁移可回滚/可重跑且不丢数据（AC-G01a）。

## Guardrail Conflicts

- LSC 触发：本变更预计触达 >10 文件与多模块，必须通过“分片 PR + 脚本化验证（MP10.3）”控制风险。
- `common.sh` 高风险：被 18 个脚本直接调用（设计 7.2 列表：scip-to-graph、graph-store、daemon、intent-learner、vuln-tracker、impact-analyzer、ast-delta、cod-visualizer、boundary-detector、hotspot-analyzer、pattern-learner、call-chain、context-layer、graph-rag、federation-lite、bug-locator、ast-diff、entropy-viz）。策略：只新增函数、不改既有函数签名/行为；先合入最小变更并跑全量测试。

## Observability

- 对降级路径（DevBooks 检测失败、ADR 目录缺失、缓存未命中、取消触发）统一记录 INFO/DEBUG 级别日志，便于排障但不污染默认输出。
- 对 warmup、缓存命中率、影响分析超时记录可聚合指标（最小实现可写入 `cache-manager.sh stats` 与 `daemon.sh status` 输出）。

## Rollout & Rollback

- 默认关闭或不影响默认路径：新参数（如 `--with-impact`、`--format`）需显式启用；warmup/cancel 由 `config/features.yaml` 控制。
- 回滚策略：
  - graph.db 迁移：使用自动备份文件回滚；`migrate --status` 可确认版本。
  - LRU 缓存：删除 `.devbooks/subgraph-cache.db` 应可安全重建。
  - 对话上下文：删除 `.devbooks/conversation-context.json` 应可安全重建。

## Risks & Edge Cases

- 路径查询：环路/深度上限/无路径返回必须稳定；避免递归 CTE 退化到全表扫描。
- 取消机制：确保取消后子进程与锁释放；避免误取消新请求。
- ADR 解析：非 MADR/Nygard 文档应跳过不报错；关键词提取避免过短/通用词。
- 结构化输出：字段缺失时必须保持 JSON schema 有效（用空数组/空对象代替），不得输出不完整 JSON。

## Open Questions（<=3）

1. OQ-01：ADR 关联边是否应存储在单独表？（设计建议：复用 edges 表 + `edge_type='ADR_RELATED'`）
2. OQ-02：对话上下文最大保留多少轮？（设计建议：默认 10，可配置）
3. OQ-03：是否引入 `CHANGELOG.md` 作为长期规范？若否，release notes 的权威落点应选 `README.md` 还是 `dev-playbooks/specs/_meta/project-profile.md`？

## 断点区 (Context Switch Breakpoint Area)

（本区用于后续会话切换时记录上下文，初始为空。）
