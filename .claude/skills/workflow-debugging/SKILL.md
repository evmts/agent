---
name: workflow-debugging
description: Debug Plue workflow execution failures. Use when a workflow fails, is stuck, runs slowly, or produces unexpected results. Automatically invoked for questions about workflow runs, step failures, agent errors, or workflow execution issues.
---

# Workflow Debugging

Specialized skill for debugging Plue workflow execution issues. Uses the workflows-mcp server for comprehensive debugging.

## Quick Debug (Recommended Starting Point)

For any workflow failure, start with:

```
workflows-mcp: quick_debug(latest=true)
```

This single command returns:
- Run overview (workflow name, status, duration)
- Complete timeline (created, started, completed)
- Full error message with context
- All step statuses with durations
- Logs from failed steps
- Similar recent failures (pattern detection)
- Next steps suggestions

To debug a specific run:
```
workflows-mcp: quick_debug(run_id=42)
```

## Compare Runs (For Regressions)

When a workflow that was working now fails:

```
workflows-mcp: compare_runs(run_id_a=15, run_id_b=16)
```

This shows:
- Side-by-side status comparison
- Step-by-step differences
- New errors in failing run
- Duration changes
- Configuration differences

## Common Failure Patterns

### Pattern 1: Run Stuck in Pending

**Symptoms:** Run never starts, status stays "pending"

**Debug:**
```
workflows-mcp: get_pending_tasks()
workflows-mcp: get_runner_pool()
```

**Common causes:**
- No runners available in warm pool
- All runners claimed
- Runner heartbeat stale

### Pattern 2: Step Execution Failure

**Symptoms:** Run starts but a step fails

**Debug:**
```
workflows-mcp: quick_debug(run_id=X)
workflows-mcp: get_step_logs(step_id=Y)
```

**Common causes:**
- Command not found
- Permission denied
- Missing dependencies
- Timeout exceeded

### Pattern 3: Agent Step Failure

**Symptoms:** Agent/LLM step fails

**Debug:**
```
workflows-mcp: quick_debug(run_id=X)
workflows-mcp: recent_agent_activity(hours=1)
logs-mcp: agent_logs(start="1h")
```

**Common causes:**
- API key issues (check ANTHROPIC_API_KEY)
- Rate limiting
- Token limit exceeded
- Tool execution error
- Max turns reached

### Pattern 4: Plan Parsing Failure

**Symptoms:** Run fails immediately with JSON parsing error

**Debug:**
```
workflows-mcp: get_workflow_definition(workflow_name="X")
```

**Common causes:**
- Invalid JSON in workflow definition
- Missing required fields in plan
- Type mismatch in step configuration

### Pattern 5: Intermittent Failures

**Symptoms:** Same workflow sometimes passes, sometimes fails

**Debug:**
```
workflows-mcp: analyze_failures(hours=24, workflow_name="X")
workflows-mcp: workflow_stats(hours=24, workflow_name="X")
```

**Common causes:**
- Race conditions
- External service flakiness
- Resource contention
- Timing-dependent logic

## Debugging Checklist

When debugging a workflow failure:

1. **Get the overview**
   ```
   workflows-mcp: quick_debug(latest=true)
   ```

2. **Check system health**
   ```
   workflows-mcp: system_overview(hours=1)
   ```

3. **View step logs** (for failed steps)
   ```
   workflows-mcp: get_step_logs(step_id=X)
   ```

4. **Check for patterns**
   ```
   workflows-mcp: analyze_failures(hours=24)
   ```

5. **Compare with passing run** (if regression)
   ```
   workflows-mcp: compare_runs(run_id_a=PASS, run_id_b=FAIL)
   ```

## Key Files

When you need to investigate code:

| Component | Location |
|-----------|----------|
| Workflow routes | `server/src/routes/workflows.zig` |
| Workflow v2 routes | `server/src/routes/workflows_v2.zig` |
| Queue dispatch | `server/src/dispatch/queue.zig` |
| Workflow executor | `server/src/workflows/executor.zig` |
| LLM executor | `server/src/workflows/llm_executor.zig` |
| Local runner | `server/src/workflows/local_runner.zig` |
| Prompt parser | `server/src/workflows/prompt.zig` |
| Registry | `server/src/workflows/registry.zig` |
| DB operations | `db/daos/workflows.zig` |

## Database Queries

For direct database investigation:

```sql
-- Recent failed runs with error details
database-mcp: query(sql="
  SELECT r.id, w.name, r.status, r.error_message, r.created_at
  FROM workflow_runs r
  JOIN workflow_definitions w ON r.workflow_definition_id = w.id
  WHERE r.status = 'failed'
  ORDER BY r.created_at DESC
  LIMIT 10
")

-- Steps for a specific run
database-mcp: query(sql="
  SELECT id, name, step_type, status, error_message,
         EXTRACT(EPOCH FROM (completed_at - started_at)) as duration_s
  FROM workflow_steps
  WHERE run_id = [RUN_ID]
  ORDER BY id
")

-- LLM usage for agent steps
database-mcp: query(sql="
  SELECT prompt_name, model, input_tokens, output_tokens, latency_ms
  FROM llm_usage
  WHERE step_id = [STEP_ID]
")
```

## Debug Report Template

After debugging, provide a summary:

```markdown
## Workflow Debug Report

**Run ID:** #[ID]
**Workflow:** [name]
**Status:** [status]

### Timeline
- Created: [timestamp]
- Started: [timestamp]
- Failed/Completed: [timestamp]
- Duration: [X seconds]

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

1. **Always start with `quick_debug`** - it's comprehensive and fast
2. **Check similar failures** - patterns reveal systemic issues
3. **Compare with working runs** - regressions show what changed
4. **Follow the data flow** - Trigger -> Queue -> Runner -> Execution -> Result
5. **Check timestamps** - correlate events across services
6. **Use request_id** - traces requests through all logs
