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
  getIssueHistory,
  getIssueCounts,
  getLabels,
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

export default app;
