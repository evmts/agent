/**
 * Landing Queue API Routes
 *
 * Replaces pull requests with jj-native "landing" workflow.
 * Changes are queued for landing onto bookmarks with conflict detection.
 */

import { Hono } from "hono";
import { sql } from "../../ui/lib/db";
import * as jj from "../../ui/lib/jj";
import type { LandingRequest, LandingReview } from "../../ui/lib/jj-types";

const app = new Hono();

// =============================================================================
// List Landing Queue
// =============================================================================

app.get("/:user/:repo/landing", async (c) => {
  const { user, repo } = c.req.param();
  const status = c.req.query("status");
  const page = parseInt(c.req.query("page") || "1");
  const limit = parseInt(c.req.query("limit") || "20");
  const offset = (page - 1) * limit;

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

    // Build query with optional status filter
    let requests: LandingRequest[];
    let count: number;

    if (status) {
      requests = await sql<LandingRequest[]>`
        SELECT lq.*,
          json_build_object(
            'id', u.id,
            'username', u.username,
            'displayName', u.display_name
          ) as author
        FROM landing_queue lq
        LEFT JOIN users u ON lq.author_id = u.id
        WHERE lq.repository_id = ${repository.id}
          AND lq.status = ${status}
        ORDER BY lq.created_at DESC
        LIMIT ${limit} OFFSET ${offset}
      `;

      const [countResult] = await sql`
        SELECT COUNT(*) as count FROM landing_queue
        WHERE repository_id = ${repository.id}
          AND status = ${status}
      `;
      count = Number(countResult.count);
    } else {
      requests = await sql<LandingRequest[]>`
        SELECT lq.*,
          json_build_object(
            'id', u.id,
            'username', u.username,
            'displayName', u.display_name
          ) as author
        FROM landing_queue lq
        LEFT JOIN users u ON lq.author_id = u.id
        WHERE lq.repository_id = ${repository.id}
        ORDER BY
          CASE WHEN lq.status IN ('pending', 'checking', 'ready') THEN 0 ELSE 1 END,
          lq.created_at DESC
        LIMIT ${limit} OFFSET ${offset}
      `;

      const [countResult] = await sql`
        SELECT COUNT(*) as count FROM landing_queue
        WHERE repository_id = ${repository.id}
      `;
      count = Number(countResult.count);
    }

    return c.json({
      requests,
      total: count,
      page,
      limit,
    });
  } catch (error: unknown) {
    console.error('Error listing landing queue:', error);
    return c.json({ error: "Failed to list landing queue" }, 500);
  }
});

// =============================================================================
// Get Single Landing Request
// =============================================================================

app.get("/:user/:repo/landing/:id", async (c) => {
  const { user, repo, id } = c.req.param();

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

    const [request] = await sql<LandingRequest[]>`
      SELECT lq.*,
        json_build_object(
          'id', u.id,
          'username', u.username,
          'displayName', u.display_name
        ) as author
      FROM landing_queue lq
      LEFT JOIN users u ON lq.author_id = u.id
      WHERE lq.repository_id = ${repository.id}
        AND lq.id = ${id}
    `;

    if (!request) {
      return c.json({ error: "Landing request not found" }, 404);
    }

    // Get change details
    const change = await jj.getChange(user, repo, request.changeId);

    // Get reviews
    const reviews = await sql<LandingReview[]>`
      SELECT lr.*,
        json_build_object(
          'id', u.id,
          'username', u.username,
          'displayName', u.display_name
        ) as reviewer
      FROM landing_reviews lr
      LEFT JOIN users u ON lr.reviewer_id = u.id
      WHERE lr.landing_id = ${id}
      ORDER BY lr.created_at ASC
    `;

    return c.json({
      request: {
        ...request,
        change,
      },
      reviews,
    });
  } catch (error: unknown) {
    console.error('Error getting landing request:', error);
    return c.json({ error: "Failed to get landing request" }, 500);
  }
});

// =============================================================================
// Create Landing Request
// =============================================================================

app.post("/:user/:repo/landing", async (c) => {
  const { user, repo } = c.req.param();

  try {
    const { change_id, target_bookmark, title, description } = await c.req.json();

    if (!change_id || !target_bookmark) {
      return c.json({ error: "Missing required fields: change_id, target_bookmark" }, 400);
    }

    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Check if change exists
    const change = await jj.getChange(user, repo, change_id);
    if (!change) {
      return c.json({ error: "Change not found" }, 404);
    }

    // Check if landing request already exists for this change
    const [existing] = await sql`
      SELECT id FROM landing_queue
      WHERE repository_id = ${repository.id}
        AND change_id = ${change_id}
        AND status NOT IN ('landed', 'cancelled')
    `;

    if (existing) {
      return c.json({ error: "Landing request already exists for this change" }, 409);
    }

    // Check for conflicts
    const { landable, conflictedFiles } = await jj.checkLandable(user, repo, change_id, target_bookmark);

    // Create landing request
    const [request] = await sql`
      INSERT INTO landing_queue (
        repository_id, change_id, target_bookmark,
        title, description, author_id,
        status, has_conflicts, conflicted_files
      )
      VALUES (
        ${repository.id}, ${change_id}, ${target_bookmark},
        ${title || change.description}, ${description || null},
        ${repository.user_id},
        ${landable ? 'ready' : 'conflicted'},
        ${!landable}, ${conflictedFiles.length > 0 ? conflictedFiles : null}
      )
      RETURNING *
    `;

    return c.json({ request }, 201);
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Failed to create landing request";
    console.error('Error creating landing request:', error);
    return c.json({ error: message }, 400);
  }
});

// =============================================================================
// Check Landing Status (refresh conflict check)
// =============================================================================

app.post("/:user/:repo/landing/:id/check", async (c) => {
  const { user, repo, id } = c.req.param();

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

    const [request] = await sql<LandingRequest[]>`
      SELECT * FROM landing_queue
      WHERE repository_id = ${repository.id} AND id = ${id}
    `;

    if (!request) {
      return c.json({ error: "Landing request not found" }, 404);
    }

    if (request.status === 'landed' || request.status === 'cancelled') {
      return c.json({ error: "Landing request is already complete" }, 400);
    }

    // Update status to checking
    await sql`
      UPDATE landing_queue
      SET status = 'checking', updated_at = NOW()
      WHERE id = ${id}
    `;

    // Check for conflicts
    const { landable, conflictedFiles } = await jj.checkLandable(
      user, repo,
      request.changeId,
      request.targetBookmark
    );

    // Update status
    await sql`
      UPDATE landing_queue
      SET status = ${landable ? 'ready' : 'conflicted'},
          has_conflicts = ${!landable},
          conflicted_files = ${conflictedFiles.length > 0 ? conflictedFiles : null},
          updated_at = NOW()
      WHERE id = ${id}
    `;

    return c.json({
      status: landable ? 'ready' : 'conflicted',
      hasConflicts: !landable,
      conflictedFiles,
    });
  } catch (error: unknown) {
    console.error('Error checking landing status:', error);
    return c.json({ error: "Failed to check landing status" }, 500);
  }
});

// =============================================================================
// Execute Landing
// =============================================================================

app.post("/:user/:repo/landing/:id/land", async (c) => {
  const { user, repo, id } = c.req.param();

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

    const [request] = await sql<LandingRequest[]>`
      SELECT * FROM landing_queue
      WHERE repository_id = ${repository.id} AND id = ${id}
    `;

    if (!request) {
      return c.json({ error: "Landing request not found" }, 404);
    }

    if (request.status === 'landed') {
      return c.json({ error: "Already landed" }, 400);
    }

    if (request.status === 'cancelled') {
      return c.json({ error: "Landing request was cancelled" }, 400);
    }

    if (request.status === 'conflicted') {
      return c.json({ error: "Cannot land with unresolved conflicts" }, 400);
    }

    // Get user info for commit
    const [author] = await sql`
      SELECT username, email FROM users WHERE id = ${request.authorId}
    `;

    // Execute landing
    const landedChangeId = await jj.landChange(
      user, repo,
      request.changeId,
      request.targetBookmark,
      author?.username || 'Plue',
      author?.email || 'plue@local'
    );

    // Update landing request
    await sql`
      UPDATE landing_queue
      SET status = 'landed',
          landed_at = NOW(),
          landed_by = ${repository.user_id},
          landed_change_id = ${landedChangeId},
          updated_at = NOW()
      WHERE id = ${id}
    `;

    // Update bookmark in database
    await sql`
      UPDATE bookmarks
      SET target_change_id = ${landedChangeId},
          updated_at = NOW()
      WHERE repository_id = ${repository.id}
        AND name = ${request.targetBookmark}
    `;

    return c.json({
      success: true,
      landedChangeId,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Failed to land change";
    console.error('Error landing change:', error);
    return c.json({ error: message }, 400);
  }
});

// =============================================================================
// Cancel Landing Request
// =============================================================================

app.delete("/:user/:repo/landing/:id", async (c) => {
  const { user, repo, id } = c.req.param();

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

    const [request] = await sql<LandingRequest[]>`
      SELECT * FROM landing_queue
      WHERE repository_id = ${repository.id} AND id = ${id}
    `;

    if (!request) {
      return c.json({ error: "Landing request not found" }, 404);
    }

    if (request.status === 'landed') {
      return c.json({ error: "Cannot cancel a landed request" }, 400);
    }

    // Update status to cancelled
    await sql`
      UPDATE landing_queue
      SET status = 'cancelled', updated_at = NOW()
      WHERE id = ${id}
    `;

    return c.json({ success: true });
  } catch (error: unknown) {
    console.error('Error cancelling landing request:', error);
    return c.json({ error: "Failed to cancel landing request" }, 500);
  }
});

// =============================================================================
// Add Review
// =============================================================================

app.post("/:user/:repo/landing/:id/reviews", async (c) => {
  const { user, repo, id } = c.req.param();

  try {
    const { type, content } = await c.req.json();

    if (!type) {
      return c.json({ error: "Missing required field: type" }, 400);
    }

    const [repository] = await sql`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const [request] = await sql<LandingRequest[]>`
      SELECT * FROM landing_queue
      WHERE repository_id = ${repository.id} AND id = ${id}
    `;

    if (!request) {
      return c.json({ error: "Landing request not found" }, 404);
    }

    // Create review
    const [review] = await sql`
      INSERT INTO landing_reviews (
        landing_id, reviewer_id, type, content, change_id
      )
      VALUES (
        ${id}, ${repository.user_id}, ${type},
        ${content || null}, ${request.changeId}
      )
      RETURNING *
    `;

    return c.json({ review }, 201);
  } catch (error: unknown) {
    console.error('Error adding review:', error);
    return c.json({ error: "Failed to add review" }, 500);
  }
});

// =============================================================================
// Get Landing Request Diff (files changed)
// =============================================================================

app.get("/:user/:repo/landing/:id/files", async (c) => {
  const { user, repo, id } = c.req.param();

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

    const [request] = await sql<LandingRequest[]>`
      SELECT * FROM landing_queue
      WHERE repository_id = ${repository.id} AND id = ${id}
    `;

    if (!request) {
      return c.json({ error: "Landing request not found" }, 404);
    }

    // Get diff files
    const diff = await jj.getDiff(user, repo, request.changeId);

    return c.json({ files: diff });
  } catch (error: unknown) {
    console.error('Error getting landing files:', error);
    return c.json({ error: "Failed to get landing files" }, 500);
  }
});

export default app;
