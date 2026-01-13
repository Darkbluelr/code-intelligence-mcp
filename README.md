# Code Intelligence MCP Server

MCP Server providing code intelligence capabilities for AI coding assistants.

## Features

- **Embedding Search**: Semantic code search using local (Ollama) or cloud (OpenAI) embeddings
- **Graph-RAG Context**: Graph-based retrieval-augmented generation
- **Call-chain Tracing**: Trace function call chains
- **Bug Locator**: Intelligent bug location
- **Complexity Analysis**: Code complexity metrics
- **Entropy Visualization**: Code entropy metrics

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

## Configuration

Copy `config/config.yaml.template` to your project's `.devbooks/config.yaml`.

## License

MIT
