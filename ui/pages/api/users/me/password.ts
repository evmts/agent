import type { APIRoute } from 'astro';
import {
  getUserBySession,
  clearSessionCookie,
  validateCsrfToken,
  csrfErrorResponse,
  validatePassword
} from '../../../../lib/auth-helpers';
import { getUserById, updateUserPassword, deleteAllUserSessions } from '../../../../lib/auth-db';
import { hash, verify } from '@node-rs/argon2';

export const PUT: APIRoute = async ({ request }) => {
  try {
    // Validate CSRF token
    if (!validateCsrfToken(request)) {
      return csrfErrorResponse();
    }

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

    // Validate input lengths to prevent DoS
    if (currentPassword.length > 128 || newPassword.length > 128) {
      return new Response(JSON.stringify({ error: 'Password too long' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate new password complexity
    const passwordValidation = validatePassword(newPassword);
    if (!passwordValidation.valid) {
      return new Response(JSON.stringify({
        error: 'New password does not meet requirements',
        details: passwordValidation.errors
      }), {
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
    console.error('Update password error:', error instanceof Error ? error.message : 'Unknown error');
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};