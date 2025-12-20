import { test, expect, selectors, TEST_DATA } from './fixtures';

const { user, repo, defaultBranch } = TEST_DATA;

test.describe('Tree View (Directory Browser)', () => {
  test.describe('Navigation', () => {
    test('should display breadcrumb with path', async ({ page }) => {
      await page.goto(`/${user}/${repo}/tree/${defaultBranch}/src`);

      const breadcrumb = page.locator(selectors.breadcrumb);
      await expect(breadcrumb).toBeVisible();

      // Should have user, repo, branch, and path
      await expect(breadcrumb.locator('a').first()).toHaveText(user);
      await expect(breadcrumb).toContainText(repo);
      await expect(breadcrumb).toContainText(defaultBranch);
      await expect(breadcrumb).toContainText('src');
    });

    test('should navigate using breadcrumb links', async ({ page }) => {
      await page.goto(`/${user}/${repo}/tree/${defaultBranch}/src/components`);

      // Click on 'src' in breadcrumb
      const srcLink = page.locator(selectors.breadcrumb).getByRole('link', { name: 'src' });
      await srcLink.click();

      await expect(page).toHaveURL(new RegExp(`/tree/${defaultBranch}/src$`));
    });

    test('should navigate to root via repo name in breadcrumb', async ({ page }) => {
      await page.goto(`/${user}/${repo}/tree/${defaultBranch}/src`);

      const repoLink = page.locator(selectors.breadcrumb).getByRole('link', { name: repo });
      await repoLink.click();

      await expect(page).toHaveURL(`/${user}/${repo}`);
    });
  });

  test.describe('File Tree Display', () => {
    test('should display directory contents', async ({ page }) => {
      await page.goto(`/${user}/${repo}/tree/${defaultBranch}`);

      const fileTree = page.locator(selectors.fileTree);
      await expect(fileTree).toBeVisible();

      const items = page.locator(selectors.fileTreeItem);
      const count = await items.count();
      expect(count).toBeGreaterThan(0);
    });

    test('should sort directories before files', async ({ page }) => {
      await page.goto(`/${user}/${repo}/tree/${defaultBranch}`);

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
      await page.goto(`/${user}/${repo}/tree/${defaultBranch}`);

      const directory = page.locator(selectors.fileTreeDirectory).first();
      if (await directory.count() > 0) {
        const dirName = await directory.locator('.name').textContent();
        await directory.click();

        await expect(page).toHaveURL(new RegExp(`/tree/${defaultBranch}/${dirName}`));
      }
    });
  });
});

test.describe('Blob View (File Viewer)', () => {
  test.describe('File Display', () => {
    test('should display file viewer component', async ({ page }) => {
      await page.goto(`/${user}/${repo}/blob/${defaultBranch}/README.md`);

      const fileViewer = page.locator(selectors.fileViewer);
      await expect(fileViewer).toBeVisible();
    });

    test('should display filename in header', async ({ page }) => {
      await page.goto(`/${user}/${repo}/blob/${defaultBranch}/README.md`);

      const filename = page.locator(selectors.filename);
      await expect(filename).toBeVisible();
      await expect(filename).toHaveText('README.md');
    });

    test('should display line count in metadata', async ({ page }) => {
      await page.goto(`/${user}/${repo}/blob/${defaultBranch}/README.md`);

      const meta = page.locator(selectors.fileMeta);
      await expect(meta).toBeVisible();
      await expect(meta).toContainText('lines');
    });

    test('should display file content with line numbers', async ({ page }) => {
      await page.goto(`/${user}/${repo}/blob/${defaultBranch}/README.md`);

      const code = page.locator(`${selectors.fileViewer} pre code`);
      await expect(code).toBeVisible();

      // Check that line numbers are present (format: "   1  content")
      const content = await code.textContent();
      expect(content).toMatch(/^\s*1\s+/);
    });

    test('should apply syntax highlighting class based on extension', async ({ page }) => {
      await page.goto(`/${user}/${repo}/blob/${defaultBranch}/src/index.ts`);

      const code = page.locator(`${selectors.fileViewer} pre code`);
      await expect(code).toHaveClass(/lang-ts/);
    });
  });

  test.describe('Breadcrumb Navigation', () => {
    test('should display full path in breadcrumb', async ({ page }) => {
      await page.goto(`/${user}/${repo}/blob/${defaultBranch}/src/components/Button.tsx`);

      const breadcrumb = page.locator(selectors.breadcrumb);
      await expect(breadcrumb).toContainText(user);
      await expect(breadcrumb).toContainText(repo);
      await expect(breadcrumb).toContainText(defaultBranch);
      await expect(breadcrumb).toContainText('src');
      await expect(breadcrumb).toContainText('components');
      await expect(breadcrumb).toContainText('Button.tsx');
    });

    test('should navigate to directory via breadcrumb', async ({ page }) => {
      await page.goto(`/${user}/${repo}/blob/${defaultBranch}/src/components/Button.tsx`);

      const srcLink = page.locator(selectors.breadcrumb).getByRole('link', { name: 'src' });
      await srcLink.click();

      await expect(page).toHaveURL(new RegExp(`/tree/${defaultBranch}/src$`));
    });
  });

  test.describe('Repository Navigation from Blob', () => {
    test('should have Code tab active', async ({ page }) => {
      await page.goto(`/${user}/${repo}/blob/${defaultBranch}/README.md`);

      const activeTab = page.locator(`${selectors.repoNav} a.active`);
      await expect(activeTab).toHaveText('Code');
    });

    test('should navigate to Issues from blob view', async ({ page }) => {
      await page.goto(`/${user}/${repo}/blob/${defaultBranch}/README.md`);

      await page.locator(selectors.repoNav).getByRole('link', { name: /Issues/ }).click();
      await expect(page).toHaveURL(`/${user}/${repo}/issues`);
    });
  });
});
