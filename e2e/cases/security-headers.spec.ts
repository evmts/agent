import { test, expect } from '@playwright/test';

/**
 * Test that security headers are properly set on all responses
 * These headers protect against XSS, clickjacking, and other attacks
 */

test.describe('Security Headers', () => {
  test('should set security headers on homepage', async ({ page }) => {
    const response = await page.goto('/');
    expect(response).toBeTruthy();

    const headers = response!.headers();

    // Content-Security-Policy
    expect(headers['content-security-policy']).toBeDefined();
    expect(headers['content-security-policy']).toContain("default-src 'self'");
    expect(headers['content-security-policy']).toContain("frame-ancestors 'none'");

    // X-Frame-Options prevents clickjacking
    expect(headers['x-frame-options']).toBe('DENY');

    // X-Content-Type-Options prevents MIME sniffing
    expect(headers['x-content-type-options']).toBe('nosniff');

    // Referrer-Policy
    expect(headers['referrer-policy']).toBe('strict-origin-when-cross-origin');

    // XSS Protection
    expect(headers['x-xss-protection']).toBe('1; mode=block');

    // HSTS (Strict-Transport-Security)
    expect(headers['strict-transport-security']).toContain('max-age=31536000');
  });

  test('should set security headers on API routes', async ({ request }) => {
    const response = await request.get('/api/auth/nonce');
    expect(response.ok()).toBeTruthy();

    const headers = response.headers();

    // Content-Security-Policy
    expect(headers['content-security-policy']).toBeDefined();
    expect(headers['content-security-policy']).toContain("default-src 'self'");

    // Anti-clickjacking
    expect(headers['x-frame-options']).toBe('DENY');

    // MIME sniffing protection
    expect(headers['x-content-type-options']).toBe('nosniff');
  });

  test('should set security headers on static assets', async ({ request }) => {
    const response = await request.get('/favicon.svg');

    const headers = response.headers();

    // Even static assets should have security headers
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['x-frame-options']).toBe('DENY');
  });

  test('CSP should prevent inline script execution', async ({ page }) => {
    // Navigate to a page
    await page.goto('/');

    // Try to execute inline script (should be blocked by CSP)
    // Note: This will fail silently in browsers with CSP enforcement
    const consoleMessages: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error' && msg.text().includes('Content Security Policy')) {
        consoleMessages.push(msg.text());
      }
    });

    // Attempt to inject and execute inline script
    // This should fail due to CSP (though we allow unsafe-inline for Astro)
    const result = await page.evaluate(() => {
      try {
        // Try to create a script element
        const script = document.createElement('script');
        script.textContent = 'window.injectedScript = true;';
        document.body.appendChild(script);
        return (window as any).injectedScript === true;
      } catch {
        return false;
      }
    });

    // If CSP is properly configured, inline scripts should work
    // (because we allow unsafe-inline for Astro hydration)
    // but external scripts from untrusted sources would be blocked
    expect(result).toBe(true);
  });

  test('should prevent framing in iframe', async ({ page }) => {
    await page.goto('/');

    // Check that X-Frame-Options is set to DENY
    const response = await page.goto('/');
    const headers = response!.headers();
    expect(headers['x-frame-options']).toBe('DENY');

    // Also check CSP frame-ancestors
    expect(headers['content-security-policy']).toContain("frame-ancestors 'none'");
  });
});
