/**
 * E2E Test Database Seed Script
 *
 * Creates test data for Playwright e2e tests.
 * Run with: bun e2e/seed.ts
 */

import { sql } from "../db";
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

// Test session for authenticated tests
export const TEST_SESSION_KEY = "e2e-test-session-key-for-playwright-tests";

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
 * Create test session for authenticated e2e tests
 */
async function createTestSession(userId: number, username: string) {
  console.log("Creating test session...");

  // Delete any existing test session
  await sql`DELETE FROM auth_sessions WHERE session_key = ${TEST_SESSION_KEY}`;

  // Create a test session that expires in 7 days
  await sql`
    INSERT INTO auth_sessions (session_key, user_id, username, is_admin, expires_at)
    VALUES (
      ${TEST_SESSION_KEY},
      ${userId},
      ${username},
      false,
      NOW() + INTERVAL '7 days'
    )
  `;

  console.log(`Test session created: ${TEST_SESSION_KEY}`);
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
      default_branch
    ) VALUES (
      ${userId},
      ${repoName},
      ${description},
      true,
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
    // Create empty jj workspace (with git for compatibility)
    await mkdir(repoPath, { recursive: true });
    await execAsync(`git init "${repoPath}"`);
    await execAsync(`git config user.name "E2E Test"`, { cwd: repoPath });
    await execAsync(`git config user.email "e2e@plue.local"`, { cwd: repoPath });
    // Create an initial empty commit so jj can colocate
    await execAsync(`git commit --allow-empty -m "Initial commit"`, { cwd: repoPath });
    // Initialize jj colocated
    await execAsync(`jj git init --colocate`, { cwd: repoPath }).catch(() => {
      console.log("jj init failed for empty repo (jj CLI may not be installed)");
    });
  }

  console.log(`Repository initialized: ${repoPath}`);
}

/**
 * Add test files to repository
 * Works directly in the repo since we use non-bare jj workspaces
 */
async function addTestFiles(username: string, repoName: string) {
  console.log("Adding test files...");

  const repoPath = `${REPOS_DIR}/${username}/${repoName}`;

  // Create directory structure
  await mkdir(`${repoPath}/src`, { recursive: true });
  await mkdir(`${repoPath}/src/components`, { recursive: true });
  await mkdir(`${repoPath}/docs`, { recursive: true });

  // Create test files
  await writeFile(
    `${repoPath}/README.md`,
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
    `${repoPath}/src/index.ts`,
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
    `${repoPath}/src/components/Button.tsx`,
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
    `${repoPath}/docs/guide.md`,
    `# User Guide

This is a test document for e2e testing.
`
  );

  await writeFile(
    `${repoPath}/package.json`,
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

  // Commit with git
  await execAsync(`git add .`, { cwd: repoPath });
  await execAsync(`git config user.name "E2E Test"`, { cwd: repoPath });
  await execAsync(`git config user.email "e2e@plue.local"`, { cwd: repoPath });
  await execAsync(`git commit -m "Add test files for e2e testing"`, {
    cwd: repoPath,
  });

  // Import git changes into jj
  await execAsync(`jj git import`, { cwd: repoPath }).catch(() => {
    // jj git import may fail if jj isn't properly initialized, ignore
  });

  // Update the main bookmark to point to the latest commit
  await execAsync(`jj bookmark set main -r @-`, { cwd: repoPath }).catch(() => {});

  console.log("Test files added");
}

/**
 * Create test bookmarks in database (if table exists)
 */
async function createTestBookmarks(repoId: number) {
  console.log("Creating test bookmarks...");

  try {
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
  } catch (error) {
    console.log("Skipping bookmarks (table may not exist)");
  }
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
 * Create test workflow definitions and runs
 */
async function createTestWorkflows(repoId: number, userId: number) {
  console.log("Creating test workflow definitions and runs...");

  try {
    // Create a workflow definition
    const [workflowDef] = await sql<{ id: number }[]>`
      INSERT INTO workflow_definitions (
        repository_id,
        name,
        file_path,
        triggers,
        image,
        plan,
        content_hash
      ) VALUES (
        ${repoId},
        'test-ci',
        '.plue/workflows/ci.py',
        ${JSON.stringify([{ type: 'push', branches: ['main'] }, { type: 'pull_request' }])}::jsonb,
        'ubuntu:22.04',
        ${JSON.stringify({
          name: 'test-ci',
          steps: [
            { id: 'step_1', name: 'Install deps', type: 'shell', config: { data: { cmd: 'echo "Installing..."' } }, depends_on: [] },
            { id: 'step_2', name: 'Run tests', type: 'shell', config: { data: { cmd: 'echo "Testing..."' } }, depends_on: ['step_1'] }
          ]
        })}::jsonb,
        'abc123'
      )
      ON CONFLICT (repository_id, name) DO UPDATE SET
        file_path = EXCLUDED.file_path,
        triggers = EXCLUDED.triggers
      RETURNING id
    `;

    // Create a successful workflow run
    const [successRun] = await sql<{ id: number }[]>`
      INSERT INTO workflow_runs (
        workflow_definition_id,
        trigger_type,
        trigger_payload,
        status,
        started_at,
        completed_at
      ) VALUES (
        ${workflowDef.id},
        'push',
        ${JSON.stringify({ ref: 'refs/heads/main', sha: 'abc123' })}::jsonb,
        'success',
        NOW() - INTERVAL '1 hour',
        NOW() - INTERVAL '50 minutes'
      )
      ON CONFLICT DO NOTHING
      RETURNING id
    `;

    if (successRun) {
      // Create workflow steps for the successful run
      await sql`
        INSERT INTO workflow_steps (
          run_id,
          step_id,
          name,
          step_type,
          config,
          status,
          started_at,
          completed_at,
          exit_code
        ) VALUES (
          ${successRun.id},
          'step_1',
          'Install deps',
          'shell',
          ${JSON.stringify({ data: { cmd: 'echo "Installing..."' } })}::jsonb,
          'success',
          NOW() - INTERVAL '1 hour',
          NOW() - INTERVAL '55 minutes',
          0
        )
        ON CONFLICT DO NOTHING
      `;

      await sql`
        INSERT INTO workflow_steps (
          run_id,
          step_id,
          name,
          step_type,
          config,
          status,
          started_at,
          completed_at,
          exit_code
        ) VALUES (
          ${successRun.id},
          'step_2',
          'Run tests',
          'shell',
          ${JSON.stringify({ data: { cmd: 'echo "Testing..."' } })}::jsonb,
          'success',
          NOW() - INTERVAL '55 minutes',
          NOW() - INTERVAL '50 minutes',
          0
        )
        ON CONFLICT DO NOTHING
      `;
    }

    // Create a failed workflow run
    await sql`
      INSERT INTO workflow_runs (
        workflow_definition_id,
        trigger_type,
        trigger_payload,
        status,
        started_at,
        completed_at,
        error_message
      ) VALUES (
        ${workflowDef.id},
        'push',
        ${JSON.stringify({ ref: 'refs/heads/feature', sha: 'def456' })}::jsonb,
        'failed',
        NOW() - INTERVAL '2 hours',
        NOW() - INTERVAL '1 hour 55 minutes',
        'Step "Run tests" failed with exit code 1'
      )
      ON CONFLICT DO NOTHING
    `;

    // Create a pending workflow run
    await sql`
      INSERT INTO workflow_runs (
        workflow_definition_id,
        trigger_type,
        trigger_payload,
        status
      ) VALUES (
        ${workflowDef.id},
        'manual',
        ${JSON.stringify({ triggered_by: 'e2etest' })}::jsonb,
        'pending'
      )
      ON CONFLICT DO NOTHING
    `;

    console.log("Workflow definitions and runs created");
  } catch (error) {
    console.log("Skipping workflows (tables may not exist):", error);
  }
}

/**
 * Create test landing requests (if table exists)
 */
async function createTestLandingRequests(repoId: number, userId: number) {
  console.log("Creating test landing requests...");

  try {
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
  } catch (error) {
    console.log("Skipping landing requests (table may not exist)");
  }
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

    // Create test session for authenticated tests
    await createTestSession(userId, TEST_USER.username);

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

    // Create workflow definitions and runs
    await createTestWorkflows(repoId, userId);

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
