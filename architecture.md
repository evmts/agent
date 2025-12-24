# Plue: A Brutalist GitHub Clone with Integrated AI Agents

## Executive Summary

Plue is a GitHub alternative built from scratch with AI agents as first-class citizens. The key insight: **workflows and agents are fundamentally the same thing**—both execute code in sandboxed containers, the only difference is whether a human or an LLM decides the steps.

---

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    CLIENTS                                           │
│                                                                                      │
│     Browser (Astro SSR)              Git Client                   API Client        │
│           │                              │                            │             │
│           │ HTTPS                        │ SSH                        │ HTTPS       │
│           │                              │                            │             │
└───────────┼──────────────────────────────┼────────────────────────────┼─────────────┘
            │                              │                            │
            ▼                              │                            │
┌─────────────────────────────────────┐    │                            │
│        CLOUDFLARE EDGE              │    │                            │
│                                     │    │                            │
│  ┌─────────────────────────────┐   │    │                            │
│  │   Edge Worker (TypeScript)  │   │    │                            │
│  │                             │   │    │                            │
│  │ • Session-aware caching     │   │    │                            │
│  │ • Version-based invalidation│   │    │                            │
│  │ • Cache-Tag purge support   │   │    │                            │
│  │ • DDoS protection           │   │    │                            │
│  └─────────────────────────────┘   │    │                            │
│                                     │    │                            │
└─────────────────┬───────────────────┘    │                            │
                  │                        │                            │
                  │ Cache miss             │                            │
                  ▼                        ▼                            ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              ZIG API SERVER                                          │
│                                                                                      │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────┐│
│  │   REST API    │  │  SSE Stream   │  │  SSH Server   │  │    K8s Client         ││
│  │               │  │               │  │               │  │                       ││
│  │ • CRUD ops    │  │ • Agent token │  │ • Git push/   │  │ • Claim runners       ││
│  │ • Git tree    │  │   streaming   │  │   pull/fetch  │  │ • Create Jobs         ││
│  │ • Git blob    │  │ • Workflow    │  │ • Public key  │  │ • Watch status        ││
│  │ • Issues/PRs  │  │   logs        │  │   auth        │  │ • Warm pool mgmt      ││
│  └───────────────┘  └───────────────┘  └───────────────┘  └───────────────────────┘│
│                                     │                                               │
│  ┌──────────────────────────────────┴───────────────────────────────────────────┐  │
│  │                              jj-lib (Rust FFI)                                │  │
│  │                                                                               │  │
│  │    Git operations • Tree walking • Blob content • Snapshots • Change IDs     │  │
│  └───────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                      │
│  ┌───────────────────────────────────────────────────────────────────────────────┐  │
│  │                           Auth (SIWE + JWT + Session)                         │  │
│  │                                                                               │  │
│  │   Sign-In With Ethereum • Cookie sessions • API tokens • SSH key auth        │  │
│  └───────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                      │
└────────────────────────────────────────────┬────────────────────────────────────────┘
                                             │
                      ┌──────────────────────┴──────────────────────┐
                      │                                             │
                      ▼                                             ▼
┌─────────────────────────────────────┐    ┌───────────────────────────────────────────┐
│          POSTGRESQL                 │    │            KUBERNETES (GKE)               │
│                                     │    │                                           │
│  Source of truth for:               │    │   ┌─────────────────────────────────────┐ │
│                                     │    │   │    Sandbox Node Pool (gVisor)       │ │
│  • Users & Auth                     │    │   │                                     │ │
│  • Repositories                     │    │   │   ┌─────────┐ ┌─────────┐ ┌───────┐│ │
│  • Issues & PRs                     │    │   │   │ Runner  │ │ Runner  │ │Runner ││ │
│  • Agent sessions & messages        │    │   │   │  Pod 1  │ │  Pod 2  │ │ Pod N ││ │
│  • Workflow runs & logs             │    │   │   │(standby)│ │(active) │ │(active)│ │
│  • Warm pool registry               │    │   │   └─────────┘ └─────────┘ └───────┘│ │
│                                     │    │   │                                     │ │
│  40+ tables with full FK            │    │   │   • Python agent runtime            │ │
│  constraints & indexes              │    │   │   • File system access              │ │
│                                     │    │   │   • Network restricted              │ │
│                                     │    │   │   • Resource limited                │ │
└─────────────────────────────────────┘    │   └─────────────────────────────────────┘ │
                                           │                                           │
                                           └───────────────────────────────────────────┘
```

---

## The Unified Workflow/Agent Model

This is the architectural insight that makes Plue unique:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                    TRADITIONAL VIEW: Separate Systems                                   │
│                                                                                        │
│   ┌─────────────────────────────┐         ┌─────────────────────────────┐             │
│   │     CI/CD Workflows         │         │       AI Agents              │             │
│   │                             │         │                              │             │
│   │  • Predefined YAML steps    │    ≠    │  • LLM decides actions      │             │
│   │  • Triggered by git events  │         │  • Triggered by prompts     │             │
│   │  • Runs in containers       │         │  • Needs sandboxing         │             │
│   └─────────────────────────────┘         └──────────────────────────────┘             │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │  PLUE'S INSIGHT
                                      ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                         UNIFIED VIEW: Same Infrastructure                               │
│                                                                                        │
│   ┌──────────────────────────────────────────────────────────────────────────────┐    │
│   │                           EVENT OCCURS                                        │    │
│   │                                                                               │    │
│   │   push │ pull_request │ issue.comment │ user_prompt │ @plue mention          │    │
│   └───────────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                                 │
│                                      ▼                                                 │
│   ┌──────────────────────────────────────────────────────────────────────────────┐    │
│   │                     MATCH TO WORKFLOW DEFINITION                              │    │
│   │                                                                               │    │
│   │   .plue/workflows/*.py  or  .plue/workflows/*.yaml                           │    │
│   └───────────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                                 │
│                          ┌───────────┴───────────┐                                     │
│                          │                       │                                     │
│                          ▼                       ▼                                     │
│   ┌──────────────────────────────┐  ┌──────────────────────────────┐                  │
│   │      SCRIPTED MODE           │  │       AGENT MODE              │                  │
│   │                              │  │                               │                  │
│   │  @workflow(triggers=[push()])│  │  mode: agent                  │                  │
│   │  def ci(ctx):                │  │  agent:                       │                  │
│   │    ctx.run("bun test")       │  │    model: claude-sonnet-4-... │                  │
│   │    ctx.run("bun build")      │  │    tools: [read_file, ...]    │                  │
│   │                              │  │                               │                  │
│   │  WHO DECIDES: Python code    │  │  WHO DECIDES: Claude          │                  │
│   └──────────────────────────────┘  └───────────────────────────────┘                  │
│                          │                       │                                     │
│                          └───────────┬───────────┘                                     │
│                                      │                                                 │
│                                      ▼                                                 │
│   ┌──────────────────────────────────────────────────────────────────────────────┐    │
│   │                        SAME EXECUTION ENVIRONMENT                             │    │
│   │                                                                               │    │
│   │   • gVisor-sandboxed K8s pod                                                 │    │
│   │   • Same tools: read_file, write_file, shell, git, search_code               │    │
│   │   • Same resource limits                                                      │    │
│   │   • Same network policies                                                     │    │
│   │   • Same streaming protocol to Zig server                                     │    │
│   └──────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Execution Flow: From Event to Completion

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              WORKFLOW EXECUTION FLOW                                     │
└─────────────────────────────────────────────────────────────────────────────────────────┘

  ① EVENT
  ─────────────────────────────────────────────────────────────────────────────────────────

    User pushes code         User opens chat          User comments "@plue help"
           │                       │                            │
           ▼                       ▼                            ▼
    ┌────────────┐          ┌────────────┐              ┌────────────┐
    │   push     │          │user_prompt │              │  mention   │
    └────────────┘          └────────────┘              └────────────┘
           │                       │                            │
           └───────────────────────┴────────────────────────────┘
                                   │
                                   ▼
  ② QUEUE
  ─────────────────────────────────────────────────────────────────────────────────────────

    ┌───────────────────────────────────────────────────────────────────────────────────┐
    │                              ZIG SERVER                                            │
    │                                                                                    │
    │   1. Parse .plue/workflows/ directory                                             │
    │   2. Match event → workflow definition (triggers)                                 │
    │   3. INSERT INTO workflow_runs (status = 'pending')                               │
    │   4. INSERT INTO workflow_steps for each step in DAG                             │
    │                                                                                    │
    └───────────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
  ③ RUNNER ASSIGNMENT
  ─────────────────────────────────────────────────────────────────────────────────────────

    ┌───────────────────────────────────────────────────────────────────────────────────┐
    │                           QUEUE WATCHER (1s poll)                                  │
    │                                                                                    │
    │   SELECT * FROM workflow_steps WHERE status = 'waiting' FOR UPDATE SKIP LOCKED   │
    │                                                                                    │
    └───────────────────────────────────────────────────────────────────────────────────┘
                                   │
                        ┌──────────┴──────────┐
                        │                     │
                        ▼                     ▼
            ┌─────────────────────┐  ┌─────────────────────┐
            │    WARM POOL        │  │    COLD START       │
            │    (< 500ms)        │  │    (3-5 seconds)    │
            │                     │  │                     │
            │ WITH claimed AS (   │  │ Create K8s Job:     │
            │   SELECT id         │  │                     │
            │   FROM runner_pool  │  │ kind: Job           │
            │   WHERE status =    │  │ spec:               │
            │         'available' │  │   runtimeClassName: │
            │   FOR UPDATE        │  │     gvisor          │
            │   SKIP LOCKED       │  │   containers:       │
            │   LIMIT 1           │  │   - image: runner   │
            │ )                   │  │                     │
            │ UPDATE ...          │  │                     │
            └─────────────────────┘  └─────────────────────┘
                        │                     │
                        └──────────┬──────────┘
                                   │
                                   ▼
  ④ EXECUTION
  ─────────────────────────────────────────────────────────────────────────────────────────

    ┌───────────────────────────────────────────────────────────────────────────────────┐
    │                         SANDBOXED RUNNER POD                                       │
    │                           (gVisor runtime)                                         │
    │                                                                                    │
    │   ┌─────────────────────────────────────────────────────────────────────────────┐ │
    │   │                        Python Agent Runtime                                  │ │
    │   │                                                                             │ │
    │   │   if mode == "scripted":                                                    │ │
    │   │       # Execute predefined steps                                            │ │
    │   │       for step in workflow.steps:                                           │ │
    │   │           result = subprocess.run(step.cmd)                                 │ │
    │   │           stream_to_zig(result.stdout)                                      │ │
    │   │                                                                             │ │
    │   │   elif mode == "agent":                                                     │ │
    │   │       # LLM decides actions                                                 │ │
    │   │       agent = Agent(model="claude-sonnet-4-20250514")                       │ │
    │   │       while not done:                                                       │ │
    │   │           response = anthropic.messages.create(...)                         │ │
    │   │           for token in response:                                            │ │
    │   │               stream_to_zig(token)                                          │ │
    │   │           if response.tool_calls:                                           │ │
    │   │               results = execute_tools(response.tool_calls)                  │ │
    │   │               stream_to_zig(results)                                        │ │
    │   │                                                                             │ │
    │   └─────────────────────────────────────────────────────────────────────────────┘ │
    │                                                                                    │
    │   ┌─────────────────────────────────────────────────────────────────────────────┐ │
    │   │                         AVAILABLE TOOLS                                      │ │
    │   │                                                                             │ │
    │   │  File System:  read_file │ write_file │ list_files │ grep                   │ │
    │   │  Git (jj):     status │ diff │ commit │ branch │ merge                      │ │
    │   │  Shell:        run_command (sandboxed, timeout, resource limits)            │ │
    │   │  Collaboration: create_issue │ comment │ create_pr │ review                 │ │
    │   │                                                                             │ │
    │   └─────────────────────────────────────────────────────────────────────────────┘ │
    │                                                                                    │
    └───────────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ HTTP POST (chunked streaming)
                                   │
                                   ▼
  ⑤ STREAMING
  ─────────────────────────────────────────────────────────────────────────────────────────

    ┌───────────────────────────────────────────────────────────────────────────────────┐
    │                              ZIG SERVER                                            │
    │                                                                                    │
    │   1. Receive streaming chunks from runner                                         │
    │   2. Push to connected clients via SSE (Server-Sent Events)                       │
    │   3. Buffer and batch-persist to Postgres                                         │
    │   4. Update step status on completion                                             │
    │                                                                                    │
    │   SSE Message Types:                                                              │
    │   ┌────────────────────────────────────────────────────────────────────────────┐ │
    │   │  event: token      → { message_id, text, token_index }                     │ │
    │   │  event: tool_start → { message_id, tool_name, input }                      │ │
    │   │  event: tool_end   → { message_id, tool_name, output, state }              │ │
    │   │  event: done       → { message_id, finish_reason }                         │ │
    │   │  event: error      → { message_id, error }                                 │ │
    │   └────────────────────────────────────────────────────────────────────────────┘ │
    │                                                                                    │
    └───────────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ SSE
                                   ▼
    ┌───────────────────────────────────────────────────────────────────────────────────┐
    │                              BROWSER                                               │
    │                                                                                    │
    │   const eventSource = new EventSource('/api/sessions/123/stream');               │
    │   eventSource.addEventListener('token', (e) => renderToken(e.data));             │
    │   eventSource.addEventListener('tool_start', (e) => showToolSpinner(e.data));    │
    │   eventSource.addEventListener('tool_end', (e) => showToolResult(e.data));       │
    │                                                                                    │
    └───────────────────────────────────────────────────────────────────────────────────┘
```

---

## Sandboxing Architecture: Defense in Depth

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              SANDBOXING LAYERS                                           │
└─────────────────────────────────────────────────────────────────────────────────────────┘

 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │  LAYER 1: NODE ISOLATION                                                                │
 │                                                                                         │
 │   ┌─────────────────────────────────┐    ┌─────────────────────────────────┐           │
 │   │    Sandbox Node Pool            │    │    Default Node Pool            │           │
 │   │    (gVisor enabled)             │    │    (Regular containers)         │           │
 │   │                                 │    │                                 │           │
 │   │  ┌───────┐┌───────┐┌───────┐   │    │  ┌───────┐┌───────┐            │           │
 │   │  │Runner ││Runner ││Runner │   │    │  │Zig API││Postgres│            │           │
 │   │  │  Pod  ││  Pod  ││  Pod  │   │    │  │       ││ Proxy  │            │           │
 │   │  └───────┘└───────┘└───────┘   │    │  └───────┘└───────┘            │           │
 │   │                                 │    │                                 │           │
 │   │  Taint: sandbox.gke.io/runtime │    │  No taint (normal scheduling)  │           │
 │   └─────────────────────────────────┘    └─────────────────────────────────┘           │
 │                                                                                         │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │  LAYER 2: gVisor SYSCALL INTERCEPTION                                                   │
 │                                                                                         │
 │   NORMAL CONTAINER:                                                                     │
 │   ┌──────────────────────────────────────────────────────────────────────────────────┐ │
 │   │  App → syscall → Host Kernel → Hardware                                          │ │
 │   │                      ↑                                                           │ │
 │   │              DANGER: Container escape possible                                   │ │
 │   └──────────────────────────────────────────────────────────────────────────────────┘ │
 │                                                                                         │
 │   gVisor CONTAINER:                                                                     │
 │   ┌──────────────────────────────────────────────────────────────────────────────────┐ │
 │   │  App → syscall → gVisor (userspace kernel) → Limited Host Kernel → Hardware     │ │
 │   │                      ↑                                                           │ │
 │   │              SAFE: Syscalls filtered/emulated in userspace                       │ │
 │   └──────────────────────────────────────────────────────────────────────────────────┘ │
 │                                                                                         │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │  LAYER 3: POD SECURITY CONTEXT                                                          │
 │                                                                                         │
 │   securityContext:                                                                      │
 │     runAsNonRoot: true                    # Never root                                 │
 │     runAsUser: 1000                       # Unprivileged user                          │
 │     readOnlyRootFilesystem: true          # Can't modify system files                  │
 │     allowPrivilegeEscalation: false       # Can't become root                          │
 │     capabilities:                                                                       │
 │       drop: ["ALL"]                       # No special permissions                      │
 │     seccompProfile:                                                                     │
 │       type: RuntimeDefault                # Additional syscall filtering               │
 │                                                                                         │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │  LAYER 4: NETWORK POLICY                                                                │
 │                                                                                         │
 │   ┌────────────────────────────────────────────────────────────────────────────────┐   │
 │   │                     RUNNER POD CAN REACH:                                       │   │
 │   │                                                                                 │   │
 │   │   ✅ api.anthropic.com:443     (Claude API)                                    │   │
 │   │   ✅ Zig API callback          (streaming output)                               │   │
 │   │   ✅ DNS                        (name resolution only)                          │   │
 │   │                                                                                 │   │
 │   │                     RUNNER POD CANNOT REACH:                                    │   │
 │   │                                                                                 │   │
 │   │   ❌ Other pods                                                                 │   │
 │   │   ❌ PostgreSQL                                                                 │   │
 │   │   ❌ Internal services                                                          │   │
 │   │   ❌ Cloud metadata API (169.254.169.254)                                       │   │
 │   │   ❌ Internet (except allowlisted hosts)                                        │   │
 │   │                                                                                 │   │
 │   └────────────────────────────────────────────────────────────────────────────────┘   │
 │                                                                                         │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │  LAYER 5: RESOURCE LIMITS                                                               │
 │                                                                                         │
 │   resources:                                                                            │
 │     limits:                                                                             │
 │       cpu: "2"                             # Max 2 CPU cores                            │
 │       memory: "4Gi"                        # Max 4GB RAM                                │
 │       ephemeral-storage: "10Gi"            # Max 10GB disk                              │
 │                                                                                         │
 │   activeDeadlineSeconds: 3600              # Max 1 hour runtime                         │
 │                                                                                         │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Database Schema: Entity Relationships

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              PLUE DATABASE SCHEMA                                        │
│                              (~40 tables, PostgreSQL)                                    │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─ AUTH DOMAIN ────────────────────────────────────────────────────────────────────────────┐
│                                                                                          │
│   ┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐                       │
│   │   users     │     │  auth_sessions  │     │  access_tokens  │                       │
│   │─────────────│     │─────────────────│     │─────────────────│                       │
│   │ id (PK)     │◄────│ user_id (FK)    │     │ user_id (FK)    │───►│                  │
│   │ username    │     │ session_key (PK)│     │ token_hash      │                       │
│   │ wallet_addr │     │ expires_at      │     │ scopes          │                       │
│   │ email       │     └─────────────────┘     └─────────────────┘                       │
│   │ is_admin    │                                                                        │
│   └─────────────┘     ┌─────────────────┐     ┌─────────────────┐                       │
│          │            │  siwe_nonces    │     │    ssh_keys     │                       │
│          │            │─────────────────│     │─────────────────│                       │
│          │            │ nonce (PK)      │     │ user_id (FK)    │───►│                  │
│          │            │ wallet_address  │     │ fingerprint     │                       │
│          │            │ expires_at      │     │ public_key      │                       │
│          │            └─────────────────┘     └─────────────────┘                       │
│          │                                                                               │
└──────────┼───────────────────────────────────────────────────────────────────────────────┘
           │
           │
┌─ GIT DOMAIN ─────────────────────────────────────────────────────────────────────────────┐
│           │                                                                              │
│           ▼                                                                              │
│   ┌─────────────────┐                                                                    │
│   │  repositories   │                                                                    │
│   │─────────────────│      ┌───────────────┐     ┌──────────────────────┐               │
│   │ id (PK)         │◄─────│   branches    │     │  protected_branches  │               │
│   │ user_id (FK)    │      │───────────────│     │──────────────────────│               │
│   │ name            │      │ repo_id (FK)  │     │ repo_id (FK)         │               │
│   │ is_public       │      │ name          │     │ rule_name            │               │
│   │ default_branch  │      │ commit_id     │     │ required_approvals   │               │
│   └─────────────────┘      │ commit_time   │     │ status_check_contexts│               │
│           │                └───────────────┘     └──────────────────────┘               │
│           │                                                                              │
│   ┌───────┼───────────────────────────────────────────────────────────────────────────┐ │
│   │       │                     JJ-NATIVE (Jujutsu VCS)                                │ │
│   │       │                                                                            │ │
│   │       ▼                                                                            │ │
│   │ ┌───────────────┐     ┌───────────────┐     ┌───────────────┐                     │ │
│   │ │   changes     │     │   bookmarks   │     │  conflicts    │                     │ │
│   │ │───────────────│     │───────────────│     │───────────────│                     │ │
│   │ │ change_id     │◄────│ target_change │     │ change_id     │                     │ │
│   │ │ commit_id     │     │ name          │     │ file_path     │                     │ │
│   │ │ has_conflict  │     │ is_default    │     │ conflict_type │                     │ │
│   │ │ parent_ids    │     └───────────────┘     │ resolved      │                     │ │
│   │ └───────────────┘                           └───────────────┘                     │ │
│   └───────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘

┌─ COLLABORATION DOMAIN ───────────────────────────────────────────────────────────────────┐
│                                                                                          │
│   ┌─────────────┐                     ┌───────────────────┐                             │
│   │   issues    │                     │   pull_requests   │                             │
│   │─────────────│                     │───────────────────│                             │
│   │ id (PK)     │◄────────────────────│ issue_id (FK)     │  (PR extends Issue)         │
│   │ repo_id     │                     │ head_branch       │                             │
│   │ author_id   │                     │ base_branch       │                             │
│   │ issue_number│                     │ status            │                             │
│   │ title       │                     │ has_merged        │                             │
│   │ state       │                     │ merge_style       │                             │
│   │ milestone_id│                     └───────────────────┘                             │
│   └─────────────┘                               │                                        │
│         │                                       │                                        │
│         │                          ┌────────────┴─────────────┐                         │
│         │                          │                          │                         │
│         ▼                          ▼                          ▼                         │
│   ┌─────────────┐          ┌─────────────┐          ┌──────────────────┐               │
│   │  comments   │          │   reviews   │          │  review_comments │               │
│   │─────────────│          │─────────────│          │──────────────────│               │
│   │ issue_id    │          │ pr_id       │◄─────────│ review_id        │               │
│   │ author_id   │          │ reviewer_id │          │ file_path        │               │
│   │ body        │          │ type        │          │ line             │               │
│   └─────────────┘          │ content     │          │ body             │               │
│                            └─────────────┘          └──────────────────┘               │
│                                                                                          │
│   ┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐                       │
│   │   labels    │     │  issue_labels   │     │ issue_assignees │                       │
│   │─────────────│     │─────────────────│     │─────────────────│                       │
│   │ repo_id     │◄────│ label_id        │     │ issue_id        │                       │
│   │ name        │     │ issue_id        │     │ user_id         │                       │
│   │ color       │     └─────────────────┘     └─────────────────┘                       │
│   └─────────────┘                                                                        │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘

┌─ AGENT/WORKFLOW DOMAIN ──────────────────────────────────────────────────────────────────┐
│                                                                                          │
│   ┌──────────────────────┐                                                               │
│   │ workflow_definitions │                                                               │
│   │──────────────────────│      ┌─────────────────┐                                     │
│   │ repo_id              │◄─────│  workflow_runs  │                                     │
│   │ name                 │      │─────────────────│      ┌─────────────────┐            │
│   │ triggers (JSONB)     │      │ definition_id   │◄─────│ workflow_steps  │            │
│   │ plan (DAG)           │      │ trigger_type    │      │─────────────────│            │
│   │ content_hash         │      │ trigger_payload │      │ run_id          │            │
│   └──────────────────────┘      │ status          │      │ step_id         │            │
│                                 │ started_at      │      │ step_type       │  ◄─────┐   │
│                                 │ completed_at    │      │ status          │        │   │
│                                 └─────────────────┘      │ tokens_in/out   │        │   │
│                                                          └─────────────────┘        │   │
│                                                                   │                 │   │
│   ┌─────────────────┐      ┌─────────────────┐                   │                 │   │
│   │ prompt_definitions│     │  workflow_logs  │◄──────────────────┘                 │   │
│   │─────────────────│      │─────────────────│                                      │   │
│   │ repo_id         │      │ step_id         │      ┌─────────────────┐             │   │
│   │ name            │      │ log_type        │      │   runner_pool   │─────────────┘   │
│   │ client          │      │ content         │      │─────────────────│                 │
│   │ prompt_type     │      │ sequence        │      │ pod_name        │                 │
│   │ body_template   │      └─────────────────┘      │ pod_ip          │                 │
│   └─────────────────┘                               │ status          │                 │
│                                                     │ claimed_by_step │                 │
│                                                     └─────────────────┘                 │
│                                                                                          │
│   ┌─ AGENT SESSION STATE ───────────────────────────────────────────────────────────┐   │
│   │                                                                                  │   │
│   │   ┌─────────────┐       ┌─────────────┐       ┌─────────────┐                   │   │
│   │   │  sessions   │◄──────│  messages   │◄──────│    parts    │                   │   │
│   │   │─────────────│       │─────────────│       │─────────────│                   │   │
│   │   │ id (PK)     │       │ session_id  │       │ message_id  │                   │   │
│   │   │ directory   │       │ role        │       │ type        │                   │   │
│   │   │ title       │       │ status      │       │ text        │                   │   │
│   │   │ token_count │       │ tokens_*    │       │ tool_name   │                   │   │
│   │   │ model       │       │ cost        │       │ tool_state  │                   │   │
│   │   └─────────────┘       └─────────────┘       └─────────────┘                   │   │
│   │                                                                                  │   │
│   └──────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Git Caching Strategy

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                    GIT CONTENT-ADDRESSABLE CACHING                                       │
│                                                                                          │
│   KEY INSIGHT: Git SHA = hash(content), making most objects immutable forever           │
└─────────────────────────────────────────────────────────────────────────────────────────┘

  REQUEST: GET /api/torvalds/linux/blob/master/README

  STEP 1: RESOLVE REF (Only mutable part - short cache)
  ──────────────────────────────────────────────────────────────────────────────────────────

  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │   Cache Key: master@torvalds/linux                                                   │
  │   TTL: 5 seconds                                                                     │
  │   Value: commit abc123def456...                                                      │
  │                                                                                      │
  │   On miss: Zig calls jj-lib to resolve: refs/heads/master → abc123def456...         │
  └─────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        │ commit = abc123def456
                                        ▼

  STEP 2: GET BLOB (Immutable - cache forever)
  ──────────────────────────────────────────────────────────────────────────────────────────

  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │   Cache Key: abc123def456:/README                                                    │
  │   TTL: 31536000 (1 year, effectively forever)                                       │
  │   Value: <file content>                                                              │
  │                                                                                      │
  │   This NEVER changes because:                                                        │
  │   - If README content changes → different SHA → different cache key                 │
  │   - Same SHA = same content (cryptographic guarantee)                               │
  └─────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼

  STEP 3: RETURN WITH HEADERS
  ──────────────────────────────────────────────────────────────────────────────────────────

  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │   HTTP/1.1 200 OK                                                                    │
  │   Cache-Control: public, max-age=31536000, immutable                                │
  │   ETag: "abc123def456"                                                               │
  │   Content-Type: text/plain                                                           │
  │                                                                                      │
  │   # Linux README                                                                     │
  │   ...                                                                                │
  └─────────────────────────────────────────────────────────────────────────────────────┘


  CACHE BEHAVIOR MATRIX:
  ╔═══════════════════════╦═════════════════╦═══════════════════════════════════════════╗
  ║ Object Type           ║ Cache TTL       ║ Why                                       ║
  ╠═══════════════════════╬═════════════════╬═══════════════════════════════════════════╣
  ║ Ref → Commit          ║ 5 seconds       ║ Only mutable part (changes on push)       ║
  ╠═══════════════════════╬═════════════════╬═══════════════════════════════════════════╣
  ║ Commit → Tree         ║ Forever         ║ Immutable (SHA = hash of content)         ║
  ╠═══════════════════════╬═════════════════╬═══════════════════════════════════════════╣
  ║ Tree → Entries        ║ Forever         ║ Immutable (SHA = hash of content)         ║
  ╠═══════════════════════╬═════════════════╬═══════════════════════════════════════════╣
  ║ Blob → Content        ║ Forever         ║ Immutable (SHA = hash of content)         ║
  ╚═══════════════════════╩═════════════════╩═══════════════════════════════════════════╝
```

---

## Edge Caching Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                         CLOUDFLARE EDGE CACHING FLOW                                     │
└─────────────────────────────────────────────────────────────────────────────────────────┘

   Request ───┬──────────────────────────────────────────────────────────────────────────►
              │
              ▼
    ┌─────────────────────────────────────┐
    │      Has session cookie?            │
    │                                     │
    │   cookies.includes('session=')      │
    └─────────────────────────────────────┘
              │
       ┌──────┴──────┐
       │             │
      YES           NO
       │             │
       ▼             ▼
   ┌────────┐  ┌─────────────────────────────┐
   │ BYPASS │  │    Check Workers Cache       │
   │ cache  │  │                              │
   │        │  │  Cache key includes:         │
   │ X-Cache│  │  • URL path                  │
   │ BYPASS │  │  • BUILD_VERSION (deploy)    │
   └────────┘  │                              │
       │       └─────────────────────────────┘
       │                    │
       │           ┌───────┴───────┐
       │           │               │
       │          HIT            MISS
       │           │               │
       │           ▼               ▼
       │    ┌────────────┐  ┌────────────────────────┐
       │    │ Return     │  │ Fetch from origin      │
       │    │ cached     │  │                        │
       │    │            │  │ Check Cache-Control:   │
       │    │ X-Cache:   │  │ - public?              │
       │    │ HIT        │  │ - max-age?             │
       │    └────────────┘  │                        │
       │           │        │ If yes: cache.put()    │
       │           │        │                        │
       │           │        │ X-Cache: MISS          │
       │           │        └────────────────────────┘
       │           │               │
       └───────────┴───────────────┘
                   │
                   ▼
              Response


  CACHE INVALIDATION STRATEGIES:
  ╔════════════════════════╦══════════════════════════╦════════════════════════════════════╗
  ║ Strategy               ║ Use Case                 ║ How                                ║
  ╠════════════════════════╬══════════════════════════╬════════════════════════════════════╣
  ║ Deploy version         ║ Invalidate all on deploy ║ BUILD_VERSION in cache key         ║
  ╠════════════════════════╬══════════════════════════╬════════════════════════════════════╣
  ║ Cache-Tag purge        ║ Targeted invalidation    ║ Cache-Tag header + Cloudflare API  ║
  ╠════════════════════════╬══════════════════════════╬════════════════════════════════════╣
  ║ TTL expiry             ║ Time-based refresh       ║ Cache-Control: max-age=N           ║
  ╚════════════════════════╩══════════════════════════╩════════════════════════════════════╝


  ASTRO CACHE HELPERS (ui/lib/cache.ts):
  ┌──────────────────────────────────────────────────────────────────────────────────────┐
  │                                                                                      │
  │  cacheStatic(Astro)              → max-age=31536000, immutable                      │
  │  cacheWithTags(Astro, tags)      → max-age=86400 + Cache-Tag: user:123,repo:456     │
  │  cacheShort(Astro, tags, 60)     → max-age=60, stale-while-revalidate=3600          │
  │  noCache(Astro)                  → no-store (personalized content)                  │
  │                                                                                      │
  └──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Warm Pool Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                          WARM RUNNER POOL                                                │
│                                                                                          │
│   Goal: Sub-500ms latency from task creation to execution start                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘

  ┌───────────────────────────────────────────────────────────────────────────────────────┐
  │                              POSTGRESQL (Queue)                                        │
  │                                                                                        │
  │   workflow_steps table:                                                                │
  │   ┌────┬────────┬─────────┬───────────┬────────────┬─────────────┐                   │
  │   │ id │ run_id │ status  │ runner_id │ created_at │ started_at  │                   │
  │   ├────┼────────┼─────────┼───────────┼────────────┼─────────────┤                   │
  │   │ 1  │   10   │ done    │   pod-a   │ 10:00:00   │ 10:00:01    │                   │
  │   │ 2  │   11   │ running │   pod-b   │ 10:00:05   │ 10:00:06    │                   │
  │   │ 3  │   12   │ waiting │   NULL    │ 10:00:10   │ NULL        │ ← Next            │
  │   │ 4  │   13   │ waiting │   NULL    │ 10:00:15   │ NULL        │                   │
  │   └────┴────────┴─────────┴───────────┴────────────┴─────────────┘                   │
  │                                                                                        │
  │   runner_pool table:                                                                   │
  │   ┌────┬───────────────┬─────────────┬───────────┬─────────────────┐                 │
  │   │ id │ pod_name      │ status      │ pod_ip    │ claimed_by_step │                 │
  │   ├────┼───────────────┼─────────────┼───────────┼─────────────────┤                 │
  │   │ 1  │ runner-pool-a │ available   │ 10.0.1.5  │ NULL            │ ← Claim this    │
  │   │ 2  │ runner-pool-b │ claimed     │ 10.0.1.6  │ 2               │                 │
  │   │ 3  │ runner-pool-c │ available   │ 10.0.1.7  │ NULL            │                 │
  │   └────┴───────────────┴─────────────┴───────────┴─────────────────┘                 │
  │                                                                                        │
  └───────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        │ Poll every 1s
                                        ▼
  ┌───────────────────────────────────────────────────────────────────────────────────────┐
  │                              ZIG QUEUE WATCHER                                         │
  │                                                                                        │
  │   while (true) {                                                                       │
  │       // Find waiting steps                                                            │
  │       steps = SELECT * FROM workflow_steps WHERE status = 'waiting'                   │
  │                FOR UPDATE SKIP LOCKED LIMIT 10;                                        │
  │                                                                                        │
  │       for (step in steps) {                                                            │
  │           // Atomic claim from warm pool                                               │
  │           runner = WITH claimed AS (                                                   │
  │               SELECT id FROM runner_pool                                               │
  │               WHERE status = 'available'                                               │
  │               FOR UPDATE SKIP LOCKED LIMIT 1                                           │
  │           )                                                                            │
  │           UPDATE runner_pool SET status = 'claimed',                                   │
  │                                  claimed_by_step = step.id                             │
  │           WHERE id = claimed.id RETURNING *;                                           │
  │                                                                                        │
  │           if (runner) {                                                                │
  │               // Fast path: <500ms                                                     │
  │               http_post(runner.pod_ip, step.config);                                  │
  │           } else {                                                                     │
  │               // Slow path: create K8s Job (3-5s)                                      │
  │               k8s.createJob(step);                                                     │
  │           }                                                                            │
  │       }                                                                                │
  │       sleep(1s);                                                                       │
  │   }                                                                                    │
  │                                                                                        │
  └───────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                         ┌──────────────┴──────────────┐
                         │                             │
                         ▼                             ▼
  ┌──────────────────────────────────┐  ┌──────────────────────────────────┐
  │          WARM POOL               │  │          COLD START              │
  │          (< 500ms)               │  │          (3-5 seconds)           │
  │                                  │  │                                  │
  │  ┌────────┐ ┌────────┐ ┌──────┐ │  │   K8s creates Job:               │
  │  │ Standby│ │ Standby│ │Standby│ │  │   - Pull image (if not cached)  │
  │  │ Runner │ │ Runner │ │Runner │ │  │   - Schedule to sandbox node    │
  │  │ (idle) │ │ (idle) │ │(idle) │ │  │   - Start gVisor runtime        │
  │  └────────┘ └────────┘ └──────┘ │  │   - Wait for ready probe         │
  │                                  │  │                                  │
  │  K8s Deployment keeps 5 ready    │  │  Used when pool exhausted        │
  │  Auto-scales based on demand     │  │  Image pre-pulled on nodes       │
  └──────────────────────────────────┘  └──────────────────────────────────┘


  LATENCY COMPARISON:
  ╔═══════════════════════════════╦═══════════════╦═════════════════════════════════════╗
  ║ Scenario                      ║ Latency       ║ Notes                               ║
  ╠═══════════════════════════════╬═══════════════╬═════════════════════════════════════╣
  ║ Warm pool hit                 ║ < 500ms       ║ Claim pod + HTTP POST assignment    ║
  ╠═══════════════════════════════╬═══════════════╬═════════════════════════════════════╣
  ║ Pool empty, cold start        ║ 3-5s          ║ K8s scheduling + container start    ║
  ╠═══════════════════════════════╬═══════════════╬═════════════════════════════════════╣
  ║ Pool empty, image not cached  ║ 30s+          ║ Image pull required                 ║
  ╚═══════════════════════════════╩═══════════════╩═════════════════════════════════════╝
```

---

## Infrastructure Topology

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              PRODUCTION INFRASTRUCTURE                                   │
└─────────────────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────────────┐
                              │      INTERNET       │
                              └──────────┬──────────┘
                                         │
                              ┌──────────┴──────────┐
                              │                     │
                              ▼                     ▼
                    ┌─────────────────┐   ┌─────────────────┐
                    │   CLOUDFLARE    │   │    SSH Client   │
                    │                 │   │                 │
                    │ • Edge Worker   │   │                 │
                    │ • DDoS protect  │   │                 │
                    │ • SSL terminate │   │                 │
                    │ • Cache static  │   │                 │
                    └────────┬────────┘   └────────┬────────┘
                             │                     │
                             │ HTTPS               │ SSH (port 22)
                             │                     │
┌────────────────────────────┼─────────────────────┼─────────────────────────────────────┐
│                            │    GCP PROJECT      │                                      │
│                            │                     │                                      │
│   ┌────────────────────────┴─────────────────────┴───────────────────────────────────┐ │
│   │                              GKE CLUSTER (Regional)                               │ │
│   │                                                                                   │ │
│   │   ┌─────────────────────────────────────────────────────────────────────────────┐│ │
│   │   │                     DEFAULT NODE POOL                                        ││ │
│   │   │                     (3x e2-standard-4, multi-zone)                           ││ │
│   │   │                                                                             ││ │
│   │   │   ┌─────────────────────────────────────────────────────────────────────┐  ││ │
│   │   │   │                    NAMESPACE: production                             │  ││ │
│   │   │   │                                                                      │  ││ │
│   │   │   │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │  ││ │
│   │   │   │   │   zig-api    │  │   zig-api    │  │   zig-api    │              │  ││ │
│   │   │   │   │   (zone-a)   │  │   (zone-b)   │  │   (zone-c)   │              │  ││ │
│   │   │   │   │              │  │              │  │              │              │  ││ │
│   │   │   │   │  HTTP :4000  │  │  HTTP :4000  │  │  HTTP :4000  │              │  ││ │
│   │   │   │   │  SSH :2222   │  │  SSH :2222   │  │  SSH :2222   │              │  ││ │
│   │   │   │   └──────────────┘  └──────────────┘  └──────────────┘              │  ││ │
│   │   │   │                           │                                          │  ││ │
│   │   │   │                    LoadBalancer Service                              │  ││ │
│   │   │   │                           │                                          │  ││ │
│   │   │   └───────────────────────────┼──────────────────────────────────────────┘  ││ │
│   │   │                               │                                             ││ │
│   │   └───────────────────────────────┼─────────────────────────────────────────────┘│ │
│   │                                   │                                              │ │
│   │   ┌───────────────────────────────┼──────────────────────────────────────────────┐│ │
│   │   │             SANDBOX NODE POOL │(gVisor, auto-scale 2-20)                     ││ │
│   │   │                               │                                              ││ │
│   │   │   ┌───────────────────────────┴────────────────────────────────────────────┐││ │
│   │   │   │                    NAMESPACE: workflows                                 │││ │
│   │   │   │                                                                         │││ │
│   │   │   │   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │││ │
│   │   │   │   │ Standby  │ │ Standby  │ │ Standby  │ │ Standby  │ │ Standby  │    │││ │
│   │   │   │   │ Runner 1 │ │ Runner 2 │ │ Runner 3 │ │ Runner 4 │ │ Runner 5 │    │││ │
│   │   │   │   │ (Python) │ │ (Python) │ │ (Python) │ │ (Python) │ │ (Python) │    │││ │
│   │   │   │   │ gVisor   │ │ gVisor   │ │ gVisor   │ │ gVisor   │ │ gVisor   │    │││ │
│   │   │   │   └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘    │││ │
│   │   │   │                                                                         │││ │
│   │   │   │   NetworkPolicy: Only reach api.anthropic.com:443 + Zig callback       │││ │
│   │   │   │                                                                         │││ │
│   │   │   └─────────────────────────────────────────────────────────────────────────┘││ │
│   │   │                                                                              ││ │
│   │   └──────────────────────────────────────────────────────────────────────────────┘│ │
│   │                                                                                   │ │
│   └───────────────────────────────────────────────────────────────────────────────────┘ │
│                                         │                                               │
│                            Private IP   │                                               │
│                                         ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐  │
│   │                         CLOUD SQL (PostgreSQL 16)                                │  │
│   │                         (db-custom-2-8192, HA, multi-zone)                       │  │
│   │                                                                                  │  │
│   │   • Automated daily backups                                                      │  │
│   │   • Point-in-time recovery (7 days)                                              │  │
│   │   • Private IP only (no public access)                                           │  │
│   │   • Query insights enabled                                                       │  │
│   │                                                                                  │  │
│   └─────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐  │
│   │                              MONITORING                                          │  │
│   │                                                                                  │  │
│   │   Cloud Monitoring │ Cloud Logging │ Uptime Checks │ PagerDuty Integration      │  │
│   │                                                                                  │  │
│   └─────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack Summary

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                 TECH STACK                                               │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│   LANGUAGE        │  PURPOSE                                                            │
│   ────────────────┼─────────────────────────────────────────────────────────────────── │
│   Zig             │  API server, SSH server, WebSocket, auth, orchestration            │
│   Rust            │  jj-lib FFI (Git operations via Jujutsu VCS library)               │
│   TypeScript      │  Astro frontend (SSR), Edge Worker, E2E tests                      │
│   Python          │  Agent runtime, workflow executor, tool implementations            │
│   SQL             │  PostgreSQL schema (~40 tables)                                     │
│   HCL             │  Terraform infrastructure-as-code                                   │
│                                                                                          │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│   INFRASTRUCTURE  │  PURPOSE                                                            │
│   ────────────────┼─────────────────────────────────────────────────────────────────── │
│   GKE             │  Kubernetes cluster (default pool + gVisor sandbox pool)           │
│   Cloud SQL       │  Managed PostgreSQL 16 with HA                                      │
│   Cloudflare      │  CDN, DDoS protection, Edge Workers                                 │
│   gVisor          │  Userspace kernel for sandboxed container execution                 │
│   Terraform       │  Infrastructure provisioning and management                         │
│   Helm            │  Kubernetes deployment charts                                       │
│                                                                                          │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│   KEY LIBRARIES   │  PURPOSE                                                            │
│   ────────────────┼─────────────────────────────────────────────────────────────────── │
│   httpz           │  Zig HTTP server framework                                          │
│   jj-lib          │  Jujutsu VCS library for Git operations                             │
│   Astro v5        │  SSR frontend framework                                             │
│   Playwright      │  E2E testing                                                        │
│   anthropic-sdk   │  Claude API client for agent execution                              │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Architectural Decisions

| Decision | Approach | Why |
|----------|----------|-----|
| **Language** | Zig for server | Performance, memory safety, no runtime, compiles to single binary |
| **VCS Backend** | Jujutsu (jj) | First-class change tracking, better than Git for collaboration |
| **Auth** | SIWE (Ethereum) | Passwordless, decentralized, wallet-based identity |
| **Sandboxing** | gVisor on GKE | Syscall interception, stronger than namespaces alone |
| **Streaming** | SSE (not WebSocket) | Simpler, HTTP-native, auto-reconnect, HTTP/2 multiplexing |
| **Caching** | Content-addressable | Git SHAs are perfect cache keys (immutable by design) |
| **Edge** | Cloudflare Workers | Global distribution, version-based invalidation |
| **Database** | PostgreSQL (not Edge) | Complex joins, full ACID, co-located with agents |
| **Warm Pool** | Standby pods | Sub-500ms task start vs 3-5s cold start |

---

## Project Structure

```
plue/
├── server/            # Zig API server (httpz)
│   ├── src/ai/        # Agent system + tools
│   ├── src/routes/    # API handlers
│   ├── src/ssh/       # SSH server for Git
│   ├── src/workflows/ # Workflow execution
│   └── jj-ffi/        # Rust FFI for jj-lib
├── ui/                # Astro SSR frontend
│   ├── pages/         # Astro pages
│   ├── components/    # UI components
│   └── lib/           # Utilities (auth, cache, git, etc.)
├── edge/              # Cloudflare Workers caching proxy
│   ├── index.ts       # Main worker (proxy + cache)
│   ├── purge.ts       # Cache purge utilities
│   └── types.ts       # Environment bindings
├── db/                # Database layer
│   ├── schema.sql     # PostgreSQL schema
│   └── daos/          # Data Access Objects (Zig)
├── runner/            # Agent execution environment (Python)
│   └── src/
│       ├── agent.py   # Claude agent runtime
│       ├── workflow.py# Workflow executor
│       └── tools/     # Tool implementations
├── e2e/               # End-to-end tests (Playwright)
├── infra/             # All deployment infrastructure
│   ├── terraform/     # Infrastructure as code
│   ├── helm/          # Helm charts
│   ├── k8s/           # Kubernetes manifests
│   └── docker/        # Dockerfile, docker-compose
└── docs/              # Additional documentation
```

---

## Quick Start

```bash
# Prerequisites: Docker, Zig 0.15.1+, Bun

# Start everything
zig build run          # Docker + Zig server (localhost:4000)
zig build run:web      # Astro dev server (localhost:3000) - separate terminal

# Run tests
zig build test         # All tests (Zig + TS + Rust)
```

---

## Key Innovations

1. **Unified workflow/agent model** - Same sandboxed infrastructure for CI and AI agents
2. **Content-addressable caching** - Leveraging Git's immutability for infinite cache TTLs
3. **gVisor sandboxing** - Userspace kernel for safe execution of untrusted code
4. **Warm pool** - Pre-warmed pods for sub-500ms agent response times
5. **Zig + Rust FFI** - Performance-critical paths in systems languages
6. **Jujutsu VCS** - First-class change tracking with stable change IDs across rebases
