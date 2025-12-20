# Server Routes Unit Tests

Comprehensive unit tests for server route handlers in `/server/routes/`.

## Overview

This test suite focuses on testing the **business logic and validation** of route handlers without making actual HTTP requests. Tests use mocking to isolate route logic from external dependencies.

## Test Files

### Core Authentication & User Management
- **auth.test.ts** - SIWE authentication, registration, login/logout flows
- **users.test.ts** - User profile management, search, and updates

### Repository Management
- **repositories.test.ts** - Repository topics CRUD operations
- **bookmarks.test.ts** - JJ-native bookmark operations
- **stars.test.ts** - Repository starring and watching

### Session Management
- **sessions.test.ts** - AI agent session CRUD, forking, reverting, undo operations
- **messages.test.ts** - Message handling and persistence

### Issue Tracking
- **issues.test.ts** - Git-based issue tracking (sample tests for 1400+ line file)
  - Issue CRUD operations
  - Comments and reactions
  - Labels and milestones
  - Dependencies and pinning

## Testing Approach

### 1. Mocking Strategy

Tests use Bun's `mock()` function to mock external dependencies:

```typescript
const mockSql = mock(() => []);
mock.module('../../db/client', () => ({
  default: mockSql,
}));
```

Key dependencies that are mocked:
- **Database** (`sql` from `@databases/pg` or `postgres`)
- **External services** (SIWE, JWT, sessions)
- **Middleware** (auth, rate limiting)
- **Git operations** (JJ, git-issues)

### 2. Test Structure

Each test file follows this pattern:

```typescript
describe('Route Group', () => {
  let app: Hono;

  beforeEach(() => {
    app = new Hono();
    app.route('/prefix', routeApp);
    // Clear all mocks
  });

  describe('HTTP Method /path', () => {
    test('success case', async () => {
      // Arrange: Set up mocks
      // Act: Make request
      // Assert: Verify response
    });

    test('error case', async () => {
      // Test error handling
    });
  });
});
```

### 3. Test Coverage

Tests focus on:
- **Input validation** - Required fields, format validation, type checking
- **Business logic** - Data transformations, conditional flows
- **Error handling** - 400, 401, 403, 404, 500 responses
- **Edge cases** - Empty inputs, boundary conditions, special characters
- **Database interactions** - Queries are called correctly (mocked)
- **Authentication** - Protected routes require auth
- **Authorization** - Users can only access permitted resources

### 4. What's NOT Tested

These tests do **not** cover:
- Actual HTTP server behavior (use integration tests)
- Real database operations (use integration tests)
- Middleware execution order (tested in middleware tests)
- WebSocket connections
- File system operations
- Real cryptographic operations

## Running Tests

```bash
# Run all route tests
bun test server/routes/

# Run specific test file
bun test server/routes/__tests__/auth.test.ts

# Run with coverage
bun test --coverage server/routes/

# Run in watch mode
bun test --watch server/routes/
```

## Known Issues & Improvements Needed

### Current Issues

1. **Mock Module Resolution**: Some tests fail because Bun's `mock.module()` requires exact module path matching. Paths must match how the route files import them.

2. **Route Mounting**: Tests mount routes with different prefixes. The actual app mounts them differently, so URL paths in tests may not match production.

3. **Middleware Mocking**: Auth middleware is mocked but doesn't properly populate `c.get('user')` in all cases.

### Improvements Needed

1. **Fix Mock Paths**: Update mock module paths to match actual imports
   ```typescript
   // Example fix
   mock.module('../../db/client', () => ({ default: mockSql }));
   // Should be:
   mock.module('/Users/williamcory/agent/db/client', () => ({ default: mockSql }));
   ```

2. **Add Integration Tests**: These unit tests should be supplemented with integration tests that:
   - Start a real server
   - Use a test database
   - Make real HTTP requests

3. **Improve Mock Helpers**: Create shared mock factories:
   ```typescript
   // server/routes/__tests__/helpers/mocks.ts
   export function mockAuthenticatedRequest(user) { ... }
   export function mockDatabase() { ... }
   ```

4. **Add More Issue Tests**: `issues.test.ts` has sample tests for a 1400+ line file. Add:
   - More label management tests
   - Milestone management tests
   - Assignee tests
   - Full reaction workflow tests

5. **Test Middleware Integration**: Test how routes interact with:
   - `requireAuth` middleware
   - `requireActiveAccount` middleware
   - Rate limiting
   - CORS

6. **Add Validation Schema Tests**: Test Zod schemas separately:
   ```typescript
   describe('Validation Schemas', () => {
     test('verifySchema rejects invalid signature', () => {
       expect(() => verifySchema.parse({ ... })).toThrow();
     });
   });
   ```

## Writing New Tests

When adding tests for a new route file:

1. **Copy the pattern** from existing test files
2. **Mock all external dependencies** at the top of the file
3. **Group tests by route** using `describe()`
4. **Test both success and error paths**
5. **Clear mocks in `beforeEach()`**
6. **Use descriptive test names** that explain what is being tested

Example:
```typescript
test('returns 400 when email format is invalid', async () => {
  const req = new Request('http://localhost/users/me', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'not-an-email' }),
  });
  const res = await app.fetch(req);

  expect(res.status).toBe(400);
  expect(await res.json()).toMatchObject({
    error: expect.stringContaining('email'),
  });
});
```

## Testing Philosophy

These tests follow the principle: **Test behavior, not implementation**.

- ✅ Test what responses are returned for given inputs
- ✅ Test that errors are handled gracefully
- ✅ Test validation logic
- ❌ Don't test SQL query syntax
- ❌ Don't test framework internals
- ❌ Don't test mock implementations

## Resources

- [Bun Test Documentation](https://bun.sh/docs/cli/test)
- [Hono Testing Guide](https://hono.dev/guides/testing)
- [Testing Best Practices](https://kentcdodds.com/blog/common-mistakes-with-react-testing-library)
