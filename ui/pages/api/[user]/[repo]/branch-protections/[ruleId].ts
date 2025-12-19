import type { APIRoute } from 'astro';
import { sql } from '../../../../../lib/db';

export const PATCH: APIRoute = async ({ params, request }) => {
  const { user, repo, ruleId } = params;

  if (!user || !repo || !ruleId) {
    return new Response(JSON.stringify({ error: 'Missing parameters' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const data = await request.json();

    const [repository] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return new Response(JSON.stringify({ error: 'Repository not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
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
      return new Response(JSON.stringify({ error: 'No fields to update' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    await sql`
      UPDATE protected_branches
      SET ${sql(updates)}
      WHERE id = ${ruleId} AND repository_id = ${repository.id}
    `;

    const [rule] = await sql`
      SELECT * FROM protected_branches WHERE id = ${ruleId}
    `;

    return new Response(JSON.stringify({ rule }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error: any) {
    console.error('Error updating protection rule:', error);
    return new Response(JSON.stringify({ error: 'Failed to update protection rule' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

export const DELETE: APIRoute = async ({ params }) => {
  const { user, repo, ruleId } = params;

  if (!user || !repo || !ruleId) {
    return new Response(JSON.stringify({ error: 'Missing parameters' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const [repository] = await sql`
      SELECT r.id FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return new Response(JSON.stringify({ error: 'Repository not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    await sql`
      DELETE FROM protected_branches
      WHERE id = ${ruleId} AND repository_id = ${repository.id}
    `;

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error: any) {
    console.error('Error deleting protection rule:', error);
    return new Response(JSON.stringify({ error: 'Failed to delete protection rule' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};