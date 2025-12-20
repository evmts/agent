---
allowed-tools: Bash(bun:*), Bash(git:*), Bash(gh:*), Glob, Grep, Read, Write, Edit, Task, TodoWrite
argument-hint: [--max=N] [--category=SEC|VAL|AUTH|API|A11Y] [--dry-run]
description: Find bugs, create failing Playwright tests, and open GitHub issues. Does NOT fix bugs.
model: claude-sonnet-4-20250514
---

# Bug Discovery Agent

Systematically find bugs and unimplemented features, validate them with Playwright tests, and document them as GitHub issues. **Do NOT fix any bugs** - only document them.

## Arguments

- `--max=N`: Maximum number of issues to create (default: 10)
- `--category=X`: Focus on specific category (SEC, VAL, AUTH, API, A11Y, UX)
- `--dry-run`: Show what would be done without creating issues

Arguments: $ARGUMENTS

## Phase 1: Discovery

Use the Explore agent to find potential bugs:

```
Task(subagent_type=Explore): Search the codebase for:
1. TODO, FIXME, "not implemented", "hack" comments
2. Error handling gaps (catch blocks that swallow errors)
3. Forms without validation (check ui/pages/*.astro)
4. API endpoints without input validation (check server/src/routes/)
5. Auth edge cases (session handling, token validation)
6. Unimplemented features mentioned in UI
7. Database queries without proper null checks
8. Missing error boundaries or 500 pages

Priority order: Security > Data integrity > Functionality > UX > Accessibility

Return a prioritized list of potential bugs with file locations.
```

## Phase 2: Write Failing Tests

Create test file: `e2e/bugs-{YYYY-MM-DD}.spec.ts`

### Test Structure

```typescript
import { test, expect } from './fixtures';

/**
 * Bug Validation Tests - {DATE}
 *
 * These tests document known bugs. Each test should FAIL until fixed.
 * Run: bun playwright test e2e/bugs-{DATE}.spec.ts
 */

test.describe('BUG-SEC: Security Issues', () => {
  test('BUG-SEC-001: {description}', async ({ page, request }) => {
    // Test implementation
  });
});

test.describe('BUG-VAL: Validation Issues', () => {
  // ...
});

test.describe('BUG-AUTH: Authentication Issues', () => {
  // ...
});

test.describe('BUG-API: API Issues', () => {
  // ...
});

test.describe('BUG-A11Y: Accessibility Issues', () => {
  // ...
});

test.describe('BUG-UX: User Experience Issues', () => {
  // ...
});
```

### Category Prefixes

| Prefix | Category | Priority |
|--------|----------|----------|
| SEC | Security (XSS, injection, auth bypass) | Critical |
| VAL | Input validation failures | High |
| AUTH | Authentication/authorization bugs | High |
| API | API behavior issues (wrong status codes, etc) | Medium |
| A11Y | Accessibility violations | Medium |
| UX | User experience issues | Low |

### Test Naming Convention

```
BUG-{CATEGORY}-{NNN}: {short description}
```

Examples:
- `BUG-SEC-001: Path traversal in blob route`
- `BUG-VAL-003: Pagination accepts negative numbers`
- `BUG-AUTH-002: Long session cookie crashes server`

## Phase 3: Validate Tests

Run the tests to confirm they fail:

```bash
bun playwright test e2e/bugs-*.spec.ts --reporter=list 2>&1 | head -100
```

**Only proceed with tests that ACTUALLY FAIL.** Remove or skip tests that pass.

## Phase 4: Check for Duplicates

Before creating issues, check for existing ones:

```bash
gh issue list -S "{bug description keywords}" --state all --limit 5
```

Skip any bugs that already have open issues.

## Phase 5: Commit Tests

Commit the test file before opening issues:

```bash
git add e2e/bugs-*.spec.ts
git commit -m "$(cat <<'EOF'
🧪 test: Add bug validation tests ({DATE})

Documents {N} bugs found during automated bug discovery:

{CATEGORY} Issues:
- BUG-{ID}: {description}
...

These tests are expected to FAIL until bugs are fixed.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Phase 6: Create GitHub Issues

For each failing test, create an issue:

```bash
gh issue create \
  --title "BUG-{ID}: {title}" \
  --label "bug" \
  --body "$(cat <<'EOF'
## Bug Description

{Clear description of the bug}

## Reproduction Steps

1. {Step 1}
2. {Step 2}
3. {Step 3}

## Expected Behavior

{What should happen}

## Actual Behavior

{What actually happens}

## Test Case

File: `e2e/bugs-{DATE}.spec.ts`
Line: {LINE}
Test: `{test name}`

```bash
bun playwright test -g "BUG-{ID}"
```

## Root Cause Analysis

{Brief analysis of why this bug exists}

## Suggested Fix

{High-level suggestion, NOT the actual fix}

## Observability Suggestion

{Metrics or logging that would help track this bug}

## Affected Files

- `{file1}:{line}`
- `{file2}:{line}`

---
*Discovered by automated bug hunt on {DATE}*
EOF
)"
```

## Phase 7: Summary Report

After completing, output a summary:

```markdown
## Bug Hunt Summary - {DATE}

### Tests Created
- File: `e2e/bugs-{DATE}.spec.ts`
- Total tests: {N}
- Failing (real bugs): {N}
- Passing (false positives removed): {N}
- Skipped (need special setup): {N}

### Issues Opened

| ID | Title | Category | Severity |
|----|-------|----------|----------|
| #{N} | BUG-SEC-001: ... | Security | Critical |
| ... | ... | ... | ... |

### Categories Breakdown
- Security: {N} issues
- Validation: {N} issues
- Auth: {N} issues
- API: {N} issues
- Accessibility: {N} issues
- UX: {N} issues

### Commits
- `{hash}` - 🧪 test: Add bug validation tests

### Next Steps
1. Prioritize security issues (BUG-SEC-*) for immediate fix
2. Add observability for {suggested metrics}
3. Consider running this again in {timeframe}
```

## Important Guidelines

1. **Do NOT fix bugs** - only document them with failing tests
2. **Be conservative** - only report bugs you're confident about
3. **Avoid duplicates** - always check existing issues first
4. **Prioritize security** - SEC bugs should be flagged as critical
5. **Include reproduction** - every issue must have clear repro steps
6. **Reference tests** - every issue must link to its test case
7. **Suggest observability** - help future debugging with metrics ideas

## Safety Checks

Before creating issues:
- [ ] All tests actually fail (not false positives)
- [ ] No duplicate issues exist
- [ ] Security issues don't expose sensitive details publicly
- [ ] Test file is committed first
- [ ] Issue descriptions are professional and actionable
