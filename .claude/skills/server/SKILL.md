---
name: server
description: Plue Zig API server internals. Use when working on HTTP routes, middleware, WebSocket handlers, SSH server, or understanding the server architecture.
---

# Plue Server (Zig API)

The main backend server built with Zig and httpz. Handles HTTP API, WebSocket streaming, SSH git operations, and agent execution.

## Entry Point

- Main: `server/src/main.zig`
- Routes: `server/src/routes.zig`

## Key Modules

| Module | Location | Purpose |
|--------|----------|---------|
| Routes | `server/src/routes/` | HTTP API handlers |
| AI/Agent | `server/src/ai/` | Agent system, Anthropic client |
| Workflows | `server/src/workflows/` | Workflow execution engine |
| Middleware | `server/src/middleware/` | Auth, CSRF, rate limiting, validation |
| WebSocket | `server/src/websocket/` | Real-time agent streaming |
| SSH | `server/src/ssh/` | Git over SSH |
| Services | `server/src/services/` | Background services (repo watcher, cleanup) |
| Dispatch | `server/src/dispatch/` | Task queue for runners |

## Route Categories

### Auth (`routes/auth.zig`)
- `POST /api/auth/siwe/verify` - SIWE wallet login
- `POST /api/auth/siwe/register` - New user registration
- `GET /api/auth/me` - Current user info
- `POST /api/auth/logout` - Logout

### Repositories (`routes/repositories.zig`)
- `POST /api/repos` - Create repository
- `GET/POST/DELETE /api/:user/:repo/star` - Star management
- `GET/PUT /api/:user/:repo/topics` - Repository topics
- Bookmarks (jj branches): CRUD at `/api/:user/:repo/bookmarks`

### Issues (`routes/issues.zig`)
- Full issue lifecycle: create, update, close, reopen, delete
- Comments, labels, reactions, assignees
- Dependencies and due dates

### Agent Sessions (`routes/sessions.zig`, `routes/messages.zig`)
- `POST /api/sessions` - Create agent session
- `GET /api/sessions/:id/stream` - SSE streaming
- Messages and parts CRUD

### Workflows v2 (`routes/workflows_v2.zig`)
- `POST /api/workflows/parse` - Parse workflow definition
- `POST /api/workflows/run` - Execute workflow
- `GET /api/workflows/runs/:id/stream` - Stream execution

### Internal (`routes/internal.zig`)
- Runner pod registration and heartbeat
- Task streaming and completion

## Middleware Stack

Applied in order: `validation -> auth -> rate_limit -> csrf`

```zig
// Wrap handlers requiring auth + CSRF
router.post("/api/repos", withAuthAndCsrf(repo_routes.createRepository), .{});

// Auth only (no CSRF for GET)
router.get("/api/sessions/:id", withAuth(sessions.getSession), .{});

// Rate limiting for auth endpoints
router.post("/api/auth/siwe/verify", withRateLimit(rate_limit.presets.login, "login", auth_routes.verify), .{});
```

## Server Context

```zig
pub const Context = struct {
    allocator: std.mem.Allocator,
    pool: *db.Pool,           // Database connection pool
    config: config.Config,
    csrf_store: *CsrfStore,
    repo_watcher: ?*RepoWatcher,
    edge_notifier: ?*EdgeNotifier,
    connection_manager: ?*ConnectionManager,  // WebSocket connections
    user: ?User,              // Set by auth middleware
    session_key: ?[]const u8,
    token_scopes: ?[]const u8,
};
```

## Background Services

Started in `main.zig`:

| Service | Purpose |
|---------|---------|
| `RepoWatcher` | Monitors git repos for changes |
| `SessionCleanup` | Cleans expired sessions |
| `EdgeNotifier` | Notifies CDN of cache invalidation |

## AI Tools

Located in `server/src/ai/tools/`:

| Tool | File | Purpose |
|------|------|---------|
| `read_file` | `read_file.zig` | Read file contents |
| `write_file` | `write_file.zig` | Write/create files |
| `multiedit` | `multiedit.zig` | Multi-file edits |
| `filesystem` | `filesystem.zig` | List directories, file ops |
| `grep` | `grep.zig` | Search file contents |
| `web_fetch` | `web_fetch.zig` | HTTP requests |
| `github` | `github.zig` | GitHub API integration |

## Configuration

Environment variables loaded via `config.zig`:

```bash
PORT=4000
DATABASE_URL=postgresql://...
ANTHROPIC_API_KEY=sk-ant-...
SSH_ENABLED=true
SSH_PORT=2222
WATCHER_ENABLED=true
EDGE_URL=https://...
```

## Build & Run

```bash
zig build run          # Start server (also starts docker)
zig build test:zig     # Run Zig tests
```
