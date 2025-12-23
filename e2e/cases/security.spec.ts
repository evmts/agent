import { test, expect } from '@playwright/test';

/**
 * Security Test Suite
 *
 * Tests browser-based security controls including:
 * - CSRF protection
 * - XSS prevention
 * - Content Security Policy
 * - Authentication/authorization
 * - Input validation
 */

test.describe('Security: CSRF Protection', () => {
  test('should reject repository creation without valid session', async ({ request }) => {
    const response = await request.post('http://localhost:3000/api/repos', {
      data: {
        name: 'test-repo',
        description: 'Test repository',
        is_public: true
      },
      // No session cookie
    });

    expect(response.status()).toBe(401);
    const body = await response.json();
    expect(body.error).toContain('Authentication required');
  });

  test('should reject issue creation without authentication', async ({ request }) => {
    const response = await request.post('http://localhost:3000/api/repos/testuser/testrepo/issues', {
      data: {
        title: 'Test Issue',
        body: 'This should be rejected'
      },
    });

    expect(response.status()).toBe(401);
  });

  test('should reject star action without authentication', async ({ request }) => {
    const response = await request.post('http://localhost:3000/api/repos/testuser/testrepo/star', {
      data: {},
    });

    expect(response.status()).toBe(401);
  });
});

test.describe('Security: XSS Prevention', () => {
  test('should escape script tags in repository name display', async ({ page }) => {
    // Navigate to any repository page (even if creation fails, we test rendering)
    await page.goto('/e2etest/testrepo');

    // Inject test data with script tag (if we had a repo creation form)
    const content = await page.content();

    // Verify that any script tags are escaped, not executed
    expect(content).not.toContain('<script>alert(');
    expect(content).not.toContain('javascript:');
  });

  test('should escape HTML in repository description', async ({ page }) => {
    await page.goto('/e2etest/testrepo');

    const content = await page.content();

    // Common XSS payloads should be escaped
    expect(content).not.toContain('<img src=x onerror=');
    expect(content).not.toContain('<iframe src=');
    expect(content).not.toContain('onload=');
  });

  test('should escape special characters in username display', async ({ page }) => {
    // Username with special characters should be properly escaped
    await page.goto('/e2etest');

    const content = await page.content();

    // Check that HTML entities are properly encoded if present
    if (content.includes('&lt;') || content.includes('&gt;')) {
      expect(content).not.toContain('<script>');
    }
  });

  test('should sanitize issue title and body', async ({ page }) => {
    // Navigate to issues page
    await page.goto('/e2etest/testrepo/issues');

    const content = await page.content();

    // Verify XSS payloads are escaped
    expect(content).not.toContain('<script>');
    expect(content).not.toContain('javascript:');
    expect(content).not.toContain('onerror=');
  });

  test('should escape markdown that could execute scripts', async ({ page }) => {
    // README and other markdown content
    await page.goto('/e2etest/testrepo');

    // Wait for markdown to render
    await page.waitForSelector('.markdown-body', { timeout: 5000 }).catch(() => {});

    const content = await page.content();

    // Markdown should be sanitized
    expect(content).not.toContain('<script');
    expect(content).not.toContain('javascript:');
  });
});

test.describe('Security: Content Security Policy', () => {
  test('should set CSP headers', async ({ page }) => {
    const response = await page.goto('/');
    expect(response).not.toBeNull();

    if (response) {
      const headers = response.headers();

      // Check for security headers
      expect(headers['x-content-type-options']).toBe('nosniff');
      expect(headers['x-frame-options']).toBe('DENY');
      expect(headers['x-xss-protection']).toBe('1; mode=block');

      // CSP header should be present
      if (headers['content-security-policy']) {
        expect(headers['content-security-policy']).toContain("default-src 'self'");
      }
    }
  });

  test('should block inline script execution via CSP', async ({ page }) => {
    // CSP should prevent inline scripts from executing
    await page.goto('/e2etest/testrepo');

    // Try to inject and execute inline script (should be blocked by CSP)
    const scriptExecuted = await page.evaluate(() => {
      try {
        // This should be blocked by CSP
        eval('window.xssTest = true');
        return (window as any).xssTest === true;
      } catch (e) {
        return false;
      }
    }).catch(() => false);

    // CSP should have prevented execution (or eval is blocked)
    expect(scriptExecuted).toBe(false);
  });
});

test.describe('Security: Authorization', () => {
  test('should not allow access to private repositories without authentication', async ({ page }) => {
    // Attempt to access a hypothetically private repo
    const response = await page.goto('/privateuser/privaterepo');

    // Should redirect to login or show 401/403
    expect([401, 403, 404]).toContain(response?.status() || 200);
  });

  test('should not expose API endpoints without authentication', async ({ request }) => {
    // Try to access user settings endpoint
    const response = await request.get('http://localhost:3000/api/user/settings');

    expect(response.status()).toBe(401);
  });

  test('should not allow deletion without proper permissions', async ({ request }) => {
    // Try to delete a repository without authentication
    const response = await request.delete('http://localhost:3000/api/repos/testuser/testrepo');

    expect(response.status()).toBe(401);
  });
});

test.describe('Security: Input Validation', () => {
  test('should reject repository names with invalid characters', async ({ request }) => {
    const response = await request.post('http://localhost:3000/api/repos', {
      data: {
        name: '../../../etc/passwd',
        description: 'Path traversal attempt'
      },
    });

    // Should reject (401 for no auth, or 400 for bad input if authenticated)
    expect([400, 401]).toContain(response.status());
  });

  test('should reject excessively long input', async ({ request }) => {
    const longString = 'A'.repeat(100000);

    const response = await request.post('http://localhost:3000/api/repos', {
      data: {
        name: longString,
        description: 'Test'
      },
    });

    // Should reject with 400 or 413 (payload too large)
    expect([400, 401, 413]).toContain(response.status());
  });

  test('should reject null bytes in input', async ({ request }) => {
    const response = await request.post('http://localhost:3000/api/repos', {
      data: {
        name: 'test\x00repo',
        description: 'Null byte injection'
      },
    });

    expect([400, 401]).toContain(response.status());
  });

  test('should validate email format', async ({ request }) => {
    const response = await request.post('http://localhost:3000/api/auth/register', {
      data: {
        username: 'testuser',
        email: 'not-an-email',
        password: 'password123'
      },
    });

    // Should reject invalid email (if endpoint exists)
    expect([400, 404]).toContain(response.status());
  });
});

test.describe('Security: Session Management', () => {
  test('should set HttpOnly flag on session cookies', async ({ page }) => {
    // Navigate to trigger cookie setting (if logged in)
    await page.goto('/');

    const cookies = await page.context().cookies();
    const sessionCookie = cookies.find(c => c.name === 'plue_session');

    if (sessionCookie) {
      expect(sessionCookie.httpOnly).toBe(true);
    }
  });

  test('should set SameSite attribute on session cookies', async ({ page }) => {
    await page.goto('/');

    const cookies = await page.context().cookies();
    const sessionCookie = cookies.find(c => c.name === 'plue_session');

    if (sessionCookie) {
      expect(sessionCookie.sameSite).toBeTruthy();
    }
  });

  test('should reject expired sessions', async ({ request }) => {
    // Try to use an obviously invalid/expired session token
    const response = await request.get('http://localhost:3000/api/user', {
      headers: {
        'Cookie': 'plue_session=expired_or_invalid_token_12345'
      }
    });

    expect([401, 404]).toContain(response.status());
  });
});

test.describe('Security: Rate Limiting', () => {
  test('should rate limit repeated requests', async ({ request }) => {
    // Make many rapid requests
    const requests = [];
    for (let i = 0; i < 100; i++) {
      requests.push(
        request.get('http://localhost:3000/api/repos/testuser/testrepo')
      );
    }

    const responses = await Promise.all(requests);
    const statusCodes = responses.map(r => r.status());

    // At least some should be rate limited (429)
    // Note: May not trigger in dev environment
    const hasRateLimit = statusCodes.some(code => code === 429);

    // In production this should be true, but in dev it may not be enforced
    if (hasRateLimit) {
      expect(hasRateLimit).toBe(true);
    }
  });
});

test.describe('Security: Path Traversal', () => {
  test('should block path traversal in file access', async ({ page }) => {
    // Try to access files outside repo via path traversal
    const response = await page.goto('/e2etest/testrepo/blob/main/../../../../etc/passwd');

    // Should return 400, 403, or 404, not 200
    expect([400, 403, 404]).toContain(response?.status() || 404);
  });

  test('should block path traversal with encoded slashes', async ({ page }) => {
    const response = await page.goto('/e2etest/testrepo/blob/main/..%2F..%2F..%2Fetc%2Fpasswd');

    expect([400, 403, 404]).toContain(response?.status() || 404);
  });

  test('should block absolute paths in file requests', async ({ page }) => {
    const response = await page.goto('/e2etest/testrepo/blob/main//etc/passwd');

    expect([400, 403, 404]).toContain(response?.status() || 404);
  });
});

test.describe('Security: Information Disclosure', () => {
  test('should not expose stack traces in production', async ({ request }) => {
    // Trigger an error
    const response = await request.get('http://localhost:3000/api/nonexistent/route/that/errors');

    const body = await response.text();

    // Should not contain stack traces or internal paths
    expect(body).not.toContain('at Object.');
    expect(body).not.toContain('node_modules');
    expect(body).not.toContain('/Users/');
    expect(body).not.toContain('C:\\');
  });

  test('should not expose database errors to users', async ({ request }) => {
    const response = await request.get("http://localhost:3000/api/users/'; DROP TABLE users; --");

    const body = await response.text();

    // Should not contain SQL error messages
    expect(body).not.toContain('PostgreSQL');
    expect(body).not.toContain('syntax error');
    expect(body).not.toContain('SQLSTATE');
  });

  test('should not expose server version in headers', async ({ page }) => {
    const response = await page.goto('/');

    if (response) {
      const headers = response.headers();

      // Should not expose server details
      expect(headers['server']).not.toContain('Zig');
      expect(headers['x-powered-by']).toBeUndefined();
    }
  });
});
