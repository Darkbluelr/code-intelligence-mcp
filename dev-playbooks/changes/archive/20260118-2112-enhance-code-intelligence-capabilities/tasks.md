# Implementation Plan

**Change-ID**: `20260118-2112-enhance-code-intelligence-capabilities`
**Maintainer**: DevBooks Planner
**Created**: 2026-01-19
**Input**: `design.md` (12 ACs)
**Related Specs**: `dev-playbooks/specs/architecture/c4.md`

---

## 模式选择

**当前模式**: 主线计划模式 (Main Plan Mode)

---

## 主线计划区 (Main Plan Area)

### MP1: 上下文压缩（P0，AC-001）

**目的**: 实现基于 AST 的上下文压缩，将代码上下文压缩至 30-50%，保留关键信息。

**交付物**:
- `scripts/context-compressor.sh`（上下文压缩脚本）
- `tests/context-compressor.bats`（功能测试）
- `evidence/context-compression-test.log`（证据文件）

**影响范围**:
- 新增文件：`scripts/context-compressor.sh`
- 新增测试：`tests/context-compressor.bats`

**验收标准**:
- 压缩率达到 30-50%
- 信息保留率 > 85%
- 支持 TypeScript/JavaScript 文件
- 提供 `--compress` 参数（low/medium/high）
- `tests/context-compressor.bats` 全部通过

**依赖**: 无

**风险**: 压缩算法可能导致信息丢失

**子任务**:
- [x] MP1.1 创建 `scripts/context-compressor.sh` 脚本骨架，定义接口签名（输入：文件路径，输出：压缩后内容）
- [x] MP1.2 实现 AST 骨架抽取算法（保留函数签名、类型定义、导入导出，移除函数体细节）
- [x] MP1.3 实现压缩级别控制（low: 70%, medium: 50%, high: 30%）
- [x] MP1.4 添加信息保留率计算逻辑（基于关键节点保留比例）
- [x] MP1.5 编写 `tests/context-compressor.bats`，覆盖 3 种压缩级别和边界条件
- [x] MP1.6 运行测试并生成证据文件 `evidence/context-compression-test.log`

---

### MP2: 架构漂移检测（P0，AC-002）

**目的**: 检测代码与 C4 架构图的偏离，评分 > 50 时告警。

**交付物**:
- `scripts/drift-detector.sh`（漂移检测脚本）
- `tests/drift-detector.bats`（功能测试）
- `evidence/drift-detection-report.md`（漂移报告）

**影响范围**:
- 新增文件：`scripts/drift-detector.sh`
- 新增测试：`tests/drift-detector.bats`
- 依赖文件：`dev-playbooks/specs/architecture/c4.md`

**验收标准**:
- 计算漂移评分（0-100）
- 检测 4 种漂移类型（新增/删除/修改组件，新增依赖）
- 评分 > 50 时输出告警
- 生成 Markdown 格式漂移报告
- `tests/drift-detector.bats` 全部通过

**依赖**: 需要 `dev-playbooks/specs/architecture/c4.md` 存在

**风险**: C4 架构图格式不一致可能导致解析失败

**子任务**:
- [x] MP2.1 创建 `scripts/drift-detector.sh` 脚本骨架，定义接口签名（输入：C4 文件路径，输出：漂移报告）
- [x] MP2.2 实现 C4 架构图解析器（提取组件列表和依赖关系）
- [x] MP2.3 实现代码扫描器（基于 SCIP 索引或文件扫描，提取实际组件和依赖）
- [x] MP2.4 实现漂移评分算法（新增组件 +15 分，删除组件 +20 分，修改职责 +10 分，新增依赖 +5 分）
- [x] MP2.5 实现漂移报告生成器（Markdown 格式，包含漂移类型、评分、建议）
- [x] MP2.6 编写 `tests/drift-detector.bats`，覆盖 4 种漂移类型和评分阈值
- [x] MP2.7 运行测试并生成证据文件 `evidence/drift-detection-report.md`

---

### MP3: 数据流追踪（P0，AC-003）

**目的**: 在 `call-chain.sh` 中新增数据流追踪功能，支持 TypeScript/JavaScript。

**交付物**:
- 修改 `scripts/call-chain.sh`（新增 `--data-flow` 参数）
- `tests/data-flow-tracing.bats`（功能测试）
- `evidence/data-flow-tracing-test.log`（证据文件）

**影响范围**:
- 修改文件：`scripts/call-chain.sh`
- 新增测试：`tests/data-flow-tracing.bats`

**验收标准**:
- 支持 `--data-flow` 参数
- 输出数据流路径（变量 → 函数 → 返回值）
- 支持跨函数追踪（最多 5 跳）
- 不支持其他语言时返回友好错误提示
- `tests/data-flow-tracing.bats` 全部通过

**依赖**: 依赖现有的 `call-chain.sh` 和 SCIP 索引

**风险**: 跨函数追踪可能遇到动态调用或闭包，导致追踪不完整

**子任务**:
- [x] MP3.1 在 `scripts/call-chain.sh` 中新增 `--data-flow` 参数解析逻辑
- [x] MP3.2 实现数据流追踪算法（基于 SCIP 索引，提取变量定义、使用、传递关系）
- [x] MP3.3 实现跨函数追踪逻辑（最多 5 跳，避免循环依赖）
- [x] MP3.4 实现语言检测和友好错误提示（仅支持 TS/JS）
- [x] MP3.5 编写 `tests/data-flow-tracing.bats`，覆盖单函数、跨函数、循环依赖场景
- [x] MP3.6 运行测试并生成证据文件 `evidence/data-flow-tracing-test.log`


### MP4: 图查询加速（P1，AC-004 + AC-012）

**目的**: 使用闭包表优化图查询性能，P95 延迟 < 200ms。

**交付物**:
- 修改 `scripts/graph-store.sh`（新增闭包表和路径索引表）
- Schema 迁移脚本（v3 → v4）
- `tests/graph-store.bats`（功能测试）
- `evidence/graph-query-performance.json`（性能证据）
- `evidence/schema-migration-test.log`（迁移证据）

**影响范围**:
- 修改文件：`scripts/graph-store.sh`
- 新增表：`transitive_closure`, `path_index`
- Schema 版本：v3 → v4

**验收标准**:
- 图查询 P95 延迟 < 200ms（3 跳查询）
- 支持自动预计算和增量更新
- 提供 `--skip-precompute` 跳过预计算
- Schema 迁移自动备份和回滚
- `tests/graph-store.bats` 全部通过

**依赖**: 依赖现有的 `graph-store.sh` 和 SQLite

**风险**: 闭包表计算耗时过长，可能影响索引构建性能

**子任务**:
- [x] MP4.1 设计 Schema v4（新增 `transitive_closure` 和 `path_index` 表结构）
- [x] MP4.2 编写 Schema 迁移脚本（v3 → v4，包含备份和回滚逻辑）
- [x] MP4.3 在 `scripts/graph-store.sh` 中实现闭包表预计算逻辑（异步执行）
- [x] MP4.4 实现增量更新逻辑（仅更新受影响的闭包路径）
- [x] MP4.5 修改图查询函数，优先使用闭包表（降级至递归查询）
- [x] MP4.6 添加 `--skip-precompute` 参数支持
- [x] MP4.7 编写 `tests/graph-store.bats`，覆盖迁移、预计算、增量更新、性能测试
- [x] MP4.8 运行性能测试并生成证据文件 `evidence/graph-query-performance.json`
- [x] MP4.9 运行迁移测试并生成证据文件 `evidence/schema-migration-test.log`

---

### MP5: 混合检索（P1，AC-005）

**目的**: 实现关键词 + 向量 + 图距离的 RRF 融合，MRR@10 > 0.65。

**交付物**:
- 修改 `scripts/embedding.sh`（增强 `fusion_search()` 函数）
- 配置文件支持（权重配置）
- `tests/hybrid-retrieval.bats`（功能测试）
- `evidence/hybrid-retrieval-quality.json`（质量证据）

**影响范围**:
- 修改文件：`scripts/embedding.sh`
- 新增配置：`config/retrieval-weights.yaml`

**验收标准**:
- 实现 RRF 融合算法
- 默认权重：关键词 30%，向量 50%，图距离 20%
- 支持用户配置权重
- MRR@10 > 0.65
- 提供 A/B 测试框架
- `tests/hybrid-retrieval.bats` 全部通过

**依赖**: 依赖 MP4（图查询加速）

**风险**: 权重调优困难，可能需要多次迭代

**子任务**:
- [x] MP5.1 在 `scripts/embedding.sh` 中实现 RRF 融合算法（Reciprocal Rank Fusion）
- [x] MP5.2 实现权重配置加载逻辑（从 `config/retrieval-weights.yaml` 读取）
- [x] MP5.3 集成关键词搜索（基于 ripgrep）、向量搜索（基于 embedding）、图距离搜索（基于闭包表）
- [x] MP5.4 实现 A/B 测试框架（支持对比不同权重配置的效果）
- [x] MP5.5 编写 `tests/hybrid-retrieval.bats`，覆盖 RRF 融合、权重配置、A/B 测试
- [x] MP5.6 运行质量测试并生成证据文件 `evidence/hybrid-retrieval-quality.json`

---

### MP6: 默认重排序管线（P1，AC-006）

**目的**: 支持 LLM 和启发式两种重排序策略，MRR@10 提升 > 10%。

**交付物**:
- 修改 `scripts/reranker.sh`（新增两种策略）
- `tests/reranker.bats`（功能测试）
- `evidence/reranker-performance.json`（性能证据）

**影响范围**:
- 修改文件：`scripts/reranker.sh`

**验收标准**:
- 支持 LLM 重排序（使用 Ollama）
- 支持启发式重排序（基于规则）
- 提供 `--rerank-strategy` 参数
- LLM 超时时自- MRR@10 提升 > 10%
- `tests/reranker.bats` 全部通过

**依赖**: 依赖 MP5（混合检索）

**风险**: LLM 重排序可能超时或不可用

**子任务**:
- [x] MP6.1 在 `scripts/reranker.sh` 中新增 `--rerank-strategy` 参数解析逻辑
- [x] MP6.2 实现 LLM 重排序策略（调用 Ollama API，基于查询相关性重排）
- [x] MP6.3 实现启发式重排序策略（基于文件类型、最近修改时间、热度等规则）
- [x] MP6.4 实现超时和降级逻辑（LLM 超时 > 5s 时降级至启发式）
- [x] MP6.5 编写 `tests/reranker.bats`，覆盖两种策略、超时降级、性能对比
- [x] MP6.6 运行性能测试并生成证据文件 `evidence/reranker-performance.json`

---

### MP7: 上下文层信号（P2，AC-007）

**目的**: 记录用户交互信号并纳入检索权重。

**交付物**:
- `src/context-signal-manager.ts`（信号管理组件）
- 修改 `scripts/embedding.sh`（集成信号权重）
- `tests/long-term-memory.bats`（功能测试）
- `evidence/context-signals-test.log`（证据文件）

**影响范围**:
- 新增文件：`src/context-signal-manager.ts`
- 修改文件：`scripts/embedding.sh`
- 新增表：`user_signals`

**验收标准**:
- 记录用户交互信号（查看、编辑、忽略）
- 信号权重：查看 +1.5x，编辑 +2.0x，忽略 -0.5x
- 信号衰减机制（90 天后衰减至 0）
- 提供 `--enable-context-signals` 开关
- `tests/long-term-memory.bats` 全部通过

**依赖**: 依赖 MP5（混合检索）

**风险**: 信号收集可能影响性能

**子任务**:
- [x] MP7.1 设计 `user_signals` 表结构（文件路径、信号类型、时间戳、权重）
- [x] MP7.2 实现 `src/context-signal-manager.ts`（信号记录、查询、衰减逻辑）
- [x] MP7.3 在 `scripts/embedding.sh` 中集成信号权重（查询时加载信号并调整排序）
- [x] MP7.4 实现信号衰减机制（基于时间戳计算衰减系数）
- [x] MP7.5 添加 `--enable-context-signals` 开关支持
- [x] MP7.6 编写 `tests/long-term-memory.bats`，覆盖信号记录、权重调整、衰减机制
- [x] MP7.7 运行测试并生成证据文件 `evidence/context-signals-test.log`

---

### MP8: 语义异常检测（P2，AC-008）

**目的**: 检测代码模式异常并学习用户反馈。

**交付物**:
- `scripts/semantic-anomaly.sh`（异常检测脚本）
- `tests/semantic-anomaly.bats`（功能测试）
- `evidence/semantic-anomaly-report.md`（异常报告）

**影响范围**:
- 新增文件：`scripts/semantic-anomaly.sh`
- 新增测试：`tests/semantic-anomaly.bats`

**验收标准**:
- 检测代码模式异常（如突然出现的新模式）
- 学习用户反馈（标记为正常/异常）
- 生成 Markdown 格式异常报告
- 提供 `--enable-anomaly-detection` 开关
- `tests/semantic-anomaly.bats` 全部通过

**依赖**: 依赖 MP5（混合检索）和 Ollama

**风险**: 异常检测可能产生误报

**子任务**:
- [x] MP8.1 创建 `scripts/semantic-anomaly.sh` 脚本骨架，定义接口签名
- [x] MP8.2 实现代码模式提取逻辑（基于 embedding 聚类）
- [x] MP8.3 实现异常检测算法（基于距离阈值或孤立森林）
- [x] MP8.4 实现用户反馈学习逻辑（更新异常阈值）
- [x] MP8.5 实现异常报告生成器（Markdown 格式）
- [x] MP8.6 添加 `--enable-anomaly-detection` 开关支持
- [x] MP8.7 编写 `tests/semantic-anomaly.bats`，覆盖异常检测、反馈学习、报告生成
- [x] MP8.8 运行测试并生成证据文件 `evidence/semantic-anomaly-report.md`


### MP9: 评测基准（P3，AC-009）

**目的**: 建立自举和公开数据集的评测基准。

**交付物**:
- 修改 `scripts/benchmark.sh`（新增数据集支持）
- `tests/benchmark.bats`（功能测试）
- `evidence/benchmark-report.json`（评测报告）

**影响范围**:
- 修改文件：`scripts/benchmark.sh`
- 新增测试：`tests/benchmark.bats`

**验收标准**:
- 支持自举数据集（本项目代码库）
- 支持公开数据集（CodeSearchNet）
- 输出评测报告（JSON 格式），包含 MRR@10, Recall@10, P95 延迟
- 提供回归检测（与基线对比）
- `tests/benchmark.bats` 全部通过

**依赖**: 依赖 MP5（混合检索）和 MP6（重排序）

**风险**: 公开数据集下载和处理可能耗时

**子任务**:
- [x] MP9.1 在 `scripts/benchmark.sh` 中新增自举数据集支持（使用本项目代码库）
- [x] MP9.2 新增公开数据集支持（CodeSearchNet，提供下载和预处理脚本）
- [x] MP9.3 实现评测指标计算逻辑（MRR@10, Recall@10, P95 延迟）
- [x] MP9.4 实现回归检测逻辑（与基线对比，输出差异）
- [x] MP9.5 实现评测报告生成器（JSON 格式）
- [x] MP9.6 编写 `tests/benchmark.bats`，覆盖两种数据集、指标计算、回归检测
- [x] MP9.7 运行评测并生成证据文件 `evidence/benchmark-report.json`

---

### MP10: 功能开关与性能回退检测（AC-010 + AC-011）

**目的**: 提供功能开关和性能回退检测机制。

**交付物**:
- 修改 `config/features.yaml`（功能开关配置）
- 性能回退检测脚本
- `evidence/feature-toggle-test.log`（功能开关证据）
- `evidence/performance-regression-test.log`（性能回退证据）

**影响范围**:
- 修改文件：`config/features.yaml`
- 新增脚本：性能回退检测脚本

**验收标准**:
- 所有新功能通过配置文件控制
- 默认所有新功能关闭
- 提供 `--enable-all-features` 一键启用
- 建立性能基线（MRR@10 = 0.54, P95 = 1200ms）
- 检测阈值：P95 延迟 < 基线 × 1.1，MRR@10 > 基线 × 0.95
- 性能回退时输出告警

**依赖**: 依赖所有前置任务包

**风险**: 功能开关可能遗漏某些功能

**子任务**:
- [x] MP10.1 在 `config/features.yaml` 中添加所有新功能的开关配置
- [x] MP10.2 修改所有脚本，读取功能开关配置并控制功能启用
- [x] MP10.3 实现 `--enable-all-features` 参数支持
- [x] MP10.4 创建性能回退检测脚本（建立基线、运行测试、对比结果）
- [x] MP10.5 运行功能开关测试并生成证据文件 `evidence/feature-toggle-test.log`
- [x] MP10.6 运行性能回退测试并生成证据文件 `evidence/performance-regression-test.log`

---

## 临时计划区 (Temporary Plan Area)

（预留，用于计划外高优任务）

---

## 断点区 (Context Switch Breakpoint Area)

**当前状态**: 主线计划模式
**最后更新**: 2026-01-19
**断点信息**: 无

---

## 计划细化区

### Scope & Non-goals

**范围内**:
- 9 个核心功能点（上下文压缩、架构漂移检测、数据流追踪、图查询加速、混合检索、重排序管线、上下文层信号、语义异常检测、评测基准）
- 功能开关和性能回退检测
- Schema 迁移（v3 → v4）

**范围外**:
- 其他语言的数据流追踪（仅支持 TS/JS）
- 新的模型训练
- 修改现有 API
- 破坏向后兼容性

---

### Architecture Delta

**新增组件**:
- `scripts/context-compressor.sh`（上下文压缩）
- `scripts/drift-detector.sh`（架构漂移检测）
- `scripts/semantic-anomaly.sh`（语义异常检测）
- `src/context-signal-manager.ts`（上下文层信号管理）

**修改组件**:
- `scripts/call-chain.sh`（新增数据流追踪）
- `scripts/graph-store.sh`（新增闭包表）
- `scripts/embedding.sh`（增强混合检索）
- `scripts/reranker.sh`（新增重排序策略）
- `scripts/benchmark.sh`（新增数据集支持）

**依赖方向**:
```
scripts/context-compressor.sh → tree-sitter
scripts/drift-detector.sh → dev-playbooks/specs/architecture/c4.md
scripts/embedding.sh → scripts/graph-store.sh
scripts/reranker.sh → scripts/embedding.sh
src/context-signal-manager.ts → SQLite
```

**扩展点**:
- 重排序策略（可扩展新的策略）
- 压缩算法（可扩展新的压缩级别）
- 异常检测算法（可扩展新的检测方法）

---

### Data Contracts

**新增表结构**:

1. `transitive_closure`（闭包表）:
```sql
CREATE TABLE transitive_closure (
  ancestor TEXT NOT NULL,
  descendant TEXT NOT NULL,
  depth INTEGER NOT NULL,
  PRIMARY KEY (ancestor, descendant)
);
```

2. `path_index`（路径索引表）:
```sql
CREATE TABLE path_index (
  source TEXT NOT NULL,
  target TEXT NOT NULL,
  path TEXT NOT NULL,
  PRIMARY KEY (source, target)
);
```

3. `user_signals`（用户交互信号表）:
```sql
CREATE TABLE user_signals (
  file_path TEXT NOT NULL,
  signal_type TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  weight REAL NOT NULL,
  PRIMARY KEY (file_path, signal_type, timestamp)
);
```

**Schema 版本**: v3 → v4

**兼容策略**:
- 提供自动迁移脚本
- 迁移前自动备份
- 迁移失败时自动回滚

---

### Milestones

**Phase 1: P0 功能（关键路径）**
- MP1: 上下文压缩
- MP2: 架构漂移检测
- MP3: 数据流追踪
- **验收口径**: 所有 P0 功能测试通过，证据文件生成

**Phase 2: P1 功能（性能优化）**
- MP4: 图查询加速
- MP5: 混合检索
- MP6: 默认重排序管线
- **验收口径**: P95 延迟 < 200ms，MRR@10 > 0.65

**Phase 3: P2 功能（增强特性）**
- MP7: 上下文层信号
- MP8: 语义异常检测
- **验收口径**: 所有 P2 功能测试通过

**Phase 4: P3 功能（评测基准）**
- MP9: 评测基准
- **验收口径**: 评测报告生成，回归检测通过

**Phase 5: 集成与验收**
- MP10: 功能开关与性能回退检测
- **验收口径**: 所有功能开关生效，性能无回退，所有测试通过

---

### Work Breakdown

**PR 切分建议**:
- PR1: MP1（上下文压缩）- 独立功能，无依赖
- PR2: MP2（架构漂移检测）- 独立功能，无依赖
- PR3: MP3（数据流追踪）- 独立功能，依赖现有 call-chain.sh
- PR4: MP4（图查询加速 + Schema 迁移）- 关键依赖，需优先合并
- PR5: MP5（混合检索）- 依赖 PR4
- PR6: MP6（重排序管线）- 依赖 PR5
- PR7: MP7（上下文层信号）- 依赖 PR5
- PR8: MP8（语义异常检测）- 依赖 PR5
- PR9: MP9（评测基准）- 依赖 PR5, PR6
- PR10: MP10（功能开关与性能回退检测）- 依赖所有前置 PR

**可并行点**:
- MP1, MP2, MP3 可并行开发（P0 阶段）
- MP7, MP8 可并行开发（P2 阶段）

**依赖关系**:
```
MP4 (图查询加速)
  ↓
MP5 (混合检索)
  ↓
MP6 (重排序管线)
  ↓
MP7 (上下文层信号)
MP8 (语义异常检测)
  ↓
MP9 (评测基准)
  ↓
MP10 (功能开关与性能回退检测)
```

---

### Deprecation & Cleanup

**无弃用内容**: 本次变更为增量功能，不涉及弃用或删除现有功能。

**清理计划**:
- Schema 迁移完成后，删除 v3 备份文件（保留 30 天）
- 评测完成后，清理临时数据集文件

---

### Dependency Policy

**外部依赖**:
- tree-sitter（上下文压缩）
- jq（架构漂移检测）
- sqlite3（图查询加速、上下文层信号）
- Ollama（可选，重排序、语义异常检测）

**内部依赖**:
- 遵循现有脚本架构
- 禁止循环依赖
- 共享模块（common.sh, cache-utils.sh）不得依赖功能模块

**版本锁定**:
- tree-sitter: >= 0.20.0
- sqlite3: >= 3.35.0
- jq: >= 1.6

---

### Quality Gates

**静态检查**:
- ShellCheck 检查所有 Shell 脚本
- TypeScript 严格模式检查
- ESLint 检查

**复杂度**:
- 单个函数圈复杂度 < 15
- 单个脚本行数 < 500

**测试覆盖**:
- 所有新功能必须有对应的 Bats 测试
- 测试覆盖率 > 80%

**性能**:
- 图查询 P95 延迟 < 200ms
- 检索质量 MRR@10 > 0.65
- 上下文压缩率 30-50%


### Guardrail Conflicts

**潜在冲突**:
1. **200 行限制 vs 算法完整性**: MP4（图查询加速）的闭包表预计算逻辑可能超过 200 行
   - **评估**: 闭包表预计算是核心算法，拆分会破坏内聚性
   - **缓解**: 将预计算逻辑封装为独立函数，提供完整的单元测试和性能测试
   - **风险控制**: 提供 `--skip-precompute` 参数，支持跳过预计算

2. **并行开发 vs 依赖关系**: MP5-MP9 依赖 MP4，无法完全并行
   - **评估**: MP4 是关键路径，必须优先完成
   - **缓解**: MP1-MP3 可并行开发，MP7-MP8 可并行开发
   - **风险控制**: 明确依赖关系，避免阻塞

**决策**: 上述冲突已评估，风险可控，继续执行。

---

### Observability

**指标**:
- 图查询 P95 延迟（目标 < 200ms）
- 检索质量 MRR@10（目标 > 0.65）
- 上下文压缩率（目标 30-50%）
- 信息保留率（目标 > 85%）

**日志**:
- 所有脚本输出结构化日志（JSON 格式）
- 错误日志包含堆栈信息和上下文

**审计**:
- 用户交互信号记录到 `user_signals` 表
- Schema 迁移记录到迁移日志

---

### Rollout & Rollback

**灰度策略**:
- 所有新功能默认关闭（通过 `config/features.yaml` 控制）
- 提供 `--enable-all-features` 一键启用
- 支持单独启用某个功能

**回滚方案**:
- Schema 迁移失败时自动回滚到 v3
- 功能开关失败时不影响现有功能
- 提供手动回滚脚本

**数据迁移**:
- Schema v3 → v4 自动迁移
- 迁移前自动备份
- 迁移失败时自动恢复备份

---

### Risks & Edge Cases

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 闭包表计算耗时过长 | 中 | 中 | 异步预计算 + 增量更新 + `--skip-precompute` |
| 压缩算法信息丢失 | 中 | 高 | 提供压缩级别配置 + 信息保留率监控 |
| 混合检索权重调优困难 | 高 | 中 | 提供权重配置 + A/B 测试框架 |
| 9 个功能点集成复杂度高 | 高 | 高 | 分阶段集成 + 功能开关 + 性能回退检测 |
| LLM 重排序不可用 | 中 | 低 | 自动降级至启发式重排序 |
| 数据流追踪遇到动态调用 | 中 | 中 | 提供友好错误提示，标记为不支持 |
| C4 架构图格式不一致 | 低 | 中 | 提供格式验证和友好错误提示 |

**边界条件**:
- 空文件或空查询：返回空结果
- 超大文件（> 10MB）：跳过压缩，返回原文件
- 图查询深度 > 10：限制为 10 跳，避免性能问题
- 用户信号表过大（> 100万条）：自动清理 90 天前的记录

---

### Algorithm Spec

#### 1. RRF 融合算法（MP5）

**输入**:
- `keyword_results`: 关键词搜索结果列表（文件路径 + 分数）
- `vector_results`: 向量搜索结果列表（文件路径 + 分数）
- `graph_results`: 图距离搜索结果列表（文件路径 + 分数）
- `weights`: 权重配置（keyword_weight, vector_weight, graph_weight）

**输出**:
- `fused_results`: 融合后的结果列表（文件路径 + 融合分数）

**核心流程**:
```
FUNCTION rrf_fusion(keyword_results, vector_results, graph_results, weights):
  k = 60  // RRF 常数
  fused_scores = {}
  
  FOR EACH result IN keyword_results:
    rank = result.rank
    fused_scores[result.path] += weights.keyword * (1 / (k + rank))
  
  FOR EACH result IN vector_results:
    rank = result.rank
    fused_scores[result.path] += weights.vector * (1 / (k + rank))
  
  FOR EACH result IN graph_results:
    rank = result.rank
    fused_scores[result.path] += weights.graph * (1 / (k + rank))
  
  SORT fused_scores BY score DESC
  RETURN fused_scores
```

**复杂度**:
- 时间复杂度: O(n log n)，n 为结果总数
- 空间复杂度: O(n)

**边界条件**:
- 某个结果列表为空：跳过该列表
- 权重和 ≠ 1：自动归一化
- 重复文件路径：合并分数

---

#### 2. 闭包表预计算算法（MP4）

**输入**:
- `edges`: 边列表（source, target）

**输出**:
- `transitive_closure`: 闭包表（ancestor, descendant, depth）

**核心流程**:
```
FUNCTION precompute_closure(edges):
  closure = {}
  
  // 初始化：直接边
  FOR EACH edge IN edges:
    closure[(edge.source, edge.target)] = 1
  
  // Floyd-Warshall 算法
  FOR EACH node_k IN all_nodes:
    FOR EACH node_i IN all_nodes:
      FOR EACH node_j IN all_nodes:
        IF (node_i, node_k) IN closure AND (node_k, node_j) IN closure:
          depth = closure[(node_i, node_k)] + closure[(node_k, node_j)]
          IF (node_i, node_j) NOT IN closure OR depth < closure[(node_i, node_j)]:
            closure[(node_i, node_j)] = depth
  
  RETURN closure
```

**复杂度**:
- 时间复杂度: O(n³)，n 为节点数
- 空间复杂度: O(n²)

**失败模式**:
- 节点数 > 10000：超时，建议使用 `--skip-precompute`
- 循环依赖：检测并跳过

**边界条件**:
- 空边列表：返回空闭包表
- 自环：深度为 0
- 孤立节点：不出现在闭包表中

---

#### 3. 上下文压缩算法（MP1）

**输入**:
- `file_path`: 文件路径
- `compress_level`: 压缩级别（low/medium/high）

**输出**:
- `compressed_content`: 压缩后的内容
- `compression_ratio`: 压缩率

**核心流程**:
```
FUNCTION compress_context(file_path, compress_level):
  ast = PARSE_AST(file_path)
  
  IF compress_level == "low":
    KEEP function_signatures, class_definitions, imports, exports
    REMOVE function_bodies (keep first 3 lines)
  ELSE IF compress_level == "medium":
    KEEP function_signatures, class_definitions, imports, exports
    REMOVE function_bodies
  ELSE IF compress_level == "high":
    KEEP function_signatures, type_definitions, imports
    REMOVE class_bodies, function_bodies
  
  compressed_content = SERIALIZE_AST(ast)
  compression_ratio = LENGTH(compressed_content) / LENGTH(original_content)
  
  RETURN compressed_content, compression_ratio
```

**复杂度**:
- 时间复杂度: O(n)，n 为文件大小
- 空间复杂度: O(n)

**边界条件**:
- 解析失败：返回原文件
- 压缩后更大：返回原文件
- 空文件：返回空内容

---

### Open Questions

1. **混合检索权重调优**: 默认权重（关键词 30%，向量 50%，图距离 20%）是否需要根据不同场景动态调整？
   - **建议**: 先使用默认权重，后续根据 A/B 测试结果调整

2. **闭包表预计算时机**: 是否在索引构建时自动预计算，还是延迟到首次查询时？
   - **建议**: 索引构建时异步预计算，避免阻塞用户

3. **语义异常检测阈值**: 异常检测的距离阈值如何确定？
   - **建议**: 使用 95 分位数作为初始阈值，根据用户反馈动态调整

---

**编码计划结束**
