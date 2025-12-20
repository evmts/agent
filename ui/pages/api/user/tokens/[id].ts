import type { APIRoute } from 'astro';
import { getUserBySession } from '../../../../lib/auth-helpers';
import { sql } from '../../../../lib/db';

export const DELETE: APIRoute = async ({ request, params }) => {
  try {
    const user = await getUserBySession(request);

    if (!user) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const tokenId = params.id;

    if (!tokenId || isNaN(Number(tokenId))) {
      return new Response(JSON.stringify({ error: 'Invalid token ID' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Delete the token (only if it belongs to the user)
    const result = await sql`
      DELETE FROM access_tokens
      WHERE id = ${tokenId} AND user_id = ${user.id}
      RETURNING id
    `;

    if (result.length === 0) {
      return new Response(JSON.stringify({ error: 'Token not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({ message: 'Token revoked successfully' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Failed to delete token:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
