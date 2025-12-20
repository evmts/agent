/**
 * Database operations for storing mentions
 */

import sql from "../../db/client";
import { getUniqueMentionedUsernames } from "./mentions";

/**
 * Save mentions from issue body to database
 */
export async function saveMentionsForIssue(
  issueId: number,
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
      INSERT INTO mentions (issue_id, mentioned_user_id)
      VALUES (${issueId}, ${user.id})
      ON CONFLICT DO NOTHING
    `;
  }
}

/**
 * Save mentions from comment body to database
 */
export async function saveMentionsForComment(
  commentId: number,
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
      INSERT INTO mentions (comment_id, mentioned_user_id)
      VALUES (${commentId}, ${user.id})
      ON CONFLICT DO NOTHING
    `;
  }
}

/**
 * Get all users mentioned in an issue (including comments)
 */
export async function getMentionedUsersForIssue(
  issueId: number
): Promise<Array<{ id: number; username: string }>> {
  return await sql<Array<{ id: number; username: string }>>`
    SELECT DISTINCT u.id, u.username
    FROM mentions m
    JOIN users u ON u.id = m.mentioned_user_id
    WHERE m.issue_id = ${issueId}
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
  issue_id: number | null;
  comment_id: number | null;
  created_at: Date;
}>> {
  return await sql<Array<{
    id: number;
    issue_id: number | null;
    comment_id: number | null;
    created_at: Date;
  }>>`
    SELECT id, issue_id, comment_id, created_at
    FROM mentions
    WHERE mentioned_user_id = ${userId}
    ORDER BY created_at DESC
    LIMIT ${limit}
  `;
}
