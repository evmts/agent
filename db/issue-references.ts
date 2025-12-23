/**
 * Issue References Data Access Object
 *
 * SQL operations for tracking cross-references between issues.
 */

import { sql } from './client';
import { parseReferences } from './references';

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get all issues that reference this issue
 */
export async function getReferencingIssues(issueId: number) {
  return await sql`
    SELECT
      i.id,
      i.repository_id,
      i.author_id,
      i.issue_number,
      i.title,
      i.state,
      i.created_at,
      u.username as author_username,
      r.name as repository_name,
      owner.username as repository_owner
    FROM issue_references ir
    JOIN issues i ON ir.source_issue_id = i.id
    JOIN users u ON i.author_id = u.id
    JOIN repositories r ON i.repository_id = r.id
    JOIN users owner ON r.user_id = owner.id
    WHERE ir.target_issue_id = ${issueId}
    ORDER BY ir.created_at DESC
  `;
}

/**
 * Get all issues referenced by this issue
 */
export async function getReferencedIssues(issueId: number) {
  return await sql`
    SELECT
      i.id,
      i.repository_id,
      i.author_id,
      i.issue_number,
      i.title,
      i.state,
      i.created_at,
      u.username as author_username,
      r.name as repository_name,
      owner.username as repository_owner
    FROM issue_references ir
    JOIN issues i ON ir.target_issue_id = i.id
    JOIN users u ON i.author_id = u.id
    JOIN repositories r ON i.repository_id = r.id
    JOIN users owner ON r.user_id = owner.id
    WHERE ir.source_issue_id = ${issueId}
    ORDER BY ir.created_at DESC
  `;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Parse and store references from issue body
 */
export async function trackIssueReferences(
  sourceIssueId: number,
  text: string,
  currentOwner: string,
  currentRepo: string
): Promise<void> {
  const references = parseReferences(text, currentOwner, currentRepo);

  // Filter out references that don't have owner/repo (can't resolve them yet)
  const resolvedRefs = references.filter(ref => ref.owner && ref.repo);

  // For each reference, try to find the target issue and create a reference
  for (const ref of resolvedRefs) {
    if (!ref.owner || !ref.repo) continue;

    try {
      // Find the target issue by repository and issue number
      const [targetIssue] = await sql`
        SELECT i.id
        FROM issues i
        JOIN repositories r ON i.repository_id = r.id
        JOIN users u ON r.user_id = u.id
        WHERE u.username = ${ref.owner}
          AND r.name = ${ref.repo}
          AND i.issue_number = ${ref.number}
      `;

      if (targetIssue) {
        // Insert reference (ON CONFLICT DO NOTHING handles duplicates)
        await sql`
          INSERT INTO issue_references (source_issue_id, target_issue_id)
          VALUES (${sourceIssueId}, ${targetIssue.id})
          ON CONFLICT (source_issue_id, target_issue_id) DO NOTHING
        `;
      }
    } catch (error) {
      // Silently ignore errors (target issue might not exist yet)
      console.error(`Failed to track reference to ${ref.owner}/${ref.repo}#${ref.number}:`, error);
    }
  }
}

/**
 * Parse and store references from comment body
 */
export async function trackCommentReferences(
  commentId: number,
  text: string,
  currentOwner: string,
  currentRepo: string
): Promise<void> {
  const references = parseReferences(text, currentOwner, currentRepo);

  // Filter out references that don't have owner/repo
  const resolvedRefs = references.filter(ref => ref.owner && ref.repo);

  for (const ref of resolvedRefs) {
    if (!ref.owner || !ref.repo) continue;

    try {
      // Find the target issue
      const [targetIssue] = await sql`
        SELECT i.id
        FROM issues i
        JOIN repositories r ON i.repository_id = r.id
        JOIN users u ON r.user_id = u.id
        WHERE u.username = ${ref.owner}
          AND r.name = ${ref.repo}
          AND i.issue_number = ${ref.number}
      `;

      if (targetIssue) {
        // Insert reference
        await sql`
          INSERT INTO comment_references (comment_id, target_issue_id)
          VALUES (${commentId}, ${targetIssue.id})
          ON CONFLICT (comment_id, target_issue_id) DO NOTHING
        `;
      }
    } catch (error) {
      console.error(`Failed to track reference to ${ref.owner}/${ref.repo}#${ref.number}:`, error);
    }
  }
}

// =============================================================================
// Delete Operations
// =============================================================================

/**
 * Delete all references from a comment (when comment is deleted)
 */
export async function deleteCommentReferences(commentId: number): Promise<void> {
  await sql`
    DELETE FROM comment_references
    WHERE comment_id = ${commentId}
  `;
}

/**
 * Delete all references to/from an issue (when issue is deleted)
 */
export async function deleteIssueReferences(issueId: number): Promise<void> {
  await sql`
    DELETE FROM issue_references
    WHERE source_issue_id = ${issueId} OR target_issue_id = ${issueId}
  `;
}
