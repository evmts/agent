# Workflow System

Python-based workflow engine with plan-based execution. Workflows are evaluated in a restricted environment to produce deterministic execution plans (DAGs) that are executed by the runner system.

## Key Files

| File | Purpose |
|------|---------|
| `plan.zig` | Workflow plan types and DAG structures |
| `evaluator.zig` | Python workflow evaluation in sandboxed environment |
| `executor.zig` | Workflow execution engine with step orchestration |
| `llm_executor.zig` | LLM step execution with streaming |
| `prompt.zig` | Prompt template parsing and rendering |
| `validation.zig` | Workflow and plan validation |
| `registry.zig` | Workflow discovery and registration |
| `runner_pool.zig` | Warm runner pool management |
| `local_runner.zig` | Local runner for development |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Workflow System                              │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │   Registry   │───▶│  Evaluator   │───▶│    Executor      │  │
│  │              │    │              │    │                  │  │
│  │ • Discovery  │    │ • Python     │    │ • Step exec      │  │
│  │ • Validation │    │   sandbox    │    │ • DAG traversal  │  │
│  │ • Triggers   │    │ • Plan gen   │    │ • State mgmt     │  │
│  └──────────────┘    └──────────────┘    └────────┬─────────┘  │
│                                                    │            │
│  ┌──────────────┐    ┌──────────────┐             │            │
│  │    Prompt    │    │  Validation  │             │            │
│  │              │    │              │             │            │
│  │ • Templates  │    │ • Schema     │             │            │
│  │ • Variables  │    │ • Deps       │             │            │
│  │ • Rendering  │    │ • Cycles     │             │            │
│  └──────────────┘    └──────────────┘             │            │
│                                                    │            │
│                                                    ▼            │
│  ┌────────────────────────────────────────────────────────────┐│
│  │                    LLM Executor                            ││
│  │                                                            ││
│  │  • Claude API integration                                 ││
│  │  • Streaming token/tool events                            ││
│  │  • Tool execution (filesystem, git, etc.)                 ││
│  │  • Result aggregation                                     ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐│
│  │                  Runner Pool                               ││
│  │                                                            ││
│  │  • Warm pool of standby runners (K8s pods)                ││
│  │  • Claim/release lifecycle                                ││
│  │  • Health monitoring                                      ││
│  │  • Auto-scaling                                           ││
│  └────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Workflow Lifecycle

```
1. Workflow Definition (.plue.py)
   - Python file with workflow() function
   - Returns Plan with steps and triggers

   ▼

2. Registry Discovery
   - Scan repository for .plue.py files
   - Parse and validate syntax
   - Register triggers

   ▼

3. Event Trigger
   - GitHub push, PR, issue, schedule
   - Match against workflow triggers
   - Queue workflow run

   ▼

4. Evaluator
   - Execute workflow() in Python sandbox
   - Generate Plan (DAG of steps)
   - Validate plan structure

   ▼

5. Executor
   - Traverse DAG in topological order
   - Execute each step:
     * bash: Run shell command
     * llm: Execute LLM with tools
     * python: Run Python script
   - Handle dependencies and parallelism

   ▼

6. Runner Pool
   - Claim warm runner from pool
   - Stream logs to database
   - Release runner on completion

   ▼

7. Result Storage
   - Save step outputs
   - Log streaming events
   - Update workflow run status
```

## Plan Structure

```python
# .plue.py
def workflow():
    return Plan(
        name="CI Pipeline",
        triggers=[
            Trigger.on_push(branch="main"),
            Trigger.on_pull_request(),
        ],
        steps=[
            Step.bash("test", "npm test"),
            Step.bash("build", "npm run build", depends_on=["test"]),
            Step.llm(
                "review",
                prompt="Review the code changes",
                depends_on=["test"],
            ),
        ],
    )
```

Becomes a DAG:

```
      test
     /    \
  build  review
```

## Step Types

| Type | Description | Execution |
|------|-------------|-----------|
| `bash` | Shell command | Runner pod subprocess |
| `llm` | LLM agent | Claude API with tools |
| `python` | Python script | Runner pod Python interpreter |

## Execution Guarantees

- Steps execute in topological order respecting `depends_on`
- Failed steps block dependent steps
- Parallel execution when no dependencies
- Idempotent step execution (can retry)
- Deterministic plan generation (same input = same plan)

## Prompt System

Prompts are markdown files with frontmatter:

```markdown
---
name: code-review
description: Review code changes
schema:
  type: object
  properties:
    files:
      type: array
---

Review the following code changes:

{{#each files}}
## {{this.path}}
{{this.diff}}
{{/each}}
```

Rendered with Handlebars-style templates.
