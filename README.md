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
npm install -g code-intelligence-mcp
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
| `ci_index_status` | Manage embedding index (status/build/clear) |
| `ci_boundary` | Code boundary detection (user/library/generated) |
| `ci_graph_store` | Graph store operations (init/query/stats) |
| `ci_federation` | Cross-repo API contract tracking |
| `ci_ast_delta` | Incremental AST parsing |
| `ci_cod` | Architecture visualization (Mermaid/D3.js) |
| `ci_intent` | Query history and preference learning |

**20+ tools available** - Each tool supports `--help` for detailed usage.

## Configuration

### Embedding Providers

Supports multiple embedding providers for semantic search:

```yaml
# config/llm-providers.yaml
embedding:
  provider: ollama  # or openai, anthropic
  model: nomic-embed-text

  # Ollama (local, free)
  # provider: ollama
  # base_url: http://localhost:11434

  # OpenAI (cloud, paid)
  # provider: openai
  # api_key: sk-...

  # Anthropic (cloud, paid)
  # provider: anthropic
  # api_key: sk-ant-...
```

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

Install the Claude Code hook for automatic context injection:

```bash
./install.sh --with-hook
```

Now when you ask Claude to "fix the authentication bug", relevant code is automatically injected.

### Custom Queries

```bash
# Search with specific mode
ci-search "user service" --mode semantic --limit 5

# Trace call chains
ci_call_chain --symbol "processPayment" --direction both

# Check architecture
ci_arch_check --path src/
```

## Performance

Measured on 2026-01-22 in this repo (see `dev-playbooks/changes/20260122-verify-metrics/evidence/`):

- Semantic search (ci-search): ~570ms single run (not P95)
- Graph-RAG retrieval: 551ms first, 526ms second (single runs)
- Context compression ratio (skeleton mode on `src/server.ts`): 0.07

Previously stated targets (P95/relative improvements) are now tracked in evidence and should be updated per release.

## Contributing

Contributions welcome! Please read `CONTRIBUTING.md` first.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

Built with: Model Context Protocol, tree-sitter, SCIP

---

Need help? Open an issue on your repo or check `docs/TECHNICAL.md`.
