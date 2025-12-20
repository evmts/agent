/**
 * Repository starring and watching routes.
 */

import { Hono } from "hono";
import { sql } from "../../ui/lib/db";
import { getUserBySession } from "../../ui/lib/auth-helpers";
import type { Repository, User } from "../../ui/lib/types";

const app = new Hono();

// =============================================================================
// Star Routes
// =============================================================================

// Get stargazers for a repository
app.get("/:user/:repo/stargazers", async (c) => {
  const username = c.req.param("user");
  const reponame = c.req.param("repo");

  try {
    const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repo] = await sql<Repository[]>`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    `;
    if (!repo) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const stargazers = await sql`
      SELECT u.id, u.username, u.display_name, u.avatar_url, s.created_at
      FROM stars s
      JOIN users u ON s.user_id = u.id
      WHERE s.repository_id = ${repo.id}
      ORDER BY s.created_at DESC
    `;

    return c.json({ stargazers, total: stargazers.length });
  } catch (error) {
    console.error("Error fetching stargazers:", error);
    return c.json({ error: "Failed to fetch stargazers" }, 500);
  }
});

// Star a repository
app.post("/:user/:repo/star", async (c) => {
  const username = c.req.param("user");
  const reponame = c.req.param("repo");

  const currentUser = await getUserBySession(c.req.raw);
  if (!currentUser) {
    return c.json({ error: "Unauthorized" }, 401);
  }

  try {
    const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repo] = await sql<Repository[]>`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    `;
    if (!repo) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Check if already starred
    const [existing] = await sql`
      SELECT * FROM stars
      WHERE user_id = ${currentUser.id} AND repository_id = ${repo.id}
    `;

    if (existing) {
      return c.json({ message: "Already starred" }, 200);
    }

    // Create star
    await sql`
      INSERT INTO stars (user_id, repository_id)
      VALUES (${currentUser.id}, ${repo.id})
    `;

    // Get updated count
    const [{ count }] = await sql`
      SELECT COUNT(*) as count FROM stars WHERE repository_id = ${repo.id}
    `;

    return c.json({ message: "Repository starred", starCount: Number(count) }, 201);
  } catch (error) {
    console.error("Error starring repository:", error);
    return c.json({ error: "Failed to star repository" }, 500);
  }
});

// Unstar a repository
app.delete("/:user/:repo/star", async (c) => {
  const username = c.req.param("user");
  const reponame = c.req.param("repo");

  const currentUser = await getUserBySession(c.req.raw);
  if (!currentUser) {
    return c.json({ error: "Unauthorized" }, 401);
  }

  try {
    const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repo] = await sql<Repository[]>`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    `;
    if (!repo) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Delete star
    await sql`
      DELETE FROM stars
      WHERE user_id = ${currentUser.id} AND repository_id = ${repo.id}
    `;

    // Get updated count
    const [{ count }] = await sql`
      SELECT COUNT(*) as count FROM stars WHERE repository_id = ${repo.id}
    `;

    return c.json({ message: "Repository unstarred", starCount: Number(count) });
  } catch (error) {
    console.error("Error unstarring repository:", error);
    return c.json({ error: "Failed to unstar repository" }, 500);
  }
});

// Get current user's starred repositories
app.get("/user/starred", async (c) => {
  const currentUser = await getUserBySession(c.req.raw);
  if (!currentUser) {
    return c.json({ error: "Unauthorized" }, 401);
  }

  try {
    const repos = await sql`
      SELECT r.*, u.username, s.created_at as starred_at,
        (SELECT COUNT(*) FROM stars WHERE repository_id = r.id) as star_count
      FROM stars s
      JOIN repositories r ON s.repository_id = r.id
      JOIN users u ON r.user_id = u.id
      WHERE s.user_id = ${currentUser.id}
      ORDER BY s.created_at DESC
    `;

    return c.json({ repositories: repos, total: repos.length });
  } catch (error) {
    console.error("Error fetching starred repositories:", error);
    return c.json({ error: "Failed to fetch starred repositories" }, 500);
  }
});

// =============================================================================
// Watch Routes
// =============================================================================

// Get watchers for a repository
app.get("/:user/:repo/watchers", async (c) => {
  const username = c.req.param("user");
  const reponame = c.req.param("repo");

  try {
    const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repo] = await sql<Repository[]>`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    `;
    if (!repo) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const watchers = await sql`
      SELECT u.id, u.username, u.display_name, u.avatar_url, w.level, w.created_at
      FROM watches w
      JOIN users u ON w.user_id = u.id
      WHERE w.repository_id = ${repo.id} AND w.level != 'ignore'
      ORDER BY w.created_at DESC
    `;

    return c.json({ watchers, total: watchers.length });
  } catch (error) {
    console.error("Error fetching watchers:", error);
    return c.json({ error: "Failed to fetch watchers" }, 500);
  }
});

// Watch a repository
app.post("/:user/:repo/watch", async (c) => {
  const username = c.req.param("user");
  const reponame = c.req.param("repo");

  const currentUser = await getUserBySession(c.req.raw);
  if (!currentUser) {
    return c.json({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await c.req.json();
    const level = body.level || "all";

    if (!["all", "releases", "ignore"].includes(level)) {
      return c.json({ error: "Invalid watch level" }, 400);
    }

    const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repo] = await sql<Repository[]>`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    `;
    if (!repo) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Insert or update watch
    await sql`
      INSERT INTO watches (user_id, repository_id, level)
      VALUES (${currentUser.id}, ${repo.id}, ${level})
      ON CONFLICT (user_id, repository_id)
      DO UPDATE SET level = ${level}, updated_at = NOW()
    `;

    return c.json({ message: "Watch preferences updated", level });
  } catch (error) {
    console.error("Error watching repository:", error);
    return c.json({ error: "Failed to watch repository" }, 500);
  }
});

// Unwatch a repository
app.delete("/:user/:repo/watch", async (c) => {
  const username = c.req.param("user");
  const reponame = c.req.param("repo");

  const currentUser = await getUserBySession(c.req.raw);
  if (!currentUser) {
    return c.json({ error: "Unauthorized" }, 401);
  }

  try {
    const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repo] = await sql<Repository[]>`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    `;
    if (!repo) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Delete watch
    await sql`
      DELETE FROM watches
      WHERE user_id = ${currentUser.id} AND repository_id = ${repo.id}
    `;

    return c.json({ message: "Repository unwatched" });
  } catch (error) {
    console.error("Error unwatching repository:", error);
    return c.json({ error: "Failed to unwatch repository" }, 500);
  }
});

// Get current user's watch status for a repository
app.get("/:user/:repo/watch/status", async (c) => {
  const username = c.req.param("user");
  const reponame = c.req.param("repo");

  const currentUser = await getUserBySession(c.req.raw);
  if (!currentUser) {
    return c.json({ watching: false, level: null });
  }

  try {
    const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repo] = await sql<Repository[]>`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    `;
    if (!repo) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const [watch] = await sql`
      SELECT level FROM watches
      WHERE user_id = ${currentUser.id} AND repository_id = ${repo.id}
    `;

    return c.json({
      watching: !!watch,
      level: watch?.level || null,
    });
  } catch (error) {
    console.error("Error fetching watch status:", error);
    return c.json({ watching: false, level: null });
  }
});

// Get current user's star status for a repository
app.get("/:user/:repo/star/status", async (c) => {
  const username = c.req.param("user");
  const reponame = c.req.param("repo");

  const currentUser = await getUserBySession(c.req.raw);
  if (!currentUser) {
    return c.json({ starred: false });
  }

  try {
    const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repo] = await sql<Repository[]>`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    `;
    if (!repo) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const [star] = await sql`
      SELECT * FROM stars
      WHERE user_id = ${currentUser.id} AND repository_id = ${repo.id}
    `;

    // Also get star count
    const [{ count }] = await sql`
      SELECT COUNT(*) as count FROM stars WHERE repository_id = ${repo.id}
    `;

    return c.json({
      starred: !!star,
      starCount: Number(count),
    });
  } catch (error) {
    console.error("Error fetching star status:", error);
    return c.json({ starred: false, starCount: 0 });
  }
});

export default app;
