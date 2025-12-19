import type { APIRoute } from 'astro';
import { getUserBySession, clearSessionCookie } from '../../../../lib/auth-helpers';
import { getUserById, updateUserPassword, deleteAllUserSessions } from '../../../../../db/auth';
import { hash, verify } from '@node-rs/argon2';

export const PUT: APIRoute = async ({ request }) => {
  try {
    const user = await getUserBySession(request);
    
    if (!user) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const body = await request.json();
    const { currentPassword, newPassword } = body;

    if (!currentPassword || !newPassword) {
      return new Response(JSON.stringify({ error: 'Current password and new password are required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get user with password hash
    const fullUser = await getUserById(user.id);
    
    if (!fullUser) {
      return new Response(JSON.stringify({ error: 'User not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Verify current password
    const isValid = await verify(fullUser.password_hash as string, currentPassword);
    if (!isValid) {
      return new Response(JSON.stringify({ error: 'Current password is incorrect' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Hash new password
    const newPasswordHash = await hash(newPassword);

    // Update password
    await updateUserPassword(user.id, newPasswordHash);

    // Invalidate all sessions for this user
    await deleteAllUserSessions(user.id);

    return new Response(JSON.stringify({ 
      success: true,
      message: 'Password updated successfully. Please log in again.'
    }), {
      status: 200,
      headers: { 
        'Content-Type': 'application/json',
        'Set-Cookie': clearSessionCookie()
      }
    });
  } catch (error) {
    console.error('Update password error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};