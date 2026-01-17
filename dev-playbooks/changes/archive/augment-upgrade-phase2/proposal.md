# 提案：代码智能能力升级 Phase 2（Augment 差距补齐续篇）

> **Change ID**: `augment-upgrade-phase2`
> **Author**: Proposal Author
> **Created**: 2026-01-13
> **Status**: Archived
> **Archived At**: 2026-01-14

---

## 1. Why（问题与目标）

### 1.1 问题陈述

`enhance-code-intelligence` 变更包已完成 Augment 对比文档中的部分升级（热点算法、4 维意图分析、子图检索、边界识别、Pattern Learner、数据流追踪基础、增量索引），但仍存在以下核心差距：

| 差距类型 | 当前状态 | Augment 能力 | 差距评估 |
|----------|----------|--------------|----------|
| 性能延迟 | P95 约 3s | 200-300ms | ❌ 差距大 |
| 缓存策略 | 基于 mtime 单级缓存 | 多级缓存 + 预计算 | ⚠️ 中等差距 |
| 架构合规 | 基础边界检测 | 循环依赖检测 + 架构规则校验 | ⚠️ 中等差距 |
| 多仓库支持 | 单仓库 | 跨仓库依赖追踪 | ❌ 未实现 |
| 上下文深度 | 4 维意图信号 | Commit 语义分类 + Bug 修复历史 | ⚠️ 可增强 |

### 1.2 目标

**延续轻资产原则**，通过以下升级将代码智能能力从 Augment 的 **70%**（enhance-code-intelligence 后）提升至 **85%**：

1. **性能优化**：P95 延迟从 3s 降至 500ms（缓存 + 预计算）
2. **架构守护**：引入循环依赖检测 + 架构规则校验 + Pre-commit 集成
3. **上下文增强**：Commit 语义分类 + Bug 修复历史权重增强热点算法
4. **多仓库基础**：轻量联邦索引（跨仓库 API 契约追踪）

---

## 2. What Changes（范围）

### 2.1 变更范围

本提案涉及 4 个核心模块的新增或增强：

| 模块 | 类型 | 路径 | 说明 |
|------|------|------|------|
| Cache Manager | 新增 | `scripts/cache-manager.sh` | 多级缓存 + TTL + 增量失效 |
| Dependency Guard | 新增 | `scripts/dependency-guard.sh` | 循环依赖检测 + 架构规则校验 |
| Context Layer | 新增 | `scripts/context-layer.sh` | Commit 语义分类 + Bug 修复历史 |
| Federation Lite | 新增 | `scripts/federation-lite.sh` | 跨仓库 API 契约追踪 |
| Hotspot Analyzer | 增强 | `scripts/hotspot-analyzer.sh` | 集成 Bug 修复历史权重 |
| Pre-commit Hook | 新增 | `hooks/pre-commit` | 架构规则校验 + 循环依赖检测 |

### 2.2 非目标（明确排除）

| 排除项 | 原因 |
|--------|------|
| 分布式缓存（Redis） | 重资产，超出单机方案范畴 |
| 中心化联邦索引服务 | 需要独立基础设施 |
| 实时跨仓库同步 | 复杂度高，ROI 低于定时任务 |
| 后台守护进程 | 避免增加运维复杂度 |

### 2.3 影响文件清单

**新增文件（6 个）**：
1. `scripts/cache-manager.sh` - 多级缓存管理
2. `scripts/dependency-guard.sh` - 架构守护
3. `scripts/context-layer.sh` - 上下文层增强
4. `scripts/federation-lite.sh` - 多仓库联邦
5. `config/arch-rules.yaml` - 架构规则定义
6. `hooks/pre-commit` - Pre-commit 钩子

**修改文件（3 个）**：
1. `scripts/hotspot-analyzer.sh` - 集成 Bug 修复历史权重
2. `scripts/common.sh` - 新增缓存相关共享函数
3. `src/server.ts` - 新增 MCP 工具注册

**新增索引/缓存结构（2 个）**：
1. `.devbooks/context-index.json` - 上下文索引（运行时生成）
2. `.devbooks/federation-index.json` - 联邦索引（运行时生成）

---

## 3. Impact（影响分析）

### 3.0 影响范围概览

| 指标 | 数量 | 说明 |
|------|------|------|
| 直接影响文件 | 3 个 | 需修改的现有文件 |
| 新增文件 | 6 个 | 4 个脚本 + 1 个配置 + 1 个钩子 |
| 间接影响文件 | 5+ 个 | 所有使用缓存的脚本 |
| 热点重叠 | 1 个 | hotspot-analyzer.sh（已验证稳定） |

### 3.1 对外契约影响

| 契约 | 影响级别 | 说明 | 兼容性 |
|------|----------|------|--------|
| MCP 工具接口 | **新增** | 新增 2 个工具：`ci_arch_check`、`ci_federation` | ✅ 向后兼容 |
| 现有工具签名 | **无变更** | 现有 8 个工具保持兼容 | ✅ 完全兼容 |
| 脚本接口 | **扩展** | `hotspot-analyzer.sh` 新增 `--with-bug-history` 参数 | ✅ 向后兼容 |
| 配置格式 | **新增** | `config/arch-rules.yaml` 新配置文件 | ✅ 可选配置 |
| Pre-commit Hook | **新增** | 可选安装 | ✅ 可选 |

### 3.2 数据影响

| 数据 | 影响 | 迁移需求 |
|------|------|----------|
| 缓存目录 `.ci-cache/` | 新增 `l2/` 子目录（文件级缓存） | 自动创建 |
| 上下文索引 | 新增 `.devbooks/context-index.json` | 运行时生成 |
| 联邦索引 | 新增 `.devbooks/federation-index.json` | 运行时生成 |

### 3.3 模块依赖影响

```
新增依赖：
  hotspot-analyzer.sh ──→ context-layer.sh (Bug 修复历史)
  bug-locator.sh ────────→ cache-manager.sh (缓存加速)
  graph-rag.sh ──────────→ cache-manager.sh (缓存加速)
  server.ts ─────────────→ dependency-guard.sh (ci_arch_check)
  server.ts ─────────────→ federation-lite.sh (ci_federation)
  hooks/pre-commit ──────→ dependency-guard.sh

依赖方向合规性检查：
  ✅ hotspot-analyzer.sh → context-layer.sh：功能脚本 → 工具脚本，合规
  ✅ 无循环依赖
  ✅ 无反向依赖
```

**R-08 补充：cache-manager.sh 与 cache-utils.sh 关系说明**：

| 模块 | 职责 | 关系 |
|------|------|------|
| `cache-utils.sh`（已有） | 基础缓存函数（get/set/invalidate），单级文件缓存 | **被增强** |
| `cache-manager.sh`（新增） | 多级缓存策略（L1 内存 + L2 文件）、LRU 淘汰、竞态处理、blob hash 失效 | **协作层** |

- **协作模式**：`cache-manager.sh` 内部调用 `cache-utils.sh` 的基础函数，在其上封装多级缓存逻辑
- **向后兼容**：直接使用 `cache-utils.sh` 的现有代码无需修改，新功能脚本推荐使用 `cache-manager.sh`
- **迁移路径**：现有脚本可逐步迁移到 `cache-manager.sh` 以获得性能提升

### 3.4 Transaction Scope

**`None`** - 本变更不涉及数据库事务，所有操作均为文件级读写。

### 3.5 价值信号

| 信号 | 度量方式 | 当前基线 | 目标 |
|------|----------|----------|------|
| P95 延迟 | `time` 命令 | **~2.8s**（测量：`time scripts/bug-locator.sh "test" .` 在 code-intelligence-mcp 项目，15 个 .ts/.sh 文件） | < 500ms |
| 热查询延迟 | 缓存命中 | N/A（无多级缓存） | < 100ms |
| 架构违规检出率 | 测试用例 | 0%（无检测能力） | 95%+ |
| 跨仓库影响分析 | 测试用例 | 不可用 | 可用 |

### 3.6 风险热点叠加分析

| 文件 | 热点等级 | 变更类型 | 综合风险 |
|------|----------|----------|----------|
| `scripts/hotspot-analyzer.sh` | 🟡 中 | 参数扩展 | 低 |
| `scripts/common.sh` | 🟢 低 | 新增函数 | 低 |
| `src/server.ts` | 🟢 低 | 工具注册 | 低 |

### 3.7 Minimal Diff（最小变更策略）

**Phase 1（低风险 - 基础能力）**：
- 新增 `cache-manager.sh`
- 修改 `common.sh` 新增缓存共享函数
- 集成缓存到现有高频脚本

**Phase 2（中风险 - 架构守护）**：
- 新增 `dependency-guard.sh`
- 新增 `config/arch-rules.yaml`
- 新增 `hooks/pre-commit`
- `src/server.ts` 注册 `ci_arch_check`

**Phase 3（中风险 - 上下文增强）**：
- 新增 `context-layer.sh`
- `hotspot-analyzer.sh` 集成 Bug 修复历史

**Phase 4（中风险 - 联邦能力）**：
- 新增 `federation-lite.sh`
- `src/server.ts` 注册 `ci_federation`

### 3.8 Open Questions

| ID | 问题 | 影响范围 | 建议处理方 | 状态 |
|----|------|----------|------------|------|
| OQ1 | 多级缓存 TTL 策略？L1（会话级）/L2（跨会话）分别设多少？ | cache-manager.sh | Design Owner | ✅ 已决策（DP-01：无 TTL，基于 mtime + blob hash） |
| OQ2 | 架构规则违反时是阻断还是警告？ | pre-commit | User | ✅ 已决策（DP-02：默认警告，可配置） |
| OQ3 | 联邦索引的跨仓库路径如何配置？ | federation-lite.sh | Design Owner | ✅ **已决策**：采用**配置文件方式**（`config/federation.yaml`），支持显式路径列表 + glob 自动发现；格式见附录 A |

---

## 4. Risks & Rollback（风险与回滚）

### 4.1 风险清单

| 风险 ID | 风险描述 | 可能性 | 影响 | 缓解措施 |
|---------|----------|--------|------|----------|
| R1 | 缓存失效策略不当导致数据陈旧 | 中 | 高 | 基于 mtime + git blob hash 的精确失效；**竞态处理**：(1) 文件写入中：检测 mtime 变化间隔 < 1s 时视为"写入中"，跳过缓存直接计算；(2) 并发读写：使用文件锁（`flock`）保护缓存写入，读取时若锁定则等待或降级；(3) 原子写入：缓存文件先写临时文件再 `mv` 替换 |
| R2 | 循环依赖检测误报 | 低 | 中 | 白名单机制 + 置信度阈值 |
| R3 | Pre-commit 检查耗时过长影响开发体验 | 中 | 中 | 增量检查 + 可跳过选项 |
| R4 | 联邦索引跨仓库路径配置复杂 | 中 | 低 | 提供默认模板 + 自动发现 |
| R5 | Commit 语义分类规则覆盖不全 | 中 | 低 | 支持自定义规则扩展 |

### 4.2 回滚策略

| 阶段 | 回滚方式 |
|------|----------|
| 开发中 | Git revert 到变更前 commit |
| 部署后 | 功能开关禁用新功能 |
| 数据层 | 删除 `.devbooks/context-index.json`、`.devbooks/federation-index.json`、`.ci-cache/l2/` |

**功能开关设计**：
```yaml
# .devbooks/config.yaml 新增
features:
  # 已有功能开关...
  multi_level_cache: true     # 多级缓存
  dependency_guard: true      # 架构守护
  context_layer: true         # 上下文层增强
  federation_lite: true       # 多仓库联邦
```

---

## 5. Validation（验收锚点）

### 5.1 功能验收

| ID | 验收项 | 验证方法 | 证据落点 |
|----|--------|----------|----------|
| V1 | 多级缓存生效 | 连续两次相同查询，第二次 < 100ms | `evidence/cache-benchmark.log` |
| V2 | 循环依赖检测 | 检测已知循环依赖的测试项目 | `evidence/cycle-detection.log` |
| V3 | 架构规则校验 | 违规代码被正确识别 | `evidence/arch-violation.log` |
| V4 | Commit 语义分类 | 正确分类 fix/feat/refactor | `evidence/commit-classify.log` |
| V5 | Bug 修复历史权重 | 热点分数包含 bug_weight | `evidence/hotspot-enhanced.log` |
| V6 | 联邦索引生成 | 成功扫描跨仓库契约 | `.devbooks/federation-index.json` |
| V7 | Pre-commit 集成 | 钩子正常触发 | `evidence/pre-commit-test.log` |
| V8 | 循环依赖检测误报率 | 误报率 < 5%（测试集 20+ 样本，含 10+ 真循环 + 10+ 非循环） | `evidence/cycle-false-positive.log` |

### 5.2 非功能验收

| ID | 验收项 | 阈值 | 验证方法 |
|----|--------|------|----------|
| N1 | 缓存命中后延迟 | < 100ms | `time` 命令 |
| N2 | 完整查询 P95 | < 500ms | 多次测量取 P95 |
| N3 | Pre-commit 耗时 | < 2s（仅 staged 文件）；< 5s（含一级依赖） | `time` 命令；**检查边界**：默认仅检查 `git diff --cached --name-only` 的 staged 文件；若启用 `--with-deps` 则扩展到一级 import 依赖；**多文件基线**：10 个 staged 文件 + 50 个依赖文件 < 5s |
| N4 | 缓存磁盘占用 | < 50MB（1000 文件项目）；**上限行为**：达到 50MB 时启用 LRU 淘汰（按访问时间删除最旧 20% 缓存条目），日志记录淘汰事件；可配置 `cache.max_size_mb` 和 `cache.eviction_strategy`（lru/fifo/none） | `du -sh`；`evidence/cache-eviction.log` |

### 5.3 回归验收

| ID | 验收项 | 验证方法 |
|----|--------|----------|
| REG1 | 现有 MCP 工具兼容 | 运行现有烟雾测试 |
| REG2 | hotspot-analyzer.sh 基线 | 无 `--with-bug-history` 时输出不变 |
| REG3 | tests/bug-locator.bats | 18 个测试用例全部通过 |

---

## 6. Debate Packet（争议点）

### 6.1 需要辩论的问题

| ID | 争议点 | 正方观点 | 反方观点 | 建议裁决者 |
|----|--------|----------|----------|------------|
| D1 | 是否需要 Pre-commit Hook | 防止架构腐化、自动化检查 | 增加开发摩擦、可能被跳过 | User |
| D2 | 联邦索引是否必须 | 多仓库场景有刚需 | 单仓库项目无用、增加复杂度 | Product Owner |
| D3 | Bug 修复历史的计算周期 | 90 天覆盖足够 | 长期项目可能需要更长 | Technical Lead |

### 6.2 设计性决策

#### DP-01：缓存 TTL 策略 ✅

**选项**：
- A：固定 TTL（L1: 5min, L2: 1h）- 优点：简单可预测；缺点：可能过期过快或过慢
- B：智能 TTL（基于文件变更频率动态调整）- 优点：更精确；缺点：实现复杂
- C：无 TTL（仅基于 mtime + git hash 失效）- 优点：最准确；缺点：需要每次检查文件状态

**Author 建议**：C（无 TTL，基于 mtime + git hash）- 精确失效，避免数据陈旧风险
**用户决策**：✅ 采纳 C

**R-02 补充：git hash 粒度说明**：
- 使用**文件级 blob hash**（`git hash-object <file>`）而非 HEAD commit hash
- 理由：blob hash 精确到文件内容级别，即使 commit 变化但文件内容未变，缓存仍有效
- 缓存 key 格式：`<file_path>:<mtime>:<blob_hash>:<query_hash>`
- 未 tracked 文件：仅使用 `<file_path>:<mtime>:<content_md5>`

#### DP-02：架构违规处理方式 ✅

**选项**：
- A：阻断（违规时 pre-commit 失败）- 优点：强制合规；缺点：可能影响紧急修复
- B：警告（仅输出警告，不阻断）- 优点：柔和；缺点：可能被忽视
- C：可配置（默认警告，可设为阻断）- 优点：灵活；缺点：可能导致配置混乱

**Author 建议**：C（默认警告，可配置为阻断）- 渐进式采用
**用户决策**：✅ 采纳 C

#### DP-03：联邦索引更新策略 ✅

**选项**：
- A：手动触发（`ci_federation --update`）- 优点：可控；缺点：可能遗忘更新
- B：定时任务（每天自动更新）- 优点：自动；缺点：需要后台进程
- C：Git Hook 触发（push 时更新）- 优点：与代码变更同步；缺点：可能增加 push 耗时

**Author 建议**：A（手动触发）- 轻量方案，避免后台进程
**用户决策**：✅ 采纳 A

### 6.3 不确定点

| ID | 不确定点 | 需要的输入 | 影响范围 |
|----|----------|------------|----------|
| U1 | 多仓库路径配置方式 | 用户实际 monorepo 结构 | federation-lite.sh |
| U2 | Commit 语义分类规则是否需要国际化 | 用户提交信息语言 | context-layer.sh |

---

## 7. Decision Log

### 7.1 决策状态

**`Approved`**

### 7.2 需要裁决的问题清单

1. **DP-01**: 缓存 TTL 策略选择？ ✅ 已决策（C：mtime + git hash）
2. **DP-02**: 架构违规处理方式选择？ ✅ 已决策（C：默认警告，可配置）
3. **DP-03**: 联邦索引更新策略选择？ ✅ 已决策（A：手动触发）
4. **D1**: 是否实现 Pre-commit Hook？（待 Challenger/Judge 裁决）
5. **D2**: 是否实现联邦索引？（待 Challenger/Judge 裁决）

### 7.3 裁决记录

| 日期 | 裁决者 | 问题 ID | 裁决结果 | 理由 |
|------|--------|---------|----------|------|
| 2026-01-13 | User | DP-01 | **C：无 TTL，基于 mtime + git hash** | 精确失效，避免数据陈旧风险 |
| 2026-01-13 | User | DP-02 | **C：默认警告，可配置为阻断** | 渐进式采用，灵活可控 |
| 2026-01-13 | User | DP-03 | **A：手动触发** | 轻量方案，避免后台进程 |

### 7.4 Judge 裁决（2026-01-13）

**裁决结果**：`Revise`

**裁决者**：Proposal Judge

**裁决理由**：
1. 缓存失效策略（DP-01）存在未定义的竞态条件处理和 git hash 粒度问题
2. 增量检查边界（N3/R3）定义不一致
3. OQ3（联邦索引配置）为 P4 前置条件，必须决策或延迟
4. 缺失关键 AC：误报率阈值、缓存上限行为

**必须修改项**：

| 序号 | 修改要求 | 落点 | 状态 |
|------|----------|------|------|
| R-01 | 定义 mtime + git hash 失效的竞态处理策略（文件写入中、并发读写） | §4.1 R1 缓解措施 | ✅ 已完成 |
| R-02 | 明确 git hash 粒度：HEAD commit hash 还是文件级 blob hash？ | §6.2 DP-01 补充 | ✅ 已完成 |
| R-03 | 定义 N3 增量检查边界：仅 staged 文件？还是含依赖文件？给出多文件基线。 | §5.2 N3 | ✅ 已完成 |
| R-04 | 补充 AC：误报率 < 5%（循环依赖检测） | §5.1 新增 V8 | ✅ 已完成 |
| R-05 | 补充 AC：缓存达上限行为（LRU 淘汰 / 报警 / 拒绝写入） | §5.2 N4 补充 | ✅ 已完成 |
| R-06 | OQ3 必须决策：联邦索引配置方式（环境变量 / 配置文件 / 自动发现），或将 P4 移至独立提案 | §3.8 OQ3 | ✅ 已完成（配置文件方式） |
| R-07 | 补充 arch-rules.yaml 最小 schema 示例 | 附录 A.1 | ✅ 已完成 |
| R-08 | cache-manager.sh 与 cache-utils.sh 关系说明（协作/替代/共存） | §3.3 依赖影响 | ✅ 已完成 |

**验证要求**（落点在 design.md / evidence/）：

| ID | 验证项 | 证据类型 | 状态 |
|----|--------|----------|------|
| VR-01 | 竞态处理策略需在 design.md 中给出伪代码 | 设计文档 | ⏳ design.md 阶段产出 |
| VR-02 | 提供至少 3 个违规代码样本用于 V3 测试 | `evidence/arch-violation-samples/` | ⏳ test-owner 阶段产出 |
| VR-03 | 提供 hotspot-analyzer.sh 无 Bug 历史时的 golden file | `evidence/baseline-hotspot.golden` | ⏳ test-owner 阶段产出 |
| VR-04 | 补充性能基线实际测量（工具名、项目规模、P95 数据） | §3.5 价值信号 | ✅ 已完成（~2.8s） |

**范围建议**：
- 接受 Challenger 的收缩建议：P1（Cache Manager）+ P3（Context Layer）为必选
- P2（Dependency Guard + Pre-commit）和 P4（Federation Lite）可延迟或拆分为独立提案

### 7.5 Judge 复议裁决（2026-01-13）

**裁决结果**：`Approved`

**裁决者**：Proposal Judge

**裁决理由**：
1. 首轮裁决的 8 项必须修改项（R-01~R-08）已全部完成并验证
2. 关键技术决策已明确：竞态处理策略（flock + 原子写入 + mtime 检测）、blob hash 粒度、LRU 淘汰策略
3. 验收标准完整：V1-V8 功能验收 + N1-N4 非功能验收均有明确阈值和验证方法
4. 配置 schema 已补充：附录 A.1/A.2 提供完整示例
5. 复核发现的遗漏项（M-01~M-03）和非阻断项（NB-01~NB-04）均为低优先级，不影响推进

**后续阶段验证要求**：

| ID | 验证项 | 责任阶段 | 证据落点 |
|----|--------|----------|----------|
| VR-01 | 竞态处理策略伪代码 | design.md | `design.md` |
| VR-02 | 违规代码样本（≥3 个） | test-owner | `evidence/arch-violation-samples/` |
| VR-03 | hotspot-analyzer.sh 无 Bug 历史 golden file | test-owner | `evidence/baseline-hotspot.golden` |

**非阻断改进建议**（建议在 design.md 阶段处理）：

| ID | 建议 | 优先级 |
|----|------|--------|
| NB-02 | N4 缓存上限 50MB 是否支持动态配置 | 低 |
| NB-03 | untracked 文件统一使用 `git hash-object` | 低 |
| NB-04 | 明确 rule severity vs config.on_violation 优先级 | 低 |
| M-02 | LRU "最旧 20%" 计算基准（条目数 vs 大小） | 低 |
| M-03 | federation auto_discover 最大扫描仓库数 | 低 |

---

## 8. 实施优先级建议

基于 ROI 分析，建议按以下顺序实施：

| 优先级 | 模块 | 实现难度 | 价值 | 说明 |
|--------|------|----------|------|------|
| P1 | Cache Manager | 低 | 高 | 性能提升最直接 |
| P2 | Context Layer | 低 | 高 | 热点精度提升 |
| P3 | Dependency Guard | 中 | 高 | 架构质量保障 |
| P4 | Federation Lite | 中 | 中 | 多仓库场景可选 |

---

## 9. 下一步

1. ~~**用户决策**：请对 DP-01、DP-02、DP-03 做出选择~~ ✅ 已完成
2. ~~**Challenger 质疑**：请 `devbooks-proposal-challenger` 对本提案进行质疑~~ ✅ 已完成
3. ~~**Judge 裁决**：请 `devbooks-proposal-judge` 裁决争议点（D1、D2）~~ ✅ 已完成（Revise）
4. ~~**Author 修订**：请 Author 根据 R-01 ~ R-08 修订本提案~~ ✅ 已完成
5. ~~**Challenger 复核**：修订后提交 Challenger 快速复核（仅检查阻断项是否解决）~~ ✅ 已完成
6. ~~**Judge 复议**：复核通过后 Judge 复议裁决~~ ✅ **Approved**
7. **设计文档**：请 `devbooks-design-doc` 产出 `design.md` ← **当前步骤**
8. **实现计划**：请 `devbooks-implementation-plan` 产出 `tasks.md`

---

## 附录 A：配置文件 Schema 示例

### A.1 config/arch-rules.yaml（R-07）

```yaml
schema_version: "1.0.0"

# 架构规则定义
rules:
  # 规则 1：UI 层不能直接访问数据库层
  - name: "ui-no-direct-db"
    description: "UI 组件不能直接导入数据库模块"
    from: "src/ui/**"
    cannot_import:
      - "src/db/**"
      - "src/repository/**"
    severity: "error"  # error | warning

  # 规则 2：工具类不能有业务依赖
  - name: "utils-no-business"
    description: "工具函数不能依赖业务逻辑"
    from: "src/utils/**"
    cannot_import:
      - "src/services/**"
      - "src/domain/**"
    severity: "warning"

  # 规则 3：禁止循环依赖
  - name: "no-circular-deps"
    description: "禁止模块间循环依赖"
    type: "cycle-detection"
    scope: "src/**"
    severity: "error"
    whitelist:
      - "src/types/**"  # 类型定义允许被多处引用

# 全局配置
config:
  # 违规时行为：block（阻断） | warn（警告）
  on_violation: "warn"
  # 忽略的路径
  ignore:
    - "**/*.test.ts"
    - "**/*.spec.ts"
    - "node_modules/**"
```

### A.2 config/federation.yaml（OQ3 决策）

```yaml
schema_version: "1.0.0"

# 联邦索引配置
federation:
  # 显式仓库列表
  repositories:
    - name: "api-contracts"
      path: "../api-contracts"
      contracts:
        - "**/*.proto"
        - "**/openapi.yaml"
    - name: "shared-types"
      path: "../shared-types"
      contracts:
        - "src/types/**/*.ts"

  # 自动发现（glob 模式）
  auto_discover:
    enabled: true
    search_paths:
      - "../*"           # 同级目录
      - "../../libs/*"   # 上级 libs 目录
    contract_patterns:
      - "**/*.proto"
      - "**/openapi.yaml"
      - "**/swagger.json"
      - "**/*.graphql"

  # 索引更新策略
  update:
    trigger: "manual"  # manual | on-push | scheduled
    # scheduled_cron: "0 2 * * *"  # 每天 2:00（仅 scheduled 模式）
```
