# 提案：代码智能能力增强（Augment 差距补齐）

> **Change ID**: `enhance-code-intelligence`
> **Author**: Proposal Author
> **Created**: 2026-01-10
> **Status**: Pending

---

## 1. Why（问题与目标）

### 1.1 问题陈述

根据与 Augment Code 的技术对比分析，当前 `code-intelligence-mcp` 项目存在以下核心差距：

| 差距类型 | 当前状态 | 目标状态 |
|----------|----------|----------|
| 热点计算 | 简单规则评分 | 数据驱动评分（Frequency × Complexity） |
| 意图分析 | 单维度关键词提取 | 多维信号聚合（显式+隐式+历史+代码） |
| 检索策略 | 线性结果列表拼接 | 子图检索（保留边关系） |
| 边界识别 | 无区分 | 用户代码 vs 库代码 vs 生成代码 |
| 语义异常 | 预定义规则 | 动态学习规范 |
| 数据流追踪 | 函数级调用链 | 跨函数参数流追踪 |
| 增量更新 | 全量索引 | AST Diff + 节点级更新 |

### 1.2 目标

**在不引入重资产（图数据库）和重数据（自训练模型）的前提下**，通过算法改进将代码智能能力提升 30-50%，具体目标：

1. **热点定位精度**：从规则驱动升级为数据驱动，Bug 定位准确率提升 20%
2. **意图理解深度**：从单维度升级为 4 维信号聚合，上下文相关性提升 30%
3. **检索质量**：从线性列表升级为子图检索，保留代码关系上下文
4. **安全边界**：防止 AI 建议修改库代码或生成代码

---

## 2. What Changes（范围）

### 2.1 变更范围

本提案涉及 7 个功能模块的新增或增强：

| 模块 | 类型 | 路径 | 说明 |
|------|------|------|------|
| Hotspot Analyzer | 新增 | `scripts/hotspot-analyzer.sh` | Augment 热点公式实现 |
| Intent Analyzer | 增强 | `hooks/augment-context-global.sh` | 4 维信号聚合 |
| Subgraph Retrieval | 增强 | `scripts/graph-rag.sh` | 子图检索替代线性列表 |
| Boundary Detector | 新增 | `scripts/boundary-detector.sh` | 边界识别 |
| Pattern Learner | 新增 | `scripts/pattern-learner.sh` | 语义异常检测 |
| Data Flow Tracer | 增强 | `scripts/call-chain.sh` | 参数流追踪 |
| AST Diff | 新增 | `scripts/ast-diff.sh` | 增量索引 |

### 2.2 非目标（明确排除）

| 排除项 | 原因 |
|--------|------|
| Neo4j 图数据库集成 | 重资产，运维成本高 |
| 自训练代码模型 | 重数据，需要大量标注 |
| 跨语言符号归一化 | 复杂度高，ROI 低 |
| 执行路径模拟 | 需要运行时支持，超出静态分析范畴 |
| 击键级请求取消 | 需要 IDE 集成，非 MCP 层面 |

### 2.3 影响文件清单

**前置依赖（P0）**：
1. **SCIP 索引生成** - 增量索引（AST Diff）依赖 SCIP 索引可用
   - 执行：`scip-typescript index --output index.scip`
   - 验证：`test -f index.scip && ls -la index.scip`

**新增文件（4 个）**：
1. `scripts/hotspot-analyzer.sh`
2. `scripts/boundary-detector.sh`
3. `scripts/pattern-learner.sh`
4. `scripts/ast-diff.sh`

**修改文件（5 个）**：
1. `scripts/graph-rag.sh` - 子图检索逻辑
2. `scripts/call-chain.sh` - 数据流追踪选项
3. `scripts/bug-locator.sh` - 集成新热点算法
4. `hooks/augment-context-global.sh` - 4 维意图分析
5. `src/server.ts` - 新增 MCP 工具注册

**新增配置（2 个）**：
1. `config/boundaries.yaml` - 边界配置
2. `.devbooks/learned-patterns.json` - 学习到的模式缓存

---

## 3. Impact（影响分析）

> **分析模式**：文本搜索（Grep + Glob）+ 部分图遍历
> **分析时间**：2026-01-10
> **分析者**：Impact Analyst

### 3.0 影响范围概览

| 指标 | 数量 | 说明 |
|------|------|------|
| 直接影响文件 | 5 个 | 需修改的现有文件 |
| 新增文件 | 6 个 | 4 个脚本 + 2 个配置 |
| 间接影响文件 | 4 个 | 引用被修改脚本的文件 |
| 热点重叠 | 1 个 | bug-locator.sh（高变更频率） |

### 3.1 对外契约影响

| 契约 | 影响级别 | 说明 | 兼容性 |
|------|----------|------|--------|
| MCP 工具接口 | **新增** | 新增 2 个工具：`ci_hotspot`、`ci_boundary` | ✅ 向后兼容 |
| 现有工具签名 | **无变更** | 现有 6 个工具保持兼容 | ✅ 完全兼容 |
| CLI 接口 | **无变更** | `ci-search` 命令保持兼容 | ✅ 完全兼容 |
| 脚本接口 | **扩展** | `call-chain.sh` 新增 `--trace-data-flow` 参数 | ✅ 向后兼容 |
| 配置格式 | **新增** | `config/boundaries.yaml` 新配置文件 | ✅ 可选配置 |

### 3.2 数据影响

| 数据 | 影响 | 迁移需求 |
|------|------|----------|
| 索引文件 `index.scip` | 无变更 | 无 |
| 缓存目录 `.ci-cache/` | 新增 `patterns/` 子目录 | 自动创建 |
| 配置文件 | 新增 `config/boundaries.yaml` | 提供默认模板 |
| 学习模式 | 新增 `.devbooks/learned-patterns.json` | 运行时生成 |

### 3.3 模块依赖影响（详细）

#### 3.3.1 现有依赖关系

```
src/server.ts
  ├── scripts/embedding.sh      (ci_search)
  ├── scripts/call-chain.sh     (ci_call_chain)
  ├── scripts/bug-locator.sh    (ci_bug_locate)
  ├── scripts/complexity.sh     (ci_complexity)
  ├── scripts/graph-rag.sh      (ci_graph_rag)
  └── scripts/indexer.sh        (ci_index_status)

scripts/bug-locator.sh
  ├── scripts/common.sh         (共享函数)
  └── scripts/call-chain-tracer.sh (调用链)

scripts/graph-rag.sh
  ├── scripts/common.sh         (共享函数)
  └── scripts/devbooks-embedding.sh (向量搜索)

hooks/augment-context-global.sh
  ├── tools/devbooks-embedding.sh (Embedding)
  └── tools/graph-rag-context.sh  (Graph-RAG)
```

#### 3.3.2 变更后依赖关系

```
新增依赖：
  bug-locator.sh ──→ hotspot-analyzer.sh (新增，热点评分)
  graph-rag.sh ────→ boundary-detector.sh (新增，边界过滤)
  augment-context-global.sh ──→ pattern-learner.sh (新增，模式匹配)
  call-chain.sh ───→ (内部增强，无新依赖)
  server.ts ───────→ hotspot-analyzer.sh (新增 ci_hotspot)
  server.ts ───────→ boundary-detector.sh (新增 ci_boundary)

依赖方向合规性检查：
  ✅ bug-locator.sh → hotspot-analyzer.sh：功能脚本 → 工具脚本，合规
  ✅ graph-rag.sh → boundary-detector.sh：功能脚本 → 工具脚本，合规
  ✅ augment-context-global.sh → pattern-learner.sh：钩子 → 工具脚本，合规
  ✅ 无循环依赖
  ✅ 无反向依赖（工具脚本不依赖功能脚本）
```

### 3.4 代码级影响分析

#### 3.4.1 bug-locator.sh 修改点

| 行号 | 现有代码 | 变更内容 | 风险 |
|------|----------|----------|------|
| 59-62 | `WEIGHT_HOTSPOT=0.15` | 可能调整权重或替换为动态计算 | 低 |
| 404-437 | `get_hotspot_files()` | 替换为调用 `hotspot-analyzer.sh` | 中 |
| 441-479 | `add_hotspot_scores()` | 使用新热点算法输出 | 中 |
| 562-570 | 评分计算逻辑 | 集成 Frequency × Complexity 公式 | 中 |

**回归风险**：`bug-locator.sh` 是高频使用脚本，行为变更需充分测试。

#### 3.4.2 graph-rag.sh 修改点

| 行号 | 现有代码 | 变更内容 | 风险 |
|------|----------|----------|------|
| 243-262 | `embedding_search()` | 无变更 | - |
| 新增 | - | 添加子图连通性分析 | 中 |
| 新增 | - | 添加边关系保留逻辑 | 中 |
| 新增 | - | 调用 `boundary-detector.sh` 过滤库代码 | 低 |

**关键变更**：结果格式从线性列表变为包含边关系的结构化数据。

#### 3.4.3 call-chain.sh 修改点

| 行号 | 现有代码 | 变更内容 | 风险 |
|------|----------|----------|------|
| 100 | `--direction <dir>` | 新增 `--trace-data-flow` 参数 | 低 |
| 285-341 | 调用链分析逻辑 | 增加参数流追踪 | 中 |

**兼容性**：新参数为可选，默认行为不变。

#### 3.4.4 augment-context-global.sh 修改点

| 行号 | 现有代码 | 变更内容 | 风险 |
|------|----------|----------|------|
| 216-282 | Embedding 相关函数 | 无变更 | - |
| 新增 | - | 添加 4 维意图分析模块 | 中 |
| 新增 | - | 添加历史信号收集 | 低 |
| 新增 | - | 调用 `pattern-learner.sh` | 低 |

**意图分析 4 维信号**：
1. 显式信号：用户 Prompt 关键词
2. 隐式信号：当前文件、光标位置
3. 历史信号：最近 5 次编辑记录
4. 代码信号：AST 上下文（函数体/类定义）

#### 3.4.5 src/server.ts 修改点

| 行号 | 现有代码 | 变更内容 | 风险 |
|------|----------|----------|------|
| 29-119 | `TOOLS` 数组 | 新增 `ci_hotspot`、`ci_boundary` 定义 | 低 |
| 144-222 | `handleToolCall()` | 新增 2 个 case 分支 | 低 |

**MCP 协议兼容性**：✅ 新增工具不影响现有工具。

### 3.5 间接影响文件

以下文件引用了被修改的脚本，需关注但无需修改：

| 文件 | 引用方式 | 影响 |
|------|----------|------|
| `hooks/augment-context-with-embedding.sh` | 调用 embedding 相关函数 | 无影响 |
| `bin/ci-search` | 调用 `embedding.sh` | 无影响 |
| `scripts/test-embedding.sh` | 测试脚本 | 可能需更新测试用例 |
| `scripts/entropy-viz.sh` | 共享 `common.sh` | 无影响 |

### 3.6 测试影响

| 影响类型 | 说明 | 建议 |
|----------|------|------|
| 单元测试 | 需新增 4 个脚本的单元测试 | 必须 |
| 集成测试 | 需新增 MCP 工具集成测试 | 必须 |
| 回归测试 | `bug-locator.sh` 行为变更 | 必须，对比变更前后输出 |
| 性能测试 | 热点算法、子图检索性能 | 建议，1000 文件基准 |

### 3.7 Transaction Scope

**`None`** - 本变更不涉及数据库事务，所有操作均为文件级读写。

### 3.8 价值信号

| 信号 | 度量方式 | 当前基线 | 目标 |
|------|----------|----------|------|
| Bug 定位准确率 | Top-5 命中率 | 待测量（建议先跑基线） | +20% |
| 上下文相关性 | 用户采纳率 | 待测量 | +30% |
| 检索召回率 | 相关文件覆盖 | 待测量 | +25% |

### 3.9 风险热点叠加分析

| 文件 | 热点等级 | 变更类型 | 综合风险 |
|------|----------|----------|----------|
| `scripts/bug-locator.sh` | 🔴 高 | 核心逻辑修改 | **高** |
| `scripts/graph-rag.sh` | 🟡 中 | 输出格式变更 | 中 |
| `scripts/call-chain.sh` | 🟢 低 | 参数扩展 | 低 |
| `hooks/augment-context-global.sh` | 🟡 中 | 功能增强 | 中 |
| `src/server.ts` | 🟢 低 | 工具注册 | 低 |

### 3.10 Minimal Diff（最小变更策略）

为降低风险，建议采用渐进式变更：

**Phase 1（低风险）**：
- 新增 `hotspot-analyzer.sh`、`boundary-detector.sh`
- `src/server.ts` 注册新工具
- 新增 `config/boundaries.yaml`

**Phase 2（中风险）**：
- `call-chain.sh` 增加 `--trace-data-flow`
- `augment-context-global.sh` 增加意图分析

**Phase 3（高风险）**：
- **前置：回归测试就绪** - `bug-locator.sh` 回归测试必须在核心逻辑修改前完成
  - 创建 `tests/bug-locator.bats` 或等效测试
  - 记录变更前输出作为基线
- `bug-locator.sh` 集成新热点算法
- `graph-rag.sh` 改为子图检索
- 新增 `pattern-learner.sh`

### 3.11 Open Questions

| ID | 问题 | 影响范围 | 建议处理方 |
|----|------|----------|------------|
| OQ1 | `bug-locator.sh` 热点权重变更后是否需要 A/B 测试？ | Bug 定位准确率 | Product Owner |
| OQ2 | 子图检索的边关系输出格式如何定义？ | graph-rag.sh | Design Owner |
| OQ3 | Pattern Learner 的模式存储格式？ | pattern-learner.sh | Design Owner |

---

## 4. Risks & Rollback（风险与回滚）

### 4.1 风险清单

| 风险 ID | 风险描述 | 可能性 | 影响 | 缓解措施 |
|---------|----------|--------|------|----------|
| R1 | 热点算法计算耗时过长（大型仓库） | 中 | 中 | 增量计算 + 缓存 |
| R2 | Pattern Learner 误报率高 | 中 | 低 | 设置置信度阈值 |
| R3 | 子图检索内存占用增加 | 低 | 中 | 设置深度限制 |
| R4 | AST Diff 解析失败（语法错误文件） | 低 | 低 | 降级为全量索引 |
| R5 | 边界配置误判（monorepo） | 低 | 中 | 支持自定义配置 |

### 4.2 回滚策略

| 阶段 | 回滚方式 |
|------|----------|
| 开发中 | Git revert 到变更前 commit |
| 部署后 | 功能开关禁用新算法，回退到旧逻辑 |
| 数据层 | 删除 `.devbooks/learned-patterns.json` |

**功能开关设计**：
```yaml
# .devbooks/config.yaml 新增
features:
  enhanced_hotspot: true      # 新热点算法
  intent_analysis: true       # 4 维意图分析
  subgraph_retrieval: true    # 子图检索
  boundary_detection: true    # 边界识别
  pattern_learning: true      # 语义异常检测
  data_flow_tracing: true     # 数据流追踪
  incremental_indexing: true  # 增量索引
```

---

## 5. Validation（验收锚点）

### 5.1 功能验收

| ID | 验收项 | 验证方法 | 证据落点 |
|----|--------|----------|----------|
| V1 | 热点算法输出正确 | `scripts/hotspot-analyzer.sh` 输出 Top-20 热点 | `evidence/hotspot-output.log` |
| V2 | 意图分析 4 维信号 | 检查 hook 输出包含 4 类信号 | `evidence/intent-output.log` |
| V3 | 子图检索保留边关系 | 检查输出包含 `--calls-->` 等关系 | `evidence/subgraph-output.log` |
| V4 | 边界识别正确 | `node_modules/` 标记为库代码 | `evidence/boundary-output.log` |
| V5 | Pattern Learner 学习 | 检查生成 `learned-patterns.json` | `.devbooks/learned-patterns.json` |
| V6 | 数据流追踪 | `--trace-data-flow` 输出参数流 | `evidence/dataflow-output.log` |
| V7 | AST Diff 增量更新 | 修改单文件后只更新相关节点 | `evidence/ast-diff-output.log` |

### 5.2 非功能验收

| ID | 验收项 | 阈值 | 验证方法 |
|----|--------|------|----------|
| N1 | 热点计算耗时 | < 5s（1000 文件） | `time scripts/hotspot-analyzer.sh` |
| N2 | 子图检索内存 | < 200MB 增量 | `pmap` 监控 |
| N3 | 增量索引耗时 | < 1s（单文件变更） | `time scripts/ast-diff.sh` |

### 5.3 回归验收

| ID | 验收项 | 验证方法 |
|----|--------|----------|
| REG1 | 现有 MCP 工具兼容 | 运行现有烟雾测试 |
| REG2 | CLI 兼容 | `ci-search --version` 正常 |
| REG3 | Bug Locator 基线 | 对比变更前后输出 |

---

## 6. Debate Packet（争议点）

### 6.1 需要辩论的问题

| ID | 争议点 | 正方观点 | 反方观点 | 建议裁决者 |
|----|--------|----------|----------|------------|
| D1 | 是否需要 Pattern Learner | 提升语义异常检测能力 | 误报风险高，增加复杂度 | Judge |
| D2 | 子图深度限制 | 深度 3 覆盖足够 | 复杂项目可能需要深度 4+ | Technical Lead |
| D3 | 边界配置粒度 | 目录级别足够 | 需支持 glob 模式 | User |
| D4 | 增量索引实现方式 | tree-sitter AST Diff | SCIP 增量模式 | Technical Lead |

### 6.2 不确定点

| ID | 不确定点 | 需要的输入 | 影响范围 |
|----|----------|------------|----------|
| U1 | tree-sitter 是否已安装 | 检查环境 | AST Diff 模块 |
| U2 | 大型 monorepo 性能表现 | 需要实际测试 | 热点算法、子图检索 |
| U3 | CKB MCP 是否必须可用 | 确认降级策略 | 子图检索 |

### 6.3 已知风险需讨论

| 风险 | 讨论点 |
|------|--------|
| R1（热点计算耗时） | 是否需要后台预计算 + 缓存？ |
| R2（Pattern Learner 误报） | 置信度阈值设为多少？0.8 还是 0.9？ |

---

## 7. Decision Log

### 7.1 决策状态

**`Approved`**（第三轮复审通过）

> **裁决说明**（2026-01-11 Judge）：
> - M1-M7 共 7 个必须修改项全部完成并验证通过
> - 所有争议点（D1-D4、U3）已裁决
> - 证据链完整，风险可控
> - 提案批准进入设计阶段

### 7.2 需要裁决的问题清单

1. **D1**: 是否采纳 Pattern Learner 模块？ ✅ 已裁决
2. **D2**: 子图检索深度限制设为多少？ ✅ 已裁决
3. **D3**: 边界配置是否需要支持 glob 模式？ ✅ 已裁决
4. **D4**: 增量索引采用 tree-sitter 还是 SCIP 增量模式？ ✅ 已裁决
5. **U3**: CKB MCP 不可用时的降级策略是否接受？ ✅ 已裁决

### 7.3 裁决记录

| 日期 | 裁决者 | 问题 ID | 裁决结果 | 理由 |
|------|--------|---------|----------|------|
| 2026-01-10 | Judge | D1 | **采纳**，置信度阈值 0.85 | 误报风险可通过阈值控制；功能开关可随时禁用 |
| 2026-01-10 | Judge | D2 | **深度 3**，支持 `--depth` 参数（最大 5） | 深度 3 覆盖 90% 场景；超大项目可手动调高 |
| 2026-01-10 | Judge | D3 | **支持 glob 模式** | monorepo 场景必需；实现成本低 |
| 2026-01-10 | Judge | D4 | **SCIP 增量模式**（前置：SCIP 索引可用） | tree-sitter 未安装；scip-typescript 已安装；**需先运行索引生成** |
| 2026-01-10 | Judge | U3 | **接受降级策略** | CKB 不可用时降级为 ripgrep 文本搜索 |

### 7.4 裁决附加说明

- **Pattern Learner 置信度**：默认阈值 0.85，低于此阈值的模式不输出警告
- **子图检索深度**：默认 3，CLI 参数 `--depth N` 可调整，最大允许 5
- **边界配置格式**：`config/boundaries.yaml` 支持 glob 模式（如 `**/vendor/**`）
- **增量索引实现**：利用 SCIP 索引的文件级更新能力，不引入 tree-sitter 依赖；**前置条件：SCIP 索引可用**
- **CKB 降级策略**：子图检索在 CKB 不可用时返回线性列表（兼容现有行为）

### 7.5 Challenger 质疑裁决（2026-01-10 第一轮）

| 日期 | 裁决者 | 质疑 ID | 裁决结果 | 必须修改项 |
|------|--------|---------|----------|------------|
| 2026-01-10 | Judge | B1（缺少基线数据） | **成立** | M1：补充基线测量任务，产出 `evidence/baseline-metrics.md` |
| 2026-01-10 | Judge | B2（SCIP 索引不可用） | **成立** | M2：明确 SCIP 索引前置依赖；M4：更新 D4 裁决条目 |
| 2026-01-10 | Judge | B3（测试覆盖为零） | **成立** | M3：`bug-locator.sh` 回归测试列为 Phase 3 前置 |

### 7.5.1 Challenger 质疑裁决（2026-01-10 第二轮复审）

| 日期 | 裁决者 | 质疑 ID | 裁决结果 | 必须修改项 |
|------|--------|---------|----------|------------|
| 2026-01-10 | Judge | B1-R2（基线数值缺失） | **成立** | M5：`evidence/baseline-metrics.md` 核心指标必须为具体数值（非"待测量"） |
| 2026-01-10 | Judge | B2-R2（回归测试不存在） | **成立** | M6：创建 `tests/bug-locator.bats` 或等效测试文件 |
| 2026-01-10 | Judge | B3-R2（项目画像不一致） | **成立** | M7：更新 `project-profile.md` SCIP 状态为"可用" |

### 7.5.2 第三轮复审裁决（2026-01-11）

| 日期 | 裁决者 | 决定 | 理由 |
|------|--------|------|------|
| 2026-01-11 | Judge | **Approved** | M1-M7 全部完成并验证通过；争议点已裁决；风险可控 |

**验证记录**：

| ID | 验证项 | 验证方式 | 结果 |
|----|--------|----------|------|
| V-M1 | 基线测量完成 | `evidence/baseline-metrics.md` 存在（182 行） | ✅ 通过 |
| V-M2 | SCIP 索引可用 | `index.scip` 存在（46533 字节） | ✅ 通过 |
| V-M3 | 回归测试定义 | `tests/bug-locator.bats` 存在（16 测试用例） | ✅ 通过 |
| V-M5 | 基线数值非空 | Top-5: 0%, 搜索命中率: 67%, 召回率: 67% | ✅ 通过 |
| V-M6 | 回归测试存在 | 文件存在性验证 | ✅ 通过 |
| V-M7 | 项目画像一致 | SCIP 状态"✅ 可用" | ✅ 通过 |

**非阻断项备注**（来自 Challenger，供后续参考）：

| ID | 建议 | 处理方式 |
|----|------|----------|
| NB1 | 在目标中说明 Top-5 基线为 0% | 可在 design.md 中补充 |
| NB2 | `jq` 依赖说明 | 已通过 skip 处理，可接受 |
| NB3 | 性能阈值可配置化 | 可在实现阶段考虑 |

### 7.6 必须修改项清单

| ID | 修改项 | 责任方 | 完成标准 | 状态 |
|----|--------|--------|----------|------|
| M1 | 补充基线指标测量任务 | Author / Test Owner | `evidence/baseline-metrics.md` 包含 Top-5 命中率等基线数值 | ✅ 已完成 |
| M2 | 明确 SCIP 索引前置依赖 | Author | Section 2.3 或 tasks.md 增加"P0: SCIP 索引生成"任务 | ✅ 已完成 |
| M3 | 回归测试列为 Phase 3 前置 | Author / Planner | tasks.md 明确：回归测试先于 `bug-locator.sh` 核心逻辑修改 | ✅ 已完成 |
| M4 | 更新 D4 裁决条目 | Author | D4 包含"前置：SCIP 索引可用" | ✅ 已完成 |
| M5 | 补充基线指标实际数值 | Author / Test Owner | `evidence/baseline-metrics.md` 中 Top-5 命中率等核心指标为具体数值 | ✅ 已完成 (Top-5: 0%, 搜索: 67%) |
| M6 | 创建回归测试定义 | Author / Test Owner | 存在 `tests/bug-locator.bats` 或等效测试文件 | ✅ 已完成 (18 测试用例) |
| M7 | 更新项目画像 SCIP 状态 | Author | `dev-playbooks/specs/_meta/project-profile.md` SCIP 状态更新为"可用" | ✅ 已完成 |

### 7.7 验证要求

| ID | 验证项 | 验证方式 | 证据落点 |
|----|--------|----------|----------|
| V-M1 | 基线测量完成 | 文件存在且数值非空 | `evidence/baseline-metrics.md` |
| V-M2 | SCIP 索引可用 | `index.scip` 存在 | 项目根目录 |
| V-M3 | 回归测试定义 | 测试文件存在 | `tests/bug-locator.bats` 或等效 |
| V-M5 | 基线数值非空 | 检查 Top-5 命中率等字段为具体数值（非"待测量"） | `evidence/baseline-metrics.md` |
| V-M6 | 回归测试存在 | `test -f tests/bug-locator.bats` 或等效 | 文件存在性 |
| V-M7 | 项目画像一致 | `project-profile.md` SCIP 状态与 `index.scip` 存在性一致 | 文档内容 |

---

## 8. 实施优先级建议

基于 ROI 分析，建议按以下顺序实施：

| 优先级 | 模块 | 实现难度 | 价值 |
|--------|------|----------|------|
| P1 | Hotspot Analyzer | 低 | 高 |
| P2 | Intent Analyzer (4维) | 低 | 高 |
| P3 | Subgraph Retrieval | 中 | 高 |
| P4 | Boundary Detector | 低 | 中 |
| P5 | Pattern Learner | 中 | 中 |
| P6 | Data Flow Tracer | 中 | 中 |
| P7 | AST Diff | 高 | 中 |

---

## 9. 下一步

1. ~~**Challenger 质疑**：请 `devbooks-proposal-challenger` 对本提案进行质疑~~ ✅ 已完成
2. ~~**Judge 裁决**：请 `devbooks-proposal-judge` 裁决争议点~~ ✅ 已完成（裁决：Revise）
3. ~~**Author 修订**：完成 M1-M4 修改项后重新提交复审~~ ✅ 已完成
4. ~~**Judge 复审**：请 `devbooks-proposal-judge` 对修订后的提案进行复审~~ ✅ 已完成（裁决：Revise）
5. ~~**Author 二次修订**：完成 M5-M7 修改项后再次提交复审~~ ✅ 已完成
   - M5：已测量基线指标（Top-5: 0%, 搜索命中率: 67%）
   - M6：已创建 `tests/bug-locator.bats`（18 测试用例）
   - M7：已更新 `project-profile.md` SCIP 状态
6. ~~**Judge 三次复审**：请 `devbooks-proposal-judge` 对修订后的提案进行复审~~ ✅ 已完成（裁决：**Approved**）
7. **设计文档**：请 `devbooks-design-doc` 产出 `design.md`
8. **实现计划**：请 `devbooks-implementation-plan` 产出 `tasks.md`
