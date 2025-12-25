# HTTP Routes

API route handlers for the Zig HTTP server. Implements REST endpoints for repositories, issues, workflows, agents, and authentication.

## Key Files

| File | Purpose |
|------|---------|
| `auth.zig` | Authentication endpoints (SIWE, sessions, tokens) |
| `repositories.zig` | Repository CRUD and Git tree/blob operations |
| `issues.zig` | Issue tracking and management |
| `milestones.zig` | Milestone management |
| `changes.zig` | Git change tracking and display |
| `git.zig` | Git protocol operations (tree, blob, refs) |
| `workflows.zig` | Workflow execution and monitoring |
| `workflows_v2.zig` | New workflow system with plan-based execution |
| `agent.zig` | Agent session management |
| `sessions.zig` | Session lifecycle management |
| `users.zig` | User profile and settings |
| `ssh_keys.zig` | SSH key management for Git operations |
| `tokens.zig` | API token generation and revocation |
| `messages.zig` | Agent message history |
| `watcher.zig` | Repository watching/starring |
| `landing_queue.zig` | PR merge queue management |
| `operations.zig` | Repository operations (fork, archive) |
| `runner_pool.zig` | Warm runner pool status |
| `runners.zig` | Runner registration and health |
| `internal.zig` | Internal-only endpoints (runner callbacks) |
| `prompts.zig` | Workflow prompt definitions |

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         HTTP Routes                              │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────┐ │
│  │   Repository   │  │     Issue      │  │     Workflow       │ │
│  │                │  │                │  │                    │ │
│  │ GET  /repos    │  │ GET  /issues   │  │ GET  /workflows    │ │
│  │ POST /repos    │  │ POST /issues   │  │ POST /workflows    │ │
│  │ GET  /tree     │  │ PUT  /issues   │  │ GET  /runs         │ │
│  │ GET  /blob     │  │ POST /comments │  │ POST /runs/cancel  │ │
│  └────────────────┘  └────────────────┘  └────────────────────┘ │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────┐ │
│  │      Auth      │  │      Git       │  │      Agent         │ │
│  │                │  │                │  │                    │ │
│  │ POST /siwe     │  │ GET  /refs     │  │ POST /agent/run    │ │
│  │ POST /login    │  │ GET  /commits  │  │ GET  /agent/msg    │ │
│  │ POST /logout   │  │ POST /push     │  │ SSE  /agent/stream │ │
│  │ GET  /me       │  │ GET  /changes  │  │                    │ │
│  └────────────────┘  └────────────────┘  └────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Middleware Chain                        │ │
│  │                                                            │ │
│  │  Request → CORS → Auth → CSRF → Rate Limit → Route → DB  │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

## Route Categories

| Category | Prefix | Description |
|----------|--------|-------------|
| Auth | `/api/auth/*` | SIWE, sessions, tokens |
| Repos | `/api/repos/*` | Repository management |
| Issues | `/api/issues/*` | Issue tracking |
| Git | `/api/git/*` | Git protocol operations |
| Workflows | `/api/workflows/*` | Workflow execution |
| Agent | `/api/agent/*` | Agent sessions |
| Internal | `/internal/*` | Runner callbacks (auth required) |

## Request Flow

```
Client Request
      │
      ▼
┌──────────────┐
│    CORS      │  Set headers, handle preflight
└──────┬───────┘
       │
       ▼
┌──────────────┐
│     Auth     │  Validate session/token
└──────┬───────┘
       │
       ▼
┌──────────────┐
│     CSRF     │  Verify CSRF token (mutating requests)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Rate Limit  │  Check rate limits
└──────┬───────┘
       │
       ▼
┌──────────────┐
│    Route     │  Execute handler
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   Database   │  Query/update data
└──────┬───────┘
       │
       ▼
   Response
```
