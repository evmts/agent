import type { APIRoute } from 'astro';
import { getUserBySession } from '../../../lib/auth-helpers';
import { getUserById, updateUserProfile as dbUpdateUserProfile } from '../../../../db/auth';

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
    console.error('Get current user error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

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
    const { display_name, bio, avatar_url } = body;

    // Update user profile
    const updatedUser = await dbUpdateUserProfile(user.id, {
      display_name,
      bio,
      avatar_url
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
    console.error('Update user error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};