/**
 * Users Data Access Object
 *
 * SQL operations for user queries (beyond auth).
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface User {
  id: number;
  username: string;
  display_name: string | null;
  email: string | null;
  avatar_url: string | null;
  bio: string | null;
  location: string | null;
  website: string | null;
  created_at: Date;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get user by username
 */
export async function getByUsername(username: string): Promise<User | null> {
  const [user] = await sql<User[]>`
    SELECT * FROM users WHERE username = ${username}
  `;
  return user || null;
}

/**
 * Get user by ID
 */
export async function getById(id: number): Promise<User | null> {
  const [user] = await sql<User[]>`
    SELECT * FROM users WHERE id = ${id}
  `;
  return user || null;
}

/**
 * Get user by email
 */
export async function getByEmail(email: string): Promise<User | null> {
  const [user] = await sql<User[]>`
    SELECT * FROM users WHERE email = ${email}
  `;
  return user || null;
}

/**
 * List all users (for admin/explore)
 */
export async function list(
  limit: number = 50,
  offset: number = 0
): Promise<User[]> {
  return await sql<User[]>`
    SELECT * FROM users
    ORDER BY username
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Search users by username
 */
export async function search(
  query: string,
  limit: number = 50,
  offset: number = 0
): Promise<User[]> {
  const searchPattern = `%${query}%`;
  return await sql<User[]>`
    SELECT * FROM users
    WHERE username ILIKE ${searchPattern}
       OR display_name ILIKE ${searchPattern}
    ORDER BY username
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Count total users
 */
export async function count(): Promise<number> {
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM users
  `;
  return result?.count || 0;
}

/**
 * Count users matching a search query
 */
export async function countSearch(query: string): Promise<number> {
  const searchPattern = `%${query}%`;
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count
    FROM users
    WHERE username ILIKE ${searchPattern}
       OR display_name ILIKE ${searchPattern}
  `;
  return result?.count || 0;
}

/**
 * Get repository count for a user
 */
export async function getRepositoryCount(userId: number): Promise<number> {
  const [result] = await sql<[{ repo_count: number }]>`
    SELECT COUNT(*)::int as repo_count
    FROM repositories
    WHERE user_id = ${userId}
  `;
  return result?.repo_count || 0;
}
