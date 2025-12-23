# Plue Workflows: Product Requirements Document

Infrastructure-as-code workflows with first-class AI agent support.

---

## 1) Product Overview

### 1.1 What We're Building

A workflow system that replaces YAML-based CI/CD with a proper programming model. Plue Workflows combines:

- **Restricted Python** — Python syntax with decorators, evaluated by the Zig service with RestrictedPython-compatible rules (no separate Python service)
- **Starlark-like builtins** — `schema()`, `enum()`, `list()`, `optional()` for type definitions
- **Jinja2 Prompts** — Markdown documents with Jinja2-compatible templating implemented via Rust/C
- **Unified Execution** — Traditional CI steps and AI agents share the same sandboxed Docker runtime

**Key Insight: Python produces a plan.** The workflow code doesn't execute directly — it generates a DAG of steps that the runtime executes later. The Zig runtime enforces deterministic, RestrictedPython-compatible plan evaluation.

### 1.2 The Plue Approach

```
┌─────────────────────────────────────────────────────────────────┐
│                     PLUE WORKFLOWS                               │
│                                                                  │
│   workflow.py ──► RestrictedPython ──► Plan (DAG) ──► Execution │
│   (decorators)    (sandboxed eval)     (validated)    (runtime) │
│                                                                  │
│   prompt.md ──────► Jinja2 + YAML ────► LLM agent            │
│   (markdown)        (typed schema)      (first-class step)      │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 Design Principles

1. **Workflows produce plans** — Python defines what to do, runtime executes it
2. **Python syntax, Starlark safety** — Decorators and clean syntax, but sandboxed
3. **Prompts are documents** — Markdown + Jinja2, not strings in code
4. **Agents are steps** — An LLM call is just another step in the DAG
5. **Tools are composable** — A tool can be another workflow or agent
6. **Docker-based runtime** — Each workflow defines its container environment
7. **Works like GitHub** — When in doubt, match GitHub Actions behavior

---

## 2) Workflow Language Specification

### 2.1 File Structure

Mirrors GitHub Actions structure (`.github/workflows/` → `.plue/workflows/`):

```
repo/
├── .plue/
│   ├── workflows/               # Like .github/workflows/
│   │   ├── ci.py                # Workflow definitions
│   │   ├── release.py
│   │   └── review.py
│   ├── prompts/                 # AI prompt definitions
│   │   ├── CodeReview.prompt.md
│   │   ├── SecurityAudit.prompt.md
│   │   └── FixErrors.prompt.md
│   ├── actions/                 # Reusable actions (like GitHub Actions)
│   │   ├── setup-node/
│   │   │   └── action.py
│   │   └── deploy-preview/
│   │       └── action.py
│   └── lib/                     # Shared Python modules
│       └── notify.py
└── ...
```

### 2.2 RestrictedPython Sandbox

Workflow files are evaluated by the Zig runtime with RestrictedPython-compatible rules. The following are **blocked**:

- `import` (except whitelisted `plue` modules)
- File I/O (`open`, `os`, `pathlib`)
- Network access (`socket`, `urllib`, `requests`)
- System calls (`subprocess`, `os.system`)
- `eval`, `exec`, `compile`
- Private attribute access (`__class__`, `_private`)

Only Plue SDK builtins are available.

### 2.3 Type System (Starlark-like)

```python
# Primitive types
str, int, float, bool

# Schema definition
Comment = schema(
    file = str,
    line = int,
    severity = enum("info", "warning", "error"),
    message = str,
    suggestion = optional(str),
)

ReviewResult = schema(
    approved = bool,
    comments = list(Comment),
    summary = str,
)

# Composite types
list(Comment)           # Array of Comments
optional(str)           # String or None
enum("a", "b", "c")     # Union of literals
```

### 2.4 Workflow Definition

```python
# .plue/workflows/ci.py

from plue import workflow, push, pull_request, schema, enum, list, optional
from plue.prompts import CodeReview  # Auto-imported from .prompt.md files

@workflow(
    triggers=[
        push(branches=["main"]),
        pull_request(types=["opened", "synchronize"]),
        manual(inputs={"env": str, "skip_tests": bool}),
    ],
    # Docker environment - defaults to Ubuntu if not specified
    dockerfile="Dockerfile",        # Path to Dockerfile
    # OR
    image="ubuntu:22.04",           # Use existing image
)
def release(ctx):
    # Workflow logic - this produces a plan, not immediate execution
    ...
```

### 2.5 Step Primitives

```python
@workflow(triggers=[push()])
def ci(ctx):
    # Shell step - adds to the plan
    build = ctx.run(
        name="build",
        cmd="zig build -Doptimize=ReleaseSafe",
        env={"CC": "clang"},
        cache=cache_key("build", hash_files("build.zig*")),
    )

    # Parallel steps - executed concurrently
    tests = ctx.parallel([
        ctx.run(name="test-unit", cmd="zig build test"),
        ctx.run(name="test-integration", cmd="bun test"),
    ])

    # Conditional logic
    if ctx.event.type == "pull_request":
        ctx.run(name="preview", cmd="deploy --preview")

    return ctx.success()
```

### 2.6 LLM Functions

```python
from plue.prompts import CodeReview

@workflow(triggers=[pull_request()])
def review(ctx):
    # Import and call prompt - adds LLM step to the plan
    review = CodeReview(
        diff=ctx.git.diff(),
        context=ctx.read("CONTRIBUTING.md"),
    )

    # Type-safe access to result
    if not review.approved:
        return ctx.fail(review.comments)

    return ctx.success()
```

### 2.7 Context Object (`ctx`)

Mirrors GitHub Actions contexts (`github`, `secrets`, `env`, etc.):

```python
# GitHub context (like ${{ github.* }})
ctx.event.action            # "opened", "synchronize", etc.
ctx.event.ref               # "refs/heads/main"
ctx.event.sha               # Commit SHA
ctx.event.actor             # User who triggered (like github.actor)
ctx.event.repository        # Repository info
ctx.event.pull_request      # PR info (if applicable)
ctx.event.pull_request.base # Base branch
ctx.event.pull_request.head # Head branch/SHA

# Repository context
ctx.repo                    # Repository object
ctx.repo.name               # "my-repo"
ctx.repo.owner              # "my-org"
ctx.repo.default_branch     # "main"

# Git operations (enhanced over GitHub Actions)
ctx.git.diff(base="HEAD~1") # Get diff
ctx.git.log(n=10)           # Get commit log
ctx.git.checkout(ref="main")

# File operations
ctx.read(path)              # Read file contents
ctx.write(path, content)    # Write file
ctx.glob(pattern)           # Find files

# Secrets (like ${{ secrets.* }})
ctx.secrets.GITHUB_TOKEN    # Access secrets
ctx.secrets.DEPLOY_KEY

# Environment (like ${{ env.* }})
ctx.env.CI                  # Environment variables
ctx.env.NODE_ENV

# PR/Issue interactions (like GitHub Actions)
ctx.comment(body)           # Add PR/issue comment
ctx.review_comment(         # Add review comment
    path="src/file.ts",
    line=42,
    body="Issue here"
)
ctx.approve()               # Approve PR
ctx.request_changes(body)   # Request changes

# Workflow control
ctx.success(**outputs)      # Complete successfully (like exit 0)
ctx.fail(reason)            # Fail with message (like exit 1)
```

---

## 3) Prompt Specification (Jinja2 + Markdown)

Note: Prompt rendering is handled inside the Zig service using a Jinja2-compatible Rust/C implementation (no separate Python service).

### 3.1 File Format

````markdown
---
name: CodeReview
client: anthropic/claude-sonnet

inputs:
  diff: string
  context: string?
  rules: string[]?

output:
  approved: boolean
  comments:
    - file: string
      line: integer
      severity: info | warning | error
      message: string
  summary: string
---

Review this code change for production deployment.

{% if context %}

## Project Guidelines

{{ context }}
{% endif %}

## Code to Review

```diff
{{ diff }}
```
````

{% if rules %}

## Review Criteria

{% for rule in rules %}

- {{ rule }}
  {% endfor %}
  {% endif %}

## Instructions

Focus on:

- Logic errors and bugs
- Security vulnerabilities
- Performance issues

{{ output_schema }}

````

### 3.2 Frontmatter Schema

```yaml
# Required
name: string              # Function name for imports

# LLM Configuration
client: string            # "anthropic/claude-sonnet", "openai/gpt-4", etc.
type: llm | agent         # Default: llm

# Type Definitions
inputs:
  field_name: type        # string, integer, float, boolean
                          # string? for optional
                          # string[] for arrays

output:
  field_name: type        # Same type syntax
                          # enum: value1 | value2 | value3

# Agent-specific (type: agent)
tools:                    # List of available tools
  - read_file             # Built-in tool
  - write_file
  - shell
  - //tools:search        # Custom tool (another prompt/workflow)
  - dynamic               # Accept tools passed at runtime
max_turns: integer        # Default: 10
````

### 3.3 Jinja2 Features

| Syntax                | Purpose              | Example                                     |
| --------------------- | -------------------- | ------------------------------------------- |
| `{{ var }}`           | Interpolate variable | `{{ diff }}`                                |
| `{% if x %}`          | Conditional          | `{% if context %}...{% endif %}`            |
| `{% for x in list %}` | Loop                 | `{% for rule in rules %}...{% endfor %}`    |
| `{% include "..." %}` | Import file          | `{% include "partials/instructions.md" %}`  |
| `{% extends "..." %}` | Template inheritance | `{% extends "base.prompt.md" %}`            |
| `{% block name %}`    | Overridable section  | `{% block instructions %}...{% endblock %}` |
| `{% macro name() %}`  | Reusable snippet     | `{% macro header() %}...{% endmacro %}`     |
| `{{ output_schema }}` | Inject output format | Auto-generated from schema                  |

### 3.4 Template Inheritance

Base template:

````markdown
## {# prompts/base-review.prompt.md #}

name: BaseReview
client: anthropic/claude-sonnet

---

{% block intro %}
Review this code change.
{% endblock %}

## Code

```diff
{{ diff }}
```
````

{% block criteria %}
Focus on correctness and clarity.
{% endblock %}

{{ output_schema }}

````

Extended template:

```markdown
---
name: SecurityReview
client: anthropic/claude-sonnet
extends: base-review.prompt.md

inputs:
  diff: string

output:
  issues: SecurityIssue[]
---

{% extends "base-review.prompt.md" %}

{% block intro %}
Perform a security audit on this code change.
{% endblock %}

{% block criteria %}
Look for:
- SQL injection
- XSS vulnerabilities
- Authentication bypasses
- Secrets in code
{% endblock %}
````

### 3.5 Agent Prompts

```markdown
---
name: FixBuildErrors
client: anthropic/claude-sonnet
type: agent

inputs:
  goal: string
  errors: string

output:
  status: complete | stuck | error
  summary: string
  files_changed: string[]

tools:
  - read_file
  - write_file
  - shell
  - glob
  - //tools:run-tests # Custom tool - another workflow

max_turns: 20
---

You are a coding agent. Your goal is to fix build errors.

## Objective

{{ goal }}

## Current Errors
```

{{ errors }}

```

## Instructions

1. Use `read_file` to understand the code structure
2. Use `glob` to find relevant files
3. Use `write_file` to make fixes
4. Use `shell` to verify your changes compile
5. Iterate until the build passes

When complete, summarize what you changed.

{{ output_schema }}
```

---

## 4) Tool System

### 4.1 Built-in Tools

Available to all agents (similar to actions/checkout, actions/setup-node):

| Tool        | Description                 | GitHub Actions Equivalent |
| ----------- | --------------------------- | ------------------------- |
| `read_file` | Read file contents          | N/A (agents only)         |
| `write_file` | Write content to file       | N/A (agents only)         |
| `shell`     | Execute shell command       | `run:` step               |
| `glob`      | Find files matching pattern | N/A                       |
| `grep`      | Search file contents        | N/A                       |
| `websearch` | Search the web              | N/A (AI enhancement)      |

### 4.2 Tool Invocation in Workflows

Tools can be scoped to specific repo refs (like checkout@v4):

```python
from plue.tools import read_file, grep, glob, websearch

@workflow(triggers=[pull_request()])
def review(ctx):
    result = CodeReview(
        diff=ctx.git.diff(base=ctx.event.pull_request.base),
        tools=[
            # Tools scoped to PR head commit
            read_file(repo=ctx.repo, ref=ctx.event.pull_request.head),
            grep(repo=ctx.repo, ref=ctx.event.pull_request.head),
            glob(repo=ctx.repo, ref=ctx.event.pull_request.head),
            websearch(),
        ],
        max_turns=10,
    )
```

### 4.3 Custom Tools (Reusable Actions)

Like GitHub Actions, tools can be reusable actions defined as prompts or Python:

```markdown
---
# tools/search-codebase.prompt.md
name: SearchCodebase
client: anthropic/claude-haiku
type: agent

inputs:
  query: string
  file_types: string[]?

output:
  results: SearchResult[]
  summary: string

tools:
  - glob
  - read_file
  - grep
---

Search the codebase for: {{ query }}

{% if file_types %}
Only search in files matching: {{ file_types | join(", ") }}
{% endif %}

Return relevant code snippets and file locations.

{{ output_schema }}
```

Or as a Python workflow:

```python
# tools/run-tests.py

from plue import tool, schema, list, optional

@tool(
    inputs={"test_pattern": optional(str)},
    output=schema(
        passed=bool,
        failed_tests=list(str),
        output=str,
    ),
)
def run_tests(ctx):
    pattern = ctx.inputs.get("test_pattern", "")
    result = ctx.run(cmd=f"bun test {pattern}")

    return ctx.success(
        passed=result.exit_code == 0,
        failed_tests=parse_failures(result.stderr),
        output=result.stdout,
    )
```

### 4.3 Using Custom Tools

Reference tools in agent prompts:

```yaml
# In frontmatter
tools:
  - read_file # Built-in
  - //tools:search-codebase # Custom agent tool
  - //tools:run-tests # Custom workflow tool
```

### 4.4 Dynamic Tools

Agents can accept tools passed at runtime:

```yaml
tools:
  - read_file
  - dynamic # Accept additional tools from caller
```

```python
# In workflow
result = FixBuildErrors(
    goal="Fix the tests",
    errors=build.stderr,
    tools=[
        "//tools:run-tests",
        "//tools:lint",
    ],
)
```

---

## 5) Runtime Environment

### 5.1 Docker Configuration

Each workflow defines its container environment:

```python
@workflow(
    triggers=[push()],
    # Option 1: Use existing image
    image="ubuntu:22.04",
)
def basic(ctx):
    ...

@workflow(
    triggers=[push()],
    # Option 2: Build from Dockerfile
    dockerfile=".plue/Dockerfile",
)
def custom(ctx):
    ...
```

Default image is `ubuntu:22.04` if not specified.

### 5.2 Dockerfile Example

```dockerfile
# .plue/Dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    git \
    curl \
    build-essential

# Install project-specific tools
RUN curl -fsSL https://bun.sh/install | bash
```

### 5.3 Agent Execution

Agents run using the Claude Code SDK (or similar). The runtime:

1. Spins up container from workflow's Docker image
2. Mounts workspace with repo code
3. Executes agent loop with tools
4. Streams output via SSE

---

## 6) Sandboxing

### 6.1 Two-Phase Sandboxing

**Phase 1: Plan Generation (RestrictedPython)**

- Workflow `.py` files run in RestrictedPython
- No imports except Plue SDK
- No I/O, network, or system calls
- Deterministic: same code = same plan

**Phase 2: Execution (Docker + gVisor)**

- Steps run in isolated Docker containers
- gVisor runtime for syscall filtering
- Network egress allowlist
- Resource limits (CPU, memory, disk, time)

### 6.2 Container Isolation

- **gVisor runtime** — syscalls intercepted, no host kernel access
- **Read-only root filesystem** — only `/workspace` and `/tmp` writable
- **Non-root user** — runs as UID 1000
- **Resource limits** — CPU, memory, disk bounded
- **Network isolation** — egress allowlist only

### 6.3 Security Roadmap

**MVP:**

- RestrictedPython for plan phase
- Basic container sandboxing
- Network egress controls
- Resource limits

**Future (Important):**

- Closed-source prompt injection protection
- Agentic security hardening
- We will offer prompt injection security as a service
- Implementation details will not be published

---

## 7) Frontend

The workflow UI should work similarly to GitHub Actions:

### 7.1 Run List View

- List of workflow runs with status indicators
- Filter by workflow, branch, status
- Trigger manual runs

### 7.2 Run Detail View

- DAG visualization of steps
- Live streaming logs
- Step-by-step status
- Expandable log output per step

### 7.3 Agent View

- Token streaming (like chat)
- Tool call visualization
- Collapsible tool inputs/outputs
- Turn counter

### 7.4 Prompt Editor

- Markdown + Jinja2 syntax highlighting
- Live preview with sample inputs
- Schema validation
- Test execution

---

## 8) Examples

### 8.1 Basic CI Pipeline

```python
# .plue/workflows/ci.py

from plue import workflow, push, pull_request

@workflow(
    triggers=[push(), pull_request()],
    image="ubuntu:22.04",
)
def ci(ctx):
    # Install dependencies
    install = ctx.run(
        name="install",
        cmd="bun install",
        cache=cache_key("deps", hash_files("bun.lockb")),
    )

    # Run tests and lint in parallel
    checks = ctx.parallel([
        ctx.run(name="test", cmd="bun test", depends_on=[install]),
        ctx.run(name="lint", cmd="bun lint", depends_on=[install]),
        ctx.run(name="typecheck", cmd="bun typecheck", depends_on=[install]),
    ])

    # Build only on main
    if ctx.event.ref == "refs/heads/main":
        ctx.run(
            name="build",
            cmd="bun run build",
            depends_on=checks,
        )

    return ctx.success()
```

### 8.2 AI Code Review with Multiple Focuses

```python
# .plue/workflows/review.py

from plue import workflow, pull_request
from plue.prompts import CodeReview
from plue.tools import read_file, grep, glob, websearch


# Define review focus areas (like matrix strategy in GitHub Actions)
FOCUSES = [
    {
        "name": "security",
        "description": "Security vulnerabilities and attack vectors",
        "checks": [
            "XSS and injection attacks",
            "Authentication/authorization flaws",
            "Secrets or credentials in code",
        ],
    },
    {
        "name": "performance",
        "description": "Performance issues and optimization opportunities",
        "checks": [
            "N+1 queries or unnecessary fetches",
            "Missing memoization or caching",
            "Bundle size impacts",
        ],
    },
    {
        "name": "correctness",
        "description": "Logic errors and potential bugs",
        "checks": [
            "Off-by-one errors",
            "Null/undefined handling",
            "Race conditions",
        ],
    },
]


@workflow(triggers=[pull_request()])
def review(ctx):
    """Multi-pass AI code review with tools."""

    diff = ctx.git.diff(base=ctx.event.pull_request.base)
    all_issues = []

    # Run focused review passes (like matrix jobs)
    for focus in FOCUSES:
        result = CodeReview(
            diff=diff,
            language="typescript",
            focus=focus["name"],
            focus_description=focus["description"],
            checks=focus["checks"],
            tools=[
                read_file(repo=ctx.repo, ref=ctx.event.pull_request.head),
                grep(repo=ctx.repo, ref=ctx.event.pull_request.head),
                glob(repo=ctx.repo, ref=ctx.event.pull_request.head),
                websearch(),
            ],
            max_turns=10,
        )
        all_issues.extend(result.issues)

    # Post inline comments (like GitHub Actions annotations)
    for issue in all_issues:
        ctx.review_comment(
            path=issue.file,
            line=issue.line,
            body=f"**[{issue.focus}]** {issue.message}",
        )

    approved = not any(i.severity == "error" for i in all_issues)
    return ctx.success(approved=approved)
```

### 8.3 Agent-Powered Issue Helper

```python
# .plue/workflows/issue-helper.py

from plue import workflow, issue_comment
from plue.prompts import IssueHelper

@workflow(triggers=[issue_comment(contains="@plue")])
def issue_helper(ctx):
    issue = ctx.event.issue
    comment = ctx.event.comment

    # Run agent with tools
    result = IssueHelper(
        issue_title=issue.title,
        issue_body=issue.body,
        comment=comment.body,
        repo_context=ctx.read("README.md"),
    )

    if result.action == "create_pr":
        ctx.issue.comment(
            body=f"I've created a PR to address this: #{result.pr_number}\n\n{result.summary}"
        )
    elif result.action == "explain":
        ctx.issue.comment(body=result.explanation)
    elif result.action == "needs_clarification":
        ctx.issue.comment(body=result.question)

    return ctx.success()
```

---

## 9) GitHub Actions Comparison

| GitHub Actions                | Plue Workflows                         |
| ----------------------------- | -------------------------------------- |
| `.github/workflows/*.yml`     | `.plue/workflows/*.py`                 |
| `on: push`                    | `@workflow(triggers=[push()])`         |
| `on: pull_request`            | `@workflow(triggers=[pull_request()])` |
| `jobs:` / `steps:`            | `ctx.run()` / `ctx.parallel()`         |
| `uses: actions/checkout@v4`   | Built-in (auto-checkout)               |
| `uses: actions/setup-node@v4` | `image="node:22"` or custom action     |
| `${{ github.event }}`         | `ctx.event`                            |
| `${{ secrets.* }}`            | `ctx.secrets.*`                        |
| `run: npm test`               | `ctx.run(cmd="npm test")`              |
| Matrix strategy               | Python loops (more powerful)           |
| Reusable workflows            | Python imports / actions               |
| N/A                           | AI agents as first-class steps         |
| N/A                           | Tool-using agents with `max_turns`     |

---

## 10) CLI Specification

Mirrors GitHub CLI (`gh`) patterns:

```bash
# Workflow management
plue workflow list                    # List all workflows
plue workflow run <name>              # Run workflow manually
plue workflow run <name> --input k=v  # Run with inputs
plue run list                         # List recent runs
plue run view <run-id>                # View run details
plue run watch <run-id>               # Watch live run
plue run cancel <run-id>              # Cancel running workflow

# Development
plue workflow lint                    # Lint .py and .prompt.md files

# Prompt development
plue prompt preview <file>            # Render prompt with sample inputs
plue prompt test <file>               # Test prompt execution
```

---

## 11) Configuration

```yaml
# .plue/config.yaml

# Default LLM client
default_client: anthropic/claude-sonnet

# Default Docker image (if not specified per-workflow)
default_image: ubuntu:22.04

# Secrets source
secrets:
  provider: vault
  address: https://vault.internal:8200
```

---

## 12) How It Works (Summary)

```
1. AUTHOR
   Developer writes .py workflow + .prompt.md files

2. PARSE
   RestrictedPython evaluates workflow, producing a Plan (DAG of steps)
   Jinja2 prompts are parsed, schemas extracted

3. VALIDATE
   Plan is validated: no cycles, all deps exist, types check

4. TRIGGER
   Event occurs (push, PR, manual, etc.)
   Matching workflow's plan is queued

5. EXECUTE
   Runtime spins up Docker container
   Steps execute in topological order
   Agent steps use Claude Code SDK
   Output streams via SSE

6. COMPLETE
   Results persisted
   UI shows logs and outputs
   Downstream workflows triggered if configured
```

---

## 13) Open Questions

1. **Timeouts** — Default timeout per step? Per workflow? Configurable?
2. **Billing** — How to meter LLM usage? (Not for MVP)
3. **Caching** — Cache LLM responses? Cache Docker layers?
4. **Rollback** — Works like GitHub: rerun previous workflow version

---

## 14) References

- [RestrictedPython](https://github.com/zopefoundation/RestrictedPython)
- [Jinja2 Documentation](https://jinja.palletsprojects.com/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Claude Code SDK](https://github.com/anthropics/claude-code)
