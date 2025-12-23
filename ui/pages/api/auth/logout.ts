import type { APIRoute } from 'astro';
import { deleteSession } from '../../../../db';
import { getSessionIdFromRequest, clearSessionCookie } from '../../../lib/auth-helpers';

export const POST: APIRoute = async ({ request }) => {
  try {
    const sessionId = getSessionIdFromRequest(request);
    
    if (sessionId) {
      await deleteSession(sessionId);
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { 
        'Content-Type': 'application/json',
        'Set-Cookie': clearSessionCookie()
      }
    });
  } catch (error) {
    console.error('Logout error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};