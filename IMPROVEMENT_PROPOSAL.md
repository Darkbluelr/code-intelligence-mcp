# 改进提案：增强多语言支持的用户体验

## 问题描述

当前工具描述中没有明确说明：
1. 支持哪些编程语言
2. 需要安装哪些额外的索引器
3. 如何检测和安装缺失的依赖

这导致用户可能不知道如何启用其他语言的支持，AI 也无法主动帮助用户解决依赖问题。

## 改进方案

### 方案 1：改进现有工具描述（推荐）

#### 1.1 改进 `ci_index_status` 工具

**位置**：`src/server.ts:115-127`

**当前描述**：
```typescript
description: "Check or manage the semantic search embedding index. Use 'status' to check index health, 'build' to rebuild after major code changes, 'clear' to reset. Best for: troubleshooting search issues, maintaining search quality."
```

**改进后**：
```typescript
description: `Check or manage the semantic search embedding index and language indexers.

Supported Languages & Requirements:
• TypeScript/JavaScript: ✅ Built-in (scip-typescript installed)
• Python: ⚠️ Requires scip-python
  Install: npm install -g @sourcegraph/scip-python
• Go: ⚠️ Requires scip-go
  Install: go install github.com/sourcegraph/scip-go/cmd/scip-go@latest
• Java/Scala/Kotlin: ⚠️ Requires scip-java
  Install: See github.com/sourcegraph/scip-java
• Rust: ⚠️ Requires rust-analyzer
  Install: rustup component add rust-analyzer
• C/C++: ⚠️ Requires scip-clang
  Install: See github.com/sourcegraph/scip-clang
• Ruby: ⚠️ Requires scip-ruby
  Install: gem install scip-ruby
• C#: ⚠️ Requires scip-dotnet
  Install: See github.com/sourcegraph/scip-dotnet

Actions:
- status: Check index health and detect missing language indexers
- build: Rebuild embedding index after major code changes
- clear: Clear embedding cache

Best for: troubleshooting search issues, maintaining search quality, checking language support.`
```

#### 1.2 改进 `ci_search` 工具

**位置**：`src/server.ts:40-56`

**添加语言支持说明**：
```typescript
description: `Semantic code search using embeddings or keywords. Use this for natural language queries like 'find authentication code' or 'where is error handling'.

Language Support:
• Currently indexed: TypeScript/JavaScript (via scip-typescript)
• To index other languages: Install corresponding SCIP indexer and run 'ci_index_status build'
• See 'ci_index_status' tool for full language list and installation instructions

Supports both semantic (AI-powered) and keyword search modes. Best for: discovering code by concept, finding related implementations, exploring unfamiliar codebases.`
```

### 方案 2：创建新的系统检查工具

#### 2.1 添加 `ci_system_check` 工具

**位置**：在 `src/server.ts` 的 `TOOLS` 数组中添加

```typescript
{
  name: "ci_system_check",
  description: `Check system dependencies and language indexer availability. Detects installed SCIP indexers and provides installation instructions for missing ones.

This tool helps:
- Detect which programming languages are currently supported
- Identify missing language indexers
- Provide installation commands for missing dependencies
- Check embedding provider status (Ollama/OpenAI)
- Verify optional tools (ripgrep, jq, etc.)

Best for: initial setup, troubleshooting, adding support for new languages.`,
  inputSchema: {
    type: "object" as const,
    properties: {
      check_type: {
        type: "string",
        enum: ["all", "indexers", "embeddings", "tools"],
        description: "Type of check to perform (default: all)",
      },
      format: {
        type: "string",
        enum: ["text", "json"],
        description: "Output format (default: json)",
      },
      auto_install: {
        type: "boolean",
        description: "Attempt to auto-install missing dependencies (default: false)",
      },
    },
  },
}
```

#### 2.2 创建对应的 Shell 脚本

**文件**：`scripts/system-check.sh`

```bash
#!/bin/bash
# system-check.sh - 系统依赖检查工具
# 检测已安装的 SCIP 索引器和其他依赖

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

export LOG_PREFIX="system-check"

# 检查 SCIP 索引器
check_indexers() {
    local result='{"indexers":{'

    # TypeScript/JavaScript
    if command -v scip-typescript &>/dev/null; then
        local version=$(scip-typescript --version 2>&1 | head -1 || echo "unknown")
        result+='"typescript":{"installed":true,"version":"'$version'","command":"scip-typescript"},'
    else
        result+='"typescript":{"installed":false,"install":"npm install -g @sourcegraph/scip-typescript"},'
    fi

    # Python
    if command -v scip-python &>/dev/null; then
        local version=$(scip-python --version 2>&1 | head -1 || echo "unknown")
        result+='"python":{"installed":true,"version":"'$version'","command":"scip-python"},'
    else
        result+='"python":{"installed":false,"install":"npm install -g @sourcegraph/scip-python"},'
    fi

    # Go
    if command -v scip-go &>/dev/null; then
        local version=$(scip-go --version 2>&1 | head -1 || echo "unknown")
        result+='"go":{"installed":true,"version":"'$version'","command":"scip-go"},'
    else
        result+='"go":{"installed":false,"install":"go install github.com/sourcegraph/scip-go/cmd/scip-go@latest"},'
    fi

    # Rust
    if command -v rust-analyzer &>/dev/null; then
        local version=$(rust-analyzer --version 2>&1 | head -1 || echo "unknown")
        result+='"rust":{"installed":true,"version":"'$version'","command":"rust-analyzer"},'
    else
        result+='"rust":{"installed":false,"install":"rustup component add rust-analyzer"},'
    fi

    result=${result%,}  # 移除最后的逗号
    result+='}}'

    echo "$result"
}

# 检查 embedding 提供商
check_embeddings() {
    local result='{"embeddings":{'

    # Ollama
    if command -v ollama &>/dev/null && curl -s http://localhost:11434/api/tags &>/dev/null; then
        result+='"ollama":{"installed":true,"available":true,"endpoint":"http://localhost:11434"},'
    elif command -v ollama &>/dev/null; then
        result+='"ollama":{"installed":true,"available":false,"note":"Ollama installed but not running"},'
    else
        result+='"ollama":{"installed":false,"install":"curl -fsSL https://ollama.com/install.sh | sh"},'
    fi

    # OpenAI
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        result+='"openai":{"configured":true,"note":"API key found in environment"},'
    else
        result+='"openai":{"configured":false,"note":"Set OPENAI_API_KEY environment variable"},'
    fi

    result=${result%,}
    result+='}}'

    echo "$result"
}

# 检查可选工具
check_tools() {
    local result='{"tools":{'

    for tool in ripgrep jq git curl; do
        if command -v "$tool" &>/dev/null; then
            local version=$($tool --version 2>&1 | head -1 || echo "unknown")
            result+='"'$tool'":{"installed":true,"version":"'$version'"},'
        else
            result+='"'$tool'":{"installed":false},'
        fi
    done

    result=${result%,}
    result+='}}'

    echo "$result"
}

# 主函数
main() {
    local check_type="${1:-all}"
    local format="${2:-json}"

    case "$check_type" in
        indexers)
            check_indexers
            ;;
        embeddings)
            check_embeddings
            ;;
        tools)
            check_tools
            ;;
        all)
            local indexers=$(check_indexers)
            local embeddings=$(check_embeddings)
            local tools=$(check_tools)

            # 合并 JSON
            echo '{"status":"ok",'
            echo "$indexers" | sed 's/^{//' | sed 's/}$/,/'
            echo "$embeddings" | sed 's/^{//' | sed 's/}$/,/'
            echo "$tools" | sed 's/^{//' | sed 's/}$//'
            echo '}'
            ;;
        *)
            log_error "Unknown check type: $check_type"
            exit 1
            ;;
    esac
}

main "$@"
```

#### 2.3 在 `tool-handlers.ts` 中添加处理器

**位置**：`src/tool-handlers.ts`

```typescript
async ci_system_check(
  args: Record<string, unknown>,
  runScript: (script: string, args: string[]) => Promise<{ stdout: string; stderr: string }>
): Promise<string> {
  const checkType = (args.check_type as string) || "all";
  const format = (args.format as string) || "json";

  const { stdout, stderr } = await runScript("system-check.sh", [checkType, format]);

  if (stderr) {
    return `Warning: ${stderr}\n\n${stdout}`;
  }

  return stdout;
}
```

### 方案 3：改进文档

#### 3.1 在 README.zh-CN.md 中添加多语言支持章节

**位置**：在"配置"章节之后添加

```markdown
## 多语言支持

Code Intelligence MCP Server 通过 SCIP 协议支持多种编程语言。

### 已支持的语言

| 语言 | 索引器 | 安装状态 | 安装命令 |
|------|--------|----------|----------|
| TypeScript/JavaScript | scip-typescript | ✅ 内置 | 已安装 |
| Python | scip-python | ⚠️ 需安装 | `npm install -g @sourcegraph/scip-python` |
| Go | scip-go | ⚠️ 需安装 | `go install github.com/sourcegraph/scip-go/cmd/scip-go@latest` |
| Java/Scala/Kotlin | scip-java | ⚠️ 需安装 | 参见 [scip-java](https://github.com/sourcegraph/scip-java) |
| Rust | rust-analyzer | ⚠️ 需安装 | `rustup component add rust-analyzer` |
| C/C++ | scip-clang | ⚠️ 需安装 | 参见 [scip-clang](https://github.com/sourcegraph/scip-clang) |
| Ruby | scip-ruby | ⚠️ 需安装 | `gem install scip-ruby` |
| C# | scip-dotnet | ⚠️ 需安装 | 参见 [scip-dotnet](https://github.com/sourcegraph/scip-dotnet) |

### 检查系统支持

使用 `ci_system_check` 工具检查当前系统支持的语言：

```bash
# 通过 MCP 工具
ci_system_check --check-type all

# 或直接运行脚本
./scripts/system-check.sh all json
```

### 添加新语言支持

1. **安装对应的 SCIP 索引器**（参见上表）
2. **在项目目录生成索引**：
   ```bash
   cd /path/to/your/project
   scip-python index .  # 以 Python 为例
   ```
3. **验证索引**：
   ```bash
   ci_index_status --action status
   ```

### 自动检测

项目会自动检测项目类型并使用相应的索引器：
- 检测到 `tsconfig.json` 或 `package.json` → 使用 scip-typescript
- 检测到 `pyproject.toml` 或 `setup.py` → 使用 scip-python
- 检测到 `go.mod` → 使用 scip-go
- 检测到 `Cargo.toml` → 使用 rust-analyzer
```

## 实施优先级

1. **高优先级**：改进 `ci_index_status` 工具描述（方案 1.1）
   - 影响：立即改善用户体验
   - 工作量：小（只需修改描述文本）
   - 风险：无

2. **中优先级**：创建 `ci_system_check` 工具（方案 2）
   - 影响：提供主动的依赖检查能力
   - 工作量：中（需要新建脚本和处理器）
   - 风险：低

3. **低优先级**：改进文档（方案 3）
   - 影响：帮助用户理解多语言支持
   - 工作量：小
   - 风险：无

## 预期效果

实施后，AI 助手将能够：
1. ✅ 自动识别用户项目的编程语言
2. ✅ 检测缺失的索引器依赖
3. ✅ 提供具体的安装命令
4. ✅ 引导用户完成设置流程

用户体验改进：
- 减少"为什么我的 Python 项目搜索不到代码"的困惑
- AI 可以主动提示"检测到 Python 项目，但未安装 scip-python，是否需要安装？"
- 降低多语言项目的配置门槛

## 示例对话流程

**改进前**：
```
用户：为什么搜索不到我的 Python 代码？
AI：让我检查一下... [无法给出明确答案]
```

**改进后**：
```
用户：为什么搜索不到我的 Python 代码？
AI：让我检查系统状态... [调用 ci_system_check]
AI：检测到您的项目是 Python 项目，但系统未安装 scip-python 索引器。
    需要安装吗？安装命令：npm install -g @sourcegraph/scip-python
用户：好的，请安装
AI：[执行安装命令] 安装完成！现在运行索引生成...
```

## 总结

这个改进方案通过三个层次（工具描述、系统检查工具、文档）全面提升多语言支持的用户体验，让 AI 能够主动发现和解决依赖问题，显著降低用户的配置门槛。
