/**
 * SSH Keys Data Access Object
 *
 * SQL operations for user SSH keys.
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface SSHKey {
  id: number;
  user_id: number;
  name: string;
  fingerprint: string;
  public_key: string;
  created_at: Date;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * List SSH keys for a user
 */
export async function listByUserId(userId: number): Promise<SSHKey[]> {
  return await sql<SSHKey[]>`
    SELECT id, name, fingerprint, created_at
    FROM ssh_keys
    WHERE user_id = ${userId}
    ORDER BY created_at DESC
  `;
}

/**
 * Get SSH key by ID
 */
export async function getById(id: number): Promise<SSHKey | null> {
  const [key] = await sql<SSHKey[]>`
    SELECT * FROM ssh_keys WHERE id = ${id}
  `;
  return key || null;
}

/**
 * Check if fingerprint exists
 */
export async function fingerprintExists(fingerprint: string): Promise<boolean> {
  const [result] = await sql<[{ exists: boolean }]>`
    SELECT EXISTS(SELECT 1 FROM ssh_keys WHERE fingerprint = ${fingerprint}) as exists
  `;
  return result?.exists || false;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Create a new SSH key
 */
export async function create(
  userId: number,
  name: string,
  publicKey: string,
  fingerprint: string
): Promise<SSHKey> {
  const [key] = await sql<SSHKey[]>`
    INSERT INTO ssh_keys (user_id, name, public_key, fingerprint)
    VALUES (${userId}, ${name}, ${publicKey}, ${fingerprint})
    RETURNING *
  `;
  return key;
}

/**
 * Delete an SSH key
 */
export async function remove(id: number, userId: number): Promise<void> {
  await sql`DELETE FROM ssh_keys WHERE id = ${id} AND user_id = ${userId}`;
}
