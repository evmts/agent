import type { APIRoute } from 'astro';
import { activateUser } from '@plue/db';

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json();
    const { token } = body;

    if (!token) {
      return new Response(JSON.stringify({ error: 'Activation token is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Activate user
    const user = await activateUser(token);

    if (!user) {
      return new Response(JSON.stringify({ error: 'Invalid or expired activation token' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({ 
      success: true,
      message: 'Account activated successfully',
      user: {
        id: Number(user.id),
        username: user.username,
        email: user.email,
        displayName: user.display_name
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Activation error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};