# Plue Workflows: Engineering Design

Technical specification for implementing a Python-syntax workflow system with a Jinja2-compatible prompt format, executed by the Zig service with Rust/C helpers.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [RestrictedPython Runtime](#restrictedpython-runtime)
3. [Jinja2 Prompt Parser](#jinja2-prompt-parser)
4. [Type System](#type-system)
5. [Plan Generation](#plan-generation)
6. [Execution Engine](#execution-engine)
7. [AI-First Features](#ai-first-features)
8. [Tool System](#tool-system)
9. [Streaming Protocol](#streaming-protocol)
10. [Storage Schema](#storage-schema)
11. [API Specification](#api-specification)

---

## Architecture Overview

### System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER INTERFACE                                   │
│                                                                               │
│   IDE                    Web UI                    CLI                        │
│   ├─ .py editing         ├─ Run history           ├─ plue workflow run       │
│   ├─ .prompt.md editing  ├─ Live streaming        ├─ plue prompt preview     │
│   └─ Type hints          └─ Agent chat view       └─ plue dev                │
└───────────────────────────────────────┬───────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ZIG SERVER                                       │
│                                                                               │
│  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────────────┐ │
│  │   Workflow API    │  │ Workflow Runtime │  │   Prompt Parser           │ │
│  │                   │  │ (RestrictedPython)│  │   (Rust/C + Jinja2)       │ │
│  │  POST /run        │  │                   │  │  - Frontmatter (YAML)     │ │
│  │  GET /status      │  │  Sandboxed eval   │  │  - Body (Jinja2)          │ │
│  │  SSE /stream      │  │  Plan generation  │  │  - Schema validation      │ │
│  └───────────────────┘  └───────────────────┘  └───────────────────────────┘ │
│           │                      │                         │                  │
│           └──────────────────────┼─────────────────────────┘                  │
│                                  │                                            │
│                                  ▼                                            │
│  ┌───────────────────────────────────────────────────────────────────────┐   │
│  │                        EXECUTION ENGINE                                │   │
│  │                                                                        │   │
│  │   1. Receive Plan (DAG of steps)                                      │   │
│  │   2. Topological sort                                                 │   │
│  │   3. Dispatch to runner pods                                          │   │
│  │   4. Handle LLM steps specially (streaming, tools)                    │   │
│  │   5. Stream results back via SSE                                      │   │
│  └───────────────────────────────────────────────────────────────────────┘   │
│                                  │                                            │
└──────────────────────────────────┼────────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────────────┐
│         POSTGRES                │  │              K8s RUNNER PODS             │
│                                 │  │                                          │
│  workflow_definitions           │  │  ┌────────────────────────────────────┐  │
│  workflow_runs                  │  │  │         RUNNER PROCESS             │  │
│  workflow_steps                 │  │  │                                    │  │
│  workflow_logs                  │  │  │  Shell steps:                      │  │
│  prompt_cache                   │  │  │    Execute command, stream output  │  │
│  llm_usage                      │  │  │                                    │  │
│                                 │  │  │  Agent steps:                      │  │
│                                 │  │  │    Claude Code SDK loop            │  │
│                                 │  │  │    Tool execution                  │  │
│                                 │  │  │    Token streaming                 │  │
│                                 │  │  └────────────────────────────────────┘  │
│                                 │  │                                          │
└─────────────────────────────────┘  │  gVisor sandbox, network isolation       │
                                     └──────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Language | Responsibility |
|-----------|----------|----------------|
| Zig Server | Zig | HTTP API, orchestration, SSE streaming |
| Workflow Runtime | Zig | RestrictedPython-compatible plan generation |
| Prompt Parser | Rust/C (via Zig FFI) | Parse .prompt.md files, render templates |
| Execution Engine | Zig | Execute DAG, dispatch to runners |
| Runner | Zig | Execute steps, Claude Code SDK for agents |
| Postgres | SQL | Persist definitions, runs, logs, LLM usage |

---

## RestrictedPython Runtime

### Integration with Zig

Workflow plan generation runs inside the Zig service. We preserve RestrictedPython semantics, but the evaluator is embedded and invoked by Zig (no separate Python service). The interpreter can be implemented as:

- a restricted Python subset using RustPython (via FFI), or
- a custom AST evaluator that accepts the Plue DSL and enforces the same sandbox rules.

### Plan Evaluator (Zig service)

```zig
// workflow_eval.zig (conceptual)
pub fn evaluateWorkflow(source_path: []const u8) !PlanSet {
    const source = try fs.readFileAlloc(allocator, source_path, max_size);

    const module = try restricted.compile(source); // RestrictedPython-compatible
    var globals = try plueBuiltins(); // registered decorators + helpers

    try restricted.exec(module, &globals);

    return try extractPlans(globals);
}
```

### Plue Builtins Module

The builtins below are reference shapes; the production implementation lives in Zig with equivalent structs and APIs.

```python
# plue_builtins (conceptual)

from RestrictedPython import safe_builtins
from typing import Any, Callable, Dict, List, Optional
from dataclasses import dataclass, field

# Global registry for workflows
_workflows: Dict[str, 'WorkflowDef'] = {}


@dataclass
class Schema:
    """Starlark-like schema definition."""
    fields: Dict[str, Any]

    def to_json_schema(self) -> dict:
        """Convert to JSON Schema for validation."""
        properties = {}
        required = []

        for name, type_info in self.fields.items():
            properties[name] = type_info.to_json_schema()
            if not isinstance(type_info, OptionalType):
                required.append(name)

        return {
            "type": "object",
            "properties": properties,
            "required": required,
        }


@dataclass
class EnumType:
    values: List[str]

    def to_json_schema(self) -> dict:
        return {"type": "string", "enum": self.values}


@dataclass
class ListType:
    item_type: Any

    def to_json_schema(self) -> dict:
        return {"type": "array", "items": self.item_type.to_json_schema()}


@dataclass
class OptionalType:
    inner_type: Any

    def to_json_schema(self) -> dict:
        return {"anyOf": [self.inner_type.to_json_schema(), {"type": "null"}]}


@dataclass
class Step:
    """A step in the workflow plan."""
    id: str
    name: str
    step_type: str  # "shell", "llm", "agent", "parallel"
    config: dict
    depends_on: List[str] = field(default_factory=list)


@dataclass
class WorkflowDef:
    """Workflow definition produced by @workflow decorator."""
    name: str
    triggers: List[dict]
    image: Optional[str]
    dockerfile: Optional[str]
    steps: List[Step] = field(default_factory=list)

    def to_plan(self) -> dict:
        return {
            "name": self.name,
            "triggers": self.triggers,
            "image": self.image or "ubuntu:22.04",
            "dockerfile": self.dockerfile,
            "steps": [
                {
                    "id": s.id,
                    "name": s.name,
                    "type": s.step_type,
                    "config": s.config,
                    "depends_on": s.depends_on,
                }
                for s in self.steps
            ],
        }


class Context:
    """
    Workflow context - methods register steps, don't execute them.
    """

    def __init__(self, workflow_def: WorkflowDef, event: dict):
        self._workflow = workflow_def
        self._step_counter = 0
        self.event = _make_event(event)
        self.git = _GitContext()
        self.pr = _PrContext()
        self.issue = _IssueContext()

    def _next_step_id(self) -> str:
        self._step_counter += 1
        return f"step_{self._step_counter}"

    def run(
        self,
        name: str,
        cmd: str,
        env: Optional[Dict[str, str]] = None,
        cache: Optional[str] = None,
        depends_on: Optional[List[Step]] = None,
    ) -> Step:
        """Register a shell step."""
        step = Step(
            id=self._next_step_id(),
            name=name,
            step_type="shell",
            config={
                "cmd": cmd,
                "env": env or {},
                "cache": cache,
            },
            depends_on=[s.id for s in (depends_on or [])],
        )
        self._workflow.steps.append(step)
        return step

    def parallel(self, steps: List[Step]) -> Step:
        """Register a parallel group."""
        step = Step(
            id=self._next_step_id(),
            name="parallel",
            step_type="parallel",
            config={"step_ids": [s.id for s in steps]},
            depends_on=[],  # Parallel steps handle their own deps
        )
        self._workflow.steps.append(step)
        return step

    def read(self, path: str) -> str:
        """
        Returns a placeholder - actual read happens at execution time.
        """
        return f"{{{{ file:{path} }}}}"

    def exists(self, path: str) -> bool:
        """
        For plan generation, we can't know if file exists.
        Return True to include conditional branches in plan.
        """
        return True

    def secret(self, name: str) -> str:
        """Returns a placeholder for secret injection."""
        return f"{{{{ secret:{name} }}}}"

    def success(self, **outputs) -> dict:
        return {"status": "success", "outputs": outputs}

    def fail(self, reason: str) -> dict:
        return {"status": "fail", "reason": reason}


def workflow(
    triggers: List[dict],
    image: Optional[str] = None,
    dockerfile: Optional[str] = None,
):
    """
    Decorator to register a workflow.
    """
    def decorator(fn: Callable) -> Callable:
        workflow_def = WorkflowDef(
            name=fn.__name__,
            triggers=triggers,
            image=image,
            dockerfile=dockerfile,
        )

        # Create mock event for plan generation
        mock_event = {"type": "push", "ref": "refs/heads/main", "sha": "abc123"}
        ctx = Context(workflow_def, mock_event)

        # Execute function to build plan
        fn(ctx)

        # Register workflow
        _workflows[fn.__name__] = workflow_def

        return fn

    return decorator


# Trigger helpers
def push(branches: Optional[List[str]] = None) -> dict:
    return {"type": "push", "branches": branches}


def pull_request(types: Optional[List[str]] = None) -> dict:
    return {"type": "pull_request", "types": types or ["opened", "synchronize"]}


def issue_comment(contains: Optional[str] = None) -> dict:
    return {"type": "issue_comment", "contains": contains}


def manual(inputs: Optional[Dict[str, type]] = None) -> dict:
    return {"type": "manual", "inputs": inputs or {}}


def schedule(cron: str) -> dict:
    return {"type": "schedule", "cron": cron}


# Type system helpers
def schema(**fields) -> Schema:
    return Schema(fields=fields)


def enum(*values) -> EnumType:
    return EnumType(values=list(values))


def list_(item_type) -> ListType:
    return ListType(item_type=item_type)


def optional(inner_type) -> OptionalType:
    return OptionalType(inner_type=inner_type)


# Cache helpers
def cache_key(*parts) -> str:
    return ":".join(str(p) for p in parts)


def hash_files(pattern: str) -> str:
    return f"{{{{ hash_files:{pattern} }}}}"


def create_plue_globals() -> dict:
    """Create the restricted globals for workflow evaluation."""
    from RestrictedPython import safe_builtins

    return {
        "__builtins__": safe_builtins,
        "__plue_workflows__": _workflows,

        # Decorators
        "workflow": workflow,
        "tool": tool,

        # Triggers
        "push": push,
        "pull_request": pull_request,
        "issue_comment": issue_comment,
        "manual": manual,
        "schedule": schedule,

        # Type system
        "schema": schema,
        "enum": enum,
        "list": list_,
        "optional": optional,
        "str": str,
        "int": int,
        "float": float,
        "bool": bool,

        # Helpers
        "cache_key": cache_key,
        "hash_files": hash_files,
    }
```

---

## Jinja2 Prompt Parser

### File Format

```
┌─────────────────────────────────────────────────────────────────┐
│                    .prompt.md file                               │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  ---                                                       │  │
│  │  name: CodeReview                 ◄─── YAML Frontmatter    │  │
│  │  client: anthropic/claude-sonnet                           │  │
│  │  inputs:                                                   │  │
│  │    diff: string                                            │  │
│  │  output:                                                   │  │
│  │    approved: boolean                                       │  │
│  │  ---                                                       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Review this code:                 ◄─── Jinja2 Body        │  │
│  │                                                            │  │
│  │  {% if context %}                                          │  │
│  │  ## Context                                                │  │
│  │  {{ context }}                                             │  │
│  │  {% endif %}                                               │  │
│  │                                                            │  │
│  │  ```diff                                                   │  │
│  │  {{ diff }}                                                │  │
│  │  ```                                                       │  │
│  │                                                            │  │
│  │  {{ output_schema }}                                       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Parser Implementation (Zig + Rust/C)

The prompt parser runs inside the Zig service and uses a Rust/C Jinja2-compatible engine (for example, minijinja) via FFI. YAML frontmatter is parsed with a Rust or C YAML library, and templates are cached by path + mtime.

High-level steps:
1. Read file and split frontmatter/body.
2. Parse YAML frontmatter into a PromptDefinition.
3. Compile the Jinja2 template body.
4. Render with inputs + injected output schema.

```rust
// prompt_parser.rs (conceptual, called from Zig)
fn parse_prompt(path: &Path) -> PromptDefinition {
    let (frontmatter, body) = split_frontmatter(read_to_string(path));
    let fm: Frontmatter = serde_yaml::from_str(&frontmatter)?;
    let template = minijinja::Environment::new().template_from_str(&body)?;

    PromptDefinition {
        name: fm.name,
        client: fm.client.unwrap_or("anthropic/claude-sonnet"),
        prompt_type: fm.prompt_type.unwrap_or("llm"),
        inputs: parse_schema(fm.inputs),
        output: parse_schema(fm.output),
        tools: fm.tools,
        max_turns: fm.max_turns.unwrap_or(10),
        body_template: template,
        extends: fm.extends,
    }
}
```

---

## AI-First Features

Note: Code samples below are pseudocode for readability. The production implementation is Zig (runner + server) with Rust/C helpers where needed.

### LLM Step in Plan

When a prompt is called in a workflow, it registers as an LLM step (like a GitHub Actions step):

```python
# In workflow
from plue.prompts import CodeReview
from plue.tools import read_file, grep, glob, websearch

@workflow(triggers=[pull_request()])
def review(ctx):
    # This registers an LLM step, not immediate execution
    # Tools are scoped to the PR head ref (like actions/checkout@v4)
    review = CodeReview(
        diff=ctx.git.diff(base=ctx.event.pull_request.base),
        focus="security",
        focus_description="Security vulnerabilities",
        checks=["XSS", "SQL injection", "Auth bypass"],
        tools=[
            read_file(repo=ctx.repo, ref=ctx.event.pull_request.head),
            grep(repo=ctx.repo, ref=ctx.event.pull_request.head),
            glob(repo=ctx.repo, ref=ctx.event.pull_request.head),
            websearch(),
        ],
        max_turns=10,
    )
```

The generated plan includes (similar to GitHub Actions job steps):

```json
{
  "steps": [
    {
      "id": "step_1",
      "name": "CodeReview",
      "type": "agent",
      "config": {
        "prompt_path": ".plue/prompts/CodeReview.prompt.md",
        "inputs": {
          "diff": "{{ git.diff(base=event.pull_request.base) }}",
          "focus": "security",
          "focus_description": "Security vulnerabilities",
          "checks": ["XSS", "SQL injection", "Auth bypass"]
        },
        "client": "anthropic/claude-sonnet",
        "tools": [
          {"name": "read_file", "repo": "{{ repo }}", "ref": "{{ event.pull_request.head }}"},
          {"name": "grep", "repo": "{{ repo }}", "ref": "{{ event.pull_request.head }}"},
          {"name": "glob", "repo": "{{ repo }}", "ref": "{{ event.pull_request.head }}"},
          {"name": "websearch"}
        ],
        "max_turns": 10
      }
    }
  ]
}
```

### Agent Step with Tools

Agent steps include tool definitions:

```json
{
  "id": "step_2",
  "name": "FixBuildErrors",
  "type": "agent",
  "config": {
    "prompt_path": ".plue/prompts/fix-errors.prompt.md",
    "inputs": {
      "goal": "Fix the build",
      "errors": "{{ steps.build.stderr }}"
    },
    "client": "anthropic/claude-sonnet",
    "tools": [
      {"name": "read_file", "builtin": true},
      {"name": "write_file", "builtin": true},
      {"name": "shell", "builtin": true, "config": {"allow": ["zig", "git"]}},
      {"name": "run-tests", "path": "//tools:run-tests"}
    ],
    "max_turns": 20
  }
}
```

### Prompt Auto-Import

Prompts in `.plue/prompts/` are auto-imported into `plue.prompts`:

```python
# This import is resolved at plan time
from plue.prompts import CodeReview, SecurityAudit, FixBuildErrors

# Each becomes a callable that registers an LLM/agent step
review = CodeReview(diff=ctx.git.diff())
```

Implementation:

```python
# plue/prompts/__init__.py (generated or dynamic)

class PromptFunction:
    """Wrapper that registers LLM step when called."""

    def __init__(self, definition: PromptDefinition):
        self.definition = definition

    def __call__(self, **inputs) -> 'StepResult':
        # Get current workflow context
        ctx = _get_current_context()

        # Register step
        step = Step(
            id=ctx._next_step_id(),
            name=self.definition.name,
            step_type="agent" if self.definition.prompt_type == "agent" else "llm",
            config={
                "prompt_path": self.definition.path,
                "inputs": inputs,
                "client": self.definition.client,
                "tools": self.definition.tools,
                "max_turns": self.definition.max_turns,
            },
        )
        ctx._workflow.steps.append(step)

        # Return a result proxy with typed attributes
        return StepResult(step, self.definition.output)
```

### Streaming Agent Execution

During execution phase, agent steps use Claude Code SDK:

```python
# runner/agent_executor.py

from anthropic import Anthropic
from claude_code import Agent, Tool

class AgentExecutor:
    def __init__(self, client: Anthropic, stream_callback):
        self.client = client
        self.stream_callback = stream_callback

    async def execute(
        self,
        prompt: str,
        tools: List[Tool],
        max_turns: int,
        output_schema: dict,
    ) -> dict:
        """Execute agent loop with streaming."""

        messages = [{"role": "user", "content": prompt}]
        turn = 0

        while turn < max_turns:
            # Stream response
            response = await self._stream_response(messages, tools)

            # Check for tool calls
            if response.stop_reason == "tool_use":
                tool_results = await self._execute_tools(response.tool_calls)

                # Stream tool results
                for result in tool_results:
                    self.stream_callback({
                        "type": "tool_result",
                        "tool": result.tool_name,
                        "output": result.output,
                    })

                messages.append({"role": "assistant", "content": response.content})
                messages.append({"role": "user", "content": tool_results})

            else:
                # Agent finished
                return self._parse_output(response.content, output_schema)

            turn += 1

        raise MaxTurnsExceeded(turn)

    async def _stream_response(self, messages, tools):
        """Stream tokens from Claude."""
        async with self.client.messages.stream(
            model="claude-sonnet-4-20250514",
            max_tokens=4096,
            messages=messages,
            tools=[t.to_anthropic() for t in tools],
        ) as stream:
            async for event in stream:
                if event.type == "content_block_delta":
                    if event.delta.type == "text_delta":
                        self.stream_callback({
                            "type": "token",
                            "text": event.delta.text,
                        })

            return await stream.get_final_message()
```

---

## Tool System

### Built-in Tools

Tools mirror GitHub Actions patterns where applicable:

| Tool | Description | Scoped to Ref? |
|------|-------------|----------------|
| `read_file` | Read file from repo | Yes |
| `write_file` | Write file to workspace | No |
| `shell` | Execute command | No |
| `glob` | Find files by pattern | Yes |
| `grep` | Search file contents | Yes |
| `websearch` | Search the web | No |

```python
# runner/tools/builtins.py

from dataclasses import dataclass
from typing import Any, Dict

@dataclass
class ToolResult:
    success: bool
    output: Any
    error: Optional[str] = None


class ReadFileTool:
    name = "read_file"
    description = "Read the contents of a file"

    def execute(self, path: str, workspace: str) -> ToolResult:
        try:
            full_path = os.path.join(workspace, path)
            with open(full_path) as f:
                return ToolResult(success=True, output=f.read())
        except Exception as e:
            return ToolResult(success=False, output=None, error=str(e))


class WriteFileTool:
    name = "write_file"
    description = "Write content to a file"

    def execute(self, path: str, content: str, workspace: str) -> ToolResult:
        try:
            full_path = os.path.join(workspace, path)
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            with open(full_path, 'w') as f:
                f.write(content)
            return ToolResult(success=True, output=f"Wrote {len(content)} bytes to {path}")
        except Exception as e:
            return ToolResult(success=False, output=None, error=str(e))


class ShellTool:
    name = "shell"
    description = "Execute a shell command"

    def __init__(self, allowed_commands: List[str] = None):
        self.allowed_commands = allowed_commands

    def execute(self, command: str, workspace: str) -> ToolResult:
        # Validate command if restrictions exist
        if self.allowed_commands:
            cmd_name = command.split()[0]
            if cmd_name not in self.allowed_commands:
                return ToolResult(
                    success=False,
                    output=None,
                    error=f"Command '{cmd_name}' not in allowed list: {self.allowed_commands}"
                )

        try:
            result = subprocess.run(
                command,
                shell=True,
                cwd=workspace,
                capture_output=True,
                text=True,
                timeout=300,
            )
            return ToolResult(
                success=result.returncode == 0,
                output={
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "exit_code": result.returncode,
                },
            )
        except subprocess.TimeoutExpired:
            return ToolResult(success=False, output=None, error="Command timed out")
        except Exception as e:
            return ToolResult(success=False, output=None, error=str(e))


class GlobTool:
    name = "glob"
    description = "Find files matching a pattern"

    def execute(self, pattern: str, workspace: str) -> ToolResult:
        import glob
        matches = glob.glob(os.path.join(workspace, pattern), recursive=True)
        relative = [os.path.relpath(m, workspace) for m in matches]
        return ToolResult(success=True, output=relative)


class GrepTool:
    name = "grep"
    description = "Search for pattern in files"

    def execute(self, pattern: str, path: str, workspace: str) -> ToolResult:
        try:
            result = subprocess.run(
                ["grep", "-rn", pattern, path],
                cwd=workspace,
                capture_output=True,
                text=True,
            )
            return ToolResult(success=True, output=result.stdout)
        except Exception as e:
            return ToolResult(success=False, output=None, error=str(e))


class WebSearchTool:
    """Web search tool - uses external search API."""
    name = "websearch"
    description = "Search the web for information"

    def __init__(self, api_key: str = None):
        self.api_key = api_key or os.environ.get("SEARCH_API_KEY")

    def execute(self, query: str) -> ToolResult:
        try:
            # Use search API (e.g., Brave, Google, etc.)
            response = httpx.get(
                "https://api.search.brave.com/res/v1/web/search",
                params={"q": query},
                headers={"X-Subscription-Token": self.api_key},
            )
            results = response.json().get("web", {}).get("results", [])
            return ToolResult(
                success=True,
                output=[{"title": r["title"], "url": r["url"], "snippet": r["description"]} for r in results[:5]],
            )
        except Exception as e:
            return ToolResult(success=False, output=None, error=str(e))
```

### Custom Tool Loading

```python
# runner/tools/loader.py

class ToolLoader:
    def __init__(self, workspace: str, prompt_parser: PromptParser):
        self.workspace = workspace
        self.prompt_parser = prompt_parser
        self.builtins = {
            "read_file": ReadFileTool(),
            "write_file": WriteFileTool(),
            "shell": ShellTool(),
            "glob": GlobTool(),
            "grep": GrepTool(),
            "websearch": WebSearchTool(),
        }

    def load_tool(self, tool_spec: dict) -> Tool:
        """Load a tool from specification."""
        if tool_spec.get("builtin"):
            tool = self.builtins[tool_spec["name"]]
            if "config" in tool_spec:
                # Apply config (e.g., allowed commands for shell)
                tool = self._configure_tool(tool, tool_spec["config"])
            return tool

        # Custom tool - load from path
        path = tool_spec["path"]  # e.g., "//tools:run-tests"
        return self._load_custom_tool(path)

    def _load_custom_tool(self, path: str) -> Tool:
        """Load custom tool from .prompt.md or .py file."""
        # Parse path like "//tools:run-tests"
        if path.startswith("//"):
            path = path[2:]
        dir_name, tool_name = path.split(":")

        # Try .prompt.md first (agent tool)
        prompt_path = os.path.join(self.workspace, ".plue", dir_name, f"{tool_name}.prompt.md")
        if os.path.exists(prompt_path):
            return AgentTool(self.prompt_parser.parse(prompt_path))

        # Try .py (workflow tool)
        py_path = os.path.join(self.workspace, ".plue", dir_name, f"{tool_name}.py")
        if os.path.exists(py_path):
            return WorkflowTool(py_path)

        raise ValueError(f"Tool not found: {path}")
```

---

## Streaming Protocol

### SSE Events

```typescript
// Event types streamed to client

// Workflow events
interface RunStarted {
    type: "run_started"
    run_id: number
    workflow: string
}

interface StepStarted {
    type: "step_started"
    step_id: string
    name: string
    step_type: "shell" | "llm" | "agent"
}

interface StepOutput {
    type: "step_output"
    step_id: string
    line: string
}

// LLM/Agent events
interface LlmToken {
    type: "llm_token"
    step_id: string
    token: string
}

interface ToolStart {
    type: "tool_start"
    step_id: string
    tool: string
    input: object
}

interface ToolEnd {
    type: "tool_end"
    step_id: string
    tool: string
    output: string
    success: boolean
}

interface AgentTurn {
    type: "agent_turn"
    step_id: string
    turn: number
    max_turns: number
}

// Completion events
interface StepCompleted {
    type: "step_completed"
    step_id: string
    success: boolean
    output?: object
    error?: string
}

interface RunCompleted {
    type: "run_completed"
    success: boolean
    outputs?: object
    error?: string
}
```

### Runner → Server Protocol

```python
# runner/streaming.py

import httpx
import json

class StreamingClient:
    def __init__(self, callback_url: str, task_id: str):
        self.callback_url = callback_url
        self.task_id = task_id
        self.client = httpx.AsyncClient()

    async def send_event(self, event: dict):
        """Send streaming event to Zig server."""
        await self.client.post(
            f"{self.callback_url}/internal/tasks/{self.task_id}/stream",
            json=event,
        )

    async def send_token(self, step_id: str, token: str):
        await self.send_event({
            "type": "llm_token",
            "step_id": step_id,
            "token": token,
        })

    async def send_tool_start(self, step_id: str, tool: str, input: dict):
        await self.send_event({
            "type": "tool_start",
            "step_id": step_id,
            "tool": tool,
            "input": input,
        })

    async def send_tool_end(self, step_id: str, tool: str, output: str, success: bool):
        await self.send_event({
            "type": "tool_end",
            "step_id": step_id,
            "tool": tool,
            "output": output,
            "success": success,
        })

    async def send_step_completed(self, step_id: str, success: bool, output=None, error=None):
        await self.send_event({
            "type": "step_completed",
            "step_id": step_id,
            "success": success,
            "output": output,
            "error": error,
        })
```

---

## Storage Schema

```sql
-- migrations/004_workflows.sql

-- Workflow definitions (parsed from .py files)
CREATE TABLE workflow_definitions (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER REFERENCES repositories(id),
    name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    triggers JSONB NOT NULL,
    image VARCHAR(255),
    dockerfile VARCHAR(500),
    plan JSONB NOT NULL,               -- The generated DAG
    content_hash VARCHAR(64) NOT NULL,
    parsed_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(repository_id, name)
);

-- Prompt definitions (parsed from .prompt.md files)
CREATE TABLE prompt_definitions (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER REFERENCES repositories(id),
    name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    client VARCHAR(100) NOT NULL,
    prompt_type VARCHAR(20) NOT NULL,  -- llm, agent
    inputs_schema JSONB NOT NULL,
    output_schema JSONB NOT NULL,
    tools JSONB,
    max_turns INTEGER,
    body_template TEXT NOT NULL,
    content_hash VARCHAR(64) NOT NULL,
    parsed_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(repository_id, name)
);

-- Workflow runs
CREATE TABLE workflow_runs (
    id SERIAL PRIMARY KEY,
    workflow_definition_id INTEGER REFERENCES workflow_definitions(id),
    trigger_type VARCHAR(50) NOT NULL,
    trigger_payload JSONB NOT NULL,
    inputs JSONB,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    outputs JSONB,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_workflow_runs_status ON workflow_runs(status);

-- Individual steps within a run
CREATE TABLE workflow_steps (
    id SERIAL PRIMARY KEY,
    run_id INTEGER REFERENCES workflow_runs(id),
    step_id VARCHAR(100) NOT NULL,
    name VARCHAR(255) NOT NULL,
    step_type VARCHAR(20) NOT NULL,    -- shell, llm, agent, parallel
    config JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    exit_code INTEGER,
    output JSONB,
    error_message TEXT,

    -- Agent-specific
    turns_used INTEGER,
    tokens_in INTEGER,
    tokens_out INTEGER
);

CREATE INDEX idx_workflow_steps_run ON workflow_steps(run_id);

-- Step logs (streaming output)
CREATE TABLE workflow_logs (
    id SERIAL PRIMARY KEY,
    step_id INTEGER REFERENCES workflow_steps(id),
    log_type VARCHAR(20) NOT NULL,     -- stdout, stderr, token, tool_call, tool_result
    content TEXT NOT NULL,
    sequence INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_workflow_logs_step ON workflow_logs(step_id, sequence);

-- LLM usage tracking
CREATE TABLE llm_usage (
    id SERIAL PRIMARY KEY,
    step_id INTEGER REFERENCES workflow_steps(id),
    prompt_name VARCHAR(255),
    model VARCHAR(100) NOT NULL,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    latency_ms INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## API Specification

### Endpoints

```
# Workflow Management
POST   /api/workflows/parse           # Parse .py file, return plan
POST   /api/workflows/run             # Trigger workflow run
GET    /api/workflows/runs            # List runs
GET    /api/workflows/runs/:id        # Get run details
GET    /api/workflows/runs/:id/stream # SSE stream for live run
POST   /api/workflows/runs/:id/cancel # Cancel run

# Prompt Management
POST   /api/prompts/parse             # Parse .prompt.md file
POST   /api/prompts/render            # Render prompt with inputs
POST   /api/prompts/test              # Test prompt execution

# Internal (Runner → Server)
POST   /internal/tasks/:id/stream     # Runner streams events
POST   /internal/tasks/:id/complete   # Runner reports completion
POST   /internal/runners/register     # Runner registers with pool
POST   /internal/runners/heartbeat    # Runner heartbeat
```

### Zig Server Implementation

```zig
// server/src/routes/workflows.zig

const std = @import("std");
const httpz = @import("httpz");

pub fn runWorkflow(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const body = req.json(RunWorkflowRequest) catch {
        res.status = 400;
        return res.json(.{ .error = "Invalid request" });
    };

    // 1. Load workflow definition
    const workflow = try db.getWorkflowDefinition(ctx.pool, body.workflow_name);

    // 2. Create run record
    const run_id = try db.createWorkflowRun(ctx.pool, .{
        .workflow_definition_id = workflow.id,
        .trigger_type = body.trigger_type,
        .trigger_payload = body.trigger_payload,
        .inputs = body.inputs,
    });

    // 3. Queue for execution
    try queue.submitWorkload(ctx.pool, .{
        .type = .workflow,
        .run_id = run_id,
        .plan = workflow.plan,
    });

    res.json(.{ .run_id = run_id });
}

pub fn streamRun(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const run_id = req.param("id") orelse return error.MissingParam;

    // Set up SSE
    res.content_type = .@"text/event-stream";
    res.headers.append("Cache-Control", "no-cache");
    res.headers.append("Connection", "keep-alive");

    // Subscribe to run events
    const subscriber = try ctx.event_bus.subscribe(run_id);
    defer subscriber.unsubscribe();

    // Stream events
    while (try subscriber.next()) |event| {
        try res.writer().print("data: {s}\n\n", .{event.json()});
        try res.flush();

        if (event.type == .run_completed) break;
    }
}
```

---

## Implementation Order

1. **RestrictedPython-Compatible Runtime (Zig)**
   - Zig workflow evaluator with restricted semantics
   - Plue builtins implemented in Zig
   - Deterministic plan generation (no I/O/network)

2. **Jinja2-Compatible Prompt Parser (Rust/C)**
   - Frontmatter parsing (YAML)
   - Template rendering via Rust/C engine (e.g., minijinja)
   - Output schema generation

3. **Plan Execution**
   - DAG execution engine
   - Shell step executor
   - Parallel execution

4. **LLM Integration**
   - Claude API client
   - Token streaming
   - Output parsing

5. **Agent Execution**
   - Tool loading
   - Agent loop
   - Tool execution and streaming

6. **Warm Pool**
   - Runner registration
   - Fast claiming
   - Heartbeat management

7. **API + UI**
   - Workflow endpoints
   - SSE streaming
   - Frontend components
