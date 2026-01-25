# Contract Plan: Indexing Pipeline Optimization

> **Change ID**: `optimize-indexing-pipeline-20260117`
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-18

---

## 契约变更摘要

本变更涉及 3 个契约领域的变更：

| 契约 ID | 类型 | 影响范围 | 变更类型 |
|---------|------|----------|----------|
| `indexer-scheduler` | CLI | `scripts/indexer.sh` | EXTEND |
| `scip-parser-offline` | CLI + Config | `scripts/scip-to-graph.sh` | EXTEND |
| `ci-index-status-semantic` | MCP | `src/server.ts` | MODIFY |

---

## API 变更清单

### 1. scripts/indexer.sh CLI

**变更类型**: EXTEND（新增入口，保持兼容）

**现有入口（保持兼容）**:

| 命令 | 行为 | 兼容性 |
|------|------|--------|
| `--help` | 显示帮助 | 不变 |
| `--status` | 显示索引状态 | 不变 |
| `--install` | 安装守护进程 | 不变 |
| `--uninstall` | 卸载守护进程 | 不变 |
| （无参数） | 启动守护模式 | 不变 |

**新增入口**:

| 命令 | 行为 | 说明 |
|------|------|------|
| `--dry-run --files <list>` | 输出调度决策 | 不实际执行 |
| `--once --files <list>` | 一次性执行索引 | 非守护模式 |

### 2. scripts/scip-to-graph.sh CLI

**变更类型**: EXTEND（新增输出字段，保持兼容）

**输出扩展**:

```json
{
  // 现有字段...
  "proto_source": "VENDORED",  // 新增
  "proto_version": "v0.3.0"    // 新增
}
```

**新增辅助脚本**:

| 脚本 | 行为 |
|------|------|
| `scripts/vendor-proto.sh` | 下载并 vendor scip.proto |
| `scripts/vendor-proto.sh --upgrade` | 升级 vendored proto |
| `scripts/vendor-proto.sh --check` | 检查版本兼容性 |

### 3. ci_index_status MCP 工具

**变更类型**: MODIFY（语义变更，接口兼容）

**接口（不变）**:

```json
{
  "name": "ci_index_status",
  "inputSchema": {
    "properties": {
      "action": {
        "type": "string",
        "enum": ["status", "build", "clear"]
      }
    }
  }
}
```

**语义变更**:

| 参数 | 旧行为 | 新行为 |
|------|--------|--------|
| `status` | `indexer.sh status` | `embedding.sh status` |
| `build` | `indexer.sh build` | `embedding.sh build` |
| `clear` | `indexer.sh clear` | `embedding.sh clean` |

---

## Schema 变更

### config/features.yaml 扩展

```yaml
features:
  ast_delta:
    enabled: true                    # 启用增量路径
    file_threshold: 10               # 超过此数量回退到全量
  indexer:
    debounce_seconds: 2              # 防抖窗口
    offline_proto: true              # 使用 vendored proto
    allow_proto_download: false      # 是否允许下载更新
```

### 新增文件

| 路径 | 类型 | 说明 |
|------|------|------|
| `vendored/scip.proto` | Proto | 固定版本的 SCIP proto 定义 |

---

## 兼容策略

### 向后兼容保证

| 契约 | 兼容级别 | 说明 |
|------|----------|------|
| `indexer.sh` CLI | 完全兼容 | 既有入口行为不变 |
| `scip-to-graph.sh` CLI | 完全兼容 | 仅新增输出字段 |
| `ci_index_status` MCP | 接口兼容，语义变更 | 需要文档说明 |

### Breaking Change 风险

**ci_index_status 语义变更**:
- 风险级别：Low-Medium
- 影响用户：依赖返回 SCIP/图索引状态的用户
- 缓解措施：
  1. README.md 更新工具说明
  2. 提供 `ci_ast_delta` 作为 SCIP/图索引管理替代
  3. 首次调用输出迁移提示（可选）

### 弃用计划

| 功能 | 状态 | 计划 |
|------|------|------|
| `allow_proto_download: true` | 保留为后门 | v1.0 后评估移除 |

---

## Contract Test IDs

### Indexer Scheduler Tests

| Test ID | 类型 | 覆盖场景 | 验证命令 |
|---------|------|----------|----------|
| CT-IS-001 | behavior | 增量路径触发 | `tests/indexer.bats::test_incremental_path_invoked` |
| CT-IS-002 | behavior | 回退全量重建 | `tests/indexer.bats::test_fallback_to_full_rebuild` |
| CT-IS-003 | behavior | dry-run 模式 | `tests/indexer.bats::test_dry_run_mode` |
| CT-IS-004 | behavior | CLI 兼容性 | `tests/indexer.bats::test_cli_compatibility` |
| CT-IS-005 | behavior | 幂等性 | `tests/indexer.bats::test_idempotency` |
| CT-IS-006 | behavior | 功能开关 | `tests/indexer.bats::test_feature_toggle` |
| CT-IS-007 | behavior | 防抖聚合 | `tests/indexer.bats::test_debounce_aggregation` |
| CT-IS-008 | behavior | 版本戳一致性 | `tests/indexer.bats::test_version_stamp_consistency` |

### SCIP Parser Offline Tests

| Test ID | 类型 | 覆盖场景 | 验证命令 |
|---------|------|----------|----------|
| CT-SPO-001 | behavior | vendored proto | `tests/scip-to-graph.bats::test_vendored_proto` |
| CT-SPO-002 | behavior | 自定义路径 | `tests/scip-to-graph.bats::test_custom_proto_path` |
| CT-SPO-003 | behavior | 离线无 proto 报错 | `tests/scip-to-graph.bats::test_offline_no_proto_error` |
| CT-SPO-004 | behavior | 下载降级 | `tests/scip-to-graph.bats::test_download_fallback` |
| CT-SPO-005 | behavior | 版本检查 | `tests/scip-to-graph.bats::test_proto_version_check` |

### ci_index_status Semantic Tests

| Test ID | 类型 | 覆盖场景 | 验证命令 |
|---------|------|----------|----------|
| CT-CIS-001 | behavior | status 动作 | `tests/server.bats::test_ci_index_status_status` |
| CT-CIS-002 | behavior | build 动作 | `tests/server.bats::test_ci_index_status_build` |
| CT-CIS-003 | behavior | clear 动作 | `tests/server.bats::test_ci_index_status_clear` |
| CT-CIS-004 | behavior | 参数验证 | `tests/server.bats::test_ci_index_status_validation` |

---

## 追溯矩阵：Contract Tests → AC

| Contract Test | AC Coverage |
|---------------|-------------|
| CT-IS-001, CT-IS-002 | AC-001, AC-002 |
| CT-IS-003 | AC-001 |
| CT-IS-004 | AC-004 |
| CT-IS-005 | AC-006 |
| CT-IS-006 | AC-009 |
| CT-IS-007 | AC-007 |
| CT-IS-008 | AC-008 |
| CT-SPO-001 ~ CT-SPO-005 | AC-003 |
| CT-CIS-001 ~ CT-CIS-004 | AC-005 |
| （并发测试） | AC-010 |

---

## 隐式变更检测

### 检测范围

- [x] 依赖变更：无（不新增 npm 依赖）
- [x] 配置变更：`config/features.yaml` 扩展
- [x] 构建变更：无

### 配置变更风险评估

| 配置项 | 风险级别 | 说明 |
|--------|----------|------|
| `features.ast_delta.enabled` | Low | 默认 true，与现有行为一致 |
| `features.ast_delta.file_threshold` | Low | 新增配置，有默认值 |
| `features.indexer.debounce_seconds` | Low | 新增配置，有默认值 |
| `features.indexer.offline_proto` | Low | 新增配置，默认 true |
| `features.indexer.allow_proto_download` | Low | 新增配置，默认 false |

---

## 文档影响

### 必须更新

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| `README.md` | ci_index_status 语义变更说明 | P0 |
| `docs/使用说明书.md` | 新增 vendored proto 说明、功能开关说明 | P0 |

### 建议更新

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| `CHANGELOG.md` | 记录本次变更 | P1 |
| `dev-playbooks/specs/_meta/project-profile.md` | 更新工具说明 | P1 |
