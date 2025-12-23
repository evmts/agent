/**
 * SIWE (Sign-In With Ethereum) Data Access Object
 *
 * SQL operations for SIWE nonce management and wallet authentication.
 */

import { sql } from './client';

// =============================================================================
// Types
// =============================================================================

export interface NonceRecord {
  nonce: string;
  used_at: Date | null;
}

export interface WalletUser {
  id: number;
  username: string;
  email: string | null;
  display_name: string | null;
  is_admin: boolean;
  is_active: boolean;
  prohibit_login: boolean;
  wallet_address: string;
}

// =============================================================================
// Duration Constants
// =============================================================================

export const NONCE_DURATION_MS = 10 * 60 * 1000; // 10 minutes

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Validate a nonce exists and is not expired/used
 */
export async function validateNonce(nonce: string): Promise<NonceRecord | null> {
  const [record] = await sql<NonceRecord[]>`
    SELECT nonce, used_at
    FROM siwe_nonces
    WHERE nonce = ${nonce} AND expires_at > NOW()
  `;

  return record || null;
}

/**
 * Get user by wallet address
 */
export async function getUserByWallet(walletAddress: string): Promise<WalletUser | null> {
  const [user] = await sql<WalletUser[]>`
    SELECT id, username, email, display_name, is_admin, is_active, prohibit_login, wallet_address
    FROM users
    WHERE wallet_address = ${walletAddress}
  `;

  return user || null;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Create a new SIWE nonce
 */
export async function createNonce(nonce: string, expiresAt: Date): Promise<void> {
  await sql`
    INSERT INTO siwe_nonces (nonce, expires_at)
    VALUES (${nonce}, ${expiresAt})
  `;
}

/**
 * Mark a nonce as used
 */
export async function markNonceUsed(nonce: string, walletAddress: string): Promise<void> {
  await sql`
    UPDATE siwe_nonces SET used_at = NOW(), wallet_address = ${walletAddress}
    WHERE nonce = ${nonce}
  `;
}

/**
 * Get or create a user by wallet address
 */
export async function getOrCreateUserByWallet(walletAddress: string): Promise<WalletUser> {
  // Check if user exists
  let [user] = await sql<WalletUser[]>`
    SELECT id, username, email, display_name, is_admin, is_active, prohibit_login, wallet_address
    FROM users
    WHERE wallet_address = ${walletAddress}
  `;

  if (!user) {
    // Generate username from wallet address
    const username = walletAddress.slice(0, 6) + walletAddress.slice(-4);

    // Create user
    [user] = await sql<WalletUser[]>`
      INSERT INTO users (username, lower_username, wallet_address, is_active)
      VALUES (${username}, ${username.toLowerCase()}, ${walletAddress}, true)
      RETURNING id, username, email, display_name, is_admin, is_active, prohibit_login, wallet_address
    `;
  }

  return user;
}

/**
 * Create an auth session for a wallet user
 */
export async function createAuthSession(
  userId: number,
  sessionId: string,
  username: string,
  isAdmin: boolean,
  expiresAt: Date
): Promise<void> {
  await sql`
    INSERT INTO auth_sessions (session_key, user_id, username, is_admin, expires_at)
    VALUES (${sessionId}, ${userId}, ${username}, ${isAdmin}, ${expiresAt})
  `;
}

/**
 * Update user's last login timestamp
 */
export async function updateLastLogin(userId: number): Promise<void> {
  await sql`UPDATE users SET last_login_at = NOW() WHERE id = ${userId}`;
}

/**
 * Cleanup expired nonces
 */
export async function cleanupExpiredNonces(): Promise<void> {
  await sql`
    DELETE FROM siwe_nonces
    WHERE expires_at < NOW()
  `;
}
