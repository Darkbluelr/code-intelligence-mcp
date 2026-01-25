---
last_referenced_by: optimize-indexing-pipeline-20260117
last_verified: 2026-01-18
health: active
---

# Spec Delta: SCIP Parser Offline（SCIP 解析器离线化）

> **Change ID**: `optimize-indexing-pipeline-20260117`
> **Capability**: scip-parser-offline
> **Version**: 1.0.0
> **Status**: Active
> **Created**: 2026-01-18
> **Affects**: `dev-playbooks/specs/scip-parser/spec.md`（扩展）

---

## Requirements（需求）

### REQ-SPO-001: 离线优先 Proto 发现

系统必须优先使用本地 vendored `scip.proto`，不依赖运行时网络下载。

**约束**：
- 默认 proto 路径：`vendored/scip.proto`
- 可通过环境变量 `SCIP_PROTO_PATH` 自定义路径
- 仅在显式配置 `allow_proto_download: true` 时才允许下载

### REQ-SPO-002: Proto 版本固定

vendored `scip.proto` 必须固定版本，与 `scip-typescript` 兼容。

**约束**：
- 版本标注在文件头部注释中
- 升级需通过显式流程（脚本或手动）
- 版本不兼容时给出明确错误信息

### REQ-SPO-003: 降级策略

当 proto 不可用时，系统必须给出可诊断的明确错误。

**约束**：
- 错误信息包含缺失的 proto 路径
- 提供修复建议（如：添加 vendored proto 或允许下载）
- 不进行静默失败

### REQ-SPO-004: 配置控制

proto 来源策略必须可配置。

**约束**：
- 配置路径：`config/features.yaml` 中 `features.indexer.offline_proto`
- 默认值：`true`（离线优先）
- `allow_proto_download: false` 时禁止下载

---

## Scenarios（场景）

### SC-SPO-001: 使用 vendored proto 解析

**Given**：
- `vendored/scip.proto` 存在且版本兼容
- `features.indexer.offline_proto: true`

**When**：
- 执行 `scip-to-graph.sh parse`

**Then**：
- 从 `vendored/scip.proto` 加载 proto 定义
- 解析成功
- 输出 proto 来源：`VENDORED`

**Trace**: AC-003

### SC-SPO-002: 自定义 proto 路径

**Given**：
- 环境变量 `SCIP_PROTO_PATH=/custom/path/scip.proto`
- 该路径文件存在

**When**：
- 执行 `scip-to-graph.sh parse`

**Then**：
- 从自定义路径加载 proto
- 解析成功
- 输出 proto 来源：`CUSTOM`

**Trace**: AC-003

### SC-SPO-003: 离线模式无 proto 报错

**Given**：
- `vendored/scip.proto` 不存在
- `SCIP_PROTO_PATH` 未设置或指向不存在的文件
- `features.indexer.allow_proto_download: false`

**When**：
- 执行 `scip-to-graph.sh parse`

**Then**：
- 返回错误：`SCIP proto not found. Expected: vendored/scip.proto`
- 提供修复建议：`Run: scripts/vendor-proto.sh to download and vendor the proto file`
- 退出码：1

**Trace**: AC-003

### SC-SPO-004: 允许下载时的降级

**Given**：
- vendored proto 不存在
- `features.indexer.allow_proto_download: true`

**When**：
- 执行 `scip-to-graph.sh parse`

**Then**：
- 尝试下载 proto 到 `$CACHE_DIR/scip.proto`
- 下载成功后执行解析
- 输出 proto 来源：`DOWNLOADED`
- 输出警告：`Proto downloaded from network. Consider vendoring for reproducibility.`

**Trace**: AC-003

### SC-SPO-005: 下载失败时的错误处理

**Given**：
- vendored proto 不存在
- `allow_proto_download: true`
- 网络不可用或下载 URL 失效

**When**：
- 执行 `scip-to-graph.sh parse`

**Then**：
- 返回错误：`Failed to download SCIP proto: <reason>`
- 提供修复建议
- 退出码：1

**Trace**: AC-003

### SC-SPO-006: Proto 版本不兼容

**Given**：
- vendored proto 版本与 SCIP 索引格式不兼容

**When**：
- 执行 `scip-to-graph.sh parse`

**Then**：
- 返回错误：`SCIP proto version mismatch. Expected: v0.3.0, Got: v0.2.0`
- 提供升级建议：`Run: scripts/vendor-proto.sh --upgrade`
- 退出码：1

**Trace**: AC-003

### SC-SPO-007: 缓存 proto 复用

**Given**：
- 首次解析已下载 proto 到 `$CACHE_DIR/scip.proto`
- `allow_proto_download: true`

**When**：
- 再次执行 `scip-to-graph.sh parse`

**Then**：
- 复用缓存的 proto
- 不再发起网络请求
- 输出 proto 来源：`CACHED`

**Trace**: AC-003

---

## API / Schema 变更

### 新增文件

| 路径 | 类型 | 说明 |
|------|------|------|
| `vendored/scip.proto` | Proto | 固定版本的 SCIP proto 定义 |
| `scripts/vendor-proto.sh` | Script | Proto vendoring 辅助脚本 |

### CLI 变更

**现有命令增强**：

| 命令 | 新增输出 | 说明 |
|------|----------|------|
| `scip-to-graph.sh parse` | `proto_source` 字段 | 指示 proto 来源 |

**新增命令**：

| 命令 | 行为 | 说明 |
|------|------|------|
| `scripts/vendor-proto.sh` | 下载并 vendor proto | 一次性执行 |
| `scripts/vendor-proto.sh --upgrade` | 升级 vendored proto | 更新版本 |
| `scripts/vendor-proto.sh --check` | 检查版本兼容性 | 不修改文件 |

### 配置 Schema 变更

**扩展 `config/features.yaml`**：

```yaml
features:
  indexer:
    offline_proto: true              # 使用 vendored proto（默认）
    allow_proto_download: false      # 是否允许下载更新（默认禁用）
```

### 输出格式

**解析统计输出扩展（JSON）**：

```json
{
  "documents": 1,
  "symbols": 187,
  "occurrences": 494,
  "edges": {
    "DEFINES": 187,
    "IMPORTS": 0,
    "CALLS": 307,
    "MODIFIES": 0
  },
  "confidence": "high",
  "source": "scip",
  "proto_source": "VENDORED",
  "proto_version": "v0.3.0"
}
```

**proto_source 取值**：

| 值 | 说明 |
|----|------|
| `VENDORED` | 使用 vendored/scip.proto |
| `CUSTOM` | 使用 SCIP_PROTO_PATH 指定的路径 |
| `CACHED` | 使用缓存的下载 proto |
| `DOWNLOADED` | 本次下载的 proto |

---

## 兼容策略

### 向后兼容

- 若 vendored proto 存在，默认行为不变（仍能解析）
- 现有命令参数保持兼容

### 迁移方案

对于依赖隐式网络下载的现有用户：

1. **首次运行**：若 vendored proto 不存在，输出迁移提示
2. **迁移步骤**：
   ```bash
   # 1. 执行一次性 vendoring
   ./scripts/vendor-proto.sh

   # 2. 提交 vendored 文件
   git add vendored/scip.proto
   git commit -m "vendor: add scip.proto for offline parsing"
   ```
3. **回滚路径**：设置 `allow_proto_download: true` 恢复旧行为

### 弃用计划

- `allow_proto_download: true` 作为后门保留
- 计划在 v1.0 稳定后评估移除

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 | 验证命令 |
|---------|------|----------|----------|
| CT-SPO-001 | behavior | SC-SPO-001 | `tests/scip-to-graph.bats::test_vendored_proto` |
| CT-SPO-002 | behavior | SC-SPO-002 | `tests/scip-to-graph.bats::test_custom_proto_path` |
| CT-SPO-003 | behavior | SC-SPO-003 | `tests/scip-to-graph.bats::test_offline_no_proto_error` |
| CT-SPO-004 | behavior | SC-SPO-004, SC-SPO-007 | `tests/scip-to-graph.bats::test_download_fallback` |
| CT-SPO-005 | behavior | SC-SPO-006 | `tests/scip-to-graph.bats::test_proto_version_check` |

---

## Traceability Matrix（追溯矩阵）

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-SPO-001 | SC-SPO-001, SC-SPO-002, SC-SPO-003, SC-SPO-004 | AC-003 |
| REQ-SPO-002 | SC-SPO-006 | AC-003 |
| REQ-SPO-003 | SC-SPO-003, SC-SPO-005, SC-SPO-006 | AC-003 |
| REQ-SPO-004 | SC-SPO-001, SC-SPO-004 | AC-003 |
