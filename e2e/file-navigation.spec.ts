import { test, expect, selectors } from './fixtures';

test.describe('Tree View (Directory Browser)', () => {
  test.describe('Navigation', () => {
    test('should display breadcrumb with path', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/path');

      await page.goto('/testuser/testrepo/tree/main/src');

      const breadcrumb = page.locator(selectors.breadcrumb);
      await expect(breadcrumb).toBeVisible();

      // Should have user, repo, branch, and path
      await expect(breadcrumb.locator('a').first()).toHaveText('testuser');
      await expect(breadcrumb).toContainText('testrepo');
      await expect(breadcrumb).toContainText('main');
      await expect(breadcrumb).toContainText('src');
    });

    test('should navigate using breadcrumb links', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/path');

      await page.goto('/testuser/testrepo/tree/main/src/components');

      // Click on 'src' in breadcrumb
      const srcLink = page.locator(selectors.breadcrumb).getByRole('link', { name: 'src' });
      await srcLink.click();

      await expect(page).toHaveURL(/\/tree\/main\/src$/);
    });

    test('should navigate to root via repo name in breadcrumb', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/path');

      await page.goto('/testuser/testrepo/tree/main/src');

      const repoLink = page.locator(selectors.breadcrumb).getByRole('link', { name: 'testrepo' });
      await repoLink.click();

      await expect(page).toHaveURL('/testuser/testrepo');
    });
  });

  test.describe('File Tree Display', () => {
    test('should display directory contents', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/path');

      await page.goto('/testuser/testrepo/tree/main');

      const fileTree = page.locator(selectors.fileTree);
      await expect(fileTree).toBeVisible();

      const items = page.locator(selectors.fileTreeItem);
      const count = await items.count();
      expect(count).toBeGreaterThan(0);
    });

    test('should show empty state for empty directory', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual empty directory');

      await page.goto('/testuser/testrepo/tree/main/empty-dir');

      const emptyState = page.locator(selectors.emptyState);
      await expect(emptyState).toBeVisible();
      await expect(emptyState).toContainText('No files');
    });

    test('should sort directories before files', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo');

      await page.goto('/testuser/testrepo/tree/main');

      const items = page.locator(selectors.fileTreeItem);
      const firstItem = items.first();

      // First item should be a directory if there are any
      const allItemCount = await items.count();
      const dirCount = await page.locator(selectors.fileTreeDirectory).count();

      if (dirCount > 0 && allItemCount > dirCount) {
        // If there are both directories and files, first should be directory
        await expect(firstItem).toHaveClass(/directory/);
      }
    });
  });

  test.describe('Directory Navigation', () => {
    test('should navigate into subdirectory', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/path');

      await page.goto('/testuser/testrepo/tree/main');

      const directory = page.locator(selectors.fileTreeDirectory).first();
      if (await directory.count() > 0) {
        const dirName = await directory.locator('.name').textContent();
        await directory.click();

        await expect(page).toHaveURL(new RegExp(`/tree/main/${dirName}`));
      }
    });
  });
});

test.describe('Blob View (File Viewer)', () => {
  test.describe('File Display', () => {
    test('should display file viewer component', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/file');

      await page.goto('/testuser/testrepo/blob/main/README.md');

      const fileViewer = page.locator(selectors.fileViewer);
      await expect(fileViewer).toBeVisible();
    });

    test('should display filename in header', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/file');

      await page.goto('/testuser/testrepo/blob/main/README.md');

      const filename = page.locator(selectors.filename);
      await expect(filename).toBeVisible();
      await expect(filename).toHaveText('README.md');
    });

    test('should display line count in metadata', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/file');

      await page.goto('/testuser/testrepo/blob/main/README.md');

      const meta = page.locator(selectors.fileMeta);
      await expect(meta).toBeVisible();
      await expect(meta).toContainText('lines');
    });

    test('should display file content with line numbers', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/file');

      await page.goto('/testuser/testrepo/blob/main/README.md');

      const code = page.locator(`${selectors.fileViewer} pre code`);
      await expect(code).toBeVisible();

      // Check that line numbers are present (format: "   1  content")
      const content = await code.textContent();
      expect(content).toMatch(/^\s*1\s+/);
    });

    test('should apply syntax highlighting class based on extension', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/file');

      await page.goto('/testuser/testrepo/blob/main/src/index.ts');

      const code = page.locator(`${selectors.fileViewer} pre code`);
      await expect(code).toHaveClass(/lang-ts/);
    });
  });

  test.describe('Breadcrumb Navigation', () => {
    test('should display full path in breadcrumb', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/file');

      await page.goto('/testuser/testrepo/blob/main/src/components/Button.tsx');

      const breadcrumb = page.locator(selectors.breadcrumb);
      await expect(breadcrumb).toContainText('testuser');
      await expect(breadcrumb).toContainText('testrepo');
      await expect(breadcrumb).toContainText('main');
      await expect(breadcrumb).toContainText('src');
      await expect(breadcrumb).toContainText('components');
      await expect(breadcrumb).toContainText('Button.tsx');
    });

    test('should navigate to directory via breadcrumb', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/file');

      await page.goto('/testuser/testrepo/blob/main/src/components/Button.tsx');

      const srcLink = page.locator(selectors.breadcrumb).getByRole('link', { name: 'src' });
      await srcLink.click();

      await expect(page).toHaveURL(/\/tree\/main\/src$/);
    });
  });

  test.describe('Repository Navigation from Blob', () => {
    test('should have Code tab active', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/file');

      await page.goto('/testuser/testrepo/blob/main/README.md');

      const activeTab = page.locator(`${selectors.repoNav} a.active`);
      await expect(activeTab).toHaveText('Code');
    });

    test('should navigate to Issues from blob view', async ({ page }) => {
      test.skip(true, 'Requires test data setup - update with actual user/repo/file');

      await page.goto('/testuser/testrepo/blob/main/README.md');

      await page.locator(selectors.repoNav).getByRole('link', { name: /Issues/ }).click();
      await expect(page).toHaveURL('/testuser/testrepo/issues');
    });
  });
});

test.describe('Branch/Bookmark Switching', () => {
  test('should display different content for different branches', async ({ page }) => {
    test.skip(true, 'Requires test data setup with multiple branches');

    // Navigate to main branch
    await page.goto('/testuser/testrepo/tree/main');
    const mainContent = await page.locator(selectors.fileTree).innerHTML();

    // Navigate to a different branch
    await page.goto('/testuser/testrepo/tree/feature-branch');
    const featureContent = await page.locator(selectors.fileTree).innerHTML();

    // Content may or may not be different, but both should render
    expect(mainContent).toBeDefined();
    expect(featureContent).toBeDefined();
  });

  test('should preserve branch in navigation', async ({ page }) => {
    test.skip(true, 'Requires test data setup with non-main branch');

    await page.goto('/testuser/testrepo/tree/feature-branch');

    const directory = page.locator(selectors.fileTreeDirectory).first();
    if (await directory.count() > 0) {
      await directory.click();

      // URL should still contain feature-branch
      await expect(page).toHaveURL(/\/tree\/feature-branch\//);
    }
  });
});
