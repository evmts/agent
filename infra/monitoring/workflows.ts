#!/usr/bin/env bun
/**
 * Workflows MCP Server
 *
 * Enables AI agents to monitor and debug Plue workflow executions.
 * Provides tools to:
 * - List and filter workflow runs
 * - Get run details with step-by-step status
 * - View execution logs
 * - Analyze failure patterns
 * - Query runner pool status
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ToolSchema,
} from "@modelcontextprotocol/sdk/types.js";
import postgres from "postgres";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://postgres:postgres@localhost:54321/plue";

const sql = postgres(DATABASE_URL, {
  max: 5,
  idle_timeout: 20,
  connect_timeout: 10,
});

// Tool definitions
const tools: ToolSchema[] = [
  {
    name: "system_overview",
    description:
      "Get a quick overview of the entire workflow system: recent runs, failure rates, pending tasks, and agent activity. Use this FIRST to understand the current state.",
    inputSchema: {
      type: "object",
      properties: {
        hours: {
          type: "number",
          description: "Hours to look back (default: 1)",
        },
      },
    },
  },
  {
    name: "list_workflow_runs",
    description:
      "List recent workflow runs with status. Filter by workflow name, status, or repository. Use this to see what workflows have run and their outcomes.",
    inputSchema: {
      type: "object",
      properties: {
        limit: {
          type: "number",
          description: "Max runs to return (default: 20)",
        },
        status: {
          type: "string",
          enum: ["pending", "running", "completed", "failed", "cancelled"],
          description: "Filter by status",
        },
        workflow_name: {
          type: "string",
          description: "Filter by workflow name (partial match)",
        },
        repository: {
          type: "string",
          description: "Filter by repository (owner/name format)",
        },
      },
    },
  },
  {
    name: "get_run_details",
    description:
      "Get detailed information about a specific workflow run including all steps, their status, and outputs.",
    inputSchema: {
      type: "object",
      properties: {
        run_id: {
          type: "number",
          description: "Workflow run ID",
        },
      },
      required: ["run_id"],
    },
  },
  {
    name: "get_step_logs",
    description:
      "Get logs for a specific workflow step. Includes stdout, stderr, and any error messages.",
    inputSchema: {
      type: "object",
      properties: {
        step_id: {
          type: "number",
          description: "Workflow step ID (from get_run_details)",
        },
        log_type: {
          type: "string",
          enum: ["all", "stdout", "stderr", "token", "tool_call", "tool_result"],
          description: "Filter by log type (default: all)",
        },
        limit: {
          type: "number",
          description: "Max log lines to return (default: 500)",
        },
      },
      required: ["step_id"],
    },
  },
  {
    name: "get_run_logs",
    description:
      "Get all logs for a workflow run, aggregated across all steps. Useful for quick debugging.",
    inputSchema: {
      type: "object",
      properties: {
        run_id: {
          type: "number",
          description: "Workflow run ID",
        },
        limit: {
          type: "number",
          description: "Max log lines (default: 1000)",
        },
      },
      required: ["run_id"],
    },
  },
  {
    name: "analyze_failures",
    description:
      "Analyze workflow failures over a time period. Groups by error type and shows patterns.",
    inputSchema: {
      type: "object",
      properties: {
        hours: {
          type: "number",
          description: "Hours to look back (default: 24)",
        },
        workflow_name: {
          type: "string",
          description: "Optional: filter by workflow name",
        },
      },
    },
  },
  {
    name: "get_runner_pool",
    description:
      "Get status of the warm runner pool. Shows available/claimed runners and their health.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "get_pending_tasks",
    description:
      "List tasks waiting for runner assignment. Use to identify queue backlogs.",
    inputSchema: {
      type: "object",
      properties: {
        limit: {
          type: "number",
          description: "Max tasks to return (default: 50)",
        },
      },
    },
  },
  {
    name: "workflow_stats",
    description:
      "Get workflow execution statistics: success rates, average duration, throughput.",
    inputSchema: {
      type: "object",
      properties: {
        hours: {
          type: "number",
          description: "Hours to analyze (default: 24)",
        },
        workflow_name: {
          type: "string",
          description: "Optional: filter by workflow name",
        },
      },
    },
  },
  {
    name: "get_workflow_definition",
    description:
      "Get the parsed workflow definition including triggers and plan DAG.",
    inputSchema: {
      type: "object",
      properties: {
        workflow_id: {
          type: "number",
          description: "Workflow definition ID",
        },
        workflow_name: {
          type: "string",
          description: "Or search by name",
        },
      },
    },
  },
  {
    name: "recent_agent_activity",
    description:
      "Get recent AI agent activity: LLM calls, tool usage, token consumption.",
    inputSchema: {
      type: "object",
      properties: {
        hours: {
          type: "number",
          description: "Hours to look back (default: 1)",
        },
        limit: {
          type: "number",
          description: "Max entries (default: 50)",
        },
      },
    },
  },
  {
    name: "quick_debug",
    description:
      "One-stop debugging for a failed workflow run. Returns run details, step status, errors, and relevant logs. Use run_id OR 'latest' to debug the most recent failure.",
    inputSchema: {
      type: "object",
      properties: {
        run_id: {
          type: "number",
          description: "Workflow run ID to debug",
        },
        latest: {
          type: "boolean",
          description: "Debug the most recent failed run (default: false)",
        },
      },
    },
  },
  {
    name: "compare_runs",
    description:
      "Compare two workflow runs to identify differences. Useful for debugging regressions.",
    inputSchema: {
      type: "object",
      properties: {
        run_id_a: {
          type: "number",
          description: "First run ID (typically passing run)",
        },
        run_id_b: {
          type: "number",
          description: "Second run ID (typically failing run)",
        },
      },
      required: ["run_id_a", "run_id_b"],
    },
  },
];

// Tool handlers
async function handleTool(name: string, args: Record<string, unknown>): Promise<string> {
  switch (name) {
    case "system_overview": {
      const hours = (args.hours as number) || 1;

      try {
        // Get run stats
        const [runStats] = await sql`
          SELECT
            COUNT(*) as total,
            COUNT(*) FILTER (WHERE status = 'completed') as completed,
            COUNT(*) FILTER (WHERE status = 'failed') as failed,
            COUNT(*) FILTER (WHERE status = 'running') as running,
            COUNT(*) FILTER (WHERE status = 'pending') as pending
          FROM workflow_runs
          WHERE created_at > NOW() - make_interval(hours => ${hours})
        `;

        // Get recent failures
        const recentFailures = await sql`
          SELECT
            r.id,
            w.name as workflow_name,
            r.error_message,
            r.completed_at
          FROM workflow_runs r
          LEFT JOIN workflow_definitions w ON r.workflow_definition_id = w.id
          WHERE r.status = 'failed'
            AND r.created_at > NOW() - make_interval(hours => ${hours})
          ORDER BY r.completed_at DESC
          LIMIT 5
        `;

        // Get LLM usage
        const [llmStats] = await sql`
          SELECT
            COUNT(*) as total_calls,
            COALESCE(SUM(input_tokens), 0) as total_input_tokens,
            COALESCE(SUM(output_tokens), 0) as total_output_tokens,
            COALESCE(AVG(latency_ms), 0) as avg_latency_ms
          FROM llm_usage
          WHERE created_at > NOW() - make_interval(hours => ${hours})
        `;

        // Get workflow definitions count
        const [defStats] = await sql`
          SELECT COUNT(*) as count FROM workflow_definitions
        `;

        const successRate = runStats.total > 0
          ? ((runStats.completed / runStats.total) * 100).toFixed(1)
          : "N/A";

        let result = `Workflow System Overview (last ${hours}h)
${"=".repeat(55)}

Workflow Runs:
  Total: ${runStats.total} | Completed: ${runStats.completed} | Failed: ${runStats.failed}
  Running: ${runStats.running} | Pending: ${runStats.pending}
  Success Rate: ${successRate}%

Workflow Definitions: ${defStats.count}

LLM/Agent Activity:
  Total LLM Calls: ${llmStats.total_calls}
  Tokens: ${Number(llmStats.total_input_tokens).toLocaleString()} in / ${Number(llmStats.total_output_tokens).toLocaleString()} out
  Avg Latency: ${Math.round(llmStats.avg_latency_ms || 0)}ms
`;

        if (recentFailures.length > 0) {
          result += `\nRecent Failures:\n`;
          for (const f of recentFailures) {
            const error = f.error_message
              ? f.error_message.slice(0, 60).replace(/\n/g, " ")
              : "Unknown";
            result += `  - Run #${f.id} (${f.workflow_name || "unknown"}): ${error}...\n`;
          }
        } else {
          result += `\nNo failures in the last ${hours}h. Nice!\n`;
        }

        result += `\nUse list_workflow_runs, get_run_details, or analyze_failures for more info.`;

        return result;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "list_workflow_runs": {
      const limit = (args.limit as number) || 20;
      const status = args.status as string | undefined;
      const workflowName = args.workflow_name as string | undefined;
      const repository = args.repository as string | undefined;

      let query = sql`
        SELECT
          r.id,
          w.name as workflow_name,
          r.status,
          r.trigger_type,
          r.created_at,
          r.started_at,
          r.completed_at,
          EXTRACT(EPOCH FROM (COALESCE(r.completed_at, NOW()) - r.started_at)) as duration_seconds,
          r.error_message
        FROM workflow_runs r
        LEFT JOIN workflow_definitions w ON r.workflow_definition_id = w.id
        WHERE 1=1
      `;

      if (status) {
        query = sql`${query} AND r.status = ${status}`;
      }
      if (workflowName) {
        query = sql`${query} AND w.name ILIKE ${'%' + workflowName + '%'}`;
      }

      query = sql`${query} ORDER BY r.created_at DESC LIMIT ${limit}`;

      try {
        const runs = await query;

        if (runs.length === 0) {
          return "No workflow runs found matching criteria.";
        }

        const lines = runs.map((r) => {
          const duration = r.duration_seconds
            ? `${Math.round(r.duration_seconds)}s`
            : "N/A";
          const status = formatStatus(r.status);
          const error = r.error_message ? `\n     Error: ${r.error_message.slice(0, 100)}` : "";
          return `[${status}] Run #${r.id}: ${r.workflow_name || "unknown"}
     Trigger: ${r.trigger_type} | Duration: ${duration}
     Created: ${formatDate(r.created_at)}${error}`;
        });

        return `Workflow Runs (${runs.length})\n${"=".repeat(50)}\n\n${lines.join("\n\n")}`;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "get_run_details": {
      const runId = args.run_id as number;

      try {
        // Get run info
        const [run] = await sql`
          SELECT
            r.*,
            w.name as workflow_name,
            w.file_path,
            w.plan
          FROM workflow_runs r
          LEFT JOIN workflow_definitions w ON r.workflow_definition_id = w.id
          WHERE r.id = ${runId}
        `;

        if (!run) {
          return `Run #${runId} not found`;
        }

        // Get steps
        const steps = await sql`
          SELECT *
          FROM workflow_steps
          WHERE run_id = ${runId}
          ORDER BY id
        `;

        let result = `Workflow Run #${runId}
${"=".repeat(50)}
Workflow:   ${run.workflow_name || "unknown"}
File:       ${run.file_path || "N/A"}
Status:     ${formatStatus(run.status)}
Trigger:    ${run.trigger_type}

Timeline:
  Created:   ${formatDate(run.created_at)}
  Started:   ${formatDate(run.started_at)}
  Completed: ${formatDate(run.completed_at)}
`;

        if (run.error_message) {
          result += `\nError: ${run.error_message}\n`;
        }

        if (run.inputs) {
          result += `\nInputs: ${JSON.stringify(run.inputs, null, 2)}\n`;
        }

        if (run.outputs) {
          result += `\nOutputs: ${JSON.stringify(run.outputs, null, 2)}\n`;
        }

        if (steps.length > 0) {
          result += `\nSteps (${steps.length}):\n${"─".repeat(40)}\n`;
          for (const step of steps) {
            const duration = step.completed_at && step.started_at
              ? `${Math.round((new Date(step.completed_at).getTime() - new Date(step.started_at).getTime()) / 1000)}s`
              : "N/A";

            result += `\n[${formatStatus(step.status)}] Step #${step.id}: ${step.name}
   Type: ${step.step_type} | Duration: ${duration}`;

            if (step.step_type === "agent" && step.turns_used) {
              result += `\n   Agent: ${step.turns_used} turns, ${step.tokens_in || 0} in / ${step.tokens_out || 0} out tokens`;
            }

            if (step.exit_code !== null) {
              result += `\n   Exit code: ${step.exit_code}`;
            }

            if (step.error_message) {
              result += `\n   Error: ${step.error_message.slice(0, 200)}`;
            }
          }
        }

        return result;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "get_step_logs": {
      const stepId = args.step_id as number;
      const logType = args.log_type as string || "all";
      const limit = (args.limit as number) || 500;

      try {
        let query = sql`
          SELECT log_type, content, sequence, created_at
          FROM workflow_logs
          WHERE step_id = ${stepId}
        `;

        if (logType !== "all") {
          query = sql`${query} AND log_type = ${logType}`;
        }

        query = sql`${query} ORDER BY sequence LIMIT ${limit}`;

        const logs = await query;

        if (logs.length === 0) {
          return `No logs found for step #${stepId}`;
        }

        const lines = logs.map((l) => {
          const prefix = `[${l.log_type.padEnd(10)}]`;
          return `${prefix} ${l.content}`;
        });

        return `Step #${stepId} Logs (${logs.length} lines)\n${"=".repeat(50)}\n\n${lines.join("\n")}`;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "get_run_logs": {
      const runId = args.run_id as number;
      const limit = (args.limit as number) || 1000;

      try {
        const logs = await sql`
          SELECT
            l.log_type,
            l.content,
            l.sequence,
            l.created_at,
            s.name as step_name,
            s.step_type
          FROM workflow_logs l
          JOIN workflow_steps s ON l.step_id = s.id
          WHERE s.run_id = ${runId}
          ORDER BY l.created_at, l.sequence
          LIMIT ${limit}
        `;

        if (logs.length === 0) {
          return `No logs found for run #${runId}`;
        }

        let currentStep = "";
        const lines: string[] = [];

        for (const l of logs) {
          if (l.step_name !== currentStep) {
            currentStep = l.step_name;
            lines.push(`\n--- ${l.step_name} (${l.step_type}) ---\n`);
          }
          lines.push(`[${l.log_type}] ${l.content}`);
        }

        return `Run #${runId} Logs\n${"=".repeat(50)}${lines.join("\n")}`;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "analyze_failures": {
      const hours = (args.hours as number) || 24;
      const workflowName = args.workflow_name as string | undefined;

      try {
        let failuresQuery = sql`
          SELECT
            w.name as workflow_name,
            r.error_message,
            COUNT(*) as count,
            MAX(r.created_at) as last_occurrence
          FROM workflow_runs r
          LEFT JOIN workflow_definitions w ON r.workflow_definition_id = w.id
          WHERE r.status = 'failed'
            AND r.created_at > NOW() - make_interval(hours => ${hours})
        `;

        if (workflowName) {
          failuresQuery = sql`${failuresQuery} AND w.name ILIKE ${'%' + workflowName + '%'}`;
        }

        failuresQuery = sql`${failuresQuery}
          GROUP BY w.name, r.error_message
          ORDER BY count DESC
          LIMIT 20
        `;

        const failures = await failuresQuery;

        if (failures.length === 0) {
          return `No failures in the last ${hours} hours. Nice!`;
        }

        // Also get total stats
        const [stats] = await sql`
          SELECT
            COUNT(*) FILTER (WHERE status = 'failed') as failed,
            COUNT(*) FILTER (WHERE status = 'completed') as completed,
            COUNT(*) as total
          FROM workflow_runs
          WHERE created_at > NOW() - make_interval(hours => ${hours})
        `;

        const failRate = stats.total > 0
          ? ((stats.failed / stats.total) * 100).toFixed(1)
          : "0";

        let result = `Failure Analysis (last ${hours}h)
${"=".repeat(50)}
Total runs: ${stats.total} | Failed: ${stats.failed} | Success rate: ${100 - parseFloat(failRate)}%

Failure Patterns:
`;

        for (const f of failures) {
          const error = f.error_message
            ? f.error_message.slice(0, 100).replace(/\n/g, " ")
            : "Unknown error";
          result += `\n[${f.count}x] ${f.workflow_name || "unknown"}
   Error: ${error}
   Last: ${formatDate(f.last_occurrence)}`;
        }

        return result;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "get_runner_pool": {
      try {
        // Check if table exists first
        const tableCheck = await sql`
          SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = 'runner_pool'
          ) as exists
        `;

        if (!tableCheck[0]?.exists) {
          return `Runner Pool Status
${"=".repeat(50)}
The runner_pool table does not exist yet.
This feature requires the warm pool infrastructure to be set up.

To create the table, run the schema migration or add the runner pool feature.`;
        }

        const runners = await sql`
          SELECT
            id,
            pod_name,
            pod_ip,
            status,
            registered_at,
            last_heartbeat,
            claimed_at,
            claimed_by_task_id,
            EXTRACT(EPOCH FROM (NOW() - last_heartbeat)) as seconds_since_heartbeat
          FROM runner_pool
          ORDER BY status, registered_at
        `;

        if (runners.length === 0) {
          return "No runners in pool. Warm pool may not be configured.";
        }

        const available = runners.filter((r) => r.status === "available").length;
        const claimed = runners.filter((r) => r.status === "claimed").length;

        let result = `Runner Pool Status
${"=".repeat(50)}
Available: ${available} | Claimed: ${claimed} | Total: ${runners.length}

Runners:
`;

        for (const r of runners) {
          const health = r.seconds_since_heartbeat < 30 ? "healthy" : "stale";
          result += `\n[${r.status.toUpperCase()}] ${r.pod_name}
   IP: ${r.pod_ip} | Health: ${health}
   Last heartbeat: ${Math.round(r.seconds_since_heartbeat)}s ago`;

          if (r.claimed_by_task_id) {
            result += `\n   Claimed by task: #${r.claimed_by_task_id}`;
          }
        }

        return result;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "get_pending_tasks": {
      const limit = (args.limit as number) || 50;

      try {
        // Check if table exists first
        const tableCheck = await sql`
          SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = 'workflow_tasks'
          ) as exists
        `;

        if (!tableCheck[0]?.exists) {
          // Fall back to checking workflow_runs for pending runs
          const pendingRuns = await sql`
            SELECT
              id,
              trigger_type,
              status,
              created_at,
              EXTRACT(EPOCH FROM (NOW() - created_at)) as wait_seconds
            FROM workflow_runs
            WHERE status IN ('pending', 'running')
            ORDER BY created_at
            LIMIT ${limit}
          `;

          if (pendingRuns.length === 0) {
            return "No pending workflow runs. Queue is clear.";
          }

          const lines = pendingRuns.map((r) => {
            const wait = `${Math.round(r.wait_seconds)}s`;
            return `[${r.status.toUpperCase()}] Run #${r.id}
   Trigger: ${r.trigger_type}
   Waiting: ${wait}`;
          });

          return `Pending Workflow Runs (${pendingRuns.length})\n${"=".repeat(50)}\n\n${lines.join("\n\n")}`;
        }

        const tasks = await sql`
          SELECT
            t.id,
            t.workload_type,
            t.priority,
            t.status,
            t.created_at,
            t.session_id,
            EXTRACT(EPOCH FROM (NOW() - t.created_at)) as wait_seconds
          FROM workflow_tasks t
          WHERE t.status IN ('waiting', 'pending', 'assigned')
          ORDER BY t.priority DESC, t.created_at
          LIMIT ${limit}
        `;

        if (tasks.length === 0) {
          return "No pending tasks. Queue is clear.";
        }

        const lines = tasks.map((t) => {
          const wait = `${Math.round(t.wait_seconds)}s`;
          return `[${t.status}] Task #${t.id}
   Type: ${t.workload_type} | Priority: ${t.priority}
   Waiting: ${wait}`;
        });

        return `Pending Tasks (${tasks.length})\n${"=".repeat(50)}\n\n${lines.join("\n\n")}`;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "workflow_stats": {
      const hours = (args.hours as number) || 24;
      const workflowName = args.workflow_name as string | undefined;

      try {
        let query = sql`
          SELECT
            w.name as workflow_name,
            COUNT(*) as total_runs,
            COUNT(*) FILTER (WHERE r.status = 'completed') as successful,
            COUNT(*) FILTER (WHERE r.status = 'failed') as failed,
            AVG(EXTRACT(EPOCH FROM (r.completed_at - r.started_at))) as avg_duration,
            MIN(EXTRACT(EPOCH FROM (r.completed_at - r.started_at))) as min_duration,
            MAX(EXTRACT(EPOCH FROM (r.completed_at - r.started_at))) as max_duration
          FROM workflow_runs r
          LEFT JOIN workflow_definitions w ON r.workflow_definition_id = w.id
          WHERE r.created_at > NOW() - make_interval(hours => ${hours})
            AND r.status IN ('completed', 'failed')
        `;

        if (workflowName) {
          query = sql`${query} AND w.name ILIKE ${'%' + workflowName + '%'}`;
        }

        query = sql`${query} GROUP BY w.name ORDER BY total_runs DESC`;

        const stats = await query;

        if (stats.length === 0) {
          return `No workflow runs in the last ${hours} hours.`;
        }

        let result = `Workflow Statistics (last ${hours}h)
${"=".repeat(50)}
`;

        for (const s of stats) {
          const successRate = s.total_runs > 0
            ? ((s.successful / s.total_runs) * 100).toFixed(1)
            : "0";
          const avgDur = s.avg_duration ? `${Math.round(s.avg_duration)}s` : "N/A";
          const minDur = s.min_duration ? `${Math.round(s.min_duration)}s` : "N/A";
          const maxDur = s.max_duration ? `${Math.round(s.max_duration)}s` : "N/A";

          result += `\n${s.workflow_name || "unknown"}
   Runs: ${s.total_runs} | Success: ${s.successful} | Failed: ${s.failed}
   Success rate: ${successRate}%
   Duration: avg=${avgDur} min=${minDur} max=${maxDur}`;
        }

        return result;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "get_workflow_definition": {
      const workflowId = args.workflow_id as number | undefined;
      const workflowName = args.workflow_name as string | undefined;

      try {
        let query;
        if (workflowId) {
          query = sql`SELECT * FROM workflow_definitions WHERE id = ${workflowId}`;
        } else if (workflowName) {
          query = sql`SELECT * FROM workflow_definitions WHERE name ILIKE ${'%' + workflowName + '%'} LIMIT 1`;
        } else {
          return "Provide either workflow_id or workflow_name";
        }

        const [def] = await query;

        if (!def) {
          return "Workflow definition not found";
        }

        let result = `Workflow Definition: ${def.name}
${"=".repeat(50)}
ID:       ${def.id}
File:     ${def.file_path}
Image:    ${def.image || "default"}

Triggers:
${JSON.stringify(def.triggers, null, 2)}

Plan (DAG):
${JSON.stringify(JSON.parse(def.plan || "{}"), null, 2)}
`;

        return result;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "recent_agent_activity": {
      const hours = (args.hours as number) || 1;
      const limit = (args.limit as number) || 50;

      try {
        const activity = await sql`
          SELECT
            u.id,
            u.prompt_name,
            u.model,
            u.input_tokens,
            u.output_tokens,
            u.latency_ms,
            u.created_at,
            s.name as step_name,
            r.id as run_id
          FROM llm_usage u
          LEFT JOIN workflow_steps s ON u.step_id = s.id
          LEFT JOIN workflow_runs r ON s.run_id = r.id
          WHERE u.created_at > NOW() - make_interval(hours => ${hours})
          ORDER BY u.created_at DESC
          LIMIT ${limit}
        `;

        if (activity.length === 0) {
          return `No agent activity in the last ${hours} hour(s).`;
        }

        // Calculate totals
        const totalTokensIn = activity.reduce((sum, a) => sum + (a.input_tokens || 0), 0);
        const totalTokensOut = activity.reduce((sum, a) => sum + (a.output_tokens || 0), 0);
        const avgLatency = activity.reduce((sum, a) => sum + (a.latency_ms || 0), 0) / activity.length;

        let result = `Agent Activity (last ${hours}h)
${"=".repeat(50)}
Total LLM calls: ${activity.length}
Tokens: ${totalTokensIn.toLocaleString()} in / ${totalTokensOut.toLocaleString()} out
Avg latency: ${Math.round(avgLatency)}ms

Recent calls:
`;

        for (const a of activity.slice(0, 20)) {
          result += `\n[${formatDate(a.created_at)}] ${a.prompt_name || "unknown"}
   Model: ${a.model} | Tokens: ${a.input_tokens}/${a.output_tokens} | ${a.latency_ms}ms`;
          if (a.run_id) {
            result += `\n   Run: #${a.run_id} → ${a.step_name}`;
          }
        }

        return result;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "quick_debug": {
      const runId = args.run_id as number | undefined;
      const latest = args.latest as boolean;

      try {
        let targetRunId = runId;

        // Find latest failed run if requested
        if (latest || !runId) {
          const [latestFailed] = await sql`
            SELECT id FROM workflow_runs
            WHERE status = 'failed'
            ORDER BY created_at DESC
            LIMIT 1
          `;
          if (!latestFailed) {
            return "No failed runs found to debug.";
          }
          targetRunId = latestFailed.id;
        }

        // Get run details
        const [run] = await sql`
          SELECT
            r.*,
            w.name as workflow_name,
            w.file_path,
            w.triggers
          FROM workflow_runs r
          LEFT JOIN workflow_definitions w ON r.workflow_definition_id = w.id
          WHERE r.id = ${targetRunId}
        `;

        if (!run) {
          return `Run #${targetRunId} not found`;
        }

        // Get steps with details
        const steps = await sql`
          SELECT *
          FROM workflow_steps
          WHERE run_id = ${targetRunId}
          ORDER BY id
        `;

        // Get logs for failed steps
        const failedStepIds = steps.filter((s: any) => s.status === 'failed').map((s: any) => s.id);
        let logs: any[] = [];
        if (failedStepIds.length > 0) {
          logs = await sql`
            SELECT l.*, s.name as step_name
            FROM workflow_logs l
            JOIN workflow_steps s ON l.step_id = s.id
            WHERE l.step_id = ANY(${failedStepIds})
            ORDER BY l.step_id, l.sequence
            LIMIT 200
          `;
        }

        // Get similar failures for context
        const similarFailures = await sql`
          SELECT
            r.id,
            r.error_message,
            r.created_at
          FROM workflow_runs r
          WHERE r.workflow_definition_id = ${run.workflow_definition_id}
            AND r.status = 'failed'
            AND r.id != ${targetRunId}
            AND r.created_at > NOW() - INTERVAL '7 days'
          ORDER BY r.created_at DESC
          LIMIT 5
        `;

        // Build comprehensive debug output
        let result = `🔍 Quick Debug: Run #${targetRunId}
${"=".repeat(60)}

📋 OVERVIEW
Workflow:    ${run.workflow_name || "unknown"}
File:        ${run.file_path || "N/A"}
Status:      ${formatStatus(run.status)} ${run.status === 'failed' ? '❌' : ''}
Trigger:     ${run.trigger_type}
Duration:    ${run.completed_at && run.started_at
  ? `${Math.round((new Date(run.completed_at).getTime() - new Date(run.started_at).getTime()) / 1000)}s`
  : 'N/A'}

⏰ TIMELINE
Created:     ${formatDate(run.created_at)}
Started:     ${formatDate(run.started_at)}
Completed:   ${formatDate(run.completed_at)}
`;

        if (run.error_message) {
          result += `
❌ ERROR MESSAGE
${"─".repeat(40)}
${run.error_message}
`;
        }

        if (steps.length > 0) {
          result += `
📝 STEPS (${steps.length} total)
${"─".repeat(40)}`;
          for (const step of steps) {
            const icon = step.status === 'completed' ? '✓' :
                        step.status === 'failed' ? '✗' :
                        step.status === 'running' ? '⟳' : '○';
            const duration = step.completed_at && step.started_at
              ? `${Math.round((new Date(step.completed_at).getTime() - new Date(step.started_at).getTime()) / 1000)}s`
              : '';
            result += `
${icon} Step #${step.id}: ${step.name} [${step.step_type}]
   Status: ${step.status} ${duration ? `| Duration: ${duration}` : ''}`;

            if (step.error_message) {
              result += `
   Error: ${step.error_message.slice(0, 200)}`;
            }

            if (step.step_type === 'agent' && step.turns_used) {
              result += `
   Agent: ${step.turns_used} turns, ${step.tokens_in || 0}/${step.tokens_out || 0} tokens`;
            }
          }
        }

        if (logs.length > 0) {
          result += `

📜 LOGS FROM FAILED STEPS
${"─".repeat(40)}`;
          let currentStep = "";
          for (const log of logs) {
            if (log.step_name !== currentStep) {
              currentStep = log.step_name;
              result += `\n\n[${currentStep}]`;
            }
            result += `\n  ${log.log_type}: ${log.content.slice(0, 200)}`;
          }
        }

        if (similarFailures.length > 0) {
          result += `

🔄 SIMILAR RECENT FAILURES (${similarFailures.length})
${"─".repeat(40)}`;
          for (const f of similarFailures) {
            const error = f.error_message ? f.error_message.slice(0, 60) : 'Unknown';
            result += `\n  Run #${f.id} (${formatDate(f.created_at)}): ${error}`;
          }
        }

        result += `

💡 NEXT STEPS
${"─".repeat(40)}
1. Check the error message above for the root cause
2. Use get_step_logs(step_id=X) for full logs of a specific step
3. Use get_workflow_definition(workflow_name="${run.workflow_name}") to see the workflow plan
4. Check analyze_failures() to see if this is a recurring issue
`;

        return result;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    case "compare_runs": {
      const runIdA = args.run_id_a as number;
      const runIdB = args.run_id_b as number;

      try {
        // Get both runs
        const runs = await sql`
          SELECT
            r.*,
            w.name as workflow_name
          FROM workflow_runs r
          LEFT JOIN workflow_definitions w ON r.workflow_definition_id = w.id
          WHERE r.id IN (${runIdA}, ${runIdB})
        `;

        const runA = runs.find((r: any) => r.id === runIdA);
        const runB = runs.find((r: any) => r.id === runIdB);

        if (!runA || !runB) {
          return `One or both runs not found. Run A: ${runA ? 'found' : 'missing'}, Run B: ${runB ? 'found' : 'missing'}`;
        }

        // Get steps for both runs
        const stepsA = await sql`
          SELECT * FROM workflow_steps WHERE run_id = ${runIdA} ORDER BY id
        `;
        const stepsB = await sql`
          SELECT * FROM workflow_steps WHERE run_id = ${runIdB} ORDER BY id
        `;

        let result = `📊 Run Comparison
${"=".repeat(60)}

                    Run A (#${runIdA})          Run B (#${runIdB})
${"─".repeat(60)}
Workflow:           ${(runA.workflow_name || 'unknown').padEnd(20)} ${runB.workflow_name || 'unknown'}
Status:             ${runA.status.padEnd(20)} ${runB.status}
Trigger:            ${runA.trigger_type.padEnd(20)} ${runB.trigger_type}
Duration:           ${getDuration(runA).padEnd(20)} ${getDuration(runB)}
Steps:              ${String(stepsA.length).padEnd(20)} ${stepsB.length}

📝 STEP COMPARISON
${"─".repeat(60)}`;

        // Compare steps
        const maxSteps = Math.max(stepsA.length, stepsB.length);
        for (let i = 0; i < maxSteps; i++) {
          const stepA = stepsA[i];
          const stepB = stepsB[i];

          const nameA = stepA ? stepA.name : '-';
          const nameB = stepB ? stepB.name : '-';
          const statusA = stepA ? stepA.status : '-';
          const statusB = stepB ? stepB.status : '-';

          const statusMatch = statusA === statusB ? '✓' : '≠';

          result += `
${statusMatch} Step ${i + 1}:
   Name:   ${nameA.slice(0, 25).padEnd(25)} ${nameB.slice(0, 25)}
   Status: ${statusA.padEnd(25)} ${statusB}`;

          if (stepB?.error_message && !stepA?.error_message) {
            result += `
   ⚠️ New error in B: ${stepB.error_message.slice(0, 60)}`;
          }
        }

        // Highlight key differences
        const differences: string[] = [];
        if (runA.status !== runB.status) {
          differences.push(`Status changed: ${runA.status} → ${runB.status}`);
        }
        if (stepsA.length !== stepsB.length) {
          differences.push(`Step count changed: ${stepsA.length} → ${stepsB.length}`);
        }

        const failedInB = stepsB.filter((s: any) => s.status === 'failed' && !stepsA.find((a: any) => a.name === s.name && a.status === 'failed'));
        if (failedInB.length > 0) {
          differences.push(`New failures in B: ${failedInB.map((s: any) => s.name).join(', ')}`);
        }

        if (differences.length > 0) {
          result += `

🔍 KEY DIFFERENCES
${"─".repeat(40)}`;
          for (const diff of differences) {
            result += `\n  • ${diff}`;
          }
        }

        return result;
      } catch (error) {
        return `Database error: ${error}`;
      }
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// Format helpers
function formatStatus(status: string): string {
  const icons: Record<string, string> = {
    pending: "PEND",
    running: "RUN ",
    completed: " OK ",
    failed: "FAIL",
    cancelled: "CANC",
    succeeded: " OK ",
  };
  return icons[status] || status.slice(0, 4).toUpperCase();
}

function formatDate(date: Date | string | null): string {
  if (!date) return "N/A";
  const d = new Date(date);
  return d.toISOString().replace("T", " ").slice(0, 19);
}

function getDuration(run: any): string {
  if (!run.completed_at || !run.started_at) return "N/A";
  const ms = new Date(run.completed_at).getTime() - new Date(run.started_at).getTime();
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  return `${(ms / 60000).toFixed(1)}m`;
}

// Main server setup
const server = new Server(
  {
    name: "workflows-mcp",
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

// Cleanup on exit
process.on("SIGINT", async () => {
  await sql.end();
  process.exit(0);
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Workflows MCP server started");
}

main().catch(console.error);
