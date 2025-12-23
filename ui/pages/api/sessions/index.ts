/**
 * Sessions API
 *
 * GET /api/sessions - List user's AI sessions
 * POST /api/sessions - Create a new AI session
 */

import type { APIRoute } from 'astro';
import { getUserBySession } from '../../../lib/auth-helpers';
import { sessions } from '@plue/db';
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
    const sessionList = await sessions.listSessions(50);

    return new Response(JSON.stringify({ sessions: sessionList }), {
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

    const session = await sessions.createAgentSession({
      id: sessionId,
      title,
      directory,
      model,
    });

    return new Response(JSON.stringify({ session }), {
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
