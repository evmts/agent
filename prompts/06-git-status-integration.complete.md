# Git Status Integration

<metadata>
  <priority>medium</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/internal/components/sidebar/, tui/internal/app/</affects>
</metadata>

## Objective

Provide comprehensive git status information in the TUI sidebar, showing staged files, unstaged changes, and enabling quick git actions.

<context>
Claude Code deeply integrates with git to show:
- Current branch and status
- Staged and unstaged file changes
- Untracked files
- Commit history
- Quick actions (stage, unstage, commit, diff)

This helps users understand what changes the agent has made and manage their git workflow without leaving the TUI.
</context>

## Requirements

<functional-requirements>
1. Add "Git" tab to sidebar showing:
   - Current branch name with status (ahead/behind)
   - Staged files (green, ready to commit)
   - Unstaged changes (yellow, modified)
   - Untracked files (gray, new files)
2. Show file change indicators: `+` added, `M` modified, `D` deleted, `R` renamed
3. Quick actions:
   - Stage/unstage individual files
   - Stage all changes
   - View diff for selected file
   - Create commit with message
4. Refresh on file system changes
5. Show "Not a git repository" when outside git repos
</functional-requirements>

<technical-requirements>
1. Create `GitTab` component for sidebar
2. Execute git commands and parse output:
   - `git status --porcelain=v1`
   - `git branch -vv`
   - `git diff --stat`
3. Implement file selection and actions
4. Add keybindings for git operations
5. Handle git errors gracefully
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/sidebar/git.go` - New git status component
- `tui/internal/components/sidebar/model.go` - Add Git tab
- `tui/internal/git/status.go` - Git command execution
- `tui/internal/git/parser.go` - Parse git output
- `tui/internal/app/commands_git.go` - Git action handlers
</files-to-modify>

<git-status-parsing>
```go
type GitStatus struct {
    Branch       string
    Ahead        int
    Behind       int
    Staged       []FileChange
    Unstaged     []FileChange
    Untracked    []string
    IsRepo       bool
    HasConflicts bool
}

type FileChange struct {
    Path       string
    Status     ChangeStatus  // Added, Modified, Deleted, Renamed
    OldPath    string        // For renames
    Insertions int
    Deletions  int
}

func ParseGitStatus(output string) GitStatus {
    // Parse `git status --porcelain=v1` output
    // Format: XY PATH or XY ORIG -> PATH for renames
    // X = staged status, Y = unstaged status
    // Example: "M  file.txt" = staged modification
    //          " M file.txt" = unstaged modification
    //          "?? file.txt" = untracked
}
```
</git-status-parsing>

<example-ui>
```
┌─ Git ─────────────────────────────┐
│  main ↑2 ↓1                      │
│ ──────────────────────────────── │
│                                   │
│ Staged (3)                        │
│   + src/auth/login.ts             │
│   M src/api/users.ts              │
│   D old-config.json               │
│                                   │
│ Changes (2)                       │
│   M README.md                     │
│   M package.json                  │
│                                   │
│ Untracked (1)                     │
│   ? src/utils/helpers.ts          │
│                                   │
│ ──────────────────────────────── │
│ [a] Stage all  [c] Commit         │
│ [d] Diff       [r] Refresh        │
└───────────────────────────────────┘
```
</example-ui>

<not-git-repo-ui>
```
┌─ Git ─────────────────────────────┐
│                                   │
│ ⚠ Not a git repository            │
│                                   │
│ Initialize with:                  │
│   git init                        │
│                                   │
│ Or navigate to a git repository   │
│ to see status information.        │
│                                   │
└───────────────────────────────────┘
```
</not-git-repo-ui>

## Acceptance Criteria

<criteria>
- [ ] Git tab shows in sidebar when in a git repo
- [ ] Branch name and ahead/behind status displayed
- [ ] Staged files shown in green with status indicator
- [ ] Unstaged changes shown in yellow
- [ ] Untracked files shown in gray
- [ ] Can stage/unstage individual files
- [ ] Can view diff for selected file
- [ ] Can create commit with message
- [ ] "Not a git repository" shown when appropriate
- [ ] Auto-refresh when files change
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test in various git repository states
4. Rename this file from `06-git-status-integration.md` to `06-git-status-integration.complete.md`
</completion>
