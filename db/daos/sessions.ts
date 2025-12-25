/**
 * AI Sessions Data Access Object
 *
 * SQL operations for AI agent session management.
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface AgentSession {
  id: string;
  title: string;
  directory: string;
  model: string;
  createdAt: string;
  updatedAt: string;
  archived: boolean;
  tokenCount: number | null;
}

export interface CreateSessionInput {
  id: string;
  title: string;
  directory?: string;
  model?: string;
}

// =============================================================================
// Read Operations
// =============================================================================

/**
 * List AI sessions, ordered by most recently updated
 */
export async function listSessions(limit: number = 50): Promise<AgentSession[]> {
  const sessions = await sql`
    SELECT
      id,
      title,
      directory,
      model,
      time_created as "createdAt",
      time_updated as "updatedAt",
      time_archived IS NOT NULL as archived,
      token_count as "tokenCount"
    FROM sessions
    ORDER BY time_updated DESC
    LIMIT ${limit}
  `;

  // Convert timestamps from Unix ms to ISO strings
  return sessions.map((s: any) => ({
    ...s,
    createdAt: s.createdAt ? new Date(Number(s.createdAt)).toISOString() : null,
    updatedAt: s.updatedAt ? new Date(Number(s.updatedAt)).toISOString() : null,
  }));
}

/**
 * Get a single session by ID
 */
export async function getSession(sessionId: string): Promise<AgentSession | null> {
  const [session] = await sql`
    SELECT
      id,
      title,
      directory,
      model,
      time_created as "createdAt",
      time_updated as "updatedAt",
      time_archived IS NOT NULL as archived,
      token_count as "tokenCount"
    FROM sessions
    WHERE id = ${sessionId}
  `;

  if (!session) return null;

  return {
    ...session,
    createdAt: session.createdAt ? new Date(Number(session.createdAt)).toISOString() : null,
    updatedAt: session.updatedAt ? new Date(Number(session.updatedAt)).toISOString() : null,
  } as AgentSession;
}

// =============================================================================
// Write Operations
// =============================================================================

/**
 * Create a new AI session
 */
export async function createAgentSession(input: CreateSessionInput): Promise<AgentSession> {
  const now = Date.now();

  const [session] = await sql`
    INSERT INTO sessions (
      id,
      title,
      directory,
      model,
      time_created,
      time_updated
    )
    VALUES (
      ${input.id},
      ${input.title},
      ${input.directory || '/'},
      ${input.model || 'claude-sonnet-4-20250514'},
      ${now},
      ${now}
    )
    RETURNING
      id,
      title,
      directory,
      model,
      time_created as "createdAt",
      time_updated as "updatedAt"
  `;

  return {
    ...session,
    createdAt: new Date(Number(session.createdAt)).toISOString(),
    updatedAt: new Date(Number(session.updatedAt)).toISOString(),
    archived: false,
    tokenCount: null,
  } as AgentSession;
}

/**
 * Update session (e.g., title, model)
 */
export async function updateSession(
  sessionId: string,
  updates: { title?: string; model?: string }
): Promise<AgentSession | null> {
  const now = Date.now();

  const [session] = await sql`
    UPDATE sessions
    SET
      title = COALESCE(${updates.title || null}, title),
      model = COALESCE(${updates.model || null}, model),
      time_updated = ${now}
    WHERE id = ${sessionId}
    RETURNING
      id,
      title,
      directory,
      model,
      time_created as "createdAt",
      time_updated as "updatedAt",
      time_archived IS NOT NULL as archived,
      token_count as "tokenCount"
  `;

  if (!session) return null;

  return {
    ...session,
    createdAt: new Date(Number(session.createdAt)).toISOString(),
    updatedAt: new Date(Number(session.updatedAt)).toISOString(),
  } as AgentSession;
}

/**
 * Archive a session
 */
export async function archiveSession(sessionId: string): Promise<void> {
  const now = Date.now();

  await sql`
    UPDATE sessions
    SET time_archived = ${now}, time_updated = ${now}
    WHERE id = ${sessionId}
  `;
}

/**
 * Delete a session
 */
export async function deleteSession(sessionId: string): Promise<void> {
  await sql`
    DELETE FROM sessions WHERE id = ${sessionId}
  `;
}
