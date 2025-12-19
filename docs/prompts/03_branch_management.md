# Branch Management Implementation

## Overview

Implement comprehensive branch management for Plue, including branch listing, creation, deletion, renaming, and protection rules. This feature should mirror Gitea's branch management capabilities while adapting to Plue's brutalist design and PostgreSQL/Bun stack.

## Core Features

### 1. Branch Operations
- **List Branches**: Display all branches with metadata (commit info, pusher, last updated)
- **Create Branch**: Create new branches from any commit/branch/tag
- **Delete Branch**: Soft-delete branches with protection checks
- **Rename Branch**: Rename branches with validation and protection updates
- **Restore Branch**: Restore previously deleted branches
- **Default Branch**: Set and update repository default branch

### 2. Branch Protection Rules
- **Rule Patterns**: Support exact branch names and glob patterns (e.g., `release/*`, `feature/**`)
- **Priority System**: Multiple rules can apply; higher priority wins
- **Push Protection**: Control who can push to protected branches
- **Force Push Control**: Allow/deny force pushes with allowlists
- **Merge Control**: Restrict who can merge PRs to protected branches
- **Status Checks**: Require CI/CD checks before merging
- **Required Approvals**: Minimum number of PR approvals required
- **File Pattern Protection**: Protect specific files/paths within branches

## Database Schema

### Branches Table

```sql
-- Stores branch metadata for pagination and tracking
CREATE TABLE IF NOT EXISTS branches (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  commit_id VARCHAR(40) NOT NULL,
  commit_message TEXT,
  pusher_id INTEGER REFERENCES users(id),
  is_deleted BOOLEAN DEFAULT false,
  deleted_by_id INTEGER REFERENCES users(id),
  deleted_at TIMESTAMP,
  commit_time TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);

CREATE INDEX idx_branches_repo ON branches(repository_id);
CREATE INDEX idx_branches_deleted ON branches(is_deleted);
```

### Protected Branches Table

```sql
-- Branch protection rules
CREATE TABLE IF NOT EXISTS protected_branches (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  rule_name VARCHAR(255) NOT NULL, -- Branch name or glob pattern
  priority BIGINT NOT NULL DEFAULT 0,

  -- Push protection
  can_push BOOLEAN NOT NULL DEFAULT false,
  enable_whitelist BOOLEAN DEFAULT false,
  whitelist_user_ids JSONB DEFAULT '[]',
  whitelist_team_ids JSONB DEFAULT '[]',
  whitelist_deploy_keys BOOLEAN DEFAULT false,

  -- Force push protection
  can_force_push BOOLEAN NOT NULL DEFAULT false,
  enable_force_push_allowlist BOOLEAN DEFAULT false,
  force_push_allowlist_user_ids JSONB DEFAULT '[]',
  force_push_allowlist_team_ids JSONB DEFAULT '[]',
  force_push_allowlist_deploy_keys BOOLEAN DEFAULT false,

  -- Merge protection
  enable_merge_whitelist BOOLEAN DEFAULT false,
  merge_whitelist_user_ids JSONB DEFAULT '[]',
  merge_whitelist_team_ids JSONB DEFAULT '[]',

  -- Status checks
  enable_status_check BOOLEAN DEFAULT false,
  status_check_contexts JSONB DEFAULT '[]',

  -- Approvals
  enable_approvals_whitelist BOOLEAN DEFAULT false,
  approvals_whitelist_user_ids JSONB DEFAULT '[]',
  approvals_whitelist_team_ids JSONB DEFAULT '[]',
  required_approvals BIGINT DEFAULT 0,
  block_on_rejected_reviews BOOLEAN DEFAULT false,
  block_on_official_review_requests BOOLEAN DEFAULT false,
  block_on_outdated_branch BOOLEAN DEFAULT false,
  dismiss_stale_approvals BOOLEAN DEFAULT false,
  ignore_stale_approvals BOOLEAN DEFAULT false,

  -- Advanced
  require_signed_commits BOOLEAN DEFAULT false,
  protected_file_patterns TEXT,
  unprotected_file_patterns TEXT,
  block_admin_merge_override BOOLEAN DEFAULT false,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, rule_name)
);

CREATE INDEX idx_protected_branches_repo ON protected_branches(repository_id);
CREATE INDEX idx_protected_branches_priority ON protected_branches(repository_id, priority DESC);
```

### Branch Rename History

```sql
-- Track branch renames for redirects
CREATE TABLE IF NOT EXISTS renamed_branches (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  from_name VARCHAR(255) NOT NULL,
  to_name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_renamed_branches_repo ON renamed_branches(repository_id);
CREATE INDEX idx_renamed_branches_from ON renamed_branches(repository_id, from_name);
```

## Backend Implementation

### Git Utilities (`ui/lib/git.ts`)

Add the following functions to existing git utilities:

```typescript
// Branch operations
export async function createBranch(
  user: string,
  repo: string,
  newBranchName: string,
  fromRef: string
): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${repo}`;

  // Validate branch name
  if (!isValidBranchName(newBranchName)) {
    throw new Error("Invalid branch name");
  }

  // Check if branch already exists
  const exists = await branchExists(user, repo, newBranchName);
  if (exists) {
    throw new Error("Branch already exists");
  }

  // Create branch from ref (commit/branch/tag)
  await run(`git branch "${newBranchName}" "${fromRef}"`, repoPath);
}

export async function deleteBranch(
  user: string,
  repo: string,
  branchName: string
): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${repo}`;

  // Cannot delete default branch
  const defaultBranch = await getDefaultBranch(user, repo);
  if (branchName === defaultBranch) {
    throw new Error("Cannot delete default branch");
  }

  await run(`git branch -D "${branchName}"`, repoPath);
}

export async function renameBranch(
  user: string,
  repo: string,
  oldName: string,
  newName: string
): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${repo}`;

  // Validate new name
  if (!isValidBranchName(newName)) {
    throw new Error("Invalid branch name");
  }

  // Check if new name already exists
  const exists = await branchExists(user, repo, newName);
  if (exists) {
    throw new Error("Branch with new name already exists");
  }

  // Rename branch
  await run(`git branch -m "${oldName}" "${newName}"`, repoPath);

  // Update HEAD if renaming default branch
  const defaultBranch = await getDefaultBranch(user, repo);
  if (oldName === defaultBranch) {
    await run(`git symbolic-ref HEAD refs/heads/${newName}`, repoPath);
  }
}

export async function getBranchCommit(
  user: string,
  repo: string,
  branchName: string
): Promise<{ hash: string; message: string; author: string; timestamp: number }> {
  const repoPath = `${REPOS_DIR}/${user}/${repo}`;
  const format = "%H|%s|%an|%at";
  const result = await run(`git log -1 --format="${format}" "${branchName}"`, repoPath);

  const [hash, message, author, timestamp] = result.trim().split("|");
  return {
    hash: hash || "",
    message: message || "",
    author: author || "",
    timestamp: parseInt(timestamp || "0", 10) * 1000,
  };
}

function isValidBranchName(name: string): boolean {
  // Git branch name rules
  if (!name || name.length === 0) return false;
  if (name.startsWith(".") || name.endsWith(".")) return false;
  if (name.includes("..")) return false;
  if (name.includes("~") || name.includes("^") || name.includes(":")) return false;
  if (name.includes(" ") || name.includes("\t")) return false;
  if (name.includes("//")) return false;
  return true;
}

async function branchExists(user: string, repo: string, branchName: string): Promise<boolean> {
  const branches = await listBranches(user, repo);
  return branches.includes(branchName);
}

async function getDefaultBranch(user: string, repo: string): Promise<string> {
  const repoPath = `${REPOS_DIR}/${user}/${repo}`;
  const result = await run(`git symbolic-ref --short HEAD`, repoPath);
  return result.trim();
}
```

### API Routes (`server/routes/branches.ts`)

Create new API routes for branch operations:

```typescript
import { Hono } from "hono";
import { sql } from "../../db/index";
import * as git from "../../ui/lib/git";
import type { Branch, ProtectedBranch } from "../../ui/lib/types";

const app = new Hono();

// List branches
app.get("/:user/:repo/branches", async (c) => {
  const { user, repo } = c.req.param();
  const page = parseInt(c.req.query("page") || "1");
  const limit = parseInt(c.req.query("limit") || "20");
  const offset = (page - 1) * limit;

  // Get repository
  const [repository] = await sql`
    SELECT r.*, u.username
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // Get branches from database
  const branches = await sql<Branch[]>`
    SELECT b.*, u.username as pusher_username
    FROM branches b
    LEFT JOIN users u ON b.pusher_id = u.id
    WHERE b.repository_id = ${repository.id}
      AND b.is_deleted = false
    ORDER BY
      CASE WHEN b.name = ${repository.default_branch} THEN 0 ELSE 1 END,
      b.updated_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;

  const [{ count }] = await sql`
    SELECT COUNT(*) as count FROM branches
    WHERE repository_id = ${repository.id} AND is_deleted = false
  `;

  return c.json({
    branches,
    total: Number(count),
    page,
    limit,
  });
});

// Create branch
app.post("/:user/:repo/branches", async (c) => {
  const { user, repo } = c.req.param();
  const { name, from_ref } = await c.req.json();

  if (!name || !from_ref) {
    return c.json({ error: "Missing required fields" }, 400);
  }

  try {
    // Get repository
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Check if branch exists
    const [existing] = await sql`
      SELECT id FROM branches
      WHERE repository_id = ${repository.id}
        AND name = ${name}
        AND is_deleted = false
    `;

    if (existing) {
      return c.json({ error: "Branch already exists" }, 409);
    }

    // Create branch in git
    await git.createBranch(user, repo, name, from_ref);

    // Get commit info
    const commitInfo = await git.getBranchCommit(user, repo, name);

    // Create branch record
    const [branch] = await sql`
      INSERT INTO branches (
        repository_id, name, commit_id, commit_message,
        commit_time, pusher_id
      )
      VALUES (
        ${repository.id}, ${name}, ${commitInfo.hash},
        ${commitInfo.message}, ${new Date(commitInfo.timestamp)},
        ${repository.user_id}
      )
      RETURNING *
    `;

    return c.json({ branch }, 201);
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// Delete branch
app.delete("/:user/:repo/branches/:branch", async (c) => {
  const { user, repo, branch: branchName } = c.req.param();

  try {
    // Get repository
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Check if branch is protected
    const isProtected = await isBranchProtected(repository.id, branchName);
    if (isProtected) {
      return c.json({ error: "Branch is protected" }, 403);
    }

    // Cannot delete default branch
    if (branchName === repository.default_branch) {
      return c.json({ error: "Cannot delete default branch" }, 403);
    }

    // Soft delete branch in database
    await sql`
      UPDATE branches
      SET is_deleted = true,
          deleted_at = NOW(),
          deleted_by_id = ${repository.user_id}
      WHERE repository_id = ${repository.id}
        AND name = ${branchName}
    `;

    // Delete from git
    await git.deleteBranch(user, repo, branchName);

    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// Rename branch
app.patch("/:user/:repo/branches/:branch", async (c) => {
  const { user, repo, branch: oldName } = c.req.param();
  const { new_name } = await c.req.json();

  if (!new_name) {
    return c.json({ error: "Missing new_name" }, 400);
  }

  try {
    // Get repository
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Check if branch is protected
    const isProtected = await isBranchProtected(repository.id, oldName);
    if (isProtected) {
      return c.json({ error: "Branch is protected" }, 403);
    }

    // Rename in git
    await git.renameBranch(user, repo, oldName, new_name);

    // Update database
    await sql`
      UPDATE branches
      SET name = ${new_name}, updated_at = NOW()
      WHERE repository_id = ${repository.id} AND name = ${oldName}
    `;

    // Update default branch if needed
    if (oldName === repository.default_branch) {
      await sql`
        UPDATE repositories
        SET default_branch = ${new_name}
        WHERE id = ${repository.id}
      `;
    }

    // Update protected branch rules
    await sql`
      UPDATE protected_branches
      SET rule_name = ${new_name}
      WHERE repository_id = ${repository.id} AND rule_name = ${oldName}
    `;

    // Record rename history
    await sql`
      INSERT INTO renamed_branches (repository_id, from_name, to_name)
      VALUES (${repository.id}, ${oldName}, ${new_name})
    `;

    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// Helper: Check if branch is protected
async function isBranchProtected(repoId: number, branchName: string): Promise<boolean> {
  // Get all protection rules for this repo, ordered by priority
  const rules = await sql<ProtectedBranch[]>`
    SELECT * FROM protected_branches
    WHERE repository_id = ${repoId}
    ORDER BY priority DESC
  `;

  for (const rule of rules) {
    if (matchBranchPattern(rule.rule_name, branchName)) {
      return true;
    }
  }

  return false;
}

// Helper: Match branch name against glob pattern
function matchBranchPattern(pattern: string, branchName: string): boolean {
  // Exact match
  if (pattern === branchName) return true;

  // Convert glob pattern to regex
  // Simple implementation - expand for full glob support
  const regexPattern = pattern
    .replace(/\*/g, ".*")
    .replace(/\?/g, ".");

  const regex = new RegExp(`^${regexPattern}$`);
  return regex.test(branchName);
}

export default app;
```

### Branch Protection API Routes (`server/routes/protected-branches.ts`)

```typescript
import { Hono } from "hono";
import { sql } from "../../db/index";
import type { ProtectedBranch } from "../../ui/lib/types";

const app = new Hono();

// List protection rules
app.get("/:user/:repo/branch-protections", async (c) => {
  const { user, repo } = c.req.param();

  const [repository] = await sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: "Repository not found" }, 404);
  }

  const rules = await sql<ProtectedBranch[]>`
    SELECT * FROM protected_branches
    WHERE repository_id = ${repository.id}
    ORDER BY priority DESC
  `;

  return c.json({ rules });
});

// Create protection rule
app.post("/:user/:repo/branch-protections", async (c) => {
  const { user, repo } = c.req.param();
  const data = await c.req.json();

  const [repository] = await sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // Check if rule already exists
  const [existing] = await sql`
    SELECT id FROM protected_branches
    WHERE repository_id = ${repository.id} AND rule_name = ${data.rule_name}
  `;

  if (existing) {
    return c.json({ error: "Protection rule already exists" }, 409);
  }

  // Get max priority and increment
  const [{ max_priority }] = await sql`
    SELECT COALESCE(MAX(priority), 0) as max_priority
    FROM protected_branches
    WHERE repository_id = ${repository.id}
  `;

  const priority = data.priority || Number(max_priority) + 1;

  const [rule] = await sql`
    INSERT INTO protected_branches (
      repository_id, rule_name, priority,
      can_push, enable_whitelist, whitelist_user_ids,
      can_force_push, enable_force_push_allowlist,
      enable_merge_whitelist, required_approvals,
      enable_status_check, status_check_contexts
    )
    VALUES (
      ${repository.id}, ${data.rule_name}, ${priority},
      ${data.can_push || false}, ${data.enable_whitelist || false},
      ${JSON.stringify(data.whitelist_user_ids || [])},
      ${data.can_force_push || false}, ${data.enable_force_push_allowlist || false},
      ${data.enable_merge_whitelist || false}, ${data.required_approvals || 0},
      ${data.enable_status_check || false},
      ${JSON.stringify(data.status_check_contexts || [])}
    )
    RETURNING *
  `;

  return c.json({ rule }, 201);
});

// Update protection rule
app.patch("/:user/:repo/branch-protections/:ruleId", async (c) => {
  const { user, repo, ruleId } = c.req.param();
  const data = await c.req.json();

  const [repository] = await sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // Build update query dynamically based on provided fields
  const updates: string[] = [];
  const values: any[] = [];

  if (data.can_push !== undefined) {
    updates.push("can_push = $" + (values.length + 1));
    values.push(data.can_push);
  }
  if (data.enable_whitelist !== undefined) {
    updates.push("enable_whitelist = $" + (values.length + 1));
    values.push(data.enable_whitelist);
  }
  // Add more fields as needed...

  if (updates.length === 0) {
    return c.json({ error: "No fields to update" }, 400);
  }

  updates.push("updated_at = NOW()");

  await sql`
    UPDATE protected_branches
    SET ${sql.raw(updates.join(", "))}
    WHERE id = ${ruleId} AND repository_id = ${repository.id}
  `;

  const [rule] = await sql`
    SELECT * FROM protected_branches WHERE id = ${ruleId}
  `;

  return c.json({ rule });
});

// Delete protection rule
app.delete("/:user/:repo/branch-protections/:ruleId", async (c) => {
  const { user, repo, ruleId } = c.req.param();

  const [repository] = await sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: "Repository not found" }, 404);
  }

  await sql`
    DELETE FROM protected_branches
    WHERE id = ${ruleId} AND repository_id = ${repository.id}
  `;

  return c.json({ success: true });
});

export default app;
```

## Frontend Implementation

### Branch List Page (`ui/pages/[user]/[repo]/branches.astro`)

```astro
---
import Layout from "../../../layouts/Layout.astro";
import Header from "../../../components/Header.astro";
import { sql } from "../../../lib/db";
import { getBranchCommit } from "../../../lib/git";
import type { User, Repository, Branch } from "../../../lib/types";

const { user: username, repo: reponame } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

const branches = await sql<Branch[]>`
  SELECT b.*, u.username as pusher_username
  FROM branches b
  LEFT JOIN users u ON b.pusher_id = u.id
  WHERE b.repository_id = ${repo.id} AND b.is_deleted = false
  ORDER BY
    CASE WHEN b.name = ${repo.default_branch} THEN 0 ELSE 1 END,
    b.updated_at DESC
`;

const [{ count: issueCount }] = await sql`
  SELECT COUNT(*) as count FROM issues
  WHERE repository_id = ${repo.id} AND state = 'open'
`;
---

<Layout title={`Branches · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <span class="current">branches</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>
      Issues
      {Number(issueCount) > 0 && <span class="badge">{issueCount}</span>}
    </a>
    <a href={`/${username}/${reponame}/branches`} class="active">Branches</a>
    <a href={`/${username}/${reponame}/commits/${repo.default_branch}`}>Commits</a>
  </nav>

  <div class="container">
    <div class="header-row">
      <h2>{branches.length} branches</h2>
      <button class="btn" data-action="new-branch">New branch</button>
    </div>

    <div class="branch-list">
      {branches.map((branch) => (
        <div class="branch-item">
          <div class="branch-info">
            <div class="branch-name">
              <a href={`/${username}/${reponame}/tree/${branch.name}`}>
                {branch.name}
              </a>
              {branch.name === repo.default_branch && (
                <span class="badge">default</span>
              )}
            </div>
            <div class="branch-meta">
              Updated {new Date(branch.updated_at).toLocaleDateString()} by{" "}
              {branch.pusher_username || "unknown"}
            </div>
            <div class="commit-message">{branch.commit_message}</div>
          </div>

          <div class="branch-actions">
            {branch.name !== repo.default_branch && (
              <>
                <button
                  class="btn-sm"
                  data-action="rename"
                  data-branch={branch.name}
                >
                  Rename
                </button>
                <button
                  class="btn-sm btn-danger"
                  data-action="delete"
                  data-branch={branch.name}
                >
                  Delete
                </button>
              </>
            )}
          </div>
        </div>
      ))}
    </div>
  </div>

  <!-- New Branch Modal -->
  <dialog id="new-branch-modal">
    <form method="post" action={`/${username}/${reponame}/branches/new`}>
      <h3>Create new branch</h3>

      <label>
        Branch name
        <input type="text" name="name" required />
      </label>

      <label>
        Create from
        <select name="from_ref">
          {branches.map((b) => (
            <option value={b.name} selected={b.name === repo.default_branch}>
              {b.name}
            </option>
          ))}
        </select>
      </label>

      <div class="modal-actions">
        <button type="submit" class="btn">Create</button>
        <button type="button" class="btn-secondary" data-action="close-modal">
          Cancel
        </button>
      </div>
    </form>
  </dialog>
</Layout>

<style>
  .header-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
  }

  .branch-list {
    border: 2px solid var(--border);
  }

  .branch-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem;
    border-bottom: 2px solid var(--border);
  }

  .branch-item:last-child {
    border-bottom: none;
  }

  .branch-info {
    flex: 1;
  }

  .branch-name {
    font-family: var(--font-mono);
    font-size: 16px;
    font-weight: bold;
    margin-bottom: 0.25rem;
  }

  .branch-name a {
    color: var(--text);
    text-decoration: none;
  }

  .branch-name a:hover {
    text-decoration: underline;
  }

  .branch-meta {
    font-size: 12px;
    color: var(--text-muted);
    margin-bottom: 0.25rem;
  }

  .commit-message {
    font-size: 14px;
    color: var(--text-muted);
  }

  .branch-actions {
    display: flex;
    gap: 0.5rem;
  }

  dialog {
    border: 2px solid var(--border);
    padding: 2rem;
    max-width: 500px;
  }

  dialog form {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .modal-actions {
    display: flex;
    gap: 0.5rem;
    justify-content: flex-end;
  }
</style>

<script>
  // Modal handling
  document.querySelector('[data-action="new-branch"]')?.addEventListener('click', () => {
    document.getElementById('new-branch-modal')?.showModal();
  });

  document.querySelector('[data-action="close-modal"]')?.addEventListener('click', () => {
    document.getElementById('new-branch-modal')?.close();
  });

  // Delete branch
  document.querySelectorAll('[data-action="delete"]').forEach((btn) => {
    btn.addEventListener('click', async (e) => {
      const branchName = (e.target as HTMLElement).dataset.branch;
      if (!confirm(`Delete branch "${branchName}"?`)) return;

      const response = await fetch(
        `/api/branches/${window.location.pathname.split('/').slice(1, 3).join('/')}/${branchName}`,
        { method: 'DELETE' }
      );

      if (response.ok) {
        window.location.reload();
      } else {
        const data = await response.json();
        alert(data.error || 'Failed to delete branch');
      }
    });
  });
</script>
```

### Branch Protection Settings Page (`ui/pages/[user]/[repo]/settings/branches.astro`)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import type { User, Repository, ProtectedBranch } from "../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

const protectionRules = await sql<ProtectedBranch[]>`
  SELECT * FROM protected_branches
  WHERE repository_id = ${repo.id}
  ORDER BY priority DESC
`;
---

<Layout title={`Branch Protection · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <span class="current">settings</span>
  </div>

  <div class="container">
    <h2>Branch Protection Rules</h2>

    <button class="btn mb-3" data-action="new-rule">Add rule</button>

    <div class="rules-list">
      {protectionRules.length === 0 && (
        <p class="text-muted">No protection rules configured</p>
      )}

      {protectionRules.map((rule) => (
        <div class="rule-item">
          <div class="rule-header">
            <code>{rule.rule_name}</code>
            <span class="badge">Priority: {rule.priority}</span>
          </div>

          <div class="rule-details">
            <div>Push: {rule.can_push ? 'Allowed' : 'Blocked'}</div>
            <div>Force Push: {rule.can_force_push ? 'Allowed' : 'Blocked'}</div>
            <div>Required Approvals: {rule.required_approvals}</div>
            {rule.enable_status_check && (
              <div>Status Checks: Required</div>
            )}
          </div>

          <div class="rule-actions">
            <button
              class="btn-sm"
              data-action="edit"
              data-rule-id={rule.id}
            >
              Edit
            </button>
            <button
              class="btn-sm btn-danger"
              data-action="delete"
              data-rule-id={rule.id}
            >
              Delete
            </button>
          </div>
        </div>
      ))}
    </div>
  </div>
</Layout>

<style>
  .rules-list {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .rule-item {
    border: 2px solid var(--border);
    padding: 1rem;
  }

  .rule-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
  }

  .rule-header code {
    font-size: 16px;
    font-weight: bold;
  }

  .rule-details {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 0.5rem;
    margin-bottom: 1rem;
    font-size: 14px;
  }

  .rule-actions {
    display: flex;
    gap: 0.5rem;
  }
</style>
```

## Implementation Checklist

### Phase 1: Database & Core Git Operations
- [ ] Create migration with `branches`, `protected_branches`, and `renamed_branches` tables
- [ ] Add branch operation functions to `ui/lib/git.ts`
  - [ ] `createBranch()`
  - [ ] `deleteBranch()`
  - [ ] `renameBranch()`
  - [ ] `getBranchCommit()`
  - [ ] `isValidBranchName()`
- [ ] Test git operations manually with Bun

### Phase 2: API Routes
- [ ] Create `server/routes/branches.ts`
  - [ ] GET `/:user/:repo/branches` - List branches
  - [ ] POST `/:user/:repo/branches` - Create branch
  - [ ] DELETE `/:user/:repo/branches/:branch` - Delete branch
  - [ ] PATCH `/:user/:repo/branches/:branch` - Rename branch
- [ ] Create `server/routes/protected-branches.ts`
  - [ ] GET `/:user/:repo/branch-protections` - List rules
  - [ ] POST `/:user/:repo/branch-protections` - Create rule
  - [ ] PATCH `/:user/:repo/branch-protections/:ruleId` - Update rule
  - [ ] DELETE `/:user/:repo/branch-protections/:ruleId` - Delete rule
- [ ] Register routes in `server/main.ts`
- [ ] Test all API endpoints with curl/Postman

### Phase 3: Frontend Pages
- [ ] Create `ui/pages/[user]/[repo]/branches.astro`
  - [ ] Branch list with metadata
  - [ ] Create branch modal
  - [ ] Delete branch confirmation
  - [ ] Rename branch modal
  - [ ] Default branch badge
- [ ] Create `ui/pages/[user]/[repo]/settings/branches.astro`
  - [ ] Protection rules list
  - [ ] Create/edit rule modal
  - [ ] Delete rule confirmation
- [ ] Add branch navigation to repo navbar
- [ ] Add TypeScript types to `ui/lib/types.ts`

### Phase 4: Advanced Features
- [ ] Implement glob pattern matching for protection rules
- [ ] Add priority-based rule resolution
- [ ] Implement soft-delete with restore functionality
- [ ] Add branch rename redirect handling
- [ ] Create default branch change workflow
- [ ] Add branch comparison view (ahead/behind commits)

### Phase 5: Testing & Polish
- [ ] Test branch creation from different refs (commits, branches, tags)
- [ ] Test branch deletion with protection rules
- [ ] Test branch rename cascading updates
- [ ] Test protection rule priority resolution
- [ ] Test glob patterns: `release/*`, `feature/**`, `hotfix-*`
- [ ] Add error handling for all edge cases
- [ ] Add loading states to UI
- [ ] Optimize database queries with proper indexes

## Reference Code Translation

### Gitea Branch Model → Plue TypeScript

**Gitea Go (models/git/branch.go)**:
```go
type Branch struct {
    ID            int64
    RepoID        int64
    Name          string
    CommitID      string
    CommitMessage string
    PusherID      int64
    IsDeleted     bool
    DeletedByID   int64
    DeletedUnix   timeutil.TimeStamp
    CommitTime    timeutil.TimeStamp
}
```

**Plue TypeScript (ui/lib/types.ts)**:
```typescript
export interface Branch {
  id: number;
  repository_id: number;
  name: string;
  commit_id: string;
  commit_message: string;
  pusher_id: number;
  is_deleted: boolean;
  deleted_by_id?: number;
  deleted_at?: Date;
  commit_time: Date;
  created_at: Date;
  updated_at: Date;
}
```

### Gitea Protection Model → Plue TypeScript

**Gitea Go (models/git/protected_branch.go)**:
```go
type ProtectedBranch struct {
    ID                   int64
    RepoID               int64
    RuleName             string
    Priority             int64
    CanPush              bool
    EnableWhitelist      bool
    WhitelistUserIDs     []int64
    RequiredApprovals    int64
    EnableStatusCheck    bool
    StatusCheckContexts  []string
}
```

**Plue TypeScript (ui/lib/types.ts)**:
```typescript
export interface ProtectedBranch {
  id: number;
  repository_id: number;
  rule_name: string;
  priority: number;
  can_push: boolean;
  enable_whitelist: boolean;
  whitelist_user_ids: number[];
  required_approvals: number;
  enable_status_check: boolean;
  status_check_contexts: string[];
  // ... additional fields
}
```

## Git Commands Reference

### Branch Operations

```bash
# List all branches
git branch --list

# Create branch from ref
git branch <new-branch> <from-ref>

# Delete branch (force)
git branch -D <branch-name>

# Rename branch
git branch -m <old-name> <new-name>

# Get branch commit
git log -1 --format="%H|%s|%an|%at" <branch-name>

# Check if branch exists
git rev-parse --verify <branch-name>

# Update HEAD symbolic ref (for default branch)
git symbolic-ref HEAD refs/heads/<branch-name>

# Get current default branch
git symbolic-ref --short HEAD
```

## Testing Scenarios

1. **Basic Operations**
   - Create branch from main
   - Create branch from specific commit
   - Delete non-protected branch
   - Rename branch

2. **Protection Rules**
   - Create exact match rule (e.g., `main`)
   - Create glob pattern rule (e.g., `release/*`)
   - Test priority resolution with multiple rules
   - Attempt to delete protected branch (should fail)

3. **Edge Cases**
   - Create branch with invalid name
   - Delete default branch (should fail)
   - Rename to existing branch name (should fail)
   - Create multiple rules with same priority

4. **Integration**
   - Create branch, push commits, delete
   - Rename default branch and verify repository update
   - Create protection rule, test push restrictions
   - Delete branch with open pull requests

## Performance Considerations

1. **Pagination**: Implement cursor-based pagination for repositories with many branches
2. **Caching**: Cache protection rules per repository to avoid repeated DB queries
3. **Lazy Loading**: Only fetch commit metadata when displaying branch list
4. **Indexes**: Ensure proper indexes on `repository_id`, `name`, `is_deleted`, `priority`

## Security Considerations

1. **Permission Checks**: Verify user has write access before allowing branch operations
2. **Protection Validation**: Always check protection rules before deletions
3. **Input Sanitization**: Validate branch names to prevent command injection
4. **SQL Injection**: Use parameterized queries for all database operations
