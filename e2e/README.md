# E2E Tests

End-to-end tests using Playwright for comprehensive system validation.

## Purpose

Browser-based tests that exercise the full stack: UI, API server, database, and workflows. Tests run against a live instance with real authentication, database transactions, and agent execution.

## Quick Start

```bash
# Run all tests
pnpm --filter e2e test

# Run specific test file
pnpm --filter e2e test auth.spec.ts

# Open UI mode for debugging
pnpm --filter e2e test:ui

# View last test report
pnpm --filter e2e test:report
```

## Key Files

| File | Description |
|------|-------------|
| `playwright.config.ts` | Test configuration and browser setup |
| `global-setup.ts` | Database seeding before tests |
| `global-teardown.ts` | Cleanup after test run |
| `fixtures.ts` | Custom Playwright fixtures and helpers |
| `seed.ts` | Database seeding utilities |
| `test-types.d.ts` | TypeScript type definitions |
| `cases/` | Test files organized by feature |

## Test Structure

Tests are organized in `cases/` by feature area:

```
cases/
├── auth.spec.ts                 # SIWE authentication flows
├── siwe.spec.ts                 # SIWE edge cases
├── sessions.spec.ts             # Session management
├── security.spec.ts             # Security features
├── security-headers.spec.ts     # HTTP security headers
├── repository.spec.ts           # Repository CRUD
├── workflows.spec.ts            # Workflow execution
├── file-navigation.spec.ts      # File browsing
├── bookmarks-changes.spec.ts    # Bookmark/change tracking
└── bugs.spec.ts                 # Regression tests
```

## Debugging

Playwright captures artifacts on failure:
- Traces: Full timeline with screenshots, network, console
- Screenshots: Final state before failure
- Videos: Full test execution recording
- Console logs: Browser console output

Artifacts stored in `test-results/` and viewable via:
```bash
pnpm --filter e2e test:report
```
