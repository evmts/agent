import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for Plue E2E tests
 *
 * Port configuration:
 * - Dev server (user): ASTRO_PORT=3000, API on 4000
 * - Test server (Playwright CI): ASTRO_PORT=4321, API on 4000
 *
 * To run tests against your running dev server:
 *   PLAYWRIGHT_BASE_URL=https://localhost:3000 pnpm test
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

// Port configuration - Claude Code uses different ports to avoid conflicts with user's dev server
// User dev: Astro on 3000, API on 4000, Edge on 8787
// Claude Code / CI: Astro on 4321, API on 4001, Edge on 8788
const ASTRO_PORT = process.env.ASTRO_PORT || '4321';
const API_PORT = process.env.API_PORT || '4001';
const EDGE_PORT = process.env.EDGE_PORT || '8788';
const BASE_URL = process.env.PLAYWRIGHT_BASE_URL || `https://localhost:${ASTRO_PORT}`;

export default defineConfig({
  testDir: './cases',

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
  globalSetup: './global-setup.ts',
  globalTeardown: './global-teardown.ts',

  use: {
    /* Base URL for navigation */
    baseURL: BASE_URL,

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
   *
   * Starts the Zig API server, Astro dev server, and edge worker on configured ports
   * Order matters: Astro must start before edge worker (edge proxies to Astro)
   * Claude Code uses different ports (4001/4321/8788) to avoid conflicts with user's dev server (4000/3000/8787)
   */
  webServer: [
    {
      command: `PORT=${API_PORT} zig build run`,
      cwd: '..',
      url: `http://localhost:${API_PORT}/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 180 * 1000,
      stdout: 'pipe',
      stderr: 'pipe',
    },
    {
      command: `PUBLIC_API_URL=http://localhost:${API_PORT} EDGE_URL=http://localhost:${EDGE_PORT} pnpm run dev --port ${ASTRO_PORT}`,
      cwd: '..',
      url: `https://localhost:${ASTRO_PORT}`,
      reuseExistingServer: !process.env.CI,
      timeout: 120 * 1000,
      stdout: 'pipe',
      stderr: 'pipe',
      ignoreHTTPSErrors: true,
    },
    {
      command: `pnpm dev --port ${EDGE_PORT} --var ORIGIN_HOST:localhost:${ASTRO_PORT}`,
      cwd: '../edge',
      url: `http://localhost:${EDGE_PORT}/api/auth/nonce`,
      reuseExistingServer: !process.env.CI,
      timeout: 60 * 1000,
      stdout: 'pipe',
      stderr: 'pipe',
    },
  ],
});
