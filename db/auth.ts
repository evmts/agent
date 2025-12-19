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
    JOIN sessions s ON s.user_id = u.id
    WHERE s.id = ${sessionId} AND s.expires_at > NOW()
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
  const rows = await sql`
    INSERT INTO users (username, lower_username, email, lower_email, password_hash, display_name, activation_token, is_active)
    VALUES (
      ${userData.username},
      ${userData.username.toLowerCase()},
      ${userData.email},
      ${userData.email.toLowerCase()},
      ${userData.passwordHash},
      ${userData.displayName || null},
      ${userData.activationToken},
      false
    )
    RETURNING id, username, email, display_name
  `;

  return rows[0];
}

export async function createSession(userId: number, sessionId: string, expiresAt: Date) {
  await sql`
    INSERT INTO sessions (id, user_id, expires_at)
    VALUES (${sessionId}, ${userId}, ${expiresAt})
  `;
}

export async function deleteSession(sessionId: string) {
  await sql`
    DELETE FROM sessions WHERE id = ${sessionId}
  `;
}

export async function deleteAllUserSessions(userId: number) {
  await sql`
    DELETE FROM sessions WHERE user_id = ${userId}
  `;
}

export async function activateUser(token: string) {
  const rows = await sql`
    UPDATE users 
    SET is_active = true, activation_token = NULL
    WHERE activation_token = ${token} AND is_active = false
    RETURNING id, username, email, display_name
  `;

  return rows[0] || null;
}

export async function getUserByActivationToken(token: string) {
  const rows = await sql`
    SELECT id, username, email
    FROM users
    WHERE activation_token = ${token} AND is_active = false
  `;

  return rows[0] || null;
}

export async function createPasswordResetToken(userId: number, token: string, expiresAt: Date) {
  await sql`
    INSERT INTO password_reset_tokens (user_id, token, expires_at)
    VALUES (${userId}, ${token}, ${expiresAt})
    ON CONFLICT (user_id) DO UPDATE SET
      token = EXCLUDED.token,
      expires_at = EXCLUDED.expires_at,
      created_at = NOW()
  `;
}

export async function getUserByResetToken(token: string) {
  const rows = await sql`
    SELECT user_id
    FROM password_reset_tokens
    WHERE token = ${token} AND expires_at > NOW()
  `;

  return rows[0] || null;
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
    DELETE FROM password_reset_tokens
    WHERE token = ${token}
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
    SELECT id, username, email, display_name, bio, avatar_url, is_admin, is_active, created_at
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