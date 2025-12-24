# Fix CSRF Token Enforcement in UI Components

## Priority: CRITICAL | Security

## Problem

Multiple UI components make state-changing requests (POST/DELETE/PATCH) without including CSRF tokens, despite the infrastructure existing in `ui/lib/client-auth.ts`.

**Affected components:**
- `ui/components/IssueSidebar.astro` - assignees, labels, milestones (lines 668-813)
- `ui/components/FileDiffCard.astro` - comments (lines 512-530)
- `ui/components/Reactions.astro` - reactions (lines 97-100)
- `ui/pages/[user]/[repo]/workflows/[runId].astro` - cancel/rerun (lines 658-696)

## Task

1. **Audit all fetch calls:**
   ```bash
   grep -rn "fetch.*POST\|fetch.*DELETE\|fetch.*PATCH\|fetch.*PUT" ui/
   ```
   - List every file with state-changing fetch calls
   - Check if `withCsrfToken` is used

2. **Fix each component:**
   - Import: `import { withCsrfToken } from '../lib/client-auth';`
   - Wrap fetch options: `fetch(url, withCsrfToken({ method: 'POST', ... }))`
   - Ensure CSRF token is in headers, not body

3. **Fix IssueSidebar.astro:**
   - Line 668: Add assignee
   - Line 705: Remove assignee
   - Line 738: Add label
   - Line 765: Remove label
   - Line 792: Update milestone
   - Line 813: Update due date

4. **Fix FileDiffCard.astro:**
   - Line 512: Create comment
   - Line 530: Delete comment

5. **Fix Reactions.astro:**
   - Line 97: Add reaction
   - Line 100: Remove reaction

6. **Fix workflow run page:**
   - Cancel workflow run
   - Rerun workflow

7. **Add ESLint rule to prevent regression:**
   - Create custom ESLint rule or use existing pattern
   - Flag any fetch with POST/DELETE/PATCH/PUT without withCsrfToken
   - Add to CI pipeline

8. **Write E2E tests:**
   - Test that requests without CSRF token are rejected (403)
   - Test that requests with valid CSRF token succeed
   - Test CSRF token expiration behavior

## Acceptance Criteria

- [ ] All state-changing fetch calls use `withCsrfToken`
- [ ] ESLint rule prevents future regressions
- [ ] E2E tests verify CSRF protection
- [ ] Manual testing confirms functionality still works
