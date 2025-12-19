import type { APIRoute } from 'astro';
import { getUserByEmail, createPasswordResetToken } from '../../../../../db/auth';
import { randomBytes } from 'crypto';

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json();
    const { email } = body;

    if (!email) {
      return new Response(JSON.stringify({ error: 'Email is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Check if user exists
    const user = await getUserByEmail(email);

    // Always return success for security reasons (don't reveal if email exists)
    if (user) {
      // Generate reset token
      const resetToken = randomBytes(32).toString('hex');
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

      // Store reset token
      await createPasswordResetToken(Number(user.id), resetToken, expiresAt);

      // In a real app, you would send an email here
      console.log(`Password reset token for ${user.username}: ${resetToken}`);
    }

    return new Response(JSON.stringify({ 
      success: true,
      message: 'If an account with that email exists, a password reset link has been sent.'
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Password reset request error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};