# Plue Architecture

This document describes the Plue architecture, the decisions behind it, and guidance for implementation.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Previous Architecture](#previous-architecture)
3. [New Architecture](#new-architecture)
4. [Component Deep Dives](#component-deep-dives)
   - [Git File Server](#git-file-server)
   - [Database Layer](#database-layer)
   - [Agent & Workflow System](#agent--workflow-system)
   - [Sandboxing](#sandboxing)
   - [Real-time Streaming](#real-time-streaming)
5. [Migration Guide](#migration-guide)
6. [Infrastructure](#infrastructure)

---

## Executive Summary

Plue is a brutalist GitHub clone with integrated AI agent capabilities. This document describes a significant architectural simplification that:

- **Removes ElectricSQL** — wasn't providing value for our use case
- **Removes Edge SQLite (Durable Objects)** — over-engineered for our needs
- **Unifies Workflows and Agents** — same sandbox, same abstraction
- **Simplifies Git file serving** — leverage Git's content-addressable nature
- **Adopts WebSocket for streaming** — direct push, no sync layer

### Before vs After

```
BEFORE                                  AFTER
──────                                  ─────
Postgres ──► Electric ──► Edge DO       Postgres ◄──► Zig Server
                │            │                            │
                ▼            ▼                            ▼
            Zig Proxy    SQLite Cache              CDN + WebSocket
                │                                        │
                ▼                                        ▼
             Client                                   Client

Components: 5                           Components: 3
Sync layers: 2                          Sync layers: 0
Complexity: High                        Complexity: Low
```

---

## Previous Architecture

### System Diagram (Before)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CLIENTS                                     │
└─────────────────────────────────────────────────────────────────────────┘
                    │                                    │
                    │ HTTP (shapes)                      │ HTTP (API)
                    ▼                                    ▼
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│      Cloudflare Edge            │    │         Zig Server              │
│  ┌───────────────────────────┐  │    │                                 │
│  │   Durable Object          │  │    │  - REST API                     │
│  │   - SQLite cache          │  │    │  - /shape proxy (broken)        │
│  │   - Shape sync            │  │    │  - Auth (SIWE, JWT)             │
│  │   - Merkle validation     │  │    │  - Git operations (jj-lib)      │
│  │   - 5s TTL polling        │  │    │  - WebSocket/PTY                │
│  └───────────────────────────┘  │    │  - Agent execution              │
└─────────────────────────────────┘    └─────────────────────────────────┘
                    │                                    │
                    │ HTTP (shapes)                      │ SQL
                    ▼                                    ▼
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│         ElectricSQL             │    │          PostgreSQL             │
│  - Shape definitions            │◄───│  - Users, repos, issues         │
│  - Logical replication          │    │  - Sessions, messages, parts    │
│  - HTTP shape protocol          │    │  - Workflows                    │
└─────────────────────────────────┘    └─────────────────────────────────┘
```

### Problems with Previous Architecture

#### 1. ElectricSQL Not Actually Used

The UI hooks in `ui/lib/electric.ts` were stubs that threw errors:

```typescript
export function useSessionsShape(where?: string) {
  throw new Error(
    'useSessionsShape must be imported from a client component.\n' +
    'ElectricSQL is not configured.'
  );
}
```

Astro pages queried Postgres directly instead:

```typescript
// ui/pages/[user]/[repo]/issues/index.astro
const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
```

#### 2. Broken Shape Proxy

The Zig `/shape` proxy didn't forward Electric's headers:

```zig
// routes.zig:447-449
// Note: Zig 0.15.1 fetch() doesn't provide access to response headers
// like electric-offset, electric-handle, etc.
```

This broke shape resumption — clients couldn't continue from their last offset.

#### 3. Edge DO Complexity

The Durable Object in `edge/src/durable-objects/data-sync.ts`:
- Synced Electric shapes into SQLite
- Tracked merkle roots for git cache validation
- Used 5-second TTL polling or push invalidation
- Added latency without providing real-time updates

#### 4. Agent Streaming Latency

For agent chat, the path was:
```
Claude API → Zig → Postgres → Electric → (broken proxy) → Client
```

This added seconds of latency for what should be real-time token streaming.

#### 5. Git Data Wasn't Even in Electric

Git trees and files came from jj-lib on the filesystem, not Postgres. Electric couldn't help here at all.

### Why Electric Didn't Fit

Electric excels when you have:
- Many clients syncing the same shapes
- CDN caching of shape responses
- Read-heavy, write-light workloads

Plue's reality:
- Agent streaming needs <100ms latency
- Git data isn't in Postgres
- Writes need Zig server regardless
- Complex relational queries don't fit single-table shapes

---

## New Architecture

### System Diagram (After)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CLIENTS                                     │
│                                                                          │
│   Browser ◄──────────────────────────────────────────────► Browser      │
│      │                                                         │         │
│      │ WebSocket (streaming)              REST + Cache (reads) │         │
│      │                                                         │         │
└──────┼─────────────────────────────────────────────────────────┼─────────┘
       │                                                         │
       │                    ┌─────────────────┐                  │
       │                    │   Cloudflare    │                  │
       │                    │   CDN           │◄─────────────────┘
       │                    │                 │
       │                    │ - Static assets │
       │                    │ - Git blobs     │
       │                    │ - API responses │
       │                    └────────┬────────┘
       │                             │
       │                             │ Cache miss
       ▼                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           ZIG SERVER                                     │
│                                                                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │   REST API  │  │  WebSocket  │  │  Auth       │  │  K8s Client │    │
│  │             │  │  Server     │  │  (SIWE/JWT) │  │             │    │
│  │  - CRUD     │  │             │  │             │  │  - Create   │    │
│  │  - Git tree │  │  - Agent    │  │  - Login    │  │    Jobs     │    │
│  │  - Git blob │  │    stream   │  │  - Validate │  │  - Watch    │    │
│  │             │  │  - PTY      │  │  - Sessions │  │    status   │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
│         │                │                                │             │
│         │                │                                │             │
│         ▼                ▼                                ▼             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                         jj-lib (FFI)                             │   │
│  │   Git operations, tree walking, file content, snapshots          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│         PostgreSQL              │  │      Kubernetes (GKE)           │
│                                 │  │                                 │
│  - Users, auth, sessions        │  │  ┌─────────────────────────┐   │
│  - Repositories, issues, PRs    │  │  │   Workflow/Agent Pods   │   │
│  - Agent messages, parts        │  │  │   (gVisor sandbox)      │   │
│  - Workflow queue               │  │  │                         │   │
│  - All application state        │  │  │   - Sandboxed execution │   │
│                                 │  │  │   - File system access  │   │
│                                 │  │  │   - Network restricted  │   │
│                                 │  │  └─────────────────────────┘   │
└─────────────────────────────────┘  └─────────────────────────────────┘
```

### Key Principles

1. **Postgres is the source of truth** — all state lives here
2. **Zig is the application server** — API, auth, git ops, orchestration
3. **CDN for caching** — not replication, just HTTP caching
4. **WebSocket for real-time** — direct push, no sync layer
5. **K8s for sandboxed execution** — workflows and agents are the same thing

---

## Component Deep Dives

### Git File Server

#### The Insight: Git is Content-Addressable

Git already provides perfect cache keys:

```
blob SHA = hash(content)      # Immutable forever
tree SHA = hash(entries)      # Immutable forever
commit SHA = hash(...)        # Immutable forever
ref (branch/tag) = pointer    # ONLY mutable part
```

#### Caching Strategy

| What | Cache TTL | Why |
|------|-----------|-----|
| Ref → commit | 5 seconds or webhook | Mutable, changes on push |
| Commit → tree | Forever | Immutable |
| Tree → entries | Forever | Immutable |
| Blob → content | Forever | Immutable |

#### Request Flow

```
Client: GET /api/torvalds/linux/blob/master/README

Step 1: Resolve ref (only part that can be stale)
┌─────────────────────────────────────────────────────────┐
│  Cache: master@torvalds/linux → commit abc123           │
│  TTL: 5 seconds                                         │
│  On miss: Zig calls jj-lib to resolve ref               │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
Step 2: Get tree/blob (immutable, cache forever)
┌─────────────────────────────────────────────────────────┐
│  Cache key: abc123:/README                              │
│  TTL: Forever (immutable by SHA)                        │
│  On miss: Zig calls jj-lib to read blob                 │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
Step 3: Return with cache headers
┌─────────────────────────────────────────────────────────┐
│  Cache-Control: public, max-age=31536000, immutable     │
│  ETag: "abc123"                                         │
└─────────────────────────────────────────────────────────┘
```

#### API Design

```
# Ref resolution (short cache)
GET /api/:owner/:repo/refs/:ref
Response: { "commit": "abc123def456..." }
Cache-Control: public, max-age=5

# Tree by commit SHA (cache forever)
GET /api/:owner/:repo/tree/:commit_sha/:path
Response: [{ "name": "src", "type": "tree", "sha": "..." }, ...]
Cache-Control: public, max-age=31536000, immutable

# Blob by commit SHA (cache forever)
GET /api/:owner/:repo/blob/:commit_sha/:path
Response: <file content>
Cache-Control: public, max-age=31536000, immutable
```

#### What We Removed

- **merkle_roots table** — Git SHAs are the merkle roots
- **Edge DO git cache** — CDN does this better with less complexity
- **Push invalidation system** — Only ref cache needs short TTL

---

### Database Layer

#### Why Postgres, Not Edge SQLite

| Factor | Postgres | Edge SQLite (D1/DO) |
|--------|----------|---------------------|
| Complex joins | ✅ Native | ⚠️ Limited |
| Foreign keys | ✅ Enforced | ❌ Not across network |
| Transactions | ✅ Full ACID | ⚠️ Limited |
| Collaborative data | ✅ Designed for it | ❌ Single-user oriented |
| Agent execution | ✅ Co-located | ❌ Edge can't run agents |

#### Data Model Categories

```sql
-- AUTH (low frequency, no real-time needs)
users, auth_sessions, access_tokens, siwe_nonces, ssh_keys

-- GIT METADATA (updates on push, moderate frequency)
repositories, branches, protected_branches

-- COLLABORATION (moderate frequency, some real-time)
issues, comments, labels, milestones, pull_requests, reviews

-- AGENT STATE (high frequency during execution, needs streaming)
sessions, messages, parts, subtasks, file_trackers

-- WORKFLOWS (moderate frequency, needs status updates)
workflow_runs, workflow_jobs, workflow_tasks, workflow_logs
```

#### Real-Time Strategy by Data Type

| Data | Update Frequency | Strategy |
|------|------------------|----------|
| Agent parts | High (token streaming) | **WebSocket push** |
| Workflow logs | High (during execution) | **WebSocket push** |
| Issues/PRs | Low | **REST + polling or SSE** |
| Git metadata | On push only | **Webhook + cache invalidation** |

---

### Agent & Workflow System

#### The Unification Insight

Workflows and agents are fundamentally the same:

| Aspect | Traditional Workflow | Agent | Unified Model |
|--------|---------------------|-------|---------------|
| Trigger | Event (push, PR) | User prompt | **Event** |
| Execution | Predefined steps | LLM decides | **Steps** |
| Environment | Container | Container | **Sandboxed pod** |
| Capabilities | Shell, files, git | Shell, files, git | **Same tools** |

The only difference is **who decides the steps**:
- Workflow: Code/YAML defines steps upfront
- Agent: LLM decides steps dynamically

#### Unified Event Model

```python
events = [
    # Traditional CI triggers
    "push",
    "pull_request",
    "pull_request.review",
    "issue.opened",
    "issue.comment",
    "schedule",
    "workflow_dispatch",  # manual trigger

    # Agent triggers
    "user_prompt",        # Chat message
    "mention",            # @plue-bot in comment
]
```

#### Workflow Definition Examples

**Scripted Mode (Traditional CI):**
```yaml
# .plue/workflows/ci.yaml
name: CI
on: [push, pull_request]
mode: scripted

jobs:
  test:
    runs-on: sandbox
    steps:
      - name: Checkout
        run: jj workspace update-stale
      - name: Install
        run: bun install
      - name: Test
        run: bun test
      - name: Build
        run: bun run build
```

**Agent Mode (AI-powered):**
```yaml
# .plue/workflows/code-review.yaml
name: AI Code Review
on: [pull_request]
mode: agent

agent:
  model: claude-sonnet-4-20250514
  system: |
    You are a code reviewer for this repository.
    Review the PR diff for bugs, security issues, and style.
    Leave inline comments and approve or request changes.
  tools:
    - read_file
    - search_code
    - pr_diff
    - pr_comment
    - pr_review
  max_turns: 20
  timeout: 600  # 10 minutes
```

**Agent Mode (Issue Helper):**
```yaml
# .plue/workflows/issue-helper.yaml
name: Issue Helper
on:
  issue.comment:
    contains: "@plue"
mode: agent

agent:
  model: claude-sonnet-4-20250514
  system: |
    You help users with issues in this repository.
    You can read code, explain behavior, suggest fixes, and create PRs.
  tools:
    - read_file
    - search_code
    - list_files
    - create_branch
    - write_file
    - commit
    - create_pr
    - comment_on_issue
```

#### Execution Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           EVENT OCCURS                                   │
│   (push, PR, issue comment with @plue, user opens chat, etc.)           │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          ZIG SERVER                                      │
│                                                                          │
│  1. Match event to workflow definitions in repo                          │
│  2. Create workflow_run record in Postgres                               │
│  3. Create workflow_task record (status = waiting)                       │
│  4. Claim runner from warm pool OR create K8s Job                        │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
          ┌────────┴────────┐           ┌────────┴────────┐
          │   WARM POOL     │           │   COLD START    │
          │   (< 500ms)     │           │   (3-5 seconds) │
          │                 │           │                 │
          │ Claim standby   │           │ Create K8s Job  │
          │ pod, send       │           │ Wait for pod    │
          │ assignment      │           │ to be ready     │
          └────────┬────────┘           └────────┬────────┘
                   │                             │
                   └──────────────┬──────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      SANDBOXED RUNNER POD                                │
│                         (gVisor runtime)                                 │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                        RUNNER PROCESS                              │  │
│  │                                                                    │  │
│  │   if mode == "scripted":                                          │  │
│  │       for step in workflow.steps:                                 │  │
│  │           execute_step(step)                                      │  │
│  │           stream_output_to_zig()                                  │  │
│  │                                                                    │  │
│  │   elif mode == "agent":                                           │  │
│  │       agent = Agent(model, system_prompt, tools)                  │  │
│  │       while not done and turns < max_turns:                       │  │
│  │           response = agent.run(prompt)                            │  │
│  │           stream_tokens_to_zig()                                  │  │
│  │           execute_tool_calls()                                    │  │
│  │           stream_tool_results_to_zig()                            │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │   AVAILABLE TOOLS (both modes)                                     │  │
│  │                                                                    │  │
│  │   File System:  read_file, write_file, list_files, search_code   │  │
│  │   Git (jj):     status, diff, commit, branch, merge              │  │
│  │   Shell:        run_command (sandboxed)                          │  │
│  │   GitHub-like:  create_issue, comment, create_pr, review         │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ Stream output
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          ZIG SERVER                                      │
│                                                                          │
│  - Receive streaming output from runner                                  │
│  - Push to client via WebSocket                                          │
│  - Batch persist to Postgres (messages, parts tables)                    │
│  - Update workflow_task status on completion                             │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ WebSocket
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            CLIENT                                        │
│                                                                          │
│  - Render streaming tokens in real-time                                  │
│  - Show tool call progress                                               │
│  - Display final results                                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### Sandboxing

#### Why Sandboxing is Critical

Agents and workflows execute arbitrary code:
- Shell commands from LLM decisions
- User-defined workflow scripts
- File system modifications

Without sandboxing, a malicious or buggy agent could:
- Access other users' data
- Escape to the host system
- Attack internal services
- Consume unlimited resources

#### GKE Sandbox (gVisor)

GKE has native gVisor support. gVisor intercepts syscalls in userspace — the agent never talks directly to the host kernel.

```
┌─────────────────────────────────────────────────────────────┐
│                    NORMAL CONTAINER                          │
│   App ──► syscall ──► Host Kernel ──► Hardware              │
│                          ↑                                   │
│                     DANGER ZONE                              │
│              (container escape possible)                     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    gVisor CONTAINER                          │
│   App ──► syscall ──► gVisor (userspace) ──► Limited Host   │
│                          ↑                                   │
│                    INTERCEPTED                               │
│              (syscalls filtered/emulated)                    │
└─────────────────────────────────────────────────────────────┘
```

#### Defense in Depth

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          GKE CLUSTER                                     │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    LAYER 1: Node Isolation                         │  │
│  │                                                                    │  │
│  │   Sandbox Node Pool              Regular Node Pool                 │  │
│  │   (gVisor enabled)               (Zig API, Postgres)              │  │
│  │   ┌─────┐ ┌─────┐ ┌─────┐       ┌─────┐ ┌─────┐                   │  │
│  │   │Agent│ │Agent│ │Agent│       │ Zig │ │ DB  │                   │  │
│  │   │ Pod │ │ Pod │ │ Pod │       │ API │ │     │                   │  │
│  │   └─────┘ └─────┘ └─────┘       └─────┘ └─────┘                   │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    LAYER 2: Pod Security                           │  │
│  │                                                                    │  │
│  │   securityContext:                                                │  │
│  │     runAsNonRoot: true                                            │  │
│  │     runAsUser: 1000                                               │  │
│  │     readOnlyRootFilesystem: true                                  │  │
│  │     allowPrivilegeEscalation: false                               │  │
│  │     capabilities:                                                 │  │
│  │       drop: ["ALL"]                                               │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    LAYER 3: Network Policy                         │  │
│  │                                                                    │  │
│  │   Agent pods can ONLY reach:                                      │  │
│  │   ✓ api.anthropic.com:443  (Claude API)                          │  │
│  │   ✓ Zig API callback endpoint (for streaming)                    │  │
│  │   ✗ Other pods                                                    │  │
│  │   ✗ Postgres                                                      │  │
│  │   ✗ Internal services                                             │  │
│  │   ✗ Metadata API                                                  │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    LAYER 4: Resource Limits                        │  │
│  │                                                                    │  │
│  │   resources:                                                      │  │
│  │     limits:                                                       │  │
│  │       cpu: "2"                                                    │  │
│  │       memory: "4Gi"                                               │  │
│  │       ephemeral-storage: "10Gi"                                   │  │
│  │                                                                    │  │
│  │   activeDeadlineSeconds: 3600  # 1 hour max                       │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Pod Specification

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: workflow-run-${RUN_ID}
  namespace: workflows
  labels:
    app: workflow-runner
    run-id: "${RUN_ID}"
spec:
  runtimeClassName: gvisor
  restartPolicy: Never
  activeDeadlineSeconds: 3600  # 1 hour max

  serviceAccountName: workflow-runner  # Minimal permissions
  automountServiceAccountToken: false

  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault

  containers:
  - name: runner
    image: gcr.io/plue-prod/runner:${VERSION}

    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]

    env:
    - name: TASK_ID
      value: "${TASK_ID}"
    - name: CALLBACK_URL
      value: "https://api.plue.dev/internal/tasks/${TASK_ID}/stream"
    - name: ANTHROPIC_API_KEY
      valueFrom:
        secretKeyRef:
          name: workflow-secrets
          key: anthropic-api-key

    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "2"
        memory: "4Gi"
        ephemeral-storage: "10Gi"

    volumeMounts:
    - name: workspace
      mountPath: /workspace
    - name: tmp
      mountPath: /tmp

  volumes:
  - name: workspace
    emptyDir:
      sizeLimit: 10Gi
  - name: tmp
    emptyDir:
      sizeLimit: 1Gi
```

#### Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: workflow-runner-isolation
  namespace: workflows
spec:
  podSelector:
    matchLabels:
      app: workflow-runner
  policyTypes:
  - Ingress
  - Egress

  # No ingress allowed (runners only make outbound calls)
  ingress: []

  egress:
  # Allow DNS resolution
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - port: 53
      protocol: UDP

  # Allow Claude API
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - port: 443
      protocol: TCP
```

---

### Real-time Streaming

#### Why WebSocket, Not Electric/SSE

| Factor | Electric SSE | WebSocket |
|--------|--------------|-----------|
| Latency | 100-500ms (sync overhead) | <50ms (direct push) |
| Complexity | High (shape sync, offsets) | Low (direct connection) |
| Infrastructure | Separate service | Built into Zig |
| Already have it | No | Yes (PTY uses WebSocket) |

#### Streaming Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        LIVE SESSION                                      │
│                                                                          │
│   Claude API                                                             │
│       │                                                                  │
│       │ tokens                                                           │
│       ▼                                                                  │
│   ┌─────────────────┐                                                   │
│   │  Runner Pod     │                                                   │
│   │                 │                                                   │
│   │  for token in   │                                                   │
│   │    response:    │                                                   │
│   │    stream(token)│──────┐                                            │
│   │                 │      │                                            │
│   └─────────────────┘      │                                            │
│                            │ HTTP POST (streaming)                       │
│                            ▼                                            │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                      ZIG SERVER                                  │   │
│   │                                                                  │   │
│   │   1. Receive token from runner                                  │   │
│   │   2. Push to client via WebSocket                               │   │
│   │   3. Buffer for batch persist                                   │   │
│   │   4. Every N tokens: persist to Postgres                        │   │
│   │                                                                  │   │
│   └────────────────────────────┬────────────────────────────────────┘   │
│                                │                                        │
│              ┌─────────────────┼─────────────────┐                      │
│              │                 │                 │                      │
│              ▼                 ▼                 ▼                      │
│   ┌──────────────────┐  ┌───────────┐  ┌──────────────────┐            │
│   │   WebSocket      │  │ Postgres  │  │   WebSocket      │            │
│   │   Client A       │  │ (batch)   │  │   Client B       │            │
│   │   (real-time)    │  │           │  │   (optional)     │            │
│   └──────────────────┘  └───────────┘  └──────────────────┘            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                      HISTORICAL SESSION                                  │
│                                                                          │
│   Client                                                                 │
│       │                                                                  │
│       │ GET /api/sessions/:id/messages                                  │
│       ▼                                                                  │
│   ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐   │
│   │      CDN        │────▶│   Zig Server    │────▶│   Postgres      │   │
│   │   (cached)      │     │                 │     │                 │   │
│   └─────────────────┘     └─────────────────┘     └─────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

#### WebSocket Message Protocol

```typescript
// Client → Server
interface ClientMessage {
  type: 'subscribe' | 'unsubscribe' | 'ping';
  session_id?: string;
}

// Server → Client
interface ServerMessage {
  type: 'token' | 'tool_start' | 'tool_end' | 'done' | 'error' | 'pong';
  session_id: string;
  data: TokenData | ToolData | ErrorData;
}

interface TokenData {
  message_id: string;
  part_id: string;
  text: string;           // Incremental token
  token_index: number;    // For ordering
}

interface ToolData {
  message_id: string;
  part_id: string;
  tool_name: string;
  tool_state: 'running' | 'success' | 'error';
  input?: object;
  output?: object;
}
```

---

## Workflow Scheduling

### Queue Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         POSTGRES (Queue)                                 │
│                                                                          │
│  workflow_tasks table:                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ id │ job_id │ status │ runner_id │ created_at │ started_at │... │    │
│  ├────┼────────┼────────┼───────────┼────────────┼─────────────┼────┤    │
│  │ 1  │   10   │ done   │   pod-a   │ 10:00:00   │ 10:00:01    │    │    │
│  │ 2  │   11   │ running│   pod-b   │ 10:00:05   │ 10:00:06    │    │    │
│  │ 3  │   12   │ waiting│   NULL    │ 10:00:10   │ NULL        │    │    │ ← Next
│  │ 4  │   13   │ waiting│   NULL    │ 10:00:15   │ NULL        │    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ Poll every 1s
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          ZIG SERVER                                      │
│                                                                          │
│   Queue Watcher:                                                         │
│   1. SELECT * FROM workflow_tasks WHERE status = 'waiting' LIMIT 10     │
│   2. For each task:                                                      │
│      a. Try claim from warm pool                                        │
│      b. If pool empty, create K8s Job                                   │
│      c. UPDATE status = 'running'                                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│         WARM POOL               │  │         K8s Job                 │
│                                 │  │       (cold start)              │
│  ┌─────┐ ┌─────┐ ┌─────┐       │  │                                 │
│  │Idle │ │Idle │ │Idle │       │  │  Created on-demand              │
│  │ Pod │ │ Pod │ │ Pod │       │  │  3-5 second startup             │
│  └─────┘ └─────┘ └─────┘       │  │                                 │
│                                 │  │                                 │
│  Claim: < 500ms                 │  │  Used when pool exhausted      │
│  Always keep N ready            │  │                                 │
└─────────────────────────────────┘  └─────────────────────────────────┘
```

### Warm Pool Implementation

```yaml
# Standby pool deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: runner-standby-pool
  namespace: workflows
spec:
  replicas: 5  # Keep 5 warm pods
  selector:
    matchLabels:
      app: runner-standby
  template:
    metadata:
      labels:
        app: runner-standby
    spec:
      runtimeClassName: gvisor
      containers:
      - name: runner
        image: gcr.io/plue-prod/runner:latest
        env:
        - name: MODE
          value: "standby"
        - name: REGISTER_URL
          value: "https://api.plue.dev/internal/runners/register"
        command:
        - /runner
        - --standby
        - --register-and-wait
```

```sql
-- Standby runners table
CREATE TABLE standby_runners (
  id SERIAL PRIMARY KEY,
  pod_name VARCHAR(255) UNIQUE NOT NULL,
  pod_ip VARCHAR(45) NOT NULL,
  node_name VARCHAR(255),
  registered_at TIMESTAMP DEFAULT NOW(),
  last_heartbeat TIMESTAMP DEFAULT NOW(),
  claimed_at TIMESTAMP,
  claimed_by_task INTEGER REFERENCES workflow_tasks(id)
);

CREATE INDEX idx_standby_available
  ON standby_runners(claimed_at)
  WHERE claimed_at IS NULL;

-- Claim a runner atomically
WITH claimed AS (
  SELECT id, pod_name, pod_ip
  FROM standby_runners
  WHERE claimed_at IS NULL
  ORDER BY registered_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1
)
UPDATE standby_runners s
SET claimed_at = NOW(),
    claimed_by_task = $1
FROM claimed c
WHERE s.id = c.id
RETURNING s.*;
```

### Latency Comparison

| Scenario | Latency | Notes |
|----------|---------|-------|
| Warm pool hit | <500ms | Claim pod + HTTP assignment |
| Pool empty, cold start | 3-5s | K8s scheduling + container start |
| Pool empty, image not cached | 30s+ | Image pull required |

### Auto-scaling the Pool

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: runner-standby-hpa
  namespace: workflows
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: runner-standby-pool
  minReplicas: 2       # Never go below 2
  maxReplicas: 50      # Scale up to 50 during traffic
  metrics:
  - type: External
    external:
      metric:
        name: available_standby_runners  # Custom metric
      target:
        type: Value
        value: 5  # Try to maintain 5 available
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0  # Scale up immediately
      policies:
      - type: Pods
        value: 10
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 min before scaling down
      policies:
      - type: Pods
        value: 2
        periodSeconds: 60
```

---

## Migration Guide

### Phase 1: Remove Electric SQL

1. **Stop Electric service**
   ```bash
   # docker-compose.yaml
   # Comment out or remove the electric service
   ```

2. **Remove Electric client code**
   ```bash
   rm ui/lib/electric.ts
   # Remove @electric-sql/* from package.json
   ```

3. **Remove shape proxy from Zig**
   ```zig
   // routes.zig - remove shapeProxy handler
   ```

4. **Update UI to use REST**
   - Replace any shape hooks with REST calls + React Query or SWR

### Phase 2: Simplify Git Serving

1. **Remove merkle_roots table**
   ```sql
   DROP TABLE IF EXISTS merkle_roots;
   ```

2. **Update git API endpoints**
   - Add commit SHA to URL path
   - Add proper cache headers

3. **Remove Edge DO git caching**
   ```bash
   rm -rf edge/src/durable-objects/
   ```

### Phase 3: Implement Warm Pool

1. **Create runner image**
   - Standalone runner that can operate in standby or active mode
   - HTTP endpoint to receive assignments

2. **Deploy standby pool**
   - Apply K8s manifests for Deployment + HPA

3. **Implement queue watcher in Zig**
   - Poll workflow_tasks table
   - Claim runners or create Jobs

### Phase 4: WebSocket Streaming

1. **Add streaming endpoint to runner**
   - HTTP POST with chunked transfer encoding
   - Or WebSocket to Zig

2. **Implement WebSocket broadcast in Zig**
   - Track subscribed clients per session
   - Push tokens as they arrive

3. **Update client**
   - WebSocket connection for active sessions
   - REST for historical sessions

---

## Infrastructure

### GKE Cluster Configuration

```yaml
# Terraform or gcloud equivalent
resource "google_container_cluster" "plue" {
  name     = "plue-prod"
  location = "us-central1"

  # Separate node pools for isolation
  remove_default_node_pool = true
  initial_node_count       = 1

  # Enable workload identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# Regular workloads (API, Postgres proxy, etc.)
resource "google_container_node_pool" "default" {
  name       = "default-pool"
  cluster    = google_container_cluster.plue.name
  node_count = 3

  node_config {
    machine_type = "e2-standard-4"
    oauth_scopes = ["cloud-platform"]
  }
}

# Sandboxed workloads (agents, workflows)
resource "google_container_node_pool" "sandbox" {
  name       = "sandbox-pool"
  cluster    = google_container_cluster.plue.name

  autoscaling {
    min_node_count = 1
    max_node_count = 20
  }

  node_config {
    machine_type = "e2-standard-4"
    oauth_scopes = ["cloud-platform"]

    # Enable gVisor
    sandbox_config {
      sandbox_type = "gvisor"
    }

    # Taint so only workflow pods schedule here
    taint {
      key    = "sandbox.gke.io/runtime"
      value  = "gvisor"
      effect = "NO_SCHEDULE"
    }
  }
}
```

### Namespace Structure

```yaml
# Namespaces
apiVersion: v1
kind: Namespace
metadata:
  name: plue-system  # Zig API, monitoring
  labels:
    pod-security.kubernetes.io/enforce: baseline
---
apiVersion: v1
kind: Namespace
metadata:
  name: workflows  # Sandboxed runners
  labels:
    pod-security.kubernetes.io/enforce: restricted
```

### Secrets Management

```yaml
# Use GCP Secret Manager + External Secrets Operator
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: workflow-secrets
  namespace: workflows
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: gcp-secret-store
  target:
    name: workflow-secrets
  data:
  - secretKey: anthropic-api-key
    remoteRef:
      key: anthropic-api-key
```

---

## Summary

### What We Removed

| Component | Why Removed |
|-----------|-------------|
| ElectricSQL | Not providing value; UI queried Postgres directly anyway |
| Edge DO SQLite | Over-engineered; CDN caching is simpler |
| merkle_roots table | Git SHAs are already content-addressed |
| Shape proxy | Was broken; not needed without Electric |

### What We Added/Changed

| Component | Change |
|-----------|--------|
| Git API | Use commit SHA in URL, cache forever |
| WebSocket streaming | Direct push for agent tokens |
| Warm pool | Standby pods for <500ms chat latency |
| Unified workflows | Agents and CI share same sandbox infrastructure |

### Key Benefits

1. **Simpler** — fewer moving parts, easier to debug
2. **Faster** — WebSocket is lower latency than sync
3. **Cheaper** — no idle Electric service, scale-to-zero runners
4. **More secure** — gVisor sandboxing for all code execution
5. **More powerful** — unified model for CI and agents
