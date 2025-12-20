#!/usr/bin/env bun
/**
 * Prometheus MCP Server
 *
 * Enables AI agents to query Prometheus metrics for debugging and observability.
 * Provides tools to:
 * - Query instant metrics
 * - Query range metrics over time
 * - List available metrics
 * - Get service health status
 * - Analyze error patterns
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ToolSchema,
} from "@modelcontextprotocol/sdk/types.js";

const PROMETHEUS_URL = process.env.PROMETHEUS_URL || "http://localhost:9090";

// Tool definitions
const tools: ToolSchema[] = [
  {
    name: "prometheus_query",
    description:
      "Execute an instant PromQL query. Returns the current value of metrics. Use this for point-in-time queries like 'up' or 'rate(http_requests_total[5m])'.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "PromQL query expression",
        },
        time: {
          type: "string",
          description:
            "Evaluation timestamp (RFC3339 or Unix timestamp). Defaults to now.",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "prometheus_query_range",
    description:
      "Execute a range query over a time period. Returns metrics values over time. Useful for analyzing trends, patterns, and historical data.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "PromQL query expression",
        },
        start: {
          type: "string",
          description:
            "Start timestamp (RFC3339 or Unix). Can also use relative times like '1h' for 1 hour ago.",
        },
        end: {
          type: "string",
          description: "End timestamp (RFC3339 or Unix). Defaults to now.",
        },
        step: {
          type: "string",
          description: "Query resolution step (e.g., '15s', '1m'). Defaults to 1m.",
        },
      },
      required: ["query", "start"],
    },
  },
  {
    name: "prometheus_series",
    description:
      "List all time series matching a label selector. Use this to discover what metrics exist.",
    inputSchema: {
      type: "object",
      properties: {
        match: {
          type: "array",
          items: { type: "string" },
          description: "Label matchers (e.g., ['up', 'plue_http_requests_total'])",
        },
        start: {
          type: "string",
          description: "Start timestamp for the range to search",
        },
        end: {
          type: "string",
          description: "End timestamp for the range to search",
        },
      },
      required: ["match"],
    },
  },
  {
    name: "prometheus_labels",
    description:
      "List all label names or values. Use to discover available labels for filtering.",
    inputSchema: {
      type: "object",
      properties: {
        label: {
          type: "string",
          description:
            "Label name to get values for. If not provided, returns all label names.",
        },
        match: {
          type: "array",
          items: { type: "string" },
          description: "Optional series selectors to filter",
        },
      },
    },
  },
  {
    name: "prometheus_targets",
    description:
      "Get information about Prometheus scrape targets. Shows which services are being monitored and their health status.",
    inputSchema: {
      type: "object",
      properties: {
        state: {
          type: "string",
          enum: ["active", "dropped", "any"],
          description: "Filter by target state. Defaults to 'active'.",
        },
      },
    },
  },
  {
    name: "prometheus_alerts",
    description:
      "Get current alerts from Prometheus. Shows firing and pending alerts.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "service_health",
    description:
      "Get a quick health summary of all Plue services. Returns UP/DOWN status for each monitored service.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "error_analysis",
    description:
      "Analyze recent errors across all services. Returns error rates, top error paths, and patterns.",
    inputSchema: {
      type: "object",
      properties: {
        duration: {
          type: "string",
          description: "Time window to analyze (e.g., '5m', '1h'). Defaults to '15m'.",
        },
      },
    },
  },
  {
    name: "latency_analysis",
    description:
      "Analyze request latency across services. Returns p50, p95, p99 latencies by endpoint.",
    inputSchema: {
      type: "object",
      properties: {
        duration: {
          type: "string",
          description: "Time window to analyze (e.g., '5m', '1h'). Defaults to '15m'.",
        },
      },
    },
  },
];

// Helper to call Prometheus API
async function prometheusApi(endpoint: string, params: Record<string, string> = {}) {
  const url = new URL(`${PROMETHEUS_URL}/api/v1/${endpoint}`);
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined) {
      url.searchParams.set(key, value);
    }
  });

  const response = await fetch(url.toString());
  if (!response.ok) {
    throw new Error(`Prometheus API error: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  if (data.status !== "success") {
    throw new Error(`Prometheus query failed: ${data.error || "Unknown error"}`);
  }

  return data.data;
}

// Parse relative time strings
function parseRelativeTime(timeStr: string): string {
  if (!timeStr) return "";

  // Check if it's already an absolute time
  if (timeStr.includes("T") || /^\d{10,}$/.test(timeStr)) {
    return timeStr;
  }

  // Parse relative times like '1h', '30m', '1d'
  const match = timeStr.match(/^(\d+)(s|m|h|d)$/);
  if (match) {
    const value = parseInt(match[1]);
    const unit = match[2];
    const multipliers: Record<string, number> = {
      s: 1,
      m: 60,
      h: 3600,
      d: 86400,
    };
    const seconds = value * multipliers[unit];
    return String(Math.floor(Date.now() / 1000) - seconds);
  }

  return timeStr;
}

// Tool handlers
async function handleTool(name: string, args: Record<string, unknown>) {
  switch (name) {
    case "prometheus_query": {
      const { query, time } = args as { query: string; time?: string };
      const params: Record<string, string> = { query };
      if (time) params.time = time;
      const result = await prometheusApi("query", params);
      return formatQueryResult(result);
    }

    case "prometheus_query_range": {
      const { query, start, end, step } = args as {
        query: string;
        start: string;
        end?: string;
        step?: string;
      };
      const params: Record<string, string> = {
        query,
        start: parseRelativeTime(start),
        end: end ? parseRelativeTime(end) : String(Math.floor(Date.now() / 1000)),
        step: step || "1m",
      };
      const result = await prometheusApi("query_range", params);
      return formatRangeResult(result);
    }

    case "prometheus_series": {
      const { match, start, end } = args as {
        match: string[];
        start?: string;
        end?: string;
      };
      const params: Record<string, string> = {};
      match.forEach((m, i) => (params[`match[]`] = m));
      if (start) params.start = parseRelativeTime(start);
      if (end) params.end = parseRelativeTime(end);

      // Build URL manually for array params
      const url = new URL(`${PROMETHEUS_URL}/api/v1/series`);
      match.forEach((m) => url.searchParams.append("match[]", m));
      if (start) url.searchParams.set("start", parseRelativeTime(start));
      if (end) url.searchParams.set("end", parseRelativeTime(end));

      const response = await fetch(url.toString());
      const data = await response.json();
      return formatSeriesResult(data.data);
    }

    case "prometheus_labels": {
      const { label, match } = args as { label?: string; match?: string[] };
      if (label) {
        const data = await prometheusApi(`label/${label}/values`);
        return `Label "${label}" values:\n${data.join("\n")}`;
      } else {
        const data = await prometheusApi("labels");
        return `Available labels:\n${data.join("\n")}`;
      }
    }

    case "prometheus_targets": {
      const { state } = args as { state?: string };
      const data = await prometheusApi("targets", { state: state || "active" });
      return formatTargetsResult(data);
    }

    case "prometheus_alerts": {
      const data = await prometheusApi("alerts");
      return formatAlertsResult(data);
    }

    case "service_health": {
      return await getServiceHealth();
    }

    case "error_analysis": {
      const { duration } = args as { duration?: string };
      return await analyzeErrors(duration || "15m");
    }

    case "latency_analysis": {
      const { duration } = args as { duration?: string };
      return await analyzeLatency(duration || "15m");
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// Format helpers
function formatQueryResult(result: { resultType: string; result: unknown[] }) {
  if (result.resultType === "vector") {
    const vectors = result.result as Array<{
      metric: Record<string, string>;
      value: [number, string];
    }>;
    if (vectors.length === 0) return "No data";

    return vectors
      .map((v) => {
        const labels = Object.entries(v.metric)
          .map(([k, val]) => `${k}="${val}"`)
          .join(", ");
        return `{${labels}} => ${v.value[1]}`;
      })
      .join("\n");
  }

  if (result.resultType === "scalar") {
    const [timestamp, value] = result.result as [number, string];
    return `Scalar: ${value} (at ${new Date(timestamp * 1000).toISOString()})`;
  }

  return JSON.stringify(result.result, null, 2);
}

function formatRangeResult(result: { resultType: string; result: unknown[] }) {
  const series = result.result as Array<{
    metric: Record<string, string>;
    values: Array<[number, string]>;
  }>;

  if (series.length === 0) return "No data";

  return series
    .map((s) => {
      const labels = Object.entries(s.metric)
        .map(([k, v]) => `${k}="${v}"`)
        .join(", ");

      const values = s.values
        .slice(-10) // Show last 10 data points
        .map(([ts, val]) => `  ${new Date(ts * 1000).toISOString()}: ${val}`)
        .join("\n");

      return `{${labels}}:\n${values}${s.values.length > 10 ? `\n  ... (${s.values.length - 10} more points)` : ""}`;
    })
    .join("\n\n");
}

function formatSeriesResult(series: Array<Record<string, string>>) {
  if (series.length === 0) return "No series found";

  return series
    .slice(0, 50) // Limit to 50 series
    .map((s) => {
      const labels = Object.entries(s)
        .map(([k, v]) => `${k}="${v}"`)
        .join(", ");
      return `{${labels}}`;
    })
    .join("\n");
}

function formatTargetsResult(data: { activeTargets: unknown[]; droppedTargets: unknown[] }) {
  const active = data.activeTargets as Array<{
    labels: Record<string, string>;
    scrapeUrl: string;
    health: string;
    lastError: string;
    lastScrape: string;
  }>;

  if (active.length === 0) return "No active targets";

  return active
    .map((t) => {
      const job = t.labels.job || "unknown";
      const instance = t.labels.instance || t.scrapeUrl;
      const health = t.health === "up" ? "UP" : "DOWN";
      const error = t.lastError ? `\n    Error: ${t.lastError}` : "";
      return `[${health}] ${job} (${instance})${error}`;
    })
    .join("\n");
}

function formatAlertsResult(data: { alerts: unknown[] }) {
  const alerts = data.alerts as Array<{
    labels: Record<string, string>;
    annotations: Record<string, string>;
    state: string;
    activeAt: string;
    value: string;
  }>;

  if (alerts.length === 0) return "No alerts";

  return alerts
    .map((a) => {
      const name = a.labels.alertname || "Unknown";
      const state = a.state.toUpperCase();
      const summary = a.annotations.summary || a.annotations.description || "";
      return `[${state}] ${name}: ${summary}`;
    })
    .join("\n");
}

// High-level analysis functions
async function getServiceHealth(): Promise<string> {
  try {
    const result = await prometheusApi("query", { query: "up" });
    const vectors = result.result as Array<{
      metric: Record<string, string>;
      value: [number, string];
    }>;

    if (vectors.length === 0) {
      return "No services found. Is Prometheus scraping targets?";
    }

    const services = vectors.map((v) => {
      const job = v.metric.job || "unknown";
      const instance = v.metric.instance || "";
      const isUp = v.value[1] === "1";
      return `[${isUp ? "UP" : "DOWN"}] ${job} (${instance})`;
    });

    const upCount = vectors.filter((v) => v.value[1] === "1").length;
    const summary = `\nSummary: ${upCount}/${vectors.length} services healthy`;

    return services.join("\n") + summary;
  } catch (error) {
    return `Failed to get service health: ${error}`;
  }
}

async function analyzeErrors(duration: string): Promise<string> {
  try {
    const results: string[] = [];

    // Total error rate
    const errorRateQuery = `sum(rate(plue_http_requests_total{status=~"5.."}[${duration}]))`;
    const errorRateResult = await prometheusApi("query", { query: errorRateQuery });

    const errorRate = parseFloat(
      (errorRateResult.result[0]?.value?.[1] as string) || "0"
    );
    results.push(`Error Rate: ${(errorRate * 60).toFixed(2)} errors/min`);

    // Errors by path
    const errorsByPathQuery = `topk(10, sum by (path, method) (increase(plue_http_requests_total{status=~"5.."}[${duration}])))`;
    const errorsByPath = await prometheusApi("query", { query: errorsByPathQuery });

    if (errorsByPath.result.length > 0) {
      results.push("\nTop Error Endpoints:");
      (errorsByPath.result as Array<{ metric: Record<string, string>; value: [number, string] }>)
        .forEach((r) => {
          const count = parseFloat(r.value[1]);
          if (count > 0) {
            results.push(
              `  ${r.metric.method} ${r.metric.path}: ${count.toFixed(0)} errors`
            );
          }
        });
    }

    // 4xx errors
    const clientErrorQuery = `sum(rate(plue_http_requests_total{status=~"4.."}[${duration}]))`;
    const clientErrorResult = await prometheusApi("query", { query: clientErrorQuery });
    const clientErrorRate = parseFloat(
      (clientErrorResult.result[0]?.value?.[1] as string) || "0"
    );
    results.push(`\nClient Error Rate (4xx): ${(clientErrorRate * 60).toFixed(2)} errors/min`);

    // Auth failures
    const authFailQuery = `sum(increase(plue_auth_attempts_total{result!="success"}[${duration}]))`;
    try {
      const authFailResult = await prometheusApi("query", { query: authFailQuery });
      const authFails = parseFloat(
        (authFailResult.result[0]?.value?.[1] as string) || "0"
      );
      if (authFails > 0) {
        results.push(`Auth Failures: ${authFails.toFixed(0)}`);
      }
    } catch {
      // Auth metrics may not exist yet
    }

    return results.join("\n") || "No error data available";
  } catch (error) {
    return `Failed to analyze errors: ${error}`;
  }
}

async function analyzeLatency(duration: string): Promise<string> {
  try {
    const results: string[] = [];

    // P50 latency
    const p50Query = `histogram_quantile(0.50, sum by (le) (rate(plue_http_request_duration_ms_bucket[${duration}])))`;
    const p50Result = await prometheusApi("query", { query: p50Query });
    const p50 = parseFloat((p50Result.result[0]?.value?.[1] as string) || "0");

    // P95 latency
    const p95Query = `histogram_quantile(0.95, sum by (le) (rate(plue_http_request_duration_ms_bucket[${duration}])))`;
    const p95Result = await prometheusApi("query", { query: p95Query });
    const p95 = parseFloat((p95Result.result[0]?.value?.[1] as string) || "0");

    // P99 latency
    const p99Query = `histogram_quantile(0.99, sum by (le) (rate(plue_http_request_duration_ms_bucket[${duration}])))`;
    const p99Result = await prometheusApi("query", { query: p99Query });
    const p99 = parseFloat((p99Result.result[0]?.value?.[1] as string) || "0");

    results.push("Overall Latency:");
    results.push(`  P50: ${p50.toFixed(2)}ms`);
    results.push(`  P95: ${p95.toFixed(2)}ms`);
    results.push(`  P99: ${p99.toFixed(2)}ms`);

    // Request rate
    const rpsQuery = `sum(rate(plue_http_requests_total[${duration}]))`;
    const rpsResult = await prometheusApi("query", { query: rpsQuery });
    const rps = parseFloat((rpsResult.result[0]?.value?.[1] as string) || "0");
    results.push(`\nRequest Rate: ${rps.toFixed(2)} req/s`);

    // Slowest endpoints
    const slowQuery = `topk(5, histogram_quantile(0.95, sum by (path, le) (rate(plue_http_request_duration_ms_bucket[${duration}]))))`;
    try {
      const slowResult = await prometheusApi("query", { query: slowQuery });
      if (slowResult.result.length > 0) {
        results.push("\nSlowest Endpoints (P95):");
        (slowResult.result as Array<{ metric: Record<string, string>; value: [number, string] }>)
          .filter((r) => parseFloat(r.value[1]) > 0)
          .forEach((r) => {
            results.push(`  ${r.metric.path}: ${parseFloat(r.value[1]).toFixed(2)}ms`);
          });
      }
    } catch {
      // May not have enough data points
    }

    return results.join("\n") || "No latency data available";
  } catch (error) {
    return `Failed to analyze latency: ${error}`;
  }
}

// Main server setup
const server = new Server(
  {
    name: "prometheus-mcp",
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
  console.error("Prometheus MCP server started");
}

main().catch(console.error);
