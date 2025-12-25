# Database Layer

PostgreSQL database access layer with Zig DAOs. The Astro UI accesses the database via the Zig API server (`ui/lib/api.ts`).

## Architecture

```
db/
├── schema.sql          # Single-source-of-truth schema (50 tables)
├── root.zig            # Zig DAO module exports
├── build.zig           # Zig build configuration
└── daos/               # Data Access Objects (Zig only)
```

## Table Groups

The schema is organized into functional domains:

| Domain | Tables | Purpose |
|--------|--------|---------|
| **Users** | users, email_addresses | User accounts with SIWE auth |
| **Auth** | auth_sessions, access_tokens, siwe_nonces | Authentication and sessions |
| **Repositories** | repositories, branches, bookmarks | Git repository metadata |
| **Issues** | issues, comments, issue_assignees, issue_labels, issue_dependencies, subtasks | Issue tracking system |
| **Code Review** | landing_queue, landing_reviews, landing_line_comments, reviews, review_comments | Landing system (Phabricator-style) |
| **Pull Requests** | pull_requests, conflicts | GitHub-style pull requests |
| **Changes** | changes, parts, file_trackers | Change tracking (jj-lib integration) |
| **Workflows** | workflow_definitions, workflow_runs, workflow_steps, workflow_logs | AI agent workflow execution |
| **VCS** | jj_operations, snapshot_history, renamed_branches, protected_branches | Jujutsu VCS operations |
| **Collaboration** | mentions, reactions, stars, watches, messages, pinned_issues | Social features |
| **Infrastructure** | runner_pool, llm_usage, rate_limits, ssh_keys, commit_statuses | System operations |
| **Milestones** | milestones, labels | Project management |

## Data Access Patterns

### Server-Side (Zig)
- Direct PostgreSQL access via `pg` library
- Type-safe query builders in `daos/*.zig`
- Re-exported through `root.zig`
- Used by API routes and workflows

### Frontend (Astro UI)
- Calls Zig API via `ui/lib/api.ts` typed client
- No direct database access from frontend
- Server-side rendering with API data fetching

## Key Features

### Atomic Operations
```sql
-- Issue number assignment (prevents race conditions)
SELECT get_next_issue_number(repo_id);
```

### SIWE Authentication
- Wallet-based auth via Sign-In With Ethereum
- Nonce management for replay protection
- Session management with auto-refresh

### Workflow Execution
- Agent-driven workflow definitions
- Step-by-step execution tracking
- LLM usage metrics and cost tracking

### Change Tracking
- Jujutsu (jj) integration via Rust FFI
- Content-addressable storage
- Snapshot history for all operations

## Quick Reference

```zig
// Zig (server-side): Import database layer
const db = @import("db");
const user = try db.getUserById(pool, user_id);
```

```typescript
// TypeScript (Astro UI): Call API
import { api } from '@/lib/api';
const user = await api.users.getById(userId);
```

## Schema Access

| File | Purpose |
|------|---------|
| `schema.sql` | Complete PostgreSQL schema (DDL) |
| `root.zig` | Zig DAO exports and types |
| `daos/*.zig` | Individual DAO implementations |

## Connection

Default connection: `postgresql://localhost:5432/plue`

Docker managed via `zig build run` (spins up PostgreSQL container automatically).

## Testing

```bash
zig build test:zig       # Includes Zig DAO tests
```

See `daos/*_test.zig` for test examples.
