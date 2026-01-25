# 设计文档：弥合 Augment Code 代码智能差距

> **Change ID**: `augment-parity`
> **Version**: 1.0.0
> **Status**: Archived ✅ (归档于 2026-01-15)
> **Owner**: Design Owner
> **Created**: 2026-01-15
> **Last Updated**: 2026-01-15
> **Last Verified**: 2026-01-15
> **Freshness Check**: 归档完成

---

## 1. Acceptance Criteria（验收标准）

### 1.1 功能验收标准

| AC ID | 验收项 | Pass/Fail 判据 | 验收方式 |
|-------|--------|----------------|----------|
| AC-001 | SQLite 图存储支持 4 种核心边类型 CRUD | DEFINES/IMPORTS/CALLS/MODIFIES 边类型均可创建、读取、更新、删除 | A（自动化测试） |
| AC-002 | SCIP → 图数据转换成功 | `.devbooks/graph.db` 节点数 >= 187，边数 >= 307（基于当前 SCIP 索引） | A（自动化测试） |
| AC-003 | 守护进程热启动后 P95 延迟 < 500ms | 100 次请求，P95（第 95 位）<= 600ms（含 ±20% 波动） | A（自动化测试） |
| AC-004 | LLM 重排序可启用/禁用 | `features.llm_rerank.enabled: false` 时跳过重排序，系统正常工作 | A（自动化测试） |
| AC-005 | 孤儿模块检测正确识别无入边节点 | 已知孤儿模块被正确识别，非孤儿模块不误报 | A（自动化测试） |
| AC-006 | 自动模式发现至少识别 3 种高频模式 | 输出模式中频率 >= 3 的模式数量 >= 3 | A（自动化测试） |
| AC-007 | 所有现有测试继续通过（向后兼容） | `npm test` 全部通过，无回归 | A（回归测试） |
| AC-008 | 无 CKB 时图查询正常工作 | `CKB_ENABLED=false` 时 `ci_graph_rag` 返回有效结果 | A（自动化测试） |

### 1.2 非功能验收标准

| AC ID | 验收项 | 阈值 | 验收方式 |
|-------|--------|------|----------|
| AC-N01 | 守护进程 P95 延迟 | < 500ms（热启动，100 次请求） | A（性能测试） |
| AC-N02 | 冷启动延迟 | 单独记录，不作为 AC 判定条件 | A（性能测试） |
| AC-N03 | 图数据库文件大小 | 预估 1-10MB（当前项目规模） | A（文件检查） |
| AC-N04 | SCIP 解析覆盖率 | TypeScript 文件 100% | A（自动化测试） |

---

## 2. Goals / Non-goals / Red Lines

### 2.1 Goals（目标）

1. **消除 CKB 依赖**：使用 SQLite 自有图存储替代外部 CKB MCP Server
2. **性能优化**：P95 延迟从 ~3000ms 降至 < 500ms（通过守护进程 + 缓存）
3. **边类型扩展**：从 1 种（CALLS）扩展到 4 种核心边类型（DEFINES/IMPORTS/CALLS/MODIFIES）
4. **检索精度提升**：通过 LLM 重排序增强向量检索结果
5. **架构治理增强**：新增孤儿模块检测能力
6. **模式学习自动化**：从 5 种预定义扩展到动态习得模式
7. **综合能力对等度**：从 ~40% 提升至 ~85%（相对 Augment Code）

### 2.2 Non-goals（非目标）

| 排除项 | 原因 |
|--------|------|
| 追求 Augment 的 200ms 延迟 | 500ms 已满足用户体验，ROI 较低 |
| 实现 IMPLEMENTS/EXTENDS 边类型 | 需要 AST 分析，本次聚焦 SCIP 可提取的 4 种 |
| 请求取消机制 | 复杂度高，后续迭代 |
| 自研 LLM 模型 | 超出项目范围 |
| 持久化图服务（如 Neo4j） | SQLite 文件存储已足够 |
| 多语言支持（Python/Go） | TypeScript 优先，后续可扩展 |

### 2.3 Red Lines（不可破约束）

| Red Line | 理由 |
|----------|------|
| 不破坏现有 MCP 工具签名 | 向后兼容性是核心约束 |
| 不引入新编程语言 | 保持 Bash + TypeScript 技术栈 |
| 不修改 tests/ 目录 | Coder 角色禁止修改测试 |
| 保持薄壳架构（CON-TECH-002） | server.ts 仅调度，核心逻辑在脚本 |
| 所有工作在本变更包完成 | 人类强制约束，禁止拆分 |

---

## 3. 执行摘要

本设计文档定义 Code Intelligence MCP Server 的能力升级：通过 SQLite 自有图存储消除 CKB 依赖，通过常驻守护进程将 P95 延迟从 ~3000ms 降至 < 500ms，通过 SCIP 解析支持 4 种核心边类型，通过 LLM 重排序提升检索精度，通过孤儿检测和动态模式学习增强架构治理能力。核心矛盾是在保持轻资产（Bash + SQLite）的前提下实现接近 Augment Code ~85% 的能力对等。

---

## 4. Problem Context（问题背景）

### 4.1 业务驱动

- **CKB 依赖风险**：当前图查询强依赖外部 CKB MCP Server，无 CKB 时降级为线性搜索
- **性能瓶颈**：P95 延迟 ~3000ms，与 Augment 的 200-300ms 相差 10 倍
- **边类型受限**：仅支持 CALLS 边，缺少 IMPORTS/DEFINES/MODIFIES 分析维度
- **检索精度低**：纯向量检索无 LLM 重排序，结果排序不够精准
- **架构治理不完整**：仅有循环依赖检测，缺少孤儿模块检测

### 4.2 技术债

- 无自有图存储能力
- 每次查询需冷启动脚本进程
- 模式学习依赖预定义规则

### 4.3 不解决的后果

- 无 CKB 环境下功能大幅降级
- 用户体验显著差于 Augment Code
- 架构腐化（孤儿模块）无法早期发现
- 模式覆盖率受限于人工预定义

---

## 5. 价值链映射

```
Goal: 代码智能能力 40% → 85%
  │
  ├─ 阻碍: CKB 依赖
  │   └─ 杠杆: 自有图存储
  │       └─ 最小方案: graph-store.sh（SQLite + JSON）
  │
  ├─ 阻碍: P95 延迟 ~3000ms
  │   └─ 杠杆: 常驻进程 + 热缓存
  │       └─ 最小方案: daemon.sh（Unix Socket）
  │
  ├─ 阻碍: 边类型仅 1 种
  │   └─ 杠杆: SCIP 索引解析
  │       └─ 最小方案: scip-to-graph.sh（protobufjs）
  │
  ├─ 阻碍: 检索精度低
  │   └─ 杠杆: LLM 重排序
  │       └─ 最小方案: graph-rag.sh 集成 llm_rerank()
  │
  └─ 阻碍: 架构治理不完整
      └─ 杠杆: 孤儿检测 + 动态模式
          └─ 最小方案: dependency-guard.sh --orphan-check
```

---

## 6. 背景与现状评估

### 6.1 现有资产

| 资产 | 路径 | 状态 |
|------|------|------|
| MCP Server 薄壳 | `src/server.ts` | 可用，待注册新工具 |
| 共享函数库 | `scripts/common.sh` | 可用，待扩展 llm_call() |
| 多级缓存 | `scripts/cache-manager.sh` | 已有（Phase 2） |
| 架构守护 | `scripts/dependency-guard.sh` | 已有，待增强孤儿检测 |
| Graph-RAG | `scripts/graph-rag.sh` | 可用，待集成 LLM 重排序 |
| 模式学习 | `scripts/pattern-learner.sh` | 可用，待增强自动发现 |
| SCIP 索引 | `index.scip` | 存在（scip-typescript 0.4.0） |

### 6.2 主要风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| SCIP 解析复杂度 | 中 | 中 | protobufjs 已验证可行，降级到正则匹配 |
| 守护进程稳定性 | 中 | 高 | PID 锁 + 心跳 + 自动重启（max 3 次） |
| LLM 重排序延迟 | 中 | 中 | 2s 超时，超时跳过重排序 |
| SQLite 性能 | 低 | 中 | WAL 模式 + 索引优化 |

---

## 7. 设计原则

### 7.1 核心原则

1. **轻资产优先**：SQLite + Bash，不引入外部服务依赖
2. **渐进增强**：功能开关控制，默认不启用 LLM 重排序
3. **优雅降级**：CKB 不可用、LLM 不可用时自动降级
4. **可观测优先**：所有操作可追踪、可验证

### 7.2 变化点识别

| 变化点 | 可能变化 | 封装策略 |
|--------|----------|----------|
| 图存储后端 | 可能升级到更高性能存储 | 抽象 graph-store.sh 接口 |
| LLM 提供商 | Claude/OpenAI/Ollama | llm_call() 适配函数 |
| SCIP 解析范围 | 扩展到 Python/Go | 语言检测 + 解析器选择 |
| 边类型 | 扩展 IMPLEMENTS/EXTENDS | AST 分析模块可插拔 |

---

## 8. 目标架构

### 8.1 Bounded Context

```
┌─────────────────────────────────────────────────────────────────┐
│                     Code Intelligence MCP                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐       │
│  │ Graph Store   │  │ SCIP Parser   │  │ Daemon        │       │
│  │   (新增)      │  │   (新增)      │  │   (新增)      │       │
│  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘       │
│          │                  │                  │                │
│  ┌───────▼───────────────────────────────────────────┐         │
│  │                  Enhanced Scripts                  │         │
│  │  graph-rag (LLM rerank) | dependency-guard        │         │
│  │  (orphan) | pattern-learner (auto-discover)       │         │
│  └───────────────────────────────────────────────────┘         │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐                                              │
│  │ LLM Adapter   │  ← Claude/OpenAI/Ollama                      │
│  │ (common.sh)   │                                              │
│  └───────────────┘                                              │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 依赖方向

```
server.ts ──→ scripts/*.sh ──→ 外部工具 (rg, jq, git, sqlite3)
    │              │
    ▼              ▼
MCP SDK      daemon.sh ──→ Unix Socket ──→ graph-store.sh
                   │
                   ▼
             scip-to-graph.sh ──→ protobufjs
                   │
                   ▼
             graph-rag.sh ──→ llm_call() ──→ LLM APIs
             dependency-guard.sh (orphan detection)
             pattern-learner.sh (auto-discover)
```

### 8.3 关键扩展点

| 扩展点 | 位置 | 扩展方式 |
|--------|------|----------|
| 图存储后端 | graph-store.sh | 环境变量 `GRAPH_BACKEND` |
| LLM 提供商 | common.sh:llm_call() | 配置 `features.llm_rerank.provider` |
| SCIP 语言 | scip-to-graph.sh | 语言检测 + 解析器选择 |
| 边类型扩展 | graph-store.sh | 新增边类型常量 |

### 8.4 C4 Delta

**C2（Container Level）变更**：

| 变更类型 | 元素 | 说明 |
|----------|------|------|
| 新增 | scripts/graph-store.sh | SQLite 图存储容器 |
| 新增 | scripts/scip-to-graph.sh | SCIP 转换容器 |
| 新增 | scripts/daemon.sh | 常驻守护进程容器 |
| 修改 | scripts/graph-rag.sh | 集成 LLM 重排序 |
| 修改 | scripts/dependency-guard.sh | 新增孤儿检测 |
| 修改 | scripts/pattern-learner.sh | 新增自动发现 |
| 修改 | scripts/common.sh | 新增 llm_call() 适配函数 |
| 修改 | src/server.ts | 注册 ci_graph_store MCP 工具 |
| 新增 | config/features.yaml | 功能开关配置（如不存在） |

---

## 9. Testability & Seams（可测试性与接缝）

### 9.1 测试接缝（Seams）

| 模块 | 接缝位置 | 注入方式 |
|------|----------|----------|
| graph-store.sh | `GRAPH_DB_PATH` 环境变量 | 测试时指向临时数据库 |
| scip-to-graph.sh | `SCIP_INDEX_PATH` 环境变量 | 测试时指向测试索引 |
| daemon.sh | `DAEMON_SOCK` 环境变量 | 测试时指向临时 Socket |
| common.sh:llm_call() | `LLM_MOCK_RESPONSE` 环境变量 | 测试时返回 Mock 响应 |

### 9.2 Pinch Points（汇点）

| 汇点 | 路径数 | 测试价值 |
|------|--------|----------|
| graph-store.sh | 3 | 覆盖图查询/写入/边类型 |
| daemon.sh | 2 | 覆盖启动/请求处理 |
| common.sh:llm_call() | 3 | 覆盖 Claude/OpenAI/Ollama |

### 9.3 依赖隔离

| 外部依赖 | 隔离方式 |
|----------|----------|
| SQLite | 临时数据库文件 |
| LLM APIs | Mock 响应环境变量 |
| Unix Socket | 临时 Socket 路径 |
| SCIP 索引 | 测试用最小索引 |

---

## 10. 领域模型（Domain Model）

### 10.1 Data Model

```
@Entity GraphNode
  - id: string               # 节点 ID（符号指纹）
  - symbol: string           # 符号名称
  - kind: string             # 符号类型（function/class/variable）
  - file_path: string        # 文件路径
  - line_start: number       # 起始行
  - line_end: number         # 结束行
  - created_at: timestamp    # 创建时间

@Entity GraphEdge
  - id: string               # 边 ID
  - source_id: string        # 源节点 ID
  - target_id: string        # 目标节点 ID
  - edge_type: EdgeType      # 边类型
  - file_path: string        # 发生位置
  - line: number             # 行号
  - created_at: timestamp    # 创建时间

@ValueObject EdgeType
  - DEFINES                  # 定义关系（symbol_roles = 1）
  - IMPORTS                  # 导入关系（symbol_roles = 2）
  - CALLS                    # 调用关系（symbol_roles = 8, ReadAccess）
  - MODIFIES                 # 修改关系（symbol_roles = 4, WriteAccess）

@ValueObject DaemonRequest
  - action: string           # ping/query/write
  - payload: object          # 请求参数
  - timestamp: number        # 请求时间

@ValueObject DaemonResponse
  - status: string           # ok/error/busy
  - data: object             # 响应数据
  - latency_ms: number       # 处理延迟

@Entity LLMRerankResult
  - index: number            # 候选索引
  - score: number            # 相关性评分（0-10）
  - reason: string           # 评分理由
```

### 10.2 Business Rules

| BR ID | 规则 | 触发条件 | 违反行为 |
|-------|------|----------|----------|
| BR-001 | 边类型必须是 4 种之一 | 写入边时 | 拒绝写入 |
| BR-002 | 孤儿节点定义为入边数 = 0 | 孤儿检测时 | 标记为孤儿 |
| BR-003 | LLM 超时 2s 自动跳过 | 调用 LLM 时 | 返回原始排序 |
| BR-004 | 守护进程崩溃自动重启 max 3 次 | 进程崩溃时 | 进入 FAILED 状态 |
| BR-005 | 高频模式阈值 >= 3 次 | 模式发现时 | 不纳入输出 |

### 10.3 Invariants（固定规则）

```
[Invariant] 图数据库文件 <= 10MB（当前项目规模）
[Invariant] 节点数 >= SCIP 索引符号数
[Invariant] 边类型 ∈ {DEFINES, IMPORTS, CALLS, MODIFIES}
[Invariant] 守护进程 PID 文件存在 ⟺ 进程运行中
[Invariant] LLM 评分 ∈ [0, 10]
```

### 10.4 Integrations（集成边界）

| 外部系统 | ACL 接口 | 隔离策略 |
|----------|----------|----------|
| LLM APIs | `llm_call(prompt) -> response` | 提供商抽象，模型变化不影响内部逻辑 |
| SCIP 索引 | `parse_scip(path) -> json` | 格式变化在解析层处理 |
| CKB MCP | `ckb_query()` 现有接口 | 不可用时降级到本地图存储 |

---

## 11. 核心数据与事件契约

### 11.1 图数据库 Schema（SQLite）

```sql
-- nodes 表
CREATE TABLE nodes (
  id TEXT PRIMARY KEY,
  symbol TEXT NOT NULL,
  kind TEXT NOT NULL,
  file_path TEXT NOT NULL,
  line_start INTEGER,
  line_end INTEGER,
  created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX idx_nodes_file ON nodes(file_path);
CREATE INDEX idx_nodes_symbol ON nodes(symbol);

-- edges 表
CREATE TABLE edges (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL,
  target_id TEXT NOT NULL,
  edge_type TEXT NOT NULL CHECK(edge_type IN ('DEFINES', 'IMPORTS', 'CALLS', 'MODIFIES')),
  file_path TEXT,
  line INTEGER,
  created_at INTEGER DEFAULT (strftime('%s', 'now')),
  FOREIGN KEY (source_id) REFERENCES nodes(id),
  FOREIGN KEY (target_id) REFERENCES nodes(id)
);

CREATE INDEX idx_edges_source ON edges(source_id);
CREATE INDEX idx_edges_target ON edges(target_id);
CREATE INDEX idx_edges_type ON edges(edge_type);
```

### 11.2 守护进程通信协议（Unix Socket）

**请求格式**：
```json
{
  "action": "query|write|ping",
  "payload": {
    "query": "SELECT * FROM nodes WHERE ...",
    "params": []
  }
}
```

**响应格式**：
```json
{
  "status": "ok|error|busy",
  "data": [...],
  "latency_ms": 15,
  "error_message": "optional error description"
}
```

### 11.3 LLM 重排序 Prompt 模板

```
You are a code relevance judge. Given a user query and a list of code snippets,
rank the snippets by their relevance to the query.

**User Query**: {query}

**Candidate Code Snippets**:
{candidates}

**Instructions**:
1. Evaluate each snippet's relevance to the query (0-10 scale)
2. Consider: semantic match, symbol references, call relationships, context fit
3. Return a JSON array of rankings

**Output Format** (JSON only, no explanation):
[
  {"index": 0, "score": 8, "reason": "direct match"},
  {"index": 1, "score": 5, "reason": "partial relevance"},
  ...
]
```

**Token 预算**：
- 单次重排序最多 10 个候选
- 每个候选最多 500 tokens
- 总输入约 6000 tokens，输出约 200 tokens

### 11.4 功能开关配置（config/features.yaml）

```yaml
features:
  graph_store:
    enabled: true
    wal_mode: true

  scip_parser:
    enabled: true
    fallback_regex: true

  daemon:
    enabled: true
    auto_restart: true
    max_restarts: 3

  llm_rerank:
    enabled: false  # 默认关闭
    provider: anthropic  # anthropic / openai / ollama
    model: claude-3-haiku
    timeout_ms: 2000

  orphan_detection:
    enabled: true

  pattern_discovery:
    enabled: true
    min_frequency: 3

  ckb:
    enabled: true
```

### 11.5 兼容性策略

| 契约 | 版本策略 | 兼容窗口 |
|------|----------|----------|
| 图数据库 Schema | SQLite 版本检查表 | 向后兼容 |
| 守护进程协议 | JSON 字段可扩展 | 永久 |
| LLM Prompt | 内部模板，无版本 | 内部 |
| 功能开关 | YAML 可选字段 | 永久 |

---

## 12. 关键机制

### 12.1 守护进程生命周期

```
                    ┌─────────────────────────────────────┐
                    │                                     │
                    ▼                                     │
┌─────────┐   启动   ┌─────────┐   正常退出   ┌─────────┐ │
│ STOPPED │ ───────▶ │ RUNNING │ ───────────▶ │ EXITED  │ │
└─────────┘         └─────────┘              └─────────┘ │
     ▲                   │                                │
     │                   │ 崩溃/超时                       │
     │                   ▼                                │
     │              ┌─────────┐                           │
     │              │ CRASHED │ ──────────────────────────┘
     │              └─────────┘   自动重启 (max 3 次)
     │                   │
     │                   │ 超过重试上限
     │                   ▼
     │              ┌─────────┐
     └────────────── │ FAILED  │
        手动干预     └─────────┘
```

### 12.2 并发模型

**策略**：单线程顺序处理 + 请求队列

```
┌─────────────────────────────────────────────────────────┐
│                    Daemon Process                        │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │ Unix Socket │───▶│ Request     │───▶│ Handler     │  │
│  │ Listener    │    │ Queue (10)  │    │ (Sequential)│  │
│  └─────────────┘    └─────────────┘    └─────────────┘  │
│                            │                  │          │
│                            ▼                  ▼          │
│                     ┌─────────────┐    ┌─────────────┐  │
│                     │ Pending     │    │ SQLite DB   │  │
│                     │ Connections │    │ (WAL Mode)  │  │
│                     └─────────────┘    └─────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**约束**：
- 队列长度限制：最多 10 个待处理请求
- 超出时返回 `{"status": "busy"}` 响应
- SQLite WAL 模式支持并发读

### 12.3 SCIP 解析机制

```
输入: index.scip (protobuf 格式)
输出: 图数据库节点 + 边

解析流程:
1. protobufjs 加载 SCIP schema
2. 解析 documents[].occurrences
3. 根据 symbol_roles 映射边类型：
   - 1 (Definition) → DEFINES
   - 2 (Import) → IMPORTS
   - 4 (WriteAccess) → MODIFIES
   - 8 (ReadAccess) → CALLS
4. 写入 SQLite 图数据库

降级策略:
- protobufjs 解析失败 → ripgrep 正则匹配
```

### 12.4 LLM 重排序机制

```
输入: 向量检索 Top-K 候选
输出: 重排序后候选

流程:
1. 检查 features.llm_rerank.enabled
   - false → 直接返回原始排序
2. 构建 Prompt（query + candidates）
3. 调用 llm_call()（2s 超时）
   - 超时 → 返回原始排序
4. 解析 JSON 响应
5. 按 score 降序重排

降级策略:
- LLM 不可用 → 跳过重排序
- 响应格式错误 → 跳过重排序
```

---

## 13. 可观测性与验收

### 13.1 Metrics

| 指标 | 类型 | 采集方式 |
|------|------|----------|
| daemon_latency_ms | Histogram | 请求处理时间 |
| daemon_queue_size | Gauge | 当前队列长度 |
| graph_node_count | Gauge | sqlite3 COUNT |
| graph_edge_count | Gauge | sqlite3 COUNT |
| llm_rerank_latency_ms | Histogram | LLM 调用时间 |
| llm_rerank_skip_count | Counter | 跳过重排序次数 |

### 13.2 KPI

| KPI | 当前 | 目标 |
|-----|------|------|
| P95 延迟 | ~3000ms | < 500ms |
| 边类型覆盖 | 1/6 | 4/6（本次） |
| CKB 依赖程度 | 必需 | 可选 |
| 能力对等度 | ~40% | ~85% |

### 13.3 SLO

| SLO | 目标 | 测量周期 |
|-----|------|----------|
| 热查询 P95 延迟 | < 500ms | 100 次请求 |
| 守护进程可用率 | > 99% | 日 |
| LLM 重排序成功率 | > 90% | 日（当启用时） |

---

## 14. 安全、合规与多租户隔离

### 14.1 安全考量

| 风险 | 缓解措施 |
|------|----------|
| SQL 注入 | 参数化查询 |
| 路径遍历 | 验证文件路径在项目范围内 |
| LLM API Key 泄露 | 环境变量存储，不写入配置文件 |
| Unix Socket 权限 | 默认 0600 |

### 14.2 多租户

**不适用** - 本系统为单机单用户设计。每个项目有独立的 `.devbooks/graph.db`。

---

## 15. 里程碑

### Phase 1: 图存储基础

- [ ] 新增 graph-store.sh
- [ ] 新增 scip-to-graph.sh
- [ ] 新增 tests/graph-store.bats
- [ ] 新增 tests/scip-to-graph.bats
- **Go/No-Go 检查点**：SCIP 解析成功 + SQLite 写入成功

### Phase 2: 延迟优化

- [ ] 新增 daemon.sh
- [ ] 新增 tests/daemon.bats
- [ ] 性能验证 P95 < 500ms
- **Go/No-Go 检查点**：延迟达标，否则优化或调整方案

### Phase 3: 功能增强

- [ ] graph-rag.sh 集成 LLM 重排序
- [ ] dependency-guard.sh 新增孤儿检测
- [ ] pattern-learner.sh 新增自动发现
- [ ] common.sh 新增 llm_call()
- [ ] 更新相关测试

### Phase 4: 集成与验收

- [ ] server.ts 注册 ci_graph_store
- [ ] 功能开关配置 config/features.yaml
- [ ] 全量回归测试
- [ ] 性能基准报告

---

## 16. Deprecation Plan

**无弃用项**。

本次变更为新增功能 + 增强现有功能，不移除任何现有能力。CKB 集成保留为可选。

---

## 17. Design Rationale（设计决策理由）

### 17.1 为什么选择 SQLite 而非内存图结构？

**备选方案**：
- A: SQLite 文件存储
- B: 纯内存 Bash 关联数组

**选择 A 的理由**：
- 持久化避免每次重建索引（几秒 → 几毫秒）
- SQL 查询灵活性高
- SQLite 已是系统标配，无需额外安装
- 支持大规模数据（内存数组受限于 Bash）

### 17.2 为什么选择 Unix Socket 而非 HTTP？

**备选方案**：
- A: Unix Socket
- B: HTTP localhost

**选择 A 的理由**：
- MCP Server 仅本地使用
- Socket 延迟最低（无 HTTP 协议开销）
- 权限控制更严格

### 17.3 为什么 LLM 重排序默认关闭？

**理由**：
- 零配置即可使用基础功能
- 避免强制用户配置 API Key
- 渐进增强：需要更高精度时再启用

### 17.4 为什么守护进程使用单线程顺序处理？

**备选方案**：
- A: 单线程顺序 + 队列
- B: 多进程 fork
- C: 多线程

**选择 A 的理由**：
- Bash 不支持原生线程
- fork 开销大、复杂度高
- 单线程简单、无锁、可预测
- SQLite WAL 支持并发读

---

## 18. Trade-offs（权衡取舍）

| 取舍 | 放弃 | 获得 |
|------|------|------|
| 4 种边类型 vs 6 种 | IMPLEMENTS/EXTENDS（需 AST） | 快速交付，SCIP 可直接提取 |
| 500ms 延迟 vs 200ms | Augment 级别极致性能 | 轻资产实现，6 倍改进已足够 |
| 单线程 vs 多线程 | 并行处理能力 | 简单、无锁、可预测 |
| LLM 默认关闭 | 开箱即高精度 | 零配置可用 |

### 不适用场景

- 超大规模仓库（>100万符号）：SQLite 性能可能不足
- 极低延迟要求（<100ms）：需要更复杂的优化
- 多语言混合项目（本次仅 TypeScript）

---

## 19. Technical Debt（技术债务）

| TD ID | 类型 | 描述 | 原因 | 影响 | 偿还计划 |
|-------|------|------|------|------|----------|
| TD-001 | Code | 仅支持 4 种边类型，缺少 IMPLEMENTS/EXTENDS | SCIP 不直接提供，需 AST 分析 | Medium | 后续迭代添加 AST 分析 |
| TD-002 | Code | 仅支持 TypeScript | 聚焦当前项目主要语言 | Medium | 后续扩展 Python/Go |
| TD-003 | Feature | 无请求取消机制 | 复杂度高 | Low | 后续迭代实现 |
| TD-004 | Test | 守护进程并发压力测试不完整 | 测试复杂度高 | Medium | 补充并发测试 |

---

## 20. 风险与降级策略

### 20.1 Failure Modes

| 失败模式 | 检测方式 | 降级策略 |
|----------|----------|----------|
| SCIP 解析失败 | protobufjs 抛出异常 | 降级到 ripgrep 正则匹配 |
| 守护进程崩溃 | PID 文件检查 | 自动重启（max 3 次） |
| LLM 调用超时 | 2s 超时检测 | 跳过重排序，返回原始排序 |
| SQLite 损坏 | 查询错误 | 删除重建数据库 |
| 队列满 | 队列长度检查 | 返回 busy 响应 |

### 20.2 Degrade Paths

```
正常路径: SCIP → 图存储 → 守护进程 → LLM 重排序
降级路径 1: SCIP 失败 → 正则匹配 → 图存储
降级路径 2: 守护进程不可用 → 直接调用脚本（冷启动）
降级路径 3: LLM 不可用 → 跳过重排序
降级路径 4: 图存储不可用 → CKB 回退（若可用）→ 线性搜索
```

---

## 21. DoD 完成定义（Definition of Done）

### 21.1 本设计何时算"完成"？

1. 所有 AC-xxx 通过验收（见 §1）
2. 所有非功能验收标准满足（见 §1.2）
3. 回归测试通过（现有测试无回归）
4. 证据产出完整（见 §21.2）

### 21.2 必须通过的闸门

| 闸门 | 验证命令 | 通过标准 |
|------|----------|----------|
| 单元测试 | `bats tests/*.bats` | 100% 通过 |
| 静态检查 | `shellcheck scripts/*.sh` | 无 error |
| TypeScript 编译 | `npm run build` | 无错误 |
| 性能基准 | `tests/daemon-perf.sh` | P95 < 600ms |
| 回归测试 | `npm test` | 100% 通过 |

### 21.3 必须产出的证据

| 证据 | 路径 | 说明 |
|------|------|------|
| Red 基线 | `evidence/red-baseline/` | 新增测试初始失败状态 |
| Green 最终 | `evidence/green-final/` | 所有测试通过状态 |
| 性能报告 | `evidence/performance-report.md` | P95 延迟测量结果 |
| SCIP 解析日志 | `evidence/scip-parse.log` | 解析成功证据 |

### 21.4 AC 交叉引用

| DoD 项 | 关联 AC |
|--------|---------|
| 单元测试通过 | AC-001 ~ AC-008 |
| 性能基准通过 | AC-003, AC-N01 |
| 回归测试通过 | AC-007 |
| 证据产出 | 所有 AC |

---

## 22. Open Questions（<=3）

| ID | 问题 | 影响范围 | 状态 |
|----|------|----------|------|
| OQ1 | 守护进程是否需要开机自启？ | daemon.sh | 后续迭代，本次不含 |
| OQ2 | SCIP 索引陈旧检测策略？ | scip-to-graph.sh | 建议使用 mtime 比较 |
| OQ3 | 空图（无节点）边界处理？ | graph-store.sh | 测试用例覆盖 |

---

## Documentation Impact（文档影响）

### 需要更新的文档

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| README.md | 新增 `ci_graph_store` 工具说明，守护进程使用说明 | P0 |
| dev-playbooks/specs/_meta/project-profile.md | 新增模块描述 | P1 |

### 无需更新的文档

- [x] 本次变更为新增功能，现有工具使用方式不变（向后兼容）

### 文档更新检查清单

- [ ] 新增脚本（graph-store.sh、scip-to-graph.sh、daemon.sh）已在使用文档中说明
- [ ] 新增配置项（features.yaml）已在配置文档中说明
- [ ] 守护进程启动/停止命令已在 README 中说明

---

## Architecture Impact（架构影响）

### 有架构变更

#### C4 层级影响

| 层级 | 变更类型 | 影响描述 |
|------|----------|----------|
| Context | 无变更 | 外部系统关系不变 |
| Container | 新增 | 新增 3 个脚本容器 + 1 个配置 |
| Component | 修改 | 3 个脚本增强 + 1 个共享函数新增 |

#### Container 变更详情

- [新增] `scripts/graph-store.sh`: SQLite 图存储管理
- [新增] `scripts/scip-to-graph.sh`: SCIP 索引到图数据转换
- [新增] `scripts/daemon.sh`: 常驻守护进程
- [修改] `scripts/graph-rag.sh`: 集成 LLM 重排序
- [修改] `scripts/dependency-guard.sh`: 新增孤儿模块检测
- [修改] `scripts/pattern-learner.sh`: 新增自动模式发现
- [修改] `scripts/common.sh`: 新增 llm_call() 适配函数

#### 依赖变更

| 源 | 目标 | 变更类型 | 说明 |
|----|------|----------|------|
| `graph-rag.sh` | `graph-store.sh` | 新增 | 图查询依赖 |
| `graph-rag.sh` | `daemon.sh` | 新增 | 守护进程通信 |
| `graph-rag.sh` | `common.sh:llm_call()` | 新增 | LLM 重排序 |
| `scip-to-graph.sh` | `graph-store.sh` | 新增 | 数据写入 |
| `dependency-guard.sh` | `graph-store.sh` | 新增 | 孤儿检测查询 |
| `server.ts` | `graph-store.sh` | 新增 | MCP 工具注册 |

#### 分层约束影响

- [x] 本次变更遵守现有分层约束
- [ ] 本次变更需要修改分层约束

所有新增脚本遵循 `shared ← core ← integration` 分层：
- graph-store.sh、scip-to-graph.sh、daemon.sh 属于 core 层
- 可依赖 common.sh（shared），被 server.ts（integration）调用

---

## Contract（契约计划）

### API 变更

#### 新增 MCP 工具

| 工具 | 功能 | 参数 |
|------|------|------|
| `ci_graph_store` | 图存储操作 | `action`, `payload` |

#### 现有工具参数扩展

| 工具 | 新增参数 | 类型 | 说明 |
|------|----------|------|------|
| `ci_graph_rag` | `--rerank` | boolean | 启用 LLM 重排序 |
| `ci_arch_check` | `--orphan-check` | boolean | 启用孤儿检测 |
| `ci_pattern` | `--auto-discover` | boolean | 启用自动模式发现 |

### 兼容策略

| 变更类型 | 兼容性 | 说明 |
|----------|--------|------|
| 新增工具 | ✅ 向后兼容 | 不影响现有调用 |
| 新增参数 | ✅ 向后兼容 | 可选参数，默认行为不变 |
| 内部接口 | N/A | 仅内部使用 |

### 守护进程通信协议（内部契约）

**版本**: 1.0.0
**传输**: Unix Socket (`.devbooks/daemon.sock`)

```typescript
// 请求
interface DaemonRequest {
  action: 'ping' | 'query' | 'write' | 'stats';
  payload?: {
    sql?: string;
    params?: any[];
    nodes?: GraphNode[];
    edges?: GraphEdge[];
  };
}

// 响应
interface DaemonResponse {
  status: 'ok' | 'error' | 'busy';
  data?: any;
  latency_ms: number;
  error_message?: string;
}
```

### 功能开关配置 Schema

**文件**: `config/features.yaml`

```yaml
# JSON Schema 约束
features:
  graph_store:
    enabled: boolean        # default: true
    wal_mode: boolean       # default: true

  scip_parser:
    enabled: boolean        # default: true
    fallback_regex: boolean # default: true

  daemon:
    enabled: boolean        # default: true
    auto_restart: boolean   # default: true
    max_restarts: integer   # default: 3, range: 1-10

  llm_rerank:
    enabled: boolean        # default: false
    provider: enum          # anthropic | openai | ollama
    model: string           # provider-specific
    timeout_ms: integer     # default: 2000, range: 500-10000

  orphan_detection:
    enabled: boolean        # default: true

  pattern_discovery:
    enabled: boolean        # default: true
    min_frequency: integer  # default: 3, range: 1-100

  ckb:
    enabled: boolean        # default: true
```

---

## Contract Test IDs（契约测试追溯）

| Test ID | 类型 | 覆盖 | 验证内容 |
|---------|------|------|----------|
| CT-GS-001 | schema | REQ-GS-001 | 图数据库 Schema 正确性（nodes/edges 表结构） |
| CT-GS-002 | behavior | REQ-GS-004 | 边类型约束（仅接受 4 种有效类型） |
| CT-GS-003 | behavior | REQ-GS-006 | 批量操作事务性（全成功或全回滚） |
| CT-SP-001 | behavior | REQ-SP-003 | SCIP symbol_roles → 边类型映射正确 |
| CT-SP-002 | behavior | REQ-SP-006 | 降级策略触发（SCIP 失败时使用正则） |
| CT-DM-001 | behavior | REQ-DM-002 | PID 文件锁机制（防止多实例） |
| CT-DM-002 | behavior | REQ-DM-004 | 请求队列限制（队列满返回 busy） |
| CT-DM-003 | behavior | REQ-DM-005 | 守护进程协议格式（JSON 请求/响应） |
| CT-DM-004 | performance | AC-003 | P95 延迟 <= 600ms（100 次热请求） |
| CT-LR-001 | behavior | REQ-LR-001 | 功能开关控制（disabled 时跳过重排序） |
| CT-LR-002 | behavior | REQ-LR-006 | 降级策略（超时/错误时返回原始排序） |
| CT-LR-003 | schema | REQ-LR-008 | 重排序结果格式正确性 |
| CT-OD-001 | behavior | REQ-OD-001 | 孤儿定义正确（入边=0 且非入口点） |
| CT-OD-002 | behavior | REQ-OD-003 | 排除模式生效（--exclude 参数） |
| CT-PD-001 | behavior | REQ-PD-004 | 高频模式阈值（频率 >= min_frequency） |
| CT-PD-002 | behavior | REQ-PD-005 | 模式持久化（写入 learned-patterns.json） |
| CT-BC-001 | regression | AC-007 | 现有测试全部通过（无回归） |
| CT-BC-002 | behavior | AC-008 | 无 CKB 时功能正常（CKB_ENABLED=false） |

### 追溯矩阵

| AC | Contract Tests |
|----|----------------|
| AC-001 | CT-GS-001, CT-GS-002, CT-GS-003 |
| AC-002 | CT-SP-001, CT-SP-002 |
| AC-003 | CT-DM-001, CT-DM-002, CT-DM-003, CT-DM-004 |
| AC-004 | CT-LR-001, CT-LR-002, CT-LR-003 |
| AC-005 | CT-OD-001, CT-OD-002 |
| AC-006 | CT-PD-001, CT-PD-002 |
| AC-007 | CT-BC-001 |
| AC-008 | CT-BC-002 |
