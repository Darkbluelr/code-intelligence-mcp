# LLM Provider Script Conventions

This directory contains LLM Provider implementation scripts. Each provider must follow the conventions below.

## File Structure

```
scripts/llm-providers/
  anthropic.sh    # Anthropic Claude provider
  openai.sh       # OpenAI GPT provider
  ollama.sh       # Local Ollama provider
  mock.sh         # Mock provider for tests
  README.md       # This document
```

## Provider Interface Conventions

Each provider script must implement the following functions.

### Required Functions

#### `_llm_provider_rerank(query, candidates_json)`

Re-rank the candidate list.

**Parameters**:
- `query`: user query string
- `candidates_json`: candidate list in JSON array format

**Returns**:
- Success: JSON array of ranked results
- Failure: non-zero exit code

**Example output**:
```json
[
  {"index": 0, "score": 9, "reason": "direct match"},
  {"index": 2, "score": 7, "reason": "related"}
]
```

#### `_llm_provider_call(prompt)`

Call the LLM and return a response.

**Parameters**:
- `prompt`: user prompt string

**Returns**:
- Success: LLM response text
- Failure: non-zero exit code

### Optional Functions

#### `_llm_provider_validate()`

Validate whether the provider configuration is valid.

**Returns**:
- 0: configuration is valid
- 1: configuration is invalid

## Environment Variables

Providers can use the following environment variables:

| Variable | Purpose |
|------|------|
| `LLM_MODEL` | Override the default model |
| `LLM_TIMEOUT_MS` | Timeout in milliseconds (default 2000) |
| `LLM_MAX_TOKENS` | Maximum output tokens |
| `LLM_ENDPOINT` | Override the default endpoint |

## Mock Mode

All providers should check these environment variables to support testing:

| Variable | Purpose |
|------|------|
| `LLM_MOCK_RESPONSE` | Return this response instead of calling the API |
| `LLM_MOCK_DELAY_MS` | Simulate latency |
| `LLM_MOCK_FAIL_COUNT` | Fail the first N calls |

## Example Provider Template

```bash
#!/bin/bash
# My Custom Provider
# Implement a custom LLM Provider

# Rerank implementation
_llm_provider_rerank() {
  local query="$1"
  local candidates="$2"

  # Check mock mode
  if [[ -n "${LLM_MOCK_RESPONSE:-}" ]]; then
    echo "$LLM_MOCK_RESPONSE"
    return 0
  fi

  # Implement reranking logic
  # ...
}

# Call implementation
_llm_provider_call() {
  local prompt="$1"

  # Check mock mode
  if [[ -n "${LLM_MOCK_RESPONSE:-}" ]]; then
    echo "$LLM_MOCK_RESPONSE"
    return 0
  fi

  # Implement LLM call logic
  # ...
}

# Validation implementation (optional)
_llm_provider_validate() {
  # Check required config
  # ...
  return 0
}
```

## Register a New Provider

Add configuration to `config/llm-providers.yaml`:

```yaml
providers:
  my_provider:
    script: my-provider.sh
    env_key: MY_PROVIDER_API_KEY
    default_model: my-model-v1
    endpoint: https://api.my-provider.com/v1
```
