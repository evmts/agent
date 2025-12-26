# E2E Test Fix Handoff

> **BLOCKING ISSUE**: Server has a critical `ConnectionBusy` bug that crashes on first database request. This must be fixed before E2E tests can pass.

## Current State

| Metric | Value |
|--------|-------|
| Passed | 6 |
| Failed | 9 |
| Status | BLOCKED by server bug |

## Critical Bug: ConnectionBusy

The Zig API server crashes on the first database query with `error.ConnectionBusy`. This affects ALL routes that use the database, including `/api/:user/:repo/stats` which the repo page depends on.

**Symptoms:**
- Health endpoint (`/health`) works (no DB access)
- Any endpoint that queries DB returns 500 Internal Server Error
- Server log shows: `warning: httpz: unhandled exception for request: ... Err: error.ConnectionBusy`
- Server crashes after first failed request

**Root Cause Investigation:**
- Pool is initialized with `size=20, timeout=30_000ms`
- All connection acquire/release patterns appear correct (using `defer conn.release()`)
- Error happens immediately, not after 30s timeout
- Issue is in `pg.zig` library or how pool is being used

**Files to investigate:**
- `server/main.zig:49-53` - Pool initialization
- `db/daos/*.zig` - Connection usage patterns
- pg.zig library (external dependency)

## Previous Analysis (OUTDATED)

The original HANDOFF.md claimed CSS selectors were missing. **This was incorrect.** All selectors exist:

| Selector | Status | Location |
|----------|--------|----------|
| `.breadcrumb` | EXISTS | `index.astro:53` |
| `.repo-nav` | EXISTS | `index.astro:60` |
| `.file-tree` | EXISTS | `FileTree.astro` |
| `.clone-url-input` | EXISTS | `index.astro:149` |
| `.markdown-body` | FIXED | `Markdown.astro` - added wrapper div |

## What Was Fixed

1. **Markdown.astro** - Added `.markdown-body` wrapper div around rendered HTML

## Remaining Work

1. **Fix ConnectionBusy bug** (CRITICAL)
   - Debug pg.zig pool behavior
   - May need to update pg.zig dependency or fix connection management

2. **Verify E2E tests pass** (after bug fix)
   - repository.spec.ts
   - file-navigation.spec.ts
   - bookmarks-changes.spec.ts

## Quick Commands

```bash
# Seed database (run from project root)
cd /Users/williamcory/plue && bun e2e/seed.ts

# Test server manually
PORT=4001 zig build run &
curl http://localhost:4001/health  # Works
curl http://localhost:4001/api/e2etest/testrepo/stats  # FAILS with ConnectionBusy

# Run tests
cd e2e && pnpm test cases/repository.spec.ts

# Terminate stale DB connections
docker exec plue-postgres-1 psql -U postgres -d plue -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'plue' AND pid <> pg_backend_pid();"
```

## File Locations

```
server/
├── main.zig              # Pool initialization, Context setup
├── routes/repositories.zig  # Stats endpoint that fails
├── config.zig            # Database URL config

db/
├── root.zig              # Re-exports pg types
├── daos/                 # Data access objects

server/build.zig.zon      # pg.zig dependency reference
```
