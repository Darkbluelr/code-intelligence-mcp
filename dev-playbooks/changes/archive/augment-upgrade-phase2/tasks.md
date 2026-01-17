# 编码计划：代码智能能力升级 Phase 2

> **Change ID**: `augment-upgrade-phase2`
> **维护者**: Planner
> **关联设计**: `dev-playbooks/changes/augment-upgrade-phase2/design.md`
> **关联规格**: `dev-playbooks/changes/augment-upgrade-phase2/specs/*/spec.md`
> **创建日期**: 2026-01-14
> **模式**: 主线计划模式

---

## 【模式选择】

当前模式：`主线计划模式`

---

# 主线计划区 (Main Plan Area)

## MP1: 多级缓存管理 (Cache Manager)

### 目的
实现 L1（内存）+ L2（文件）多级缓存，通过 mtime + blob hash 精确失效，将 P95 延迟从 ~2.8s 降至 < 500ms。

### 交付物
- `scripts/cache-manager.sh`：多级缓存管理脚本
- `scripts/common.sh` 修改：新增缓存相关共享函数

### 影响范围
| 文件 | 变更类型 |
|------|----------|
| `scripts/cache-manager.sh` | 新增 |
| `scripts/common.sh` | 修改 |

### 子任务

#### MP1.1: 实现缓存核心函数

**交付物**：`scripts/cache-manager.sh` 核心框架

**接口契约**：
```bash
# 公开函数
get_cached_with_validation(file_path, query_hash) -> value | exit 1
set_cache_with_lock(file_path, query_hash, value) -> void
get_blob_hash(file_path) -> hash_string
compute_cache_key(file_path, mtime, blob_hash, query_hash) -> key_string
get_file_mtime(file_path) -> timestamp
```

**约束**：
- 使用 `declare -A L1_CACHE` 关联数组实现内存缓存
- L2 缓存路径 `$CACHE_DIR/l2/<key>.json`
- 缓存条目格式符合 REQ-CACHE-006

**验收标准**：
- [x] CT-CACHE-001: L1 命中返回延迟 < 10ms
- [x] CT-CACHE-002: L2 命中返回延迟 < 100ms
- [x] CT-CACHE-003: 缓存 Key 包含 file_path:mtime:blob_hash:query_hash

**依赖**：无

**风险**：Bash 关联数组性能上限

---

#### MP1.2: 实现精确失效机制

**交付物**：缓存失效检测逻辑

**接口契约**：
```bash
# 内部函数
is_file_being_written(file_path) -> boolean
validate_cache_entry(cache_file, current_mtime, current_blob_hash) -> boolean
```

**约束**：
- mtime 变化间隔 < 1s 视为"写入中"，跳过缓存
- untracked 文件使用 `md5sum`/`md5` 替代 `git hash-object`
- 禁止使用 TTL 失效策略

**验收标准**：
- [x] CT-CACHE-003: mtime 变化触发失效
- [x] CT-CACHE-003: blob hash 变化触发失效
- [x] CT-CACHE-004: 写入中检测正确跳过缓存
- [x] CT-CACHE-007: Git 不可用时降级到 md5

**依赖**：MP1.1

**风险**：stat 命令跨平台差异（macOS vs Linux）

---

#### MP1.3: 实现并发保护与原子写入

**交付物**：竞态条件处理逻辑

**接口契约**：
```bash
# 使用 flock 保护写入
# 使用 tmp.$$.$$ 临时文件 + mv 原子替换
```

**约束**：
- 使用 `flock -x` 独占锁保护写入
- 使用 `flock -s` 共享锁保护读取
- 原子写入：先写 `*.tmp.$$`，再 `mv` 替换

**验收标准**：
- [x] CT-CACHE-005: 并发写入无数据损坏
- [x] 无竞态条件导致的缓存不一致

**依赖**：MP1.1

**风险**：flock 在某些文件系统不可用

---

#### MP1.4: 实现 LRU 淘汰策略

**交付物**：缓存淘汰逻辑

**接口契约**：
```bash
check_and_evict_if_needed() -> void
```

**约束**：
- 默认上限 `CACHE_MAX_SIZE_MB=50`
- 淘汰比例 20%
- 按 `accessed_at` 字段排序淘汰最旧条目
- 必须记录淘汰事件到日志

**验收标准**：
- [x] CT-CACHE-006: 达到上限时正确淘汰 20% 条目
- [x] AC-N05: 缓存磁盘占用 <= 50MB（1000 文件项目）
- [x] AC-N06: LRU 淘汰生效

**依赖**：MP1.1

**风险**：大量小文件时 find + jq 性能

---

#### MP1.5: Schema 版本兼容处理

**交付物**：版本检查与降级逻辑

**接口契约**：
```bash
CACHE_SCHEMA_VERSION="1.0.0"
is_schema_compatible(cache_file) -> boolean
```

**约束**：
- `schema_version` 不兼容时视为缓存未命中
- 删除不兼容的旧条目

**验收标准**：
- [x] CT-CACHE-008: Schema 版本不兼容时自动失效

**依赖**：MP1.1

**风险**：低

---

### 验收标准汇总（MP1）
| AC ID | 验收项 | Pass/Fail 判据 |
|-------|--------|----------------|
| AC-001 | 多级缓存生效 | 连续两次相同查询，第二次延迟 < 100ms |
| AC-002 | L1 命中 | 同一会话内第二次查询直接返回内存值 |
| AC-003 | L2 命中 | 跨会话第二次查询从文件缓存读取 |
| AC-004 | mtime 失效 | 文件修改后缓存失效 |
| AC-005 | blob hash 失效 | 内容变化后缓存失效（即使 mtime 被篡改） |
| AC-N01 | 缓存命中延迟 | P95 < 100ms |
| AC-N05 | 磁盘占用 | <= 50MB |
| AC-N06 | LRU 淘汰 | 正确淘汰最旧 20% |

---

## MP2: 架构守护 (Dependency Guard)

### 目的
引入循环依赖检测 + 架构规则校验 + Pre-commit 集成，保护架构不腐化。

### 交付物
- `scripts/dependency-guard.sh`：架构守护脚本
- `config/arch-rules.yaml`：架构规则配置
- `hooks/pre-commit`：Pre-commit 钩子
- `src/server.ts` 修改：注册 `ci_arch_check` MCP 工具

### 影响范围
| 文件 | 变更类型 |
|------|----------|
| `scripts/dependency-guard.sh` | 新增 |
| `config/arch-rules.yaml` | 新增 |
| `hooks/pre-commit` | 新增 |
| `src/server.ts` | 修改 |

### 子任务

#### MP2.1: 实现 Import 语句解析

**交付物**：Import 语句提取逻辑

**接口契约**：
```bash
extract_imports(file_path) -> json_array
# 输出: [{"source": "file.ts", "target": "./module", "line": 5}]
```

**约束**：
- 支持 TypeScript `import`/`require`
- 支持 Bash `source`/`.`
- 使用 ripgrep + 正则提取

**验收标准**：
- [x] 正确提取 TypeScript import 语句
- [x] 正确提取 Bash source 语句
- [x] 输出 JSON 格式正确

**依赖**：无

**风险**：复杂 import 语法（动态导入、re-export）

---

#### MP2.2: 实现循环依赖检测算法

**交付物**：DFS 循环检测逻辑

**接口契约**：
```bash
detect_cycles(scope_pattern) -> json
# 输出: {"cycles": [{"path": ["a.ts", "b.ts", "a.ts"], "severity": "error"}]}
```

**约束**：
- 使用 DFS + WHITE/GRAY/BLACK 状态标记
- 发现 GRAY → GRAY 边即为循环
- 支持白名单排除

**验收标准**：
- [x] CT-GUARD-001: 简单 A→B→A 循环检测
- [x] CT-GUARD-002: 多节点 A→B→C→D→A 循环检测
- [x] CT-GUARD-003: 白名单正确排除
- [x] AC-006: 检测覆盖率 >= 95%
- [x] AC-007: 误报率 < 5%

**依赖**：MP2.1

**风险**：大型项目节点数过多时性能

---

#### MP2.3: 实现架构规则解析与校验

**交付物**：规则解析与违规检测逻辑

**接口契约**：
```bash
load_arch_rules(rules_file) -> json
check_rule_violation(source, target, rules) -> violation | null
```

**约束**：
- 规则格式符合 spec.md 定义
- 规则优先级：`rule.severity` > `config.on_violation`
- 支持 glob 模式匹配

**验收标准**：
- [x] CT-GUARD-004: 规则违规正确检测
- [x] CT-GUARD-007: 警告模式不阻断
- [x] CT-GUARD-008: 阻断模式正确退出
- [x] AC-008: 违规代码被正确识别

**依赖**：MP2.1

**风险**：复杂 glob 模式性能

---

#### MP2.4: 实现违规报告输出

**交付物**：JSON/Text 格式报告生成

**接口契约**：
```bash
generate_report(violations, cycles, format) -> string
```

**约束**：
- JSON 格式符合 REQ-GUARD-003
- 包含 summary.blocked 字段
- 支持 text/json 两种格式

**验收标准**：
- [x] CT-GUARD-010: JSON 格式符合 Schema
- [x] 报告包含 source、target、line、message

**依赖**：MP2.2, MP2.3

**风险**：低

---

#### MP2.5: 实现 Pre-commit Hook

**交付物**：`hooks/pre-commit` 脚本

**接口契约**：
```bash
# 参数
--with-deps  # 包含一级依赖
```

**约束**：
- 默认仅检查 staged 文件
- `--with-deps` 扩展到一级依赖
- 仅 staged 耗时 < 2s，含依赖 < 5s
- 默认警告不阻断

**验收标准**：
- [x] CT-GUARD-005: 仅检查 staged 文件
- [x] CT-GUARD-006: `--with-deps` 正确扩展
- [x] AC-012: 钩子正常触发
- [x] AC-N03: 耗时 < 2s（仅 staged）
- [x] AC-N04: 耗时 < 5s（含依赖）

**依赖**：MP2.4

**风险**：Pre-commit 环境差异

---

#### MP2.6: 注册 ci_arch_check MCP 工具

**交付物**：`src/server.ts` 修改

**接口契约**：
```typescript
{
  name: "ci_arch_check",
  inputSchema: {
    properties: {
      path: { type: "string" },
      format: { type: "string", enum: ["text", "json"] },
      rules: { type: "string" }
    }
  }
}
```

**约束**：
- 不影响现有 8 个工具（AC-013）
- 调用 `dependency-guard.sh`

**验收标准**：
- [x] CT-GUARD-011: MCP 工具签名正确
- [x] AC-013: 现有工具签名不变

**依赖**：MP2.4

**风险**：低

---

#### MP2.7: 创建 arch-rules.yaml 示例配置

**交付物**：`config/arch-rules.yaml`

**约束**：
- 符合 spec.md 定义的 Schema
- 包含常见规则示例（如 UI 不能直接导入 DB）

**验收标准**：
- [x] YAML 语法正确
- [x] 包含至少 2 条示例规则

**依赖**：无

**风险**：无

---

### 验收标准汇总（MP2）
| AC ID | 验收项 | Pass/Fail 判据 |
|-------|--------|----------------|
| AC-006 | 循环依赖检测 | 覆盖率 >= 95% |
| AC-007 | 误报率 | < 5% |
| AC-008 | 架构规则校验 | 违规代码被正确识别 |
| AC-012 | Pre-commit | 钩子正常触发 |
| AC-013 | 向后兼容 | 现有 8 个工具签名不变 |
| AC-N03 | Pre-commit 耗时 | < 2s（仅 staged） |
| AC-N04 | Pre-commit 耗时 | < 5s（含依赖） |

---

## MP3: 上下文层增强 (Context Layer)

### 目的
通过 Commit 语义分类增强热点分析精度，将 Bug 修复历史纳入热点分数计算。

### 交付物
- `scripts/context-layer.sh`：上下文层脚本
- `scripts/hotspot-analyzer.sh` 修改：集成 Bug 修复历史

### 影响范围
| 文件 | 变更类型 |
|------|----------|
| `scripts/context-layer.sh` | 新增 |
| `scripts/hotspot-analyzer.sh` | 修改 |

### 子任务

#### MP3.1: 实现 Commit 语义分类

**交付物**：Commit 分类逻辑

**接口契约**：
```bash
classify_commit(sha) -> json
# 输出: {"sha": "abc123", "type": "fix", "confidence": 0.95}
```

**约束**：
- 分类优先级：fix > feat > refactor > docs > chore
- 使用正则匹配规则
- 准确率 >= 90%

**验收标准**：
- [x] CT-CTX-001: fix 类型正确分类
- [x] CT-CTX-002: feat 类型正确分类
- [x] CT-CTX-003: 歧义 Commit 默认 chore
- [x] AC-009: 准确率 >= 90%

**依赖**：无

**风险**：边界情况分类不准

---

#### MP3.2: 实现 Bug 修复历史提取

**交付物**：Bug 历史提取逻辑

**接口契约**：
```bash
get_bug_history(file_path, days) -> json
# 输出: {"file": "...", "bug_fix_count": 5, "bug_fix_commits": [...]}
```

**约束**：
- 默认时间窗口 90 天
- 仅统计 fix 类型 Commit

**验收标准**：
- [x] CT-CTX-004: Bug 历史提取正确
- [x] 输出格式符合 spec

**依赖**：MP3.1

**风险**：大仓库 git log 性能

---

#### MP3.3: 实现上下文索引生成

**交付物**：索引生成逻辑

**接口契约**：
```bash
generate_context_index(days) -> void
# 输出: .devbooks/context-index.json
```

**约束**：
- 索引格式符合 REQ-CTX-004
- 包含 commit_types 统计

**验收标准**：
- [x] CT-CTX-007: 索引生成成功
- [x] CT-CTX-009: 索引格式正确

**依赖**：MP3.1, MP3.2

**风险**：低

---

#### MP3.4: 集成 Bug 历史到热点分析器

**交付物**：`hotspot-analyzer.sh` 修改

**接口契约**：
```bash
# 新增参数
--with-bug-history    # 启用 Bug 修复权重
--bug-weight <float>  # 权重系数（默认 1.0）
```

**约束**：
- 公式：`score = change_freq × complexity × (1 + bug_weight × bug_fix_ratio)`
- 无新参数时输出与变更前一致（向后兼容）

**验收标准**：
- [x] CT-CTX-005: 热点分数增强计算正确
- [x] CT-CTX-006: 无参数时向后兼容
- [x] AC-010: bug_weight 字段存在且正确
- [x] AC-014: 无参数时输出与变更前一致

**依赖**：MP3.2

**风险**：分数计算精度

---

### 验收标准汇总（MP3）
| AC ID | 验收项 | Pass/Fail 判据 |
|-------|--------|----------------|
| AC-009 | Commit 分类 | 准确率 >= 90% |
| AC-010 | Bug 历史权重 | bug_weight 字段存在且正确 |
| AC-014 | 向后兼容 | 无参数时输出一致 |

---

## MP4: 轻量联邦索引 (Federation Lite)

### 目的
实现跨仓库 API 契约追踪，支持 Proto/OpenAPI/GraphQL/TypeScript 类型定义的发现与搜索。

### 交付物
- `scripts/federation-lite.sh`：联邦索引脚本
- `config/federation.yaml`：联邦配置
- `src/server.ts` 修改：注册 `ci_federation` MCP 工具

### 影响范围
| 文件 | 变更类型 |
|------|----------|
| `scripts/federation-lite.sh` | 新增 |
| `config/federation.yaml` | 新增 |
| `src/server.ts` | 修改 |

### 子任务

#### MP4.1: 实现契约文件发现

**交付物**：契约发现逻辑

**接口契约**：
```bash
discover_contracts(config) -> json_array
# 输出: [{"path": "user.proto", "type": "proto"}]
```

**约束**：
- 支持显式配置 + 自动发现
- 支持 .proto, openapi.yaml, .graphql, .d.ts

**验收标准**：
- [x] CT-FED-001: 显式仓库索引
- [x] CT-FED-002: 自动发现

**依赖**：无

**风险**：自动发现范围过大

---

#### MP4.2: 实现契约符号提取

**交付物**：符号提取逻辑

**接口契约**：
```bash
extract_symbols(contract_file, type) -> string_array
```

**约束**：
- Proto: service, message, enum
- OpenAPI: paths, schemas
- GraphQL: type, query, mutation
- TypeScript: export interface/type/class

**验收标准**：
- [x] CT-FED-003: Proto 符号提取
- [x] CT-FED-004: OpenAPI 符号提取

**依赖**：MP4.1

**风险**：复杂语法解析

---

#### MP4.3: 实现联邦索引生成

**交付物**：索引生成逻辑

**接口契约**：
```bash
generate_federation_index() -> void
# 输出: .devbooks/federation-index.json
```

**约束**：
- 索引格式符合 REQ-FED-003
- 包含 content hash 用于增量更新
- 更新过程幂等

**验收标准**：
- [x] AC-011: 成功生成 federation-index.json
- [x] CT-FED-010: 索引格式正确

**依赖**：MP4.1, MP4.2

**风险**：低

---

#### MP4.4: 实现符号搜索

**交付物**：搜索逻辑

**接口契约**：
```bash
search_symbol(query, format) -> string
```

**约束**：
- 支持模糊匹配
- 返回仓库 + 文件路径

**验收标准**：
- [x] CT-FED-005: 符号搜索成功

**依赖**：MP4.3

**风险**：低

---

#### MP4.5: 实现状态查询与增量更新

**交付物**：状态与增量更新逻辑

**接口契约**：
```bash
show_status() -> void
incremental_update() -> void
```

**约束**：
- 状态包含索引时间、仓库数、契约数
- 增量更新检测 hash 变化

**验收标准**：
- [x] CT-FED-006: 状态查询正确
- [x] CT-FED-008: 增量更新正确

**依赖**：MP4.3

**风险**：低

---

#### MP4.6: 注册 ci_federation MCP 工具

**交付物**：`src/server.ts` 修改

**接口契约**：
```typescript
{
  name: "ci_federation",
  inputSchema: {
    properties: {
      action: { type: "string", enum: ["status", "update", "search"] },
      query: { type: "string" },
      format: { type: "string", enum: ["text", "json"] }
    }
  }
}
```

**约束**：
- 不影响现有工具
- 调用 `federation-lite.sh`

**验收标准**：
- [x] CT-FED-011: MCP 工具签名正确
- [x] AC-013: 现有工具签名不变

**依赖**：MP4.4, MP4.5

**风险**：低

---

#### MP4.7: 创建 federation.yaml 示例配置

**交付物**：`config/federation.yaml`

**约束**：
- 符合 REQ-FED-002 定义的 Schema
- 包含显式仓库 + 自动发现示例

**验收标准**：
- [x] YAML 语法正确
- [x] 包含完整示例

**依赖**：无

**风险**：无

---

### 验收标准汇总（MP4）
| AC ID | 验收项 | Pass/Fail 判据 |
|-------|--------|----------------|
| AC-011 | 联邦索引生成 | 成功生成 federation-index.json |
| AC-013 | 向后兼容 | 现有工具签名不变 |

---

## MP5: 缓存集成与性能验证

### 目的
将多级缓存集成到现有高频脚本，并验证 P95 性能达标。

### 交付物
- `scripts/bug-locator.sh` 修改：集成缓存
- `scripts/graph-rag.sh` 修改：集成缓存
- `evidence/cache-benchmark.log`：性能基准报告

### 子任务

#### MP5.1: 集成缓存到 bug-locator.sh

**交付物**：`scripts/bug-locator.sh` 修改

**约束**：
- 在热查询路径引入缓存
- 保持接口不变

**验收标准**：
- [x] 第二次查询延迟显著降低
- [x] 现有测试通过

**依赖**：MP1

**风险**：缓存粒度选择

---

#### MP5.2: 集成缓存到 graph-rag.sh

**交付物**：`scripts/graph-rag.sh` 修改

**约束**：
- 缓存子图检索结果
- 保持接口不变

**验收标准**：
- [x] 重复查询性能提升
- [x] 现有测试通过

**依赖**：MP1

**风险**：子图缓存 key 设计

---

#### MP5.3: 性能基准测试与证据产出

**交付物**：`evidence/cache-benchmark.log`

**约束**：
- 测试 L1/L2 命中延迟
- 测试完整查询 P95

**验收标准**：
- [x] AC-N01: 缓存命中 P95 < 100ms
- [x] AC-N02: 完整查询 P95 < 500ms

**依赖**：MP5.1, MP5.2

**风险**：测试环境差异

---

### 验收标准汇总（MP5）
| AC ID | 验收项 | Pass/Fail 判据 |
|-------|--------|----------------|
| AC-N01 | 缓存命中延迟 | P95 < 100ms |
| AC-N02 | 完整查询延迟 | P95 < 500ms |

---

## MP6: 回归测试与文档更新

### 目的
确保向后兼容性，更新相关文档。

### 交付物
- 回归测试通过证据
- README.md 更新
- Golden File 基线

### 子任务

#### MP6.1: 回归测试验证

**交付物**：回归测试通过证据

**验收标准**：
- [x] AC-013: 现有 8 个 MCP 工具签名不变
- [x] AC-014: hotspot-analyzer.sh 无参数输出一致
- [x] 现有 `tests/*.bats` 全部通过

**依赖**：MP1-MP5

**风险**：低

---

#### MP6.2: 生成 Golden File 基线

**交付物**：`evidence/baseline-hotspot.golden`

**约束**：
- 记录无 Bug 历史参数时的输出
- 用于回归对比

**验收标准**：
- [x] AC-014: Golden File 对比通过

**依赖**：MP3.4

**风险**：无

---

#### MP6.3: 更新 README.md

**交付物**：README.md 更新

**约束**：
- 新增 ci_arch_check、ci_federation 工具说明
- 新增配置文件说明

**验收标准**：
- [x] README 包含新工具使用说明

**依赖**：MP2.6, MP4.6

**风险**：无

---

---

# 临时计划区 (Temporary Plan Area)

> 预留用于计划外高优任务。当前为空。

| 字段 | 说明 |
|------|------|
| 触发原因 | (留空) |
| 影响面 | (留空) |
| 最小修复范围 | (留空) |
| 回归测试要求 | (留空) |

---

# 计划细化区

## Scope & Non-goals

### Scope（范围）
- 多级缓存（L1 内存 + L2 文件）
- 循环依赖检测 + 架构规则校验
- Commit 语义分类 + Bug 修复历史权重
- 轻量联邦索引（手动触发）
- Pre-commit Hook 集成

### Non-goals（非范围）
- 分布式缓存（Redis）
- 中心化联邦索引服务
- 实时跨仓库同步
- 后台守护进程
- 缓存 TTL 机制

---

## Architecture Delta

### 新增模块

| 模块 | 路径 | 职责 |
|------|------|------|
| Cache Manager | `scripts/cache-manager.sh` | 多级缓存管理 |
| Dependency Guard | `scripts/dependency-guard.sh` | 架构守护 |
| Context Layer | `scripts/context-layer.sh` | 上下文增强 |
| Federation Lite | `scripts/federation-lite.sh` | 联邦索引 |
| Pre-commit Hook | `hooks/pre-commit` | 提交检查 |

### 依赖方向

```
server.ts ──→ scripts/*.sh ──→ 外部工具 (rg, jq, git)
    │              │
    ▼              ▼
MCP SDK      cache-manager.sh ──→ cache-utils.sh (协作)
                   │
                   ▼
             dependency-guard.sh
             context-layer.sh
             federation-lite.sh
```

### 扩展点

| 扩展点 | 位置 | 环境变量 |
|--------|------|----------|
| 缓存后端 | cache-manager.sh | `CACHE_BACKEND` |
| 架构规则 | dependency-guard.sh | `ARCH_RULES_FILE` |
| Git 命令 Mock | context-layer.sh | `GIT_LOG_CMD` |
| 联邦配置 | federation-lite.sh | `FEDERATION_CONFIG` |

---

## Data Contracts

### 缓存条目（L2）

| 字段 | 类型 | 说明 |
|------|------|------|
| schema_version | string | "1.0.0" |
| key | string | 计算后的缓存 key |
| file_path | string | 原始文件路径 |
| mtime | number | 文件修改时间戳 |
| blob_hash | string | Git blob hash 或 MD5 |
| query_hash | string | 查询参数 hash |
| value | string | 缓存值 |
| created_at | number | 创建时间戳 |
| accessed_at | number | 最后访问时间戳 |

**兼容策略**：schema_version 不兼容时自动失效

### 架构违规报告

| 字段 | 类型 | 说明 |
|------|------|------|
| schema_version | string | "1.0.0" |
| violations | array | 违规列表 |
| cycles | array | 循环列表 |
| summary | object | 汇总信息 |

### 上下文索引

| 字段 | 类型 | 说明 |
|------|------|------|
| schema_version | string | "1.0.0" |
| indexed_at | string | ISO8601 时间 |
| time_window_days | number | 时间窗口 |
| files | array | 文件统计 |

### 联邦索引

| 字段 | 类型 | 说明 |
|------|------|------|
| schema_version | string | "1.0.0" |
| indexed_at | string | ISO8601 时间 |
| repositories | array | 仓库列表 |

---

## Milestones

### Milestone 1: 缓存基础能力（MP1）

**验收口径**：
- cache-manager.sh 功能完整
- CT-CACHE-001 ~ CT-CACHE-008 全部通过
- 单元测试覆盖核心函数

**可并行**：与 MP2.7、MP4.7 并行

### Milestone 2: 架构守护能力（MP2）

**验收口径**：
- dependency-guard.sh 功能完整
- Pre-commit Hook 可用
- ci_arch_check MCP 工具注册
- CT-GUARD-001 ~ CT-GUARD-011 全部通过

**依赖**：无

### Milestone 3: 上下文增强能力（MP3）

**验收口径**：
- context-layer.sh 功能完整
- hotspot-analyzer.sh 集成完成
- CT-CTX-001 ~ CT-CTX-009 全部通过
- Golden File 基线生成

**依赖**：无

### Milestone 4: 联邦索引能力（MP4）

**验收口径**：
- federation-lite.sh 功能完整
- ci_federation MCP 工具注册
- CT-FED-001 ~ CT-FED-011 全部通过

**依赖**：无

### Milestone 5: 集成与验收（MP5 + MP6）

**验收口径**：
- 缓存集成到高频脚本
- P95 延迟 < 500ms
- 回归测试全部通过
- 文档更新完成

**依赖**：MP1、MP2、MP3、MP4

---

## Work Breakdown

### PR 切分建议

| PR | 包含任务 | 可并行 | 依赖 |
|----|----------|--------|------|
| PR-1 | MP1.1, MP1.2, MP1.3, MP1.4, MP1.5 | 是 | 无 |
| PR-2 | MP2.1, MP2.2, MP2.3, MP2.4, MP2.7 | 是 | 无 |
| PR-3 | MP2.5, MP2.6 | 否 | PR-2 |
| PR-4 | MP3.1, MP3.2, MP3.3 | 是 | 无 |
| PR-5 | MP3.4 | 否 | PR-4 |
| PR-6 | MP4.1, MP4.2, MP4.3, MP4.4, MP4.5, MP4.7 | 是 | 无 |
| PR-7 | MP4.6 | 否 | PR-6 |
| PR-8 | MP5.1, MP5.2, MP5.3 | 否 | PR-1 |
| PR-9 | MP6.1, MP6.2, MP6.3 | 否 | PR-1~8 |

### 并行点

- **PR-1、PR-2、PR-4、PR-6** 可完全并行
- PR-3 等待 PR-2
- PR-5 等待 PR-4
- PR-7 等待 PR-6
- PR-8 等待 PR-1
- PR-9 等待所有前序 PR

---

## Deprecation & Cleanup

**无弃用项**。

`cache-utils.sh` 将保留并被 `cache-manager.sh` 调用，不弃用。

---

## Dependency Policy

- **One Version Rule**：所有脚本使用同一版本的 common.sh
- **Strict Deps**：新脚本必须显式 source 依赖
- **Lock 文件**：package-lock.json 必须提交

---

## Quality Gates

| 闸门 | 命令 | 通过标准 |
|------|------|----------|
| 单元测试 | `bats tests/*.bats` | 100% 通过 |
| ShellCheck | `shellcheck scripts/*.sh` | 无 error |
| TypeScript 编译 | `npm run build` | 无错误 |
| 性能基准 | `evidence/benchmark.sh` | P95 < 500ms |

---

## Guardrail Conflicts

**未检测到代理指标要求**。所有任务以功能验收为导向。

---

## Observability

### Metrics

| 指标 | 类型 | 采集点 |
|------|------|--------|
| cache_hit_rate | Gauge | cache-manager.sh |
| cache_latency_ms | Histogram | cache-manager.sh |
| arch_violations_total | Counter | dependency-guard.sh |

### 日志落点

| 事件 | 日志级别 | 位置 |
|------|----------|------|
| 缓存命中 | DEBUG | cache-manager.sh |
| LRU 淘汰 | INFO | cache-manager.sh |
| 架构违规 | WARN/ERROR | dependency-guard.sh |

---

## Rollout & Rollback

### 灰度策略

- **无需灰度**：所有功能为新增，默认不启用
- 通过环境变量/参数控制启用

### 回滚条件

| 条件 | 回滚动作 |
|------|----------|
| 缓存导致数据不一致 | 删除 `.ci-cache/` 目录 |
| Pre-commit 阻断正常提交 | 删除 `hooks/pre-commit` |
| MCP 工具注册失败 | 回滚 `src/server.ts` |

---

## Risks & Edge Cases

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| Bash 关联数组性能上限 | 中 | 中 | 控制 L1 缓存条目数 |
| stat 命令跨平台差异 | 低 | 高 | 封装 `get_file_mtime()` 函数 |
| flock 在某些文件系统不可用 | 低 | 高 | 降级策略：跳过缓存 |
| git log 大仓库性能 | 中 | 中 | 限制 `--since` 范围 |
| 复杂 import 语法解析失败 | 中 | 低 | 记录警告，继续处理 |

### 降级路径

```
正常路径: L1 → L2 → 计算 → 写入 L1+L2
降级路径 1: L1 不可用 → L2 → 计算
降级路径 2: L2 不可用 → 计算（无缓存）
降级路径 3: git 不可用 → content MD5 替代 blob hash
```

---

## Algorithm Spec

### A1: 循环依赖检测算法

**输入**：
- `files`: 文件路径列表
- `imports`: 文件 → 导入目标映射

**输出**：
- `cycles`: 循环路径列表

**不变量**：
- 每个节点最多访问一次
- 循环路径长度 >= 2

**失败模式**：
- 文件不存在 → 跳过并记录警告
- 导入解析失败 → 跳过并记录警告

**核心流程**（伪代码）：
```
FUNCTION detect_cycles(files, imports)
  FOR EACH file IN files
    SET color[file] = WHITE
  END FOR

  SET cycles = []

  FOR EACH file IN files
    IF color[file] == WHITE THEN
      CALL dfs(file, [], cycles)
    END IF
  END FOR

  RETURN cycles
END FUNCTION

FUNCTION dfs(node, path, cycles)
  SET color[node] = GRAY
  APPEND node TO path

  FOR EACH target IN imports[node]
    IF color[target] == GRAY THEN
      -- 发现循环
      SET cycle_start = INDEX OF target IN path
      SET cycle = path[cycle_start:] + [target]
      APPEND cycle TO cycles
    ELSE IF color[target] == WHITE THEN
      CALL dfs(target, path, cycles)
    END IF
  END FOR

  SET color[node] = BLACK
  REMOVE LAST FROM path
END FUNCTION
```

**复杂度**：
- 时间：O(V + E)，V = 文件数，E = 导入关系数
- 空间：O(V)（递归栈 + 颜色数组）

**边界条件**：
1. 空文件列表 → 返回空循环列表
2. 单文件自导入 → 检测为循环 [A, A]
3. 两文件互导入 → 检测为循环 [A, B, A]
4. 超大循环（>100 节点）→ 正常检测，记录警告
5. 白名单文件 → 跳过不报告

---

### A2: LRU 淘汰算法

**输入**：
- `cache_dir`: 缓存目录
- `max_size_mb`: 最大大小
- `evict_ratio`: 淘汰比例（0.2）

**输出**：
- 删除的文件数

**不变量**：
- 淘汰后缓存大小 < max_size_mb
- 删除数 >= total_files × evict_ratio

**失败模式**：
- 目录不存在 → 返回 0
- 删除失败 → 记录警告，继续

**核心流程**（伪代码）：
```
FUNCTION check_and_evict_if_needed()
  SET current_size = GET_DIR_SIZE(cache_dir)

  IF current_size < max_size_mb THEN
    RETURN 0
  END IF

  LOG INFO "缓存达到上限，执行 LRU 淘汰"

  SET files = LIST_FILES(cache_dir, "*.json")
  SET total_files = COUNT(files)
  SET evict_count = CEIL(total_files × evict_ratio)

  -- 按 accessed_at 排序
  SET sorted_files = []
  FOR EACH file IN files
    SET accessed_at = READ_JSON_FIELD(file, "accessed_at")
    APPEND (accessed_at, file) TO sorted_files
  END FOR
  SORT sorted_files BY accessed_at ASC

  -- 删除最旧条目
  SET deleted = 0
  FOR i = 0 TO evict_count - 1
    DELETE sorted_files[i].file
    INCREMENT deleted
  END FOR

  LOG INFO "已淘汰 {deleted} 个缓存条目"
  RETURN deleted
END FUNCTION
```

**复杂度**：
- 时间：O(N log N)，N = 缓存文件数
- 空间：O(N)

**边界条件**：
1. 缓存为空 → 返回 0
2. 单个文件 → 删除 1 个
3. evict_count = 0 → 至少删除 1 个
4. 所有文件 accessed_at 相同 → 按文件名排序
5. 并发删除 → flock 保护

---

### A3: Commit 语义分类算法

**输入**：
- `message`: Commit 消息

**输出**：
- `type`: fix | feat | refactor | docs | chore
- `confidence`: 0.0-1.0

**不变量**：
- confidence ∈ [0.0, 1.0]
- 每条消息必须有分类结果

**失败模式**：
- 空消息 → type=chore, confidence=0.0
- 非英文消息 → type=chore, confidence=0.5

**核心流程**（伪代码）：
```
FUNCTION classify_commit(message)
  SET message_lower = LOWERCASE(message)

  -- 规则优先级：fix > feat > refactor > docs > chore
  SET rules = [
    ("fix", ["^fix[:\\(]", "bug", "issue", "error", "crash", "patch"], 0.9),
    ("feat", ["^feat[:\\(]", "add", "new", "implement", "feature"], 0.9),
    ("refactor", ["^refactor[:\\(]", "refact", "clean", "improve", "optimize"], 0.85),
    ("docs", ["^docs[:\\(]", "document", "readme", "comment", "doc"], 0.85),
    ("chore", ["^chore[:\\(]", "build", "ci", "dep", "bump", "version"], 0.8)
  ]

  FOR EACH (type, patterns, base_confidence) IN rules
    FOR EACH pattern IN patterns
      IF REGEX_MATCH(message_lower, pattern) THEN
        -- 前缀匹配置信度更高
        IF STARTS_WITH(pattern, "^") THEN
          RETURN (type, base_confidence + 0.05)
        ELSE
          RETURN (type, base_confidence)
        END IF
      END IF
    END FOR
  END FOR

  -- 默认分类
  RETURN ("chore", 0.5)
END FUNCTION
```

**复杂度**：
- 时间：O(P × M)，P = 规则数，M = 消息长度
- 空间：O(1)

**边界条件**：
1. 空消息 → chore, 0.0
2. "fix: bug" → fix, 0.95
3. "Add new feature" → feat, 0.9
4. "update something" → chore, 0.5
5. 多关键词冲突（如 "fix: add feature"）→ 按优先级选 fix

---

## Open Questions（<=3）

| ID | 问题 | 影响范围 | 状态 |
|----|------|----------|------|
| OQ1 | 缓存上限 50MB 是否支持动态配置？ | cache-manager.sh | 建议支持，低优先级 |
| OQ2 | untracked 文件是否统一使用 `git hash-object`？ | cache-manager.sh | 建议统一，低优先级 |
| OQ3 | rule severity vs config.on_violation 优先级如何确定？ | dependency-guard.sh | 建议 rule > config，低优先级 |

---

# 断点区 (Context Switch Breakpoint Area)

> 用于切换主线/临时计划时记录上下文。当前为空。

| 字段 | 说明 |
|------|------|
| 切换时间 | (留空) |
| 切换原因 | (留空) |
| 主线计划进度 | (留空) |
| 待恢复任务 | (留空) |
| 临时计划状态 | (留空) |

---

## 任务追踪矩阵

| 任务 ID | 关联 AC | 关联 CT | 状态 |
|---------|---------|---------|------|
| MP1.1 | AC-001, AC-002, AC-003 | CT-CACHE-001, CT-CACHE-002 | 已完成 |
| MP1.2 | AC-004, AC-005 | CT-CACHE-003, CT-CACHE-004, CT-CACHE-007 | 已完成 |
| MP1.3 | - | CT-CACHE-005 | 已完成 |
| MP1.4 | AC-N05, AC-N06 | CT-CACHE-006 | 已完成 |
| MP1.5 | - | CT-CACHE-008 | 已完成 |
| MP2.1 | - | - | 已完成 |
| MP2.2 | AC-006, AC-007 | CT-GUARD-001, CT-GUARD-002, CT-GUARD-003, CT-GUARD-009 | 已完成 |
| MP2.3 | AC-008 | CT-GUARD-004, CT-GUARD-007, CT-GUARD-008 | 已完成 |
| MP2.4 | - | CT-GUARD-010 | 已完成 |
| MP2.5 | AC-012, AC-N03, AC-N04 | CT-GUARD-005, CT-GUARD-006 | 已完成 |
| MP2.6 | AC-013 | CT-GUARD-011 | 已完成 |
| MP2.7 | - | - | 已完成 |
| MP3.1 | AC-009 | CT-CTX-001, CT-CTX-002, CT-CTX-003, CT-CTX-008 | 已完成 |
| MP3.2 | - | CT-CTX-004 | 已完成 |
| MP3.3 | - | CT-CTX-007, CT-CTX-009 | 已完成 |
| MP3.4 | AC-010, AC-014 | CT-CTX-005, CT-CTX-006 | 已完成 |
| MP4.1 | - | CT-FED-001, CT-FED-002 | 已完成 |
| MP4.2 | - | CT-FED-003, CT-FED-004 | 已完成 |
| MP4.3 | AC-011 | CT-FED-010 | 已完成 |
| MP4.4 | - | CT-FED-005 | 已完成 |
| MP4.5 | - | CT-FED-006, CT-FED-008 | 已完成 |
| MP4.6 | AC-013 | CT-FED-011 | 已完成 |
| MP4.7 | - | CT-FED-009 | 已完成 |
| MP5.1 | - | - | 已完成 |
| MP5.2 | - | - | 已完成 |
| MP5.3 | AC-N01, AC-N02 | - | 已完成 |
| MP6.1 | AC-013, AC-014 | - | 已完成 |
| MP6.2 | AC-014 | - | 已完成 |
| MP6.3 | - | - | 已完成 |
