# Version Control (JJ)

## 11. Version Control (JJ)

JJ (Jujutsu) is a **bundled** dependency. The `jj` binary ships inside the `.app` bundle — users never need to install it. The agent orchestration, snapshot system, and version control UI all depend on jj.

### 11.1 JJService

CLI wrapper that spawns the bundled `jj` binary as a child process for each operation. The binary path is resolved via `Bundle.main.path(forAuxiliaryExecutable: "jj")`. All methods are `async` and run the process on a background thread via `Task.detached`.

**Operations:**
- `status()` → `JJStatus` (modified files, conflicts)
- `log(limit:)` → `[JJChange]`
- `diff(changeId:)` → `String` (unified diff)
- `commit(description:)` → success/failure
- `bookmarkList()` → `[JJBookmark]`
- `opLog(limit:)` → `[JJOperation]`
- `snapshot(description:)` → `String` (change ID)
- `undo()` → success/failure
- `detectVCS()` → `VCSType` (.jjColocated, .jjNative, .gitOnly, .none)
- `initRepo()` → initializes jj in a directory (colocated mode if .git exists)

**Output parsing:** Uses jj's `--template` flag for structured output. Parses JSON arrays from stdout.

**Threading:** `@MainActor` class. Blocking `Process` operations run in `Task.detached` with captured values. Results returned to the main actor.

### 11.2 JJSnapshotStore

SQLite via GRDB at `<workspace>/.jj/smithers/snapshots.db`.

- `DatabaseQueue` for thread-safe access.
- Migrations via `DatabaseMigrator`.
- Async wrapper: `withCheckedThrowingContinuation` + `DispatchQueue.global(.utility)`.
- Records: `Snapshot` with changeId, commitId, workspacePath, description, triggerType (aiChange, userSave, manualCommit), chatSessionId, timestamp.

### 11.3 Integration with chat

- Auto-snapshot after each AI turn completes (debounced 2s).
- Snapshot on manual file save (if preference enabled).
- Chat message hover action "Revert" calls `jjService.undo()` to restore to that snapshot.
- Diff preview cards in chat show the unified diff from the AI's changes.

### 11.4 AgentOrchestrator

Manages parallel AI agents, each in a separate jj workspace.

- `createAgent(task:)` — creates a new jj workspace branch, starts a CodexService instance.
- Each agent runs independently, applying changes to its own branch.
- When an agent completes, its changes are merged into the main workspace via `jj` operations. For MVP, this is a simple merge — if conflicts exist, flag for manual resolution.
- **Merge queue is post-MVP.** The full merge queue UI (prioritization, test gates, ordered merging) is deferred. MVP just merges completed agent work directly.

### 11.5 CommitStyleDetector

Reads the last 30 commits from `jjService.log(limit: 30)`. Analyzes descriptions to detect patterns:
- Conventional commits (`type: description`)
- Emoji prefixes
- Freeform

Returns the detected style so AI-generated commit messages match the team's conventions.
