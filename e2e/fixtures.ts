import { test as base, expect } from '@playwright/test';

/**
 * Extended test fixtures for Plue E2E tests
 */
export const test = base.extend<{
  /** Navigate to a user's profile */
  goToUser: (username: string) => Promise<void>;
  /** Navigate to a repository */
  goToRepo: (username: string, repo: string) => Promise<void>;
  /** Navigate to a specific path in a repository */
  goToPath: (username: string, repo: string, type: 'tree' | 'blob', branch: string, path?: string) => Promise<void>;
}>({
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
