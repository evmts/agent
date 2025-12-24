---
name: observability
description: System monitoring, debugging, and health checks for Plue. Use when investigating issues, checking system status, analyzing errors, debugging workflows, viewing logs, or understanding what's happening in the system. Automatically invoked when users ask about health, errors, failures, logs, metrics, or debugging.
---

# Plue Observability

Comprehensive system observability using MCP servers. This skill helps you monitor, debug, and analyze the Plue platform.

## Quick Start

Use the appropriate MCP tools based on what you need:

| Need | MCP Server | First Tool |
|------|------------|------------|
| System overview | workflows | `system_overview(hours=1)` |
| Debug failed workflow | workflows | `quick_debug(latest=true)` |
| Find errors | logs | `find_errors(start="1h")` |
| Database health | database | `db_stats()` |
| Service status | prometheus | `service_health()` |
| Test failures | playwright | `test_summary()` |

## Available MCP Servers

### workflows-mcp (Workflow Debugging)

Primary tools for workflow debugging:

- `system_overview` - **START HERE** Quick snapshot of entire workflow system
- `quick_debug` - **RECOMMENDED** One-stop debugging for failed runs
  - `quick_debug(latest=true)` - Debug most recent failure
  - `quick_debug(run_id=42)` - Debug specific run
- `compare_runs` - Compare two runs to find regressions
  - `compare_runs(run_id_a=15, run_id_b=16)` - Diff passing vs failing
- `list_workflow_runs` - List recent runs with filters
- `get_run_details` - Step-by-step execution details
- `get_step_logs` - Logs for specific step
- `analyze_failures` - Find failure patterns over time
- `workflow_stats` - Success rates, durations, throughput
- `recent_agent_activity` - LLM calls, tokens, tool usage

### logs-mcp (Log Analysis)

- `find_errors` - Error logs grouped by type
- `search_logs` - Search with LogQL queries
- `tail_logs` - Recent logs from a service
- `trace_request` - Trace request by ID across services
- `workflow_logs` - Logs for specific workflow runs
- `agent_logs` - AI agent execution logs
- `search_exceptions` - Find stack traces

### database-mcp (Database Debugging)

- `db_stats` - Database size, connections, tables
- `list_tables` - All tables with row counts
- `query` - Execute read-only SQL
- `find_user` - Find user by username/email/ID
- `find_repository` - Find repo with workflows
- `recent_activity` - New users, repos, runs
- `check_connections` - Active queries, connection pool

### prometheus-mcp (Metrics)

- `service_health` - UP/DOWN status for all services
- `error_analysis` - Error rates and patterns
- `latency_analysis` - p50/p95/p99 latencies
- `prometheus_query` - Execute PromQL
- `prometheus_targets` - Scrape targets health

### playwright-mcp (E2E Test Results)

- `test_summary` - Overall pass/fail counts
- `list_failures` - Failed tests with errors
- `failure_patterns` - Group failures by error type
- `test_details` - Details for specific test
- `flaky_tests` - Tests that passed on retry
- `slow_tests` - Performance bottlenecks

## Common Debugging Workflows

### 1. Quick System Health Check

```
1. workflows-mcp: system_overview(hours=1)
2. prometheus-mcp: service_health()
3. database-mcp: db_stats()
```

### 2. Debug Failing Workflow

```
1. workflows-mcp: quick_debug(latest=true)
   - This gives you everything: run details, steps, errors, logs, similar failures

2. If you need more context:
   - workflows-mcp: get_step_logs(step_id=X)
   - logs-mcp: workflow_logs(run_id=Y)
```

### 3. Investigate Errors

```
1. logs-mcp: find_errors(start="1h")
2. logs-mcp: search_exceptions(start="6h")
3. prometheus-mcp: error_analysis(duration="1h")
```

### 4. Find Regression Between Runs

```
1. workflows-mcp: compare_runs(run_id_a=15, run_id_b=16)
   - Shows step-by-step status differences
   - Highlights new errors
   - Duration changes
```

### 5. Trace a Request

```
1. logs-mcp: trace_request(request_id="abc-123")
   - Shows request path through all services
```

### 6. Database Investigation

```
1. database-mcp: query(sql="SELECT * FROM workflow_runs WHERE status='failed' LIMIT 5")
2. database-mcp: check_connections()
```

## Debugging Decision Tree

```
Is it a workflow issue?
├── Yes → workflows-mcp: quick_debug(latest=true)
│   └── Need more logs? → logs-mcp: workflow_logs(run_id=X)
└── No
    ├── Is it an error/exception?
    │   └── Yes → logs-mcp: find_errors(start="1h")
    ├── Is it slow performance?
    │   └── Yes → prometheus-mcp: latency_analysis()
    ├── Is it a test failure?
    │   └── Yes → playwright-mcp: list_failures()
    └── General system issue?
        └── prometheus-mcp: service_health()
```

## Report Template

After debugging, summarize findings:

```markdown
## System Status: [HEALTHY / DEGRADED / UNHEALTHY]

### Issue Summary
[Brief description of what was found]

### Root Cause
[What caused the issue]

### Affected Components
- [Component 1]
- [Component 2]

### Evidence
[Key logs, metrics, or data points]

### Recommended Fix
[Steps to resolve]

### Prevention
[How to prevent recurrence]
```

## Tips

1. **Start with `system_overview`** - gives you the big picture
2. **Use `quick_debug` for workflows** - it's comprehensive
3. **Run queries in parallel** - MCP tools support concurrent execution
4. **Use request_id for tracing** - connects logs across services
5. **Compare time windows** - issues often show up as changes over time
6. **Check all services** - one failing service can cascade
