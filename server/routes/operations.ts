/**
 * Operations API Routes
 *
 * Provides access to jj's operation log for undo/redo functionality.
 * Every jj action is tracked as an operation that can be undone.
 */

import { Hono } from "hono";
import { sql } from "../../ui/lib/db";
import * as jj from "../../ui/lib/jj";
import type { Operation } from "../../ui/lib/jj-types";

const app = new Hono();

// =============================================================================
// List Operations
// =============================================================================

app.get("/:user/:repo/operations", async (c) => {
  const { user, repo } = c.req.param();
  const limit = parseInt(c.req.query("limit") || "20");

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

    // Get operations from jj
    const operations = await jj.getOperationLog(user, repo, limit);

    // Cache operations in database
    for (const op of operations) {
      await sql`
        INSERT INTO jj_operations (
          repository_id, operation_id, operation_type,
          description, timestamp
        )
        VALUES (
          ${repository.id}, ${op.operationId}, ${op.type},
          ${op.description}, ${op.timestamp}
        )
        ON CONFLICT DO NOTHING
      `.catch(() => {}); // Ignore cache failures
    }

    return c.json({ operations });
  } catch (error: unknown) {
    console.error('Error listing operations:', error);
    return c.json({ error: "Failed to list operations" }, 500);
  }
});

// =============================================================================
// Get Single Operation
// =============================================================================

app.get("/:user/:repo/operations/:operationId", async (c) => {
  const { user, repo, operationId } = c.req.param();

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

    // Get from database first
    const [operation] = await sql<Operation[]>`
      SELECT * FROM jj_operations
      WHERE repository_id = ${repository.id}
        AND operation_id = ${operationId}
    `;

    if (!operation) {
      // Try to find in jj op log
      const operations = await jj.getOperationLog(user, repo, 100);
      const jjOp = operations.find(op => op.operationId === operationId);

      if (!jjOp) {
        return c.json({ error: "Operation not found" }, 404);
      }

      return c.json({ operation: jjOp });
    }

    return c.json({ operation });
  } catch (error: unknown) {
    console.error('Error getting operation:', error);
    return c.json({ error: "Failed to get operation" }, 500);
  }
});

// =============================================================================
// Undo Last Operation
// =============================================================================

app.post("/:user/:repo/operations/undo", async (c) => {
  const { user, repo } = c.req.param();

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

    // Undo in jj
    await jj.undoOperation(user, repo);

    // Record the undo operation
    await sql`
      INSERT INTO jj_operations (
        repository_id, operation_id, operation_type,
        description, timestamp
      )
      VALUES (
        ${repository.id}, ${`undo-${Date.now()}`}, 'undo',
        'Undo last operation', ${Date.now()}
      )
    `;

    return c.json({ success: true });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Failed to undo operation";
    console.error('Error undoing operation:', error);
    return c.json({ error: message }, 400);
  }
});

// =============================================================================
// Restore to Specific Operation
// =============================================================================

app.post("/:user/:repo/operations/:operationId/restore", async (c) => {
  const { user, repo, operationId } = c.req.param();

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

    // Restore in jj
    await jj.restoreOperation(user, repo, operationId);

    // Mark intermediate operations as undone
    await sql`
      UPDATE jj_operations
      SET is_undone = true
      WHERE repository_id = ${repository.id}
        AND timestamp > (
          SELECT timestamp FROM jj_operations
          WHERE repository_id = ${repository.id}
            AND operation_id = ${operationId}
        )
    `;

    // Record the restore operation
    await sql`
      INSERT INTO jj_operations (
        repository_id, operation_id, operation_type,
        description, timestamp
      )
      VALUES (
        ${repository.id}, ${`restore-${Date.now()}`}, 'restore',
        ${`Restore to operation ${operationId}`}, ${Date.now()}
      )
    `;

    return c.json({ success: true });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Failed to restore operation";
    console.error('Error restoring operation:', error);
    return c.json({ error: message }, 400);
  }
});

export default app;
