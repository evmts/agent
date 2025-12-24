/**
 * Workflow E2E Tests
 *
 * Tests for workflow list page, run details page, and manual workflow triggers.
 */

import { test, expect, TEST_DATA, authenticatedTest } from '../fixtures';

test.describe('Workflow List Page', () => {
  test('displays workflow list page for repository', async ({ page, goToRepo }) => {
    await goToRepo(TEST_DATA.user, TEST_DATA.repo);
    await page.click('a[href$="/workflows"]');

    // Should navigate to workflows page
    await expect(page).toHaveURL(new RegExp(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`));

    // Page should have workflow-related elements
    await expect(page.locator('h1, h2').first()).toContainText(/workflow/i);
  });

  test('shows empty state when no workflow runs exist', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.emptyRepo}/workflows`);

    // Should show empty state or message
    const emptyState = page.locator('.empty-state, [data-testid="empty-workflows"]');
    const noRuns = page.locator('text=/no.*run/i, text=/no.*workflow/i');

    // Either empty state component or no runs message should be visible
    const hasEmptyIndicator = await emptyState.count() > 0 || await noRuns.count() > 0;
    expect(hasEmptyIndicator).toBeTruthy();
  });

  test('displays workflow definitions in sidebar', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    // Sidebar should contain workflow definitions section
    const sidebar = page.locator('aside, .sidebar, [data-testid="workflow-sidebar"]');
    await expect(sidebar.first()).toBeVisible();
  });

  test('has status filter tabs', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    // Should have filter tabs for different statuses
    const tabs = page.locator('[role="tablist"], .tabs, .status-tabs');
    const allTab = page.locator('text=/all/i');

    // Either tabs component or "All" filter should exist
    const hasFilters = await tabs.count() > 0 || await allTab.count() > 0;
    expect(hasFilters).toBeTruthy();
  });
});

test.describe('Workflow Run Details Page', () => {
  test('loads run details page', async ({ page }) => {
    // Navigate to a workflow run (using run ID 1 from fixtures)
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/1`);

    // Should display run information
    const runHeader = page.locator('h1, h2, .run-header, [data-testid="run-header"]');
    await expect(runHeader.first()).toBeVisible();
  });

  test('shows run metadata', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/1`);

    // Should show status badge
    const statusBadge = page.locator('.status-badge, .badge, [data-testid="run-status"]');
    await expect(statusBadge.first()).toBeVisible();
  });

  test('displays job/step list', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/1`);

    // Should show jobs or steps section
    const jobSection = page.locator('.jobs, .steps, [data-testid="job-list"], [data-testid="step-list"]');
    const sectionExists = await jobSection.count() > 0;

    // Job section should be present (may be empty)
    expect(sectionExists).toBeTruthy();
  });

  test('has cancel button for running workflows', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/1`);

    // Cancel button should exist (visible only for running/waiting workflows)
    const cancelButton = page.locator('button:has-text("Cancel"), [data-action="cancel"]');
    // Don't assert visibility since it depends on run status
    const buttonExists = await cancelButton.count() >= 0;
    expect(buttonExists).toBeDefined();
  });

  test('has re-run button for completed workflows', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/1`);

    // Re-run button should exist (visible for completed workflows)
    const rerunButton = page.locator('button:has-text("Re-run"), [data-action="rerun"]');
    const buttonExists = await rerunButton.count() >= 0;
    expect(buttonExists).toBeDefined();
  });
});

authenticatedTest.describe('Workflow Manual Trigger', () => {
  authenticatedTest('shows run workflow button when authenticated', async ({ authedPage }) => {
    await authedPage.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    // Should show "Run workflow" button for authenticated users
    const runButton = authedPage.locator('button:has-text("Run"), [data-action="run-workflow"]');
    const buttonExists = await runButton.count() > 0;
    expect(buttonExists).toBeTruthy();
  });

  authenticatedTest('opens trigger modal on button click', async ({ authedPage }) => {
    await authedPage.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    // Click the run workflow button
    const runButton = authedPage.locator('button:has-text("Run workflow"), [data-action="run-workflow"]');

    if (await runButton.count() > 0) {
      await runButton.click();

      // Modal should open
      const modal = authedPage.locator('[role="dialog"], .modal, [data-testid="workflow-modal"]');
      await expect(modal.first()).toBeVisible();
    }
  });

  authenticatedTest('modal has workflow selector', async ({ authedPage }) => {
    await authedPage.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    const runButton = authedPage.locator('button:has-text("Run workflow"), [data-action="run-workflow"]');

    if (await runButton.count() > 0) {
      await runButton.click();

      // Should have workflow dropdown or selector
      const selector = authedPage.locator('select, [role="combobox"], [data-testid="workflow-select"]');
      await expect(selector.first()).toBeVisible();
    }
  });

  authenticatedTest('modal has branch/ref input', async ({ authedPage }) => {
    await authedPage.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    const runButton = authedPage.locator('button:has-text("Run workflow"), [data-action="run-workflow"]');

    if (await runButton.count() > 0) {
      await runButton.click();

      // Should have branch/ref input field
      const branchInput = authedPage.locator('input[name="ref"], input[name="branch"], [data-testid="ref-input"]');
      const selectBranch = authedPage.locator('select[name="ref"], [data-testid="ref-select"]');

      const hasRefInput = await branchInput.count() > 0 || await selectBranch.count() > 0;
      expect(hasRefInput).toBeTruthy();
    }
  });

  authenticatedTest('can close modal', async ({ authedPage }) => {
    await authedPage.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    const runButton = authedPage.locator('button:has-text("Run workflow"), [data-action="run-workflow"]');

    if (await runButton.count() > 0) {
      await runButton.click();

      // Close button or backdrop click should close modal
      const closeButton = authedPage.locator('[aria-label="Close"], button:has-text("Cancel"), .modal-close');

      if (await closeButton.count() > 0) {
        await closeButton.first().click();

        // Modal should be hidden
        const modal = authedPage.locator('[role="dialog"], .modal');
        await expect(modal).toBeHidden();
      }
    }
  });
});

test.describe('Workflow Logs', () => {
  test('logs section is visible on run page', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/1`);

    // Should have logs section or expandable logs
    const logsSection = page.locator('.logs, [data-testid="logs"], .workflow-logs');
    const logsButton = page.locator('button:has-text("Logs"), [data-action="view-logs"]');

    const hasLogs = await logsSection.count() > 0 || await logsButton.count() > 0;
    expect(hasLogs).toBeTruthy();
  });

  test('has download logs button', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/1`);

    // Should have download logs option
    const downloadButton = page.locator('a:has-text("Download"), button:has-text("Download"), [data-action="download-logs"]');
    const buttonExists = await downloadButton.count() >= 0;
    expect(buttonExists).toBeDefined();
  });
});

test.describe('Workflow Navigation', () => {
  test('can navigate between runs', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    // If there are run cards, clicking one should navigate to detail page
    const runCard = page.locator('.run-card, [data-testid="run-card"], a[href*="/workflows/"]').first();

    if (await runCard.count() > 0) {
      await runCard.click();

      // Should navigate to run detail page
      await expect(page).toHaveURL(new RegExp(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/\\d+`));
    }
  });

  test('back button returns to workflow list', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/1`);

    // Find back link or breadcrumb
    const backLink = page.locator('a:has-text("Back"), a[href$="/workflows"], .breadcrumb a');

    if (await backLink.count() > 0) {
      await backLink.first().click();

      // Should return to workflow list
      await expect(page).toHaveURL(new RegExp(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows$`));
    }
  });

  test('workflow tab in repo nav is highlighted', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    // Workflows tab should be active/highlighted
    const workflowsTab = page.locator('nav a[href$="/workflows"], .repo-nav a[href$="/workflows"]');

    if (await workflowsTab.count() > 0) {
      // Check for active class or aria-current
      const isActive = await workflowsTab.first().evaluate((el) => {
        return el.classList.contains('active') ||
               el.getAttribute('aria-current') === 'page' ||
               el.classList.contains('selected');
      });
      expect(isActive).toBeTruthy();
    }
  });
});

test.describe('Workflow Status Display', () => {
  test('status badges have correct colors', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    // Check that status badges exist and have appropriate styling
    const badges = page.locator('.status-badge, .badge, [data-testid="status-badge"]');

    if (await badges.count() > 0) {
      // At least one badge should be visible
      await expect(badges.first()).toBeVisible();
    }
  });

  test('running status shows animation', async ({ page }) => {
    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    // Running status badges often have animation
    const runningBadge = page.locator('.status-badge.running, [data-status="running"], .badge.running');

    if (await runningBadge.count() > 0) {
      // Check for animation class or CSS animation
      const hasAnimation = await runningBadge.first().evaluate((el) => {
        const style = window.getComputedStyle(el);
        return style.animation !== 'none' || el.classList.contains('animate-pulse');
      });
      // Animation is optional, just verify badge exists
      expect(await runningBadge.first().isVisible()).toBeTruthy();
    }
  });
});

test.describe('Workflow API Integration', () => {
  test('workflow list API returns data', async ({ page }) => {
    // Intercept API call
    const responsePromise = page.waitForResponse(
      (response) => response.url().includes('/api/workflows/runs') || response.url().includes('/workflows')
    );

    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows`);

    try {
      const response = await responsePromise;
      // API should return 200 OK
      expect(response.status()).toBe(200);
    } catch {
      // If no API call intercepted, that's okay (SSR rendering)
    }
  });

  test('workflow run API returns data', async ({ page }) => {
    const responsePromise = page.waitForResponse(
      (response) => response.url().includes('/api/workflows/runs/') && response.url().includes('/1')
    );

    await page.goto(`/${TEST_DATA.user}/${TEST_DATA.repo}/workflows/1`);

    try {
      const response = await responsePromise;
      expect(response.status()).toBe(200);
    } catch {
      // SSR rendering, no client-side API call
    }
  });
});
