---
name: runner
description: Plue Python agent runner. Use when working on workflow execution, agent tools, or sandboxed code execution in Kubernetes.
---

# Plue Runner (Agent Execution)

Python-based agent execution environment that runs in sandboxed Kubernetes pods (gVisor).

## Entry Point

- Main: `runner/src/main.py`
- Agent: `runner/src/agent.py`
- Workflow: `runner/src/workflow.py`
- Streaming: `runner/src/streaming.py`

## Architecture

```
API Server                    Kubernetes
    │                             │
    ├─ POST /api/workflows/run ───┤
    │                             │
    ▼                             ▼
TaskQueue ────────────────► RunnerPool
    │                             │
    │                             ▼
    │                      Warm Runner Pods
    │                      (gVisor sandbox)
    │                             │
    └──────── Stream ◄────────────┘
             Events
```

## Runner Pool

The server maintains a pool of warm runners:

```zig
// server/src/workflows/runner_pool.zig
pub const RunnerPool = struct {
    available: ArrayList(RunnerInfo),
    claimed: HashMap(TaskId, RunnerInfo),

    pub fn claimRunner(self: *Self, task_id: TaskId) !?RunnerInfo
    pub fn releaseRunner(self: *Self, runner_id: RunnerId) !void
};
```

## Task Flow

1. **Task Created**: Workflow run creates task in database
2. **Runner Claims**: Available runner polls for tasks
3. **Execution**: Runner executes workflow steps
4. **Streaming**: Events streamed back to API via internal endpoints
5. **Completion**: Task marked complete, runner released to pool

## Python Agent

```python
# runner/src/agent.py
class Agent:
    def __init__(self, session_id: str, api_url: str):
        self.session_id = session_id
        self.tools = load_tools()

    async def run(self, prompt: str) -> AsyncIterator[Event]:
        # Execute with Anthropic API
        # Stream events back
        pass
```

## Tools

Located in `runner/src/tools/`:

| Tool | Purpose |
|------|---------|
| `bash.py` | Execute shell commands |
| `read_file.py` | Read file contents |
| `write_file.py` | Write files |
| `grep.py` | Search files |
| `web_fetch.py` | HTTP requests |

## Workflow Execution

```python
# runner/src/workflow.py
class WorkflowExecutor:
    def __init__(self, workflow_def: WorkflowDefinition):
        self.steps = workflow_def.steps
        self.context = {}

    async def execute(self) -> AsyncIterator[StepResult]:
        for step in self.topological_sort(self.steps):
            result = await self.execute_step(step)
            self.context[step.id] = result
            yield result
```

## Streaming Protocol

```python
# runner/src/streaming.py
class EventStreamer:
    async def emit(self, event: Event):
        # POST to API internal endpoint
        await self.post(f'/internal/tasks/{self.task_id}/stream', event)

    async def complete(self, result: TaskResult):
        await self.post(f'/internal/tasks/{self.task_id}/complete', result)
```

## Internal API Endpoints

Used by runners to communicate with server:

| Endpoint | Purpose |
|----------|---------|
| `POST /internal/runners/register` | Register runner on startup |
| `POST /internal/runners/:pod/heartbeat` | Keep-alive |
| `POST /internal/tasks/:id/stream` | Stream execution events |
| `POST /internal/tasks/:id/complete` | Mark task complete |

## Kubernetes Deployment

Runners deploy as pods with gVisor:

```yaml
# infra/k8s/runner-pod.yaml
apiVersion: v1
kind: Pod
spec:
  runtimeClassName: gvisor  # Sandboxed runtime
  containers:
  - name: runner
    image: plue-runner:latest
    env:
    - name: PLUE_API_URL
      value: "http://api:4000"
```

## Warm Pool Configuration

```zig
// server/src/workflows/runner_pool.zig
pub const PoolConfig = struct {
    min_warm: u32 = 2,      // Minimum warm runners
    max_warm: u32 = 10,     // Maximum warm runners
    idle_timeout_ms: u64 = 300_000,  // 5 min idle timeout
};
```

## Local Development

For local testing without K8s:

```zig
// server/src/workflows/local_runner.zig
pub const LocalRunner = struct {
    // Executes workflows in local process
    // Used when K8s runners unavailable
};
```

## Environment Variables

```bash
PLUE_API_URL=http://api:4000    # API server URL
ANTHROPIC_API_KEY=sk-ant-...    # For LLM calls
RUNNER_POD_NAME=runner-abc123   # Pod identifier
```
