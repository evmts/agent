/**
 * Issue Events Data Access Object
 *
 * SQL operations for tracking issue activity timeline (state changes, labels, etc.)
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export type IssueEventType =
  | 'closed'
  | 'reopened'
  | 'label_added'
  | 'label_removed'
  | 'assignee_added'
  | 'assignee_removed'
  | 'milestone_added'
  | 'milestone_removed'
  | 'milestone_changed'
  | 'title_changed'
  | 'renamed';

export interface IssueEvent {
  id: number;
  repository_id: number;
  issue_number: number;
  actor_id: number | null;
  actor_username: string | null;
  event_type: IssueEventType;
  metadata: Record<string, unknown>;
  created_at: Date;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * Get all events for an issue
 */
export async function getEventsForIssue(
  repositoryId: number,
  issueNumber: number
): Promise<IssueEvent[]> {
  const events = await sql<Array<{
    id: number;
    repository_id: number;
    issue_number: number;
    actor_id: number | null;
    actor_username: string | undefined;
    event_type: IssueEventType;
    metadata: Record<string, unknown>;
    created_at: Date;
  }>>`
    SELECT
      e.id,
      e.repository_id,
      e.issue_number,
      e.actor_id,
      u.username as actor_username,
      e.event_type,
      e.metadata,
      e.created_at
    FROM issue_events e
    LEFT JOIN users u ON e.actor_id = u.id
    WHERE e.repository_id = ${repositoryId} AND e.issue_number = ${issueNumber}
    ORDER BY e.created_at ASC
  `;

  // Convert undefined to null for actor_username
  return events.map(event => ({
    ...event,
    actor_username: event.actor_username ?? null,
  }));
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Record an issue event in the activity timeline
 */
export async function recordEvent(
  repositoryId: number,
  issueNumber: number,
  eventType: IssueEventType,
  actorId: number | null,
  metadata: Record<string, unknown> = {}
): Promise<void> {
  await sql`
    INSERT INTO issue_events (repository_id, issue_number, actor_id, event_type, metadata)
    VALUES (${repositoryId}, ${issueNumber}, ${actorId}, ${eventType}, ${JSON.stringify(metadata)})
  `;
}
