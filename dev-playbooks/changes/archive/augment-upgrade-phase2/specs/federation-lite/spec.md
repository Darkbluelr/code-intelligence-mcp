# Spec: Federation Lite（轻量联邦索引）

> **Change ID**: `augment-upgrade-phase2`
> **Capability**: federation-lite
> **Version**: 1.0.0
> **Status**: Draft

---

## Requirements

### REQ-FED-001: 跨仓库契约发现

系统必须能够发现多仓库中的 API 契约文件：

| 契约类型 | 文件模式 | 说明 |
|----------|----------|------|
| Protocol Buffers | `**/*.proto` | gRPC/Protobuf 定义 |
| OpenAPI | `**/openapi.yaml`, `**/swagger.json` | REST API 定义 |
| GraphQL | `**/*.graphql` | GraphQL Schema |
| TypeScript Types | `**/*.d.ts`, `**/types/**/*.ts` | 共享类型定义 |

**约束**：
- 支持显式配置 + 自动发现两种模式
- 自动发现范围可配置

---

### REQ-FED-002: 联邦配置格式

配置文件 `config/federation.yaml` 必须支持：

```yaml
schema_version: "1.0.0"

federation:
  # 显式仓库列表
  repositories:
    - name: "<repo_name>"
      path: "<relative_or_absolute_path>"
      contracts:
        - "<glob_pattern>"

  # 自动发现
  auto_discover:
    enabled: true|false
    search_paths:
      - "<glob_pattern>"
    contract_patterns:
      - "<glob_pattern>"

  # 更新策略
  update:
    trigger: "manual"  # manual | on-push | scheduled
```

---

### REQ-FED-003: 联邦索引格式

索引文件 `.devbooks/federation-index.json` 必须包含：

```json
{
  "schema_version": "1.0.0",
  "indexed_at": "2026-01-13T10:00:00Z",
  "repositories": [
    {
      "name": "<repo_name>",
      "path": "<path>",
      "contracts": [
        {
          "path": "<contract_file>",
          "type": "proto|openapi|graphql|typescript",
          "symbols": ["<exported_symbol>"],
          "hash": "<content_hash>"
        }
      ]
    }
  ]
}
```

---

### REQ-FED-004: 契约符号提取

系统必须从契约文件中提取导出符号：

| 契约类型 | 提取内容 |
|----------|----------|
| `.proto` | service, message, enum 名称 |
| `openapi.yaml` | paths, schemas 名称 |
| `.graphql` | type, query, mutation 名称 |
| `.ts` | export interface/type/class 名称 |

---

### REQ-FED-005: MCP 工具接口

新增 MCP 工具 `ci_federation`：

```typescript
{
  name: "ci_federation",
  inputSchema: {
    type: "object",
    properties: {
      action: {
        type: "string",
        enum: ["status", "update", "search"],
        description: "Action to perform"
      },
      query: {
        type: "string",
        description: "Symbol to search (for search action)"
      },
      format: {
        type: "string",
        enum: ["text", "json"],
        description: "Output format"
      }
    }
  }
}
```

**约束**：
- 默认 action = "status"
- 向后兼容：不影响现有工具

---

### REQ-FED-006: 手动触发更新

联邦索引更新必须手动触发：

```bash
federation-lite.sh --update
```

**约束**：
- 不支持自动触发（后台进程）
- 更新过程幂等

---

## Scenarios

### SC-FED-001: 显式仓库索引

**Given**: `federation.yaml` 配置了 2 个显式仓库
**When**: 执行 `federation-lite.sh --update`
**Then**:
- 扫描 2 个仓库的契约文件
- 生成 federation-index.json
- repositories 数组长度 = 2

---

### SC-FED-002: 自动发现仓库

**Given**: `auto_discover.enabled = true`，同级目录有 3 个仓库
**When**: 执行 `federation-lite.sh --update`
**Then**:
- 扫描 search_paths 匹配的目录
- 发现并索引契约文件
- 合并显式配置和自动发现结果

---

### SC-FED-003: Proto 符号提取

**Given**: 仓库包含 `user.proto`，定义了 `UserService` 和 `User`
**When**: 执行索引
**Then**:
- contracts[].symbols 包含 "UserService" 和 "User"
- type = "proto"

---

### SC-FED-004: OpenAPI 符号提取

**Given**: 仓库包含 `openapi.yaml`，定义了 `/users` 路径和 `UserSchema`
**When**: 执行索引
**Then**:
- symbols 包含 "GET /users", "POST /users", "UserSchema"
- type = "openapi"

---

### SC-FED-005: 搜索契约符号

**Given**: federation-index.json 已生成
**When**: 执行 `federation-lite.sh --search "UserService"`
**Then**:
- 返回定义 UserService 的仓库和文件路径
- 输出格式符合指定（text/json）

---

### SC-FED-006: 索引状态查询

**Given**: federation-index.json 存在
**When**: 执行 `federation-lite.sh --status`
**Then**:
- 输出索引时间
- 输出仓库数量
- 输出契约文件数量

---

### SC-FED-007: 仓库路径不存在

**Given**: `federation.yaml` 配置了不存在的仓库路径
**When**: 执行索引
**Then**:
- 跳过不存在的仓库
- 记录警告日志
- 其他仓库正常索引

---

### SC-FED-008: 增量更新

**Given**: 已有索引，仅 1 个仓库有变更
**When**: 执行 `federation-lite.sh --update`
**Then**:
- 检测文件 hash 变化
- 仅重新提取变更文件的符号
- 保留未变更仓库的索引

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-FED-001 | behavior | REQ-FED-001, SC-FED-001 | 显式仓库索引 |
| CT-FED-002 | behavior | REQ-FED-001, SC-FED-002 | 自动发现 |
| CT-FED-003 | behavior | REQ-FED-004, SC-FED-003 | Proto 符号提取 |
| CT-FED-004 | behavior | REQ-FED-004, SC-FED-004 | OpenAPI 符号提取 |
| CT-FED-005 | behavior | REQ-FED-005, SC-FED-005 | 符号搜索 |
| CT-FED-006 | behavior | REQ-FED-005, SC-FED-006 | 状态查询 |
| CT-FED-007 | behavior | REQ-FED-001, SC-FED-007 | 路径不存在 |
| CT-FED-008 | behavior | REQ-FED-006, SC-FED-008 | 增量更新 |
| CT-FED-009 | schema | REQ-FED-002 | 配置格式 |
| CT-FED-010 | schema | REQ-FED-003 | 索引格式 |
| CT-FED-011 | contract | REQ-FED-005 | MCP 工具签名 |

---

## 脚本接口

### federation-lite.sh

```bash
# 查看索引状态
federation-lite.sh --status

# 更新索引
federation-lite.sh --update [--config config/federation.yaml]

# 搜索符号
federation-lite.sh --search "<symbol>" [--format json]

# 列出所有契约
federation-lite.sh --list-contracts [--repo "<name>"]
```

| 参数 | 说明 |
|------|------|
| `--status` | 查看索引状态 |
| `--update` | 更新索引 |
| `--config <file>` | 指定配置文件 |
| `--search <symbol>` | 搜索符号 |
| `--format text\|json` | 输出格式 |
| `--list-contracts` | 列出所有契约 |
| `--repo <name>` | 限定仓库范围 |

---

## 环境变量接口

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `FEDERATION_CONFIG` | `config/federation.yaml` | 配置文件路径 |
| `FEDERATION_INDEX` | `.devbooks/federation-index.json` | 索引文件路径 |
| `FEDERATION_DEBUG` | `0` | 启用调试日志 |

---

## 兼容性策略

### 向后兼容

- 新增 MCP 工具 `ci_federation` 不影响现有 8 个工具
- 现有脚本无需修改

### Schema 版本

- `federation-index.json` 包含 `schema_version`
- 版本不兼容时重新生成索引
