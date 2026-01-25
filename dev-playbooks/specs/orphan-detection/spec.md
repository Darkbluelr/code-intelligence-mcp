# 规格：孤儿模块检测（orphan-detection）

> **Change ID**: `augment-parity`
> **Capability**: orphan-detection
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-15

---

## Requirements（需求）

### REQ-OD-001：孤儿节点定义

系统应将以下节点识别为孤儿节点：

**定义**：入边数为 0 的节点（无其他模块引用）

**排除条件**：
- 入口点文件（如 `index.ts`、`main.ts`）
- 测试文件（`*.test.ts`、`*.spec.ts`）
- 配置文件
- 显式标记为公共 API 的节点

### REQ-OD-002：功能开关

孤儿检测应通过功能开关控制：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `features.orphan_detection.enabled` | `true` | 是否启用孤儿检测 |

### REQ-OD-003：检测命令

系统应通过新增参数启用孤儿检测：

```bash
dependency-guard.sh --orphan-check [--exclude <pattern>] [--format <json|text>]
```

**参数**：
| 参数 | 说明 |
|------|------|
| `--orphan-check` | 启用孤儿检测模式 |
| `--exclude <pattern>` | 排除特定模式的文件（glob） |
| `--format <json|text>` | 输出格式，默认 text |

### REQ-OD-004：检测结果

检测结果应包含以下信息：

```json
{
  "orphans": [
    {
      "symbol": "unusedHelper",
      "kind": "function",
      "file_path": "src/utils/deprecated.ts",
      "line": 15,
      "suggestion": "Remove or export as public API"
    }
  ],
  "summary": {
    "total_nodes": 187,
    "orphan_count": 3,
    "orphan_ratio": 0.016
  }
}
```

### REQ-OD-005：处理建议

系统应为每个孤儿节点提供处理建议：

| 节点类型 | 建议 |
|----------|------|
| 未导出函数 | "Remove or export as public API" |
| 未导出类 | "Remove or export as public API" |
| 未使用常量 | "Remove or use in code" |
| 已废弃模块 | "Remove deprecated code" |

### REQ-OD-006：集成现有架构守护

孤儿检测应作为 `dependency-guard.sh` 的扩展：

- 与现有循环依赖检测并存
- 可单独运行或与其他检查一起运行
- 输出格式保持一致

---

## Scenarios（场景）

### SC-OD-001：检测孤儿模块

**Given**:
- 图数据库包含节点 A、B、C、D
- A 被 B 和 C 引用（入边 = 2）
- B 被 C 引用（入边 = 1）
- C 被 D 引用（入边 = 1）
- D 无入边（入边 = 0）
**When**: 执行 `dependency-guard.sh --orphan-check`
**Then**:
- 报告 D 为孤儿节点
- 不报告 A、B、C

### SC-OD-002：排除入口点

**Given**:
- `src/index.ts` 中的 `main()` 函数无入边
- `main()` 是程序入口点
**When**: 执行孤儿检测
**Then**:
- 不报告 `main()` 为孤儿
- 输出：`Excluded 1 entry point(s)`

### SC-OD-003：排除测试文件

**Given**:
- `src/utils.test.ts` 中的测试函数无生产代码引用
**When**: 执行孤儿检测
**Then**:
- 不报告测试函数为孤儿
- 测试文件默认排除

### SC-OD-004：自定义排除模式

**Given**:
- 存在实验性代码目录 `src/experimental/`
- 实验性代码无引用
**When**: 执行 `dependency-guard.sh --orphan-check --exclude "src/experimental/**"`
**Then**:
- 不报告实验性代码为孤儿
- 输出排除统计

### SC-OD-005：JSON 格式输出

**Given**: 存在 2 个孤儿节点
**When**: 执行 `dependency-guard.sh --orphan-check --format json`
**Then**:
- 输出 JSON 格式结果：
  ```json
  {
    "orphans": [
      {"symbol": "unusedFunc", "file_path": "src/utils.ts", ...},
      {"symbol": "OldClass", "file_path": "src/legacy.ts", ...}
    ],
    "summary": {
      "total_nodes": 100,
      "orphan_count": 2,
      "orphan_ratio": 0.02
    }
  }
  ```

### SC-OD-006：文本格式输出

**Given**: 存在 2 个孤儿节点
**When**: 执行 `dependency-guard.sh --orphan-check --format text`
**Then**:
- 输出人类可读格式：
  ```
  Orphan Detection Report
  =======================

  Found 2 orphan node(s) out of 100 total (2.0%)

  1. [function] unusedFunc
     Location: src/utils.ts:15
     Suggestion: Remove or export as public API

  2. [class] OldClass
     Location: src/legacy.ts:30
     Suggestion: Remove or export as public API
  ```

### SC-OD-007：无孤儿节点

**Given**: 所有节点均被引用
**When**: 执行孤儿检测
**Then**:
- 输出：`No orphan nodes found`
- 退出码 0

### SC-OD-008：与循环检测联合运行

**Given**: 启用孤儿检测和循环检测
**When**: 执行 `dependency-guard.sh --orphan-check --cycle-check`
**Then**:
- 执行两种检测
- 输出合并报告
- 分别标记问题类型

### SC-OD-009：功能禁用时跳过

**Given**: `features.orphan_detection.enabled = false`
**When**: 执行 `dependency-guard.sh --orphan-check`
**Then**:
- 输出：`Orphan detection is disabled`
- 跳过检测
- 退出码 0

### SC-OD-010：空图处理

**Given**: 图数据库为空（无节点）
**When**: 执行孤儿检测
**Then**:
- 输出：`No nodes in graph, skipping orphan detection`
- 不报错
- 退出码 0

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-OD-001 | SC-OD-001, SC-OD-002, SC-OD-003 | AC-005 |
| REQ-OD-002 | SC-OD-009 | AC-005 |
| REQ-OD-003 | SC-OD-004, SC-OD-005, SC-OD-006 | AC-005 |
| REQ-OD-004 | SC-OD-005 | AC-005 |
| REQ-OD-005 | SC-OD-005, SC-OD-006 | AC-005 |
| REQ-OD-006 | SC-OD-008 | AC-005 |
