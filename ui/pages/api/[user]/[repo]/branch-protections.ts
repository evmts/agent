import type { APIRoute } from 'astro';
import { sql } from '../../../../lib/db';
import type { ProtectedBranch } from '../../../../lib/types';

export const GET: APIRoute = async ({ params }) => {
  const { user, repo } = params;

  if (!user || !repo) {
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

    const rules = await sql<ProtectedBranch[]>`
      SELECT * FROM protected_branches
      WHERE repository_id = ${repository.id}
      ORDER BY priority DESC
    `;

    return new Response(JSON.stringify({ rules }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error: any) {
    console.error('Error listing protection rules:', error);
    return new Response(JSON.stringify({ error: 'Failed to list protection rules' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

export const POST: APIRoute = async ({ params, request }) => {
  const { user, repo } = params;

  if (!user || !repo) {
    return new Response(JSON.stringify({ error: 'Missing parameters' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const data = await request.json();

    if (!data.rule_name) {
      return new Response(JSON.stringify({ error: 'Missing rule_name' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

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

    // Check if rule already exists
    const [existing] = await sql`
      SELECT id FROM protected_branches
      WHERE repository_id = ${repository.id} AND rule_name = ${data.rule_name}
    `;

    if (existing) {
      return new Response(JSON.stringify({ error: 'Protection rule already exists' }), {
        status: 409,
        headers: { 'Content-Type': 'application/json' }
      });
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

    return new Response(JSON.stringify({ rule }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error: any) {
    console.error('Error creating protection rule:', error);
    return new Response(JSON.stringify({ error: 'Failed to create protection rule' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};