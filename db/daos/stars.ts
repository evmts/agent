/**
 * Stars Data Access Object
 *
 * SQL operations for repository stars.
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface Stargazer {
  id: number;
  username: string;
  display_name: string | null;
  avatar_url: string | null;
  bio: string | null;
  starred_at: Date;
}

export interface StarredRepo {
  id: number;
  name: string;
  description: string | null;
  owner_username: string;
  starred_at: Date;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get stargazers for a repository
 */
export async function getStargazers(
  repositoryId: number,
  limit: number = 30,
  offset: number = 0
): Promise<Stargazer[]> {
  return await sql<Stargazer[]>`
    SELECT
      u.id,
      u.username,
      u.display_name,
      u.avatar_url,
      u.bio,
      s.created_at as starred_at
    FROM stars s
    JOIN users u ON s.user_id = u.id
    WHERE s.repository_id = ${repositoryId}
    ORDER BY s.created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Count stargazers for a repository
 */
export async function countStargazers(repositoryId: number): Promise<number> {
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM stars
    WHERE repository_id = ${repositoryId}
  `;
  return result?.count || 0;
}

/**
 * Get starred repositories for a user
 */
export async function getStarredRepos(
  userId: number,
  limit: number = 30,
  offset: number = 0
): Promise<StarredRepo[]> {
  return await sql<StarredRepo[]>`
    SELECT
      r.id,
      r.name,
      r.description,
      u.username as owner_username,
      s.created_at as starred_at
    FROM stars s
    JOIN repositories r ON s.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE s.user_id = ${userId}
    ORDER BY s.created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Count starred repositories for a user
 */
export async function countStarredRepos(userId: number): Promise<number> {
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM stars
    WHERE user_id = ${userId}
  `;
  return result?.count || 0;
}

/**
 * Check if user has starred a repository
 */
export async function hasStar(userId: number, repositoryId: number): Promise<boolean> {
  const [result] = await sql<[{ exists: boolean }]>`
    SELECT EXISTS(
      SELECT 1 FROM stars
      WHERE user_id = ${userId} AND repository_id = ${repositoryId}
    ) as exists
  `;
  return result?.exists || false;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Star a repository
 */
export async function star(userId: number, repositoryId: number): Promise<void> {
  await sql`
    INSERT INTO stars (user_id, repository_id)
    VALUES (${userId}, ${repositoryId})
    ON CONFLICT DO NOTHING
  `;
}

/**
 * Unstar a repository
 */
export async function unstar(userId: number, repositoryId: number): Promise<void> {
  await sql`
    DELETE FROM stars
    WHERE user_id = ${userId} AND repository_id = ${repositoryId}
  `;
}

/**
 * Get star counts for multiple repositories in a single query
 */
export async function getStarCountsForRepos(
  repositoryIds: number[]
): Promise<Map<number, number>> {
  if (repositoryIds.length === 0) {
    return new Map();
  }
  const counts = await sql<Array<{ repository_id: number; count: number }>>`
    SELECT repository_id, COUNT(*)::int as count
    FROM stars
    WHERE repository_id = ANY(${repositoryIds})
    GROUP BY repository_id
  `;
  return new Map(counts.map(c => [c.repository_id, c.count]));
}
