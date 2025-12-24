---
allowed-tools: Bash(bun:*), Bash(git:*), Bash(curl:*), Bash(zig:*), Glob, Grep, Read, Task, TodoWrite
description: Debug workflow execution issues with comprehensive diagnostics
model: claude-sonnet-4-20250514
---

# Workflow Debugging Agent

Systematically debug Plue workflow execution issues using logs, metrics, and database queries.

## Arguments

- `[run_id]`: Optional workflow run ID to investigate
- `--recent`: Show recent failures (default if no run_id)
- `--all`: Show all workflow activity

Arguments: $ARGUMENTS

## Quick Reference

```
/debug-workflows 42        # Debug specific run #42
/debug-workflows --recent  # Debug recent failures
/debug-workflows           # Interactive diagnostics
```

## NEW: One-Command Debugging

### Quick Debug (Recommended Starting Point)
```
Use workflows-mcp: quick_debug(latest=true)
```
This single command returns:
- Full run overview (workflow, status, duration)
- Complete timeline
- Error message with context
- All step statuses with durations
- Logs from failed steps
- Similar recent failures
- Next steps suggestions

### Compare Two Runs (For Regressions)
```
Use workflows-mcp: compare_runs(run_id_a=15, run_id_b=16)
```
Compare a passing run to a failing run to identify:
- Step-by-step status differences
- New errors in the failing run
- Duration changes
- Configuration differences

## Phase 1: Gather Context

First, understand what we're debugging:

```bash
# If run_id provided, get that specific run
# Otherwise, get recent failures

# Check if workflows service is running
curl -s http://localhost:4000/health | head -5
```

### Using MCP Tools (if available)

The following MCP servers provide debugging capabilities:

1. **workflows-mcp**: Query workflow runs, steps, logs
   - `quick_debug` - **NEW** One-stop debugging for failed runs
   - `compare_runs` - **NEW** Compare two runs to find regressions
   - `system_overview` - Quick system health snapshot
   - `list_workflow_runs` - See recent runs and their status
   - `get_run_details` - Get step-by-step execution details
   - `get_step_logs` - View logs for a specific step
   - `analyze_failures` - Find patterns in failures

2. **logs-mcp**: Query Loki logs
   - `find_errors` - Find error logs
   - `workflow_logs` - Get logs for a specific workflow
   - `trace_request` - Trace request through services

3. **prometheus-mcp**: Query metrics
   - `service_health` - Check all services are up
   - `error_analysis` - Analyze error rates

## Phase 2: Check System Health

Before diving into specific issues, verify the system is healthy:

```bash
# Check API server
curl -s http://localhost:4000/health

# Check database connectivity
curl -s http://localhost:4000/api/v1/user 2>/dev/null || echo "API may need auth"

# Check if workflow runs table exists
# (Use database-mcp list_tables tool)
```

### Common Health Issues

1. **Database connection failed**
   - Check: `docker ps | grep postgres`
   - Fix: `zig build run` to restart services

2. **API server not responding**
   - Check: `lsof -i :4000`
   - Fix: Restart with `zig build run`

3. **Prometheus not scraping**
   - Check: `curl http://localhost:9090/targets`
   - Fix: Check docker-compose logs

## Phase 3: Investigate Specific Run

If a run_id is provided:

### 3.1 Get Run Overview

```
Use workflows-mcp tool: get_run_details(run_id)
```

Key things to check:
- **Status**: pending/running/completed/failed
- **Duration**: How long did it take?
- **Steps**: Which step failed?
- **Error message**: What was the error?

### 3.2 Check Step Logs

For each failed step:

```
Use workflows-mcp tool: get_step_logs(step_id)
```

Look for:
- Stack traces
- Error messages
- Unexpected output
- Missing dependencies

### 3.3 Cross-Reference with Application Logs

```
Use logs-mcp tool: workflow_logs(run_id)
```

This shows logs from all services related to this workflow run.

## Phase 4: Common Failure Patterns

### Pattern 1: Plan Parsing Failure

**Symptoms:**
- Run fails immediately
- Error: "Failed to parse plan JSON"

**Investigation:**
```bash
# Check the workflow definition
grep -A 20 "plan" db/daos/workflows.zig

# Verify JSON structure
# Use database-mcp: query("SELECT plan FROM workflow_definitions WHERE id = X")
```

**Common causes:**
- Invalid JSON in workflow definition
- Missing required fields in plan
- Type mismatch in step configuration

### Pattern 2: Step Execution Timeout

**Symptoms:**
- Step status: "timedOut"
- Long duration before failure

**Investigation:**
```bash
# Check step configuration for timeout
# Look at runner logs during execution
```

**Common causes:**
- Command hanging (waiting for input)
- Network timeout
- Resource exhaustion

### Pattern 3: Runner Assignment Failure

**Symptoms:**
- Run stuck in "pending"
- No steps executed

**Investigation:**
```
Use workflows-mcp: get_runner_pool()
Use workflows-mcp: get_pending_tasks()
```

**Common causes:**
- No runners in warm pool
- All runners claimed
- Runner heartbeat stale

### Pattern 4: Agent Step Failure

**Symptoms:**
- Agent step fails
- LLM-related errors

**Investigation:**
```
Use workflows-mcp: recent_agent_activity()
Use logs-mcp: agent_logs()
```

**Common causes:**
- API key issues
- Rate limiting
- Token limit exceeded
- Tool execution error

## Phase 5: Database Investigation

When logs aren't enough, query the database directly:

```sql
-- Recent failed runs with error details
SELECT r.id, w.name, r.status, r.error_message, r.created_at
FROM workflow_runs r
JOIN workflow_definitions w ON r.workflow_definition_id = w.id
WHERE r.status = 'failed'
ORDER BY r.created_at DESC
LIMIT 10;

-- Steps for a specific run
SELECT id, name, step_type, status, error_message,
       EXTRACT(EPOCH FROM (completed_at - started_at)) as duration_s
FROM workflow_steps
WHERE run_id = [RUN_ID]
ORDER BY id;

-- Check runner pool health
SELECT pod_name, status,
       EXTRACT(EPOCH FROM (NOW() - last_heartbeat)) as seconds_since_heartbeat
FROM runner_pool;
```

## Phase 6: Code Investigation

If the issue is in workflow execution code:

### Key Files

| Component | Location |
|-----------|----------|
| Workflow routes | `server/src/routes/workflows.zig` |
| Queue dispatch | `server/src/dispatch/queue.zig` |
| Workflow executor | `server/src/workflows/executor.zig` |
| Plan parser | `server/src/workflows/plan.zig` |
| Step runner | `server/src/workflows/runner.zig` |
| DB operations | `db/daos/workflows.zig` |

### Grep for Related Code

```bash
# Find error handling
grep -rn "error\." server/src/workflows/

# Find the specific error message
grep -rn "YOUR_ERROR_MESSAGE" server/

# Find step execution logic
grep -rn "executeStep" server/src/workflows/
```

## Phase 7: Metrics Analysis

Use Prometheus to understand patterns:

```
# Error rate for workflows
rate(plue_http_requests_total{path=~"/api/v1/workflows.*",status=~"5.."}[5m])

# Workflow execution duration histogram
histogram_quantile(0.95, rate(plue_workflow_duration_seconds_bucket[1h]))

# Runner pool utilization
plue_runner_pool_available / plue_runner_pool_total
```

## Phase 8: Resolution Checklist

After identifying the issue:

- [ ] Understand root cause
- [ ] Identify fix location
- [ ] Check if fix could introduce regressions
- [ ] Test fix locally
- [ ] Document finding in issue/PR

## Debugging Commands Reference

```bash
# Restart all services
zig build run

# Run workflow tests
zig build test -- --filter workflow

# Check workflow API
curl -X POST http://localhost:4000/api/v1/workflows/run \
  -H "Content-Type: application/json" \
  -d '{"workflow_name": "ci"}'

# Tail workflow logs
docker logs -f plue-api 2>&1 | grep -i workflow

# Check database directly
docker exec -it plue-postgres psql -U postgres -d plue \
  -c "SELECT * FROM workflow_runs ORDER BY created_at DESC LIMIT 5"
```

## Report Template

After debugging, provide a summary:

```markdown
## Workflow Debug Report

**Run ID**: #[ID]
**Workflow**: [name]
**Status**: [status]

### Timeline
- Created: [timestamp]
- Started: [timestamp]
- Failed/Completed: [timestamp]

### Root Cause
[Description of what caused the failure]

### Affected Steps
1. [step_name]: [status] - [error summary]

### Logs (relevant excerpts)
```
[relevant log lines]
```

### Recommended Fix
[What needs to change]

### Prevention
[How to prevent this in the future]
```

## Tips

1. **Start broad, narrow down**: Check system health before diving into specific runs
2. **Follow the data flow**: Trigger -> Queue -> Runner -> Execution -> Result
3. **Check timestamps**: Correlate events across services
4. **Use request_id**: Trace requests through all logs
5. **Compare with working runs**: What's different about the failing run?
