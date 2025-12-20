# Changes API Implementation

This document describes the repository-level change viewing operations implemented in the Zig server.

## Overview

The Changes API provides endpoints for viewing files, content, and conflicts at specific jj changes. These operations are implemented in `src/routes/changes.zig` and use the jj-ffi C bindings when available, with fallback to jj CLI commands.

## Endpoints

### 1. List Files at Change

**GET** `/:user/:repo/changes/:changeId/files`

Lists all files present in the repository at a specific change.

**Query Parameters:**
- `path` (optional) - Filter files by path prefix

**Response:**
```json
{
  "files": ["file1.txt", "dir/file2.md"],
  "path": "",
  "total": 2
}
```

**Implementation:**
- Uses `jj_list_files()` from jj-ffi when available
- Falls back to `jj file list -r <changeId>` CLI command
- Filters files by path prefix if specified

### 2. Get File Content at Change

**GET** `/:user/:repo/changes/:changeId/file/*`

Retrieves the content of a specific file at a given change.

**Path Parameters:**
- Wildcard path after `/file/` is the file path

**Response:**
```json
{
  "content": "file contents here",
  "path": "path/to/file.txt"
}
```

**Implementation:**
- Uses `jj_get_file_content()` from jj-ffi when available
- Falls back to `jj file show -r <changeId> <path>` CLI command
- Returns 404 if file doesn't exist at that change

### 3. Compare Changes

**GET** `/:user/:repo/changes/:fromChangeId/compare/:toChangeId`

Shows the diff between two changes.

**Response:**
```json
{
  "comparison": {
    "from": "abc123",
    "to": "def456",
    "diff": "diff output here"
  }
}
```

**Implementation:**
- Uses `jj diff --from <from> --to <to> --stat` CLI command
- Returns a textual diff representation

### 4. Get Conflicts

**GET** `/:user/:repo/changes/:changeId/conflicts`

Lists all conflicts present in a change and their resolution status.

**Response:**
```json
{
  "conflicts": [
    {
      "filePath": "conflicted.txt",
      "resolved": false
    },
    {
      "filePath": "resolved.txt",
      "resolved": true,
      "resolutionMethod": "manual",
      "resolvedBy": 123
    }
  ]
}
```

**Implementation:**
- Uses `jj resolve --list -r <changeId>` CLI command
- Augments jj output with resolution status from database
- Checks `conflicts` table for resolved flag and metadata

### 5. Resolve Conflict

**POST** `/:user/:repo/changes/:changeId/conflicts/:filePath/resolve`

Marks a conflict as resolved in the database.

**Request Body:**
```json
{
  "method": "manual"
}
```

**Response:**
```json
{
  "success": true
}
```

**Implementation:**
- Requires authentication
- Records resolution in `conflicts` table
- Tracks who resolved it and the method used

## Database Schema

A new `conflicts` table was added to track conflict resolution status:

```sql
CREATE TABLE IF NOT EXISTS conflicts (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  change_id TEXT NOT NULL,
  file_path TEXT NOT NULL,
  conflict_type TEXT NOT NULL DEFAULT 'content',
  resolved BOOLEAN DEFAULT FALSE,
  resolved_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  resolution_method TEXT,
  resolved_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(change_id, file_path)
);
```

## Route Registration

Routes are registered in `src/routes.zig`:

```zig
const changes = @import("routes/changes.zig");

// In configure() function:
router.get("/api/:user/:repo/changes/:changeId/files", changes.getFilesAtChange, .{});
router.get("/api/:user/:repo/changes/:changeId/file/*", changes.getFileAtChange, .{});
router.get("/api/:user/:repo/changes/:fromChangeId/compare/:toChangeId", changes.compareChanges, .{});
router.get("/api/:user/:repo/changes/:changeId/conflicts", changes.getConflicts, .{});
router.post("/api/:user/:repo/changes/:changeId/conflicts/:filePath/resolve", changes.resolveConflict, .{});
```

## Architecture

The implementation follows these patterns:

1. **Dual Strategy**: Uses jj-ffi C bindings when the repository is a jj workspace, falls back to CLI for git-only repos
2. **Error Handling**: Returns appropriate HTTP status codes (404 for not found, 500 for server errors)
3. **JSON Escaping**: Properly escapes file content and paths for JSON responses
4. **Database Integration**: Augments jj data with database state for conflict resolution tracking
5. **Authentication**: Conflict resolution requires authentication to track who resolved conflicts

## Testing

To test these endpoints:

1. Ensure jj-ffi is built: `cd jj-ffi && cargo build --release`
2. Build the server: `zig build`
3. Run the server: `./zig-out/bin/server-zig`
4. Test endpoints with curl or a REST client

Example:
```bash
# List files at a change
curl http://localhost:3000/api/user/repo/changes/abc123/files

# Get file content
curl http://localhost:3000/api/user/repo/changes/abc123/file/README.md

# Compare changes
curl http://localhost:3000/api/user/repo/changes/abc123/compare/def456

# Get conflicts
curl http://localhost:3000/api/user/repo/changes/abc123/conflicts

# Resolve a conflict (requires auth)
curl -X POST http://localhost:3000/api/user/repo/changes/abc123/conflicts/file.txt/resolve \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"method":"manual"}'
```

## Future Enhancements

Potential improvements:

1. Add pagination for large file lists
2. Support for binary file detection and proper handling
3. Richer diff format options (unified, side-by-side)
4. Real-time conflict resolution through actual jj commands
5. Conflict markers extraction and presentation
6. Support for three-way merge views
