# Version Control (JJ)

## 11. JJ

**Bundled** — `jj` binary ships in `.app` bundle, users never install. Agent orchestration, snapshots, VCS UI all depend on jj.

### 11.1 JJService

Spawns bundled `jj` as child process per op. Path: `Bundle.main.path(forAuxiliaryExecutable: "jj")`. All `async`, `Task.detached` bg thread.

**Ops:** `status()` → `JJStatus` (mods, conflicts); `log(limit:)` → `[JJChange]`; `diff(changeId:)` → unified diff `String`; `commit(description:)` → success/fail; `bookmarkList()` → `[JJBookmark]`; `opLog(limit:)` → `[JJOperation]`; `snapshot(description:)` → change ID `String`; `undo()` → success/fail; `detectVCS()` → `VCSType` (.jjColocated, .jjNative, .gitOnly, .none); `initRepo()` → init jj (colocated if .git exists).

**Parsing:** jj `--template` flag → JSON arrays from stdout.

**Threading:** `@MainActor`. `Process` ops in `Task.detached` with captures, results → main.

### 11.2 JJSnapshotStore

SQLite via GRDB `<workspace>/.jj/smithers/snapshots.db`.

`DatabaseQueue` (thread-safe), `DatabaseMigrator` (migrations), async `withCheckedThrowingContinuation` + `DispatchQueue.global(.utility)`. Records: `Snapshot` (changeId, commitId, workspacePath, description, triggerType: aiChange/userSave/manualCommit, chatSessionId, timestamp).

### 11.3 Chat integration

Auto-snapshot post-AI turn (2s debounce). Snapshot on manual save (if pref enabled). Hover "Revert" → `jjService.undo()`. Diff cards show unified diff.

### 11.4 AgentOrchestrator

Parallel agents, separate jj workspaces. `createAgent(task:)` → new jj branch, CodexService instance. Independent runs, own branch. On complete → merge to main (MVP: simple merge, conflicts flagged). **Merge queue post-MVP** (prioritization, gates, ordering deferred).

### 11.5 CommitStyleDetector

Reads last 30 `jjService.log(limit: 30)`. Detects: conventional (`type: description`), emoji, freeform. Returns style → AI commits match conventions.
