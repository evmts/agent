import { Context, Next } from 'hono';
import { getCookie, setCookie } from 'hono/cookie';
import { getSession, refreshSession } from '../lib/session';
import sql from '../../db/client';

export interface AuthUser {
  id: number;
  username: string;
  email: string;
  displayName: string | null;
  isAdmin: boolean;
  isActive: boolean;
}

declare module 'hono' {
  interface ContextVariableMap {
    user: AuthUser | null;
    sessionKey: string | null;
  }
}

const SESSION_COOKIE_NAME = 'plue_session';

/**
 * Auth middleware - loads user from session cookie
 * Does not require authentication, just loads if present
 */
export async function authMiddleware(c: Context, next: Next) {
  const sessionKey = getCookie(c, SESSION_COOKIE_NAME);

  if (!sessionKey) {
    c.set('user', null);
    c.set('sessionKey', null);
    await next();
    return;
  }

  const sessionData = await getSession(sessionKey);

  if (!sessionData) {
    // Invalid or expired session
    c.set('user', null);
    c.set('sessionKey', null);
    await next();
    return;
  }

  // Load fresh user data from database
  const [user] = await sql<Array<{
    id: number;
    username: string;
    email: string;
    display_name: string | null;
    is_admin: boolean;
    is_active: boolean;
    prohibit_login: boolean;
  }>>`
    SELECT id, username, email, display_name, is_admin, is_active, prohibit_login
    FROM users
    WHERE id = ${sessionData.userId}
  `;

  if (!user || user.prohibit_login) {
    c.set('user', null);
    c.set('sessionKey', null);
    await next();
    return;
  }

  // Refresh session expiration
  await refreshSession(sessionKey);

  c.set('user', {
    id: user.id,
    username: user.username,
    email: user.email,
    displayName: user.display_name,
    isAdmin: user.is_admin,
    isActive: user.is_active,
  });
  c.set('sessionKey', sessionKey);

  await next();
}

/**
 * Require authentication - returns 401 if not authenticated
 */
export async function requireAuth(c: Context, next: Next) {
  const user = c.get('user');

  if (!user) {
    return c.json({ error: 'Authentication required' }, 401);
  }

  await next();
}

/**
 * Require active account - returns 403 if not activated
 */
export async function requireActiveAccount(c: Context, next: Next) {
  const user = c.get('user');

  if (!user) {
    return c.json({ error: 'Authentication required' }, 401);
  }

  if (!user.isActive) {
    return c.json({ error: 'Account not activated. Please verify your email.' }, 403);
  }

  await next();
}

/**
 * Require admin - returns 403 if not admin
 */
export async function requireAdmin(c: Context, next: Next) {
  const user = c.get('user');

  if (!user) {
    return c.json({ error: 'Authentication required' }, 401);
  }

  if (!user.isAdmin) {
    return c.json({ error: 'Admin access required' }, 403);
  }

  await next();
}

/**
 * Helper to set session cookie
 */
export function setSessionCookie(c: Context, sessionKey: string) {
  setCookie(c, SESSION_COOKIE_NAME, sessionKey, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'Lax',
    maxAge: 30 * 24 * 60 * 60, // 30 days
    path: '/',
  });
}

/**
 * Helper to clear session cookie
 */
export function clearSessionCookie(c: Context) {
  setCookie(c, SESSION_COOKIE_NAME, '', {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'Lax',
    maxAge: 0,
    path: '/',
  });
}