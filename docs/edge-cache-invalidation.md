# Edge Cache Invalidation Architecture

## Overview

Plue's edge cache invalidation system provides real-time cache updates using push-based notifications from the Kubernetes cluster to Cloudflare Workers. This eliminates the need for TTL-based polling and ensures data consistency while significantly reducing origin load.

### Problem Solved

Traditional edge caching relies on Time-To-Live (TTL) expiration, typically checking for updates every 5 seconds. This creates two problems:

1. **Stale Data Window**: Users see stale data for up to 5 seconds after changes
2. **Unnecessary Load**: Edge continuously polls even when no changes occur

Plue's solution provides:

- **Push-based Invalidation**: K8s notifies edge immediately when data changes
- **Merkle-Validated Git Cache**: Git data is validated using cryptographic tree hashes
- **Graceful Degradation**: Falls back to 5-second TTL if push notifications fail
- **Reduced Origin Load**: Edge only fetches when actual changes occur

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Write Flow                                   │
└─────────────────────────────────────────────────────────────────────┘

    User Request (POST/PUT/DELETE)
           │
           ▼
    ┌─────────────┐
    │   Worker    │  (Cloudflare Edge)
    │   (Proxy)   │
    └──────┬──────┘
           │ proxies all writes
           ▼
    ┌─────────────┐
    │   API       │  (Kubernetes Pod)
    │   (Zig)     │
    └──────┬──────┘
           │
           ├─────────────┐
           │             │
           ▼             ▼
    ┌──────────┐  ┌───────────────┐
    │PostgreSQL│  │ EdgeNotifier  │
    │          │  │   Service     │
    └────┬─────┘  └───────┬───────┘
         │                │
         │                │ POST /invalidate
         │                │ { type: "sql" | "git", ... }
         │                │
         │                ▼
         │        ┌──────────────────┐
         │        │  Durable Object  │ (Cloudflare Edge)
         │        │  (DataSyncDO)    │
         │        └─────────┬────────┘
         │                  │
         ▼                  ▼
    ┌────────────────────────────┐
    │   ElectricSQL Sync         │
    └────────────────────────────┘
         clears shape cache & merkle roots


┌─────────────────────────────────────────────────────────────────────┐
│                         Read Flow                                    │
└─────────────────────────────────────────────────────────────────────┘

    User Request (GET)
           │
           ▼
    ┌─────────────┐
    │   Worker    │  (Cloudflare Edge)
    │   Handler   │
    └──────┬──────┘
           │
           ▼
    ┌─────────────┐
    │  Durable    │  (Cloudflare DO)
    │  Object     │
    │  (SQL DO)   │
    └──────┬──────┘
           │
           ├─── Check cache ───┐
           │                   │
           ▼                   ▼
    [Cache Hit]         [Cache Miss]
           │                   │
           │                   ├─ ensureSync() ──┐
           │                   │                 │
           │                   ▼                 ▼
           │          ┌──────────────┐   ┌──────────────┐
           │          │  ElectricSQL │   │  PostgreSQL  │
           │          │  ShapeStream │   │   (Origin)   │
           │          └──────┬───────┘   └──────────────┘
           │                 │
           │                 └─ Stream changes
           │                       │
           ▼                       ▼
    Return Cached Data ◄─── Update Cache
```

## Architecture Components

### 1. SQL Data Sync (ElectricSQL)

The SQL data sync system uses ElectricSQL's ShapeStream to synchronize PostgreSQL data to Cloudflare Durable Objects.

#### How ElectricSQL ShapeStream Works

ElectricSQL provides real-time PostgreSQL replication through "shapes" - queries that define a subset of data to sync:

```typescript
const stream = new ShapeStream({
  url: `${ELECTRIC_URL}/v1/shape`,
  params: {
    table: 'repositories',
    where: 'is_public = true',
    offset: lastOffset,    // Resume from last position
    handle: shapeHandle    // Shape identity token
  }
});

for await (const messages of stream) {
  for (const message of messages) {
    if (isChangeMessage(message)) {
      // Process: insert, update, or delete
      applyChange(table, message);
    }
    if (isControlMessage(message) && message.headers?.control === 'up-to-date') {
      // Initial sync complete, cache is fresh
      break;
    }
  }
}
```

**Key Concepts:**

- **Shape**: A filtered view of table data (table + where clause)
- **Offset**: Position in the change stream for resuming
- **Handle**: Token identifying the shape definition
- **Change Messages**: Insert/update/delete operations
- **Control Messages**: Metadata like "up-to-date" marker

#### Push Invalidation vs TTL Fallback

The system operates in two modes controlled by the `ENABLE_PUSH_INVALIDATION` feature flag:

**Push Mode (Preferred):**
```typescript
if (this.enablePushInvalidation) {
  // Trust cached data indefinitely
  // Only refresh when receiving push notification
  return;
}
```

**TTL Fallback Mode:**
```typescript
// Check if cache is older than 5 seconds
if (now.getTime() - lastSync.getTime() < 5000) {
  return; // Cache is fresh
}
// Cache is stale, resync from ElectricSQL
```

This dual-mode approach ensures:
- **Optimal Performance**: Push mode provides instant updates with zero polling
- **Graceful Degradation**: TTL mode maintains functionality if push system fails
- **Easy Rollout**: Feature flag allows testing before full deployment

#### Feature Flag: ENABLE_PUSH_INVALIDATION

Set in `/Users/williamcory/agent/edge/wrangler.toml`:

```toml
[vars]
ENABLE_PUSH_INVALIDATION = "false"  # Disabled by default

[env.dev]
[env.dev.vars]
ENABLE_PUSH_INVALIDATION = "true"   # Enabled in dev

[env.production]
# Set via dashboard or terraform
```

**Deployment Strategy:**

1. Deploy with flag disabled (uses TTL)
2. Test push endpoint manually
3. Enable flag in staging
4. Monitor cache hit rates
5. Roll out to production

### 2. Git Data Cache (Merkle Validation)

Git data (file content, directory trees) is cached at the edge with cryptographic validation using merkle tree hashes.

#### Merkle Root Concept

A merkle root is a cryptographic hash representing the entire state of a git tree. In jj (Jujutsu VCS), every commit has a tree hash that uniquely identifies the repository state:

```
Repository State:
  /src/main.zig     (hash: abc123...)
  /src/config.zig   (hash: def456...)
  /README.md        (hash: 789xyz...)
                        ↓
            Combine hashes recursively
                        ↓
          Tree Hash: 4f2a8b9c... (merkle root)
```

**Properties:**

- **Deterministic**: Same files → same hash
- **Collision-Resistant**: Different content → different hash
- **Efficient**: Single comparison validates entire tree

#### How Tree Hash FFI Works

The Zig server calls into Rust FFI to compute jj tree hashes:

**C Header** (`/Users/williamcory/agent/server/jj-ffi/jj_ffi.h`):
```c
typedef struct JjTreeHash {
    char* hash;
    bool success;
    char* error_message;
} JjTreeHash;

JjTreeHash jj_get_tree_hash(
    const JjWorkspace* workspace,
    const char* revision  // "@" for working copy, or commit ID
);
```

**Zig Usage** (`/Users/williamcory/agent/server/src/services/repo_watcher.zig`):
```zig
// After syncing changes to database
const tree_hash = jj.jj_get_tree_hash(workspace, "@");

if (tree_hash.success) {
    defer jj.jj_free_tree_hash(tree_hash);

    const repo_key = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ watched_repo.user, watched_repo.repo }
    );
    const hash_str = std.mem.span(tree_hash.hash);

    // Notify edge of new merkle root
    notifier.notifyGitChange(repo_key, hash_str);
}
```

**Rust Implementation** (`/Users/williamcory/agent/server/jj-ffi/src/lib.rs`):
```rust
#[no_mangle]
pub extern "C" fn jj_get_tree_hash(
    workspace: *const JjWorkspace,
    revision: *const c_char
) -> JjTreeHash {
    // Open workspace, load commit
    let commit = repo.store().get_commit(&commit_id)?;
    let tree = commit.tree()?;

    // Compute tree hash (merkle root)
    let tree_id = tree.id();
    let hash = CString::new(tree_id.hex())?;

    JjTreeHash {
        hash: hash.into_raw(),
        success: true,
        error_message: std::ptr::null_mut()
    }
}
```

#### Cache Tables

Three tables work together in the Durable Object's SQLite storage:

**merkle_roots**: Current valid hash per repository
```sql
CREATE TABLE merkle_roots (
    repo_ref TEXT PRIMARY KEY,      -- "owner/repo:main"
    root_hash TEXT NOT NULL,        -- "4f2a8b9c..."
    updated_at TEXT NOT NULL
);
```

**git_trees**: Cached directory listings
```sql
CREATE TABLE git_trees (
    cache_key TEXT PRIMARY KEY,     -- "owner/repo:main:src/"
    merkle_root TEXT NOT NULL,      -- Validates cache entry
    tree_data TEXT NOT NULL,        -- JSON array of files
    cached_at TEXT NOT NULL
);
```

**git_files**: Cached file content with LRU eviction
```sql
CREATE TABLE git_files (
    cache_key TEXT PRIMARY KEY,     -- "owner/repo:main:src/main.zig"
    merkle_root TEXT NOT NULL,      -- Validates cache entry
    content TEXT NOT NULL,          -- File contents
    size INTEGER NOT NULL,          -- For LRU tracking
    accessed_at TEXT NOT NULL       -- For LRU eviction
);
CREATE INDEX idx_git_files_accessed ON git_files(accessed_at);
```

#### Cache Validation Flow

**Reading Cached Data:**
```typescript
async getFileContent(owner: string, repo: string, ref: string, path: string): Promise<string | null> {
  const repoRef = `${owner}/${repo}:${ref}`;
  const cacheKey = `${repoRef}:${path}`;

  // 1. Get current merkle root
  const rootRow = this.sql.exec(
    'SELECT root_hash FROM merkle_roots WHERE repo_ref = ?',
    repoRef
  ).toArray()[0];

  if (!rootRow) {
    return null; // No merkle root known yet
  }

  // 2. Check cache
  const cached = this.sql.exec(
    'SELECT content, merkle_root FROM git_files WHERE cache_key = ?',
    cacheKey
  ).toArray()[0];

  // 3. Validate merkle root matches
  if (cached && cached.merkle_root === rootRow.root_hash) {
    // Cache hit - merkle root validates data is current
    this.sql.exec(
      'UPDATE git_files SET accessed_at = ? WHERE cache_key = ?',
      new Date().toISOString(), cacheKey
    );
    return cached.content;
  }

  // Cache miss or invalidated
  return null;
}
```

**Invalidating Cached Data:**
```typescript
async handleGitInvalidation(msg: InvalidationMessage): Promise<void> {
  const repoRef = `${msg.repoKey}:main`;

  // Update merkle root - automatically invalidates all cached data
  // for this repo since cache lookups compare against current root
  this.sql.exec(
    `INSERT OR REPLACE INTO merkle_roots (repo_ref, root_hash, updated_at)
     VALUES (?, ?, ?)`,
    repoRef, msg.merkleRoot, new Date().toISOString()
  );

  // Old cached entries remain but are ignored due to merkle mismatch
  // They'll be eventually evicted by LRU or overwritten
}
```

**Why This Works:**

1. Merkle root changes every commit
2. Cache entries store the root they were fetched under
3. Comparison between current root and cache root is instant
4. No need to delete old entries - they're automatically invalid
5. LRU eviction cleans up stale entries over time

#### LRU Eviction Strategy

File cache is limited to 50MB with LRU (Least Recently Used) eviction:

```typescript
private readonly MAX_FILE_CACHE_SIZE = 50 * 1024 * 1024; // 50MB

private async evictFileCacheIfNeeded(neededSize: number): Promise<void> {
  const total = this.sql.exec(
    'SELECT COALESCE(SUM(size), 0) as total FROM git_files'
  ).toArray()[0];

  if (total.total + neededSize <= this.MAX_FILE_CACHE_SIZE) {
    return; // Plenty of space
  }

  // Delete oldest accessed files in batches of 100
  while (true) {
    const currentTotal = this.sql.exec(
      'SELECT COALESCE(SUM(size), 0) as total FROM git_files'
    ).toArray()[0];

    if (currentTotal.total + neededSize <= this.MAX_FILE_CACHE_SIZE) {
      break; // Enough space now
    }

    this.sql.exec(`
      DELETE FROM git_files WHERE cache_key IN (
        SELECT cache_key FROM git_files
        ORDER BY accessed_at ASC
        LIMIT 100
      )
    `);
  }
}
```

**Design Considerations:**

- **50MB Limit**: Balances cache effectiveness with DO storage limits
- **Batch Deletion**: Avoids long transactions, deletes 100 entries at a time
- **accessed_at Index**: Makes LRU queries efficient
- **Safety Check**: Prevents infinite loop if deletion fails

### 3. Push Endpoint

The `/invalidate` endpoint on Durable Objects receives push notifications from the Kubernetes cluster.

#### Endpoint Implementation

Located in `/Users/williamcory/agent/edge/src/durable-objects/data-sync.ts`:

```typescript
async fetch(request: Request): Promise<Response> {
  const url = new URL(request.url);

  if (url.pathname === '/invalidate' && request.method === 'POST') {
    // 1. Verify shared secret
    const auth = request.headers.get('Authorization');
    if (auth !== `Bearer ${this.env.PUSH_SECRET}`) {
      return new Response('Unauthorized', { status: 401 });
    }

    try {
      // 2. Parse invalidation message
      const msg: InvalidationMessage = await request.json();

      if (msg.type === 'sql') {
        // Clear shape metadata to force resync
        this.sql.exec(
          'DELETE FROM shape_sync_metadata WHERE shape_name LIKE ?',
          `${msg.table}%`
        );
      } else if (msg.type === 'git') {
        // Update merkle root
        await this.handleGitInvalidation(msg);
      }

      return new Response(JSON.stringify({ ok: true }), {
        headers: { 'Content-Type': 'application/json' }
      });
    } catch (e) {
      return new Response(JSON.stringify({ error: 'Invalid request' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }

  return new Response('Not found', { status: 404 });
}
```

#### Authentication with PUSH_SECRET

Shared secret authentication ensures only the K8s cluster can invalidate:

**K8s Side** (`/Users/williamcory/agent/server/src/config.zig`):
```zig
pub const Config = struct {
    // ...
    edge_url: []const u8,           // "https://plue-edge.plue.dev"
    edge_push_secret: []const u8,   // "random-secret-value"
};

pub fn load() Config {
    return .{
        // ...
        .edge_url = std.posix.getenv("EDGE_URL") orelse "",
        .edge_push_secret = std.posix.getenv("EDGE_PUSH_SECRET") orelse "",
    };
}
```

**Edge Side** (`/Users/williamcory/agent/edge/wrangler.toml`):
```toml
[vars]
PUSH_SECRET = ""  # Set via wrangler secret

[env.dev.vars]
PUSH_SECRET = "dev-secret-change-me"
```

**Setting in Production:**
```bash
# Via wrangler CLI
wrangler secret put PUSH_SECRET

# Or via Terraform (recommended)
# See section "Terraform Configuration" below
```

#### Message Format (InvalidationMessage)

TypeScript definition (`/Users/williamcory/agent/edge/src/types.ts`):
```typescript
export interface InvalidationMessage {
  type: 'sql' | 'git';
  table?: string;        // For SQL: "repositories", "issues", etc.
  repoKey?: string;      // For git: "alice/project"
  merkleRoot?: string;   // For git: "4f2a8b9c..."
  timestamp: number;     // Unix timestamp
}
```

Zig definition (`/Users/williamcory/agent/server/src/services/edge_notifier.zig`):
```zig
pub const InvalidationMessage = struct {
    type: InvalidationType,    // .sql or .git
    table: ?[]const u8 = null,
    repo_key: ?[]const u8 = null,
    merkle_root: ?[]const u8 = null,
    timestamp: i64,

    pub fn toJson(self: *const InvalidationMessage, allocator: std.mem.Allocator) ![]const u8 {
        // Serialize to JSON string
        // {"type":"git","repo_key":"alice/project","merkle_root":"4f2a8b9c...","timestamp":1234567890}
    }
};
```

**Example Messages:**

SQL invalidation:
```json
{
  "type": "sql",
  "table": "repositories",
  "repoKey": "alice/project",
  "timestamp": 1704067200
}
```

Git invalidation:
```json
{
  "type": "git",
  "repoKey": "alice/project",
  "merkleRoot": "4f2a8b9cf6e3a1d8b7e5c2f9a1b8d4e6f3a9c2d5e8b1f4a7c2d5e8b1f4a7c2",
  "timestamp": 1704067200
}
```

### 4. EdgeNotifier Service (Zig)

The EdgeNotifier service in the Zig API server sends invalidation notifications to the edge.

#### Integration with K8s

Located in `/Users/williamcory/agent/server/src/services/edge_notifier.zig`:

```zig
pub const EdgeNotifier = struct {
    allocator: std.mem.Allocator,
    edge_base_url: []const u8,    // "https://plue-edge.plue.dev"
    push_secret: []const u8,      // Loaded from env

    pub fn init(allocator: std.mem.Allocator, edge_base_url: []const u8, push_secret: []const u8) EdgeNotifier {
        return .{
            .allocator = allocator,
            .edge_base_url = edge_base_url,
            .push_secret = push_secret,
        };
    }

    /// Notify the edge of a SQL table change
    pub fn notifySqlChange(self: *EdgeNotifier, table: []const u8, repo_key: ?[]const u8) !void {
        const timestamp = std.time.timestamp();

        const msg = InvalidationMessage{
            .type = .sql,
            .table = table,
            .repo_key = repo_key,
            .timestamp = timestamp,
        };

        try self.sendInvalidation("global", &msg);
    }

    /// Notify the edge of a git repository change
    pub fn notifyGitChange(self: *EdgeNotifier, repo_key: []const u8, merkle_root: []const u8) !void {
        const timestamp = std.time.timestamp();

        const msg = InvalidationMessage{
            .type = .git,
            .repo_key = repo_key,
            .merkle_root = merkle_root,
            .timestamp = timestamp,
        };

        // Build DO name: "repo:{owner}/{repo}"
        const do_name = try std.fmt.allocPrint(self.allocator, "repo:{s}", .{repo_key});
        defer self.allocator.free(do_name);

        try self.sendInvalidation(do_name, &msg);
    }
};
```

**K8s Configuration:**

Environment variables set in Terraform (`/Users/williamcory/agent/terraform/kubernetes/services/api.tf`):

```hcl
env {
  name  = "EDGE_URL"
  value = "https://plue-edge.${var.domain}"
}

env {
  name = "EDGE_PUSH_SECRET"
  value_from {
    secret_key_ref {
      name = kubernetes_secret.edge_push_secret.metadata[0].name
      key  = "secret"
    }
  }
}
```

#### Retry Logic with Exponential Backoff

Implements robust retry logic to handle transient network failures:

```zig
fn sendInvalidation(self: *EdgeNotifier, do_name: []const u8, msg: *const InvalidationMessage) !void {
    // Skip if edge URL is not configured
    if (self.edge_base_url.len == 0) {
        log.debug("Edge URL not configured, skipping invalidation notification", .{});
        return;
    }

    // Build the URL: {edge_base_url}/do/{do_name}/invalidate
    const url = try std.fmt.allocPrint(self.allocator, "{s}/do/{s}/invalidate", .{ self.edge_base_url, do_name });
    defer self.allocator.free(url);

    // Retry logic: 3 attempts with exponential backoff (100ms, 200ms, 400ms)
    const max_attempts = 3;
    const base_delay_ms = 100;

    var attempt: u32 = 0;
    var last_error: ?anyerror = null;

    while (attempt < max_attempts) : (attempt += 1) {
        if (attempt > 0) {
            const delay_ms = base_delay_ms * (@as(u64, 1) << @intCast(attempt - 1));
            log.debug("Retrying invalidation (attempt {d}/{d}) after {d}ms", .{ attempt + 1, max_attempts, delay_ms });
            std.Thread.sleep(delay_ms * std.time.ns_per_ms);
        }

        // Send the request
        const result = self.sendHttpPost(url, json_body) catch |err| {
            log.warn("Failed to send invalidation (attempt {d}/{d}): {}", .{ attempt + 1, max_attempts, err });
            last_error = err;
            continue;
        };

        // Success
        log.info("Invalidation sent successfully to {s} (attempt {d}/{d})", .{ do_name, attempt + 1, max_attempts });
        return result;
    }

    // All retries failed
    if (last_error) |err| {
        log.err("Failed to send invalidation after {d} attempts: {}", .{ max_attempts, err });
        return err;
    }
}
```

**Retry Schedule:**

- Attempt 1: Immediate
- Attempt 2: +100ms delay
- Attempt 3: +200ms delay
- Attempt 4: +400ms delay
- Total time: ~700ms worst case

**Error Handling:**

- Logs each retry attempt
- Returns error only after all retries exhausted
- Non-blocking: won't crash API server on failure
- Graceful degradation: cache falls back to TTL mode

#### Integration with Write Routes

RepoWatcher automatically notifies edge after syncing changes:

```zig
fn syncToDatabase(self: *RepoWatcher, watched_repo: *WatchedRepo) !void {
    // ... sync changes, bookmarks, operations, conflicts ...

    // After successful sync, notify edge with merkle root
    if (self.edge_notifier) |notifier| {
        const tree_hash = jj.jj_get_tree_hash(workspace, "@");

        if (tree_hash.success) {
            defer jj.jj_free_tree_hash(tree_hash);

            const repo_key = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}",
                .{ watched_repo.user, watched_repo.repo }
            );
            defer self.allocator.free(repo_key);

            const hash_str = std.mem.span(tree_hash.hash);

            notifier.notifyGitChange(repo_key, hash_str) catch |err| {
                log.warn("Failed to notify edge of git change: {}", .{err});
            };

            log.debug("Notified edge of merkle root update: {s} -> {s}",
                .{ repo_key, hash_str[0..@min(hash_str.len, 8)] });
        }
    }
}
```

## Data Flow Diagrams

### Write Flow

```
┌──────┐                                                    ┌──────────┐
│ User │ ───(1) git push───>                               │   K8s    │
└──────┘                                                    │   Pod    │
                                                            │  (API)   │
                                                            └────┬─────┘
                                                                 │
                           ┌─────────────────────────────────────┼──────────────────┐
                           │                                     │                  │
                      (2) Write                          (3) Sync to DB      (4) Get merkle
                      to .jj                             jj → postgres             root
                           │                                     │                  │
                           ▼                                     ▼                  ▼
                    ┌────────────┐                      ┌──────────────┐    ┌──────────┐
                    │ jj Repo    │                      │  PostgreSQL  │    │  jj FFI  │
                    │ Working    │                      │  (changes,   │    │ tree_hash│
                    │ Copy       │                      │  bookmarks)  │    │    ()    │
                    └────────────┘                      └──────┬───────┘    └─────┬────┘
                                                               │                   │
                                                               │                   │
                                                               ▼                   ▼
                                                        ┌─────────────┐    ┌──────────────┐
                                                        │ ElectricSQL │    │ EdgeNotifier │
                                                        │  Replicates │    │   Service    │
                                                        └─────────────┘    └──────┬───────┘
                                                                                  │
                                                                            (5) POST /invalidate
                                                                         {type:"git", merkleRoot:"..."}
                                                                                  │
                                                                                  ▼
                                                                          ┌───────────────┐
                                                                          │ Durable Object│
                                                                          │ DataSyncDO    │
                                                                          └───────┬───────┘
                                                                                  │
                                                                      (6) Update merkle_roots
                                                                       Invalidate git_trees
                                                                       Invalidate git_files
                                                                                  │
                                                                                  ▼
                                                                          [Cache Invalidated]
```

**Step Details:**

1. User pushes changes to repository
2. RepoWatcher detects .jj directory modification
3. Syncs changes to PostgreSQL (parallel: changes, bookmarks, operations, conflicts)
4. Calls jj FFI to compute tree hash (merkle root)
5. EdgeNotifier sends POST to `/invalidate` endpoint with merkle root
6. Durable Object updates merkle_roots table, automatically invalidating cached data

### Read Flow

```
┌──────┐
│ User │ ───(1) GET /alice/project/blob/main/src/main.zig───>
└──────┘

                                    ┌──────────────────┐
                                    │ Worker Handler   │
                                    │ (Cloudflare)     │
                                    └────────┬─────────┘
                                             │
                                    (2) Get DO stub
                                             │
                                             ▼
                                    ┌──────────────────┐
                                    │ Durable Object   │
                                    │ DataSyncDO       │
                                    └────────┬─────────┘
                                             │
                            ┌────────────────┴────────────────┐
                            │                                 │
                    (3) Check merkle_roots           (3) Check git_files
                            │                                 │
                            ▼                                 ▼
                    ┌──────────────┐                 ┌──────────────┐
                    │ merkle_roots │                 │  git_files   │
                    │ alice/project│                 │ cache entry  │
                    │ :main        │                 │              │
                    │ → 4f2a8b9c   │                 │ merkle_root  │
                    └──────┬───────┘                 │ = 4f2a8b9c   │
                           │                         └──────┬───────┘
                           │                                │
                           └────────(4) Compare─────────────┘
                                        │
                        ┌───────────────┴────────────────┐
                        │                                │
                    [Match]                          [Mismatch]
                        │                                │
                  (5) Cache HIT                   (6) Cache MISS
                Update accessed_at                      │
                        │                         Fetch from origin
                        │                         Cache new content
                        │                               │
                        ▼                               ▼
                ┌────────────────────────────────────────┐
                │       Return file content              │
                └────────────────────────────────────────┘
```

**Step Details:**

1. User requests file content via GET request
2. Worker routes to appropriate Durable Object
3. DO queries merkle_roots and git_files tables
4. Compares merkle roots to validate cache
5. **Cache Hit**: Merkle roots match, return cached content, update accessed_at
6. **Cache Miss**: Merkle roots differ, fetch from origin, cache with new merkle root

## Configuration

### Environment Variables

#### Cloudflare Worker (Edge)

Set in `/Users/williamcory/agent/edge/wrangler.toml`:

```toml
[vars]
ELECTRIC_URL = "http://origin-electric.internal:3000"
PUSH_SECRET = ""                          # Set via wrangler secret
ENABLE_PUSH_INVALIDATION = "false"        # Feature flag

[env.dev.vars]
ELECTRIC_URL = "http://localhost:3000"
PUSH_SECRET = "dev-secret-change-me"
ENABLE_PUSH_INVALIDATION = "true"
```

#### Kubernetes API Server

Set in `/Users/williamcory/agent/server/src/config.zig`:

```zig
pub fn load() Config {
    return .{
        .edge_url = std.posix.getenv("EDGE_URL") orelse "",
        .edge_push_secret = std.posix.getenv("EDGE_PUSH_SECRET") orelse "",
        // ...
    };
}
```

Injected via Terraform (`/Users/williamcory/agent/terraform/kubernetes/services/api.tf`):

```hcl
env {
  name  = "EDGE_URL"
  value = "https://plue-edge.${var.domain}"
}

env {
  name = "EDGE_PUSH_SECRET"
  value_from {
    secret_key_ref {
      name = kubernetes_secret.edge_push_secret.metadata[0].name
      key  = "secret"
    }
  }
}
```

### Terraform Configuration

Secrets are provisioned through Terraform's kubernetes provider.

**Generate Secret:**

```bash
# Generate a secure random secret
openssl rand -base64 32
```

**Set in Terraform Variables:**

Create `terraform/kubernetes/services/secrets.tf`:

```hcl
resource "kubernetes_secret" "edge_push_secret" {
  metadata {
    name      = "edge-push-secret"
    namespace = var.namespace
  }

  data = {
    secret = var.edge_push_secret  # Pass via terraform.tfvars
  }

  type = "Opaque"
}
```

**Set Secret via CLI:**

For Cloudflare Workers:

```bash
cd edge
wrangler secret put PUSH_SECRET
# Enter the same secret value
```

**Verify Configuration:**

```bash
# Check K8s secret exists
kubectl get secret edge-push-secret -n plue

# Check API pod has env vars
kubectl get pod -n plue -l app=api -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="EDGE_URL")].value}'

# Check Worker secret (via wrangler)
wrangler secret list
```

### Cloudflare Workers Bindings

Durable Object binding in `wrangler.toml`:

```toml
[[durable_objects.bindings]]
name = "DATA_SYNC"
class_name = "DataSyncDO"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["DataSyncDO"]
```

This creates a Durable Object namespace accessible as `env.DATA_SYNC` in the worker.

## Rollout Guide

### Phase 1: Deploy with Feature Flag Disabled

**Goal**: Deploy infrastructure without enabling push invalidation.

1. **Deploy Worker with flag off:**
   ```toml
   # edge/wrangler.toml
   [vars]
   ENABLE_PUSH_INVALIDATION = "false"
   ```

2. **Deploy to production:**
   ```bash
   cd edge
   wrangler deploy --env production
   ```

3. **Deploy K8s API with notifier:**
   ```bash
   cd terraform/kubernetes
   terraform apply
   ```

4. **Verify baseline:**
   - Edge cache uses 5-second TTL
   - No push notifications sent
   - System functions normally

### Phase 2: Test Invalidation Manually

**Goal**: Verify push endpoint works before enabling feature.

1. **Get PUSH_SECRET:**
   ```bash
   wrangler secret list
   ```

2. **Test SQL invalidation:**
   ```bash
   curl -X POST https://plue-edge.plue.dev/do/global/invalidate \
     -H "Authorization: Bearer YOUR_PUSH_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "sql",
       "table": "repositories",
       "timestamp": 1704067200
     }'

   # Expected: {"ok":true}
   ```

3. **Test git invalidation:**
   ```bash
   curl -X POST https://plue-edge.plue.dev/do/repo:alice/project/invalidate \
     -H "Authorization: Bearer YOUR_PUSH_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "git",
       "repoKey": "alice/project",
       "merkleRoot": "test123",
       "timestamp": 1704067200
     }'

   # Expected: {"ok":true}
   ```

4. **Check logs:**
   ```bash
   wrangler tail --env production
   ```

5. **Verify K8s can reach edge:**
   ```bash
   # Exec into API pod
   kubectl exec -it -n plue deployment/api -- sh

   # Test from inside pod
   curl -X POST https://plue-edge.plue.dev/do/global/invalidate \
     -H "Authorization: Bearer $EDGE_PUSH_SECRET" \
     -H "Content-Type: application/json" \
     -d '{"type":"sql","table":"test","timestamp":1704067200}'
   ```

### Phase 3: Enable Push Invalidation

**Goal**: Activate push-based cache invalidation.

1. **Enable in staging:**
   ```bash
   # Set via wrangler CLI
   wrangler secret put ENABLE_PUSH_INVALIDATION --env staging
   # Enter: true

   # Or via dashboard
   # Cloudflare Dashboard → Workers → plue-edge-staging → Settings → Variables
   ```

2. **Deploy updated config:**
   ```bash
   cd edge
   wrangler deploy --env staging
   ```

3. **Test in staging:**
   - Make a change to a repository
   - Verify edge receives invalidation
   - Verify cache updates immediately (no 5s delay)
   - Check worker logs for "Invalidation sent successfully"

4. **Enable in production:**
   ```bash
   wrangler secret put ENABLE_PUSH_INVALIDATION --env production
   # Enter: true

   wrangler deploy --env production
   ```

### Phase 4: Monitor Cache Hit Rates

**Goal**: Verify system performance improvements.

1. **Add cache metrics to Worker:**
   ```typescript
   // In Durable Object
   private cacheHits = 0;
   private cacheMisses = 0;

   async getFileContent(...): Promise<string | null> {
     // ... validation logic ...

     if (cached && cached.merkle_root === rootRow.root_hash) {
       this.cacheHits++;
       return cached.content;
     }

     this.cacheMisses++;
     return null;
   }

   // Endpoint to check metrics
   if (url.pathname === '/metrics') {
     return new Response(JSON.stringify({
       cacheHits: this.cacheHits,
       cacheMisses: this.cacheMisses,
       hitRate: this.cacheHits / (this.cacheHits + this.cacheMisses)
     }));
   }
   ```

2. **Monitor via Analytics:**
   - Cloudflare Dashboard → Workers → Analytics
   - Check request count to origin (should decrease)
   - Check DO CPU time (should be stable)
   - Check error rates (should be low)

3. **Monitor K8s metrics:**
   ```bash
   # Check API pod logs
   kubectl logs -n plue -l app=api --tail=100 -f | grep "Invalidation sent"

   # Check API CPU/memory
   kubectl top pod -n plue -l app=api
   ```

4. **Expected improvements:**
   - Cache hit rate: 85-95%
   - Origin requests: Reduced by 70-80%
   - Edge latency: < 50ms (previously 100-200ms)
   - No stale data windows

## Troubleshooting

### Common Issues

#### 1. Authentication Failures

**Symptom:** 401 Unauthorized responses from `/invalidate` endpoint.

**Diagnosis:**
```bash
# Check K8s secret
kubectl get secret edge-push-secret -n plue -o jsonpath='{.data.secret}' | base64 -d

# Check Worker secret
wrangler secret list --env production
```

**Solution:**
```bash
# Ensure both match
# Set K8s secret
kubectl create secret generic edge-push-secret -n plue \
  --from-literal=secret=YOUR_SECRET \
  --dry-run=client -o yaml | kubectl apply -f -

# Set Worker secret
wrangler secret put PUSH_SECRET --env production
# Enter: YOUR_SECRET
```

#### 2. Network Timeouts

**Symptom:** EdgeNotifier logs show "Failed to send invalidation" with timeout errors.

**Diagnosis:**
```bash
# Test from K8s pod
kubectl exec -it -n plue deployment/api -- sh
curl -v https://plue-edge.plue.dev/do/global/health
```

**Solutions:**

- Check DNS resolution: `nslookup plue-edge.plue.dev`
- Check firewall rules: K8s must allow egress to Cloudflare IPs
- Verify EDGE_URL is correct: `kubectl get deployment api -n plue -o yaml | grep EDGE_URL`
- Check Cloudflare status: https://www.cloudflarestatus.com/

#### 3. Stale Data Despite Push

**Symptom:** Edge still serves stale data even with push enabled.

**Diagnosis:**
```bash
# Check feature flag
wrangler secret list --env production | grep ENABLE_PUSH_INVALIDATION

# Check DO logs
wrangler tail --env production
```

**Solutions:**

1. **Verify flag is enabled:**
   ```bash
   wrangler secret put ENABLE_PUSH_INVALIDATION --env production
   # Enter: true
   ```

2. **Check invalidation is received:**
   - Look for "Updated merkle root" in DO logs
   - Verify timestamp is recent

3. **Manually invalidate:**
   ```bash
   curl -X POST https://plue-edge.plue.dev/do/repo:owner/repo/invalidate \
     -H "Authorization: Bearer YOUR_PUSH_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "git",
       "repoKey": "owner/repo",
       "merkleRoot": "new-hash-here",
       "timestamp": '$(date +%s)'
     }'
   ```

### How to Verify Invalidation is Working

**End-to-End Test:**

1. **Make a change:**
   ```bash
   cd /path/to/repo
   echo "test" >> README.md
   jj commit -m "test"
   ```

2. **Check K8s logs:**
   ```bash
   kubectl logs -n plue -l app=api --tail=50 | grep "Notified edge"
   # Should see: "Notified edge of merkle root update: owner/repo -> 4f2a8b9c..."
   ```

3. **Check Worker logs:**
   ```bash
   wrangler tail --env production
   # Should see: "Updated merkle root for owner/repo:main: 4f2a8b9c..."
   ```

4. **Verify cache invalidation:**
   ```bash
   # Request file content
   curl https://plue.dev/owner/repo/blob/main/README.md

   # Should see updated content immediately (no 5s delay)
   ```

5. **Check metrics:**
   ```bash
   curl https://plue-edge.plue.dev/do/repo:owner/repo/metrics
   # Should show cache miss for first request after change
   # Then cache hits for subsequent requests
   ```

### Rollback Procedure

If issues arise, roll back incrementally:

**Step 1: Disable push invalidation (keep infrastructure)**
```bash
wrangler secret put ENABLE_PUSH_INVALIDATION --env production
# Enter: false

wrangler deploy --env production
```

**Step 2: Stop K8s from sending notifications**
```bash
kubectl set env deployment/api -n plue EDGE_URL=""
```

**Step 3: Full rollback (remove infrastructure)**
```bash
# Revert terraform
cd terraform/kubernetes
git revert <commit-hash-that-added-push>
terraform apply

# Revert worker
cd edge
git revert <commit-hash-that-added-invalidation>
wrangler deploy --env production
```

## Performance Considerations

### Cache Hit Rates

Expected cache hit rates with push invalidation enabled:

- **SQL Data**: 90-95% (high read-to-write ratio)
- **Git Trees**: 85-90% (directories change less frequently)
- **Git Files**: 80-85% (subject to LRU eviction)

### Origin Load Reduction

With push invalidation:

- **Before**: Edge polls every 5 seconds → 720 requests/hour/DO
- **After**: Edge polls only on write → ~5-10 requests/hour/DO
- **Reduction**: 98-99% fewer origin requests

### Latency Improvements

Typical response times:

- **Cache Hit**: 10-30ms (SQLite query + validation)
- **Cache Miss**: 50-200ms (origin fetch + cache store)
- **Push Notification**: 5-15ms (K8s → Worker HTTP POST)

### Cost Implications

- **Before**: High CPU time from continuous polling
- **After**: CPU time only on actual changes
- **Savings**: ~80% reduction in DO CPU time

## Security Considerations

### Authentication

- **Shared Secret**: PUSH_SECRET authenticates K8s → Edge communication
- **Secret Rotation**: Change secrets periodically via `wrangler secret put`
- **Secret Storage**: Kubernetes secrets (encrypted at rest), Cloudflare secrets (encrypted)

### Attack Vectors

1. **Secret Leakage**
   - **Risk**: Attacker gains PUSH_SECRET, can invalidate cache arbitrarily
   - **Mitigation**: Rotate secrets regularly, limit access to K8s secrets

2. **Replay Attacks**
   - **Risk**: Attacker replays old invalidation messages
   - **Mitigation**: Timestamp validation (reject old messages)

3. **DoS via Invalidation**
   - **Risk**: Attacker floods invalidation endpoint
   - **Mitigation**: Rate limiting on `/invalidate`, Cloudflare DDoS protection

### Recommendations for Production

1. **Enable mTLS**: Use mutual TLS between K8s and Workers
2. **Implement rate limiting**: Limit invalidation requests per minute
3. **Add timestamp validation**: Reject messages older than 30 seconds
4. **Monitor invalidation patterns**: Alert on unusual invalidation rates
5. **Use Cloudflare Access**: Require authentication for `/invalidate` endpoint

## References

- [ElectricSQL Documentation](https://electric-sql.com/docs) - Real-time PostgreSQL sync
- [ElectricSQL ShapeStream API](https://electric-sql.com/docs/api/clients/typescript) - Client library reference
- [Cloudflare Durable Objects](https://developers.cloudflare.com/durable-objects/) - Edge storage & compute
- [Durable Objects SQL API](https://developers.cloudflare.com/durable-objects/api/storage-sql-api/) - SQLite in DOs
- [Jujutsu VCS](https://github.com/martinvonz/jj) - Version control system used by Plue
- [PostgreSQL Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html) - Powers ElectricSQL
- [Merkle Trees](https://en.wikipedia.org/wiki/Merkle_tree) - Cryptographic data validation
- [LRU Cache](https://en.wikipedia.org/wiki/Cache_replacement_policies#Least_recently_used_(LRU)) - Eviction strategy

## Related Documentation

- `/Users/williamcory/agent/docs/electric-setup.md` - ElectricSQL configuration guide
- `/Users/williamcory/agent/CLAUDE.md` - Plue project overview
- `/Users/williamcory/agent/docs/AUTHENTICATION.md` - Authentication system
- `/Users/williamcory/agent/docs/self-hosting.md` - Self-hosting guide
