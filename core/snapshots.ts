/**
 * Snapshot operations for file state tracking.
 *
 * Provides functions for tracking file changes using the jj-based snapshot system.
 * This wraps the native/src/snapshot.ts module for session-based management.
 */

import {
  Snapshot,
  SnapshotSessionManager,
  type FileDiff,
  type SnapshotInfo,
} from '../native/src/snapshot';
import {
  sessionSnapshots,
  appendSnapshotHistory as appendSnapshotHistoryToDB,
  setSnapshotHistory,
} from './state';
import { NotFoundError } from './exceptions';

// Re-export types for convenience
export type { FileDiff, SnapshotInfo };

// Global session manager instance
const sessionManager = new SnapshotSessionManager();

/**
 * Initialize snapshot tracking for a session.
 *
 * @param sessionId - The session to initialize snapshots for
 * @param directory - The directory to track
 * @returns The initial snapshot change ID, or null if initialization failed
 */
export async function initSnapshot(
  sessionId: string,
  directory: string
): Promise<string | null> {
  try {
    const changeId = await sessionManager.initSession(sessionId, directory);
    await setSnapshotHistory(sessionId, [changeId]);
    return changeId;
  } catch (error) {
    console.error(`Failed to initialize snapshot for session ${sessionId}:`, error);
    await setSnapshotHistory(sessionId, []);
    return null;
  }
}

/**
 * Capture the current file state for a session.
 *
 * @param sessionId - The session to track
 * @param description - Optional description for the snapshot
 * @returns The snapshot change ID, or null if tracking failed
 */
export async function trackSnapshot(
  sessionId: string,
  description?: string
): Promise<string | null> {
  try {
    const changeId = await sessionManager.trackSnapshot(sessionId, description);
    if (changeId) {
      await appendSnapshotHistoryToDB(sessionId, changeId);
    }
    return changeId;
  } catch (error) {
    console.error(`Failed to track snapshot for session ${sessionId}:`, error);
    return null;
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
  try {
    return await sessionManager.computeDiff(sessionId, fromChangeId, toChangeId);
  } catch (error) {
    console.warn(
      `Failed to compute diff for session ${sessionId} (from: ${fromChangeId}, to: ${toChangeId}):`,
      error
    );
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
  const snapshot = sessionManager.getSession(sessionId);
  if (!snapshot) {
    return [];
  }

  try {
    return await snapshot.patch(fromChangeId, toChangeId);
  } catch (error) {
    console.warn(
      `Failed to get changed files for session ${sessionId} (from: ${fromChangeId}):`,
      error
    );
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
export function getSnapshotHistory(sessionId: string): string[] {
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
  sessionManager.cleanupSession(sessionId);
  sessionSnapshots.delete(sessionId);
  // Database cleanup is handled by foreign key cascades when session is deleted
}

/**
 * Get the snapshot instance for a session.
 *
 * @param sessionId - The session to get snapshot for
 * @returns The Snapshot instance, or null if not found
 */
export function getSessionSnapshot(sessionId: string): Snapshot | null {
  return sessionManager.getSession(sessionId);
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
 * @returns The file contents, or null if not found
 */
export async function getFileAtSnapshot(
  sessionId: string,
  changeId: string,
  filePath: string
): Promise<string | null> {
  const snapshot = sessionManager.getSession(sessionId);
  if (!snapshot) {
    return null;
  }

  return snapshot.getFileAt(changeId, filePath);
}

/**
 * Undo the last jj operation for a session.
 *
 * @param sessionId - The session to undo in
 */
export async function undoLastOperation(sessionId: string): Promise<void> {
  const snapshot = sessionManager.getSession(sessionId);
  if (!snapshot) {
    throw new NotFoundError('session snapshot', sessionId);
  }

  await snapshot.undo();
}
