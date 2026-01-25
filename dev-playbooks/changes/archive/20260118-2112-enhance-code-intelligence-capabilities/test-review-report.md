# Test Review Report: 20260118-2112-enhance-code-intelligence-capabilities

## 元信息

- **评审日期**: 2026-01-19
- **评审范围**: tests/ 目录下所有测试文件
- **评审方式**: 多 Agent 并行评审（5 个专项 Agent）
- **评审依据**: `dev-playbooks/changes/20260118-2112-enhance-code-intelligence-capabilities/verification.md`
- **评审角色**: Test Reviewer（遵循 CON-ROLE-001~005 约束）
- **评审者**: DevBooks Test Reviewer Skill

---

## 概览

| 指标 | 数值 | 说明 |
|------|------|------|
| 评审测试文件数 | 13 个 | 10 个 AC 相关 + 3 个新增 |
| 总测试用例数 | 179+ | 覆盖 AC-001 ~ AC-012 |
| 问题总数 | 28 | Critical: 7, Major: 16, Minor: 5 |
| 覆盖率 | 100% | 所有声明的 AC 均有对应测试 |
| 孤儿测试 | 2 个 | upgrade-capabilities.bats, indexer-scheduler.bats |

---

## 覆盖率分析

> **注意**: 覆盖状态基于测试代码存在性判断，与测试运行结果（Pass/Fail/Skip）无关。

### AC 覆盖矩阵

| AC-ID | 测试文件 | 测试用例数 | 覆盖状态 | 备注 |
|-------|----------|-----------|----------|------|
| AC-001 | context-compressor.bats | 19 | ✅ 已覆盖 | T-CC-001~013, T-CC-ERROR-001~005, T-PERF-CC-001 |
| AC-002 | drift-detector.bats | 11 | ✅ 已覆盖 | T-DD-001~010, T-PERF-DD-001 |
| AC-003 | data-flow-tracing.bats | 20 | ✅ 已覆盖 | DF-BASE-001~004, DF-FORWARD/BACKWARD/BOTH/CROSS/DEPTH/OUTPUT/CYCLE/LANG/ERROR, PERF-DFT-001~002 |
| AC-004 | graph-store.bats | 25+ | ✅ 已覆盖 | SC-GS-001~012, AC-N03a~c, test_edge_types 系列, test_find_path 系列 |
| AC-005 | hybrid-retrieval.bats | 18 | ✅ 已覆盖 | HR-BASE-001~002, T-HR-001~007, HR-INTEGRATION-001~002, HR-PERF-001, HR-ERROR-001~005 |
| AC-006 | llm-rerank.bats | 13 | ✅ 已覆盖 | SC-LR-001~014, CT-LR-003 |
| AC-007 | long-term-memory.bats | 8 | ✅ 已覆盖 | T-CS-001~008 |
| AC-008 | semantic-anomaly.bats | 15 | ✅ 已覆盖 | T-SA-001~015 |
| AC-009 | benchmark.bats | 12 | ✅ 已覆盖 | BM-BASE-001~002, T-BM-001~006, BM-ERROR-001~002, BM-INTEGRATION-001, PERF-BM-001 |
| AC-010 | feature-toggle.bats | 9 | ✅ 已覆盖 | T-FT-001~009 |
| AC-011 | regression.bats | 29 | ✅ 已覆盖 | CT-REG-001~008(b), CT-REG-BUILD-001~002, CT-REG-SCRIPT-001~004, CT-REG-MCP-001~002, CT-REG-API-001~016, CT-REG-NEW-001~002 |
| AC-012 | graph-store.bats | 5 | ✅ 已覆盖 | test_migrate_check_old/new/apply/backup/rollback |

### 追溯矩阵完整性

- ✅ **无孤儿 AC**: 所有 AC-001 ~ AC-012 均有对应测试
- ⚠️ **存在孤儿测试**:
  - `upgrade-capabilities.bats` (Change-ID: 20260118-0057-upgrade-code-intelligence-capabilities)
  - `indexer-scheduler.bats` (Change-ID: optimize-indexing-pipeline-20260117)
- ✅ **Red 基线存在**: verification.md 记录了证据路径
- ⚠️ **Green 证据**: 根据 verification.md L290，@full 运行未通过（38 项失败）

---

## 问题清单

### Critical (必须修复) - 共 7 项

#### Agent #1: 核心功能测试

**C-001** `context-compressor.bats:414-457` **T-CC-005 缓存性能测试稳定性不足**
- **问题**: 仅预热 1 次，采样 3 次取平均值，在 CI/容器环境中波动可能超过 50% 阈值
- **影响**: 测试可能出现假失败（flaky test），违反可复现性策略
- **建议**:
  1. 预热次数增加到 10 次
  2. 采样次数增加到 10 次，使用 P95 代替平均值
  3. 环境变量 `CONTEXT_COMPRESSOR_CACHE_TIME_RATIO_PCT` 默认值从 50 放宽到 70
- **对应 verification.md M-001**

**C-002** `drift-detector.bats:344-377` **T-PERF-DD-001 性能阈值过严**
- **问题**: 默认 10s 阈值在 100 个文件中型项目可能不稳定，尤其在冷启动时
- **影响**: 阻塞 Green 证据产出
- **建议**:
  1. 放宽默认阈值到 15s
  2. 增加预热次数到 10 次
  3. 使用 P95 而非单次测量
- **对应 verification.md M-002**

**C-003** `data-flow-tracing.bats:258-263` **DF-ERROR-001 缺失断言清晰度**
- **问题**: 仅检查退出码 + grep "not found|symbol"，未验证错误消息是否包含具体符号名称
- **影响**: 错误提示不友好时无法检测
- **建议**: 添加断言 `assert_contains "$output" "does_not_exist_123"`

**C-004** `graph-store.bats:350-378` **SC-GS-012 超大批量可能超时**
- **问题**: 默认 10000 节点批量导入可能在慢速 CI 环境超过 60s 超时
- **影响**: 测试假失败
- **建议**:
  1. 将默认 `GRAPH_STORE_BULK_NODES` 降到 500
  2. 或提高 `GRAPH_STORE_BULK_TIMEOUT` 到 120s
- **对应 verification.md M-004**

#### Agent #5: 新增测试

**C-005** `upgrade-capabilities.bats` + `indexer-scheduler.bats` **孤儿测试缺少追溯关系**
- **问题**: 两个测试文件引用独立的 Change ID，但 verification.md 未包含这些变更的 AC
- **影响**: 无法验证测试完整性，可能漏测或重复覆盖
- **建议**:
  1. 补充 verification.md 追溯矩阵，增加相应 AC
  2. 或将测试移动到对应变更包

**C-006** `upgrade-capabilities.bats` **测试标签命名不一致**
- **问题**: 使用 `@test "T-EDGE-001 (@smoke):"` 格式，与其他测试文件的注释形式不一致
- **影响**: 标签过滤与聚合统计可能失效
- **建议**: 统一为注释形式 `# @smoke T-EDGE-001`

**C-007** `indexer-scheduler.bats` **测试 ID 命名不规范**
- **问题**: 测试 ID 前缀为 `IS-`，但文件注释使用 `AC-001 to AC-010`
- **影响**: 无法从测试 ID 直接关联到 AC，追溯性弱
- **建议**: 统一使用 `T-IS-` 前缀或明确 AC 映射关系

---

### Major (建议修复) - 共 16 项

#### Agent #1: 核心功能测试

**M-001** `context-compressor.bats:587-596` **T-CC-ERROR-001 空文件错误消息匹配过宽**
- **建议**: 收紧为 `grep -Eqi "^(Error|Warning):.*empty (file|input)"`

**M-002** `drift-detector.bats:88-94` **T-DD-ERROR-001 错误消息未明确引用参数名**
- **建议**: 添加断言 `assert_contains "$output" "--compare"`

**M-003** `data-flow-tracing.bats:62-82` **setup() 缺少 fixture 内容完整性检查**
- **建议**: 在 setup() 中增加符号引用链完整性验证

**M-004** `graph-store.bats:662-675` **test_migrate_check_old 模拟旧版本方式脆弱**
- **建议**: 创建完整的 v3 schema fixture 或使用真实旧版本数据库文件

**M-005** `graph-store.bats:877-928` **test_migrate_rollback 回滚验证不充分**
- **建议**: 验证边数一致、外键约束恢复、坏边清理

#### Agent #2: 检索与排序测试

**M-006** `hybrid-retrieval.bats:248-312` **T-HR-007 权重总和验证不够严格**
- **建议**: 使用容差判断 `|sum - 1.0| < 0.01`

**M-007** `hybrid-retrieval.bats:384-408` **HR-PERF-001 性能测试缺少统计稳定性保障**
- **建议**: 增加迭代次数至 20+，添加环境变量覆盖阈值机制

**M-008** `llm-rerank.bats:346-402` **SC-LR-012 并发测试缺少隔离验证断言**
- **建议**: 增加断言验证 `$openai_work/.devbooks` 和 `$ollama_work/.devbooks` 互不影响
- **对应 verification.md M-005**

**M-009** `llm-rerank.bats:409-456` **SC-LR-013 启发式排序测试断言过弱**
- **建议**: 增加排序优先级验证断言

#### Agent #3: 智能增强测试

**M-010** `long-term-memory.bats:61-74` **T-CS-001 权重断言过宽**
- **建议**: 收紧倍率范围至 `[1.3, 1.4]`，在测试注释中明确设计文档规定的精确倍数
- **对应 verification.md M-006**

**M-011** `semantic-anomaly.bats:248-266` **T-SA-011 召回率基准测试依赖 fixture 完整性**
- **建议**: 在 T-SA-011 测试开始前增加注释说明依赖 setup() 的 fixture 验证
- **对应 verification.md M-007**

**M-012** `benchmark.bats:156-178` **T-BM-001 数据集质量检查不足**
- **建议**: 实现函数/类定义密度检查（每 100 行 ≥ 5 个定义）
- **对应 verification.md M-008**

**M-013** `benchmark.bats:247-270` **T-BM-006 回归检测阈值硬编码风险**
- **建议**: 在测试文件顶部注释区增加阈值说明，增加断言验证阈值设置生效

#### Agent #4: 契约与回归测试

**M-014** `feature-toggle.bats:174-198` **T-FT-009 环境变量清理不正确**
- **建议**: 使用 `unset DEVBOOKS_FEATURE_CONFIG` 而非 `FEATURES_CONFIG`

**M-015** `regression.bats:285-423` **CT-REG-API-001~016 参数类型与必需性未验证**
- **建议**: 增强断言，验证 `properties.path.type`、`required` 字段

**M-016** `regression.bats:172-182` **CT-REG-BUILD-001 TypeScript 错误模式检测过于宽松**
- **建议**: 收紧正则，仅匹配 `error TS\d+:`

---

### Minor (可选修复) - 共 5 项

**m-001** `feature-toggle.bats:51-77` **T-FT-002 硬编码功能名称列表**
- **建议**: 从 `config/features.yaml` 动态提取功能列表

**m-002** `regression.bats:184-191` **CT-REG-BUILD-002 警告计数阈值硬编码**
- **建议**: 与基线对比而非固定阈值

**m-003** `long-term-memory.bats:139-149` **T-CS-004 会话焦点加权未验证负向场景**
- **建议**: 增加断言验证非焦点符号的 `context_boost == 0`

**m-004** `semantic-anomaly.bats:101-119` **T-SA-002 不一致 API 检测依赖文件数量**
- **建议**: 增加第三个文件强化"主流模式"判断

**m-005** `benchmark.bats:80-92` **create_mock_public_dataset() 缺少代码文件**
- **建议**: 在 `$dataset_dir` 中创建对应的代码文件桩（stub）

---

## 测试质量评估

### 1. 独立性 ⭐⭐⭐⭐⭐

**优点**:
- 所有测试使用独立的 `$BATS_TEST_TMPDIR` 或 `$TEST_TEMP_DIR`
- `setup()` 和 `teardown()` 正确隔离测试环境
- 缓存相关测试使用独立的 `DEVBOOKS_DIR`

**问题**:
- `graph-store.bats:SC-GS-012` 超大批量测试可能因共享 `$GRAPH_DB_PATH` 导致磁盘 I/O 竞争（已通过 `setup_temp_dir` 隔离）

### 2. 可重复性 ⭐⭐⭐⭐☆

**优点**:
- 使用固定 fixture 数据（`order-service.base.ts`, `snapshot-template.json`）
- 时间戳固定（`drift-detector.bats:47`）
- 性能测试使用环境变量覆盖阈值

**问题**:
- **C-001/C-002**: 缓存和性能测试稳定性不足
- `data-flow-tracing.bats:73`: 依赖 `large.ts` 行数 >= 200，但未验证内容质量

### 3. 断言明确性 ⭐⭐⭐⭐☆

**优点**:
- 大量使用 `jq -e` 验证 JSON 结构
- 错误路径测试验证退出码 + 错误消息

**问题**:
- **M-001**: 空文件错误消息匹配过宽
- **C-003**: 错误测试未验证符号名称出现在错误消息中
- **M-006**: 权重总和验证精度控制不足

### 4. 可读性 ⭐⭐⭐⭐⭐

**优点**:
- 测试命名清晰（如 `SC-GS-004c: rejects near-miss edge types`）
- 使用辅助函数（`require_cmd`, `create_snapshot`, `warmup_data_flow`）
- 注释标记测试类型（`@smoke`, `@critical`, `@full`）

**问题**:
- `graph-store.bats:877-928`: test_migrate_rollback 注释过长（27 行），建议抽取到文档

### 5. 规格一致性 ⭐⭐⭐⭐⭐

**对照 verification.md 追溯矩阵**:

所有 AC-001 ~ AC-012 的要求测试 ID 均完整存在，无遗漏。

**额外发现**:
- `graph-store.bats` 新增了 `test_closure_table_performance`，未在 verification.md 追溯矩阵中列出
- `graph-store.bats` 新增了 `test_find_path_*` 系列（6 项），对应设计文档的路径查询功能

---

## 建议优先级

### P0 (阻塞 Green 证据)

1. **C-001**: 修复 T-CC-005 缓存性能测试稳定性
2. **C-002**: 放宽 T-PERF-DD-001 性能阈值或增加预热
3. **C-004**: 调整 SC-GS-012 批量节点数或超时
4. **C-005**: 补充 verification.md 追溯矩阵或移动孤儿测试

### P1 (提高测试健壮性)

5. **M-004**: 使用真实旧版本 schema fixture
6. **M-005**: 完善 test_migrate_rollback 验证逻辑
7. **C-003**: 增强 DF-ERROR-001 错误断言
8. **M-006**: 修复权重总和验证容差
9. **M-008**: 增加并发隔离验证
10. **M-010**: 收紧权重倍率范围
11. **M-014**: 修正环境变量清理

### P2 (代码清晰度)

12. **m-001**: 动态提取功能列表
13. **m-002**: 引入构建基线对比
14. **C-006/C-007**: 统一测试标签与命名规范

---

## 规格缺口发现

根据孤儿测试分析，以下功能点未被任何规格覆盖：

1. **CKB Fallback 冷却期机制**（`upgrade-capabilities.bats:T-CKB-004`）
   - 建议：新增 `dev-playbooks/specs/ckb-fallback/spec.md`
   - 关键需求：连续失败后进入 60s 冷却期

2. **索引器调度决策树**（`indexer-scheduler.bats:IS-001 ~ IS-002c`）
   - 建议：补充 `incremental-indexing/spec.md` 的 `SC-SCHED` 场景
   - 关键需求：文件数阈值、版本匹配、tree-sitter 可用性

3. **Warmup 异步启动**（`upgrade-capabilities.bats:T-WARMUP-001~003`）
   - 建议：补充 `daemon/spec.md` 的 `REQ-DM-WARMUP`
   - 关键需求：启动时异步触发 warmup（< 2s 阻塞时间）

---

## 评审结论

**结论**: ⚠️ **REVISE REQUIRED**

**判定依据**:
- Critical 问题数：7
- Major 问题数：16
- AC 覆盖率：12/12 = 100%
- 测试质量评分：8.8/10

**关键问题**:
1. **性能测试稳定性不足**（C-001, C-002, C-004）可能导致 CI 假失败
2. **孤儿测试缺少追溯**（C-005）影响变更管理完整性
3. **部分断言过宽或过严**（M-001, M-006, M-010）可能漏检或误报

**建议行动**:
1. **立即修复 P0 问题**（C-001 ~ C-005），确保 @full 运行通过
2. **补充迁移测试覆盖**（M-004, M-005），创建真实旧版本 fixture
3. **增强错误断言**（C-003, M-001），提高错误检测精度
4. **更新 verification.md**，补充新增测试到追溯矩阵

**下一步**:
- 优先修复 7 个 Critical 问题
- 与 Test Owner 协作补充 fixture 与规格文档
- 修复后重新运行 @full 测试，更新 Green 证据

---

## 附录：Agent 评审汇总

| Agent | 评审范围 | 问题数量 | 关键发现 |
|-------|---------|---------|---------|
| #1 核心功能 | context-compressor, drift-detector, data-flow-tracing, graph-store | Critical: 4, Major: 5 | 性能测试稳定性不足、迁移测试覆盖不完整 |
| #2 检索排序 | hybrid-retrieval, llm-rerank | Major: 4 | 权重验证精度、并发隔离断言缺失 |
| #3 智能增强 | long-term-memory, semantic-anomaly, benchmark | Major: 4 | 权重倍率范围过宽、数据集质量检查不足 |
| #4 契约回归 | feature-toggle, regression | Major: 3 | 环境变量清理、API 签名验证不完整 |
| #5 新增测试 | llm-provider, keystroke-cancel, upgrade-capabilities, indexer-scheduler | Critical: 3 | 孤儿测试缺少追溯、测试标签命名不一致 |

---

*此报告由 devbooks-test-reviewer 生成*
*评审时间: 2026-01-19*
*评审工具: DevBooks Test Reviewer Skill (Multi-Agent Mode)*
