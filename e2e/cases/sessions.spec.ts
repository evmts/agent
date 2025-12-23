/**
 * E2E tests for AI Sessions functionality
 *
 * Tests:
 * - Sessions tab navigation
 * - Sessions list display
 * - Authentication redirects
 * - Session creation (when API is available)
 */

import { test, expect } from '@playwright/test';

test.describe('Sessions Tab', () => {
  test.describe('Navigation', () => {
    test('should navigate to sessions page when clicking sessions tab', async ({ page }) => {
      await page.goto('/');

      // Click the sessions tab
      const sessionsLink = page.locator('nav a[href="/sessions"]');
      await expect(sessionsLink).toBeVisible();
      await sessionsLink.click();

      // Should navigate to /sessions
      await expect(page).toHaveURL('/sessions');
    });

    test('sessions tab should be visible in header', async ({ page }) => {
      await page.goto('/');

      // Sessions link should be present in the header navigation
      const sessionsLink = page.locator('.site-header nav a[href="/sessions"]');
      await expect(sessionsLink).toBeVisible();
      await expect(sessionsLink).toHaveText('sessions');
    });

    test('sessions tab should have active class when on sessions page', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      // Mock auth me endpoint
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
            }
          }),
        });
      });

      // Mock sessions API
      await page.route('/api/sessions', route => {
        if (route.request().method() === 'GET') {
          route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({ sessions: [] }),
          });
        }
      });

      await page.goto('/sessions');

      // Should have active class on sessions link
      const sessionsLink = page.locator('.site-header nav a[href="/sessions"]');
      await expect(sessionsLink).toHaveClass(/active/);
    });
  });

  test.describe('Authentication', () => {
    test('should redirect to login when not authenticated', async ({ page }) => {
      await page.goto('/sessions');

      // Should redirect to login
      await expect(page).toHaveURL('/login');
    });

    test('should show sessions page when authenticated', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      // Mock auth me endpoint
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
            }
          }),
        });
      });

      // Mock sessions API to return empty list
      await page.route('/api/sessions', route => {
        if (route.request().method() === 'GET') {
          route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({ sessions: [] }),
          });
        }
      });

      await page.goto('/sessions');

      // Should show the sessions page title
      await expect(page.locator('h1')).toContainText('AI Sessions');
    });
  });

  test.describe('Sessions List', () => {
    test('should show empty state when no sessions', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      // Mock auth
      await page.route('/api/auth/me', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            user: { id: 1, username: 'testuser', email: 'test@example.com', isActive: true }
          }),
        });
      });

      // Mock empty sessions
      await page.route('/api/sessions', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ sessions: [] }),
        });
      });

      await page.goto('/sessions');

      // Should show empty state
      await expect(page.locator('.empty-state')).toBeVisible();
      await expect(page.locator('.empty-state-title')).toContainText('No sessions yet');
    });

    test('should show session list when sessions exist', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      // Mock auth
      await page.route('/api/auth/me', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            user: { id: 1, username: 'testuser', email: 'test@example.com', isActive: true }
          }),
        });
      });

      // Mock sessions with data
      await page.route('/api/sessions', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            sessions: [
              {
                id: 'session-1',
                title: 'Test Session 1',
                directory: '/home/user/project',
                model: 'claude-sonnet-4-20250514',
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString(),
                archived: false,
              },
              {
                id: 'session-2',
                title: 'Test Session 2',
                directory: '/home/user/another-project',
                model: 'claude-opus-4-20250514',
                createdAt: new Date(Date.now() - 86400000).toISOString(),
                updatedAt: new Date(Date.now() - 86400000).toISOString(),
                archived: true,
              },
            ]
          }),
        });
      });

      await page.goto('/sessions');

      // Should show session cards
      await expect(page.locator('.sessions-list')).toBeVisible();
      await expect(page.locator('.session-card')).toHaveCount(2);

      // First session
      await expect(page.locator('.session-card').first()).toContainText('Test Session 1');
      await expect(page.locator('.session-card').first()).toContainText('claude-sonnet-4');

      // Second session (archived)
      await expect(page.locator('.session-card').last()).toContainText('Test Session 2');
      await expect(page.locator('.archived-badge')).toBeVisible();
    });

    test('should navigate to session detail when clicking a session', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      // Mock auth
      await page.route('/api/auth/me', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            user: { id: 1, username: 'testuser', email: 'test@example.com', isActive: true }
          }),
        });
      });

      // Mock sessions
      await page.route('/api/sessions', route => {
        if (route.request().method() === 'GET' && !route.request().url().includes('session-1')) {
          route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
              sessions: [{
                id: 'session-1',
                title: 'Test Session',
                directory: '/home/user/project',
                createdAt: new Date().toISOString(),
              }]
            }),
          });
        }
      });

      await page.goto('/sessions');

      // Click on the session
      const sessionCard = page.locator('.session-card').first();
      await sessionCard.click();

      // Should navigate to session detail page
      await expect(page).toHaveURL('/sessions/session-1');
    });
  });

  test.describe('New Session Modal', () => {
    test('should open new session modal when clicking new session button', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      // Mock auth
      await page.route('/api/auth/me', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            user: { id: 1, username: 'testuser', email: 'test@example.com', isActive: true }
          }),
        });
      });

      // Mock sessions
      await page.route('/api/sessions', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ sessions: [] }),
        });
      });

      await page.goto('/sessions');

      // Click new session button
      const newSessionBtn = page.locator('#new-session-btn').or(page.locator('#new-session-empty-btn'));
      await newSessionBtn.first().click();

      // Modal should be visible
      await expect(page.locator('#new-session-modal')).toBeVisible();
      await expect(page.locator('.modal-header h2')).toContainText('New Session');
    });

    test('should close modal when clicking cancel', async ({ page, context }) => {
      // Set up authenticated session
      await context.addCookies([
        {
          name: 'session',
          value: 'valid-session-id',
          domain: 'localhost',
          path: '/',
          httpOnly: true,
          sameSite: 'Strict',
        }
      ]);

      // Mock auth and sessions
      await page.route('/api/auth/me', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            user: { id: 1, username: 'testuser', email: 'test@example.com', isActive: true }
          }),
        });
      });
      await page.route('/api/sessions', route => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ sessions: [] }),
        });
      });

      await page.goto('/sessions');

      // Open modal
      await page.locator('#new-session-empty-btn').click();
      await expect(page.locator('#new-session-modal')).toBeVisible();

      // Click cancel
      await page.locator('#cancel-btn').click();

      // Modal should be hidden
      await expect(page.locator('#new-session-modal')).not.toBeVisible();
    });
  });
});
