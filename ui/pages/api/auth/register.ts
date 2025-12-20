import type { APIRoute } from 'astro';
import { createUser } from '../../../lib/auth-db';
import { hash } from '@node-rs/argon2';
import { randomBytes } from 'crypto';

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json();
    const { username, email, password, displayName } = body;

    if (!username || !email || !password) {
      return new Response(JSON.stringify({ error: 'Username, email, and password are required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Hash password
    const passwordHash = await hash(password);

    // Generate activation token
    const activationToken = randomBytes(32).toString('hex');

    // Create user
    try {
      const user = await createUser({
        username,
        email,
        passwordHash,
        displayName,
        activationToken
      });

      // In a real app, you would send an activation email here
      // For now, just return success

      return new Response(JSON.stringify({ 
        success: true,
        user: {
          id: Number(user.id),
          username: user.username,
          email: user.email,
          displayName: user.display_name
        },
        message: 'Registration successful. Please check your email for activation link.'
      }), {
        status: 201,
        headers: { 'Content-Type': 'application/json' }
      });
    } catch (dbError: any) {
      if (dbError.code === '23505') { // Unique constraint violation
        return new Response(JSON.stringify({ error: 'User with this username or email already exists' }), {
          status: 409,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      throw dbError;
    }
  } catch (error) {
    console.error('Registration error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};