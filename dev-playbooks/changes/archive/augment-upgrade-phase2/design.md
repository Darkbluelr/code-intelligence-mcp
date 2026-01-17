# 设计文档：代码智能能力升级 Phase 2

> **Change ID**: `augment-upgrade-phase2`
> **Version**: 1.0.0
> **Status**: Draft
> **Owner**: Design Owner
> **Created**: 2026-01-13
> **Last Updated**: 2026-01-13
> **Last Verified**: 2026-01-13
> **Freshness Check**: 每次实现前验证

---

## 1. Acceptance Criteria（验收标准）

### 1.1 功能验收标准

| AC ID | 验收项 | Pass/Fail 判据 | 验收方式 |
|-------|--------|----------------|----------|
| AC-001 | 多级缓存生效 | 连续两次相同查询，第二次延迟 < 100ms | A（自动化测试） |
| AC-002 | 缓存 L1（内存）命中 | 同一会话内第二次查询直接返回内存值 | A（自动化测试） |
| AC-003 | 缓存 L2（文件）命中 | 跨会话第二次查询从文件缓存读取 | A（自动化测试） |
| AC-004 | mtime 失效机制 | 文件修改后缓存失效，返回新计算结果 | A（自动化测试） |
| AC-005 | blob hash 失效机制 | 文件内容变化后缓存失效（即使 mtime 被篡改） | A（自动化测试） |
| AC-006 | 循环依赖检测 | 检测已知循环依赖的测试项目，覆盖率 ≥ 95% | A（自动化测试） |
| AC-007 | 循环依赖误报率 | 测试集（20+ 样本）误报率 < 5% | A（自动化测试） |
| AC-008 | 架构规则校验 | 违规代码被正确识别，匹配 arch-rules.yaml 定义 | A（自动化测试） |
| AC-009 | Commit 语义分类 | 正确分类 fix/feat/refactor/docs/chore，准确率 ≥ 90% | A（自动化测试） |
| AC-010 | Bug 修复历史权重 | 热点分数包含 bug_weight 字段，权重计算正确 | A（自动化测试） |
| AC-011 | 联邦索引生成 | 成功扫描跨仓库契约，生成 federation-index.json | A（自动化测试） |
| AC-012 | Pre-commit 集成 | 钩子正常触发，输出符合预期格式 | A（自动化测试） |
| AC-013 | 向后兼容性 | 现有 8 个 MCP 工具签名不变，现有脚本无需修改 | A（回归测试） |
| AC-014 | hotspot-analyzer.sh 基线 | 无 `--with-bug-history` 时输出与变更前一致 | A（Golden File 对比） |

### 1.2 非功能验收标准

| AC ID | 验收项 | 阈值 | 验收方式 |
|-------|--------|------|----------|
| AC-N01 | 缓存命中后延迟 | P95 < 100ms | A（性能测试） |
| AC-N02 | 完整查询 P95 | P95 < 500ms（当前基线 ~2.8s） | A（性能测试） |
| AC-N03 | Pre-commit 耗时（仅 staged） | P95 < 2s（10 个 staged 文件） | A（性能测试） |
| AC-N04 | Pre-commit 耗时（含依赖） | P95 < 5s（10 staged + 50 依赖） | A（性能测试） |
| AC-N05 | 缓存磁盘占用 | ≤ 50MB（1000 文件项目） | A（磁盘检查） |
| AC-N06 | LRU 淘汰生效 | 达到上限时正确淘汰最旧 20% 条目 | A（自动化测试） |

---

## 2. Goals / Non-goals / Red Lines

### 2.1 Goals（目标）

1. **性能优化**：P95 延迟从 ~2.8s 降至 < 500ms（缓存 + 预计算）
2. **架构守护**：引入循环依赖检测 + 架构规则校验 + Pre-commit 集成
3. **上下文增强**：Commit 语义分类 + Bug 修复历史权重增强热点算法
4. **多仓库基础**：轻量联邦索引（跨仓库 API 契约追踪）
5. **代码智能能力**：从 Augment 的 70% 提升至 85%

### 2.2 Non-goals（非目标）

| 排除项 | 原因 |
|--------|------|
| 分布式缓存（Redis） | 重资产，超出单机方案范畴 |
| 中心化联邦索引服务 | 需要独立基础设施 |
| 实时跨仓库同步 | 复杂度高，ROI 低于定时任务 |
| 后台守护进程 | 避免增加运维复杂度 |
| 缓存 TTL 机制 | 采用 mtime + blob hash 精确失效 |

### 2.3 Red Lines（不可破约束）

| Red Line | 理由 |
|----------|------|
| 不破坏现有 MCP 工具签名 | 向后兼容性是核心约束 |
| 不引入外部服务依赖 | 保持轻资产原则 |
| 不修改 tests/ 目录 | Coder 角色禁止修改测试 |
| 不使用全局状态污染 | 脚本间隔离 |
| 缓存数据不可陈旧 | mtime + blob hash 必须准确失效 |

---

## 3. 执行摘要

本设计文档定义 Code Intelligence MCP Server 的 Phase 2 升级：通过多级缓存将 P95 延迟从 ~2.8s 降至 < 500ms，通过架构守护检测循环依赖和规则违规，通过 Commit 语义分类增强热点算法精度，通过轻量联邦索引支持跨仓库契约追踪。核心矛盾是在保持轻资产原则的前提下实现接近 Augment 的代码智能能力。

---

## 4. Problem Context（问题背景）

### 4.1 业务驱动

- **性能瓶颈**：当前 bug-locator.sh 等高频脚本 P95 延迟约 2.8s，影响开发体验
- **架构腐化风险**：无循环依赖检测，架构规则无自动校验
- **上下文不足**：热点分析仅基于变更频率 × 复杂度，未考虑 Bug 修复历史
- **多仓库盲区**：无法追踪跨仓库 API 契约依赖

### 4.2 技术债

- `cache-utils.sh` 仅支持单级 TTL 缓存，无内存层
- 无架构规则校验能力
- 无 Commit 语义分类能力

### 4.3 不解决的后果

- 性能差距持续影响用户体验
- 架构腐化无法早期发现
- Bug 修复历史价值未被利用
- 跨仓库场景无法支持

---

## 5. 价值链映射

```
Goal: 代码智能能力 70% → 85%
  │
  ├─ 阻碍: P95 延迟 ~2.8s
  │   └─ 杠杆: 多级缓存 + 预计算
  │       └─ 最小方案: cache-manager.sh（L1 内存 + L2 文件 + blob hash 失效）
  │
  ├─ 阻碍: 无架构守护
  │   └─ 杠杆: 静态分析 + Pre-commit
  │       └─ 最小方案: dependency-guard.sh + arch-rules.yaml
  │
  ├─ 阻碍: 热点精度不足
  │   └─ 杠杆: Commit 语义分类
  │       └─ 最小方案: context-layer.sh + hotspot-analyzer.sh 集成
  │
  └─ 阻碍: 多仓库盲区
      └─ 杠杆: 轻量联邦索引
          └─ 最小方案: federation-lite.sh（手动触发）
```

---

## 6. 背景与现状评估

### 6.1 现有资产

| 资产 | 路径 | 状态 |
|------|------|------|
| 单级缓存 | `scripts/cache-utils.sh` | 可用，待增强 |
| 热点分析器 | `scripts/hotspot-analyzer.sh` | 可用，待集成 Bug 历史 |
| 共享函数库 | `scripts/common.sh` | 可用，待扩展 |
| MCP Server | `src/server.ts` | 可用，待注册新工具 |

### 6.2 主要风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| 缓存竞态条件 | 中 | 高 | flock + 原子写入 + mtime 检测 |
| 循环依赖误报 | 低 | 中 | 白名单 + 置信度阈值 |
| Pre-commit 耗时过长 | 中 | 中 | 增量检查 + 可跳过选项 |
| Commit 分类覆盖不全 | 中 | 低 | 支持自定义规则扩展 |

---

## 7. 设计原则

### 7.1 核心原则

1. **轻资产优先**：不引入外部服务依赖
2. **精确失效优于 TTL**：使用 mtime + blob hash 而非时间窗口
3. **渐进增强**：新功能不破坏现有接口
4. **可观测优先**：所有操作可追踪、可验证

### 7.2 变化点识别

| 变化点 | 可能变化 | 封装策略 |
|--------|----------|----------|
| 缓存存储层 | 可能升级为 Redis | 抽象 CacheBackend 接口 |
| 架构规则格式 | 规则语法可能扩展 | 规则解析器可插拔 |
| Commit 分类规则 | 语言/团队规范不同 | 规则配置化 |
| 联邦索引触发 | 可能自动化 | 触发策略可配置 |

---

## 8. 目标架构

### 8.1 Bounded Context

```
┌─────────────────────────────────────────────────────────────────┐
│                     Code Intelligence MCP                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐       │
│  │ Cache Manager │  │ Dep. Guard    │  │ Context Layer │       │
│  │   (新增)      │  │   (新增)      │  │   (新增)      │       │
│  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘       │
│          │                  │                  │                │
│  ┌───────▼───────────────────────────────────────────┐         │
│  │                  Existing Scripts                  │         │
│  │  hotspot-analyzer | bug-locator | graph-rag | ... │         │
│  └───────────────────────────────────────────────────┘         │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐                          │
│  │ Federation    │  │ Pre-commit    │                          │
│  │ Lite (新增)   │  │ Hook (新增)   │                          │
│  └───────────────┘  └───────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 依赖方向

```
server.ts ──→ scripts/*.sh ──→ 外部工具 (rg, jq, git)
    │              │
    ▼              ▼
MCP SDK      cache-manager.sh ──→ cache-utils.sh (协作层)
                   │
                   ▼
             dependency-guard.sh
             context-layer.sh
             federation-lite.sh
```

### 8.3 关键扩展点

| 扩展点 | 位置 | 扩展方式 |
|--------|------|----------|
| 缓存后端 | cache-manager.sh | 环境变量 `CACHE_BACKEND` |
| 架构规则 | config/arch-rules.yaml | YAML 配置 |
| Commit 分类规则 | context-layer.sh | 内置 + 自定义正则 |
| 联邦仓库 | config/federation.yaml | YAML 配置 |

### 8.4 C4 Delta

**C2（Container Level）变更**：

| 变更类型 | 元素 | 说明 |
|----------|------|------|
| 新增 | cache-manager.sh | 多级缓存管理容器 |
| 新增 | dependency-guard.sh | 架构守护容器 |
| 新增 | context-layer.sh | 上下文层容器 |
| 新增 | federation-lite.sh | 联邦索引容器 |
| 新增 | hooks/pre-commit | Pre-commit 钩子 |
| 新增 | config/arch-rules.yaml | 架构规则配置 |
| 新增 | config/federation.yaml | 联邦配置 |
| 修改 | hotspot-analyzer.sh | 集成 Bug 修复历史 |
| 修改 | common.sh | 新增缓存共享函数 |
| 修改 | server.ts | 注册 ci_arch_check、ci_federation |

---

## 9. Testability & Seams（可测试性与接缝）

### 9.1 测试接缝（Seams）

| 模块 | 接缝位置 | 注入方式 |
|------|----------|----------|
| cache-manager.sh | `CACHE_DIR` 环境变量 | 测试时指向临时目录 |
| cache-manager.sh | `GIT_HASH_CMD` 环境变量 | 测试时 Mock git hash-object |
| dependency-guard.sh | `ARCH_RULES_FILE` 环境变量 | 测试时指向测试规则 |
| context-layer.sh | `GIT_LOG_CMD` 环境变量 | 测试时 Mock git log |
| federation-lite.sh | `FEDERATION_CONFIG` 环境变量 | 测试时指向测试配置 |

### 9.2 Pinch Points（汇点）

| 汇点 | 路径数 | 测试价值 |
|------|--------|----------|
| cache-manager.sh:get_cached_with_validation() | 3 | 覆盖 L1/L2/Miss 路径 |
| dependency-guard.sh:check_imports() | 2 | 覆盖 Pass/Fail 路径 |
| hotspot-analyzer.sh:main() | 2 | 覆盖有/无 Bug 历史路径 |

### 9.3 依赖隔离

| 外部依赖 | 隔离方式 |
|----------|----------|
| git | 命令变量注入（`GIT_CMD`） |
| 文件系统 | 临时目录（`CACHE_DIR`） |
| MCP Server | 脚本直接调用测试 |

---

## 10. 领域模型（Domain Model）

### 10.1 Data Model

```
@Entity CacheEntry
  - key: string               # 缓存键（MD5 hash）
  - file_path: string         # 原始文件路径
  - mtime: timestamp          # 文件修改时间
  - blob_hash: string         # Git blob hash 或 content MD5
  - query_hash: string        # 查询参数 hash
  - value: string             # 缓存值
  - created_at: timestamp     # 创建时间
  - accessed_at: timestamp    # 最后访问时间

@ValueObject CacheKey
  - file_path: string
  - mtime: timestamp
  - blob_hash: string
  - query_hash: string
  - computed_key: string      # <file_path>:<mtime>:<blob_hash>:<query_hash>

@Entity ArchRule
  - name: string              # 规则名称
  - from: glob_pattern        # 源文件模式
  - cannot_import: glob_pattern[]  # 禁止导入的模式
  - severity: "error" | "warning"

@Entity CycleDetection
  - nodes: string[]           # 循环中的文件节点
  - edges: [string, string][] # 依赖边
  - cycle_path: string[]      # 循环路径

@ValueObject CommitClassification
  - sha: string
  - type: "fix" | "feat" | "refactor" | "docs" | "chore"
  - confidence: float         # 0.0-1.0
  - message: string

@Entity FederationEntry
  - repo_name: string
  - repo_path: string
  - contracts: ContractFile[]
  - last_indexed: timestamp

@ValueObject ContractFile
  - path: string
  - type: "proto" | "openapi" | "graphql" | "typescript"
  - symbols: string[]
```

### 10.2 Business Rules

| BR ID | 规则 | 触发条件 | 违反行为 |
|-------|------|----------|----------|
| BR-001 | 缓存 key 必须包含 blob hash | 缓存写入时 | 降级到 content MD5 |
| BR-002 | mtime 变化间隔 < 1s 视为写入中 | 缓存读取时 | 跳过缓存直接计算 |
| BR-003 | LRU 淘汰阈值 50MB | 缓存写入时 | 删除最旧 20% 条目 |
| BR-004 | 循环依赖检测白名单 | 检测时 | 跳过白名单路径 |
| BR-005 | 架构违规默认警告 | 检测到违规时 | 输出警告但不阻断 |
| BR-006 | Commit 分类优先级 | 分类时 | fix > feat > refactor > docs > chore |

### 10.3 Invariants（固定规则）

```
[Invariant] 缓存条目数 ≥ 0
[Invariant] 缓存总大小 ≤ config.cache.max_size_mb
[Invariant] blob_hash 与文件内容一致
[Invariant] 循环依赖路径长度 ≥ 2
[Invariant] Commit 分类 confidence ∈ [0.0, 1.0]
```

---

## 11. 核心数据与事件契约

### 11.1 缓存条目格式（L2 文件）

```json
{
  "schema_version": "1.0.0",
  "key": "<computed_key>",
  "file_path": "src/server.ts",
  "mtime": 1705132800,
  "blob_hash": "a1b2c3d4e5f6...",
  "query_hash": "x1y2z3...",
  "value": "<cached_result>",
  "created_at": 1705132800,
  "accessed_at": 1705132800
}
```

### 11.2 架构违规报告格式

```json
{
  "schema_version": "1.0.0",
  "violations": [
    {
      "rule": "ui-no-direct-db",
      "severity": "error",
      "source": "src/ui/Dashboard.tsx",
      "target": "src/db/connection.ts",
      "line": 15,
      "message": "UI 组件不能直接导入数据库模块"
    }
  ],
  "cycles": [
    {
      "path": ["src/a.ts", "src/b.ts", "src/c.ts", "src/a.ts"],
      "severity": "error"
    }
  ],
  "summary": {
    "total_violations": 1,
    "total_cycles": 1,
    "blocked": false
  }
}
```

### 11.3 联邦索引格式

```json
{
  "schema_version": "1.0.0",
  "indexed_at": "2026-01-13T10:00:00Z",
  "repositories": [
    {
      "name": "api-contracts",
      "path": "../api-contracts",
      "contracts": [
        {
          "path": "user.proto",
          "type": "proto",
          "symbols": ["UserService", "User", "CreateUserRequest"]
        }
      ]
    }
  ]
}
```

### 11.4 兼容性策略

| 契约 | 版本策略 | 兼容窗口 |
|------|----------|----------|
| 缓存条目 | schema_version 检查，不兼容则失效 | 1 个版本 |
| 架构报告 | 向后兼容，新增字段 | 永久 |
| 联邦索引 | schema_version 检查 | 1 个版本 |

---

## 12. 关键机制

### 12.1 多级缓存机制

```
查询请求
    │
    ▼
┌─────────────────────────────┐
│  L1 查找（内存 Hash Table）  │
│  Key = computed_key         │
└─────────────┬───────────────┘
              │ Miss
              ▼
┌─────────────────────────────┐
│  L2 查找（文件系统）         │
│  Path = $CACHE_DIR/$key     │
└─────────────┬───────────────┘
              │ Miss
              ▼
┌─────────────────────────────┐
│  计算结果                    │
│  写入 L1 + L2               │
└─────────────────────────────┘
```

### 12.2 缓存失效机制

```
读取缓存时：
1. 检查文件 mtime
   - 当前 mtime != 缓存 mtime → 失效
   - mtime 变化间隔 < 1s → 视为写入中，跳过缓存

2. 检查 blob hash（仅 tracked 文件）
   - 当前 blob_hash != 缓存 blob_hash → 失效
   - untracked 文件使用 content MD5

3. 竞态处理
   - 使用 flock 保护写入
   - 原子写入（先写临时文件再 mv）
```

### 12.3 竞态处理伪代码（VR-01）

```bash
# cache-manager.sh 核心函数

get_cached_with_validation() {
  local file_path="$1"
  local query_hash="$2"

  # 1. L1 查找（内存）
  local l1_key="${file_path}:${query_hash}"
  if [[ -n "${L1_CACHE[$l1_key]:-}" ]]; then
    echo "${L1_CACHE[$l1_key]}"
    return 0
  fi

  # 2. 获取当前文件状态
  local current_mtime
  current_mtime=$(get_file_mtime "$file_path")

  # 3. 检测写入中状态（mtime 变化 < 1s）
  local last_check_mtime="${FILE_MTIME_CACHE[$file_path]:-0}"
  local mtime_delta=$((current_mtime - last_check_mtime))
  if [[ $mtime_delta -ge 0 && $mtime_delta -lt 1 ]]; then
    # 文件可能正在写入，跳过缓存
    return 1
  fi
  FILE_MTIME_CACHE[$file_path]=$current_mtime

  # 4. 计算 blob hash
  local current_blob_hash
  current_blob_hash=$(get_blob_hash "$file_path")

  # 5. 构建缓存 key
  local cache_key
  cache_key=$(compute_cache_key "$file_path" "$current_mtime" "$current_blob_hash" "$query_hash")
  local cache_file="${CACHE_DIR}/l2/${cache_key}"

  # 6. L2 查找（文件）
  if [[ -f "$cache_file" ]]; then
    # 使用 flock 共享锁读取
    (
      flock -s 200 || return 1

      # 验证缓存条目
      local cached_mtime cached_blob_hash
      cached_mtime=$(jq -r '.mtime' "$cache_file")
      cached_blob_hash=$(jq -r '.blob_hash' "$cache_file")

      if [[ "$cached_mtime" == "$current_mtime" &&
            "$cached_blob_hash" == "$current_blob_hash" ]]; then
        # 缓存有效，更新访问时间
        local value
        value=$(jq -r '.value' "$cache_file")
        # 写入 L1
        L1_CACHE[$l1_key]="$value"
        echo "$value"
        return 0
      fi
    ) 200>"${cache_file}.lock"
  fi

  return 1  # 缓存未命中
}

set_cache_with_lock() {
  local file_path="$1"
  local query_hash="$2"
  local value="$3"

  # 获取文件状态
  local mtime blob_hash
  mtime=$(get_file_mtime "$file_path")
  blob_hash=$(get_blob_hash "$file_path")

  local cache_key
  cache_key=$(compute_cache_key "$file_path" "$mtime" "$blob_hash" "$query_hash")
  local cache_file="${CACHE_DIR}/l2/${cache_key}"
  local tmp_file="${cache_file}.tmp.$$"

  # 检查磁盘空间
  check_and_evict_if_needed

  # 原子写入：先写临时文件再 mv
  (
    flock -x 200 || return 1

    # 写入临时文件
    jq -n \
      --arg key "$cache_key" \
      --arg file_path "$file_path" \
      --arg mtime "$mtime" \
      --arg blob_hash "$blob_hash" \
      --arg query_hash "$query_hash" \
      --arg value "$value" \
      --arg created_at "$(date +%s)" \
      '{
        schema_version: "1.0.0",
        key: $key,
        file_path: $file_path,
        mtime: ($mtime | tonumber),
        blob_hash: $blob_hash,
        query_hash: $query_hash,
        value: $value,
        created_at: ($created_at | tonumber),
        accessed_at: ($created_at | tonumber)
      }' > "$tmp_file"

    # 原子替换
    mv "$tmp_file" "$cache_file"

  ) 200>"${cache_file}.lock"

  # 写入 L1
  local l1_key="${file_path}:${query_hash}"
  L1_CACHE[$l1_key]="$value"
}

get_blob_hash() {
  local file_path="$1"

  # 检查是否为 git tracked 文件
  if git ls-files --error-unmatch "$file_path" &>/dev/null 2>&1; then
    # 使用 git blob hash
    git hash-object "$file_path"
  else
    # untracked 文件使用 content MD5
    if command -v md5sum &>/dev/null; then
      md5sum "$file_path" | cut -d' ' -f1
    else
      md5 -q "$file_path"
    fi
  fi
}

check_and_evict_if_needed() {
  local max_size_mb="${CACHE_MAX_SIZE_MB:-50}"
  local cache_dir="${CACHE_DIR}/l2"

  # 获取当前缓存大小（MB）
  local current_size
  current_size=$(du -sm "$cache_dir" 2>/dev/null | cut -f1 || echo 0)

  if [[ $current_size -ge $max_size_mb ]]; then
    log_info "缓存达到上限 ${current_size}MB >= ${max_size_mb}MB，执行 LRU 淘汰"

    # 按访问时间排序，删除最旧 20%
    local total_files
    total_files=$(find "$cache_dir" -type f -name "*.json" | wc -l)
    local evict_count=$((total_files * 20 / 100))
    [[ $evict_count -lt 1 ]] && evict_count=1

    # 按 accessed_at 排序删除
    find "$cache_dir" -type f -name "*.json" -exec \
      sh -c 'echo "$(jq -r ".accessed_at // 0" "$1") $1"' _ {} \; | \
      sort -n | head -n "$evict_count" | cut -d' ' -f2- | \
      xargs rm -f

    log_info "已淘汰 $evict_count 个缓存条目"
  fi
}
```

### 12.4 循环依赖检测机制

```
输入: 文件列表 + import 关系图
输出: 循环路径列表

算法: DFS + 访问状态标记
  - WHITE: 未访问
  - GRAY: 正在访问（在递归栈中）
  - BLACK: 已完成

发现 GRAY → GRAY 边 → 检测到循环
```

### 12.5 架构规则校验机制

```
输入: 源文件 + arch-rules.yaml
输出: 违规列表

1. 解析源文件 import 语句
2. 对每条规则：
   - 检查源文件是否匹配 from 模式
   - 检查 import 目标是否匹配 cannot_import 模式
   - 匹配 → 记录违规
3. 聚合结果，按 severity 排序
```

---

## 13. 可观测性与验收

### 13.1 Metrics

| 指标 | 类型 | 采集方式 |
|------|------|----------|
| cache_hit_rate | Gauge | L1/L2 命中计数 |
| cache_latency_ms | Histogram | 查询耗时 |
| cache_size_bytes | Gauge | du -sb |
| arch_violations_total | Counter | 违规计数 |
| cycle_detections_total | Counter | 循环检测计数 |

### 13.2 KPI

| KPI | 当前 | 目标 |
|-----|------|------|
| P95 延迟 | ~2.8s | < 500ms |
| 缓存命中率 | N/A | > 80% |
| 循环检测覆盖率 | 0% | > 95% |
| 误报率 | N/A | < 5% |

### 13.3 SLO

| SLO | 目标 | 测量周期 |
|-----|------|----------|
| 热查询 P95 延迟 | < 100ms | 日 |
| 完整查询 P95 延迟 | < 500ms | 日 |
| Pre-commit P95 耗时 | < 5s | 日 |

---

## 14. 安全、合规与多租户隔离

### 14.1 安全考量

| 风险 | 缓解措施 |
|------|----------|
| 缓存注入 | 缓存 key 使用 MD5 hash |
| 路径遍历 | 验证文件路径在项目范围内 |
| 竞态条件 | flock + 原子写入 |

### 14.2 多租户

**不适用** - 本系统为单机单用户设计。

---

## 15. 里程碑

### Phase 1（低风险 - 基础能力）

- [ ] 新增 cache-manager.sh
- [ ] 修改 common.sh 新增缓存共享函数
- [ ] 集成缓存到 bug-locator.sh、graph-rag.sh

### Phase 2（中风险 - 架构守护）

- [ ] 新增 dependency-guard.sh
- [ ] 新增 config/arch-rules.yaml
- [ ] 新增 hooks/pre-commit
- [ ] server.ts 注册 ci_arch_check

### Phase 3（中风险 - 上下文增强）

- [ ] 新增 context-layer.sh
- [ ] hotspot-analyzer.sh 集成 Bug 修复历史

### Phase 4（中风险 - 联邦能力）

- [ ] 新增 federation-lite.sh
- [ ] 新增 config/federation.yaml
- [ ] server.ts 注册 ci_federation

---

## 16. Deprecation Plan

**不适用** - 本次变更为新增功能，无弃用项。

`cache-utils.sh` 将保留并被 `cache-manager.sh` 调用，不弃用。

---

## 17. Design Rationale（设计决策理由）

### 17.1 为什么选择 mtime + blob hash 而非 TTL？

**备选方案**：
- A: 固定 TTL（5min L1, 1h L2）
- B: 智能 TTL（基于变更频率）
- C: mtime + blob hash（精确失效）

**选择 C 的理由**：
- 代码文件变更不频繁但变更后必须立即失效
- TTL 可能导致陈旧数据或过早失效
- blob hash 可检测 mtime 被篡改的情况
- 实现复杂度可接受

### 17.2 为什么选择手动触发联邦索引？

**备选方案**：
- A: 手动触发（`ci_federation --update`）
- B: 定时任务（cron/launchd）
- C: Git Hook 触发（push 时）

**选择 A 的理由**：
- 避免引入后台进程增加运维复杂度
- 跨仓库契约变更频率低，手动触发足够
- 用户可控性更高
- 未来可平滑升级到自动触发

### 17.3 为什么架构违规默认警告？

**备选方案**：
- A: 阻断（违规时 pre-commit 失败）
- B: 警告（仅输出警告）
- C: 可配置（默认警告，可设为阻断）

**选择 C 的理由**：
- 渐进式采用，降低初期摩擦
- 团队可根据成熟度选择严格程度
- 紧急修复场景可跳过

---

## 18. Trade-offs（权衡取舍）

| 取舍 | 放弃 | 获得 |
|------|------|------|
| 精确失效 vs 简单 | 实现简单性 | 数据准确性 |
| 手动触发 vs 自动 | 自动化 | 可控性、轻量 |
| 默认警告 vs 阻断 | 强制合规 | 采用摩擦低 |
| 单机 vs 分布式 | 扩展性 | 轻资产 |

### 不适用场景

- 超大规模仓库（>10万文件）：缓存可能不足
- 多用户共享：无隔离机制
- 实时跨仓库同步：仅支持手动更新

---

## 19. Technical Debt（技术债务）

| TD ID | 类型 | 描述 | 原因 | 影响 | 偿还计划 |
|-------|------|------|------|------|----------|
| TD-001 | Code | L1 缓存使用 Bash 关联数组，重启后丢失 | 轻量实现 | Low | Phase 2 考虑 SQLite |
| TD-002 | Test | 竞态条件测试覆盖不完整 | 测试复杂度高 | Medium | 补充并发测试 |
| TD-003 | Code | 架构规则解析器硬编码 YAML 结构 | 快速实现 | Low | 需要扩展时重构 |

---

## 20. 风险与降级策略

### 20.1 Failure Modes

| 失败模式 | 检测方式 | 降级策略 |
|----------|----------|----------|
| 缓存损坏 | JSON 解析失败 | 清除损坏条目，直接计算 |
| flock 超时 | 超时错误 | 跳过缓存，直接计算 |
| git 不可用 | 命令失败 | 降级到 content MD5 |
| 磁盘空间不足 | 写入失败 | LRU 淘汰 + 告警 |

### 20.2 Degrade Paths

```
正常路径: L1 → L2 → 计算 → 写入 L1+L2
降级路径 1: L1 不可用 → L2 → 计算
降级路径 2: L2 不可用 → 计算（无缓存）
降级路径 3: git 不可用 → content MD5 替代 blob hash
```

---

## 21. DoD 完成定义（Definition of Done）

### 21.1 本设计何时算"完成"？

1. 所有 AC-xxx 通过验收（见 §1）
2. 所有非功能验收标准满足（见 §1.2）
3. 回归测试通过（现有 MCP 工具兼容）
4. 证据产出完整（见 §21.2）

### 21.2 必须通过的闸门

| 闸门 | 验证命令 | 通过标准 |
|------|----------|----------|
| 单元测试 | `bats tests/*.bats` | 100% 通过 |
| 静态检查 | `shellcheck scripts/*.sh` | 无 error |
| TypeScript 编译 | `npm run build` | 无错误 |
| 性能基准 | `evidence/benchmark.sh` | P95 < 500ms |
| 回归测试 | `tests/regression/*.bats` | 100% 通过 |

### 21.3 必须产出的证据

| 证据 | 路径 | 说明 |
|------|------|------|
| 缓存性能报告 | `evidence/cache-benchmark.log` | L1/L2 命中延迟 |
| 循环检测报告 | `evidence/cycle-detection.log` | 覆盖率 + 误报率 |
| 架构违规样本 | `evidence/arch-violation-samples/` | ≥3 个样本 |
| Golden File | `evidence/baseline-hotspot.golden` | 无 Bug 历史基线 |
| Pre-commit 测试 | `evidence/pre-commit-test.log` | 钩子触发验证 |
| LRU 淘汰日志 | `evidence/cache-eviction.log` | 淘汰行为验证 |

### 21.4 AC 交叉引用

| DoD 项 | 关联 AC |
|--------|---------|
| 单元测试通过 | AC-001 ~ AC-014 |
| 性能基准通过 | AC-N01 ~ AC-N06 |
| 回归测试通过 | AC-013, AC-014 |
| 证据产出 | 所有 AC |

---

## 22. Open Questions（≤3）

| ID | 问题 | 影响范围 | 状态 |
|----|------|----------|------|
| OQ1 | N4 缓存上限 50MB 是否支持动态配置？ | cache-manager.sh | 建议支持，低优先级 |
| OQ2 | untracked 文件是否统一使用 `git hash-object`？ | cache-manager.sh | 建议统一，低优先级 |
| OQ3 | rule severity vs config.on_violation 优先级如何确定？ | dependency-guard.sh | 建议 rule > config，低优先级 |

---

## 23. Contract（契约计划）

### 23.1 API 变更

#### 新增 MCP 工具

| 工具名 | 脚本 | 说明 |
|--------|------|------|
| `ci_arch_check` | `dependency-guard.sh` | 架构规则校验 + 循环依赖检测 |
| `ci_federation` | `federation-lite.sh` | 跨仓库契约索引与搜索 |

#### ci_arch_check 签名

```typescript
{
  name: "ci_arch_check",
  description: "Check architecture rules and detect circular dependencies",
  inputSchema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Target directory (default: .)" },
      format: { type: "string", enum: ["text", "json"], description: "Output format (default: json)" },
      rules: { type: "string", description: "Path to arch-rules.yaml (default: config/arch-rules.yaml)" }
    }
  }
}
```

#### ci_federation 签名

```typescript
{
  name: "ci_federation",
  description: "Manage cross-repository federation index",
  inputSchema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ["status", "update", "search"], description: "Action to perform (default: status)" },
      query: { type: "string", description: "Symbol to search (for search action)" },
      format: { type: "string", enum: ["text", "json"], description: "Output format (default: json)" }
    }
  }
}
```

### 23.2 脚本接口扩展

#### hotspot-analyzer.sh

| 参数 | 类型 | 说明 |
|------|------|------|
| `--with-bug-history` | flag | 启用 Bug 修复历史权重 |
| `--bug-weight <float>` | option | Bug 修复权重系数（默认 1.0） |

**向后兼容**：无新参数时输出与变更前一致。

### 23.3 配置文件

| 配置文件 | 路径 | 说明 |
|----------|------|------|
| 架构规则 | `config/arch-rules.yaml` | 依赖规则定义 |
| 联邦配置 | `config/federation.yaml` | 跨仓库配置 |

### 23.4 数据格式

| 数据 | 路径 | Schema 版本 |
|------|------|-------------|
| L2 缓存条目 | `.ci-cache/l2/*.json` | 1.0.0 |
| 架构违规报告 | stdout (JSON) | 1.0.0 |
| 上下文索引 | `.devbooks/context-index.json` | 1.0.0 |
| 联邦索引 | `.devbooks/federation-index.json` | 1.0.0 |

### 23.5 兼容策略

| 类别 | 策略 | 说明 |
|------|------|------|
| MCP 工具 | 向后兼容 | 现有 8 个工具签名不变 |
| 脚本接口 | 向后兼容 | 新参数为可选 |
| 缓存格式 | Schema 版本检查 | 不兼容时自动失效 |
| 配置格式 | 可选 | 无配置时使用默认值 |

### 23.6 Contract Test IDs 汇总

| 模块 | Test IDs | 数量 |
|------|----------|------|
| Cache Manager | CT-CACHE-001 ~ CT-CACHE-008 | 8 |
| Dependency Guard | CT-GUARD-001 ~ CT-GUARD-011 | 11 |
| Context Layer | CT-CTX-001 ~ CT-CTX-009 | 9 |
| Federation Lite | CT-FED-001 ~ CT-FED-011 | 11 |
| **总计** | | **39** |

详细规格见 `specs/<capability>/spec.md`。

---

## Documentation Impact（文档影响）

### 需要更新的文档

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| README.md | 新增 `ci_arch_check`、`ci_federation` 工具说明 | P0 |
| dev-playbooks/specs/_meta/project-profile.md | 新增模块描述 | P1 |

### 无需更新的文档

- [x] 本次变更不影响现有工具使用方式（向后兼容）

### 文档更新检查清单

- [ ] 新增脚本（cache-manager.sh 等）已在使用文档中说明
- [ ] 新增配置项（arch-rules.yaml、federation.yaml）已在配置文档中说明
- [ ] 新增 MCP 工具（ci_arch_check、ci_federation）已在 README 中说明
