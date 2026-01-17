# 规格：M3 COD 架构可视化

> **模块 ID**: `cod-visualizer`
> **Change ID**: `achieve-augment-full-parity`
> **Date**: 2026-01-16
> **Status**: Draft

---

## Requirements（需求）

### REQ-CV-001: 多层级可视化

系统必须支持多个抽象层级的架构可视化。

**约束**：
- Level 1：系统上下文（外部用户、外部服务）
- Level 2：模块级（src/、scripts/、hooks/、config/）
- Level 3：文件级（单模块内的文件关系）

### REQ-CV-002: Mermaid 输出格式

系统必须支持 Mermaid 格式输出，可嵌入 Markdown 文档。

**约束**：
- 输出有效的 Mermaid flowchart 语法
- 支持 GitHub/GitLab 原生渲染
- 包含子图（subgraph）划分

### REQ-CV-003: D3.js JSON 输出格式

系统必须支持 D3.js JSON 格式输出，用于交互式可视化。

**约束**：
- nodes 数组包含：id、group、hotspot、complexity
- links 数组包含：source、target、type
- metadata 包含：generated_at、level、total_nodes、total_edges

### REQ-CV-004: 元数据集成

可视化必须集成代码质量元数据。

**约束**：
- 热点着色（hotspot score）
- 复杂度标注（complexity）
- 可选：所有权标记、变更频率

---

## Scenarios（场景）

### SC-CV-001: 模块级 Mermaid 输出

**Given**：
- graph.db 中存在模块依赖关系

**When**：
- 调用 `cod-visualizer.sh generate --level 2 --format mermaid`

**Then**：
- 系统查询模块级依赖关系
- 生成 Mermaid flowchart 语法
- 模块作为子图（subgraph）
- 依赖作为箭头（-->）

**验证**：`tests/cod-visualizer.bats::test_module_mermaid`

### SC-CV-002: 文件级 D3.js JSON 输出

**Given**：
- 指定模块 `scripts/`

**When**：
- 调用 `cod-visualizer.sh module scripts/ --format d3json`

**Then**：
- 系统查询 scripts/ 目录下文件的依赖关系
- 生成 D3.js JSON 格式
- 每个文件作为 node
- 调用/依赖作为 link
- 包含 hotspot 和 complexity 字段

**验证**：`tests/cod-visualizer.bats::test_file_d3json`

### SC-CV-003: 热点着色集成

**Given**：
- 启用 `--include-hotspots` 选项
- hotspot-analyzer.sh 有数据

**When**：
- 调用 `cod-visualizer.sh generate --level 2 --include-hotspots`

**Then**：
- Mermaid 输出包含 `style` 指令
- 热点文件标记为红色（#ff6b6b）
- 中等热点标记为黄色（#ffd93d）
- D3.js JSON 的 node.hotspot 字段填充正确值

**验证**：`tests/cod-visualizer.bats::test_hotspot_coloring`

### SC-CV-004: 复杂度标注集成

**Given**：
- 启用 `--include-complexity` 选项

**When**：
- 调用 `cod-visualizer.sh generate --level 3 --include-complexity`

**Then**：
- 节点标签包含复杂度数值
- D3.js JSON 的 node.complexity 字段填充正确值

**验证**：`tests/cod-visualizer.bats::test_complexity_annotation`

### SC-CV-005: Mermaid 语法有效性

**Given**：
- 任意层级的可视化输出

**When**：
- 生成 Mermaid 输出

**Then**：
- 输出可在 Mermaid Live Editor（https://mermaid.live）成功渲染
- 无语法错误

**验证**：`tests/cod-visualizer.bats::test_mermaid_syntax_valid`

### SC-CV-006: D3.js JSON Schema 有效性

**Given**：
- 任意层级的 D3.js JSON 输出

**When**：
- 生成 D3.js JSON 输出

**Then**：
- JSON 符合预定义 Schema
- 所有必需字段存在
- 数据类型正确

**验证**：`tests/cod-visualizer.bats::test_d3json_schema_valid`

### SC-CV-007: 空模块处理

**Given**：
- 指定模块无任何文件或依赖

**When**：
- 调用 `cod-visualizer.sh module empty-module/`

**Then**：
- 返回空图或提示信息
- 不报错

**验证**：`tests/cod-visualizer.bats::test_empty_module`

### SC-CV-008: 输出到文件

**Given**：
- 指定输出文件路径

**When**：
- 调用 `cod-visualizer.sh generate --output /tmp/arch.mmd`

**Then**：
- 可视化结果写入指定文件
- 标准输出显示成功消息

**验证**：`tests/cod-visualizer.bats::test_output_to_file`

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios |
|-------------|-----------|
| REQ-CV-001 | SC-CV-001, SC-CV-002 |
| REQ-CV-002 | SC-CV-001, SC-CV-005 |
| REQ-CV-003 | SC-CV-002, SC-CV-006 |
| REQ-CV-004 | SC-CV-003, SC-CV-004 |

| Scenario | Test ID |
|----------|---------|
| SC-CV-001 | `tests/cod-visualizer.bats::test_module_mermaid` |
| SC-CV-002 | `tests/cod-visualizer.bats::test_file_d3json` |
| SC-CV-003 | `tests/cod-visualizer.bats::test_hotspot_coloring` |
| SC-CV-004 | `tests/cod-visualizer.bats::test_complexity_annotation` |
| SC-CV-005 | `tests/cod-visualizer.bats::test_mermaid_syntax_valid` |
| SC-CV-006 | `tests/cod-visualizer.bats::test_d3json_schema_valid` |
| SC-CV-007 | `tests/cod-visualizer.bats::test_empty_module` |
| SC-CV-008 | `tests/cod-visualizer.bats::test_output_to_file` |
