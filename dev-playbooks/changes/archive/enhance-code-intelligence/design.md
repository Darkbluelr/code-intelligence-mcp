# Design: enhance-code-intelligence

> **Version**: 1.0.0
> **Status**: Draft
> **Owner**: Design Owner
> **Created**: 2026-01-11
> **Last Updated**: 2026-01-11 (Backport: Edge Cases + AC-009 更正)
> **Last Verified**: 2026-01-11
> **Freshness Check**: 30 days
> **Applicable Scope**: code-intelligence-mcp 项目

---

## ⚡ Acceptance Criteria（验收标准）

| AC ID | 验收项 | Pass/Fail 判据 | 验收方式 |
|-------|--------|----------------|----------|
| AC-001 | 热点算法输出正确 | `hotspot-analyzer.sh` 对 1000 文件项目返回 Top-20 热点，耗时 < 5s | A（机器裁判） |
| AC-002 | 意图分析 4 维信号 | hook 输出包含显式/隐式/历史/代码 4 类信号标签 | A（机器裁判） |
| AC-003 | 子图检索保留边关系 | 输出包含 `--calls-->` 或 `--refs-->` 等关系标记，非线性列表 | A（机器裁判） |
| AC-004 | 边界识别正确 | `node_modules/`、`dist/`、`vendor/` 标记为非用户代码 | A（机器裁判） |
| AC-005 | Pattern Learner 学习 | 运行后生成 `.devbooks/learned-patterns.json`，置信度阈值 0.85 | A（机器裁判） |
| AC-006 | 数据流追踪 | `--trace-data-flow` 参数输出参数流路径 | A（机器裁判） |
| AC-007 | 增量索引 | 单文件变更后只更新相关节点，耗时 < 1s | A（机器裁判） |
| AC-008 | MCP 工具兼容 | 现有 6 个 MCP 工具接口不变，新增 `ci_hotspot`、`ci_boundary` | A（机器裁判） |
| AC-009 | Bug 定位回归 | `tests/bug-locator.bats` 16 个测试用例全部通过 | A（机器裁判） |
| AC-010 | 功能开关可用 | 每个新功能可通过 `.devbooks/config.yaml` 的 `features.*` 单独禁用 | A（机器裁判） |

---

## ⚡ Goals / Non-goals / Red Lines

### Goals（本次变更目标）

1. **热点定位精度提升**：从规则驱动升级为数据驱动（Frequency × Complexity），Bug 定位 Top-5 命中率从 0% 提升至 20%+
2. **意图理解深度提升**：从单维度关键词升级为 4 维信号聚合，搜索命中率从 67% 提升至 90%+
3. **检索质量提升**：从线性列表升级为子图检索，保留代码关系上下文
4. **安全边界**：防止 AI 建议修改库代码或生成代码

### Non-goals（明确不做）

1. Neo4j 图数据库集成（重资产）
2. 自训练代码模型（重数据）
3. 跨语言符号归一化（ROI 低）
4. 执行路径模拟（超出静态分析范畴）
5. 击键级请求取消（非 MCP 层面）

### Red Lines（不可破约束）

1. **向后兼容**：现有 6 个 MCP 工具接口签名不变
2. **CLI 兼容**：`ci-search` 命令保持兼容
3. **无重资产**：不引入图数据库或需要自训练的模型
4. **SCIP 索引可用**：增量索引依赖 SCIP 索引，必须先生成 `index.scip`
5. **角色隔离**：Test Owner 与 Coder 独立对话

---

## 执行摘要

**核心矛盾**：当前代码智能能力受限于简单规则驱动，与 Augment Code 相比存在 7 个核心差距（热点计算、意图分析、检索策略、边界识别、语义异常、数据流追踪、增量更新）。

**解决方案**：在不引入重资产的前提下，通过算法改进（Frequency × Complexity 热点公式、4 维意图信号聚合、子图检索、边界识别、模式学习）提升代码智能能力 30-50%。

---

## Problem Context（问题背景）

### 为什么要解决这个问题

1. **与竞品差距明显**：对比 Augment Code，当前系统在 7 个维度存在技术差距
2. **用户体验受限**：Bug 定位 Top-5 命中率为 0%（CKB 不可用时）、搜索命中率仅 67%
3. **AI 误建议风险**：无边界识别，AI 可能建议修改 `node_modules/` 中的库代码

### 若不解决的后果

1. 用户迁移到更先进的竞品工具
2. AI 编程助手给出低质量建议，降低信任度
3. 误修改库代码导致项目依赖损坏

---

## 设计原则

### 核心原则

1. **渐进增强**：新功能通过功能开关控制，可逐步启用
2. **优雅降级**：CKB 不可用时降级为 ripgrep 文本搜索，保持基本功能
3. **最小依赖**：复用现有工具链（ripgrep、jq、SCIP），不引入新重资产
4. **可测试性**：每个新模块提供独立 CLI 入口，可单独测试

### 变化点识别（Variation Points）

| 变化点 | 可能变化 | 封装策略 |
|--------|----------|----------|
| 热点算法权重 | 不同项目最优权重不同 | 配置文件 `config/hotspot-weights.yaml` |
| 边界配置 | monorepo 需自定义边界 | 配置文件 `config/boundaries.yaml` + glob 模式 |
| Pattern Learner 阈值 | 不同场景误报容忍度不同 | 配置参数 `--confidence-threshold` |
| 子图检索深度 | 大型项目可能需要更深 | CLI 参数 `--depth N`（默认 3，最大 5） |
| Embedding 提供者 | Ollama/OpenAI/本地 | 现有 `EMBEDDING_PROVIDER` 环境变量 |

---

## 目标架构

### Bounded Context

```
┌─────────────────────────────────────────────────────────────────┐
│                        Code Intelligence                         │
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Analysis      │  │   Retrieval     │  │   Detection     │  │
│  │   (热点/复杂度) │  │   (子图/向量)   │  │   (边界/模式)   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Tracing       │  │   Indexing      │  │   Integration   │  │
│  │   (调用链/数据流)│  │   (SCIP/增量)   │  │   (MCP/Hook)    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 依赖方向

```
src/server.ts (MCP 薄壳)
    │
    ├──→ scripts/hotspot-analyzer.sh [新增]
    ├──→ scripts/boundary-detector.sh [新增]
    ├──→ scripts/pattern-learner.sh [新增]
    ├──→ scripts/ast-diff.sh [新增]
    ├──→ scripts/bug-locator.sh ──→ hotspot-analyzer.sh
    ├──→ scripts/graph-rag.sh ──→ boundary-detector.sh
    ├──→ scripts/call-chain.sh (增强：--trace-data-flow)
    └──→ hooks/augment-context-global.sh ──→ pattern-learner.sh
              │
              └──→ scripts/common.sh (共享函数)

依赖合规性：
✅ server.ts → scripts/*.sh → common.sh（符合分层）
✅ hooks/*.sh → scripts/*.sh（钩子调用工具脚本）
❌ scripts/*.sh → src/*.ts（禁止反向依赖）
```

### C4 Delta

> 本节描述本次变更对架构的影响，不修改 `dev-playbooks/specs/architecture/c4.md`（当前真理）。

#### C2 Container Level 变更

| 操作 | Container | 说明 |
|------|-----------|------|
| 新增 | `scripts/hotspot-analyzer.sh` | Frequency × Complexity 热点计算 |
| 新增 | `scripts/boundary-detector.sh` | 用户代码 vs 库代码边界识别 |
| 新增 | `scripts/pattern-learner.sh` | 语义异常模式学习 |
| 新增 | `scripts/ast-diff.sh` | SCIP 增量索引 |
| 修改 | `scripts/bug-locator.sh` | 集成新热点算法 |
| 修改 | `scripts/graph-rag.sh` | 子图检索 + 边界过滤 |
| 修改 | `scripts/call-chain.sh` | 新增 `--trace-data-flow` 参数 |
| 修改 | `hooks/augment-context-global.sh` | 4 维意图分析 |
| 修改 | `src/server.ts` | 新增 `ci_hotspot`、`ci_boundary` 工具 |

#### C3 Component Level 变更

| 操作 | Component | 所属 Container | 说明 |
|------|-----------|----------------|------|
| 新增 | `get_hotspot_score()` | hotspot-analyzer.sh | 计算热点分数 |
| 新增 | `detect_boundary()` | boundary-detector.sh | 边界检测主函数 |
| 新增 | `learn_pattern()` | pattern-learner.sh | 模式学习主函数 |
| 新增 | `compute_ast_diff()` | ast-diff.sh | AST 差异计算 |
| 修改 | `get_hotspot_files()` | bug-locator.sh | 调用 hotspot-analyzer.sh |
| 修改 | `embedding_search()` | graph-rag.sh | 增加子图连通性分析 |
| 新增 | `trace_data_flow()` | call-chain.sh | 参数流追踪 |
| 新增 | `analyze_intent_4d()` | augment-context-global.sh | 4 维意图分析 |

#### 依赖方向变更

| 新依赖 | 方向 | 合规性 |
|--------|------|--------|
| bug-locator.sh → hotspot-analyzer.sh | 功能脚本 → 工具脚本 | ✅ |
| graph-rag.sh → boundary-detector.sh | 功能脚本 → 工具脚本 | ✅ |
| augment-context-global.sh → pattern-learner.sh | 钩子 → 工具脚本 | ✅ |
| server.ts → hotspot-analyzer.sh | MCP 壳 → 脚本 | ✅ |
| server.ts → boundary-detector.sh | MCP 壳 → 脚本 | ✅ |

#### Architecture Guardrails

##### Layering Constraints（分层约束）

本项目采用 3 层架构，依赖方向为：**shared ← core ← integration**

| 层级 | 目录 | 职责 | 可依赖 | 禁止依赖 |
|------|------|------|--------|----------|
| shared | `scripts/common.sh`, `scripts/cache-utils.sh` | 共享工具函数 | （无） | core, integration |
| core | `scripts/*.sh`（功能脚本） | 核心功能实现 | shared | integration |
| integration | `src/server.ts`, `hooks/*.sh` | 集成层（MCP/钩子） | shared, core | （无） |

##### Environment Constraints（环境约束）

| 脚本类型 | 可调用 | 禁止调用 |
|----------|--------|----------|
| scripts/*.sh | common.sh, 外部 CLI 工具 | src/*.ts, node 模块 |
| hooks/*.sh | scripts/*.sh, common.sh | src/*.ts |
| src/*.ts | scripts/*.sh (via execAsync) | hooks/*.sh 直接 import |

##### Validation Commands（验证命令）

```bash
# 检查脚本是否违规引用 TypeScript
rg "import.*from|require\(" scripts/*.sh && echo "FAIL" || echo "OK"

# 检查 common.sh 是否被 core 脚本循环引用
grep -l "source.*common.sh" scripts/*.sh | wc -l  # 应 > 0

# 检查循环依赖
# bug-locator.sh 不应被 hotspot-analyzer.sh 引用
grep "hotspot-analyzer.sh" scripts/bug-locator.sh && \
grep "bug-locator.sh" scripts/hotspot-analyzer.sh && \
echo "FAIL: 循环依赖" || echo "OK"
```

##### Fitness Tests（架构适配测试条目）

| 测试 ID | 约束 | 验证方式 |
|---------|------|----------|
| FT-LAYER-001 | scripts 不引用 src/*.ts | grep/rg 检查 |
| FT-LAYER-002 | common.sh 不引用功能脚本 | grep 检查 |
| FT-CYCLE-001 | 无循环依赖 | 依赖图分析 |
| FT-CONFIG-001 | 新配置有默认模板 | 文件存在性检查 |

##### 归档后待办

> 注意：当前 `dev-playbooks/specs/architecture/c4.md` 不存在。归档时需创建权威 C4 地图。

1. 创建 `dev-playbooks/specs/architecture/c4.md`（包含 C1/C2/C3 完整定义）
2. 将本次 C4 Delta 合并到权威地图
3. 添加 `layering-constraints.md`（可选，若项目规模增长）

---

## Testability & Seams（可测试性与接缝）

### 测试接缝（Seams）

| 接缝类型 | 位置 | 可替换内容 |
|----------|------|-----------|
| CLI 参数注入 | 所有新增脚本 | 通过 `--dry-run` 可模拟执行 |
| 配置注入 | `config/*.yaml` | 测试时可使用自定义配置 |
| 外部工具隔离 | CKB MCP 调用点 | CKB 不可用时降级为 ripgrep |
| 输出格式控制 | `--format json` | 机器可读输出便于断言 |

### Pinch Points（汇点）

| 汇点 | 路径数 | 测试价值 |
|------|--------|----------|
| `bug-locator.sh:main()` | 3 | 集成热点/调用链/embedding |
| `graph-rag.sh:search()` | 2 | 集成边界/子图 |
| `augment-context-global.sh:generate_context()` | 4 | 集成 4 维意图信号 |

### 依赖隔离策略

| 外部依赖 | 隔离方式 | 测试替代 |
|----------|----------|----------|
| CKB MCP Server | 检测可用性，不可用时降级 | ripgrep 文本搜索 |
| Ollama/OpenAI | `EMBEDDING_PROVIDER` 环境变量 | keyword（关键词搜索）|
| SCIP 索引 | 检测 `index.scip` 存在性 | 跳过增量索引测试 |

---

## 领域模型（Domain Model）

### Data Model

| 对象 | 类型 | 字段 | 说明 |
|------|------|------|------|
| HotspotEntry | @ValueObject | file, score, frequency, complexity | 热点条目 |
| BoundaryResult | @ValueObject | path, type, confidence | 边界检测结果 |
| PatternMatch | @ValueObject | pattern_id, confidence, context | 模式匹配结果 |
| IntentSignal | @ValueObject | type, weight, source | 意图信号 |
| SubgraphNode | @ValueObject | symbol_id, refs, calls | 子图节点 |
| DataFlowPath | @ValueObject | source, target, path | 数据流路径 |

### Business Rules

| ID | 规则 | 触发条件 | 违反时行为 |
|----|------|----------|-----------|
| BR-001 | 热点分数 = Frequency × Complexity | 计算热点 | N/A（计算公式） |
| BR-002 | 边界类型优先级：config > glob > default | 检测边界 | 使用下一优先级 |
| BR-003 | Pattern 置信度 < 0.85 不输出警告 | 模式学习 | 静默跳过 |
| BR-004 | 子图深度最大 5 | 子图检索 | 截断并警告 |
| BR-005 | CKB 不可用时降级为 ripgrep | 调用链/子图 | 返回线性列表 |

### Edge Cases（边缘情况处理）

> **Backport from tasks.md ALGO-001/ALGO-002**：以下边缘情况影响用户可感知输出，需作为设计约束。

| ID | 场景 | 输入条件 | 系统行为 | 影响模块 |
|----|------|----------|----------|----------|
| EC-001 | 文件无 git 历史 | 新增文件或历史不可达 | frequency = 0，仍计算 complexity | hotspot-analyzer.sh |
| EC-002 | 文件无法解析复杂度 | 二进制文件/未知语言 | complexity = 1（默认值） | hotspot-analyzer.sh |
| EC-003 | 二进制文件 | .png/.exe/.o 等 | 跳过，不参与热点计算 | hotspot-analyzer.sh |
| EC-004 | 超大仓库 | > 10000 文件 | 启用增量缓存；可能超时（见 Trade-offs） | hotspot-analyzer.sh |
| EC-005 | 符号不存在 | 查询未索引符号 | 返回空子图 `{nodes: [], edges: []}` | graph-rag.sh |
| EC-006 | 孤立符号 | 符号存在但无调用/引用边 | 返回单节点子图 `{nodes: [symbol], edges: []}` | graph-rag.sh |

### Invariants（固定规则）

- `[Invariant]` 热点分数 >= 0
- `[Invariant]` 边界类型 ∈ {user, library, generated, config}
- `[Invariant]` 意图信号权重 ∈ [0, 1]
- `[Invariant]` 子图深度 ∈ [1, 5]
- `[Invariant]` Pattern 置信度 ∈ [0, 1]

---

## 核心数据与事件契约

### 新增配置文件

#### config/boundaries.yaml

```yaml
schema_version: "1.0.0"

# 边界类型定义
boundaries:
  library:
    - "node_modules/**"
    - "**/vendor/**"
    - "**/.yarn/**"
  generated:
    - "dist/**"
    - "build/**"
    - "**/*.generated.*"
  config:
    - "config/**"
    - "*.config.js"
    - "*.config.ts"

# 自定义覆盖（用户可编辑）
overrides: []
```

#### .devbooks/config.yaml 新增字段

```yaml
features:
  enhanced_hotspot: true
  intent_analysis: true
  subgraph_retrieval: true
  boundary_detection: true
  pattern_learning: true
  data_flow_tracing: true
  incremental_indexing: true
```

### MCP 工具契约

#### ci_hotspot（新增）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| path | string | 否 | 分析目录（默认 .） |
| top_n | number | 否 | 返回数量（默认 20） |
| format | string | 否 | 输出格式（json/text） |

#### ci_boundary（新增）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| path | string | 是 | 待检测路径 |
| config | string | 否 | 自定义配置文件 |

### 兼容策略

| 契约 | 变更类型 | 兼容性 |
|------|----------|--------|
| 现有 6 个 MCP 工具 | 无变更 | ✅ 完全兼容 |
| `call-chain.sh` CLI | 新增可选参数 | ✅ 向后兼容 |
| `ci_hotspot` | 新增 | ✅ 加法兼容 |
| `ci_boundary` | 新增 | ✅ 加法兼容 |

---

## 可观测性与验收

### Metrics / KPI

| 指标 | 基线值 | 目标值 | 测量方式 |
|------|--------|--------|----------|
| Bug 定位 Top-5 命中率 | 0% | 20%+ | 测试用例验证 |
| 搜索命中率 | 67% | 90%+ | 测试用例验证 |
| 召回率 | 67% | 85%+ | 测试用例验证 |
| 热点计算耗时（1000 文件） | N/A | < 5s | `time` 命令 |
| 增量索引耗时（单文件） | N/A | < 1s | `time` 命令 |

### SLO

| 指标 | 阈值 | 告警条件 |
|------|------|----------|
| 热点计算 p99 | < 5s | 超时返回缓存结果 |
| 子图检索内存增量 | < 200MB | 日志警告 |
| 增量索引 p99 | < 1s | 降级为全量索引 |

---

## 风险与降级策略

### Failure Modes

| 风险 | 可能性 | 影响 | 降级策略 |
|------|--------|------|----------|
| 热点计算超时 | 中 | 中 | 返回缓存结果或 Top-10 |
| CKB MCP 不可用 | 高 | 中 | 降级为 ripgrep 线性搜索 |
| SCIP 索引缺失 | 低 | 高 | 跳过增量索引，使用全量 |
| Pattern 误报率高 | 中 | 低 | 提高置信度阈值 |
| 边界配置误判 | 低 | 中 | 用户自定义覆盖 |

### Degrade Paths

```
子图检索:
  CKB 可用? → 子图检索 + 边关系
       ↓ 否
  ripgrep 可用? → 线性列表（兼容现有行为）
       ↓ 否
  返回空结果 + 错误提示

增量索引:
  SCIP 索引存在? → AST Diff 增量更新
       ↓ 否
  返回"请先生成 SCIP 索引"提示
```

### Rollout & Rollback 策略

> **Backport from tasks.md**：明确功能开关作为回滚手段。

**灰度上线**：
- 通过 `.devbooks/config.yaml` 的 `features.*` 配置块逐步启用各功能
- 按 Phase 1 → Phase 2 → Phase 3 顺序分阶段上线

**回滚手段**：
1. **功能开关禁用**：将对应 `features.<功能名>: false` 立即生效
2. **Git Revert**：回退到变更前 commit
3. **数据清理**：删除 `.devbooks/learned-patterns.json`（如需清除学习数据）

---

## 里程碑

### Phase 1（低风险）

- 新增 `hotspot-analyzer.sh`、`boundary-detector.sh`
- `src/server.ts` 注册 `ci_hotspot`、`ci_boundary`
- 新增 `config/boundaries.yaml`

### Phase 2（中风险）

- `call-chain.sh` 增加 `--trace-data-flow`
- `augment-context-global.sh` 增加 4 维意图分析

### Phase 3（高风险，需前置条件）

**前置条件**：
- `tests/bug-locator.bats` 18 个测试用例通过
- 变更前输出已记录为基线

**变更内容**：
- `bug-locator.sh` 集成新热点算法
- `graph-rag.sh` 改为子图检索
- 新增 `pattern-learner.sh`
- 新增 `ast-diff.sh`

---

## Design Rationale（设计决策理由）

### 为什么选择 SCIP 增量模式而非 tree-sitter

| 方案 | 优点 | 缺点 | 结论 |
|------|------|------|------|
| tree-sitter AST Diff | 通用性强 | 需额外安装，环境未就绪 | ❌ 否决 |
| SCIP 增量模式 | 已安装，TypeScript 原生支持 | 仅支持 TS | ✅ 采纳 |

### 为什么子图深度默认 3

- 深度 3 覆盖 90% 的实际使用场景（基于经验）
- 更深的遍历内存消耗显著增加
- 提供 `--depth` 参数（最大 5）满足特殊场景

### 为什么 Pattern Learner 置信度阈值 0.85

- 阈值过低（0.7）：误报率高，干扰用户
- 阈值过高（0.95）：漏报率高，价值降低
- 0.85 为经验值，平衡误报与召回

---

## Trade-offs（权衡取舍）

### 放弃了什么

1. **跨语言支持**：仅支持 TypeScript，放弃其他语言的 SCIP 索引
2. **图数据库持久化**：放弃长期图关系存储，使用内存临时子图
3. **自训练模型**：放弃语义异常的深度学习方案，使用规则 + 置信度

### 接受的不完美

1. CKB 不可用时子图检索降级为线性列表，丧失关系上下文
2. Pattern Learner 基于规则，复杂模式可能漏检
3. 热点算法权重需手动调优，无自动学习

### 不适用场景

1. 超大型 monorepo（>10000 文件）：热点计算可能超时
2. 非 TypeScript 项目：SCIP 索引不可用
3. 无 ripgrep 环境：基础搜索能力受限

---

## ⚡ DoD 完成定义（Definition of Done）

### 必须通过的闸门

| 闸门 | 验证命令 | AC 引用 |
|------|----------|---------|
| TypeScript 编译 | `npm run build` | - |
| ShellCheck 检查 | `npm run lint` | - |
| 回归测试 | `bats tests/bug-locator.bats` | AC-009 |
| 单元测试（新增脚本） | 各脚本 `--test` 模式 | AC-001 ~ AC-007 |
| MCP 工具集成测试 | `npm run test:mcp` | AC-008 |

### 必须产出的证据

| 证据 | 落点 | AC 引用 |
|------|------|---------|
| 热点算法输出 | `evidence/hotspot-output.log` | AC-001 |
| 意图分析输出 | `evidence/intent-output.log` | AC-002 |
| 子图检索输出 | `evidence/subgraph-output.log` | AC-003 |
| 边界识别输出 | `evidence/boundary-output.log` | AC-004 |
| Pattern 学习结果 | `.devbooks/learned-patterns.json` | AC-005 |
| 数据流追踪输出 | `evidence/dataflow-output.log` | AC-006 |
| AST Diff 输出 | `evidence/ast-diff-output.log` | AC-007 |

---

## Open Questions

| ID | 问题 | 影响范围 | 建议处理方 | 状态 |
|----|------|----------|------------|------|
| OQ-1 | 热点算法 Frequency 计算周期（git log 多少天）？ | hotspot-analyzer.sh | Planner | **已解答**：默认 30 天（见 Contract 章节 `--days` 参数） |
| OQ-2 | 4 维意图信号的权重分配比例？ | augment-context-global.sh | Test Owner（实验确定） | 待定 |
| OQ-3 | Pattern Learner 的模式库是否需要版本化？ | pattern-learner.sh | Spec Owner | 待定 |

---

## Contract（契约计划）

> **Owner**: Contract Owner
> **Updated**: 2026-01-11

---

### API 变更清单

#### 新增 MCP 工具

| 工具名 | 端点类型 | 版本 | 说明 |
|--------|----------|------|------|
| `ci_hotspot` | MCP Tool | v1 | 热点分析工具 |
| `ci_boundary` | MCP Tool | v1 | 边界检测工具 |

#### ci_hotspot 契约

```typescript
interface CiHotspotInput {
  path?: string;      // 分析目录，默认 "."
  top_n?: number;     // 返回数量，默认 20
  format?: "json" | "text";  // 输出格式，默认 "json"
}

interface CiHotspotOutput {
  schema_version: "1.0.0";
  hotspots: Array<{
    file: string;
    score: number;
    frequency: number;
    complexity: number;
  }>;
  duration_ms: number;
}
```

#### ci_boundary 契约

```typescript
interface CiBoundaryInput {
  path: string;       // 待检测路径（必填）
  config?: string;    // 自定义配置文件路径
}

interface CiBoundaryOutput {
  schema_version: "1.0.0";
  path: string;
  type: "user" | "library" | "generated" | "config";
  confidence: number;  // 0.0 - 1.0
  matched_rule?: string;  // 匹配的规则（如 "node_modules/**"）
}
```

#### CLI 参数扩展

| 脚本 | 新增参数 | 类型 | 默认值 | 说明 |
|------|----------|------|--------|------|
| `call-chain.sh` | `--trace-data-flow` | flag | false | 启用参数流追踪 |
| `hotspot-analyzer.sh` | `--days` | number | 30 | git log 统计天数 |
| `boundary-detector.sh` | `--config` | string | - | 自定义配置路径 |
| `pattern-learner.sh` | `--confidence-threshold` | number | 0.85 | 置信度阈值 |
| `graph-rag.sh` | `--depth` | number | 3 | 子图深度（1-5） |

---

### 新增配置文件契约

#### config/boundaries.yaml

```yaml
schema_version: "1.0.0"

boundaries:
  library:
    - "node_modules/**"
    - "**/vendor/**"
    - "**/.yarn/**"
  generated:
    - "dist/**"
    - "build/**"
    - "**/*.generated.*"
  config:
    - "config/**"
    - "*.config.js"
    - "*.config.ts"

overrides: []
```

#### .devbooks/learned-patterns.json

```json
{
  "schema_version": "1.0.0",
  "generated_at": "<ISO8601>",
  "patterns": []
}
```

#### .devbooks/config.yaml 新增字段

```yaml
features:
  enhanced_hotspot: true
  intent_analysis: true
  subgraph_retrieval: true
  boundary_detection: true
  pattern_learning: true
  data_flow_tracing: true
  incremental_indexing: true
```

---

### 兼容策略

| 变更项 | 兼容类型 | 说明 |
|--------|----------|------|
| 现有 6 个 MCP 工具 | ✅ 完全兼容 | 无签名变更 |
| `call-chain.sh` CLI | ✅ 向后兼容 | 新参数为可选 |
| `ci_hotspot` MCP 工具 | ✅ 加法兼容 | 新增工具 |
| `ci_boundary` MCP 工具 | ✅ 加法兼容 | 新增工具 |
| `config/boundaries.yaml` | ✅ 可选 | 不存在时使用默认值 |
| `.devbooks/learned-patterns.json` | ✅ 运行时生成 | 不存在时自动创建 |

### 弃用策略

本次变更无弃用项。

### 迁移方案

无需迁移。所有新功能通过功能开关控制，默认启用。如需禁用：

```yaml
# .devbooks/config.yaml
features:
  enhanced_hotspot: false
```

---

### Contract Test IDs

| Test ID | 类型 | 覆盖场景 | 追溯 |
|---------|------|----------|------|
| CT-MCP-001 | schema | ci_hotspot 输入格式验证 | AC-001, AC-008 |
| CT-MCP-002 | schema | ci_hotspot 输出格式验证 | AC-001 |
| CT-MCP-003 | schema | ci_boundary 输入格式验证 | AC-004, AC-008 |
| CT-MCP-004 | schema | ci_boundary 输出格式验证 | AC-004 |
| CT-MCP-005 | behavior | 现有 6 个工具回归 | AC-008 |
| CT-CLI-001 | behavior | call-chain.sh --trace-data-flow | AC-006 |
| CT-CLI-002 | behavior | call-chain.sh 无新参数兼容 | AC-006 |
| CT-CFG-001 | schema | boundaries.yaml 格式验证 | AC-004 |
| CT-CFG-002 | schema | learned-patterns.json 格式验证 | AC-005 |
| CT-CFG-003 | behavior | 功能开关禁用测试 | AC-010 |

---

### 追溯摘要

| AC/REQ | Capability | Contract Test |
|--------|------------|---------------|
| AC-001 | hotspot-analysis | CT-MCP-001, CT-MCP-002 |
| AC-002 | intent-analysis | - |
| AC-003 | subgraph-retrieval | - |
| AC-004 | boundary-detection | CT-MCP-003, CT-MCP-004, CT-CFG-001 |
| AC-005 | pattern-learning | CT-CFG-002 |
| AC-006 | data-flow-tracing | CT-CLI-001, CT-CLI-002 |
| AC-007 | incremental-indexing | - |
| AC-008 | MCP 兼容 | CT-MCP-005 |
| AC-009 | 回归测试 | (已有 tests/bug-locator.bats) |
| AC-010 | 功能开关 | CT-CFG-003 |
