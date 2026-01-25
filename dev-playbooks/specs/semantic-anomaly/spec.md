# 规格：语义异常检测

> **Capability**: semantic-anomaly
> **Version**: 1.0.0
> **Status**: Active
> **Created**: 2026-01-17
> **Last Referenced By**: 20260118-2112-enhance-code-intelligence-capabilities
> **Last Verified**: 2026-01-22
> **Health**: active

---

## Requirements（需求）

### REQ-SA-001：异常类型定义

系统应检测以下语义异常类型：

| 异常类型 | 代码 | 描述 |
|----------|------|------|
| 缺失错误处理 | MISSING_ERROR_HANDLER | 调用可能抛出异常的函数但未捕获 |
| 不一致 API 调用 | INCONSISTENT_API_CALL | 同一 API 的调用方式不一致 |
| 命名约定违规 | NAMING_VIOLATION | 不符合项目命名约定 |
| 缺失日志 | MISSING_LOG | 关键操作点缺失日志 |
| 未使用导入 | UNUSED_IMPORT | 导入但未使用的模块 |
| 废弃模式 | DEPRECATED_PATTERN | 使用已废弃的代码模式 |

### REQ-SA-002：模式学习集成

系统应与 `pattern-learner.sh` 集成：

1. 读取已学习的模式库
2. 将模式转换为异常检测规则
3. 检测违反模式的代码

### REQ-SA-003：AST 分析

系统应进行 AST 级别分析：

- 解析函数调用关系
- 识别 try-catch 块
- 提取变量命名

### REQ-SA-004：输出格式

异常报告格式：

```json
{
  "anomalies": [
    {
      "type": "MISSING_ERROR_HANDLER",
      "file": "src/api.ts",
      "line": 42,
      "severity": "warning",
      "message": "调用 fetch() 未处理可能的网络错误",
      "suggestion": "添加 try-catch 或 .catch() 处理",
      "pattern_source": "learned:error-handling-001"
    }
  ],
  "summary": {
    "total": 5,
    "by_type": {"MISSING_ERROR_HANDLER": 2, "NAMING_VIOLATION": 3},
    "by_severity": {"warning": 4, "info": 1}
  }
}
```

### REQ-SA-005：严重程度分级

| 级别 | 条件 |
|------|------|
| error | 可能导致运行时错误 |
| warning | 可能导致难以维护的代码 |
| info | 建议改进 |

---

## Scenarios（场景）

### SC-SA-001：检测缺失错误处理

**Given**: 代码中有 `await fetch(url)` 但无 try-catch
**When**: 运行 `semantic-anomaly.sh src/`
**Then**:
- 检测到 MISSING_ERROR_HANDLER
- 报告行号和建议

### SC-SA-002：检测不一致 API 调用

**Given**:
- 文件 A 使用 `logger.info("msg")`
- 文件 B 使用 `console.log("msg")`
**When**: 运行语义异常检测
**Then**:
- 检测到 INCONSISTENT_API_CALL
- 指出推荐的一致模式

### SC-SA-003：检测命名违规

**Given**: 项目约定使用 camelCase，但存在 snake_case 变量
**When**: 运行语义异常检测
**Then**:
- 检测到 NAMING_VIOLATION
- 提供重命名建议

### SC-SA-004：与模式学习集成

**Given**: pattern-learner 已学习到 "所有 DB 操作都在事务中"
**When**: 检测到直接 DB 操作（无事务）
**Then**:
- 检测到 DEPRECATED_PATTERN
- 关联到学习的模式

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-SA-001 | SC-SA-001, SC-SA-002, SC-SA-003 | AC-003 |
| REQ-SA-002 | SC-SA-004 | AC-003 |
| REQ-SA-003 | All | AC-003 |
| REQ-SA-004 | All | AC-003 |
| REQ-SA-005 | All | AC-003 |
