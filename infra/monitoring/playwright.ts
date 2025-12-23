#!/usr/bin/env bun
/**
 * Playwright MCP Server
 *
 * Enables AI agents to analyze Playwright test results for debugging.
 * Provides tools to:
 * - Get test run summary
 * - List failed tests
 * - Get test details including traces, screenshots, logs
 * - Analyze failure patterns
 * - View console/network logs from failed tests
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ToolSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, existsSync, readdirSync, statSync } from "fs";
import { join, basename } from "path";

// Configurable paths
const PROJECT_ROOT = process.env.PROJECT_ROOT || process.cwd();
const RESULTS_PATH = join(PROJECT_ROOT, "test-results");
const REPORT_PATH = join(PROJECT_ROOT, "playwright-report");
const RESULTS_JSON = join(RESULTS_PATH, "results.json");

// Types for Playwright JSON report
interface TestResult {
  title: string;
  fullTitle: string;
  file: string;
  line: number;
  column: number;
  status: "passed" | "failed" | "timedOut" | "skipped";
  duration: number;
  errors: Array<{ message: string; stack?: string }>;
  attachments: Array<{
    name: string;
    path?: string;
    contentType: string;
    body?: string;
  }>;
  retry: number;
}

interface TestSuite {
  title: string;
  file: string;
  tests: TestResult[];
  suites: TestSuite[];
}

interface PlaywrightReport {
  config: {
    rootDir: string;
    testDir: string;
  };
  suites: TestSuite[];
  stats: {
    startTime: string;
    duration: number;
    expected: number;
    unexpected: number;
    flaky: number;
    skipped: number;
  };
}

// Tool definitions
const tools: ToolSchema[] = [
  {
    name: "test_summary",
    description:
      "Get a summary of the latest test run including pass/fail counts, duration, and flaky tests.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "list_failures",
    description:
      "List all failed tests from the latest run with error messages. Use this to see what tests need attention.",
    inputSchema: {
      type: "object",
      properties: {
        limit: {
          type: "number",
          description: "Maximum number of failures to return (default: 20)",
        },
      },
    },
  },
  {
    name: "test_details",
    description:
      "Get detailed information about a specific test including errors, attachments, console logs, and network logs.",
    inputSchema: {
      type: "object",
      properties: {
        testTitle: {
          type: "string",
          description: "Full or partial test title to search for",
        },
      },
      required: ["testTitle"],
    },
  },
  {
    name: "view_attachment",
    description:
      "View the contents of a test attachment (console-logs, network-errors, etc.)",
    inputSchema: {
      type: "object",
      properties: {
        attachmentPath: {
          type: "string",
          description: "Path to the attachment file",
        },
      },
      required: ["attachmentPath"],
    },
  },
  {
    name: "failure_patterns",
    description:
      "Analyze failure patterns across tests. Groups failures by error message to identify common issues.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "flaky_tests",
    description:
      "List tests that are flaky (passed on retry). These may indicate timing issues or race conditions.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "slow_tests",
    description:
      "List the slowest tests. Useful for identifying performance bottlenecks.",
    inputSchema: {
      type: "object",
      properties: {
        limit: {
          type: "number",
          description: "Number of tests to return (default: 10)",
        },
        threshold: {
          type: "number",
          description: "Only show tests slower than this threshold in ms (default: 5000)",
        },
      },
    },
  },
  {
    name: "test_artifacts",
    description:
      "List available artifacts (traces, screenshots, videos) for failed tests.",
    inputSchema: {
      type: "object",
      properties: {
        testTitle: {
          type: "string",
          description: "Optional: filter by test title",
        },
      },
    },
  },
  {
    name: "list_test_files",
    description: "List all test files in the e2e directory with test counts.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
];

// Helper to load test results
function loadResults(): PlaywrightReport | null {
  if (!existsSync(RESULTS_JSON)) {
    return null;
  }
  try {
    const content = readFileSync(RESULTS_JSON, "utf-8");
    return JSON.parse(content);
  } catch (error) {
    return null;
  }
}

// Helper to flatten test suites
function flattenTests(suites: TestSuite[]): TestResult[] {
  const tests: TestResult[] = [];
  for (const suite of suites) {
    tests.push(...suite.tests);
    if (suite.suites) {
      tests.push(...flattenTests(suite.suites));
    }
  }
  return tests;
}

// Tool handlers
async function handleTool(name: string, args: Record<string, unknown>) {
  switch (name) {
    case "test_summary": {
      const report = loadResults();
      if (!report) {
        return "No test results found. Run `bun playwright test` first.";
      }

      const tests = flattenTests(report.suites);
      const passed = tests.filter((t) => t.status === "passed").length;
      const failed = tests.filter((t) => t.status === "failed").length;
      const skipped = tests.filter((t) => t.status === "skipped").length;
      const timedOut = tests.filter((t) => t.status === "timedOut").length;
      const flaky = tests.filter((t) => t.retry > 0 && t.status === "passed").length;

      const duration = report.stats?.duration || tests.reduce((sum, t) => sum + t.duration, 0);
      const durationStr = duration > 60000
        ? `${(duration / 60000).toFixed(1)}m`
        : `${(duration / 1000).toFixed(1)}s`;

      return `Test Run Summary
================
Total:    ${tests.length} tests
Passed:   ${passed} (${((passed / tests.length) * 100).toFixed(1)}%)
Failed:   ${failed}
Timed Out: ${timedOut}
Skipped:  ${skipped}
Flaky:    ${flaky}

Duration: ${durationStr}
Status:   ${failed + timedOut === 0 ? "PASSED" : "FAILED"}`;
    }

    case "list_failures": {
      const report = loadResults();
      if (!report) {
        return "No test results found. Run `bun playwright test` first.";
      }

      const limit = (args.limit as number) || 20;
      const tests = flattenTests(report.suites);
      const failures = tests.filter(
        (t) => t.status === "failed" || t.status === "timedOut"
      );

      if (failures.length === 0) {
        return "No failures! All tests passed.";
      }

      const lines = failures.slice(0, limit).map((t, i) => {
        const error = t.errors[0]?.message?.split("\n")[0] || "Unknown error";
        const shortError = error.length > 100 ? error.slice(0, 100) + "..." : error;
        return `${i + 1}. [${t.status.toUpperCase()}] ${t.fullTitle}
   File: ${t.file}:${t.line}
   Error: ${shortError}
   Duration: ${t.duration}ms`;
      });

      return `Failed Tests (${failures.length} total, showing ${Math.min(failures.length, limit)})\n${"=".repeat(50)}\n\n${lines.join("\n\n")}`;
    }

    case "test_details": {
      const report = loadResults();
      if (!report) {
        return "No test results found. Run `bun playwright test` first.";
      }

      const testTitle = args.testTitle as string;
      const tests = flattenTests(report.suites);
      const test = tests.find(
        (t) =>
          t.fullTitle.toLowerCase().includes(testTitle.toLowerCase()) ||
          t.title.toLowerCase().includes(testTitle.toLowerCase())
      );

      if (!test) {
        return `No test found matching "${testTitle}"`;
      }

      let result = `Test Details: ${test.fullTitle}
${"=".repeat(50)}
Status:   ${test.status.toUpperCase()}
File:     ${test.file}:${test.line}
Duration: ${test.duration}ms
Retry:    ${test.retry}`;

      if (test.errors.length > 0) {
        result += "\n\nErrors:\n" + test.errors.map((e) => e.message).join("\n---\n");
      }

      if (test.attachments.length > 0) {
        result += "\n\nAttachments:";
        for (const att of test.attachments) {
          result += `\n- ${att.name} (${att.contentType})`;
          if (att.path) {
            result += `: ${att.path}`;
          }
        }
      }

      return result;
    }

    case "view_attachment": {
      const attachmentPath = args.attachmentPath as string;
      const fullPath = attachmentPath.startsWith("/")
        ? attachmentPath
        : join(PROJECT_ROOT, attachmentPath);

      if (!existsSync(fullPath)) {
        return `Attachment not found: ${fullPath}`;
      }

      try {
        const content = readFileSync(fullPath, "utf-8");
        // Try to parse as JSON for better formatting
        try {
          const json = JSON.parse(content);
          return JSON.stringify(json, null, 2);
        } catch {
          return content;
        }
      } catch (error) {
        return `Error reading attachment: ${error}`;
      }
    }

    case "failure_patterns": {
      const report = loadResults();
      if (!report) {
        return "No test results found. Run `bun playwright test` first.";
      }

      const tests = flattenTests(report.suites);
      const failures = tests.filter(
        (t) => t.status === "failed" || t.status === "timedOut"
      );

      if (failures.length === 0) {
        return "No failures to analyze!";
      }

      // Group by error message pattern
      const patterns = new Map<string, TestResult[]>();
      for (const test of failures) {
        const error = test.errors[0]?.message?.split("\n")[0] || "Unknown error";
        // Normalize error message (remove specific values)
        const pattern = error
          .replace(/\d+/g, "N")
          .replace(/"[^"]*"/g, '"..."')
          .slice(0, 100);

        if (!patterns.has(pattern)) {
          patterns.set(pattern, []);
        }
        patterns.get(pattern)!.push(test);
      }

      // Sort by frequency
      const sorted = [...patterns.entries()].sort((a, b) => b[1].length - a[1].length);

      const lines = sorted.map(([pattern, tests]) => {
        const testNames = tests.slice(0, 3).map((t) => `  - ${t.title}`).join("\n");
        const more = tests.length > 3 ? `\n  ... and ${tests.length - 3} more` : "";
        return `Pattern: ${pattern}\nCount: ${tests.length}\nAffected tests:\n${testNames}${more}`;
      });

      return `Failure Patterns Analysis\n${"=".repeat(50)}\n\n${lines.join("\n\n")}`;
    }

    case "flaky_tests": {
      const report = loadResults();
      if (!report) {
        return "No test results found. Run `bun playwright test` first.";
      }

      const tests = flattenTests(report.suites);
      const flaky = tests.filter((t) => t.retry > 0 && t.status === "passed");

      if (flaky.length === 0) {
        return "No flaky tests detected.";
      }

      const lines = flaky.map((t) => {
        return `- ${t.fullTitle}\n  File: ${t.file}:${t.line}\n  Retries: ${t.retry}`;
      });

      return `Flaky Tests (${flaky.length})\n${"=".repeat(50)}\n\n${lines.join("\n\n")}`;
    }

    case "slow_tests": {
      const report = loadResults();
      if (!report) {
        return "No test results found. Run `bun playwright test` first.";
      }

      const limit = (args.limit as number) || 10;
      const threshold = (args.threshold as number) || 5000;

      const tests = flattenTests(report.suites);
      const slow = tests
        .filter((t) => t.duration > threshold)
        .sort((a, b) => b.duration - a.duration)
        .slice(0, limit);

      if (slow.length === 0) {
        return `No tests slower than ${threshold}ms.`;
      }

      const lines = slow.map((t, i) => {
        const duration =
          t.duration > 60000
            ? `${(t.duration / 60000).toFixed(1)}m`
            : `${(t.duration / 1000).toFixed(1)}s`;
        return `${i + 1}. ${t.fullTitle}\n   Duration: ${duration}\n   File: ${t.file}:${t.line}`;
      });

      return `Slowest Tests (threshold: ${threshold}ms)\n${"=".repeat(50)}\n\n${lines.join("\n\n")}`;
    }

    case "test_artifacts": {
      const testTitle = args.testTitle as string | undefined;

      if (!existsSync(RESULTS_PATH)) {
        return "No test results directory found.";
      }

      const artifacts: Array<{ test: string; type: string; path: string }> = [];

      // Recursively find artifacts
      function scanDir(dir: string, testName = "") {
        const entries = readdirSync(dir);
        for (const entry of entries) {
          const fullPath = join(dir, entry);
          const stat = statSync(fullPath);

          if (stat.isDirectory()) {
            // Directory name often contains test name
            scanDir(fullPath, entry);
          } else {
            // Determine artifact type
            let type = "unknown";
            if (entry.endsWith(".png")) type = "screenshot";
            else if (entry.endsWith(".webm")) type = "video";
            else if (entry.endsWith(".zip")) type = "trace";
            else if (entry.endsWith(".json")) type = "json";

            artifacts.push({
              test: testName,
              type,
              path: fullPath.replace(PROJECT_ROOT, ""),
            });
          }
        }
      }

      scanDir(RESULTS_PATH);

      // Filter by test title if provided
      const filtered = testTitle
        ? artifacts.filter((a) =>
            a.test.toLowerCase().includes(testTitle.toLowerCase())
          )
        : artifacts;

      if (filtered.length === 0) {
        return testTitle
          ? `No artifacts found for tests matching "${testTitle}"`
          : "No artifacts found.";
      }

      // Group by test
      const byTest = new Map<string, typeof artifacts>();
      for (const art of filtered) {
        if (!byTest.has(art.test)) {
          byTest.set(art.test, []);
        }
        byTest.get(art.test)!.push(art);
      }

      const lines = [...byTest.entries()].map(([test, arts]) => {
        const artLines = arts.map((a) => `  - [${a.type}] ${a.path}`).join("\n");
        return `${test || "Unknown test"}:\n${artLines}`;
      });

      return `Test Artifacts\n${"=".repeat(50)}\n\n${lines.join("\n\n")}`;
    }

    case "list_test_files": {
      const e2eDir = join(PROJECT_ROOT, "e2e");
      if (!existsSync(e2eDir)) {
        return "No e2e directory found.";
      }

      const files = readdirSync(e2eDir).filter((f) => f.endsWith(".spec.ts"));

      if (files.length === 0) {
        return "No test files found in e2e directory.";
      }

      const report = loadResults();
      const tests = report ? flattenTests(report.suites) : [];

      const lines = files.map((f) => {
        const testsInFile = tests.filter((t) => t.file.includes(f));
        const passed = testsInFile.filter((t) => t.status === "passed").length;
        const failed = testsInFile.filter((t) => t.status === "failed").length;
        const total = testsInFile.length;

        if (total > 0) {
          const status = failed > 0 ? "FAIL" : "PASS";
          return `[${status}] ${f} (${passed}/${total} passed)`;
        }
        return `[????] ${f} (no results)`;
      });

      return `Test Files\n${"=".repeat(50)}\n\n${lines.join("\n")}`;
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// Main server setup
const server = new Server(
  {
    name: "playwright-mcp",
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
  console.error("Playwright MCP server started");
}

main().catch(console.error);
