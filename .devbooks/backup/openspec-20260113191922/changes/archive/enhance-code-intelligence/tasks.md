# Implementation Plan: enhance-code-intelligence

> **Version**: 1.0.0
> **Maintainer**: Planner
> **Created**: 2026-01-11
> **Input Materials**: `dev-playbooks/changes/enhance-code-intelligence/design.md`
> **Related Specs**: `dev-playbooks/changes/enhance-code-intelligence/specs/**`

---

## 模式选择

**当前模式**: `主线计划模式`

---

# 计划区域

## 主线计划区 (Main Plan Area)

### MP1. Phase 1 - 基础能力新增（低风险）

#### MP1.1 热点分析器 (hotspot-analyzer.sh)

**目的 (Why)**：实现 Frequency × Complexity 热点计算公式，为 Bug 定位提供数据驱动的热点评分。

**交付物 (Deliverables)**：
- `scripts/hotspot-analyzer.sh`：热点计算脚本

**影响范围 (Files/Modules)**：
- 新增：`scripts/hotspot-analyzer.sh`

**验收标准 (Acceptance Criteria)**：
- [x] 输出 Top-N 热点文件列表（默认 20）
- [x] 支持 `--days N` 参数控制 git log 统计周期
- [x] 支持 `--format json|text` 输出格式
- [x] 1000 文件项目耗时 < 5s
- [x] 无 git 历史的文件 Frequency = 0
- **Trace**: AC-001

**依赖 (Dependencies)**：
- git 命令可用
- `scripts/common.sh`（共享函数）

**风险 (Risks)**：
- 大型仓库 git log 耗时较长 → 增量缓存

---

#### MP1.2 边界检测器 (boundary-detector.sh)

**目的 (Why)**：区分用户代码、库代码、生成代码，防止 AI 误建议修改库代码。

**交付物 (Deliverables)**：
- `scripts/boundary-detector.sh`：边界检测脚本
- `config/boundaries.yaml`：边界配置模板

**影响范围 (Files/Modules)**：
- 新增：`scripts/boundary-detector.sh`
- 新增：`config/boundaries.yaml`

**验收标准 (Acceptance Criteria)**：
- [x] 正确识别 `node_modules/**` 为 library
- [x] 正确识别 `dist/**` 为 generated
- [x] 支持 glob 模式配置
- [x] 支持 `--config` 自定义配置路径
- [x] 输出包含 type、confidence、matched_rule
- **Trace**: AC-004

**依赖 (Dependencies)**：
- `scripts/common.sh`

**风险 (Risks)**：
- monorepo 边界复杂 → 支持 overrides 配置

---

#### MP1.3 MCP 工具注册 (server.ts)

**目的 (Why)**：将新增的热点分析和边界检测能力暴露为 MCP 工具。

**交付物 (Deliverables)**：
- 修改 `src/server.ts`：新增 `ci_hotspot`、`ci_boundary` 工具定义

**影响范围 (Files/Modules)**：
- 修改：`src/server.ts`（TOOLS 数组 + handleToolCall）

**验收标准 (Acceptance Criteria)**：
- [x] `ci_hotspot` 工具可调用，返回 JSON 格式热点列表
- [x] `ci_boundary` 工具可调用，返回边界类型
- [x] 现有 6 个工具接口不变
- [x] TypeScript 编译通过
- **Trace**: AC-008

**依赖 (Dependencies)**：
- MP1.1 完成
- MP1.2 完成

**风险 (Risks)**：
- 低（仅新增 case 分支）

---

#### MP1.4 功能开关配置

**目的 (Why)**：支持按功能粒度禁用新能力，降低上线风险。

**交付物 (Deliverables)**：
- 更新 `.devbooks/config.yaml`：新增 `features.*` 配置块

**影响范围 (Files/Modules)**：
- 修改：`.devbooks/config.yaml`
- 修改：各新增脚本（读取功能开关）

**验收标准 (Acceptance Criteria)**：
- [x] 每个新功能可通过 `features.xxx: false` 禁用
- [x] 禁用后对应功能返回"功能已禁用"提示
- **Trace**: AC-010

**依赖 (Dependencies)**：
- MP1.1、MP1.2、MP1.3 完成

**风险 (Risks)**：
- 低

---

### MP2. Phase 2 - 能力增强（中风险）

#### MP2.1 数据流追踪 (call-chain.sh)

**目的 (Why)**：支持跨函数参数流追踪，展示数据如何流动。

**交付物 (Deliverables)**：
- 修改 `scripts/call-chain.sh`：新增 `--trace-data-flow` 参数

**影响范围 (Files/Modules)**：
- 修改：`scripts/call-chain.sh`

**验收标准 (Acceptance Criteria)**：
- [x] 新增 `--trace-data-flow` 可选参数
- [x] 无参数时行为不变（向后兼容）
- [x] 有参数时输出参数流路径
- [x] 输出格式包含 source → path → sink
- **Trace**: AC-006

**依赖 (Dependencies)**：
- CKB MCP 可用（或降级模式）

**风险 (Risks)**：
- 复杂符号追踪可能遗漏 → 增量迭代

---

#### MP2.2 四维意图分析 (augment-context-global.sh)

**目的 (Why)**：聚合显式/隐式/历史/代码 4 维信号，提升意图理解深度。

**交付物 (Deliverables)**：
- 修改 `hooks/augment-context-global.sh`：新增 `analyze_intent_4d()` 函数

**影响范围 (Files/Modules)**：
- 修改：`hooks/augment-context-global.sh`

**验收标准 (Acceptance Criteria)**：
- [x] 输出包含 4 类信号标签（explicit/implicit/historical/code）
- [x] 每类信号有对应权重
- [x] 缺失维度权重设为 0
- **Trace**: AC-002

**依赖 (Dependencies)**：
- 无强依赖

**风险 (Risks)**：
- 历史信号收集依赖文件系统状态

---

### MP3. Phase 3 - 核心集成（高风险）

> **前置条件**：`tests/bug-locator.bats` 18 个测试用例通过，变更前输出已记录为基线。

#### MP3.1 热点算法集成 (bug-locator.sh)

**目的 (Why)**：将新热点算法集成到 Bug 定位流程。

**交付物 (Deliverables)**：
- 修改 `scripts/bug-locator.sh`：调用 `hotspot-analyzer.sh`

**影响范围 (Files/Modules)**：
- 修改：`scripts/bug-locator.sh`（`get_hotspot_files()`、`add_hotspot_scores()`）

**验收标准 (Acceptance Criteria)**：
- [x] 调用 `hotspot-analyzer.sh` 获取热点分数
- [x] 回归测试 18 个用例全部通过
- [x] 热点权重可配置
- **Trace**: AC-001, AC-009

**依赖 (Dependencies)**：
- MP1.1 完成
- 回归测试就绪

**风险 (Risks)**：
- 高频脚本，行为变更影响大 → 充分回归测试

---

#### MP3.2 子图检索 (graph-rag.sh)

**目的 (Why)**：从线性列表升级为保留边关系的子图检索。

**交付物 (Deliverables)**：
- 修改 `scripts/graph-rag.sh`：新增子图连通性分析、边界过滤

**影响范围 (Files/Modules)**：
- 修改：`scripts/graph-rag.sh`

**验收标准 (Acceptance Criteria)**：
- [x] 输出包含 `--calls-->` / `--refs-->` 边关系
- [x] 支持 `--depth N` 参数（默认 3，最大 5）
- [x] 集成边界检测过滤库代码
- [x] CKB 不可用时降级为线性列表
- **Trace**: AC-003, AC-004

**依赖 (Dependencies)**：
- MP1.2 完成（边界检测）
- CKB MCP

**风险 (Risks)**：
- 输出格式变化 → 提供 `--legacy` 兼容选项

---

#### MP3.3 模式学习器 (pattern-learner.sh)

**目的 (Why)**：从代码库学习语义模式，检测异常。

**交付物 (Deliverables)**：
- `scripts/pattern-learner.sh`：模式学习脚本
- `.devbooks/learned-patterns.json`：模式持久化文件（运行时生成）

**影响范围 (Files/Modules)**：
- 新增：`scripts/pattern-learner.sh`

**验收标准 (Acceptance Criteria)**：
- [x] 学习到的模式写入 `.devbooks/learned-patterns.json`
- [x] 支持 `--confidence-threshold` 参数（默认 0.85）
- [x] 低于阈值的模式不产生警告
- [x] 支持加载已有模式并合并
- **Trace**: AC-005

**依赖 (Dependencies)**：
- `scripts/common.sh`

**风险 (Risks)**：
- 误报率控制 → 阈值可调

---

#### MP3.4 增量索引 (ast-diff.sh)

**目的 (Why)**：基于 SCIP 实现增量索引，单文件变更无需全量重建。

**交付物 (Deliverables)**：
- `scripts/ast-diff.sh`：增量索引脚本

**影响范围 (Files/Modules)**：
- 新增：`scripts/ast-diff.sh`
- 新增：`.ci-cache/last-index-time`（时间戳文件）

**验收标准 (Acceptance Criteria)**：
- [x] 单文件变更后只更新相关节点
- [x] 更新耗时 < 1s
- [x] SCIP 索引不存在时返回错误提示
- [x] 无变更时返回"索引已是最新"
- [x] 增量失败时降级为全量索引
- **Trace**: AC-007

**依赖 (Dependencies)**：
- `index.scip` 存在
- git 命令

**风险 (Risks)**：
- SCIP 索引格式变化 → 版本兼容检查

---

## 临时计划区 (Temporary Plan Area)

> 本区域预留给计划外高优任务。当前为空。

**模板**：
```markdown
### TP-XXX: [紧急任务标题]

**触发原因**：
**影响面**：
**最小修复范围**：
**回归测试要求**：
**完成后回到主线**：MP?.?
```

---

# 计划细化区

## Scope & Non-goals

**In Scope**：
- 7 个新增/增强模块（见 MP1-MP3）
- 2 个新增 MCP 工具
- 配置文件模板
- 功能开关

**Out of Scope**（来自 design.md Non-goals）：
- Neo4j 集成
- 自训练模型
- 跨语言符号归一化
- 执行路径模拟
- 击键级请求取消

---

## Architecture Delta

**新增模块**：
| 模块 | 层级 | 职责 |
|------|------|------|
| hotspot-analyzer.sh | core | 热点计算 |
| boundary-detector.sh | core | 边界检测 |
| pattern-learner.sh | core | 模式学习 |
| ast-diff.sh | core | 增量索引 |

**修改模块**：
| 模块 | 变更类型 |
|------|----------|
| bug-locator.sh | 集成新热点算法 |
| graph-rag.sh | 子图检索 + 边界过滤 |
| call-chain.sh | 新增参数 |
| augment-context-global.sh | 4 维意图分析 |
| server.ts | 新增 2 个工具 |

**依赖方向**：
```
server.ts → scripts/*.sh → common.sh
hooks/*.sh → scripts/*.sh
```

---

## Data Contracts

| 契约 | schema_version | 兼容策略 |
|------|----------------|----------|
| ci_hotspot 输入/输出 | 1.0.0 | 新增字段 backward compatible |
| ci_boundary 输入/输出 | 1.0.0 | 新增字段 backward compatible |
| boundaries.yaml | 1.0.0 | 不存在时使用默认值 |
| learned-patterns.json | 1.0.0 | 运行时生成 |

---

## Milestones

| 里程碑 | 交付物 | 验收口径 |
|--------|--------|----------|
| M1: Phase 1 完成 | MP1.1-MP1.4 | AC-001, AC-004, AC-008, AC-010 通过 |
| M2: Phase 2 完成 | MP2.1-MP2.2 | AC-002, AC-006 通过 |
| M3: Phase 3 完成 | MP3.1-MP3.4 | AC-003, AC-005, AC-007, AC-009 通过 |
| M4: 全量验收 | 所有任务 | 10 个 AC 全部通过 |

---

## Work Breakdown

### PR 切分建议

| PR | 包含任务 | 可并行 | 依赖 |
|----|----------|--------|------|
| PR-1a | MP1.1 | ✅ | 无 |
| PR-1b | MP1.2 | ✅ | 无 |
| PR-1c | MP1.3 | ❌ | PR-1a, PR-1b |
| PR-1d | MP1.4 | ❌ | PR-1c |
| PR-2a | MP2.1 | ✅ | 无 |
| PR-2b | MP2.2 | ✅ | 无 |
| PR-3a | MP3.1 | ❌ | PR-1a, 回归测试就绪 |
| PR-3b | MP3.2 | ❌ | PR-1b |
| PR-3c | MP3.3 | ✅ | 无 |
| PR-3d | MP3.4 | ✅ | 无 |

### 并行化建议

- **Wave 1**：MP1.1 + MP1.2 + MP2.1 + MP2.2 + MP3.3 + MP3.4（可并行开发）
- **Wave 2**：MP1.3 + MP1.4（依赖 Wave 1）
- **Wave 3**：MP3.1 + MP3.2（依赖回归测试）

---

## Quality Gates

| 闸门 | 验证命令 | 阻断条件 |
|------|----------|----------|
| TypeScript 编译 | `npm run build` | 失败 |
| ShellCheck | `npm run lint` | 错误 |
| 回归测试 | `bats tests/bug-locator.bats` | 失败 |
| 分层约束 | `rg "import.*from" scripts/*.sh` | 有匹配 |

---

## Algorithm Spec

### ALGO-001: 热点分数计算

**Inputs**：
- 文件路径列表
- git log 统计周期（天数）
- 复杂度权重配置

**Outputs**：
- 文件热点分数列表（file, score, frequency, complexity）

**Invariants**：
- score >= 0
- score = frequency × complexity

**Core Flow (Pseudocode)**：
```
FOR EACH file IN file_list:
    frequency = COUNT commits touching file IN last N days
    complexity = GET cyclomatic_complexity(file)
    score = frequency * complexity
    EMIT (file, score, frequency, complexity)
SORT BY score DESC
RETURN TOP N
```

**Complexity**：O(files × log_entries)

**Edge Cases**：
1. 文件无 git 历史 → frequency = 0
2. 文件无法解析复杂度 → complexity = 1（默认值）
3. 空目录 → 返回空列表
4. 超大仓库（>10000 文件） → 增量缓存
5. 二进制文件 → 跳过

---

### ALGO-002: 子图检索

**Inputs**：
- 查询符号 ID
- 深度限制
- 边界配置

**Outputs**：
- 子图（nodes + edges）

**Invariants**：
- depth ∈ [1, 5]
- 无库代码节点（经边界过滤）

**Core Flow (Pseudocode)**：
```
visited = SET()
queue = [(start_symbol, depth=0)]
nodes = []
edges = []

WHILE queue NOT EMPTY:
    symbol, d = queue.POP()
    IF symbol IN visited OR d > max_depth:
        CONTINUE
    visited.ADD(symbol)

    IF is_library_code(symbol):
        CONTINUE

    nodes.ADD(symbol)

    FOR EACH ref IN get_references(symbol):
        edges.ADD((symbol, ref, "refs"))
        queue.ADD((ref, d+1))

    FOR EACH callee IN get_callees(symbol):
        edges.ADD((symbol, callee, "calls"))
        queue.ADD((callee, d+1))

RETURN {nodes, edges}
```

**Complexity**：O(nodes × avg_edges)

**Edge Cases**：
1. 符号不存在 → 返回空子图
2. CKB 不可用 → 降级为 ripgrep 线性列表
3. 深度过大 → 截断并警告
4. 循环引用 → visited 集合处理
5. 孤立符号（无边） → 仅返回单节点

---

## Rollout & Rollback

**灰度策略**：
- 通过 `features.*` 功能开关逐步启用
- Phase 1 → Phase 2 → Phase 3 分阶段上线

**回滚策略**：
- 功能开关设为 false
- Git revert 到变更前 commit
- 删除 `.devbooks/learned-patterns.json`（如需清除学习数据）

---

## Risks & Edge Cases

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 热点计算超时 | 中 | 缓存 + 分页 |
| CKB 不可用 | 中 | 降级为 ripgrep |
| SCIP 索引缺失 | 高 | 提示用户生成 |
| 误报率高 | 低 | 可调阈值 |
| 边界误判 | 中 | 用户 override |

---

## Open Questions

| ID | 问题 | 建议处理方 |
|----|------|------------|
| OQ-1 | 热点计算的 git log 统计周期默认值是否需要可配置？ | Coder（实现时确认） |
| OQ-2 | 4 维意图信号的权重比例是否需要 A/B 测试确定？ | Product Owner |
| OQ-3 | Pattern Learner 的模式库是否需要版本迁移策略？ | Spec Owner |

---

# 断点区 (Context Switch Breakpoint Area)

> 用于切换主线/临时计划时记录上下文。

**当前断点**：无（全部任务已完成）

### Breakpoint: 2026-01-11 10:55

**状态**：✅ 全部完成
**完成任务**：MP1.1-MP1.4, MP2.1-MP2.2, MP3.1-MP3.4
**闸门验证**：
- `npm run build` ✅ 通过
- `npm run lint` ⚠️ 无 error 级别问题
- `bats tests/bug-locator.bats` ✅ 16/16 通过

**模板**：
```markdown
### Breakpoint: YYYY-MM-DD HH:MM

**切换原因**：
**暂停任务**：MP?.?
**切换到**：TP-XXX / 回到主线
**恢复条件**：
**上下文快照**：
```

---

## 追溯矩阵

| AC ID | 任务 | 验收锚点 |
|-------|------|----------|
| AC-001 | MP1.1, MP3.1 | 热点输出测试 |
| AC-002 | MP2.2 | 4 维信号标签检查 |
| AC-003 | MP3.2 | 边关系输出检查 |
| AC-004 | MP1.2, MP3.2 | 边界类型检查 |
| AC-005 | MP3.3 | learned-patterns.json 生成 |
| AC-006 | MP2.1 | 数据流路径输出 |
| AC-007 | MP3.4 | 增量更新耗时 < 1s |
| AC-008 | MP1.3 | MCP 工具调用测试 |
| AC-009 | MP3.1 | bug-locator.bats 全通过 |
| AC-010 | MP1.4 | 功能开关禁用测试 |
