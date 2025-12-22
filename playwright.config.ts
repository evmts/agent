import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for Plue E2E tests
 *
 * Optimized for debugging with:
 * - Traces on all failures (not just retries)
 * - Video recording on failure
 * - Screenshots on failure
 * - Console log capture
 * - JSON reporter for AI agent access
 *
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: './e2e',

  /* Run tests in parallel for speed */
  fullyParallel: true,

  /* Fail CI on test.only() */
  forbidOnly: !!process.env.CI,

  /* Retries - more in CI, none locally for faster feedback */
  retries: process.env.CI ? 2 : 0,

  /* Workers - single in CI for stability, parallel locally */
  workers: process.env.CI ? 1 : undefined,

  /* Test timeout - 30s default, can be overridden per test */
  timeout: 30000,

  /* Expect timeout for assertions */
  expect: {
    timeout: 10000,
  },

  /* Output directory for test artifacts */
  outputDir: './test-results',

  /*
   * Reporters:
   * - html: Interactive report for humans
   * - json: Machine-readable for AI agents (prometheus-mcp can read this)
   * - list: Console output during runs
   */
  reporter: [
    ['list'],
    ['html', { outputFolder: './playwright-report', open: 'never' }],
    ['json', { outputFile: './test-results/results.json' }],
  ],

  /* Global setup seeds the database before all tests */
  globalSetup: './e2e/global-setup.ts',
  globalTeardown: './e2e/global-teardown.ts',

  use: {
    /* Base URL for navigation */
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'https://localhost:4321',

    /*
     * Tracing: Capture on first failure AND retries
     * This ensures we always have traces for debugging
     */
    trace: 'retain-on-failure',

    /* Screenshots: Capture on failure */
    screenshot: 'only-on-failure',

    /* Video: Record on failure for complex flow debugging */
    video: 'retain-on-failure',

    /* Capture browser console logs */
    browserName: 'chromium',

    /*
     * Add test context headers for backend correlation
     * Backend can use these to tag metrics/logs with test info
     */
    extraHTTPHeaders: {
      'X-Test-Run': process.env.PLAYWRIGHT_RUN_ID || `local-${Date.now()}`,
    },

    /* Viewport for consistent screenshots */
    viewport: { width: 1280, height: 720 },

    /* Ignore HTTPS errors for local dev */
    ignoreHTTPSErrors: true,

    /* Action timeout */
    actionTimeout: 15000,

    /* Navigation timeout */
    navigationTimeout: 30000,
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    /* Uncomment to test on more browsers
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
    */
  ],

  /*
   * Web server configuration
   * Note: For full observability, run `docker-compose up -d` first
   * to ensure Prometheus/Grafana/Loki are available
   */
  webServer: {
    command: 'bun run dev',
    url: 'https://localhost:4321',
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000,
    stdout: 'pipe',
    stderr: 'pipe',
    ignoreHTTPSErrors: true,
  },
});
