# 验证追溯文档：代码智能能力升级 Phase 2

> **Change ID**: `augment-upgrade-phase2`
> **Version**: 1.0.0
> **Status**: Draft
> **Owner**: Test Owner
> **Created**: 2026-01-14
> **Last Updated**: 2026-01-14

---

## 测试分层策略

| 类型 | 数量 | 覆盖场景 | 预期执行时间 |
|------|------|----------|--------------|
| 单元测试 | 70 | AC-001 ~ AC-014, AC-N01 ~ AC-N06 | < 60s |
| 集成测试 | 8 | Pre-commit Hook, MCP 工具集成 | < 60s |
| 回归测试 | 29 | AC-013, AC-014 (向后兼容) | < 30s |
| 性能测试 | 9 | AC-N01 ~ AC-N04 | < 120s |
| **总计** | **108** | | < 270s |

## 测试环境要求

| 测试类型 | 运行环境 | 依赖 |
|----------|----------|------|
| 单元测试 | Bash + Bats | jq, git |
| 集成测试 | Bash + Node.js | npm run build |
| 性能测试 | Bash | 无外部依赖 |

---

## AC 到 Test ID 追溯矩阵

### 功能验收标准追溯

| AC ID | 验收项 | Test IDs | 测试文件 |
|-------|--------|----------|----------|
| AC-001 | 多级缓存生效 | CT-CACHE-001, CT-CACHE-002, CT-CACHE-003 | cache-manager.bats |
| AC-002 | 缓存 L1（内存）命中 | CT-CACHE-001 | cache-manager.bats |
| AC-003 | 缓存 L2（文件）命中 | CT-CACHE-002 | cache-manager.bats |
| AC-004 | mtime 失效机制 | CT-CACHE-003a | cache-manager.bats |
| AC-005 | blob hash 失效机制 | CT-CACHE-003b | cache-manager.bats |
| AC-006 | 循环依赖检测 | CT-GUARD-001, CT-GUARD-002, CT-GUARD-009 | dependency-guard.bats |
| AC-007 | 循环依赖误报率 | CT-GUARD-009 | dependency-guard.bats |
| AC-008 | 架构规则校验 | CT-GUARD-004, CT-GUARD-007, CT-GUARD-008 | dependency-guard.bats |
| AC-009 | Commit 语义分类 | CT-CTX-001, CT-CTX-002, CT-CTX-003, CT-CTX-008 | context-layer.bats |
| AC-010 | Bug 修复历史权重 | CT-CTX-004, CT-CTX-005 | context-layer.bats |
| AC-011 | 联邦索引生成 | CT-FED-001, CT-FED-002, CT-FED-003, CT-FED-004 | federation-lite.bats |
| AC-012 | Pre-commit 集成 | CT-GUARD-005, CT-GUARD-006 | dependency-guard.bats |
| AC-013 | 向后兼容性 | CT-REG-001 ~ CT-REG-008 | regression.bats |
| AC-014 | hotspot-analyzer.sh 基线 | CT-CTX-006 | context-layer.bats |

### 非功能验收标准追溯

| AC ID | 验收项 | Test IDs | 测试文件 |
|-------|--------|----------|----------|
| AC-N01 | 缓存命中后延迟 P95 < 100ms | CT-PERF-001 | performance.bats |
| AC-N02 | 完整查询 P95 < 500ms | CT-PERF-002 | performance.bats |
| AC-N03 | Pre-commit 耗时（仅 staged）< 2s | CT-PERF-003 | performance.bats |
| AC-N04 | Pre-commit 耗时（含依赖）< 5s | CT-PERF-004 | performance.bats |
| AC-N05 | 缓存磁盘占用 ≤ 50MB | CT-CACHE-006b | cache-manager.bats |
| AC-N06 | LRU 淘汰生效 | CT-CACHE-006 | cache-manager.bats |

---

## 模块 Contract Test 汇总

### Cache Manager (CT-CACHE-xxx)

| Test ID | 场景 | 覆盖 Spec | Pass/Fail 判据 |
|---------|------|-----------|----------------|
| CT-CACHE-001 | L1 命中路径 | SC-CACHE-001 | 延迟 < 10ms，无文件 I/O |
| CT-CACHE-002 | L2 命中路径 | SC-CACHE-002 | 延迟 < 100ms，验证 mtime + blob hash |
| CT-CACHE-003 | 缓存失效重算 | SC-CACHE-003 | 文件变更后返回新结果 |
| CT-CACHE-003a | mtime 失效 | REQ-CACHE-002 | mtime 变化触发失效 |
| CT-CACHE-003b | blob hash 失效 | REQ-CACHE-002 | 内容变化触发失效 |
| CT-CACHE-004 | 写入中检测 | SC-CACHE-004 | mtime 变化 < 1s 跳过缓存 |
| CT-CACHE-005 | 并发写入保护 | SC-CACHE-005 | flock 串行化，无数据损坏 |
| CT-CACHE-006 | LRU 淘汰 | SC-CACHE-006 | 达上限时删除最旧 20% |
| CT-CACHE-006b | 磁盘占用 | AC-N05 | ≤ 50MB |
| CT-CACHE-007 | Git 不可用降级 | SC-CACHE-007 | 降级到 md5 |
| CT-CACHE-008 | Schema 兼容性 | SC-CACHE-008 | 版本不兼容自动失效 |

### Dependency Guard (CT-GUARD-xxx)

| Test ID | 场景 | 覆盖 Spec | Pass/Fail 判据 |
|---------|------|-----------|----------------|
| CT-GUARD-001 | 简单循环检测 | SC-GUARD-001 | 检测 A → B → A |
| CT-GUARD-002 | 多节点循环检测 | SC-GUARD-002 | 检测 A → B → C → D → A |
| CT-GUARD-003 | 白名单排除 | SC-GUARD-003 | 白名单路径不报告 |
| CT-GUARD-004 | 规则违规检测 | SC-GUARD-004 | 违规被正确识别 |
| CT-GUARD-005 | Pre-commit staged only | SC-GUARD-005 | 仅检查 staged 文件 |
| CT-GUARD-006 | Pre-commit with deps | SC-GUARD-006 | 包含一级依赖 |
| CT-GUARD-007 | 警告模式 | SC-GUARD-007 | blocked = false |
| CT-GUARD-008 | 阻断模式 | SC-GUARD-008 | blocked = true, exit 1 |
| CT-GUARD-009 | 误报率 < 5% | SC-GUARD-009 | 测试集误报率统计 |
| CT-GUARD-010 | 违规报告格式 | REQ-GUARD-003 | JSON schema 验证 |
| CT-GUARD-011 | MCP 工具签名 | REQ-GUARD-005 | ci_arch_check 注册 |

### Context Layer (CT-CTX-xxx)

| Test ID | 场景 | 覆盖 Spec | Pass/Fail 判据 |
|---------|------|-----------|----------------|
| CT-CTX-001 | fix 分类 | SC-CTX-001 | type = "fix", confidence >= 0.9 |
| CT-CTX-002 | feat 分类 | SC-CTX-002 | type = "feat", confidence >= 0.9 |
| CT-CTX-003 | 歧义处理 | SC-CTX-003 | 默认 chore, confidence < 0.8 |
| CT-CTX-004 | Bug 历史提取 | SC-CTX-004 | bug_fix_count 正确 |
| CT-CTX-005 | 热点增强 | SC-CTX-005 | 公式计算正确 |
| CT-CTX-006 | 向后兼容 | SC-CTX-006 | 无参数时输出一致 |
| CT-CTX-007 | 索引生成 | SC-CTX-007 | 生成 context-index.json |
| CT-CTX-008 | 准确率 >= 90% | SC-CTX-008 | 测试集准确率统计 |
| CT-CTX-009 | 索引格式 | REQ-CTX-004 | JSON schema 验证 |

### Federation Lite (CT-FED-xxx)

| Test ID | 场景 | 覆盖 Spec | Pass/Fail 判据 |
|---------|------|-----------|----------------|
| CT-FED-001 | 显式仓库索引 | SC-FED-001 | repositories 数量正确 |
| CT-FED-002 | 自动发现 | SC-FED-002 | 发现并索引契约 |
| CT-FED-003 | Proto 符号提取 | SC-FED-003 | symbols 包含 service/message |
| CT-FED-004 | OpenAPI 符号提取 | SC-FED-004 | symbols 包含 paths/schemas |
| CT-FED-005 | 符号搜索 | SC-FED-005 | 返回正确仓库和路径 |
| CT-FED-006 | 状态查询 | SC-FED-006 | 输出索引时间和统计 |
| CT-FED-007 | 路径不存在 | SC-FED-007 | 跳过并警告 |
| CT-FED-008 | 增量更新 | SC-FED-008 | 仅更新变更文件 |
| CT-FED-009 | 配置格式 | REQ-FED-002 | YAML schema 验证 |
| CT-FED-010 | 索引格式 | REQ-FED-003 | JSON schema 验证 |
| CT-FED-011 | MCP 工具签名 | REQ-FED-005 | ci_federation 注册 |

### 回归测试 (CT-REG-xxx)

| Test ID | 场景 | 覆盖 AC | Pass/Fail 判据 |
|---------|------|---------|----------------|
| CT-REG-001 | ci_search 可用 | AC-013 | 工具注册存在 |
| CT-REG-002 | ci_call_chain 可用 | AC-013 | 工具注册存在 |
| CT-REG-003 | ci_bug_locate 可用 | AC-013 | 工具注册存在 |
| CT-REG-004 | ci_complexity 可用 | AC-013 | 工具注册存在 |
| CT-REG-005 | ci_graph_rag 可用 | AC-013 | 工具注册存在 |
| CT-REG-006 | ci_index_status 可用 | AC-013 | 工具注册存在 |
| CT-REG-007 | ci_hotspot 可用 | AC-013 | 工具注册存在 |
| CT-REG-008 | ci_boundary 可用 | AC-013 | 工具注册存在 |

### 性能测试 (CT-PERF-xxx)

| Test ID | 场景 | 覆盖 AC | Pass/Fail 判据 |
|---------|------|---------|----------------|
| CT-PERF-001 | 缓存命中延迟 | AC-N01 | P95 < 100ms |
| CT-PERF-002 | 完整查询延迟 | AC-N02 | P95 < 500ms |
| CT-PERF-003 | Pre-commit (staged) | AC-N03 | P95 < 2s |
| CT-PERF-004 | Pre-commit (with deps) | AC-N04 | P95 < 5s |
| CT-PERF-005 | 循环检测性能 | - | < 5s (50 文件) |
| CT-PERF-006 | 联邦索引性能 | - | < 10s (3 仓库) |

---

## 测试文件清单

| 文件路径 | 测试数量 | 模块 |
|----------|----------|------|
| `tests/cache-manager.bats` | 15 | Cache Manager |
| `tests/dependency-guard.bats` | 17 | Dependency Guard |
| `tests/context-layer.bats` | 16 | Context Layer |
| `tests/federation-lite.bats` | 22 | Federation Lite |
| `tests/regression.bats` | 29 | 回归测试 |
| `tests/performance.bats` | 9 | 性能测试 |
| **总计** | **108** | |

---

## 测试隔离要求

- [x] 每个测试必须独立运行，不依赖其他测试的执行顺序
- [x] 使用 `setup_temp_dir`/`cleanup_temp_dir` 管理临时目录
- [x] 禁止使用共享的可变状态
- [x] 缓存测试使用独立 `CACHE_DIR`
- [x] Git 操作使用临时仓库

## 测试稳定性要求

- [x] 禁止提交 `test.only` / `@test.only`
- [x] 性能测试允许 ±20% 波动
- [x] 超时设置：单元测试 < 5s，集成测试 < 30s
- [x] 外部命令（git, jq）Mock 或条件跳过

---

## DoD 闸门

| 闸门 | 验证命令 | 通过标准 |
|------|----------|----------|
| 单元测试 | `bats tests/*.bats` | 100% 通过 |
| 静态检查 | `shellcheck scripts/*.sh` | 无 error |
| TypeScript 编译 | `npm run build` | 无错误 |
| 性能基准 | `bats tests/performance.bats` | 全部通过 |
| 回归测试 | `bats tests/regression.bats` | 100% 通过 |

---

## Red 基线记录

**Red 基线建立时间**: 2026-01-14

**预期失败测试数**: 108（全部新增测试）

**证据存放位置**: `dev-playbooks/changes/augment-upgrade-phase2/evidence/red-baseline/`

### Red 基线摘要

| 模块 | 总测试数 | 预期跳过 | 跳过原因 |
|------|----------|----------|----------|
| Cache Manager | 15 | 15 | 脚本未实现 |
| Dependency Guard | 17 | 15 | 脚本未实现 |
| Context Layer | 16 | 14 | 脚本未实现 |
| Federation Lite | 22 | 22 | 脚本未实现 |
| Regression | 29 | 0 | 现有工具已存在 |
| Performance | 9 | 7 | 脚本未实现 |
| **总计** | **108** | **73** | |

---

## 证据产出检查清单

- [x] `evidence/red-baseline/test-2026-01-14.log` - Red 基线测试日志
- [x] `evidence/red-baseline/summary.md` - 失败摘要
- [x] `evidence/green-final/` - Green 阶段证据
- [x] `evidence/green-final/test-summary-20260114.md` - 测试摘要报告
- [x] `evidence/green-final/bats-full-*.log` - 完整测试日志
- [x] `evidence/cache-benchmark.log` - 缓存性能报告
- [x] `evidence/cycle-detection.log` - 循环检测报告
- [x] `evidence/baseline-hotspot.golden` - 热点分析基线

---

## 当前测试状态（2026-01-14 更新）

**测试统计**:
| 指标 | 数量 |
|------|------|
| 总测试数 | 302 |
| 通过 | 274 |
| 失败 | 28 |
| 跳过 | 81 |

**路径修复**: 已修复 16 个测试文件中的脚本路径问题，使用 `PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."` 获取项目根目录。

**失败测试分析**:
- boundary-detector.bats: 12 失败（边界检测功能未完全实现）
- data-flow-tracing.bats: 5 失败（数据流追踪功能未完全实现）
- hotspot-analyzer.bats: 3 失败（参数和输出格式问题）
- intent-analysis.bats: 6 失败（意图分析功能未完全实现）
- context-layer.bats: 1 失败（--with-bug-history 未完全实现）
- performance.bats: 1 失败（循环检测性能测试）
