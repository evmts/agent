import type { APIRoute } from 'astro';
import { sql } from '../../../../lib/db';
import * as git from '../../../../lib/git';
import type { Branch, ProtectedBranch } from '../../../../lib/types';

export const GET: APIRoute = async ({ params, url }) => {
  const { user, repo } = params;
  
  if (!user || !repo) {
    return new Response(JSON.stringify({ error: 'Missing parameters' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  const searchParams = new URLSearchParams(url.search);
  const page = parseInt(searchParams.get("page") || "1");
  const limit = parseInt(searchParams.get("limit") || "20");
  const offset = (page - 1) * limit;

  try {
    // Get repository
    const [repository] = await sql<Array<{
      id: number;
      name: string;
      user_id: number;
      username: string;
      default_branch: string;
    }>>`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return new Response(JSON.stringify({ error: 'Repository not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get branches from database
    const branches = await sql<Branch[]>`
      SELECT b.*, u.username as pusher_username
      FROM branches b
      LEFT JOIN users u ON b.pusher_id = u.id
      WHERE b.repository_id = ${repository.id}
        AND b.is_deleted = false
      ORDER BY
        CASE WHEN b.name = ${repository.default_branch} THEN 0 ELSE 1 END,
        b.updated_at DESC
      LIMIT ${limit} OFFSET ${offset}
    `;

    const [{ count }] = await sql<[{ count: number }]>`
      SELECT COUNT(*) as count FROM branches
      WHERE repository_id = ${repository.id} AND is_deleted = false
    `;

    return new Response(JSON.stringify({
      branches,
      total: Number(count),
      page,
      limit,
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error: any) {
    console.error('Error listing branches:', error);
    return new Response(JSON.stringify({ error: 'Failed to list branches' }), { 
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
    const { name, from_ref } = await request.json();

    if (!name || !from_ref) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), { 
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get repository
    const [repository] = await sql<Array<{
      id: number;
      name: string;
      user_id: number;
      username: string;
      default_branch: string;
    }>>`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
    `;

    if (!repository) {
      return new Response(JSON.stringify({ error: 'Repository not found' }), { 
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Check if branch exists
    const [existing] = await sql<Array<{ id: number }>>`
      SELECT id FROM branches
      WHERE repository_id = ${repository.id}
        AND name = ${name}
        AND is_deleted = false
    `;

    if (existing) {
      return new Response(JSON.stringify({ error: 'Branch already exists' }), { 
        status: 409,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Create branch in git
    await git.createBranch(user, repo, name, from_ref);

    // Get commit info
    const commitInfo = await git.getBranchCommit(user, repo, name);

    // Create branch record
    const [branch] = await sql<Branch[]>`
      INSERT INTO branches (
        repository_id, name, commit_id, commit_message,
        commit_time, pusher_id
      )
      VALUES (
        ${repository.id}, ${name}, ${commitInfo.hash},
        ${commitInfo.message}, ${new Date(commitInfo.timestamp)},
        ${repository.user_id}
      )
      RETURNING *
    `;

    return new Response(JSON.stringify({ branch }), { 
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error: any) {
    console.error('Error creating branch:', error);
    return new Response(JSON.stringify({ error: error.message || 'Failed to create branch' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};