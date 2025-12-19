import type { APIRoute } from 'astro';
import { sql } from '../../../../../lib/db';
import * as git from '../../../../../lib/git';
import type { ProtectedBranch } from '../../../../../lib/types';

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

// Delete branch
export const DELETE: APIRoute = async ({ params }) => {
  const { user, repo, branch: branchName } = params;

  if (!user || !repo || !branchName) {
    return new Response(JSON.stringify({ error: 'Missing parameters' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
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
      return new Response(JSON.stringify({ error: 'Repository not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Check if branch is protected
    const isProtected = await isBranchProtected(repository.id, branchName);
    if (isProtected) {
      return new Response(JSON.stringify({ error: 'Branch is protected' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Cannot delete default branch
    if (branchName === repository.default_branch) {
      return new Response(JSON.stringify({ error: 'Cannot delete default branch' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' }
      });
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

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error: any) {
    console.error('Error deleting branch:', error);
    return new Response(JSON.stringify({ error: error.message || 'Failed to delete branch' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

// Rename branch
export const PATCH: APIRoute = async ({ params, request }) => {
  const { user, repo, branch: oldName } = params;

  if (!user || !repo || !oldName) {
    return new Response(JSON.stringify({ error: 'Missing parameters' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const { new_name } = await request.json();

    if (!new_name) {
      return new Response(JSON.stringify({ error: 'Missing new_name' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get repository
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return new Response(JSON.stringify({ error: 'Repository not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Check if branch is protected
    const isProtected = await isBranchProtected(repository.id, oldName);
    if (isProtected) {
      return new Response(JSON.stringify({ error: 'Branch is protected' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' }
      });
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

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error: any) {
    console.error('Error renaming branch:', error);
    return new Response(JSON.stringify({ error: error.message || 'Failed to rename branch' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};