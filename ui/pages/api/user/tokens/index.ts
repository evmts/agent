import type { APIRoute } from 'astro';
import { getUserBySession } from '../../../../lib/auth-helpers';
import { sql } from '../../../../lib/db';
import crypto from 'crypto';

export const GET: APIRoute = async ({ request }) => {
  try {
    const user = await getUserBySession(request);

    if (!user) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Fetch user's tokens (don't return full token)
    const tokens = await sql`
      SELECT
        id,
        name,
        token_last_eight,
        scopes,
        created_at,
        last_used_at
      FROM access_tokens
      WHERE user_id = ${user.id}
      ORDER BY created_at DESC
    `;

    return new Response(JSON.stringify({ tokens }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Failed to fetch tokens:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

export const POST: APIRoute = async ({ request }) => {
  try {
    const user = await getUserBySession(request);

    if (!user) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const body = await request.json();
    const { name, scopes } = body;

    if (!name || typeof name !== 'string' || name.trim().length === 0) {
      return new Response(JSON.stringify({ error: 'Token name is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (!scopes || !Array.isArray(scopes) || scopes.length === 0) {
      return new Response(JSON.stringify({ error: 'At least one scope is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate scopes
    const validScopes = ['repo', 'user', 'admin'];
    const invalidScopes = scopes.filter(s => !validScopes.includes(s));
    if (invalidScopes.length > 0) {
      return new Response(JSON.stringify({
        error: `Invalid scopes: ${invalidScopes.join(', ')}. Valid scopes are: ${validScopes.join(', ')}`
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Generate random token (32 bytes = 64 hex characters)
    const token = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const tokenLastEight = token.slice(-8);

    // Insert into database
    const result = await sql`
      INSERT INTO access_tokens (
        user_id,
        name,
        token_hash,
        token_last_eight,
        scopes
      )
      VALUES (
        ${user.id},
        ${name.trim()},
        ${tokenHash},
        ${tokenLastEight},
        ${scopes.join(',')}
      )
      RETURNING id, name, token_last_eight, scopes, created_at
    `;

    // Return the full token ONCE (this is the only time it will be shown)
    return new Response(JSON.stringify({
      token: result[0],
      fullToken: token,
      message: 'Token created successfully. Save it now - you won\'t be able to see it again!'
    }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Failed to create token:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
