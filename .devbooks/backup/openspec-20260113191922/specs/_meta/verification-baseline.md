# 最小验收锚点：Code Intelligence MCP Server

> 生成时间：2026-01-10
> 用途：存量项目基线验收，确保变更不破坏核心功能

---

## 烟雾测试（Smoke Tests）

### ST-001：CLI 版本检查

```bash
# 执行
./bin/code-intelligence-mcp --version

# 期望输出
code-intelligence-mcp v0.1.0
```

### ST-002：帮助信息检查

```bash
# 执行
./bin/ci-search --help

# 期望：显示帮助信息，包含 search query 参数说明
```

### ST-003：TypeScript 编译

```bash
# 执行
npm run build

# 期望：无错误，生成 dist/server.js
```

### ST-004：脚本权限检查

```bash
# 执行
ls -la scripts/*.sh | grep -c "^-rwx"

# 期望：输出数字大于 0（脚本有执行权限）
```

---

## 健康检查脚本

创建 `scripts/health-check.sh`（建议）：

```bash
#!/bin/bash
# 健康检查脚本

set -euo pipefail

PASS=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo "✓ $name"
        ((PASS++))
    else
        echo "✗ $name"
        ((FAIL++))
    fi
}

echo "=== Code Intelligence MCP 健康检查 ==="
echo ""

# 环境检查
check "Node.js 版本 >= 18" '[[ $(node -v | sed "s/v//" | cut -d. -f1) -ge 18 ]]'
check "npm 可用" "command -v npm"
check "ripgrep 可用" "command -v rg"
check "jq 可用" "command -v jq"

# 项目检查
check "package.json 存在" "test -f package.json"
check "tsconfig.json 存在" "test -f tsconfig.json"
check "src/server.ts 存在" "test -f src/server.ts"

# 依赖检查
check "node_modules 存在" "test -d node_modules"
check "dist 目录存在" "test -d dist"

# CLI 检查
check "MCP CLI 可执行" "test -x bin/code-intelligence-mcp"
check "Search CLI 可执行" "test -x bin/ci-search"

# 脚本检查
check "scripts 目录存在" "test -d scripts"
check "embedding.sh 可执行" "test -x scripts/embedding.sh"
check "call-chain.sh 可执行" "test -x scripts/call-chain.sh"

echo ""
echo "=== 结果：$PASS 通过，$FAIL 失败 ==="

[[ $FAIL -eq 0 ]]
```

---

## 验收矩阵

| ID | 验收项 | 验证方法 | 阻断级别 |
|----|--------|----------|----------|
| AC-001 | CLI 可启动 | `./bin/code-intelligence-mcp --version` | 阻断 |
| AC-002 | TypeScript 可编译 | `npm run build` | 阻断 |
| AC-003 | 脚本可执行 | `bash scripts/embedding.sh --help` | 阻断 |
| AC-004 | 依赖完整 | `npm ls --depth=0` | 阻断 |
| AC-005 | 搜索功能可用 | `./bin/ci-search "test"` | 警告 |
| AC-006 | ShellCheck 通过 | `npm run lint` | 警告 |

---

## 回归防护

### 关键路径

1. **MCP 协议路径**
   ```
   stdio → server.ts → handleToolCall → runScript → scripts/*.sh
   ```

2. **搜索路径**
   ```
   ci_search → embedding.sh → [Ollama/OpenAI] → 结果
   ```

3. **调用链路径**
   ```
   ci_call_chain → call-chain.sh → [CKB MCP / grep] → 结果
   ```

### 变更风险点

| 变更类型 | 风险级别 | 回归检查 |
|----------|----------|----------|
| 修改 server.ts | 高 | 所有 ST-* |
| 修改 scripts/*.sh | 中 | 对应功能测试 |
| 修改 hooks/*.sh | 低 | 钩子功能测试 |
| 修改依赖版本 | 中 | npm install + build |

---

## 下一步建议

1. **自动化测试**：为烟雾测试创建 CI 脚本
2. **集成测试**：添加 MCP 协议级别的集成测试
3. **脚本测试**：为关键脚本添加单元测试
4. **索引生成**：运行 `devbooks-index-bootstrap` 启用 SCIP 索引

---

## 基线快照

| 指标 | 当前值 | 说明 |
|------|--------|------|
| TypeScript 文件数 | 1 | src/server.ts |
| Shell 脚本数 | 13 | scripts/ + hooks/ |
| npm 依赖数 | 1 prod + 2 dev | @modelcontextprotocol/sdk |
| MCP 工具数 | 6 | 见 project-profile.md |
| 测试覆盖率 | 0% | 无自动化测试 |
