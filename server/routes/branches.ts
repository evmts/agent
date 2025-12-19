import { Hono } from "hono";
import { sql } from "../../ui/lib/db";
import * as git from "../../ui/lib/git";
import type { Branch, ProtectedBranch } from "../../ui/lib/types";

const app = new Hono();

// List branches
app.get("/:user/:repo/branches", async (c) => {
  const { user, repo } = c.req.param();
  const page = parseInt(c.req.query("page") || "1");
  const limit = parseInt(c.req.query("limit") || "20");
  const offset = (page - 1) * limit;

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
  } catch (error: any) {
    console.error('Error listing branches:', error);
    return c.json({ error: "Failed to list branches" }, 500);
  }
});

// Create branch
app.post("/:user/:repo/branches", async (c) => {
  const { user, repo } = c.req.param();
  
  try {
    const { name, from_ref } = await c.req.json();

    if (!name || !from_ref) {
      return c.json({ error: "Missing required fields" }, 400);
    }

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
    console.error('Error creating branch:', error);
    return c.json({ error: error.message || "Failed to create branch" }, 400);
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
    console.error('Error deleting branch:', error);
    return c.json({ error: error.message || "Failed to delete branch" }, 400);
  }
});

// Rename branch
app.patch("/:user/:repo/branches/:branch", async (c) => {
  const { user, repo, branch: oldName } = c.req.param();
  
  try {
    const { new_name } = await c.req.json();

    if (!new_name) {
      return c.json({ error: "Missing new_name" }, 400);
    }

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
    console.error('Error renaming branch:', error);
    return c.json({ error: error.message || "Failed to rename branch" }, 400);
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