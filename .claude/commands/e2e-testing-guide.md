# E2E Testing Guide for Plue

> **CRITICAL ABORT RULE**: If you cannot successfully start the stack or run tests, **ABORT IMMEDIATELY** and report the issue loudly. Do not waste time trying workarounds. The human needs to fix infrastructure issues before E2E testing can proceed.

## Quick Start

```bash
# Start the full stack
docker compose -f infra/docker/docker-compose.yaml up -d

# Run E2E tests (from e2e directory)
cd e2e && pnpm test
```

Access app at: `http://localhost:8787`

> **Note**: Tests run via `pnpm test` in the e2e/ directory. The package.json scripts are:
> - `pnpm test` - Run all tests
> - `pnpm test:ui` - Interactive Playwright UI
> - `pnpm test:debug` - Debug mode with inspector
> - `pnpm seed` - Seed database manually

---

## Pre-Flight Checklist

Before starting any E2E testing session, verify:

1. **Docker is running**: `docker ps` should work
2. **Ports are free**: 4000, 4001, 5173, 8787, 8788, 54321
3. **Database is seeded**: Check `e2e/seed.ts` ran successfully
4. **Services respond**: `curl http://localhost:8787` returns HTML

If ANY of these fail, **ABORT** and report the specific failure.

---

## Service Architecture

```
Browser → Edge Worker (8787) → Astro SSR (5173) → Zig API (4000) → PostgreSQL (54321)
                ↓
         Auth routes (/api/auth/*)
```

| Service | Docker Port | Playwright Port | Purpose |
|---------|-------------|-----------------|---------|
| Edge Worker | 8787 | 8788 | Auth + CDN proxy |
| Astro SSR | 5173 | 4321 | Frontend rendering |
| Zig API | 4000 | 4001 | Backend logic |
| PostgreSQL | 54321 | 54321 | Database |

> **Note**: "Docker Port" is used when running `docker compose`. "Playwright Port" is used when Playwright starts its own servers via `playwright.config.ts`. Playwright uses different ports to avoid conflicts with any running dev servers.

---

## Running the Stack

### Option 1: Docker Compose (Recommended)

```bash
# Start all services
docker compose -f infra/docker/docker-compose.yaml up -d

# Verify services
docker compose -f infra/docker/docker-compose.yaml ps
```

### Option 2: Local Development

```bash
# Terminal 1: Backend
docker compose -f infra/docker/docker-compose.yaml up -d postgres api

# Terminal 2: Edge worker
cd edge && pnpm dev

# Terminal 3: Frontend
EDGE_URL=http://localhost:8787 bun dev
```

### Verifying Services Are Up

```bash
# Check API health
curl -s http://localhost:4000/health | jq

# Check Edge worker
curl -s http://localhost:8787 | head -1

# Check database
psql postgresql://plue:password@localhost:54321/plue -c "SELECT 1"
```

---

## Running E2E Tests

All commands run from the `e2e/` directory:

```bash
cd e2e
```

### Full Test Suite

```bash
pnpm test
```

### Interactive Mode (for debugging)

```bash
pnpm test:ui
```

### Debug Mode (with browser inspector)

```bash
pnpm test:debug
```

### Run Specific Test File

```bash
pnpm test cases/auth.spec.ts
```

### Keep Test Data for Debugging

```bash
KEEP_TEST_DATA=1 pnpm test
```

### Seed Database Manually

```bash
pnpm seed
```

---

## Gaining Visibility (MCP Tools)

Use these MCP tools to debug issues during testing:

### System Health

```
# Quick health check of all services
mcp__prometheus__service_health

# Error analysis (last 15 minutes)
mcp__prometheus__error_analysis

# Latency analysis
mcp__prometheus__latency_analysis
```

### Test Results

```
# Overall test summary
mcp__playwright__test_summary

# List failed tests
mcp__playwright__list_failures

# Details for specific test
mcp__playwright__test_details(testTitle="login")

# Find flaky tests
mcp__playwright__flaky_tests

# Failure patterns
mcp__playwright__failure_patterns
```

### Logs

```
# Recent errors across all services
mcp__logs__find_errors(start="15m")

# Tail logs from specific service
mcp__logs__tail_logs(service="api")

# Trace a specific request
mcp__logs__trace_request(request_id="<uuid>")
```

### Database

```
# Recent activity
mcp__database__recent_activity(hours=1)

# Find specific user
mcp__database__find_user(username="e2etest")

# Custom query
mcp__database__query(sql="SELECT * FROM auth_sessions LIMIT 5")
```

### Workflows

```
# System overview
mcp__workflows__system_overview

# Quick debug latest failure
mcp__workflows__quick_debug(latest=true)
```

---

## Complete Feature Checklist

Test EVERY feature in this list. Check off as you verify each works E2E.

### Authentication & Sessions

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| SIWE wallet connection | Edge `/api/auth/nonce` | `/login` | P0 |
| SIWE signature verify | Edge `/api/auth/verify` | `/login` | P0 |
| Logout | Edge `/api/auth/logout` | Header | P0 |
| Session persistence | `auth_sessions` table | All pages | P0 |
| Dev login (testing only) | `POST /auth/dev-login` | N/A | P0 |
| Get current user | `GET /auth/me` | All pages | P0 |

### User Management

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| View user profile | `GET /users/:username` | `/{user}` | P1 |
| Update own profile | `PATCH /users/me` | `/settings` | P1 |
| Search users | `GET /users/search` | `/users` | P2 |
| List all users | `GET /api/users` | `/users` | P2 |
| View user's repos | `GET /api/users/:username/repos` | `/{user}` | P1 |
| View user's stars | `GET /api/users/:username/starred` | `/{user}/stars` | P2 |

### Repository Management

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| Create repository | `POST /api/repos` | `/new` | P0 |
| List public repos | `GET /api/repos` | `/` (home) | P0 |
| Search repos | `GET /api/repos/search` | `/explore` | P1 |
| View repository | `GET /:user/:repo` | `/{user}/{repo}` | P0 |
| Star repository | `POST /:user/:repo/star` | `/{user}/{repo}` | P1 |
| Unstar repository | `DELETE /:user/:repo/star` | `/{user}/{repo}` | P1 |
| Watch repository | `POST /:user/:repo/watch` | `/{user}/{repo}` | P2 |
| Unwatch repository | `DELETE /:user/:repo/watch` | `/{user}/{repo}` | P2 |
| View stargazers | `GET /:user/:repo/stargazers` | `/{user}/{repo}/stargazers` | P2 |
| View watchers | `GET /api/:user/:repo/watchers` | `/{user}/{repo}/watchers` | P2 |

### Repository Topics

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| Get repo topics | `GET /:user/:repo/topics` | `/{user}/{repo}` | P2 |
| Update topics | `PUT /:user/:repo/topics` | `/{user}/{repo}` (modal) | P2 |
| Popular topics | `GET /api/repos/topics/popular` | `/explore` | P2 |
| Repos by topic | `GET /api/repos/topics/:topic` | `/explore` | P2 |

### File Browsing (Git Content)

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| View file tree | `GET /:user/:repo/tree/:path` | `/{user}/{repo}/tree/{path}` | P0 |
| View file content | `GET /:user/:repo/blob/:path` | `/{user}/{repo}/blob/{path}` | P0 |
| View README | Embedded in repo view | `/{user}/{repo}` | P0 |
| Clone URL display | N/A | `/{user}/{repo}` | P1 |
| Breadcrumb navigation | N/A | All file views | P1 |

### Bookmarks (JJ Branches)

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List bookmarks | `GET /:user/:repo/bookmarks` | `/{user}/{repo}/bookmarks` | P1 |
| Create bookmark | `POST /:user/:repo/bookmarks` | `/{user}/{repo}/bookmarks` (modal) | P1 |
| Delete bookmark | `DELETE /:user/:repo/bookmarks/:name` | `/{user}/{repo}/bookmarks` | P1 |
| Move bookmark | `PUT /:user/:repo/bookmarks/:name` | `/{user}/{repo}/bookmarks` (modal) | P2 |
| Set default bookmark | `POST /:user/:repo/bookmarks/:name/set-default` | `/{user}/{repo}/bookmarks` | P2 |

### Changes (JJ Commits)

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List changes | `GET /:user/:repo/changes` | `/{user}/{repo}/changes/{bookmark}` | P1 |
| View change details | `GET /:user/:repo/changes/:changeId` | `/{user}/{repo}/changes/{id}` | P1 |
| View change diff | `GET /:user/:repo/changes/:changeId/diff` | `/{user}/{repo}/changes/{id}` | P2 |

### Issues

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List issues | `GET /:user/:repo/issues` | `/{user}/{repo}/issues` | P0 |
| Create issue | `POST /:user/:repo/issues` | `/{user}/{repo}/issues/new` | P0 |
| View issue | `GET /:user/:repo/issues/:number` | `/{user}/{repo}/issues/{number}` | P0 |
| Update issue | `PATCH /:user/:repo/issues/:number` | `/{user}/{repo}/issues/{number}` | P1 |
| Close issue | `POST /:user/:repo/issues/:number/close` | `/{user}/{repo}/issues/{number}` | P0 |
| Reopen issue | `POST /:user/:repo/issues/:number/reopen` | `/{user}/{repo}/issues/{number}` | P1 |
| Filter by state | Query param `?state=open\|closed` | `/{user}/{repo}/issues` tabs | P1 |

### Issue Comments

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List comments | `GET /:user/:repo/issues/:number/comments` | `/{user}/{repo}/issues/{number}` | P0 |
| Add comment | `POST /:user/:repo/issues/:number/comments` | `/{user}/{repo}/issues/{number}` | P0 |
| Edit comment | `PATCH /:user/:repo/issues/:number/comments/:id` | `/{user}/{repo}/issues/{number}` | P1 |
| Delete comment | `DELETE /:user/:repo/issues/:number/comments/:id` | `/{user}/{repo}/issues/{number}` | P1 |

### Issue Labels

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List repo labels | `GET /:user/:repo/labels` | `/{user}/{repo}/labels` | P1 |
| Create label | `POST /:user/:repo/labels` | `/{user}/{repo}/labels` | P1 |
| Add label to issue | `POST /:user/:repo/issues/:number/labels` | `/{user}/{repo}/issues/{number}` | P1 |
| Remove label | `DELETE /:user/:repo/issues/:number/labels/:id` | `/{user}/{repo}/issues/{number}` | P2 |

### Issue Assignees

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| Add assignee | `POST /:user/:repo/issues/:number/assignees` | `/{user}/{repo}/issues/{number}` | P1 |
| Remove assignee | `DELETE /:user/:repo/issues/:number/assignees/:userId` | `/{user}/{repo}/issues/{number}` | P2 |

### Issue Reactions

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| Add issue reaction | `POST /:user/:repo/issues/:number/reactions` | `/{user}/{repo}/issues/{number}` | P2 |
| Remove reaction | `DELETE /:user/:repo/issues/:number/reactions/:emoji` | `/{user}/{repo}/issues/{number}` | P2 |
| Comment reactions | Same pattern with `/comments/:id/reactions` | `/{user}/{repo}/issues/{number}` | P2 |

### Issue Extras

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| Pin issue | `POST /:user/:repo/issues/:number/pin` | `/{user}/{repo}/issues/{number}` | P2 |
| Unpin issue | `POST /:user/:repo/issues/:number/unpin` | `/{user}/{repo}/issues/{number}` | P2 |
| Add dependency | `POST /:user/:repo/issues/:number/dependencies` | `/{user}/{repo}/issues/{number}` | P2 |
| Remove dependency | `DELETE /:user/:repo/issues/:number/dependencies/:blocked` | `/{user}/{repo}/issues/{number}` | P2 |

### Milestones

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List milestones | `GET /:user/:repo/milestones` | `/{user}/{repo}/milestones` | P2 |
| Create milestone | `POST /:user/:repo/milestones` | `/{user}/{repo}/milestones` | P2 |
| View milestone | `GET /:user/:repo/milestones/:id` | `/{user}/{repo}/milestones/{id}` | P2 |
| Update milestone | `PATCH /:user/:repo/milestones/:id` | `/{user}/{repo}/milestones/{id}` | P2 |
| Delete milestone | `DELETE /:user/:repo/milestones/:id` | `/{user}/{repo}/milestones/{id}` | P2 |
| Assign to issue | `PUT /:user/:repo/issues/:number/milestone` | `/{user}/{repo}/issues/{number}` | P2 |

### Workflows

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List workflow runs | `GET /:user/:repo/workflows/runs` | `/{user}/{repo}/workflows` | P1 |
| View run details | `GET /:user/:repo/workflows/runs/:runId` | `/{user}/{repo}/workflows/{runId}` | P1 |
| Create workflow run | `POST /:user/:repo/workflows/runs` | `/{user}/{repo}/workflows` (modal) | P1 |
| Cancel workflow | `POST /:user/:repo/workflows/runs/:runId/cancel` | `/{user}/{repo}/workflows/{runId}` | P1 |
| View run logs | `GET /:user/:repo/workflows/runs/:runId/logs` | `/{user}/{repo}/workflows/{runId}` | P1 |
| Filter by status | Query param `?status=...` | `/{user}/{repo}/workflows` tabs | P2 |

### Agent Sessions

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List sessions | `GET /api/sessions` | `/sessions` | P1 |
| Create session | `POST /api/sessions` | `/sessions` (modal) | P1 |
| View session | `GET /api/sessions/:id` | `/sessions/{id}` | P1 |
| Update session | `PATCH /api/sessions/:id` | `/sessions/{id}` | P2 |
| Delete session | `DELETE /api/sessions/:id` | `/sessions` | P2 |
| Abort session | `POST /api/sessions/:id/abort` | `/sessions/{id}` | P2 |
| Run agent | `POST /api/sessions/:id/run` | `/sessions/{id}` | P1 |
| Stream session | `GET /api/sessions/:id/stream` (SSE) | `/sessions/{id}` | P1 |

### SSH Keys

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List SSH keys | `GET /api/ssh-keys` | `/settings/ssh-keys` | P1 |
| Add SSH key | `POST /api/ssh-keys` | `/settings/ssh-keys` | P1 |
| Delete SSH key | `DELETE /api/ssh-keys/:id` | `/settings/ssh-keys` | P1 |

### Access Tokens

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| List tokens | `GET /api/user/tokens` | `/settings/tokens` | P1 |
| Create token | `POST /api/user/tokens` | `/settings/tokens` | P1 |
| Revoke token | `DELETE /api/user/tokens/:id` | `/settings/tokens` | P1 |

### Settings

| Feature | Backend Route | Frontend Page | Priority |
|---------|---------------|---------------|----------|
| Settings hub | N/A | `/settings` | P1 |
| Profile settings | Redirect to `/{user}` | `/settings` → `/{user}` | P1 |
| SSH keys page | See above | `/settings/ssh-keys` | P1 |
| Tokens page | See above | `/settings/tokens` | P1 |

---

## Features Potentially Missing UI

These backend routes exist but may not have complete UI:

| Backend Feature | Route Exists | UI Status | Notes |
|-----------------|--------------|-----------|-------|
| Repository settings | Partial | Check `/{user}/{repo}/settings` | |
| Branch protection | `protected_branches` table | Missing UI | DB schema only |
| Pull requests | `pull_requests` table | Missing UI | DB schema only |
| Code reviews | `reviews` table | Missing UI | DB schema only |
| Landing queue | `landing_queue` table | Check UI | May be incomplete |
| Commit statuses | `commit_statuses` table | Missing UI | DB schema only |
| Repository operations | `GET /:user/:repo/operations` | Check UI | |
| Contributors | N/A | Check `/{user}/{repo}/contributors` | |

---

## Test Data (Seeded by `e2e/seed.ts`)

```typescript
TEST_DATA = {
  user: 'e2etest',
  repo: 'testrepo',
  emptyRepo: 'emptyrepo',
  defaultBranch: 'main'
}
```

The seed creates:
- User: `e2etest` (ID: 7)
- Repository: `testrepo` with files (README.md, src/index.ts, etc.)
- Repository: `emptyrepo` (empty)
- Sample bookmarks, issues, workflow definitions

---

## Writing New Tests

### Test File Location

```
e2e/cases/{feature}.spec.ts
```

### Using Fixtures

```typescript
import { test, expect, TEST_DATA, selectors, authenticatedTest } from '../fixtures';

// Unauthenticated test
test('can view public repo', async ({ page, goToRepo }) => {
  await goToRepo(TEST_DATA.user, TEST_DATA.repo);
  await expect(page.locator(selectors.readme)).toBeVisible();
});

// Authenticated test
authenticatedTest('can create issue', async ({ authedPage, authedUser }) => {
  await authedPage.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/issues/new`);
  // ...
});
```

### Navigation Helpers

```typescript
await goToUser('e2etest');                    // → /e2etest
await goToRepo('e2etest', 'testrepo');        // → /e2etest/testrepo
await goToPath('e2etest', 'testrepo', 'blob', 'main', 'src/index.ts');
```

---

## Debugging Failed Tests

### 1. Check Test Output

```bash
# View HTML report
open e2e/playwright-report/index.html
```

### 2. Use MCP Tools

```
# Get failure details
mcp__playwright__test_details(testTitle="the failing test name")

# Check for patterns
mcp__playwright__failure_patterns
```

### 3. Check Service Logs

```
mcp__logs__find_errors(start="5m")
mcp__logs__tail_logs(service="api", lines=100)
```

### 4. Verify Database State

```
mcp__database__find_user(username="e2etest")
mcp__database__query(sql="SELECT * FROM issues WHERE repository_id = 1")
```

### 5. Run in Debug Mode

```bash
PWDEBUG=1 pnpm test cases/failing.spec.ts
```

---

## Common Issues & Solutions

### Issue: "Port already in use"

```bash
lsof -ti:4000 | xargs kill -9
lsof -ti:8787 | xargs kill -9
```

### Issue: "Database connection refused"

```bash
docker compose -f infra/docker/docker-compose.yaml restart postgres
```

### Issue: "Auth not working"

1. Verify edge worker is running: `curl http://localhost:8787/api/auth/nonce`
2. Check for CSRF token issues in browser console
3. Use dev-login for testing: `POST /auth/dev-login` with `{"username": "e2etest"}`

### Issue: "Test data not found"

```bash
cd e2e && pnpm seed
```

### Issue: "Flaky test"

```
# Find flaky tests
mcp__playwright__flaky_tests

# Check for timing issues in logs
mcp__logs__find_slow_requests(threshold_ms=1000)
```

---

## Abort Conditions

**IMMEDIATELY STOP and report if:**

1. Docker services fail to start
2. Database cannot be reached
3. API returns 5xx on health check
4. Edge worker doesn't respond
5. Seed script fails
6. More than 50% of tests fail on first run (infrastructure issue)

**Report format:**
```
ABORT: [Component] failed to [action]
Error: [exact error message]
Tried: [what you attempted]
Logs: [relevant log output]
```

---

## Priority Guide

- **P0**: Core functionality. App is broken without these.
- **P1**: Important features. Should work for MVP.
- **P2**: Nice-to-have. Can skip initially.

Test P0 features first, then P1, then P2.
