/**
 * Repository routes - REST API for repository metadata.
 */

import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import { sql } from "../../ui/lib/db";
import { updateTopicsSchema } from "../lib/validation";

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
app.put("/:user/:repo/topics", zValidator("json", updateTopicsSchema), async (c) => {
  const user = c.req.param("user");
  const repo = c.req.param("repo");
  const { topics } = c.req.valid("json");

  // Normalize topics to lowercase
  const normalizedTopics = topics.map((t: string) => t.toLowerCase().trim());

  try {
    const [userRecord] = await sql`
      SELECT id FROM users WHERE username = ${user}
    `;

    if (!userRecord) {
      return c.json({ error: "User not found" }, 404);
    }

    const [repository] = await sql`
      UPDATE repositories
      SET topics = ${normalizedTopics}, updated_at = NOW()
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
