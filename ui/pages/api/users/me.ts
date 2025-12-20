import type { APIRoute } from 'astro';
import {
  getUserBySession,
  validateCsrfToken,
  csrfErrorResponse,
  validateTextInput
} from '../../../lib/auth-helpers';
import { getUserById, updateUserProfile as dbUpdateUserProfile } from '../../../lib/auth-db';

export const GET: APIRoute = async ({ request }) => {
  try {
    const user = await getUserBySession(request);

    if (!user) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get full user details
    const fullUser = await getUserById(user.id);

    if (!fullUser) {
      return new Response(JSON.stringify({ error: 'User not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({
      user: {
        id: Number(fullUser.id),
        username: fullUser.username,
        email: fullUser.email,
        display_name: fullUser.display_name,
        bio: fullUser.bio,
        avatar_url: fullUser.avatar_url,
        isAdmin: fullUser.is_admin,
        isActive: fullUser.is_active,
        created_at: fullUser.created_at
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Get current user error:', error instanceof Error ? error.message : 'Unknown error');
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

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
    const { display_name, bio, avatar_url } = body;

    // Validate inputs
    const displayNameValidation = validateTextInput(display_name, 'Display name', { maxLength: 100 });
    if (!displayNameValidation.valid) {
      return new Response(JSON.stringify({ error: displayNameValidation.error }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const bioValidation = validateTextInput(bio, 'Bio', { maxLength: 500 });
    if (!bioValidation.valid) {
      return new Response(JSON.stringify({ error: bioValidation.error }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const avatarUrlValidation = validateTextInput(avatar_url, 'Avatar URL', { maxLength: 500 });
    if (!avatarUrlValidation.valid) {
      return new Response(JSON.stringify({ error: avatarUrlValidation.error }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Update user profile
    const updatedUser = await dbUpdateUserProfile(user.id, {
      display_name: displayNameValidation.value || undefined,
      bio: bioValidation.value || undefined,
      avatar_url: avatarUrlValidation.value || undefined
    });

    if (!updatedUser) {
      return new Response(JSON.stringify({ error: 'Failed to update profile' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({
      success: true,
      user: {
        id: Number(updatedUser.id),
        username: updatedUser.username,
        email: updatedUser.email,
        display_name: updatedUser.display_name,
        bio: updatedUser.bio,
        avatar_url: updatedUser.avatar_url,
        isAdmin: updatedUser.is_admin,
        isActive: updatedUser.is_active,
        created_at: updatedUser.created_at
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Update user error:', error instanceof Error ? error.message : 'Unknown error');
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};