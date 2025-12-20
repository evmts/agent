/**
 * E2E Test Database Seed Script
 *
 * Creates test data for Playwright e2e tests.
 * Run with: bun e2e/seed.ts
 */

import { sql } from "../db/client";
import { initRepo, repoExists, deleteRepo } from "../ui/lib/jj";
import { mkdir, writeFile, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);

const REPOS_DIR = `${process.cwd()}/repos`;

// Test data constants - these should match e2e/fixtures.ts
export const TEST_USER = {
  username: "e2etest",
  email: "e2etest@plue.local",
  displayName: "E2E Test User",
};

export const TEST_REPO = {
  name: "testrepo",
  description: "Test repository for e2e tests",
};

export const SECONDARY_REPO = {
  name: "emptyrepo",
  description: "Empty test repository",
};

/**
 * Clean up existing test data
 */
async function cleanup() {
  console.log("Cleaning up existing test data...");

  // Get test user ID
  const [user] = await sql<{ id: number }[]>`
    SELECT id FROM users WHERE username = ${TEST_USER.username}
  `;

  if (user) {
    // Delete repositories from database (cascade will handle related tables)
    await sql`DELETE FROM repositories WHERE user_id = ${user.id}`;

    // Delete user
    await sql`DELETE FROM users WHERE id = ${user.id}`;
  }

  // Clean up repo files
  const testUserRepoPath = `${REPOS_DIR}/${TEST_USER.username}`;
  if (existsSync(testUserRepoPath)) {
    await rm(testUserRepoPath, { recursive: true, force: true });
  }

  console.log("Cleanup complete");
}

/**
 * Create test user
 */
async function createTestUser(): Promise<number> {
  console.log(`Creating test user: ${TEST_USER.username}`);

  const [user] = await sql<{ id: number }[]>`
    INSERT INTO users (
      username,
      lower_username,
      email,
      lower_email,
      display_name,
      is_active
    ) VALUES (
      ${TEST_USER.username},
      ${TEST_USER.username.toLowerCase()},
      ${TEST_USER.email},
      ${TEST_USER.email.toLowerCase()},
      ${TEST_USER.displayName},
      true
    )
    ON CONFLICT (username) DO UPDATE SET
      email = EXCLUDED.email,
      display_name = EXCLUDED.display_name,
      is_active = true
    RETURNING id
  `;

  console.log(`Created user with ID: ${user.id}`);
  return user.id;
}

/**
 * Create test repository in database
 */
async function createTestRepo(
  userId: number,
  repoName: string,
  description: string
): Promise<number> {
  console.log(`Creating repository: ${repoName}`);

  const [repo] = await sql<{ id: number }[]>`
    INSERT INTO repositories (
      user_id,
      name,
      description,
      is_public,
      default_branch,
      default_bookmark
    ) VALUES (
      ${userId},
      ${repoName},
      ${description},
      true,
      'main',
      'main'
    )
    ON CONFLICT (user_id, name) DO UPDATE SET
      description = EXCLUDED.description
    RETURNING id
  `;

  console.log(`Created repository with ID: ${repo.id}`);
  return repo.id;
}

/**
 * Initialize repository on disk with jj
 */
async function initTestRepoOnDisk(
  username: string,
  repoName: string,
  withContent: boolean = true
) {
  console.log(`Initializing repo on disk: ${username}/${repoName}`);

  const repoPath = `${REPOS_DIR}/${username}/${repoName}`;

  // Remove if exists
  if (existsSync(repoPath)) {
    await rm(repoPath, { recursive: true, force: true });
  }

  if (withContent) {
    // Use the existing initRepo which creates a proper jj repository
    await initRepo(username, repoName);

    // Add some additional test files
    await addTestFiles(username, repoName);
  } else {
    // Create empty bare repo
    await mkdir(repoPath, { recursive: true });
    await execAsync(`git init --bare "${repoPath}"`);
  }

  console.log(`Repository initialized: ${repoPath}`);
}

/**
 * Add test files to repository
 */
async function addTestFiles(username: string, repoName: string) {
  console.log("Adding test files...");

  const tempDir = `/tmp/plue-e2e-seed-${Date.now()}`;
  const repoPath = `${REPOS_DIR}/${username}/${repoName}`;

  try {
    // Clone the repo
    await execAsync(`git clone "${repoPath}" "${tempDir}"`);

    // Configure git
    await execAsync(`git config user.name "E2E Test"`, { cwd: tempDir });
    await execAsync(`git config user.email "e2e@plue.local"`, { cwd: tempDir });

    // Create directory structure
    await mkdir(`${tempDir}/src`, { recursive: true });
    await mkdir(`${tempDir}/src/components`, { recursive: true });
    await mkdir(`${tempDir}/docs`, { recursive: true });

    // Create test files
    await writeFile(
      `${tempDir}/README.md`,
      `# ${repoName}

A test repository for e2e testing.

## Features
- File browsing
- Directory navigation
- Bookmark management
- Change history
`
    );

    await writeFile(
      `${tempDir}/src/index.ts`,
      `/**
 * Main entry point
 */
export function main() {
  console.log("Hello from ${repoName}");
}

main();
`
    );

    await writeFile(
      `${tempDir}/src/components/Button.tsx`,
      `interface ButtonProps {
  label: string;
  onClick: () => void;
}

export function Button({ label, onClick }: ButtonProps) {
  return <button onClick={onClick}>{label}</button>;
}
`
    );

    await writeFile(
      `${tempDir}/docs/guide.md`,
      `# User Guide

This is a test document for e2e testing.
`
    );

    await writeFile(
      `${tempDir}/package.json`,
      JSON.stringify(
        {
          name: repoName,
          version: "1.0.0",
          type: "module",
          main: "src/index.ts",
        },
        null,
        2
      )
    );

    // Commit and push
    await execAsync(`git add .`, { cwd: tempDir });
    await execAsync(`git commit -m "Add test files for e2e testing"`, {
      cwd: tempDir,
    });
    await execAsync(`git push origin main`, { cwd: tempDir });

    console.log("Test files added");
  } finally {
    // Cleanup temp dir
    await rm(tempDir, { recursive: true, force: true }).catch(() => {});
  }
}

/**
 * Create test bookmarks in database
 */
async function createTestBookmarks(repoId: number) {
  console.log("Creating test bookmarks...");

  // Main bookmark
  await sql`
    INSERT INTO bookmarks (repository_id, name, target_change_id, is_default)
    VALUES (${repoId}, 'main', 'main-change-id', true)
    ON CONFLICT (repository_id, name) DO UPDATE SET
      target_change_id = EXCLUDED.target_change_id,
      is_default = EXCLUDED.is_default
  `;

  // Feature bookmark
  await sql`
    INSERT INTO bookmarks (repository_id, name, target_change_id, is_default)
    VALUES (${repoId}, 'feature-test', 'feature-change-id', false)
    ON CONFLICT (repository_id, name) DO UPDATE SET
      target_change_id = EXCLUDED.target_change_id
  `;

  console.log("Bookmarks created");
}

/**
 * Create test issues
 */
async function createTestIssues(repoId: number, userId: number) {
  console.log("Creating test issues...");

  // Open issue
  await sql`
    INSERT INTO issues (repository_id, author_id, issue_number, title, body, state)
    VALUES (
      ${repoId},
      ${userId},
      1,
      'Test issue for e2e',
      'This is a test issue body for e2e testing.',
      'open'
    )
    ON CONFLICT (repository_id, issue_number) DO UPDATE SET
      title = EXCLUDED.title,
      body = EXCLUDED.body,
      state = EXCLUDED.state
  `;

  // Closed issue
  await sql`
    INSERT INTO issues (repository_id, author_id, issue_number, title, body, state, closed_at)
    VALUES (
      ${repoId},
      ${userId},
      2,
      'Closed test issue',
      'This issue has been closed.',
      'closed',
      NOW()
    )
    ON CONFLICT (repository_id, issue_number) DO UPDATE SET
      title = EXCLUDED.title,
      body = EXCLUDED.body,
      state = EXCLUDED.state,
      closed_at = EXCLUDED.closed_at
  `;

  console.log("Issues created");
}

/**
 * Create test landing requests
 */
async function createTestLandingRequests(repoId: number, userId: number) {
  console.log("Creating test landing requests...");

  await sql`
    INSERT INTO landing_queue (
      repository_id,
      change_id,
      target_bookmark,
      title,
      description,
      author_id,
      status
    ) VALUES (
      ${repoId},
      'test-change-id-1',
      'main',
      'Test landing request',
      'This is a test landing request for e2e testing.',
      ${userId},
      'pending'
    )
    ON CONFLICT DO NOTHING
  `;

  console.log("Landing requests created");
}

/**
 * Main seed function
 */
export async function seed() {
  console.log("Starting e2e database seed...\n");

  try {
    // Clean up first
    await cleanup();

    // Create test user
    const userId = await createTestUser();

    // Create main test repository
    const repoId = await createTestRepo(
      userId,
      TEST_REPO.name,
      TEST_REPO.description
    );

    // Initialize repo on disk with content
    await initTestRepoOnDisk(TEST_USER.username, TEST_REPO.name, true);

    // Create bookmarks
    await createTestBookmarks(repoId);

    // Create issues
    await createTestIssues(repoId, userId);

    // Create landing requests
    await createTestLandingRequests(repoId, userId);

    // Create empty secondary repo
    const emptyRepoId = await createTestRepo(
      userId,
      SECONDARY_REPO.name,
      SECONDARY_REPO.description
    );
    await initTestRepoOnDisk(TEST_USER.username, SECONDARY_REPO.name, false);

    console.log("\nE2E seed completed successfully!");
    console.log(`Test user: ${TEST_USER.username}`);
    console.log(`Test repo: ${TEST_USER.username}/${TEST_REPO.name}`);
    console.log(`Empty repo: ${TEST_USER.username}/${SECONDARY_REPO.name}`);

    return { userId, repoId, emptyRepoId };
  } catch (error) {
    console.error("Seed failed:", error);
    throw error;
  }
}

/**
 * Teardown function to clean up after tests
 */
export async function teardown() {
  console.log("Tearing down e2e test data...");
  await cleanup();
  console.log("Teardown complete");
}

// Run if executed directly
if (import.meta.main) {
  seed()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
