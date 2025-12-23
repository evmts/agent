import type { APIRoute } from 'astro';
import { getUserByEmail, createPasswordResetToken } from '../../../../../db';
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
    const isDevelopment = import.meta.env.DEV || process.env.NODE_ENV === 'development';
    let devInfo: { resetToken?: string; resetUrl?: string } = {};

    if (user) {
      // Generate reset token
      const resetToken = randomBytes(32).toString('hex');
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

      // Store reset token
      await createPasswordResetToken(Number(user.id), resetToken, expiresAt);

      // In development mode, log the reset link to console
      if (isDevelopment) {
        const resetUrl = `${new URL(request.url).origin}/reset-password?token=${resetToken}`;
        console.log('='.repeat(80));
        console.log('Development mode: Password reset link');
        console.log('='.repeat(80));
        console.log(`Username: ${user.username}`);
        console.log(`Email: ${user.email}`);
        console.log(`Reset URL: ${resetUrl}`);
        console.log(`Expires: ${expiresAt.toISOString()}`);
        console.log('='.repeat(80));

        devInfo = { resetToken, resetUrl };
      }
    }

    return new Response(JSON.stringify({
      success: true,
      message: 'If an account with that email exists, a password reset link has been sent.',
      ...(isDevelopment ? { devInfo } : {})
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