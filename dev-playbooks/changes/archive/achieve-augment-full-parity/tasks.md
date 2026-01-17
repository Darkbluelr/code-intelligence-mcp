# 编码计划：全面达到 Augment 代码智能水平

> **Change ID**: `achieve-augment-full-parity`
> **Plan Owner**: Planner (Claude)
> **Date**: 2026-01-16
> **Mode**: 主线计划模式
> **Input**: `dev-playbooks/changes/achieve-augment-full-parity/design.md`

---

## 主线计划区 (Main Plan Area)

### MP1: AST Delta 增量索引模块（M1）

**目的（Why）**：实现基于 tree-sitter 的增量 AST 解析，减少每次变更的索引时间，支持快速代码智能响应。

**交付物（Deliverables）**：
- `src/ast-delta.ts`：TypeScript tree-sitter 解析薄壳
- `scripts/ast-delta.sh`：协调解析、缓存、图更新
- 功能开关配置更新

**影响范围（Files/Modules）**：
- 新增：`src/ast-delta.ts`
- 新增：`scripts/ast-delta.sh`
- 修改：`config/features.yaml`（新增 `ast_delta` 配置节）

**验收标准（Acceptance Criteria）**：
- AC-F01：单文件更新 P95 < 100ms（±20%）

**依赖（Dependencies）**：
- tree-sitter npm 包安装（`tree-sitter`、`tree-sitter-typescript`）
- 现有 `scripts/graph-store.sh` 和 `scripts/scip-to-graph.sh`

**风险（Risks）**：
- tree-sitter npm 包兼容性问题（降级路径已设计）
- AST 缓存一致性问题（原子写入策略已设计）

**子任务**：

- [x] MP1.1 实现 TypeScript tree-sitter 解析薄壳（src/ast-delta.ts）
  - 接口：`parseTypeScript(code: string): AstNode`
  - 接口：`computeDelta(oldAst: AstNode, newAst: AstNode): AstDelta`
  - 接口：`serializeAst(ast: AstNode): string`
  - 数据结构：`AstNode`、`AstDelta`
  - 验收锚点：单元测试验证接口正确性

- [x] MP1.2 实现 AST Delta 协调脚本（scripts/ast-delta.sh）
  - 命令：`update <file-path>`（单文件增量更新）
  - 命令：`batch [--since <ref>]`（批量增量更新）
  - 命令：`status`（显示索引状态）
  - 命令：`clear-cache`（清理 AST 缓存）
  - 验收锚点：SC-AD-001、SC-AD-002 场景测试

- [x] MP1.3 实现索引协调状态机
  - 状态：IDLE → CHECK → INCREMENTAL/FULL_REBUILD/FALLBACK → CLEANUP
  - 决策条件：条件 A（增量更新）、条件 B（全量重建）、条件 C（降级）
  - 版本戳格式和存储位置
  - 验收锚点：SC-AD-003、SC-AD-005 场景测试

- [x] MP1.4 实现降级路径
  - 降级链：tree-sitter → SCIP 全量 → regex 匹配
  - 检测逻辑：`require('tree-sitter')` 成功/失败
  - 验收锚点：SC-AD-004 场景测试

- [x] MP1.5 实现原子写入策略
  - 写入临时文件后原子移动（mv）
  - PID 后缀隔离并发
  - 孤儿临时文件清理
  - 验收锚点：SC-AD-007 场景测试

- [x] MP1.6 更新功能开关配置
  - 新增 `ast_delta` 配置节到 `config/features.yaml`
  - 配置项：`enabled`、`cache_dir`、`cache_max_size_mb`、`cache_ttl_days`、`fallback_to_scip`

---

### MP2: 传递性影响分析模块（M2）

**目的（Why）**：实现多跳图遍历和置信度衰减算法，量化符号变更的传递性影响，帮助开发者评估变更风险。

**交付物（Deliverables）**：
- `scripts/impact-analyzer.sh`：多跳图遍历 + 置信度衰减

**影响范围（Files/Modules）**：
- 新增：`scripts/impact-analyzer.sh`
- 修改：`config/features.yaml`（新增 `impact_analyzer` 配置节）

**验收标准（Acceptance Criteria）**：
- AC-F02：5 跳内置信度正确计算

**依赖（Dependencies）**：
- `scripts/graph-store.sh`（图遍历查询）
- `scripts/common.sh`（通用函数）

**风险（Risks）**：
- 大型代码库遍历性能（深度限制已设计）
- 循环依赖处理（访问集合去重已设计）

**子任务**：

- [x] MP2.1 实现符号影响分析命令
  - 命令：`analyze <symbol> [--depth <n>] [--format json|md|mermaid]`
  - 参数：`--decay`（衰减系数）、`--threshold`（影响阈值）
  - 验收锚点：SC-IA-001 场景测试

- [x] MP2.2 实现文件级影响分析命令
  - 命令：`file <file-path> [--depth <n>]`
  - 逻辑：识别文件中所有符号 → 对每个符号执行影响分析 → 合并去重
  - 验收锚点：SC-IA-002 场景测试

- [x] MP2.3 实现置信度衰减算法
  - 公式：`Impact(node, depth) = base_impact × (decay_factor ^ depth)`
  - 默认参数：decay_factor=0.8, threshold=0.1
  - 验收锚点：SC-IA-003、SC-IA-004 场景测试

- [x] MP2.4 实现 BFS 图遍历
  - 边类型：CALLS、IMPORTS、DEFINES、MODIFIES
  - 深度限制保护（最大 5 跳）
  - 访问集合去重（防止循环）
  - 验收锚点：SC-IA-006 场景测试

- [x] MP2.5 实现多种输出格式
  - JSON 格式：包含 root、depth、affected 数组
  - Mermaid 格式：流程图语法，节点含置信度标注
  - Markdown 格式：表格形式
  - 验收锚点：SC-IA-005 场景测试

- [x] MP2.6 更新功能开关配置
  - 新增 `impact_analyzer` 配置节到 `config/features.yaml`
  - 配置项：`enabled`、`max_depth`、`decay_factor`、`threshold`、`cache_intermediate`

---

### MP3: COD 架构可视化模块（M3）

**目的（Why）**：生成代码库概览图（COD），支持 Mermaid 和 D3.js JSON 两种格式，帮助开发者理解架构和依赖关系。

**交付物（Deliverables）**：
- `scripts/cod-visualizer.sh`：可视化生成器

**影响范围（Files/Modules）**：
- 新增：`scripts/cod-visualizer.sh`
- 修改：`config/features.yaml`（新增 `cod_visualizer` 配置节）

**验收标准（Acceptance Criteria）**：
- AC-F03：Mermaid 输出可在 Mermaid Live Editor 渲染

**依赖（Dependencies）**：
- `scripts/graph-store.sh`（数据源）
- `scripts/hotspot-analyzer.sh`（热点数据源）

**风险（Risks）**：
- 大型代码库节点过多导致图不可读（层级抽象已设计）

**子任务**：

- [x] MP3.1 实现多层级可视化命令
  - 命令：`generate [--level 1|2|3] [--format mermaid|d3json]`
  - Level 1：系统上下文
  - Level 2：模块级
  - Level 3：文件级
  - 验收锚点：SC-CV-001 场景测试

- [x] MP3.2 实现模块级可视化命令
  - 命令：`module <module-path> [--format mermaid|d3json]`
  - 验收锚点：SC-CV-002 场景测试

- [x] MP3.3 实现 Mermaid 格式输出
  - 语法：`graph TD`、`subgraph`、`-->`
  - 热点着色：`style A fill:#ff6b6b`
  - 验收锚点：SC-CV-005 场景测试

- [x] MP3.4 实现 D3.js JSON 格式输出
  - Schema：nodes 数组、links 数组、metadata
  - 字段：id、group、hotspot、complexity
  - 验收锚点：SC-CV-006 场景测试

- [x] MP3.5 实现元数据集成
  - 热点着色集成（`--include-hotspots`）
  - 复杂度标注集成（`--include-complexity`）
  - 验收锚点：SC-CV-003、SC-CV-004 场景测试

- [x] MP3.6 更新功能开关配置
  - 新增 `cod_visualizer` 配置节到 `config/features.yaml`
  - 配置项：`enabled`、`output_formats`、`include_hotspots`、`include_complexity`

---

### MP4: 子图智能裁剪功能（M4）

**目的（Why）**：在 graph-rag 搜索中实现 Token 预算控制，通过优先级算法智能裁剪子图，确保输出不超过 LLM 上下文限制。

**交付物（Deliverables）**：
- `scripts/graph-rag.sh` 修改：新增 `--budget` 参数和裁剪逻辑

**影响范围（Files/Modules）**：
- 修改：`scripts/graph-rag.sh`
- 修改：`config/features.yaml`（新增 `smart_pruning` 配置节）

**验收标准（Acceptance Criteria）**：
- AC-F04：输出 Token 数 ≤ 预算值

**依赖（Dependencies）**：
- `scripts/graph-store.sh`（数据源）
- `scripts/intent-learner.sh`（偏好加权，可选）

**风险（Risks）**：
- Token 估算精度（保守估算策略已设计）

**子任务**：

- [x] MP4.1 实现 Token 预算参数
  - 参数：`--budget <tokens>`（默认 8000）
  - 参数：`--min-relevance`（最低相关度阈值）
  - 验收锚点：SC-SP-004 场景测试

- [x] MP4.2 实现优先级评分算法
  - 公式：`Priority = relevance × 0.4 + hotspot × 0.3 + (1/distance) × 0.3`
  - 验收锚点：SC-SP-002 场景测试

- [x] MP4.3 实现 Token 估算函数
  - 基础方法：字符数 / 4
  - 保守策略：宁多估不少估
  - 验收锚点：SC-SP-008 场景测试

- [x] MP4.4 实现贪婪选择策略
  - 按优先级降序排列
  - 贪婪选择直到预算耗尽
  - 不分割单个代码片段
  - 验收锚点：SC-SP-001、SC-SP-003 场景测试

- [x] MP4.5 实现边界情况处理
  - 零预算处理（SC-SP-005）
  - 单片段超预算处理（SC-SP-006）
  - 验收锚点：SC-SP-005、SC-SP-006 场景测试

- [x] MP4.6 更新功能开关配置
  - 新增 `smart_pruning` 配置节到 `config/features.yaml`
  - 配置项：`enabled`、`default_budget`、`priority_weights`

---

### MP5: 联邦虚拟边连接功能（M5）

**目的（Why）**：生成跨仓库的虚拟边，连接本地 API 调用与远程服务定义，支持跨仓库影响分析。

**交付物（Deliverables）**：
- `scripts/federation-lite.sh` 修改：新增虚拟边生成功能
- graph.db 扩展：新增 `virtual_edges` 表

**影响范围（Files/Modules）**：
- 修改：`scripts/federation-lite.sh`
- 修改：`scripts/graph-store.sh`（新增 virtual_edges 表 Schema）
- 修改：`config/features.yaml`（新增 `federation_virtual_edges` 配置节）

**验收标准（Acceptance Criteria）**：
- AC-F05：跨仓符号可查询，置信度正确计算

**依赖（Dependencies）**：
- `scripts/graph-store.sh`（虚拟边存储）
- `.devbooks/federation-index.json`（远程服务索引）

**风险（Risks）**：
- 模糊匹配精度（置信度阈值过滤已设计）

**子任务**：

- [x] MP5.1 扩展 graph.db Schema
  - 新增 `virtual_edges` 表
  - 索引：source、target、edge_type
  - 验收锚点：Schema DDL 执行成功

- [x] MP5.2 实现虚拟边生成命令
  - 命令：`generate-virtual-edges [--repo <name>]`
  - 逻辑：本地 API 调用检测 → 符号匹配 → 置信度计算 → 虚拟边写入
  - 验收锚点：SC-FV-001 场景测试

- [x] MP5.3 实现置信度计算算法
  - 公式：`confidence = exact_match × 0.6 + signature_similarity × 0.3 + contract_bonus × 0.1`
  - exact_match：精确=1.0、前缀=0.7、模糊=0.4
  - contract_bonus：Proto=0.1、OpenAPI=0.05、GraphQL=0.08
  - 验收锚点：SC-FV-002 场景测试

- [x] MP5.4 实现置信度阈值过滤
  - 默认阈值：0.5
  - 高置信阈值：0.8（标记）
  - 验收锚点：SC-FV-003、SC-FV-005 场景测试

- [x] MP5.5 实现虚拟边查询命令
  - 命令：`query-virtual <symbol>`
  - 参数：`--virtual-edges`、`--confidence`
  - 验收锚点：SC-FV-004 场景测试

- [x] MP5.6 实现模糊匹配算法
  - Jaro-Winkler 算法（或简化近似实现）
  - 验收锚点：SC-FV-008 场景测试

- [x] MP5.7 更新功能开关配置
  - 新增 `federation_virtual_edges` 配置节到 `config/features.yaml`
  - 配置项：`enabled`、`confidence_threshold`、`high_confidence_threshold`、`auto_sync`

---

### MP6: 意图偏好学习模块（M6）

**目的（Why）**：记录用户查询历史并学习偏好模式，为子图智能裁剪提供偏好加权，提升搜索结果相关性。

**交付物（Deliverables）**：
- `scripts/intent-learner.sh`：历史记录 + 偏好计算

**影响范围（Files/Modules）**：
- 新增：`scripts/intent-learner.sh`
- 新增：`.devbooks/intent-history.json`（运行时生成）
- 修改：`config/features.yaml`（新增 `intent_learner` 配置节）

**验收标准（Acceptance Criteria）**：
- AC-F06：历史记录正确存储和查询
- AC-F09：90 天自动清理

**依赖（Dependencies）**：
- `scripts/common.sh`（通用函数）

**风险（Risks）**：
- 历史文件损坏（恢复机制已设计）

**子任务**：

- [x] MP6.1 实现查询历史记录命令
  - 命令：`record <query> <symbols> [--action view|edit|ignore]`
  - 数据格式：id、timestamp、query、matched_symbols、user_action、session_id
  - 验收锚点：SC-IL-001 场景测试

- [x] MP6.2 实现偏好分数计算
  - 公式：`Preference(symbol) = frequency × recency_weight × click_weight`
  - recency_weight：`1 / (1 + days_since_last_query)`
  - 验收锚点：SC-IL-002 场景测试

- [x] MP6.3 实现偏好查询命令
  - 命令：`get-preferences [--top <n>] [--prefix <path>]`
  - 验收锚点：SC-IL-004、SC-IL-005 场景测试

- [x] MP6.4 实现 90 天自动清理机制
  - 命令：`cleanup [--days <n>]`
  - 触发：每次 intent-learner.sh 启动时
  - 最大条目数限制：10000
  - 验收锚点：SC-IL-003、SC-IL-006 场景测试

- [x] MP6.5 实现用户操作权重
  - 权重表：view=1.0、edit=2.0、ignore=0.5
  - 验收锚点：SC-IL-008 场景测试

- [x] MP6.6 实现历史文件损坏恢复
  - 检测损坏 → 备份（.bak）→ 创建新文件 → 警告日志
  - 验收锚点：SC-IL-009 场景测试

- [x] MP6.7 更新功能开关配置
  - 新增 `intent_learner` 配置节到 `config/features.yaml`
  - 配置项：`enabled`、`history_file`、`max_history_entries`、`auto_cleanup_days`、`privacy_mode`

---

### MP7: 安全漏洞基础追踪模块（M7）

**目的（Why）**：集成 npm audit 进行依赖漏洞扫描，追踪漏洞的依赖传播路径，帮助开发者识别和修复安全风险。

**交付物（Deliverables）**：
- `scripts/vuln-tracker.sh`：npm audit 集成 + 影响追踪

**影响范围（Files/Modules）**：
- 新增：`scripts/vuln-tracker.sh`
- 修改：`config/features.yaml`（新增 `vuln_tracker` 配置节）

**验收标准（Acceptance Criteria）**：
- AC-F07：npm audit 输出正确解析
- AC-F10：漏洞严重性阈值过滤正确

**依赖（Dependencies）**：
- npm（系统依赖）
- `scripts/graph-store.sh`（依赖追踪）
- `scripts/common.sh`（通用函数）

**风险（Risks）**：
- npm audit 输出格式变化（版本检测已设计）

**子任务**：

- [x] MP7.1 实现漏洞扫描命令
  - 命令：`scan [--format json|md] [--severity <level>] [--include-dev]`
  - 验收锚点：SC-VT-001 场景测试

- [x] MP7.2 实现 npm audit 格式适配
  - npm 7+ 格式：解析 `.vulnerabilities` 结构
  - npm 6.x 格式：解析 `.advisories` 结构
  - 版本检测函数：`detect_npm_audit_format()`
  - 验收锚点：SC-VT-002、SC-VT-003 场景测试

- [x] MP7.3 实现严重性等级过滤
  - 等级顺序：low < moderate < high < critical
  - 阈值过滤逻辑
  - 验收锚点：SC-VT-004 场景测试

- [x] MP7.4 实现依赖传播追踪命令
  - 命令：`trace <package-name>`
  - 显示依赖链和受影响文件
  - 验收锚点：SC-VT-005 场景测试

- [x] MP7.5 实现输出格式
  - JSON 格式：scan_time、total、by_severity、vulnerabilities
  - Markdown 格式：表格、严重性徽章
  - 验收锚点：SC-VT-007、SC-VT-008 场景测试

- [x] MP7.6 实现降级策略
  - npm audit 不可用：跳过并警告
  - 返回空结果，退出码 0
  - 验收锚点：SC-VT-006 场景测试

- [x] MP7.7 更新功能开关配置
  - 新增 `vuln_tracker` 配置节到 `config/features.yaml`
  - 配置项：`enabled`、`scanners`、`severity_threshold`、`auto_scan_on_install`

---

### MP8: MCP 工具注册与集成

**目的（Why）**：将新增的 5 个脚本注册为 MCP 工具，更新 server.ts 的工具定义，使 Claude Code 可以调用这些新能力。

**交付物（Deliverables）**：
- `src/server.ts` 修改：新增 5 个工具定义和处理逻辑

**影响范围（Files/Modules）**：
- 修改：`src/server.ts`

**验收标准（Acceptance Criteria）**：
- AC-F08：所有现有测试继续通过（向后兼容）

**依赖（Dependencies）**：
- MP1-MP7 全部完成

**风险（Risks）**：
- 工具定义 Schema 错误（单元测试覆盖）

**子任务**：

- [x] MP8.1 新增 ci_ast_delta 工具定义
  - inputSchema：file（可选）、since（可选）
  - 处理逻辑：调用 ast-delta.sh

- [x] MP8.2 新增 ci_impact 工具定义
  - inputSchema：symbol（必需）、depth（可选）、format（可选）
  - 处理逻辑：调用 impact-analyzer.sh

- [x] MP8.3 新增 ci_cod 工具定义
  - inputSchema：level（可选）、format（可选）、module（可选）
  - 处理逻辑：调用 cod-visualizer.sh

- [x] MP8.4 新增 ci_intent 工具定义
  - inputSchema：action（必需）、query（可选）、symbols（可选）
  - 处理逻辑：调用 intent-learner.sh

- [x] MP8.5 新增 ci_vuln 工具定义
  - inputSchema：action（必需）、package（可选）、severity（可选）
  - 处理逻辑：调用 vuln-tracker.sh

- [x] MP8.6 更新现有工具参数
  - ci_graph_rag：新增 `budget` 参数
  - ci_federation：新增 `virtual_edges` 参数

- [x] MP8.7 验证向后兼容性
  - 运行现有所有测试
  - 确保无回归
  - 验收锚点：`npm test` 全部通过

---

### MP9: 集成测试与性能验证

**目的（Why）**：验证各模块之间的集成正确性，收集性能数据，确保满足设计文档中的性能约束。

**交付物（Deliverables）**：
- 集成测试通过
- 性能报告

**影响范围（Files/Modules）**：
- 执行：全部测试文件
- 生成：`dev-playbooks/changes/achieve-augment-full-parity/evidence/`

**验收标准（Acceptance Criteria）**：
- 全部 AC-F01 到 AC-F10 验收通过

**依赖（Dependencies）**：
- MP1-MP8 全部完成

**风险（Risks）**：
- 性能未达标（需回退优化）

**子任务**：

- [x] MP9.1 运行 AST Delta + Graph Store 集成测试
  - 验证增量更新写入 graph.db
  - 验收锚点：`tests/integration/ast-graph.bats`（Test Owner 产出）

- [x] MP9.2 运行 Impact Analyzer + Graph Store 集成测试
  - 验证图遍历查询性能
  - 验收锚点：`tests/integration/impact-graph.bats`（Test Owner 产出）

- [x] MP9.3 运行 Smart Pruning + Intent Learner 集成测试
  - 验证偏好加权裁剪
  - 验收锚点：`tests/integration/pruning-rerank.bats`（Test Owner 产出）

- [x] MP9.4 运行 Virtual Edges + Federation 集成测试
  - 验证虚拟边与契约索引协作
  - 验收锚点：`tests/integration/federation-edges.bats`（Test Owner 产出）

- [x] MP9.5 收集性能数据并生成报告
  - AST Delta 性能：P95 延迟
  - 影响分析性能：5 跳响应时间
  - 输出：`evidence/performance-report.md`

- [x] MP9.6 全量回归测试
  - 运行 `npm test`
  - 确保所有现有测试通过

---

## 临时计划区 (Temporary Plan Area)

> 本区域用于计划外高优任务。当前无临时任务。

**模板**：

```markdown
### TP1: [临时任务名称]

**触发原因**：[为什么需要临时任务]
**影响面**：[受影响的文件/模块]
**最小修复范围**：[最小必要变更]
**回归测试要求**：[需要运行的测试]
**与主线计划关系**：[是否阻塞主线/可并行]

- [ ] TP1.1 [子任务]
```

---

## 计划细化区 (Plan Detail Area)

### Scope & Non-goals

**范围内**：
- 7 个新模块实现（M1-M7）
- 5 个新脚本 + 1 个 TypeScript 模块
- 2 个现有脚本增强
- 5 个新 MCP 工具 + 2 个工具参数扩展
- 7 个功能开关配置

**范围外（Non-goals）**：
- OSV-scanner 集成（vuln-tracker 仅支持 npm audit）
- 实时 AST 监控（仅支持命令触发）
- 远程意图同步（隐私优先，纯本地存储）
- 交互式 D3.js 前端（仅输出 JSON 数据）

---

### Architecture Delta

**新增依赖关系**：

| 源 | 目标 | 类型 | 说明 |
|----|------|------|------|
| ast-delta.sh | graph-store.sh | CALLS | 增量写入图存储 |
| ast-delta.sh | scip-to-graph.sh | CALLS | 降级时全量重建 |
| impact-analyzer.sh | graph-store.sh | CALLS | 图遍历查询 |
| cod-visualizer.sh | graph-store.sh | CALLS | 数据源 |
| cod-visualizer.sh | hotspot-analyzer.sh | CALLS | 热点数据源 |
| graph-rag.sh | intent-learner.sh | CALLS | 偏好加权 |
| vuln-tracker.sh | graph-store.sh | CALLS | 依赖追踪 |

**分层归属**：

| 脚本 | 层级 | 依赖层级 |
|------|------|----------|
| ast-delta.sh | core | shared, graph-store |
| impact-analyzer.sh | core | shared, graph-store |
| cod-visualizer.sh | core | shared, graph-store, hotspot-analyzer |
| intent-learner.sh | core | shared |
| vuln-tracker.sh | core | shared, graph-store |
| src/ast-delta.ts | integration | Node.js tree-sitter |

---

### Data Contracts

**新增数据结构**：

1. **AstNode**（src/ast-delta.ts）
   - id: string（file_path:node_type:start_line）
   - type: string（function_declaration, class_declaration 等）
   - name?: string
   - startLine: number
   - endLine: number
   - children: AstNode[]

2. **AstDelta**（src/ast-delta.ts）
   - added: AstNode[]
   - removed: AstNode[]
   - modified: Array<{ old: AstNode; new: AstNode }>

3. **virtual_edges 表**（graph.db）
   - id: TEXT PRIMARY KEY
   - source_repo, source_symbol: TEXT NOT NULL
   - target_repo, target_symbol: TEXT NOT NULL
   - edge_type: TEXT NOT NULL（VIRTUAL_CALLS/VIRTUAL_IMPORTS）
   - contract_type: TEXT NOT NULL（proto/openapi/graphql/typescript）
   - confidence: REAL DEFAULT 1.0
   - created_at, updated_at: TEXT

4. **intent-history.json**
   - version: "1.0"
   - entries: Array<{ id, timestamp, query, matched_symbols, user_action, session_id }>
   - preferences: Map<symbol, { frequency, last_query, score }>

**兼容策略**：
- 新增表/字段，不修改现有结构
- 功能开关控制新功能启用

---

### Milestones

| Phase | 内容 | 验收口径 |
|-------|------|----------|
| Phase 1 | MP1（AST Delta） | AC-F01 通过 |
| Phase 2 | MP2、MP3（分析与可视化） | AC-F02、AC-F03 通过 |
| Phase 3 | MP4、MP6（智能优化） | AC-F04、AC-F06、AC-F09 通过 |
| Phase 4 | MP5、MP7（扩展能力） | AC-F05、AC-F07、AC-F10 通过 |
| Phase 5 | MP8、MP9（集成验收） | AC-F08 + 全部 AC 通过 |

---

### Work Breakdown

**PR 切分建议**：

| PR | 内容 | 依赖 | 可并行 |
|----|------|------|--------|
| PR1 | MP1（AST Delta） | 无 | 是 |
| PR2 | MP2（影响分析） | 无 | 是 |
| PR3 | MP3（COD 可视化） | 无 | 是 |
| PR4 | MP4（智能裁剪） | MP6（可选） | 否 |
| PR5 | MP5（虚拟边） | 无 | 是 |
| PR6 | MP6（意图学习） | 无 | 是 |
| PR7 | MP7（漏洞追踪） | 无 | 是 |
| PR8 | MP8（MCP 集成） | PR1-PR7 | 否 |
| PR9 | MP9（集成测试） | PR8 | 否 |

**可并行点**：PR1、PR2、PR3、PR5、PR6、PR7 可并行开发。

---

### Deprecation & Cleanup

本次变更无弃用项。

---

### Dependency Policy

**新增依赖**：

| 包名 | 版本 | 用途 |
|------|------|------|
| tree-sitter | ^0.21.x | AST 解析 |
| tree-sitter-typescript | ^0.21.x | TypeScript 语法支持 |

**安装方式**：
```bash
npm install tree-sitter tree-sitter-typescript
```

**降级策略**：依赖不可用时降级到 SCIP/regex 解析。

---

### Quality Gates

| 检查项 | 阈值 | 工具 |
|--------|------|------|
| 单元测试覆盖 | 行覆盖 > 80% | bats |
| TypeScript 类型检查 | 0 errors | tsc |
| Shell 脚本检查 | 0 errors | shellcheck |
| 代码复杂度 | 单函数 < 50 行 | 人工审查 |

---

### Guardrail Conflicts

**已识别冲突**：无。

**代理指标评估**：
- 本计划遵循"≤200 行/子任务"软约束
- 部分子任务（如 MP1.2 协调脚本）可能略超，但因结构完整性需求可接受

---

### Observability

**日志落点**：
- 所有脚本使用 `scripts/common.sh` 的 `log_info`、`log_warn`、`log_error`
- AST Delta 性能日志：解析耗时、缓存命中率
- 影响分析日志：遍历深度、节点数量

**指标**：
- AST Delta P95 延迟
- 影响分析平均响应时间
- 意图历史条目数

---

### Rollout & Rollback

**灰度策略**：
- 所有新功能默认通过功能开关控制
- 初始可设置 `enabled: false`，逐步开启

**回滚条件**：
- 任一功能导致现有测试失败
- 性能严重下降（P95 > 5s）

**回滚步骤**：
1. 设置功能开关 `enabled: false`
2. 必要时回退代码变更

---

### Risks & Edge Cases

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| tree-sitter 兼容性 | 中 | 中 | 多级降级路径 |
| npm audit 格式变化 | 低 | 低 | 版本检测适配 |
| 大规模代码库性能 | 中 | 中 | 深度限制、Token 预算 |
| 意图历史损坏 | 低 | 低 | 自动恢复机制 |

---

### Algorithm Spec

#### ALG-001: 置信度衰减算法（M2 影响分析）

**输入/输出**：
- 输入：起始符号 S、最大深度 D、衰减系数 F、阈值 T
- 输出：受影响节点列表 [{symbol, depth, impact}]

**关键不变量**：
- 0 < F < 1
- impact 单调递减
- 无重复节点

**失败模式**：
- 循环依赖导致无限循环 → 访问集合去重
- 深度过大导致超时 → 硬性深度限制

**核心流程**：
```
INITIALIZE visited = empty set
INITIALIZE queue = [(S, 0, 1.0)]
INITIALIZE result = []

WHILE queue is not empty:
    (node, depth, impact) = DEQUEUE from queue
    IF node in visited THEN CONTINUE
    ADD node to visited

    IF impact >= T THEN
        APPEND {node, depth, impact} to result

    IF depth < D THEN
        FOR EACH caller of node:
            new_impact = impact * F
            IF new_impact >= T THEN
                ENQUEUE (caller, depth+1, new_impact)

RETURN result sorted by impact descending
```

**复杂度**：
- 时间：O(V + E) 其中 V 为节点数，E 为边数
- 空间：O(V) 访问集合

**边界条件测试要点**：
1. 起始符号无调用者 → 返回空结果
2. 存在循环依赖 → 正确去重
3. 深度恰好等于 D → 包含在结果中
4. 深度等于 D+1 → 不包含
5. impact 恰好等于 T → 包含在结果中

---

#### ALG-002: 优先级评分算法（M4 智能裁剪）

**输入/输出**：
- 输入：候选片段列表 [{content, relevance, hotspot, distance}]、预算 B
- 输出：选中片段列表（Token 总数 ≤ B）

**关键不变量**：
- 输出 Token 数 ≤ B
- 不分割单个片段
- 优先级高的片段优先选中

**失败模式**：
- 所有片段都超预算 → 返回空或警告
- 预算为 0 → 返回空

**核心流程**：
```
FOR EACH fragment in candidates:
    fragment.tokens = ESTIMATE_TOKENS(fragment.content)
    fragment.priority = relevance * 0.4 + hotspot * 0.3 + (1/distance) * 0.3

SORT candidates by priority descending

INITIALIZE selected = []
INITIALIZE total_tokens = 0

FOR EACH fragment in candidates:
    IF total_tokens + fragment.tokens <= B THEN
        APPEND fragment to selected
        total_tokens = total_tokens + fragment.tokens

RETURN selected
```

**复杂度**：
- 时间：O(N log N) 排序
- 空间：O(N)

**边界条件测试要点**：
1. 预算为 0 → 返回空
2. 单个片段超预算 → 跳过该片段
3. 所有片段超预算 → 返回空 + 警告
4. 预算恰好用完 → 正确处理
5. 多个片段优先级相同 → 稳定排序

---

#### ALG-003: 偏好分数计算（M6 意图学习）

**输入/输出**：
- 输入：历史记录列表 [{symbol, timestamp, action}]
- 输出：偏好分数映射 {symbol → score}

**关键不变量**：
- score ≥ 0
- recency_weight ∈ (0, 1]

**失败模式**：
- 历史为空 → 返回空映射
- 时间戳格式错误 → 跳过该记录

**核心流程**：
```
INITIALIZE preferences = empty map
INITIALIZE action_weights = {view: 1.0, edit: 2.0, ignore: 0.5}

FOR EACH entry in history:
    symbol = entry.symbol
    days_since = DAYS_BETWEEN(entry.timestamp, NOW)
    recency_weight = 1 / (1 + days_since)
    action_weight = action_weights[entry.action] or 1.0

    IF symbol not in preferences THEN
        preferences[symbol] = {frequency: 0, total_weight: 0}

    preferences[symbol].frequency += 1
    preferences[symbol].total_weight += recency_weight * action_weight

FOR EACH symbol in preferences:
    avg_weight = preferences[symbol].total_weight / preferences[symbol].frequency
    preferences[symbol].score = preferences[symbol].frequency * avg_weight

RETURN preferences
```

**复杂度**：
- 时间：O(N) 其中 N 为历史条目数
- 空间：O(M) 其中 M 为唯一符号数

**边界条件测试要点**：
1. 历史为空 → 返回空映射
2. 同一符号多次查询 → 正确累加
3. 查询时间为今天 → recency_weight = 0.5
4. 查询时间为 100 天前 → recency_weight ≈ 0.01
5. 不同 action 权重不同 → 正确加权

---

## 断点区 (Context Switch Breakpoint Area)

> 本区域用于记录主线/临时计划切换时的上下文。

**模板**：

```markdown
### Breakpoint: [日期时间]

**切换原因**：[为什么切换]
**当前进度**：[完成的任务包/子任务]
**下一步**：[切换回来后的第一个任务]
**阻塞项**：[如有阻塞，记录阻塞原因]
**依赖状态**：[外部依赖的当前状态]
```

---

## Design Backport Candidates（需回写设计）

> 无需回写设计的候选项。本计划完全可追溯到设计文档。

---

## Open Questions（待澄清问题）

1. **tree-sitter TypeScript 解析器对 JSX/TSX 的支持程度**
   - 假设：使用 `tree-sitter-tsx` 替代或补充
   - 分支方案：如不支持 TSX，降级到 SCIP 解析

2. **意图历史与 graph-rag 集成的调用时机**
   - 假设：graph-rag.sh 启动时调用 intent-learner.sh get-preferences
   - 分支方案：可配置是否启用偏好加权

3. **Jaro-Winkler 算法的 Shell 实现复杂度**
   - 假设：使用简化近似实现（前缀匹配 + 字符重叠率）
   - 分支方案：如需精确实现，外部调用 Python/Node.js

---

**Plan Owner 签名**：Planner (Claude)
**日期**：2026-01-16
