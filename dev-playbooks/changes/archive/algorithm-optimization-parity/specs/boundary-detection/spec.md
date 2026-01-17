# 规格：快速路径匹配 (Boundary Detection)

> **Capability ID**: ALG-009
> **模块**: boundary-detector.sh / graph-rag.sh
> **类型**: 行为变更（性能优化）

## Requirements

### REQ-BD-001: 快速路径规则

**描述**: 对常见库代码路径使用快速匹配规则，避免完整边界检测。

**快速规则列表**:
- `node_modules/*` → 库代码
- `vendor/*` → 库代码
- `.git/*` → 库代码
- `dist/*` → 库代码
- `build/*` → 库代码

---

### REQ-BD-002: 快速路径优先

**描述**: 快速规则匹配成功后，不调用完整边界检测器。

**性能要求**: 快速路径检测 < 1ms

---

### REQ-BD-003: 完整检测降级

**描述**: 快速规则未匹配时，调用完整边界检测器。

**完整检测器行为**:
- 解析项目配置（如 `.gitignore`、`tsconfig.json`）
- 检测文件类型（生成代码、测试代码等）

---

### REQ-BD-004: 边界类型分类

**描述**: 将文件分类为以下边界类型。

| 类型 | 说明 | 处理方式 |
|------|------|----------|
| user | 用户代码 | 保留 |
| library | 第三方库 | 过滤 |
| vendor | 供应商代码 | 过滤 |
| generated | 生成代码 | 过滤 |

---

### REQ-BD-005: 返回值

**描述**:
- 返回 0 = 是库代码（应过滤）
- 返回 1 = 是用户代码（应保留）

---

## Scenarios

### SC-BD-001: node_modules 快速匹配

- **Given**: 文件路径 = `node_modules/lodash/index.js`
- **When**: 调用 `is_library_code()` 函数
- **Then**: 快速规则匹配成功
- **And**: 不调用完整检测器
- **And**: 返回 0（是库代码）

### SC-BD-002: vendor 快速匹配

- **Given**: 文件路径 = `vendor/github.com/pkg/errors/errors.go`
- **When**: 调用 `is_library_code()` 函数
- **Then**: 快速规则匹配成功
- **And**: 返回 0（是库代码）

### SC-BD-003: 用户代码路径

- **Given**: 文件路径 = `src/auth/handler.ts`
- **When**: 调用 `is_library_code()` 函数
- **Then**: 快速规则未匹配
- **And**: 调用完整检测器
- **And**: 返回 1（是用户代码）

### SC-BD-004: 嵌套路径处理

- **Given**: 文件路径 = `src/components/node_modules/local-pkg/index.js`
- **When**: 调用 `is_library_code()` 函数
- **Then**: 快速规则匹配（包含 node_modules）
- **And**: 返回 0（是库代码）

### SC-BD-005: dist 目录

- **Given**: 文件路径 = `dist/bundle.js`
- **When**: 调用 `is_library_code()` 函数
- **Then**: 快速规则匹配成功
- **And**: 返回 0（是库代码/生成代码）

### SC-BD-006: 性能测试

- **Given**: 1000 个 node_modules 路径
- **When**: 批量调用 `is_library_code()`
- **Then**: 总耗时 < 100ms（平均 < 0.1ms/个）

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-BD-001 | behavior | SC-BD-001 |
| CT-BD-002 | behavior | SC-BD-002 |
| CT-BD-003 | behavior | SC-BD-003 |
| CT-BD-004 | boundary | SC-BD-004 |
| CT-BD-005 | behavior | SC-BD-005 |
| CT-BD-006 | performance | SC-BD-006 |
