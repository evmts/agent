---
name: git
description: Plue Git operations using jj (Jujutsu) via Rust FFI. Use when working on repository operations, SSH server, or understanding how Git data flows through the system.
---

# Plue Git System

Plue uses [Jujutsu (jj)](https://github.com/martinvonz/jj) as the backend VCS, accessed via Rust FFI from the Zig server.

## Why Jujutsu?

- **Change-centric** - Every working copy state is a commit
- **Stable Change IDs** - IDs persist across rebases (unlike Git SHAs)
- **First-class Conflicts** - Conflicts are recorded in commits, not blocking
- **Git Compatible** - Can push/pull from Git remotes

## Architecture

```
Git Client (push/pull) ──► SSH Server ──► jj-lib (Rust FFI) ──► Git repo on disk
                                              │
UI (tree/blob view) ──► Zig API ─────────────┘
```

## jj-lib FFI

Located in `server/jj-ffi/` (Rust library):

```rust
// Key FFI functions exposed to Zig
pub extern "C" fn jj_open_repo(path: *const c_char) -> *mut JjRepo
pub extern "C" fn jj_get_tree(repo: *mut JjRepo, commit_id: *const c_char) -> *mut JjTree
pub extern "C" fn jj_get_blob(repo: *mut JjRepo, path: *const c_char) -> *mut JjBlob
pub extern "C" fn jj_resolve_ref(repo: *mut JjRepo, ref_name: *const c_char) -> *const c_char
pub extern "C" fn jj_list_changes(repo: *mut JjRepo) -> *mut JjChangeList
```

## SSH Server

Git operations happen over SSH:

```zig
// server/ssh/server.zig
// Listens on SSH_PORT (default 2222)

// Commands supported:
// - git-receive-pack (push)
// - git-upload-pack (fetch/clone/pull)

// Auth via public key lookup in ssh_keys table
```

### SSH Flow

```
1. Client: ssh git@plue.dev:owner/repo.git
2. Server: Authenticate via public key
3. Server: Check repo access permissions
4. Server: Execute git-receive-pack or git-upload-pack
5. Server: On push completion, trigger webhooks/workflows
```

## API Endpoints

### Blob/Tree Access

```
GET /api/:owner/:repo/tree/:commit_sha/:path   # Directory listing
GET /api/:owner/:repo/blob/:commit_sha/:path   # File content
GET /api/:owner/:repo/refs/:ref                # Resolve ref to commit
```

### Changes (jj-specific)

```
GET /api/:owner/:repo/changes                  # List all changes
GET /api/:owner/:repo/changes/:id              # Get change details
GET /api/:owner/:repo/changes/:id/files        # Files in change
GET /api/:owner/:repo/changes/:id/diff         # Diff for change
```

### Bookmarks (branches)

```
GET /api/:owner/:repo/bookmarks                # List bookmarks
POST /api/:owner/:repo/bookmarks               # Create bookmark
DELETE /api/:owner/:repo/bookmarks/:name       # Delete bookmark
```

### Operations (jj operation log)

```
GET /api/:owner/:repo/operations               # Operation history
POST /api/:owner/:repo/operations/:id/restore  # Restore to operation
```

## Key Files

| File | Purpose |
|------|---------|
| `server/ssh/server.zig` | SSH server implementation |
| `server/routes/changes.zig` | Change/commit API routes |
| `server/routes/repositories.zig` | Repository CRUD |
| `jj/` | Jujutsu submodule |
| `ui/lib/git.ts` | UI git utilities |

## Caching Strategy

Git objects are content-addressable, enabling aggressive caching:

```
Ref (master) ──► Commit SHA ──► Tree SHA ──► Blob SHA
     │                │             │            │
     │                │             │            │
  5s cache       Forever       Forever      Forever
  (mutable)     (immutable)  (immutable)  (immutable)
```

See the `caching` skill for details.

## Repository Storage

```
/var/plue/repos/
├── user1/
│   └── repo1.git/          # Bare git repository
│       ├── .jj/            # Jujutsu metadata
│       └── ...             # Git objects
├── user2/
│   └── ...
```

## Hooks

Git hooks trigger on events:

```zig
// server/services/repo_watcher.zig
// Watches for:
// - post-receive: New commits pushed
// - update: Branch updates

// Triggers:
// - Workflow execution
// - Cache invalidation
// - WebSocket notifications
```

## jj Concepts

| Git | jj | Description |
|-----|-----|-------------|
| Commit | Change | A snapshot of the working copy |
| Branch | Bookmark | A named pointer to a change |
| SHA | Change ID | Identifier for a change (stable across rebases) |
| N/A | Operation | An entry in the operation log |

## Common Operations

```bash
# In jj-lib (via FFI)
jj_squash()        # Squash changes
jj_rebase()        # Rebase changes
jj_split()         # Split a change
jj_abandon()       # Abandon a change
jj_backout()       # Revert a change
```
