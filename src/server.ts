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
import { exec } from "child_process";
import { promisify } from "util";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const execAsync = promisify(exec);

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const SCRIPTS_DIR = join(__dirname, "..", "scripts");

const VERSION = "0.1.0";

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
];

async function runScript(
  script: string,
  args: string[]
): Promise<{ stdout: string; stderr: string }> {
  const scriptPath = join(SCRIPTS_DIR, script);
  const cmd = `bash "${scriptPath}" ${args.map((a) => `"${a}"`).join(" ")}`;

  try {
    const { stdout, stderr } = await execAsync(cmd, {
      timeout: 60000, // 60s timeout
      maxBuffer: 10 * 1024 * 1024, // 10MB buffer
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
  - Graph-RAG context
  - Hotspot analysis (frequency x complexity)
  - Code boundary detection

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
