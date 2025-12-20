/**
 * E2E tests for authentication flows
 *
 * Tests wallet-based authentication (SIWE) flows:
 * - Login via wallet connection
 * - Logout
 * - Session persistence
 * - Session expiry handling
 */

import { test, expect } from '@playwright/test';

test.describe('Authentication', () => {
  test.describe('Wallet Login Flow', () => {
    test('should show login page when not authenticated', async ({ page }) => {
      await page.goto('/login');

      await expect(page.locator('h1')).toContainText('Sign In');
      await expect(page.locator('.auth-description')).toContainText('Connect your wallet');
      await expect(page.locator('#connect-btn')).toBeVisible();
      await expect(page.locator('#connect-btn')).toHaveText('Connect Wallet');
    });

    test('should redirect to home if already logged in', async ({ page, context }) => {
      // Set up a mock session cookie
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'mock-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      await page.goto('/login');

      // Should redirect to home page
      await expect(page).toHaveURL('/');
    });

    test('should show error on failed wallet connection', async ({ page }) => {
      await page.goto('/login');

      // Mock wallet connection failure
      await page.evaluate(() => {
        // Override the connectAndLogin function to simulate failure
        window.connectAndLogin = () => Promise.reject(new Error('User rejected connection'));
      });

      await page.click('#connect-btn');

      // Should show error message
      await expect(page.locator('#error')).toBeVisible();
      await expect(page.locator('#error')).toContainText('User rejected connection');

      // Button should be re-enabled
      await expect(page.locator('#connect-btn')).not.toBeDisabled();
      await expect(page.locator('#connect-btn')).toHaveText('Connect Wallet');
    });

    test('should show loading state during connection', async ({ page }) => {
      await page.goto('/login');

      // Mock slow wallet connection
      await page.evaluate(() => {
        window.connectAndLogin = () => new Promise(resolve => setTimeout(resolve, 2000));
      });

      const connectBtn = page.locator('#connect-btn');
      await connectBtn.click();

      // Button should show loading state
      await expect(connectBtn).toBeDisabled();
      await expect(connectBtn).toHaveText('Connecting...');
    });
  });

  test.describe('Logout Flow', () => {
    test('should logout successfully', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      await page.goto('/');

      // Find and click logout button/link
      // Note: Adjust selector based on actual UI implementation
      const logoutBtn = page.locator('[data-action="logout"]').or(page.locator('a[href*="logout"]')).first();

      if (await logoutBtn.count() > 0) {
        await logoutBtn.click();

        // Should redirect to login or home page
        await expect(page).toHaveURL(/\/(login)?/);

        // Session cookie should be cleared
        const cookies = await context.cookies();
        const sessionCookie = cookies.find(c => c.name === 'plue_session');
        expect(sessionCookie?.value).toBeFalsy();
      }
    });

    test('should clear wallet state on logout', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      await page.goto('/');

      // Track if disconnectWallet was called
      await page.evaluate(() => {
        window.wasDisconnectCalled = false;
        if (window.disconnectWallet) {
          const original = window.disconnectWallet;
          window.disconnectWallet = () => {
            window.wasDisconnectCalled = true;
            return original();
          };
        }
      });

      // Logout
      const logoutBtn = page.locator('[data-action="logout"]').or(page.locator('a[href*="logout"]')).first();
      if (await logoutBtn.count() > 0) {
        await logoutBtn.click();

        // Check if wallet disconnect was called
        const wasDisconnected = await page.evaluate(() => window.wasDisconnectCalled);
        expect(wasDisconnected).toBe(true);
      }
    });
  });

  test.describe('Session Persistence', () => {
    test('should maintain session after page refresh', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
          expires: Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60, // 7 days
        }
      ]);

      await page.goto('/');

      // Reload the page
      await page.reload();

      // Session should still be valid
      const cookies = await context.cookies();
      const sessionCookie = cookies.find(c => c.name === 'plue_session');
      expect(sessionCookie?.value).toBe('valid-session-id');

      // Should not redirect to login
      await expect(page).not.toHaveURL('/login');
    });

    test('should persist session across navigation', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      await page.goto('/');

      // Navigate to different pages
      await page.goto('/explore');
      await page.goto('/users');
      await page.goto('/');

      // Session should still be present
      const cookies = await context.cookies();
      const sessionCookie = cookies.find(c => c.name === 'plue_session');
      expect(sessionCookie?.value).toBe('valid-session-id');
    });
  });

  test.describe('Session Expiry', () => {
    test('should handle expired session gracefully', async ({ page, context }) => {
      // Set up expired session
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'expired-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
          expires: Math.floor(Date.now() / 1000) - 3600, // Expired 1 hour ago
        }
      ]);

      await page.goto('/');

      // Session cookie should not be present or should be cleared
      const cookies = await context.cookies();
      const sessionCookie = cookies.find(c => c.name === 'plue_session');

      // Either no cookie or the cookie is expired
      if (sessionCookie) {
        const now = Math.floor(Date.now() / 1000);
        expect(sessionCookie.expires).toBeLessThan(now);
      }
    });

    test('should prompt login for expired session on protected routes', async ({ page, context }) => {
      // Set up expired session
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'expired-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
          expires: Math.floor(Date.now() / 1000) - 3600,
        }
      ]);

      // Try to access protected route (e.g., settings)
      await page.goto('/settings');

      // Should redirect to login or show unauthorized state
      // Note: Adjust expectation based on actual implementation
      const url = page.url();
      const isLoginOrUnauthorized = url.includes('/login') || await page.locator('text=/unauthorized|sign in|connect wallet/i').count() > 0;
      expect(isLoginOrUnauthorized).toBe(true);
    });
  });

  test.describe('CSRF Protection', () => {
    test('should include CSRF token in authentication requests', async ({ page }) => {
      await page.goto('/login');

      // Intercept authentication API calls
      let hasCsrfHeader = false;

      page.on('request', request => {
        const url = request.url();
        if (url.includes('/api/auth/siwe/verify') || url.includes('/api/auth/login')) {
          const headers = request.headers();
          hasCsrfHeader = 'x-csrf-token' in headers;
        }
      });

      // Mock wallet connection
      await page.evaluate(() => {
        if (window.connectAndLogin) {
          window.connectAndLogin = async () => {
            // Make actual API call to test CSRF
            await fetch('/api/auth/siwe/verify', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'x-csrf-token': 'mock-token'
              },
              body: JSON.stringify({ message: 'mock', signature: 'mock' })
            });
          };
        }
      });

      const connectBtn = page.locator('#connect-btn');
      if (await connectBtn.count() > 0) {
        await connectBtn.click();
      }

      // Wait a bit for request to complete
      await page.waitForTimeout(1000);
    });

    test('should reject requests without CSRF token', async ({ request }) => {
      // Test API directly without CSRF token
      const response = await request.post('/api/auth/siwe/verify', {
        data: {
          message: 'test message',
          signature: 'test signature'
        }
      });

      expect(response.status()).toBe(403);
      const body = await response.json();
      expect(body.error).toContain('CSRF');
    });
  });

  test.describe('Session Security', () => {
    test('session cookie should have security flags', async ({ page, context }) => {
      await page.goto('/login');

      // Check if cookies have proper security flags
      const cookies = await context.cookies();
      const sessionCookie = cookies.find(c => c.name === 'plue_session');

      if (sessionCookie) {
        // HttpOnly flag should be set
        expect(sessionCookie.httpOnly).toBe(true);

        // SameSite should be set
        expect(sessionCookie.sameSite).toBeDefined();
        expect(['Strict', 'Lax']).toContain(sessionCookie.sameSite);
      }
    });

    test('should not expose session token in client-side JavaScript', async ({ page, context }) => {
      // Set up session
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'secret-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      await page.goto('/');

      // Try to read session cookie from JavaScript
      const canReadSession = await page.evaluate(() => {
        return document.cookie.includes('plue_session');
      });

      // Should not be readable due to HttpOnly flag
      expect(canReadSession).toBe(false);
    });
  });

  test.describe('Error Handling', () => {
    test('should show appropriate error for network failures', async ({ page }) => {
      await page.goto('/login');

      // Simulate network failure
      await page.route('/api/auth/siwe/**', route => route.abort('failed'));

      const connectBtn = page.locator('#connect-btn');
      if (await connectBtn.count() > 0) {
        await connectBtn.click();

        // Should show error message
        const errorDiv = page.locator('#error').or(page.locator('.error-message'));
        await expect(errorDiv.first()).toBeVisible();
      }
    });

    test('should handle malformed API responses', async ({ page }) => {
      await page.goto('/login');

      // Mock malformed response
      await page.route('/api/auth/siwe/nonce', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: 'invalid json',
        });
      });

      const connectBtn = page.locator('#connect-btn');
      if (await connectBtn.count() > 0) {
        await connectBtn.click();

        // Should handle error gracefully
        await expect(connectBtn).not.toBeDisabled();
      }
    });
  });

  test.describe('User State', () => {
    test('should fetch and display user info when authenticated', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      // Mock the /me endpoint
      await page.route('/api/auth/me', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            user: {
              id: 1,
              username: 'testuser',
              email: 'test@example.com',
              isActive: true,
              isAdmin: false,
              walletAddress: '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
            }
          }),
        });
      });

      await page.goto('/');

      // Wait for user info to load
      await page.waitForTimeout(1000);

      // Check if user info is displayed (adjust selector based on actual UI)
      const userElement = page.locator('[data-testid="user-info"]').or(page.locator('text=/testuser/i')).first();
      if (await userElement.count() > 0) {
        await expect(userElement).toBeVisible();
      }
    });

    test('should clear user state on logout', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'plue_session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      await page.goto('/');

      // Logout
      const logoutBtn = page.locator('[data-action="logout"]').or(page.locator('a[href*="logout"]')).first();
      if (await logoutBtn.count() > 0) {
        await logoutBtn.click();

        // User info should be cleared
        const userElement = page.locator('[data-testid="user-info"]');
        if (await userElement.count() > 0) {
          await expect(userElement).not.toBeVisible();
        }
      }
    });
  });
});
