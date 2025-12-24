# Implement Security Test Suites

## Priority: CRITICAL | Testing

## Problem

50+ security tests are empty placeholders that always pass:

**SQL Injection:** `server/src/tests/security/injection_test.zig`
```zig
test "user search with SQL injection payload should be safe" {
    try testing.expect(true);  // Always passes!
}
```

**Path Traversal:** `server/src/tests/security/path_traversal_test.zig`
```zig
test "path traversal attempt should be blocked" {
    try testing.expect(true);  // Always passes!
}
```

This creates a false sense of security with no actual protection verification.

## Task

### Phase 1: SQL Injection Tests

1. **Set up test database:**
   - Create test fixtures with known data
   - Use in-memory SQLite or test PostgreSQL instance
   - Implement cleanup between tests

2. **Implement injection tests in `injection_test.zig`:**
   ```zig
   test "user search with SQL injection payload should be safe" {
       const db = try setupTestDb();
       defer db.deinit();

       // Attempt SQL injection
       const result = try users.findByUsername(db, "'; DROP TABLE users; --");

       // Should return null (user not found), not crash
       try testing.expect(result == null);

       // Verify users table still exists
       const count = try db.query("SELECT COUNT(*) FROM users");
       try testing.expect(count >= 0);
   }
   ```

3. **Test payloads to implement:**
   - `'; DROP TABLE users; --`
   - `' OR '1'='1`
   - `'; INSERT INTO users VALUES(...); --`
   - `' UNION SELECT * FROM passwords --`
   - `1; WAITFOR DELAY '00:00:05'--` (timing attacks)

### Phase 2: Path Traversal Tests

4. **Implement path traversal tests:**
   ```zig
   test "path traversal with dot-dot should be blocked" {
       const result = resolveAndValidatePathSecure(alloc, "../../../etc/passwd", workspace);
       try testing.expect(result == error.PathTraversalBlocked);
   }

   test "path traversal with encoded dots should be blocked" {
       const result = resolveAndValidatePathSecure(alloc, "%2e%2e%2fetc/passwd", workspace);
       try testing.expect(result == error.PathTraversalBlocked);
   }
   ```

5. **Test payloads to implement:**
   - `../../../etc/passwd`
   - `....//....//etc/passwd`
   - `..%252f..%252f..%252fetc/passwd`
   - `/etc/passwd` (absolute path)
   - `file.txt\x00.png` (null byte)

### Phase 3: CSRF Tests

6. **Add CSRF tests:**
   - Request without token → 403
   - Request with invalid token → 403
   - Request with expired token → 403
   - Request with valid token → 200

### Phase 4: Rate Limiting Tests

7. **Add rate limiting tests:**
   - Exceed limit → 429 response
   - Wait for reset → requests allowed again
   - Different IPs have separate limits

### Phase 5: Auth Tests

8. **Add authentication tests:**
   - Invalid JWT → 401
   - Expired JWT → 401
   - JWT for deleted user → 401
   - Valid JWT → 200

## Acceptance Criteria

- [ ] 0 placeholder tests remaining (no `expect(true)`)
- [ ] All SQL injection tests use real database queries
- [ ] All path traversal tests use real filesystem operations
- [ ] Tests run in CI on every PR
- [ ] Coverage report shows security code is tested
- [ ] Tests fail when security code is removed (regression protection)
