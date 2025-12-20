/**
 * Repository routes - REST API for repository metadata.
 */

import { Hono } from "hono";
import { sql } from "../../ui/lib/db";

const app = new Hono();

// Get repository topics
app.get("/:user/:repo/topics", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");

  try {
    const [userRecord] = await sql`
      SELECT id FROM users WHERE username = ${user}
    `;

    if (!userRecord) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repository] = await sql`
      SELECT topics FROM repositories
      WHERE user_id = ${userRecord.id} AND name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    return c.json({
      topics: repository.topics || [],
    });
  } catch (error) {
    console.error("Error fetching topics:", error);
    return c.json({ error: "Internal server error" }, 500);
  }
});

// Update repository topics
app.put("/:user/:repo/topics", async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const body = await c.req.json();

  if (!Array.isArray(body.topics)) {
    return c.json({ error: "Topics must be an array" }, 400);
  }

  // Validate topics: max 20 topics, each max 35 chars, alphanumeric + hyphens
  const topics = body.topics.slice(0, 20).map((t: string) =>
    t.toLowerCase().trim().slice(0, 35)
  );

  const invalidTopic = topics.find((t: string) => !/^[a-z0-9-]+$/.test(t));
  if (invalidTopic) {
    return c.json(
      {
        error: `Invalid topic "${invalidTopic}". Topics must contain only lowercase letters, numbers, and hyphens.`,
      },
      400
    );
  }

  try {
    const [userRecord] = await sql`
      SELECT id FROM users WHERE username = ${user}
    `;

    if (!userRecord) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repository] = await sql`
      UPDATE repositories
      SET topics = ${topics}, updated_at = NOW()
      WHERE user_id = ${userRecord.id} AND name = ${repo}
      RETURNING topics
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    return c.json({
      topics: repository.topics,
    });
  } catch (error) {
    console.error("Error updating topics:", error);
    return c.json({ error: "Internal server error" }, 500);
  }
});

export default app;
