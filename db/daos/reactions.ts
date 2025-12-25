/**
 * Reactions Data Access Object
 *
 * SQL operations for issue and comment reactions.
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface Reaction {
  id: number;
  user_id: number;
  target_type: 'issue' | 'comment';
  target_id: number;
  emoji: string;
  created_at: Date;
}

export interface ReactionCount {
  target_id: number;
  emoji: string;
  count: number;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get reaction counts grouped by target and emoji
 */
export async function getCountsByTargets(
  targetType: 'issue' | 'comment',
  targetIds: number[]
): Promise<ReactionCount[]> {
  if (targetIds.length === 0) {
    return [];
  }

  return await sql<ReactionCount[]>`
    SELECT target_id, emoji, COUNT(*)::int as count
    FROM reactions
    WHERE target_type = ${targetType} AND target_id = ANY(${targetIds})
    GROUP BY target_id, emoji
  `;
}

/**
 * Get all reactions for a specific target
 */
export async function getByTarget(
  targetType: 'issue' | 'comment',
  targetId: number
): Promise<Reaction[]> {
  return await sql<Reaction[]>`
    SELECT * FROM reactions
    WHERE target_type = ${targetType} AND target_id = ${targetId}
    ORDER BY created_at ASC
  `;
}

/**
 * Check if a user has reacted with a specific emoji to a target
 */
export async function hasUserReacted(
  userId: number,
  targetType: 'issue' | 'comment',
  targetId: number,
  emoji: string
): Promise<boolean> {
  const [result] = await sql<{ exists: boolean }[]>`
    SELECT EXISTS(
      SELECT 1 FROM reactions
      WHERE user_id = ${userId}
        AND target_type = ${targetType}
        AND target_id = ${targetId}
        AND emoji = ${emoji}
    ) as exists
  `;
  return result?.exists || false;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Add a reaction (idempotent - uses UNIQUE constraint)
 */
export async function add(
  userId: number,
  targetType: 'issue' | 'comment',
  targetId: number,
  emoji: string
): Promise<Reaction | null> {
  const [reaction] = await sql<Reaction[]>`
    INSERT INTO reactions (user_id, target_type, target_id, emoji)
    VALUES (${userId}, ${targetType}, ${targetId}, ${emoji})
    ON CONFLICT (user_id, target_type, target_id, emoji) DO NOTHING
    RETURNING *
  `;
  return reaction || null;
}

/**
 * Remove a reaction
 */
export async function remove(
  userId: number,
  targetType: 'issue' | 'comment',
  targetId: number,
  emoji: string
): Promise<void> {
  await sql`
    DELETE FROM reactions
    WHERE user_id = ${userId}
      AND target_type = ${targetType}
      AND target_id = ${targetId}
      AND emoji = ${emoji}
  `;
}

/**
 * Remove all reactions for a target
 */
export async function removeAllForTarget(
  targetType: 'issue' | 'comment',
  targetId: number
): Promise<void> {
  await sql`
    DELETE FROM reactions
    WHERE target_type = ${targetType} AND target_id = ${targetId}
  `;
}

// =============================================================================
// Queries with user info (for UI display)
// =============================================================================

export interface ReactionWithUser {
  user_id: number;
  username: string;
  emoji: string;
}

export interface ReactionWithUserAndTarget extends ReactionWithUser {
  target_id: string;
}

/**
 * Get reactions for an issue with username
 */
export async function getForIssueWithUser(
  issueNumber: number
): Promise<ReactionWithUser[]> {
  return await sql<ReactionWithUser[]>`
    SELECT r.user_id, u.username, r.emoji
    FROM reactions r
    JOIN users u ON r.user_id = u.id
    WHERE r.target_type = 'issue'
      AND r.target_id = ${issueNumber}
    ORDER BY r.created_at ASC
  `;
}

/**
 * Get reactions for multiple comments with username
 */
export async function getForCommentsWithUser(
  commentIds: number[]
): Promise<Map<number, ReactionWithUser[]>> {
  if (commentIds.length === 0) {
    return new Map();
  }
  const reactions = await sql<ReactionWithUserAndTarget[]>`
    SELECT r.target_id, r.user_id, u.username, r.emoji
    FROM reactions r
    JOIN users u ON r.user_id = u.id
    WHERE r.target_type = 'comment'
      AND r.target_id = ANY(${commentIds})
    ORDER BY r.created_at ASC
  `;

  const map = new Map<number, ReactionWithUser[]>();
  for (const r of reactions) {
    const key = Number(r.target_id);
    if (!map.has(key)) {
      map.set(key, []);
    }
    map.get(key)!.push({
      user_id: r.user_id,
      username: r.username,
      emoji: r.emoji,
    });
  }
  return map;
}
