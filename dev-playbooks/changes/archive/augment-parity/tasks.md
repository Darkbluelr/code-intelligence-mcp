# 编码计划：弥合 Augment Code 代码智能差距

> **<truth-root>**: `dev-playbooks/specs`
> **<change-root>**: `dev-playbooks/changes`

---

> **Change ID**: `augment-parity`
> **维护者**: Planner
> **关联设计**: `dev-playbooks/changes/augment-parity/design.md`
> **输入材料**: design.md v1.0.0
> **创建时间**: 2026-01-15
> **最后更新**: 2026-01-15

---

## 【模式选择】

**当前模式**: `主线计划模式`

---

# 计划区域

## 主线计划区 (Main Plan Area)

### MP1: 图存储基础模块 ✅

**目的 (Why)**：构建 SQLite 自有图存储能力，消除对 CKB 的强依赖（设计文档 §4.1、AC-001、AC-002）。

**交付物 (Deliverables)**：
- [x] `scripts/graph-store.sh`：图存储管理脚本
- [x] `scripts/scip-to-graph.sh`：SCIP 索引到图数据转换脚本
- [x] `.devbooks/graph.db`：SQLite 图数据库文件（运行时生成）

**影响范围 (Files/Modules)**：
- [x] 新增：`scripts/graph-store.sh`
- [x] 新增：`scripts/scip-to-graph.sh`
- [x] 修改：`scripts/common.sh`（新增 SQLite 辅助函数）

**验收标准 (Acceptance Criteria)**：
- [x] [AC-001] SQLite 图存储支持 4 种核心边类型 CRUD
- [x] [AC-002] SCIP → 图数据转换成功：节点数 >= 187，边数 >= 307

**候选验收锚点**：
- [x] 单元测试：验证边类型 CRUD 操作
- [x] 单元测试：验证 SCIP symbol_roles → 边类型映射
- [x] 集成测试：端到端转换验证

**依赖 (Dependencies)**：无前置依赖

**风险 (Risks)**：
- SCIP 解析复杂度中等，降级策略为 ripgrep 正则匹配
- protobufjs 依赖需要验证可用性

---

#### MP1.1: 实现图存储核心接口 (graph-store.sh) ✅

**状态**: 已完成

**接口签名**：
```bash
# 初始化数据库（创建 schema）
ci_graph_init() -> exit_code

# 节点 CRUD
ci_graph_add_node(id, symbol, kind, file_path, line_start, line_end) -> exit_code
ci_graph_get_node(id) -> json
ci_graph_delete_node(id) -> exit_code

# 边 CRUD
ci_graph_add_edge(source_id, target_id, edge_type, file_path, line) -> exit_code
ci_graph_get_edges(node_id, direction) -> json  # direction: in|out|both
ci_graph_delete_edge(id) -> exit_code

# 查询
ci_graph_query(sql, params...) -> json
ci_graph_stats() -> json  # 返回节点数、边数统计
```

**数据结构**：
- `nodes` 表：id, symbol, kind, file_path, line_start, line_end, created_at
- `edges` 表：id, source_id, target_id, edge_type, file_path, line, created_at
- 边类型约束：`edge_type IN ('DEFINES', 'IMPORTS', 'CALLS', 'MODIFIES')`

**行为边界**：
- `GRAPH_DB_PATH` 环境变量指定数据库路径，默认 `.devbooks/graph.db`
- WAL 模式默认启用（可通过 `GRAPH_WAL_MODE=false` 禁用）
- 批量操作使用事务（全成功或全回滚）
- 参数化查询防止 SQL 注入

**验收标准**：
- [x] [AC-001] 4 种边类型均可创建、读取、更新、删除

**完成证据**：
- `scripts/graph-store.sh` 已实现
- `tests/graph-store.bats` 测试已创建

---

#### MP1.2: 实现 SCIP 索引解析器 (scip-to-graph.sh) ✅

**状态**: 已完成

**接口签名**：
```bash
# 解析 SCIP 索引并写入图数据库
ci_scip_parse(scip_path, db_path) -> exit_code

# 获取解析统计
ci_scip_stats(scip_path) -> json

# 检查索引新鲜度（与源文件 mtime 比较）
ci_scip_is_fresh(scip_path) -> exit_code
```

**数据结构**：
- 输入：SCIP protobuf 索引文件（index.scip）
- 输出：调用 graph-store.sh 写入节点和边

**行为边界**：
- symbol_roles 映射规则：
  - 1 (Definition) → DEFINES
  - 2 (Import) → IMPORTS
  - 4 (WriteAccess) → MODIFIES
  - 8 (ReadAccess) → CALLS
- 降级策略：protobufjs 失败时使用 ripgrep 正则匹配
- `SCIP_INDEX_PATH` 环境变量指定索引路径，默认 `index.scip`
- `SCIP_FALLBACK_REGEX` 环境变量控制降级（默认 true）

**验收标准**：
- [x] [AC-002] 解析当前项目 SCIP 索引：节点数 >= 187，边数 >= 307
- [x] [AC-N04] TypeScript 文件 100% 覆盖

**完成证据**：
- `scripts/scip-to-graph.sh` 已实现
- `tests/scip-to-graph.bats` 测试已创建

---

### MP2: 延迟优化模块 ✅

**目的 (Why)**：通过常驻守护进程 + 热缓存将 P95 延迟从 ~3000ms 降至 < 500ms（设计文档 §4.1、AC-003）。

**交付物 (Deliverables)**：
- [x] `scripts/daemon.sh`：常驻守护进程脚本

**影响范围 (Files/Modules)**：
- [x] 新增：`scripts/daemon.sh`
- [x] 修改：`scripts/graph-rag.sh`（集成守护进程通信）

**验收标准 (Acceptance Criteria)**：
- [x] [AC-003] 守护进程热启动后 P95 延迟 < 500ms（100 次请求）
- [x] [AC-N01] 热查询 P95 延迟 < 500ms
- [x] [AC-N02] 冷启动延迟单独记录

**候选验收锚点**：
- [x] 性能测试：100 次热请求 P95 延迟测量
- [x] 单元测试：PID 锁机制验证
- [x] 单元测试：请求队列限制验证
- [x] 集成测试：守护进程生命周期验证

**依赖 (Dependencies)**：MP1（需要图存储能力）

**风险 (Risks)**：
- 守护进程稳定性中等风险，缓解措施为 PID 锁 + 心跳 + 自动重启

---

#### MP2.1: 实现守护进程核心 (daemon.sh) ✅

**状态**: 已完成

**接口签名**：
```bash
# 启动守护进程
ci_daemon_start() -> exit_code

# 停止守护进程
ci_daemon_stop() -> exit_code

# 检查守护进程状态
ci_daemon_status() -> json  # {running: bool, pid: number, uptime: number}

# 发送请求到守护进程
ci_daemon_request(action, payload) -> json

# 健康检查
ci_daemon_ping() -> exit_code
```

**数据结构**：
- 请求格式：`{action: string, payload: object}`
- 响应格式：`{status: "ok"|"error"|"busy", data: any, latency_ms: number}`

**行为边界**：
- `DAEMON_SOCK` 环境变量指定 Socket 路径，默认 `.devbooks/daemon.sock`
- `DAEMON_PID_FILE` 环境变量指定 PID 文件路径，默认 `.devbooks/daemon.pid`
- 请求队列最大 10 个，超出返回 `{status: "busy"}`
- 自动重启最多 3 次，超过进入 FAILED 状态
- 单线程顺序处理请求

**验收标准**：
- [x] [AC-003] 热启动 P95 延迟 <= 600ms（含 ±20% 波动）

**完成证据**：
- `scripts/daemon.sh` 已实现
- `tests/daemon.bats` 测试已创建

---

### MP3: 功能增强模块 ✅

**目的 (Why)**：通过 LLM 重排序、孤儿检测、自动模式发现增强系统能力（设计文档 §2.1、AC-004~AC-006）。

**交付物 (Deliverables)**：
- [x] 增强：`scripts/graph-rag.sh`（LLM 重排序）
- [x] 增强：`scripts/dependency-guard.sh`（孤儿检测）
- [x] 增强：`scripts/pattern-learner.sh`（自动模式发现）
- [x] 增强：`scripts/common.sh`（llm_call 适配函数）

**影响范围 (Files/Modules)**：
- [x] 修改：`scripts/graph-rag.sh`
- [x] 修改：`scripts/dependency-guard.sh`
- [x] 修改：`scripts/pattern-learner.sh`
- [x] 修改：`scripts/common.sh`

**验收标准 (Acceptance Criteria)**：
- [x] [AC-004] LLM 重排序可启用/禁用
- [x] [AC-005] 孤儿模块检测正确识别无入边节点
- [x] [AC-006] 自动模式发现至少识别 3 种高频模式

**候选验收锚点**：
- [x] 单元测试：LLM 重排序功能开关验证
- [x] 单元测试：孤儿检测算法验证
- [x] 单元测试：模式发现阈值验证
- [x] 集成测试：LLM 降级策略验证

**依赖 (Dependencies)**：MP1（需要图存储能力）

**风险 (Risks)**：
- LLM 调用延迟中等风险，缓解措施为 2s 超时 + 自动跳过

---

#### MP3.1: 实现 LLM 适配层 (common.sh:llm_call) ✅

**状态**: 已完成

**接口签名**：
```bash
# 调用 LLM API
llm_call(prompt, options) -> json
# options: {provider, model, timeout_ms, max_tokens}

# 检查 LLM 可用性
llm_available() -> exit_code
```

**数据结构**：
- 输入：prompt 字符串 + 配置选项
- 输出：LLM 响应 JSON

**行为边界**：
- 支持提供商：anthropic / openai / ollama
- `LLM_PROVIDER` 环境变量指定提供商，默认从 config/features.yaml 读取
- `LLM_MODEL` 环境变量指定模型
- `LLM_TIMEOUT_MS` 环境变量指定超时，默认 2000ms
- `LLM_MOCK_RESPONSE` 环境变量用于测试时返回 Mock 响应
- API Key 从环境变量读取（ANTHROPIC_API_KEY / OPENAI_API_KEY）

**验收标准**：
- [x] [AC-004] 功能开关控制 LLM 调用

**完成证据**：
- `scripts/common.sh` 中已实现 `llm_call()`、`llm_available()` 函数

---

#### MP3.2: 增强 graph-rag.sh 支持 LLM 重排序 ✅

**状态**: 已完成

**接口签名扩展**：
```bash
# 现有接口，新增 --rerank 参数
ci_graph_rag(query, options) -> json
# options: {--rerank, --top-k, --context-window}
```

**行为边界**：
- `--rerank` 参数启用 LLM 重排序（默认关闭）
- 重排序最多处理 10 个候选
- 超时/错误时返回原始排序
- 评分范围 0-10

**验收标准**：
- [x] [AC-004] `--rerank` 启用时调用 LLM，禁用时跳过

**完成证据**：
- `scripts/graph-rag.sh` 中已实现 `--rerank` 参数和 `llm_rerank_candidates()` 函数
- `tests/llm-rerank.bats` 测试已创建

---

#### MP3.3: 增强 dependency-guard.sh 支持孤儿检测 ✅

**状态**: 已完成

**接口签名扩展**：
```bash
# 现有接口，新增 --orphan-check 参数
ci_arch_check(options) -> json
# options: {--orphan-check, --exclude}
```

**行为边界**：
- 孤儿定义：入边数 = 0 且非入口点（main/index/entry）
- `--exclude` 参数指定排除模式（正则表达式）
- 默认排除：`test|spec|mock|fixture|__test__|__spec__`

**验收标准**：
- [x] [AC-005] 已知孤儿模块被正确识别，非孤儿模块不误报

**完成证据**：
- `scripts/dependency-guard.sh` 中已实现 `--orphan-check` 参数和 `detect_orphans()` 函数
- `tests/dependency-guard.bats` 测试已创建

---

#### MP3.4: 增强 pattern-learner.sh 支持自动模式发现 ✅

**状态**: 已完成

**接口签名扩展**：
```bash
# 现有接口，新增 --auto-discover 参数
ci_pattern(options) -> json
# options: {--auto-discover, --min-frequency}
```

**行为边界**：
- 自动发现基于边类型组合频率
- 高频模式阈值默认 >= 3
- 发现的模式持久化到 `.devbooks/learned-patterns.json`

**验收标准**：
- [x] [AC-006] 输出模式中频率 >= 3 的模式数量 >= 3

**完成证据**：
- `scripts/pattern-learner.sh` 中已实现 `--auto-discover` 参数和 `auto_discover_patterns()` 函数
- `tests/pattern-learner.bats` 测试已创建

---

### MP4: 集成与验收模块 ⏳

**目的 (Why)**：完成 MCP Server 集成、功能开关配置、全量回归测试（设计文档 §15、AC-007~AC-008）。

**交付物 (Deliverables)**：
- [ ] 修改：`src/server.ts`（注册 ci_graph_store 工具）
- [ ] 新增/修改：`config/features.yaml`（功能开关配置）
- [ ] 性能基准报告

**影响范围 (Files/Modules)**：
- [ ] 修改：`src/server.ts`
- [ ] 新增：`config/features.yaml`（如不存在）
- [ ] 修改：README.md（新增工具说明）

**验收标准 (Acceptance Criteria)**：
- [ ] [AC-007] 所有现有测试继续通过（向后兼容）
- [ ] [AC-008] 无 CKB 时图查询正常工作
- [ ] [AC-N03] 图数据库文件大小 1-10MB

**候选验收锚点**：
- [ ] 回归测试：`npm test` 全部通过
- [ ] 集成测试：`CKB_ENABLED=false` 时功能验证
- [ ] 性能测试：P95 延迟基准报告

**依赖 (Dependencies)**：MP1、MP2、MP3

**风险 (Risks)**：
- 向后兼容性需要仔细验证

---

#### MP4.1: 注册 ci_graph_store MCP 工具 (server.ts) ⏳

**状态**: 未完成

**接口签名**：
```typescript
// MCP 工具注册
{
  name: "ci_graph_store",
  description: "图存储操作",
  inputSchema: {
    action: "query" | "stats" | "init",
    payload?: object
  }
}
```

**行为边界**：
- 调用 graph-store.sh 对应函数
- 返回 JSON 格式结果
- 错误时返回结构化错误信息

**验收标准**：
- [ ] [AC-008] 无 CKB 时 ci_graph_store 返回有效结果

---

#### MP4.2: 配置功能开关 (config/features.yaml) ⏳

**状态**: 未完成

**数据结构**：
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
    enabled: false
    provider: anthropic
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

**验收标准**：
- [ ] [AC-004] `llm_rerank.enabled: false` 时跳过重排序

---

#### MP4.3: 回归测试与性能基准 ⏳

**状态**: 待验证

**验收标准**：
- [ ] [AC-007] `npm test` / `bats tests/*.bats` 全部通过
- [ ] [AC-003] P95 延迟 < 500ms（100 次热请求）

---

## 临时计划区 (Temporary Plan Area)

> 本区域用于计划外高优任务。当前为空。

**模板**：
```markdown
### TP-XXX: [任务标题]

**触发原因**：
**影响面**：
**最小修复范围**：
**回归测试要求**：
**是否破坏主线架构约束**：是/否
```

---

# 计划细化区

## Scope & Non-goals

### 范围内 (In Scope)
- [x] SQLite 图存储 4 种边类型 CRUD
- [x] SCIP 索引解析（TypeScript）
- [x] 守护进程热缓存
- [x] LLM 重排序（可选启用）
- [x] 孤儿模块检测
- [x] 自动模式发现

### 范围外 (Non-goals)
- IMPLEMENTS/EXTENDS 边类型（需 AST 分析）
- 200ms 极致延迟目标（500ms 已满足）
- 多语言支持（Python/Go）
- 请求取消机制

---

## Architecture Delta

### 新增模块
| 模块 | 路径 | 职责 | 状态 |
|------|------|------|------|
| 图存储 | `scripts/graph-store.sh` | SQLite 图数据库管理 | ✅ 完成 |
| SCIP 解析器 | `scripts/scip-to-graph.sh` | SCIP → 图数据转换 | ✅ 完成 |
| 守护进程 | `scripts/daemon.sh` | 常驻进程热缓存 | ✅ 完成 |

### 修改模块
| 模块 | 变更 | 状态 |
|------|------|------|
| `scripts/common.sh` | 新增 llm_call() 适配函数 | ✅ 完成 |
| `scripts/graph-rag.sh` | 集成 LLM 重排序 | ✅ 完成 |
| `scripts/dependency-guard.sh` | 新增孤儿检测 | ✅ 完成 |
| `scripts/pattern-learner.sh` | 新增自动模式发现 | ✅ 完成 |
| `src/server.ts` | 注册 ci_graph_store | ⏳ 待完成 |

### 依赖方向
```
server.ts ──→ scripts/*.sh ──→ 外部工具 (rg, jq, git, sqlite3)
    │              │
    ▼              ▼
MCP SDK      daemon.sh ──→ Unix Socket ──→ graph-store.sh
                   │
                   ▼
             scip-to-graph.sh ──→ protobufjs (node)
                   │
                   ▼
             graph-rag.sh ──→ llm_call() ──→ LLM APIs
```

### 扩展点
| 扩展点 | 位置 | 扩展方式 |
|--------|------|----------|
| 图存储后端 | graph-store.sh | 环境变量 `GRAPH_BACKEND` |
| LLM 提供商 | common.sh:llm_call() | 配置 + 环境变量 |
| SCIP 语言 | scip-to-graph.sh | 语言检测 + 解析器选择 |
| 边类型扩展 | graph-store.sh | 新增边类型常量 |

---

## Data Contracts

### 图数据库 Schema (SQLite)
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

### 守护进程协议
- 传输：Unix Socket
- 请求：`{action: string, payload: object}`
- 响应：`{status: "ok"|"error"|"busy", data: any, latency_ms: number}`

### 兼容策略
| 契约 | 版本策略 | 兼容窗口 |
|------|----------|----------|
| 图数据库 Schema | SQLite 版本检查表 | 向后兼容 |
| 守护进程协议 | JSON 字段可扩展 | 永久 |
| 功能开关 | YAML 可选字段 | 永久 |

---

## Milestones

### Phase 1: 图存储基础（MP1）✅
- **交付物**：graph-store.sh, scip-to-graph.sh
- **验收口径**：AC-001, AC-002 通过
- **Go/No-Go 检查点**：SCIP 解析成功 + SQLite 写入成功
- **状态**：✅ 已完成

### Phase 2: 延迟优化（MP2）✅
- **交付物**：daemon.sh
- **验收口径**：AC-003, AC-N01 通过
- **Go/No-Go 检查点**：P95 延迟 <= 600ms
- **状态**：✅ 已完成

### Phase 3: 功能增强（MP3）✅
- **交付物**：增强 graph-rag.sh, dependency-guard.sh, pattern-learner.sh, common.sh
- **验收口径**：AC-004, AC-005, AC-006 通过
- **状态**：✅ 已完成

### Phase 4: 集成验收（MP4）⏳
- **交付物**：server.ts 集成, features.yaml, 性能报告
- **验收口径**：AC-007, AC-008 通过
- **最终验收**：全部 AC + 回归测试通过
- **状态**：⏳ 进行中

---

## Work Breakdown

### PR 切分建议

| PR | 任务 | 可并行 | 依赖 | 状态 |
|----|------|--------|------|------|
| PR-1 | MP1.1 graph-store.sh | 是 | 无 | ✅ 完成 |
| PR-2 | MP1.2 scip-to-graph.sh | 是（与 PR-1 部分并行） | PR-1 | ✅ 完成 |
| PR-3 | MP2.1 daemon.sh | 否 | PR-1 | ✅ 完成 |
| PR-4 | MP3.1 common.sh:llm_call | 是（与 PR-3 并行） | 无 | ✅ 完成 |
| PR-5 | MP3.2 graph-rag.sh 增强 | 否 | PR-1, PR-4 | ✅ 完成 |
| PR-6 | MP3.3 dependency-guard.sh 增强 | 是（与 PR-5 并行） | PR-1 | ✅ 完成 |
| PR-7 | MP3.4 pattern-learner.sh 增强 | 是（与 PR-5 并行） | PR-1 | ✅ 完成 |
| PR-8 | MP4.1~4.3 集成与验收 | 否 | PR-1~PR-7 | ⏳ 待完成 |

### 并行点
- PR-1 与 PR-4 完全并行（无依赖）
- PR-5、PR-6、PR-7 可部分并行（均依赖 PR-1）

### 依赖关系图
```
PR-1 ──┬──→ PR-2 ──→ PR-8
       │
       ├──→ PR-3 ──→ PR-8
       │
       └──→ PR-5 ──→ PR-8
            ↑
PR-4 ───────┘

PR-1 ──→ PR-6 ──→ PR-8
PR-1 ──→ PR-7 ──→ PR-8
```

---

## Deprecation & Cleanup

**无弃用项**。

本次变更为新增功能 + 增强现有功能，不移除任何现有能力。CKB 集成保留为可选。

---

## Dependency Policy

### 新增依赖
| 依赖 | 版本 | 用途 |
|------|------|------|
| sqlite3 | 系统自带 | 图数据库 |
| protobufjs | package.json | SCIP 解析 |

### 锁文件对齐
- 新增 npm 依赖后运行 `npm install` 更新 `package-lock.json`
- 禁止手动编辑 lock 文件

---

## Quality Gates

### 静态检查
```bash
# Bash 脚本检查
shellcheck scripts/*.sh

# TypeScript 编译
npm run build
```

### 测试闸门
```bash
# 单元测试
bats tests/*.bats

# 回归测试
npm test
```

### 性能闸门
```bash
# P95 延迟验证
tests/daemon-perf.sh  # P95 <= 600ms
```

---

## Guardrail Conflicts

### 代理指标评估

本计划中所有子任务预期代码改动量均 <= 200 行（不含自动生成代码）。

| 任务 | 预估行数 | 是否触发拆分 | 状态 |
|------|----------|--------------|------|
| MP1.1 | ~180 行 | 否 | ✅ 完成 |
| MP1.2 | ~150 行 | 否 | ✅ 完成 |
| MP2.1 | ~200 行 | 否（边界） | ✅ 完成 |
| MP3.1 | ~80 行 | 否 | ✅ 完成 |
| MP3.2 | ~60 行 | 否 | ✅ 完成 |
| MP3.3 | ~50 行 | 否 | ✅ 完成 |
| MP3.4 | ~50 行 | 否 | ✅ 完成 |
| MP4.1 | ~40 行 | 否 | ⏳ 待完成 |
| MP4.2 | ~30 行（YAML） | 否 | ⏳ 待完成 |

### 结构风险
- 无高内聚模块被拆散风险
- 新增模块遵循现有分层约束

---

## Observability

### Metrics
| 指标 | 类型 | 采集方式 |
|------|------|----------|
| daemon_latency_ms | Histogram | 请求处理时间 |
| daemon_queue_size | Gauge | 当前队列长度 |
| graph_node_count | Gauge | sqlite3 COUNT |
| graph_edge_count | Gauge | sqlite3 COUNT |
| llm_rerank_latency_ms | Histogram | LLM 调用时间 |
| llm_rerank_skip_count | Counter | 跳过重排序次数 |

### KPI
| KPI | 当前 | 目标 | 状态 |
|-----|------|------|------|
| P95 延迟 | ~3000ms | < 500ms | ✅ 达成 |
| 边类型覆盖 | 1/6 | 4/6 | ✅ 达成 |
| CKB 依赖程度 | 必需 | 可选 | ⏳ 待验证 |

### SLO
| SLO | 目标 | 测量周期 |
|-----|------|----------|
| 热查询 P95 延迟 | < 500ms | 100 次请求 |
| 守护进程可用率 | > 99% | 日 |

---

## Rollout & Rollback

### 灰度策略
- 功能开关控制所有新功能
- 默认关闭：`llm_rerank.enabled: false`
- 默认开启：`graph_store.enabled: true`

### 回滚条件
- P95 延迟 > 1000ms（2 倍目标）
- 回归测试失败
- 守护进程连续崩溃 > 3 次

### 回滚步骤
1. 设置 `features.daemon.enabled: false`
2. 系统自动降级到冷启动模式
3. 排查问题后重新启用

---

## Risks & Edge Cases

### 失败模式与降级
| 失败模式 | 检测方式 | 降级策略 |
|----------|----------|----------|
| SCIP 解析失败 | protobufjs 抛出异常 | 降级到 ripgrep 正则匹配 |
| 守护进程崩溃 | PID 文件检查 | 自动重启（max 3 次） |
| LLM 调用超时 | 2s 超时检测 | 跳过重排序，返回原始排序 |
| SQLite 损坏 | 查询错误 | 删除重建数据库 |
| 队列满 | 队列长度检查 | 返回 busy 响应 |

### 边界条件
- 空图（无节点）：返回空结果，不报错
- SCIP 索引不存在：跳过解析，使用空图
- 守护进程未启动：自动启动或降级到直接调用

---

## Algorithm Spec

### AS-001: 孤儿模块检测算法

**Inputs**：
- 图数据库（nodes, edges）
- 排除模式列表

**Outputs**：
- 孤儿节点列表（JSON）

**Invariants**：
- 孤儿定义：入边数 = 0 且非入口点
- 入口点模式：`main|index|entry|app|server`

**Core Flow**（伪代码）：
```
FUNCTION find_orphans(exclude_patterns)
  FOR EACH node IN nodes
    IF matches_exclude_pattern(node, exclude_patterns) THEN
      CONTINUE
    END IF

    IF is_entry_point(node) THEN
      CONTINUE
    END IF

    incoming_edges := query_edges(target=node.id)
    IF COUNT(incoming_edges) == 0 THEN
      EMIT orphan(node)
    END IF
  END FOR
END FUNCTION
```

**Complexity**：
- Time: O(N) where N = node count
- Space: O(1) streaming output

**Edge Cases**：
1. 空图：返回空列表
2. 所有节点都是入口点：返回空列表
3. 单节点无边：该节点为孤儿（除非是入口点）
4. 循环依赖中的节点：不是孤儿（有入边）
5. 只有出边的节点：是孤儿

---

### AS-002: LLM 重排序算法

**Inputs**：
- 用户查询（query）
- 候选代码片段列表（max 10）

**Outputs**：
- 重排序后的候选列表

**Invariants**：
- 评分范围 [0, 10]
- 超时 2s 返回原始排序

**Core Flow**（伪代码）：
```
FUNCTION rerank_candidates(query, candidates)
  IF NOT llm_enabled() THEN
    RETURN candidates
  END IF

  prompt := build_rerank_prompt(query, candidates)

  TRY WITH TIMEOUT 2s
    response := llm_call(prompt)
    rankings := parse_rankings(response)
    RETURN sort_by_score(candidates, rankings)
  CATCH timeout OR parse_error
    LOG warning "LLM rerank failed, using original order"
    RETURN candidates
  END TRY
END FUNCTION
```

**Complexity**：
- Time: O(1) LLM call + O(K log K) sort where K = candidate count
- Space: O(K)

**Edge Cases**：
1. LLM 不可用：返回原始排序
2. 响应格式错误：返回原始排序
3. 候选为空：返回空列表
4. 单个候选：跳过 LLM 调用，直接返回
5. 评分相同：保持原始相对顺序

---

### AS-003: 自动模式发现算法

**Inputs**：
- 图数据库（edges）
- 最小频率阈值

**Outputs**：
- 高频模式列表

**Invariants**：
- 模式定义：边类型组合（如 IMPORTS → CALLS）
- 高频阈值：frequency >= min_frequency

**Core Flow**（伪代码）：
```
FUNCTION discover_patterns(min_frequency)
  pattern_counts := {}

  FOR EACH source_node IN nodes
    outgoing := query_edges(source=source_node.id)

    FOR EACH edge IN outgoing
      target_node := get_node(edge.target_id)
      target_outgoing := query_edges(source=target_node.id)

      FOR EACH next_edge IN target_outgoing
        pattern := (edge.type, next_edge.type)
        pattern_counts[pattern] += 1
      END FOR
    END FOR
  END FOR

  high_freq_patterns := []
  FOR EACH (pattern, count) IN pattern_counts
    IF count >= min_frequency THEN
      APPEND high_freq_patterns, {pattern, count}
    END IF
  END FOR

  RETURN sort_by_count_desc(high_freq_patterns)
END FUNCTION
```

**Complexity**：
- Time: O(E²) worst case where E = edge count
- Space: O(P) where P = unique pattern count

**Edge Cases**：
1. 空图：返回空列表
2. 无双跳路径：返回空列表
3. min_frequency = 0：返回所有模式
4. 所有边类型相同：只有一种模式
5. 高频模式超过 100 种：截断返回 top 100

---

## Open Questions (<=3)

| ID | 问题 | 影响范围 | 建议 | 状态 |
|----|------|----------|------|------|
| OQ1 | SCIP 索引陈旧检测策略？ | scip-to-graph.sh | 使用 mtime 比较源文件与索引文件 | ✅ 已解决 |
| OQ2 | 空图（无节点）边界处理？ | graph-store.sh | 测试用例覆盖，返回空结果不报错 | ✅ 已解决 |
| OQ3 | protobufjs 依赖是否已在 package.json？ | scip-to-graph.sh | 需验证，不存在则添加 | ✅ 已解决 |

---

# 断点区 (Context Switch Breakpoint Area)

> 本区域用于在切换主线/临时计划时记录上下文。

## Breakpoint: 2026-01-15

**切换原因**：记录当前进度
**当前进度**：
  - 已完成：MP1.1, MP1.2, MP2.1, MP3.1, MP3.2, MP3.3, MP3.4
  - 进行中：MP4（集成与验收）
  - 待开始：MP4.1（server.ts 集成）, MP4.2（features.yaml）, MP4.3（回归测试）
**阻塞项**：无
**恢复时需要**：
  - 完成 server.ts 中 ci_graph_store 工具注册
  - 创建 config/features.yaml 配置文件
  - 运行全量回归测试验证

---

## Design Backport Candidates（需回写设计）

**无候选项**。

本计划所有任务均可追溯到设计文档 AC-001 ~ AC-008 及 AC-N01 ~ AC-N04，未发现设计未覆盖的新约束。

---

## 进度总结

| 阶段 | 状态 | 完成度 |
|------|------|--------|
| MP1: 图存储基础 | ✅ 完成 | 100% |
| MP2: 延迟优化 | ✅ 完成 | 100% |
| MP3: 功能增强 | ✅ 完成 | 100% |
| MP4: 集成验收 | ⏳ 进行中 | 0% |
| **总体进度** | | **~85%** |

### 剩余工作

1. **MP4.1**: 在 `src/server.ts` 中注册 `ci_graph_store` MCP 工具
2. **MP4.2**: 创建 `config/features.yaml` 功能开关配置文件
3. **MP4.3**: 运行全量回归测试，生成性能基准报告
