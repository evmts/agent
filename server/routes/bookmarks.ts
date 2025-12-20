/**
 * Bookmarks API Routes
 *
 * Replaces branches.ts with jj-native bookmark operations.
 * Bookmarks are movable labels pointing to change IDs.
 */

import { Hono } from "hono";
import { sql } from "../../ui/lib/db";
import * as jj from "../../ui/lib/jj";
import type { Bookmark, ProtectedBookmark } from "../../ui/lib/jj-types";
import { requireAuth } from "../middleware/auth";

const app = new Hono();

// =============================================================================
// List Bookmarks
// =============================================================================

app.get("/:user/:repo/bookmarks", async (c) => {
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

    // Get bookmarks from database
    const bookmarks = await sql<Bookmark[]>`
      SELECT b.*, u.username as pusher_username
      FROM bookmarks b
      LEFT JOIN users u ON b.pusher_id = u.id
      WHERE b.repository_id = ${repository.id}
      ORDER BY
        CASE WHEN b.is_default THEN 0 ELSE 1 END,
        b.updated_at DESC
      LIMIT ${limit} OFFSET ${offset}
    `;

    const [{ count }] = await sql`
      SELECT COUNT(*) as count FROM bookmarks
      WHERE repository_id = ${repository.id}
    `;

    // If no bookmarks in DB, try to sync from jj
    if (bookmarks.length === 0) {
      const jjBookmarks = await jj.listBookmarks(user, repo);
      return c.json({
        bookmarks: jjBookmarks,
        total: jjBookmarks.length,
        page,
        limit,
        synced: true,
      });
    }

    return c.json({
      bookmarks,
      total: Number(count),
      page,
      limit,
    });
  } catch (error: unknown) {
    console.error('Error listing bookmarks:', error);
    return c.json({ error: "Failed to list bookmarks" }, 500);
  }
});

// =============================================================================
// Get Single Bookmark
// =============================================================================

app.get("/:user/:repo/bookmarks/:name", async (c) => {
  const { user, repo, name } = c.req.param();

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

    const [bookmark] = await sql<Bookmark[]>`
      SELECT b.*, u.username as pusher_username
      FROM bookmarks b
      LEFT JOIN users u ON b.pusher_id = u.id
      WHERE b.repository_id = ${repository.id}
        AND b.name = ${name}
    `;

    if (!bookmark) {
      return c.json({ error: "Bookmark not found" }, 404);
    }

    return c.json({ bookmark });
  } catch (error: unknown) {
    console.error('Error getting bookmark:', error);
    return c.json({ error: "Failed to get bookmark" }, 500);
  }
});

// =============================================================================
// Create Bookmark
// =============================================================================

app.post("/:user/:repo/bookmarks", requireAuth, async (c) => {
  const { user, repo } = c.req.param();

  try {
    const { name, change_id } = await c.req.json();

    if (!name) {
      return c.json({ error: "Missing required field: name" }, 400);
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

    // Check if bookmark exists
    const [existing] = await sql`
      SELECT id FROM bookmarks
      WHERE repository_id = ${repository.id}
        AND name = ${name}
    `;

    if (existing) {
      return c.json({ error: "Bookmark already exists" }, 409);
    }

    // Create bookmark in jj
    await jj.createBookmark(user, repo, name, change_id);

    // Get the target change ID
    const targetChangeId = change_id || await jj.getCurrentChange(user, repo);

    // Create bookmark record
    const [bookmark] = await sql`
      INSERT INTO bookmarks (
        repository_id, name, target_change_id, pusher_id
      )
      VALUES (
        ${repository.id}, ${name}, ${targetChangeId}, ${repository.user_id}
      )
      RETURNING *
    `;

    return c.json({ bookmark }, 201);
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Failed to create bookmark";
    console.error('Error creating bookmark:', error);
    return c.json({ error: message }, 400);
  }
});

// =============================================================================
// Delete Bookmark
// =============================================================================

app.delete("/:user/:repo/bookmarks/:name", requireAuth, async (c) => {
  const { user, repo, name } = c.req.param();

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

    // Check if bookmark is protected
    const isProtected = await isBookmarkProtected(repository.id, name);
    if (isProtected) {
      return c.json({ error: "Bookmark is protected" }, 403);
    }

    // Cannot delete default bookmark
    const defaultBookmark = repository.default_bookmark || 'main';
    if (name === defaultBookmark) {
      return c.json({ error: "Cannot delete default bookmark" }, 403);
    }

    // Delete from jj
    await jj.deleteBookmark(user, repo, name);

    // Delete from database
    await sql`
      DELETE FROM bookmarks
      WHERE repository_id = ${repository.id}
        AND name = ${name}
    `;

    return c.json({ success: true });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Failed to delete bookmark";
    console.error('Error deleting bookmark:', error);
    return c.json({ error: message }, 400);
  }
});

// =============================================================================
// Move Bookmark (Update target change)
// =============================================================================

app.patch("/:user/:repo/bookmarks/:name", requireAuth, async (c) => {
  const { user, repo, name } = c.req.param();

  try {
    const { change_id } = await c.req.json();

    if (!change_id) {
      return c.json({ error: "Missing change_id" }, 400);
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

    // Check if bookmark is protected and requires landing queue
    const protection = await getBookmarkProtection(repository.id, name);
    if (protection?.requireLandingQueue) {
      return c.json({
        error: "This bookmark requires using the landing queue to update",
        requiresLanding: true,
      }, 403);
    }

    // Move bookmark in jj
    await jj.moveBookmark(user, repo, name, change_id);

    // Update database
    const [bookmark] = await sql`
      UPDATE bookmarks
      SET target_change_id = ${change_id},
          updated_at = NOW(),
          pusher_id = ${repository.user_id}
      WHERE repository_id = ${repository.id} AND name = ${name}
      RETURNING *
    `;

    if (!bookmark) {
      // Bookmark doesn't exist in DB yet, create it
      const [newBookmark] = await sql`
        INSERT INTO bookmarks (
          repository_id, name, target_change_id, pusher_id
        )
        VALUES (
          ${repository.id}, ${name}, ${change_id}, ${repository.user_id}
        )
        RETURNING *
      `;
      return c.json({ bookmark: newBookmark });
    }

    return c.json({ bookmark });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Failed to move bookmark";
    console.error('Error moving bookmark:', error);
    return c.json({ error: message }, 400);
  }
});

// =============================================================================
// Set Default Bookmark
// =============================================================================

app.post("/:user/:repo/bookmarks/:name/set-default", requireAuth, async (c) => {
  const { user, repo, name } = c.req.param();

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

    // Check bookmark exists
    const [bookmark] = await sql`
      SELECT id FROM bookmarks
      WHERE repository_id = ${repository.id} AND name = ${name}
    `;

    if (!bookmark) {
      return c.json({ error: "Bookmark not found" }, 404);
    }

    // Clear existing default
    await sql`
      UPDATE bookmarks
      SET is_default = false
      WHERE repository_id = ${repository.id}
    `;

    // Set new default
    await sql`
      UPDATE bookmarks
      SET is_default = true
      WHERE repository_id = ${repository.id} AND name = ${name}
    `;

    // Update repository
    await sql`
      UPDATE repositories
      SET default_bookmark = ${name}
      WHERE id = ${repository.id}
    `;

    return c.json({ success: true });
  } catch (error: unknown) {
    console.error('Error setting default bookmark:', error);
    return c.json({ error: "Failed to set default bookmark" }, 500);
  }
});

// =============================================================================
// Helpers
// =============================================================================

async function isBookmarkProtected(repoId: number, bookmarkName: string): Promise<boolean> {
  const rules = await sql<ProtectedBookmark[]>`
    SELECT * FROM protected_bookmarks
    WHERE repository_id = ${repoId}
    ORDER BY priority DESC
  `;

  for (const rule of rules) {
    if (matchBookmarkPattern(rule.ruleName, bookmarkName)) {
      return true;
    }
  }

  return false;
}

async function getBookmarkProtection(
  repoId: number,
  bookmarkName: string
): Promise<ProtectedBookmark | null> {
  const rules = await sql<ProtectedBookmark[]>`
    SELECT * FROM protected_bookmarks
    WHERE repository_id = ${repoId}
    ORDER BY priority DESC
  `;

  for (const rule of rules) {
    if (matchBookmarkPattern(rule.ruleName, bookmarkName)) {
      return rule;
    }
  }

  return null;
}

function matchBookmarkPattern(pattern: string, bookmarkName: string): boolean {
  if (pattern === bookmarkName) return true;

  const regexPattern = pattern
    .replace(/\*/g, ".*")
    .replace(/\?/g, ".");

  const regex = new RegExp(`^${regexPattern}$`);
  return regex.test(bookmarkName);
}

export default app;
