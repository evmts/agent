# Integration Test Suite

This directory contains integration tests for the Plue server that test against a real PostgreSQL database.

## Overview

The integration test suite provides:

- **Test Harness** (`mod.zig`) - Infrastructure for running tests with database connection
- **Authentication Tests** (`auth_test.zig`) - Session management, user registration, login/logout
- **Repository Tests** (`repo_test.zig`) - Repository CRUD, issues, milestones, labels

## Running Tests

### Prerequisites

1. **PostgreSQL Database**: You need a running PostgreSQL instance
2. **Test Database**: Create a test database (recommended: `plue_test`)
3. **Environment Variable**: Set `TEST_DATABASE_URL` to your test database connection string

### Setup Test Database

```bash
# Create test database
createdb plue_test

# Run migrations (from project root)
psql -d plue_test -f db/schema.sql
```

### Run Integration Tests

```bash
# Set test database URL
export TEST_DATABASE_URL="postgres://localhost:5432/plue_test"

# Run integration tests only
cd server
zig build test:integration

# Run all tests (unit + integration)
zig build test:all
```

### Using Different Database

You can use any PostgreSQL database by setting the `TEST_DATABASE_URL`:

```bash
# Local PostgreSQL
export TEST_DATABASE_URL="postgres://localhost:5432/plue_test"

# Remote PostgreSQL
export TEST_DATABASE_URL="postgres://user:pass@remote-host:5432/plue_test"

# With connection parameters
export TEST_DATABASE_URL="postgres://localhost/plue_test?sslmode=disable"
```

## Test Structure

### Test Harness (`mod.zig`)

The test harness provides:

- **TestContext**: Manages database connection, server setup, and cleanup
- **Test Helpers**: Create test users, sessions, repositories
- **Database Cleanup**: Automatic cleanup before/after tests
- **Assertions**: Custom assertions for database state

### Configuration

```zig
const test_config = mod.TestConfig{
    .database_url = mod.getTestDatabaseUrl(),
    .cleanup_on_success = true,  // Clean DB after successful tests
    .cleanup_on_failure = false, // Keep DB for debugging after failures
};

var ctx = try mod.TestContext.init(allocator, test_config);
defer ctx.deinit(true); // Pass true if test succeeded
```

### Writing New Tests

Example test structure:

```zig
test "my feature: does something" {
    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test data
    const user_id = try ctx.createTestUser("testuser", "test@example.com");
    const repo_id = try ctx.createTestRepo(user_id, "test-repo");

    // Perform operations
    var conn = try ctx.pool.acquire();
    defer conn.release();

    // ... your test logic ...

    // Make assertions
    try testing.expect(something_is_true);
}
```

## Test Coverage

### Authentication Tests (`auth_test.zig`)

- ✓ Session creation and retrieval
- ✓ Invalid session handling
- ✓ Session deletion
- ✓ Session refresh/expiration
- ✓ Expired session cleanup
- ✓ User CRUD operations
- ✓ Case-insensitive username lookup
- ✓ User profile updates
- ✓ Access token creation/validation
- ✓ Complete login/logout flow
- ✓ Concurrent sessions

### Repository Tests (`repo_test.zig`)

- ✓ Repository creation
- ✓ Repository listing
- ✓ Duplicate name prevention
- ✓ Repository updates
- ✓ Repository deletion (cascade)
- ✓ Issue creation
- ✓ Sequential issue numbers
- ✓ Issue state changes (open/close)
- ✓ Issue comments
- ✓ Milestone creation/assignment
- ✓ Label creation/assignment
- ✓ Complete repository workflow

## Best Practices

### 1. Isolation

Each test should be independent and not rely on other tests:

```zig
// Good: Creates own test data
const user_id = try ctx.createTestUser("testuser", "test@example.com");

// Bad: Relies on data from another test
const user = try db.getUserByUsername(ctx.pool, "testuser");
```

### 2. Cleanup

Always use defer to ensure cleanup runs:

```zig
var ctx = try mod.TestContext.init(allocator, test_config);
defer ctx.deinit(true); // Cleanup runs even if test fails
```

### 3. Descriptive Names

Use clear test names that describe what's being tested:

```zig
test "session: invalid session key returns null" { ... }  // Good
test "test1" { ... }                                       // Bad
```

### 4. Test One Thing

Each test should focus on a single behavior:

```zig
// Good: Tests only session creation
test "session: create and retrieve session" { ... }

// Bad: Tests multiple unrelated things
test "everything works" { ... }
```

### 5. Use Transactions

For tests that modify data, consider using transactions that can be rolled back:

```zig
// Begin transaction
_ = try conn.exec("BEGIN", .{});
defer _ = conn.exec("ROLLBACK", .{}) catch {};

// ... test operations ...
```

## Debugging Failed Tests

### View Test Output

```bash
# Run with verbose output
zig build test:integration --summary all

# Run specific test file (requires zig test)
zig test src/tests/integration/auth_test.zig
```

### Inspect Database

If a test fails, set `cleanup_on_failure = false` to inspect the database:

```zig
const test_config = mod.TestConfig{
    .database_url = mod.getTestDatabaseUrl(),
    .cleanup_on_failure = false, // Keep data for debugging
};
```

Then connect to the database:

```bash
psql plue_test
SELECT * FROM users;
SELECT * FROM repositories;
```

### Enable Logging

Set log level to see detailed output:

```bash
# Run with debug logging
ZIG_DEBUG=1 zig build test:integration
```

## CI Integration

For CI environments, create the test database automatically:

```bash
#!/bin/bash
# ci-test.sh

# Create test database
createdb plue_test || true

# Run migrations
psql -d plue_test -f db/schema.sql

# Set environment
export TEST_DATABASE_URL="postgres://localhost/plue_test"

# Run tests
cd server
zig build test:integration
```

## Future Enhancements

Potential improvements to the test suite:

1. **HTTP Client**: Implement TestClient for end-to-end HTTP testing
2. **Fixtures**: Add fixture system for complex test data
3. **Parallel Tests**: Run tests in parallel with separate databases
4. **Test Snapshots**: Compare database state snapshots
5. **Performance Tests**: Add benchmarks for database operations
6. **jj-ffi Tests**: Add tests for jj snapshot operations (once integrated)

## Troubleshooting

### Connection Refused

```
error: connection refused
```

**Solution**: Ensure PostgreSQL is running:
```bash
# macOS (Homebrew)
brew services start postgresql

# Linux (systemd)
systemctl start postgresql
```

### Database Does Not Exist

```
error: database "plue_test" does not exist
```

**Solution**: Create the test database:
```bash
createdb plue_test
psql -d plue_test -f db/schema.sql
```

### Permission Denied

```
error: permission denied for database plue_test
```

**Solution**: Grant permissions:
```bash
psql -c "GRANT ALL ON DATABASE plue_test TO your_user;"
```

### Port Already in Use

The tests don't actually bind to a port, but if you see port conflicts:

```zig
// The test server uses port 0 (no actual binding)
.port = 0,
```

## Contributing

When adding new integration tests:

1. Follow existing patterns in `auth_test.zig` and `repo_test.zig`
2. Use the TestContext helpers for common operations
3. Add cleanup for any new resources
4. Document test coverage in this README
5. Ensure tests are independent and can run in any order

## License

Same as the main Plue project.
