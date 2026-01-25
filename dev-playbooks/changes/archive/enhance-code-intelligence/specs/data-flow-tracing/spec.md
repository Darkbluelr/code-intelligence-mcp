# Spec Delta: data-flow-tracing

> **Change ID**: enhance-code-intelligence
> **Capability**: data-flow-tracing
> **Type**: ADDED
> **Owner**: Spec Owner
> **Created**: 2026-01-11

---

## ADDED Requirements

### Requirement: Cross-Function Data Flow Tracing

系统 SHALL 支持跨函数的参数流追踪，展示数据如何从源头流向目标。

#### Scenario: Trace parameter flow

- **GIVEN** 查询参数 `toolName` 在函数 `handleToolCall`
- **AND** 使用 `--trace-data-flow` 参数
- **WHEN** 执行数据流追踪
- **THEN** 返回 `toolName` 从调用者到被调用者的流动路径
- **AND** 路径包含每个函数中的参数名映射

Trace: AC-006

#### Scenario: Trace return value flow

- **GIVEN** 查询函数 `runScript` 的返回值
- **AND** 使用 `--trace-data-flow` 参数
- **WHEN** 执行数据流追踪
- **THEN** 返回返回值被使用的位置
- **AND** 展示返回值如何被传递到后续函数

Trace: AC-006

#### Scenario: Data flow with transformation

- **GIVEN** 参数 `input` 经过 `JSON.parse()` 转换
- **WHEN** 执行数据流追踪
- **THEN** 路径标记转换点
- **AND** 标记转换前后的类型变化

Trace: AC-006

---

### Requirement: Data Flow CLI Option

系统 SHALL 在 `call-chain.sh` 中新增 `--trace-data-flow` 可选参数。

#### Scenario: Enable data flow tracing

- **GIVEN** 调用 `call-chain.sh --symbol handleToolCall --trace-data-flow`
- **WHEN** 执行命令
- **THEN** 输出包含调用链
- **AND** 输出包含参数流动路径

Trace: AC-006

#### Scenario: Default behavior without flag

- **GIVEN** 调用 `call-chain.sh --symbol handleToolCall`（无 --trace-data-flow）
- **WHEN** 执行命令
- **THEN** 输出仅包含调用链
- **AND** 不包含参数流动路径（保持向后兼容）

Trace: AC-006

---

## Data Examples

### Data Flow Output Format

```json
{
  "source": {
    "function": "Server.handleRequest",
    "parameter": "request.toolName",
    "type": "string"
  },
  "path": [
    {
      "function": "handleToolCall",
      "parameter": "toolName",
      "transformation": null
    },
    {
      "function": "runScript",
      "parameter": "scriptName",
      "transformation": "string concatenation"
    }
  ],
  "sink": {
    "function": "execAsync",
    "parameter": "command",
    "type": "string"
  }
}
```

### Call Chain with Data Flow

```
handleRequest(request)
    │
    │ request.toolName → toolName
    ▼
handleToolCall(toolName, arguments)
    │
    │ toolName → "scripts/" + toolName + ".sh"
    ▼
runScript(scriptPath, args)
    │
    │ scriptPath → command
    ▼
execAsync(command)
```
