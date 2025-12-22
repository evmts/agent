# Plue Migration Plan

This document provides a step-by-step migration plan from the current architecture to the simplified architecture described in `architecture.md` and `infrastructure.md`.

## Table of Contents

1. [Current State Summary](#current-state-summary)
2. [Target State Summary](#target-state-summary)
3. [Migration Phases](#migration-phases)
   - [Phase 1: Remove ElectricSQL](#phase-1-remove-electricsql)
   - [Phase 2: Simplify Edge Layer](#phase-2-simplify-edge-layer)
   - [Phase 3: Simplify Git File Serving](#phase-3-simplify-git-file-serving)
   - [Phase 4: WebSocket Streaming](#phase-4-websocket-streaming)
   - [Phase 5: Sandboxed Runner Infrastructure](#phase-5-sandboxed-runner-infrastructure)
   - [Phase 6: Unified Workflow/Agent System](#phase-6-unified-workflowagent-system)
   - [Phase 7: Infrastructure & CI/CD](#phase-7-infrastructure--cicd)
4. [Risk Assessment](#risk-assessment)
5. [Rollback Procedures](#rollback-procedures)

---

## Current State Summary

### What Exists Today

| Component | Status | Location | Notes |
|-----------|--------|----------|-------|
| **ElectricSQL** | Partial | `docker-compose.yaml`, `edge/` | Docker service runs; Edge DO uses it; UI stubs throw errors |
| **Edge Worker (DO)** | Complete | `edge/src/` | DataSyncDO with SQLite, Electric sync, merkle validation |
| **Git Caching (Edge)** | Unused | `edge/src/durable-objects/data-sync.ts` | Code exists but page handlers never call it |
| **Agent System** | In-process | `server/src/ai/` | Direct execution in Zig, 10 tools, SSE streaming |
| **Workflow System** | Scaffolded | `db/schema.sql` | 11 tables exist but not connected to agents |
| **Database** | Complete | `db/schema.sql` | 49 tables covering auth, repos, issues, sessions, workflows |
| **Terraform** | Partial | `terraform/` | Production modules exist; no staging environments |
| **CI/CD** | Missing | — | No GitHub workflows |
| **Helm Charts** | Missing | — | Infrastructure.md describes but doesn't exist |

### Current Architecture Diagram

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
│  │   - SQLite cache          │  │    │  - /shape proxy (BROKEN)        │
│  │   - Electric sync         │  │    │  - Auth (SIWE, JWT)             │
│  │   - Merkle validation     │  │    │  - Git operations (jj-lib)      │
│  │   - Git cache (UNUSED)    │  │    │  - SSE streaming                │
│  └───────────────────────────┘  │    │  - Agent execution (IN-PROCESS) │
└─────────────────────────────────┘    └─────────────────────────────────┘
                    │                                    │
                    │ HTTP (shapes)                      │ SQL
                    ▼                                    ▼
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│         ElectricSQL             │    │          PostgreSQL             │
│  - Shape definitions            │◄───│  - 49 tables                    │
│  - Logical replication          │    │  - Sessions, messages, parts    │
│  - Used by Edge DO only         │    │  - Workflows (unused)           │
└─────────────────────────────────┘    └─────────────────────────────────┘
```

### Key Problems with Current State

1. **ElectricSQL adds complexity without value**
   - UI stubs throw errors (never integrated)
   - Shape proxy in Zig doesn't forward headers correctly
   - Only Edge DO uses it, and that's being removed

2. **Edge Durable Objects are over-engineered**
   - Merkle-validated git caching exists but is never called
   - Push invalidation system works but not needed without Electric
   - CDN can handle caching more simply

3. **Agent execution is unsafe**
   - Runs in-process with full server privileges
   - No resource isolation (CPU, memory, network)
   - Can't handle untrusted code execution

4. **Streaming uses SSE (not WebSocket)**
   - Server-sent events for token streaming
   - Separate POST endpoint for abort functionality
   - Real-time persistence of streaming state

5. **Workflows and Agents are separate systems**
   - Workflow tables exist but aren't connected to agent execution
   - Duplicate infrastructure for similar use cases

---

## Target State Summary

### Target Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CLIENTS                                     │
│   Browser ◄────────────────────────────────────────────► Browser        │
│      │                                                       │          │
│      │ WebSocket (streaming)              REST + Cache       │          │
└──────┼───────────────────────────────────────────────────────┼──────────┘
       │                                                       │
       │                    ┌─────────────────┐                │
       │                    │   Cloudflare    │◄───────────────┘
       │                    │   CDN           │
       │                    │  - Static assets│
       │                    │  - Git blobs    │
       │                    └────────┬────────┘
       │                             │ Cache miss
       ▼                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           ZIG SERVER                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  REST API   │  │     SSE     │  │  Auth       │  │  K8s Client │    │
│  │  - CRUD     │  │  Streaming  │  │  - SIWE/JWT │  │  - Job mgmt │    │
│  │  - Git tree │  │  - Agent    │  │  - Sessions │  │  - Warm pool│    │
│  │  - Abort    │  │  - Sessions │  │             │  │             │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
│                              │                              │           │
│                              ▼                              ▼           │
│                         jj-lib (FFI)                  Kubernetes        │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    ▼                             ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│         PostgreSQL              │  │      Kubernetes (GKE)           │
│  - All application state        │  │  ┌─────────────────────────┐   │
│  - Sessions, messages, parts    │  │  │   Workflow/Agent Pods   │   │
│  - Workflow queue               │  │  │   (gVisor sandbox)      │   │
└─────────────────────────────────┘  └─────────────────────────────────┘
```

### What Changes

| Removed | Added/Changed |
|---------|---------------|
| ElectricSQL service | Direct Postgres queries |
| Edge Durable Objects | CDN caching with proper headers |
| In-process agent execution | K8s sandboxed pods (gVisor) |
| N/A | SSE streaming (was already in place) |
| Separate workflow/agent systems | Unified execution model |
| Shape proxy | SHA-based git caching |
| Terminal/PTY feature | Removed entirely |

---

## Migration Phases

### Phase 1: Remove ElectricSQL

**Goal**: Remove ElectricSQL service and all related code without breaking functionality.

**Duration**: Low complexity, can be done in one session.

**Prerequisites**: None

#### Tasks

1. **Stop Electric service**
   ```bash
   # In docker-compose.yaml, comment out or remove:
   # - electric service (lines 27-43)
   # - ELECTRIC_URL env vars
   ```

2. **Remove UI Electric stubs**
   ```bash
   rm ui/lib/electric.ts
   ```
   - File is 403 lines of stubs that throw errors
   - No components import it

3. **Remove Zig shape proxy**
   - File: `server/src/routes.zig`
   - Remove `/shape` route handler (lines 376-454)
   - Remove `shapeProxy` function
   - Remove `electric_url` from `server/src/config.zig` (line 49)

4. **Update package.json**
   - Remove `@electric-sql/*` from `edge/package.json`
   - Run `bun install` to clean lock file

5. **Update docker-compose.yaml**
   - Remove `electric` service definition
   - Remove `ELECTRIC_URL` environment variables from all services
   - Remove Electric-related healthchecks

#### Verification

```bash
# Start services without Electric
docker-compose up -d postgres
zig build run

# Verify API still works
curl http://localhost:4000/api/health

# Run tests
zig build test
```

---

### Phase 2: Simplify Edge Layer

**Goal**: Remove Durable Objects complexity, convert edge to simple CDN proxy.

**Duration**: Medium complexity.

**Prerequisites**: Phase 1 complete

#### Current Edge Structure

```
edge/
├── src/
│   ├── index.ts                    # Main router
│   ├── durable-objects/
│   │   └── data-sync.ts            # 954 lines - REMOVE
│   └── pages/                      # 8 page handlers
│       ├── home.ts
│       ├── issues-list.ts
│       ├── issue-detail.ts
│       └── ...
├── wrangler.toml
└── package.json
```

#### Tasks

1. **Remove Durable Objects**
   ```bash
   rm -rf edge/src/durable-objects/
   ```

2. **Simplify index.ts**
   - Remove DO binding and instantiation
   - Convert page handlers to simple origin proxies
   - Keep static asset routing

3. **Update wrangler.toml**
   - Remove `[durable_objects]` section
   - Remove `[[migrations]]` sections
   - Simplify to basic Worker configuration

4. **Simplify page handlers**
   - Remove DO queries
   - Proxy all dynamic content to origin
   - Keep only static HTML shell rendering if needed

5. **Update Edge tests**
   - Remove DO-related tests
   - Add simple proxy tests

#### New Edge Architecture

```typescript
// edge/src/index.ts (simplified)
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Static assets - let CDN handle
    if (url.pathname.startsWith('/_astro/')) {
      return fetch(request);
    }

    // All other requests - proxy to origin with caching headers
    const response = await fetch(new URL(url.pathname, env.ORIGIN_URL), {
      method: request.method,
      headers: request.headers,
      body: request.body,
    });

    return response;
  }
};
```

#### Verification

```bash
# Deploy simplified worker
cd edge && bun run deploy:staging

# Test edge routing
curl https://staging.plue.dev/api/health
curl https://staging.plue.dev/torvalds/linux
```

---

### Phase 3: Simplify Git File Serving

**Goal**: Implement SHA-based caching with proper HTTP cache headers.

**Duration**: Medium complexity.

**Prerequisites**: Phase 2 complete

#### Current Git Serving

- Routes in `server/src/routes/changes.zig`
- Uses jj-lib FFI for file content
- No caching headers
- Edge has unused merkle root validation

#### New API Design

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

#### Tasks

1. **Add new routes to Zig server**
   - Create `server/src/routes/git.zig`
   - Add `/api/:owner/:repo/refs/:ref` endpoint
   - Add `/api/:owner/:repo/tree/:sha/:path` endpoint
   - Add `/api/:owner/:repo/blob/:sha/:path` endpoint

2. **Implement proper cache headers**
   ```zig
   // For immutable content (by SHA)
   res.headers.add("Cache-Control", "public, max-age=31536000, immutable");
   res.headers.add("ETag", sha);

   // For ref resolution
   res.headers.add("Cache-Control", "public, max-age=5");
   ```

3. **Extend jj-lib FFI**
   - Add `jj_resolve_ref()` to get commit SHA from ref name
   - Add `jj_get_tree_by_sha()` for tree listing
   - Add `jj_get_blob_by_sha()` for blob content

4. **Update UI to use new endpoints**
   - Modify file browser to resolve ref first
   - Then fetch tree/blob by SHA
   - Client-side caching will "just work"

5. **Remove old change-based routes** (optional, can deprecate)
   - Keep `/api/:owner/:repo/changes/:id/files` for now
   - Mark as deprecated in docs

#### Database Changes

No new tables needed. Git SHAs are the cache keys (content-addressable).

#### Verification

```bash
# Test ref resolution
curl -v http://localhost:4000/api/torvalds/linux/refs/main
# Should return commit SHA with 5s cache

# Test tree fetch
curl -v http://localhost:4000/api/torvalds/linux/tree/abc123/src
# Should return tree with immutable cache

# Test blob fetch
curl -v http://localhost:4000/api/torvalds/linux/blob/abc123/README.md
# Should return content with immutable cache

# Verify caching works
curl -H "If-None-Match: abc123" http://localhost:4000/api/torvalds/linux/blob/abc123/README.md
# Should return 304 Not Modified
```

---

### Phase 4: SSE Streaming Improvements

**Goal**: Enhance SSE streaming with abort functionality.

**Duration**: Low complexity (already implemented).

**Prerequisites**: None (can be done in parallel with Phases 1-3)

#### Current Streaming

```zig
// server/src/routes/agent.zig
res.content_type = .EVENTS;  // SSE
// Streaming via Server-Sent Events
```

#### Tasks

1. **Add abort endpoint**
   - Implement `POST /api/sessions/:id/abort`
   - Handle graceful cancellation of running agents
   - Update session status

2. **Improve SSE message protocol**
   ```typescript
   // Server → Client (SSE events)
   interface ServerEvent {
     event: 'token' | 'tool_start' | 'tool_end' | 'done' | 'error';
     data: TokenData | ToolData | ErrorData;
   }
   ```

3. **Add client-side abort handling**
   - Update `ui/lib/agent-client.ts` to support abort
   - Close EventSource on abort
   - Show cancellation UI feedback

#### Verification

```bash
# Test SSE connection
curl -N http://localhost:4000/api/sessions/test123/stream

# Test abort in another terminal
curl -X POST http://localhost:4000/api/sessions/test123/abort

# Verify stream closes gracefully
```

---

### Phase 5: Sandboxed Runner Infrastructure

**Goal**: Create K8s-based sandboxed execution environment for agents/workflows.

**Duration**: High complexity.

**Prerequisites**: Phase 4 complete (SSE streaming enhancements)

#### Current Execution

```
User → Zig API → runAgent() → Tools execute in-process
```

#### Target Execution

```
User → Zig API → K8s Job → gVisor Pod → runAgent() → Sandboxed tools
              ↑ stream results back via HTTP/WebSocket
```

#### Tasks

##### 5.1 Create Runner Container Image

1. **Create runner directory**
   ```bash
   mkdir -p runner/src
   ```

2. **Implement runner in Python/TypeScript**
   ```python
   # runner/src/main.py
   class Runner:
       def __init__(self, task_id: str, callback_url: str):
           self.task_id = task_id
           self.callback_url = callback_url
           self.anthropic = Anthropic()

       def run_agent(self, config: AgentConfig):
           """Execute agent loop and stream results back."""
           while not done and turns < config.max_turns:
               response = self.anthropic.messages.create(...)
               for block in response.content:
                   self.stream_to_zig(block)
                   if block.type == "tool_use":
                       result = self.execute_tool(block)
                       self.stream_to_zig(result)

       def stream_to_zig(self, event):
           """POST streaming events back to Zig server."""
           requests.post(
               f"{self.callback_url}/stream",
               json=event.to_dict(),
               headers={"Authorization": f"Bearer {self.task_token}"}
           )
   ```

3. **Create Dockerfile**
   ```dockerfile
   # runner/Dockerfile
   FROM python:3.12-slim

   WORKDIR /app
   COPY requirements.txt .
   RUN pip install -r requirements.txt

   COPY src/ ./src/

   USER 1000:1000
   ENTRYPOINT ["python", "-m", "src.main"]
   ```

4. **Implement tool execution**
   - Port tools from `server/src/ai/tools/` to Python
   - Add sandboxing wrappers (subprocess limits, network filtering)
   - Implement stdout/stderr streaming

##### 5.2 Add K8s Client to Zig Server

1. **Create K8s client module**
   - `server/src/k8s/client.zig`
   - Implement Job creation API
   - Implement Pod log streaming
   - Handle warm pool claiming

2. **Add internal streaming endpoint**
   ```zig
   // POST /internal/tasks/:id/stream
   // Called by runner pods to push events
   fn handleTaskStream(req, res) {
       // Validate task token
       // Push to WebSocket subscribers
       // Buffer for persistence
   }
   ```

3. **Implement warm pool management**
   ```sql
   -- Add to schema.sql
   CREATE TABLE runner_pool (
     id SERIAL PRIMARY KEY,
     pod_name VARCHAR(255) UNIQUE NOT NULL,
     pod_ip VARCHAR(45) NOT NULL,
     status VARCHAR(20) DEFAULT 'available', -- available, claimed, terminated
     claimed_at TIMESTAMP,
     claimed_by_task_id VARCHAR(64),
     registered_at TIMESTAMP DEFAULT NOW(),
     last_heartbeat TIMESTAMP DEFAULT NOW()
   );
   ```

##### 5.3 Create K8s Manifests

1. **Pod template for runners**
   ```yaml
   # runner/k8s/pod-template.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: runner-${TASK_ID}
     namespace: workflows
   spec:
     runtimeClassName: gvisor
     restartPolicy: Never
     activeDeadlineSeconds: 3600

     securityContext:
       runAsNonRoot: true
       runAsUser: 1000

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
       resources:
         limits:
           cpu: "2"
           memory: "4Gi"
           ephemeral-storage: "10Gi"
   ```

2. **Network policy**
   ```yaml
   # runner/k8s/network-policy.yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: runner-isolation
     namespace: workflows
   spec:
     podSelector:
       matchLabels:
         app: runner
     policyTypes:
     - Ingress
     - Egress

     ingress: []  # No ingress

     egress:
     - to:
       - namespaceSelector: {}
         podSelector:
           matchLabels:
             k8s-app: kube-dns
       ports:
       - port: 53
         protocol: UDP
     - to:
       - ipBlock:
           cidr: 0.0.0.0/0
       ports:
       - port: 443
         protocol: TCP
   ```

3. **Warm pool deployment**
   ```yaml
   # runner/k8s/warm-pool.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: runner-standby-pool
     namespace: workflows
   spec:
     replicas: 5
     selector:
       matchLabels:
         app: runner-standby
     template:
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
   ```

##### 5.4 Update Terraform

1. **Add sandbox node pool to GKE module**
   ```hcl
   # terraform/modules/gke/sandbox-pool.tf
   resource "google_container_node_pool" "sandbox" {
     name    = "sandbox-pool"
     cluster = google_container_cluster.cluster.name

     autoscaling {
       min_node_count = 1
       max_node_count = 20
     }

     node_config {
       machine_type = "e2-standard-4"

       sandbox_config {
         sandbox_type = "gvisor"
       }

       taint {
         key    = "sandbox.gke.io/runtime"
         value  = "gvisor"
         effect = "NO_SCHEDULE"
       }
     }
   }
   ```

2. **Add workflows namespace**
   ```hcl
   # terraform/kubernetes/workflows.tf
   resource "kubernetes_namespace" "workflows" {
     metadata {
       name = "workflows"
       labels = {
         "pod-security.kubernetes.io/enforce" = "restricted"
       }
     }
   }
   ```

#### Verification

```bash
# Build and push runner image
docker build -t gcr.io/plue-staging/runner:test runner/
docker push gcr.io/plue-staging/runner:test

# Apply K8s manifests
kubectl apply -f runner/k8s/

# Verify warm pool
kubectl get pods -n workflows -l app=runner-standby

# Test agent execution through K8s
curl -X POST http://localhost:4000/api/sessions/test/run \
  -H "Content-Type: application/json" \
  -d '{"message":"List files in current directory"}'

# Check pod was created
kubectl get pods -n workflows -l task-id=<task-id>
```

---

### Phase 6: Unified Workflow/Agent System

**Goal**: Merge workflow and agent systems into single execution model.

**Duration**: High complexity.

**Prerequisites**: Phase 5 complete

#### Current State

- **Agents**: Sessions/messages/parts tables, in-process execution
- **Workflows**: 11 tables (definitions, runs, jobs, tasks, steps, logs), unused

#### Tasks

##### 6.1 Unify Event Model

1. **Update workflow_runs table**
   ```sql
   ALTER TABLE workflow_runs
   ADD COLUMN session_id VARCHAR(64) REFERENCES sessions(id),
   ADD COLUMN mode VARCHAR(20) DEFAULT 'scripted'; -- 'scripted' or 'agent'
   ```

2. **Update workflow trigger types**
   ```sql
   -- workflow_runs.trigger_event can now be:
   -- 'push', 'pull_request', 'issue', 'manual', 'chat', 'mention'
   ```

##### 6.2 Create Unified Workload Abstraction

1. **Add workload table**
   ```sql
   CREATE TABLE workloads (
     id VARCHAR(64) PRIMARY KEY,
     type VARCHAR(20) NOT NULL, -- 'agent' or 'workflow'

     -- For agents
     session_id VARCHAR(64) REFERENCES sessions(id),
     model VARCHAR(255),
     system_prompt TEXT,
     max_turns INTEGER DEFAULT 20,

     -- For workflows
     workflow_run_id INTEGER REFERENCES workflow_runs(id),

     -- Common
     trigger_event VARCHAR(50),
     trigger_context JSONB,
     status VARCHAR(20) DEFAULT 'pending',
     pod_name VARCHAR(255),
     started_at TIMESTAMP,
     ended_at TIMESTAMP,
     exit_code INTEGER,

     created_at TIMESTAMP DEFAULT NOW()
   );
   ```

2. **Update runner to handle both modes**
   ```python
   # runner/src/main.py
   def run_workload(self, workload: Workload):
       if workload.type == "agent":
           self.run_agent(workload.agent_config)
       elif workload.type == "workflow":
           self.run_workflow(workload.workflow_steps)

   def run_workflow(self, steps: list[WorkflowStep]):
       for step in steps:
           result = self.execute_step(step)
           self.stream_to_zig(StepResult(step=step, result=result))
   ```

##### 6.3 Implement Workflow Parser

1. **Parse .plue/workflows/*.yaml**
   ```python
   # runner/src/workflow_parser.py
   def parse_workflow(path: str) -> Workflow:
       with open(path) as f:
           config = yaml.safe_load(f)

       return Workflow(
           name=config['name'],
           on=config['on'],
           mode=config.get('mode', 'scripted'),
           jobs=[parse_job(j) for j in config.get('jobs', {}).values()],
           agent=parse_agent_config(config.get('agent')),
       )
   ```

2. **Handle both scripted and agent modes**
   ```yaml
   # Scripted mode (traditional CI)
   name: CI
   on: [push, pull_request]
   mode: scripted
   jobs:
     test:
       steps:
         - run: bun install
         - run: bun test

   # Agent mode (AI-powered)
   name: Code Review
   on: [pull_request]
   mode: agent
   agent:
     model: claude-sonnet-4-20250514
     system: "You are a code reviewer..."
     tools: [read_file, pr_diff, pr_comment]
     max_turns: 20
   ```

##### 6.4 Implement Event Triggers

1. **Create event processor in Zig**
   ```zig
   // server/src/workflows/trigger.zig
   pub fn processEvent(event: Event) !void {
       // Find matching workflow definitions
       const workflows = try db.getWorkflowsForEvent(event.repo_id, event.type);

       for (workflows) |workflow| {
           // Create workload
           const workload = try createWorkload(workflow, event);

           // Submit to K8s
           try k8s.submitWorkload(workload);
       }
   }
   ```

2. **Add webhook handlers**
   - `POST /api/webhooks/push` - Git push events
   - `POST /api/webhooks/pr` - Pull request events
   - `POST /api/webhooks/issue` - Issue events
   - Trigger from jj-lib hooks or git post-receive

#### Verification

```bash
# Create test workflow
cat > test-repo/.plue/workflows/ci.yaml << EOF
name: CI
on: [push]
mode: scripted
jobs:
  test:
    steps:
      - run: echo "Hello from CI"
EOF

# Push and verify workflow runs
git push origin main

# Check workflow run
curl http://localhost:4000/api/repos/test/test-repo/runs
```

---

### Phase 7: Infrastructure & CI/CD

**Goal**: Implement per-engineer staging and automated deployment.

**Duration**: Medium complexity.

**Prerequisites**: Phases 1-6 substantially complete

#### Tasks

##### 7.1 Create Helm Charts

1. **Create chart structure**
   ```bash
   mkdir -p helm/plue/templates
   ```

2. **Create Chart.yaml**
   ```yaml
   # helm/plue/Chart.yaml
   apiVersion: v2
   name: plue
   version: 0.1.0
   appVersion: "1.0.0"
   ```

3. **Create values files**
   ```yaml
   # helm/plue/values-staging.yaml
   replicaCount: 1
   runner:
     warmPool:
       replicas: 2
   ingress:
     host: "${NAMESPACE}.staging.plue.dev"
   ```

4. **Create templates**
   - `templates/deployment.yaml`
   - `templates/service.yaml`
   - `templates/ingress.yaml`
   - `templates/runner-deployment.yaml`
   - `templates/network-policy.yaml`

##### 7.2 Create Staging Terraform Modules

1. **Create staging-namespace module**
   ```hcl
   # terraform/modules/staging-namespace/main.tf
   variable "engineer_name" {
     type = string
   }

   resource "google_sql_database" "database" {
     name     = "plue_${var.engineer_name}"
     instance = var.sql_instance_name
   }

   resource "kubernetes_namespace" "namespace" {
     metadata {
       name = var.engineer_name
     }
   }

   resource "helm_release" "plue" {
     name      = "plue"
     namespace = kubernetes_namespace.namespace.metadata[0].name
     chart     = "${path.module}/../../../helm/plue"

     set {
       name  = "ingress.host"
       value = "${var.engineer_name}.staging.plue.dev"
     }
   }
   ```

2. **Create staging-base environment**
   ```hcl
   # terraform/environments/staging-base/main.tf
   module "gke" {
     source = "../../modules/gke"
     # Shared staging cluster
   }

   module "cloud_sql" {
     source = "../../modules/cloudsql"
     # Shared database instance
   }
   ```

##### 7.3 Create GitHub Workflows

1. **Create deploy workflow**
   ```yaml
   # .github/workflows/deploy.yaml
   name: Deploy

   on:
     push:
       branches:
         - main
         - 'staging/*'

   jobs:
     test:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - run: zig build test

     build:
       needs: test
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - run: docker build -t gcr.io/plue-staging/zig-api:${{ github.sha }} server/
         - run: docker push gcr.io/plue-staging/zig-api:${{ github.sha }}

     deploy-staging:
       needs: build
       if: startsWith(github.ref, 'refs/heads/staging/')
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - run: |
             NAMESPACE=${GITHUB_REF#refs/heads/staging/}
             helm upgrade --install plue ./helm/plue \
               --namespace $NAMESPACE \
               --set image.tag=${{ github.sha }}

     deploy-production:
       needs: build
       if: github.ref == 'refs/heads/main'
       runs-on: ubuntu-latest
       environment: production
       steps:
         - uses: actions/checkout@v4
         - run: |
             helm upgrade --install plue ./helm/plue \
               --namespace production \
               --set image.tag=${{ github.sha }}
   ```

2. **Create deployment scripts**
   ```bash
   # scripts/deploy-staging.sh
   #!/bin/bash
   NAMESPACE="${STAGING_NAMESPACE:-$USER}"
   helm upgrade --install plue ./helm/plue \
     --namespace $NAMESPACE \
     --set ingress.host="${NAMESPACE}.staging.plue.dev"
   ```

##### 7.4 Update Makefile

```makefile
# Makefile (new file or update existing)

.PHONY: dev dev-db deploy-staging

dev: dev-db
	@trap 'kill 0' SIGINT; \
		zig build run & \
		(cd ui && bun dev) & \
		wait

dev-db:
	docker-compose up -d postgres

deploy-staging:
	./scripts/deploy-staging.sh

logs-staging:
	kubectl logs -f -l app=zig-api -n $(USER)
```

#### Verification

```bash
# Initialize your staging environment
./scripts/init-my-staging.sh

# Deploy to staging
make deploy-staging

# Check your staging
curl https://$USER.staging.plue.dev/api/health
```

---

## Risk Assessment

### High Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| Agent migration breaks existing sessions | Users lose chat history | Keep in-process execution available via feature flag; migrate data in phases |
| gVisor performance overhead | Slower agent execution | Benchmark before/after; consider containerd as fallback |
| WebSocket reliability | Lost messages during reconnection | Implement message buffering; persist before acknowledging |

### Medium Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| Warm pool exhaustion | Cold starts for agents (3-5s) | Monitor pool usage; auto-scale aggressively |
| Network policy too restrictive | Agents can't reach required endpoints | Test thoroughly in staging; add metrics for blocked requests |
| Database schema changes | Downtime during migration | Use zero-downtime migrations; add columns as nullable first |

### Low Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| ElectricSQL removal | None (not used) | Test that UI still works without it |
| Edge simplification | Slightly slower first request | CDN will cache; measure latency impact |

---

## Rollback Procedures

### Phase 1 Rollback (ElectricSQL)

```bash
# Re-enable Electric in docker-compose
git checkout HEAD -- docker-compose.yaml

# Restart services
docker-compose up -d
```

### Phase 4-5 Rollback (SSE + K8s)

```bash
# Re-enable in-process execution
export RUNNER_MODE=in-process

# Restart Zig server
zig build run
```

Feature flag in config:
```zig
// server/src/config.zig
pub const runner_mode: enum { in_process, kubernetes } =
    if (std.os.getenv("RUNNER_MODE")) |m|
        if (std.mem.eql(u8, m, "kubernetes")) .kubernetes else .in_process
    else
        .in_process;
```

### Full Rollback

```bash
# Restore from backup branch
git checkout pre-migration-backup

# Restore database
pg_restore --clean --if-exists plue_backup.dump

# Restart all services
docker-compose down
docker-compose up -d
```

---

## Migration Checklist

### Pre-Migration

- [ ] Create database backup
- [ ] Tag current state: `git tag pre-migration`
- [ ] Document current metrics baselines
- [ ] Notify users of maintenance window

### Phase 1: Remove ElectricSQL

- [ ] Remove Electric Docker service
- [ ] Remove `ui/lib/electric.ts`
- [ ] Remove `/shape` proxy route
- [ ] Update environment variables
- [ ] Run full test suite
- [ ] Deploy to staging
- [ ] Verify in staging for 24h

### Phase 2: Simplify Edge

- [ ] Remove Durable Objects
- [ ] Simplify edge router
- [ ] Update wrangler.toml
- [ ] Deploy edge worker
- [ ] Verify CDN caching works

### Phase 3: Git File Serving

- [ ] Add new git routes
- [ ] Implement cache headers
- [ ] Extend jj-lib FFI
- [ ] Update UI file browser
- [ ] Verify caching with curl

### Phase 4: SSE Streaming Enhancements

- [x] SSE streaming already implemented
- [ ] Add abort endpoint (POST /api/sessions/:id/abort)
- [ ] Enhance client-side abort handling
- [ ] Test abort functionality

### Phase 5: Sandboxed Runners

- [ ] Create runner container
- [ ] Port tools to Python
- [ ] Add K8s client to Zig
- [ ] Create pod templates
- [ ] Implement network policies
- [ ] Add warm pool
- [ ] Update Terraform
- [ ] Deploy to staging
- [ ] Benchmark performance

### Phase 6: Unified Workflows

- [ ] Update database schema
- [ ] Create workload abstraction
- [ ] Implement workflow parser
- [ ] Add event triggers
- [ ] Test CI workflows
- [ ] Test agent workflows

### Phase 7: Infrastructure

- [ ] Create Helm charts
- [ ] Create staging modules
- [ ] Create GitHub workflows
- [ ] Test per-engineer staging
- [ ] Deploy to production

### Post-Migration

- [ ] Monitor error rates
- [ ] Compare latency metrics
- [ ] Gather user feedback
- [ ] Remove deprecated code
- [ ] Update documentation
- [ ] Celebrate!

---

## Appendix: File Changes Summary

### Files to Remove

```
ui/lib/electric.ts
edge/src/durable-objects/data-sync.ts
edge/src/durable-objects/data-sync.test.ts
```

### Files to Create

```
runner/
├── Dockerfile
├── requirements.txt
├── src/
│   ├── main.py
│   ├── agent.py
│   ├── workflow.py
│   ├── tools/
│   │   ├── grep.py
│   │   ├── read_file.py
│   │   ├── write_file.py
│   │   └── ...
│   └── streaming.py
└── k8s/
    ├── pod-template.yaml
    ├── network-policy.yaml
    └── warm-pool.yaml

server/src/routes/git.zig
server/src/websocket/agent_stream.zig
server/src/k8s/client.zig
server/src/workflows/trigger.zig

helm/plue/
├── Chart.yaml
├── values.yaml
├── values-staging.yaml
├── values-production.yaml
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    └── ...

terraform/environments/staging-base/
terraform/modules/staging-namespace/

.github/workflows/deploy.yaml
scripts/deploy-staging.sh
scripts/init-my-staging.sh
```

### Files to Modify

```
docker-compose.yaml          # Remove Electric
server/src/routes.zig        # Remove /shape, add new routes
server/src/config.zig        # Remove electric_url, add runner_mode
edge/src/index.ts            # Simplify to proxy
edge/wrangler.toml           # Remove DO config
db/schema.sql                # Add workloads, runner_pool tables
```
