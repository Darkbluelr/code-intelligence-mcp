# Code Intelligence MCP Server

MCP Server providing code intelligence capabilities for AI coding assistants.

## Features

- **Embedding Search**: Semantic code search using local (Ollama) or cloud (OpenAI/Anthropic) embeddings
- **LLM Provider Abstraction**: Multi-provider support (Ollama/OpenAI/Anthropic) with automatic fallback to keyword search
- **Graph-RAG Context**: Graph-based retrieval-augmented generation with smart pruning
- **Call-chain Tracing**: Trace function call chains
- **Bug Locator**: Intelligent bug location with caching support and optional impact analysis
- **Complexity Analysis**: Code complexity metrics
- **Hotspot Analysis**: Identify high-churn, high-complexity files
- **Architecture Guard**: Detect circular dependencies and rule violations
- **Federation Index**: Cross-repository API contract tracking with virtual edges
- **AST Delta**: Incremental AST parsing with tree-sitter
- **Impact Analysis**: Transitive impact analysis with confidence decay
- **Entropy Visualization**: Codebase entropy visualization (Fractal/Mermaid/ASCII)
- **COD Visualization**: Architecture visualization (Mermaid + D3.js)
- **Intent Learning**: Query history and preference learning
- **Pattern Learning**: Automated code pattern discovery and rule generation
- **Performance Regression Detection**: Detect performance regressions across benchmark runs
- **Vulnerability Tracking**: npm audit integration and dependency tracing
- **ADR Parsing**: Parse Architecture Decision Records and link to code graph
- **Conversation Context**: Multi-turn conversation history for improved search relevance
- **Structured Context Output**: 5-layer structured context for AI assistants
- **DevBooks Integration**: Auto-detect DevBooks projects for enhanced context
- **Daemon Warmup**: Pre-warm caches for reduced cold-start latency
- **Request Cancellation**: Cancel stale requests to free resources
- **Subgraph LRU Cache**: Cross-process SQLite-based cache for hot subgraphs
- **Context Compression**: Smart context compression (measured 0.07 ratio on `src/server.ts`, skeleton mode)
- **Drift Detection**: Architecture drift detection against C4 model compliance
- **Data Flow Tracing**: Cross-function data flow tracing with taint propagation
- **Hybrid Retrieval**: RRF fusion of graph + embedding search results
- **Semantic Anomaly Detection**: Detect 6 types of semantic anomalies
- **Evaluation Benchmark**: Performance benchmarking with latency/accuracy/token metrics
- **Graceful Degradation**: All optional features degrade gracefully when not configured

## Installation

```bash
git clone https://github.com/user/code-intelligence-mcp.git
cd code-intelligence-mcp
./install.sh
```

## Requirements

- Node.js >= 18.0.0
- Bash shell
- ripgrep (rg)
- jq

## Usage

### As MCP Server

```bash
code-intelligence-mcp
```

### Command Line

```bash
ci-search "search query"
ci index build
ci-search --help
ci-search --version
```

## MCP Tools

| Tool | Description |
|------|-------------|
| `ci_search` | Semantic code search |
| `ci_call_chain` | Trace function call chains |
| `ci_bug_locate` | Intelligent bug location |
| `ci_complexity` | Code complexity analysis |
| `ci_graph_rag` | Graph-based context retrieval (supports --budget for smart pruning) |
| `ci_index` | Manage embedding index with workspace support (status/build/clean/rebuild) |
| `ci_index_status` | Manage Embedding index (status/build/clear) |
| `ci_hotspot` | Hotspot file analysis |
| `ci_boundary` | Boundary detection |
| `ci_arch_check` | Architecture rule checking |
| `ci_graph_store` | Graph store operations (init, query, stats) |
| `ci_federation` | Cross-repo contract search (supports --virtual-edges) |
| `ci_ast_delta` | Incremental AST parsing and graph update |
| `ci_impact` | Transitive impact analysis with confidence decay |
| `ci_cod` | Architecture visualization (Mermaid/D3.js) |
| `ci_intent` | Query history and preference learning |
| `ci_vuln` | Vulnerability scanning and dependency tracing |
| `ci_adr` | Parse and index Architecture Decision Records |
| `ci_warmup` | Pre-warm daemon caches for hot subgraphs |
| `ci_context_compress` | Smart context compression (measured 0.07 ratio on `src/server.ts`, skeleton mode) |
| `ci_drift_detect` | Architecture drift detection against C4 model |
| `ci_semantic_anomaly` | Detect semantic anomalies (6 types) |
| `ci_benchmark` | Run performance benchmarks |

Note: `ci_index_status` is legacy and kept for backward compatibility. Prefer `ci_index`.

### Graph Store Commands

```bash
# Initialize graph database
./scripts/graph-store.sh init

# Query graph statistics
./scripts/graph-store.sh stats

# Find shortest path between symbols
./scripts/graph-store.sh find-path --from "symbolA" --to "symbolB" [--max-depth 10] [--edge-types CALLS,IMPORTS]

# Migrate graph schema (for upgrades)
./scripts/graph-store.sh migrate --check   # Check if migration needed
./scripts/graph-store.sh migrate --apply   # Apply migration with auto-backup
./scripts/graph-store.sh migrate --status  # Show current schema version
```

### Bug Locator with Impact Analysis

```bash
# Basic bug location
./scripts/bug-locator.sh --error "NullPointerException in OrderService"

# With impact analysis (shows affected files)
./scripts/bug-locator.sh --error "NullPointerException" --with-impact [--impact-depth 3]
```

Output with `--with-impact`:
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

### ADR Parsing

```bash
# Scan all ADRs (auto-discover docs/adr, doc/adr, ADR, adr)
./scripts/adr-parser.sh scan

# Scan and link ADR keywords into graph
./scripts/adr-parser.sh scan --link

# Parse a single ADR file
./scripts/adr-parser.sh parse docs/adr/0001-use-sqlite.md
```

### Daemon Management

```bash
# Start daemon
./scripts/daemon.sh start

# Pre-warm caches (see evidence for cold/warm timings)
./scripts/daemon.sh warmup

# Check warmup status
./scripts/daemon.sh status
```

### Conversation Context

```bash
# Start new conversation session
./scripts/intent-learner.sh session new

# Resume existing session
./scripts/intent-learner.sh session resume <session-id>

# List sessions
./scripts/intent-learner.sh session list

# Clear session
./scripts/intent-learner.sh session clear
```

### Cache Management

```bash
# View cache statistics
./scripts/cache-manager.sh stats

# Clear cache
./scripts/cache-manager.sh clear

# Get cached subgraph
./scripts/cache-manager.sh cache-get <cache-key>

# Set cached subgraph
./scripts/cache-manager.sh cache-set <cache-key> <value>
```

### Context Compression

```bash
# Compress a file (skeleton mode)
./scripts/context-compressor.sh src/server.ts

# Compress a directory with a token budget
./scripts/context-compressor.sh --budget 4000 src/

# Enable cache and prioritize a hotspot directory
./scripts/context-compressor.sh --cache --hotspot src/ src/
```

Compression modes:
- `skeleton`: Extract function/class signatures only (current supported mode)

### Drift Detection

```bash
# Compare two snapshots
./scripts/drift-detector.sh --compare baseline.json current.json

# Generate a snapshot
./scripts/drift-detector.sh --snapshot . --output snapshot.json

# Compare C4 model with codebase
./scripts/drift-detector.sh --c4 dev-playbooks/specs/architecture/c4.md --code .
```

Output example:
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

### Data Flow Tracing

```bash
# Trace data flow forward from a symbol
./scripts/call-chain.sh --data-flow userInput --data-flow-direction forward

# Trace backward to find data sources
./scripts/call-chain.sh --data-flow dbQuery --data-flow-direction backward

# Trace both directions
./scripts/call-chain.sh --data-flow data --data-flow-direction both --max-depth 5

# Include transformation details
./scripts/call-chain.sh --data-flow req.body --include-transforms --format json
```

### Semantic Anomaly Detection

```bash
# Scan directory for semantic anomalies
./scripts/semantic-anomaly.sh src/

# Scan specific file
./scripts/semantic-anomaly.sh src/api.ts

# Use custom pattern file
./scripts/semantic-anomaly.sh --pattern my-patterns.json src/

# Set confidence threshold
./scripts/semantic-anomaly.sh --threshold 0.9 src/

# Output formats
./scripts/semantic-anomaly.sh --output json src/
./scripts/semantic-anomaly.sh --output text src/
```

Anomaly types:
- `MISSING_ERROR_HANDLER`: Unhandled async/throw operations
- `INCONSISTENT_API_CALL`: Same API called differently across files
- `NAMING_VIOLATION`: Naming convention violations
- `MISSING_LOG`: Missing logs at critical points
- `UNUSED_IMPORT`: Imported but unused modules
- `DEPRECATED_PATTERN`: Using deprecated code patterns

### Evaluation Benchmark

```bash
# Run dataset benchmark
./scripts/benchmark.sh --dataset self --queries queries.jsonl --output results/benchmark.json

# Compare with baseline
./scripts/benchmark.sh --compare results/baseline.json results/benchmark.json

# Legacy modes
./scripts/benchmark.sh --all
./scripts/benchmark.sh --cache
```

### Pattern Learning

Automatically discover code patterns and generate rules for consistency checking.

```bash
# Discover code patterns in a directory
./scripts/pattern-learner.sh discover src/

# Generate rules from learned patterns
./scripts/pattern-learner.sh generate-rules --output config/learned-rules.yaml

# Apply learned patterns to new code
./scripts/pattern-learner.sh apply --rules config/learned-rules.yaml src/new-feature/

# Show pattern statistics
./scripts/pattern-learner.sh stats
```

### Performance Regression Detection

Detect performance regressions by comparing benchmark results.

```bash
# Run performance regression check against baseline
./scripts/performance-regression.sh --baseline results/baseline.json

# Compare two benchmark reports
./scripts/performance-regression.sh --compare results/before.json results/after.json

# Set custom regression threshold (default: 10%)
./scripts/performance-regression.sh --threshold 15 --baseline results/baseline.json

# Generate regression report
./scripts/performance-regression.sh --report --baseline results/baseline.json --output results/regression-report.md
```

### LLM Provider Management

Manage and test LLM providers for semantic search.

```bash
# Check current provider status
./scripts/llm-provider.sh status

# Test provider connectivity
./scripts/llm-provider.sh test ollama
./scripts/llm-provider.sh test openai
./scripts/llm-provider.sh test anthropic

# Switch provider (updates config)
./scripts/llm-provider.sh switch anthropic

# List available providers
./scripts/llm-provider.sh list
```

## Structured Context Output

The `hooks/context-inject-global.sh` hook supports multiple output formats:

- Default (Claude Code): emits a Claude Code hook envelope with `hookSpecificOutput.additionalContext` (string).
- JSON: `hooks/context-inject-global.sh --format json` emits the Auto Tool Orchestrator JSON schema (`schema_version: "1.0"`), including `tool_plan`, `tool_results`, `fused_context`, `degraded`, and `enforcement`.
  For backward compatibility, it also includes the 5-layer fields (`project_profile`, `current_state`, `task_context`, `recommended_tools`, `constraints`) at the top-level and under `fused_context.for_model.structured`.
- Text: `--format text` prints a human-readable summary (mainly for debugging).

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

## Auto Tool Orchestration

The Auto Tool Orchestration layer automatically selects and executes relevant MCP tools before AI output, reducing cognitive load and improving first-hit accuracy.

### Architecture

The orchestration system consists of three layers:

1. **Entry Layer** (`hooks/context-inject-global.sh`)
   - Parses Hook/CLI input
   - Delegates all planning/execution to the orchestrator kernel
   - Outputs three formats: hook envelope, JSON, or text

2. **Orchestrator Kernel** (`hooks/auto-tool-orchestrator.sh`)
   - The ONLY place allowed to plan/execute tools
   - Performs intent recognition
   - Selects appropriate tools based on user prompt
   - Executes tools in parallel with budget control
   - Fuses results into structured context

3. **Tool Executors** (MCP tools)
   - Individual tools like `ci_search`, `ci_graph_rag`, etc.
   - Execute independently with timeout protection

### Tool Tier Strategy

Tools are organized into tiers based on cost and risk:

- **Tier 0** (Always executed): `ci_index_status` - Environment readiness check
- **Tier 1** (Default enabled): `ci_search`, `ci_graph_rag` - Quick code location
- **Tier 2** (Disabled by default): `ci_impact`, `ci_hotspot` - Deep analysis

Control tier execution with environment variable:

```bash
export CI_AUTO_TOOLS_TIER_MAX=2  # Enable tier 2 tools
```

### Intent Recognition

The system recognizes user intent through multiple signals:

- **Explicit signals**: Keywords like "fix", "bug", "error", "implement"
- **Implicit signals**: File paths, line numbers, function names
- **Historical signals**: Previous queries and actions
- **Contextual signals**: Current git branch, recent commits

### Workflow

```
User Prompt
    ↓
UserPromptSubmit Hook (Claude Code)
    ↓
context-inject-global.sh (Entry)
    ↓
auto-tool-orchestrator.sh (Kernel)
    ↓
Intent Recognition → Tool Selection → Parallel Execution
    ↓
Result Fusion → Context Injection
    ↓
AI Response with Full Context
```

### Output Schema v1.0

The orchestrator outputs a stable JSON schema:

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
    "prompt": "fix the authentication bug",
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
        "reason": "Quick code location",
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

### User-Visible Output

The orchestrator provides **dual-channel output** to optimize context usage:

1. **stderr (User-Visible Summary)**
   - Tool plan: `[Auto Tools] planned N tools`
   - Execution results: Summary of each tool's status
   - Limits: Budget constraints and tier restrictions
   - **Does NOT consume model context**

2. **stdout (Model Context)**
   - Hook JSON with `additionalContext` field
   - Contains only relevant code context for the AI model
   - Optimized to stay within token budget

**Example user-visible output:**
```
[Auto Tools] planned 3 tools

结果摘要：
ci_index_status | ok | ok
ci_search | ok | {...}
ci_graph_rag | ok | {...}

[Limits] tier-2 disabled by default; set CI_AUTO_TOOLS_TIER_MAX=2 to enable
```

This dual-channel approach ensures users can see what tools were executed without wasting model context on status messages.

### Configuration

Configure auto tool orchestration in `.devbooks/config.yaml`:

```yaml
auto_tools:
  enabled: true
  tier_max: 1
  budget:
    wall_ms: 5000
    max_concurrency: 3
    max_injected_chars: 12000
```

Or use environment variables:

```bash
export CI_AUTO_TOOLS_ENABLED=1
export CI_AUTO_TOOLS_TIER_MAX=1
export CI_AUTO_TOOLS_BUDGET_WALL_MS=5000
```

### Degradation Strategy

When tools fail or timeout, the system gracefully degrades:

1. **Tool timeout**: Skip the tool and continue with others
2. **All tools fail**: Return empty context with degradation notice
3. **Budget exceeded**: Stop execution and return partial results

The `degraded` field in output indicates degradation status:

```json
{
  "degraded": {
    "is_degraded": true,
    "reason": "tool_timeout",
    "degraded_to": "partial"
  }
}
```

## Benchmark Framework

The benchmark framework provides standardized performance measurement and regression detection.

### Schema v1.1

The `benchmark_result.json` follows schema v1.1 with the following structure:

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

### Key Metrics

| Metric | Direction | Description |
|--------|-----------|-------------|
| `mrr_at_10` | higher | Mean Reciprocal Rank at top 10 |
| `recall_at_10` | higher | Recall at top 10 results |
| `precision_at_10` | higher | Precision at top 10 results |
| `hit_rate_at_10` | higher | Query hit rate at top 10 |
| `latency_p95_ms` | lower | 95th percentile latency |
| `semantic_search.latency_p95_ms` | lower | Semantic search P95 latency |
| `graph_rag.cold_latency_p95_ms` | lower | Graph-RAG cold start P95 |
| `graph_rag.warm_latency_p95_ms` | lower | Graph-RAG warm start P95 |
| `graph_rag.speedup_pct` | higher | Speedup percentage (cold vs warm) |
| `cache_hit_p95_ms` | lower | Cache hit P95 latency |
| `precommit_staged_p95_ms` | lower | Pre-commit staged files P95 |

### Baseline and Comparison

The framework maintains baseline and current results for regression detection:

**Directory Structure**:
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

**Run Benchmarks**:
```bash
# Generate current results (3 runs)
python benchmarks/run_benchmarks.py --output benchmarks/results/run-1/benchmark_result.json
python benchmarks/run_benchmarks.py --output benchmarks/results/run-2/benchmark_result.json
python benchmarks/run_benchmarks.py --output benchmarks/results/run-3/benchmark_result.json

# Calculate median
python benchmarks/calculate_median.py \
  --input benchmarks/results/run-{1,2,3}/benchmark_result.json \
  --output benchmarks/results/benchmark_result.median.json

# Compare with baseline
scripts/benchmark.sh --compare \
  benchmarks/baselines/benchmark_result.median.json \
  benchmarks/results/benchmark_result.median.json
```

**Comparison Output**:
```
result=no_regression
summary={"status":"pass","metrics":[...]}
exit_code=0
```

### Regression Thresholds

Default regression thresholds:

- **Higher is better** metrics: `threshold = baseline * 0.95` (5% tolerance)
- **Lower is better** metrics: `threshold = baseline * 1.10` (10% tolerance)

Custom thresholds can be set per metric or globally:

```bash
export BENCHMARK_REGRESSION_THRESHOLD=0.05  # 5% global threshold
```

## Demo Suite

The Demo Suite provides standardized demonstrations with A/B comparison capabilities.

### Architecture

The demo suite consists of:

1. **Individual Demos** (`demo/00-*.sh` to `demo/05-*.sh`)
   - Self-contained demonstration scripts
   - Can run independently
   - Output to standard locations

2. **Suite Runner** (`demo/run-suite.sh`)
   - Orchestrates all demos
   - Collects metrics from each demo
   - Generates unified report

3. **Comparison Tool** (`demo/compare.sh`)
   - Compares two demo runs
   - Generates diff report
   - Supports A/B testing

### Output Contract

Each demo run produces standardized outputs:

**metrics.json** (Machine-readable):
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

**report.md** (Human-readable):
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

### Running Demos

**Run Individual Demo**:
```bash
bash demo/00-quick-compare.sh
```

**Run Full Suite**:
```bash
bash demo/run-suite.sh --output demo-results/
```

**A/B Comparison**:
```bash
# Run baseline
git checkout v0.1.0
bash demo/run-suite.sh --output baseline/

# Run current
git checkout main
bash demo/run-suite.sh --output current/

# Compare
bash demo/compare.sh baseline/metrics.json current/metrics.json
```

### Demo Scenarios

| Demo | Scenario | Purpose |
|------|----------|---------|
| `00-quick-compare.sh` | With/without context injection | Show auto-injection value |
| `01-semantic-search.sh` | Semantic code search | Demonstrate search capabilities |
| `02-diagnosis.sh` | Bug diagnosis workflow | Show multi-tool collaboration |
| `03-graph-rag.sh` | Graph-RAG context retrieval | Demonstrate graph traversal |
| `04-call-chain.sh` | Call chain analysis | Show dependency tracing |
| `05-performance.sh` | Performance benchmarks | Measure system performance |

### A/B Testing

The demo suite supports three types of A/B testing:

1. **Version A/B**: Compare different git refs
2. **Configuration A/B**: Compare different settings (e.g., with/without cache)
3. **AI Agent A/B**: Compare different AI coding approaches (semi-automated)

**Example Configuration A/B**:
```bash
# Test with cache
export CI_CACHE_ENABLED=1
bash demo/run-suite.sh --output with-cache/

# Test without cache
export CI_CACHE_ENABLED=0
bash demo/run-suite.sh --output without-cache/

# Compare
bash demo/compare.sh with-cache/metrics.json without-cache/metrics.json
```

## CI/CD Integration

### GitHub Actions

Add `.github/workflows/arch-check.yml` to your repository:

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

Copy `.gitlab-ci.yml.template` to `.gitlab-ci.yml` and customize as needed.

## LLM Provider Configuration

The server supports multiple LLM providers with automatic fallback for semantic search and embedding operations.

### Provider Priority (Automatic Fallback)

1. **Ollama** (default, local) - No API key required
2. **OpenAI** (cloud) - Requires API key
3. **Anthropic** (cloud) - Requires API key
4. **Keyword Search** (fallback) - Always available, no configuration needed

### Configuration Methods

**Method 1: Environment Variables**

```bash
# Choose provider (default: ollama)
export LLM_DEFAULT_PROVIDER="ollama"  # or "openai", "anthropic"

# Ollama configuration (local)
export OLLAMA_ENDPOINT="http://localhost:11434"
export OLLAMA_MODEL="nomic-embed-text"

# OpenAI configuration
export OPENAI_API_KEY="sk-..."
export LLM_ENDPOINT="https://api.openai.com/v1"

# Anthropic configuration
export ANTHROPIC_API_KEY="sk-ant-..."
```

**Method 2: Config File** (`config/llm-providers.yaml`)

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

### Behavior When Not Configured

- **No LLM configured**: Automatically falls back to keyword search (ripgrep-based)
- **Ollama not running**: Attempts OpenAI, then Anthropic, then keyword search
- **API key missing**: Skips that provider and tries next in priority
- **All providers fail**: Returns keyword search results with warning

**Note**: Keyword search is always available as a fallback and requires no configuration. The system degrades gracefully without throwing errors.

## Configuration

Copy `config/ci-config.yaml.template` to your project root as `ci-config.yaml` for workspace/index settings. Embedding provider config can stay in `.devbooks/config.yaml` (legacy compatibility).

### Environment Variables

The following environment variables control the server's behavior. All variables are optional unless marked as "Conditional".

#### Core Configuration

| Variable | Required | Default | Description | Behavior When Not Set |
|----------|----------|---------|-------------|----------------------|
| `OPENAI_API_KEY` | Conditional | - | OpenAI API key | OpenAI provider unavailable, falls back to next provider |
| `ANTHROPIC_API_KEY` | Conditional | - | Anthropic API key | Anthropic provider unavailable, falls back to next provider |
| `OLLAMA_ENDPOINT` | Optional | `http://localhost:11434` | Ollama API endpoint | Uses default endpoint |
| `OLLAMA_MODEL` | Optional | `nomic-embed-text` | Ollama embedding model | Uses default model |
| `GRAPH_DB_PATH` | Optional | `.devbooks/graph.db` | SQLite graph database path | Creates database in default location |

#### LLM Provider Configuration

| Variable | Required | Default | Description | Behavior When Not Set |
|----------|----------|---------|-------------|----------------------|
| `LLM_DEFAULT_PROVIDER` | Optional | `ollama` | LLM provider (`ollama`, `openai`, `anthropic`) | Uses Ollama as default |
| `LLM_DEFAULT_MODEL` | Optional | Provider-specific | LLM model name | Uses provider's default model |
| `LLM_ENDPOINT` | Optional | Provider-specific | LLM API endpoint | Uses provider's default endpoint |
| `LLM_MAX_TOKENS` | Optional | `4096` | Maximum tokens for LLM requests | Uses default limit |

#### Indexing & Caching

| Variable | Required | Default | Description | Behavior When Not Set |
|----------|----------|---------|-------------|----------------------|
| `DISABLE_TREE_SITTER` | Optional | `false` | Force disable Tree-sitter | Uses Tree-sitter if available, falls back to text parsing |
| `FORCE_SCIP_FALLBACK` | Optional | `false` | Force SCIP fallback mode | Uses Tree-sitter when available |
| `SCIP_PROTO_URL` | Optional | (Google Storage) | Custom scip.proto download URL | Uses default URL |
| `AST_CACHE_DIR` | Optional | `.devbooks/ast-cache` | AST cache directory | Creates cache in default location |
| `AST_CACHE_TTL_DAYS` | Optional | `7` | AST cache expiration (days) | Uses default TTL |
| `AST_CACHE_MAX_SIZE_MB` | Optional | `100` | AST cache max size (MB) | Uses default size limit |

#### Federation & Cross-Repo

| Variable | Required | Default | Description | Behavior When Not Set |
|----------|----------|---------|-------------|----------------------|
| `FEDERATION_CONFIG` | Optional | `config/federation.yaml` | Federation config file path | No cross-repo tracking, tools return empty results |
| `FEDERATION_INDEX` | Optional | `.devbooks/federation-index.json` | Federation index file path | Creates index in default location |

#### Feature Toggles

| Variable | Required | Default | Description | Behavior When Not Set |
|----------|----------|---------|-------------|----------------------|
| `FEATURES_CONFIG` | Optional | `config/features.yaml` | Feature toggles config file | All features enabled by default |
| `DEVBOOKS_ENABLE_ALL_FEATURES` | Optional | - | Force enable all features (overrides config) | Respects feature config file |
| `CI_AST_DELTA_ENABLED` | Optional | - | Override `ast_delta.enabled` | Uses config file value |
| `CI_FILE_THRESHOLD` | Optional | - | Override `ast_delta.file_threshold` | Uses config file value |
| `DEBOUNCE_SECONDS` | Optional | - | Override `indexer.debounce_seconds` | Uses config file value |

#### Daemon & Performance

| Variable | Required | Default | Description | Behavior When Not Set |
|----------|----------|---------|-------------|----------------------|
| `DAEMON_WARMUP_ENABLED` | Optional | `true` | Enable daemon warmup | Warmup disabled, cold start latency higher |
| `DAEMON_WARMUP_TIMEOUT` | Optional | `30` | Warmup timeout (seconds) | Uses default timeout |
| `DAEMON_CANCEL_ENABLED` | Optional | `true` | Enable request cancellation | Stale requests not cancelled |
| `GRAPH_WAL_MODE` | Optional | `true` | Enable SQLite WAL mode | Uses default journal mode |

#### Bug Locator

| Variable | Required | Default | Description | Behavior When Not Set |
|----------|----------|---------|-------------|----------------------|
| `BUG_LOCATOR_WITH_IMPACT` | Optional | `false` | Enable impact analysis in bug locator | Returns bug locations without impact analysis |
| `BUG_LOCATOR_IMPACT_DEPTH` | Optional | `3` | Impact analysis depth | Uses default depth |

#### Intent Learning

| Variable | Required | Default | Description | Behavior When Not Set |
|----------|----------|---------|-------------|----------------------|
| `INTENT_HISTORY_PATH` | Optional | `.devbooks/intent-history.json` | Intent history file path | Creates history in default location |
| `INTENT_MAX_ENTRIES` | Optional | `10000` | Max intent history entries | Uses default limit |

#### Debugging & Logging

| Variable | Required | Default | Description | Behavior When Not Set |
|----------|----------|---------|-------------|----------------------|
| `DEBUG` | Optional | `false` | Enable debug output | Debug output disabled |
| `LOG_LEVEL` | Optional | `INFO` | Log level (`DEBUG`, `INFO`, `WARN`, `ERROR`) | Uses INFO level |
| `NO_COLOR` | Optional | - | Disable colored output | Colors enabled in TTY |

### Architecture Rules

Define architecture rules in `config/arch-rules.yaml`:

```yaml
rules:
  - id: no-ui-to-db
    from: "src/ui/**"
    to: "src/db/**"
    severity: error
    message: "UI layer cannot import DB layer directly"
```

### Federation Config

Configure cross-repository tracking in `config/federation.yaml`:

```yaml
repositories:
  - path: ./api-contracts
    type: local
    patterns:
      - "*.proto"
      - "openapi.yaml"
```

### Feature Toggles

Control feature modules in `config/features.yaml`:

```yaml
features:
  graph_store:
    enabled: true
    wal_mode: true
  llm_rerank:
    enabled: false
    provider: anthropic

  # AST Delta incremental indexing (optimize-indexing-pipeline: AC-001)
  ast_delta:
    enabled: true  # Set to false to disable incremental path
    file_threshold: 10  # Files > threshold trigger full rebuild

  # Indexer scheduler (optimize-indexing-pipeline: AC-003, AC-007)
  indexer:
    debounce_seconds: 2  # Aggregate changes within this window
    offline_proto: true  # Use vendored/scip.proto
    allow_proto_download: false  # Set to true to allow downloading proto

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

  # Context compression (20260118-2112: AC-001)
  context_compressor:
    enabled: true
    default_budget: 8000
    min_compression_ratio: 0.3
    max_compression_ratio: 0.5
    strategy: smart  # skeleton, smart, truncate

  # Architecture drift detection (20260118-2112: AC-002)
  drift_detector:
    enabled: true
    c4_path: dev-playbooks/specs/architecture/c4.md
    auto_fix: false

  # Semantic anomaly detection (20260118-2112: AC-003)
  semantic_anomaly:
    enabled: true
    severity_threshold: warning  # error, warning, info

  # Codebase Entropy Visualization
  entropy_visualization:
    enabled: true
    mermaid: true           # Generate Mermaid diagrams
    ascii_dashboard: true   # Show ASCII dashboard in CLI

  # Impact Analysis configuration
  impact_analyzer:
    max_depth: 5            # Maximum propagation depth
    decay_factor: 0.5       # Confidence decay per hop
    threshold: 0.2          # Minimum confidence to report

  # Evaluation benchmark (20260118-2112: AC-012)
  benchmark:
    enabled: false  # Enable only when running benchmarks
    output_dir: results/
```

Environment variable overrides:
- `CI_AST_DELTA_ENABLED`: Override `ast_delta.enabled`
- `CI_FILE_THRESHOLD`: Override `ast_delta.file_threshold`
- `DEBOUNCE_SECONDS`: Override `indexer.debounce_seconds`

### Vendored Proto (Offline Mode)

The SCIP proto file is vendored for offline operation:

```bash
# Check proto version and compatibility
./scripts/vendor-proto.sh --check

# Upgrade proto from GitHub
./scripts/vendor-proto.sh --upgrade

# View current version
./scripts/vendor-proto.sh --version
```

Proto discovery priority:
1. `$SCIP_PROTO_PATH` environment variable
2. `vendored/scip.proto` (default)
3. Cached proto in `/tmp/scip.proto`
4. Download (only if `allow_proto_download: true`)

### Data Files

The following data files are automatically created in `.devbooks/`:

| File | Purpose | Safe to Delete |
|------|---------|----------------|
| `graph.db` | Graph database (SQLite) | Yes, will rebuild on next index |
| `subgraph-cache.db` | LRU cache for hot subgraphs | Yes, will rebuild automatically |
| `conversation-context.json` | Conversation history | Yes, will start fresh |
| `adr-index.json` | ADR index cache | Yes, will rebuild on next parse |
| `intent-history.json` | Query history for learning | Yes, will start fresh |

### Optional Configuration Behavior

This section clarifies what happens when optional configurations are not provided. The system is designed for graceful degradation.

#### Embedding & Search

**When no LLM provider is configured:**
- System automatically falls back to keyword search (ripgrep-based)
- Semantic search commands still work but use keyword matching
- No error is thrown; degraded functionality is transparent
- Performance: keyword search is faster but less accurate for conceptual queries

**When Tree-sitter is disabled or unavailable:**
- System falls back to text-based parsing
- Indexing still works but with reduced accuracy for complex syntax
- Performance may be slightly slower for large files

#### Federation & Cross-Repo

**When federation config is not provided:**
- `ci_federation` tool remains available and functional
- All federation commands return empty results with status `"empty"`
- No error is thrown; graceful degradation
- Example response:
  ```json
  {
    "status": "empty",
    "edges_created": 0,
    "message": "No federation index found at .devbooks/federation-index.json"
  }
  ```

**When federation index is missing:**
- `generate-virtual-edges` creates the index automatically on first run
- Other federation commands return empty results until index is built
- Use `ci_federation --action update` to build the index

#### Graph Database

**When graph database doesn't exist:**
- Database is automatically created on first use
- Default location: `.devbooks/graph.db`
- No manual initialization required
- Initial indexing may take a few seconds for large codebases

#### Cache & Performance

**When cache is not configured:**
- Cache directories are created automatically in `.devbooks/`
- Default cache locations are used for all cache types
- Cache is optional; system works without it (slower on repeated queries)
- Cache improves performance for repeated operations (see evidence)

**When daemon warmup is disabled:**
- Cold start latency is higher (see evidence)
- Subsequent queries are not affected
- No functional impact, only performance
- Recommended to enable for production use

#### ADR Parsing

**When ADR directory is not specified:**
- System auto-discovers ADRs in common locations:
  - `docs/adr/`
  - `doc/adr/`
  - `ADR/`
  - `adr/`
- If no ADRs found, commands return empty results
- No error is thrown

#### SCIP Proto

**When SCIP proto is not configured:**
- System searches in priority order:
  1. `$SCIP_PROTO_PATH` environment variable
  2. `vendored/scip.proto` (bundled, always available)
  3. Cached proto in `/tmp/scip.proto`
  4. Download from GitHub (only if `allow_proto_download: true`)
- Offline operation is fully supported via vendored proto
- No internet connection required for normal operation

### Boundary Detection

Configure code boundary rules in `config/boundaries.yaml`:

```yaml
rules:
  - pattern: "node_modules/**"
    type: library
    confidence: 0.99
  - pattern: "dist/**"
    type: generated
    confidence: 0.95
```

Boundary types: `user`, `library`, `generated`, `vendor`
