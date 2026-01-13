# 项目画像：Code Intelligence MCP Server

> 生成时间：2026-01-10（更新：2026-01-11）
> 生成方式：Brownfield Bootstrap（SCIP 索引可用）

---

## 第一层：快速定位（30秒阅读）

### 项目概述

| 属性 | 值 |
|------|-----|
| 项目名称 | code-intelligence-mcp |
| 项目类型 | MCP Server（Model Context Protocol） |
| 主要用途 | 为 AI 编程助手提供代码智能能力 |
| 技术栈 | TypeScript + Node.js + Shell Scripts |
| 当前版本 | 0.2.0 |

### 核心功能

| 功能 | 描述 | 入口 |
|------|------|------|
| 语义搜索 | 使用 Embedding 进行代码语义搜索 | `ci_search` |
| 调用链追踪 | 追踪函数调用链（callers/callees） | `ci_call_chain` |
| Bug 定位 | 基于错误描述智能定位潜在 Bug 位置 | `ci_bug_locate` |
| 复杂度分析 | 代码复杂度指标分析 | `ci_complexity` |
| Graph-RAG | 图基检索增强生成上下文 | `ci_graph_rag` |
| 索引管理 | Embedding 索引状态管理 | `ci_index_status` |

### 目录结构

```
code-intelligence-mcp/
├── src/                    # TypeScript 源码
│   └── server.ts          # MCP 服务器入口（薄壳）
├── scripts/               # 核心功能脚本
│   ├── embedding.sh       # Embedding 搜索
│   ├── call-chain.sh      # 调用链追踪
│   ├── bug-locator.sh     # Bug 定位
│   ├── complexity.sh      # 复杂度分析
│   ├── graph-rag.sh       # Graph-RAG
│   └── indexer.sh         # 索引管理
├── hooks/                 # Claude Code 钩子
│   └── augment-context-global.sh  # 全局上下文注入
├── bin/                   # CLI 入口
│   ├── code-intelligence-mcp     # MCP 服务器启动器
│   └── ci-search                 # 独立搜索命令
├── config/                # 配置模板
├── dev-playbooks/         # DevBooks Skills 和模板
└── dev-playbooks/              # OpenSpec 规范目录
```

---

## 第二层：开发约定（3分钟阅读）

### 技术栈详情

| 层级 | 技术 | 版本要求 |
|------|------|----------|
| 运行时 | Node.js | >= 18.0.0 |
| 语言 | TypeScript | ^5.0.0 |
| 协议 | MCP SDK | ^1.0.0 |
| 脚本 | Bash | - |
| 工具 | ripgrep, jq | - |

### 架构模式

**薄壳模式（Thin Shell）**：
- MCP Server 使用 TypeScript 作为薄壳
- 核心功能由 Shell 脚本实现
- 设计约束：`CON-TECH-002: MCP Server 使用 Node.js 薄壳调用 Shell 脚本`

```
[Claude Code] → [MCP Protocol] → [server.ts] → [scripts/*.sh]
```

### 命令速查

| 命令 | 用途 |
|------|------|
| `npm install` | 安装依赖 |
| `npm run build` | 编译 TypeScript |
| `npm run start` | 启动 MCP Server |
| `npm run lint` | 运行 ShellCheck |
| `./install.sh` | 安装脚本 |
| `./install.sh --global` | 全局安装 |
| `./install.sh --with-hook` | 安装 Claude Code 钩子 |

### 代码风格约定

- TypeScript：严格模式（`strict: true`）
- ES 模块：使用 `NodeNext` 模块解析
- Shell 脚本：使用 `set -euo pipefail`
- 命名：
  - MCP 工具名：`ci_*` 前缀（snake_case）
  - 脚本文件：`*.sh`（kebab-case）

### 测试策略

- 当前状态：无自动化测试（`npm test` 输出 "No tests yet"）
- 建议：添加脚本单元测试和 MCP 集成测试

---

## 第三层：深度约定（按需阅读）

### 边界识别

| 类型 | 路径 | 说明 |
|------|------|------|
| 用户代码 | `src/`, `scripts/`, `hooks/` | 可修改 |
| 库代码 | `node_modules/` | 不可变接口 |
| 生成代码 | `dist/` | 禁止手动修改 |
| 配置模板 | `config/` | 复制后修改 |
| DevBooks | `dev-playbooks/` | 独立子项目 |

### 依赖方向约束

```
server.ts → scripts/*.sh → 外部工具 (rg, jq, CKB MCP)
     ↓
  MCP SDK
```

禁止：
- scripts 不得直接导入 TypeScript 模块
- 循环依赖

### 外部依赖

| 依赖 | 用途 | 必需 |
|------|------|------|
| ripgrep (rg) | 文本搜索 | 推荐 |
| jq | JSON 处理 | 推荐 |
| Ollama / OpenAI | Embedding 生成 | 可选 |
| CKB MCP Server | 图基代码分析 | 可选 |

### 配置层级

1. **全局配置**：`~/.claude/settings.json`（钩子配置）
2. **项目配置**：`.devbooks/config.yaml`（协议发现）
3. **运行时配置**：环境变量

### 已知设计约束

| 约束 ID | 描述 |
|---------|------|
| CON-TECH-002 | MCP Server 使用 Node.js 薄壳调用 Shell 脚本 |
| CON-PUB-003 | 安装方式统一为 git clone + ./install.sh |

---

## 验收锚点（最小基线）

### 烟雾测试

```bash
# 1. 检查 CLI 可用
./bin/code-intelligence-mcp --version  # 期望输出版本号

# 2. 检查 TypeScript 编译
npm run build  # 期望无错误

# 3. 检查脚本权限
ls -la scripts/*.sh  # 期望有执行权限
```

### 健康检查清单

| 检查项 | 验证命令 | 期望结果 |
|--------|----------|----------|
| Node.js 版本 | `node -v` | >= 18.0.0 |
| 依赖安装 | `npm ls` | 无错误 |
| TypeScript 编译 | `npm run build` | 成功 |
| CLI 可用 | `./bin/ci-search --help` | 显示帮助 |

---

## 索引状态

| 后端 | 状态 | 说明 |
|------|------|------|
| SCIP | ✅ 可用 | index.scip (46KB) TypeScript 索引 |
| LSP | 不可用 | 无服务器运行 |
| Git | 可用 | 可用于历史分析 |

**索引生成命令**：
```bash
scip-typescript index --output index.scip
```
