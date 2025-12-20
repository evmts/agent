/**
 * Issue routes - REST API for git-based issue tracking.
 *
 * Issues are stored in a nested git repository at .plue/issues/
 * within each project repository.
 */

import { Hono } from "hono";
import {
  listIssues,
  getIssue,
  createIssue,
  updateIssue,
  closeIssue,
  reopenIssue,
  deleteIssue,
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
app.post("/:user/:repo/issues", async (c) => {
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
app.patch("/:user/:repo/issues/:number", async (c) => {
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
app.post("/:user/:repo/issues/:number/close", async (c) => {
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
app.post("/:user/:repo/issues/:number/reopen", async (c) => {
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
app.delete("/:user/:repo/issues/:number", async (c) => {
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
app.post("/:user/:repo/issues/:number/comments", async (c) => {
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
app.post("/:user/:repo/labels", async (c) => {
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
app.patch("/:user/:repo/labels/:name", async (c) => {
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
app.delete("/:user/:repo/labels/:name", async (c) => {
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
app.post("/:user/:repo/issues/:number/labels", async (c) => {
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
app.delete("/:user/:repo/issues/:number/labels/:label", async (c) => {
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
app.post("/:user/:repo/issues/:number/assignees", async (c) => {
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
app.delete("/:user/:repo/issues/:number/assignees/:username", async (c) => {
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

export default app;
