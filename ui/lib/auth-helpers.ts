/**
 * Authentication helper functions for API routes.
 */

import { getUserBySession as dbGetUserBySession } from './auth-db';
import type { AuthUser } from './types';

export function getSessionIdFromRequest(request: Request): string | null {
  const cookies = request.headers.get('cookie') || '';
  const sessionMatch = cookies.match(/session=([^;]+)/);
  return sessionMatch ? sessionMatch[1] : null;
}

export async function getUserBySession(request: Request): Promise<AuthUser | null> {
  const sessionId = getSessionIdFromRequest(request);
  if (!sessionId) {
    return null;
  }
  
  return await dbGetUserBySession(sessionId);
}

export function createSessionCookie(sessionId: string, maxAge: number = 7 * 24 * 60 * 60): string {
  return `session=${sessionId}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=${maxAge}`;
}

export function clearSessionCookie(): string {
  return 'session=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0';
}