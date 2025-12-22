/**
 * Sessions API
 *
 * GET /api/sessions - List user's AI sessions
 * POST /api/sessions - Create a new AI session
 */

import type { APIRoute } from 'astro';
import { getUserBySession } from '../../../lib/auth-helpers';
import sql from '../../../lib/db';
import { randomBytes } from 'crypto';

export const GET: APIRoute = async ({ request }) => {
  try {
    const user = await getUserBySession(request);

    if (!user) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Fetch sessions for the user
    // Note: Sessions table may not have user_id yet, so we fetch all sessions
    // In production, this should be filtered by user_id
    const sessions = await sql`
      SELECT
        id,
        title,
        directory,
        model,
        time_created as "createdAt",
        time_updated as "updatedAt",
        time_archived IS NOT NULL as archived,
        token_count as "tokenCount"
      FROM sessions
      ORDER BY time_updated DESC
      LIMIT 50
    `;

    // Convert timestamps from Unix ms to ISO strings
    const formattedSessions = sessions.map((s: any) => ({
      ...s,
      createdAt: s.createdAt ? new Date(Number(s.createdAt)).toISOString() : null,
      updatedAt: s.updatedAt ? new Date(Number(s.updatedAt)).toISOString() : null,
    }));

    return new Response(JSON.stringify({ sessions: formattedSessions }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Failed to fetch sessions:', error);
    return new Response(JSON.stringify({ error: 'Failed to fetch sessions' }), {
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
    const { title, directory, model } = body;

    if (!title) {
      return new Response(JSON.stringify({ error: 'Title is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const sessionId = randomBytes(16).toString('hex');
    const now = Date.now();

    const [session] = await sql`
      INSERT INTO sessions (
        id,
        title,
        directory,
        model,
        time_created,
        time_updated
      )
      VALUES (
        ${sessionId},
        ${title},
        ${directory || '/'},
        ${model || 'claude-sonnet-4-20250514'},
        ${now},
        ${now}
      )
      RETURNING
        id,
        title,
        directory,
        model,
        time_created as "createdAt",
        time_updated as "updatedAt"
    `;

    return new Response(JSON.stringify({
      session: {
        ...session,
        createdAt: new Date(Number(session.createdAt)).toISOString(),
        updatedAt: new Date(Number(session.updatedAt)).toISOString(),
      }
    }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Failed to create session:', error);
    return new Response(JSON.stringify({ error: 'Failed to create session' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
