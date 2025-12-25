# Plue Runner

Python agent execution environment running in gVisor-sandboxed K8s pods.

## Purpose

The runner executes Claude-powered AI agents and scripted workflows in isolated
containers, streaming results back to the Zig API server in real-time.

## Architecture

```
                 ┌─────────────────┐
                 │   Zig Server    │
                 └────────┬────────┘
                          │
         ┌────────────────┼────────────────┐
         │                                  │
    ┌────▼─────┐                     ┌─────▼────┐
    │  Assign  │                     │ Callback │
    │   Task   │                     │   URL    │
    └────┬─────┘                     └─────▲────┘
         │                                  │
    ┌────▼──────────────────────────────────┴────┐
    │      K8s Pod (gVisor sandbox)              │
    │  ┌──────────────────────────────────────┐  │
    │  │            Runner Process            │  │
    │  │  ┌────────────┐   ┌───────────────┐ │  │
    │  │  │   Agent    │   │   Workflow    │ │  │
    │  │  │   Runner   │   │   Runner      │ │  │
    │  │  └──────┬─────┘   └───────┬───────┘ │  │
    │  │         │                 │         │  │
    │  │         └────────┬────────┘         │  │
    │  │                  │                  │  │
    │  │         ┌────────▼────────┐         │  │
    │  │         │  Tools (sandboxed) │      │  │
    │  │         │  - read_file       │      │  │
    │  │         │  - write_file      │      │  │
    │  │         │  - list_files      │      │  │
    │  │         │  - grep            │      │  │
    │  │         │  - shell           │      │  │
    │  │         └────────────────────┘      │  │
    │  └──────────────────────────────────────┘  │
    │                                            │
    │  /workspace (repository checkout)         │
    └───────────────────────────────────────────┘
```

## Execution Modes

| Mode     | Description                                    |
|----------|------------------------------------------------|
| active   | Execute a task immediately (TASK_ID required)  |
| standby  | Wait for assignment from API server (warm pool)|

## Configuration

Environment variables:

| Variable          | Required | Description                           |
|-------------------|----------|---------------------------------------|
| MODE              | No       | "active" or "standby" (default: active)|
| TASK_ID           | Active   | Task identifier                       |
| CALLBACK_URL      | Active   | URL to stream results back to         |
| ANTHROPIC_API_KEY | Yes      | API key for Claude                    |
| REGISTER_URL      | Standby  | URL to register as standby runner     |
| LOG_LEVEL         | No       | Logging verbosity (default: INFO)     |
| REQUEST_ID        | No       | Request ID for distributed tracing    |

## Task Types

### Agent Tasks

Execute Claude-powered agents with tool use:

```json
{
  "type": "agent",
  "model": "claude-sonnet-4-20250514",
  "system_prompt": "You are a helpful assistant.",
  "messages": [{"role": "user", "content": "Fix the bug"}],
  "tools": ["read_file", "write_file", "grep"],
  "max_turns": 20
}
```

### Workflow Tasks

Execute scripted CI/CD workflows:

```json
{
  "type": "workflow",
  "steps": [
    {"type": "run", "run": "npm test"},
    {"type": "run", "run": "npm run build"}
  ]
}
```

## Security Model

```
┌───────────────────────────────────────┐
│  gVisor Sandbox                       │
│  - Filesystem restricted to /workspace│
│  - Network limited to callback URL    │
│  - Resource limits enforced           │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  Tool Path Validation           │  │
│  │  - Realpath resolution          │  │
│  │  - Workspace boundary checks    │  │
│  │  - Symlink protection           │  │
│  └─────────────────────────────────┘  │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  Input Validation               │  │
│  │  - Model whitelist              │  │
│  │  - Tool whitelist               │  │
│  │  - Config schema validation     │  │
│  └─────────────────────────────────┘  │
└───────────────────────────────────────┘
```

## Key Files

| File           | Purpose                                      |
|----------------|----------------------------------------------|
| main.py        | Entry point, task orchestration              |
| agent.py       | Claude agent execution with tool use         |
| workflow.py    | Scripted workflow execution                  |
| streaming.py   | HTTP streaming client with retry logic       |
| logger.py      | Structured JSON logging                      |
| tools/         | Sandboxed tool implementations               |
| tests/         | Security and functionality tests             |

## Dependencies

```toml
anthropic    # Claude API client
httpx        # HTTP client for streaming
pyyaml       # Workflow YAML parsing
pytest       # Testing framework
```

Managed via uv (fast Python package manager).

## Development

```bash
# Install dependencies
uv sync

# Run tests
uv run pytest

# Run locally (requires mock environment)
uv run python -m runner
```

## Streaming Protocol

Events sent to CALLBACK_URL:

| Event Type   | Description                          |
|--------------|--------------------------------------|
| token        | Text delta from Claude response      |
| tool_start   | Tool execution beginning             |
| tool_end     | Tool execution complete              |
| step_start   | Workflow step beginning              |
| step_end     | Workflow step complete               |
| log          | Log message (stdout/stderr/info)     |
| done         | Task completed successfully          |
| error        | Task failed with error               |

Critical events (done, error, tool_end) are retried up to 10 times with
exponential backoff.

## Allowed Models

- claude-sonnet-4-20250514
- claude-3-5-sonnet-20241022
- claude-3-5-haiku-20241022
- claude-3-opus-20240229

## Allowed Tools

- read_file
- write_file
- list_files
- grep
- shell
