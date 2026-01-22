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
- **Context Compression**: Smart context compression (30-50% ratio) preserving key information
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
| `ci_context_compress` | Smart context compression (30-50% ratio) |
| `ci_drift_detect` | Architecture drift detection against C4 model |
| `ci_semantic_anomaly` | Detect semantic anomalies (6 types) |
| `ci_benchmark` | Run performance benchmarks |

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

# Pre-warm caches (reduces cold-start latency)
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

The `context-inject-global.sh` hook outputs a 5-layer structured JSON:

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

Use `--format text` for plain text output.

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

Copy `config/config.yaml.template` to your project's `.devbooks/config.yaml`.

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
- Cache improves performance by 50-80% for repeated operations

**When daemon warmup is disabled:**
- Cold start latency is higher (first query 2-5x slower)
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

## License

MIT
