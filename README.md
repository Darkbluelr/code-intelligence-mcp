# Code Intelligence MCP Server

MCP Server providing code intelligence capabilities for AI coding assistants.

## Features

- **Embedding Search**: Semantic code search using local (Ollama) or cloud (OpenAI) embeddings
- **Graph-RAG Context**: Graph-based retrieval-augmented generation with smart pruning
- **Call-chain Tracing**: Trace function call chains
- **Bug Locator**: Intelligent bug location with caching support
- **Complexity Analysis**: Code complexity metrics
- **Hotspot Analysis**: Identify high-churn, high-complexity files
- **Architecture Guard**: Detect circular dependencies and rule violations
- **Federation Index**: Cross-repository API contract tracking with virtual edges
- **AST Delta**: Incremental AST parsing with tree-sitter
- **Impact Analysis**: Transitive impact analysis with confidence decay
- **COD Visualization**: Architecture visualization (Mermaid + D3.js)
- **Intent Learning**: Query history and preference learning
- **Vulnerability Tracking**: npm audit integration and dependency tracing
- **ADR Parsing**: Parse Architecture Decision Records and link to code graph
- **Conversation Context**: Multi-turn conversation history for improved search relevance
- **Structured Context Output**: 5-layer structured context for AI assistants
- **DevBooks Integration**: Auto-detect DevBooks projects for enhanced context
- **Daemon Warmup**: Pre-warm caches for reduced cold-start latency
- **Request Cancellation**: Cancel stale requests to free resources
- **Subgraph LRU Cache**: Cross-process SQLite-based cache for hot subgraphs

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
| `ci_index_status` | Check indexing status |
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
# Parse all ADRs in docs/adr/
./scripts/adr-parser.sh discover

# Parse and index ADRs to graph
./scripts/adr-parser.sh index

# Link ADR keywords to code symbols
./scripts/adr-parser.sh link
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

## Structured Context Output

The `augment-context-global.sh` hook outputs a 5-layer structured JSON:

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

## Configuration

Copy `config/config.yaml.template` to your project's `.devbooks/config.yaml`.

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
```

### Data Files

The following data files are automatically created in `.devbooks/`:

| File | Purpose | Safe to Delete |
|------|---------|----------------|
| `graph.db` | Graph database (SQLite) | Yes, will rebuild on next index |
| `subgraph-cache.db` | LRU cache for hot subgraphs | Yes, will rebuild automatically |
| `conversation-context.json` | Conversation history | Yes, will start fresh |
| `adr-index.json` | ADR index cache | Yes, will rebuild on next parse |
| `intent-history.json` | Query history for learning | Yes, will start fresh |

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
