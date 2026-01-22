# 🎯 Context Injection Hook Demo Guide

This demo script showcases the full capabilities of the DevBooks context injection Hook, letting you see the context Claude receives behind the scenes.

## 📦 Quick Start

### 1. Run the interactive demo

```bash
./demo-context-injection.sh
```

This launches an interactive menu where you can choose different demo scenarios.

### 2. Run specific demos

```bash
# Run all demos
./demo-context-injection.sh --all

# 4D intent analysis
./demo-context-injection.sh --intent

# Structured context injection
./demo-context-injection.sh --structured

# @file reference feature
./demo-context-injection.sh --file-ref

# Intent type comparison
./demo-context-injection.sh --comparison

# Hotspot file analysis
./demo-context-injection.sh --hotspot

# Full workflow
./demo-context-injection.sh --workflow

# Compare with/without context injection
./demo-context-injection.sh --compare
```

---

## 🎬 Demo Scenarios

### Demo 1: 4D Intent Analysis

Shows how the Hook analyzes the intent of user prompts, including:
- **Explicit**: Direct instruction words (fix, add, remove, etc.)
- **Implicit**: Problem descriptions (error, bug, issue, etc.)
- **Historical**: File references and prior context
- **Code**: Code snippets and symbol names

**Example output**:
```json
{
  "weights": {
    "explicit": 1.0,
    "implicit": 0.8,
    "historical": 0,
    "code": 0.7
  },
  "dominant_dimension": "explicit"
}
```

---

### Demo 2: Structured Context Injection

Shows the 5-layer structured context injected by the Hook:

1. **Project Profile**
   - Project name
   - Tech stack
   - Architecture type
   - Key constraints

2. **Current State**
   - Index status
   - Hotspot files
   - Recent commits

3. **Task Context**
   - Intent analysis
   - Relevant code snippets
   - Call chains

4. **Recommended Tools**
   - MCP tools recommended by intent
   - Suggested parameters

5. **Constraints**
   - Architecture constraints
   - Security constraints

---

### Demo 3: @file Reference Feature

Shows how to use `@file` or `@folder` references to auto-read file content.

**Example**:
```
@src/server.ts What is the main purpose of this file?
```

The Hook automatically:
- Reads the file content (first 30 lines)
- Injects it into context
- Shows the file path and line count

---

### Demo 4: Tool Recommendations by Intent Type

Shows how different intent types recommend different tools:

| Intent Type | Recommended Tools |
|---------|---------|
| **Debug** | `ci_bug_locate`, `ci_call_chain` |
| **Modify** | `ci_call_chain`, `ci_impact` |
| **Explore** | `ci_search`, `ci_graph_rag` |

---

### Demo 5: Hotspot File Analysis

Shows hotspot file detection based on Git history:
- Analyze commit history from the last 30 days
- Find files with the highest change frequency
- These are typically core logic or bug-prone areas

**Example output**:
```
🔥 Hotspot files:
  🔥 scripts/graph-rag.sh (15 changes)
  🔥 hooks/augment-context-global.sh (12 changes)
  🔥 scripts/call-chain.sh (10 changes)
```

---

### Demo 6: Full Context Injection Workflow

Shows the full flow from user prompt to context injection:

```
User prompt
    ↓
Intent analysis
    ↓
Symbol extraction
    ↓
Code search
    ↓
Hotspot analysis
    ↓
Tool recommendation
    ↓
Structured context injection
    ↓
Claude receives enhanced context
```

---

### Demo 7: Comparison With/Without Context Injection

A direct comparison of the differences:

#### ❌ Without context injection
- Claude only knows the user's prompt
- Requires multiple turns to locate issues
- Provides generic suggestions

#### ✅ With context injection
- Claude automatically knows the project tech stack
- Sees related code locations
- Knows hotspot files
- Receives recommended tools
- Provides accurate suggestions in one shot

---

## 🔍 Real-World Scenarios

### Scenario 1: Fixing a Bug

**User prompt**: "fix the authentication bug"

**Hook auto-injects**:
- Extracted symbols: `authentication`
- Related code: `src/auth.ts`, `src/login.ts`
- Recommended tools: `ci_bug_locate`, `ci_call_chain`
- Hotspot files: recently modified auth-related files

**Result**: Claude can directly locate the problematic code, analyze call chains, and provide precise fixes.


---

### Scenario 2: Adding a Feature

**User prompt**: "add a new export feature"

**Hook auto-injects**:
- Intent analysis: modify (explicit instruction "add")
- Recommended tools: `ci_call_chain`, `ci_impact`
- Project constraints shown: architecture rules and tech stack limits

**Result**: Claude understands the architecture, recommends an appropriate implementation, and analyzes impact.

---

### Scenario 3: Understanding the Codebase

**User prompt**: "how does the MCP server work?"

**Hook auto-injects**:
- Intent analysis: explore
- Recommended tools: `ci_search`, `ci_graph_rag`
- Project structure shown: tech stack and architecture type

**Result**: Claude uses Graph-RAG to understand the code structure and provides a clear explanation.

---

## 🎨 Custom Demos

You can edit `demo-context-injection.sh` to add your own demo scenarios:

```bash
# Add a new demo function
demo_my_scenario() {
    print_title "My Custom Demo"

    local my_prompt="your prompt"
    print_prompt "$my_prompt"

    result=$(echo "{\"prompt\":\"$my_prompt\"}" | "$HOOK_SCRIPT")
    print_json "$result"
}
```

---

## 📊 Output Formats

### JSON format (default)
```bash
echo '{"prompt":"your prompt"}' | hooks/augment-context-global.sh
```

### Text format
```bash
echo '{"prompt":"your prompt"}' | hooks/augment-context-global.sh --format text
```

### Intent analysis
```bash
hooks/augment-context-global.sh --analyze-intent --prompt "your prompt"
```

---

## 🔧 Troubleshooting

### Issue 1: Hook script not found

**Solution**:
```bash
# Ensure scripts are executable
chmod +x hooks/augment-context-global.sh
chmod +x demo-context-injection.sh
```

### Issue 2: jq command not found

**Solution**:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

### Issue 3: No Git history

**Solution**:
- Hotspot analysis requires a Git repository
- Ensure the project is a Git repo: `git init`

---

## 💡 Tips

1. **Interactive mode is most intuitive**: Use `./demo-context-injection.sh` to explore scenarios one by one.

2. **Comparison demo is most persuasive**: Run `--compare` to see the value of context injection.

3. **Full workflow is most comprehensive**: Run `--workflow` to understand the end-to-end flow.

4. **Custom prompts**: You can invoke the Hook directly to test your own prompts:
   ```bash
   echo '{"prompt":"your prompt"}' | hooks/augment-context-global.sh
   ```

---

## 🎯 Next Steps

1. **Run the demo**: `./demo-context-injection.sh`
2. **Read the Hook source**: `hooks/augment-context-global.sh`
3. **Configure the Hook**: edit `.devbooks/config.yaml`
4. **Integrate with Claude Code**: the Hook triggers on UserPromptSubmit events

---

## 📚 Related Docs

- [Hook internals](hooks/augment-context-global.sh)
- [Configuration reference](.devbooks/config.yaml)
- [MCP tool list](src/server.ts)

---

## 🤝 Feedback

If you find any issues or have suggestions:
1. Check the demo output
2. Check the Hook script logs
3. Open an Issue or PR

---

**Enjoy context-enhanced AI coding!** 🚀
