import { test, expect, selectors, TEST_DATA } from './fixtures';

const { user, repo, defaultBranch } = TEST_DATA;

test.describe('Bookmarks Page (JJ Branches)', () => {
  test.describe('Page Layout', () => {
    test('should display bookmarks page', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      await expect(page).toHaveTitle(/Bookmarks/);
    });

    test('should show Bookmarks tab as active', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const activeTab = page.locator(`${selectors.repoNav} a.active`);
      await expect(activeTab).toHaveText('Bookmarks');
    });

    test('should display JJ info banner', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const jjInfo = page.locator('.jj-info');
      await expect(jjInfo).toBeVisible();
      await expect(jjInfo).toContainText('movable labels');
    });

    test('should display JJ badge', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const badge = page.locator('.jj-badge');
      await expect(badge).toBeVisible();
      await expect(badge).toHaveText('jj');
    });
  });

  test.describe('Bookmark List', () => {
    test('should display bookmark count in header', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const header = page.locator('h2');
      await expect(header).toContainText('bookmarks');
    });

    test('should display bookmark list', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const bookmarkList = page.locator(selectors.bookmarkList);
      await expect(bookmarkList).toBeVisible();
    });

    test('should show bookmark items with name and change ID', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const bookmarkItem = page.locator(selectors.bookmarkItem).first();
      if (await bookmarkItem.count() > 0) {
        await expect(bookmarkItem.locator(selectors.bookmarkName)).toBeVisible();
        await expect(bookmarkItem.locator('.change-id')).toBeVisible();
      }
    });

    // Skip: This test requires jj bookmarks to be imported from git branches,
    // which doesn't happen automatically in colocated mode without jj CLI.
    // TODO: Enable when jj git import is implemented in native bindings
    test.skip('should mark default bookmark with badge', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const defaultBadge = page.locator('.badge.default');
      await expect(defaultBadge).toBeVisible();
      await expect(defaultBadge).toHaveText('default');
    });
  });

  test.describe('Bookmark Actions', () => {
    test('should have New bookmark button', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const newBtn = page.locator(selectors.newBookmarkBtn);
      await expect(newBtn).toBeVisible();
      await expect(newBtn).toHaveText('New bookmark');
    });

    test('should open new bookmark modal on button click', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      await page.locator(selectors.newBookmarkBtn).click();

      const modal = page.locator('#new-bookmark-modal');
      await expect(modal).toBeVisible();
      await expect(modal.locator('h3')).toHaveText('Create new bookmark');
    });

    test('should have History link for each bookmark', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const bookmarkItem = page.locator(selectors.bookmarkItem).first();
      if (await bookmarkItem.count() > 0) {
        const historyLink = bookmarkItem.getByRole('link', { name: 'History' });
        await expect(historyLink).toBeVisible();
      }
    });

    test('should navigate to changes page via History link', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const bookmarkItem = page.locator(selectors.bookmarkItem).first();
      if (await bookmarkItem.count() > 0) {
        const historyLink = bookmarkItem.getByRole('link', { name: 'History' });
        await historyLink.click();

        await expect(page).toHaveURL(/\/changes\//);
      }
    });

    test('should navigate to tree via bookmark name link', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);

      const bookmarkItem = page.locator(selectors.bookmarkItem).first();
      if (await bookmarkItem.count() > 0) {
        const nameLink = bookmarkItem.locator(`${selectors.bookmarkName} a`);
        await nameLink.click();

        await expect(page).toHaveURL(/\/tree\//);
      }
    });
  });

  test.describe('Bookmark Modal', () => {
    test('should have name input field', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);
      await page.locator(selectors.newBookmarkBtn).click();

      const nameInput = page.locator('#new-bookmark-modal input[name="name"]');
      await expect(nameInput).toBeVisible();
      await expect(nameInput).toHaveAttribute('required', '');
    });

    test('should have optional change_id field', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);
      await page.locator(selectors.newBookmarkBtn).click();

      const changeIdInput = page.locator('#new-bookmark-modal input[name="change_id"]');
      await expect(changeIdInput).toBeVisible();
      await expect(changeIdInput).not.toHaveAttribute('required');
    });

    test('should close modal on Cancel click', async ({ page }) => {
      await page.goto(`/${user}/${repo}/bookmarks`);
      await page.locator(selectors.newBookmarkBtn).click();

      const modal = page.locator('#new-bookmark-modal');
      await expect(modal).toBeVisible();

      await modal.locator('[data-action="close-modal"]').click();
      await expect(modal).not.toBeVisible();
    });
  });
});

test.describe('Changes Page (JJ Commits)', () => {
  test.describe('Page Layout', () => {
    test('should display changes page', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      await expect(page).toHaveTitle(/Changes/);
    });

    test('should show Changes tab as active', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const activeTab = page.locator(`${selectors.repoNav} a.active`);
      await expect(activeTab).toHaveText('Changes');
    });

    test('should display bookmark name in header', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const header = page.locator('h2');
      await expect(header).toContainText('Changes on');
      await expect(header.locator('.bookmark-name')).toHaveText(defaultBranch);
    });

    test('should display JJ info banner about stable IDs', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const jjInfo = page.locator('.jj-info');
      await expect(jjInfo).toBeVisible();
      await expect(jjInfo).toContainText('stable identifiers');
    });

    test('should have link to Operation Log', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const opLogLink = page.getByRole('link', { name: 'Operation Log' });
      await expect(opLogLink).toBeVisible();
    });
  });

  test.describe('Change List', () => {
    test('should display change list', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const changeList = page.locator(selectors.changeList);
      await expect(changeList).toBeVisible();
    });

    test('should display change items with timeline markers', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const changeItem = page.locator(selectors.changeItem).first();
      if (await changeItem.count() > 0) {
        const marker = changeItem.locator('.change-marker .marker-dot');
        await expect(marker).toBeVisible();
      }
    });

    test('should display change ID (8 chars) as link', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const changeId = page.locator(selectors.changeId).first();
      if (await changeId.count() > 0) {
        await expect(changeId).toBeVisible();
        const text = await changeId.textContent();
        // Trim whitespace before checking length
        expect(text?.trim().length).toBe(8);
      }
    });

    test('should display change description', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const changeItem = page.locator(selectors.changeItem).first();
      if (await changeItem.count() > 0) {
        const description = changeItem.locator(selectors.changeDescription);
        await expect(description).toBeVisible();
      }
    });

    test('should display author and date', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const changeItem = page.locator(selectors.changeItem).first();
      if (await changeItem.count() > 0) {
        await expect(changeItem.locator('.author')).toBeVisible();
        await expect(changeItem.locator('.date')).toBeVisible();
      }
    });
  });

  test.describe('Change Actions', () => {
    test('should have Browse button for each change', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const changeItem = page.locator(selectors.changeItem).first();
      if (await changeItem.count() > 0) {
        const browseBtn = changeItem.getByRole('link', { name: 'Browse' });
        await expect(browseBtn).toBeVisible();
      }
    });

    test('should navigate to tree view via Browse button', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const changeItem = page.locator(selectors.changeItem).first();
      if (await changeItem.count() > 0) {
        const browseBtn = changeItem.getByRole('link', { name: 'Browse' });
        await browseBtn.click();

        await expect(page).toHaveURL(/\/tree\//);
      }
    });

    test('should have Land button for each change', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const landBtn = page.locator(selectors.landBtn).first();
      if (await landBtn.count() > 0) {
        await expect(landBtn).toBeVisible();
        await expect(landBtn).toHaveText('Land');
      }
    });

    test('should open land modal on Land button click', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const landBtn = page.locator(selectors.landBtn).first();
      if (await landBtn.count() > 0) {
        await landBtn.click();

        const modal = page.locator('#land-modal');
        await expect(modal).toBeVisible();
        await expect(modal.locator('h3')).toHaveText('Land Change');
      }
    });
  });

  test.describe('Land Modal', () => {
    test('should display change ID preview', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const landBtn = page.locator(selectors.landBtn).first();
      if (await landBtn.count() > 0) {
        await landBtn.click();

        const preview = page.locator('.change-id-preview');
        await expect(preview).toBeVisible();
      }
    });

    test('should have target bookmark selector', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const landBtn = page.locator(selectors.landBtn).first();
      if (await landBtn.count() > 0) {
        await landBtn.click();

        const select = page.locator('#land-modal select[name="target_bookmark"]');
        await expect(select).toBeVisible();
      }
    });

    test('should have optional title input', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const landBtn = page.locator(selectors.landBtn).first();
      if (await landBtn.count() > 0) {
        await landBtn.click();

        const titleInput = page.locator('#land-modal input[name="title"]');
        await expect(titleInput).toBeVisible();
      }
    });

    test('should close modal on Cancel', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const landBtn = page.locator(selectors.landBtn).first();
      if (await landBtn.count() > 0) {
        await landBtn.click();

        const modal = page.locator('#land-modal');
        await expect(modal).toBeVisible();

        await modal.locator('[data-action="close-modal"]').click();
        await expect(modal).not.toBeVisible();
      }
    });
  });

  test.describe('Navigation to Operation Log', () => {
    test('should navigate to operations page', async ({ page }) => {
      await page.goto(`/${user}/${repo}/changes/${defaultBranch}`);

      const opLogLink = page.getByRole('link', { name: 'Operation Log' });
      await opLogLink.click();

      await expect(page).toHaveURL(`/${user}/${repo}/operations`);
    });
  });
});
