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

`hooks/context-inject-global.sh` 钩子支持多种输出形态：

- 默认（Claude Code）：输出 Claude Code hook envelope，内容在 `hookSpecificOutput.additionalContext`（字符串）。
- JSON：`hooks/context-inject-global.sh --format json` 输出自动工具编排器 JSON schema（`schema_version: "1.0"`），包含 `tool_plan`、`tool_results`、`fused_context`、`degraded`、`enforcement`。
  为兼容旧消费者，同时在顶层与 `fused_context.for_model.structured` 中保留 5 层字段（`project_profile/current_state/task_context/recommended_tools/constraints`）。
- 文本：`--format text` 输出用户可读摘要（主要用于调试）。

```json
{
  "schema_version": "1.0",
  "run_id": "20260124-123456-acde12",
  "tool_plan": { "tier_max": 1, "tools": [] },
  "tool_results": [],
  "fused_context": {
    "for_model": {
      "additional_context": "",
      "structured": {
        "project_profile": {},
        "current_state": {},
        "task_context": {},
        "recommended_tools": [],
        "constraints": {}
      }
    },
    "for_user": {
      "tool_plan_text": "",
      "results_text": "",
      "limits_text": ""
    }
  },
  "degraded": { "is_degraded": false, "reason": "", "degraded_to": "" },
  "enforcement": { "single_tool_entry": true, "source": "orchestrator" }
}
```

## 自动工具编排

自动工具编排层在 AI 输出之前自动选择并执行相关的 MCP 工具，降低认知负担并提升一次命中率。

### 架构

编排系统由三层组成：

1. **入口层** (`hooks/context-inject-global.sh`)
   - 解析 Hook/CLI 输入
   - 将所有计划/执行委托给编排内核
   - 输出三种格式：hook envelope、JSON 或文本

2. **编排内核** (`hooks/auto-tool-orchestrator.sh`)
   - 唯一允许计划/执行工具的地方
   - 执行意图识别
   - 根据用户提示选择合适的工具
   - 并行执行工具并控制预算
   - 将结果融合为结构化上下文

3. **工具执行器** (MCP 工具)
   - 独立的工具如 `ci_search`、`ci_graph_rag` 等
   - 带超时保护的独立执行

### 工具分层策略

工具根据成本和风险分为不同层级：

- **Tier 0**（总是执行）：`ci_index_status` - 环境就绪性检查
- **Tier 1**（默认启用）：`ci_search`、`ci_graph_rag` - 快速代码定位
- **Tier 2**（默认禁用）：`ci_impact`、`ci_hotspot` - 深度分析

使用环境变量控制层级执行：

```bash
export CI_AUTO_TOOLS_TIER_MAX=2  # 启用 tier 2 工具
```

### 意图识别

系统通过多种信号识别用户意图：

- **显式信号**：关键词如 "fix"、"bug"、"error"、"implement"
- **隐式信号**：文件路径、行号、函数名
- **历史信号**：之前的查询和操作
- **上下文信号**：当前 git 分支、最近提交

### 工作流程

```
用户提示
    ↓
UserPromptSubmit Hook (Claude Code)
    ↓
context-inject-global.sh (入口)
    ↓
auto-tool-orchestrator.sh (内核)
    ↓
意图识别 → 工具选择 → 并行执行
    ↓
结果融合 → 上下文注入
    ↓
AI 基于完整上下文响应
```

### 输出 Schema v1.0

编排器输出稳定的 JSON schema：

```json
{
  "schema_version": "1.0",
  "run_id": "20260124-123456-acde12",
  "created_at": "2026-01-24T12:34:56Z",
  "client": {
    "name": "claude-code",
    "event": "UserPromptSubmit"
  },
  "inputs": {
    "prompt": "修复认证 bug",
    "repo_root": "/path/to/repo",
    "signals": []
  },
  "tool_plan": {
    "tier_max": 1,
    "budget": {
      "wall_ms": 5000,
      "max_concurrency": 3,
      "max_injected_chars": 12000
    },
    "tools": [
      {
        "tool": "ci_search",
        "tier": 1,
        "reason": "快速代码定位",
        "args": {"limit": 10, "mode": "semantic"},
        "timeout_ms": 2000
      }
    ]
  },
  "tool_results": [
    {
      "tool": "ci_search",
      "status": "ok",
      "duration_ms": 1236,
      "data": {...}
    }
  ],
  "fused_context": {
    "for_model": {
      "additional_context": "...",
      "structured": {...}
    },
    "for_user": {
      "tool_plan_text": "[Auto Tools] planned 3 tools",
      "results_text": "...",
      "limits_text": ""
    }
  }
}
```

### 配置

在 `.devbooks/config.yaml` 中配置自动工具编排：

```yaml
auto_tools:
  enabled: true
  tier_max: 1
  budget:
    wall_ms: 5000
    max_concurrency: 3
    max_injected_chars: 12000
```

或使用环境变量：

```bash
export CI_AUTO_TOOLS_ENABLED=1
export CI_AUTO_TOOLS_TIER_MAX=1
export CI_AUTO_TOOLS_BUDGET_WALL_MS=5000
```

### 降级策略

当工具失败或超时时，系统会优雅降级：

1. **工具超时**：跳过该工具并继续执行其他工具
2. **所有工具失败**：返回空上下文并附带降级通知
3. **预算超支**：停止执行并返回部分结果

输出中的 `degraded` 字段指示降级状态：

```json
{
  "degraded": {
    "is_degraded": true,
    "reason": "tool_timeout",
    "degraded_to": "partial"
  }
}
```

## 基准测试框架

基准测试框架提供标准化的性能测量和回归检测。

### Schema v1.1

`benchmark_result.json` 遵循 schema v1.1，具有以下结构：

```json
{
  "schema_version": "1.1",
  "generated_at": "2026-01-24T06:27:38Z",
  "project_root": "/path/to/project",
  "git_commit": "3547af1",
  "queries_version": "sha256:2a944e88",
  "run": {
    "mode": "full",
    "cold_definition": "cache cleared before each cold sample",
    "warm_definition": "same process, cache retained",
    "cache_clear": ["rm -rf ${TMPDIR:-/tmp}/.ci-cache"],
    "random_seed": 42
  },
  "environment": {
    "os": {"name": "Darwin", "version": "25.2.0"},
    "cpu": {"model": "Apple M4", "cores": 10, "arch": "arm64"},
    "memory": {"total_mb": 16384},
    "runtime": {"node": "v22.15.0", "python": "Python 3.12.9"}
  },
  "metrics": {
    "semantic_search": {
      "iterations": 3,
      "latency_p50_ms": 209.0,
      "latency_p95_ms": 222.0,
      "latency_p99_ms": 222.0
    },
    "graph_rag": {
      "iterations": 3,
      "cold_latency_p95_ms": 862.64,
      "warm_latency_p95_ms": 69.37,
      "speedup_pct": 91.96
    },
    "retrieval_quality": {
      "iterations": 12,
      "dataset": "self",
      "query_count": 12,
      "mrr_at_10": 0.4264,
      "recall_at_10": 1.0,
      "precision_at_10": 0.3377,
      "hit_rate_at_10": 1.0,
      "latency_p95_ms": 6.10
    },
    "cache": {
      "iterations": 20,
      "cache_hit_p95_ms": 75.0,
      "full_query_p95_ms": 89.0,
      "precommit_staged_p95_ms": 35.0,
      "precommit_deps_p95_ms": 27.0
    }
  }
}
```

### 关键指标

| 指标 | 方向 | 描述 |
|------|------|------|
| `mrr_at_10` | 越高越好 | 前 10 个结果的平均倒数排名 |
| `recall_at_10` | 越高越好 | 前 10 个结果的召回率 |
| `precision_at_10` | 越高越好 | 前 10 个结果的精确率 |
| `hit_rate_at_10` | 越高越好 | 前 10 个结果的查询命中率 |
| `latency_p95_ms` | 越低越好 | 第 95 百分位延迟 |
| `semantic_search.latency_p95_ms` | 越低越好 | 语义搜索 P95 延迟 |
| `graph_rag.cold_latency_p95_ms` | 越低越好 | Graph-RAG 冷启动 P95 |
| `graph_rag.warm_latency_p95_ms` | 越低越好 | Graph-RAG 热启动 P95 |
| `graph_rag.speedup_pct` | 越高越好 | 提速百分比（冷启动 vs 热启动）|
| `cache_hit_p95_ms` | 越低越好 | 缓存命中 P95 延迟 |
| `precommit_staged_p95_ms` | 越低越好 | 预提交暂存文件 P95 |

### 基线和对比

框架维护基线和当前结果以进行回归检测：

**目录结构**：
```
benchmarks/
├── baselines/
│   ├── run-1/benchmark_result.json
│   ├── run-2/benchmark_result.json
│   ├── run-3/benchmark_result.json
│   └── benchmark_result.median.json
└── results/
    ├── run-1/benchmark_result.json
    ├── run-2/benchmark_result.json
    ├── run-3/benchmark_result.json
    └── benchmark_result.median.json
```

**运行基准测试**：
```bash
# 生成当前结果（3 次运行）
python benchmarks/run_benchmarks.py --output benchmarks/results/run-1/benchmark_result.json
python benchmarks/run_benchmarks.py --output benchmarks/results/run-2/benchmark_result.json
python benchmarks/run_benchmarks.py --output benchmarks/results/run-3/benchmark_result.json

# 计算中位数
python benchmarks/calculate_median.py \
  --input benchmarks/results/run-{1,2,3}/benchmark_result.json \
  --output benchmarks/results/benchmark_result.median.json

# 与基线对比
scripts/benchmark.sh --compare \
  benchmarks/baselines/benchmark_result.median.json \
  benchmarks/results/benchmark_result.median.json
```

**对比输出**：
```
result=no_regression
summary={"status":"pass","metrics":[...]}
exit_code=0
```

### 回归阈值

默认回归阈值：

- **越高越好的指标**：`threshold = baseline * 0.95`（5% 容差）
- **越低越好的指标**：`threshold = baseline * 1.10`（10% 容差）

可以为每个指标或全局设置自定义阈值：

```bash
export BENCHMARK_REGRESSION_THRESHOLD=0.05  # 5% 全局阈值
```

## 演示套件

演示套件提供标准化的演示，具有 A/B 对比能力。

### 架构

演示套件包括：

1. **独立演示**（`demo/00-*.sh` 到 `demo/05-*.sh`）
   - 自包含的演示脚本
   - 可独立运行
   - 输出到标准位置

2. **套件运行器**（`demo/run-suite.sh`）
   - 编排所有演示
   - 从每个演示收集指标
   - 生成统一报告

3. **对比工具**（`demo/compare.sh`）
   - 对比两次演示运行
   - 生成差异报告
   - 支持 A/B 测试

### 输出契约

每次演示运行产生标准化输出：

**metrics.json**（机器可读）：
```json
{
  "schema_version": "1.0",
  "run_id": "20260124-demo-001",
  "git_ref": "main",
  "environment": {...},
  "demos": {
    "00-quick-compare": {
      "status": "success",
      "duration_ms": 1500,
      "metrics": {...}
    }
  }
}
```

**report.md**（人类可读）：
```markdown
# Demo Suite Report

- Run ID: 20260124-demo-001
- Git Ref: main
- Environment: macOS 14.2, Apple M4

## Results

### 00-quick-compare
- Status: ✅ Success
- Duration: 1.5s
- Key Findings: Auto context injection reduced query time by 60%
```

### 运行演示

**运行单个演示**：
```bash
bash demo/00-quick-compare.sh
```

**运行完整套件**：
```bash
bash demo/run-suite.sh --output demo-results/
```

**A/B 对比**：
```bash
# 运行基线
git checkout v0.1.0
bash demo/run-suite.sh --output baseline/

# 运行当前版本
git checkout main
bash demo/run-suite.sh --output current/

# 对比
bash demo/compare.sh baseline/metrics.json current/metrics.json
```

### 演示场景

| 演示 | 场景 | 目的 |
|------|------|------|
| `00-quick-compare.sh` | 有/无上下文注入 | 展示自动注入价值 |
| `01-semantic-search.sh` | 语义代码搜索 | 演示搜索能力 |
| `02-diagnosis.sh` | Bug 诊断工作流 | 展示多工具协作 |
| `03-graph-rag.sh` | Graph-RAG 上下文检索 | 演示图遍历 |
| `04-call-chain.sh` | 调用链分析 | 展示依赖追踪 |
| `05-performance.sh` | 性能基准测试 | 测量系统性能 |

### A/B 测试

演示套件支持三种类型的 A/B 测试：

1. **版本 A/B**：对比不同的 git refs
2. **配置 A/B**：对比不同的设置（例如，有/无缓存）
3. **AI Agent A/B**：对比不同的 AI 编程方法（半自动化）

**配置 A/B 示例**：
```bash
# 测试有缓存
export CI_CACHE_ENABLED=1
bash demo/run-suite.sh --output with-cache/

# 测试无缓存
export CI_CACHE_ENABLED=0
bash demo/run-suite.sh --output without-cache/

# 对比
bash demo/compare.sh with-cache/metrics.json without-cache/metrics.json
```

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
