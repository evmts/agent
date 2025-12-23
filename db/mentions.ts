/**
 * Mentions Data Access Object
 *
 * SQL operations for tracking @mentions in issues and comments.
 */

import { sql } from './client';
import { getUniqueMentionedUsernames } from '../ui/lib/mentions';

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get all users mentioned in an issue (including comments)
 */
export async function getMentionedUsersForIssue(
  repositoryId: number,
  issueNumber: number
): Promise<Array<{ id: number; username: string }>> {
  return await sql<Array<{ id: number; username: string }>>`
    SELECT DISTINCT u.id, u.username
    FROM mentions m
    JOIN users u ON u.id = m.mentioned_user_id
    WHERE m.repository_id = ${repositoryId}
      AND m.issue_number = ${issueNumber}
    ORDER BY u.username
  `;
}

/**
 * Get all mentions for a user
 */
export async function getMentionsForUser(
  userId: number,
  limit: number = 50
): Promise<Array<{
  id: number;
  repository_id: number;
  issue_number: number;
  comment_id: string | null;
  created_at: Date;
}>> {
  return await sql<Array<{
    id: number;
    repository_id: number;
    issue_number: number;
    comment_id: string | null;
    created_at: Date;
  }>>`
    SELECT id, repository_id, issue_number, comment_id, created_at
    FROM mentions
    WHERE mentioned_user_id = ${userId}
    ORDER BY created_at DESC
    LIMIT ${limit}
  `;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Save mentions from issue body to database
 */
export async function saveMentionsForIssue(
  repositoryId: number,
  issueNumber: number,
  bodyText: string
): Promise<void> {
  const usernames = getUniqueMentionedUsernames(bodyText);

  if (usernames.length === 0) {
    return;
  }

  // Fetch user IDs for mentioned usernames
  const users = await sql<Array<{ id: number; lower_username: string }>>`
    SELECT id, lower_username
    FROM users
    WHERE lower_username = ANY(${usernames})
      AND is_active = true
      AND prohibit_login = false
  `;

  if (users.length === 0) {
    return;
  }

  // Insert mentions
  for (const user of users) {
    await sql`
      INSERT INTO mentions (repository_id, issue_number, comment_id, mentioned_user_id)
      VALUES (${repositoryId}, ${issueNumber}, NULL, ${user.id})
      ON CONFLICT DO NOTHING
    `.catch(() => {
      // Ignore duplicate errors
    });
  }
}

/**
 * Save mentions from comment body to database
 */
export async function saveMentionsForComment(
  repositoryId: number,
  issueNumber: number,
  commentId: string,
  bodyText: string
): Promise<void> {
  const usernames = getUniqueMentionedUsernames(bodyText);

  if (usernames.length === 0) {
    return;
  }

  // Fetch user IDs for mentioned usernames
  const users = await sql<Array<{ id: number; lower_username: string }>>`
    SELECT id, lower_username
    FROM users
    WHERE lower_username = ANY(${usernames})
      AND is_active = true
      AND prohibit_login = false
  `;

  if (users.length === 0) {
    return;
  }

  // Insert mentions
  for (const user of users) {
    await sql`
      INSERT INTO mentions (repository_id, issue_number, comment_id, mentioned_user_id)
      VALUES (${repositoryId}, ${issueNumber}, ${commentId}, ${user.id})
      ON CONFLICT DO NOTHING
    `.catch(() => {
      // Ignore duplicate errors
    });
  }
}
