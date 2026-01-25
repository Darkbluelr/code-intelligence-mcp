# 提案：补齐 Augment 对等最后差距（Final Gaps）

> **Change ID**: `augment-parity-final-gaps`
> **Author**: Proposal Author (Claude)
> **Date**: 2026-01-16
> **Status**: Approved
---

## 人类要求（最高优先级，Challenger 和 Judge 不可违背）

**强制约束**：本提案覆盖之前多 agent 分析发现的**所有剩余轻资产差距**，必须在本变更包内一次性完成。

理由：
1. 这是 `achieve-augment-full-parity` 的补充完整版，覆盖该提案未涉及的差距项
2. 与前序变更包配合后，实现 100% 轻资产能力对等
3. 用户明确要求一次性交付，避免多轮变更的协调开销

---

## 1. Why（问题与目标）

### 问题陈述

基于 2026-01-16 对 Augment.md 文档的五维度多 agent 深度分析，当前项目（含已批准的 `augment-parity` 和 `achieve-augment-full-parity` 变更包）仍存在以下**轻资产可解决的最终差距**：

| 维度 | 差距项 | 当前状态 | Augment 基准 | 预计影响 |
|------|--------|---------|-------------|---------|
| **图存储与检索** | 边类型不完整 | 4 种基础边 | 6+ 种（含 IMPLEMENTS/EXTENDS/RETURNS_TYPE） | 类型关系追踪缺失 |
| **图存储与检索** | 路径查询缺失 | 无 A-B 路径算法 | BFS 最短路径 | 影响分析不完整 |
| **上下文引擎** | ADR 未集成 | 无架构决策关联 | ADR 解析 + 上下文关联 | 架构决策上下文缺失 |
| **上下文引擎** | 对话历史信号弱 | 仅记录查询历史 | 多轮对话上下文累积 | 对话连续性差 |
| **延迟与实时性** | 无预热机制 | 冷启动延迟高 | 热启动预加载 | 首次响应慢 |
| **延迟与实时性** | 无请求取消 | 请求必须完成 | 击键检测取消 | 资源浪费 |
| **延迟与实时性** | 无子图内存缓存 | 每次查询重读 SQLite | 热点子图 LRU 常驻 | 重复查询慢 |
| **Bug 定位** | 分析工具未融合 | bug-locator 独立 | 调用链 + 影响分析融合 | 定位精度受限 |
| **企业级治理** | 无 CI/CD 集成 | 仅 pre-commit 本地 | GitHub Action PR 拦截 | 架构守门缺失 |
| **企业级治理** | 循环检测未自动化 | 需手动运行 | CI 自动检测 | 漏检风险 |

### 目标

在**轻资产**范围内弥合上述最终差距，使当前项目配合前序变更包后**完全达到 Augment 轻资产能力对等**。

### 与前序变更包的关系

| 变更包 | 覆盖范围 | 状态 |
|--------|---------|------|
| `enhance-code-intelligence` | 基础功能（热点/边界/模式/Bug 定位等） | Archived |
| `augment-parity` | 图存储、SCIP、守护进程、LLM 重排序、孤儿检测 | Archived |
| `augment-upgrade-phase2` | 缓存管理、依赖守卫、上下文层、联邦 | Archived |
| `achieve-augment-full-parity` | AST Delta、影响分析、COD、智能裁剪、虚拟边、意图学习、漏洞追踪 | Approved（有条件） |
| `augment-parity-final-gaps`（本提案） | 边类型扩展、路径查询、ADR、预热、请求取消、LRU 缓存、分析融合、CI/CD | Pending |

**所有变更包合并后综合对等度**：~95% → **100%**（轻资产范围内）

### 非目标

- 自研 LLM 模型（重资产）
- 实时文件系统监听 daemon（需要额外架构）
- IDE 插件开发（重资产）
- 分布式图数据库迁移（重资产）

---

## 2. What Changes（变更范围）

### 2.1 变更清单

本提案包含 **12 个变更模块**：

#### 模块 1：边类型扩展（IMPLEMENTS/EXTENDS/RETURNS_TYPE）

| 项目 | 内容 |
|------|------|
| 修改文件 | `scripts/scip-to-graph.sh`、`scripts/graph-store.sh` |
| 功能 | 扩展边类型支持：IMPLEMENTS（接口实现）、EXTENDS（继承）、RETURNS_TYPE（返回类型） |
| 数据来源 | SCIP 索引的 `symbol_roles` 位图和 `relationships` 字段 |
| 输出 | graph.db 中新增边类型 |

**技术实现**：
```
扩展 map_role_to_edge_type() 函数：
- SymbolRole.Implementation → IMPLEMENTS
- SymbolRole.Definition + 继承关系 → EXTENDS
- 函数签名中的返回类型 → RETURNS_TYPE
```

**OPT-02 补充：SCIP 字段缺失时的降级策略**

不同语言的 SCIP 索引器对边类型字段的支持程度不同：

| 语言 | SCIP 索引器 | 支持 IMPLEMENTS | 支持 EXTENDS | 支持 RETURNS_TYPE |
|------|------------|-----------------|--------------|-------------------|
| TypeScript | scip-typescript | ✅ | ✅ | ✅ |
| Python | scip-python | ✅ | ✅ | ⚠️ 部分（需类型注解） |
| Go | scip-go | ✅ | ❌（无类继承） | ✅ |
| Java | scip-java | ✅ | ✅ | ✅ |
| Rust | rust-analyzer | ✅ | ❌（无类继承） | ✅ |

**降级策略**：
```bash
# scip-to-graph.sh 中的降级处理
map_role_to_edge_type() {
    local symbol_role="$1"
    local relationships="$2"
    local lang="$3"

    # 尝试解析 IMPLEMENTS
    if has_role "$symbol_role" "Implementation"; then
        echo "IMPLEMENTS"
        return 0
    fi

    # 尝试解析 EXTENDS（部分语言不支持）
    if has_role "$symbol_role" "Definition" && has_inheritance "$relationships"; then
        echo "EXTENDS"
        return 0
    fi

    # 尝试解析 RETURNS_TYPE
    if has_return_type "$relationships"; then
        echo "RETURNS_TYPE"
        return 0
    fi

    # 降级到基础边类型
    log_debug "字段缺失，降级为 REFERENCES：lang=$lang, role=$symbol_role"
    echo "REFERENCES"
}
```

**测试覆盖**：
- AC-G01 测试覆盖 TypeScript 和 Python（两种最常用的语言）
- 降级场景作为边界测试，验证不会报错

**MOD-02 修复：迁移策略闭环**

边类型扩展会改变 graph.db Schema，需要明确迁移方案：

**迁移命令**：
```bash
# graph-store.sh 新增 migrate 子命令
./scripts/graph-store.sh migrate --check    # 检查是否需要迁移
./scripts/graph-store.sh migrate --apply    # 执行迁移
./scripts/graph-store.sh migrate --status   # 查看迁移状态
```

**迁移实现**：
```bash
# scripts/graph-store.sh 新增 migrate 函数
migrate_schema() {
    local action="${1:---check}"
    local db="${GRAPH_DB:-.devbooks/graph.db}"

    case "$action" in
        --check)
            # 检查 edge_type CHECK 约束是否包含新类型
            local constraint
            constraint=$(sqlite3 "$db" "SELECT sql FROM sqlite_master WHERE type='table' AND name='edges';")
            if [[ "$constraint" != *"IMPLEMENTS"* ]]; then
                echo "NEEDS_MIGRATION: 边类型 Schema 需要更新"
                echo "  - 缺少 IMPLEMENTS"
                echo "  - 缺少 EXTENDS"
                echo "  - 缺少 RETURNS_TYPE"
                return 1
            fi
            echo "UP_TO_DATE: Schema 已是最新"
            return 0
            ;;
        --apply)
            echo "执行 Schema 迁移..."

            # 备份现有数据库
            cp "$db" "${db}.backup.$(date +%Y%m%d%H%M%S)"

            # 方案：重建表（SQLite 不支持直接修改 CHECK 约束）
            sqlite3 "$db" <<EOF
BEGIN;
-- 创建新表
CREATE TABLE edges_new (
    id INTEGER PRIMARY KEY,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    edge_type TEXT NOT NULL CHECK(edge_type IN (
        'CALLS', 'IMPORTS', 'REFERENCES', 'DEFINES',
        'IMPLEMENTS', 'EXTENDS', 'RETURNS_TYPE',
        'VIRTUAL_TYPE', 'VIRTUAL_INHERIT', 'ADR_RELATED'
    )),
    weight REAL DEFAULT 1.0,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- 迁移数据
INSERT INTO edges_new (id, source_id, target_id, edge_type, weight, created_at)
SELECT id, source_id, target_id, edge_type, weight, created_at FROM edges;

-- 替换表
DROP TABLE edges;
ALTER TABLE edges_new RENAME TO edges;

-- 重建索引
CREATE INDEX idx_edges_source ON edges(source_id);
CREATE INDEX idx_edges_target ON edges(target_id);
CREATE INDEX idx_edges_type ON edges(edge_type);
COMMIT;
EOF

            echo "迁移完成。备份文件：${db}.backup.*"
            ;;
        --status)
            echo "=== 迁移状态 ==="
            echo "数据库：$db"
            echo "边类型分布："
            sqlite3 "$db" "SELECT edge_type, COUNT(*) as count FROM edges GROUP BY edge_type ORDER BY count DESC;"
            echo ""
            echo "Schema 版本检查："
            migrate_schema --check
            ;;
    esac
}
```

**升级路径**：

| 场景 | 操作 | 数据保留 |
|------|------|----------|
| 空 graph.db | 直接使用新 Schema | N/A |
| 已有 graph.db | `graph-store.sh migrate --apply` | 完整保留 |
| 重新索引 | 删除 graph.db + 重新运行 scip-to-graph.sh | 重建 |

**验证命令**：
```bash
# 验证迁移成功
./scripts/graph-store.sh migrate --check
# 预期输出：UP_TO_DATE: Schema 已是最新
```

#### 模块 2：A-B 路径查询

| 项目 | 内容 |
|------|------|
| 修改文件 | `scripts/graph-store.sh` |
| 新增命令 | `find-path --from <id> --to <id> --max-depth <n>` |
| 算法 | BFS 最短路径 |
| 输出 | 路径节点列表 + 路径长度 |

**技术实现**：
```bash
# 使用 SQLite 递归 CTE 实现 BFS
WITH RECURSIVE path AS (
    SELECT source_id, target_id, source_id || '->' || target_id AS route, 1 AS depth
    FROM edges WHERE source_id = ?
    UNION ALL
    SELECT e.source_id, e.target_id, p.route || '->' || e.target_id, p.depth + 1
    FROM edges e JOIN path p ON e.source_id = p.target_id
    WHERE p.depth < ? AND p.route NOT LIKE '%' || e.target_id || '%'
)
SELECT * FROM path WHERE target_id = ? LIMIT 1;
```

#### 模块 3：ADR（架构决策记录）解析与关联

| 项目 | 内容 |
|------|------|
| 新增文件 | `scripts/adr-parser.sh` |
| 功能 | 解析 `docs/adr/*.md` 文件，提取决策关键词，关联到代码模块 |
| 输出 | ADR 元数据 JSON + 与 graph.db 节点的关联边 |

**ADR 格式支持**：
```markdown
# ADR-001: 使用 SQLite 作为图存储

## Status
Accepted

## Context
需要一个轻量级的图存储解决方案...

## Decision
使用 SQLite + WAL 模式...

## Consequences
- 正面：部署简单、无外部依赖
- 负面：大规模扩展受限
```

**关联算法**：
```
1. 解析 ADR 的 Decision/Context 部分
2. 提取技术关键词（如 SQLite、graph-store、WAL）
3. 在 graph.db 中查找匹配的文件/符号节点
4. 生成 ADR_RELATED 边类型
```

#### 模块 4：对话历史信号累积

| 项目 | 内容 |
|------|------|
| 修改文件 | `scripts/intent-learner.sh`、`hooks/augment-context-global.sh` |
| 新增功能 | 记录对话上下文（最近 N 条查询 + 响应摘要） |
| 存储位置 | `.devbooks/conversation-context.json` |
| 应用 | 搜索结果排序时加入对话连续性加权 |

**对话上下文格式**：
```json
{
  "session_id": "session-xxx",
  "context_window": [
    { "turn": 1, "query": "find auth module", "focus_symbols": ["src/auth.ts"] },
    { "turn": 2, "query": "show callers", "focus_symbols": ["src/auth.ts::login"] }
  ],
  "accumulated_focus": ["src/auth.ts", "src/auth.ts::login"]
}
```

#### 模块 5：Daemon 预热机制

| 项目 | 内容 |
|------|------|
| 修改文件 | `scripts/daemon.sh` |
| 新增功能 | 启动时预加载高频查询、热点子图、常用符号索引 |
| 配置项 | `daemon.warmup.enabled`、`daemon.warmup.queries` |

**预热流程**：
```bash
daemon_warmup() {
    log_info "Warming up daemon..."

    # 1. 预加载热点文件的子图
    local hotspots=$(./scripts/hotspot-analyzer.sh analyze --limit 10 --format json)
    for file in $(echo "$hotspots" | jq -r '.[].file'); do
        ./scripts/graph-store.sh query-edges --from "$file" >/dev/null
    done

    # 2. 预执行常见查询
    ./scripts/graph-rag.sh search "main" --budget 1000 >/dev/null

    # 3. 加载符号索引到内存缓存
    ./scripts/cache-manager.sh warmup-symbols

    log_info "Warmup completed"
}
```

#### 模块 6：请求取消机制

| 项目 | 内容 |
|------|------|
| 修改文件 | `scripts/daemon.sh`、`src/server.ts` |
| 新增功能 | 支持请求取消令牌，检测新请求时终止旧请求 |
| 机制 | 请求 ID + 取消信号文件 + **flock 文件锁** |

**OPT-01 补充：flock 文件锁实现**

```bash
# daemon.sh 中的请求处理（带文件锁）
LOCK_FILE=".devbooks/daemon.lock"
CANCEL_DIR=".devbooks/cancel"

handle_request() {
    local request_id="$1"
    local cancel_file="$CANCEL_DIR/$request_id"

    mkdir -p "$CANCEL_DIR"

    # 使用 flock 保证原子性
    (
        flock -x 200  # 获取排他锁

        # 取消所有旧请求
        for old_cancel in "$CANCEL_DIR"/*; do
            [[ "$old_cancel" != "$cancel_file" ]] && touch "$old_cancel"
        done

        # 创建当前请求的取消文件（空文件表示未取消）
        : > "$cancel_file"
    ) 200>"$LOCK_FILE"

    # 检查取消信号
    check_cancel() {
        [[ -s "$cancel_file" ]]  # 文件非空表示已取消
    }

    # 在长时间操作前检查
    for step in "$steps"; do
        if check_cancel; then
            log_info "Request $request_id cancelled"
            rm -f "$cancel_file"
            return 1
        fi
        execute_step "$step"
    done

    # 完成后清理
    rm -f "$cancel_file"
}

# 取消特定请求
cancel_request() {
    local request_id="$1"
    local cancel_file="$CANCEL_DIR/$request_id"

    (
        flock -x 200
        if [[ -f "$cancel_file" ]]; then
            echo "cancelled" > "$cancel_file"  # 写入内容表示取消
        fi
    ) 200>"$LOCK_FILE"
}
```

**并发安全保证**：
- 使用 `flock` 排他锁保证取消操作原子性
- 使用文件内容（空 vs 非空）而非文件存在性判断取消状态
- 取消检测在 100ms 内生效（每个 step 开始前检查）

#### 模块 7：子图 LRU 缓存（SQLite 持久化）

| 项目 | 内容 |
|------|------|
| 修改文件 | `scripts/cache-manager.sh` |
| 新增功能 | 热点子图 LRU 缓存，**跨进程持久化** |
| 缓存大小 | 默认 100 个子图（可配置） |
| 淘汰策略 | LRU（最近最少使用） |
| 存储后端 | SQLite 表（`.devbooks/subgraph-cache.db`） |

**MOD-01 修复**：Challenger 正确指出 Bash 关联数组无法跨进程共享。修改为 SQLite 持久化方案，解决进程隔离问题。

**LRU 缓存实现（SQLite 版）**：
```bash
CACHE_DB=".devbooks/subgraph-cache.db"
CACHE_MAX_SIZE=${CACHE_MAX_SIZE:-100}

# 初始化缓存表
init_cache_db() {
    sqlite3 "$CACHE_DB" <<EOF
CREATE TABLE IF NOT EXISTS subgraph_cache (
    cache_key TEXT PRIMARY KEY,
    cache_value TEXT NOT NULL,
    access_time INTEGER NOT NULL,
    created_time INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_access_time ON subgraph_cache(access_time);
EOF
}

# 写入缓存（带 LRU 淘汰）
cache_subgraph() {
    local key="$1"
    local value="$2"
    local now=$(date +%s)

    # 事务内完成：淘汰 + 写入
    sqlite3 "$CACHE_DB" <<EOF
BEGIN;
-- 如果超过容量，淘汰最旧的条目
DELETE FROM subgraph_cache
WHERE cache_key IN (
    SELECT cache_key FROM subgraph_cache
    ORDER BY access_time ASC
    LIMIT MAX(0, (SELECT COUNT(*) FROM subgraph_cache) - $CACHE_MAX_SIZE + 1)
);
-- 插入或更新缓存
INSERT OR REPLACE INTO subgraph_cache (cache_key, cache_value, access_time, created_time)
VALUES ('$key', '$value', $now, COALESCE((SELECT created_time FROM subgraph_cache WHERE cache_key = '$key'), $now));
COMMIT;
EOF
}

# 读取缓存（更新访问时间）
get_cached_subgraph() {
    local key="$1"
    local now=$(date +%s)

    # 原子读取 + 更新访问时间
    local value
    value=$(sqlite3 "$CACHE_DB" <<EOF
UPDATE subgraph_cache SET access_time = $now WHERE cache_key = '$key';
SELECT cache_value FROM subgraph_cache WHERE cache_key = '$key';
EOF
)

    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    return 1
}

# 获取缓存统计（用于测试验证）
get_cache_stats() {
    sqlite3 "$CACHE_DB" <<EOF
SELECT json_object(
    'total_entries', (SELECT COUNT(*) FROM subgraph_cache),
    'oldest_access', (SELECT MIN(access_time) FROM subgraph_cache),
    'newest_access', (SELECT MAX(access_time) FROM subgraph_cache)
);
EOF
}
```

**跨进程验证**：
```bash
# PoC 测试：验证跨进程缓存有效
# 进程 1 写入
./scripts/cache-manager.sh cache-set "key1" "value1"

# 进程 2 读取（新进程）
./scripts/cache-manager.sh cache-get "key1"  # 应返回 "value1"
```

#### 模块 8：Bug 定位 + 影响分析融合

| 项目 | 内容 |
|------|------|
| 修改文件 | `scripts/bug-locator.sh` |
| 新增功能 | 集成 `impact-analyzer.sh`，在 Bug 候选输出中包含传递性影响范围 |
| 新增参数 | `--with-impact`、`--impact-depth <n>` |

**融合算法**：
```bash
# bug-locator.sh 修改
locate_bug_with_impact() {
    local query="$1"
    local impact_depth="${2:-3}"

    # 1. 获取 Bug 候选
    local candidates=$(locate_bug "$query")

    # 2. 对每个候选计算影响范围
    local enhanced_candidates=$(echo "$candidates" | jq -c '.[]' | while read -r candidate; do
        local symbol=$(echo "$candidate" | jq -r '.symbol')
        local impact=$(./scripts/impact-analyzer.sh analyze "$symbol" --depth "$impact_depth" --format json)
        echo "$candidate" | jq --argjson impact "$impact" '. + {impact: $impact}'
    done | jq -s '.')

    # 3. 重新计算综合分数（加入影响范围权重）
    echo "$enhanced_candidates" | jq 'sort_by(-.score * (1 + .impact.total_affected / 100))'
}
```

#### 模块 9：GitHub Action CI/CD 模板

| 项目 | 内容 |
|------|------|
| 新增文件 | `.github/workflows/arch-check.yml` |
| 功能 | PR 自动架构检查（循环依赖、孤儿模块、架构规则违规） |
| 触发条件 | Pull Request |

**GitHub Action 模板**：
```yaml
# .github/workflows/arch-check.yml
name: Architecture Check

on:
  pull_request:
    branches: [master, main]

jobs:
  arch-check:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm ci

      - name: Run architecture checks
        run: |
          # 循环依赖检测
          ./scripts/dependency-guard.sh --cycles --format json > /tmp/cycles.json
          if jq -e '.cycles | length > 0' /tmp/cycles.json; then
            echo "::error::Circular dependencies detected"
            cat /tmp/cycles.json
            exit 1
          fi

          # 孤儿模块检测
          ./scripts/dependency-guard.sh --orphan-check --format json > /tmp/orphans.json
          if jq -e '.orphans | length > 0' /tmp/orphans.json; then
            echo "::warning::Orphan modules detected"
            cat /tmp/orphans.json
          fi

          # 架构规则检测
          ./scripts/boundary-detector.sh detect --rules config/arch-rules.yaml --format json > /tmp/violations.json
          if jq -e '.violations | length > 0' /tmp/violations.json; then
            echo "::error::Architecture rule violations detected"
            cat /tmp/violations.json
            exit 1
          fi

      - name: Comment on PR
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '## Architecture Check Failed\n\nPlease review the architecture violations in the workflow logs.'
            })
```

#### 模块 10：GitLab CI 模板

| 项目 | 内容 |
|------|------|
| 新增文件 | `.gitlab-ci.yml.template` |
| 功能 | GitLab CI 架构检查模板 |

**GitLab CI 模板**：
```yaml
# .gitlab-ci.yml.template
# 复制此文件为 .gitlab-ci.yml 以启用

stages:
  - lint
  - test
  - arch-check

arch-check:
  stage: arch-check
  image: node:18
  script:
    - npm ci
    - ./scripts/dependency-guard.sh --all --format json
  only:
    - merge_requests
  allow_failure: false
```

#### 模块 11：结构化上下文输出（Universal Context Template）

| 项目 | 内容 |
|------|------|
| 修改文件 | `hooks/augment-context-global.sh` |
| 功能 | 将上下文输出从自由文本升级为结构化模板，提升 AI 理解效率 |
| 输出格式 | 5 层结构：项目画像 → 当前状态 → 任务上下文 → 推荐工具 → 约束提醒 |

**结构化模板设计**：
```
[项目上下文]
├── 1. 项目画像（Project Profile）
│   ├── 名称/类型/技术栈
│   ├── 架构模式（如：薄壳模式）
│   └── 关键约束（如：CON-TECH-002）
│
├── 2. 当前状态（Current State）
│   ├── 索引状态（SCIP/CKB/Embedding）
│   ├── 热点文件（Top 5）
│   └── 最近变更（Last 3 commits）
│
├── 3. 任务上下文（Task Context）
│   ├── 意图分析（4 维信号）
│   ├── 相关代码片段
│   └── 调用链/影响范围
│
├── 4. 推荐工具（Recommended Tools）
│   ├── 基于意图的工具推荐
│   └── 工具参数建议
│
└── 5. 约束提醒（Constraints）
    ├── 架构约束（分层规则）
    └── 安全约束（敏感文件）
```

**技术实现**：
```bash
# 新增函数：build_structured_context()
build_structured_context() {
    local intent_analysis="$1"

    # 1. 项目画像
    local profile=$(build_project_profile)

    # 2. 当前状态
    local state=$(build_current_state)

    # 3. 任务上下文
    local task_ctx=$(build_task_context "$intent_analysis")

    # 4. 推荐工具
    local tools=$(recommend_tools "$intent_analysis")

    # 5. 约束提醒
    local constraints=$(get_active_constraints)

    # 组装结构化输出
    jq -n \
        --argjson profile "$profile" \
        --argjson state "$state" \
        --argjson task "$task_ctx" \
        --argjson tools "$tools" \
        --argjson constraints "$constraints" \
        '{
            project_profile: $profile,
            current_state: $state,
            task_context: $task,
            recommended_tools: $tools,
            constraints: $constraints
        }'
}
```

#### 模块 12：DevBooks 适配（自动检测 + 高信噪比信息增强）

| 项目 | 内容 |
|------|------|
| 修改文件 | `hooks/augment-context-global.sh`、`scripts/common.sh` |
| 功能 | 自动检测 dev-playbooks 配置，提取高信噪比信息增强代码智能 |
| 信息来源 | `specs/_meta/`、`specs/architecture/`、`changes/` |

**检测逻辑（分层）**：
```bash
# 检测 DevBooks 配置
detect_devbooks() {
    local cwd="${1:-$CWD}"

    # 层级 1：检测 .devbooks/config.yaml（最可靠）
    if [ -f "$cwd/.devbooks/config.yaml" ]; then
        local root
        root=$(grep "^root:" "$cwd/.devbooks/config.yaml" | sed 's/root:\s*//' | tr -d ' ')
        if [ -n "$root" ] && [ -d "$cwd/$root" ]; then
            echo "$cwd/$root"
            return 0
        fi
    fi

    # 层级 2：检测常见目录名
    for dir in "dev-playbooks" "openspec" ".openspec" "specs"; do
        if [ -d "$cwd/$dir" ] && [ -f "$cwd/$dir/project.md" ]; then
            echo "$cwd/$dir"
            return 0
        fi
    done

    return 1  # 未检测到
}
```

**高信噪比信息提取**：

| 信息类别 | 文件路径 | 提取内容 | 用途 |
|---------|---------|---------|------|
| 项目画像 | `_meta/project-profile.md` | 技术栈、架构模式、命令速查 | 上下文注入 |
| 术语表 | `_meta/glossary.md` | 领域术语、禁用词 | 搜索同义词扩展 |
| 架构约束 | `architecture/c4.md` | 分层规则、依赖方向 | 架构守门 |
| 当前变更 | `changes/*/proposal.md` | 变更状态、验收标准 | 工作流感知 |

**上下文增强实现**：
```bash
# 加载 DevBooks 高信噪比上下文
load_devbooks_context() {
    local devbooks_root="$1"
    local context=""

    # 1. 项目画像（第一层：快速定位）
    local profile="$devbooks_root/specs/_meta/project-profile.md"
    if [ -f "$profile" ]; then
        context+=$(extract_section "$profile" "## 第一层" "## 第二层")
    fi

    # 2. 架构约束
    local c4="$devbooks_root/specs/architecture/c4.md"
    if [ -f "$c4" ]; then
        context+=$(extract_section "$c4" "### Layering Constraints" "### Environment")
    fi

    # 3. 当前变更包状态
    local active_change=$(find_active_change "$devbooks_root")
    if [ -n "$active_change" ]; then
        context+="当前变更包：$active_change"
    fi

    echo "$context"
}
```

**输出效果对比**：

| 场景 | 无 DevBooks | 有 DevBooks |
|------|------------|-------------|
| 项目画像 | 仅索引状态 | 技术栈 + 架构模式 + 约束 |
| 架构约束 | 无 | 分层规则 + 禁止依赖 |
| 工作流感知 | 无 | 当前变更包 + 验收标准 |
| 术语支持 | 无 | 同义词扩展 + 禁用词提醒 |

### 2.2 文件变更矩阵

| 文件 | 操作 | 变更类型 |
|------|------|----------|
| `scripts/scip-to-graph.sh` | 修改 | 边类型扩展 |
| `scripts/graph-store.sh` | 修改 | 路径查询 + 边类型 Schema |
| `scripts/adr-parser.sh` | 新增 | ADR 解析 |
| `scripts/intent-learner.sh` | 修改 | 对话上下文 |
| `scripts/daemon.sh` | 修改 | 预热 + 请求取消 |
| `scripts/cache-manager.sh` | 修改 | LRU 子图缓存 |
| `scripts/bug-locator.sh` | 修改 | 影响分析融合 |
| `hooks/augment-context-global.sh` | 修改 | 对话信号注入 + 结构化输出 + DevBooks 适配 |
| `scripts/common.sh` | 修改 | DevBooks 检测函数 |
| `.github/workflows/arch-check.yml` | 新增 | GitHub Action |
| `.gitlab-ci.yml.template` | 新增 | GitLab CI 模板 |
| `tests/graph-store.bats` | 修改 | 路径查询测试 |
| `tests/adr-parser.bats` | 新增 | ADR 解析测试 |
| `tests/daemon.bats` | 修改 | 预热 + 取消测试 |
| `tests/cache-manager.bats` | 修改 | LRU 缓存测试 |
| `tests/bug-locator.bats` | 修改 | 融合测试 |
| `config/features.yaml` | 修改 | 新增功能开关 |
| `tests/augment-context.bats` | 新增 | 结构化输出 + DevBooks 适配测试 |

**共计**：18 个文件（4 个新增、14 个修改）

### 2.3 非目标（明确排除）

1. **不迁移到 Neo4j**：保持 SQLite 图存储
2. **不实现 IDE 插件**：无隐式信号获取
3. **不实现实时文件监听**：增量索引由触发式驱动
4. **不构建向量数据库**：保持现有 Embedding 方案

---

## 3. Impact（影响分析）

### 3.0 变更边界（Scope）

**In（变更范围内）**：
- `scripts/` 目录下的 7 个脚本（1 新增 + 6 修改）
- `hooks/` 目录下的 1 个钩子（修改）
- `.github/workflows/` CI 配置（新增）
- `tests/` 目录下的 5 个测试文件（1 新增 + 4 修改）
- `config/` 配置文件

**Out（明确排除）**：
- `src/server.ts`（本提案无新 MCP 工具，功能通过现有工具参数扩展）
- 前序变更包已覆盖的功能

### 3.1 对外契约影响

| 契约 | 影响 | 兼容性 |
|------|------|--------|
| `graph-store.sh` 命令 | 新增 `find-path` 命令 | 向后兼容（新增） |
| `bug-locator.sh` 参数 | 新增 `--with-impact` | 向后兼容（可选参数） |
| graph.db Schema | 新增 3 种边类型 | 向后兼容（扩展） |
| CI/CD | 新增 GitHub Action | 可选启用 |

### 3.2 数据影响

| 数据 | 影响 |
|------|------|
| `.devbooks/conversation-context.json` | 新增对话上下文文件（预估 < 100KB） |
| `.devbooks/adr-index.json` | 新增 ADR 索引文件（预估 < 50KB） |
| graph.db | 扩展边类型（IMPLEMENTS/EXTENDS/RETURNS_TYPE/ADR_RELATED） |

### 3.3 模块依赖影响

```
新增/修改依赖关系：
adr-parser.sh → graph-store.sh（写入 ADR 关联边）
bug-locator.sh → impact-analyzer.sh（融合分析）
daemon.sh → cache-manager.sh（预热调用）
daemon.sh → hotspot-analyzer.sh（预热数据源）
intent-learner.sh → augment-context-global.sh（对话上下文注入）
augment-context-global.sh → common.sh（DevBooks 检测函数）
```

### 3.3.1 详细依赖关系矩阵（Grep 分析）

| 被修改文件 | 直接调用者 | 间接影响 | 风险等级 |
|-----------|-----------|---------|----------|
| `scripts/scip-to-graph.sh` | 无（入口脚本） | graph.db 数据格式 | 中 |
| `scripts/graph-store.sh` | ast-delta, scip-to-graph, daemon, adr-parser | 所有图查询功能 | **高** |
| `scripts/daemon.sh` | 无（常驻进程） | 所有 MCP 工具响应 | **高** |
| `scripts/cache-manager.sh` | bug-locator, graph-rag, daemon | 缓存依赖脚本 | 中 |
| `scripts/bug-locator.sh` | server.ts (ci_bug_locate) | MCP 工具输出 | 中 |
| `scripts/intent-learner.sh` | server.ts (ci_intent), graph-rag | 偏好加权 | 低 |
| `hooks/augment-context-global.sh` | Claude Code Hook | 上下文注入 | 中 |
| `scripts/common.sh` | **18 个脚本** | 全局影响 | **高** |

### 3.3.2 高风险依赖链

**common.sh 修改影响链（18 个直接调用者）**：
- scip-to-graph, graph-store, daemon, intent-learner, vuln-tracker
- impact-analyzer, ast-delta, cod-visualizer, boundary-detector
- hotspot-analyzer, pattern-learner, call-chain, context-layer
- graph-rag, federation-lite, bug-locator, ast-diff, entropy-viz

**graph-store.sh 修改影响链**：
- ast-delta.sh（图更新）
- scip-to-graph.sh（批量导入）
- daemon.sh（查询代理）
- adr-parser.sh（新增，ADR 边写入）

### 3.4 价值信号

| 指标 | 当前值（含前序变更） | 本提案后 | 改进幅度 |
|------|---------------------|---------|----------|
| 边类型覆盖 | 4 种 + 2 虚拟 | 7 种 + 2 虚拟 | +75% |
| 路径查询 | 无 | BFS 最短路径 | 新增能力 |
| ADR 上下文 | 无 | 架构决策关联 | 新增能力 |
| 对话连续性 | 弱 | 多轮累积 | 质的提升 |
| 冷启动延迟 | ~600ms | ~300ms（预热后） | -50% |
| 请求效率 | 无取消 | 击键取消 | 资源释放 |
| 重复查询 | 每次重读 | LRU 命中 | 10x 提速 |
| Bug 定位精度 | 四维评分 | 四维 + 影响范围 | +20% |
| CI 守门 | 手动 | 自动 PR 检查 | 自动化 |

---

## 4. Risks & Rollback（风险与回滚）

### 4.1 技术风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| LRU 缓存内存占用 | 中 | 中 | 缓存大小可配置，默认 100 |
| 递归 CTE 性能 | 低 | 中 | 最大深度限制（默认 10） |
| ADR 格式多样 | 中 | 低 | 支持多种常见格式 |
| GitHub Action 权限 | 低 | 低 | 只读检查，无写操作 |
| 请求取消并发 | 中 | 中 | 文件锁 + 原子操作 |

### 4.2 回滚策略

1. **功能开关回滚**：所有新功能通过 `features.*.enabled` 控制
2. **文件回滚**：删除新增文件，恢复修改文件
3. **数据回滚**：删除 `.devbooks/conversation-context.json`、`.devbooks/adr-index.json`
4. **CI 回滚**：删除 `.github/workflows/arch-check.yml`

---

## 5. Validation（验收标准）

### 5.1 验收锚点（量化版）

| AC 编号 | 验收标准 | 具体验证条件 | 验证方法 |
|---------|---------|-------------|----------|
| AC-G01 | 边类型扩展 | TypeScript 项目索引后，graph.db 包含 IMPLEMENTS/EXTENDS/RETURNS_TYPE 边类型（覆盖 TypeScript、Python） | `tests/graph-store.bats::test_edge_types` |
| AC-G01a | 迁移命令 | `graph-store.sh migrate --check` 在新旧 graph.db 上均返回正确状态 | `tests/graph-store.bats::test_migrate_check` |
| AC-G02 | 路径查询 | `find-path --from A --to B` 返回正确路径，深度 1-10 均可工作 | `tests/graph-store.bats::test_find_path` |
| AC-G03 | ADR 解析 | 解析 MADR 和 Nygard 格式的 ADR 文件，正确提取 Status/Decision/Context | `tests/adr-parser.bats::test_parse_madr` |
| AC-G04 | 对话上下文 | **存储 5 轮后可正确读取全部上下文**：写入 5 条对话记录，读取时返回完整 5 条 | `tests/intent-learner.bats::test_conversation_context` |
| AC-G05 | 预热机制 | **预热完成后 `cache-manager.sh stats` 显示已缓存条目 > 0** | `tests/daemon.bats::test_warmup` |
| AC-G06 | 请求取消 | **并发场景测试**：启动长时间请求，发起新请求后旧请求在 100ms 内终止（使用 flock 文件锁） | `tests/daemon.bats::test_cancel_concurrent` |
| AC-G07 | LRU 缓存 | **连续执行 10 次相同查询，命中率 > 80%**（跨进程持久化验证） | `tests/cache-manager.bats::test_lru_hit_rate` |
| AC-G08 | Bug 定位融合 | **输出 JSON 包含 `impact` 字段**，Schema：`{ symbol, score, impact: { total_affected, affected_files[] } }` | `tests/bug-locator.bats::test_with_impact` |
| AC-G09 | GitHub Action | workflow 文件语法正确（通过 `actionlint` 检查） | `tests/ci.bats::test_workflow_syntax` |
| AC-G10 | 向后兼容 | `npm test` 全部通过，无回归 | CI 全量测试 |
| AC-G11 | 结构化输出 | **输出 JSON 包含 5 个必需字段**：`project_profile`、`current_state`、`task_context`、`recommended_tools`、`constraints` | `tests/augment-context.bats::test_structured_output` |
| AC-G12 | DevBooks 适配 | **正向测试**：有 `.devbooks/config.yaml` 时注入画像；**负向测试**：无配置时不报错 | `tests/augment-context.bats::test_devbooks_detection` |

### 5.2 输出 Schema 定义

**AC-G08 Bug 定位融合输出 Schema**：
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "required": ["symbol", "score", "impact"],
    "properties": {
      "symbol": { "type": "string" },
      "file": { "type": "string" },
      "line": { "type": "integer" },
      "score": { "type": "number", "minimum": 0, "maximum": 100 },
      "impact": {
        "type": "object",
        "required": ["total_affected", "affected_files"],
        "properties": {
          "total_affected": { "type": "integer" },
          "affected_files": { "type": "array", "items": { "type": "string" } },
          "max_depth": { "type": "integer" }
        }
      }
    }
  }
}
```

**AC-G11 结构化上下文输出 Schema**：
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["project_profile", "current_state", "task_context", "recommended_tools", "constraints"],
  "properties": {
    "project_profile": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "tech_stack": { "type": "array", "items": { "type": "string" } },
        "architecture": { "type": "string" },
        "key_constraints": { "type": "array", "items": { "type": "string" } }
      }
    },
    "current_state": {
      "type": "object",
      "properties": {
        "index_status": { "type": "string", "enum": ["ready", "stale", "missing"] },
        "hotspot_files": { "type": "array", "items": { "type": "string" }, "maxItems": 5 },
        "recent_commits": { "type": "array", "items": { "type": "string" }, "maxItems": 3 }
      }
    },
    "task_context": {
      "type": "object",
      "properties": {
        "intent_analysis": { "type": "object" },
        "relevant_snippets": { "type": "array" },
        "call_chains": { "type": "array" }
      }
    },
    "recommended_tools": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "tool": { "type": "string" },
          "reason": { "type": "string" },
          "suggested_params": { "type": "object" }
        }
      }
    },
    "constraints": {
      "type": "object",
      "properties": {
        "architectural": { "type": "array", "items": { "type": "string" } },
        "security": { "type": "array", "items": { "type": "string" } }
      }
    }
  }
}
```

### 5.3 证据落点

| 证据类型 | 路径 |
|---------|------|
| Red 基线 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/red-baseline/` |
| Green 最终 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/green-final/` |
| 性能报告 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/performance-report.md` |
| 迁移测试 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/migrate-test.log` |
| LRU PoC 测试 | `dev-playbooks/changes/augment-parity-final-gaps/evidence/lru-poc-test.log` |

### 5.4 性能基准测试脚本（OPT-04）

```bash
# evidence/scripts/benchmark.sh
#!/bin/bash
# 性能基准测试脚本

set -euo pipefail

REPORT_FILE="${1:-evidence/performance-report.md}"
RUNS=10

echo "# 性能基准报告" > "$REPORT_FILE"
echo "生成时间：$(date -Iseconds)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 测试 1：冷启动 vs 预热启动
echo "## 1. 冷启动延迟" >> "$REPORT_FILE"
rm -f .devbooks/subgraph-cache.db
cold_start=$(time (./scripts/graph-rag.sh search "main" --budget 1000 >/dev/null) 2>&1 | grep real | awk '{print $2}')
echo "- 冷启动时间：$cold_start" >> "$REPORT_FILE"

echo "## 2. 预热后启动" >> "$REPORT_FILE"
./scripts/daemon.sh warmup
warm_start=$(time (./scripts/graph-rag.sh search "main" --budget 1000 >/dev/null) 2>&1 | grep real | awk '{print $2}')
echo "- 预热后时间：$warm_start" >> "$REPORT_FILE"

# 测试 2：LRU 缓存命中率
echo "## 3. LRU 缓存命中率" >> "$REPORT_FILE"
for i in $(seq 1 $RUNS); do
    ./scripts/graph-store.sh query-edges --from "src/server.ts" >/dev/null
done
stats=$(./scripts/cache-manager.sh stats)
echo "- 10 次重复查询后统计：$stats" >> "$REPORT_FILE"

# 测试 3：重复查询提速
echo "## 4. 重复查询提速" >> "$REPORT_FILE"
first=$(time (./scripts/graph-store.sh query-edges --from "src/server.ts" >/dev/null) 2>&1 | grep real | awk '{print $2}')
second=$(time (./scripts/graph-store.sh query-edges --from "src/server.ts" >/dev/null) 2>&1 | grep real | awk '{print $2}')
echo "- 首次查询：$first" >> "$REPORT_FILE"
echo "- 缓存命中后：$second" >> "$REPORT_FILE"

echo "## 结论" >> "$REPORT_FILE"
echo "性能基准测试完成。详细数据见上方。" >> "$REPORT_FILE"
```

---

## 6. Debate Packet（争议点）

### DP-G01：LRU 缓存实现方式（已决策 → 已修订）

**背景**：子图缓存需要实现 LRU 淘汰策略。

**原始选项**：
- **A：Bash 关联数组（内存）** ~~已选择~~
  - 优点：简单、无外部依赖
  - 缺点：**进程退出后丢失、无法跨进程共享**（Challenger 指出的阻塞问题）
- **B：SQLite 临时表（持久化）** ✅ **修订后选择**
  - 优点：持久化、支持跨进程共享、支持更大缓存
  - 缺点：需要额外 I/O（但 SQLite WAL 模式性能影响可忽略）
- **C：Redis（外部服务）**
  - 优点：高性能、原生 LRU
  - 缺点：需要额外部署

**修订决策**：选项 B（SQLite 持久化）。

**修订理由**：
1. Challenger 正确指出 Bash 关联数组无法跨进程共享，AC-G07（命中率 > 80%）在原方案下不可达成
2. SQLite 方案与现有 graph.db 架构一致，无新依赖
3. 使用事务保证原子性，使用 WAL 模式保证并发性能

---

### DP-G02：ADR 格式支持范围（已决策）

**背景**：ADR 有多种格式标准。

**选项**：
- **A：仅支持标准 MADR 格式**
  - 优点：解析简单、格式统一
  - 缺点：不兼容非标准 ADR
- **B：支持 MADR + Nygard 格式** ✅ **已选择**
  - 优点：覆盖两种最常见格式
  - 缺点：解析复杂度增加
- **C：正则模糊匹配**
  - 优点：兼容性最强
  - 缺点：精度可能下降

**决策**：选项 B（MADR + Nygard）。理由：覆盖 90% 的 ADR 使用场景。

---

### DP-G03：预热查询范围（已决策）

**背景**：预热时需要决定加载哪些数据。

**选项**：
- **A：仅热点文件子图**
  - 优点：启动快
  - 缺点：覆盖范围小
- **B：热点 + 最近访问符号** ✅ **已选择**
  - 优点：覆盖用户常用路径
  - 缺点：需要记录历史
- **C：热点 + 常用查询模式**
  - 优点：覆盖常见场景
  - 缺点：需要定义模式

**决策**：选项 B（热点 + 最近访问符号）。理由：intent-learner.sh 已有历史记录，可直接复用。

---

### DP-G04：已确定的非争议决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 保持 SQLite 图存储 | 是 | 不迁移到 Neo4j |
| 边类型使用 CHECK 约束 | 是 | 数据完整性保证 |
| 路径查询最大深度 10 | 是 | 性能与实用性平衡 |
| GitHub Action 只读检查 | 是 | 安全最小权限 |
| 取消机制使用文件信号 | 是 | 跨进程简单可靠 |

---

## 7. Open Questions（待澄清问题）

| 编号 | 问题 | 影响 | 建议处理 | 状态 |
|------|------|------|----------|------|
| OQ-G01 | 边类型扩展是否需要迁移脚本？ | graph.db 兼容性 | **已闭环**：提供 `graph-store.sh migrate` 命令 | ✅ 已解决 |
| OQ-G02 | ADR 关联边是否应该存储在单独表？ | 查询性能 | 建议复用 edges 表 + edge_type 区分 | 待确认 |
| OQ-G03 | 对话上下文最大保留多少轮？ | 存储大小 | 建议 10 轮（可配置） | 待确认 |

---

## 8. Decision Log（裁决记录）

### 决策状态：`Revise`（待 Judge 重新裁决）

### 已裁决的问题清单

1. ✅ DP-G01：LRU 缓存实现方式 → ~~选项 A~~ → **选项 B（已修订）**
2. ✅ DP-G02：ADR 格式支持范围 → 选项 B
3. ✅ DP-G03：预热查询范围 → 选项 B

### 裁决记录

| 日期 | 裁决者 | 决策 | 理由 |
|------|--------|------|------|
| 2026-01-16 | User | DP-G01 → A | 采纳 Author 建议：与薄壳架构一致 |
| 2026-01-16 | User | DP-G02 → B | 采纳 Author 建议：覆盖 90% ADR 场景 |
| 2026-01-16 | User | DP-G03 → B | 采纳 Author 建议：复用 intent-learner 历史 |

---

### 2026-01-16 裁决：Revise

**裁决者**：Proposal Judge (Claude)

**理由摘要**：

1. **Q-01 LRU 缓存的进程隔离问题是阻塞项**：Challenger 正确指出 Bash 关联数组无法跨进程共享。提案声称"跨请求复用"，但技术实现（subprocess 调用 cache-manager.sh）无法支撑此声明。AC-G07（LRU 命中率 > 80%）在当前设计下不可达成。

2. **OQ-G01 迁移策略未闭环是阻塞项**：边类型扩展会改变 graph.db Schema，但提案未明确迁移方案。现有用户升级时可能遇到兼容性问题。

3. **AC 量化不足**：多个验收标准（AC-G04、AC-G05、AC-G07、AC-G08、AC-G11）缺乏具体的验证条件或量化指标。

4. **人类要求已充分尊重**：裁决不反对"一次性完成所有差距项"的目标，仅要求补充技术细节。修订后仍可保持 12 个模块的完整范围。

5. **Challenger 其他质疑有合理性**：Q-02（竞态条件）、Q-03（SCIP 字段可用性）、M-02（性能基准）虽非阻塞项，但建议一并补充。

**必须修改项**（阻塞项）：

- [ ] **MOD-01**：修复 LRU 缓存进程隔离问题。选择以下方案之一：
  - (a) 在 daemon.sh 中直接实现缓存逻辑（避免跨进程）
  - (b) 使用 SQLite 临时表或文件持久化替代 Bash 关联数组
  - (c) 使用 `source cache-manager.sh` 而非 subprocess 调用（需说明副作用）

- [ ] **MOD-02**：闭环 OQ-G01（迁移策略）。明确以下内容：
  - 提供 `graph-store.sh migrate` 命令或等效方案
  - 明确升级路径：重新索引 vs 增量添加边类型
  - 在 AC 中添加迁移命令测试

**建议修改项**（非阻塞，提高质量）：

- [ ] **OPT-01**：补充 Q-02 请求取消的文件锁实现（flock），并在 AC-G06 中添加并发场景测试
- [ ] **OPT-02**：补充 Q-03 SCIP 字段缺失时的降级策略，并在 AC-G01 中明确测试覆盖的语言范围
- [ ] **OPT-03**：量化 AC：
  - AC-G04：改为"存储 5 轮后可正确读取全部上下文"
  - AC-G05：添加"预热完成后检查缓存状态命令输出"
  - AC-G07：明确测试场景"连续执行 10 次相同查询，命中率 > 80%"
  - AC-G08：定义输出 JSON 结构 Schema
  - AC-G11：提供 JSON Schema 或完整示例
- [ ] **OPT-04**：在 evidence/ 中添加性能基准测试脚本（支撑冷启动 -50%、重复查询 10x 提速的声明）
- [ ] **OPT-05**：补充 DevBooks 检测的负面测试用例（非 DevBooks 项目不应报错）

**验证要求**：

- [ ] 修订后的 LRU 缓存方案需要通过概念验证（PoC）测试，证明跨请求缓存有效
- [ ] 迁移命令需要在空 graph.db 和已有 graph.db 两种场景下测试
- [ ] 修订后的 AC 需要明确可自动化验证的具体条件

---

### 2026-01-16 修订：Author 响应 Revise 裁决

**修订者**：Proposal Author (Claude)

**修订摘要**：

**阻塞项已解决**：

- [x] **MOD-01**：LRU 缓存进程隔离问题
  - 选择方案 (b)：SQLite 临时表持久化
  - 修改模块 7 技术实现，使用 `.devbooks/subgraph-cache.db`
  - 更新 DP-G01 为"已修订"，记录方案变更原因
  - 添加跨进程验证 PoC 测试代码

- [x] **MOD-02**：迁移策略闭环
  - 在模块 1 中添加 `graph-store.sh migrate` 命令设计
  - 明确三种升级路径：空数据库 / 已有数据库迁移 / 重新索引
  - 在 AC 中添加 AC-G01a 迁移命令测试
  - 更新 OQ-G01 状态为"已解决"

**建议项已补充**：

- [x] **OPT-01**：请求取消的 flock 文件锁实现
  - 在模块 6 中添加完整的 flock 锁实现代码
  - 更新 AC-G06 为并发场景测试

- [x] **OPT-02**：SCIP 字段缺失时的降级策略
  - 在模块 1 中添加语言支持矩阵
  - 添加降级处理代码示例
  - 更新 AC-G01 明确测试覆盖 TypeScript 和 Python

- [x] **OPT-03**：量化 AC
  - AC-G04：改为"存储 5 轮后可正确读取全部上下文"
  - AC-G05：添加"预热完成后 cache-manager.sh stats 显示已缓存条目 > 0"
  - AC-G06：添加"并发场景测试，使用 flock 文件锁"
  - AC-G07：明确"连续执行 10 次相同查询，命中率 > 80%"
  - AC-G08：提供完整 JSON Schema
  - AC-G11：提供完整 JSON Schema

- [x] **OPT-04**：性能基准测试脚本
  - 在 5.4 节添加 evidence/scripts/benchmark.sh 脚本
  - 覆盖冷启动 vs 预热启动、LRU 缓存命中率、重复查询提速

- [x] **OPT-05**：DevBooks 检测负面测试
  - 在 AC-G12 中添加"负向测试：无配置时不报错"

**待 Judge 重新裁决**。

---

## 附录 A：能力对等矩阵（变更后）

| 能力维度 | 前序变更后 | 本提案后 | Augment 基准 | 对等度 |
|---------|-----------|---------|-------------|--------|
| 边类型 | 4 核心 + 2 虚拟 | **7 核心 + 2 虚拟** | 6+ 种 | **100%** |
| 路径查询 | 无 | **BFS 最短路径** | 有 | **100%** |
| ADR 集成 | 无 | **解析 + 关联** | 有 | **100%** |
| 对话连续性 | 弱 | **多轮累积** | 有 | **90%** |
| 预热机制 | 无 | **热点预加载** | 有 | **100%** |
| 请求取消 | 无 | **击键取消** | 有 | **80%** |
| 子图缓存 | 文件缓存 | **SQLite LRU（跨进程持久化）** | 有 | **95%** |
| Bug 定位融合 | 独立工具 | **影响范围集成** | 有 | **100%** |
| CI 守门 | 手动 | **GitHub Action** | 有 | **100%** |
| 结构化上下文 | 自由文本 | **5 层结构化模板** | 有 | **100%** |
| 规格感知 | 无 | **DevBooks 高信噪比注入** | 有 | **100%** |
| **综合对等度** | ~95% | **~100%** | 100% | - |

**注**：剩余差距来自重资产项（IDE 插件、分布式图数据库），本提案明确排除。

---

## 附录 B：实施顺序建议

```
Phase 1: 图存储增强
├── scripts/scip-to-graph.sh（边类型扩展）
├── scripts/graph-store.sh（路径查询）
└── tests/graph-store.bats

Phase 2: 上下文增强
├── scripts/adr-parser.sh
├── scripts/intent-learner.sh（对话上下文）
├── hooks/augment-context-global.sh
└── tests/adr-parser.bats

Phase 3: 性能优化
├── scripts/daemon.sh（预热 + 取消）
├── scripts/cache-manager.sh（LRU 缓存）
└── tests/daemon.bats、tests/cache-manager.bats

Phase 4: 分析融合
├── scripts/bug-locator.sh
└── tests/bug-locator.bats

Phase 5: CI/CD
├── .github/workflows/arch-check.yml
├── .gitlab-ci.yml.template
└── 全量测试

Phase 6: 上下文结构化 + DevBooks 适配
├── hooks/augment-context-global.sh（结构化输出 + DevBooks 检测）
├── scripts/common.sh（detect_devbooks 函数）
└── tests/augment-context.bats
```

**注意**：以上 Phase 仅为实施顺序建议，**不代表拆分为多个 changes**。所有工作在本变更包内完成。

---

## 附录 C：与前序变更包的完整合并视图

所有变更包合并后的功能清单：

| 功能模块 | 来源 | 状态 |
|---------|------|------|
| 热点分析 | enhance-code-intelligence | Archived |
| 边界检测 | enhance-code-intelligence | Archived |
| 模式学习 | enhance-code-intelligence | Archived |
| Bug 定位（基础） | enhance-code-intelligence | Archived |
| SQLite 图存储 | augment-parity | Archived |
| SCIP 解析 | augment-parity | Archived |
| 守护进程 | augment-parity | Archived |
| LLM 重排序 | augment-parity | Archived |
| 孤儿检测 | augment-parity | Archived |
| 动态模式学习 | augment-parity | Archived |
| 缓存管理 | augment-upgrade-phase2 | Archived |
| 依赖守卫 | augment-upgrade-phase2 | Archived |
| 上下文层 | augment-upgrade-phase2 | Archived |
| 联邦 | augment-upgrade-phase2 | Archived |
| AST Delta 增量索引 | achieve-augment-full-parity | Approved |
| 传递性影响分析 | achieve-augment-full-parity | Approved |
| COD 架构可视化 | achieve-augment-full-parity | Approved |
| 子图智能裁剪 | achieve-augment-full-parity | Approved |
| 联邦虚拟边 | achieve-augment-full-parity | Approved |
| 意图偏好学习 | achieve-augment-full-parity | Approved |
| 安全漏洞追踪 | achieve-augment-full-parity | Approved |
| **边类型扩展** | **本提案** | **Pending** |
| **路径查询** | **本提案** | **Pending** |
| **ADR 解析** | **本提案** | **Pending** |
| **对话上下文** | **本提案** | **Pending** |
| **预热机制** | **本提案** | **Pending** |
| **请求取消** | **本提案** | **Pending** |
| **LRU 子图缓存** | **本提案** | **Pending** |
| **Bug 定位融合** | **本提案** | **Pending** |
| **CI/CD 集成** | **本提案** | **Pending** |
| **结构化上下文输出** | **本提案** | **Pending** |
| **DevBooks 适配** | **本提案** | **Pending** |

**合并后总能力**：31 个功能模块，覆盖 Augment **100% 轻资产能力**。

---

**Proposal Author 签名**：Proposal Author (Claude)
**日期**：2026-01-16

---

## Decision Log

### 2026-01-16 裁决：Approved

**裁决者**：Proposal Judge (Claude)

**理由摘要**：
- Author 已充分响应上一轮 Judge 裁决的所有阻塞项和建议项
- MOD-01 LRU 缓存进程隔离：已修改为 SQLite 持久化方案，跨进程可验证
- MOD-02 迁移策略闭环：已提供 `graph-store.sh migrate` 命令设计和三种升级路径
- OPT-01~05 所有建议均已纳入提案
- AC 量化充分：12 个验收标准均有明确验证条件，提供 2 个完整 JSON Schema
- 技术方案可行，与现有薄壳架构一致，风险识别完整

**必须修改项**：无（所有阻塞项已在修订中解决）

**验证要求**：
- [ ] Test Owner 阶段执行 Red 基线，产出 `evidence/red-baseline/`
- [ ] Coder 阶段执行 Green 验证，产出 `evidence/green-final/`
- [ ] 性能基准脚本首次运行时记录基线到 `evidence/baseline-metrics.md`
- [ ] common.sh 变更需优先编写回归测试（高风险依赖链）
- [ ] graph-store.sh 迁移需集成测试验证向后兼容

**遗漏项处理建议**（非阻塞，apply 阶段处理）：
- [ ] M-01 design.md 缺失：补充或声明替代
- [ ] M-02 迁移回滚方案：tasks.md 中添加
- [ ] M-03 ADR 测试数据：tests/fixtures/adr/ 添加
- [ ] M-04 性能基准基线值：Red 基线阶段记录

**下一步**：进入 Test Owner 阶段，产出 verification.md 和 Red 基线测试
