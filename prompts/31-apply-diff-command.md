# Apply Diff Command

<metadata>
  <priority>high</priority>
  <category>cli-feature</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/, core/</affects>
</metadata>

## Objective

Implement an `apply` / `a` command that applies the latest session diff to the working tree using git apply.

<context>
Codex provides `codex apply` / `codex a` to apply changes made during a session. This is useful when:
- Running in plan mode where changes aren't applied immediately
- Reviewing changes before applying
- Selectively applying changes from a session
- Recovering changes after a revert

The command takes the diff from the most recent session and applies it to the working directory, similar to `git apply`.
</context>

## Requirements

<functional-requirements>
1. Add `apply` / `a` subcommand to CLI
2. Retrieve diff from most recent session (or specified session)
3. Apply diff to working tree using git apply
4. Options:
   - `--session <ID>`: Apply diff from specific session
   - `--dry-run`: Show what would be applied without making changes
   - `--reverse`: Reverse/unapply the diff
   - `--check`: Check if diff applies cleanly without applying
   - `--3way`: Fall back to 3-way merge on conflict
5. Display summary of applied changes
6. Handle errors gracefully (conflicts, missing files)
</functional-requirements>

<technical-requirements>
1. Add `apply` subcommand to Go CLI in `tui/main.go`
2. Create `apply.go` module for apply logic
3. Fetch session diff via API (`GET /session/{id}/diff`)
4. Use `git apply` subprocess for applying
5. Parse and display git apply output
6. Handle various git apply exit codes
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/main.go` - Add apply subcommand
- `tui/apply.go` (CREATE) - Apply command implementation
</files-to-modify>

<cli-interface>
```
agent apply [OPTIONS]

Apply the latest session diff to the working tree.

Options:
  --session <ID>    Apply diff from specific session (default: latest)
  --dry-run         Show what would be applied without changes
  --reverse         Reverse the diff (unapply changes)
  --check           Check if diff applies cleanly
  --3way            Use 3-way merge for conflicts
  -q, --quiet       Suppress output except errors
  -h, --help        Print help
```
</cli-interface>

<example-usage>
```bash
# Apply latest session diff
agent apply

# Dry run to preview changes
agent apply --dry-run

# Apply diff from specific session
agent apply --session ses_abc123

# Check if diff can be applied
agent apply --check

# Reverse (unapply) the diff
agent apply --reverse

# With 3-way merge for conflicts
agent apply --3way
```
</example-usage>

<implementation-sketch>
```go
func runApply(cmd *cobra.Command, args []string) error {
    // Get session ID (latest or specified)
    sessionID := getLatestSessionID()
    if specified := cmd.Flag("session").Value.String(); specified != "" {
        sessionID = specified
    }

    // Fetch diff from API
    diff, err := fetchSessionDiff(sessionID)
    if err != nil {
        return fmt.Errorf("failed to fetch diff: %w", err)
    }

    if diff == "" {
        fmt.Println("No changes to apply")
        return nil
    }

    // Build git apply args
    gitArgs := []string{"apply"}
    if dryRun, _ := cmd.Flags().GetBool("dry-run"); dryRun {
        gitArgs = append(gitArgs, "--dry-run")
    }
    if reverse, _ := cmd.Flags().GetBool("reverse"); reverse {
        gitArgs = append(gitArgs, "--reverse")
    }
    if check, _ := cmd.Flags().GetBool("check"); check {
        gitArgs = append(gitArgs, "--check")
    }
    if threeWay, _ := cmd.Flags().GetBool("3way"); threeWay {
        gitArgs = append(gitArgs, "--3way")
    }

    // Run git apply with diff on stdin
    gitCmd := exec.Command("git", gitArgs...)
    gitCmd.Stdin = strings.NewReader(diff)
    gitCmd.Stdout = os.Stdout
    gitCmd.Stderr = os.Stderr

    if err := gitCmd.Run(); err != nil {
        if exitErr, ok := err.(*exec.ExitError); ok {
            return fmt.Errorf("git apply failed with exit code %d", exitErr.ExitCode())
        }
        return fmt.Errorf("git apply failed: %w", err)
    }

    if !dryRun && !check {
        fmt.Println("✓ Changes applied successfully")
    }

    return nil
}
```
</implementation-sketch>

## Acceptance Criteria

<criteria>
- [ ] `agent apply` applies latest session diff
- [ ] `--session <ID>` applies diff from specific session
- [ ] `--dry-run` shows changes without applying
- [ ] `--reverse` unapplies the diff
- [ ] `--check` validates diff can be applied
- [ ] `--3way` enables 3-way merge for conflicts
- [ ] Success message shows summary of changes
- [ ] Error handling for conflicts and missing files
- [ ] Works with both staged and unstaged changes
- [ ] Exit codes reflect git apply results
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
2. Run `zig build build-go` to ensure compilation succeeds
3. Test apply with various diff scenarios
4. Test conflict handling and error cases
5. Rename this file from `31-apply-diff-command.md` to `31-apply-diff-command.complete.md`
</completion>
