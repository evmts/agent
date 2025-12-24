/**
 * Auth route handlers for edge worker
 *
 * Implements SIWE authentication at the Cloudflare edge:
 * - GET  /api/auth/nonce  - Generate nonce for signing
 * - POST /api/auth/verify - Verify signature and create session
 * - POST /api/auth/logout - Clear session
 *
 * Uses Durable Objects for nonce storage to ensure strong consistency
 * and prevent replay attacks.
 */

import type { Env } from '../types';
import { generateNonce, verifySiweMessage } from '../lib/siwe';
import {
  createSessionToken,
  createSessionCookie,
  createClearSessionCookie,
  getSessionFromRequest,
  verifySessionToken,
} from '../lib/session';

/** Global nonce DO instance name */
const NONCE_DO_NAME = 'global-nonces';

interface VerifyRequest {
  message: string;
  signature: string;
}

/**
 * Handle auth routes
 */
export async function handleAuthRoute(
  request: Request,
  env: Env,
  pathname: string,
): Promise<Response> {
  switch (pathname) {
    case '/api/auth/nonce':
      if (request.method !== 'GET') {
        return methodNotAllowed();
      }
      return handleNonce(env);

    case '/api/auth/verify':
      if (request.method !== 'POST') {
        return methodNotAllowed();
      }
      return handleVerify(request, env);

    case '/api/auth/logout':
      if (request.method !== 'POST') {
        return methodNotAllowed();
      }
      return handleLogout(request, env);

    default:
      return notFound();
  }
}

/**
 * GET /api/auth/nonce
 * Generate a nonce for SIWE signing
 */
async function handleNonce(env: Env): Promise<Response> {
  const nonce = generateNonce();

  // Store nonce in Durable Object for strong consistency
  const authDO = env.AUTH_DO.get(env.AUTH_DO.idFromName(NONCE_DO_NAME));
  const response = await authDO.fetch(new Request('https://do/nonce', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ nonce }),
  }));

  if (!response.ok) {
    console.error('Failed to store nonce in DO:', await response.text());
    return jsonResponse({ error: 'Failed to generate nonce' }, 500);
  }

  return jsonResponse({ nonce });
}

/**
 * POST /api/auth/verify
 * Verify SIWE signature and create session
 */
async function handleVerify(request: Request, env: Env): Promise<Response> {
  let body: VerifyRequest;
  try {
    body = await request.json() as VerifyRequest;
  } catch {
    return jsonResponse({ error: 'Invalid JSON' }, 400);
  }

  if (!body.message || !body.signature) {
    return jsonResponse({ error: 'Missing message or signature' }, 400);
  }

  try {
    // Extract expected domain from request
    // Use CF-Host header (set by Cloudflare) or fall back to Host header
    const expectedDomain = request.headers.get('CF-Host') ||
                          request.headers.get('Host') ||
                          new URL(request.url).host;

    // SECURITY: Verify the SIWE signature with domain validation
    // This prevents cross-domain replay attacks where a signature
    // obtained on one domain could be used on another
    const { address, message: siweMessage } = await verifySiweMessage(
      body.message,
      body.signature,
      expectedDomain,  // Validate domain matches request
    );

    // Consume nonce atomically via Durable Object (replay protection)
    // This is the critical operation - nonce must be used only once
    const authDO = env.AUTH_DO.get(env.AUTH_DO.idFromName(NONCE_DO_NAME));
    const nonceResponse = await authDO.fetch(
      new Request(`https://do/nonce/${siweMessage.nonce}`, { method: 'DELETE' })
    );

    if (!nonceResponse.ok) {
      const errorData = await nonceResponse.json() as { error?: string };
      const errorMsg = errorData.error || 'Invalid or expired nonce';
      return jsonResponse({ error: errorMsg }, 401);
    }

    // Create session JWT
    const token = await createSessionToken(env.JWT_SECRET, {
      address,
    });

    // Store session in user's DO for future blocklist checking (optional)
    const userDO = env.AUTH_DO.get(env.AUTH_DO.idFromName(address));
    await userDO.fetch(new Request('https://do/session', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ address }),
    }));

    // Create response with session cookie
    const isProduction = !env.ORIGIN_HOST.includes('localhost');
    const response = jsonResponse({
      message: 'Authentication successful',
      address,
    });

    response.headers.set('Set-Cookie', createSessionCookie(token, isProduction));

    return response;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Verification failed';
    return jsonResponse({ error: message }, 401);
  }
}

/**
 * POST /api/auth/logout
 * Clear session cookie and invalidate the session in the DO
 */
async function handleLogout(request: Request, env: Env): Promise<Response> {
  const isProduction = !env.ORIGIN_HOST.includes('localhost');

  // Try to invalidate the session in the Durable Object
  // This prevents the JWT from being used even if stolen
  try {
    const token = getSessionFromRequest(request);
    if (token) {
      const payload = await verifySessionToken(env.JWT_SECRET, token);
      if (payload?.address) {
        // Mark this session as logged out in the user's DO
        const userDO = env.AUTH_DO.get(env.AUTH_DO.idFromName(payload.address));
        await userDO.fetch(new Request('https://do/logout', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ address: payload.address }),
        }));
      }
    }
  } catch (error) {
    // Log but don't fail the logout - clearing the cookie is the primary action
    console.warn('Failed to invalidate session in DO:', error);
  }

  const response = jsonResponse({ message: 'Logout successful' });
  response.headers.set('Set-Cookie', createClearSessionCookie(isProduction));
  return response;
}

/**
 * Get authenticated user info from session
 * Returns null if not authenticated
 */
export async function getAuthenticatedUser(
  request: Request,
  env: Env,
): Promise<{ address: string } | null> {
  const token = getSessionFromRequest(request);
  if (!token) return null;

  const payload = await verifySessionToken(env.JWT_SECRET, token);
  if (!payload) return null;

  return { address: payload.address };
}

// Helper functions

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
    },
  });
}

function methodNotAllowed(): Response {
  return jsonResponse({ error: 'Method not allowed' }, 405);
}

function notFound(): Response {
  return jsonResponse({ error: 'Not found' }, 404);
}
