# 规格：跨函数数据流追踪

> **Capability**: data-flow-tracing
> **Version**: 2.0.0
> **Status**: Active
> **Created**: 2026-01-17
> **Last Referenced By**: 20260118-2112-enhance-code-intelligence-capabilities
> **Last Verified**: 2026-01-22
> **Health**: active

---

## Requirements（需求）

### REQ-DFT-001：数据流追踪命令

扩展 `call-chain.sh` 支持数据流追踪：

```bash
call-chain.sh --data-flow <symbol> [options]

Options:
  --direction <forward|backward|both>  追踪方向（默认: both）
  --depth <n>                          最大深度（默认: 5）
  --include-transforms                 包含转换详情
  --format <json|mermaid>             输出格式
```

### REQ-DFT-002：追踪方向

| 方向 | 描述 | 用途 |
|------|------|------|
| forward | 从定义追踪到使用 | 影响分析 |
| backward | 从使用追踪到来源 | 根因分析 |
| both | 双向追踪 | 完整数据流 |

### REQ-DFT-003：变量映射追踪

系统应追踪以下变量转换：

| 转换类型 | 示例 |
|----------|------|
| 参数传递 | `foo(x)` 中 x 传入 foo |
| 返回值 | `y = foo()` 中 foo 返回到 y |
| 赋值 | `z = x` 中 x 赋给 z |
| 属性访问 | `obj.prop` 中 obj 到 prop |
| 数组/Map | `arr[i]` 或 `map.get(k)` |

### REQ-DFT-004：污点传播算法

```
算法：Taint Propagation

输入：源符号 S，方向 D，深度限制 N
输出：数据流路径列表

1. 初始化：TAINTED = {S}，PATHS = []
2. 队列：Q = [(S, [], 0)]
3. while Q 非空 且 深度 < N:
   a. 取出 (current, path, depth)
   b. 如果 D=forward: 找所有使用 current 的位置
      如果 D=backward: 找 current 的来源
   c. 对每个相关符号 next:
      - 如果 next 未访问：
        - 记录转换 transform
        - TAINTED.add(next)
        - Q.push((next, path + [transform], depth + 1))
        - 如果 next 是 sink: PATHS.add(path)
4. 返回 PATHS
```

### REQ-DFT-005：输出格式

```json
{
  "source": {
    "symbol": "userInput",
    "file": "src/handler.ts",
    "line": 10,
    "type": "parameter"
  },
  "sink": {
    "symbol": "dbQuery",
    "file": "src/db.ts",
    "line": 50,
    "type": "function_call"
  },
  "path": [
    {
      "symbol": "userInput",
      "file": "src/handler.ts",
      "line": 10,
      "transform": "parameter_input"
    },
    {
      "symbol": "data",
      "file": "src/handler.ts",
      "line": 15,
      "transform": "assignment: data = validate(userInput)"
    },
    {
      "symbol": "query",
      "file": "src/service.ts",
      "line": 30,
      "transform": "parameter_pass: processData(data)"
    },
    {
      "symbol": "dbQuery",
      "file": "src/db.ts",
      "line": 50,
      "transform": "function_call: executeQuery(query)"
    }
  ],
  "depth": 4,
  "transforms_count": 4
}
```

### REQ-DFT-006：深度限制

- 默认最大深度：5 跳
- 可配置范围：1-10
- 超过限制时：标记 `truncated: true`

---

## Scenarios（场景）

### SC-DFT-001：正向追踪用户输入

**Given**: 用户输入变量 `req.body`
**When**: `call-chain.sh --data-flow req.body --direction forward`
**Then**:
- 追踪到所有使用该输入的位置
- 标识数据库查询等敏感 sink

### SC-DFT-002：反向追踪错误来源

**Given**: 错误发生在 `processResult(data)`
**When**: `call-chain.sh --data-flow data --direction backward`
**Then**:
- 追踪 data 的来源
- 找到原始输入点

### SC-DFT-003：跨文件追踪

**Given**: 变量跨越 3 个文件传递
**When**: 执行数据流追踪
**Then**:
- 完整追踪跨文件路径
- 正确记录文件边界

### SC-DFT-004：深度限制

**Given**: 数据流深度超过 10 跳
**When**: `call-chain.sh --data-flow x --depth 5`
**Then**:
- 在第 5 跳停止
- 标记 `truncated: true`

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-DFT-001 | All | AC-004 |
| REQ-DFT-002 | SC-DFT-001, SC-DFT-002 | AC-004 |
| REQ-DFT-003 | All | AC-004 |
| REQ-DFT-004 | All | AC-004 |
| REQ-DFT-005 | All | AC-004 |
| REQ-DFT-006 | SC-DFT-004 | AC-004 |
