const { chromium } = require('playwright');

const TARGET_URL = 'http://localhost:8787';

(async () => {
  const browser = await chromium.launch({ headless: false, slowMo: 100 });
  const context = await browser.newContext();
  const page = await context.newPage();

  // Capture console logs
  page.on('console', msg => {
    console.log(`[CONSOLE ${msg.type()}] ${msg.text()}`);
  });

  // Capture page errors
  page.on('pageerror', error => {
    console.log(`[PAGE ERROR] ${error.message}`);
  });

  // Capture network requests and responses
  page.on('request', request => {
    if (request.url().includes('/api/')) {
      console.log(`[REQUEST] ${request.method()} ${request.url()}`);
    }
  });

  page.on('response', response => {
    if (response.url().includes('/api/')) {
      console.log(`[RESPONSE] ${response.status()} ${response.url()}`);
    }
  });

  try {
    console.log('=== Navigating to login page ===');
    await page.goto(`${TARGET_URL}/login`);
    console.log('Page loaded:', await page.title());

    // Find and click the Connect Wallet button
    console.log('\n=== Clicking Connect Wallet button ===');
    const connectBtn = page.locator('#connect-btn');
    await connectBtn.waitFor({ state: 'visible' });
    await connectBtn.click();

    // Wait for verify to complete
    await page.waitForResponse(resp => resp.url().includes('/api/auth/verify'));
    console.log('Verify completed!');

    // Wait a bit for any redirects or state changes
    await page.waitForTimeout(2000);

    // Check current URL
    console.log('\n=== Current state ===');
    console.log('URL:', page.url());

    // Check for any visible errors
    const errorDiv = page.locator('#error');
    if (await errorDiv.isVisible()) {
      console.log('Error visible:', await errorDiv.textContent());
    }

    // Check cookies
    const cookies = await context.cookies();
    console.log('Cookies:', cookies.map(c => c.name).join(', '));

    // Take screenshot
    await page.screenshot({ path: '/tmp/login-success.png', fullPage: true });
    console.log('📸 Screenshot saved: /tmp/login-success.png');

    console.log('\n✅ Login flow completed!');

  } catch (error) {
    console.error('❌ Test error:', error.message);
    await page.screenshot({ path: '/tmp/login-error.png', fullPage: true });
  } finally {
    await browser.close();
  }
})();
