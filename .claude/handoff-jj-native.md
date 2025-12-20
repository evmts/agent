# JJ-Native Transformation Handoff

## Mission

Transform Plue (a GitHub clone with AI agent capabilities) from git-centric to jj-native version control. Jujutsu (jj) is a modern VCS that treats the working copy as a commit, has stable change IDs that survive rebases, and stores conflicts as first-class citizens in commits rather than blocking operations.

## Context

### Why jj?

1. **Stable Change IDs** - Unlike git commit SHAs that change on rebase, jj change IDs are stable identifiers
2. **First-class Conflicts** - Conflicts are stored in commits, don't block rebases, can be resolved later
3. **Working Copy = Commit** - Every change to the working directory is automatically tracked
4. **Operation Log** - Every jj action is tracked and can be undone
5. **Better for AI Agents** - When an agent and user edit concurrently, conflicts don't break the workflow

### User Decisions Made

- **Full replacement**: Remove git concepts entirely, use only jj bookmarks and change IDs
- **Replace PRs with Changes**: No pull requests - changes are "landed" onto bookmarks with conflict detection
- **Parallel work**: Both repository UI and agent sessions should be jj-native

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        UI Layer (Astro)                         │
│  bookmarks.astro | changes/[bookmark].astro | landing/*.astro   │
│                      operations.astro                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       API Layer (Hono)                          │
│  /api/:user/:repo/bookmarks | /changes | /operations | /landing │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Core Layer                                 │
│           ui/lib/jj.ts (jj CLI wrapper)                        │
│           ui/lib/jj-types.ts (TypeScript types)                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Database (PostgreSQL)                        │
│  changes | bookmarks | jj_operations | conflicts | landing_queue│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    jj CLI (Jujutsu)                             │
│              Colocated with git for compatibility               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Concept Mapping (Git → jj)

| Git Concept | jj Equivalent | Notes |
|-------------|---------------|-------|
| Branch | Bookmark | Movable label, doesn't affect history |
| Commit SHA | Change ID | Stable 8-12 char ID, survives rebases |
| Pull Request | Landing Request | Conflict-aware landing workflow |
| Merge Conflict | Conflict State | Stored in commit, not blocking |
| `git log` | `jj log` | Shows change IDs |
| `git merge` | `jj squash` / land | Conflicts recorded, not blocking |
| Working directory | `@` (working copy commit) | Always a real commit |

---

## Completed Work

### Wave 1: Foundation ✅

**Database Migration**: `db/migrate-jj-native.sql`
- `changes` - Change metadata (change_id, commit_id, description, author, conflicts)
- `bookmarks` - Bookmark labels (name, target_change_id, is_default)
- `jj_operations` - Operation log for undo/redo
- `conflicts` - First-class conflict tracking per file
- `landing_queue` - Landing requests (replaces pull_requests)
- `protected_bookmarks` - Protection rules (replaces protected_branches)
- `landing_reviews` - Reviews on landing requests

**Type Definitions**: `ui/lib/jj-types.ts`
- `Change`, `ChangeDetail`, `ChangeFile`
- `Bookmark`, `ProtectedBookmark`
- `Conflict`, `ConflictDetail`
- `Operation`, `OperationType`
- `LandingRequest`, `LandingStatus`, `LandingReview`
- `ChangeComparison`, `FileDiff`

**Core Library**: `ui/lib/jj.ts`
- Repository: `initRepo`, `deleteRepo`, `repoExists`, `isJjRepo`
- Bookmarks: `listBookmarks`, `createBookmark`, `deleteBookmark`, `moveBookmark`
- Changes: `listChanges`, `getChange`, `getCurrentChange`
- Tree/Files: `getTree`, `getFileContent`
- Diffs: `compareChanges`, `getDiff`
- Conflicts: `getConflicts`, `hasConflicts`
- Operations: `getOperationLog`, `undoOperation`, `restoreOperation`
- Landing: `checkLandable`, `landChange`

### Wave 2: API Layer ✅

**Bookmarks API**: `server/routes/bookmarks.ts`
```
GET    /:user/:repo/bookmarks           - List bookmarks
GET    /:user/:repo/bookmarks/:name     - Get single bookmark
POST   /:user/:repo/bookmarks           - Create bookmark
DELETE /:user/:repo/bookmarks/:name     - Delete bookmark
PATCH  /:user/:repo/bookmarks/:name     - Move bookmark to change
POST   /:user/:repo/bookmarks/:name/set-default
```

**Changes API**: `server/routes/changes.ts`
```
GET  /:user/:repo/changes                    - List changes
GET  /:user/:repo/changes/:changeId          - Get change details
GET  /:user/:repo/changes/:changeId/files    - List files in change
GET  /:user/:repo/changes/:changeId/file/*   - Get file content
GET  /:user/:repo/changes/:changeId/diff     - Get change diff
GET  /:user/:repo/changes/:from/compare/:to  - Compare two changes
GET  /:user/:repo/changes/:changeId/conflicts
POST /:user/:repo/changes/:changeId/conflicts/:file/resolve
```

**Operations API**: `server/routes/operations.ts`
```
GET  /:user/:repo/operations              - List operations
GET  /:user/:repo/operations/:id          - Get operation
POST /:user/:repo/operations/undo         - Undo last operation
POST /:user/:repo/operations/:id/restore  - Restore to operation
```

**Landing API**: `server/routes/landing.ts`
```
GET    /:user/:repo/landing              - List landing queue
GET    /:user/:repo/landing/:id          - Get landing request
POST   /:user/:repo/landing              - Create landing request
POST   /:user/:repo/landing/:id/check    - Refresh conflict check
POST   /:user/:repo/landing/:id/land     - Execute landing
DELETE /:user/:repo/landing/:id          - Cancel request
POST   /:user/:repo/landing/:id/reviews  - Add review
GET    /:user/:repo/landing/:id/files    - Get files to land
```

**Routes Registered**: `server/index.ts` (lines 14-18, 82-86)

### Wave 3-5: UI Pages ✅

| Page | Path | Purpose |
|------|------|---------|
| Bookmarks | `ui/pages/[user]/[repo]/bookmarks.astro` | List/manage bookmarks |
| Change History | `ui/pages/[user]/[repo]/changes/[bookmark].astro` | View changes on a bookmark |
| Landing Queue | `ui/pages/[user]/[repo]/landing/index.astro` | List landing requests |
| Landing Detail | `ui/pages/[user]/[repo]/landing/[id].astro` | Landing request with actions |
| Operations | `ui/pages/[user]/[repo]/operations.astro` | Operation log with undo |

---

## Remaining Work

### Wave 6: Session Integration (Priority: High)

The agent system already uses jj via `snapshot/src/snapshot.ts` and `core/snapshots.ts`. These need to be enhanced to expose jj concepts to the UI.

**Tasks:**

1. **Enhance `server/routes/sessions.ts`** with new endpoints:
   ```
   GET  /sessions/:id/changes      - List changes in session
   GET  /sessions/:id/conflicts    - Get active conflicts
   GET  /sessions/:id/operations   - Get operation history
   POST /sessions/:id/operations/:opId/undo
   ```

2. **Update `core/snapshots.ts`** to expose:
   - `getConflictState(sessionId, changeId)`
   - `getBookmarks(sessionId)`
   - `getOperations(sessionId)`
   - Change IDs in snapshot history (already stored, need to expose)

3. **Update session UI** (if exists) to show:
   - Change IDs instead of opaque snapshot hashes
   - Conflict warnings when user edits conflict with agent
   - Operation history with undo buttons

**Key Files:**
- `server/routes/sessions.ts` - Has /diff, /revert, /undo but needs jj-native endpoints
- `core/snapshots.ts` - Wrapper around snapshot module
- `snapshot/src/snapshot.ts` - Low-level jj operations (already comprehensive)
- `ai/wrapper.ts` - Agent wrapper that captures snapshots per turn

### Wave 7: Cleanup (Priority: Medium)

Remove legacy git-centric code after migration is complete.

**Tasks:**

1. **Remove old routes:**
   - `server/routes/branches.ts` → replaced by `bookmarks.ts`
   - `server/routes/protected-branches.ts` → replaced by protected_bookmarks in DB
   - `server/routes/pulls.ts` → replaced by `landing.ts`

2. **Remove old UI pages:**
   - `ui/pages/[user]/[repo]/branches.astro`
   - `ui/pages/[user]/[repo]/commits/[branch].astro`
   - `ui/pages/[user]/[repo]/pulls/*`
   - `ui/pages/[user]/[repo]/settings/branches.astro`

3. **Remove old library:**
   - `ui/lib/git.ts` → replaced by `jj.ts`

4. **Update remaining references:**
   - Search for `default_branch` and update to `default_bookmark`
   - Search for imports of `git.ts` and update to `jj.ts`
   - Update navigation links in remaining pages

5. **Database cleanup:**
   - After data migration, drop: `branches`, `protected_branches`, `pull_requests`, `reviews`, `review_comments`, `renamed_branches`

### Wave 8: Polish (Priority: Low)

1. **Update tree navigation** - `tree/[branch]` should become `tree/[bookmark]` or `tree/[changeId]`
2. **Add conflicts page** - `ui/pages/[user]/[repo]/conflicts.astro` to show all unresolved conflicts
3. **Add change detail page** - `ui/pages/[user]/[repo]/changes/[bookmark]/[changeId].astro`
4. **ElectricSQL shapes** - Add real-time sync for new tables in `server/electric.ts`

---

## Key Patterns & Conventions

### jj CLI Wrapper Pattern

All jj operations go through `ui/lib/jj.ts` which wraps CLI calls:

```typescript
async function runJj(args: string[], cwd: string): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  // Executes: jj <args> in <cwd>
}
```

Templates are used to parse jj output:
```typescript
const template = 'change_id ++ "|" ++ commit_id ++ "|" ++ description ++ "\\n"';
await runJj(['log', '-T', template], repoPath);
```

### Change ID Display

Change IDs are displayed with consistent styling:
```html
<span class="change-id">{changeId.substring(0, 8)}</span>
```

CSS:
```css
.change-id {
  font-family: var(--font-mono);
  background: #e5e7eb;
  padding: 0.125rem 0.5rem;
  border-radius: 0.25rem;
  color: #7c3aed;  /* Purple for jj */
  font-weight: 500;
}
```

### jj Badge

Pages include a jj info banner:
```html
<div class="jj-info">
  <span class="jj-badge">jj</span>
  Explanation of jj concept...
</div>
```

### API Response Pattern

```typescript
// Success
return c.json({ bookmark }, 201);

// Error
return c.json({ error: "Message" }, 400);

// List with pagination
return c.json({ items, total, page, limit });
```

---

## Potential Issues & Gotchas

1. **jj not installed** - The system falls back gracefully when jj CLI is not available, but features won't work. Check with `which jj`.

2. **Colocated mode** - Repos are initialized with `jj init --colocate` to maintain `.git` for compatibility. Both `.jj` and `.git` directories exist.

3. **Bare repositories** - Plue uses bare git repos in `repos/` directory. jj commands need a working copy, so operations clone to temp directories.

4. **Change ID format** - jj change IDs are typically 8-12 lowercase hex characters. They're different from commit IDs.

5. **Operation log size** - jj's operation log can grow large. Consider pagination and cleanup.

6. **Conflict markers** - jj stores logical conflicts, not `<<<<` markers. The conflict resolution UI should show both versions cleanly.

---

## Testing the Implementation

1. **Run the migration:**
   ```bash
   psql $DATABASE_URL < db/migrate-jj-native.sql
   ```

2. **Initialize a test repo with jj:**
   ```bash
   cd repos/testuser
   mkdir testrepo && cd testrepo
   jj init --colocate
   echo "# Test" > README.md
   jj describe -m "Initial commit"
   jj bookmark create main
   ```

3. **Test the API:**
   ```bash
   curl http://localhost:4000/api/testuser/testrepo/bookmarks
   curl http://localhost:4000/api/testuser/testrepo/changes
   curl http://localhost:4000/api/testuser/testrepo/operations
   ```

4. **Test the UI:**
   - Navigate to `http://localhost:5173/testuser/testrepo/bookmarks`
   - Create a bookmark, view changes, create a landing request

---

## File Reference

### New Files Created

```
db/migrate-jj-native.sql          # Database schema
ui/lib/jj-types.ts                # TypeScript types
ui/lib/jj.ts                      # Core jj operations
server/routes/bookmarks.ts        # Bookmarks API
server/routes/changes.ts          # Changes API
server/routes/operations.ts       # Operations API
server/routes/landing.ts          # Landing queue API
ui/pages/[user]/[repo]/bookmarks.astro
ui/pages/[user]/[repo]/changes/[bookmark].astro
ui/pages/[user]/[repo]/landing/index.astro
ui/pages/[user]/[repo]/landing/[id].astro
ui/pages/[user]/[repo]/operations.astro
```

### Modified Files

```
server/index.ts                   # Added route imports and mounts (lines 14-18, 82-86)
```

### Existing Files to Reference

```
snapshot/src/snapshot.ts          # Low-level jj operations (already comprehensive)
core/snapshots.ts                 # Session snapshot management
ai/wrapper.ts                     # Agent wrapper with snapshot capture
server/routes/sessions.ts         # Session routes (needs enhancement)
ui/lib/git.ts                     # Old git operations (reference for patterns)
ui/pages/[user]/[repo]/branches.astro  # Old branches page (reference for patterns)
```

---

## Success Criteria

The transformation is complete when:

1. ✅ Users can manage bookmarks instead of branches
2. ✅ Change history shows stable change IDs
3. ✅ Landing queue replaces pull requests with conflict awareness
4. ✅ Operation log enables undo/redo of all actions
5. ✅ Agent sessions expose jj concepts (changes, conflicts, operations)
6. ✅ Old git-centric code is removed
7. ✅ All navigation uses bookmarks/changes instead of branches/commits

---

## Questions for Continuation

Before proceeding, consider clarifying:

1. Should the old git endpoints remain available during a transition period, or remove immediately?
2. For session integration, should conflicts block agent execution or just be surfaced in the UI?
3. Is there an existing session UI that needs updating, or is it terminal-only?
4. Should we add ElectricSQL real-time sync for the new tables?
