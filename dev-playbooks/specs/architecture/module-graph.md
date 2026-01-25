# 模块依赖图：Code Intelligence MCP Server

> 生成时间：2026-01-10
> 生成方式：传统分析（SCIP 索引不可用）

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                        External Clients                          │
│                    (Claude Code, AI Assistants)                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ MCP Protocol (stdio)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                         src/server.ts                            │
│                    (MCP Server - Thin Shell)                     │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ ListTools   │  │ CallTool    │  │ Transport   │              │
│  │ Handler     │  │ Handler     │  │ (stdio)     │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ execAsync (shell)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        scripts/                                  │
│                    (Core Functionality)                          │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ embedding   │  │ call-chain  │  │ bug-locator │              │
│  │    .sh      │  │    .sh      │  │    .sh      │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ complexity  │  │ graph-rag   │  │  indexer    │              │
│  │    .sh      │  │    .sh      │  │    .sh      │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐                               │
│  │  common     │  │ cache-utils │  (shared utilities)           │
│  │    .sh      │  │    .sh      │                               │
│  └─────────────┘  └─────────────┘                               │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      External Tools                              │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  ripgrep    │  │     jq      │  │   Ollama/   │              │
│  │    (rg)     │  │             │  │   OpenAI    │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│  ┌─────────────┐                                                 │
│  │  CKB MCP    │  (optional - for graph-based analysis)         │
│  │   Server    │                                                 │
│  └─────────────┘                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 模块清单

### 核心模块

| 模块 | 路径 | 职责 | 依赖 |
|------|------|------|------|
| MCP Server | `src/server.ts` | MCP 协议处理，工具调度 | @modelcontextprotocol/sdk |
| Embedding | `scripts/embedding.sh` | 语义代码搜索 | common.sh, Ollama/OpenAI |
| Call Chain | `scripts/call-chain.sh` | 调用链追踪 | common.sh, CKB MCP |
| Bug Locator | `scripts/bug-locator.sh` | Bug 位置定位 | common.sh, embedding.sh |
| Complexity | `scripts/complexity.sh` | 复杂度分析 | common.sh |
| Graph-RAG | `scripts/graph-rag.sh` | 图基上下文检索 | common.sh, CKB MCP |
| Indexer | `scripts/indexer.sh` | 索引管理 | common.sh |

### 共享模块

| 模块 | 路径 | 职责 |
|------|------|------|
| Common | `scripts/common.sh` | 共享函数、配置、日志 |
| Cache Utils | `scripts/cache-utils.sh` | 缓存管理 |
| Reranker | `scripts/reranker.sh` | LLM 重排序 |

### 钩子模块

| 模块 | 路径 | 职责 |
|------|------|------|
| Global Context | `hooks/augment-context-global.sh` | 全局上下文注入 |
| Embedding Context | `hooks/augment-context-with-embedding.sh` | Embedding 增强上下文 |
| Context | `hooks/augment-context.sh` | 基础上下文注入 |
| Cache Manager | `hooks/cache-manager.sh` | 钩子缓存管理 |

### CLI 入口

| 模块 | 路径 | 职责 |
|------|------|------|
| MCP 入口 | `bin/code-intelligence-mcp` | 启动 MCP Server |
| 搜索入口 | `bin/ci-search` | 独立搜索命令 |

---

## 依赖矩阵

```
                    │ common │ cache  │ embed  │ call   │ bug    │ graph  │
                    │  .sh   │ utils  │ ding   │ chain  │ locator│  rag   │
────────────────────┼────────┼────────┼────────┼────────┼────────┼────────┤
server.ts           │   -    │   -    │   ✓    │   ✓    │   ✓    │   ✓    │
embedding.sh        │   ✓    │   ✓    │   -    │   -    │   -    │   -    │
call-chain.sh       │   ✓    │   -    │   -    │   -    │   -    │   -    │
bug-locator.sh      │   ✓    │   -    │   ✓    │   ✓    │   -    │   -    │
complexity.sh       │   ✓    │   -    │   -    │   -    │   -    │   -    │
graph-rag.sh        │   ✓    │   ✓    │   ✓    │   -    │   -    │   -    │
indexer.sh          │   ✓    │   -    │   -    │   -    │   -    │   -    │
```

**图例**：
- `✓` = 直接依赖
- `-` = 无依赖

---

## 依赖方向规则

### 允许的依赖方向

```
server.ts → scripts/*.sh → common.sh
                        → cache-utils.sh
                        → 外部工具
```

### 禁止的依赖

- ❌ scripts/*.sh → src/*.ts（脚本不得依赖 TypeScript）
- ❌ common.sh → 其他功能脚本（共享模块不得依赖功能模块）
- ❌ 循环依赖

---

## 外部依赖

### 必需依赖

| 依赖 | 类型 | 来源 |
|------|------|------|
| @modelcontextprotocol/sdk | npm | package.json |
| Node.js | 运行时 | 系统 |
| Bash | 运行时 | 系统 |

### 推荐依赖

| 依赖 | 类型 | 用途 |
|------|------|------|
| ripgrep (rg) | CLI 工具 | 文本搜索 |
| jq | CLI 工具 | JSON 处理 |

### 可选依赖

| 依赖 | 类型 | 用途 |
|------|------|------|
| Ollama | 服务 | 本地 Embedding |
| OpenAI API | 服务 | 云端 Embedding |
| CKB MCP Server | MCP | 图基代码分析 |
