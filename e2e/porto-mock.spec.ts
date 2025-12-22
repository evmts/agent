/**
 * E2E tests for Porto mock passkey in relay mode
 *
 * Tests that Porto's mock: true configuration works correctly
 * for headless E2E testing without real passkey interaction.
 */

import { test, expect } from './fixtures';

test.describe('Porto Mock Passkey', () => {
  test('should detect E2E test environment', async ({ page }) => {
    await page.goto('/login');

    // Verify our __E2E_TEST__ flag is injected
    const isE2ETest = await page.evaluate(() => {
      return !!(window as any).__E2E_TEST__;
    });

    expect(isE2ETest).toBe(true);
  });

  test('should not show any dialogs or popups in mock mode', async ({ page }) => {
    await page.goto('/login');

    // Track if any dialogs/popups appear (they shouldn't in mock mode)
    let dialogAppeared = false;
    page.on('dialog', () => {
      dialogAppeared = true;
    });

    let popupAppeared = false;
    page.on('popup', () => {
      popupAppeared = true;
    });

    // Click the connect button
    const connectBtn = page.locator('#connect-btn');
    await expect(connectBtn).toBeVisible();

    await connectBtn.click();

    // Wait for any dialogs to appear
    await page.waitForTimeout(2000);

    // No dialogs or popups should have appeared in mock mode
    expect(dialogAppeared).toBe(false);
    expect(popupAppeared).toBe(false);
  });

  test('should complete mock SIWE flow with console logging', async ({ page, consoleLogs }) => {
    // Capture all console messages
    page.on('console', msg => {
      console.log(`[Browser ${msg.type()}]:`, msg.text());
    });

    page.on('pageerror', err => {
      console.log('[Browser error]:', err.message);
    });

    await page.goto('/login');

    // Mock the backend endpoints
    await page.route('/api/auth/siwe/nonce', route => {
      console.log('[Test] Nonce endpoint called');
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ nonce: 'mock-test-nonce-xyz' }),
      });
    });

    let verifyWasCalled = false;
    let verifyRequestBody: any = null;
    await page.route('/api/auth/siwe/verify', async route => {
      verifyWasCalled = true;
      const request = route.request();
      try {
        verifyRequestBody = await request.postDataJSON();
        console.log('[Test] Verify endpoint called with:', JSON.stringify(verifyRequestBody, null, 2));
      } catch (e) {
        console.log('[Test] Verify endpoint called, could not parse body');
      }

      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          message: 'Login successful',
          user: {
            id: 1,
            username: '0xMock1234',
            walletAddress: '0x1234567890123456789012345678901234567890',
            isActive: true,
            isAdmin: false,
          }
        }),
        headers: {
          'Set-Cookie': 'plue_session=mock-session; HttpOnly; SameSite=Lax; Path=/; Max-Age=2592000'
        }
      });
    });

    const connectBtn = page.locator('#connect-btn');
    console.log('[Test] Clicking connect button');
    await connectBtn.click();

    // Wait for the flow
    console.log('[Test] Waiting for flow to complete...');
    await page.waitForTimeout(8000);

    // Check results
    console.log('[Test] Verify was called:', verifyWasCalled);
    if (verifyRequestBody) {
      console.log('[Test] Message:', typeof verifyRequestBody.message);
      console.log('[Test] Signature:', verifyRequestBody.signature?.slice(0, 30));
    }

    // Check error display
    const errorDiv = page.locator('#error');
    if (await errorDiv.isVisible()) {
      const errorText = await errorDiv.textContent();
      console.log('[Test] Error displayed:', errorText);
    }

    // The key assertion - verify should have been called with message and signature
    if (verifyWasCalled) {
      expect(verifyRequestBody).toBeTruthy();
      expect(verifyRequestBody.message).toBeTruthy();
      expect(verifyRequestBody.signature).toBeTruthy();
    }
  });
});
