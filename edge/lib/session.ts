/**
 * JWT Session management for edge worker
 *
 * Signs and verifies JWTs for authenticated sessions.
 * Uses the jose library for JWT operations.
 */

import jwt from '@tsndr/cloudflare-worker-jwt';

export interface SessionPayload {
  /** User's Ethereum address (lowercase) */
  address: string;
  /** User ID from origin database */
  userId?: number;
  /** Username */
  username?: string;
  /** Whether user is admin */
  isAdmin?: boolean;
  /** JWT issued at timestamp */
  iat: number;
  /** JWT expiration timestamp */
  exp: number;
}

/** Session cookie name */
export const SESSION_COOKIE_NAME = 'plue_session';

/** Session duration: 30 days in seconds */
const SESSION_DURATION = 30 * 24 * 60 * 60;

/**
 * Create a signed JWT for a session
 */
export async function createSessionToken(
  secret: string,
  payload: Omit<SessionPayload, 'iat' | 'exp'>,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const token = await jwt.sign(
    {
      ...payload,
      iat: now,
      exp: now + SESSION_DURATION,
    },
    secret,
    { algorithm: 'HS256' },
  );

  return token;
}

/**
 * Verify and decode a session JWT
 *
 * @returns The decoded payload or null if invalid/expired
 */
export async function verifySessionToken(
  secret: string,
  token: string,
): Promise<SessionPayload | null> {
  try {
    const isValid = await jwt.verify(token, secret, { algorithm: 'HS256' });
    if (!isValid) {
      return null;
    }

    const decoded = jwt.decode(token);
    if (!decoded || !decoded.payload) {
      return null;
    }

    const payload = decoded.payload as SessionPayload;

    // Check expiration
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp && payload.exp < now) {
      return null;
    }

    return payload;
  } catch {
    return null;
  }
}

/**
 * Extract session token from request cookies
 */
export function getSessionFromRequest(request: Request): string | null {
  const cookieHeader = request.headers.get('Cookie');
  if (!cookieHeader) return null;

  const cookies = cookieHeader.split(';').map(c => c.trim());
  for (const cookie of cookies) {
    if (cookie.startsWith(`${SESSION_COOKIE_NAME}=`)) {
      return cookie.slice(SESSION_COOKIE_NAME.length + 1);
    }
  }

  return null;
}

/**
 * Create Set-Cookie header for session
 */
export function createSessionCookie(
  token: string,
  isProduction: boolean,
): string {
  const secure = isProduction ? '; Secure' : '';
  const maxAge = SESSION_DURATION;

  return `${SESSION_COOKIE_NAME}=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure}`;
}

/**
 * Create Set-Cookie header to clear session
 */
export function createClearSessionCookie(isProduction: boolean): string {
  const secure = isProduction ? '; Secure' : '';
  return `${SESSION_COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${secure}`;
}
