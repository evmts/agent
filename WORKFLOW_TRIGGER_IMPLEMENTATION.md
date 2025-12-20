# Workflow Trigger Service Implementation

## Overview

The Workflow Trigger Service automatically triggers workflows when repository events occur. It discovers workflow files in `.plue/workflows/*.py`, parses their event triggers, and creates the necessary database records for execution by the runner system.

## Architecture

```
┌─────────────────┐
│ Repository Push │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Repo Watcher   │ (monitors .jj/op_heads for changes)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Workflow Trigger │ (discovers & triggers workflows)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Database      │ (workflow_runs, workflow_jobs, workflow_tasks)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Runner System  │ (picks up tasks & executes)
└─────────────────┘
```

## Files Created/Modified

### Created Files

1. **`server/src/services/workflow_trigger.zig`**
   - Main service implementation
   - Discovers workflows in `.plue/workflows/`
   - Parses Python workflow decorators
   - Creates database records

2. **`server/src/services/workflow_trigger.test.zig`**
   - Comprehensive unit tests
   - Tests workflow parsing, event matching, JSON serialization

3. **Example Workflow Files**
   - `server/test-repo/.plue/workflows/ci.py` - CI pipeline example
   - `server/test-repo/.plue/workflows/deploy.py` - Deployment workflow

### Modified Files

1. **`server/src/services/repo_watcher.zig`**
   - Added `WorkflowTrigger` import
   - Added `triggerPushWorkflows()` method
   - Integrated workflow triggering after successful sync

## Service Components

### WorkflowTrigger

Main service struct that handles workflow discovery and triggering.

```zig
pub const WorkflowTrigger = struct {
    allocator: std.mem.Allocator,
    pool: *db.Pool,

    pub fn triggerWorkflows(
        self: *WorkflowTrigger,
        repo_id: i64,
        event: []const u8,
        ref: ?[]const u8,
        commit_sha: ?[]const u8,
        trigger_user_id: ?i64,
    ) !void
};
```

### WorkflowMetadata

Struct representing discovered workflow information:

```zig
pub const WorkflowMetadata = struct {
    name: []const u8,
    file_path: []const u8,
    events: []const []const u8,
    is_agent_workflow: bool,
    allocator: std.mem.Allocator,
};
```

### WorkflowEvent

Enum for supported event types:

```zig
pub const WorkflowEvent = enum {
    push,
    pull_request,
    issue,
    chat,
};
```

## Workflow Discovery

The service discovers workflows by:

1. Looking for `.plue/workflows/*.py` files in the repository
2. Parsing Python files for `@workflow` decorators
3. Extracting metadata:
   - Workflow name
   - Event triggers (`on=["push", "pull_request"]`)
   - Agent flag (`agent=True`)

### Supported Decorator Format

```python
@workflow(name="CI Pipeline", on=["push", "pull_request"])
async def ci(ctx):
    pass
```

### Parsing Logic

The parser uses simple string matching to extract:
- `name="..."` - Workflow display name
- `on=[...]` - List of triggering events
- `agent=True` - Whether this is an AI agent workflow

## Database Integration

### Tables Used

1. **`workflow_definitions`**
   - Stores workflow metadata
   - Links to repository
   - Contains event list as JSONB

2. **`workflow_runs`**
   - Top-level run record
   - Contains trigger info, status, timing

3. **`workflow_jobs`**
   - Jobs within a run
   - Links to run_id

4. **`workflow_tasks`**
   - Actual execution tasks
   - Contains workflow Python source
   - Picked up by runners

### Status Flow

```
waiting (5) → running (6) → success (1) / failure (2) / cancelled (3)
```

## Integration with Repo Watcher

The workflow trigger is called after successful repository sync:

```zig
// In syncToDatabase()
self.triggerPushWorkflows(watched_repo, workspace) catch |err| {
    log.warn("Failed to trigger workflows: {}", .{err});
};
```

### Trigger Logic

1. Get latest commit SHA from jj
2. Get current branch/bookmark as ref
3. Initialize WorkflowTrigger
4. Call `triggerWorkflows()` with "push" event
5. Service discovers matching workflows
6. Creates database records for each match

## Example Workflows

### CI Workflow

```python
@workflow(name="CI Pipeline", on=["push", "pull_request"])
async def ci(ctx):
    await ctx.step(checkout)
    await ctx.step(install_deps)
    await ctx.step(run_tests)
    await ctx.step(build)
```

### Deploy Workflow

```python
@workflow(name="Deploy to Production", on=["push"])
async def deploy(ctx):
    if ctx.ref != "main":
        return  # Only deploy from main

    await ctx.step(build_docker)
    await ctx.step(push_docker)
    await ctx.step(deploy_k8s)
```

## Testing

### Unit Tests

Run workflow trigger tests:

```bash
zig build test:server
```

Key test cases:
- Workflow file parsing with decorators
- Event matching logic
- JSON serialization of events
- Agent workflow detection
- Fallback name generation

### Integration Testing

To test the full flow:

1. Create a test repository with `.plue/workflows/` directory
2. Add a workflow file with `@workflow` decorator
3. Make a commit/push to the repository
4. Verify workflow_run is created in database
5. Check runner picks up the task

## Configuration

No configuration required. The service uses:
- Repository path from database
- `.plue/workflows/` as fixed directory
- `*.py` files as workflow files

## Error Handling

The service handles:
- Missing `.plue/workflows/` directory (returns empty list)
- Invalid Python files (uses filename as fallback name)
- Database errors (logged and propagated)
- Parse errors (graceful degradation)

## Performance Considerations

- Workflow discovery runs on every repo sync
- Limited to repositories with actual changes
- Parser is simple string matching (fast)
- Database queries are batched where possible

## Future Enhancements

Potential improvements:

1. **Caching**: Cache workflow definitions to avoid re-parsing
2. **AST Parsing**: Use proper Python AST parser instead of string matching
3. **Validation**: Validate workflow syntax before creating records
4. **Concurrency**: Handle concurrency groups and cancellation
5. **Filters**: Support branch/path filters (`if: github.ref == 'refs/heads/main'`)
6. **Manual Triggers**: API endpoint to manually trigger workflows

## Debugging

Enable debug logging:

```bash
RUST_LOG=server::services::workflow_trigger=debug ./server
```

Log messages:
- "Triggering workflows for repo {d}, event: {s}"
- "Discovered {d} workflow(s)"
- "Triggered {d} workflow(s) for event: {s}"
- "Created workflow run {d} for workflow: {s}"

## Dependencies

- `std` - Zig standard library
- `db` - PostgreSQL database layer
- `jj-ffi` - jj VCS C bindings (indirect, via repo_watcher)

## API

No direct HTTP API. Triggered internally by repo_watcher service.

Future API endpoints could include:
- `POST /api/repos/:user/:repo/workflows/trigger` - Manual trigger
- `GET /api/repos/:user/:repo/workflows` - List workflows
- `GET /api/repos/:user/:repo/workflows/definitions` - Get definitions

## Success Criteria

✅ Workflow files are discovered automatically
✅ Events are parsed from decorator
✅ Database records are created correctly
✅ Runner can pick up tasks
✅ Unit tests pass
✅ Integration with repo_watcher works

## Known Limitations

1. **Simple Parser**: Uses string matching, not a real Python parser
2. **No Validation**: Doesn't validate Python syntax
3. **Fixed Directory**: Only looks in `.plue/workflows/`
4. **No Hot Reload**: Requires repo sync to detect new workflows
5. **Limited Events**: Only basic event types supported

## References

- Database Schema: `/Users/williamcory/agent/db/schema.sql`
- Runner Implementation: `/Users/williamcory/agent/runner/`
- Workflow Decorators: `/Users/williamcory/agent/runner/plue/workflow.py`
- Repo Watcher: `/Users/williamcory/agent/server/src/services/repo_watcher.zig`
