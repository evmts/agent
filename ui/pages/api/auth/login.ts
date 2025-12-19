import type { APIRoute } from 'astro';
import { getUserByUsernameOrEmail, createSession } from '../../../../db/auth';
import { createSessionCookie } from '../../../lib/auth-helpers';
import { verify } from '@node-rs/argon2';
import { randomBytes } from 'crypto';

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json();
    const { usernameOrEmail, password } = body;

    if (!usernameOrEmail || !password) {
      return new Response(JSON.stringify({ error: 'Username/email and password are required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Find user by username or email
    const user = await getUserByUsernameOrEmail(usernameOrEmail);

    if (!user) {
      return new Response(JSON.stringify({ error: 'Invalid credentials' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Verify password
    const isValid = await verify(user.password_hash as string, password);
    if (!isValid) {
      return new Response(JSON.stringify({ error: 'Invalid credentials' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Create session
    const sessionId = randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

    await createSession(Number(user.id), sessionId, expiresAt);

    return new Response(JSON.stringify({ 
      success: true,
      user: {
        id: Number(user.id),
        username: user.username,
        email: user.email,
        displayName: user.display_name,
        isAdmin: user.is_admin,
        isActive: user.is_active
      }
    }), {
      status: 200,
      headers: { 
        'Content-Type': 'application/json',
        'Set-Cookie': createSessionCookie(sessionId)
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};