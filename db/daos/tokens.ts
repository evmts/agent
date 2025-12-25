/**
 * Access Tokens Data Access Object
 *
 * SQL operations for user access tokens.
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface AccessToken {
  id: number;
  user_id: number;
  name: string;
  token_last_eight: string;
  scopes: string;
  created_at: Date;
  last_used_at: Date | null;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * List access tokens for a user
 */
export async function listByUserId(userId: number): Promise<AccessToken[]> {
  return await sql<AccessToken[]>`
    SELECT
      id,
      name,
      token_last_eight,
      scopes,
      created_at,
      last_used_at
    FROM access_tokens
    WHERE user_id = ${userId}
    ORDER BY created_at DESC
  `;
}

/**
 * Get token by ID
 */
export async function getById(id: number): Promise<AccessToken | null> {
  const [token] = await sql<AccessToken[]>`
    SELECT * FROM access_tokens WHERE id = ${id}
  `;
  return token || null;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Delete a token
 */
export async function remove(id: number, userId: number): Promise<void> {
  await sql`DELETE FROM access_tokens WHERE id = ${id} AND user_id = ${userId}`;
}

/**
 * Update last used timestamp
 */
export async function markUsed(id: number): Promise<void> {
  await sql`UPDATE access_tokens SET last_used_at = NOW() WHERE id = ${id}`;
}
