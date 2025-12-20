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
// Snapshot Instance Interface
// =============================================================================

/**
 * Interface for Snapshot instances from the native jj module.
 * This describes the shape of the Snapshot class without importing it
 * to avoid circular dependencies.
 */
export interface SnapshotInstance {
  track(description?: string): Promise<string>;
  current(): Promise<string>;
  patch(fromChangeId: string, toChangeId?: string): Promise<string[]>;
  diff(fromChangeId: string, toChangeId?: string): Promise<FileDiff[]>;
  revert(changeId: string, files: string[]): Promise<void>;
  restore(changeId: string): Promise<void>;
  getFileAt(changeId: string, filePath: string): Promise<string | null>;
  listFilesAt(changeId: string): Promise<string[]>;
  fileExistsAt(changeId: string, filePath: string): Promise<boolean>;
  getSnapshot(changeId: string): Promise<SnapshotInfo>;
  listSnapshots(limit?: number): Promise<SnapshotInfo[]>;
  undo(): Promise<void>;
  getOperationLog(limit?: number): Promise<OperationInfo[]>;
  restoreOperation(operationId: string): Promise<void>;
}

export interface FileDiff {
  path: string;
  changeType: 'added' | 'modified' | 'deleted';
  beforeContent?: string;
  afterContent?: string;
  addedLines: number;
  deletedLines: number;
}

export interface SnapshotInfo {
  changeId: string;
  commitId: string;
  description: string;
  timestamp: number;
  isEmpty: boolean;
}

export interface OperationInfo {
  id: string;
  description: string;
  timestamp: number;
}

// =============================================================================
// Runtime-Only State (In-Memory)
// =============================================================================

/** Active tasks: sessionID -> AbortController for cancellation */
export const activeTasks = new Map<string, AbortController>();

/** Session snapshots: sessionID -> Snapshot instance (native, runtime-only) */
export const sessionSnapshots = new Map<string, SnapshotInstance>();

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
 * Clear runtime-only state for a session (in-memory Maps).
 * This is separated for testability - can be tested without database mocking.
 */
export function clearRuntimeState(sessionId: string): void {
  const task = activeTasks.get(sessionId);
  if (task) {
    task.abort();
    activeTasks.delete(sessionId);
  }
  sessionSnapshots.delete(sessionId);
}

/**
 * Clear all state for a session (both runtime and database).
 */
export async function clearSessionState(sessionId: string): Promise<void> {
  // Clear runtime state
  clearRuntimeState(sessionId);

  // Clear database state
  await db.clearSessionState(sessionId);
}
