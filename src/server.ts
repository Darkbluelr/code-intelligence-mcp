#!/usr/bin/env node
/**
 * Code Intelligence MCP Server
 *
 * A thin MCP shell that delegates to shell scripts for code intelligence capabilities.
 * CON-TECH-002: MCP Server 使用 Node.js 薄壳调用 Shell 脚本
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execFile } from "child_process";
import { promisify } from "util";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { TOOL_HANDLERS } from "./tool-handlers.js";

const execFileAsync = promisify(execFile);

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const SCRIPTS_DIR = join(__dirname, "..", "scripts");

const VERSION = "0.1.0";

// Configuration constants
const SCRIPT_TIMEOUT_MS = 60000; // 60s timeout
const MAX_BUFFER_SIZE = 10 * 1024 * 1024; // 10MB buffer

interface ExecError extends Error {
  stdout?: string;
  stderr?: string;
}

// Tool definitions
const TOOLS = [
  {
    name: "ci_search",
    description: "Semantic code search using embeddings or keywords. Use this for natural language queries like 'find authentication code' or 'where is error handling'. Supports both semantic (AI-powered) and keyword search modes. Best for: discovering code by concept, finding related implementations, exploring unfamiliar codebases.",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: { type: "string", description: "Search query" },
        limit: { type: "number", description: "Max results (default: 10)" },
        mode: {
          type: "string",
          enum: ["semantic", "keyword"],
          description: "Search mode (default: semantic)",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "ci_call_chain",
    description: "Trace function call chains to understand code flow. Use this to find who calls a function (callers) or what a function calls (callees). Best for: understanding dependencies, impact analysis before refactoring, debugging call paths, finding entry points.",
    inputSchema: {
      type: "object" as const,
      properties: {
        symbol: { type: "string", description: "Symbol to trace" },
        direction: {
          type: "string",
          enum: ["callers", "callees", "both"],
          description: "Trace direction (default: both)",
        },
        depth: { type: "number", description: "Max depth (default: 3)" },
      },
      required: ["symbol"],
    },
  },
  {
    name: "ci_bug_locate",
    description: "Locate potential bug locations based on error description. Paste an error message or stack trace to find relevant code. Best for: debugging errors, finding root causes, locating exception sources.",
    inputSchema: {
      type: "object" as const,
      properties: {
        error: { type: "string", description: "Error message or description" },
      },
      required: ["error"],
    },
  },
  {
    name: "ci_complexity",
    description: "Analyze code complexity metrics (cyclomatic complexity, lines of code, etc.). Use this to identify complex code that may need refactoring. Best for: code quality assessment, finding technical debt, prioritizing refactoring.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: { type: "string", description: "File or directory path" },
        format: {
          type: "string",
          enum: ["text", "json"],
          description: "Output format (default: text)",
        },
      },
      required: ["path"],
    },
  },
  {
    name: "ci_graph_rag",
    description: "Get Graph-RAG context for a query. Combines semantic search with code graph traversal to provide rich context. Use this when you need comprehensive context about a topic including related code, dependencies, and call relationships. Best for: understanding complex features, gathering context for code changes, exploring interconnected code.",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: { type: "string", description: "Query for context retrieval" },
        depth: { type: "number", description: "Graph traversal depth (default: 2)" },
        budget: { type: "number", description: "Token budget (default: 8000)" },
      },
      required: ["query"],
    },
  },
  {
    name: "ci_index_status",
    description: "Check or manage the semantic search embedding index. Use 'status' to check index health, 'build' to rebuild after major code changes, 'clear' to reset. Best for: troubleshooting search issues, maintaining search quality.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["status", "build", "clear"],
          description: "Action to perform: status (check index status), build (rebuild embedding index), clear (clean embedding cache). Default: status",
        },
      },
    },
  },
  {
    name: "ci_hotspot",
    description: "Find code hotspots - files that change frequently and have high complexity. These are often sources of bugs and good refactoring candidates. Best for: identifying risky code, prioritizing code review, finding technical debt.",
    inputSchema: {
      type: "object" as const,
      properties: {
        top: { type: "number", description: "Number of top hotspots to return (default: 20)" },
        days: { type: "number", description: "Number of days to analyze git history (default: 30)" },
        format: {
          type: "string",
          enum: ["text", "json"],
          description: "Output format (default: json)",
        },
        path: { type: "string", description: "Target directory to analyze (default: current directory)" },
      },
    },
  },
  {
    name: "ci_boundary",
    description: "Detect code boundary type (user code, library, generated, vendor). Use this to understand code ownership and filter analysis. Best for: excluding vendor code from analysis, identifying generated files.",
    inputSchema: {
      type: "object" as const,
      properties: {
        file: { type: "string", description: "File or pattern to check" },
        format: {
          type: "string",
          enum: ["text", "json"],
          description: "Output format (default: json)",
        },
      },
      required: ["file"],
    },
  },
  {
    name: "ci_arch_check",
    description: "Check architecture rules and detect circular dependencies. Use this to enforce module boundaries and find dependency cycles. Best for: maintaining clean architecture, preventing spaghetti code, enforcing layering rules.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: { type: "string", description: "Path to analyze (default: src/)" },
        format: {
          type: "string",
          enum: ["text", "json"],
          description: "Output format (default: json)",
        },
        rules: { type: "string", description: "Path to architecture rules file (default: config/arch-rules.yaml)" },
      },
    },
  },
  {
    name: "ci_federation",
    description: "Cross-repo API contract tracking and symbol search. Use this to find how external APIs are used across repositories, track breaking changes, and discover virtual edges between repos. Best for: microservices architecture, API versioning, cross-repo refactoring.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["status", "update", "search", "generate-virtual-edges", "query-virtual"],
          description: "Action to perform (default: status)",
        },
        query: { type: "string", description: "Symbol query for search/query-virtual action" },
        format: {
          type: "string",
          enum: ["text", "json"],
          description: "Output format (default: json)",
        },
        min_confidence: { type: "number", description: "Minimum confidence threshold for virtual edges (default: 0.5)" },
        local_repo: { type: "string", description: "Local repository path for generate-virtual-edges (default: current directory)" },
        sync: { type: "boolean", description: "Enable sync mode for generate-virtual-edges (update existing, remove stale)" },
      },
    },
  },
  {
    name: "ci_graph_store",
    description: "Query the code intelligence graph database directly with SQL. Use this for custom queries on symbols, references, and relationships. Best for: advanced analysis, custom reports, debugging index issues.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["init", "query", "stats"],
          description: "Action to perform: init (initialize database), query (execute SQL), stats (show statistics)",
        },
        payload: {
          type: "object",
          properties: {
            sql: { type: "string", description: "SQL query for query action" },
          },
          description: "Payload object for query action containing sql field",
        },
      },
      required: ["action"],
    },
  },
  // MP8.1: AST Delta 增量索引工具
  {
    name: "ci_ast_delta",
    description: "AST-based incremental indexing using tree-sitter. Use this to update the code index after file changes without full rebuild. Best for: keeping index fresh, fast incremental updates, CI/CD integration.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["update", "batch", "status", "clear-cache"],
          description: "Action to perform: update (single file), batch (multiple files), status, clear-cache",
        },
        file: { type: "string", description: "File path for update action" },
        since: { type: "string", description: "Git ref for batch action (default: HEAD~1)" },
      },
    },
  },
  // MP8.2: 影响分析工具
  {
    name: "ci_impact",
    description: "Analyze the impact of changing a symbol or file. Uses multi-hop graph traversal with confidence decay to find all affected code. Best for: safe refactoring, understanding change risk, planning migrations, pre-commit impact check.",
    inputSchema: {
      type: "object" as const,
      properties: {
        symbol: { type: "string", description: "Symbol to analyze impact for" },
        file: { type: "string", description: "File path for file-level analysis (alternative to symbol)" },
        depth: { type: "number", description: "Max traversal depth (default: 3, max: 5)" },
        decay: { type: "number", description: "Decay factor for impact calculation (default: 0.8)" },
        threshold: { type: "number", description: "Minimum impact threshold (default: 0.1)" },
        format: {
          type: "string",
          enum: ["json", "md", "mermaid"],
          description: "Output format (default: json)",
        },
      },
    },
  },
  // MP8.3: COD 架构可视化工具
  {
    name: "ci_cod",
    description: "Generate codebase architecture diagrams (Mermaid or D3.js). Visualize module dependencies, file relationships, and system structure. Best for: documentation, onboarding, architecture review, identifying coupling.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["generate", "module"],
          description: "Action: generate (full codebase), module (specific module)",
        },
        level: {
          type: "number",
          enum: [1, 2, 3],
          description: "Visualization level: 1=system context, 2=module, 3=file (default: 2)",
        },
        module: { type: "string", description: "Module path for module action" },
        format: {
          type: "string",
          enum: ["mermaid", "d3json"],
          description: "Output format (default: mermaid)",
        },
        include_hotspots: { type: "boolean", description: "Include hotspot coloring (default: true)" },
        include_complexity: { type: "boolean", description: "Include complexity annotations (default: false)" },
      },
    },
  },
  // MP8.4: 意图偏好学习工具
  {
    name: "ci_intent",
    description: "Track user query history and learn preferences. Records which code users frequently access to improve future search relevance. Best for: personalized search, learning codebase patterns, improving recommendations.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["record", "get-preferences", "cleanup"],
          description: "Action: record (add query), get-preferences, cleanup",
        },
        query: { type: "string", description: "Query text for record action" },
        symbols: {
          type: "array",
          items: { type: "string" },
          description: "Matched symbols for record action",
        },
        user_action: {
          type: "string",
          enum: ["view", "edit", "ignore"],
          description: "User action for record (default: view)",
        },
        top: { type: "number", description: "Number of top preferences to return (default: 10)" },
        prefix: { type: "string", description: "Filter preferences by path prefix" },
        days: { type: "number", description: "Days threshold for cleanup (default: 90)" },
      },
    },
  },
  // MP8.5: 安全漏洞追踪工具
  {
    name: "ci_vuln",
    description: "Scan for security vulnerabilities in dependencies using npm audit. Trace how vulnerable packages are used in your code. Best for: security audits, dependency updates, compliance checks.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["scan", "trace"],
          description: "Action: scan (vulnerability scan), trace (dependency trace)",
        },
        package: { type: "string", description: "Package name for trace action" },
        severity: {
          type: "string",
          enum: ["low", "moderate", "high", "critical"],
          description: "Minimum severity threshold (default: moderate)",
        },
        format: {
          type: "string",
          enum: ["json", "md"],
          description: "Output format (default: json)",
        },
        include_dev: { type: "boolean", description: "Include dev dependencies (default: false)" },
      },
    },
  },
  {
    name: "ci_adr",
    description: "Parse Architecture Decision Records (ADRs) and optionally link them to the code graph. Use this to scan ADRs, extract keywords, and keep an ADR index up to date.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["scan", "status", "parse", "keywords"],
          description: "Action to perform: scan (scan all ADRs), status (index status), parse (parse one ADR file), keywords (extract keywords from one ADR file)",
        },
        file: { type: "string", description: "ADR file path for parse/keywords" },
        adr_dir: { type: "string", description: "ADR directory for scan (overrides auto discovery)" },
        link: { type: "boolean", description: "Whether to link ADR keywords into graph (scan only)" },
        format: {
          type: "string",
          enum: ["json", "text"],
          description: "Output format (default: json)",
        },
      },
    },
  },
  {
    name: "ci_warmup",
    description: "Pre-warm daemon caches for hot subgraphs. Uses daemon warmup pipeline to reduce cold-start latency.",
    inputSchema: {
      type: "object" as const,
      properties: {
        timeout: { type: "number", description: "Warmup timeout in seconds (default: 30)" },
        hotspot_limit: { type: "number", description: "Number of hotspot files to cache (default: 10)" },
        queries: { type: "string", description: "Comma-separated warmup query list" },
        format: {
          type: "string",
          enum: ["json", "text"],
          description: "Output format (default: json)",
        },
        async: { type: "boolean", description: "Run warmup in background" },
      },
    },
  },
  {
    name: "ci_context_compress",
    description: "Compress code context into a compact skeleton for efficient prompting. Useful for large files or directories where only signatures matter.",
    inputSchema: {
      type: "object" as const,
      properties: {
        paths: {
          type: "array",
          items: { type: "string" },
          description: "Input files or directories to compress",
        },
        mode: { type: "string", enum: ["skeleton"], description: "Compression mode (default: skeleton)" },
        compress: {
          type: "string",
          enum: ["low", "medium", "high"],
          description: "Compression level (default: medium)",
        },
        budget: { type: "number", description: "Token budget (line-based)" },
        hotspot: { type: "string", description: "Hotspot directory for prioritization" },
        cache: { type: "boolean", description: "Enable cache" },
      },
      required: ["paths"],
    },
  },
  {
    name: "ci_drift_detect",
    description: "Detect architecture drift and compare snapshots. Supports snapshot/compare/report and C4/code scans.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["compare", "diff", "snapshot", "rules", "report", "c4", "parse-c4", "scan-code"],
          description: "Action to perform (default: compare)",
        },
        baseline: { type: "string", description: "Baseline snapshot path" },
        current: { type: "string", description: "Current snapshot path" },
        project_dir: { type: "string", description: "Project directory for snapshot/rules/scan-code" },
        output: { type: "string", description: "Output snapshot path (snapshot action)" },
        rules: { type: "string", description: "Architecture rules file path" },
        period: { type: "string", description: "Report period (weekly|daily|monthly)" },
        snapshots_dir: { type: "string", description: "Snapshots directory for report" },
        c4: { type: "string", description: "C4 model file path" },
        code: { type: "string", description: "Code directory for C4 compare" },
      },
    },
  },
  {
    name: "ci_semantic_anomaly",
    description: "Detect semantic anomalies based on learned patterns. Useful for finding inconsistent API usage, missing error handling, and other latent issues.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: { type: "string", description: "File or directory to scan" },
        pattern: { type: "string", description: "Custom pattern file" },
        output: {
          type: "string",
          description: "Output format (json|text) or output file path",
        },
        threshold: { type: "number", description: "Confidence threshold (default: 0.8)" },
        report: { type: "boolean", description: "Generate report to evidence/semantic-anomaly-report.md" },
        enable_all_features: { type: "boolean", description: "Force enable all features" },
      },
      required: ["path"],
    },
  },
  {
    name: "ci_benchmark",
    description: "Run performance benchmarks or compare benchmark reports.",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["dataset", "compare", "cache", "full", "precommit", "all"],
          description: "Action to perform: dataset/compare or legacy cache/full/precommit/all",
        },
        dataset: { type: "string", enum: ["self", "public"], description: "Dataset type" },
        queries: { type: "string", description: "Queries file (JSONL)" },
        output: { type: "string", description: "Output report path (required for dataset action)" },
        baseline: { type: "string", description: "Baseline report path (optional for dataset action)" },
        compare_base: { type: "string", description: "Compare baseline path" },
        compare_current: { type: "string", description: "Compare current path" },
        iterations: { type: "number", description: "Iterations for legacy modes" },
        enable_all_features: { type: "boolean", description: "Force enable all features" },
      },
    },
  },
];

async function runScript(
  script: string,
  args: string[]
): Promise<{ stdout: string; stderr: string }> {
  const scriptPath = join(SCRIPTS_DIR, script);
  // Use execFile instead of exec to avoid shell injection vulnerabilities
  // Arguments are passed as array, not interpolated into a shell command string

  try {
    const { stdout, stderr } = await execFileAsync("bash", [scriptPath, ...args], {
      timeout: SCRIPT_TIMEOUT_MS,
      maxBuffer: MAX_BUFFER_SIZE,
    });
    return { stdout, stderr };
  } catch (error: unknown) {
    const execError = error as ExecError;
    // Return partial output even on error
    return {
      stdout: execError.stdout || "",
      stderr: execError.stderr || execError.message || "Unknown error",
    };
  }
}

/**
 * Handle MCP tool calls using strategy pattern
 *
 * Fixes:
 * - C-001: Added parameter validation via tool handlers
 * - C-002: Refactored from 374-line switch statement to strategy pattern
 */
async function handleToolCall(
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  const handler = TOOL_HANDLERS[name];
  if (!handler) {
    return `Unknown tool: ${name}`;
  }

  try {
    return await handler(args, runScript);
  } catch (error) {
    if (error instanceof Error) {
      return `Error: ${error.message}`;
    }
    return `Error: Unknown error occurred`;
  }
}

async function main() {
  // Handle --version and --help
  const args = process.argv.slice(2);
  if (args.includes("--version") || args.includes("-v")) {
    console.log(`code-intelligence-mcp v${VERSION}`);
    process.exit(0);
  }
  if (args.includes("--help") || args.includes("-h")) {
    console.log(`
Code Intelligence MCP Server v${VERSION}

Usage:
  code-intelligence-mcp [options]

Options:
  -h, --help     Show this help message
  -v, --version  Show version number

Description:
  MCP Server providing code intelligence capabilities:
  - Semantic code search (embeddings)
  - Call chain tracing
  - Bug location
  - Complexity analysis
  - Graph-RAG context with smart pruning
  - Hotspot analysis (frequency x complexity)
  - Code boundary detection
  - AST delta incremental indexing
  - Transitive impact analysis
  - Codebase architecture visualization (COD)
  - Intent preference learning
  - Security vulnerability tracking
  - Cross-repo federation with virtual edges

For more information, see: https://github.com/user/code-intelligence-mcp
`);
    process.exit(0);
  }

  const server = new Server(
    {
      name: "code-intelligence-mcp",
      version: VERSION,
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  // List tools handler
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    return { tools: TOOLS };
  });

  // Call tool handler
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;
    const result = await handleToolCall(name, args || {});
    return {
      content: [{ type: "text", text: result }],
    };
  });

  // Start server
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
