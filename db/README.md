# Database Layer

PostgreSQL database access layer with dual language support: Zig DAOs for server-side operations and TypeScript DAOs for UI/edge compatibility.

## Architecture

```
db/
├── schema.sql          # Single-source-of-truth schema (50 tables)
├── root.zig            # Zig DAO module exports
├── index.ts            # TypeScript DAO module exports
├── daos/               # Data Access Objects (Zig)
└── migrations/         # Schema migration files
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

## Language Support

### Zig DAOs (server/core)
- Direct PostgreSQL access via `pg` library
- Type-safe query builders
- Located in `daos/*.zig`
- Re-exported through `root.zig`

### TypeScript DAOs (ui/edge)
- PostgreSQL access via `postgres.js`
- Used in Astro SSR pages and edge workers
- Located in `*.ts` files
- Re-exported through `index.ts`

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
// Zig: Import database layer
const db = @import("db");
const user = try db.getUserById(pool, user_id);

// TypeScript: Import database layer
import { getUserById } from '@/db';
const user = await getUserById(userId);
```

## Schema Access

| File | Purpose |
|------|---------|
| `schema.sql` | Complete PostgreSQL schema (DDL) |
| `migrations/` | Incremental schema changes |
| `root.zig` | Zig DAO exports and types |
| `index.ts` | TypeScript DAO exports |

## Connection

Default connection: `postgresql://localhost:5432/plue`

Docker managed via `zig build run` (spins up PostgreSQL container automatically).

## Testing

```bash
zig build test:db        # Zig DAO tests
npm test                 # TypeScript DAO tests (if configured)
```

See `daos/*_test.zig` for Zig test examples.
