/**
 * State storage backed by PostgreSQL.
 *
 * This module provides the interface for session state management.
 * Persistent state (sessions, messages, snapshots) is stored in the database.
 * Runtime-only state (active tasks, abort controllers) remains in-memory.
 */

import * as db from '../db/agent-state';

// =============================================================================
// Re-export Types from Database Module
// =============================================================================

export type { MessageWithParts, FileTimeTracker } from '../db/agent-state';

// =============================================================================
// Runtime-Only State (In-Memory)
// =============================================================================

/** Active tasks: sessionID -> AbortController for cancellation */
export const activeTasks = new Map<string, AbortController>();

/** Session snapshots: sessionID -> Snapshot instance (native, runtime-only) */
export const sessionSnapshots = new Map<string, any>();

// =============================================================================
// Session Operations (Database-Backed)
// =============================================================================

export const getSession = db.getSession;
export const getAllSessions = db.getAllSessions;
export const saveSession = db.saveSession;
export const deleteSessionFromDB = db.deleteSession;

// =============================================================================
// Message Operations (Database-Backed)
// =============================================================================

export const getSessionMessages = db.getSessionMessages;
export const appendSessionMessage = db.appendMessage;
export const setSessionMessages = db.setSessionMessages;

// =============================================================================
// Snapshot History Operations (Database-Backed)
// =============================================================================

export const getSnapshotHistory = db.getSnapshotHistory;
export const setSnapshotHistory = db.setSnapshotHistory;
export const appendSnapshotHistory = db.appendSnapshotHistory;

// =============================================================================
// Subtask Operations (Database-Backed)
// =============================================================================

export const getSubtasks = db.getSubtasks;
export const appendSubtask = db.appendSubtask;
export const clearSubtasks = db.clearSubtasks;

// =============================================================================
// File Tracker Operations (Database-Backed)
// =============================================================================

export const getFileTracker = db.getFileTracker;
export const updateFileTracker = db.updateFileTracker;
export const clearFileTrackers = db.clearFileTrackers;

// =============================================================================
// Cleanup Operations
// =============================================================================

/**
 * Clear all state for a session.
 */
export async function clearSessionState(sessionId: string): Promise<void> {
  // Clear runtime state
  activeTasks.get(sessionId)?.abort();
  activeTasks.delete(sessionId);
  sessionSnapshots.delete(sessionId);

  // Clear database state
  await db.clearSessionState(sessionId);
}
