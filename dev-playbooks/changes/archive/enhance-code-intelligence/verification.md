# Verification: enhance-code-intelligence

> **Change ID**: enhance-code-intelligence
> **Owner**: Test Owner
> **Created**: 2026-01-11
> **Status**: Red Baseline
> **Last Run**: 2026-01-11
> **Last Updated**: 2026-01-11 (v2 - added boundary/perf tests)

---

## 测试分层策略

| 类型 | 数量 | 覆盖场景 | 预期执行时间 |
|------|------|----------|--------------|
| 单元测试 | 42 | AC-001, AC-004, AC-005, AC-010 | < 5s |
| 集成测试 | 35 | AC-002, AC-003, AC-006 | < 30s |
| 性能测试 | 12 | AC-001, AC-007 | < 60s |
| 契约测试 | 24 | AC-008 | < 10s |
| 回归测试 | 16 | AC-009 | < 30s |
| 边界测试 | 35 | ALL | < 10s |
| 参数验证测试 | 28 | ALL | < 5s |

**总计**: 192 个测试用例

---

## 测试环境要求

| 测试类型 | 运行环境 | 依赖 |
|----------|----------|------|
| 单元测试 | Bash + bats-core | 无外部依赖 |
| 集成测试 | Bash + Node.js | index.scip |
| 性能测试 | Bash + time | Git repo |
| 契约测试 | Node.js | MCP Server |
| 边界测试 | Bash + bats-core | tests/helpers/common.bash |

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `EXPECT_RED` | `true` | Red 基线阶段设为 true，Green 阶段设为 false |
| `CKB_DISABLED` | `false` | 测试 CKB 降级行为时设为 true |
| `FORCE_INCREMENTAL_FAIL` | `false` | 测试增量索引回退时设为 true |

---

## 追溯矩阵（Traceability Matrix）

| AC ID | 验收项 | 测试文件 | 测试组 | 测试数 | 状态 |
|-------|--------|----------|--------|--------|------|
| AC-001 | 热点算法输出正确 | tests/hotspot-analyzer.bats | HS-* | 20 | RED |
| AC-002 | 意图分析 4 维信号 | tests/intent-analysis.bats | IA-* | 11 | RED |
| AC-003 | 子图检索保留边关系 | tests/subgraph-retrieval.bats | SR-* | 21 | RED |
| AC-004 | 边界识别正确 | tests/boundary-detector.bats | BD-* | 24 | RED |
| AC-005 | Pattern Learner 学习 | tests/pattern-learner.bats | PL-* | 19 | RED |
| AC-006 | 数据流追踪 | tests/data-flow-tracing.bats | DF-* | 23 | RED |
| AC-007 | 增量索引 | tests/incremental-indexing.bats | II-* | 23 | RED |
| AC-008 | MCP 工具兼容 | tests/mcp-contract.bats | CT-* | 24 | RED |
| AC-009 | Bug 定位回归 | tests/bug-locator.bats | BL-*, REGRESSION-*, PERF-*, BASELINE-* | 16 | GREEN |
| AC-010 | 功能开关可用 | tests/feature-toggle.bats | FT-* | 11 | RED |

---

## 测试用例详情

### AC-001: 热点算法输出正确

**测试文件**: `tests/hotspot-analyzer.bats`

| 测试 ID | 场景 | 输入 | 期望输出 | Spec 引用 |
|---------|------|------|----------|-----------|
| HS-001 | 脚本存在且可执行 | `hotspot-analyzer.sh` | 退出码 0 | - |
| HS-002 | 帮助信息显示 | `--help` | 包含 "Hotspot Analyzer" | - |
| HS-003 | 默认返回 Top-20 | 无参数 | JSON 包含 20 个条目 | Scenario: Calculate hotspot for project |
| HS-004 | 自定义 top_n | `--top-n 10` | JSON 包含 10 个条目 | Scenario: Invoke ci_hotspot with custom top_n |
| HS-005 | 热点分数计算公式 | 已知文件 | score = frequency * complexity | Requirement: Hotspot Calculation |
| HS-006 | 性能：< 5s | 项目目录 | duration_ms < 5000 | Scenario: Calculate hotspot for project |

### AC-004: 边界识别正确

**测试文件**: `tests/boundary-detector.bats`

| 测试 ID | 场景 | 输入 | 期望输出 | Spec 引用 |
|---------|------|------|----------|-----------|
| BD-001 | 脚本存在且可执行 | `boundary-detector.sh` | 退出码 0 | - |
| BD-002 | 检测库代码 | `node_modules/lodash/index.js` | type: library | Scenario: Detect library code |
| BD-003 | 检测生成代码 | `dist/server.js` | type: generated | Scenario: Detect generated code |
| BD-004 | 检测用户代码 | `src/server.ts` | type: user | Scenario: Detect user code |
| BD-005 | 检测配置文件 | `config/boundaries.yaml` | type: config | Scenario: Detect config file |
| BD-006 | Glob 模式匹配 | `src/vendor/legacy/utils.js` | type: library | Scenario: Match glob pattern |

### AC-002: 意图分析 4 维信号

**测试文件**: `tests/intent-analysis.bats`

| 测试 ID | 场景 | 输入 | 期望输出 | Spec 引用 |
|---------|------|------|----------|-----------|
| IA-001 | 显式信号提取 | prompt: "fix auth bug" | 包含 explicit 标签 | Scenario: Analyze intent with explicit keywords |
| IA-002 | 隐式信号提取 | file: src/auth.ts, line: 42 | 包含 implicit 标签 | Scenario: Analyze intent with implicit context |
| IA-003 | 历史信号提取 | 最近 5 次编辑 | 包含 historical 标签 | Scenario: Analyze intent with historical context |
| IA-004 | 代码信号提取 | function: validateToken | 包含 code 标签 | Scenario: Analyze intent with code context |

### AC-003: 子图检索保留边关系

**测试文件**: `tests/subgraph-retrieval.bats`

| 测试 ID | 场景 | 输入 | 期望输出 | Spec 引用 |
|---------|------|------|----------|-----------|
| SR-001 | 子图包含调用边 | symbol: handleToolCall | 包含 --calls--> | Scenario: Retrieve subgraph with call edges |
| SR-002 | 子图包含引用边 | symbol: TOOLS | 包含 --refs--> | Scenario: Retrieve subgraph with reference edges |
| SR-003 | 深度控制 | --depth 3 | 深度不超过 3 | Scenario: Subgraph depth control |
| SR-004 | CKB 不可用降级 | CKB offline | degraded: true | Scenario: CKB unavailable fallback |

### AC-005: Pattern Learner 学习

**测试文件**: `tests/pattern-learner.bats`

| 测试 ID | 场景 | 输入 | 期望输出 | Spec 引用 |
|---------|------|------|----------|-----------|
| PL-001 | 脚本存在且可执行 | `pattern-learner.sh` | 退出码 0 | - |
| PL-002 | 生成 patterns 文件 | 项目目录 | 存在 .devbooks/learned-patterns.json | Scenario: Persist learned patterns |
| PL-003 | 置信度阈值过滤 | 低置信度模式 | 不产生警告 | Scenario: Ignore low confidence patterns |
| PL-004 | 自定义阈值 | --confidence-threshold 0.90 | 0.87 不警告 | Scenario: Custom confidence threshold |

### AC-006: 数据流追踪

**测试文件**: `tests/data-flow-tracing.bats`

| 测试 ID | 场景 | 输入 | 期望输出 | Spec 引用 |
|---------|------|------|----------|-----------|
| DF-001 | 参数流追踪 | --trace-data-flow | 包含 path 数组 | Scenario: Trace parameter flow |
| DF-002 | 返回值流追踪 | --trace-data-flow | 包含 sink | Scenario: Trace return value flow |
| DF-003 | 默认行为兼容 | 无 --trace-data-flow | 仅调用链 | Scenario: Default behavior without flag |
| DF-004 | CLI 参数支持 | --help | 包含 --trace-data-flow | Requirement: Data Flow CLI Option |

### AC-007: 增量索引

**测试文件**: `tests/incremental-indexing.bats`

| 测试 ID | 场景 | 输入 | 期望输出 | Spec 引用 |
|---------|------|------|----------|-----------|
| II-001 | 单文件增量更新 | 修改 1 文件 | duration_ms < 1000 | Scenario: Incremental update single file |
| II-002 | SCIP 缺失时报错 | 无 index.scip | 错误提示 | Scenario: Full reindex when SCIP missing |
| II-003 | 无变更时跳过 | 无文件变更 | "索引已是最新" | Scenario: No changes detected |

### AC-008: MCP 工具兼容

**测试文件**: `tests/mcp-contract.bats`

| 测试 ID | 场景 | 输入 | 期望输出 | Spec 引用 |
|---------|------|------|----------|-----------|
| CT-001 | ci_hotspot 输入格式 | 有效参数 | 无错误 | CT-MCP-001 |
| CT-002 | ci_hotspot 输出格式 | 调用 | schema_version: 1.0.0 | CT-MCP-002 |
| CT-003 | ci_boundary 输入格式 | path 参数 | 无错误 | CT-MCP-003 |
| CT-004 | ci_boundary 输出格式 | 调用 | type + confidence | CT-MCP-004 |
| CT-005 | 现有工具回归 | 6 个工具 | 全部可用 | CT-MCP-005 |
| CT-006 | 功能开关禁用 | enhanced_hotspot: false | 功能禁用 | CT-CFG-003 |

### AC-010: 功能开关可用

**测试文件**: `tests/feature-toggle.bats`

| 测试 ID | 场景 | 输入 | 期望输出 | Spec 引用 |
|---------|------|------|----------|-----------|
| FT-001 | 默认启用 | 无配置 | 功能可用 | - |
| FT-002 | 禁用热点 | enhanced_hotspot: false | 热点功能禁用 | AC-010 |
| FT-003 | 禁用边界 | boundary_detection: false | 边界功能禁用 | AC-010 |
| FT-004 | 禁用所有 | 全部 false | 所有新功能禁用 | AC-010 |

---

## DoD 闸门映射

| 闸门 | 验证命令 | AC 引用 | 状态 |
|------|----------|---------|------|
| TypeScript 编译 | `npm run build` | - | PENDING |
| ShellCheck 检查 | `npm run lint` | - | PENDING |
| 回归测试 | `bats tests/bug-locator.bats` | AC-009 | GREEN |
| 单元测试 | `bats tests/*.bats` | AC-001, AC-004 | RED |
| 契约测试 | `bats tests/mcp-contract.bats` | AC-008 | RED |
| 性能测试 | `bats tests/*-performance.bats` | AC-001, AC-007 | RED |

---

## Red Baseline 证据

> Red 基线运行时间: 2026-01-11
> 证据落点: `dev-playbooks/changes/enhance-code-intelligence/evidence/red-baseline/`

### 预期失败原因

| 测试类别 | 失败原因 | 影响 AC |
|----------|----------|---------|
| hotspot-analyzer.bats | 脚本不存在 | AC-001 |
| boundary-detector.bats | 脚本不存在 | AC-004 |
| pattern-learner.bats | 脚本不存在 | AC-005 |
| intent-analysis.bats | Hook 未增强 | AC-002 |
| subgraph-retrieval.bats | 子图逻辑未实现 | AC-003 |
| data-flow-tracing.bats | 参数未添加 | AC-006 |
| incremental-indexing.bats | 脚本不存在 | AC-007 |
| mcp-contract.bats | 新工具未注册 | AC-008 |
| feature-toggle.bats | 配置字段未添加 | AC-010 |

---

## 测试隔离要求

- [x] 每个测试独立运行，不依赖执行顺序
- [x] 测试使用临时目录进行文件操作
- [x] 测试结束后清理创建的文件/数据
- [x] 禁止使用共享的可变状态

---

## 测试稳定性要求

- [x] 禁止提交 `test.only` / `@test:skip`
- [x] 测试超时设置：单元 < 5s，集成 < 30s
- [x] 禁止依赖外部网络（mock 外部调用）
- [ ] Flaky 测试标记并限期修复

---

## 运行指南

```bash
# 运行所有测试（Red 基线阶段）
EXPECT_RED=true bats tests/*.bats

# 运行所有测试（Green 阶段 - 实现后）
EXPECT_RED=false bats tests/*.bats

# 运行特定模块测试
bats tests/hotspot-analyzer.bats
bats tests/boundary-detector.bats

# 运行回归测试（预期 Green）
bats tests/bug-locator.bats

# 运行边界测试
bats tests/*.bats | grep -E "(BOUNDARY|passed|failed)"

# 验证变更包
openspec validate enhance-code-intelligence --strict
```

### CI 集成示例

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install bats
        run: sudo apt-get install -y bats
      - name: Run tests (Red baseline)
        run: EXPECT_RED=true bats tests/*.bats
        continue-on-error: true  # 期望部分失败
      - name: Run regression tests
        run: bats tests/bug-locator.bats  # 必须全部通过
```

---

## 下一步

1. **Coder 实现**：按 `tasks.md` 实现各脚本，让测试 Green
2. **Test Owner 监控**：跟踪测试通过率，更新追溯矩阵
3. **归档前审核**：确认所有 AC 对应测试通过
