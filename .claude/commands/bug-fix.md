---
allowed-tools: Bash(bun:*), Bash(git:*), Bash(gh:*), Bash(zig:*), Glob, Grep, Read, Write, Edit, Task, TodoWrite
argument-hint: <issue-number> [--dry-run] [--skip-tests]
description: Fix a bug from GitHub issues, verify with tests, and update the issue with results.
model: claude-sonnet-4-20250514
---

# Bug Fix Agent

Systematically fix bugs documented in GitHub issues, verify fixes with Playwright tests, and report results back to the issue tracker.

## Arguments

- `<issue-number>`: Required. GitHub issue number (e.g., `41`) or URL
- `--dry-run`: Analyze and plan the fix without making changes
- `--skip-tests`: Skip running tests (for quick iteration)

Arguments: $ARGUMENTS

## Open Bug Issues

These are the currently open bugs available to fix:

| Issue | Title | Severity | Test File |
|-------|-------|----------|-----------|
| [#41](https://github.com/evmts/agent/issues/41) | BUG-SEC-006: No rate limiting on login attempts | High | `e2e/bugs-2025-12-20.spec.ts:120` |
| [#40](https://github.com/evmts/agent/issues/40) | BUG-043: Potential XSS in repository display | Critical | `e2e/bugs.spec.ts:506` |
| [#39](https://github.com/evmts/agent/issues/39) | BUG-038: Login form missing accessibility labels | Medium | `e2e/bugs.spec.ts:430` |
| [#38](https://github.com/evmts/agent/issues/38) | BUG-031/032: API accepts null bytes/control chars | High | `e2e/bugs.spec.ts:336` |
| [#37](https://github.com/evmts/agent/issues/37) | BUG-025: Long session cookie causes server error | High | `e2e/bugs.spec.ts:284` |
| [#36](https://github.com/evmts/agent/issues/36) | BUG-018-022: Unimplemented ops return 500 not 501 | Medium | `e2e/bugs.spec.ts:217` |
| [#35](https://github.com/evmts/agent/issues/35) | BUG-010: Repo name validation mismatch | Low | `e2e/bugs.spec.ts:99` |
| [#34](https://github.com/evmts/agent/issues/34) | BUG-001-003: Pagination with invalid numbers | Medium | `e2e/bugs.spec.ts:12` |

## Phase 1: Issue Analysis

First, fetch and understand the issue:

```bash
# Extract issue number from argument (handles both "41" and full URL)
ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+' | head -1)

# Fetch issue details
gh issue view $ISSUE_NUM --json title,body,labels,state
```

Parse the issue body to extract:
1. **Bug Description**: What is broken
2. **Reproduction Steps**: How to trigger the bug
3. **Expected vs Actual Behavior**: What should happen
4. **Test Case**: The test that validates this bug (file:line)
5. **Affected Files**: Where to look for the fix
6. **Root Cause Analysis**: Initial hypothesis (if provided)

## Phase 2: Create Fix Branch

Before making any changes, create a dedicated branch:

```bash
# Ensure we're on a clean state
git stash -u -m "bug-fix-$ISSUE_NUM-stash"

# Create fix branch from main
git checkout main
git pull origin main
git checkout -b fix/issue-$ISSUE_NUM

# Post initial comment to issue
gh issue comment $ISSUE_NUM --body "$(cat <<'EOF'
## 🔧 Fix Attempt Started

An automated fix attempt has been initiated.

**Branch**: `fix/issue-$ISSUE_NUM`
**Started**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Will update with progress...
EOF
)"
```

## Phase 3: Locate Test and Affected Code

Find the relevant test case:

```bash
# Search for the BUG-XXX pattern in test files
grep -rn "BUG-$BUG_ID\|$ISSUE_TITLE_KEYWORDS" e2e/bugs*.spec.ts
```

Find the affected source files mentioned in the issue:

```bash
# Use the Explore agent to understand the affected code
Task(subagent_type=Explore):
Find all code related to [issue description].
Trace the execution path from the API route to the bug location.
Identify the exact line(s) that need modification.
```

## Phase 4: Implement the Fix

Guidelines for fixing:
1. **Minimal changes**: Only modify what's necessary
2. **Follow existing patterns**: Match the codebase style
3. **Add observability**: Include metrics/logging for the fixed path
4. **Consider edge cases**: Handle all inputs gracefully

### Fix Categories and Approaches

**Security (SEC) bugs**:
- Add input validation at entry points
- Implement rate limiting where needed
- Escape output properly
- Add security headers

**Validation (VAL) bugs**:
- Add server-side validation
- Normalize inputs early
- Return proper 400 errors with clear messages

**API bugs**:
- Return correct HTTP status codes
- Handle edge cases (null, empty, oversized)
- Add request size limits

**Accessibility (A11Y) bugs**:
- Add proper ARIA labels
- Ensure keyboard navigation
- Add semantic HTML elements

## Phase 5: Run Verification Tests

```bash
# Run the specific bug test
bun playwright test -g "BUG-XXX" --reporter=list

# If specific test passes, run related test suite
bun playwright test e2e/bugs*.spec.ts --reporter=list

# Run broader tests to check for regressions
bun playwright test --reporter=list
```

Capture test output for reporting.

## Phase 6: Success Path - Commit and Close

If ALL tests pass:

```bash
# 1. Commit the fix
git add -A
git commit -m "$(cat <<'EOF'
🐛 fix: [Issue Title]

Fixes #$ISSUE_NUM

## Changes
- [List of changes made]

## Verification
- Test `BUG-XXX` now passes
- No regressions in test suite

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# 2. Push the branch
git push -u origin fix/issue-$ISSUE_NUM

# 3. Create PR (optional - or merge directly if authorized)
gh pr create --title "fix: $ISSUE_TITLE" --body "$(cat <<'EOF'
## Summary

Fixes #$ISSUE_NUM

## Changes Made
- [Detailed list]

## Test Results
- ✅ `BUG-XXX` test now passes
- ✅ Full test suite passes (X tests)

## Verification Steps
1. Run `bun playwright test -g "BUG-XXX"`
2. Verify expected behavior manually

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

# 4. Comment on issue with success
gh issue comment $ISSUE_NUM --body "$(cat <<'EOF'
## ✅ Fix Implemented Successfully

**Branch**: `fix/issue-$ISSUE_NUM`
**PR**: #[PR_NUMBER]

### Changes Made
[Summary of changes]

### Test Results
```
[Test output showing pass]
```

### Verification
The test case `BUG-XXX` now passes. Full test suite shows no regressions.

---
*Automated fix by Claude Code*
EOF
)"

# 5. Close the issue (if PR is merged or direct fix)
gh issue close $ISSUE_NUM --reason "completed" --comment "Fixed in PR #[PR_NUMBER]"
```

## Phase 7: Failure Path - Revert and Report

If tests FAIL or fix cannot be completed:

```bash
# 1. Capture what was learned
LEARNINGS="[Document findings here]"
BLOCKERS="[What prevented the fix]"

# 2. Revert all changes
git checkout -- .
git clean -fd

# 3. Return to previous branch
git checkout -
git branch -D fix/issue-$ISSUE_NUM

# 4. Restore stash if any
git stash pop 2>/dev/null || true

# 5. Update issue with detailed findings
gh issue comment $ISSUE_NUM --body "$(cat <<'EOF'
## ⚠️ Fix Attempt Unsuccessful

An automated fix was attempted but could not be completed.

### What Was Tried
[Description of attempted fix]

### What Was Learned
$LEARNINGS

### Blockers
$BLOCKERS

### Recommendations for Manual Fix
1. [Specific recommendation]
2. [Additional context]

### Files Analyzed
- `[file1]:[lines]`
- `[file2]:[lines]`

### Next Steps
- [ ] [Suggested action 1]
- [ ] [Suggested action 2]

---
*Automated analysis by Claude Code - Changes reverted, no modifications persist*
EOF
)"
```

## Safety Checklist

Before making any fix, verify:
- [ ] Created a new branch (not modifying main directly)
- [ ] Issue is actually open and a bug
- [ ] Test case exists to validate the fix
- [ ] Understand the root cause (not just symptoms)
- [ ] Fix doesn't introduce new security issues
- [ ] Changes are minimal and focused

## Observability Integration

When fixing bugs, consider adding observability:

```zig
// Add metrics for the fixed code path
pub const BugFixMetrics = struct {
    // e.g., for rate limiting fix
    rate_limited_requests: Counter,

    // e.g., for validation fix
    validation_rejections: Counter,
};
```

Update Grafana dashboards if new metrics are added.

## Example Fix Workflow

```
/bug-fix 41

Phase 1: Reading issue #41 - "No rate limiting on login attempts"
Phase 2: Creating branch fix/issue-41
Phase 3: Found test at e2e/bugs-2025-12-20.spec.ts:120
         Affected files: server/src/routes/auth.zig, server/src/middleware/
Phase 4: Implementing rate limiting middleware...
Phase 5: Running tests...
         ✅ BUG-SEC-006 now passes
         ✅ 26/26 other tests pass
Phase 6: Committing fix, creating PR, updating issue
         PR #42 created
         Issue #41 closed

Fix complete! PR: https://github.com/evmts/agent/pull/42
```

## Important Guidelines

1. **One bug at a time**: Focus on a single issue per invocation
2. **Test-driven**: Always verify with the documented test case
3. **Document everything**: Update the issue with all findings
4. **Revert on failure**: Never leave broken code on any branch
5. **Minimal changes**: Don't refactor unrelated code
6. **Security first**: Never introduce new vulnerabilities
7. **Observability**: Add metrics/logging for fixed code paths
