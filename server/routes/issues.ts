/**
 * Issue routes - REST API for git-based issue tracking.
 *
 * Issues are stored in a nested git repository at .plue/issues/
 * within each project repository.
 */

import { Hono } from "hono";
import { requireAuth } from "../middleware/auth";
import {
  listIssues,
  getIssue,
  createIssue,
  updateIssue,
  closeIssue,
  reopenIssue,
  deleteIssue,
  pinIssue,
  unpinIssue,
  getComments,
  addComment,
  updateComment,
  deleteComment,
  getIssueHistory,
  getIssueCounts,
  getLabels,
  createLabel,
  updateLabel,
  deleteLabel,
  addLabelsToIssue,
  removeLabelFromIssue,
  ensureIssuesRepo,
  IssueNotFoundError,
  IssuesRepoNotInitializedError,
  GitOperationError,
} from "../../ui/lib/git-issues";
import {
  addDependency,
  removeDependency,
  getBlockingIssues,
  getBlockedByIssues,
  canCloseIssue,
} from "../../ui/lib/git-issue-dependencies";
import { sql } from "../../ui/lib/db";

const app = new Hono();

// =============================================================================
// Issue Routes
// =============================================================================

// List issues for a repository
app.get("/:user/:repo/issues", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const state = (c.req.query("state") || "open") as "open" | "closed" | "all";

  try {
    await ensureIssuesRepo(user, repo);
    const issues = await listIssues(user, repo, state);
    const counts = await getIssueCounts(user, repo);

    return c.json({
      issues,
      counts,
      total: issues.length,
    });
  } catch (error) {
    if (error instanceof IssuesRepoNotInitializedError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get a single issue with comments
app.get("/:user/:repo/issues/:number", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    const comments = await getComments(user, repo, number);

    return c.json({
      ...issue,
      comments,
    });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Create a new issue
app.post("/:user/:repo/issues", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const body = await c.req.json();

  if (!body.title) {
    return c.json({ error: "Title is required" }, 400);
  }

  if (!body.author || !body.author.id || !body.author.username) {
    return c.json({ error: "Author with id and username is required" }, 400);
  }

  try {
    await ensureIssuesRepo(user, repo);
    const issue = await createIssue(user, repo, {
      title: body.title,
      body: body.body || "",
      author: body.author,
      labels: body.labels,
      assignees: body.assignees,
      milestone: body.milestone,
    });

    return c.json(issue, 201);
  } catch (error) {
    if (error instanceof GitOperationError) {
      return c.json({ error: error.message }, 500);
    }
    throw error;
  }
});

// Update an issue
app.patch("/:user/:repo/issues/:number", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const body = await c.req.json();

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const issue = await updateIssue(user, repo, number, {
      title: body.title,
      body: body.body,
      state: body.state,
      labels: body.labels,
      assignees: body.assignees,
      milestone: body.milestone,
    });

    return c.json(issue);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof GitOperationError) {
      return c.json({ error: error.message }, 500);
    }
    throw error;
  }
});

// Close an issue
app.post("/:user/:repo/issues/:number/close", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    await closeIssue(user, repo, number);
    const issue = await getIssue(user, repo, number);
    return c.json(issue);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Reopen an issue
app.post("/:user/:repo/issues/:number/reopen", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    await reopenIssue(user, repo, number);
    const issue = await getIssue(user, repo, number);
    return c.json(issue);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Delete an issue
app.delete("/:user/:repo/issues/:number", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    await deleteIssue(user, repo, number);
    return c.json({ success: true });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Pin an issue
app.post("/:user/:repo/issues/:number/pin", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const issue = await pinIssue(user, repo, number);
    return c.json(issue);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof Error && error.message.includes("Maximum")) {
      return c.json({ error: error.message }, 400);
    }
    throw error;
  }
});

// Unpin an issue
app.post("/:user/:repo/issues/:number/unpin", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const issue = await unpinIssue(user, repo, number);
    return c.json(issue);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// =============================================================================
// Comment Routes
// =============================================================================

// Get comments for an issue
app.get("/:user/:repo/issues/:number/comments", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const comments = await getComments(user, repo, number);
    return c.json({ comments });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Add a comment to an issue
app.post("/:user/:repo/issues/:number/comments", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const body = await c.req.json();

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (!body.body) {
    return c.json({ error: "Comment body is required" }, 400);
  }

  if (!body.author || !body.author.id || !body.author.username) {
    return c.json({ error: "Author with id and username is required" }, 400);
  }

  try {
    const comment = await addComment(user, repo, number, {
      body: body.body,
      author: body.author,
    });

    return c.json(comment, 201);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof GitOperationError) {
      return c.json({ error: error.message }, 500);
    }
    throw error;
  }
});

// Update a comment
app.patch("/:user/:repo/issues/:number/comments/:commentId", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const commentId = parseInt(c.req.param("commentId"), 10);
  const body = await c.req.json();

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (isNaN(commentId)) {
    return c.json({ error: "Invalid comment ID" }, 400);
  }

  if (!body.body) {
    return c.json({ error: "Comment body is required" }, 400);
  }

  try {
    const comment = await updateComment(user, repo, number, commentId, {
      body: body.body,
    });

    return c.json(comment);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof Error && error.message.includes("not found")) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof GitOperationError) {
      return c.json({ error: error.message }, 500);
    }
    throw error;
  }
});

// Delete a comment
app.delete("/:user/:repo/issues/:number/comments/:commentId", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const commentId = parseInt(c.req.param("commentId"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (isNaN(commentId)) {
    return c.json({ error: "Invalid comment ID" }, 400);
  }

  try {
    await deleteComment(user, repo, number, commentId);
    return c.json({ success: true });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof Error && error.message.includes("not found")) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof GitOperationError) {
      return c.json({ error: error.message }, 500);
    }
    throw error;
  }
});

// =============================================================================
// History and Metadata Routes
// =============================================================================

// Get issue history (git log)
app.get("/:user/:repo/issues/:number/history", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const history = await getIssueHistory(user, repo, number);
    return c.json({ history });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get issue counts
app.get("/:user/:repo/issues/counts", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");

  try {
    await ensureIssuesRepo(user, repo);
    const counts = await getIssueCounts(user, repo);
    return c.json(counts);
  } catch (error) {
    throw error;
  }
});

// =============================================================================
// Label Routes
// =============================================================================

// Get available labels for a repository
app.get("/:user/:repo/labels", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");

  try {
    await ensureIssuesRepo(user, repo);
    const labels = await getLabels(user, repo);
    return c.json({ labels });
  } catch (error) {
    throw error;
  }
});

// Create a new label
app.post("/:user/:repo/labels", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const body = await c.req.json();

  if (!body.name || !body.color) {
    return c.json({ error: "Name and color are required" }, 400);
  }

  // Validate color format (hex)
  if (!/^#[0-9A-Fa-f]{6}$/.test(body.color)) {
    return c.json({ error: "Color must be a valid hex color (e.g., #ff0000)" }, 400);
  }

  try {
    await createLabel(user, repo, {
      name: body.name,
      color: body.color,
      description: body.description,
    });

    const labels = await getLabels(user, repo);
    return c.json({ labels }, 201);
  } catch (error) {
    if (error instanceof Error && error.message.includes("already exists")) {
      return c.json({ error: error.message }, 409);
    }
    throw error;
  }
});

// Update a label
app.patch("/:user/:repo/labels/:name", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const name = decodeURIComponent(c.req.param("name"));
  const body = await c.req.json();

  if (!body.name || !body.color) {
    return c.json({ error: "Name and color are required" }, 400);
  }

  // Validate color format (hex)
  if (!/^#[0-9A-Fa-f]{6}$/.test(body.color)) {
    return c.json({ error: "Color must be a valid hex color (e.g., #ff0000)" }, 400);
  }

  try {
    await updateLabel(user, repo, name, {
      name: body.name,
      color: body.color,
      description: body.description,
    });

    const labels = await getLabels(user, repo);
    return c.json({ labels });
  } catch (error) {
    if (error instanceof Error && error.message.includes("not found")) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Delete a label
app.delete("/:user/:repo/labels/:name", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const name = decodeURIComponent(c.req.param("name"));

  try {
    await deleteLabel(user, repo, name);
    return c.json({ success: true });
  } catch (error) {
    if (error instanceof Error && error.message.includes("not found")) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Add labels to an issue
app.post("/:user/:repo/issues/:number/labels", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const body = await c.req.json();

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (!Array.isArray(body.labels) || body.labels.length === 0) {
    return c.json({ error: "Labels array is required" }, 400);
  }

  try {
    const issue = await addLabelsToIssue(user, repo, number, body.labels);
    return c.json(issue);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Remove a label from an issue
app.delete("/:user/:repo/issues/:number/labels/:label", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const label = decodeURIComponent(c.req.param("label"));

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const issue = await removeLabelFromIssue(user, repo, number, label);
    return c.json(issue);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// =============================================================================
// Assignee Routes
// =============================================================================

// Get assignees for an issue
app.get("/:user/:repo/issues/:number/assignees", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    // Return assignees from git issue frontmatter
    return c.json({ assignees: issue.assignees || [] });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Add an assignee to an issue
app.post("/:user/:repo/issues/:number/assignees", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const body = await c.req.json();

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (!body.username) {
    return c.json({ error: "Username is required" }, 400);
  }

  try {
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    // Add assignee if not already present
    const assignees = issue.assignees || [];
    if (!assignees.includes(body.username)) {
      assignees.push(body.username);
      await updateIssue(user, repo, number, { assignees });
    }

    return c.json({ assignees });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof GitOperationError) {
      return c.json({ error: error.message }, 500);
    }
    throw error;
  }
});

// Remove an assignee from an issue
app.delete("/:user/:repo/issues/:number/assignees/:username", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const username = c.req.param("username");

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    // Remove assignee
    const assignees = (issue.assignees || []).filter((a) => a !== username);
    await updateIssue(user, repo, number, { assignees });

    return c.json({ assignees });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof GitOperationError) {
      return c.json({ error: error.message }, 500);
    }
    throw error;
  }
});

// =============================================================================
// Reaction Routes
// =============================================================================

// Get reactions for an issue
app.get("/:user/:repo/issues/:number/reactions", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    // Verify issue exists
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    // Get reactions from database
    const reactions = await sql<Array<{ id: number; user_id: number; username: string; emoji: string; created_at: Date }>>`
      SELECT r.id, r.user_id, u.username, r.emoji, r.created_at
      FROM reactions r
      JOIN users u ON r.user_id = u.id
      WHERE r.target_type = 'issue' AND r.target_id = ${number}
      ORDER BY r.created_at ASC
    `;

    // Group by emoji
    const grouped = reactions.reduce((acc, r) => {
      if (!acc[r.emoji]) {
        acc[r.emoji] = {
          emoji: r.emoji,
          count: 0,
          users: [],
        };
      }
      acc[r.emoji].count++;
      acc[r.emoji].users.push({ id: r.user_id, username: r.username });
      return acc;
    }, {} as Record<string, { emoji: string; count: number; users: Array<{ id: number; username: string }> }>);

    return c.json({
      reactions: Object.values(grouped),
    });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Add a reaction to an issue
app.post("/:user/:repo/issues/:number/reactions", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const body = await c.req.json();

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (!body.user_id || !body.emoji) {
    return c.json({ error: "user_id and emoji are required" }, 400);
  }

  try {
    // Verify issue exists
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    // Insert reaction (or ignore if duplicate due to unique constraint)
    const [reaction] = await sql<Array<{ id: number; user_id: number; target_type: string; target_id: number; emoji: string; created_at: Date }>>`
      INSERT INTO reactions (user_id, target_type, target_id, emoji)
      VALUES (${body.user_id}, 'issue', ${number}, ${body.emoji})
      ON CONFLICT (user_id, target_type, target_id, emoji) DO NOTHING
      RETURNING id, user_id, target_type, target_id, emoji, created_at
    `;

    if (!reaction) {
      return c.json({ message: "Reaction already exists" }, 200);
    }

    return c.json(reaction, 201);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Remove a reaction from an issue
app.delete("/:user/:repo/issues/:number/reactions/:emoji", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const emoji = c.req.param("emoji");
  const userId = c.req.query("user_id");

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (!userId) {
    return c.json({ error: "user_id query parameter is required" }, 400);
  }

  try {
    // Verify issue exists
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    // Delete reaction
    await sql`
      DELETE FROM reactions
      WHERE user_id = ${userId}
        AND target_type = 'issue'
        AND target_id = ${number}
        AND emoji = ${emoji}
    `;

    return c.json({ success: true });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get reactions for a comment
app.get("/:user/:repo/issues/:number/comments/:commentId/reactions", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const commentId = parseInt(c.req.param("commentId"), 10);

  if (isNaN(number) || isNaN(commentId)) {
    return c.json({ error: "Invalid issue or comment number" }, 400);
  }

  try {
    // Verify issue exists
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    // Get reactions from database
    const reactions = await sql<Array<{ id: number; user_id: number; username: string; emoji: string; created_at: Date }>>`
      SELECT r.id, r.user_id, u.username, r.emoji, r.created_at
      FROM reactions r
      JOIN users u ON r.user_id = u.id
      WHERE r.target_type = 'comment' AND r.target_id = ${commentId}
      ORDER BY r.created_at ASC
    `;

    // Group by emoji
    const grouped = reactions.reduce((acc, r) => {
      if (!acc[r.emoji]) {
        acc[r.emoji] = {
          emoji: r.emoji,
          count: 0,
          users: [],
        };
      }
      acc[r.emoji].count++;
      acc[r.emoji].users.push({ id: r.user_id, username: r.username });
      return acc;
    }, {} as Record<string, { emoji: string; count: number; users: Array<{ id: number; username: string }> }>);

    return c.json({
      reactions: Object.values(grouped),
    });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Add a reaction to a comment
app.post("/:user/:repo/issues/:number/comments/:commentId/reactions", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const commentId = parseInt(c.req.param("commentId"), 10);
  const body = await c.req.json();

  if (isNaN(number) || isNaN(commentId)) {
    return c.json({ error: "Invalid issue or comment number" }, 400);
  }

  if (!body.user_id || !body.emoji) {
    return c.json({ error: "user_id and emoji are required" }, 400);
  }

  try {
    // Verify issue exists
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    // Insert reaction (or ignore if duplicate due to unique constraint)
    const [reaction] = await sql<Array<{ id: number; user_id: number; target_type: string; target_id: number; emoji: string; created_at: Date }>>`
      INSERT INTO reactions (user_id, target_type, target_id, emoji)
      VALUES (${body.user_id}, 'comment', ${commentId}, ${body.emoji})
      ON CONFLICT (user_id, target_type, target_id, emoji) DO NOTHING
      RETURNING id, user_id, target_type, target_id, emoji, created_at
    `;

    if (!reaction) {
      return c.json({ message: "Reaction already exists" }, 200);
    }

    return c.json(reaction, 201);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Remove a reaction from a comment
app.delete("/:user/:repo/issues/:number/comments/:commentId/reactions/:emoji", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const commentId = parseInt(c.req.param("commentId"), 10);
  const emoji = c.req.param("emoji");
  const userId = c.req.query("user_id");

  if (isNaN(number) || isNaN(commentId)) {
    return c.json({ error: "Invalid issue or comment number" }, 400);
  }

  if (!userId) {
    return c.json({ error: "user_id query parameter is required" }, 400);
  }

  try {
    // Verify issue exists
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    // Delete reaction
    await sql`
      DELETE FROM reactions
      WHERE user_id = ${userId}
        AND target_type = 'comment'
        AND target_id = ${commentId}
        AND emoji = ${emoji}
    `;

    return c.json({ success: true });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// =============================================================================
// Milestone Routes
// =============================================================================

// List milestones for a repository
app.get("/:user/:repo/milestones", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const state = (c.req.query("state") || "open") as "open" | "closed" | "all";

  try {
    // Get repository
    const [repoResult] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repoResult) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Build query based on state
    let milestones;
    if (state === "all") {
      milestones = await sql`
        SELECT m.*,
          (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open') as open_issues,
          (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed') as closed_issues
        FROM milestones m
        WHERE m.repository_id = ${repoResult.id}
        ORDER BY m.due_date ASC NULLS LAST, m.created_at DESC
      `;
    } else {
      milestones = await sql`
        SELECT m.*,
          (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open') as open_issues,
          (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed') as closed_issues
        FROM milestones m
        WHERE m.repository_id = ${repoResult.id} AND m.state = ${state}
        ORDER BY m.due_date ASC NULLS LAST, m.created_at DESC
      `;
    }

    return c.json({ milestones });
  } catch (error) {
    console.error("Error fetching milestones:", error);
    return c.json({ error: "Failed to fetch milestones" }, 500);
  }
});

// Create a milestone
app.post("/:user/:repo/milestones", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const body = await c.req.json();

  if (!body.title) {
    return c.json({ error: "Title is required" }, 400);
  }

  try {
    // Get repository
    const [repoResult] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repoResult) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const [milestone] = await sql`
      INSERT INTO milestones (repository_id, title, description, due_date)
      VALUES (${repoResult.id}, ${body.title}, ${body.description || null}, ${body.due_date || null})
      RETURNING *
    `;

    return c.json(milestone, 201);
  } catch (error) {
    console.error("Error creating milestone:", error);
    return c.json({ error: "Failed to create milestone" }, 500);
  }
});

// Get a single milestone
app.get("/:user/:repo/milestones/:id", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid milestone ID" }, 400);
  }

  try {
    // Get repository
    const [repoResult] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repoResult) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const [milestone] = await sql`
      SELECT m.*,
        (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open') as open_issues,
        (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed') as closed_issues
      FROM milestones m
      WHERE m.id = ${id} AND m.repository_id = ${repoResult.id}
    `;

    if (!milestone) {
      return c.json({ error: "Milestone not found" }, 404);
    }

    return c.json(milestone);
  } catch (error) {
    console.error("Error fetching milestone:", error);
    return c.json({ error: "Failed to fetch milestone" }, 500);
  }
});

// Update a milestone
app.patch("/:user/:repo/milestones/:id", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const id = parseInt(c.req.param("id"), 10);
  const body = await c.req.json();

  if (isNaN(id)) {
    return c.json({ error: "Invalid milestone ID" }, 400);
  }

  try {
    // Get repository
    const [repoResult] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repoResult) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Build update fields
    const updates: any = { updated_at: sql`NOW()` };

    if (body.title !== undefined) updates.title = body.title;
    if (body.description !== undefined) updates.description = body.description;
    if (body.due_date !== undefined) updates.due_date = body.due_date;
    if (body.state !== undefined) {
      updates.state = body.state;
      if (body.state === 'closed') {
        updates.closed_at = sql`NOW()`;
      } else if (body.state === 'open') {
        updates.closed_at = null;
      }
    }

    const [milestone] = await sql`
      UPDATE milestones
      SET ${sql(updates)}
      WHERE id = ${id} AND repository_id = ${repoResult.id}
      RETURNING *
    `;

    if (!milestone) {
      return c.json({ error: "Milestone not found" }, 404);
    }

    return c.json(milestone);
  } catch (error) {
    console.error("Error updating milestone:", error);
    return c.json({ error: "Failed to update milestone" }, 500);
  }
});

// Delete a milestone
app.delete("/:user/:repo/milestones/:id", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const id = parseInt(c.req.param("id"), 10);

  if (isNaN(id)) {
    return c.json({ error: "Invalid milestone ID" }, 400);
  }

  try {
    // Get repository
    const [repoResult] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repoResult) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const result = await sql`
      DELETE FROM milestones
      WHERE id = ${id} AND repository_id = ${repoResult.id}
      RETURNING id
    `;

    if (result.length === 0) {
      return c.json({ error: "Milestone not found" }, 404);
    }

    return c.json({ success: true });
  } catch (error) {
    console.error("Error deleting milestone:", error);
    return c.json({ error: "Failed to delete milestone" }, 500);
  }
});

// Set milestone for an issue
app.post("/:user/:repo/issues/:number/milestone", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const body = await c.req.json();

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (!body.milestone_id) {
    return c.json({ error: "Milestone ID is required" }, 400);
  }

  try {
    // Get repository
    const [repoResult] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repoResult) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Verify milestone exists and belongs to this repository
    const [milestone] = await sql`
      SELECT id FROM milestones
      WHERE id = ${body.milestone_id} AND repository_id = ${repoResult.id}
    `;

    if (!milestone) {
      return c.json({ error: "Milestone not found" }, 404);
    }

    const [issue] = await sql`
      UPDATE issues
      SET milestone_id = ${body.milestone_id}, updated_at = NOW()
      WHERE issue_number = ${number} AND repository_id = ${repoResult.id}
      RETURNING *
    `;

    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    return c.json(issue);
  } catch (error) {
    console.error("Error setting milestone:", error);
    return c.json({ error: "Failed to set milestone" }, 500);
  }
});

// Remove milestone from an issue
app.delete("/:user/:repo/issues/:number/milestone", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    // Get repository
    const [repoResult] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repoResult) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const [issue] = await sql`
      UPDATE issues
      SET milestone_id = NULL, updated_at = NOW()
      WHERE issue_number = ${number} AND repository_id = ${repoResult.id}
      RETURNING *
    `;

    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    return c.json(issue);
  } catch (error) {
    console.error("Error removing milestone:", error);
    return c.json({ error: "Failed to remove milestone" }, 500);
  }
});

// =============================================================================
// Dependency Routes
// =============================================================================

// Get dependencies for an issue
app.get("/:user/:repo/issues/:number/dependencies", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const issue = await getIssue(user, repo, number);
    if (!issue) {
      return c.json({ error: "Issue not found" }, 404);
    }

    const blocking = await getBlockingIssues(user, repo, number);
    const blockedBy = await getBlockedByIssues(user, repo, number);

    return c.json({
      blocks: blocking,
      blocked_by: blockedBy,
    });
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Add a dependency (this issue blocks another)
app.post("/:user/:repo/issues/:number/dependencies", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const body = await c.req.json();

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (!body.blocks) {
    return c.json({ error: "blocks issue number is required" }, 400);
  }

  const blockedIssue = parseInt(body.blocks, 10);
  if (isNaN(blockedIssue)) {
    return c.json({ error: "Invalid blocked issue number" }, 400);
  }

  try {
    const result = await addDependency(user, repo, number, blockedIssue);
    return c.json(result, 201);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof Error) {
      return c.json({ error: error.message }, 400);
    }
    throw error;
  }
});

// Remove a dependency (this issue no longer blocks another)
app.delete("/:user/:repo/issues/:number/dependencies/:blockedNumber", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const blockedNumber = parseInt(c.req.param("blockedNumber"), 10);

  if (isNaN(number) || isNaN(blockedNumber)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const result = await removeDependency(user, repo, number, blockedNumber);
    return c.json(result);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Check if an issue can be closed
app.get("/:user/:repo/issues/:number/can-close", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const result = await canCloseIssue(user, repo, number);
    return c.json(result);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// =============================================================================
// Due Date Routes
// =============================================================================

// Set due date for an issue
app.post("/:user/:repo/issues/:number/due-date", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);
  const body = await c.req.json();

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  if (!body.due_date) {
    return c.json({ error: "Due date is required" }, 400);
  }

  try {
    const issue = await updateIssue(user, repo, number, {
      due_date: body.due_date,
    });

    return c.json(issue);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof GitOperationError) {
      return c.json({ error: error.message }, 500);
    }
    throw error;
  }
});

// Remove due date from an issue
app.delete("/:user/:repo/issues/:number/due-date", requireAuth, async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const number = parseInt(c.req.param("number"), 10);

  if (isNaN(number)) {
    return c.json({ error: "Invalid issue number" }, 400);
  }

  try {
    const issue = await updateIssue(user, repo, number, {
      due_date: null,
    });

    return c.json(issue);
  } catch (error) {
    if (error instanceof IssueNotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof GitOperationError) {
      return c.json({ error: error.message }, 500);
    }
    throw error;
  }
});

export default app;
