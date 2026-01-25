# 验证计划：achieve-augment-full-parity

> **Change ID**: `achieve-augment-full-parity`
> **Test Owner**: Test Owner (Claude)
> **Date**: 2026-01-16
> **Status**: Archived
> **Archived Date**: 2026-01-16

---

## 测试策略

### 测试类型分布

| 测试类型 | 数量 | 用途 | 预期耗时 |
|----------|------|------|----------|
| 单元测试 | 45 | 核心逻辑、边界条件、算法验证 | < 5s/文件 |
| 集成测试 | 8 | 模块协作、数据流验证 | < 30s/文件 |
| 性能测试 | 3 | P95 延迟、Token 预算验证 | < 60s |
| 契约测试 | 0 | 本变更无外部 API 契约 | N/A |

### 测试环境

| 测试类型 | 环境 | 依赖 |
|----------|------|------|
| 单元测试 | Node.js + Bash | bats-core, jq, sqlite3 |
| 集成测试 | Node.js + Bash | graph.db, 现有脚本 |
| 性能测试 | Node.js + Bash | tree-sitter (可选) |

---

## AC 覆盖矩阵

| AC-ID | 描述 | 测试类型 | Test ID | 优先级 | 状态 |
|-------|------|----------|---------|--------|------|
| AC-F01 | AST Delta 单文件更新 P95 < 100ms（±20%） | 性能 | T-AD-006 | P0 | [x] |
| AC-F02 | 传递性影响分析：5 跳内置信度正确计算 | 单元 | T-IA-003, T-IA-004 | P0 | [x] |
| AC-F03 | COD 可视化：Mermaid 输出可渲染 | 单元 | T-CV-005, T-CV-006 | P0 | [x] |
| AC-F04 | 子图智能裁剪：输出 Token 数 ≤ 预算值 | 单元 | T-SP-001, T-SP-003 | P0 | [x] |
| AC-F05 | 联邦虚拟边：跨仓符号可查询，置信度正确 | 单元 | T-FV-001, T-FV-002, T-FV-004 | P0 | [x] |
| AC-F06 | 意图偏好学习：历史记录正确存储和查询 | 单元 | T-IL-001, T-IL-002, T-IL-004 | P0 | [x] |
| AC-F07 | 安全漏洞追踪：npm audit 输出正确解析 | 单元 | T-VT-001, T-VT-002, T-VT-003 | P0 | [x] |
| AC-F08 | 所有现有测试继续通过（向后兼容） | 集成 | T-INT-001 | P0 | [x] |
| AC-F09 | 意图历史 90 天自动清理 | 单元 | T-IL-003 | P1 | [x] |
| AC-F10 | 漏洞严重性阈值过滤正确 | 单元 | T-VT-004 | P1 | [x] |

**覆盖摘要**：
- AC 总数：10
- 已有测试覆盖：10
- 覆盖率：100%（Green 验证通过）
- 验证日期：2026-01-16

---

## 测试文件规划

### 新增测试文件

| 文件路径 | 覆盖模块 | 场景数量 |
|----------|----------|----------|
| `tests/ast-delta.bats` | M1: AST Delta | 7 |
| `tests/impact-analyzer.bats` | M2: 影响分析 | 7 |
| `tests/cod-visualizer.bats` | M3: COD 可视化 | 8 |
| `tests/vuln-tracker.bats` | M7: 漏洞追踪 | 10 |
| `tests/intent-learner.bats` | M6: 意图学习 | 9 |

### 现有测试文件扩展

| 文件路径 | 新增场景 | 说明 |
|----------|----------|------|
| `tests/graph-rag.bats` | 8 | M4: 智能裁剪 |
| `tests/federation-lite.bats` | 8 | M5: 虚拟边 |

### 集成测试文件

| 文件路径 | 覆盖内容 |
|----------|----------|
| `tests/integration/ast-graph.bats` | AST Delta + Graph Store |
| `tests/integration/impact-graph.bats` | Impact Analyzer + Graph Store |
| `tests/integration/pruning-rerank.bats` | Smart Pruning + Intent Learner |
| `tests/integration/federation-edges.bats` | Virtual Edges + Federation |

---

## 边界条件检查清单

### 输入验证

- [x] 空输入 / null 值（各模块 empty 场景）
- [x] 超过最大长度（历史条目数限制）
- [x] 无效格式（JSON 解析失败）
- [ ] SQL 注入 / XSS 尝试（不适用，无外部输入）

### 状态边界

- [x] 第一项（index 0）
- [x] 最后一项（index n-1）
- [x] 空集合（空历史、空图）
- [x] 单元素集合
- [x] 最大容量（10000 条历史）

### 并发与时序

- [x] 并发访问同一资源（原子写入测试）
- [x] 请求超时处理（深度限制保护）
- [x] 竞态条件场景（AST 缓存并发写入）
- [ ] 失败后重试（不适用）

### 错误处理

- [x] 网络故障（npm audit 降级）
- [x] 数据库连接丢失（不适用，使用文件）
- [x] 外部 API 不可用（tree-sitter 降级）
- [x] 无效响应格式（JSON 损坏恢复）

---

## 测试优先级

| 优先级 | 定义 | Red 基线要求 |
|--------|------|--------------|
| P0 | 阻塞发布，核心功能 | 必须在 Red 基线中失败 |
| P1 | 重要，应该覆盖 | 应该在 Red 基线中失败 |
| P2 | 锦上添花，可以后补 | Red 基线中可选 |

### P0 测试（必须在 Red 基线中）

| Test ID | 测试描述 | AC 覆盖 |
|---------|----------|---------|
| T-AD-001 | 单文件增量更新 | AC-F01 |
| T-AD-006 | 性能验证 P95 < 120ms | AC-F01 |
| T-IA-003 | 置信度正确计算 | AC-F02 |
| T-CV-005 | Mermaid 语法有效性 | AC-F03 |
| T-SP-001 | 基本预算裁剪 | AC-F04 |
| T-SP-003 | 预算边界精确控制 | AC-F04 |
| T-FV-001 | Proto 契约虚拟边生成 | AC-F05 |
| T-FV-002 | 置信度正确计算 | AC-F05 |
| T-IL-001 | 记录查询历史 | AC-F06 |
| T-IL-002 | 偏好分数正确计算 | AC-F06 |
| T-VT-001 | 基本漏洞扫描 | AC-F07 |
| T-VT-002 | npm 7+ 格式解析 | AC-F07 |
| T-INT-001 | 现有测试向后兼容 | AC-F08 |

### P1 测试（应该在 Red 基线中）

| Test ID | 测试描述 | AC 覆盖 |
|---------|----------|---------|
| T-IL-003 | 90 天自动清理 | AC-F09 |
| T-VT-004 | 严重性阈值过滤 | AC-F10 |
| T-AD-002 | 批量增量更新 | AC-F01 |
| T-AD-003 | 缓存失效触发全量重建 | AC-F01 |
| T-AD-004 | tree-sitter 不可用降级 | AC-F01 |
| T-IA-001 | 符号影响分析 | AC-F02 |
| T-IA-006 | 深度限制保护 | AC-F02 |
| T-FV-003 | 低置信度过滤 | AC-F05 |
| T-FV-004 | 虚拟边查询 | AC-F05 |

---

## 测试用例详细定义

### M1: AST Delta 增量索引

| Test ID | 场景 | Given | When | Then |
|---------|------|-------|------|------|
| T-AD-001 | 单文件增量更新 | tree-sitter 可用，缓存存在 | `ast-delta.sh update <file>` | 解析 AST、计算差异、更新 graph.db |
| T-AD-002 | 批量增量更新 | 变更文件数 ≤ 10 | `ast-delta.sh batch --since HEAD~1` | 检测变更文件、逐个更新 |
| T-AD-003 | 缓存失效触发重建 | 缓存版本戳不一致 | `ast-delta.sh update <file>` | 执行 FULL_REBUILD |
| T-AD-004 | tree-sitter 降级 | tree-sitter 不可用 | `ast-delta.sh update <file>` | 降级到 SCIP/regex |
| T-AD-005 | 大规模变更触发重建 | 变更文件数 > 10 | `ast-delta.sh batch` | 执行 FULL_REBUILD |
| T-AD-006 | 性能验证 | 测试文件 500 行 | 50 次解析 | P95 ≤ 120ms |
| T-AD-007 | 原子写入保护 | 进程终止后 | 下次调用 | 清理孤儿文件 |

### M2: 传递性影响分析

| Test ID | 场景 | Given | When | Then |
|---------|------|-------|------|------|
| T-IA-001 | 符号影响分析 | 存在调用关系链 | `impact-analyzer.sh analyze <symbol>` | BFS 遍历、返回影响矩阵 |
| T-IA-002 | 文件级影响分析 | 文件被多个脚本依赖 | `impact-analyzer.sh file <file>` | 合并去重受影响节点 |
| T-IA-003 | 置信度正确计算 | A→B→C→D 调用链 | 分析 A | B=0.8, C=0.64, D=0.512 |
| T-IA-004 | 阈值过滤 | 置信度 < 0.1 | 分析 | 过滤低置信度节点 |
| T-IA-005 | Mermaid 格式输出 | 有受影响节点 | `--format mermaid` | 有效 Mermaid 语法 |
| T-IA-006 | 深度限制保护 | 循环依赖 | 深度 5 | 不无限循环 |
| T-IA-007 | 空结果处理 | 符号无调用者 | 分析 | 返回空矩阵 |

### M3: COD 架构可视化

| Test ID | 场景 | Given | When | Then |
|---------|------|-------|------|------|
| T-CV-001 | 模块级 Mermaid | 存在模块依赖 | `generate --level 2` | 生成 Mermaid flowchart |
| T-CV-002 | 文件级 D3.js JSON | 指定模块 | `module scripts/` | 生成 D3.js JSON |
| T-CV-003 | 热点着色集成 | 启用 hotspots | `--include-hotspots` | 红/黄着色 |
| T-CV-004 | 复杂度标注 | 启用 complexity | `--include-complexity` | 复杂度数值 |
| T-CV-005 | Mermaid 语法有效性 | 任意层级 | 生成 | 可渲染 |
| T-CV-006 | D3.js JSON 有效性 | 任意层级 | 生成 | 符合 Schema |
| T-CV-007 | 空模块处理 | 模块无文件 | `module empty/` | 返回空图 |
| T-CV-008 | 输出到文件 | 指定路径 | `--output /tmp/arch.mmd` | 写入文件 |

### M4: 子图智能裁剪（扩展 graph-rag.bats）

| Test ID | 场景 | Given | When | Then |
|---------|------|-------|------|------|
| T-SP-001 | 基本预算裁剪 | 候选片段超预算 | `--budget 4000` | 输出 ≤ 4000 tokens |
| T-SP-002 | 优先级正确计算 | 已知 relevance/hotspot/distance | 计算 | 符合公式 |
| T-SP-003 | 预算边界精确控制 | 预算 1000 | 贪婪选择 | 不超预算 |
| T-SP-004 | 默认预算行为 | 未指定 budget | 搜索 | 使用 8000 |
| T-SP-005 | 零预算处理 | budget=0 | 搜索 | 返回空结果 |
| T-SP-006 | 单片段超预算 | 所有片段 > 预算 | 裁剪 | 返回空+警告 |
| T-SP-007 | 意图偏好集成 | 有偏好数据 | 搜索 | 偏好加权 |
| T-SP-008 | Token 估算准确性 | 已知内容 | 估算 | 误差 < 20% |

### M5: 联邦虚拟边（扩展 federation-lite.bats）

| Test ID | 场景 | Given | When | Then |
|---------|------|-------|------|------|
| T-FV-001 | Proto 虚拟边生成 | 本地调用匹配远程 Proto | `generate-virtual-edges` | 生成虚拟边 |
| T-FV-002 | 置信度正确计算 | getUserById vs GetUserById | 计算 | 0.61 |
| T-FV-003 | 低置信度过滤 | 无明显关联 | 计算 | 不生成虚拟边 |
| T-FV-004 | 虚拟边查询 | 存在虚拟边 | `query-virtual <symbol>` | 返回匹配信息 |
| T-FV-005 | 高置信标记 | 置信度 0.85 | 生成 | 标记"高置信" |
| T-FV-006 | OpenAPI 虚拟边 | fetch('/api/users/{id}') | 生成 | VIRTUAL_CALLS |
| T-FV-007 | 虚拟边同步 | 远程定义变更 | `--sync` | 更新/删除虚拟边 |
| T-FV-008 | 模糊匹配算法 | fetchUser vs getUser | 计算 | 0.4 |

### M6: 意图偏好学习

| Test ID | 场景 | Given | When | Then |
|---------|------|-------|------|------|
| T-IL-001 | 记录查询历史 | 用户搜索 | `record <query> <symbols>` | 写入 history.json |
| T-IL-002 | 偏好分数正确计算 | A 查 5 次 1 天前，B 查 3 次 10 天前 | 计算 | A > B |
| T-IL-003 | 90 天自动清理 | 100 天前记录 | `cleanup` | 删除过期记录 |
| T-IL-004 | 查询 Top N 偏好 | 多符号记录 | `get-preferences --top 5` | 返回前 5 |
| T-IL-005 | 前缀过滤偏好 | 有 src/ 和 scripts/ | `--prefix scripts/` | 仅返回 scripts/ |
| T-IL-006 | 最大条目数限制 | 接近 10000 | 继续记录 | 淘汰最旧 |
| T-IL-007 | 空历史处理 | 无 history.json | `get-preferences` | 返回空数组 |
| T-IL-008 | 用户操作权重 | view/edit/ignore 记录 | 计算 | 不同权重 |
| T-IL-009 | 历史文件损坏恢复 | 非有效 JSON | 任意命令 | 备份+新建 |

### M7: 安全漏洞追踪

| Test ID | 场景 | Given | When | Then |
|---------|------|-------|------|------|
| T-VT-001 | 基本漏洞扫描 | package.json 存在 | `scan` | 解析 npm audit |
| T-VT-002 | npm 7+ 格式解析 | npm >= 7 | 解析 | 正确解析 vulnerabilities |
| T-VT-003 | npm 6.x 格式解析 | npm < 7 | 解析 | 正确解析 advisories |
| T-VT-004 | 严重性阈值过滤 | 有 low/moderate/high/critical | `--severity high` | 仅返回 high/critical |
| T-VT-005 | 依赖传播追踪 | 间接依赖漏洞 | `trace <package>` | 显示依赖链 |
| T-VT-006 | npm audit 降级 | npm audit 失败 | `scan` | 输出警告、返回空 |
| T-VT-007 | JSON 输出格式 | 发现漏洞 | `--format json` | 有效 JSON |
| T-VT-008 | Markdown 输出格式 | 发现漏洞 | `--format md` | Markdown 表格 |
| T-VT-009 | 无漏洞结果 | 无已知漏洞 | `scan` | 输出"未发现" |
| T-VT-010 | 开发依赖包含/排除 | devDependencies 漏洞 | `--include-dev` | 包含/排除 |

---

## 集成测试场景

### T-INT-AST-GRAPH: AST Delta + Graph Store

**Given**：AST Delta 模块和 Graph Store 模块均已实现
**When**：执行增量更新
**Then**：变更正确写入 graph.db

### T-INT-IMPACT-GRAPH: Impact Analyzer + Graph Store

**Given**：Impact Analyzer 和 Graph Store 均已实现
**When**：执行影响分析
**Then**：图遍历性能 < 1s

### T-INT-PRUNING: Smart Pruning + Intent Learner

**Given**：Smart Pruning 和 Intent Learner 均已实现
**When**：带偏好的搜索
**Then**：偏好符号优先级提升

### T-INT-FEDERATION: Virtual Edges + Federation

**Given**：Virtual Edges 和 Federation Lite 均已实现
**When**：跨仓查询
**Then**：虚拟边正确返回

---

## 手动验证检查清单

### MANUAL-001: Mermaid 渲染验证

- [ ] 访问 https://mermaid.live
- [ ] 粘贴 cod-visualizer 输出
- [ ] 确认无语法错误
- [ ] 确认图形可读

### MANUAL-002: 性能回归验证

- [ ] 运行 `npm test` 总耗时 < 60s
- [ ] 无超时测试
- [ ] 无内存泄漏

---

## 追溯矩阵

| 需求 | 设计 (AC) | 测试 | 证据 |
|------|-----------|------|------|
| REQ-AD-001 | AC-F01 | T-AD-001, T-AD-002, T-AD-004 | evidence/red-baseline/*.log |
| REQ-AD-004 | AC-F01 | T-AD-006 | evidence/red-baseline/performance.log |
| REQ-IA-002 | AC-F02 | T-IA-003, T-IA-004 | evidence/red-baseline/*.log |
| REQ-CV-002 | AC-F03 | T-CV-005 | evidence/red-baseline/*.log |
| REQ-SP-001 | AC-F04 | T-SP-001, T-SP-003 | evidence/red-baseline/*.log |
| REQ-FV-002 | AC-F05 | T-FV-002 | evidence/red-baseline/*.log |
| REQ-IL-001 | AC-F06 | T-IL-001 | evidence/red-baseline/*.log |
| REQ-IL-003 | AC-F09 | T-IL-003 | evidence/red-baseline/*.log |
| REQ-VT-001 | AC-F07 | T-VT-001, T-VT-002, T-VT-003 | evidence/red-baseline/*.log |
| REQ-VT-002 | AC-F10 | T-VT-004 | evidence/red-baseline/*.log |
| 向后兼容 | AC-F08 | T-INT-001 | evidence/red-baseline/*.log |

---

## 证据落点

| 证据类型 | 路径 |
|---------|------|
| Red 基线 | `dev-playbooks/changes/achieve-augment-full-parity/evidence/red-baseline/` |
| Green 最终 | `dev-playbooks/changes/achieve-augment-full-parity/evidence/green-final/` |
| 性能报告 | `dev-playbooks/changes/achieve-augment-full-parity/evidence/performance-report.md` |

---

**Test Owner 签名**：Test Owner (Claude)
**日期**：2026-01-16
