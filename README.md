# Code Intelligence MCP Server

> A Model Context Protocol (MCP) server that provides intelligent code analysis and context retrieval for AI coding assistants.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Node.js Version](https://img.shields.io/badge/node-%3E%3D18.0.0-brightgreen)](https://nodejs.org/)

## What is this?

Code Intelligence MCP Server enhances AI coding assistants with deep codebase understanding through:

- **Semantic Search**: Find code by meaning, not just keywords
- **Graph-RAG**: Context-aware code retrieval using knowledge graphs
- **Call Chain Analysis**: Trace function dependencies and impacts
- **Smart Context**: Automatically inject relevant code snippets into AI conversations

Perfect for use with Claude Code, Cline, or any MCP-compatible AI assistant.

## Quick Start

### Installation

**Via npm** (recommended):

```bash
npm install -g @ozbombor/code-intelligence-mcp
```

**Via git**:

```bash
git clone https://github.com/Darkbluelr/code-intelligence-mcp.git
cd code-intelligence-mcp
./install.sh
```

### Requirements

- Node.js >= 18.0.0
- Bash shell
- [ripgrep](https://github.com/BurntSushi/ripgrep) (optional, for faster search)
- [jq](https://stedolan.github.io/jq/) (optional, for JSON processing)

### Usage

**As MCP Server** (recommended):

Add to your MCP client configuration:

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

**Command Line**:

```bash
ci-search "find authentication code"
ci index build
ci index status --workspace demo-zod
ci-search --help
```

## Core Features

### Semantic Code Search
```bash
# Natural language queries
ci-search "how does user authentication work"
```

### Graph-RAG Context Retrieval
```bash
# Get relevant context with smart pruning
ci_graph_rag --query "fix login bug" --budget 8000
```

### Call Chain Tracing
```bash
# Trace function dependencies
ci_call_chain --symbol "handleLogin" --depth 3
```

### Impact Analysis
```bash
# Analyze change impact
ci_impact --file "src/auth.ts"
```

### Bug Location
```bash
# Intelligent bug locator
ci_bug_locate --error "TypeError: Cannot read property 'user'"
```

## Available MCP Tools

| Tool | Description |
|------|-------------|
| `ci_search` | Semantic code search with embeddings |
| `ci_graph_rag` | Graph-based context retrieval with smart pruning |
| `ci_call_chain` | Function call chain tracing |
| `ci_bug_locate` | Intelligent bug location with impact analysis |
| `ci_complexity` | Code complexity analysis |
| `ci_hotspot` | High-churn file detection |
| `ci_impact` | Transitive impact analysis with confidence decay |
| `ci_arch_check` | Architecture rule validation |
| `ci_vuln` | Vulnerability scanning and dependency tracing |
| `ci_index` | Manage embedding index with workspace support (status/build/clean/rebuild) |
| `ci_index_status` | Manage embedding index (status/build/clear) |
| `ci_boundary` | Code boundary detection (user/library/generated) |
| `ci_graph_store` | Graph store operations (init/query/stats) |
| `ci_federation` | Cross-repo API contract tracking |
| `ci_ast_delta` | Incremental AST parsing |
| `ci_cod` | Architecture visualization (Mermaid/D3.js) |
| `ci_intent` | Query history and preference learning |

**20+ tools available** - Each tool supports `--help` for detailed usage.

Note: `ci_index_status` is kept for backward compatibility; prefer `ci_index`.

## Configuration

### Workspace & Index Configuration (ci-config.yaml)

`ci-config.yaml` is the single entry point for workspace and index settings. It supports multi-project workspaces and index isolation:

```yaml
version: 1.0

global:
  index_dir: .ci-index
  respect_gitignore: true
  global_exclude:
    - "**/node_modules/**"
    - "**/.git/**"
    - "**/dist/**"
    - "**/build/**"

default_workspace:
  name: main
  root: .
  include:
    - "src/**"
    - "packages/**"
  exclude:
    - "**/*.d.ts"

workspaces:
  - name: demo-zod
    root: demo/zod
    respect_gitignore: false
    include:
      - "packages/zod/src/**"
      - "packages/zod/tests/**"

imports:
  boundaries: config/boundaries.yaml
  features: config/features.yaml
  llm_providers: config/llm-providers.yaml
```

Workspace usage examples:
```bash
# MCP tool usage
ci_index action=build workspace=demo-zod
ci_search query="schema parse" workspace=demo-zod

# CLI usage
ci index build --workspace demo-zod
ci-search "schema parse" --workspace demo-zod
```

### Embedding Providers

The server supports multiple embedding providers with automatic fallback:

**Three-tier Fallback Strategy:**
1. **Ollama** (Local, Free) → Preferred, no network latency, privacy-safe
2. **OpenAI API** (Cloud, Paid) → Automatic fallback when Ollama unavailable
3. **Keyword Search** → Final fallback when no embedding service available

#### Option 1: Ollama (Recommended for Local Use)

**Installation:**
```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull the embedding model
ollama pull nomic-embed-text
```

**Configuration:**
```yaml
# .devbooks/config.yaml (embedding provider config)
embedding:
  provider: ollama  # or 'auto' for automatic detection
  ollama:
    model: nomic-embed-text
    endpoint: http://localhost:11434
    timeout: 30
```

**Usage:**
```bash
# Build the embedding index
ci index build

# Search with Ollama
ci-search "authentication code"
```

#### Option 2: OpenAI API (Cloud)

**Setup:**
```bash
# Set your API key
export OPENAI_API_KEY="sk-..."
```

**Configuration:**
```yaml
# .devbooks/config.yaml (embedding provider config)
embedding:
  provider: openai
  openai:
    model: text-embedding-3-small
    api_key: ${OPENAI_API_KEY}  # or set directly
    base_url: https://api.openai.com/v1
    timeout: 30
```

**Usage:**
```bash
# Build index with OpenAI
ci index build

# Or force OpenAI for a single search
ci-search "user authentication" --provider openai
```

#### Option 3: Keyword Search (No Setup Required)

Keyword search works out of the box without any configuration:

```bash
# Force keyword search
ci-search "error handling" --provider keyword
```

#### Advanced Configuration

**Automatic Provider Detection:**
```yaml
# .devbooks/config.yaml (embedding provider config)
embedding:
  provider: auto  # Tries Ollama → OpenAI → Keyword
  fallback_to_keyword: true
  auto_build: true
```

**Command-line Override:**
```bash
# Override provider for a single search
ci-search "test" --provider ollama --ollama-model mxbai-embed-large

# JSON output with custom settings
ci-search "payment" --format json --top-k 10 --threshold 0.7
```

**Environment Variables:**
- `OPENAI_API_KEY` - OpenAI API key
- `EMBEDDING_API_KEY` - Generic embedding API key
- `PROJECT_ROOT` - Project root directory

#### Important: Workspace Parameter

**Always specify the workspace parameter when using MCP tools in multi-workspace projects:**

```bash
# MCP tool usage - CORRECT
ci_search query="authentication code" workspace=demo-typescript

# MCP tool usage - INCORRECT (uses default 'main' workspace)
ci_search query="authentication code"
```

**Why this matters:**
- Each workspace has its own embedding index
- Using the wrong workspace will result in empty or incorrect search results
- The default `main` workspace may not have the files you're looking for

**Troubleshooting:**
If `ci_search` falls back to keyword search or returns no results:
1. Check if you specified the correct workspace parameter
2. Verify the workspace index exists: `ci_index action=status workspace=<name>`
3. Build the index if needed: `ci_index action=build workspace=<name>`
4. Ensure ollama is running: `curl http://localhost:11434/api/tags`

### Optional Features

All features degrade gracefully:
- **No embeddings?** Falls back to keyword search
- **No SCIP index?** Uses regex parsing
- **No external tools?** Core features still work
- **No git history?** Hotspot analysis disabled

This means you can start using the MCP server immediately without any configuration.

## Documentation

For advanced usage, see the local documentation:
- Complete tool reference and examples
- Architecture and system design
- Performance tuning guide
- Troubleshooting tips

Run `./install.sh` to access full documentation locally.

## Examples

### Automatic Context Injection

Enable automatic context injection for Claude Code:

```bash
ci-setup-hook
```

This installs a hook that automatically injects relevant code context when you interact with Claude, making your AI assistant more aware of your codebase without manual queries.

### Custom Queries

```bash
# Search with specific mode
ci-search "user service" --mode semantic --limit 5

# Trace call chains
ci_call_chain --symbol "processPayment" --direction both

# Check architecture
ci_arch_check --path src/
```

### Demo Suite

Run comprehensive demos with A/B comparison:

```bash
# Run quick comparison demo
bash demo/00-quick-compare.sh

# Run all demos
bash demo/run-suite.sh

# Compare versions (if available)
bash demo/compare.sh baseline.json current.json
```

The demo suite showcases:
- Automatic context injection vs manual queries
- Semantic search and Graph-RAG capabilities
- Performance benchmarks and metrics
- A/B comparison between different configurations

## Performance

Metrics are generated by `python3 benchmarks/run_benchmarks.py` into `benchmark_result.json`.
Use `python3 benchmarks/update_readme.py` to refresh this section.

<!-- BENCHMARK:START -->
Updated at: 2026-01-24T06:27:38+00:00

| Metric | Value | Notes |
| --- | --- | --- |
| Semantic search P95 latency | 222 ms | iterations=3 |
| Graph-RAG cold P95 latency | 862.64 ms | iterations=3 |
| Graph-RAG warm P95 latency | 69.37 ms | iterations=3 |
| Graph-RAG speedup | 91.96 % | cold vs warm |
| Retrieval MRR@10 | 0.4264 | dataset=self, queries=12 |
| Retrieval Recall@10 | 1.0 | dataset=self, queries=12 |
| Retrieval Precision@10 | 0.3377 | dataset=self, queries=12 |
| Retrieval P95 latency | 6.10 ms | dataset=self, queries=12 |
| Cache hit P95 latency | 75 ms | iterations=20 |
| Full query P95 latency | 89 ms | iterations=20 |
| Precommit staged P95 | 35 ms | iterations=20 |
| Precommit deps P95 | 27 ms | iterations=20 |
| Compression latency | 8.95 ms | iterations=1 |
<!-- BENCHMARK:END -->

## Contributing

Contributions welcome! Please read `CONTRIBUTING.md` first.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

Built with: Model Context Protocol, tree-sitter, SCIP

---

Need help? Open an issue on your repo or check `docs/TECHNICAL.md`.
