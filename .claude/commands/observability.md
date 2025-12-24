---
allowed-tools: Bash(curl:*), Bash(docker:*), Bash(zig:*), Glob, Grep, Read, Task
description: Unified observability dashboard - quick system status for debugging
model: claude-sonnet-4-20250514
---

# Observability Dashboard

Get a comprehensive view of the Plue system state using all available MCP servers.

## Arguments

- `--quick`: Fast overview only (default)
- `--full`: Include detailed logs and metrics
- `--workflows`: Focus on workflow system
- `--errors`: Focus on recent errors
- `--debug <run_id>`: Debug a specific workflow run

Arguments: $ARGUMENTS

## MCP Servers Available

This skill uses the following MCP servers:

1. **workflows-mcp**: Workflow execution data
   - `system_overview` - Quick snapshot of workflow system
   - `list_workflow_runs` - Recent runs
   - `analyze_failures` - Failure patterns
   - `quick_debug` - **NEW** One-stop debugging for failed runs
   - `compare_runs` - **NEW** Compare two runs to find regressions

2. **logs-mcp**: Application logs via Loki
   - `find_errors` - Recent errors
   - `log_stats` - Volume by service

3. **database-mcp**: Direct database access
   - `db_stats` - Database health
   - `recent_activity` - Recent changes

4. **prometheus-mcp**: Metrics (requires Prometheus running)
   - `service_health` - Service status
   - `error_analysis` - Error rates

5. **playwright-mcp**: E2E test results
   - `test_summary` - Test run overview
   - `list_failures` - Failed tests with errors
   - `failure_patterns` - Group failures by error type

## Quick Dashboard

```
Use workflows-mcp: system_overview(hours=1)
```

This gives you:
- Workflow run counts (completed/failed/pending/running)
- Success rate
- LLM/Agent activity (calls, tokens, latency)
- Recent failures

## System Health Check

Run these in parallel for a complete picture:

```
# Service Status
Use prometheus-mcp: service_health()

# Database Health
Use database-mcp: db_stats()

# Recent Errors
Use logs-mcp: find_errors(start="1h")
```

## Workflow Debugging Flow

### Quick Debug (Recommended)
```
Use workflows-mcp: quick_debug(latest=true)
```
This single command gives you:
- Run overview (workflow, status, duration)
- Timeline (created, started, completed)
- Full error message
- All steps with status
- Logs from failed steps
- Similar recent failures
- Next steps suggestions

### Compare Runs (For Regressions)
```
Use workflows-mcp: compare_runs(run_id_a=15, run_id_b=16)
```
Compare a passing run to a failing run to identify:
- Step-by-step status differences
- New errors in failing run
- Duration changes

### Traditional Flow
1. **Overview**: `system_overview(hours=24)`
2. **List Failures**: `analyze_failures(hours=24)`
3. **Drill Down**: `get_run_details(run_id=X)`
4. **View Logs**: `get_step_logs(step_id=Y)`

## Error Investigation Flow

1. **Find Errors**: `logs-mcp: find_errors(start="1h")`
2. **Trace Request**: `logs-mcp: trace_request(request_id="...")`
3. **Check Metrics**: `prometheus-mcp: error_analysis(duration="1h")`

## Common Queries

### Recent Activity
```
Use database-mcp: recent_activity(hours=24)
```
Shows: new users, repositories, sessions, workflow runs

### Workflow Statistics
```
Use workflows-mcp: workflow_stats(hours=24)
```
Shows: per-workflow success rates and durations

### Agent Activity
```
Use workflows-mcp: recent_agent_activity(hours=1)
```
Shows: LLM calls, token usage, latency

### Database Connections
```
Use database-mcp: check_connections()
```
Shows: active queries, connection pool status

## Quick Commands Reference

### Check if services are up
```bash
curl -s http://localhost:4000/health | head -3
curl -s http://localhost:3000 -o /dev/null -w "%{http_code}"
docker exec plue-postgres-1 pg_isready -U postgres
```

### Check Docker containers
```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "plue|postgres"
```

### View recent logs
```bash
docker logs plue-api 2>&1 | tail -50
```

## Dashboard Template

After running queries, summarize like this:

```markdown
## System Status: [HEALTHY / DEGRADED / UNHEALTHY]

### Services
- API: UP/DOWN
- Database: UP/DOWN
- Prometheus: UP/DOWN

### Workflows (last 1h)
- Runs: X total (Y completed, Z failed)
- Success Rate: X%
- Pending: X

### Recent Errors
1. [error summary]
2. [error summary]

### Recommendations
- [action item]
```

## Tips

1. **Start with `system_overview`** - gives you the big picture in one call
2. **Use parallel queries** - MCP tools can run concurrently
3. **Check logs when metrics look wrong** - they complement each other
4. **Use request_id for tracing** - connects logs across services
5. **Compare time windows** - issues often show up as changes over time
