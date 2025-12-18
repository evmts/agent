# Diff Command

<metadata>
  <priority>medium</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>low</estimated-complexity>
  <affects>tui/</affects>
</metadata>

## Objective

Implement a `/diff` slash command that shows the current git diff for the session, including both tracked and untracked file changes.

<context>
Codex provides `/diff` to view pending changes. This is useful for:
- Reviewing changes before committing
- Understanding what the agent has modified
- Debugging unexpected changes
- Preparing for code review

The command should show a clear, formatted diff of all changes made during the session.
</context>

## Requirements

<functional-requirements>
1. `/diff` shows git diff of session changes
2. Include:
   - Staged changes
   - Unstaged changes
   - Untracked files (with content preview)
3. Formatted output with:
   - File headers
   - Line numbers
   - Color-coded additions/deletions
4. Options:
   - `/diff --staged` - Only staged changes
   - `/diff --stat` - Summary statistics
   - `/diff <file>` - Specific file only
5. Paginated output for long diffs
</functional-requirements>

<technical-requirements>
1. Add `/diff` handler to TUI slash commands
2. Run git diff and format output
3. Handle untracked files separately
4. Use TUI pager for long output
5. Color output based on theme
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/main.go` - Add /diff command handler
- `tui/internal/components/diff/view.go` (CREATE) - Diff rendering
</files-to-modify>

<diff-output>
```
╭──────────────────────────────────────────────────────╮
│                    Session Diff                       │
├──────────────────────────────────────────────────────┤
│ Modified: src/auth/login.py                          │
├──────────────────────────────────────────────────────┤
│  23 │ def login(username, password):                 │
│  24 │-    if check_password(password):               │
│  24 │+    if verify_credentials(username, password): │
│  25 │         return create_session(username)        │
│  26 │+        log_login_attempt(username, True)      │
│  27 │     return None                                │
├──────────────────────────────────────────────────────┤
│ New file: src/auth/utils.py                          │
├──────────────────────────────────────────────────────┤
│   1 │+def verify_credentials(user, pwd):             │
│   2 │+    """Verify user credentials."""             │
│   3 │+    return check_user(user) and check_pwd(pwd) │
├──────────────────────────────────────────────────────┤
│ Summary: 2 files changed, 4 insertions, 1 deletion   │
╰──────────────────────────────────────────────────────╯
```
</diff-output>

<slash-command-handler>
```go
// In TUI slash command handler
case "/diff":
    args := parseArgs(input)

    var gitArgs []string
    if slices.Contains(args, "--staged") {
        gitArgs = append(gitArgs, "--staged")
    }
    if slices.Contains(args, "--stat") {
        gitArgs = append(gitArgs, "--stat")
    }

    // Check for specific file
    for _, arg := range args {
        if !strings.HasPrefix(arg, "-") {
            gitArgs = append(gitArgs, "--", arg)
            break
        }
    }

    // Get diff
    diff, err := runGitDiff(gitArgs)
    if err != nil {
        return fmt.Errorf("failed to get diff: %w", err)
    }

    if diff == "" {
        // Check for untracked files
        untracked, _ := runGitCommand("ls-files", "--others", "--exclude-standard")
        if untracked == "" {
            fmt.Println("No changes")
            return nil
        }
        diff = formatUntrackedFiles(untracked)
    }

    // Display in pager if long
    if strings.Count(diff, "\n") > 30 {
        return showInPager(diff)
    }

    fmt.Println(formatDiff(diff))
    return nil

func runGitDiff(args []string) (string, error) {
    cmdArgs := append([]string{"diff", "--color=always"}, args...)
    output, err := exec.Command("git", cmdArgs...).Output()
    return string(output), err
}

func formatUntrackedFiles(files string) string {
    var result strings.Builder
    result.WriteString("Untracked files:\n\n")

    for _, file := range strings.Split(strings.TrimSpace(files), "\n") {
        if file == "" {
            continue
        }
        result.WriteString(fmt.Sprintf("  + %s (new file)\n", file))
    }

    return result.String()
}
```
</slash-command-handler>

<diff-formatting>
```go
func formatDiff(raw string) string {
    var result strings.Builder
    lines := strings.Split(raw, "\n")

    for _, line := range lines {
        switch {
        case strings.HasPrefix(line, "diff --git"):
            // File header
            parts := strings.Split(line, " ")
            if len(parts) >= 4 {
                file := strings.TrimPrefix(parts[2], "a/")
                result.WriteString(fmt.Sprintf("\n═══ %s ═══\n", file))
            }
        case strings.HasPrefix(line, "@@"):
            // Hunk header
            result.WriteString(lipgloss.NewStyle().
                Foreground(lipgloss.Color("cyan")).
                Render(line) + "\n")
        case strings.HasPrefix(line, "+") && !strings.HasPrefix(line, "+++"):
            // Addition
            result.WriteString(lipgloss.NewStyle().
                Foreground(lipgloss.Color("green")).
                Render(line) + "\n")
        case strings.HasPrefix(line, "-") && !strings.HasPrefix(line, "---"):
            // Deletion
            result.WriteString(lipgloss.NewStyle().
                Foreground(lipgloss.Color("red")).
                Render(line) + "\n")
        case strings.HasPrefix(line, "index") || strings.HasPrefix(line, "---") || strings.HasPrefix(line, "+++"):
            // Skip meta lines
            continue
        default:
            result.WriteString(line + "\n")
        }
    }

    return result.String()
}
```
</diff-formatting>

## Acceptance Criteria

<criteria>
- [ ] `/diff` shows all pending changes
- [ ] Staged and unstaged changes included
- [ ] Untracked files shown with preview
- [ ] `/diff --staged` shows only staged
- [ ] `/diff --stat` shows summary only
- [ ] `/diff <file>` shows specific file
- [ ] Color-coded additions/deletions
- [ ] Pager for long output
- [ ] "No changes" message when clean
- [ ] Works in non-git directories (graceful error)
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Test with various git states (clean, staged, unstaged, untracked)
3. Test pager with long diffs
4. Run `zig build build-go` to ensure compilation succeeds
5. Rename this file from `38-diff-command.md` to `38-diff-command.complete.md`
</completion>
