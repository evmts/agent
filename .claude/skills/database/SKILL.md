---
name: database
description: Plue database schema, migrations, and table structure. Use when working with the database, writing queries, or understanding data models.
---

# Plue Database

PostgreSQL 16 database with ~40 tables.

## Schema Location

- Schema file: `db/schema.sql`
- DAOs (Zig only): `db/daos/`

## Table Domains

### Auth Domain

| Table | Purpose |
|-------|---------|
| `users` | User accounts (id, username, wallet_address, email) |
| `auth_sessions` | Cookie sessions (session_key, user_id, expires_at) |
| `access_tokens` | API tokens (token_hash, scopes, expires_at) |
| `siwe_nonces` | SIWE replay protection (nonce, expires_at, used_at) |
| `ssh_keys` | SSH public keys (user_id, fingerprint, public_key) |

### Git Domain

| Table | Purpose |
|-------|---------|
| `repositories` | Repos (owner, name, is_public, default_branch) |
| `branches` | Branch metadata (repo_id, name, commit_id) |
| `protected_branches` | Branch protection rules |

### Collaboration Domain

| Table | Purpose |
|-------|---------|
| `issues` | Issues/PRs (repo_id, issue_number, title, state) |
| `comments` | Issue comments |
| `labels` | Label definitions |
| `issue_labels` | Issue-label associations |
| `issue_assignees` | Issue-user associations |
| `milestones` | Milestone tracking |
| `reactions` | Emoji reactions |
| `reviews` | PR reviews |
| `review_comments` | Line-level PR comments |

### Agent/Workflow Domain

| Table | Purpose |
|-------|---------|
| `sessions` | Agent sessions (directory, model, token_count) |
| `messages` | Chat messages (session_id, role, status) |
| `parts` | Message parts (text, tool_call, tool_result) |
| `workflow_definitions` | Workflow configs (triggers, plan DAG) |
| `workflow_runs` | Execution instances |
| `workflow_steps` | Individual steps in run |
| `workflow_logs` | Step output logs |
| `runner_pool` | Warm runner pod registry |

## Key Relationships

```sql
users ──┬── repositories
        ├── issues ──── comments
        ├── sessions ── messages ── parts
        └── ssh_keys

repositories ──┬── issues ── labels
               ├── branches
               ├── workflow_definitions ── workflow_runs ── workflow_steps
               └── protected_branches
```

## Connection

Database connections are managed exclusively by the Zig API server. The UI does not connect to the database directly.

```bash
# Environment variable (Zig server only)
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/plue

# Zig connection pool (single pool in server)
const pool = try db.Pool.init(allocator, config.database_url);
defer pool.deinit();
```

## DAOs (Data Access Objects)

Located in `db/daos/` (Zig):

```zig
// db/daos/users.zig
pub fn getById(pool: *Pool, id: u64) !?User
pub fn getByUsername(pool: *Pool, username: []const u8) !?User
pub fn create(pool: *Pool, data: CreateUserData) !User

// db/daos/issues.zig
pub fn list(pool: *Pool, repo_id: u64, filters: IssueFilters) ![]Issue
pub fn create(pool: *Pool, data: CreateIssueData) !Issue
pub fn update(pool: *Pool, id: u64, data: UpdateIssueData) !Issue
```

## Common Queries

```sql
-- Get user with repos
SELECT u.*, array_agg(r.name) as repos
FROM users u
LEFT JOIN repositories r ON r.user_id = u.id
WHERE u.username = $1
GROUP BY u.id;

-- Get issue with labels
SELECT i.*, array_agg(l.name) as labels
FROM issues i
LEFT JOIN issue_labels il ON il.issue_id = i.id
LEFT JOIN labels l ON l.id = il.label_id
WHERE i.id = $1
GROUP BY i.id;

-- Recent workflow runs
SELECT wr.*, wd.name as workflow_name
FROM workflow_runs wr
JOIN workflow_definitions wd ON wd.id = wr.definition_id
WHERE wr.repo_id = $1
ORDER BY wr.created_at DESC
LIMIT 20;
```

## Migrations

Currently using raw SQL schema. Run:

```bash
# Apply schema
psql $DATABASE_URL < db/schema.sql

# Or via Docker
docker compose exec postgres psql -U postgres -d plue < db/schema.sql
```

## Indexes

Key indexes for performance:

```sql
CREATE INDEX idx_issues_repo_state ON issues(repo_id, state);
CREATE INDEX idx_workflow_runs_repo_status ON workflow_runs(repo_id, status);
CREATE INDEX idx_messages_session ON messages(session_id, created_at);
CREATE INDEX idx_auth_sessions_key ON auth_sessions(session_key);
CREATE INDEX idx_ssh_keys_fingerprint ON ssh_keys(fingerprint);
```

## Local Development

```bash
docker compose up -d postgres    # Start PostgreSQL
zig build run                    # Server connects automatically
```

## MCP Tools

Use the `database` MCP server for debugging:

```
mcp__database__query(sql="SELECT * FROM users LIMIT 5")
mcp__database__list_tables()
mcp__database__describe_table(table="issues")
mcp__database__find_user(username="alice")
mcp__database__db_stats()
```
