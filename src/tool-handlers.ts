/**
 * Tool handlers for Code Intelligence MCP Server
 *
 * This module contains individual handlers for each MCP tool,
 * extracted from the monolithic handleToolCall function.
 *
 * Fixes:
 * - C-001: Added parameter validation for all tool calls
 * - C-002: Refactored to strategy pattern for better maintainability
 */

// Parameter validation functions (C-001 fix)
export function validateString(value: unknown, name: string): string {
  if (typeof value !== 'string') {
    throw new Error(`Invalid ${name}: expected string, got ${typeof value}`);
  }
  return value;
}

export function validateNumber(value: unknown, name: string, defaultValue?: number): number {
  if (value === undefined && defaultValue !== undefined) {
    return defaultValue;
  }
  if (typeof value !== 'number') {
    throw new Error(`Invalid ${name}: expected number, got ${typeof value}`);
  }
  return value;
}

export function validateStringOptional(value: unknown, name: string, defaultValue: string): string {
  if (value === undefined) {
    return defaultValue;
  }
  return validateString(value, name);
}

export function validateBoolean(value: unknown, name: string, defaultValue: boolean): boolean {
  if (value === undefined) {
    return defaultValue;
  }
  if (typeof value !== 'boolean') {
    throw new Error(`Invalid ${name}: expected boolean, got ${typeof value}`);
  }
  return value;
}

export function validateStringArray(value: unknown, name: string): string[] {
  if (!Array.isArray(value)) {
    throw new Error(`Invalid ${name}: expected array, got ${typeof value}`);
  }
  return value.map((item, index) => {
    if (typeof item !== 'string') {
      throw new Error(`Invalid ${name}[${index}]: expected string, got ${typeof item}`);
    }
    return item;
  });
}

export function formatOutput(stdout: string, stderr: string): string {
  return stderr ? `${stdout}\n[stderr]: ${stderr}` : stdout;
}

// Tool handler type (C-002 fix: Strategy pattern)
export type ToolHandler = (
  args: Record<string, unknown>,
  runScript: (script: string, args: string[]) => Promise<{ stdout: string; stderr: string }>
) => Promise<string>;

// Tool handlers (C-002 fix: Extract handlers from switch statement)
export const handleCiSearch: ToolHandler = async (args, runScript) => {
  const query = validateString(args.query, 'query');
  const limit = validateNumber(args.limit, 'limit', 10);
  // Note: embedding.sh uses --top-k, not --limit, and doesn't have --mode
  const { stdout, stderr } = await runScript("embedding.sh", [
    "search",
    query,
    "--top-k",
    String(limit),
    "--format",
    "text",
  ]);
  return formatOutput(stdout, stderr);
};

export const handleCiCallChain: ToolHandler = async (args, runScript) => {
  const symbol = validateString(args.symbol, 'symbol');
  const direction = validateStringOptional(args.direction, 'direction', 'both');
  const depth = validateNumber(args.depth, 'depth', 3);
  const { stdout, stderr } = await runScript("call-chain.sh", [
    "--symbol",
    symbol,
    "--direction",
    direction,
    "--depth",
    String(depth),
  ]);
  return formatOutput(stdout, stderr);
};

export const handleCiBugLocate: ToolHandler = async (args, runScript) => {
  const error = validateString(args.error, 'error');
  const { stdout, stderr } = await runScript("bug-locator.sh", [
    "--error",
    error,
  ]);
  return formatOutput(stdout, stderr);
};

export const handleCiComplexity: ToolHandler = async (args, runScript) => {
  const path = validateString(args.path, 'path');
  const format = validateStringOptional(args.format, 'format', 'text');
  const { stdout, stderr } = await runScript("complexity.sh", [
    path,
    "--format",
    format,
  ]);
  return formatOutput(stdout, stderr);
};

export const handleCiGraphRag: ToolHandler = async (args, runScript) => {
  const query = validateString(args.query, 'query');
  const depth = validateNumber(args.depth, 'depth', 2);
  const budget = validateNumber(args.budget, 'budget', 8000);
  const { stdout, stderr } = await runScript("graph-rag.sh", [
    "--query",
    query,
    "--depth",
    String(depth),
    "--budget",
    String(budget),
  ]);
  return formatOutput(stdout, stderr);
};

export const handleCiIndexStatus: ToolHandler = async (args, runScript) => {
  const rawAction = args.action as string | undefined;
  const validActions = ["status", "build", "clear"];
  if (rawAction && !validActions.includes(rawAction)) {
    return `Error: Invalid action '${rawAction}'. Valid actions: ${validActions.join(", ")}`;
  }
  const action = rawAction || "status";
  const embeddingAction = action === "clear" ? "clean" : action;
  const { stdout, stderr } = await runScript("embedding.sh", [embeddingAction]);
  return formatOutput(stdout, stderr);
};

export const handleCiHotspot: ToolHandler = async (args, runScript) => {
  const top = validateNumber(args.top, 'top', 20);
  const days = validateNumber(args.days, 'days', 30);
  const format = validateStringOptional(args.format, 'format', 'json');
  const path = validateStringOptional(args.path, 'path', '.');
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
  return formatOutput(stdout, stderr);
};

export const handleCiBoundary: ToolHandler = async (args, runScript) => {
  const file = validateString(args.file, 'file');
  const format = validateStringOptional(args.format, 'format', 'json');
  const { stdout, stderr } = await runScript("boundary-detector.sh", [
    "--format",
    format,
    file,
  ]);
  return formatOutput(stdout, stderr);
};

export const handleCiArchCheck: ToolHandler = async (args, runScript) => {
  // Default to src/ for faster execution (scanning entire project is too slow)
  const path = validateStringOptional(args.path, 'path', 'src/');
  const format = validateStringOptional(args.format, 'format', 'json');
  const rules = args.rules as string | undefined;
  const scriptArgs = ["--all", "--scope", path, "--format", format];
  if (rules) {
    scriptArgs.push("--rules", rules);
  }
  const { stdout, stderr } = await runScript("dependency-guard.sh", scriptArgs);
  return formatOutput(stdout, stderr);
};

export const handleCiFederation: ToolHandler = async (args, runScript) => {
  const action = validateStringOptional(args.action, 'action', 'status');
  const query = args.query as string | undefined;
  const format = validateStringOptional(args.format, 'format', 'json');
  const minConfidence = args.min_confidence as number | undefined;
  const localRepo = args.local_repo as string | undefined;
  const sync = validateBoolean(args.sync, 'sync', false);

  const scriptArgs: string[] = [];
  switch (action) {
    case "status":
      scriptArgs.push("--status");
      break;
    case "update":
      scriptArgs.push("--update");
      break;
    case "search":
      if (!query) {
        return "Error: search action requires query parameter";
      }
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
  return formatOutput(stdout, stderr);
};

export const handleCiGraphStore: ToolHandler = async (args, runScript) => {
  const action = validateString(args.action, 'action');
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
  return formatOutput(stdout, stderr);
};

export const handleCiAstDelta: ToolHandler = async (args, runScript) => {
  const action = validateStringOptional(args.action, 'action', 'status');
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
  return formatOutput(stdout, stderr);
};

export const handleCiImpact: ToolHandler = async (args, runScript) => {
  const symbol = args.symbol as string | undefined;
  const file = args.file as string | undefined;
  const depth = validateNumber(args.depth, 'depth', 3);
  const decay = args.decay as number | undefined;
  const threshold = args.threshold as number | undefined;
  const format = validateStringOptional(args.format, 'format', 'json');

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
  return formatOutput(stdout, stderr);
};

export const handleCiCod: ToolHandler = async (args, runScript) => {
  const action = validateStringOptional(args.action, 'action', 'generate');
  const level = validateNumber(args.level, 'level', 2);
  const module = args.module as string | undefined;
  const format = validateStringOptional(args.format, 'format', 'mermaid');
  const includeHotspots = validateBoolean(args.include_hotspots, 'include_hotspots', true);
  const includeComplexity = validateBoolean(args.include_complexity, 'include_complexity', false);

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
  return formatOutput(stdout, stderr);
};

export const handleCiIntent: ToolHandler = async (args, runScript) => {
  // Note: intent-learner.sh doesn't have a 'stats' command.
  // Available commands: record, get-preferences, cleanup, context, session
  const action = validateStringOptional(args.action, 'action', 'get-preferences');
  const query = args.query as string | undefined;
  const symbols = args.symbols as string[] | undefined;
  const userAction = validateStringOptional(args.user_action, 'user_action', 'view');
  const top = args.top as number | undefined;
  const prefix = args.prefix as string | undefined;
  const days = args.days as number | undefined;

  const scriptArgs: string[] = [];
  switch (action) {
    case "record":
      {
        const symbolIds = symbols ? validateStringArray(symbols, 'symbols') : [];
        const hasSymbols = symbolIds.length > 0;
        const hasQuery = typeof query === 'string' && query.length > 0;

        if (!hasSymbols && !hasQuery) {
          return "Error: record action requires symbols or query parameter";
        }

        const deriveSymbolName = (symbolId: string) => {
          if (symbolId.includes("::")) {
            return symbolId.split("::").pop() || symbolId;
          }
          const parts = symbolId.split("/");
          return parts[parts.length - 1] || symbolId;
        };

        if (hasSymbols) {
          const outputs: string[] = [];
          for (const symbolId of symbolIds) {
            const symbolName = deriveSymbolName(symbolId);
            const { stdout, stderr } = await runScript("intent-learner.sh", [
              "record",
              symbolName,
              symbolId,
              "--action",
              userAction,
            ]);
            outputs.push(formatOutput(stdout, stderr));
          }
          return outputs.filter(Boolean).join("\n");
        }

        const symbolId = query as string;
        const symbolName = deriveSymbolName(symbolId);
        scriptArgs.push("record", symbolName, symbolId, "--action", userAction);
      }
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
    default:
      return `Unknown action: ${action}. Valid actions: record, get-preferences, cleanup`;
  }
  const { stdout, stderr } = await runScript("intent-learner.sh", scriptArgs);
  return formatOutput(stdout, stderr);
};

export const handleCiVuln: ToolHandler = async (args, runScript) => {
  const action = validateStringOptional(args.action, 'action', 'scan');
  const pkg = args.package as string | undefined;
  const severity = validateStringOptional(args.severity, 'severity', 'moderate');
  const format = validateStringOptional(args.format, 'format', 'json');
  const includeDev = validateBoolean(args.include_dev, 'include_dev', false);

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
  return formatOutput(stdout, stderr);
};

export const handleCiAdr: ToolHandler = async (args, runScript) => {
  const action = validateStringOptional(args.action, 'action', 'scan');
  const file = args.file as string | undefined;
  const adrDir = args.adr_dir as string | undefined;
  const link = validateBoolean(args.link, 'link', false);
  const format = validateStringOptional(args.format, 'format', 'json');

  const scriptArgs: string[] = [];
  switch (action) {
    case "scan":
      scriptArgs.push("scan");
      if (adrDir) {
        scriptArgs.push("--adr-dir", adrDir);
      }
      if (link) {
        scriptArgs.push("--link");
      }
      scriptArgs.push("--format", format);
      break;
    case "status":
      scriptArgs.push("status");
      break;
    case "parse":
      if (!file) {
        return "Error: parse action requires file parameter";
      }
      scriptArgs.push("parse", file, "--format", format);
      break;
    case "keywords":
      if (!file) {
        return "Error: keywords action requires file parameter";
      }
      scriptArgs.push("keywords", file);
      break;
    default:
      return `Unknown action: ${action}`;
  }

  const { stdout, stderr } = await runScript("adr-parser.sh", scriptArgs);
  return formatOutput(stdout, stderr);
};

export const handleCiWarmup: ToolHandler = async (args, runScript) => {
  const timeout = args.timeout as number | undefined;
  const hotspotLimit = args.hotspot_limit as number | undefined;
  const queries = args.queries as string | undefined;
  const format = validateStringOptional(args.format, 'format', 'json');
  const runAsync = validateBoolean(args.async, 'async', false);

  const scriptArgs: string[] = ["warmup", "--format", format];
  if (timeout !== undefined) {
    scriptArgs.push("--timeout", String(timeout));
  }
  if (hotspotLimit !== undefined) {
    scriptArgs.push("--hotspot-limit", String(hotspotLimit));
  }
  if (queries) {
    scriptArgs.push("--queries", queries);
  }
  if (runAsync) {
    scriptArgs.push("--async");
  }

  const { stdout, stderr } = await runScript("daemon.sh", scriptArgs);
  return formatOutput(stdout, stderr);
};

export const handleCiContextCompress: ToolHandler = async (args, runScript) => {
  const paths = args.paths as string[] | undefined;
  if (!paths || paths.length === 0) {
    return "Error: paths parameter is required";
  }
  const inputPaths = validateStringArray(paths, 'paths');
  const mode = validateStringOptional(args.mode, 'mode', 'skeleton');
  const compress = validateStringOptional(args.compress, 'compress', 'medium');
  const budget = args.budget as number | undefined;
  const hotspot = args.hotspot as string | undefined;
  const cache = validateBoolean(args.cache, 'cache', false);

  const scriptArgs: string[] = ["--mode", mode, "--compress", compress];
  if (budget !== undefined) {
    scriptArgs.push("--budget", String(budget));
  }
  if (hotspot) {
    scriptArgs.push("--hotspot", hotspot);
  }
  if (cache) {
    scriptArgs.push("--cache");
  }
  scriptArgs.push(...inputPaths);

  const { stdout, stderr } = await runScript("context-compressor.sh", scriptArgs);
  return formatOutput(stdout, stderr);
};

export const handleCiDriftDetect: ToolHandler = async (args, runScript) => {
  const action = validateStringOptional(args.action, 'action', 'compare');
  const baseline = args.baseline as string | undefined;
  const current = args.current as string | undefined;
  const projectDir = args.project_dir as string | undefined;
  const output = args.output as string | undefined;
  const rules = args.rules as string | undefined;
  const period = args.period as string | undefined;
  const snapshotsDir = args.snapshots_dir as string | undefined;
  const c4 = args.c4 as string | undefined;
  const code = args.code as string | undefined;

  const scriptArgs: string[] = [];
  switch (action) {
    case "compare":
      if (!baseline || !current) {
        return "Error: compare action requires baseline and current";
      }
      scriptArgs.push("--compare", baseline, current);
      break;
    case "diff":
      if (!baseline || !current) {
        return "Error: diff action requires baseline and current";
      }
      scriptArgs.push("--diff", baseline, current);
      break;
    case "snapshot":
      if (!projectDir) {
        return "Error: snapshot action requires project_dir";
      }
      if (!output) {
        return "Error: snapshot action requires output";
      }
      scriptArgs.push("--snapshot", projectDir, "--output", output);
      break;
    case "rules":
      if (!rules || !projectDir) {
        return "Error: rules action requires rules and project_dir";
      }
      scriptArgs.push("--rules", rules, projectDir);
      break;
    case "report":
      if (!snapshotsDir) {
        return "Error: report action requires snapshots_dir";
      }
      scriptArgs.push("--report", snapshotsDir);
      if (period) {
        scriptArgs.push("--period", period);
      }
      break;
    case "c4":
      if (!c4 || !code) {
        return "Error: c4 action requires c4 and code";
      }
      scriptArgs.push("--c4", c4, "--code", code);
      break;
    case "parse-c4":
      if (!c4) {
        return "Error: parse-c4 action requires c4";
      }
      scriptArgs.push("--parse-c4", c4);
      break;
    case "scan-code":
      if (!projectDir) {
        return "Error: scan-code action requires project_dir";
      }
      scriptArgs.push("--scan-code", projectDir);
      break;
    default:
      return `Unknown action: ${action}`;
  }

  const { stdout, stderr } = await runScript("drift-detector.sh", scriptArgs);
  return formatOutput(stdout, stderr);
};

export const handleCiSemanticAnomaly: ToolHandler = async (args, runScript) => {
  const path = validateString(args.path, 'path');
  const pattern = args.pattern as string | undefined;
  const output = args.output as string | undefined;
  const threshold = args.threshold as number | undefined;
  const report = validateBoolean(args.report, 'report', false);
  const enableAll = validateBoolean(args.enable_all_features, 'enable_all_features', false);

  const scriptArgs: string[] = [];
  if (pattern) {
    scriptArgs.push("--pattern", pattern);
  }
  if (output) {
    scriptArgs.push("--output", output);
  }
  if (threshold !== undefined) {
    scriptArgs.push("--threshold", String(threshold));
  }
  if (report) {
    scriptArgs.push("--report");
  }
  if (enableAll) {
    scriptArgs.push("--enable-all-features");
  }
  scriptArgs.push(path);

  const { stdout, stderr } = await runScript("semantic-anomaly.sh", scriptArgs);
  return formatOutput(stdout, stderr);
};

export const handleCiBenchmark: ToolHandler = async (args, runScript) => {
  const action = validateStringOptional(args.action, 'action', 'all');
  const dataset = args.dataset as string | undefined;
  const queries = args.queries as string | undefined;
  const output = args.output as string | undefined;
  const baseline = args.baseline as string | undefined;
  const compareBase = args.compare_base as string | undefined;
  const compareCurrent = args.compare_current as string | undefined;
  const iterations = args.iterations as number | undefined;
  const enableAll = validateBoolean(args.enable_all_features, 'enable_all_features', false);

  const scriptArgs: string[] = [];
  switch (action) {
    case "dataset":
      if (!dataset || !queries || !output) {
        return "Error: dataset action requires dataset, queries, and output";
      }
      scriptArgs.push("--dataset", dataset, "--queries", queries, "--output", output);
      if (baseline) {
        scriptArgs.push("--baseline", baseline);
      }
      break;
    case "compare":
      if (!compareBase || !compareCurrent) {
        return "Error: compare action requires compare_base and compare_current";
      }
      scriptArgs.push("--compare", compareBase, compareCurrent);
      break;
    case "cache":
      scriptArgs.push("--cache");
      break;
    case "full":
      scriptArgs.push("--full");
      break;
    case "precommit":
      scriptArgs.push("--precommit");
      break;
    case "all":
      scriptArgs.push("--all");
      break;
    default:
      return `Unknown action: ${action}`;
  }

  if (iterations !== undefined) {
    scriptArgs.push("--iterations", String(iterations));
  }
  if (enableAll) {
    scriptArgs.push("--enable-all-features");
  }

  const { stdout, stderr } = await runScript("benchmark.sh", scriptArgs);
  return formatOutput(stdout, stderr);
};

// Tool handler registry (C-002 fix: Strategy pattern)
export const TOOL_HANDLERS: Record<string, ToolHandler> = {
  ci_search: handleCiSearch,
  ci_call_chain: handleCiCallChain,
  ci_bug_locate: handleCiBugLocate,
  ci_complexity: handleCiComplexity,
  ci_graph_rag: handleCiGraphRag,
  ci_index_status: handleCiIndexStatus,
  ci_hotspot: handleCiHotspot,
  ci_boundary: handleCiBoundary,
  ci_arch_check: handleCiArchCheck,
  ci_federation: handleCiFederation,
  ci_graph_store: handleCiGraphStore,
  ci_ast_delta: handleCiAstDelta,
  ci_impact: handleCiImpact,
  ci_cod: handleCiCod,
  ci_intent: handleCiIntent,
  ci_vuln: handleCiVuln,
  ci_adr: handleCiAdr,
  ci_warmup: handleCiWarmup,
  ci_context_compress: handleCiContextCompress,
  ci_drift_detect: handleCiDriftDetect,
  ci_semantic_anomaly: handleCiSemanticAnomaly,
  ci_benchmark: handleCiBenchmark,
};
