# Repository Settings Feature Implementation

## Overview

Implement a comprehensive Repository Settings feature for Plue, allowing repository owners to manage general settings, collaborators, and perform dangerous operations like transfer, archive, and delete. This feature is essential for repository administration and mirrors GitHub/Gitea settings capabilities.

**Scope**: General settings (name, description, visibility), collaborator management (add/remove/permissions), and danger zone operations (transfer, archive/unarchive, delete).

**Stack**: Bun runtime, Hono API server, Astro SSR frontend, PostgreSQL database, Git CLI operations.

---

## 1. Database Schema Changes

### 1.1 Repository Collaborators Table

```sql
-- Repository collaborators with access permissions
CREATE TABLE IF NOT EXISTS collaborators (
  id SERIAL PRIMARY KEY,
  repo_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  access_mode VARCHAR(20) NOT NULL DEFAULT 'read' CHECK (access_mode IN (
    'read',     -- Can view and clone
    'write',    -- Can push to non-protected branches
    'admin'     -- Can change settings, add collaborators
  )),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repo_id, user_id)
);

CREATE INDEX idx_collaborators_repo ON collaborators(repo_id);
CREATE INDEX idx_collaborators_user ON collaborators(user_id);
```

### 1.2 Repository Transfer Requests

```sql
-- Pending repository transfers
CREATE TABLE IF NOT EXISTS repository_transfers (
  id SERIAL PRIMARY KEY,
  repo_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  doer_id INTEGER NOT NULL REFERENCES users(id),  -- Who initiated transfer
  recipient_id INTEGER NOT NULL REFERENCES users(id),  -- New owner
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repo_id)
);

CREATE INDEX idx_transfers_repo ON repository_transfers(repo_id);
CREATE INDEX idx_transfers_recipient ON repository_transfers(recipient_id);
```

### 1.3 Update Repositories Table

```sql
-- Add new columns to existing repositories table
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT false;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS website VARCHAR(512);
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS is_template BOOLEAN DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_repositories_archived ON repositories(is_archived);
```

---

## 2. API Endpoints

### 2.1 Settings Routes (`server/routes/repos.ts`)

```typescript
import { Hono } from "hono";
import { sql } from "../../db";
import { execSync } from "child_process";
import { renameSync, rmSync } from "fs";
import { z } from "zod";

const repos = new Hono();

// ============================================================================
// GET /:user/:repo/settings - Get repository settings page data
// ============================================================================
repos.get("/:user/:repo/settings", async (c) => {
  const { user: username, repo: reponame } = c.req.param();

  // Get repository with owner info
  const [repo] = await sql`
    SELECT r.*, u.username as owner_name
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // TODO: Check if current user is owner or has admin access

  // Get collaborators with user details
  const collaborators = await sql`
    SELECT c.*, u.username, u.display_name
    FROM collaborators c
    JOIN users u ON c.user_id = u.id
    WHERE c.repo_id = ${repo.id}
    ORDER BY c.created_at
  `;

  // Get pending transfer if exists
  const [transfer] = await sql`
    SELECT t.*, u.username as recipient_name
    FROM repository_transfers t
    JOIN users u ON t.recipient_id = u.id
    WHERE t.repo_id = ${repo.id}
  `;

  return c.json({
    repo,
    collaborators,
    transfer: transfer || null,
  });
});

// ============================================================================
// POST /:user/:repo/settings/general - Update general settings
// ============================================================================
const updateGeneralSchema = z.object({
  name: z.string().min(1).max(100).regex(/^[a-zA-Z0-9_.-]+$/),
  description: z.string().max(500).optional(),
  website: z.string().url().max(512).optional().or(z.literal("")),
  is_template: z.boolean().optional(),
});

repos.post("/:user/:repo/settings/general", async (c) => {
  const { user: username, repo: reponame } = c.req.param();
  const body = await c.req.json();

  const data = updateGeneralSchema.parse(body);

  // Get repository
  const [repo] = await sql`
    SELECT r.*, u.username as owner_name
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // Check if name changed
  if (data.name !== repo.name) {
    // Check if new name is available
    const [existing] = await sql`
      SELECT id FROM repositories
      WHERE user_id = ${repo.user_id} AND name = ${data.name}
    `;

    if (existing) {
      return c.json({ error: "Repository name already exists" }, 400);
    }

    // Rename repository directory
    const oldPath = `/tmp/repos/${username}/${reponame}.git`;
    const newPath = `/tmp/repos/${username}/${data.name}.git`;

    try {
      renameSync(oldPath, newPath);
    } catch (err) {
      return c.json({ error: "Failed to rename repository directory" }, 500);
    }
  }

  // Update database
  await sql`
    UPDATE repositories SET
      name = ${data.name},
      description = ${data.description || null},
      website = ${data.website || null},
      is_template = ${data.is_template || false},
      updated_at = NOW()
    WHERE id = ${repo.id}
  `;

  return c.json({ success: true });
});

// ============================================================================
// POST /:user/:repo/settings/visibility - Toggle public/private
// ============================================================================
repos.post("/:user/:repo/settings/visibility", async (c) => {
  const { user: username, repo: reponame } = c.req.param();

  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // Toggle visibility
  const newVisibility = !repo.is_public;

  await sql`
    UPDATE repositories
    SET is_public = ${newVisibility}, updated_at = NOW()
    WHERE id = ${repo.id}
  `;

  return c.json({
    success: true,
    is_public: newVisibility
  });
});

// ============================================================================
// Collaborator Management
// ============================================================================

// GET /:user/:repo/settings/collaborators
repos.get("/:user/:repo/settings/collaborators", async (c) => {
  const { user: username, repo: reponame } = c.req.param();

  const [repo] = await sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  const collaborators = await sql`
    SELECT c.*, u.username, u.display_name, u.bio
    FROM collaborators c
    JOIN users u ON c.user_id = u.id
    WHERE c.repo_id = ${repo.id}
    ORDER BY c.created_at DESC
  `;

  return c.json({ collaborators });
});

// POST /:user/:repo/settings/collaborators - Add collaborator
const addCollaboratorSchema = z.object({
  username: z.string().min(1),
  access_mode: z.enum(["read", "write", "admin"]).default("write"),
});

repos.post("/:user/:repo/settings/collaborators", async (c) => {
  const { user: username, repo: reponame } = c.req.param();
  const body = await c.req.json();

  const data = addCollaboratorSchema.parse(body);

  // Get repository
  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // Get user to add
  const [userToAdd] = await sql`
    SELECT id FROM users WHERE username = ${data.username}
  `;

  if (!userToAdd) {
    return c.json({ error: "User not found" }, 404);
  }

  // Check if user is owner
  if (userToAdd.id === repo.user_id) {
    return c.json({ error: "Cannot add owner as collaborator" }, 400);
  }

  // Check if already a collaborator
  const [existing] = await sql`
    SELECT id FROM collaborators
    WHERE repo_id = ${repo.id} AND user_id = ${userToAdd.id}
  `;

  if (existing) {
    return c.json({ error: "User is already a collaborator" }, 400);
  }

  // Add collaborator
  await sql`
    INSERT INTO collaborators (repo_id, user_id, access_mode)
    VALUES (${repo.id}, ${userToAdd.id}, ${data.access_mode})
  `;

  return c.json({ success: true });
});

// PATCH /:user/:repo/settings/collaborators/:id - Change access mode
repos.patch("/:user/:repo/settings/collaborators/:id", async (c) => {
  const { user: username, repo: reponame, id } = c.req.param();
  const { access_mode } = await c.req.json();

  if (!["read", "write", "admin"].includes(access_mode)) {
    return c.json({ error: "Invalid access mode" }, 400);
  }

  await sql`
    UPDATE collaborators
    SET access_mode = ${access_mode}, updated_at = NOW()
    WHERE id = ${id}
  `;

  return c.json({ success: true });
});

// DELETE /:user/:repo/settings/collaborators/:id - Remove collaborator
repos.delete("/:user/:repo/settings/collaborators/:id", async (c) => {
  const { id } = c.req.param();

  await sql`DELETE FROM collaborators WHERE id = ${id}`;

  return c.json({ success: true });
});

// ============================================================================
// Danger Zone Operations
// ============================================================================

// POST /:user/:repo/settings/archive - Archive repository
repos.post("/:user/:repo/settings/archive", async (c) => {
  const { user: username, repo: reponame } = c.req.param();

  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  await sql`
    UPDATE repositories
    SET is_archived = true, archived_at = NOW(), updated_at = NOW()
    WHERE id = ${repo.id}
  `;

  return c.json({ success: true });
});

// POST /:user/:repo/settings/unarchive - Unarchive repository
repos.post("/:user/:repo/settings/unarchive", async (c) => {
  const { user: username, repo: reponame } = c.req.param();

  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  await sql`
    UPDATE repositories
    SET is_archived = false, archived_at = NULL, updated_at = NOW()
    WHERE id = ${repo.id}
  `;

  return c.json({ success: true });
});

// POST /:user/:repo/settings/transfer - Transfer repository
const transferSchema = z.object({
  new_owner: z.string().min(1),
  confirm_name: z.string().min(1),
});

repos.post("/:user/:repo/settings/transfer", async (c) => {
  const { user: username, repo: reponame } = c.req.param();
  const body = await c.req.json();

  const data = transferSchema.parse(body);

  // Get repository
  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // Verify confirmation
  if (data.confirm_name !== repo.name) {
    return c.json({ error: "Repository name confirmation does not match" }, 400);
  }

  // Get new owner
  const [newOwner] = await sql`
    SELECT id, username FROM users WHERE username = ${data.new_owner}
  `;

  if (!newOwner) {
    return c.json({ error: "New owner not found" }, 404);
  }

  // Check if new owner already has a repo with this name
  const [existing] = await sql`
    SELECT id FROM repositories
    WHERE user_id = ${newOwner.id} AND name = ${repo.name}
  `;

  if (existing) {
    return c.json({ error: "New owner already has a repository with this name" }, 400);
  }

  // Create transfer request
  await sql`
    INSERT INTO repository_transfers (repo_id, doer_id, recipient_id)
    VALUES (${repo.id}, ${repo.user_id}, ${newOwner.id})
    ON CONFLICT (repo_id) DO UPDATE SET
      doer_id = ${repo.user_id},
      recipient_id = ${newOwner.id},
      created_at = NOW()
  `;

  return c.json({
    success: true,
    message: `Transfer request sent to ${newOwner.username}`
  });
});

// POST /:user/:repo/settings/transfer/accept - Accept transfer
repos.post("/:user/:repo/settings/transfer/accept", async (c) => {
  const { user: username, repo: reponame } = c.req.param();

  // Get repository and transfer
  const [result] = await sql`
    SELECT
      r.id as repo_id,
      r.name as repo_name,
      r.user_id as old_owner_id,
      u_old.username as old_owner_name,
      t.recipient_id as new_owner_id,
      u_new.username as new_owner_name
    FROM repositories r
    JOIN users u_old ON r.user_id = u_old.id
    JOIN repository_transfers t ON t.repo_id = r.id
    JOIN users u_new ON t.recipient_id = u_new.id
    WHERE u_old.username = ${username} AND r.name = ${reponame}
  `;

  if (!result) {
    return c.json({ error: "Transfer request not found" }, 404);
  }

  // Move repository directory
  const oldPath = `/tmp/repos/${result.old_owner_name}/${result.repo_name}.git`;
  const newPath = `/tmp/repos/${result.new_owner_name}/${result.repo_name}.git`;

  try {
    renameSync(oldPath, newPath);
  } catch (err) {
    return c.json({ error: "Failed to move repository" }, 500);
  }

  // Update repository owner
  await sql`
    UPDATE repositories
    SET user_id = ${result.new_owner_id}, updated_at = NOW()
    WHERE id = ${result.repo_id}
  `;

  // Delete transfer request
  await sql`DELETE FROM repository_transfers WHERE repo_id = ${result.repo_id}`;

  // Remove collaborators that are no longer needed (new owner was collaborator)
  await sql`
    DELETE FROM collaborators
    WHERE repo_id = ${result.repo_id} AND user_id = ${result.new_owner_id}
  `;

  return c.json({ success: true });
});

// POST /:user/:repo/settings/transfer/cancel - Cancel transfer
repos.post("/:user/:repo/settings/transfer/cancel", async (c) => {
  const { user: username, repo: reponame } = c.req.param();

  const [repo] = await sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  await sql`DELETE FROM repository_transfers WHERE repo_id = ${repo.id}`;

  return c.json({ success: true });
});

// DELETE /:user/:repo/settings/delete - Delete repository
const deleteSchema = z.object({
  confirm_name: z.string().min(1),
});

repos.delete("/:user/:repo/settings/delete", async (c) => {
  const { user: username, repo: reponame } = c.req.param();
  const body = await c.req.json();

  const data = deleteSchema.parse(body);

  // Get repository
  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // Verify confirmation
  if (data.confirm_name !== repo.name) {
    return c.json({ error: "Repository name confirmation does not match" }, 400);
  }

  // Delete repository directory
  const repoPath = `/tmp/repos/${username}/${reponame}.git`;

  try {
    rmSync(repoPath, { recursive: true, force: true });
  } catch (err) {
    console.error("Failed to delete repository directory:", err);
    // Continue with database deletion even if file deletion fails
  }

  // Delete from database (CASCADE will handle related records)
  await sql`DELETE FROM repositories WHERE id = ${repo.id}`;

  return c.json({ success: true });
});

export default repos;
```

---

## 3. UI Pages

### 3.1 Settings Navigation (`ui/pages/[user]/[repo]/settings/index.astro`)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

// TODO: Check if current user is owner or admin
// For now, assume they have access

const [{ count: issueCount }] = await sql`
  SELECT COUNT(*) as count FROM issues WHERE repository_id = ${repo.id} AND state = 'open'
`;

const currentTab = Astro.url.pathname.split('/').pop() || 'general';
---

<Layout title={`Settings - ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <span class="current">Settings</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>
      Issues
      {Number(issueCount) > 0 && <span class="badge">{issueCount}</span>}
    </a>
    <a href={`/${username}/${reponame}/commits/${repo.default_branch}`}>Commits</a>
    <a href={`/${username}/${reponame}/settings`} class="active">Settings</a>
  </nav>

  <div class="container settings-layout">
    <nav class="settings-nav">
      <a href={`/${username}/${reponame}/settings`}
         class:list={[currentTab === 'general' && 'active']}>
        General
      </a>
      <a href={`/${username}/${reponame}/settings/collaborators`}
         class:list={[currentTab === 'collaborators' && 'active']}>
        Collaborators
      </a>
      <a href={`/${username}/${reponame}/settings/danger`}
         class:list={[currentTab === 'danger' && 'active']}>
        Danger Zone
      </a>
    </nav>

    <div class="settings-content">
      <slot />
    </div>
  </div>
</Layout>

<style>
  .settings-layout {
    display: grid;
    grid-template-columns: 200px 1fr;
    gap: 2rem;
    margin-top: 2rem;
  }

  .settings-nav {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .settings-nav a {
    padding: 0.5rem 1rem;
    border: 1px solid var(--border);
    text-decoration: none;
    color: var(--text);
  }

  .settings-nav a:hover {
    background: var(--bg-secondary);
  }

  .settings-nav a.active {
    background: var(--text);
    color: var(--bg);
    font-weight: bold;
  }

  .settings-content {
    border: 1px solid var(--border);
    padding: 2rem;
  }
</style>
```

### 3.2 General Settings (`ui/pages/[user]/[repo]/settings/index.astro` - content)

```astro
---
// In the same file, after the layout, add the content:
---

<div class="settings-section">
  <h2>General Settings</h2>

  <form id="general-form" class="form">
    <div class="form-group">
      <label for="name">Repository name</label>
      <input
        type="text"
        id="name"
        name="name"
        value={repo.name}
        pattern="[a-zA-Z0-9_.-]+"
        required
      />
      <small>Repository URL: /{username}/{repo.name}</small>
    </div>

    <div class="form-group">
      <label for="description">Description (optional)</label>
      <textarea
        id="description"
        name="description"
        rows="3"
        maxlength="500"
      >{repo.description || ''}</textarea>
    </div>

    <div class="form-group">
      <label for="website">Website (optional)</label>
      <input
        type="url"
        id="website"
        name="website"
        value={repo.website || ''}
        placeholder="https://example.com"
      />
    </div>

    <div class="form-group">
      <label>
        <input type="checkbox" name="is_template" {repo.is_template && 'checked'} />
        Template repository
      </label>
      <small>Allow users to create new repositories from this template</small>
    </div>

    <button type="submit" class="btn btn-primary">Update settings</button>
  </form>
</div>

<div class="settings-section">
  <h2>Visibility</h2>

  <p>This repository is currently <strong>{repo.is_public ? 'public' : 'private'}</strong>.</p>

  <button id="toggle-visibility" class="btn">
    Make {repo.is_public ? 'private' : 'public'}
  </button>
</div>

<script>
  // General settings form
  document.getElementById('general-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target as HTMLFormElement;
    const formData = new FormData(form);

    const data = {
      name: formData.get('name'),
      description: formData.get('description'),
      website: formData.get('website'),
      is_template: formData.has('is_template'),
    };

    const response = await fetch(window.location.pathname.replace('/settings', '/settings/general'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });

    if (response.ok) {
      window.location.reload();
    } else {
      const error = await response.json();
      alert(error.error || 'Failed to update settings');
    }
  });

  // Visibility toggle
  document.getElementById('toggle-visibility')?.addEventListener('click', async () => {
    if (!confirm('Are you sure you want to change repository visibility?')) return;

    const response = await fetch(window.location.pathname.replace('/settings', '/settings/visibility'), {
      method: 'POST',
    });

    if (response.ok) {
      window.location.reload();
    } else {
      alert('Failed to change visibility');
    }
  });
</script>

<style>
  .settings-section {
    margin-bottom: 3rem;
    padding-bottom: 2rem;
    border-bottom: 1px solid var(--border);
  }

  .settings-section:last-child {
    border-bottom: none;
  }

  .form-group {
    margin-bottom: 1.5rem;
  }

  .form-group label {
    display: block;
    margin-bottom: 0.5rem;
    font-weight: bold;
  }

  .form-group input[type="text"],
  .form-group input[type="url"],
  .form-group textarea {
    width: 100%;
    max-width: 500px;
    padding: 0.5rem;
    border: 1px solid var(--border);
    font-family: inherit;
  }

  .form-group small {
    display: block;
    margin-top: 0.25rem;
    color: var(--text-muted);
    font-size: 0.875rem;
  }
</style>
```

### 3.3 Collaborators Page (`ui/pages/[user]/[repo]/settings/collaborators.astro`)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";

const { user: username, repo: reponame } = Astro.params;

const [repo] = await sql`
  SELECT r.* FROM repositories r
  JOIN users u ON r.user_id = u.id
  WHERE u.username = ${username} AND r.name = ${reponame}
`;

if (!repo) return Astro.redirect("/404");

const collaborators = await sql`
  SELECT c.*, u.username, u.display_name
  FROM collaborators c
  JOIN users u ON c.user_id = u.id
  WHERE c.repo_id = ${repo.id}
  ORDER BY c.created_at
`;
---

<Layout title={`Collaborators - ${username}/${reponame}`}>
  <Header />

  <!-- Same breadcrumb and nav as settings index -->

  <div class="container">
    <h2>Collaborators</h2>

    <div class="add-collaborator">
      <h3>Add collaborator</h3>
      <form id="add-form" class="inline-form">
        <input
          type="text"
          name="username"
          placeholder="Username"
          required
        />
        <select name="access_mode">
          <option value="read">Read</option>
          <option value="write" selected>Write</option>
          <option value="admin">Admin</option>
        </select>
        <button type="submit" class="btn">Add</button>
      </form>
    </div>

    <div class="collaborators-list">
      {collaborators.length === 0 ? (
        <p class="empty">No collaborators yet.</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>User</th>
              <th>Access</th>
              <th>Added</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {collaborators.map((collab) => (
              <tr>
                <td>
                  <a href={`/${collab.username}`}>{collab.display_name || collab.username}</a>
                </td>
                <td>
                  <select
                    class="access-select"
                    data-id={collab.id}
                    value={collab.access_mode}
                  >
                    <option value="read">Read</option>
                    <option value="write">Write</option>
                    <option value="admin">Admin</option>
                  </select>
                </td>
                <td>{new Date(collab.created_at).toLocaleDateString()}</td>
                <td>
                  <button
                    class="btn btn-danger btn-sm remove-btn"
                    data-id={collab.id}
                  >
                    Remove
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  </div>
</Layout>

<script>
  // Add collaborator
  document.getElementById('add-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target as HTMLFormElement;
    const formData = new FormData(form);

    const data = {
      username: formData.get('username'),
      access_mode: formData.get('access_mode'),
    };

    const response = await fetch(window.location.pathname, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });

    if (response.ok) {
      window.location.reload();
    } else {
      const error = await response.json();
      alert(error.error || 'Failed to add collaborator');
    }
  });

  // Change access mode
  document.querySelectorAll('.access-select').forEach((select) => {
    select.addEventListener('change', async (e) => {
      const target = e.target as HTMLSelectElement;
      const id = target.dataset.id;
      const access_mode = target.value;

      const response = await fetch(`${window.location.pathname}/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ access_mode }),
      });

      if (!response.ok) {
        alert('Failed to update access mode');
        window.location.reload();
      }
    });
  });

  // Remove collaborator
  document.querySelectorAll('.remove-btn').forEach((btn) => {
    btn.addEventListener('click', async (e) => {
      if (!confirm('Remove this collaborator?')) return;

      const target = e.target as HTMLButtonElement;
      const id = target.dataset.id;

      const response = await fetch(`${window.location.pathname}/${id}`, {
        method: 'DELETE',
      });

      if (response.ok) {
        window.location.reload();
      } else {
        alert('Failed to remove collaborator');
      }
    });
  });
</script>

<style>
  .add-collaborator {
    margin: 2rem 0;
    padding: 1.5rem;
    border: 1px solid var(--border);
  }

  .inline-form {
    display: flex;
    gap: 0.5rem;
    margin-top: 1rem;
  }

  .inline-form input,
  .inline-form select {
    padding: 0.5rem;
    border: 1px solid var(--border);
  }

  table {
    width: 100%;
    border-collapse: collapse;
  }

  th, td {
    text-align: left;
    padding: 1rem;
    border-bottom: 1px solid var(--border);
  }

  .access-select {
    padding: 0.25rem;
    border: 1px solid var(--border);
  }
</style>
```

### 3.4 Danger Zone (`ui/pages/[user]/[repo]/settings/danger.astro`)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";

const { user: username, repo: reponame } = Astro.params;

const [repo] = await sql`
  SELECT r.* FROM repositories r
  JOIN users u ON r.user_id = u.id
  WHERE u.username = ${username} AND r.name = ${reponame}
`;

if (!repo) return Astro.redirect("/404");

const [transfer] = await sql`
  SELECT t.*, u.username as recipient_name
  FROM repository_transfers t
  JOIN users u ON t.recipient_id = u.id
  WHERE t.repo_id = ${repo.id}
`;
---

<Layout title={`Danger Zone - ${username}/${reponame}`}>
  <Header />

  <div class="container">
    <h2>Danger Zone</h2>

    <!-- Archive/Unarchive -->
    <div class="danger-item">
      <div class="danger-info">
        <h3>{repo.is_archived ? 'Unarchive' : 'Archive'} repository</h3>
        <p>
          {repo.is_archived
            ? 'Restore this repository to normal operation.'
            : 'Mark this repository as archived and read-only.'}
        </p>
      </div>
      <button
        id="archive-btn"
        class="btn btn-warning"
        data-action={repo.is_archived ? 'unarchive' : 'archive'}
      >
        {repo.is_archived ? 'Unarchive' : 'Archive'}
      </button>
    </div>

    <!-- Transfer -->
    <div class="danger-item">
      <div class="danger-info">
        <h3>Transfer repository</h3>
        <p>Transfer this repository to another user or organization.</p>
        {transfer && (
          <p class="warning">
            Pending transfer to <strong>{transfer.recipient_name}</strong>
          </p>
        )}
      </div>
      {transfer ? (
        <button id="cancel-transfer-btn" class="btn btn-warning">
          Cancel transfer
        </button>
      ) : (
        <button id="transfer-btn" class="btn btn-warning">
          Transfer
        </button>
      )}
    </div>

    <!-- Delete -->
    <div class="danger-item">
      <div class="danger-info">
        <h3>Delete repository</h3>
        <p class="danger">
          Once deleted, it will be gone forever. Please be certain.
        </p>
      </div>
      <button id="delete-btn" class="btn btn-danger">
        Delete repository
      </button>
    </div>
  </div>
</Layout>

<script define:vars={{ reponame }}>
  // Archive/Unarchive
  document.getElementById('archive-btn')?.addEventListener('click', async (e) => {
    const action = (e.target as HTMLButtonElement).dataset.action;

    if (!confirm(`Are you sure you want to ${action} this repository?`)) return;

    const response = await fetch(`/api/repos/${window.location.pathname.split('/')[1]}/${window.location.pathname.split('/')[2]}/settings/${action}`, {
      method: 'POST',
    });

    if (response.ok) {
      window.location.reload();
    } else {
      alert(`Failed to ${action} repository`);
    }
  });

  // Transfer
  document.getElementById('transfer-btn')?.addEventListener('click', async () => {
    const newOwner = prompt('Enter the username of the new owner:');
    if (!newOwner) return;

    const confirmName = prompt(`Type "${reponame}" to confirm:`);
    if (confirmName !== reponame) {
      alert('Repository name does not match');
      return;
    }

    const response = await fetch(`/api/repos/${window.location.pathname.split('/')[1]}/${window.location.pathname.split('/')[2]}/settings/transfer`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ new_owner: newOwner, confirm_name: confirmName }),
    });

    if (response.ok) {
      window.location.reload();
    } else {
      const error = await response.json();
      alert(error.error || 'Failed to transfer repository');
    }
  });

  // Cancel transfer
  document.getElementById('cancel-transfer-btn')?.addEventListener('click', async () => {
    if (!confirm('Cancel transfer request?')) return;

    const response = await fetch(`/api/repos/${window.location.pathname.split('/')[1]}/${window.location.pathname.split('/')[2]}/settings/transfer/cancel`, {
      method: 'POST',
    });

    if (response.ok) {
      window.location.reload();
    } else {
      alert('Failed to cancel transfer');
    }
  });

  // Delete
  document.getElementById('delete-btn')?.addEventListener('click', async () => {
    const confirmName = prompt(`Type "${reponame}" to confirm deletion:`);
    if (confirmName !== reponame) {
      alert('Repository name does not match');
      return;
    }

    const response = await fetch(`/api/repos/${window.location.pathname.split('/')[1]}/${window.location.pathname.split('/')[2]}/settings/delete`, {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ confirm_name: confirmName }),
    });

    if (response.ok) {
      window.location.href = `/${window.location.pathname.split('/')[1]}`;
    } else {
      const error = await response.json();
      alert(error.error || 'Failed to delete repository');
    }
  });
</script>

<style>
  .danger-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1.5rem;
    margin-bottom: 1rem;
    border: 2px solid var(--danger);
  }

  .danger-info h3 {
    margin: 0 0 0.5rem 0;
  }

  .danger-info p {
    margin: 0;
    color: var(--text-muted);
  }

  .danger-info .warning {
    color: var(--warning);
    font-weight: bold;
  }

  .danger-info .danger {
    color: var(--danger);
  }
</style>
```

---

## 4. Reference Implementation (from Gitea)

### 4.1 Repository Model (TypeScript translation)

```typescript
// Based on gitea/models/repo/repo.go

export interface Repository {
  id: number;
  owner_id: number;
  owner_name: string;
  name: string;
  lower_name: string;
  description: string;
  website: string;
  default_branch: string;

  is_private: boolean;
  is_empty: boolean;
  is_archived: boolean;
  is_mirror: boolean;
  is_fork: boolean;
  is_template: boolean;

  size: number;

  created_at: Date;
  updated_at: Date;
  archived_at: Date | null;
}

// Validation
export function isValidRepoName(name: string): boolean {
  // Must match: /^[a-zA-Z0-9_.-]+$/
  // Cannot contain: ..
  // Cannot be: . or .. or -
  const validPattern = /^[a-zA-Z0-9_.-]+$/;
  const invalidPattern = /\.\./;
  const reserved = ['.', '..', '-'];

  return (
    validPattern.test(name) &&
    !invalidPattern.test(name) &&
    !reserved.includes(name)
  );
}
```

### 4.2 Collaboration Functions (TypeScript translation)

```typescript
// Based on gitea/models/repo/collaboration.go

export interface Collaboration {
  id: number;
  repo_id: number;
  user_id: number;
  mode: 'read' | 'write' | 'admin';
  created_at: Date;
  updated_at: Date;
}

export async function getCollaborators(repoId: number) {
  return sql`
    SELECT c.*, u.username, u.display_name
    FROM collaborators c
    JOIN users u ON c.user_id = u.id
    WHERE c.repo_id = ${repoId}
    ORDER BY c.created_at
  `;
}

export async function isCollaborator(repoId: number, userId: number): Promise<boolean> {
  const [result] = await sql`
    SELECT 1 FROM collaborators
    WHERE repo_id = ${repoId} AND user_id = ${userId}
  `;
  return !!result;
}

export async function changeCollaborationAccessMode(
  repoId: number,
  userId: number,
  mode: 'read' | 'write' | 'admin'
) {
  await sql`
    UPDATE collaborators
    SET mode = ${mode}, updated_at = NOW()
    WHERE repo_id = ${repoId} AND user_id = ${userId}
  `;
}
```

### 4.3 Transfer Logic (TypeScript translation)

```typescript
// Based on gitea/services/repository/transfer.go

export async function transferOwnership(
  doer: User,
  newOwnerName: string,
  repo: Repository
) {
  // Get new owner
  const [newOwner] = await sql`
    SELECT * FROM users WHERE username = ${newOwnerName}
  `;

  if (!newOwner) {
    throw new Error('New owner not found');
  }

  // Check if repository exists for new owner
  const [existing] = await sql`
    SELECT id FROM repositories
    WHERE user_id = ${newOwner.id} AND name = ${repo.name}
  `;

  if (existing) {
    throw new Error('Repository already exists for new owner');
  }

  const oldOwnerName = repo.owner_name;

  // Rename repository directory
  const oldPath = `/tmp/repos/${oldOwnerName}/${repo.name}.git`;
  const newPath = `/tmp/repos/${newOwnerName}/${repo.name}.git`;
  renameSync(oldPath, newPath);

  // Update repository
  await sql`
    UPDATE repositories
    SET user_id = ${newOwner.id}, owner_name = ${newOwnerName}, updated_at = NOW()
    WHERE id = ${repo.id}
  `;

  // Remove collaborators who are now redundant
  await sql`
    DELETE FROM collaborators
    WHERE repo_id = ${repo.id} AND user_id = ${newOwner.id}
  `;

  // Delete transfer request
  await sql`DELETE FROM repository_transfers WHERE repo_id = ${repo.id}`;
}
```

### 4.4 Delete Repository Logic (TypeScript translation)

```typescript
// Based on gitea/services/repository/delete.go

export async function deleteRepository(repo: Repository) {
  // Delete repository directory
  const repoPath = `/tmp/repos/${repo.owner_name}/${repo.name}.git`;
  rmSync(repoPath, { recursive: true, force: true });

  // Database cleanup happens via CASCADE constraints:
  // - issues (and comments)
  // - collaborators
  // - repository_transfers

  await sql`DELETE FROM repositories WHERE id = ${repo.id}`;
}
```

---

## 5. Implementation Checklist

### Phase 1: Database Setup
- [ ] Create migration script for new tables (`collaborators`, `repository_transfers`)
- [ ] Add new columns to `repositories` table
- [ ] Create indexes for performance
- [ ] Test CASCADE delete behavior

### Phase 2: API Endpoints
- [ ] Implement GET `/settings` endpoint
- [ ] Implement POST `/settings/general` (update name, description, website, template)
- [ ] Implement POST `/settings/visibility` (toggle public/private)
- [ ] Implement collaborator CRUD endpoints
- [ ] Implement archive/unarchive endpoints
- [ ] Implement transfer endpoints (create, accept, cancel)
- [ ] Implement delete endpoint
- [ ] Add validation with Zod schemas
- [ ] Add permission checks (owner/admin only)

### Phase 3: UI Pages
- [ ] Create settings layout with tab navigation
- [ ] Build general settings form
- [ ] Build collaborators management page
- [ ] Build danger zone page
- [ ] Add client-side validation
- [ ] Add confirmation dialogs for dangerous operations
- [ ] Style with brutalist CSS

### Phase 4: Integration
- [ ] Add "Settings" link to repository navigation
- [ ] Update repository list to show archived status
- [ ] Add permission checks to all repo pages (archived = read-only)
- [ ] Add transfer acceptance notifications/page
- [ ] Test repository rename (redirects still work)

### Phase 5: Testing
- [ ] Test adding/removing collaborators
- [ ] Test changing collaborator permissions
- [ ] Test repository rename
- [ ] Test visibility toggle
- [ ] Test archive/unarchive
- [ ] Test transfer flow (initiate, accept, cancel)
- [ ] Test delete with confirmation
- [ ] Test CASCADE deletes work correctly

---

## 6. Security Considerations

1. **Permission Checks**: Only repository owner or admins can access settings
2. **Transfer Validation**: Confirm repository name before dangerous operations
3. **Collaborator Limits**: Prevent adding owner as collaborator
4. **Archive Protection**: Archived repos should be read-only
5. **SQL Injection**: Use parameterized queries (already using `@neondatabase/serverless`)
6. **Directory Traversal**: Validate repository names to prevent path manipulation

---

## 7. Future Enhancements

1. **Teams**: Add team-based permissions (for organization repos)
2. **Deploy Keys**: SSH keys for CI/CD read-only access
3. **Webhooks**: Trigger external services on repo events
4. **Branch Protection**: Require reviews, status checks before merging
5. **Repository Templates**: Create repos from templates with initial files
6. **Repository Size Limits**: Enforce storage quotas
7. **Audit Log**: Track all settings changes

---

## Notes

- Repository paths are currently hardcoded to `/tmp/repos`. In production, use environment variable.
- Git operations use `fs` sync methods. Consider async alternatives for production.
- No authentication layer yet. Add session/token checks before implementing.
- Transfer requests create a pending state. Consider adding email notifications.
- Archive status should disable push operations. Implement in git hooks or middleware.
