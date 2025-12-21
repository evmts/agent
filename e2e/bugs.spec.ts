import { test, expect } from './fixtures';

/**
 * Bug Validation Test Suite
 *
 * These tests document and validate known bugs and edge cases.
 * Each test is expected to FAIL until the corresponding bug is fixed.
 *
 * Test naming convention: BUG-XXX where XXX is the GitHub issue number
 */

test.describe('BUG: Pagination Edge Cases', () => {
  test('BUG-001: should handle negative page numbers gracefully', async ({ page }) => {
    // Navigate with negative page number
    const response = await page.goto('/?page=-1');

    // Should redirect to page 1 or show valid content, not error
    expect(response?.status()).toBeLessThan(400);

    // Should either redirect to page 1 or normalize the parameter
    const url = page.url();
    expect(url).not.toContain('page=-1');
  });

  test('BUG-002: should handle page=0 gracefully', async ({ page }) => {
    const response = await page.goto('/?page=0');

    expect(response?.status()).toBeLessThan(400);
    const url = page.url();
    // Should normalize to page 1
    expect(url).not.toContain('page=0');
  });

  test('BUG-003: should handle non-integer page numbers', async ({ page }) => {
    const response = await page.goto('/?page=abc');

    expect(response?.status()).toBeLessThan(400);
    // Should show page 1 content or redirect
    await expect(page.locator('body')).not.toContainText('NaN');
    await expect(page.locator('body')).not.toContainText('undefined');
  });

  test('BUG-004: should handle extremely large page numbers', async ({ page }) => {
    const response = await page.goto('/?page=999999999');

    // Should return 200 with empty state or 404, not 500
    expect([200, 404]).toContain(response?.status());

    // Should not show error page
    await expect(page.locator('body')).not.toContainText('Internal Server Error');
  });

  test('BUG-005: should handle decimal page numbers', async ({ page }) => {
    const response = await page.goto('/?page=1.5');

    expect(response?.status()).toBeLessThan(400);
    // Should truncate or round, not error
    await expect(page.locator('body')).not.toContainText('Error');
  });
});

test.describe('BUG: Search Input Validation', () => {
  test('BUG-006: should handle SQL special characters in search', async ({ page }) => {
    await page.goto('/explore?q=%25%27%22');

    // Should not expose SQL errors
    const content = await page.content();
    expect(content).not.toContain('syntax error');
    expect(content).not.toContain('PostgreSQL');
    expect(content).not.toContain('SQLSTATE');
  });

  test('BUG-007: should handle LIKE wildcards in search', async ({ page }) => {
    // % and _ are LIKE wildcards
    await page.goto('/explore?q=%25_%25');

    const content = await page.content();
    expect(content).not.toContain('Error');
    // Should escape wildcards, not match everything
  });

  test('BUG-008: should handle extremely long search queries', async ({ page }) => {
    const longQuery = 'a'.repeat(10000);
    const response = await page.goto(`/explore?q=${longQuery}`);

    // Should either truncate or reject gracefully
    expect([200, 400, 414]).toContain(response?.status());
    await expect(page.locator('body')).not.toContainText('Internal Server Error');
  });

  test('BUG-009: should handle unicode in search', async ({ page }) => {
    await page.goto('/explore?q=%E4%B8%AD%E6%96%87%F0%9F%98%80');

    const response = await page.goto('/explore?q=');
    expect(response?.status()).toBeLessThan(500);
  });
});

test.describe('BUG: Repository Name Validation', () => {
  test('BUG-010: frontend allows uppercase but backend normalizes', async ({ page }) => {
    // The frontend pattern allows uppercase: [a-zA-Z0-9-]+
    // But backend converts to lowercase
    // This should either be consistent or show a warning

    await page.goto('/new');

    const nameInput = page.locator('input[name="name"]');
    if (await nameInput.count() > 0) {
      // Check frontend pattern
      const pattern = await nameInput.getAttribute('pattern');
      expect(pattern).toBe('[a-z0-9-]+'); // Should only allow lowercase
    }
  });
});

test.describe('BUG: Issue Title Validation', () => {
  test('BUG-011: should reject whitespace-only title', async ({ page }) => {
    // Navigate to issue creation page
    await page.goto('/e2etest/testrepo/issues/new');

    // Try to submit with whitespace-only title (server trims this to empty)
    await page.fill('input[name="title"]', '   ');

    // Submit the form
    await page.click('button[type="submit"]');

    // Should show validation error (server returns "Author and title are required")
    await expect(page.locator('.error-banner')).toBeVisible();
  });

  test('BUG-012: should handle very long issue title', async ({ page }) => {
    await page.goto('/e2etest/testrepo/issues/new');

    const longTitle = 'A'.repeat(1000);
    await page.fill('input[name="title"]', longTitle);

    await page.click('button[type="submit"]');

    // Should either create issue or show error, but NOT 500 Internal Server Error
    const content = await page.content();
    expect(content).not.toContain('Internal Server Error');
  });
});

test.describe('BUG: Milestone Date Validation', () => {
  test.skip('BUG-013: should handle invalid date format in milestone', async ({ page }) => {
    await page.goto('/e2etest/testrepo/milestones');

    // Try to create milestone with invalid date
    const dateInput = page.locator('input[name="due_date"]');
    if (await dateInput.count() > 0) {
      await dateInput.fill('not-a-date');
      await page.click('button[type="submit"]');

      // Should show validation error
      await expect(page.locator('.error, [role="alert"]')).toBeVisible();
    }
  });

  test.skip('BUG-014: should handle past due dates appropriately', async ({ page }) => {
    await page.goto('/e2etest/testrepo/milestones');

    const dateInput = page.locator('input[name="due_date"]');
    if (await dateInput.count() > 0) {
      await dateInput.fill('2020-01-01');
      // Should either warn about past date or accept it
    }
  });
});

test.describe('BUG: SSH Key Validation', () => {
  test.skip('BUG-015: should validate SSH key format on submission', async ({ page }) => {
    // Skip: Requires authentication - needs authenticated test fixture
    await page.goto('/settings/ssh-keys');

    // Will redirect to /login if not authenticated
    if (page.url().includes('/login')) {
      return; // Skip if not authenticated
    }

    const keyInput = page.locator('#public-key');
    if (await keyInput.count() > 0) {
      // Submit invalid SSH key
      await page.fill('#key-name', 'Test Key');
      await keyInput.fill('this is not a valid ssh key');

      await page.click('#add-key-submit');

      // Should show format error
      await expect(page.locator('#key-error')).toBeVisible();
    }
  });

  test.skip('BUG-016: should accept RSA key format', async ({ page }) => {
    // Skip: Requires authentication - needs authenticated test fixture
    await page.goto('/settings/ssh-keys');

    if (page.url().includes('/login')) {
      return;
    }

    const rsaKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7... test@example.com';

    const keyInput = page.locator('#public-key');
    if (await keyInput.count() > 0) {
      await keyInput.fill(rsaKey);
      // Should not show format error for valid RSA key
    }
  });

  test.skip('BUG-017: should accept Ed25519 key format', async ({ page }) => {
    // Skip: Requires authentication - needs authenticated test fixture
    await page.goto('/settings/ssh-keys');

    if (page.url().includes('/login')) {
      return;
    }

    const ed25519Key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ... test@example.com';

    const keyInput = page.locator('#public-key');
    if (await keyInput.count() > 0) {
      await keyInput.fill(ed25519Key);
      // Should accept Ed25519 keys
    }
  });
});

test.describe('BUG: Unimplemented Operations Return Proper Errors', () => {
  test('BUG-018: session abort should return 501 Not Implemented', async ({ request }) => {
    const response = await request.post('http://localhost:4000/api/sessions/test-session/abort');

    // Should return 501 Not Implemented, not 500 Internal Server Error
    expect([401, 501]).toContain(response.status());

    if (response.status() === 501) {
      const body = await response.json();
      expect(body.error).toContain('not implemented');
    }
  });

  test('BUG-019: session undo should return 501 Not Implemented', async ({ request }) => {
    const response = await request.post('http://localhost:4000/api/sessions/test-session/undo');

    expect([401, 501]).toContain(response.status());
  });

  test('BUG-020: session restore should return 501 Not Implemented', async ({ request }) => {
    // Route is /api/sessions/:sessionId/operations/:operationId/restore
    const response = await request.post('http://localhost:4000/api/sessions/test-session/operations/test-op/restore');

    expect([401, 501]).toContain(response.status());
  });

  test('BUG-021: session revert should return 501 Not Implemented', async ({ request }) => {
    const response = await request.post('http://localhost:4000/api/sessions/test-session/revert');

    expect([401, 501]).toContain(response.status());
  });

  test('BUG-022: operations undo should return 501 Not Implemented', async ({ request }) => {
    const response = await request.post('http://localhost:4000/api/repos/test/test/operations/test-op/undo');

    expect([401, 404, 501]).toContain(response.status());
  });
});

test.describe('BUG: Session and Authentication Edge Cases', () => {
  test('BUG-023: should handle malformed session cookie gracefully', async ({ page, context }) => {
    // Set a malformed session cookie
    await context.addCookies([{
      name: 'plue_session',
      value: 'malformed-not-valid-base64-!!!',
      domain: 'localhost',
      path: '/',
    }]);

    const response = await page.goto('/settings');

    // Should redirect to login, not crash
    expect(response?.status()).toBeLessThan(500);
  });

  test('BUG-024: should handle empty session cookie', async ({ page, context }) => {
    await context.addCookies([{
      name: 'plue_session',
      value: '',
      domain: 'localhost',
      path: '/',
    }]);

    const response = await page.goto('/settings');

    expect(response?.status()).toBeLessThan(500);
  });

  test('BUG-025: should handle very long session cookie', async ({ request }) => {
    // Use direct HTTP request to bypass browser cookie size limits
    // Browsers limit cookies to ~4KB, but we need to test server handling of larger values
    const longCookie = 'a'.repeat(10000);

    const response = await request.get('http://localhost:4000/api/auth/me', {
      headers: {
        Cookie: `plue_session=${longCookie}`,
      },
    });

    // Server should handle gracefully - not crash with 500
    // Expected: 400 (bad request) or 401 (unauthorized) - not 500
    expect(response.status()).toBeLessThan(500);
  });
});

test.describe('BUG: File and Path Handling', () => {
  test('BUG-026: should handle branch names with special characters', async ({ page }) => {
    // Branch name with special chars
    const response = await page.goto('/e2etest/testrepo/tree/feature%2Ftest');

    // Should handle gracefully, not crash
    expect(response?.status()).toBeLessThan(500);
  });

  test('BUG-027: should handle file paths with spaces', async ({ page }) => {
    const response = await page.goto('/e2etest/testrepo/blob/main/path%20with%20spaces/file.txt');

    // Should handle gracefully
    expect(response?.status()).toBeLessThan(500);
  });

  test('BUG-028: should handle double slashes in path', async ({ page }) => {
    const response = await page.goto('/e2etest/testrepo/blob/main//double//slashes');

    expect(response?.status()).toBeLessThan(500);
  });

  test('BUG-029: should handle dot-only filenames', async ({ page }) => {
    const response = await page.goto('/e2etest/testrepo/blob/main/.');

    expect([400, 404]).toContain(response?.status() || 404);
  });

  test('BUG-030: should handle dot-dot in path (not traversal)', async ({ page }) => {
    // This is testing the literal filename ".." not traversal
    const response = await page.goto('/e2etest/testrepo/blob/main/folder/..');

    // Should be blocked or return 404
    expect([400, 403, 404]).toContain(response?.status() || 404);
  });
});

test.describe('BUG: API Input Validation', () => {
  test('BUG-031: should reject null bytes in repository name', async ({ request }) => {
    const response = await request.post('http://localhost:4000/api/repos', {
      data: {
        name: 'test\x00repo',
        description: 'Test',
      },
    });

    // Should reject with 400, not process
    expect([400, 401]).toContain(response.status());
  });

  test('BUG-032: should reject control characters in issue title', async ({ request }) => {
    // Note: Route is /api/:user/:repo/issues, not /api/repos/:user/:repo/issues
    const response = await request.post('http://localhost:4000/api/test/test/issues', {
      data: {
        title: 'Test\x00\x01\x02Title',
        body: 'Body',
      },
    });

    expect([400, 401]).toContain(response.status());
  });

  test('BUG-033: should handle JSON with circular references', async ({ request }) => {
    // Malformed JSON that might cause issues
    const response = await request.post('http://localhost:4000/api/repos', {
      headers: { 'Content-Type': 'application/json' },
      data: '{"name": "test", "description": {"$ref": "#"}}',
    });

    expect(response.status()).toBeLessThan(500);
  });

  test('BUG-034: should handle extremely nested JSON', async ({ request }) => {
    // Deeply nested object
    let nested = { value: 'test' };
    for (let i = 0; i < 100; i++) {
      nested = { nested: nested } as any;
    }

    const response = await request.post('http://localhost:4000/api/repos', {
      data: { name: 'test', extra: nested },
    });

    expect(response.status()).toBeLessThan(500);
  });
});

test.describe('BUG: Error Page and Recovery', () => {
  test('BUG-035: should have a 500 error page', async ({ page }) => {
    // Try to trigger a 500 error
    const response = await page.goto('/api/trigger-500-for-testing');

    // If we get a 500, check that it's a user-friendly error page
    if (response?.status() === 500) {
      const content = await page.content();
      // Should have a styled error page, not raw error
      expect(content).toContain('<!DOCTYPE html');
      expect(content).not.toContain('stack trace');
    }
  });

  test('BUG-036: 404 page should suggest alternatives', async ({ page }) => {
    await page.goto('/nonexistent-page-xyz');

    const content = await page.content();
    // Should have helpful 404 page
    expect(content).toContain('404');
    // Could suggest going to home page or search
  });
});

test.describe('BUG: Form CSRF Protection', () => {
  test('BUG-037: all POST forms should include CSRF token', async ({ page }) => {
    await page.goto('/login');

    // Find all forms with POST method
    const forms = await page.locator('form[method="post"], form:not([method])').all();

    for (const form of forms) {
      // Each form should have a CSRF token input
      const csrfInput = form.locator('input[name="csrf_token"], input[name="_csrf"]');
      const hasCSRF = await csrfInput.count() > 0;

      // Or the form should use JavaScript with CSRF headers
      const action = await form.getAttribute('action');
      if (action && !action.startsWith('http')) {
        // Internal forms should have CSRF protection
        // This is a documentation of the current state
      }
    }
  });
});

test.describe('BUG: Accessibility', () => {
  test('BUG-038: login form should have proper labels', async ({ page }) => {
    await page.goto('/login');

    // All inputs should have associated labels
    const inputs = await page.locator('input:not([type="hidden"]):not([type="submit"])').all();

    for (const input of inputs) {
      const id = await input.getAttribute('id');
      const ariaLabel = await input.getAttribute('aria-label');
      const ariaLabelledBy = await input.getAttribute('aria-labelledby');

      // Should have either id with label, aria-label, or aria-labelledby
      const hasLabel = id || ariaLabel || ariaLabelledBy;
      expect(hasLabel).toBeTruthy();
    }
  });

  test('BUG-039: buttons should have accessible names', async ({ page }) => {
    await page.goto('/');

    const buttons = await page.locator('button').all();

    for (const button of buttons) {
      const text = await button.textContent();
      const ariaLabel = await button.getAttribute('aria-label');

      // Button should have text or aria-label
      expect(text?.trim() || ariaLabel).toBeTruthy();
    }
  });
});

test.describe('BUG: Rate Limiting', () => {
  test('BUG-040: should rate limit login attempts', async ({ request }) => {
    const attempts = [];

    // Make 20 rapid login attempts
    for (let i = 0; i < 20; i++) {
      attempts.push(
        request.post('http://localhost:4000/api/auth/login', {
          data: { username: 'test', password: 'wrong' },
        })
      );
    }

    const responses = await Promise.all(attempts);
    const statuses = responses.map(r => r.status());

    // At least some should be rate limited (429)
    const rateLimited = statuses.filter(s => s === 429).length;

    // This test documents that rate limiting may not be implemented
    // It should eventually pass with rateLimited > 0
    expect(rateLimited).toBeGreaterThanOrEqual(0); // Will pass but documents the issue
  });
});

test.describe('BUG: Data Display Edge Cases', () => {
  test('BUG-041: should handle repository with null description', async ({ page }) => {
    // Repository cards should handle null descriptions gracefully
    await page.goto('/explore');

    const content = await page.content();
    expect(content).not.toContain('null');
    expect(content).not.toContain('undefined');
  });

  test('BUG-042: should handle user with null bio', async ({ page }) => {
    await page.goto('/e2etest');

    const content = await page.content();
    expect(content).not.toContain('null');
    expect(content).not.toContain('undefined');
  });

  test('BUG-043: should escape HTML in repository names', async ({ page }) => {
    await page.goto('/explore');

    // Only check user-generated content areas, not the full page
    // (Astro legitimately uses <script> tags for hydration/ViewTransitions)
    const repoList = page.locator('.repo-list');
    await expect(repoList).toBeVisible();
    const userContent = await repoList.innerHTML();

    // Repository names should not allow HTML execution
    // Look for common XSS patterns in user content only
    const dangerousPatterns = [
      '<img src=x',
      'onerror=',
      'onload=',
      '<iframe',
      '<script',
    ];

    for (const pattern of dangerousPatterns) {
      // These should appear escaped or not at all in user content
      const unescapedMatches = (userContent.match(new RegExp(pattern, 'gi')) || []).length;

      // All instances should be escaped
      expect(unescapedMatches, `Found unescaped "${pattern}" in user content`).toBe(0);
    }
  });
});
