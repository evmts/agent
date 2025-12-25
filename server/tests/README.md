# Server Tests

Test suites for the Zig server. Includes integration tests and security tests.

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `integration/` | Integration tests for API endpoints and workflows |
| `security/` | Security and penetration tests |

## Test Organization

```
tests/
├── integration/
│   ├── api_integration_test.zig    # API endpoint tests
│   ├── workflow_test.zig           # Workflow execution tests
│   └── git_test.zig                # Git operations tests
│
└── security/
    ├── auth_test.zig               # Authentication security tests
    ├── csrf_test.zig               # CSRF protection tests
    ├── rate_limit_test.zig         # Rate limiting tests
    └── injection_test.zig          # Injection attack tests
```

## Running Tests

```bash
# All tests
zig build test

# Zig tests only
zig build test:zig

# Specific test file
zig test server/tests/integration/api_integration_test.zig
```

## Integration Tests

Integration tests verify:
- API endpoint behavior
- Database operations
- Workflow execution
- Git operations (via jj-lib FFI)
- Authentication flows
- WebSocket/SSE streaming

Pattern:

```zig
test "workflow execution end-to-end" {
    // Setup test database
    const db = try setupTestDb();
    defer db.deinit();

    // Create test repository
    const repo = try createTestRepo(db);

    // Trigger workflow
    const run = try triggerWorkflow(repo.id, "test-workflow");

    // Verify execution
    try expectEqual(run.status, .completed);
    try expect(run.steps.len == 3);
}
```

## Security Tests

Security tests verify:
- SIWE authentication
- CSRF token validation
- Rate limiting enforcement
- SQL injection prevention
- XSS prevention
- Path traversal prevention
- Command injection prevention

Pattern:

```zig
test "CSRF protection blocks forged requests" {
    const server = try startTestServer();
    defer server.stop();

    // Make request without CSRF token
    const response = try server.post("/api/repos", .{
        .body = "{}",
        .headers = .{},
    });

    try expectEqual(response.status, 403);
}
```

## Test Utilities

Common test utilities:

| Utility | Purpose |
|---------|---------|
| `setupTestDb()` | Initialize test database |
| `createTestRepo()` | Create test repository |
| `createTestUser()` | Create test user |
| `startTestServer()` | Start test HTTP server |
| `makeRequest()` | Make authenticated request |
| `expectJson()` | Assert JSON response |

## CI Integration

Tests run in GitHub Actions on:
- Every push
- Every PR
- Scheduled daily runs

Test results are stored in the database and visible in the Plue UI.
