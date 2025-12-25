/**
 * Repositories Data Access Object
 *
 * SQL operations for repository management.
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface Repository {
  id: number;
  user_id: number;
  name: string;
  description: string | null;
  is_private: boolean;
  default_branch: string | null;
  default_bookmark: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface RepositoryStats {
  issueCount: number;
  starCount: number;
  landingCount: number;
  workflowRunning: number;
  workflowFailing: number;
}

export interface Bookmark {
  id?: number;
  repository_id: number;
  name: string;
  targetChangeId: string;
  is_default?: boolean;
  created_at?: Date;
  updated_at?: Date;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get repository by owner username and repo name
 */
export async function getByOwnerAndName(
  username: string,
  reponame: string
): Promise<Repository | null> {
  const [repo] = await sql<Repository[]>`
    SELECT r.*
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;
  return repo || null;
}

/**
 * Get repository by ID
 */
export async function getById(id: number): Promise<Repository | null> {
  const [repo] = await sql<Repository[]>`
    SELECT * FROM repositories WHERE id = ${id}
  `;
  return repo || null;
}

/**
 * List repositories for a user
 */
export async function listByUserId(
  userId: number,
  limit: number = 50
): Promise<Repository[]> {
  return await sql<Repository[]>`
    SELECT * FROM repositories
    WHERE user_id = ${userId}
    ORDER BY updated_at DESC
    LIMIT ${limit}
  `;
}

/**
 * Count total public repositories
 */
export async function countPublic(): Promise<number> {
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count
    FROM repositories
    WHERE is_private = false
  `;
  return result?.count || 0;
}

/**
 * List public repositories (for explore page)
 */
export async function listPublic(
  limit: number = 50,
  offset: number = 0,
  sortBy: 'name' | 'updated_at' = 'updated_at'
): Promise<Repository[]> {
  if (sortBy === 'name') {
    return await sql<Repository[]>`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE r.is_private = false
      ORDER BY r.name
      LIMIT ${limit} OFFSET ${offset}
    `;
  }
  return await sql<Repository[]>`
    SELECT r.*, u.username
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE r.is_private = false
    ORDER BY r.updated_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Search public repositories
 */
export async function searchPublic(
  query: string,
  limit: number = 50,
  offset: number = 0,
  sortBy: 'name' | 'updated_at' = 'updated_at'
): Promise<Repository[]> {
  const searchPattern = `%${query}%`;
  if (sortBy === 'name') {
    return await sql<Repository[]>`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE r.is_private = false
        AND (r.name ILIKE ${searchPattern} OR r.description ILIKE ${searchPattern})
      ORDER BY r.name
      LIMIT ${limit} OFFSET ${offset}
    `;
  }
  return await sql<Repository[]>`
    SELECT r.*, u.username
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE r.is_private = false
      AND (r.name ILIKE ${searchPattern} OR r.description ILIKE ${searchPattern})
    ORDER BY r.updated_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Get repository stats (issue count, star count, etc.)
 */
export async function getStats(repositoryId: number): Promise<RepositoryStats> {
  const [issueResult] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM issues
    WHERE repository_id = ${repositoryId} AND state = 'open'
  `;

  const [starResult] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM stars
    WHERE repository_id = ${repositoryId}
  `;

  let landingCount = 0;
  try {
    const [landingResult] = await sql<[{ count: number }]>`
      SELECT COUNT(*)::int as count FROM landing_queue
      WHERE repository_id = ${repositoryId} AND status NOT IN ('landed', 'cancelled')
    `;
    landingCount = landingResult?.count || 0;
  } catch {
    // landing_queue table may not exist yet
  }

  let workflowRunning = 0;
  let workflowFailing = 0;
  try {
    const [runningResult] = await sql<[{ count: number }]>`
      SELECT COUNT(*)::int as count FROM workflow_runs
      WHERE repository_id = ${repositoryId} AND status = 6
    `;
    workflowRunning = runningResult?.count || 0;

    const [failingResult] = await sql<[{ count: number }]>`
      SELECT COUNT(*)::int as count FROM workflow_runs
      WHERE repository_id = ${repositoryId} AND status = 2
      AND created_at > NOW() - INTERVAL '24 hours'
    `;
    workflowFailing = failingResult?.count || 0;
  } catch {
    // workflow tables may not exist yet
  }

  return {
    issueCount: issueResult?.count || 0,
    starCount: starResult?.count || 0,
    landingCount,
    workflowRunning,
    workflowFailing,
  };
}

/**
 * List public repositories filtered by topic
 */
export async function listPublicByTopic(
  topic: string,
  limit: number = 50,
  offset: number = 0,
  sortBy: 'name' | 'updated_at' = 'updated_at'
): Promise<Repository[]> {
  if (sortBy === 'name') {
    return await sql<Repository[]>`
      SELECT r.*, u.username
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE r.is_private = false AND ${topic} = ANY(r.topics)
      ORDER BY r.name
      LIMIT ${limit} OFFSET ${offset}
    `;
  }
  return await sql<Repository[]>`
    SELECT r.*, u.username
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE r.is_private = false AND ${topic} = ANY(r.topics)
    ORDER BY r.updated_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Get popular topics across all repositories
 */
export async function getPopularTopics(limit: number = 10): Promise<Array<{ topic: string; count: number }>> {
  return await sql<Array<{ topic: string; count: number }>>`
    SELECT unnest(topics) as topic, COUNT(*)::int as count
    FROM repositories
    WHERE is_private = false AND topics IS NOT NULL AND array_length(topics, 1) > 0
    GROUP BY topic
    ORDER BY count DESC
    LIMIT ${limit}
  `;
}

/**
 * Get branches for a repository
 */
export async function getBranches(repositoryId: number): Promise<Array<{ name: string }>> {
  return await sql<Array<{ name: string }>>`
    SELECT name FROM branches
    WHERE repository_id = ${repositoryId}
    ORDER BY name
  `;
}

/**
 * Get bookmarks for a repository (fallback when jj not available)
 */
export async function getBookmarks(repositoryId: number): Promise<Bookmark[]> {
  return await sql<Bookmark[]>`
    SELECT * FROM bookmarks
    WHERE repository_id = ${repositoryId}
    ORDER BY is_default DESC, updated_at DESC
  `;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Create a new repository
 */
export async function create(
  userId: number,
  name: string,
  description?: string,
  isPrivate: boolean = false
): Promise<Repository> {
  const [repo] = await sql<Repository[]>`
    INSERT INTO repositories (user_id, name, description, is_private)
    VALUES (${userId}, ${name}, ${description || null}, ${isPrivate})
    RETURNING *
  `;
  return repo;
}

/**
 * Check if repository exists
 */
export async function exists(userId: number, name: string): Promise<boolean> {
  const [result] = await sql<[{ exists: boolean }]>`
    SELECT EXISTS(
      SELECT 1 FROM repositories WHERE user_id = ${userId} AND name = ${name}
    ) as exists
  `;
  return result?.exists || false;
}

/**
 * Get repository ID from owner username and repo name
 */
export async function getIdByOwnerAndName(
  username: string,
  reponame: string
): Promise<number | null> {
  const [repository] = await sql<Array<{ id: number }>>`
    SELECT r.id
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${reponame}
  `;
  return repository?.id || null;
}
