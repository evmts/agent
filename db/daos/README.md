# Data Access Objects (DAOs)

Zig modules for type-safe PostgreSQL operations. Each DAO corresponds to one or more database tables.

## DAO Modules

| Module | Tables | Purpose |
|--------|--------|---------|
| `users.zig` | users, email_addresses | User account operations |
| `sessions.zig` | auth_sessions, siwe_nonces | Session and nonce management |
| `tokens.zig` | access_tokens | API token operations |
| `ssh_keys.zig` | ssh_keys | SSH key management |
| `repositories.zig` | repositories | Repository CRUD |
| `issues.zig` | issues, comments, issue_* | Issue tracking system |
| `labels.zig` | labels, issue_labels | Label management |
| `milestones.zig` | milestones | Milestone operations |
| `reactions.zig` | reactions | Reaction system (emoji responses) |
| `stars.zig` | stars | Repository starring |
| `workflows.zig` | workflow_*, llm_usage | AI workflow execution |
| `changes.zig` | changes, parts, file_trackers | Change tracking (jj-lib) |
| `agent.zig` | prompt_definitions, sessions | Agent configuration |
| `landing.zig` | landing_queue, landing_reviews, landing_line_comments | Code review landing system |

## Structure

Each DAO module follows this pattern:

```zig
// Type definitions
pub const Record = struct {
    id: i32,
    name: []const u8,
    created_at: i64,
};

// CRUD operations
pub fn create(pool: *Pool, data: CreateData) !Record { }
pub fn getById(pool: *Pool, id: i32) !?Record { }
pub fn update(pool: *Pool, id: i32, data: UpdateData) !void { }
pub fn delete(pool: *Pool, id: i32) !void { }

// Custom queries
pub fn findByUsername(pool: *Pool, username: []const u8) !?Record { }
```

## Re-exports

All DAOs are re-exported through `../root.zig` for convenience:

```zig
const db = @import("db");

// Direct access
const user = try db.users.getById(pool, id);

// Re-exported convenience function
const user = try db.getUserById(pool, id);
```

## Testing

Test files follow the pattern `*_test.zig`:

```
daos/
├── users.zig
├── issues.zig
├── issues_test.zig      # Tests for issues.zig
├── workflows.zig
└── workflows_test.zig   # Tests for workflows.zig
```

Run tests:
```bash
zig build test:db
```

## Type Safety

DAOs use Zig's compile-time type system for query safety:

```zig
// Compile-time SQL validation
const result = try pool.query(
    \\SELECT id, username, email
    \\FROM users
    \\WHERE id = $1
, .{user_id});

// Type-safe result parsing
const user = try result.row(UserRecord);
```

## Connection Management

DAOs accept a `*Pool` or `*Conn` parameter:

```zig
// Use connection pool (most operations)
const user = try users.getById(pool, id);

// Use explicit connection (transactions)
const conn = try pool.acquire();
defer conn.release();
try conn.begin();
try users.create(conn, data);
try sessions.create(conn, session_data);
try conn.commit();
```

## Common Patterns

### Atomic Operations
```zig
// Get next issue number atomically
const issue_num = try pool.queryRow(
    "SELECT get_next_issue_number($1)",
    .{repo_id},
    i32,
);
```

### Case-Insensitive Lookups
```zig
// Uses lower_username index
const user = try users.getByUsername(pool, username);
```

### JSON Columns
```zig
// JSONB stored as []const u8, parsed as needed
const workflow = try workflows.getById(pool, id);
const triggers = try std.json.parseFromSlice(Triggers, allocator, workflow.triggers);
```

### Timestamps
```zig
// Stored as TIMESTAMPTZ, represented as i64 (Unix ms)
const created_at = std.time.milliTimestamp();
try users.updateLastLogin(pool, user_id, created_at);
```

## Performance

Indexes are defined in `../schema.sql`:

```sql
-- Example: Fast user lookups
CREATE INDEX idx_users_lower_username ON users(lower_username);
CREATE INDEX idx_users_wallet_address ON users(wallet_address);
```

DAOs leverage these indexes for efficient queries.
