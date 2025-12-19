/**
 * Authentication database operations.
 */

import sql from "./client";
import type { AuthUser } from "../ui/lib/types";

export interface CreateSessionResult {
  sessionId: string;
  user: AuthUser;
}

export async function getUserBySession(sessionId: string): Promise<AuthUser | null> {
  const rows = await sql`
    SELECT u.id, u.username, u.email, u.display_name, u.is_admin, u.is_active
    FROM users u
    JOIN auth_sessions s ON s.user_id = u.id
    WHERE s.session_key = ${sessionId} AND s.expires_at > NOW()
  `;

  if (rows.length === 0) {
    return null;
  }

  const row = rows[0];
  return {
    id: Number(row.id),
    username: row.username as string,
    email: row.email as string,
    displayName: row.display_name as string | null,
    isAdmin: row.is_admin as boolean,
    isActive: row.is_active as boolean,
  };
}

export async function getUserByUsernameOrEmail(usernameOrEmail: string) {
  const rows = await sql`
    SELECT id, username, email, password_hash, display_name, is_admin, is_active
    FROM users
    WHERE (username = ${usernameOrEmail} OR email = ${usernameOrEmail})
    AND is_active = true
  `;

  return rows[0] || null;
}

export async function createUser(userData: {
  username: string;
  email: string;
  passwordHash: string;
  displayName?: string;
  activationToken: string;
}) {
  // Create user first
  const [user] = await sql`
    INSERT INTO users (username, lower_username, email, lower_email, password_hash, display_name, is_active)
    VALUES (
      ${userData.username},
      ${userData.username.toLowerCase()},
      ${userData.email},
      ${userData.email.toLowerCase()},
      ${userData.passwordHash},
      ${userData.displayName || null},
      false
    )
    RETURNING id, username, email, display_name
  `;

  // Create activation token
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours
  await sql`
    INSERT INTO email_verification_tokens (user_id, email, token_hash, token_type, expires_at)
    VALUES (${user.id}, ${userData.email}, ${userData.activationToken}, 'activate', ${expiresAt})
  `;

  return user;
}

export async function createSession(userId: number, sessionId: string, expiresAt: Date) {
  await sql`
    INSERT INTO auth_sessions (session_key, user_id, expires_at)
    VALUES (${sessionId}, ${userId}, ${expiresAt})
  `;
}

export async function deleteSession(sessionId: string) {
  await sql`
    DELETE FROM auth_sessions WHERE session_key = ${sessionId}
  `;
}

export async function deleteAllUserSessions(userId: number) {
  await sql`
    DELETE FROM auth_sessions WHERE user_id = ${userId}
  `;
}

export async function activateUser(token: string) {
  // Find the token
  const [tokenData] = await sql`
    SELECT user_id, email
    FROM email_verification_tokens
    WHERE token_hash = ${token} AND token_type = 'activate' AND expires_at > NOW()
  `;

  if (!tokenData) {
    return null;
  }

  // Activate the user
  const [user] = await sql`
    UPDATE users 
    SET is_active = true
    WHERE id = ${tokenData.user_id}
    RETURNING id, username, email, display_name
  `;

  // Delete the used token
  await sql`
    DELETE FROM email_verification_tokens
    WHERE token_hash = ${token} AND token_type = 'activate'
  `;

  return user;
}

export async function getUserByActivationToken(token: string) {
  const [tokenData] = await sql`
    SELECT u.id, u.username, u.email
    FROM users u
    JOIN email_verification_tokens t ON t.user_id = u.id
    WHERE t.token_hash = ${token} AND t.token_type = 'activate' AND t.expires_at > NOW()
    AND u.is_active = false
  `;

  return tokenData || null;
}

export async function createPasswordResetToken(userId: number, token: string, expiresAt: Date) {
  const [user] = await sql`SELECT email FROM users WHERE id = ${userId}`;
  
  await sql`
    INSERT INTO email_verification_tokens (user_id, email, token_hash, token_type, expires_at)
    VALUES (${userId}, ${user.email}, ${token}, 'reset_password', ${expiresAt})
    ON CONFLICT (token_hash) DO UPDATE SET
      expires_at = EXCLUDED.expires_at
  `;
}

export async function getUserByResetToken(token: string) {
  const [tokenData] = await sql`
    SELECT user_id
    FROM email_verification_tokens
    WHERE token_hash = ${token} AND token_type = 'reset_password' AND expires_at > NOW()
  `;

  return tokenData || null;
}

export async function updateUserPassword(userId: number, passwordHash: string) {
  await sql`
    UPDATE users 
    SET password_hash = ${passwordHash}
    WHERE id = ${userId}
  `;
}

export async function deletePasswordResetToken(token: string) {
  await sql`
    DELETE FROM email_verification_tokens
    WHERE token_hash = ${token} AND token_type = 'reset_password'
  `;
}

export async function getUserByEmail(email: string) {
  const rows = await sql`
    SELECT id, username, email
    FROM users
    WHERE email = ${email} AND is_active = true
  `;

  return rows[0] || null;
}

export async function getUserById(userId: number) {
  const rows = await sql`
    SELECT id, username, email, display_name, bio, avatar_url, is_admin, is_active, created_at, password_hash
    FROM users
    WHERE id = ${userId}
  `;

  return rows[0] || null;
}

export async function updateUserProfile(userId: number, updates: {
  display_name?: string;
  bio?: string;
  avatar_url?: string;
}) {
  const rows = await sql`
    UPDATE users 
    SET 
      display_name = COALESCE(${updates.display_name || null}, display_name),
      bio = COALESCE(${updates.bio || null}, bio),
      avatar_url = COALESCE(${updates.avatar_url || null}, avatar_url)
    WHERE id = ${userId}
    RETURNING id, username, email, display_name, bio, avatar_url, is_admin, is_active, created_at
  `;

  return rows[0] || null;
}

export async function getUserByUsername(username: string) {
  const rows = await sql`
    SELECT id, username, display_name, bio, avatar_url, created_at
    FROM users
    WHERE username = ${username} AND is_active = true
  `;

  return rows[0] || null;
}