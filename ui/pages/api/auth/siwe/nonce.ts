import type { APIRoute } from 'astro';
import { randomBytes } from 'crypto';
import sql from '../../../../lib/db';

export const GET: APIRoute = async () => {
  try {
    // Generate a cryptographically secure nonce
    const nonce = randomBytes(16).toString('base64url');

    // Store nonce in database with 10 minute expiration
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
    await sql`
      INSERT INTO siwe_nonces (nonce, expires_at)
      VALUES (${nonce}, ${expiresAt})
    `;

    return new Response(JSON.stringify({ nonce }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Failed to generate nonce:', error);
    return new Response(JSON.stringify({ error: 'Failed to generate nonce' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
