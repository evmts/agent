import type { APIRoute } from 'astro';
import { siwe } from '@plue/db';

/**
 * Get current authenticated user from edge worker header.
 * The edge worker sets X-Plue-User-Address header when user is authenticated.
 */
export const GET: APIRoute = async ({ request }) => {
  try {
    // Read wallet address from header set by edge worker
    const walletAddress = request.headers.get('X-Plue-User-Address');

    if (!walletAddress) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Look up user by wallet address
    const user = await siwe.getUserByWallet(walletAddress);

    if (!user) {
      return new Response(JSON.stringify({ error: 'User not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Return user data in expected format
    return new Response(JSON.stringify({
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        isActive: user.is_active,
        isAdmin: user.is_admin,
        walletAddress: user.wallet_address,
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Auth error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};