# Repository Watcher Service

The Repository Watcher is a background service that monitors jj repositories for changes and automatically syncs data to the PostgreSQL database.

## Architecture

### Components

1. **RepoWatcher** (`repo_watcher.zig`): Main service that manages file system watching
2. **Background Thread**: Polls repositories for changes using file system metadata
3. **JJ-FFI Integration**: Uses Rust FFI to interact with jj-lib for reading repository data
4. **Database Sync**: Updates PostgreSQL with changes, bookmarks, operations, and conflicts

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     Repository Watcher                       │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Background Thread (Polling Loop)                     │   │
│  │  • Check .jj/op_heads modification time               │   │
│  │  • Detect changes via file metadata                   │   │
│  │  • Debounce changes (300ms default)                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                           │                                   │
│                           ▼                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Sync Coordinator                                     │   │
│  │  • Spawn 4 parallel sync threads                      │   │
│  │  • Coordinate database updates                        │   │
│  └──────────────────────────────────────────────────────┘   │
│           │            │            │            │           │
│           ▼            ▼            ▼            ▼           │
│      ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐        │
│      │Changes │  │Bookmarks│  │Operations│  │Conflicts│       │
│      │  Sync  │  │  Sync   │  │  Sync    │  │  Sync   │       │
│      └────┬───┘  └────┬────┘  └────┬─────┘  └────┬────┘       │
│           │           │            │             │            │
│           └───────────┴────────────┴─────────────┘            │
│                           │                                   │
└───────────────────────────┼───────────────────────────────────┘
                            ▼
                   ┌────────────────┐
                   │   PostgreSQL   │
                   │    Database    │
                   └────────────────┘
```

## Features

### Automatic Monitoring

- Monitors all repositories in the `repos/` directory
- Polls file system for changes (default: 100ms interval)
- Detects changes via `.jj/op_heads` modification time
- Debounces rapid changes (default: 300ms)

### Parallel Syncing

When a change is detected, the service spawns 4 parallel threads to sync:

1. **Changes**: Commits with metadata (author, timestamp, description)
2. **Bookmarks**: Branch pointers (jj bookmarks ≈ git branches)
3. **Operations**: Operation log entries
4. **Conflicts**: Merge conflict tracking

### JJ-FFI Integration

Uses the Rust FFI library (`jj-ffi`) to:
- Open jj workspaces
- List changes and bookmarks
- Get commit metadata
- Track operations

## Configuration

Environment variables:

```bash
# Enable/disable the watcher service
WATCHER_ENABLED=true

# Polling interval (milliseconds)
WATCHER_POLL_INTERVAL=100

# Debounce delay (milliseconds)
WATCHER_DEBOUNCE=300

# Base path for repositories
REPOS_BASE_PATH=repos
```

## API Endpoints

### Admin Endpoints

Require authentication with admin privileges.

#### GET /api/watcher/status
Get watcher service status.

**Response:**
```json
{
  "running": true,
  "watchedRepos": 5
}
```

#### GET /api/watcher/repos
List all watched repositories.

**Response:**
```json
{
  "repos": [
    {
      "user": "alice",
      "repo": "my-project",
      "repoId": 1
    }
  ]
}
```

#### POST /api/watcher/watch/:user/:repo
Add a repository to the watch list.

**Response:**
```json
{
  "message": "Repository added to watch list",
  "repo": "alice/my-project"
}
```

#### DELETE /api/watcher/watch/:user/:repo
Remove a repository from the watch list.

**Response:**
```json
{
  "message": "Repository removed from watch list",
  "repo": "alice/my-project"
}
```

### User Endpoints

#### POST /api/watcher/sync/:user/:repo
Manually trigger sync for a repository.

Requires authentication and permission (repo owner or admin).

**Response:**
```json
{
  "message": "Sync triggered for repository",
  "repo": "alice/my-project"
}
```

## Database Schema

The watcher syncs data to these tables:

### changes
```sql
CREATE TABLE changes (
  change_id TEXT PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id),
  commit_id TEXT,
  description TEXT,
  author_name TEXT,
  author_email TEXT,
  timestamp TIMESTAMP,
  is_empty BOOLEAN,
  has_conflicts BOOLEAN
);
```

### bookmarks
```sql
CREATE TABLE bookmarks (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id),
  name TEXT,
  target_change_id TEXT,
  is_default BOOLEAN,
  UNIQUE(repository_id, name)
);
```

### jj_operations
```sql
CREATE TABLE jj_operations (
  operation_id TEXT PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id),
  operation_type TEXT,
  description TEXT,
  timestamp TIMESTAMP,
  is_undone BOOLEAN
);
```

### conflicts
```sql
CREATE TABLE conflicts (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id),
  change_id TEXT,
  file_path TEXT,
  resolved BOOLEAN,
  UNIQUE(change_id, file_path)
);
```

## Usage

### Starting the Service

The watcher starts automatically when the server starts (if `WATCHER_ENABLED=true`):

```bash
WATCHER_ENABLED=true zig build run
```

### Manual Sync

Trigger a sync via the API:

```bash
# As repo owner or admin
curl -X POST http://localhost:4000/api/watcher/sync/alice/my-project \
  -H "Authorization: Bearer <token>"
```

### Monitoring

Check watcher status:

```bash
# As admin
curl http://localhost:4000/api/watcher/status \
  -H "Authorization: Bearer <admin-token>"
```

## Performance

### Efficiency

- **Polling**: Efficient file metadata checks (no repository opens unless changed)
- **Debouncing**: Prevents excessive syncs during rapid changes
- **Parallel Sync**: 4 threads sync different data types simultaneously
- **Incremental**: Only syncs changed data (upserts with conflict resolution)

### Resource Usage

- Minimal CPU usage when idle (file stat checks only)
- Spawns threads only when changes detected
- Database connections from pool (reused)

## Development

### Adding New Sync Types

To add a new data type to sync:

1. Add a new `SyncType` variant in `repo_watcher.zig`
2. Implement sync function (e.g., `syncNewType`)
3. Update `syncThread` to handle the new type
4. Update thread count in `syncToDatabase`

### Testing

```zig
// Run unit tests
zig build test

// Integration test (requires jj-ffi and database)
WATCHER_ENABLED=true zig build test --summary all
```

## Troubleshooting

### Watcher Not Starting

Check logs:
```
Repository watcher started
Started watching 5 repositories
Watcher thread started
```

If not present:
- Verify `WATCHER_ENABLED=true`
- Check database connection
- Ensure jj-ffi library is built

### Changes Not Syncing

1. Check if repository is in watch list:
   ```bash
   curl http://localhost:4000/api/watcher/repos \
     -H "Authorization: Bearer <admin-token>"
   ```

2. Trigger manual sync:
   ```bash
   curl -X POST http://localhost:4000/api/watcher/sync/:user/:repo \
     -H "Authorization: Bearer <token>"
   ```

3. Check logs for errors:
   ```
   Error checking repo alice/my-project: WorkspaceOpenFailed
   ```

### Performance Issues

If sync is slow:
- Reduce `max_changes` in config (default: 1000)
- Increase `debounce_ms` to reduce sync frequency
- Check database connection pool size
- Monitor database query performance

## References

- [jj-lib Documentation](https://github.com/martinvonz/jj)
- [jj-ffi Implementation](../jj-ffi/)
- [TypeScript Implementation](../../../server/lib/repo-watcher.ts)
