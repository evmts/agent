/**
 * Snapshot operations for file state tracking.
 *
 * Provides functions for tracking file changes using the jj-based snapshot system.
 * This wraps the snapshot/src/snapshot.ts module for session-based management.
 */

import {
  sessionSnapshots,
  appendSnapshotHistory as appendSnapshotHistoryToDB,
  setSnapshotHistory,
} from './state';
import { NotFoundError } from './exceptions';

// Types (defined locally to avoid native dependency)
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

// Module state
type SnapshotClass = typeof import('../snapshot/src/snapshot').Snapshot;
type SnapshotSessionManagerClass = typeof import('../snapshot/src/snapshot').SnapshotSessionManager;
type SnapshotSessionManagerInstance = InstanceType<SnapshotSessionManagerClass>;

let _Snapshot: SnapshotClass | null = null;
let SnapshotSessionManager: SnapshotSessionManagerClass | null = null;
let initialized = false;

// Global session manager instance
let sessionManager: SnapshotSessionManagerInstance | null = null;

/**
 * Initialize the native snapshot module lazily.
 * Throws if the native module is not available.
 */
async function initializeNative(): Promise<void> {
  if (initialized) return;

  const native = await import('../snapshot/src/snapshot');
  _Snapshot = native.Snapshot;
  SnapshotSessionManager = native.SnapshotSessionManager;
  sessionManager = new SnapshotSessionManager();
  console.log('[snapshots] Native jj module loaded successfully');

  initialized = true;
}

/**
 * Initialize snapshot tracking for a session.
 *
 * @param sessionId - The session to initialize snapshots for
 * @param directory - The directory to track
 * @returns The initial snapshot change ID
 */
export async function initSnapshot(
  sessionId: string,
  directory: string
): Promise<string> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  const changeId = await sessionManager.initSession(sessionId, directory);
  await setSnapshotHistory(sessionId, [changeId]);
  return changeId;
}

/**
 * Capture the current file state for a session.
 *
 * @param sessionId - The session to track
 * @param description - Optional description for the snapshot
 * @returns The snapshot change ID
 * @throws NotFoundError if the session is not found
 */
export async function trackSnapshot(
  sessionId: string,
  description?: string
): Promise<string> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  const changeId = await sessionManager.trackSnapshot(sessionId, description);
  if (!changeId) {
    throw new NotFoundError('session snapshot', sessionId);
  }

  await appendSnapshotHistoryToDB(sessionId, changeId);
  return changeId;
}

/**
 * Compute file diffs between two snapshots.
 *
 * @param sessionId - The session to compute diffs for
 * @param fromChangeId - The starting snapshot change ID
 * @param toChangeId - The ending snapshot change ID (optional, defaults to working copy)
 * @returns List of file diffs
 */
export async function computeDiff(
  sessionId: string,
  fromChangeId: string,
  toChangeId?: string
): Promise<FileDiff[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  return await sessionManager.computeDiff(sessionId, fromChangeId, toChangeId);
}

/**
 * Get list of files changed between two snapshots.
 *
 * @param sessionId - The session to check
 * @param fromChangeId - The starting snapshot change ID
 * @param toChangeId - The ending snapshot change ID (optional)
 * @returns List of changed file paths
 */
export async function getChangedFiles(
  sessionId: string,
  fromChangeId: string,
  toChangeId?: string
): Promise<string[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  const snapshot = sessionManager.getSession(sessionId);
  if (!snapshot) {
    throw new NotFoundError('session snapshot', sessionId);
  }

  return await snapshot.patch(fromChangeId, toChangeId);
}

/**
 * Restore files to a previous snapshot state.
 *
 * @param sessionId - The session to restore
 * @param changeId - The snapshot change ID to restore to
 * @throws NotFoundError if the session is not found
 */
export async function restoreSnapshot(
  sessionId: string,
  changeId: string
): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  try {
    await sessionManager.restoreSnapshot(sessionId, changeId);
  } catch (error) {
    if (error instanceof Error && error.message.includes('not found')) {
      throw new NotFoundError('session snapshot', sessionId);
    }
    throw error;
  }
}

/**
 * Get the snapshot history for a session.
 *
 * @param sessionId - The session to get history for
 * @returns Array of change IDs in order
 */
export async function getSnapshotHistory(sessionId: string): Promise<string[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  return sessionManager.getHistory(sessionId);
}

/**
 * Append a snapshot change ID to the session's history.
 *
 * @param sessionId - The session to update
 * @param changeId - The change ID to append
 */
export async function appendSnapshotHistory(sessionId: string, changeId: string): Promise<void> {
  await appendSnapshotHistoryToDB(sessionId, changeId);
}

/**
 * Clean up snapshot resources for a session.
 *
 * @param sessionId - The session to clean up
 */
export async function cleanupSnapshots(sessionId: string): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  sessionManager.cleanupSession(sessionId);
  sessionSnapshots.delete(sessionId);
  // Database cleanup is handled by foreign key cascades when session is deleted
}

/**
 * Get the snapshot instance for a session.
 *
 * @param sessionId - The session to get snapshot for
 * @returns The Snapshot instance
 * @throws NotFoundError if the session is not found
 */
export async function getSessionSnapshot(sessionId: string): Promise<Awaited<ReturnType<NonNullable<typeof sessionManager>['getSession']>>> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  const snapshot = sessionManager.getSession(sessionId);
  if (!snapshot) {
    throw new NotFoundError('session snapshot', sessionId);
  }

  return snapshot;
}

/**
 * Revert specific files from a snapshot.
 *
 * @param sessionId - The session to revert files in
 * @param changeId - The snapshot change ID to revert from
 * @param files - Array of file paths to revert
 */
export async function revertFiles(
  sessionId: string,
  changeId: string,
  files: string[]
): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  const snapshot = sessionManager.getSession(sessionId);
  if (!snapshot) {
    throw new NotFoundError('session snapshot', sessionId);
  }

  await snapshot.revert(changeId, files);
}

/**
 * Get file contents at a specific snapshot.
 *
 * @param sessionId - The session to get file from
 * @param changeId - The snapshot change ID
 * @param filePath - The file path
 * @returns The file contents
 * @throws NotFoundError if the session is not found
 */
export async function getFileAtSnapshot(
  sessionId: string,
  changeId: string,
  filePath: string
): Promise<string | null> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  const snapshot = sessionManager.getSession(sessionId);
  if (!snapshot) {
    throw new NotFoundError('session snapshot', sessionId);
  }

  return snapshot.getFileAt(changeId, filePath);
}

/**
 * Undo the last jj operation for a session.
 *
 * @param sessionId - The session to undo in
 */
export async function undoLastOperation(sessionId: string): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    throw new Error('[snapshots] Session manager not initialized');
  }

  const snapshot = sessionManager.getSession(sessionId);
  if (!snapshot) {
    throw new NotFoundError('session snapshot', sessionId);
  }

  await snapshot.undo();
}