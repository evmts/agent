# Implement Missing UI Features

Implement the 5 UI features that have backend/database support but lack frontend implementation.

> **IMPORTANT**: This is a jj-native codebase. We do NOT use GitHub-style pull requests. Instead we use:
> - **Landing Queue**: Stacked changesets that get landed (rebased) onto the target bookmark
> - **Changes**: Individual changesets (not commits) that can be stacked, rebased, and evolved
> - **Bookmarks**: Movable labels pointing to changes (like git branches but more flexible)

---

## Architecture Context

```
┌─────────────────────────────────────────────────────────────────┐
│                         JJ Workflow                              │
├─────────────────────────────────────────────────────────────────┤
│  1. Create changes (stacked if needed)                          │
│  2. Submit to landing queue for review                          │
│  3. Reviews happen on changes, not "PRs"                        │
│  4. CI runs, creates commit statuses                            │
│  5. When approved + green, change lands (rebases onto target)   │
└─────────────────────────────────────────────────────────────────┘
```

This is fundamentally different from GitHub PRs:
- No merge commits (changes are rebased/landed)
- Stacked diffs are first-class (change A depends on change B)
- Changes evolve (same change-id, different commit-id after rebase)
- Landing is atomic (all stacked changes land together or none)

---

## Features to Implement

### 1. Landing Queue UI (`/{user}/{repo}/landing`)

**Database Tables**: `landing_queue`, `landing_reviews`, `landing_line_comments`

**Backend Routes** (verify these exist, implement if missing):
- `GET /:user/:repo/landing` - List landing requests
- `POST /:user/:repo/landing` - Submit change for landing
- `GET /:user/:repo/landing/:id` - View landing request details
- `POST /:user/:repo/landing/:id/land` - Land the change
- `POST /:user/:repo/landing/:id/abort` - Abort landing request

**UI Requirements**:
- Landing queue list page showing pending/ready/landed changes
- Stacked diff visualization (show dependency chain)
- Diff viewer for each change in the stack
- Review status indicators
- Conflict detection display
- "Land" button (enabled when ready)
- "Abort" button

**Key Components**:
```
LandingQueueList - List of landing requests with filters
LandingRequestCard - Individual request with status, author, conflicts
StackedDiffView - Visualization of change dependencies
LandingDiffViewer - Side-by-side or unified diff view
LandingActions - Land/Abort/Re-check buttons
```

---

### 2. Code Reviews UI (on Landing Requests)

**Database Tables**: `landing_reviews`, `landing_line_comments`

**Backend Routes** (verify/implement):
- `GET /:user/:repo/landing/:id/reviews` - List reviews
- `POST /:user/:repo/landing/:id/reviews` - Submit review (approve/reject/comment)
- `GET /:user/:repo/landing/:id/comments` - List line comments
- `POST /:user/:repo/landing/:id/comments` - Add line comment
- `PATCH /:user/:repo/landing/:id/comments/:commentId` - Update comment
- `POST /:user/:repo/landing/:id/comments/:commentId/resolve` - Resolve comment

**UI Requirements**:
- Review submission form (approve/request changes/comment)
- Line-by-line commenting in diff view
- Comment threads with resolve/unresolve
- Review status badges
- Reviewer avatars and status

**Key Components**:
```
ReviewForm - Submit review with type selection
ReviewList - Show all reviews with status
LineCommentThread - Threaded comments on specific lines
DiffWithComments - Diff view with inline comment capability
ReviewBadge - Approved/Changes Requested/Pending indicator
```

---

### 3. Commit Statuses UI (CI Status)

**Database Tables**: `commit_statuses`

**Backend Routes** (verify/implement):
- `GET /:user/:repo/changes/:changeId/statuses` - Get statuses for change
- `POST /:user/:repo/changes/:changeId/statuses` - Create/update status (internal)

**UI Requirements**:
- Status badges on change/landing views (pending/success/failure/error)
- Expandable status details showing all checks
- Link to workflow run that created the status
- Combined status indicator (all checks must pass)

**Key Components**:
```
CommitStatusBadge - Green check / Red X / Yellow dot
CommitStatusList - All statuses for a change
StatusDetail - Individual status with description and link
CombinedStatus - Overall pass/fail based on all statuses
```

**Integration Points**:
- Show on `/{user}/{repo}/changes/{changeId}` page
- Show on `/{user}/{repo}/landing/{id}` page
- Show in landing queue list (blocked if failing)

---

### 4. Protected Bookmarks UI

**Database Tables**: `protected_bookmarks`, `protected_branches` (legacy)

**Backend Routes** (verify/implement):
- `GET /:user/:repo/settings/protection` - List protection rules
- `POST /:user/:repo/settings/protection` - Create rule
- `PATCH /:user/:repo/settings/protection/:id` - Update rule
- `DELETE /:user/:repo/settings/protection/:id` - Delete rule

**UI Requirements**:
- Protection rules list in repo settings
- Create/edit protection rule form:
  - Bookmark pattern (glob, e.g., `main`, `release/*`)
  - Require reviews (number of approvals)
  - Require status checks (select which contexts)
  - Restrict who can push directly
- Rule priority ordering

**Key Components**:
```
ProtectionRulesList - All rules for repo
ProtectionRuleForm - Create/edit rule
PatternInput - Glob pattern with preview of matching bookmarks
RequiredChecksSelect - Multi-select for status contexts
ApprovalSettings - Number input with bypass options
```

**Location**: `/{user}/{repo}/settings/protection`

---

### 5. Stacked Changes Visualization

**Database Tables**: `changes` (parent_change_ids field)

**Backend Routes** (verify/implement):
- `GET /:user/:repo/changes/:changeId/stack` - Get full stack
- `GET /:user/:repo/changes/:changeId/ancestors` - Get ancestor chain
- `GET /:user/:repo/changes/:changeId/descendants` - Get descendant changes

**UI Requirements**:
- Visual graph of change dependencies
- Stack view showing linear chain
- Rebase indicators (when change needs update)
- Conflict indicators per change in stack
- Navigate between changes in stack

**Key Components**:
```
ChangeStackGraph - Visual DAG of change relationships
ChangeStackList - Linear list view of stack
ChangeStackItem - Individual change with status
StackNavigation - Prev/Next in stack buttons
RebaseIndicator - Shows if change is behind target
```

**Integration Points**:
- Show on `/{user}/{repo}/changes/{changeId}` page
- Show on `/{user}/{repo}/landing/{id}` page
- Show in landing queue (full stack context)

---

## Implementation Order

1. **Commit Statuses UI** (P0) - Needed for CI visibility
2. **Landing Queue UI** (P0) - Core workflow
3. **Code Reviews UI** (P0) - Required for landing
4. **Stacked Changes Visualization** (P1) - Enhances understanding
5. **Protected Bookmarks UI** (P1) - Governance feature

---

## Subagent Tasks

Spawn these subagents to implement each feature:

### Subagent 1: Commit Statuses

```xml
<context>
Database table `commit_statuses` exists with: repository_id, commit_sha, context, state, description, target_url, workflow_run_id.

Backend routes may exist in server/routes/ - check first.

Frontend location: ui/pages/[user]/[repo]/changes/[changeId].astro and related components.
</context>

<task>
1. Verify backend routes exist for commit statuses, implement if missing
2. Create CommitStatusBadge component (green/red/yellow icons)
3. Create CommitStatusList component showing all checks
4. Integrate into change detail page
5. Add status display to landing queue items
</task>

<constraints>
- Use existing UI patterns from ui/components/
- Follow brutalist design aesthetic
- No external icon libraries - use ASCII/text symbols
</constraints>
```

### Subagent 2: Landing Queue

```xml
<context>
Database tables exist: landing_queue, landing_reviews, landing_line_comments.

This is jj-style landing, NOT GitHub PRs:
- Changes are rebased onto target, not merged
- Stacked changes land together
- change_id is stable, commit_id changes on rebase

Backend routes in server/routes/landing_queue.zig (verify).
</context>

<task>
1. Verify/implement backend CRUD routes for landing queue
2. Create landing queue list page at /{user}/{repo}/landing
3. Create landing request detail page
4. Implement diff viewer for changes
5. Add Land/Abort actions
6. Show stack context when change has dependencies
</task>

<constraints>
- Terminology: "landing" not "merging", "changes" not "commits"
- Show change-id (8 char prefix), not full commit SHA
- Indicate when rebase is needed
</constraints>
```

### Subagent 3: Code Reviews

```xml
<context>
Database tables: landing_reviews (status: pending/approved/rejected/dismissed), landing_line_comments.

Reviews happen on landing requests, not on individual changes.
</context>

<task>
1. Verify/implement review submission routes
2. Create review form component (approve/request changes/comment)
3. Create line comment system in diff view
4. Implement comment threads with resolve/unresolve
5. Show review status badges on landing requests
</task>

<constraints>
- Reviews block landing until approved
- Stale reviews (after new changes pushed) should be indicated
- Comment resolution is tracked
</constraints>
```

### Subagent 4: Stacked Changes

```xml
<context>
Database: changes table has parent_change_ids JSONB array.

JJ changes form a DAG, but most common case is linear stacks.
</context>

<task>
1. Verify/implement stack-related API routes
2. Create ChangeStackGraph component (visual DAG)
3. Create ChangeStackList component (linear view)
4. Add stack navigation (prev/next buttons)
5. Integrate into change detail and landing pages
</task>

<constraints>
- Handle diamond dependencies (A -> B, A -> C, B+C -> D)
- Show which changes are already landed
- Indicate rebase status for each change in stack
</constraints>
```

### Subagent 5: Protected Bookmarks

```xml
<context>
Database: protected_bookmarks table with pattern, require_review, required_approvals.

This replaces GitHub-style branch protection with jj bookmark protection.
</context>

<task>
1. Create settings page at /{user}/{repo}/settings/protection
2. Implement protection rules CRUD
3. Create pattern input with glob matching preview
4. Add required checks selection
5. Enforce rules in landing queue (show blocked status)
</task>

<constraints>
- Patterns use glob syntax (main, release/*, feature/*)
- Rules have priority ordering
- Admin can bypass (with warning)
</constraints>
```

---

## Testing Each Feature

After implementing, verify with E2E tests:

```typescript
// Example test for landing queue
test('can submit change for landing', async ({ authedPage }) => {
  await authedPage.goto('/e2etest/testrepo/changes/abc123');
  await authedPage.click('button:has-text("Submit for Landing")');
  await expect(authedPage.locator('.landing-status')).toContainText('Pending');
});

test('can approve and land change', async ({ authedPage }) => {
  await authedPage.goto('/e2etest/testrepo/landing/1');
  await authedPage.click('button:has-text("Approve")');
  await authedPage.click('button:has-text("Land")');
  await expect(authedPage.locator('.landing-status')).toContainText('Landed');
});
```

---

## Success Criteria

Each feature is complete when:

1. Backend routes exist and work (test with curl)
2. Frontend pages render without errors
3. CRUD operations work end-to-end
4. E2E tests pass
5. Integrates with existing pages (changes, repos, settings)
