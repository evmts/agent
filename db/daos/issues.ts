/**
 * Issues Data Access Object
 *
 * SQL operations for issues.
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface Issue {
  id: number;
  repository_id: number;
  author_id: number;
  issue_number: number;
  title: string;
  body: string | null;
  state: 'open' | 'closed';
  milestone_id: number | null;
  created_at: Date;
  updated_at: Date;
  closed_at: Date | null;
  // Joined fields
  author_username?: string;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get issues for a milestone with author information
 */
export async function getByMilestone(
  milestoneId: number,
  state?: 'open' | 'closed' | 'all'
): Promise<Issue[]> {
  if (!state || state === 'all') {
    return await sql<Issue[]>`
      SELECT i.*, u.username as author_username
      FROM issues i
      JOIN users u ON i.author_id = u.id
      WHERE i.milestone_id = ${milestoneId}
      ORDER BY i.created_at DESC
    `;
  }
  return await sql<Issue[]>`
    SELECT i.*, u.username as author_username
    FROM issues i
    JOIN users u ON i.author_id = u.id
    WHERE i.milestone_id = ${milestoneId} AND i.state = ${state}
    ORDER BY i.created_at DESC
  `;
}

/**
 * Count issues by state for a repository
 */
export async function countByState(
  repositoryId: number,
  state: 'open' | 'closed'
): Promise<number> {
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count
    FROM issues
    WHERE repository_id = ${repositoryId} AND state = ${state}
  `;
  return result?.count || 0;
}
