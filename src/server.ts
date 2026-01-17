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
    description: "Semantic code search using embeddings or keywords",
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
    description: "Trace function call chains",
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
    description: "Locate potential bug locations based on error description",
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
    description: "Analyze code complexity metrics",
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
    description: "Get Graph-RAG context for a query",
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
    description: "Check or manage embedding index status",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["status", "build", "clear"],
          description: "Action to perform (default: status)",
        },
      },
    },
  },
  {
    name: "ci_hotspot",
    description: "Analyze code hotspots based on change frequency and complexity",
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
    description: "Detect code boundary type (user/library/generated/vendor)",
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
    description: "Check architecture rules and detect circular dependencies",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: { type: "string", description: "Path to analyze (default: current directory)" },
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
    description: "Cross-repo API contract tracking, symbol search, and virtual edges",
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
    description: "图存储操作（初始化、查询、统计）",
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
    description: "AST 增量索引操作（基于 tree-sitter 的快速代码变更检测）",
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
    description: "符号变更的传递性影响分析（多跳图遍历 + 置信度衰减）",
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
    description: "代码库架构可视化（生成 Mermaid 或 D3.js JSON 格式的架构图）",
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
    description: "用户查询意图历史记录和偏好学习",
    inputSchema: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          enum: ["record", "get-preferences", "cleanup", "stats"],
          description: "Action: record (add query), get-preferences, cleanup, stats",
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
    description: "依赖安全漏洞扫描与追踪（集成 npm audit）",
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

async function handleToolCall(
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "ci_search": {
      const query = args.query as string;
      const limit = (args.limit as number) || 10;
      const mode = (args.mode as string) || "semantic";
      const { stdout, stderr } = await runScript("embedding.sh", [
        "search",
        query,
        "--limit",
        String(limit),
        "--mode",
        mode,
      ]);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_call_chain": {
      const symbol = args.symbol as string;
      const direction = (args.direction as string) || "both";
      const depth = (args.depth as number) || 3;
      const { stdout, stderr } = await runScript("call-chain.sh", [
        symbol,
        "--direction",
        direction,
        "--depth",
        String(depth),
      ]);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_bug_locate": {
      const error = args.error as string;
      const { stdout, stderr } = await runScript("bug-locator.sh", [
        "--error",
        error,
      ]);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_complexity": {
      const path = args.path as string;
      const format = (args.format as string) || "text";
      const { stdout, stderr } = await runScript("complexity.sh", [
        path,
        "--format",
        format,
      ]);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_graph_rag": {
      const query = args.query as string;
      const depth = (args.depth as number) || 2;
      const budget = (args.budget as number) || 8000;
      const { stdout, stderr } = await runScript("graph-rag.sh", [
        query,
        "--depth",
        String(depth),
        "--budget",
        String(budget),
      ]);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_index_status": {
      const action = (args.action as string) || "status";
      const { stdout, stderr } = await runScript("indexer.sh", [action]);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_hotspot": {
      const top = (args.top as number) || 20;
      const days = (args.days as number) || 30;
      const format = (args.format as string) || "json";
      const path = (args.path as string) || ".";
      const { stdout, stderr } = await runScript("hotspot-analyzer.sh", [
        "--top",
        String(top),
        "--days",
        String(days),
        "--format",
        format,
        "--path",
        path,
      ]);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_boundary": {
      const file = args.file as string;
      const format = (args.format as string) || "json";
      const { stdout, stderr } = await runScript("boundary-detector.sh", [
        "--format",
        format,
        file,
      ]);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_arch_check": {
      const path = (args.path as string) || ".";
      const format = (args.format as string) || "json";
      const rules = (args.rules as string) || "";
      const scriptArgs = ["--all", "--scope", path, "--format", format];
      if (rules) {
        scriptArgs.push("--rules", rules);
      }
      const { stdout, stderr } = await runScript("dependency-guard.sh", scriptArgs);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_federation": {
      const action = (args.action as string) || "status";
      const query = (args.query as string) || "";
      const format = (args.format as string) || "json";
      const minConfidence = args.min_confidence as number | undefined;
      const localRepo = args.local_repo as string | undefined;
      const sync = args.sync === true;

      const scriptArgs: string[] = [];
      switch (action) {
        case "status":
          scriptArgs.push("--status");
          break;
        case "update":
          scriptArgs.push("--update");
          break;
        case "search":
          scriptArgs.push("--search", query);
          break;
        case "generate-virtual-edges":
          scriptArgs.push("generate-virtual-edges");
          if (localRepo) {
            scriptArgs.push("--local-repo", localRepo);
          }
          if (minConfidence !== undefined) {
            scriptArgs.push("--min-confidence", String(minConfidence));
          }
          if (sync) {
            scriptArgs.push("--sync");
          }
          break;
        case "query-virtual":
          if (!query) {
            return "Error: query-virtual action requires query parameter";
          }
          scriptArgs.push("query-virtual", query);
          if (minConfidence !== undefined) {
            scriptArgs.push("--confidence", String(minConfidence));
          }
          break;
        default:
          return `Unknown action: ${action}`;
      }
      scriptArgs.push("--format", format);
      const { stdout, stderr } = await runScript("federation-lite.sh", scriptArgs);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    case "ci_graph_store": {
      const action = args.action as string;
      const payload = args.payload as Record<string, unknown> | undefined;
      let scriptArgs: string[] = [];
      switch (action) {
        case "init":
          scriptArgs = ["init"];
          break;
        case "stats":
          scriptArgs = ["stats"];
          break;
        case "query":
          if (payload && typeof payload.sql === "string") {
            scriptArgs = ["query", payload.sql];
          } else {
            return "Error: query action requires payload.sql";
          }
          break;
        default:
          return `Unknown action: ${action}`;
      }
      const { stdout, stderr } = await runScript("graph-store.sh", scriptArgs);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    // MP8.1: AST Delta 增量索引
    case "ci_ast_delta": {
      const action = (args.action as string) || "status";
      const file = args.file as string | undefined;
      const since = args.since as string | undefined;
      const scriptArgs: string[] = [];
      switch (action) {
        case "update":
          if (file) {
            scriptArgs.push("update", file);
          } else {
            return "Error: update action requires file parameter";
          }
          break;
        case "batch":
          scriptArgs.push("batch");
          if (since) {
            scriptArgs.push("--since", since);
          }
          break;
        case "status":
          scriptArgs.push("status");
          break;
        case "clear-cache":
          scriptArgs.push("clear-cache");
          break;
        default:
          return `Unknown action: ${action}`;
      }
      const { stdout, stderr } = await runScript("ast-delta.sh", scriptArgs);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    // MP8.2: 影响分析
    case "ci_impact": {
      const symbol = args.symbol as string | undefined;
      const file = args.file as string | undefined;
      const depth = (args.depth as number) || 3;
      const decay = args.decay as number | undefined;
      const threshold = args.threshold as number | undefined;
      const format = (args.format as string) || "json";

      const scriptArgs: string[] = [];
      if (symbol) {
        scriptArgs.push("analyze", symbol);
      } else if (file) {
        scriptArgs.push("file", file);
      } else {
        return "Error: either symbol or file parameter is required";
      }
      scriptArgs.push("--depth", String(depth));
      if (decay !== undefined) {
        scriptArgs.push("--decay", String(decay));
      }
      if (threshold !== undefined) {
        scriptArgs.push("--threshold", String(threshold));
      }
      scriptArgs.push("--format", format);
      const { stdout, stderr } = await runScript("impact-analyzer.sh", scriptArgs);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    // MP8.3: COD 架构可视化
    case "ci_cod": {
      const action = (args.action as string) || "generate";
      const level = (args.level as number) || 2;
      const module = args.module as string | undefined;
      const format = (args.format as string) || "mermaid";
      const includeHotspots = args.include_hotspots !== false; // 默认 true
      const includeComplexity = args.include_complexity === true; // 默认 false

      const scriptArgs: string[] = [];
      if (action === "module" && module) {
        scriptArgs.push("module", module);
      } else {
        scriptArgs.push("generate", "--level", String(level));
      }
      scriptArgs.push("--format", format);
      if (includeHotspots) {
        scriptArgs.push("--include-hotspots");
      }
      if (includeComplexity) {
        scriptArgs.push("--include-complexity");
      }
      const { stdout, stderr } = await runScript("cod-visualizer.sh", scriptArgs);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    // MP8.4: 意图偏好学习
    case "ci_intent": {
      const action = (args.action as string) || "stats";
      const query = args.query as string | undefined;
      const symbols = args.symbols as string[] | undefined;
      const userAction = (args.user_action as string) || "view";
      const top = args.top as number | undefined;
      const prefix = args.prefix as string | undefined;
      const days = args.days as number | undefined;

      const scriptArgs: string[] = [];
      switch (action) {
        case "record":
          if (!query) {
            return "Error: record action requires query parameter";
          }
          scriptArgs.push("record", query);
          if (symbols && symbols.length > 0) {
            scriptArgs.push("--symbols", symbols.join(","));
          }
          scriptArgs.push("--action", userAction);
          break;
        case "get-preferences":
          scriptArgs.push("get-preferences");
          if (top !== undefined) {
            scriptArgs.push("--top", String(top));
          }
          if (prefix) {
            scriptArgs.push("--prefix", prefix);
          }
          break;
        case "cleanup":
          scriptArgs.push("cleanup");
          if (days !== undefined) {
            scriptArgs.push("--days", String(days));
          }
          break;
        case "stats":
          scriptArgs.push("stats");
          break;
        default:
          return `Unknown action: ${action}`;
      }
      const { stdout, stderr } = await runScript("intent-learner.sh", scriptArgs);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    // MP8.5: 安全漏洞追踪
    case "ci_vuln": {
      const action = (args.action as string) || "scan";
      const pkg = args.package as string | undefined;
      const severity = (args.severity as string) || "moderate";
      const format = (args.format as string) || "json";
      const includeDev = args.include_dev === true;

      const scriptArgs: string[] = [];
      switch (action) {
        case "scan":
          scriptArgs.push("scan");
          scriptArgs.push("--severity", severity);
          scriptArgs.push("--format", format);
          if (includeDev) {
            scriptArgs.push("--include-dev");
          }
          break;
        case "trace":
          if (!pkg) {
            return "Error: trace action requires package parameter";
          }
          scriptArgs.push("trace", pkg);
          break;
        default:
          return `Unknown action: ${action}`;
      }
      const { stdout, stderr } = await runScript("vuln-tracker.sh", scriptArgs);
      return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
    }

    default:
      return `Unknown tool: ${name}`;
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
