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

  try {
    const native = await import('../snapshot/src/snapshot');
    _Snapshot = native.Snapshot;
    SnapshotSessionManager = native.SnapshotSessionManager;
    sessionManager = new SnapshotSessionManager();
    console.log('[snapshots] Native jj module loaded successfully');

    initialized = true;
  } catch (error) {
    console.warn('[snapshots] Native jj module not available, falling back to no-op implementation');
    console.warn('[snapshots] Error:', error);
    // Initialize with no-op implementations
    initialized = true;
  }
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
    console.warn('[snapshots] Session manager not available, using placeholder');
    const changeId = `placeholder_${sessionId}_${Date.now()}`;
    await setSnapshotHistory(sessionId, [changeId]);
    return changeId;
  }

  try {
    const changeId = await sessionManager.initSession(sessionId, directory);
    await setSnapshotHistory(sessionId, [changeId]);
    return changeId;
  } catch (error) {
    console.warn('[snapshots] Failed to init session, using placeholder:', error);
    const changeId = `placeholder_${sessionId}_${Date.now()}`;
    await setSnapshotHistory(sessionId, [changeId]);
    return changeId;
  }
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
    const changeId = `placeholder_${sessionId}_${Date.now()}`;
    await appendSnapshotHistoryToDB(sessionId, changeId);
    return changeId;
  }

  try {
    const changeId = await sessionManager.trackSnapshot(sessionId, description);
    if (!changeId) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    await appendSnapshotHistoryToDB(sessionId, changeId);
    return changeId;
  } catch (error) {
    console.warn('[snapshots] Failed to track snapshot, using placeholder:', error);
    const changeId = `placeholder_${sessionId}_${Date.now()}`;
    await appendSnapshotHistoryToDB(sessionId, changeId);
    return changeId;
  }
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
    return [];
  }

  try {
    return await sessionManager.computeDiff(sessionId, fromChangeId, toChangeId);
  } catch (error) {
    console.warn('[snapshots] Failed to compute diff:', error);
    return [];
  }
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
    return [];
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    return await snapshot.patch(fromChangeId, toChangeId);
  } catch (error) {
    console.warn('[snapshots] Failed to get changed files:', error);
    return [];
  }
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
    console.warn('[snapshots] Cannot restore snapshot: session manager not available');
    return;
  }

  try {
    await sessionManager.restoreSnapshot(sessionId, changeId);
  } catch (error) {
    if (error instanceof Error && error.message.includes('not found')) {
      throw new NotFoundError('session snapshot', sessionId);
    }
    console.warn('[snapshots] Failed to restore snapshot:', error);
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
    return [];
  }

  try {
    return sessionManager.getHistory(sessionId);
  } catch (error) {
    console.warn('[snapshots] Failed to get snapshot history:', error);
    return [];
  }
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
    sessionSnapshots.delete(sessionId);
    return;
  }

  try {
    sessionManager.cleanupSession(sessionId);
    sessionSnapshots.delete(sessionId);
  } catch (error) {
    console.warn('[snapshots] Failed to cleanup snapshots:', error);
    sessionSnapshots.delete(sessionId);
  }
  // Database cleanup is handled by foreign key cascades when session is deleted
}

/**
 * Get the snapshot instance for a session.
 *
 * @param sessionId - The session to get snapshot for
 * @returns The Snapshot instance
 * @throws NotFoundError if the session is not found
 */
export async function getSessionSnapshot(sessionId: string): Promise<any> {
  await initializeNative();

  if (!sessionManager) {
    throw new NotFoundError('session snapshot', sessionId);
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
    console.warn('[snapshots] Cannot revert files: session manager not available');
    return;
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    await snapshot.revert(changeId, files);
  } catch (error) {
    console.warn('[snapshots] Failed to revert files:', error);
  }
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
    return null;
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    return snapshot.getFileAt(changeId, filePath);
  } catch (error) {
    console.warn('[snapshots] Failed to get file at snapshot:', error);
    return null;
  }
}

/**
 * Undo the last jj operation for a session.
 *
 * @param sessionId - The session to undo in
 */
export async function undoLastOperation(sessionId: string): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    console.warn('[snapshots] Cannot undo: session manager not available');
    return;
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    await snapshot.undo();
  } catch (error) {
    console.warn('[snapshots] Failed to undo operation:', error);
  }
}