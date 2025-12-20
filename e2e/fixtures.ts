import { test as base, expect, type Page, type TestInfo } from '@playwright/test';

/**
 * Test context for correlation with backend metrics/logs
 */
interface TestContext {
  testId: string;
  testName: string;
  testFile: string;
  runId: string;
  startTime: number;
}

/**
 * Console log entry captured during test
 */
interface ConsoleLogEntry {
  type: string;
  text: string;
  timestamp: number;
}

/**
 * Network request entry for debugging
 */
interface NetworkEntry {
  url: string;
  method: string;
  status?: number;
  duration?: number;
  error?: string;
}

/**
 * Extended test fixtures for Plue E2E tests
 *
 * Includes:
 * - Navigation helpers
 * - Test context injection for backend correlation
 * - Console log capture
 * - Network request logging
 */
export const test = base.extend<{
  /** Navigate to a user's profile */
  goToUser: (username: string) => Promise<void>;
  /** Navigate to a repository */
  goToRepo: (username: string, repo: string) => Promise<void>;
  /** Navigate to a specific path in a repository */
  goToPath: (username: string, repo: string, type: 'tree' | 'blob', branch: string, path?: string) => Promise<void>;
  /** Current test context for debugging */
  testContext: TestContext;
  /** Captured console logs */
  consoleLogs: ConsoleLogEntry[];
  /** Captured network requests */
  networkLogs: NetworkEntry[];
}>({
  // Test context - automatically injected into all requests
  testContext: async ({ page }, use, testInfo) => {
    const context: TestContext = {
      testId: testInfo.testId,
      testName: testInfo.title,
      testFile: testInfo.file,
      runId: process.env.PLAYWRIGHT_RUN_ID || `local-${Date.now()}`,
      startTime: Date.now(),
    };

    // Inject test context into all API requests
    await page.route('**/api/**', async (route) => {
      const headers = {
        ...route.request().headers(),
        'X-Test-Id': context.testId,
        'X-Test-Name': context.testName,
        'X-Test-Run': context.runId,
      };
      await route.continue({ headers });
    });

    await use(context);
  },

  // Console log capture
  consoleLogs: async ({ page }, use, testInfo) => {
    const logs: ConsoleLogEntry[] = [];

    page.on('console', (msg) => {
      logs.push({
        type: msg.type(),
        text: msg.text(),
        timestamp: Date.now(),
      });
    });

    page.on('pageerror', (error) => {
      logs.push({
        type: 'error',
        text: error.message,
        timestamp: Date.now(),
      });
    });

    await use(logs);

    // Attach logs to test report on failure
    if (testInfo.status !== 'passed' && logs.length > 0) {
      await testInfo.attach('console-logs', {
        body: JSON.stringify(logs, null, 2),
        contentType: 'application/json',
      });
    }
  },

  // Network request logging
  networkLogs: async ({ page }, use, testInfo) => {
    const logs: NetworkEntry[] = [];
    const pendingRequests = new Map<string, { url: string; method: string; startTime: number }>();

    page.on('request', (request) => {
      pendingRequests.set(request.url(), {
        url: request.url(),
        method: request.method(),
        startTime: Date.now(),
      });
    });

    page.on('response', (response) => {
      const pending = pendingRequests.get(response.url());
      if (pending) {
        logs.push({
          url: pending.url,
          method: pending.method,
          status: response.status(),
          duration: Date.now() - pending.startTime,
        });
        pendingRequests.delete(response.url());
      }
    });

    page.on('requestfailed', (request) => {
      const pending = pendingRequests.get(request.url());
      if (pending) {
        logs.push({
          url: pending.url,
          method: pending.method,
          duration: Date.now() - pending.startTime,
          error: request.failure()?.errorText,
        });
        pendingRequests.delete(request.url());
      }
    });

    await use(logs);

    // Attach network logs to test report on failure
    if (testInfo.status !== 'passed' && logs.length > 0) {
      // Filter to just failed/slow requests for readability
      const interestingLogs = logs.filter(
        (l) => l.error || (l.status && l.status >= 400) || (l.duration && l.duration > 1000)
      );
      if (interestingLogs.length > 0) {
        await testInfo.attach('network-errors', {
          body: JSON.stringify(interestingLogs, null, 2),
          contentType: 'application/json',
        });
      }
    }
  },

  goToUser: async ({ page }, use) => {
    await use(async (username: string) => {
      await page.goto(`/${username}`);
    });
  },

  goToRepo: async ({ page }, use) => {
    await use(async (username: string, repo: string) => {
      await page.goto(`/${username}/${repo}`);
    });
  },

  goToPath: async ({ page }, use) => {
    await use(async (username: string, repo: string, type: 'tree' | 'blob', branch: string, path?: string) => {
      const url = path
        ? `/${username}/${repo}/${type}/${branch}/${path}`
        : `/${username}/${repo}/${type}/${branch}`;
      await page.goto(url);
    });
  },
});

export { expect };

/**
 * Test data constants - synced with e2e/seed.ts
 * These are automatically created by the global setup before tests run.
 */
export const TEST_DATA = {
  user: 'e2etest',
  repo: 'testrepo',
  emptyRepo: 'emptyrepo',
  defaultBranch: 'main',
} as const;

/**
 * Page object helpers for common selectors
 */
export const selectors = {
  // Navigation
  breadcrumb: '.breadcrumb',
  repoNav: '.repo-nav',

  // File tree
  fileTree: '.file-tree',
  fileTreeItem: '.file-tree-item',
  fileTreeDirectory: '.file-tree-item.directory',

  // File viewer
  fileViewer: '.file-viewer',
  fileHeader: '.file-header',
  filename: '.file-header .filename',
  fileMeta: '.file-header .meta',

  // Repository page
  cloneUrl: '.clone-url-input',
  readme: '.markdown-body',

  // Bookmarks page
  bookmarkList: '.bookmark-list',
  bookmarkItem: '.bookmark-item',
  bookmarkName: '.bookmark-name',
  newBookmarkBtn: '[data-action="new-bookmark"]',

  // Changes page
  changeList: '.change-list',
  changeItem: '.change-item',
  changeId: '.change-id',
  changeDescription: '.change-description',
  landBtn: '[data-action="land"]',

  // Common
  emptyState: '.empty-state',
  badge: '.badge',
  container: '.container',
} as const;

/**
 * Authenticated test fixture for tests requiring login
 *
 * Usage:
 * ```typescript
 * import { authenticatedTest } from './fixtures';
 *
 * authenticatedTest('should access settings', async ({ authedPage }) => {
 *   await authedPage.goto('/settings');
 *   // User is already logged in
 * });
 * ```
 */
export const authenticatedTest = base.extend<{
  /** Page with authenticated session */
  authedPage: Page;
  /** Authenticated user info */
  authedUser: { username: string; id: number };
}>({
  authedUser: async ({}, use) => {
    // Use the seeded test user
    await use({ username: TEST_DATA.user, id: 7 });
  },

  authedPage: async ({ page, context, authedUser }, use) => {
    // Create a valid session for the test user
    // This requires the test user to exist (created by global-setup)
    const response = await page.request.post('/api/auth/dev-login', {
      data: { username: authedUser.username },
    });

    if (response.ok()) {
      // Session cookie should be set automatically
      await use(page);
    } else {
      // Fallback: try to set session directly via cookie
      // This is for environments where dev-login isn't available
      console.warn('Dev login failed, some auth tests may be skipped');
      await use(page);
    }
  },
});

/**
 * Helper to check if we're in an authenticated context
 */
export async function isAuthenticated(page: Page): Promise<boolean> {
  const cookies = await page.context().cookies();
  return cookies.some(c => c.name === 'plue_session' && c.value.length > 0);
}

/**
 * Helper to get current user from session
 */
export async function getCurrentUser(page: Page): Promise<{ username: string } | null> {
  try {
    const response = await page.request.get('/api/auth/me');
    if (response.ok()) {
      return await response.json();
    }
  } catch {
    // Not authenticated
  }
  return null;
}
