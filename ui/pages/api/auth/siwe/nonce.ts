import type { APIRoute } from 'astro';
import { randomBytes } from 'crypto';
import { siwe } from '../../../../../db';

export const GET: APIRoute = async () => {
  try {
    // Generate a cryptographically secure alphanumeric nonce
    // SIWE requires alphanumeric characters only (no - or _)
    const nonce = randomBytes(16).toString('hex');

    // Store nonce in database with 10 minute expiration
    const expiresAt = new Date(Date.now() + siwe.NONCE_DURATION_MS);
    await siwe.createNonce(nonce, expiresAt);

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
