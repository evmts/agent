import { randomBytes } from 'crypto';
import sql from '../db/client';

export interface SessionData {
  userId: number;
  username: string;
  isAdmin: boolean;
  [key: string]: any;
}

const SESSION_DURATION = 30 * 24 * 60 * 60 * 1000; // 30 days in ms

/**
 * Create a new session
 */
export async function createSession(userId: number, username: string, isAdmin: boolean): Promise<string> {
  const sessionKey = randomBytes(32).toString('hex');
  const data: SessionData = { userId, username, isAdmin };
  const dataBuffer = Buffer.from(JSON.stringify(data));
  const expiresAt = new Date(Date.now() + SESSION_DURATION);

  await sql`
    INSERT INTO auth_sessions (session_key, user_id, data, expires_at)
    VALUES (${sessionKey}, ${userId}, ${dataBuffer}, ${expiresAt})
  `;

  return sessionKey;
}

/**
 * Get session data by key
 */
export async function getSession(sessionKey: string): Promise<SessionData | null> {
  if (!sessionKey) return null;

  const [session] = await sql<Array<{
    user_id: number;
    data: Buffer;
    expires_at: Date;
  }>>`
    SELECT user_id, data, expires_at
    FROM auth_sessions
    WHERE session_key = ${sessionKey}
      AND expires_at > NOW()
  `;

  if (!session) return null;

  try {
    return JSON.parse(session.data.toString());
  } catch (error) {
    console.error('Failed to parse session data:', error);
    return null;
  }
}

/**
 * Update session expiration (refresh on activity)
 */
export async function refreshSession(sessionKey: string): Promise<void> {
  const expiresAt = new Date(Date.now() + SESSION_DURATION);

  await sql`
    UPDATE auth_sessions
    SET expires_at = ${expiresAt}, updated_at = NOW()
    WHERE session_key = ${sessionKey}
  `;
}

/**
 * Delete a session (logout)
 */
export async function deleteSession(sessionKey: string): Promise<void> {
  await sql`
    DELETE FROM auth_sessions
    WHERE session_key = ${sessionKey}
  `;
}

/**
 * Cleanup expired sessions (run periodically)
 */
export async function cleanupExpiredSessions(): Promise<number> {
  const result = await sql`
    DELETE FROM auth_sessions
    WHERE expires_at <= NOW()
  `;

  return result.count;
}

/**
 * Cleanup expired SIWE nonces (run periodically)
 */
export async function cleanupExpiredNonces(): Promise<number> {
  const result = await sql`
    DELETE FROM siwe_nonces
    WHERE expires_at <= NOW()
  `;

  return result.count;
}

/**
 * Start session cleanup background job
 */
export function startSessionCleanup(): void {
  // Run cleanup every hour
  setInterval(async () => {
    try {
      const cleanedSessions = await cleanupExpiredSessions();
      if (cleanedSessions > 0) {
        console.log(`Cleaned up ${cleanedSessions} expired sessions`);
      }

      // Also clean up expired SIWE nonces
      const cleanedNonces = await cleanupExpiredNonces();
      if (cleanedNonces > 0) {
        console.log(`Cleaned up ${cleanedNonces} expired SIWE nonces`);
      }
    } catch (error) {
      console.error('Cleanup error:', error);
    }
  }, 60 * 60 * 1000); // 1 hour

  // Run initial cleanup
  cleanupExpiredSessions().catch(console.error);
  cleanupExpiredNonces().catch(console.error);
}