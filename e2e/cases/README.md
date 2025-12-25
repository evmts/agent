# E2E Test Cases

Individual test files organized by feature area.

## Purpose

Each spec file tests a specific feature or subsystem with comprehensive coverage including happy paths, edge cases, and error scenarios.

## Test Files

| File | Description |
|------|-------------|
| `auth.spec.ts` | SIWE authentication: login, logout, session persistence |
| `siwe.spec.ts` | SIWE edge cases: nonce expiry, signature validation |
| `sessions.spec.ts` | Session management: creation, list, deletion |
| `security.spec.ts` | Security: CSRF, rate limiting, permissions |
| `security-headers.spec.ts` | HTTP security headers validation |
| `repository.spec.ts` | Repository CRUD operations |
| `workflows.spec.ts` | Workflow execution and status |
| `file-navigation.spec.ts` | File tree browsing and navigation |
| `bookmarks-changes.spec.ts` | Bookmark and change tracking |
| `password-reset.spec.ts` | Password reset flows (legacy auth) |
| `bugs.spec.ts` | Regression tests for fixed bugs |
| `bugs-2025-12-20.spec.ts` | Recent bug fixes |
| `porto-mock.spec.ts` | Porto service mocking |

## Writing Tests

Structure:
```typescript
import { test, expect } from '@playwright/test';

test.describe('Feature Area', () => {
  test('should do something', async ({ page }) => {
    // Arrange
    await page.goto('/path');

    // Act
    await page.click('button');

    // Assert
    await expect(page.locator('.result')).toBeVisible();
  });
});
```

Use fixtures from `../fixtures.ts`:
```typescript
test('with auth', async ({ authenticatedPage }) => {
  // Page is already authenticated
  await authenticatedPage.goto('/dashboard');
});
```

## Test Patterns

| Pattern | Usage |
|---------|-------|
| `test.describe()` | Group related tests |
| `test.beforeEach()` | Setup per test |
| `test.afterEach()` | Cleanup per test |
| `test.skip()` | Temporarily disable test |
| `test.fixme()` | Mark known failure |
| `test.slow()` | Extend timeout for slow tests |
