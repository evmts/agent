import { test, expect, selectors, TEST_DATA } from './fixtures';

const { user, repo } = TEST_DATA;

test.describe('Repository Page', () => {
  test.describe('Navigation', () => {
    test('should display breadcrumb with user and repo', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const breadcrumb = page.locator(selectors.breadcrumb);
      await expect(breadcrumb).toBeVisible();
      await expect(breadcrumb.locator('a').first()).toHaveText(user);
    });

    test('should display repository navigation tabs', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const nav = page.locator(selectors.repoNav);
      await expect(nav).toBeVisible();

      // Check for main navigation links
      await expect(nav.getByRole('link', { name: 'Code' })).toBeVisible();
      await expect(nav.getByRole('link', { name: /Issues/ })).toBeVisible();
      await expect(nav.getByRole('link', { name: /Landing/ })).toBeVisible();
      await expect(nav.getByRole('link', { name: 'Bookmarks' })).toBeVisible();
      await expect(nav.getByRole('link', { name: /Changes/ })).toBeVisible();
    });

    test('should mark Code tab as active on repo page', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const codeLink = page.locator(`${selectors.repoNav} a.active`);
      await expect(codeLink).toHaveText('Code');
    });
  });

  test.describe('Clone URL', () => {
    test('should display clone URL', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const cloneUrl = page.locator(selectors.cloneUrl);
      await expect(cloneUrl).toBeVisible();
      await expect(cloneUrl).toContainText(`${user}/${repo}`);
    });

    test('should have copy button for clone URL', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const copyBtn = page.locator('.clone-url button');
      await expect(copyBtn).toBeVisible();
      await expect(copyBtn).toHaveText('Copy');
    });

    test('should have link to SSH keys settings', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const sshLink = page.locator('.ssh-key-link');
      await expect(sshLink).toBeVisible();
      await expect(sshLink).toHaveAttribute('href', '/settings/ssh-keys');
    });
  });

  test.describe('File Tree', () => {
    test('should display file tree on repo page', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const fileTree = page.locator(selectors.fileTree);
      await expect(fileTree).toBeVisible();
    });

    test('should display files and directories', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      // Should have at least one file or directory
      const items = page.locator(selectors.fileTreeItem);
      const count = await items.count();
      expect(count).toBeGreaterThan(0);
    });

    test('directories should have triangle icon', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const directory = page.locator(selectors.fileTreeDirectory).first();
      if (await directory.count() > 0) {
        const icon = directory.locator('.icon');
        await expect(icon).toHaveText('▸');
      }
    });

    test('files should have dot icon', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const file = page.locator(`${selectors.fileTreeItem}:not(.directory)`).first();
      if (await file.count() > 0) {
        const icon = file.locator('.icon');
        await expect(icon).toHaveText('·');
      }
    });

    test('clicking a directory should navigate to tree view', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const directory = page.locator(selectors.fileTreeDirectory).first();
      if (await directory.count() > 0) {
        const href = await directory.getAttribute('href');
        expect(href).toContain('/tree/');

        await directory.click();
        await expect(page).toHaveURL(/\/tree\//);
      }
    });

    test('clicking a file should navigate to blob view', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      const file = page.locator(`${selectors.fileTreeItem}:not(.directory)`).first();
      if (await file.count() > 0) {
        const href = await file.getAttribute('href');
        expect(href).toContain('/blob/');

        await file.click();
        await expect(page).toHaveURL(/\/blob\//);
      }
    });
  });

  test.describe('README Display', () => {
    test('should render README if present', async ({ page }) => {
      await page.goto(`/${user}/${repo}`);

      // README is rendered in a Markdown component
      const readme = page.locator(selectors.readme);
      // The seeded repo should have a README
      await expect(readme).toBeVisible();
    });
  });
});

test.describe('404 Handling', () => {
  test('should redirect to 404 for non-existent user', async ({ page }) => {
    await page.goto('/nonexistentuser12345xyz/somerepo');
    await expect(page).toHaveURL('/404');
  });

  test('should redirect to 404 for non-existent repo', async ({ page }) => {
    // Use existing user but non-existent repo
    await page.goto(`/${user}/nonexistentrepo12345xyz`);
    await expect(page).toHaveURL('/404');
  });
});
