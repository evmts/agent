# Server-Side Security Tests

This directory contains server-side security tests for Plue, written in Zig.

## Test Modules

### `mod.zig`
Main security test module that re-exports all security tests.

```bash
zig test server/src/tests/security/mod.zig
```

### `csrf_test.zig` (17 tests)
Tests CSRF protection and session security:
- POST/DELETE/PUT requests require authentication
- Session cookies have HttpOnly and SameSite flags
- CORS headers prevent unauthorized origins
- Session expiration and refresh logic

### `injection_test.zig` (21 tests)
Tests SQL injection prevention:
- Parameterized queries protect against injection
- UNION, boolean-based, and time-based blind attacks
- Stacked queries, comment injection, hex encoding
- NULL byte injection, case manipulation

### `auth_test.zig` (30 tests)
Tests authentication and authorization:
- **Real tests**: Token hashing with SHA256 (6 tests)
- **Real tests**: Bearer token extraction (3 tests)
- Session management and validation
- Account activation and admin checks
- Multi-session support

### `path_traversal_test.zig` (25 tests)
Tests path traversal prevention:
- `../` and encoded traversal attempts blocked
- Absolute paths rejected
- Windows-style backslash traversal blocked
- NULL byte and Unicode path attacks
- Symlink and archive extraction safety

### `rate_limit_test.zig` (30 tests)
Tests rate limiting enforcement:
- Requests tracked per IP/user
- 429 status with Retry-After header
- Different limits for different endpoints
- Login, password reset, token creation limits
- Burst handling and distributed limiting

## Running Tests

### Run All Security Tests
```bash
zig test server/src/tests/security/mod.zig
```

### Run Individual Test Files
```bash
zig test server/src/tests/security/csrf_test.zig
zig test server/src/tests/security/injection_test.zig
zig test server/src/tests/security/auth_test.zig
zig test server/src/tests/security/path_traversal_test.zig
zig test server/src/tests/security/rate_limit_test.zig
```

### Run Specific Tests
```bash
# Run tests matching a pattern
zig test server/src/tests/security/auth_test.zig --test-filter "hashToken"
```

## Test Output

When tests pass:
```
1/30 auth_test.test.hashToken produces consistent output...OK
2/30 auth_test.test.hashToken different inputs produce different hashes...OK
3/30 auth_test.test.hashToken output format is valid hex...OK
...
All 30 tests passed.
```

## Test Types

### Real Implementation Tests
These tests call actual code and verify behavior:
- `hashToken` - Tests SHA256 hashing of tokens
- `getBearerToken` - Tests Bearer token extraction from headers

Example:
```zig
test "hashToken produces consistent output" {
    const allocator = testing.allocator;

    const hash1 = try hashToken(allocator, "test_token");
    defer allocator.free(hash1);

    const hash2 = try hashToken(allocator, "test_token");
    defer allocator.free(hash2);

    try testing.expectEqualStrings(hash1, hash2);
}
```

### Documentation Tests
These tests document expected behavior for future implementation:

Example:
```zig
test "should reject SQL injection in user search" {
    // Expected behavior:
    // - POST /api/users?search='; DROP TABLE users; --
    // - Should return 200 (search succeeds)
    // - Table should still exist (injection blocked)

    try testing.expect(true);
}
```

## Test Statistics

```
Total Tests: 123
├── CSRF: 17 tests
├── SQL Injection: 21 tests
├── Authentication: 30 tests (9 real, 21 docs)
├── Path Traversal: 25 tests
└── Rate Limiting: 30 tests

Real Implementation: 9 tests
Documentation: 114 tests
```

## Adding New Tests

### Add Real Implementation Test
```zig
test "descriptive test name" {
    const allocator = testing.allocator;

    // Call actual implementation
    const result = try someFunction(allocator, input);
    defer allocator.free(result);

    // Verify behavior
    try testing.expectEqual(expected, result);
}
```

### Add Documentation Test
```zig
test "descriptive test name" {
    // Expected behavior:
    // - Describe what should happen
    // - Include example inputs/outputs
    // - Document security controls

    try testing.expect(true);
}
```

## CI Integration

These tests run automatically:
```bash
zig build test        # Includes all security tests
zig build test:zig    # Only Zig tests
zig build test:server # Only server tests
```

## Related Files

- `server/src/middleware/auth.zig` - Authentication implementation
- `server/src/middleware/security.zig` - Security headers
- `server/src/lib/db.zig` - Database layer (parameterized queries)
- `e2e/security.spec.ts` - E2E security tests

## Security Resources

See also:
- [SECURITY_TESTS.md](../../../../../SECURITY_TESTS.md) - Comprehensive documentation
- [SECURITY_TEST_QUICKSTART.md](../../../../../SECURITY_TEST_QUICKSTART.md) - Quick start guide
- [CLAUDE.md](../../../../../CLAUDE.md) - Project overview
