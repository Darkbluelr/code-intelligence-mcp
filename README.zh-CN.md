# Code Intelligence MCP Server

> 为 AI 编程助手提供智能代码分析和上下文检索的 Model Context Protocol (MCP) 服务器。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Node.js Version](https://img.shields.io/badge/node-%3E%3D18.0.0-brightgreen)](https://nodejs.org/)

[English](README.md) | 简体中文

## 这是什么？

Code Intelligence MCP Server 通过以下功能增强 AI 编程助手对代码库的理解：

- **语义搜索**：通过含义而非关键词查找代码
- **Graph-RAG**：使用知识图谱的上下文感知代码检索
- **调用链分析**：追踪函数依赖和影响
- **智能上下文**：自动向 AI 对话注入相关代码片段

完美适配 [Claude Code](https://claude.ai/code)、[Cline](https://github.com/cline/cline) 或任何兼容 MCP 的 AI 助手。

## 快速开始

### 安装

```bash
git clone https://github.com/Darkbluelr/code-intelligence-mcp.git
cd code-intelligence-mcp
./install.sh
```

### 系统要求

- Node.js >= 18.0.0
- Bash shell
- [ripgrep](https://github.com/BurntSushi/ripgrep)（可选，用于更快的搜索）
- [jq](https://stedolan.github.io/jq/)（可选，用于 JSON 处理）

### 使用方式

**作为 MCP 服务器**（推荐）：

添加到 MCP 客户端配置：

```json
{
  "mcpServers": {
    "code-intelligence": {
      "command": "code-intelligence-mcp",
      "args": []
    }
  }
}
```

**命令行**：

```bash
ci-search "查找认证代码"
ci-search --help
```

## 核心功能

### 语义代码搜索
```bash
# 自然语言查询
ci-search "用户认证是如何工作的"
```

### Graph-RAG 上下文检索
```bash
# 获取相关上下文并智能裁剪
ci_graph_rag --query "修复登录 bug" --budget 8000
```

### 调用链追踪
```bash
# 追踪函数依赖
ci_call_chain --symbol "handleLogin" --depth 3
```

### 影响分析
```bash
# 分析变更影响
ci_impact --file "src/auth.ts"
```

### Bug 定位
```bash
# 智能 bug 定位器
ci_bug_locate --error "TypeError: Cannot read property 'user'"
```

## 可用的 MCP 工具

| 工具 | 描述 |
|------|------|
| `ci_search` | 基于 embedding 的语义代码搜索 |
| `ci_graph_rag` | 基于图的上下文检索 |
| `ci_call_chain` | 函数调用链追踪 |
| `ci_bug_locate` | 智能 bug 定位 |
| `ci_complexity` | 代码复杂度分析 |
| `ci_hotspot` | 高频修改文件检测 |
| `ci_impact` | 传递影响分析 |
| `ci_arch_check` | 架构规则验证 |
| `ci_vuln` | 漏洞扫描 |

[查看全部 20+ 工具 →](docs/TECHNICAL.md#mcp-tools)

## 配置

### Embedding 提供商

支持多个 embedding 提供商：

```yaml
# config/llm-providers.yaml
embedding:
  provider: ollama  # 或 openai, anthropic
  model: nomic-embed-text
```

### 可选功能

所有功能都支持优雅降级：
- 没有 embeddings？回退到关键词搜索
- 没有 SCIP 索引？使用正则解析
- 没有外部工具？核心功能仍然可用

## 文档

- [技术文档](docs/TECHNICAL.md) - 完整 API 参考和架构
- [配置指南](docs/TECHNICAL.md#configuration) - 详细配置选项
- [架构说明](docs/TECHNICAL.md#architecture) - 系统设计和组件

## 示例

### 自动上下文注入

安装 Claude Code hook 以实现自动上下文注入：

```bash
./install.sh --with-hook
```

现在当你让 Claude "修复认证 bug" 时，相关代码会自动注入。

### 自定义查询

```bash
# 指定搜索模式
ci-search "用户服务" --mode semantic --limit 5

# 追踪调用链
ci_call_chain --symbol "processPayment" --direction both

# 检查架构
ci_arch_check --path src/
```

## 性能

以下为 2026-01-22 在本仓库的实测数据（见 `dev-playbooks/changes/20260122-verify-metrics/evidence/`）：

- 语义搜索（ci-search）：单次 ~570ms（非 P95）
- Graph-RAG 检索：首次 551ms，第二次 526ms（单次）
- 上下文压缩率（skeleton 模式、`src/server.ts`）：0.07

此前的性能目标（P95/相对提升）已转为证据跟踪，建议按版本更新。

## 贡献

欢迎贡献！请先阅读我们的[贡献指南](CONTRIBUTING.md)。

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件。

## 致谢

构建于：
- [Model Context Protocol](https://modelcontextprotocol.io/) by Anthropic
- [tree-sitter](https://tree-sitter.github.io/) 用于 AST 解析
- [SCIP](https://github.com/sourcegraph/scip) 用于代码索引

---

**需要帮助？** [提交 issue](https://github.com/Darkbluelr/code-intelligence-mcp/issues) 或查看[文档](docs/TECHNICAL.md)。
