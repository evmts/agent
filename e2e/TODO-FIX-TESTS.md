# E2E Test Fix Task

## Problem Summary

The Playwright e2e tests are set up but fail because the Astro pages query database tables that may not exist (specifically `landing_queue` from the JJ migration). This causes error pages instead of the expected content.

**Test Results:** 27 passed, 38 failed

## Root Cause

1. The repository index page (`ui/pages/[user]/[repo]/index.astro`) queries `landing_queue` table at line 47-55
2. The bookmarks page (`ui/pages/[user]/[repo]/bookmarks.astro`) queries `landing_queue` at line 63-66
3. These tables are created by `db/migrate-jj-native.sql` which may not be applied

When these queries fail, Astro shows an error page instead of the expected content, causing all tests to fail.

## Files Involved

### Test Files (in `e2e/`)
- `fixtures.ts` - Test fixtures and selectors
- `seed.ts` - Database seeding script
- `global-setup.ts` - Runs before all tests
- `global-teardown.ts` - Runs after all tests
- `repository.spec.ts` - Repository page tests
- `file-navigation.spec.ts` - Tree/blob view tests
- `bookmarks-changes.spec.ts` - Bookmarks and changes tests

### Page Files That Query Missing Tables
- `ui/pages/[user]/[repo]/index.astro` - Lines 47-55 query `landing_queue`
- `ui/pages/[user]/[repo]/bookmarks.astro` - Lines 63-66 query `landing_queue`
- `ui/pages/[user]/[repo]/tree/[...path].astro` - May have similar issues
- `ui/pages/[user]/[repo]/blob/[...path].astro` - May have similar issues

### Migration Files
- `db/schema.sql` - Base schema (has users, repositories, issues, etc.)
- `db/migrate-jj-native.sql` - Creates `landing_queue`, `bookmarks`, `changes`, etc.

## Solution Options

### Option 1: Apply Migrations in Global Setup (Recommended)
Modify `e2e/global-setup.ts` to run the necessary migrations before seeding:

```typescript
import { sql } from "../db/client";
import { readFile } from "node:fs/promises";

async function applyMigrations() {
  // Apply JJ migration if tables don't exist
  const migrationSql = await readFile("db/migrate-jj-native.sql", "utf-8");
  await sql.unsafe(migrationSql);
}
```

### Option 2: Make Pages Handle Missing Tables Gracefully
Wrap the `landing_queue` queries in try/catch in the Astro pages:

```typescript
let landingCount = 0;
try {
  const [result] = await sql`
    SELECT COUNT(*) as count FROM landing_queue WHERE ...
  `;
  landingCount = result?.count || 0;
} catch {
  // Table doesn't exist yet, show 0
}
```

Note: The index.astro already has this pattern but bookmarks.astro doesn't.

### Option 3: Create Test-Specific Database
Use a separate test database with all migrations pre-applied.

## Current Database State

The test database at `postgresql://postgres:password@localhost:54321/electric` has:
- ✅ `users` table
- ✅ `repositories` table
- ✅ `issues` table
- ❌ `landing_queue` table (missing - from JJ migration)
- ❌ `bookmarks` table (missing - from JJ migration)
- ❌ `changes` table (missing - from JJ migration)

## Test Data Created by Seed

The seed script (`e2e/seed.ts`) creates:
- User: `e2etest`
- Repository: `e2etest/testrepo` with files:
  - README.md
  - src/index.ts
  - src/components/Button.tsx
  - docs/guide.md
  - package.json
- Empty repository: `e2etest/emptyrepo`
- 2 test issues (1 open, 1 closed)

## How to Verify Fix

```bash
# Run all e2e tests
bun run test:e2e

# Run with visible browser for debugging
bun run test:e2e:debug

# Run specific test file
bunx playwright test e2e/repository.spec.ts
```

## Expected Outcome

All 65 tests should pass:
- 17 repository page tests
- 16 file navigation tests
- 32 bookmarks/changes tests

## Additional Context

- The app uses Bun runtime, not Node.js
- Frontend is Astro v5 with SSR
- Database is PostgreSQL via postgres.js library
- The app is transitioning from git to jj (Jujutsu) version control
- Bookmarks replace branches, landing requests replace PRs
