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

完美适配 Claude Code、Cline 或任何兼容 MCP 的 AI 助手。

## 快速开始

### 安装

**通过 npm**（推荐）：

```bash
npm install -g @ozbombor/code-intelligence-mcp
```

**通过 git**：

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

服务器支持多个 embedding 提供商,并具有自动降级功能:

**三级降级策略:**
1. **Ollama**(本地,免费)→ 优先使用,无网络延迟,隐私安全
2. **OpenAI API**(云端,付费)→ Ollama 不可用时自动降级
3. **关键词搜索** → 无 embedding 服务时的最终降级方案

#### 方案 1: Ollama(推荐本地使用)

**安装:**
```bash
# 安装 Ollama
curl -fsSL https://ollama.com/install.sh | sh

# 拉取 embedding 模型
ollama pull nomic-embed-text
```

**配置:**
```yaml
# .devbooks/config.yaml
embedding:
  provider: ollama  # 或使用 'auto' 自动检测
  ollama:
    model: nomic-embed-text
    endpoint: http://localhost:11434
    timeout: 30
```

**使用:**
```bash
# 构建 embedding 索引
ci-search build

# 使用 Ollama 搜索
ci-search "认证代码"
```

#### 方案 2: OpenAI API(云端)

**设置:**
```bash
# 设置 API 密钥
export OPENAI_API_KEY="sk-..."
```

**配置:**
```yaml
# .devbooks/config.yaml
embedding:
  provider: openai
  openai:
    model: text-embedding-3-small
    api_key: ${OPENAI_API_KEY}  # 或直接设置
    base_url: https://api.openai.com/v1
    timeout: 30
```

**使用:**
```bash
# 使用 OpenAI 构建索引
ci-search build

# 或强制使用 OpenAI 进行单次搜索
ci-search "用户认证" --provider openai
```

#### 方案 3: 关键词搜索(无需设置)

关键词搜索开箱即用,无需任何配置:

```bash
# 强制使用关键词搜索
ci-search "错误处理" --provider keyword
```

#### 高级配置

**自动 Provider 检测:**
```yaml
# .devbooks/config.yaml
embedding:
  provider: auto  # 尝试 Ollama → OpenAI → 关键词
  fallback_to_keyword: true
  auto_build: true
```

**命令行覆盖:**
```bash
# 为单次搜索覆盖 provider
ci-search "测试" --provider ollama --ollama-model mxbai-embed-large

# JSON 输出与自定义设置
ci-search "支付" --format json --top-k 10 --threshold 0.7
```

**环境变量:**
- `OPENAI_API_KEY` - OpenAI API 密钥
- `EMBEDDING_API_KEY` - 通用 embedding API 密钥
- `PROJECT_ROOT` - 项目根目录

### 可选功能

所有功能都支持优雅降级：
- 没有 embeddings？回退到关键词搜索
- 没有 SCIP 索引？使用正则解析
- 没有外部工具？核心功能仍然可用

## 文档

高级用法请参考本地文档：
- 完整工具参考和示例
- 架构和系统设计
- 性能调优指南
- 故障排除技巧

运行 `./install.sh` 以访问完整本地文档。

## 示例

### 自动上下文注入

启用 Claude Code 的自动上下文注入：

```bash
ci-setup-hook
```

这会安装一个 hook，在你与 Claude 交互时自动注入相关的代码上下文，让 AI 助手无需手动查询就能了解你的代码库。

### 自定义查询

```bash
# 指定搜索模式
ci-search "用户服务" --mode semantic --limit 5

# 追踪调用链
ci_call_chain --symbol "processPayment" --direction both

# 检查架构
ci_arch_check --path src/
```

### 演示套件

运行完整的演示并进行 A/B 对比：

```bash
# 运行快速对比演示
bash demo/00-quick-compare.sh

# 运行所有演示
bash demo/run-suite.sh

# 对比版本（如果可用）
bash demo/compare.sh baseline.json current.json
```

演示套件展示：
- 自动上下文注入 vs 手动查询
- 语义搜索和 Graph-RAG 能力
- 性能基准测试和指标
- 不同配置之间的 A/B 对比

## 性能

以下指标由 `python3 benchmarks/run_benchmarks.py` 生成的 `benchmark_result.json` 自动更新。
执行 `python3 benchmarks/update_readme.py` 可刷新本段内容。

<!-- BENCHMARK:START -->
更新时间：2026-01-24T06:27:38+00:00

| 指标 | 数值 | 备注 |
| --- | --- | --- |
| 语义搜索 P95 延迟 | 222 ms | iterations=3 |
| Graph-RAG 冷启动 P95 延迟 | 862.64 ms | iterations=3 |
| Graph-RAG 热启动 P95 延迟 | 69.37 ms | iterations=3 |
| Graph-RAG 提速 | 91.96 % | cold vs warm |
| 检索质量 MRR@10 | 0.4264 | dataset=self, queries=12 |
| 检索质量 Recall@10 | 1.0 | dataset=self, queries=12 |
| 检索质量 Precision@10 | 0.3377 | dataset=self, queries=12 |
| 检索 P95 延迟 | 6.10 ms | dataset=self, queries=12 |
| 缓存命中 P95 延迟 | 75 ms | iterations=20 |
| 完整查询 P95 延迟 | 89 ms | iterations=20 |
| 预提交暂存 P95 | 35 ms | iterations=20 |
| 预提交依赖 P95 | 27 ms | iterations=20 |
| 压缩延迟 | 8.95 ms | iterations=1 |
<!-- BENCHMARK:END -->

## 贡献

欢迎贡献！请先阅读 `CONTRIBUTING.md`。

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件。

## 致谢

构建于：Model Context Protocol、tree-sitter、SCIP

---

需要帮助？请在你的仓库提交 issue 或查看 `docs/TECHNICAL.md`。
