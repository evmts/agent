import type { APIRoute } from 'astro';
import { getUserByResetToken, updateUserPassword, deletePasswordResetToken, deleteAllUserSessions } from '@plue/db';
import { hash } from '@node-rs/argon2';

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json();
    const { token, password } = body;

    if (!token || !password) {
      return new Response(JSON.stringify({ error: 'Token and password are required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Find valid reset token
    const tokenResult = await getUserByResetToken(token);

    if (!tokenResult) {
      return new Response(JSON.stringify({ error: 'Invalid or expired reset token' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const userId = Number(tokenResult.user_id);

    // Hash new password
    const passwordHash = await hash(password);

    // Update password
    await updateUserPassword(userId, passwordHash);

    // Delete used reset token
    await deletePasswordResetToken(token);

    // Invalidate all sessions for this user
    await deleteAllUserSessions(userId);

    return new Response(JSON.stringify({ 
      success: true,
      message: 'Password has been reset successfully. Please log in with your new password.'
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Password reset confirm error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};