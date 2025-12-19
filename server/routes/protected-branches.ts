import { Hono } from "hono";
import { sql } from "../../ui/lib/db";
import type { ProtectedBranch } from "../../ui/lib/types";

const app = new Hono();

// List protection rules
app.get("/:user/:repo/branch-protections", async (c) => {
  const { user, repo } = c.req.param();

  try {
    const [repository] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    const rules = await sql<ProtectedBranch[]>`
      SELECT * FROM protected_branches
      WHERE repository_id = ${repository.id}
      ORDER BY priority DESC
    `;

    return c.json({ rules });
  } catch (error: any) {
    console.error('Error listing protection rules:', error);
    return c.json({ error: "Failed to list protection rules" }, 500);
  }
});

// Create protection rule
app.post("/:user/:repo/branch-protections", async (c) => {
  const { user, repo } = c.req.param();
  
  try {
    const data = await c.req.json();

    if (!data.rule_name) {
      return c.json({ error: "Missing rule_name" }, 400);
    }

    const [repository] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Check if rule already exists
    const [existing] = await sql`
      SELECT id FROM protected_branches
      WHERE repository_id = ${repository.id} AND rule_name = ${data.rule_name}
    `;

    if (existing) {
      return c.json({ error: "Protection rule already exists" }, 409);
    }

    // Get max priority and increment
    const [{ max_priority }] = await sql`
      SELECT COALESCE(MAX(priority), 0) as max_priority
      FROM protected_branches
      WHERE repository_id = ${repository.id}
    `;

    const priority = data.priority || Number(max_priority) + 1;

    const [rule] = await sql`
      INSERT INTO protected_branches (
        repository_id, rule_name, priority,
        can_push, enable_whitelist, whitelist_user_ids,
        can_force_push, enable_force_push_allowlist,
        enable_merge_whitelist, required_approvals,
        enable_status_check, status_check_contexts
      )
      VALUES (
        ${repository.id}, ${data.rule_name}, ${priority},
        ${data.can_push || false}, ${data.enable_whitelist || false},
        ${JSON.stringify(data.whitelist_user_ids || [])},
        ${data.can_force_push || false}, ${data.enable_force_push_allowlist || false},
        ${data.enable_merge_whitelist || false}, ${data.required_approvals || 0},
        ${data.enable_status_check || false},
        ${JSON.stringify(data.status_check_contexts || [])}
      )
      RETURNING *
    `;

    return c.json({ rule }, 201);
  } catch (error: any) {
    console.error('Error creating protection rule:', error);
    return c.json({ error: "Failed to create protection rule" }, 500);
  }
});

// Update protection rule
app.patch("/:user/:repo/branch-protections/:ruleId", async (c) => {
  const { user, repo, ruleId } = c.req.param();
  
  try {
    const data = await c.req.json();

    const [repository] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    // Build update object
    const updates: any = { updated_at: sql`NOW()` };
    
    if (data.can_push !== undefined) updates.can_push = data.can_push;
    if (data.enable_whitelist !== undefined) updates.enable_whitelist = data.enable_whitelist;
    if (data.whitelist_user_ids !== undefined) updates.whitelist_user_ids = JSON.stringify(data.whitelist_user_ids);
    if (data.can_force_push !== undefined) updates.can_force_push = data.can_force_push;
    if (data.required_approvals !== undefined) updates.required_approvals = data.required_approvals;
    if (data.enable_status_check !== undefined) updates.enable_status_check = data.enable_status_check;
    if (data.status_check_contexts !== undefined) updates.status_check_contexts = JSON.stringify(data.status_check_contexts);

    if (Object.keys(updates).length === 1) { // Only updated_at
      return c.json({ error: "No fields to update" }, 400);
    }

    await sql`
      UPDATE protected_branches
      SET ${sql(updates)}
      WHERE id = ${ruleId} AND repository_id = ${repository.id}
    `;

    const [rule] = await sql`
      SELECT * FROM protected_branches WHERE id = ${ruleId}
    `;

    return c.json({ rule });
  } catch (error: any) {
    console.error('Error updating protection rule:', error);
    return c.json({ error: "Failed to update protection rule" }, 500);
  }
});

// Delete protection rule
app.delete("/:user/:repo/branch-protections/:ruleId", async (c) => {
  const { user, repo, ruleId } = c.req.param();

  try {
    const [repository] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return c.json({ error: "Repository not found" }, 404);
    }

    await sql`
      DELETE FROM protected_branches
      WHERE id = ${ruleId} AND repository_id = ${repository.id}
    `;

    return c.json({ success: true });
  } catch (error: any) {
    console.error('Error deleting protection rule:', error);
    return c.json({ error: "Failed to delete protection rule" }, 500);
  }
});

export default app;