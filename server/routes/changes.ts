/**
 * Changes API Routes
 *
 * Provides access to jj changes (commits with stable IDs).
 * Changes are the fundamental unit of work in jj.
 */

import { Hono } from "hono";
import { sql } from "../../ui/lib/db";
import * as jj from "../../ui/lib/jj";
import type { Change, Conflict } from "../../ui/lib/jj-types";

const app = new Hono();

// =============================================================================
// List Changes
// =============================================================================

app.get("/:user/:repo/changes", async (c) => {
  const { user, repo } = c.req.param();
  const bookmark = c.req.query("bookmark");
  const limit = parseInt(c.req.query("limit") || "50");

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

    // Get changes from jj
    const changes = await jj.listChanges(user, repo, limit, bookmark);

    // Optionally cache in database for faster future queries
    for (const change of changes.slice(0, 20)) {
      await sql`
        INSERT INTO changes (
          change_id, repository_id, commit_id, description,
          author_name, author_email, timestamp, is_empty, has_conflicts
        )
        VALUES (
          ${change.changeId}, ${repository.id}, ${change.commitId},
          ${change.description}, ${change.author.name}, ${change.author.email},
          ${change.timestamp}, ${change.isEmpty}, ${change.hasConflicts}
        )
        ON CONFLICT (change_id) DO UPDATE SET
          commit_id = EXCLUDED.commit_id,
          has_conflicts = EXCLUDED.has_conflicts
      `.catch(() => {}); // Ignore cache failures
    }

    return c.json({
      changes,
      bookmark: bookmark || null,
    });
  } catch (error: unknown) {
    console.error('Error listing changes:', error);
    return c.json({ error: "Failed to list changes" }, 500);
  }
});

// =============================================================================
// Get Single Change
// =============================================================================

app.get("/:user/:repo/changes/:changeId", async (c) => {
  const { user, repo, changeId } = c.req.param();

  try {
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Get change details from jj
    const change = await jj.getChange(user, repo, changeId);

    if (!change) {
      return c.json({ error: "Change not found" }, 404);
    }

    return c.json({ change });
  } catch (error: unknown) {
    console.error('Error getting change:', error);
    return c.json({ error: "Failed to get change" }, 500);
  }
});

// =============================================================================
// Get Change Files
// =============================================================================

app.get("/:user/:repo/changes/:changeId/files", async (c) => {
  const { user, repo, changeId } = c.req.param();
  const path = c.req.query("path") || "";

  try {
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Get file tree at this change
    const files = await jj.getTree(user, repo, changeId, path);

    return c.json({ files, path });
  } catch (error: unknown) {
    console.error('Error getting change files:', error);
    return c.json({ error: "Failed to get change files" }, 500);
  }
});

// =============================================================================
// Get File Content at Change
// =============================================================================

app.get("/:user/:repo/changes/:changeId/file/*", async (c) => {
  const { user, repo, changeId } = c.req.param();
  const filePath = c.req.path.split('/file/')[1] || '';

  try {
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const content = await jj.getFileContent(user, repo, changeId, filePath);

    if (content === null) {
      return c.json({ error: "File not found" }, 404);
    }

    return c.json({ content, path: filePath });
  } catch (error: unknown) {
    console.error('Error getting file content:', error);
    return c.json({ error: "Failed to get file content" }, 500);
  }
});

// =============================================================================
// Get Change Diff
// =============================================================================

app.get("/:user/:repo/changes/:changeId/diff", async (c) => {
  const { user, repo, changeId } = c.req.param();

  try {
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const diff = await jj.getDiff(user, repo, changeId);

    return c.json({ diff });
  } catch (error: unknown) {
    console.error('Error getting change diff:', error);
    return c.json({ error: "Failed to get change diff" }, 500);
  }
});

// =============================================================================
// Compare Two Changes
// =============================================================================

app.get("/:user/:repo/changes/:fromChangeId/compare/:toChangeId", async (c) => {
  const { user, repo, fromChangeId, toChangeId } = c.req.param();

  try {
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const comparison = await jj.compareChanges(user, repo, fromChangeId, toChangeId);

    return c.json({ comparison });
  } catch (error: unknown) {
    console.error('Error comparing changes:', error);
    return c.json({ error: "Failed to compare changes" }, 500);
  }
});

// =============================================================================
// Get Change Conflicts
// =============================================================================

app.get("/:user/:repo/changes/:changeId/conflicts", async (c) => {
  const { user, repo, changeId } = c.req.param();

  try {
    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Get conflicts from jj
    const conflicts = await jj.getConflicts(user, repo, changeId);

    // Also check database for resolution status
    const dbConflicts = await sql<Conflict[]>`
      SELECT * FROM conflicts
      WHERE repository_id = ${repository.id}
        AND change_id = ${changeId}
    `;

    // Merge jj conflicts with db resolution status
    const mergedConflicts = conflicts.map(conflict => {
      const dbConflict = dbConflicts.find(c => c.filePath === conflict.filePath);
      return {
        ...conflict,
        resolved: dbConflict?.resolved || false,
        resolvedBy: dbConflict?.resolvedBy || null,
        resolutionMethod: dbConflict?.resolutionMethod || null,
      };
    });

    return c.json({ conflicts: mergedConflicts });
  } catch (error: unknown) {
    console.error('Error getting change conflicts:', error);
    return c.json({ error: "Failed to get change conflicts" }, 500);
  }
});

// =============================================================================
// Mark Conflict Resolved
// =============================================================================

app.post("/:user/:repo/changes/:changeId/conflicts/:filePath/resolve", async (c) => {
  const { user, repo, changeId } = c.req.param();
  const filePath = decodeURIComponent(c.req.param("filePath") || "");

  try {
    const { method } = await c.req.json();

    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Record resolution in database
    await sql`
      INSERT INTO conflicts (
        repository_id, change_id, file_path, conflict_type,
        resolved, resolved_by, resolution_method, resolved_at
      )
      VALUES (
        ${repository.id}, ${changeId}, ${filePath}, 'content',
        true, ${repository.user_id}, ${method || 'manual'}, NOW()
      )
      ON CONFLICT (change_id, file_path) DO UPDATE SET
        resolved = true,
        resolved_by = EXCLUDED.resolved_by,
        resolution_method = EXCLUDED.resolution_method,
        resolved_at = EXCLUDED.resolved_at
    `;

    return c.json({ success: true });
  } catch (error: unknown) {
    console.error('Error resolving conflict:', error);
    return c.json({ error: "Failed to resolve conflict" }, 500);
  }
});

export default app;
