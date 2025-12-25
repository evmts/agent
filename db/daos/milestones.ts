/**
 * Milestones Data Access Object
 *
 * SQL operations for repository milestones.
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface Milestone {
  id: number;
  repository_id: number;
  title: string;
  description: string | null;
  state: 'open' | 'closed';
  due_date: Date | null;
  created_at: Date;
  updated_at: Date;
  open_issues?: number;
  closed_issues?: number;
}

export interface MilestoneCounts {
  open: number;
  closed: number;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get milestone by ID
 */
export async function getById(id: number): Promise<Milestone | null> {
  const [milestone] = await sql<Milestone[]>`
    SELECT m.*,
      (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open')::int as open_issues,
      (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed')::int as closed_issues
    FROM milestones m
    WHERE m.id = ${id}
  `;
  return milestone || null;
}

/**
 * List milestones for a repository with issue counts
 */
export async function list(
  repositoryId: number,
  state?: 'open' | 'closed' | 'all'
): Promise<Milestone[]> {
  if (!state || state === 'all') {
    return await sql<Milestone[]>`
      SELECT m.*,
        (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open')::int as open_issues,
        (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed')::int as closed_issues
      FROM milestones m
      WHERE m.repository_id = ${repositoryId}
      ORDER BY m.due_date ASC NULLS LAST, m.created_at DESC
    `;
  }
  return await sql<Milestone[]>`
    SELECT m.*,
      (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open')::int as open_issues,
      (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed')::int as closed_issues
    FROM milestones m
    WHERE m.repository_id = ${repositoryId} AND m.state = ${state}
    ORDER BY m.due_date ASC NULLS LAST, m.created_at DESC
  `;
}

/**
 * List open milestones for filtering (lightweight query without issue counts)
 */
export async function listOpenForFiltering(
  repositoryId: number
): Promise<Array<{ id: number; title: string }>> {
  return await sql<Array<{ id: number; title: string }>>`
    SELECT id, title
    FROM milestones
    WHERE repository_id = ${repositoryId} AND state = 'open'
    ORDER BY due_date ASC NULLS LAST, title ASC
  `;
}

/**
 * Count milestones by state
 */
export async function countByState(repositoryId: number): Promise<MilestoneCounts> {
  const [result] = await sql<MilestoneCounts[]>`
    SELECT
      COUNT(*) FILTER (WHERE state = 'open')::int as open,
      COUNT(*) FILTER (WHERE state = 'closed')::int as closed
    FROM milestones
    WHERE repository_id = ${repositoryId}
  `;
  return result || { open: 0, closed: 0 };
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Create a new milestone
 */
export async function create(
  repositoryId: number,
  title: string,
  description?: string,
  dueDate?: string
): Promise<Milestone> {
  const [milestone] = await sql<Milestone[]>`
    INSERT INTO milestones (repository_id, title, description, due_date)
    VALUES (${repositoryId}, ${title}, ${description || null}, ${dueDate || null})
    RETURNING *
  `;
  return milestone;
}

/**
 * Update a milestone
 */
export async function update(
  id: number,
  updates: { title?: string; description?: string; due_date?: string | null; state?: 'open' | 'closed' }
): Promise<Milestone | null> {
  const [milestone] = await sql<Milestone[]>`
    UPDATE milestones SET
      title = COALESCE(${updates.title ?? null}, title),
      description = COALESCE(${updates.description ?? null}, description),
      due_date = COALESCE(${updates.due_date ?? null}, due_date),
      state = COALESCE(${updates.state ?? null}, state),
      updated_at = NOW()
    WHERE id = ${id}
    RETURNING *
  `;
  return milestone || null;
}

/**
 * Close a milestone
 */
export async function close(id: number): Promise<void> {
  await sql`
    UPDATE milestones SET state = 'closed', updated_at = NOW()
    WHERE id = ${id}
  `;
}

/**
 * Reopen a milestone
 */
export async function reopen(id: number): Promise<void> {
  await sql`
    UPDATE milestones SET state = 'open', updated_at = NOW()
    WHERE id = ${id}
  `;
}

/**
 * Delete a milestone
 */
export async function remove(id: number): Promise<void> {
  await sql`DELETE FROM milestones WHERE id = ${id}`;
}
