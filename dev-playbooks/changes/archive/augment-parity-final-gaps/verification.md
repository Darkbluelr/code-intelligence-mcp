# 验证计划：augment-parity-final-gaps

## 测试计划指令表

### 主线计划区

TP1.1 图存储增强验收测试（边类型/迁移/路径查询）
- Why: 图存储是影响分析与上下文追踪的核心基础，边类型与路径查询缺口会导致分析链断裂。
- AC: AC-G01, AC-G01a, AC-G02
- Test Type: unit, contract
- Non-goals: 不生成真实 SCIP 索引文件；不做性能基准测试。

TP1.2 ADR 解析与关联验收测试
- Why: 架构决策无法关联代码会导致上下文缺失，影响诊断与决策可追溯性。
- AC: AC-G03
- Test Type: integration
- Non-goals: 不覆盖 ADR 以外的文档格式；不验证 UI 展示。

TP1.3 对话历史信号累积验收测试
- Why: 对话连续性是排序质量的关键输入，窗口与加权错误会造成排序漂移。
- AC: AC-G04
- Test Type: unit
- Non-goals: 不验证跨会话存储策略；不测试外部搜索服务。

TP1.4 守护进程预热与请求取消验收测试
- Why: 冷启动与并发取消直接影响交互延迟与资源占用。
- AC: AC-G05, AC-G06
- Test Type: integration
- Non-goals: 不进行大规模并发压力测试；不验证系统级进程监控。

TP1.5 子图 LRU 缓存验收测试
- Why: LRU 缓存是性能与跨进程共享的关键组件，错误会导致命中率下降或数据污染。
- AC: AC-G07
- Test Type: unit
- Non-goals: 不测试不同 SQLite 版本兼容性；不做磁盘容量极限测试。

TP1.6 Bug 定位 + 影响分析融合验收测试
- Why: 影响分析权重改变排序逻辑，输出契约不稳将破坏调用方依赖。
- AC: AC-G08
- Test Type: unit, contract
- Non-goals: 不验证复杂度/热度算法本身；不调用外部 LLM 服务。

TP1.7 结构化上下文输出与 DevBooks 适配验收测试
- Why: 结构化输出是高信噪比上下文的核心接口，字段缺失将导致上下游失配。
- AC: AC-G11, AC-G12
- Test Type: contract
- Non-goals: 不测试 UI Hook 效果；不覆盖图检索召回质量。

TP1.8 CI/CD 架构检查模板验收测试
- Why: CI 模板是企业级治理入口，语法或触发条件错误会导致架构规则失效。
- AC: AC-G09
- Test Type: unit
- Non-goals: 不执行真实 CI 流水线；不验证 PR 评论权限配置。

TP1.9 回归测试基线
- Why: 新增能力必须保持旧接口稳定，避免破坏现有 MCP 工具与脚本。
- AC: AC-G10
- Test Type: integration
- Non-goals: 不扩展历史回归用例集；不新增基准指标。

### 临时计划区

TP-T1 Python SCIP fixture 接入
- Why: Python IMPLEMENTS 边类型需要真实 SCIP 输入才能验证。
- AC: AC-G01
- Test Type: integration
- Non-goals: 不在测试中生成 SCIP 索引文件。

TP-T2 Unsupported language SCIP fixture 接入
- Why: REFERENCES 降级逻辑需要真实不支持语言的 SCIP 输入验证。
- AC: AC-G01
- Test Type: integration
- Non-goals: 不在测试中新增语言解析器。

TP-T3 actionlint 可执行文件准备
- Why: GitHub Action 语法检查依赖 actionlint。
- AC: AC-G09
- Test Type: unit
- Non-goals: 不在测试中安装系统级依赖。

### 【断点区】

BP1 未安装 bats 时无法运行 Red 基线，需要提供 bats 或改用现有 CI 环境执行。

BP2 缺少 jq 或 sqlite3 时相关测试将跳过，需要补齐依赖后再运行。

BP3 缺少 SCIP_PYTHON_INDEX_PATH 或 SCIP_UNSUPPORTED_INDEX_PATH 时边类型相关集成测试将跳过。

BP4 缺少 actionlint 时 workflow 语法测试将跳过。

---

> **Change ID**: `augment-parity-final-gaps`
> **Test Owner**: Test Owner (Codex)
> **Date**: 2026-01-16
> **Status**: Done
> **Code Review**: APPROVED WITH COMMENTS (2026-01-16)
> **Reviewer Notes**: 可维护性建议已记录为技术债务，不阻塞归档

---

## 测试策略

### 测试类型分布

| 测试类型 | 数量（按测试文件计） | 用途 | 预期耗时 |
|----------|----------------------|------|----------|
| 单元测试 | 5 | 脚本行为/边界/输出契约 | < 5s/文件 |
| 集成测试 | 2 | 脚本协作与数据写入 | < 30s/文件 |
| 契约测试 | 1 | 结构化输出 Schema 验证 | < 10s/文件 |
| E2E 测试 | 0 | 不适用 | N/A |

### 测试环境

| 测试类型 | 环境 | 依赖 |
|----------|------|------|
| 单元测试 | Node.js + Bash | bats-core, jq, sqlite3 |
| 集成测试 | Node.js + Bash | sqlite3, graph.db, 临时目录 |
| 契约测试 | Node.js + Bash | jq |

---

## 测试分层策略

| 类型 | 数量（按测试文件计） | 覆盖场景 | 预期执行时间 |
|------|----------------------|----------|--------------|
| 单元测试 | 5 | AC-G01, AC-G01a, AC-G02, AC-G04, AC-G07, AC-G08, AC-G09 | < 5s/文件 |
| 集成测试 | 2 | AC-G03, AC-G05, AC-G06 | < 30s/文件 |
| 契约测试 | 1 | AC-G11, AC-G12 | < 10s/文件 |
| E2E 测试 | 0 | 不适用 | N/A |

## 测试环境要求

| 测试类型 | 运行环境 | 依赖 |
|----------|----------|------|
| 单元测试 | Node.js | bats-core, jq, sqlite3 |
| 集成测试 | Node.js + Bash | sqlite3, graph.db |
| 契约测试 | Node.js + Bash | jq |

---

## 计划细化区

### Scope & Non-goals

- Scope: AC-G01, AC-G01a, AC-G02, AC-G03, AC-G04, AC-G05, AC-G06, AC-G07, AC-G08, AC-G09, AC-G10, AC-G11, AC-G12 的验收测试与回归测试触发方式。
- Non-goals: 不实现业务代码；不新增外部服务依赖；不编写性能基准脚本。

### 测试金字塔与分层边界

- Unit: 单脚本行为与输出契约（graph-store、intent-learner、cache-manager、bug-locator、ci）。
- Integration: 多脚本协作与数据写入（adr-parser + graph-store，daemon + cache-manager）。
- Contract: 结构化输出 JSON Schema 与字段完整性（augment-context）。
- E2E: 本变更不引入 UI 或端到端链路。

### 测试矩阵（Requirement/Risk → Test IDs → 断言点 → 覆盖 AC）

| 需求/风险 | Test IDs | 断言点 | 覆盖 AC |
|----------|----------|--------|---------|
| 图存储边类型与迁移 | T-GS-01, T-GS-02, T-GS-03, T-GS-04, T-GS-05, T-GS-06, T-GS-07 | 新边类型可写入、迁移检测输出、迁移数据保留 | AC-G01, AC-G01a |
| A-B 路径查询 | T-GS-08, T-GS-09, T-GS-10, T-GS-11, T-GS-12 | found 标志、深度限制、无路径返回、输出包含长度与路径 | AC-G02 |
| ADR 解析与关联 | T-ADR-01, T-ADR-02, T-ADR-03, T-ADR-04, T-ADR-05 | MADR/Nygard 字段解析、关键词提取、ADR_RELATED 边、空目录处理 | AC-G03 |
| 对话上下文窗口 | T-CC-01, T-CC-02, T-CC-03, T-CC-04 | 写入/读取条数、Schema 字段、FIFO 淘汰、加权排序提升 | AC-G04 |
| 预热机制 | T-DM-01, T-DM-02, T-DM-03, T-DM-04 | warmup 执行成功、缓存统计、热点与符号预热字段 | AC-G05 |
| 请求取消 | T-DM-05, T-DM-06, T-DM-07, T-DM-08 | 旧请求取消、flock 原子性、取消清理、正常完成 | AC-G06 |
| 子图 LRU 缓存 | T-SLC-01, T-SLC-02, T-SLC-03, T-SLC-04, T-SLC-05 | SQLite 持久化、命中率、跨进程读取、LRU 淘汰、统计字段 | AC-G07 |
| Bug 定位融合 | T-BLF-01, T-BLF-02, T-BLF-03, T-BLF-04, T-BLF-05 | impact 字段、affected_files 数组、分数调整、向后兼容；保持 `--error` 入口与 JSON 外层结构 | AC-G08 |
| 结构化上下文输出 | T-SCO-01, T-SCO-02, T-SCO-03, T-SCO-04, T-SCO-05, T-SCO-06 | 5 层字段完整、JSON Schema 满足 | AC-G11 |
| DevBooks 适配 | T-DBA-01, T-DBA-02, T-DBA-03, T-DBA-04, T-DBA-05 | config.yaml 检测、画像/约束注入、无配置降级 | AC-G12 |
| CI/CD 模板 | T-CI-01, T-CI-02, T-CI-03, T-CI-04, T-CI-05, T-CI-06 | actionlint 通过、触发条件存在、关键脚本步骤存在 | AC-G09 |
| 回归测试 | T-REG-01, T-REG-02 | 全量 bats 与 MCP 契约稳定 | AC-G10 |

### 设计回写追溯（Design Backport Trace）

- DBP-01 Bug 定位 CLI 契约回写（保持 `--error` 入口与外层结构）：`tests/bug-locator.bats`（T-BLF-01 ~ T-BLF-05）

### 测试数据与夹具策略

- ADR 测试使用测试用例内生成的临时 Markdown 文件。
- 图存储与 LRU 测试使用临时 SQLite 数据库，路径由 DEVBOOKS_DIR 控制。
- 结构化输出测试使用临时 DevBooks 目录（config.yaml、project-profile.md、c4.md）。
- Python/不支持语言 SCIP fixture 通过环境变量 SCIP_PYTHON_INDEX_PATH 与 SCIP_UNSUPPORTED_INDEX_PATH 提供。

### 业务语言约束

- 测试断言仅针对 CLI 行为与输出结构，不依赖内部函数或实现细节。
- 不引入 UI 步骤或交互式操作说明。

### 可复现性策略

- 使用 setup_temp_dir 隔离测试目录，避免污染项目根目录。
- 固定测试输入（JSON、ADR 文本、查询字符串），不依赖外部网络。
- 测试默认 EXPECT_RED=true，Green 验证需显式设置 EXPECT_RED=false。

### 风险与降级

- 缺少 jq、sqlite3、actionlint 时相关测试会跳过；需要安装依赖后复测。
- SCIP fixture 未提供时，Python 与降级测试会跳过；需补齐 fixture 后复测。
- 若 daemon 或 cache-manager 接口仍未实现，相关测试将以 skip_not_implemented 标记 Red 缺口。
- 缺少 timeout 或 gtimeout 时，daemon 正常完成性测试将跳过。

### 配置与依赖变更验证

- GitHub Action 语法：`actionlint .github/workflows/arch-check.yml`
- CI 模板覆盖：`bats tests/ci.bats`
- 架构规则脚本自检：`./scripts/dependency-guard.sh --cycles --format json` 与 `./scripts/boundary-detector.sh detect --format json`

### 坏味道检测策略

- 依赖循环：`scripts/dependency-guard.sh --cycles`
- 分层违规：`scripts/boundary-detector.sh detect --rules config/arch-rules.yaml`
- 不新增额外静态检查工具，保持现有工具链一致性。

### Test Oracle Spec: A-B 最短路径（BFS）

**Inputs**
- 节点集合、边集合、from、to、max_depth、edge_types

**Outputs**
- found（true/false）、path（节点序列）、edges（边序列）、length（边数）

**Invariants**
- found=false 时 path 与 edges 为空数组，length=0
- found=true 时 length = path.length - 1
- edges 中的 from/to 串联与 path 一致

**Failure Modes**
- 循环导致无限遍历
- 忽略 max_depth 限制
- edge_types 过滤失效

**Pseudo Code**
```
queue <- [from]
visited <- {from}
parent <- {}
while queue not empty:
  node <- queue.pop_front()
  if node == to: break
  for each edge in outgoing(node):
    if edge.type not in edge_types: continue
    if depth(node)+1 > max_depth: continue
    if edge.to not in visited:
      visited.add(edge.to)
      parent[edge.to] <- node
      queue.push(edge.to)
if to not in visited: return found=false
path <- build_path(parent, to)
edges <- build_edges(path)
return found=true, path, edges, length=len(edges)
```

**边界条件与测试映射**
- 基本路径存在：T-GS-08
- 深度限制导致找不到路径：T-GS-09
- 边类型过滤导致找不到路径：T-GS-12
- 无路径返回空：T-GS-10
- 输出 length 与 path 一致：T-GS-11

### Test Oracle Spec: 子图 LRU 缓存

**Inputs**
- cache_key、cache_value、CACHE_MAX_SIZE

**Outputs**
- cache-get 返回值、stats 命中率、SQLite 条目数

**Invariants**
- 条目数始终 <= CACHE_MAX_SIZE
- 命中读取后 access_time 更新
- 跨进程读取返回相同值

**Failure Modes**
- 淘汰未发生导致条目数超限
- 命中率统计不更新
- SQLite 未启用 WAL 导致并发异常

**Pseudo Code**
```
BEGIN TRANSACTION
if count > MAX_SIZE:
  delete oldest by access_time
insert or replace (key, value, access_time, created_time)
COMMIT
on get:
  update access_time
  return value
```

**边界条件与测试映射**
- 首次写入创建 SQLite：T-SLC-01
- 重复读取提升命中率：T-SLC-02
- 跨进程读取一致性：T-SLC-03
- 超上限触发淘汰：T-SLC-04
- 统计字段完整：T-SLC-05

### Test Oracle Spec: 请求取消

**Inputs**
- 请求 A、请求 B、取消信号文件、flock 锁

**Outputs**
- A 返回 cancelled，B 正常执行

**Invariants**
- 新请求触发旧请求取消
- 取消操作受 flock 保护
- 取消完成后清理信号文件

**Failure Modes**
- 旧请求未取消且继续执行
- 取消信号产生竞态
- 取消文件泄漏

**Pseudo Code**
```
on new request:
  acquire lock
  write cancel file for previous request
  release lock
  start new request
previous request loop:
  if cancel file marked: exit cancelled
cleanup cancel file on exit
```

**边界条件与测试映射**
- 新请求触发取消：T-DM-05
- 原子锁保护：T-DM-06
- 取消后清理：T-DM-07
- 正常完成不被取消：T-DM-08
- 取消响应时间门槛：T-DM-05

### 测试文件清单

**新增测试文件**
- tests/adr-parser.bats
- tests/augment-context.bats
- tests/ci.bats

**扩展测试文件**
- tests/graph-store.bats
- tests/intent-learner.bats
- tests/daemon.bats
- tests/cache-manager.bats
- tests/bug-locator.bats

### 执行命令

- `bats tests/graph-store.bats`
- `bats tests/adr-parser.bats`
- `bats tests/intent-learner.bats`
- `bats tests/daemon.bats`
- `bats tests/cache-manager.bats`
- `bats tests/bug-locator.bats`
- `bats tests/augment-context.bats`
- `bats tests/ci.bats`
- `bats tests/mcp-contract.bats`
- `bats tests/*.bats`

---

## AC 覆盖矩阵

| AC-ID | 描述 | 测试类型 | Test ID | 优先级 | 状态 |
|-------|------|----------|---------|--------|------|
| AC-G01 | 边类型扩展 | 单元 | T-GS-01, T-GS-02, T-GS-03 | P0 | [x] |
| AC-G01a | 迁移命令 | 单元 | T-GS-04, T-GS-05, T-GS-06, T-GS-07 | P0 | [x] |
| AC-G02 | 路径查询 | 单元 | T-GS-08, T-GS-09, T-GS-10, T-GS-11, T-GS-12 | P0 | [x] |
| AC-G03 | ADR 解析 | 集成 | T-ADR-01, T-ADR-02, T-ADR-03, T-ADR-04, T-ADR-05 | P0 | [x] |
| AC-G04 | 对话上下文 | 单元 | T-CC-01, T-CC-02, T-CC-03, T-CC-04 | P0 | [x] |
| AC-G05 | 预热机制 | 集成 | T-DM-01, T-DM-02, T-DM-03, T-DM-04 | P0 | [x] |
| AC-G06 | 请求取消 | 集成 | T-DM-05, T-DM-06, T-DM-07, T-DM-08 | P0 | [x] |
| AC-G07 | LRU 缓存 | 单元 | T-SLC-01, T-SLC-02, T-SLC-03, T-SLC-04, T-SLC-05 | P0 | [x] |
| AC-G08 | Bug 定位融合 | 单元 | T-BLF-01, T-BLF-02, T-BLF-03, T-BLF-04, T-BLF-05 | P0 | [x] |
| AC-G09 | GitHub Action CI/CD | 单元 | T-CI-01, T-CI-02, T-CI-03, T-CI-04, T-CI-05, T-CI-06 | P1 | [x] |
| AC-G10 | 回归测试 | 集成 | T-REG-01, T-REG-02 | P0 | [x] |
| AC-G11 | 结构化上下文输出 | 契约 | T-SCO-01, T-SCO-02, T-SCO-03, T-SCO-04, T-SCO-05, T-SCO-06 | P0 | [x] |
| AC-G12 | DevBooks 适配 | 契约 | T-DBA-01, T-DBA-02, T-DBA-03, T-DBA-04, T-DBA-05 | P0 | [x] |

**覆盖摘要**：
- AC 总数：12
- 已验证通过：12
- 覆盖率：12/12 = 100%
- Green 验证日期：2026-01-16
- Green 证据：`dev-playbooks/changes/augment-parity-final-gaps/evidence/green-final/test-20260116-225946-final.log`

---

## 边界条件检查清单

### 输入验证
- [x] 空输入 / null 值（空 ADR 目录、空路径查询）
- [ ] 超过最大长度
- [ ] 无效格式（缺失必填字段）
- [ ] SQL 注入 / XSS 尝试

### 状态边界
- [ ] 第一项（index 0）
- [ ] 最后一项（index n-1）
- [x] 空集合（无路径、无 ADR）
- [ ] 单元素集合
- [x] 最大容量（LRU 淘汰）

### 并发与时序
- [ ] 并发访问同一资源
- [ ] 请求超时处理
- [x] 竞态条件场景（取消原子性）
- [ ] 失败后重试

### 错误处理
- [ ] 网络故障
- [ ] 数据库连接丢失
- [ ] 外部 API 不可用
- [ ] 无效响应格式

---

## 测试优先级

| 优先级 | 定义 | Red 基线要求 |
|--------|------|--------------|
| P0 | 阻塞发布，核心功能 | 必须在 Red 基线中体现缺口 |
| P1 | 重要，应该覆盖 | 应该在 Red 基线中体现缺口 |
| P2 | 锦上添花 | 可选 |

### P0 测试
1. T-GS-01, T-GS-02, T-GS-03, T-GS-04, T-GS-05, T-GS-06, T-GS-07, T-GS-08, T-GS-09, T-GS-10, T-GS-11, T-GS-12
2. T-ADR-01, T-ADR-02, T-ADR-03, T-ADR-04, T-ADR-05
3. T-CC-01, T-CC-02, T-CC-03, T-CC-04
4. T-DM-01, T-DM-02, T-DM-03, T-DM-04, T-DM-05, T-DM-06, T-DM-07, T-DM-08
5. T-SLC-01, T-SLC-02, T-SLC-03, T-SLC-04, T-SLC-05
6. T-BLF-01, T-BLF-02, T-BLF-03, T-BLF-04, T-BLF-05
7. T-SCO-01, T-SCO-02, T-SCO-03, T-SCO-04, T-SCO-05, T-SCO-06
8. T-DBA-01, T-DBA-02, T-DBA-03, T-DBA-04, T-DBA-05
9. T-REG-01, T-REG-02

### P1 测试
1. T-CI-01, T-CI-02, T-CI-03, T-CI-04, T-CI-05, T-CI-06

---

## 手动验证检查清单

### MANUAL-001: GitHub Action 触发与评论
- [ ] 在 PR 上触发 arch-check workflow
- [ ] 人为制造循环依赖并确认 workflow 失败
- [ ] 检查 PR 评论是否出现 Architecture Check Failed 提示

### MANUAL-002: GitLab CI 模板验证
- [ ] 复制 .gitlab-ci.yml.template 为 .gitlab-ci.yml
- [ ] 触发 Merge Request 并观察 arch-check stage 运行

---

## 追溯矩阵

| 需求 | 设计 (AC) | 测试 | Red 证据 | Green 证据 |
|------|-----------|------|----------|------------|
| 边类型扩展 | AC-G01 | T-GS-01, T-GS-02, T-GS-03 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| 迁移命令 | AC-G01a | T-GS-04, T-GS-05, T-GS-06, T-GS-07 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| 路径查询 | AC-G02 | T-GS-08, T-GS-09, T-GS-10, T-GS-11, T-GS-12 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| ADR 解析 | AC-G03 | T-ADR-01, T-ADR-02, T-ADR-03, T-ADR-04, T-ADR-05 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| 对话上下文 | AC-G04 | T-CC-01, T-CC-02, T-CC-03, T-CC-04 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| 预热机制 | AC-G05 | T-DM-01, T-DM-02, T-DM-03, T-DM-04 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| 请求取消 | AC-G06 | T-DM-05, T-DM-06, T-DM-07, T-DM-08 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| LRU 缓存 | AC-G07 | T-SLC-01, T-SLC-02, T-SLC-03, T-SLC-04, T-SLC-05 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| Bug 定位融合 | AC-G08 | T-BLF-01, T-BLF-02, T-BLF-03, T-BLF-04, T-BLF-05 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| CI/CD 模板 | AC-G09 | T-CI-01, T-CI-02, T-CI-03, T-CI-04, T-CI-05, T-CI-06 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| 回归测试 | AC-G10 | T-REG-01, T-REG-02 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| 结构化上下文输出 | AC-G11 | T-SCO-01, T-SCO-02, T-SCO-03, T-SCO-04, T-SCO-05, T-SCO-06 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |
| DevBooks 适配 | AC-G12 | T-DBA-01, T-DBA-02, T-DBA-03, T-DBA-04, T-DBA-05 | `evidence/red-baseline/test-20260116-172302.log` | `evidence/green-final/test-20260116-225946-final.log` |

---

## 架构异味报告

- Setup 复杂度：中等，涉及多脚本交互与临时 DevBooks 目录构造。
- Mock 数量：低，主要使用临时文件与环境变量隔离。
- 清理难度：中等，daemon 测试需确保进程与 socket 清理。
- 改进建议：为 bug-locator 统一 CLI 契约；为 augment-context 提供稳定的 JSON Schema 输出入口。
