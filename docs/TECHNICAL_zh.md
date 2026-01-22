# Code Intelligence MCP Server (代码智能 MCP 服务器)

为 AI 编程助手提供代码智能能力的 MCP 服务器。

## 功能特性

- **向量搜索 (Embedding Search)**：使用本地 (Ollama) 或云端 (OpenAI/Anthropic) 向量进行语义代码搜索。
- **LLM 供应商抽象**：支持多供应商 (Ollama/OpenAI/Anthropic)，并具备自动回退到关键词搜索的功能。
- **Graph-RAG 上下文**：基于图谱的检索增强生成，支持智能剪枝。
- **调用链追踪**：追踪函数调用链。
- **Bug 定位器**：智能 Bug 定位，支持缓存和可选的影响分析。
- **复杂度分析**：代码复杂度指标。
- **热点分析 (Hotspot Analysis)**：识别高频修改、高复杂度的文件。
- **架构守卫 (Architecture Guard)**：检测循环依赖和规则违规。
- **联邦索引 (Federation Index)**：跨仓库 API 契约追踪（带虚拟边）。
- **AST 增量 (AST Delta)**：使用 tree-sitter 进行增量 AST 解析。
- **影响分析**：传递性影响分析（带置信度衰减）。
- **熵可视化**：代码库熵可视化 (Fractal/Mermaid/ASCII)。
- **COD 可视化**：架构可视化 (Mermaid + D3.js)。
- **意图学习**：查询历史和偏好学习。
- **模式学习**：自动化代码模式发现和规则生成。
- **性能回退检测**：跨基准测试运行检测性能回退。
- **漏洞追踪**：npm audit 集成和依赖追踪。
- **ADR 解析**：解析架构决策记录 (ADR) 并链接到代码图谱。
- **对话上下文**：多轮对话历史，提高搜索相关性。
- **结构化上下文输出**：为 AI 助手提供 5 层结构化上下文。
- **DevBooks 集成**：自动检测 DevBooks 项目以增强上下文。
- **守护进程预热**：预热缓存以减少冷启动延迟。
- **请求取消**：取消陈旧请求以释放资源。
- **子图 LRU 缓存**：用于热点子图的跨进程 SQLite 缓存。
- **上下文压缩**：智能上下文压缩（在骨架模式下，`src/server.ts` 实测压缩比为 0.07）。
- **漂移检测**：针对 C4 模型合规性的架构漂移检测。
- **数据流追踪**：带污点传播的跨函数数据流追踪。
- **混合检索**：图谱 + 向量搜索结果的 RRF 融合。
- **语义异常检测**：检测 6 种类型的语义异常。
- **评估基准**：包含延迟/准确性/Token 指标的性能基准测试。
- **优雅降级**：所有可选功能在未配置时均会优雅降级。

## 安装

```bash
git clone https://github.com/user/code-intelligence-mcp.git
cd code-intelligence-mcp
./install.sh
```

## 环境要求

- Node.js >= 18.0.0
- Bash shell
- ripgrep (rg)
- jq

## 使用方法

### 作为 MCP 服务器运行

```bash
code-intelligence-mcp
```

### 命令行运行

```bash
ci-search "search query"
ci-search --help
ci-search --version
```

## MCP 工具列表

| 工具 | 描述 |
|------|-------------|
| `ci_search` | 语义代码搜索 |
| `ci_call_chain` | 追踪函数调用链 |
| `ci_bug_locate` | 智能 Bug 定位 |
| `ci_complexity` | 代码复杂度分析 |
| `ci_graph_rag` | 基于图谱的上下文检索（支持 --budget 参数进行智能剪枝） |
| `ci_index_status` | 管理向量索引（状态/构建/清除） |
| `ci_hotspot` | 热点文件分析 |
| `ci_boundary` | 边界检测 |
| `ci_arch_check` | 架构规则检查 |
| `ci_graph_store` | 图存储操作（初始化、查询、统计） |
| `ci_federation` | 跨仓库契约搜索（支持 --virtual-edges） |
| `ci_ast_delta` | 增量 AST 解析和图谱更新 |
| `ci_impact` | 带置信度衰减的传递性影响分析 |
| `ci_cod` | 架构可视化 (Mermaid/D3.js) |
| `ci_intent` | 查询历史和偏好学习 |
| `ci_vuln` | 漏洞扫描和依赖追踪 |
| `ci_adr` | 解析并索引架构决策记录 |
| `ci_warmup` | 为热点子图预热守护进程缓存 |
| `ci_context_compress` | 智能上下文压缩（骨架模式下 `src/server.ts` 实测比率 0.07） |
| `ci_drift_detect` | 针对 C4 模型的架构漂移检测 |
| `ci_semantic_anomaly` | 检测语义异常（6 种类型） |
| `ci_benchmark` | 运行性能基准测试 |

### 图存储命令 (Graph Store Commands)

```bash
# 初始化图数据库
./scripts/graph-store.sh init

# 查询图统计信息
./scripts/graph-store.sh stats

# 查找符号间的最短路径
./scripts/graph-store.sh find-path --from "symbolA" --to "symbolB" [--max-depth 10] [--edge-types CALLS,IMPORTS]

# 迁移图模式（用于升级）
./scripts/graph-store.sh migrate --check   # 检查是否需要迁移
./scripts/graph-store.sh migrate --apply   # 应用迁移并自动备份
./scripts/graph-store.sh migrate --status  # 显示当前模式版本
```

### 带影响分析的 Bug 定位器

```bash
# 基本 Bug 定位
./scripts/bug-locator.sh --error "NullPointerException in OrderService"

# 带影响分析（显示受影响的文件）
./scripts/bug-locator.sh --error "NullPointerException" --with-impact [--impact-depth 3]
```

`--with-impact` 的输出示例：
```json
{
  "schema_version": "1.0",
  "candidates": [
    {
      "symbol": "processOrder",
      "file": "src/order.ts",
      "line": 42,
      "score": 85.5,
      "impact": {
        "total_affected": 12,
        "affected_files": ["src/checkout.ts", "src/inventory.ts"],
        "max_depth": 3
      }
    }
  ]
}
```

### ADR 解析

```bash
# 扫描所有 ADR (自动发现 docs/adr, doc/adr, ADR, adr)
./scripts/adr-parser.sh scan

# 扫描并将 ADR 关键词链接到图谱中
./scripts/adr-parser.sh scan --link

# 解析单个 ADR 文件
./scripts/adr-parser.sh parse docs/adr/0001-use-sqlite.md
```

### 守护进程管理 (Daemon Management)

```bash
# 启动守护进程
./scripts/daemon.sh start

# 预热缓存（参见冷/热启动时间证据）
./scripts/daemon.sh warmup

# 检查预热状态
./scripts/daemon.sh status
```

### 对话上下文 (Conversation Context)

```bash
# 开始新的会话
./scripts/intent-learner.sh session new

# 恢复现有会话
./scripts/intent-learner.sh session resume <session-id>

# 列出会话
./scripts/intent-learner.sh session list

# 清除会话
./scripts/intent-learner.sh session clear
```

### 缓存管理

```bash
# 查看缓存统计
./scripts/cache-manager.sh stats

# 清除缓存
./scripts/cache-manager.sh clear

# 获取缓存的子图
./scripts/cache-manager.sh cache-get <cache-key>

# 设置缓存子图
./scripts/cache-manager.sh cache-set <cache-key> <value>
```

### 上下文压缩

```bash
# 压缩文件（骨架模式）
./scripts/context-compressor.sh src/server.ts

# 使用 Token 预算压缩目录
./scripts/context-compressor.sh --budget 4000 src/

# 启用缓存并优先处理热点目录
./scripts/context-compressor.sh --cache --hotspot src/ src/
```

压缩模式：
- `skeleton`：仅提取函数/类签名（当前支持的模式）

### 漂移检测 (Drift Detection)

```bash
# 比较两个快照
./scripts/drift-detector.sh --compare baseline.json current.json

# 生成快照
./scripts/drift-detector.sh --snapshot . --output snapshot.json

# 将代码库与 C4 模型进行比较
./scripts/drift-detector.sh --c4 dev-playbooks/specs/architecture/c4.md --code .
```

输出示例：
```json
{
  "status": "drift_detected",
  "drifts": [
    {
      "type": "MISSING_CONTAINER",
      "file": "scripts/new-feature.sh",
      "message": "File not documented in C4 Container Inventory"
    },
    {
      "type": "STALE_CONTAINER",
      "container": "old-script.sh",
      "message": "Documented in C4 but file does not exist"
    }
  ],
  "compliance_score": 0.85
}
```

### 数据流追踪

```bash
# 从符号向前追踪数据流
./scripts/call-chain.sh --data-flow userInput --data-flow-direction forward

# 向后追踪以查找数据源
./scripts/call-chain.sh --data-flow dbQuery --data-flow-direction backward

# 双向追踪
./scripts/call-chain.sh --data-flow data --data-flow-direction both --max-depth 5

# 包含转换详情
./scripts/call-chain.sh --data-flow req.body --include-transforms --format json
```

### 语义异常检测

```bash
# 扫描目录中的语义异常
./scripts/semantic-anomaly.sh src/

# 扫描特定文件
./scripts/semantic-anomaly.sh src/api.ts

# 使用自定义模式文件
./scripts/semantic-anomaly.sh --pattern my-patterns.json src/

# 设置置信度阈值
./scripts/semantic-anomaly.sh --threshold 0.9 src/

# 输出格式
./scripts/semantic-anomaly.sh --output json src/
./scripts/semantic-anomaly.sh --output text src/
```

异常类型：
- `MISSING_ERROR_HANDLER`：未处理的 async/throw 操作
- `INCONSISTENT_API_CALL`：跨文件调用同一 API 的方式不一致
- `NAMING_VIOLATION`：命名约定违规
- `MISSING_LOG`：关键点缺失日志
- `UNUSED_IMPORT`：导入但未使用的模块
- `DEPRECATED_PATTERN`：使用已弃用的代码模式

### 评估基准

```bash
# 运行数据集基准测试
./scripts/benchmark.sh --dataset self --queries queries.jsonl --output results/benchmark.json

# 与基线比较
./scripts/benchmark.sh --compare results/baseline.json results/benchmark.json

# 传统模式
./scripts/benchmark.sh --all
./scripts/benchmark.sh --cache
```

### 模式学习 (Pattern Learning)

自动发现代码模式并生成一致性检查规则。

```bash
# 在目录中发现代码模式
./scripts/pattern-learner.sh discover src/

# 从学习到的模式生成规则
./scripts/pattern-learner.sh generate-rules --output config/learned-rules.yaml

# 将学习到的模式应用到新代码
./scripts/pattern-learner.sh apply --rules config/learned-rules.yaml src/new-feature/

# 显示模式统计
./scripts/pattern-learner.sh stats
```

### 性能回退检测

通过比较基准测试结果来检测性能回退。

```bash
# 针对基线运行性能回退检查
./scripts/performance-regression.sh --baseline results/baseline.json

# 比较两份基准测试报告
./scripts/performance-regression.sh --compare results/before.json results/after.json

# 设置自定义回退阈值（默认：10%）
./scripts/performance-regression.sh --threshold 15 --baseline results/baseline.json

# 生成回退报告
./scripts/performance-regression.sh --report --baseline results/baseline.json --output results/regression-report.md
```

### LLM 供应商管理

管理和测试用于语义搜索的 LLM 供应商。

```bash
# 检查当前供应商状态
./scripts/llm-provider.sh status

# 测试供应商连接性
./scripts/llm-provider.sh test ollama
./scripts/llm-provider.sh test openai
./scripts/llm-provider.sh test anthropic

# 切换供应商（更新配置）
./scripts/llm-provider.sh switch anthropic

# 列出可用供应商
./scripts/llm-provider.sh list
```

## 结构化上下文输出

`context-inject-global.sh` 钩子输出一个 5 层结构的 JSON：

```json
{
  "project_profile": {
    "name": "my-project",
    "tech_stack": ["TypeScript", "Node.js"],
    "architecture": "microservices",
    "key_constraints": ["no-ui-to-db"]
  },
  "current_state": {
    "index_status": "ready",
    "hotspot_files": ["src/order.ts", "src/auth.ts"],
    "recent_commits": ["fix: order validation", "feat: add caching"]
  },
  "task_context": {
    "intent_analysis": {},
    "relevant_snippets": [],
    "call_chains": []
  },
  "recommended_tools": [
    { "tool": "ci_bug_locate", "reason": "Error investigation", "suggested_params": {} }
  ],
  "constraints": {
    "architectural": ["shared <- core <- integration"],
    "security": ["no hardcoded secrets"]
  }
}
```

使用 `--format text` 可获得纯文本输出。

## CI/CD 集成

### GitHub Actions

添加 `.github/workflows/arch-check.yml` 到你的仓库：

```yaml
name: Architecture Check
on: [pull_request]
jobs:
  arch-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check for cycles
        run: ./scripts/dependency-guard.sh --cycles --format json
      - name: Check for orphan modules
        run: ./scripts/dependency-guard.sh --orphans --format json
      - name: Check architecture rules
        run: ./scripts/boundary-detector.sh detect --rules config/arch-rules.yaml --format json
```

### GitLab CI

复制 `.gitlab-ci.yml.template` 到 `.gitlab-ci.yml` 并按需定制。

## LLM 供应商配置

服务器支持多个 LLM 供应商，并在语义搜索和向量操作时自动回退。

### 供应商优先级（自动回退）

1.  **Ollama** (默认, 本地) - 无需 API Key
2.  **OpenAI** (云端) - 需要 API Key
3.  **Anthropic** (云端) - 需要 API Key
4.  **关键词搜索** (回退) - 始终可用，无需配置

### 配置方法

**方法 1: 环境变量**

```bash
# 选择供应商 (默认: ollama)
export LLM_DEFAULT_PROVIDER="ollama"  # 或 "openai", "anthropic"

# Ollama 配置 (本地)
export OLLAMA_ENDPOINT="http://localhost:11434"
export OLLAMA_MODEL="nomic-embed-text"

# OpenAI 配置
export OPENAI_API_KEY="sk-..."
export LLM_ENDPOINT="https://api.openai.com/v1"

# Anthropic 配置
export ANTHROPIC_API_KEY="sk-ant-..."
```

**方法 2: 配置文件** (`config/llm-providers.yaml`)

```yaml
default_provider: ollama

providers:
  ollama:
    endpoint: http://localhost:11434
    model: nomic-embed-text
    timeout: 30

  openai:
    api_key: ${OPENAI_API_KEY}
    model: text-embedding-3-small
    max_tokens: 4096

  anthropic:
    api_key: ${ANTHROPIC_API_KEY}
    model: claude-3-haiku-20240307
```

### 未配置时的行为

-   **未配置 LLM**：自动回退到关键词搜索（基于 ripgrep）。
-   **Ollama 未运行**：尝试 OpenAI，然后 Anthropic，最后是关键词搜索。
-   **缺少 API Key**：跳过该供应商并尝试优先级中的下一个。
-   **所有供应商均失败**：返回关键词搜索结果并附带警告。

**注意**：关键词搜索作为一种回退机制始终可用，无需配置。系统会优雅降级而不会抛出错误。

## 配置

复制 `config/config.yaml.template` 到项目的 `.devbooks/config.yaml`。

### 环境变量

以下环境变量控制服务器的行为。除非标记为“有条件”，否则所有变量均为可选。

#### 核心配置

| 变量 | 是否必需 | 默认值 | 描述 | 未设置时的行为 |
|----------|----------|---------|-------------|----------------------|
| `OPENAI_API_KEY` | 有条件 | - | OpenAI API Key | OpenAI 供应商不可用，回退到下一个供应商 |
| `ANTHROPIC_API_KEY` | 有条件 | - | Anthropic API Key | Anthropic 供应商不可用，回退到下一个供应商 |
| `OLLAMA_ENDPOINT` | 可选 | `http://localhost:11434` | Ollama API 端点 | 使用默认端点 |
| `OLLAMA_MODEL` | 可选 | `nomic-embed-text` | Ollama 向量模型 | 使用默认模型 |
| `GRAPH_DB_PATH` | 可选 | `.devbooks/graph.db` | SQLite 图数据库路径 | 在默认位置创建数据库 |

#### LLM 供应商配置

| 变量 | 是否必需 | 默认值 | 描述 | 未设置时的行为 |
|----------|----------|---------|-------------|----------------------|
| `LLM_DEFAULT_PROVIDER` | 可选 | `ollama` | LLM 供应商 (`ollama`, `openai`, `anthropic`) | 默认使用 Ollama |
| `LLM_DEFAULT_MODEL` | 可选 | 特定于供应商 | LLM 模型名称 | 使用供应商的默认模型 |
| `LLM_ENDPOINT` | 可选 | 特定于供应商 | LLM API 端点 | 使用供应商的默认端点 |
| `LLM_MAX_TOKENS` | 可选 | `4096` | LLM 请求的最大 Token 数 | 使用默认限制 |

#### 索引与缓存

| 变量 | 是否必需 | 默认值 | 描述 | 未设置时的行为 |
|----------|----------|---------|-------------|----------------------|
| `DISABLE_TREE_SITTER` | 可选 | `false` | 强制禁用 Tree-sitter | 如果可用则使用 Tree-sitter，否则回退到文本解析 |
| `FORCE_SCIP_FALLBACK` | 可选 | `false` | 强制 SCIP 回退模式 | 可用时使用 Tree-sitter |
| `SCIP_PROTO_URL` | 可选 | (Google Storage) | 自定义 scip.proto 下载 URL | 使用默认 URL |
| `AST_CACHE_DIR` | 可选 | `.devbooks/ast-cache` | AST 缓存目录 | 在默认位置创建缓存 |
| `AST_CACHE_TTL_DAYS` | 可选 | `7` | AST 缓存过期时间（天） | 使用默认 TTL |
| `AST_CACHE_MAX_SIZE_MB` | 可选 | `100` | AST 缓存最大大小 (MB) | 使用默认大小限制 |

#### 联邦与跨仓库

| 变量 | 是否必需 | 默认值 | 描述 | 未设置时的行为 |
|----------|----------|---------|-------------|----------------------|
| `FEDERATION_CONFIG` | 可选 | `config/federation.yaml` | 联邦配置文件路径 | 无跨仓库追踪，工具返回空结果 |
| `FEDERATION_INDEX` | 可选 | `.devbooks/federation-index.json` | 联邦索引文件路径 | 在默认位置创建索引 |

#### 功能开关

| 变量 | 是否必需 | 默认值 | 描述 | 未设置时的行为 |
|----------|----------|---------|-------------|----------------------|
| `FEATURES_CONFIG` | 可选 | `config/features.yaml` | 功能开关配置文件 | 默认启用所有功能 |
| `DEVBOOKS_ENABLE_ALL_FEATURES` | 可选 | - | 强制启用所有功能（覆盖配置） | 遵循功能配置文件 |
| `CI_AST_DELTA_ENABLED` | 可选 | - | 覆盖 `ast_delta.enabled` | 使用配置文件值 |
| `CI_FILE_THRESHOLD` | 可选 | - | 覆盖 `ast_delta.file_threshold` | 使用配置文件值 |
| `DEBOUNCE_SECONDS` | 可选 | - | 覆盖 `indexer.debounce_seconds` | 使用配置文件值 |

#### 守护进程与性能

| 变量 | 是否必需 | 默认值 | 描述 | 未设置时的行为 |
|----------|----------|---------|-------------|----------------------|
| `DAEMON_WARMUP_ENABLED` | 可选 | `true` | 启用守护进程预热 | 预热禁用，冷启动延迟较高 |
| `DAEMON_WARMUP_TIMEOUT` | 可选 | `30` | 预热超时时间（秒） | 使用默认超时 |
| `DAEMON_CANCEL_ENABLED` | 可选 | `true` | 启用请求取消 | 陈旧请求不被取消 |
| `GRAPH_WAL_MODE` | 可选 | `true` | 启用 SQLite WAL 模式 | 使用默认日志模式 |

#### Bug 定位器

| 变量 | 是否必需 | 默认值 | 描述 | 未设置时的行为 |
|----------|----------|---------|-------------|----------------------|
| `BUG_LOCATOR_WITH_IMPACT` | 可选 | `false` | 在 Bug 定位器中启用影响分析 | 返回不带影响分析的 Bug 位置 |
| `BUG_LOCATOR_IMPACT_DEPTH` | 可选 | `3` | 影响分析深度 | 使用默认深度 |

#### 意图学习

| 变量 | 是否必需 | 默认值 | 描述 | 未设置时的行为 |
|----------|----------|---------|-------------|----------------------|
| `INTENT_HISTORY_PATH` | 可选 | `.devbooks/intent-history.json` | 意图历史文件路径 | 在默认位置创建历史记录 |
| `INTENT_MAX_ENTRIES` | 可选 | `10000` | 最大意图历史条目数 | 使用默认限制 |

#### 调试与日志

| 变量 | 是否必需 | 默认值 | 描述 | 未设置时的行为 |
|----------|----------|---------|-------------|----------------------|
| `DEBUG` | 可选 | `false` | 启用调试输出 | 禁用调试输出 |
| `LOG_LEVEL` | 可选 | `INFO` | 日志级别 (`DEBUG`, `INFO`, `WARN`, `ERROR`) | 使用 INFO 级别 |
| `NO_COLOR` | 可选 | - | 禁用彩色输出 | 在 TTY 中启用颜色 |

### 架构规则

在 `config/arch-rules.yaml` 中定义架构规则：

```yaml
rules:
  - id: no-ui-to-db
    from: "src/ui/**"
    to: "src/db/**"
    severity: error
    message: "UI layer cannot import DB layer directly"
```

### 联邦配置

在 `config/federation.yaml` 中配置跨仓库追踪：

```yaml
repositories:
  - path: ./api-contracts
    type: local
    patterns:
      - "*.proto"
      - "openapi.yaml"
```

### 功能开关

在 `config/features.yaml` 中控制功能模块：

```yaml
features:
  graph_store:
    enabled: true
    wal_mode: true
  llm_rerank:
    enabled: false
    provider: anthropic

  # AST 增量索引 (优化索引管道: AC-001)
  ast_delta:
    enabled: true  # 设置为 false 以禁用增量路径
    file_threshold: 10  # 文件数 > 阈值触发全量重建

  # 索引调度器 (优化索引管道: AC-003, AC-007)
  indexer:
    debounce_seconds: 2  # 在此窗口内聚合更改
    offline_proto: true  # 使用 vendored/scip.proto
    allow_proto_download: false  # 设置为 true 以允许下载 proto

  smart_pruning:
    enabled: true
    default_budget: 8000
  daemon:
    enabled: true
    warmup:
      enabled: true
      timeout_seconds: 30
      hotspot_limit: 10
    cancel:
      enabled: true
      check_interval_ms: 50
  intent_learner:
    enabled: true
    max_history_entries: 10000

  # 上下文压缩 (20260118-2112: AC-001)
  context_compressor:
    enabled: true
    default_budget: 8000
    min_compression_ratio: 0.3
    max_compression_ratio: 0.5
    strategy: smart  # skeleton, smart, truncate

  # 架构漂移检测 (20260118-2112: AC-002)
  drift_detector:
    enabled: true
    c4_path: dev-playbooks/specs/architecture/c4.md
    auto_fix: false

  # 语义异常检测 (20260118-2112: AC-003)
  semantic_anomaly:
    enabled: true
    severity_threshold: warning  # error, warning, info

  # 代码库熵可视化
  entropy_visualization:
    enabled: true
    mermaid: true           # 生成 Mermaid 图表
    ascii_dashboard: true   # 在 CLI 中显示 ASCII 仪表板

  # 影响分析配置
  impact_analyzer:
    max_depth: 5            # 最大传播深度
    decay_factor: 0.5       # 每跳置信度衰减
    threshold: 0.2          # 报告的最小置信度

  # 评估基准 (20260118-2112: AC-012)
  benchmark:
    enabled: false  # 仅在运行基准测试时启用
    output_dir: results/
```

环境变量覆盖：
- `CI_AST_DELTA_ENABLED`：覆盖 `ast_delta.enabled`
- `CI_FILE_THRESHOLD`：覆盖 `ast_delta.file_threshold`
- `DEBOUNCE_SECONDS`：覆盖 `indexer.debounce_seconds`

### Vendored Proto (离线模式)

SCIP proto 文件已内置以支持离线操作：

```bash
# 检查 proto 版本和兼容性
./scripts/vendor-proto.sh --check

# 从 GitHub 升级 proto
./scripts/vendor-proto.sh --upgrade

# 查看当前版本
./scripts/vendor-proto.sh --version
```

Proto 发现优先级：
1. `$SCIP_PROTO_PATH` 环境变量
2. `vendored/scip.proto` (默认，内置)
3. `/tmp/scip.proto` 中的缓存 proto
4. 下载 (仅当 `allow_proto_download: true`)

### 数据文件

以下数据文件会自动在 `.devbooks/` 中创建：

| 文件 | 用途 | 是否可安全删除 |
|------|---------|----------------|
| `graph.db` | 图数据库 (SQLite) | 是，下次索引时会重建 |
| `subgraph-cache.db` | 热点子图的 LRU 缓存 | 是，会自动重建 |
| `conversation-context.json` | 对话历史 | 是，将重新开始 |
| `adr-index.json` | ADR 索引缓存 | 是，下次解析时会重建 |
| `intent-history.json` | 用于学习的查询历史 | 是，将重新开始 |

### 可选配置行为

本节说明未提供可选配置时会发生什么。系统设计为优雅降级。

#### 向量与搜索

**当未配置 LLM 供应商时：**
- 系统自动回退到关键词搜索（基于 ripgrep）
- 语义搜索命令仍然工作，但使用关键词匹配
- 不会抛出错误；降级功能是透明的
- 性能：关键词搜索更快，但对于概念性查询准确度较低

**当 Tree-sitter 被禁用或不可用时：**
- 系统回退到基于文本的解析
- 索引仍然工作，但对于复杂语法的准确度降低
- 对于大文件，性能可能会稍慢

#### 联邦与跨仓库

**当未提供联邦配置时：**
- `ci_federation` 工具仍然可用且功能正常
- 所有联邦命令返回空结果，状态为 `"empty"`
- 不会抛出错误；优雅降级
- 响应示例：
  ```json
  {
    "status": "empty",
    "edges_created": 0,
    "message": "No federation index found at .devbooks/federation-index.json"
  }
  ```

**当联邦索引丢失时：**
- `generate-virtual-edges` 在首次运行时自动创建索引
- 其他联邦命令在索引构建前返回空结果
- 使用 `ci_federation --action update` 构建索引

#### 图数据库

**当图数据库不存在时：**
- 首次使用时自动创建数据库
- 默认位置：`.devbooks/graph.db`
- 无需手动初始化
- 对于大型代码库，初始索引可能需要几秒钟

#### 缓存与性能

**当未配置缓存时：**
- 自动在 `.devbooks/` 中创建缓存目录
- 所有缓存类型使用默认缓存位置
- 缓存是可选的；系统在没有它的情况下也能工作（重复查询变慢）
- 缓存提高重复操作的性能（见证据）

**当禁用守护进程预热时：**
- 冷启动延迟较高（见证据）
- 后续查询不受影响
- 无功能影响，仅影响性能
- 建议在生产环境中启用

#### ADR 解析

**当未指定 ADR 目录时：**
- 系统在常见位置自动发现 ADR：
  - `docs/adr/`
  - `doc/adr/`
  - `ADR/`
  - `adr/`
- 如果未找到 ADR，命令返回空结果
- 不会抛出错误

#### SCIP Proto

**当未配置 SCIP proto 时：**
- 系统按优先级顺序搜索：
  1. `$SCIP_PROTO_PATH` 环境变量
  2. `vendored/scip.proto` (捆绑，始终可用)
  3. `/tmp/scip.proto` 中的缓存 proto
  4. 从 GitHub 下载 (仅当 `allow_proto_download: true`)
- 通过内置 proto 完全支持离线操作
- 正常操作无需互联网连接

### 边界检测

在 `config/boundaries.yaml` 中配置代码边界规则：

```yaml
rules:
  - pattern: "node_modules/**"
    type: library
    confidence: 0.99
  - pattern: "dist/**"
    type: generated
    confidence: 0.95
```

边界类型：`user`（用户代码）, `library`（库）, `generated`（生成代码）, `vendor`（供应商代码）
