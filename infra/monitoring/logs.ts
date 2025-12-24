#!/usr/bin/env bun
/**
 * Logs MCP Server (Loki)
 *
 * Enables AI agents to query application logs via Loki.
 * Provides tools to:
 * - Search logs by service, level, and content
 * - Tail recent logs
 * - Find errors and exceptions
 * - Trace requests by ID
 * - Analyze log patterns
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ToolSchema,
} from "@modelcontextprotocol/sdk/types.js";

const LOKI_URL = process.env.LOKI_URL || "http://localhost:3100";

// Tool definitions
const tools: ToolSchema[] = [
  {
    name: "search_logs",
    description:
      "Search logs using LogQL queries. Supports filtering by service, level, and content patterns.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "LogQL query (e.g., '{service=\"api\"} |= \"error\"'). If not provided, builds from other params.",
        },
        service: {
          type: "string",
          enum: ["api", "web", "runner", "postgres", "all"],
          description: "Filter by service (default: all)",
        },
        level: {
          type: "string",
          enum: ["error", "warn", "info", "debug", "all"],
          description: "Filter by log level (default: all)",
        },
        contains: {
          type: "string",
          description: "Text to search for in log messages",
        },
        start: {
          type: "string",
          description: "Start time (e.g., '1h', '30m', '2024-01-01T00:00:00Z'). Default: 1h",
        },
        limit: {
          type: "number",
          description: "Max log lines to return (default: 100)",
        },
      },
    },
  },
  {
    name: "tail_logs",
    description:
      "Get the most recent logs from a service. Like 'tail -f' but for distributed logs.",
    inputSchema: {
      type: "object",
      properties: {
        service: {
          type: "string",
          enum: ["api", "web", "runner", "postgres", "all"],
          description: "Service to tail (default: all)",
        },
        lines: {
          type: "number",
          description: "Number of recent lines (default: 50)",
        },
      },
    },
  },
  {
    name: "find_errors",
    description:
      "Find error logs across all services. Returns errors grouped by type and frequency.",
    inputSchema: {
      type: "object",
      properties: {
        start: {
          type: "string",
          description: "How far back to look (e.g., '1h', '6h', '1d'). Default: 1h",
        },
        service: {
          type: "string",
          description: "Optional: filter to specific service",
        },
        limit: {
          type: "number",
          description: "Max errors to return (default: 50)",
        },
      },
    },
  },
  {
    name: "trace_request",
    description:
      "Trace a request through all services using request_id. Shows the full request lifecycle.",
    inputSchema: {
      type: "object",
      properties: {
        request_id: {
          type: "string",
          description: "Request ID to trace (UUID format)",
        },
      },
      required: ["request_id"],
    },
  },
  {
    name: "find_slow_requests",
    description:
      "Find slow HTTP requests based on duration. Useful for performance debugging.",
    inputSchema: {
      type: "object",
      properties: {
        threshold_ms: {
          type: "number",
          description: "Minimum duration in ms (default: 1000)",
        },
        start: {
          type: "string",
          description: "How far back to look (default: 1h)",
        },
        limit: {
          type: "number",
          description: "Max results (default: 20)",
        },
      },
    },
  },
  {
    name: "log_stats",
    description:
      "Get log statistics: volume by service, error rates, top log patterns.",
    inputSchema: {
      type: "object",
      properties: {
        start: {
          type: "string",
          description: "Time range (default: 1h)",
        },
      },
    },
  },
  {
    name: "search_exceptions",
    description:
      "Find stack traces and exceptions in logs. Groups by exception type.",
    inputSchema: {
      type: "object",
      properties: {
        start: {
          type: "string",
          description: "How far back to look (default: 6h)",
        },
        language: {
          type: "string",
          enum: ["zig", "typescript", "python", "all"],
          description: "Filter by language/runtime (default: all)",
        },
      },
    },
  },
  {
    name: "workflow_logs",
    description:
      "Get logs related to workflow execution. Filters by workflow run ID or name.",
    inputSchema: {
      type: "object",
      properties: {
        run_id: {
          type: "number",
          description: "Workflow run ID",
        },
        workflow_name: {
          type: "string",
          description: "Workflow name to search for",
        },
        start: {
          type: "string",
          description: "How far back to look (default: 1h)",
        },
      },
    },
  },
  {
    name: "agent_logs",
    description:
      "Get logs from AI agent executions. Shows LLM calls, tool usage, and agent decisions.",
    inputSchema: {
      type: "object",
      properties: {
        session_id: {
          type: "string",
          description: "Optional: filter by agent session ID",
        },
        start: {
          type: "string",
          description: "How far back to look (default: 1h)",
        },
        limit: {
          type: "number",
          description: "Max lines (default: 200)",
        },
      },
    },
  },
];

// Helper to call Loki API
async function lokiQuery(query: string, start: string, end: string, limit: number): Promise<any> {
  const params = new URLSearchParams({
    query,
    start: parseTime(start),
    end: parseTime(end),
    limit: String(limit),
    direction: "backward",
  });

  const url = `${LOKI_URL}/loki/api/v1/query_range?${params}`;
  const response = await fetch(url);

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Loki API error: ${response.status} - ${text}`);
  }

  const data = await response.json();
  if (data.status !== "success") {
    throw new Error(`Loki query failed: ${data.error || "Unknown error"}`);
  }

  return data.data;
}

// Parse relative time strings to Unix nanoseconds
function parseTime(timeStr: string): string {
  if (!timeStr) {
    return String(Date.now() * 1000000); // Now in nanoseconds
  }

  // Check for relative time
  const match = timeStr.match(/^(\d+)(s|m|h|d)$/);
  if (match) {
    const value = parseInt(match[1]);
    const unit = match[2];
    const multipliers: Record<string, number> = {
      s: 1000,
      m: 60 * 1000,
      h: 60 * 60 * 1000,
      d: 24 * 60 * 60 * 1000,
    };
    const ms = Date.now() - value * multipliers[unit];
    return String(ms * 1000000); // Convert to nanoseconds
  }

  // Try parsing as ISO date
  try {
    const date = new Date(timeStr);
    return String(date.getTime() * 1000000);
  } catch {
    return String(Date.now() * 1000000);
  }
}

// Build LogQL query from parameters
function buildQuery(service?: string, level?: string, contains?: string): string {
  let selector = "";

  if (service && service !== "all") {
    selector = `{service="${service}"}`;
  } else {
    selector = `{service=~".+"}`;
  }

  let query = selector;

  if (level && level !== "all") {
    query += ` | json | level="${level}"`;
  }

  if (contains) {
    // Escape special LogQL characters
    const escaped = contains.replace(/[|=~]/g, "\\$&");
    query += ` |= "${escaped}"`;
  }

  return query;
}

// Format log entries for display
function formatLogs(result: any): string {
  if (!result.result || result.result.length === 0) {
    return "No logs found.";
  }

  const lines: string[] = [];

  for (const stream of result.result) {
    const labels = stream.stream;
    const service = labels.service || labels.container_name || "unknown";

    for (const [timestamp, value] of stream.values) {
      const date = new Date(parseInt(timestamp) / 1000000);
      const time = date.toISOString().replace("T", " ").slice(11, 23);

      // Try to parse JSON log
      let logLine = value;
      let level = "";
      try {
        const parsed = JSON.parse(value);
        level = parsed.level || parsed.severity || "";
        logLine = parsed.msg || parsed.message || value;
      } catch {
        // Not JSON, use raw value
      }

      const levelPrefix = level ? `[${level.toUpperCase().padEnd(5)}]` : "";
      lines.push(`${time} [${service}] ${levelPrefix} ${logLine}`);
    }
  }

  return lines.join("\n");
}

// Tool handlers
async function handleTool(name: string, args: Record<string, unknown>): Promise<string> {
  switch (name) {
    case "search_logs": {
      const query = args.query as string || buildQuery(
        args.service as string,
        args.level as string,
        args.contains as string
      );
      const start = (args.start as string) || "1h";
      const limit = (args.limit as number) || 100;

      try {
        const result = await lokiQuery(query, start, "now", limit);
        const formatted = formatLogs(result);

        return `Log Search Results (query: ${query})
${"=".repeat(50)}

${formatted}`;
      } catch (error) {
        return `Failed to query logs: ${error}`;
      }
    }

    case "tail_logs": {
      const service = (args.service as string) || "all";
      const lines = (args.lines as number) || 50;

      const query = service === "all"
        ? `{service=~".+"}`
        : `{service="${service}"}`;

      try {
        const result = await lokiQuery(query, "5m", "now", lines);
        const formatted = formatLogs(result);

        return `Recent Logs (${service})
${"=".repeat(50)}

${formatted}`;
      } catch (error) {
        return `Failed to tail logs: ${error}`;
      }
    }

    case "find_errors": {
      const start = (args.start as string) || "1h";
      const service = args.service as string;
      const limit = (args.limit as number) || 50;

      let query = service
        ? `{service="${service}"} |~ "(?i)(error|exception|panic|fatal)"`
        : `{service=~".+"} |~ "(?i)(error|exception|panic|fatal)"`;

      try {
        const result = await lokiQuery(query, start, "now", limit);
        const formatted = formatLogs(result);

        // Count error types
        const errorCounts = new Map<string, number>();
        if (result.result) {
          for (const stream of result.result) {
            for (const [_, value] of stream.values) {
              // Extract error type
              const match = value.match(/(?:error|Error|ERROR|exception|Exception|panic)[:=\s]+([^\n]+)/);
              if (match) {
                const errorType = match[1].slice(0, 80);
                errorCounts.set(errorType, (errorCounts.get(errorType) || 0) + 1);
              }
            }
          }
        }

        let summary = "";
        if (errorCounts.size > 0) {
          summary = "\nError Types:\n";
          const sorted = [...errorCounts.entries()].sort((a, b) => b[1] - a[1]);
          for (const [type, count] of sorted.slice(0, 10)) {
            summary += `  [${count}x] ${type}\n`;
          }
        }

        return `Error Logs (last ${start})
${"=".repeat(50)}
${summary}
Detailed Logs:
${formatted}`;
      } catch (error) {
        return `Failed to find errors: ${error}`;
      }
    }

    case "trace_request": {
      const requestId = args.request_id as string;

      if (!requestId) {
        return "request_id is required";
      }

      const query = `{service=~".+"} |= "${requestId}"`;

      try {
        const result = await lokiQuery(query, "24h", "now", 500);
        const formatted = formatLogs(result);

        const logCount = result.result?.reduce(
          (sum: number, s: any) => sum + s.values.length, 0
        ) || 0;

        return `Request Trace: ${requestId}
${"=".repeat(50)}
Found ${logCount} log entries

${formatted}`;
      } catch (error) {
        return `Failed to trace request: ${error}`;
      }
    }

    case "find_slow_requests": {
      const threshold = (args.threshold_ms as number) || 1000;
      const start = (args.start as string) || "1h";
      const limit = (args.limit as number) || 20;

      // Look for duration_ms in structured logs
      const query = `{service="api"} | json | duration_ms > ${threshold}`;

      try {
        const result = await lokiQuery(query, start, "now", limit);
        const formatted = formatLogs(result);

        return `Slow Requests (>${threshold}ms)
${"=".repeat(50)}

${formatted}`;
      } catch (error) {
        // Fallback to text search
        const fallbackQuery = `{service="api"} |~ "duration.*[0-9]{4,}"`;
        try {
          const result = await lokiQuery(fallbackQuery, start, "now", limit);
          const formatted = formatLogs(result);
          return `Slow Requests (pattern match)
${"=".repeat(50)}

${formatted}`;
        } catch (err) {
          return `Failed to find slow requests: ${error}`;
        }
      }
    }

    case "log_stats": {
      const start = (args.start as string) || "1h";

      try {
        // Query for total log volume by service
        const volumeQuery = `sum by (service) (count_over_time({service=~".+"}[${start}]))`;
        const volumeUrl = `${LOKI_URL}/loki/api/v1/query?query=${encodeURIComponent(volumeQuery)}`;
        const volumeResp = await fetch(volumeUrl);
        const volumeData = await volumeResp.json();

        let result = `Log Statistics (last ${start})
${"=".repeat(50)}

Volume by Service:
`;

        if (volumeData.data?.result) {
          for (const item of volumeData.data.result) {
            const service = item.metric.service || "unknown";
            const count = parseInt(item.value[1]);
            result += `  ${service}: ${count.toLocaleString()} lines\n`;
          }
        }

        // Query for error count by service
        const errorQuery = `sum by (service) (count_over_time({service=~".+"} |~ "(?i)error" [${start}]))`;
        const errorUrl = `${LOKI_URL}/loki/api/v1/query?query=${encodeURIComponent(errorQuery)}`;
        const errorResp = await fetch(errorUrl);
        const errorData = await errorResp.json();

        result += "\nErrors by Service:\n";
        if (errorData.data?.result) {
          for (const item of errorData.data.result) {
            const service = item.metric.service || "unknown";
            const count = parseInt(item.value[1]);
            result += `  ${service}: ${count} errors\n`;
          }
        }

        return result;
      } catch (error) {
        return `Failed to get log stats: ${error}`;
      }
    }

    case "search_exceptions": {
      const start = (args.start as string) || "6h";
      const language = args.language as string;

      let query = `{service=~".+"} |~ "(?i)(exception|panic|traceback|stack trace)"`;

      if (language === "zig") {
        query = `{service=~".+"} |~ "(panic|error\\.)"`;
      } else if (language === "typescript") {
        query = `{service=~".+"} |~ "(Error:|at .+\\.ts:)"`;
      } else if (language === "python") {
        query = `{service=~".+"} |~ "(Traceback|Exception:)"`;
      }

      try {
        const result = await lokiQuery(query, start, "now", 100);
        const formatted = formatLogs(result);

        return `Exceptions (last ${start})
${"=".repeat(50)}

${formatted}`;
      } catch (error) {
        return `Failed to search exceptions: ${error}`;
      }
    }

    case "workflow_logs": {
      const runId = args.run_id as number;
      const workflowName = args.workflow_name as string;
      const start = (args.start as string) || "1h";

      let query: string;
      if (runId) {
        query = `{service=~".+"} |= "run_id=${runId}" or |= "run_id\\":\\"${runId}"`;
      } else if (workflowName) {
        query = `{service=~".+"} |= "${workflowName}"`;
      } else {
        query = `{service=~".+"} |= "workflow"`;
      }

      try {
        const result = await lokiQuery(query, start, "now", 500);
        const formatted = formatLogs(result);

        return `Workflow Logs
${"=".repeat(50)}
${runId ? `Run ID: ${runId}` : workflowName ? `Workflow: ${workflowName}` : "All workflows"}

${formatted}`;
      } catch (error) {
        return `Failed to get workflow logs: ${error}`;
      }
    }

    case "agent_logs": {
      const sessionId = args.session_id as string;
      const start = (args.start as string) || "1h";
      const limit = (args.limit as number) || 200;

      let query = `{service=~".+"} |~ "(?i)(agent|llm|claude|tool_call|tool_result)"`;
      if (sessionId) {
        query = `{service=~".+"} |= "${sessionId}"`;
      }

      try {
        const result = await lokiQuery(query, start, "now", limit);
        const formatted = formatLogs(result);

        return `Agent Logs
${"=".repeat(50)}
${sessionId ? `Session: ${sessionId}` : "All agent activity"}

${formatted}`;
      } catch (error) {
        return `Failed to get agent logs: ${error}`;
      }
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// Main server setup
const server = new Server(
  {
    name: "logs-mcp",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Register handlers
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    const result = await handleTool(name, args || {});
    return {
      content: [{ type: "text", text: result }],
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      content: [{ type: "text", text: `Error: ${message}` }],
      isError: true,
    };
  }
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Logs MCP server started");
}

main().catch(console.error);
