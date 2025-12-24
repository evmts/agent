# Implement Comprehensive Test Coverage

## Priority: MEDIUM | Quality

## Problem

Test coverage is critically low across all components:
- **Server (Zig):** ~40% effective (many placeholders)
- **Frontend (Astro):** ~10% (7 tests for 38+ components)
- **Runner (Python):** 0%
- **Edge (Cloudflare):** 0% (1 placeholder test)

## Task

### Phase 1: Server Security Tests

1. **Implement SQL injection tests:**
   - Location: `server/src/tests/security/injection_test.zig`
   - Replace all `expect(true)` with real tests
   - Test each DAO function with malicious input

2. **Implement path traversal tests:**
   - Location: `server/src/tests/security/path_traversal_test.zig`
   - Test file operations with `../`, encoded paths, symlinks

3. **Implement CSRF tests:**
   - Test missing token rejection
   - Test invalid token rejection
   - Test expired token rejection

### Phase 2: Frontend Unit Tests

4. **Add auth-helpers tests:**
   ```typescript
   // ui/lib/__tests__/auth-helpers.test.ts

   describe('validatePassword', () => {
     it('rejects passwords under 8 characters', () => {...});
     it('requires uppercase letter', () => {...});
     it('requires lowercase letter', () => {...});
     it('requires number', () => {...});
     it('requires special character', () => {...});
   });

   describe('validateCsrfToken', () => {
     it('accepts valid token', () => {...});
     it('rejects expired token', () => {...});
     it('rejects tampered token', () => {...});
   });
   ```

5. **Add cache tests:**
   ```typescript
   // ui/lib/__tests__/cache.test.ts

   describe('cacheWithTags', () => {
     it('sets correct Cache-Control header', () => {...});
     it('adds cache tags header', () => {...});
   });
   ```

6. **Add markdown tests:**
   - Test XSS prevention (javascript: URLs)
   - Test HTML escaping
   - Test all markdown features

### Phase 3: Runner Tests

7. **Create pytest suite:**
   ```python
   # runner/tests/test_tools.py

   class TestReadFile:
       def test_reads_file_in_workspace(self):
           ...

       def test_blocks_path_traversal(self):
           ...

       def test_blocks_symlink_escape(self):
           ...

   class TestShell:
       def test_executes_safe_command(self):
           ...

       def test_respects_timeout(self):
           ...

       def test_captures_output(self):
           ...
   ```

8. **Add streaming tests:**
   ```python
   # runner/tests/test_streaming.py

   def test_retry_on_network_error(mocker):
       ...

   def test_no_retry_on_client_error(mocker):
       ...

   def test_event_buffering(mocker):
       ...
   ```

### Phase 4: Edge Worker Tests

9. **Implement vitest tests:**
   ```typescript
   // edge/index.test.ts

   describe('caching', () => {
     it('caches responses with Cache-Control header', async () => {...});
     it('bypasses cache for authenticated users', async () => {...});
     it('includes build version in cache key', async () => {...});
   });

   describe('error handling', () => {
     it('returns 503 on origin failure', async () => {...});
     it('serves stale content when available', async () => {...});
   });

   describe('session detection', () => {
     it('detects session cookie', async () => {...});
     it('handles malformed cookies', async () => {...});
   });
   ```

### Phase 5: Integration Tests

10. **Add E2E tests for critical flows:**
    ```typescript
    // e2e/cases/security.spec.ts

    test('XSS in issue body is escaped', async ({ page }) => {
      // Create issue with XSS payload
      // Verify script doesn't execute
    });

    test('CSRF protection blocks cross-origin requests', async ({ page }) => {
      // Attempt state-changing request without token
      // Verify 403 response
    });
    ```

### Phase 6: CI Integration

11. **Add coverage requirements to CI:**
    ```yaml
    # .github/workflows/test.yml

    - name: Run tests with coverage
      run: |
        zig build test:coverage
        npm run test:coverage
        pytest --cov=runner

    - name: Check coverage thresholds
      run: |
        # Fail if coverage below 80%
        coverage report --fail-under=80
    ```

12. **Add coverage badges to README**

## Acceptance Criteria

- [ ] 0 placeholder tests remaining
- [ ] Server security tests: 100% of injection/traversal tests implemented
- [ ] Frontend auth-helpers: 100% coverage
- [ ] Runner tools: 80%+ coverage
- [ ] Edge worker: 80%+ coverage
- [ ] CI enforces coverage thresholds
- [ ] All new code requires tests in PR
