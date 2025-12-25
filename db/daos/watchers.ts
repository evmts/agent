/**
 * Watchers Data Access Object
 *
 * SQL operations for repository watchers (watches table).
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface Watcher {
  id: number;
  username: string;
  display_name: string | null;
  avatar_url: string | null;
  bio: string | null;
  level: string;
  watching_since: Date;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get watchers for a repository
 */
export async function getWatchers(
  repositoryId: number,
  limit: number = 30,
  offset: number = 0
): Promise<Watcher[]> {
  return await sql<Watcher[]>`
    SELECT
      u.id,
      u.username,
      u.display_name,
      u.avatar_url,
      u.bio,
      w.level,
      w.created_at as watching_since
    FROM watches w
    JOIN users u ON w.user_id = u.id
    WHERE w.repository_id = ${repositoryId}
    ORDER BY w.created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Count watchers for a repository
 */
export async function countWatchers(repositoryId: number): Promise<number> {
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM watches
    WHERE repository_id = ${repositoryId}
  `;
  return result?.count || 0;
}

/**
 * Check if user is watching a repository
 */
export async function isWatching(userId: number, repositoryId: number): Promise<boolean> {
  const [result] = await sql<[{ exists: boolean }]>`
    SELECT EXISTS(
      SELECT 1 FROM watches
      WHERE user_id = ${userId} AND repository_id = ${repositoryId}
    ) as exists
  `;
  return result?.exists || false;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Watch a repository
 */
export async function watch(
  userId: number,
  repositoryId: number,
  level: string = 'all'
): Promise<void> {
  await sql`
    INSERT INTO watches (user_id, repository_id, level)
    VALUES (${userId}, ${repositoryId}, ${level})
    ON CONFLICT (user_id, repository_id)
    DO UPDATE SET level = ${level}
  `;
}

/**
 * Unwatch a repository
 */
export async function unwatch(userId: number, repositoryId: number): Promise<void> {
  await sql`
    DELETE FROM watches
    WHERE user_id = ${userId} AND repository_id = ${repositoryId}
  `;
}
