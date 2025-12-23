/**
 * Landing Queue Data Access Object
 *
 * SQL operations for landing_queue, landing_reviews, and landing_line_comments tables.
 */

import { sql } from './client';

// =============================================================================
// Types
// =============================================================================

export interface LandingRequest {
  id: number;
  repositoryId: number;
  changeId: string;
  targetBookmark: string;
  title: string | null;
  description: string | null;
  authorId: number;
  status: 'pending' | 'reviewing' | 'approved' | 'landed' | 'cancelled' | 'conflicted';
  hasConflicts: boolean;
  conflictedFiles: string[] | null;
  createdAt: string;
  updatedAt: string;
  landedAt: string | null;
  landedBy: number | null;
  landedChangeId: string | null;
}

export interface LineComment {
  id: number;
  landingId: number;
  authorId: number;
  filePath: string;
  lineNumber: number;
  side: 'left' | 'right';
  body: string;
  resolved: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface LandingReview {
  id: number;
  landingId: number;
  reviewerId: number;
  reviewType: 'approve' | 'request_changes' | 'comment';
  content: string | null;
  changeId: string;
  createdAt: string;
}

// =============================================================================
// Helper Functions
// =============================================================================

function mapLandingRow(row: any): LandingRequest {
  return {
    id: Number(row.id),
    repositoryId: Number(row.repository_id),
    changeId: row.change_id,
    targetBookmark: row.target_bookmark,
    title: row.title,
    description: row.description,
    authorId: Number(row.author_id),
    status: row.status,
    hasConflicts: row.has_conflicts,
    conflictedFiles: row.conflicted_files,
    createdAt: row.created_at ? new Date(Number(row.created_at)).toISOString() : new Date().toISOString(),
    updatedAt: row.updated_at ? new Date(Number(row.updated_at)).toISOString() : new Date().toISOString(),
    landedAt: row.landed_at ? new Date(Number(row.landed_at)).toISOString() : null,
    landedBy: row.landed_by ? Number(row.landed_by) : null,
    landedChangeId: row.landed_change_id,
  };
}

function mapLineCommentRow(row: any): LineComment {
  return {
    id: Number(row.id),
    landingId: Number(row.landing_id),
    authorId: Number(row.author_id),
    filePath: row.file_path,
    lineNumber: Number(row.line_number),
    side: row.side,
    body: row.body,
    resolved: row.resolved,
    createdAt: row.created_at ? new Date(Number(row.created_at)).toISOString() : new Date().toISOString(),
    updatedAt: row.updated_at ? new Date(Number(row.updated_at)).toISOString() : new Date().toISOString(),
  };
}

function mapReviewRow(row: any): LandingReview {
  return {
    id: Number(row.id),
    landingId: Number(row.landing_id),
    reviewerId: Number(row.reviewer_id),
    reviewType: row.review_type,
    content: row.content,
    changeId: row.change_id,
    createdAt: row.created_at ? new Date(Number(row.created_at)).toISOString() : new Date().toISOString(),
  };
}

// =============================================================================
// Landing Request Operations
// =============================================================================

export async function list(
  repositoryId: number,
  statusFilter?: string,
  limit: number = 50,
  offset: number = 0
): Promise<LandingRequest[]> {
  const rows = statusFilter
    ? await sql`
        SELECT id, repository_id, change_id, target_bookmark, title, description,
               author_id, status, has_conflicts, conflicted_files,
               EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
               EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
               EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
               landed_by, landed_change_id
        FROM landing_queue
        WHERE repository_id = ${repositoryId} AND status = ${statusFilter}
        ORDER BY created_at DESC
        LIMIT ${limit} OFFSET ${offset}
      `
    : await sql`
        SELECT id, repository_id, change_id, target_bookmark, title, description,
               author_id, status, has_conflicts, conflicted_files,
               EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
               EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
               EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
               landed_by, landed_change_id
        FROM landing_queue
        WHERE repository_id = ${repositoryId}
        ORDER BY created_at DESC
        LIMIT ${limit} OFFSET ${offset}
      `;

  return rows.map(mapLandingRow);
}

export async function getById(
  repositoryId: number,
  landingId: number
): Promise<LandingRequest | null> {
  const [row] = await sql`
    SELECT id, repository_id, change_id, target_bookmark, title, description,
           author_id, status, has_conflicts, conflicted_files,
           EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
           EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
           EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
           landed_by, landed_change_id
    FROM landing_queue
    WHERE repository_id = ${repositoryId} AND id = ${landingId}
  `;

  return row ? mapLandingRow(row) : null;
}

export async function findByChangeId(
  repositoryId: number,
  changeId: string
): Promise<LandingRequest | null> {
  const [row] = await sql`
    SELECT id, repository_id, change_id, target_bookmark, title, description,
           author_id, status, has_conflicts, conflicted_files,
           EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
           EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
           EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
           landed_by, landed_change_id
    FROM landing_queue
    WHERE repository_id = ${repositoryId} AND change_id = ${changeId}
      AND status NOT IN ('landed', 'cancelled')
  `;

  return row ? mapLandingRow(row) : null;
}

export async function count(
  repositoryId: number,
  statusFilter?: string
): Promise<number> {
  const [row] = statusFilter
    ? await sql`
        SELECT COUNT(*) as count FROM landing_queue
        WHERE repository_id = ${repositoryId} AND status = ${statusFilter}
      `
    : await sql`
        SELECT COUNT(*) as count FROM landing_queue
        WHERE repository_id = ${repositoryId}
      `;

  return Number(row?.count || 0);
}

export async function create(
  repositoryId: number,
  changeId: string,
  targetBookmark: string,
  authorId: number,
  title?: string,
  description?: string
): Promise<LandingRequest> {
  const [row] = await sql`
    INSERT INTO landing_queue (repository_id, change_id, target_bookmark, title, description, author_id, status)
    VALUES (${repositoryId}, ${changeId}, ${targetBookmark}, ${title || null}, ${description || null}, ${authorId}, 'pending')
    RETURNING id, repository_id, change_id, target_bookmark, title, description,
              author_id, status, has_conflicts, conflicted_files,
              EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
              EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
              EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
              landed_by, landed_change_id
  `;

  return mapLandingRow(row);
}

export async function updateStatus(
  landingId: number,
  status: LandingRequest['status']
): Promise<void> {
  await sql`
    UPDATE landing_queue SET status = ${status}, updated_at = NOW()
    WHERE id = ${landingId}
  `;
}

export async function updateConflicts(
  landingId: number,
  hasConflicts: boolean,
  conflictedFiles: string[]
): Promise<void> {
  await sql`
    UPDATE landing_queue
    SET has_conflicts = ${hasConflicts}, conflicted_files = ${JSON.stringify(conflictedFiles)}::jsonb, updated_at = NOW()
    WHERE id = ${landingId}
  `;
}

export async function markLanded(
  landingId: number,
  landedBy: number,
  landedChangeId: string
): Promise<void> {
  await sql`
    UPDATE landing_queue
    SET status = 'landed', landed_at = NOW(), landed_by = ${landedBy}, landed_change_id = ${landedChangeId}, updated_at = NOW()
    WHERE id = ${landingId}
  `;
}

// =============================================================================
// Line Comment Operations
// =============================================================================

export async function getLineComments(landingId: number): Promise<LineComment[]> {
  const rows = await sql`
    SELECT id, landing_id, author_id, file_path, line_number, side, body, resolved,
           EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
           EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
    FROM landing_line_comments
    WHERE landing_id = ${landingId}
    ORDER BY created_at ASC
  `;

  return rows.map(mapLineCommentRow);
}

export async function getLineCommentById(commentId: number): Promise<LineComment | null> {
  const [row] = await sql`
    SELECT id, landing_id, author_id, file_path, line_number, side, body, resolved,
           EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
           EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
    FROM landing_line_comments
    WHERE id = ${commentId}
  `;

  return row ? mapLineCommentRow(row) : null;
}

export async function createLineComment(
  landingId: number,
  authorId: number,
  filePath: string,
  lineNumber: number,
  side: 'left' | 'right',
  body: string
): Promise<LineComment> {
  const [row] = await sql`
    INSERT INTO landing_line_comments (landing_id, author_id, file_path, line_number, side, body)
    VALUES (${landingId}, ${authorId}, ${filePath}, ${lineNumber}, ${side}, ${body})
    RETURNING id, landing_id, author_id, file_path, line_number, side, body, resolved,
              EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
              EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
  `;

  return mapLineCommentRow(row);
}

export async function updateLineComment(
  commentId: number,
  body?: string,
  resolved?: boolean
): Promise<LineComment | null> {
  if (body !== undefined) {
    await sql`UPDATE landing_line_comments SET body = ${body}, updated_at = NOW() WHERE id = ${commentId}`;
  }
  if (resolved !== undefined) {
    await sql`UPDATE landing_line_comments SET resolved = ${resolved}, updated_at = NOW() WHERE id = ${commentId}`;
  }

  return getLineCommentById(commentId);
}

export async function deleteLineComment(commentId: number): Promise<void> {
  await sql`DELETE FROM landing_line_comments WHERE id = ${commentId}`;
}

// =============================================================================
// Review Operations
// =============================================================================

export async function getReviews(landingId: number): Promise<LandingReview[]> {
  const rows = await sql`
    SELECT id, landing_id, reviewer_id, review_type, content, change_id,
           EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at
    FROM landing_reviews
    WHERE landing_id = ${landingId}
    ORDER BY created_at ASC
  `;

  return rows.map(mapReviewRow);
}

export async function createReview(
  landingId: number,
  reviewerId: number,
  reviewType: LandingReview['reviewType'],
  changeId: string,
  content?: string
): Promise<LandingReview> {
  const [row] = await sql`
    INSERT INTO landing_reviews (landing_id, reviewer_id, review_type, content, change_id)
    VALUES (${landingId}, ${reviewerId}, ${reviewType}, ${content || null}, ${changeId})
    RETURNING id, landing_id, reviewer_id, review_type, content, change_id,
              EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at
  `;

  return mapReviewRow(row);
}
